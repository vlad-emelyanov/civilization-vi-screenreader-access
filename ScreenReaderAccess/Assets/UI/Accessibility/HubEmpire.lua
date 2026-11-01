-- ===========================================================================
--	HubEmpire: the empire overview list (Control+Shift+I, action KeyNavEmpire).
--	Part of the InGameAccess hub (see docs/features.md, Architecture): included by UI/Additions/InGameAccess.lua.
--
--	Groups (PageUp / PageDown): Needs attention, Cities, Units, Victories, Standing. Everything is read once when the list
--	opens (the cache m_data, no engine call per key) and nothing changes in the game. Each group is gathered in a pcall:
--	a failed group logs and is left out. Wording: EmpireText.lua. The victory numbers follow what the World Rankings screen
--	(PartialScreens/WorldRankings.lua, Expansion2 replacement) computes and shows; unmet civilizations stay unnamed.
-- ===========================================================================
include( "ScreenReader" );
include( "KeyNavList" );
include( "EmpireText" );

HubEmpire = {};

local m_data:table = nil;		-- { attention = {...}, cities = {...}, units = {...}, victories = {...}, standing = {...}, needOrders }
local m_list:table;

local function LocalPlayer()
	return Players[ Game.GetLocalPlayer() ];
end

local function Guard( name:string, f )
	local ok:boolean, result = xpcall( f, KeyNavErrorHandler );
	if not ok then
		print( "HubEmpire " .. name .. " error: " .. tostring( result ) );
		return nil;
	end
	return result;
end

-- ---------------------------------------------------------------------------
--	Names (the World Rankings rule: a civilization we have not met is "Unmet civilization")
-- ---------------------------------------------------------------------------
local function KnownCiv( id:number )
	local config:table = PlayerConfigurations[ id ];
	if id == Game.GetLocalPlayer() or ( config ~= nil and config:IsHuman() ) then return true; end
	local player:table = LocalPlayer();
	return player ~= nil and player:GetDiplomacy():HasMet( id );
end

local function CivName( id:number )
	if id == Game.GetLocalPlayer() then return "you"; end
	if KnownCiv( id ) then return PlotDescription_GetCivName( id ); end
	local text:string = Locale.Lookup( "LOC_WORLD_RANKING_UNMET_PLAYER" );
	if text == nil or text == "" or string.find( text, "LOC_", 1, true ) == 1 then text = "Unmet civilization"; end
	return CleanTextForSpeech( text );
end

-- Civilizations at war with us that we have met: { id, name } (majors); the number of city-states at war.
local function WarEnemies()
	local enemies:table, cityStates:number = {}, 0;
	local player:table = LocalPlayer();
	if player == nil then return enemies, cityStates; end
	local diplomacy:table = player:GetDiplomacy();
	for _, id in ipairs( PlayerManager.GetAliveMajorIDs() ) do
		if id ~= Game.GetLocalPlayer() and diplomacy:HasMet( id ) and diplomacy:IsAtWarWith( id ) then
			table.insert( enemies, { id = id, name = PlotDescription_GetCivName( id ) } );
		end
	end
	for _, id in ipairs( PlayerManager.GetAliveMinorIDs() ) do
		if diplomacy:HasMet( id ) and diplomacy:IsAtWarWith( id ) then cityStates = cityStates + 1; end
	end
	return enemies, cityStates;
end

