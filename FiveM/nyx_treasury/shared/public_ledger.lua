--[[
    Nyxframework: nyx_treasury
    File: shared/public_ledger.lua
    Description: Pure Lua 5.4 domain engine for auditable public treasury ledgers,
                 open municipal balance sheets, automated statutory percentage splits,
                 department cap enforcement, and fiscal crisis threshold telemetry.
]]

Nyx = Nyx or {}
Nyx.PublicLedger = Nyx.PublicLedger or {}

-- ----------------------------------------------------------------------------
-- Statutory Pillars & Department Allocation Categories
-- ----------------------------------------------------------------------------
Nyx.PublicLedger.AllocationCategories = {
    ["emergency_services"] = {
        label = "Készenléti Szervek (Emergency Services)",
        description = "Rendvédelmi és mentési készenlét, járőrszolgálat és sürgősségi ellátás.",
        statutoryPillar = "Emergency Services Payroll & Tactical Fleet"
    },
    ["infrastructure"] = {
        label = "Városi Infrastruktúra & Közművek (Infrastructure)",
        description = "Elektromos hálózat, transzformátor állomások, vízművek és útkarbantartás.",
        statutoryPillar = "Public Works & Grid Infrastructure"
    },
    ["social_dividend"] = {
        label = "Társadalmi Osztalék & Polgári Pályázatok (Social Dividend)",
        description = "Polgári alapjövedelem, kisvállalkozói támogatások és közösségi ösztöndíjak.",
        statutoryPillar = "Social Dividend & Citizen Small Grants"
    },
    ["general"] = {
        label = "Általános Költségvetési Célelőirányzat",
        description = "Egyéb törvényhozási és közigazgatási céltartalékok.",
        statutoryPillar = "General Civic Appropriations"
    }
}

-- ----------------------------------------------------------------------------
-- Transaction Categories & Flow Classifications
-- ----------------------------------------------------------------------------
Nyx.PublicLedger.TransactionCategories = {
    ["pos_sale"] = { label = "Kereskedelmi Értékesítés", badge = "COMMERCE", flow = "internal" },
    ["pos_tax"] = { label = "Értékesítési Adó (ÁFA)", badge = "TAX_INFLOW", flow = "inflow" },
    ["transfer_p2p"] = { label = "Banki Átutalás (P2P)", badge = "WIRE_TRANSFER", flow = "internal" },
    ["transfer_duty"] = { label = "Pénzügyi Tranzakciós Illeték", badge = "DUTY_INFLOW", flow = "inflow" },
    ["payroll"] = { label = "Közszolgálati Bérkifizetés", badge = "PAYROLL", flow = "outflow" },
    ["allocation"] = { label = "Költségvetési Adóelosztás", badge = "ALLOCATION", flow = "internal" },
    ["emergency_subvention"] = { label = "Rendkívüli Kincstári Szubvenció", badge = "SUBVENTION", flow = "internal" },
    ["commercial_laundering"] = { label = "Pénzmosási Letét (Washed)", badge = "LAUNDER_INFLOW", flow = "inflow" },
    ["laundering_tax"] = { label = "Pénzmosási Forgalmi Adó", badge = "LAUNDER_TAX", flow = "inflow" },
    ["cash_transit_deposit"] = { label = "Páncélozott Készpénz Befizetés", badge = "VAULT_DEPOSIT", flow = "inflow" },
    ["cash_transit_fee"] = { label = "Készpénzszállítási Banki Díj", badge = "TRANSIT_FEE", flow = "inflow" },
    ["equity_dividend"] = { label = "Társasági Osztalékfizetés", badge = "DIVIDEND", flow = "internal" },
    ["utility_bill"] = { label = "Közműdíj Befizetés", badge = "UTILITY_REVENUE", flow = "inflow" },
    ["circuit_event"] = { label = "Fiskális Áramkörvédelmi Esemény", badge = "CIRCUIT_ALERT", flow = "audit" }
}

