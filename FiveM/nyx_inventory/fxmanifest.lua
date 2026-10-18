fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'nyx_inventory'
author 'Nyxframework Collective'
description 'Ultra-Optimized Authoritative Dynamic Storage & Item Engine'
version '1.0.0'

dependencies {
    'oxmysql',
    'nyx_core'
}

shared_scripts {
    '@nyx_core/shared/math.lua',
    'config.lua',
    'shared/items.lua',
    'shared/drops.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/mutex.lua',
    'server/state.lua',
    'server/drops.lua',
    'server/actions.lua',
    'server/main.lua',
    'server/exports.lua'
}

client_scripts {
    'client/placement.lua',
    'client/drops.lua',
    'client/main.lua',
    'client/exports.lua'
}

files {
    'sql/migrations/*.sql'
}
