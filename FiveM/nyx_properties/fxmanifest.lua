--[[
    Nyxframework: nyx_properties
    File: fxmanifest.lua
    Description: Real estate registry, 5-tier RFID locks, virtual routing buckets,
                 utility meter integration, progressive millage taxes, dynamic land
                 maintenance taxation, and municipal foreclosure auction reclamation.
]]

fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'nyx_properties'
author 'Nyxframework Collective'
description 'Authoritative Real Estate, Progressive Millage Taxes, Land Maintenance & Foreclosure Auctions'
version '1.1.0'

shared_scripts {
    'config.lua',
    'shared/taxation.lua',
    'shared/inactivity.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua',
    'server/locks.lua',
    'server/taxation.lua',
    'server/auction.lua',
    'server/inactivity.lua',
    'server/billing.lua',
    'server/exports.lua'
}

client_scripts {
    'client/main.lua',
    'client/locks.lua',
    'client/taxation.lua',
    'client/inactivity.lua',
    'client/interact.lua',
    'client/exports.lua'
}

files {
    'sql/migrations/*.sql'
}

dependencies {
    'oxmysql',
    'nyx_core',
    'nyx_inventory',
    'nyx_treasury',
    'nyx_services',
    'nyx_interact'
}
