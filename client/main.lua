-- blaze_bossmenu | GNU GPL v3 (see LICENSE) | based on qbx_management by the Qbox Project (see NOTICE.md)
-- blaze_bossmenu client menus. All menus/forms/confirms go through UI.* (client/ui.lua).
-- Boss menu flow forked from qbx_management (Qbox Project, GPL-3.0).
if not Config.enabled then
    exports('openBossMenu', function() end)
    exports('openApplication', function() end)
    exports('openApplicationStatus', function() end)
    return
end

local RES = GetCurrentResourceName()

local function call(name, ...) return lib.callback.await(('%s:%s'):format(RES, name), false, ...) end
local function notify(msg, ntype, title) lib.notify({ title = title or 'Management', description = msg, type = ntype or 'inform' }) end
local function result(ok, msg)
    notify(msg or (ok and 'Done.' or 'That didn\'t work.'), ok and 'success' or 'error')
    return ok
end
local function money(n) return n and ('$' .. tostring(math.floor(n)):reverse():gsub('(%d%d%d)', '%1,'):reverse():gsub('^,', '')) or 'unknown' end
local function short(s, n)
    s = tostring(s or '')
    s = s:gsub('\n', ' ')
    return #s > n and (s:sub(1, n - 1) .. '…') or s
end

