--[[
    Nyxframework: nyx_mdt
    File: client/main.lua
    Description: Client command handling, key mapping, and master SPA terminal bridge.
]]

Nyx = Nyx or {}
Nyx.MDT = Nyx.MDT or {}

-- Open MDT Command
RegisterCommand("mdt", function()
    if not exports['nyx_core'] or not exports['nyx_core'].TriggerRPCAwait then return end

    local data = exports['nyx_core']:TriggerRPCAwait("mdt:getDashboard")
    if data and data.success then
        exports['nyx_ui']:SetFocus(true, true)
        exports['nyx_ui']:Send("mdt", "MDT_OPEN", data)
    else
        TriggerEvent("nyx:ui:notify", {
            type = "error",
            title = "HOZZÁFÉRÉS MEGTAGADVA",
            message = "Nincs jogosultságod a hatósági MDT rendszer megnyitásához."
        })
    end
end, false)

-- Register hotkey for MDT (F6 keybind)
RegisterKeyMapping("mdt", "Open Emergency MDT", "keyboard", "F6")
