# Engine notes (Civ VI Lua, as verified in this project)

Facts about the game engine that cost time to find, grouped by topic. Design and status of features: `features.md`; open work: `backlog.md`; how-to for screens: `keynav-guide.md`; the test harness (civctl, regress, fixtures): `.claude/skills/civ-test/SKILL.md`. Add new facts under the matching topic; "verified" means checked in the real game (fixture or scenario named where useful), "unverified" means read from the game files or offline.

## FORBIDDEN calls

Each of these has crashed or wedged the game, or wasted a play session:

- Hand-made `PlayerOperations.APPOINT_GOVERNOR` / `PROMOTE_GOVERNOR` parameters. Appoint through the Governors screen (F10). (One verification used them to give the Merchant the Contractor promotion; do not copy that.)
- Faked popup-manager locks, and firing `NaturalDisasterPopup_Shown` / `NaturalDisasterPopup_Closed` unbalanced: the `BulkHide` count goes wrong and the game crashed once. A real disaster could not be triggered (`GameRandomEvents.ApplyEvent` did nothing visible).
- `Network.LoadGame` from the `InGame` state: returns `true`, then the game crashes or hangs at "Continue Game". Use `civctl load` (it goes through `MainMenu`). Re-probed 2026-10-29, all hang at the load screen after `LoadScreen: OnLoadGameViewStateDone` (no `Continue Game` speech, Enter does nothing, tuner unreachable, needs stop/start): `Network.LeaveGame(); Network.LoadGame(...)` in one tuner call from the `LoadGameMenu` state, and the real in-game Load Game screen (menu, pick save, confirm Yes). So there is no faster in-game load path; the main-menu round trip (~41-44 s per `civctl load` incl. advisor clearing) is the only reliable one.
- Observer autoplay (`AutoplayManager.SetObserveAsPlayer(PlayerTypes.OBSERVER)`): 3x slower, tears down the UI contexts for ~80 s, thousands of `MinimapPanel.lua` errors. Use `SetObserveAsPlayer(0)`.
- `UI.RequestAction(ActionTypes.ACTION_ENDTURN)` as an end-turn shortcut: does nothing while units need orders. `civctl endturn` is the safe form for setup/verification (it checks `NotificationManager.GetFirstEndTurnBlocking` and `UI.CanEndTurn` first, like `ActionPanel.lua` `DoEndTurn`, and names the blocker); play-tests still end turns with Enter.
- `key Shift+Tab`: opens the Steam overlay, which eats the key-up, so the game keeps Shift logically held (Down does nothing, Tab goes backwards in every screen) until both Shift keys are released. `civctl key` refuses it and releases modifiers after every chord; `civctl key-release` frees a stuck one (by hand: `civctl key LShiftKey` then `RShiftKey`; a plain `Shift` key name does not work). Shift+Tab never reaches the game with the overlay on (the next one closes the overlay), so use Control+Tab for "previous" in our screens (the deal screen accepts it); do not use Shift+Tab for new features.
- Sending NumPad `+` / `-` (`civctl key Add` / `Subtract`): JAWS commands; `Subtract` turns on the JAWS cursor, which swallows arrow keys system-wide (injected keys too, survives a game restart) until `Add` turns it off. civctl refuses them. Use `OemPlus` / `OemMinus`.
- Synthetic notifications (USER_DEFINED / CHOOSE_TECH) do not behave like real ones: trigger the real event instead (finish research, end turn).
- Hot reloading the deal view while a diplomacy session is open leaves the session in a state where Make Deal no longer opens the screen and Escape does nothing (recover with `lua DiplomacyActionView OnForceClose()`); test deal changes after a restart, not with `deploy`.
- `DealManager.SendWorkingDeal` from the InGame state: does nothing visible and leaves autoplay (`advance`) stuck.
- Target modes must not rely on `ClickCursorPlot`: the click lands at the screen centre, not at the hub cursor. Use WorldInput's per-mode requests (HubTargets `m_directRequests`, `ConfirmFormation`) instead of a mouse click. (Exception: the WMD strike confirmation, see Units.)

## Lua sandbox and limits

- No `debug` table (`xpcall` handlers must not call `debug.traceback`), no `%f` frontier patterns, no `_G` (use the direct global names; verified in game).
- `rawset` does not exist (calling it errors; the city report item broke on it). The game's own UI Lua never uses `rawset`/`rawget`/`rawequal`, so `.luacheckrc` lists them in `not_globals` and lint reports their use. Check `setmetatable`, `getmetatable`, `debug`, `os`, `io`, `load*` and `dofile` availability before using them.
- `local x:table = value` is a RUNTIME type check in Civ's Lua: assigning a number gives "Type check failed: (expected 'table', but got 'number')". `Game.GetWorldCongress():GetResolutions(pid)` (and `GetReview(pid).Resolutions`) contain a numeric `Stage` key next to the resolution tables, so loop variables over them must not be annotated `:table` (the game's own loops test `type(v) == "table"`).
- A typed local keeps its type for the whole scope: `local alarmed:table = nil;` followed by `alarmed = false` fails to LOAD the file ("set local of type table to boolean"; it killed the whole hub once). nil is always allowed. `util/typedlocals.py` (run by `lint.py`) flags later assignments of a literal (`true/false`, number, string, `{}`, `function`) of another type; expressions are not checked, so keep a typed local's value type stable or leave it untyped.
- A chunk holds at most 200 local variables (functions included): `InGameAccess.lua` hit it (the file did not compile: "too many local variables"). The hub is split into `Accessibility/Hub*.lua` modules (one global table each, `function HubX.Name()` for anything shared); each file stays far below the limit (the hub itself has 2 top-level locals). `util/lint.py` warns when a file passes 185 top-level locals; luacheck itself does NOT report the limit; count with `grep -c '^local ' <file>`.
- `Events.InputActionTriggered.Call( id )` exists but does nothing (verified). Fire an input action through a LuaEvent that the owning context answers (e.g. the lenses list uses `LuaEvents.SRA_ToggleLens`, handled by an `ImportFiles` copy of `MinimapPanel.lua`).
- UI buttons are read with `Controls.X:IsHidden()`, `:IsDisabled()`, `:GetTextControl():GetText()`, `:GetToolTipString()`.

