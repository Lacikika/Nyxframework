--[[
    Nyxframework: nyx_factions
    File: shared/equity.lua
    Description: Pure Lua 5.4 domain engine for corporate equity public offerings (IPO),
                 consolidated shareholder cap table math, and automated weekly dividend
                 distribution calculations with zero-cent conservation.
]]

Nyx = Nyx or {}
Nyx.Equity = Nyx.Equity or {}

-- ----------------------------------------------------------------------------
-- 1. Configuration Constants & Statutory Governance Rules
-- ----------------------------------------------------------------------------
Nyx.Equity.MinPurchaseShares = 0.10         -- Minimum 0.10% equity share purchase
Nyx.Equity.MaxPurchaseShares = 50.00        -- Max 50.00% equity share purchase per single order
Nyx.Equity.MinReinvestmentRate = 0.10       -- Minimum 10% retained earnings constitution floor
Nyx.Equity.MaxReinvestmentRate = 0.50       -- Maximum 50% retained earnings constitution ceiling
Nyx.Equity.DefaultReinvestmentRate = 0.20   -- Default 20% retained for corporate operating reserves
Nyx.Equity.DefaultDividendFrequencyDays = 7 -- Weekly automated dividend cycle (7 days)
Nyx.Equity.OperationalReserveFloor = 5000.00 -- Minimum treasury balance required before dividends can disburse

Nyx.Equity.EligibleCharters = {
    ['corporation'] = true,
    ['private_enterprise'] = true,
    ['syndicate'] = true
}

-- ----------------------------------------------------------------------------
-- 2. Precision Math Helpers
-- ----------------------------------------------------------------------------
local function round2(num)
    return math.floor((tonumber(num) or 0.0) * 100 + 0.5) / 100
end

local function clamp(val, minVal, maxVal)
    if val < minVal then return minVal end
    if val > maxVal then return maxVal end
    return val
end

-- ----------------------------------------------------------------------------
-- 3. Valuation & Capital Raising Math
-- ----------------------------------------------------------------------------

--- Computes target capital raise and implied enterprise market capitalization
-- @param sharesOffered number Percentage of total equity offered (e.g. 25.00)
-- @param pricePerShare number Price per 1.00% share (e.g. 2000.00)
-- @return table Valuation breakdown
function Nyx.Equity.CalculateOfferingValuation(sharesOffered, pricePerShare)
    local shares = tonumber(sharesOffered) or 0.00
    local pps = tonumber(pricePerShare) or 0.00

    if shares <= 0 or pps <= 0 then
        return {
            sharesOffered = 0.00,
            pricePerShare = 0.00,
            targetCapital = 0.00,
            impliedMarketCap = 0.00
        }
    end

    local targetCapital = round2(shares * pps)
    local impliedMarketCap = round2(pps * 100.00)

    return {
        sharesOffered = shares,
        pricePerShare = pps,
        targetCapital = targetCapital,
        impliedMarketCap = impliedMarketCap
    }
end

--- Computes total acquisition cost for an equity share purchase
-- @param shares number Quantity of shares (percentage points)
-- @param pricePerShare number Unit price per 1.00% share
-- @return number Total purchase price rounded to cents
function Nyx.Equity.CalculatePurchaseCost(shares, pricePerShare)
    local s = tonumber(shares) or 0.00
    local pps = tonumber(pricePerShare) or 0.00
    if s <= 0 or pps <= 0 then return 0.00 end
    return round2(s * pps)
end

-- ----------------------------------------------------------------------------
-- 4. Zero-Trust Offering Creation & Purchase Validators
-- ----------------------------------------------------------------------------

