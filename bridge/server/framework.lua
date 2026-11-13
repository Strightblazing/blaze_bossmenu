-- Framework bridge (server): Qbox (qbx_core) or QBCore. Nothing else in this resource talks to the framework.
-- Group functions take a group type: 'job' or 'gang'.
-- Based on the group handling in qbx_management (Qbox Project, GPL-3.0); QBCore support added.
if not Config.enabled then return end

Bridge = {}

local function pick()
    if GetResourceState('qbx_core') ~= 'missing' then return 'qbx' end -- first: Qbox also provides qb-core
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
    if not cid then return nil end
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
Bridge.CharName = charName

function Bridge.GetName(src)
    local p = Bridge.GetPlayer(src)
    return p and charName(p.PlayerData.charinfo) or ('ID %s'):format(src)
end

--- Name for a citizenid, online or offline
function Bridge.GetNameByCitizenId(cid)
    local p = byCitizenId(cid)
    if p then return charName(p.PlayerData.charinfo) end
    return charName(MySQL.scalar.await('SELECT charinfo FROM players WHERE citizenid = ?', { cid }))
end

--- Primary job: { name, grade, isboss, onduty }
function Bridge.GetJob(src)
    local p = Bridge.GetPlayer(src)
    if not p then return nil end
    local j = p.PlayerData.job or {}
    return { name = j.name, grade = j.grade and j.grade.level or 0, isboss = j.isboss == true, onduty = j.onduty == true }
end

--- The player's grade in a job/gang, or nil if they don't have it.
-- Qbox supports several groups at once (PlayerData.jobs / gangs); QBCore only the primary one.
function Bridge.GetPlayerGroupGrade(src, gtype, name)
    local p = Bridge.GetPlayer(src)
    if not p then return nil end
    local pd = p.PlayerData
    local primary = pd[gtype]
    if primary and primary.name == name then return primary.grade and primary.grade.level or 0 end
    local list = QBX and pd[gtype .. 's']
    if type(list) == 'table' and list[name] then return list[name] end
    return nil
end

function Bridge.IsFrameworkAdmin(src)
    if QBX then return exports.qbx_core:HasPermission(src, 'admin') or exports.qbx_core:HasPermission(src, 'god') end
    return QBCore.Functions.HasPermission(src, 'admin') or QBCore.Functions.HasPermission(src, 'god')
end

---------------------------------------------------------------------------
-- Groups and grades
---------------------------------------------------------------------------
local function sharedGroup(gtype, name)
    if QBX then
        if gtype == 'gang' then return exports.qbx_core:GetGang(name) end
        return exports.qbx_core:GetJob(name)
    end
    return (gtype == 'gang' and QBCore.Shared.Gangs or QBCore.Shared.Jobs)[name]
end
Bridge.GetGroup = sharedGroup

function Bridge.GroupExists(gtype, name) return sharedGroup(gtype, name) ~= nil end

