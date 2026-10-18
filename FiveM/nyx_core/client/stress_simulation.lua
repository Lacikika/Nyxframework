--[[
    Nyxframework: nyx_core
    File: client/stress_simulation.lua
    Description: Client-side command and RPC invoker for 14-resource stress testing.
]]

Nyx = Nyx or {}
Nyx.Client = Nyx.Client or {}

-- Client command for administrators to trigger stress tests
RegisterCommand("nyx_stress", function(_, args)
    local concurrency = tonumber(args[1]) or 50
    local txPerActor = tonumber(args[2]) or 10

    print(string.format("^3[Nyx:Stress] Requesting server-side stress simulation (concurrency=%d, txPerActor=%d)...^7", concurrency, txPerActor))

    Nyx.RPC.Trigger("core:runStressSimulation", {
        concurrency = concurrency,
        transactionsPerActor = txPerActor
    }, function(response)
        if not response or not response.success then
            local err = response and response.error or "UNKNOWN_ERROR"
            print(string.format("^1[Nyx:Stress:ERROR] Stress simulation failed: %s^7", tostring(err)))
            TriggerEvent("chat:addMessage", {
                color = { 255, 50, 50 },
                multiline = true,
                args = { "Nyx:Stress", string.format("Stress simulation failed: %s", tostring(err)) }
            })
            return
        end

        local r = response.results
        local msg = string.format("Stress Run [%s]: %s | %d tx | %s idle | Econ Delta: $%.2f",
            r.uuid,
            r.isPassed and "PASSED" or "FAILED",
            r.totalTransactions,
            r.idlePerformance and r.idlePerformance.displayFormatted or "0.00ms",
            r.economicConservation and r.economicConservation.delta or 0.0
        )

        print(string.format("^2[Nyx:Stress:SUCCESS]^7 %s", msg))
        TriggerEvent("chat:addMessage", {
            color = { 0, 220, 100 },
            multiline = true,
            args = { "Nyx:Stress", msg }
        })
    end)
end, false)
