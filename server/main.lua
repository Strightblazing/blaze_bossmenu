-- blaze_bossmenu server.
-- Fork of qbx_management (Qbox Project, GPL-3.0): staff list, hire with consent, promote/demote, fire,
-- duty hours, grade editor, gang menus and the qbx_management/qb-bossmenu compatibility hooks.
-- Added: Qbox + QBCore bridge, applications + form builder, funds, callsigns, placed points, logging.
-- Every action re-checks permission on the server; the client is never trusted about job or grade.

if not Config.enabled then
    print('^3[blaze_bossmenu]^7 Disabled in config.lua (Config.enabled = false). Nothing is loaded.')
    exports('isManager', function() return false end)
    return
end

local RES = GetCurrentResourceName()

-- Shared with server/features.lua: helpers (filled in at the end of this file) and hooks it can attach to.
BM = { hooks = {} }
local function hook(name, ...)
    local fn = BM.hooks[name]
    if not fn then return end
    local ok, err = pcall(fn, ...)
    if not ok then print(('^1[blaze_bossmenu]^7 hook %s failed: %s'):format(name, err)) end
end

local APPS = Config.applications or {}
local FUNDS = Config.funds or {}
local ACT = Config.activity or {}

---------------------------------------------------------------------------
-- Groups and switches
---------------------------------------------------------------------------
local function groupCfg(gtype, name)
    if type(name) ~= 'string' then return nil end
    if gtype == 'gang' then return Config.gangs and Config.gangs[name] or nil end
    if gtype == 'job' then return Config.jobs and Config.jobs[name] or nil end
end

--- Key used in our own tables: 'ambulance' for jobs, 'gang:lostmc' for gangs
local function gkey(gtype, name) return gtype == 'gang' and ('gang:' .. name) or name end

local function appsOn(gtype, name)
    local c = gtype == 'job' and groupCfg('job', name)
    return (c and APPS.enabled and c.applications) and true or false
end

local function fundsOn(gtype, name)
    local c = groupCfg(gtype, name)
    return (c and FUNDS.enabled and c.funds and c.society and Banking.available()) and true or false
end

local function qbxManagementRunning() return GetResourceState('qbx_management') == 'started' end

local function gradeEditorOn()
    return Config.gradeEditor and Bridge.canEditGrades and GetConvar('qbx:enableGroupManagement', 'false') == 'true' or false
end

---------------------------------------------------------------------------
-- Permissions
---------------------------------------------------------------------------
local function isAdmin(src)
    return IsPlayerAceAllowed(src, Config.adminAce) or Bridge.IsFrameworkAdmin(src) or false
end

--- The player's grade if it makes them a manager of the group, else nil
local function managerGrade(src, gtype, name)
    local c = groupCfg(gtype, name)
    if not c then return nil end
    local g = Bridge.GetPlayerGroupGrade(src, gtype, name)
    if not g then return nil end
    if c.bossGrade then return g >= c.bossGrade and g or nil end
    local grade = Bridge.GetGrade(gtype, name, g)
    return grade and grade.isboss and g or nil
end

