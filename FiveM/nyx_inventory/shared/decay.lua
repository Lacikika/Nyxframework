--[[
    Nyxframework: nyx_inventory
    File: shared/decay.lua
    Description: Authoritative time-based item durability degradation engine,
                 container environmental multipliers, status transitions, and repair mechanics.
]]

Nyx = Nyx or {}
Nyx.Decay = Nyx.Decay or {}

-- Durability Tier Status Constants
Nyx.Decay.STATUS_PRISTINE = "PRISTINE" -- >= 75.0%
Nyx.Decay.STATUS_GOOD     = "GOOD"     -- 50.0% - 74.9%
Nyx.Decay.STATUS_WORN     = "WORN"     -- 25.0% - 49.9%
Nyx.Decay.STATUS_CRITICAL = "CRITICAL" -- 0.1% - 24.9%
Nyx.Decay.STATUS_BROKEN   = "BROKEN"   -- <= 0.0% (weapons/tools)
Nyx.Decay.STATUS_SPOILED  = "SPOILED"  -- <= 0.0% (food/drink)
Nyx.Decay.STATUS_EXPIRED  = "EXPIRED"  -- <= 0.0% (medical)

-- Default Container Decay Multipliers (Ground drops weather much faster)
Nyx.Decay.DefaultMultipliers = {
    ['drop']     = 2.0,  -- Open world terrain, rain, UV, insects
    ['player']   = 1.0,  -- Carried in player pocket/backpack
    ['trunk']    = 0.75, -- Vehicle trunk, sheltered from elements
    ['glovebox'] = 0.75, -- Vehicle interior glovebox
    ['stash']    = 0.50  -- Climate-controlled warehouse shelf, home stash
}

-- Retrieve container decay rate multiplier based on container archetype
function Nyx.Decay.GetContainerMultiplier(containerType)
    if Config and Config.DecayMultipliers and Config.DecayMultipliers[containerType] then
        return tonumber(Config.DecayMultipliers[containerType]) or 1.0
    end
    return Nyx.Decay.DefaultMultipliers[containerType] or 1.0
end

-- Calculate numerical durability loss over elapsed deltaSeconds
-- Formula: loss = (deltaSeconds / 3600.0) * decayRate * 100.0 * containerMultiplier * envFactor
function Nyx.Decay.CalculateDecayLoss(decayRate, deltaSeconds, containerType, envFactor)
    decayRate = tonumber(decayRate) or 0.0
    deltaSeconds = math.max(0, tonumber(deltaSeconds) or 0)
    if decayRate <= 0 or deltaSeconds <= 0 then
        return 0.0
    end

    local cMult = Nyx.Decay.GetContainerMultiplier(containerType)
    local eMult = math.max(0.1, tonumber(envFactor) or 1.0)
    local rawLoss = (deltaSeconds / 3600.0) * decayRate * 100.0 * cMult * eMult
    return math.max(0.0, math.floor(rawLoss * 10) / 10)
end

-- Determine current durability tier status and flag states
function Nyx.Decay.GetItemStatus(item)
    if not item or type(item.metadata) ~= "table" then
        return Nyx.Decay.STATUS_PRISTINE, { isBroken = false, isSpoiled = false, isExpired = false }
    end

    local dur = tonumber(item.metadata.durability)
    if dur == nil then dur = 100.0 end

    local itemDef = Nyx.Items and Nyx.Items.Get and Nyx.Items.Get(item.item_id)
    local itemType = itemDef and itemDef.type or "general"

    local isBroken = (item.metadata.isBroken == true) or (dur <= 0.0 and (itemType == "weapon" or itemType == "tool"))
    local isSpoiled = (item.metadata.isSpoiled == true) or (dur <= 0.0 and (itemType == "food" or itemType == "drink"))
    local isExpired = (item.metadata.isExpired == true) or (dur <= 0.0 and itemType == "medical")

    if dur <= 0.0 then
        if itemType == "food" or itemType == "drink" then
            return Nyx.Decay.STATUS_SPOILED, { isBroken = false, isSpoiled = true, isExpired = false }
        elseif itemType == "medical" then
            return Nyx.Decay.STATUS_EXPIRED, { isBroken = false, isSpoiled = false, isExpired = true }
        else
            return Nyx.Decay.STATUS_BROKEN, { isBroken = true, isSpoiled = false, isExpired = false }
        end
    elseif dur < 25.0 then
        return Nyx.Decay.STATUS_CRITICAL, { isBroken = false, isSpoiled = false, isExpired = false }
    elseif dur < 50.0 then
        return Nyx.Decay.STATUS_WORN, { isBroken = false, isSpoiled = false, isExpired = false }
    elseif dur < 75.0 then
        return Nyx.Decay.STATUS_GOOD, { isBroken = false, isSpoiled = false, isExpired = false }
    else
        return Nyx.Decay.STATUS_PRISTINE, { isBroken = false, isSpoiled = false, isExpired = false }
    end
end

