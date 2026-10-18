--[[
    Nyxframework: nyx_parliament
    File: client/legislation_ui.lua
    Description: Ranked-choice voting interface, active session explorer, and Master NUI bridge.
]]

Nyx = Nyx or {}
Nyx.Parliament = Nyx.Parliament or {}
Nyx.Parliament.IsOpen = false

-- Open Ranked-Choice Ballot & Legislation Interface
function Nyx.Parliament.OpenVotingUI(options)
    if Nyx.Parliament.IsOpen then return end

    options = options or {}
    CreateThread(function()
        -- Route through master nyx_ui single-frame CEF SPA if available
        if exports['nyx_ui'] and exports['nyx_ui'].OpenParliamentUI then
            Nyx.Parliament.IsOpen = true
            exports['nyx_ui']:OpenParliamentUI(options)
            return
        end

        -- Resilient fallback: Query data directly
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
            activeTab = options.activeTab or "ballot",
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

    if exports['nyx_ui'] and exports['nyx_ui'].CloseParliamentUI then
        exports['nyx_ui']:CloseParliamentUI()
    else
        SetNuiFocus(false, false)
        SendNUIMessage({
            action = "CLOSE_PARLIAMENT_UI"
        })
    end
end

-- Player & Console Chat Commands
RegisterCommand("parliament", function()
    Nyx.Parliament.OpenVotingUI({ activeTab = "ballot" })
end, false)

RegisterCommand("ballot", function()
    Nyx.Parliament.OpenVotingUI({ activeTab = "ballot" })
end, false)

RegisterCommand("vote", function()
    Nyx.Parliament.OpenVotingUI({ activeTab = "ballot" })
end, false)

RegisterCommand("penalcode", function()
    Nyx.Parliament.OpenVotingUI({ activeTab = "laws" })
end, false)

RegisterCommand("laws", function()
    Nyx.Parliament.OpenVotingUI({ activeTab = "laws" })
end, false)

-- Direct NUI Callbacks (preserved for backward compatibility)
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
