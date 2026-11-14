-- blaze_bossmenu | GNU GPL v3 (see LICENSE) | based on qbx_management by the Qbox Project (see NOTICE.md)
-- /bossmenu (admins): place boss desks, application, review, duty and wardrobe points in game.
-- Managers get the same tools for their own job in the boss menu (Locations). The server checks every action.
if not Config.enabled then return end

local RES = GetCurrentResourceName()
local function call(name, ...) return lib.callback.await(('%s:%s'):format(RES, name), false, ...) end
local function result(ok, msg) lib.notify({ title = 'Boss menu placement', description = msg or (ok and 'Done.' or 'Failed.'), type = ok and 'success' or 'error' }) return ok end

local TYPE_LABEL = { boss = 'Boss desk', applications = 'Applications point', review = 'Application review point', duty = 'Duty point', outfits = 'Wardrobe' }
local TYPE_ICON = { boss = 'fa-solid fa-briefcase', applications = 'fa-solid fa-file-signature', review = 'fa-solid fa-clipboard-check', duty = 'fa-solid fa-clock', outfits = 'fa-solid fa-shirt' }
local TYPE_DESC = {
    boss = 'Managers open the boss menu here', applications = 'Anyone can apply here', review = 'Managers review applications here',
    duty = 'Staff clock in and out here', outfits = 'Staff change into job outfits here',
}

--- Can this point type exist for this group? (mirrors the server check)
local function typeFits(g, ptype)
    if ptype == 'applications' or ptype == 'review' then return g.apps == true end
    if ptype == 'duty' then return g.gtype == 'job' and (Config.duty or {}).enabled == true end
    if ptype == 'outfits' then return (Config.outfits or {}).enabled == true end
    return ptype == 'boss'
end
local openPlacement

--- Raycast marker where the player looks. E = confirm, Backspace = cancel. Returns coords, heading or nil.
local function placeMarker(text)
    lib.showTextUI(('%s  \n[E] Place  \n[Backspace] Cancel'):format(text))
    local chosen
    while true do
        Wait(0)
        DisableControlAction(0, 38, true)  -- E
        DisableControlAction(0, 177, true) -- Backspace / cancel
        DisableControlAction(0, 194, true)
        local hit, _, coords = lib.raycast.fromCamera(1 | 16, cache.ped, 15.0)
        if hit and coords then
            DrawMarker(28, coords.x, coords.y, coords.z, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.25, 0.25, 0.25, 61, 220, 132, 160, false, false, 2, false, nil, nil, false)
            if IsDisabledControlJustPressed(0, 38) then chosen = coords break end
        end
        if IsDisabledControlJustPressed(0, 177) or IsDisabledControlJustPressed(0, 194) then break end
    end
    lib.hideTextUI()
    if not chosen then return nil end
    return chosen, GetEntityHeading(cache.ped)
end

local function addFlow(info, ptype)
    local options = {}
    for _, g in ipairs(info.groups) do
        if typeFits(g, ptype) then -- e.g. no application points when applications are off
            options[#options + 1] = {
                title = g.label, description = (g.gtype == 'gang' and 'Gang · ' or 'Job · ') .. g.name, arrow = true,
                onSelect = function()
                    local coords, heading = placeMarker(('%s · %s'):format(TYPE_LABEL[ptype], g.label))
                    if coords then
                        local v = UI.input('Point size', { { type = 'number', label = 'Radius (0.5 - 5.0 m)', default = 1.0, min = 0.5, max = 5.0, required = true } })
                        result(call('addPoint', g.gtype, g.name, ptype, { x = coords.x, y = coords.y, z = coords.z }, heading, v and v[1] or 1.0))
                    end
                    openPlacement()
                end,
            }
        end
    end
    if #options == 0 then options[1] = { title = 'No configured groups', description = 'Add jobs/gangs in config.lua', readOnly = true } end
    UI.registerMenu({ id = 'blaze_boss_place_pick', title = 'Add ' .. TYPE_LABEL[ptype]:lower(), menu = 'blaze_boss_place', options = options })
    UI.showMenu('blaze_boss_place_pick')
end

