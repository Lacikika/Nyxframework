fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'nyx_ui'
author 'Nyxframework Team'
description 'Unified Master SPA Shell, NUI Transport Bridge, Central Audio & Citizen OS Master Smartphone Subsystem'
version '1.0.0'

ui_page 'web/index.html'

files {
    'web/index.html',
    'web/css/app.css',
    'web/js/app.js'
}

shared_scripts {
    'shared/phone.lua',
    '@nyx_treasury/shared/public_ledger.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/phone.lua',
    'server/exports.lua'
}

client_scripts {
    'config.lua',
    'shared/phone.lua',
    'client/bridge.lua',
    'client/phone.lua',
    'client/hud.lua',
    'client/audio.lua',
    'client/exports.lua',
    'client/main.lua'
}

dependencies {
    'oxmysql',
    'nyx_core',
    'nyx_treasury',
    'nyx_logistics',
    'nyx_mdt'
}
