--[[
    Nyxframework: nyx_treasury
    File: server/payroll.lua
    Description: Autonomous public service payroll distributor with logarithmic
                 fiscal crisis throttling, department subventions, and run ledger persistence.
]]

Nyx = Nyx or {}
Nyx.Treasury = Nyx.Treasury or {}

-- Calculate active logarithmic wage multiplier based on municipal master liquidity
function Nyx.Treasury.GetWageMultiplier()
    local masterReserve = Nyx.Treasury.GetBalance(Config.Accounts.Master or "gov:city:master")
    local targetReserve = tonumber(Config.TargetReserve) or 5000000.00
    local critReserve = tonumber(Config.CriticalReserve) or 500000.00
    local cautionReserve = tonumber(Config.CautionReserve) or (targetReserve * 0.50)

    -- If circuit breaker is tripped, wage multiplier is throttled or frozen
    if Nyx.Treasury.IsCircuitTripped and Nyx.Treasury.IsCircuitTripped() then
        local floor = (Config.Circuit and Config.Circuit.AusterityWageFloor) or 0.10
        if masterReserve <= critReserve then
            return 0.00, "CIRCUIT_TRIPPED_FROZEN", masterReserve
        end
        return floor, "CIRCUIT_TRIPPED_AUSTERITY", masterReserve
    end

    local opts = {
        austerityFloor = Config.Circuit and Config.Circuit.AusterityWageFloor or 0.10,
        criticalMultiplier = Config.Circuit and Config.Circuit.CriticalWageMultiplier or 0.00
    }

    return Nyx.Circuit.CalculateWageMultiplier(masterReserve, targetReserve, critReserve, cautionReserve, opts)
end

