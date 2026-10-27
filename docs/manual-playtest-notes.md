# Manual play-test notes (user, 2026-10-26)

Findings from the user's own play-testing, researched but not yet worked on. Each entry: what was reported, what the code does today, and the proposed work. Triage these into the next round like play-segment findings.

## M1. Macro map overview: where am I on the continent? (feature, design needed)

**Reported:** there is no way to get map information at continent or region level, e.g. "Rome is in a grassland region on the coast, hills to the east, the rest of the continent is unexplored".

**Today:**
- Tile level only. The cursor's long description includes the continent name (`PlotDescription.lua`, `LOC_TOOLTIP_CONTINENT`), and the Continent lens (key 2, `LensText.lua`) names the continents you have seen and reads the continent per tile.
- J (places, `HubPlaces.lua`) lists cities, units and points of interest with a position relative to your cities ("3 tiles north-east of Rome"). It describes no terrain.
- Nothing summarises an area: which terrain dominates, coast and rivers, how big the continent is, how much of it is explored, who else lives on it.

**Proposed: an "area overview" command**, for the cursor's tile or a city. It reads only revealed plots, so it reveals nothing hidden.
1. **Around a point** (radius about 3-4, the city's working area): the dominant terrain and feature ("mostly grassland and woods, some hills"), coast, lake or river, mountains, and the count of luxury and strategic resources.
   - Example: "Rome: grassland and plains, woods to the north, on the coast and a river, mountains 3 tiles east, 2 luxuries, 1 strategic."
2. **Continent level:** the continent's name, its size in revealed tiles, how much of it you have explored, the cities on it (yours, rivals', city-states'), and its rough extent from your capital ("stretches about 12 tiles north and 6 south").
   - Example: "Rome is on Asia, about 40 percent explored. On it: 3 of your cities, Babylon's Ur, the city-state Geneva. Asia continues north beyond your borders."
3. **Optional, by direction:** a coarse sector summary ("north: unexplored; east: ocean after 5 tiles; south: Babylon's territory, desert"). This gives a blind player the mental map a sighted player gets from the minimap.

**Engine facts to probe before design** (one short `civctl lua` session):
- `Map.GetContinentPlots(index)` versus `Map.GetVisibleContinentPlots(index)` (the lens uses the latter): which plots does each return?
- Can `plot:GetContinentType()` be read on revealed but unseen plots without revealing anything?
- Is there an area or landmass id (`plot:GetArea()`), to tell islands apart from the continent?
- What does it cost to scan all revealed plots per keypress on a large map?

**Where it would live:** a new section in `HubPlaces.lua` or a small `HubOverview.lua` helper, keyed from the cursor and from the city report. The key and its `HelpText.lua` entry are still to choose (check `.claude/skills/civ-test/keymap.md` for free keys). Related: beginner gaps G6 (settle spot context) and G10 (vision) in `docs/beginner-guide-gaps.md`.

## M2. Control+F (Map Search) is silent and unusable (bug: inaccessible game screen)

**Reported:** Control+F, "find something on map", did not seem to work.

**What it is:** the game's own **Map Search** panel, not a mod feature.
- The key is the game's `OpenMapSearch` action (`keymap.md`: Control+F, the user's binding).
- `MinimapPanel.lua` shows the panel and fires `LuaEvents.MapSearch_PanelOpened`. Then `Popups/MapSearchPanel.lua` puts the keyboard focus in a text box (`MapSearchBox:TakeFocus()`).
- You type search words (resource, terrain, feature, district, improvement, city, civ, "unclaimed", ...), plus an optional exclude filter, and Enter (`OnSearchCommit`) searches the map incrementally.
- Matches are highlighted green and grouped. The Next and Prev buttons only move the camera (`UI.LookAtPosition`), and they have no keys.

**Why it seems broken:** the mod has no support for it at all (`grep MapSearch` finds nothing in `ScreenReaderAccess/`). Opening is silent, typing is silent, and suggestions, results ("N results") and Next/Prev are only shown visually. While the text box has focus, typed letters probably go into it rather than to the hub keys. Confirm in game what Escape does and whether hub keys still work.

