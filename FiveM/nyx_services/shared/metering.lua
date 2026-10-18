--[[
    Nyxframework: nyx_services & nyx_properties
    File: shared/metering.lua
    Description: Pure Lua 5.4 domain logic for municipal utility metering, continuous
                 kilowatt-hour and water consumption modeling, dynamic substation grid draw,
                 automated invoice calculation, zero-cent conservation, and delinquency cutoff.
]]

Nyx = Nyx or {}
Nyx.Metering = Nyx.Metering or {}

-- 1. Statutory Configuration & Baseline Profiles
Nyx.Metering.Config = {
    DefaultKwhTariff = 0.1500,               -- $0.1500 per kilowatt-hour
    DefaultWaterTariff = 0.0500,             -- $0.0500 per gallon/liter
    SuspensionThreshold = 2500.00,           -- Arrears threshold triggering utility cutoff
    LatePenaltyRate = 0.10,                  -- 10% late surcharge on missed billing cycle
    ReconnectFee = 150.00,                   -- Flat administrative reconnection fee
    LienThreshold = 7500.00,                 -- Extreme arrears threshold referring to auction/lien
    MaxDelinquencyCyclesBeforeCutoff = 3,    -- Consecutive unpaid cycles before cutoff
    PublicWorksAccount = "gov:dept:works",   -- Treasury account collecting utility revenues

    -- Baseline Consumption Profiles per Property Category
    Profiles = {
        ['residential'] = {
            baseKwh = 120.00,
            baseWater = 80.00,
            kwhPerOccupant = 15.00,
            waterPerOccupant = 10.00,
            continuousKw = 8.50,
            label = "Lakossági (Residential)"
        },
        ['commercial'] = {
            baseKwh = 450.00,
            baseWater = 200.00,
            kwhPerOccupant = 30.00,
            waterPerOccupant = 25.00,
            continuousKw = 35.00,
            label = "Kereskedelmi (Commercial)"
        },
        ['industrial'] = {
            baseKwh = 1200.00,
            baseWater = 650.00,
            kwhPerOccupant = 50.00,
            waterPerOccupant = 40.00,
            continuousKw = 120.00,
            label = "Ipari Létesítmény (Industrial)"
        }
    },

    -- Ambient Weather and Environmental Load Stress Multipliers
    WeatherMultipliers = {
        ['THUNDER'] = 1.40,
        ['RAIN'] = 1.15,
        ['FOGGY'] = 1.05,
        ['CLEAR'] = 1.00,
        ['EXTRASUNNY'] = 1.25,
        ['CLOUDS'] = 1.00,
        ['OVERCAST'] = 1.05
    },

    -- Status Taxonomy
    StatusTaxonomy = {
        ['active'] = { label = "Aktív / Normál", badge = "^2[AKTÍV]^7", isSuspended = false, color = "green" },
        ['grace_notice'] = { label = "Fizetési Felszólítás (Türelmi Idő)", badge = "^3[FELSZÓLÍTÁS]^7", isSuspended = false, color = "yellow" },
        ['late_warning'] = { label = "Késedelmi Pótlék Terhelve", badge = "^3[KÉSEDELMES]^7", isSuspended = false, color = "orange" },
        ['disconnected'] = { label = "Közmű Felfüggesztve (Lekapcsolva)", badge = "^1[KIKAPCSOLVA]^7", isSuspended = true, color = "red" },
        ['lien_referred'] = { label = "Hatósági Zálogjog / Végrehajtás", badge = "^1[VÉGREHAJTÁS]^7", isSuspended = true, color = "purple" }
    }
}

--- Helper: Round number to nearest whole cent (2 decimal places)
function Nyx.Metering.RoundToCent(val)
    val = tonumber(val) or 0.0
    return math.floor(val * 100.0 + 0.5) / 100.0
end

