--[[
    Nyxframework: nyx_properties
    File: server/billing.lua
    Description: Automated municipal property millage tax assessment,
                 dynamic land maintenance evaluation, condition degradation,
                 double-entry treasury collection & delinquency monitoring.
]]

Nyx = Nyx or {}
Nyx.Properties = Nyx.Properties or {}

-- 1. Periodic Millage & Land Maintenance Tax Assessment Cycle
function Nyx.Properties.ProcessMillageBillingCycle()
    local intervalHours = Config.Millage.BillingIntervalHours or 24

    -- 1.1 Process structural condition decay on all properties
    local nowTime = os.time()
    for _, prop in pairs(Nyx.Properties.Loaded or {}) do
        if prop.ownerCitizenId and not prop.reclaimedForAuction then
            local lastMaint = prop.lastMaintenanceAt or nowTime
            local decay = Nyx.Taxation.CalculateConditionDecay(lastMaint, nowTime)
            if decay > 0.0 then
                local floorCond = (Config.Taxation and Config.Taxation.MinConditionFloor) or 10.0
                local currentCond = prop.maintenanceCondition or 100.0
                local newCond = math.max(floorCond, currentCond - decay)

                if newCond ~= currentCond then
                    prop.maintenanceCondition = newCond
                    MySQL.prepare("UPDATE `nyx_properties` SET `maintenance_condition` = ? WHERE `property_id` = ?", {
                        newCond, prop.id
                    })
                end
            end
        end
    end

    -- 1.2 Query properties due for tax assessment
    local propsToBill = MySQL.query.await([[
        SELECT `property_id`
        FROM `nyx_properties`
        WHERE `owner_citizen_id` IS NOT NULL
          AND `reclaimed_for_auction` = 0
          AND (`last_tax_billed_at` IS NULL OR `last_tax_billed_at` <= NOW() - INTERVAL ? HOUR)
    ]], { intervalHours })

    if not propsToBill or #propsToBill == 0 then return end

    local billedCount = 0
    local delinquentCount = 0

    for _, p in ipairs(propsToBill) do
        local ok, resOrErr, assessment = Nyx.Properties.ExecuteTaxCollection(p.property_id)
        if ok then
            billedCount = billedCount + 1
        else
            delinquentCount = delinquentCount + 1
            if Config.Debug then
                print(string.format("^1[Nyx:Properties:Billing] Delinquency Alert: Property #%d tax collection failed: %s^7",
                    p.property_id, tostring(resOrErr)))
            end
        end
    end

    if Config.Debug and (billedCount > 0 or delinquentCount > 0) then
        print(string.format("^3[Nyx:Properties:Billing] Tax assessment complete: %d settled, %d delinquent.^7",
            billedCount, delinquentCount))
    end
end

-- 2. Periodic Millage Heartbeat (Runs every 30 minutes)
CreateThread(function()
    while true do
        Wait(1800000) -- 30 minutes tick
        Nyx.Properties.ProcessMillageBillingCycle()
    end
end)

-- 3. Console Command for Administrative Tax Cycle Execution
RegisterCommand("nyx_properties_bill_cycle", function(source, args)
    if source == 0 then
        print("^3[Nyx:Properties] Admin triggering manual property millage billing cycle...^7")
        Nyx.Properties.ProcessMillageBillingCycle()
    else
        local player = exports['nyx_core']:GetPlayer(source)
        if player and player.hasPermission and player.hasPermission("admin") then
            print(string.format("^3[Nyx:Properties] Admin %s triggering manual property billing cycle...^7", player.citizenId))
            Nyx.Properties.ProcessMillageBillingCycle()
        end
    end
end, true)
