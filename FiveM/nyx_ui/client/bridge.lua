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
    -- Parliamentary Ranked-Choice Voting & Legislation parameters
    if data.sessionId and (type(data.sessionId) == "string" or type(data.sessionId) == "number") then sanitized.sessionId = tostring(data.sessionId) end
    if data.candidateId and (type(data.candidateId) == "string" or type(data.candidateId) == "number") then sanitized.candidateId = tostring(data.candidateId) end
    if data.preferences and type(data.preferences) == "table" then sanitized.preferences = data.preferences end
    if data.displayName and type(data.displayName) == "string" then sanitized.displayName = string.sub(data.displayName, 1, 96) end
    if data.party and type(data.party) == "string" then sanitized.party = string.sub(data.party, 1, 96) end
    if data.platform and type(data.platform) == "string" then sanitized.platform = string.sub(data.platform, 1, 1024) end
    if data.slogan and type(data.slogan) == "string" then sanitized.slogan = string.sub(data.slogan, 1, 128) end
    if data.receiptHash and type(data.receiptHash) == "string" then sanitized.receiptHash = string.sub(data.receiptHash, 1, 64) end
    if data.officeId and type(data.officeId) == "string" then sanitized.officeId = string.sub(data.officeId, 1, 32) end
    if data.filterLawId and type(data.filterLawId) == "string" then sanitized.filterLawId = string.sub(data.filterLawId, 1, 32) end
    if data.categoryFilter and type(data.categoryFilter) == "string" then sanitized.categoryFilter = string.sub(data.categoryFilter, 1, 32) end
    if data.activeTab and type(data.activeTab) == "string" then sanitized.activeTab = string.sub(data.activeTab, 1, 32) end
    if data.actions and type(data.actions) == "table" then sanitized.actions = data.actions end
    if data.billPayload and type(data.billPayload) == "table" then sanitized.billPayload = data.billPayload end
    if data.description and type(data.description) == "string" then sanitized.description = string.sub(data.description, 1, 1024) end
    if data.boothId and type(data.boothId) == "string" then sanitized.boothId = string.sub(data.boothId, 1, 32) end
    if data.boothLabel and type(data.boothLabel) == "string" then sanitized.boothLabel = string.sub(data.boothLabel, 1, 96) end
    -- Real Estate & Property Portal parameters
    if data.auctionId and (type(data.auctionId) == "string" or type(data.auctionId) == "number") then sanitized.auctionId = tonumber(data.auctionId) or tostring(data.auctionId) end
    if data.propertyId and (type(data.propertyId) == "string" or type(data.propertyId) == "number") then sanitized.propertyId = tonumber(data.propertyId) or tostring(data.propertyId) end
    if data.bidAmount and type(data.bidAmount) == "number" then sanitized.bidAmount = data.bidAmount end
    if data.delegateCitizenId and type(data.delegateCitizenId) == "string" then sanitized.delegateCitizenId = string.sub(data.delegateCitizenId, 1, 16) end
    if data.scope and type(data.scope) == "string" then sanitized.scope = string.sub(data.scope, 1, 32) end
    if data.notes and type(data.notes) == "string" then sanitized.notes = string.sub(data.notes, 1, 255) end
    if data.statusFilter and type(data.statusFilter) == "string" then sanitized.statusFilter = string.sub(data.statusFilter, 1, 32) end
    if data.typeFilter and type(data.typeFilter) == "string" then sanitized.typeFilter = string.sub(data.typeFilter, 1, 32) end
    if data.searchQuery and type(data.searchQuery) == "string" then sanitized.searchQuery = string.sub(data.searchQuery, 1, 128) end
    -- 3D Warehouse Matrix & Elastic Market Monitor parameters
    if data.warehouseId and type(data.warehouseId) == "string" then sanitized.warehouseId = string.sub(data.warehouseId, 1, 64) end
    if data.shelfId and type(data.shelfId) == "string" then sanitized.shelfId = string.sub(data.shelfId, 1, 64) end
    if data.nodeId and type(data.nodeId) == "string" then sanitized.nodeId = string.sub(data.nodeId, 1, 64) end
    if data.originWarehouseId and type(data.originWarehouseId) == "string" then sanitized.originWarehouseId = string.sub(data.originWarehouseId, 1, 64) end
    if data.destinationZoneId and type(data.destinationZoneId) == "string" then sanitized.destinationZoneId = string.sub(data.destinationZoneId, 1, 32) end
    if data.zoneId and type(data.zoneId) == "string" then sanitized.zoneId = string.sub(data.zoneId, 1, 32) end
    if data.filterZoneId and type(data.filterZoneId) == "string" then sanitized.filterZoneId = string.sub(data.filterZoneId, 1, 32) end
    if data.units and type(data.units) == "number" then sanitized.units = math.max(1, math.min(1000, math.floor(data.units))) end
    if data.durationMinutes and type(data.durationMinutes) == "number" then sanitized.durationMinutes = math.max(10, math.min(1440, math.floor(data.durationMinutes))) end
    if data.dispatchId and (type(data.dispatchId) == "string" or type(data.dispatchId) == "number") then sanitized.dispatchId = tonumber(data.dispatchId) or tostring(data.dispatchId) end
    if data.temperatureZone and type(data.temperatureZone) == "string" then sanitized.temperatureZone = string.sub(data.temperatureZone, 1, 20) end
    -- Vehicle Diagnostics & Civic Impound Terminal parameters
    if data.vin and type(data.vin) == "string" then sanitized.vin = string.sub(data.vin, 1, 32) end
    if data.plate and type(data.plate) == "string" then sanitized.plate = string.sub(data.plate, 1, 16) end
    if data.serviceType and type(data.serviceType) == "string" then sanitized.serviceType = string.sub(data.serviceType, 1, 32) end
    if data.lotId and type(data.lotId) == "string" then sanitized.lotId = string.sub(data.lotId, 1, 64) end
    -- Citizen OS Master Smartphone Framework parameters
    if data.recipientCitizenId and type(data.recipientCitizenId) == "string" then sanitized.recipientCitizenId = string.sub(data.recipientCitizenId, 1, 64) end
    if data.transferAmount and type(data.transferAmount) == "number" then sanitized.transferAmount = math.max(0.01, math.min(10000000.0, data.transferAmount)) end
    if data.transferMemo and type(data.transferMemo) == "string" then sanitized.transferMemo = string.sub(data.transferMemo, 1, 128) end
    if data.alertCategory and type(data.alertCategory) == "string" then sanitized.alertCategory = string.sub(data.alertCategory, 1, 32) end
    if data.alertMessage and type(data.alertMessage) == "string" then sanitized.alertMessage = string.sub(data.alertMessage, 1, 500) end
    if data.alertPriority and type(data.alertPriority) == "string" then sanitized.alertPriority = string.sub(data.alertPriority, 1, 16) end
    if data.locationLabel and type(data.locationLabel) == "string" then sanitized.locationLabel = string.sub(data.locationLabel, 1, 128) end
    if data.wallpaper and type(data.wallpaper) == "string" then sanitized.wallpaper = string.sub(data.wallpaper, 1, 64) end
    if data.darkMode ~= nil then sanitized.darkMode = (data.darkMode == true or data.darkMode == 1) end
    if data.airplaneMode ~= nil then sanitized.airplaneMode = (data.airplaneMode == true or data.airplaneMode == 1) end
    if data.appId and type(data.appId) == "string" then sanitized.appId = string.sub(data.appId, 1, 32) end
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