**Proposed fix:**
1. Override `MapSearchPanel.lua`. The Gathering Storm and Barbarian Clans replacements (`MapSearchPanel_Expansion2.lua`, `MapSearchPanel_BarbarianClansMode.lua`) include it, so check whether ImportFiles or ReplaceUIScript is needed (`util/overridecheck.py`).
2. Speak when it opens: "Map search: type words, Enter searches, Escape closes".
3. Speak typed text on demand, and the suggestions (Tab completes).
4. After the search, speak the results: "12 matches in 5 groups".
5. Up/Down (or N/P) steps through the result groups. Each group moves the **map cursor** there, not only the camera, and is spoken like a J item ("Iron, 4 tiles south-east of Rome").
6. Escape closes it and speaks "Closed".

Alternative if the override is too costly: a mod-side search list (type a word, list the matching revealed plots) built on `GetPlotSearchTerms`-like matching. Overlap: J already covers resources and points of interest, so check what Map Search adds (terrain, districts, improvements, "unclaimed").

## M3. Send a unit to the cursor's tile (small feature)

**Asked:** after jumping the cursor to a tribal village from a notification, is there a menu that lists nearby units and sends one to it?

**Today:** yes, but not from the cursor itself.
- Control+N, then M on the notification opens the send list.
- J, then M on the village under points of interest, opens the same list.
- The list (`HubPlaces.BuildSendItems`) gives each unit with the turns it needs, fastest first, plus what it is doing and whether it is escorting someone. Enter sends the unit.
- With the cursor on the tile there is no such key. M on the map is the game's Move To, which needs a unit selected first and then a target tile.

**Proposed:** a cursor key (or Shift+M) that opens the same send list for the cursor's plot, with the plot's short description as the place name. It works for any tile, not only listed places. It also needs a `HelpText.lua` entry. Check `keymap.md` for a free key.

## M4. City report population row: put housing first (small tweak)

**Reported:** the population row says the population, then food and growth, and only at the end "housing 6 of 7". The population-out-of-housing number should come first.

**Today:** `CityReportData.lua` `GrowthItem` builds "Population 6, plus 4 food, grows in 11 turns, housing 6 of 14". It is checked in `test/lua/test_cityreport.lua:55`. No regress `.txt` expects this wording; only `.recorded.txt` sidecars contain it.

**Proposed:** "Population 6 of 7 housing, plus 4 food, grows in 11 turns". Drop the trailing "housing X of Y", keep the starving, housing-stopped and slowed states as they are, and update the Lua test. Optionally add "1 free housing" or "housing full" right after it, because that is what decides growth.

## M5. X in attack modes cycles through targets you cannot attack (behaviour change)

**Reported:** in a ranged attack, probably in a melee attack, and in a city ranged attack, X walks through many units that cannot actually be attacked. This gets worse in later eras, when more units are on the map.

**Today:** `HubCursor.ScanUnits` (X) collects every visible foreign unit within 10 tiles, and the same list is used in target modes.
- In an attack mode it only sorts the list: valid targets first, then hostile ones, then "would declare war", then the rest (`ScanEntryRank`, from `HubTargets.IsAttackTarget`). Every entry is still visited, and "Last target, X wraps" comes only after all of them.
- Modes that list their own plots (deploy, rebase, form corps, ...) already walk only valid plots (`HubTargets.ModeTargetPlots`). Attack modes don't, because `ModeTargetPlots` returns nil for them.
- City and district ranged attacks: when the mode opens, the cursor goes to the nearest target (`HubTargets.CursorToNearestCityTarget`, from `GetCityAttackTargets`). X then falls back to the all-units scan.
- The scan only finds plots with units. An enemy city or district with no unit in it is never an X stop, even when it can be attacked.

**Proposed:** in attack modes, X walks only plots the attack can hit this turn.
- **Ranged, air and strikes:** the plots from `GetAttackTargets( unit, operation )` (already in `HubTargets.lua`, `UnitManager.GetOperationTargets` with `MODIFIER_IS_TARGET`).
- **City and district ranged attacks:** `GetCityAttackTargets( city )`.
- **Melee (Move To with the Attack key):** hostile plots the unit can reach and attack this turn. Filter the current candidates with `HubTargets.IsAttackTarget`, and also add enemy cities and districts.
- **Declare war:** a target that would declare war is listed only if the game lists it as a target, and it keeps the "would declare war" warning.
- **No targets:** keep the current "No enemy in range of the X. Nearest enemy: ..." line. Optionally add how many hostile units are in view but out of reach.
- **Wrap line:** "Last target, X wraps" stays.

