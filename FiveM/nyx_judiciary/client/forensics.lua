--[[
    Nyxframework: nyx_judiciary
    File: client/forensics.lua
    Description: Client forensic detection, weapon discharge telemetry, localized clue streaming,
                 and proximity collection interactions.
]]

local LocalEvidence = {}
local isForensicActive = false

-- Listen for server evidence streams
RegisterNetEvent("nyx:judiciary:client:evidenceCreated", function(drop)
    if not drop or not drop.evidenceId then return end
    LocalEvidence[drop.evidenceId] = {
        evidenceId = drop.evidenceId,
        type = drop.type or "casing",
        coords = vector3(drop.coords.x, drop.coords.y, drop.coords.z)
    }

    if exports['nyx_interact'] and exports['nyx_interact'].AddTargetCoords then
        exports['nyx_interact']:AddTargetCoords("evidence_" .. drop.evidenceId, drop.coords, 2.5, {
            options = {
                {
                    icon = "fa-solid fa-box-archive",
                    label = "Bag Evidence (Gloves): " .. string.upper(drop.type or "casing"),
                    event = "nyx:judiciary:client:collectEvidenceGloves",
                    args = { evidenceId = drop.evidenceId },
                    canInteract = function(entity, dist)
                        return dist <= 2.5
                    end
                },
                {
                    icon = "fa-solid fa-hand",
                    label = "Pick Up (Bare Hands): " .. string.upper(drop.type or "casing"),
                    event = "nyx:judiciary:client:collectEvidenceBare",
                    args = { evidenceId = drop.evidenceId },
                    canInteract = function(entity, dist)
                        return dist <= 2.5
                    end
                }
            },
            distance = 2.5
        })
    end
end)

RegisterNetEvent("nyx:judiciary:client:evidenceRemoved", function(evidenceId)
    LocalEvidence[evidenceId] = nil
    if exports['nyx_interact'] and exports['nyx_interact'].RemoveTargetCoords then
        exports['nyx_interact']:RemoveTargetCoords("evidence_" .. evidenceId)
    end
end)

-- Event handlers for Third-Eye forensic evidence collection
RegisterNetEvent("nyx:judiciary:client:collectEvidenceGloves", function(args)
    local evidenceId = (type(args) == "table" and args.evidenceId) or args
    if evidenceId and exports['nyx_core'] and exports['nyx_core'].TriggerServerRPC then
        exports['nyx_core']:TriggerServerRPC("judiciary:collectEvidence", evidenceId, true)
    end
end)

RegisterNetEvent("nyx:judiciary:client:collectEvidenceBare", function(args)
    local evidenceId = (type(args) == "table" and args.evidenceId) or args
    if evidenceId and exports['nyx_core'] and exports['nyx_core'].TriggerServerRPC then
        exports['nyx_core']:TriggerServerRPC("judiciary:collectEvidence", evidenceId, false)
    end
end)

-- 1. Weapon Discharge Detection Loop (Tick rate adaptive: 100ms when armed, 1000ms when unarmed)
CreateThread(function()
    while true do
        local ped = PlayerPedId()
        local sleep = 1000

        if DoesEntityExist(ped) and not IsPedDeadOrDying(ped, true) then
            local armed = IsPedArmed(ped, 4) -- 4 = firearm
            if armed then
                sleep = 50
                if IsPedShooting(ped) then
                    local weaponHash = GetSelectedPedWeapon(ped)
                    local muzzleCoords = GetPedBoneCoords(ped, 0x6F06, 0.0, 0.0, 0.0) -- Right hand / muzzle approximation
                    TriggerServerEvent("nyx:judiciary:server:weaponFired", weaponHash, muzzleCoords)
                    Wait(250) -- Debounce burst fire
                end
            end
        end

        Wait(sleep)
    end
end)

-- 2. Relaxed Forensic Clue Ring Visual Thread (Sleeps 250-1000ms, zero Wait(0) busy-wait)
CreateThread(function()
    while true do
        local sleep = 1000
        local ped = PlayerPedId()

        if DoesEntityExist(ped) and not IsPedDeadOrDying(ped, true) then
            local pCoords = GetEntityCoords(ped)

            for id, data in pairs(LocalEvidence) do
                local d = #(pCoords - data.coords)
                if d < (Config.Forensics and Config.Forensics.DetectionRadius or 15.0) then
                    sleep = 250
                    local c = data.coords
                    DrawMarker(1, c.x, c.y, c.z - 0.95, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.35, 0.35, 0.15, 200, 180, 50, 140, false, false, 2, false, nil, nil, false)
                end
            end
        end

        Wait(sleep)
    end
end)

