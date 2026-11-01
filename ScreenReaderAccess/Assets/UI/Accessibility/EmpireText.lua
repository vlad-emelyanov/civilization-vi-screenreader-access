-- ===========================================================================
--	EmpireText: the wording of the empire overview list (Control+Shift+I, HubEmpire.lua). Pure: no engine calls except
--	Locale.Lookup, so test/lua/test_empire.lua checks it. HubEmpire gathers the facts, this file says them.
--
--	City facts (EmpireText.FactsFromReport( d ) turns the table of CityReportGather into them): name, population, foodSurplus,
--	occupied, turnsUntilGrowth, housing, housingMultiplier, amenitiesHave, amenitiesNeeded, mood, loyalty / loyaltyPerTurn /
--	loyaltyTurnsToLoss / loyaltyLevel / loyaltyTopLevel, production (name), productionTurns, wallMax, underSiege, plus what
--	HubEmpire adds: danger = { count, civ }, undefended = { enemy }.
-- ===========================================================================

EmpireText = {};

-- A slow build is worth a line from this many turns on.
EmpireText.LONG_PRODUCTION_TURNS = 20;

local function Round1( value:number )
	return math.floor( value * 10 + 0.5 ) / 10;
end

local function Num( value:number )
	value = Round1( value );
	if value == math.floor( value ) then return tostring( math.floor( value ) ); end
	return tostring( value );
end

local function Turns( n:number )
	return n .. ( n == 1 and " turn" or " turns" );
end

function EmpireText.Plural( n:number, one:string, many:string )
	return n .. " " .. ( n == 1 and one or many );
end

local ORDINALS:table = { "first", "second", "third", "fourth", "fifth", "sixth", "seventh", "eighth", "ninth" };
function EmpireText.Ordinal( n:number )
	return ORDINALS[ n ] or ( n .. "th" );
end

-- ---------------------------------------------------------------------------
--	Cities
-- ---------------------------------------------------------------------------
function EmpireText.FactsFromReport( d:table )
	local g:table = d.growth or {};
	local f:table = {
		name = d.name, population = d.population or 0, foodSurplus = d.foodSurplus or 0,
		occupied = g.occupied == true, turnsUntilGrowth = g.turnsUntilGrowth or 0, housing = g.housing, housingMultiplier = g.housingMultiplier or 1,
		wallMax = d.defense ~= nil and d.defense.wallMax or 0, underSiege = d.defense ~= nil and d.defense.underSiege == true,
	};
	if d.amenities ~= nil then
		f.amenitiesHave, f.amenitiesNeeded, f.mood = d.amenities.have, d.amenities.needed, d.amenities.mood;
	end
	local l:table = d.loyalty;
	if l ~= nil then
		f.loyalty, f.loyaltyPerTurn, f.loyaltyTurnsToLoss = l.current, l.perTurn, l.turnsToLoss;
		f.loyaltyLevel, f.loyaltyTopLevel = l.levelIndex, l.topLevel or 3;
	end
	local p:table = d.production;
	if p ~= nil and p.name ~= nil and p.name ~= "" then
		f.production = p.name;
		if p.turns ~= nil and p.turns > 0 then f.productionTurns = p.turns; end
	end
	return f;
end