**Engine probe first:**
- Does `GetOperationTargets` return the plots of attackable cities and districts?
- In a war-declaring case, does it return plots of a civ you are at peace with?
- For melee, is there an operation-targets call for `UnitOperationTypes.MOVE_TO`, or must the per-plot check stay? It costs one `TargetInfo` per candidate.

**Regress impact:** these scripts use X and must be rechecked in attack modes: `attack-x-hostile-first`, `t128-attack-targets`, `city-x-order`, `attack-far-strength`, `air-units`, `carrier`, `nuke-ready`, `t60-enemy-at-capital`. `attack-x-hostile-first` checks the current order on purpose and will need its expectations rewritten. Update the X entry in `HelpText.lua` ("in an attack mode: only what you can attack").

## M6. X browser for units that act on highlighted tiles (feature)

**Asked:** great prophets, some great scientists, other great people and archaeologists act on specific tiles that the game highlights on the map. These units should get an X list of those tiles, and Enter should send the unit there, as for builders and settlers.

**Today:** X (`HubSettle.ScanKey`) opens a browser only for settlers (settle spots) and builders (`BuildScan_Improvements`). Every other unit falls through to the foreign-unit scan (`HubCursor.ScanUnits`), which is useless for these units. The only help is in U and the Tab menu: a great person that needs a district says "must stand on a completed Campus district. Nearest: Rome's Campus, 1 tile north-west" (`UnitPanel.lua` `SRNearestDistrict`, `PlotDescription_DistrictReason`).

**Where the game gets the tiles** (`DLC/Expansion2/UI/Replacements/SelectedUnit_Expansion2.lua`, `RealizeGreatPersonLens`):
- Great people whose `GreatPersonIndividuals.ActionEffectTileHighlighting` is set: `unit:GetGreatPerson():GetActivationHighlightPlots()`. Some also have an `AreaHighlightRadius`, the area their effect covers (`GetAreaHighlightPlots()`).
- Archaeologists (`Units.ExtractsArtifacts`): `unit:GetArchaeology():GetActivationHighlightPlots()`, the antiquity sites and shipwrecks they can excavate.
- Naturalists (`ParkCharges > 0`): `Game.GetNationalParks():GetPossibleParkTiles( playerID )`.
- Rock bands: `unit:GetRockBand():GetActivationHighlightPlots()`.
- `Units_XP2.CanCauseDisasters` units: `GameClimate.GetLocationsForPossibleTriggerableEvents`. This is probably not owned content; check `docs/game-content.md`.
- Not highlighted by the game, but the same need: great people that must stand on a completed district (prophet on a Holy Site, scientist on a Campus, ...). For them the list would be the completed districts of that type, from the same search `SRNearestDistrict` does.