-- Parliamentary Ranked-Choice Voting & Legislation Callbacks
Nyx.UI.SafeNUICallback("closeParliamentUI", function(_, cb)
    Nyx.UI.SetFocus(false, false)
    cb({ success = true })
end)

Nyx.UI.SafeNUICallback("parliament:getOverview", function(_, cb)
    if exports['nyx_core'] and exports['nyx_core'].TriggerRPCAwait then
        local res = exports['nyx_core']:TriggerRPCAwait("parliament:getOverview")
        return cb(res or { success = false })
    end
    cb({ success = false, error = "RPC_UNAVAILABLE" })
end)

Nyx.UI.SafeNUICallback("parliament:getActiveSessions", function(_, cb)
    if exports['nyx_core'] and exports['nyx_core'].TriggerRPCAwait then
        local res = exports['nyx_core']:TriggerRPCAwait("parliament:getActiveSessions")
        return cb(res or {})
    end
    cb({})
end)

Nyx.UI.SafeNUICallback("parliament:getCandidates", function(data, cb)
    if exports['nyx_core'] and exports['nyx_core'].TriggerRPCAwait then
        local res = exports['nyx_core']:TriggerRPCAwait("parliament:getCandidates", data and data.sessionId)
        return cb(res or {})
    end
    cb({})
end)

