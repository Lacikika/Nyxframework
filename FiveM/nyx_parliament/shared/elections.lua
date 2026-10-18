--[[
    Nyxframework: nyx_parliament
    File: shared/elections.lua
    Description: Pure Lua 5.4 domain engine for Democratic Parliamentary Elections & Recall Referendums:
                 candidate eligibility, collateral escrow & refund evaluation, physical voting booth proximity,
                 anti-Sybil machine footprint hashing, term limit expiration, and recall referendum state machine.
]]

Nyx = Nyx or {}
Nyx.DemocraticElections = Nyx.DemocraticElections or {}

-- ----------------------------------------------------------------------------
-- Statutory Constants & Canonical Civic Defaults
-- ----------------------------------------------------------------------------
Nyx.DemocraticElections.Constants = {
    NominationWindowHours = 48,
    VotingWindowHours = 72,
    CollateralRefundVoteThresholdPct = 10.0, -- Candidates with >= 10.0% votes receive collateral refund
    CandidateCollateralDefault = 2500.00,
    RequiredEndorsementsDefault = 3,
    RecallSignatureThresholdDefault = 5,
    RecallImmunityCooldownDays = 7,          -- 7-day immunity after surviving a recall referendum
    MaxCandidatesPerSession = 10,
    DefaultBoothInteractDistance = 2.5
}

Nyx.DemocraticElections.Offices = {
    ['mayor'] = {
        title = "City Mayor",
        department = "Executive",
        termDays = 30,
        maxConsecutiveTerms = 2
    },
    ['chief_magistrate'] = {
        title = "Chief Magistrate",
        department = "Judiciary",
        termDays = 45,
        maxConsecutiveTerms = 2
    },
    ['district_commissioner'] = {
        title = "District Commissioner",
        department = "Legislative",
        termDays = 30,
        maxConsecutiveTerms = 3
    }
}

Nyx.DemocraticElections.Booths = {
    ['booth:city_hall'] = {
        id = "booth:city_hall",
        label = "City Hall Council Voting Booth",
        zone = "Downtown Los Santos",
        coords = vector3(-540.9, -199.3, 47.5),
        radius = 2.5
    },
    ['booth:sandy_shores'] = {
        id = "booth:sandy_shores",
        label = "Sandy Shores Regional Ballot Station",
        zone = "Sandy Shores",
        coords = vector3(1853.2, 3686.9, 34.3),
        radius = 2.5
    },
    ['booth:paleto_bay'] = {
        id = "booth:paleto_bay",
        label = "Paleto Bay Justice Center Ballot Station",
        zone = "Paleto Bay",
        coords = vector3(-448.2, 6012.3, 31.7),
        radius = 2.5
    }
}

-- ----------------------------------------------------------------------------
-- 1. Candidate Eligibility & Registration Validator
-- ----------------------------------------------------------------------------
function Nyx.DemocraticElections.EvaluateCandidateEligibility(citizenId, officeId, session, existingCandidates, activeOfficial, config)
    if not citizenId or type(citizenId) ~= "string" or #citizenId < 3 then
        return false, "INVALID_CITIZEN_ID"
    end

    if not session or type(session) ~= "table" then
        return false, "SESSION_NOT_FOUND"
    end

    if session.type ~= "election" then
        return false, "SESSION_NOT_AN_ELECTION"
    end

    if session.status ~= "active" and session.status ~= "scheduled" then
        return false, "SESSION_NOT_OPEN"
    end

    -- If election session has phased lifecycle, only allow during nomination or early voting
    if session.election_phase and session.election_phase ~= "nomination" and session.election_phase ~= "voting" then
        return false, "NOMINATION_PERIOD_CLOSED"
    end

    local cfg = config or Nyx.DemocraticElections.Constants
    local maxCandidates = cfg.MaxCandidatesPerSession or 10
    local candidates = existingCandidates or {}

    if #candidates >= maxCandidates then
        return false, "MAX_CANDIDATES_REACHED"
    end

    -- Check if candidate already registered in this session
    for _, c in ipairs(candidates) do
        local cCitId = c.citizen_id or c.citizenId
        if cCitId == citizenId and c.status ~= "withdrawn" then
            return false, "ALREADY_REGISTERED_AS_CANDIDATE"
        end
    end

    -- Check term limits (e.g. consecutive term limits if citizen is current official)
    local targetOffice = officeId or session.office_id or (session.metadata and session.metadata.officeId)
    if targetOffice and activeOfficial and (activeOfficial.citizen_id == citizenId or activeOfficial.citizenId == citizenId) then
        local officeSpec = Nyx.DemocraticElections.Offices[targetOffice]
        local maxTerms = officeSpec and officeSpec.maxConsecutiveTerms or 2
        local currentTerms = tonumber(activeOfficial.consecutive_terms) or 1
        if currentTerms >= maxTerms then
            return false, "TERM_LIMIT_EXCEEDED"
        end
    end

    return true, nil
