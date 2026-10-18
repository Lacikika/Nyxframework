--[[
    Nyxframework: nyx_treasury
    File: server/degradation.lua
    Description: Authoritative municipal fiscal state monitoring, infrastructure degradation mode engine,
                 and public service status broadcasts.
]]

Nyx = Nyx or {}
Nyx.Treasury = Nyx.Treasury or {}

Nyx.Treasury.CurrentFiscalTier = "solvent"
Nyx.Treasury.FiscalStateCache = {
    tier = "solvent",
    liquidBalance = 0.00,
    details = Nyx.Degradation.GetTierDetails("solvent"),
    evaluatedAt = 0
}

--- Authoritatively evaluates and synchronizes municipal fiscal solvency state.
--- @return table state
function Nyx.Treasury.EvaluateMunicipalFiscalState()
    local masterAcc = Config.Accounts and Config.Accounts.Master or "gov:city:master"
    local balance = Nyx.Treasury.GetBalance(masterAcc) or 0.00

    local newTier, details = Nyx.Degradation.EvaluateFiscalTier(balance)
    local prevTier = Nyx.Treasury.CurrentFiscalTier

    Nyx.Treasury.CurrentFiscalTier = newTier
    Nyx.Treasury.FiscalStateCache = {
        tier = newTier,
        liquidBalance = balance,
        details = details,
        evaluatedAt = os.time()
    }

    -- Synchronize via OneSync GlobalState
    if GlobalState then
        GlobalState.municipalFiscalTier = newTier
        GlobalState.municipalFiscalState = Nyx.Treasury.FiscalStateCache
    end

    -- If tier changed, log and broadcast
    if prevTier ~= newTier then
        print(string.format("^3[Nyx:Treasury] MUNICIPAL FISCAL STATE TRANSITION: '%s' -> '%s' (Balance: $%.2f)^7",
            prevTier, newTier, balance))

        pcall(function()
            MySQL.prepare.await([[
                INSERT INTO `nyx_treasury_fiscal_states`
                    (`master_account_id`, `liquid_balance`, `fiscal_tier`, `auto_repair_status`, `impound_lot_status`, `ai_dispatch_latency_sec`, `notes`)
                VALUES (?, ?, ?, ?, ?, ?, ?)
            ]], {
                masterAcc,
                balance,
                newTier,
                details.autoRepairStatus,
                details.impoundLotStatus,
                details.dispatchLatencySec,
                string.format("Automated evaluation transition from %s to %s", prevTier, newTier)
            })
        end)

        TriggerEvent("nyx:treasury:server:fiscalTierChanged", newTier, prevTier, details)
        TriggerClientEvent("nyx:treasury:client:fiscalStateChanged", -1, Nyx.Treasury.FiscalStateCache)
    end

    return Nyx.Treasury.FiscalStateCache
end

--- Returns the current municipal fiscal tier.
--- @return string tier
function Nyx.Treasury.GetMunicipalFiscalTier()
    return Nyx.Treasury.CurrentFiscalTier or "solvent"
end

--- Returns full cached fiscal state telemetry.
--- @return table
function Nyx.Treasury.GetMunicipalFiscalState()
    if Nyx.Treasury.FiscalStateCache.evaluatedAt == 0 then
        return Nyx.Treasury.EvaluateMunicipalFiscalState()
    end
    return Nyx.Treasury.FiscalStateCache
end

--- Helper export to check if infrastructure is in degraded or bankrupt state.
--- @return boolean
function Nyx.Treasury.IsInfrastructureDegraded()
    local tier = Nyx.Treasury.GetMunicipalFiscalTier()
    return (tier == "degraded" or tier == "bankrupt")
end

--- Helper export to check if municipal treasury is completely bankrupt.
--- @return boolean
function Nyx.Treasury.IsMunicipalBankrupt()
    return Nyx.Treasury.GetMunicipalFiscalTier() == "bankrupt"
end

-- Initialize and evaluate on boot
MySQL.ready(function()
    SetTimeout(1500, function()
        Nyx.Treasury.EvaluateMunicipalFiscalState()
    end)
end)

-- 60-Second Background Solvency Watchdog
CreateThread(function()
    while true do
        Wait(60000)
        Nyx.Treasury.EvaluateMunicipalFiscalState()
    end
end)

-- RPC Endpoints
if Nyx.RPC and Nyx.RPC.Register then
    Nyx.RPC.Register("treasury:getMunicipalFiscalState", function(src, payload)
        return Nyx.Treasury.GetMunicipalFiscalState()
    end)
end