Nyx.UI.SafeNUICallback("parliament:castBallot", function(data, cb)
    if exports['nyx_core'] and exports['nyx_core'].TriggerRPCAwait then
        local res = exports['nyx_core']:TriggerRPCAwait("parliament:castBallot", data and data.sessionId, data and data.preferences, data and data.boothId, data and data.boothLabel)
        return cb(res or { success = false })
    end
    cb({ success = false, error = "RPC_UNAVAILABLE" })
end)

Nyx.UI.SafeNUICallback("parliament:verifyReceipt", function(data, cb)
    if exports['nyx_core'] and exports['nyx_core'].TriggerRPCAwait then
        local res = exports['nyx_core']:TriggerRPCAwait("parliament:verifyReceipt", data and data.sessionId, data and data.receiptHash)
        return cb(res or { verified = false })
    end
    cb({ verified = false })
end)

Nyx.UI.SafeNUICallback("parliament:registerCandidate", function(data, cb)
    if exports['nyx_core'] and exports['nyx_core'].TriggerRPCAwait then
        local res = exports['nyx_core']:TriggerRPCAwait("parliament:registerCandidate", data)
        return cb(res or { success = false })
    end
    cb({ success = false, error = "RPC_UNAVAILABLE" })
end)

Nyx.UI.SafeNUICallback("parliament:withdrawCandidacy", function(data, cb)
    if exports['nyx_core'] and exports['nyx_core'].TriggerRPCAwait then
        local res = exports['nyx_core']:TriggerRPCAwait("parliament:withdrawCandidacy", data and (data.candidateId or data.id))
        return cb(res or { success = false })
    end
    cb({ success = false, error = "RPC_UNAVAILABLE" })
end)

Nyx.UI.SafeNUICallback("parliament:endorseCandidate", function(data, cb)
    if exports['nyx_core'] and exports['nyx_core'].TriggerRPCAwait then
        local res = exports['nyx_core']:TriggerRPCAwait("parliament:endorseCandidate", data and data.candidateId)
        return cb(res or { success = false })
    end
    cb({ success = false, error = "RPC_UNAVAILABLE" })
end)

Nyx.UI.SafeNUICallback("parliament:getPenalCode", function(_, cb)
    if exports['nyx_core'] and exports['nyx_core'].TriggerRPCAwait then
        local res = exports['nyx_core']:TriggerRPCAwait("parliament:getPenalCode")
        return cb(res or {})
    end
    cb({})
end)

Nyx.UI.SafeNUICallback("parliament:getLawBook", function(data, cb)
    if exports['nyx_core'] and exports['nyx_core'].TriggerRPCAwait then
        local filter = data and (data.categoryFilter or data.category) or "ALL"
        local res = exports['nyx_core']:TriggerRPCAwait("parliament:getLawBook", filter)
        return cb(res or {})
    end
    cb({})
end)

Nyx.UI.SafeNUICallback("parliament:getOfficials", function(_, cb)
    if exports['nyx_core'] and exports['nyx_core'].TriggerRPCAwait then
        local res = exports['nyx_core']:TriggerRPCAwait("parliament:getOfficials")
        return cb(res or {})
    end
    cb({})
end)

Nyx.UI.SafeNUICallback("parliament:getTabulationAudit", function(data, cb)
    if exports['nyx_core'] and exports['nyx_core'].TriggerRPCAwait then
        local res = exports['nyx_core']:TriggerRPCAwait("parliament:getTabulationAudit", data and data.sessionId)
        return cb(res or {})
    end
    cb({})
end)

Nyx.UI.SafeNUICallback("parliament:proposeBill", function(data, cb)
    if exports['nyx_core'] and exports['nyx_core'].TriggerRPCAwait then
        local payload = data and (data.billPayload or data)
        local res = exports['nyx_core']:TriggerRPCAwait("parliament:proposeBill", payload)
        return cb(res or { success = false })
    end
    cb({ success = false, error = "RPC_UNAVAILABLE" })
end)

