-- Framework bridge (server): Qbox (qbx_core) or QBCore. Nothing else in this resource talks to the framework.
-- Qbox is checked first because Qbox also provides a qb-core compatibility layer.
if not Config.enabled then return end

Bridge = {}

local function pick()
    if GetResourceState('qbx_core') ~= 'missing' then return 'qbx' end
    if GetResourceState('qb-core') ~= 'missing' then return 'qb' end
    error('blaze_bossmenu: no supported framework found (qbx_core or qb-core).')
end
Bridge.framework = pick()
local QBX = Bridge.framework == 'qbx'
local QBCore = not QBX and exports['qb-core']:GetCoreObject() or nil

---------------------------------------------------------------------------
-- Players
---------------------------------------------------------------------------
function Bridge.GetPlayer(src)
    if not src then return nil end
    if QBX then return exports.qbx_core:GetPlayer(src) end
    return QBCore.Functions.GetPlayer(src)
end

local function byCitizenId(cid)
    if QBX then return exports.qbx_core:GetPlayerByCitizenId(cid) end
    return QBCore.Functions.GetPlayerByCitizenId(cid)
end
Bridge.GetPlayerByCitizenId = byCitizenId

--- { [src] = player } for everyone online
function Bridge.GetPlayers()
    if QBX then return exports.qbx_core:GetQBPlayers() end
    return QBCore.Functions.GetQBPlayers()
end

function Bridge.GetCitizenId(src)
    local p = Bridge.GetPlayer(src)
    return p and p.PlayerData.citizenid or nil
end

local function charName(charinfo)
    if type(charinfo) == 'string' then charinfo = json.decode(charinfo) end
    if type(charinfo) ~= 'table' then return 'Unknown' end
    return ('%s %s'):format(charinfo.firstname or '?', charinfo.lastname or '?')
end

function Bridge.GetName(src)
    local p = Bridge.GetPlayer(src)
    return p and charName(p.PlayerData.charinfo) or ('ID %s'):format(src)
end

--- Primary job: { name, grade, isboss, onduty }
function Bridge.GetJob(src)
    local p = Bridge.GetPlayer(src)
    if not p then return nil end
    local j = p.PlayerData.job or {}
    return { name = j.name, grade = j.grade and j.grade.level or 0, isboss = j.isboss == true, onduty = j.onduty == true }
end

--- The player's grade in `job`, or nil if they don't have it.
-- Qbox supports several jobs at once (PlayerData.jobs); QBCore only the primary job.
function Bridge.GetPlayerJobGrade(src, job)
    local p = Bridge.GetPlayer(src)
    if not p then return nil end
    local pd = p.PlayerData
    if pd.job and pd.job.name == job then return pd.job.grade and pd.job.grade.level or 0 end
    if QBX and type(pd.jobs) == 'table' and pd.jobs[job] then return pd.jobs[job] end
    return nil
end

function Bridge.IsFrameworkAdmin(src)
    if QBX then return exports.qbx_core:HasPermission(src, 'admin') or exports.qbx_core:HasPermission(src, 'god') end
    return QBCore.Functions.HasPermission(src, 'admin') or QBCore.Functions.HasPermission(src, 'god')
end

---------------------------------------------------------------------------
-- Jobs and grades
---------------------------------------------------------------------------
local function sharedJob(job)
    if QBX then return exports.qbx_core:GetJob(job) end
    return QBCore.Shared.Jobs[job]
end

function Bridge.JobExists(job) return sharedJob(job) ~= nil end

