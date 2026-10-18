--[[
    Nyxframework: nyx_press
    File: shared/press.lua
    Description: Pure Lua 5.4 domain logic for printing circulation economics,
                 retail revenue split conservation, cryptographic whistleblower anonymity,
                 trade union media accreditation, and state machine transition rules.
]]

Nyx = Nyx or {}
Nyx.Press = Nyx.Press or {}

-- ----------------------------------------------------------------------------
-- 1. Pure Lua 5.4 Cryptographic SHA-256 Engine
-- ----------------------------------------------------------------------------
local band = function(a, b) return a & b end
local bor = function(a, b) return a | b end
local bxor = function(a, b) return a ~ b end
local bnot = function(a) return ~a & 0xFFFFFFFF end
local rshift = function(a, b) return (a & 0xFFFFFFFF) >> b end
local lshift = function(a, b) return (a << b) & 0xFFFFFFFF end

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

local function sha256(str)
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

Nyx.Press.SHA256 = sha256

-- Constant-time string equality check to prevent timing analysis attacks
local function constantTimeEquals(a, b)
    if type(a) ~= "string" or type(b) ~= "string" then return false end
    if #a ~= #b then return false end
    local diff = 0
    for i = 1, #a do
        diff = diff | (a:byte(i) ~ b:byte(i))
    end
    return diff == 0
end

Nyx.Press.ConstantTimeEquals = constantTimeEquals

-- ----------------------------------------------------------------------------
-- 2. Printing Press Circulation Cost Formulation
-- ----------------------------------------------------------------------------
-- Computes the production expense for physical newspapers:
-- C_print = N_copies * (BaseCost + PageFactor * (ceil(ContentLen / 500) - 1)) + Overhead
function Nyx.Press.CalculatePrintingCost(copies, contentLen, baseCost, pageFactor, overhead)
    local n = math.floor(tonumber(copies) or 0)
    if n <= 0 then
        return 0.00, 0.00, 1
    end

    local len = math.max(0, tonumber(contentLen) or 0)
    local lengthTier = math.max(1, math.ceil(len / 500))
    local bCost = math.max(0.00, tonumber(baseCost) or 2.00)
    local pFactor = math.max(0.00, tonumber(pageFactor) or 0.50)
    local mOverhead = math.max(0.00, tonumber(overhead) or 25.00)

    local unitCost = math.floor((bCost + (pFactor * (lengthTier - 1))) * 100) / 100
    local gross = (n * unitCost) + mOverhead
    local totalCost = math.floor(gross * 100) / 100

    return totalCost, unitCost, lengthTier
end

-- ----------------------------------------------------------------------------
-- 3. Retail Newsstand Sales Revenue Split (Conserved Zero Cent Leakage)
-- ----------------------------------------------------------------------------
-- Enforces closed-loop economic conservation: PublisherShare + MuniTaxShare == TotalCoverPrice
function Nyx.Press.CalculateSaleRevenueSplit(coverPrice, publisherSplitRatio)
    local price = math.max(0.00, math.floor((tonumber(coverPrice) or 10.00) * 100) / 100)
    if price <= 0.00 then
        return 0.00, 0.00, 0.00
    end

    local ratio = tonumber(publisherSplitRatio) or 0.75
    if ratio < 0.00 then ratio = 0.00 end
    if ratio > 1.00 then ratio = 1.00 end

    local publisherShare = math.floor((price * ratio) * 100) / 100
    local muniShare = math.floor((price - publisherShare) * 100) / 100

    -- Strict sanity invariant check
    local sum = math.floor((publisherShare + muniShare) * 100) / 100
    if sum ~= price then
        local delta = price - sum
        publisherShare = publisherShare + delta
    end

    return publisherShare, muniShare, price
end

-- ----------------------------------------------------------------------------
-- 4. Cryptographic Whistleblower Source Identity & Anonymity
-- ----------------------------------------------------------------------------
-- Generates a zero-knowledge source hash: SHA-256(citizenId .. ":" .. salt .. ":" .. nonce)
function Nyx.Press.GenerateSourceHash(citizenId, salt, nonce)
    local cId = tostring(citizenId or "anonymous")
    local s = tostring(salt or "press_salt")
    local n = tostring(nonce or "press_nonce")
    local payload = string.format("%s:%s:%s", cId, s, n)
    return sha256(payload)
end

