--[[
    Nyxframework: nyx_judiciary
    File: client/exports.lua
    Description: Client export wrappers for forensic status and courtroom interaction.
]]

exports("IsForensicActive", function()
    return IsForensicActive and IsForensicActive() or false
end)

exports("GetCourtroomCenter", function()
    return Config.Courtroom and Config.Courtroom.InteriorCenter or vector3(-545.2, -203.8, 38.2)
end)

exports("PerformForensicSwab", function(targetServerId, swabType)
    return PerformForensicSwab and PerformForensicSwab(targetServerId, swabType) or false
end)

exports("CapturePhotoEvidence", function(cameraName, notes)
    return CapturePhotoEvidence and CapturePhotoEvidence(cameraName, notes) or false
end)

exports("VerifyChainOfCustody", function(evidenceId)
    return ClientVerifyChainOfCustody and ClientVerifyChainOfCustody(evidenceId) or false
end)

exports("OpenCourtTerminal", function(activeTab)
    if OpenCourtTerminal then
        OpenCourtTerminal(activeTab)
        return true
    end
    return false
end)

exports("CloseCourtTerminal", function()
    if exports['nyx_ui'] and exports['nyx_ui'].CloseCourtTerminal then
        exports['nyx_ui']:CloseCourtTerminal()
        return true
    end
    return false
end)

-- Penal Labor Client Exports
exports("GetNearestPenalWorkstation", function()
    local ws, dist = exports['nyx_judiciary']:GetNearestPenalWorkstation()
    return ws, dist
end)

exports("IsPerformingLabor", function()
    return exports['nyx_judiciary']:IsPerformingLabor()
end)

exports("GetCachedPenalOverview", function()
    return exports['nyx_judiciary']:GetCachedPenalOverview()
end)
