# Engine notes (Civ VI Lua, as verified in this project)

Facts about the game engine that cost time to find. Design and status of features stay in `ingame-plan.md`; the how-to for screens is in `keynav-guide.md`; the harness is in `.claude/skills/civ-test/SKILL.md`. Add new facts here.

## FORBIDDEN calls

Each of these has crashed or wedged the game, or wasted a play session:

- Hand-made `PlayerOperations.APPOINT_GOVERNOR` / `PROMOTE_GOVERNOR` parameters. Appoint through the Governors screen (F10). (One verification used them to give the Merchant the Contractor promotion; do not copy that.)
- Faked popup-manager locks, and firing `NaturalDisasterPopup_Shown` / `NaturalDisasterPopup_Closed` unbalanced: the `BulkHide` count goes wrong and the game crashed once. A real disaster could not be triggered (`GameRandomEvents.ApplyEvent` did nothing visible).
- `Network.LoadGame` from the `InGame` state: returns `true`, then the game crashes or hangs at "Continue Game". Use `civctl load` (it goes through `MainMenu`).
- Observer autoplay (`AutoplayManager.SetObserveAsPlayer(PlayerTypes.OBSERVER)`): 3x slower, tears down the UI contexts for ~80 s, thousands of `MinimapPanel.lua` errors. Use `SetObserveAsPlayer(0)`.
- `UI.RequestAction(ActionTypes.ACTION_ENDTURN)` as an end-turn shortcut: does nothing while units need orders.
- Sending NumPad `+` / `-` (`civctl key Add` / `Subtract`): JAWS commands; `Subtract` turns on the JAWS cursor, which swallows arrow keys system-wide (injected keys too) until `Add` turns it off. civctl refuses them. Use `OemPlus` / `OemMinus`.
- Synthetic notifications (USER_DEFINED / CHOOSE_TECH) do not behave like real ones: trigger the real event instead.
- Not available in `GameCore_Tuner`: `UnitManager.Kill`, `Plot:IsRevealed`, `Network`, `UI.SelectUnit` (use the `InGameAccess` state for the last). `AutoplayManager` exists in `InGame`, `InGameAccess`, `WorldInput`, not in `GameCore_Tuner`.

## Keys

- The engine `Keys` enum is NOT Win32: Return 102, Escape 103, Down 86, `VK_BACK` 104, `VK_OEM_PLUS` 88, `C` 3. Always compare against `Keys.VK_*` / `Keys.<Letter>`.
- Input order in game: the hub's `SetInputHandler` (InGameAccess) runs before `WorldInput` and `ActionPanel`. Returning `true` on KeyDown/KeyUp stops the lower contexts' raw handlers (ActionPanel acts on Enter KeyUp) and the input action the key would have produced (a consumed Down never fires `CameraPanDown`). The reverse holds too: a key a context handler consumes never becomes an input action. Hotkeys that are plain input actions (`Events.InputActionTriggered`) arrive only if nobody consumed the key. Popups and the in-game menu sit above the hub and consume everything while open.
- A rebinding key is only recorded by the engine if the input handler returns false for it; key-state polling needs `civctl key <Key> -Hold 200`.
- Escape on the map with nothing open opens the in-game menu (`civctl menu` tells which).
- While an `EditBox` has focus the context's input handler gets no key events; Enter fires the commit callback; Escape reverts the text, fires the commit callback and its KeyUp still reaches the context. `SetNumberInput(true)` rejects characters without a callback. See `Accessibility/KeyNavEditBox.lua`.
- A mouse resting on a slider eats arrow keys (the context stops receiving them).
- The Lua sandbox has no `debug` table (`xpcall` handlers must not call `debug.traceback`) and no `%f` frontier patterns.

## Events: what fires for which action

