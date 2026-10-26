# ScreenReaderAccess (Civilization VI mod)

Screen reader support and keyboard navigation ("keynav") for Civ VI, for blind players. Read `README.md` for the why; this file is the how.

## Architecture

Civ VI mods can't call DLLs, make HTTP calls or write files, so the only channel out of the game is Lua `print()` into `Lua.log`:

- **Mod** (`ScreenReaderAccess/`): modified copies of the game's Lua UI files, overriding the originals via `ImportFiles` in `ScreenReaderAccess/ScreenReaderAccess.civ6proj`. They print prefixed lines.
- **Console app** (`ScreenreaderAccess.Console/`, .NET 10, WinForms): tails `%LOCALAPPDATA%\Firaxis Games\Sid Meier's Civilization VI\Logs\Lua.log` (`LogFileWatcher` → `Mediator`) and acts on the prefixes:

| Prefix (printed by) | Console app does |
|---|---|
| `#SCREENREADER - text` / `#SCREENREADER[NOINTERRUPT] - text` (`Accessibility/ScreenReader.lua`, `OutputMessageToScreenReader(msg, nointerrupt)`) | speaks it via AccessibleOutput |
| `#KEYNAV_MOVE - x,y` (`KeyNavMoveMouse(control)`) | moves the real mouse there |
| `#KEYNAV_CLICK - L` (`KeyNavLeftClick()`) | real left click at the mouse position |
| `#KEYNAV - <id> START/…/END` (`PrintKeyboardNavigationElements`) | older nav-set protocol, mostly unused now |

The console app must be running for clicks/mouse moves to happen, and for any announcement that is still triggered by `MouseEnter`. `.github/copilot-instructions.md` is older and partly inaccurate (e.g. prefix names); trust this file and the code.

## Layout

- `ScreenReaderAccess/Assets/UI/Accessibility/`: mod-only helpers (`ScreenReader.lua`, `KeyboardNavigation.lua`, plot utils, `PlotDescription.lua`). Always read the first two. `HelpText.lua` is the text of the Control+H help list: every new shortcut gets an entry there (Workflow rules).
- `ScreenReaderAccess/UI/Additions/InGameAccess.{xml,lua}`: the in-game hub context (wiring only: input handler, update loop, `Initialize`); its code is in `Assets/UI/Accessibility/Hub*.lua` modules (map cursor, target modes, placement, menus, regions, city report, events ...; one global table each), see `docs/ingame-plan.md` Architecture and `docs/keynav-guide.md` (where new hub code goes).
- `ScreenReaderAccess/Assets/UI/Frontend/`: front-end screens (MainMenu, AdvancedSetup = Create Game + Advanced Setup, LoadScreen, LoadGameMenu, FrontEndPopup).
- `ScreenReaderAccess/Assets/UI/{Panels,Popups,ToolTips,Menus}/`, `WorldInput.lua`: in-game UI.
- `ScreenReaderAccess/Database/*.sql`: input actions / default hotkeys.
- Game originals (read-only reference): `C:\Program Files (x86)\Steam\steamapps\common\Sid Meier's Civilization VI\Base\Assets\UI\…`. Check `DLC\Expansion1|2\UI\Replacements` too: expansions sometimes replace a file and `include` the base one.
- `util/civctl.ps1` / `util/civctl.cmd`: build/launch/drive harness (see below).

## Build and test loop

Lua changes can only be verified in the real game. Use the harness (details in the `civ-test` skill, `.claude/skills/civ-test/SKILL.md`):

