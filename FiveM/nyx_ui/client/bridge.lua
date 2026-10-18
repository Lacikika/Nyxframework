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

-- 3. Inbound Generic NUI Callback Router
RegisterNUICallback("postNui", function(data, cb)
    if not data or not data.app then
        cb({ success = false, error = "INVALID_ENVELOPE" })
        return
    end

    if Config.Debug then
        print(string.format("^3[Nyx:UI:Bridge] Inbound postNui: app=%s action=%s^7", tostring(data.app), tostring(data.action)))
    end

    -- Route to internal app event handlers
    TriggerEvent("nyx:ui:inbound:" .. data.app, data.action, data.payload, cb)
end)

-- 4. Specific NUI Callback Handlers
RegisterNUICallback("close", function(data, cb)
    Nyx.UI.SetFocus(false, false)
    if data and data.app then
        TriggerEvent("nyx:ui:closed:" .. data.app, data)
    end
    cb({ success = true })
end)

RegisterNUICallback("closeTreasury", function(_, cb)
    Nyx.UI.SetFocus(false, false)
    cb({ success = true })
end)

RegisterNUICallback("closeMdt", function(_, cb)
    Nyx.UI.SetFocus(false, false)
    cb({ success = true })
end)

RegisterNUICallback("hotbar:useSlot", function(data, cb)
    if data and data.slot then
        TriggerEvent("nyx:inventory:client:useHotbarSlot", data.slot)
    end
    cb({ success = true })
end)

RegisterNUICallback("inventory:useItem", function(data, cb)
    if data and data.slot then
        TriggerEvent("nyx:inventory:client:useItem", data.slot)
    end
    cb({ success = true })
end)

RegisterNUICallback("inventory:dropItem", function(data, cb)
    if data and data.slot then
        TriggerEvent("nyx:inventory:client:dropItem", data.slot, data.amount or 1)
    end
    cb({ success = true })
end)

RegisterNUICallback("mdt:respondCall", function(data, cb)
    if data and data.callId then
        TriggerEvent("nyx:mdt:client:respondCall", data.callId)
    end
    cb({ success = true })
end)

RegisterNUICallback("interact:selectOption", function(data, cb)
    TriggerEvent("nyx:interact:client:triggerOption", data)
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
