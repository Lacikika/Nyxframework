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
    'config.lua',
    'shared/irv.lua',
    'shared/legislation_ui.lua',
    'shared/elections.lua',
    'shared/campaign_finance.lua',
    'shared/statutory_enforcement.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/statutes.lua',
    'server/enactment.lua',
    'server/elections.lua',
    'server/campaign_finance.lua',
    'server/polling.lua',
    'server/tabulation.lua',
    'server/voting.lua',
    'server/main.lua',
    'server/exports.lua'
}

client_scripts {
    'client/booths.lua',
    'client/legislation_ui.lua',
    'client/polling.lua',
    'client/pacs.lua',
    'client/main.lua',
    'client/exports.lua'
}

files {
    'sql/migrations/*.sql'
}