--- Sorted list (lowest first) of { level, name, isboss, payment, bankAuth }
function Bridge.GetGrades(gtype, name)
    local g = sharedGroup(gtype, name)
    local out = {}
    if not g or not g.grades then return out end
    for k, v in pairs(g.grades) do
        local level = tonumber(k)
        if level then
            out[#out + 1] = { level = level, name = v.name or tostring(level), isboss = v.isboss == true, payment = v.payment, bankAuth = v.bankAuth == true }
        end
    end
    table.sort(out, function(a, b) return a.level < b.level end)
    return out
end

function Bridge.GetGrade(gtype, name, level)
    for _, g in ipairs(Bridge.GetGrades(gtype, name)) do if g.level == level then return g end end
end

--- Grade a citizen holds in a group (online or offline), or nil
function Bridge.GetMemberGrade(cid, gtype, name)
    local p = byCitizenId(cid)
    if p then return Bridge.GetPlayerGroupGrade(p.PlayerData.source, gtype, name) end
    if QBX then
        return MySQL.scalar.await('SELECT grade FROM player_groups WHERE citizenid = ? AND `group` = ? AND type = ?', { cid, name, gtype })
    end
    local row = MySQL.scalar.await(('SELECT %s FROM players WHERE citizenid = ?'):format(gtype == 'gang' and 'gang' or 'job'), { cid })
    local j = row and json.decode(row)
    if j and j.name == name then return j.grade and j.grade.level or 0 end
    return nil
end

--- Everyone in a group, online and offline: { citizenid, name, grade, online, onduty, src }
function Bridge.GetMembers(gtype, name)
    local byCid = {}
    if QBX then
        local rows = exports.qbx_core:GetGroupMembers(name, gtype) or {}
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
        local col = gtype == 'gang' and 'gang' or 'job'
        local rows = MySQL.query.await(("SELECT citizenid, charinfo, %s AS grp FROM players WHERE JSON_UNQUOTE(JSON_EXTRACT(%s, '$.name')) = ?"):format(col, col), { name }) or {}
        for _, r in ipairs(rows) do
            local j = json.decode(r.grp) or {}
            byCid[r.citizenid] = { citizenid = r.citizenid, grade = j.grade and j.grade.level or 0, name = charName(r.charinfo), online = false, onduty = false }
        end
    end
    -- Online data wins (the database can lag behind)
    for src, p in pairs(Bridge.GetPlayers() or {}) do
        local pd = p.PlayerData
        local grade = Bridge.GetPlayerGroupGrade(src, gtype, name)
        if grade then
            byCid[pd.citizenid] = {
                citizenid = pd.citizenid, grade = grade, name = charName(pd.charinfo), online = true, src = src,
                onduty = gtype == 'job' and pd.job and pd.job.name == name and pd.job.onduty == true or false,
            }
        elseif byCid[pd.citizenid] then
            byCid[pd.citizenid] = nil
        end
    end
    local out = {}
    for _, m in pairs(byCid) do out[#out + 1] = m end
    return out
end

local function qbOfflineSet(gtype, cid, name, grade)
    local shared = (gtype == 'gang' and QBCore.Shared.Gangs or QBCore.Shared.Jobs)[name]
    local g = shared and shared.grades[tostring(grade)]
    if not g then return false, 'Unknown grade' end
    local data = { name = name, label = shared.label, isboss = g.isboss == true, grade = { name = g.name, level = grade } }
    if gtype == 'job' then data.payment = g.payment or 0; data.type = shared.type; data.onduty = false end
    local n = MySQL.update.await(('UPDATE players SET %s = ? WHERE citizenid = ?'):format(gtype == 'gang' and 'gang' or 'job'), { json.encode(data), cid })
    return (n or 0) > 0
end

--- Hire into a group (becomes their primary job/gang). Online and offline.
-- Qbox: uses SetJob/SetGang so qbx:max_jobs_per_player and qbx:setjob_replaces are respected.
function Bridge.SetGroup(cid, gtype, name, grade)
    grade = tonumber(grade) or 0
    if QBX then
        local ok, err
        if gtype == 'gang' then ok, err = exports.qbx_core:SetGang(cid, name, grade)
        else ok, err = exports.qbx_core:SetJob(cid, name, grade) end
        return ok ~= false, type(err) == 'table' and err.message or nil
    end
    local p = byCitizenId(cid)
    if p then
        local ok = gtype == 'gang' and p.Functions.SetGang(name, grade) or p.Functions.SetJob(name, grade)
        return ok ~= false
    end
    return qbOfflineSet(gtype, cid, name, grade)
end

--- Change the grade of someone already in the group (promote / demote)
function Bridge.SetGrade(cid, gtype, name, grade)
    grade = tonumber(grade) or 0
    if QBX then
        local ok, err
        if gtype == 'gang' then ok, err = exports.qbx_core:AddPlayerToGang(cid, name, grade)
        else ok, err = exports.qbx_core:AddPlayerToJob(cid, name, grade) end
        return ok ~= false, type(err) == 'table' and err.message or nil
    end
    return Bridge.SetGroup(cid, gtype, name, grade)
end

--- Fire / kick from the group (unemployed / no gang)
function Bridge.RemoveGroup(cid, gtype, name)
    if QBX then
        local ok, err
        if gtype == 'gang' then ok, err = exports.qbx_core:RemovePlayerFromGang(cid, name)
        else ok, err = exports.qbx_core:RemovePlayerFromJob(cid, name) end
        return ok ~= false, type(err) == 'table' and err.message or nil
    end
    local none = gtype == 'gang' and 'none' or 'unemployed'
    local p = byCitizenId(cid)
    if p then
        local ok = gtype == 'gang' and p.Functions.SetGang(none, 0) or p.Functions.SetJob(none, 0)
        return ok ~= false
    end
    return qbOfflineSet(gtype, cid, none, 0)
end

--- Callsign into player metadata when online (our own table is the source of truth)
function Bridge.SetCallsign(cid, callsign)
    local p = byCitizenId(cid)
    if p then p.Functions.SetMetaData('callsign', callsign) end
end

---------------------------------------------------------------------------
-- Grade editor (Qbox only, like qbx_management)
---------------------------------------------------------------------------
Bridge.canEditGrades = QBX

function Bridge.UpsertGrade(gtype, name, level, data)
    if not QBX then return false end
    if gtype == 'gang' then exports.qbx_core:UpsertGangGrade(name, level, data)
    else exports.qbx_core:UpsertJobGrade(name, level, data) end
    return true
end

function Bridge.LoadManagedGroups(jobs, gangs)
    if not QBX then return end
    if next(jobs) then exports.qbx_core:CreateJobs(jobs) end
    if next(gangs) then exports.qbx_core:CreateGangs(gangs) end
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

function Bridge.Notify(src, description, ntype, title)
    TriggerClientEvent('ox_lib:notify', src, { title = title or 'Management', description = description, type = ntype or 'inform' })
end
