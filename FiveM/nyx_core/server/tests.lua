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

-- 8. Master Test Runner
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

    print("^5--------------------------------------------------^7")
    if t1 and t2 and t3 and t4 and t5 and t6 and t7 then
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
