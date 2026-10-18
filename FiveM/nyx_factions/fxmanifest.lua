--[[
    Nyxframework: nyx_factions
    File: fxmanifest.lua
    Description: Resource manifest for autonomous player organizations, corporate charters,
                 granular RBAC, and multi-signature vaults.
]]

fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'Nyxframework Team'
description 'Autonomous Player Organizations, Granular RBAC & Multi-Sig Vaults'
version '1.0.0'

shared_scripts {
    'config.lua',
    'shared/unions.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/permissions.lua',
    'server/charter.lua',
    'server/vaults.lua',
    'server/multisig.lua',
    'server/dividends.lua',
    'server/unions.lua',
    'server/cba.lua',
    'server/fleet.lua',
    'server/main.lua',
    'server/exports.lua'
}

client_scripts {
    'client/terminals.lua',
    'client/fleet_depot.lua',
    'client/unions.lua',
    'client/main.lua',
    'client/exports.lua'
}

dependencies {
    'oxmysql',
    'nyx_core',
    'nyx_inventory',
    'nyx_treasury'
}
