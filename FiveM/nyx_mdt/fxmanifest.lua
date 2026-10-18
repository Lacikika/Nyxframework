--[[
    Nyxframework: nyx_mdt
    File: fxmanifest.lua
    Description: Resource manifest for the Emergency Services Mobile Data Terminal & CAD system.
]]

fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'nyx_mdt'
author 'Nyxframework Collective'
description 'Zero-Polling Emergency Dispatch, CAD System, Criminal Records & Court Docket Viewer'
version '1.0.0'

shared_scripts {
    'config.lua',
    '@nyx_parliament/shared/statutory_enforcement.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua',
    'server/dispatch.lua',
    'server/records.lua',
    'server/exports.lua'
}

client_scripts {
    'client/main.lua',
    'client/dispatch.lua',
    'client/exports.lua'
}

files {
    'sql/migrations/*.sql'
}

dependencies {
    'oxmysql',
    'nyx_core',
    'nyx_ui',
    'nyx_treasury',
    'nyx_judiciary',
    'nyx_vehicles',
    'nyx_parliament'
}