- Unit orders: `UnitOperationStarted` for most actions (fortify, sleep, build improvement, found city). Automate Exploration and Fortify Until Healed fire only `UnitOperationAdded`. The game re-adds the operation for already automated units, so only trust it within ~2 s of a key press.
- `UnitSelectionChanged` also reaches hidden contexts. When the only ready unit is already selected, Next Action re-selects it WITHOUT an event.
- `UnitKilledInCombat(killedPlayer, killedUnit, killerPlayer, killerUnit)`: the killed unit is already gone at event time (cache names while alive). Attacker/defender come from `CombatVisBegin`.
- `LocalPlayerTurnEnd` also fires when the end of turn was refused: compare the turn number / active player before saying "Turn ended".
- Purchases: gold/faith spending arrives as treasury/faith events ("Bought X, N gold left"); a production change as `CityProductionQueueChanged`; governors `GovernorAppointed`, `GovernorAssigned`; saves `Events.SaveComplete` (within 1.5 s).
- `LoadScreenClose` marks the end of a load; a unit selected during the load is announced after it. A turn-1 save shows the Gathering Storm intro again after loading (Escape).
- Every `Events.X.Add` / `LuaEvents.X.Add` needs a matching `.Remove` on shutdown (use `SRListen` + `SRUnlistenAll`), else a hot reload leaves a stale instance that speaks twice.
- `UI.GetPlotScreenPos` does not exist; use `UI.LookAtPlotScreenPosition(x, y, 0.5, 0.5)` and `UI.GetPlotCoordFromNormalizedScreenPos` (takes -1..1, y up). Hex geometry: odd rows shift half a plot east (`Map.GetAdjacentPlot(4,4,NE) = (4,5)`).
- A context added with `AddUserInterfaces` starts hidden and a hidden context gets no input actions or `SetUpdate`: call `ContextPtr:SetHide(false)` first.
- `CanStartCommand(PURCHASE)` does not check the balance (says yes, the request silently fails): check gold yourself. `CanStartOperation(FOUND_CITY, plot, false, true)` tests the plot given but says no for every plot at 0 moves.
- Placement failure reasons: `CityOperationResults.FAILURE_REASONS` (already localized text), `NO_SUITABLE_LOCATION` (true for wonders), plots under `PLOTS`; `city:GetBuildQueue():CanProduce(hash, false, true)` (4th argument = allow purchasing plots). District cap `1 + floor((pop - 1) / 3)`; at the cap every further district is refused with a population reason. What placing destroys: SUCCESS_CONDITIONS of `CanStartOperation(BUILD, {X, Y, type}, true)`. BUILD is refused on tiles the city does not own; the game buys a tile with a separate `PURCHASE` command.

## ReplaceUIScript vs ImportFiles

