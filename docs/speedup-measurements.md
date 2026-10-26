# Speedup measurements

Measured 2026-10-23 by the verifier on master (91e82bd). 11-script subset: t100-rankings t100-reports t100-tech-tree t100-civics-tree t100-great-people t100-city-report early-cursor-and-next early-quick-yields early-unavailable-screens t128-city-attack t128-attack-targets.

## Baseline (before)

Run 1, default (every named script loads fresh): TOTAL 16 m 12 s, 97 checks passed, 0 failed.

```
TIMING:   (per script: wall time, verdict, [where it went, seconds])
  t100-rankings              1 m 42 s  PASS  [load 40, keys 48 (settle 14), advisors 14 s]
  t100-reports               1 m 54 s  PASS  [load 39, keys 61 (settle 17), advisors 14 s]
  t100-tech-tree             1 m 37 s  PASS  [load 38, keys 45 (settle 11), advisors 14 s]
  t100-civics-tree           1 m 42 s  PASS  [load 40, keys 48 (settle 11), advisors 14 s]
  t100-great-people          1 m 35 s  PASS  [load 39, keys 37 (settle 14), lua 1, advisors 17 s]
  t100-city-report           1 m 19 s  PASS  [load 38, keys 28 (settle 9), advisors 14 s]
  early-cursor-and-next          56 s  PASS  [load 41, keys 15 (settle 4) s]
  early-quick-yields             43 s  PASS  [load 40, keys 3 (settle 1) s]
  early-unavailable-screens  1 m 06 s  PASS  [load 40, keys 23 (settle 9), advisors 3 s]
  t128-city-attack           1 m 10 s  PASS  [load 37, keys 14 (settle 6), wait 11, lua 2, advisors 6 s]
  t128-attack-targets        2 m 29 s  PASS  [load 38, keys 87 (settle 25), wait 15, lua 3, advisors 6 s]
BREAKDOWN: load 7 m 09 s (11 loads), keys 6 m 49 s of which settle sleeps 2 m 02 s, wait 26 s, lua 6 s, advisors 1 m 42 s, other 0 s
```

Run 2, `--share-load` (control): TOTAL 16 m 09 s, 97 passed. No load was shared: every script carries `# no-share-load`, so this equals run 1.

```
TIMING:   (per script: wall time, verdict, [where it went, seconds])
  t100-rankings              1 m 39 s  PASS  [load 37, keys 48 (settle 14), advisors 14 s]
  t100-reports               1 m 47 s  PASS  [load 38, keys 55 (settle 17), advisors 14 s]
  t100-tech-tree             1 m 37 s  PASS  [load 38, keys 45 (settle 11), advisors 14 s]
  t100-civics-tree           1 m 40 s  PASS  [load 38, keys 48 (settle 11), advisors 14 s]
  t100-great-people          1 m 34 s  PASS  [load 38, keys 38 (settle 14), lua 1, advisors 17 s]
  t100-city-report           1 m 21 s  PASS  [load 39, keys 28 (settle 9), advisors 14 s]
  early-cursor-and-next          57 s  PASS  [load 42, keys 15 (settle 4) s]
  early-quick-yields             45 s  PASS  [load 41, keys 3 (settle 1) s]
  early-unavailable-screens  1 m 07 s  PASS  [load 41, keys 23 (settle 9), advisors 3 s]
  t128-city-attack           1 m 12 s  PASS  [load 38, keys 15 (settle 6), wait 12, lua 2, advisors 6 s]
  t128-attack-targets        2 m 30 s  PASS  [load 38, keys 88 (settle 25), wait 14, lua 3, advisors 6 s]
BREAKDOWN: load 7 m 08 s (11 loads), keys 6 m 48 s of which settle sleeps 2 m 02 s, wait 26 s, lua 6 s, advisors 1 m 41 s, other 0 s
```

Where the time goes (run 1): load 7 m 09 s (11 loads, ~38-41 s each), keys 6 m 49 s (of which scripted settle sleeps only 2 m 02 s, so ~4 m 47 s is per-call overhead), advisors 1 m 42 s, wait 26 s, lua 6 s.

## Game options experiments

User values (restored at the end, UserOptions.txt identical to backup): QuickCombat 0, QuickMovement 0, LookAtPlayerTurnCombat 2, LookAtPlayerOffTurnCombat 1, TutorialLevel 0, PlayHistoricMomentAnimation 1.

