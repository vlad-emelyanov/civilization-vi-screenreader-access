-- ===========================================================================
--	ResourceTech: which tech / civic unlocks the improvement of a resource, for the tile text, the builder browser,
--	the tech and civics trees and the city report (docs/beginner-guide-gaps.md, G1).
--
--	The rule is the game's own (ToolTips/PlotToolTip.lua): Improvement_ValidResources names the improvements of a resource,
--	the improvement's PrereqTech / PrereqCivic says what is missing. For a listed resource the engine ignores the terrain and
--	feature lists, only the domain (land / sea) matters. Improvements of other civs (Improvements.TraitType the player
--	does not have) are skipped, resources the player cannot see are never named.
--
--	ResourceTech_Info( plot )                 -> nil | { resource, status, improvement, need, improvedWith }
--	    status: "needs" (no improvement possible yet: need = { kind "tech"|"civic", type, name, id }, improvement = name),
--	            "possible" (improvement = name), "improved" (improvedWith = name), "other" (another improvement or a
--	            district / city is on the plot: say nothing)
--	ResourceTech_Short( plot )                -> "needs Bronze Working" | "pasture possible" | nil     (cursor read)
--	ResourceTech_Full( plot )                 -> "Iron: Mine needs Bronze Working, 6 turns of research" | nil   (I key)
--	ResourceTech_NeedText( need )             -> "Bronze Working"
--	ResourceTech_Turns( need )                -> turns of research along the path (missing prerequisites summed), or nil
--	ResourceTech_Scan( kind )                 -> groups for the trees: { { kind, type, name, total, turns, missing = {names},
--	                                             resources = { { name, count, city } } } } sorted cheapest first
--	ResourceTech_NodePhrase( groups, type )   -> "improves 2 Horses and 1 Sheep near your cities" | nil
--	ResourceTech_GroupText( group )           -> "Bronze Working, 6 turns: Iron near Rome, 2 Horses near Antium"
--	ResourceTech_CityResources( city )        -> { improved = { {name, count, improvement} }, needs = { {name, count, need, improvement} },
--	                                             possible = { {name, count, improvement} } }
--	ResourceTech_PathTurns( kind, typeName, has, turnsOf ) -> sum of turnsOf(type) over the missing path (pure, tested)
--	ResourceTech_ResetCache()                 -> forget the static GameInfo indexes (tests)
-- ===========================================================================

local SCAN_RANGE:number = 3;		-- unowned tiles this close to one of my cities count for the trees

-- ===========================================================================
--	Static indexes from GameInfo
-- ===========================================================================
local m_byResource:table = nil;			-- resource type -> { improvement row, ... } (in table order)
local m_buildable:table = nil;			-- improvement type -> true when some unit can build it
local m_techPrereqs:table = nil;		-- tech type -> { prereq tech type, ... }
local m_civicPrereqs:table = nil;

function ResourceTech_ResetCache()
	m_byResource, m_buildable, m_techPrereqs, m_civicPrereqs = nil, nil, nil, nil;
end

local function _Index()
	if m_byResource ~= nil then return; end
	m_byResource, m_buildable = {}, {};
	if GameInfo.Improvement_ValidBuildUnits ~= nil then
		for row in GameInfo.Improvement_ValidBuildUnits() do m_buildable[ row.ImprovementType ] = true; end
	end
	for row in GameInfo.Improvement_ValidResources() do
		local improvement:table = GameInfo.Improvements[ row.ImprovementType ];
		if improvement ~= nil and ( m_buildable[ row.ImprovementType ] or next( m_buildable ) == nil ) then
			m_byResource[ row.ResourceType ] = m_byResource[ row.ResourceType ] or {};
			table.insert( m_byResource[ row.ResourceType ], improvement );
		end
	end
end