-- Public getter for active forensic mode
function IsForensicActive()
    return isForensicActive
end

-- 3. Forensic Swab Collection (GSR, DNA, Chemical)
function PerformForensicSwab(targetServerId, swabType)
    swabType = swabType or "gsr"
    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)

    -- Play swab animation
    local dict = "mp_arresting"
    RequestAnimDict(dict)
    local timeout = 0
    while not HasAnimDictLoaded(dict) and timeout < 20 do
        Wait(50)
        timeout = timeout + 1
    end

    TaskPlayAnim(ped, dict, "a_uncuff", 8.0, -8.0, 2500, 49, 0, false, false, false)
    Wait(2500)
    ClearPedTasks(ped)

    if exports['nyx_core'] and exports['nyx_core'].TriggerServerRPC then
        local res = exports['nyx_core']:TriggerServerRPC("judiciary:createSwabEvidence", {
            targetCitizenId = targetServerId and tostring(targetServerId) or "UNKNOWN",
            swabType = swabType,
            coords = { x = coords.x, y = coords.y, z = coords.z },
            isGSRPositive = true
        })
        return res
    end
    return false
end

-- 4. Digital Photographic / CCTV Surveillance Evidence
function CapturePhotoEvidence(cameraName, notes)
    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)

    -- Camera flash effect
    PlaySoundFrontend(-1, "Camera_Shoot", "Phone_Soundset_Franklin", true)

    local snapshotHash = string.format("EXIF-%d-%04d", GetGameTimer(), math.random(1000, 9999))
    if exports['nyx_core'] and exports['nyx_core'].TriggerServerRPC then
        local res = exports['nyx_core']:TriggerServerRPC("judiciary:createPhotoEvidence", {
            cameraLocation = cameraName or "PATROL_DASHCAM_01",
            snapshotHash = snapshotHash,
            coords = { x = coords.x, y = coords.y, z = coords.z },
            notes = notes or "Patrol photographic evidence"
        })
        return res
    end
    return false
end

-- 5. Chain of Custody Verification Query
function ClientVerifyChainOfCustody(evidenceId)
    if not evidenceId then return false end

    if exports['nyx_core'] and exports['nyx_core'].TriggerServerRPC then
        local res = exports['nyx_core']:TriggerServerRPC("judiciary:verifyChainOfCustody", evidenceId)
        return res
    end
    return false
end

-- Commands for Law Enforcement & Forensic Personnel
RegisterCommand("swab", function(source, args)
    local targetId = args[1] or "0"
    local swabType = args[2] or "gsr"
    TriggerEvent("chat:addMessage", {
        color = { 0, 180, 255 },
        multiline = true,
        args = { "Forensics", string.format("Collecting %s swab from subject %s...", swabType:upper(), targetId) }
    })
    PerformForensicSwab(targetId, swabType)
end, false)

RegisterCommand("photocctv", function(source, args)
    local cam = args[1] or "FIELD_CAMERA"
    local notes = table.concat(args, " ", 2)
    CapturePhotoEvidence(cam, notes)
    TriggerEvent("chat:addMessage", {
        color = { 0, 220, 100 },
        multiline = true,
        args = { "Forensics", string.format("Photographic snapshot captured and cryptographically sealed: %s", cam) }
    })
end, false)

RegisterCommand("verifychain", function(source, args)
    local evId = args[1]
    if not evId then
        TriggerEvent("chat:addMessage", {
            color = { 255, 100, 100 },
            multiline = true,
            args = { "Forensics", "Usage: /verifychain <evidenceId>" }
        })
        return
    end

    CreateThread(function()
        local res = ClientVerifyChainOfCustody(evId)
        if res and res.success then
            TriggerEvent("chat:addMessage", {
                color = { 50, 230, 50 },
                multiline = true,
                args = { "Forensics", string.format("Chain Integrity: [VALID] | Blocks: %d | Head: %s",
                    res.data.chainLength or 0, (res.data.currentChainHash or ""):sub(1, 12)) }
            })
        else
            TriggerEvent("chat:addMessage", {
                color = { 255, 50, 50 },
                multiline = true,
                args = { "Forensics", string.format("Chain Integrity: [COMPROMISED/FAILED] Status: %s", tostring(res and res.status or "ERROR")) }
            })
        end
    end)
end, false)
