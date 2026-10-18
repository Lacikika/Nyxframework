--[[
    Nyxframework: nyx_ui
    File: client/exports.lua
    Description: Public client exports for sending NUI envelopes, controlling focus, and queuing alerts.
]]

exports('Send', function(app, action, payload)
    Nyx.UI.Send(app, action, payload)
end)

exports('SetFocus', function(hasCursor, hasKeyboard)
    Nyx.UI.SetFocus(hasCursor, hasKeyboard)
end)

exports('Notify', function(data)
    TriggerEvent("nyx:ui:notify", data)
end)

exports('PlaySound', function(soundKey, customBank)
    Nyx.UI.PlaySound(soundKey, customBank)
end)
