# Notice

blaze_bossmenu is a fork of **qbx_management** by the Qbox Project
(https://github.com/Qbox-project/qbx_management, version 1.4.0), licensed under the
GNU General Public License v3.0. blaze_bossmenu is therefore also licensed under GPL-3.0
(see `LICENSE`).

## What comes from qbx_management

- The boss menu flow: staff list, hire nearby players, promote/demote, fire (online and offline).
- The hire consent popup shown to the person being hired.
- Duty hours tracking (`player_jobs_activity` table: check-in/check-out, hours, last check-in, 31-day cleanup).
- In-game grade editor (Qbox, `qbx:enableGroupManagement`) and its `management_groups` table,
  loaded into qbx_core with `CreateJobs` / `CreateGangs` on start.
- Gang menus.
- The `OpenBossMenu`, `AddBossMenuItem` / `AddGangMenuItem`, `RemoveBossMenuItem` / `RemoveGangMenuItem`
  and `RegisterBossMenu` exports, and the `qb-bossmenu:client:OpenMenu` / `qb-gangmenu:client:OpenMenu` events.

The table names `player_jobs_activity` and `management_groups` are kept the same so a server
switching from qbx_management keeps its hours and edited grades.

## Changes in blaze_bossmenu

- Runs on Qbox **and** QBCore through a framework bridge (`bridge/server/framework.lua`).
- Job application system with an in-game form builder, society funds, callsigns,
  in-game placement of points, configurable rank rules, admin overrides, ox_lib / Lation UI menus,
  and console / ox_lib / Discord logging.
