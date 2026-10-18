--[[
    Nyxframework: nyx_logistics
    File: client/retail_shelves.lua
    Description: Client-side spatial prop streaming for retail store shelves,
                 dynamic empty shelf prop swapping/despawning, and Third-Eye (nyx_interact) targets.
]]

Nyx = Nyx or {}
Nyx.Logistics = Nyx.Logistics or {}
Nyx.Logistics.ClientShelves = {}      -- [shelfId] = shelfData
Nyx.Logistics.SpawnedEntities = {}    -- [shelfId] = { entity = entityId, model = modelHash, coords = vec3 }

local streamingActive = true
local streamingRadius = Nyx.RetailShelves and Nyx.RetailShelves.StreamingRadius or 45.0
local despawnRadius = streamingRadius + 8.0

-- ----------------------------------------------------------------------------
-- 1. Cache Retail Shelves on Startup & Resource Events
-- ----------------------------------------------------------------------------
local function refreshClientShelves()
    CreateThread(function()
        local res = exports['nyx_core']:TriggerRPCAwait("logistics:getRetailShelves")
        if res and res.success and res.shelves then
            for _, s in ipairs(res.shelves) do
                Nyx.Logistics.ClientShelves[s.shelfId] = s
            end
            if Config.Debug then
                print(string.format("^2[Nyx:Logistics:Client] Loaded %d retail shelves into client cache.^7", #res.shelves))
            end
        end
    end)
end

CreateThread(function()
    while not NetworkIsSessionStarted() do
        Wait(500)
    end
    refreshClientShelves()
end)

RegisterNetEvent("onResourceStart", function(resName)
    if resName == GetCurrentResourceName() then
        refreshClientShelves()
    end
end)

-- ----------------------------------------------------------------------------
-- 2. Prop Model Spawner & Swapper
-- ----------------------------------------------------------------------------
local function spawnShelfEntity(shelfId, shelf)
    if not shelf or not shelf.coords then return nil end

    local stock = shelf.currentStock or shelf.current_stock or 0
    local modelName = Nyx.RetailShelves.ResolveShelfPropModel(shelf, stock)
    local modelHash = GetHashKey(modelName)

    RequestModel(modelHash)
    local timeout = 0
    while not HasModelLoaded(modelHash) and timeout < 50 do
        Wait(20)
        timeout = timeout + 1
    end

    if not HasModelLoaded(modelHash) then
        modelHash = GetHashKey(Nyx.RetailShelves.DefaultStockedModel or "prop_shelves_02")
        RequestModel(modelHash)
        while not HasModelLoaded(modelHash) and timeout < 70 do
            Wait(20)
            timeout = timeout + 1
        end
    end

    local c = shelf.coords
    local obj = CreateObject(modelHash, c.x, c.y, c.z, false, false, false)
    if not DoesEntityExist(obj) then return nil end

    SetEntityHeading(obj, shelf.heading or 0.0)
    FreezeEntityPosition(obj, true)
    PlaceObjectOnGroundProperly(obj)
    SetModelAsNoLongerNeeded(modelHash)

    -- Register Third-Eye Spatial Interaction with nyx_interact
    if exports['nyx_interact'] and exports['nyx_interact'].AddTargetEntity then
        exports['nyx_interact']:AddTargetEntity(obj, {
            options = {
                {
                    id = "opt_retail_buy_" .. shelfId,
                    label = string.format("Vásárlás: %s ($%.2f)", shelf.label or "Termék", shelf.unitPrice or 10.0),
                    icon = "fas fa-shopping-basket",
                    distance = Nyx.RetailShelves.MaxInteractionDistance or 2.5,
                    action = function(entity)
                        TriggerEvent("nyx:logistics:client:promptShelfPurchase", shelfId)
                    end
                },
                {
                    id = "opt_retail_restock_" .. shelfId,
                    label = string.format("Készlet Feltöltése (Restock: +$%.2f/db)", shelf.wholesaleRestockRate or 7.0),
                    icon = "fas fa-dolly",
                    distance = Nyx.RetailShelves.MaxInteractionDistance or 2.5,
                    action = function(entity)
                        TriggerEvent("nyx:logistics:client:promptShelfRestock", shelfId)
                    end
                },
                {
                    id = "opt_retail_info_" .. shelfId,
                    label = "Polc Piaci Árindex & Készlet",
                    icon = "fas fa-circle-info",
                    distance = Nyx.RetailShelves.MaxInteractionDistance or 2.5,
                    action = function(entity)
                        TriggerEvent("nyx:logistics:client:showShelfInfo", shelfId)
                    end
                }
            },
            distance = Nyx.RetailShelves.MaxInteractionDistance or 2.5
        })
    end

    Nyx.Logistics.SpawnedEntities[shelfId] = {
        entity = obj,
        model = modelHash,
        modelName = modelName,
        coords = vector3(c.x, c.y, c.z)
    }

    return obj
end

local function despawnShelfEntity(shelfId)
    local data = Nyx.Logistics.SpawnedEntities[shelfId]
    if not data then return end

    if exports['nyx_interact'] and exports['nyx_interact'].RemoveTargetEntity and DoesEntityExist(data.entity) then
        pcall(function()
            exports['nyx_interact']:RemoveTargetEntity(data.entity)
        end)
    end

    if DoesEntityExist(data.entity) then
        DeleteEntity(data.entity)
    end

    Nyx.Logistics.SpawnedEntities[shelfId] = nil
end

-- ----------------------------------------------------------------------------
-- 3. World Streaming Thread
-- ----------------------------------------------------------------------------
CreateThread(function()
    while streamingActive do
        Wait(1000)

        local ped = PlayerPedId()
        if DoesEntityExist(ped) then
            local pCoords = GetEntityCoords(ped)

            for shelfId, shelf in pairs(Nyx.Logistics.ClientShelves) do
                if shelf.coords then
                    local sCoords = vector3(shelf.coords.x, shelf.coords.y, shelf.coords.z)
                    local dist = #(pCoords - sCoords)

                    local spawned = Nyx.Logistics.SpawnedEntities[shelfId]

                    if dist <= streamingRadius then
                        local stock = shelf.currentStock or shelf.current_stock or 0
                        local expectedModel = Nyx.RetailShelves.ResolveShelfPropModel(shelf, stock)
                        local expectedHash = GetHashKey(expectedModel)

                        if not spawned or not DoesEntityExist(spawned.entity) then
                            spawnShelfEntity(shelfId, shelf)
                        elseif spawned.model ~= expectedHash then
                            -- Stock changed and crossed empty/stocked threshold: SWAP PROP IMMEDIATELY!
                            despawnShelfEntity(shelfId)
                            spawnShelfEntity(shelfId, shelf)
                        end
                    elseif dist > despawnRadius and spawned then
                        despawnShelfEntity(shelfId)
                    end
                end
            end
        end
    end
end)

-- ----------------------------------------------------------------------------
-- 4. Network Synchronization Listeners
-- ----------------------------------------------------------------------------
RegisterNetEvent("nyx:logistics:client:shelfVisualStateChanged", function(payload)
    if type(payload) ~= "table" or not payload.shelfId then return end
    local shelfId = payload.shelfId

    local shelf = Nyx.Logistics.ClientShelves[shelfId]
    if shelf then
        shelf.currentStock = payload.newStock
        shelf.fullnessState = payload.fullnessState
        shelf.activeModel = payload.activeModel
    else
        Nyx.Logistics.ClientShelves[shelfId] = {
            shelfId = shelfId,
            currentStock = payload.newStock,
            targetCapacity = payload.targetCapacity or 100,
            fullnessState = payload.fullnessState,
            activeModel = payload.activeModel,
            coords = payload.coords,
            heading = payload.heading
        }
    end

    -- If currently spawned and model differs, swap entity immediately
    local spawned = Nyx.Logistics.SpawnedEntities[shelfId]
    if spawned and DoesEntityExist(spawned.entity) and payload.modelChanged then
        despawnShelfEntity(shelfId)
        spawnShelfEntity(shelfId, Nyx.Logistics.ClientShelves[shelfId])
    end
end)

RegisterNetEvent("nyx:logistics:client:shelfUpdated", function(shelfId, newPrice, newStock, zoneId, stockToDemandRatio)
    local shelf = Nyx.Logistics.ClientShelves[shelfId]
    if shelf then
        shelf.currentStock = newStock
        shelf.unitPrice = newPrice
        shelf.stockToDemandRatio = stockToDemandRatio
    end
end)

-- ----------------------------------------------------------------------------
-- 5. User Interaction Handlers
-- ----------------------------------------------------------------------------
RegisterNetEvent("nyx:logistics:client:promptShelfPurchase", function(shelfId)
    local shelf = Nyx.Logistics.ClientShelves[shelfId]
    if not shelf then
        local res = exports['nyx_core']:TriggerRPCAwait("logistics:getShelfInfo", shelfId)
        if res and res.id then
            shelf = res
        else
            TriggerEvent("nyx:core:client:notify", "A polc nem található vagy offline.", "error")
            return
        end
    end

    local stock = shelf.currentStock or shelf.stock or 0
    if stock <= 0 then
        TriggerEvent("nyx:core:client:notify", "A polc teljesen kiürült! Várj fuvarozói készletfeltöltésre.", "error")
        return
    end

    -- Direct purchase of 1 unit
    local buyRes = exports['nyx_core']:TriggerRPCAwait("logistics:buyFromShelf", shelfId, 1)
    if buyRes and buyRes.success then
        TriggerEvent("nyx:core:client:notify",
            string.format("Sikeres vásárlás: 1x %s ($%.2f levonva).", shelf.itemId or "áru", buyRes.unitPrice or 0.0),
            "success")
    else
        local err = buyRes and buyRes.error or "Hiba a vásárlás során."
        TriggerEvent("nyx:core:client:notify", string.format("Vásárlás sikertelen: %s", err), "error")
    end
end)

RegisterNetEvent("nyx:logistics:client:promptShelfRestock", function(shelfId)
    local shelf = Nyx.Logistics.ClientShelves[shelfId]
    if not shelf then
        refreshClientShelves()
        Wait(200)
        shelf = Nyx.Logistics.ClientShelves[shelfId]
    end

    if not shelf then
        TriggerEvent("nyx:core:client:notify", "A polc adatai nem tölthetők be.", "error")
        return
    end

    -- Trigger restock RPC for default batch (10 units or remaining headroom)
    local restockRes = exports['nyx_core']:TriggerRPCAwait("logistics:restockShelf", shelfId, 10)
    if restockRes and restockRes.success then
        TriggerEvent("nyx:core:client:notify",
            string.format("Polc feltöltve: +%dx %s! Nagykereskedelmi jutalom: $%.2f.",
                restockRes.restockedQuantity, shelf.itemId or "áru", restockRes.wholesalePayout or 0.0),
            "success")
    else
        local err = restockRes and restockRes.error or "Sikertelen feltöltés."
        TriggerEvent("nyx:core:client:notify", string.format("Készletfeltöltés elutasítva: %s", err), "error")
    end
end)

RegisterNetEvent("nyx:logistics:client:showShelfInfo", function(shelfId)
    local shelf = Nyx.Logistics.ClientShelves[shelfId]
    if not shelf then return end

    local stock = shelf.currentStock or 0
    local cap = shelf.targetCapacity or 100
    local price = shelf.unitPrice or 10.0
    local state = shelf.fullnessState or "FULL"

    TriggerEvent("nyx:core:client:notify",
        string.format("[%s] Készlet: %d/%d db | Ár: $%.2f | Állapot: %s",
            shelf.label or "Polc", stock, cap, price, state),
        "info")
end)

-- ----------------------------------------------------------------------------
-- 6. Player Commands
-- ----------------------------------------------------------------------------
RegisterCommand("retailshelves", function()
    local res = exports['nyx_core']:TriggerRPCAwait("logistics:getNearbyRetailShelves", 60.0)
    if res and res.success and res.shelves and #res.shelves > 0 then
        print("^2=== KÖZELI KISKERESKEDELMI POLCOK ===^7")
        for _, s in ipairs(res.shelves) do
            print(string.format("^3[%s]^7 %s - Készlet: %d/%d (%s) - Ár: $%.2f (Távolság: %.1fm)",
                s.shelfId, s.label, s.currentStock, s.targetCapacity, s.fullnessState, s.unitPrice, s.distance or 0.0))
        end
    else
        print("^1Nincsenek aktív kiskereskedelmi polcok a közeledben.^7")
    end
end, false)

RegisterCommand("restockshelf", function(source, args)
    local shelfId = args[1]
    local qty = tonumber(args[2]) or 5
    if not shelfId then
        print("^3Használat: /restockshelf [shelfId] [mennyiség]^7")
        return
    end

    local res = exports['nyx_core']:TriggerRPCAwait("logistics:restockShelf", shelfId, qty)
    if res and res.success then
        print(string.format("^2[Nyx:Logistics] Sikeres polcfeltöltés! +%dx áru, Kifizetés: $%.2f^7",
            res.restockedQuantity, res.wholesalePayout))
    else
        print(string.format("^1[Nyx:Logistics] Sikertelen polcfeltöltés: %s^7", tostring(res and res.error)))
    end
end, false)

-- ----------------------------------------------------------------------------
-- 7. Client Exports
-- ----------------------------------------------------------------------------
exports("GetClosestRetailShelf", function(maxDist)
    maxDist = tonumber(maxDist) or 10.0
    local ped = PlayerPedId()
    local pCoords = GetEntityCoords(ped)

    local bestShelf = nil
    local bestDist = maxDist + 0.1

    for shelfId, shelf in pairs(Nyx.Logistics.ClientShelves) do
        if shelf.coords then
            local isNear, dist = Nyx.RetailShelves.IsPointNearShelf(pCoords, shelf.coords, maxDist)
            if isNear and dist < bestDist then
                bestDist = dist
                bestShelf = shelf
            end
        end
    end

    return bestShelf, bestDist
end)

exports("GetNearbyRetailShelves", function(maxDist)
    local res = exports['nyx_core']:TriggerRPCAwait("logistics:getNearbyRetailShelves", maxDist or 50.0)
    return res and res.shelves or {}
end)

exports("GetRetailShelfVisualState", function(shelfId)
    local shelf = Nyx.Logistics.ClientShelves[shelfId]
    if not shelf then return nil end
    local stock = shelf.currentStock or 0
    return {
        shelfId = shelfId,
        stock = stock,
        activeModel = Nyx.RetailShelves.ResolveShelfPropModel(shelf, stock),
        fullnessState = Nyx.RetailShelves.GetFullnessState(stock, shelf.targetCapacity or 100),
        isSpawned = (Nyx.Logistics.SpawnedEntities[shelfId] ~= nil)
    }
end)

-- ----------------------------------------------------------------------------
-- 8. Clean Resource Teardown
-- ----------------------------------------------------------------------------
AddEventHandler("onResourceStop", function(resName)
    if resName == GetCurrentResourceName() then
        streamingActive = false
        for shelfId, _ in pairs(Nyx.Logistics.SpawnedEntities) do
            despawnShelfEntity(shelfId)
        end
        Nyx.Logistics.SpawnedEntities = {}
    end
end)
