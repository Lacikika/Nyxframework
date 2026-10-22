--[[
    Nyxframework: nyx_parliament
    File: server/polling.lua
    Description: Citizen OS mobile opinion surveys, voter sentiment tracking, and response deduplication.
]]

Nyx = Nyx or {}
Nyx.Parliament = Nyx.Parliament or {}

-- 1. Create a Citizen OS Mobile Survey / Opinion Poll
function Nyx.Parliament.CreateMobilePoll(src, title, description, pollType, officeId, optionsList, durationHours)
    local creatorCitId = "SYSTEM_GOV"
    if src and src > 0 then
        local player = exports['nyx_core']:GetPlayer(src)
        if player then creatorCitId = player.citizenId end
    end

    if not title or type(title) ~= "string" or #title < 3 then
        return { success = false, error = "INVALID_POLL_TITLE" }
    end

    if not optionsList or type(optionsList) ~= "table" or #optionsList < 2 then
        return { success = false, error = "AT_LEAST_TWO_OPTIONS_REQUIRED" }
    end

    local sanitizeTitle = title:gsub("[^%w%s]", ""):gsub("%s+", "_"):lower()
    local pollId = string.format("poll:%s_%s", sanitizeTitle:sub(1, 24), Nyx.RPC.GenerateNonce():sub(1, 6))
    local pType = pollType or "policy_survey"
    local hours = tonumber(durationHours) or Config.MobilePollDurationHours or 72

    local optionsJson = json.encode(optionsList)

    local inserted = MySQL.prepare.await([[
        INSERT INTO `nyx_parliament_polls`
            (`poll_id`, `title`, `description`, `creator_citizen_id`, `poll_type`, `office_id`,
             `options_json`, `total_responses`, `starts_at`, `ends_at`, `status`)
        VALUES (?, ?, ?, ?, ?, ?, ?, 0, CURRENT_TIMESTAMP, DATE_ADD(CURRENT_TIMESTAMP, INTERVAL ? HOUR), 'active')
    ]], {
        pollId,
        title,
        description or "Citizen OS Opinion Survey",
        creatorCitId,
        pType,
        officeId,
        optionsJson,
        hours
    })

    if not inserted then
        return { success = false, error = "DATABASE_INSERTION_FAILED" }
    end

    print(string.format("^2[Nyx:Parliament] Created Citizen OS Mobile Poll '%s' (%s, Type: %s, %d hours)^7",
        title, pollId, pType, hours))

    TriggerClientEvent("nyx:parliament:client:newMobilePoll", -1, {
        pollId = pollId,
        title = title,
        pollType = pType,
        endsInHours = hours
    })

    return {
        success = true,
        pollId = pollId,
        title = title,
        pollType = pType,
        options = optionsList
    }
end

-- 2. Submit a Mobile Survey Response with Deduplication
function Nyx.Parliament.SubmitPollResponse(src, pollId, selectedOption, clientHash)
    local player = exports['nyx_core']:GetPlayer(src)
    if not player then return { success = false, error = "UNAUTHORIZED" } end

    if not pollId or type(pollId) ~= "string" or not selectedOption or type(selectedOption) ~= "string" then
        return { success = false, error = "INVALID_POLL_PARAMETERS" }
    end

    local poll = MySQL.single.await([[
        SELECT * FROM `nyx_parliament_polls`
        WHERE `poll_id` = ? AND `status` = 'active' AND `ends_at` >= CURRENT_TIMESTAMP
    ]], { pollId })

    if not poll then
        return { success = false, error = "POLL_NOT_ACTIVE_OR_EXPIRED" }
    end

    local citId = player.citizenId
    local voterHash = clientHash
    if not voterHash or #voterHash < 8 then
        voterHash = Nyx.RPC.GenerateNonce():sub(1, 16)
    end

    -- Deduplication check by citizen ID or voter hash
    local alreadyResponded = MySQL.scalar.await([[
        SELECT COUNT(*) FROM `nyx_parliament_poll_responses`
        WHERE `poll_id` = ? AND (`citizen_id` = ? OR `voter_hash` = ?)
    ]], { pollId, citId, voterHash }) or 0

    if alreadyResponded > 0 then
        return { success = false, error = "ALREADY_SUBMITTED_POLL_RESPONSE" }
    end

    local inserted = MySQL.insert.await([[
        INSERT INTO `nyx_parliament_poll_responses`
            (`poll_id`, `citizen_id`, `voter_hash`, `selected_option`, `device_os`)
        VALUES (?, ?, ?, ?, 'CitizenOS_Mobile')
    ]], {
        pollId,
        citId,
        voterHash,
        selectedOption
    })

    if not inserted then
        return { success = false, error = "DATABASE_INSERTION_FAILED" }
    end

    MySQL.prepare.await([[
        UPDATE `nyx_parliament_polls` SET `total_responses` = `total_responses` + 1 WHERE `poll_id` = ?
    ]], { pollId })

    print(string.format("^2[Nyx:Parliament] Poll response recorded for '%s' from citizen %s (Option: %s)^7",
        pollId, citId, selectedOption))

    return {
        success = true,
        pollId = pollId,
        selectedOption = selectedOption
    }
