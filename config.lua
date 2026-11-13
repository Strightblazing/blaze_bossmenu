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

    -- On start, check GitHub for a newer release and say so in the console (false = don't check)
    versionCheck = true,

    -- Admin test tools: fake offline staff + applications so one person can try everything, plus effect previews.
    -- "Remove all test data" in the menu cleans it all up. false = no command (recommended once you go live)
    testCommand = 'bossmenutest',

    -- Which target script to use: 'auto' (ox_target, then qb-target, else 'none') | 'ox_target' | 'qb-target'
    -- | 'none' (walk-up zone: a "[E]" text prompt when you stand at the point, like qbx_management without target)
    target = 'auto',

    -- Ace that allows /bossmenu (placing points) and admin overrides. Framework admins also count.
    -- server.cfg: add_ace group.admin blaze_bossmenu.admin allow
    adminAce = 'blaze_bossmenu.admin',

    -- true = admins can open and use ANY configured job's boss menu
    adminsCanManage = true,

    -- How close (metres) a player must be to the manager to be hired from the boss menu
    hireDistance = 5.0,

    -- true = the person being hired gets an Accept/Decline popup first (from qbx_management)
    hireConsent = true,
    -- Seconds they have to answer before it counts as declined
    hireConsentSeconds = 30,

    -- Duty hours (from qbx_management): logs on/off duty time per employee and shows hours + last check-in
    -- in the staff list. Uses the same player_jobs_activity table as qbx_management, so old hours carry over.
    activity = {
        -- false = no duty hour tracking
        enabled = true,
        -- Shifts shorter than this (minutes) aren't saved
        minOnDutyMinutes = 30,
        -- Hours shown are from the last this-many days; older rows are deleted on start
        keepDays = 31,
        -- How dates are shown (os.date format)
        dateFormat = '%m-%d-%Y %H:%M',
    },

    -- In-game grade editor (from qbx_management): bosses rename grades, change pay, boss flag and bank access
    -- for grades up to their own. Qbox only. Saved in the management_groups table (same as qbx_management)
    -- and loaded into qbx_core on start. Also needs this in server.cfg (the same convar qbx_management used):
    --   setr qbx:enableGroupManagement "true"
    gradeEditor = true,

    -- qbx_management compatibility: answer qb-bossmenu:client:OpenMenu / qb-gangmenu:client:OpenMenu and
    -- exports.qbx_management:OpenBossMenu / AddBossMenuItem / RegisterBossMenu ... so other scripts
    -- (illenium-appearance boss outfits, etc.) keep working after qbx_management is stopped.
    -- Turned off automatically while qbx_management itself is started.
    qbxManagementCompat = true,

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
            -- Shown on the /jobs board
            description = 'Save lives on the streets of Los Santos. No experience needed, we train you.',
            -- Ready for promotion: hours on duty (last activity.keepDays days) needed at each rank. Remove = no badge.
            promotionHours = { [0] = 10, [1] = 20, [2] = 35, [3] = 50 },
            -- Most a rank can withdraw (and pay in bonuses) per day. Ranks not listed = no limit. Admins aren't limited.
            withdrawLimits = { [3] = 10000 },
            -- Items new hires get (ox_inventory or your framework inventory). {} = none.
            starterItems = {
                -- { item = 'radio', count = 1 },
            },
        },
        -- police = { label = 'LSPD', bossGrade = nil, society = 'police', applications = true, funds = true },
        -- fire = { label = 'LSFD', bossGrade = 4, society = 'fire', applications = true, funds = false },
        -- mechanic = { label = 'Mechanic', bossGrade = nil, society = 'mechanic', applications = true, funds = true },
    },

    -- Gangs that get a gang menu (members, hire, promote/demote, kick, grade editor, optional funds).
    -- Gangs don't use applications or callsigns. The key is the framework gang name.
    gangs = {
        -- lostmc = {
        --     label = 'The Lost MC',
        --     bossGrade = nil,      -- nil = the gang grade's isboss flag; or a number (min grade)
        --     society = 'lostmc',   -- account name for Funds (only used when funds = true)
        --     funds = false,        -- show Funds for this gang (also needs funds.enabled below)
        -- },
    },

    applications = {
        -- false = application system off everywhere (the boss menu still works)
        enabled = true,
        -- Whether applications start open for a job. Managers can open/close them in game afterwards.
        startOpen = true,
        -- After a denial, how many hours before that player can apply to the same job again
        denyCooldownHours = 72,
        -- Command that opens "My applications" (status, reasons, interview details, their answers).
        -- false = no command (the application point still has "My application status")
        statusCommand = 'applicationstatus',
        -- Applicants can withdraw an application that hasn't been decided yet
        allowWithdraw = true,
        -- Managers vote 👍/👎 on applications and see the tally
        votes = true,
        -- Applicants invited to an interview can "Check in" at the review point; online managers are told
        interviewCheckIn = true,
        -- Ready-made messages managers can pick when denying or inviting (they can still write their own)
        quickReplies = {
            deny = {
                'We have no open positions right now. Please try again later.',
                'Your application needs more detail. Feel free to apply again.',
                'You did not meet our requirements at this time.',
            },
            interview = {
                'Come to the front desk today. Check in at the review desk when you arrive.',
                'Contact a manager in the city to set up a time.',
            },
        },
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
        -- Managers pay bonuses from the society account to one employee or everyone on duty (into their bank)
        bonuses = true,
        -- Biggest bonus per person
        maxBonus = 5000,
        -- "Payroll" page: pay per rank and what one paycheck costs for all staff / staff on duty (jobs only)
        payroll = true,
    },

    -- Extras. Each one can be turned off on its own.
    features = {
        -- Employee profiles (staff list + /myjob): hire date, hours this week, rank history, record
        profiles = true,
        -- Commendations and write-ups on an employee's record
        records = true,
        -- New hires are on probation this many days; managers get a reminder when it ends. 0 = off
        probationDays = 7,
        -- Flag staff with no duty time in this many days as Inactive in the staff list. 0 = off
        inactiveDays = 7,
        -- Managers post an announcement; on-duty staff see it now, others when they clock in
        announcements = true,
        -- Managers name an Employee of the Week (⭐ in the staff list, announced to the department)
        employeeOfWeek = true,
        -- "Activity log" in the boss menu: recent hires, fires, promotions, money moves...
        auditLog = true,
        -- How many entries the activity log shows, and how many days they're kept
        auditShow = 50,
        auditKeepDays = 30,
        -- Big on-screen message + sound when someone is hired, promoted, gets a bonus or Employee of the Week
        celebrations = true,
        -- Manager and new hire shake hands when a nearby hire is accepted
        handshake = true,
        -- Command for staff to see their own profile, record and the department announcement. false = off
        myJobCommand = 'myjob',
        -- "Now hiring" board: lists jobs taking applications, with a waypoint to each application point. false = off
        jobBoardCommand = 'jobs',
        -- Also send application results by phone mail (sd-phone, if it's running). false = off
        phoneMail = true,
        -- A receptionist NPC stands at each applications point and greets people who walk up
        receptionist = {
            enabled = true,
            model = 'a_f_y_business_02',
            -- Animation the receptionist plays (GTA scenario name); false = just stand
            scenario = 'WORLD_HUMAN_CLIPBOARD',
            -- Say hello when someone walks up
            greet = true,
        },
    },

    -- Optional fixed points. In-game placed points (/bossmenu) are added on top.
    -- These can't be deleted in game; remove them here.
    -- type: 'boss' (management desk), 'applications' (apply point) or 'review' (managers review applications).
    -- For a gang desk use gang = 'name' instead of job.
    locations = {
        -- { job = 'ambulance', type = 'boss', coords = vec3(0.0, 0.0, 0.0), radius = 1.0 },
        -- { job = 'ambulance', type = 'applications', coords = vec3(0.0, 0.0, 0.0), radius = 1.0 },
        -- { gang = 'lostmc', type = 'boss', coords = vec3(983.69, -90.92, 74.85), radius = 1.0 },
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
            toggle = true, formEdit = true, formReset = true, placement = true, gradeEdit = true,
            record = true, eotw = true, announce = true, bonus = true, withdrawApp = true, checkin = true,
        },
    },
}
