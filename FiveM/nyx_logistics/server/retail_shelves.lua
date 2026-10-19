--[[
    Nyxframework: nyx_logistics
    File: server/retail_shelves.lua
    Description: Authoritative physical retail shelf controller, dynamic prop model resolution,
                 manual player restocking engine with double-entry wholesale consignment payouts,
                 and zero-trust spatial validation.
]]

Nyx = Nyx or {}
Nyx.Logistics = Nyx.Logistics or {}
Nyx.Logistics.RetailShelves = {} -- [shelfId] = shelfTable

-- Server RPC Bridge
Nyx.RPC = Nyx.RPC or {
    Register = function(route, handler)
        exports['nyx_core']:RegisterRPC(route, handler)
    end,
    GenerateNonce = function()
        local template = 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'
        return (string.gsub(template, '[xy]', function(c)
            local v = (c == 'x') and math.random(0, 0xf) or math.random(8, 0xb)
            return string.format('%x', v)
        end))
    end
}

-- ----------------------------------------------------------------------------
-- 1. Database Bootloader & Physical Shelf Hydration
-- ----------------------------------------------------------------------------
MySQL.ready(function()
    while GetResourceState("oxmysql") ~= "started" do
        Wait(50)
    end
    while not (exports['nyx_core'] and exports['nyx_core'].IsDatabaseReady and exports['nyx_core']:IsDatabaseReady()) do
        Wait(50)
    end

    local rows = MySQL.query.await([[
        SELECT `shelf_id`, `store_id`, `zone_id`, `target_capacity`, `item_id`,
               `base_price`, `current_price`, `inventory_id`, `coords`, `heading`,
               `shelf_category`, `shelf_label`, `stocked_model`, `empty_model`,
               `display_mode`, `is_restockable`, `sales_velocity`,
               UNIX_TIMESTAMP(`last_purchased_at`) AS `last_purchased_unix`
        FROM `nyx_logistics_shelves`
    ]])

    if rows then
        for _, r in ipairs(rows) do
            local rawCoords = r.coords and json.decode(r.coords) or { x = 0.0, y = 0.0, z = 0.0 }
            local currentStock = 0
            if exports['nyx_inventory'] and exports['nyx_inventory'].GetItemCount then
                currentStock = exports['nyx_inventory']:GetItemCount(r.inventory_id, r.item_id)
            end

            local shelfData = {
                shelf_id = r.shelf_id,
                id = r.shelf_id,
                store_id = r.store_id,
                zone_id = r.zone_id or "zone_ls_metro",
                target_capacity = tonumber(r.target_capacity) or 100,
                item_id = r.item_id,
                base_price = tonumber(r.base_price) or 10.00,
                current_price = tonumber(r.current_price) or 10.00,
                inventory_id = r.inventory_id,
                coords = { x = rawCoords.x or 0.0, y = rawCoords.y or 0.0, z = rawCoords.z or 0.0 },
                heading = tonumber(r.heading) or 0.00,
                shelf_category = r.shelf_category or "general",
                shelf_label = r.shelf_label or "Retail Display Shelf",
                stocked_model = r.stocked_model or "prop_shelves_02",
                empty_model = r.empty_model or "prop_rack_empty",
                display_mode = r.display_mode or "prop_swap",
                is_restockable = (tonumber(r.is_restockable) == 1),
                current_stock = currentStock,
                sales_velocity = tonumber(r.sales_velocity) or 0.0,
                last_purchased_at = r.last_purchased_unix
            }

            -- Resolve active model
            shelfData.active_model = Nyx.RetailShelves.ResolveShelfPropModel(shelfData, currentStock)
            shelfData.fullness_state = Nyx.RetailShelves.GetFullnessState(currentStock, shelfData.target_capacity)

            Nyx.Logistics.RetailShelves[r.shelf_id] = shelfData

            -- Ensure synchronized with Nyx.Logistics.Shelves
            if Nyx.Logistics.Shelves then
                Nyx.Logistics.Shelves[r.shelf_id] = shelfData
            end
        end

        print(string.format("^2[Nyx:Logistics] Hydrated %d physical retail shelves with 3D prop models and coordinates.^7", #rows))
    end
end)

-- ----------------------------------------------------------------------------
-- 2. Shelf Stock Change Hook & Visual State Synchronizer
-- ----------------------------------------------------------------------------
--- Called whenever stock changes (via purchase, restock, or freight contract delivery)
function Nyx.Logistics.NotifyShelfStockChanged(shelfId, newStock, action, citizenId, unitPrice, wholesalePayout)
    local shelf = Nyx.Logistics.RetailShelves[shelfId]
    if not shelf then
        -- Attempt to find in Nyx.Logistics.Shelves
        shelf = Nyx.Logistics.Shelves and Nyx.Logistics.Shelves[shelfId]
        if shelf then
            Nyx.Logistics.RetailShelves[shelfId] = shelf
        else
            return
        end
    end

    local prevStock = shelf.current_stock or 0
    newStock = math.max(0, math.floor(tonumber(newStock) or 0))
    shelf.current_stock = newStock

    local prevState = shelf.fullness_state
    local newState, ratio, deficit = Nyx.RetailShelves.GetFullnessState(newStock, shelf.target_capacity)
    shelf.fullness_state = newState

    local prevModel = shelf.active_model
    local newModel = Nyx.RetailShelves.ResolveShelfPropModel(shelf, newStock)
    shelf.active_model = newModel

    -- Broadcast visual state update to clients
    TriggerClientEvent("nyx:logistics:client:shelfVisualStateChanged", -1, {
        shelfId = shelfId,
        newStock = newStock,
        targetCapacity = shelf.target_capacity,
        fullnessState = newState,
        activeModel = newModel,
        modelChanged = (prevModel ~= newModel),
        coords = shelf.coords,
        heading = shelf.heading
    })

    -- Audit record in database
    pcall(function()
        local auditUuid = Nyx.RPC.GenerateNonce()
        MySQL.prepare([[
            INSERT INTO `nyx_logistics_shelf_restock_audits`
            (`audit_uuid`, `shelf_id`, `store_id`, `citizen_id`, `action`, `item_id`, `quantity`,
             `previous_stock`, `new_stock`, `unit_price`, `wholesale_payout`, `notes`)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ]], {
            auditUuid,
            shelfId,
            shelf.store_id or "store_general",
            citizenId or "SYSTEM",
            action or "STOCK_TRANSFER",
            shelf.item_id,
            math.abs(newStock - prevStock),
            prevStock,
            newStock,
            unitPrice or shelf.current_price or shelf.base_price,
            wholesalePayout or 0.00,
            string.format("Stock transition: %s -> %s (Model: %s)", prevState or "UNKNOWN", newState, newModel)
        })
    end)
end

-- ----------------------------------------------------------------------------
-- 3. Authoritative Manual Shelf Restocking Engine
-- ----------------------------------------------------------------------------
function Nyx.Logistics.RestockShelf(src, shelfId, requestedQty)
    local player = exports['nyx_core']:GetPlayer(src)
    if not player then return { success = false, error = "UNAUTHENTICATED" } end

    local shelf = Nyx.Logistics.RetailShelves[shelfId]
    if not shelf then
        return { success = false, error = "SHELF_NOT_FOUND" }
    end

    if not shelf.is_restockable then
        return { success = false, error = "SHELF_NOT_RESTOCKABLE" }
    end

    -- Proximity validation: ped must be within interaction radius of shelf coords
    local ped = GetPlayerPed(tostring(src))
    local pCoords = GetEntityCoords(ped)
    local sCoords = vector3(shelf.coords.x, shelf.coords.y, shelf.coords.z)

    if #(pCoords - sCoords) > 4.50 then
        return { success = false, error = "TOO_FAR_FROM_SHELF" }
    end

    -- Check player inventory item count
    local playerInvId = string.format("char:%s:main", player.citizenId)
    local playerCount = exports['nyx_inventory']:GetItemCount(playerInvId, shelf.item_id)

    if playerCount <= 0 then
        return { success = false, error = "NO_MATCHING_ITEMS_IN_INVENTORY" }
    end

    -- Evaluate restock limits and wholesale reimbursement
    local okEval, evalDataOrErr = Nyx.RetailShelves.EvaluateRestock(shelf, playerCount, requestedQty)
    if not okEval then
        return { success = false, error = evalDataOrErr }
    end

    local qty = evalDataOrErr.quantity
    local wholesalePayout = evalDataOrErr.wholesalePayout

    -- Dijkstra Dual-Mutex Lock: Transfer from player to shelf container
    local okLock, transferErr = exports['nyx_inventory']:WithDualLock(playerInvId, shelf.inventory_id, function()
        local okRemove = exports['nyx_inventory']:RemoveItem(playerInvId, shelf.item_id, qty)
        if not okRemove then
            return false, "FAILED_TO_REMOVE_FROM_PLAYER"
        end

        local okAdd = exports['nyx_inventory']:AddItem(shelf.inventory_id, shelf.item_id, qty, {
            restockedBy = player.citizenId,
            restockedAt = os.time()
        })

        if not okAdd then
            -- Rollback
            exports['nyx_inventory']:AddItem(playerInvId, shelf.item_id, qty)
            return false, "SHELF_CONTAINER_FULL"
        end

        return true
    end)

    if not okLock or transferErr then
        return { success = false, error = transferErr or "TRANSFER_LOCK_FAILED" }
    end

    -- Credit wholesale reimbursement to player bank account via double-entry treasury
    local storeAcc = string.format("store:%s", shelf.store_id)
    local playerAcc = string.format("char:%s:bank", player.citizenId)

    if wholesalePayout > 0 then
        local okTransfer = exports['nyx_treasury']:ExecuteTransfer(
            storeAcc,
            playerAcc,
            wholesalePayout,
            "consignment_payout",
            string.format("restock:%s", shelfId),
            string.format("Wholesale restock payout (%dx %s)", qty, shelf.item_id),
            0.0
        )

        -- If store account lacks liquidity, settle from municipal economic stabilization fund
        if not okTransfer then
            exports['nyx_treasury']:ExecuteTransfer(
                "gov:city:master",
                playerAcc,
                wholesalePayout,
                "consignment_payout",
                string.format("restock:%s", shelfId),
                string.format("Municipal restock incentive payout (%dx %s)", qty, shelf.item_id),
                0.0
            )
        end
    end

    -- Recalculate shelf elastic price downwards due to increased stock
    local newStock = evalDataOrErr.newStock
    local newPrice, newMult, newRatio = Nyx.Logistics.CalculateShelfPrice(
        shelf.base_price, shelf.target_capacity, newStock, shelf.zone_id, shelf.item_id, shelf
    )
    shelf.current_price = newPrice

    MySQL.prepare([[
        UPDATE `nyx_logistics_shelves`
        SET `current_price` = ?
        WHERE `shelf_id` = ?
    ]], { newPrice, shelfId })

    -- Synchronize visual state and log audit
    Nyx.Logistics.NotifyShelfStockChanged(shelfId, newStock, "RESTOCK_MANUAL", player.citizenId, newPrice, wholesalePayout)

    -- Broadcast shelf price update
    TriggerClientEvent("nyx:logistics:client:shelfUpdated", -1, shelfId, newPrice, newStock, shelf.zone_id, newRatio)

    print(string.format("^2[Nyx:Logistics] Citizen %s restocked %dx %s into %s (Payout: $%.2f, New Price: $%.2f)^7",
        player.citizenId, qty, shelf.item_id, shelfId, wholesalePayout, newPrice))

    return {
        success = true,
        shelfId = shelfId,
        restockedQuantity = qty,
        wholesalePayout = wholesalePayout,
        previousStock = evalDataOrErr.previousStock,
        newStock = newStock,
        newPrice = newPrice,
        fullnessState = shelf.fullness_state,
        activeModel = shelf.active_model
    }
end

-- ----------------------------------------------------------------------------
-- 4. RPC Route Handlers
-- ----------------------------------------------------------------------------

-- RPC: Get all physical retail shelves
Nyx.RPC.Register("logistics:getRetailShelves", function(src)
    local list = {}
    for _, s in pairs(Nyx.Logistics.RetailShelves) do
        local stock = exports['nyx_inventory']:GetItemCount(s.inventory_id, s.item_id)
        local price = s.current_price or s.base_price
        list[#list + 1] = Nyx.RetailShelves.FormatShelfDisplay(s, stock, price)
    end
    return {
        success = true,
        shelves = list
    }
end)

-- RPC: Get nearby retail shelves relative to player position
Nyx.RPC.Register("logistics:getNearbyRetailShelves", function(src, maxDist)
    maxDist = tonumber(maxDist) or 50.0
    local ped = GetPlayerPed(tostring(src))
    local pCoords = GetEntityCoords(ped)

    local nearby = {}
    for _, s in pairs(Nyx.Logistics.RetailShelves) do
        local isNear, dist = Nyx.RetailShelves.IsPointNearShelf(pCoords, s.coords, maxDist)
        if isNear then
            local stock = exports['nyx_inventory']:GetItemCount(s.inventory_id, s.item_id)
            local item = Nyx.RetailShelves.FormatShelfDisplay(s, stock, s.current_price)
            item.distance = math.floor(dist * 10) / 10
            nearby[#nearby + 1] = item
        end
    end

    table.sort(nearby, function(a, b) return a.distance < b.distance end)

    return {
        success = true,
        shelves = nearby
    }
end)

-- RPC: Restock a shelf manually from inventory
Nyx.RPC.Register("logistics:restockShelf", function(src, shelfId, quantity)
    return Nyx.Logistics.RestockShelf(src, shelfId, quantity)
end)
