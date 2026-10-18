--[[
    Nyxframework: nyx_logistics
    File: shared/retail_shelves.lua
    Description: Pure Lua 5.4 deterministic algorithms for in-world retail point-of-sale displays,
                 fullness state classification, dynamic empty shelf prop resolution,
                 manual player restocking evaluation, and double-entry wholesale consignment payouts.
]]

Nyx = Nyx or {}
Nyx.RetailShelves = Nyx.RetailShelves or {}

-- ----------------------------------------------------------------------------
-- 1. Statutory Constants & Parameters
-- ----------------------------------------------------------------------------
Nyx.RetailShelves.WholesalePayoutMargin = 0.70       -- Supplier / restocker receives 70% of base price
Nyx.RetailShelves.SparseCapacityThreshold = 0.50     -- Stock below 50% capacity is classified as SPARSE
Nyx.RetailShelves.CriticalEmptyThreshold = 0.10     -- Stock at or below 10% generates urgent freight notices
Nyx.RetailShelves.MaxInteractionDistance = 2.50      -- Maximum distance (meters) for Third-Eye interactions
Nyx.RetailShelves.StreamingRadius = 45.00            -- World streaming distance for spawning retail shelf props
Nyx.RetailShelves.DefaultStockedModel = "prop_shelves_02"
Nyx.RetailShelves.DefaultEmptyModel = "prop_rack_empty"

-- ----------------------------------------------------------------------------
-- 2. Retail Category Taxonomy
-- ----------------------------------------------------------------------------
Nyx.RetailShelves.Categories = {
    ['convenience'] = {
        label = "Vegyesbolt & Élelmiszer",
        icon = "shopping-basket",
        color = "#10B981"
    },
    ['hardware'] = {
        label = "Barkács & Ipari Szerszámok",
        icon = "wrench",
        color = "#F59E0B"
    },
    ['arms'] = {
        label = "Fegyver & Lőszerbolt",
        icon = "shield-halved",
        color = "#EF4444"
    },
    ['pharmacy'] = {
        label = "Gyógyszertár & Kórházi Ellátmány",
        icon = "kit-medical",
        color = "#3B82F6"
    },
    ['electronics'] = {
        label = "Elektronika & Híradástechnika",
        icon = "microchip",
        color = "#8B5CF6"
    },
    ['general'] = {
        label = "Általános Kiskereskedelem",
        icon = "store",
        color = "#6B7280"
    }
}

-- ----------------------------------------------------------------------------
-- 3. Fullness State Classifier
-- ----------------------------------------------------------------------------
--- Evaluates current shelf inventory stock against target capacity
--- Returns: state ('FULL' | 'SPARSE' | 'EMPTY'), fillRatio, deficitUnits
function Nyx.RetailShelves.GetFullnessState(currentStock, targetCapacity)
    local stock = math.max(0, math.floor(tonumber(currentStock) or 0))
    local capacity = math.max(1, math.floor(tonumber(targetCapacity) or 100))

    local fillRatio = math.floor((stock / capacity) * 10000) / 10000
    local deficitUnits = math.max(0, capacity - stock)

    if stock <= 0 then
        return "EMPTY", fillRatio, deficitUnits
    elseif fillRatio < Nyx.RetailShelves.SparseCapacityThreshold then
        return "SPARSE", fillRatio, deficitUnits
    else
        return "FULL", fillRatio, deficitUnits
    end
end

-- ----------------------------------------------------------------------------
-- 4. Dynamic In-World Prop Model Resolver
-- ----------------------------------------------------------------------------
--- Resolves which physical GTA entity model should be displayed in the world
--- When stock is 0, swaps to empty_model (or despawns/empties)
function Nyx.RetailShelves.ResolveShelfPropModel(shelf, currentStock)
    if not shelf or type(shelf) ~= "table" then
        return Nyx.RetailShelves.DefaultStockedModel
    end

    local stock = tonumber(currentStock) or tonumber(shelf.current_stock) or 0
    local state = Nyx.RetailShelves.GetFullnessState(stock, shelf.target_capacity)

    if state == "EMPTY" then
        return shelf.empty_model or Nyx.RetailShelves.DefaultEmptyModel
    else
        return shelf.stocked_model or Nyx.RetailShelves.DefaultStockedModel
    end
end

