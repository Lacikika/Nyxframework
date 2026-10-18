--[[
    Nyxframework: nyx_properties
    File: server/inactivity.lua
    Description: Authoritative Anti-Monopoly Inactivity Reclamation Sweeper & Stewardship Engine.
                 Monitors character last login timestamps, evaluates stewardship proxy protections,
                 issues 72-hour grace period notices, executes forfeiture to municipal blind auction,
                 and audits all actions into nyx_inactivity_reclamation_logs.
]]

Nyx = Nyx or {}
Nyx.Properties = Nyx.Properties or {}

-- 1. Register a Stewardship Delegate Authorization
function Nyx.Properties.RegisterStewardshipDelegate(ownerCitizenId, delegateCitizenId, scope, notes)
    local valid, err = Nyx.Inactivity.ValidateDelegation(ownerCitizenId, delegateCitizenId, scope)
    if not valid then return false, err end

    -- Verify that the target delegate citizen actually exists
    local delegateChar = MySQL.single.await([[
        SELECT `citizen_id`, `first_name`, `last_name`, UNIX_TIMESTAMP(`last_active_at`) AS `last_active_unix`
        FROM `nyx_characters`
        WHERE `citizen_id` = ? AND `deleted_at` IS NULL
    ]], { delegateCitizenId })

    if not delegateChar then
        return false, "DELEGATE_CITIZEN_NOT_FOUND"
    end

    -- Insert or update delegation record
    local success = MySQL.prepare.await([[
        INSERT INTO `nyx_stewardship_delegates`
            (`owner_citizen_id`, `delegate_citizen_id`, `scope`, `is_active`, `authorized_at`, `notes`)
        VALUES (?, ?, ?, 1, NOW(), ?)
        ON DUPLICATE KEY UPDATE
            `is_active` = 1,
            `revoked_at` = NULL,
            `authorized_at` = NOW(),
            `notes` = VALUES(`notes`)
    ]], { ownerCitizenId, delegateCitizenId, scope or "all", notes or "Stewardship proxy authorized" })

    return (success ~= nil), {
        ownerCitizenId = ownerCitizenId,
        delegateCitizenId = delegateCitizenId,
        scope = scope or "all",
        delegateName = string.format("%s %s", delegateChar.first_name or "", delegateChar.last_name or "")
    }
end

-- 2. Revoke a Stewardship Delegate Authorization
function Nyx.Properties.RevokeStewardshipDelegate(ownerCitizenId, delegateCitizenId, scope)
    if not ownerCitizenId or not delegateCitizenId then
        return false, "INVALID_CREDENTIALS"
    end

    scope = scope or "all"
    local affected = MySQL.update.await([[
        UPDATE `nyx_stewardship_delegates`
        SET `is_active` = 0,
            `revoked_at` = NOW()
        WHERE `owner_citizen_id` = ? AND `delegate_citizen_id` = ?
          AND (`scope` = ? OR `scope` = 'all')
    ]], { ownerCitizenId, delegateCitizenId, scope })

    -- Also clear delegate from properties owned by this citizen
    MySQL.update.await([[
        UPDATE `nyx_properties`
        SET `steward_delegate_citizen_id` = NULL,
            `inactivity_status` = 'active'
        WHERE `owner_citizen_id` = ? AND `steward_delegate_citizen_id` = ?
    ]], { ownerCitizenId, delegateCitizenId })

    return (affected and affected > 0), "DELEGATION_REVOKED"
end

