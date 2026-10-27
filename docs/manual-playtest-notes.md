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
