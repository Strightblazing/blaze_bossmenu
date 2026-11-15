-- blaze_bossmenu | GNU GPL v3 (see LICENSE) | based on qbx_management by the Qbox Project (see NOTICE.md)
-- /bossmenuadmin (admins): place boss desks, application, review, duty and wardrobe points in game.
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

local ZONE_COLOR = {
    boss = { 245, 197, 66 }, applications = { 90, 169, 255 }, review = { 167, 139, 250 },
    duty = { 63, 185, 122 }, outfits = { 240, 169, 59 },
}

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

local MIN_R, MAX_R, STEP_R = 0.5, 5.0, 0.25
local function clampRadius(r) return math.max(MIN_R, math.min(MAX_R, math.floor((tonumber(r) or 1.0) / STEP_R + 0.5) * STEP_R)) end

--- Mouse wheel / arrow keys change the size: returns -1, 0 or 1 (weapon wheel and phone scroll are blocked meanwhile)
local function sizeInput()
    for _, c in ipairs({ 14, 15, 16, 17, 99, 100, 172, 173, 241, 242, 261, 262 }) do DisableControlAction(0, c, true) end
    if IsDisabledControlJustPressed(0, 241) or IsDisabledControlJustPressed(0, 15) or IsDisabledControlJustPressed(0, 172) then return 1 end
    if IsDisabledControlJustPressed(0, 242) or IsDisabledControlJustPressed(0, 14) or IsDisabledControlJustPressed(0, 173) then return -1 end
    return 0
end

--- The zone as it will be: ring at its real size in the type's colour, a center dot, a facing arrow and a label
local function drawPreview(c, ptype, radius, heading, label)
    local col = ZONE_COLOR[ptype] or { 61, 220, 132 }
    local d = radius * 2.0
    DrawMarker(1, c.x, c.y, c.z - 0.02, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, d, d, 0.6, col[1], col[2], col[3], 70, false, false, 2, false, nil, nil, false)
    DrawMarker(28, c.x, c.y, c.z + 0.05, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.12, 0.12, 0.12, col[1], col[2], col[3], 220, false, false, 2, false, nil, nil, false)
    if heading then -- which way you faced when placing it (the receptionist stands on that side, facing back)
        local rad = math.rad(heading)
        local tx, ty = c.x - math.sin(rad) * (radius + 0.6), c.y + math.cos(rad) * (radius + 0.6)
        DrawLine(c.x, c.y, c.z + 0.1, tx, ty, c.z + 0.1, col[1], col[2], col[3], 230)
        DrawMarker(28, tx, ty, c.z + 0.1, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.08, 0.08, 0.08, col[1], col[2], col[3], 230, false, false, 2, false, nil, nil, false)
    end
    if label then draw3DText(c.x, c.y, c.z + 1.0, label) end
end