Notes: UserOptions.txt has two `[Gameplay]` sections; QuickCombat/QuickMovement/LookAt* are in the first, `PlayHistoricMomentAnimation` is under `[Interface]`.

1. Tuner calls work in the `InGame` state (has `Options` and `UserConfiguration`):
   - `Options.SetUserOption("Gameplay", "QuickCombat", 1)` only changes the Options value (UserConfiguration stays 0).
   - `UserConfiguration.SetValue("QuickCombat", 1)` is what the game logic reads (Options.lua applies it the same way on Confirm).
   - Neither writes the file. `Options.SaveOptions()` writes UserOptions.txt (it is `SaveOptions`, not SaveUserOptions); after it the file showed `QuickCombat 1`.
   - Full set used: `for _,k in ipairs({"QuickCombat","QuickMovement"}) do Options.SetUserOption("Gameplay",k,1); UserConfiguration.SetValue(k,1) end; Options.SetUserOption("Gameplay","LookAtPlayerTurnCombat",0); Options.SetUserOption("Gameplay","LookAtPlayerOffTurnCombat",0); Options.SetUserOption("Interface","PlayHistoricMomentAnimation",0)`. LookAt* and PlayHistoricMomentAnimation are read directly via Options.GetUserOption (CameraManager.lua), so SetUserOption is enough. No SaveOptions needed for the running game.
2. QuickCombat/QuickMovement take effect immediately in the loaded game (advance 5 got faster with no reload), and they survive later `load`s within the same game process (UserConfiguration stayed 1/1 after `load medieval-t100`). The save does not override them.
3. TutorialLevel: with `Options.SetUserOption("Gameplay","TutorialLevel",-1); UserConfiguration.SetValue("TutorialLevel",-1)`, `load medieval-t100 -KeepAdvisors` then `menu` says "no popup or screen open". With level 0 the same load shows `POPUP/SCREEN OPEN: ADVISOR:AdvisorPopup` (several advisor popups). The save carries no tutorial level of its own; the setting persists across loads in the process. So with -1 no clear-advisors is needed (the step still costs ~6 s of probing in the runner: skip it when the level is -1).
4. `load medieval-t100` + `advance 5` (load itself ~50 s incl. advisor clearing):
   - user options: 1 m 50 s (110 s)
   - QuickCombat 1, QuickMovement 1, both LookAt 0, HistoricMoment 0: 48 s. Saves ~62 s per 5 AI turns (56 %).
5. `regress t128-city-attack t128-attack-targets` with the quick options on (and tutorial -1): both PASS, 14 checks. Total 3 m 27 s vs 3 m 39 s baseline. t128-city-attack 1 m 03 s (was 1 m 10 s), t128-attack-targets 2 m 24 s (was 2 m 29 s); wait steps shrank (11 -> 3 s, 15 -> 6 s). Little gain: these scripts are dominated by load and key overhead.

## Key overhead

- `powershell -NoProfile -ExecutionPolicy Bypass -File util/civctl.ps1 status`: 1.56, 1.53, 1.52 s per call (process cost, no game interaction).
- World Rankings open (F1), `key Down -Settle N`, wall time per call (3 runs each): N=600: 3.63/3.57/3.55 s; N=300: 3.29/3.23/3.33 s; N=150: 3.21/3.15/3.08 s; N=0: 2.93/2.90/3.23 s. Every run printed its own speech line, nothing arrived late (a following `sr` after each batch returned nothing). Even N=0 got the full line, because the fixed per-call work (focus, crash check, log read) already takes ~1.4 s after the 1.5 s process start.
- So the fixed cost is ~2.9 s per key call and settle contributes little; speedups must come from cutting that fixed cost (long-lived process, no repeated checks), not the settle. Recommended quiet window: 150 ms or an adaptive "quiet for ~150 ms" with a cap; 0 worked here for a short Down announcement, but screens that open need longer (the scripts use 1500-3000).

# Phase 2: the three branches merged one stage at a time

Same 11-script subset S. Each stage was run on top of the previous one.

## Stage 1: keys (speed-keys: quiet window, `civctl batch` host, CIVCTL_PROFILE)

