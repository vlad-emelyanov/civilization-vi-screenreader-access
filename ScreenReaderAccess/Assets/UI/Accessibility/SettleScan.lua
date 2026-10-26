-- ===========================================================================
--	SettleScan: where can the selected settler found a city, and where is it best? Pure data, no speech.
--
--	SettleScan_CheckPlot( plot, cities )  -> true | false, reason   (the game's found-city rules, tested for any plot;
--	                                           reason "" = cannot, but nothing visible explains it (a city we have not seen))
--	SettleScan_CanFound( unit, plot )     -> true [, true when the unit has no moves left] | false, reason
--	                                           (CheckPlot, plus the engine's own check while the unit has moves)
--	SettleScan_CannotText( reason )       -> "cannot settle" / "cannot settle: reason"
--	SettleScan_Scan( unit, force )        -> { here = candidate|nil, hereReason = string|nil, list = { candidates sorted by score },
--	                                           best = candidate|nil }   (cached per unit + plot + turn + moves; force = rescan)
--	candidate: { key, plotIndex, x, y, distance, turns, score, recommended, reasons = { good short phrases, most important
--	             first }, negatives = { bad short phrases }, detail = <all reasons as one string for Space>, here = true for
--	             the settler's own plot }
--
--	Candidates: (a) the game's advisor (GrandStrategicAI:GetSettlementRecommendations, shown as icons by the settler
--	lens), (b) every revealed plot within SCAN_RADIUS of the settler where a city can be founded.
--
--	Engine check (verified in game): UnitManager.CanStartOperation( unit, FOUND_CITY, plot, false, true ) tests the given
--	plot (remote plots work, the unit's own plot is irrelevant: a settler inside a city still gets "yes" for far plots),
--	but answers false for EVERY plot when the unit has no moves left. So CheckPlot decides and the engine only vetoes
--	while the unit has moves.
--
--	Score (higher is better; only the order matters, tuned by looking at what it picks in real games):
--	  water       river / lake / oasis (fresh water) +6; coastal +3; the two together at most +8; neither: -4
--	  yields      0.7 * ( ring 1 plots + 0.5 * ring 2 plots ) of ( food + 0.7 * production ); unknown plots count 1.5
--	  food        average food of the known ring 1-2 plots < 1.3: -4 "poor food"; < 1.8 with production < 0.7: -2
--	              "poor land"; fewer than 4 workable land plots (no water, no mountain) in rings 1-2: -3 "little land"
--	  explored    fewer than 8 known plots in rings 1-2: -2 "little explored"
--	  resources   per ring around the city (ring 1 = the 6 neighbours, owned at once; rings 2 and 3 come with border growth):
--	              ring 1: luxury +4, strategic +2.5, bonus +2; ring 2: +2.5 / +1.5 / +1; ring 3: +1.2 / +0.8 / +0.5 (artifacts
--	              a quarter of a bonus). Each resource counts once, in the closest ring. Plots owned by a city already
--	              (ours or foreign) do not count: they stay with that city (named "taken by <city>" in the detail).
--	              The reasons say "ring 1: wheat, silk" (one reason per ring, ring 3 only in the detail). The city plot itself: -1
--	  site        hills +2 (production, defense); mountain next to it +1 each (max 2); natural wonder within 3: +3
--	  hazards     (Gathering Storm API, when present) flooding river or coastal lowlands on the city plot -3, volcano
--	              within 2 -4
--	  crowding    own cities closer than 5 tiles: -1.5 per missing tile; foreign borders within 2 tiles: -0.7 per plot
--	  danger      visible barbarian/enemy soldiers within 3: -4 each (max 2); a barbarian camp within 3: -5
--	  travel      -1.2 per turn needed to reach it (the settler's own pathfinding); unreachable spots are dropped
--	  advisor     +6 and "recommended" for the advisor's picks
--	Candidates within 2 tiles of a better one are dropped (they are the same city site), except the settler's plot and
--	the advisor picks. Path finding runs down the list sorted by score until MAX_CANDIDATES distinct sites are reachable.
--
--	Speed: per-plot facts (visibility, yields, resource, ...) are read once per scan, the list of cities is cached per
--	turn and city count (names looked up only when a reason needs one).
-- ===========================================================================

include( "ScreenReader" );
include( "PlotDescription" );

local SCAN_RADIUS		:number = 6;
local RIVAL_RANGE		:number = 10;		-- G6: a foreign major city this close is named with its distance
local SAME_GAP			:number = 3;		-- G8: the best spot scores less than this above "here": about the same
local CLEAR_GAP			:number = 6;		-- G8: more than this above "here": clearly better
local SIDES_NOTE		:number = 3;		-- G6: this many of the 6 neighbours mountain or water: said in Space
local MAX_CANDIDATES	:number = 12;
local MAX_PATHS			:number = 60;	-- path finding calls per scan at most (it runs in order of static score)
local TURN_COST			:number = 1.2;
local ADVISOR_BONUS		:number = 6;

-- ===========================================================================
--	Helpers
-- ===========================================================================

local function _LocalPlayer()
	local id:number = Game.GetLocalPlayer();
	if id == nil or id == -1 then return nil; end
	return id;
end

local function _IsRevealed( plot:table )
	return PlotDescription_GetVisibility( plot ) ~= "unexplored";
end

local function _MinRange()
	local ok:boolean, value = pcall( function() return GlobalParameters.CITY_MIN_RANGE; end );
	if ok and value ~= nil then return tonumber( value ) or 3; end
	return 3;
end

-- Hex distances and neighbourhoods are computed here instead of asking the engine (Map.GetPlotDistance is a call
-- across the Lua bridge, and a scan needs tens of thousands of them). Odd rows are shifted half a plot east.
local m_gridWidth:number, m_gridHeight:number, m_wrapX:boolean = nil, nil, false;

local function _RefreshGrid()
	m_gridWidth, m_gridHeight = Map.GetGridSize();
	m_wrapX = Map.IsWrapX();
end

local function _DistFlat( x1:number, y1:number, x2:number, y2:number )
	local q1:number = x1 - ( y1 - ( y1 % 2 ) ) / 2;
	local q2:number = x2 - ( y2 - ( y2 % 2 ) ) / 2;
	local dq:number, dr:number = q2 - q1, y2 - y1;
	return ( math.abs( dq ) + math.abs( dr ) + math.abs( dq + dr ) ) / 2;
end

local function _Dist( x1:number, y1:number, x2:number, y2:number )
	local d:number = _DistFlat( x1, y1, x2, y2 );
	if m_wrapX then
		d = math.min( d, _DistFlat( x1, y1, x2 + m_gridWidth, y2 ), _DistFlat( x1, y1, x2 - m_gridWidth, y2 ) );
	end
	return d;
end

-- offsets[ radius ][ row parity ] = { { dx, dy, d } ... } of the plots within radius (the centre included, d = 0)
local m_offsets:table = {};
local function _Offsets( radius:number, parity:number )
	local byRadius:table = m_offsets[ radius ];
	if byRadius == nil then
		byRadius = {};
		m_offsets[ radius ] = byRadius;
		for par = 0, 1 do
			local list:table = {};
			for dy = -radius, radius do
				for dx = -radius - 1, radius + 1 do
					local d:number = _DistFlat( 10 + par, 10 + par, 10 + par + dx, 10 + par + dy );
					if d <= radius then table.insert( list, { dx, dy, d } ); end
				end
			end
			byRadius[ par ] = list;
		end
	end
	return byRadius[ parity ];
end

-- Plots within `radius` of (x, y) as { plot = , d = } (the centre has d = 0). plotAt( x, y ) may cache Map.GetPlot.
local function _Around( x:number, y:number, radius:number, plotAt )
	local list:table = {};
	for _, offset in ipairs( _Offsets( radius, y % 2 ) ) do
		local px:number, py:number = x + offset[1], y + offset[2];
		if m_wrapX then px = px % m_gridWidth; end
		if py >= 0 and py < m_gridHeight and px >= 0 and px < m_gridWidth then
			local plot:table = plotAt( px, py );
			if plot ~= nil then table.insert( list, { plot = plot, d = offset[3] } ); end
		end
	end
	return list;
end

-- All cities of all players: { x, y, owner, id, name = nil until CityName looks it up }. Cached per turn and number of
-- cities (names are localized strings, looked up only when a reason needs one).
local m_citiesKey:string = nil;
local m_cities:table = nil;

local function _AllCities()
	local counts:table = {};
	for playerID = 0, 63 do
		local player:table = Players[ playerID ];
		if player ~= nil and player:IsAlive() and not player:IsBarbarian() then
			table.insert( counts, playerID .. "=" .. player:GetCities():GetCount() );
		end
	end
	local key:string = tostring( Game.GetCurrentGameTurn() ) .. ":" .. table.concat( counts, "," );
	if key == m_citiesKey and m_cities ~= nil then return m_cities; end
	local cities:table = {};
	for playerID = 0, 63 do
		local player:table = Players[ playerID ];
		if player ~= nil and player:IsAlive() and not player:IsBarbarian() then
			for _, city in player:GetCities():Members() do
				table.insert( cities, { x = city:GetX(), y = city:GetY(), owner = playerID, id = city:GetID() } );
			end
		end
	end
	m_citiesKey, m_cities = key, cities;
	return cities;
end

local function _CityName( city:table )
	if city.name == nil then
		local player:table = Players[ city.owner ];
		local real:table = ( player ~= nil ) and player:GetCities():FindID( city.id ) or nil;
		city.name = ( real ~= nil ) and Locale.Lookup( real:GetName() ) or "a city";
	end
	return city.name;
end

local function _IsHostile( playerID:number )
	local localPlayer:number = _LocalPlayer();
	local player:table = Players[ playerID ];
	if player == nil or localPlayer == nil or playerID == localPlayer then return false; end
	if player:IsBarbarian() then return true; end
	local diplomacy:table = Players[ localPlayer ]:GetDiplomacy();
	return diplomacy ~= nil and diplomacy:IsAtWarWith( playerID );
end

-- Visible soldiers of barbarians and of players at war with us: { x, y, barbarian }.
local function _HostileUnits()
	local list:table = {};
	local localPlayer:number = _LocalPlayer();
	for playerID = 0, 63 do
		local player:table = Players[ playerID ];
		if player ~= nil and playerID ~= localPlayer and player:IsAlive() and _IsHostile( playerID ) then
			for _, unit in player:GetUnits():Members() do
				if ( unit:GetCombat() > 0 or unit:GetRangedCombat() > 0 ) and PlotDescription_IsUnitVisible( unit ) then
					table.insert( list, { x = unit:GetX(), y = unit:GetY(), barbarian = player:IsBarbarian() } );
				end
			end
		end
	end
	return list;
end

-- Weight of one resource by class and ring (1-3)
local RING_WEIGHTS:table = {
	luxury		= { 4, 2.5, 1.2 },
	strategic	= { 2.5, 1.5, 0.8 },
	bonus		= { 2, 1, 0.5 },
	artifact	= { 1, 0.5, 0.25 },
};

-- Name of the resource on the plot when the local player can see it: name, class ("luxury" ...). nil if none.
local function _Resource( plot:table )
	local resourceType:number = plot:GetResourceType();
	if resourceType == nil or resourceType < 0 then return nil; end
	local row:table = GameInfo.Resources[ resourceType ];
	if row == nil then return nil; end
	local localPlayer:number = _LocalPlayer();
	if localPlayer ~= nil then
		local resources:table = Players[ localPlayer ]:GetResources();
		if resources ~= nil and not resources:IsResourceVisible( row.Hash ) then return nil; end
	end
	local class:string = "bonus";
	if row.ResourceClassType == "RESOURCECLASS_LUXURY" then class = "luxury";
	elseif row.ResourceClassType == "RESOURCECLASS_STRATEGIC" then class = "strategic";
	elseif row.ResourceClassType == "RESOURCECLASS_ARTIFACT" then class = "artifact"; end
	return Locale.Lookup( row.Name ), class;
end

local function _IsFreshWater( plot:table )
	if plot:IsRiver() or plot:IsLake() then return true; end
	local ok:boolean, result = pcall( plot.IsFreshWater, plot );
	return ok and result == true;
end

-- "Rome" for civilizations we have met, the game's "Unmet Player" for the others (their name would be a leak).
local function _OwnerName( owner:number )
	local localPlayer:number = _LocalPlayer();
	if localPlayer ~= nil then
		local diplomacy:table = Players[ localPlayer ]:GetDiplomacy();
		if diplomacy ~= nil and owner ~= localPlayer and not diplomacy:HasMet( owner ) then
			return Locale.Lookup( "LOC_DIPLOPANEL_UNMET_PLAYER" );
		end
	end
	return PlotDescription_GetCivName( owner );
end

-- The city that owns the plot ("Rome"), else the owner's civilization; for the "taken by" notes.
local function _TakenBy( plot:table )
	if Cities ~= nil and Cities.GetPlotPurchaseCity ~= nil then
		local ok:boolean, city = pcall( Cities.GetPlotPurchaseCity, plot );
		if ok and city ~= nil then
			local cityPlot:table = Map.GetPlot( city:GetX(), city:GetY() );
			if cityPlot ~= nil and _IsRevealed( cityPlot ) then return Locale.Lookup( city:GetName() ); end
		end
	end
	return _OwnerName( plot:GetOwner() );
end

-- ===========================================================================
--	Can a city be founded here? (the game's rules, for any plot)
-- ===========================================================================
-- Returns true, or false and a short reason ("too close to Rome", "water", "mountain" ...). Cities on plots the player
-- has not seen are not named ("" = no reason to give: the plot is invalid, that is all we may say).
function SettleScan_CheckPlot( plot:table, cities:table )
	if plot == nil then return false, "edge of the map"; end
	if m_gridWidth == nil or cities == nil then _RefreshGrid(); end
	if not _IsRevealed( plot ) then return false, "unexplored"; end
	if plot:IsWater() then
		if plot:IsLake() then return false, "lake"; end
		return false, "water";
	end
	if plot:IsCity() then return false, "already a city"; end
	if plot:IsNaturalWonder() then return false, "natural wonder"; end
	if plot:IsMountain() then return false, "mountain"; end
	if plot:IsImpassable() then return false, "impassable"; end
	local owner:number = plot:GetOwner();
	local localPlayer:number = _LocalPlayer();
	if owner ~= nil and owner >= 0 and owner ~= localPlayer then
		return false, "owned by " .. _OwnerName( owner );
	end
	local minRange:number = _MinRange();
	local hidden:boolean = false;
	for _, city in ipairs( cities or _AllCities() ) do
		if _Dist( plot:GetX(), plot:GetY(), city.x, city.y ) <= minRange then
			local cityPlot:table = Map.GetPlot( city.x, city.y );
			if cityPlot ~= nil and _IsRevealed( cityPlot ) then
				return false, "too close to " .. _CityName( city );
			end
			hidden = true;
		end
	end
	if hidden then return false, ""; end
	return true;
end

-- The single answer for "can this unit found a city on this plot": true (second value true: no moves left, so the
-- city can only be founded next turn) or false and a reason (see SettleScan_CheckPlot; "" = none to give).
function SettleScan_CanFound( unit:table, plot:table, cities:table )
	local ok:boolean, reason:string = SettleScan_CheckPlot( plot, cities );
	if not ok then return false, reason; end
	if unit == nil then return true; end
	if unit:GetMovesRemaining() <= 0 then return true, true; end		-- the engine says no to everything then
	local engineOk:boolean, engine = pcall( UnitManager.CanStartOperation, unit, UnitOperationTypes.FOUND_CITY, plot, false, true );
	if engineOk and engine == false then
		for _, other in ipairs( Units.GetUnitsInPlot( plot ) ) do
			if other:GetOwner() ~= unit:GetOwner() and PlotDescription_IsUnitVisible( other ) then return false, "occupied by another unit"; end
		end
		return false, "the game does not allow a city here";
	end
	return true;
end

-- Names (lower case) of the resources a city on this plot would own at once: the 6 neighbours that no city owns yet.
-- Cheap (reads only those plots), for the map cursor.
function SettleScan_Ring1Resources( plot:table )
	local names:table = {};
	if plot == nil then return names; end
	if m_gridWidth == nil then _RefreshGrid(); end
	local seen:table = {};
	for _, around in ipairs( _Around( plot:GetX(), plot:GetY(), 1, Map.GetPlot ) ) do
		local p:table = around.plot;
		if around.d == 1 and _IsRevealed( p ) then
			local owner:number = p:GetOwner();
			local name:string = _Resource( p );
			if name ~= nil and ( owner == nil or owner < 0 ) and not seen[ name ] then
				seen[ name ] = true;
				table.insert( names, string.lower( name ) );
			end
		end
	end
	return names;
end

function SettleScan_CannotText( reason:string )
	if reason == nil or reason == "" then return "cannot settle"; end
	return "cannot settle: " .. reason;
end

-- ===========================================================================
--	Advisor
-- ===========================================================================
-- plot index -> { tooltip = string|nil, reasons = { { title, explanation, positive } } }
local function _AdvisorPicks()
	local picks:table = {};
	local localPlayer:number = _LocalPlayer();
	if localPlayer == nil then return picks; end
	local ok:boolean, err = pcall( function()
		local ai:table = Players[ localPlayer ]:GetGrandStrategicAI();
		if ai == nil then return; end
		for _, rec in pairs( ai:GetSettlementRecommendations( 5 ) ) do
			local entry:table = { reasons = {} };
			if rec.SettlingTooltip then entry.tooltip = CleanTextForSpeech( Locale.Lookup( rec.SettlingTooltip ) ); end
			for i = 0, ( rec.NumReasons or 0 ) - 1 do
				local title:string = rec[ "SettleTitle" .. tostring( i ) ];
				local explanation:string = rec[ "SettleExplanation" .. tostring( i ) ];
				table.insert( entry.reasons, {
					title = ( title ~= nil ) and CleanTextForSpeech( Locale.Lookup( title ) ) or "",
					explanation = ( explanation ~= nil ) and CleanTextForSpeech( Locale.Lookup( explanation ) ) or "",
					positive = rec[ "SettlePositive" .. tostring( i ) ] ~= false,
				} );
			end
			picks[ rec.SettlingLocation ] = entry;
		end
	end );
	if not ok then print( "SettleScan advisor error: " .. tostring( err ) ); end
	return picks;
end

-- ===========================================================================
--	Per-plot facts, read once per scan
-- ===========================================================================
local function _Info( ctx:table, plot:table )
	local index:number = plot:GetIndex();
	local info:table = ctx.infos[ index ];
	if info ~= nil then return info; end
	info = { revealed = _IsRevealed( plot ), food = 0, prod = 0 };
	ctx.infos[ index ] = info;
	if not info.revealed then return info; end
	info.food = plot:GetYield( ctx.foodIndex );
	info.prod = plot:GetYield( ctx.prodIndex );
	info.water = plot:IsWater();
	info.mountain = plot:IsMountain();
	info.lake = plot:IsLake();
	info.wonder = plot:IsNaturalWonder();
	info.owner = plot:GetOwner();
	info.resource, info.resourceClass = _Resource( plot );
	local feature:number = plot:GetFeatureType();
	if feature ~= nil and feature >= 0 and GameInfo.Features[ feature ] ~= nil then
		info.feature = GameInfo.Features[ feature ].FeatureType;
		info.featureName = GameInfo.Features[ feature ].Name;
	end
	local improvement:number = plot:GetImprovementType();
	info.camp = improvement ~= nil and improvement >= 0 and GameInfo.Improvements[ improvement ] ~= nil
		and GameInfo.Improvements[ improvement ].ImprovementType == "IMPROVEMENT_BARBARIAN_CAMP";
	-- A plot in the fog: what it holds now is not known to the player (a camp may have spawned there), only a camp
	-- that was seen there counts (the places list remembers it).
	if info.camp then
		local vis:table = PlayersVisibility ~= nil and PlayersVisibility[ ctx.localPlayer ] or nil;
		if vis ~= nil and not vis:IsVisible( index ) then
			info.camp = HubPlaces ~= nil and HubPlaces.IsCampRemembered ~= nil and HubPlaces.IsCampRemembered( index ) or false;
		end
	end
	if MapFeatureManager ~= nil and MapFeatureManager.CanSufferEruption ~= nil then
		local ok:boolean, erupts = pcall( MapFeatureManager.CanSufferEruption, plot );
		info.volcano = ok and erupts == true;
	end
	return info;
end

-- ===========================================================================
--	Scoring of one site
-- ===========================================================================
local function _Score( plot:table, ctx:table )
	local x:number, y:number = plot:GetX(), plot:GetY();
	local score:number = 0;
	local items:table = {};		-- { weight = , text = , long = } reasons, positive and negative
	local function Add( weight:number, text:string, long:string )
		score = score + weight;
		if text ~= nil then table.insert( items, { weight = weight, text = text, long = long or text } ); end
	end

	-- water: fresh water and the coast together are worth at most 8 (a coastal river is not twice as good)
	local waterText:string = nil;
	if plot:IsRiver() then waterText = "river";
	else
		for _, around in ipairs( ctx.GetAround( x, y, 1 ) ) do
			local info:table = _Info( ctx, around.plot );
			if info.lake then waterText = "lake"; break; end
			if info.feature == "FEATURE_OASIS" then waterText = "oasis"; break; end
		end
		if waterText == nil and _IsFreshWater( plot ) then waterText = "fresh water"; end
	end
	local coastal:boolean = plot:IsCoastalLand();
	local water:number = 0;
	if waterText ~= nil then water = water + 6; Add( 6, waterText, ( waterText == "fresh water" ) and waterText or ( "fresh water: " .. waterText ) ); end
	if coastal then water = water + 3; Add( 3, "coast" ); end
	if water > 8 then score = score - ( water - 8 ); end
	if waterText == nil and not coastal then Add( -4, "no fresh water" ); end

	-- site
	local terrain:table = GameInfo.Terrains[ plot:GetTerrainType() ];
	if terrain ~= nil and ( terrain.TerrainType == "TERRAIN_GRASS_HILLS" or terrain.TerrainType == "TERRAIN_PLAINS_HILLS"
			or terrain.TerrainType == "TERRAIN_DESERT_HILLS" or terrain.TerrainType == "TERRAIN_TUNDRA_HILLS" or terrain.TerrainType == "TERRAIN_SNOW_HILLS" ) then
		Add( 2, "hills", "hills: production and defense" );
	end
	local centerResource:string = _Info( ctx, plot ).resource;
	if centerResource ~= nil then Add( -1, "on " .. string.lower( centerResource ), "the city would sit on " .. centerResource ); end

	-- hazards (Gathering Storm API, absent in the base game)
	if RiverManager ~= nil and RiverManager.CanBeFlooded ~= nil then
		local ok:boolean, flood = pcall( RiverManager.CanBeFlooded, plot );
		if ok and flood then Add( -3, "floods", "the river floods this plot" ); end
	end
	if TerrainManager ~= nil and TerrainManager.GetCoastalLowlandType ~= nil and TerrainManager.IsProtected ~= nil then
		local ok:boolean, lowland = pcall( function()
			if TerrainManager.IsProtected( plot ) then return -1; end
			return TerrainManager.GetCoastalLowlandType( plot );
		end );
		if ok and lowland ~= nil and lowland > -1 then Add( -3, "coastal flooding", "coastal lowland: sea level rise will flood it" ); end
	end

	-- yields of rings 1 and 2, resources, mountains, wonders, hazards and borders around
	local foodTotal:number, prodTotal:number, known:number, total:number, land:number = 0, 0, 0, 0, 0;
	local weighted:number = 0;
	local mountains:number = 0;
	local volcano:boolean = false;
	local foreign:number = 0;
	local camp:boolean = false;
	local wonder:string = nil;
	local resources:table = {};
	local ringStats:table = { { food = 0, production = 0, known = 0 }, { food = 0, production = 0, known = 0 } };
	for _, around in ipairs( ctx.GetAround( x, y, 3 ) ) do
		local p:table = around.plot;
		local d:number = around.d;
		local info:table = _Info( ctx, p );
		if d >= 1 and d <= 2 then
			total = total + 1;
			local weight:number = ( d == 1 ) and 1 or 0.5;
			if info.revealed then
				known = known + 1;
				ringStats[ d ].food = ringStats[ d ].food + info.food;
				ringStats[ d ].production = ringStats[ d ].production + info.prod;
				ringStats[ d ].known = ringStats[ d ].known + 1;
				foodTotal = foodTotal + info.food;
				prodTotal = prodTotal + info.prod;
				weighted = weighted + weight * ( info.food + 0.7 * info.prod );
				if not info.water and not info.mountain then land = land + 1; end
			else
				weighted = weighted + weight * 1.5;		-- unknown: counts as a poor plot, not an average one
			end
		end
		if info.revealed then
			if d >= 1 then
				if info.resource ~= nil and d <= 3 then
					table.insert( resources, { name = info.resource, class = info.resourceClass, d = d, owner = info.owner, plot = p } );
				end
				if d == 1 and info.mountain then mountains = mountains + 1; end
				if info.wonder then
					wonder = wonder or ( ( info.featureName ~= nil ) and Locale.Lookup( info.featureName ) or "natural wonder" );
				end
				if d <= 2 and info.volcano then volcano = true; end
				if info.camp then camp = true; end
			end
			if d <= 2 and info.owner ~= nil and info.owner >= 0 and info.owner ~= ctx.localPlayer then foreign = foreign + 1; end
		end
	end
	score = score + 0.7 * weighted;
	if known >= 8 then
		local avgFood:number = foodTotal / known;
		local avgProd:number = prodTotal / known;
		if avgFood >= 2.2 then table.insert( items, { weight = 3, text = "good food", long = "good food around" } ); end
		if avgProd >= 1 then table.insert( items, { weight = 3, text = "good production", long = "good production around" } ); end
		if avgFood < 1.3 then Add( -4, "poor food", "poor food around" );
		elseif avgFood < 1.8 and avgProd < 0.7 then Add( -2, "poor land", "little food and production around" ); end
		if land < 4 then Add( -3, "little land", "only " .. land .. " workable land tiles within 2 tiles" ); end
	elseif total > 0 then
		Add( -2, "little explored", "little explored around" );
	end

	-- resources by ring, the closest ring first, each name once; plots a city owns already do not count
	table.sort( resources, function( a, b )
		if a.d ~= b.d then return a.d < b.d; end
		return a.name < b.name;
	end );
	local rings:table = { { free = {}, taken = {}, weight = 0 }, { free = {}, taken = {}, weight = 0 }, { free = {}, taken = {}, weight = 0 } };
	local seen:table = {};
	for _, r in ipairs( resources ) do
		if ( r.owner == nil or r.owner < 0 ) and not seen[ r.name ] then
			seen[ r.name ] = true;
			table.insert( rings[ r.d ].free, { name = r.name, class = r.class } );
			rings[ r.d ].weight = rings[ r.d ].weight + ( RING_WEIGHTS[ r.class ] or RING_WEIGHTS.bonus )[ r.d ];
		end
	end
	for _, r in ipairs( resources ) do
		if r.owner ~= nil and r.owner >= 0 and not seen[ r.name ] then
			seen[ r.name ] = true;
			table.insert( rings[ r.d ].taken, { name = r.name, class = r.class, by = _TakenBy( r.plot ) } );
		end
	end
	for ring = 1, 3 do
		local names:table = {};
		for _, r in ipairs( rings[ ring ].free ) do table.insert( names, string.lower( r.name ) ); end
		if #names > 0 then
			score = score + rings[ ring ].weight;
			if ring <= 2 then		-- ring 3 is in the detail only
				table.insert( items, { weight = rings[ ring ].weight, text = "ring " .. ring .. ": " .. table.concat( names, ", " ), long = "", ring = true } );
			end
		end
	end
	if mountains > 0 then Add( math.min( mountains, 2 ), "mountains", mountains .. " mountain" .. ( mountains > 1 and "s" or "" ) .. " next to it" ); end
	if wonder ~= nil then Add( 3, string.lower( wonder ), "natural wonder: " .. wonder ); end
	if volcano then Add( -4, "volcano near", "a volcano within 2 tiles" ); end
	if camp then Add( -5, "barbarian camp", "a barbarian camp within 3 tiles" ); end
	if foreign > 0 then Add( -0.7 * foreign, "foreign border", foreign .. " plots within 2 tiles belong to another civilization" ); end

	-- crowding: own cities that are close share tiles
	local nearest:table, nearestD:number = nil, 99;
	for _, city in ipairs( ctx.cities ) do
		if city.owner == ctx.localPlayer then
			local d:number = _Dist( x, y, city.x, city.y );
			if d < nearestD then nearest, nearestD = city, d; end
		end
	end
	if nearest ~= nil and nearestD < 5 then
		local name:string = _CityName( nearest );
		Add( -1.5 * ( 5 - nearestD ), "close to " .. name, "only " .. nearestD .. " tiles from " .. name .. ", they share tiles" );
	end

	-- danger
	local enemies:number = 0;
	local barbarians:boolean = false;
	for _, enemy in ipairs( ctx.hostiles ) do
		if _Dist( x, y, enemy.x, enemy.y ) <= 3 then
			enemies = enemies + 1;
			if enemy.barbarian then barbarians = true; end
		end
	end
	if enemies > 0 then
		Add( -4 * math.min( enemies, 2 ), barbarians and "barbarians nearby" or "enemies nearby",
			enemies .. ( enemies == 1 and " hostile unit" or " hostile units" ) .. " within 3 tiles" );
	end

	-- order the reasons: most weighty first, positive before negative of the same size
	table.sort( items, function( a, b )
		if math.abs( a.weight ) ~= math.abs( b.weight ) then return math.abs( a.weight ) > math.abs( b.weight ); end
		return a.weight > b.weight;
	end );
	return score, items, { food = foodTotal, production = prodTotal, known = known, total = total, rings = rings, ringStats = ringStats };
end

-- ===========================================================================
--	G6 context (distances to cities, rivals, defensibility) and G8 wording. Pure functions on candidate fields.
--	c.context = { own = { name, d } | nil, rival = { name, civ, d } | nil, hills = bool, sides = number }
-- ===========================================================================
local function _Tiles( n:number )
	return n .. ( n == 1 and " tile" or " tiles" );
end

-- ", 4 tiles from Rome, 7 from Kyoto (Japan)" (empty when no city is known)
function SettleScan_DistanceText( c:table )
	local ctx:table = c.context;
	if ctx == nil then return ""; end
	local text:string = "";
	if ctx.own ~= nil then text = text .. ", " .. _Tiles( ctx.own.d ) .. " from " .. ctx.own.name; end
	if ctx.rival ~= nil then text = text .. ", " .. ctx.rival.d .. " from " .. ctx.rival.name .. " (" .. ctx.rival.civ .. ")"; end
	return text;
end

-- "Between Rome and Japan. Hills. 3 of 6 sides mountain or water" (empty when there is nothing to say)
function SettleScan_SpaceText( c:table )
	local ctx:table = c.context;
	if ctx == nil then return ""; end
	local parts:table = {};
	if ctx.own ~= nil and ctx.rival ~= nil and ctx.rival.d < ctx.own.d then
		table.insert( parts, "Between " .. ctx.own.name .. " and " .. ctx.rival.civ );
	elseif ctx.own ~= nil and ctx.rival == nil then
		table.insert( parts, "Behind " .. ctx.own.name );
	end
	if ctx.hills then table.insert( parts, "On hills" ); end
	if ctx.sides >= SIDES_NOTE then table.insert( parts, ctx.sides .. " of 6 sides mountain or water" ); end
	return table.concat( parts, ". " );
end

-- The first n good and m bad reasons as "river, coast, silk, but floods, poor food" (empty when there are none).
function SettleScan_ReasonList( c:table, n:number, m:number )
	local parts:table = {};
	for i = 1, math.min( n, #c.reasons ) do table.insert( parts, c.reasons[i] ); end
	local bad:table = {};
	for i = 1, math.min( m, #c.negatives ) do table.insert( bad, c.negatives[i] ); end
	local text:string = table.concat( parts, ", " );
	if #bad > 0 then text = text .. ( #parts > 0 and ", " or "" ) .. "but " .. table.concat( bad, ", " ); end
	return text;
end

-- "same" | "clearly" | "between" | nil (no comparison: here cannot found, or here is the best, or no spot)
function SettleScan_Compare( scan:table )
	local here:table, best:table = scan.here, scan.best;
	if here == nil or best == nil or best.here then return nil; end
	local gap:number = best.score - here.score;
	if gap < SAME_GAP then return "same"; end
	if gap > CLEAR_GAP then return "clearly"; end
	return "between";
end

-- The sentence said when a settler is selected. foundKey = the Found City key ("B"), hasMoves = it can found now.
function SettleScan_Sentence( scan:table, foundKey:string, hasMoves:boolean )
	local here:table, best:table = scan.here, scan.best;
	local function Reasons( c:table, n:number, m:number )
		local list:string = SettleScan_ReasonList( c, n, m );
		return ( list ~= "" ) and ( ", " .. list ) or "";
	end
	local text:string;
	if here ~= nil then
		text = "Can settle here" .. Reasons( { reasons = {}, negatives = here.negatives }, 0, 2 );
	elseif scan.hereReason ~= nil and scan.hereReason ~= "" then
		text = "Cannot settle here: " .. scan.hereReason;
	else
		text = "Cannot settle here";
	end
	if best == nil then return text .. ". No spot found nearby."; end
	if best.here then
		local list:string = SettleScan_ReasonList( best, 3, 2 );
		return ( here ~= nil and "Can settle here" or text ) .. ", this is the best spot nearby" .. ( list ~= "" and ( ": " .. list ) or "" )
			.. ( hasMoves and ( ". " .. foundKey .. " to found." ) or ( ". " .. foundKey .. " to found next turn." ) );
	end
	local verdict:string = SettleScan_Compare( scan );
	if verdict == "same" then
		local list:string = SettleScan_ReasonList( here, 3, 2 );
		return "Here is good" .. ( list ~= "" and ( ": " .. list ) or "" ) .. ". Best nearby is about the same. " .. foundKey
			.. ( hasMoves and " founds here" or " founds here next turn" );
	end
	local turns:string = best.turns .. ( best.turns == 1 and " turn" or " turns" );
	if verdict == "clearly" then
		return "Best spot is clearly better: " .. best.relative .. Reasons( best, 3, 2 ) .. ", " .. turns
			.. SettleScan_DistanceText( best ) .. ". X to browse";
	end
	text = text .. ". Best: " .. best.relative .. ", " .. turns .. Reasons( best, 3, 2 );
	if best.recommended then text = text .. ", recommended"; end
	return text .. SettleScan_DistanceText( best ) .. ". X to browse.";
end

-- Fills c.context from the cities list.
local function _Context( c:table, ctx:table )
	local own:table, ownD:number = nil, 99;
	local rival:table, rivalD:number = nil, 99;
	for _, city in ipairs( ctx.cities ) do
		local d:number = _Dist( c.x, c.y, city.x, city.y );
		if city.owner == ctx.localPlayer then
			if d < ownD then own, ownD = city, d; end
		elseif d <= RIVAL_RANGE and d < rivalD then
			local player:table = Players[ city.owner ];
			local cityPlot:table = Map.GetPlot( city.x, city.y );
			if player ~= nil and player:IsMajor() and cityPlot ~= nil and _IsRevealed( cityPlot ) then rival, rivalD = city, d; end
		end
	end
	local result:table = { hills = false, sides = 0 };
	if own ~= nil then result.own = { name = _CityName( own ), d = ownD }; end
	if rival ~= nil then result.rival = { name = _CityName( rival ), civ = _OwnerName( rival.owner ), d = rivalD }; end
	local terrain:table = GameInfo.Terrains[ c.plot:GetTerrainType() ];
	result.hills = terrain ~= nil and string.find( terrain.TerrainType, "_HILLS", 1, true ) ~= nil;
	for _, around in ipairs( ctx.GetAround( c.x, c.y, 1 ) ) do
		if around.d == 1 then
			local info:table = _Info( ctx, around.plot );
			if info.revealed and ( info.mountain or info.water ) then result.sides = result.sides + 1; end
		end
	end
	c.context = result;
end

-- ===========================================================================
--	Scan
-- ===========================================================================
local function _Detail( c:table )
	local parts:table = {};
	local where:string = c.here and "Here" or ( c.relative or "" );
	if not c.here then
		where = where .. ", " .. c.turns .. ( c.turns == 1 and " turn" or " turns" );
	end
	table.insert( parts, where );
	local space:string = SettleScan_SpaceText( c );
	if space ~= "" then table.insert( parts, space ); end
	if c.recommended then table.insert( parts, "recommended by the advisor" ); end
	if c.advisor ~= nil then
		if c.advisor.tooltip ~= nil then table.insert( parts, c.advisor.tooltip ); end
		for _, r in ipairs( c.advisor.reasons ) do
			table.insert( parts, "advisor " .. ( r.positive and "plus" or "minus" ) .. ": " .. r.title .. ( r.explanation ~= "" and ( ", " .. r.explanation ) or "" ) );
		end
	end
	for _, item in ipairs( c.items ) do
		if not item.ring then table.insert( parts, ( item.weight < 0 and "minus: " or "" ) .. item.long ); end
	end
	if c.totals ~= nil and c.totals.rings ~= nil then
		for ring = 1, 3 do
			local entries:table = {};
			for _, r in ipairs( c.totals.rings[ ring ].free ) do table.insert( entries, r.name .. " (" .. r.class .. ")" ); end
			for _, r in ipairs( c.totals.rings[ ring ].taken ) do table.insert( entries, r.name .. " (" .. r.class .. ", taken by " .. r.by .. ")" ); end
			local label:string = ( ring == 1 ) and "Ring 1, the city's first tiles" or ( "Ring " .. ring );
			if #entries > 0 then
				table.insert( parts, label .. ": " .. table.concat( entries, ", " ) );
			elseif ring == 1 then
				table.insert( parts, label .. ": no resources" );
			end
		end
	end
	if c.totals ~= nil and c.totals.ringStats ~= nil then
		for ring = 1, 2 do
			local st:table = c.totals.ringStats[ ring ];
			if st.known > 0 then
				table.insert( parts, "ring " .. ring .. ": " .. st.food .. " food, " .. st.production .. " production on " .. st.known .. ( st.known == 1 and " tile" or " tiles" ) );
			end
		end
	end
	return table.concat( parts, ". " );
end

local m_scanKey:string = nil;
local m_scan:table = nil;

function SettleScan_Scan( unit:table, force:boolean )
	local localPlayer:number = _LocalPlayer();
	if unit == nil or localPlayer == nil then return { list = {} }; end

	local cities:table = _AllCities();
	local key:string = table.concat( { localPlayer, unit:GetID(), unit:GetX(), unit:GetY(), Game.GetCurrentGameTurn(), unit:GetMovesRemaining(), m_citiesKey }, ":" );
	if not force and key == m_scanKey and m_scan ~= nil then return m_scan; end

	_RefreshGrid();
	if HubPlaces ~= nil and HubPlaces.RefreshSeen ~= nil then pcall( HubPlaces.RefreshSeen ); end		-- the camps in view now are remembered
	local result:table = { list = {} };
	local plotCache:table = {};
	local function PlotAt( x:number, y:number )
		local index:number = y * m_gridWidth + x;
		local plot:table = plotCache[ index ];
		if plot == nil then
			plot = Map.GetPlot( x, y );
			plotCache[ index ] = plot;
		end
		return plot;
	end
	local ctx:table = {
		localPlayer = localPlayer,
		cities = cities,
		hostiles = _HostileUnits(),
		infos = {},
		foodIndex = GameInfo.Yields[ "YIELD_FOOD" ].Index,
		prodIndex = GameInfo.Yields[ "YIELD_PRODUCTION" ].Index,
	};
	local aroundCache:table = {};
	ctx.GetAround = function( x:number, y:number, radius:number )
		local cacheKey:string = x .. "," .. y;
		local entry:table = aroundCache[ cacheKey ];
		if entry == nil then
			entry = _Around( x, y, 3, PlotAt );
			aroundCache[ cacheKey ] = entry;
		end
		if radius >= 3 then return entry; end
		local list:table = {};
		for _, around in ipairs( entry ) do
			if around.d <= radius then table.insert( list, around ); end
		end
		return list;
	end

	local advisor:table = _AdvisorPicks();
	local unitPlot:table = Map.GetPlot( unit:GetX(), unit:GetY() );
	local unitIndex:number = unitPlot:GetIndex();

	-- candidate plots: the advisor's, then everything revealed nearby
	local seenIndex:table = {};
	local candidates:table = {};
	local function Consider( plot:table )
		if plot == nil or seenIndex[ plot:GetIndex() ] then return; end
		seenIndex[ plot:GetIndex() ] = true;
		local ok:boolean, reason = SettleScan_CanFound( unit, plot, cities );
		if plot:GetIndex() == unitIndex then
			result.hereReason = ( not ok ) and reason or nil;
		end
		if not ok then return; end
		local score:number, items:table, totals:table = _Score( plot, ctx );
		local pick:table = advisor[ plot:GetIndex() ];
		if pick ~= nil then score = score + ADVISOR_BONUS; end
		table.insert( candidates, {
			key = tostring( plot:GetIndex() ), plotIndex = plot:GetIndex(), plot = plot, x = plot:GetX(), y = plot:GetY(),
			distance = _Dist( unit:GetX(), unit:GetY(), plot:GetX(), plot:GetY() ),
			static = score, score = score, items = items, totals = totals, advisor = pick, recommended = pick ~= nil,
			here = plot:GetIndex() == unitIndex,
		} );
	end
	for plotIndex, _ in pairs( advisor ) do Consider( Map.GetPlotByIndex( plotIndex ) ); end
	for _, around in ipairs( _Around( unit:GetX(), unit:GetY(), SCAN_RADIUS, PlotAt ) ) do Consider( around.plot ); end
	if result.hereReason == nil and not seenIndex[ unitIndex ] then
		local _, reason = SettleScan_CheckPlot( unitPlot, cities );
		result.hereReason = reason;
	end

	-- travel: path finding down the list sorted by static score until enough distinct sites are reachable (the spots
	-- of an unreachable landmass must not use up the slots). Plots within 2 tiles of one already tried are the same
	-- site (and the same landmass): not tried again.
	table.sort( candidates, function( a, b ) return a.static > b.static; end );
	local reachable:table = {};
	local tried:table = {};
	local sites:number = 0;
	local pathed:number = 0;
	for _, c in ipairs( candidates ) do
		if c.here then
			c.turns = 0;
			table.insert( reachable, c );
			table.insert( tried, c );
			sites = sites + 1;
		elseif c.recommended or ( sites < MAX_CANDIDATES and pathed < MAX_PATHS ) then
			local duplicate:boolean = false;
			if not c.recommended then
				for _, other in ipairs( tried ) do
					if _Dist( c.x, c.y, other.x, other.y ) <= 2 then duplicate = true; break; end
				end
			end
			if not duplicate then
				pathed = pathed + 1;
				table.insert( tried, c );
				local path:table = UnitManager.GetMoveToPathEx( unit, c.plotIndex );
				if path ~= nil and path.plots ~= nil and #path.plots >= 2 then
					c.turns = path.turns[ #path.turns ] or 1;
					c.score = c.static - TURN_COST * c.turns;
					table.insert( reachable, c );
					sites = sites + 1;
				end
			end
		end
	end
	table.sort( reachable, function( a, b )
		if a.score ~= b.score then return a.score > b.score; end
		return a.distance < b.distance;
	end );

	-- one entry per city site
	local chosen:table = {};
	for _, c in ipairs( reachable ) do
		local keep:boolean = true;
		if not c.here and not c.recommended then
			for _, other in ipairs( chosen ) do
				if _Dist( c.x, c.y, other.x, other.y ) <= 2 then keep = false; break; end
			end
		end
		if keep and ( #chosen < MAX_CANDIDATES or c.here ) then table.insert( chosen, c ); end
	end

	local origin:table = unitPlot;
	for _, c in ipairs( chosen ) do
		c.relative = PlotDescription_GetRelative( origin, c.plot );
		c.reasons = {};
		c.negatives = {};
		for _, item in ipairs( c.items ) do
			if item.weight > 0 then
				if #c.reasons < 6 then table.insert( c.reasons, item.text ); end
			elseif item.weight < 0 then
				if #c.negatives < 3 then table.insert( c.negatives, item.text ); end
			end
		end
		_Context( c, ctx );
		c.detail = _Detail( c );
		if c.here then result.here = c; end
	end
	result.list = chosen;
	result.best = chosen[1];
	m_scanKey, m_scan = key, result;
	return result;
end
