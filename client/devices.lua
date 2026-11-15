-- blaze_bossmenu | GNU GPL v3 (see LICENSE) | based on qbx_management by the Qbox Project (see NOTICE.md)
-- The Boss Menu app on sd-phone, which sd-tablet shows too (config.lua > devices.phone).
-- sd-computers registers on the server (server/devices.lua). Both use the page in web/apps/.
if not Config.enabled then return end

local RES = GetCurrentResourceName()
local D = Config.devices or {}
if D.phone == false then return end

--- Only players in a configured job get the app (sd-phone gates by job); the app shows only what they manage
local function jobs()
    local out, any = {}, false
    for name in pairs(Config.jobs or {}) do out[name] = 0 any = true end
    return any and out or nil
end

local function register()
    if GetResourceState('sd-phone') ~= 'started' then return end
    local ok, err = pcall(function()
        return exports['sd-phone']:addCustomApp({
            identifier = 'blaze_bossmenu',
            name = D.label or 'Boss Menu',
            description = 'Staff, applications, funds and activity for the jobs you manage.',
            developer = 'Blaze Scriptworks',
            defaultApp = true, -- pre-installed, no App Store download
            ui = RES .. '/web/apps/phone.html',
            icon = ('https://cfx-nui-%s/web/apps/icon.svg'):format(RES),
            jobs = jobs(),
        })
    end)
    if not ok then print(('^3[blaze_bossmenu]^7 Couldn\'t add the Boss Menu app to sd-phone: %s'):format(err)) end
end

-- sd-phone keeps apps in memory: register once it's up, and again whenever it restarts
CreateThread(function()
    local tries = 0
    while GetResourceState('sd-phone') ~= 'started' and tries < 120 do Wait(500) tries = tries + 1 end
    Wait(1000)
    register()
end)
AddEventHandler('onResourceStart', function(res)
    if res ~= 'sd-phone' then return end
    Wait(1000)
    register()
end)

-- The page's fetchNui('bm:call', { name, args }) -> the same server checks as the boss menu
RegisterNUICallback('bm:call', function(d, cb)
    d = type(d) == 'table' and d or {}
    local r = lib.callback.await(RES .. ':deviceCall', false, d.name, d.args)
    cb(type(r) == 'table' and r or { ok = false, msg = 'The server didn\'t answer.' })
end)
