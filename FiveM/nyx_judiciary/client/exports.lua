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
