fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'nyx_treasury'
author 'Nyxframework Collective'
description 'Decentralized Public Finance & Double-Entry Ledger Engine'
version '1.0.0'

dependencies {
    'oxmysql',
    'nyx_core'
}

shared_scripts {
    'config.lua',
    'shared/circuit.lua',
    'shared/degradation.lua',
    '@nyx_factions/shared/laundering.lua',
    '@nyx_factions/shared/equity.lua',
    'shared/subpoena_audit.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/circuit.lua',
    'server/degradation.lua',
    'server/ledger.lua',
    'server/taxes.lua',
    'server/payroll.lua',
    'server/subpoena_audit.lua',
    'server/main.lua',
    'server/exports.lua'
}

client_scripts {
    'client/terminals.lua',
    'client/subpoena_audit.lua',
    'client/main.lua',
    'client/exports.lua'
}

files {
    'sql/migrations/*.sql'
}
