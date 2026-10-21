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
    '@nyx_core/shared/math.lua',
    '@nyx_treasury/shared/degradation.lua',
    '@nyx_parliament/shared/statutory_enforcement.lua',
    'config.lua',
    'shared/registration.lua',
    'shared/diagnostics.lua',
    'shared/fuel.lua',
    'shared/keys.lua',
    'shared/tolls_and_weighing.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/damage.lua',
    'server/wear.lua',
    'server/keys.lua',
    'server/impound.lua',
    'server/registration.lua',
    'server/diagnostics.lua',
    'server/fuel.lua',
    'server/tolls_and_weighing.lua',
    'server/spawner.lua',
    'server/main.lua',
    'server/exports.lua'
}

client_scripts {
    'client/keys.lua',
    'client/storage.lua',
    'client/sync.lua',
    'client/wear.lua',
    'client/impound.lua',
    'client/diagnostics.lua',
    'client/fuel.lua',
    'client/speedometer.lua',
    'client/tolls_and_weighing.lua',
    'client/main.lua',
    'client/exports.lua'
}

dependencies {
    'oxmysql',
    'nyx_core',
    'nyx_inventory',
    'nyx_treasury',
    'nyx_parliament'
}