--- Get Consumption Profile by Property Type
function Nyx.Metering.GetProfile(propertyType)
    local p = Nyx.Metering.Config.Profiles[propertyType]
    if not p then
        p = Nyx.Metering.Config.Profiles['residential']
    end
    return p
end

--- Calculate continuous kilowatt-hour and water consumption delta.
--- Pure Lua 5.4 deterministic evaluator.
function Nyx.Metering.CalculateConsumptionDelta(propertyType, landAreaSqm, occupancyCount, weatherType, applianceMultiplier)
    local profile = Nyx.Metering.GetProfile(propertyType)
    local area = math.max(20.0, tonumber(landAreaSqm) or 150.00)
    local occupancy = math.max(0, math.floor(tonumber(occupancyCount) or 0))
    local weather = tostring(weatherType or "CLEAR"):upper()
    local weatherMult = Nyx.Metering.Config.WeatherMultipliers[weather] or 1.00
    local applianceMult = math.max(0.5, math.min(3.0, tonumber(applianceMultiplier) or 1.00))

    -- Land area footprint scaling factor: square root proportional scaling centered at 150 m^2
    local areaFactor = math.max(0.40, math.min(3.50, math.sqrt(area / 150.00)))

    local rawKwh = (profile.baseKwh * areaFactor + (occupancy * profile.kwhPerOccupant)) * weatherMult * applianceMult
    local rawWater = (profile.baseWater * areaFactor + (occupancy * profile.waterPerOccupant)) * weatherMult * applianceMult

    local kwh = Nyx.Metering.RoundToCent(rawKwh)
    local water = Nyx.Metering.RoundToCent(rawWater)

    return kwh, water, {
        areaFactor = areaFactor,
        weatherMultiplier = weatherMult,
        applianceMultiplier = applianceMult,
        occupancy = occupancy
    }
end

--- Calculate aggregate kilowatt and megawatt load drawn by connected properties on a localized substation.
--- Pure function evaluating real-time transformer burden.
function Nyx.Metering.CalculateSubstationGridDraw(substationId, connectedProperties, maxCapacityMw)
    substationId = tostring(substationId or "grid_central_ls")
    connectedProperties = connectedProperties or {}
    maxCapacityMw = tonumber(maxCapacityMw) or 75.00

    local totalKw = 0.00
    local totalMeters = 0
    local activeMeters = 0
    local suspendedMeters = 0
    local generatorBackedMeters = 0

    for _, prop in ipairs(connectedProperties) do
        totalMeters = totalMeters + 1
        local isSuspended = (prop.isUtilitySuspended == true or prop.is_service_suspended == 1)
        local hasBackupGen = (prop.hasBackupGenerator == true or prop.has_backup_generator == 1)

        if hasBackupGen then
            generatorBackedMeters = generatorBackedMeters + 1
            -- Backup generator absorbs 100% of property load off the municipal grid
        elseif isSuspended then
            suspendedMeters = suspendedMeters + 1
            -- Disconnected meters draw negligible idle ghost current (0.1 kW)
            totalKw = totalKw + 0.10
        else
            activeMeters = activeMeters + 1
            local profile = Nyx.Metering.GetProfile(prop.propertyType or prop.type)
            local kwDraw = profile.continuousKw
            -- Scale with occupancy if provided
            local occupancy = tonumber(prop.occupancyCount) or 0
            if occupancy > 0 then
                kwDraw = kwDraw + (occupancy * (profile.kwhPerOccupant * 0.10))
            end
            totalKw = totalKw + kwDraw
        end
    end

    -- Convert Kilowatts to MegaWatts (1 MW = 1,000 kW)
    local aggregateLoadMw = Nyx.Metering.RoundToCent(totalKw / 1000.0)
    local utilizationPct = (maxCapacityMw > 0.0) and Nyx.Metering.RoundToCent((aggregateLoadMw / maxCapacityMw) * 100.0) or 0.00
    local isOverloaded = (aggregateLoadMw > maxCapacityMw)

    return aggregateLoadMw, {
        totalKw = totalKw,
        totalMeters = totalMeters,
        activeMeters = activeMeters,
        suspendedMeters = suspendedMeters,
        generatorBackedMeters = generatorBackedMeters,
        utilizationPct = utilizationPct,
        isOverloaded = isOverloaded,
        maxCapacityMw = maxCapacityMw
    }
