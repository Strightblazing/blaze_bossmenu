fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'blaze_bossmenu'
author 'Blaze'
description 'Boss menu + job applications for any job (Qbox / QBCore, ox_lib, optional Lation UI)'
version '1.0.0'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'bridge/server/framework.lua',
    'bridge/server/banking.lua',
    'server/logs.lua',
    'server/main.lua',
}

client_scripts {
    'bridge/client/framework.lua',
    'client/ui.lua',      -- UI wrapper: must load before client/main.lua
    'client/main.lua',
    'client/placement.lua',
}

-- ox_target / qb-target / lation_ui are optional and detected at runtime
dependencies {
    'ox_lib',
    'oxmysql',
}
