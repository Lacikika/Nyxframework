fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'nyx_ui'
author 'Nyxframework Team'
description 'Unified Master SPA Shell, NUI Transport Bridge & Central Audio Subsystem'
version '1.0.0'

ui_page 'web/index.html'

files {
    'web/index.html',
    'web/css/app.css',
    'web/js/app.js'
}

client_scripts {
    'config.lua',
    'client/bridge.lua',
    'client/hud.lua',
    'client/audio.lua',
    'client/exports.lua',
    'client/main.lua'
}

dependencies {
    'nyx_core'
}
