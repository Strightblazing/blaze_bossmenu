-- blaze_bossmenu | GNU GPL v3 (see LICENSE) | based on qbx_management by the Qbox Project (see NOTICE.md)
-- /bossmenutest (admins): add/remove test staff and applications, and preview the effects you'd
-- otherwise need a second player for. The server checks admin on every action.
if not Config.enabled or not Config.testCommand then return end

local RES = GetCurrentResourceName()
local function call(name, ...) return lib.callback.await(('%s:%s'):format(RES, name), false, ...) end
local function result(ok, msg)
    lib.notify({ title = 'Boss menu test', description = msg or (ok and 'Done.' or 'Failed.'), type = ok and 'success' or 'error', duration = 8000 })
    return ok
end

local openTest

local function pickGroup(info, appsOnly, title, fn)
    local options = {}
    for _, g in ipairs(info.groups) do
        if not appsOnly or g.apps then
            options[#options + 1] = { title = g.label, description = (g.gtype == 'gang' and 'Gang · ' or 'Job · ') .. g.name, arrow = true,
                onSelect = function() fn(g) openTest() end }
        end
    end
    if #options == 0 then options[1] = { title = appsOnly and 'No jobs with applications on' or 'No configured jobs or gangs', readOnly = true } end
    UI.registerMenu({ id = 'blaze_boss_test_pick', title = title, menu = 'blaze_boss_test', options = options })
    UI.showMenu('blaze_boss_test_pick')
end

--- "View as": pick a rank (or Civilian) in a group and see everything the way they would
local function viewAsMenu(g)
    local options = {
        { title = 'Civilian', description = ('Not in %s: application point, /jobs, /applicationstatus'):format(g.label), icon = 'fa-solid fa-person', arrow = true,
          onSelect = function() result(call('testViewAs', g.gtype, g.name, false)) end },
    }
    for i = #g.grades, 1, -1 do
        local gr = g.grades[i]
        local boss = (g.bossGrade and gr.level >= g.bossGrade) or (not g.bossGrade and gr.isboss)
        options[#options + 1] = {
            title = ('%s (rank %d)'):format(gr.name, gr.level), icon = boss and 'fa-solid fa-user-tie' or 'fa-solid fa-user',
            iconColor = boss and '#F5C542' or nil, arrow = true,
            description = boss and 'Command / boss access: boss menu at their limits' or 'Regular employee: no boss access, /myjob',
            onSelect = function() result(call('testViewAs', g.gtype, g.name, gr.level)) end,
        }
    end
    UI.registerMenu({ id = 'blaze_boss_test_viewas', title = 'View ' .. g.label .. ' as…', menu = 'blaze_boss_test_pick', options = options })
    UI.showMenu('blaze_boss_test_viewas')
end

