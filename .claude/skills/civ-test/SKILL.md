---
name: civ-test
description: Build the mod, launch Civilization VI and drive it with the keyboard while reading the screen reader output, to verify a change in the real game. Use whenever a Lua/mod change needs testing, or to reproduce a bug in the game.
---

# Driving the game with civctl

`util\civctl.cmd <command>` (PowerShell script `util\civctl.ps1`; read its header for all options).

| Command | Does |
|---|---|
| `build` | ModBuddy build + deploy. Must print `1 succeeded`; exit code 1 otherwise. **Refuses while the game is running** (ModBuddy recreates the deployed folder, which kills hot reload until a restart); `stop` first, or `-Force` if you restart anyway. Times out (instead of hanging) if ModBuddy shows a dialog; then take a `shot`. |
| `stop` | Kills game + console app and waits for teardown. |
| `start [-Timeout 180]` | Starts the console app and the game, skips the intro movie, returns once "Main menu" is announced. |
| `key <Key> [-Count n] [-Settle ms] [-All]` | Focuses the game, sends the key as a hardware scancode, prints the screen reader lines it caused as `SR> ...`. Lines that arrived after the previous command show as `(earlier) SR> ...`. `-Settle` (default 600) is the wait per press; use 1500-3000 for keys that open screens. Key names are .NET `Keys` names: `Down`, `Up`, `Left`, `Right`, `Enter`, `Escape`, `Space`, `Tab`, `A`, `F1`... Chords: `Shift+E`, `Control+Shift+F` (Shift/Control/Alt + one key). |
| `sr [-All]` | Prints new screen reader lines (`-All`: every new `Lua.log` line, incl. `#KEYNAV_MOVE`). |
| `wait <regex> [-Timeout s]` | Blocks until a screen reader line matches (exit 1 on timeout). Use it instead of sleeps, e.g. `wait Begin Game -Timeout 240` (multi-word patterns unquoted: from Git Bash a quoted arg breaks cmd.exe; avoid `|` and `&` in patterns) during a game load. |
| `shot` | Screenshot of the game window (downscaled to 1280 px), prints the PNG path; view it with the Read tool. |
| `deploy` | Hot reload: copies changed shipped files (.lua/.xml/.sql/...) from `ScreenReaderAccess\` straight into the deployed mod folder (in place; shrinking files are padded first so the game never reads a half-written file), the running game re-initialises the affected context within ~1 s. Prints `deployed <file>` per file and `LUA ERROR> ...` (exit 1) for errors in the next 2.5 s. New files, files deleted from the repo but still deployed, and `Database\` changes are reported as `needs build + restart` (exit 3). |
| `reload <file...>` | Rewrites the named deployed files (path or name fragment, e.g. `reload InGameAccess.lua`) even if unchanged, to force the game to re-init that context. |
| `lua <state> <code>` / `lua <state> -File f.lua` | Runs Lua in a Lua state via FireTuner (needs `EnableTuner 1` + game restart). States: `civctl states`; useful: `GameCore_Tuner` (gameplay DB/players: set up scenarios, read units), `InGame`, `InGameAccess` (the hub's own state). Prints `print()` output; a single expression or a `return x` is printed like a REPL (`lua InGame 'Game.GetCurrentGameTurn()'`). `ERR:` + exit 1 on Lua errors, and `ERR: no completion within 8s` (exit 1) if the state hangs. State may be a name or an index (state indexes change when the game reloads contexts; prefer names). **Quoting:** from Git Bash use `util/civctl lua ...` (no `.cmd`), which keeps spaces and quotes intact; `civctl.cmd` loses double quotes inside arguments from PowerShell and breaks on quoted arguments from Git Bash, so with `.cmd` use single-quoted Lua strings, or `-File` for anything non-trivial. |
| `menu` | Is the in-game options menu or a popup/screen open? Prints `MENU: OPEN/closed` and `POPUP/SCREEN OPEN: ...`; exit 4 if either is open. |
| `states` | Lists tuner Lua states. |
| `status` | Is the game / console app running. |
| `keymap` | Regenerates `keymap.md` (below) from the `#KEYMAP` dump in `Lua.log`. |

## Workflow