-- 3. Assign a Specific Steward to a Specific Property
function Nyx.Properties.AssignPropertySteward(propertyId, ownerCitizenId, delegateCitizenId)
    propertyId = tonumber(propertyId)
    local prop = Nyx.Properties.Loaded and Nyx.Properties.Loaded[propertyId]
    if not prop then return false, "PROPERTY_NOT_FOUND" end

    if prop.ownerCitizenId ~= ownerCitizenId then
        return false, "UNAUTHORIZED_NOT_OWNER"
    end

    if delegateCitizenId then
        -- Verify delegation authorization exists and is active
        local auth = MySQL.single.await([[
            SELECT `delegate_id` FROM `nyx_stewardship_delegates`
            WHERE `owner_citizen_id` = ? AND `delegate_citizen_id` = ?
              AND `is_active` = 1 AND `scope` IN ('all', 'properties')
        ]], { ownerCitizenId, delegateCitizenId })

        if not auth then
            return false, "NO_ACTIVE_STEWARDSHIP_AUTHORIZATION"
        end
    end

    prop.stewardDelegateCitizenId = delegateCitizenId
    prop.inactivityStatus = delegateCitizenId and "delegated" or "active"

    MySQL.prepare.await([[
        UPDATE `nyx_properties`
        SET `steward_delegate_citizen_id` = ?,
            `inactivity_status` = ?
        WHERE `property_id` = ?
    ]], { delegateCitizenId, prop.inactivityStatus, propertyId })

    return true, {
        propertyId = propertyId,
        stewardCitizenId = delegateCitizenId,
        status = prop.inactivityStatus
    }
end

-- 4. Query Stewardship Overview for a Citizen
function Nyx.Properties.GetCitizenStewardshipOverview(citizenId)
    if not citizenId then return { delegates = {}, managedProperties = {}, ownedProperties = {} } end

    -- Active delegates appointed by this citizen
    local delegates = MySQL.query.await([[
        SELECT d.*, c.`first_name`, c.`last_name`, UNIX_TIMESTAMP(c.`last_active_at`) AS `delegate_last_active_unix`
        FROM `nyx_stewardship_delegates` d
        LEFT JOIN `nyx_characters` c ON c.`citizen_id` = d.`delegate_citizen_id`
        WHERE d.`owner_citizen_id` = ? AND d.`is_active` = 1
    ]], { citizenId }) or {}

    -- Properties where this citizen is the steward delegate
    local managedProperties = MySQL.query.await([[
        SELECT `property_id`, `property_code`, `label`, `type`, `price`, `owner_citizen_id`,
               `inactivity_status`, `inactivity_warning_at`
        FROM `nyx_properties`
        WHERE `steward_delegate_citizen_id` = ?
    ]], { citizenId }) or {}

    -- Properties owned by this citizen with stewardship info
    local ownedProperties = MySQL.query.await([[
        SELECT `property_id`, `property_code`, `label`, `type`, `price`, `steward_delegate_citizen_id`,
               `inactivity_status`, `inactivity_warning_at`, `delinquency_tier`
        FROM `nyx_properties`
        WHERE `owner_citizen_id` = ?
    ]], { citizenId }) or {}

    return {
        delegates = delegates,
        managedProperties = managedProperties,
        ownedProperties = ownedProperties
    }
end

