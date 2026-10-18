--[[
    Nyxframework: nyx_treasury
    File: server/payroll.lua
    Description: Autonomous public service payroll distributor with logarithmic
                 fiscal crisis throttling and reserve preservation.
]]

Nyx = Nyx or {}
Nyx.Treasury = Nyx.Treasury or {}

-- Calculate active logarithmic wage multiplier based on municipal master liquidity
function Nyx.Treasury.GetWageMultiplier()
    local masterReserve = Nyx.Treasury.GetBalance(Config.Accounts.Master or "gov:city:master")
    local targetReserve = tonumber(Config.TargetReserve) or 5000000.00
    local critReserve = tonumber(Config.CriticalReserve) or 500000.00

    if masterReserve >= targetReserve then
        return 1.0, "SOLVENT", masterReserve
    end

    if masterReserve < critReserve then
        return 0.0, "CRITICAL_FREEZE", masterReserve
    end

    -- Logarithmic throttle curve
    local numerator = math.log(masterReserve + 1.0)
    local denominator = math.log(targetReserve + 1.0)
    local scaled = math.max(0.10, numerator / denominator)
    local multiplier = math.floor(scaled * 100) / 100

    return multiplier, "THROTTLED", masterReserve
end

-- Execute public service payroll cycle across all on-duty municipal workers
function Nyx.Treasury.ProcessPublicPayroll()
    local multiplier, status, currentReserve = Nyx.Treasury.GetWageMultiplier()

    print(string.format("^4[Nyx:Treasury]^7 Running public payroll cycle. Status: ^3%s^7 | Reserve: ^2$%.2f^7 | Wage Scale: ^3%.0f%%^7",
        status, currentReserve, multiplier * 100))

    local players = exports['nyx_core']:GetPlayers()
    local totalDisbursed = 0.00
    local recipientCount = 0

    for src, player in pairs(players) do
        if player and player.citizenId then
            local job = player:getMetadata("job")
            local jobName = (type(job) == "table" and job.name) or (type(job) == "string" and job) or nil
            local jobGrade = (type(job) == "table" and tonumber(job.grade)) or 0

            -- Check if player is a public civil employee (Police, EMS, Public Works)
            local deptAccount = nil
            if jobName == "police" or player:hasPermission("police") then
                deptAccount = Config.Accounts.Police or "gov:dept:police"
                jobName = "police"
            elseif jobName == "ems" or player:hasPermission("ems") then
                deptAccount = Config.Accounts.EMS or "gov:dept:ems"
                jobName = "ems"
            elseif jobName == "works" or player:hasPermission("works") then
                deptAccount = Config.Accounts.Works or "gov:dept:works"
                jobName = "works"
            end

            if deptAccount then
                local gradeWages = Config.DefaultWages[jobName] or {}
                local baseWage = gradeWages[jobGrade] or gradeWages[0] or 600.00
                local payable = math.floor(baseWage * multiplier * 100) / 100
                local workerAccount = string.format("char:%s:bank", player.citizenId)

                if payable > 0 then
                    local ok, txUuid = Nyx.Treasury.ExecuteTransfer(
                        deptAccount,
                        workerAccount,
                        payable,
                        "payroll",
                        "SYSTEM",
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

    print(string.format("^2[Nyx:Treasury] Payroll completed. Disbursed $%.2f across %d public personnel.^7", totalDisbursed, recipientCount))
end

-- Background Periodic Payroll Dispatcher Thread
CreateThread(function()
    local intervalMs = (Config.PayrollInterval or 900) * 1000
    while true do
        Wait(intervalMs)
        Nyx.Treasury.ProcessPublicPayroll()
    end
end)
