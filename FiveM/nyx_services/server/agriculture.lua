--[[
    Nyxframework: nyx_services
    File: server/agriculture.lua
    Description: Authoritative server engine for natural crop harvest extraction,
                 soil fertility degradation/recovery, municipal food pantry stocking,
                 perishable food freshness simulation, and emergency food contracts.
]]

Nyx = Nyx or {}
Nyx.Services = Nyx.Services or {}
Nyx.Services.Farms = {}    -- [farmId] = farmState
Nyx.Services.Pantries = {} -- [pantryId] = pantryState

local function parseCoords(coordsVal)
    if type(coordsVal) == "table" then return coordsVal end
    if type(coordsVal) == "string" then
        local ok, parsed = pcall(json.decode, coordsVal)
        if ok and type(parsed) == "table" then return parsed end
    end
    return { x = 0.0, y = 0.0, z = 0.0 }
end

-- ----------------------------------------------------------------------------
-- 1. Bootloader & Hydration
-- ----------------------------------------------------------------------------

function Nyx.Services.LoadAgriculture()
    while GetResourceState("oxmysql") ~= "started" do
        Wait(50)
    end

    -- 1. Load Farmlands
    local farmRows = MySQL.query.await("SELECT * FROM `nyx_logistics_agriculture_farms`")
    if farmRows then
        for _, row in ipairs(farmRows) do
            local coords = parseCoords(row.coords)
            Nyx.Services.Farms[row.farm_id] = {
                id = row.farm_id,
                name = row.name,
                zone_id = row.zone_id,
                crop_type = row.crop_type,
                soil_fertility = tonumber(row.soil_fertility) or 100.00,
                irrigation_status = row.irrigation_status or "optimal",
                current_reserve = tonumber(row.current_reserve) or 600,
                max_reserve = tonumber(row.max_reserve) or 600,
                regen_rate_per_hour = tonumber(row.regen_rate_per_hour) or 60,
                coords = coords,
                last_harvested = os.time()
            }
        end
        print(string.format("^2[Nyx:Services] Loaded %d agricultural farmland nodes.^7", #farmRows))
    end

    -- 2. Load Municipal Emergency Food Pantries
    local pantryRows = MySQL.query.await("SELECT * FROM `nyx_services_food_pantries`")
    if pantryRows then
        for _, row in ipairs(pantryRows) do
            Nyx.Services.Pantries[row.pantry_id] = {
                id = row.pantry_id,
                name = row.name,
                zone_id = row.zone_id,
                stash_id = row.stash_id,
                target_rations = tonumber(row.target_rations) or 100,
                target_bread = tonumber(row.target_bread) or 50,
                status = row.status or "optimal",
                last_emergency_contract_at = row.last_emergency_contract_at,
                last_inspection = os.time()
            }

            -- Ensure container exists in nyx_inventory
            if exports['nyx_inventory'] and exports['nyx_inventory'].GetInventory then
                exports['nyx_inventory']:GetInventory(row.stash_id)
            end
        end
        print(string.format("^2[Nyx:Services] Loaded %d municipal emergency food pantries.^7", #pantryRows))
    end
end

-- ----------------------------------------------------------------------------
-- 2. Authoritative Crop Harvesting
-- ----------------------------------------------------------------------------

--- Authoritatively harvest crops from an agricultural farmland node
--- @param src number player source
--- @param farmId string
--- @return boolean success, table|string dataOrError
function Nyx.Services.HarvestCrop(src, farmId)
    local player = exports['nyx_core']:GetPlayer(src)
    if not player then return false, "UNAUTHORIZED" end

    local farm = Nyx.Services.Farms[farmId]
    if not farm then return false, "FARM_NOT_FOUND" end

    -- 1. Proximity check
    local ped = GetPlayerPed(tostring(src))
    local playerCoords = GetEntityCoords(ped)
    local farmVec = vector3(farm.coords.x, farm.coords.y, farm.coords.z)
    if #(playerCoords - farmVec) > 6.0 then
        return false, "OUT_OF_RANGE"
    end

    -- 2. Reserves check
    if farm.current_reserve <= 0 then
        return false, "FARM_RESERVE_DEPLETED"
    end

    -- 3. Pure Calculation of Yield and Soil Wear
    local yieldAmount, remainingReserve, newFertility = Nyx.Agriculture.CalculateCropYield(
        farm.current_reserve,
        farm.soil_fertility,
        1.0
    )

    if yieldAmount <= 0 then
        return false, "ZERO_YIELD"
    end

    -- 4. Capacity and weight check
    local playerInvId = string.format("char:%s:main", player.citizenId)
    local itemWeight = exports['nyx_inventory']:GetWeight(farm.crop_type, yieldAmount)
    local inv = exports['nyx_inventory']:GetInventory(playerInvId)
    if inv and not inv:canHoldWeight(itemWeight) then
        return false, "INVENTORY_OVERWEIGHT"
    end

    -- 5. Mutex & State Update
    farm.current_reserve = remainingReserve
    farm.soil_fertility = newFertility
    farm.last_harvested = os.time()

    MySQL.prepare([[
        UPDATE `nyx_logistics_agriculture_farms`
        SET `current_reserve` = ?, `soil_fertility` = ?, `last_harvested_at` = CURRENT_TIMESTAMP
        WHERE `farm_id` = ?
    ]], { farm.current_reserve, farm.soil_fertility, farmId })

    -- Mirror to nyx_logistics_nodes
    MySQL.prepare([[
        UPDATE `nyx_logistics_nodes`
        SET `current_reserve` = ?, `last_harvested_at` = CURRENT_TIMESTAMP
        WHERE `node_id` = ?
    ]], { farm.current_reserve, farmId })

    -- 6. Allocate Metadata and Add Item to Inventory
    local metadata = {
        farmOrigin = farmId,
        cropType = farm.crop_type,
        harvestedAt = os.time(),
        soilQuality = farm.soil_fertility,
        durability = 100.0,
        isSpoiled = false
    }

    local okAdd, addErr = exports['nyx_inventory']:AddItem(playerInvId, farm.crop_type, yieldAmount, metadata)
    if not okAdd then
        -- Rollback
        farm.current_reserve = farm.current_reserve + yieldAmount
        return false, addErr or "INVENTORY_ADD_FAILED"
    end

    -- 7. Audit log
    Nyx.Services.RecordFoodAudit(
        "HARVEST",
        farmId,
        playerInvId,
        farm.crop_type,
        yieldAmount,
        100.0,
        false,
        player.citizenId,
        string.format("Harvested %d units of %s (soil fertility: %.1f%%)", yieldAmount, farm.crop_type, farm.soil_fertility)
    )

    -- Stream telemetry update to clients
    TriggerClientEvent("nyx:services:client:farmUpdated", -1, farmId, farm.current_reserve, farm.soil_fertility)

    return true, {
        farmId = farmId,
        cropType = farm.crop_type,
        yield = yieldAmount,
        remainingReserve = farm.current_reserve,
        soilFertility = farm.soil_fertility
    }
end

-- ----------------------------------------------------------------------------
-- 3. Food Pantry Triage & Restocking
-- ----------------------------------------------------------------------------

--- Get item counts for a municipal food pantry
--- @param pantryId string
--- @return table counts
function Nyx.Services.GetPantryStockCounts(pantryId)
    local pantry = Nyx.Services.Pantries[pantryId]
    if not pantry then return {} end

    local counts = {
        food_ration = 0,
        food_bread = 0,
        food_sandwich = 0,
        crop_produce = 0
    }

    if exports['nyx_inventory'] and exports['nyx_inventory'].GetItemCount then
        counts.food_ration = exports['nyx_inventory']:GetItemCount(pantry.stash_id, "food_ration") or 0
        counts.food_bread = exports['nyx_inventory']:GetItemCount(pantry.stash_id, "food_bread") or 0
        counts.food_sandwich = exports['nyx_inventory']:GetItemCount(pantry.stash_id, "food_sandwich") or 0
        counts.crop_produce = exports['nyx_inventory']:GetItemCount(pantry.stash_id, "crop_produce") or 0
    end

    return counts
end

--- Authoritatively evaluate food pantry inventory levels and trigger emergency contracts on deficit
--- @param pantryId string
--- @return string status, number securityPercent, table metrics
function Nyx.Services.EvaluatePantryStatus(pantryId)
    local pantry = Nyx.Services.Pantries[pantryId]
    if not pantry then return "unknown", 0.0, {} end

    local counts = Nyx.Services.GetPantryStockCounts(pantryId)
    local status, securityPercent, metrics = Nyx.Agriculture.EvaluatePantryStatus(pantry, counts)

    local statusChanged = (pantry.status ~= status)
    pantry.status = status

    if statusChanged then
        MySQL.prepare([[
            UPDATE `nyx_services_food_pantries`
            SET `status` = ?, `updated_at` = CURRENT_TIMESTAMP
            WHERE `pantry_id` = ?
        ]], { status, pantryId })
    end

    -- Dynamic Emergency Freight Contract Generation on Critical Shortage
    if status == Nyx.Agriculture.STATUS_CRITICAL_SHORTAGE and exports['nyx_logistics'] then
        local now = os.time()
        local lastContractTime = pantry.last_emergency_contract_time or 0
        if (now - lastContractTime) >= 900 then -- 15 minute cooldown between emergency posts
            pantry.last_emergency_contract_time = now
            pantry.last_emergency_contract_at = os.date("!%Y-%m-%d %H:%M:%S", now)

            local deficitItem = (metrics.deficitRations > metrics.deficitBread) and "food_ration" or "food_bread"
            local deficitAmt = math.max(20, math.min(60, metrics.deficitRations + metrics.deficitBread))
            local contractParams = Nyx.Agriculture.CalculateEmergencyFoodContract(pantry, deficitItem, deficitAmt, status)

            local contractUuid = string.format("food-emerg-%s-%d", pantryId, now)

            MySQL.prepare([[
                INSERT INTO `nyx_logistics_freight_contracts`
                (`contract_uuid`, `contract_type`, `source_inventory_id`, `dest_inventory_id`, `item_id`, `quantity`, `payout_per_unit`, `total_payout`, `escrow_deposit`, `deadline_seconds`, `status`, `created_at`)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'available', NOW())
            ]], {
                contractUuid,
                contractParams.contractType,
                contractParams.sourceInventoryId,
                contractParams.destInventoryId,
                contractParams.itemId,
                contractParams.quantity,
                contractParams.payoutPerUnit,
                contractParams.totalPayout,
                contractParams.escrowDeposit,
                contractParams.deadlineSeconds
            })

            MySQL.prepare([[
                UPDATE `nyx_services_food_pantries`
                SET `last_emergency_contract_at` = CURRENT_TIMESTAMP
                WHERE `pantry_id` = ?
            ]], { pantryId })

            TriggerClientEvent("nyx:ui:notify", -1, {
                type = "warning",
                title = "EMERGENCY FOOD ALERT",
                message = string.format("Critical food shortage at %s! Priority emergency courier haul posted ($%.2f total payout).", pantry.name, contractParams.totalPayout)
            })

            print(string.format("^3[Nyx:Services] Emergency food contract dispatched for '%s': %d units of %s^7",
                pantryId, contractParams.quantity, contractParams.itemId))
        end
    end

    return status, securityPercent, metrics
end

--- Deposit food items into an emergency pantry
--- @param src number
--- @param pantryId string
--- @param itemId string
--- @param amount number
--- @return boolean success, table|string dataOrError
function Nyx.Services.RestockPantry(src, pantryId, itemId, amount)
    local player = exports['nyx_core']:GetPlayer(src)
    if not player then return false, "UNAUTHORIZED" end

    local pantry = Nyx.Services.Pantries[pantryId]
    if not pantry then return false, "PANTRY_NOT_FOUND" end

    local valid, valErr = Nyx.Agriculture.ValidateRestockPayload({
        pantryId = pantryId,
        itemId = itemId,
        amount = amount
    })
    if not valid then return false, valErr end

    local playerInvId = string.format("char:%s:main", player.citizenId)
    local hasItem = exports['nyx_inventory']:HasItem(playerInvId, itemId, amount)
    if not hasItem then
        return false, "INSUFFICIENT_ITEMS"
    end

    -- Dual Mutex Transfer
    local okLock, lockErr = exports['nyx_inventory']:WithDualLock(playerInvId, pantry.stash_id, function()
        local okRem = exports['nyx_inventory']:RemoveItem(playerInvId, itemId, amount)
        if not okRem then return false, "FAILED_TO_REMOVE" end

        local okAdd = exports['nyx_inventory']:AddItem(pantry.stash_id, itemId, amount, {
            restockedBy = player.citizenId,
            restockedAt = os.time(),
            durability = 100.0,
            isSpoiled = false
        })
        if not okAdd then
            exports['nyx_inventory']:AddItem(playerInvId, itemId, amount)
            return false, "PANTRY_STASH_FULL"
        end
        return true
    end)

    if not okLock or not lockErr then
        return false, lockErr or "LOCK_COLLISION"
    end

    -- Audit log
    Nyx.Services.RecordFoodAudit(
        "RESTOCK",
        playerInvId,
        pantry.stash_id,
        itemId,
        amount,
        100.0,
        false,
        player.citizenId,
        string.format("Citizen restocked %d units of %s into %s", amount, itemId, pantry.name)
    )

    -- Re-evaluate pantry status
    local status, securityPercent, metrics = Nyx.Services.EvaluatePantryStatus(pantryId)

    return true, {
        pantryId = pantryId,
        itemId = itemId,
        amount = amount,
        newStatus = status,
        securityPercent = securityPercent,
        metrics = metrics
    }
end

--- Dispose of spoiled or rotten food in a pantry container
--- @param src number
--- @param pantryId string
--- @return boolean success, table|string dataOrError
function Nyx.Services.DisposeSpoiledFood(src, pantryId)
    local player = exports['nyx_core']:GetPlayer(src)
    if not player then return false, "UNAUTHORIZED" end

    local pantry = Nyx.Services.Pantries[pantryId]
    if not pantry then return false, "PANTRY_NOT_FOUND" end

    local inv = exports['nyx_inventory']:GetInventory(pantry.stash_id)
    if not inv then return false, "INVENTORY_NOT_FOUND" end

    local snapshot = inv:getSnapshot()
    local disposedCount = 0

    if snapshot and snapshot.items then
        for _, itm in ipairs(snapshot.items) do
            local dur = tonumber(itm.metadata and itm.metadata.durability) or 100.0
            local isSp = (itm.metadata and itm.metadata.isSpoiled == true) or (dur <= 0.0)
            if isSp then
                local removed = exports['nyx_inventory']:RemoveItem(pantry.stash_id, itm.item_id, itm.amount or 1)
                if removed then
                    disposedCount = disposedCount + (itm.amount or 1)
                    Nyx.Services.RecordFoodAudit(
                        "SPOILAGE_DISPOSAL",
                        pantry.stash_id,
                        nil,
                        itm.item_id,
                        itm.amount or 1,
                        0.0,
                        true,
                        player.citizenId,
                        "Sanitary disposal of spoiled food"
                    )
                end
            end
        end
    end

    Nyx.Services.EvaluatePantryStatus(pantryId)

    return true, { pantryId = pantryId, disposedCount = disposedCount }
end

-- ----------------------------------------------------------------------------
-- 4. Immutable Food Logistics Audit Ledger
-- ----------------------------------------------------------------------------

function Nyx.Services.RecordFoodAudit(action, sourceId, targetInvId, itemId, quantity, durability, isSpoiled, citizenId, notes)
    local uuid = string.format("faudit-%s-%d", action:lower(), math.random(100000, 999999))
    MySQL.prepare([[
        INSERT INTO `nyx_logistics_food_audit`
        (`audit_uuid`, `action`, `source_id`, `target_inventory_id`, `item_id`, `quantity`, `durability`, `is_spoiled`, `citizen_id`, `notes`)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ]], {
        uuid,
        action,
        sourceId,
        targetInvId,
        itemId,
        quantity,
        durability or 100.0,
        isSpoiled and 1 or 0,
        citizenId,
        notes or ""
    })
end

-- ----------------------------------------------------------------------------
-- 5. Background Simulation: Soil Recovery & Perishable Freshness Ticks
-- ----------------------------------------------------------------------------

-- Soil Fertility Recovery Routine (Runs every 5 minutes)
function Nyx.Services.ProcessSoilRecoveryTick()
    local now = os.time()
    for farmId, farm in pairs(Nyx.Services.Farms) do
        if farm.soil_fertility < 100.0 then
            local elapsed = now - (farm.last_harvested or now)
            if elapsed >= 120 then
                local recovered = Nyx.Agriculture.CalculateSoilRecovery(farm.soil_fertility, elapsed, 15.0)
                if recovered ~= farm.soil_fertility then
                    farm.soil_fertility = recovered
                    MySQL.prepare([[
                        UPDATE `nyx_logistics_agriculture_farms`
                        SET `soil_fertility` = ?
                        WHERE `farm_id` = ?
                    ]], { farm.soil_fertility, farmId })
                    TriggerClientEvent("nyx:services:client:farmUpdated", -1, farmId, farm.current_reserve, farm.soil_fertility)
                end
            end
        end
    end
end

-- Perishable Freshness Degradation Sweep (Runs every 3 minutes)
function Nyx.Services.ProcessFoodFreshnessTick()
    local monitoredStashes = {}

    for _, p in pairs(Nyx.Services.Pantries) do
        monitoredStashes[#monitoredStashes + 1] = { id = p.stash_id, type = "cold_storage" }
    end

    -- Add retail store shelves
    monitoredStashes[#monitoredStashes + 1] = { id = "stash:store_vinewood_food", type = "stash" }
    monitoredStashes[#monitoredStashes + 1] = { id = "stash:store_davis_food", type = "stash" }
    for _, container in ipairs(monitoredStashes) do
        local inv = exports['nyx_inventory'] and exports['nyx_inventory']:GetInventory(container.id)
        if inv then
            local snapshot = (type(inv.getSnapshot) == "function" and inv:getSnapshot()) or inv
            if snapshot and snapshot.items then
                for _, itm in ipairs(snapshot.items) do
                    local itemDef = exports['nyx_inventory']:GetItemDefinition(itm.item_id)
                    if itemDef and (itemDef.type == "food" or itemDef.type == "drink") and (itemDef.decayRate or 0) > 0 then
                        local curDur = tonumber(itm.metadata and itm.metadata.durability) or 100.0
                        local decayRate = tonumber(itm.metadata and itm.metadata.decayRate) or itemDef.decayRate
                        local newDur, isSp, tier, loss = Nyx.Agriculture.CalculatePerishableDecay(
                            curDur,
                            decayRate,
                            180, -- 180s per tick
                            container.type,
                            container.type == "cold_storage"
                        )
                        if loss > 0.0 and itm.metadata then
                            itm.metadata.durability = newDur
                            itm.metadata.isSpoiled = isSp
                            itm.metadata.freshnessTier = tier
                        end
                    end
                end
            end
        end
    end

    -- Re-evaluate all pantries after freshness sweep
    for pantryId, _ in pairs(Nyx.Services.Pantries) do
        Nyx.Services.EvaluatePantryStatus(pantryId)
    end
end

-- ----------------------------------------------------------------------------
-- 6. Event Handlers & RPC Registration
-- ----------------------------------------------------------------------------

-- Hook for delivered logistics hauls
AddEventHandler("nyx:services:server:foodLogisticsDelivered", function(destInvId, contractId, itemId, quantity)
    for pantryId, pantry in pairs(Nyx.Services.Pantries) do
        if pantry.stash_id == destInvId then
            Nyx.Services.RecordFoodAudit(
                "EMERGENCY_DELIVERY",
                string.format("contract:%s", tostring(contractId)),
                destInvId,
                itemId,
                quantity,
                100.0,
                false,
                nil,
                string.format("Contract #%s fulfilled: %d units of %s delivered to pantry", tostring(contractId), quantity, itemId)
            )
            Nyx.Services.EvaluatePantryStatus(pantryId)
            break
        end
    end
end)

-- Background Tick Threads
CreateThread(function()
    while true do
        Wait(300000) -- Every 5 minutes
        Nyx.Services.ProcessSoilRecoveryTick()
    end
end)

CreateThread(function()
    while true do
        Wait(180000) -- Every 3 minutes
        Nyx.Services.ProcessFoodFreshnessTick()
    end
end)
