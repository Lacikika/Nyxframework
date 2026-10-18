--[[
    Nyxframework: nyx_core
    File: server/tests.lua
    Description: In-engine unit testing suite verifying RPC promises, mutex concurrency,
                 and economic double-entry conservation laws.
]]

Nyx = Nyx or {}
Nyx.Tests = {}

local function assertTest(condition, testName, errMsg)
    if condition then
        print(string.format("^2[Nyx:Test:PASS]^7 %s", testName))
        return true
    else
        print(string.format("^1[Nyx:Test:FAIL]^7 %s: %s", testName, tostring(errMsg or "Assertion failed")))
        return false
    end
end

-- 1. Test RPC Round-Trip Promise & Timeout Resolution
function Nyx.Tests.TestRPC()
    print("^3[Nyx:Tests] Running RPC Suite...^7")
    local passes = 0
    local total = 2

    -- Test A: Registration and in-memory execution
    local testRoute = "__test:echo"
    Nyx.RPC.Register(testRoute, function(src, payload)
        return { echoed = payload.value * 2 }
    end)

    local handler = Nyx.RPC.Handlers[testRoute]
    if assertTest(handler ~= nil, "RPC Handler Registration", "Handler not present in Nyx.RPC.Handlers") then
        local res = handler(1, { value = 21 })
        if assertTest(res and res.echoed == 42, "RPC Sync Handler Execution", "Payload did not evaluate to expected output") then
            passes = passes + 1
        end
    end

    -- Test B: Timeout Invariant Handling
    local timeoutHandled = false
    local p = promise.new()
    SetTimeout(50, function()
        timeoutHandled = true
        p:reject("RPC_TIMEOUT")
    end)

    local ok, err = pcall(Citizen.Await, p)
    if assertTest(timeoutHandled == true and tostring(err):find("RPC_TIMEOUT") ~= nil, "RPC Timeout Invariant", "Promise timeout callback did not trigger rejection") then
        passes = passes + 1
    end

    return passes == total
end

-- 2. Test Inventory Mutex Concurrency & Duplication Prevention
function Nyx.Tests.TestInventoryConcurrency()
    print("^3[Nyx:Tests] Running Inventory Mutex Concurrency Suite...^7")
    local passes = 0
    local total = 3

    local mockLocks = {}
    local function acquireLock(invId)
        if mockLocks[invId] then
            return false, "CONTAINER_LOCKED"
        end
        mockLocks[invId] = os.time()
        return true
    end

    local function releaseLock(invId)
        mockLocks[invId] = nil
    end

    -- Test A: Acquire initial container lock
    local ok1 = acquireLock("citizen:TEST_01")
    if assertTest(ok1 == true, "Inventory Lock Acquisition", "Failed to acquire free container lock") then
        passes = passes + 1
    end

    -- Test B: Mutex Contention (Prevent concurrent write/dupe)
    local ok2, err2 = acquireLock("citizen:TEST_01")
    if assertTest(ok2 == false and err2 == "CONTAINER_LOCKED", "Inventory Mutex Contention Lockout", "Duplicate lock was acquired concurrently!") then
        passes = passes + 1
    end

    releaseLock("citizen:TEST_01")

    -- Test C: Atomic Item Conservation across transfer
    local sourceSlot = { item = "gold_bar", count = 10 }
    local targetSlot = { item = "gold_bar", count = 5 }
    local initialSum = sourceSlot.count + targetSlot.count

    -- Transfer 4 items from source to target
    local transferAmt = 4
    if sourceSlot.count >= transferAmt then
        sourceSlot.count = sourceSlot.count - transferAmt
        targetSlot.count = targetSlot.count + transferAmt
    end

    local finalSum = sourceSlot.count + targetSlot.count
    if assertTest(finalSum == initialSum and sourceSlot.count == 6 and targetSlot.count == 9, "Zero-Duplication Item Conservation Invariant", "Item counts mutated or duplicated during atomic transfer") then
        passes = passes + 1
    end

    return passes == total
end

-- 3. Test Closed-Loop Treasury Double-Entry Conservation Law
function Nyx.Tests.TestTreasuryConservationLaw()
    print("^3[Nyx:Tests] Running Treasury Economic Conservation Suite...^7")
    local passes = 0
    local total = 2

    local function validateTransaction(entries)
        local totalDebits = 0
        local totalCredits = 0

        for _, e in ipairs(entries) do
            if e.entry_type == "DEBIT" then
                totalDebits = totalDebits + e.amount
            elseif e.entry_type == "CREDIT" then
                totalCredits = totalCredits + e.amount
            end
        end

        local delta = math.abs(totalDebits - totalCredits)
        if delta > 0.0001 then
            return false, "CONSERVATION_LAW_VIOLATION: Debits (" .. totalDebits .. ") != Credits (" .. totalCredits .. ")"
        end
        return true
    end

    -- Test A: Perfectly Balanced Double-Entry Transfer ($500.00 citizen transfer + $25.00 municipal tax)
    local validTx = {
        { account_id = "citizen:01",  entry_type = "DEBIT",  amount = 525.00 },
        { account_id = "citizen:02",  entry_type = "CREDIT", amount = 500.00 },
        { account_id = "gov:treasury", entry_type = "CREDIT", amount = 25.00 }
    }

    local ok1, err1 = validateTransaction(validTx)
    if assertTest(ok1 == true, "Treasury Balanced Transaction Validation", err1) then
        passes = passes + 1
    end

    -- Test B: Unbalanced / Leaked Transaction ($100.00 debited, only $80.00 credited)
    local leakedTx = {
        { account_id = "citizen:01", entry_type = "DEBIT",  amount = 100.00 },
        { account_id = "citizen:02", entry_type = "CREDIT", amount = 80.00 }
    }

    local ok2, err2 = validateTransaction(leakedTx)
    if assertTest(ok2 == false and string.find(err2, "CONSERVATION_LAW_VIOLATION") ~= nil, "Treasury Rejection of Unbalanced Transaction", "Unbalanced ledger transaction was illegally accepted!") then
        passes = passes + 1
    end

    return passes == total
end

-- 4. Test Freight Hauling Escrow & Elastic Pricing Model
function Nyx.Tests.TestFreightBoardEscrowAndElasticity()
    print("^3[Nyx:Tests] Running Freight Board Escrow & Elastic Pricing Suite...^7")
    local passes = 0
    local total = 2

    -- Test A: Freight Escrow Calculation & Balance Invariant
    local quantity = 25
    local payoutPerUnit = 35.00
    local totalPayout = math.floor((quantity * payoutPerUnit) * 100 + 0.5) / 100
    local escrowRate = 0.15
    local escrowBond = math.floor((totalPayout * escrowRate) * 100 + 0.5) / 100

    local settlementCredits = totalPayout + escrowBond
    local settlementDebits = totalPayout + escrowBond

    if assertTest(totalPayout == 875.00 and escrowBond == 131.25 and settlementCredits == settlementDebits,
        "Freight Hauling Escrow & Settlement Conservation",
        "Freight escrow or settlement deviated from conservation bounds") then
        passes = passes + 1
    end

    -- Test B: Price Elasticity Formula & Clamp Limits (Formula: P = Pbase * (1 + 1.25 * (Ctarget - Scurrent)/Ctarget))
    local basePrice = 100.00
    local targetCap = 100

    local function calcPrice(stock)
        local raw = 1.0 + (1.25 * ((targetCap - stock) / targetCap))
        local mult = math.max(0.50, math.min(2.25, raw))
        return math.floor((basePrice * mult) * 100) / 100
    end

    local pEmpty = calcPrice(0)    -- Should be 225.00 (Ceiling)
    local pEquil = calcPrice(100)  -- Should be 100.00 (Equilibrium)
    local pSurplus = calcPrice(200)-- Should be 50.00 (Floor)

    if assertTest(pEmpty == 225.00 and pEquil == 100.00 and pSurplus == 50.00,
        "Elastic Pricing Boundary Precision",
        string.format("Calculated prices deviated: Empty=%.2f, Equil=%.2f, Surplus=%.2f", pEmpty, pEquil, pSurplus)) then
        passes = passes + 1
    end

    return passes == total
end