-- ---------------------------------------------------------------------------
--	Cities and what needs attention
-- ---------------------------------------------------------------------------
-- No soldier in the city, no walls, and a soldier of a civilization at war with us is visible within HOSTILE_NEAR_RANGE tiles.
local HOSTILE_NEAR_RANGE:number = 6;
local function Undefended( city:table, facts:table, enemies:table )
	if #enemies == 0 or ( facts.wallMax or 0 ) > 0 then return nil; end
	local plot:table = Map.GetPlot( city:GetX(), city:GetY() );
	if plot == nil then return nil; end
	for _, unit in ipairs( Units.GetUnitsInPlot( plot ) ) do
		if unit:GetOwner() == city:GetOwner() and ( unit:GetCombat() > 0 or unit:GetRangedCombat() > 0 or unit:GetBombardCombat() > 0 ) then return nil; end
	end
	local vis:table = PlayersVisibility[ Game.GetLocalPlayer() ];
	if vis == nil then return nil; end
	for _, enemy in ipairs( enemies ) do
		for _, unit in Players[ enemy.id ]:GetUnits():Members() do
			if ( unit:GetCombat() > 0 or unit:GetRangedCombat() > 0 or unit:GetBombardCombat() > 0 )
					and Map.GetPlotDistance( city:GetX(), city:GetY(), unit:GetX(), unit:GetY() ) <= HOSTILE_NEAR_RANGE then
				local there:table = Map.GetPlot( unit:GetX(), unit:GetY() );
				if there ~= nil and vis:IsVisible( there:GetIndex() ) then return { enemy = enemy.name }; end
			end
		end
	end
	return nil;
end

