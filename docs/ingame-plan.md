# In-game accessibility plan

Goal: a blind player can play a full game with the keyboard and speech. The turn loop is driven by **Enter = Next Action** (the game's own ActionPanel binding): it selects the next unit needing orders, opens the production/research/civic chooser, and ends the turn when nothing blocks. Everything below fills the gaps in that loop. Read `CLAUDE.md` and `docs/keynav-guide.md` first; their rules apply.

## Architecture

- **Hub context `InGameAccess`**: a new UI context added with `AddUserInterfaces` (Context `InGame`), like `UI/Additions/ExpansionIntroAccess.xml`. Files: `ScreenReaderAccess/UI/Additions/InGameAccess.xml` + `.lua`. It owns global hotkeys, the map cursor, modes (list navigation) and event-driven announcements. Prefer it over editing game files.
- **Reusable logic in `Accessibility/`**, e.g. `PlotDescription.lua` (plot text, direction/distance words), `SettleScan.lua`. Import them in `InGameActionData` (and `FrontEndActionData` only if a front-end file includes them).
- **Game file overrides only where the data or callbacks live in that context** (UnitPanel actions, ProductionPanel, ResearchChooser, CivicsChooser, NotificationPanel, TopPanel, ActionPanel). Check `DLC/Expansion1|2/UI/Replacements`: with Gathering Storm active, e.g. `TopPanel.lua` is replaced by the Expansion2 copy, `UnitPanel_Expansion2.lua` includes `UnitPanel_Expansion1` which includes `UnitPanel`. Override the file that actually holds the code you change, and confirm with a print that your copy loads. Pristine-asset commit first.
- **Cross-context calls** go through `LuaEvents.SRA_*` (names prefixed `SRA_`). Pass plain data, never functions.
- **Hotkeys**: new `InputActions` + `InputActionDefaultGestures` rows (see `Database/keynav_queries_configuration.sql`), handled via `Events.InputActionTriggered`, so they are rebindable and show up in `keymap.md`. Modal list navigation (arrows/Enter/Escape inside a menu) is raw key handling in the owning context's input handler, consuming the keys while the mode is active. **Phase 1 must verify** that a consumed Enter/arrow in a mode does not also fire Next Action / camera pan; if input actions fire first, the mode must suppress them (e.g. ignore the action while a mode is active, or intercept in ActionPanel).
- **Speech style**: most important word first, short, no repeats. Event announcements (new turn, notifications, combat) use `nointerrupt = true`; responses to a key interrupt.

## Key map (new keys; avoid the user's bindings in `.claude/skills/civ-test/keymap.md`)

| Key | Does |
|---|---|
| Shift+Arrows | move the map cursor (existing actions `KeyNavMoveCell*`; logic moves from `WorldInput.lua` into the hub) |
| I | detailed description of the cursor plot |
| `.` (period) | cursor to the selected unit/city ("where am I") and speak it |
| N | what's next: speak the current end-turn blocker (what Enter will do) |
| Tab | selected unit: actions menu (Up/Down, Enter runs, Escape closes) |
| X | scan: with a settler, the settle-spot browser (later: other units scan for threats/targets) |
| Control+Y | top panel region (yields, gold, turn, era, current research/civic) |
| Control+N | notifications region |

Region/list conventions: Up/Down (or Left/Right in the top bar) move and wrap, Home/End, Enter activates, Space reads details, Escape leaves back to the map. Announce "i of n" on entering.

## Phases (each: implement, test in game with civctl, commit; then review)

1. **Hub, map cursor, announcements.** Context + project registration; input-order spike (above). Cursor: Shift+Arrows as now, but announce the plot (see below), keep `UI.LookAtPlot` and the mouse move. `PlotDescription`: short form = terrain/feature (hills, woods), resource (+ class: luxury/strategic/bonus), river/coast/lake, improvement/district/wonder, city, owner, units (owner + type + health if damaged), yields, "unexplored"/"fogged". Relative position to the selected unit: "3 tiles north-east". Detailed form (I) adds appeal, movement cost, defense, continent, adjacency, etc. Unit selected: "Warrior, 2 of 2 moves, <short plot>". City selected: name, population, production, growth. Turn flow: "Turn 5, 3600 BC" on turn start; "Turn ended"/"Waiting for other players" on end turn; N key. Replace the old `OnUnitSelectionChanged` in `ScreenReaderEventHandlers.lua` (it is loaded as a gameplay script) so nothing speaks twice.
2. **Unit orders.** Tab actions menu built from UnitPanel's own action table (override UnitPanel, run the action callbacks there; speak name, hotkey, disabled reason). Target modes: when the interface mode is MOVE_TO / RANGE_ATTACK / similar (M, R, or chosen from the menu), Shift+Arrows move the cursor and announce the plot plus "N turns" / attack preview, Enter commits through the game API (`UnitManager.RequestOperation`), Escape cancels. Announce results: unit moved/arrived, combat results, city founded.
3. **Choosers.** Production (city panel/ProductionPanel), Research, Civics choosers: keyboard lists with name, turns, cost, short effect; Enter chooses; announce when they open from Next Action. Also popups that block the turn loop as they show up (boost "Eureka", tech/civic completed is partly done, first contact/diplomacy, natural wonder discovered, era/historic moments).
4. **Regions.** Top panel (Control+Y): one item per yield/resource (gold balance and per turn, science, culture, faith, tourism, favor, strategic resources, turn/date, current research and civic with turns left); Space reads the tooltip breakdown. Notifications (Control+N): list with summary; Enter activates (as a click would), Delete dismisses; new notifications are announced on arrival (nointerrupt).
5. **Settler scanner** (see below).
6. **Play-through.** Play 30+ turns using only `SR>` output; every silent or unreachable step becomes a fix or a filed gap in this doc.

## Settler scanner

Two sources of candidates:
- The game's advisor: `Players[p]:GetGrandStrategicAI():GetSettlementRecommendations(5)` (see `WorldViewIconsManager.lua` `AddSettlementRecommendations`): plot index + reasons `SettleTitle<i>` / `SettleExplanation<i>` / `SettlePositive<i>`.
- Our own scan of land plots within ~6 tiles of the settler that a city can be founded on (not within the minimum distance of another city, not water/mountain, not foreign-owned; mirror the settler lens / found-city validity rules), scored by: fresh water (river/lake) > coast; food+production of the ring-1 and ring-2 plots; luxury and strategic resources within 3; hills; adjacency to mountains/natural wonders; turns to reach; danger (visible barbarians/enemies).

Interaction:
- On settler selection, after the unit announcement (nointerrupt): one sentence about here and the best spot, e.g. "Here: can settle, river. Best: 2 tiles north-east, 1 turn, river, wine and silk. X to browse."
- X opens the browser: candidates sorted by score (advisor picks marked "recommended"), each spoken as "<direction> <distance> tiles, <turns> turns, <top 3 reasons>, i of n". Up/Down browse, Space reads all reasons (advisor text + resources by name), Enter orders the settler to move there (or found the city if it is the current plot), Shift+Enter only moves the cursor there, Escape closes.
- The plot description gains "can settle" / "cannot settle: too close to Rome" when a settler is selected.
- Possible later: earcons (a new console-app prefix that plays a short tone, panned by direction, pitched by quality) for a quick sweep. Speech first.
