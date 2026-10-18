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
end)

RegisterNetEvent("nyx:judiciary:client:evidenceRemoved", function(evidenceId)
    LocalEvidence[evidenceId] = nil
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

-- 2. Proximity Evidence Marker & Collection Thread (Zero Wait(0) unless in close proximity < 2.5m)
CreateThread(function()
    while true do
        local sleep = 1000
        local ped = PlayerPedId()

        if DoesEntityExist(ped) and not IsPedDeadOrDying(ped, true) then
            local pCoords = GetEntityCoords(ped)
            local nearestEvidence = nil
            local nearestDist = 999.0

            for id, data in pairs(LocalEvidence) do
                local d = #(pCoords - data.coords)
                if d < (Config.Forensics and Config.Forensics.DetectionRadius or 15.0) then
                    if d < nearestDist then
                        nearestDist = d
                        nearestEvidence = data
                    end
                end
            end

            if nearestEvidence then
                if nearestDist < 10.0 then
                    sleep = 0

                    -- Render localized forensic clue ring
                    local c = nearestEvidence.coords
                    DrawMarker(1, c.x, c.y, c.z - 0.95, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.35, 0.35, 0.15, 200, 180, 50, 180, false, false, 2, false, nil, nil, false)

                    if nearestDist <= (Config.Forensics and Config.Forensics.MaxCollectionDistance or 2.5) then
                        -- Display 3D interaction text
                        BeginTextCommandDisplayText("STRING")
                        local prompt = string.format("[~g~E~w~] Bag Evidence (Gloves) | [~r~G~w~] Pick Up (Bare Hands)\n~y~Type:~w~ %s", nearestEvidence.type:upper())
                        AddTextComponentSubstringPlayerName(prompt)
                        SetTextFont(0)
                        SetTextScale(0.32, 0.32)
                        SetTextColour(255, 255, 255, 230)
                        SetTextCentre(true)

                        SetDrawOrigin(c.x, c.y, c.z + 0.25, 0)
                        EndTextCommandDisplayText(0.0, 0.0)
                        ClearDrawOrigin()

                        -- Handle key inputs
                        if IsControlJustPressed(0, 38) then -- E key: With Gloves
                            if exports['nyx_core'] and exports['nyx_core'].TriggerServerRPC then
                                exports['nyx_core']:TriggerServerRPC("judiciary:collectEvidence", nearestEvidence.evidenceId, true)
                            end
                            Wait(500)
                        elseif IsControlJustPressed(0, 47) then -- G key: Bare Hands (Contaminated)
                            if exports['nyx_core'] and exports['nyx_core'].TriggerServerRPC then
                                exports['nyx_core']:TriggerServerRPC("judiciary:collectEvidence", nearestEvidence.evidenceId, false)
                            end
                            Wait(500)
                        end
                    end
                else
                    sleep = 250
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
