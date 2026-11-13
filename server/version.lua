-- Startup banner + version check (same style as Blaze Medical).
-- The banner prints once everything has loaded (called from server/main.lua), so it means "fully started".
-- The check reads 'repository' from fxmanifest.lua ('owner/name' on GitHub) and compares this version with
-- the latest GitHub release. Turn it off with versionCheck = false in config.lua.
if not Config.enabled then return end

local RES = GetCurrentResourceName()
local VERSION = GetResourceMetadata(RES, 'version', 0) or '0.0.0'
local REPO = GetResourceMetadata(RES, 'repository', 0)

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

local WIDTH = 52
-- one boxed line: pads to WIDTH, ignoring colour codes (^1 etc) and counting characters, not bytes
local function boxed(text)
    local visible = text:gsub('%^%d', '')
    local len = (utf8 and utf8.len(visible)) or #visible
    return '^1|^7' .. text .. (' '):rep(math.max(0, WIDTH - len)) .. '^1|^7'
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
    local line = '^1+' .. ('-'):rep(WIDTH) .. '+^7'
    print(line)
    print(boxed(('  ^1+^7 BLAZE BOSS MENU  ^1v%s^7'):format(VERSION)))
    print(boxed(('    %s · %s · %s'):format(fw, targetName(), ui)))
    print(boxed(('    %d jobs · %d gangs · %d points · %s'):format(stats.jobs or 0, stats.gangs or 0, stats.points or 0, bank)))
    print(boxed('    ^2Fully started.^7 ' .. TAGLINES[math.random(#TAGLINES)]))
    print(line)
    check()
end