local function _PrereqMap( kind:string )
	if kind == "tech" then
		if m_techPrereqs == nil then
			m_techPrereqs = {};
			if GameInfo.TechnologyPrereqs ~= nil then
				for row in GameInfo.TechnologyPrereqs() do
					m_techPrereqs[ row.Technology ] = m_techPrereqs[ row.Technology ] or {};
					table.insert( m_techPrereqs[ row.Technology ], row.PrereqTech );
				end
			end
		end
		return m_techPrereqs;
	end
	if m_civicPrereqs == nil then
		m_civicPrereqs = {};
		if GameInfo.CivicPrereqs ~= nil then
			for row in GameInfo.CivicPrereqs() do
				m_civicPrereqs[ row.Civic ] = m_civicPrereqs[ row.Civic ] or {};
				table.insert( m_civicPrereqs[ row.Civic ], row.PrereqCivic );
			end
		end
	end
	return m_civicPrereqs;
end

-- ===========================================================================
--	Player state
-- ===========================================================================
local function _Player()
	local id:number = Game.GetLocalPlayer();
	if id == nil or id < 0 then return nil; end
	return Players[ id ], id;
end

local function _HasTech( player:table, row:table )
	local techs:table = player:GetTechs();
	return techs ~= nil and techs:HasTech( row.Index ) == true;
end

local function _HasCivic( player:table, row:table )
	local culture:table = player:GetCulture();
	return culture ~= nil and culture:HasCivic( row.Index ) == true;
end

-- True when the player's civ / leader may use this improvement (unique improvements carry a TraitType).
local function _MayUse( improvement:table, playerId:number )
	local trait:string = improvement.TraitType;
	if trait == nil or trait == "" then return true; end
	local config:table = PlayerConfigurations[ playerId ];
	if config == nil or config.GetCivilizationTypeName == nil then return false; end
	local civ:string, leader:string = config:GetCivilizationTypeName(), config:GetLeaderTypeName();
	if GameInfo.CivilizationTraits ~= nil then
		for row in GameInfo.CivilizationTraits() do
			if row.TraitType == trait and row.CivilizationType == civ then return true; end
		end
	end
	if GameInfo.LeaderTraits ~= nil then
		for row in GameInfo.LeaderTraits() do
			if row.TraitType == trait and row.LeaderType == leader then return true; end
		end
	end
	return false;
end

-- The first unmet prerequisite of an improvement: nil (possible now) or { kind, type, name, id }.
local function _Missing( improvement:table, player:table )
	if improvement.PrereqTech ~= nil and improvement.PrereqTech ~= "" then
		local row:table = GameInfo.Technologies[ improvement.PrereqTech ];
		if row ~= nil and not _HasTech( player, row ) then
			return { kind = "tech", type = row.TechnologyType, name = Locale.Lookup( row.Name ), id = row.Index };
		end
	end
	if improvement.PrereqCivic ~= nil and improvement.PrereqCivic ~= "" then
		local row:table = GameInfo.Civics[ improvement.PrereqCivic ];
		if row ~= nil and not _HasCivic( player, row ) then
			return { kind = "civic", type = row.CivicType, name = Locale.Lookup( row.Name ), id = row.Index };
		end
	end
	return nil;
end

-- ===========================================================================
--	One plot
-- ===========================================================================
local function _Revealed( plot:table, playerId:number )
	local vis:table = PlayersVisibility[ playerId ];
	return vis ~= nil and vis:IsRevealed( plot:GetIndex() );
end

