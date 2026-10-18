fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'nyx_interact'
author 'Nyxframework Team'
description 'Spatial Raycasting Engine & Declarative Eye-Target Registry'
version '1.0.0'

client_scripts {
    '@nyx_core/shared/math.lua',
    'config.lua',
    'client/registry.lua',
    'client/raycast.lua',
    'client/exports.lua',
    'client/main.lua'
}

dependencies {
    'nyx_core',
    'nyx_ui'
}
