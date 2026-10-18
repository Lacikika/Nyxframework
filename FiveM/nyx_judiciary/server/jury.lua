--[[
    Nyxframework: nyx_judiciary
    File: server/jury.lua
    Description: Unbiased civic juror selection via Fisher-Yates shuffle, automated summons pipeline,
                 no-show replacement, OneSync virtual routing bucket courtroom isolation,
                 deliberation chamber isolation, and civic duty stipend payouts.
]]

Nyx = Nyx or {}
Nyx.Judiciary = Nyx.Judiciary or {}

-- ----------------------------------------------------------------------------
-- 1. Virtual Routing Bucket Allocation for Trials
-- ----------------------------------------------------------------------------
function Nyx.Judiciary.AllocateCourtroomBucket(docketId)
    local base = (Config.Jury and Config.Jury.CourtroomBucketBase) or 2100
    local range = (Config.Jury and Config.Jury.CourtroomBucketRange) or 800
    local offset = (Config.Jury and Config.Jury.DeliberationBucketOffset) or 2000

    -- Deterministic hash of docketId string into designated bucket range
    local hash = 0
    for i = 1, #docketId do
        hash = (hash * 31 + string.byte(docketId, i)) % range
    end
    local courtroomBucket = base + hash
    local deliberationBucket = courtroomBucket + offset

    MySQL.prepare.await([[
        UPDATE `nyx_judiciary_dockets`
        SET `routing_bucket` = ?, `deliberation_bucket` = ?
        WHERE `docket_id` = ?
    ]], { courtroomBucket, deliberationBucket, docketId })

    -- Configure isolated bucket properties (disable ambient traffic/NPCs)
    if exports['nyx_core'] and exports['nyx_core'].ConfigureBucket then
        exports['nyx_core']:ConfigureBucket(courtroomBucket, false, false)
        exports['nyx_core']:ConfigureBucket(deliberationBucket, false, false)
    end

    if Config.Debug then
        print(string.format("^2[Nyx:Judiciary]^7 Allocated buckets for docket %s: Courtroom=%d, Deliberation=%d^7",
            docketId, courtroomBucket, deliberationBucket))
    end

    return courtroomBucket, deliberationBucket
end

