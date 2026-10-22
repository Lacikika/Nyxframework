--[[
    Nyxframework: nyx_services
    File: fxmanifest.lua
    Description: Resource manifest for civil infrastructure, regional power grids,
                 metered public utility billing, and supply-dependent healthcare.
]]

fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'Nyxframework Team'
description 'Civil Infrastructure, Regional Power Grids, Utility Billing & Healthcare'
version '1.0.0'

shared_scripts {
    '@nyx_treasury/shared/degradation.lua',
    'config.lua',
    'shared/trauma.lua',
    'shared/medical.lua',
    'shared/agriculture.lua',
    'shared/sabotage.lua',
    'shared/metering.lua',
    'shared/hospital_beds.lua',
    'shared/chemical_labs.lua',
    'shared/water_utility.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/powergrid.lua',
    'server/sabotage.lua',
    'server/billing.lua',
    'server/medical.lua',
    'server/trauma.lua',
    'server/beds.lua',
    'server/chemlabs.lua',
    'server/agriculture.lua',
    'server/repair_stations.lua',
    'server/water_utility.lua',
    'server/main.lua',
    'server/exports.lua'
}

client_scripts {
    'client/blackout.lua',
    'client/substations.lua',
    'client/sabotage.lua',
    'client/metering.lua',
    'client/repair_stations.lua',
    'client/trauma.lua',
    'client/beds.lua',
    'client/chemlabs.lua',
    'client/agriculture.lua',
    'client/water_utility.lua',
    'client/main.lua',
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
    'nyx_logistics'
}