function ResourceTech_Info( plot:table )
	if plot == nil then return nil; end
	local player:table, playerId:number = _Player();
	if player == nil then return nil; end
	local resourceType:number = plot:GetResourceType();
	if resourceType == nil or resourceType < 0 then return nil; end
	local row:table = GameInfo.Resources[ resourceType ];
	if row == nil or not _Revealed( plot, playerId ) then return nil; end
	local resources:table = player:GetResources();
	if resources ~= nil and not resources:IsResourceVisible( row.Hash ) then return nil; end
	_Index();
	local candidates:table = m_byResource[ row.ResourceType ];
	if candidates == nil then return nil; end

	local info:table = { resource = Locale.Lookup( row.Name ), resourceType = row.ResourceType };
	local onPlot:number = plot:GetImprovementType();
	local hasImprovement:boolean = onPlot ~= nil and onPlot >= 0;
	local districtType:number = plot:GetDistrictType();
	if plot:IsCity() or ( districtType ~= nil and districtType >= 0 ) then info.status = "other"; return info; end
	local water:boolean = plot:IsWater();
	local options:table = {};
	for _, improvement in ipairs( candidates ) do
		local sea:boolean = improvement.Domain == "DOMAIN_SEA";
		if sea == water and _MayUse( improvement, playerId ) then table.insert( options, improvement ); end
	end
	if #options == 0 then info.status = "other"; return info; end

	if hasImprovement then
		local current:table = GameInfo.Improvements[ onPlot ];
		for _, improvement in ipairs( options ) do
			if current ~= nil and improvement.ImprovementType == current.ImprovementType then
				info.status, info.improvedWith = "improved", Locale.Lookup( current.Name );
				return info;
			end
		end
		info.status = "other";
		return info;
	end

	local first:table = nil;
	for _, improvement in ipairs( options ) do
		local missing:table = _Missing( improvement, player );
		if missing == nil then
			info.status, info.improvement = "possible", Locale.Lookup( improvement.Name );
			return info;
		end
		if first == nil then first = { improvement = improvement, missing = missing }; end
	end
	info.status, info.improvement, info.need = "needs", Locale.Lookup( first.improvement.Name ), first.missing;
	return info;
end

function ResourceTech_NeedText( need:table )
	if need == nil then return ""; end
	return need.name;
end

-- Turns of research for a tech or civic, the missing prerequisites included: the sum of turnsOf over every missing
-- node on the path (each once). has( type ) / turnsOf( type ) are supplied by the caller.
function ResourceTech_PathTurns( kind:string, typeName:string, has, turnsOf )
	local prereqs:table = _PrereqMap( kind );
	local seen:table = {};
	local total:number = 0;
	local function Visit( t:string )
		if seen[ t ] or has( t ) then return; end
		seen[ t ] = true;
		total = total + ( turnsOf( t ) or 0 );
		for _, p in ipairs( prereqs[ t ] or {} ) do Visit( p ); end
	end
	Visit( typeName );
	return total;
end

local function _KindFns( kind:string, player:table )
	if kind == "tech" then
		local techs:table = player:GetTechs();
		return function( t ) local r = GameInfo.Technologies[ t ]; return r == nil or techs:HasTech( r.Index ); end,
			function( t ) local r = GameInfo.Technologies[ t ]; return r ~= nil and techs:GetTurnsToResearch( r.Index ) or 0; end;
	end
	local culture:table = player:GetCulture();
	return function( t ) local r = GameInfo.Civics[ t ]; return r == nil or culture:HasCivic( r.Index ); end,
		function( t ) local r = GameInfo.Civics[ t ]; return r ~= nil and culture:GetTurnsToProgressCivic( r.Index ) or 0; end;
end

function ResourceTech_Turns( need:table )
	if need == nil then return nil; end
	local player:table = _Player();
	if player == nil then return nil; end
	local ok:boolean, turns = pcall( function()
		local has, turnsOf = _KindFns( need.kind, player );
		return ResourceTech_PathTurns( need.kind, need.type, has, turnsOf );
	end );
	if ok and turns ~= nil and turns > 0 then return turns; end
	return nil;
end

local function _Turns( n:number )
	if n == 1 then return "1 turn"; end
	return n .. " turns";
end

-- Plots owned by someone else are not ours to improve: nothing to say about them.
local function _Foreign( plot:table )
	local owner:number = plot:GetOwner();
	return owner ~= nil and owner >= 0 and owner ~= Game.GetLocalPlayer();
end

function ResourceTech_Short( plot:table )
	local info:table = ResourceTech_Info( plot );
	if info == nil or _Foreign( plot ) then return nil; end
	if info.status == "needs" then return "needs " .. info.need.name; end
	if info.status == "possible" and plot:GetOwner() == Game.GetLocalPlayer() then
		return string.lower( info.improvement ) .. " possible";
	end
	return nil;
end

