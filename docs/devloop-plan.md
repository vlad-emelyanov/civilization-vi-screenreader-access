# Dev loop plan: faster, reproducible play testing

Why: in the Phase 6 play-through (see `ingame-plan.md`) most of the time went to things other than code:
- Only one agent can drive the game, so implementation was serial.
- Situations were hard to trigger (attacks on cities, natural disasters, historic moments, governor blockers, make peace), so many fixes ended as "verified by a direct call" only.
- Crashes cost progress back to the last autosave, and a leftover `FiraxisBugReporter.exe` blocked `start`.
- Fixes were validated in whatever state the running game was in, not in the state where the bug was found.
- Agents rediscovered the same engine facts.

This plan fixes that in eight workstreams, in priority order. Each one: implement (sonnet agent), verify in game, commit, then update `CLAUDE.md` / the civ-test skill / the team-lead skill so later agents use it. Sections 1-4 rest on spikes run in game on 2026-10-22 (see "Spikes" at the end); the Lua snippets there are known to work.

## How saves were used in Phase 6 (the problem)

- Agents only had the quick save (one slot, overwritten all the time: batch B's testing replaced the turn-10 save) and the per-turn autosaves.
- When a play agent found a bug it did NOT save at that moment. The fix agent then tried to reproduce it in the current game, often at a later turn, via the tuner, or by calling the handler directly.
- Nobody replayed from turn 1, but nobody reloaded the exact moment either. After a crash, the agent continued from the autosave of the turn start.
- Test setup (tuner-founded cities, spawned units, declared wars) went into the same save the play-through continued with, so the "real" game drifted.

Target: every finding has a named save from just before it happened. Fixes are verified by loading that save and replaying the keys. Play-through saves and test saves are kept apart.

## 1. civctl hardening (small, do first)

- `start`: kill a leftover `FiraxisBugReporter.exe` before launching, and say so. It also appears after every crash and blocks the tuner and keys until it is killed.
- Crash and hang detection: `key`, `wait`, `sr` and `lua` check that the game process is alive and responding, and that no `FiraxisBugReporter.exe` is running. If not, print `GAME CRASHED` (or `GAME HUNG`) with the crash-dump path and exit with a distinct code (e.g. 5). Agents then stop guessing.
- `key` refuses `Add`, `Subtract` (and other JAWS-reserved numpad keys) with a clear message.
- `status` reports the front end or the turn number when in game.
- A lock file (`%TEMP%\civctl\lock`, with the owner's name) prevents two agents driving the game by accident. A second `civctl` call waits or fails with "game in use by <owner>".
- Save paths: Documents is redirected to OneDrive on this PC (`C:\Users\vladi\OneDrive\Documents\My Games\Sid Meier's Civilization VI\`; `$USERPROFILE\Documents` does not exist). Resolve the folder with `[Environment]::GetFolderPath('MyDocuments')`, never a hard-coded path.
- Mod fix found by the autoplay spike: the hub's `IsHostile` (`InGameAccess.lua:161`, called from the `UnitVisibilityChanged` handler) indexes `Players[Game.GetLocalPlayer()]` while the local player is -1 during autoplay (166 caught errors in a 30-turn run). Add a nil guard.

## 2. Save fixtures (named saves, load by name)

Verified facts:
- **Saving works from the `InGame` state** (`GameCore_Tuner` has no `Network`):
  ```lua
  local s={}; s.Name="<name>"; s.Location=SaveLocations.LOCAL_STORAGE; s.Type=SaveTypes.SINGLE_PLAYER; s.IsAutosave=false; s.IsQuicksave=false; return tostring(Network.SaveGame(s))
  ```
  It returns `true`, and `Saves\Single\<name>.Civ6Save` appears within ~2 s (0.5-1 MB). Quick saves go to `Saves\Single\quick\quicksave.Civ6Save`, autosaves to `Saves\Single\auto\AutoSave_NNNN.Civ6Save`. A new game moves the old autosaves to `auto\prev\`.
- **Loading works ONLY from the `MainMenu` state.** `Network.LoadGame` from `InGame` returns `true` and then crashes the game (twice, hung at "Continue Game").
  ```lua
  -- state MainMenu
  local s={}; s.Name="<name>"; s.Location=SaveLocations.LOCAL_STORAGE; s.Type=SaveTypes.SINGLE_PLAYER; s.IsAutosave=false; s.IsQuicksave=false; s.Directory=SaveDirectories.DEFAULT; return tostring(Network.LoadGame(s, ServerType.SERVER_TYPE_NONE))
  ```
  Then `wait Continue Game` (~22 s), `key Enter -Settle 3000`, and the turn announcement (~6 s). From in game, leave first with `lua InGame 'Events.ExitToMainMenu()'` and wait for "Single Player" (~5 s). That is about 35 s in total.
- The tuner reaches all front-end states (`MainMenu`, `FrontEnd`, `HostGame`, `LoadGameMenu`, ...). `AdvancedSetup` only exists once the Create Game screen has been opened.
- The mod list in a save could not be inspected (the file is compressed). A reload after restarts and redeploys worked. Watch for fixtures that stop loading after mod changes.

Commands:
- `civctl save <name>`: the `InGame` call above, then poll for the file (up to 10 s), copy it to the fixture folder, and write a sidecar `<name>.txt`: turn, civ, profile, purpose, mod commit.
- `civctl load <name>`: copy the fixture into `Saves\Single\` if missing. If in game, run `ExitToMainMenu` and wait for "Single Player". Then the `MainMenu` call, `wait Continue Game`, `key Enter`, `wait Turn`. Never call `LoadGame` from `InGame`. On a crash: kill the reporter, `stop`, `start`, and load from the fresh main menu.
- `civctl fixtures`: lists the fixtures with their sidecar lines.

Storage:
- Commit the fixtures to the repo under `test/fixtures/` (0.5-1 MB each; you work on two PCs).
- The sidecar records the mod commit. Regenerate a fixture when it no longer loads.

Policy (goes into the civ-test and team-lead skills):
- A play agent that hits a bug runs `civctl save bug-<short-name>` right away (before working around it) and names the fixture in its report.
- A fix agent first loads that fixture and reproduces the bug, then verifies the fix by loading it again. "Direct call only" is then the exception.
- Test setup (tuner spawns, wars) happens in a game loaded from a fixture, and it is never saved over the play-through chain. The play-through keeps its own chain: `pt-t10`, `pt-t20`, and so on.
- After a crash: `civctl load` the latest fixture, not the autosave.

## 3. Playtest game setups (profiles) and a new-game command

Setup parameters (ids as used by the Advanced Setup parameter system, verified):

| Parameter | Id | Values |
|---|---|---|
| Game speed | `GameSpeeds` | `GAMESPEED_ONLINE` (fastest), `_QUICK`, `_STANDARD`, `_EPIC`, `_MARATHON` |
| Start era | `GameStartEra` | `ERA_ANCIENT` ... `ERA_INFORMATION` |
| Map size, map type | `MapSize` (`MAPSIZE_SMALL`, ...), `Map` | the player count follows the map size (Small = 6) |
| City-States | `CityStateCount` | number |
| Difficulty | `GameDifficulty` | |
| Disaster intensity (Gathering Storm) | `Realism` | 0 to 4, default 2 |
| Barbarians, tribal villages | `NoBarbarians`, `NoGoodyHuts` | |
| Game modes | `GameMode_BarbarianClans`, `GameMode_SecretSocieties`, ... | only the modes installed show up |
| Random seeds | `GameRandomSeed`, `MapRandomSeed` | number; re-randomised whenever the screen opens |
| Leader | player parameter `PlayerLeader` | e.g. `LEADER_TRAJAN`; random unless set |

How to set them: in the `AdvancedSetup` state, after opening Create Game by keyboard. Raw `GameConfiguration.SetValue` is not the way: values read back as hashes, and the screen's parameter system has to stay in sync.
```lua
local function setenum(pid, val) local p=g_GameParameters.Parameters[pid]; for _,v in ipairs(p.Values) do if v.Value==val then g_GameParameters:SetParameterValue(p, v) end end end
local function setnum(pid, n) g_GameParameters:SetParameterValue(g_GameParameters.Parameters[pid], n) end
setenum("GameSpeeds","GAMESPEED_ONLINE"); setenum("GameStartEra","ERA_MEDIEVAL"); setenum("MapSize","MAPSIZE_SMALL")
setnum("CityStateCount",8); setnum("Realism",4); setnum("GameRandomSeed",12345); setnum("MapRandomSeed",67890)
local pp=GetPlayerParameters(0); local lp=pp.Parameters.PlayerLeader; for _,v in ipairs(lp.Values) do if v.Value=="LEADER_TRAJAN" then pp:SetParameterValue(lp, v) end end
```
Then call `HostGame()` (a global in that state); "Begin Game" follows after ~26 s. Read a value back with `(GameConfiguration.GetValue(k))`. The extra parentheses matter, because a missing key returns nothing.

Verified results:
- All settings took effect in game.
- **Determinism:** the same seeds plus the same leader gave identical start positions twice. With a random leader the start differed, so a profile must fix the leader and both seeds.
- **A Medieval start on Online speed begins at turn 71 (500 AD)**: 2 settlers, a scout, an archer, 104 gold, 10 faith, 19 techs, 14 civics, no cities.
- A first game on a fresh game profile shows the Gathering Storm intro (Escape skips it), then advisor popups.

Profiles (`util/profiles/<name>.lua`; each one fixes the leader and both seeds):

| Profile | Purpose | Settings |
|---|---|---|
| `early` | default play-through | Online, Ancient, Small, 10 city-states, disasters 4, barbarians and villages on, Prince, Trajan |
| `crowded` | contact, diplomacy, envoys, quests, war, AI requests | Online, Tiny map, many city-states |
| `medieval` | trade routes, religion, governors, more districts, World Congress sooner | Online, Medieval (starts at turn 71) |
| `industrial` / `modern` | late-game screens: corps and armies, great works, tourism, spies | Online, Industrial or Modern |
| `modes` | secret-society governors (a known gap); one game mode per test | Secret Societies, others later |

Notes:
- **Online speed** roughly halves the turns needed for production, research and growth compared with Standard.
- **A later start era** is the cheapest way to reach mid-game screens. It gives settlers, techs and civics, but no cities: found them first.
- **Disaster intensity 4** makes the Natural Disaster popup frequent.
- **More civs and city-states on a small map** give early contacts, envoys, quests, delegations and wars.
- Keep difficulty moderate. Tests are about the UI, not winning.

`civctl newgame <profile>`:
1. From the main menu: Enter, Down until "Create Game", Enter (`-Settle 3000`). This creates the `AdvancedSetup` state.
2. `lua AdvancedSetup -File util/profiles/<profile>.lua`, which sets the parameters, the leader and the seeds.
3. Wait 2 s, then `lua AdvancedSetup 'HostGame()'`.
4. `wait Begin Game -Timeout 240`, `key Enter`, then Escape for the intro if it shows.
5. `civctl save <profile>-start`. Later runs then use a ~35 s `load` instead of the ~45 s setup.

## 4. Autoplay to later turns

Verified facts:
- `AutoplayManager` exists in the `InGame` state (also `InGameAccess`, `WorldInput`), not in `GameCore_Tuner`:
  ```lua
  AutoplayManager.SetTurns(n); AutoplayManager.SetReturnAsPlayer(0); AutoplayManager.SetObserveAsPlayer(0); AutoplayManager.SetActive(true)
  ```
- The AI plays our civ too (it founded the capital and built units). The UI stays visible and the tuner keeps working. `AutoplayManager.IsActive()` turns false after n turns, and control returns to player 0 with no popup open.
- Speed: ~6.5 s per turn around turn 71, ~21 s per turn around turn 115 (30 turns took ~10 min). 100 turns from turn 71 is roughly 25-35 minutes. Frequent tuner polling slows it, so poll every 30 s at most.
- Our mod stayed quiet: 6 SR> lines in 5 turns, 17 in 30 (barbarian kills). There was no flood, so no mute flag is needed. The only problem is the `IsHostile` nil guard (workstream 1).
- Don't use `SetObserveAsPlayer(PlayerTypes.OBSERVER)`: it was 3x slower, tore down the UI contexts for ~80 s, and logged thousands of base-game `MinimapPanel.lua` errors.
- `UI.RequestAction(ActionTypes.ACTION_ENDTURN)` is no alternative: it does not end the turn while units need orders.

`civctl autoplay <n> [-Save <name>]`: start autoplay as above, poll `IsActive()` every 30 s (time out at ~25 s per turn), then save the fixture. Run it in the background while other agents do code-only work.

Combined with profiles this gives mid- and late-game fixtures (`medieval-t100`, `early-t120`) with AI-built trade routes, religions, a World Congress, wars and so on. Build them once, commit them, and regenerate them only when they stop loading.

Autoplay does not replace blind play-throughs: those stay the way we find UX problems. Autoplay only gets us to the interesting state.

## 5. Scenario scripts and engine notes

- `util/scenarios/<name>.lua`: GameCore_Tuner scripts that set up one situation on a loaded fixture. Examples: an enemy next to our city that attacks it, a governor title ready, envoys to give, a builder next to a forest, a city at its district cap, war with a city-state.
- `civctl scenario <name>` runs one. Each script starts with a comment: which fixture it expects, and what to press afterwards.
- Only safe calls. The calls that crashed the game are listed as forbidden in the notes:
  - hand-made `APPOINT_GOVERNOR` parameters
  - faked popup-manager locks and `NaturalDisasterPopup_Closed`
  - `Network.LoadGame` from `InGame`
  - observer autoplay
- `docs/engine-notes.md`: move the engine facts that are now scattered through `ingame-plan.md` into one place:
  - the `Keys` codes, and which events fire for which action (e.g. `UnitOperationAdded` and not `UnitOperationStarted` for auto-explore)
  - the `ReplaceUIScript` versus `ImportFiles` rule
  - status-message tags and where the failure reasons are
  - how to trigger each popup
  - the save, load, setup and autoplay recipes above
  `ingame-plan.md` keeps the design and status and links to it.

## 6. Speech regression scripts

- `test/regress/<name>.txt`, one step per line:
  ```
  load bug-historic-moment
  key Enter -Settle 2000
  expect ^Historic moment: .*Enter to continue
  key Enter
  expect-not Turn ended
  ```
  - Supported steps: `load`, `scenario`, `key`, `wait`, `expect` (regex over the SR> lines since the previous step), `expect-not`, `lua`.
- `civctl regress [name|all]` runs the steps, prints PASS/FAIL per step with the actual lines, and exits non-zero on failure.
- Scripts that share a fixture run back to back, so the ~35 s load is paid once per fixture, not per script. A `scenario` step can follow the load.
- Every fixed bug that has a fixture gets a script; the fix agent writes it.
- A play segment starts with `civctl regress all` instead of re-confirming old fixes by hand.

## 7. Code checks without the game

**Done (2026-10-22):** `python util/lint.py` (luacheck, strict for mod-only files), `python util/luatest.py` (lupa/Lua 5.1, 6 test files), `Accessibility/SRListen.lua` added and registered. Pending: wiring lint into `civctl deploy`, and adopting `SRListen` in the overrides (needs a game restart).

These let more agents work in parallel, because only work that needs the game waits for it.

1. **Static check:**
   - `luacheck` (standalone Windows binary, or via LuaRocks) with a `.luacheckrc` that declares the game's globals: `Events`, `LuaEvents`, `UI`, `Game`, `Players`, `GameInfo`, `Map`, `Locale`, `Keys`, `ContextPtr`, `Controls`, `include`, the mod's own globals, ...
   - Run it in `civctl deploy` before copying; refuse on errors such as undefined variables and syntax errors.
   - Start with warnings only for the game-file copies (they are upstream code).
2. **Offline unit tests for pure logic:**
   - Run under Lua 5.1 through Python (`lupa`, matching our Python-first tooling) or a standalone `lua5.1.exe`.
   - Give it small stubs of `GameInfo`, `Map`, `Locale` and `Players`.
   - First targets: `SettleScan.lua` scoring, `PlacementScan.lua`, `PlotDescription` direction/distance words, `CleanTextForSpeech` / `OutputMessageToScreenReader` markup stripping, the status-message combat patterns (the "a/an" bug), and `KeyNavList` navigation.
   - `python util/luatest.py` runs everything in seconds.
3. **Listener helper:**
   - Add `Accessibility/SRListen.lua`: `SRListen(Events.X, fn)` records each listener, and `SRUnlistenAll()` in the context's shutdown removes them.
   - Use it in every override we touch from now on.
   - This ends the class of "stale instance after hot reload" errors that cost time in Phase 6, where UnitPanel, AdvisorPopup and HistoricMoments each had to be fixed by hand.

## 8. Workflow change: implement in parallel, verify in a slot

Once 2, 6 and 7 exist, the team-lead loop changes:
- Several fix agents can work at the same time.
  - They implement and run luacheck and the offline tests.
  - They write the regression script for their item.
  - They do not drive the game; they commit on a branch each, or hand over a patch.
- One verifier agent owns the game (the lock file from workstream 1). It merges, deploys, runs `civctl regress` for the new scripts plus all old ones, and reports failures back to the owning agent.
- Long autoplay runs that build fixtures go in the verifier's idle time.

## Order and rough size

| # | Item | Size | Depends on |
|---|---|---|---|
| 1 | civctl hardening + lock file + `IsHostile` guard | small | - |
| 2 | save / load / fixtures + policy in skills | small to medium | 1 |
| 3 | profiles + `newgame` | small to medium | 2 |
| 4 | `civctl autoplay` + first mid-game fixtures | small (plus ~30 min autoplay runs) | 2, 3 |
| 5 | scenario scripts + `docs/engine-notes.md` | small, then grows | 2 |
| 6 | speech regression runner | medium | 2 |
| 7 | luacheck, offline tests, listener helper | medium | - (parallel with 2-6) |
| 8 | team-lead skill update for parallel implement / single verifier | small | 6, 7 |

Suggested agent batches: (1+2+3) as one game-driving agent, since they share civctl.ps1 and each builds on the last. Item 7 runs as a code-only agent at the same time. Then 4 and 5 together, then 6, then 8 (done by the lead, since it is the team-lead skill).

## Spikes (done 2026-10-22, results folded into sections 1-4)

1. Saves and the front end: named saves work from `InGame`; loads work only from `MainMenu` (from `InGame` the game crashes); the tuner reaches every front-end state.
2. Setup: the Advanced Setup parameter objects plus `HostGame()` work. The same seeds plus the same leader give the same start. A Medieval start on Online speed begins at turn 71.
3. Autoplay: works with `SetObserveAsPlayer(0)`, and our mod stays quiet apart from the `IsHostile` errors. `OBSERVER` mode is unusable. About 6-21 s per turn.

Spike leftovers in the save folder: `spike1.Civ6Save` (the turn-42 play-through) and `spike-med-t71.Civ6Save` (Medieval profile, turn 71). A backup of the saves from before the spikes is in `%TEMP%\civ-save-backup`.
