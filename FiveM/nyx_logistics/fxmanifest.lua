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
    'nyx_treasury',
    'nyx_vehicles'
}

shared_scripts {
    '@nyx_core/shared/math.lua',
    '@nyx_vehicles/shared/tolls_and_weighing.lua',
    'config.lua',
    'shared/zones.lua',
    'shared/nodes.lua',
    'shared/recipes.lua',
    'shared/pallets.lua',
    'shared/assembly.lua',
    'shared/contracts.lua',
    'shared/warehouses.lua',
    'shared/market_monitor.lua',
    'shared/retail_shelves.lua',
    'shared/refining.lua',
    '@nyx_factions/shared/storage_networks.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua',
    'server/zones.lua',
    'server/nodes.lua',
    'server/facilities.lua',
    'server/refining.lua',
    'server/pallets.lua',
    'server/shelves.lua',
    'server/retail_shelves.lua',
    'server/contracts.lua',
    'server/warehouses.lua',
    'server/market_monitor.lua',
    'server/exports.lua'
}

client_scripts {
    'client/zones.lua',
    'client/harvesting.lua',
    'client/pallets.lua',
    'client/contracts.lua',
    'client/warehouses.lua',
    'client/market_monitor.lua',
    'client/retail_shelves.lua',
    'client/refining.lua',
    'client/main.lua',
    'client/exports.lua'
}

files {
    'sql/migrations/*.sql'
}
