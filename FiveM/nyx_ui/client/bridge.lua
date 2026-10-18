--[[
    Nyxframework: nyx_ui
    File: client/bridge.lua
    Description: Standardized NUI message envelope dispatcher, inbound callback router,
                 and event bridging between native runtime and master SPA.
]]

Nyx = Nyx or {}
Nyx.UI = Nyx.UI or {}

-- 1. Standardized Outbound NUI Envelope Dispatcher
function Nyx.UI.Send(app, action, payload)
    SendNUIMessage({
        app = app or "generic",
        action = action or "DEFAULT",
        payload = payload or {}
    })
end

-- 2. Focus & Input Controller
function Nyx.UI.SetFocus(hasCursor, hasKeyboard)
    SetNuiFocus(hasCursor or false, hasKeyboard or false)
end

-- 3. Zero-Trust Intent Payload Sanitizer
function Nyx.UI.SanitizePayload(data)
    if type(data) ~= "table" then return {} end

    local sanitized = {}
    -- Whitelist allowed player intent parameters only (never trust client calculations)
    if data.app and type(data.app) == "string" then sanitized.app = string.sub(data.app, 1, 64) end
    if data.action and type(data.action) == "string" then sanitized.action = string.sub(data.action, 1, 64) end
    if data.actionType and type(data.actionType) == "string" then sanitized.actionType = string.sub(data.actionType, 1, 64) end
    if data.itemId and (type(data.itemId) == "string" or type(data.itemId) == "number") then
        sanitized.itemId = tostring(data.itemId)
    end
    if data.targetId and (type(data.targetId) == "string" or type(data.targetId) == "number") then
        sanitized.targetId = tostring(data.targetId)
    end
    if data.slot and type(data.slot) == "number" then
        sanitized.slot = math.max(1, math.min(1000, math.floor(data.slot)))
    end
    if data.amount and type(data.amount) == "number" then
        sanitized.amount = math.max(1, math.min(1000, math.floor(data.amount)))
    end
    if data.callId and (type(data.callId) == "string" or type(data.callId) == "number") then
        sanitized.callId = tonumber(data.callId) or tostring(data.callId)
    end
    if data.contractId and (type(data.contractId) == "string" or type(data.contractId) == "number") then
        sanitized.contractId = tonumber(data.contractId) or tostring(data.contractId)
    end
    if data.input and type(data.input) == "string" then
        sanitized.input = string.sub(data.input, 1, 256)
    end
    -- Corporate RBAC, Multi-Sig & Union parameters
    if data.factionId and type(data.factionId) == "string" then sanitized.factionId = string.sub(data.factionId, 1, 64) end
    if data.targetCitizenId and type(data.targetCitizenId) == "string" then sanitized.targetCitizenId = string.sub(data.targetCitizenId, 1, 64) end
    if data.roleTitle and type(data.roleTitle) == "string" then sanitized.roleTitle = string.sub(data.roleTitle, 1, 64) end
    if data.permissionNodes and type(data.permissionNodes) == "table" then sanitized.permissionNodes = data.permissionNodes end
    if data.equityShares and type(data.equityShares) == "number" then sanitized.equityShares = math.max(0.0, math.min(100.0, data.equityShares)) end
    if data.wageHourly and type(data.wageHourly) == "number" then sanitized.wageHourly = math.max(0.0, math.min(10000.0, data.wageHourly)) end
    if data.requestId and (type(data.requestId) == "string" or type(data.requestId) == "number") then sanitized.requestId = tostring(data.requestId) end
    if data.cbaId and type(data.cbaId) == "string" then sanitized.cbaId = string.sub(data.cbaId, 1, 64) end
    if data.unionId and type(data.unionId) == "string" then sanitized.unionId = string.sub(data.unionId, 1, 64) end
    if data.vaultId and type(data.vaultId) == "string" then sanitized.vaultId = string.sub(data.vaultId, 1, 64) end
    if data.reason and type(data.reason) == "string" then sanitized.reason = string.sub(data.reason, 1, 256) end
    if data.note and type(data.note) == "string" then sanitized.note = string.sub(data.note, 1, 256) end
    if data.vote and type(data.vote) == "string" then sanitized.vote = string.sub(data.vote, 1, 16) end
    if data.title and type(data.title) == "string" then sanitized.title = string.sub(data.title, 1, 64) end
    if data.wageFloor and type(data.wageFloor) == "number" then sanitized.wageFloor = data.wageFloor end
    if data.overtimeMultiplier and type(data.overtimeMultiplier) == "number" then sanitized.overtimeMultiplier = data.overtimeMultiplier end
    if data.hazardBonus and type(data.hazardBonus) == "number" then sanitized.hazardBonus = data.hazardBonus end
    if data.netProfit and type(data.netProfit) == "number" then sanitized.netProfit = data.netProfit end
    if data.rate and type(data.rate) == "number" then sanitized.rate = data.rate end
    if data.legalName and type(data.legalName) == "string" then sanitized.legalName = string.sub(data.legalName, 1, 64) end
    if data.charterType and type(data.charterType) == "string" then sanitized.charterType = string.sub(data.charterType, 1, 32) end
    if data.initialDeposit and type(data.initialDeposit) == "number" then sanitized.initialDeposit = data.initialDeposit end
    -- Courtroom Terminal, Forensics & Warrants parameters
    if data.evidenceId and (type(data.evidenceId) == "string" or type(data.evidenceId) == "number") then sanitized.evidenceId = tostring(data.evidenceId) end
    if data.warrantId and (type(data.warrantId) == "string" or type(data.warrantId) == "number") then sanitized.warrantId = tostring(data.warrantId) end
    if data.petitionId and (type(data.petitionId) == "string" or type(data.petitionId) == "number") then sanitized.petitionId = tostring(data.petitionId) end
    if data.decision and type(data.decision) == "string" then sanitized.decision = string.sub(data.decision, 1, 32) end
    if data.verdictRuling and type(data.verdictRuling) == "string" then sanitized.verdictRuling = string.sub(data.verdictRuling, 1, 64) end
    if data.docketId and type(data.docketId) == "string" then sanitized.docketId = string.sub(data.docketId, 1, 64) end
    if data.probableCauseSummary and type(data.probableCauseSummary) == "string" then sanitized.probableCauseSummary = string.sub(data.probableCauseSummary, 1, 4096) end
    if data.subpoenaScope and type(data.subpoenaScope) == "string" then sanitized.subpoenaScope = string.sub(data.subpoenaScope, 1, 32) end
    if data.warrantType and type(data.warrantType) == "string" then sanitized.warrantType = string.sub(data.warrantType, 1, 32) end
    if data.filterQuery and type(data.filterQuery) == "string" then sanitized.filterQuery = string.sub(data.filterQuery, 1, 128) end
    if data.search and type(data.search) == "string" then sanitized.search = string.sub(data.search, 1, 128) end
    if data.evidenceType and type(data.evidenceType) == "string" then sanitized.evidenceType = string.sub(data.evidenceType, 1, 32) end
    if data.type and type(data.type) == "string" then sanitized.type = string.sub(data.type, 1, 32) end
    if data.isSealedOnly ~= nil then sanitized.isSealedOnly = (data.isSealedOnly == true or data.isSealedOnly == 1) end
    if data.seatIndex and type(data.seatIndex) == "number" then sanitized.seatIndex = math.max(1, math.min(20, math.floor(data.seatIndex))) end
    if data.requiredCount and type(data.requiredCount) == "number" then sanitized.requiredCount = math.max(1, math.min(20, math.floor(data.requiredCount))) end
    if data.requestedDurationHours and type(data.requestedDurationHours) == "number" then sanitized.requestedDurationHours = math.max(1, math.min(336, math.floor(data.requestedDurationHours))) end
    if data.durationHours and type(data.durationHours) == "number" then sanitized.durationHours = math.max(1, math.min(336, math.floor(data.durationHours))) end
    if data.reviewNotes and type(data.reviewNotes) == "string" then sanitized.reviewNotes = string.sub(data.reviewNotes, 1, 512) end
    if data.limit and type(data.limit) == "number" then sanitized.limit = math.max(1, math.min(100, math.floor(data.limit))) end
    if data.offset and type(data.offset) == "number" then sanitized.offset = math.max(0, math.min(10000, math.floor(data.offset))) end
    if data.payload and type(data.payload) == "table" then
        sanitized.payload = Nyx.UI.SanitizePayload(data.payload)
    end

    return sanitized
