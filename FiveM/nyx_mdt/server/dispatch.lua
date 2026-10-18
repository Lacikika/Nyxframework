--[[
    Nyxframework: nyx_mdt
    File: server/dispatch.lua
    Description: Zero-polling emergency dispatch feed (911/CAD),
                 server push notifications, and incident assignment.
]]

Nyx = Nyx or {}
Nyx.MDT = Nyx.MDT or {}

-- 1. Create a new emergency dispatch call and push to on-duty units
function Nyx.MDT.CreateCall(code, title, description, caller, coords, locationLabel, priority)
    code = code or "10-99"
    title = title or "Segélyhívás"
    caller = caller or "Anonymus"
    coords = coords or { x = 0.0, y = 0.0, z = 0.0 }
    locationLabel = locationLabel or "Ismeretlen helyszín"
    priority = priority or "medium"

    local callId = MySQL.insert.await([[
        INSERT INTO `nyx_mdt_calls`
            (`code`, `title`, `description`, `caller`, `coords`, `location_label`, `priority`, `status`)
        VALUES (?, ?, ?, ?, ?, ?, ?, 'active')
    ]], {
        code,
        title,
        description,
        caller,
        json.encode(coords),
        locationLabel,
        priority
    })

    if not callId then return nil end

    local callData = {
        id = callId,
        code = code,
        title = title,
        description = description,
        caller = caller,
        coords = coords,
        location = locationLabel,
        priority = priority,
        status = "active",
        assignedUnit = nil,
        time = os.date("%H:%M", math.floor(os.time()))
    }

    Nyx.MDT.ActiveCalls[callId] = callData

    -- Push event to all on-duty units (Zero client polling!)
    for _, src in ipairs(GetPlayers()) do
        if Nyx.MDT.IsAuthorized(tonumber(src)) then
            TriggerClientEvent("nyx:mdt:client:newCall", src, callData)
        end
    end

    if Config.Debug then
        print(string.format("^3[Nyx:MDT] New 911 Call #%d: [%s] %s @ %s^7", callId, code, title, locationLabel))
    end

    return callId
end

-- 2. Command / Trigger for Citizen 911 Calls
RegisterCommand("911", function(source, args)
    if source == 0 then return end
    local player = exports['nyx_core']:GetPlayer(source)
    if not player then return end

    local message = table.concat(args, " ")
    if #message < 3 then
        TriggerClientEvent("nyx:ui:notify", source, {
            type = "warning",
            title = "911 SEGÉLYHÍVÓ",
            message = "Kérlek add meg a segélyhívás okát! (pl. /911 Fegyveres rablás a Davis LTD-nél)"
        })
        return
    end

    local ped = GetPlayerPed(tostring(source))
    local pCoords = GetEntityCoords(ped)
    local coordsTable = { x = pCoords.x, y = pCoords.y, z = pCoords.z }

    local callId = Nyx.MDT.CreateCall(
        "10-99",
        "Polgári Segélyhívás (911)",
        message,
        string.format("%s (%s)", player.name or "Állampolgár", player.citizenId),
        coordsTable,
        "Los Santos Területe",
        "high"
    )

    if callId then
        TriggerClientEvent("nyx:ui:notify", source, {
            type = "success",
            title = "911 RÖGZÍTVE",
            message = "A diszpécser rögzítette a hívásodat. A legközelebbi egység riasztásra került."
        })
    end
end, false)

-- 3. RPC: Respond to Call (Sets unit assignment and returns GPS coordinates)
exports['nyx_core']:RegisterRPC("mdt:respondCall", function(src, callId)
    if not Nyx.MDT.IsAuthorized(src) then
        return { success = false, error = "UNAUTHORIZED" }
    end

    callId = tonumber(callId)
    local call = Nyx.MDT.ActiveCalls[callId]
    if not call then
        return { success = false, error = "CALL_NOT_FOUND" }
    end

    local player = exports['nyx_core']:GetPlayer(src)
    local callsign = player and (player.callsign or player.name) or "UNIT-1"

    call.status = "assigned"
    call.assignedUnit = callsign

    MySQL.prepare([[
        UPDATE `nyx_mdt_calls` SET `status` = 'assigned', `assigned_unit` = ? WHERE `call_id` = ?
    ]], { callsign, callId })

    -- Broadcast update
    for _, officerSrc in ipairs(GetPlayers()) do
        if Nyx.MDT.IsAuthorized(tonumber(officerSrc)) then
            TriggerClientEvent("nyx:mdt:client:updateCall", officerSrc, call)
        end
    end

    return {
        success = true,
        callId = callId,
        coords = call.coords,
        location = call.location
    }
end)

