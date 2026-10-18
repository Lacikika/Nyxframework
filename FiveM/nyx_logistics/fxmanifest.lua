fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'nyx_logistics'
author 'Nyxframework Collective'
description 'Zero-Sum Supply Chain, Industrial Manufacturing & Logistics Engine'
version '1.0.0'

dependencies {
    'oxmysql',
    'nyx_core',
    'nyx_inventory',
    'nyx_treasury'
}

shared_scripts {
    'config.lua',
    'shared/nodes.lua',
    'shared/recipes.lua',
    'shared/contracts.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua',
    'server/nodes.lua',
    'server/facilities.lua',
    'server/shelves.lua',
    'server/contracts.lua',
    'server/exports.lua'
}

client_scripts {
    'client/harvesting.lua',
    'client/pallets.lua',
    'client/contracts.lua',
    'client/main.lua',
    'client/exports.lua'
}

files {
    'sql/migrations/*.sql'
}