end

-- 4. Guaranteed Safe NUI Callback Wrapper (Zero Dangling Promises)
function Nyx.UI.SafeNUICallback(name, handler)
    RegisterNUICallback(name, function(rawPayload, rawCb)
        local cbHandled = false
        local function safeCb(resp)
            if not cbHandled then
                cbHandled = true
                rawCb(resp or { success = true })
            end
        end

        local sanitized = Nyx.UI.SanitizePayload(rawPayload)
        local ok, err = pcall(handler, sanitized, safeCb)
        if not ok then
            print(string.format("^1[Nyx:UI:Bridge] Error in NUI callback '%s': %s^7", tostring(name), tostring(err)))
            safeCb({ success = false, error = "INTERNAL_ERROR" })
        else
            -- Ensure safeCb is called even if handler is synchronous and forgot to call it
            safeCb({ success = true })
        end
    end)
end

-- 5. Inbound Generic NUI Callback Router
Nyx.UI.SafeNUICallback("postNui", function(data, cb)
    if not data or not data.app then
        return cb({ success = false, error = "INVALID_ENVELOPE" })
    end

    if Config.Debug then
        print(string.format("^3[Nyx:UI:Bridge] Inbound postNui: app=%s action=%s^7", tostring(data.app), tostring(data.action)))
    end

    -- Route to internal app event handlers
    TriggerEvent("nyx:ui:inbound:" .. data.app, data.action, data.payload, cb)
end)

