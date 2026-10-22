# Dev loop plan: faster, reproducible play testing

Why: in the Phase 6 play-through (see `ingame-plan.md`) most of the time went to things other than code:
- Only one agent can drive the game, so implementation was serial.
- Situations were hard to trigger (attacks on cities, natural disasters, historic moments, governor blockers, make peace), so many fixes ended as "verified by a direct call" only.
- Crashes cost progress back to the last autosave, and a leftover `FiraxisBugReporter.exe` blocked `start`.
- Fixes were validated in whatever state the running game was in, not in the state where the bug was found.
- Agents rediscovered the same engine facts.

This plan fixes that in seven workstreams, in priority order. Each one: implement (sonnet agent), verify in game, commit, then update `CLAUDE.md` / the civ-test skill / the team-lead skill so later agents use it.

## How saves were used in Phase 6 (the problem)

- Agents only had the quick save (one slot, overwritten all the time: batch B's testing replaced the turn-10 save) and the per-turn autosaves.
- When a play agent found a bug it did NOT save at that moment. The fix agent then tried to reproduce it in the current game, often at a later turn, via the tuner, or by calling the handler directly.
- Nobody replayed from turn 1, but nobody reloaded the exact moment either. After a crash, the agent continued from the autosave of the turn start.
- Test setup (tuner-founded cities, spawned units, declared wars) went into the same save the play-through continued with, so the "real" game drifted.

Target: every finding has a named save from just before it happened. Fixes are verified by loading that save and replaying the keys. Play-through saves and test saves are kept apart.

## 1. civctl hardening (small, do first)

- `start`: kill a leftover `FiraxisBugReporter.exe` / `CrashReporter` before launching, and say so.
- Crash and hang detection: `key`, `wait`, `sr` and `lua` check that the game process is alive and responding. If not, print `GAME CRASHED` (or `GAME HUNG`) with the crash-dump path and exit with a distinct code (e.g. 5). Agents then stop guessing.
- `key` refuses `Add`, `Subtract` (and other JAWS-reserved numpad keys) with a clear message.
- `status` reports the turn number and the loaded save name (via the tuner) when in game.

## 2. Save fixtures (named saves, load by name)

Commands:
- `civctl save <name>`: makes a normal (not quick) save named `<name>` in game. Use the API the in-game Save menu uses (`Network.SaveGame` / the `SaveGame` path in `InGameTopOptionsMenu.lua` / `SaveLoad.lua`), called through the tuner. Then copy the file to the fixture folder with a small sidecar `<name>.txt`: turn, civ, setup profile, what the save is for, and the mod commit.
- `civctl load <name>`: copies the fixture into the game's save folder if needed and loads it. Works from the main menu or in game. `Network.LoadGame({ Name=..., Location=SaveLocations.LOCAL_STORAGE, Type=SaveTypes.SINGLE_PLAYER, Directory=SaveDirectories.DEFAULT, IsAutosave=false, IsQuicksave=false }, ServerType.SERVER_TYPE_NONE)`, as in `Base/Assets/UI/Automation/Automation_DailySmokeTest.lua`. Afterwards it waits for "CONTINUE GAME", presses Enter, and waits for the turn announcement. If the tuner cannot reach the front end, fall back to the keyboard path (Single Player > Load Game) and add keynav to the Load Game screen. That screen is a known gap anyway.
- `civctl fixtures`: lists the fixtures with their sidecar lines.

Storage:
- Recommended: commit the fixtures to the repo under `test/fixtures/`. They are a few MB each, and you work on two PCs.
- A save records the mods it was made with, and a mod change can make old saves stale. The sidecar records the commit; regenerate the fixture when it no longer loads.

Policy (goes into the civ-test and team-lead skills):
- A play agent that hits a bug runs `civctl save bug-<short-name>` right away (before working around it) and names the fixture in its report.
- A fix agent first loads that fixture and reproduces the bug, then verifies the fix by loading it again. "Direct call only" is then the exception.
- Test setup (tuner spawns, wars) happens on a copy loaded from a fixture, never in the play-through save. The play-through keeps its own chain: `pt-t10`, `pt-t20`, and so on.
- After a crash: `civctl load` the latest fixture, not the autosave.

## 3. Playtest game setups (profiles) and a new-game command

The game exposes these setup parameters:

| Parameter | Configuration | Values |
|---|---|---|
| Game speed | `GameSpeeds` | Online (fastest), Quick, Standard, Epic, Marathon |
| Start era | `GameStartEra` | Ancient through Information |
| Map size, map type | `MapSize`, `Map` | |
| Number of players | | |
| City-States | `CityStateCount` | |
| Difficulty | `GameDifficulty` / `PlayerDifficulty` | |
| Disaster intensity (Gathering Storm) | `Realism` / `GAME_REALISM` | 0 to 4, default 2 |
| Barbarians, tribal villages | `NoBarbarians`, `NoGoodyHuts` | |
| Game modes | | Secret Societies, Barbarian Clans, Heroes, Monopolies, Dramatic Ages, Apocalypse, ... |
| Random seeds | `GameRandomSeed`, `MapRandomSeed` | |

Profiles to define. Start each from a fixed seed so every run of a profile gives the same map and start:

| Profile | Purpose | Settings |
|---|---|---|
| `early` | default play-through | Online speed, Ancient, Small map, 6 civs, 10 city-states, disasters 4, barbarians and villages on, difficulty Prince |
| `crowded` | contact, diplomacy, envoys, quests, war, AI requests | Tiny map, max civs for the size, many city-states, Online speed |
| `medieval` | mid-game features from turn 1: trade routes, religion founding, governors, more districts, World Congress sooner | Medieval or Renaissance start, Online speed |
| `industrial` / `modern` | late-game screens: corps and armies, great works, tourism, spies | Industrial or Modern start |
| `modes` | the known gap of secret-society governors; one game mode per test | Secret Societies (and others when we cover them) |

Notes:
- **Online speed** roughly halves the turns needed for production, research and growth compared with Standard, so situations come sooner.
- **A later start era** gives more cities' worth of techs and civics, extra settlers, gold and units. That is the cheapest way to test mid-game screens without playing 100 turns.
- **Disaster intensity 4** makes the Natural Disaster popup frequent.
- **More civs and city-states on a small map** give early first contacts, envoys, city-state quests, delegations and wars.
- Keep difficulty moderate. Tests are about the UI, not winning, and high difficulty loses units to barbarians and AIs (we lost a scout and a captured builder).

New-game command:
- `civctl newgame <profile>`: from the main menu, set the configuration and launch.
- Preferred path: `GameConfiguration.SetValue` / `MapConfiguration` / `PlayerConfigurations` setters plus `Network.HostGame(ServerType.SERVER_TYPE_NONE)` through the tuner in the front-end state. Verify first that the tuner can reach a front-end Lua state; the Automation scripts do the same kind of thing.
- Fallback: drive Advanced Setup by keyboard (it has keynav), with the profile as a list of option names and values.
- After launch: wait for "Begin Game", press Enter, run `civctl save <profile>-t1`.

## 4. Autoplay to later turns

- The engine has an autoplay used by Firaxis's own test automation: `AutoplayManager.SetTurns(n)`, `SetReturnAsPlayer(0)`, `SetObserveAsPlayer(id)`, `SetActive(true)` (see `Automation_StandardTests.lua`). The AI plays every civ, including ours, for n turns, then returns control to player 0.
- Spike: call it through the tuner in a normal session (not an automation run).
  - Does it run?
  - How fast is it, with the UI hidden or visible?
  - Does our hub survive it (selection and turn events will flood)?
  - Does control come back cleanly?
- If it works: `civctl autoplay <turns>` mutes the hub while it runs (a `LuaEvents.SRA_Mute` flag), then saves a fixture.
- Combined with profiles this gives cheap mid- and late-game fixtures (`medieval-t60`, `early-t120`) that contain AI-built trade routes, religions, a World Congress, wars and so on.
- Not a replacement for blind play-throughs: those stay the way we find UX problems. Autoplay only gets us to the interesting state.

## 5. Scenario scripts and engine notes

- `util/scenarios/<name>.lua`: GameCore_Tuner scripts that set up one situation on a loaded fixture. Examples: an enemy next to our city that attacks it, a governor title ready, envoys to give, a builder next to a forest, a city at its district cap, war with a city-state.
- `civctl scenario <name>` runs one. Each script starts with a comment: which fixture it expects, and what to press afterwards.
- Only safe calls. The engine operations that crashed the game (hand-made `APPOINT_GOVERNOR` parameters, faked popup-manager locks) are listed as forbidden in the notes.
- `docs/engine-notes.md`: move the engine facts that are now scattered through `ingame-plan.md` into one place:
  - `Keys` codes, and which events fire for which action (e.g. `UnitOperationAdded` and not `UnitOperationStarted` for auto-explore)
  - the `ReplaceUIScript` versus `ImportFiles` rule
  - status-message tags, failure-reason locations
  - how to trigger each popup
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
- Every fixed bug that has a fixture gets a script; the fix agent writes it.
- A play segment starts with `civctl regress all` instead of re-confirming old fixes by hand.

## 7. Code checks without the game

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
- One verifier agent owns the game. It merges, deploys, runs `civctl regress` for the new scripts plus all old ones, and reports failures back to the owning agent.
- A `civctl` lock file (`%TEMP%\civctl\lock`, with the owner's name) prevents two agents driving the game by accident. A second `civctl` call waits or fails with "game in use by <owner>".

## Order and rough size

| # | Item | Size | Depends on |
|---|---|---|---|
| 1 | civctl hardening + lock file | small | - |
| 2 | save / load / fixtures + policy in skills | medium | 1 |
| 3 | profiles + `newgame` (spike: tuner in the front end) | medium | 2 |
| 4 | autoplay spike, then `civctl autoplay` | small to medium | 2 |
| 5 | scenario scripts + `docs/engine-notes.md` | small, then grows | 2 |
| 6 | speech regression runner | medium | 2 |
| 7 | luacheck, offline tests, listener helper | medium | - (parallel with 2-6) |
| 8 | team-lead skill update for parallel implement / single verifier | small | 6, 7 |

Spikes that decide the approach (do these first, each 15-30 min in game):
1. Can the tuner run `Network.LoadGame` / `Network.SaveGame` and reach a front-end state?
2. Does `AutoplayManager` work outside automation, and how fast is it?
3. Does `GameConfiguration` set from the tuner survive into the launched game (start era, speed, seeds)?