-- ----------------------------------------------------------------------------
-- 5. Wholesale Restock Evaluation Engine
-- ----------------------------------------------------------------------------
--- Evaluates whether a player can restock a retail shelf from inventory
--- Returns: ok (bool), resultOrError (table | string)
function Nyx.RetailShelves.EvaluateRestock(shelf, playerItemCount, requestedQty)
    if not shelf or type(shelf) ~= "table" then
        return false, "INVALID_SHELF_DATA"
    end

    if shelf.is_restockable == 0 or shelf.is_restockable == false then
        return false, "SHELF_NOT_RESTOCKABLE"
    end

    local playerItems = math.max(0, math.floor(tonumber(playerItemCount) or 0))
    if playerItems <= 0 then
        return false, "INSUFFICIENT_ITEMS_IN_INVENTORY"
    end

    local currentStock = math.max(0, math.floor(tonumber(shelf.current_stock) or 0))
    local capacity = math.max(1, math.floor(tonumber(shelf.target_capacity) or 100))
    local headroom = capacity - currentStock

    if headroom <= 0 then
        return false, "SHELF_ALREADY_AT_FULL_CAPACITY"
    end

    local req = math.max(1, math.floor(tonumber(requestedQty) or headroom))
    local allowedQty = math.min(req, math.min(playerItems, headroom))

    if allowedQty <= 0 then
        return false, "RESTOCK_QUANTITY_ZERO"
    end

    local basePrice = math.max(1.0, tonumber(shelf.base_price) or 10.0)
    local wholesalePayout = math.floor((basePrice * Nyx.RetailShelves.WholesalePayoutMargin * allowedQty) * 100) / 100
    local newStock = currentStock + allowedQty

    return true, {
        quantity = allowedQty,
        headroomRemaining = headroom - allowedQty,
        wholesalePayout = wholesalePayout,
        previousStock = currentStock,
        newStock = newStock,
        basePrice = basePrice,
        shelfId = shelf.shelf_id or shelf.id,
        itemId = shelf.item_id
    }
end

-- ----------------------------------------------------------------------------
-- 6. Spatial Proximity & Heading Calculations
-- ----------------------------------------------------------------------------
--- Checks if a given 3D coordinate is within interaction distance of a shelf
function Nyx.RetailShelves.IsPointNearShelf(point, shelfCoords, maxDist)
    if not point or not shelfCoords then return false end
    maxDist = tonumber(maxDist) or Nyx.RetailShelves.MaxInteractionDistance

    local px, py, pz = point.x or 0.0, point.y or 0.0, point.z or 0.0
    local sx, sy, sz = shelfCoords.x or 0.0, shelfCoords.y or 0.0, shelfCoords.z or 0.0

    local dx = px - sx
    local dy = py - sy
    local dz = pz - sz
    local distSq = (dx * dx) + (dy * dy) + (dz * dz)

    return (distSq <= (maxDist * maxDist)), math.sqrt(distSq)
end

-- ----------------------------------------------------------------------------
-- 7. UI / Telemetry Summary Formatter
-- ----------------------------------------------------------------------------
--- Formats localized metadata badges and presentation strings for client UI
function Nyx.RetailShelves.FormatShelfDisplay(shelf, currentStock, currentPrice)
    local stock = math.max(0, math.floor(tonumber(currentStock) or 0))
    local capacity = math.max(1, math.floor(tonumber(shelf and shelf.target_capacity) or 100))
    local price = math.floor((tonumber(currentPrice) or tonumber(shelf and shelf.base_price) or 10.0) * 100) / 100

    local state, fillRatio, deficit = Nyx.RetailShelves.GetFullnessState(stock, capacity)
    local categoryKey = (shelf and shelf.shelf_category) or "general"
    local catInfo = Nyx.RetailShelves.Categories[categoryKey] or Nyx.RetailShelves.Categories['general']

    local badgeLabel = "TELJES KÉSZLET"
    local badgeClass = "badge-success"
    local badgeColor = "#10B981"

    if state == "EMPTY" then
        badgeLabel = "TELJESEN KIÜRÜLT"
        badgeClass = "badge-danger"
        badgeColor = "#EF4444"
    elseif state == "SPARSE" then
        badgeLabel = "FOGYÓBAN LÉVŐ KÉSZLET"
        badgeClass = "badge-warning"
        badgeColor = "#F59E0B"
    end

    local wholesaleRate = math.floor((tonumber(shelf and shelf.base_price or 10.0) * Nyx.RetailShelves.WholesalePayoutMargin) * 100) / 100

    return {
        shelfId = shelf and (shelf.shelf_id or shelf.id) or "unknown_shelf",
        label = shelf and shelf.shelf_label or "Kiskereskedelmi Polc",
        storeId = shelf and shelf.store_id or "store_general",
        itemId = shelf and shelf.item_id or "item_unknown",
        category = categoryKey,
        categoryLabel = catInfo.label,
        categoryColor = catInfo.color,
        currentStock = stock,
        targetCapacity = capacity,
        fillRatio = fillRatio,
        deficitUnits = deficit,
        unitPrice = price,
        wholesaleRestockRate = wholesaleRate,
        fullnessState = state,
        badge = {
            label = badgeLabel,
            badgeClass = badgeClass,
            color = badgeColor
        }
    }
end
