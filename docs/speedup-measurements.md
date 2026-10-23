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
