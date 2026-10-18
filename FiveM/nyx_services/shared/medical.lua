--[[
    Nyxframework: nyx_services
    File: shared/medical.lua
    Description: Pure Lua 5.4 specifications, hospital stash container mappings,
                 supply status evaluations, shortage penalties, and emergency contract models.
]]

Nyx = Nyx or {}
Nyx.HospitalSupplies = {}

-- Canonical Container IDs
Nyx.HospitalSupplies.CanonicalPillboxStash = "stash:pillbox_meds"

-- Static Hospital to Stash Mappings
Nyx.HospitalSupplies.HospitalStashMap = {
    ['pillbox_hill'] = "stash:pillbox_meds",
    ['sandy_shores_clinic'] = "stash:sandy_clinic_meds",
    ['paleto_bay_hospital'] = "stash:paleto_hospital_meds"
}

-- Inverse Stash to Hospital Mappings
Nyx.HospitalSupplies.StashHospitalMap = {
    ['stash:pillbox_meds'] = "pillbox_hill",
    ['stash:sandy_clinic_meds'] = "sandy_shores_clinic",
    ['stash:paleto_hospital_meds'] = "paleto_bay_hospital"
}

-- Tracked Clinical Consumables & Target Reserves
Nyx.HospitalSupplies.TrackedItems = {
    ['med_plasma'] = {
        key = "sterilePlasma",
        label = "Sterile Blood Plasma Unit",
        weight = 500,
        criticalMin = 5,
        degradedMin = 15,
        targetStock = 50,
        isCore = true
    },
    ['med_firstaid'] = {
        key = "traumaKits",
        label = "Trauma First Aid Kit",
        weight = 1200,
        criticalMin = 5,
        degradedMin = 15,
        targetStock = 40,
        isCore = true
    },
    ['med_surgical_pack'] = {
        key = "surgicalPacks",
        label = "Sterile Surgical Pack",
        weight = 1500,
        criticalMin = 3,
        degradedMin = 8,
        targetStock = 25,
        isCore = true
    },
    ['bandage_sterile'] = {
        key = "sterileBandages",
        label = "Sterile Pressure Bandage",
        weight = 100,
        criticalMin = 10,
        degradedMin = 25,
        targetStock = 80,
        isCore = false
    },
    ['tourniquet'] = {
        key = "tourniquets",
        label = "Combat Application Tourniquet",
        weight = 150,
        criticalMin = 5,
        degradedMin = 12,
        targetStock = 30,
        isCore = false
    }
}

-- Priority Emergency Freight Parameters
Nyx.HospitalSupplies.EmergencyFreightConfig = {
    BaseBountyMultiplier = 1.85,     -- 1.85x base freight payout for emergency medical hauls
    MaxBountyMultiplier = 2.75,      -- Cap for maximum emergency shortage surge
    DefaultQuantity = 25,            -- Units per standard emergency restock manifest
    DefaultDeadlineSeconds = 900,    -- 15 minutes expedited courier deadline
    EscrowRate = 0.15,               -- 15% escrow collateral
    HazardBasePrice = 120.00         -- Base value per medical unit
}

-- 1. Resolve Stash ID for a given hospital
function Nyx.HospitalSupplies.GetStashIdForHospital(hospitalId)
    if not hospitalId then return Nyx.HospitalSupplies.CanonicalPillboxStash end
    return Nyx.HospitalSupplies.HospitalStashMap[hospitalId] or string.format("stash:%s_meds", hospitalId)
end

-- 2. Resolve Hospital ID for a given stash ID
function Nyx.HospitalSupplies.GetHospitalIdForStash(stashId)
    if not stashId then return "pillbox_hill" end
    return Nyx.HospitalSupplies.StashHospitalMap[stashId] or "pillbox_hill"
end

-- 3. Evaluate Supply Level and Classify Shortage Status
function Nyx.HospitalSupplies.EvaluateSupplyLevel(countsTable, customThresholds)
    countsTable = countsTable or {}
    customThresholds = customThresholds or {}

    local critThresh = tonumber(customThresholds.critical) or 5
    local degThresh = tonumber(customThresholds.degraded) or 15

    local plasma = tonumber(countsTable['med_plasma']) or 0
    local trauma = tonumber(countsTable['med_firstaid']) or tonumber(countsTable['first_aid_pack']) or 0
    local surgery = tonumber(countsTable['med_surgical_pack']) or 0

    local isCritical = (plasma <= critThresh) or (trauma <= critThresh) or (surgery <= 1)
    local isDegraded = (plasma <= degThresh) or (trauma <= degThresh) or (surgery <= 3)

    local status = "optimal"
    if isCritical then
        status = "critical_shortage"
    elseif isDegraded then
        status = "degraded"
    end

    -- Compute composite medical readiness percentage (0.0% to 100.0%)
    local totalRatio = 0.0
    local itemsChecked = 0
    local deficits = {}

    for itemId, def in pairs(Nyx.HospitalSupplies.TrackedItems) do
        local cur = tonumber(countsTable[itemId]) or 0
        local ratio = math.min(1.0, cur / math.max(1, def.targetStock))
        totalRatio = totalRatio + ratio
        itemsChecked = itemsChecked + 1

        if cur <= def.degradedMin then
            deficits[itemId] = {
                current = cur,
                target = def.targetStock,
                needed = math.max(0, def.targetStock - cur),
                label = def.label,
                isCritical = (cur <= def.criticalMin)
            }
        end
    end

    local readinessPercent = itemsChecked > 0 and math.floor((totalRatio / itemsChecked) * 1000) / 10 or 100.0

    return status, {
        readinessPercent = readinessPercent,
        plasma = plasma,
        traumaKits = trauma,
        surgicalPacks = surgery,
        deficits = deficits,
        isSurgicalAvailable = (surgery > 0),
        status = status
    }