-- Cities in danger now (HubEnemies.ScanCityDanger): city id -> { count, civ }
local function DangerByCity()
	local found:table = {};
	if HubEnemies == nil or HubEnemies.ScanCityDanger == nil then return found; end
	Guard( "danger", function()
		for _, entry in ipairs( HubEnemies.ScanCityDanger() ) do
			found[ entry.city:GetID() ] = { count = entry.count, civ = ( entry.civs ~= nil and #entry.civs == 1 ) and entry.civs[ 1 ] or nil };
		end
	end );
	return found;
end

-- Cheap facts straight from the city objects (no GetCityData): a missing call leaves its field out, so no claim is made from it.
local function Try( object, method:string )
	if object == nil or object[ method ] == nil then return nil; end
	local ok:boolean, result = pcall( function() return object[ method ]( object ); end );
	if ok then return result; end
	return nil;
end

local function CheapFacts( city:table )
	local f:table = { name = Locale.Lookup( city:GetName() ), population = city:GetPopulation(), foodSurplus = 0, occupied = false,
		turnsUntilGrowth = 0, housingMultiplier = 1, wallMax = 0, underSiege = false };
	local growth:table = city:GetGrowth();
	f.foodSurplus = Try( growth, "GetFoodSurplus" ) or 0;
	f.turnsUntilGrowth = Try( growth, "GetTurnsUntilGrowth" ) or 0;
	if f.foodSurplus < 0 then
		-- the engine reports -1 for "never grows" and for starving alike: the turns until a citizen is lost come from GetTurnsUntilStarvation
		local starve = Try( growth, "GetTurnsUntilStarvation" );
		if starve ~= nil and starve > 0 then f.turnsUntilGrowth = -starve; end
	end
	f.housing = Try( growth, "GetHousing" );
	f.housingMultiplier = Try( growth, "GetHousingGrowthModifier" ) or 1;
	f.occupied = Try( city, "IsOccupied" ) == true;
	f.amenitiesHave = Try( growth, "GetAmenities" );
	f.amenitiesNeeded = Try( growth, "GetAmenitiesNeeded" );
	local queue:table = city:GetBuildQueue();
	local hash = Try( queue, "GetCurrentProductionTypeHash" );
	if hash ~= nil and hash ~= 0 then
		local row = GameInfo.Buildings[ hash ] or GameInfo.Districts[ hash ] or GameInfo.Units[ hash ] or GameInfo.Projects[ hash ];
		if row ~= nil then f.production = Locale.Lookup( row.Name ); end
		local turns = Try( queue, "GetTurnsLeft" );
		if turns ~= nil and turns > 0 then f.productionTurns = turns; end
	end
	if f.production == "" then f.production = nil; end
	local identity = Try( city, "GetCulturalIdentity" );
	if identity ~= nil then
		f.loyalty, f.loyaltyPerTurn = Try( identity, "GetLoyalty" ), Try( identity, "GetLoyaltyPerTurn" );
		f.loyaltyLevel, f.loyaltyTopLevel = Try( identity, "GetLoyaltyLevel" ), 3;
		if IdentityConversionOutcome ~= nil and Try( identity, "GetConversionOutcome" ) == IdentityConversionOutcome.LOSING_LOYALTY then
			local turns = Try( identity, "GetTurnsToConversion" );
			if turns ~= nil and turns >= 1 then f.loyaltyTurnsToLoss = turns; end
		end
	end
	local district = CityManager.GetDistrictAt( city:GetX(), city:GetY() );
	if district ~= nil then f.wallMax = Try( district, "GetMaxDamage" ) or 0; end
	return f;
end

-- { facts, problems, owner } for each city of ours. A city whose gather fails keeps a minimal row (its name) so the count stays right.
local function GatherCities()
	local out:table = {};
	local player:table = LocalPlayer();
	if player == nil then return out; end
	local danger:table = DangerByCity();
	local enemies:table = WarEnemies();
	for _, city in player:GetCities():Members() do
		local facts = Guard( "city", function() return CheapFacts( city ); end );
		if facts == nil then
			facts = { name = Locale.Lookup( city:GetName() ), population = 0, minimal = true };
		else
			facts.danger = danger[ city:GetID() ];
			facts.undefended = Guard( "undefended", function() return Undefended( city, facts, enemies ); end );
		end
		facts.id, facts.x, facts.y = city:GetID(), city:GetX(), city:GetY();
		table.insert( out, { facts = facts, problems = EmpireText.CityProblems( facts ), owner = city:GetOwner() } );
	end
	table.sort( out, function( a, b ) return EmpireText.CityLess( a.facts, b.facts ); end );
	return out;
end

-- Cursor on the city, then the same function Control+I uses.
function HubEmpire.OpenCity( facts:table )
	HubCursor.SetCursor( facts.x, facts.y, false, nil, true );
	HubCityReport.OpenReport( nil, nil, true );
end

-- Space: the full city report data is read only now, for this one city.
local function CityDetail( entry:table )
	return function()
		local items:table = {};
		local city:table = Players[ entry.owner ]:GetCities():FindID( entry.facts.id );
		if city ~= nil and CityReport_Gather ~= nil and CityReport_BuildItems ~= nil then
			local ok:boolean, d = pcall( CityReport_Gather, city );
			if ok and d ~= nil then
				local ok2:boolean, result = pcall( CityReport_BuildItems, d );
				if ok2 then items = result; end
			end
		end
		if #items == 0 then return EmpireText.CityLine( entry.facts, #entry.problems ); end
		return EmpireText.CitySummary( entry.facts.name, items );
	end;
end

local function AttentionItems( cities:table )
	local all:table = {};
	local byCity:table = {};
	for _, entry in ipairs( cities ) do
		byCity[ entry.facts.name ] = entry;
		for _, problem in ipairs( entry.problems ) do table.insert( all, problem ); end
	end
	local items:table = {};
	for i, problem in ipairs( EmpireText.Attention( all ) ) do
		local entry:table = byCity[ problem.city ];
		table.insert( items, { key = "a:" .. i .. ":" .. problem.text, section = "Needs attention", text = problem.text,
			city = entry ~= nil and entry.facts or nil, detail = entry ~= nil and CityDetail( entry ) or nil } );
	end
	if #items == 0 then
		table.insert( items, { key = "a:none", section = "Needs attention", text = "Nothing urgent", uncounted = true } );
	end
	return items;
end

local function CityItems( cities:table )
	local items:table = {};
	for _, entry in ipairs( cities ) do
		table.insert( items, { key = "c:" .. entry.facts.id, section = "Cities", text = EmpireText.CityLine( entry.facts, #entry.problems ),
			city = entry.facts, detail = CityDetail( entry ) } );
	end
	return items;
end

-- ---------------------------------------------------------------------------
--	Units
-- ---------------------------------------------------------------------------
local function BusyState( activity:string )
	if activity == nil then return nil; end
	if string.find( activity, "moving", 1, true ) == 1 then return "moving"; end
	if activity == "needs orders" or activity == "no moves left" then return nil; end
	return activity;
end

local function GatherUnits()
	local u:table = { total = 0, needOrders = 0, needNames = {}, idle = {}, soldiers = 0, formation = 0, busy = {} };
	local player:table = LocalPlayer();
	if player == nil then return u; end
	for _, unit in player:GetUnits():Members() do
		Guard( "unit", function()
			u.total = u.total + 1;
			local name:string = Locale.Lookup( unit:GetName() );
			local activity:string = HubPlaces.UnitActivity( unit, true );
			local idle:string = HubPlaces.IdleActivity( unit );
			if idle ~= nil then u.idle[ name ] = ( u.idle[ name ] or 0 ) + 1; end
			if activity == "needs orders" then
				u.needOrders = u.needOrders + 1;
				u.needNames[ name ] = ( u.needNames[ name ] or 0 ) + 1;
			elseif idle == nil then
				local state:string = BusyState( activity );
				if state ~= nil then u.busy[ state ] = ( u.busy[ state ] or 0 ) + 1; end
			end
			if unit:GetCombat() > 0 or unit:GetRangedCombat() > 0 or unit:GetBombardCombat() > 0 then
				u.soldiers = u.soldiers + 1;
				local formation = unit:GetMilitaryFormation();
				if formation ~= nil and formation ~= MilitaryFormationTypes.STANDARD_FORMATION then u.formation = u.formation + 1; end
			end
		end );
	end
	return u;
end

local function UnitItemsFor( u:table )
	local items:table = EmpireText.UnitItems( u );
	for _, item in ipairs( items ) do
		item.section = "Units";
		item.key = "u:" .. item.key;
	end
	return items;
end

-- Enter on a unit line: the places list at Your units (J), where the units can be selected.
function HubEmpire.OpenUnits()
	HubPlaces.Open( { catName = "Your units" } );
end

-- ---------------------------------------------------------------------------
--	Victories (WorldRankings.lua: ViewOverall ordering, Gather*Data / View* numbers)
-- ---------------------------------------------------------------------------
local TIEBREAK:table = {
	VICTORY_CONQUEST = {
		function( p ) return p:GetStats():GetMilitaryStrengthWithoutTreasury(); end,
		function( p ) return p:GetStats():GetMilitaryStrengthWithoutTreasury(); end },
	VICTORY_CULTURE = {
		function( p ) return p:GetStats():GetTourism(); end,
		function( p ) return p:GetCulture():GetCultureYield(); end },
	VICTORY_RELIGIOUS = {
		function( p ) return p:GetStats():GetNumCitiesFollowingReligion(); end,
		function( p ) return p:GetReligion():GetFaithYield(); end },
	VICTORY_TECHNOLOGY = {
		function( p ) return p:GetStats():GetNumTechsResearched(); end,
		function( p ) return p:GetTechs():GetScienceYield(); end },
};

-- The alive majors the game ranks for this victory type, best first: the order of the World Rankings overview
-- (victory progress of the team, then the two tiebreakers, then score, then id). Players without progress are left out.
local function RankPlayers( victoryType:string )
	local entries:table = {};
	local tie:table = TIEBREAK[ victoryType ];
	for _, id in ipairs( PlayerManager.GetAliveMajorIDs() ) do
		local player:table = Players[ id ];
		local progress = Game.GetVictoryProgressForTeam( victoryType, player:GetTeam() );
		if progress ~= nil then
			local first:number, second:number = 0, 0;
			if tie ~= nil then
				first, second = tie[ 1 ]( player ), tie[ 2 ]( player );
			else
				first = player:GetScore();
				second = first;
			end
			table.insert( entries, { id = id, progress = progress, first = first, second = second, score = player:GetScore() } );
		end
	end
	table.sort( entries, function( a, b )
		if a.progress ~= b.progress then return a.progress > b.progress; end
		if a.first ~= b.first then return a.first > b.first; end
		if a.second ~= b.second then return a.second > b.second; end
		if a.score ~= b.score then return a.score > b.score; end
		return a.id < b.id;
	end );
	return entries;
end

local function PositionOf( entries:table, id:number )
	for i, e in ipairs( entries ) do
		if e.id == id then return i; end
	end
	return nil;
end

-- Fills the leader fields of v and returns the ranking entries { id }.
local function Ranked( v:table, victoryType:string )
	local entries:table = RankPlayers( victoryType );
	local me:number = Game.GetLocalPlayer();
	v.position = PositionOf( entries, me );
	if #entries > 0 then
		v.leaderId = entries[ 1 ].id;
		v.leaderIsYou = entries[ 1 ].id == me;
		v.leaderName = CivName( entries[ 1 ].id );
	end
	return entries;
end

-- Science: the milestones of PopulateScienceInstance. Each stage is a list of project types.
local function ScienceStages()
	if GameInfo.Projects[ "PROJECT_LAUNCH_EXOPLANET_EXPEDITION" ] ~= nil and GameInfo.Projects[ "PROJECT_LAUNCH_MARS_BASE" ] ~= nil then
		return { { "PROJECT_LAUNCH_EARTH_SATELLITE" }, { "PROJECT_LAUNCH_MOON_LANDING" }, { "PROJECT_LAUNCH_MARS_BASE" }, { "PROJECT_LAUNCH_EXOPLANET_EXPEDITION" } };
	end
	return { { "PROJECT_LAUNCH_EARTH_SATELLITE" }, { "PROJECT_LAUNCH_MOON_LANDING" },
		{ "PROJECT_LAUNCH_MARS_REACTOR", "PROJECT_LAUNCH_MARS_HABITATION", "PROJECT_LAUNCH_MARS_HYDROPONICS" } };
end

-- Is this project finished by the player? The game's own test per city: advanced projects count as complete at their full cost.
local function ProjectDone( player:table, row:table )
	if player:GetStats():GetNumProjectsAdvanced( row.Index ) > 0 then return true; end
	local any:boolean = false;
	for _, city in player:GetCities():Members() do
		local queue:table = city:GetBuildQueue();
		local cost:number = queue:GetProjectCost( row.Index );
		if cost <= 0 or queue:GetProjectProgress( row.Index ) < cost then return false; end
		any = true;
	end
	return any;
end

local function HasSpaceport( player:table )
	local info:table = GameInfo.Districts[ "DISTRICT_SPACEPORT" ];
	if info == nil then return false; end
	for _, district in player:GetDistricts():Members() do
		if district ~= nil and district:IsComplete() and district:GetType() == info.Index then return true; end
	end
	return false;
end

-- done milestones, and (for the next unfinished one) what GetNextStepForScienceProject would say
local function ScienceProgress( player:table, wantNext:boolean )
	local stages:table = ScienceStages();
	local done:number = 0;
	local nextStep:string = nil;
	local spaceport:boolean = HasSpaceport( player );
	for _, stage in ipairs( stages ) do
		local stageDone:boolean = true;
		local step:string = nil;
		for _, projectType in ipairs( stage ) do
			local row:table = GameInfo.Projects[ projectType ];
			if row ~= nil and not ProjectDone( player, row ) then
				stageDone = false;
				if wantNext and step == nil then
					local prereq:table = row.PrereqTech ~= nil and GameInfo.Technologies[ row.PrereqTech ] or nil;
					if not spaceport then
						step = Locale.Lookup( "LOC_WORLD_RANKINGS_SCIENCE_NEXT_STEP_BUILD", Locale.Lookup( GameInfo.Districts[ "DISTRICT_SPACEPORT" ].Name ) );
					elseif prereq ~= nil and not player:GetTechs():HasTech( prereq.Index ) then
						step = Locale.Lookup( "LOC_WORLD_RANKINGS_SCIENCE_NEXT_STEP_RESEARCH", Locale.Lookup( prereq.Name ) );
					else
						step = Locale.Lookup( row.Name );
					end
				end
			end
		end
		if stageDone then
			done = done + 1;
		elseif nextStep == nil then
			nextStep = step;
		end
	end
	return done, #stages, nextStep;
end

local function CultureNumbers( id:number )
	local player:table = Players[ id ];
	local visiting:number = player:GetCulture():GetTouristsTo();
	local required:number = 0;
	for _, otherId in ipairs( PlayerManager.GetAliveMajorIDs() ) do
		local other:table = Players[ otherId ];
		if otherId ~= id and other:GetTeam() ~= player:GetTeam() then
			local stay:number = other:GetCulture():GetStaycationers();
			if stay >= required then required = stay + 1; end
		end
	end
	return visiting, required;
end

-- original capitals held by the player: its own and the captured ones; the number of civilizations that have a capital
local function CapitalNumbers( id:number )
	local held:number = 0;
	for _, city in Players[ id ]:GetCities():Members() do
		local original:number = city:GetOriginalOwner();
		if city:IsOriginalCapital() and Players[ original ] ~= nil and Players[ original ]:IsMajor() then held = held + 1; end
	end
	return held;
end

-- Civilizations with an original capital in play: the alive majors that have one, plus the original owners of every original
-- capital an alive major holds (a dead civ's capital still counts), so held never exceeds the total.
local function CapitalTotal()
	local owners:table = {};
	for _, id in ipairs( PlayerManager.GetAliveMajorIDs() ) do
		local cities:table = Players[ id ]:GetCities();
		if cities:GetCapitalCity() ~= nil then owners[ id ] = true; end
		for _, city in cities:Members() do
			local original:number = city:GetOriginalOwner();
			if city:IsOriginalCapital() and Players[ original ] ~= nil and Players[ original ]:IsMajor() then owners[ original ] = true; end
		end
	end
	local total:number = 0;
	for _ in pairs( owners ) do total = total + 1; end
	return total;
end

-- Civilizations whose cities mostly follow the religion this player founded (-1: none founded)
local function ConvertedNumbers( id:number )
	local religion:table = Players[ id ]:GetReligion();
	if religion == nil then return -1, 0; end
	local created:number = religion:GetReligionTypeCreated();
	local total:number = #PlayerManager.GetAliveMajorIDs();
	if created == nil or created == -1 then return -1, total; end
	local count:number = 0;
	for _, otherId in ipairs( PlayerManager.GetAliveMajorIDs() ) do
		local other:table = Players[ otherId ]:GetReligion();
		if other ~= nil and other:GetReligionInMajorityOfCities() == created then count = count + 1; end
	end
	return count, total;
end

local function VictoryItem( v:table, entries:table, perPlayerText )
	local ranking:table = {};
	for _, e in ipairs( entries ) do
		table.insert( ranking, { name = e.id == Game.GetLocalPlayer() and "You" or CivName( e.id ), text = perPlayerText ~= nil and perPlayerText( e.id ) or nil } );
	end
	return { key = "v:" .. v.kind .. ( v.name or "" ), section = "Victories", text = EmpireText.VictoryLine( v ), detail = EmpireText.Ranking( ranking ) };
end

local function GatherVictories()
	local items:table = {};
	local me:number = Game.GetLocalPlayer();
	local player:table = LocalPlayer();
	local function Add( f )
		local item = Guard( "victory", f );
		if item ~= nil then table.insert( items, item ); end
	end

	if Game.IsVictoryEnabled( "VICTORY_TECHNOLOGY" ) then Add( function()
		local v:table = { kind = "science" };
		local entries:table = Ranked( v, "VICTORY_TECHNOLOGY" );
		v.done, v.total, v.next = ScienceProgress( player, true );
		if v.leaderId ~= nil and not v.leaderIsYou then v.leaderDone = ScienceProgress( Players[ v.leaderId ], false ); end
		if v.done >= v.total then
			local stats:table = player:GetStats();
			if stats.GetScienceVictoryPointsTotalNeeded ~= nil then
				v.lightTotal = stats:GetScienceVictoryPointsTotalNeeded();
				v.lightYears = math.min( stats:GetScienceVictoryPoints(), v.lightTotal );
			end
		end
		return VictoryItem( v, entries, function( id ) local done, total = ScienceProgress( Players[ id ], false ); return done .. " of " .. total; end );
	end ); end

	if Game.IsVictoryEnabled( "VICTORY_CULTURE" ) then Add( function()
		local v:table = { kind = "culture" };
		local entries:table = Ranked( v, "VICTORY_CULTURE" );
		v.visiting, v.required = CultureNumbers( me );
		if v.leaderId ~= nil and not v.leaderIsYou then v.leaderVisiting, v.leaderRequired = CultureNumbers( v.leaderId ); end
		return VictoryItem( v, entries, function( id ) local a, b = CultureNumbers( id ); return a .. " of " .. b .. " foreign tourists"; end );
	end ); end

	if Game.IsVictoryEnabled( "VICTORY_CONQUEST" ) then Add( function()
		local v:table = { kind = "domination" };
		local entries:table = Ranked( v, "VICTORY_CONQUEST" );
		v.held, v.total = CapitalNumbers( me ), CapitalTotal();
		if v.leaderId ~= nil and not v.leaderIsYou then v.leaderHeld = CapitalNumbers( v.leaderId ); end
		return VictoryItem( v, entries, function( id ) return "holds " .. CapitalNumbers( id ) .. " capitals"; end );
	end ); end

	if Game.IsVictoryEnabled( "VICTORY_RELIGIOUS" ) then Add( function()
		local v:table = { kind = "religion" };
		local entries:table = Ranked( v, "VICTORY_RELIGIOUS" );
		local converted:number, total:number = ConvertedNumbers( me );
		v.hasReligion, v.converted, v.total = converted >= 0, math.max( converted, 0 ), total;
		if v.leaderId ~= nil and not v.leaderIsYou then v.leaderConverted = math.max( ConvertedNumbers( v.leaderId ), 0 ); end
		return VictoryItem( v, entries, function( id ) local c = ConvertedNumbers( id ); return math.max( c, 0 ) .. " of " .. total .. " civs"; end );
	end ); end

	-- modded and expansion victory types (Gathering Storm: diplomatic), as the overview adds them
	for row in GameInfo.Victories() do
		local victoryType:string = row.VictoryType;
		if victoryType ~= "VICTORY_DEFAULT" and victoryType ~= "VICTORY_SCORE" and TIEBREAK[ victoryType ] == nil and Game.IsVictoryEnabled( victoryType ) then
			Add( function()
				local v:table = { kind = ( victoryType == "VICTORY_DIPLOMATIC" ) and "diplomatic" or "other", name = CleanTextForSpeech( Locale.Lookup( row.Name ) ) };
				local entries:table = Ranked( v, victoryType );
				if v.kind == "diplomatic" then
					v.required = GlobalParameters.DIPLOMATIC_VICTORY_POINTS_REQUIRED;
					v.points = player:GetStats():GetDiplomaticVictoryPoints();
					if v.leaderId ~= nil and not v.leaderIsYou then v.leaderPoints = Players[ v.leaderId ]:GetStats():GetDiplomaticVictoryPoints(); end
					return VictoryItem( v, entries, function( id ) return Players[ id ]:GetStats():GetDiplomaticVictoryPoints() .. " points"; end );
				end
				return VictoryItem( v, entries, nil );
			end );
		end
	end

	if Game.IsVictoryEnabled( "VICTORY_SCORE" ) then Add( function()
		local scores:table = {};
		for _, id in ipairs( PlayerManager.GetAliveMajorIDs() ) do table.insert( scores, { id = id, score = Players[ id ]:GetScore() } ); end
		table.sort( scores, function( a, b )
			if a.score ~= b.score then return a.score > b.score; end
			return a.id < b.id;
		end );
		local v:table = { kind = "score", score = player:GetScore(), count = #scores, endTurn = Game.GetMaxGameTurns() };
		v.position = PositionOf( scores, me ) or #scores;
		if #scores > 0 then
			v.leaderIsYou = scores[ 1 ].id == me;
			v.leaderName = CivName( scores[ 1 ].id );
			v.leaderScore = scores[ 1 ].score;
		end
		return VictoryItem( v, scores, function( id ) return Players[ id ]:GetScore() .. " points"; end );
	end ); end
	return items;
end

-- ---------------------------------------------------------------------------
--	Standing (the diplomacy ribbon's military numbers, wars, the era countdown)
-- ---------------------------------------------------------------------------
local function GatherStanding()
	local player:table = LocalPlayer();
	local s:table = { met = 0, atWar = {}, military = {} };
	local enemies:table, cityStates:number = WarEnemies();
	s.cityStatesAtWar = cityStates;
	local warIds:table = {};
	for _, e in ipairs( enemies ) do table.insert( s.atWar, e.name ); warIds[ e.id ] = true; end
	local diplomacy:table = player:GetDiplomacy();
	local mine = HubMenus.StandingValues( Game.GetLocalPlayer() ).military;
	for _, id in ipairs( PlayerManager.GetAliveMajorIDs() ) do
		if id ~= Game.GetLocalPlayer() and diplomacy:HasMet( id ) then
			s.met = s.met + 1;
			local military = HubMenus.StandingValues( id ).military;
			if military ~= nil then table.insert( s.military, { name = PlotDescription_GetCivName( id ), value = military, atWar = warIds[ id ] == true } ); end
		end
	end
	table.sort( s.military, function( a, b ) return a.value > b.value; end );
	s.myMilitary = mine;
	Guard( "era", function()
		local eras:table = Game.GetEras and Game.GetEras() or nil;
		if eras ~= nil and eras.GetNextEraCountdown ~= nil then
			local countdown:number = eras:GetNextEraCountdown() + 1;		-- 0 is the last turn (ActionPanel_Expansion1)
			if countdown > 0 then s.eraTurns = countdown; end
		end
	end );
	local items:table = EmpireText.StandingItems( s );
	for _, item in ipairs( items ) do
		item.section = "Standing";
		item.key = "s:" .. item.key;
	end
	return items;
end

-- ---------------------------------------------------------------------------
--	The list
-- ---------------------------------------------------------------------------
function HubEmpire.Gather()
	local data:table = { items = {}, attention = 0, cities = 0, needOrders = 0 };
	local cities:table = Guard( "cities", GatherCities ) or {};
	local function Append( list )
		if list == nil then return; end
		for _, item in ipairs( list ) do table.insert( data.items, item ); end
	end
	local attention:table = Guard( "attention", function() return AttentionItems( cities ); end );
	Append( attention );
	for _, item in ipairs( attention or {} ) do
		if not item.uncounted then data.attention = data.attention + 1; end
	end
	Append( Guard( "city list", function() return CityItems( cities ); end ) );
	data.cities = #cities;
	local units:table = Guard( "units", GatherUnits );
	if units ~= nil then
		data.needOrders = units.needOrders;
		Append( Guard( "unit list", function() return UnitItemsFor( units ); end ) );
	end
	Append( Guard( "victories", GatherVictories ) );
	Append( Guard( "standing", GatherStanding ) );
	return data;
end

local function Activate( item:table )
	if item.city ~= nil then
		HubEmpire.OpenCity( item.city );
	elseif string.sub( item.key, 1, 2 ) == "u:" and not item.noAction then
		HubEmpire.OpenUnits();
	else
		OutputMessageToScreenReader( item.detail ~= nil and ( type( item.detail ) == "function" and item.detail() or item.detail ) or item.text );
	end
end

m_list = KeyNavList_Create{
	build		= function() return m_data ~= nil and m_data.items or {}; end,
	isActive	= function() return HubCore.IsModeOpen( "empire" ); end,
	sectionCounts = true,
	onActivate	= Activate,
	onClose		= function() HubCore.CloseMode( true, false ); end,
};

-- Always opens (the controller ring); the keyboard toggle below closes an open list instead.
function HubEmpire.Open()
	if not HubCore.IsLocalPlayerActive() then return; end
	if not HubTargets.CanOpenMode() then return; end
	m_data = HubEmpire.Gather();
	if #m_data.items == 0 then
		m_data = nil;
		OutputMessageToScreenReader( "The empire overview is not available" );
		return;
	end
	local mine:table = m_data;
	-- OpenMode closes an open empire list first, which runs the old onClose: only the list that is closing may clear the cache
	HubCore.OpenMode( "empire", m_list, EmpireText.OpenLine( mine.attention, mine.cities, mine.needOrders ), function()
		if m_data == mine then m_data = nil; end
	end );
end

function HubEmpire.Toggle()
	if not HubCore.IsLocalPlayerActive() then return; end
	if HubCore.IsModeOpen( "empire" ) then HubCore.CloseMode( true, false ); return; end
	HubEmpire.Open();
end
