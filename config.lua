-- blaze_bossmenu configuration. Server owner only: nothing here can be changed in game.
-- The Discord webhook is NOT set here. Put it in server.cfg:
--   set blaze_bossmenu_webhook "https://discord.com/api/webhooks/..."

Config = {
    -- false = the WHOLE resource does nothing (boss menu, applications and funds).
    -- Saved points/forms/applications stay in the database and come back when turned on again.
    enabled = true,

    -- true = menus, forms and confirm popups use Lation UI (lation_ui) instead of ox_lib.
    -- Falls back to ox_lib automatically if lation_ui isn't started. Notifications always use ox_lib.
    useLationUI = false,

    -- Which target script to use: 'auto' (ox_target first, then qb-target) | 'ox_target' | 'qb-target'
    target = 'auto',

    -- Ace that allows /bossmenu (placing points) and admin overrides. Framework admins also count.
    -- server.cfg: add_ace group.admin blaze_bossmenu.admin allow
    adminAce = 'blaze_bossmenu.admin',

    -- true = admins can open and use ANY configured job's boss menu
    adminsCanManage = true,

    -- How close (metres) a player must be to the manager to be hired from the boss menu
    hireDistance = 5.0,

    -- Only jobs listed here get a boss menu / applications. The key is the framework job name.
    jobs = {
        ambulance = {
            -- Shown in menus
            label = 'EMS',
            -- nil = use the job grade's isboss flag from the framework; or a number = minimum grade that counts as a manager
            bossGrade = nil,
            -- Society/bank account name used for Funds
            society = 'ambulance',
            -- Allow applications for this job (also needs applications.enabled below)
            applications = true,
            -- Show Funds for this job (also needs funds.enabled below)
            funds = true,
        },
        -- police = { label = 'LSPD', bossGrade = nil, society = 'police', applications = true, funds = true },
        -- fire = { label = 'LSFD', bossGrade = 4, society = 'fire', applications = true, funds = false },
        -- mechanic = { label = 'Mechanic', bossGrade = nil, society = 'mechanic', applications = true, funds = true },
    },

    applications = {
        -- false = application system off everywhere (the boss menu still works)
        enabled = true,
        -- Whether applications start open for a job. Managers can open/close them in game afterwards.
        startOpen = true,
        -- After a denial, how many hours before that player can apply to the same job again
        denyCooldownHours = 72,
        -- Who can build/edit the application form in game:
        -- 'management' = managers (+ admins), 'admin' = admins only, false = no in-game editing
        formEditor = 'management',
        -- Most questions a form can have
        maxQuestions = 15,
        -- Default intro text shown before the form (managers can change it per job in the form editor)
        intro = 'Thanks for your interest in joining. Answer honestly — managers will review your application.',
        -- The STARTING form for every job. Once a job's form is edited in game, that saved version is used
        -- ("Reset to default" in game goes back to these). The applicant's full name is always taken from
        -- their character automatically, so it is never a question.
        -- Types: 'input' (short answer), 'textarea' (long answer), 'number', 'select' (dropdown), 'checkbox'
        -- input/textarea: min/max = length in characters. number: min/max = value.
        defaultQuestions = {
            { label = 'Phone number', type = 'input', required = true },
            { label = 'Age', type = 'number', required = true, min = 18, max = 80 },
            { label = 'Relevant experience', type = 'textarea', required = true, min = 10 },
            { label = 'Why do you want to join?', type = 'textarea', required = true, min = 10 },
            { label = 'Availability', type = 'select', required = true,
              options = { 'Mornings', 'Afternoons', 'Evenings', 'Weekends', 'Anytime' } },
            { label = 'I have read the server and department rules', type = 'checkbox', required = true },
        },
    },

    funds = {
        -- false = no Funds anywhere (for servers using another society/banking script)
        enabled = true,
        -- Deposits/withdrawals of this amount or more ask for a confirm first
        confirmAbove = 5000,
        -- How many recent transactions show in "Recent history"
        historyLimit = 20,
    },

    -- Optional fixed points. In-game placed points (/bossmenu) are added on top.
    -- These can't be deleted in game; remove them here.
    -- type: 'boss' (management desk) or 'applications' (apply point)
    locations = {
        -- { job = 'ambulance', type = 'boss', coords = vec3(0.0, 0.0, 0.0), radius = 1.0 },
        -- { job = 'ambulance', type = 'applications', coords = vec3(0.0, 0.0, 0.0), radius = 1.0 },
    },

    logs = {
        -- Print events to the server console
        console = true,
        -- Send events to the ox_lib logger (Datadog / Fivemanage / Grafana Loki via the ox:logger convar)
        oxLogger = true,
        -- Send events to Discord. The webhook comes ONLY from the convar blaze_bossmenu_webhook in server.cfg.
        discord = true,
        -- Turn single events on/off
        events = {
            hire = true, fire = true, promote = true, demote = true, callsign = true,
            accept = true, deny = true, interview = true, deposit = true, withdraw = true,
            toggle = true, formEdit = true, formReset = true, placement = true,
        },
    },
}
