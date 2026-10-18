fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'nyx_parliament'
author 'Nyxframework Collective'
description 'Autonomous Civic Governance, Ranked-Choice Tabulation & Legislative Engine'
version '1.0.0'

dependencies {
    'oxmysql',
    'nyx_core',
    'nyx_treasury'
}

shared_scripts {
    'config.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/statutes.lua',
    'server/enactment.lua',
    'server/tabulation.lua',
    'server/voting.lua',
    'server/main.lua',
    'server/exports.lua'
}

client_scripts {
    'client/booths.lua',
    'client/legislation_ui.lua',
    'client/main.lua',
    'client/exports.lua'
}

files {
    'sql/migrations/*.sql'
}
