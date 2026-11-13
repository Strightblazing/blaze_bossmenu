-- Logging: console, ox_lib logger and Discord, each switched in Config.logs.
-- Discord webhook comes ONLY from server.cfg:  set blaze_bossmenu_webhook "https://discord.com/api/webhooks/..."
if not Config.enabled then return end

Logs = {}

local cfg = Config.logs or {}
local events = cfg.events or {}

local COLOURS = {
    hire = 0x3DDC84, accept = 0x3DDC84, promote = 0x5AA9FF, demote = 0xF0A93B, fire = 0xE5484D,
    deny = 0xE5484D, interview = 0x5AA9FF, callsign = 0x8F99A5, deposit = 0x3DDC84, withdraw = 0xF0A93B,
    toggle = 0xA78BFA, formEdit = 0xA78BFA, formReset = 0xA78BFA, placement = 0x8F99A5,
}

--- "Steven Blaze (ABC12345) [12]"
function Logs.who(src)
    if not src or src == 0 then return 'system' end
    return ('%s (%s) [%s]'):format(Bridge.GetName(src), Bridge.GetCitizenId(src) or '?', src)
end

-- Discord: batched so a busy server never hits the rate limit
local webhook = GetConvar('blaze_bossmenu_webhook', '')
local queue, sending = {}, false

local function flush()
    if sending or #queue == 0 or webhook == '' then return end
    sending = true
    local batch = {}
    for i = 1, math.min(10, #queue) do batch[i] = table.remove(queue, 1) end -- 10 embeds per message max
    PerformHttpRequest(webhook, function(status)
        sending = false
        if status == 429 then
            for i = #batch, 1, -1 do table.insert(queue, 1, batch[i]) end
        elseif status and (status < 200 or status >= 300) then
            print(('^3[blaze_bossmenu]^7 Discord log failed (HTTP %s). Check the blaze_bossmenu_webhook convar.'):format(status))
        end
    end, 'POST', json.encode({ username = 'Blaze Boss Menu', embeds = batch }), { ['Content-Type'] = 'application/json' })
end

if cfg.discord then
    CreateThread(function()
        while true do
            Wait(3000)
            flush()
            if #queue > 200 then for _ = 1, #queue - 200 do table.remove(queue, 1) end end
        end
    end)
    if webhook == '' then
        print('^3[blaze_bossmenu]^7 Discord logging is on but no webhook is set. Add to server.cfg: set blaze_bossmenu_webhook "https://discord.com/api/webhooks/..."')
    end
end

--- Log one event.
--- @param event string   key in Config.logs.events
--- @param src number?    player who did it (nil = system)
--- @param message string plain words
--- @param fields table?  extra details { Job = 'ambulance', Amount = '$500' }
function Logs.log(event, src, message, fields)
    if events[event] == false then return end
    fields = fields or {}

    if cfg.oxLogger and lib.logger then
        local tags = {}
        for k, v in pairs(fields) do tags[#tags + 1] = ('%s:%s'):format(tostring(k):lower():gsub('%s+', '_'), tostring(v)) end
        pcall(lib.logger, src or 0, 'blaze_bossmenu:' .. event, message, table.unpack(tags))
    end

    if cfg.console then
        local extra = {}
        for k, v in pairs(fields) do extra[#extra + 1] = ('%s=%s'):format(k, tostring(v)) end
        print(('^5[blaze_bossmenu:%s]^7 %s %s'):format(event, message, #extra > 0 and ('(' .. table.concat(extra, ', ') .. ')') or ''))
    end

    if cfg.discord and webhook ~= '' then
        local embedFields = {}
        for k, v in pairs(fields) do
            embedFields[#embedFields + 1] = { name = tostring(k), value = tostring(v):sub(1, 1000), inline = true }
        end
        queue[#queue + 1] = {
            title = event:gsub('^%l', string.upper), description = message:sub(1, 2000),
            color = COLOURS[event] or 0x8F99A5, fields = embedFields,
            footer = { text = 'Blaze Boss Menu' }, timestamp = os.date('!%Y-%m-%dT%H:%M:%SZ'),
        }
    end
end
