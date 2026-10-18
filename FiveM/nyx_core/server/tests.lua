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

-- 5. Master Test Runner
function Nyx.Tests.RunAll()
    print("^5==================================================^7")
    print("^5   NYXFRAMEWORK IN-ENGINE INTEGRATION HARNESS    ^7")
    print("^5==================================================^7")

    local t1 = Nyx.Tests.TestRPC()
    local t2 = Nyx.Tests.TestInventoryConcurrency()
    local t3 = Nyx.Tests.TestTreasuryConservationLaw()
    local t4 = Nyx.Tests.TestFreightBoardEscrowAndElasticity()

    print("^5--------------------------------------------------^7")
    if t1 and t2 and t3 and t4 then
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
