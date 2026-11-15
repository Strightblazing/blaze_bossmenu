-- blaze_bossmenu | GNU GPL v3 (see LICENSE) | based on qbx_management by the Qbox Project (see NOTICE.md)
fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'blaze_bossmenu'
author 'Blaze'
description 'Boss menu, job applications, time clock and employment contracts for any job (Qbox / QBCore, ox_lib)'
version '1.2.3'
license 'GPL-3.0' -- fork of qbx_management by the Qbox Project (see LICENSE and NOTICE.md)
repository 'Strightblazing/blaze_bossmenu' -- used by the startup version check (server/version.lua)

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'bridge/server/framework.lua',
    'bridge/server/banking.lua',
    'server/logs.lua',
    'server/version.lua',
    'server/main.lua',
    'server/features.lua', -- extras (profiles, records, bonuses, ...): needs server/main.lua first
    'server/test.lua',     -- /bossmenutest (admins)
}

client_scripts {
    'bridge/client/framework.lua',
    'client/ui.lua',       -- UI wrapper: must load before client/main.lua
    'client/features.lua', -- extras (profiles, /myjob, /jobs, celebrations, receptionist)
    'client/main.lua',
    'client/placement.lua',
    'client/admin.lua',    -- /bossmenuadmin: admin tools (needs client/main.lua and client/placement.lua first)
    'client/test.lua',
    'client/debug.lua',   -- live debug panel (/bossdebug)
}

-- Web screens: web/index.html hosts the employment contract (signed with the mouse), the time clock, the debug panel and the placement card
ui_page 'web/index.html'
files {
    'web/index.html',
    'web/contract.html',
    'web/timeclock.html',
    'web/debug.html',
    'web/place.html',
}

-- ox_target / qb-target / lation_ui are optional and detected at runtime
dependencies {
    'ox_lib',
    'oxmysql',
}
