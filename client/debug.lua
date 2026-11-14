-- blaze_bossmenu | GNU GPL v3 (see LICENSE) | based on qbx_management by the Qbox Project (see NOTICE.md)
-- Debug (like Blaze Medical's): the live panel (web/debug.html) for admins who turned debug on
-- (/bossdebug, or Debug mode in /bossmenu). Point labels are drawn by client/placement.lua (Show zones).
if not Config.enabled then return end

local RES = GetCurrentResourceName()
local TYPE_LABEL = { boss = 'Boss desk', applications = 'Applications point', review = 'Review point', duty = 'Duty point', outfits = 'Wardrobe' }

-- this player's debug view (state bag set by the server); kept in a local so the change handler can start the panel
local isViewing = LocalPlayer.state.bossDebugView == true
local function viewing() return isViewing end

-- last few boss menu actions (sent by the server while you're viewing), also printed to F8
local log = {}
RegisterNetEvent(RES .. ':client:debugLog', function(entry)
    if type(entry) ~= 'table' then return end
    table.insert(log, 1, { name = entry.name, result = entry.result, ms = entry.ms })
    if #log > 6 then log[7] = nil end
    print(('^5[blaze_bossmenu:debug]^7 %s -> %s  %.1f ms'):format(entry.name, entry.result, entry.ms or 0))
end)

local function groupLabel(gtype, name)
    local c = (gtype == 'gang' and (Config.gangs or {}) or Config.jobs)[name] or {}
    return c.label or name
end

--- What the live panel shows, refreshed 4 times a second
local function liveData()
    local ped = cache.ped
    local pd = Bridge.PlayerData()
    local job = pd.job or {}
    local manages, member, admin = {}, {}, false
    if BMC and BMC.mine then
        local groups, mem, isAdmin = BMC.mine()
        for _, g in ipairs(groups or {}) do manages[#manages + 1] = ('%s (%s)'):format(g.name, g.label) end
        for k in pairs(mem or {}) do member[#member + 1] = k:gsub('^job:', ''):gsub('^gang:', 'gang ') end
        admin = isAdmin == true
    end
    table.sort(member)

    local pos = GetEntityCoords(ped)
    local nearby, nearest = 0, nil
    for _, p in ipairs(BMC and BMC.points and BMC.points() or {}) do
        local d = #(pos - vec3(p.coords.x, p.coords.y, p.coords.z))
        if d < 30.0 then
            nearby = nearby + 1
            if not nearest or d < nearest.dist then
                nearest = { id = p.id, type = TYPE_LABEL[p.type] or p.type, group = groupLabel(p.gtype, p.group), dist = d, radius = p.radius or 1.0 }
            end
        end
    end

    return {
        job = job.name or 'unemployed', grade = job.grade and job.grade.level or 0, gradeName = job.grade and job.grade.name or nil,
        duty = job.onduty == true, admin = admin, global = GlobalState.bossmenuDebug == true or Config.debug == true,
        viewAs = BMC and BMC.viewAsLabel or nil,
        manages = manages, member = member,
        framework = Bridge.framework == 'qbx' and 'Qbox' or (Bridge.framework == 'qb' and 'QBCore' or 'unknown'),
        target = Bridge.target or '?', ui = (UI and UI.lation) and 'Lation UI' or 'ox_lib',
        nearby = nearby, nearest = nearest, log = log,
        pos = { x = pos.x, y = pos.y, z = pos.z, h = GetEntityHeading(ped) },
    }
end

-- live panel: 4 times a second while the debug view is on; no loop at all otherwise
local panelRunning = false
local function startPanel()
    if panelRunning then return end
    panelRunning = true
    CreateThread(function()
        while isViewing do
            SendNUIMessage({ action = 'dbg:live', data = liveData() })
            Wait(250)
        end
        SendNUIMessage({ action = 'dbg:live', data = false })
        panelRunning = false
    end)
end
AddStateBagChangeHandler('bossDebugView', ('player:%s'):format(cache.serverId), function(_, _, value)
    isViewing = value == true
    if isViewing then startPanel() end
end)
if isViewing then startPanel() end

-- Move mode (/bossdebug move): drag the panel; the spot is remembered on this PC
local movingPanel = false
RegisterNetEvent(RES .. ':client:debugMove', function()
    if not viewing() then
        return lib.notify({ title = 'Debug', description = 'Turn debug on first, so the panel is on screen.', type = 'inform' })
    end
    movingPanel = true
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'dbg:move' })
end)
RegisterNUICallback('dbg:moveDone', function(_, cb)
    cb(1)
    if movingPanel then movingPanel = false SetNuiFocus(false, false) end
end)
AddEventHandler('onResourceStop', function(res)
    if res == RES and movingPanel then SetNuiFocus(false, false) end
end)

TriggerEvent('chat:addSuggestion', '/' .. (Config.debugCommand or 'bossdebug'), 'Boss menu debug (admin)', {
    { name = 'mode', help = 'on, off, view (just your panel) or move (move and resize your panel)' },
})
