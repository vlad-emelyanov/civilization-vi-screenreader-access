# Engine notes (Civ VI Lua, as verified in this project)

Facts about the game engine that cost time to find. Design and status of features stay in `ingame-plan.md`; the how-to for screens is in `keynav-guide.md`; the harness is in `.claude/skills/civ-test/SKILL.md`. Add new facts here.

## FORBIDDEN calls

Each of these has crashed or wedged the game, or wasted a play session:

- Hand-made `PlayerOperations.APPOINT_GOVERNOR` / `PROMOTE_GOVERNOR` parameters. Appoint through the Governors screen (F10). (One verification used them to give the Merchant the Contractor promotion; do not copy that.)
- Faked popup-manager locks, and firing `NaturalDisasterPopup_Shown` / `NaturalDisasterPopup_Closed` unbalanced: the `BulkHide` count goes wrong and the game crashed once. A real disaster could not be triggered (`GameRandomEvents.ApplyEvent` did nothing visible).
- `Network.LoadGame` from the `InGame` state: returns `true`, then the game crashes or hangs at "Continue Game". Use `civctl load` (it goes through `MainMenu`).
- Observer autoplay (`AutoplayManager.SetObserveAsPlayer(PlayerTypes.OBSERVER)`): 3x slower, tears down the UI contexts for ~80 s, thousands of `MinimapPanel.lua` errors. Use `SetObserveAsPlayer(0)`.
- `UI.RequestAction(ActionTypes.ACTION_ENDTURN)` as an end-turn shortcut: does nothing while units need orders. `civctl endturn` is the safe form for setup/verification (it checks `NotificationManager.GetFirstEndTurnBlocking` and `UI.CanEndTurn` first, like `ActionPanel.lua` `DoEndTurn`, and names the blocker); play-tests still end turns with Enter.
- `key Shift+Tab`: opens the Steam overlay, which eats the key-up, so the game keeps Shift logically held (Down does nothing, Tab goes backwards) until both Shift keys are released. `civctl key` refuses it and releases modifiers after every chord; `civctl key-release` frees a stuck one.
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

## Trade choosers (unverified, read from the game files)

- Selecting a trader with moves in a city makes `TradeRouteChooser` open by itself (`OnUnitSelectionChanged` -> `CheckNeedsToOpen` -> interface mode MAKE_TRADE_ROUTE); the Tab menu entry is just another way in. `RequestTradeRoute()` starts the operation and sets the interface mode back to SELECTION in the same call, which runs `Close()` (context hidden). A hidden context gets no `SetUpdate`, so anything that must be said after the request has to be timed by a context that stays shown (the hub: `LuaEvents.SRA_TradeResult`).
- `TradeOriginChooser`'s own Escape (`AnimSidePanelSupport` OnInputHandler) only hides the panel; the interface mode TELEPORT_TO_CITY stays until something else changes it.
- Both are contexts of `InGame.xml` listed after ActionPanel / ProductionPanel, so they get keys before them (the hub, added last, before everything).
- Trade route data: destinations in `m_unfilteredDestinations` (`owner`, `id`, `pathPlots`), yields `GetYieldsForRoute(origin, city[, true for the destination's side])` in `TradeSupport.lua` (`kYieldValues` indexed from 1 = `GameInfo.Yields[i - 1]`, `TooltipText`, `MajorityReligion`, `ReligionPressure`), a started route shows in `city:GetTrade():GetOutgoingRoutes()` (`TraderUnitID`).

## Events: what fires for which action

- Unit orders: `UnitOperationStarted` for most actions (fortify, sleep, build improvement, found city). Automate Exploration and Fortify Until Healed fire only `UnitOperationAdded`. The game re-adds the operation for already automated units, so only trust it within ~2 s of a key press.
- `UnitSelectionChanged` also reaches hidden contexts. When the only ready unit is already selected, Next Action re-selects it WITHOUT an event.
- `UnitKilledInCombat(killedPlayer, killedUnit, killerPlayer, killerUnit)`: the killed unit is already gone at event time (cache names while alive). Attacker/defender come from `CombatVisBegin`.
- `GoodyHutReward(playerID, unitID, goodyHutTypeHash, subTypeHash)` (verified 2026-10-24): the hashes are `DB.MakeHash(GoodyHuts.GoodyHutType)` / `DB.MakeHash(GoodyHutSubTypes.SubTypeGoodyHut)` (`GameInfo.GoodyHutSubTypes[hash]` does NOT work: loop and compare). `Description` is a format string taking the amount (`Locale.Lookup(desc, 60)`); empty for boosts (the boost popup speaks them) and units/population/relic. Amounts of gold/faith in the ModifierArguments are scaled by `GameSpeeds.CostMultiplier/100` (Online: 60 faith -> 30, checked against the balance). Spoken by `HubEvents.OnGoodyHutReward`. A hut for tests: `ImprovementBuilder.SetImprovementType(plot, GameInfo.Improvements.IMPROVEMENT_GOODY_HUT.Index, -1)` in `GameCore_Tuner` (`util/scenarios/goody-hut.lua`).
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

