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
