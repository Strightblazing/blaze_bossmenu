-- blaze_bossmenu | GNU GPL v3 (see LICENSE) | based on qbx_management by the Qbox Project (see NOTICE.md)
-- Client bridge: framework events + a small Target layer (ox_target, qb-target, or a walk-up zone with [E]).
if not Config.enabled then return end

Bridge = {}

Bridge.framework = GetResourceState('qbx_core') ~= 'missing' and 'qbx' or (GetResourceState('qb-core') ~= 'missing' and 'qb' or nil)

--- The local player's framework data (job, gang, charinfo, metadata). Used by the debug panel.
function Bridge.PlayerData()
    if Bridge.framework == 'qbx' then return exports.qbx_core:GetPlayerData() or {} end
    if Bridge.framework == 'qb' then return exports['qb-core']:GetCoreObject().Functions.GetPlayerData() or {} end
    return {}
end

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
local TARGET_DIST = tonumber(Config.targetDistance) or 2.0 -- how close you must be to use a point (PEDs / props: +0.5 m)
local n = 0

---------------------------------------------------------------------------
-- [E] prompt for walk-up zones (no target script). One prompt for the whole resource:
-- * only the nearest zone you're inside with something you can do shows, so overlapping points never stack
-- * E fires once per press, and not while a menu / screen is open or right after something opened
---------------------------------------------------------------------------
Prompt = {}
local inside, shownFor, lastFire, running = {}, nil, 0, false

local function usable(entry)
    local out = {}
    for _, o in ipairs(entry.options) do if not o.canInteract or o.canInteract() then out[#out + 1] = o end end
    return out
end
local function hidePrompt() if shownFor then lib.hideTextUI() shownFor = nil end end
local function busy()
    return IsNuiFocused() or IsPauseMenuActive() or (lib.getOpenContextMenu and lib.getOpenContextMenu() ~= nil)
        or (lib.getOpenMenu and lib.getOpenMenu() ~= nil) or IsPedDeadOrDying(cache.ped, true) or IsPedInAnyVehicle(cache.ped, false)
end

local function loop()
    if running then return end
    running = true
    CreateThread(function()
        while next(inside) do
            local pos = GetEntityCoords(cache.ped)
            local best, bestList, bestDist
            if not busy() then
                for entry in pairs(inside) do
                    local d = #(pos - entry.coords)
                    if not bestDist or d < bestDist then
                        local list = usable(entry)
                        if #list > 0 then best, bestList, bestDist = entry, list, d end
                    end
                end
            end
            if not best then
                hidePrompt()
                Wait(250)
            else
                local text = #bestList == 1 and ('[E] ' .. bestList[1].label) or '[E] Open'
                if shownFor ~= best or best.text ~= text then
                    lib.showTextUI(text)
                    shownFor, best.text = best, text
                end
                if IsControlJustPressed(0, 38) and GetGameTimer() - lastFire > 600 then
                    lastFire = GetGameTimer()
                    hidePrompt()
                    if #bestList == 1 then
                        bestList[1].onSelect()
                    else
                        local options = {}
                        for _, o in ipairs(bestList) do options[#options + 1] = { title = o.label, icon = o.icon, onSelect = o.onSelect } end
                        UI.registerMenu({ id = best.name, title = 'Options', options = options })
                        UI.showMenu(best.name)
                    end
                end
                Wait(0)
            end
        end
        hidePrompt()
        running = false
    end)
end

function Prompt.enter(entry) inside[entry] = true loop() end
function Prompt.leave(entry)
    inside[entry] = nil
    if shownFor == entry then hidePrompt() end
end

--- opts = { coords = vector3, radius, options = { { name, label, icon, canInteract = fn(), onSelect = fn() } } }
--- returns a handle for Target.remove
function Target.addPoint(opts)
    n = n + 1
    local name = ('blaze_bossmenu_%d'):format(n)
    if mode == 'ox_target' then
        local options = {}
        for _, o in ipairs(opts.options) do
            options[#options + 1] = { name = o.name, label = o.label, icon = o.icon, distance = TARGET_DIST,
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
        exports['qb-target']:AddCircleZone(name, opts.coords, opts.radius or 1.0, { name = name, debugPoly = false, useZ = true }, { options = options, distance = TARGET_DIST })
        return { kind = 'qb', id = name }
    end

    -- No target script: walk-up zone with an [E] prompt (like qbx_management without target).
    -- All zones report to one prompt (Prompt below): only the nearest usable point shows, E fires once.
    local entry = { name = name, coords = opts.coords, options = opts.options }
    local zone = lib.zones.sphere({
        coords = opts.coords, radius = math.max(opts.radius or 1.0, 1.0), debug = false,
        onEnter = function() Prompt.enter(entry) end,
        onExit = function() Prompt.leave(entry) end,
    })
    return { kind = 'zone', id = zone, entry = entry }
end

--- Same options on an entity (e.g. the receptionist NPC). Returns a handle for Target.remove, or nil with no target script.
function Target.addEntity(entity, options)
    if not entity or not DoesEntityExist(entity) then return nil end
    if mode == 'ox_target' then
        local opts, names = {}, {}
        for _, o in ipairs(options) do
            opts[#opts + 1] = { name = o.name, label = o.label, icon = o.icon, distance = TARGET_DIST + 0.5,
                canInteract = o.canInteract and function() return o.canInteract() end or nil,
                onSelect = function() o.onSelect() end }
            names[#names + 1] = o.name
        end
        exports.ox_target:addLocalEntity(entity, opts)
        return { kind = 'oxent', id = entity, names = names }
    elseif mode == 'qb-target' then
        local opts = {}
        for i, o in ipairs(options) do
            opts[#opts + 1] = { type = 'client', icon = o.icon, label = o.label, num = i,
                canInteract = o.canInteract and function() return o.canInteract() end or nil,
                action = function() o.onSelect() end }
        end
        exports['qb-target']:AddTargetEntity(entity, { options = opts, distance = TARGET_DIST + 0.5 })
        return { kind = 'qbent', id = entity }
    end
    return nil -- no target script: the walk-up zone at the point already covers it
end

function Target.remove(h)
    if not h then return end
    if h.kind == 'oxent' then pcall(function() exports.ox_target:removeLocalEntity(h.id, h.names) end) return end
    if h.kind == 'qbent' then pcall(function() exports['qb-target']:RemoveTargetEntity(h.id) end) return end
    if h.kind == 'ox' then exports.ox_target:removeZone(h.id)
    elseif h.kind == 'qb' then exports['qb-target']:RemoveZone(h.id)
    elseif h.kind == 'zone' then h.id:remove() if h.entry then Prompt.leave(h.entry) end end
end
