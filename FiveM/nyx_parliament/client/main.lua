--[[
    Nyxframework: nyx_parliament
    File: client/main.lua
    Description: Parliament client lifecycle, law update broadcasts, and civic announcements.
]]

Nyx = Nyx or {}
Nyx.Parliament = Nyx.Parliament or {}

-- Law Amendment Real-Time Notification
RegisterNetEvent("nyx:parliament:client:lawsUpdated", function(actions)
    TriggerEvent("nyx:core:client:notify",
        string.format("CIVIC ALERT: Parliament has ratified %d statutory amendments. Penal and fiscal codes updated.", #actions),
        "info"
    )
end)

-- Session Concluded Broadcast
RegisterNetEvent("nyx:parliament:client:sessionConcluded", function(sessionId, winner)
    TriggerEvent("nyx:core:client:notify",
        string.format("ELECTION UPDATE: Session '%s' concluded! Certified Outcome: %s", sessionId, tostring(winner)),
        "success"
    )
end)

-- New Session Posted Broadcast
RegisterNetEvent("nyx:parliament:client:newSessionPosted", function(sessionId, title)
    TriggerEvent("nyx:core:client:notify",
        string.format("CIVIC BALLOT: New voting session opened: '%s'. Visit any voting booth to cast your ballot.", title),
        "info"
    )
end)

-- Official Instated Broadcast
RegisterNetEvent("nyx:parliament:client:officialInstated", function(data)
    TriggerEvent("nyx:core:client:notify",
        string.format("ELECTION ANNOUNCEMENT: %s has been sworn in as %s (%d-day term)!",
            data.displayName or "A citizen", data.title or data.officeId, data.termDays or 30),
        "success"
    )
end)

-- Official Recalled Broadcast
RegisterNetEvent("nyx:parliament:client:officialRecalled", function(officeId)
    TriggerEvent("nyx:core:client:notify",
        string.format("CIVIC NOTICE: Citizens have recalled the official holding office '%s'. Office vacated.", tostring(officeId):upper()),
        "warning"
    )
end)