local managed = {}  -- ['job:ambulance'] = true   (groups they can manage)
local member = {}   -- ['job:ambulance'] = true   (groups they're in: duty points, wardrobes)
local myGroups = {} -- list from getMyJobs
local isAdmin = false
local dynamicItems = {} -- items other scripts add (AddBossMenuItem / AddGangMenuItem)

local function refreshManaged()
    local d = call('getMyJobs') or { groups = {} }
    managed, member, myGroups, isAdmin = {}, {}, d.groups or {}, d.isAdmin == true
    for _, g in ipairs(myGroups) do managed[g.gtype .. ':' .. g.name] = true end
    for _, k in ipairs(d.member or {}) do member[k] = true end
    if BMC and BMC.updateRadial then BMC.updateRadial(myGroups) end -- "Work" radial entry for bosses
end
Bridge.onGroupsChanged(refreshManaged)
--- For the debug panel (client/debug.lua): groups you manage, groups you're in, admin
if BMC then BMC.mine = function() return myGroups, member, isAdmin end end

local openGroup -- forward

---------------------------------------------------------------------------
-- Rank picker
---------------------------------------------------------------------------
--- Returns the chosen grade level (only ranks below the manager's limit), or nil
local function pickRank(m, title)
    local options = {}
    for _, g in ipairs(m.grades or {}) do
        if g.level < m.limit then options[#options + 1] = { value = tostring(g.level), label = ('%s (%d)'):format(g.name, g.level) } end
    end
    if #options == 0 then notify('There is no rank you can give.', 'error') return nil end
    local v = UI.input(title or 'Starting rank', {
        { type = 'select', label = 'Rank', options = options, default = options[1].value, required = true },
    })
    return v and tonumber(v[1]) or nil
end

---------------------------------------------------------------------------
-- Staff
---------------------------------------------------------------------------
local openStaff

local function gradeAfter(grades, level, dir)
    if dir > 0 then
        for _, g in ipairs(grades) do if g.level > level then return g end end
    else
        for i = #grades, 1, -1 do if grades[i].level < level then return grades[i] end end
    end
end

local function openMember(m, data, p)
    local below = p.grade < data.limit
    local up, down = gradeAfter(data.grades, p.grade, 1), gradeAfter(data.grades, p.grade, -1)
    local options = {
        {
            title = 'Promote', icon = 'fa-solid fa-arrow-up',
            description = up and ('To ' .. up.name) or 'Already at the top rank',
            disabled = p.isSelf or not below or not up or up.level >= data.limit,
            onSelect = function()
                if UI.confirm({ header = 'Promote', content = ('Promote %s to %s?'):format(p.name, up.name), type = 'info' }) then
                    result(call('promote', m.gtype, m.name, p.citizenid))
                end
                openStaff(m)
            end,
        },
        {
            title = 'Demote', icon = 'fa-solid fa-arrow-down',
            description = down and ('To ' .. down.name) or 'Already at the lowest rank',
            disabled = p.isSelf or not below or not down,
            onSelect = function()
                if UI.confirm({ header = 'Demote', content = ('Demote %s to %s?'):format(p.name, down.name), type = 'warning' }) then
                    result(call('demote', m.gtype, m.name, p.citizenid))
                end
                openStaff(m)
            end,
        },
    }
    if m.callsigns then
        options[#options + 1] = {
            title = 'Set callsign', icon = 'fa-solid fa-hashtag', description = p.callsign and ('Current: ' .. p.callsign) or 'None set',
            disabled = not p.isSelf and not below,
            onSelect = function()
                local v = UI.input('Callsign · ' .. p.name, {
                    { type = 'input', label = 'Callsign', description = '1-8 letters, numbers or dashes', default = p.callsign, required = true, minLength = 1, maxLength = 8 },
                })
                if v then result(call('setCallsign', m.gtype, m.name, p.citizenid, v[1])) end
                openStaff(m)
            end,
        }
    end
    local FT = Config.features or {}
    if FT.profiles and BMC then
        table.insert(options, 1, { title = 'View profile', icon = 'fa-solid fa-id-badge', arrow = true, description = 'Hours, rank history and record',
            onSelect = function() BMC.openProfile(m.gtype, m.name, p.citizenid, 'blaze_boss_member') end })
    end
    if FT.records then
        options[#options + 1] = { title = 'Give commendation', icon = 'fa-solid fa-award', iconColor = '#3DDC84', disabled = p.isSelf,
            onSelect = function()
                local v = UI.input('Commend ' .. p.name, { { type = 'textarea', label = 'What did they do well?', required = true, minLength = 3, maxLength = 300 } })
                if v then result(call('addRecord', m.gtype, m.name, p.citizenid, 'commend', v[1])) end
                openStaff(m)
            end }
        options[#options + 1] = { title = 'Write-up', icon = 'fa-solid fa-triangle-exclamation', iconColor = '#F0A93B', disabled = p.isSelf or not below,
            onSelect = function()
                local v = UI.input('Write-up · ' .. p.name, { { type = 'textarea', label = 'What happened?', required = true, minLength = 3, maxLength = 300 } })
                if v and UI.confirm({ header = 'Write-up', content = ('Add a write-up to %s\'s record? They will be told.'):format(p.name), type = 'warning', confirm = 'Add write-up' }) then
                    result(call('addRecord', m.gtype, m.name, p.citizenid, 'warning', v[1]))
                end
                openStaff(m)
            end }
    end
    if FT.employeeOfWeek then
        options[#options + 1] = { title = p.eotw and 'Employee of the Week (this week)' or 'Make Employee of the Week', icon = 'fa-solid fa-star', iconColor = '#F5C542',
            disabled = p.isSelf or p.eotw == true, description = 'Announced to the whole department',
            onSelect = function()
                local v = UI.input('Employee of the Week · ' .. p.name, { { type = 'input', label = 'Why? (optional)', maxLength = 200 } })
                if v then result(call('setEmployeeOfWeek', m.gtype, m.name, p.citizenid, v[1] or '')) end
                openStaff(m)
            end }
    end
    if m.funds and Config.funds.bonuses then
        options[#options + 1] = { title = 'Give bonus', icon = 'fa-solid fa-gift', iconColor = '#3DDC84', disabled = p.isSelf or not p.online,
            description = p.online and ('Paid into their bank from %s funds'):format(m.label) or 'They must be online',
            onSelect = function()
                local v = UI.input('Bonus · ' .. p.name, {
                    { type = 'number', label = ('Amount (max $%d)'):format(Config.funds.maxBonus or 5000), required = true, min = 1, max = Config.funds.maxBonus or 5000 },
                    { type = 'input', label = 'Reason', required = true, minLength = 1, maxLength = 100 },
                })
                if v and v[1] and UI.confirm({ header = 'Give bonus', content = ('Pay %s a $%d bonus?'):format(p.name, math.floor(v[1])), type = 'info', confirm = 'Pay' }) then
                    result(call('bonus', m.gtype, m.name, 'one', p.citizenid, math.floor(v[1]), v[2]))
                end
                openStaff(m)
            end }
    end
    options[#options + 1] = {
        title = m.gtype == 'gang' and 'Kick from gang' or 'Fire', icon = 'fa-solid fa-user-slash', iconColor = '#E5484D',
        disabled = p.isSelf or not below,
        onSelect = function()
            if UI.confirm({ header = m.gtype == 'gang' and 'Kick member' or 'Fire employee', content = ('Remove %s from %s?'):format(p.name, m.label),
                    type = 'error', callout = 'This removes them from the ' .. (m.gtype == 'gang' and 'gang.' or 'job.'), confirm = 'Remove' }) then
                result(call('fire', m.gtype, m.name, p.citizenid))
            end
            openStaff(m)
        end,
    }
    UI.registerMenu({ id = 'blaze_boss_member', title = p.name, menu = 'blaze_boss_staff', options = options })
    UI.showMenu('blaze_boss_member')
end

openStaff = function(m)
    local data = call('getStaff', m.gtype, m.name)
    if not data then return notify('You are not a manager here.', 'error') end
    local options = {}
    for _, p in ipairs(data.members) do
        local status = p.online and (p.onduty and 'On duty' or 'Off duty') or 'Offline'
        if m.gtype == 'gang' then status = p.online and 'Online' or 'Offline' end
        local parts = { p.gradeName }
        if p.callsign then parts[#parts + 1] = p.callsign end
        parts[#parts + 1] = status
        -- badges
        if p.probationDays then parts[#parts + 1] = ('Probation %dd'):format(p.probationDays) end
        if p.inactive then parts[#parts + 1] = 'Inactive' end
        if p.readyForPromotion then parts[#parts + 1] = 'Ready for promotion' end
        local meta = {}
        if p.hours or p.lastCheckin then
            meta[#meta + 1] = { label = 'Status', value = status }
            meta[#meta + 1] = { label = 'Hours (last ' .. ((Config.activity and Config.activity.keepDays) or 31) .. ' days)', value = tostring(p.hours or 0) }
            meta[#meta + 1] = { label = 'Last check-in', value = p.lastCheckin or 'N/A' }
        end
        if p.hiredAt then meta[#meta + 1] = { label = 'Hired', value = p.hiredAt } end
        if #meta == 0 then meta = nil end
        options[#options + 1] = {
            title = p.name .. (p.isSelf and ' (you)' or ''),
            description = table.concat(parts, ' · '),
            icon = p.readyForPromotion and 'fa-solid fa-arrow-up-right-dots' or (p.inactive and 'fa-solid fa-user-clock' or 'fa-solid fa-user'),
            iconColor = p.online and (p.onduty and '#3DDC84' or '#F0A93B') or '#8F99A5',
            metadata = meta, arrow = true,
            onSelect = function() openMember(m, data, p) end,
        }
    end
    if #options == 0 then options[1] = { title = 'Nobody here yet', readOnly = true } end
    UI.registerMenu({ id = 'blaze_boss_staff', title = (m.gtype == 'gang' and 'Members' or 'Staff') .. ' · ' .. m.label, menu = 'blaze_boss_main', options = options })
    UI.showMenu('blaze_boss_staff')
end

---------------------------------------------------------------------------
-- Hire
---------------------------------------------------------------------------
local function doHire(m, target, name)
    local grade = pickRank(m, 'Hire ' .. (name or ('ID ' .. target)))
    if not grade then return end
    if Config.hireConsent then
        notify((Config.contract or {}).enabled and 'Contract sent. Waiting for them to read and sign it…' or 'Waiting for them to accept the offer…', 'inform')
    end
    result(call('hire', m.gtype, m.name, target, grade))
end

local function openHire(m)
    local players = call('getNearbyPlayers', m.gtype, m.name) or {}
    local options = {
        {
            title = 'Hire by server ID', icon = 'fa-solid fa-id-card',
            description = ('They must be within %sm of you'):format(Config.hireDistance or 5.0),
            onSelect = function()
                local v = UI.input('Hire by server ID', { { type = 'number', label = 'Server ID', required = true, min = 1 } })
                if v and v[1] then doHire(m, math.floor(v[1])) end
            end,
        },
    }
    for _, p in ipairs(players) do
        options[#options + 1] = {
            title = p.name, description = 'ID ' .. p.src, icon = 'fa-solid fa-user-plus',
            onSelect = function() doHire(m, p.src, p.name) end,
        }
    end
    if #players == 0 then options[#options + 1] = { title = 'Nobody nearby', description = 'Stand close to the person you want to hire', readOnly = true } end
    UI.registerMenu({ id = 'blaze_boss_hire', title = 'Hire · ' .. m.label, menu = 'blaze_boss_main', options = options })
    UI.showMenu('blaze_boss_hire')
end

---------------------------------------------------------------------------
-- Application form helpers (shared by the applicant form, preview and editor)
---------------------------------------------------------------------------
local FRIENDLY = { input = 'Short answer', textarea = 'Long answer', number = 'Number', select = 'Dropdown', checkbox = 'Checkbox' }
local TYPE_ORDER = { 'input', 'textarea', 'number', 'select', 'checkbox' }

--- Turn saved questions into UI.input fields. defaults = previous answers by index.
local function buildFields(questions, defaults)
    defaults = defaults or {}
    local fields = {}
    for i, q in ipairs(questions) do
        local f = { type = q.type, label = q.label, required = q.required, default = defaults[i] }
        if q.type == 'input' then
            f.minLength, f.maxLength = q.min, q.max or 200
        elseif q.type == 'textarea' then
            f.minLength, f.maxLength = q.min, q.max or 1000
            if q.min then f.description = ('At least %d characters'):format(q.min) end
        elseif q.type == 'number' then
            f.min, f.max = q.min, q.max
        elseif q.type == 'select' then
            f.options = {}
            for _, o in ipairs(q.options or {}) do f.options[#f.options + 1] = { value = o, label = o } end
        elseif q.type == 'checkbox' then
            f.checked = defaults[i] == true
            f.default = nil
        end
        fields[i] = f
    end
    return fields
end

local function answerText(a)
    if a.type == 'checkbox' then return a.answer and 'Yes' or 'No' end
    if a.answer == nil or a.answer == '' then return '—' end
    return tostring(a.answer)
end

---------------------------------------------------------------------------
-- Form editor
---------------------------------------------------------------------------
local openApps

local function questionDialog(existing)
    local typeOptions = {}
    for _, t in ipairs(TYPE_ORDER) do typeOptions[#typeOptions + 1] = { value = t, label = FRIENDLY[t] } end
    local v = UI.input(existing and 'Edit question' or 'Add question', {
        { type = 'input', label = 'Question text', required = true, minLength = 1, maxLength = 100, default = existing and existing.label },
        { type = 'select', label = 'Type', options = typeOptions, required = true, default = existing and existing.type or 'input' },
        { type = 'checkbox', label = 'Required', checked = existing == nil or existing.required == true },
    })
    if not v or not v[1] or not v[2] then return nil end
    local q = { label = v[1], type = v[2], required = v[3] == true }
    local keep = existing and existing.type == q.type and existing or {}

    if q.type == 'input' or q.type == 'textarea' then
        local w = UI.input('Answer length (optional)', {
            { type = 'number', label = 'Minimum length', min = 0, max = 1000, default = keep.min },
            { type = 'number', label = 'Maximum length', min = 1, max = 1000, default = keep.max },
        })
        if not w then return nil end
        q.min, q.max = w[1], w[2]
        if q.min and q.max and q.min > q.max then notify('Minimum can\'t be more than maximum.', 'error') return nil end
    elseif q.type == 'number' then
        local w = UI.input('Allowed numbers (optional)', {
            { type = 'number', label = 'Minimum', default = keep.min },
            { type = 'number', label = 'Maximum', default = keep.max },
        })
        if not w then return nil end
        q.min, q.max = w[1], w[2]
        if q.min and q.max and q.min > q.max then notify('Minimum can\'t be more than maximum.', 'error') return nil end
    elseif q.type == 'select' then
        local text = keep.options and table.concat(keep.options, '\n') or nil
        while true do
            local w = UI.input('Dropdown options', {
                { type = 'textarea', label = 'Options', description = 'One per line, 2-10 options, up to 50 characters each', required = true, default = text },
            })
            if not w then return nil end
            text = w[1]
            local opts, bad = {}, nil
            for line in tostring(text):gmatch('[^\n]+') do
                line = line:gsub('^%s+', ''):gsub('%s+$', '')
                if #line > 0 then
                    if #line > 50 then bad = ('"%s" is longer than 50 characters.'):format(short(line, 20)) end
                    opts[#opts + 1] = line
                end
            end
            if not bad and (#opts < 2 or #opts > 10) then bad = 'Enter 2 to 10 options.' end
            if not bad then q.options = opts break end
            notify(bad, 'error')
        end
    end
    return q
end

local function openFormEditor(m)
    local form = call('getForm', m.name)
    if not form then return notify('Applications are off for this job.', 'error') end
    local draft = { intro = form.intro or '', questions = lib.table.deepclone(form.questions or {}) }
    local dirty = false
    local max = form.maxQuestions or 15
    local show

    local function leave(after)
        CreateThread(function()
            if dirty and not UI.confirm({ header = 'Discard changes?', content = 'You have unsaved changes to this form. Discard them?', type = 'warning', confirm = 'Discard', cancel = 'Keep editing' }) then
                return show()
            end
            if after then after() end
        end)
    end

    local function openQuestion(i)
        local q = draft.questions[i]
        UI.registerMenu({
            id = 'blaze_boss_form_q', title = ('%d. %s'):format(i, short(q.label, 40)), menu = 'blaze_boss_form',
            options = {
                { title = 'Edit', icon = 'fa-solid fa-pen', onSelect = function()
                    local nq = questionDialog(q)
                    if nq then draft.questions[i] = nq dirty = true end
                    show()
                end },
                { title = 'Move up', icon = 'fa-solid fa-arrow-up', disabled = i == 1, onSelect = function()
                    draft.questions[i], draft.questions[i - 1] = draft.questions[i - 1], draft.questions[i]
                    dirty = true
                    show()
                end },
                { title = 'Move down', icon = 'fa-solid fa-arrow-down', disabled = i == #draft.questions, onSelect = function()
                    draft.questions[i], draft.questions[i + 1] = draft.questions[i + 1], draft.questions[i]
                    dirty = true
                    show()
                end },
                { title = 'Delete', icon = 'fa-solid fa-trash', iconColor = '#E5484D', disabled = #draft.questions <= 1, onSelect = function()
                    if UI.confirm({ header = 'Delete question', content = ('Delete "%s"?'):format(q.label), type = 'error', confirm = 'Delete' }) then
                        table.remove(draft.questions, i)
                        dirty = true
                    end
                    show()
                end },
            },
        })
        UI.showMenu('blaze_boss_form_q')
    end

    show = function()
        local options = {
            { title = 'Back to applications', icon = 'fa-solid fa-angle-left', onSelect = function() leave(function() openApps(m) end) end },
            { title = 'Add question', icon = 'fa-solid fa-plus', disabled = #draft.questions >= max,
              description = ('%d of %d questions'):format(#draft.questions, max), onSelect = function()
                local q = questionDialog(nil)
                if q then draft.questions[#draft.questions + 1] = q dirty = true end
                show()
            end },
            { title = 'Edit intro text', icon = 'fa-solid fa-align-left', description = short(draft.intro ~= '' and draft.intro or 'No intro', 60), onSelect = function()
                local v = UI.input('Intro text', { { type = 'textarea', label = 'Shown before the form (max 500 characters)', default = draft.intro, maxLength = 500 } })
                if v then draft.intro = v[1] or '' dirty = true end
                show()
            end },
            { title = 'Preview form', icon = 'fa-solid fa-eye', description = 'Shows the exact applicant form. Nothing is sent.', onSelect = function()
                UI.confirm({ header = 'Apply for ' .. m.label, content = (draft.intro ~= '' and draft.intro or 'No intro text.') .. '\n\nYour name is taken from your character automatically.', type = 'info', confirm = 'Continue' })
                UI.input('Preview · ' .. m.label, buildFields(draft.questions), { submitText = 'Preview only' })
                notify('Preview only. Nothing was sent.', 'inform')
                show()
            end },
            { title = 'Save form', icon = 'fa-solid fa-floppy-disk', description = dirty and 'You have unsaved changes' or 'No changes', disabled = not dirty, onSelect = function()
                if UI.confirm({ header = 'Save form', content = 'Save this form? New applicants will see it. Applications already sent keep their own questions and answers.', type = 'info', confirm = 'Save' }) then
                    if result(call('saveForm', m.name, draft)) then dirty = false end
                end
                show()
            end },
            { title = 'Reset to default', icon = 'fa-solid fa-rotate-left', description = form.custom and 'Go back to the form in config.lua' or 'Already using the default form', onSelect = function()
                if UI.confirm({ header = 'Reset form', content = 'Delete the saved form for ' .. m.label .. ' and use the default from config.lua?', type = 'warning', confirm = 'Reset' }) then
                    if result(call('resetForm', m.name)) then dirty = false return openFormEditor(m) end
                end
                show()
            end },
        }
        for i, q in ipairs(draft.questions) do
            options[#options + 1] = {
                title = ('%d. %s'):format(i, q.label), icon = 'fa-solid fa-circle-question', arrow = true,
                description = FRIENDLY[q.type] .. (q.required and ' · Required' or ' · Optional'),
                onSelect = function() openQuestion(i) end,
            }
        end
        UI.registerMenu({ id = 'blaze_boss_form', title = 'Edit form · ' .. m.label .. (dirty and ' *' or ''), options = options,
            onExit = function() if dirty then leave() end end })
        UI.showMenu('blaze_boss_form')
    end
    show()
end

---------------------------------------------------------------------------
-- Applications (managers)
---------------------------------------------------------------------------
local FILTERS = { review = 'To review', accepted = 'Accepted', denied = 'Denied', withdrawn = 'Withdrawn' }
local NEXT_FILTER = { review = 'accepted', accepted = 'denied', denied = 'withdrawn', withdrawn = 'review' }
local STATUS_ICON = { new = 'fa-solid fa-envelope', interview = 'fa-solid fa-comments', accepted = 'fa-solid fa-check', denied = 'fa-solid fa-xmark', withdrawn = 'fa-solid fa-rotate-left' }

--- Message dialog with optional ready-made replies (Config.applications.quickReplies[kind]).
--- Returns the text, or nil if cancelled.
local function messageDialog(title, label, kind, default)
    local replies = (Config.applications.quickReplies or {})[kind] or {}
    if #replies == 0 then
        local v = UI.input(title, { { type = 'textarea', label = label, required = true, minLength = 1, maxLength = 300, default = default } })
        return v and v[1] or nil
    end
    local opts = { { value = 'own', label = 'Write my own (below)' } }
    for i, r in ipairs(replies) do opts[#opts + 1] = { value = tostring(i), label = short(r, 60) } end
    while true do
        local v = UI.input(title, {
            { type = 'select', label = 'Quick reply', options = opts, default = 'own' },
            { type = 'textarea', label = label, maxLength = 300, default = default },
        })
        if not v then return nil end
        if v[2] and v[2] ~= '' then return v[2] end
        local i = tonumber(v[1])
        if i and replies[i] then return replies[i] end
        notify('Pick a quick reply or write a message.', 'error')
    end
end

local function openApp(m, id, filter)
    local a = call('getApplication', m.name, id)
    if not a then return notify('Application not found.', 'error') end
    local decided = a.status == 'accepted' or a.status == 'denied' or a.status == 'withdrawn'
    local back = function()
        local again = call('getMenu', m.gtype, m.name) or m
        again.fromReview = m.fromReview
        openApps(again, filter)
    end
    local reopen = function() openApp(m, id, filter) end
    local statusLine = a.statusLabel or a.status
    if a.reviewed_by then statusLine = statusLine .. ' · by ' .. a.reviewed_by end
    local meta = {}
    if a.deny_reason then meta[#meta + 1] = { label = 'Deny reason', value = a.deny_reason } end
    if a.interview_msg then meta[#meta + 1] = { label = 'Interview message', value = a.interview_msg } end
    local options = {
        { title = a.name, description = statusLine, icon = STATUS_ICON[a.status] or 'fa-solid fa-file', readOnly = true,
          metadata = #meta > 0 and meta or nil },
    }
    for _, ans in ipairs(a.answers or {}) do
        local text = answerText(ans)
        options[#options + 1] = {
            title = ans.label, description = short(text, 80), icon = 'fa-regular fa-comment', readOnly = true,
            metadata = #text > 80 and { { label = 'Answer', value = text } } or nil,
        }
    end
    if a.votes then
        local mine = a.votes.mine
        local voterMeta = {}
        for _, s in ipairs(a.votes.voters) do voterMeta[#voterMeta + 1] = s end
        options[#options + 1] = { title = ('Team vote: %d for · %d against'):format(a.votes.up, a.votes.down), icon = 'fa-solid fa-square-poll-vertical',
            description = mine == 1 and 'You voted for' or (mine == -1 and 'You voted against' or 'You haven\'t voted'), readOnly = true,
            metadata = #voterMeta > 0 and voterMeta or nil }
        options[#options + 1] = { title = mine == 1 and 'Remove your vote' or 'Vote for', icon = 'fa-solid fa-thumbs-up', iconColor = '#3DDC84', onSelect = function()
            result(call('voteApplication', m.name, a.id, mine == 1 and 0 or 1)) reopen()
        end }
        options[#options + 1] = { title = mine == -1 and 'Remove your vote' or 'Vote against', icon = 'fa-solid fa-thumbs-down', iconColor = '#E5484D', onSelect = function()
            result(call('voteApplication', m.name, a.id, mine == -1 and 0 or -1)) reopen()
        end }
    end
    options[#options + 1] = { title = 'Invite to interview', icon = 'fa-solid fa-comments', disabled = decided, onSelect = function()
        local msg = messageDialog('Invite ' .. a.name, 'Message (when / where)', 'interview', a.interview_msg)
        if msg then result(call('interview', m.name, a.id, msg)) end
        reopen()
    end }
    options[#options + 1] = { title = 'Accept & hire', icon = 'fa-solid fa-user-check', iconColor = '#3DDC84', disabled = decided, onSelect = function()
        local grade = pickRank(m, 'Hire ' .. a.name)
        if grade and UI.confirm({ header = 'Accept & hire', content = ('Hire %s into %s?'):format(a.name, m.label), type = 'info', confirm = 'Hire' }) then
            if result(call('accept', m.name, a.id, grade)) then return back() end
        end
        reopen()
    end }
    options[#options + 1] = { title = 'Deny', icon = 'fa-solid fa-xmark', iconColor = '#E5484D', disabled = decided, onSelect = function()
        local reason = messageDialog('Deny ' .. a.name, 'Reason (the applicant sees this)', 'deny')
        if reason and UI.confirm({ header = 'Deny application', content = ('Deny %s\'s application?'):format(a.name), type = 'error', confirm = 'Deny' }) then
            if result(call('deny', m.name, a.id, reason)) then return back() end
        end
        reopen()
    end }
    options[#options + 1] = { title = a.notes and a.notes ~= '' and 'Edit note' or 'Add note', icon = 'fa-solid fa-note-sticky',
        description = a.notes and a.notes ~= '' and short(a.notes, 60) or 'Only managers see notes', onSelect = function()
        local v = UI.input('Note · ' .. a.name, { { type = 'textarea', label = 'Note', default = a.notes, maxLength = 1000 } })
        if v then result(call('saveNote', m.name, a.id, v[1] or '')) end
        reopen()
    end }
    UI.registerMenu({ id = 'blaze_boss_app', title = 'Application #' .. a.id, menu = 'blaze_boss_apps', options = options })
    UI.showMenu('blaze_boss_app')
end

openApps = function(m, filter)
    filter = filter or 'review'
    local list = call('getApplications', m.name, filter) or {}
    local options = {
        { title = 'Accepting applications: ' .. (m.appsOpen and 'On' or 'Off'), icon = m.appsOpen and 'fa-solid fa-toggle-on' or 'fa-solid fa-toggle-off',
          iconColor = m.appsOpen and '#3DDC84' or '#8F99A5', description = 'Click to turn ' .. (m.appsOpen and 'off' or 'on'), onSelect = function()
            local ok, msg, open = call('toggleApplications', m.name)
            result(ok, msg)
            if ok then m.appsOpen = open end
            openApps(m, filter)
        end },
    }
    if m.formEdit then
        options[#options + 1] = { title = 'Edit application form', icon = 'fa-solid fa-pen-to-square', arrow = true, onSelect = function() openFormEditor(m) end }
    end
    options[#options + 1] = { title = 'Showing: ' .. FILTERS[filter], icon = 'fa-solid fa-filter', description = 'Click for ' .. FILTERS[NEXT_FILTER[filter]],
        onSelect = function() openApps(m, NEXT_FILTER[filter]) end }
    for _, a in ipairs(list) do
        options[#options + 1] = {
            title = a.name, description = ('%s · %s'):format(a.status == 'new' and 'New' or (a.status == 'interview' and 'Interview' or a.status:gsub('^%l', string.upper)), a.created or ''),
            icon = STATUS_ICON[a.status] or 'fa-solid fa-file', arrow = true,
            onSelect = function() openApp(m, a.id, filter) end,
        }
    end
    if #list == 0 then options[#options + 1] = { title = 'No applications here', readOnly = true } end
    -- opened from a review point: no "back" to the boss menu (they may not be at a desk)
    UI.registerMenu({ id = 'blaze_boss_apps', title = 'Applications · ' .. m.label, menu = not m.fromReview and 'blaze_boss_main' or nil, options = options })
    UI.showMenu('blaze_boss_apps')
end

---------------------------------------------------------------------------
-- Funds
---------------------------------------------------------------------------
local openFunds

local function moneyDialog(m, kind, confirmAbove)
    local deposit = kind == 'deposit'
    local v = UI.input(deposit and 'Deposit cash' or 'Withdraw cash', {
        { type = 'number', label = 'Amount', required = true, min = 1 },
        { type = 'input', label = 'Reason', required = true, minLength = 1, maxLength = 100 },
    })
    if not v or not v[1] then return end
    local amount = math.floor(v[1])
    if amount >= (confirmAbove or 5000) then
        if not UI.confirm({ header = deposit and 'Confirm deposit' or 'Confirm withdrawal',
                content = ('%s %s %s %s?'):format(deposit and 'Deposit' or 'Withdraw', money(amount), deposit and 'into' or 'from', m.label),
                type = deposit and 'info' or 'warning' }) then return end
    end
    result(call(kind, m.gtype, m.name, amount, v[2]))
end

openFunds = function(m)
    local d, err = call('getFunds', m.gtype, m.name)
    if not d then return notify(err or 'Funds are not available.', 'error') end
    local history = {}
    local KIND = { deposit = { '+', 'fa-solid fa-arrow-down', '#3DDC84' }, withdraw = { '-', 'fa-solid fa-arrow-up', '#F0A93B' }, bonus = { '-', 'fa-solid fa-gift', '#A78BFA' } }
    for _, h in ipairs(d.history or {}) do
        local k = KIND[h.type] or KIND.withdraw
        history[#history + 1] = {
            title = ('%s %s%s'):format(k[1], money(h.amount), h.type == 'bonus' and '  (bonus)' or ''),
            description = ('%s · %s · %s'):format(h.name or '?', short(h.reason or '', 40), h.at or ''),
            icon = k[2], iconColor = k[3], readOnly = true,
            metadata = #(h.reason or '') > 40 and { { label = 'Reason', value = h.reason } } or nil,
        }
    end
    if #history == 0 then history[1] = { title = 'No transactions yet', readOnly = true } end
    UI.registerMenu({ id = 'blaze_boss_funds_history', title = 'Recent history · ' .. m.label, menu = 'blaze_boss_funds', options = history })
    local options = {
        { title = 'Balance', description = money(d.balance), icon = 'fa-solid fa-building-columns', readOnly = true },
        { title = 'Deposit', description = 'Put your cash into the account', icon = 'fa-solid fa-money-bill-wave', onSelect = function() moneyDialog(m, 'deposit', d.confirmAbove) openFunds(m) end },
        { title = 'Withdraw', description = d.left and ('Your rank can take out %s more today'):format(money(math.max(0, d.left))) or 'Take cash out of the account',
          icon = 'fa-solid fa-hand-holding-dollar', onSelect = function() moneyDialog(m, 'withdraw', d.confirmAbove) openFunds(m) end },
    }
    if Config.funds.bonuses then
        options[#options + 1] = { title = 'Bonus everyone on duty', description = 'Each person on duty (except you) gets the amount in their bank',
            icon = 'fa-solid fa-gifts', iconColor = '#A78BFA', onSelect = function()
                local v = UI.input('Bonus everyone on duty', {
                    { type = 'number', label = ('Amount per person (max $%d)'):format(Config.funds.maxBonus or 5000), required = true, min = 1, max = Config.funds.maxBonus or 5000 },
                    { type = 'input', label = 'Reason', required = true, minLength = 1, maxLength = 100 },
                })
                if v and v[1] and UI.confirm({ header = 'Bonus everyone on duty', content = ('Pay %s to each person on duty? The total comes out of %s funds.'):format(money(v[1]), m.label), type = 'warning', confirm = 'Pay bonuses' }) then
                    result(call('bonus', m.gtype, m.name, 'onduty', nil, math.floor(v[1]), v[2]))
                end
                openFunds(m)
            end }
    end
    options[#options + 1] = { title = 'Recent history', icon = 'fa-solid fa-clock-rotate-left', menu = 'blaze_boss_funds_history', arrow = true }
    UI.registerMenu({ id = 'blaze_boss_funds', title = 'Funds · ' .. money(d.balance), menu = 'blaze_boss_main', options = options })
    UI.showMenu('blaze_boss_funds')
end

---------------------------------------------------------------------------
-- Grade editor (Qbox, from qbx_management)
---------------------------------------------------------------------------
local function openGrades(m)
    local options = {}
    for _, g in ipairs(m.grades or {}) do
        options[#options + 1] = {
            title = g.name, icon = 'fa-solid fa-pen-to-square',
            description = ('Rank %d%s%s'):format(g.level, g.isboss and ' · Boss' or '', g.payment and (' · ' .. money(g.payment)) or ''),
            disabled = g.level > m.limit and g.level ~= m.ownGrade,
            onSelect = function()
                local fields = { { type = 'input', label = 'Rank name', default = g.name, required = true, minLength = 1, maxLength = 50 } }
                if m.gtype == 'job' then
                    fields[#fields + 1] = { type = 'number', label = 'Pay', default = g.payment or 0, min = 0, max = 1000000, required = true }
                end
                fields[#fields + 1] = { type = 'checkbox', label = 'Boss (can open this menu)', checked = g.isboss }
                if m.gtype == 'job' then fields[#fields + 1] = { type = 'checkbox', label = 'Bank access', checked = g.bankAuth } end
                local v = UI.input(('%s: %s'):format(m.label, g.name), fields)
                if v then
                    local data = { name = v[1] }
                    if m.gtype == 'job' then data.payment, data.isboss, data.bankAuth = v[2], v[3], v[4]
                    else data.isboss = v[2] end
                    result(call('modifyGrade', m.gtype, m.name, g.level, data))
                end
                openGroup(m.gtype, m.name)
            end,
        }
    end
    UI.registerMenu({ id = 'blaze_boss_grades', title = 'Ranks · ' .. m.label, menu = 'blaze_boss_main', options = options })
    UI.showMenu('blaze_boss_grades')
end

---------------------------------------------------------------------------
-- Payroll, announcements, activity log
---------------------------------------------------------------------------
local function openPayroll(m)
    local d = call('getPayroll', m.gtype, m.name)
    if not d then return notify('Payroll isn\'t available.', 'error') end
    local options = {
        { title = 'One paycheck, everyone', description = money(d.perPaycheckAll), icon = 'fa-solid fa-users', readOnly = true },
        { title = 'One paycheck, on duty now', description = money(d.perPaycheckOnDuty), icon = 'fa-solid fa-user-check', iconColor = '#3DDC84', readOnly = true },
    }
    for i = #d.grades, 1, -1 do
        local g = d.grades[i]
        options[#options + 1] = { title = ('%s · %s'):format(g.name, money(g.pay)), icon = 'fa-solid fa-money-check-dollar', readOnly = true,
            description = ('%d member%s · %d on duty'):format(g.members, g.members == 1 and '' or 's', g.onduty) }
    end
    UI.registerMenu({ id = 'blaze_boss_payroll', title = 'Payroll · ' .. m.label, menu = 'blaze_boss_main', options = options })
    UI.showMenu('blaze_boss_payroll')
end

local function openAnnouncement(m)
    local a = call('getAnnouncement', m.gtype, m.name)
    local options = {}
    if a then
        options[#options + 1] = { title = 'Current announcement', description = short(a.message, 80), icon = 'fa-solid fa-bullhorn', iconColor = '#A78BFA', readOnly = true,
            metadata = { { label = 'From', value = a.by_name or '?' }, { label = 'Posted', value = a.at or '' }, { label = 'Message', value = a.message } } }
    else
        options[#options + 1] = { title = 'No announcement right now', icon = 'fa-solid fa-bullhorn', readOnly = true }
    end
    options[#options + 1] = { title = a and 'Post a new one' or 'Post announcement', icon = 'fa-solid fa-pen', description = 'On-duty staff see it now, others when they clock in',
        onSelect = function()
            local v = UI.input('Announcement · ' .. m.label, { { type = 'textarea', label = 'Message', required = true, minLength = 1, maxLength = 500 } })
            if v then result(call('postAnnouncement', m.gtype, m.name, v[1])) end
            openAnnouncement(m)
        end }
    options[#options + 1] = { title = 'Clear announcement', icon = 'fa-solid fa-eraser', disabled = not a, onSelect = function()
        if UI.confirm({ header = 'Clear announcement', content = 'Remove the current announcement?', type = 'warning', confirm = 'Clear' }) then
            result(call('postAnnouncement', m.gtype, m.name, ''))
        end
        openAnnouncement(m)
    end }
    UI.registerMenu({ id = 'blaze_boss_announce', title = 'Announcement · ' .. m.label, menu = 'blaze_boss_main', options = options })
    UI.showMenu('blaze_boss_announce')
end

local AUDIT_ICON = {
    hire = 'fa-solid fa-user-plus', accept = 'fa-solid fa-user-check', fire = 'fa-solid fa-user-slash', promote = 'fa-solid fa-arrow-up',
    demote = 'fa-solid fa-arrow-down', deposit = 'fa-solid fa-arrow-down', withdraw = 'fa-solid fa-arrow-up', bonus = 'fa-solid fa-gift',
    deny = 'fa-solid fa-xmark', interview = 'fa-solid fa-comments', record = 'fa-solid fa-folder-open', eotw = 'fa-solid fa-star',
    announce = 'fa-solid fa-bullhorn', callsign = 'fa-solid fa-hashtag', checkin = 'fa-solid fa-door-open',
}
local function openAudit(m)
    local rows = call('getAudit', m.gtype, m.name) or {}
    local options = {}
    for _, r in ipairs(rows) do
        options[#options + 1] = { title = short(r.message or r.event, 60), description = ('%s · %s'):format(r.actor or 'system', r.at or ''),
            icon = AUDIT_ICON[r.event] or 'fa-solid fa-circle-dot', readOnly = true,
            metadata = #(r.message or '') > 60 and { { label = 'Details', value = r.message } } or nil }
    end
    if #options == 0 then options[1] = { title = 'Nothing yet', readOnly = true } end
    UI.registerMenu({ id = 'blaze_boss_audit', title = 'Activity log · ' .. m.label, menu = 'blaze_boss_main', options = options })
    UI.showMenu('blaze_boss_audit')
end

---------------------------------------------------------------------------
-- Main menu
---------------------------------------------------------------------------
local function openPicker(list)
    local options = {}
    for _, g in ipairs(list) do
        options[#options + 1] = { title = g.label, description = g.gtype == 'gang' and 'Gang' or 'Job', icon = g.gtype == 'gang' and 'fa-solid fa-users-rectangle' or 'fa-solid fa-briefcase',
            arrow = true, onSelect = function() openGroup(g.gtype, g.name, true) end }
    end
    UI.registerMenu({ id = 'blaze_boss_pick', title = 'Pick a job', options = options })
    UI.showMenu('blaze_boss_pick')
end

openGroup = function(gtype, name, fromPicker)
    local m = call('getMenu', gtype, name)
    if not m then return notify('You are not a manager here.', 'error') end
    local options = {
        { title = gtype == 'gang' and 'Members' or 'Staff', description = 'Promote, demote, ' .. (m.callsigns and 'callsigns, ' or '') .. (gtype == 'gang' and 'kick' or 'fire'),
          icon = 'fa-solid fa-users', arrow = true, onSelect = function() openStaff(m) end },
        { title = 'Hire', description = 'Hire someone nearby or by server ID', icon = 'fa-solid fa-user-plus', arrow = true, onSelect = function() openHire(m) end },
    }
    if m.apps then
        options[#options + 1] = { title = 'Applications', icon = 'fa-solid fa-file-signature', arrow = true,
            description = ('%d new · %s'):format(m.newApps or 0, m.appsOpen and 'Open' or 'Closed'), onSelect = function() openApps(m) end }
    end
    if m.funds then
        options[#options + 1] = { title = 'Funds', description = 'Balance: ' .. money(m.balance), icon = 'fa-solid fa-building-columns', arrow = true, onSelect = function() openFunds(m) end }
    end
    if m.gradeEdit then
        options[#options + 1] = { title = 'Manage ranks', description = 'Rank names, pay and boss access', icon = 'fa-solid fa-clipboard-list', arrow = true, onSelect = function() openGrades(m) end }
    end
    local FT = Config.features or {}
    if gtype == 'job' and Config.funds.payroll then
        options[#options + 1] = { title = 'Payroll', description = 'Pay per rank and what a paycheck costs', icon = 'fa-solid fa-file-invoice-dollar', arrow = true, onSelect = function() openPayroll(m) end }
    end
    if FT.announcements then
        options[#options + 1] = { title = 'Announcement', description = 'Post a message to your department', icon = 'fa-solid fa-bullhorn', arrow = true, onSelect = function() openAnnouncement(m) end }
    end
    if (Config.outfits or {}).enabled and BMC then
        options[#options + 1] = { title = 'Outfits', description = 'Save uniforms for your ranks', icon = 'fa-solid fa-shirt', arrow = true,
            onSelect = function() BMC.openOutfitManager(m) end }
    end
    if ((Config.managerPlacement or {}).enabled or m.isAdmin) and BMC and BMC.openLocations then
        options[#options + 1] = { title = 'Locations', description = 'Boss desk, duty, wardrobe and application points', icon = 'fa-solid fa-location-dot', arrow = true,
            onSelect = function() BMC.openLocations(m) end }
    end
    local CT = Config.contract or {}
    if CT.enabled and BMC and (CT.editor == 'management' or (CT.editor == 'admin' and m.isAdmin)) then
        options[#options + 1] = { title = 'Employment contract', description = 'Edit the contract new hires sign', icon = 'fa-solid fa-file-contract', arrow = true,
            onSelect = function() BMC.openContractEditor(m) end }
    end
    if FT.auditLog then
        options[#options + 1] = { title = 'Activity log', description = 'Recent hires, promotions, money moves…', icon = 'fa-solid fa-list-check', arrow = true, onSelect = function() openAudit(m) end }
    end
    for _, item in pairs(dynamicItems) do
        if item.args and type(item.args.type) == 'string' and item.args.type:lower() == gtype then options[#options + 1] = item end
    end
    UI.registerMenu({ id = 'blaze_boss_main', title = m.label .. ' · Management', menu = fromPicker and 'blaze_boss_pick' or nil, options = options })
    UI.showMenu('blaze_boss_main')
end

--- Open the boss menu. job = a job name (or nil to pick). gtype defaults to 'job'.
local function openBossMenu(job, gtype)
    refreshManaged()
    if job then
        gtype = gtype or 'job'
        if not managed[gtype .. ':' .. job] then return notify('You are not a manager here.', 'error') end
        return openGroup(gtype, job)
    end
    local list = {}
    for _, g in ipairs(myGroups) do if not gtype or g.gtype == gtype then list[#list + 1] = g end end
    if #list == 0 then return notify('You are not a manager of any ' .. (gtype or 'job') .. '.', 'error') end
    if #list == 1 then return openGroup(list[1].gtype, list[1].name) end
    openPicker(list)
end
exports('openBossMenu', function(job) openBossMenu(job, 'job') end)

---------------------------------------------------------------------------
-- Applicants
---------------------------------------------------------------------------
local function openApplication(job)
    if not Config.jobs[job] then return end
    local form = call('getForm', job)
    if not form then return notify('This job doesn\'t take applications.', 'error', 'Application') end
    if not form.open then return notify(('%s is not accepting applications right now.'):format(form.label), 'error', 'Application') end
    if not UI.confirm({ header = 'Apply for ' .. form.label, content = (form.intro ~= '' and form.intro or 'Fill in the form to apply.') .. '\n\nYour name is taken from your character automatically.',
            type = 'info', confirm = 'Start' }) then return end
    local fields, answers = nil, nil
    while true do
        fields = buildFields(form.questions, answers)
        local v = UI.input('Apply · ' .. form.label, fields, { submitText = 'Send application' })
        if not v then return end
        local ok, msg = call('submitApplication', job, v)
        if ok then return notify(msg, 'success', 'Application') end
        notify(msg or 'Your application could not be sent.', 'error', 'Application')
        if msg and (msg:find('already') or msg:find('not accepting') or msg:find('denied') or msg:find('turned off') or msg:find('doesn\'t take')) then return end
        answers = v
    end
end
exports('openApplication', openApplication)

---------------------------------------------------------------------------
-- My applications (status menu: /applicationstatus, the application point, or the export)
---------------------------------------------------------------------------
local STATUS_COLOR = { new = '#5AA9FF', interview = '#F0A93B', accepted = '#3DDC84', denied = '#E5484D', withdrawn = '#8F99A5' }
local openMyApplications

local function openMyApplication(a, job)
    local options = {
        { title = a.statusLabel or a.status, description = a.message, icon = STATUS_ICON[a.status] or 'fa-solid fa-file',
          iconColor = STATUS_COLOR[a.status], readOnly = true },
    }
    if a.status == 'interview' and a.interviewMsg then
        options[#options + 1] = { title = 'Interview details', description = short(a.interviewMsg, 80), icon = 'fa-solid fa-comments', readOnly = true,
            metadata = #a.interviewMsg > 80 and { { label = 'Message', value = a.interviewMsg } } or nil }
    end
    if a.status == 'denied' then
        if a.denyReason then
            options[#options + 1] = { title = 'Reason', description = short(a.denyReason, 80), icon = 'fa-solid fa-circle-info', readOnly = true,
                metadata = #a.denyReason > 80 and { { label = 'Reason', value = a.denyReason } } or nil }
        end
        options[#options + 1] = { title = a.reapplyAt and ('You can apply again after ' .. a.reapplyAt) or 'You can apply again',
            icon = 'fa-solid fa-hourglass-half', readOnly = true }
    end
    options[#options + 1] = { title = 'Sent', description = a.created or '', icon = 'fa-regular fa-calendar', readOnly = true }
    if a.reviewedBy then
        options[#options + 1] = { title = 'Reviewed by', description = ('%s · %s'):format(a.reviewedBy, a.updated or ''), icon = 'fa-solid fa-user-tie', readOnly = true }
    end
    for _, ans in ipairs(a.answers or {}) do
        local text = answerText(ans)
        options[#options + 1] = { title = ans.label, description = short(text, 80), icon = 'fa-regular fa-comment', readOnly = true,
            metadata = #text > 80 and { { label = 'Your answer', value = text } } or nil }
    end
    if Config.applications.allowWithdraw and (a.status == 'new' or a.status == 'interview') then
        options[#options + 1] = { title = 'Withdraw application', icon = 'fa-solid fa-rotate-left', iconColor = '#E5484D', onSelect = function()
            if UI.confirm({ header = 'Withdraw application', content = ('Withdraw your %s application? You can apply again later.'):format(a.jobLabel), type = 'warning', confirm = 'Withdraw' }) then
                result(call('withdrawApplication', a.id))
            end
            openMyApplications(job)
        end }
    end
    UI.registerMenu({ id = 'blaze_boss_myapp', title = ('%s · Application #%d'):format(a.jobLabel, a.id), menu = 'blaze_boss_myapps', options = options })
    UI.showMenu('blaze_boss_myapp')
end

--- job = nil lists every job they applied to; a job name shows only that job
openMyApplications = function(job)
    if not Config.applications.enabled then return notify('Applications are turned off on this server.', 'error', 'Application') end
    local list = call('getMyApplications', job) or {}
    local options = {}
    for _, a in ipairs(list) do
        options[#options + 1] = {
            title = a.jobLabel, description = ('%s · %s'):format(a.statusLabel or a.status, a.created or ''),
            icon = STATUS_ICON[a.status] or 'fa-solid fa-file', iconColor = STATUS_COLOR[a.status], arrow = true,
            onSelect = function() openMyApplication(a, job) end,
        }
    end
    if #options == 0 then
        options[1] = { title = job and 'You haven\'t applied here yet' or 'You haven\'t applied anywhere yet',
            description = 'Find an application point to apply', icon = 'fa-solid fa-circle-info', readOnly = true }
    end
    local title = job and ((Config.jobs[job] or {}).label or job) .. ' · My applications' or 'My applications'
    UI.registerMenu({ id = 'blaze_boss_myapps', title = title, options = options })
    UI.showMenu('blaze_boss_myapps')
end

local function openApplicationStatus(job)
    if job and not Config.jobs[job] then return end
    openMyApplications(job)
end
exports('openApplicationStatus', openApplicationStatus)

if Config.applications.enabled and Config.applications.statusCommand then
    RegisterCommand(Config.applications.statusCommand, function() openMyApplications(nil) end, false)
    TriggerEvent('chat:addSuggestion', '/' .. Config.applications.statusCommand, 'See the status of your job applications')
end

---------------------------------------------------------------------------
-- Review point: straight to that job's applications (managers only; the server checks)
---------------------------------------------------------------------------
local function openReview(job)
    local m = call('getMenu', 'job', job)
    if not m or not m.apps then return notify('You can\'t review applications here.', 'error') end
    m.fromReview = true
    openApps(m)
end

---------------------------------------------------------------------------
-- Hire consent (from qbx_management)
---------------------------------------------------------------------------
--- offer = { template, values = { job, rank, pay, probation, employee, manager, manager_rank, date, number }, contract, style, expectedName }
lib.callback.register(RES .. ':client:confirmHire', function(offer, seconds)
    if offer.contract then return BMC.signContract(offer, seconds) end -- client/features.lua
    local v = offer.values or {}
    local open = true
    SetTimeout((seconds or 30) * 1000, function() if open then UI.closeConfirm() end end)
    local ok = UI.confirm({ header = 'Job offer', content = ('%s (%s) wants to hire you into %s as %s. Do you accept?'):format(v.manager or '?', v.manager_rank or '', v.job or '?', v.rank or '?'),
        type = 'info', confirm = 'Accept', cancel = 'Decline' })
    open = false
    return { accepted = ok }
end)

---------------------------------------------------------------------------
-- Points -> targets
---------------------------------------------------------------------------
local handles = {}

local function buildTargets(points)
    for _, h in ipairs(handles) do Target.remove(h) end
    handles = {}
    local seen = {} -- the same kind of point for the same group twice on one spot would show its options twice
    for _, p in ipairs(points or {}) do
        local coords = vec3(p.coords.x, p.coords.y, p.coords.z)
        local key = p.type .. ':' .. p.gtype .. ':' .. p.group
        local dup = false
        for _, c in ipairs(seen[key] or {}) do if #(c - coords) < 1.5 then dup = true break end end
        seen[key] = seen[key] or {}
        table.insert(seen[key], coords)
        if dup then p.dup = true goto continue end
        local cfg = (p.gtype == 'gang' and (Config.gangs or {}) or Config.jobs)[p.group] or {}
        local label = cfg.label or p.group
        local options
        if p.type == 'boss' then
            options = { {
                name = 'blaze_boss_desk', label = label .. ' management', icon = 'fa-solid fa-briefcase',
                canInteract = function() return managed[p.gtype .. ':' .. p.group] == true end,
                onSelect = function() openGroup(p.gtype, p.group) end,
            } }
        elseif p.type == 'duty' then
            options = { {
                name = 'blaze_boss_duty', label = 'Time clock · ' .. label, icon = 'fa-solid fa-clock',
                canInteract = function() return member[p.gtype .. ':' .. p.group] == true end,
                onSelect = function()
                    -- 'clock' = the time clock screen, 'instant' = just toggle duty
                    if (Config.duty or {}).style ~= 'instant' and BMC and BMC.openClock then return BMC.openClock(p.group) end
                    local ok, msg, onDuty = call('toggleDuty', p.group)
                    lib.notify({ title = label, description = msg or (ok and 'Done.' or 'That didn\'t work.'), type = ok and (onDuty and 'success' or 'inform') or 'error' })
                end,
            } }
        elseif p.type == 'outfits' then
            options = {
                { name = 'blaze_boss_wardrobe', label = label .. ' wardrobe', icon = 'fa-solid fa-shirt',
                  canInteract = function() return member[p.gtype .. ':' .. p.group] == true or managed[p.gtype .. ':' .. p.group] == true end,
                  onSelect = function() BMC.openWardrobe(p.gtype, p.group, label) end },
                { name = 'blaze_boss_ownclothes', label = 'Back to my own clothes', icon = 'fa-solid fa-person',
                  canInteract = function() return member[p.gtype .. ':' .. p.group] == true or managed[p.gtype .. ':' .. p.group] == true end,
                  onSelect = function() BMC.ownClothes() end },
            }
        elseif p.type == 'review' then
            options = { {
                name = 'blaze_boss_review', label = 'Review ' .. label .. ' applications', icon = 'fa-solid fa-clipboard-check',
                canInteract = function() return managed[p.gtype .. ':' .. p.group] == true end,
                onSelect = function() openReview(p.group) end,
            } }
            if Config.applications.interviewCheckIn then
                -- applicants invited to an interview check in here (the server checks they have one)
                options[#options + 1] = {
                    name = 'blaze_boss_checkin', label = 'Check in for interview', icon = 'fa-solid fa-door-open',
                    canInteract = function() return managed[p.gtype .. ':' .. p.group] ~= true end,
                    onSelect = function() result(call('interviewCheckIn', p.group)) end,
                }
            end
        else
            options = {
                { name = 'blaze_boss_apply', label = 'Apply for ' .. label, icon = 'fa-solid fa-file-signature', onSelect = function() openApplication(p.group) end },
                { name = 'blaze_boss_status', label = 'My application status', icon = 'fa-solid fa-circle-info', onSelect = function() openApplicationStatus(p.group) end },
            }
        end
        p.targetOptions = options -- a PED / prop at the point gets the same options (client/features.lua)
        -- With a target script, a point with a PED or prop is targeted on that entity only (not the floor under it)
        if not (Bridge.target ~= 'none' and BMC and BMC.pointLook and BMC.pointLook(p)) then
            handles[#handles + 1] = Target.addPoint({ coords = coords, radius = p.radius or 1.0, options = options })
        end
        ::continue::
    end
    if BMC then BMC.onPoints(points) end -- PEDs / props at points (client/features.lua)
end

RegisterNetEvent(RES .. ':client:points', function(points) buildTargets(points) end)
-- "View as" preview started/stopped (/bossmenutest): refresh which desks and menus this player gets
RegisterNetEvent(RES .. ':client:viewAs', function() refreshManaged() end)
-- From the radial menu (client/features.lua). Local events only; the server re-checks everything.
AddEventHandler(RES .. ':client:openGroup', function(gtype, name) openGroup(gtype, name) end)
AddEventHandler(RES .. ':client:openReview', function(job) openReview(job) end)

CreateThread(function()
    Wait(1000)
    refreshManaged()
    buildTargets(call('getPoints'))
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= RES then return end
    for _, h in ipairs(handles) do pcall(Target.remove, h) end
end)

---------------------------------------------------------------------------
-- qbx_management / qb-bossmenu compatibility
---------------------------------------------------------------------------
--- menuItem = ox-style menu option with args.type = 'job'|'gang' (any case). Returns an id.
local function addMenuItem(menuItem)
    if type(menuItem) ~= 'table' or type(menuItem.args) ~= 'table' or not menuItem.args.type then return end
    local id = #dynamicItems + 1
    dynamicItems[id] = lib.table.deepclone(menuItem)
    return id
end
local function removeMenuItem(id) dynamicItems[id] = nil end
local function compatOpen(gtype) openBossMenu(nil, gtype == 'gang' and 'gang' or 'job') end

exports('OpenBossMenu', compatOpen)
exports('AddBossMenuItem', addMenuItem)
exports('AddGangMenuItem', addMenuItem)
exports('RemoveBossMenuItem', removeMenuItem)
exports('RemoveGangMenuItem', removeMenuItem)

if Config.qbxManagementCompat and GetResourceState('qbx_management') ~= 'started' then
    -- exports.qbx_management:X() calls from other scripts land here while qbx_management is stopped
    local map = { OpenBossMenu = compatOpen, AddBossMenuItem = addMenuItem, AddGangMenuItem = addMenuItem,
        RemoveBossMenuItem = removeMenuItem, RemoveGangMenuItem = removeMenuItem }
    for name, fn in pairs(map) do
        AddEventHandler(('__cfx_export_qbx_management_%s'):format(name), function(setCB) setCB(fn) end)
    end
    RegisterNetEvent('qb-bossmenu:client:OpenMenu', function() compatOpen('job') end)
    RegisterNetEvent('qb-gangmenu:client:OpenMenu', function() compatOpen('gang') end)
end