-- Validates source identity with constant-time verification
function Nyx.Press.VerifySourceIdentity(expectedHash, citizenId, salt, nonce)
    if not expectedHash or not citizenId or not salt or not nonce then
        return false
    end
    local computed = Nyx.Press.GenerateSourceHash(citizenId, salt, nonce)
    return constantTimeEquals(expectedHash, computed)
end

-- ----------------------------------------------------------------------------
-- 5. Trade Union Media Accreditation Evaluator
-- ----------------------------------------------------------------------------
-- Checks if an investigative journalist holds valid trade union credentials or media leadership
function Nyx.Press.EvaluateMediaAccreditation(unionMembership, factionMembership)
    -- Priority 1: Trade Union Membership (Press Guild)
    if unionMembership and type(unionMembership) == "table" then
        local uId = tostring(unionMembership.unionId or "")
        local isPressUnion = (uId == "union:press_guild") or (string.find(uId, "press") ~= nil) or (string.find(uId, "media") ~= nil)
        local standing = tostring(unionMembership.standing or "")
        local isGoodStanding = (standing == "good_standing")

        local allowedRoles = { ['steward'] = true, ['delegate'] = true, ['member'] = true }
        local role = tostring(unionMembership.role or "member")

        if isPressUnion and isGoodStanding and allowedRoles[role] then
            return true, "TRADE_UNION_ACCREDITED"
        end
    end

    -- Priority 2: Registered Media Corporate Charter Leadership
    if factionMembership and type(factionMembership) == "table" then
        local fId = tostring(factionMembership.factionId or "")
        local isMediaFaction = (string.sub(fId, 1, 6) == "press:") or (string.find(fId, "media") ~= nil) or (string.find(fId, "news") ~= nil)
        local isLeader = (factionMembership.isLeader == true) or (factionMembership.roleTitle == "CEO") or (factionMembership.roleTitle == "Editor-in-Chief")

        if isMediaFaction and isLeader then
            return true, "MEDIA_CHARTER_LEADERSHIP_ACCREDITED"
        end
    end

    return false, "UNACCREDITED_MEDIA_PERSONNEL"
end

-- ----------------------------------------------------------------------------
-- 6. Publication Article Validator
-- ----------------------------------------------------------------------------
local VALID_CATEGORIES = {
    ['investigative'] = true,
    ['business'] = true,
    ['politics'] = true,
    ['whistleblower'] = true,
    ['general'] = true
}

function Nyx.Press.ValidateArticle(article)
    if not article or type(article) ~= "table" then
        return false, "MISSING_ARTICLE_DATA"
    end

    local headline = tostring(article.headline or "")
    if #headline < 5 or #headline > 255 then
        return false, "INVALID_HEADLINE_LENGTH"
    end

    local category = tostring(article.category or "")
    if not VALID_CATEGORIES[category] then
        return false, "INVALID_ARTICLE_CATEGORY"
    end

    local byline = tostring(article.authorByline or "")
    if #byline < 2 or #byline > 96 then
        return false, "INVALID_BYLINE_LENGTH"
    end

    local content = tostring(article.content or "")
    if #content < 20 or #content > 100000 then
        return false, "INVALID_CONTENT_LENGTH"
    end

    return true, "VALID"
end

-- ----------------------------------------------------------------------------
-- 7. State Machine Transition Evaluators
-- ----------------------------------------------------------------------------
local PUBLICATION_TRANSITIONS = {
    ['draft'] = { ['published'] = true },
    ['published'] = { ['retracted'] = true },
    ['retracted'] = {} -- Terminal state
}

function Nyx.Press.CanTransitionPublication(currentStatus, nextStatus)
    if not currentStatus or not nextStatus then return false end
    if currentStatus == nextStatus then return true end
    local allowed = PUBLICATION_TRANSITIONS[currentStatus]
    return (allowed and allowed[nextStatus] == true) or false
end

local LEAK_TRANSITIONS = {
    ['unclaimed'] = { ['under_investigation'] = true },
    ['under_investigation'] = { ['published'] = true, ['quashed'] = true },
    ['published'] = {}, -- Terminal state
    ['quashed'] = {}    -- Terminal state
}

function Nyx.Press.CanTransitionLeak(currentStatus, nextStatus)
    if not currentStatus or not nextStatus then return false end
    if currentStatus == nextStatus then return true end
    local allowed = LEAK_TRANSITIONS[currentStatus]
    return (allowed and allowed[nextStatus] == true) or false
end