Nyx.UI.SafeNUICallback("parliament:fileRecallPetition", function(data, cb)
    if exports['nyx_core'] and exports['nyx_core'].TriggerRPCAwait then
        local res = exports['nyx_core']:TriggerRPCAwait("parliament:fileRecallPetition", data)
        return cb(res or { success = false })
    end
    cb({ success = false, error = "RPC_UNAVAILABLE" })
end)

Nyx.UI.SafeNUICallback("parliament:signRecallPetition", function(data, cb)
    if exports['nyx_core'] and exports['nyx_core'].TriggerRPCAwait then
        local res = exports['nyx_core']:TriggerRPCAwait("parliament:signRecallPetition", data and (data.petitionId or data.id))
        return cb(res or { success = false })
    end
    cb({ success = false, error = "RPC_UNAVAILABLE" })
end)

Nyx.UI.SafeNUICallback("parliament:getAmendmentAudit", function(data, cb)
    if exports['nyx_core'] and exports['nyx_core'].TriggerRPCAwait then
        local res = exports['nyx_core']:TriggerRPCAwait("parliament:getAmendmentAudit", data and data.filterLawId)
        return cb(res or {})
    end
    cb({})
end)

Nyx.UI.SafeNUICallback("parliament:getBoothTerminals", function(_, cb)
    if exports['nyx_core'] and exports['nyx_core'].TriggerRPCAwait then
        local res = exports['nyx_core']:TriggerRPCAwait("parliament:getBoothTerminals")
        return cb(res or {})
    end
    cb({})
end)

Nyx.UI.SafeNUICallback("parliament:getTermAudits", function(data, cb)
    if exports['nyx_core'] and exports['nyx_core'].TriggerRPCAwait then
        local res = exports['nyx_core']:TriggerRPCAwait("parliament:getTermAudits", data and data.officeId)
        return cb(res or {})
    end
    cb({})
end)

-- Property Blind-Auction & Stewardship Portal Callbacks
Nyx.UI.SafeNUICallback("closePropertyPortal", function(_, cb)
    Nyx.UI.SetFocus(false, false)
    cb({ success = true })
end)

Nyx.UI.SafeNUICallback("property:getOverview", function(_, cb)
    if exports['nyx_core'] and exports['nyx_core'].TriggerRPCAwait then
        local res = exports['nyx_core']:TriggerRPCAwait("properties:getRealEstatePortalOverview")
        return cb(res or { success = false })
    end
    cb({ success = false, error = "RPC_UNAVAILABLE" })
end)

Nyx.UI.SafeNUICallback("property:getActiveAuctions", function(_, cb)
    if exports['nyx_core'] and exports['nyx_core'].TriggerRPCAwait then
        local res = exports['nyx_core']:TriggerRPCAwait("properties:getActiveAuctions")
        return cb(res or { success = false, auctions = {} })
    end
    cb({ success = false, auctions = {} })
end)

Nyx.UI.SafeNUICallback("property:placeBid", function(data, cb)
    if exports['nyx_core'] and exports['nyx_core'].TriggerRPCAwait then
        local res = exports['nyx_core']:TriggerRPCAwait("properties:placeSealedBid", data)
        return cb(res or { success = false })
    end
    cb({ success = false, error = "RPC_UNAVAILABLE" })
end)

Nyx.UI.SafeNUICallback("property:getAuctionBids", function(data, cb)
    if exports['nyx_core'] and exports['nyx_core'].TriggerRPCAwait then
        local res = exports['nyx_core']:TriggerRPCAwait("properties:getAuctionBidsHistory", data and data.auctionId)
        return cb(res or {})
    end
    cb({})
end)

Nyx.UI.SafeNUICallback("property:payArrears", function(data, cb)
    if exports['nyx_core'] and exports['nyx_core'].TriggerRPCAwait then
        local res = exports['nyx_core']:TriggerRPCAwait("properties:payDelinquentTaxes", data and data.propertyId)
        return cb(res or { success = false })
    end
    cb({ success = false, error = "RPC_UNAVAILABLE" })
end)