-- Execute public service payroll cycle across all on-duty municipal workers
function Nyx.Treasury.ProcessPublicPayroll()
    local multiplier, status, masterReserveBefore = Nyx.Treasury.GetWageMultiplier()
    local masterAcc = Config.Accounts.Master or "gov:city:master"
    local critReserve = tonumber(Config.CriticalReserve) or 500000.00

    print(string.format("^4[Nyx:Treasury]^7 Running public payroll cycle. Status: ^3%s^7 | Reserve: ^2$%.2f^7 | Wage Scale: ^3%.0f%%^7",
        status, masterReserveBefore, multiplier * 100))

    local players = exports['nyx_core']:GetPlayers()
    local totalDisbursed = 0.00
    local totalSubventions = 0.00
    local recipientCount = 0

    -- 1. Aggregate municipal workers by department
    local departmentWorkers = {
        police = {},
        ems = {},
        works = {}
    }

    for src, player in pairs(players) do
        if player and player.citizenId then
            local job = player:getMetadata("job")
            local jobName = (type(job) == "table" and job.name) or (type(job) == "string" and job) or nil
            local jobGrade = (type(job) == "table" and tonumber(job.grade)) or 0

            local deptKey = nil
            local deptAccount = nil

            if jobName == "police" or player:hasPermission("police") then
                deptKey = "police"
                deptAccount = Config.Accounts.Police or "gov:dept:police"
            elseif jobName == "ems" or player:hasPermission("ems") then
                deptKey = "ems"
                deptAccount = Config.Accounts.EMS or "gov:dept:ems"
            elseif jobName == "works" or player:hasPermission("works") then
                deptKey = "works"
                deptAccount = Config.Accounts.Works or "gov:dept:works"
            end

            if deptKey and deptAccount then
                local gradeWages = Config.DefaultWages[deptKey] or {}
                local baseWage = gradeWages[jobGrade] or gradeWages[0] or 600.00
                local payable = math.floor(baseWage * multiplier * 100) / 100

                departmentWorkers[deptKey][#departmentWorkers[deptKey] + 1] = {
                    player = player,
                    payable = payable,
                    deptAccount = deptAccount,
                    jobName = deptKey,
                    grade = jobGrade
                }
            end
        end
    end

    -- 2. Process each department with liquidity check & automated emergency subvention
    for deptKey, workers in pairs(departmentWorkers) do
        if #workers > 0 then
            local deptAccount = workers[1].deptAccount
            local requiredDeptPayroll = 0.00

            for _, w in ipairs(workers) do
                requiredDeptPayroll = requiredDeptPayroll + w.payable
            end

            local deptBalance = Nyx.Treasury.GetBalance(deptAccount)

            -- If department lacks liquidity and wages are payable, check for emergency subvention
            if requiredDeptPayroll > 0 and deptBalance < requiredDeptPayroll then
                local currentMaster = Nyx.Treasury.GetBalance(masterAcc)
                local grant, subStatus, deficit = Nyx.Circuit.CalculateSubvention(deptBalance, requiredDeptPayroll, currentMaster, critReserve)

                if grant > 0 then
                    local okSub, txSubUuid = Nyx.Treasury.ExecuteTransfer(
                        masterAcc,
                        deptAccount,
                        grant,
                        "emergency_subvention",
                        "PAYROLL_SUBVENTION_DAEMON",
                        string.format("Automated payroll liquidity subvention to %s (deficit: $%.2f)", deptKey, deficit)
                    )

                    if okSub then
                        totalSubventions = totalSubventions + grant
                        print(string.format("^3[Nyx:Treasury] Subvention granted: $%.2f from Master to %s (%s)^7",
                            grant, deptAccount, subStatus))
                    end
                end
            end

            -- Disburse paychecks to department personnel
            for _, w in ipairs(workers) do
                local player = w.player
                local payable = w.payable
                local workerAccount = string.format("char:%s:bank", player.citizenId)

                if payable > 0 then
                    local ok, txUuid = Nyx.Treasury.ExecuteTransfer(
                        deptAccount,
                        workerAccount,
                        payable,
                        "payroll",
                        "SYSTEM_PAYROLL",
                        string.format("Duty paycheck for %s (scale: %.0f%%)", player.citizenId, multiplier * 100)
                    )

                    if ok then
                        player:addMoney("bank", payable, "Municipal Duty Paycheck")
                        totalDisbursed = totalDisbursed + payable
                        recipientCount = recipientCount + 1

                        TriggerClientEvent("nyx:core:client:notify", player.source,
                            string.format("Civil Paycheck: +$%.2f (Wage Scale: %d%%)", payable, math.floor(multiplier * 100)),
                            "success"
                        )
                    else
                        TriggerClientEvent("nyx:core:client:notify", player.source,
                            "Department payroll halted: Insufficient department operating balance.",
                            "error"
                        )
                    end
                else
                    TriggerClientEvent("nyx:core:client:notify", player.source,
                        "Municipal fiscal crisis: Public paychecks suspended due to critical reserve depletion.",
                        "error"
                    )
                end
            end
        end
    end

    local masterReserveAfter = Nyx.Treasury.GetBalance(masterAcc)
    local runUuid = Nyx.RPC.GenerateNonce()

    -- 3. Persist payroll run record to audit ledger
    pcall(function()
        MySQL.prepare.await([[
            INSERT INTO `nyx_treasury_payroll_runs`
            (`run_uuid`, `fiscal_state`, `wage_multiplier`, `total_disbursed`, `recipient_count`, `master_reserve_before`, `master_reserve_after`, `subventions_total`)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        ]], {
            runUuid,
            status,
            multiplier,
            totalDisbursed,
            recipientCount,
            masterReserveBefore,
            masterReserveAfter,
            totalSubventions
        })
    end)

    print(string.format("^2[Nyx:Treasury] Payroll completed. Disbursed $%.2f across %d public personnel (Subventions: $%.2f).^7",
        totalDisbursed, recipientCount, totalSubventions))

    TriggerEvent("nyx:treasury:payrollCompleted", runUuid, totalDisbursed, recipientCount, multiplier, totalSubventions)

    return {
        success = true,
        runUuid = runUuid,
        fiscalState = status,
        wageMultiplier = multiplier,
        totalDisbursed = totalDisbursed,
        recipientCount = recipientCount,
        subventionsTotal = totalSubventions,
        masterReserveBefore = masterReserveBefore,
        masterReserveAfter = masterReserveAfter
    }
end

-- Background Periodic Payroll Dispatcher Thread
CreateThread(function()
    local intervalMs = (Config.PayrollInterval or 900) * 1000
    while true do
        Wait(intervalMs)
        Nyx.Treasury.ProcessPublicPayroll()
    end
end)
