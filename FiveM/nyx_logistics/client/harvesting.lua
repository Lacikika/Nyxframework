--[[
    Nyxframework: nyx_logistics
    File: client/harvesting.lua
    Description: Client spatial node detection, 3D markers, gathering animations, and RPC invocation.
]]

Nyx = Nyx or {}
Nyx.Logistics = Nyx.Logistics or {}
Nyx.Logistics.IsHarvesting = false

-- Proximity loop for natural extraction points
CreateThread(function()
    while true do
        local ped = PlayerPedId()
        local playerCoords = GetEntityCoords(ped)
        local nearNode = false
        local interactDist = Config.HarvestInteractDistance or 3.0

        for nodeId, node in pairs(Nyx.Logistics.Nodes.Registry) do
            local dist = #(playerCoords - node.coords)

            if dist <= 20.0 then
                -- Render 3D gathering beacon marker
                DrawMarker(1, node.coords.x, node.coords.y, node.coords.z - 1.0,
                    0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
                    1.5, 1.5, 0.8, 205, 133, 63, 160,
                    false, false, 2, false, nil, nil, false
                )

                if dist <= interactDist then
                    nearNode = true
                    if not Nyx.Logistics.IsHarvesting then
                        BeginTextCommandDisplayHelp("STRING")
                        AddTextComponentSubstringPlayerName(string.format("Press ~INPUT_CONTEXT~ to extract ~y~%s~s~", node.label))
                        EndTextCommandDisplayHelp(0, false, true, -1)

                        if IsControlJustPressed(0, 38) then -- INPUT_CONTEXT (E)
                            Nyx.Logistics.StartHarvesting(nodeId, node)
                        end
                    end
                end
            end
        end

        if nearNode or Nyx.Logistics.IsHarvesting then
            Wait(0)
        else
            Wait(500)
        end
    end
end)

-- Execute Harvesting Animation & Server RPC Handshake
function Nyx.Logistics.StartHarvesting(nodeId, node)
    local ped = PlayerPedId()
    Nyx.Logistics.IsHarvesting = true

    -- Load animation dictionary if specified
    local animDict = (node.anim and node.anim.dict) or "amb@world_human_hammering@male@base"
    local animName = (node.anim and node.anim.name) or "base"

    RequestAnimDict(animDict)
    while not HasAnimDictLoaded(animDict) do
        Wait(50)
    end

    TaskPlayAnim(ped, animDict, animName, 8.0, -8.0, 4000, 1, 0, false, false, false)

    -- 4-second harvesting progress
    Wait(4000)
    ClearPedTasks(ped)

    CreateThread(function()
        local result = exports['nyx_core']:TriggerRPCAwait("logistics:harvestNode", nodeId, nil)
        Nyx.Logistics.IsHarvesting = false

        if result and result.success then
            TriggerEvent("nyx:core:client:notify",
                string.format("Harvested %dx raw resources! (Remaining: %d)", result.yielded, result.remaining),
                "success"
            )
        else
            local err = (result and result.error) or "EXTRACTION_FAILED"
            TriggerEvent("nyx:core:client:notify",
                string.format("Extraction failed: %s", err),
                "error"
            )
        end
    end)
end

-- Real-time Node Reserve Update Broadcast Listener
RegisterNetEvent("nyx:logistics:client:nodeUpdated", function(nodeId, currentReserve, maxReserve)
    local reg = Nyx.Logistics.Nodes.Registry[nodeId]
    if reg then
        reg.currentReserve = currentReserve
    end
end)
