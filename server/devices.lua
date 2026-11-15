-- blaze_bossmenu | GNU GPL v3 (see LICENSE) | based on qbx_management by the Qbox Project (see NOTICE.md)
-- The Boss Menu app on other devices (config.lua > devices):
--   * sd-computers: an app on the desktop (registered here, server side)
--   * sd-phone and sd-tablet: an app on the phone, which the tablet shows too (registered in client/devices.lua)
-- Both only ever run when that resource is started. The app's page is web/apps/ (one page for every device).
--
-- Security: the app can only call the actions listed in ALLOWED, with no more arguments than the boss menu itself
-- passes, and each one runs the same handler (and the same server checks) as the boss menu. getMenu is never
-- opened as admin from a device: admin access stays in /bossmenuadmin.
if not Config.enabled then return end

local RES = GetCurrentResourceName()
local D = Config.devices or {}

--- action -> how many arguments it takes (after the player)
local ALLOWED = {
    getMyJobs = 0, getMenu = 2, getStaff = 2,
    promote = 3, demote = 3, fire = 3, setCallsign = 4, hire = 4,
    getFunds = 2, deposit = 4, withdraw = 4,
    getApplications = 2, getApplication = 2, interview = 3, accept = 3, deny = 3, voteApplication = 3, toggleApplications = 1,
    getAnnouncement = 2, postAnnouncement = 3, getAudit = 2,
    getProfile = 3, addRecord = 5, setEmployeeOfWeek = 4, bonus = 6, getPayroll = 2, saveNote = 3, modifyGrade = 4,
}

--- Run one boss menu action for a player from a device. Returns { ok, a, b } (a, b = what the boss menu gets back).
function BM.deviceCall(src, name, args)
    local n = type(name) == 'string' and ALLOWED[name]
    if not n then return { ok = false, msg = 'That isn\'t available in the app.' } end
    local fn = BM.handlers and BM.handlers[name]
    if not fn then return { ok = false, msg = 'That isn\'t available on this server.' } end
    args = type(args) == 'table' and args or {}
    local a, b = fn(src, table.unpack(args, 1, n)) -- extra arguments are dropped (getMenu can't ask for admin access)
    return { ok = true, a = a, b = b }
end

-- Phones / tablets: the page asks through the client (client/devices.lua), which lands here
BM.register('deviceCall', function(src, name, args)
    if D.phone == false then return { ok = false, msg = 'The phone app is turned off.' } end
    return BM.deviceCall(src, name, args)
end)

--- Every configured job and gang, any rank: the app is on their desktop, and only shows what they manage
local function groups()
    local out = {}
    for name in pairs(Config.jobs or {}) do out[name] = 0 end
    for name in pairs(Config.gangs or {}) do out[name] = 0 end
    return out
end

---------------------------------------------------------------------------
-- sd-computers
---------------------------------------------------------------------------
local function registerComputer()
    if D.computers ~= true or GetResourceState('sd-computers') ~= 'started' then return end -- experimental: only when turned on
    local ok, err = exports['sd-computers']:AddCustomApp({
        id = 'blaze_bossmenu',
        label = D.label or 'Boss Menu',
        description = 'Staff, applications, funds and activity for the jobs you manage.',
        developer = 'Blaze Scriptworks',
        color = '#3B82F6',
        ui = RES .. '/web/apps/computer.html',
        icon = RES .. '/web/apps/icon.png', -- Blaze Scriptworks flame
        size = { w = 1040, h = 700 },
        pinned = D.pinned ~= false,
        -- the copy of the screen nearby players see on the desk prop: off by default (staff, funds and applications
        -- are private), which also stops the mirror's mouse trail drawing long lines across the screen
        mirror = D.mirrorScreen == true,
        groups = groups(),
        computers = D.computerIds, -- nil = every computer
        endpoints = {
            ['bm:call'] = function(source, data)
                local r = BM.deviceCall(source, type(data) == 'table' and data.name, type(data) == 'table' and data.args)
                if not r.ok then return false, r.msg end
                return r
            end,
        },
    })
    if ok then
        print('^5[blaze_bossmenu]^7 Boss Menu app added to sd-computers.')
    else
        print(('^3[blaze_bossmenu]^7 Couldn\'t add the Boss Menu app to sd-computers: %s'):format(err or 'unknown error'))
    end
end

-- sd-computers keeps apps in memory: register at its every (re)start, and once now if it's already running
AddEventHandler('sd-computers:ready', registerComputer)
CreateThread(function()
    Wait(2000)
    pcall(registerComputer)
end)
