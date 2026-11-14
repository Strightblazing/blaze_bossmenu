-- Extra features on top of the boss menu: profiles, records, probation, inactivity, promotion readiness,
-- announcements, Employee of the Week, activity log, payroll, bonuses, application votes/withdraw/check-in,
-- job board, phone mail, celebrations, handshake and starter items. Every switch is in Config.features
-- (and a few in Config.applications / Config.funds / Config.jobs). All checks happen here on the server.
if not Config.enabled or not BM then return end

local RES = GetCurrentResourceName()
local F = Config.features or {}
local APPS = Config.applications or {}
local FUNDS = Config.funds or {}
local register = BM.register

local function label(gtype, name) return BM.groupLabel(gtype, name) end

--- Everyone online in a group: { [src] = grade }
local function onlineMembers(gtype, name)
    local out = {}
    for src in pairs(Bridge.GetPlayers() or {}) do
        local g = Bridge.GetPlayerGroupGrade(src, gtype, name)
        if g then out[src] = g end
    end
    return out
end

local function notifyManagers(gtype, name, msg, ntype, except)
    local n = 0
    for src in pairs(Bridge.GetPlayers() or {}) do
        if src ~= except and BM.managerGrade(src, gtype, name) then
            Bridge.Notify(src, msg, ntype or 'inform', label(gtype, name))
            n = n + 1
        end
    end
    return n
end

local function addRecord(gtype, name, cid, rtype, text, byName)
    MySQL.insert('INSERT INTO blaze_boss_records (job, citizenid, type, text, by_name) VALUES (?, ?, ?, ?, ?)',
        { BM.gkey(gtype, name), cid, rtype, text, byName })
end

local function celebrate(src, title, text)
    if F.celebrations and src then TriggerClientEvent(RES .. ':client:celebrate', src, title, text) end
end

---------------------------------------------------------------------------
-- Hooks from server/main.lua
---------------------------------------------------------------------------
--- Someone joined (hire or accepted application). handshakeWith = hiring manager's partner src (nearby hire).
BM.hooks.hired = function(src, cid, gtype, name, grade, handshakeWith, onlineSrc, signature, contract)
    -- the signed contract: exact template + filled values + signature image, so it reads the same forever
    if contract then
        MySQL.insert.await('INSERT INTO blaze_boss_contracts (job, citizenid, number, doc, signature) VALUES (?, ?, ?, ?, ?)', {
            BM.gkey(gtype, name), cid, contract.values and contract.values.number,
            json.encode({ template = contract.template, values = contract.values }), contract.image,
        })
    end
    local key = BM.gkey(gtype, name)
    local days = gtype == 'job' and tonumber(F.probationDays) or 0
    MySQL.query.await(([[INSERT INTO blaze_boss_members (citizenid, job, hired_at, probation_until, probation_done)
        VALUES (?, ?, NOW(), %s, 0) ON DUPLICATE KEY UPDATE hired_at = NOW(), probation_until = VALUES(probation_until), probation_done = 0]])
        :format(days > 0 and 'DATE_ADD(NOW(), INTERVAL ? DAY)' or 'NULL'), days > 0 and { cid, key, days } or { cid, key })
    if F.records then addRecord(gtype, name, cid, 'rank', ('Joined as %s'):format(BM.gradeName(gtype, name, grade)), Bridge.GetName(src)) end
    -- signed employment contract (Config.contract): kept on their record
    if signature then
        addRecord(gtype, name, cid, 'contract', ('Employment contract%s signed as %s, offered by %s')
            :format(contract and contract.values and contract.values.number and (' No. ' .. contract.values.number) or '',
                BM.gradeName(gtype, name, grade), Bridge.GetName(src)), Bridge.GetName(src))
    end

    local target = onlineSrc or handshakeWith
    if target then
        celebrate(target, signature and 'CONTRACT SIGNED' or ('WELCOME TO %s'):format(label(gtype, name):upper()),
            signature and ('Welcome to %s, %s'):format(label(gtype, name), BM.gradeName(gtype, name, grade)) or BM.gradeName(gtype, name, grade))
        local c = BM.groupCfg(gtype, name)
        for _, it in ipairs(c and c.starterItems or {}) do
            if type(it) == 'table' and it.item then
                if not Bridge.AddItem(target, it.item, tonumber(it.count) or 1, it.metadata) then
                    Bridge.Notify(target, ('Couldn\'t give you %s (inventory full?). Ask a manager.'):format(it.item), 'error')
                end
            end
        end
        if days > 0 then Bridge.Notify(target, ('You are on probation for %d days.'):format(days), 'inform', label(gtype, name)) end
    end
    if F.handshake and handshakeWith and src and GetPlayerPed(src) ~= 0 then
        TriggerClientEvent(RES .. ':client:handshake', src, handshakeWith, 'a')
        TriggerClientEvent(RES .. ':client:handshake', handshakeWith, src, 'b')
    end
end

BM.hooks.gradeChanged = function(src, cid, gtype, name, old, new, dir)
    local gname = BM.gradeName(gtype, name, new)
    if F.records then addRecord(gtype, name, cid, 'rank', ('%s to %s'):format(dir > 0 and 'Promoted' or 'Demoted', gname), Bridge.GetName(src)) end
    if dir > 0 then
        local p = Bridge.GetPlayerByCitizenId(cid)
        if p then celebrate(p.PlayerData.source, 'PROMOTED', gname) end
    end
end

BM.hooks.removed = function(src, cid, gtype, name)
    MySQL.update('DELETE FROM blaze_boss_members WHERE citizenid = ? AND job = ?', { cid, BM.gkey(gtype, name) })
    if F.records then addRecord(gtype, name, cid, 'rank', 'Removed', Bridge.GetName(src)) end
end

--- Phone mail when an application is updated (sd-phone)
BM.hooks.applicationUpdate = function(row)
    if F.phoneMail == false then return end
    local jl = label('job', row.job)
    local subject, body
    if row.status == 'accepted' then
        subject = ('Welcome to %s'):format(jl)
        body = ('Hi %s,\n\nGood news: your application to %s was accepted. Welcome to the team!\n\n%s Management'):format(row.name or '', jl, jl)
    elseif row.status == 'denied' then
        subject = ('Your %s application'):format(jl)
        body = ('Hi %s,\n\nThank you for applying to %s. Unfortunately your application was not successful.%s\n\n%s Management')
            :format(row.name or '', jl, row.deny_reason and ('\n\nReason: ' .. row.deny_reason) or '', jl)
    elseif row.status == 'interview' then
        subject = ('Interview invitation: %s'):format(jl)
        body = ('Hi %s,\n\nYou are invited to an interview with %s.%s\n\nWhen you arrive, check in at the review desk.\n\n%s Management')
            :format(row.name or '', jl, row.interview_msg and ('\n\n' .. row.interview_msg) or '', jl)
    else
        return
    end
    Bridge.SendMail(row.citizenid, jl .. ' Management', ('hr@%s.jobs'):format(row.job), subject, body)