-- The problems of one city: { score, text } entries, the most urgent first (score is the order across cities too).
function EmpireText.CityProblems( f:table )
	local list:table = {};
	local name:string = f.name;
	local function Add( score:number, text:string ) table.insert( list, { score = score, text = text, city = name } ); end
	if f.danger ~= nil then
		local who:string = EmpireText.Plural( f.danger.count or 1, "unit", "units" );
		if f.danger.civ ~= nil and f.danger.civ ~= "" then who = who .. " of " .. f.danger.civ; end
		Add( 100, name .. " in danger, " .. who .. " near" );
	end
	if f.underSiege then Add( 98, name .. " under siege" ); end
	if f.loyaltyTurnsToLoss ~= nil and f.loyaltyTurnsToLoss >= 1 then
		Add( 96 - math.min( f.loyaltyTurnsToLoss, 30 ), name .. " loyalty falling, lost in " .. Turns( f.loyaltyTurnsToLoss ) );
	end
	if not f.occupied and f.turnsUntilGrowth < 0 then
		local text:string = name .. " is starving, food minus " .. Num( -f.foodSurplus );
		Add( 90, text .. ", loses a citizen in " .. Turns( -f.turnsUntilGrowth ) );
	end
	if f.amenitiesHave ~= nil and f.amenitiesNeeded ~= nil and f.amenitiesHave < f.amenitiesNeeded then
		local deficit:number = f.amenitiesNeeded - f.amenitiesHave;
		local mood:string = ( f.mood ~= nil and f.mood ~= "" ) and string.lower( f.mood ) or "unhappy";
		Add( 70 + math.min( deficit, 20 ), name .. " " .. mood .. ", amenities minus " .. Num( deficit ) );
	end
	if f.production == nil then Add( 60, name .. ": no production" ); end
	if f.undefended ~= nil then
		local text:string = name .. " undefended, no garrison and no walls";
		if f.undefended.enemy ~= nil and f.undefended.enemy ~= "" then text = text .. ", at war with " .. f.undefended.enemy; end
		Add( 55, text );
	end
	if f.loyaltyPerTurn ~= nil and f.loyaltyPerTurn < 0 and f.loyaltyTurnsToLoss == nil and f.loyaltyLevel ~= nil
			and f.loyaltyLevel < ( f.loyaltyTopLevel or 3 ) then
		Add( 50, name .. " loyalty " .. Num( f.loyalty or 0 ) .. ", falling " .. Num( -f.loyaltyPerTurn ) .. " a turn" );
	end
	if not f.occupied and f.housing ~= nil then
		local free:number = f.housing - f.population;
		if free <= 0 and f.foodSurplus > 0 then
			Add( 40, name .. ": housing full, growth stopped" );
		elseif free > 0 and free <= 1 and f.turnsUntilGrowth > 0 then
			Add( 38, name .. ": housing full in " .. Turns( f.turnsUntilGrowth ) );
		end
	end
	if f.production ~= nil and f.productionTurns ~= nil and f.productionTurns >= EmpireText.LONG_PRODUCTION_TURNS then
		Add( 30, name .. ": " .. f.production .. " takes " .. Turns( f.productionTurns ) );
	end
	table.sort( list, function( a, b ) return a.score > b.score; end );
	return list;
end

-- All problems of all cities, most urgent first (ties: city name).
function EmpireText.Attention( problems:table )
	local sorted:table = {};
	for i, p in ipairs( problems ) do sorted[ i ] = p; end
	table.sort( sorted, function( a, b )
		if a.score ~= b.score then return a.score > b.score; end
		if a.city ~= b.city then return a.city < b.city; end
		return a.text < b.text;
	end );
	return sorted;
end

function EmpireText.GrowthState( f:table )
	if f.occupied then return "occupied"; end
	if f.turnsUntilGrowth < 0 then return "starving"; end
	if f.housingMultiplier <= 0 and f.foodSurplus > 0 then return "growth stopped, housing"; end
	if f.turnsUntilGrowth > 0 then return "growing in " .. Turns( f.turnsUntilGrowth ); end
	return "not growing";
end

-- "Rome, population 8, growing in 4 turns, Harbor 5 turns, 3 problems"
function EmpireText.CityLine( f:table, problemCount:number )
	local text:string = f.name .. ", population " .. f.population .. ", " .. EmpireText.GrowthState( f ) .. ", ";
	if f.production == nil then
		text = text .. "no production";
	else
		text = text .. f.production .. ( f.productionTurns ~= nil and ( " " .. Turns( f.productionTurns ) ) or "" );
	end
	if problemCount > 0 then text = text .. ", " .. EmpireText.Plural( problemCount, "problem", "problems" ); end
	return text;
end

-- Cities biggest first, then by name.
function EmpireText.CityLess( a:table, b:table )
	if a.population ~= b.population then return a.population > b.population; end
	return a.name < b.name;
end

-- Space on a city: the yields, growth, amenities and production lines of the city report, from its items ({ key, text }).
local SUMMARY_KEYS:table = { "yields", "growth", "amenities", "production" };
function EmpireText.CitySummary( name:string, reportItems:table )
	local parts:table = { name };
	for _, key in ipairs( SUMMARY_KEYS ) do
		for _, item in ipairs( reportItems or {} ) do
			if item.key == key then table.insert( parts, item.text ); end
		end
	end
	return table.concat( parts, ". " );
end