-- 6. Specific NUI Callback Handlers with Guaranteed cb Execution
Nyx.UI.SafeNUICallback("close", function(data, cb)
    Nyx.UI.SetFocus(false, false)
    if data and data.app then
        TriggerEvent("nyx:ui:closed:" .. data.app, data)
    end
    cb({ success = true })
end)

Nyx.UI.SafeNUICallback("closeTreasury", function(_, cb)
    Nyx.UI.SetFocus(false, false)
    TriggerEvent("nyx:ui:closed:treasury", {})
    cb({ success = true })
end)

Nyx.UI.SafeNUICallback("closeMdt", function(_, cb)
    Nyx.UI.SetFocus(false, false)
    TriggerEvent("nyx:ui:closed:mdt", {})
    cb({ success = true })
end)

Nyx.UI.SafeNUICallback("closeFreightBoard", function(_, cb)
    Nyx.UI.SetFocus(false, false)
    SendNUIMessage({ action = "FREIGHT_BOARD_CLOSE" })
    TriggerEvent("nyx:ui:closed:freight", {})
    cb({ success = true })
end)

Nyx.UI.SafeNUICallback("hotbar:useSlot", function(data, cb)
    if data and data.slot then
        TriggerEvent("nyx:inventory:client:useHotbarSlot", data.slot)
    end
    cb({ success = true })
end)

Nyx.UI.SafeNUICallback("inventory:useItem", function(data, cb)
    if data and data.slot then
        TriggerEvent("nyx:inventory:client:useItem", data.slot)
    end
    cb({ success = true })
end)

Nyx.UI.SafeNUICallback("inventory:dropItem", function(data, cb)
    if data and data.slot then
        TriggerEvent("nyx:inventory:client:dropItem", data.slot, data.amount or 1)
    end
    cb({ success = true })
end)

Nyx.UI.SafeNUICallback("inventory:giveItem", function(data, cb)
    if data and data.slot then
        TriggerEvent("nyx:inventory:client:giveItem", data.slot)
    end
    cb({ success = true })
end)

Nyx.UI.SafeNUICallback("mdt:respondCall", function(data, cb)
    if data and data.callId then
        TriggerEvent("nyx:mdt:client:respondCall", data.callId)
    end
    cb({ success = true })
end)

Nyx.UI.SafeNUICallback("interact:selectOption", function(data, cb)
    TriggerEvent("nyx:interact:client:triggerOption", data)
    cb({ success = true })
end)

Nyx.UI.SafeNUICallback("claimFreightContract", function(data, cb)
    local contractId = tonumber(data and data.contractId)
    if not contractId then
        return cb({ success = false, error = "INVALID_CONTRACT_ID" })
    end
    if exports['nyx_core'] and exports['nyx_core'].TriggerRPCAwait then
        local res = exports['nyx_core']:TriggerRPCAwait("logistics:claimContract", contractId)
        return cb(res or { success = false })
    end
    cb({ success = true, contractId = contractId })
end)

Nyx.UI.SafeNUICallback("loadFreightPallet", function(data, cb)
    TriggerEvent("nyx:logistics:client:loadPallet", data)
    cb({ success = true })
end)

Nyx.UI.SafeNUICallback("deliverFreightContract", function(data, cb)
    TriggerEvent("nyx:logistics:client:deliverContract", data)
    cb({ success = true })
end)