end

-- ----------------------------------------------------------------------------
-- 2. Collateral Escrow & Account Resolution
-- ----------------------------------------------------------------------------
function Nyx.DemocraticElections.CalculateCollateralEscrow(collateralRequired, bankBalance, citizenId, sessionId)
    local required = tonumber(collateralRequired) or Nyx.DemocraticElections.Constants.CandidateCollateralDefault
    local balance = tonumber(bankBalance) or 0.0

    if required < 0 then
        return false, nil, "INVALID_COLLATERAL_AMOUNT"
    end

    if balance < required then
        return false, {
            required = required,
            balance = balance,
            deficit = math.max(0.0, required - balance)
        }, "INSUFFICIENT_COLLATERAL_FUNDS"
    end

    return true, {
        required = required,
        balance = balance,
        debitAccount = string.format("char:%s:bank", citizenId or "unknown"),
        creditAccount = "gov:city:master",
        category = "election_collateral",
        reference = string.format("parliament:%s", sessionId or "general")
    }, nil
end

-- ----------------------------------------------------------------------------
-- 3. Collateral Refund & Forfeiture Evaluator
-- ----------------------------------------------------------------------------
function Nyx.DemocraticElections.EvaluateCollateralRefund(candidate, totalValidBallots, winnerCandidateId, thresholdPct)
    if not candidate or type(candidate) ~= "table" then
        return { eligible = false, amount = 0.0, status = "forfeited", reason = "INVALID_CANDIDATE" }
    end

    local deposited = tonumber(candidate.collateral_deposited) or 0.0
    if deposited <= 0.0 then
        return { eligible = false, amount = 0.0, status = "refunded", reason = "NO_COLLATERAL_DEPOSITED" }
    end

    local status = candidate.status or "nominated"
    local candId = candidate.candidate_id or candidate.id

    -- 1. Voluntary withdrawal before voting
    if status == "withdrawn" then
        return {
            eligible = true,
            amount = deposited,
            status = "refunded",
            reason = "WITHDRAWAL_BEFORE_BALLOT"
        }
    end

    -- 2. Disqualified candidates forfeit collateral to municipal treasury
    if status == "disqualified" then
        return {
            eligible = false,
            amount = 0.0,
            status = "forfeited",
            reason = "CANDIDATE_DISQUALIFIED"
        }
    end

    -- 3. Winner of election always receives full collateral refund
    if winnerCandidateId and candId == winnerCandidateId then
        return {
            eligible = true,
            amount = deposited,
            status = "refunded",
            reason = "ELECTION_WINNER"
        }
    end

    -- 4. Vote share threshold evaluation
    local totalVotes = tonumber(totalValidBallots) or 0
    local candVotes = tonumber(candidate.vote_count) or 0
    local threshold = tonumber(thresholdPct) or Nyx.DemocraticElections.Constants.CollateralRefundVoteThresholdPct

    if totalVotes > 0 then
        local sharePct = (candVotes / totalVotes) * 100.0
        if sharePct >= threshold then
            return {
                eligible = true,
                amount = deposited,
                status = "refunded",
                reason = "MET_VOTE_THRESHOLD",
                sharePct = sharePct
            }
        else
            return {
                eligible = false,
                amount = 0.0,
                status = "forfeited",
                reason = "BELOW_VOTE_THRESHOLD",
                sharePct = sharePct
            }
        end
    end

    -- 5. Fallback: If election concluded with zero ballots or invalidated, refund qualified candidates
    if status == "qualified" then
        return {
            eligible = true,
            amount = deposited,
            status = "refunded",
            reason = "QUALIFIED_NO_VOTES_CAST"
        }
    end

    return {
        eligible = false,
        amount = 0.0,
        status = "forfeited",
        reason = "DID_NOT_QUALIFY"
    }
