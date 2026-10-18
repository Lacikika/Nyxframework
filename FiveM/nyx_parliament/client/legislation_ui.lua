--[[
    Nyxframework: nyx_parliament
    File: client/legislation_ui.lua
    Description: Ranked-choice voting interface, active session explorer, and NUI bridge.
]]

Nyx = Nyx or {}
Nyx.Parliament = Nyx.Parliament or {}
Nyx.Parliament.IsOpen = false

-- Open Ranked-Choice Ballot & Legislation Interface
function Nyx.Parliament.OpenVotingUI()
    if Nyx.Parliament.IsOpen then return end

    CreateThread(function()
        local ok, sessions = pcall(function()
            return exports['nyx_core']:TriggerRPCAwait("parliament:getActiveSessions")
        end)

        if not ok or not sessions then
            print("^1[Nyx:Parliament] Failed to retrieve active legislative sessions.^7")
            return
        end

        local okLaws, laws = pcall(function()
            return exports['nyx_core']:TriggerRPCAwait("parliament:getLawBook", "ALL")
        end)

        local okPenal, penal = pcall(function()
            return exports['nyx_core']:TriggerRPCAwait("parliament:getPenalCode")
        end)

        local okOfficials, officials = pcall(function()
            return exports['nyx_core']:TriggerRPCAwait("parliament:getOfficials")
        end)

        Nyx.Parliament.IsOpen = true
        SetNuiFocus(true, true)
        SendNUIMessage({
            action = "OPEN_PARLIAMENT_UI",
            sessions = sessions,
            laws = okLaws and laws or {},
            penalCode = okPenal and penal or {},
            officials = okOfficials and officials or {}
        })
    end)
end

-- Close Interface
function Nyx.Parliament.CloseVotingUI()
    if not Nyx.Parliament.IsOpen then return end
    Nyx.Parliament.IsOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({
        action = "CLOSE_PARLIAMENT_UI"
    })
end

-- NUI Handlers
RegisterNUICallback("close", function(_, cb)
    Nyx.Parliament.CloseVotingUI()
    cb("ok")
end)

RegisterNUICallback("castBallot", function(payload, cb)
    CreateThread(function()
        local sessionId = payload and payload.sessionId
        local preferences = payload and payload.preferences or {}

        local result = exports['nyx_core']:TriggerRPCAwait("parliament:castBallot", sessionId, preferences)
        cb(result or { success = false, error = "NETWORK_ERROR" })
    end)
end)

RegisterNUICallback("proposeBill", function(payload, cb)
    CreateThread(function()
        local result = exports['nyx_core']:TriggerRPCAwait("parliament:proposeBill", payload)
        cb(result or { success = false, error = "NETWORK_ERROR" })
    end)
end)

RegisterNUICallback("verifyReceipt", function(payload, cb)
    CreateThread(function()
        local sessionId = payload and payload.sessionId
        local receiptHash = payload and payload.receiptHash

        local result = exports['nyx_core']:TriggerRPCAwait("parliament:verifyReceipt", sessionId, receiptHash)
        cb(result or { verified = false })
    end)
end)

RegisterNUICallback("registerCandidate", function(payload, cb)
    CreateThread(function()
        local result = exports['nyx_core']:TriggerRPCAwait("parliament:registerCandidate", payload)
        cb(result or { success = false, error = "NETWORK_ERROR" })
    end)
end)

RegisterNUICallback("endorseCandidate", function(payload, cb)
    CreateThread(function()
        local candidateId = payload and payload.candidateId
        local result = exports['nyx_core']:TriggerRPCAwait("parliament:endorseCandidate", candidateId)
        cb(result or { success = false, error = "NETWORK_ERROR" })
    end)
end)

RegisterNUICallback("getCandidates", function(payload, cb)
    CreateThread(function()
        local sessionId = payload and payload.sessionId
        local result = exports['nyx_core']:TriggerRPCAwait("parliament:getCandidates", sessionId)
        cb(result or {})
    end)
end)

RegisterNUICallback("fileRecallPetition", function(payload, cb)
    CreateThread(function()
        local result = exports['nyx_core']:TriggerRPCAwait("parliament:fileRecallPetition", payload)
        cb(result or { success = false, error = "NETWORK_ERROR" })
    end)
end)

RegisterNUICallback("signRecallPetition", function(payload, cb)
    CreateThread(function()
        local petitionId = payload and payload.petitionId
        local result = exports['nyx_core']:TriggerRPCAwait("parliament:signRecallPetition", petitionId)
        cb(result or { success = false, error = "NETWORK_ERROR" })
    end)
end)
