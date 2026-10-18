--[[
    Nyxframework: nyx_ui
    File: client/phone.lua
    Description: Client runtime controller, keybind registration, and lifecycle management
                 for the Citizen OS Master Smartphone Framework.
]]

Nyx = Nyx or {}
Nyx.UI = Nyx.UI or {}
Nyx.UI.PhoneOpen = false

-- Open Smartphone Overlay
function Nyx.UI.OpenPhone(initialApp)
    if IsPauseMenuActive() then return end
    Nyx.UI.PhoneOpen = true
    Nyx.UI.SetFocus(true, true)
    Nyx.UI.Send("phone", "PHONE_OPEN", {
        initialApp = initialApp or "home"
    })
    if Nyx.UI.PlaySound then
        Nyx.UI.PlaySound("open")
    end
end

-- Close Smartphone Overlay
function Nyx.UI.ClosePhone()
    if not Nyx.UI.PhoneOpen then return end
    Nyx.UI.PhoneOpen = false
    Nyx.UI.SetFocus(false, false)
    Nyx.UI.Send("phone", "PHONE_CLOSE", {})
    if Nyx.UI.PlaySound then
        Nyx.UI.PlaySound("close")
    end
end

-- Toggle Smartphone Overlay
function Nyx.UI.TogglePhone(initialApp)
    if Nyx.UI.PhoneOpen then
        Nyx.UI.ClosePhone()
    else
        Nyx.UI.OpenPhone(initialApp)
    end
end

-- Commands
RegisterCommand("phone", function(_, args)
    local targetApp = args and args[1]
    Nyx.UI.TogglePhone(targetApp)
end, false)

RegisterCommand("smartphone", function(_, args)
    local targetApp = args and args[1]
    Nyx.UI.TogglePhone(targetApp)
end, false)

RegisterCommand("citizenphone", function(_, args)
    local targetApp = args and args[1]
    Nyx.UI.TogglePhone(targetApp)
end, false)

-- Register Default Keybinding (F1)
RegisterKeyMapping("phone", "Megnyitás: Citizen OS Okostelefon", "keyboard", "F1")

-- Incoming Citizen Emergency Alert Broadcast Listener
RegisterNetEvent("nyx:phone:client:emergencyAlert", function(alertData)
    if not alertData then return end

    -- Send incoming notification to HUD / Phone
    Nyx.UI.Send("phone", "PHONE_NOTIFICATION", alertData)

    -- If phone is not focused, trigger non-intrusive HUD toast
    TriggerEvent("nyx:ui:notify", {
        type = (alertData.priority == "critical" or alertData.priority == "high") and "error" or "warning",
        title = string.format("RIASZTÁS: %s", (alertData.category or "911"):upper()),
        message = string.format("[%s] %s", alertData.location or "Ismeretlen", alertData.message or "Nincs részlet"),
        duration = 6000
    })

    if Nyx.UI.PlaySound then
        Nyx.UI.PlaySound("beep")
    end
end)