-- Apply time degradation to a single discrete item in-place
-- Returns: hasChanged, prevDurability, newDurability, statusChanged, status
function Nyx.Decay.ApplyDecayToItem(item, deltaSeconds, containerType, envFactor)
    if not item or type(item.metadata) ~= "table" then
        return false, 100.0, 100.0, false, Nyx.Decay.STATUS_PRISTINE
    end

    local itemDef = Nyx.Items and Nyx.Items.Get and Nyx.Items.Get(item.item_id)
    local decayRate = tonumber(item.metadata.decayRate) or (itemDef and tonumber(itemDef.decayRate)) or 0.0
    local curDur = tonumber(item.metadata.durability)
    if curDur == nil then
        curDur = 100.0
        item.metadata.durability = 100.0
    end

    if decayRate <= 0.0 or curDur <= 0.0 then
        local st, flags = Nyx.Decay.GetItemStatus(item)
        return false, curDur, curDur, false, st
    end

    local loss = Nyx.Decay.CalculateDecayLoss(decayRate, deltaSeconds, containerType, envFactor)
    if loss <= 0.0 then
        local st, flags = Nyx.Decay.GetItemStatus(item)
        return false, curDur, curDur, false, st
    end

    local newDur = math.max(0.0, math.floor((curDur - loss) * 10) / 10)
    if newDur == curDur then
        local st, flags = Nyx.Decay.GetItemStatus(item)
        return false, curDur, curDur, false, st
    end

    local prevStatus = Nyx.Decay.GetItemStatus(item)
    item.metadata.durability = newDur
    item.metadata.lastDecay = os.time()

    local itemType = itemDef and itemDef.type or "general"
    if newDur <= 0.0 then
        if itemType == "food" or itemType == "drink" then
            item.metadata.isSpoiled = true
        elseif itemType == "medical" then
            item.metadata.isExpired = true
        elseif itemType == "weapon" or itemType == "tool" then
            item.metadata.isBroken = true
        end
    end

    local newStatus, flags = Nyx.Decay.GetItemStatus(item)
    local statusChanged = (prevStatus ~= newStatus)

    return true, curDur, newDur, statusChanged, newStatus
end

-- Check if an item can be repaired with a maintenance tool or repair kit
function Nyx.Decay.CanRepairItem(item)
    if not item or type(item.metadata) ~= "table" then return false end
    local itemDef = Nyx.Items and Nyx.Items.Get and Nyx.Items.Get(item.item_id)
    if not itemDef then return false end

    -- Perishable consumables cannot be repaired
    if itemDef.type == "food" or itemDef.type == "drink" or itemDef.type == "ammo" or itemDef.type == "medical" then
        return false
    end

    -- Weapons, tools, and mechanical freight are repairable
    local isRepairableType = (itemDef.type == "weapon" or itemDef.type == "tool" or itemDef.type == "freight" or itemDef.isRepairable == true)
    if not isRepairableType then return false end

    local curDur = tonumber(item.metadata.durability) or 100.0
    local maxDur = tonumber(item.metadata.maxDurability) or 100.0

    return curDur < maxDur
end

-- Calculate repair gain and fatigue wear penalty
-- Each repair restores durability up to maxDurability, but incurs slight structural wear
function Nyx.Decay.CalculateRepairGain(targetItem, repairToolItem)
    if not targetItem or not Nyx.Decay.CanRepairItem(targetItem) then
        return 0.0, 0.0, 0.0
    end

    local curDur = tonumber(targetItem.metadata.durability) or 0.0
    local maxDur = tonumber(targetItem.metadata.maxDurability) or 100.0
    local baseGain = (Config and Config.RepairConfig and Config.RepairConfig.baseGain) or 35.0
    local wearPenalty = (Config and Config.RepairConfig and Config.RepairConfig.wearPenalty) or 2.0

    -- If repair tool has specialized power
    if repairToolItem and type(repairToolItem.metadata) == "table" and repairToolItem.metadata.repairPower then
        baseGain = tonumber(repairToolItem.metadata.repairPower) or baseGain
    end

    -- Wear penalty reduces maximum repair ceiling down to floor of 50%
    local newMaxDur = math.max(50.0, math.floor((maxDur - wearPenalty) * 10) / 10)
    local newDur = math.min(newMaxDur, math.floor((curDur + baseGain) * 10) / 10)
    local actualGain = math.max(0.0, math.floor((newDur - curDur) * 10) / 10)

    return actualGain, newDur, newMaxDur
end

-- Formatted text quality badge for UI and inspect displays
function Nyx.Decay.GetQualityLabel(durability, maxDurability)
    durability = tonumber(durability) or 100.0
    maxDurability = tonumber(maxDurability) or 100.0

    if durability <= 0.0 then
        return "0.0% [Broken / Depleted]"
    elseif durability < 25.0 then
        return string.format("%.1f%% [Critical]", durability)
    elseif durability < 50.0 then
        return string.format("%.1f%% [Worn]", durability)
    elseif durability < 75.0 then
        return string.format("%.1f%% [Good]", durability)
    else
        return string.format("%.1f%% [Pristine]", durability)
    end
end
