--[[
    Nyxframework: nyx_judiciary
    File: server/jury.lua
    Description: Unbiased civic juror selection via Fisher-Yates shuffle, automated summons pipeline,
                 and isolated secret balloting.
]]

Nyx = Nyx or {}
Nyx.Judiciary = Nyx.Judiciary or {}

-- 1. Unbiased Juror Selection Routine via Fisher-Yates Shuffle
function Nyx.Judiciary.SummonJury(docketId, requiredCount)
    requiredCount = requiredCount or (Config.Jury and Config.Jury.DefaultRequiredCount or 5)
    local minQuorum = Config.Jury and Config.Jury.MinimumQuorum or 3

    local docket = MySQL.single.await([[
        SELECT `docket_id`, `plaintiff_citizen_id`, `defendant_citizen_id`
        FROM `nyx_judiciary_dockets`
        WHERE `docket_id` = ?
    ]], { docketId })

    if not docket then
        return false, "DOCKET_NOT_FOUND"
    end

    -- Query active online players and filter ineligible roles
    local candidates = {}
    local onlinePlayers = Nyx.GetPlayers()

    for _, player in pairs(onlinePlayers) do
        local citId = player.citizenId
        local job = player:getMetadata("job") or "unemployed"

        local isExempt = Config.Jury and Config.Jury.ExemptJobs and Config.Jury.ExemptJobs[job]
        local isParticipant = (citId == docket.plaintiff_citizen_id or citId == docket.defendant_citizen_id)

        if not isExempt and not isParticipant then
            table.insert(candidates, {
                source = player.source,
                citizenId = citId,
                name = player.data.firstName .. " " .. player.data.lastName
            })
        end
    end

    if #candidates < minQuorum then
        return false, "INSUFFICIENT_CITIZENS_FOR_JURY"
    end

    -- Fisher-Yates shuffle for mathematically uniform random distribution
    for i = #candidates, 2, -1 do
        local j = math.random(i)
        candidates[i], candidates[j] = candidates[j], candidates[i]
    end

    local finalCount = math.min(requiredCount, #candidates)
    local selected = {}

    for i = 1, finalCount do
        local juror = candidates[i]
        table.insert(selected, juror)

        MySQL.prepare.await([[
            INSERT INTO `nyx_judiciary_juries`
                (`docket_id`, `citizen_id`, `selection_status`)
            VALUES (?, ?, 'summoned')
            ON DUPLICATE KEY UPDATE `selection_status` = 'summoned'
        ]], { docketId, juror.citizenId })

        -- Dispatch subpoena notification to the citizen
        TriggerClientEvent("nyx:ui:notify", juror.source, {
            type = "warning",
            title = "CIVIC JURY SUMMONS",
            message = string.format("You are summoned for mandatory jury duty on Case %s. Report to District Court immediately.", docketId)
        })

        TriggerClientEvent("nyx:judiciary:client:jurySummons", juror.source, {
            docketId = docketId,
            courtroom = Config.Courtroom and Config.Courtroom.InteriorCenter
        })
    end

    if Config.Debug then
        print(string.format("^2[Nyx:Judiciary]^7 Summoned %d jurors for docket %s^7", #selected, docketId))
    end

    return true, selected
end

-- 2. Check-in / Seat Juror upon arriving at the courthouse
function Nyx.Judiciary.SeatJuror(docketId, citizenId)
    local affected = MySQL.update.await([[
        UPDATE `nyx_judiciary_juries`
        SET `selection_status` = 'seated'
        WHERE `docket_id` = ? AND `citizen_id` = ? AND `selection_status` = 'summoned'
    ]], { docketId, citizenId })

    return (affected and affected > 0)
end

-- 3. Excuse Juror (e.g. peremptory challenge or valid legal hardship)
function Nyx.Judiciary.ExcuseJuror(docketId, citizenId, reason)
    local affected = MySQL.update.await([[
        UPDATE `nyx_judiciary_juries`
        SET `selection_status` = 'excused'
        WHERE `docket_id` = ? AND `citizen_id` = ?
    ]], { docketId, citizenId })

    return (affected and affected > 0)
end

-- 4. Cast Anonymized Secret Ballot during Deliberation
function Nyx.Judiciary.CastSecretBallot(docketId, citizenId, voteOutcome)
    local validVotes = {
        ['guilty'] = true,
        ['not_guilty'] = true,
        ['abstain'] = true
    }

    if not validVotes[voteOutcome] then
        return false, "INVALID_VOTE_OPTION"
    end

    local juror = MySQL.single.await([[
        SELECT `jury_id`, `selection_status`
        FROM `nyx_judiciary_juries`
        WHERE `docket_id` = ? AND `citizen_id` = ?
    ]], { docketId, citizenId })

    if not juror then
        return false, "NOT_A_JUROR_ON_CASE"
    end

    if juror.selection_status == 'voted' then
        return false, "ALREADY_VOTED"
    end

    if juror.selection_status ~= 'seated' and juror.selection_status ~= 'summoned' then
        return false, "JUROR_NOT_SEATED"
    end

    -- Commit secret ballot
    MySQL.prepare.await([[
        UPDATE `nyx_judiciary_juries`
        SET `selection_status` = 'voted',
            `secret_ballot` = ?
        WHERE `docket_id` = ? AND `citizen_id` = ?
    ]], { voteOutcome, docketId, citizenId })

    -- Check if all seated jurors have completed voting
    local tally = MySQL.query.await([[
        SELECT `selection_status`, `secret_ballot`
        FROM `nyx_judiciary_juries`
        WHERE `docket_id` = ? AND `selection_status` IN ('seated', 'voted')
    ]], { docketId })

    local totalSeated = #tally
    local totalVoted = 0
    local guiltyCount = 0
    local notGuiltyCount = 0
    local abstainCount = 0

    for _, row in ipairs(tally) do
        if row.selection_status == 'voted' then
            totalVoted = totalVoted + 1
            if row.secret_ballot == 'guilty' then
                guiltyCount = guiltyCount + 1
            elseif row.secret_ballot == 'not_guilty' then
                notGuiltyCount = notGuiltyCount + 1
            elseif row.secret_ballot == 'abstain' then
                abstainCount = abstainCount + 1
            end
        end
    end

    local allCompleted = (totalVoted >= totalSeated and totalSeated > 0)

    if allCompleted then
        local verdictRuling = (guiltyCount > notGuiltyCount) and "guilty" or "not_guilty"

        TriggerClientEvent("nyx:judiciary:client:juryVerdictReached", -1, {
            docketId = docketId,
            ruling = verdictRuling,
            tally = {
                guilty = guiltyCount,
                notGuilty = notGuiltyCount,
                abstain = abstainCount,
                total = totalVoted
            }
        })

        if Config.Debug then
            print(string.format("^2[Nyx:Judiciary]^7 Jury reached verdict on %s: %s (%d Guilty / %d Not Guilty)^7",
                docketId, verdictRuling, guiltyCount, notGuiltyCount))
        end
    end

    return true, {
        recorded = true,
        allCompleted = allCompleted
    }
end

-- 5. Query jury status for a docket
function Nyx.Judiciary.GetJuryStatus(docketId)
    local jurors = MySQL.query.await([[
        SELECT `jury_id`, `citizen_id`, `selection_status`, `assigned_at`
        FROM `nyx_judiciary_juries`
        WHERE `docket_id` = ?
    ]], { docketId })

    return jurors or {}
end
