--[[
    Nyxframework: nyx_vehicles
    File: shared/diagnostics.lua
    Description: Pure Lua 5.4 mechanical diagnostics engine, OBD-II DTC trouble code analyzer,
                 overall roadworthiness grading, service cost estimator, and civic impound fee calculator.
]]

Nyx = Nyx or {}
Nyx.VehicleDiagnostics = Nyx.VehicleDiagnostics or {}

-- Fiscal Crisis Impound Surcharge Multipliers (aligned with nyx_treasury)
Nyx.VehicleDiagnostics.SURCHARGE_RATES = {
    ['solvent']       = 0.00,
    ['fiscal_stress'] = 0.15,
    ['degraded']      = 0.35,
    ['bankrupt']      = 0.60
}

-- Standard Certified Servicing Catalog
Nyx.VehicleDiagnostics.SERVICE_CATALOG = {
    ['oil_change'] = {
        label = "Motorolaj Csere & Szűrő (Oil & Filter Service)",
        baseCost = 150.00,
        requiredItem = "tool_repairkit",
        component = "oilQuality",
        targetRestore = 100.0,
        description = "Szintetikus kenőanyag frissítése és olajszűrő csere az optimális kenésért."
    },
    ['brake_replacement'] = {
        label = "Fékbetét & Féktárcsa Csere (Brake Overhaul)",
        baseCost = 350.00,
        requiredItem = "tool_repairkit",
        component = "brakePadWear",
        targetRestore = 100.0,
        description = "Kerámia fékbetétek beszerelése és hidraulikus fékfolyadék légtelenítés."
    },
    ['transmission_overhaul'] = {
        label = "Sebességváltó Generál & Kuplung (Gearbox Overhaul)",
        baseCost = 850.00,
        requiredItem = "tool_repairkit",
        component = "transmissionWear",
        targetRestore = 100.0,
        description = "Fogaskerekek ellenőrzése, kuplungtárcsa és szinkrongyűrűk felújítása."
    },
    ['suspension_tune'] = {
        label = "Futómű Beállítás & Lengéscsillapító (Suspension Tune)",
        baseCost = 400.00,
        requiredItem = "tool_repairkit",
        component = "suspensionWear",
        targetRestore = 100.0,
        description = "Lengéscsillapítók cseréje, szilentek és kerékösszetartás precíziós beállítása."
    },
    ['full_service'] = {
        label = "Teljes Műszaki Generál & Átvizsgálás (Full Overhaul)",
        baseCost = 1600.00,
        requiredItem = "tool_repairkit",
        component = "all",
        targetRestore = 100.0,
        description = "Minden fődarab (motorolaj, fékek, sebességváltó, futómű) teljes gyári felújítása."
    }
}