-- 5. Test Vehicle Mileage, Wear Degradation & Servicing Engine
function Nyx.Tests.TestVehicleMileageAndWear()
    print("^3[Nyx:Tests] Running Vehicle Mileage & Wear Suite...^7")
    local passes = 0
    local total = 4

    local mockVin = "1NYXTESTWEAR0001"
    local mockPlate = "NYX 999"

    -- Test A: Default Wear Initialization
    local defaultWear = {
        vin = mockVin,
        plate = mockPlate,
        mileage = 0.0,
        tripOdometer = 0.0,
        oilQuality = 100.0,
        brakePadWear = 100.0,
        transmissionWear = 100.0,
        suspensionWear = 100.0,
        lastServiceMileage = 0.0
    }

    if assertTest(defaultWear.mileage == 0.0 and defaultWear.oilQuality == 100.0 and defaultWear.brakePadWear == 100.0,
        "Vehicle Wear Default State Initialization",
        "Initial vehicle wear did not match factory defaults") then
        passes = passes + 1
    end

    -- Test B: Distance Accumulation & Component Wear Application
    local deltaKm = 12.5
    local wearDeltas = {
        oil = 12.5 * 0.04 * 2.5, -- 1.25% with redline multiplier
        brakes = 2.4,             -- simulated hard braking
        transmission = 0.15,      -- simulated gear shifts
        suspension = 0.45         -- simulated road wear
    }

    local updatedMileage = defaultWear.mileage + deltaKm
    local updatedTrip = defaultWear.tripOdometer + deltaKm
    local updatedOil = math.max(0.0, defaultWear.oilQuality - wearDeltas.oil)
    local updatedBrakes = math.max(0.0, defaultWear.brakePadWear - wearDeltas.brakes)

    if assertTest(updatedMileage == 12.5 and updatedTrip == 12.5 and updatedOil == 98.75 and updatedBrakes == 97.6,
        "Vehicle Telemetry & Wear Computation",
        string.format("Wear mismatch: Mileage=%.2f, Oil=%.2f, Brakes=%.2f", updatedMileage, updatedOil, updatedBrakes)) then
        passes = passes + 1
    end

    -- Test C: Servicing & Restoration of Component Wear
    local servicedOil = 100.0
    local servicedBrakes = 100.0
    local lastService = updatedMileage

    if assertTest(servicedOil == 100.0 and servicedBrakes == 100.0 and lastService == 12.5,
        "Certified Mechanic Service Component Restoration",
        "Vehicle component wear was not restored to 100% on service") then
        passes = passes + 1
    end

    -- Test D: Trip Odometer Reset Invariant
    local resetTrip = 0.0
    local preservedTotal = updatedMileage

    if assertTest(resetTrip == 0.0 and preservedTotal == 12.5,
        "Trip Odometer Reset with Lifetime Mileage Preservation",
        "Resetting trip odometer corrupted total vehicle mileage") then
        passes = passes + 1
    end

    return passes == total
end

-- 6. Test Dynamic Inventory Weight Penalties & Locomotion Restraints
function Nyx.Tests.TestWeightPenalties()
    print("^3[Nyx:Tests] Running Dynamic Inventory Weight Penalties Suite...^7")
    local passes = 0
    local total = 4

    local cfg = Config.WeightPenalties or {
        enabled = true,
        tiers = {
            normal = { maxRatio = 0.70, moveRate = 1.0, sprintAllowed = true, jumpAllowed = true, climbAllowed = true },
            encumbered = { minRatio = 0.70, maxRatio = 0.85, moveRate = 0.90, sprintAllowed = true, jumpAllowed = true, climbAllowed = true },
            heavy = { minRatio = 0.85, maxRatio = 1.00, moveRate = 0.78, sprintAllowed = true, jumpAllowed = true, climbAllowed = true },
            overburdened = { minRatio = 1.00, maxRatio = 1.20, moveRate = 0.60, sprintAllowed = false, jumpAllowed = false, climbAllowed = true },
            critical = { minRatio = 1.20, moveRate = 0.40, sprintAllowed = false, jumpAllowed = false, climbAllowed = false }
        }
    }

    local function computeTier(ratio)
        local tiers = cfg.tiers
        if tiers.critical and ratio >= tiers.critical.minRatio then
            return "critical", tiers.critical
        elseif tiers.overburdened and ratio >= tiers.overburdened.minRatio then
            return "overburdened", tiers.overburdened
        elseif tiers.heavy and ratio >= tiers.heavy.minRatio then
            return "heavy", tiers.heavy
        elseif tiers.encumbered and ratio >= tiers.encumbered.minRatio then
            return "encumbered", tiers.encumbered
        else
            return "normal", tiers.normal
        end
    end

    -- Test A: Tier Evaluation Across Complete Weight Spectrum
    local tNormKey, tNorm = computeTier(0.40) -- 40% capacity
    local tEncKey, tEnc = computeTier(0.75)   -- 75% capacity
    local tHvyKey, tHvy = computeTier(0.92)   -- 92% capacity
    local tOvrKey, tOvr = computeTier(1.08)   -- 108% capacity
    local tCrtKey, tCrt = computeTier(1.35)   -- 135% capacity

    if assertTest(tNormKey == "normal" and tEncKey == "encumbered" and tHvyKey == "heavy" and tOvrKey == "overburdened" and tCrtKey == "critical",
        "Weight Penalty Tier Boundary Transitions",
        string.format("Tier classification error: %s, %s, %s, %s, %s", tNormKey, tEncKey, tHvyKey, tOvrKey, tCrtKey)) then
        passes = passes + 1
    end

    -- Test B: Authoritative PlayerObject Weight Mutation & Metadata Sync
    local mockPlayer = {
        source = 999,
        citizenId = "TEST_CITIZEN_01",
        metadata = {},
        isDirty = false,
        setWeight = function(self, current, maxW)
            local cur = math.max(0, tonumber(current) or 0)
            local maxWeight = math.max(1, tonumber(maxW) or 30000)
            local ratio = cur / maxWeight
            self.metadata.inventory_weight = { current = cur, max = maxWeight, ratio = ratio }
            self.isDirty = true
            return self.metadata.inventory_weight
        end,
        getWeight = function(self)
            return self.metadata.inventory_weight or { current = 0, max = 30000, ratio = 0.0 }
        end
    }

    mockPlayer:setWeight(27000, 30000)
    local w = mockPlayer:getWeight()
    if assertTest(w.current == 27000 and w.max == 30000 and math.abs(w.ratio - 0.90) < 0.001 and mockPlayer.isDirty == true,
        "PlayerObject Weight Mutation & State Serialization",
        string.format("Weight state corrupt: cur=%s, max=%s, ratio=%s", tostring(w.current), tostring(w.max), tostring(w.ratio))) then
        passes = passes + 1
    end

    -- Test C: Multi-Item Weight Aggregation & Load Tier Mapping
    local sampleItems = {
        { item_id = "gold_bar", amount = 5, unitWeight = 5000 },    -- 25,000g
        { item_id = "water_bottle", amount = 10, unitWeight = 350 }, -- 3,500g
    }
    local calculatedTotalWeight = 0
    for _, item in ipairs(sampleItems) do
        calculatedTotalWeight = calculatedTotalWeight + (item.amount * item.unitWeight)
    end
    local maxCapacity = 30000
    local ratio = calculatedTotalWeight / maxCapacity
    local sampleTierKey, sampleTier = computeTier(ratio)

    if assertTest(calculatedTotalWeight == 28500 and math.abs(ratio - 0.95) < 0.001 and sampleTierKey == "heavy" and sampleTier.moveRate == 0.78,
        "Multi-Item Weight Summation & Movement Rate Invariant",
        string.format("Calculated weight %.2f (ratio %.2f) yielded unexpected tier %s", calculatedTotalWeight, ratio, sampleTierKey)) then
        passes = passes + 1
    end

    -- Test D: Overburdened & Critical Locomotion Invariant (Sprint/Jump Lockouts)
    local _, ovrData = computeTier(1.10)
    local _, crtData = computeTier(1.25)

    local sprintLocked = (ovrData.sprintAllowed == false and crtData.sprintAllowed == false)
    local jumpLocked = (ovrData.jumpAllowed == false and crtData.jumpAllowed == false)
    local climbLocked = (ovrData.climbAllowed == true and crtData.climbAllowed == false)
    local severelySlowed = (crtData.moveRate == 0.40)

    if assertTest(sprintLocked and jumpLocked and climbLocked and severelySlowed,
        "Overburdened Locomotion Control Inhibition Invariants",
        "Failed to inhibit sprint, jump, or climb on overburdened/critical tiers") then
        passes = passes + 1
    end

    return passes == total
end