-- 7. Corporate Multi-Sig, RBAC & Union Management NUI Callbacks
Nyx.UI.SafeNUICallback("closeFactionDashboard", function(_, cb)
    Nyx.UI.SetFocus(false, false)
    TriggerEvent("nyx:ui:closed:faction", {})
    cb({ success = true })
end)

Nyx.UI.SafeNUICallback("faction:getOverview", function(data, cb)
    if exports['nyx_core'] and exports['nyx_core'].TriggerRPCAwait then
        local res = exports['nyx_core']:TriggerRPCAwait("factions:getOverview", data and data.factionId)
        return cb(res or { success = false })
    end
    cb({ success = false, error = "RPC_UNAVAILABLE" })
end)

Nyx.UI.SafeNUICallback("faction:getCitizenFactions", function(data, cb)
    if exports['nyx_core'] and exports['nyx_core'].TriggerRPCAwait then
        local res = exports['nyx_core']:TriggerRPCAwait("factions:getCitizenFactions", data and data.targetCitizenId)
        return cb(res or { success = false })
    end
    cb({ success = false, error = "RPC_UNAVAILABLE" })
end)

Nyx.UI.SafeNUICallback("faction:addMember", function(data, cb)
    if exports['nyx_core'] and exports['nyx_core'].TriggerRPCAwait then
        local res = exports['nyx_core']:TriggerRPCAwait("factions:addMember", data)
        return cb(res or { success = false })
    end
    cb({ success = false, error = "RPC_UNAVAILABLE" })
end)

Nyx.UI.SafeNUICallback("faction:updateMember", function(data, cb)
    if exports['nyx_core'] and exports['nyx_core'].TriggerRPCAwait then
        local res = exports['nyx_core']:TriggerRPCAwait("factions:updateMember", data)
        return cb(res or { success = false })
    end
    cb({ success = false, error = "RPC_UNAVAILABLE" })
end)

Nyx.UI.SafeNUICallback("faction:removeMember", function(data, cb)
    if exports['nyx_core'] and exports['nyx_core'].TriggerRPCAwait then
        local res = exports['nyx_core']:TriggerRPCAwait("factions:removeMember", data and data.factionId, data and data.targetCitizenId)
        return cb(res or { success = false })
    end
    cb({ success = false, error = "RPC_UNAVAILABLE" })
end)

Nyx.UI.SafeNUICallback("faction:initiateWithdrawal", function(data, cb)
    if exports['nyx_core'] and exports['nyx_core'].TriggerRPCAwait then
        local res = exports['nyx_core']:TriggerRPCAwait("factions:initiateWithdrawal", data)
        return cb(res or { success = false })
    end
    cb({ success = false, error = "RPC_UNAVAILABLE" })
end)

Nyx.UI.SafeNUICallback("faction:signMultiSig", function(data, cb)
    if exports['nyx_core'] and exports['nyx_core'].TriggerRPCAwait then
        local res = exports['nyx_core']:TriggerRPCAwait("factions:signMultiSig", data)
        return cb(res or { success = false })
    end
    cb({ success = false, error = "RPC_UNAVAILABLE" })
end)

Nyx.UI.SafeNUICallback("faction:rejectMultiSig", function(data, cb)
    if exports['nyx_core'] and exports['nyx_core'].TriggerRPCAwait then
        local res = exports['nyx_core']:TriggerRPCAwait("factions:rejectMultiSig", data and data.requestId, data and data.reason)
        return cb(res or { success = false })
    end
    cb({ success = false, error = "RPC_UNAVAILABLE" })
end)

Nyx.UI.SafeNUICallback("faction:cancelMultiSig", function(data, cb)
    if exports['nyx_core'] and exports['nyx_core'].TriggerRPCAwait then
        local res = exports['nyx_core']:TriggerRPCAwait("factions:cancelMultiSig", data)
        return cb(res or { success = false })
    end
    cb({ success = false, error = "RPC_UNAVAILABLE" })
end)

Nyx.UI.SafeNUICallback("faction:executeTimelocked", function(data, cb)
    if exports['nyx_core'] and exports['nyx_core'].TriggerRPCAwait then
        local res = exports['nyx_core']:TriggerRPCAwait("factions:executeTimelocked", data and data.requestId)
        return cb(res or { success = false })
    end
    cb({ success = false, error = "RPC_UNAVAILABLE" })
end)