First attempt: 74 checks passed, 22 failed, 1 aborted. Cause 1 (harness bug): back-to-back tuner calls from the batch host hit "FireTuner busy" (the handshake returned no states while the game was still dropping the previous client) so `clear-advisors` and a `load` failed. Fixed in civtuner.py (handshake retried up to 5 times, 0.7 s apart; commit 77f6006). Cause 2 (scripts relying on the fixed sleep): the quiet window makes `-Settle` a maximum, so keys whose speech comes after a pause return too early: the search result after Enter in t100-tech-tree / t100-civics-tree ("Found:"), the combat result in t128-city-attack, the move order in t128-attack-targets (the next unit selection happened while the unit still moved). Those four keys got `-NoQuiet` (b929938). One more failure of t128-attack-targets in the same run did not reproduce in 3 reruns.

Final stage-1 run (default fresh loads): SUMMARY: 11 scripts, 97 checks passed, 0 failed
TOTAL: 8 m 17 s

```
TIMING:   (per script: wall time, verdict, [where it went, seconds])
  t100-rankings                  47 s  PASS  [load 32, keys 8 (settle 6), advisors 7 s]
  t100-reports                   47 s  PASS  [load 32, keys 8 (settle 6), advisors 8 s]
  t100-tech-tree                 45 s  PASS  [load 31, keys 7 (settle 5), advisors 7 s]
  t100-civics-tree               47 s  PASS  [load 31, keys 7 (settle 6), advisors 8 s]
  t100-great-people              47 s  PASS  [load 32, keys 7 (settle 5), lua 1, advisors 8 s]
  t100-city-report               44 s  PASS  [load 31, keys 5 (settle 4), advisors 8 s]
  early-cursor-and-next          36 s  PASS  [load 33, keys 3 (settle 2) s]
  early-quick-yields             34 s  PASS  [load 34, keys 0 (settle 0) s]
  early-unavailable-screens      39 s  PASS  [load 33, keys 6 (settle 4), advisors 1 s]
  t128-city-attack               52 s  PASS  [load 31, keys 6 (settle 5), wait 12, lua 1, advisors 2 s]
  t128-attack-targets        1 m 00 s  PASS  [load 32, keys 12 (settle 10), wait 12, lua 2, advisors 2 s]
BREAKDOWN: load 5 m 51 s (11 loads), keys 1 m 08 s of which settle sleeps 54 s, wait 24 s, lua 4 s, advisors 51 s, other 0 s
```

Checks: `civctl key Down` from a normal shell prints no `@@` lines; a Control+Tab chord releases (the next Down behaved normally); `--no-batch` on early-quick-yields passes. Profile of one `key Down` in World Rankings (`CIVCTL_PROFILE=1`, ms): init 257, health1 89, focus 10, pending 46, pre 7, send 55, wait 286, log 15, health2 24, total ~790 (before: ~2900 per call from a separate powershell.exe: 1520 process start + ~1400 checks + settle).

What changed: keys 6 m 49 s -> 1 m 08 s; loads unchanged (~31 s each).

## Stage 2: share (speed-share: HubCore.TestResetState, reset check, fewer no-share-load)

The merge was not a fast-forward (stage-1 fixes on master), done as a merge commit. `deploy` copies HubCore.lua, but the hub did not re-include it: `civctl reload InGameAccess.lua` was needed before `HubCore.TestResetState` existed. First run: every reset baseline failed with `HubCore.lua:148: function expected instead of nil`: a unit has no `GetActivityType`, it is `UnitManager.GetActivityType(unit)`. Fixed (8aebaff); `TestResetState()` then returns `clean ...` in the tuner. Run S `--share-load`: SUMMARY: 11 scripts, 97 checks passed, 0 failed
TOTAL: 5 m 17 s