function ResourceTech_Full( plot:table )
	local info:table = ResourceTech_Info( plot );
	if info == nil or _Foreign( plot ) then return nil; end
	if info.status == "needs" then
		local text:string = info.resource .. ": " .. info.improvement .. " needs " .. info.need.name;
		local turns:number = ResourceTech_Turns( info.need );
		if turns ~= nil then text = text .. ", " .. _Turns( turns ) .. " of research"; end
		return text;
	end
	if info.status == "possible" and plot:GetOwner() == Game.GetLocalPlayer() then
		return info.resource .. ": " .. info.improvement .. " can be built now";
	end
	return nil;
end

-- ===========================================================================
--	The trees: techs / civics that unlock improvements near my cities
-- ===========================================================================
local function _NearestCity( plot:table, cities:table )
	local best:table, bestDistance:number = nil, 1000;
	for _, city in ipairs( cities ) do
		local d:number = Map.GetPlotDistance( plot:GetX(), plot:GetY(), city.x, city.y );
		if d < bestDistance then best, bestDistance = city, d; end
	end
	return best;
end

local function _MyCities( player:table )
	local list:table = {};
	for _, city in player:GetCities():Members() do
		table.insert( list, { city = city, x = city:GetX(), y = city:GetY(), name = Locale.Lookup( city:GetName() ) } );
	end
	return list;
end

-- Every plot owned by one of my cities or within SCAN_RANGE of one (unowned), each once: calls visit( plot, nearestCity ).
local function _EachNearPlot( cities:table, visit )
	local width:number = Map.GetGridSize();
	local seen:table = {};
	local localPlayer:number = Game.GetLocalPlayer();
	local function Try( plot:table )
		if plot == nil or seen[ plot:GetIndex() ] then return; end
		seen[ plot:GetIndex() ] = true;
		local owner:number = plot:GetOwner();
		if owner ~= nil and owner >= 0 and owner ~= localPlayer then return; end
		visit( plot, _NearestCity( plot, cities ) );
	end
	for _, c in ipairs( cities ) do
		if Map.GetCityPlots ~= nil then
			local ok:boolean, owned = pcall( function() return Map.GetCityPlots():GetPurchasedPlots( c.city ); end );
			if ok and owned ~= nil then
				for _, index in ipairs( owned ) do Try( Map.GetPlotByIndex( index ) ); end
			end
		end
		for dy = -SCAN_RANGE, SCAN_RANGE do
			for dx = -SCAN_RANGE, SCAN_RANGE do
				local x:number = c.x + dx;
				if Map.IsWrapX() then x = x % width; end
				local plot:table = Map.GetPlot( x, c.y + dy );
				if plot ~= nil and Map.GetPlotDistance( c.x, c.y, plot:GetX(), plot:GetY() ) <= SCAN_RANGE then Try( plot ); end
			end
		end
	end
end

function ResourceTech_Scan( kind:string )
	local player:table = _Player();
	if player == nil then return {}; end
	local cities:table = _MyCities( player );
	local byType:table, groups:table = {}, {};
	_EachNearPlot( cities, function( plot:table, city:table )
		local info:table = ResourceTech_Info( plot );
		if info == nil or info.status ~= "needs" or info.need.kind ~= kind then return; end
		local g:table = byType[ info.need.type ];
		if g == nil then
			g = { kind = kind, type = info.need.type, name = info.need.name, total = 0, resources = {}, byName = {} };
			byType[ info.need.type ] = g;
			table.insert( groups, g );
		end
		g.total = g.total + 1;
		local r:table = g.byName[ info.resource ];
		if r == nil then
			r = { name = info.resource, count = 0, city = city ~= nil and city.name or nil, distance = 1000 };
			g.byName[ info.resource ] = r;
			table.insert( g.resources, r );
		end
		r.count = r.count + 1;
		if city ~= nil then
			local d:number = Map.GetPlotDistance( plot:GetX(), plot:GetY(), city.x, city.y );
			if d < r.distance then r.distance, r.city = d, city.name; end
		end
	end );
	local has, turnsOf = _KindFns( kind, player );
	local prereqs:table = _PrereqMap( kind );
	for _, g in ipairs( groups ) do
		g.byName = nil;
		table.sort( g.resources, function( a, b )
			if a.count ~= b.count then return a.count > b.count; end
			return a.name < b.name;
		end );
		local ok:boolean, turns = pcall( ResourceTech_PathTurns, kind, g.type, has, turnsOf );
		g.turns = ok and turns or 0;
		g.missing = {};
		for _, p in ipairs( prereqs[ g.type ] or {} ) do
			if not has( p ) then
				local row:table = ( kind == "tech" ) and GameInfo.Technologies[ p ] or GameInfo.Civics[ p ];
				if row ~= nil then table.insert( g.missing, Locale.Lookup( row.Name ) ); end
			end
		end
	end
	table.sort( groups, function( a, b )
		if a.turns ~= b.turns then return a.turns < b.turns; end
		return a.name < b.name;
	end );
	return groups;
