--[[
    Nyxframework: nyx_logistics
    File: server/nodes.lua
    Description: Finite extraction engine, reserve depletion, tool validation, and replenishment ticks.
]]

Nyx = Nyx or {}
Nyx.Logistics = Nyx.Logistics or {}
Nyx.Logistics.ActiveNodes = {} -- [nodeId] = nodeState

-- Load nodes into memory cache on boot
CreateThread(function()
    while GetResourceState("oxmysql") ~= "started" do
        Wait(50)
    end

    local rows = MySQL.query.await("SELECT * FROM `nyx_logistics_nodes`")
    if rows then
        for _, row in ipairs(rows) do
            local coords = nil
            if row.coords then
                local ok, parsed = pcall(json.decode, row.coords)
                if ok and parsed then coords = parsed end
            end

            Nyx.Logistics.ActiveNodes[row.node_id] = {
                id = row.node_id,
                resource_item = row.resource_item,
                current_reserve = tonumber(row.current_reserve) or 0,
                max_reserve = tonumber(row.max_reserve) or 500,
                regen_rate_per_hour = tonumber(row.regen_rate_per_hour) or 50,
                coords = coords or { x = 0, y = 0, z = 0 },
                last_harvested = os.time()
            }
        end
        print(string.format("^2[Nyx:Logistics] Loaded %d finite natural resource extraction nodes.^7", #rows))
    end
end)

-- Authoritative Node Harvesting RPC
Nyx.RPC.Register("logistics:harvestNode", function(src, nodeId, toolSlot)
    local player = exports['nyx_core']:GetPlayer(src)
    if not player then return { success = false, error = "UNAUTHORIZED" } end

    local node = Nyx.Logistics.ActiveNodes[nodeId]
    if not node then
        return { success = false, error = "NODE_NOT_FOUND" }
    end

    -- 1. Distance & Line of Sight Validation
    local ped = GetPlayerPed(tostring(src))
    local playerCoords = GetEntityCoords(ped)
    local nodeVec = vector3(node.coords.x, node.coords.y, node.coords.z)
    local dist = #(playerCoords - nodeVec)

    if dist > (Config.HarvestInteractDistance or 3.0) then
        return { success = false, error = "OUT_OF_RANGE" }
    end

    -- 2. Finite Reserve Depletion Check
    if node.current_reserve <= 0 then
        return { success = false, error = "NODE_DEPLETED" }
    end

    -- 3. Player Inventory & Capacity Validation
    local playerInvId = string.format("char:%s:main", player.citizenId)
    local yieldAmount = math.min(Config.HarvestAmountPerAction or 3, node.current_reserve)

    local itemWeight = exports['nyx_inventory']:GetInventory(playerInvId)
    if itemWeight and not itemWeight:canHoldWeight(yieldAmount * 1000) then
        return { success = false, error = "INVENTORY_OVERWEIGHT" }
    end

    -- 4. Mutex / Atomic Reserve Deduction
    node.current_reserve = node.current_reserve - yieldAmount
    node.last_harvested = os.time()

    MySQL.prepare([[
        UPDATE `nyx_logistics_nodes` 
        SET `current_reserve` = ?, `last_harvested_at` = CURRENT_TIMESTAMP 
        WHERE `node_id` = ?
    ]], { node.current_reserve, nodeId })

    -- 5. Allocate Dynamic Metadata and Grant Raw Materials
    local metadata = {
        sourceNode = nodeId,
        originBatch = Nyx.RPC.GenerateNonce():sub(1, 8),
        harvestedAt = os.time(),
        purity = math.random(85, 99) / 100.0
    }

    local okAdd, err = exports['nyx_inventory']:AddItem(playerInvId, node.resource_item, yieldAmount, metadata)
    if not okAdd then
        -- Refund reserve if inventory addition failed
        node.current_reserve = node.current_reserve + yieldAmount
        return { success = false, error = err or "INVENTORY_ADD_FAILED" }
    end

    -- Stream updated reserve to nearby observers
    TriggerClientEvent("nyx:logistics:client:nodeUpdated", -1, nodeId, node.current_reserve, node.max_reserve)

    return {
        success = true,
        yielded = yieldAmount,
        remaining = node.current_reserve
    }
end)

-- Periodic Reserve Regeneration Routine
function Nyx.Logistics.ProcessRegenerationTick()
    local now = os.time()
    local regeneratedCount = 0

    for nodeId, node in pairs(Nyx.Logistics.ActiveNodes) do
        if node.current_reserve < node.max_reserve then
            local elapsedHours = (now - node.last_harvested) / 3600.0
            if elapsedHours >= 0.10 then
                local recovered = math.floor(elapsedHours * node.regen_rate_per_hour)
                if recovered > 0 then
                    node.current_reserve = math.min(node.max_reserve, node.current_reserve + recovered)
                    node.last_harvested = now
                    regeneratedCount = regeneratedCount + 1

                    MySQL.prepare([[
                        UPDATE `nyx_logistics_nodes` 
                        SET `current_reserve` = ?, `last_harvested_at` = CURRENT_TIMESTAMP 
                        WHERE `node_id` = ?
                    ]], { node.current_reserve, nodeId })

                    TriggerClientEvent("nyx:logistics:client:nodeUpdated", -1, nodeId, node.current_reserve, node.max_reserve)
                end
            end
        end
    end

    if Config.Debug and regeneratedCount > 0 then
        print(string.format("^2[Nyx:Logistics] Regenerated reserves across %d extraction nodes.^7", regeneratedCount))
    end
end

-- Regeneration Tick Thread
CreateThread(function()
    local intervalMs = (Config.HarvestRegenInterval or 900) * 1000
    while true do
        Wait(intervalMs)
        Nyx.Logistics.ProcessRegenerationTick()
    end
end)
