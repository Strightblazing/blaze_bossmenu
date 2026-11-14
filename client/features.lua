-- Client extras: profiles, /myjob, /jobs board, announcements, celebrations, hire handshake, receptionist NPC.
-- Loaded before client/main.lua, which uses BMC.* for the profile and points.
if not Config.enabled then return end

local RES = GetCurrentResourceName()
local F = Config.features or {}
local function call(name, ...) return lib.callback.await(('%s:%s'):format(RES, name), false, ...) end
local function notify(msg, ntype, title) lib.notify({ title = title or 'Management', description = msg, type = ntype or 'inform' }) end

BMC = {}

---------------------------------------------------------------------------
-- Profiles
---------------------------------------------------------------------------
local RECORD_ICON = { commend = 'fa-solid fa-award', warning = 'fa-solid fa-triangle-exclamation', rank = 'fa-solid fa-ranking-star', eotw = 'fa-solid fa-star', contract = 'fa-solid fa-file-signature' }
local RECORD_COLOR = { commend = '#3DDC84', warning = '#E5484D', rank = '#5AA9FF', eotw = '#F5C542', contract = '#A78BFA' }
local RECORD_LABEL = { commend = 'Commendation', warning = 'Write-up', rank = 'Rank', eotw = 'Employee of the Week', contract = 'Contract' }