-- ----------------------------------------------------------------------------
-- Pure Domain Function: Compute Municipal Balance Sheet
-- ----------------------------------------------------------------------------
function Nyx.PublicLedger.CalculateBalanceSheet(accounts, targetReserve, criticalReserve)
    targetReserve = tonumber(targetReserve) or 5000000.00
    criticalReserve = tonumber(criticalReserve) or 500000.00
    accounts = (type(accounts) == "table") and accounts or {}

    local totalLiquidity = 0.00
    for _, acc in ipairs(accounts) do
        local bal = tonumber(acc.balance) or 0.00
        totalLiquidity = totalLiquidity + bal
    end
    totalLiquidity = math.floor(totalLiquidity * 100) / 100

    local processedAccounts = {}
    for _, acc in ipairs(accounts) do
        local bal = tonumber(acc.balance) or 0.00
        local cap = tonumber(acc.cap_limit or acc.capLimit)
        local sharePct = (totalLiquidity > 0) and (math.floor((bal / totalLiquidity * 100.00) * 100) / 100) or 0.00

        local solvency = "SOLVENT"
        if bal <= 0.00 then
            solvency = "DEPLETED"
        elseif cap and cap > 0 and (bal / cap) < 0.20 then
            solvency = "DEFICIT_WARNING"
        elseif cap and cap > 0 and (bal / cap) < 0.50 then
            solvency = "LOW_RESERVE"
        end

        processedAccounts[#processedAccounts + 1] = {
            accountId = acc.account_id or acc.id or acc.accountId,
            label = acc.label or acc.account_id or "Municipal Account",
            type = acc.type or "department",
            balance = math.floor(bal * 100) / 100,
            capLimit = (cap and cap > 0) and (math.floor(cap * 100) / 100) or nil,
            sharePercentage = sharePct,
            solvencyStatus = solvency,
            circuitExempt = (acc.circuit_exempt == 1 or acc.circuit_exempt == true or acc.circuitExempt == true)
        }
    end

    return {
        totalLiquidity = totalLiquidity,
        accountCount = #processedAccounts,
        accounts = processedAccounts,
        targetReserve = math.floor(targetReserve * 100) / 100,
        criticalReserve = math.floor(criticalReserve * 100) / 100,
        isBalanced = true,
        conservationVariance = 0.00
    }
end

-- ----------------------------------------------------------------------------
-- Pure Domain Function: Exact Closed-Loop Revenue Sweep Split Calculator
-- Guarantee: Sum(EffectiveShares) + MasterSurplusRetained == CollectedAmount
-- ----------------------------------------------------------------------------
function Nyx.PublicLedger.CalculateSweepSplits(collectedAmount, allocations, currentBalances)
    collectedAmount = math.floor((tonumber(collectedAmount) or 0.00) * 100) / 100
    allocations = (type(allocations) == "table") and allocations or {}
    currentBalances = (type(currentBalances) == "table") and currentBalances or {}

    if collectedAmount < 10.00 or #allocations == 0 then
        return {
            success = false,
            reason = (collectedAmount < 10.00) and "INSUFFICIENT_POOL_BALANCE" or "NO_ALLOCATIONS_CONFIGURED",
            collectedAmount = collectedAmount,
            totalSwept = 0.00,
            masterSurplusRetained = 0.00,
            splits = {}
        }
    end

    local splits = {}
    local totalAllocated = 0.00
    local masterSurplus = 0.00

    for _, alloc in ipairs(allocations) do
        local target = alloc.target_department or alloc.targetDepartment
        local pct = tonumber(alloc.percentage_split or alloc.percentageSplit) or 0.00
        local rawCap = tonumber(alloc.cap_limit or alloc.capLimit)
        local cap = (rawCap and rawCap > 0) and rawCap or nil

        local rawShare = math.floor((collectedAmount * (pct / 100.00)) * 100) / 100
        local currentBal = tonumber(currentBalances[target]) or 0.00
        local effectiveShare = rawShare
        local divertedSurplus = 0.00

        if cap then
            local headroom = math.max(0.00, cap - currentBal)
            if rawShare > headroom then
                effectiveShare = math.floor(headroom * 100) / 100
                divertedSurplus = math.floor((rawShare - effectiveShare) * 100) / 100
                masterSurplus = masterSurplus + divertedSurplus
            end
        end

        splits[#splits + 1] = {
            targetDepartment = target,
            departmentLabel = alloc.department_label or alloc.label or target,
            allocationCategory = alloc.allocation_category or alloc.category or "general",
            percentageSplit = pct,
            rawShare = rawShare,
            effectiveShare = effectiveShare,
            divertedToMaster = divertedSurplus,
            capLimit = cap,
            balanceBefore = math.floor(currentBal * 100) / 100,
            balanceAfter = math.floor((currentBal + effectiveShare) * 100) / 100
        }

        totalAllocated = totalAllocated + effectiveShare
    end

    totalAllocated = math.floor(totalAllocated * 100) / 100
    masterSurplus = math.floor(masterSurplus * 100) / 100

    -- Capture any fractional cent rounding dust strictly into master surplus
    local totalSwept = math.floor((totalAllocated + masterSurplus) * 100) / 100
    local centRemainder = math.floor((collectedAmount - totalSwept) * 100) / 100
    if centRemainder > 0 then
        masterSurplus = math.floor((masterSurplus + centRemainder) * 100) / 100
        totalSwept = math.floor((totalAllocated + masterSurplus) * 100) / 100
    end

    local variance = math.floor((collectedAmount - totalSwept) * 100) / 100

    return {
        success = true,
        collectedAmount = collectedAmount,
        totalAllocated = totalAllocated,
        masterSurplusRetained = masterSurplus,
        totalSwept = totalSwept,
        variance = variance,
        splits = splits
    }
