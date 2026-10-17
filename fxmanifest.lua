fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'duo-rewards'
description 'Twitch & Kick stream tracking, referral system, interval rewards and leaderboards for QBCore'
author 'Duo Development'
version '1.1.0'

shared_scripts {
    'config.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua',
    'server/twitch.lua',
    'server/referrals.lua',
    'server/rewards.lua',
}

client_scripts {
    'client/main.lua',
}

ui_page 'nui/index.html'

files {
    'nui/index.html',
    'nui/css/style.css',
    'nui/js/app.js',
}

dependencies {
    'qb-core',
    'oxmysql',
    'ox_inventory',
}