Nyx.UI.SafeNUICallback("faction:proposeCBA", function(data, cb)
    if exports['nyx_core'] and exports['nyx_core'].TriggerRPCAwait then
        local res = exports['nyx_core']:TriggerRPCAwait("factions:proposeCBA", data)
        return cb(res or { success = false })
    end
    cb({ success = false, error = "RPC_UNAVAILABLE" })
end)

Nyx.UI.SafeNUICallback("faction:ratifyCBA", function(data, cb)
    if exports['nyx_core'] and exports['nyx_core'].TriggerRPCAwait then
        local res = exports['nyx_core']:TriggerRPCAwait("factions:ratifyCBA", data and data.cbaId)
        return cb(res or { success = false })
    end
    cb({ success = false, error = "RPC_UNAVAILABLE" })
end)

Nyx.UI.SafeNUICallback("faction:claimStrikeRelief", function(data, cb)
    if exports['nyx_core'] and exports['nyx_core'].TriggerRPCAwait then
        local res = exports['nyx_core']:TriggerRPCAwait("factions:claimStrikeRelief", data and data.unionId)
        return cb(res or { success = false })
    end
    cb({ success = false, error = "RPC_UNAVAILABLE" })
end)

Nyx.UI.SafeNUICallback("faction:castStrikeVote", function(data, cb)
    if exports['nyx_core'] and exports['nyx_core'].TriggerRPCAwait then
        local res = exports['nyx_core']:TriggerRPCAwait("factions:castStrikeVote", data)
        return cb(res or { success = false })
    end
    cb({ success = false, error = "RPC_UNAVAILABLE" })
end)

Nyx.UI.SafeNUICallback("faction:distributeDividends", function(data, cb)
    if exports['nyx_core'] and exports['nyx_core'].TriggerRPCAwait then
        local res = exports['nyx_core']:TriggerRPCAwait("factions:distributeDividends", data and data.factionId, data and data.netProfit, data and data.rate)
        return cb(res or { success = false })
    end
    cb({ success = false, error = "RPC_UNAVAILABLE" })
end)

-- ============================================================================
-- 4E. Courtroom Terminal & Forensic Explorer NUI Callbacks
-- ============================================================================

Nyx.UI.SafeNUICallback("closeCourtTerminal", function(data, cb)
    Nyx.UI.SetFocus(false, false)
    cb({ success = true })
end)

Nyx.UI.SafeNUICallback("court:getOverview", function(data, cb)
    if exports['nyx_core'] and exports['nyx_core'].TriggerRPCAwait then
        local res = exports['nyx_core']:TriggerRPCAwait("judiciary:getCourtOverview")
        return cb(res or { success = false })
    end
    cb({ success = false, error = "RPC_UNAVAILABLE" })
end)

Nyx.UI.SafeNUICallback("court:getEvidenceList", function(data, cb)
    if exports['nyx_core'] and exports['nyx_core'].TriggerRPCAwait then
        local res = exports['nyx_core']:TriggerRPCAwait("judiciary:getEvidenceList", data)
        return cb(res or { success = false })
    end
    cb({ success = false, error = "RPC_UNAVAILABLE" })
end)

Nyx.UI.SafeNUICallback("court:getEvidenceChain", function(data, cb)
    if exports['nyx_core'] and exports['nyx_core'].TriggerRPCAwait then
        local res = exports['nyx_core']:TriggerRPCAwait("judiciary:getEvidenceChain", data and data.evidenceId)
        return cb(res or { success = false })
    end
    cb({ success = false, error = "RPC_UNAVAILABLE" })
end)

Nyx.UI.SafeNUICallback("court:verifyEvidenceChain", function(data, cb)
    if exports['nyx_core'] and exports['nyx_core'].TriggerRPCAwait then
        local res = exports['nyx_core']:TriggerRPCAwait("judiciary:verifyEvidenceChain", data and data.evidenceId)
        return cb(res or { success = false })
    end
    cb({ success = false, error = "RPC_UNAVAILABLE" })
end)

Nyx.UI.SafeNUICallback("court:castJuryVote", function(data, cb)
    if exports['nyx_core'] and exports['nyx_core'].TriggerRPCAwait then
        local res = exports['nyx_core']:TriggerRPCAwait("judiciary:castJuryVote", data and data.docketId, data and data.vote)
        return cb(res or { success = false })
    end
    cb({ success = false, error = "RPC_UNAVAILABLE" })
end)

