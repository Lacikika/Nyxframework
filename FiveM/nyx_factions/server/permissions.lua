--[[
    Nyxframework: nyx_factions
    File: server/permissions.lua
    Description: Granular Role-Based Access Control (RBAC) permission node tree evaluator
                 and membership roster manager.
]]

Nyx = Nyx or {}
Nyx.Factions = Nyx.Factions or {}
Nyx.Factions.MembersCache = {} -- [factionId .. ":" .. citizenId] = memberData

-- 1. Evaluate whether a set of member permission nodes satisfies a required node
local function evaluateNodeMatch(nodesList, requiredNode)
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
