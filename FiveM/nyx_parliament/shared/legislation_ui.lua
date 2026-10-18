--[[
    Nyxframework: nyx_parliament
    File: shared/legislation_ui.lua
    Description: Pure Lua 5.4 algorithms for Parliamentary Ranked-Choice Voting & Legislation UI:
                 candidate payload validation, endorsement threshold state machine, bill formulation
                 statutory checks, penal code filtering, statute badges, and receipt formatting.
]]

Nyx = Nyx or {}
Nyx.ParliamentUI = Nyx.ParliamentUI or {}

-- ----------------------------------------------------------------------------
-- 1. Candidate Registration Payload Validator
-- ----------------------------------------------------------------------------
function Nyx.ParliamentUI.ValidateCandidatePayload(payload)
    if type(payload) ~= "table" then
        return false, nil, "INVALID_PAYLOAD"
    end

    local name = payload.displayName
    if type(name) ~= "string" or #string.gsub(name, "%s+", "") < 3 then
        return false, nil, "NAME_TOO_SHORT"
    end
    if #name > 64 then
        return false, nil, "NAME_TOO_LONG"
    end

    local party = payload.party
    if not party or #party == 0 then
        party = "Independent"
    end
    if type(party) ~= "string" or #party > 64 then
        return false, nil, "PARTY_TOO_LONG"
    end

    local platform = payload.platform
    if type(platform) ~= "string" or #string.gsub(platform, "%s+", "") < 10 then
        return false, nil, "PLATFORM_TOO_SHORT"
    end
    if #platform > 1024 then
        return false, nil, "PLATFORM_TOO_LONG"
    end

    local slogan = payload.slogan or ""
    if type(slogan) == "string" and #slogan > 128 then
        return false, nil, "SLOGAN_TOO_LONG"
    end

    local sanitized = {
        displayName = string.gsub(name, "^%s*(.-)%s*$", "%1"),
        party = string.gsub(party, "^%s*(.-)%s*$", "%1"),
        platform = string.gsub(platform, "^%s*(.-)%s*$", "%1"),
        slogan = string.gsub(tostring(slogan or ""), "^%s*(.-)%s*$", "%1")
    }

    return true, sanitized, nil
end

-- ----------------------------------------------------------------------------
-- 2. Candidate Endorsement & Threshold State Machine
-- ----------------------------------------------------------------------------
function Nyx.ParliamentUI.ValidateEndorsement(candidate, citizenId, requiredEndorsements)
    if type(candidate) ~= "table" then
        return false, "INVALID_CANDIDATE"
    end

    local candCitId = candidate.citizen_id or candidate.citizenId
    if candCitId == citizenId then
        return false, "CANNOT_ENDORSE_SELF"
    end

    local status = candidate.status or "nominated"
    if status == "disqualified" or status == "withdrawn" then
        return false, "CANDIDATE_NOT_ACTIVE"
    end

    local currentCount = tonumber(candidate.endorsements_count) or 0
    local req = math.max(1, tonumber(requiredEndorsements) or 3)
    local newCount = currentCount + 1
    local progressPercent = math.min(100.0, math.floor(((newCount / req) * 100.0) + 0.5))
    local willQualify = (newCount >= req)

    return true, {
        newCount = newCount,
        required = req,
        progressPercent = progressPercent,
        willQualify = willQualify
    }
end

-- ----------------------------------------------------------------------------
-- 3. Bill Proposal & Statutory Bound Validator
-- ----------------------------------------------------------------------------
function Nyx.ParliamentUI.ValidateBillProposal(payload, statutesCatalog)
    if type(payload) ~= "table" then
        return false, nil, "INVALID_PAYLOAD"
    end

    local title = payload.title
    if type(title) ~= "string" or #string.gsub(title, "%s+", "") < 5 or #title > 96 then
        return false, nil, "INVALID_TITLE_LENGTH"
    end

    local description = payload.description or ""
    if type(description) ~= "string" or #string.gsub(description, "%s+", "") < 10 or #description > 1024 then
        return false, nil, "INVALID_DESCRIPTION_LENGTH"
    end

    local actions = payload.actions
    if type(actions) ~= "table" or #actions == 0 then
        return false, nil, "INVALID_ACTIONS"
    end
    if #actions > 10 then
        return false, nil, "TOO_MANY_ACTIONS"
    end

    local sanitizedActions = {}
    for idx, act in ipairs(actions) do
        if type(act) ~= "table" then
            return false, nil, string.format("MALFORMED_ACTION_%d", idx)
        end

        local lawId = act.targetLawId
        local field = act.field
        local newVal = tonumber(act.newValue)

        if not lawId or not field or newVal == nil then
            return false, nil, string.format("MALFORMED_ACTION_%d", idx)
        end

        if statutesCatalog and statutesCatalog[lawId] then
            local lawDef = statutesCatalog[lawId]
            local minVal = lawDef.min_allowed and tonumber(lawDef.min_allowed[field]) or (lawDef.minAllowed and tonumber(lawDef.minAllowed[field]))
            local maxVal = lawDef.max_allowed and tonumber(lawDef.max_allowed[field]) or (lawDef.maxAllowed and tonumber(lawDef.maxAllowed[field]))

            if minVal and newVal < minVal then
                return false, nil, string.format("STATUTORY_MINIMUM_VIOLATION:%s.%s", lawId, field)
            end
            if maxVal and newVal > maxVal then
                return false, nil, string.format("STATUTORY_MAXIMUM_VIOLATION:%s.%s", lawId, field)
            end
        end

        sanitizedActions[#sanitizedActions + 1] = {
            targetLawId = tostring(lawId),
            field = tostring(field),
            newValue = newVal
        }
    end

    return true, {
        title = string.gsub(title, "^%s*(.-)%s*$", "%1"),
        description = string.gsub(description, "^%s*(.-)%s*$", "%1"),
        actions = sanitizedActions
    }, nil
