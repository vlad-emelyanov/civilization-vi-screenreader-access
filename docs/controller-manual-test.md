# Manual test findings (controller and general)

Findings from the user's manual play, mostly with the Xbox controller (2026-10-27 onwards). Each entry: what was heard, the cause, the proposed fix. Nothing here is implemented yet.

## C1. "X to browse" for a settler (and "X lists other tiles" for a builder) is wrong on the pad

- **Heard:** a settler on a city tile is announced with "... X to browse". Pressing X on the pad selected the city, and pressing it again selected the settler. No browser opened.
- **Cause:** on the bare map the keyboard X key opens the settle / improvement browser (`HubSettle.ScanKey`), but the pad's X button is "select at cursor", the K key (`HubGamepad.lua`, `MAP_ACTIONS.X = HubCursor.SelectAtCursor`, as designed in `docs/controller-plan.md`). The pad X opens the browser only in a target mode. The spoken-hints round wrapped these hints as `SRKey( "X", "X" )`, which tells the pad player to press X.
- **Affected hints:** `SettleScan.lua:682` and `:687` ("X to browse"), `HubSettle.lua:367` ("X lists other tiles"), `HubMenus.lua` "Opens the same browser as the X key" (`SRKey( "X key", "X button" )`). Check every other `SRKey( "X", "X" )` and `"X button"` for the same context mismatch (the target-mode "or X" hints in `HubTargets.lua` are right).
- **How a pad player reaches the browser today:** D-pad right (the unit actions menu, Tab), whose first entry is "Browse settle spots" / "Browse tiles to improve" / "Browse tiles to act on".
- **Fix options:**
  1. Hint only: the pad wording names the menu, e.g. `SRKey( "X", "D-pad right, first entry," )` so it reads "D-pad right, first entry, to browse". Smallest change; awkward wording.
  2. Behaviour (recommended): pad X on the bare map opens the browser when the selected unit has one (`HubSettle.BrowserFor( unit ) ~= nil`), else selects at cursor. Then the hint stays "X". Selecting what is on the cursor tile is still available with A on a tile (check what Enter does on the bare map first) or by pressing X with no browser unit selected. Needs a `docs/controller-plan.md` table update and a `HelpText.lua` Controller entry change.
- **Lesson for the hints round:** a button argument must be checked against the context where the hint is spoken (map vs list vs target mode), not just the keyboard key's meaning.

## C2. Opening the unit actions list (Tab) on the pad

- **Question:** how to reach the list of unit actions that Tab opens on the keyboard.
- **Answer, not a bug:** D-pad right. The console app sends Tab for it, so the hub opens the same unit actions menu. D-pad left is Control+Tab (the area overview).
- **Possible improvement:** the selection announcement could say it, as the keyboard one says "Tab for its actions" (converted, so the pad hears "D-pad right"). If the user did not hear such a hint for this unit, check which announcements carry it.

## C3. World Congress hints stay in keyboard words on the pad

- **Heard (Lua.log, raw text):** "equals adds a vote, Left and Right switch option, 1 of 3. H for keys", "target needed, T to choose", "equals adds a vote for 4 favor", and in the intro "Enter to begin voting". None of these carry a `[KEY:..]` token. The wrapped ones work as raw tokens ("[KEY:Enter] on Submit votes sends them", "[KEY:Enter] or [KEY:Control+N|RB] resumes it").
- **Cause:** the hints-round file split missed some files, and the agents' grep was case-sensitive:
  - `Accessibility/WorldCongressText.lua` was in no agent's list. Its lines 135-161 build "equals adds a vote ...", "minus removes one", "equals votes for, minus votes against" and "Left and Right switch option". `NextStep` takes the key names as arguments ("equals", "minus").
  - `UI/Replacements/WorldCongressIntro_SRA.lua:52`: "Enter to begin voting".
  - `UI/Replacements/WorldCongressPopup_SRA.lua:2987`: "T to choose". On the pad, A (Enter) opens the target list too (the help line says "T or Enter chooses the target"), so the pad wording is "A to choose".
  - `WorldCongressPopup_SRA.lua:3259`: "H for keys". The pad has no H; see C4.
- **Fix:** wrap these with `SRKey( "equals", "X" )`, `SRKey( "minus", "LT" )`, `SRKey( "Left and Right" )`, `SRKey( "Enter" )`, `SRKey( "T", "A" )`. For `NextStep`, pass tokens instead of bare words. Keyboard wording stays byte-identical, so no regress change.
- **Other hints of the same kind found by a case-insensitive sweep:** `HubSettle.lua:65,67` "B to found next turn / the city here". The pad has no Found City button; the action is in the D-pad right menu. Either the pad wording names it (`SRKey( "B", "D-pad right, Found City," )`) or C1's behaviour fix pattern applies. The rest of the sweep found no other missed spoken hints (DealSpeech, DiplomacyText, Trade/Religion/Climate/Report text helpers only say "minus" as a number sign).