-- ---------------------------------------------------------------------------
--	Units. u = { total, needOrders, needNames = { [name] = n }, idle = { [name] = n }, soldiers, formation, busy = { [state] = n } }
-- ---------------------------------------------------------------------------
local BUSY_ORDER:table = { "fortified", "sleeping", "healing", "on alert", "intercepting", "exploring", "moving", "building", "on a trade route", "on a mission", "turn skipped", "busy" };

local function SortedNames( counts:table )
	local names:table = {};
	for name, _ in pairs( counts ) do table.insert( names, name ); end
	table.sort( names );
	return names;
end

local function CountedNames( counts:table )
	local parts:table = {};
	for _, name in ipairs( SortedNames( counts ) ) do
		local n:number = counts[ name ];
		table.insert( parts, n .. " " .. ( n == 1 and name or ( name .. "s" ) ) );
	end
	return table.concat( parts, ", " );
end

function EmpireText.UnitItems( u:table )
	local items:table = {};
	for _, name in ipairs( SortedNames( u.idle or {} ) ) do
		local n:number = u.idle[ name ];
		table.insert( items, { key = "idle:" .. name, text = n .. " " .. ( n == 1 and name or ( name .. "s" ) ) .. " idle",
			detail = EmpireText.Plural( n, name, name .. "s" ) .. " asleep or fortified and forgotten" } );
	end
	if ( u.needOrders or 0 ) > 0 then
		table.insert( items, { key = "orders", text = EmpireText.Plural( u.needOrders, "unit needs", "units need" ) .. " orders",
			detail = "Need orders: " .. CountedNames( u.needNames or {} ) } );
	end
	if ( u.soldiers or 0 ) > 0 then
		local text:string = EmpireText.Plural( u.soldiers, "soldier", "soldiers" );
		if ( u.formation or 0 ) > 0 then text = text .. ", " .. u.formation .. " in formation"; end
		table.insert( items, { key = "soldiers", text = text, detail = text } );
	end
	local busy:table = {};
	for _, state in ipairs( BUSY_ORDER ) do
		local n:number = ( u.busy or {} )[ state ];
		if n ~= nil and n > 0 then table.insert( busy, n .. " " .. state ); end
	end
	if #busy > 0 then
		local text:string = "Busy: " .. table.concat( busy, ", " );
		table.insert( items, { key = "busy", text = text, detail = text } );
	end
	if #items == 0 then
		table.insert( items, { key = "none", text = "No units", detail = "No units", uncounted = true, noAction = true } );
	end
	return items;
end

-- ---------------------------------------------------------------------------
--	Victories. v = { kind, ... } as HubEmpire gathers it; leaderName / leaderIsYou: the first of the game's own ranking.
-- ---------------------------------------------------------------------------
local function LeaderText( v:table, detail:string )
	if v.leaderIsYou then return "; you lead"; end
	if v.leaderName == nil then return ""; end
	local text:string = "; leader " .. v.leaderName;
	if detail ~= nil and detail ~= "" then text = text .. ", " .. detail; end
	return text;
end

function EmpireText.VictoryLine( v:table )
	local k:string = v.kind;
	if k == "science" then
		local text:string = "Science: " .. v.done .. " of " .. v.total .. " milestones";
		if v.done >= v.total and ( v.lightTotal or 0 ) > 0 then
			text = text .. ", light years " .. ( v.lightYears or 0 ) .. " of " .. v.lightTotal;
		elseif v.next ~= nil and v.next ~= "" then
			text = text .. ", next " .. v.next;
		end
		return text .. LeaderText( v, v.leaderDone ~= nil and ( v.leaderDone .. " of " .. v.total ) or nil );
	elseif k == "culture" then
		local text:string = "Culture: " .. v.visiting .. " of " .. v.required .. " foreign tourists";
		return text .. LeaderText( v, v.leaderVisiting ~= nil and ( v.leaderVisiting .. " of " .. v.leaderRequired ) or nil );
	elseif k == "domination" then
		local text:string = "Domination: you hold " .. v.held .. " of " .. v.total .. " capitals";
		return text .. LeaderText( v, v.leaderHeld ~= nil and ( "holds " .. v.leaderHeld ) or nil );
	elseif k == "religion" then
		local text:string;
		if v.hasReligion then
			text = "Religion: followers majority in " .. v.converted .. " of " .. v.total .. " civs";
		else
			text = "Religion: you have not founded a religion";
		end
		return text .. LeaderText( v, v.leaderConverted ~= nil and ( v.leaderConverted .. " of " .. v.total ) or nil );
	elseif k == "diplomatic" then
		local text:string = "Diplomatic: " .. v.points .. " of " .. v.required .. " victory points";
		return text .. LeaderText( v, v.leaderPoints ~= nil and tostring( v.leaderPoints ) or nil );
	elseif k == "score" then
		local text:string = "Score: " .. v.score .. ", " .. EmpireText.Ordinal( v.position ) .. " of " .. v.count;
		text = text .. LeaderText( v, v.leaderScore ~= nil and tostring( v.leaderScore ) or nil );
		if ( v.endTurn or 0 ) > 0 then text = text .. "; game ends turn " .. v.endTurn; end
		return text;
	end
	-- a modded victory type: its name and who leads
	local text:string = ( v.name or "Victory" ) .. ": " .. ( v.position ~= nil and ( "you are " .. EmpireText.Ordinal( v.position ) ) or "no ranking" );
	return text .. LeaderText( v, nil );