-- Standard OBD-II Diagnostic Trouble Code (DTC) Catalog
Nyx.VehicleDiagnostics.DTC_CATALOG = {
    P0198 = {
        code = "P0198",
        system = "engine",
        severity = "warning",
        title = "Motorolaj Hőmérséklet Magas (Engine Oil High Temp)",
        description = "A motorolaj kenőképessége kritikus szintre csökkent (<= 15.0%). Olajcsere szükséges."
    },
    P0524 = {
        code = "P0524",
        system = "engine",
        severity = "critical",
        title = "Kritikus Olajnyomás Elvesztés (Critical Low Oil Pressure)",
        description = "A motorolaj elhasználódása elérte a végzetes határt (<= 5.0%). Motorkárosodás veszély!"
    },
    C0035 = {
        code = "C0035",
        system = "brakes",
        severity = "warning",
        title = "Fékbetét Kopásérzékelő Jelzett (Brake Wear Sensor)",
        description = "A fékbetétek vastagsága 15% alá esett. A fékút megnyúlt, cseréjük sürgős."
    },
    C0040 = {
        code = "C0040",
        system = "brakes",
        severity = "critical",
        title = "Fékrendszer Hatásfok Elégtelen (Brake Hydraulic Fade)",
        description = "A fékhatás drasztikusan lecsökkent (<= 5.0%). A jármű közúti közlekedésre alkalmatlan!"
    },
    P0730 = {
        code = "P0730",
        system = "transmission",
        severity = "warning",
        title = "Sebességfokozat Megcsúszás (Gear Ratio Slippage)",
        description = "A sebességváltó fogaskerekei vagy a kuplung kopottak (<= 20.0%). Gyorsításkor teljesítményvesztés."
    },
    P0700 = {
        code = "P0700",
        system = "transmission",
        severity = "critical",
        title = "Váltómű Mechanikai Meghibásodás (Transmission Malfunction)",
        description = "Súlyos sebességváltó kopás (<= 10.0%). A nyomatékátvitel bizonytalan."
    },
    C1100 = {
        code = "C1100",
        system = "suspension",
        severity = "warning",
        title = "Futómű Lengéscsillapító Kopás (Strut Damper Deterioration)",
        description = "A lengéscsillapítók és szilentek elhasználódtak (<= 20.0%). Csökkent úttartás."
    },
    C1105 = {
        code = "C1105",
        system = "suspension",
        severity = "critical",
        title = "Súlyos Futómű Instabilitás (Chassis Structural Instability)",
        description = "A futómű kopása veszélyes (<= 10.0%). Nagy sebességnél a jármű bizonytalanná válik."
    },
    P0300 = {
        code = "P0300",
        system = "engine",
        severity = "warning",
        title = "Henger Égéskimaradás (Engine Cylinder Misfire)",
        description = "A motor mechanikai állapota leromlott (<= 400 HP). Egyenetlen alapjárat."
    },
    P0217 = {
        code = "P0217",
        system = "engine",
        severity = "critical",
        title = "Motor Túlmelegedés & Hengerfej Kár (Engine Overtemperature)",
        description = "Kritikus motorállapot (<= 200 HP). Azonnali leállás és javítás szükséges."
    }
}

--- 1. Computes overall roadworthiness grade, composite score (0-100), and certification boolean.
--- @param engineHealth number (0 - 1000)
--- @param oilQuality number (0 - 100)
--- @param brakePadWear number (0 - 100)
--- @param transmissionWear number (0 - 100)
--- @param suspensionWear number (0 - 100)
--- @return string grade ("pristine", "good", "fair", "critical", "hazardous")
--- @return number compositeScore (0.00 - 100.00)
--- @return boolean isRoadworthy
function Nyx.VehicleDiagnostics.CalculateOverallGrade(engineHealth, oilQuality, brakePadWear, transmissionWear, suspensionWear)
    local engNorm = math.max(0.0, math.min(100.0, (tonumber(engineHealth) or 1000.0) / 10.0))
    local oilNorm = math.max(0.0, math.min(100.0, tonumber(oilQuality) or 100.0))
    local brkNorm = math.max(0.0, math.min(100.0, tonumber(brakePadWear) or 100.0))
    local trnNorm = math.max(0.0, math.min(100.0, tonumber(transmissionWear) or 100.0))
    local susNorm = math.max(0.0, math.min(100.0, tonumber(suspensionWear) or 100.0))

    local composite = (engNorm * 0.30) + (oilNorm * 0.20) + (brkNorm * 0.20) + (trnNorm * 0.15) + (susNorm * 0.15)
    composite = math.floor((composite * 100) + 0.5) / 100

    local isRoadworthy = true
    if composite < 25.0 or oilNorm <= 10.0 or brkNorm <= 10.0 or engNorm <= 20.0 then
        isRoadworthy = false
    end

    local grade = "pristine"
    if composite < 25.0 then
        grade = "hazardous"
    elseif composite < 50.0 then
        grade = "critical"
    elseif composite < 75.0 then
        grade = "fair"
    elseif composite < 90.0 then
        grade = "good"
    else
        grade = "pristine"
    end

    return grade, composite, isRoadworthy
end

