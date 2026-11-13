-- Client bridge: framework events + a small Target layer (ox_target, qb-target, or a walk-up zone with [E]).
if not Config.enabled then return end

Bridge = {}

Bridge.framework = GetResourceState('qbx_core') ~= 'missing' and 'qbx' or (GetResourceState('qb-core') ~= 'missing' and 'qb' or nil)

-- Fired when the local player's job/gang/character changes, so menus and targets can refresh
local listeners = {}
function Bridge.onGroupsChanged(fn) listeners[#listeners + 1] = fn end
local function changed() for _, fn in ipairs(listeners) do pcall(fn) end end

RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function() SetTimeout(1000, changed) end)
RegisterNetEvent('QBCore:Client:OnJobUpdate', function() SetTimeout(500, changed) end)
RegisterNetEvent('QBCore:Client:OnGangUpdate', function() SetTimeout(500, changed) end)
RegisterNetEvent('qbx_core:client:onGroupUpdate', function() SetTimeout(500, changed) end)

---------------------------------------------------------------------------
-- Target layer
---------------------------------------------------------------------------
local mode
do
    local want = Config.target or 'auto'
    if want == 'ox_target' or want == 'qb-target' or want == 'none' then mode = want
    elseif GetResourceState('ox_target') == 'started' then mode = 'ox_target'
    elseif GetResourceState('qb-target') == 'started' then mode = 'qb-target'
    else mode = 'none' end
end
Bridge.target = mode

Target = {}
local n = 0

--- opts = { coords = vector3, radius, options = { { name, label, icon, canInteract = fn(), onSelect = fn() } } }
--- returns a handle for Target.remove
function Target.addPoint(opts)
    n = n + 1
    local name = ('blaze_bossmenu_%d'):format(n)
    if mode == 'ox_target' then
        local options = {}
        for _, o in ipairs(opts.options) do
            options[#options + 1] = { name = o.name, label = o.label, icon = o.icon, distance = 2.0,
                canInteract = o.canInteract and function() return o.canInteract() end or nil,
                onSelect = function() o.onSelect() end }
        end
        return { kind = 'ox', id = exports.ox_target:addSphereZone({ coords = opts.coords, radius = opts.radius or 1.0, debug = false, options = options }) }
    elseif mode == 'qb-target' then
        local options = {}
        for i, o in ipairs(opts.options) do
            options[#options + 1] = { type = 'client', icon = o.icon, label = o.label, num = i,
                canInteract = o.canInteract and function() return o.canInteract() end or nil,
                action = function() o.onSelect() end }
        end
        exports['qb-target']:AddCircleZone(name, opts.coords, opts.radius or 1.0, { name = name, debugPoly = false, useZ = true }, { options = options, distance = 2.0 })
        return { kind = 'qb', id = name }
    end

    -- No target script: walk-up zone with a text prompt (like qbx_management without target)
    local function usable()
        local out = {}
        for _, o in ipairs(opts.options) do if not o.canInteract or o.canInteract() then out[#out + 1] = o end end
        return out
    end
    local shown = false
    local zone = lib.zones.sphere({
        coords = opts.coords, radius = math.max(opts.radius or 1.0, 1.0), debug = false,
        inside = function()
            local list = usable()
            if #list == 0 then
                if shown then lib.hideTextUI() shown = false end
                return
            end
            if not shown then
                lib.showTextUI(#list == 1 and ('[E] ' .. list[1].label) or '[E] Open')
                shown = true
            end
            if IsControlJustPressed(0, 38) then
                lib.hideTextUI() shown = false
                if #list == 1 then return list[1].onSelect() end
                local options = {}
                for _, o in ipairs(list) do options[#options + 1] = { title = o.label, icon = o.icon, onSelect = o.onSelect } end
                UI.registerMenu({ id = name, title = 'Options', options = options })
                UI.showMenu(name)
            end
        end,
        onExit = function() if shown then lib.hideTextUI() shown = false end end,
    })
    return { kind = 'zone', id = zone }
end

function Target.remove(h)
    if not h then return end
    if h.kind == 'ox' then exports.ox_target:removeZone(h.id)
    elseif h.kind == 'qb' then exports['qb-target']:RemoveZone(h.id)
    elseif h.kind == 'zone' then h.id:remove() end
end
