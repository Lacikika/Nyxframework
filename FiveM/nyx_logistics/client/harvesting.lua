--[[
    Nyxframework: nyx_logistics
    File: client/harvesting.lua
    Description: Spatial harvesting node Third-Eye (LALT) target registration,
                 gathering animations, and zero-busywait interaction dispatching.
]]

Nyx = Nyx or {}
Nyx.Logistics = Nyx.Logistics or {}
Nyx.Logistics.IsHarvesting = false

-- Register Natural Resource Extraction Nodes with Third-Eye (LALT) Raycast Engine
CreateThread(function()
    while not exports['nyx_interact'] do
        Wait(200)
    end

    local interactDist = Config.HarvestInteractDistance or 3.0

    for nodeId, node in pairs(Nyx.Logistics.Nodes.Registry or {}) do
        exports['nyx_interact']:AddTargetCoords("logistics_harvest_" .. nodeId, node.coords, interactDist, {
            options = {
                {
                    icon = "fa-solid fa-gem",
                    label = "Extract " .. (node.label or "Resources"),
                    event = "nyx:logistics:client:harvestNode",
                    args = { nodeId = nodeId },
                    canInteract = function(entity, dist)
                        return dist <= interactDist and not Nyx.Logistics.IsHarvesting
                    end
                }
            },
            distance = interactDist
        })
    end
end)

-- Event hook for node extraction
RegisterNetEvent("nyx:logistics:client:harvestNode", function(args)
    local nodeId = (type(args) == "table" and args.nodeId) or args
    local node = nodeId and Nyx.Logistics.Nodes.Registry[nodeId]
    if node and not Nyx.Logistics.IsHarvesting then
        Nyx.Logistics.StartHarvesting(nodeId, node)
    end
end)

-- Relaxed visual beacon thread (Sleeps 1000ms, zero Wait(0) busy-wait)
CreateThread(function()
    while true do
        local sleep = 1000
        local ped = PlayerPedId()
        local playerCoords = GetEntityCoords(ped)

        for nodeId, node in pairs(Nyx.Logistics.Nodes.Registry or {}) do
            local dist = #(playerCoords - node.coords)
            if dist <= 20.0 then
                sleep = 250
                DrawMarker(1, node.coords.x, node.coords.y, node.coords.z - 1.0,
                    0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
                    1.5, 1.5, 0.8, 205, 133, 63, 140,
                    false, false, 2, false, nil, nil, false
                )
            end
        end

        Wait(sleep)
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
    local reg = Nyx.Logistics.Nodes.Registry and Nyx.Logistics.Nodes.Registry[nodeId]
    if reg then
        reg.currentReserve = currentReserve
    end
end)
