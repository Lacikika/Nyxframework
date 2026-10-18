--[[
    Nyxframework: nyx_mdt
    File: server/exports.lua
    Description: Public server exports for triggering 911 calls and issuing citations.
]]

exports('CreateCall', function(code, title, description, caller, coords, locationLabel, priority)
    return Nyx.MDT.CreateCall(code, title, description, caller, coords, locationLabel, priority)
end)

exports('GetActiveCalls', function()
    return Nyx.MDT.ActiveCalls
end)

exports('CreateDispatchWarning', function(payload)
    return Nyx.MDT.CreateDispatchWarning(payload)
end)

exports('RecordRadarDetection', function(plate, model, speedMph, coords, citizenId)
    return Nyx.MDT.RecordRadarDetection(plate, model, speedMph, coords, citizenId)
end)

exports('GetActiveWarnings', function()
    return Nyx.MDT.ActiveWarnings
end)

exports('GetRadarZones', function()
    return Nyx.MDT.RadarZones
end)

