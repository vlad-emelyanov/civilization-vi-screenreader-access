-- ===========================================================================
--	HubOverview: the area overview list (Shift+J, action KeyNavAreaOverview).
--	Part of the InGameAccess hub (see docs/ingame-plan.md, Architecture): included by UI/Additions/InGameAccess.lua.
--
--	A macro view of the map around the map cursor, for a player who has no minimap: items "Area" (terrain, coast, river,
--	resources within 3 tiles), "Continent" (size known, extent, cities, unexplored edges) and one item per compass direction
--	(plots within 8 tiles). Up/Down/Home/End move, Space repeats, Escape closes ("Closed").
--	Only REVEALED plots count (what the game's own map shows): terrain, owner, cities and resources the player can see;
--	units and live state of fogged plots are never read. The continent sizes come from Map.GetVisibleContinentPlots (the
--	revealed plots), never Map.GetContinentPlots (it includes unexplored plots).
--
--	The wording is pure functions over plain tables (Join, TopTerrains, AreaText, Extent, ContinentText, SectorText), tested by
--	test/lua/test_overview.lua; the gathering from the engine is below them.
-- ===========================================================================
HubOverview = {};

local AREA_RADIUS		:number = 3;
local SECTOR_RADIUS		:number = 8;
local ISLAND_TILES		:number = 20;		-- fewer known tiles than this: a small island
local FEATURE_MIN		:number = 3;		-- a feature is the main one from this many plots
local HILLS_MIN			:number = 2;
local MOUNTAINS_MIN		:number = 2;

local m_items			:table = {};
local m_list			:table;

-- ===========================================================================
--	PURE WORDING
-- ===========================================================================
local function Plural( n:number, one:string, many:string )
	if n == 1 then return n .. " " .. one; end
	return n .. " " .. many;
end

-- "a", "a and b", "a, b and c"
function HubOverview.Join( list:table )
	local n:number = #list;
	if n == 0 then return ""; end
	if n == 1 then return list[1]; end
	return table.concat( list, ", ", 1, n - 1 ) .. " and " .. list[n];
end

-- The n words with the highest counts (ties: alphabetical). counts: word -> number.
function HubOverview.TopTerrains( counts:table, n:number )
	local words:table = {};
	for word, count in pairs( counts ) do
		if count > 0 then table.insert( words, word ); end
	end
	table.sort( words, function( a, b )
		if counts[a] ~= counts[b] then return counts[a] > counts[b]; end
		return a < b;
	end );
	local top:table = {};
	for i = 1, math.min( n, #words ) do top[i] = words[i]; end
	return top;
end

-- a: { terrains = { word -> count } (flat land only), hills, mountains, feature = { name, count } | nil,
--      coast = "on the coast" | "near the coast" | nil, lake, river (booleans), luxuries, strategics (name lists), unexplored (number),
--      revealed (number of revealed plots) }
function HubOverview.AreaText( name:string, a:table )
	if ( a.revealed or 0 ) == 0 then return name .. ": unexplored"; end
	local land:table = {};
	local top:table = HubOverview.TopTerrains( a.terrains or {}, 2 );
	if #top > 0 then table.insert( land, HubOverview.Join( top ) ); end
	if a.feature ~= nil and a.feature.count >= FEATURE_MIN then table.insert( land, a.feature.name ); end
	if ( a.hills or 0 ) >= HILLS_MIN then table.insert( land, "hills" ); end
	if ( a.mountains or 0 ) >= MOUNTAINS_MIN then table.insert( land, "mountains" ); end
	local water:table = {};
	if a.coast ~= nil then table.insert( water, a.coast ); end
	if a.lake then table.insert( water, "a lake" ); end
	if a.river then table.insert( water, "a river" ); end
	if #water > 0 then table.insert( land, HubOverview.Join( water ) ); end
	local text:string = name .. ": " .. ( #land > 0 and table.concat( land, ", " ) or "no land known" );
	if a.luxuries ~= nil and #a.luxuries > 0 then text = text .. "; luxuries: " .. table.concat( a.luxuries, ", " ); end
	if a.strategics ~= nil and #a.strategics > 0 then text = text .. "; strategic: " .. table.concat( a.strategics, ", " ); end
	if ( a.unexplored or 0 ) > 0 then text = text .. "; " .. a.unexplored .. " tiles unexplored"; end
	return text;
end

-- Extent of a set of offsets { dx, dy } (dy > 0 north, dx > 0 east) from the centre: how far it reaches in each direction.
function HubOverview.Extent( offsets:table )
	local e:table = { north = 0, south = 0, east = 0, west = 0 };
	for _, o in ipairs( offsets ) do
		if o[2] > e.north then e.north = o[2]; end
		if -o[2] > e.south then e.south = -o[2]; end
		if o[1] > e.east then e.east = o[1]; end
		if -o[1] > e.west then e.west = -o[1]; end
	end
	for k, v in pairs( e ) do e[k] = math.floor( v + 0.5 ); end
	return e;
end

-- c: { name, known (revealed tiles), centre (name), extent, cities = { mine = {names}, others = { { civ, names } }, minors = {names} },
--      edges = { direction words in order } }
function HubOverview.ContinentText( c:table )
	local text:string = c.name .. ": " .. Plural( c.known, "tile", "tiles" ) .. " known";
	if c.known < ISLAND_TILES then text = text .. " (a small island)"; end
	local e:table = c.extent;
	if e ~= nil then
		text = text .. "; extends about " .. e.north .. " north, " .. e.south .. " south, " .. e.east .. " east, " .. e.west .. " west of " .. c.centre;
	end
	local cities:table = {};
	if c.cities ~= nil then
		if #c.cities.mine > 0 then table.insert( cities, "yours " .. HubOverview.Join( c.cities.mine ) ); end
		for _, group in ipairs( c.cities.others ) do table.insert( cities, group.civ .. ": " .. HubOverview.Join( group.names ) ); end
		if #c.cities.minors > 0 then table.insert( cities, "city-states: " .. HubOverview.Join( c.cities.minors ) ); end
	end
	if #cities > 0 then
		text = text .. "; cities on it: " .. table.concat( cities, "; " );
	else
		text = text .. "; no cities seen on it";
	end
	if c.edges ~= nil and #c.edges > 0 then
		text = text .. "; unexplored edges: " .. table.concat( c.edges, ", " );
	else
		text = text .. "; no unexplored edges";
	end
	return text;
end

-- title: "North". entries: plain tables of the plots of that wedge within the radius:
--   { dist, revealed, water (ocean or coast), kind (land word, incl. hills / mountains), owner (foreign civ name), city (name), cityOwner (civ name, nil = yours) }
function HubOverview.SectorText( title:string, entries:table )
	local total:number = #entries;
	if total == 0 then return title .. ": edge of the map"; end
	local unexplored:number = 0;
	local counts:table = {};
	local waterDist:number = nil;
	local owner:table, city:table = nil, nil;
	for _, e in ipairs( entries ) do
		if not e.revealed then
			unexplored = unexplored + 1;
		else
			if e.water then
				if waterDist == nil or e.dist < waterDist then waterDist = e.dist; end
			elseif e.kind ~= nil then
				counts[ e.kind ] = ( counts[ e.kind ] or 0 ) + 1;
			end
			if e.owner ~= nil and ( owner == nil or e.dist < owner.dist ) then owner = e; end
			if e.city ~= nil and ( city == nil or e.dist < city.dist ) then city = e; end
		end
	end
	if unexplored == total then return title .. ": unexplored"; end
	local parts:table = {};
	local top:table = HubOverview.TopTerrains( counts, 2 );
	if #top > 0 then table.insert( parts, HubOverview.Join( top ) ); end
	if owner ~= nil then table.insert( parts, owner.owner .. "'s territory after " .. Plural( owner.dist, "tile", "tiles" ) ); end
	if waterDist ~= nil then
		local far:number, farWater:number = 0, 0;
		for _, e in ipairs( entries ) do
			if e.revealed and e.dist >= waterDist then
				far = far + 1;
				if e.water then farWater = farWater + 1; end
			end
		end
		if farWater * 2 > far then table.insert( parts, "ocean from " .. Plural( waterDist, "tile", "tiles" ) ); end
	end
	if city ~= nil then
		local who:string = city.cityOwner ~= nil and ( city.city .. " of " .. city.cityOwner ) or ( "your city " .. city.city );
		table.insert( parts, who .. " at " .. Plural( city.dist, "tile", "tiles" ) );
	end
	if unexplored * 2 > total then
		table.insert( parts, "mostly unexplored" );
	elseif unexplored * 5 > total then
		table.insert( parts, "partly unexplored" );
	end
	if #parts == 0 then return title .. ": nothing special"; end
	return title .. ": " .. table.concat( parts, ", " );
end

-- ===========================================================================
--	GATHERING FROM THE ENGINE (revealed plots only)
-- ===========================================================================
local function Lower( s:string )
	return string.lower( s or "" );
end

local function IsRevealed( plot:table )
	local localPlayer:number = Game.GetLocalPlayer();
	if localPlayer == nil or localPlayer == -1 then return true; end
	local vis:table = PlayersVisibility[ localPlayer ];
	return vis ~= nil and vis:IsRevealed( plot:GetIndex() );
end

-- Plots within radius of (cx, cy), wrapping the map: a list of { plot, dist }.
local function PlotsAround( cx:number, cy:number, radius:number )
	local list:table = {};
	local width:number = Map.GetGridSize();
	for dy = -radius, radius do
		for dx = -radius, radius do
			local x:number = cx + dx;
			if Map.IsWrapX() then x = x % width; end
			local plot:table = Map.GetPlot( x, cy + dy );
			if plot ~= nil then
				local dist:number = Map.GetPlotDistance( cx, cy, plot:GetX(), plot:GetY() );
				if dist <= radius then table.insert( list, { plot = plot, dist = dist } ); end
			end
		end
	end
	return list;
end

-- What a revealed plot is: "ocean" (ocean or coast), "lake", or the land word (hills, mountains, grassland ...).
local function PlotKind( plot:table )
	if plot:IsLake() then return "lake"; end
	if plot:IsWater() then return "ocean"; end
	local row:table = GameInfo.Terrains[ plot:GetTerrainType() ];
	if row == nil then return nil; end
	local t:string = row.TerrainType or "";
	if string.find( t, "_HILLS$" ) then return "hills"; end
	if string.find( t, "_MOUNTAIN$" ) then return "mountains"; end
	return Lower( Locale.Lookup( row.Name ) );
end

local function FeatureName( plot:table )
	local featureType:number = plot:GetFeatureType();
	if featureType == nil or featureType < 0 then return nil; end
	local row:table = GameInfo.Features[ featureType ];
	if row == nil then return nil; end
	return Lower( Locale.Lookup( row.Name ) );
end

-- The city whose area the cursor plot is in (a city of ours on it or owning it), else nil.
local function CentreCity( plot:table )
	local localPlayer:number = Game.GetLocalPlayer();
	if plot:IsCity() then
		local city:table = Cities.GetCityInPlot( plot:GetX(), plot:GetY() );
		if city ~= nil and city:GetOwner() == localPlayer then return city; end
		return nil;
	end
	if plot:GetOwner() ~= localPlayer then return nil; end
	local best:table, bestDist:number = nil, 1000;
	for _, city in Players[ localPlayer ]:GetCities():Members() do
		local d:number = Map.GetPlotDistance( plot:GetX(), plot:GetY(), city:GetX(), city:GetY() );
		if d < bestDist then best, bestDist = city, d; end
	end
	return best;
end

local function BuildArea( name:string, cx:number, cy:number )
	local a:table = { terrains = {}, hills = 0, mountains = 0, luxuries = {}, strategics = {}, unexplored = 0, revealed = 0 };
	local featureCounts:table = {};
	local waterNear:boolean, waterWide:boolean = false, false;
	local seen:table = {};
	local localPlayer:number = Game.GetLocalPlayer();
	local resources:table = Players[ localPlayer ]:GetResources();
	for _, entry in ipairs( PlotsAround( cx, cy, AREA_RADIUS ) ) do
		local plot:table = entry.plot;
		if not IsRevealed( plot ) then
			a.unexplored = a.unexplored + 1;
		else
			a.revealed = a.revealed + 1;
			local kind:string = PlotKind( plot );
			if kind == "lake" then
				a.lake = true;
			elseif kind == "ocean" then
				if entry.dist <= 1 then waterNear = true; end
				waterWide = true;
			elseif kind == "hills" then
				a.hills = a.hills + 1;
			elseif kind == "mountains" then
				a.mountains = a.mountains + 1;
			elseif kind ~= nil then
				a.terrains[ kind ] = ( a.terrains[ kind ] or 0 ) + 1;
			end
			if kind ~= "ocean" and kind ~= "lake" and plot:IsRiver() then a.river = true; end
			local feature:string = ( kind ~= "ocean" and kind ~= "lake" ) and FeatureName( plot ) or nil;
			if feature ~= nil then featureCounts[ feature ] = ( featureCounts[ feature ] or 0 ) + 1; end
			local resourceType:number = plot:GetResourceType();
			if resourceType ~= nil and resourceType >= 0 then
				local row:table = GameInfo.Resources[ resourceType ];
				if row ~= nil and ( resources == nil or resources:IsResourceVisible( row.Hash ) ) and not seen[ resourceType ] then
					seen[ resourceType ] = true;
					local resourceName:string = Locale.Lookup( row.Name );
					if row.ResourceClassType == "RESOURCECLASS_LUXURY" then
						table.insert( a.luxuries, resourceName );
					elseif row.ResourceClassType == "RESOURCECLASS_STRATEGIC" then
						table.insert( a.strategics, resourceName );
					end
				end
			end
		end
	end
	table.sort( a.luxuries );
	table.sort( a.strategics );
	local top:table = HubOverview.TopTerrains( featureCounts, 1 );
	if #top > 0 then a.feature = { name = top[1], count = featureCounts[ top[1] ] }; end
	if waterNear then a.coast = "on the coast"; elseif waterWide then a.coast = "near the coast"; end
	return HubOverview.AreaText( name, a );
end

local function ContinentName( continent:number )
	local row:table = GameInfo.Continents[ continent ];
	if row == nil then return nil; end
	return Locale.Lookup( row.Description );
end

-- The 8 direction words in order, lower case, as PlotDescription_GetDirectionWord says them.
local DIRECTION_KEYS:table = { "NORTH", "NORTH_EAST", "EAST", "SOUTH_EAST", "SOUTH", "SOUTH_WEST", "WEST", "NORTH_WEST" };
local function DirectionWords()
	local words:table = {};
	for i, key in ipairs( DIRECTION_KEYS ) do words[i] = Lower( Locale.Lookup( "LOC_DIRECTION_" .. key ) ); end
	return words;
end

-- Offset of a plot from the centre in tiles (dx east, dy north), the hex row shift and the wrapping map included.
local function Offset( cx:number, cy:number, x:number, y:number )
	local width:number = Map.GetGridSize();
	local dx:number = ( x + ( ( y % 2 ) * 0.5 ) ) - ( cx + ( ( cy % 2 ) * 0.5 ) );
	if Map.IsWrapX() then
		if dx > width / 2 then dx = dx - width; elseif dx < -width / 2 then dx = dx + width; end
	end
	return { dx, y - cy };
end

local function CityGroups( cityPlots:table )
	local localPlayer:number = Game.GetLocalPlayer();
	local mine:table, minors:table = {}, {};
	local byCiv:table, order:table = {}, {};
	for _, plot in ipairs( cityPlots ) do
		local city:table = Cities.GetCityInPlot( plot:GetX(), plot:GetY() );
		if city ~= nil then
			local owner:number = city:GetOwner();
			local name:string = Locale.Lookup( city:GetName() );
			if owner == localPlayer then
				table.insert( mine, name );
			elseif Players[ owner ] ~= nil and not Players[ owner ]:IsMajor() then
				table.insert( minors, name );
			else
				local civ:string = PlotDescription_GetCivName( owner );
				if byCiv[ civ ] == nil then byCiv[ civ ] = {}; table.insert( order, civ ); end
				table.insert( byCiv[ civ ], name );
			end
		end
	end
	table.sort( mine ); table.sort( minors ); table.sort( order );
	local others:table = {};
	for _, civ in ipairs( order ) do
		table.sort( byCiv[ civ ] );
		table.insert( others, { civ = civ, names = byCiv[ civ ] } );
	end
	return { mine = mine, others = others, minors = minors };
end

local function BuildContinent( centre:table, centreName:string )
	local cx:number, cy:number = centre:GetX(), centre:GetY();
	local words:table = DirectionWords();
	if centre:IsWater() then
		-- nearest revealed land
		local best:table = nil;
		for _, entry in ipairs( PlotsAround( cx, cy, 12 ) ) do
			local plot:table = entry.plot;
			if not plot:IsWater() and IsRevealed( plot ) and ( best == nil or entry.dist < best.dist ) then best = { plot = plot, dist = entry.dist }; end
		end
		if best == nil then return "Water tile; no land known within 12 tiles"; end
		local name:string = ContinentName( best.plot:GetContinentType() ) or "land";
		return "Water tile; nearest land: " .. name .. ", " .. ( PlotDescription_GetRelative( centre, best.plot ) or "here" );
	end
	local continent:number = centre:GetContinentType();
	local name:string = ( continent ~= nil and continent >= 0 ) and ContinentName( continent ) or nil;
	if name == nil then return "Continent unknown"; end
	local indexes:table = Map.GetVisibleContinentPlots( continent ) or {};
	local offsets:table, cityPlots:table, edgeSet:table = {}, {}, {};
	for _, index in ipairs( indexes ) do
		local plot:table = Map.GetPlotByIndex( index );
		if plot ~= nil and IsRevealed( plot ) then
			table.insert( offsets, Offset( cx, cy, plot:GetX(), plot:GetY() ) );
			if plot:IsCity() then table.insert( cityPlots, plot ); end
			for dir = 0, 5 do
				local n:table = Map.GetAdjacentPlot( plot:GetX(), plot:GetY(), dir );
				if n ~= nil and not IsRevealed( n ) then
					local word:string = PlotDescription_GetDirectionWord( cx, cy, plot:GetX(), plot:GetY() );
					if word ~= nil then edgeSet[ Lower( word ) ] = true; end
					break;
				end
			end
		end
	end
	local edges:table = {};
	for _, word in ipairs( words ) do
		if edgeSet[ word ] then table.insert( edges, word ); end
	end
	return HubOverview.ContinentText{
		name = name, known = #offsets, centre = centreName == "This area" and "here" or centreName,
		extent = HubOverview.Extent( offsets ), cities = CityGroups( cityPlots ), edges = edges,
	};
end

local function BuildSectors( centre:table )
	local cx:number, cy:number = centre:GetX(), centre:GetY();
	local localPlayer:number = Game.GetLocalPlayer();
	local words:table = DirectionWords();
	local buckets:table = {};
	for _, word in ipairs( words ) do buckets[ word ] = {}; end
	for _, entry in ipairs( PlotsAround( cx, cy, SECTOR_RADIUS ) ) do
		local plot:table = entry.plot;
		if entry.dist > 0 then
			local word:string = PlotDescription_GetDirectionWord( cx, cy, plot:GetX(), plot:GetY() );
			local bucket:table = word ~= nil and buckets[ Lower( word ) ] or nil;
			if bucket ~= nil then
				local e:table = { dist = entry.dist, revealed = IsRevealed( plot ) };
				if e.revealed then
					local kind:string = PlotKind( plot );
					e.water = ( kind == "ocean" );
					if kind ~= "ocean" and kind ~= "lake" then e.kind = kind; end
					local owner:number = plot:GetOwner();
					if owner ~= nil and owner >= 0 and owner ~= localPlayer then e.owner = PlotDescription_GetCivName( owner ); end
					if plot:IsCity() then
						local city:table = Cities.GetCityInPlot( plot:GetX(), plot:GetY() );
						if city ~= nil then
							e.city = Locale.Lookup( city:GetName() );
							if city:GetOwner() ~= localPlayer then e.cityOwner = PlotDescription_GetCivName( city:GetOwner() ); end
						end
					end
				end
				table.insert( bucket, e );
			end
		end
	end
	local texts:table = {};
	for _, word in ipairs( words ) do
		local title:string = string.upper( string.sub( word, 1, 1 ) ) .. string.sub( word, 2 );
		table.insert( texts, HubOverview.SectorText( title, buckets[ word ] ) );
	end
	return texts;
end

-- The items of the list for the map cursor.
function HubOverview.BuildItems()
	local x:number, y:number = HubCursor.GetCursor();
	local cursor:table = Map.GetPlot( x, y );
	if cursor == nil then return {}; end
	local city:table = CentreCity( cursor );
	local centre:table = cursor;
	local name:string = "This area";
	if city ~= nil then
		centre = Map.GetPlot( city:GetX(), city:GetY() ) or cursor;
		name = Locale.Lookup( city:GetName() );
	end
	local cx:number, cy:number = centre:GetX(), centre:GetY();
	local items:table = {};
	local function Add( key:string, text:string )
		table.insert( items, { key = key, text = text, detail = text } );
	end
	if not IsRevealed( centre ) then
		Add( "area", "This area: unexplored tile" );
	else
		Add( "area", BuildArea( name, cx, cy ) );
		Add( "continent", BuildContinent( centre, name ) );
	end
	for i, text in ipairs( BuildSectors( centre ) ) do Add( "sector" .. i, text ); end
	return items;
end

-- ===========================================================================
--	THE LIST
-- ===========================================================================
local m_facade:table = {
	Open = function( title:string )
		m_list.Open( title );
	end,
	Reset = function() m_list.Reset(); end,
	HandleInput = function( input:table ) return m_list.HandleInput( input ); end,
};

m_list = KeyNavList_Create{
	build		= function() return m_items; end,
	isActive	= function() return HubCore.IsModeOpen( "overview" ); end,
	onActivate	= function( item ) OutputMessageToScreenReader( item.text ); end,
	onClose		= function() HubCore.CloseMode( true, false ); end,
};

-- Shift+J (action KeyNavAreaOverview): opens the overview, or closes it when open.
function HubOverview.Toggle()
	if HubCore.IsModeOpen( "overview" ) then HubCore.CloseMode( true, false ); return; end
	if not HubTargets.CanOpenMode() then return; end
	local ok:boolean, items = pcall( HubOverview.BuildItems );
	if not ok then
		print( "HubOverview error: " .. tostring( items ) );
		OutputMessageToScreenReader( "Area overview is not available here" );
		return;
	end
	if #items == 0 then
		OutputMessageToScreenReader( "Nothing to overview here" );
		return;
	end
	m_items = items;
	HubCore.OpenMode( "overview", m_facade, "Area overview" );
end
