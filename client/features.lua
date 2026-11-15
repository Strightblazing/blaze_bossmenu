-- blaze_bossmenu | GNU GPL v3 (see LICENSE) | based on qbx_management by the Qbox Project (see NOTICE.md)
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
    o[#o + 1] = { title = p.name, description = ('%s · %s%s'):format(p.group, p.gradeName, p.callsign and (' · ' .. p.callsign) or ''),
        icon = 'fa-solid fa-id-badge', readOnly = true }
    if p.eotw then o[#o + 1] = { title = 'Employee of the Week', icon = 'fa-solid fa-star', iconColor = '#F5C542', readOnly = true } end
    o[#o + 1] = { title = 'Hired', description = p.hiredAt or 'Before records began', icon = 'fa-regular fa-calendar', readOnly = true }
    if p.phone then o[#o + 1] = { title = 'Phone', description = p.phone, icon = 'fa-solid fa-phone', readOnly = true } end
    if p.email then o[#o + 1] = { title = 'Email', description = p.email, icon = 'fa-solid fa-envelope', readOnly = true } end
    if p.probationUntil then
        o[#o + 1] = { title = 'On probation', description = 'Until ' .. p.probationUntil, icon = 'fa-solid fa-hourglass-half', iconColor = '#F0A93B', readOnly = true }
    end
    if p.gtype == 'job' then
        o[#o + 1] = { title = 'Hours on duty', description = ('%s this week · %s in the last %d days'):format(p.hoursWeek or 0, p.hours or 0, (Config.activity and Config.activity.keepDays) or 31),
            icon = 'fa-solid fa-clock', readOnly = true, progress = math.min(100, math.floor(((p.hoursWeek or 0) / 40) * 100)) }
        o[#o + 1] = { title = 'Last check-in', description = p.lastCheckin or 'N/A', icon = 'fa-solid fa-right-to-bracket', readOnly = true }
    end
    for _, c in ipairs(p.contracts or {}) do
        o[#o + 1] = { title = 'View employment contract', description = ('No. %s · signed %s'):format(c.number or c.id, c.at or ''),
            icon = 'fa-solid fa-file-contract', iconColor = '#A78BFA', arrow = true, onSelect = function() BMC.viewContract(c.id) end }
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
        options[#options + 1] = { title = 'Announcement', description = (#p.announcement.message > 80 and (p.announcement.message:sub(1, 79) .. '…') or p.announcement.message),
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
                if not spot then return end
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

--- Fill {placeholders} (job, rank, pay, probation, employee, manager, manager_rank, date, number)
local function fill(text, v, bold)
    return (tostring(text or ''):gsub('{([%w_]+)}', function(k)
        local val = v[k]
        if val == nil or val == '' then return '{' .. k .. '}' end
        return bold and ('**' .. tostring(val) .. '**') or tostring(val)
    end))
end
BMC.fillContract = fill

--- Typed style: the template as markdown for the confirm popup. Sections using {pay}/{probation} drop out when they don't apply.
local function contractText(offer)
    local t, v = offer.template or {}, offer.values or {}
    local lines = { ('**%s** · No. %s · %s'):format(fill(t.title or 'Employment Agreement', v), v.number or '', v.date or '') }
    if t.intro and t.intro ~= '' then lines[#lines + 1] = '' lines[#lines + 1] = '_' .. fill(t.intro, v) .. '_' end
    local n = 0
    for _, s in ipairs(t.sections or {}) do
        local text = s.text or ''
        if not ((text:find('{pay}', 1, true) and not v.pay) or (text:find('{probation}', 1, true) and not v.probation)) then
            n = n + 1
            lines[#lines + 1] = ''
            lines[#lines + 1] = ('**%d. %s**'):format(n, s.title or '')
            local i = 0
            for line in (text .. '\n'):gmatch('(.-)\n') do
                local item = line:match('^%s*[-*•]%s*(.+)')
                if item then i = i + 1 lines[#lines + 1] = ('%d. %s'):format(i, fill(item, v, true))
                elseif line:match('%S') then lines[#lines + 1] = fill(line, v, true) end
            end
        end
    end
    return table.concat(lines, '\n')
end

---------------------------------------------------------------------------
-- Paper contract page (web/contract.html): signed with the mouse
---------------------------------------------------------------------------
local nuiPending -- promise while the page is open

--- mode 'sign' | 'view' | 'preview'. Returns what the page sent back ({ accepted, image } / { closed = true }).
local function openPaper(mode, payload, seconds)
    if nuiPending then return { accepted = false } end
    local p = promise.new()
    nuiPending = p
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'openContract', mode = mode, offer = payload, seconds = seconds })
    if seconds then
        SetTimeout((seconds + 2) * 1000, function()
            if nuiPending ~= p then return end
            nuiPending = nil
            SendNUIMessage({ action = 'closeContract' })
            SetNuiFocus(false, false)
            p:resolve({ accepted = false, expired = true })
        end)
    end
    return Citizen.Await(p)
end

local function nuiDone(data, cb)
    cb(1)
    local p = nuiPending
    if not p then return end
    nuiPending = nil
    SetNuiFocus(false, false)
    p:resolve(data or {})
end
RegisterNUICallback('contract:result', nuiDone)
RegisterNUICallback('contract:closed', function(_, cb) nuiDone({ closed = true }, cb) end)

AddEventHandler('onResourceStop', function(res)
    if res == RES and nuiPending then SetNuiFocus(false, false) end
end)

--- A signed copy, from the profile or /myjob
function BMC.viewContract(id)
    local c = call('getContract', id)
    if not c then return notify('Contract not found.', 'error', 'Contract') end
    openPaper('view', c)
end

--- Template preview (contract editor / test menu): nothing to sign
function BMC.previewContract(template, values)
    openPaper('preview', { template = template, values = values })
end

---------------------------------------------------------------------------
-- Contract editor (boss menu): title, intro and sections with {placeholders}. A draft until saved.
---------------------------------------------------------------------------
local PLACEHOLDERS = {
    { '{job}', 'Job / gang name (e.g. EMS)' }, { '{rank}', 'Rank they are hired as' }, { '{pay}', 'Pay per paycheck (section hidden if none)' },
    { '{probation}', 'Probation length (section hidden if off)' }, { '{employee}', 'New hire\'s name' }, { '{manager}', 'Who is hiring' },
    { '{manager_rank}', 'Their rank (e.g. Chief)' }, { '{date}', 'Today' }, { '{number}', 'Contract number' },
}

local function short(s, n) s = tostring(s or ''):gsub('\n', ' ') return #s > n and (s:sub(1, n - 1) .. '…') or s end

function BMC.openContractEditor(m)
    local d = call('getContractTemplate', m.gtype, m.name)
    if not d then return notify('You can\'t edit this contract.', 'error', 'Contract') end
    local draft = lib.table.deepclone(d.template)
    draft.sections = draft.sections or {}
    local dirty = false
    local show

    local function sectionDialog(sec)
        local v = UI.input(sec and 'Edit section' or 'Add section', {
            { type = 'input', label = 'Section title', required = true, minLength = 1, maxLength = 60, default = sec and sec.title },
            { type = 'textarea', label = 'Text', required = true, minLength = 1, maxLength = 1500, default = sec and sec.text,
              description = 'Use {job}, {rank}, {pay}, {probation}, {employee}, {manager}, {manager_rank}, {date}. Lines starting with - become a numbered list.' },
        })
        if v and v[1] and v[2] then return { title = v[1], text = v[2] } end
    end

    local function leave()
        CreateThread(function()
            if dirty and not UI.confirm({ header = 'Discard changes?', content = 'You have unsaved changes to this contract. Discard them?', type = 'warning', confirm = 'Discard', cancel = 'Keep editing' }) then
                return show()
            end
            UI.showMenu('blaze_boss_main')
        end)
    end

    local function openSection(i)
        local s = draft.sections[i]
        UI.registerMenu({ id = 'blaze_boss_contract_sec', title = ('%d. %s'):format(i, short(s.title, 40)), menu = 'blaze_boss_contract', options = {
            { title = 'Edit', icon = 'fa-solid fa-pen', description = short(s.text, 80), onSelect = function()
                local ns = sectionDialog(s)
                if ns then draft.sections[i] = ns dirty = true end
                show()
            end },
            { title = 'Move up', icon = 'fa-solid fa-arrow-up', disabled = i == 1, onSelect = function()
                draft.sections[i], draft.sections[i - 1] = draft.sections[i - 1], draft.sections[i] dirty = true show()
            end },
            { title = 'Move down', icon = 'fa-solid fa-arrow-down', disabled = i == #draft.sections, onSelect = function()
                draft.sections[i], draft.sections[i + 1] = draft.sections[i + 1], draft.sections[i] dirty = true show()
            end },
            { title = 'Delete', icon = 'fa-solid fa-trash', iconColor = '#E5484D', disabled = #draft.sections <= 1, onSelect = function()
                if UI.confirm({ header = 'Delete section', content = ('Delete "%s"?'):format(s.title), type = 'error', confirm = 'Delete' }) then
                    table.remove(draft.sections, i) dirty = true
                end
                show()
            end },
        } })
        UI.showMenu('blaze_boss_contract_sec')
    end

    show = function()
        local help = {}
        for _, p in ipairs(PLACEHOLDERS) do help[#help + 1] = { label = p[1], value = p[2] } end
        local options = {
            { title = 'Back to boss menu', icon = 'fa-solid fa-angle-left', onSelect = leave },
            { title = 'Placeholders', icon = 'fa-solid fa-circle-info', readOnly = true, metadata = help,
              description = 'Filled in automatically: {job}, {rank}, {pay}, {manager}, {manager_rank}…' },
            { title = 'Title: ' .. (draft.title or ''), icon = 'fa-solid fa-heading', onSelect = function()
                local v = UI.input('Contract title', { { type = 'input', label = 'Title', required = true, minLength = 1, maxLength = 60, default = draft.title } })
                if v and v[1] then draft.title = v[1] dirty = true end
                show()
            end },
            { title = 'Edit intro', icon = 'fa-solid fa-align-left', description = short(draft.intro ~= '' and draft.intro or 'No intro', 70), onSelect = function()
                local v = UI.input('Intro', { { type = 'textarea', label = 'Opening paragraph (max 600)', maxLength = 600, default = draft.intro,
                    description = 'e.g. "...between {job} (the Employer), represented by {manager}, {manager_rank}, and {employee}..."' } })
                if v then draft.intro = v[1] or '' dirty = true end
                show()
            end },
            { title = 'Add section', icon = 'fa-solid fa-plus', disabled = #draft.sections >= 12, description = ('%d of 12 sections'):format(#draft.sections), onSelect = function()
                local s = sectionDialog(nil)
                if s then draft.sections[#draft.sections + 1] = s dirty = true end
                show()
            end },
            { title = 'Preview contract', icon = 'fa-solid fa-eye', description = 'See it on paper, filled in with example details', onSelect = function()
                BMC.previewContract(draft, d.sample)
                show()
            end },
            { title = 'Save contract', icon = 'fa-solid fa-floppy-disk', disabled = not dirty, description = dirty and 'You have unsaved changes' or 'No changes', onSelect = function()
                if UI.confirm({ header = 'Save contract', content = 'New hires will sign this version. Contracts already signed keep their own wording.', type = 'info', confirm = 'Save' }) then
                    local ok, msg = call('saveContractTemplate', m.gtype, m.name, draft)
                    notify(msg or (ok and 'Saved.' or 'Failed.'), ok and 'success' or 'error', 'Contract')
                    if ok then dirty = false end
                end
                show()
            end },
            { title = 'Reset to default', icon = 'fa-solid fa-rotate-left', description = d.custom and 'Go back to the contract in config.lua' or 'Already using the default', onSelect = function()
                if UI.confirm({ header = 'Reset contract', content = 'Delete this job\'s saved contract and use the default from config.lua?', type = 'warning', confirm = 'Reset' }) then
                    local ok, msg = call('resetContractTemplate', m.gtype, m.name)
                    notify(msg or '', ok and 'success' or 'error', 'Contract')
                    if ok then return BMC.openContractEditor(m) end
                end
                show()
            end },
        }
        for i, s in ipairs(draft.sections) do
            options[#options + 1] = { title = ('%d. %s'):format(i, s.title), description = short(s.text, 70), icon = 'fa-solid fa-paragraph', arrow = true,
                onSelect = function() openSection(i) end }
        end
        UI.registerMenu({ id = 'blaze_boss_contract', title = 'Contract · ' .. m.label .. (dirty and ' *' or ''), options = options,
            onExit = function() if dirty then leave() end end })
        UI.showMenu('blaze_boss_contract')
    end
    show()
end

--- offer = { template, values, style = 'paper'|'typed', expectedName }
--- Returns { accepted = bool, signature = string?, image = string? }
function BMC.signContract(offer, seconds)
    local C = Config.contract or {}
    if offer.style ~= 'typed' then
        local animating = C.animation ~= false and not IsPedInAnyVehicle(cache.ped, false)
        if animating then TaskStartScenarioInPlace(cache.ped, 'CODE_HUMAN_MEDIC_TIME_OF_DEATH', 0, true) end
        local res = openPaper('sign', { template = offer.template, values = offer.values }, seconds or 90)
        if animating then ClearPedTasks(cache.ped) end
        if res.accepted then PlaySoundFrontend(-1, 'PICK_UP', 'HUD_FRONTEND_DEFAULT_SOUNDSET', true) end
        return { accepted = res.accepted == true, image = res.image }
    end
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

    if not UI.confirm({ header = 'Employment Contract', content = contractText(offer), type = 'info', icon = 'fa-solid fa-file-signature',
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
    lib.notify({ title = ('%s announcement'):format(groupLabel), description = ('%s\n— %s'):format(message, by or 'Management'), type = 'inform', duration = 15000 })
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
-- PEDs and props at points (client-side only, spawned when you're within 40 m)
-- A point's look is p.entity = { kind = 'ped' | 'prop', model, scenario?, anim? }. Application points without one
-- still get the classic receptionist (features.receptionist) standing behind the counter.
-- The same helpers draw the see-through preview while placing (client/placement.lua), so the preview is the result.
---------------------------------------------------------------------------
local R = F.receptionist or {}
local pedPoints = {}

local function modelHash(m) return type(m) == 'number' and m or joaat(m) end

--- Put an entity on the spot: feet / base on z, facing heading
function BMC.setEntitySpot(ent, x, y, z, heading)
    local min = GetModelDimensions(GetEntityModel(ent))
    SetEntityCoordsNoOffset(ent, x, y, z - (min and min.z or 0.0), false, false, false)
    SetEntityHeading(ent, (heading or 0.0) % 360.0)
end

--- Stationary PED: never wanders, flees, fights, ragdolls or reacts to anything around it
local function calmPed(ped)
    SetEntityInvincible(ped, true)
    SetEntityCanBeDamaged(ped, false)
    SetBlockingOfNonTemporaryEvents(ped, true)
    TaskSetBlockingOfNonTemporaryEvents(ped, true)
    SetPedFleeAttributes(ped, 0, false)
    SetPedCombatAttributes(ped, 17, false)
    SetPedCombatAttributes(ped, 46, false)
    SetPedSeeingRange(ped, 0.0)
    SetPedHearingRange(ped, 0.0)
    SetPedAlertness(ped, 0)
    SetPedKeepTask(ped, true)
    SetPedCanRagdoll(ped, false)
    SetPedCanEvasiveDive(ped, false)
    SetPedCanBeTargetted(ped, false)
    SetPedDiesWhenInjured(ped, false)
    SetPedConfigFlag(ped, 185, true) -- no reacting to bumps
    SetPedConfigFlag(ped, 208, true) -- no shocking-event reactions
end

--- Spawn what a look describes at x, y, z (ground) facing heading. ghost = see-through preview without collision.
--- Returns the entity or nil (bad model, didn't load in time).
function BMC.spawnLook(look, x, y, z, heading, ghost)
    if type(look) ~= 'table' or not look.model then return nil end
    local model = modelHash(look.model)
    if not IsModelInCdimage(model) or not lib.requestModel(model, 5000) then return nil end
    local ent
    if look.kind == 'ped' then
        ent = CreatePed(4, model, x, y, z, heading or 0.0, false, false)
    else
        ent = CreateObjectNoOffset(model, x, y, z, false, false, false)
    end
    SetModelAsNoLongerNeeded(model)
    if not ent or ent == 0 then return nil end
    BMC.setEntitySpot(ent, x, y, z, heading)
    FreezeEntityPosition(ent, true)
    if look.kind == 'ped' then calmPed(ent) end
    if ghost then
        SetEntityAlpha(ent, 150, false)
        SetEntityCollision(ent, false, false)
        return ent
    end
    if look.kind == 'ped' then
        if look.scenario then
            TaskStartScenarioInPlace(ent, look.scenario, 0, false)
        elseif type(look.anim) == 'table' and lib.requestAnimDict(look.anim.dict, 3000) then
            TaskPlayAnim(ent, look.anim.dict, look.anim.name, 8.0, -8.0, -1, 1, 0.0, false, false, false)
            RemoveAnimDict(look.anim.dict)
        end
    end
    return ent
end

--- What stands at a point and where: look, x, y, z, heading (nil = invisible point)
function BMC.pointLook(p)
    if type(p.entity) == 'table' then
        return p.entity, p.coords.x, p.coords.y, p.coords.z, p.heading or 0.0
    end
    if p.type == 'applications' and R.enabled then -- classic receptionist: ~0.8 m behind the point, facing whoever placed it
        local h = p.heading or 0.0
        local rad = math.rad(h)
        local x, y = p.coords.x - math.sin(rad) * 0.8, p.coords.y + math.cos(rad) * 0.8
        local found, gz = GetGroundZFor_3dCoord(x, y, p.coords.z + 1.0, false)
        return { kind = 'ped', model = R.model or 'a_f_y_business_02', scenario = R.scenario or nil }, x, y, found and gz or p.coords.z, (h + 180.0) % 360.0
    end
    return nil
end

local function clearLooks()
    for _, p in ipairs(pedPoints) do
        if p.target then Target.remove(p.target) p.target = nil end
        if p.ent and DoesEntityExist(p.ent) then DeleteEntity(p.ent) end
        p:remove()
    end
    pedPoints = {}
end

function BMC.onPoints(points)
    clearLooks()
    for _, p in ipairs(points or {}) do
        local look = not p.dup and BMC.pointLook(p)
        if look then
            local lastGreet = 0
            local point = lib.points.new({ coords = vec3(p.coords.x, p.coords.y, p.coords.z), distance = 40.0 })
            function point:onEnter()
                if self.ent or self.target then return end
                local l, x, y, z, h = BMC.pointLook(p)
                self.ent = BMC.spawnLook(l, x, y, z, h)
                -- aim at the PED / prop itself (same options as the point). If it didn't spawn, fall back to the spot.
                if p.targetOptions then
                    if self.ent then self.target = Target.addEntity(self.ent, p.targetOptions) end
                    if not self.target and Bridge.target ~= 'none' then
                        self.target = Target.addPoint({ coords = vec3(p.coords.x, p.coords.y, p.coords.z), radius = p.radius or 1.0, options = p.targetOptions })
                    end
                end
            end
            function point:onExit()
                if self.target then Target.remove(self.target) self.target = nil end
                if self.ent and DoesEntityExist(self.ent) then DeleteEntity(self.ent) end
                self.ent = nil
            end
            if p.type == 'applications' and R.greet then
                function point:nearby()
                    if self.ent and IsEntityAPed(self.ent) and self.currentDistance < 2.5 and GetGameTimer() - lastGreet > 60000 then
                        lastGreet = GetGameTimer()
                        PlayPedAmbientSpeechNative(self.ent, 'GENERIC_HI', 'SPEECH_PARAMS_FORCE_NORMAL')
                    end
                end
            end
            pedPoints[#pedPoints + 1] = point
        end
    end
end

AddEventHandler('onResourceStop', function(res) if res == RES then clearLooks() end end)

---------------------------------------------------------------------------
-- Outfits: read / apply clothes. Uses illenium-appearance when it's running (auto), else plain GTA natives.
-- Face (0) and hair (2) are never touched: an outfit is clothes only.
---------------------------------------------------------------------------
local OUT = Config.outfits or {}
local COMPONENTS = { 1, 3, 4, 5, 6, 7, 8, 9, 10, 11 }
local PROPS = { 0, 1, 2, 6, 7 }
local KEEP = {}
for _, c in ipairs(COMPONENTS) do KEEP[c] = true end

local function useIllenium()
    return OUT.appearance ~= 'native' and GetResourceState('illenium-appearance') == 'started'
end

--- 'male' / 'female' for the freemode characters, nil for anything else
function BMC.pedModel()
    local m = GetEntityModel(cache.ped)
    if m == joaat('mp_m_freemode_01') then return 'male' end
    if m == joaat('mp_f_freemode_01') then return 'female' end
end

function BMC.readClothes()
    local ped, out = cache.ped, { components = {}, props = {} }
    if useIllenium() then
        for _, c in ipairs(exports['illenium-appearance']:getPedComponents(ped) or {}) do
            if KEEP[c.component_id] then out.components[#out.components + 1] = { component_id = c.component_id, drawable = c.drawable, texture = c.texture } end
        end
        for _, p in ipairs(exports['illenium-appearance']:getPedProps(ped) or {}) do
            out.props[#out.props + 1] = { prop_id = p.prop_id, drawable = p.drawable, texture = p.texture }
        end
        return out
    end
    for _, id in ipairs(COMPONENTS) do
        out.components[#out.components + 1] = { component_id = id, drawable = GetPedDrawableVariation(ped, id), texture = GetPedTextureVariation(ped, id) }
    end
    for _, id in ipairs(PROPS) do
        out.props[#out.props + 1] = { prop_id = id, drawable = GetPedPropIndex(ped, id), texture = GetPedPropTextureIndex(ped, id) }
    end
    return out
end

function BMC.applyClothes(data)
    local ped = cache.ped
    if type(data) ~= 'table' then return end
    if useIllenium() then
        exports['illenium-appearance']:setPedComponents(ped, data.components or {})
        exports['illenium-appearance']:setPedProps(ped, data.props or {})
        return
    end
    for _, c in ipairs(data.components or {}) do SetPedComponentVariation(ped, c.component_id, c.drawable, c.texture, 0) end
    for _, p in ipairs(data.props or {}) do
        if p.drawable == -1 then ClearPedProp(ped, p.prop_id) else SetPedPropIndex(ped, p.prop_id, p.drawable, p.texture, true) end
    end
end

--- Back to their own saved clothes (illenium-appearance's reloadSkin)
function BMC.ownClothes()
    if GetResourceState('illenium-appearance') == 'started' then
        TriggerEvent('illenium-appearance:client:reloadSkin', true)
        return notify('Back in your own clothes.', 'success', 'Wardrobe')
    end
    notify('Change back at a clothing store (no clothing script detected).', 'inform', 'Wardrobe')
end

local function changeAnim()
    if IsPedInAnyVehicle(cache.ped, false) then return end
    if lib.requestAnimDict('clothingtie', 2000) then
        TaskPlayAnim(cache.ped, 'clothingtie', 'try_tie_neutral_a', 8.0, -8.0, 1800, 51, 0.0, false, false, false)
        Wait(1200)
        RemoveAnimDict('clothingtie')
    end
end

local function wear(gtype, name, id)
    local o, err = call('wearOutfit', gtype, name, id)
    if not o then return notify(err or 'Couldn\'t put that on.', 'error', 'Wardrobe') end
    if o.model ~= BMC.pedModel() then return notify('That outfit is made for a different body type.', 'error', 'Wardrobe') end
    changeAnim()
    BMC.applyClothes(o.data)
    notify(('You put on "%s".'):format(o.name), 'success', 'Wardrobe')
end

--- Wardrobe point: staff pick an outfit for their rank
function BMC.openWardrobe(gtype, name, label)
    local model = BMC.pedModel()
    local d = call('getOutfits', gtype, name, model)
    if not d then return notify('Only staff can use this wardrobe.', 'error', 'Wardrobe') end
    local options = {}
    for _, o in ipairs(d.outfits) do
        if o.model == model then
            options[#options + 1] = { title = o.name, description = ('%s and up'):format(o.rankName), icon = 'fa-solid fa-shirt',
                disabled = not o.allowed, onSelect = function() wear(gtype, name, o.id) end }
        end
    end
    if #options == 0 then
        options[1] = { title = model and 'No outfits for you yet' or 'Outfits only work on freemode characters', icon = 'fa-solid fa-circle-info', readOnly = true,
            description = d.manager and 'Save one in the boss menu > Outfits' or 'Ask a manager to add some' }
    end
    options[#options + 1] = { title = 'Back to my own clothes', icon = 'fa-solid fa-person', onSelect = function() changeAnim() BMC.ownClothes() end }
    UI.registerMenu({ id = 'blaze_boss_wardrobe', title = 'Wardrobe · ' .. (label or name), options = options })
    UI.showMenu('blaze_boss_wardrobe')
end

--- Boss menu > Outfits: save what you're wearing, rename / change rank, try on, delete
function BMC.openOutfitManager(m)
    local model = BMC.pedModel()
    local d = call('getOutfits', m.gtype, m.name, model)
    if not d or not d.manager then return notify('You are not a manager here.', 'error', 'Outfits') end
    local function rankOptions()
        local o = {}
        for _, g in ipairs(d.grades) do o[#o + 1] = { value = tostring(g.level), label = ('%s (%d)'):format(g.name, g.level) } end
        return o
    end
    local options = {
        { title = 'Save what I\'m wearing', icon = 'fa-solid fa-plus', disabled = not model,
          description = model and ('Saved as a %s outfit. Face and hair aren\'t included.'):format(model) or 'Only works on the freemode characters',
          onSelect = function()
              local v = UI.input('New outfit', {
                  { type = 'input', label = 'Outfit name', required = true, minLength = 1, maxLength = 40, placeholder = 'Class A uniform' },
                  { type = 'select', label = 'Lowest rank that can wear it', options = rankOptions(), default = tostring(d.grades[1] and d.grades[1].level or 0), required = true },
              })
              if v and v[1] then
                  local ok, msg = call('saveOutfit', m.gtype, m.name, { name = v[1], minGrade = tonumber(v[2]) or 0, model = model, data = BMC.readClothes() })
                  notify(msg or '', ok and 'success' or 'error', 'Outfits')
              end
              BMC.openOutfitManager(m)
          end },
    }
    for _, o in ipairs(d.outfits) do
        options[#options + 1] = {
            title = o.name, description = ('%s · %s and up'):format(o.model == 'male' and 'Male' or 'Female', o.rankName), icon = 'fa-solid fa-shirt', arrow = true,
            onSelect = function()
                UI.registerMenu({ id = 'blaze_boss_outfit', title = o.name, menu = 'blaze_boss_outfits', options = {
                    { title = 'Try it on', icon = 'fa-solid fa-person-half-dress', disabled = o.model ~= model,
                      description = o.model ~= model and 'Made for a different body type' or nil, onSelect = function() wear(m.gtype, m.name, o.id) end },
                    { title = 'Rename / change rank', icon = 'fa-solid fa-pen', onSelect = function()
                        local v = UI.input('Edit outfit', {
                            { type = 'input', label = 'Outfit name', required = true, minLength = 1, maxLength = 40, default = o.name },
                            { type = 'select', label = 'Lowest rank that can wear it', options = rankOptions(), default = tostring(o.minGrade), required = true },
                        })
                        if v and v[1] then
                            local ok, msg = call('updateOutfit', m.gtype, m.name, o.id, v[1], tonumber(v[2]))
                            notify(msg or '', ok and 'success' or 'error', 'Outfits')
                        end
                        BMC.openOutfitManager(m)
                    end },
                    { title = 'Delete', icon = 'fa-solid fa-trash', iconColor = '#E5484D', onSelect = function()
                        if UI.confirm({ header = 'Delete outfit', content = ('Delete "%s"?'):format(o.name), type = 'error', confirm = 'Delete' }) then
                            local ok, msg = call('deleteOutfit', m.gtype, m.name, o.id)
                            notify(msg or '', ok and 'success' or 'error', 'Outfits')
                        end
                        BMC.openOutfitManager(m)
                    end },
                } })
                UI.showMenu('blaze_boss_outfit')
            end,
        }
    end
    if #d.outfits == 0 then options[#options + 1] = { title = 'No outfits yet', description = 'Put on a uniform, then "Save what I\'m wearing"', readOnly = true } end
    options[#options + 1] = { title = 'Back to my own clothes', icon = 'fa-solid fa-person', onSelect = function() BMC.ownClothes() end }
    UI.registerMenu({ id = 'blaze_boss_outfits', title = 'Outfits · ' .. m.label, menu = 'blaze_boss_main', options = options })
    UI.showMenu('blaze_boss_outfits')
end

---------------------------------------------------------------------------
-- Radial menu (ox_lib / qbx_radialmenu): a "Work" entry for bosses with their boss menu, applications, /myjob
---------------------------------------------------------------------------
local RAD = Config.radial or {}
local radialShown = false

--- groups = the groups this player really manages (from getMyJobs; admins only get theirs here)
--- admin = real admin: a separate "Boss admin" entry that opens /bossmenuadmin (radial.admin = false hides it)
local adminShown = false
function BMC.updateRadial(groups, admin)
    if not RAD.enabled or not lib.addRadialItem then return end
    if adminShown then lib.removeRadialItem('blaze_boss_admin') adminShown = false end
    if admin and RAD.admin ~= false and BMC.openAdmin then
        lib.addRadialItem({ id = 'blaze_boss_admin', label = RAD.adminLabel or 'Boss admin', icon = 'user-shield', onSelect = function() BMC.openAdmin() end })
        adminShown = true
    end
    if radialShown then lib.removeRadialItem('blaze_boss_work') radialShown = false end
    if #groups == 0 then return end
    local items = {}
    for _, g in ipairs(groups) do
        items[#items + 1] = { id = 'bb_boss_' .. g.gtype .. g.name, label = (#groups > 1 and (g.label .. ' ') or '') .. 'Boss menu', icon = 'briefcase',
            onSelect = function() TriggerEvent(RES .. ':client:openGroup', g.gtype, g.name) end }
        if g.apps then
            items[#items + 1] = { id = 'bb_apps_' .. g.name, label = (#groups > 1 and (g.label .. ' ') or '') .. 'Applications', icon = 'file-signature',
                onSelect = function() TriggerEvent(RES .. ':client:openReview', g.name) end }
        end
    end
    if F.profiles and F.myJobCommand then
        items[#items + 1] = { id = 'bb_myjob', label = 'My job', icon = 'id-badge', onSelect = function() BMC.openMyJob() end }
    end
    lib.registerRadial({ id = 'blaze_boss_work_menu', items = items })
    lib.addRadialItem({ id = 'blaze_boss_work', label = RAD.label or 'Work', icon = RAD.icon or 'briefcase', menu = 'blaze_boss_work_menu' })
    radialShown = true
end

AddEventHandler('onResourceStop', function(res)
    if res ~= RES or not lib.removeRadialItem then return end
    if radialShown then lib.removeRadialItem('blaze_boss_work') end
    if adminShown then lib.removeRadialItem('blaze_boss_admin') end
end)

---------------------------------------------------------------------------
-- Time clock screen (web/timeclock.html): opened from a duty point when Config.duty.style = 'clock'
---------------------------------------------------------------------------
local clockJob -- job of the clock that's open

function BMC.openClock(job)
    local data, err, methods = call('getClockData', job)
    if not data then return notify(err or 'This time clock isn\'t for you.', 'error', 'Time clock') end
    clockJob = job
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'openClock', data = data, methods = methods, size = (Config.duty or {}).size, view = (Config.duty or {}).view })
end

RegisterNUICallback('clock:punch', function(d, cb)
    if not clockJob then return cb({ ok = false, msg = 'The time clock is closed.' }) end
    cb(call('clockPunch', clockJob, d and d.method, d and d.pin) or { ok = false, msg = 'The time clock didn\'t respond.' })
end)

-- already on duty: the scan only opens the full screen
RegisterNUICallback('clock:access', function(d, cb)
    if not clockJob then return cb({ ok = false, msg = 'The time clock is closed.' }) end
    cb(call('clockAccess', clockJob, d and d.method, d and d.pin) or { ok = false, msg = 'The time clock didn\'t respond.' })
end)

RegisterNUICallback('clock:close', function(_, cb)
    cb(1)
    clockJob = nil
    SetNuiFocus(false, false)
end)

AddEventHandler('onResourceStop', function(res)
    if res == RES and clockJob then SetNuiFocus(false, false) end
end)