end

-- ----------------------------------------------------------------------------
-- 4. Physical Voting Booth Spatial Proximity & Station Resolution
-- ----------------------------------------------------------------------------
function Nyx.DemocraticElections.ValidateBoothProximity(playerCoords, boothsCatalog, maxDistance)
    local booths = boothsCatalog or Nyx.DemocraticElections.Booths
    local maxDist = maxDistance or Nyx.DemocraticElections.Constants.DefaultBoothInteractDistance

    if not playerCoords then
        return {
            isNear = false,
            boothId = nil,
            boothLabel = "Remote Terminal",
            distance = 999999.0
        }
    end

    local px = playerCoords.x or (playerCoords[1]) or 0.0
    local py = playerCoords.y or (playerCoords[2]) or 0.0
    local pz = playerCoords.z or (playerCoords[3]) or 0.0

    local nearestId = nil
    local nearestLabel = nil
    local shortestDist = 999999.0

    for id, booth in pairs(booths) do
        local bx = booth.coords and (booth.coords.x or booth.coords[1]) or 0.0
        local by = booth.coords and (booth.coords.y or booth.coords[2]) or 0.0
        local bz = booth.coords and (booth.coords.z or booth.coords[3]) or 0.0

        local dx = px - bx
        local dy = py - by
        local dz = pz - bz
        local dist = math.sqrt(dx * dx + dy * dy + dz * dz)

        if dist < shortestDist then
            shortestDist = dist
            nearestId = id
            nearestLabel = booth.label
        end
    end

    local isNear = shortestDist <= maxDist

    return {
        isNear = isNear,
        boothId = isNear and nearestId or nil,
        boothLabel = isNear and nearestLabel or "Remote Terminal",
        distance = math.floor(shortestDist * 100.0 + 0.5) / 100.0,
        nearestBoothId = nearestId
    }
end

