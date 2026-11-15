# Changelog

## Unreleased

- **Blaze Scriptworks** branding: the startup banner is the logo as console art (red flame with </>, white BLAZE, gold
  SCRIPTWORKS, red bar, gold frame), no image or URL needed. Logo in the README (`docs/branding`).
- **Admin menu `/bossmenuadmin`** (`adminCommand`): boss menus for any job or gang with full access, points, Show zones,
  debug, test tools and a settings overview. The boss menu is roleplay only now: admin rights (`adminsCanManage`) only
  apply to a group opened from the admin menu, checked on the server; at desks and in the radial menu admins are
  treated like anyone else. Admin-only form / contract editing works from there too. The radial menu gets a separate
  **Boss admin** entry for admins (`radial.admin`). `/bossmenu` now just points admins to `/bossmenuadmin`.
- **Points can have a PED or a prop** (or stay invisible): picked when placing (`pointLooks` in config.lua: models,
  idle scenarios / animations, or type any model), changed later with **Change look**, also in `config.lua > locations`
  (`entity = { ... }`). PEDs stand still and never wander, flee or react. Targeting aims at the PED / prop itself, not
  the floor. The see-through preview is spawned like the real one (standing on the ground, not in it), turn it with
  **← →**, and **Move** keeps the look.
- **E prompts** (no target script): one prompt for the nearest point only, fires once per press, never while a menu is
  open, no prompts stacking on overlapping points. Duplicate points on one spot are registered once.
  `targetDistance` sets how close you must be with ox_target / qb-target.
- Placing points shows a live preview: the zone ring at its real size and color, the facing direction, and a
  see-through receptionist for application points. Size with the mouse wheel or arrow keys while aiming (no more typing
  it in); **Change size** previews the ring on the spot. A new placement card (web/place.html) replaces the ox_lib text
  prompt: type and job in its color, a live size bar, aim status and the keys. The game HUD hides while placing
  (`placementHud` in config.lua or the event `blaze_bossmenu:client:placing` for your HUD resource). **G** switches the output to copying a config.lua line instead
  of saving (admins, remembered on the PC; a FiveM key binding, rebindable, only active while placing).
- Fix: the receptionist at application points can be targeted (ox_target / qb-target), not just the floor at the point.
- Lighter: the debug panel and debug labels no longer check once a second on every client (they start only when an
  admin turns debug on), the Discord sender only runs when a webhook is set, and the time clock stops updating while closed.
- Debug panel size: 70-150% with the mouse wheel or − / + while moving it (`/bossdebug move`, or the new **Move / resize
  debug panel** button in `/bossmenu`), saved on the PC with its position.
- Cleanup: removed an unused variable and parameter, and the old docs/contract-preview.html redirect.

## 1.2.1

- Time clock full view is configurable (`duty.view`): `layout` = `full` / `standard` / `minimal`, single sections
  on or off, and which About you lines show. Phone and email that are turned off aren't looked up.
- Release images: showcase banner, feature cards and the time clock styles.
- Removed a stray image from the download.

## 1.2.0 (first public release)

**Time clock** (duty points, `duty.style = 'clock'`)
- Opens as a small clock-in panel: tap the virtual ID on the reader, swipe it, or type the PIN (keyboard works too).
- Off duty: the scan clocks you in and opens the full view. On duty: the scan only opens it; clock out by scanning
  again or pressing **Clock out**, then it closes.
- Full view: live shift timer, hours this week (per day) and the last 31 days, last shift, next rank with hours
  progress and pay, tags, About you (rank, callsign, phone, email, department, time employed, pay, record),
  department stats and who's on duty, the announcement.
- Clean neutral design, green / red on and off duty, subtle animations; size adjustable in game (80-160%),
  switching to a roomier layout from 130%; Escape or Backspace closes it.

**Employment contract**
- New hires sign a real-looking agreement with the mouse; it fills itself in from the job label, rank, pay,
  probation and the hiring manager's name and rank. Per-job templates edited in the boss menu; signed copies kept.

**Staff and departments**
- Duty points, job outfits and wardrobes (illenium-appearance auto-detected).
- Boss menu **Locations**: managers add, move, resize and delete their own job's points.
- Phone number and email from sd-phone, lb-phone, high-phone, qs-smartphone(-pro), 17mov_Phone and npwd.
- Radial menu **Work** entry for bosses.

**Admin tools**
- `/bossdebug on | off | view | move`: live debug panel, point labels and action logs. **Show zones** in `/bossmenu`.
- `/bossmenutest` **View as…**: see a job as a civilian, an employee or any rank.

**Fixes**
- QBCore: clocking in or out from the time clock now counts toward duty hours.
- Long ranks and callsigns no longer overlap on the ID card.

## 1.1.0

- Employee profiles and `/myjob`, commendations and write-ups, probation, inactivity and promotion-ready badges.
- Announcements, Employee of the Week, activity log, payroll, bonuses, daily withdrawal limits per rank.
- Application votes, quick replies, withdraw, interview check-in, `/jobs` board, sd-phone mail results.
- Celebrations, hire handshake, starter items, receptionist NPC at application points.
- `/bossmenutest` test tools; application review points and `/applicationstatus`.

## 1.0.0

- Fork of qbx_management (Qbox Project, GPL-3.0) for Qbox and QBCore: staff, hire with consent, promote,
  demote, fire, callsigns, duty hours, rank editor, gangs, qbx_management / qb-bossmenu compatibility.
- Job applications with an in-game form builder, society funds, in-game placement (`/bossmenu`),
  ox_lib / Lation UI menus, console / ox_lib / Discord logs, startup banner and version check.
