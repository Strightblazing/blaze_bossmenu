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

openTest = function()
    local info = call('testInfo')
    if not info then return result(false, 'Admins only.') end
    UI.registerMenu({
        id = 'blaze_boss_test', title = 'Boss menu test',
        options = {
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
        },
    })
    UI.showMenu('blaze_boss_test')
end

RegisterNetEvent(RES .. ':client:testMenu', function() openTest() end)
TriggerEvent('chat:addSuggestion', '/' .. Config.testCommand, 'Boss menu test tools (admin)')
