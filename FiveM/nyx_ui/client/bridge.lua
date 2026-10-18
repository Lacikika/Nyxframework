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