-- 5. Authoritative Property Inactivity Sweeper
function Nyx.Properties.SweepPropertyInactivity()
    local now = os.time()
    local cfg = Config.Inactivity or Nyx.Inactivity.Defaults

    -- Fetch all owned properties that are not currently under auction
    local properties = MySQL.query.await([[
        SELECT p.`property_id`, p.`property_code`, p.`label`, p.`price`, p.`owner_citizen_id`,
               p.`steward_delegate_citizen_id`, p.`inactivity_status`,
               UNIX_TIMESTAMP(p.`inactivity_warning_at`) AS `warning_at_unix`,
               UNIX_TIMESTAMP(c.`last_active_at`) AS `owner_last_active_unix`,
               UNIX_TIMESTAMP(d.`last_active_at`) AS `delegate_last_active_unix`
        FROM `nyx_properties` p
        INNER JOIN `nyx_characters` c ON c.`citizen_id` = p.`owner_citizen_id`
        LEFT JOIN `nyx_characters` d ON d.`citizen_id` = p.`steward_delegate_citizen_id`
        WHERE p.`owner_citizen_id` IS NOT NULL AND p.`reclaimed_for_auction` = 0
    ]])

    if not properties or #properties == 0 then return { processed = 0, warnings = 0, forfeitures = 0 } end

    local warningCount = 0
    local forfeitureCount = 0
    local clearedCount = 0

    for _, p in ipairs(properties) do
        local propId = tonumber(p.property_id)
        local eval = Nyx.Inactivity.EvaluateStewardshipStatus(
            now,
            p.owner_last_active_unix,
            p.steward_delegate_citizen_id,
            p.delegate_last_active_unix,
            p.warning_at_unix,
            cfg
        )

        -- Handle state transitions
        if eval.status == "active" or eval.status == "delegated" then
            if p.inactivity_status == "grace_period" or p.warning_at_unix ~= nil then
                -- Inactivity warning cleared due to owner or steward login
                clearedCount = clearedCount + 1
                MySQL.prepare.await([[
                    UPDATE `nyx_properties`
                    SET `inactivity_status` = ?,
                        `inactivity_warning_at` = NULL
                    WHERE `property_id` = ?
                ]], { eval.status, propId })

                MySQL.prepare([[
                    INSERT INTO `nyx_inactivity_reclamation_logs`
                        (`asset_type`, `asset_id`, `previous_owner_citizen_id`, `delegate_citizen_id`, `action`, `notes`)
                    VALUES ('property', ?, ?, ?, 'warning_cleared', ?)
                ]], {
                    tostring(propId),
                    p.owner_citizen_id,
                    p.steward_delegate_citizen_id,
                    string.format("Inactivity warning cleared: %s", eval.reason)
                })

                if Nyx.Properties.Loaded and Nyx.Properties.Loaded[propId] then
                    Nyx.Properties.Loaded[propId].inactivityStatus = eval.status
                end
            end
        elseif eval.status == "grace_period" then
            if eval.needsWarning or p.inactivity_status ~= "grace_period" then
                -- Issue formal 72h grace period warning
                warningCount = warningCount + 1
                MySQL.prepare.await([[
                    UPDATE `nyx_properties`
                    SET `inactivity_status` = 'grace_period',
                        `inactivity_warning_at` = FROM_UNIXTIME(?)
                    WHERE `property_id` = ?
                ]], { now, propId })

                MySQL.prepare([[
                    INSERT INTO `nyx_inactivity_reclamation_logs`
                        (`asset_type`, `asset_id`, `previous_owner_citizen_id`, `delegate_citizen_id`, `action`, `notes`)
                    VALUES ('property', ?, ?, ?, 'warning_issued', ?)
                ]], {
                    tostring(propId),
                    p.owner_citizen_id,
                    p.steward_delegate_citizen_id,
                    string.format("72-hour grace period warning issued: Inactivity %d days without active steward",
                        math.floor(eval.inactivitySeconds / 86400))
                })

                if Nyx.Properties.Loaded and Nyx.Properties.Loaded[propId] then
                    Nyx.Properties.Loaded[propId].inactivityStatus = "grace_period"
                end

                -- Notify online owner or delegate
                local ownerPly = Nyx.GetPlayerByCitizenId(p.owner_citizen_id)
                if ownerPly then
                    TriggerClientEvent("nyx:ui:notify", ownerPly.source, {
                        type = "error",
                        title = "INAKTIVITÁSI FIGYELMEZTETÉS",
                        message = string.format("Az ingatlanod (%s) inaktivitás miatt 72 órán belül árverésre kerül!", p.label)
                    })
                end
                if p.steward_delegate_citizen_id then
                    local delPly = Nyx.GetPlayerByCitizenId(p.steward_delegate_citizen_id)
                    if delPly then
                        TriggerClientEvent("nyx:ui:notify", delPly.source, {
                            type = "warning",
                            title = "GONDNOKOLT INGATLAN VESZÉLYBEN",
                            message = string.format("A gondnokolt ingatlan (%s) 72 órán belül árverésre kerül!", p.label)
                        })
                    end
                end
            end
        elseif eval.status == "forfeited" then
            -- Grace period expired: execute municipal foreclosure blind auction
            forfeitureCount = forfeitureCount + 1

            MySQL.prepare.await([[
                UPDATE `nyx_properties`
                SET `inactivity_status` = 'reclaimed_for_auction',
                    `reclaimed_at` = NOW()
                WHERE `property_id` = ?
            ]], { propId })

            -- Trigger municipal blind auction creation via auction engine
            local okAuction, auctionIdOrErr = Nyx.Properties.ForfeitPropertyToAuction(propId)

            MySQL.prepare([[
                INSERT INTO `nyx_inactivity_reclamation_logs`
                    (`asset_type`, `asset_id`, `previous_owner_citizen_id`, `delegate_citizen_id`, `action`, `auction_id`, `notes`)
                VALUES ('property', ?, ?, ?, 'forfeited_to_auction', ?, ?)
            ]], {
                tostring(propId),
                p.owner_citizen_id,
                p.steward_delegate_citizen_id,
                tonumber(auctionIdOrErr),
                string.format("Inactivity forfeiture executed: Transferred to public blind auction (valuation $%.2f)", p.price)
            })

            if Nyx.Properties.Loaded and Nyx.Properties.Loaded[propId] then
                Nyx.Properties.Loaded[propId].inactivityStatus = "reclaimed_for_auction"
            end
        end
    end

    -- Cross-resource hook: also trigger faction inactivity check if nyx_factions is loaded
    if GetResourceState("nyx_factions") == "started" and exports['nyx_factions'] and exports['nyx_factions'].CheckFactionInactivity then
        pcall(function()
            exports['nyx_factions']:CheckFactionInactivity()
        end)
    end

    if Config.Debug then
        print(string.format("^2[Nyx:Properties:Inactivity]^7 Sweeper complete: %d checked, %d warnings, %d forfeitures, %d cleared.^7",
            #properties, warningCount, forfeitureCount, clearedCount))
    end

    return {
        processed = #properties,
        warnings = warningCount,
        forfeitures = forfeitureCount,
        cleared = clearedCount
    }
end

-- Detached Periodic Sweeper Thread
CreateThread(function()
    while GetResourceState("oxmysql") ~= "started" do
        Wait(500)
    end
    Wait(5000) -- Allow startup hydration to settle

    local intervalMs = ((Config.Inactivity and Config.Inactivity.SweeperIntervalSeconds) or 300) * 1000
    while true do
        Wait(intervalMs)
        pcall(Nyx.Properties.SweepPropertyInactivity)
    end
end)

-- ============================================================================
-- RPC Registration
-- ============================================================================

Nyx.RPC.Register("properties:registerStewardDelegate", function(src, payload)
    local player = Nyx.GetPlayer(src)
    if not player then return false, "UNAUTHENTICATED" end

    local delegateCitizenId = payload and payload.delegateCitizenId
    local scope = payload and payload.scope or "all"
    local notes = payload and payload.notes

    return Nyx.Properties.RegisterStewardshipDelegate(player.citizenId, delegateCitizenId, scope, notes)
end)

Nyx.RPC.Register("properties:revokeStewardDelegate", function(src, payload)
    local player = Nyx.GetPlayer(src)
    if not player then return false, "UNAUTHENTICATED" end

    local delegateCitizenId = payload and payload.delegateCitizenId
    local scope = payload and payload.scope or "all"

    return Nyx.Properties.RevokeStewardshipDelegate(player.citizenId, delegateCitizenId, scope)
end)

Nyx.RPC.Register("properties:assignPropertySteward", function(src, payload)
    local player = Nyx.GetPlayer(src)
    if not player then return false, "UNAUTHENTICATED" end

    local propertyId = payload and payload.propertyId
    local delegateCitizenId = payload and payload.delegateCitizenId

    return Nyx.Properties.AssignPropertySteward(propertyId, player.citizenId, delegateCitizenId)
end)

Nyx.RPC.Register("properties:getMyStewardship", function(src)
    local player = Nyx.GetPlayer(src)
    if not player then return nil, "UNAUTHENTICATED" end

    return Nyx.Properties.GetCitizenStewardshipOverview(player.citizenId)
end)

Nyx.RPC.Register("properties:getInactivityAuditLogs", function(src, limit)
    limit = math.min(100, math.max(1, tonumber(limit) or 20))
    local logs = MySQL.query.await([[
        SELECT `log_id`, `asset_type`, `asset_id`, `previous_owner_citizen_id`, `delegate_citizen_id`,
               `action`, `auction_id`, `liquidated_funds`, `treasury_tx_uuid`, `notes`,
               UNIX_TIMESTAMP(`created_at`) AS `timestamp`
        FROM `nyx_inactivity_reclamation_logs`
        ORDER BY `log_id` DESC
        LIMIT ?
    ]], { limit })
    return logs or {}
end)