end

--- Going on duty: show the department announcement they haven't seen yet
local seenAnnouncement = {} -- [cid .. job] = created_at
BM.hooks.dutyOn = function(src, cid, job)
    if not F.announcements or not job or not BM.groupCfg('job', job) then return end
    SetTimeout(1500, function()
        local a = MySQL.single.await('SELECT message, by_name, UNIX_TIMESTAMP(created_at) AS t FROM blaze_boss_announcements WHERE job = ?', { job })
        if not a or seenAnnouncement[cid .. job] == a.t then return end
        seenAnnouncement[cid .. job] = a.t
        TriggerClientEvent(RES .. ':client:announcement', src, label('job', job), a.message, a.by_name)
    end)
end

--- Staff list badges: probation, inactive, ready for promotion, Employee of the Week, hire date
BM.hooks.decorateStaff = function(gtype, name, members, activity)
    local key = BM.gkey(gtype, name)
    local extra = {}
    for _, r in ipairs(MySQL.query.await([[SELECT citizenid, DATE_FORMAT(hired_at, '%m-%d-%Y') AS hired, UNIX_TIMESTAMP(hired_at) AS hired_t,
            GREATEST(0, CEIL(TIMESTAMPDIFF(MINUTE, NOW(), probation_until) / 1440)) AS prob_days
            FROM blaze_boss_members WHERE job = ?]], { key }) or {}) do
        extra[r.citizenid] = r
    end
    local eotw = F.employeeOfWeek and MySQL.single.await('SELECT citizenid FROM blaze_boss_eotw WHERE job = ? AND week = YEARWEEK(NOW(), 3)', { key })
    local c = BM.groupCfg(gtype, name) or {}
    local inactiveDays = tonumber(F.inactiveDays) or 0
    local now = os.time()
    for _, m in ipairs(members) do
        local e = extra[m.citizenid]
        m.hiredAt = e and e.hired or nil
        if e and tonumber(e.prob_days) and tonumber(e.prob_days) > 0 then m.probationDays = tonumber(e.prob_days) end
        m.eotw = eotw and eotw.citizenid == m.citizenid or nil
        if gtype == 'job' then
            -- inactive: no duty time in N days (new hires get N days of grace)
            if inactiveDays > 0 and not m.onduty then
                local a = activity and activity[m.citizenid]
                local lastT = a and a.lastT or nil
                local recentHire = e and e.hired_t and (now - e.hired_t) < inactiveDays * 86400
                if not recentHire and (not lastT or (now - lastT) > inactiveDays * 86400) then m.inactive = true end
            end
            -- ready for promotion: enough hours for their current rank
            local need = type(c.promotionHours) == 'table' and c.promotionHours[m.grade]
            if need and (m.hours or 0) >= need then m.readyForPromotion = true end
        end
    end
end

---------------------------------------------------------------------------
-- Probation reminders (checked every 5 minutes)
---------------------------------------------------------------------------
CreateThread(function()
    while true do
        Wait(5 * 60000)
        if (tonumber(F.probationDays) or 0) > 0 then
            local rows = MySQL.query.await('SELECT citizenid, job FROM blaze_boss_members WHERE probation_until IS NOT NULL AND probation_until <= NOW() AND probation_done = 0') or {}
            for _, r in ipairs(rows) do
                if BM.groupCfg('job', r.job) then
                    local who = Bridge.GetNameByCitizenId(r.citizenid)
                    -- only mark done once a manager has actually been told
                    if notifyManagers('job', r.job, ('%s has finished their probation. Time for a review!'):format(who), 'inform') > 0 then
                        MySQL.update('UPDATE blaze_boss_members SET probation_done = 1 WHERE citizenid = ? AND job = ?', { r.citizenid, r.job })
                        local p = Bridge.GetPlayerByCitizenId(r.citizenid)
                        if p then Bridge.Notify(p.PlayerData.source, 'Your probation is over. Nice work!', 'success', label('job', r.job)) end
                    end
                end
            end
        end
    end
end)

---------------------------------------------------------------------------
-- Profiles (/myjob and the staff list)
---------------------------------------------------------------------------
local RECORD_TYPES = { commend = true, warning = true }

local function buildProfile(gtype, name, cid)
    local key = BM.gkey(gtype, name)
    local grade = Bridge.GetMemberGrade(cid, gtype, name)
    if not grade then return nil end
    local p = {
        citizenid = cid, name = Bridge.GetNameByCitizenId(cid), grade = grade, gradeName = BM.gradeName(gtype, name, grade),
        group = label(gtype, name), gtype = gtype,
    }
    local m = MySQL.single.await([[SELECT DATE_FORMAT(hired_at, '%m-%d-%Y') AS hired, DATE_FORMAT(probation_until, '%m-%d-%Y %H:%i') AS prob,
        probation_until > NOW() AS on_prob FROM blaze_boss_members WHERE citizenid = ? AND job = ?]], { cid, key })
    if m then
        p.hiredAt = m.hired
        if m.on_prob == 1 or m.on_prob == true then p.probationUntil = m.prob end
    end
    if gtype == 'job' then
        p.callsign = MySQL.scalar.await('SELECT callsign FROM blaze_boss_callsigns WHERE citizenid = ? AND job = ?', { cid, name })
        local a = BM.activityFor(name)[cid]
        p.hours, p.lastCheckin = a and a.hours or 0, a and a.lastCheckin or 'N/A'
        -- this week = since Monday 00:00
        p.hoursWeek = tonumber(MySQL.scalar.await([[SELECT ROUND(COALESCE(SUM(last_checkout - last_checkin) / 3600, 0), 2) FROM player_jobs_activity
            WHERE citizenid = ? AND job = ? AND last_checkin >= UNIX_TIMESTAMP(DATE_SUB(CURDATE(), INTERVAL WEEKDAY(CURDATE()) DAY))]], { cid, name })) or 0
    end
    if F.employeeOfWeek then
        p.eotw = MySQL.scalar.await('SELECT 1 FROM blaze_boss_eotw WHERE job = ? AND citizenid = ? AND week = YEARWEEK(NOW(), 3)', { key, cid }) and true or nil
    end
    do
        local pl = Bridge.GetPlayerByCitizenId(cid)
        p.phone, p.email = Bridge.GetContact(cid, pl and pl.PlayerData.source or nil)
    end
    p.contracts = MySQL.query.await("SELECT id, number, DATE_FORMAT(signed_at, '%m-%d-%Y') AS at FROM blaze_boss_contracts WHERE job = ? AND citizenid = ? ORDER BY id DESC LIMIT 5", { key, cid }) or {}
    if F.records then
        p.records = MySQL.query.await("SELECT type, text, by_name, DATE_FORMAT(created_at, '%m-%d-%Y') AS at FROM blaze_boss_records WHERE job = ? AND citizenid = ? ORDER BY id DESC LIMIT 25", { key, cid }) or {}
        local counts = MySQL.single.await("SELECT SUM(type = 'commend') AS c, SUM(type = 'warning') AS w FROM blaze_boss_records WHERE job = ? AND citizenid = ?", { key, cid }) or {}
        p.commendations, p.warnings = tonumber(counts.c) or 0, tonumber(counts.w) or 0
    end
    return p