--- Validates whether a corporation is eligible to issue a public equity offering
-- @param faction table Corporate entity record from nyx_factions_registry
-- @param data table Offering input parameters (title, prospectus, sharesOffered, pricePerShare, minPurchase, maxPurchase, durationHours)
-- @param currentIssuedEquity number Total percentage of equity currently issued/reserved
-- @return boolean isValid
-- @return table|string cleanData or error code
function Nyx.Equity.ValidateOfferingCreation(faction, data, currentIssuedEquity)
    if not faction or type(faction) ~= "table" then
        return false, "INVALID_FACTION_ENTITY"
    end

    if faction.is_active ~= 1 and faction.is_active ~= true then
        return false, "FACTION_INACTIVE"
    end

    local charterType = faction.charter_type or "unknown"
    if not Nyx.Equity.EligibleCharters[charterType] then
        return false, "CHARTER_INELIGIBLE_FOR_EQUITY_OFFERING"
    end

    if not data or type(data) ~= "table" then
        return false, "INVALID_OFFERING_DATA"
    end

    local title = tostring(data.title or ""):gsub("^%s*(.-)%s*$", "%1")
    if #title < 3 or #title > 128 then
        return false, "INVALID_OFFERING_TITLE"
    end

    local prospectus = tostring(data.prospectus or ""):gsub("^%s*(.-)%s*$", "%1")

    local sharesOffered = tonumber(data.sharesOffered) or 0.00
    if sharesOffered <= 0.00 then
        return false, "INVALID_SHARES_OFFERED"
    end

    local issued = tonumber(currentIssuedEquity) or 0.00
    local availableEquity = round2(100.00 - issued)
    if sharesOffered > availableEquity then
        return false, string.format("OFFERING_EXCEEDS_UNISSUED_EQUITY_AVAILABLE_%.2f", availableEquity)
    end

    local pricePerShare = tonumber(data.pricePerShare) or 0.00
    if pricePerShare < 1.00 then
        return false, "PRICE_PER_SHARE_BELOW_MINIMUM"
    end

    local minPurchase = tonumber(data.minPurchase) or Nyx.Equity.MinPurchaseShares
    if minPurchase < 0.05 or minPurchase > sharesOffered then
        return false, "INVALID_MIN_PURCHASE_BOUNDS"
    end

    local maxPurchase = tonumber(data.maxPurchase) or sharesOffered
    if maxPurchase < minPurchase or maxPurchase > sharesOffered then
        return false, "INVALID_MAX_PURCHASE_BOUNDS"
    end

    local durationHours = tonumber(data.durationHours) or (7 * 24)
    if durationHours < 1 or durationHours > (90 * 24) then
        return false, "INVALID_OFFERING_DURATION_HOURS"
    end

    local valuation = Nyx.Equity.CalculateOfferingValuation(sharesOffered, pricePerShare)

    return true, {
        factionId = faction.faction_id,
        title = title,
        prospectus = prospectus,
        totalSharesOffered = sharesOffered,
        sharesAvailable = sharesOffered,
        pricePerShare = pricePerShare,
        minPurchase = minPurchase,
        maxPurchase = maxPurchase,
        targetCapital = valuation.targetCapital,
        impliedMarketCap = valuation.impliedMarketCap,
        durationHours = durationHours
    }
end

--- Validates an equity share purchase request from an investor
-- @param offering table Offering record from database
-- @param buyerCitizenId string Citizen ID of the investor
-- @param sharesRequested number Shares requested to buy
-- @param buyerBalance number Investor bank liquidity
-- @param currentUnix number Current epoch timestamp
-- @return boolean isValid
-- @return table|string purchaseDetails or error code
function Nyx.Equity.ValidatePurchaseRequest(offering, buyerCitizenId, sharesRequested, buyerBalance, currentUnix)
    if not offering or type(offering) ~= "table" then
        return false, "OFFERING_NOT_FOUND"
    end

    if offering.status ~= "active" then
        return false, "OFFERING_NOT_ACTIVE"
    end

    if currentUnix and offering.expires_at_unix and currentUnix > offering.expires_at_unix then
        return false, "OFFERING_EXPIRED"
    end

    if not buyerCitizenId or type(buyerCitizenId) ~= "string" or #buyerCitizenId < 3 then
        return false, "INVALID_BUYER_CITIZEN_ID"
    end

    local shares = tonumber(sharesRequested) or 0.00
    if shares <= 0.00 then
        return false, "INVALID_PURCHASE_AMOUNT"
    end

    local minP = tonumber(offering.min_purchase) or Nyx.Equity.MinPurchaseShares
    local maxP = tonumber(offering.max_purchase) or offering.total_shares_offered
    local avail = tonumber(offering.shares_available) or 0.00

    if shares < minP then
        return false, string.format("PURCHASE_BELOW_MINIMUM_%.2f", minP)
    end

    if shares > maxP then
        return false, string.format("PURCHASE_EXCEEDS_MAXIMUM_%.2f", maxP)
    end

    if shares > avail then
        return false, string.format("PURCHASE_EXCEEDS_AVAILABLE_SHARES_%.2f", avail)
    end

    local pps = tonumber(offering.price_per_share) or 0.00
    local totalCost = Nyx.Equity.CalculatePurchaseCost(shares, pps)
    local balance = tonumber(buyerBalance) or 0.00

    if balance < totalCost then
        return false, string.format("INSUFFICIENT_FUNDS_REQUIRED_%.2f", totalCost)
    end

    return true, {
        offeringId = offering.offering_id,
        factionId = offering.faction_id,
        buyerCitizenId = buyerCitizenId,
        shares = shares,
        pricePerShare = pps,
        totalCost = totalCost,
        remainingAvailable = round2(avail - shares)
    }