```
TIMING:   (per script: wall time, verdict, [where it went, seconds])
  t100-rankings                  49 s  PASS  [load 32, keys 8 (settle 6), advisors 7 s]
  t100-reports                    9 s  PASS  [load 0, keys 8 (settle 6), advisors 1 s]
  t100-tech-tree                  9 s  PASS  [load 0, keys 7 (settle 5), advisors 1 s]
  t100-civics-tree                9 s  PASS  [load 0, keys 7 (settle 6), advisors 1 s]
  t100-city-report                6 s  PASS  [load 0, keys 5 (settle 4), advisors 1 s]
  t100-great-people              47 s  PASS  [load 31, keys 7 (settle 5), lua 1, advisors 9 s]
  early-quick-yields             35 s  PASS  [load 33, keys 0 (settle 0) s]
  early-unavailable-screens       6 s  PASS  [load 0, keys 6 (settle 4), advisors 1 s]
  early-cursor-and-next          36 s  PASS  [load 33, keys 3 (settle 2) s]
  t128-city-attack               52 s  PASS  [load 32, keys 6 (settle 5), wait 12, lua 1, advisors 2 s]
  t128-attack-targets            59 s  PASS  [load 31, keys 12 (settle 10), wait 12, lua 2, advisors 2 s]
BREAKDOWN: load 3 m 11 s (6 loads, 5 saved by sharing; reset checks: 7, 6 s), keys 1 m 08 s of which settle sleeps 54 s, wait 24 s, lua 3 s, advisors 24 s, other 0 s
```

Every reset check printed "reset check: clean" (7 checks, 6 s in total); 5 of the 11 loads were saved (the t100 and early-start groups). What changed: load 5 m 50 s -> 3 m 11 s.

## Stage 3: options (speed-options: testopts, `# options:`, advisor off)

Run S `--share-load`: SUMMARY: 11 scripts, 97 checks passed, 0 failed
TOTAL: 5 m 02 s

```
TIMING:   (per script: wall time, verdict, [where it went, seconds])
  t100-rankings                  41 s  PASS  [load 31, keys 8 (settle 6) s]
  t100-reports                    9 s  PASS  [load 0, keys 8 (settle 6) s]
  t100-tech-tree                  8 s  PASS  [load 0, keys 7 (settle 5) s]
  t100-civics-tree                8 s  PASS  [load 0, keys 7 (settle 6) s]
  t100-city-report                5 s  PASS  [load 0, keys 5 (settle 4) s]
  t100-great-people              39 s  PASS  [load 31, keys 7 (settle 6), lua 1 s]
  early-quick-yields             35 s  PASS  [load 33, keys 0 (settle 0) s]
  early-unavailable-screens       5 s  PASS  [load 0, keys 5 (settle 4) s]
  early-cursor-and-next          36 s  PASS  [load 33, keys 3 (settle 2) s]
  t128-city-attack               52 s  PASS  [load 31, keys 6 (settle 5), wait 12, lua 1 s]
  t128-attack-targets            59 s  PASS  [load 31, keys 12 (settle 10), wait 12, lua 2 s]
BREAKDOWN: load 3 m 11 s (6 loads, 5 saved by sharing; reset checks: 7, 6 s), keys 1 m 08 s of which settle sleeps 54 s, wait 24 s, lua 4 s, advisors 0 s, other 1 s
```

The advisor is off (advisors 0 s; was 52 s); t128-* print "(options: animations at the user's values)" and still pass. Problem found: after the run UserOptions.txt differed from the backup (`TutorialLevel -1`, and after the advisor-popup run all five animation keys): the game rewrites the file with the in-memory values at some events (loads), so "in memory only" does not keep the file clean. `testopts restore` now also calls `Options.SaveOptions()` through the tuner (ec4b46b); verified: file identical to the backup afterwards, no testopts-backup.json left, `civctl status` prints no warning. A crash during a run can still leave test values in the file (the backup json is kept then; `python util/testopts.py restore`). `advisor-popup` recorded (passes; one expect added: `^Tell me more, 2 of 2$`) and marked verified.

## Stage 4: one `regress all`

SUMMARY: 49 scripts, 360 checks passed, 2 failed
TOTAL: 26 m 11 s

(the one failing script, world-congress, was rerun alone: 13 passed). Cause: `key N -Settle 45000` slept out the AI turn before; with the quiet window it returns after "votes submitted" and the results screen was not up yet. The script now has `wait World Congress results\. -Timeout 60` after it.

