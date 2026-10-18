--[[
    Nyxframework: nyx_factions
    File: server/permissions.lua
    Description: Granular Role-Based Access Control (RBAC) permission node tree evaluator
                 and membership roster manager.
]]

Nyx = Nyx or {}
Nyx.Factions = Nyx.Factions or {}
Nyx.Factions.MembersCache = {} -- [factionId .. ":" .. citizenId] = memberData

-- Standardized Bridge to nyx_core
Nyx.GetPlayer = Nyx.GetPlayer or function(src)
    if exports['nyx_core'] and exports['nyx_core'].GetPlayer then
        return exports['nyx_core']:GetPlayer(src)
    end
    return nil
end

Nyx.GetPlayerByCitizenId = Nyx.GetPlayerByCitizenId or function(citizenId)
    if exports['nyx_core'] and exports['nyx_core'].GetPlayerByCitizenId then
        return exports['nyx_core']:GetPlayerByCitizenId(citizenId)
    end
    return nil
end

Nyx.RPC = Nyx.RPC or {
    Register = function(route, handler)
        if exports['nyx_core'] and exports['nyx_core'].RegisterRPC then
            exports['nyx_core']:RegisterRPC(route, handler)
        end
    end
}

-- 1. Evaluate whether a set of member permission nodes satisfies a required node
local function evaluateNodeMatch(nodesList, requiredNode)
    if Nyx.CorporateRBAC and Nyx.CorporateRBAC.EvaluatePermission then
        return Nyx.CorporateRBAC.EvaluatePermission(nodesList, requiredNode)
    end
    if not nodesList or type(nodesList) ~= "table" then return false end

    for _, node in ipairs(nodesList) do
        -- Direct exact match or global root wildcard
        if node == "*" or node == requiredNode then
            return true
        end

        -- Category prefix wildcard (e.g. 'treasury:*' matches 'treasury:sign_tx')
        if string.sub(node, -2) == ":*" then
            local prefix = string.sub(node, 1, -2) -- includes the colon
            if string.sub(requiredNode, 1, #prefix) == prefix then
                return true
            end
        end
    end

    return false
end

-- 1b. Immutable RBAC Audit Logger
function Nyx.Factions.LogRBACAction(factionId, actorCitizenId, targetCitizenId, actionType, oldValues, newValues, notes)
    if not factionId or not actorCitizenId or not targetCitizenId or not actionType then return end
    pcall(function()
        MySQL.prepare.await([[
            INSERT INTO `nyx_factions_rbac_audit`
                (`faction_id`, `actor_citizen_id`, `target_citizen_id`, `action_type`, `old_values`, `new_values`, `notes`)
            VALUES (?, ?, ?, ?, ?, ?, ?)
        ]], {
            factionId,
            actorCitizenId,
            targetCitizenId,
            actionType,
            oldValues and json.encode(oldValues) or nil,
            newValues and json.encode(newValues) or nil,
            notes or ""
        })
    end)
end

-- 2. Query member record (in-memory cache with prepared DB query fallback)
function Nyx.Factions.GetMember(citizenId, factionId)
    if not citizenId or not factionId then return nil end

    local cacheKey = factionId .. ":" .. citizenId
    if Nyx.Factions.MembersCache[cacheKey] then
        return Nyx.Factions.MembersCache[cacheKey]
    end

    local row = MySQL.single.await([[
        SELECT `membership_id`, `faction_id`, `citizen_id`, `role_title`,
               `permission_nodes`, `equity_shares`, `wage_hourly`, `hired_at`
        FROM `nyx_factions_members`
        WHERE `faction_id` = ? AND `citizen_id` = ?
    ]], { factionId, citizenId })

    if row then
        local nodes = {}
        if type(row.permission_nodes) == "string" then
            local ok, parsed = pcall(json.decode, row.permission_nodes)
            if ok and type(parsed) == "table" then nodes = parsed end
        elseif type(row.permission_nodes) == "table" then
            nodes = row.permission_nodes
        end

        local memberData = {
            membershipId = row.membership_id,
            factionId = row.faction_id,
            citizenId = row.citizen_id,
            roleTitle = row.role_title,
            permissionNodes = nodes,
            equityShares = tonumber(row.equity_shares) or 0.00,
            wageHourly = tonumber(row.wage_hourly) or 0.00,
            hiredAt = row.hired_at
        }

        Nyx.Factions.MembersCache[cacheKey] = memberData
        return memberData
    end

    return nil
end

-- 3. Granular RBAC Permission Check
function Nyx.Factions.HasPermission(citizenId, factionId, requiredNode)
    if not citizenId or not factionId or not requiredNode then return false end

    local member = Nyx.Factions.GetMember(citizenId, factionId)
    if not member then return false end

    return evaluateNodeMatch(member.permissionNodes, requiredNode)
end

-- 4. Query total issued equity shares across the faction
function Nyx.Factions.GetTotalIssuedEquity(factionId)
    local total = MySQL.scalar.await([[
        SELECT COALESCE(SUM(`equity_shares`), 0.00)
        FROM `nyx_factions_members`
        WHERE `faction_id` = ?
    ]], { factionId })

    return tonumber(total) or 0.00
end

-- 5. Add new member to faction roster
function Nyx.Factions.AddMember(actorCitizenId, factionId, targetCitizenId, roleTitle, permissionNodes, equityShares, wageHourly)
    -- Authorize action
    if actorCitizenId ~= "SYSTEM" and not Nyx.Factions.HasPermission(actorCitizenId, factionId, "roster:invite") then
        return false, "INSUFFICIENT_PERMISSIONS_INVITE"
    end

    local existing = Nyx.Factions.GetMember(targetCitizenId, factionId)
    if existing then
        return false, "MEMBER_ALREADY_EXISTS"
    end

    local equity = tonumber(equityShares) or 0.00
    if equity > 0.00 then
        local currentTotal = Nyx.Factions.GetTotalIssuedEquity(factionId)
        if (currentTotal + equity) > 100.00 then
            return false, "EXCEEDS_MAXIMUM_EQUITY_100_PERCENT"
        end
    end

    local nodes = (type(permissionNodes) == "table") and permissionNodes or { "treasury:view_ledger", "inventory:view" }
    local nodesJson = json.encode(nodes)

    local success = MySQL.prepare.await([[
        INSERT INTO `nyx_factions_members`
            (`faction_id`, `citizen_id`, `role_title`, `permission_nodes`, `equity_shares`, `wage_hourly`)
        VALUES (?, ?, ?, ?, ?, ?)
    ]], {
        factionId,
        targetCitizenId,
        roleTitle or "Associate",
        nodesJson,
        equity,
        tonumber(wageHourly) or 0.00
    })

    if not success then
        return false, "DATABASE_ERROR"
    end

    -- Invalidate cache
    Nyx.Factions.MembersCache[factionId .. ":" .. targetCitizenId] = nil

    -- Immutable audit log
    Nyx.Factions.LogRBACAction(factionId, actorCitizenId, targetCitizenId, "INVITE", nil, {
        roleTitle = roleTitle,
        nodes = nodes,
        equityShares = equity,
        wageHourly = tonumber(wageHourly) or 0.00
    }, "New member added to corporate roster")

    return true, {
        factionId = factionId,
        citizenId = targetCitizenId,
        roleTitle = roleTitle,
        nodes = nodes,
        equity = equity
    }
end

-- 6. Update existing member's roles, permission nodes, or equity
function Nyx.Factions.UpdateMember(actorCitizenId, factionId, targetCitizenId, roleTitle, permissionNodes, equityShares, wageHourly)
    if actorCitizenId ~= "SYSTEM" and not Nyx.Factions.HasPermission(actorCitizenId, factionId, "roster:promote") then
        return false, "INSUFFICIENT_PERMISSIONS_PROMOTE"
    end

    local member = Nyx.Factions.GetMember(targetCitizenId, factionId)
    if not member then
        return false, "MEMBER_NOT_FOUND"
    end

    local newEquity = (equityShares ~= nil) and tonumber(equityShares) or member.equityShares
    if newEquity ~= member.equityShares then
        local currentTotal = Nyx.Factions.GetTotalIssuedEquity(factionId)
        local adjustedTotal = (currentTotal - member.equityShares) + newEquity
        if adjustedTotal > 100.00 then
            return false, "EXCEEDS_MAXIMUM_EQUITY_100_PERCENT"
        end
    end

    local newNodes = (permissionNodes ~= nil and type(permissionNodes) == "table") and permissionNodes or member.permissionNodes
    local newRole = roleTitle or member.roleTitle
    local newWage = (wageHourly ~= nil) and tonumber(wageHourly) or member.wageHourly

    MySQL.prepare.await([[
        UPDATE `nyx_factions_members`
        SET `role_title` = ?,
            `permission_nodes` = ?,
            `equity_shares` = ?,
            `wage_hourly` = ?
        WHERE `faction_id` = ? AND `citizen_id` = ?
    ]], {
        newRole,
        json.encode(newNodes),
        newEquity,
        newWage,
        factionId,
        targetCitizenId
    })

    -- Update cache
    local cacheKey = factionId .. ":" .. targetCitizenId
    Nyx.Factions.MembersCache[cacheKey] = {
        membershipId = member.membershipId,
        factionId = factionId,
        citizenId = targetCitizenId,
        roleTitle = newRole,
        permissionNodes = newNodes,
        equityShares = newEquity,
        wageHourly = newWage,
        hiredAt = member.hiredAt
    }

    -- Immutable audit log
    Nyx.Factions.LogRBACAction(factionId, actorCitizenId, targetCitizenId, "UPDATE_PERMISSIONS", {
        roleTitle = member.roleTitle,
        nodes = member.permissionNodes,
        equityShares = member.equityShares,
        wageHourly = member.wageHourly
    }, {
        roleTitle = newRole,
        nodes = newNodes,
        equityShares = newEquity,
        wageHourly = newWage
    }, "Member role, wage, or permission nodes modified")

    return true, Nyx.Factions.MembersCache[cacheKey]
end

-- 7. Terminate member employment
function Nyx.Factions.RemoveMember(actorCitizenId, factionId, targetCitizenId)
    if actorCitizenId ~= "SYSTEM" and not Nyx.Factions.HasPermission(actorCitizenId, factionId, "roster:terminate") then
        return false, "INSUFFICIENT_PERMISSIONS_TERMINATE"
    end

    -- Prevent self-termination if sole equity holder
    local member = Nyx.Factions.GetMember(targetCitizenId, factionId)
    if not member then return false, "MEMBER_NOT_FOUND" end

    if member.equityShares >= 100.00 then
        return false, "CANNOT_TERMINATE_SOLE_OWNER"
    end

    MySQL.prepare.await([[
        DELETE FROM `nyx_factions_members`
        WHERE `faction_id` = ? AND `citizen_id` = ?
    ]], { factionId, targetCitizenId })

    Nyx.Factions.MembersCache[factionId .. ":" .. targetCitizenId] = nil

    -- Immutable audit log
    Nyx.Factions.LogRBACAction(factionId, actorCitizenId, targetCitizenId, "TERMINATE", {
        roleTitle = member.roleTitle,
        equityShares = member.equityShares
    }, nil, "Member employment terminated")

    return true
end

-- 8. Query complete roster for faction
function Nyx.Factions.GetFactionMembers(factionId)
    local rows = MySQL.query.await([[
        SELECT `membership_id`, `faction_id`, `citizen_id`, `role_title`,
               `permission_nodes`, `equity_shares`, `wage_hourly`, `hired_at`
        FROM `nyx_factions_members`
        WHERE `faction_id` = ?
        ORDER BY `equity_shares` DESC, `hired_at` ASC
    ]], { factionId })

    local roster = {}
    for _, row in ipairs(rows or {}) do
        local nodes = {}
        if type(row.permission_nodes) == "string" then
            local ok, parsed = pcall(json.decode, row.permission_nodes)
            if ok and type(parsed) == "table" then nodes = parsed end
        elseif type(row.permission_nodes) == "table" then
            nodes = row.permission_nodes
        end

        table.insert(roster, {
            membershipId = row.membership_id,
            factionId = row.faction_id,
            citizenId = row.citizen_id,
            roleTitle = row.role_title,
            permissionNodes = nodes,
            equityShares = tonumber(row.equity_shares) or 0.00,
            wageHourly = tonumber(row.wage_hourly) or 0.00,
            hiredAt = row.hired_at
        })
    end

    return roster
end

-- 9. Query RBAC audit logs for a faction
function Nyx.Factions.GetRBACAuditLog(factionId, limit)
    if not factionId then return {} end
    local maxLimit = math.max(1, math.min(100, tonumber(limit) or 25))
    local rows = MySQL.query.await([[
        SELECT `audit_id`, `faction_id`, `actor_citizen_id`, `target_citizen_id`,
               `action_type`, `old_values`, `new_values`, `notes`, `created_at`
        FROM `nyx_factions_rbac_audit`
        WHERE `faction_id` = ?
        ORDER BY `created_at` DESC
        LIMIT ?
    ]], { factionId, maxLimit })

    local auditLogs = {}
    for _, row in ipairs(rows or {}) do
        local oldVals, newVals = nil, nil
        if row.old_values and type(row.old_values) == "string" then
            local ok, parsed = pcall(json.decode, row.old_values)
            if ok then oldVals = parsed end
        end
        if row.new_values and type(row.new_values) == "string" then
            local ok, parsed = pcall(json.decode, row.new_values)
            if ok then newVals = parsed end
        end
        table.insert(auditLogs, {
            auditId = row.audit_id,
            factionId = row.faction_id,
            actorCitizenId = row.actor_citizen_id,
            targetCitizenId = row.target_citizen_id,
            actionType = row.action_type,
            oldValues = oldVals,
            newValues = newVals,
            notes = row.notes,
            createdAt = row.created_at
        })
    end
    return auditLogs
end

-- 10. Query all organization memberships for a citizen
function Nyx.Factions.GetCitizenFactions(citizenId)
    if not citizenId then return {} end
    local rows = MySQL.query.await([[
        SELECT m.`faction_id`, m.`role_title`, m.`permission_nodes`, m.`equity_shares`, m.`wage_hourly`, m.`hired_at`,
               r.`legal_name`, r.`charter_type`, r.`treasury_account_id`, r.`founder_citizen_id`, r.`inactivity_status`
        FROM `nyx_factions_members` m
        JOIN `nyx_factions_registry` r ON m.`faction_id` = r.`faction_id`
        WHERE m.`citizen_id` = ?
        ORDER BY m.`equity_shares` DESC, m.`hired_at` ASC
    ]], { citizenId })

    local factions = {}
    for _, row in ipairs(rows or {}) do
        local nodes = {}
        if type(row.permission_nodes) == "string" then
            local ok, parsed = pcall(json.decode, row.permission_nodes)
            if ok and type(parsed) == "table" then nodes = parsed end
        elseif type(row.permission_nodes) == "table" then
            nodes = row.permission_nodes
        end

        table.insert(factions, {
            factionId = row.faction_id,
            legalName = row.legal_name,
            charterType = row.charter_type,
            treasuryAccountId = row.treasury_account_id,
            founderCitizenId = row.founder_citizen_id,
            inactivityStatus = row.inactivity_status,
            roleTitle = row.role_title,
            permissionNodes = nodes,
            equityShares = tonumber(row.equity_shares) or 0.00,
            wageHourly = tonumber(row.wage_hourly) or 0.00,
            hiredAt = row.hired_at
        })
    end
    return factions
end