-- 4. RPC: Close Call
exports['nyx_core']:RegisterRPC("mdt:closeCall", function(src, callId)
    if not Nyx.MDT.IsAuthorized(src) then
        return { success = false, error = "UNAUTHORIZED" }
    end

    callId = tonumber(callId)
    Nyx.MDT.ActiveCalls[callId] = nil

    MySQL.prepare([[
        UPDATE `nyx_mdt_calls` SET `status` = 'closed', `closed_at` = NOW() WHERE `call_id` = ?
    ]], { callId })

    for _, officerSrc in ipairs(GetPlayers()) do
        if Nyx.MDT.IsAuthorized(tonumber(officerSrc)) then
            TriggerClientEvent("nyx:mdt:client:closeCall", officerSrc, callId)
        end
    end

    return { success = true, callId = callId }
end)

-- ----------------------------------------------------------------------------
-- 5. Traffic Radar Zones & Real-Time Dispatch Warning Overlays Subsystem
-- ----------------------------------------------------------------------------
Nyx.MDT.ActiveWarnings = Nyx.MDT.ActiveWarnings or {}
Nyx.MDT.RadarZones = Nyx.MDT.RadarZones or {}

-- Hydrate Traffic Radar Monitoring Zones
function Nyx.MDT.HydrateRadarZones()
    local rows = MySQL.query.await("SELECT * FROM `nyx_mdt_traffic_radar_zones` WHERE `is_active` = 1")
    Nyx.MDT.RadarZones = {}
    if rows then
        for _, r in ipairs(rows) do
            local coords = { x = 0.0, y = 0.0, z = 0.0 }
            if type(r.coords) == "string" then
                local ok, parsed = pcall(json.decode, r.coords)
                if ok and type(parsed) == "table" then coords = parsed end
            elseif type(r.coords) == "table" then
                coords = r.coords
            end

            Nyx.MDT.RadarZones[r.zone_id] = {
                id = r.zone_id,
                name = r.zone_name,
                zoneType = r.zone_type,
                coords = coords,
                radius = tonumber(r.radius) or 120.0
            }
        end
        if Config.Debug then
            print(string.format("^2[Nyx:MDT] Hydrated %d traffic radar ANPR zones.^7", #rows))
        end
    end
end

CreateThread(function()
    while GetResourceState("oxmysql") ~= "started" do
        Wait(50)
    end
    Nyx.MDT.HydrateRadarZones()
end)

-- Create a new real-time dispatch warning overlay and push to all active officers
function Nyx.MDT.CreateDispatchWarning(payload)
    if not payload then return nil end

    local warningUuid = payload.warningUuid or string.format("wrn-%s-%d", payload.category or "alert", os.time())
    local category = payload.category or "speeding_anpr"
    local severity = payload.severity or "medium"
    local title = payload.title or "MDT Figyelmeztető Riasztás"
    local description = payload.description or ""
    local locationLabel = payload.locationLabel or "San Andreas Területe"
    local coords = payload.coords or { x = 0.0, y = 0.0, z = 0.0 }
    local plate = payload.targetPlate
    local model = payload.targetModel
    local speedRec = payload.speedRecordedMph
    local speedLim = payload.speedLimitMph
    local targetCitId = payload.targetCitizenId

    local warningId = MySQL.insert.await([[
        INSERT INTO `nyx_mdt_dispatch_warnings`
            (`warning_uuid`, `category`, `severity`, `title`, `description`, `location_label`, `coords`,
             `target_plate`, `target_model`, `speed_recorded_mph`, `speed_limit_mph`, `target_citizen_id`, `status`)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'active')
    ]], {
        warningUuid,
        category,
        severity,
        title,
        description,
        locationLabel,
        json.encode(coords),
        plate,
        model,
        speedRec,
        speedLim,
        targetCitId
    })

    if not warningId then return nil end

    local warningData = {
        id = warningId,
        warningUuid = warningUuid,
        category = category,
        severity = severity,
        title = title,
        description = description,
        location = locationLabel,
        coords = coords,
        plate = plate,
        model = model,
        speedRecorded = speedRec,
        speedLimit = speedLim,
        targetCitizenId = targetCitId,
        status = "active",
        createdAt = os.date("%H:%M:%S", math.floor(os.time()))
    }

    Nyx.MDT.ActiveWarnings[warningId] = warningData

    -- Push event to all on-duty units (Zero client polling!)
    for _, src in ipairs(GetPlayers()) do
        if Nyx.MDT.IsAuthorized(tonumber(src)) then
            TriggerClientEvent("nyx:mdt:client:dispatchWarning", src, warningData)
        end
    end

    if Config.Debug then
        print(string.format("^1[Nyx:MDT] DISPATCH WARNING #%d [%s/%s]: %s @ %s^7",
            warningId, category, severity, title, locationLabel))
    end

    return warningId
end

-- Process an ANPR / Speed Radar Detection Event
function Nyx.MDT.RecordRadarDetection(plate, model, speedMph, coords, citizenId)
    speedMph = tonumber(speedMph) or 0.0
    coords = coords or { x = 0.0, y = 0.0, z = 0.0 }

    -- Resolve Radar Zone
    local matchedZone = nil
    for _, z in pairs(Nyx.MDT.RadarZones) do
        local inZone = false
        if exports['nyx_parliament'] and exports['nyx_parliament'].IsPointInRadarZone then
            inZone = exports['nyx_parliament']:IsPointInRadarZone(coords, z.coords, z.radius)
        elseif Nyx.StatutoryEnforcement and Nyx.StatutoryEnforcement.IsPointInRadarZone then
            inZone = Nyx.StatutoryEnforcement.IsPointInRadarZone(coords, z.coords, z.radius)
        else
            local dx = (coords.x or 0.0) - (z.coords.x or 0.0)
            local dy = (coords.y or 0.0) - (z.coords.y or 0.0)
            inZone = (math.sqrt((dx * dx) + (dy * dy)) <= z.radius)
        end

        if inZone then
            matchedZone = z
            break
        end
    end

    local zoneType = matchedZone and matchedZone.zoneType or "urban"
    local zoneName = matchedZone and matchedZone.name or "Los Santos Közterület"

    local eval
    if exports['nyx_parliament'] and exports['nyx_parliament'].EvaluateSpeeding then
        eval = exports['nyx_parliament']:EvaluateSpeeding(speedMph, zoneType)
    elseif Nyx.StatutoryEnforcement and Nyx.StatutoryEnforcement.EvaluateSpeeding then
        eval = Nyx.StatutoryEnforcement.EvaluateSpeeding(speedMph, zoneType, GlobalState.parliamentLaws)
    else
        local limit = 45.0
        eval = {
            isViolation = (speedMph > limit + 5.0),
            tier = (speedMph > limit + 30.0) and 3 or ((speedMph > limit + 15.0) and 2 or 1),
            speedLimitMph = limit,
            deltaMph = speedMph - limit,
            tierLabel = "Sebességtúllépés",
            recommendedFine = 500.0,
            sentenceMonths = 0,
            severity = (speedMph > limit + 30.0) and "critical" or "medium",
            impoundRecommended = (speedMph > limit + 30.0),
            triggerDispatchWarning = (speedMph > limit + 5.0)
        }
    end

    if not eval.isViolation or not eval.triggerDispatchWarning then
        return { isViolation = false, violation = eval }
    end

    local cleanPlate = tostring(plate or "ISMERETLEN"):upper()
    local cleanModel = tostring(model or "Jármű")
    local category = (eval.tier == 3) and "reckless_endangerment" or "speeding_anpr"
    local severity = (eval.tier == 3) and "critical" or ((eval.tier == 2) and "high" or "medium")

    local title = string.format("TRAFFIPAX [%s]: %s (%.1f / %.1f mph)",
        string.upper(eval.tierCode or "SPEED"), zoneName, speedMph, eval.speedLimitMph)

    local desc = string.format("Rendszám: %s (%s) | +%.1f mph túllépés (%s) | Javasolt bírság: $%.2f%s",
        cleanPlate, cleanModel, eval.deltaMph, eval.tierLabel, eval.recommendedFine,
        eval.impoundRecommended and " | LEFOGLALÁS JAVASOLT" or "")

    local warningId = Nyx.MDT.CreateDispatchWarning({
        category = category,
        severity = severity,
        title = title,
        description = desc,
        locationLabel = zoneName,
        coords = coords,
        targetPlate = cleanPlate,
        targetModel = cleanModel,
        speedRecordedMph = speedMph,
        speedLimitMph = eval.speedLimitMph,
        targetCitizenId = citizenId
    })

    return {
        isViolation = true,
        warningId = warningId,
        violation = eval
    }
end

-- Network Listener: Client/Radar Reporting
RegisterNetEvent("nyx:mdt:server:reportRadarDetection", function(payload)
    local src = source
    if type(payload) ~= "table" then return end
    Nyx.MDT.RecordRadarDetection(
        payload.plate,
        payload.model,
        payload.speedMph,
        payload.coords,
        payload.citizenId
    )
end)

-- RPC: Query Active Dispatch Warning Overlays
exports['nyx_core']:RegisterRPC("mdt:getDispatchWarnings", function(src)
    if not Nyx.MDT.IsAuthorized(src) then
        return { success = false, error = "UNAUTHORIZED" }
    end

    local warningsList = {}
    for _, w in pairs(Nyx.MDT.ActiveWarnings) do
        warningsList[#warningsList + 1] = w
    end
    table.sort(warningsList, function(a, b) return a.id > b.id end)

    return {
        success = true,
        warnings = warningsList
    }
end)

-- RPC: Acknowledge Dispatch Warning
exports['nyx_core']:RegisterRPC("mdt:acknowledgeDispatchWarning", function(src, warningId)
    if not Nyx.MDT.IsAuthorized(src) then
        return { success = false, error = "UNAUTHORIZED" }
    end

    warningId = tonumber(warningId)
    local warn = Nyx.MDT.ActiveWarnings[warningId]
    if not warn then
        return { success = false, error = "WARNING_NOT_FOUND" }
    end

    local officer = exports['nyx_core']:GetPlayer(src)
    local citId = officer and officer.citizenId or "OFFICER"

    warn.status = "acknowledged"
    warn.acknowledgedBy = citId

    MySQL.prepare([[
        UPDATE `nyx_mdt_dispatch_warnings`
        SET `status` = 'acknowledged', `acknowledged_by` = ?, `acknowledged_at` = NOW()
        WHERE `warning_id` = ?
    ]], { citId, warningId })

    for _, officerSrc in ipairs(GetPlayers()) do
        if Nyx.MDT.IsAuthorized(tonumber(officerSrc)) then
            TriggerClientEvent("nyx:mdt:client:updateWarning", officerSrc, warn)
        end
    end

    return { success = true, warningId = warningId }
end)

-- RPC: Clear / Resolve Dispatch Warning
exports['nyx_core']:RegisterRPC("mdt:clearDispatchWarning", function(src, warningId)
    if not Nyx.MDT.IsAuthorized(src) then
        return { success = false, error = "UNAUTHORIZED" }
    end

    warningId = tonumber(warningId)
    Nyx.MDT.ActiveWarnings[warningId] = nil

    MySQL.prepare([[
        UPDATE `nyx_mdt_dispatch_warnings`
        SET `status` = 'cleared'
        WHERE `warning_id` = ?
    ]], { warningId })

    for _, officerSrc in ipairs(GetPlayers()) do
        if Nyx.MDT.IsAuthorized(tonumber(officerSrc)) then
            TriggerClientEvent("nyx:mdt:client:clearWarning", officerSrc, warningId)
        end
    end

    return { success = true, warningId = warningId }
end)

-- RPC: Query Radar Zones
exports['nyx_core']:RegisterRPC("mdt:getRadarZones", function(src)
    return {
        success = true,
        zones = Nyx.MDT.RadarZones
    }
end)

-- RPC: Manual Radar Violation Evaluation Test
exports['nyx_core']:RegisterRPC("mdt:recordRadarDetection", function(src, payload)
    if not Nyx.MDT.IsAuthorized(src) then
        return { success = false, error = "UNAUTHORIZED" }
    end
    if type(payload) ~= "table" then
        return { success = false, error = "INVALID_PAYLOAD" }
    end

    local res = Nyx.MDT.RecordRadarDetection(
        payload.plate,
        payload.model,
        payload.speedMph,
        payload.coords,
        payload.citizenId
    )
    return { success = true, result = res }
end)