end

-- "2 Horses" / "Iron"
local function _CountName( r:table )
	if r.count > 1 then return r.count .. " " .. r.name; end
	return r.name;
end

local function _JoinAnd( parts:table )
	if #parts <= 1 then return parts[1] or ""; end
	return table.concat( parts, ", ", 1, #parts - 1 ) .. " and " .. parts[ #parts ];
end

-- "improves 2 Horses and 1 Sheep near your cities" (counts always spoken, three resources at most)
function ResourceTech_NodePhrase( groups:table, typeName:string )
	for _, g in ipairs( groups or {} ) do
		if g.type == typeName then
			local parts:table = {};
			for i, r in ipairs( g.resources ) do
				if i > 3 then
					table.insert( parts, ( #g.resources - 3 ) .. " more kinds" );
					break;
				end
				table.insert( parts, r.count .. " " .. r.name );
			end
			return "improves " .. _JoinAnd( parts ) .. " near your cities";
		end
	end
	return nil;
end

-- "Bronze Working, 6 turns: Iron near Rome, 2 Horses near Antium" / "Irrigation, 9 turns, needs Pottery: ..."
function ResourceTech_GroupText( g:table )
	local head:string = g.name;
	if g.turns ~= nil and g.turns > 0 then head = head .. ", " .. _Turns( g.turns ); end
	if g.missing ~= nil and #g.missing > 0 then head = head .. ", needs " .. table.concat( g.missing, " and " ); end
	local parts:table = {};
	for _, r in ipairs( g.resources ) do
		table.insert( parts, _CountName( r ) .. ( r.city ~= nil and ( " near " .. r.city ) or "" ) );
	end
	return head .. ": " .. table.concat( parts, ", " );
end

-- ===========================================================================
--	City report
-- ===========================================================================
function ResourceTech_CityResources( city:table )
	local result:table = { improved = {}, needs = {}, possible = {} };
	if city == nil or Map.GetCityPlots == nil then return result; end
	local lists:table = { improved = {}, needs = {}, possible = {} };
	local function Add( bucket:string, key:string, entry:table )
		local e:table = lists[ bucket ][ key ];
		if e == nil then
			e = entry;
			e.count = 0;
			lists[ bucket ][ key ] = e;
			table.insert( result[ bucket ], e );
		end
		e.count = e.count + 1;
	end
	for _, index in ipairs( Map.GetCityPlots():GetPurchasedPlots( city ) ) do
		local plot:table = Map.GetPlotByIndex( index );
		local info:table = ResourceTech_Info( plot );
		if info ~= nil then
			if info.status == "improved" then
				Add( "improved", info.resource, { name = info.resource, improvement = info.improvedWith } );
			elseif info.status == "needs" then
				Add( "needs", info.resource .. ":" .. info.need.name, { name = info.resource, need = info.need.name, improvement = info.improvement } );
			elseif info.status == "possible" then
				Add( "possible", info.resource, { name = info.resource, improvement = info.improvement } );
			end
		end
	end
	for _, list in pairs( result ) do
		table.sort( list, function( a, b ) return a.name < b.name; end );
	end
	return result;
end