--- Menu options for a profile (shared by the staff list and /myjob)
function BMC.profileOptions(p)
    local o = {}
    o[#o + 1] = { title = p.name .. (p.eotw and '  ⭐' or ''), description = ('%s · %s%s'):format(p.group, p.gradeName, p.callsign and (' · ' .. p.callsign) or ''),
        icon = 'fa-solid fa-id-badge', readOnly = true }
    if p.eotw then o[#o + 1] = { title = 'Employee of the Week', icon = 'fa-solid fa-star', iconColor = '#F5C542', readOnly = true } end
    o[#o + 1] = { title = 'Hired', description = p.hiredAt or 'Before records began', icon = 'fa-regular fa-calendar', readOnly = true }
    if p.probationUntil then
        o[#o + 1] = { title = 'On probation', description = 'Until ' .. p.probationUntil, icon = 'fa-solid fa-hourglass-half', iconColor = '#F0A93B', readOnly = true }
    end
    if p.gtype == 'job' then
        o[#o + 1] = { title = 'Hours on duty', description = ('%s this week · %s in the last %d days'):format(p.hoursWeek or 0, p.hours or 0, (Config.activity and Config.activity.keepDays) or 31),
            icon = 'fa-solid fa-clock', readOnly = true, progress = math.min(100, math.floor(((p.hoursWeek or 0) / 40) * 100)) }
        o[#o + 1] = { title = 'Last check-in', description = p.lastCheckin or 'N/A', icon = 'fa-solid fa-right-to-bracket', readOnly = true }
    end
    if p.records then
        o[#o + 1] = { title = 'Record', description = ('%d commendation%s · %d write-up%s'):format(p.commendations or 0, p.commendations == 1 and '' or 's', p.warnings or 0, p.warnings == 1 and '' or 's'),
            icon = 'fa-solid fa-folder-open', readOnly = true }
        for _, r in ipairs(p.records) do
            local text = r.text or ''
            o[#o + 1] = {
                title = ('%s · %s'):format(RECORD_LABEL[r.type] or r.type, r.at or ''),
                description = (#text > 70 and (text:sub(1, 69) .. '…') or text) .. (r.by_name and (' · by ' .. r.by_name) or ''),
                icon = RECORD_ICON[r.type] or 'fa-solid fa-file', iconColor = RECORD_COLOR[r.type], readOnly = true,
                metadata = #text > 70 and { { label = 'Details', value = text } } or nil,
            }
        end
    end
    return o
end

function BMC.openProfile(gtype, name, cid, backMenu)
    local p = call('getProfile', gtype, name, cid)
    if not p then return notify('Profile not found.', 'error') end
    UI.registerMenu({ id = 'blaze_boss_profile', title = 'Profile · ' .. p.name, menu = backMenu, options = BMC.profileOptions(p) })
    UI.showMenu('blaze_boss_profile')
end

---------------------------------------------------------------------------
-- /myjob
---------------------------------------------------------------------------
local function showMine(p, backMenu)
    local options = {}
    if p.announcement then
        options[#options + 1] = { title = '📢 Announcement', description = (#p.announcement.message > 80 and (p.announcement.message:sub(1, 79) .. '…') or p.announcement.message),
            icon = 'fa-solid fa-bullhorn', iconColor = '#A78BFA', readOnly = true,
            metadata = { { label = 'From', value = p.announcement.by_name or '?' }, { label = 'Posted', value = p.announcement.at or '' }, { label = 'Message', value = p.announcement.message } } }
    end
    for _, o in ipairs(BMC.profileOptions(p)) do options[#options + 1] = o end
    UI.registerMenu({ id = 'blaze_boss_myjob', title = 'My job · ' .. p.group, menu = backMenu, options = options })
    UI.showMenu('blaze_boss_myjob')
end

local function openMyJob()
    local list = call('getMyJob') or {}
    if #list == 0 then return notify('You don\'t work for a department that uses this menu.', 'inform', 'My job') end
    if #list == 1 then return showMine(list[1]) end
    local options = {}
    for _, p in ipairs(list) do
        options[#options + 1] = { title = p.group, description = p.gradeName, icon = p.gtype == 'gang' and 'fa-solid fa-users-rectangle' or 'fa-solid fa-briefcase',
            arrow = true, onSelect = function() showMine(p, 'blaze_boss_myjobs') end }
    end
    UI.registerMenu({ id = 'blaze_boss_myjobs', title = 'My jobs', options = options })
    UI.showMenu('blaze_boss_myjobs')
end
BMC.openMyJob = openMyJob

if F.profiles and F.myJobCommand then
    RegisterCommand(F.myJobCommand, openMyJob, false)
    TriggerEvent('chat:addSuggestion', '/' .. F.myJobCommand, 'Your job profile, record and department announcement')
end

---------------------------------------------------------------------------
-- /jobs: "Now hiring" board
---------------------------------------------------------------------------
local function nearest(points)
    local me, best, bestD = GetEntityCoords(cache.ped), nil, nil
    for _, c in ipairs(points or {}) do
        local d = #(me - vec3(c.x, c.y, c.z))
        if not bestD or d < bestD then best, bestD = c, d end
    end
    return best, bestD
end

local function openJobBoard()
    local list = call('getJobBoard') or {}
    local options = {}
    for _, j in ipairs(list) do
        local spot, dist = nearest(j.points)
        options[#options + 1] = {
            title = j.label, icon = j.open and 'fa-solid fa-door-open' or 'fa-solid fa-door-closed', iconColor = j.open and '#3DDC84' or '#8F99A5',
            description = (j.open and 'Hiring' or 'Not hiring right now') .. (spot and (' · %dm away'):format(math.floor(dist)) or ''),
            metadata = j.description and { { label = 'About', value = j.description } } or nil,
            disabled = not spot,
            onSelect = function()
                SetNewWaypoint(spot.x, spot.y)
                notify(('Waypoint set to the %s application point.'):format(j.label), 'success', 'Now hiring')
            end,
        }
    end
    if #options == 0 then options[1] = { title = 'Nobody is hiring right now', readOnly = true } end
    UI.registerMenu({ id = 'blaze_boss_jobboard', title = 'Now hiring', options = options })
    UI.showMenu('blaze_boss_jobboard')
end

if Config.applications.enabled and F.jobBoardCommand then
    RegisterCommand(F.jobBoardCommand, openJobBoard, false)
    TriggerEvent('chat:addSuggestion', '/' .. F.jobBoardCommand, 'See which jobs are hiring and where to apply')
end

---------------------------------------------------------------------------
-- Employment contract (Config.contract): read it, sign with your full name, little writing animation
---------------------------------------------------------------------------
local function plainName(s)
    return (tostring(s or ''):lower():gsub('[^%w%s%-\']', ''):gsub('%s+', ' '):gsub('^%s', ''):gsub('%s$', ''))
end

local function contractText(offer)
    local lines = {
        ('**%s** is offering you a position with **%s**.'):format(offer.from or 'Management', offer.group or '?'),
        '',
        ('- **Position:** %s'):format(offer.rank or '?'),
    }
    if offer.pay then lines[#lines + 1] = ('- **Pay:** $%s per paycheck'):format(math.floor(offer.pay)) end
    if offer.probationDays then lines[#lines + 1] = ('- **Probation:** %d days'):format(offer.probationDays) end
    lines[#lines + 1] = ('- **Date:** %s'):format(offer.date or '')
    if offer.terms and #offer.terms > 0 then
        lines[#lines + 1] = ''
        lines[#lines + 1] = '**Terms of employment**'
        for i, t in ipairs(offer.terms) do lines[#lines + 1] = ('%d. %s'):format(i, t) end
    end
    lines[#lines + 1] = ''
    lines[#lines + 1] = '_By signing you accept this position and agree to the terms above._'
    return table.concat(lines, '\n')
end

--- Returns { accepted = bool, signature = string? }. preview = true never sends anything (test menu).
function BMC.signContract(offer, seconds)
    local C = Config.contract or {}
    local timedOut, open = false, true
    SetTimeout((seconds or 90) * 1000, function()
        if not open then return end
        timedOut = true
        UI.closeConfirm()
        UI.closeInput()
    end)

    -- pen and notepad while reading and signing
    local animating = C.animation ~= false and not IsPedInAnyVehicle(cache.ped, false)
    if animating then TaskStartScenarioInPlace(cache.ped, 'CODE_HUMAN_MEDIC_TIME_OF_DEATH', 0, true) end
    local function finish(res)
        open = false
        if animating then ClearPedTasks(cache.ped) end
        return res
    end

    if not UI.confirm({ header = '📝 Employment Contract', content = contractText(offer), type = 'info', icon = 'fa-solid fa-file-signature',
            confirm = 'Sign contract', cancel = 'Decline' }) or timedOut then
        return finish({ accepted = false })
    end

    local expected = offer.expectedName or ''
    for _ = 1, 3 do
        local v = UI.input('Sign the contract', {
            { type = 'input', label = 'Signature', description = ('Sign with your full name: %s'):format(expected), placeholder = expected, required = true, maxLength = 60 },
            { type = 'checkbox', label = 'I have read and agree to the terms', required = true },
        }, { submitText = 'Sign' })
        if not v or timedOut then return finish({ accepted = false }) end
        if not v[2] then
            notify('Tick the box to agree to the terms.', 'error', 'Contract')
        elseif C.requireExactName ~= false and plainName(v[1]) ~= plainName(expected) then
            notify(('That\'s not your name. Sign as "%s".'):format(expected), 'error', 'Contract')
        else
            PlaySoundFrontend(-1, 'PICK_UP', 'HUD_FRONTEND_DEFAULT_SOUNDSET', true)
            if animating then Wait(1500) end -- finish the last pen stroke
            return finish({ accepted = true, signature = v[1] })
        end
    end
    notify('Contract not signed.', 'error', 'Contract')
    return finish({ accepted = false })
end

---------------------------------------------------------------------------
-- Announcements
---------------------------------------------------------------------------
RegisterNetEvent(RES .. ':client:announcement', function(groupLabel, message, by)
    PlaySoundFrontend(-1, 'Text_Arrive_Tone', 'Phone_SoundSet_Default', false)
    lib.notify({ title = ('📢 %s announcement'):format(groupLabel), description = ('%s\n— %s'):format(message, by or 'Management'), type = 'inform', duration = 15000 })
end)

---------------------------------------------------------------------------
-- Celebrations: big centre-screen message + sound
---------------------------------------------------------------------------
local celebrating = false
RegisterNetEvent(RES .. ':client:celebrate', function(title, text)
    if not F.celebrations or celebrating then return end
    celebrating = true
    CreateThread(function()
        local sf = RequestScaleformMovie('MIDSIZED_MESSAGE')
        local t = GetGameTimer() + 3000
        while not HasScaleformMovieLoaded(sf) and GetGameTimer() < t do Wait(0) end
        if HasScaleformMovieLoaded(sf) then
            BeginScaleformMovieMethod(sf, 'SHOW_SHARD_MIDSIZED_MESSAGE')
            ScaleformMovieMethodAddParamTextureNameString(title or '')
            ScaleformMovieMethodAddParamTextureNameString(text or '')
            ScaleformMovieMethodAddParamInt(2) -- gold
            EndScaleformMovieMethod()
            PlaySoundFrontend(-1, 'RANK_UP', 'HUD_AWARDS', true)
            local untilT = GetGameTimer() + 5000
            while GetGameTimer() < untilT do
                DrawScaleformMovieFullscreen(sf, 255, 255, 255, 255, 0)
                Wait(0)
            end
            SetScaleformMovieAsNoLongerNeeded(sf)
        end
        celebrating = false
    end)
end)

---------------------------------------------------------------------------
-- Hire handshake
---------------------------------------------------------------------------
RegisterNetEvent(RES .. ':client:handshake', function(partnerServerId, role)
    if not F.handshake then return end
    local player = GetPlayerFromServerId(partnerServerId)
    if player == -1 then return end
    local other = GetPlayerPed(player)
    if not DoesEntityExist(other) or #(GetEntityCoords(cache.ped) - GetEntityCoords(other)) > 4.0 or IsPedInAnyVehicle(cache.ped, false) then return end
    TaskTurnPedToFaceEntity(cache.ped, other, 1200)
    Wait(1200)
    if not lib.requestAnimDict('mp_ped_interaction', 3000) then return end
    TaskPlayAnim(cache.ped, 'mp_ped_interaction', role == 'a' and 'handshake_guy_a' or 'handshake_guy_b', 8.0, -8.0, 3500, 0, 0.0, false, false, false)
    RemoveAnimDict('mp_ped_interaction')
end)

---------------------------------------------------------------------------
-- Receptionist NPC at applications points (client-side only, spawned when you're near)
---------------------------------------------------------------------------
local R = F.receptionist or {}
local pedPoints = {}

local function clearReceptionists()
    for _, p in ipairs(pedPoints) do
        if p.ped and DoesEntityExist(p.ped) then DeleteEntity(p.ped) end
        p:remove()
    end
    pedPoints = {}
end

--- Stands ~0.8 m behind the point (the other side of the counter from the admin who placed it), facing them
local function spawnReceptionist(point)
    local h = (point.heading or 0.0)
    local rad = math.rad(h)
    local x = point.coords.x - math.sin(rad) * 0.8
    local y = point.coords.y + math.cos(rad) * 0.8
    local found, groundZ = GetGroundZFor_3dCoord(x, y, point.coords.z + 1.0, false)
    local z = found and groundZ or (point.coords.z - 1.0)
    local model = joaat(R.model or 'a_f_y_business_02')
    if not lib.requestModel(model, 5000) then return nil end
    local ped = CreatePed(4, model, x, y, z, (h + 180.0) % 360.0, false, false)
    SetModelAsNoLongerNeeded(model)
    SetEntityInvincible(ped, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    FreezeEntityPosition(ped, true)
    SetPedCanRagdoll(ped, false)
    if R.scenario then TaskStartScenarioInPlace(ped, R.scenario, 0, true) end
    return ped
end

function BMC.onPoints(points)
    clearReceptionists()
    if not R.enabled then return end
    for _, p in ipairs(points or {}) do
        if p.type == 'applications' then
            local lastGreet = 0
            local point = lib.points.new({ coords = vec3(p.coords.x, p.coords.y, p.coords.z), distance = 40.0 })
            function point:onEnter() if not self.ped then self.ped = spawnReceptionist(p) end end
            function point:onExit() if self.ped and DoesEntityExist(self.ped) then DeleteEntity(self.ped) end self.ped = nil end
            function point:nearby()
                if R.greet and self.ped and self.currentDistance < 2.5 and GetGameTimer() - lastGreet > 60000 then
                    lastGreet = GetGameTimer()
                    PlayPedAmbientSpeechNative(self.ped, 'GENERIC_HI', 'SPEECH_PARAMS_FORCE_NORMAL')
                end
            end
            pedPoints[#pedPoints + 1] = point
        end
    end
end

AddEventHandler('onResourceStop', function(res) if res == RES then clearReceptionists() end end)
