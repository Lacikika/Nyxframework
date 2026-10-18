--[[
    Nyxframework: nyx_vehicles
    File: fxmanifest.lua
    Description: Resource manifest for authoritative vehicle persistence, physical storage bindings,
                 damage serialization, and modular access keys.
]]

fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'Nyxframework Team'
description 'Persistent Vehicle Lifecycle, Damage Engine & Storage Bindings'
version '1.0.0'

shared_scripts {
    'config.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/damage.lua',
    'server/keys.lua',
    'server/spawner.lua',
    'server/main.lua',
    'server/exports.lua'
}

client_scripts {
    'client/keys.lua',
    'client/storage.lua',
    'client/sync.lua',
    'client/main.lua',
    'client/exports.lua'
}

dependencies {
    'oxmysql',
    'nyx_core',
    'nyx_inventory',
    'nyx_treasury'
}