end

-- 4. Calculate Respawn Penalty Seconds based on Facility Status and Electrical Grid State
function Nyx.HospitalSupplies.CalculateRespawnPenalty(status, isPowered)
    local penalties = {
        optimal = 0,
        degraded = 30,
        critical_shortage = 60
    }
    local basePenalty = penalties[status] or 0
    if not isPowered then
        basePenalty = basePenalty + 30 -- Emergency backup generator delay
    end
    return basePenalty
end

-- 5. Calculate Emergency Logistics Haul Contract Specifications
function Nyx.HospitalSupplies.CalculateEmergencyContract(hospitalId, itemId, currentStock, customQty, customTarget)
    hospitalId = hospitalId or "pillbox_hill"
    itemId = itemId or "med_plasma"
    currentStock = math.max(0, tonumber(currentStock) or 0)

    local itemDef = Nyx.HospitalSupplies.TrackedItems[itemId] or Nyx.HospitalSupplies.TrackedItems['med_plasma']
    local targetStock = customTarget or itemDef.targetStock or 50
    local quantity = customQty or math.max(15, targetStock - currentStock)

    local deficitRatio = math.max(0.0, math.min(1.0, (targetStock - currentStock) / math.max(1, targetStock)))
    local cfg = Nyx.HospitalSupplies.EmergencyFreightConfig

    -- Hazard surge multiplier scales higher when supplies approach 0
    local surgeMultiplier = cfg.BaseBountyMultiplier + (deficitRatio * (cfg.MaxBountyMultiplier - cfg.BaseBountyMultiplier))
    local payoutPerUnit = math.floor((cfg.HazardBasePrice * surgeMultiplier) * 100 + 0.5) / 100
    local totalPayout = math.floor((payoutPerUnit * quantity) * 100 + 0.5) / 100
    local escrowBond = math.floor((totalPayout * cfg.EscrowRate) * 100 + 0.5) / 100

    local hospitalLabels = {
        ['pillbox_hill'] = "Pillbox Hill Medical Center",
        ['sandy_shores_clinic'] = "Mount Zonah Desert Clinic",
        ['paleto_bay_hospital'] = "Paleto Bay Emergency Care"
    }
    local hospLabel = hospitalLabels[hospitalId] or "Municipal Hospital"

    return {
        hospitalId = hospitalId,
        itemId = itemId,
        itemLabel = itemDef.label,
        quantity = quantity,
        payoutPerUnit = payoutPerUnit,
        totalPayout = totalPayout,
        escrowDeposit = escrowBond,
        deadlineSeconds = cfg.DefaultDeadlineSeconds,
        title = string.format("Sürgősségi Orvosi Ellátmány: %s [%s]", itemDef.label, hospLabel),
        sourceInv = "stash:chemical_refinery",
        destInv = Nyx.HospitalSupplies.GetStashIdForHospital(hospitalId)
    }
end

-- 6. Validate Medical Supply Restock Items
function Nyx.HospitalSupplies.ValidateRestockItem(itemId, amount)
    if not itemId or type(itemId) ~= "string" then
        return false, "INVALID_ITEM_ID"
    end
    amount = tonumber(amount)
    if not amount or amount <= 0 or math.floor(amount) ~= amount then
        return false, "INVALID_AMOUNT"
    end
    if not Nyx.HospitalSupplies.TrackedItems[itemId] then
        return false, "UNTRACKED_MEDICAL_SUPPLY_ITEM"
    end
    return true, { itemId = itemId, amount = amount }
end

-- 7. Format UI Status Badge and Color Coding
function Nyx.HospitalSupplies.FormatSupplyBadge(status)
    local badges = {
        ['optimal'] = {
            class = "badge-success",
            label = "ELLÁTÁS OPTIMÁLIS",
            color = "#10B981",
            description = "Teljes orvosi és sebészeti kapacitás aktív."
        },
        ['degraded'] = {
            class = "badge-warning",
            label = "KÉSZLETHIÁNY",
            color = "#F59E0B",
            description = "Csökkentett készletszintek. Újraélesztési késleltetés +30mp."
        },
        ['critical_shortage'] = {
            class = "badge-danger",
            label = "KRITIKUS HIÁNYÁLLAPOT",
            color = "#EF4444",
            description = "Kritikus orvosi hiány! Sürgősségi futárszolgálati szerződés aktív."
        }
    }
    return badges[status] or badges['optimal']
end

-- 8. Format Structured Stock Diagnostics String
function Nyx.HospitalSupplies.FormatStockSummary(countsTable)
    countsTable = countsTable or {}
    local lines = {}
    for itemId, def in pairs(Nyx.HospitalSupplies.TrackedItems) do
        local count = tonumber(countsTable[itemId]) or 0
        local tag = (count <= def.criticalMin) and "[KRITIKUS]" or (count <= def.degradedMin and "[ALACSONY]" or "[OK]")
        table.insert(lines, string.format("• %s: %d/%d %s", def.label, count, def.targetStock, tag))
    end
    return table.concat(lines, "\n")
end