end

-- ----------------------------------------------------------------------------
-- 4. Penal Code & Statute Filter
-- ----------------------------------------------------------------------------
function Nyx.ParliamentUI.FilterPenalCode(penalList, query, categoryFilter)
    if type(penalList) ~= "table" then
        return {}, { total = 0, felonies = 0, misdemeanors = 0, infractions = 0, fiscal = 0 }
    end

    local q = query and string.lower(string.gsub(query, "^%s*(.-)%s*$", "%1")) or ""
    local cat = categoryFilter and string.lower(string.gsub(categoryFilter, "^%s*(.-)%s*$", "%1")) or "all"

    local filtered = {}
    local counts = { total = #penalList, felonies = 0, misdemeanors = 0, infractions = 0, fiscal = 0 }

    for _, item in ipairs(penalList) do
        local itemCat = string.lower(item.category or "")
        local itemTitle = string.lower(item.title or "")
        local itemId = string.lower(item.id or "")

        if itemCat == "penal_felony" then
            counts.felonies = counts.felonies + 1
        elseif itemCat == "penal_misdemeanor" then
            counts.misdemeanors = counts.misdemeanors + 1
        elseif itemCat == "penal_infraction" then
            counts.infractions = counts.infractions + 1
        elseif itemCat == "fiscal_policy" then
            counts.fiscal = counts.fiscal + 1
        end

        local catMatch = (cat == "all") or (itemCat == cat)
        local queryMatch = (#q == 0) or string.find(itemTitle, q, 1, true) ~= nil or string.find(itemId, q, 1, true) ~= nil

        if catMatch and queryMatch then
            filtered[#filtered + 1] = item
        end
    end

    return filtered, counts
end

-- ----------------------------------------------------------------------------
-- 5. Statute Taxonomy Badge Formatter
-- ----------------------------------------------------------------------------
function Nyx.ParliamentUI.FormatStatuteBadge(category)
    local cat = string.lower(category or "")
    if cat == "penal_felony" then
        return { label = "Bűntett (Felony)", badgeClass = "badge-danger", icon = "fa-solid fa-gavel" }
    elseif cat == "penal_misdemeanor" then
        return { label = "Vétség (Misdemeanor)", badgeClass = "badge-warning", icon = "fa-solid fa-triangle-exclamation" }
    elseif cat == "penal_infraction" then
        return { label = "Szabálysértés (Infraction)", badgeClass = "badge-info", icon = "fa-solid fa-ticket" }
    elseif cat == "fiscal_policy" then
        return { label = "Közpénzügy (Fiscal)", badgeClass = "badge-primary", icon = "fa-solid fa-coins" }
    elseif cat == "zoning" then
        return { label = "Területrendezés (Zoning)", badgeClass = "badge-secondary", icon = "fa-solid fa-city" }
    end
    return { label = "Általános Törvény", badgeClass = "badge-outline", icon = "fa-solid fa-landmark" }
end

-- ----------------------------------------------------------------------------
-- 6. Ballot Receipt Formatter & Verification
-- ----------------------------------------------------------------------------
function Nyx.ParliamentUI.FormatBallotReceipt(receiptHash, timestamp, sessionId)
    if type(receiptHash) ~= "string" then
        return { receiptHash = "", isValidFormat = false }
    end

    local isValid = (string.match(receiptHash, "^NYX%-BALLOT%-[%w%-_]+$") ~= nil)
    return {
        receiptHash = receiptHash,
        sessionId = sessionId or "",
        timestamp = timestamp or "2026-10-18T10:00:00Z",
        isValidFormat = isValid
    }
end

-- ----------------------------------------------------------------------------
-- 7. Ballot Preference Ranking & Completeness Evaluator
-- ----------------------------------------------------------------------------
function Nyx.ParliamentUI.EvaluateBallotPreferences(preferences, availableCandidates)
    local totalAvail = type(availableCandidates) == "table" and #availableCandidates or 0
    if type(preferences) ~= "table" then
        return {}, { rankedCount = 0, totalAvailable = totalAvail, isComplete = false }
    end

    local allowed = {}
    if type(availableCandidates) == "table" then
        for _, c in ipairs(availableCandidates) do
            local cid = type(c) == "table" and (c.id or c.candidate_id or c.candidateId) or tostring(c)
            allowed[cid] = true
        end
    end

    local seen = {}
    local clean = {}

    for _, p in ipairs(preferences) do
        local pid = tostring(p)
        if allowed[pid] and not seen[pid] then
            seen[pid] = true
            clean[#clean + 1] = pid
        end
    end

    local rankedCnt = #clean
    return clean, {
        rankedCount = rankedCnt,
        totalAvailable = totalAvail,
        isComplete = (rankedCnt == totalAvail and totalAvail > 0)
    }
end