--- Teleport / Move / Change size / Delete for one point. after() reopens the list. teleport = allowed?
local function pointActions(p, groupLabel, backMenu, after, teleport)
    local fixed = p.fixed == 'config' and 'From config.lua (can\'t be changed in game)'
        or p.fixed == 'script' and 'Added by another script (can\'t be changed in game)' or nil
    local title = ('%s · %s'):format(groupLabel, TYPE_LABEL[p.type] or p.type)
    local options = {}
    if teleport then
        options[#options + 1] = { title = 'Teleport', icon = 'fa-solid fa-location-arrow', onSelect = function()
            SetEntityCoords(cache.ped, p.coords.x, p.coords.y, p.coords.z, false, false, false, false)
        end }
    end
    options[#options + 1] = { title = 'Set waypoint', icon = 'fa-solid fa-map-pin', onSelect = function()
        SetNewWaypoint(p.coords.x, p.coords.y)
        result(true, 'Waypoint set.')
    end }
    options[#options + 1] = { title = 'Move', icon = 'fa-solid fa-up-down-left-right', disabled = p.fixed ~= nil,
      description = fixed or 'Aim at the new spot and press E. Same job, type and size.', onSelect = function()
        local coords, heading = placeMarker('Move: ' .. title)
        if coords then result(call('movePoint', p.id, { x = coords.x, y = coords.y, z = coords.z }, heading)) end
        after()
    end }
    options[#options + 1] = { title = 'Change size', icon = 'fa-solid fa-expand', disabled = p.fixed ~= nil,
      description = fixed or ('Now %.1f m'):format(p.radius or 1.0), onSelect = function()
        local v = UI.input('Point size', { { type = 'number', label = 'Radius (0.5 - 5.0 m)', default = p.radius or 1.0, min = 0.5, max = 5.0, required = true } })
        if v and v[1] then result(call('resizePoint', p.id, v[1])) end
        after()
    end }
    options[#options + 1] = { title = 'Delete', icon = 'fa-solid fa-trash', iconColor = '#E5484D', disabled = p.fixed ~= nil,
      description = fixed, onSelect = function()
        if UI.confirm({ header = 'Delete point', content = 'Delete this point? It disappears for everyone.', type = 'error', confirm = 'Delete' }) then
            result(call('removePoint', p.id))
        end
        after()
    end }
    UI.registerMenu({ id = 'blaze_boss_place_point', title = title, menu = backMenu, options = options })
    UI.showMenu('blaze_boss_place_point')
end

