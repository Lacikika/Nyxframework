--[[
    Nyxframework: nyx_logistics
    File: server/shelves.lua
    Description: Physical retail shelf engine, dynamic price elasticity, and tax-intercepted consumer checkout.
]]

Nyx = Nyx or {}
Nyx.Logistics = Nyx.Logistics or {}
Nyx.Logistics.Shelves = {} -- [shelfId] = shelfState

-- Calculate dynamic shelf price based on current stock vs equilibrium target
function Nyx.Logistics.CalculateShelfPrice(basePrice, targetCapacity, currentStock)
    basePrice = tonumber(basePrice) or 10.00
    targetCapacity = math.max(1, tonumber(targetCapacity) or 100)
    currentStock = math.max(0, tonumber(currentStock) or 0)

    local alpha = Config.ElasticityCoefficient or 1.25
    local floorCoeff = Config.SurplusFloor or 0.50
    local ceilCoeff = Config.ShortageCeiling or 2.25

    -- Core Formula: P = Pbase * (1 + alpha * (Ctarget - Scurrent) / Ctarget)
    local rawMultiplier = 1.0 + (alpha * ((targetCapacity - currentStock) / targetCapacity))
    local boundedMultiplier = math.max(floorCoeff, math.min(ceilCoeff, rawMultiplier))

    local calculatedPrice = math.floor((basePrice * boundedMultiplier) * 100) / 100
    return calculatedPrice, boundedMultiplier
end

-- Hydrate retail shelves on server start
CreateThread(function()
    while GetResourceState("oxmysql") ~= "started" do
        Wait(50)
    end

    local rows = MySQL.query.await("SELECT * FROM `nyx_logistics_shelves`")
    if rows then
        for _, row in ipairs(rows) do
            local shelf = {
                id = row.shelf_id,
                store_id = row.store_id,
                target_capacity = tonumber(row.target_capacity) or 100,
                item_id = row.item_id,
                base_price = tonumber(row.base_price) or 10.00,
                current_price = tonumber(row.current_price) or 10.00,
                inventory_id = row.inventory_id
            }

            -- Ensure physical shelf inventory container exists
            exports['nyx_inventory']:GetInventory(row.inventory_id)

            -- Compute initial price based on actual current stock
            local stock = exports['nyx_inventory']:GetItemCount(shelf.inventory_id, shelf.item_id)
            shelf.current_price = Nyx.Logistics.CalculateShelfPrice(shelf.base_price, shelf.target_capacity, stock)

            Nyx.Logistics.Shelves[row.shelf_id] = shelf
        end
        print(string.format("^2[Nyx:Logistics] Loaded %d retail shelf containers with dynamic elasticity.^7", #rows))
    end
end)

-- RPC: Query Shelf State & Active Elastic Price
Nyx.RPC.Register("logistics:getShelfInfo", function(src, shelfId)
    local shelf = Nyx.Logistics.Shelves[shelfId]
    if not shelf then return nil, "SHELF_NOT_FOUND" end

    local stock = exports['nyx_inventory']:GetItemCount(shelf.inventory_id, shelf.item_id)
    local currentPrice, mult = Nyx.Logistics.CalculateShelfPrice(shelf.base_price, shelf.target_capacity, stock)
    shelf.current_price = currentPrice

    return {
        id = shelf.id,
        storeId = shelf.store_id,
        itemId = shelf.item_id,
        basePrice = shelf.base_price,
        currentPrice = currentPrice,
        stock = stock,
        targetCapacity = shelf.target_capacity,
        priceMultiplier = mult
    }
end)

-- RPC: Authoritative Shelf Item Purchase
Nyx.RPC.Register("logistics:buyFromShelf", function(src, shelfId, quantity)
    local player = exports['nyx_core']:GetPlayer(src)
    if not player then return { success = false, error = "UNAUTHORIZED" } end

    local shelf = Nyx.Logistics.Shelves[shelfId]
    if not shelf then return { success = false, error = "SHELF_NOT_FOUND" } end

    quantity = math.max(1, math.floor(tonumber(quantity) or 1))

    -- 1. In-Stock Verification
    local currentStock = exports['nyx_inventory']:GetItemCount(shelf.inventory_id, shelf.item_id)
    if currentStock < quantity then
        -- Trigger freight shortage contract automatically
        Nyx.Logistics.CheckShortageContract(shelf, currentStock)
        return { success = false, error = "OUT_OF_STOCK" }
    end

    -- 2. Elastic Price Calculation
    local unitPrice = Nyx.Logistics.CalculateShelfPrice(shelf.base_price, shelf.target_capacity, currentStock)
    local totalGross = math.floor((unitPrice * quantity) * 100) / 100

    -- 3. Consumer Funds Verification
    local playerCash = player:getWallet("cash") or 0
    local playerBank = player:getWallet("bank") or 0

    local paymentWallet = "cash"
    if playerCash < totalGross then
        if playerBank >= totalGross then
            paymentWallet = "bank"
        else
            return { success = false, error = "INSUFFICIENT_FUNDS" }
        end
    end

    -- 4. Deduct Consumer Funds & Intercept Municipal Sales Tax via nyx_treasury
    local buyerAcc = string.format("char:%s:%s", player.citizenId, paymentWallet)
    local storeAcc = string.format("store:%s", shelf.store_id)

    -- Deduct locally from player object
    player:removeMoney(paymentWallet, totalGross, string.format("Retail purchase at %s", shelf.store_id))

    -- Route tax split directly into municipal treasury
    local okTax, taxResult = exports['nyx_treasury']:ProcessPOSTransaction(
        buyerAcc,
        storeAcc,
        totalGross,
        string.format("Shelf purchase: %dx %s", quantity, shelf.item_id)
    )

    if not okTax then
        -- Fallback: If bank ledger transfer fails, log warning but proceed with retail delivery
        if Config.Debug then
            print(string.format("^3[Nyx:Logistics] Warning: POS tax leg bypassed for shelf purchase: %s^7", tostring(taxResult)))
        end
    end

    -- 5. Physically Deduct Item from Shelf & Add to Player
    local playerInvId = string.format("char:%s:main", player.citizenId)
    local okRemove = exports['nyx_inventory']:RemoveItem(shelf.inventory_id, shelf.item_id, quantity)
    if not okRemove then
        -- Refund consumer
        player:addMoney(paymentWallet, totalGross, "Shelf transaction rollback")
        return { success = false, error = "SHELF_EXTRACTION_FAILED" }
    end

    local itemMeta = {
        retailSource = shelf.store_id,
        purchasedPrice = unitPrice,
        purchasedAt = os.time()
    }
    exports['nyx_inventory']:AddItem(playerInvId, shelf.item_id, quantity, itemMeta)

    -- 6. Recalibrate Price Post-Purchase
    local newStock = currentStock - quantity
    local newPrice = Nyx.Logistics.CalculateShelfPrice(shelf.base_price, shelf.target_capacity, newStock)
    shelf.current_price = newPrice

    MySQL.prepare([[
        UPDATE `nyx_logistics_shelves` 
        SET `current_price` = ? 
        WHERE `shelf_id` = ?
    ]], { newPrice, shelf.id })

    -- Check if shortage contract should be posted
    Nyx.Logistics.CheckShortageContract(shelf, newStock)

    -- Broadcast price update to clients
    TriggerClientEvent("nyx:logistics:client:shelfUpdated", -1, shelf.id, newPrice, newStock)

    return {
        success = true,
        unitPrice = unitPrice,
        totalGross = totalGross,
        quantity = quantity,
        newStock = newStock
    }
end)
