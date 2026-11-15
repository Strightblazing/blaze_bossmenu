-- blaze_bossmenu | GNU GPL v3 (see LICENSE) | based on qbx_management by the Qbox Project (see NOTICE.md)
-- Startup banner + version check (same style as Blaze Medical).
-- The banner prints once everything has loaded (called from server/main.lua), so it means "fully started".
-- The check reads 'repository' from fxmanifest.lua ('owner/name' on GitHub) and compares this version with
-- the latest GitHub release. Turn it off with versionCheck = false in config.lua.
if not Config.enabled then return end

local RES = GetCurrentResourceName()
local VERSION = GetResourceMetadata(RES, 'version', 0) or '0.0.0'
local REPO = GetResourceMetadata(RES, 'repository', 0)

local DISCORD = 'https://discord.gg/u6b6nCDJMa' -- Blaze Scriptworks: support and updates

local TAGLINES = {
    'Desk cleared, coffee poured.', 'Applications open for business.', 'Payroll balanced.', 'Rosters up to date.',
    'Interview room is ready.', 'The boss is in.', 'Clipboards at the ready.', 'Now hiring.',
}

-- '1.2.10' vs '1.2.9' -> 1 / 0 / -1 (a leading 'v' is ignored)
local function compare(a, b)
    local function parts(v)
        local t = {}
        for n in tostring(v):gsub('^v', ''):gmatch('%d+') do t[#t + 1] = tonumber(n) end
        return t
    end
    local x, y = parts(a), parts(b)
    for i = 1, math.max(#x, #y) do
        local p, q = x[i] or 0, y[i] or 0
        if p ~= q then return p > q and 1 or -1 end
    end
    return 0
end

local WIDTH = 58
-- one boxed line: pads to WIDTH, ignoring colour codes (^1 etc) and counting characters, not bytes
local function boxed(text)
    local visible = text:gsub('%^%d', '')
    local len = (utf8 and utf8.len(visible)) or #visible
    return '^3|^7' .. text .. (' '):rep(math.max(0, WIDTH - len)) .. '^3|^7'
end

-- Blaze Scriptworks logo as console art: red flame with a white </>, white BLAZE, gold SCRIPTWORKS, red bar,
-- gold frame (^1 red, ^3 gold, ^7 white). Plain ASCII, so it lines up in any console. No image needed.
local FLAME = {
    [[^1      (     ]],
    [[^1     ) )    ]],
    [[^1    ( ( (   ]],
    [[^1   ) )/\ )  ]],
    [[^1  ( ^7</>^1 (   ]],
    [[^1   \____/   ]],
}
local WORD = {
    [[                                     ]],
    [[ ____   _         _     _____  _____ ]],
    [[| __ ) | |       / \   |__  / | ____|]],
    [[|  _ \ | |      / _ \    / /  |  _|  ]],
    [[| |_) || |___  / ___ \  / /_  | |___ ]],
    [[|____/ |_____|/_/   \_\/____| |_____|]],
}
local function logo()
    local out = {}
    for i = 1, #FLAME do out[#out + 1] = boxed('  ' .. FLAME[i] .. '^7' .. WORD[i]) end
    out[#out + 1] = boxed((' '):rep(22) .. '^3S C R I P T W O R K S^7')
    out[#out + 1] = boxed((' '):rep(14) .. '^1' .. ('='):rep(37) .. '^7')
    return out
end

local function targetName()
    local want = Config.target or 'auto'
    if want ~= 'auto' then return want == 'none' and 'walk-up [E]' or want end
    if GetResourceState('ox_target') == 'started' then return 'ox_target' end
    if GetResourceState('qb-target') == 'started' then return 'qb-target' end
    return 'walk-up [E]'
end

local function check()
    if Config.versionCheck == false then return end
    if type(REPO) ~= 'string' or not REPO:match('^[%w%-_%.]+/[%w%-_%.]+$') then
        print('^3[blaze_bossmenu]^7 Version check is off: set repository \'owner/name\' in fxmanifest.lua to turn it on.')
        return
    end
    PerformHttpRequest(('https://api.github.com/repos/%s/releases/latest'):format(REPO), function(status, body)
        local latest = status == 200 and body and (json.decode(body) or {}).tag_name
        if not latest then
            print('^3[blaze_bossmenu]^7 Couldn\'t check for updates right now. No worries, everything still works.')
            return
        end
        local c = compare(VERSION, latest)
        if c == 0 then
            print(('^2[blaze_bossmenu] Blaze Boss Menu is up to date (v%s). %s^7'):format(VERSION, TAGLINES[math.random(#TAGLINES)]))
        elseif c < 0 then
            print(('^3[blaze_bossmenu] Update available: %s (you have v%s). Get it at https://github.com/%s/releases/latest^7'):format(latest, VERSION, REPO))
        else
            print(('^5[blaze_bossmenu]^7 Running v%s, newer than the latest release (%s). Dev build?'):format(VERSION, latest))
        end
    end, 'GET', '', { ['User-Agent'] = 'blaze_bossmenu', ['Accept'] = 'application/vnd.github+json' })
end

--- Print the "fully started" banner. stats = { jobs, gangs, points }
function StartupBanner(stats)
    local fw = Bridge.framework == 'qb' and 'QBCore' or 'Qbox'
    local ui = (Config.useLationUI and GetResourceState('lation_ui') == 'started') and 'Lation UI' or 'ox_lib'
    local bank = Banking.resource() or 'no banking'
    local line = '^3+' .. ('-'):rep(WIDTH) .. '+^7'
    print(line)
    for _, l in ipairs(logo()) do print(l) end
    print(boxed(''))
    print(boxed(('  ^7BOSS MENU ^1v%s^7  ·  %s · %s · %s'):format(VERSION, fw, targetName(), ui)))
    print(boxed(('  %d jobs · %d gangs · %d points · %s'):format(stats.jobs or 0, stats.gangs or 0, stats.points or 0, bank)))
    print(boxed('  ^2Fully started.^7 ' .. TAGLINES[math.random(#TAGLINES)]))
    print(boxed('  ^3Discord (support + updates):^7 ' .. DISCORD:gsub('^https://', '')))
    print(line)
    check()
end