--- Actor's limit: they may act on members whose grade is BELOW this, and give grades below it.
-- Managers: their own grade. Admins (adminsCanManage): top grade + 1. nil = not allowed.
local function actorLimit(src, gtype, name)
    if not groupCfg(gtype, name) then return nil end
    local limit = managerGrade(src, gtype, name)
    if Config.adminsCanManage and isAdmin(src) then
        local grades = Bridge.GetGrades(gtype, name)
        local top = grades[#grades]
        limit = math.max(limit or -1, (top and top.level or 0) + 1)
    end
    return limit
end

local function isManager(src, job, gtype)
    return actorLimit(src, gtype or 'job', job) ~= nil
end
exports('isManager', isManager)

local function canEditForm(src, job)
    if not appsOn('job', job) then return false end
    local fe = APPS.formEditor
    if fe == 'management' then return isManager(src, job, 'job') end
    if fe == 'admin' then return isAdmin(src) end
    return false
end

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
local function notify(src, msg, ntype) Bridge.Notify(src, msg, ntype) end

local function cleanText(s, maxLen)
    if type(s) ~= 'string' then return nil end
    s = s:gsub('[%c]', ' '):gsub('^%s+', ''):gsub('%s+$', '')
    if maxLen and #s > maxLen then s = s:sub(1, maxLen) end
    return s
end

local function cleanLong(s, maxLen) -- keeps line breaks
    if type(s) ~= 'string' then return nil end
    s = s:gsub('\r', ''):gsub('[\0-\9\11-\31]', ''):gsub('^%s+', ''):gsub('%s+$', '')
    if maxLen and #s > maxLen then s = s:sub(1, maxLen) end
    return s
end

local function groupLabel(gtype, name)
    local c = groupCfg(gtype, name)
    return c and c.label or name
end

local function gradeName(gtype, name, level)
    local g = Bridge.GetGrade(gtype, name, level)
    return g and g.name or tostring(level)
end

--- Next existing grade above / below `level`
local function neighbourGrade(gtype, name, level, dir)
    local grades = Bridge.GetGrades(gtype, name)
    if dir > 0 then
        for _, g in ipairs(grades) do if g.level > level then return g.level end end
    else
        for i = #grades, 1, -1 do if grades[i].level < level then return grades[i].level end end
    end
end

--- Register a callback with error protection. Returned values go straight to the client.
local function register(name, fn)
    lib.callback.register(('%s:%s'):format(RES, name), function(src, ...)
        local ok, a, b, c = pcall(fn, src, ...)
        if not ok then
            print(('^1[blaze_bossmenu]^7 %s failed: %s'):format(name, a))
            return false, 'Something went wrong. Check the server console.'
        end
        return a, b, c
    end)
end

---------------------------------------------------------------------------
-- Database
---------------------------------------------------------------------------
local forms = {}        -- [job] = { intro, questions }  (only jobs with a saved form)
local appsOpen = {}     -- [job] = bool
local points = {}       -- placed points from the DB
local runtimePoints = {} -- points registered by other scripts (RegisterBossMenu export)
local ready = false

local function createTables()
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS `blaze_boss_applications` (
        `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
        `citizenid` VARCHAR(64) NOT NULL,
        `job` VARCHAR(64) NOT NULL,
        `name` VARCHAR(128) NOT NULL,
        `answers` LONGTEXT NOT NULL,
        `status` VARCHAR(16) NOT NULL DEFAULT 'new',
        `notes` TEXT NULL,
        `deny_reason` TEXT NULL,
        `interview_msg` TEXT NULL,
        `reviewed_by` VARCHAR(128) NULL,
        `notified` TINYINT(1) NOT NULL DEFAULT 1,
        `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        PRIMARY KEY (`id`), INDEX `job_status` (`job`, `status`), INDEX `citizenid_job` (`citizenid`, `job`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS `blaze_boss_forms` (
        `job` VARCHAR(64) NOT NULL,
        `intro` TEXT NULL,
        `questions` LONGTEXT NOT NULL,
        `updated_by` VARCHAR(128) NULL,
        `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        PRIMARY KEY (`job`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS `blaze_boss_callsigns` (
        `citizenid` VARCHAR(64) NOT NULL,
        `job` VARCHAR(64) NOT NULL,
        `callsign` VARCHAR(8) NOT NULL,
        PRIMARY KEY (`citizenid`, `job`), UNIQUE KEY `job_callsign` (`job`, `callsign`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS `blaze_boss_fund_log` (
        `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
        `job` VARCHAR(64) NOT NULL,
        `citizenid` VARCHAR(64) NULL,
        `name` VARCHAR(128) NULL,
        `type` VARCHAR(16) NOT NULL,
        `amount` INT NOT NULL,
        `reason` VARCHAR(128) NULL,
        `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (`id`), INDEX `job` (`job`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS `blaze_boss_settings` (
        `job` VARCHAR(64) NOT NULL,
        `applications_open` TINYINT(1) NOT NULL DEFAULT 1,
        PRIMARY KEY (`job`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS `blaze_boss_points` (
        `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
        `job` VARCHAR(70) NOT NULL,
        `type` VARCHAR(16) NOT NULL,
        `coords` VARCHAR(255) NOT NULL,
        `heading` FLOAT NOT NULL DEFAULT 0,
        `radius` FLOAT NOT NULL DEFAULT 1.0,
        `created_by` VARCHAR(128) NULL,
        PRIMARY KEY (`id`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
    -- Member extras: hire date + probation (rows exist for people hired through blaze_bossmenu)
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS `blaze_boss_members` (
        `citizenid` VARCHAR(64) NOT NULL,
        `job` VARCHAR(70) NOT NULL,
        `hired_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        `probation_until` DATETIME NULL,
        `probation_done` TINYINT(1) NOT NULL DEFAULT 0,
        PRIMARY KEY (`citizenid`, `job`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
    -- Employee record: commendations, write-ups, rank history, Employee of the Week wins
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS `blaze_boss_records` (
        `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
        `job` VARCHAR(70) NOT NULL,
        `citizenid` VARCHAR(64) NOT NULL,
        `type` VARCHAR(16) NOT NULL,
        `text` TEXT NULL,
        `by_name` VARCHAR(128) NULL,
        `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (`id`), INDEX `job_citizen` (`job`, `citizenid`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS `blaze_boss_audit` (
        `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
        `job` VARCHAR(70) NOT NULL,
        `actor` VARCHAR(128) NULL,
        `event` VARCHAR(32) NOT NULL,
        `message` TEXT NULL,
        `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (`id`), INDEX `job` (`job`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS `blaze_boss_announcements` (
        `job` VARCHAR(70) NOT NULL,
        `message` TEXT NOT NULL,
        `by_name` VARCHAR(128) NULL,
        `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (`job`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS `blaze_boss_eotw` (
        `job` VARCHAR(70) NOT NULL,
        `citizenid` VARCHAR(64) NOT NULL,
        `name` VARCHAR(128) NULL,
        `reason` VARCHAR(255) NULL,
        `week` INT NOT NULL,
        `by_name` VARCHAR(128) NULL,
        PRIMARY KEY (`job`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS `blaze_boss_app_votes` (
        `app_id` INT UNSIGNED NOT NULL,
        `citizenid` VARCHAR(64) NOT NULL,
        `name` VARCHAR(128) NULL,
        `vote` TINYINT NOT NULL,
        PRIMARY KEY (`app_id`, `citizenid`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
    -- Same table as qbx_management, so existing hours carry over (no foreign key: works on QBCore too)
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS `player_jobs_activity` (
        `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
        `citizenid` VARCHAR(50),
        `job` VARCHAR(255) NOT NULL,
        `last_checkin` INT NOT NULL,
        `last_checkout` INT NULL DEFAULT NULL,
        PRIMARY KEY (`id`), INDEX `last_checkout` (`last_checkout`), INDEX `citizenid_job` (`citizenid`, `job`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
end

local function loadData()
    for _, r in ipairs(MySQL.query.await('SELECT job, intro, questions FROM blaze_boss_forms') or {}) do
        local q = json.decode(r.questions)
        if type(q) == 'table' then forms[r.job] = { intro = r.intro or '', questions = q } end
    end
    for _, r in ipairs(MySQL.query.await('SELECT job, applications_open FROM blaze_boss_settings') or {}) do
        appsOpen[r.job] = r.applications_open == 1 or r.applications_open == true
    end
    points = {}
    for _, r in ipairs(MySQL.query.await('SELECT id, job, type, coords, heading, radius FROM blaze_boss_points') or {}) do
        local c = json.decode(r.coords)
        if c then
            local gtype, name = 'job', r.job
            if r.job:sub(1, 5) == 'gang:' then gtype, name = 'gang', r.job:sub(6) end
            points[#points + 1] = { id = r.id, gtype = gtype, group = name, type = r.type, coords = c, heading = r.heading, radius = r.radius }
        end
    end
end

---------------------------------------------------------------------------
-- Grade editor storage (from qbx_management: management_groups table, Qbox only)
---------------------------------------------------------------------------
local managedReady = false

local function convertGrades(gradesJson)
    local raw = json.decode(gradesJson) or {}
    local out = {}
    for k, v in pairs(raw) do out[tonumber(('%d'):format(k))] = v end
    return out
end

local function initManagedGroups()
    if not gradeEditorOn() or qbxManagementRunning() then return end
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS `management_groups` (
        `name` varchar(255) NOT NULL UNIQUE,
        `type` varchar(10) NOT NULL,
        `label` varchar(255) NOT NULL,
        `defaultDuty` tinyint(1) DEFAULT 1,
        `offDutyPay` tinyint(1) DEFAULT 0,
        `grades` LONGTEXT DEFAULT NULL,
        PRIMARY KEY (`name`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]])
    local jobs, gangs = {}, {}
    for _, r in ipairs(MySQL.query.await('SELECT * FROM `management_groups`') or {}) do
        local grades = r.grades and convertGrades(r.grades) or {}
        if r.type == 'job' then
            jobs[r.name] = { label = r.label, type = r.type, defaultDuty = r.defaultDuty == 1, offDutyPay = r.offDutyPay == 1, grades = grades }
        elseif r.type == 'gang' then
            gangs[r.name] = { label = r.label, grades = grades }
        end
    end
    Bridge.LoadManagedGroups(jobs, gangs)
    managedReady = true
end

local function saveManagedGroup(name, gtype, data)
    if not managedReady or qbxManagementRunning() then return end
    MySQL.query([[INSERT INTO `management_groups` (name, type, label, defaultDuty, offDutyPay, grades)
        VALUES (@name, @type, @label, @defaultDuty, @offDutyPay, @grades)
        ON DUPLICATE KEY UPDATE `type` = @type, `label` = @label, `defaultDuty` = @defaultDuty, `offDutyPay` = @offDutyPay, `grades` = @grades]], {
        name = name, type = gtype, label = data.label, defaultDuty = data.defaultDuty, offDutyPay = data.offDutyPay,
        grades = data.grades and json.encode(data.grades),
    })
end
AddEventHandler('qbx_core:server:onJobUpdate', function(name, job) saveManagedGroup(name, 'job', job) end)
AddEventHandler('qbx_core:server:onGangUpdate', function(name, gang) saveManagedGroup(name, 'gang', gang) end)

---------------------------------------------------------------------------
-- Duty hours (from qbx_management)
---------------------------------------------------------------------------
local clockedIn = {} -- [src] = { citizenid, job, time }

local function activityOn() return ACT.enabled and not qbxManagementRunning() end

local function checkIn(src, cid, job)
    hook('dutyOn', src, cid, job)
    if not activityOn() then return end
    clockedIn[src] = { citizenid = cid, job = job, time = os.time() }
end

local function checkOut(src)
    local c = clockedIn[src]
    if not c then return end
    clockedIn[src] = nil
    local now = os.time()
    if (now - c.time) / 60 < (ACT.minOnDutyMinutes or 30) then return end
    MySQL.insert('INSERT INTO `player_jobs_activity` (`citizenid`, `job`, `last_checkin`, `last_checkout`) VALUES (?, ?, ?, ?)',
        { c.citizenid, c.job, c.time, now })
end

RegisterNetEvent('QBCore:Server:OnPlayerLoaded', function()
    local src = source
    local p = Bridge.GetPlayer(src)
    if p and p.PlayerData.job and p.PlayerData.job.onduty then checkIn(src, p.PlayerData.citizenid, p.PlayerData.job.name) end
end)

AddEventHandler('QBCore:Server:OnJobUpdate', function(src, job)
    if clockedIn[src] then checkOut(src) end
    local p = Bridge.GetPlayer(src)
    if p and p.PlayerData.job and p.PlayerData.job.onduty then checkIn(src, p.PlayerData.citizenid, job and job.name or p.PlayerData.job.name) end
end)

AddEventHandler('QBCore:Server:SetDuty', function(src, duty)
    local p = Bridge.GetPlayer(src)
    if not p then return end
    if duty then checkIn(src, p.PlayerData.citizenid, p.PlayerData.job.name) else checkOut(src) end
end)

AddEventHandler('QBCore:Server:OnPlayerUnload', function(src) checkOut(src or source) end)
AddEventHandler('playerDropped', function() checkOut(source) end)
AddEventHandler('onResourceStop', function(res)
    if res ~= RES then return end
    for src in pairs(clockedIn) do checkOut(src) end
end)

--- { [citizenid] = { hours, lastCheckin } } for a job
local function activityFor(job)
    local out = {}
    if not ACT.enabled then return out end
    local rows = MySQL.query.await([[SELECT citizenid, MAX(last_checkin) AS last, ROUND(COALESCE(SUM(last_checkout - last_checkin) / 3600, 0), 2) AS hours
        FROM player_jobs_activity WHERE job = ? GROUP BY citizenid]], { job }) or {}
    local fmt = ACT.dateFormat or '%m-%d-%Y %H:%M'
    for _, r in ipairs(rows) do
        out[r.citizenid] = { hours = tonumber(r.hours) or 0, lastCheckin = r.last and os.date(fmt, r.last) or 'N/A', lastT = r.last }
    end
    for _, c in pairs(clockedIn) do
        if c.job == job then
            out[c.citizenid] = out[c.citizenid] or { hours = 0 }
            out[c.citizenid].lastCheckin = os.date(fmt, c.time)
            out[c.citizenid].lastT = os.time()
        end
    end
    return out
end

---------------------------------------------------------------------------
-- Points (boss desks + application points)
---------------------------------------------------------------------------
local function pointVisible(p)
    if not groupCfg(p.gtype, p.group) then return false end
    -- 'applications' = where people apply, 'review' = where managers review them
    if p.type == 'applications' or p.type == 'review' then return appsOn(p.gtype, p.group) end
    return p.type == 'boss'
end

local function allPoints()
    local out = {}
    for i, l in ipairs(Config.locations or {}) do
        local gtype = l.gang and 'gang' or 'job'
        local p = { id = 'cfg' .. i, gtype = gtype, group = l.gang or l.job, type = l.type or 'boss',
            coords = { x = l.coords.x, y = l.coords.y, z = l.coords.z }, heading = l.heading or 0.0, radius = l.radius or 1.0, fixed = 'config' }
        if pointVisible(p) then out[#out + 1] = p end
    end
    for _, p in ipairs(runtimePoints) do if pointVisible(p) then out[#out + 1] = p end end
    for _, p in ipairs(points) do if pointVisible(p) then out[#out + 1] = p end end
    return out
end

local function syncPoints() TriggerClientEvent(RES .. ':client:points', -1, allPoints()) end

---------------------------------------------------------------------------
-- Application forms
---------------------------------------------------------------------------
local TYPES = { input = true, textarea = true, number = true, select = true, checkbox = true }

local function currentForm(job)
    local f = forms[job]
    if f then return { intro = f.intro, questions = f.questions, custom = true } end
    return { intro = APPS.intro or '', questions = APPS.defaultQuestions or {}, custom = false }
end

local function isOpen(job)
    if appsOpen[job] == nil then return APPS.startOpen ~= false end
    return appsOpen[job]
end

--- Strict server-side cleaning of a form sent by the client. Returns clean form or nil, message.
local function sanitizeForm(data)
    if type(data) ~= 'table' or type(data.questions) ~= 'table' then return nil, 'Invalid form.' end
    local intro = cleanLong(data.intro or '', 10000) or ''
    if #intro > 500 then return nil, 'Intro text can be at most 500 characters.' end
    local qs = {}
    local max = APPS.maxQuestions or 15
    if #data.questions < 1 then return nil, 'The form needs at least 1 question.' end
    if #data.questions > max then return nil, ('The form can have at most %d questions.'):format(max) end
    for i, q in ipairs(data.questions) do
        if type(q) ~= 'table' then return nil, ('Question %d is invalid.'):format(i) end
        local label = cleanText(q.label, 1000)
        if not label or #label < 1 or #label > 100 then return nil, ('Question %d: text must be 1-100 characters.'):format(i) end
        if not TYPES[q.type] then return nil, ('Question %d: unknown type.'):format(i) end
        local clean = { label = label, type = q.type, required = q.required == true }
        if q.type ~= 'select' and q.type ~= 'checkbox' then
            local mn, mx = tonumber(q.min), tonumber(q.max)
            if mn then mn = math.floor(mn) end
            if mx then mx = math.floor(mx) end
            if q.type ~= 'number' then
                if mn and (mn < 0 or mn > 1000) then return nil, ('Question %d: min length must be 0-1000.'):format(i) end
                if mx and (mx < 1 or mx > 1000) then return nil, ('Question %d: max length must be 1-1000.'):format(i) end
            end
            if mn and mx and mn > mx then return nil, ('Question %d: min can\'t be more than max.'):format(i) end
            clean.min, clean.max = mn, mx
        end
        if q.type == 'select' then
            if type(q.options) ~= 'table' or #q.options < 2 or #q.options > 10 then
                return nil, ('Question %d: a dropdown needs 2-10 options.'):format(i)
            end
            clean.options = {}
            for j, o in ipairs(q.options) do
                local s = cleanText(o, 1000)
                if not s or #s < 1 or #s > 50 then return nil, ('Question %d, option %d: must be 1-50 characters.'):format(i, j) end
                clean.options[#clean.options + 1] = s
            end
        end
        qs[#qs + 1] = clean
    end
    return { intro = intro, questions = qs }
end

--- Check answers against the CURRENT form. Returns snapshot list or nil, message, question index.
local function validateAnswers(questions, answers)
    if type(answers) ~= 'table' then return nil, 'No answers received.' end
    local snapshot = {}
    for i, q in ipairs(questions) do
        local a = answers[i]
        local out
        if q.type == 'checkbox' then
            out = a == true
            if q.required and not out then return nil, ('"%s" must be ticked.'):format(q.label), i end
        elseif q.type == 'number' then
            local n = tonumber(a)
            if n == nil then
                if q.required then return nil, ('"%s" is required.'):format(q.label), i end
            else
                if q.min and n < q.min then return nil, ('"%s" must be at least %s.'):format(q.label, q.min), i end
                if q.max and n > q.max then return nil, ('"%s" must be at most %s.'):format(q.label, q.max), i end
                out = n
            end
        elseif q.type == 'select' then
            local s = type(a) == 'string' and a or nil
            if s == nil or s == '' then
                if q.required then return nil, ('"%s" is required.'):format(q.label), i end
            else
                local found = false
                for _, o in ipairs(q.options or {}) do if o == s then found = true break end end
                if not found then return nil, ('"%s": pick one of the options.'):format(q.label), i end
                out = s
            end
        else
            local s = q.type == 'textarea' and cleanLong(a, 1000) or cleanText(a, 1000)
            if s == nil or s == '' then
                if q.required then return nil, ('"%s" is required.'):format(q.label), i end
            else
                if q.min and #s < q.min then return nil, ('"%s" needs at least %d characters.'):format(q.label, q.min), i end
                if q.max and #s > q.max then return nil, ('"%s" can be at most %d characters.'):format(q.label, q.max), i end
                out = s
            end
        end
        snapshot[#snapshot + 1] = { label = q.label, type = q.type, answer = out }
    end
    return snapshot
end

local STATUS_LABEL = { new = 'Waiting for review', interview = 'Invited to interview', accepted = 'Accepted', denied = 'Denied', withdrawn = 'Withdrawn' }

local function statusMessage(job, row)
    local label = groupLabel('job', job)
    if row.status == 'accepted' then return ('Your %s application was accepted. Welcome aboard!'):format(label), 'success' end
    if row.status == 'denied' then
        return ('Your %s application was denied.%s'):format(label, row.deny_reason and (' Reason: ' .. row.deny_reason) or ''), 'error'
    end
    if row.status == 'interview' then
        return ('You are invited to an interview for %s.%s'):format(label, row.interview_msg and (' ' .. row.interview_msg) or ''), 'inform'
    end
    if row.status == 'withdrawn' then return ('You withdrew your %s application.'):format(label), 'inform' end
    return ('Your %s application is waiting for review.'):format(label), 'inform'
end

--- Tell the applicant now if online, otherwise flag it for their next login
local function notifyApplicant(id)
    local row = MySQL.single.await('SELECT id, citizenid, job, name, status, deny_reason, interview_msg FROM blaze_boss_applications WHERE id = ?', { id })
    if not row then return end
    hook('applicationUpdate', row)
    local p = Bridge.GetPlayerByCitizenId(row.citizenid)
    if p then
        local msg, t = statusMessage(row.job, row)
        Bridge.Notify(p.PlayerData.source, msg, t, 'Application')
        MySQL.update('UPDATE blaze_boss_applications SET notified = 1, updated_at = updated_at WHERE id = ?', { id })
    else
        MySQL.update('UPDATE blaze_boss_applications SET notified = 0, updated_at = updated_at WHERE id = ?', { id })
    end
end

AddEventHandler('QBCore:Server:PlayerLoaded', function(player)
    if not ready or not APPS.enabled then return end
    local pd = player and player.PlayerData
    if not pd then return end
    local src, cid = pd.source, pd.citizenid
    SetTimeout(5000, function()
        local rows = MySQL.query.await("SELECT id, job, status, deny_reason, interview_msg FROM blaze_boss_applications WHERE citizenid = ? AND notified = 0 AND status IN ('accepted','denied','interview')", { cid }) or {}
        for _, r in ipairs(rows) do
            local msg, t = statusMessage(r.job, r)
            Bridge.Notify(src, msg, t, 'Application')
            MySQL.update('UPDATE blaze_boss_applications SET notified = 1, updated_at = updated_at WHERE id = ?', { r.id })
        end
    end)
end)

---------------------------------------------------------------------------
-- Hire consent (from qbx_management)
---------------------------------------------------------------------------
local function askConsent(target, fromName, label)
    if not Config.hireConsent then return true end
    local p, done = promise.new(), false
    lib.callback(RES .. ':client:confirmHire', target, function(answer)
        if done then return end
        done = true
        p:resolve(answer == true)
    end, fromName, label, Config.hireConsentSeconds or 30)
    SetTimeout(((Config.hireConsentSeconds or 30) + 2) * 1000, function()
        if done then return end
        done = true
        p:resolve(false)
    end)
    return Citizen.Await(p)
end

---------------------------------------------------------------------------
-- Menu data
---------------------------------------------------------------------------
--- Groups this player can manage
register('getMyJobs', function(src)
    local list = {}
    local admin = isAdmin(src)
    for _, gtype in ipairs({ 'job', 'gang' }) do
        local cfgList = gtype == 'job' and Config.jobs or Config.gangs or {}
        for name, c in pairs(cfgList) do
            if Bridge.GroupExists(gtype, name) and actorLimit(src, gtype, name) then
                list[#list + 1] = { gtype = gtype, name = name, label = c.label or name }
            end
        end
    end
    table.sort(list, function(a, b) return a.label < b.label end)
    return { groups = list, isAdmin = admin }
end)

--- Everything the main menu needs to show/hide its options
register('getMenu', function(src, gtype, name)
    local limit = actorLimit(src, gtype, name)
    if not limit then return nil end
    local data = {
        gtype = gtype, name = name, label = groupLabel(gtype, name), limit = limit,
        apps = appsOn(gtype, name), funds = fundsOn(gtype, name),
        formEdit = gtype == 'job' and canEditForm(src, name) or false,
        gradeEdit = gradeEditorOn(), isAdmin = isAdmin(src),
        callsigns = gtype == 'job', grades = Bridge.GetGrades(gtype, name),
        ownGrade = managerGrade(src, gtype, name),
    }
    if data.apps then
        data.appsOpen = isOpen(name)
        data.newApps = MySQL.scalar.await("SELECT COUNT(*) FROM blaze_boss_applications WHERE job = ? AND status = 'new'", { name }) or 0
    end
    if data.funds then data.balance = Banking.getBalance(groupCfg(gtype, name).society) end
    return data
end)

register('getStaff', function(src, gtype, name)
    local limit = actorLimit(src, gtype, name)
    if not limit then return nil end
    local members = Bridge.GetMembers(gtype, name)
    local callsigns, activity = {}, {}
    if gtype == 'job' then
        for _, r in ipairs(MySQL.query.await('SELECT citizenid, callsign FROM blaze_boss_callsigns WHERE job = ?', { name }) or {}) do
            callsigns[r.citizenid] = r.callsign
        end
        activity = activityFor(name)
    end
    local me = Bridge.GetCitizenId(src)
    for _, m in ipairs(members) do
        m.gradeName = gradeName(gtype, name, m.grade)
        m.callsign = callsigns[m.citizenid]
        m.isSelf = m.citizenid == me
        local a = activity[m.citizenid]
        if a then m.hours, m.lastCheckin = a.hours, a.lastCheckin end
        m.src = nil
    end
    table.sort(members, function(a, b)
        if a.grade ~= b.grade then return a.grade > b.grade end
        return a.name < b.name
    end)
    hook('decorateStaff', gtype, name, members, activity)
    return { members = members, limit = limit, grades = Bridge.GetGrades(gtype, name) }
end)

---------------------------------------------------------------------------
-- Staff actions
---------------------------------------------------------------------------
--- Shared checks for acting on someone. Returns limit, targetGrade or nil, message.
local function checkTarget(src, gtype, name, cid, allowSelf)
    local limit = actorLimit(src, gtype, name)
    if not limit then return nil, 'You are not a manager here.' end
    if type(cid) ~= 'string' then return nil, 'Invalid person.' end
    local self = Bridge.GetCitizenId(src) == cid
    if self and not allowSelf then return nil, 'You can\'t do that to yourself.' end
    local grade = Bridge.GetMemberGrade(cid, gtype, name)
    if not grade then return nil, 'That person is not in this ' .. (gtype == 'gang' and 'gang' or 'job') .. '.' end
    if not self and grade >= limit then return nil, 'You can only manage people below your rank.' end
    return limit, grade
end

local function notifyMember(cid, msg, ntype)
    local p = Bridge.GetPlayerByCitizenId(cid)
    if p then Bridge.Notify(p.PlayerData.source, msg, ntype) end
end

local function changeGrade(src, gtype, name, cid, dir)
    local limit, grade = checkTarget(src, gtype, name, cid, false)
    if not limit then return false, grade end
    local new = neighbourGrade(gtype, name, grade, dir)
    if not new then return false, dir > 0 and 'They are already at the top rank.' or 'They are already at the lowest rank.' end
    if dir > 0 and new >= limit then return false, 'You can only promote up to the rank below yours.' end
    local ok, err = Bridge.SetGrade(cid, gtype, name, new)
    if not ok then return false, err or 'Could not change their rank.' end
    local who = Bridge.GetNameByCitizenId(cid)
    local newName = gradeName(gtype, name, new)
    hook('gradeChanged', src, cid, gtype, name, grade, new, dir)
    notifyMember(cid, ('You were %s to %s.'):format(dir > 0 and 'promoted' or 'demoted', newName), dir > 0 and 'success' or 'inform')
    Logs.log(dir > 0 and 'promote' or 'demote', src, ('%s %s %s to %s (%s)'):format(Logs.who(src), dir > 0 and 'promoted' or 'demoted', who, newName, groupLabel(gtype, name)),
        { Group = gkey(gtype, name), Target = cid, From = grade, To = new })
    return true, ('%s is now %s.'):format(who, newName)
end

register('promote', function(src, gtype, name, cid) return changeGrade(src, gtype, name, cid, 1) end)
register('demote', function(src, gtype, name, cid) return changeGrade(src, gtype, name, cid, -1) end)

register('fire', function(src, gtype, name, cid)
    local limit, grade = checkTarget(src, gtype, name, cid, false)
    if not limit then return false, grade end
    local who = Bridge.GetNameByCitizenId(cid)
    local ok, err = Bridge.RemoveGroup(cid, gtype, name)
    if not ok then return false, err or 'Could not remove them.' end
    if gtype == 'job' then MySQL.update('DELETE FROM blaze_boss_callsigns WHERE citizenid = ? AND job = ?', { cid, name }) end
    hook('removed', src, cid, gtype, name)
    notifyMember(cid, ('You were removed from %s.'):format(groupLabel(gtype, name)), 'error')
    Logs.log('fire', src, ('%s removed %s from %s'):format(Logs.who(src), who, groupLabel(gtype, name)), { Group = gkey(gtype, name), Target = cid, Grade = grade })
    return true, ('%s was removed.'):format(who)
end)

register('setCallsign', function(src, gtype, name, cid, callsign)
    if gtype ~= 'job' then return false, 'Callsigns are for jobs only.' end
    local limit, err = checkTarget(src, gtype, name, cid, true)
    if not limit then return false, err end
    callsign = type(callsign) == 'string' and callsign:upper():gsub('%s', '') or ''
    if #callsign < 1 or #callsign > 8 or not callsign:match('^[A-Z0-9%-]+$') then
        return false, 'Callsign must be 1-8 letters, numbers or dashes.'
    end
    local taken = MySQL.scalar.await('SELECT citizenid FROM blaze_boss_callsigns WHERE job = ? AND callsign = ?', { name, callsign })
    if taken and taken ~= cid then return false, ('Callsign %s is already taken.'):format(callsign) end
    MySQL.query.await('INSERT INTO blaze_boss_callsigns (citizenid, job, callsign) VALUES (?, ?, ?) ON DUPLICATE KEY UPDATE callsign = VALUES(callsign)', { cid, name, callsign })
    Bridge.SetCallsign(cid, callsign)
    local who = Bridge.GetNameByCitizenId(cid)
    Logs.log('callsign', src, ('%s set %s\'s callsign to %s (%s)'):format(Logs.who(src), who, callsign, groupLabel(gtype, name)), { Group = name, Target = cid, Callsign = callsign })
    return true, ('Callsign set to %s.'):format(callsign)
end)

register('getNearbyPlayers', function(src, gtype, name)
    if not actorLimit(src, gtype, name) then return {} end
    local out = {}
    local myPos = GetEntityCoords(GetPlayerPed(src))
    for target, p in pairs(Bridge.GetPlayers() or {}) do
        if target ~= src and not Bridge.GetPlayerGroupGrade(target, gtype, name) then
            local ped = GetPlayerPed(target)
            if ped ~= 0 and #(GetEntityCoords(ped) - myPos) <= (Config.hireDistance or 5.0) then
                out[#out + 1] = { src = target, name = Bridge.CharName(p.PlayerData.charinfo) }
            end
        end
    end
    table.sort(out, function(a, b) return a.name < b.name end)
    return out
end)

register('hire', function(src, gtype, name, target, grade)
    local limit = actorLimit(src, gtype, name)
    if not limit then return false, 'You are not a manager here.' end
    target, grade = tonumber(target), tonumber(grade)
    if not target or not grade then return false, 'Invalid input.' end
    if target == src then return false, 'You can\'t hire yourself.' end
    local tp = Bridge.GetPlayer(target)
    if not tp then return false, 'Nobody with that ID is online.' end
    local a, b = GetPlayerPed(src), GetPlayerPed(target)
    if a == 0 or b == 0 or #(GetEntityCoords(a) - GetEntityCoords(b)) > (Config.hireDistance or 5.0) then
        return false, 'That person is too far away.'
    end
    if Bridge.GetPlayerGroupGrade(target, gtype, name) then return false, 'They are already a member.' end
    if not Bridge.GetGrade(gtype, name, grade) then return false, 'That rank doesn\'t exist.' end
    if grade >= limit then return false, 'You can only hire up to the rank below yours.' end
    local label = groupLabel(gtype, name)
    if not askConsent(target, Bridge.GetName(src), label) then return false, 'They declined the offer.' end
    local cid = tp.PlayerData.citizenid
    local ok, err = Bridge.SetGroup(cid, gtype, name, grade)
    if not ok then return false, err or 'Could not hire them.' end
    local who = Bridge.GetName(target)
    Bridge.Notify(target, ('You were hired into %s as %s.'):format(label, gradeName(gtype, name, grade)), 'success')
    hook('hired', src, cid, gtype, name, grade, target)
    Logs.log('hire', src, ('%s hired %s into %s as %s'):format(Logs.who(src), Logs.who(target), label, gradeName(gtype, name, grade)), { Group = gkey(gtype, name), Target = cid, Grade = grade })
    return true, ('%s was hired.'):format(who)
end)

---------------------------------------------------------------------------
-- Grade editor (from qbx_management, Qbox only)
---------------------------------------------------------------------------
register('modifyGrade', function(src, gtype, name, level, data)
    if not gradeEditorOn() then return false, 'Grade editing is turned off.' end
    local limit = actorLimit(src, gtype, name)
    level = tonumber(level)
    if not limit or not level then return false, 'You are not a manager here.' end
    local own = managerGrade(src, gtype, name)
    if level >= limit and level ~= own then return false, 'You can only edit ranks up to your own.' end
    local group = Bridge.GetGroup(gtype, name)
    local current = group and group.grades and group.grades[level]
    if not current or type(data) ~= 'table' then return false, 'That rank doesn\'t exist.' end
    local label = cleanText(data.name, 100)
    if not label or #label < 1 or #label > 50 then return false, 'Rank name must be 1-50 characters.' end
    local new = lib.table.deepclone(current)
    new.name = label
    if gtype == 'job' then
        local pay = tonumber(data.payment)
        if not pay or pay < 0 or pay > 1000000 then return false, 'Pay must be between 0 and 1,000,000.' end
        new.payment = math.floor(pay)
        new.bankAuth = data.bankAuth == true
    end
    local wantBoss = data.isboss == true
    if level == own and not wantBoss and not isAdmin(src) then return false, 'You can\'t remove the boss flag from your own rank.' end
    new.isboss = wantBoss
    Bridge.UpsertGrade(gtype, name, level, new)
    Logs.log('gradeEdit', src, ('%s edited rank %s of %s'):format(Logs.who(src), level, groupLabel(gtype, name)),
        { Group = gkey(gtype, name), Grade = level, Name = new.name, Pay = new.payment or '-', Boss = tostring(new.isboss) })
    return true, 'Rank updated.'
end)

---------------------------------------------------------------------------
-- Funds
---------------------------------------------------------------------------
if FUNDS.enabled then
    local function fundsCheck(src, gtype, name)
        if not fundsOn(gtype, name) then return nil, 'Funds are turned off for this group.' end
        if not actorLimit(src, gtype, name) then return nil, 'You are not a manager here.' end
        return groupCfg(gtype, name).society
    end

    local function cleanAmount(amount)
        amount = tonumber(amount)
        if not amount or amount ~= math.floor(amount) or amount < 1 or amount > 1000000000 then return nil end
        return math.floor(amount)
    end

    register('getFunds', function(src, gtype, name)
        local account, err = fundsCheck(src, gtype, name)
        if not account then return nil, err end
        local history = MySQL.query.await(("SELECT name, type, amount, reason, DATE_FORMAT(created_at, '%%Y-%%m-%%d %%H:%%i') AS at FROM blaze_boss_fund_log WHERE job = ? ORDER BY id DESC LIMIT %d")
            :format(math.max(1, math.floor(FUNDS.historyLimit or 20))), { gkey(gtype, name) }) or {}
        return { balance = Banking.getBalance(account), history = history, confirmAbove = FUNDS.confirmAbove or 5000, left = BM.withdrawLeft(src, gtype, name) }
    end)

    local function logFunds(src, gtype, name, kind, amount, reason)
        MySQL.insert('INSERT INTO blaze_boss_fund_log (job, citizenid, name, type, amount, reason) VALUES (?, ?, ?, ?, ?, ?)',
            { gkey(gtype, name), Bridge.GetCitizenId(src), Bridge.GetName(src), kind, amount, reason })
        Logs.log(kind, src, ('%s %s $%d %s %s (%s)'):format(Logs.who(src), kind == 'deposit' and 'deposited' or 'withdrew', amount,
            kind == 'deposit' and 'into' or 'from', groupLabel(gtype, name), reason), { Group = gkey(gtype, name), Amount = '$' .. amount, Reason = reason })
    end

    register('deposit', function(src, gtype, name, amount, reason)
        local account, err = fundsCheck(src, gtype, name)
        if not account then return false, err end
        amount = cleanAmount(amount)
        reason = cleanText(reason, 100)
        if not amount then return false, 'Enter a whole amount of at least $1.' end
        if not reason or #reason < 1 then return false, 'A reason is required.' end
        if not Bridge.RemoveCash(src, amount, 'Society deposit') then return false, 'You don\'t have that much cash.' end
        if not Banking.deposit(account, amount, reason) then
            Bridge.AddCash(src, amount, 'Society deposit refund')
            return false, 'The deposit failed. Your cash was returned.'
        end
        logFunds(src, gtype, name, 'deposit', amount, reason)
        return true, ('Deposited $%d.'):format(amount)
    end)

    register('withdraw', function(src, gtype, name, amount, reason)
        local account, err = fundsCheck(src, gtype, name)
        if not account then return false, err end
        amount = cleanAmount(amount)
        reason = cleanText(reason, 100)
        if not amount then return false, 'Enter a whole amount of at least $1.' end
        if not reason or #reason < 1 then return false, 'A reason is required.' end
        local left = BM.withdrawLeft(src, gtype, name)
        if left and amount > left then return false, ('Your rank can take out $%d more today.'):format(math.max(0, left)) end
        if not Banking.withdraw(account, amount, reason) then return false, 'The account doesn\'t have enough money.' end
        if not Bridge.AddCash(src, amount, 'Society withdrawal') then
            Banking.deposit(account, amount, 'Withdrawal refund')
            return false, 'Could not give you the cash. The money was returned to the account.'
        end
        logFunds(src, gtype, name, 'withdraw', amount, reason)
        return true, ('Withdrew $%d.'):format(amount)
    end)
end

---------------------------------------------------------------------------
-- Applications
---------------------------------------------------------------------------
if APPS.enabled then
    local function managerCheck(src, job)
        if not appsOn('job', job) then return nil, 'Applications are turned off for this job.' end
        local limit = actorLimit(src, 'job', job)
        if not limit then return nil, 'You are not a manager here.' end
        return limit
    end

    local function loadApp(job, id)
        id = tonumber(id)
        if not id then return nil end
        return MySQL.single.await('SELECT * FROM blaze_boss_applications WHERE id = ? AND job = ?', { id, job })
    end

    register('getForm', function(src, job)
        if not appsOn('job', job) then return nil end
        local f = currentForm(job)
        return { intro = f.intro, questions = f.questions, custom = f.custom, open = isOpen(job), label = groupLabel('job', job), maxQuestions = APPS.maxQuestions or 15 }
    end)

    register('submitApplication', function(src, job, answers)
        if not appsOn('job', job) then return false, 'This job doesn\'t take applications.' end
        if not isOpen(job) then return false, ('%s is not accepting applications right now.'):format(groupLabel('job', job)) end
        local cid = Bridge.GetCitizenId(src)
        if not cid then return false, 'Character not loaded.' end
        if Bridge.GetPlayerGroupGrade(src, 'job', job) then return false, 'You already work here.' end
        local open = MySQL.scalar.await("SELECT id FROM blaze_boss_applications WHERE citizenid = ? AND job = ? AND status IN ('new','interview') LIMIT 1", { cid, job })
        if open then return false, 'You already have an application waiting for review.' end
        local hours = tonumber(APPS.denyCooldownHours) or 0
        if hours > 0 then
            local recent = MySQL.scalar.await("SELECT id FROM blaze_boss_applications WHERE citizenid = ? AND job = ? AND status = 'denied' AND updated_at > (NOW() - INTERVAL ? HOUR) LIMIT 1", { cid, job, hours })
            if recent then return false, ('Your last application was denied. You can apply again %d hours after the denial.'):format(hours) end
        end
        local snapshot, err, badIndex = validateAnswers(currentForm(job).questions, answers)
        if not snapshot then return false, err, badIndex end
        local name = Bridge.GetName(src)
        MySQL.insert.await('INSERT INTO blaze_boss_applications (citizenid, job, name, answers) VALUES (?, ?, ?, ?)', { cid, job, name, json.encode(snapshot) })
        for target in pairs(Bridge.GetPlayers() or {}) do
            if target ~= src and managerGrade(target, 'job', job) then
                Bridge.Notify(target, ('New job application from %s'):format(name), 'inform', groupLabel('job', job))
            end
        end
        return true, 'Application sent. Managers will review it.'
    end)

    register('getMyApplicationStatus', function(src, job)
        if not appsOn('job', job) then return nil end
        local cid = Bridge.GetCitizenId(src)
        local row = MySQL.single.await('SELECT status, deny_reason, interview_msg FROM blaze_boss_applications WHERE citizenid = ? AND job = ? ORDER BY id DESC LIMIT 1', { cid, job })
        if not row then return { none = true } end
        local msg, t = statusMessage(job, row)
        return { status = row.status, label = STATUS_LABEL[row.status], message = msg, type = t }
    end)

    --- The player's own applications (newest first) for the status menu. job = nil for every job.
    -- Manager notes are never sent to the applicant.
    register('getMyApplications', function(src, job)
        local cid = Bridge.GetCitizenId(src)
        if not cid then return {} end
        if job ~= nil and not appsOn('job', job) then return {} end
        local hours = tonumber(APPS.denyCooldownHours) or 0
        local rows = MySQL.query.await(([[SELECT id, job, status, answers, deny_reason, interview_msg, reviewed_by,
                DATE_FORMAT(created_at, '%%Y-%%m-%%d %%H:%%i') AS created, DATE_FORMAT(updated_at, '%%Y-%%m-%%d %%H:%%i') AS updated,
                DATE_FORMAT(updated_at + INTERVAL ? HOUR, '%%Y-%%m-%%d %%H:%%i') AS reapply_at,
                (updated_at + INTERVAL ? HOUR > NOW()) AS cooling
            FROM blaze_boss_applications WHERE citizenid = ? %s ORDER BY id DESC LIMIT 25]]):format(job and 'AND job = ?' or ''),
            job and { hours, hours, cid, job } or { hours, hours, cid }) or {}
        local out = {}
        for _, r in ipairs(rows) do
            if appsOn('job', r.job) then
                local msg = statusMessage(r.job, r)
                out[#out + 1] = {
                    id = r.id, job = r.job, jobLabel = groupLabel('job', r.job), status = r.status, statusLabel = STATUS_LABEL[r.status],
                    message = msg, answers = json.decode(r.answers) or {}, denyReason = r.deny_reason, interviewMsg = r.interview_msg,
                    reviewedBy = r.reviewed_by, created = r.created, updated = r.updated,
                    reapplyAt = (r.status == 'denied' and hours > 0 and (r.cooling == 1 or r.cooling == true)) and r.reapply_at or nil,
                    open = isOpen(r.job),
                }
            end
        end
        -- they've now seen any pending updates
        MySQL.update('UPDATE blaze_boss_applications SET notified = 1, updated_at = updated_at WHERE citizenid = ? AND notified = 0', { cid })
        return out
    end)

    register('getApplications', function(src, job, filter)
        if not managerCheck(src, job) then return nil end
        local where = "status IN ('new','interview')"
        if filter == 'accepted' then where = "status = 'accepted'"
        elseif filter == 'denied' then where = "status = 'denied'"
        elseif filter == 'withdrawn' then where = "status = 'withdrawn'" end
        return MySQL.query.await(("SELECT id, name, status, DATE_FORMAT(created_at, '%%Y-%%m-%%d %%H:%%i') AS created FROM blaze_boss_applications WHERE job = ? AND %s ORDER BY id DESC LIMIT 100"):format(where), { job }) or {}
    end)

    register('getApplication', function(src, job, id)
        if not managerCheck(src, job) then return nil end
        local row = loadApp(job, id)
        if not row then return nil end
        row.answers = json.decode(row.answers) or {}
        row.statusLabel = STATUS_LABEL[row.status]
        if APPS.votes then
            local me = Bridge.GetCitizenId(src)
            row.votes = { up = 0, down = 0, mine = 0, voters = {} }
            for _, v in ipairs(MySQL.query.await('SELECT citizenid, name, vote FROM blaze_boss_app_votes WHERE app_id = ?', { row.id }) or {}) do
                if v.vote > 0 then row.votes.up = row.votes.up + 1 else row.votes.down = row.votes.down + 1 end
                if v.citizenid == me then row.votes.mine = v.vote end
                row.votes.voters[#row.votes.voters + 1] = ('%s %s'):format(v.vote > 0 and '👍' or '👎', v.name or '?')
            end
        end
        row.created_at, row.updated_at = nil, nil
        return row
    end)

    register('interview', function(src, job, id, msg)
        local limit, err = managerCheck(src, job)
        if not limit then return false, err end
        local row = loadApp(job, id)
        if not row then return false, 'Application not found.' end
        if row.status ~= 'new' and row.status ~= 'interview' then return false, 'This application was already decided.' end
        msg = cleanText(msg, 300)
        if not msg or #msg < 1 then return false, 'Write a message for the applicant.' end
        MySQL.update.await("UPDATE blaze_boss_applications SET status = 'interview', interview_msg = ?, reviewed_by = ? WHERE id = ?", { msg, Bridge.GetName(src), row.id })
        notifyApplicant(row.id)
        Logs.log('interview', src, ('%s invited %s to an interview (%s)'):format(Logs.who(src), row.name, groupLabel('job', job)), { Job = job, Application = row.id })
        return true, 'Interview invite sent.'
    end)

    register('accept', function(src, job, id, grade)
        local limit, err = managerCheck(src, job)
        if not limit then return false, err end
        local row = loadApp(job, id)
        if not row then return false, 'Application not found.' end
        if row.status ~= 'new' and row.status ~= 'interview' then return false, 'This application was already decided.' end
        grade = tonumber(grade)
        if not grade or not Bridge.GetGrade('job', job, grade) then return false, 'That rank doesn\'t exist.' end
        if grade >= limit then return false, 'You can only hire up to the rank below yours.' end
        if Bridge.GetMemberGrade(row.citizenid, 'job', job) then return false, 'They already work here.' end
        local ok, e = Bridge.SetGroup(row.citizenid, 'job', job, grade)
        if not ok then return false, e or 'Could not hire them.' end
        MySQL.update.await("UPDATE blaze_boss_applications SET status = 'accepted', reviewed_by = ? WHERE id = ?", { Bridge.GetName(src), row.id })
        notifyApplicant(row.id)
        local applicant = Bridge.GetPlayerByCitizenId(row.citizenid)
        hook('hired', src, row.citizenid, 'job', job, grade, nil, applicant and applicant.PlayerData.source or nil)
        Logs.log('accept', src, ('%s accepted %s into %s as %s'):format(Logs.who(src), row.name, groupLabel('job', job), gradeName('job', job, grade)),
            { Job = job, Application = row.id, Target = row.citizenid, Grade = grade })
        return true, ('%s was hired.'):format(row.name)
    end)

    register('deny', function(src, job, id, reason)
        local limit, err = managerCheck(src, job)
        if not limit then return false, err end
        local row = loadApp(job, id)
        if not row then return false, 'Application not found.' end
        if row.status ~= 'new' and row.status ~= 'interview' then return false, 'This application was already decided.' end
        reason = cleanText(reason, 300)
        if not reason or #reason < 1 then return false, 'A reason is required.' end
        MySQL.update.await("UPDATE blaze_boss_applications SET status = 'denied', deny_reason = ?, reviewed_by = ? WHERE id = ?", { reason, Bridge.GetName(src), row.id })
        notifyApplicant(row.id)
        Logs.log('deny', src, ('%s denied %s for %s'):format(Logs.who(src), row.name, groupLabel('job', job)), { Job = job, Application = row.id, Reason = reason })
        return true, 'Application denied.'
    end)

    register('saveNote', function(src, job, id, note)
        local limit, err = managerCheck(src, job)
        if not limit then return false, err end
        local row = loadApp(job, id)
        if not row then return false, 'Application not found.' end
        note = cleanLong(note or '', 1000) or ''
        -- keep updated_at so a note doesn't restart the denial cooldown
        MySQL.update.await('UPDATE blaze_boss_applications SET notes = ?, updated_at = updated_at WHERE id = ?', { note, row.id })
        return true, 'Note saved.'
    end)

    register('toggleApplications', function(src, job)
        local limit, err = managerCheck(src, job)
        if not limit then return false, err end
        local new = not isOpen(job)
        appsOpen[job] = new
        MySQL.query.await('INSERT INTO blaze_boss_settings (job, applications_open) VALUES (?, ?) ON DUPLICATE KEY UPDATE applications_open = VALUES(applications_open)', { job, new and 1 or 0 })
        Logs.log('toggle', src, ('%s %s applications for %s'):format(Logs.who(src), new and 'opened' or 'closed', groupLabel('job', job)), { Job = job, Open = tostring(new) })
        return true, new and 'Applications are now open.' or 'Applications are now closed.', new
    end)

    if APPS.formEditor then
        register('saveForm', function(src, job, data)
            if not canEditForm(src, job) then return false, 'You can\'t edit this form.' end
            local clean, err = sanitizeForm(data)
            if not clean then return false, err end
            MySQL.query.await('INSERT INTO blaze_boss_forms (job, intro, questions, updated_by) VALUES (?, ?, ?, ?) ON DUPLICATE KEY UPDATE intro = VALUES(intro), questions = VALUES(questions), updated_by = VALUES(updated_by)',
                { job, clean.intro, json.encode(clean.questions), Bridge.GetName(src) })
            forms[job] = clean
            Logs.log('formEdit', src, ('%s saved the %s application form (%d questions)'):format(Logs.who(src), groupLabel('job', job), #clean.questions), { Job = job })
            return true, 'Form saved. New applicants will see it.'
        end)

        register('resetForm', function(src, job)
            if not canEditForm(src, job) then return false, 'You can\'t edit this form.' end
            MySQL.query.await('DELETE FROM blaze_boss_forms WHERE job = ?', { job })
            forms[job] = nil
            Logs.log('formReset', src, ('%s reset the %s application form to default'):format(Logs.who(src), groupLabel('job', job)), { Job = job })
            return true, 'Form reset to the default.'
        end)
    end
end

---------------------------------------------------------------------------
-- Points (placement is admin only)
---------------------------------------------------------------------------
register('getPoints', function() return allPoints() end)

register('getPlacementInfo', function(src)
    if not isAdmin(src) then return nil end
    local groups = {}
    for _, gtype in ipairs({ 'job', 'gang' }) do
        for name, c in pairs((gtype == 'job' and Config.jobs or Config.gangs) or {}) do
            groups[#groups + 1] = { gtype = gtype, name = name, label = c.label or name, apps = appsOn(gtype, name) }
        end
    end
    table.sort(groups, function(a, b) return a.label < b.label end)
    return { groups = groups, points = allPoints() }
end)

register('addPoint', function(src, gtype, name, ptype, coords, heading, radius)
    if not isAdmin(src) then return false, 'Admins only.' end
    if not groupCfg(gtype, name) then return false, 'That group isn\'t configured.' end
    if ptype ~= 'boss' and ptype ~= 'applications' and ptype ~= 'review' then return false, 'Invalid point type.' end
    if ptype ~= 'boss' and not appsOn(gtype, name) then return false, 'Applications are off for this group.' end
    if type(coords) ~= 'table' and type(coords) ~= 'vector3' then return false, 'Invalid position.' end
    local x, y, z = tonumber(coords.x), tonumber(coords.y), tonumber(coords.z)
    if not x or not y or not z then return false, 'Invalid position.' end
    radius = math.min(5.0, math.max(0.5, tonumber(radius) or 1.0))
    heading = (tonumber(heading) or 0.0) % 360
    local c = { x = math.floor(x * 100) / 100, y = math.floor(y * 100) / 100, z = math.floor(z * 100) / 100 }
    local id = MySQL.insert.await('INSERT INTO blaze_boss_points (job, type, coords, heading, radius, created_by) VALUES (?, ?, ?, ?, ?, ?)',
        { gkey(gtype, name), ptype, json.encode(c), heading, radius, Bridge.GetName(src) })
    points[#points + 1] = { id = id, gtype = gtype, group = name, type = ptype, coords = c, heading = heading, radius = radius }
    syncPoints()
    Logs.log('placement', src, ('%s added a %s point for %s'):format(Logs.who(src), ptype, groupLabel(gtype, name)), { Group = gkey(gtype, name), Id = id, Coords = json.encode(c) })
    return true, 'Point saved.'
end)

register('removePoint', function(src, id)
    if not isAdmin(src) then return false, 'Admins only.' end
    id = tonumber(id)
    if not id then return false, 'Built-in points can\'t be deleted in game. Remove them from config.lua.' end
    for i, p in ipairs(points) do
        if p.id == id then
            MySQL.query.await('DELETE FROM blaze_boss_points WHERE id = ?', { id })
            table.remove(points, i)
            syncPoints()
            Logs.log('placement', src, ('%s deleted %s point #%d for %s'):format(Logs.who(src), p.type, id, groupLabel(p.gtype, p.group)), { Group = gkey(p.gtype, p.group), Id = id })
            return true, 'Point deleted.'
        end
    end
    return false, 'Point not found.'
end)

RegisterCommand('bossmenu', function(src)
    if src == 0 then return print('[blaze_bossmenu] /bossmenu is an in-game command.') end
    if not isAdmin(src) then return notify(src, 'You don\'t have permission to use this.', 'error') end
    TriggerClientEvent(RES .. ':client:placement', src)
end, false)

---------------------------------------------------------------------------
-- qbx_management compatibility: RegisterBossMenu export
---------------------------------------------------------------------------
--- menuInfo = { groupName, type = 'job'|'gang', coords = vec3, size?, rotation? } (qbx_management shape)
local function registerBossMenu(menuInfo)
    if type(menuInfo) ~= 'table' or not menuInfo.coords or not menuInfo.groupName then return end
    local gtype = menuInfo.type == 'gang' and 'gang' or 'job'
    if not groupCfg(gtype, menuInfo.groupName) then
        print(('^3[blaze_bossmenu]^7 RegisterBossMenu: %s "%s" is not in config.lua, so no desk was added.'):format(gtype, menuInfo.groupName))
        return
    end
    runtimePoints[#runtimePoints + 1] = {
        id = 'rt' .. (#runtimePoints + 1), gtype = gtype, group = menuInfo.groupName, type = 'boss',
        coords = { x = menuInfo.coords.x, y = menuInfo.coords.y, z = menuInfo.coords.z },
        heading = menuInfo.rotation or 0.0, radius = 1.0, fixed = 'script',
    }
    syncPoints()
end
exports('RegisterBossMenu', registerBossMenu)

if Config.qbxManagementCompat and not qbxManagementRunning() then
    AddEventHandler('__cfx_export_qbx_management_RegisterBossMenu', function(setCB) setCB(registerBossMenu) end)
end

---------------------------------------------------------------------------
-- Daily withdrawal limit per rank (jobs[x].withdrawLimits = { [grade] = amount }). nil = no limit.
-- Counts withdrawals and bonuses paid today by this player. Admins aren't limited.
---------------------------------------------------------------------------
local function withdrawLeft(src, gtype, name)
    local c = groupCfg(gtype, name)
    if not c or type(c.withdrawLimits) ~= 'table' or isAdmin(src) then return nil end
    local grade = Bridge.GetPlayerGroupGrade(src, gtype, name)
    local limit = grade and c.withdrawLimits[grade]
    if not limit then return nil end
    local used = MySQL.scalar.await("SELECT COALESCE(SUM(amount), 0) FROM blaze_boss_fund_log WHERE job = ? AND citizenid = ? AND type IN ('withdraw','bonus') AND created_at >= CURDATE()",
        { gkey(gtype, name), Bridge.GetCitizenId(src) }) or 0
    return math.floor(limit - (tonumber(used) or 0))
end

-- Helpers for server/features.lua
BM.register, BM.groupCfg, BM.gkey, BM.appsOn, BM.fundsOn = register, groupCfg, gkey, appsOn, fundsOn
BM.isAdmin, BM.managerGrade, BM.actorLimit, BM.checkTarget = isAdmin, managerGrade, actorLimit, checkTarget
BM.notifyMember, BM.groupLabel, BM.gradeName, BM.cleanText, BM.cleanLong = notifyMember, groupLabel, gradeName, cleanText, cleanLong
BM.isOpen, BM.activityFor, BM.allPoints, BM.withdrawLeft = isOpen, activityFor, allPoints, withdrawLeft
BM.clockedIn = clockedIn

---------------------------------------------------------------------------
-- Start
---------------------------------------------------------------------------
CreateThread(function()
    createTables()
    loadData()
    initManagedGroups()
    if ACT.enabled then
        MySQL.query('DELETE FROM `player_jobs_activity` WHERE `last_checkout` < UNIX_TIMESTAMP(DATE_SUB(NOW(), INTERVAL ? DAY)) OR `last_checkout` IS NULL', { ACT.keepDays or 31 })
        -- people already on duty when the resource (re)starts
        for src, p in pairs(Bridge.GetPlayers() or {}) do
            if p.PlayerData.job and p.PlayerData.job.onduty then checkIn(src, p.PlayerData.citizenid, p.PlayerData.job.name) end
        end
    end
    for name in pairs(Config.jobs or {}) do
        if not Bridge.GroupExists('job', name) then print(('^3[blaze_bossmenu]^7 Job "%s" in config.lua does not exist in the framework.'):format(name)) end
    end
    for name in pairs(Config.gangs or {}) do
        if not Bridge.GroupExists('gang', name) then print(('^3[blaze_bossmenu]^7 Gang "%s" in config.lua does not exist in the framework.'):format(name)) end
    end
    if qbxManagementRunning() then
        print('^3[blaze_bossmenu]^7 qbx_management is also running. Stop it in server.cfg: blaze_bossmenu replaces it (duty hours and grade storage are paused until then).')
    end
    ready = true
    syncPoints()

    -- "Fully started" banner (server/version.lua), after the other startup lines so it isn't buried
    Wait(2000)
    local jobs, gangs = 0, 0
    for name in pairs(Config.jobs or {}) do if Bridge.GroupExists('job', name) then jobs = jobs + 1 end end
    for name in pairs(Config.gangs or {}) do if Bridge.GroupExists('gang', name) then gangs = gangs + 1 end end
    StartupBanner({ jobs = jobs, gangs = gangs, points = #allPoints() })
end)
