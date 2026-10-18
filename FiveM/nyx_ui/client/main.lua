--[[
    Nyxframework: nyx_ui
    File: client/main.lua
    Description: Resource lifecycle initialization, SPA ready handshake, and input escapes.
]]

Nyx = Nyx or {}
Nyx.UI = Nyx.UI or {}
Nyx.UI.IsReady = false

-- Handshake from CEF Web Frame with Guaranteed Callback Resolution
if Nyx.UI.SafeNUICallback then
    Nyx.UI.SafeNUICallback("uiReady", function(_, cb)
        Nyx.UI.IsReady = true
        if Config.Debug then
            print("^2[Nyx:UI] Master Single Page Application shell successfully mounted.^7")
        end
        TriggerEvent("nyx:ui:client:ready")
        cb({ success = true })
    end)
else
    RegisterNUICallback("uiReady", function(_, cb)
        Nyx.UI.IsReady = true
        if Config.Debug then
            print("^2[Nyx:UI] Master Single Page Application shell successfully mounted.^7")
        end
        TriggerEvent("nyx:ui:client:ready")
        cb({ success = true })
    end)
end

-- Escape Key Fallback for Closing Focused Interfaces
RegisterCommand("nyx_ui_escape", function()
    if not IsPauseMenuActive() then
        Nyx.UI.SetFocus(false, false)
        Nyx.UI.Send("core", "ESCAPE_KEY", {})
    end
end, false)

RegisterKeyMapping("nyx_ui_escape", "Close Active Interface", "keyboard", "ESCAPE")

-- On Resource Stop: Ensure cursor and focus are released cleanly (Lifecycle Failsafe)
local function ResetAllNuiFocus()
    SetNuiFocus(false, false)
    SetNuiFocusKeepInput(false)
end

AddEventHandler("onResourceStop", function(resName)
    if resName == GetCurrentResourceName() then
        ResetAllNuiFocus()
    end
end)

AddEventHandler("onClientResourceStop", function(resName)
    if resName == GetCurrentResourceName() then
        ResetAllNuiFocus()
    end
end)