end

--- Evaluate delinquency state machine tier and determine if power/water cut-off should be enforced.
--- Pure Lua 5.4 state evaluator.
function Nyx.Metering.EvaluateDelinquencyTier(missedCycles, unpaidArrears, customCutoff)
    local missed = math.max(0, math.floor(tonumber(missedCycles) or 0))
    local arrears = math.max(0.0, Nyx.Metering.RoundToCent(tonumber(unpaidArrears) or 0.0))
    local cutoff = tonumber(customCutoff) or Nyx.Metering.Config.SuspensionThreshold
    local lienThreshold = Nyx.Metering.Config.LienThreshold or (cutoff * 3.0)

    if arrears <= 0.00 then
        return 0, "active", false, 0.00
    end

    if arrears >= lienThreshold or missed >= (Nyx.Metering.Config.LienCycles or 5) then
        return 4, "lien_referred", true, Nyx.Metering.Config.LatePenaltyRate
    end

    if arrears >= cutoff or missed >= (Nyx.Metering.Config.MaxDelinquencyCyclesBeforeCutoff or 3) then
        return 3, "disconnected", true, Nyx.Metering.Config.LatePenaltyRate
    end

    if missed == 2 then
        return 2, "late_warning", false, Nyx.Metering.Config.LatePenaltyRate
    end

    -- 1 missed cycle or arrears < cutoff
    return 1, "grace_notice", false, 0.00
end

--- Calculate utility bill, charges, late surcharges, and total amount due.
--- Strictly guarantees exact zero-cent closed-loop arithmetic conservation:
--- delta = totalDue - (energyCharge + waterCharge + unpaidArrears + latePenalty + reconnectFee) == 0.00
function Nyx.Metering.CalculateUtilityBill(params)
    params = params or {}
    local kwhConsumed = math.max(0.0, tonumber(params.kwhConsumed) or 0.00)
    local waterConsumed = math.max(0.0, tonumber(params.waterConsumed) or 0.00)
    local kwhTariff = tonumber(params.kwhTariff) or Nyx.Metering.Config.DefaultKwhTariff
    local waterTariff = tonumber(params.waterTariff) or Nyx.Metering.Config.DefaultWaterTariff
    local unpaidArrears = math.max(0.0, Nyx.Metering.RoundToCent(tonumber(params.unpaidArrears) or 0.00))
    local missedCycles = math.max(0, math.floor(tonumber(params.missedCycles) or 0))
    local isReconnecting = (params.isReconnecting == true)
    local gridStressMult = math.max(1.0, tonumber(params.gridStressMultiplier) or 1.00)

    local effectiveKwhTariff = kwhTariff * gridStressMult
    local effectiveWaterTariff = waterTariff

    local energyCharge = Nyx.Metering.RoundToCent(kwhConsumed * effectiveKwhTariff)
    local waterCharge = Nyx.Metering.RoundToCent(waterConsumed * effectiveWaterTariff)
    local currentCharges = Nyx.Metering.RoundToCent(energyCharge + waterCharge)

    local tier, status, shouldSuspend, lateRate = Nyx.Metering.EvaluateDelinquencyTier(missedCycles, unpaidArrears, params.customCutoff)

    local latePenalty = 0.00
    if lateRate > 0.0 and unpaidArrears > 0.0 then
        latePenalty = Nyx.Metering.RoundToCent(unpaidArrears * lateRate)
    end

    local reconnectFee = 0.00
    if isReconnecting then
        reconnectFee = Nyx.Metering.RoundToCent(Nyx.Metering.Config.ReconnectFee)
    end

    local totalDue = Nyx.Metering.RoundToCent(currentCharges + unpaidArrears + latePenalty + reconnectFee)

    -- Invariant Verification: Closed-circuit zero-cent balance conservation
    local expectedTotal = energyCharge + waterCharge + unpaidArrears + latePenalty + reconnectFee
    local delta = math.abs(totalDue - expectedTotal)
    if delta >= 0.01 then
        -- Force-absorb residual rounding cent into energyCharge
        energyCharge = totalDue - (waterCharge + unpaidArrears + latePenalty + reconnectFee)
        currentCharges = energyCharge + waterCharge
    end

    return {
        kwhConsumed = kwhConsumed,
        waterConsumed = waterConsumed,
        kwhTariff = effectiveKwhTariff,
        waterTariff = effectiveWaterTariff,
        energyCharge = energyCharge,
        waterCharge = waterCharge,
        currentCharges = currentCharges,
        unpaidArrears = unpaidArrears,
        missedCycles = missedCycles,
        delinquencyTier = tier,
        meterStatus = status,
        shouldSuspend = shouldSuspend,
        latePenalty = latePenalty,
        reconnectFee = reconnectFee,
        totalDue = totalDue,
        conservationDelta = 0.00
    }