local function manageFlow(info)
    local byGroup, order = {}, {}
    local labels = {}
    for _, g in ipairs(info.groups) do labels[g.gtype .. ':' .. g.name] = g.label end
    for _, p in ipairs(info.points) do
        local k = p.gtype .. ':' .. p.group
        if not byGroup[k] then byGroup[k] = {} order[#order + 1] = k end
        table.insert(byGroup[k], p)
    end
    table.sort(order, function(a, b) return (labels[a] or a) < (labels[b] or b) end)

    local options = {}
    for _, k in ipairs(order) do
        for _, p in ipairs(byGroup[k]) do
            local fixed = p.fixed == 'config' and 'From config.lua (can\'t be changed in game)'
                or p.fixed == 'script' and 'Added by another script (can\'t be changed in game)' or nil
            options[#options + 1] = {
                title = ('%s · %s'):format(labels[k] or k, TYPE_LABEL[p.type] or p.type),
                description = fixed or ('#%s · %.1f, %.1f, %.1f'):format(p.id, p.coords.x, p.coords.y, p.coords.z),
                icon = TYPE_ICON[p.type] or 'fa-solid fa-location-dot', arrow = true,
                onSelect = function()
                    pointActions(p, labels[k] or k, 'blaze_boss_place_list', openPlacement, true)
                end,
            }
        end
    end
    if #options == 0 then options[1] = { title = 'No points yet', readOnly = true } end
    UI.registerMenu({ id = 'blaze_boss_place_list', title = 'Manage points', menu = 'blaze_boss_place', options = options })
    UI.showMenu('blaze_boss_place_list')
end

openPlacement = function()
    local info = call('getPlacementInfo')
    if not info then return result(false, 'Admins only.') end
    UI.registerMenu({
        id = 'blaze_boss_place', title = 'Boss menu placement',
        options = {
            { title = 'Add boss desk', description = 'Managers open the boss menu here', icon = 'fa-solid fa-briefcase', arrow = true, onSelect = function() addFlow(info, 'boss') end },
            { title = 'Add applications point', description = 'Anyone can apply here', icon = TYPE_ICON.applications, arrow = true, onSelect = function() addFlow(info, 'applications') end },
            { title = 'Add application review point', description = 'Managers review that job\'s applications here', icon = TYPE_ICON.review, arrow = true, onSelect = function() addFlow(info, 'review') end },
            { title = 'Add duty point', description = TYPE_DESC.duty, icon = TYPE_ICON.duty, arrow = true, disabled = not (Config.duty or {}).enabled, onSelect = function() addFlow(info, 'duty') end },
            { title = 'Add wardrobe', description = TYPE_DESC.outfits, icon = TYPE_ICON.outfits, arrow = true, disabled = not (Config.outfits or {}).enabled, onSelect = function() addFlow(info, 'outfits') end },
            { title = 'Manage points', description = ('%d points'):format(#info.points), icon = 'fa-solid fa-list', arrow = true, onSelect = function() manageFlow(info) end },
            { title = 'Show zones: ' .. (BMC.zonesShown() and 'On' or 'Off'), icon = 'fa-solid fa-draw-polygon',
              description = 'Draw every point on the ground with a label (only you see it)', onSelect = function()
                BMC.setShowZones(not BMC.zonesShown() and 'all' or false)
                openPlacement()
            end },
            { title = 'Debug mode: ' .. (BMC.debugOn() and 'On' or 'Off'), icon = 'fa-solid fa-bug',
              description = 'Point ids / radius / distance, and your actions logged to F8 and the server console', onSelect = function()
                BMC.setDebug(not BMC.debugOn())
                openPlacement()
            end },
        },
    })
    UI.showMenu('blaze_boss_place')
end

RegisterNetEvent(RES .. ':client:placement', function() openPlacement() end)

TriggerEvent('chat:addSuggestion', '/bossmenu', 'Place boss desks, duty, wardrobe and application points (admin)')

---------------------------------------------------------------------------
-- Boss menu > Locations: a manager's own job's points (Config.managerPlacement)
---------------------------------------------------------------------------
BMC.placeMarker = placeMarker

function BMC.openLocations(m)
    local d = call('getGroupPoints', m.gtype, m.name)
    if not d then return result(false, 'You are not a manager here.') end
    local reopen = function() BMC.openLocations(m) end
    local teleport = m.isAdmin or (Config.managerPlacement or {}).teleport == true
    local key = m.gtype .. ':' .. m.name
    local options = {
        { title = 'Show zones: ' .. (BMC.zonesShown() and 'On' or 'Off'), icon = 'fa-solid fa-draw-polygon',
          description = ('Draw %s\'s points on the ground (only you see it)'):format(m.label), onSelect = function()
            BMC.setShowZones(not BMC.zonesShown() and { [key] = true } or false)
            reopen()
        end },
    }
    table.sort(d.types, function(a, b) return (TYPE_LABEL[a] or a) < (TYPE_LABEL[b] or b) end)
    for _, t in ipairs(d.types) do
        options[#options + 1] = { title = 'Add ' .. (TYPE_LABEL[t] or t):lower(), description = TYPE_DESC[t], icon = 'fa-solid fa-plus', onSelect = function()
            local coords, heading = placeMarker(('%s · %s'):format(TYPE_LABEL[t] or t, m.label))
            if coords then
                local v = UI.input('Point size', { { type = 'number', label = 'Radius (0.5 - 5.0 m)', default = 1.0, min = 0.5, max = 5.0, required = true } })
                result(call('addPoint', m.gtype, m.name, t, { x = coords.x, y = coords.y, z = coords.z }, heading, v and v[1] or 1.0))
            end
            reopen()
        end }
    end
    for _, p in ipairs(d.points) do
        options[#options + 1] = {
            title = TYPE_LABEL[p.type] or p.type, icon = TYPE_ICON[p.type] or 'fa-solid fa-location-dot', arrow = true,
            description = p.fixed and 'Set in config.lua' or ('%.0f m away'):format(#(GetEntityCoords(cache.ped) - vec3(p.coords.x, p.coords.y, p.coords.z))),
            onSelect = function() pointActions(p, m.label, 'blaze_boss_locations', reopen, teleport) end,
        }
    end
    if #d.points == 0 then options[#options + 1] = { title = 'No points yet', description = 'Use Add above, then aim and press E', readOnly = true } end
    UI.registerMenu({ id = 'blaze_boss_locations', title = 'Locations · ' .. m.label, menu = 'blaze_boss_main', options = options })
    UI.showMenu('blaze_boss_locations')
end

---------------------------------------------------------------------------
-- Show zones + debug mode
-- Show zones: every point drawn as a colored ring on the ground with a label (admins: all; managers: their job).
-- Debug mode (admins): labels also show id / radius / distance, and actions are logged to F8.
---------------------------------------------------------------------------
local zonePoints = {}
local showZones = false      -- false | 'all' | { ['job:ambulance'] = true }
-- debug: Config.debug, or this player's debug view (/bossdebug, or Debug mode in /bossmenu)
local function debugMode() return Config.debug == true or LocalPlayer.state.bossDebugView == true end

local ZONE_COLOR = {
    boss = { 245, 197, 66 }, applications = { 90, 169, 255 }, review = { 167, 139, 250 },
    duty = { 63, 185, 122 }, outfits = { 240, 169, 59 },
}

RegisterNetEvent(RES .. ':client:points', function(points) zonePoints = points or {} end)

local function draw3DText(x, y, z, text)
    SetDrawOrigin(x, y, z, 0)
    SetTextScale(0.0, 0.3)
    SetTextFont(4)
    SetTextCentre(true)
    SetTextOutline()
    SetTextColour(255, 255, 255, 230)
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayText(0.0, 0.0)
    ClearDrawOrigin()
end

local drawing = false
local function startDrawing()
    if drawing then return end
    drawing = true
    if #zonePoints == 0 then zonePoints = call('getPoints') or {} end
    CreateThread(function()
        while showZones or debugMode() do
            local me = GetEntityCoords(cache.ped)
            for _, p in ipairs(zonePoints) do
                local key = p.gtype .. ':' .. p.group
                if showZones == 'all' or debugMode() or (type(showZones) == 'table' and showZones[key]) then
                    local c = vec3(p.coords.x, p.coords.y, p.coords.z)
                    local dist = #(me - c)
                    if dist < 60.0 then
                        local col = ZONE_COLOR[p.type] or { 200, 200, 200 }
                        local r = (p.radius or 1.0) * 2.0
                        DrawMarker(1, c.x, c.y, c.z - 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, r, r, 1.4, col[1], col[2], col[3], 60, false, false, 2, false, nil, nil, false)
                        DrawMarker(28, c.x, c.y, c.z, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.12, 0.12, 0.12, col[1], col[2], col[3], 200, false, false, 2, false, nil, nil, false)
                        if dist < 25.0 then
                            local cfg = (p.gtype == 'gang' and (Config.gangs or {}) or Config.jobs)[p.group] or {}
                            local text = ('%s · %s'):format(TYPE_LABEL[p.type] or p.type, cfg.label or p.group)
                            if debugMode() then
                                text = text .. ('~n~#%s · r %.1f · %.1fm%s'):format(p.id, p.radius or 1.0, dist, p.fixed and (' · ' .. p.fixed) or '')
                            end
                            draw3DText(c.x, c.y, c.z + 0.35, text)
                        end
                    end
                end
            end
            Wait(0)
        end
        drawing = false
    end)
end

--- mode: false (off), 'all', or a table of group keys
function BMC.setShowZones(mode)
    showZones = mode
    if mode then startDrawing() end
end
function BMC.zonesShown() return showZones ~= false end

function BMC.setDebug(on)
    local ok, msg = call('setDebug', on)
    result(ok, msg)
end
function BMC.debugOn() return debugMode() end
--- Points (for the debug panel's "nearest point")
function BMC.points() return zonePoints end

-- start drawing labels whenever debug turns on (the state bag can change at any time)
CreateThread(function()
    while true do
        Wait(1000)
        if debugMode() and not drawing then startDrawing() end
    end
end)
