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
    'config.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/ledger.lua',
    'server/taxes.lua',
    'server/payroll.lua',
    'server/main.lua',
    'server/exports.lua'
}

client_scripts {
    'client/terminals.lua',
    'client/main.lua',
    'client/exports.lua'
}

files {
    'sql/migrations/*.sql'
}