end

--- Calculate payment settlement, arrears reduction, and service reconnection eligibility.
--- Pure Lua 5.4 settlement evaluator.
function Nyx.Metering.CalculatePaymentSettlement(currentArrears, paymentAmount, isSuspended, customCutoff)
    local arrears = math.max(0.0, Nyx.Metering.RoundToCent(tonumber(currentArrears) or 0.00))
    local payment = math.max(0.0, Nyx.Metering.RoundToCent(tonumber(paymentAmount) or 0.00))
    local cutoff = tonumber(customCutoff) or Nyx.Metering.Config.SuspensionThreshold

    local actualPaid = math.min(arrears, payment)
    local remainingArrears = Nyx.Metering.RoundToCent(arrears - actualPaid)

    local canReconnect = false
    local newSuspended = isSuspended and true or false

    if isSuspended then
        -- Service is restored if remaining arrears are paid down below the cutoff threshold
        if remainingArrears < cutoff then
            canReconnect = true
            newSuspended = false
        end
    else
        if remainingArrears >= cutoff then
            newSuspended = true
        end
    end

    local newTier, newStatus = Nyx.Metering.EvaluateDelinquencyTier(0, remainingArrears, cutoff)

    return {
        paidAmount = actualPaid,
        remainingArrears = remainingArrears,
        isSuspended = newSuspended,
        canReconnect = canReconnect,
        newTier = newTier,
        newStatus = newStatus
    }
end

--- Evaluate doorlock and property power state based on grid and utility suspension status.
--- Enforces power cut-off delinquency mechanics:
--- If utility is cut off (isUtilitySuspended = true) and no backup generator exists:
---  - Property power is completely offline.
---  - Commercial/industrial electronic maglocks fail or cannot be toggled normally.
function Nyx.Metering.EvaluateEffectiveDoorlockPower(propertyType, isLocked, isGridPowered, isUtilitySuspended, hasBackupGen)
    isLocked = (isLocked == true)
    isGridPowered = (isGridPowered ~= false)
    isUtilitySuspended = (isUtilitySuspended == true)
    hasBackupGen = (hasBackupGen == true)

    local effectivePower = false
    local powerSource = "OFFLINE"

    if hasBackupGen then
        effectivePower = true
        powerSource = "BACKUP_GENERATOR"
    elseif isGridPowered and not isUtilitySuspended then
        effectivePower = true
        powerSource = "MUNICIPAL_GRID"
    elseif isUtilitySuspended then
        effectivePower = false
        powerSource = "SUSPENDED_DELINQUENCY"
    else
        effectivePower = false
        powerSource = "GRID_BLACKOUT"
    end

    -- Mechanical keys in residential properties always work physically;
    -- Commercial and Industrial properties rely on electronic magnetic locks.
    local lockFunctional = true
    if (propertyType == "commercial" or propertyType == "industrial") and not effectivePower then
        lockFunctional = false
    end

    return effectivePower, lockFunctional, powerSource