## Deal screen (DiplomacyDealView)

- With Gathering Storm `DLC/Expansion2/UI/Replacements/DiplomacyDealView.lua` (3232 lines, globals `g_LocalPlayer`, `g_OtherPlayer`, `g_AvailableGroups` ...) replaces `Base/Assets/UI/DiplomacyDealView.lua` through `ImportFiles` (default priority) in `Expansion2.modinfo`; it wildcard-includes `DiplomacyDealView_Expansion2.lua` (favor: `PopulateAvailableFavor`, `OnClickAvailableOneTimeFavor`, group types) before `Initialize()`. Expansion 1 has no deal view file. The XML is the base one (`Base/Assets/UI/DiplomacyDealView.xml`, a child context of `DiplomacyActionView.xml`) and is not overridden.
- VERIFIED 2026-10-22: the ImportFiles copy did NOT win (no "copy loaded" line in `Lua.log`, the screen opened silently): the XP2 file in `DLC/Expansion2/UI/Replacements` replaces the base one at the same or higher priority. Our copy is now `UI/Replacements/SRA_DealView.lua`, registered with `ReplaceUIScript` (LuaContext `DiplomacyDealView`, LuaReplace that file); after that `ScreenReaderAccess: DiplomacyDealView copy loaded` appears once at game start. The file name must NOT start with `DiplomacyDealView_`: the copy ends with the wildcard `include("DiplomacyDealView_", true)`, which then included the copy itself (a file named `DiplomacyDealView_SRA.lua` gave "C stack overflow: too many (128) nested C function calls" while the game loaded). Code that sits after the wildcard include (`PopulateAvailableFavor` wrapper) stays just before `Initialize()`.
- Shift+Tab is Steam's overlay hotkey: with the overlay on, Shift+Tab never reaches the game (it opens the Steam overlay and the next Shift+Tab closes it). The deal screen therefore also accepts Control+Tab for the previous section; do not use Shift+Tab for new features.
- Hot reloading the deal view while a diplomacy session is open leaves the session in a state where Make Deal no longer opens the screen and Escape does nothing (recover with `lua DiplomacyActionView OnForceClose()`); test deal changes after a restart, not with `deploy`.
- Deal item facts used: `DealManager.GetWorkingDeal(DealDirection.OUTGOING, local, other)`, `pDeal:Items()`, `pDealItem:GetType/GetFromPlayerID/GetAmount/GetDuration/GetSubType/GetValueType/GetValueTypeNameID/GetSubTypeNameID/IsLocked/IsUnacceptable/GetMaxAmount`, `pDeal:GetItemParent(item)` (items that come with a city have a parent and cannot be removed or edited alone). Changing an amount re-creates the item (`OnValueEditButton` removes and re-adds it), so its ID changes. `OnValueEditButton(itemID)` reads `Controls.ValueAmountEditBox:GetText()`, so a keyboard amount edit sets that text and calls it (no popup needed). `GetPossibleDealItems` entries carry `IsValid` / `ValidationResult` but no reason text; only resources have one (`LOC_DEAL_PLAYER_HAS_NO_CAP_ROOM` / `LOC_DEAL_AI_HAS_NO_CAP_ROOM`).
- The AI's answers arrive as `LuaEvents.DiploPopup_DealUpdated(otherID, action, text)` and `Events.DiplomacyIncomingDeal(from, to, action)` (`DealProposalAction`: PENDING, PROPOSED, ADJUSTED, ACCEPTED, REJECTED, EQUALIZE_FAILED ...); `UpdateProposalButtons` calls `SetLeaderDialog` on nearly every status update, so speak only a leader text that changed after the events were quiet. The deal is closed by `LuaEvents.DiploPopup_HideDeal` (from `DiplomacyActionView`) or by `OnContinue()` after the final accept.
- Buttons are read with `Controls.X:IsHidden()`, `:IsDisabled()`, `:GetTextControl():GetText()`, `:GetToolTipString()`.

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