## Input and keys

- The engine `Keys` enum is NOT Win32: Return 102, Escape 103, Down 86, `VK_BACK` 104, `VK_OEM_PLUS` 88, `C` 3. Always compare against `Keys.VK_*` / `Keys.<Letter>`. `WorldCongressBetweenTurns` compares with `Keys.VK_ENTER`, which may not exist; `VK_RETURN` is the engine name.
- Input order in game: the hub's `SetInputHandler` (InGameAccess) runs before `WorldInput` and `ActionPanel`. Returning `true` on KeyDown/KeyUp stops the lower contexts' raw handlers (ActionPanel acts on Enter KeyUp) and the input action the key would have produced (a consumed Down never fires `CameraPanDown`). The reverse holds too: a key a context handler consumes never becomes an input action. Hotkeys that are plain input actions (`Events.InputActionTriggered`) arrive only if nobody consumed the key. Popups and the in-game menu sit above the hub and consume everything while open.
- A rebinding key is only recorded by the engine if the input handler returns false for it; key-state polling needs `civctl key <Key> -Hold 200`.
- Escape on the map with nothing open opens the in-game menu (`civctl menu` tells which).
- While an `EditBox` has focus the context's input handler gets no key events; Enter fires the commit callback; Escape reverts the text, fires the commit callback and its KeyUp still reaches the context. `SetNumberInput(true)` rejects characters without a callback. See `Accessibility/KeyNavEditBox.lua`.
- A mouse resting on a slider eats arrow keys (the context stops receiving them).
- The in-game top options menu (Escape) does not receive the real mouse: hover and clicks go to the map under it (a Coast tooltip shows). Everything there must work by direct calls (announce on Up/Down, Enter calls the button's handler), not through KEYNAV_MOVE/KEYNAV_CLICK.
- Both trade choosers (below) are contexts of `InGame.xml` listed after ActionPanel / ProductionPanel, so they get keys before them (the hub, added last, before everything). `TradeOriginChooser`'s own Escape (`AnimSidePanelSupport` OnInputHandler) only hides the panel; the interface mode TELEPORT_TO_CITY stays until something else changes it.
- `Input.GetGestureDisplayString( Input.GetActionId( name ), 0 )` gives the current binding text of an input action (what the help list shows).
- A popup that takes input with `InputAtCurrentParent` (Great People) can let arrow keys reach the map cursor when the hub's handler runs before it: the hub must stand down while such a popup is shown.

## Contexts, visibility and update loops

- A context added with `AddUserInterfaces` starts hidden, and a hidden context gets no input actions or `SetUpdate` ticks: call `ContextPtr:SetHide(false)` first.
- A result that is spoken from an update loop after the screen closed never fires, because the closed context gets no `SetUpdate`. Keep the popup shown until the result is spoken (Great People: `Close()` is deferred while a request is pending), or time it from a context that stays shown (the hub: `LuaEvents.SRA_TradeResult` after a trade route request).
- `UnitSelectionChanged` and other events also reach hidden contexts; only input and `SetUpdate` do not.
- `Events.X.Add` / `LuaEvents.X.Add` need a matching `.Remove` on shutdown (use `SRListen` + `SRUnlistenAll`, `Accessibility/SRListen.lua`), else a hot reload leaves a stale instance that speaks twice.
- Hot reload: see the civ-test skill. Hot-reloading the deal view during a diplomacy session breaks it (FORBIDDEN).
- Popup state in the World Congress scripts is file-local, see World Congress.

## Overrides: ReplaceUIScript vs ImportFiles

- Base-game UI files (`Base/Assets/UI/...`): override with `ImportFiles` in the `.civ6proj` (`FrontEndActionData` and/or `InGameActionData`, priority 10001); a `print` from the copy shows in `Lua.log` and tells which context loads it. Check `DLC/Expansion1|2/UI/Replacements`: the expansion may replace the file and `include` the base one, so override the file that holds the code. An `include`d base file can be replaced with ImportFiles (CityStates).
- The base `MinimapPanel.lua` CAN be overridden with `ImportFiles` even with Gathering Storm (the Expansion2 replacement `include`s the base file), while a `ReplaceUIScript` of the Expansion2 file (`MinimapPanel_SRA`) never loaded (the DLC's wins).
- DLC `UI/Additions` scripts (Governor panels, HistoricMoments, NaturalDisasterPopup, World Congress): ImportFiles does NOT work (the DLC's own ImportFiles is applied later and the context is loaded by path). Use `ReplaceUIScript` with `LuaContext` = the file stem (`GovernorPanel`; the child context ID `DetailsPanel` does not match), file as `UI/Replacements/<Name>_SRA.lua`.
- Expansion replacements of base files can also win over an ImportFiles copy: DiplomacyDealView (verified): the XP2 file in `DLC/Expansion2/UI/Replacements` replaces the base one at the same or higher priority; our copy is `UI/Replacements/SRA_DealView.lua`, registered with `ReplaceUIScript` (LuaContext `DiplomacyDealView`, LuaReplace that file); then `ScreenReaderAccess: DiplomacyDealView copy loaded` appears once at game start.
- Wildcard include trap: the file name of a copy must NOT start with a prefix that a wildcard `include("Prefix_", true)` loads. The deal view copy ends with `include("DiplomacyDealView_", true)`; a file named `DiplomacyDealView_SRA.lua` included itself ("C stack overflow: too many (128) nested C function calls" while the game loaded). Code that sits after the wildcard include (the `PopulateAvailableFavor` wrapper) stays just before `Initialize()`. `util/overridecheck.py` checks this statically.
- `Accessibility/` helpers that a front-end screen includes must be in BOTH `FrontEndActionData` and `InGameActionData`, else the screen script silently aborts after returning from a game.
- New files, `.civ6proj` / `.modinfo` and `Database/*.sql` changes need `build` + restart; Lua edits hot-reload with `civctl deploy` (never `build` while the game runs).

## Events: what fires when

- Unit orders: `UnitOperationStarted` for most actions (fortify, sleep, build improvement, found city). Automate Exploration and Fortify Until Healed fire only `UnitOperationAdded`. The game re-adds the operation for already automated units, so only trust it within ~2 s of a key press.
- `UnitSelectionChanged`: when the only ready unit is already selected, Next Action re-selects it WITHOUT an event.
- `UnitKilledInCombat(killedPlayer, killedUnit, killerPlayer, killerUnit)`: the killed unit is already gone at event time (cache names while alive). Attacker/defender come from `CombatVisBegin`.
- `GoodyHutReward(playerID, unitID, goodyHutTypeHash, subTypeHash)` (verified): the hashes are `DB.MakeHash(GoodyHuts.GoodyHutType)` / `DB.MakeHash(GoodyHutSubTypes.SubTypeGoodyHut)` (`GameInfo.GoodyHutSubTypes[hash]` does NOT work: loop and compare). `Description` is a format string taking the amount (`Locale.Lookup(desc, 60)`); empty for boosts (the boost popup speaks them) and units/population/relic. Amounts of gold/faith in the ModifierArguments are scaled by `GameSpeeds.CostMultiplier/100` (Online: 60 faith -> 30, checked against the balance). Spoken by `HubEvents.OnGoodyHutReward`. A hut for tests: `util/scenarios/goody-hut.lua` (see Tuner recipes).
- Purchases: gold/faith spending arrives as treasury/faith events ("Bought X, N gold left"); a production change as `CityProductionQueueChanged`; governors `GovernorAppointed`, `GovernorAssigned`; saves `Events.SaveComplete` (within 1.5 s).
- `LoadScreenClose` marks the end of a load; a unit selected during the load is announced after it. A turn-1 save shows the Gathering Storm intro again after loading (Escape).
- `Events.BarbarianSpottedCity(playerID, unitID, cityOwner, cityID)` fires when a barbarian first sees a city (handled in `HubEnemies.OnBarbarianSpottedCity`).
- `UnitManager.PlaceUnit` fires no visibility event (nothing to listen to for a unit placed that way).
- `Events.LocalPlayerTurnEnd` also fires when the end of turn was refused, see Turn flow.
- `LuaEvents.DiploPopup_DealUpdated` / `Events.DiplomacyIncomingDeal`: see Diplomacy and deals.

## Map, plots and visibility

- `UI.GetPlotScreenPos` does not exist; use `UI.LookAtPlotScreenPosition(x, y, 0.5, 0.5)` and `UI.GetPlotCoordFromNormalizedScreenPos` (takes -1..1, y up).
- Hex geometry: odd rows shift half a plot east (`Map.GetAdjacentPlot(4,4,NE) = (4,5)`).
- No revealed / last-seen improvement accessor exists: the UI state's `plot:GetImprovementType()` returns the LIVE improvement even on unrevealed plots and in the fog (the fogged cursor text and the game's plot tooltip show it; no `GetRevealed*` API in the UI Lua). `PlayersVisibility[p]` has only `IsRevealed / IsVisible / GetState`. The mod therefore speaks only what the player saw while the plot was visible (`HubPlaces` m_seen, shared with the settle scan via `HubPlaces.IsCampRemembered`; the memory is empty after a load). `HubPlaces.Prime` accepts barbarian camps on revealed, not visible plots once after a load ("last seen", no guards); a camp that spawned in the fog after the reveal can leak once.
- `CanStartOperation(FOUND_CITY, plot, false, true)` tests the plot given but says no for every plot at 0 moves.
- Tuner: `PlayersVisibility[0]:ChangeVisibilityCount(plotIndex, 1)` makes a plot visible (a unit spawned in the fog is not in the hub's hostile list until then).
- Barbarian camp tuning constants: `BARBARIAN_CAMP_MINIMUM_DISTANCE_CITY` 4 / `_ANOTHER_CAMP` 7 are in `GameInfo.GlobalParameters`.
- `GameRandomEvents.GetCurrentTurnEventAtPlot` gives counts only (PopLost, UnitsLost, TilesDamaged, FertilityAdded), no text.
- `Search.Search` is the engine's full-text search (the tree and Civilopedia searches use it).

## Units

- Operations and commands: `CanStartOperation` / `CanStartCommand` quirks are in Combat and cities (purchase) and Map (found city).
- Skip / Fortify / Sleep: `CanStartOperation` returns false with NO failure reason whenever two awake own units of the same formation class share a tile (game string `LOC_CITY_UNIT_STACK_ILLEGAL`, ActionPanel blocker "MOVE STACKED UNIT"). Escort formations are not the cause (Rome fixture: Settler + Builder). The mod says which unit it is stacked with.
- Stacking: one unit per `Units.FormationClass` per tile, also in a city; a formation counts as both its classes. `UnitManager.GetMoveToPathEx` returns 0 plots for a Builder, a free Settler or a Spearman+Settler formation to a tile holding another own civilian-class unit (a Great General); a Heavy Chariot (land combat) paths fine.
- Formations survive inside a city: Spearman + Settler in Rome both report `GetFormationUnitCount() == 2` the next turn (it returns 2 for both members of an escort, with the same `GetFormationID`). Shift+E on an escorted unit runs UNITCOMMAND_EXIT_FORMATION (a plain command, no speech by itself); a Great General can be an escort partner too.
- Corps and armies (verified by keys, fixture `air-ready`, scenario `corps-army`): `Players[0]:GetCulture():SetCivic(CIVIC.Index, true)` grants a civic (Nationalism = corps, Mobilization = armies); `GetTechs():SetTech(idx, true)` a tech. Forming a corps/army uses up all moves of the unit; a corps shows only "Delete Unit" in its Tab menu that turn. A unit adjacent to a corps sees "Form Army" (Control+Shift+F) instead of "Form Corps" (Shift+F); `GetMilitaryFormation()` is 1 corps, 2 army. The first corps/civic opens a "Historic moment" popup that swallows keys.
- Air units (verified by keys, fixture `air-ready`, scenario `air-units`): the Tab menu of a Fighter/Bomber has Priority Target, Air Attack (R), Deploy, Re-Base (Shift+R), Skip, Sleep, Alert, Delete. REBASE mode: X lists own cities/aerodromes in range, Enter -> `UnitManager.RequestOperation(REBASE, {PARAM_X, PARAM_Y})` moves the unit at once and uses up all its moves ("Rebasing" is the only line; the unit then shows 0 moves). AIR_ATTACK: X lists enemies with the combat preview, Enter sends AIR_ATTACK, the combat line arrives ~3 s later (Fighter and Bomber both work, the Bomber also hits barbarians). The first air flight opens a "Historic moment: Taking Flight" popup that swallows keys (dismiss with Enter). DEPLOY mode: `GetOperationTargets(DEPLOY)` has no plots for a plain city fighter, the menu entry stays "unavailable" and the mode (forced via `UI.SetInterfaceMode`) says "Not possible there"; the real use of Deploy (carrier/airstrip) is UNVERIFIED. There is no Patrol operation in this game version. `Create()` spawns air units into an Aerodrome city without resource checks.
- Aircraft Carrier (verified, scenario `carrier`): `Units:Create(UNIT_AIRCRAFT_CARRIER, x, y)` on a water plot next to a coastal city works. A Fighter's Re-Base targets (X) include the carrier plot ("Aircraft Carrier, Coast ..."); Enter rebases onto it (all moves used). Deploy stays "unavailable" and Deploy mode has no target even next to a carrier. The carrier's own menu: Move To, Skip Turn, Sleep, Alert, Automate Exploration, Delete Unit (no air actions).
- Nukes (verified, scenario `nuke-ready`): `Players[0]:GetWMDs():ChangeWeaponCount(GameInfo.WMDs["WMD_NUCLEAR_DEVICE"].Index, 1)` makes the Bomber's WMD strike for the nuclear device startable (no project or tech needed); the thermonuclear one stays "No available warhead.". WMD mode: `UI.SetInterfaceMode(InterfaceModeTypes.WMD_STRIKE, {[UnitOperationTypes.PARAM_WMD_TYPE]=idx})`. Enter on a target is `ClickCursorPlot` (#KEYNAV_MOVE 960,540 then #KEYNAV_CLICK - L): the real click lands, the game opens its "ARE YOU SURE? Commence bombing mission?" popup (Stand down is the default button; Enter cancels and nothing is launched).
- Allowed hand-built request: `HubTargets.ConfirmTeleport` mirrors WorldInput.lua `TeleportToCity()` exactly (PARAM_X/PARAM_Y of the chosen city, CanStartOperation, RequestOperation, SetInterfaceMode(SELECTION)), because for non-traders no panel owns TELEPORT_TO_CITY. Transfer is instant and uses all moves.
- A unit created by the tuner and given `UnitManager.RestoreMovement` has its moves in the UI at once (the trader-in-capital scenario works without ending the turn).
- Scout auto-explore end: `HubPlaces` keeps its "exploring" flag until a player order, so a scout the game stopped is still listed as "exploring". Unit activity goes ACTIVITY_AWAKE at every turn start before the operation resumes (and `advance` autoplay cancels it), so a stop cannot be told by activity alone; a 1 s recheck on `UnitActivityChanged` was drafted but could not be verified (reveal-all + explore never ended on its own).
- `UnitManager.GetActivityType` returns hashes (HOLD 75236491, AWAKE 1797587246, OPERATION 1225574625); `HasPendingOperations` is true on a trip.
- Failure reasons for actions come from the engine: `UnitManager.CanStartOperation` result tables (`FAILURE_REASONS`, localized), `CombatManager.IsAttackChangeWarState` for "would declare war", and for builders the per-improvement check over `Improvement_ValidBuildUnits` ("not possible on this tile" / "already built here" / "no moves left" are our fallbacks when the engine gives no reason).
- Make Trade Route / Transfer to Another City have no tooltip when disabled; the Tab menu text is composed from `GetNumOutgoingRoutes` / `GetOutgoingRouteCapacity` (UnitPanel).
- `StatusMessagePanel` (base) shows the game's own tagged messages; our copy drops unit-versus-unit combat lines the hub already spoke (`LuaEvents.SRA_CombatSpoken` within 2 s) by matching the localized templates built from the LOC tags (`LOC_GRAMMAR_A_AN` is matched as `an?`; city/district targets are never dropped).
- `UnitOperationTypes.SKIP_TURN` is nil in the UI Lua: use `GameInfo.UnitOperations["UNITOPERATION_SKIP_TURN"].Hash`. `CanStartOperation` for skip/sleep also returns false with no reasons for an unescorted settler or a besieged unit.
- `UnitExperience:CanPromote` does not exist: use `UnitManager.CanStartCommand( unit, UnitCommandTypes.PROMOTE )`.
- Activation tiles: `GetActivationHighlightPlots` exists on `unit:GetGreatPerson()`, `unit:GetArchaeology()` and `unit:GetRockBand()`; naturalists use `Game.GetNationalParks():GetPossibleParkTiles( playerID )`.
- `unit:IsEmbarked()` exists.
- Settling advice: `Players[p]:GetGrandStrategicAI():GetSettlementRecommendations( 5 )` returns plots with reasons (see `WorldViewIconsManager.lua` `AddSettlementRecommendations`).

## Combat and cities

- City ranged attack "already attacked": the engine has no query for it. `District:CanAttack()` stays true (it is only the "can strike" capability of the banner), `CityManager.CanStartCommand(RANGE_ATTACK, true)` returns no failure reasons, and `GetCommandTargets` returns an EMPTY table after the attack even with enemies in range. The attacked flag survives a save/load. Handled in `HubTargets.CityAttackReason`: it says "already attacked this turn" when we recorded the attack this turn (`HubTargets.cityAttackTurn`, keyed owner:id, city modes only); with only a visible enemy within 2 tiles it hedges ("no enemy it can target in range, or it already attacked this turn"). Encampment-type districts have their own `DISTRICT_RANGE_ATTACK` mode (separate attack), which is probably how a city "attacks twice" per turn.
- `CanStartCommand(PURCHASE)` does not check the balance (says yes, the request silently fails): check gold yourself.
- Placement failure reasons: `CityOperationResults.FAILURE_REASONS` (already localized text), `NO_SUITABLE_LOCATION` (true for wonders), plots under `PLOTS`; `city:GetBuildQueue():CanProduce(hash, false, true)` (4th argument = allow purchasing plots). District cap `1 + floor((pop - 1) / 3)`; at the cap every further district is refused with a population reason. What placing destroys: SUCCESS_CONDITIONS of `CanStartOperation(BUILD, {X, Y, type}, true)`. BUILD is refused on tiles the city does not own; the game buys a tile with a separate `PURCHASE` command.
- City power (required power) is recomputed only at a turn change: in the tuner it stays 0 until a turn change after creating a building (scenario `city-power`).
- `CityBuildQueue:CanProduce` is "Not Implemented" in GameCore_Tuner; `CityBuildQueue:CreateIncompleteDistrict(districtIndex, plotIndex, 100)` (GameCore_Tuner) places a finished district (used by the prophet-ready scenario to make a Holy Site).
- Research: `Player:GetTechs():GetTurnsToResearch(id)` is the time for THAT tech alone at the current science, not cumulative along the queue (fixture bug-tech-turns-mismatch: queue Writing 2, Currency 4, Sailing 2, Mathematics 13, Shipbuilding 13 (both cost 80), Buttress 24, Cartography 56, Square Rigging 68; an unqueued cost-20 tech says 2). The queue total is the sum of the entries (182 there), which is what the tree says as "about 182 turns"; a node's own number is "for this tech alone". The current research uses `GetTurnsLeft()`. Sums only: a list that happens to be non-decreasing is not cumulative.
- `CombatManager.SimulateAttackInto` also answers for non-adjacent targets (usable for previews before moving).
- `UnitKilledInCombat` reports killer -1 when a city (district) shot the unit.

## Barbarians

- `UnitFlagManager.lua` (~1507) draws the barbarian scout "!" when `unit:GetBarbarianTargetPlayer() == local player`; readable in the InGame (UI) state. Value: target player id, -1 none. `HubEnemies.CheckScouts` alarms on exactly this flag (once per scout); `HubEnemies.OnBarbarianSpottedCity` runs the check promptly for our cities (during the AI turn the turn start does it).
- `unit:GetBarbarianTribeIndex()` + `Game.GetBarbarianManager():GetTribeCampLocation(tribe)` give the scout's camp (x,y) (e.g. tribe 13 -> 55,21). We name it ("toward its camp 4 tiles north-east") only when `PlayersVisibility[local]:IsRevealed(plot)`; otherwise just "heading away from <city>".
- `GetQueuedDestination` is nil for barbarian scouts. A barbarian scout created through the tuner has tribe -1 and is never flagged: `GetBarbarianTargetPlayer` stays -1, so CheckScouts cannot be tested with it.
- The "Raid: N barbarians near X" line counts land units only (`GameInfo.Units[type].Domain ~= "DOMAIN_SEA"`); ships stay in the Enemies line.
- Barbarian camps (offline findings, unverified in game): `Improvements.xml` gives `IMPROVEMENT_BARBARIAN_CAMP` `DispersalGold="50"` and `RemoveOnEntry="true"`; the gold is scaled by `BARBARIAN_CAMP_GOLD_SCALING` (difficulty, `MODIFIER_PLAYER_ADJUST_GOLD_DISPERSAL`), so J says "about 50 gold" from the DB row and the destroyed line ("Barbarian camp destroyed, N gold", `HubPlaces.OnImprovementRemovedFromMap`) uses the treasury growth. No GoodyHutReward is expected for camps (the reward is a dispersal, not a goody hut). The NEW_BARBARIAN_CAMP notification has a location (`pNotification:GetLocation()`); `HubRegions.OnNotificationAdded` adds the position from the nearest city.

## Trade

(unverified, read from the game files)

- Selecting a trader with moves in a city makes `TradeRouteChooser` open by itself (`OnUnitSelectionChanged` -> `CheckNeedsToOpen` -> interface mode MAKE_TRADE_ROUTE); the Tab menu entry is just another way in. `RequestTradeRoute()` starts the operation and sets the interface mode back to SELECTION in the same call, which runs `Close()` (context hidden); see Contexts for timing the result.
- Trade route data: destinations in `m_unfilteredDestinations` (`owner`, `id`, `pathPlots`), yields `GetYieldsForRoute(origin, city[, true for the destination's side])` in `TradeSupport.lua` (`kYieldValues` indexed from 1 = `GameInfo.Yields[i - 1]`, `TooltipText`, `MajorityReligion`, `ReligionPressure`), a started route shows in `city:GetTrade():GetOutgoingRoutes()` (`TraderUnitID`).

## Diplomacy and deals

- With Gathering Storm `DLC/Expansion2/UI/Replacements/DiplomacyDealView.lua` (3232 lines, globals `g_LocalPlayer`, `g_OtherPlayer`, `g_AvailableGroups` ...) replaces `Base/Assets/UI/DiplomacyDealView.lua` through `ImportFiles` (default priority) in `Expansion2.modinfo`; it wildcard-includes `DiplomacyDealView_Expansion2.lua` (favor: `PopulateAvailableFavor`, `OnClickAvailableOneTimeFavor`, group types) before `Initialize()`. Expansion 1 has no deal view file. The XML is the base one (`Base/Assets/UI/DiplomacyDealView.xml`, a child context of `DiplomacyActionView.xml`) and is not overridden. How our copy is registered: Overrides.
- Deal item facts used: `DealManager.GetWorkingDeal(DealDirection.OUTGOING, local, other)`, `pDeal:Items()`, `pDealItem:GetType/GetFromPlayerID/GetAmount/GetDuration/GetSubType/GetValueType/GetValueTypeNameID/GetSubTypeNameID/IsLocked/IsUnacceptable/GetMaxAmount`, `pDeal:GetItemParent(item)` (items that come with a city have a parent and cannot be removed or edited alone). Changing an amount re-creates the item (`OnValueEditButton` removes and re-adds it), so its ID changes. `OnValueEditButton(itemID)` reads `Controls.ValueAmountEditBox:GetText()`, so a keyboard amount edit sets that text and calls it (no popup needed). `GetPossibleDealItems` entries carry `IsValid` / `ValidationResult` but no reason text; only resources have one (`LOC_DEAL_PLAYER_HAS_NO_CAP_ROOM` / `LOC_DEAL_AI_HAS_NO_CAP_ROOM`).
- The AI's answers arrive as `LuaEvents.DiploPopup_DealUpdated(otherID, action, text)` and `Events.DiplomacyIncomingDeal(from, to, action)` (`DealProposalAction`: PENDING, PROPOSED, ADJUSTED, ACCEPTED, REJECTED, EQUALIZE_FAILED ...); `UpdateProposalButtons` calls `SetLeaderDialog` on nearly every status update, so speak only a leader text that changed after the events were quiet. The deal is closed by `LuaEvents.DiploPopup_HideDeal` (from `DiplomacyActionView`) or by `OnContinue()` after the final accept.
- AI-initiated deal screen without a session (for tests): in the `DiplomacyDealView` state set `ms_OtherPlayerID` and `ms_InitiatedByPlayerID` to the AI, fill `DealManager.GetWorkingDeal(DealDirection.INCOMING, 0, ai)` and `ContextPtr:SetHide(false)`. Autoplay answers AI deals itself, so they do not show up while advancing.
- Multiplayer (verified 2026-10-29, host with one AI, Duel map): the FireTuner is NOT reachable in any network game (LAN or Internet; `civctl lua/status/menu/load` print 'Cannot connect to the tuner'), so MP tests are played with keys only (no tuner setup, no `civctl save`/`load`; leave with Escape menu, Exit to Main Menu or `civctl stop`). The Multiplayer menu is Play By Cloud, Internet, Internet (Unified PC Play, goes to a crossplay login lobby), Local Network, Hot Seat. Internet hosts have a `Private Game` checkbox on the setup screen / Game Setup tab (keynav item 'Private Game'; LAN has none). The deal screen (V, Make Deal) with an AI works in LAN and in a private Internet game exactly as in single player: both item lists fill. `DiplomacyDealView open: ... avail mine=N theirs=M netMP=...` in Lua.log shows what the deal screen found (diagnostic print in `SRA_Announce`). Deals with a second human are untested.
- `ExposedMembers` is one table shared by every UI Lua state (verified: set from `InGame`, read back in `InGameAccess`, `NotificationPanel`, `UnitPanel`, `WorldInput`, `DiplomacyDealView`, `GameCore_Tuner`; and the other way round).

## World Congress

(read from the scripts, unverified unless noted)

- Scripts in `DLC/Expansion2/UI/Additions` (`WorldCongressPopup/Intro/BetweenTurns`): use `ReplaceUIScript`. Popup state is file-local (`m_CurrentStage` 1/2/4, `m_CurrentPhase` 1/2, `m_kResolutionVotes`, `m_kResolutionChoices`); pulldown and check-box callbacks are closures, so the copy records them (`sraSelect`, `sraToggle`).
- A resolution needs >= 1 vote and a target to pass Next; voting for the other option zeroes the first and clears the target; removing the last vote is impossible. `GetVotesandFavorCost` is 0-based and cumulative, with `MaxVotes`.
- `LOC_NOTIFICATION_WORLD_CONGRESS_RESULTS_MESSAGE/_SUMMARY` exist in no text file (raw tag is returned); the notification is AutoActivate and opens the results popup.
- The ActionPanel label stays "End turn" after Escape closed the World Congress popup while the Resume Congress blocker is pending, and says "Please wait" while the congress is in session: the hub's N checks `Game.GetWorldCongress():IsInSession()`.
- After a World Congress session the engine selects no unit at the turn start (fixture pt-late-congress-t210: only the blocker "City ranged attack" was pending), so the results popup was the last thing said. `HubCore.m_repeatTurnLine` (set when the "WorldCongressResults" speech hold ends) makes `HubAnnounce.RepeatTurnStartLine` say the selected unit again, else "<blocker>. Enter handles it", once every popup is closed.

## Religion

- The Religion screen's `CanCreatePantheon` and the "Accumulate N Faith" text are computed when the screen is shown (UpdatePlayerData) and not refreshed while it stays open; closing and reopening shows current faith (probed with tuner ChangeFaithBalance). Vanilla behaviour, accepted.

## Turn flow

- `Events.LocalPlayerTurnEnd` also fires when ending the turn is refused during the end-of-turn processing (an auto-exploring scout or a unit with a queued move finishes and asks for orders) (verified, fixture pt-modes-t90). `IsTurnActive()` is false at the event, true again within 0.1 s, but `Events.PlayerTurnActivated(local, false)` and `Events.LocalPlayerTurnBegin` (same game turn) only follow ~3 s later, and `/InGame/HUD/ActionPanel/EndTurnText` says "Please wait" until then, then "Unit needs orders". `HubAnnounce.OnLocalPlayerTurnEnd` therefore says "Turn ended" and, when the turn is active again 0.4 s later (or on PlayerTurnActivated with isFirstTime false), "Turn not ended: <panel text>" (waits for the text, max 6 s; a World Congress in session says so instead). Compare the turn number / active player before saying "Turn ended".
- The local player is -1 during autoplay: nil-guard `Players[Game.GetLocalPlayer()]` in listeners.
- World Congress turn start and the ActionPanel label: see World Congress.

## Tuner and test setup

Availability: `EnableTuner 1` in `AppOptions.txt` (needs a restart). Only one tuner connection at a time. State indexes change on context reload: use names. The `InGame` state is absent at the front end; `AdvancedSetup` exists only once Create Game was opened. The tuner reaches all front-end states (`MainMenu`, `FrontEnd`, `HostGame`, `LoadGameMenu`, ...).

Not available in `GameCore_Tuner`: `UnitManager.Kill`, `Plot:IsRevealed`, `Network`, `UI.SelectUnit` (use the `InGameAccess` state for the last), `CityBuildQueue:CanProduce`, `Players[i]:IsMinor()` (a city-state is `PlayerConfigurations[i]:GetCivilizationLevelTypeName() == "CIVILIZATION_LEVEL_CITY_STATE"`). `AutoplayManager` exists in `InGame`, `InGameAccess`, `WorldInput`, not in `GameCore_Tuner`. In `GameCore_Tuner` these exist: `Players[i]:GetInfluence():ChangeTokensToGive(n)` / `GetTokensToGive()`, `Players[i]:GetGovernors():ChangeGovernorPoints(n)` / `GetGovernorPoints()` / `GetGovernorPointsSpent()`, `Map.GetAdjacentPlot(x, y, dir)`.

### Triggering popups and screens (for tests)

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

### Setup limits

- `CityStateCount` is limited by the map size (`MapSizes.xml`: Tiny max 10, Small 14, Standard 18, Large 22, Huge 24). A larger value reads back fine right after setting it, but the game then creates 0 city-states. The `crowded` profile clamps to the parameter's `Values.MaximumValue`.

## Tuner recipes

Tuner (`civctl lua <state> ...`):
- Spawn a unit: `Players[0]:GetUnits():Create(GameInfo.Units["UNIT_SETTLER"].Index, x, y)`; gold: `Players[0]:GetTreasury():ChangeGoldBalance(100)`; finish research: `Players[0]:GetTechs():ChangeCurrentResearchProgress(1000)`. Give a civic / tech: see Units (corps).
- Read a config value with `(GameConfiguration.GetValue(k))` (the extra parentheses matter: a missing key returns nothing). `lua` prints `print()` output; a single expression or `return x` is printed.
- Scenario scripts: `util/scenarios/` (`civctl scenario <name>`); a hut for tests: `ImprovementBuilder.SetImprovementType(plot, GameInfo.Improvements.IMPROVEMENT_GOODY_HUT.Index, -1)` in `GameCore_Tuner` (`util/scenarios/goody-hut.lua`).
- Map editing in `GameCore_Tuner` (verified 2026-10-29 on early-t60 and bug-builder-x-list-no-build; fixtures may be prepared with the tuner and saved with `civctl save <new-name>`, scripts don't run setup): `ResourceBuilder.SetResourceType(plot, GameInfo.Resources.RESOURCE_WHEAT.Index, 1)` adds a bonus/luxury/strategic resource (`-1, 0` removes it); `TerrainBuilder.SetTerrainType(plot, GameInfo.Terrains.TERRAIN_GRASS.Index)` changes terrain but CLEARS the resource on the plot (set the terrain first, then the resource); `TerrainBuilder.SetFeatureType(plot, GameInfo.Features.FEATURE_FOREST.Index)` / `(plot, -1)` adds/removes a feature; `ImprovementBuilder.SetImprovementType(plot, -1, -1)` removes an improvement. All pcall true, no crash. The change is visible at once, without a turn change: `plot:GetYield` (after SetResourceType; right after SetFeatureType(-1) the yield read stale), hub cursor speech ("Grassland, Wheat (bonus), river, yours, 3 Food", "Builder can build: Farm"), the builder X list (BuildScan) and `UnitManager.CanStartOperation(BUILD_IMPROVEMENT)` (state `InGameAccess`; `UnitManager.CanStartOperation` is nil in `GameCore_Tuner`). The edits survive `civctl save` + `load` (verified with fixture builder-farms-t83: a Wheat on a made grassland tile is offered as Farm by Builder X). Not verified: the 3D graphics of the plot (no screenshot taken); a resource on a terrain it cannot occur on (Wheat on desert is accepted and offers a Farm).
- Select a unit for a test (state `InGameAccess`; `UI.SelectUnit` works only there): `for _,u in Players[0]:GetUnits():Members() do if GameInfo.Units[u:GetType()].UnitType=="UNIT_BUILDER" then UI.SelectUnit(u) break end end`; the selection is announced.

Save (state `InGame`, works):
```lua
local s={}; s.Name="<name>"; s.Location=SaveLocations.LOCAL_STORAGE; s.Type=SaveTypes.SINGLE_PLAYER; s.IsAutosave=false; s.IsQuicksave=false; return tostring(Network.SaveGame(s))
```
`Saves\Single\<name>.Civ6Save` appears within ~2 s (quick saves in `Saves\Single\quick\`, autosaves in `auto\`; a new game moves old autosaves to `auto\prev\`). Documents is OneDrive-redirected on this PC: use `[Environment]::GetFolderPath('MyDocuments')`.

Load (state `MainMenu` ONLY; leave a running game first with `lua InGame 'Events.ExitToMainMenu()'` and wait for "Single Player"):
```lua
local s={}; s.Name="<name>"; s.Location=SaveLocations.LOCAL_STORAGE; s.Type=SaveTypes.SINGLE_PLAYER; s.IsAutosave=false; s.IsQuicksave=false; s.Directory=SaveDirectories.DEFAULT; return tostring(Network.LoadGame(s, ServerType.SERVER_TYPE_NONE))
```
Then `wait Continue Game` (~22 s), `key Enter -Settle 3000`, and the turn announcement (~6 s).

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
The AI plays our civ (UI visible, tuner works); `AutoplayManager.IsActive()` goes false after n turns and control returns with no popup open. ~6.5 s/turn around turn 71, ~21 s/turn around turn 115; poll at most every 30 s. The local player is -1 during autoplay.
