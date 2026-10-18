--[[
    Nyxframework: nyx_press
    File: fxmanifest.lua
    Description: Resource manifest for decentralized media printing, encrypted whistleblower
                 dropboxes, and trade union media accreditation.
]]

fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'nyx_press'
author 'Nyxframework Collective'
description 'Decentralized Broadcast Printing, Whistleblower Dropboxes & Trade Union Media Accreditation'
version '1.0.0'

shared_scripts {
    'config.lua',
    'shared/press.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua',
    'server/press.lua',
    'server/exports.lua'
}

client_scripts {
    'client/main.lua',
    'client/press.lua',
    'client/interact.lua',
    'client/exports.lua'
}

files {
    'sql/migrations/*.sql'
}

dependencies {
    'oxmysql',
    'nyx_core',
    'nyx_treasury',
    'nyx_factions',
    'nyx_inventory',
    'nyx_interact'
}
