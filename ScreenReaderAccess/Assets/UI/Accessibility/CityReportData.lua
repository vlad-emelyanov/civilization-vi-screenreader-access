-- ===========================================================================
--	CityReportData: turns a plain table about one city into the items of the city report region (Control+I).
--	No engine calls except CleanTextForSpeech, so it is unit tested (test/lua/test_cityreport.lua). The table is
--	filled by CityReportGather.lua from the game's own GetCityData (CitySupport.lua), see there for the fields.
--
--	CityReport_BuildItems( d ) -> array of { key, text, detail }
--	  text:    what Up/Down speak, e.g. "Yields: food plus 4, production 12, gold 8, science 6, culture 3, faith 2"
--	  detail:  what Space speaks (the game's own tooltips / breakdowns, cleaned for speech)
--
--	Fields of d that are optional: loyalty, power, greatWorks, tradingPosts (nil or empty: no item).
-- ===========================================================================

include( "ScreenReader" );
include( "DistrictAdvice" );

local function Round1( value:number )
	return math.floor( value * 10 + 0.5 ) / 10;
end

-- 6, 2.5, 0 (no trailing .0)
local function Num( value:number )
	value = Round1( value );
	if value == math.floor( value ) then return tostring( math.floor( value ) ); end
	return tostring( value );
end

-- "plus 4", "minus 2.5", "0"
local function Signed( value:number )
	value = Round1( value );
	if value == 0 then return "0"; end
	if value > 0 then return "plus " .. Num( value ); end
	return "minus " .. Num( -value );
end

local function Turns( n:number )
	return n .. ( n == 1 and " turn" or " turns" );
end

local function Clean( text:string )
	text = CleanTextForSpeech( text );
	text = string.gsub( text, "%.%s*%.", "." );		-- "[NEWLINE][NEWLINE]" gives ". ."
	return text;
end

local function Join( parts:table, separator:string )
	return table.concat( parts, separator or ", " );
end

-- "a, b, c and 2 more"
local function ShortList( names:table, maxShown:number )
	if #names <= maxShown then return Join( names ); end
	local shown:table = {};
	for i = 1, maxShown do shown[i] = names[i]; end
	return Join( shown ) .. " and " .. ( #names - maxShown ) .. " more";
end

local function Plural( n:number, one:string, many:string )
	return n .. " " .. ( n == 1 and one or many );
end

-- "Label value" for every entry { label, value } that is not 0, signed: "Luxuries plus 4, Civics minus 1"
local function SignedLines( entries:table )
	local parts:table = {};
	for _, e in ipairs( entries or {} ) do
		if e.value ~= nil and Round1( e.value ) ~= 0 then table.insert( parts, e.label .. " " .. Signed( e.value ) ); end
	end
	return parts;
end

-- ---------------------------------------------------------------------------
-- 1. Yields
-- ---------------------------------------------------------------------------
local YIELD_ORDER:table = { "food", "production", "gold", "science", "culture", "faith" };

local function YieldsItem( d:table )
	local parts:table = {};
	local details:table = {};
	for _, name in ipairs( YIELD_ORDER ) do
		local y:table = d.yields[ name ];
		if y ~= nil then
			if name == "food" then
				table.insert( parts, "food " .. Signed( d.foodSurplus ) );
			else
				table.insert( parts, name .. " " .. Num( y.value ) );
			end
			local tip:string = Clean( y.tooltip );
			local head:string = name .. " " .. Num( y.value ) .. " per turn";
			if name == "food" then head = "food " .. Num( y.value ) .. " per turn, " .. Signed( d.foodSurplus ) .. " after the citizens eat"; end
			if tip ~= "" then head = head .. ". " .. tip; end
			table.insert( details, head );
		end
	end
	return { key = "yields", text = "Yields: " .. Join( parts ), detail = Join( details, ". " ) };
end

-- ---------------------------------------------------------------------------
-- 2. Growth and housing
-- ---------------------------------------------------------------------------
local function HousingBreakdown( h:table )
	local entries:table = {
		{ label = "buildings", value = h.fromBuildings }, { label = "districts", value = h.fromDistricts },
		{ label = "improvements", value = h.fromImprovements }, { label = "water", value = h.fromWater },
		{ label = "civics", value = h.fromCivics }, { label = "great people", value = h.fromGreatPeople },
		{ label = "starting era", value = h.fromStartingEra }, { label = "great works", value = h.fromGreatWorks },
	};
	local parts:table = {};
	for _, e in ipairs( entries ) do
		if e.value ~= nil and e.value ~= 0 then table.insert( parts, e.label .. " " .. Num( e.value ) ); end
	end
	return parts;
end

local function GrowthItem( d:table )
	local g:table = d.growth;
	local text:string = "Population " .. d.population .. " of " .. Num( g.housing ) .. " housing";
	if d.population >= g.housing then
		text = text .. ", housing full";
	elseif g.housing - d.population == 1 then
		text = text .. ", 1 free housing";
	end
	local surplus:number = d.foodSurplus;
	local state:string;
	if g.occupied then
		state = "occupied, no growth";
	elseif g.turnsUntilGrowth < 0 then
		text = text .. ", " .. Signed( surplus ) .. " food";
		state = "starving, loses a citizen in " .. Turns( -g.turnsUntilGrowth );
	elseif g.housingMultiplier <= 0 and surplus > 0 then
		text = text .. ", " .. Signed( surplus ) .. " food";
		state = "growth stopped: housing";
	elseif g.turnsUntilGrowth > 0 then
		text = text .. ", " .. Signed( surplus ) .. " food";
		state = "grows in " .. Turns( g.turnsUntilGrowth );
		if g.housingMultiplier > 0 and g.housingMultiplier <= 0.5 then
			state = state .. ", slowed " .. Num( ( 1 - g.housingMultiplier ) * 100 ) .. " percent by housing";
		end
	else
		text = text .. ", " .. Signed( surplus ) .. " food";
		state = "not growing";
	end
	text = text .. ", " .. state;

	local detail:table = {};
	local eaten:number = g.foodPerTurn - surplus;
	table.insert( detail, "Food " .. Num( g.foodPerTurn ) .. " per turn, citizens eat " .. Num( eaten ) .. ", surplus " .. Signed( surplus ) );
	if not g.occupied and g.turnsUntilGrowth >= 0 then
		table.insert( detail, Num( g.foodNeeded ) .. " more food for the next citizen" );
		local mods:table = {};
		if g.happinessGrowthModifier ~= 0 then table.insert( mods, "amenities " .. Signed( g.happinessGrowthModifier ) .. " percent" ); end
		if g.otherGrowthModifier ~= 0 then table.insert( mods, "religion and wonders " .. Signed( g.otherGrowthModifier * 100 ) .. " percent" ); end
		table.insert( mods, "housing multiplier " .. Num( g.housingMultiplier ) );
		table.insert( detail, "Growth modifiers: " .. Join( mods ) );
	elseif g.occupied then
		table.insert( detail, "Occupied: growth multiplier " .. Num( g.occupationMultiplier * 100 ) .. " percent" );
	end
	if g.loyaltyGrowthPercent ~= nil and g.loyaltyGrowthPercent ~= 0 then
		table.insert( detail, "Loyalty changes growth by " .. Signed( g.loyaltyGrowthPercent ) .. " percent" );
	end
	local housing:table = HousingBreakdown( g.housingSources or {} );
	local h:string = "Housing " .. Num( g.housing ) .. " for " .. Plural( d.population, "citizen", "citizens" );
	if #housing > 0 then h = h .. ", from " .. Join( housing ); end
	table.insert( detail, h );
	if g.housingAdvice ~= nil and g.housingAdvice ~= "" then table.insert( detail, Clean( g.housingAdvice ) ); end
	return { key = "growth", text = text, detail = Join( detail, ". " ) };
end

-- ---------------------------------------------------------------------------
-- 3. Amenities
-- ---------------------------------------------------------------------------
local function AmenitiesItem( d:table )
	local a:table = d.amenities;
	local text:string = "Amenities " .. Num( a.have ) .. " of " .. Num( a.needed );
	if a.mood ~= nil and a.mood ~= "" then text = text .. ", " .. a.mood; end
	if a.growthPercent ~= 0 then
		text = text .. ", growth " .. Signed( a.growthPercent ) .. " percent, yields " .. Signed( a.yieldPercent ) .. " percent";
	end

	local detail:table = {};
	local sources:table = SignedLines( a.sources );
	if #sources > 0 then
		table.insert( detail, "Amenities from " .. Join( sources ) );
	else
		table.insert( detail, "No amenity sources" );
	end
	local lost:table = SignedLines( a.losses );
	if #lost > 0 then table.insert( detail, "Lost: " .. Join( lost ) ); end
	table.insert( detail, "Needs " .. Num( a.needed ) .. " for " .. Plural( d.population, "citizen", "citizens" ) .. ", has " .. Num( a.have ) );
	if a.growthPercent ~= 0 then
		table.insert( detail, "Effect: citizen growth " .. Signed( a.growthPercent ) .. " percent, all yields except food " .. Signed( a.yieldPercent ) .. " percent" );
	end
	if a.advice ~= nil and a.advice ~= "" then table.insert( detail, Clean( a.advice ) ); end
	return { key = "amenities", text = text, detail = Join( detail, ". " ) };
end

-- ---------------------------------------------------------------------------
-- 4. Loyalty (Rise and Fall, Gathering Storm)
-- ---------------------------------------------------------------------------
local function LoyaltyItem( d:table )
	local l:table = d.loyalty;
	if l == nil then return nil; end
	local text:string = "Loyalty " .. Num( l.current ) .. ", " .. Signed( l.perTurn ) .. " per turn";
	if l.level ~= nil and l.level ~= "" then text = text .. ", " .. l.level; end
	-- only a city that is falling or below the top level is in danger of turning (levelIndex: LoyaltyLevels row, 3 = Loyal)
	local atRisk:boolean = l.perTurn < 0 or ( l.levelIndex ~= nil and l.levelIndex < ( l.topLevel or 3 ) );
	if atRisk and l.rival ~= nil and l.rival ~= "" then text = text .. ", may turn to " .. l.rival; end

	local detail:table = {};
	table.insert( detail, "Loyalty " .. Num( l.current ) .. " of " .. Num( l.max ) .. ", " .. Signed( l.perTurn ) .. " per turn" );
	if l.effect ~= nil and l.effect ~= "" then table.insert( detail, Clean( l.effect ) ); end
	local sources:table = SignedLines( l.sources );
	if #sources > 0 then table.insert( detail, "Pressure per turn: " .. Join( sources ) ); end
	local influence:table = {};
	for _, p in ipairs( l.influence or {} ) do table.insert( influence, p.name .. " " .. Num( p.value ) ); end
	if #influence > 0 then table.insert( detail, "Influence of civilizations here: " .. Join( influence ) ); end
	if l.rival ~= nil and l.rival ~= "" then table.insert( detail, "The city would turn to " .. l.rival .. " if loyalty ran out" ); end
	if l.advice ~= nil and l.advice ~= "" then table.insert( detail, Clean( l.advice ) ); end
	return { key = "loyalty", text = text, detail = Join( detail, ". " ) };
end

-- ---------------------------------------------------------------------------
-- 4b. Power (Gathering Storm): d.power = { current, required, generatedTotal, status = "powered"|"underpowered"|"none",
--     description, consumed / needed / generated = { { label, value } }, advice }
-- ---------------------------------------------------------------------------
-- A power source name can reach us as "Rome Rome" (the game's source key is a composed string); say a repeated
-- word sequence once ("Rome Rome" -> "Rome", "Coal Plant Coal Plant" -> "Coal Plant").
local function CollapseRepeat( label:string )
	label = string.gsub( tostring( label or "" ), "%s+", " " );
	label = string.gsub( label, "^ ", "" );
	label = string.gsub( label, " $", "" );
	local words:table = {};
	for w in string.gmatch( label, "%S+" ) do table.insert( words, w ); end
	local n:number = #words;
	if n >= 2 and n % 2 == 0 then
		local half:number = n / 2;
		local same:boolean = true;
		for i = 1, half do
			if words[ i ] ~= words[ i + half ] then same = false; break; end
		end
		if same then return table.concat( words, " ", 1, half ); end
	end
	return label;
end

local function PowerLines( entries:table )
	local parts:table = {};
	for _, e in ipairs( entries or {} ) do
		if e.value ~= nil then table.insert( parts, CollapseRepeat( e.label ) .. " " .. Num( e.value ) ); end
	end
	return parts;
end

local function PowerItem( d:table )
	local p:table = d.power;
	if p == nil then return nil; end
	local required:number = p.required or 0;
	local generated:number = p.generatedTotal or 0;
	if required == 0 and generated == 0 then return nil; end
	local text:string;
	if required == 0 then
		text = "Power: none needed, generates " .. Num( generated );
	else
		text = "Power " .. Num( p.current or 0 ) .. " of " .. Num( required );
		if p.status == "underpowered" then
			text = text .. " needed, underpowered";
		else
			text = text .. ", powered";
		end
		if generated > 0 then text = text .. ", generates " .. Num( generated ); end
	end

	local detail:table = {};
	if p.description ~= nil and p.description ~= "" then table.insert( detail, Clean( p.description ) ); end
	local consumed:table = PowerLines( p.consumed );
	if #consumed > 0 then table.insert( detail, "From: " .. Join( consumed ) ); end
	local needed:table = PowerLines( p.needed );
	if #needed > 0 then table.insert( detail, "Needed by: " .. Join( needed ) ); end
	local made:table = PowerLines( p.generated );
	if #made > 0 then table.insert( detail, "Generates: " .. Join( made ) ); end
	if p.advice ~= nil and p.advice ~= "" then table.insert( detail, Clean( p.advice ) ); end
	if #detail == 0 then table.insert( detail, text ); end
	-- the LOC descriptions and the advice end with a period: strip it before joining with ". "
	for i, part in ipairs( detail ) do detail[i] = string.gsub( part, "[%.%s]+$", "" ); end
	return { key = "power", text = text, detail = Join( detail, ". " ) };
end

-- ---------------------------------------------------------------------------
-- 5. Defense
-- ---------------------------------------------------------------------------
local function DefenseItem( d:table )
	local f:table = d.defense;
	local parts:table = { "Health " .. Num( f.hp ) .. " of " .. Num( f.hpMax ) };
	if f.wallMax > 0 then
		table.insert( parts, "walls " .. Num( f.wall ) .. " of " .. Num( f.wallMax ) );
	else
		table.insert( parts, "no walls" );
	end
	table.insert( parts, "defense strength " .. Num( f.strength ) );
	if f.underSiege then table.insert( parts, "under siege" ); end
	local text:string = Join( parts );
	local detail:string = text;
	if f.underSiege then detail = detail .. ". A besieged city does not heal and cannot be supplied"; end
	if f.hp < f.hpMax or ( f.wallMax > 0 and f.wall < f.wallMax ) then detail = detail .. ". Damaged"; end
	return { key = "defense", text = text, detail = detail };
end

-- ---------------------------------------------------------------------------
-- 6. Production
-- ---------------------------------------------------------------------------
local function ProductionItem( d:table )
	local p:table = d.production;
	if p == nil or p.name == nil or p.name == "" then
		local text:string = "Production: nothing, " .. SRKey( "Tab" ) .. " opens production";
		return { key = "production", text = text, detail = text };
	end
	local text:string = "Production: " .. p.name;
	if p.turns ~= nil and p.turns > 0 then text = text .. ", " .. Turns( p.turns ); end
	if p.queued ~= nil and p.queued > 0 then text = text .. ", " .. p.queued .. " more queued"; end
	text = text .. ", " .. SRKey( "Tab" ) .. " opens production";

	local detail:table = { p.name };
	if p.percent ~= nil then table.insert( detail, Num( p.percent * 100 ) .. " percent done" ); end
	if p.turns ~= nil and p.turns > 0 then table.insert( detail, Turns( p.turns ) .. " left" ); end
	table.insert( detail, Num( d.yields.production.value ) .. " production per turn" );
	if p.description ~= nil and p.description ~= "" then table.insert( detail, Clean( p.description ) ); end
	if p.queued ~= nil and p.queued > 0 then table.insert( detail, p.queued .. " more in the queue" ); end
	table.insert( detail, SRKey( "Tab" ) .. " opens the production panel to choose or buy" );
	return { key = "production", text = text, detail = Join( detail, ". " ) };
end

-- ---------------------------------------------------------------------------
-- 7. Districts and buildings, wonders
-- ---------------------------------------------------------------------------
local function BuildingName( b:table )
	if b.pillaged then return b.name .. " (pillaged)"; end
	return b.name;
end

local function DistrictsItem( d:table )
	local parts:table = {};
	local detail:table = {};
	for _, dist in ipairs( d.districts ) do
		local name:string = dist.name;
		if dist.pillaged then name = name .. " (pillaged)"; end
		local buildings:table = {};
		for _, b in ipairs( dist.buildings ) do table.insert( buildings, BuildingName( b ) ); end
		local line:string = name;
		if #buildings > 0 then line = line .. " (" .. ShortList( buildings, 2 ) .. ")"; end
		table.insert( parts, line );
		local full:string = name;
		if #buildings > 0 then full = full .. ": " .. Join( buildings ); else full = full .. ": no buildings"; end
		if dist.yield ~= nil and dist.yield ~= "" then full = full .. ", yields " .. dist.yield; end
		table.insert( detail, full );
	end
	local wonders:table = {};
	for _, w in ipairs( d.wonders ) do table.insert( wonders, BuildingName( w ) ); end
	local text:string;
	if #parts == 0 then
		text = "Districts: none";
	else
		text = "Districts: " .. Join( parts );
	end
	if #wonders > 0 then
		text = text .. ". Wonders: " .. ShortList( wonders, 3 );
		table.insert( detail, "Wonders: " .. Join( wonders ) );
	end
	if d.districtsMax ~= nil and d.districtsMax > 0 then
		table.insert( detail, d.districtsCount .. " of " .. d.districtsMax .. " districts that need population" );
	end
	table.insert( detail, Plural( d.buildingsNum, "building", "buildings" ) .. " in total" );
	return { key = "districts", text = text, detail = Join( detail, ". " ) };
end

-- "District spots": d.districtSpots() returns the entries of DistrictAdvice (computed lazily: the item's text is only
-- looked up when it is spoken, because the item list is rebuilt at every key and the scan is not free).
local function DistrictSpotsItem( d:table )
	if d.districtSpots == nil then return nil; end
	local item:table = { key = "districtspots" };
	local function Entries()
		local ok:boolean, entries = pcall( d.districtSpots );
		if ok and entries ~= nil then return entries; end
		return {};
	end
	local cache:table = {};
	setmetatable( item, { __index = function( t, k )
		if cache[k] ~= nil then return cache[k]; end
		if k == "text" then
			local text:string = DistrictAdvice_Line( Entries(), false );
			cache[k] = text;
			return text;
		elseif k == "detail" then
			local entries:table = Entries();
			local text:string = DistrictAdvice_Line( entries, true );
			local best:table = {};
			for _, e in ipairs( entries ) do
				if ( e.total or 0 ) > 0 then table.insert( best, e.name .. ": " .. DistrictAdvice_BestSpot( e ) ); end
			end
			if #best > 0 then text = text .. ". " .. Join( best, ". " ); end
			text = text .. ". " .. SRKey( "Tab" ) .. " opens production";
			cache[k] = text;
			return text;
		end
	end } );
	return item;
end

-- ---------------------------------------------------------------------------
-- 8. Citizens
-- ---------------------------------------------------------------------------
local function CitizensItem( d:table )
	local c:table = d.citizens;
	local text:string = Plural( c.total, "citizen", "citizens" ) .. ": " .. c.working .. " working " ..
		( c.working == 1 and "tile" or "tiles" ) .. ", " .. Plural( c.specialists, "specialist", "specialists" );
	local detail:table = {};
	local by:table = {};
	for _, s in ipairs( c.byDistrict ) do
		if s.count > 0 then table.insert( by, s.name .. " " .. s.count ); end
	end
	if #by > 0 then
		table.insert( detail, "Specialists: " .. Join( by ) );
	else
		table.insert( detail, "No specialists" );
	end
	if c.favored ~= nil and #c.favored > 0 then table.insert( detail, "Citizens favor " .. Join( c.favored ) ); end
	if d.manage ~= nil then
		table.insert( detail, "The Focus, Tiles and Specialists items below let you change this" );
	end
	return { key = "citizens", text = text, detail = Join( detail, ". " ) };
end

-- ---------------------------------------------------------------------------
-- 9. Religion
-- ---------------------------------------------------------------------------
local function ReligionItem( d:table )
	local r:table = d.religion;
	local text:string;
	local detail:table = {};
	local rows:table = r.rows;		-- { { name, followers, pressure, own } } from GetReligionsInCity, nil: use the older fields
	local pantheonText:string = ( r.pantheon ~= nil and r.pantheon ~= "" ) and ( ", pantheon " .. r.pantheon ) or "";
	local total:number = r.citizens or d.population;
	if rows ~= nil then
		if r.majority ~= nil then
			text = "Religion: " .. r.majority.name .. " majority, " .. r.majority.followers .. " of " .. Plural( total, "citizen", "citizens" );
		elseif #rows > 0 then
			local parts:table = {};
			for _, o in ipairs( rows ) do table.insert( parts, o.name .. " " .. o.followers ); end
			text = "Religion: no majority. " .. Join( parts ) .. ", of " .. Plural( total, "citizen", "citizens" );
		else
			text = "Religion: none" .. pantheonText;
		end
		if r.majority == nil and #rows > 0 and pantheonText ~= "" then text = text .. pantheonText; end
		if r.majority ~= nil and #rows > 1 then
			local parts:table = {};
			for _, o in ipairs( rows ) do
				if o.name ~= r.majority.name then table.insert( parts, o.name .. " " .. o.followers ); end
			end
			if #parts > 0 then text = text .. ", others " .. Join( parts ); end
		end
		if r.nextName ~= nil and r.nextTurns ~= nil and r.nextTurns > 0 and ( r.majority == nil or r.nextName ~= r.majority.name ) then
			text = text .. ", turns to " .. r.nextName .. " in " .. Turns( r.nextTurns );
		end
		if r.holyCityOf ~= nil then text = text .. ", holy city of " .. r.holyCityOf; end
		local pressure:table = {};
		for _, o in ipairs( rows ) do
			if o.pressure ~= nil and o.pressure ~= 0 then table.insert( pressure, o.name .. " " .. Num( o.pressure ) ); end
		end
		if #pressure > 0 then table.insert( detail, "Pressure per turn: " .. Join( pressure ) ); end
	elseif r.majorityName ~= nil then
		text = "Religion: " .. r.majorityName .. ", " .. Plural( r.majorityFollowers, "follower", "followers" );
	elseif r.pantheon ~= nil and r.pantheon ~= "" then
		text = "Religion: pantheon " .. r.pantheon .. ", no majority religion";
	else
		text = "Religion: none";
	end
	if r.majorityName ~= nil and #r.beliefs > 0 then table.insert( detail, r.majorityName .. " beliefs: " .. Join( r.beliefs ) ); end
	if r.pantheon ~= nil and r.pantheon ~= "" then table.insert( detail, "Pantheon: " .. r.pantheon ); end
	if rows == nil then
		local others:table = {};
		for _, o in ipairs( r.others ) do table.insert( others, o.name .. " " .. o.followers ); end
		if #others > 0 then table.insert( detail, "Other religions: " .. Join( others ) ); end
	end
	if #detail == 0 then table.insert( detail, "No religion has followers here" ); end
	return { key = "religion", text = text, detail = Join( detail, ". " ) };
end

-- ---------------------------------------------------------------------------
-- 10. Great works and trading posts (only when present)
-- ---------------------------------------------------------------------------
local function GreatWorksItem( d:table )
	local g:table = d.greatWorks;
	if g == nil or g.slots <= 0 then return nil; end
	local text:string = "Great works: " .. g.filled .. " of " .. Plural( g.slots, "slot", "slots" );
	if #g.names > 0 then text = text .. ", " .. ShortList( g.names, 3 ); end
	local detail:string = text;
	if #g.names > 3 then detail = "Great works: " .. g.filled .. " of " .. Plural( g.slots, "slot", "slots" ) .. ", " .. Join( g.names ); end
	return { key = "greatworks", text = text, detail = detail };
end

-- Resources on the city's tiles (G1): d.resources = { improved = { {name, count, improvement} }, needs = { {name, count, need, improvement} },
-- possible = { {name, count, improvement} } } (ResourceTech_CityResources), nil or all empty: no item.
local function ResourcesItem( d:table )
	local r:table = d.resources;
	if r == nil then return nil; end
	local improved:table, notImproved:table = {}, {};
	for _, e in ipairs( r.improved or {} ) do
		table.insert( improved, ( e.count > 1 and ( e.count .. " " ) or "" ) .. e.name .. " (" .. e.improvement .. ")" );
	end
	for _, e in ipairs( r.needs or {} ) do
		table.insert( notImproved, ( e.count > 1 and ( e.count .. " " ) or "" ) .. e.name .. ", needs " .. e.need );
	end
	for _, e in ipairs( r.possible or {} ) do
		table.insert( notImproved, ( e.count > 1 and ( e.count .. " " ) or "" ) .. e.name .. ", a builder can make a " .. string.lower( e.improvement ) .. " now" );
	end
	if #improved == 0 and #notImproved == 0 then return nil; end
	local text:string = "Resources. Improved: " .. ( #improved > 0 and Join( improved ) or "none" );
	if #notImproved > 0 then text = text .. ". Not improved: " .. Join( notImproved, "; " ); end
	return { key = "resources", text = text,
		detail = "Resource tiles inside the city's borders. A tile that needs a tech or civic can be improved once you have researched it" };
end

local function TradingPostsItem( d:table )
	local t:table = d.tradingPosts;
	if t == nil or #t == 0 then return nil; end
	local text:string = "Trading posts: " .. ShortList( t, 4 );
	return { key = "tradingposts", text = text, detail = "Trading posts of " .. Join( t ) .. ". A trade route to this city adds a post for its owner." };
end

-- ---------------------------------------------------------------------------
-- 11. City management: focus, tiles, specialists (items of the report; Enter opens a sub-list in InGameAccess)
--	d.manage (CityManage_Gather): focus = { { key, name, state = "normal"|"favored"|"ignored" } },
--	tiles = { { key, plotIndex, relative, desc, count, max, locked } } (worked first),
--	districts = { { key, plotIndex, name, count, max, perSlot, locked } }, buy = { { key, plotIndex, relative, desc, cost } },
--	gold = the player's gold.
-- ---------------------------------------------------------------------------
local function FocusItem( d:table )
	local m:table = d.manage;
	if m == nil or m.focus == nil or #m.focus == 0 then return nil; end
	local favored:table, ignored:table = {}, {};
	for _, f in ipairs( m.focus ) do
		if f.state == "favored" then table.insert( favored, string.lower( f.name ) ); end
		if f.state == "ignored" then table.insert( ignored, string.lower( f.name ) ); end
	end
	local text:string = "Focus: " .. ( #favored > 0 and Join( favored, " and " ) or "none" );
	if #ignored > 0 then text = text .. ", ignoring " .. Join( ignored, " and " ); end
	return { key = "focus", manage = "focus", text = text .. ". " .. SRKey( "Enter" ) .. " to change",
		detail = "Favored yields make the citizens prefer tiles with that yield, ignored yields make them avoid it. " .. SRKey( "Enter" ) .. " opens the list" };
end

local function TilesItem( d:table )
	local m:table = d.manage;
	if m == nil or m.tiles == nil then return nil; end
	local c:table = d.citizens;
	local text:string = "Tiles: " .. c.working .. " of " .. Plural( c.total, "citizen", "citizens" ) .. " on tiles";
	local detail:string = text .. ". " .. Plural( #m.tiles, "workable tile", "workable tiles" );
	if m.buy ~= nil and #m.buy > 0 then detail = detail .. ", " .. Plural( #m.buy, "tile", "tiles" ) .. " to buy"; end
	return { key = "tiles", manage = "tiles", text = text .. ". " .. SRKey( "Enter" ) .. " to manage", detail = detail .. ". " .. SRKey( "Enter" ) .. " opens the list" };
end

local function SpecialistsItem( d:table )
	local m:table = d.manage;
	if m == nil or m.districts == nil or #m.districts == 0 then return nil; end
	local filled:number, slots:number = 0, 0;
	for _, dist in ipairs( m.districts ) do filled = filled + dist.count; slots = slots + dist.max; end
	local where:string = ( #m.districts == 1 ) and m.districts[1].name or Plural( #m.districts, "district", "districts" );
	return { key = "specialists", manage = "specialists",
		text = "Specialists: " .. filled .. " of " .. Plural( slots, "slot", "slots" ) .. " in " .. where .. ". " .. SRKey( "Enter" ) .. " to manage",
		detail = "Specialists work in districts instead of on tiles. " .. SRKey( "Enter" ) .. " opens the list" };
end

-- The city's totals after a change: "Food plus 5, production 13"
function CityManage_Totals( d:table )
	return "Food " .. Signed( d.foodSurplus ) .. ", production " .. Num( d.yields.production.value );
end

-- "Locked" / "Worked, not locked" / "Not worked" for a tile record
function CityManage_TileState( t:table )
	if t.count ~= nil and t.count > 0 then return t.locked and "Locked" or "Worked, not locked"; end
	return "Not worked";
end

-- Up/Down line of a tile: "2 tiles north-east, Grassland Farm, 3 Food 1 Production, worked, locked"
function CityManage_TileText( t:table )
	local parts:table = {};
	if t.relative ~= nil then table.insert( parts, t.relative ); end
	if t.desc ~= nil and t.desc ~= "" then table.insert( parts, t.desc ); end
	if t.cost ~= nil then
		table.insert( parts, "can buy, " .. t.cost .. " gold" );
	elseif t.count ~= nil and t.count > 0 then
		table.insert( parts, t.locked and "worked, locked" or "worked" );
	else
		table.insert( parts, "not worked" );
	end
	return Join( parts );
end

function CityManage_TileItems( m:table )
	local items:table = {};
	for _, t in ipairs( m.tiles or {} ) do
		table.insert( items, { key = t.key, text = CityManage_TileText( t ), tile = t } );
	end
	for _, t in ipairs( m.buy or {} ) do
		local text:string = CityManage_TileText( t );
		if m.gold ~= nil and t.cost > m.gold then text = text .. ", need " .. ( t.cost - m.gold ) .. " more"; end
		table.insert( items, { key = t.key, text = text, tile = t } );
	end
	return items;
end

-- "Campus, 1 of 2 specialists, +2 science each"
function CityManage_DistrictText( dist:table )
	local text:string = dist.name .. ", " .. dist.count .. " of " .. dist.max .. ( dist.max == 1 and " specialist" or " specialists" );
	if dist.perSlot ~= nil and dist.perSlot ~= "" then text = text .. ", " .. dist.perSlot .. " each"; end
	return text;
end

function CityManage_DistrictItems( m:table )
	local items:table = {};
	for _, dist in ipairs( m.districts or {} ) do
		table.insert( items, { key = dist.key, text = CityManage_DistrictText( dist ), district = dist } );
	end
	return items;
end

-- Two items per yield: "Food focus, off" (Enter toggles favored) and "Ignore food, off" (Enter toggles ignored)
function CityManage_FocusItems( m:table )
	local items:table = {};
	for _, f in ipairs( m.focus or {} ) do
		table.insert( items, { key = "favor_" .. f.key, text = f.name .. " focus, " .. ( f.state == "favored" and "on" or "off" ),
			yield = f, ignore = false, detail = "Citizens prefer tiles with " .. string.lower( f.name ) } );
	end
	for _, f in ipairs( m.focus or {} ) do
		table.insert( items, { key = "ignore_" .. f.key, text = "Ignore " .. string.lower( f.name ) .. ", " .. ( f.state == "ignored" and "on" or "off" ),
			yield = f, ignore = true, detail = "Citizens avoid tiles with " .. string.lower( f.name ) } );
	end
	return items;
end

function CityReport_BuildItems( d:table )
	local items:table = {};
	local function Add( item:table )
		if item ~= nil then table.insert( items, item ); end
	end
	local function Guard( f )
		local ok:boolean, err = pcall( f );
		if not ok then print( "CityReportData error: " .. tostring( err ) ); end
	end
	Guard( function() Add( YieldsItem( d ) ); end );
	Guard( function() Add( GrowthItem( d ) ); end );
	Guard( function() Add( AmenitiesItem( d ) ); end );
	Guard( function() Add( LoyaltyItem( d ) ); end );
	Guard( function() Add( PowerItem( d ) ); end );
	Guard( function() Add( ReligionItem( d ) ); end );
	Guard( function() Add( DefenseItem( d ) ); end );
	Guard( function() Add( ProductionItem( d ) ); end );
	Guard( function() Add( DistrictsItem( d ) ); end );
	Guard( function() Add( DistrictSpotsItem( d ) ); end );
	Guard( function() Add( CitizensItem( d ) ); end );
	Guard( function() Add( FocusItem( d ) ); end );
	Guard( function() Add( TilesItem( d ) ); end );
	Guard( function() Add( SpecialistsItem( d ) ); end );
	Guard( function() Add( ResourcesItem( d ) ); end );
	Guard( function() Add( GreatWorksItem( d ) ); end );
	Guard( function() Add( TradingPostsItem( d ) ); end );
	return items;
end
