-- ===========================================================================
--	HelpText: the text of the accessibility help list (Control+H, action KeyNavHelp, shown by HubHelp.lua).
--	THE ONE PLACE where shortcut descriptions live. RULE: every new or changed shortcut (an input action in Database/*.sql,
--	or a key inside one of our lists and screens) needs an entry here. test/py/test_helptext.py fails when a KeyNav* input
--	action has no `action = "..."` entry below.
--
--	Sections: { title, entries = { entry ... } }. Entry kinds:
--		{ action = "KeyNavWhatsNext", default = "N", text = "what Enter will do next" }
--			an input action: the key shown is the CURRENT binding (Input.GetGestureDisplayString, so a rebinding on the
--			game's Key Bindings page shows up); `default` is the text used when the action is unknown or unbound.
--		{ keys = "Shift+Arrows", text = "move the map cursor" }
--			a key inside our own lists and screens (not rebindable): static.
--	Spoken as "<key>: <text>". Write text lowercase, short, one line.
--
--	HelpText_Sections()                      -> the sections above (a table you must not change)
--	HelpText_KeyText( entry, lookup )        -> "Control+I" (lookup( actionName ) -> display string or nil/"" when unbound)
--	HelpText_Line( entry, lookup )           -> "Control+I: city report: yields ..."
--	HelpText_Build( lookup )                 -> { { title, items = { { key = "h:2:5", text = line } ... } } ... }: what HubHelp lists
-- ===========================================================================

local m_sections:table = {
	{ title = "General list conventions", entries = {
		{ keys = "Up and Down",			text = "previous and next entry, wraps around" },
		{ keys = "Home and End",		text = "first and last entry (controller: the D-pad moves one entry, see the Controller section)" },
		{ keys = "Page Up and Page Down",	text = "jump to the first entry of the previous and next group, where the list has groups (production: districts, buildings, wonders, units, projects; places: your units by type); a list without groups says so. Controller: hold LB or RB and press up or down on the left stick or D-pad" },
		{ keys = "Enter",				text = "choose or open the entry" },
		{ keys = "Space",				text = "read more about the entry" },
		{ keys = "Escape",				text = "close the list or go back one step" },
		{ keys = "Tab and Control+Tab",	text = "next and previous section, tab or category (Shift+Tab is the Steam overlay; controller: RB and LB)" },
		{ keys = "Left and Right",		text = "change a value, or switch tabs, where the list says so" },
		{ keys = "Delete or Backspace",	text = "remove or go back, where the list says so" },
		{ keys = "A to Z",				text = "in this help: jump to the next section whose title starts with the letter" },
	} },
	{ title = "Map and turn", entries = {
		{ action = "EndTurn",					default = "Enter",		text = "next action: select the next unit, open a chooser, or end the turn" },
		{ action = "KeyNavWhatsNext",			default = "N",			text = "what Enter will do next" },
		{ action = "KeyNavMoveCellLeft",		default = "Shift+Left",	text = "move the map cursor west and read the tile" },
		{ action = "KeyNavMoveCellRight",		default = "Shift+Right",text = "move the map cursor east and read the tile" },
		{ action = "KeyNavMoveCellUp",			default = "Shift+Up",	text = "move the map cursor north and read the tile" },
		{ action = "KeyNavMoveCellDown",		default = "Shift+Down",	text = "move the map cursor south and read the tile" },
		{ action = "KeyNavJumpCellLeft",		default = "Control+Shift+Left",	text = "jump the map cursor 5 tiles west and read the tile (also in target modes)" },
		{ action = "KeyNavJumpCellRight",		default = "Control+Shift+Right",	text = "jump the map cursor 5 tiles east and read the tile (also in target modes)" },
		{ action = "KeyNavJumpCellUp",		default = "Control+Shift+Up",	text = "jump the map cursor 5 tiles north and read the tile (also in target modes)" },
		{ action = "KeyNavJumpCellDown",		default = "Control+Shift+Down",	text = "jump the map cursor 5 tiles south and read the tile (also in target modes)" },
		{ action = "KeyNavPlotDetails",			default = "I",			text = "detailed description of the cursor tile" },
		{ action = "KeyNavCursorToSelection",	default = ".",			text = "cursor back to the selected unit or city and read it" },
		{ keys = "Cursor on a resource",	text = "the tile text adds what the resource needs: \"Horses, needs Animal Husbandry\" or \"Wine, plantation possible\"; I adds the research turns" },
		{ action = "KeyNavSelectAtCursor",		default = "K",			text = "select your unit or city on the cursor tile, again: the next one there" },
		{ action = "KeyNavCycleAllUnits",		default = "Control+K",	text = "select the next of all your units, also fortified and automated ones" },
		{ action = "NextUnit",					default = "]",			text = "next ready unit" },
		{ action = "PrevUnit",					default = "[",			text = "previous ready unit" },
		{ action = "KeyNavScanUnits",			default = "X",			text = "cursor to the nearest foreign unit in view, hostile first, again: the next; in an attack mode only what you can attack" },
		{ action = "KeyNavYields",				default = "Control+G",	text = "gold, science, culture and faith in one sentence" },
		{ action = "KeyNavTopPanel",			default = "Control+Y",	text = "top panel list: yields, resources, research, civic, turn, era" },
		{ action = "KeyNavNotifications",		default = "Control+N",	text = "notifications: Enter activates, Delete (controller: X) dismisses, M sends a unit to its place" },
		{ action = "KeyNavEraProgress",			default = "Control+E",	text = "era progress: era score, thresholds, other civilizations" },
		{ action = "KeyNavHelp",				default = "Control+H",	text = "this help list" },
		{ action = "OpenMapSearch",			default = "Control+F",	text = "map search: type words such as Iron, Hills or Unclaimed, Enter searches, Down and Up step through the matches (the cursor goes there), Escape closes, the cursor stays on the match" },
		{ action = "QuickSave",					default = "F5",			text = "quick save" },
		{ action = "QuickLoad",					default = "F6",			text = "quick load" },
		{ action = "LensReligion", default = "1", text = "Religion lens, the cursor then also reads followers of your cities" },
		{ action = "LensContinent", default = "2", text = "Continent lens, the cursor then also reads the continent" },
		{ action = "LensAppeal", default = "3", text = "Appeal lens, the cursor then also reads the appeal" },
		{ action = "LensSettler", default = "4", text = "Settler lens, the cursor then also reads water access for a city" },
		{ action = "LensGovernment", default = "5", text = "Government lens, the cursor then also reads the governor or government effect" },
		{ action = "LensPolitical", default = "6", text = "Political lens, the cursor then also reads the usual tile text, only the colours change" },
		{ action = "LensTourism", default = "7", text = "Tourism lens, the cursor then also reads the usual tile text, only the colours change" },
		{ action = "LensLoyalty", default = "8", text = "Loyalty lens, the cursor then also reads the loyalty of your cities" },
		{ action = "LensEmpire", default = "9", text = "Empire lens, the cursor then also reads the usual tile text, only the colours change" },
		{ action = "LensPower", default = "0", text = "Power lens, the cursor then also reads the usual tile text, only the colours change" },
		{ keys = "Escape",				text = "with nothing open: the in-game menu" },
		{ keys = "Turn start",			text = "after the turn line: what visible enemies near your cities and units did, moved toward or away, new, wounded, out of sight" },
	} },
	{ title = "Units", entries = {
		{ action = "KeyNavUnitActions",			default = "Tab",		text = "menu of everything the selected unit can do: Enter runs, Space reads the tooltip. Actions that destroy something (Remove Improvement, Harvest, Pillage) come after the normal ones, and a great general's Retire comes last; they ask first: Enter again on the same item within 5 seconds to confirm (their own hotkeys act at once)" },
		{ action = "MoveTo",					default = "M",			text = "move to: choose a tile" },
		{ action = "Attack",					default = "W",			text = "attack: jumps to the nearest enemy and previews it" },
		{ action = "RangedAttack",				default = "R",			text = "ranged attack, also for a city" },
		{ action = "SkipTurn",					default = "Space",		text = "skip the unit's turn" },
		{ action = "Fortify",					default = "D",			text = "fortify" },
		{ action = "FortifyUntilHeal",			default = "S",			text = "fortify until healed" },
		{ action = "Sleep",						default = "Z",			text = "sleep" },
		{ action = "Alert",						default = "A",			text = "alert (sentry)" },
		{ action = "AutoExplore",				default = "E",			text = "automate exploration" },
		{ action = "ExtraHotkeysUnitWake",		default = "Shift+W",	text = "wake up" },
		{ action = "ExtraHotkeysUnitCancel",	default = "Shift+C",	text = "cancel the unit's orders" },
		{ action = "ExtraHotkeysPromote",		default = "Shift+U",	text = "promotion list" },
		{ action = "ExtraHotkeysFormCorps",		default = "Shift+F",	text = "form a corps" },
		{ action = "ExtraHotkeysFormArmy",		default = "Control+Shift+F", text = "form an army" },
		{ action = "ExtraHotkeysUpgrade",		default = "U",			text = "upgrade the unit, or activate a great person (a Great Prophet founds its religion); says what happened, or why it cannot. Selecting a unit that can upgrade says \"Upgrade to <unit> available, <gold> gold, U\" (or why it is blocked), once per unit per turn" },
		{ action = "ExtraHotkeysEnterFormation",default = "Shift+E",	text = "create or leave an escort formation (on an escorted unit it ends the escort: \"Escort ended: <unit> is on its own again\"; says \"Escort formed: <unit> with <unit>\", the unit you pressed it on first, or why it could not); selecting a settler or builder says when a soldier of yours shares its tile or already escorts it" },
		{ keys = "Warnings",			text = "a settler or builder sent off alone near enemies or a barbarian camp is told so, with the key for an escort; a barbarian scout near your city sounds an alarm, a raid of two or more soldiers near a city is spoken once, again only when its members change or one comes within 2 tiles, else a short reminder every 3 turns; an unescorted builder in danger is spoken once and again when it changes (civilians inside your cities are never warned about, and ships are ignored for civilians on land); Enter with a settler or builder exposed to an enemy soldier within 3 tiles warns first and a second Enter within 10 seconds ends the turn anyway; automatic exploration says Caution with an enemy within 3 tiles; J lists under Threats every enemy soldier within 3 tiles of a city; N adds Raid expected after a scout escaped" },
		{ action = "ExtraHotkeysPillageOrRepair",default = "Shift+P",	text = "pillage, coastal raid or repair" },
		{ action = "DeleteUnit",				default = "Delete",		text = "delete the unit, asks first" },
		{ keys = "Shift+Arrows",		text = "in a target mode (move, attack ...): move the target, the tile is described" },
		{ keys = "X",					text = "in a target mode: target the nearest foreign unit" },
		{ keys = "J",					text = "in a target mode: places list, Enter only moves the target there" },
		{ keys = "Enter",				text = "in a target mode: confirm the move or attack" },
		{ keys = "Space",				text = "in an attack target mode: modifiers of both sides for the target tile (flanking, terrain, wounds ...)" },
		{ keys = "Escape",				text = "in a target mode: cancel" },
	} },
	{ title = "Settler and builder", entries = {
		{ keys = "X",					text = "with a settler: browse the best places to found a city, each with its distance to your nearest city and to a rival city within 10 tiles; Space adds Between you and a rival or Behind your city, hills and mountain or water sides. Selecting the settler says Here is good when no spot nearby is clearly better, or Best spot is clearly better when that spot is within 4 turns; a farther one is said as Best: ..., far away, with barbarians near it when hostile soldiers are close to it" },
		{ keys = "X",					text = "with a builder: browse the tiles it can improve; after them a Later group lists resource tiles that need a tech or civic first, Enter says what is missing; a tile with a hostile soldier within 2 tiles says \"danger: <unit> <distance> away\" and the first Enter on it only warns (Enter again sends the builder); Enter on another tile sends the builder and remembers the improvement named first: on arrival it says \"Enter builds <improvement>\" and Enter builds it (with no moves left: select the builder next turn and press Enter); any other key or order cancels it" },
		{ keys = "X",					text = "with a great person, archaeologist, naturalist or rock band: the tiles it can act on (a great person that needs a district: your completed districts of that kind), nearest first with turns to reach; Enter goes there, on arrival it says \"Enter activates <name>\" and Enter activates (on the tile it stands on, Enter activates at once); a tile with a hostile soldier near warns first" },
		{ keys = "Tab",					text = "the browsers (settle spots, tiles to improve, tiles to act on) are also the first entries of the unit actions menu (Tab, controller D-pad right); Space on the entry says it opens the same browser as the X key" },
		{ keys = "Up and Down",			text = "in the browser: next and previous place or tile" },
		{ keys = "Left and Right",		text = "builder browser: next and previous city" },
		{ keys = "Space",				text = "in the browser: all reasons for the place" },
		{ keys = "Enter",				text = "in the browser: go there, or found the city or open the actions menu on the tile" },
		{ action = "FoundCity",			default = "B",			text = "found a city with the settler" },
		{ keys = "Escape",				text = "close the browser, the cursor goes back to the unit" },
	} },
	{ title = "Places list", entries = {
		{ action = "KeyNavPlaces",		default = "J",			text = "places list: threats first (a barbarian scout that has seen your city, raiders, enemies next to your settler or builder), cities, units, points of interest (barbarian camps say what guards them; Space says what destroying one gives), blind spots (land near your cities out of sight or unexplored, where barbarian camps can appear; unexplored areas may include sea and mountains), notification places, foreign cities, enemy civilians you can capture" },
		{ action = "KeyNavAreaOverview",	default = "Shift+J",	text = "area overview of the map cursor: a list with the area (terrain, coast, river, luxury and strategic resources within 3 tiles; your city's area when the cursor is in your territory), the continent (tiles known, how far it reaches, cities on it, unexplored edges) and one item per direction (terrain, borders, ocean, first city, how much is unexplored); only explored tiles count; Space repeats, Escape closes" },
		{ action = "KeyNavSendHere",		default = "Shift+M",	text = "send a unit to the cursor tile (any tile, also unexplored): list of your units that can get there with the turns they need, fastest first; Enter sends the chosen one; Escape closes" },
		{ keys = "Tab and Control+Tab",	text = "next and previous category (controller: RB and LB; past the last or first category they move on to the next or previous list of the ring)" },
		{ keys = "Page Up and Page Down",	text = "in Your units: the previous and next unit type (Builder, Warrior ...), spoken with how many there are; controller: hold LB or RB and press up or down" },
		{ keys = "Space",				text = "read the tile and where it is" },
		{ keys = "Enter",				text = "cursor there, a unit of yours is selected" },
		{ keys = "M",					text = "send one of your units there, fastest first (on a threat: soldiers only; on a barbarian camp the first entry sends an attack party, the two fastest military units; a unit that escorts a Builder or Settler never joins the party and is named as skipped, in the plain list it says \"escorting <civilian>\" because sending it drags the civilian along); for a civilian to capture only military land units are offered, moving onto it captures it. On a Settler or Builder in Your units it sends an escort instead: soldiers that can reach it, fastest first; Enter moves one onto its tile, then Shift+E forms the escort" },
		{ keys = "Control+N then M",	text = "send a unit to the place of a notification" },
		{ keys = "X",					text = "controller: the same as M, send one of your units there" },
		{ keys = "T",					text = "on a barbarian clan camp in view (Barbarian Clans mode): treat with the clan, opens hire, incite, bribe or ransom; also on the map with the cursor on the camp, instead of the tech tree" },
		{ keys = "Escape",				text = "close the list" },
	} },
	{ title = "Cities", entries = {
		{ action = "CapitalCity",		default = "\\",			text = "select the capital" },
		{ keys = "Backslash",			text = "in a target mode (move to, rebase ...): move the target to the capital and say what it is, Enter confirms" },
		{ action = "NextCity",			default = "Shift+0",	text = "next city" },
		{ action = "PrevCity",			default = "Shift+9",	text = "previous city" },
		{ keys = "Tab",					text = "with a city selected: production panel" },
		{ keys = "Tab",					text = "in the city report: production panel of that city (the unit actions menu opens only from the map)" },
		{ keys = "Tab and Control+Tab",	text = "in the production panel: production, queue, purchase with gold, purchase with faith; the item you were on stays focused. The panel opens on the production in progress, and Enter on another item says what it replaces" },
		{ keys = "Enter",				text = "in the production panel: produce or buy; districts and wonders start the placement mode" },
		{ action = "KeyNavCityReport",	default = "Control+I",	text = "city report: yields, growth, amenities, loyalty, defense, districts, citizens, religion" },
		{ keys = "Space",				text = "in the city report: the breakdown of the entry" },
		{ keys = "District spots entry",	text = "city report: which districts the city can build and the best adjacency spot for each, or the nearest unmet requirement when none can be built now (Enter repeats it with the best spot of every district, Tab opens production)" },
		{ keys = "Space",				text = "in the production panel on a district: the description, then Best spot with the adjacency bonus, direction and tile cost" },
		{ keys = "Resources entry",		text = "city report: the resources on the city's tiles, improved or not, and which tech or civic the missing improvements need" },
		{ keys = "Enter",				text = "city report: change yield focus, manage tiles, specialists, buy a tile" },
		{ keys = "Backspace or Delete",	text = "city report, specialists: remove one (controller: X)" },
		{ keys = "Escape",				text = "city report: back, then close" },
	} },
	{ title = "Placement mode", entries = {
		{ keys = "Up and Down",			text = "next and previous tile for the district or wonder" },
		{ keys = "Shift+Arrows",		text = "move the cursor freely, valid or not is spoken" },
		{ keys = "I",					text = "details of the tile" },
		{ keys = "Space",				text = "adjacency explanation, what is removed" },
		{ keys = "Enter",				text = "twice: first asks, second places; on a purchasable tile it buys it first" },
		{ keys = "Escape",				text = "go back one step, then cancel the placement" },
	} },
	{ title = "Screens", entries = {
		{ action = "ToggleTechTree",	default = "T",			text = "tech tree: Left and Right eras, Up and Down nodes, Enter sets the target (on a node you cannot research yet it says how many nodes and turns lie on the way, what comes next and which current research it replaces; a blocked node's own turns are for that tech alone), Shift+Enter queues" },
		{ action = "ToggleCivicsTree",	default = "C",			text = "civics tree: the same keys as the tech tree" },
		{ keys = "J, Q and F",			text = "in the trees: J current research and the target at the end of the queue (controller: left trigger), Q the queue (controller: right trigger), F search by name; Shift+Enter queues the node (controller: X, also in the R list)" },
		{ keys = "R",					text = "in the trees: lists the techs (civics) that unlock the improvement of resources near your cities, cheapest first; Up and Down, Enter sets the target, Shift+Enter or controller X queues, Escape leaves. A node that does so also says \"improves 2 Horses and 1 Sheep near your cities\"" },
		{ action = "ToggleGovernment",	default = "F7",			text = "government: Tab switches policies, governments, my government; Enter on a policy slot opens the policies that fit, Delete (controller: X) empties the slot" },
		{ keys = "Escape in government",	text = "with an empty policy slot the changes are not confirmed: the first Escape warns, Escape again closes and discards them" },
		{ action = "ToggleCityStates",	default = "F2",			text = "city-states: Space bonuses and quests, Enter actions" },
		{ keys = "Enter, Left and C",		text = "city-states envoy mode: Enter or Right or plus adds an envoy, Left or minus or Backspace removes one, C confirms (controller: X), A actions (controller: left trigger)" },
		{ keys = "Escape in city-states envoy mode",	text = "with pending envoys the first Escape warns, Escape again discards them and closes; C confirms them" },
		{ action = "ToggleReligion",	default = "L",			text = "religion screen, also to found a religion and choose beliefs; Tab next tab, C confirms or continues (controller: X), F filters the list (controller: left trigger)" },
		{ action = "ToggleGreatPeople",	default = "O",			text = "great people: Enter opens recruit, pass, patronize; Tab previously recruited" },
		{ action = "KeyNavGreatWorks",	default = "Control+W",	text = "great works: Enter picks up and places, V describes the work (controller: X), Tab next building" },
		{ action = "ToggleTradeRoutes",	default = "F4",			text = "trade routes: Tab switches tabs, B switches whose benefits (controller: X), Enter selects a trader" },
		{ action = "ToggleEspionage",	default = "F3",			text = "espionage: operatives, city activity, mission history; Enter gives a spy orders" },
		{ action = "ToggleRankings",	default = "F1",			text = "world rankings: Tab switches victory types, H explains the victory (controller: X)" },
		{ action = "KeyNavReports",		default = "F8",			text = "reports: yields, resources, city status, gossip; Tab switches tabs" },
		{ action = "ToggleGovernors",	default = "F10",		text = "governors: Enter opens appoint, assign and promote" },
		{ action = "ToggleTimeline",	default = "F11",		text = "historic moments timeline" },
		{ action = "ToggleWorldClimate",default = "Page Down",	text = "world climate (Gathering Storm): Tab switches overview, CO2, history" },
		{ action = "OpenCivilopedia",	default = "F9",			text = "civilopedia: Tab sections, Enter opens a page or link, Backspace back (controller: left trigger), F search" },
		{ keys = "Delete in options",		text = "options, key bindings: Delete (controller: X) clears the selected binding" },
		{ action = "KeyNavDiplomacy",	default = "V",			text = "diplomacy: the civilizations met first, you last (Up from the first civilization wraps to you), each with score, military, science, culture, gold and faith; Enter opens the diplomacy screen with that leader" },
		{ action = "KeyNavStanding",	default = "Control+R",	text = "where you stand among the civilizations you have met: rank in score, military, science, culture, gold and faith, and your weakest category" },
		{ keys = "Tab and Control+Tab",	text = "deal screen: Deal, your items, their items, actions; S reads the summary (controller: X)" },
		{ keys = "Left and Right",		text = "deal screen: change a gold or resource amount by 1, with Shift by 10" },
		{ keys = "Delete",				text = "deal screen, your items: remove the focused item from the deal (controller: LT)" },
		{ keys = "Left and Right",		text = "world congress: choose option A or B; equals or Shift+Up adds a vote (controller: X), minus removes (controller: LT)" },
		{ keys = "T, N and H",			text = "world congress: T chooses the target of a resolution, N goes forward (controller: RT), H reads the help (controller: View)" },
	} },
	{ title = "Controller", entries = {
		{ keys = "A",					text = "activate or confirm; on the map Next Action; in a target mode confirm the tile" },
		{ keys = "B",					text = "back or close; closes the open list; in a target mode cancel; on the map it does nothing (Menu opens the game menu)" },
		{ keys = "Y",					text = "details: reads the item in a list; on the map your own city under the cursor opens its city report, else the details of the tile; in an attack mode the combat modifiers" },
		{ keys = "X",					text = "the list's second action: dismiss in notifications, send a unit in places; on the map: with the cursor on the selected unit and that unit has a browser (settler, builder, great person ...) it opens that browser, otherwise it selects your unit or city on the cursor tile, again the next one there; in a target mode target the nearest foreign unit (like the X key); in screens: the screen's main extra key, see each screen" },
		{ keys = "Left stick",			text = "move in lists, Left and Right change values; on the map move the cursor one tile; in a target mode move the target cursor" },
		{ keys = "D-pad up and down",	text = "in a list or screen: previous and next entry, like the left stick, and it repeats while held; on the map what is next and cursor to selection" },
		{ keys = "D-pad right and left",text = "in a list or screen: the same as Right and Left on the left stick (nothing where the list does not use them); on the map the unit actions menu or city production, and the area overview" },
		{ keys = "RB and LB",			text = "in a list or screen with tabs or sections: next and previous section or tab (production tabs, places categories, help sections, deal sections ...); a list without tabs says so. On the map RB opens the first list of the ring and LB the last. The ring: Notifications, Top panel, Lenses, Diplomacy, Screens, Places. In a ring list without sections RB opens the next one and LB the previous one; in Places they move through the categories first and go on to the next or previous list past the last or first category; in a target mode they open the places list (like J, Enter there only moves the target)" },
		{ keys = "Hold LB or RB, then up or down",	text = "in a list: jump to the previous or next group (the left stick or the D-pad, repeating while held), like Page Up and Page Down; the bumper does nothing else when used this way" },
		{ keys = "Left trigger",		text = "on the map: attack with the selected unit or city" },
		{ keys = "Hold the left trigger, then point the left stick",	text = "the wheel, in the Top panel, Lenses, Diplomacy and Screens lists (other lists say they have none): the entries sit around the stick like a clock face, the first one straight up, going clockwise; pointing the stick jumps to the entry in that direction and reads it (4 entries: up, right, down, left). Release the trigger and A chooses it, or move on with the stick" },
		{ keys = "Right trigger",		text = "on the map: move the selected unit to a tile" },
		{ keys = "View",				text = "this accessibility help, again closes it" },
		{ keys = "Menu",				text = "the game menu; closes an open list or the production panel first; with another screen open it says to close that screen first" },
		{ keys = "Left stick click",	text = "select your capital city; in a target mode move the target to the capital (like Backslash)" },
		{ keys = "Right stick click",	text = "select the next unit that needs orders" },
		{ keys = "Right stick up and down",	text = "previous and next of all your units" },
		{ keys = "Right stick left and right",	text = "previous and next city" },
		{ keys = "Lenses list",			text = "A switches the lens on or off like its number key and the list stays open, Y reads what its colors mean" },
		{ keys = "Screens list",		text = "A closes the list and opens the screen: tech tree, civics tree, government, religion, great people, great works, governors, city-states, espionage, trade routes, world rankings, climate, era progress, reports, civilopedia; a screen that is not available yet says so; B closes the screen" },
	} },
	{ title = "Popups", entries = {
		{ keys = "Enter",				text = "continue or close a popup, an advisor, a completed tech or civic, a wonder, an era" },
		{ keys = "Space",				text = "read the rest of a popup" },
		{ keys = "Up and Down",			text = "move between a popup's buttons" },
		{ keys = "Escape",				text = "close a popup" },
		{ keys = "Left and Right",		text = "treat with a clan popup: on Incite, choose the civilization to incite the clan against" },
		{ keys = "Enter",				text = "treat with a clan popup: hire, incite, bribe, ransom or close; Space reads the full description" },
		{ keys = "G or F7",				text = "completed tech or civic popup: opens the government screen (controller: X)" },
		{ keys = "R",					text = "espionage mission popup: renews a completed mission (controller: X)" },
		{ keys = "C",					text = "dedication popup: confirms the chosen dedication (controller: X)" },
		{ keys = "Any popup",			text = "other announcements wait until it closes, then they follow" },
	} },
};

function HelpText_Sections()
	return m_sections;
end

-- The key as the player presses it: the current binding, else the default of the entry, else "unbound".
function HelpText_KeyText( entry:table, lookup )
	if entry.action == nil then return entry.keys or ""; end
	local shown = nil;
	if lookup ~= nil then
		local ok:boolean, value = pcall( lookup, entry.action );
		if ok and type( value ) == "string" and value ~= "" then shown = value; end
	end
	return shown or entry.default or "unbound";
end

function HelpText_Line( entry:table, lookup )
	return HelpText_KeyText( entry, lookup ) .. ": " .. entry.text;
end

function HelpText_Build( lookup )
	local result:table = {};
	for s, section in ipairs( m_sections ) do
		local items:table = {};
		for e, entry in ipairs( section.entries ) do
			local line:string = HelpText_Line( entry, lookup );
			table.insert( items, { key = "h:" .. s .. ":" .. e, text = line, detail = line } );
		end
		table.insert( result, { title = section.title, items = items } );
	end
	return result;
end