- Base-game UI files (`Base/Assets/UI/...`): override with `ImportFiles` in the `.civ6proj` (`FrontEndActionData` and/or `InGameActionData`, priority 10001); a `print` from the copy shows in `Lua.log` and tells which context loads it. Check `DLC/Expansion1|2/UI/Replacements`: the expansion may replace the file and `include` the base one, so override the file that holds the code. An `include`d base file can be replaced with ImportFiles (CityStates).
- DLC `UI/Additions` scripts (Governor panels, HistoricMoments, NaturalDisasterPopup): ImportFiles does NOT work (the DLC's own ImportFiles is applied later and the context is loaded by path). Use `ReplaceUIScript` with `LuaContext` = the file stem (`GovernorPanel`; the child context ID `DetailsPanel` does not match), file as `UI/Replacements/<Name>_SRA.lua`.
- `Accessibility/` helpers that a front-end screen includes must be in BOTH `FrontEndActionData` and `InGameActionData`, else the screen script silently aborts after returning from a game.
- New files, `.civ6proj` / `.modinfo` and `Database/*.sql` changes need `build` + restart; Lua edits hot-reload with `civctl deploy` (never `build` while the game runs).

## Status messages

`StatusMessagePanel` (base) shows the game's own tagged messages; our copy drops unit-versus-unit combat lines the hub already spoke (`LuaEvents.SRA_CombatSpoken` within 2 s) by matching the localized templates built from the LOC tags (`LOC_GRAMMAR_A_AN` is matched as `an?`; city/district targets are never dropped). Failure reasons for actions come from the engine: `UnitManager.CanStartOperation` result tables (`FAILURE_REASONS`, localized), `CombatManager.IsAttackChangeWarState` for "would declare war", and for builders the per-improvement check over `Improvement_ValidBuildUnits` ("not possible on this tile" / "already built here" / "no moves left" are our fallbacks when the engine gives no reason).

## Triggering popups and screens (for tests)

| Popup / screen | How |
|---|---|
| Tech / civic completed | `GameCore_Tuner`: `Players[0]:GetTechs():ChangeCurrentResearchProgress(1000)`, then end the turn (the real event) |
| Boost (Eureka/Inspiration), natural wonder | normal play; natural wonder by moving next to one |
| First contact / diplomacy | `GameCore_Tuner`: `Players[0]:GetDiplomacy():SetHasMet(id)` and `Players[id]:GetDiplomacy():SetHasMet(0)` (both sides); the declare-war dialog via Declare Surprise War in the overview |
| Historic moment | not triggerable for real; from the context's own state call `ShowNewTimelineMoment` / `ToggleHistoricMomentsScreen` |
| Natural disaster | not triggerable (see FORBIDDEN); only a hand-queued popup was checked |
| Advisor | first game on a fresh profile, turn-1 events |
| Gathering Storm intro | a turn-1 save after loading |
| Governors | F10 or the appointment blocker; City-States: F2, the "Send envoy" blocker or a banner |
| Pantheon | enough faith; it blocks the turn loop |
| In-game menu | Escape with nothing open (`civctl menu`) |

## Recipes

Tuner (`civctl lua <state> ...`; needs `EnableTuner 1` in `AppOptions.txt` and a restart):
- Spawn a unit: `Players[0]:GetUnits():Create(GameInfo.Units["UNIT_SETTLER"].Index, x, y)`; gold: `Players[0]:GetTreasury():ChangeGoldBalance(100)`.
- `lua` prints `print()` output; a single expression or `return x` is printed. Read a config value with `(GameConfiguration.GetValue(k))` (the extra parentheses matter: a missing key returns nothing). Only one tuner connection at a time. State indexes change on context reload: use names. The `InGame` state is absent at the front end; `AdvancedSetup` exists only once Create Game was opened.
- Scenario scripts: `util/scenarios/`.

Save (state `InGame`, works):
```lua
local s={}; s.Name="<name>"; s.Location=SaveLocations.LOCAL_STORAGE; s.Type=SaveTypes.SINGLE_PLAYER; s.IsAutosave=false; s.IsQuicksave=false; return tostring(Network.SaveGame(s))
```
`Saves\Single\<name>.Civ6Save` appears within ~2 s (quick saves in `Saves\Single\quick\`, autosaves in `auto\`; a new game moves old autosaves to `auto\prev\`). Documents is OneDrive-redirected on this PC: use `[Environment]::GetFolderPath('MyDocuments')`.

Load (state `MainMenu` ONLY; leave a running game first with `lua InGame 'Events.ExitToMainMenu()'` and wait for "Single Player"):
```lua
local s={}; s.Name="<name>"; s.Location=SaveLocations.LOCAL_STORAGE; s.Type=SaveTypes.SINGLE_PLAYER; s.IsAutosave=false; s.IsQuicksave=false; s.Directory=SaveDirectories.DEFAULT; return tostring(Network.LoadGame(s, ServerType.SERVER_TYPE_NONE))
```
Then `wait Continue Game` (~22 s), `key Enter -Settle 3000`, and the turn announcement (~6 s). The tuner reaches all front-end states (`MainMenu`, `FrontEnd`, `HostGame`, `LoadGameMenu`, ...).

Setup (state `AdvancedSetup`, after opening Create Game by keyboard; raw `GameConfiguration.SetValue` is wrong: values read back as hashes and the screen's parameter system must stay in sync):
```lua
local function setenum(pid, val) local p=g_GameParameters.Parameters[pid]; for _,v in ipairs(p.Values) do if v.Value==val then g_GameParameters:SetParameterValue(p, v) end end end
local function setnum(pid, n) g_GameParameters:SetParameterValue(g_GameParameters.Parameters[pid], n) end
```
Parameter ids: `GameSpeeds` (`GAMESPEED_ONLINE` ... `_MARATHON`), `GameStartEra`, `MapSize`, `Map`, `CityStateCount`, `GameDifficulty`, `Realism` (disasters 0-4), `NoBarbarians`, `NoGoodyHuts`, `GameMode_*`, `GameRandomSeed`, `MapRandomSeed`; leader: `GetPlayerParameters(0).Parameters.PlayerLeader`. Then `HostGame()` (a global in that state); "Begin Game" follows after ~26 s. Same seeds + same leader = identical start (a random leader changes it). A Medieval start on Online speed begins at turn 71 with 2 settlers and no cities. Profiles: `util/profiles/*.lua`, `civctl newgame <profile>`.

Autoplay (state `InGame`, never `GameCore_Tuner`):
```lua
AutoplayManager.SetTurns(n); AutoplayManager.SetReturnAsPlayer(0); AutoplayManager.SetObserveAsPlayer(0); AutoplayManager.SetActive(true)
```
The AI plays our civ (UI visible, tuner works); `AutoplayManager.IsActive()` goes false after n turns and control returns with no popup open. ~6.5 s/turn around turn 71, ~21 s/turn around turn 115; poll at most every 30 s. The local player is -1 during autoplay: nil-guard `Players[Game.GetLocalPlayer()]` in listeners.