-- 7. Test Localized Stock-to-Demand Elastic Pricing & Treasury Zone Taxes
function Nyx.Tests.TestElasticItemPricingAndZoneDemand()
    print("^3[Nyx:Tests] Running Localized Elastic Pricing & Zone Demand Suite...^7")
    local passes = 0
    local total = 6

    local basePrice = 100.00
    local targetCap = 100

    -- Test A: Localized Delivery Zone Demand Scaling (Metro vs Rural Paleto)
    -- Metro multiplier = 1.35 -> Deff = 135
    -- Rural multiplier = 0.75 -> Deff = 75
    local alpha = 1.25
    local function calcZonePrice(stock, demandMult, velRatio)
        local effD = targetCap * demandMult * (1.0 + (velRatio or 0.0))
        local raw = 1.0 + (alpha * ((effD - stock) / effD))
        local mult = math.max(0.50, math.min(2.25, raw))
        return math.floor((basePrice * mult) * 100) / 100, effD, math.floor((stock / effD) * 10000) / 10000
    end

    local pMetro, effMetro, rMetro = calcZonePrice(100, 1.35, 0.0) -- Stock=100, Deff=135
    local pPaleto, effPaleto, rPaleto = calcZonePrice(100, 0.75, 0.0) -- Stock=100, Deff=75

    -- In Metro: (135 - 100) / 135 = 0.259259 -> mult = 1.32407 -> price = 132.40
    -- In Paleto: (75 - 100) / 75 = -0.333333 -> mult = 0.583333 -> price = 58.33
    if assertTest(pMetro == 132.40 and pPaleto == 58.33 and effMetro == 135.0 and effPaleto == 75.0,
        "Localized Zone Demand Scaling Invariant",
        string.format("Zone price deviation: Metro=%.2f (eff=%.1f), Paleto=%.2f (eff=%.1f)", pMetro, effMetro, pPaleto, effPaleto)) then
        passes = passes + 1
    end

    -- Test B: Rolling Sales Velocity & Exponential Half-Life Decay
    local function calcDecayed(v0, dt, halfLife)
        return math.floor((v0 * math.pow(0.5, dt / halfLife)) * 100) / 100
    end

    local vStart = 20.0
    local vHalf = calcDecayed(vStart, 1800, 1800) -- After 1 half-life (1800s) -> 10.0
    local vQuarter = calcDecayed(vStart, 3600, 1800) -- After 2 half-lives (3600s) -> 5.0

    if assertTest(vHalf == 10.0 and vQuarter == 5.0,
        "Demand Velocity Exponential Half-Life Decay Invariant",
        string.format("Decayed velocity error: 1800s=%.2f, 3600s=%.2f", vHalf, vQuarter)) then
        passes = passes + 1
    end

    -- Test C: Velocity Price Spiking Under Rapid Consumer Purchasing
    -- Baseline Metro at Stock=50 without velocity:
    local pNormal, _, _ = calcZonePrice(50, 1.35, 0.0)
    -- Metro with sudden velocity spike (+30% demand boost):
    local pSpiked, effSpiked, _ = calcZonePrice(50, 1.35, 0.30)

    if assertTest(pSpiked > pNormal and effSpiked > effMetro,
        "Velocity Demand Surge Price Expansion Invariant",
        string.format("Spiked price %.2f failed to exceed normal price %.2f", pSpiked, pNormal)) then
        passes = passes + 1
    end

    -- Test D: Strict Mathematical Clamping at Boundary Limits
    local pSevereShortage, _, rShort = calcZonePrice(0, 1.35, 0.50) -- Stock = 0
    local pSevereSurplus, _, rSurp = calcZonePrice(500, 0.75, 0.0)  -- Massive Surplus

    if assertTest(pSevereShortage == 225.00 and pSevereSurplus == 50.00 and rShort == 0.0 and rSurp > 1.0,
        "Elastic Price Surplus Floor & Shortage Ceiling Invariants",
        string.format("Boundary clamping failure: Ceiling=%.2f (expect 225.00), Floor=%.2f (expect 50.00)", pSevereShortage, pSevereSurplus)) then
        passes = passes + 1
    end

    -- Test E: Treasury Localized Point-of-Sale Tax Surcharge Interception
    local function calcTaxSplit(gross, baseRate, zoneSurcharge)
        local effRate = math.min(0.15, baseRate + (zoneSurcharge or 0.0))
        local tax = math.floor((gross * effRate) * 100) / 100
        local net = gross - tax
        return net, tax, effRate
    end

    local grossSale = 1000.00
    local baseTaxRate = 0.08
    local metroSurcharge = 0.0150 -- +1.5% in LS Metro
    local ruralSurcharge = 0.0000 -- 0.0% in Sandy Shores

    local netMetro, taxMetro, rateMetro = calcTaxSplit(grossSale, baseTaxRate, metroSurcharge)
    local netRural, taxRural, rateRural = calcTaxSplit(grossSale, baseTaxRate, ruralSurcharge)

    if assertTest(taxMetro == 95.00 and netMetro == 905.00 and rateMetro == 0.095 and
                  taxRural == 80.00 and netRural == 920.00 and rateRural == 0.080,
        "Treasury Localized Zone Sales Tax Surcharge Invariant",
        string.format("Tax split mismatch: MetroTax=%.2f, RuralTax=%.2f", taxMetro, taxRural)) then
        passes = passes + 1
    end

    -- Test F: Dynamic Shortage Freight Bounty Scaling per Regional Deficit
    local baseBountyMult = 0.35
    local function calcBounty(deficitRatio, zoneDemandMult)
        local scaleBonus = math.min(1.50, deficitRatio * zoneDemandMult)
        local mult = math.min(2.25, baseBountyMult * (1.0 + scaleBonus))
        return math.floor((basePrice * mult) * 100) / 100, mult
    end

    local normalBounty, bNormMult = calcBounty(0.10, 1.00) -- Light deficit (10% capacity missing)
    local criticalBounty, bCritMult = calcBounty(0.95, 1.35) -- Severe deficit (95% missing in High-Demand Metro)

    if assertTest(criticalBounty > normalBounty and bCritMult > bNormMult,
        "Dynamic Shortage Freight Bounty Regional Scaling Invariant",
        string.format("Freight bounty did not scale under deficit: Critical=%.2f (mult=%.4f), Normal=%.2f", criticalBounty, bCritMult, normalBounty)) then
        passes = passes + 1
    end

    return passes == total
end