--- 2. Detects active OBD-II Diagnostic Trouble Codes based on mechanical telemetry.
--- @param wearData table
--- @param engineHealth number
--- @return table dtcList
function Nyx.VehicleDiagnostics.GenerateDiagnosticCodes(wearData, engineHealth)
    local codes = {}
    local wear = wearData or {}
    local oil = tonumber(wear.oilQuality or wear.oil) or 100.0
    local brakes = tonumber(wear.brakePadWear or wear.brakes) or 100.0
    local trans = tonumber(wear.transmissionWear or wear.transmission) or 100.0
    local susp = tonumber(wear.suspensionWear or wear.suspension) or 100.0
    local eng = tonumber(engineHealth) or 1000.0

    if oil <= 15.0 then table.insert(codes, Nyx.VehicleDiagnostics.DTC_CATALOG.P0198) end
    if oil <= 5.0 then table.insert(codes, Nyx.VehicleDiagnostics.DTC_CATALOG.P0524) end
    if brakes <= 15.0 then table.insert(codes, Nyx.VehicleDiagnostics.DTC_CATALOG.C0035) end
    if brakes <= 5.0 then table.insert(codes, Nyx.VehicleDiagnostics.DTC_CATALOG.C0040) end
    if trans <= 20.0 then table.insert(codes, Nyx.VehicleDiagnostics.DTC_CATALOG.P0730) end
    if trans <= 10.0 then table.insert(codes, Nyx.VehicleDiagnostics.DTC_CATALOG.P0700) end
    if susp <= 20.0 then table.insert(codes, Nyx.VehicleDiagnostics.DTC_CATALOG.C1100) end
    if susp <= 10.0 then table.insert(codes, Nyx.VehicleDiagnostics.DTC_CATALOG.C1105) end
    if eng <= 400.0 then table.insert(codes, Nyx.VehicleDiagnostics.DTC_CATALOG.P0300) end
    if eng <= 200.0 then table.insert(codes, Nyx.VehicleDiagnostics.DTC_CATALOG.P0217) end

    return codes
end

--- 3. Calculates service estimate, labor, parts cost, and required items.
--- @param wearData table
--- @param serviceType string
--- @param isCommercial boolean
--- @return table estimate
function Nyx.VehicleDiagnostics.CalculateServiceEstimate(wearData, serviceType, isCommercial)
    local cfg = Nyx.VehicleDiagnostics.SERVICE_CATALOG[serviceType]
    if not cfg then return nil end

    local multiplier = isCommercial and 1.25 or 1.00
    local cost = math.floor(((cfg.baseCost * multiplier) * 100) + 0.5) / 100

    local currentVal = 100.0
    if cfg.component ~= "all" and wearData then
        currentVal = tonumber(wearData[cfg.component]) or 100.0
    end

    local recoveryDelta = math.max(0.0, 100.0 - currentVal)

    return {
        serviceType = serviceType,
        label = cfg.label,
        cost = cost,
        requiredItem = cfg.requiredItem,
        currentValue = currentVal,
        targetValue = 100.0,
        recoveryDelta = math.floor((recoveryDelta * 100) + 0.5) / 100,
        description = cfg.description
    }
end

--- 4. Validates service payload before execution.
--- @param payload table
--- @return boolean isValid
--- @return string|nil errorReason
function Nyx.VehicleDiagnostics.ValidateServicePayload(payload)
    if not payload or type(payload) ~= "table" then
        return false, "INVALID_PAYLOAD"
    end

    local vin = payload.vin or payload.plate
    if not vin or type(vin) ~= "string" or #vin < 3 then
        return false, "INVALID_VIN_OR_IDENTIFIER"
    end

    local serviceType = payload.serviceType
    if not serviceType or not Nyx.VehicleDiagnostics.SERVICE_CATALOG[serviceType] then
        return false, "UNKNOWN_SERVICE_TYPE"
    end

    if payload.notes and type(payload.notes) == "string" and #payload.notes > 255 then
        return false, "NOTES_EXCEED_255_CHARS"
    end

    return true, nil
end