Nyx.UI.SafeNUICallback("property:repairCondition", function(data, cb)
    if exports['nyx_core'] and exports['nyx_core'].TriggerRPCAwait then
        local res = exports['nyx_core']:TriggerRPCAwait("properties:repairCondition", data and data.propertyId)
        return cb(res or { success = false })
    end
    cb({ success = false, error = "RPC_UNAVAILABLE" })
end)

Nyx.UI.SafeNUICallback("property:getTaxAssessment", function(data, cb)
    if exports['nyx_core'] and exports['nyx_core'].TriggerRPCAwait then
        local res = exports['nyx_core']:TriggerRPCAwait("properties:getTaxAssessment", data and data.propertyId)
        return cb(res or { success = false })
    end
    cb({ success = false, error = "RPC_UNAVAILABLE" })
end)

Nyx.UI.SafeNUICallback("property:registerDelegate", function(data, cb)
    if exports['nyx_core'] and exports['nyx_core'].TriggerRPCAwait then
        local res = exports['nyx_core']:TriggerRPCAwait("properties:registerStewardDelegate", data)
        return cb(res or { success = false })
    end
    cb({ success = false, error = "RPC_UNAVAILABLE" })
end)

Nyx.UI.SafeNUICallback("property:revokeDelegate", function(data, cb)
    if exports['nyx_core'] and exports['nyx_core'].TriggerRPCAwait then
        local res = exports['nyx_core']:TriggerRPCAwait("properties:revokeStewardDelegate", data)
        return cb(res or { success = false })
    end
    cb({ success = false, error = "RPC_UNAVAILABLE" })
end)

Nyx.UI.SafeNUICallback("property:assignSteward", function(data, cb)
    if exports['nyx_core'] and exports['nyx_core'].TriggerRPCAwait then
        local res = exports['nyx_core']:TriggerRPCAwait("properties:assignPropertySteward", data)
        return cb(res or { success = false })
    end
    cb({ success = false, error = "RPC_UNAVAILABLE" })
end)

Nyx.UI.SafeNUICallback("property:getMyStewardship", function(_, cb)
    if exports['nyx_core'] and exports['nyx_core'].TriggerRPCAwait then
        local res = exports['nyx_core']:TriggerRPCAwait("properties:getMyStewardship")
        return cb(res or {})
    end
    cb({})
end)

Nyx.UI.SafeNUICallback("property:getInactivityAuditLogs", function(data, cb)
    if exports['nyx_core'] and exports['nyx_core'].TriggerRPCAwait then
        local limit = data and data.limit or 20
        local res = exports['nyx_core']:TriggerRPCAwait("properties:getInactivityAuditLogs", limit)
        return cb(res or {})
    end
    cb({})
end)

-- 3D Warehouse Matrix & Elastic Market Monitor NUI Callbacks
Nyx.UI.SafeNUICallback("closeMarketMonitor", function(_, cb)
    Nyx.UI.SetFocus(false, false)
    cb({ success = true })
end)

Nyx.UI.SafeNUICallback("logistics:getMatrixOverview", function(data, cb)
    if exports['nyx_core'] and exports['nyx_core'].TriggerRPCAwait then
        local res = exports['nyx_core']:TriggerRPCAwait("logistics:getWarehouseMatrixOverview", data and data.warehouseId)
        return cb(res or { success = false })
    end
    cb({ success = false, error = "RPC_UNAVAILABLE" })
end)

Nyx.UI.SafeNUICallback("logistics:getMarketOverview", function(data, cb)
    if exports['nyx_core'] and exports['nyx_core'].TriggerRPCAwait then
        local res = exports['nyx_core']:TriggerRPCAwait("logistics:getMarketMonitorOverview", data and (data.zoneId or data.filterZoneId))
        return cb(res or { success = false })
    end
    cb({ success = false, error = "RPC_UNAVAILABLE" })
end)

Nyx.UI.SafeNUICallback("logistics:getArbitrageRoutes", function(_, cb)
    if exports['nyx_core'] and exports['nyx_core'].TriggerRPCAwait then
        local res = exports['nyx_core']:TriggerRPCAwait("logistics:getHaulerArbitrageRoutes")
        return cb(res or { success = false, routes = {} })
    end
    cb({ success = false, routes = {} })
end)