## Setup limits

- `CityStateCount` is limited by the map size (`MapSizes.xml`: Tiny max 10, Small 14, Standard 18, Large 22, Huge 24). A larger value reads back fine right after setting it, but the game then creates 0 city-states. The `crowded` profile clamps to the parameter's `Values.MaximumValue`.

## Recipes

Tuner (`civctl lua <state> ...`; needs `EnableTuner 1` in `AppOptions.txt` and a restart):
- Spawn a unit: `Players[0]:GetUnits():Create(GameInfo.Units["UNIT_SETTLER"].Index, x, y)`; gold: `Players[0]:GetTreasury():ChangeGoldBalance(100)`.
- `lua` prints `print()` output; a single expression or `return x` is printed. Read a config value with `(GameConfiguration.GetValue(k))` (the extra parentheses matter: a missing key returns nothing). Only one tuner connection at a time. State indexes change on context reload: use names. The `InGame` state is absent at the front end; `AdvancedSetup` exists only once Create Game was opened.
- Scenario scripts: `util/scenarios/` (`civctl scenario <name>`). In `GameCore_Tuner` these exist: `Players[i]:GetInfluence():ChangeTokensToGive(n)` / `GetTokensToGive()`, `Players[i]:GetGovernors():ChangeGovernorPoints(n)` / `GetGovernorPoints()` / `GetGovernorPointsSpent()`, `Map.GetAdjacentPlot(x, y, dir)`. `Players[i]:IsMinor()` does NOT exist: a city-state is `PlayerConfigurations[i]:GetCivilizationLevelTypeName() == "CIVILIZATION_LEVEL_CITY_STATE"`.
- Select a unit for a test (state `InGameAccess`): `for _,u in Players[0]:GetUnits():Members() do if GameInfo.Units[u:GetType()].UnitType=="UNIT_BUILDER" then UI.SelectUnit(u) break end end`; the selection is announced.
- `civctl lua` does not print the SR> lines it causes; they show up as `(earlier)` lines in the next `key`/`sr`. Advisor popups (queued after a load, first contact, a governor point, envoys) swallow keys and are not listed by `civctl menu`; Enter closes one at a time (`clear-advisors` in regress scripts).

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

## World Congress (read from the scripts, unverified)

- Scripts in `DLC/Expansion2/UI/Additions` (`WorldCongressPopup/Intro/BetweenTurns`): use `ReplaceUIScript`. Popup state is file-local (`m_CurrentStage` 1/2/4, `m_CurrentPhase` 1/2, `m_kResolutionVotes`, `m_kResolutionChoices`); pulldown and check-box callbacks are closures, so the copy records them (`sraSelect`, `sraToggle`).
- A resolution needs >= 1 vote and a target to pass Next; voting for the other option zeroes the first and clears the target; removing the last vote is impossible. `GetVotesandFavorCost` is 0-based and cumulative, with `MaxVotes`.
- `LOC_NOTIFICATION_WORLD_CONGRESS_RESULTS_MESSAGE/_SUMMARY` exist in no text file (raw tag is returned); the notification is AutoActivate and opens the results popup.
- `WorldCongressBetweenTurns` compares with `Keys.VK_ENTER`, which may not exist; `VK_RETURN` is the engine name.

## Misc engine facts (verified 2026-10-22)

- `local x:table = value` is a RUNTIME type check in Civ's Lua: assigning a number gives "Type check failed: (expected 'table', but got 'number')". `Game.GetWorldCongress():GetResolutions(pid)` (and `GetReview(pid).Resolutions`) contain a numeric `Stage` key next to the resolution tables, so loop variables over them must not be annotated `:table` (the game's own loops test `type(v) == "table"`).
- `CityBuildQueue:CanProduce` is "Not Implemented" in GameCore_Tuner; `CityBuildQueue:CreateIncompleteDistrict(districtIndex, plotIndex, 100)` (GameCore_Tuner) places a finished district (used by the prophet-ready scenario to make a Holy Site).
- A unit created by the tuner and given `UnitManager.RestoreMovement` has its moves in the UI at once (the trader-in-capital scenario works without ending the turn).
- The ActionPanel label stays "End turn" after Escape closed the World Congress popup while the Resume Congress blocker is pending, and says "Please wait" while the congress is in session: the hub's N checks `Game.GetWorldCongress():IsInSession()`.
- Make Trade Route / Transfer to Another City have no tooltip when disabled; the Tab menu text is composed from `GetNumOutgoingRoutes` / `GetOutgoingRouteCapacity` (UnitPanel).