--- 5. Visual Wear Badge Metadata Generator.
--- @param percentage number
--- @return table badgeInfo
function Nyx.VehicleDiagnostics.FormatWearBadge(percentage)
    local val = tonumber(percentage) or 0.0

    if val >= 75.0 then
        return { label = "KIVÁLÓ / GYÁRI", cssClass = "badge-emerald", status = "optimal", pct = val }
    elseif val >= 40.0 then
        return { label = "NORMÁL KOPÁS", cssClass = "badge-amber", status = "warning", pct = val }
    elseif val >= 15.0 then
        return { label = "SZERVIZ ESEDÉKES", cssClass = "badge-orange", status = "urgent", pct = val }
    else
        return { label = "VESZÉLYES / LEÁLLÁS", cssClass = "badge-rose", status = "danger", pct = val }
    end
end

--- 6. Calculates impound totals including storage fees and municipal fiscal crisis surcharges.
--- @param baseFee number
--- @param elapsedDays number
--- @param dailyRate number
--- @param fiscalTier string ("solvent", "fiscal_stress", "degraded", "bankrupt")
--- @return table calculation
function Nyx.VehicleDiagnostics.CalculateImpoundTotals(baseFee, elapsedDays, dailyRate, fiscalTier)
    local base = math.max(0.0, tonumber(baseFee) or 500.00)
    local days = math.max(0, math.floor(tonumber(elapsedDays) or 0))
    local daily = math.max(0.0, tonumber(dailyRate) or 150.00)
    local tier = fiscalTier and string.lower(fiscalTier) or "solvent"

    local rate = Nyx.VehicleDiagnostics.SURCHARGE_RATES[tier] or 0.00
    local storage = math.floor(((days * daily) * 100) + 0.5) / 100
    local subtotal = math.floor(((base + storage) * 100) + 0.5) / 100
    local surcharge = math.floor(((subtotal * rate) * 100) + 0.5) / 100
    local total = math.floor(((subtotal + surcharge) * 100) + 0.5) / 100

    return {
        baseFee = base,
        storageDays = days,
        dailyRate = daily,
        storageFee = storage,
        subtotal = subtotal,
        fiscalTier = tier,
        surchargeRate = rate,
        emergencySurcharge = surcharge,
        totalFee = total
    }
end

--- 7. Filters catalog of vehicles by query substring, lot ID, or status.
--- @param vehicles table
--- @param query string|nil
--- @param lotFilter string|nil
--- @param statusFilter string|nil
--- @return table filtered
function Nyx.VehicleDiagnostics.FilterVehiclesCatalog(vehicles, query, lotFilter, statusFilter)
    if not vehicles or type(vehicles) ~= "table" then return {} end

    local q = query and string.lower(query) or ""
    local lot = (lotFilter and lotFilter ~= "all") and string.lower(lotFilter) or nil
    local status = (statusFilter and statusFilter ~= "all") and string.lower(statusFilter) or nil

    local filtered = {}
    for _, v in ipairs(vehicles) do
        local matchQuery = true
        if q ~= "" then
            local plate = string.lower(tostring(v.plate or ""))
            local vin = string.lower(tostring(v.vin or ""))
            local model = string.lower(tostring(v.modelName or v.model or ""))
            local reason = string.lower(tostring(v.impoundReason or ""))
            matchQuery = (string.find(plate, q, 1, true) ~= nil) or
                         (string.find(vin, q, 1, true) ~= nil) or
                         (string.find(model, q, 1, true) ~= nil) or
                         (string.find(reason, q, 1, true) ~= nil)
        end

        local matchLot = true
        if lot then
            local vLot = string.lower(tostring(v.impoundLotId or v.lotId or ""))
            matchLot = (vLot == lot)
        end

        local matchStatus = true
        if status then
            local vStatus = string.lower(tostring(v.status or v.storage_state or ""))
            matchStatus = (vStatus == status)
        end

        if matchQuery and matchLot and matchStatus then
            table.insert(filtered, v)
        end
    end

    return filtered
end

--- 8. Formats monetary amount as standard US currency string.
--- @param amount number
--- @return string
function Nyx.VehicleDiagnostics.FormatCurrency(amount)
    local n = tonumber(amount) or 0.00
    local formatted = string.format("%.2f", n)
    local k
    while true do
        formatted, k = string.gsub(formatted, "^(-?%d+)(%d%d%d)", '%1,%2')
        if k == 0 then break end
    end
    return "$" .. formatted
end