-- ----------------------------------------------------------------------------
-- 2. Unbiased Juror Selection Routine via Fisher-Yates Shuffle
-- ----------------------------------------------------------------------------
function Nyx.Judiciary.SummonJury(docketId, requiredCount)
    requiredCount = tonumber(requiredCount) or (Config.Jury and Config.Jury.DefaultRequiredCount or 5)
    local minQuorum = (Config.Jury and Config.Jury.MinimumQuorum) or 3
    local summonsTimeout = (Config.Jury and Config.Jury.SummonsTimeoutSeconds) or 180
    local cooldownSec = (Config.Jury and Config.Jury.CooldownSeconds) or 604800

    local docket = MySQL.single.await([[
        SELECT `docket_id`, `plaintiff_citizen_id`, `defendant_citizen_id`, `presiding_judge_id`, `status`
        FROM `nyx_judiciary_dockets`
        WHERE `docket_id` = ?
    ]], { docketId })

    if not docket then
        return false, "DOCKET_NOT_FOUND"
    end

    -- Query already assigned jurors for this docket
    local existingJurors = MySQL.query.await([[
        SELECT `citizen_id`, `selection_status`, `seat_index`
        FROM `nyx_judiciary_juries`
        WHERE `docket_id` = ?
    ]], { docketId }) or {}

    local existingMap = {}
    local seatedCount = 0
    local activeSummonedCount = 0

    for _, j in ipairs(existingJurors) do
        existingMap[j.citizen_id] = j.selection_status
        if j.selection_status == 'seated' or j.selection_status == 'deliberating' or j.selection_status == 'voted' then
            seatedCount = seatedCount + 1
        elseif j.selection_status == 'summoned' then
            activeSummonedCount = activeSummonedCount + 1
        end
    end

    -- Check if we already have sufficient seated or summoned jurors
    local needed = math.max(0, requiredCount - seatedCount - activeSummonedCount)
    if needed <= 0 and (seatedCount + activeSummonedCount) >= minQuorum then
        return true, {}
    end

    -- Query active arrest warrants to disqualify wanted suspects
    local warrantRows = MySQL.query.await([[
        SELECT DISTINCT `target_citizen_id` FROM `nyx_judiciary_warrants` WHERE `status` = 'active'
    ]]) or {}
    local activeWarrantMap = {}
    for _, w in ipairs(warrantRows) do
        activeWarrantMap[w.target_citizen_id] = true
    end

    -- Query recent jury service records to respect fatigue cooldown
    local cooldownRows = MySQL.query.await([[
        SELECT DISTINCT `citizen_id` FROM `nyx_judiciary_jury_service_logs`
        WHERE `served_at` > NOW() - INTERVAL ? SECOND
    ]], { cooldownSec }) or {}
    local recentServedMap = {}
    for _, c in ipairs(cooldownRows) do
        recentServedMap[c.citizen_id] = true
    end

    -- Gather online players and extract metadata
    local candidates = {}
    local onlinePlayers = Nyx.GetPlayers() or {}

    for _, player in pairs(onlinePlayers) do
        local citId = player.citizenId
        if citId and not existingMap[citId] then
            local job = player:getMetadata("job") or "unemployed"
            local inJail = player:getMetadata("inJail") == true
            local firstName = (player.data and player.data.firstName) or "Citizen"
            local lastName = (player.data and player.data.lastName) or citId

            table.insert(candidates, {
                source = player.source,
                citizenId = citId,
                job = job,
                inJail = inJail,
                name = firstName .. " " .. lastName
            })
        end
    end

    -- Build qualification criteria
    local criteria = {
        exemptJobs = Config.Jury and Config.Jury.ExemptJobs or {},
        participants = {
            [docket.plaintiff_citizen_id] = true,
            [docket.defendant_citizen_id] = true,
            [docket.presiding_judge_id or ""] = true
        },
        activeWarrants = activeWarrantMap,
        inJail = {},
        recentServed = recentServedMap
    }

    -- Evaluate candidate pool through pure shared filter
    local eligible, disqualified = Nyx.Jury.FilterCandidates(candidates, criteria)

    -- Evaluate quorum threshold
    local totalPotential = seatedCount + activeSummonedCount + #eligible
    if totalPotential < minQuorum then
        if Config.Debug then
            print(string.format("^3[Nyx:Judiciary]^7 Insufficient citizens for jury on %s (Potential: %d, Min: %d)^7",
                docketId, totalPotential, minQuorum))
        end
        return false, "INSUFFICIENT_CITIZENS_FOR_JURY"
    end

    -- Run Fisher-Yates shuffle algorithm on eligible pool
    Nyx.Jury.FisherYatesShuffle(eligible)

    -- Dispatch summons to top needed candidates
    local selected = {}
    local dispatchCount = math.min(needed, #eligible)

    for i = 1, dispatchCount do
        local juror = eligible[i]
        table.insert(selected, juror)

        MySQL.prepare.await([[
            INSERT INTO `nyx_judiciary_juries`
                (`docket_id`, `citizen_id`, `selection_status`, `summons_expires_at`)
            VALUES (?, ?, 'summoned', DATE_ADD(NOW(), INTERVAL ? SECOND))
            ON DUPLICATE KEY UPDATE
                `selection_status` = 'summoned',
                `summons_expires_at` = DATE_ADD(NOW(), INTERVAL ? SECOND)
        ]], { docketId, juror.citizenId, summonsTimeout, summonsTimeout })

        -- Dispatch subpoena notification and court waypoint to citizen
        TriggerClientEvent("nyx:ui:notify", juror.source, {
            type = "warning",
            title = "CIVIC JURY SUMMONS",
            message = string.format("You are summoned for mandatory jury duty on Case %s. Report to District Court within %d seconds.",
                docketId, summonsTimeout)
        })

        TriggerClientEvent("nyx:judiciary:client:jurySummons", juror.source, {
            docketId = docketId,
            courtroom = Config.Courtroom and Config.Courtroom.InteriorCenter,
            timeoutSeconds = summonsTimeout
        })
    end

    if Config.Debug then
        print(string.format("^2[Nyx:Judiciary]^7 Summoned %d new jurors for docket %s (Seated: %d, Needed: %d)^7",
            #selected, docketId, seatedCount, needed))
    end

    return true, selected
end

-- ----------------------------------------------------------------------------
-- 3. Check-in / Seat Juror upon arriving at the courthouse
-- ----------------------------------------------------------------------------
function Nyx.Judiciary.SeatJuror(docketId, citizenId, preferredSeat)
    local juror = MySQL.single.await([[
        SELECT `jury_id`, `selection_status`, `seat_index`
        FROM `nyx_judiciary_juries`
        WHERE `docket_id` = ? AND `citizen_id` = ?
    ]], { docketId, citizenId })

    if not juror then
        return false, "NOT_SUMMONED_ON_CASE"
    end

    if juror.selection_status == 'seated' or juror.selection_status == 'deliberating' or juror.selection_status == 'voted' then
        return true, { seatIndex = juror.seat_index, alreadySeated = true }
    end

    if juror.selection_status ~= 'summoned' then
        return false, "INVALID_SELECTION_STATUS"
    end

    -- Query all existing jurors on docket to allocate an available seat
    local existingJurors = MySQL.query.await([[
        SELECT `citizen_id`, `seat_index`
        FROM `nyx_judiciary_juries`
        WHERE `docket_id` = ? AND `selection_status` IN ('seated', 'deliberating', 'voted')
    ]], { docketId }) or {}

    local occupied = {}
    for _, row in ipairs(existingJurors) do
        if row.seat_index then
            occupied[tonumber(row.seat_index)] = true
        end
    end

    local totalSeats = (Config.Courtroom and Config.Courtroom.JuryBox and #Config.Courtroom.JuryBox) or 6
    local chosenSeat = nil

    if preferredSeat and tonumber(preferredSeat) and not occupied[tonumber(preferredSeat)] and tonumber(preferredSeat) <= totalSeats then
        chosenSeat = tonumber(preferredSeat)
    else
        for s = 1, totalSeats do
            if not occupied[s] then
                chosenSeat = s
                break
            end
        end
    end

    if not chosenSeat then
        return false, "NO_JURY_SEATS_AVAILABLE"
    end

    -- Update database with seated status and seat index
    MySQL.prepare.await([[
        UPDATE `nyx_judiciary_juries`
        SET `selection_status` = 'seated',
            `seat_index` = ?,
            `summons_expires_at` = NULL
        WHERE `docket_id` = ? AND `citizen_id` = ?
    ]], { chosenSeat, docketId, citizenId })

    -- Synchronize player state and routing bucket if trial is underway
    local player = Nyx.GetPlayerByCitizenId(citizenId)
    if player then
        local src = player.source
        if Player and Player(src) and Player(src).state then
            Player(src).state.courtroomDocket = docketId
            Player(src).state.jurySeat = chosenSeat
        end

        local docket = MySQL.single.await([[
            SELECT `status`, `routing_bucket`, `deliberation_bucket`
            FROM `nyx_judiciary_dockets`
            WHERE `docket_id` = ?
        ]], { docketId })

        if docket and (docket.status == 'in_trial' or docket.status == 'deliberation') then
            local targetBucket = (docket.status == 'deliberation') and docket.deliberation_bucket or docket.routing_bucket
            if targetBucket and exports['nyx_core'] and exports['nyx_core'].SetRoutingBucket then
                exports['nyx_core']:SetRoutingBucket(src, targetBucket)
            end
        end

        -- Teleport and trigger seating kinematic on client
        local seatCoords = Config.Courtroom and Config.Courtroom.JuryBox and Config.Courtroom.JuryBox[chosenSeat]
        TriggerClientEvent("nyx:judiciary:client:jurorSeated", src, {
            docketId = docketId,
            seatIndex = chosenSeat,
            seatCoords = seatCoords
        })
    end

    return true, { seatIndex = chosenSeat }
end

-- ----------------------------------------------------------------------------
-- 4. Excuse Juror (Peremptory Challenge, Conflict of Interest, or Delinquency)
-- ----------------------------------------------------------------------------
function Nyx.Judiciary.ExcuseJuror(docketId, citizenId, reason)
    local affected = MySQL.update.await([[
        UPDATE `nyx_judiciary_juries`
        SET `selection_status` = 'excused',
            `seat_index` = NULL,
            `summons_expires_at` = NULL
        WHERE `docket_id` = ? AND `citizen_id` = ?
    ]], { docketId, citizenId })

    local player = Nyx.GetPlayerByCitizenId(citizenId)
    if player then
        local src = player.source
        if Player and Player(src) and Player(src).state then
            Player(src).state.courtroomDocket = nil
            Player(src).state.jurySeat = nil
            Player(src).state.inDeliberation = false
        end
        if exports['nyx_core'] and exports['nyx_core'].SetDefaultBucket then
            exports['nyx_core']:SetDefaultBucket(src)
        end
    end

    -- Automatically summon replacement if case is still pending
    local docket = MySQL.single.await([[
        SELECT `status` FROM `nyx_judiciary_dockets` WHERE `docket_id` = ?
    ]], { docketId })

    if docket and (docket.status == 'scheduled' or docket.status == 'in_trial') then
        Nyx.Judiciary.SummonJury(docketId)
    end

    return (affected and affected > 0)
end

-- ----------------------------------------------------------------------------
-- 5. Start Trial & Isolate Participants in Courtroom Routing Bucket
-- ----------------------------------------------------------------------------
function Nyx.Judiciary.StartTrial(docketId, presidingJudgeCitId)
    local docket = MySQL.single.await([[
        SELECT * FROM `nyx_judiciary_dockets` WHERE `docket_id` = ?
    ]], { docketId })

    if not docket then
        return false, "DOCKET_NOT_FOUND"
    end

    if docket.status == 'in_trial' or docket.status == 'concluded' or docket.status == 'dismissed' then
        return false, "INVALID_DOCKET_STATUS"
    end

    -- Verify jury quorum for felony criminal cases
    local minQuorum = (Config.Jury and Config.Jury.MinimumQuorum) or 3
    local seatedJurors = MySQL.query.await([[
        SELECT `citizen_id`, `seat_index`
        FROM `nyx_judiciary_juries`
        WHERE `docket_id` = ? AND `selection_status` IN ('seated', 'deliberating')
    ]], { docketId }) or {}

    if docket.case_type == 'criminal_felony' and #seatedJurors < minQuorum then
        return false, "INSUFFICIENT_SEATED_JURORS"
    end

    -- Allocate isolated courtroom routing bucket
    local courtroomBucket = docket.routing_bucket
    local deliberationBucket = docket.deliberation_bucket
    if not courtroomBucket or courtroomBucket == 0 then
        courtroomBucket, deliberationBucket = Nyx.Judiciary.AllocateCourtroomBucket(docketId)
    end

    -- Transition docket status
    MySQL.prepare.await([[
        UPDATE `nyx_judiciary_dockets`
        SET `status` = 'in_trial',
            `presiding_judge_id` = COALESCE(?, `presiding_judge_id`)
        WHERE `docket_id` = ?
    ]], { presidingJudgeCitId or nil, docketId })

    -- Route trial participants to the trial's courtroom bucket
    local participants = {
        { citId = docket.plaintiff_citizen_id, role = "plaintiff", coords = Config.Courtroom and Config.Courtroom.ProsecutionBench },
        { citId = docket.defendant_citizen_id, role = "defendant", coords = Config.Courtroom and Config.Courtroom.DefenseBench },
        { citId = presidingJudgeCitId or docket.presiding_judge_id, role = "judge", coords = Config.Courtroom and Config.Courtroom.JudgeBench }
    }

    for _, j in ipairs(seatedJurors) do
        local sIdx = j.seat_index or 1
        local sCoords = Config.Courtroom and Config.Courtroom.JuryBox and Config.Courtroom.JuryBox[sIdx]
        table.insert(participants, {
            citId = j.citizen_id,
            role = "juror",
            seatIndex = sIdx,
            coords = sCoords
        })
    end

    for _, p in ipairs(participants) do
        if p.citId then
            local ply = Nyx.GetPlayerByCitizenId(p.citId)
            if ply then
                local src = ply.source
                if exports['nyx_core'] and exports['nyx_core'].SetRoutingBucket then
                    exports['nyx_core']:SetRoutingBucket(src, courtroomBucket)
                end
                if Player and Player(src) and Player(src).state then
                    Player(src).state.courtroomDocket = docketId
                    Player(src).state.courtroomRole = p.role
                    Player(src).state.courtroomBucket = courtroomBucket
                end

                TriggerClientEvent("nyx:judiciary:client:trialSessionEnter", src, {
                    docketId = docketId,
                    role = p.role,
                    routingBucket = courtroomBucket,
                    seatIndex = p.seatIndex,
                    coords = p.coords
                })
            end
        end
    end

    TriggerClientEvent("nyx:judiciary:client:trialStarted", -1, {
        docketId = docketId,
        title = docket.title,
        caseType = docket.case_type
    })

    return true, {
        docketId = docketId,
        routingBucket = courtroomBucket,
        seatedJurorsCount = #seatedJurors
    }
end

-- ----------------------------------------------------------------------------
-- 6. Start Deliberation & Isolate Jurors in Deliberation Chamber Bucket
-- ----------------------------------------------------------------------------
function Nyx.Judiciary.StartDeliberation(docketId, presidingJudgeCitId)
    local docket = MySQL.single.await([[
        SELECT `docket_id`, `status`, `routing_bucket`, `deliberation_bucket`
        FROM `nyx_judiciary_dockets`
        WHERE `docket_id` = ?
    ]], { docketId })

    if not docket then
        return false, "DOCKET_NOT_FOUND"
    end

    if docket.status ~= 'in_trial' then
        return false, "TRIAL_NOT_IN_SESSION"
    end

    local deliberationBucket = docket.deliberation_bucket
    if not deliberationBucket or deliberationBucket == 0 then
        _, deliberationBucket = Nyx.Judiciary.AllocateCourtroomBucket(docketId)
    end

    -- Update docket status to deliberation
    MySQL.prepare.await([[
        UPDATE `nyx_judiciary_dockets`
        SET `status` = 'deliberation',
            `deliberation_started_at` = NOW()
        WHERE `docket_id` = ?
    ]], { docketId })

    -- Fetch seated jurors
    local jurors = MySQL.query.await([[
        SELECT `citizen_id`, `seat_index`
        FROM `nyx_judiciary_juries`
        WHERE `docket_id` = ? AND `selection_status` IN ('seated', 'deliberating')
    ]], { docketId }) or {}

    local minQuorum = (Config.Jury and Config.Jury.MinimumQuorum) or 3
    if #jurors < minQuorum then
        return false, "INSUFFICIENT_JURORS_FOR_DELIBERATION"
    end

    -- Update jury status and transition to deliberation chamber bucket
    MySQL.prepare.await([[
        UPDATE `nyx_judiciary_juries`
        SET `selection_status` = 'deliberating',
            `deliberation_entered_at` = NOW(),
            `secret_ballot` = NULL
        WHERE `docket_id` = ? AND `selection_status` = 'seated'
    ]], { docketId })

    local chamberCoords = Config.Courtroom and Config.Courtroom.DeliberationChamber

    for _, j in ipairs(jurors) do
        local ply = Nyx.GetPlayerByCitizenId(j.citizen_id)
        if ply then
            local src = ply.source
            if exports['nyx_core'] and exports['nyx_core'].SetRoutingBucket then
                exports['nyx_core']:SetRoutingBucket(src, deliberationBucket)
            end
            if Player and Player(src) and Player(src).state then
                Player(src).state.inDeliberation = true
                Player(src).state.deliberationBucket = deliberationBucket
            end

            TriggerClientEvent("nyx:judiciary:client:enterDeliberation", src, {
                docketId = docketId,
                chamberCoords = chamberCoords,
                timeoutSeconds = Config.Jury and Config.Jury.DeliberationTimeout or 900
            })
        end
    end

    return true, {
        docketId = docketId,
        deliberationBucket = deliberationBucket,
        jurorCount = #jurors
    }
end

-- ----------------------------------------------------------------------------
-- 7. Cast Secret Ballot & Automated Tabulation
-- ----------------------------------------------------------------------------
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
        SELECT `jury_id`, `selection_status`, `seat_index`
        FROM `nyx_judiciary_juries`
        WHERE `docket_id` = ? AND `citizen_id` = ?
    ]], { docketId, citizenId })

    if not juror then
        return false, "NOT_A_JUROR_ON_CASE"
    end

    if juror.selection_status == 'voted' then
        return false, "ALREADY_VOTED"
    end

    if juror.selection_status ~= 'seated' and juror.selection_status ~= 'deliberating' and juror.selection_status ~= 'summoned' then
        return false, "JUROR_NOT_SEATED"
    end

    -- Commit secret ballot
    MySQL.prepare.await([[
        UPDATE `nyx_judiciary_juries`
        SET `selection_status` = 'voted',
            `secret_ballot` = ?
        WHERE `docket_id` = ? AND `citizen_id` = ?
    ]], { voteOutcome, docketId, citizenId })

    -- Query all active seated/deliberating/voted jurors on this docket
    local tallyRows = MySQL.query.await([[
        SELECT `selection_status`, `secret_ballot`, `citizen_id`, `seat_index`
        FROM `nyx_judiciary_juries`
        WHERE `docket_id` = ? AND `selection_status` IN ('seated', 'deliberating', 'voted')
    ]], { docketId }) or {}

    local ballots = {}
    local allVoted = true

    for _, row in ipairs(tallyRows) do
        if row.selection_status == 'voted' and row.secret_ballot then
            table.insert(ballots, row.secret_ballot)
        else
            allVoted = false
        end
    end

    local ruleType = (Config.Jury and Config.Jury.DeliberationVoteRule) or 'majority'
    local minQuorum = (Config.Jury and Config.Jury.MinimumQuorum) or 3
    local verdictRuling, tally = Nyx.Jury.TabulateVotes(ballots, ruleType, minQuorum)

    if allVoted and verdictRuling ~= "incomplete" then
        -- Return jurors from deliberation chamber bucket back to courtroom bucket
        local docket = MySQL.single.await([[
            SELECT `routing_bucket` FROM `nyx_judiciary_dockets` WHERE `docket_id` = ?
        ]], { docketId })
        local courtroomBucket = docket and docket.routing_bucket or 0

        for _, row in ipairs(tallyRows) do
            local ply = Nyx.GetPlayerByCitizenId(row.citizen_id)
            if ply then
                local src = ply.source
                if exports['nyx_core'] and exports['nyx_core'].SetRoutingBucket then
                    exports['nyx_core']:SetRoutingBucket(src, courtroomBucket)
                end
                if Player and Player(src) and Player(src).state then
                    Player(src).state.inDeliberation = false
                end

                local seatCoords = Config.Courtroom and Config.Courtroom.JuryBox and Config.Courtroom.JuryBox[row.seat_index or 1]
                TriggerClientEvent("nyx:judiciary:client:exitDeliberation", src, {
                    docketId = docketId,
                    courtroomBucket = courtroomBucket,
                    seatIndex = row.seat_index,
                    seatCoords = seatCoords
                })
            end
        end

        -- Update docket status back to in_trial awaiting formal sentence entry
        MySQL.prepare.await([[
            UPDATE `nyx_judiciary_dockets`
            SET `status` = 'in_trial'
            WHERE `docket_id` = ?
        ]], { docketId })

        TriggerClientEvent("nyx:judiciary:client:juryVerdictReached", -1, {
            docketId = docketId,
            ruling = verdictRuling,
            tally = tally
        })

        if Config.Debug then
            print(string.format("^2[Nyx:Judiciary]^7 Jury reached verdict on %s: %s (%d Guilty / %d Not Guilty)^7",
                docketId, verdictRuling, tally.guilty, tally.notGuilty))
        end
    end

    return true, {
        recorded = true,
        allCompleted = allVoted,
        ruling = verdictRuling,
        tally = tally
    }
end

-- ----------------------------------------------------------------------------
-- 8. Conclude Trial, Award Civic Duty Stipends, and Restore Bucket 0
-- ----------------------------------------------------------------------------
function Nyx.Judiciary.ConcludeTrial(docketId, verdictRuling)
    local docket = MySQL.single.await([[
        SELECT * FROM `nyx_judiciary_dockets` WHERE `docket_id` = ?
    ]], { docketId })

    if not docket then return false, "DOCKET_NOT_FOUND" end

    local stipend = (Config.Jury and Config.Jury.CivicStipendAmount) or 500.0
    local cityMasterAcc = "gov:city:master"

    local jurors = MySQL.query.await([[
        SELECT `citizen_id`, `seat_index`, `selection_status`
        FROM `nyx_judiciary_juries`
        WHERE `docket_id` = ? AND `selection_status` IN ('seated', 'deliberating', 'voted')
    ]], { docketId }) or {}

    for _, j in ipairs(jurors) do
        -- 1. Award civic duty compensation via nyx_treasury
        if stipend > 0 and exports['nyx_treasury'] and exports['nyx_treasury'].ExecuteTransfer then
            pcall(function()
                exports['nyx_treasury']:ExecuteTransfer(
                    cityMasterAcc,
                    "citizen:" .. j.citizen_id,
                    stipend,
                    "stipend",
                    "judiciary:jury:" .. docketId,
                    string.format("Civic Duty Jury Stipend: %s", docketId),
                    0.0
                )
            end)
        end

        -- 2. Log immutable jury service for fatigue cooldown tracking
        MySQL.prepare.await([[
            INSERT INTO `nyx_judiciary_jury_service_logs`
                (`docket_id`, `citizen_id`, `seat_index`, `verdict_ruling`, `stipend_amount`)
            VALUES (?, ?, ?, ?, ?)
        ]], { docketId, j.citizen_id, j.seat_index, verdictRuling or "concluded", stipend })

        -- 3. Update jury record status
        MySQL.prepare.await([[
            UPDATE `nyx_judiciary_juries`
            SET `selection_status` = 'dismissed',
                `stipend_paid` = ?
            WHERE `docket_id` = ? AND `citizen_id` = ?
        ]], { stipend, docketId, j.citizen_id })

        -- 4. Restore juror to public routing bucket 0 and clear state
        local ply = Nyx.GetPlayerByCitizenId(j.citizen_id)
        if ply then
            local src = ply.source
            if exports['nyx_core'] and exports['nyx_core'].SetDefaultBucket then
                exports['nyx_core']:SetDefaultBucket(src)
            end
            if Player and Player(src) and Player(src).state then
                Player(src).state.courtroomDocket = nil
                Player(src).state.courtroomBucket = nil
                Player(src).state.courtroomRole = nil
                Player(src).state.jurySeat = nil
                Player(src).state.inDeliberation = false
            end
            TriggerClientEvent("nyx:judiciary:client:juryServiceConcluded", src, {
                docketId = docketId,
                stipend = stipend
            })
        end
    end

    -- Restore principal parties (plaintiff, defendant, judge) to public bucket 0
    local principals = { docket.plaintiff_citizen_id, docket.defendant_citizen_id, docket.presiding_judge_id }
    for _, citId in ipairs(principals) do
        if citId then
            local ply = Nyx.GetPlayerByCitizenId(citId)
            if ply then
                local src = ply.source
                if exports['nyx_core'] and exports['nyx_core'].SetDefaultBucket then
                    exports['nyx_core']:SetDefaultBucket(src)
                end
                if Player and Player(src) and Player(src).state then
                    Player(src).state.courtroomDocket = nil
                    Player(src).state.courtroomBucket = nil
                    Player(src).state.courtroomRole = nil
                end
            end
        end
    end

    return true, {
        docketId = docketId,
        jurorsCompensated = #jurors,
        stipendPerJuror = stipend
    }
end

-- ----------------------------------------------------------------------------
-- 9. Automated Sweeper: Summons Timeouts & Deliberation Timeouts
-- ----------------------------------------------------------------------------
function Nyx.Judiciary.CheckSummonsTimeouts()
    local expiredSummons = MySQL.query.await([[
        SELECT `docket_id`, `citizen_id`
        FROM `nyx_judiciary_juries`
        WHERE `selection_status` = 'summoned'
          AND `summons_expires_at` IS NOT NULL
          AND `summons_expires_at` < NOW()
    ]]) or {}

    for _, row in ipairs(expiredSummons) do
        if Config.Debug then
            print(string.format("^3[Nyx:Judiciary]^7 Juror %s timed out for docket %s. Auto-replacing...^7",
                row.citizen_id, row.docket_id))
        end
        Nyx.Judiciary.ExcuseJuror(row.docket_id, row.citizen_id, "summons_timeout")
    end
end

function Nyx.Judiciary.CheckDeliberationTimeouts()
    local timeoutSec = (Config.Jury and Config.Jury.DeliberationTimeout) or 900
    local timedOutDockets = MySQL.query.await([[
        SELECT `docket_id`, `routing_bucket`, `deliberation_bucket`
        FROM `nyx_judiciary_dockets`
        WHERE `status` = 'deliberation'
          AND `deliberation_started_at` IS NOT NULL
          AND `deliberation_started_at` < DATE_SUB(NOW(), INTERVAL ? SECOND)
    ]], { timeoutSec }) or {}

    for _, doc in ipairs(timedOutDockets) do
        local docketId = doc.docket_id

        -- Query current cast ballots
        local tallyRows = MySQL.query.await([[
            SELECT `secret_ballot`, `citizen_id`, `seat_index`
            FROM `nyx_judiciary_juries`
            WHERE `docket_id` = ? AND `selection_status` IN ('seated', 'deliberating', 'voted')
        ]], { docketId }) or {}

        local ballots = {}
        for _, row in ipairs(tallyRows) do
            if row.secret_ballot then table.insert(ballots, row.secret_ballot) end
        end

        local outcome, tally = Nyx.Jury.TabulateVotes(ballots, "majority", 1)
        local finalOutcome = (outcome == "incomplete" or outcome == "hung_jury") and "mistrial" or outcome

        -- Return jurors to courtroom bucket
        for _, row in ipairs(tallyRows) do
            local ply = Nyx.GetPlayerByCitizenId(row.citizen_id)
            if ply then
                local src = ply.source
                if exports['nyx_core'] and exports['nyx_core'].SetRoutingBucket then
                    exports['nyx_core']:SetRoutingBucket(src, doc.routing_bucket or 0)
                end
                if Player and Player(src) and Player(src).state then
                    Player(src).state.inDeliberation = false
                end
            end
        end

        MySQL.prepare.await([[
            UPDATE `nyx_judiciary_dockets`
            SET `status` = ?
            WHERE `docket_id` = ?
        ]], { (finalOutcome == "mistrial") and "mistrial" or "in_trial", docketId })

        TriggerClientEvent("nyx:judiciary:client:juryVerdictReached", -1, {
            docketId = docketId,
            ruling = finalOutcome,
            tally = tally,
            isTimeout = true
        })
    end
end

-- ----------------------------------------------------------------------------
-- 10. Query jury status for a docket
-- ----------------------------------------------------------------------------
function Nyx.Judiciary.GetJuryStatus(docketId)
    local jurors = MySQL.query.await([[
        SELECT `jury_id`, `citizen_id`, `seat_index`, `selection_status`, `assigned_at`, `summons_expires_at`, `stipend_paid`
        FROM `nyx_judiciary_juries`
        WHERE `docket_id` = ?
        ORDER BY `seat_index` ASC, `assigned_at` ASC
    ]], { docketId })

    return jurors or {}
end
