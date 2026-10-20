# ScreenReaderAccess (Civilization VI mod)

Screen reader support and keyboard navigation ("keynav") for Civ VI, for blind players. Read `README.md` for the why; this file is the how.

## Architecture

Civ VI mods can't call DLLs, make HTTP calls or write files, so the only channel out of the game is Lua `print()` into `Lua.log`:

- **Mod** (`ScreenReaderAccess/`): modified copies of the game's Lua UI files, overriding the originals via `ImportFiles` in `ScreenReaderAccess/ScreenReaderAccess.civ6proj`. They print prefixed lines.
- **Console app** (`ScreenreaderAccess.Console/`, .NET 8, WinForms): tails `%LOCALAPPDATA%\Firaxis Games\Sid Meier's Civilization VI\Logs\Lua.log` (`LogFileWatcher` → `Mediator`) and acts on the prefixes:

| Prefix (printed by) | Console app does |
|---|---|
| `#SCREENREADER - text` / `#SCREENREADER[NOINTERRUPT] - text` (`Accessibility/ScreenReader.lua`, `OutputMessageToScreenReader(msg, nointerrupt)`) | speaks it via AccessibleOutput |
| `#KEYNAV_MOVE - x,y` (`KeyNavMoveMouse(control)`) | moves the real mouse there |
| `#KEYNAV_CLICK - L` (`KeyNavLeftClick()`) | real left click at the mouse position |
| `#KEYNAV - <id> START/…/END` (`PrintKeyboardNavigationElements`) | older nav-set protocol, mostly unused now |

The console app must be running for clicks/mouse moves to happen, and for any announcement that is still triggered by `MouseEnter`. `.github/copilot-instructions.md` is older and partly inaccurate (e.g. prefix names); trust this file and the code.

## Layout

- `ScreenReaderAccess/Assets/UI/Accessibility/`: mod-only helpers (`ScreenReader.lua`, `KeyboardNavigation.lua`, plot utils, gameplay event handlers). Always read the first two.
- `ScreenReaderAccess/Assets/UI/Frontend/`: front-end screens (MainMenu, AdvancedSetup = Create Game + Advanced Setup, LoadScreen, LoadGameMenu, FrontEndPopup).
- `ScreenReaderAccess/Assets/UI/{Panels,Popups,ToolTips,Menus}/`, `WorldInput.lua`: in-game UI.
- `ScreenReaderAccess/Database/*.sql`: input actions / default hotkeys.
- Game originals (read-only reference): `C:\Program Files (x86)\Steam\steamapps\common\Sid Meier's Civilization VI\Base\Assets\UI\…`. Check `DLC\Expansion1|2\UI\Replacements` too: expansions sometimes replace a file and `include` the base one.
- `util/civctl.ps1` / `util/civctl.cmd`: build/launch/drive harness (see below).

## Build and test loop

Lua changes can only be verified in the real game. Use the harness (details in the `civ-test` skill, `.claude/skills/civ-test/SKILL.md`):

```
util\civctl.cmd build                 # ModBuddy build + deploy to My Games\...\Mods; must print "1 succeeded"
util\civctl.cmd stop; util\civctl.cmd start -Timeout 180   # restart is required to load Lua changes
util\civctl.cmd key Down              # sends a key, prints the resulting "SR> ..." lines
util\civctl.cmd shot                  # screenshot path, view only when output is confusing
```

- Console app: `dotnet build ScreenreaderAccess.Console` (`civctl start` launches it).
- Lua errors land in `Lua.log` as `Runtime Error:`; grep for them after every run. Wrap new input handlers in `xpcall` while developing; an error in an input handler otherwise silently kills the screen's keyboard input.
- Drive the game by reacting to the `SR>` output, not fixed key counts: menus change (e.g. Resume Game appears once a save exists).

## Workflow rules

- **New override of a game file:** first commit the untouched game file alone ("Add X.lua pristine asset"), then commit the mod changes on top. Register it in the `.civ6proj`: a `<File priority="10001">` entry in `FrontEndActionData` and/or `InGameActionData` (which context loads it: verify a print from your copy shows up in `Lua.log`) plus a `<Content Include>` entry.
- **`.civ6proj`** often contains the user's uncommitted work. Never commit their hunks. Stage only your lines by building the index blob (`git hash-object -w` + `git update-index --cacheinfo`). The file has a UTF-8 BOM; keep it.
- Keep edits to game files minimal and localized (they're copies of upstream code); put reusable logic in `Accessibility/`. Match the surrounding Lua style (type annotations like `local x:number`, tabs, semicolons).
- Don't touch untracked personal scripts at the repo root (`build.cmd`, `run.cmd`, `open_log.cmd`, `util/update_assets.bat` which points at the user's other PC).

## Implementing keyboard navigation

See `docs/keynav-guide.md` for the patterns that work (and the traps that cost time): announce directly on focus change, rebuild item lists from visible state at key time, track focus by identity, call callbacks instead of synthetic clicks, defer mouse moves until animations settle, keep the mouse off sliders. Good reference implementations: `Frontend/MainMenu.lua` (commit `dcc804f`) and `Frontend/AdvancedSetup.lua` (`c7f54ec`, `246224f`).

## Environment notes

- Game: Steam, `C:\Program Files (x86)\Steam\steamapps\common\Sid Meier's Civilization VI` (launching `CivilizationVI.exe` relaunches as `CivilizationVI_DX12`). The intro movie blocks the main menu until a key is pressed (`civctl start` handles it).
- ModBuddy needs the VS Isolated Shell (`…\Sid Meier's Civilization VI SDK\ModBuddy\Redist\vs_isoshell.exe`, needs UAC approval from the user). Without it, ModBuddy shows "Cannot find one or more components" and `build` times out.
- Driving the game takes over the real keyboard focus and mouse; the user can't use the PC meanwhile.
