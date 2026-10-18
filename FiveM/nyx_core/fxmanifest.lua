fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'nyx_core'
author 'Nyxframework Collective'
description 'Ultra-Optimized Authoritative Core Kernel'
version '1.0.0'

shared_scripts {
    'config.lua',
    'shared/math.lua',
    'shared/rpc.lua',
    'shared/weights.lua',
    'shared/bootloader.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/bootloader.lua',
    'server/migrations.lua',
    'server/rpc.lua',
    'server/player.lua',
    'server/buckets.lua',
    'server/main.lua',
    'server/exports.lua',
    'server/tests.lua'
}

client_scripts {
    'client/rpc.lua',
    'client/spawn.lua',
    'client/main.lua',
    'client/movement.lua',
    'client/exports.lua'
}

files {
    'sql/migrations/*.sql',
    'sql/migrations/*.json'
}
