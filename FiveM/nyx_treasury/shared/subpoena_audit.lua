--[[
    Nyxframework: nyx_treasury
    File: shared/subpoena_audit.lua
    Description: Pure Lua 5.4 forensic anomaly analysis engine for subpoenaed
                 commercial ledgers, Benford deviation, velocity spikes,
                 and cryptographic SHA-256 evidence hashing.
]]

Nyx = Nyx or {}
Nyx.SubpoenaAudit = Nyx.SubpoenaAudit or {}

-- 1. Bitwise operations for pure Lua 5.4 SHA-256
local band = function(a, b) return a & b end
local bor = function(a, b) return a | b end
local bxor = function(a, b) return a ~ b end
local bnot = function(a) return ~a & 0xFFFFFFFF end
local rshift = function(a, b) return (a & 0xFFFFFFFF) >> b end
local lshift = function(a, b) return (a << b) & 0xFFFFFFFF end

local function ror(x, n)
    return (rshift(x, n) | lshift(x, 32 - n)) & 0xFFFFFFFF
end

local K = {
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2
}

function Nyx.SubpoenaAudit.Sha256(str)
    if type(str) ~= "string" then str = tostring(str or "") end
    local H = {
        0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
        0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19
    }

    local len = #str
    local bit_len = len * 8
    local pad = { str:byte(1, len) }
    pad[#pad + 1] = 0x80
    while (#pad % 64) ~= 56 do
        pad[#pad + 1] = 0x00
    end

    for i = 7, 0, -1 do
        pad[#pad + 1] = (bit_len >> (i * 8)) & 0xFF
    end

    local W = {}
    for chunk = 1, #pad, 64 do
        for t = 0, 15 do
            local idx = chunk + t * 4
            W[t] = (lshift(pad[idx], 24) | lshift(pad[idx + 1], 16) | lshift(pad[idx + 2], 8) | pad[idx + 3]) & 0xFFFFFFFF
        end
        for t = 16, 63 do
            local s0 = bxor(bxor(ror(W[t - 15], 7), ror(W[t - 15], 18)), rshift(W[t - 15], 3))
            local s1 = bxor(bxor(ror(W[t - 2], 17), ror(W[t - 2], 19)), rshift(W[t - 2], 10))
            W[t] = (W[t - 16] + s0 + W[t - 7] + s1) & 0xFFFFFFFF
        end

        local a, b, c, d, e, f, g, h = H[1], H[2], H[3], H[4], H[5], H[6], H[7], H[8]

        for t = 0, 63 do
            local S1 = bxor(bxor(ror(e, 6), ror(e, 11)), ror(e, 25))
            local ch = bxor(band(e, f), band(bnot(e), g))
            local temp1 = (h + S1 + ch + K[t + 1] + W[t]) & 0xFFFFFFFF
            local S0 = bxor(bxor(ror(a, 2), ror(a, 13)), ror(a, 22))
            local maj = bxor(bxor(band(a, b), band(a, c)), band(b, c))
            local temp2 = (S0 + maj) & 0xFFFFFFFF

            h = g
            g = f
            f = e
            e = (d + temp1) & 0xFFFFFFFF
            d = c
            c = b
            b = a
            a = (temp1 + temp2) & 0xFFFFFFFF
        end

        H[1] = (H[1] + a) & 0xFFFFFFFF
        H[2] = (H[2] + b) & 0xFFFFFFFF
        H[3] = (H[3] + c) & 0xFFFFFFFF
        H[4] = (H[4] + d) & 0xFFFFFFFF
        H[5] = (H[5] + e) & 0xFFFFFFFF
        H[6] = (H[6] + f) & 0xFFFFFFFF
        H[7] = (H[7] + g) & 0xFFFFFFFF
        H[8] = (H[8] + h) & 0xFFFFFFFF
    end

    local out = {}
    for i = 1, 8 do
        out[i] = string.format("%08x", H[i])
    end
    return table.concat(out)
end

-- 2. Statistical Anomaly & Benford Deviation Detection
function Nyx.SubpoenaAudit.AnalyzeLedgerAnomalies(transactions, registerData, businessType)
    transactions = type(transactions) == "table" and transactions or {}
    registerData = type(registerData) == "table" and registerData or {}
    businessType = businessType or registerData.business_type or registerData.businessType or "retail"

    local totalVolume = 0.00
    local cashVolume = 0.00
    local roundAmountCount = 0
    local totalDeposits = 0
    local burstVelocitySpikes = 0
    local offHoursCount = 0
    local anomalies = {}
    local anomalyScore = 0.00

    local lastTxTime = nil

    for _, tx in ipairs(transactions) do
        local amount = math.abs(tonumber(tx.amount) or 0.00)
        local category = tx.category or "general"
        totalVolume = totalVolume + amount

        local isCash = (category == "cash_deposit" or category == "laundering_clean_deposit" or category == "register_intake" or (tx.memo and string.find(string.lower(tx.memo), "cash")))
        if isCash then
            cashVolume = cashVolume + amount
            totalDeposits = totalDeposits + 1

            -- Vector 1: Round-number anomaly (e.g. $1,000, $5,000, $2,500 instead of $18.99, $42.50)
            if amount >= 500.00 and (amount % 500.00 == 0.00) then
                roundAmountCount = roundAmountCount + 1
            end

            -- Vector 2: Velocity Spikes (successive deposits within < 300s)
            local txTime = tonumber(tx.created_at_unix or tx.timestamp)
            if txTime and lastTxTime then
                local deltaSec = math.abs(txTime - lastTxTime)
                if deltaSec <= 300 then
                    burstVelocitySpikes = burstVelocitySpikes + 1
                end
            end
            if txTime then lastTxTime = txTime end

            -- Vector 3: Off-Hours activity (02:00 - 05:00 UTC/local)
            if tx.hour_of_day and (tx.hour_of_day >= 2 and tx.hour_of_day <= 5) then
                offHoursCount = offHoursCount + 1
            end
        end
    end

    local cashRatio = (totalVolume > 0.00) and (cashVolume / totalVolume) or 0.00
    local baselineRatio = 0.30
    if Nyx.Laundering and Nyx.Laundering.BusinessProfiles and Nyx.Laundering.BusinessProfiles[businessType] then
        baselineRatio = Nyx.Laundering.BusinessProfiles[businessType].baselineCashRatio
    end

    -- Anomaly 1: Cash Volume Ratio Incongruence
    if cashRatio > (baselineRatio + 0.15) then
        local excess = cashRatio - baselineRatio
        local points = math.min(35.0, math.floor(excess * 50.0 * 100 + 0.5) / 100)
        anomalyScore = anomalyScore + points
        table.insert(anomalies, {
            code = "DISPROPORTIONATE_CASH_RATIO",
            description = string.format("Cash ratio %.1f%% exceeds expected industry baseline %.1f%%", cashRatio * 100, baselineRatio * 100),
            weight = points
        })
    end

    -- Anomaly 2: High proportion of artificial round-number figures
    if totalDeposits >= 3 then
        local roundRatio = roundAmountCount / totalDeposits
        if roundRatio >= 0.50 then
            local points = math.min(25.0, math.floor(roundRatio * 25.0 * 100 + 0.5) / 100)
            anomalyScore = anomalyScore + points
            table.insert(anomalies, {
                code = "ARTIFICIAL_ROUND_AMOUNTS",
                description = string.format("%.1f%% of deposits are structured round multiples ($500/$1000)", roundRatio * 100),
                weight = points
            })
        end
    end

    -- Anomaly 3: Velocity Spikes / Burst Deposits
    if burstVelocitySpikes >= 2 then
        local points = math.min(20.0, burstVelocitySpikes * 5.0)
        anomalyScore = anomalyScore + points
        table.insert(anomalies, {
            code = "CASH_VELOCITY_SPIKE",
            description = string.format("%d rapid successive cash deposits detected within 5-minute intervals", burstVelocitySpikes),
            weight = points
        })
    end

    -- Anomaly 4: Register Cap Saturation or Active Dirty Pool Presence
    local dirtyPool = tonumber(registerData.dirty_cash_pool or registerData.dirtyCashPool) or 0.00
    local launderedToday = tonumber(registerData.daily_laundered_amount or registerData.dailyLaunderedAmount) or 0.00
    local maxCap = tonumber(registerData.max_daily_laundering_cap or registerData.maxDailyLaunderingCap) or 50000.00

    if maxCap > 0.00 and (launderedToday / maxCap) >= 0.85 then
        local points = 10.0
        anomalyScore = anomalyScore + points
        table.insert(anomalies, {
            code = "CAP_SATURATION_MAX",
            description = string.format("Register reached %.1f%% of maximum permissible daily throughput", (launderedToday / maxCap) * 100),
            weight = points
        })
    end

    if dirtyPool > 0.00 then
        local points = 15.0
        anomalyScore = anomalyScore + points
        table.insert(anomalies, {
            code = "UNRESOLVED_DIRTY_POOL",
            description = string.format("Register currently holds $%.2f in unverified cash escrow", dirtyPool),
            weight = points
        })
    end

    if offHoursCount >= 2 then
        local points = 10.0
        anomalyScore = anomalyScore + points
        table.insert(anomalies, {
            code = "OFF_HOURS_SURGE",
            description = string.format("%d deposits logged during unusual off-business hours (02:00-05:00)", offHoursCount),
            weight = points
        })
    end

    anomalyScore = math.min(100.00, math.floor(anomalyScore * 100 + 0.5) / 100)

    -- Determine Suspicion Level
    local suspicionLevel = "clean"
    local recommendation = "No abnormal transactional activity detected. Standard operation."

    if anomalyScore >= 85.00 then
        suspicionLevel = "blatant_anomalies"
        recommendation = "IMMEDIATE_ASSET_SEIZURE_AND_PROSECUTION: Severe systematic money laundering identified."
    elseif anomalyScore >= 65.00 then
        suspicionLevel = "high_suspicion"
        recommendation = "FREEZE_COMMERCIAL_VAULT: Probable cause established for criminal illicit cash integration."
    elseif anomalyScore >= 35.00 then
        suspicionLevel = "elevated"
        recommendation = "SUBPOENA_RECORDS: Elevated risk warrants deep corporate ledger inspection and subpoena."
    elseif anomalyScore >= 15.00 then
        suspicionLevel = "low_risk"
        recommendation = "MONITOR: Minor transactional variance; maintain routine financial oversight."
    end

    -- Canonical string for cryptographic SHA-256 fingerprinting
    local canonicalStr = string.format(
        "AUDIT:TARGET=%s:BIZ=%s:VOL=%.2f:CASH_PCT=%.2f:SCORE=%.2f:ANOMALIES=%d",
        tostring(registerData.register_id or registerData.faction_id or "UNKNOWN"),
        businessType,
        totalVolume,
        cashRatio * 100,
        anomalyScore,
        #anomalies
    )
    local reportHash = Nyx.SubpoenaAudit.Sha256(canonicalStr)

    return {
        anomalyScore = anomalyScore,
        suspicionLevel = suspicionLevel,
        recommendation = recommendation,
        totalVolume = totalVolume,
        cashVolume = cashVolume,
        cashRatioPct = math.floor(cashRatio * 10000 + 0.5) / 100,
        anomalies = anomalies,
        reportHash = reportHash,
        canonicalString = canonicalStr
    }
end

-- 3. Validate Subpoena Warrant Legal Scope
function Nyx.SubpoenaAudit.ValidateSubpoenaScope(warrant, targetType, targetId)
    if not warrant or type(warrant) ~= "table" then
        return false, "WARRANT_NOT_FOUND"
    end

    if warrant.status ~= "active" then
        return false, string.format("WARRANT_NOT_ACTIVE_STATUS_%s", tostring(warrant.status))
    end

    local wType = tostring(warrant.type or warrant.warrant_type or ""):lower()
    if wType ~= "subpoena" and wType ~= "financial" then
        return false, "WARRANT_TYPE_NOT_SUBPOENA"
    end

    local scope = tostring(warrant.subpoena_scope or warrant.subpoenaScope or "financial"):lower()
    if scope ~= "all" and scope ~= "financial" and scope ~= "corporate" then
        return false, string.format("INVALID_SUBPOENA_SCOPE_%s", scope)
    end

    -- If target_entity_id is set, it must match or match target prefix
    local entityId = warrant.target_entity_id or warrant.targetEntityId
    if entityId and targetId then
        local cleanEntity = string.lower(entityId)
        local cleanTarget = string.lower(targetId)
        if cleanEntity ~= cleanTarget and not string.find(cleanEntity, cleanTarget, 1, true) and not string.find(cleanTarget, cleanEntity, 1, true) then
            return false, string.format("SUBPOENA_ENTITY_MISMATCH_EXPECTED_%s_GOT_%s", cleanEntity, cleanTarget)
        end
    end

    return true, {
        warrantId = warrant.warrant_id or warrant.warrantId or "UNKNOWN",
        subpoenaScope = scope,
        judicialSignature = warrant.judicial_signature or warrant.judicialSignature or "SEALED"
    }
end

-- 4. Format Audit Summary for Logs & Inspector Displays
function Nyx.SubpoenaAudit.FormatAuditSummary(report)
    if not report then return "No audit data." end
    local lines = {
        string.format("=== FORENSIC SUBPOENA AUDIT REPORT [%s] ===", (report.reportHash or ""):sub(1, 12):upper()),
        string.format("Total Volume Audited: $%.2f | Cash Ratio: %.1f%%", report.totalVolume or 0.00, report.cashRatioPct or 0.0),
        string.format("Anomaly Score: %.2f/100.00 | Risk Level: %s", report.anomalyScore or 0.0, string.upper(report.suspicionLevel or "clean")),
        string.format("Recommendation: %s", report.recommendation or "None")
    }

    if report.anomalies and #report.anomalies > 0 then
        table.insert(lines, "Identified Irregularities:")
        for i, a in ipairs(report.anomalies) do
            table.insert(lines, string.format("  [%d] %s (+%.1f pts): %s", i, a.code, a.weight or 0.0, a.description or ""))
        end
    else
        table.insert(lines, "  No anomalous indicators detected.")
    end

    return table.concat(lines, "\n")
end
