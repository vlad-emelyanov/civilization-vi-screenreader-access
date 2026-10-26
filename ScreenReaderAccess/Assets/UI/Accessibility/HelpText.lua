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
		{ keys = "Home and End",		text = "first and last entry" },
		{ keys = "Enter",				text = "choose or open the entry" },
		{ keys = "Space",				text = "read more about the entry" },
		{ keys = "Escape",				text = "close the list or go back one step" },
		{ keys = "Tab and Control+Tab",	text = "next and previous section, tab or category (Shift+Tab is the Steam overlay)" },
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
		{ action = "KeyNavPlotDetails",			default = "I",			text = "detailed description of the cursor tile" },
		{ action = "KeyNavCursorToSelection",	default = ".",			text = "cursor back to the selected unit or city and read it" },
		{ keys = "Cursor on a resource",	text = "the tile text adds what the resource needs: \"Horses, needs Animal Husbandry\" or \"Wine, plantation possible\"; I adds the research turns" },
		{ action = "KeyNavSelectAtCursor",		default = "K",			text = "select your unit or city on the cursor tile, again: the next one there" },
		{ action = "KeyNavCycleAllUnits",		default = "Control+K",	text = "select the next of all your units, also fortified and automated ones" },
		{ action = "NextUnit",					default = "]",			text = "next ready unit" },
		{ action = "PrevUnit",					default = "[",			text = "previous ready unit" },
		{ action = "KeyNavScanUnits",			default = "X",			text = "cursor to the nearest foreign unit in view, hostile first, again: the next" },
		{ action = "KeyNavYields",				default = "Control+G",	text = "gold, science, culture and faith in one sentence" },
		{ action = "KeyNavTopPanel",			default = "Control+Y",	text = "top panel list: yields, resources, research, civic, turn, era" },
		{ action = "KeyNavNotifications",		default = "Control+N",	text = "notifications: Enter activates, Delete dismisses, M sends a unit to its place" },
		{ action = "KeyNavEraProgress",			default = "Control+E",	text = "era progress: era score, thresholds, other civilizations" },
		{ action = "KeyNavHelp",				default = "Control+H",	text = "this help list" },
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
		{ action = "KeyNavUnitActions",			default = "Tab",		text = "menu of everything the selected unit can do: Enter runs, Space reads the tooltip" },
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
		{ action = "ExtraHotkeysUpgrade",		default = "U",			text = "upgrade the unit, or activate a great person (a Great Prophet founds its religion); says what happened, or why it cannot" },
		{ action = "ExtraHotkeysEnterFormation",default = "Shift+E",	text = "create or leave an escort formation; selecting a settler or builder says when a soldier of yours shares its tile or already escorts it" },
		{ keys = "Warnings",			text = "a settler or builder sent off alone near enemies or a barbarian camp is told so, with the key for an escort; a barbarian scout near your city sounds an alarm, a raid of two or more soldiers near a city and an unescorted builder in danger are spoken once and again when they change; N adds Raid expected after a scout escaped" },
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
		{ keys = "X",					text = "with a builder: browse the tiles it can improve; after them a Later group lists resource tiles that need a tech or civic first, Enter says what is missing" },
		{ keys = "Up and Down",			text = "in the browser: next and previous place or tile" },
		{ keys = "Left and Right",		text = "builder browser: next and previous city" },
		{ keys = "Space",				text = "in the browser: all reasons for the place" },
		{ keys = "Enter",				text = "in the browser: go there, or found the city or open the actions menu on the tile" },
		{ action = "FoundCity",			default = "B",			text = "found a city with the settler" },
		{ keys = "Escape",				text = "close the browser, the cursor goes back to the unit" },
	} },
	{ title = "Places list", entries = {
		{ action = "KeyNavPlaces",		default = "J",			text = "places list: threats first (a barbarian scout that has seen your city, raiders, enemies next to your settler or builder), cities, units, points of interest (barbarian camps say what guards them; Space says what destroying one gives), blind spots (land near your cities out of sight or unexplored, where barbarian camps can appear; unexplored areas may include sea and mountains), notification places, foreign cities, enemy civilians you can capture" },
		{ keys = "Tab and Control+Tab",	text = "next and previous category" },
		{ keys = "Space",				text = "read the tile and where it is" },
		{ keys = "Enter",				text = "cursor there, a unit of yours is selected" },
		{ keys = "M",					text = "send one of your units there, fastest first (on a threat: soldiers only; on a barbarian camp the first entry sends an attack party, the two fastest military units); for a civilian to capture only military land units are offered, moving onto it captures it. On a Settler or Builder in Your units it sends an escort instead: soldiers that can reach it, fastest first; Enter moves one onto its tile, then Shift+E forms the escort" },
		{ keys = "Control+N then M",	text = "send a unit to the place of a notification" },
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
		{ keys = "Tab and Control+Tab",	text = "in the production panel: production, queue, purchase with gold, purchase with faith" },
		{ keys = "Enter",				text = "in the production panel: produce or buy; districts and wonders start the placement mode" },
		{ action = "KeyNavCityReport",	default = "Control+I",	text = "city report: yields, growth, amenities, loyalty, defense, districts, citizens, religion" },
		{ keys = "Space",				text = "in the city report: the breakdown of the entry" },
		{ keys = "District spots entry",	text = "city report: which districts the city can build and the best adjacency spot for each, or the nearest unmet requirement when none can be built now (Enter repeats it with the best spot of every district, Tab opens production)" },
		{ keys = "Space",				text = "in the production panel on a district: the description, then Best spot with the adjacency bonus, direction and tile cost" },
		{ keys = "Resources entry",		text = "city report: the resources on the city's tiles, improved or not, and which tech or civic the missing improvements need" },
		{ keys = "Enter",				text = "city report: change yield focus, manage tiles, specialists, buy a tile" },
		{ keys = "Backspace or Delete",	text = "city report, specialists: remove one" },
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
		{ action = "ToggleTechTree",	default = "T",			text = "tech tree: Left and Right eras, Up and Down nodes, Enter sets the target (on a node you cannot research yet it says how many nodes and turns lie on the way, and what comes next), Shift+Enter queues" },
		{ action = "ToggleCivicsTree",	default = "C",			text = "civics tree: the same keys as the tech tree" },
		{ keys = "J, Q and F",			text = "in the trees: J current research and the target at the end of the queue, Q the queue, F search by name" },
		{ keys = "R",					text = "in the trees: lists the techs (civics) that unlock the improvement of resources near your cities, cheapest first; Up and Down, Enter sets the target, Shift+Enter queues, Escape leaves. A node that does so also says \"improves 2 Horses and 1 Sheep near your cities\"" },
		{ action = "ToggleGovernment",	default = "F7",			text = "government: Tab switches policies, governments, my government" },
		{ keys = "Escape in government",	text = "with an empty policy slot the changes are not confirmed: the first Escape warns, Escape again closes and discards them" },
		{ action = "ToggleCityStates",	default = "F2",			text = "city-states: Space bonuses and quests, Enter actions" },
		{ keys = "Enter, Left and C",		text = "city-states envoy mode: Enter adds an envoy, Left removes one, C confirms, A actions" },
		{ keys = "Escape in city-states envoy mode",	text = "with pending envoys the first Escape warns, Escape again discards them and closes; C confirms them" },
		{ action = "ToggleReligion",	default = "L",			text = "religion screen, also to found a religion and choose beliefs" },
		{ action = "ToggleGreatPeople",	default = "O",			text = "great people: Enter opens recruit, pass, patronize; Tab previously recruited" },
		{ action = "KeyNavGreatWorks",	default = "Control+W",	text = "great works: Enter picks up and places, V describes the work, Tab next building" },
		{ action = "ToggleTradeRoutes",	default = "F4",			text = "trade routes: Tab switches tabs, B switches whose benefits, Enter selects a trader" },
		{ action = "ToggleEspionage",	default = "F3",			text = "espionage: operatives, city activity, mission history; Enter gives a spy orders" },
		{ action = "ToggleRankings",	default = "F1",			text = "world rankings: Tab switches victory types, H explains the victory" },
		{ action = "KeyNavReports",		default = "F8",			text = "reports: yields, resources, city status, gossip; Tab switches tabs" },
		{ action = "ToggleGovernors",	default = "F10",		text = "governors: Enter opens appoint, assign and promote" },
		{ action = "ToggleTimeline",	default = "F11",		text = "historic moments timeline" },
		{ action = "ToggleWorldClimate",default = "Page Down",	text = "world climate (Gathering Storm): Tab switches overview, CO2, history" },
		{ action = "OpenCivilopedia",	default = "F9",			text = "civilopedia: Tab sections, Enter opens a page or link, Backspace back, F search" },
		{ action = "KeyNavDiplomacy",	default = "V",			text = "diplomacy: you first, then civilizations met, each with score, military, science, culture, gold and faith; Enter opens the diplomacy screen with that leader" },
		{ action = "KeyNavStanding",	default = "Control+R",	text = "where you stand among the civilizations you have met: rank in score, military, science, culture, gold and faith, and your weakest category" },
		{ keys = "Tab and Control+Tab",	text = "deal screen: Deal, your items, their items, actions; S reads the summary" },
		{ keys = "Left and Right",		text = "deal screen: change a gold or resource amount by 1, with Shift by 10" },
		{ keys = "Left and Right",		text = "world congress: choose option A or B; equals or Shift+Up adds a vote, minus removes" },
	} },
	{ title = "Popups", entries = {
		{ keys = "Enter",				text = "continue or close a popup, an advisor, a completed tech or civic, a wonder, an era" },
		{ keys = "Space",				text = "read the rest of a popup" },
		{ keys = "Up and Down",			text = "move between a popup's buttons" },
		{ keys = "Escape",				text = "close a popup" },
		{ keys = "Left and Right",		text = "treat with a clan popup: on Incite, choose the civilization to incite the clan against" },
		{ keys = "Enter",				text = "treat with a clan popup: hire, incite, bribe, ransom or close; Space reads the full description" },
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
