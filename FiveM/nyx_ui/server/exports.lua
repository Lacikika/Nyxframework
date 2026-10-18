--[[
    Nyxframework: nyx_ui
    File: server/exports.lua
    Description: Authoritative server exports for Citizen OS Smartphone Framework.
]]

-- Export: Retrieve citizen phone settings and metadata
exports('GetCitizenPhoneData', function(citizenId)
    if not citizenId then return nil end
    local row = MySQL.single.await([[
        SELECT `citizen_id`, `phone_number`, `wallpaper`, `dark_mode`, `airplane_mode`, `notifications_enabled`
        FROM `nyx_phone_settings`
        WHERE `citizen_id` = ?
    ]], { citizenId })
    return row
end)

-- Export: Dispatch public emergency broadcast to all online phones
exports('SendPublicEmergencyAlert', function(category, message, priority, locationLabel)
    category = category or "general"
    message = message or "Városi Biztonsági Figyelmeztetés"
    priority = priority or "high"
    locationLabel = locationLabel or "Los Santos"

    local alertUuid = exports['nyx_core'] and exports['nyx_core']:GenerateUUID() or string.format("alert_%d", os.time())
    local now = os.time()

    local alertId = MySQL.insert.await([[
        INSERT INTO `nyx_phone_emergency_alerts`
            (`alert_uuid`, `citizen_id`, `caller_name`, `category`, `message`, `location_label`, `priority`, `status`, `created_at`)
        VALUES (?, 'SYSTEM', 'KÖZÉRDEKŰ KÖZLÉNY', ?, ?, ?, ?, 'broadcasted', ?)
    ]], {
        alertUuid,
        category,
        message,
        locationLabel,
        priority,
        now
    })

    local badge = Nyx.Phone and Nyx.Phone.FormatAlertBadge(priority, category) or {
        priorityBadgeClass = "badge-danger",
        priorityLabel = priority:upper(),
        priorityIcon = "fa-solid fa-triangle-exclamation"
    }

    local alertPacket = {
        id = alertId,
        uuid = alertUuid,
        caller = "KÖZÉRDEKŰ KÖZLÉNY",
        category = category,
        message = message,
        location = locationLabel,
        priority = priority,
        createdAt = now,
        badge = badge
    }

    TriggerClientEvent("nyx:phone:client:emergencyAlert", -1, alertPacket)
    return alertId, alertUuid
end)