```
TIMING:   (per script: wall time, verdict, [where it went, seconds])
  religion                                 39 s  PASS  [load 34, keys 4 (settle 3) s]
  t100-city-report                          6 s  PASS  [load 0, keys 5 (settle 4) s]
  t100-civics-tree                          8 s  PASS  [load 0, keys 7 (settle 6) s]
  t100-rankings                             8 s  PASS  [load 0, keys 8 (settle 6) s]
  t100-reports                              8 s  PASS  [load 0, keys 7 (settle 6) s]
  t100-tech-tree                            8 s  PASS  [load 0, keys 7 (settle 5) s]
  t100-trade-overview                       8 s  PASS  [load 0, keys 8 (settle 7) s]
  advisor-popup                            38 s  PASS  [load 33, keys 2 (settle 2) s]
  bug-diplo-advisor-deferred               47 s  PASS  [load 31, keys 6 (settle 5), advisors 8 s]
  religion-found                           41 s  PASS  [load 31, keys 8 (settle 7), lua 2 s]
  t100-chooser-closes-on-v                 35 s  PASS  [load 31, keys 4 (settle 3) s]
  t100-chooser-enter-guard                 34 s  PASS  [load 31, keys 3 (settle 2) s]
  t100-city-manage                         48 s  PASS  [load 32, keys 17 (settle 14) s]
  t100-deal                                42 s  PASS  [load 31, keys 11 (settle 9) s]
  t100-espionage                           44 s  PASS  [load 32, keys 11 (settle 9), lua 2 s]
  t100-great-people                        39 s  PASS  [load 31, keys 7 (settle 6), lua 1 s]
  t100-trade-route                         38 s  PASS  [load 31, keys 4 (settle 3), wait 1, lua 3 s]
  bug-city-attack-reason                   37 s  PASS  [load 32, keys 4 (settle 3) s]
  bug-city-ranged-attack-item3             38 s  PASS  [load 31, keys 3 (settle 3), lua 1 s]
  bug-city-ranged-attack-notification      37 s  PASS  [load 31, keys 3 (settle 3) s]
  bug-enter-opens-governors-item2          35 s  PASS  [load 31, keys 2 (settle 2), lua 1 s]
  bug-espionage-popup                      31 s  PASS  [load 31, keys 0 (settle 0) s]
  bug-settler-cannot-skip-only             33 s  PASS  [load 31, keys 2 (settle 2) s]
  bug-settler-no-skip-delete-confirm       37 s  PASS  [load 31, keys 5 (settle 5) s]
  bug-settler-no-skip-item1                36 s  PASS  [load 31, keys 4 (settle 3) s]
  early-quick-yields                       34 s  PASS  [load 32, keys 0 (settle 0) s]
  early-unavailable-screens                 6 s  PASS  [load 0, keys 5 (settle 4) s]
  early-cursor-and-next                    36 s  PASS  [load 32, keys 3 (settle 2) s]
  early-start-blocked-hotkeys              34 s  PASS  [load 32, keys 2 (settle 1) s]
  early-turn-announce                      32 s  PASS  [load 32, keys 0 (settle 0) s]
  early-t60-government-escape              35 s  PASS  [load 31, keys 2 (settle 2) s]
  early-t60-government-tabs                 4 s  PASS  [load 0, keys 4 (settle 3) s]
  early-t60-screens-open                   11 s  PASS  [load 0, keys 10 (settle 7) s]
  t60-civilopedia                          11 s  PASS  [load 0, keys 10 (settle 8), lua 1 s]
  early-t60-civic-popup-keys               36 s  PASS  [load 31, keys 2 (settle 2), lua 2 s]
  early-t60-completed-popup-once           34 s  PASS  [load 31, keys 1 (settle 1), lua 2 s]
  t60-builder-by-forest                    34 s  PASS  [load 31, keys 1 (settle 1), lua 2 s]
  t60-enemy-at-capital                     33 s  PASS  [load 31, keys 1 (settle 1), lua 1 s]
  t60-envoys-to-give                       34 s  PASS  [load 31, keys 2 (settle 2), lua 1 s]
  t60-governor-title                       35 s  PASS  [load 31, keys 2 (settle 2), lua 1 s]
  t60-save-load-menus                      42 s  PASS  [load 31, keys 11 (settle 9) s]
  era-dedication                           35 s  PASS  [load 31, keys 4 (settle 3) s]
  promotion                                35 s  PASS  [load 31, keys 2 (settle 2), lua 1 s]
  t100-climate                             40 s  PASS  [load 32, keys 7 (settle 5) s]
  t100-great-works                         39 s  PASS  [load 32, keys 4 (settle 3), lua 2 s]
  t100-unit-position                       34 s  PASS  [load 31, keys 0 (settle 0), lua 3 s]
  t128-attack-targets                  1 m 00 s  PASS  [load 31, keys 12 (settle 10), wait 12, lua 2 s]
  t128-city-attack                         52 s  PASS  [load 31, keys 6 (settle 5), wait 12, lua 1 s]
  world-congress                           42 s  FAIL  [load 31, keys 11 (settle 10) s]
BREAKDOWN: load 20 m 31 s (39 loads, 10 saved by sharing; reset checks: 13, 12 s), keys 4 m 06 s of which settle sleeps 3 m 20 s, wait 25 s, lua 26 s, advisors 8 s, other 2 s
```