end

-- Space: the game's ranking, "1. Russia, 2 of 4. 2. You, 1 of 4" from { name, text } entries (at most six).
function EmpireText.Ranking( entries:table )
	local parts:table = {};
	for i, e in ipairs( entries or {} ) do
		if i > 6 then break; end
		table.insert( parts, i .. ". " .. e.name .. ( ( e.text ~= nil and e.text ~= "" ) and ( ", " .. e.text ) or "" ) );
	end
	if #parts == 0 then return "No ranking"; end
	return "Ranking: " .. table.concat( parts, ". " );
end

-- ---------------------------------------------------------------------------
--	Standing. s = { met = n, atWar = { names }, cityStatesAtWar = n, military = { { name, value, atWar } }, myMilitary, eraTurns }
-- ---------------------------------------------------------------------------
local function And( names:table )
	if #names <= 1 then return names[ 1 ] or ""; end
	local head:table = {};
	for i = 1, #names - 1 do head[ i ] = names[ i ]; end
	return table.concat( head, ", " ) .. " and " .. names[ #names ];
end
EmpireText.And = And;

function EmpireText.StandingItems( s:table )
	local items:table = {};
	local war:table = {};
	for _, name in ipairs( s.atWar or {} ) do table.insert( war, name ); end
	if ( s.cityStatesAtWar or 0 ) > 0 then table.insert( war, EmpireText.Plural( s.cityStatesAtWar, "city-state", "city-states" ) ); end
	local text:string;
	if #war > 0 then
		text = "At war with " .. And( war );
	elseif ( s.met or 0 ) == 0 then
		text = "You have not met any civilization";
	else
		text = "At peace with all " .. EmpireText.Plural( s.met, "civilization", "civilizations" ) .. " you have met";
	end
	table.insert( items, { key = "war", text = text, detail = text } );
	if s.myMilitary ~= nil and #( s.military or {} ) > 0 then
		local parts:table = {};
		for i, m in ipairs( s.military ) do
			if i > 3 then break; end
			table.insert( parts, m.name .. " " .. Num( m.value ) .. ( m.atWar and ", at war" or "" ) );
		end
		local mine:string = "your military " .. Num( s.myMilitary );
		table.insert( items, { key = "military", text = "Strongest militaries: " .. table.concat( parts, "; " ) .. "; " .. mine,
			detail = "Military strength as the diplomacy ribbon shows it: " .. table.concat( parts, "; " ) .. "; " .. mine } );
	end
	if s.eraTurns ~= nil and s.eraTurns > 0 then
		local text2:string = "Next era in " .. Turns( s.eraTurns );
		table.insert( items, { key = "era", text = text2, detail = text2 } );
	end
	return items;
end

-- ---------------------------------------------------------------------------
--	The opening line: "Empire, 3 need attention, 8 cities, 7 units need orders"
-- ---------------------------------------------------------------------------
function EmpireText.OpenLine( attention:number, cities:number, needOrders:number )
	local parts:table = { "Empire" };
	if attention > 0 then
		table.insert( parts, attention .. ( attention == 1 and " needs" or " need" ) .. " attention" );
	else
		table.insert( parts, "nothing urgent" );
	end
	table.insert( parts, EmpireText.Plural( cities, "city", "cities" ) );
	if needOrders > 0 then table.insert( parts, EmpireText.Plural( needOrders, "unit needs", "units need" ) .. " orders" ); end
	return table.concat( parts, ", " );
end