end

-- ----------------------------------------------------------------------------
-- 5. Dividend Distribution Math Engine (Zero-Cent Conservation)
-- ----------------------------------------------------------------------------

--- Authoritative Dividend Distribution Calculator
-- Enforces closed-loop conservation: Sum(Payouts) + RetainedReserves == DeclaredNetProfit
-- @param declaredNetProfit number Net profit allocated for distribution
-- @param reinvestmentRate number Ratio of profit retained in corporate reserves (0.10 to 0.50)
-- @param shareholders table Array of { citizenId = string, equityShares = number, roleTitle = string }
-- @return boolean ok
-- @return table|string breakdown or error code
function Nyx.Equity.CalculateDividendDistribution(declaredNetProfit, reinvestmentRate, shareholders)
    local profit = round2(tonumber(declaredNetProfit) or 0.00)
    if profit <= 0.00 then
        return false, "INVALID_PROFIT_AMOUNT"
    end

    if not shareholders or #shareholders == 0 then
        return false, "NO_EQUITY_SHAREHOLDERS"
    end

    local rate = tonumber(reinvestmentRate) or Nyx.Equity.DefaultReinvestmentRate
    rate = clamp(rate, Nyx.Equity.MinReinvestmentRate, Nyx.Equity.MaxReinvestmentRate)

    -- Retained Operating Reserves = NetProfits * r_reinvest
    local initialRetained = round2(profit * rate)
    local distributablePool = round2(profit - initialRetained)

    -- Calculate total equity shares in cap table
    local totalShares = 0.00
    for _, s in ipairs(shareholders) do
        totalShares = totalShares + (tonumber(s.equityShares) or 0.00)
    end
    totalShares = round2(totalShares)

    if totalShares <= 0.00 then
        return false, "ZERO_TOTAL_EQUITY"
    end

    local payouts = {}
    local totalDisbursed = 0.00

    for _, s in ipairs(shareholders) do
        local shares = tonumber(s.equityShares) or 0.00
        if shares > 0.00 then
            local fraction = shares / totalShares
            -- Floor to cents to prevent fractional money creation
            local payout = math.floor((distributablePool * fraction) * 100) / 100
            totalDisbursed = round2(totalDisbursed + payout)

            table.insert(payouts, {
                citizenId = s.citizenId,
                roleTitle = s.roleTitle or "Shareholder",
                equityShares = shares,
                fraction = fraction,
                payoutAmount = payout
            })
        end
    end

    -- Sub-cent remainder dust is preserved and added back to retained reserves
    local subCentRemainder = round2(distributablePool - totalDisbursed)
    local finalRetainedReserves = round2(initialRetained + subCentRemainder)

    -- Mathematical conservation verification: Sum(Payouts) + FinalRetained == DeclaredProfit
    local balanceCheck = round2(totalDisbursed + finalRetainedReserves)
    if math.abs(balanceCheck - profit) > 0.001 then
        return false, string.format("CONSERVATION_VIOLATION_DELTA_%.4f", math.abs(balanceCheck - profit))
    end

    return true, {
        declaredNetProfit = profit,
        reinvestmentRate = rate,
        initialRetained = initialRetained,
        distributablePool = distributablePool,
        subCentRemainder = subCentRemainder,
        retainedReserves = finalRetainedReserves,
        totalDisbursed = totalDisbursed,
        totalShares = totalShares,
        shareholderCount = #payouts,
        payouts = payouts
    }
end

-- ----------------------------------------------------------------------------
-- 6. Weekly Automated Dividend Cycle Eligibility Evaluator
-- ----------------------------------------------------------------------------

