--[[
    Nyxframework: nyx_mdt
    File: config.lua
    Description: Mobile Data Terminal & CAD emergency dispatch configuration.
]]

Config = Config or {}
Config.Debug = true

Config.MDT = {
    AuthorizedJobs = {
        ['police'] = true,
        ['sheriff'] = true,
        ['state_police'] = true,
        ['ems'] = true,
        ['doj'] = true
    },
    TreasuryFinesAccount = "gov:dept:police", -- Account where collected court fines flow
    MaxActiveCalls = 50,
    DefaultFineLimit = 25000.00
}