## C4. Screen key help ("H for keys") has no pad button

- **Cause:** screens with their own key help (World Congress H, also the lobby's H for chat history, which is a different action) read it on a letter key. With a popup open, the hub passes every pad button except LB/RB on to the screen (`HubGamepad.HandleInput`, `IsGamePopupOpen` branch), so the View button (F18) reaches the World Congress screen, which ignores it.
- **Fix:** in screens that have a key-help key, make View (F18, `Gamepad.ButtonOf( key, ctrl ) == "View"`) an alias for it, the same way X / LT / RT are aliased. Then the hint becomes `SRKey( "H", "View" )`, read as "View button for keys". `grep -n '"H for\|H for keys\|H reads' ` to find all of them. Add the alias to the screen's `HelpText.lua` keys entry.

## C5. Y (details) is not advertised

- **Request:** where Y gives more detail, say so.
- **Where Y (Space) works:**
  - every `KeyNavList` list whose items have a `detail` (`KeyNavList.lua:188-191, 225`; "No further details" when an item has none). That covers the hub lists (notifications, places, top panel, city report, unit menu, J lists) and most of the mod's screens (congress, deal, religion, government, trees, city-states, trade, espionage, great works, rankings, reports);
  - the bare map: Y reads the tile, or opens the city report on an own city (`HubGamepad.OnPadDetails`);
  - the unit menu: Y on the browser entry says what it opens.
- **Today:** only a few screen help lines mention Space (e.g. the congress H help: "Space reads the whole resolution"). Item announcements never say it, for either device.
- **Proposed design:**
  1. A pad-only hint, so keyboard speech and the regress scripts do not change: a second token, `SRPadHint( text )` -> `[PAD:text]`, spoken by the console app only when the pad is the current device and dropped otherwise (`KeyHints.Expand`; civctl drops it too).
  2. `KeyNavList`, when a list opens (its first announcement), appends `SRPadHint( ", Y for details" )` if the focused item has a detail. Only once per list open, not on every item, to keep it short. A screen can opt out with a list option.
  3. On the bare map, the hub's selection announcement for an own city could append "Y for its report" (pad only). Plot details stay unadvertised; they are in the Controller help section.
  - Alternative: also say "Space for details" to keyboard players, with the same once-per-open rule (`SRKey( "Space" )`). That changes the opening line of many regress expects; decide before implementing.

## C6. Places list in Move To offers places a ship can never reach

- **Heard:** in Move To with a ship, the places list (LB / RB in a target mode, J on the keyboard) lists landlocked cities and other inland places. Not controller-specific: the keyboard J list behaves the same.
- **Cause:** in a target mode the places list is the ordinary places list (`HubPlaces.lua`, `m_facade.Open`, items from `m_data.cats`). Nothing filters by the selected unit. Reachability is only handled at Enter: `ActivateItem` -> `MoveTargetNear` looks for the nearest reachable tile 1-2 tiles from the place (path finding with a budget of `MAX_PATH_CALLS`); for an inland city no such water tile exists, so the target lands on the city itself and the move order then fails.
- **Proposed fix (needs a short engine probe first):**
  1. When the places list opens in the Move To mode with a naval unit (`GameInfo.Units[ unit:GetUnitType() ].Domain == "DOMAIN_SEA"`), drop items that have no water tile of the ship's own water body within 2 tiles (the same radius `MoveTargetNear` uses), or that are not water themselves. "Own water body": compare the plot's area with the ship's (`Plot:GetArea()` and an area id; this is the call to probe, it is not used anywhere in the mod yet). That also drops lakes and inland seas the ship cannot sail to. If the area call does not exist, fall back to `plot:IsWater()` / `plot:IsCoastalLand()` plus `not plot:IsLake()` for the ship's sea.
  2. Keep unexplored items (path finding would leak what is hidden; the mod already lists them by distance for that reason).
  3. Optional second pass: path finding nearest-first within the existing budget, dropping places whose best tile has no path (closed borders block ships too). Places beyond the budget stay listed.
  4. The category head says how many were left out, e.g. "Cities, 4. 3 inland cities left out", so the player knows the list is filtered.
  5. Land units: no filter (they embark). Air units are out of scope (their own range / rebase lists).
- **Tests:** a pure filter function in `HubPlaces` with a luatest on the stub map (`stub("world")` with water / land / lake tiles); a regress script on a fixture with a ship and an inland city (check `test/fixtures/*.txt` facts for a coastal city with a naval unit).

## C7. City power (Gathering Storm) is not spoken anywhere

- **Heard:** with power plants built, the city report (`Accessibility/CityReportData.lua`, `CityReport_BuildItems`: population, amenities, loyalty, religion ...) says nothing about power. Not controller-specific.
- **What the mod has today:** only the power lens legend ("Shows power: ...", `LensText.lua:159`) and the power resources' per-turn consumption in the top panel resources (`TopPanelData.lua:86-103`). No per-city power status, no tile-level "powered / in range of a plant".
- **What the game shows sighted players:** the city panel's Power tab (`DLC/Expansion2/UI/Additions/CityPanelPower.lua`, `OnRefresh`): `pCity:GetPower()` gives `GetFreePower()`, `GetTemporaryPower()`, `GetRequiredPower()`, `IsFullyPowered()`, `IsFullyPoweredByActiveProject()`, the breakdowns `GetFreePowerSources()` / `GetTemporaryPowerSources()` / `GetRequiredPowerSources()` / `GetGeneratedPowerSources()` (lists of `{ [sourceName] = value }`), and `pCity:GetPowerAdvice()`. Status names: `LOC_POWER_STATUS_POWERED_NAME` / `_UNPOWERED_NAME` / `_NO_POWER_NEEDED_NAME` with `_DESCRIPTION` texts (the description says what underpowered buildings lose).
- **Proposed fix:** a "Power" entry in the city report right after Loyalty, copying `OnRefresh`'s logic (current = free + temporary, or required when fully powered by an active project):
  - text: "Power 4 of 6 needed, underpowered" / "Power 6 of 6, powered" / no entry when required power is 0 and the city generates none (or "Power: none needed" only if the city generates power for others);
  - detail (Y / Space): the status description, then "From:" the consumed sources, "Needed by:" the required sources, "Generates:" the generated sources (the power plants), then the advice text.
  - Gather it in `CityReportGather.lua` (Gathering Storm only: guard `pCity.GetPower ~= nil`), pure text building in `CityReportData.lua` with a luatest; a regress script on a modern fixture with a power plant (check fixture facts; build one with a scenario if none has it).
  - Optional follow-up: the map tile description of a city or district could say "underpowered" when the city is not fully powered, and the power lens could read per tile "in range of <plant>".

## C8. Word order in list items: the part that differs should come first (audit needed)

- **Heard:** in the spy's counterspy mission list every item starts with "Counterspy", then the district ("Counterspy, Campus, 8 turns, 1 of 5"). The player already knows it is the counterspy list, so the district should lead, and "Counterspy" can go.
- **Cause (this example):** `Choosers/EspionageChooser.lua` `SRA_MissionItems` builds every item with `EspionageText_Mission{ name, district, ... }` (`Accessibility/EspionageText.lua:91`), which always puts the operation name first. For the offensive list that is right (the operation differs per item); for the counterspy list (`entry.counter`) the name is the same on every item.
- **Fix for this example:** for counterspy entries, leave the operation name out of the item text and say it once in the list's opening line ("Counterspy missions in Rome. Campus, 8 turns, 1 of 5"). The detail (Y / Space) keeps the game's sentence "Protect Campus (and all adjacent districts) from enemy spies".
- **Rule to adopt (add to `docs/keynav-guide.md`):** an item starts with what tells it apart from its neighbours. Words that every item of the list shares, or that the list title already said, are dropped or moved to the opening line. Status and numbers follow; position ("n of m") stays last.
- **Other cases already visible in today's `Lua.log`** (found with a quick script: three or more consecutive "n of m" items with the same first phrase):
  - **builder tile browser / improvement list:** "Plains, Rainforest, Lumber Mill plus 2 production, 2 tiles south, 2 turns, worked, 1 of 5", then "Plains, Woods, ...", "Plains, Rainforest, ...". The terrain leads, the direction comes late. Probably better: "2 tiles south, Lumber Mill plus 2 production, Plains Rainforest, 2 turns, worked". Same for "Snow, Ice Hockey Rink, ..." and "Crabs, Fishing Boats plus 1 food, ...".
  - **World Congress option switch (Left / Right):** "Sovereignty, option A: ..." then "Sovereignty, option B: ..." on the same resolution. On a switch only "Option B: ..." is new; the resolution name should be said only when moving to another resolution.
  - **places / resources lists:** "Coast, Pearls (luxury), Fishing Boats, ..." The terrain leads although the resource is what the list is about.
- **Audit plan (offline, cheap):**
  1. A script (`util/speechaudit.py`) over the regress recordings (`test/regress/*.recorded.txt`, or a `Lua.log` after `regress all`): group consecutive list items ("..., n of m") into runs per list, then flag (a) runs where most items share the same first phrase, (b) items whose first phrase repeats the list title just spoken, (c) items longer than ~20 words whose distinguishing part (the phrase that differs between neighbours) comes after the 5th word. Output: one line per list with the first three items as examples.
  2. The lead triages the output into rules per list (what leads, what moves to the title, what moves to the detail).
  3. One fix agent per area (hub lists, espionage, congress, trade, religion, ...), each updating the item builders and the regress expects those lists appear in (wording changes are intended, so the expects change).
  4. A luatest per changed builder.