-- ----------------------------------------------------------------------------
-- 5. Anti-Sybil Machine / License Footprint Hasher
-- ----------------------------------------------------------------------------
function Nyx.DemocraticElections.GenerateHardwareFootprintHash(identifiers, tokens, fallbackSrc)
    if type(tokens) == "table" and #tokens > 0 then
        local raw = table.concat(tokens, ":")
        return string.format("HWID-%08x%08x", #raw, #tokens * 54321)
    end

    if type(identifiers) == "table" then
        for _, id in ipairs(identifiers) do
            if type(id) == "string" and string.sub(id, 1, 8) == "license:" then
                return "LIC-" .. string.sub(id, 9)
            end
        end
    end

    return string.format("ANON-DEV-%s", tostring(fallbackSrc or "unknown"))
end

-- ----------------------------------------------------------------------------
-- 6. Official Term Limit Expiration State Machine
-- ----------------------------------------------------------------------------
function Nyx.DemocraticElections.EvaluateTermExpiration(official, currentEpoch)
    if not official or type(official) ~= "table" then
        return { isExpired = false, error = "INVALID_OFFICIAL" }
    end

    local status = official.status or "active"
    if status ~= "active" then
        return { isExpired = false, status = status, reason = "NOT_ACTIVE" }
    end

    local now = tonumber(currentEpoch) or os.time()
    local termEnd = official.term_end_epoch or (type(official.term_end) == "number" and official.term_end) or now + 86400

    -- If string timestamp e.g. "2026-10-18 10:00:00", caller or helper converts or compares
    local isExpired = (now >= termEnd)

    return {
        isExpired = isExpired,
        officeId = official.office_id or "unknown",
        citizenId = official.citizen_id or "unknown",
        remainingSeconds = math.max(0, termEnd - now),
        consecutiveTerms = tonumber(official.consecutive_terms) or 1
    }
end

-- ----------------------------------------------------------------------------
-- 7. Recall Petition Eligibility & Cooldown Evaluator
-- ----------------------------------------------------------------------------
function Nyx.DemocraticElections.EvaluateRecallEligibility(official, initiatorCitizenId, existingPetitions, currentEpoch)
    if not official or type(official) ~= "table" then
        return false, "NO_ACTIVE_OFFICIAL_IN_OFFICE"
    end

    if official.status ~= "active" then
        return false, "OFFICIAL_NOT_ACTIVE"
    end

    local targetCitId = official.citizen_id or official.citizenId
    if not targetCitId then
        return false, "NO_OFFICIAL_ASSIGNED"
    end

    -- Cannot recall self
    if initiatorCitizenId == targetCitId then
        return false, "CANNOT_RECALL_SELF"
    end

    local now = tonumber(currentEpoch) or os.time()

    -- Check recall immunity cooldown
    local cooldownEpoch = official.cooldown_until_epoch or (type(official.cooldown_until) == "number" and official.cooldown_until)
    if cooldownEpoch and now < cooldownEpoch then
        local remSec = cooldownEpoch - now
        return false, string.format("RECALL_COOLDOWN_ACTIVE:%d", remSec)
    end

    -- Check for duplicate active recall petition
    if existingPetitions and type(existingPetitions) == "table" then
        for _, pet in ipairs(existingPetitions) do
            local pOffice = pet.office_id or pet.officeId
            local pStatus = pet.status
            if pOffice == official.office_id and pStatus == "active" then
                return false, "ACTIVE_PETITION_ALREADY_EXISTS"
            end
        end
    end

    return true, nil
end

-- ----------------------------------------------------------------------------
-- 8. Recall Referendum Outcome Evaluator
-- ----------------------------------------------------------------------------
function Nyx.DemocraticElections.EvaluateRecallReferendumOutcome(winnerOption, officeId)
    local winner = tostring(winnerOption or ""):upper()
    local passed = (winner == "RECALL_YES" or winner == "PASS" or winner == "YES")

    if passed then
        return {
            passed = true,
            vacateOfficial = true,
            scheduleSnapElection = true,
            action = "OFFICIAL_RECALLED",
            officeId = officeId
        }
    else
        return {
            passed = false,
            vacateOfficial = false,
            scheduleSnapElection = false,
            applyCooldown = true,
            cooldownDays = Nyx.DemocraticElections.Constants.RecallImmunityCooldownDays,
            action = "OFFICIAL_RETAINED",
            officeId = officeId
        }
    end
end

-- ----------------------------------------------------------------------------
-- 9. Status Badge & UI Progress Formatters
-- ----------------------------------------------------------------------------
function Nyx.DemocraticElections.FormatElectionStatusBadge(phase, status)
    local p = string.lower(phase or "")
    local s = string.lower(status or "")

    if s == "concluded" then
        return { label = "Lezárult (Hitelesítve)", badgeClass = "badge-concluded", icon = "fa-solid fa-award" }
    elseif s == "invalidated" then
        return { label = "Érvénytelen (Kórum Hiánya)", badgeClass = "badge-danger", icon = "fa-solid fa-ban" }
    elseif p == "nomination" or s == "scheduled" then
        return { label = "Jelöltállítási Időszak", badgeClass = "badge-info", icon = "fa-solid fa-user-plus" }
    elseif p == "voting" or s == "active" then
        return { label = "Aktív Szavazás (Preferenciális)", badgeClass = "badge-success", icon = "fa-solid fa-check-to-slot" }
    elseif p == "tallying" or s == "tallying" then
        return { label = "Összesítés Folyamatban (IRV)", badgeClass = "badge-warning", icon = "fa-solid fa-arrows-rotate" }
    end

    return { label = "Általános Választás", badgeClass = "badge-secondary", icon = "fa-solid fa-landmark" }
end

function Nyx.DemocraticElections.FormatRecallProgressBar(currentSignatures, requiredSignatures)
    local cur = math.max(0, tonumber(currentSignatures) or 0)
    local req = math.max(1, tonumber(requiredSignatures) or Nyx.DemocraticElections.Constants.RecallSignatureThresholdDefault)
    local pct = math.min(100.0, math.floor(((cur / req) * 100.0) + 0.5))
    local certified = (cur >= req)

    return {
        currentSignatures = cur,
        requiredSignatures = req,
        progressPercent = pct,
        isCertified = certified,
        remainingSignatures = math.max(0, req - cur),
        label = string.format("%d / %d aláírás (%d%%)", cur, req, pct)
    }
end

function Nyx.DemocraticElections.GenerateElectionSessionId(officeId, year, nonce)
    local cleanOffice = tostring(officeId or "general"):lower():gsub("[^%w_]", "")
    local y = tostring(year or 2026)
    local n = tostring(nonce or math.random(1000, 9999))
    return string.format("election:%s_%s_%s", cleanOffice, y, n)
end
