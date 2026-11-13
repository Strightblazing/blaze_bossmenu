-- /bossmenu (admins): place boss desks and application points in game. The server checks admin on every action.
if not Config.enabled then return end

local RES = GetCurrentResourceName()
local function call(name, ...) return lib.callback.await(('%s:%s'):format(RES, name), false, ...) end
local function result(ok, msg) lib.notify({ title = 'Boss menu placement', description = msg or (ok and 'Done.' or 'Failed.'), type = ok and 'success' or 'error' }) return ok end

local TYPE_LABEL = { boss = 'Boss desk', applications = 'Applications point' }
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
        if ptype == 'boss' or g.apps then -- hide applications points for groups with applications off
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
            local fixed = p.fixed == 'config' and 'From config.lua (can\'t be deleted in game)'
                or p.fixed == 'script' and 'Added by another script (can\'t be deleted in game)' or nil
            options[#options + 1] = {
                title = ('%s · %s'):format(labels[k] or k, TYPE_LABEL[p.type] or p.type),
                description = fixed or ('#%s · %.1f, %.1f, %.1f'):format(p.id, p.coords.x, p.coords.y, p.coords.z),
                icon = p.type == 'boss' and 'fa-solid fa-briefcase' or 'fa-solid fa-file-signature', arrow = true,
                onSelect = function()
                    UI.registerMenu({
                        id = 'blaze_boss_place_point', title = ('%s · %s'):format(labels[k] or k, TYPE_LABEL[p.type] or p.type), menu = 'blaze_boss_place_list',
                        options = {
                            { title = 'Teleport', icon = 'fa-solid fa-location-arrow', onSelect = function()
                                SetEntityCoords(cache.ped, p.coords.x, p.coords.y, p.coords.z, false, false, false, false)
                            end },
                            { title = 'Delete', icon = 'fa-solid fa-trash', iconColor = '#E5484D', disabled = p.fixed ~= nil,
                              description = fixed, onSelect = function()
                                if UI.confirm({ header = 'Delete point', content = 'Delete this point? It disappears for everyone.', type = 'error', confirm = 'Delete' }) then
                                    result(call('removePoint', p.id))
                                end
                                openPlacement()
                            end },
                        },
                    })
                    UI.showMenu('blaze_boss_place_point')
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
            { title = 'Add applications point', description = 'Anyone can apply here', icon = 'fa-solid fa-file-signature', arrow = true, onSelect = function() addFlow(info, 'applications') end },
            { title = 'Manage points', description = ('%d points'):format(#info.points), icon = 'fa-solid fa-list', arrow = true, onSelect = function() manageFlow(info) end },
        },
    })
    UI.showMenu('blaze_boss_place')
end

RegisterNetEvent(RES .. ':client:placement', function() openPlacement() end)

TriggerEvent('chat:addSuggestion', '/bossmenu', 'Place boss desks and application points (admin)')