end

if F.profiles then
    register('getProfile', function(src, gtype, name, cid)
        local self = Bridge.GetCitizenId(src) == cid
        if not self and not BM.actorLimit(src, gtype, name) then return nil end
        return buildProfile(gtype, name, cid)
    end)

    --- Every configured job/gang the player is in, with their profile and the current announcement
    register('getMyJob', function(src)
        local cid = Bridge.GetCitizenId(src)
        local out = {}
        for _, gtype in ipairs({ 'job', 'gang' }) do
            for name in pairs((gtype == 'job' and Config.jobs or Config.gangs) or {}) do
                if Bridge.GetPlayerGroupGrade(src, gtype, name) then
                    local p = buildProfile(gtype, name, cid)
                    if p then
                        if F.announcements then
                            local a = MySQL.single.await("SELECT message, by_name, DATE_FORMAT(created_at, '%m-%d-%Y %H:%i') AS at FROM blaze_boss_announcements WHERE job = ?", { BM.gkey(gtype, name) })
                            p.announcement = a
                        end
                        p.groupName = name
                        out[#out + 1] = p
                    end
                end
            end
        end
        return out
    end)
end

---------------------------------------------------------------------------
-- Commendations & write-ups
---------------------------------------------------------------------------
if F.records then
    register('addRecord', function(src, gtype, name, cid, rtype, text)
        if not RECORD_TYPES[rtype] then return false, 'Invalid record type.' end
        local limit, err
        if rtype == 'warning' then
            limit, err = BM.checkTarget(src, gtype, name, cid, false) -- only people below you
        else
            limit = BM.actorLimit(src, gtype, name)
            err = 'You are not a manager here.'
            if limit and Bridge.GetCitizenId(src) == cid then limit, err = nil, 'You can\'t commend yourself.' end
            if limit and not Bridge.GetMemberGrade(cid, gtype, name) then limit, err = nil, 'That person is not a member.' end
        end
        if not limit then return false, err end
        text = BM.cleanText(text, 300)
        if not text or #text < 3 then return false, 'Write at least a few words.' end
        addRecord(gtype, name, cid, rtype, text, Bridge.GetName(src))
        local who = Bridge.GetNameByCitizenId(cid)
        BM.notifyMember(cid, rtype == 'commend' and ('You received a commendation: %s'):format(text) or ('You received a write-up: %s'):format(text),
            rtype == 'commend' and 'success' or 'error')
        Logs.log('record', src, ('%s gave %s a %s: %s'):format(Logs.who(src), who, rtype == 'commend' and 'commendation' or 'write-up', text),
            { Group = BM.gkey(gtype, name), Target = cid, Type = rtype })
        return true, rtype == 'commend' and 'Commendation saved.' or 'Write-up saved.'
    end)
end

---------------------------------------------------------------------------
-- Employee of the Week
---------------------------------------------------------------------------
if F.employeeOfWeek then
    register('setEmployeeOfWeek', function(src, gtype, name, cid, reason)
        if not BM.actorLimit(src, gtype, name) then return false, 'You are not a manager here.' end
        if Bridge.GetCitizenId(src) == cid then return false, 'You can\'t pick yourself.' end
        if not Bridge.GetMemberGrade(cid, gtype, name) then return false, 'That person is not a member.' end
        reason = BM.cleanText(reason, 200) or ''
        local who = Bridge.GetNameByCitizenId(cid)
        local key = BM.gkey(gtype, name)
        MySQL.query.await([[INSERT INTO blaze_boss_eotw (job, citizenid, name, reason, week, by_name) VALUES (?, ?, ?, ?, YEARWEEK(NOW(), 3), ?)
            ON DUPLICATE KEY UPDATE citizenid = VALUES(citizenid), name = VALUES(name), reason = VALUES(reason), week = VALUES(week), by_name = VALUES(by_name)]],
            { key, cid, who, reason, Bridge.GetName(src) })
        if F.records then addRecord(gtype, name, cid, 'eotw', reason ~= '' and reason or 'Employee of the Week', Bridge.GetName(src)) end
        local gl = label(gtype, name)
        for target in pairs(onlineMembers(gtype, name)) do
            Bridge.Notify(target, ('%s is %s\'s Employee of the Week.%s'):format(who, gl, reason ~= '' and (' ' .. reason) or ''), 'success', gl)
        end
        local p = Bridge.GetPlayerByCitizenId(cid)
        if p then celebrate(p.PlayerData.source, 'EMPLOYEE OF THE WEEK', gl) end
        Logs.log('eotw', src, ('%s named %s Employee of the Week (%s)'):format(Logs.who(src), who, gl), { Group = key, Target = cid })
        return true, ('%s is Employee of the Week.'):format(who)
    end)
end

---------------------------------------------------------------------------
-- Department announcements
---------------------------------------------------------------------------
if F.announcements then
    register('getAnnouncement', function(src, gtype, name)
        if not Bridge.GetPlayerGroupGrade(src, gtype, name) and not BM.actorLimit(src, gtype, name) then return nil end
        return MySQL.single.await("SELECT message, by_name, DATE_FORMAT(created_at, '%m-%d-%Y %H:%i') AS at FROM blaze_boss_announcements WHERE job = ?", { BM.gkey(gtype, name) })
    end)

    register('postAnnouncement', function(src, gtype, name, message)
        if not BM.actorLimit(src, gtype, name) then return false, 'You are not a manager here.' end
        local key = BM.gkey(gtype, name)
        message = BM.cleanLong(message or '', 500) or ''
        if message == '' then
            MySQL.query.await('DELETE FROM blaze_boss_announcements WHERE job = ?', { key })
            return true, 'Announcement cleared.'
        end
        MySQL.query.await('INSERT INTO blaze_boss_announcements (job, message, by_name, created_at) VALUES (?, ?, ?, NOW()) ON DUPLICATE KEY UPDATE message = VALUES(message), by_name = VALUES(by_name), created_at = NOW()',
            { key, message, Bridge.GetName(src) })
        local t = MySQL.scalar.await('SELECT UNIX_TIMESTAMP(created_at) FROM blaze_boss_announcements WHERE job = ?', { key })
        local gl, by = label(gtype, name), Bridge.GetName(src)
        for target in pairs(onlineMembers(gtype, name)) do
            local onduty = gtype ~= 'job' or (Bridge.GetJob(target) or {}).onduty
            if onduty then
                TriggerClientEvent(RES .. ':client:announcement', target, gl, message, by)
                local cid = Bridge.GetCitizenId(target)
                if cid then seenAnnouncement[cid .. name] = t end
            end
        end
        Logs.log('announce', src, ('%s posted a %s announcement: %s'):format(Logs.who(src), gl, message), { Group = key })
        return true, 'Announcement posted. Off-duty staff see it when they clock in.'
    end)
end

---------------------------------------------------------------------------
-- Activity log (in-game audit)
---------------------------------------------------------------------------
if F.auditLog then
    register('getAudit', function(src, gtype, name)
        if not BM.actorLimit(src, gtype, name) then return nil end
        return MySQL.query.await(("SELECT actor, event, message, DATE_FORMAT(created_at, '%%m-%%d-%%Y %%H:%%i') AS at FROM blaze_boss_audit WHERE job = ? ORDER BY id DESC LIMIT %d")
            :format(math.max(1, math.floor(tonumber(F.auditShow) or 50))), { BM.gkey(gtype, name) }) or {}
    end)
    CreateThread(function()
        Wait(15000)
        MySQL.query('DELETE FROM blaze_boss_audit WHERE created_at < (NOW() - INTERVAL ? DAY)', { tonumber(F.auditKeepDays) or 30 })
    end)
end

---------------------------------------------------------------------------
-- Payroll overview + bonuses
---------------------------------------------------------------------------
if FUNDS.payroll then
    register('getPayroll', function(src, gtype, name)
        if gtype ~= 'job' or not BM.actorLimit(src, gtype, name) then return nil end
        local byGrade = {}
        for _, m in ipairs(Bridge.GetMembers(gtype, name)) do
            local b = byGrade[m.grade] or { total = 0, onduty = 0 }
            b.total = b.total + 1
            if m.onduty then b.onduty = b.onduty + 1 end
            byGrade[m.grade] = b
        end
        local rows, all, now = {}, 0, 0
        for _, g in ipairs(Bridge.GetGrades(gtype, name)) do
            local b = byGrade[g.level] or { total = 0, onduty = 0 }
            local pay = tonumber(g.payment) or 0
            rows[#rows + 1] = { level = g.level, name = g.name, pay = pay, members = b.total, onduty = b.onduty }
            all, now = all + pay * b.total, now + pay * b.onduty
        end
        return { grades = rows, perPaycheckAll = all, perPaycheckOnDuty = now }
    end)
end

if FUNDS.enabled and FUNDS.bonuses then
    --- mode 'one' (cid) or 'onduty' (everyone on duty except you). Paid into their bank from the society.
    register('bonus', function(src, gtype, name, mode, cid, amount, reason)
        if not BM.fundsOn(gtype, name) then return false, 'Funds are turned off for this group.' end
        if not BM.actorLimit(src, gtype, name) then return false, 'You are not a manager here.' end
        amount = tonumber(amount)
        if not amount or amount ~= math.floor(amount) or amount < 1 then return false, 'Enter a whole amount of at least $1.' end
        local max = tonumber(FUNDS.maxBonus) or 5000
        if amount > max then return false, ('A bonus can be at most $%d per person.'):format(max) end
        reason = BM.cleanText(reason, 100)
        if not reason or #reason < 1 then return false, 'A reason is required.' end
        local me = Bridge.GetCitizenId(src)
        local recipients = {}
        if mode == 'one' then
            if cid == me then return false, 'You can\'t give yourself a bonus.' end
            local p = Bridge.GetPlayerByCitizenId(cid)
            if not p or not Bridge.GetPlayerGroupGrade(p.PlayerData.source, gtype, name) then return false, 'They must be online and in this group.' end
            recipients[1] = p.PlayerData.source
        else
            for target in pairs(onlineMembers(gtype, name)) do
                local onduty = gtype ~= 'job' or (Bridge.GetJob(target) or {}).onduty
                if target ~= src and onduty then recipients[#recipients + 1] = target end
            end
            if #recipients == 0 then return false, 'Nobody else is on duty.' end
        end
        local total = amount * #recipients
        local left = BM.withdrawLeft(src, gtype, name)
        if left and total > left then return false, ('Your rank can pay out $%d more today.'):format(math.max(0, left)) end
        local account = BM.groupCfg(gtype, name).society
        if not Banking.withdraw(account, total, 'Bonus: ' .. reason) then return false, ('The account doesn\'t have $%d.'):format(total) end
        local gl, names = label(gtype, name), {}
        for _, target in ipairs(recipients) do
            if Bridge.AddBank(target, amount, 'Bonus: ' .. reason) then
                names[#names + 1] = Bridge.GetName(target)
                Bridge.Notify(target, ('You received a $%d bonus: %s'):format(amount, reason), 'success', gl)
                celebrate(target, 'BONUS', ('$%d · %s'):format(amount, reason))
            else
                Banking.deposit(account, amount, 'Bonus refund')
            end
        end
        local paid = amount * #names
        MySQL.insert('INSERT INTO blaze_boss_fund_log (job, citizenid, name, type, amount, reason) VALUES (?, ?, ?, ?, ?, ?)',
            { BM.gkey(gtype, name), me, Bridge.GetName(src), 'bonus', paid, ('%s (%s)'):format(reason, table.concat(names, ', ')):sub(1, 128) })
        Logs.log('bonus', src, ('%s paid a $%d bonus to %s (%s)'):format(Logs.who(src), amount, table.concat(names, ', '), reason),
            { Group = BM.gkey(gtype, name), Amount = '$' .. paid, People = #names })
        return true, ('Paid $%d to %d %s.'):format(paid, #names, #names == 1 and 'person' or 'people')
    end)
end

---------------------------------------------------------------------------
-- Applications: withdraw, votes, interview check-in, job board
---------------------------------------------------------------------------
if APPS.enabled then
    if APPS.allowWithdraw then
        register('withdrawApplication', function(src, id)
            local cid = Bridge.GetCitizenId(src)
            local row = MySQL.single.await('SELECT id, job, name, status FROM blaze_boss_applications WHERE id = ? AND citizenid = ?', { tonumber(id), cid })
            if not row then return false, 'Application not found.' end
            if row.status ~= 'new' and row.status ~= 'interview' then return false, 'This application was already decided.' end
            MySQL.update.await("UPDATE blaze_boss_applications SET status = 'withdrawn', notified = 1 WHERE id = ?", { row.id })
            Logs.log('withdrawApp', src, ('%s withdrew their %s application'):format(Logs.who(src), label('job', row.job)), { Job = row.job, Application = row.id })
            return true, 'Application withdrawn.'
        end)
    end

    if APPS.votes then
        register('voteApplication', function(src, job, id, vote)
            if not BM.appsOn('job', job) or not BM.actorLimit(src, 'job', job) then return false, 'You are not a manager here.' end
            id, vote = tonumber(id), tonumber(vote)
            if not MySQL.scalar.await('SELECT id FROM blaze_boss_applications WHERE id = ? AND job = ?', { id, job }) then return false, 'Application not found.' end
            local cid = Bridge.GetCitizenId(src)
            if vote == 1 or vote == -1 then
                MySQL.query.await('INSERT INTO blaze_boss_app_votes (app_id, citizenid, name, vote) VALUES (?, ?, ?, ?) ON DUPLICATE KEY UPDATE vote = VALUES(vote), name = VALUES(name)',
                    { id, cid, Bridge.GetName(src), vote })
                return true, vote == 1 and 'You voted for.' or 'You voted against.'
            end
            MySQL.query.await('DELETE FROM blaze_boss_app_votes WHERE app_id = ? AND citizenid = ?', { id, cid })
            return true, 'Vote removed.'
        end)
    end

    if APPS.interviewCheckIn then
        local lastCheckIn = {}
        register('interviewCheckIn', function(src, job)
            if not BM.appsOn('job', job) then return false, 'Applications are off for this job.' end
            if lastCheckIn[src] and os.time() - lastCheckIn[src] < 60 then return false, 'You already checked in. Please wait for a manager.' end
            local cid = Bridge.GetCitizenId(src)
            local row = MySQL.single.await("SELECT id FROM blaze_boss_applications WHERE citizenid = ? AND job = ? AND status = 'interview' ORDER BY id DESC LIMIT 1", { cid, job })
            if not row then return false, 'You don\'t have an interview with ' .. label('job', job) .. '.' end
            lastCheckIn[src] = os.time()
            local name = Bridge.GetName(src)
            local told = notifyManagers('job', job, ('%s is here for their interview (application #%d).'):format(name, row.id), 'inform')
            Logs.log('checkin', src, ('%s checked in for their %s interview'):format(Logs.who(src), label('job', job)), { Job = job, Application = row.id })
            if told == 0 then return true, 'You\'re checked in. No managers are around right now; they\'ll see it in the activity log.' end
            return true, 'You\'re checked in. A manager has been told you\'re here.'
        end)
        AddEventHandler('playerDropped', function() lastCheckIn[source] = nil end)
    end

    if F.jobBoardCommand then
        register('getJobBoard', function()
            local out, points = {}, BM.allPoints()
            for name, c in pairs(Config.jobs or {}) do
                if BM.appsOn('job', name) then
                    local spots = {}
                    for _, p in ipairs(points) do
                        if p.type == 'applications' and p.gtype == 'job' and p.group == name then spots[#spots + 1] = p.coords end
                    end
                    out[#out + 1] = { job = name, label = c.label or name, description = c.description, open = BM.isOpen(name), points = spots }
                end
            end
            table.sort(out, function(a, b)
                if a.open ~= b.open then return a.open end
                return a.label < b.label
            end)
            return out
        end)
    end
end

---------------------------------------------------------------------------
-- Employment contract templates (Config.contract): per job, edited in the boss menu
---------------------------------------------------------------------------
local C = Config.contract or {}
local templates = {} -- [group key] = saved template

local function defaultTemplate() return C.template or { title = 'Employment Agreement', intro = '', sections = {} } end

--- The template a group's contracts use: its saved one, or the default from config.lua
function BM.contractTemplate(gtype, name)
    return templates[BM.gkey(gtype, name)] or defaultTemplate()
end

local function canEditContract(src, gtype, name)
    if not C.enabled or not BM.groupCfg(gtype, name) then return false end
    if C.editor == 'management' then return BM.actorLimit(src, gtype, name) ~= nil end
    if C.editor == 'admin' then return BM.isAdmin(src) end
    return false
end

--- Strict server-side cleaning of a template sent by the client
local function sanitizeTemplate(t)
    if type(t) ~= 'table' or type(t.sections) ~= 'table' then return nil, 'Invalid contract.' end
    local title = BM.cleanText(t.title, 200)
    if not title or #title < 1 or #title > 60 then return nil, 'Title must be 1-60 characters.' end
    local intro = BM.cleanLong(t.intro or '', 2000) or ''
    if #intro > 600 then return nil, 'Intro can be at most 600 characters.' end
    if #t.sections < 1 or #t.sections > 12 then return nil, 'A contract needs 1 to 12 sections.' end
    local out = { title = title, intro = intro, sections = {} }
    for i, s in ipairs(t.sections) do
        if type(s) ~= 'table' then return nil, ('Section %d is invalid.'):format(i) end
        local st = BM.cleanText(s.title, 200)
        if not st or #st < 1 or #st > 60 then return nil, ('Section %d: title must be 1-60 characters.'):format(i) end
        local body = BM.cleanLong(s.text, 4000)
        if not body or #body < 1 or #body > 1500 then return nil, ('Section %d: text must be 1-1500 characters.'):format(i) end
        out.sections[i] = { title = st, text = body }
    end
    return out
end

if C.enabled then
    CreateThread(function()
        Wait(2000) -- tables are created by server/main.lua on start
        for _, r in ipairs(MySQL.query.await('SELECT job, template FROM blaze_boss_contract_templates') or {}) do
            local t = json.decode(r.template)
            if type(t) == 'table' then templates[r.job] = t end
        end
    end)

    register('getContractTemplate', function(src, gtype, name)
        if not canEditContract(src, gtype, name) then return nil end
        local key = BM.gkey(gtype, name)
        -- example values for the preview: this group, its lowest rank, and you as the one hiring
        local low = Bridge.GetGrades(gtype, name)[1] or {}
        local mine = Bridge.GetPlayerGroupGrade(src, gtype, name)
        local days = gtype == 'job' and tonumber(F.probationDays) or 0
        local pay = gtype == 'job' and tonumber(low.payment) or nil
        local sample = {
            job = label(gtype, name), rank = low.name or 'Recruit', pay = (pay and pay > 0) and ('$' .. math.floor(pay)) or nil,
            probation = days > 0 and ('%d day%s'):format(days, days == 1 and '' or 's') or nil,
            employee = 'Jane Doe', manager = Bridge.GetName(src), manager_rank = mine and BM.gradeName(gtype, name, mine) or 'Management',
            date = os.date('%m-%d-%Y'), number = 'EA-PREVIEW',
        }
        return { template = BM.contractTemplate(gtype, name), custom = templates[key] ~= nil, sample = sample }
    end)

    register('saveContractTemplate', function(src, gtype, name, t)
        if not canEditContract(src, gtype, name) then return false, 'You can\'t edit this contract.' end
        local clean, err = sanitizeTemplate(t)
        if not clean then return false, err end
        local key = BM.gkey(gtype, name)
        MySQL.query.await('INSERT INTO blaze_boss_contract_templates (job, template, updated_by) VALUES (?, ?, ?) ON DUPLICATE KEY UPDATE template = VALUES(template), updated_by = VALUES(updated_by)',
            { key, json.encode(clean), Bridge.GetName(src) })
        templates[key] = clean
        Logs.log('contractEdit', src, ('%s saved the %s employment contract (%d sections)'):format(Logs.who(src), label(gtype, name), #clean.sections), { Group = key })
        return true, 'Contract saved. New hires will sign this version.'
    end)

    register('resetContractTemplate', function(src, gtype, name)
        if not canEditContract(src, gtype, name) then return false, 'You can\'t edit this contract.' end
        local key = BM.gkey(gtype, name)
        MySQL.query.await('DELETE FROM blaze_boss_contract_templates WHERE job = ?', { key })
        templates[key] = nil
        Logs.log('contractEdit', src, ('%s reset the %s employment contract to default'):format(Logs.who(src), label(gtype, name)), { Group = key })
        return true, 'Contract reset to the default.'
    end)

    --- A signed contract: the employee themself, or a manager of that group
    register('getContract', function(src, id)
        local row = MySQL.single.await("SELECT job, citizenid, doc, signature, DATE_FORMAT(signed_at, '%m-%d-%Y') AS at FROM blaze_boss_contracts WHERE id = ?", { tonumber(id) })
        if not row then return nil end
        local gtype, name = 'job', row.job
        if row.job:sub(1, 5) == 'gang:' then gtype, name = 'gang', row.job:sub(6) end
        if Bridge.GetCitizenId(src) ~= row.citizenid and not BM.actorLimit(src, gtype, name) then return nil end
        local doc = json.decode(row.doc) or {}
        return { template = doc.template, values = doc.values, signature = row.signature, signedAt = row.at }
    end)
end

---------------------------------------------------------------------------
-- Duty points: clock in / out at a placed duty point (Config.duty)
---------------------------------------------------------------------------
local DUTY = Config.duty or {}
if DUTY.enabled then
    register('toggleDuty', function(src, job)
        if not BM.groupCfg('job', job) then return false, 'That job isn\'t configured.' end
        if not Bridge.GetPlayerGroupGrade(src, 'job', job) then return false, 'You don\'t work here.' end
        local current = Bridge.GetJob(src) or {}
        local goingOn = not (current.name == job and current.onduty)
        local state, why = Bridge.SetDuty(src, job, goingOn)
        if state == nil then return false, why end
        return true, state and ('You\'re now on duty with %s.'):format(label('job', job)) or ('You\'re now off duty from %s.'):format(label('job', job)), state
    end)
end

---------------------------------------------------------------------------
-- Outfits (Config.outfits): managers save outfits for their job; staff of that rank or higher wear them
-- at a wardrobe point. Clothes are read/applied on the client (illenium-appearance if running).
---------------------------------------------------------------------------
local OUT = Config.outfits or {}
if OUT.enabled then
    local MODELS = { male = true, female = true }

    --- keep only numbers in the expected shape: { components = { {component_id, drawable, texture} }, props = { {prop_id, drawable, texture} } }
    local function cleanClothes(d)
        if type(d) ~= 'table' then return nil end
        local out = { components = {}, props = {} }
        for _, c in ipairs(type(d.components) == 'table' and d.components or {}) do
            local id, dr, tx = tonumber(c.component_id), tonumber(c.drawable), tonumber(c.texture)
            if id and dr and tx and id >= 0 and id <= 11 and #out.components < 12 then
                out.components[#out.components + 1] = { component_id = math.floor(id), drawable = math.floor(dr), texture = math.floor(tx) }
            end
        end
        for _, p in ipairs(type(d.props) == 'table' and d.props or {}) do
            local id, dr, tx = tonumber(p.prop_id), tonumber(p.drawable), tonumber(p.texture)
            if id and dr and tx and id >= 0 and id <= 13 and #out.props < 10 then
                out.props[#out.props + 1] = { prop_id = math.floor(id), drawable = math.floor(dr), texture = math.floor(tx) }
            end
        end
        if #out.components == 0 then return nil end
        return out
    end

    --- Outfits this player can see: staff see the ones for their rank and body; managers see all
    register('getOutfits', function(src, gtype, name, model)
        local grade = Bridge.GetPlayerGroupGrade(src, gtype, name)
        local manager = BM.actorLimit(src, gtype, name) ~= nil
        if not grade and not manager then return nil end
        local rows = MySQL.query.await('SELECT id, name, min_grade, model FROM blaze_boss_outfits WHERE job = ? ORDER BY min_grade, name', { BM.gkey(gtype, name) }) or {}
        local out = {}
        for _, r in ipairs(rows) do
            local allowed = (grade or -1) >= r.min_grade
            if manager or (allowed and r.model == model) then
                out[#out + 1] = { id = r.id, name = r.name, minGrade = r.min_grade, rankName = BM.gradeName(gtype, name, r.min_grade), model = r.model, allowed = allowed or manager }
            end
        end
        return { outfits = out, manager = manager, grades = Bridge.GetGrades(gtype, name) }
    end)

    register('wearOutfit', function(src, gtype, name, id)
        local row = MySQL.single.await('SELECT job, min_grade, model, data, name FROM blaze_boss_outfits WHERE id = ? AND job = ?', { tonumber(id), BM.gkey(gtype, name) })
        if not row then return nil, 'Outfit not found.' end
        local grade = Bridge.GetPlayerGroupGrade(src, gtype, name)
        if not BM.actorLimit(src, gtype, name) and (not grade or grade < row.min_grade) then return nil, 'Your rank can\'t wear that outfit.' end
        return { data = json.decode(row.data), model = row.model, name = row.name }
    end)

    register('saveOutfit', function(src, gtype, name, o)
        if not BM.actorLimit(src, gtype, name) then return false, 'You are not a manager here.' end
        if type(o) ~= 'table' then return false, 'Invalid outfit.' end
        local oname = BM.cleanText(o.name, 100)
        if not oname or #oname < 1 or #oname > 40 then return false, 'Outfit name must be 1-40 characters.' end
        local minGrade = tonumber(o.minGrade) or 0
        if not Bridge.GetGrade(gtype, name, minGrade) then return false, 'That rank doesn\'t exist.' end
        if not MODELS[o.model] then return false, 'Outfits work on the male/female freemode characters only.' end
        local clothes = cleanClothes(o.data)
        if not clothes then return false, 'Couldn\'t read your clothes.' end
        local count = MySQL.scalar.await('SELECT COUNT(*) FROM blaze_boss_outfits WHERE job = ?', { BM.gkey(gtype, name) }) or 0
        if count >= (OUT.maxPerJob or 30) then return false, ('This job already has %d outfits (the most allowed).'):format(count) end
        MySQL.insert.await('INSERT INTO blaze_boss_outfits (job, name, min_grade, model, data, created_by) VALUES (?, ?, ?, ?, ?, ?)',
            { BM.gkey(gtype, name), oname, minGrade, o.model, json.encode(clothes), Bridge.GetName(src) })
        Logs.log('outfit', src, ('%s saved the %s outfit "%s" (rank %d+, %s)'):format(Logs.who(src), label(gtype, name), oname, minGrade, o.model), { Group = BM.gkey(gtype, name) })
        return true, ('Outfit "%s" saved.'):format(oname)
    end)

    register('updateOutfit', function(src, gtype, name, id, newName, minGrade)
        if not BM.actorLimit(src, gtype, name) then return false, 'You are not a manager here.' end
        newName = BM.cleanText(newName, 100)
        if not newName or #newName < 1 or #newName > 40 then return false, 'Outfit name must be 1-40 characters.' end
        minGrade = tonumber(minGrade)
        if not minGrade or not Bridge.GetGrade(gtype, name, minGrade) then return false, 'That rank doesn\'t exist.' end
        local n = MySQL.update.await('UPDATE blaze_boss_outfits SET name = ?, min_grade = ? WHERE id = ? AND job = ?', { newName, minGrade, tonumber(id), BM.gkey(gtype, name) })
        return (n or 0) > 0, (n or 0) > 0 and 'Outfit updated.' or 'Outfit not found.'
    end)

    register('deleteOutfit', function(src, gtype, name, id)
        if not BM.actorLimit(src, gtype, name) then return false, 'You are not a manager here.' end
        local n = MySQL.update.await('DELETE FROM blaze_boss_outfits WHERE id = ? AND job = ?', { tonumber(id), BM.gkey(gtype, name) })
        if (n or 0) > 0 then Logs.log('outfit', src, ('%s deleted outfit #%s from %s'):format(Logs.who(src), id, label(gtype, name)), { Group = BM.gkey(gtype, name) }) end
        return (n or 0) > 0, (n or 0) > 0 and 'Outfit deleted.' or 'Outfit not found.'
    end)
end

---------------------------------------------------------------------------
-- Time clock (Config.duty.style = 'clock'): everything the clock screen shows, from the boss menu's own data
---------------------------------------------------------------------------
if DUTY.enabled then
    --- 4-digit PIN that belongs to a character (shown on their virtual ID)
    local function pinOf(cid)
        local h = 7
        for i = 1, #cid do h = (h * 31 + cid:byte(i)) % 10000 end
        return ('%04d'):format(h)
    end

    local function fmtDuration(sec)
        sec = math.max(0, math.floor(sec or 0))
        return ('%dh %dm'):format(sec // 3600, (sec // 60) % 60)
    end

    --- Is the player standing at one of this job's duty points?
    local function atDutyPoint(src, job)
        local pos = GetEntityCoords(GetPlayerPed(src))
        for _, p in ipairs(BM.allPoints()) do
            if p.type == 'duty' and p.gtype == 'job' and p.group == job then
                if #(pos - vec3(p.coords.x, p.coords.y, p.coords.z)) <= (p.radius or 1.0) + 3.0 then return true end
            end
        end
        return false
    end

    local function clockData(src, job)
        local cid = Bridge.GetCitizenId(src)
        local grade = Bridge.GetPlayerGroupGrade(src, 'job', job)
        if not cid or not grade then return nil end
        local c = BM.groupCfg('job', job) or {}
        local current = Bridge.GetJob(src) or {}
        local onDuty = current.name == job and current.onduty == true
        local session = BM.clockedIn[src]
        local live = (session and session.job == job) and (os.time() - session.time) or 0

        -- hours: this week by day (Mon = 1), last 31 days, last finished shift
        local week, weekTotal = { 0, 0, 0, 0, 0, 0, 0 }, 0
        for _, r in ipairs(MySQL.query.await([[SELECT WEEKDAY(FROM_UNIXTIME(last_checkin)) AS d, SUM(last_checkout - last_checkin) / 3600 AS h
            FROM player_jobs_activity WHERE citizenid = ? AND job = ? AND last_checkin >= UNIX_TIMESTAMP(DATE_SUB(CURDATE(), INTERVAL WEEKDAY(CURDATE()) DAY))
            GROUP BY d]], { cid, job }) or {}) do
            local d = tonumber(r.d)
            if d then week[d + 1] = tonumber(r.h) or 0 weekTotal = weekTotal + week[d + 1] end
        end
        local today = tonumber(MySQL.scalar.await('SELECT WEEKDAY(CURDATE())')) or 0
        week[today + 1] = week[today + 1] + live / 3600
        weekTotal = weekTotal + live / 3600
        local a = BM.activityFor(job)[cid]
        local month = (a and a.hours or 0) + live / 3600
        local last = MySQL.single.await([[SELECT last_checkout - last_checkin AS len, DATE_FORMAT(FROM_UNIXTIME(last_checkout), '%m-%d-%Y') AS at
            FROM player_jobs_activity WHERE citizenid = ? AND job = ? ORDER BY last_checkout DESC LIMIT 1]], { cid, job })

        -- next rank and what it takes (jobs[x].promotionHours over the last activity.keepDays days)
        local grades = Bridge.GetGrades('job', job)
        local mine, nextG = nil, nil
        for i, g in ipairs(grades) do if g.level == grade then mine = g nextG = grades[i + 1] end end
        local need = type(c.promotionHours) == 'table' and c.promotionHours[grade] or nil

        -- tags
        local tags = {}
        local key = BM.gkey('job', job)
        if F.employeeOfWeek and MySQL.scalar.await('SELECT 1 FROM blaze_boss_eotw WHERE job = ? AND citizenid = ? AND week = YEARWEEK(NOW(), 3)', { key, cid }) then
            tags[#tags + 1] = 'Employee of the week'
        end
        local prob = MySQL.scalar.await('SELECT CEIL(TIMESTAMPDIFF(MINUTE, NOW(), probation_until) / 1440) FROM blaze_boss_members WHERE citizenid = ? AND job = ? AND probation_until > NOW()', { cid, key })
        if prob then tags[#tags + 1] = ('Probation · %d day%s left'):format(prob, prob == 1 and '' or 's') end
        if need and month >= need and nextG then tags[#tags + 1] = 'Ready for promotion' end

        -- who's on duty (not you: the screen adds you while you're clocked in)
        local list = {}
        for other in pairs(Bridge.GetPlayers() or {}) do
            local j = Bridge.GetJob(other) or {}
            if other ~= src and j.name == job and j.onduty then
                list[#list + 1] = { Bridge.GetName(other), BM.gradeName('job', job, j.grade) }
            end
        end
        table.sort(list, function(x, y) return x[1] < y[1] end)

        local ann = F.announcements and MySQL.single.await("SELECT message, by_name, DATE_FORMAT(created_at, '%m-%d-%Y') AS at FROM blaze_boss_announcements WHERE job = ?", { key }) or nil

        -- job + rank details
        local shared = Bridge.GetGroup('job', job) or {}
        local rankPos = 0
        for i, g in ipairs(grades) do if g.level == grade then rankPos = i end end
        local TYPES = { ems = 'Medical', leo = 'Law enforcement', fire = 'Fire', mechanic = 'Mechanic' }
        -- employment
        local mem = MySQL.single.await("SELECT DATEDIFF(NOW(), hired_at) AS days, DATE_FORMAT(hired_at, '%m-%d-%Y') AS since FROM blaze_boss_members WHERE citizenid = ? AND job = ?", { cid, key })
        local record
        if F.records then
            local r = MySQL.single.await("SELECT SUM(type = 'commend') AS c, SUM(type = 'warning') AS w FROM blaze_boss_records WHERE job = ? AND citizenid = ?", { key, cid }) or {}
            record = { commendations = tonumber(r.c) or 0, writeups = tonumber(r.w) or 0 }
        end
        -- department stats (applications waiting: managers only)
        local manager = BM.actorLimit(src, 'job', job) ~= nil
        local appsWaiting = (manager and BM.appsOn('job', job))
            and MySQL.scalar.await("SELECT COUNT(*) FROM blaze_boss_applications WHERE job = ? AND status IN ('new','interview')", { job }) or nil
        local eotwName = F.employeeOfWeek and MySQL.scalar.await('SELECT name FROM blaze_boss_eotw WHERE job = ? AND week = YEARWEEK(NOW(), 3)', { key }) or nil

        local phone, email = Bridge.GetContact(cid, src)

        return {
            phone = phone, email = email,
            fullName = c.fullName, jobType = TYPES[shared.type] or (shared.type and shared.type:gsub('^%l', string.upper)) or nil,
            rankPos = rankPos, rankCount = #grades,
            employedDays = mem and tonumber(mem.days) or nil, employedSince = mem and mem.since or nil,
            pay = mine and tonumber(mine.payment) or nil, record = record,
            staffTotal = #Bridge.GetMembers('job', job), appsWaiting = appsWaiting and tonumber(appsWaiting) or nil, eotw = eotwName,
            dept = label('job', job), name = Bridge.GetName(src), rank = mine and mine.name or tostring(grade),
            callsign = MySQL.scalar.await('SELECT callsign FROM blaze_boss_callsigns WHERE citizenid = ? AND job = ?', { cid, job }),
            id = cid:sub(-5):upper(), pin = pinOf(cid), virtual = true,
            onDuty = onDuty, shiftSeconds = onDuty and live or 0,
            weekHours = weekTotal, monthHours = month, week = week, today = today, keepDays = (Config.activity or {}).keepDays or 31,
            lastShift = last and last.len and (last.at .. ' · ' .. fmtDuration(last.len)) or nil,
            next = nextG and { rank = nextG.name, need = need, payNow = mine and mine.payment or 0, payNext = nextG.payment or 0 } or nil,
            tags = tags, onDutyList = list,
            announcement = ann and { message = ann.message, by = ann.by_name, at = ann.at } or nil,
        }
    end

    register('getClockData', function(src, job)
        if not BM.groupCfg('job', job) then return nil, 'That job isn\'t configured.' end
        if not Bridge.GetPlayerGroupGrade(src, 'job', job) then return nil, 'This time clock is for ' .. label('job', job) .. ' staff.' end
        return clockData(src, job), nil, DUTY.methods or { 'tap', 'swipe', 'keypad' }
    end)

    --- Clock in / out from the time clock screen
    --- Shared checks for a scan / button press at the clock. Returns nil or an error result.
    local function checkScan(src, job, method, pin)
        if not Bridge.GetPlayerGroupGrade(src, 'job', job) then return { ok = false, msg = 'This time clock is for ' .. label('job', job) .. ' staff.' } end
        if not atDutyPoint(src, job) then return { ok = false, msg = 'Stand at the time clock.' } end
        if method == 'keypad' and tostring(pin or '') ~= pinOf(Bridge.GetCitizenId(src)) then return { ok = false, msg = 'Wrong PIN. It\'s on your ID.' } end
    end

    local function isOnDuty(src, job)
        local current = Bridge.GetJob(src) or {}
        return current.name == job and current.onduty == true
    end

    --- Already on duty: a scan just opens the full screen (checks the scan, doesn't change duty)
    register('clockAccess', function(src, job, method, pin)
        local bad = checkScan(src, job, method, pin)
        if bad then return bad end
        return { ok = true, onDuty = isOnDuty(src, job), data = clockData(src, job) }
    end)

    --- Clock in / out. method 'button' = the Clock out button on the open clock (only clocks out).
    register('clockPunch', function(src, job, method, pin)
        local bad = checkScan(src, job, method, pin)
        if bad then return bad end
        local session = BM.clockedIn[src]
        local shift = (session and session.job == job) and (os.time() - session.time) or nil
        local goingOn = not isOnDuty(src, job)
        if method == 'button' and goingOn then return { ok = false, msg = 'Scan your ID to clock in.' } end
        local state, why = Bridge.SetDuty(src, job, goingOn)
        if state == nil then return { ok = false, msg = why } end
        return { ok = true, onDuty = state, shift = (not state and shift) and fmtDuration(shift) or nil, data = clockData(src, job) }
    end)
end