end

-- 3. Calculate and Retrieve Poll Results & Voter Sentiment
function Nyx.Parliament.GetPollResults(pollId)
    if not pollId or type(pollId) ~= "string" then
        return { success = false, error = "INVALID_POLL_ID" }
    end

    local poll = MySQL.single.await([[
        SELECT * FROM `nyx_parliament_polls` WHERE `poll_id` = ?
    ]], { pollId })

    if not poll then
        return { success = false, error = "POLL_NOT_FOUND" }
    end

    local responseRows = MySQL.query.await([[
        SELECT `selected_option`, COUNT(*) AS `cnt`
        FROM `nyx_parliament_poll_responses`
        WHERE `poll_id` = ?
        GROUP BY `selected_option`
    ]], { pollId }) or {}

    local counts = {}
    for _, r in ipairs(responseRows) do
        counts[r.selected_option] = tonumber(r.cnt) or 0
    end

    local sentiment = Nyx.CampaignFinance.CalculatePollSentiment(poll.options_json, counts, poll.total_responses)

    return {
        success = true,
        pollId = pollId,
        title = poll.title,
        description = poll.description,
        pollType = poll.poll_type,
        status = poll.status,
        totalResponses = poll.total_responses,
        sentiment = sentiment
    }
end

-- ============================================================================
-- RPC Registrations for Citizen OS Polling
-- ============================================================================

Nyx.RPC.Register("parliament:createMobilePoll", function(src, payload)
    if type(payload) ~= "table" then return { success = false, error = "INVALID_PAYLOAD" } end
    return Nyx.Parliament.CreateMobilePoll(
        src,
        payload.title,
        payload.description,
        payload.pollType,
        payload.officeId,
        payload.options,
        payload.durationHours
    )
end)

Nyx.RPC.Register("parliament:submitPollResponse", function(src, payload)
    if type(payload) ~= "table" then return { success = false, error = "INVALID_PAYLOAD" } end
    return Nyx.Parliament.SubmitPollResponse(src, payload.pollId, payload.selectedOption, payload.voterHash)
end)

Nyx.RPC.Register("parliament:getPollResults", function(src, pollId)
    return Nyx.Parliament.GetPollResults(pollId)
end)

Nyx.RPC.Register("parliament:getMobilePolls", function(src, status)
    local query = [[
        SELECT `poll_id`, `title`, `description`, `creator_citizen_id`, `poll_type`,
               `office_id`, `options_json`, `total_responses`, `starts_at`, `ends_at`, `status`, `created_at`
        FROM `nyx_parliament_polls`
    ]]
    local params = {}
    if status and #status > 0 then
        query = query .. " WHERE `status` = ?"
        params[#params + 1] = status
    end
    query = query .. " ORDER BY `created_at` DESC LIMIT 20"

    local rows = MySQL.query.await(query, params) or {}
    return rows
end)
