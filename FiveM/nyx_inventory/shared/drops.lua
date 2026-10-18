--[[
    Nyxframework: nyx_inventory
    File: shared/drops.lua
    Description: Smart fallback 3D model resolution based on item category and weight tiers.
]]

Nyx = Nyx or {}
Nyx.Drops = Nyx.Drops or {}

-- Retrieve weight-tiered fallback 3D model name based on category and total weight in grams
function Nyx.Drops.GetFallbackModel(category, weight)
    weight = tonumber(weight) or 0
    local cfg = Config.DropFallbackModels

    -- 1. Check category-specific rules if configured
    if cfg and cfg.categories and category and cfg.categories[category] then
        for _, tier in ipairs(cfg.categories[category]) do
            if weight <= tier.maxWeight then
                return tier.model
            end
        end
    end

    -- 2. General weight-tiered fallback
    if cfg and cfg.tiers then
        for _, tier in ipairs(cfg.tiers) do
            if weight <= tier.maxWeight then
                return tier.model
            end
        end
    end

    return Config.DropModel or "prop_paper_bag_small"
end

-- Resolve the optimal 3D world model for an item, container, or item stack
function Nyx.Drops.ResolveModel(source, amountOverride)
    if not source then
        return Config.DropModel or "prop_paper_bag_small"
    end

    -- CASE A: Single item name string (e.g. "weapon_pistol" or "refined_iron")
    if type(source) == "string" then
        local itemDef = Nyx.Items and Nyx.Items.Get and Nyx.Items.Get(source)
        if itemDef and itemDef.client and itemDef.client.model then
            return itemDef.client.model
        end
        local amount = tonumber(amountOverride) or 1
        local totalWeight = (Nyx.Items and Nyx.Items.GetWeight) and Nyx.Items.GetWeight(source, amount) or 0
        local category = itemDef and itemDef.type or "general"
        return Nyx.Drops.GetFallbackModel(category, totalWeight)
    end

    -- CASE B: Single item data table (e.g. { item_id = "...", amount = ..., metadata = ... })
    local itemId = source.item_id or source.itemId
    if itemId and (source.amount or amountOverride) and not source.items then
        local itemDef = Nyx.Items and Nyx.Items.Get and Nyx.Items.Get(itemId)
        if itemDef and itemDef.client and itemDef.client.model then
            return itemDef.client.model
        end
        local amount = tonumber(source.amount) or tonumber(amountOverride) or 1
        local totalWeight = (Nyx.Items and Nyx.Items.GetWeight) and Nyx.Items.GetWeight(itemId, amount) or 0
        local category = itemDef and itemDef.type or "general"
        return Nyx.Drops.GetFallbackModel(category, totalWeight)
    end

    -- CASE C: Container object or table of items (e.g. container.items)
    local items = source.items or source
    local totalWeight = 0
    local categoryWeights = {}
    local itemCount = 0
    local singleItemDef = nil

    if type(items) == "table" then
        for _, it in pairs(items) do
            if type(it) == "table" and (it.item_id or it.itemId) then
                local id = it.item_id or it.itemId
                local count = tonumber(it.amount) or 1
                local itWeight = (Nyx.Items and Nyx.Items.GetWeight) and Nyx.Items.GetWeight(id, count) or 0
                totalWeight = totalWeight + itWeight
                itemCount = itemCount + 1

                local def = Nyx.Items and Nyx.Items.Get and Nyx.Items.Get(id)
                if def then
                    singleItemDef = def
                    local cat = def.type or "general"
                    categoryWeights[cat] = (categoryWeights[cat] or 0) + (itWeight > 0 and itWeight or 100)
                end
            end
        end
    end

    -- If container has exactly 1 item and that item has a custom dedicated model, use it
    if itemCount == 1 and singleItemDef and singleItemDef.client and singleItemDef.client.model then
        return singleItemDef.client.model
    end

    -- If container has a dominant category by cumulative weight, use its category
    local dominantCategory = "general"
    local highestWeight = -1
    for cat, weight in pairs(categoryWeights) do
        if weight > highestWeight then
            highestWeight = weight
            dominantCategory = cat
        end
    end

    return Nyx.Drops.GetFallbackModel(dominantCategory, totalWeight)
end

-- Collect all unique fallback model names configured
function Nyx.Drops.GetAllFallbackModels()
    local models = {}
    local seen = {}

    local function addModel(name)
        if name and not seen[name] then
            seen[name] = true
            models[#models + 1] = name
        end
    end

    addModel(Config.DropModel or "prop_paper_bag_small")

    local cfg = Config.DropFallbackModels
    if cfg then
        if cfg.categories then
            for _, tierList in pairs(cfg.categories) do
                for _, tier in ipairs(tierList) do
                    addModel(tier.model)
                end
            end
        end
        if cfg.tiers then
            for _, tier in ipairs(cfg.tiers) do
                addModel(tier.model)
            end
        end
    end

    return models
end
