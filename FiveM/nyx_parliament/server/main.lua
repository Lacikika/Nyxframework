--[[
    Nyxframework: nyx_parliament
    File: server/main.lua
    Description: Parliament main lifecycle, lawbook queries, and server event bindings.
]]

Nyx = Nyx or {}
Nyx.Parliament = Nyx.Parliament or {}

-- Standardized RPC Bridge to nyx_core
Nyx.RPC = Nyx.RPC or {
    Register = function(route, handler)
        exports['nyx_core']:RegisterRPC(route, handler)
    end,
    GenerateNonce = function()
        local template = 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'
        return (string.gsub(template, '[xy]', function(c)
            local v = (c == 'x') and math.random(0, 0xf) or math.random(8, 0xb)
            return string.format('%x', v)
        end))
    end
}

-- RPC: Query Authoritative Law Book
Nyx.RPC.Register("parliament:getLawBook", function(src, categoryFilter)
    local results = {}
    for id, law in pairs(Nyx.Parliament.Laws) do
        if not categoryFilter or categoryFilter == "ALL" or law.category == categoryFilter then
            results[#results + 1] = {
                id = law.id,
                title = law.title,
                category = law.category,
                currentValue = law.currentValue,
                minAllowed = law.minAllowed,
                maxAllowed = law.maxAllowed,
                lastAmended = law.lastAmended
            }
        end
    end
    return results
end)

-- RPC: Comprehensive Governance Overview for Master UI
Nyx.RPC.Register("parliament:getOverview", function(src)
    local player = exports['nyx_core']:GetPlayer(src)
    local citId = player and player.citizenId or "CIT_UNKNOWN"
    local charName = player and player.charName or "Citizen"

    -- 1. Check if caller is an elected official
    local officialRow = MySQL.single.await([[
        SELECT `office_id`, `title` FROM `nyx_parliament_officials`
        WHERE `citizen_id` = ? AND `status` = 'active'
    ]], { citId })

    local isOfficial = officialRow ~= nil
    local officeTitle = officialRow and officialRow.title or nil
    local officeId = officialRow and officialRow.office_id or nil

    -- 2. Query Active & Recent Sessions
    local sessions = {}
    local sessionRows = MySQL.query.await([[
        SELECT `session_id`, `title`, `description`, `type`, `category`, `required_quorum`,
               `starts_at`, `ends_at`, `status`, `metadata`, `winner_option`
        FROM `nyx_parliament_sessions`
        WHERE `status` IN ('active', 'scheduled', 'concluded')
        ORDER BY FIELD(`status`, 'active', 'scheduled', 'concluded'), `created_at` DESC
        LIMIT 20
    ]]) or {}

    for _, r in ipairs(sessionRows) do
        local meta = {}
        if r.metadata and #r.metadata > 0 then
            local ok, parsed = pcall(json.decode, r.metadata)
            if ok and type(parsed) == "table" then meta = parsed end
        end

        local candidates = {}
        if r.type == "election" then
            local candRows = MySQL.query.await([[
                SELECT `candidate_id`, `session_id`, `citizen_id`, `display_name`, `party_affiliation`,
                       `campaign_slogan`, `platform_summary`, `collateral_deposited`, `endorsements_count`, `status`
                FROM `nyx_parliament_candidates`
                WHERE `session_id` = ?
                ORDER BY `endorsements_count` DESC, `created_at` ASC
            ]], { r.session_id }) or {}
            candidates = candRows
        elseif meta.candidates then
            candidates = meta.candidates
        elseif meta.options then
            candidates = meta.options
        end

        sessions[#sessions + 1] = {
            sessionId = r.session_id,
            title = r.title,
            description = r.description,
            type = r.type,
            category = r.category or "general",
            requiredQuorum = r.required_quorum,
            startsAt = r.starts_at,
            endsAt = r.ends_at,
            status = r.status,
            winner = r.winner_option,
            metadata = meta,
            candidates = candidates
        }
    end

    -- 3. Live Penal Code and Statutory Lawbook
    local penalCode = Nyx.Parliament.GetPenalCode()
    local allLaws = {}
    for id, law in pairs(Nyx.Parliament.Laws) do
        allLaws[#allLaws + 1] = {
            id = law.id,
            title = law.title,
            category = law.category,
            currentValue = law.currentValue,
            minAllowed = law.minAllowed,
            maxAllowed = law.maxAllowed,
            lastAmended = law.lastAmended
        }
    end
    table.sort(allLaws, function(a, b) return a.id < b.id end)

    -- 4. Active Elected Officials
    local officials = MySQL.query.await([[
        SELECT `office_id`, `title`, `citizen_id`, `display_name`, `elected_session_id`,
               `term_start`, `term_end`, `status`
        FROM `nyx_parliament_officials`
        WHERE `status` = 'active'
    ]]) or {}

    -- 5. Active Recall Petitions
    local petitions = MySQL.query.await([[
        SELECT `petition_id`, `office_id`, `initiator_citizen_id`, `reason`,
               `signatures_count`, `required_signatures`, `status`, `expires_at`
        FROM `nyx_parliament_recall_petitions`
        WHERE `status` = 'active' AND `expires_at` >= CURRENT_TIMESTAMP
    ]]) or {}

    -- 6. Recent Legislative Amendments
    local recentAmendments = MySQL.query.await([[
        SELECT `audit_id`, `session_id`, `law_id`, `field`, `old_value`, `new_value`,
               `enacted_by_session_title`, `enacted_at`
        FROM `nyx_parliament_amendment_audit`
        ORDER BY `enacted_at` DESC
        LIMIT 10
    ]]) or {}

    return {
        citizenId = citId,
        characterName = charName,
        isOfficial = isOfficial,
        officeTitle = officeTitle,
        officeId = officeId,
        sessions = sessions,
        laws = allLaws,
        penalCode = penalCode,
        officials = officials,
        petitions = petitions,
        recentAmendments = recentAmendments
    }
end)

-- RPC: Query Legislative Amendment Audit History
Nyx.RPC.Register("parliament:getAmendmentAudit", function(src, filterLawId)
    local query = [[
        SELECT `audit_id`, `session_id`, `law_id`, `field`, `old_value`, `new_value`,
               `enacted_by_session_title`, `enacted_at`
        FROM `nyx_parliament_amendment_audit`
    ]]
    local params = {}
    if filterLawId and #filterLawId > 0 then
        query = query .. " WHERE `law_id` = ?"
        params[#params + 1] = filterLawId
    end
    query = query .. " ORDER BY `enacted_at` DESC LIMIT 50"

    local rows = MySQL.query.await(query, params)
    return rows or {}
end)

AddEventHandler("onResourceStart", function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    print("^2[Nyx:Parliament] Autonomous Civic Governance & Legislative Engine initialized.^7")
end)

AddEventHandler("onResourceStop", function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    print("^3[Nyx:Parliament] Governance engine halted.^7")
end)