- Shift+Tab leaves Shift logically held in the game after the overlay swallowed its key-up: afterwards Down/Up do nothing and Tab goes backwards in every screen. `civctl key LShiftKey` then `RShiftKey` releases it (a plain `Shift` key name does not). Use Control+Tab for "previous" in our screens.
- The in-game top options menu (Escape) does not receive the real mouse: hover and clicks go to the map under it (a Coast tooltip shows). Everything there must work by direct calls (announce on Up/Down, Enter calls the button's handler), not through KEYNAV_MOVE/KEYNAV_CLICK.
- A context that was hidden gets no `SetUpdate` ticks: a result that is spoken from an update loop after the screen closed never fires. Keep the popup shown until the result is spoken (Great People: `Close()` is deferred while a request is pending).
- Skip / Fortify / Sleep: `CanStartOperation` returns false with NO failure reason whenever two awake own units of the same formation class share a tile (game string `LOC_CITY_UNIT_STACK_ILLEGAL`, ActionPanel blocker "MOVE STACKED UNIT"). Escort formations are not the cause (round 12, Rome fixture: Settler + Builder). The mod says which unit it is stacked with.
- Target modes must not rely on `ClickCursorPlot`: the click lands at the screen centre, not at the hub cursor. Use WorldInput's per-mode requests (HubTargets `m_directRequests`, `ConfirmFormation`) instead of a mouse click.
- City ranged attack "already attacked": the engine has no query for it. `District:CanAttack()` stays true (it is only the "can strike" capability of the banner), `CityManager.CanStartCommand(RANGE_ATTACK, true)` returns no failure reasons, and `GetCommandTargets` returns an EMPTY table after the attack even with enemies in range. The attacked flag survives a save/load. `HubTargets.CityAttackReason` therefore says "already attacked this turn" when we recorded the attack this turn (`HubTargets.cityAttackTurn`, keyed owner:id, city modes only); with only a visible enemy within 2 tiles it hedges ("no enemy it can target in range, or it already attacked this turn"). Encampment-type districts have their own `DISTRICT_RANGE_ATTACK` mode (separate attack), which is probably how a city "attacks twice" per turn.
- Air units (verified by keys, fixture `air-ready`, scenario `air-units`): the Tab menu of a Fighter/Bomber has Priority Target, Air Attack (R), Deploy, Re-Base (Shift+R), Skip, Sleep, Alert, Delete. REBASE mode: X lists own cities/aerodromes in range, Enter -> `UnitManager.RequestOperation(REBASE, {PARAM_X, PARAM_Y})` moves the unit at once and uses up all its moves ("Rebasing" is the only line; the unit then shows 0 moves). AIR_ATTACK: X lists enemies with the combat preview, Enter sends AIR_ATTACK, the combat line arrives ~3 s later (Fighter and Bomber both work, the Bomber also hits barbarians). The first air flight opens a "Historic moment: Taking Flight" popup that swallows keys (dismiss with Enter). DEPLOY mode: `GetOperationTargets(DEPLOY)` has no plots for a plain city fighter, the menu entry stays "unavailable" and the mode (forced via `UI.SetInterfaceMode`) says "Not possible there"; the real use of Deploy (carrier/airstrip) is UNVERIFIED. There is no Patrol operation in this game version. Create() spawns air units into an Aerodrome city without resource checks.

## Lua limits

- A chunk holds at most 200 local variables (functions included): `InGameAccess.lua` hit it (the file did not compile: "too many local variables"). The hub is now split into `Accessibility/Hub*.lua` modules (one global table each, `function HubX.Name()` for anything shared): each file stays far below the limit (the hub itself has 2 top-level locals). `util/lint.py` warns when a file passes 185 top-level locals; luacheck itself does NOT report the limit; count with `grep -c '^local ' <file>`.

## Turn end handed back (verified 2026-10-24, pt-modes-t90)

- `Events.LocalPlayerTurnEnd` also fires when ending the turn is refused during the end-of-turn processing (an auto-exploring scout or a unit with a queued move finishes and asks for orders). `IsTurnActive()` is false at the event, true again within 0.1 s, but `Events.PlayerTurnActivated(local, false)` and `Events.LocalPlayerTurnBegin` (same game turn) only follow ~3 s later, and `/InGame/HUD/ActionPanel/EndTurnText` says "Please wait" until then, then "Unit needs orders". `HubAnnounce.OnLocalPlayerTurnEnd` therefore says "Turn ended" and, when the turn is active again 0.4 s later (or on PlayerTurnActivated with isFirstTime false), "Turn not ended: <panel text>" (waits for the text, max 6 s; a World Congress in session says so instead).
- Plot memory: `plot:GetImprovementType()` on a revealed plot in the fog returns the live improvement (no `GetRevealed*` API exists in the UI Lua); only what the player saw while the plot was visible may be spoken (`HubPlaces` m_seen, shared with the settle scan via `HubPlaces.IsCampRemembered`). The memory is empty after a load.

## Corps, armies, carriers, nukes (verified by keys 2026-10-24, fixture `air-ready`, scenarios `corps-army`, `carrier`, `nuke-ready`)

- `Players[0]:GetCulture():SetCivic(CIVIC.Index, true)` grants a civic (Nationalism = corps, Mobilization = armies); `GetTechs():SetTech(idx, true)` a tech. Forming a corps/army uses up all moves of the unit; a corps shows only "Delete Unit" in its Tab menu that turn. A unit adjacent to a corps sees "Form Army" (Control+Shift+F) instead of "Form Corps" (Shift+F); `GetMilitaryFormation()` is 1 corps, 2 army. The first corps/civic opens a "Historic moment" popup that swallows keys.
- Aircraft Carrier: `Units:Create(UNIT_AIRCRAFT_CARRIER, x, y)` on a water plot next to a coastal city works. A Fighter's Re-Base targets (X) include the carrier plot ("Aircraft Carrier, Coast ..."); Enter rebases onto it (all moves used). Deploy stays "unavailable" and Deploy mode has no target even next to a carrier. The carrier's own menu: Move To, Skip Turn, Sleep, Alert, Automate Exploration, Delete Unit (no air actions).
- Nukes: `Players[0]:GetWMDs():ChangeWeaponCount(GameInfo.WMDs["WMD_NUCLEAR_DEVICE"].Index, 1)` makes the Bomber's WMD strike for the nuclear device startable (no project or tech needed); the thermonuclear one stays "No available warhead.". WMD mode: `UI.SetInterfaceMode(InterfaceModeTypes.WMD_STRIKE, {[UnitOperationTypes.PARAM_WMD_TYPE]=idx})`. Enter on a target is `ClickCursorPlot` (#KEYNAV_MOVE 960,540 then #KEYNAV_CLICK - L): the real click lands, the game opens its "ARE YOU SURE? Commence bombing mission?" popup (Stand down is the default button; Enter cancels and nothing is launched).

## Barbarian scouts and camps (verified by the verifier, round 24)

- UnitFlagManager.lua (~1507) draws the barbarian scout "!" when `unit:GetBarbarianTargetPlayer() == local player`; readable in the InGame (UI) state. Value: target player id, -1 none. HubEnemies.CheckScouts alarms on exactly this flag (once per scout).
- `Events.BarbarianSpottedCity(playerID, unitID, cityOwner, cityID)` fires when a barbarian first sees a city; HubEnemies.OnBarbarianSpottedCity runs the scout check promptly for our cities (during the AI turn the turn start does it).
- `unit:GetBarbarianTribeIndex()` + `Game.GetBarbarianManager():GetTribeCampLocation(tribe)` give the scout's camp (x,y) (e.g. tribe 13 -> 55,21). We name it ("toward its camp 4 tiles north-east") only when `PlayersVisibility[local]:IsRevealed(plot)`; otherwise just "heading away from <city>".
- `UnitManager.GetActivityType` returns hashes (HOLD 75236491, AWAKE 1797587246, OPERATION 1225574625); `GetQueuedDestination` is nil for barbarian scouts; `HasPendingOperations` is true on a trip.
- `GetFormationUnitCount` returns 2 for both members of an escort, with the same `GetFormationID`.
- The "Raid: N barbarians near X" line counts land units only (`GameInfo.Units[type].Domain ~= "DOMAIN_SEA"`); ships stay in the Enemies line.