--- Evaluates whether a corporation is currently due for an automated dividend distribution
-- @param faction table Corporate entity record from database
-- @param treasuryBalance number Current corporate treasury balance
-- @param lastDividendRunUnix number Timestamp of last dividend run
-- @param currentUnix number Current epoch timestamp
-- @param options table Optional overrides (reserveFloor, frequencyDays, reinvestmentRate)
-- @return boolean isEligible
-- @return number|string recommendedProfit or status/reason
-- @return number surplusBalance
function Nyx.Equity.EvaluateDividendEligibility(faction, treasuryBalance, lastDividendRunUnix, currentUnix, options)
    options = options or {}
    local floor = tonumber(options.reserveFloor) or Nyx.Equity.OperationalReserveFloor
    local freqDays = tonumber(options.frequencyDays) or (faction and faction.dividend_frequency_days) or Nyx.Equity.DefaultDividendFrequencyDays
    local freqSec = freqDays * 86400

    local lastRun = tonumber(lastDividendRunUnix) or 0
    local now = tonumber(currentUnix) or os.time()

    -- Check if weekly frequency cycle has elapsed
    local elapsed = now - lastRun
    if lastRun > 0 and elapsed < freqSec then
        return false, "SCHEDULE_INTERVAL_NOT_ELAPSED", 0.00
    end

    local bal = round2(tonumber(treasuryBalance) or 0.00)
    local surplus = round2(bal - floor)

    -- Company must have operating funds above the minimum constitutional reserve floor
    if surplus <= 0.00 then
        return false, "INSUFFICIENT_LIQUIDITY_SURPLUS", surplus
    end

    -- Conservative profit distribution: disburse up to 25% of surplus above floor, retaining the rest
    local recommendedProfit = round2(surplus * 0.25)
    if recommendedProfit < 100.00 then
        return false, "SURPLUS_BELOW_MINIMUM_DISTRIBUTION_THRESHOLD", surplus
    end

    return true, recommendedProfit, surplus
end

-- ----------------------------------------------------------------------------
-- 7. Zero-Trust Payload Sanitizers & Display Formatters
-- ----------------------------------------------------------------------------

function Nyx.Equity.ValidateOfferingPayload(raw)
    if type(raw) ~= "table" then return false, "PAYLOAD_NOT_A_TABLE" end
    local factionId = tostring(raw.factionId or ""):gsub("^%s*(.-)%s*$", "%1")
    local title = tostring(raw.title or ""):gsub("^%s*(.-)%s*$", "%1")
    local sharesOffered = tonumber(raw.sharesOffered) or 0.00
    local pricePerShare = tonumber(raw.pricePerShare) or 0.00

    if #factionId < 2 then return false, "INVALID_FACTION_ID" end
    if #title < 3 then return false, "INVALID_TITLE" end
    if sharesOffered <= 0 or sharesOffered > 100 then return false, "INVALID_SHARES" end
    if pricePerShare <= 0 then return false, "INVALID_PRICE" end

    return true, {
        factionId = factionId,
        title = title,
        prospectus = raw.prospectus and tostring(raw.prospectus) or "",
        sharesOffered = round2(sharesOffered),
        pricePerShare = round2(pricePerShare),
        minPurchase = tonumber(raw.minPurchase) or Nyx.Equity.MinPurchaseShares,
        maxPurchase = tonumber(raw.maxPurchase) or sharesOffered,
        durationHours = tonumber(raw.durationHours) or (7 * 24)
    }
end

function Nyx.Equity.ValidatePurchasePayload(raw)
    if type(raw) ~= "table" then return false, "PAYLOAD_NOT_A_TABLE" end
    local offeringId = tostring(raw.offeringId or ""):gsub("^%s*(.-)%s*$", "%1")
    local shares = tonumber(raw.shares) or 0.00

    if #offeringId < 2 then return false, "INVALID_OFFERING_ID" end
    if shares <= 0 then return false, "INVALID_SHARES_AMOUNT" end

    return true, {
        offeringId = offeringId,
        shares = round2(shares)
    }
end

function Nyx.Equity.ValidateDividendPayload(raw)
    if type(raw) ~= "table" then return false, "PAYLOAD_NOT_A_TABLE" end
    local factionId = tostring(raw.factionId or ""):gsub("^%s*(.-)%s*$", "%1")
    local netProfit = tonumber(raw.netProfit) or 0.00
    local reinvestmentRate = tonumber(raw.reinvestmentRate) or Nyx.Equity.DefaultReinvestmentRate

    if #factionId < 2 then return false, "INVALID_FACTION_ID" end
    if netProfit <= 0 then return false, "INVALID_PROFIT_AMOUNT" end

    return true, {
        factionId = factionId,
        netProfit = round2(netProfit),
        reinvestmentRate = clamp(reinvestmentRate, Nyx.Equity.MinReinvestmentRate, Nyx.Equity.MaxReinvestmentRate)
    }
end

function Nyx.Equity.FormatEquityBadge(shares)
    return string.format("%.2f%% Equity", tonumber(shares) or 0.00)
end

function Nyx.Equity.FormatCurrency(amount)
    return string.format("$%.2f", tonumber(amount) or 0.00)
end