**Proposed:** X with such a unit selected opens a tile browser modelled on the builder browser (`HubSettle.lua` `OpenBuildBrowser`).
- Each entry: what the tile is (e.g. "Antiquity site, Classical era", "Rome's Campus", a park spot naming its 4 tiles), turns to reach it, and the position relative to the nearest city. Nearest first.
- Space reads the tile. For an area-of-effect great person it also says what the effect would touch, if the game exposes that.
- Enter sends the unit (the builder's Move To path, with the danger guard). On arrival, say "Arrived. Enter activates <action>" and run the unit's own action button, like build on arrival (`HubSettle.OnArrived`, `SRA_RunUnitAction`).
- An empty list says why: "No antiquity sites revealed", or "You have no completed Holy Site".
- Escape closes the browser. Update the X entry in `HelpText.lua`.

**Engine probe first:**
- Which `GetActivationHighlightPlots` calls exist on the owned build?
- What do they return for a great person whose ability works anywhere?
- Do they include tiles in the fog or foreign territory?
- Can the antiquity site's era or type be read for the entry text (`plot:GetResourceType()` is `RESOURCE_ANTIQUITY_SITE` or `RESOURCE_SHIPWRECK`)?

**Fixtures:** none of the current chains is known to have an archaeologist or naturalist. The great person case can use the prophet and great person fixtures the round-21 scripts use. Archaeology needs a scenario that spawns an archaeologist after Natural History, with revealed antiquity sites.

## M7. City report: the religion row is hard to find and thin (tweak + small feature)

**Reported:** no section about the city's religious status in the city report.

**Today:** the row exists (`CityReportData.lua` `ReligionItem`, data from `CityReportGather.lua` `GatherReligion`), but it is the 13th or 14th of about 16 items. It comes after Focus, Tiles, Specialists and Resources, and the user's log shows them stopping at item 7 (Districts).
- With no majority religion it says only "Religion: none". The log has "Religion: none, 12 of 13" in a game where the user had founded Eastern Orthodoxy, the majority in 0 cities.
- Space adds the majority's beliefs, the pantheon, and "Other religions: <name> <followers>".
- It says nothing about where the city is heading: the pressure per religion, or how many citizens follow which religion out of the population.

**Proposed:**
1. Move Religion up, right after Loyalty (the other "who influences this city" row), before Defense. The order is set by the `Guard( Add(...) )` calls at the end of `CityReport_BuildItems`. Grep `test/regress/*.txt` for "of 15" or "of 16" and for item positions in city report scripts; the order change shifts them.
2. Main line: "Religion: Eastern Orthodoxy majority, 6 of 11 citizens" or "Religion: no majority. Eastern Orthodoxy 2, Buddhism 1 of 8 citizens". Name your own religion first. Say "pantheon <name>" only when it is the only thing there.
3. Space adds:
   - the pressure per turn per religion, if the engine exposes it (probe: `pCity:GetReligion():GetPressure` or similar; the game's CityPanel religion tab and `CityPanelOverview.lua` show "pressure");
   - the holy city, if it is one;
   - the beliefs.
4. Optionally, a letter key in the report that jumps to a row (R for religion), if the report has no letter jump yet. Add a `HelpText.lua` entry for it.

## M8. City report: "may turn to Free Cities" at full loyalty (minor bug)

**Seen in the user's log:** "Loyalty 100, plus 34 per turn, Loyal, may turn to Free Cities". `LoyaltyItem` appends "may turn to <rival>" whenever the data names a rival civ. At full loyalty and positive pressure that is misleading.

**Proposed:** say "may turn to X" only when loyalty is falling (perTurn < 0) or the level is below Loyal. Otherwise keep it in the Space detail as "would turn to X if loyalty ran out".

## M9. "Transfer to Another City" does nothing for great people (bug, cause found)

**Reported:** great people have a Transfer to Another City action (Shift+R), and pressing it seems to do nothing.

**From the user's log:**
- "Isaac Newton actions, 7 options ... Transfer to Another City, key Shift+R, 3 of 7".
- After Enter the only line is a plain cursor read ("Warrior, Plains, Farm, yours ... 1 tile south-east"). No mode line, and nothing about where the unit can go.
- For a trader the same action works: "Move trader to which city? 5 cities ... Trader moved to Winnipeg" (TradeOriginChooser).

**Cause:**
- The action enters `InterfaceModeTypes.TELEPORT_TO_CITY`. `HubTargets.lua` lists that mode in `m_chooserModes`: "the trade chooser panels own these modes, the hub stays silent and lets every key through".
- `Choosers/TradeOriginChooser.lua` `OnInterfaceModeChanged` opens only `if pSelectedUnitInfo.MakeTradeRoute`, so only for traders.
- For a great person (or any other unit with this operation) nothing owns the mode. The game waits for a mouse click on one of the highlighted cities (`WorldInput.lua` `OnInterfaceModeChange_TeleportToCity` highlights `UnitManager.GetOperationTargets( unit, UI.GetInterfaceModeParameter( UnitOperationTypes.PARAM_OPERATION_TYPE ) )`, and the click runs `TeleportToCity()`). The player hears nothing and has no keys.

**Proposed fix:**
- Treat `TELEPORT_TO_CITY` as a chooser mode only when the head unit's `GameInfo.Units[...].MakeTradeRoute` is true. Otherwise make it a hub target mode named "Transfer to city".
- **Opening line:** "Transfer Isaac Newton to which city? N cities". Better still, a list like the trader's: city name and distance, nearest first. Build it from the `GetOperationTargets` plots (add the mode to `HubTargets.ModeTargetPlots`, so X walks the valid cities in the cursor version too).
- **Enter:** move the cursor to the city and confirm through the game's own path, the click that runs WorldInput `TeleportToCity()` (`ClickCursorPlot`, as other target modes do). Never call `RequestOperation` with hand-built parameters. Then say "Isaac Newton moved to Montréal".
- **Escape:** cancels.
- **Engine probe:**
  - Which units get this operation: great people, and maybe others such as `UNITOPERATION_TELEPORT_TO_CITY` holders?
  - Which cities does `GetOperationTargets` return?
  - Is the transfer instant, and does it cost the unit's moves?
- **Fixture:** any save with an unactivated great person and two or more cities. The user's game had Isaac Newton in Ottawa at turn 103. pt-modes fixtures from rounds 20-21 have great people.

## M10. World Congress: how to add votes is never said on the resolution (tweak)

**Reported:** it was not clear how to put more votes on an option. The resolution line should say it.

**Today:** the keys exist: equals or Shift+Up adds a vote, minus removes one, and Left/Right switch between A and B (`HelpText.lua`, world congress entry; `WorldCongressPopup_SRA.lua`). But they are only reachable through the help list. In the user's session (turn ~110):
- Opening line: "World Congress. Resolutions: 2 to vote on. You have 410 diplomatic favor, 1 free vote each. Migration Treaty, option A: ..., no votes yet, 1 of 3. H for keys".
- Resolution line: "Migration Treaty, option A: <effect>, no votes yet, 1 of 3" (`WorldCongressText.lua` `WCText_ResolutionLine`). No key names.
- After a vote: "1 vote for A, free, 410 favor left, target needed, T to choose". It doesn't say that another vote can be bought, or what it costs.

**Proposed:**
1. On a resolution or proposal with no votes yet, append "equals adds a vote, Left and Right switch option". To keep later lines short, say it on the first focus only, or until the player has used the key once in the session.
2. On a resolution that holds votes, add the next step: "equals adds a vote for 20 favor, minus removes one". The cost is the difference between the next two entries of `GetVotesandFavorCost()`, the same numbers `WCText_VoteBlock` uses. At the maximum: "maximum votes".
3. Use the real binding names if these keys are rebindable; they are plain keys inside the screen, so probably fixed.
4. Regress impact: grep `test/regress/*congress*.txt` for the resolution and vote lines and update the expectations. `WCText_*` has Lua tests (`test/lua/test_worldcongress*.lua`, if present) to extend.

## M11. Say "upgrade available" when a unit is selected (small feature)

**Asked:** when switching to a unit that can be upgraded, say so clearly.

**Today:** U upgrades and says what happened or why it can't (`HelpText.lua`, `ExtraHotkeysUpgrade`). The Tab menu lists "Upgrade" with its tooltip (`UnitPanel.lua`, around line 491: target unit, gold cost, resource cost). The selection line (`HubAnnounce.OnUnitSelectionChanged`) says nothing about upgrades. It already appends a promotion hint the same way: `HubAnnounce.PromotionHint` gives "Promotion available, Shift+U".

**Proposed:** an `HubAnnounce.UpgradeHint( unit )` next to `PromotionHint`, appended in the same place.
- **Can upgrade now:** "Upgrade to Pikeman available, 120 gold, U". Use `UnitManager.CanStartCommand( unit, UnitCommandTypes.UPGRADE, true, true )`, which gives the target from `results[UnitCommandResults.UNIT_TYPE]`, and `unit:GetUpgradeCost()`. Add the resource cost when it is above 0 (`GetUpgradeResourceCost`).
- **Possible but blocked:** for example not enough gold, outside your territory, or moves already used. The test is: `CanStartCommand( ..., true, false )` true (the command exists for the unit), `( ..., true, true )` false. Then say it shorter, "Upgrade to Pikeman: needs 120 gold, you have 42", or only the target name. One phrase only; U gives the full reason.
- **No upgrade:** silent.
- **Avoid spam:** say it on selection only, not on every turn-start unit cycle. Or say it in full once per unit per turn, then just "upgrade available".
- **Optional:** a J places entry or a turn-start line "3 units can be upgraded", for the moment a new tech makes many units upgradable.
- **Fixtures:** the round-16 and round-19 upgrade plays (pt-modes chain, "Upgraded to Pikeman") have an upgradable unit. Grep `test/regress/*.txt` for unit selection lines that would gain the new suffix.