```
util\civctl.cmd deploy               # FAST LOOP (~4 s): lints the changed .lua files (util/lint.py; errors refuse the deploy, -NoLint skips), copies them into the running game, which hot-reloads the UI context
util\civctl.cmd build                # ModBuddy build + deploy to My Games\...\Mods; must print "1 succeeded"; refuses while the game runs (-Force overrides)
util\civctl.cmd reload InGameAccess.lua   # force a hot reload of a file without content change
util\civctl.cmd menu                 # is the in-game options menu / a popup open? (Escape with nothing open opens the menu)
util\civctl.cmd stop; util\civctl.cmd start -Timeout 180   # full restart (~35 s to main menu, ~65 s back in a game)
util\civctl.cmd key Down             # sends a key, prints the resulting "SR> ..." lines (plain navigation keys inside our own screens: Up, Down, Enter, Escape, Tab, letters)
util\civctl.cmd action NextUnit      # sends the CURRENT key of a game/mod hotkey (user's InputSettings.json, else the default from Database/*.sql / the game), same output/lock/owner rules as key; errors if the action is unbound. Prefer it to `key` for rebindable hotkeys, also as an `action <Id>` step in test\regress scripts
util\civctl.cmd keymap              # regenerates .claude/skills/civ-test/keymap.md from InputSettings.json + defaults (no game needed; python util/keybindings.py [--json] [ActionId] prints one binding)
util/civctl lua InGame 'Game.GetCurrentGameTurn()'   # (Git Bash: `util/civctl`, keeps quotes/spaces; expressions and `return x` are printed) run Lua in a game state via FireTuner (GameCore_Tuner, InGame, InGameAccess, ...); `states` lists them
util\civctl.cmd autoplay 29 -Save medieval-t100   # AI plays n turns for us (~5-20 s/turn, prints turn numbers every 30 s; run in background), then saves the fixture
util\civctl.cmd shot                 # screenshot path, view only when output is confusing
util\civctl.cmd load early-t60       # named fixtures (test\fixtures); also `save <name>`, `newgame <profile>`, `autoplay <n>`
util\civctl.cmd scenario governor-title   # set up one situation (util\scenarios\*.lua) on a loaded fixture
util\civctl.cmd regress changed [--base <rev>]  # ONLY the scripts the changes since the last green `regress all` (or --base) can affect: each script has a `# covers: <glob>...` header; core files (ScreenReader/KeyNavList/SRListen/KeyboardNavigation/InGameAccess/HubCore) select all (unless the diff only adds single-line include/AddEvent/Listen/RegisterAction/`.Add(` registrations), other Hub*.lua go by `# covers:` (the end-of-round `regress all` backs this up; if it fails a script `changed` skipped, add the file to that script's `# covers:`); no-header scripts always run; `--dry-run` shows why. The verifier runs this per item
util\civctl.cmd regress all [--no-share-load] [--no-batch]   # (key/action: -Settle is the max wait, returns after -Quiet ms (default 150; 700 when -Settle >= 1500; explicit wins) without a new SR line, -NoQuiet = fixed wait; the runner uses one `civctl batch` process, --no-batch = one powershell.exe per step) speech regression scripts (test\regress\*.txt), exit 1 on a failed check; a green run records the commit for `changed` (once per round, at the end, after the last merge; ~1 h for 48 scripts, fewer loads since browse-only scripts share). TIMING shows load/keys/settle/wait per script + BREAKDOWN. `all` shares ONE load per fixture, but a script only skips its load when a reset check (one tuner call, `HubCore.TestResetState`: no popup/menu/target mode, turn/gold/units/cities as after the load; it restores cursor and selection) says the game is clean, else it loads fresh; `# options:` and `# own-load: <reason>` scripts (they check the load's own speech) load themselves; `# no-share-load: <reason>` and scenario scripts (anything that changes game state the check cannot see) may start on a clean shared game but the next script loads fresh; a script failing on a shared game is retried fresh. BREAKDOWN shows loads saved and reset-check time. After a mid-round fix rerun only the failing script + `regress changed`. Prints a TIMING table + TOTAL (18 scripts took ~22 min with a load each). One script: `regress <name>`
CIVCTL_OWNER=<your agent name> util/civctl <command> ...   # REQUIRED for every command that drives the game. Git Bash: PREFIX every call (an `export` does not persist between tool calls). PowerShell: $env:CIVCTL_OWNER='name'. Without it: REFUSED, exit 7 (the message prints this form)
util\civctl.cmd advance 5            # SETUP/VERIFICATION only (play-tests never use it): the autoplay AI plays our civ for exactly n turns (it resolves every blocker), control returns, turn counter checked
util\civctl.cmd endturn              # SETUP/VERIFICATION only: request the end of turn (what the End Turn button does; refuses while a blocker is pending and names it with the ActionPanel text, e.g. "Unit needs orders"). Play-tests end turns with Enter like a player
util\civctl.cmd wait-turn 62 -Timeout 300   # wait until the game is at turn 62 and your turn is active (prints SR> lines, REPORTS open popups, never presses keys); exit 1 on timeout / already past
util\civctl.cmd clear-advisors       # close advisor popups (Enter only while AdvisorPopup is visible); `load` does this by default (-KeepAdvisors skips it)
util\civctl.cmd key-release          # release Shift/Control/Alt, both sides (`key` does it after every chord; Shift+Tab is refused: Steam overlay, use Control+Tab)
util\civctl.cmd fixture-info early-t60   # with that fixture loaded: appends a `facts:` block (cities, districts, buildings, units, trade slots, spies, religion, governors, blockers...) to test\fixtures\early-t60.txt; read these before writing a scenario
util\civctl.cmd status              # game/console/lock + "in game, turn N" or "front end"
util\civctl.cmd save bug-foo -Purpose "why"   # named save -> test/fixtures/bug-foo.Civ6Save + .txt (turn, civ, commit)
util\civctl.cmd load early-start    # load a fixture by name (~30-45 s, from in game or main menu; never LoadGame from InGame)
util\civctl.cmd fixtures            # list fixtures; util\civctl.cmd newgame <early|crowded|medieval|industrial|modern|modes>  # new game from util/profiles/*.lua (~70 s), saves <profile>-start
util\civctl.cmd unlock              # release the lease (no owner needed, frees a dead agent's too). Other owners get "game in use by X" (exit 6) until it is released or idle 3 min
# exit 5 + "GAME CRASHED/HUNG" (key, wait, sr, lua, save, load): stop guessing, `stop`, `start`, `load` the latest fixture. `key` refuses Add/Subtract/numpad keys (JAWS).
```

- **Hot reload (verified):** the game watches the deployed mod folder and re-initialises a UI context ~1 s after one of its Lua files is rewritten in place. It works for the hub (`InGameAccess.lua`), game-file overrides (`NotificationPanel.lua`, `UnitPanel.lua`) and front-end files (`MainMenu.lua`), with or without `EnableTuner`. Use `civctl deploy` (it copies repo -> deployed folder in place and reports Lua errors from the following 2.5 s). A changed included helper (`Hub*.lua`, `HelpText.lua`, ...) does not re-init the contexts that `include` it, so `deploy`/`reload` also rewrite those includers in place (`util/includers.py`, transitive; prints `reloaded <file> (includes <helper>)`). Do NOT run `build` in between: ModBuddy deletes and recreates the whole deployed folder, and the game's file watcher is dead until the game is restarted (edits then silently do nothing). So: `build` once before `start`, then only `deploy` while the game runs. A reload resets that context's state (e.g. the map cursor); the first key after a front-end reload may be swallowed.
- **Needs a full restart:** new files, `.civ6proj`/`.modinfo` changes (these need `build`), `Database/*.sql` (`deploy` reports them with exit code 3 and prints `NEW FILE(S) not deployed: ... -> civctl build + restart needed` for files the deployed folder lacks, also files deleted from the repo that are still deployed), probably XML layout changes (untested). If a deploy shows a `Syntax Error`, fix and deploy again.
- Without a restart you can also `Exit to Main Menu` and `Resume Game` (~25 s) to re-run everything, but hot reload makes that rarely necessary.
- Tuner: `EnableTuner 1` in `%LOCALAPPDATA%\Firaxis Games\Sid Meier's Civilization VI\AppOptions.txt` (`[Debug]`, needs a game restart; disables achievements). `util\civtuner.py` (adapted from civ6-mcp, MIT) speaks the FireTuner protocol on 127.0.0.1:4318; only one tuner connection at a time. Use it to set up scenarios in `GameCore_Tuner` (e.g. `Players[0]:GetTreasury():ChangeGoldBalance(100)`) and to read state; errors print as `ERR:` with exit code 1.
- In team-lead mode only the verifier/game-owning agent runs `civctl`; fix agents use lint/luatest/regress scripts (see `.claude/skills/team-lead/SKILL.md`).
- Do not run several `civctl` commands in parallel: they share the log cursor in `%TEMP%\civctl\cursor.txt`.
- Console app: `dotnet build ScreenreaderAccess.Console` (`civctl start` launches it).
- Lua errors land in `Lua.log` as `Runtime Error:`; grep for them after every run. Wrap new input handlers in `xpcall` while developing; an error in an input handler otherwise silently kills the screen's keyboard input.
- Drive the game by reacting to the `SR>` output, not fixed key counts: menus change (e.g. Resume Game appears once a save exists).

## Offline checks (no game needed)

```
python util/lint.py [-v] [files...]   # luacheck (fetches util/tools/luacheck.exe on first use; ~1 s). Exit 1 = syntax error anywhere or any warning in mod-only files (Accessibility/, UI/Additions/); 2 = tool problem. -v lists upstream warnings. Also compiles every file with real Lua 5.1 (lupa): "more than 200 local variables", too many upvalues/registers fail with file:line (the game only logs `Syntax Error` and the whole context dies); warns above 185 top-level locals (the hub is at ~190: move new state into tables)
python -m unittest discover test/py   # tooling tests (keybindings, regress runner, civ6proj, civturn, fixtureinfo), no game
python util/civ6proj.py add Assets/UI/Popups/Foo.lua --context InGame [--replace-ui FooPopup]   # REGISTER files this way (also list / merge-union); never hand-edit the one-line CDATA blocks, see Workflow rules
python util/overridecheck.py [-v]      # static check of the .civ6proj registrations against the game install (CIV_GAME_DIR or the Steam path; skipped with a warning if absent; lint.py runs it too). Run it before committing a new override. Exit 1 = ImportFiles copy that loses to an expansion (use ReplaceUIScript, see docs/engine-notes.md), DLC UI/Additions overridden with ImportFiles, file name that a wildcard include("Prefix_", true) would load, missing/unregistered/duplicate files or Content entries, Accessibility helper missing from FrontEndActionData/InGameActionData
python util/civregress.py <name> --record     # (with a game) run a regress script and write test/regress/<name>.recorded.txt = the SR> lines every expect saw; --update also rewrites failing expect lines in place (.bak kept). Use it for the first run of an unverified, blind-written script
python util/luatest.py [name...]      # Lua 5.1 unit tests via lupa (pip install lupa on first use), test/lua/test_*.lua with stubs in test/lua/stubs/; <1 s. Exit 1 = failure
```

- Both read Civ's `local x:number` annotations (stripped before checking). Engine and mod globals are declared in `.luacheckrc`: a new global defined in `Accessibility/` must be added to `globals` there.
- New pure logic gets a `test/lua/test_*.lua` (`stub("engine")`, `stub("world")` for a fake map, `include("X")` loads `Accessibility/X.lua`, `Spoken()` returns what `OutputMessageToScreenReader` printed, `load_mod_block(path, n)` loads a mod-change block of a game-file copy).
- Register event listeners with `SRListen` / `SRUnlistenAll()` (`Accessibility/SRListen.lua`, see `docs/keynav-guide.md`).

## Workflow rules

- **Help list rule:** every new or changed shortcut (an input action in `Database/*.sql`, OR a key inside one of our lists and screens) needs an entry in `ScreenReaderAccess/Assets/UI/Accessibility/HelpText.lua`, the text of the Control+H accessibility help list (the player's place to look up what the mod can do). `test/py/test_helptext.py` fails for a `KeyNav*` input action without an `action = "..."` entry; keys inside screens have no automatic check, so add a `keys = "..."` entry yourself.
- **New override of a game file:** first commit the untouched game file alone ("Add X.lua pristine asset"), then commit the mod changes on top. Register it in the `.civ6proj`: a `<File priority="10001">` entry in `FrontEndActionData` and/or `InGameActionData` (which context loads it: verify a print from your copy shows up in `Lua.log`) plus a `<Content Include>` entry. Any `Accessibility/` helper that a front-end screen `include`s must be listed in BOTH `FrontEndActionData` and `InGameActionData`, or it silently fails to load after returning from a game (the screen script aborts).
- **Register files with `python util/civ6proj.py add <file> --context InGame|FrontEnd|Both [--replace-ui <LuaContext>]`** (adds the `<File>` / `ReplaceUIScript` entry and the `<Content Include>`; idempotent; keeps BOM and CRLF). `civ6proj.py list` shows what is registered. Merge conflicts in the `.civ6proj` (InGameActionData is one long line): `git config merge.civ6proj.driver "python util/civ6proj.py merge-driver %O %A %B"` + `merge.civ6proj.name x` once per clone (the .gitattributes line exists), or resolve by hand with `python util/civ6proj.py merge-union <ours> <theirs> --out <file>` (union of File / ReplaceUIScript / Content entries). Run `overridecheck.py` afterwards.
- Worktree agents start with `git rebase master` (master moves fast).
- `test/fixtures/*.txt` carry a `facts:` block (from `civctl fixture-info`) once the verifier has run it: read it before assuming a Holy Site, a free trade slot or spies.
- **`.civ6proj`** often contains the user's uncommitted work. Never commit their hunks. Stage only your lines by building the index blob (`git hash-object -w` + `git update-index --cacheinfo`). The file has a UTF-8 BOM; keep it.
- Keep edits to game files minimal and localized (they're copies of upstream code); put reusable logic in `Accessibility/`. Match the surrounding Lua style (type annotations like `local x:number`, tabs, semicolons).
- Don't touch untracked personal scripts at the repo root (`build.cmd`, `run.cmd`, `open_log.cmd`, `util/update_assets.bat` which points at the user's other PC).

## Implementing keyboard navigation

See `docs/keynav-guide.md` for the patterns that work (and the traps that cost time): announce directly on focus change, rebuild item lists from visible state at key time, track focus by identity, call callbacks instead of synthetic clicks, defer mouse moves until animations settle, keep the mouse off sliders. Good reference implementations: `Frontend/MainMenu.lua` (commit `dcc804f`) and `Frontend/AdvancedSetup.lua` (`c7f54ec`, `246224f`).

## Environment notes

- Game: Steam, `C:\Program Files (x86)\Steam\steamapps\common\Sid Meier's Civilization VI` (launching `CivilizationVI.exe` relaunches as `CivilizationVI_DX12`). The intro movie blocks the main menu until a key is pressed (`civctl start` handles it).
- ModBuddy needs the VS Isolated Shell (`…\Sid Meier's Civilization VI SDK\ModBuddy\Redist\vs_isoshell.exe`, needs UAC approval from the user). Without it, ModBuddy shows "Cannot find one or more components" and `build` times out.
- Driving the game takes over the real keyboard focus and mouse; the user can't use the PC meanwhile.
- Owned content: base game + Gathering Storm only (plus the free Barbarian Clans and Tech/Civic Shuffle modes). Read `docs/game-content.md` before planning tests or features; no Secret Societies, Heroes, Monopolies, Dramatic Ages, Apocalypse or civ packs.
