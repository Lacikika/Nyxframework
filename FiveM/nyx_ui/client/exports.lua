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

exports('OpenFactionDashboard', function(data)
    Nyx.UI.SetFocus(true, true)
    Nyx.UI.Send("faction", "FACTION_DASHBOARD_OPEN", data or {})
end)

exports('CloseFactionDashboard', function()
    Nyx.UI.SetFocus(false, false)
    Nyx.UI.Send("faction", "FACTION_DASHBOARD_CLOSE", {})
end)

exports('OpenCourtTerminal', function(data)
    Nyx.UI.SetFocus(true, true)
    Nyx.UI.Send("court", "COURT_TERMINAL_OPEN", data or {})
end)

exports('CloseCourtTerminal', function()
    Nyx.UI.SetFocus(false, false)
    Nyx.UI.Send("court", "COURT_TERMINAL_CLOSE", {})
end)

exports('OpenParliamentUI', function(data)
    Nyx.UI.SetFocus(true, true)
    Nyx.UI.Send("parliament", "PARLIAMENT_UI_OPEN", data or {})
end)

exports('CloseParliamentUI', function()
    Nyx.UI.SetFocus(false, false)
    Nyx.UI.Send("parliament", "PARLIAMENT_UI_CLOSE", {})
end)

exports('OpenPropertyPortal', function(data)
    Nyx.UI.SetFocus(true, true)
    Nyx.UI.Send("property", "PROPERTY_PORTAL_OPEN", data or {})
end)

exports('ClosePropertyPortal', function()
    Nyx.UI.SetFocus(false, false)
    Nyx.UI.Send("property", "PROPERTY_PORTAL_CLOSE", {})
end)

exports('OpenMarketMonitorUI', function(data)
    Nyx.UI.SetFocus(true, true)
    Nyx.UI.Send("logistics", "LOGISTICS_MATRIX_OPEN", data or {})
end)

exports('CloseMarketMonitorUI', function()
    Nyx.UI.SetFocus(false, false)
    Nyx.UI.Send("logistics", "LOGISTICS_MATRIX_CLOSE", {})
end)

exports('OpenVehicleTerminalUI', function(data)
    Nyx.UI.SetFocus(true, true)
    Nyx.UI.Send("vehicle", "VEHICLE_TERMINAL_OPEN", data or {})
end)

exports('CloseVehicleTerminalUI', function()
    Nyx.UI.SetFocus(false, false)
    Nyx.UI.Send("vehicle", "VEHICLE_TERMINAL_CLOSE", {})
end)

exports('OpenPhone', function(initialApp)
    if Nyx.UI.OpenPhone then
        Nyx.UI.OpenPhone(initialApp)
    else
        Nyx.UI.SetFocus(true, true)
        Nyx.UI.Send("phone", "PHONE_OPEN", { initialApp = initialApp or "home" })
    end
end)

exports('ClosePhone', function()
    if Nyx.UI.ClosePhone then
        Nyx.UI.ClosePhone()
    else
        Nyx.UI.SetFocus(false, false)
        Nyx.UI.Send("phone", "PHONE_CLOSE", {})
    end
end)

exports('TogglePhone', function(initialApp)
    if Nyx.UI.TogglePhone then
        Nyx.UI.TogglePhone(initialApp)
    else
        Nyx.UI.SetFocus(true, true)
        Nyx.UI.Send("phone", "PHONE_OPEN", { initialApp = initialApp or "home" })
    end
end)

exports('OpenView', function(viewName, data)
    if viewName == "phone" or viewName == "smartphone" or viewName == "citizenphone" or viewName == "mobile" then
        if Nyx.UI.OpenPhone then
            Nyx.UI.OpenPhone(data and data.initialApp)
        else
            Nyx.UI.SetFocus(true, true)
            Nyx.UI.Send("phone", "PHONE_OPEN", data or {})
        end
        return true
    elseif viewName == "faction_commerce_terminal" or viewName == "corporate" or viewName == "factions" or viewName == "union" then
        Nyx.UI.SetFocus(true, true)
        Nyx.UI.Send("faction", "FACTION_DASHBOARD_OPEN", data or {})
        return true
    elseif viewName == "court" or viewName == "courtroom" or viewName == "judiciary" then
        Nyx.UI.SetFocus(true, true)
        Nyx.UI.Send("court", "COURT_TERMINAL_OPEN", data or {})
        return true
    elseif viewName == "parliament" or viewName == "voting" or viewName == "ballot" or viewName == "election" or viewName == "legislation" or viewName == "penalcode" then
        Nyx.UI.SetFocus(true, true)
        Nyx.UI.Send("parliament", "PARLIAMENT_UI_OPEN", data or {})
        return true
    elseif viewName == "property" or viewName == "properties" or viewName == "realestate" or viewName == "auction" or viewName == "auctions" or viewName == "stewardship" then
        Nyx.UI.SetFocus(true, true)
        Nyx.UI.Send("property", "PROPERTY_PORTAL_OPEN", data or {})
        return true
    elseif viewName == "market" or viewName == "market_monitor" or viewName == "warehouse_matrix" or viewName == "matrix" or viewName == "logistics_monitor" then
        Nyx.UI.SetFocus(true, true)
        Nyx.UI.Send("logistics", "LOGISTICS_MATRIX_OPEN", data or {})
        return true
    elseif viewName == "vehicle" or viewName == "vehicles" or viewName == "diagnostics" or viewName == "mechanic" or viewName == "impound" or viewName == "impounds" then
        Nyx.UI.SetFocus(true, true)
        Nyx.UI.Send("vehicle", "VEHICLE_TERMINAL_OPEN", data or {})
        return true
    elseif viewName == "freight_board" then
        Nyx.UI.SetFocus(true, true)
        Nyx.UI.Send("freight", "FREIGHT_BOARD_OPEN", data or {})
        return true
    elseif viewName == "treasury" then
        Nyx.UI.SetFocus(true, true)
        Nyx.UI.Send("treasury", "TREASURY_DASHBOARD_OPEN", data or {})
        return true
    elseif viewName == "mdt" then
        Nyx.UI.SetFocus(true, true)
        Nyx.UI.Send("mdt", "MDT_OPEN", data or {})
        return true
    end
    return false
end)

