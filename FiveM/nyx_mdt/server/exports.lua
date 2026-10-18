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