Nyx.UI.SafeNUICallback("logistics:bookDispatch", function(data, cb)
    if exports['nyx_core'] and exports['nyx_core'].TriggerRPCAwait then
        local res = exports['nyx_core']:TriggerRPCAwait("logistics:bookHaulerDispatch", data)
        return cb(res or { success = false })
    end
    cb({ success = false, error = "RPC_UNAVAILABLE" })
end)

Nyx.UI.SafeNUICallback("logistics:cancelDispatch", function(data, cb)
    if exports['nyx_core'] and exports['nyx_core'].TriggerRPCAwait then
        local res = exports['nyx_core']:TriggerRPCAwait("logistics:cancelHaulerDispatch", data and data.dispatchId)
        return cb(res or { success = false })
    end
    cb({ success = false, error = "RPC_UNAVAILABLE" })
end)

Nyx.UI.SafeNUICallback("logistics:reserveNode", function(data, cb)
    if exports['nyx_core'] and exports['nyx_core'].TriggerRPCAwait then
        local res = exports['nyx_core']:TriggerRPCAwait("logistics:reserveShelfNode", data and data.nodeId, data and data.durationMinutes)
        return cb(res or { success = false })
    end
    cb({ success = false, error = "RPC_UNAVAILABLE" })
end)

-- Vehicle Diagnostics & Civic Impound Terminal NUI Callbacks
Nyx.UI.SafeNUICallback("closeVehicleTerminal", function(_, cb)
    Nyx.UI.SetFocus(false, false)
    cb({ success = true })
end)

Nyx.UI.SafeNUICallback("vehicle:getOverview", function(data, cb)
    if exports['nyx_core'] and exports['nyx_core'].TriggerRPCAwait then
        local res = exports['nyx_core']:TriggerRPCAwait("vehicles:getDiagnosticsOverview", data and (data.vin or data.plate))
        return cb(res or { success = false })
    end
    cb({ success = false, error = "RPC_UNAVAILABLE" })
end)

Nyx.UI.SafeNUICallback("vehicle:scanOBD", function(data, cb)
    if exports['nyx_core'] and exports['nyx_core'].TriggerRPCAwait then
        local res = exports['nyx_core']:TriggerRPCAwait("vehicles:scanVehicle", data)
        return cb(res or { success = false })
    end
    cb({ success = false, error = "RPC_UNAVAILABLE" })
end)

Nyx.UI.SafeNUICallback("vehicle:performService", function(data, cb)
    if exports['nyx_core'] and exports['nyx_core'].TriggerRPCAwait then
        local res = exports['nyx_core']:TriggerRPCAwait("vehicles:performCertifiedService", data)
        return cb(res or { success = false })
    end
    cb({ success = false, error = "RPC_UNAVAILABLE" })
end)

Nyx.UI.SafeNUICallback("vehicle:resetTrip", function(data, cb)
    if exports['nyx_core'] and exports['nyx_core'].TriggerRPCAwait then
        local res = exports['nyx_core']:TriggerRPCAwait("vehicles:resetTrip", data and (data.vin or data.plate))
        return cb(res or { success = false })
    end
    cb({ success = false, error = "RPC_UNAVAILABLE" })
end)

Nyx.UI.SafeNUICallback("vehicle:releaseImpound", function(data, cb)
    if exports['nyx_core'] and exports['nyx_core'].TriggerRPCAwait then
        local res = exports['nyx_core']:TriggerRPCAwait("vehicles:releaseImpoundedVehicle", data)
        return cb(res or { success = false })
    end
    cb({ success = false, error = "RPC_UNAVAILABLE" })
end)

Nyx.UI.SafeNUICallback("vehicle:renewRegistration", function(data, cb)
    if exports['nyx_core'] and exports['nyx_core'].TriggerRPCAwait then
        local res = exports['nyx_core']:TriggerRPCAwait("vehicles:renewRegistration", data)
        return cb(res or { success = false })
    end
    cb({ success = false, error = "RPC_UNAVAILABLE" })
end)

Nyx.UI.SafeNUICallback("vehicle:getImpoundLots", function(_, cb)
    if exports['nyx_core'] and exports['nyx_core'].TriggerRPCAwait then
        local res = exports['nyx_core']:TriggerRPCAwait("vehicles:getCivicImpoundLots")
        return cb(res or { success = false, lots = {} })
    end
    cb({ success = false, lots = {} })
end)