end

-- ----------------------------------------------------------------------------
-- Pure Domain Function: Compute Fiscal Crisis & Threshold Telemetry
-- ----------------------------------------------------------------------------
function Nyx.PublicLedger.CalculateFiscalTelemetry(masterReserve, circuitTelemetry, targetReserve, criticalReserve, cautionReserve)
    masterReserve = math.max(0.00, tonumber(masterReserve) or 0.00)
    targetReserve = tonumber(targetReserve) or 5000000.00
    criticalReserve = tonumber(criticalReserve) or 500000.00
    cautionReserve = tonumber(cautionReserve) or 2500000.00
    circuitTelemetry = (type(circuitTelemetry) == "table") and circuitTelemetry or {}

    local isTripped = (circuitTelemetry.tripped == true)

    local fiscalState = "SOLVENT"
    if isTripped then
        fiscalState = "CIRCUIT_TRIPPED"
    elseif masterReserve <= criticalReserve then
        fiscalState = "CRITICAL_DEFICIT"
    elseif masterReserve < cautionReserve then
        fiscalState = "AUSTERITY"
    elseif masterReserve < targetReserve then
        fiscalState = "THROTTLED"
    end

    -- Logarithmic wage scaling
    local wageMultiplier = 1.00
    local wageStatus = "SOLVENT"
    if isTripped or masterReserve <= criticalReserve then
        wageMultiplier = 0.00
        wageStatus = "CRITICAL_FREEZE"
    elseif masterReserve < targetReserve then
        local floor = 0.10
        local logRatio = math.log(masterReserve / criticalReserve)
        local logMax = math.log(targetReserve / criticalReserve)
        local normalized = (logMax > 0) and (logRatio / logMax) or 0.00
        local scaled = floor + ((1.00 - floor) * normalized)
        local clamped = math.max(floor, math.min(1.00, scaled))
        wageMultiplier = math.floor(clamped * 100) / 100
        wageStatus = (masterReserve < cautionReserve) and "AUSTERITY" or "THROTTLED"
    end

    -- Drain velocity & projected runway hours
    local drain = circuitTelemetry.drainVelocity or {}
    local outflowHr = tonumber(drain.velocityPerHour) or 0.00
    local runwayHours = nil
    if outflowHr > 0 and masterReserve > criticalReserve then
        local surplus = masterReserve - criticalReserve
        runwayHours = math.floor((surplus / outflowHr) * 10) / 10
    end

    local reserveRatio = (targetReserve > 0) and (math.floor((masterReserve / targetReserve * 100.0) * 10) / 10) or 0.0

    -- Public Infrastructure Degradation Status
    local isDegraded = (fiscalState == "CRITICAL_DEFICIT" or fiscalState == "CIRCUIT_TRIPPED" or masterReserve <= 100000.00)
    local autoRepairStatus = isDegraded and "OFFLINE" or "OPERATIONAL"
    local impoundSurcharge = (fiscalState == "AUSTERITY" or fiscalState == "CRITICAL_DEFICIT" or fiscalState == "CIRCUIT_TRIPPED")
    local aiDispatchStatus = isDegraded and "DEGRADED" or "OPERATIONAL"

    return {
        masterReserve = masterReserve,
        targetReserve = targetReserve,
        cautionReserve = cautionReserve,
        criticalReserve = criticalReserve,
        reserveRatioPercentage = reserveRatio,
        fiscalState = fiscalState,
        wageMultiplier = wageMultiplier,
        wageMultiplierPercentage = math.floor(wageMultiplier * 1000) / 10,
        wageStatus = wageStatus,
        drainVelocityPerHour = outflowHr,
        runwayHours = runwayHours,
        circuitTripped = isTripped,
        infrastructure = {
            autoRepair = autoRepairStatus,
            impoundSurchargeActive = impoundSurcharge,
            aiDispatch = aiDispatchStatus,
            municipalDegraded = isDegraded
        }
    }
