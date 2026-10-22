--[[
    Nyxframework: nyx_parliament
    File: client/pacs.lua
    Description: Client-side Political Action Committee (PAC) interactions & campaign finance bridge.
]]

Nyx = Nyx or {}
Nyx.Parliament = Nyx.Parliament or {}

-- Donate to PAC Client Method
function Nyx.Parliament.DonateToPAC(pacId, amount, donorFactionId)
    local res = Nyx.RPC.Call("parliament:donateToPAC", {
        pacId = pacId,
        amount = amount,
        donorFactionId = donorFactionId
    })
    return res
end

-- Register PAC Client Method
function Nyx.Parliament.RegisterPAC(candidateId, officeId, title)
    local res = Nyx.RPC.Call("parliament:registerPAC", {
        candidateId = candidateId,
        officeId = officeId,
        title = title
    })
    return res
end

-- Exports
exports('DonateToPAC', function(pacId, amount, donorFactionId)
    return Nyx.Parliament.DonateToPAC(pacId, amount, donorFactionId)
end)

exports('RegisterPAC', function(candidateId, officeId, title)
    return Nyx.Parliament.RegisterPAC(candidateId, officeId, title)
end)
