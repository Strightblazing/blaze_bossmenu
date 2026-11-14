# Notice

**blaze_bossmenu**
Copyright (C) 2026 Blaze

This program is free software: you can redistribute it and/or modify it under the terms of the
GNU General Public License as published by the Free Software Foundation, version 3 of the License.
It is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied
warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See `LICENSE` for the full text.

## Based on qbx_management

blaze_bossmenu is a fork of **qbx_management** by the **Qbox Project**
(https://github.com/Qbox-project/qbx_management, version 1.4.0), licensed under the GNU General Public
License v3.0. Because of that, blaze_bossmenu is licensed under GPL-3.0 too, and any copy or modified
version you share must stay under GPL-3.0 with its source code available.

### What comes from qbx_management

- The boss menu flow: staff list, hire nearby players, promote/demote, fire (online and offline).
- The hire consent popup shown to the person being hired.
- Duty hours tracking (`player_jobs_activity` table: check-in/check-out, hours, last check-in, 31-day cleanup).
- The in-game grade editor (Qbox, `qbx:enableGroupManagement`) and its `management_groups` table,
  loaded into qbx_core with `CreateJobs` / `CreateGangs` on start.
- Gang menus.
- The `OpenBossMenu`, `AddBossMenuItem` / `AddGangMenuItem`, `RemoveBossMenuItem` / `RemoveGangMenuItem`
  and `RegisterBossMenu` exports, and the `qb-bossmenu:client:OpenMenu` / `qb-gangmenu:client:OpenMenu` events.

The table names `player_jobs_activity` and `management_groups` are kept the same so a server switching
from qbx_management keeps its hours and edited grades.

### What blaze_bossmenu changes and adds (2026)

- Runs on Qbox **and** QBCore through a framework bridge (`bridge/server/framework.lua`, `bridge/client/framework.lua`).
- Job applications with an in-game form builder, review points, votes, quick replies, withdraw, interview check-in,
  `/applicationstatus` and a `/jobs` board.
- Society funds with bonuses, payroll and per-rank daily limits; callsigns; commendations and write-ups;
  probation; Employee of the Week; announcements; an activity log; employee profiles and `/myjob`.
- An employment contract signed with the mouse, with per-job templates edited in game.
- A time clock with tap / swipe / PIN clock-in, live shift and hours data.
- Job outfits and wardrobes; duty points; in-game placement for admins and managers; a radial menu entry.
- Phone number / email lookup from popular phone resources; sd-phone mail.
- Debug tools (`/bossdebug` live panel, Show zones) and test tools (`/bossmenutest`).
- ox_lib / Lation UI menus, configurable rank rules, admin overrides, and console / ox_lib / Discord logging.

## Third-party material

- **Fonts** used by the web screens (Inter, JetBrains Mono, Libre Baskerville, Barlow: SIL Open Font License 1.1;
  Homemade Apple: Apache License 2.0) are loaded from Google Fonts
  at runtime. They are not included in this repository.
- **Icons** in menus are Font Awesome icon names, drawn by ox_lib / Lation UI. No icon files are included.
- Exports of other resources (frameworks, banking, phone, inventory, appearance and target scripts) are only
  called when those resources are running. None of their code is included.
