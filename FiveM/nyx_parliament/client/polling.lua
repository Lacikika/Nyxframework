--[[
    Nyxframework: nyx_parliament
    File: client/polling.lua
    Description: Client-side Citizen OS mobile opinion survey notification handlers & NUI bridge.
]]

Nyx = Nyx or {}
Nyx.Parliament = Nyx.Parliament or {}

-- New Mobile Poll Broadcast Handler
RegisterNetEvent("nyx:parliament:client:newMobilePoll", function(pollData)
    if type(pollData) == "table" then
        TriggerEvent("nyx:core:client:notify",
            string.format("CITIZEN OS POLL: New mobile opinion survey: '%s'. Open Smartphone to respond.", pollData.title or "Public Poll"),
            "info"
        )
    end
end)

-- Submit Mobile Poll Response via RPC
function Nyx.Parliament.SubmitMobilePollResponse(pollId, selectedOption)
    local voterHash = string.format("hw_%d_%s", GetGameTimer(), tostring(GetPlayerServerId(PlayerId())))
    local res = Nyx.RPC.Call("parliament:submitPollResponse", {
        pollId = pollId,
        selectedOption = selectedOption,
        voterHash = voterHash
    })
    return res
end

-- Export for Citizen OS Smartphone UI
exports('SubmitMobilePollResponse', function(pollId, selectedOption)
    return Nyx.Parliament.SubmitMobilePollResponse(pollId, selectedOption)
end)
