-- blaze_bossmenu | GNU GPL v3 (see LICENSE) | based on qbx_management by the Qbox Project (see NOTICE.md)
-- Admin menu (/bossmenuadmin): every admin tool in one place. The boss menu itself stays roleplay only.
-- The server checks admin on every action; this file only builds the menus.
if not Config.enabled then return end

local RES = GetCurrentResourceName()
local ADMIN_CMD = Config.adminCommand or 'bossmenuadmin'
local function call(name, ...) return lib.callback.await(('%s:%s'):format(RES, name), false, ...) end
local function notify(msg, kind) lib.notify({ title = 'Boss menu admin', description = msg, type = kind or 'inform' }) end

local openAdmin

--- Boss menus: any configured job or gang, opened with full access
local function openGroups()
    local d = call('adminGroups')
    if not d then return notify('Admins only.', 'error') end
    local options = {}
    if not d.canManage then
        options[1] = { title = 'Turned off', description = 'adminsCanManage = false in config.lua', readOnly = true }
    else
        for _, g in ipairs(d.groups) do
            options[#options + 1] = {
                title = g.label, description = ('%s · %s · %d %s'):format(g.gtype == 'gang' and 'Gang' or 'Job', g.name, g.members, g.members == 1 and 'member' or 'members'),
                icon = g.gtype == 'gang' and 'fa-solid fa-users-rectangle' or 'fa-solid fa-briefcase', arrow = true,
                onSelect = function() BMC.openGroupAsAdmin(g.gtype, g.name) end,
            }
        end
        if #options == 0 then options[1] = { title = 'No configured groups', description = 'Add jobs / gangs in config.lua', readOnly = true } end
    end
    UI.registerMenu({ id = 'blaze_boss_admin_groups', title = 'Boss menus (admin)', menu = 'blaze_boss_admin', options = options })
    UI.showMenu('blaze_boss_admin_groups')
end

--- Read-only overview of the important settings
local function openSettings()
    local rows = call('adminSettings')
    if not rows then return notify('Admins only.', 'error') end
    local options = {}
    for _, r in ipairs(rows) do options[#options + 1] = { title = r[1], description = tostring(r[2]), readOnly = true } end
    options[#options + 1] = { title = 'Change these in config.lua', description = 'Then restart the resource', icon = 'fa-solid fa-circle-info', readOnly = true }
    UI.registerMenu({ id = 'blaze_boss_admin_settings', title = 'Settings', menu = 'blaze_boss_admin', options = options })
    UI.showMenu('blaze_boss_admin_settings')
end

openAdmin = function()
    local options = {
        { title = 'Boss menus', description = 'Open any job\'s or gang\'s boss menu with full access', icon = 'fa-solid fa-briefcase', arrow = true, onSelect = openGroups },
        { title = 'Points', description = 'Place boss desks, application, review, duty and wardrobe points', icon = 'fa-solid fa-location-dot', arrow = true,
          onSelect = function() BMC.openPlacement() end },
        { title = 'Show zones: ' .. (BMC.zonesShown() and 'On' or 'Off'), icon = 'fa-solid fa-draw-polygon',
          description = 'Draw every point on the ground with a label (only you see it)', onSelect = function()
            BMC.setShowZones(not BMC.zonesShown() and 'all' or false)
            openAdmin()
        end },
        { title = 'Debug mode: ' .. (BMC.debugOn() and 'On' or 'Off'), icon = 'fa-solid fa-bug',
          description = 'Live panel, point ids / radius / distance, your actions logged to F8 and the server console', onSelect = function()
            BMC.setDebug(not BMC.debugOn())
            openAdmin()
        end },
        { title = 'Move / resize debug panel', icon = 'fa-solid fa-up-down-left-right', disabled = LocalPlayer.state.bossDebugView ~= true,
          description = 'Drag it, mouse wheel or - / + for size (saved on this PC)', onSelect = function() TriggerEvent(RES .. ':client:debugMove') end },
    }
    if Config.testCommand then
        options[#options + 1] = { title = 'Test tools', description = 'Test staff and applications, "View as" any rank', icon = 'fa-solid fa-flask', arrow = true,
            onSelect = function() ExecuteCommand(Config.testCommand) end }
    end
    options[#options + 1] = { title = 'Settings', description = 'What this server has turned on', icon = 'fa-solid fa-sliders', arrow = true, onSelect = openSettings }
    UI.registerMenu({ id = 'blaze_boss_admin', title = 'Boss menu · Admin', options = options })
    UI.showMenu('blaze_boss_admin')
end
BMC.openAdmin = function() openAdmin() end

RegisterNetEvent(RES .. ':client:adminMenu', function() openAdmin() end)
TriggerEvent('chat:addSuggestion', '/' .. ADMIN_CMD, 'Boss menu admin: boss menus, points, zones, debug, test tools (admin)')