openTest = function()
    local info = call('testInfo')
    if not info then return result(false, 'Admins only.') end
    local top = {}
    if info.viewAs then
        top[#top + 1] = { title = 'Stop preview', icon = 'fa-solid fa-eye-slash', iconColor = '#E5484D',
            description = ('Now viewing %s as %s'):format(info.viewAs.label, info.viewAs.who),
            onSelect = function() result(call('testViewAs')) openTest() end }
    end
    top[#top + 1] = { title = 'View as…', icon = 'fa-solid fa-eye', iconColor = '#5AA9FF', arrow = true,
        description = 'See a job as a civilian, an employee or any rank (only you are affected)',
        onSelect = function()
            local options = {}
            for _, g in ipairs(info.groups) do
                options[#options + 1] = { title = g.label, description = (g.gtype == 'gang' and 'Gang · ' or 'Job · ') .. g.name, arrow = true,
                    onSelect = function() viewAsMenu(g) end }
            end
            UI.registerMenu({ id = 'blaze_boss_test_pick', title = 'View which job as…', menu = 'blaze_boss_test', options = options })
            UI.showMenu('blaze_boss_test_pick')
        end }
    local options = {
            { title = ('Test data: %d characters · %d applications'):format(info.characters, info.applications), icon = 'fa-solid fa-flask', readOnly = true,
              description = 'Fake offline characters (citizen ID BMTEST..). Nobody can log in as them.' },
            { title = 'Add 4 test staff', icon = 'fa-solid fa-users', arrow = true,
              description = 'Probation, inactive, ready for promotion + commendation, regular',
              onSelect = function() pickGroup(info, false, 'Add test staff to…', function(g) result(call('testAddStaff', g.gtype, g.name)) end) end },
            { title = 'Add 3 test applications', icon = 'fa-solid fa-file-signature', arrow = true,
              description = '2 waiting for review, 1 invited to interview (uses the current form)',
              onSelect = function() pickGroup(info, true, 'Add test applications to…', function(g) result(call('testAddApplications', g.name)) end) end },
            { title = 'Preview: promotion celebration', icon = 'fa-solid fa-trophy', iconColor = '#F5C542', description = 'What a promoted player sees',
              onSelect = function() TriggerEvent(RES .. ':client:celebrate', 'PROMOTED', 'Test Rank') end },
            { title = 'Preview: hire offer popup', icon = 'fa-solid fa-handshake', description = 'What the person being hired sees (nothing happens)',
              onSelect = function()
                  local ok = UI.confirm({ header = 'Job offer', content = 'Test Manager wants to hire you into Test Department. Do you accept?', type = 'info', confirm = 'Accept', cancel = 'Decline' })
                  result(true, ok and 'You pressed Accept (preview only).' or 'You pressed Decline (preview only).')
              end },
            { title = 'Preview: employment contract', icon = 'fa-solid fa-file-signature', iconColor = '#A78BFA', description = 'Read and sign it yourself (nothing is saved)',
              onSelect = function()
                  local C = Config.contract or {}
                  local days = tonumber((Config.features or {}).probationDays) or 0
                  local r = BMC.signContract({
                      template = C.template or {}, style = C.style == 'typed' and 'typed' or 'paper', expectedName = info.myName,
                      values = { job = 'Test Department', rank = 'Probationary Paramedic', pay = '$500', probation = days > 0 and (days .. ' days') or nil,
                          employee = info.myName, manager = 'Test Manager', manager_rank = 'Chief', date = info.today, number = 'EA-TEST' },
                  }, C.seconds or 90)
                  result(r.accepted, r.accepted and 'Contract signed (preview only, nothing saved).' or 'Not signed (preview only).')
              end },
            { title = 'Preview: announcement popup', icon = 'fa-solid fa-bullhorn', description = 'What on-duty staff see',
              onSelect = function() TriggerEvent(RES .. ':client:announcement', 'Test Department', 'This is a test announcement. Briefing at 8pm!', 'Test Manager') end },
            { title = 'Remove all test data', icon = 'fa-solid fa-trash', iconColor = '#E5484D', description = 'Deletes every test character and everything linked to them',
              onSelect = function()
                  if UI.confirm({ header = 'Remove all test data', content = 'Delete every BMTEST character, their applications, records, hours and memberships?', type = 'error', confirm = 'Remove' }) then
                      result(call('testClear'))
                  end
                  openTest()
              end },
    }
    for i = #top, 1, -1 do table.insert(options, 1, top[i]) end
    UI.registerMenu({ id = 'blaze_boss_test', title = 'Boss menu test', options = options })
    UI.showMenu('blaze_boss_test')
end

-- On-screen reminder while previewing, so it's never forgotten
RegisterNetEvent(RES .. ':client:viewAs', function(v)
    if BMC then BMC.viewAsLabel = v and ('%s as %s'):format(v.label, v.who) or nil end -- debug panel
    if v then
        lib.showTextUI(('Previewing %s as %s  \n/%s to stop'):format(v.label, v.who, Config.testCommand), { position = 'top-center', icon = 'eye' })
    else
        lib.hideTextUI()
    end
end)

RegisterNetEvent(RES .. ':client:testMenu', function() openTest() end)
TriggerEvent('chat:addSuggestion', '/' .. Config.testCommand, 'Boss menu test tools (admin)')