--- What stands at a point: invisible, a PED or a prop (config.lua > pointLooks). Returns look (table),
--- false (invisible) or nil (cancelled). current = the point's look now (for "Change look").
local LOOKS = Config.pointLooks or {}
local function chooseLook(ptype, current)
    local peds, props, idles = { { value = 'custom', label = 'Custom model (below)' } }, { { value = 'custom', label = 'Custom model (below)' } }, { { value = 'none', label = 'Just stand' } }
    for i, m in ipairs(LOOKS.peds or {}) do table.insert(peds, i, { value = m.model, label = ('%s (%s)'):format(m.label or m.model, m.model) }) end
    for i, m in ipairs(LOOKS.props or {}) do table.insert(props, i, { value = m.model, label = ('%s (%s)'):format(m.label or m.model, m.model) }) end
    for i, a in ipairs(LOOKS.idles or {}) do idles[#idles + 1] = { value = tostring(i), label = a.label or a.scenario or (a.anim and a.anim.name) or ('Idle ' .. i) } end
    local kind = current and current.kind or (current == nil and ptype == 'applications' and 'ped' or 'none')
    local idleNow = 'none'
    if current and current.kind == 'ped' then
        for i, a in ipairs(LOOKS.idles or {}) do
            if (a.scenario and a.scenario == current.scenario) or (a.anim and current.anim and a.anim.name == current.anim.name) then idleNow = tostring(i) end
        end
    end
    local v = UI.input('What stands here?', {
        { type = 'select', label = 'Look', required = true, default = kind, options = {
            { value = 'none', label = 'Invisible point' }, { value = 'ped', label = 'PED (person)' }, { value = 'prop', label = 'Prop (object)' } } },
        { type = 'select', label = 'PED model', default = current and current.kind == 'ped' and current.model or (peds[1] and peds[1].value), options = peds },
        { type = 'select', label = 'PED idle', default = idleNow, options = idles },
        { type = 'select', label = 'Prop model', default = current and current.kind == 'prop' and current.model or (props[1] and props[1].value), options = props },
        { type = 'input', label = 'Custom model (optional)', placeholder = 'e.g. s_m_m_doctor_01 or prop_laptop_01a' },
    })
    if not v then return nil end
    if v[1] == 'none' then return false end
    local model = (v[5] and v[5] ~= '') and v[5] or (v[1] == 'ped' and v[2] or v[4])
    if not model or model == 'custom' then result(false, 'Pick a model or type a custom one.') return nil end
    model = tostring(model):gsub('%s', '')
    if not IsModelInCdimage(joaat(model)) then result(false, ('"%s" isn\'t a model in the game.'):format(model)) return nil end
    if v[1] == 'ped' and not IsModelAPed(joaat(model)) then result(false, ('"%s" isn\'t a PED model.'):format(model)) return nil end
    if v[1] == 'prop' and IsModelAPed(joaat(model)) then result(false, ('"%s" is a PED, not a prop.'):format(model)) return nil end
    local look = { kind = v[1], model = model }
    local idle = v[1] == 'ped' and (LOOKS.idles or {})[tonumber(v[3]) or 0]
    if idle then look.scenario, look.anim = idle.scenario, idle.anim end
    return look
end

--- The placement card (web/place.html): what you're placing, its size and the keys. Never takes the mouse.
-- While placing, moving or resizing, the game HUD and minimap are hidden so only the card shows (called every frame).
-- Custom HUD resources can hide too by listening to 'blaze_bossmenu:client:placing' (true when it starts, false when it ends).
local function hideHud() HideHudAndRadarThisFrame() end
local placing = false
local function setPlacing(on)
    if placing == on then return end
    placing = on
    TriggerEvent(RES .. ':client:placing', on)
    -- your HUD resource (config.lua > placementHud)
    if type(Config.placementHud) == 'function' then
        local ok, err = pcall(Config.placementHud, on)
        if not ok then print(('^3[blaze_bossmenu]^7 placementHud failed: %s'):format(err)) end
    end
end

-- Output toggle on the card (G): save the point in game, or just copy a config.lua line (Config.locations).
-- Remembered on this PC. A real key binding (Settings > Key Bindings > FiveM), only active while placing,
-- so it reacts to every press and G works normally the rest of the time.
local EXPORT_KVP = 'place_export'
local exportOn = GetResourceKvpInt(EXPORT_KVP) == 1
local exportKey = lib.addKeybind({
    name = 'blaze_bossmenu_place_output',
    description = 'Boss menu placement: switch Save in game / Copy config line',
    defaultKey = 'G',
    disabled = true,
    onPressed = function()
        exportOn = not exportOn
        SetResourceKvpInt(EXPORT_KVP, exportOn and 1 or 0)
        SendNUIMessage({ action = 'place:export', on = exportOn })
    end,
})
local function keyName()
    local ok, k = pcall(function() return exportKey:getCurrentKey() end)
    return (ok and k and k ~= '') and k or 'G'
end

local function cardShow(mode, ptype, title, group, radius, resize, canExport, rotate)
    setPlacing(true)
    SendNUIMessage({ action = 'place:show', mode = mode, type = ptype, title = title, group = group,
        color = ZONE_COLOR[ptype] or { 122, 162, 255 }, size = radius, resize = resize == true,
        canExport = canExport == true, exportOn = exportOn, exportKey = keyName(), rotate = rotate == true })
end
local function fmt(n) return ('%.2f'):format(n + 0.0) end
local function lookLua(look)
    if not look then return '' end
    local idle = look.scenario and (", scenario = '%s'"):format(look.scenario)
        or (look.anim and (", anim = { dict = '%s', name = '%s' }"):format(look.anim.dict, look.anim.name)) or ''
    return (", entity = { kind = '%s', model = '%s'%s }"):format(look.kind, look.model, idle)
end
local function exportPoint(e, coords, heading, radius, look)
    local line = ("{ %s = '%s', type = '%s', coords = vec3(%s, %s, %s), heading = %s, radius = %s%s },"):format(
        e.gtype == 'gang' and 'gang' or 'job', e.name, e.ptype, fmt(coords.x), fmt(coords.y), fmt(coords.z), fmt(heading), fmt(radius), lookLua(look))
    lib.setClipboard(line)
    print('^5[blaze_bossmenu]^7 config.lua > locations:  ' .. line)
    lib.notify({ title = 'Boss menu placement', description = 'Config line copied (also in F8). Paste it into config.lua > locations. Nothing was saved in game.', type = 'success', duration = 7000 })
end
local function cardSize(radius) SendNUIMessage({ action = 'place:size', size = radius }) end
local function cardHide() SendNUIMessage({ action = 'place:hide' }) setPlacing(false) end
AddEventHandler('onResourceStop', function(res) if res == RES then cardHide() end end)

--- Aim where the point goes and see it before placing.
--- opts = { ptype, radius, resize = true (wheel changes size), title, group, mode = 'place' | 'move',
---         look = PED / prop that stands there (see-through preview, rotate with arrow keys), heading = its start heading,
---         export = { gtype, name, ptype } (G switches to copying a config.lua line) }
--- E = place, Backspace = cancel. Returns coords, heading, radius (or nil). With export on it copies the line and returns nil.
--- The preview is spawned with the same code as the real thing (BMC.spawnLook / BMC.pointLook), so what you see is what you get.
local function placeMarker(text, opts)
    opts = opts or {}
    local radius = clampRadius(opts.radius or 1.0)
    local look = opts.look or nil
    cardShow(opts.mode or 'place', opts.ptype, opts.title or text, opts.group, radius, opts.resize, opts.export ~= nil, look ~= nil)
    if opts.export then exportKey:disable(false) end
    local aimOk = true
    local rot = opts.heading or ((GetEntityHeading(cache.ped) + 180.0) % 360.0) -- a PED / prop starts facing you
    local ghost, ghostTried = nil, false
    local pointHeading = GetEntityHeading(cache.ped)
    local lift, shownLift = 0.0, 0.0 -- Page Up / Page Down: raise or lower the point (and its PED / prop), -2 to +2 m
    local chosen
    while true do
        Wait(0)
        DisableControlAction(0, 38, true)  -- E
        DisableControlAction(0, 177, true) -- Backspace / cancel
        DisableControlAction(0, 194, true)
        if opts.resize then
            local dir = sizeInput()
            if dir ~= 0 then radius = clampRadius(radius + dir * STEP_R) cardSize(radius) end
        end
        hideHud()
        if opts.export then
            DisableControlAction(0, 47, true) -- G: no detonate / other G actions while placing (the toggle itself is the key binding)
            DisableControlAction(0, 58, true)
        end
        if look then -- arrow keys turn the PED / prop (hold to keep turning)
            DisableControlAction(0, 174, true)
            DisableControlAction(0, 175, true)
            if IsDisabledControlPressed(0, 174) then rot = (rot + 2.0) % 360.0 end
            if IsDisabledControlPressed(0, 175) then rot = (rot - 2.0) % 360.0 end
        end
        -- Page Up / Page Down: height (hold to keep moving, ~0.6 m a second)
        DisableControlAction(0, 10, true)
        DisableControlAction(0, 11, true)
        if IsDisabledControlPressed(0, 10) then lift = math.min(2.0, lift + 0.01) end
        if IsDisabledControlPressed(0, 11) then lift = math.max(-2.0, lift - 0.01) end
        local rounded = math.floor(lift * 100 + 0.5) / 100
        if rounded ~= shownLift then shownLift = rounded SendNUIMessage({ action = 'place:height', height = rounded }) end
        pointHeading = look and rot or GetEntityHeading(cache.ped)
        local hit, _, coords = lib.raycast.fromCamera(1 | 16, cache.ped, 15.0)
        local ok = (hit and coords) and true or false
        if ok ~= aimOk then aimOk = ok SendNUIMessage({ action = 'place:aim', ok = ok }) end
        if hit and coords then
            coords = vec3(coords.x, coords.y, coords.z + shownLift)
            drawPreview(coords, opts.ptype, radius, pointHeading) -- the card names it, so no 3D text
            -- see-through PED / prop exactly where the real one will stand (classic receptionist: behind the counter)
            local gl, gx, gy, gz, gh = BMC.pointLook({ entity = look, type = opts.ptype, coords = coords, heading = pointHeading })
            if gl and not ghostTried then ghostTried = true ghost = BMC.spawnLook(gl, gx, gy, gz, gh, true) end
            if ghost then BMC.setEntitySpot(ghost, gx, gy, gz, gh) end
            if IsDisabledControlJustPressed(0, 38) then chosen = coords break end
        elseif ghost then
            SetEntityCoordsNoOffset(ghost, 0.0, 0.0, -100.0, false, false, false)
        end
        if IsDisabledControlJustPressed(0, 177) or IsDisabledControlJustPressed(0, 194) then break end
    end
    if ghost and DoesEntityExist(ghost) then DeleteEntity(ghost) end
    exportKey:disable(true)
    cardHide()
    if not chosen then return nil end
    if opts.export and exportOn then
        exportPoint(opts.export, chosen, pointHeading, radius, look)
        return nil
    end
    return chosen, pointHeading, radius
end

--- Change a placed point's size with a live ring on the spot. Returns the new radius or nil.
local function sizeMarker(p, group)
    local c = vec3(p.coords.x, p.coords.y, p.coords.z)
    local radius = clampRadius(p.radius or 1.0)
    cardShow('size', p.type, TYPE_LABEL[p.type] or p.type, group, radius, true)
    local saved
    while true do
        Wait(0)
        DisableControlAction(0, 38, true)
        DisableControlAction(0, 177, true)
        DisableControlAction(0, 194, true)
        local dir = sizeInput()
        if dir ~= 0 then radius = clampRadius(radius + dir * STEP_R) cardSize(radius) end
        hideHud()
        drawPreview(c, p.type, radius, p.heading)
        if IsDisabledControlJustPressed(0, 38) then saved = radius break end
        if IsDisabledControlJustPressed(0, 177) or IsDisabledControlJustPressed(0, 194) then break end
        if #(GetEntityCoords(cache.ped) - c) > 40.0 then lib.notify({ title = 'Boss menu placement', description = 'Too far from the point.', type = 'error' }) break end
    end
    cardHide()
    return saved
end

local function addFlow(info, ptype)
    local options = {}
    for _, g in ipairs(info.groups) do
        if typeFits(g, ptype) then -- e.g. no application points when applications are off
            options[#options + 1] = {
                title = g.label, description = (g.gtype == 'gang' and 'Gang · ' or 'Job · ') .. g.name, arrow = true,
                onSelect = function()
                    local look = chooseLook(ptype)
                    if look == nil then return openPlacement() end
                    look = look or nil
                    local coords, heading, radius = placeMarker(('%s · %s'):format(TYPE_LABEL[ptype], g.label),
                        { ptype = ptype, radius = 1.0, resize = true, title = TYPE_LABEL[ptype], group = g.label, look = look,
                          export = { gtype = g.gtype, name = g.name, ptype = ptype } })
                    if coords then
                        result(call('addPoint', g.gtype, g.name, ptype, { x = coords.x, y = coords.y, z = coords.z }, heading, radius, look))
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
        -- admins (/bossmenuadmin) can also export the moved spot as a config.lua line
        local export = backMenu == 'blaze_boss_place_list' and { gtype = p.gtype, name = p.group, ptype = p.type } or nil
        local coords, heading = placeMarker('Move: ' .. title, { ptype = p.type, radius = p.radius or 1.0, mode = 'move', title = TYPE_LABEL[p.type] or p.type,
            group = groupLabel, look = p.entity, heading = p.entity and p.heading or nil, export = export })
        if coords then result(call('movePoint', p.id, { x = coords.x, y = coords.y, z = coords.z }, heading)) end
        after()
    end }
    local lookNow = p.entity and ('%s · %s'):format(p.entity.kind == 'ped' and 'PED' or 'Prop', p.entity.model) or 'Invisible'
    options[#options + 1] = { title = 'Change look', icon = 'fa-solid fa-person', disabled = p.fixed ~= nil,
      description = fixed or ('Now: %s. Invisible, a PED or a prop. Stays where it is.'):format(lookNow), onSelect = function()
        local look = chooseLook(p.type, p.entity or false)
        if look ~= nil then result(call('setPointEntity', p.id, look or nil)) end
        after()
    end }
    options[#options + 1] = { title = 'Change size', icon = 'fa-solid fa-expand', disabled = p.fixed ~= nil,
      description = fixed or ('Now %.2f m. Scroll to resize, see it on the spot.'):format(p.radius or 1.0), onSelect = function()
        local r = sizeMarker(p, groupLabel)
        if r then result(call('resizePoint', p.id, r)) end
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
        id = 'blaze_boss_place', title = 'Points', menu = 'blaze_boss_admin',
        options = {
            { title = 'Add boss desk', description = 'Managers open the boss menu here', icon = 'fa-solid fa-briefcase', arrow = true, onSelect = function() addFlow(info, 'boss') end },
            { title = 'Add applications point', description = 'Anyone can apply here', icon = TYPE_ICON.applications, arrow = true, onSelect = function() addFlow(info, 'applications') end },
            { title = 'Add application review point', description = 'Managers review that job\'s applications here', icon = TYPE_ICON.review, arrow = true, onSelect = function() addFlow(info, 'review') end },
            { title = 'Add duty point', description = TYPE_DESC.duty, icon = TYPE_ICON.duty, arrow = true, disabled = not (Config.duty or {}).enabled, onSelect = function() addFlow(info, 'duty') end },
            { title = 'Add wardrobe', description = TYPE_DESC.outfits, icon = TYPE_ICON.outfits, arrow = true, disabled = not (Config.outfits or {}).enabled, onSelect = function() addFlow(info, 'outfits') end },
            { title = 'Manage points', description = ('%d points: move, change look, size, delete'):format(#info.points), icon = 'fa-solid fa-list', arrow = true, onSelect = function() manageFlow(info) end },
        },
    })
    UI.showMenu('blaze_boss_place')
end

BMC.openPlacement = function() openPlacement() end

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
            local look = chooseLook(t)
            if look == nil then return reopen() end
            look = look or nil
            local coords, heading, radius = placeMarker(('%s · %s'):format(TYPE_LABEL[t] or t, m.label),
                { ptype = t, radius = 1.0, resize = true, title = TYPE_LABEL[t] or t, group = m.label, look = look })
            if coords then
                result(call('addPoint', m.gtype, m.name, t, { x = coords.x, y = coords.y, z = coords.z }, heading, radius, look))
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
-- debug: Config.debug, or this player's debug view (/bossdebug, or Debug mode in /bossmenuadmin)
local debugView = LocalPlayer.state.bossDebugView == true
local function debugMode() return Config.debug == true or debugView end

RegisterNetEvent(RES .. ':client:points', function(points) zonePoints = points or {} end)

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
                    local c = p.v
                    if not c then c = vec3(p.coords.x, p.coords.y, p.coords.z) p.v = c end
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

-- start drawing labels when debug turns on (no polling: the state bag tells us)
AddStateBagChangeHandler('bossDebugView', ('player:%s'):format(cache.serverId), function(_, _, value)
    debugView = value == true
    if debugView then CreateThread(startDrawing) end
end)
CreateThread(function()
    Wait(1000)
    if debugMode() then startDrawing() end
end)