1. First time (or after new files / `.civ6proj` / SQL changes): `build`, then `stop` and `start`, load a game. After that, for Lua edits use `deploy` and keep playing: no restart. `build` refuses while the game runs (it would kill hot reload until the next restart). Timings: full loop build+stop+start+load a save ~65 s; `deploy` ~4 s.
2. Navigate by **reacting to `SR>` output**: press one key, read what was announced, decide the next key. Loop in PowerShell with a match condition when walking a list, e.g.
   ```powershell
   for ($i=1; $i -le 12; $i++) { $o = & util\civctl.cmd key Down; "Down -> $($o -join ' | ')"; if ($o -match 'Start Game') { break } }
   ```
3. After a run, grep `%LOCALAPPDATA%\Firaxis Games\Sid Meier's Civilization VI\Logs\Lua.log` for `Runtime Error` and your file name.
4. `stop` when done (the user may want the PC back).

## In-game hotkeys

`.claude/skills/civ-test/keymap.md` lists every action on the Options > Key Bindings tab with its key and the exact `civctl key` argument (e.g. Found City = `B`, Next Ready Unit = `OemPeriod`, Form Army = `Control+Shift+F`). Do not read it whole: grep it, e.g. `grep -i "found city\|next ready" .claude/skills/civ-test/keymap.md`.

It is generated, not hand-written: `Options.lua` prints a `#KEYMAP` block to `Lua.log` whenever the Options screen is shown. To refresh after rebinding keys or editing `Database/*.sql` hotkeys: build, `stop`/`start`, press Down to "Game Options" and Enter (then Escape), then `util\civctl.cmd keymap`. All actions are currently bound (the script lists any unbound ones at the top of the file).

## Escape and the in-game menu

Escape with no popup or mode open opens the in-game options menu (`In game menu` / `RETURN TO GAME`), and the next Down+Enter then does something real (Quick Save...). Before a key sequence that starts with Escape, run `util/civctl menu`: `MENU: OPEN` means Escape will close it, `closed` means Escape will open it. To back out: `key Escape` once while `MENU: OPEN` (announces `RETURN TO GAME`), then `menu` again to confirm. The `POPUP/SCREEN OPEN` line lists open screens (e.g. `PartialScreens/CityStates`); close those with Escape too.

## GameCore_Tuner recipes

Run with `lua GameCore_Tuner '<code>'` (`-File` for longer scripts):

- Spawn a unit: `Players[0]:GetUnits():Create(GameInfo.Units["UNIT_SETTLER"].Index, x, y)`
- Finish the current research: `Players[0]:GetTechs():ChangeCurrentResearchProgress(1000)`
- Meet another civ: `Players[0]:GetDiplomacy():SetHasMet(id)` and `Players[id]:GetDiplomacy():SetHasMet(0)` (both sides).
- `UI.SelectUnit(unit)` works from the `InGameAccess` state (not GameCore_Tuner).
- Not available in GameCore_Tuner: `UnitManager.Kill`, `Plot:IsRevealed`.
- Notifications sent synthetically (USER_DEFINED / CHOOSE_TECH) did not behave like real ones; trigger the real event (finish research, end turn) when testing notification handling.

## Common paths (as of 2026-10-19)

- Main menu opens with focus on Single Player. `key Enter` opens the submenu (announces Resume Game if a save exists, else Load Game); Down until `Create Game`; `key Enter -Settle 3000` → `CREATE GAME`.
- On Create Game, Up from the first item wraps to `Start Game`; Down reaches `ADVANCED SETUP`.
- After Start Game: `wait Begin Game -Timeout 240`, then `key Enter -Settle 3000` begins the game.
- Exit: Up from Single Player to `Exit to Desktop`, Enter, the popup announces and focuses `OK`, Enter.

## Tips

- Screenshots are not routine: do not `shot` after keys. Take one only for the UI you are actively building, or when the SR> output is unexpected and unexplained.
- Token cost: `key`/`sr` output is ~10-30 tokens per press; a screenshot is ~1-1.5k. Screenshot only when the announcements don't explain what happened.
- `Lua.log` shows what the mod printed, not what the console app actually spoke.
- Don't use Bash `sleep` to wait on the game; use `wait`, or a PowerShell loop polling `Lua.log` for a pattern.
- The user can't use their PC while you drive the game (focus and mouse are taken over).