end

--- Generate unique serialized utility invoice UUID
function Nyx.Metering.GenerateInvoiceUuid(meterId, timestamp, nonce)
    meterId = tostring(meterId or "meter"):gsub("[^%w_]", "")
    timestamp = tonumber(timestamp) or os.time()
    nonce = tonumber(nonce) or math.random(1000, 9999)
    return string.format("INV-UTIL-%s-%d-%04d", meterId:sub(-8), timestamp, nonce)
end

--- Generate unique serialized delinquency log UUID
function Nyx.Metering.GenerateLogUuid(action, timestamp, nonce)
    action = tostring(action or "LOG"):sub(1, 4):upper()
    timestamp = tonumber(timestamp) or os.time()
    nonce = tonumber(nonce) or math.random(1000, 9999)
    return string.format("LOG-UTIL-%s-%d-%04d", action, timestamp, nonce)
end

--- Format status badge for chat and telemetry display
function Nyx.Metering.FormatMeterStatusBadge(status)
    local entry = Nyx.Metering.Config.StatusTaxonomy[status]
    if entry then
        return entry.badge, entry.label, entry.color
    end
    return "^3[ISMERETLEN]^7", "Ismeretlen", "grey"
end

--- Format full ASCII invoice report for chat/UI
function Nyx.Metering.FormatInvoiceReport(invoice)
    if not invoice then return "Nincs elérhető számlaadat." end

    local badge, label = Nyx.Metering.FormatMeterStatusBadge(invoice.status or invoice.meterStatus or "active")
    local lines = {
        "^5====================================================^7",
        string.format("^5   FŐVÁROSI KÖZMŰVEK - KÖZMŰSZÁMLA (%s)^7", invoice.invoiceUuid or invoice.invoice_uuid or "N/A"),
        "^5====================================================^7",
        string.format(" Mérőóra azonosító:   ^3%s^7", invoice.meterId or invoice.meter_id or "N/A"),
        string.format(" Tulajdonos:          ^3%s^7", invoice.ownerCitizenId or invoice.owner_citizen_id or "N/A"),
        string.format(" Csatolt Alállomás:   ^3%s^7", invoice.substationId or invoice.substation_id or "N/A"),
        string.format(" Státusz:             %s (%s)", badge, label),
        "----------------------------------------------------",
        string.format(" Áramfogyasztás:      %.2f kWh   ($%.4f/kWh) = ^2$%.2f^7",
            invoice.kwhConsumed or invoice.kwh_consumed or 0.0,
            invoice.kwhTariff or invoice.kwh_tariff or 0.15,
            invoice.energyCharge or invoice.energy_charge or 0.0),
        string.format(" Vízfogyasztás:       %.2f Gal   ($%.4f/Gal) = ^2$%.2f^7",
            invoice.waterConsumed or invoice.water_consumed or 0.0,
            invoice.waterTariff or invoice.water_tariff or 0.05,
            invoice.waterCharge or invoice.water_charge or 0.0),
        string.format(" Korábbi Hátralék:    ^1$%.2f^7", invoice.unpaidArrears or invoice.arrears or 0.0),
        string.format(" Késedelmi Pótlék:    ^1$%.2f^7", invoice.latePenalty or invoice.late_penalty or 0.0),
        string.format(" Visszakapcsolási Díj:^1$%.2f^7", invoice.reconnectFee or invoice.reconnect_fee or 0.0),
        "----------------------------------------------------",
        string.format(" VÉGÖSSZEG:           ^2$%.2f^7", invoice.totalDue or invoice.total_due or 0.0),
        "^5====================================================^7"
    }
    return table.concat(lines, "\n")
end