--- Sorted list (lowest first) of { level, name, isboss }
function Bridge.GetJobGrades(job)
    local j = sharedJob(job)
    local out = {}
    if not j or not j.grades then return out end
    for k, g in pairs(j.grades) do
        local level = tonumber(k)
        if level then out[#out + 1] = { level = level, name = g.name or tostring(level), isboss = g.isboss == true } end
    end
    table.sort(out, function(a, b) return a.level < b.level end)
    return out
end

function Bridge.GetGrade(job, level)
    for _, g in ipairs(Bridge.GetJobGrades(job)) do if g.level == level then return g end end
end

--- Grade a citizen holds in `job` (online or offline), or nil
function Bridge.GetMemberGrade(cid, job)
    local p = byCitizenId(cid)
    if p then return Bridge.GetPlayerJobGrade(p.PlayerData.source, job) end
    if QBX then
        return MySQL.scalar.await('SELECT grade FROM player_groups WHERE citizenid = ? AND `group` = ? AND type = ?', { cid, job, 'job' })
    end
    local row = MySQL.scalar.await('SELECT job FROM players WHERE citizenid = ?', { cid })
    local j = row and json.decode(row)
    if j and j.name == job then return j.grade and j.grade.level or 0 end
    return nil
end

--- Everyone in a job, online and offline: { citizenid, name, grade, online, onduty, src }
function Bridge.GetJobMembers(job)
    local byCid = {}
    if QBX then
        local rows = exports.qbx_core:GetGroupMembers(job, 'job') or {}
        local cids = {}
        for _, r in ipairs(rows) do
            byCid[r.citizenid] = { citizenid = r.citizenid, grade = r.grade, name = 'Unknown', online = false, onduty = false }
            cids[#cids + 1] = r.citizenid
        end
        if #cids > 0 then
            local names = MySQL.query.await(('SELECT citizenid, charinfo FROM players WHERE citizenid IN (%s)'):format(('?,'):rep(#cids):sub(1, -2)), cids) or {}
            for _, n in ipairs(names) do if byCid[n.citizenid] then byCid[n.citizenid].name = charName(n.charinfo) end end
        end
    else
        local rows = MySQL.query.await("SELECT citizenid, charinfo, job FROM players WHERE JSON_UNQUOTE(JSON_EXTRACT(job, '$.name')) = ?", { job }) or {}
        for _, r in ipairs(rows) do
            local j = json.decode(r.job) or {}
            byCid[r.citizenid] = { citizenid = r.citizenid, grade = j.grade and j.grade.level or 0, name = charName(r.charinfo), online = false, onduty = false }
        end
    end
    -- Online data wins (the database can lag behind)
    for src, p in pairs(Bridge.GetPlayers() or {}) do
        local pd = p.PlayerData
        local grade = Bridge.GetPlayerJobGrade(src, job)
        if grade then
            byCid[pd.citizenid] = {
                citizenid = pd.citizenid, grade = grade, name = charName(pd.charinfo), online = true, src = src,
                onduty = pd.job and pd.job.name == job and pd.job.onduty == true or false,
            }
        elseif byCid[pd.citizenid] then
            byCid[pd.citizenid] = nil
        end
    end
    local out = {}
    for _, m in pairs(byCid) do out[#out + 1] = m end
    return out
end

--- Hire / promote / demote. Works online and offline.
function Bridge.SetJob(cid, job, grade)
    grade = tonumber(grade) or 0
    if QBX then
        local ok, err = exports.qbx_core:AddPlayerToJob(cid, job, grade)
        if not ok then return false, err and err.message end
        exports.qbx_core:SetPlayerPrimaryJob(cid, job)
        return true
    end
    local p = byCitizenId(cid)
    if p then
        return p.Functions.SetJob(job, grade) ~= false
    end
    local j = QBCore.Shared.Jobs[job]
    local g = j and j.grades[tostring(grade)]
    if not g then return false, 'Unknown grade' end
    local data = {
        name = job, label = j.label, payment = g.payment or 0, type = j.type, onduty = false,
        isboss = g.isboss == true, grade = { name = g.name, level = grade },
    }
    local n = MySQL.update.await('UPDATE players SET job = ? WHERE citizenid = ?', { json.encode(data), cid })
    return (n or 0) > 0
end

--- Fire: remove the job (unemployed on QBCore)
function Bridge.RemoveJob(cid, job)
    if QBX then
        local ok, err = exports.qbx_core:RemovePlayerFromJob(cid, job)
        return ok, err and err.message
    end
    local p = byCitizenId(cid)
    if p then return p.Functions.SetJob('unemployed', 0) ~= false end
    local j = QBCore.Shared.Jobs.unemployed
    local g = j and j.grades['0'] or { name = 'Freelancer', payment = 10 }
    local data = { name = 'unemployed', label = j and j.label or 'Civilian', payment = g.payment or 0, onduty = false, isboss = false, grade = { name = g.name, level = 0 } }
    local n = MySQL.update.await('UPDATE players SET job = ? WHERE citizenid = ?', { json.encode(data), cid })
    return (n or 0) > 0
end

--- Callsign into player metadata when online (our own table is the source of truth)
function Bridge.SetCallsign(cid, callsign)
    local p = byCitizenId(cid)
    if p then p.Functions.SetMetaData('callsign', callsign) end
end

---------------------------------------------------------------------------
-- Cash
---------------------------------------------------------------------------
function Bridge.GetCash(src)
    local p = Bridge.GetPlayer(src)
    return p and (p.PlayerData.money and p.PlayerData.money.cash) or 0
end

function Bridge.AddCash(src, amount, reason)
    local p = Bridge.GetPlayer(src)
    return p and p.Functions.AddMoney('cash', amount, reason or 'blaze_bossmenu') ~= false or false
end

function Bridge.RemoveCash(src, amount, reason)
    local p = Bridge.GetPlayer(src)
    if not p or Bridge.GetCash(src) < amount then return false end
    return p.Functions.RemoveMoney('cash', amount, reason or 'blaze_bossmenu') ~= false
end

function Bridge.Notify(src, description, ntype)
    TriggerClientEvent('ox_lib:notify', src, { title = 'Management', description = description, type = ntype or 'inform' })
end