Nyx.UI.SafeNUICallback("court:seatJuror", function(data, cb)
    if exports['nyx_core'] and exports['nyx_core'].TriggerRPCAwait then
        local res = exports['nyx_core']:TriggerRPCAwait("judiciary:seatJuror", data)
        return cb(res or { success = false })
    end
    cb({ success = false, error = "RPC_UNAVAILABLE" })
end)

Nyx.UI.SafeNUICallback("court:summonJury", function(data, cb)
    if exports['nyx_core'] and exports['nyx_core'].TriggerRPCAwait then
        local res = exports['nyx_core']:TriggerRPCAwait("judiciary:summonJury", data)
        return cb(res or { success = false })
    end
    cb({ success = false, error = "RPC_UNAVAILABLE" })
end)

Nyx.UI.SafeNUICallback("court:startTrial", function(data, cb)
    if exports['nyx_core'] and exports['nyx_core'].TriggerRPCAwait then
        local res = exports['nyx_core']:TriggerRPCAwait("judiciary:startTrial", data and data.docketId)
        return cb(res or { success = false })
    end
    cb({ success = false, error = "RPC_UNAVAILABLE" })
end)

Nyx.UI.SafeNUICallback("court:startDeliberation", function(data, cb)
    if exports['nyx_core'] and exports['nyx_core'].TriggerRPCAwait then
        local res = exports['nyx_core']:TriggerRPCAwait("judiciary:startDeliberation", data and data.docketId)
        return cb(res or { success = false })
    end
    cb({ success = false, error = "RPC_UNAVAILABLE" })
end)

Nyx.UI.SafeNUICallback("court:concludeTrial", function(data, cb)
    if exports['nyx_core'] and exports['nyx_core'].TriggerRPCAwait then
        local res = exports['nyx_core']:TriggerRPCAwait("judiciary:concludeTrial", data)
        return cb(res or { success = false })
    end
    cb({ success = false, error = "RPC_UNAVAILABLE" })
end)

Nyx.UI.SafeNUICallback("court:petitionWarrant", function(data, cb)
    if exports['nyx_core'] and exports['nyx_core'].TriggerRPCAwait then
        local res = exports['nyx_core']:TriggerRPCAwait("judiciary:petitionWarrant", data)
        return cb(res or { success = false })
    end
    cb({ success = false, error = "RPC_UNAVAILABLE" })
end)

Nyx.UI.SafeNUICallback("court:reviewPetition", function(data, cb)
    if exports['nyx_core'] and exports['nyx_core'].TriggerRPCAwait then
        local res = exports['nyx_core']:TriggerRPCAwait("judiciary:reviewPetition", data)
        return cb(res or { success = false })
    end
    cb({ success = false, error = "RPC_UNAVAILABLE" })
end)

Nyx.UI.SafeNUICallback("court:rescindWarrant", function(data, cb)
    if exports['nyx_core'] and exports['nyx_core'].TriggerRPCAwait then
        local res = exports['nyx_core']:TriggerRPCAwait("judiciary:rescindWarrant", data)
        return cb(res or { success = false })
    end
    cb({ success = false, error = "RPC_UNAVAILABLE" })
end)

Nyx.UI.SafeNUICallback("court:getSubpoenaRecords", function(data, cb)
    if exports['nyx_core'] and exports['nyx_core'].TriggerRPCAwait then
        local target = data and (data.targetCitizenId or data.targetId)
        local res = exports['nyx_core']:TriggerRPCAwait("judiciary:getSubpoenaRecords", target)
        return cb(res or { success = false })
    end
    cb({ success = false, error = "RPC_UNAVAILABLE" })
end)

-- 5. Intercept Universal Notification Triggers across All Framework Modules
RegisterNetEvent("nyx:ui:notify", function(data)
    if not data then return end

    local envelope = {
        id = "notif_" .. tostring(GetGameTimer()) .. "_" .. math.random(100, 999),
        type = data.type or "info",            -- "info", "success", "warning", "error"
        title = data.title or string.upper(data.type or "NOTICE"),
        message = data.message or data.text or "",
        duration = data.duration or Config.Notifications.DefaultDuration or 4500
    }

    Nyx.UI.Send("hud", "ADD_NOTIFICATION", envelope)
end)

RegisterNetEvent("nyx:core:notify", function(text, nType, duration)
    TriggerEvent("nyx:ui:notify", {
        type = nType or "info",
        message = text or "",
        duration = duration or Config.Notifications.DefaultDuration
    })
end)