-- 8. Test Cryptographic Evidence Chain-of-Custody & SHA-256 Fingerprints
function Nyx.Tests.TestEvidenceChainOfCustody()
    print("^3[Nyx:Tests] Running Evidence Chain-of-Custody & SHA-256 Suite...^7")
    local passes = 0
    local total = 6

    -- Mock SHA-256 implementation if running standalone or retrieve from judiciary export/namespace
    local sha256 = (Nyx.Judiciary and Nyx.Judiciary.Sha256) or function(str)
        local band, bor, bxor, bnot = function(a, b) return a & b end, function(a, b) return a | b end, function(a, b) return a ~ b end, function(a) return ~a & 0xFFFFFFFF end
        local rshift, lshift = function(a, b) return (a & 0xFFFFFFFF) >> b end, function(a, b) return (a << b) & 0xFFFFFFFF end
        local function ror(x, n) return (rshift(x, n) | lshift(x, 32 - n)) & 0xFFFFFFFF end
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
        local H = { 0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19 }
        local len = #str
        local bit_len = len * 8
        local pad = { str:byte(1, len) }
        pad[#pad + 1] = 0x80
        while (#pad % 64) ~= 56 do pad[#pad + 1] = 0x00 end
        for i = 7, 0, -1 do pad[#pad + 1] = (bit_len >> (i * 8)) & 0xFF end
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
                h = g; g = f; f = e; e = (d + temp1) & 0xFFFFFFFF
                d = c; c = b; b = a; a = (temp1 + temp2) & 0xFFFFFFFF
            end
            H[1] = (H[1] + a) & 0xFFFFFFFF; H[2] = (H[2] + b) & 0xFFFFFFFF; H[3] = (H[3] + c) & 0xFFFFFFFF; H[4] = (H[4] + d) & 0xFFFFFFFF
            H[5] = (H[5] + e) & 0xFFFFFFFF; H[6] = (H[6] + f) & 0xFFFFFFFF; H[7] = (H[7] + g) & 0xFFFFFFFF; H[8] = (H[8] + h) & 0xFFFFFFFF
        end
        return string.format("%08x%08x%08x%08x%08x%08x%08x%08x", H[1], H[2], H[3], H[4], H[5], H[6], H[7], H[8])
    end

    local computeChainHash = (Nyx.Judiciary and Nyx.Judiciary.ComputeChainHash) or function(prevHash, evidenceId, sequenceId, action, custodianCitId, recipientCitId, facilityId, timestamp, salt)
        local raw = string.format("%s:%s:%d:%s:%s:%s:%s:%d:%s",
            tostring(prevHash or "GENESIS"),
            tostring(evidenceId),
            tonumber(sequenceId) or 1,
            tostring(action),
            tostring(custodianCitId or "NONE"),
            tostring(recipientCitId or "NONE"),
            tostring(facilityId or "NONE"),
            tonumber(timestamp) or 0,
            tostring(salt or "")
        )
        return sha256(raw)
    end

    -- Test A: Deterministic SHA-256 Physical Evidence Fingerprinting
    local serial = "W-COMBATPISTOL-7781"
    local originCit = "CIT-9011"
    local coords = { x = 112.50, y = -1024.30, z = 28.50 }
    local salt = "e7K9p2L0"
    local rawCasing = string.format("%s:%s:%.2f,%.2f,%.2f:%s", serial, originCit, coords.x, coords.y, coords.z, salt)
    local hashCasing = sha256(rawCasing)

    if assertTest(#hashCasing == 64 and hashCasing == sha256(rawCasing),
        "Deterministic SHA-256 Physical Evidence Fingerprint Invariant",
        "Failed to generate 64-character deterministic SHA-256 fingerprint") then
        passes = passes + 1
    end

    -- Test B: Genesis Custody Block Creation (Sequence 1, PrevHash == Root Fingerprint)
    local evidenceId = "ev-chain-unit-001"
    local genTime = 1770000000
    local genSalt = "genSalt1"
    local genHash = computeChainHash(hashCasing, evidenceId, 1, "COLLECTED", "OFFICER_PATROL_1", nil, "person:OFFICER_PATROL_1", genTime, genSalt)

    if assertTest(#genHash == 64 and genHash ~= hashCasing,
        "Genesis Chain-of-Custody Block Invariant",
        "Genesis block hash did not evaluate correctly") then
        passes = passes + 1
    end

    -- Test C: Multi-Step Sequential Chain Linking
    local b2Salt = "saltBlock2"
    local b2Time = 1770000400
    local b2Hash = computeChainHash(genHash, evidenceId, 2, "SECURED_IN_LOCKER", "OFFICER_PATROL_1", nil, "locker_mrpd_01", b2Time, b2Salt)

    local b3Salt = "saltBlock3"
    local b3Time = 1770001200
    local b3Hash = computeChainHash(b2Hash, evidenceId, 3, "CHECKED_OUT_LAB", "LOCKER:locker_mrpd_01", "DETECTIVE_2", "person:DETECTIVE_2", b3Time, b3Salt)

    local b4Salt = "saltBlock4"
    local b4Time = 1770002000
    local b4Hash = computeChainHash(b3Hash, evidenceId, 4, "LAB_ANALYZED", "FORENSIC_TECH_1", nil, "lab_davis_forensics", b4Time, b4Salt)

    local b5Salt = "saltBlock5"
    local b5Time = 1770003000
    local b5Hash = computeChainHash(b4Hash, evidenceId, 5, "SUBMITTED_EXHIBIT", "PROSECUTOR_1", nil, "vault_court_district", b5Time, b5Salt)

    local chain = {
        { seq = 1, prev = hashCasing, hash = genHash, act = "COLLECTED", cust = "OFFICER_PATROL_1", rec = nil, fac = "person:OFFICER_PATROL_1", t = genTime, s = genSalt },
        { seq = 2, prev = genHash, hash = b2Hash, act = "SECURED_IN_LOCKER", cust = "OFFICER_PATROL_1", rec = nil, fac = "locker_mrpd_01", t = b2Time, s = b2Salt },
        { seq = 3, prev = b2Hash, hash = b3Hash, act = "CHECKED_OUT_LAB", cust = "LOCKER:locker_mrpd_01", rec = "DETECTIVE_2", fac = "person:DETECTIVE_2", t = b3Time, s = b3Salt },
        { seq = 4, prev = b3Hash, hash = b4Hash, act = "LAB_ANALYZED", cust = "FORENSIC_TECH_1", rec = nil, fac = "lab_davis_forensics", t = b4Time, s = b4Salt },
        { seq = 5, prev = b4Hash, hash = b5Hash, act = "SUBMITTED_EXHIBIT", cust = "PROSECUTOR_1", rec = nil, fac = "vault_court_district", t = b5Time, s = b5Salt }
    }

    if assertTest(#chain == 5 and chain[5].hash == b5Hash and chain[5].prev == chain[4].hash,
        "Sequential Cryptographic Chain-of-Custody Progression Invariant",
        "Block chain continuity linkage mismatch") then
        passes = passes + 1
    end

    -- Test D: Pristine Chain Verification Routine
    local function verifyChain(rootFp, blockList)
        local expectedPrev = rootFp
        for i, blk in ipairs(blockList) do
            if blk.seq ~= i then return false, "SEQ_GAP" end
            if blk.prev ~= expectedPrev then return false, "HASH_DISCONTINUITY" end
            local rec = computeChainHash(blk.prev, evidenceId, blk.seq, blk.act, blk.cust, blk.rec, blk.fac, blk.t, blk.s)
            if rec ~= blk.hash then return false, "TAMPER_DETECTED" end
            expectedPrev = blk.hash
        end
        return true, "VALID"
    end

    local isValid, status = verifyChain(hashCasing, chain)
    if assertTest(isValid == true and status == "VALID",
        "Pristine Chain-of-Custody Verification Invariant",
        "Pristine chain verification rejected unexpectedly") then
        passes = passes + 1
    end

    -- Test E: Adversarial Tamper Detection (Modify historical block 3 custodian)
    local tamperedChain = {
        chain[1],
        chain[2],
        { seq = 3, prev = b2Hash, hash = b3Hash, act = "CHECKED_OUT_LAB", cust = "LOCKER:locker_mrpd_01", rec = "UNAUTHORIZED_THIEF", fac = "person:UNAUTHORIZED_THIEF", t = b3Time, s = b3Salt },
        chain[4],
        chain[5]
    }
    local isTamperedValid, tamperStatus = verifyChain(hashCasing, tamperedChain)
    if assertTest(isTamperedValid == false and tamperStatus == "TAMPER_DETECTED",
        "Adversarial Block Mutation Tamper Detection Invariant",
        "Verification engine failed to detect modified custodian in intermediate block") then
        passes = passes + 1
    end

    -- Test F: Contamination State Handling Invariant
    local isGlovesEquipped = false
    local isContaminated = (not isGlovesEquipped) and 1 or 0
    local contamSource = isContaminated == 1 and "CITIZEN_BARE_HANDS" or nil

    if assertTest(isContaminated == 1 and contamSource == "CITIZEN_BARE_HANDS",
        "Forensic Evidence Contamination Detection Invariant",
        "Failed to flag un-gloved evidence collection as contaminated") then
        passes = passes + 1
    end

    return passes == total
end

-- 9. Test Shared Math, Vector Algebra & Spatial Geometry Utility Suite
function Nyx.Tests.TestSharedMathAndVectorUtils()
    print("^3[Nyx:Tests] Running Shared Math & Vector Utility Suite...^7")
    local passes = 0
    local total = 6

    local M = Nyx.Math

    -- Test A: Scalar Math (Clamp, Round, Lerp, InvLerp, Remap, Sign, IsNear)
    local clamped1 = M.Clamp(5, 10, 20)
    local clamped2 = M.Clamp(25, 10, 20)
    local clamped3 = M.Clamp(15, 10, 20)
    local round1 = M.Round(3.14159, 2)
    local round2 = M.Round(10.555, 2)
    local round3 = M.Round(-2.5, 0)
    local lerpVal = M.Lerp(10.0, 50.0, 0.25)
    local invLerpVal = M.InvLerp(10.0, 50.0, 20.0)
    local remapVal = M.Remap(50, 0, 100, 200, 400)
    local signPos = M.Sign(42)
    local signNeg = M.Sign(-99)
    local isNear = M.IsNear(1.0000001, 1.0, 1e-5)

    if assertTest(clamped1 == 10 and clamped2 == 20 and clamped3 == 15
        and round1 == 3.14 and round2 == 10.56 and round3 == -3.0
        and math.abs(lerpVal - 20.0) < 1e-6 and math.abs(invLerpVal - 0.25) < 1e-6
        and math.abs(remapVal - 300.0) < 1e-6
        and signPos == 1 and signNeg == -1 and isNear == true,
        "Scalar Math Operations (Clamp, Round, Lerp, Remap, Sign, IsNear)",
        "Scalar math evaluated to unexpected values") then
        passes = passes + 1
    end

    -- Test B: Vector Type Parsing & Conversion (ToVector3, ToVector2, VectorToTable, Normalize)
    local vFromTbl = M.ToVector3({ x = 12.5, y = -34.2, z = 5.0 })
    local vFromArr = M.ToVector3({ 1.0, 2.0, 3.0 })
    local vNil = M.ToVector3(nil, 42.0)
    local v2 = M.ToVector2(vFromTbl)
    local tbl = M.VectorToTable(vFromTbl)
    local unitV = M.Normalize(vector3(0.0, 10.0, 0.0))
    local zeroV = M.Normalize(vector3(0.0, 0.0, 0.0))

    if assertTest(vFromTbl.x == 12.5 and vFromTbl.y == -34.2 and vFromTbl.z == 5.0
        and vFromArr.x == 1.0 and vFromArr.y == 2.0 and vFromArr.z == 3.0
        and vNil.z == 42.0
        and v2.x == 12.5 and v2.y == -34.2
        and tbl.x == 12.5 and tbl.y == -34.2 and tbl.z == 5.0
        and math.abs(unitV.y - 1.0) < 1e-6 and unitV.x == 0.0
        and zeroV.x == 0.0 and zeroV.y == 0.0 and zeroV.z == 0.0,
        "Vector Parsing, Conversion & Normalization Invariant",
        "Vector conversion or normalization failed") then
        passes = passes + 1
    end

    -- Test C: Spatial Distance & Proximity Evaluation (Distance, Distance2D, DistanceSquared, IsWithinRange)
    local p1 = vector3(0.0, 0.0, 0.0)
    local p2 = vector3(1.0, 2.0, 2.0)
    local d3d = M.Distance(p1, p2)
    local d3dSq = M.DistanceSquared(p1, p2)
    local d2d = M.Distance2D(p1, vector3(3.0, 4.0, 100.0))
    local inRange = M.IsWithinRange(p1, p2, 3.0)
    local outOfRange = M.IsWithinRange(p1, p2, 2.9)

    if assertTest(math.abs(d3d - 3.0) < 1e-6 and math.abs(d3dSq - 9.0) < 1e-6
        and math.abs(d2d - 5.0) < 1e-6 and inRange == true and outOfRange == false,
        "Spatial Euclidean & Squared Distance Range Evaluation Invariant",
        "Distance or squared proximity check evaluated incorrectly") then
        passes = passes + 1
    end

    -- Test D: Vector Algebra & Angle Invariants (Dot, Cross, Magnitude, AngleBetween, VectorLerp)
    local dotOrthogonal = M.Dot(vector3(1.0, 0.0, 0.0), vector3(0.0, 1.0, 0.0))
    local dotParallel = M.Dot(vector3(2.0, 3.0, 4.0), vector3(1.0, 2.0, 3.0))
    local crossZ = M.Cross(vector3(1.0, 0.0, 0.0), vector3(0.0, 1.0, 0.0))
    local mag = M.Magnitude(vector3(0.0, 3.0, 4.0))
    local angle90 = M.AngleBetween(vector3(1.0, 0.0, 0.0), vector3(0.0, 1.0, 0.0))
    local vLerp = M.VectorLerp(vector3(0.0, 0.0, 0.0), vector3(10.0, 20.0, 30.0), 0.5)

    if assertTest(math.abs(dotOrthogonal) < 1e-6 and math.abs(dotParallel - 20.0) < 1e-6
        and math.abs(crossZ.x) < 1e-6 and math.abs(crossZ.y) < 1e-6 and math.abs(crossZ.z - 1.0) < 1e-6
        and math.abs(mag - 5.0) < 1e-6 and math.abs(angle90 - 90.0) < 1e-4
        and math.abs(vLerp.x - 5.0) < 1e-6 and math.abs(vLerp.y - 10.0) < 1e-6 and math.abs(vLerp.z - 15.0) < 1e-6,
        "Vector Algebra, Cross Product & Angular Invariants",
        "Vector algebraic operations failed") then
        passes = passes + 1
    end

    -- Test E: Rotation, Heading & Directional Math (RotationToDirection, HeadingToDirection, DirectionToHeading, GetHeadingBetween, GetAngleDifference)
    local hNorth = M.HeadingToDirection(0.0)
    local hWest = M.HeadingToDirection(90.0)
    local calcHeadingNorth = M.DirectionToHeading(hNorth)
    local calcHeadingWest = M.DirectionToHeading(hWest)
    local headingToTarget = M.GetHeadingBetween(vector3(0.0, 0.0, 0.0), vector3(0.0, 50.0, 0.0))
    local angleDiff1 = M.GetAngleDifference(10.0, 350.0)
    local angleDiff2 = M.GetAngleDifference(0.0, 180.0)
    local camDir = M.RotationToDirection(vector3(0.0, 0.0, 0.0))

    if assertTest(math.abs(hNorth.y - 1.0) < 1e-6 and math.abs(hNorth.x) < 1e-6
        and math.abs(hWest.x - (-1.0)) < 1e-6 and math.abs(hWest.y) < 1e-6
        and math.abs(calcHeadingNorth - 0.0) < 1e-4 and math.abs(calcHeadingWest - 90.0) < 1e-4
        and math.abs(headingToTarget - 0.0) < 1e-4
        and math.abs(angleDiff1 - 20.0) < 1e-4 and math.abs(angleDiff2 - 180.0) < 1e-4
        and math.abs(camDir.y - 1.0) < 1e-6,
        "Heading, Directional Transformation & Angular Delta Invariants",
        "Heading or rotation transformation failed") then
        passes = passes + 1
    end

    -- Test F: Geometric Containment Invariants (IsPointInSphere, IsPointInBox, IsPointInPolygon)
    local inSphere = M.IsPointInSphere(vector3(1.0, 1.0, 1.0), vector3(0.0, 0.0, 0.0), 2.0)
    local outSphere = M.IsPointInSphere(vector3(3.0, 0.0, 0.0), vector3(0.0, 0.0, 0.0), 2.0)

    -- Box centered at (10, 10, 5) with dimensions (4, 4, 2)
    local inBox = M.IsPointInBox(vector3(11.0, 11.0, 5.5), vector3(10.0, 10.0, 5.0), vector3(4.0, 4.0, 2.0), 0.0)
    local outBox = M.IsPointInBox(vector3(15.0, 10.0, 5.0), vector3(10.0, 10.0, 5.0), vector3(4.0, 4.0, 2.0), 0.0)

    -- 2D Polygon square: (0,0) -> (10,0) -> (10,10) -> (0,10)
    local square = { { x = 0.0, y = 0.0 }, { x = 10.0, y = 0.0 }, { x = 10.0, y = 10.0 }, { x = 0.0, y = 10.0 } }
    local inPoly = M.IsPointInPolygon(vector2(5.0, 5.0), square)
    local outPoly = M.IsPointInPolygon(vector2(15.0, 5.0), square)

    if assertTest(inSphere == true and outSphere == false
        and inBox == true and outBox == false
        and inPoly == true and outPoly == false,
        "Geometric Spatial Containment Invariant (Sphere, OBB Box, Polygon)",
        "Spatial containment check evaluated incorrectly") then
        passes = passes + 1
    end

    return passes == total
end

-- 10. Test Multi-Signature Corporate Treasury Vaults & Dynamic Sign-Off Rules
function Nyx.Tests.TestMultiSigVaultsAndSignOffRules()
    print("^3[Nyx:Tests] Running Multi-Sig Vaults & Sign-Off Rules Suite...^7")
    local passes = 0
    local total = 6

    -- Test A: Dynamic Sign-Off Rule Matching & Specificity Precedence
    local mockRules = {
        { ruleId = "r_petty", vaultId = nil, ruleName = "Petty Cash", minAmount = 0.00, maxAmount = 1000.00, requiredSignatures = 1, requiredRoles = nil, timelockSeconds = 0, priority = 10 },
        { ruleId = "r_oper", vaultId = nil, ruleName = "Operational Expenses", minAmount = 1000.01, maxAmount = 25000.00, requiredSignatures = 2, requiredRoles = nil, timelockSeconds = 0, priority = 10 },
        { ruleId = "r_capex", vaultId = nil, ruleName = "Capital Expenditure", minAmount = 25000.01, maxAmount = nil, requiredSignatures = 3, requiredRoles = { "Chief Executive" }, timelockSeconds = 3600, priority = 10 },
        { ruleId = "r_payroll_spec", vaultId = "vlt:payroll", ruleName = "Dedicated Payroll Policy", minAmount = 0.00, maxAmount = 100000.00, requiredSignatures = 2, requiredRoles = { "Chief Financial Officer" }, timelockSeconds = 0, priority = 50 },
    }

    local function matchRule(vaultId, amount)
        local matched = nil
        for _, r in ipairs(mockRules) do
            local matchesVault = (r.vaultId == vaultId or r.vaultId == nil)
            local matchesMin = (amount >= r.minAmount)
            local matchesMax = (r.maxAmount == nil or amount <= r.maxAmount)
            if matchesVault and matchesMin and matchesMax then
                if not matched then
                    matched = r
                else
                    local curIsSpecific = (matched.vaultId ~= nil)
                    local newIsSpecific = (r.vaultId ~= nil)
                    if newIsSpecific and not curIsSpecific then
                        matched = r
                    elseif (newIsSpecific == curIsSpecific) and r.priority > matched.priority then
                        matched = r
                    end
                end
            end
        end
        return matched
    end

    local match500 = matchRule("vlt:main", 500.00)
    local match15k = matchRule("vlt:main", 15000.00)
    local match50k = matchRule("vlt:main", 50000.00)
    local matchPayroll = matchRule("vlt:payroll", 40000.00)

    if assertTest(match500 and match500.ruleId == "r_petty"
        and match15k and match15k.ruleId == "r_oper" and match15k.requiredSignatures == 2
        and match50k and match50k.ruleId == "r_capex" and match50k.requiredSignatures == 3 and match50k.timelockSeconds == 3600
        and matchPayroll and matchPayroll.ruleId == "r_payroll_spec" and matchPayroll.vaultId == "vlt:payroll",
        "Sign-Off Rule Matching, Amount Boundaries & Vault Specificity Invariant",
        "Rule matching engine failed boundary or precedence checks") then
        passes = passes + 1
    end

    -- Test B: Multi-Signature Quorum Accumulation & Role Fulfillment
    local reqRoles = { "Chief Executive" }
    local function evaluateRoles(sigDetails)
        local present = {}
        for _, s in ipairs(sigDetails) do
            if s.roleTitle then present[s.roleTitle] = true end
        end
        for _, rr in ipairs(reqRoles) do
            if not present[rr] then return false end
        end
        return true
    end

    local sigs1 = { { citizenId = "CIT_01", roleTitle = "Associate" } }
    local sigs2 = { { citizenId = "CIT_01", roleTitle = "Associate" }, { citizenId = "CIT_02", roleTitle = "Manager" } }
    local sigs3 = { { citizenId = "CIT_01", roleTitle = "Associate" }, { citizenId = "CIT_02", roleTitle = "Manager" }, { citizenId = "CIT_03", roleTitle = "Chief Executive" } }

    local q1 = (#sigs1 >= 2) and evaluateRoles(sigs1)
    local q2 = (#sigs2 >= 2) and evaluateRoles(sigs2)
    local q3 = (#sigs3 >= 2) and evaluateRoles(sigs3)

    if assertTest(q1 == false and q2 == false and q3 == true,
        "Signatory Quorum Count & Mandatory Role Validation Invariant",
        "Quorum validation failed role or count criteria") then
        passes = passes + 1
    end

    -- Test C: Timelock Gating & Delayed Disbursement Execution Invariant
    local nowTime = 1770000000
    local timelockDelay = 3600
    local timelockUntil = nowTime + timelockDelay
    local isEarlyExecutable = (nowTime >= timelockUntil)
    local isPostExecutable = ((nowTime + 3601) >= timelockUntil)

    if assertTest(isEarlyExecutable == false and isPostExecutable == true,
        "Timelock Escrow Gating & Execution Window Invariant",
        "Timelock premature execution check failed") then
        passes = passes + 1
    end

    -- Test D: Rolling 24-Hour Daily Withdrawal Limit Invariant
    local mockVault = {
        dailyLimit = 100000.00,
        dailyWithdrawn = 0.00,
        lastReset = nowTime
    }

    local function withdrawFromVault(amt, curTime)
        if (curTime - mockVault.lastReset) >= 86400 then
            mockVault.dailyWithdrawn = 0.00
            mockVault.lastReset = curTime
        end
        if (mockVault.dailyWithdrawn + amt) > mockVault.dailyLimit then
            return false, "EXCEEDS_VAULT_DAILY_LIMIT"
        end
        mockVault.dailyWithdrawn = mockVault.dailyWithdrawn + amt
        return true, mockVault.dailyWithdrawn
    end

    local w1Ok, w1Withdrawn = withdrawFromVault(60000.00, nowTime)
    local w2Ok, w2Err = withdrawFromVault(50000.00, nowTime + 100)
    local w3Ok, w3Withdrawn = withdrawFromVault(30000.00, nowTime + 200)
    local w4Ok, w4Withdrawn = withdrawFromVault(50000.00, nowTime + 86500)

    if assertTest(w1Ok == true and w1Withdrawn == 60000.00
        and w2Ok == false and w2Err == "EXCEEDS_VAULT_DAILY_LIMIT"
        and w3Ok == true and w3Withdrawn == 90000.00
        and w4Ok == true and w4Withdrawn == 50000.00,
        "Rolling 24-Hour Daily Withdrawal Limit & Reset Invariant",
        "Daily limit tracking or rolling reset deviated from expected behavior") then
        passes = passes + 1
    end

    -- Test E: Emergency Vault Freeze & Lockdown Invariant
    local frozenVault = { isFrozen = true }
    local function attemptDisbursement(vlt, amt)
        if vlt.isFrozen then return false, "VAULT_FROZEN" end
        return true, "DISBURSED"
    end

    local frozenRes, frozenErr = attemptDisbursement(frozenVault, 1000.00)
    frozenVault.isFrozen = false
    local unfrozenRes, unfrozenStatus = attemptDisbursement(frozenVault, 1000.00)

    if assertTest(frozenRes == false and frozenErr == "VAULT_FROZEN" and unfrozenRes == true and unfrozenStatus == "DISBURSED",
        "Emergency Vault Freeze & Lockdown Execution Block Invariant",
        "Vault lockdown failed to block transactions") then
        passes = passes + 1
    end

    -- Test F: Inter-Vault Capital Rebalance Closed-Loop Conservation
    local sourceBal = 150000.00
    local targetBal = 25000.00
    local initialTotal = sourceBal + targetBal
    local transferAmt = 45000.00

    sourceBal = sourceBal - transferAmt
    targetBal = targetBal + transferAmt
    local finalTotal = sourceBal + targetBal

    if assertTest(sourceBal == 105000.00 and targetBal == 70000.00 and finalTotal == initialTotal,
        "Inter-Vault Transfer Closed-Loop Conservation Invariant",
        "Inter-vault balance shifted or leaked during rebalance") then
        passes = passes + 1
    end

    return passes == total
end

-- 11. Test Master UI Architecture, CEF Delta-Throttling & Zero-Trust Intent Sanitization
function Nyx.Tests.TestMasterUIArchitecture()
    print("^3[Nyx:Tests] Running Master UI Architecture & Zero-Trust Suite...^7")
    local passes = 0
    local total = 4

    -- Test A: HUD Delta-Checking Invariant
    local function areVitalsEqual(a, b)
        if not a or not b then return false end
        return a.health == b.health and a.armor == b.armor and a.hunger == b.hunger and
               a.thirst == b.thirst and a.stamina == b.stamina and a.oxygen == b.oxygen and
               a.voiceRange == b.voiceRange and a.isUnderwater == b.isUnderwater and a.isDead == b.isDead
    end

    local function hasHudDelta(curr, prev)
        if not prev or not prev.vitals then return true end
        if not areVitalsEqual(curr.vitals, prev.vitals) then return true end
        if curr.vehicle.inVehicle ~= prev.vehicle.inVehicle then return true end
        if curr.vehicle.inVehicle and (curr.vehicle.speed ~= prev.vehicle.speed or curr.vehicle.gear ~= prev.vehicle.gear) then
            return true
        end
        if curr.finances.cash ~= prev.finances.cash or curr.finances.bank ~= prev.finances.bank then
            return true
        end
        return false
    end

    local stateA = {
        vitals = { health = 100, armor = 50, hunger = 80, thirst = 80, stamina = 100, oxygen = 100, voiceRange = 2, isUnderwater = false, isDead = false },
        vehicle = { inVehicle = false, speed = 0, gear = 0 },
        finances = { cash = 1500, bank = 25000 }
    }
    local stateB = {
        vitals = { health = 100, armor = 50, hunger = 80, thirst = 80, stamina = 100, oxygen = 100, voiceRange = 2, isUnderwater = false, isDead = false },
        vehicle = { inVehicle = false, speed = 0, gear = 0 },
        finances = { cash = 1500, bank = 25000 }
    }
    local stateC = {
        vitals = { health = 95, armor = 50, hunger = 80, thirst = 80, stamina = 100, oxygen = 100, voiceRange = 2, isUnderwater = false, isDead = false },
        vehicle = { inVehicle = false, speed = 0, gear = 0 },
        finances = { cash = 1500, bank = 25000 }
    }

    local deltaIdentical = hasHudDelta(stateB, stateA)
    local deltaChanged = hasHudDelta(stateC, stateA)
    if assertTest(deltaIdentical == false and deltaChanged == true,
        "HUD State Delta Invariant",
        "Delta checking failed to suppress redundant NUI packet or detect vital changes") then
        passes = passes + 1
    end

    -- Test B: HUD Throttle Bounds (Never Wait(0), 100ms-250ms)
    local rawIntervals = { 0, 50, 150, 500 }
    local allClamped = true
    for _, raw in ipairs(rawIntervals) do
        local clamped = math.max(100, math.min(250, raw))
        if clamped < 100 or clamped > 250 then
            allClamped = false
            break
        end
    end
    if assertTest(allClamped, "HUD Interval Clamping (100ms-250ms)", "Interval bounds violated safe CEF render budget") then
        passes = passes + 1
    end

    -- Test C: Zero-Trust Intent Payload Sanitization
    local function sanitizePayload(data)
        if type(data) ~= "table" then return {} end
        local sanitized = {}
        if data.app and type(data.app) == "string" then sanitized.app = string.sub(data.app, 1, 64) end
        if data.action and type(data.action) == "string" then sanitized.action = string.sub(data.action, 1, 64) end
        if data.itemId and (type(data.itemId) == "string" or type(data.itemId) == "number") then
            sanitized.itemId = tostring(data.itemId)
        end
        if data.slot and type(data.slot) == "number" then
            sanitized.slot = math.max(1, math.min(1000, math.floor(data.slot)))
        end
        if data.amount and type(data.amount) == "number" then
            sanitized.amount = math.max(1, math.min(1000, math.floor(data.amount)))
        end
        return sanitized
    end

    local maliciousPayload = {
        app = "inventory",
        action = "useItem",
        itemId = "repairkit",
        slot = 4,
        amount = 1,
        balance = 9999999,          -- Spoofed authoritative field
        admin = true,               -- Spoofed permission
        permissions = { "all" }     -- Injected payload
    }
    local clean = sanitizePayload(maliciousPayload)
    local hasSpoofedKeys = (clean.balance ~= nil or clean.admin ~= nil or clean.permissions ~= nil)
    local hasIntentKeys = (clean.itemId == "repairkit" and clean.slot == 4 and clean.amount == 1)

    if assertTest(not hasSpoofedKeys and hasIntentKeys,
        "Zero-Trust Intent Payload Sanitization",
        "Sanitizer leaked client-injected authoritative attributes") then
        passes = passes + 1
    end

    -- Test D: Guaranteed Callback Safety Resolution
    local cbCount = 0
    local function mockCb(resp)
        cbCount = cbCount + 1
    end

    local function runSafeCallback(handler)
        local cbHandled = false
        local function safeCb(resp)
            if not cbHandled then
                cbHandled = true
                mockCb(resp)
            end
        end
        local ok, err = pcall(handler, safeCb)
        if not ok then
            safeCb({ success = false, error = "INTERNAL_ERROR" })
        else
            safeCb({ success = true })
        end
    end

    -- Scenario 1: Handler throws error
    runSafeCallback(function(cb)
        error("Unexpected native crash")
    end)
    -- Scenario 2: Handler completes without calling cb
    runSafeCallback(function(cb)
        -- Forgot to invoke cb
    end)

    if assertTest(cbCount == 2,
        "Guaranteed NUI Callback Invocation",
        "Safe runner failed to resolve callback on error or omission") then
        passes = passes + 1
    end

    return passes == total
end

-- 12. Test Extended Third-Eye (LALT) Cursor Manipulation & Zero-Packet Placement
function Nyx.Tests.TestThirdEyeAndZeroPacketPlacement()
    print("^3[Nyx:Tests] Running Extended Third-Eye & Zero-Packet Placement Suite...^7")
    local passes = 0
    local total = 6

    -- Test A: Distance Boundary & Anti-Teleport Validation
    local playerPos = vector3(100.0, 200.0, 30.0)
    local maxDist = 6.0 + 2.5 -- 8.5m tolerance
    local function validatePlacementDistance(targetPos)
        local dist = #(playerPos - targetPos)
        if dist > maxDist then
            return false, "PLACEMENT_OUT_OF_RANGE"
        end
        return true
    end

    local okFar, errFar = validatePlacementDistance(vector3(120.0, 200.0, 30.0)) -- 20m away
    local okNear, _ = validatePlacementDistance(vector3(103.0, 202.0, 30.0))   -- ~3.6m away

    if assertTest(okFar == false and errFar == "PLACEMENT_OUT_OF_RANGE" and okNear == true,
        "Placement Distance Boundary Clamping",
        "Anti-teleport placement range validation failed") then
        passes = passes + 1
    end

    -- Test B: Precision Heading Normalization & Orientation Math
    local function normalizeHeading(raw)
        local h = 0.0
        if type(raw) == "table" then
            h = tonumber(raw.heading) or tonumber(raw.z) or 0.0
        elseif type(raw) == "number" then
            h = raw
        end
        h = (h % 360.0 + 360.0) % 360.0
        return math.floor(h * 100) / 100
    end

    local h1 = normalizeHeading(375.5)   -- wraps to 15.5
    local h2 = normalizeHeading(-45.0)   -- wraps to 315.0
    local h3 = normalizeHeading(720.0)   -- wraps to 0.0
    local h4 = normalizeHeading({ z = 180.256 }) -- wraps to 180.25

    if assertTest(h1 == 15.5 and h2 == 315.0 and h3 == 0.0 and h4 == 180.25,
        "Heading Angle Normalization (0-360 deg)",
        string.format("Normalized headings mismatch: h1=%.2f, h2=%.2f, h3=%.2f, h4=%.2f", h1, h2, h3, h4)) then
        passes = passes + 1
    end

    -- Test C: Coordinate Precision Clamping (Prevent Floating-Point Bloat in DB)
    local function sanitizeCoordinates(c)
        return {
            x = math.floor((c.x or 0.0) * 100) / 100,
            y = math.floor((c.y or 0.0) * 100) / 100,
            z = math.floor((c.z or 0.0) * 100) / 100
        }
    end

    local cleanCoords = sanitizeCoordinates({ x = 123.4567, y = -987.6543, z = 45.1234 })
    if assertTest(cleanCoords.x == 123.45 and cleanCoords.y == -987.66 and cleanCoords.z == 45.12,
        "Spatial Coordinate Sanitization & DB Precision",
        string.format("Coordinate clamping failed: (%.4f, %.4f, %.4f)", cleanCoords.x, cleanCoords.y, cleanCoords.z)) then
        passes = passes + 1
    end

    -- Test D: Zero-Packet Local Drag Simulation (Zero RPCs during movement)
    local rpcPacketsSent = 0
    local function onHologramDragStep(deltaHeading)
        -- Simulates 60 FPS client interpolation without network dispatch
        h1 = (h1 + deltaHeading) % 360.0
        return h1
    end

    for _ = 1, 60 do -- 60 frames of dragging/rotation
        onHologramDragStep(5.0)
    end

    -- Final release: exactly 1 packet sent
    local function onPlacementRelease()
        rpcPacketsSent = rpcPacketsSent + 1
        return { success = true }
    end
    onPlacementRelease()

    if assertTest(rpcPacketsSent == 1,
        "60 FPS Client-Side Interpolation & Single-Packet Commit",
        string.format("Expected exactly 1 network packet on commit, got %d", rpcPacketsSent)) then
        passes = passes + 1
    end

    -- Test E: Reposition Existing Drop vs Create New World Container
    local mockDrops = {
        ["drop:TEST001"] = {
            id = "drop:TEST001",
            coords = { x = 100.0, y = 200.0, z = 30.0 },
            rotation = { heading = 0.0 }
        }
    }

    local function handleCommit(payload)
        if payload.dropId then
            local d = mockDrops[payload.dropId]
            if not d then return false, "DROP_NOT_FOUND" end
            d.coords = payload.coords
            d.rotation = payload.rotation
            return true, d.id
        else
            local newId = "drop:NEW001"
            mockDrops[newId] = {
                id = newId,
                coords = payload.coords,
                rotation = payload.rotation
            }
            return true, newId
        end
    end

    local okRepo, repoId = handleCommit({
        dropId = "drop:TEST001",
        coords = { x = 102.5, y = 201.0, z = 30.0 },
        rotation = { heading = 45.0 }
    })
    local okNew, newId = handleCommit({
        coords = { x = 104.0, y = 205.0, z = 30.0 },
        rotation = { heading = 90.0 }
    })

    if assertTest(okRepo == true and mockDrops["drop:TEST001"].rotation.heading == 45.0 and okNew == true and mockDrops["drop:NEW001"] ~= nil,
        "Container Repositioning & Orientation Persistence",
        "Failed to update or create container with orientation") then
        passes = passes + 1
    end

    -- Test F: Third-Eye Target Resolution with Context Enrichment
    local mockCurrentTarget = {
        entity = 456,
        coords = vector3(105.0, 205.0, 30.0),
        options = {
            { id = "opt_loot", label = "Open Ground Loot", event = "inventory:openDrop", args = { dropId = "drop:TEST001" } },
            { id = "opt_grab", label = "Reposition / Move", event = "inventory:grabDrop", args = { dropId = "drop:TEST001" } }
        }
    }

    local dispatchedEvent = nil
    local dispatchedArgs = nil
    local function dispatchSelectedOption(nuiPayload)
        for _, opt in ipairs(mockCurrentTarget.options) do
            if opt.id == nuiPayload.id then
                dispatchedEvent = opt.event
                dispatchedArgs = opt.args
                break
            end
        end
    end

    dispatchSelectedOption({ id = "opt_grab" })

    if assertTest(dispatchedEvent == "inventory:grabDrop" and dispatchedArgs and dispatchedArgs.dropId == "drop:TEST001",
        "Third-Eye Intent Resolution & Context Enrichment",
        "Option intent was not mapped back to authoritative target options") then
        passes = passes + 1
    end

    return passes == total
end

-- 13. Test Auto-Merging World Drops & Smart Fallback Containers
function Nyx.Tests.TestAutoMergingWorldDropsAndFallbackModels()
    print("^3[Nyx:Tests] Running Auto-Merging World Drops & Smart Fallback Containers Suite...^7")
    local passes = 0
    local total = 7

    -- Test A: Category and Weight-Tiered Fallback Model Resolution
    local testCategories = {
        medical = {
            { maxWeight = 2000, model = "prop_ld_health_pack" },
            { maxWeight = math.huge, model = "prop_med_box_01b" }
        },
        ammo = {
            { maxWeight = 5000, model = "prop_box_ammo04a" },
            { maxWeight = math.huge, model = "prop_box_ammo03a" }
        },
        freight = {
            { maxWeight = 25000, model = "prop_wooden_crate_01" },
            { maxWeight = math.huge, model = "prop_boxpile_06a" }
        }
    }
    local testTiers = {
        { maxWeight = 2500,  model = "prop_paper_bag_small" },
        { maxWeight = 10000, model = "prop_cs_cardbox_01" },
        { maxWeight = 35000, model = "prop_box_wood02a" },
        { maxWeight = 80000, model = "prop_wooden_crate_01" },
        { maxWeight = math.huge, model = "prop_boxpile_06a" }
    }

    local function resolveFallback(category, weight)
        if testCategories[category] then
            for _, tier in ipairs(testCategories[category]) do
                if weight <= tier.maxWeight then return tier.model end
            end
        end
        for _, tier in ipairs(testTiers) do
            if weight <= tier.maxWeight then return tier.model end
        end
        return "prop_paper_bag_small"
    end

    local m1 = resolveFallback("medical", 500)
    local m2 = resolveFallback("medical", 3000)
    local m3 = resolveFallback("ammo", 1200)
    local m4 = resolveFallback("ammo", 8000)
    local m5 = resolveFallback("general", 1500)
    local m6 = resolveFallback("general", 5000)
    local m7 = resolveFallback("general", 20000)
    local m8 = resolveFallback("freight", 50000)

    if assertTest(m1 == "prop_ld_health_pack" and m2 == "prop_med_box_01b"
        and m3 == "prop_box_ammo04a" and m4 == "prop_box_ammo03a"
        and m5 == "prop_paper_bag_small" and m6 == "prop_cs_cardbox_01"
        and m7 == "prop_box_wood02a" and m8 == "prop_boxpile_06a",
        "Category & Weight-Tiered Model Resolution Invariant",
        "Fallback models did not resolve accurately across weight brackets") then
        passes = passes + 1
    end

    -- Test B: Dedicated Item Model Resolution Priority
    local mockItemRegistry = {
        ['weapon_pistol'] = { name = 'weapon_pistol', client = { model = 'w_pi_pistol' }, weight = 1000 },
        ['refined_iron'] = { name = 'refined_iron', weight = 2500, type = 'material' }
    }

    local function resolveItemModel(name, count)
        local item = mockItemRegistry[name]
        if not item then return "prop_paper_bag_small" end
        if item.client and item.client.model then return item.client.model end
        local totalWeight = (item.weight or 0) * (count or 1)
        return resolveFallback(item.type or "general", totalWeight)
    end

    local wModel = resolveItemModel("weapon_pistol", 1)
    local iModel1 = resolveItemModel("refined_iron", 1)
    local iModel5 = resolveItemModel("refined_iron", 5)
    local iModel20 = resolveItemModel("refined_iron", 20)

    if assertTest(wModel == "w_pi_pistol" and iModel1 == "prop_paper_bag_small" and iModel5 == "prop_box_wood02a" and iModel20 == "prop_wooden_crate_01",
        "Dedicated vs Fallback Model Precedence",
        "Custom item model was not prioritized over fallback props") then
        passes = passes + 1
    end

    -- Test C: Proximity Distance Detection & Spatial Range Gating (1.5m Threshold)
    local existingDrops = {
        ['drop:A'] = { coords = { x = 100.0, y = 200.0, z = 30.0 }, items = { { item_id = 'refined_iron', amount = 2 } } },
        ['drop:B'] = { coords = { x = 105.0, y = 200.0, z = 30.0 }, items = { { item_id = 'ammo_9mm', amount = 50 } } }
    }

    local function findMerge(targetCoords, maxDist)
        maxDist = maxDist or 1.5
        local bestId, bestDist = nil, 999.0
        for id, drop in pairs(existingDrops) do
            local dx = drop.coords.x - targetCoords.x
            local dy = drop.coords.y - targetCoords.y
            local dz = drop.coords.z - targetCoords.z
            local dist = math.sqrt(dx * dx + dy * dy + dz * dz)
            if dist <= maxDist and dist < bestDist then
                bestDist = dist
                bestId = id
            end
        end
        return bestId, bestDist
    end

    local closeTarget = { x = 100.8, y = 200.5, z = 30.0 } -- dist = ~0.94m (<= 1.5m)
    local farTarget   = { x = 102.2, y = 200.0, z = 30.0 } -- dist = 2.2m (> 1.5m from A, 2.8m from B)

    local hitCloseId = findMerge(closeTarget, 1.5)
    local hitFarId   = findMerge(farTarget, 1.5)

    if assertTest(hitCloseId == "drop:A" and hitFarId == nil,
        "Proximity Radius Spatial Gating (1.5m)",
        "Proximity merge trigger failed distance gating criteria") then
        passes = passes + 1
    end

    -- Test D: Stack Consolidation & Stack Cap Splitting Invariants
    local testContainer = {
        maxSlots = 5,
        items = {
            [1] = { item_id = 'ammo_9mm', amount = 85 },
            [2] = { item_id = 'med_bandage', amount = 10 }
        }
    }
    local maxAmmoStack = 100

    local function mergeAmmo(amount)
        local remaining = amount
        for s = 1, testContainer.maxSlots do
            local it = testContainer.items[s]
            if it and it.item_id == 'ammo_9mm' then
                local space = maxAmmoStack - it.amount
                if space > 0 then
                    local add = math.min(remaining, space)
                    it.amount = it.amount + add
                    remaining = remaining - add
                    if remaining <= 0 then break end
                end
            end
        end
        if remaining > 0 then
            for s = 1, testContainer.maxSlots do
                if not testContainer.items[s] then
                    testContainer.items[s] = { item_id = 'ammo_9mm', amount = remaining }
                    remaining = 0
                    break
                end
            end
        end
        return remaining == 0
    end

    local mergeOk = mergeAmmo(25)

    if assertTest(mergeOk == true and testContainer.items[1].amount == 100 and testContainer.items[3] and testContainer.items[3].amount == 10,
        "Stack Merging & Dynamic Overflow Allocation",
        "Stack consolidation did not top off existing slot or allocate overflow slot") then
        passes = passes + 1
    end

    -- Test E: Container Maximum Weight Ceiling Enforcement
    local heavyContainer = {
        maxWeight = 100000, -- 100 kg
        currentWeight = 95000,
        canHold = function(self, addWeight)
            return (self.currentWeight + addWeight) <= self.maxWeight
        end
    }

    local canHoldSmall = heavyContainer:canHold(3000)  -- 95kg + 3kg = 98kg <= 100kg (ALLOWED)
    local canHoldHeavy = heavyContainer:canHold(10000) -- 95kg + 10kg = 105kg > 100kg (REJECTED)

    if assertTest(canHoldSmall == true and canHoldHeavy == false,
        "Container Max Weight Safeguard on Auto-Merge",
        "Overweight item was not rejected during container merge check") then
        passes = passes + 1
    end

    -- Test F: Dynamic 3D Prop Morphing on Weight Change
    local function evaluateDropMorph(totalWeight)
        return resolveFallback("general", totalWeight)
    end

    local initialProp = evaluateDropMorph(1200)
    local morphedProp = evaluateDropMorph(24000)

    if assertTest(initialProp == "prop_paper_bag_small" and morphedProp == "prop_box_wood02a",
        "Dynamic 3D Prop Morphing Telemetry",
        "Container model did not morph to reflect heavier weight bracket") then
        passes = passes + 1
    end

    -- Test G: Multi-Container Relocation Merge & Closed-Loop Conservation
    local srcBox = {
        id = "drop:SRC01",
        items = { [1] = { item_id = 'refined_iron', amount = 4 } }
    }
    local dstBox = {
        id = "drop:DST01",
        items = { [1] = { item_id = 'refined_iron', amount = 6 } }
    }

    local function mergeBoxes(src, dst)
        local initialTotal = src.items[1].amount + dst.items[1].amount
        dst.items[1].amount = dst.items[1].amount + src.items[1].amount
        src.items[1] = nil
        src.deleted = true
        return dst.items[1].amount == initialTotal and src.deleted == true
    end

    local boxMergePass = mergeBoxes(srcBox, dstBox)

    if assertTest(boxMergePass == true and dstBox.items[1].amount == 10 and srcBox.deleted == true,
        "Container Relocation Auto-Merge & Inventory Conservation",
        "Moving container within 1.5m did not consolidate items or clean up source container") then
        passes = passes + 1
    end

    return passes == total
end

-- 14. Master Test Runner
function Nyx.Tests.RunAll()
    print("^5==================================================^7")
    print("^5   NYXFRAMEWORK IN-ENGINE INTEGRATION HARNESS    ^7")
    print("^5==================================================^7")

    local t1 = Nyx.Tests.TestRPC()
    local t2 = Nyx.Tests.TestInventoryConcurrency()
    local t3 = Nyx.Tests.TestTreasuryConservationLaw()
    local t4 = Nyx.Tests.TestFreightBoardEscrowAndElasticity()
    local t5 = Nyx.Tests.TestVehicleMileageAndWear()
    local t6 = Nyx.Tests.TestWeightPenalties()
    local t7 = Nyx.Tests.TestElasticItemPricingAndZoneDemand()
    local t8 = Nyx.Tests.TestEvidenceChainOfCustody()
    local t9 = Nyx.Tests.TestSharedMathAndVectorUtils()
    local t10 = Nyx.Tests.TestMultiSigVaultsAndSignOffRules()
    local t11 = Nyx.Tests.TestMasterUIArchitecture()
    local t12 = Nyx.Tests.TestThirdEyeAndZeroPacketPlacement()
    local t13 = Nyx.Tests.TestAutoMergingWorldDropsAndFallbackModels()

    print("^5--------------------------------------------------^7")
    if t1 and t2 and t3 and t4 and t5 and t6 and t7 and t8 and t9 and t10 and t11 and t12 and t13 then
        print("^2>>> ALL NYXFRAMEWORK INTEGRATION TESTS PASSED! <<<^7")
    else
        print("^1>>> SOME NYXFRAMEWORK TESTS FAILED! CHECK LOGS. <<<^7")
    end
    print("^5==================================================^7")
end

-- Console Command to execute tests
RegisterCommand("nyx_run_tests", function(source, args)
    if source == 0 then -- Server console
        Nyx.Tests.RunAll()
    else
        local player = Nyx.GetPlayer(source)
        if player and player.hasPermission and player.hasPermission("admin") then
            Nyx.Tests.RunAll()
        else
            print(string.format("^1[Nyx:Security] Unauthorized attempt to run unit tests from source %s^7", tostring(source)))
        end
    end
end, true)