## Summary

| Stage | Subset S TOTAL | Loads | Keys | Advisors |
|---|---|---|---|---|
| Baseline | 16 m 12 s | 7 m 09 s (11) | 6 m 49 s | 1 m 42 s |
| 1 keys | 8 m 17 s | 5 m 51 s (11) | 1 m 08 s | 51 s |
| 2 share | 5 m 17 s | 3 m 11 s (6) | 1 m 08 s | 24 s |
| 3 options | 5 m 02 s | 3 m 11 s (6) | 1 m 08 s | 0 s |

Full `regress all`: 26 m 11 s (49 scripts, 360 checks passed, 1 script failed and fixed) against about 62 min before (34 scripts at the time; now 49). Per key call: ~2.9 s before, ~0.8 s after (World Rankings, Down).

## Game settings experiment (2026-10-26)

Goal: do game config settings (`AppOptions.txt`, `GraphicsOptions.txt`, read at game start) make `civctl load` faster? Each configuration: `stop` + `start`, then 5 timed `civctl load` calls alternating medieval-t100 / early-t60 / medieval-t100 / early-t60 / medieval-t100 (wall time of the whole command, incl. advisor clearing; the regress BREAKDOWN "load" figure is ~15 s lower and is the comparable number to the earlier sections). The user's files were backed up first and restored byte-identical at the end.

| Config | Start to main menu | Loads, wall (M, E, M, E, M) | Notes |
|---|---|---|---|
| 0 Baseline | 42 s (cold; ~29 s warm) | 54, 46, 47, 45, 49 s (avg 48) | |
| 1 `LoadGameTickIntervalInMS` 16 -> 1 | 29 s | 50, 50, 51, 50, 54 s (avg 51) | no gain (within noise, not better); 0 not tried |
| 2 `EnableAsserts` 0 | 29 s | 43, 44, 47, 44, 48 s (avg 45) | about -3 s, small |
| 3 Low graphics preset (all keys of the task; TerrainSynthesisDetailLevel 2 = low-res, not 0, per the file comment) | 28 s | 38, 38, 42, 38, 42 s (avg 40) | about -8 s (-17%), the one real win |
| 4 `UIOnlyRendering` 1 (alone) | 28 s | 43, 44, 46, 44, 46 s (avg 45) | game runs, `key` gives SR> lines, `regress t100-chooser-flow` (mouse + click) PASS; only ~-3 s, no gain on top of 3 |
| 5 `AddMinimapSnapshotToSaves` 0 | n/a | `save` 3.6 s vs 3.6-3.7 s | no time difference; save file 60 KB smaller (908 vs 969 KB) |
| 6a 3 + 2 (low graphics + asserts off) | 27 s | 38, 39, 42, 39, 42 s (avg 40) | best; in `regress` BREAKDOWN a load is 28 s vs 31-32 s before |
| 6b 3 + 2 + 4 | 28 s | 38, 38, 42, 38, 42 s (avg 40) | UIOnlyRendering adds nothing |

Config 6a verification: `regress early-t60-places-list t100-chooser-flow t128-city-attack` 3 scripts, 29 checks passed, 0 failed (mouse/click flows fine), TOTAL 2 m 12 s. `advance 3` on medieval-t100: 77 s with 6a and 77 s with baseline, so AI turn speed is unchanged (CPU bound). Start-to-menu: 42 s on the first (cold) start, then 27-29 s for every config, so the restart time is not affected by the settings either.

Conclusion: only the low graphics preset helps (about 3-4 s of the ~31 s in-script load, -17% of wall time of a bare `load`); asserts off adds nothing measurable on top. A `regress all` with ~39 loads would save about 2-3 min of ~26. The cost is that the user's graphics settings change, so apply it to a test-only profile (swap the files in `civctl start`/`stop`) rather than the user's real files. Not worth: tick interval, UIOnlyRendering, minimap snapshot.