end

-- ----------------------------------------------------------------------------
-- Zero-Trust Query Sanitizer for Public Ledger Explorer
-- ----------------------------------------------------------------------------
function Nyx.PublicLedger.SanitizeLedgerQuery(params)
    params = (type(params) == "table") and params or {}

    local page = math.max(1, math.floor(tonumber(params.page) or 1))
    local pageSize = math.max(5, math.min(100, math.floor(tonumber(params.pageSize) or 20)))
    local offset = (page - 1) * pageSize

    local rawCategory = tostring(params.category or "ALL")
    local category = "ALL"
    if rawCategory and rawCategory ~= "ALL" and Nyx.PublicLedger.TransactionCategories[rawCategory] then
        category = rawCategory
    end

    local search = ""
    local rawSearch = params.search
    if rawSearch and type(rawSearch) == "string" then
        local clean = string.gsub(rawSearch, "[^%w%-%: %_]", "")
        search = string.sub(clean, 1, 64)
    end

    return {
        page = page,
        pageSize = pageSize,
        offset = offset,
        category = category,
        search = search
    }
end

-- ----------------------------------------------------------------------------
-- ASCII Financial Telemetry Report Formatter
-- ----------------------------------------------------------------------------
function Nyx.PublicLedger.FormatLedgerReport(balanceSheet, telemetry)
    balanceSheet = balanceSheet or {}
    telemetry = telemetry or {}

    local lines = {}
    lines[#lines + 1] = "================================================================================"
    lines[#lines + 1] = "        NYX CIVIC TREASURY: AUDITABLE PUBLIC FINANCIAL TELEMETRY"
    lines[#lines + 1] = "================================================================================"
    lines[#lines + 1] = string.format(" MUNICIPAL MASTER RESERVE:  $%12.2f  (Target: $%10.2f)", telemetry.masterReserve or 0.00, telemetry.targetReserve or 0.00)
    lines[#lines + 1] = string.format(" TOTAL CIVIC LIQUIDITY:    $%12.2f  (Solvency: %s)", balanceSheet.totalLiquidity or 0.00, telemetry.fiscalState or "SOLVENT")
    lines[#lines + 1] = string.format(" WAGE MULTIPLIER (LOG):    %6.1f%% (%s)  | CIRCUIT: %s", (telemetry.wageMultiplier or 1.0) * 100, telemetry.wageStatus or "OK", (telemetry.circuitTripped and "TRIPPED" or "NORMAL"))
    lines[#lines + 1] = string.format(" DRAIN VELOCITY:           $%10.2f/hr  | RUNWAY: %s hrs", telemetry.drainVelocityPerHour or 0.00, tostring(telemetry.runwayHours or "STABLE"))
    lines[#lines + 1] = "--------------------------------------------------------------------------------"
    lines[#lines + 1] = " ACCOUNT BREAKDOWN:"
    for _, acc in ipairs(balanceSheet.accounts or {}) do
        lines[#lines + 1] = string.format("  - %-20s : $%11.2f (%5.1f%%) [%s]", acc.accountId, acc.balance, acc.sharePercentage or 0.0, acc.solvencyStatus or "OK")
    end
    lines[#lines + 1] = "================================================================================"
    return table.concat(lines, "\n")
end
