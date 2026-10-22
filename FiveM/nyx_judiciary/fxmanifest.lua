--[[
    Nyxframework: nyx_judiciary
    File: fxmanifest.lua
    Description: Resource manifest for the decentralized judiciary and forensic engine.
]]

fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'Nyxframework Team'
description 'Decentralized Judiciary, Immutable Forensic Chain-of-Custody & Automated Jury System'
version '1.0.0'

shared_scripts {
    'config.lua',
    'shared/jury.lua',
    'shared/warrants.lua',
    'shared/courtroom_ui.lua',
    'shared/penal_labor.lua',
    'shared/acid_etch.lua',
    'shared/bail_bonds.lua',
    'shared/ballistics.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/evidence.lua',
    'server/ballistics.lua',
    'server/dockets.lua',
    'server/warrants.lua',
    'server/jury.lua',
    'server/execution.lua',
    'server/penal_labor.lua',
    'server/acid_etch.lua',
    'server/bail.lua',
    'server/main.lua',
    'server/exports.lua'
}

client_scripts {
    'client/forensics.lua',
    'client/courtroom.lua',
    'client/penal_labor.lua',
    'client/acid_etch.lua',
    'client/bail.lua',
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

files {
    'sql/migrations/*.sql'
}
