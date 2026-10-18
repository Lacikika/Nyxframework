--[[
    Nyxframework: nyx_judiciary
    File: shared/courtroom_ui.lua
    Description: Pure Lua 5.4 algorithms for the Courtroom Terminal & Forensic Explorer UI:
                 SHA-256 evidence chain verification, explorer search filters, warrant taxonomy badges,
                 jury voting state evaluator, and warrant issuance validation.
]]

Nyx = Nyx or {}
Nyx.CourtroomUI = Nyx.CourtroomUI or {}

-- ----------------------------------------------------------------------------
-- 1. Pure Lua 5.4 SHA-256 Engine (Zero Dependency)
-- ----------------------------------------------------------------------------
local band, bor, bxor, bnot = function(a, b) return a & b end, function(a, b) return a | b end, function(a, b) return a ~ b end, function(a) return ~a & 0xFFFFFFFF end
local rshift, lshift = function(a, b) return (a & 0xFFFFFFFF) >> b end, function(a, b) return (a << b) & 0xFFFFFFFF end

local function ror(x, n)
    return (rshift(x, n) | lshift(x, 32 - n)) & 0xFFFFFFFF
end

local K = {
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2
}

local function computeSHA256(str)
    if type(str) ~= "string" then str = tostring(str or "") end
    local H = {
        0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
        0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19
    }

    local len = #str
    local bit_len = len * 8
    local pad = { str:byte(1, len) }
    pad[#pad + 1] = 0x80
    while (#pad % 64) ~= 56 do
        pad[#pad + 1] = 0x00
    end

    for i = 7, 0, -1 do
        pad[#pad + 1] = (bit_len >> (i * 8)) & 0xFF
    end

    local W = {}
    for chunk = 1, #pad, 64 do
        for t = 0, 15 do
            local idx = chunk + t * 4
            W[t] = (lshift(pad[idx], 24) | lshift(pad[idx + 1], 16) | lshift(pad[idx + 2], 8) | pad[idx + 3]) & 0xFFFFFFFF
        end
        for t = 16, 63 do
            local s0 = bxor(bxor(ror(W[t - 15], 7), ror(W[t - 15], 18)), rshift(W[t - 15], 3))
            local s1 = bxor(bxor(ror(W[t - 2], 17), ror(W[t - 2], 19)), rshift(W[t - 2], 10))
            W[t] = (W[t - 16] + s0 + W[t - 7] + s1) & 0xFFFFFFFF
        end

        local a, b, c, d, e, f, g, h = H[1], H[2], H[3], H[4], H[5], H[6], H[7], H[8]

        for t = 0, 63 do
            local S1 = bxor(bxor(ror(e, 6), ror(e, 11)), ror(e, 25))
            local ch = bxor(band(e, f), band(bnot(e), g))
            local temp1 = (h + S1 + ch + K[t + 1] + W[t]) & 0xFFFFFFFF
            local S0 = bxor(bxor(ror(a, 2), ror(a, 13)), ror(a, 22))
            local maj = bxor(bxor(band(a, b), band(a, c)), band(b, c))
            local temp2 = (S0 + maj) & 0xFFFFFFFF

            h = g
            g = f
            f = e
            e = (d + temp1) & 0xFFFFFFFF
            d = c
            c = b
            b = a
            a = (temp1 + temp2) & 0xFFFFFFFF
        end

        H[1] = (H[1] + a) & 0xFFFFFFFF
        H[2] = (H[2] + b) & 0xFFFFFFFF
        H[3] = (H[3] + c) & 0xFFFFFFFF
        H[4] = (H[4] + d) & 0xFFFFFFFF
        H[5] = (H[5] + e) & 0xFFFFFFFF
        H[6] = (H[6] + f) & 0xFFFFFFFF
        H[7] = (H[7] + g) & 0xFFFFFFFF
        H[8] = (H[8] + h) & 0xFFFFFFFF
    end

    return string.format("%08x%08x%08x%08x%08x%08x%08x%08x",
        H[1], H[2], H[3], H[4], H[5], H[6], H[7], H[8])
end

Nyx.CourtroomUI.SHA256 = computeSHA256

-- ----------------------------------------------------------------------------
-- 2. Evidence Integrity & Chain-of-Custody Evaluator
-- ----------------------------------------------------------------------------
--- Evaluates cryptographic continuity of an evidence record and its custody chain blocks.
--- @param evidenceRecord table Base evidence row { evidence_id, evidence_hash, current_chain_hash, chain_length, ... }
--- @param chainBlocks table Array of custody log rows ordered by sequence_id ASC
--- @return boolean isValid, string status, table details
function Nyx.CourtroomUI.EvaluateEvidenceIntegrity(evidenceRecord, chainBlocks)
    if not evidenceRecord or type(evidenceRecord) ~= "table" then
        return false, "INVALID_RECORD", { error = "Evidence record must be a table" }
    end

    chainBlocks = chainBlocks or {}

    local rootHash = evidenceRecord.evidence_hash or evidenceRecord.evidenceHash
    if not rootHash or string.len(rootHash) ~= 64 then
        return false, "INVALID_ROOT_HASH", { error = "Root evidence hash is missing or invalid SHA-256" }
    end

    local headHash = evidenceRecord.current_chain_hash or evidenceRecord.currentChainHash or rootHash
    local reportedLength = tonumber(evidenceRecord.chain_length or evidenceRecord.chainLength or 0)
    local actualLength = #chainBlocks

    -- If no blocks recorded yet, root hash must match head hash
    if actualLength == 0 then
        if reportedLength == 0 and (headHash == rootHash or headHash == nil) then
            return true, "EMPTY_CHAIN_VALID", {
                evidenceId = evidenceRecord.evidence_id or evidenceRecord.evidenceId,
                verifiedBlocks = 0,
                rootHash = rootHash,
                headHash = rootHash,
                isSealed = (evidenceRecord.is_sealed == 1 or evidenceRecord.is_sealed == true),
                isContaminated = (evidenceRecord.is_contaminated == 1 or evidenceRecord.is_contaminated == true)
            }
        else
            return false, "CHAIN_LENGTH_MISMATCH", {
                reportedLength = reportedLength,
                actualBlocks = actualLength
            }
        end
    end

    local prevExpected = rootHash
    for i, block in ipairs(chainBlocks) do
        local seq = tonumber(block.sequence_id or block.sequenceId or i)
        if seq ~= i then
            return false, "SEQUENCE_GAP_DETECTED", {
                expectedSequence = i,
                actualSequence = seq,
                blockIndex = i
            }
        end

        local blockPrev = block.previous_hash or block.previousHash
        if blockPrev ~= prevExpected then
            return false, "CHAIN_HASH_DISCONTINUITY", {
                sequence = seq,
                expectedPreviousHash = prevExpected,
                actualPreviousHash = blockPrev
            }
        end

        local entryHash = block.entry_hash or block.entryHash
        if not entryHash or string.len(entryHash) ~= 64 then
            return false, "INVALID_ENTRY_HASH", {
                sequence = seq,
                entryHash = entryHash
            }
        end

        prevExpected = entryHash
    end

    -- Verify the parent record's current_chain_hash matches the final block's entry_hash
    local latestBlockHash = chainBlocks[#chainBlocks].entry_hash or chainBlocks[#chainBlocks].entryHash
    if headHash and headHash ~= "" and headHash ~= latestBlockHash then
        return false, "CHAIN_HEAD_MISMATCH", {
            parentHeadHash = headHash,
            latestBlockHash = latestBlockHash
        }
    end

    return true, "CHAIN_VERIFIED_AUTHENTIC", {
        evidenceId = evidenceRecord.evidence_id or evidenceRecord.evidenceId,
        verifiedBlocks = actualLength,
        rootHash = rootHash,
        headHash = latestBlockHash,
        isSealed = (evidenceRecord.is_sealed == 1 or evidenceRecord.is_sealed == true),
        isContaminated = (evidenceRecord.is_contaminated == 1 or evidenceRecord.is_contaminated == true),
        currentCustodian = evidenceRecord.current_custodian_id or evidenceRecord.currentCustodianId,
        currentFacility = evidenceRecord.current_facility or evidenceRecord.currentFacility
    }
end

-- ----------------------------------------------------------------------------
-- 3. Evidence Explorer Filtering Algorithm
-- ----------------------------------------------------------------------------
--- Filters a collection of evidence items based on search string, type, and sealed status.
--- @param evidenceList table Array of evidence objects
--- @param searchFilter string|nil Case-insensitive search query
--- @param typeFilter string|nil Case type or "all"
--- @param isSealedOnly boolean|nil Filter for sealed evidence only
--- @return table filteredList
function Nyx.CourtroomUI.FilterEvidenceExplorer(evidenceList, searchFilter, typeFilter, isSealedOnly)
    if not evidenceList or type(evidenceList) ~= "table" then return {} end

    local query = searchFilter and string.lower(string.gsub(searchFilter, "^%s*(.-)%s*$", "%1")) or ""
    local typeCheck = (typeFilter and typeFilter ~= "all" and typeFilter ~= "") and string.lower(typeFilter) or nil
    local sealedOnly = (isSealedOnly == true or isSealedOnly == 1)

    local filtered = {}
    for _, item in ipairs(evidenceList) do
        local matchType = true
        if typeCheck then
            local itType = string.lower(item.type or "")
            if itType ~= typeCheck then matchType = false end
        end

        local matchSealed = true
        if sealedOnly then
            local isSealed = (item.is_sealed == 1 or item.is_sealed == true)
            if not isSealed then matchSealed = false end
        end

        local matchQuery = true
        if query ~= "" then
            local evId = string.lower(item.evidence_id or item.evidenceId or "")
            local evHash = string.lower(item.evidence_hash or item.evidenceHash or "")
            local cust = string.lower(item.current_custodian_id or item.currentCustodianId or "")
            local col = string.lower(item.collector_citizen_id or item.collectorCitizenId or "")
            local doc = string.lower(item.docket_id or item.docketId or "")
            local exh = string.lower(item.exhibit_label or item.exhibitLabel or "")
            local itType = string.lower(item.type or "")

            if not (string.find(evId, query, 1, true) or
                    string.find(evHash, query, 1, true) or
                    string.find(cust, query, 1, true) or
                    string.find(col, query, 1, true) or
                    string.find(doc, query, 1, true) or
                    string.find(exh, query, 1, true) or
                    string.find(itType, query, 1, true)) then
                matchQuery = false
            end
        end

        if matchType and matchSealed and matchQuery then
            table.insert(filtered, item)
        end
    end

    return filtered
end

-- ----------------------------------------------------------------------------
-- 4. Warrant & Subpoena Presentation Badges
-- ----------------------------------------------------------------------------
local WARRANT_TAXONOMY = {
    arrest = {
        label = "Arrest Warrant",
        badgeClass = "badge-danger",
        colorHex = "#EF4444",
        icon = "fa-handcuffs",
        description = "Probable cause warrant authorizing detention of suspect"
    },
    search_property = {
        label = "Property Search",
        badgeClass = "badge-info",
        colorHex = "#3B82F6",
        icon = "fa-house-lock",
        description = "Judicial search warrant for residential or commercial real estate"
    },
    search_vehicle = {
        label = "Vehicle Search",
        badgeClass = "badge-cyan",
        colorHex = "#06B6D4",
        icon = "fa-car-side",
        description = "Warrant authorizing impound inspection and forensic swab of vehicle"
    },
    subpoena = {
        label = "Financial Subpoena",
        badgeClass = "badge-warning",
        colorHex = "#F59E0B",
        icon = "fa-file-invoice-dollar",
        description = "Judicial subpoena commanding disclosure of financial & corporate ledgers"
    },
    wiretap = {
        label = "Cellular Wiretap",
        badgeClass = "badge-purple",
        colorHex = "#8B5CF6",
        icon = "fa-tower-broadcast",
        description = "Triangulated surveillance authorization feeding MDT tactical tracking"
    }
}

--- Formats warrant type and status into structured UI badges.
--- @param warrantType string Type of warrant
--- @param status string Lifecycle status
--- @return table formatted
function Nyx.CourtroomUI.FormatWarrantBadge(warrantType, status)
    local wType = warrantType and string.lower(warrantType) or "arrest"
    local st = status and string.lower(status) or "active"

    local typeMeta = WARRANT_TAXONOMY[wType] or {
        label = "Judicial Order",
        badgeClass = "badge-secondary",
        colorHex = "#64748B",
        icon = "fa-gavel",
        description = "General judicial council writ"
    }

    local statusMeta = {
        active = { label = "ACTIVE", badgeClass = "badge-success", colorHex = "#10B981" },
        pending_review = { label = "PENDING REVIEW", badgeClass = "badge-warning", colorHex = "#F59E0B" },
        approved = { label = "APPROVED", badgeClass = "badge-success", colorHex = "#10B981" },
        rejected = { label = "REJECTED", badgeClass = "badge-danger", colorHex = "#EF4444" },
        executed = { label = "EXECUTED", badgeClass = "badge-info", colorHex = "#3B82F6" },
        rescinded = { label = "RESCINDED", badgeClass = "badge-secondary", colorHex = "#64748B" },
        expired = { label = "EXPIRED", badgeClass = "badge-neutral", colorHex = "#475569" }
    }

    local stData = statusMeta[st] or { label = string.upper(st), badgeClass = "badge-secondary", colorHex = "#64748B" }

    return {
        type = wType,
        typeLabel = typeMeta.label,
        typeBadgeClass = typeMeta.badgeClass,
        typeColor = typeMeta.colorHex,
        typeIcon = typeMeta.icon,
        description = typeMeta.description,
        status = st,
        statusLabel = stData.label,
        statusBadgeClass = stData.badgeClass,
        statusColor = stData.colorHex
    }
end

-- ----------------------------------------------------------------------------
-- 5. Jury Terminal State Evaluator
-- ----------------------------------------------------------------------------
--- Evaluates juror and courtroom terminal interactive permissions.
--- @param docket table Docket data { docket_id, status, ... }
--- @param jurorRecord table|nil Citizen's juror record { selection_status, seat_index, secret_ballot }
--- @param allJurors table|nil Array of all juror records for the case
--- @return table state
function Nyx.CourtroomUI.EvaluateJuryTerminalState(docket, jurorRecord, allJurors)
    docket = docket or {}
    allJurors = allJurors or {}

    local docketStatus = docket.status or "filed"
    local isSummoned = false
    local isSeated = false
    local hasVoted = false
    local canVote = false
    local seatIndex = nil

    if jurorRecord and type(jurorRecord) == "table" then
        local selStatus = jurorRecord.selection_status or jurorRecord.selectionStatus
        seatIndex = jurorRecord.seat_index or jurorRecord.seatIndex
        isSummoned = (selStatus == "summoned")
        isSeated = (selStatus == "seated" or selStatus == "deliberating" or selStatus == "voted")
        hasVoted = (jurorRecord.secret_ballot ~= nil or selStatus == "voted")

        if (docketStatus == "deliberation" or docketStatus == "in_trial") and isSeated and not hasVoted then
            canVote = true
        end
    end

    local seatedCount = 0
    local votedCount = 0
    for _, j in ipairs(allJurors) do
        local st = j.selection_status or j.selectionStatus
        if st == "seated" or st == "deliberating" or st == "voted" then
            seatedCount = seatedCount + 1
        end
        if j.secret_ballot ~= nil or st == "voted" then
            votedCount = votedCount + 1
        end
    end

    local minQuorum = tonumber(docket.minQuorum) or 3
    local isQuorumMet = (seatedCount >= minQuorum)

    return {
        docketId = docket.docket_id or docket.docketId,
        docketStatus = docketStatus,
        isSummoned = isSummoned,
        isSeated = isSeated,
        seatIndex = seatIndex,
        hasVoted = hasVoted,
        canVote = canVote,
        seatedCount = seatedCount,
        votedCount = votedCount,
        totalJurors = #allJurors,
        minQuorum = minQuorum,
        isQuorumMet = isQuorumMet,
        isInDeliberation = (docketStatus == "deliberation")
    }
end

-- ----------------------------------------------------------------------------
-- 6. Probable Cause Warrant Issuance Payload Validator
-- ----------------------------------------------------------------------------
local VALID_WARRANT_TYPES = {
    arrest = true,
    search_property = true,
    search_vehicle = true,
    subpoena = true,
    wiretap = true
}

local VALID_SUBPOENA_SCOPES = {
    all = true,
    financial = true,
    property = true,
    telecom = true
}

--- Validates and sanitizes warrant issuance payloads from UI.
--- @param payload table Raw form payload
--- @return boolean isValid, table sanitized, string|nil errorMessage
function Nyx.CourtroomUI.ValidateWarrantIssuancePayload(payload)
    if not payload or type(payload) ~= "table" then
        return false, nil, "PAYLOAD_MUST_BE_TABLE"
    end

    local targetCitId = payload.targetCitizenId or payload.targetCitizen_id
    if not targetCitId or type(targetCitId) ~= "string" or string.len(targetCitId) < 3 then
        return false, nil, "INVALID_TARGET_CITIZEN_ID"
    end
    targetCitId = string.sub(string.gsub(targetCitId, "^%s*(.-)%s*$", "%1"), 1, 64)

    local wType = payload.warrantType or payload.type
    if not wType or not VALID_WARRANT_TYPES[string.lower(wType)] then
        return false, nil, "INVALID_WARRANT_TYPE"
    end
    wType = string.lower(wType)

    local causeSummary = payload.probableCauseSummary or payload.causeSummary or payload.narrative
    if not causeSummary or type(causeSummary) ~= "string" or string.len(string.gsub(causeSummary, "^%s*(.-)%s*$", "%1")) < 20 then
        return false, nil, "PROBABLE_CAUSE_NARRATIVE_MIN_20_CHARS"
    end
    causeSummary = string.sub(string.gsub(causeSummary, "^%s*(.-)%s*$", "%1"), 1, 4096)

    local duration = tonumber(payload.requestedDurationHours or payload.durationHours or 72) or 72
    if duration < 1 or duration > 336 then
        return false, nil, "DURATION_HOURS_OUT_OF_BOUNDS_1_TO_336"
    end
    duration = math.floor(duration)

    local subpoenaScope = nil
    if wType == "subpoena" then
        local scope = payload.subpoenaScope and string.lower(payload.subpoenaScope) or "financial"
        if not VALID_SUBPOENA_SCOPES[scope] then
            return false, nil, "INVALID_SUBPOENA_SCOPE"
        end
        subpoenaScope = scope
    end

    local targetEntityId = payload.targetEntityId and string.sub(string.gsub(payload.targetEntityId, "^%s*(.-)%s*$", "%1"), 1, 64) or nil

    return true, {
        targetCitizenId = targetCitId,
        warrantType = wType,
        probableCauseSummary = causeSummary,
        requestedDurationHours = duration,
        subpoenaScope = subpoenaScope,
        targetEntityId = targetEntityId
    }, nil
end
