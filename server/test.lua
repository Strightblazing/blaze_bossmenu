-- /bossmenutest (admins): fake staff and applications so one person can try the boss menu alone.
-- Test characters are real offline characters with citizen IDs starting 'BMTEST' and the license
-- 'blaze_bossmenu_test', so nobody can log in as them. "Remove all test data" deletes every trace.
-- Turn the command off with Config.testCommand = false.
if not Config.enabled or not BM or not Config.testCommand then return end

local RES = GetCurrentResourceName()
local PREFIX = 'BMTEST'
local LICENSE = 'blaze_bossmenu_test'
local register = BM.register

local FIRST = { 'Alex', 'Jordan', 'Casey', 'Riley', 'Morgan', 'Taylor', 'Jamie', 'Quinn', 'Avery', 'Drew', 'Sam', 'Rowan' }
local LAST = { 'Test', 'Sample', 'Demo', 'Tryout', 'Mock', 'Example' }

local function nextIds(n)
    local max = 0
    for _, r in ipairs(MySQL.query.await('SELECT citizenid FROM players WHERE citizenid LIKE ?', { PREFIX .. '%' }) or {}) do
        local num = tonumber(r.citizenid:sub(#PREFIX + 1))
        if num and num > max then max = num end
    end
    local out = {}
    for i = 1, n do out[i] = ('%s%02d'):format(PREFIX, max + i) end
    return out
end

local function groupJson(gtype, name, level)
    local grp = Bridge.GetGroup(gtype, name)
    local g = Bridge.GetGrade(gtype, name, level) or { name = tostring(level) }
    local data = { name = name, label = grp and grp.label or name, isboss = g.isboss == true, grade = { name = g.name, level = level } }
    if gtype == 'job' then data.payment, data.onduty, data.type = g.payment or 0, false, grp and grp.type end
    return json.encode(data)
end

--- Create one offline test character. gtype/name/grade = nil makes them unemployed (for applications).
local function createCharacter(cid, first, last, gtype, name, grade)
    local job = (gtype == 'job' and name) and groupJson('job', name, grade) or groupJson('job', 'unemployed', 0)
    local gang = (gtype == 'gang' and name) and groupJson('gang', name, grade) or groupJson('gang', 'none', 0)
    local charinfo = json.encode({ firstname = first, lastname = last, birthdate = '1995-01-01', gender = 0, nationality = 'Test', phone = '5550000', cid = 1 })
    MySQL.insert.await([[INSERT INTO players (citizenid, cid, license, name, money, charinfo, job, gang, position, metadata)
        VALUES (?, 1, ?, ?, ?, ?, ?, ?, ?, ?)]], {
        cid, LICENSE, ('%s %s'):format(first, last), json.encode({ cash = 0, bank = 0, crypto = 0 }), charinfo, job, gang,
        json.encode({ x = 0.0, y = 0.0, z = 0.0 }), json.encode({}),
    })
    if Bridge.framework == 'qbx' and gtype and name then
        MySQL.insert.await('INSERT INTO player_groups (citizenid, `group`, type, grade) VALUES (?, ?, ?, ?)', { cid, name, gtype, grade })
    end
end

local function randomName(i)
    return FIRST[math.random(#FIRST)], LAST[((i - 1) % #LAST) + 1]
end

register('testInfo', function(src)
    if not BM.isAdmin(src) then return nil end
    local groups = {}
    for _, gtype in ipairs({ 'job', 'gang' }) do
        for name, c in pairs((gtype == 'job' and Config.jobs or Config.gangs) or {}) do
            if Bridge.GroupExists(gtype, name) then groups[#groups + 1] = { gtype = gtype, name = name, label = c.label or name, apps = BM.appsOn(gtype, name) } end
        end
    end
    table.sort(groups, function(a, b) return a.label < b.label end)
    return {
        groups = groups,
        characters = MySQL.scalar.await('SELECT COUNT(*) FROM players WHERE citizenid LIKE ?', { PREFIX .. '%' }) or 0,
        applications = MySQL.scalar.await('SELECT COUNT(*) FROM blaze_boss_applications WHERE citizenid LIKE ?', { PREFIX .. '%' }) or 0,
    }
end)

--- 4 offline staff spread over the lower ranks, each set up to show a different badge
register('testAddStaff', function(src, gtype, name)
    if not BM.isAdmin(src) then return false, 'Admins only.' end
    if not BM.groupCfg(gtype, name) then return false, 'That group isn\'t configured.' end
    local grades = Bridge.GetGrades(gtype, name)
    if #grades < 2 then return false, 'This group needs at least 2 ranks.' end
    local function rank(i) return grades[math.min(i, math.max(1, #grades - 1))].level end -- never the top rank
    local plan = {
        { grade = rank(1), probation = true, note = 'New hire on probation' },
        { grade = rank(1), inactive = true, note = 'Inactive (last shift 12 days ago)' },
        { grade = rank(2), hours = 60, commend = true, note = 'Ready for promotion + a commendation' },
        { grade = rank(3), hours = 6, note = 'Regular' },
    }
    local ids = nextIds(#plan)
    local key = BM.gkey(gtype, name)
    local made = {}
    for i, p in ipairs(plan) do
        local cid = ids[i]
        local first, last = randomName(i)
        createCharacter(cid, first, last, gtype, name, p.grade)
        local days = tonumber((Config.features or {}).probationDays) or 0
        MySQL.insert.await(('INSERT INTO blaze_boss_members (citizenid, job, hired_at, probation_until) VALUES (?, ?, %s, %s)')
            :format(p.probation and 'NOW()' or 'NOW() - INTERVAL 40 DAY', (p.probation and days > 0) and ('NOW() + INTERVAL ' .. days .. ' DAY') or 'NULL'), { cid, key })
        if gtype == 'job' then
            local now = os.time()
            if p.hours then
                -- split into shifts over the past week so "this week" and "last 31 days" both show
                local per = math.floor(p.hours / 3 * 3600)
                for d = 1, 3 do
                    local start = now - d * 86400
                    MySQL.insert.await('INSERT INTO player_jobs_activity (citizenid, job, last_checkin, last_checkout) VALUES (?, ?, ?, ?)', { cid, name, start, start + per })
                end
            elseif p.inactive then
                local start = now - 12 * 86400
                MySQL.insert.await('INSERT INTO player_jobs_activity (citizenid, job, last_checkin, last_checkout) VALUES (?, ?, ?, ?)', { cid, name, start, start + 7200 })
            end
        end
        if p.commend then
            MySQL.insert.await('INSERT INTO blaze_boss_records (job, citizenid, type, text, by_name) VALUES (?, ?, ?, ?, ?)',
                { key, cid, 'commend', 'Test commendation: great work on a busy shift.', 'Test data' })
        end
        made[#made + 1] = ('%s %s (%s)'):format(first, last, p.note)
    end
    return true, ('Added %d test staff: %s'):format(#made, table.concat(made, '; '))
end)

local SAMPLE_TEXT = {
    'I have three years of experience and I work well under pressure with a team.',
    'I want to help people in the city and grow with a professional department.',
    'I am reliable, I show up on time, and I learn quickly from feedback.',
}

local function sampleAnswers(questions)
    local out = {}
    for i, q in ipairs(questions) do
        local a
        if q.type == 'checkbox' then a = true
        elseif q.type == 'number' then a = math.max(q.min or 21, math.min(q.max or 99, 25))
        elseif q.type == 'select' then a = q.options and q.options[math.random(#q.options)] or nil
        elseif q.type == 'textarea' then a = SAMPLE_TEXT[math.random(#SAMPLE_TEXT)]
        else a = ('555-01%02d'):format(math.random(0, 99)) end
        if (q.type == 'input' or q.type == 'textarea') and type(a) == 'string' then
            while q.min and #a < q.min do a = a .. ' ' .. SAMPLE_TEXT[1] end
            if q.max and #a > q.max then a = a:sub(1, q.max) end
        end
        out[i] = { label = q.label, type = q.type, answer = a }
    end
    return out
end

--- 3 applications (2 waiting, 1 invited to interview) from test characters with no job
register('testAddApplications', function(src, job)
    if not BM.isAdmin(src) then return false, 'Admins only.' end
    if not BM.appsOn('job', job) then return false, 'Applications are off for this job.' end
    local f = MySQL.single.await('SELECT questions FROM blaze_boss_forms WHERE job = ?', { job })
    local questions = f and json.decode(f.questions) or (Config.applications.defaultQuestions or {})
    local ids = nextIds(3)
    local names = {}
    for i, cid in ipairs(ids) do
        local first, last = randomName(i + 3)
        createCharacter(cid, first, last, nil, nil, nil)
        local status = i == 3 and 'interview' or 'new'
        MySQL.insert.await('INSERT INTO blaze_boss_applications (citizenid, job, name, answers, status, interview_msg) VALUES (?, ?, ?, ?, ?, ?)',
            { cid, job, ('%s %s'):format(first, last), json.encode(sampleAnswers(questions)), status, status == 'interview' and 'Test: come to the front desk at 6pm.' or nil })
        names[#names + 1] = ('%s %s'):format(first, last)
    end
    return true, ('Added 3 test applications: %s'):format(table.concat(names, ', '))
end)

register('testClear', function(src)
    if not BM.isAdmin(src) then return false, 'Admins only.' end
    local like = PREFIX .. '%'
    local apps = MySQL.query.await('SELECT id FROM blaze_boss_applications WHERE citizenid LIKE ?', { like }) or {}
    for _, a in ipairs(apps) do MySQL.query.await('DELETE FROM blaze_boss_app_votes WHERE app_id = ?', { a.id }) end
    for _, t in ipairs({ 'blaze_boss_applications', 'blaze_boss_members', 'blaze_boss_records', 'blaze_boss_callsigns', 'blaze_boss_eotw', 'player_jobs_activity' }) do
        MySQL.query.await(('DELETE FROM %s WHERE citizenid LIKE ?'):format(t), { like })
    end
    if Bridge.framework == 'qbx' then MySQL.query.await('DELETE FROM player_groups WHERE citizenid LIKE ?', { like }) end
    local n = MySQL.update.await('DELETE FROM players WHERE citizenid LIKE ? AND license = ?', { like, LICENSE }) or 0
    return true, ('Removed %d test characters and all their test data.'):format(n)
end)

RegisterCommand(Config.testCommand, function(src)
    if src == 0 then return print(('[blaze_bossmenu] /%s is an in-game command.'):format(Config.testCommand)) end
    if not BM.isAdmin(src) then return Bridge.Notify(src, 'You don\'t have permission to use this.', 'error') end
    TriggerClientEvent(RES .. ':client:testMenu', src)
end, false)
