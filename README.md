# blaze_bossmenu

Boss menu + job application system for **any job** (EMS, fire, police, mechanic, …) and gangs.
Runs on **Qbox** and **QBCore**. Menus use **ox_lib** by default, with optional **Lation UI**. Menus use no web page of their own; the one exception is the employment contract, signed with the mouse.

It is a fork of [qbx_management](https://github.com/Qbox-project/qbx_management) (GPL-3.0) and replaces it:
everything qbx_management did is here, plus applications, funds, callsigns and in-game placement. See `NOTICE.md`.
It does **not** need Blaze Medical or any other Blaze resource.

## Features

- **Staff**: list everyone in the job (online and offline) with rank, callsign, on duty / off duty / offline,
  hours worked and last check-in. Promote, demote, set callsign and fire.
- **Rank rules** (checked on the server): you only manage people *below* your rank, only promote up to the rank
  just below yours, and can't act on yourself (except your own callsign). Admins can manage any configured job.
- **Hire**: nearby players or by server ID. The person gets an **Accept / Decline** popup first.
- **Applications**: anyone applies at an application point. Managers review, invite to interview, accept & hire
  (picking the starting rank), or deny with a reason. Applicants are told right away, or on their next login.
  Managers can also review at a separate **application review point**, and applicants check theirs with `/applicationstatus`.
- **Form builder in game**: add, edit, reorder, delete and preview questions; edit the intro; save or reset to default.
  Old applications keep their own questions and answers, so they still read correctly after the form changes.
- **Funds**: society balance, deposit and withdraw cash (with a reason), confirm on big amounts, recent history.
- **Duty hours**: on/off duty time per employee, kept for 31 days (same table as qbx_management, so old hours carry over).
- **Rank editor** (Qbox): rename ranks, change pay, boss flag and bank access, saved across restarts.
- **Gangs**: members, hire, promote/demote, kick, rank editor, optional funds.
- **Placement**: `/bossmenu` lets admins place boss desks and application points where they're looking.
- **Logs** to console, the ox_lib logger and Discord.
- **Compatibility** with scripts written for qbx_management or qb-bossmenu (e.g. illenium-appearance boss outfits).

### Extras (each can be turned off in `Config.features`, `Config.applications` or `Config.funds`)

**Staff**
- **Employee profiles**: hire date, probation, hours this week and this month, last check-in, rank history and record.
- **Commendations & write-ups** on an employee's record (write-ups only for people below you). They're told right away.
- **Probation**: new hires are on probation for `probationDays`; managers get a reminder when it ends.
- **Badges in the staff list**: ⭐ Employee of the Week, Probation, Inactive (no duty in `inactiveDays`), Ready for promotion (`promotionHours`).
- **Employee of the Week**: announced to the whole department, with a big on-screen message for the winner.
- **`/myjob`**: staff see their own profile, record and the current department announcement.

**Applications**
- **Team votes**: managers vote 👍/👎 on an application and see who voted what.
- **Quick replies**: ready-made deny reasons and interview messages (`applications.quickReplies`).
- **Withdraw**: applicants can withdraw an undecided application from `/applicationstatus`.
- **Interview check-in**: invited applicants "Check in for interview" at the review point, and online managers are told.
- **`/jobs` "Now hiring" board**: every job taking applications, with a waypoint to its application point.
- **Phone mail**: results also arrive as an email in sd-phone (if it's running).
- **Receptionist NPC**: stands behind each applications point and says hello.

**Money**
- **Bonuses**: pay one employee or everyone on duty from society funds, straight into their bank (`maxBonus` per person).
- **Daily withdrawal limits per rank** (`jobs[x].withdrawLimits`), covering withdrawals and bonuses. Admins aren't limited.
- **Payroll**: pay per rank, and what one paycheck costs for everyone / for staff on duty now.

**Employment contract**
- When someone is hired nearby, they get a real-looking **Employment Agreement** on screen instead of a plain Accept/Decline,
  and **sign it with the mouse**. A red SIGNED stamp lands on the page. Their character writes on a notepad meanwhile.
- It **fills itself in**: the job label, rank, pay, probation, the new hire's name, and the person hiring with their rank
  ("represented by Dr. Steven Blaze, Chief"). Placeholders: `{job}` `{rank}` `{pay}` `{probation}` `{employee}`
  `{manager}` `{manager_rank}` `{date}` `{number}`. A section that uses `{pay}` or `{probation}` drops out when it doesn't apply.
- **Edit it in game**: boss menu → **Employment contract**. Change the title and intro, add/edit/move/delete sections,
  preview it on paper, save, or reset to default. Each job has its own; the default is `contract.template` in config.lua.
- The signed copy (exact wording + signature) is kept, so editing the template later never changes old contracts.
  **View employment contract** in their profile or `/myjob` opens it again.
- Prefer typing? `contract.style = 'typed'`: a popup where they type their full name (checked on the server).
- Try it alone with `/bossmenutest` → **Preview: employment contract**, or open `web/contract.html` in a browser for a demo.

**Flair**
- **Celebrations**: big centre-screen message + sound for new hires, promotions, bonuses and Employee of the Week.
- **Handshake**: manager and new hire shake hands when a nearby hire is accepted.
- **Starter items** for new hires (`jobs[x].starterItems`, ox_inventory or the framework inventory).
- **Announcements**: on-duty staff see them now (with a sound), others when they clock in.
- **Activity log**: recent hires, fires, promotions, money moves and more, right in the boss menu.

## Requirements

- [ox_lib](https://github.com/overextended/ox_lib)
- [oxmysql](https://github.com/overextended/oxmysql)
- Qbox (`qbx_core`) **or** QBCore (`qb-core`)
- `ox_target` or `qb-target` (optional: without one, points use a walk-up `[E]` prompt)
- For Funds: one of Renewed-Banking, qb-banking, okokBanking or qb-management
- Optional: `lation_ui`

## Install

1. Put `blaze_bossmenu` in your resources (for example `resources/[standalone]/blaze_bossmenu`).
2. If you used **qbx_management**, stop it. blaze_bossmenu replaces it.
   Keep the folder, but move it somewhere that isn't ensured (for example `resources/[disabled]/qbx_management`).
   Scripts such as illenium-appearance check that the folder exists and then call `exports.qbx_management:…`;
   blaze_bossmenu answers those calls while qbx_management is stopped.
3. Add to `server.cfg` (after ox_lib, oxmysql, your framework and your target script):

```cfg
ensure blaze_bossmenu

# Discord logs. Set the webhook HERE only, never in a file.
set blaze_bossmenu_webhook "https://discord.com/api/webhooks/..."

# Who can use /bossmenu and admin overrides (framework admins also count)
add_ace group.admin blaze_bossmenu.admin allow

# Optional, Qbox: turn on the in-game rank editor (same convar qbx_management used)
setr qbx:enableGroupManagement "true"
```

If you use `ensure [standalone]` and the resource is in that folder, you don't need its own `ensure` line.
The database tables are created on first start.

## Adding jobs and gangs

Only jobs and gangs listed in `config.lua` get a boss menu. The key is the framework job/gang name.

```lua
jobs = {
    ambulance = { label = 'EMS', bossGrade = nil, society = 'ambulance', applications = true, funds = true },
    police    = { label = 'LSPD', bossGrade = nil, society = 'police', applications = true, funds = true },
    mechanic  = { label = 'Mechanic', bossGrade = 3, society = 'mechanic', applications = false, funds = true },
},
gangs = {
    lostmc = { label = 'The Lost MC', bossGrade = nil, society = 'lostmc', funds = false },
},
```

- `bossGrade = nil` uses the grade's **isboss** flag from your framework. A number makes that grade and above managers.
- `society` is the bank/society account used for Funds.

## Placing points

Use `/bossmenu` in game (admins only):

- **Add boss desk**: pick the job or gang, aim at the spot, press **E** (Backspace cancels), then pick a size.
- **Add applications point**: same, but only for jobs with applications on.
- **Add application review point**: where managers review that job's applications (for example an HR office),
  without needing the boss desk. Only that job's managers (and admins) see it.
- **Manage points**: everything placed, grouped by job. **Teleport** to a point, **Move** it (aim at the new spot,
  press E; it keeps its job, type and size), **Change size**, or **Delete** it.
  Points from `Config.locations`, or added by other scripts, can't be changed in game.

Boss desks and review points only show to that job's managers (and admins). Application points show to everyone.

## Checking your applications

`/applicationstatus` (or "My application status" at an application point) opens **My applications**:
every job you applied to, with the status (waiting, interview, accepted, denied), the interview message,
the deny reason and when you can apply again, who reviewed it, and your own answers. Manager notes are never shown.
Change or turn off the command with `applications.statusCommand`.

## Testing on your own

`/bossmenutest` (admins) opens test tools:

- **Add 4 test staff** to a job or gang: one on probation, one inactive, one ready for promotion with a commendation,
  and one regular. They're real offline characters (citizen IDs `BMTEST01`, `BMTEST02`, …) that nobody can log in as,
  so you can promote, demote, write up, commend, set callsigns and fire them.
- **Add 3 test applications** using the job's current form: two waiting, one invited to an interview. Accepting one hires that test character.
- **Previews** of the promotion celebration, the hire offer popup and the announcement popup.
- **Remove all test data**: deletes every test character and everything linked to them.

Things that need a real second player: hiring someone nearby (consent popup + handshake) and bonuses (paid to online players).
Turn the command off with `testCommand = false` once you go live.

## Building the application form

Boss menu → Applications → **Edit application form**:

- **Add question**: question text, type (Short answer, Long answer, Number, Dropdown, Checkbox) and Required,
  then what that type needs: min/max length, min/max number, or the dropdown options (one per line, 2-10).
- Pick a question to **Edit**, **Move up**, **Move down** or **Delete** it.
- **Edit intro text** (up to 500 characters), **Preview form** (exactly what applicants see, nothing is sent).
- Changes are a draft until **Save form**. Leaving with unsaved changes asks "Discard changes?".
- **Reset to default** deletes the saved form and goes back to `Config.applications.defaultQuestions`.

The applicant's full name always comes from their character. It is never a question.

## Config options

| Option | What it does |
|---|---|
| `enabled` | `false` = the whole resource does nothing. Saved data stays in the database. |
| `versionCheck` | On start, compare with the latest GitHub release and say if there's an update. |
| `useLationUI` | `true` = menus, forms and confirms use Lation UI. Falls back to ox_lib if lation_ui isn't started. |
| `target` | `'auto'`, `'ox_target'`, `'qb-target'` or `'none'` (walk-up `[E]` prompt). |
| `adminAce` | Ace for `/bossmenu` and admin overrides. Framework admins also count. |
| `adminsCanManage` | Admins can open and use any configured job's or gang's boss menu. |
| `hireDistance` | How close (m) someone must be to be hired. |
| `hireConsent` / `hireConsentSeconds` | Accept/Decline popup for the person being hired, and how long they have. |
| `contract.*` | Employment contract: `enabled`, `style` (`'paper'` mouse / `'typed'`), `seconds`, `requireExactName` (typed), `animation`, `editor` (`'management'` / `'admin'` / `false`), `template`. |
| `activity.*` | Duty hours: on/off, shortest shift saved, days kept, date format. |
| `gradeEditor` | In-game rank editor (Qbox, also needs `qbx:enableGroupManagement "true"`). |
| `qbxManagementCompat` | Answer qbx_management exports and qb-bossmenu events while qbx_management is stopped. |
| `jobs` / `gangs` | Which groups get a boss menu, and their per-group switches. |
| `applications.enabled` | `false` = applications off everywhere (the boss menu still works). |
| `applications.startOpen` | Whether applications start open. Managers can open/close them in game. |
| `applications.denyCooldownHours` | Wait after a denial before applying to the same job again. |
| `applications.statusCommand` | Command for "My applications" (default `applicationstatus`), or `false` for none. |
| `applications.formEditor` | `'management'` (managers + admins), `'admin'` (admins only) or `false` (no in-game editing). |
| `applications.maxQuestions` | Most questions a form can have. |
| `applications.intro` / `defaultQuestions` | The starting form for every job. |
| `funds.enabled` | `false` = no Funds anywhere. |
| `funds.confirmAbove` | Deposits/withdrawals of this amount or more ask to confirm. |
| `funds.historyLimit` | Transactions shown in Recent history. |
| `applications.allowWithdraw` / `votes` / `interviewCheckIn` | Applicant withdraw, manager 👍/👎 votes, interview check-in at the review point. |
| `applications.quickReplies` | Ready-made `deny` and `interview` messages. |
| `funds.bonuses` / `maxBonus` / `payroll` | Bonuses from society funds, biggest bonus per person, the Payroll page. |
| `jobs[x].description` | Text shown on the `/jobs` board. |
| `jobs[x].promotionHours` | `{ [rank] = hours }` needed to show "Ready for promotion". |
| `jobs[x].withdrawLimits` | `{ [rank] = amount }` most that rank can withdraw + pay in bonuses per day. |
| `jobs[x].starterItems` | `{ { item = 'radio', count = 1 } }` given to new hires. |
| `features.profiles` / `records` | Employee profiles (+ `/myjob`) and commendations / write-ups. |
| `features.probationDays` / `inactiveDays` | Probation length and the Inactive badge (0 = off). |
| `features.announcements` / `employeeOfWeek` / `auditLog` | Announcements, Employee of the Week, Activity log (`auditShow`, `auditKeepDays`). |
| `features.celebrations` / `handshake` | On-screen celebrations and the hire handshake. |
| `features.myJobCommand` / `jobBoardCommand` | `/myjob` and `/jobs` command names, or `false`. |
| `features.phoneMail` | Send application results by sd-phone mail. |
| `features.receptionist` | NPC at applications points: `enabled`, `model`, `scenario`, `greet`. |
| `locations` | Fixed points from config (added to the ones placed in game). |
| `logs.*` | Console, ox_lib logger, Discord, and each event on/off. |

### On/off switches (all enforced on the server)

- **Whole resource**: `enabled = false`. Nothing loads; saved points come back when turned on.
- **Per job**: a job not in `jobs` gets nothing, and the server refuses everything for it.
- **Applications**: on for a job only if `applications.enabled` **and** `jobs[job].applications`.
- **Form editor**: `applications.formEditor = false` hides "Edit application form" and the server refuses edits.
- **Funds**: on only if `funds.enabled` **and** `jobs[job].funds` **and** a supported banking resource is running.

## Discord logs

Set `set blaze_bossmenu_webhook "https://discord.com/api/webhooks/..."` in `server.cfg`.
The webhook is **never** read from a file, so it can't end up in the repo. Logs are batched to stay under Discord's rate limit.
Events: hire, fire, promote, demote, callsign, accept, deny, interview, deposit, withdraw, toggle, formEdit,
formReset, placement, gradeEdit, record, eotw, announce, bonus, withdrawApp, checkin. Turn single events off in `Config.logs.events`.

## Lation UI

`useLationUI` is optional. Lation UI isn't a dependency and no Lation files are included.
With it on: confirm popups get colours (red for Fire/Deny, orange for Withdraw/Reset), Fire shows a
"This removes them from the job" note, and staff icons are coloured (green on duty, gray offline).
If your server runs **Lation's ox_lib fork**, ox_lib itself forwards menus to lation_ui while it's started,
so you'll see Lation UI even with `useLationUI = false`.

## Exports

Client:

```lua
exports.blaze_bossmenu:openBossMenu('ambulance')          -- opens if the player manages that job
exports.blaze_bossmenu:openApplication('ambulance')       -- the apply flow
exports.blaze_bossmenu:openApplicationStatus('ambulance') -- shows their application status
```

Server:

```lua
exports.blaze_bossmenu:isManager(source, 'ambulance')        -- true/false (jobs)
exports.blaze_bossmenu:isManager(source, 'lostmc', 'gang')   -- gangs
```

qbx_management-style exports, also answered as `exports.qbx_management:*` while qbx_management is stopped:

```lua
-- client
exports.blaze_bossmenu:OpenBossMenu('job')  -- or 'gang'
local id = exports.blaze_bossmenu:AddBossMenuItem({ title = 'My item', icon = 'fa-solid fa-star', event = 'my:event', args = { type = 'job' } })
exports.blaze_bossmenu:RemoveBossMenuItem(id)  -- AddGangMenuItem / RemoveGangMenuItem for gangs
-- server
exports.blaze_bossmenu:RegisterBossMenu({ groupName = 'ambulance', type = 'job', coords = vec3(0, 0, 0) })
```

Events `qb-bossmenu:client:OpenMenu` and `qb-gangmenu:client:OpenMenu` open the job / gang menu.

## Database tables

`blaze_boss_applications`, `blaze_boss_forms`, `blaze_boss_callsigns`, `blaze_boss_fund_log`,
`blaze_boss_settings`, `blaze_boss_points`, `blaze_boss_members`, `blaze_boss_records`, `blaze_boss_audit`,
`blaze_boss_announcements`, `blaze_boss_eotw`, `blaze_boss_app_votes`, `blaze_boss_contract_templates`, `blaze_boss_contracts`, plus `player_jobs_activity` and `management_groups`
(the same tables qbx_management used).

## License

GPL-3.0. See `LICENSE` and `NOTICE.md`.
