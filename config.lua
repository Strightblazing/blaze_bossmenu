-- blaze_bossmenu | GNU GPL v3 (see LICENSE) | based on qbx_management by the Qbox Project (see NOTICE.md)
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

    -- Debug: log every boss menu action (name, result, time) to the server console, and draw all points with
    -- their ids for everyone. Leave false on a live server. Admins use /bossdebug instead (like Blaze Medical's
    -- /blazedebug): on / off (everyone's actions in the console + your panel), view (just your panel), move.
    debug = false,
    -- Admin debug command name
    debugCommand = 'bossdebug',

    -- Admin test tools: fake offline staff + applications so one person can try everything, plus effect previews.
    -- "Remove all test data" in the menu cleans it all up. false = no command (recommended once you go live)
    testCommand = 'bossmenutest',

    -- Which target script to use: 'auto' (ox_target, then qb-target, else 'none') | 'ox_target' | 'qb-target'
    -- | 'none' (walk-up zone: a "[E]" text prompt when you stand at the point, like qbx_management without target)
    target = 'auto',

    -- Ace that allows the admin menu (/bossmenuadmin) and its tools. Framework admins also count.
    -- server.cfg: add_ace group.admin blaze_bossmenu.admin allow
    adminAce = 'blaze_bossmenu.admin',

    -- Admin menu command: boss menus for any job, points, Show zones, debug, test tools, settings
    adminCommand = 'bossmenuadmin',

    -- true = admins can open ANY configured job's boss menu with full access, from the admin menu only
    -- (Boss menus). At desks and in the radial menu admins are treated like anyone else (their real rank).
    adminsCanManage = true,

    -- How close (metres) a player must be to the manager to be hired from the boss menu
    hireDistance = 5.0,

    -- true = the person being hired gets an Accept/Decline popup first (from qbx_management)
    hireConsent = true,
    -- Seconds they have to answer before it counts as declined
    hireConsentSeconds = 30,

    -- Employment contract: instead of a plain Accept/Decline, the person being hired reads an employment
    -- agreement and signs it. It fills itself in: job label, rank, pay, probation, the new hire, and the
    -- person hiring with their rank. The signed copy (exact wording + signature) is kept on their record.
    -- Needs hireConsent = true.
    contract = {
        enabled = true,
        -- 'paper' = a real-looking contract on screen, signed with the mouse
        -- 'typed' = a popup where they type their full name instead
        style = 'paper',
        -- Seconds to read and sign before the offer expires
        seconds = 90,
        -- 'typed' style only: the typed name must match their character's name (checked on the server)
        requireExactName = true,
        -- Notepad animation while reading/signing
        animation = true,
        -- Who can edit a job's contract in game (boss menu > Employment contract):
        -- 'management' = managers (+ admins), 'admin' = admins only, false = only this file
        editor = 'management',
        -- The default contract for every job. Once a job's contract is edited in game, that version is used
        -- ("Reset to default" in game comes back to this one).
        -- Placeholders filled in automatically: {job} {rank} {pay} {probation} {employee} {manager} {manager_rank} {date} {number}
        -- A section that uses {pay} or {probation} is left out when that doesn't apply (no pay / probation off).
        -- In a section's text, lines starting with "-" become a numbered list.
        template = {
            title = 'Employment Agreement',
            intro = 'This Employment Agreement (the "Agreement") is made on {date} between {job} (the "Employer"), represented by {manager}, {manager_rank}, and {employee} (the "Employee").',
            sections = {
                { title = 'Position', text = 'The Employer hires the Employee as {rank}, reporting through the {job} chain of command.' },
                { title = 'Compensation', text = 'The Employee will be paid {pay} per paycheck, under {job} policy.' },
                { title = 'Probation', text = 'The first {probation} are a probationary period. {job} management will review the Employee\'s work when it ends.' },
                { title = 'Terms of employment', text = '- Show up for your shifts and follow {job} rules and the chain of command.\n'
                    .. '- Treat the public and your co-workers with respect.\n'
                    .. '- {job} vehicles, equipment and funds are for work only.\n'
                    .. '- Either side may end this employment at any time.' },
                { title = 'Agreement', text = 'By signing below, the Employee accepts this position and agrees to the terms of this Agreement.' },
            },
        },
    },

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
            -- Full name, shown under the label on the time clock (optional)
            fullName = 'Emergency Medical Services',
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
        -- The applicant's phone number and email, pulled from their phone (sd-phone, lb-phone, ...; see contact below)
        -- and sent with the application so managers can reach them. required = they must set it up on their phone first.
        contact = {
            phone = true, phoneRequired = true,
            email = true, emailRequired = true,
        },
        -- The applicant's age, worked out from their character's birthdate and sent with the application
        age = true,
        -- Youngest age that can apply (from the birthdate). nil = no minimum
        minAge = 18,
        -- Managers vote for/against applications and see the tally
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
            -- "Needs training": passed the interview, training before they're hired
            training = {
                'You passed your interview. Complete a ride-along with a senior member before you are hired.',
                'Finish the department training course, then contact a manager.',
            },
        },
        -- Who can build/edit the application form in game:
        -- 'management' = managers (+ admins), 'admin' = admins only, false = no in-game editing
        formEditor = 'management',
        -- Who sees "Clear application data" in Hiring settings (delete closed or all applications of the job):
        -- 'management' = managers (+ admins), 'admin' = admins only (in /bossmenuadmin), false = nobody
        clearData = 'management',
        -- Most questions a form can have
        maxQuestions = 15,
        -- Default intro text shown before the form (managers can change it per job in the form editor)
        intro = 'Thanks for your interest in joining. Answer honestly — managers will review your application.',
        -- The STARTING form for every job. Once a job's form is edited in game, that saved version is used
        -- ("Reset to default" in game goes back to these). The applicant's full name is always taken from
        -- their character automatically, so it is never a question; their phone number and email come from their
        -- phone (contact above) and their age from their birthdate (age above), so those aren't questions either
        -- (a saved form's name / phone / email / age questions are skipped).
        -- Types: 'input' (short answer), 'textarea' (long answer), 'number', 'select' (dropdown), 'checkbox'
        -- input/textarea: min/max = length in characters. number: min/max = value.
        defaultQuestions = {
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

    -- Duty points: staff clock in / out at a placed duty point (feeds the duty hours too)
    duty = {
        enabled = true,
        -- 'clock' = time clock screen (their virtual ID, shift timer, hours this week, next rank, who's on duty,
        --           the announcement); 'instant' = just toggle duty with a notification
        style = 'clock',
        -- How staff can clock in on the time clock (they pick one; first = default):
        -- 'tap' = drag the ID onto the reader, 'swipe' = swipe it through the slot, 'keypad' = type the PIN on their ID
        methods = { 'tap', 'swipe', 'keypad' },
        -- Starting size of the time clock (1.0 = normal, 1.25 = 25% larger). Each player can change their own
        -- with the - / + buttons on the clock (saved on their PC). It always shrinks to fit small screens.
        size = 1.25,
        -- What the full time clock view shows after clocking in.
        view = {
            -- 'full'     = everything
            -- 'standard' = your shift, tags, this week, next rank, who's on duty, announcement (no About you / Department)
            -- 'minimal'  = your shift and who's on duty
            layout = 'full',
            -- Turn single sections on/off on top of the layout (nil = follow the layout)
            sections = {
                shift = nil,        -- this shift / this week / last 31 days
                tags = nil,         -- Employee of the week, probation, ready for promotion
                week = nil,         -- hours per day this week
                nextRank = nil,     -- progress to the next rank and its pay
                department = nil,   -- on duty vs staff, applications waiting, Employee of the week
                onDuty = nil,       -- who's on duty right now
                aboutYou = nil,     -- the About you list (lines below)
                announcement = nil, -- the department announcement
            },
            -- Lines in About you (phone / email off = not even looked up)
            aboutYou = { rank = true, callsign = true, phone = true, email = true, department = true, employed = true, pay = true, record = true },
        },
    },

    -- Job outfits: managers save what they're wearing as a job outfit (with the lowest rank allowed),
    -- staff change into them at a wardrobe point. Male and female outfits are kept apart. Face and hair are never changed.
    outfits = {
        enabled = true,
        -- 'auto' = use illenium-appearance when it's running (recommended), 'native' = plain GTA clothing natives
        appearance = 'auto',
        -- Most outfits one job can have
        maxPerJob = 30,
    },

    -- Phone number + email on the time clock (About you) and in employee profiles.
    -- Auto-detects: sd-phone, lb-phone, high-phone, qs-smartphone-pro, qs-smartphone (qs-base), 17mov_Phone, npwd,
    -- then falls back to the character's own phone (qb-phone, nPhone and others).
    contact = {
        enabled = true,
        -- 'auto' = first phone resource that's running, or one resource name, e.g. 'lb-phone'
        phone = 'auto',
        -- Your own lookup for any other phone script (return nil to fall through to the ones above):
        -- getPhone = function(citizenid, source) return exports['my-phone']:GetNumber(citizenid) end,
        -- getEmail = function(citizenid, source) return exports['my-phone']:GetEmail(citizenid) end,
    },

    -- Managers place/move/delete their OWN job's points from the boss menu (Locations). Admins can always use /bossmenuadmin.
    managerPlacement = {
        enabled = true,
        -- Which point types managers may place
        types = { boss = true, applications = true, review = true, duty = true, outfits = true },
        -- Managers can teleport to their job's points (admins always can)
        teleport = false,
    },

    -- How close you must be to use a point with ox_target / qb-target (PEDs and props: +0.5 m)
    targetDistance = 2.0,

    -- What can stand at a point (picked when placing it, or "Change look" later). Any model name can also be typed in.
    -- PEDs stand still: they never wander off, flee or react to what happens around them.
    pointLooks = {
        peds = {
            { label = 'Receptionist', model = 'a_f_y_business_02' },
            { label = 'Business man', model = 'a_m_y_business_03' },
            { label = 'Doctor', model = 's_m_m_doctor_01' },
            { label = 'Nurse', model = 's_f_y_scrubs_01' },
            { label = 'Paramedic', model = 's_m_m_paramedic_01' },
            { label = 'Police officer', model = 's_m_y_cop_01' },
            { label = 'Security guard', model = 's_m_m_security_01' },
            { label = 'Mechanic', model = 's_m_y_xmech_02' },
        },
        -- Idle: a GTA scenario, or an animation { dict, name } (played on a loop)
        idles = {
            { label = 'Clipboard', scenario = 'WORLD_HUMAN_CLIPBOARD' },
            { label = 'Stand guard', scenario = 'WORLD_HUMAN_GUARD_STAND' },
            { label = 'On the phone', scenario = 'WORLD_HUMAN_STAND_MOBILE' },
            { label = 'Coffee', scenario = 'WORLD_HUMAN_AA_COFFEE' },
            { label = 'Police idle', scenario = 'WORLD_HUMAN_COP_IDLES' },
            { label = 'Arms crossed', anim = { dict = 'amb@world_human_hang_out_street@female_arms_crossed@idle_a', name = 'idle_a' } },
        },
        props = {
            { label = 'Laptop', model = 'prop_laptop_01a' },
            { label = 'Computer screen', model = 'prop_monitor_w_large' },
            { label = 'Cash register', model = 'prop_till_01' },
            { label = 'Office desk', model = 'prop_office_desk_01' },
            { label = 'Tool chest', model = 'prop_toolchest_05' },
            { label = 'Notepad', model = 'prop_notepad_01' },
            { label = 'Cardboard box', model = 'prop_cs_cardbox_01' },
        },
    },

    -- Your HUD resource: hidden while boss menu screens are open (menus, forms, popups, the contract, the time clock)
    -- and while placing, moving or resizing points (the GTA HUD and minimap always hide then).
    -- It only shows again if it was on before. Other scripts can use the same thing:
    --   exports.blaze_bossmenu:HideHud(true)   -- hide (for example while examining a patient)
    --   exports.blaze_bossmenu:HideHud(false)  -- let go (shows again when nothing else is hiding it)
    hud = {
        hideInMenus = false, -- true = hide while boss menu screens are open
        hideWhilePlacing = true, -- hide while placing / moving / resizing points
        -- Which export hides your HUD (client side). false = none. Either one "set visible" export:
        --   export = { resource = 'your_hud', set = 'setVisible', isVisible = 'isVisible' },
        --     set(true / false) shows / hides it; isVisible (optional) remembers if it was on before
        -- or separate hide / show exports:
        --   export = { resource = 'your_hud', hide = 'hideHud', show = 'showHud' },
        -- element_hud: { resource = 'element_hud', set = 'setHudVisible', isVisible = 'isHudVisible' }
        export = false,
        -- Or a function(hidden) for anything else, for example:
        --   toggle = function(hidden) TriggerEvent('your_hud:toggle', not hidden) end,
        -- HUDs can also listen to the client event 'blaze_bossmenu:client:hud' (true = hide, false = show).
        toggle = false,
    },

    -- Older option, still works: function(hidden) called only while placing points. Use hud above instead.
    placementHud = false,

    -- Radial menu (ox_lib / qbx_radialmenu): a "Work" entry for bosses with their boss menu, applications and My job
    radial = {
        enabled = true,
        label = 'Work',
        icon = 'briefcase',
        -- Admins also get a separate "Boss admin" entry that opens the admin menu
        admin = true,
        adminLabel = 'Boss admin',
    },

    -- Boss Menu app on other devices: staff, hiring, applications, funds and activity, with the same server checks
    -- as the boss menu. Each only does anything when that resource is running.
    devices = {
        label = 'Boss Menu',
        -- sd-computers (experimental, off by default): an app on the desktop of every computer
        -- (computerIds = { 'pc_1', ... } for only those). Known issues on some servers: typing in computer apps, and
        -- thin lines drawn across the screen while the app is open.
        computers = false,
        computerIds = nil,
        pinned = true, -- also on the taskbar / dock
        mirrorScreen = false, -- true = players walking past can read the app on the computer's screen
        -- sd-phone: an app on the phone; sd-tablet shows it too (players in a configured job)
        phone = true,
        -- false = players download it from the phone's App Store first; true = already installed
        preinstalled = false,
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
        -- Managers name an Employee of the Week (shown in the staff list, announced to the department)
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
        -- Seconds before that mail arrives, picked at random between min and max (a reply doesn't land the same instant)
        phoneMailDelay = { min = 15, max = 45 },
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

    -- Optional fixed points. In-game placed points (/bossmenuadmin) are added on top.
    -- These can't be deleted in game; remove them here.
    -- type: 'boss' (management desk), 'applications' (apply point) or 'review' (managers review applications).
    -- For a gang desk use gang = 'name' instead of job.
    locations = {
        -- { job = 'ambulance', type = 'boss', coords = vec3(0.0, 0.0, 0.0), radius = 1.0 },
        -- { job = 'ambulance', type = 'applications', coords = vec3(0.0, 0.0, 0.0), radius = 1.0 },
        -- { gang = 'lostmc', type = 'boss', coords = vec3(983.69, -90.92, 74.85), radius = 1.0 },
        -- With a PED or prop (entity): kind = 'ped' or 'prop', model, and for PEDs scenario = '...' or anim = { dict, name }
        -- { job = 'ambulance', type = 'applications', coords = vec3(0.0, 0.0, 0.0), heading = 90.0, radius = 1.0, entity = { kind = 'ped', model = 'a_f_y_business_02', scenario = 'WORLD_HUMAN_CLIPBOARD' } },
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
            record = true, eotw = true, announce = true, bonus = true, withdrawApp = true, checkin = true, contractEdit = true, outfit = true,
        },
    },
}