-- Citizen OS Master Smartphone NUI Callbacks
Nyx.UI.SafeNUICallback("closePhone", function(_, cb)
    if Nyx.UI.ClosePhone then
        Nyx.UI.ClosePhone()
    else
        Nyx.UI.SetFocus(false, false)
    end
    cb({ success = true })
end)

Nyx.UI.SafeNUICallback("phone:getOverview", function(_, cb)
    if exports['nyx_core'] and exports['nyx_core'].TriggerRPCAwait then
        local res = exports['nyx_core']:TriggerRPCAwait("phone:getOverview")
        return cb(res or { success = false })
    end
    cb({ success = false, error = "RPC_UNAVAILABLE" })
end)

Nyx.UI.SafeNUICallback("phone:transferMoney", function(data, cb)
    if exports['nyx_core'] and exports['nyx_core'].TriggerRPCAwait then
        local res = exports['nyx_core']:TriggerRPCAwait("phone:transferMoney", data)
        return cb(res or { success = false })
    end
    cb({ success = false, error = "RPC_UNAVAILABLE" })
end)

Nyx.UI.SafeNUICallback("phone:getFreightBoard", function(data, cb)
    if exports['nyx_core'] and exports['nyx_core'].TriggerRPCAwait then
        local res = exports['nyx_core']:TriggerRPCAwait("phone:getFreightBoard", data and data.filterType, data and data.search)
        return cb(res or { success = false, contracts = {} })
    end
    cb({ success = false, contracts = {} })
end)

Nyx.UI.SafeNUICallback("phone:claimContract", function(data, cb)
    if exports['nyx_core'] and exports['nyx_core'].TriggerRPCAwait then
        local res = exports['nyx_core']:TriggerRPCAwait("phone:claimContract", data and data.contractId)
        return cb(res or { success = false })
    end
    cb({ success = false, error = "RPC_UNAVAILABLE" })
end)

Nyx.UI.SafeNUICallback("phone:loadFreightPallet", function(data, cb)
    if exports['nyx_core'] and exports['nyx_core'].TriggerRPCAwait then
        local res = exports['nyx_core']:TriggerRPCAwait("logistics:loadFreightPallet", data)
        return cb(res or { success = false })
    end
    cb({ success = false, error = "RPC_UNAVAILABLE" })
end)

Nyx.UI.SafeNUICallback("phone:deliverContract", function(data, cb)
    if exports['nyx_core'] and exports['nyx_core'].TriggerRPCAwait then
        local res = exports['nyx_core']:TriggerRPCAwait("logistics:deliverContract", data)
        return cb(res or { success = false })
    end
    cb({ success = false, error = "RPC_UNAVAILABLE" })
end)

Nyx.UI.SafeNUICallback("phone:abandonContract", function(data, cb)
    if exports['nyx_core'] and exports['nyx_core'].TriggerRPCAwait then
        local res = exports['nyx_core']:TriggerRPCAwait("logistics:abandonContract", data and data.contractId)
        return cb(res or { success = false })
    end
    cb({ success = false, error = "RPC_UNAVAILABLE" })
end)

Nyx.UI.SafeNUICallback("phone:sendEmergencyAlert", function(data, cb)
    if exports['nyx_core'] and exports['nyx_core'].TriggerRPCAwait then
        local res = exports['nyx_core']:TriggerRPCAwait("phone:sendEmergencyAlert", data)
        return cb(res or { success = false })
    end
    cb({ success = false, error = "RPC_UNAVAILABLE" })
end)

Nyx.UI.SafeNUICallback("phone:getEmergencyAlerts", function(_, cb)
    if exports['nyx_core'] and exports['nyx_core'].TriggerRPCAwait then
        local res = exports['nyx_core']:TriggerRPCAwait("phone:getEmergencyAlerts")
        return cb(res or { success = false, alerts = {} })
    end
    cb({ success = false, alerts = {} })
end)

Nyx.UI.SafeNUICallback("phone:updateSettings", function(data, cb)
    if exports['nyx_core'] and exports['nyx_core'].TriggerRPCAwait then
        local res = exports['nyx_core']:TriggerRPCAwait("phone:updateSettings", data)
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
