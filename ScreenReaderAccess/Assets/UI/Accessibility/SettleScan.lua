-- ===========================================================================
--	SettleScan: where can the selected settler found a city, and where is it best? Pure data, no speech.
--
--	SettleScan_CheckPlot( plot )          -> canSettle:boolean, reason:string   (the game's found-city rules, tested for any plot)
--	SettleScan_Scan( unit )               -> { here = candidate|nil, hereReason = string|nil, list = { candidates sorted by score },
--	                                           best = candidate|nil }
--	candidate: { key, plotIndex, x, y, distance, turns, score, recommended, reasons = { short phrases, most important
--	             first }, detail = <all reasons as one string for Space>, here = true for the settler's own plot }
--
--	Candidates: (a) the game's advisor (GrandStrategicAI:GetSettlementRecommendations, shown as icons by the settler
--	lens), (b) every revealed plot within SCAN_RADIUS of the settler where a city can be founded.
--
--	Score (higher is better; only the order matters, tuned by looking at what it picks in a real game):
--	  water       river / lake / oasis (fresh water) +8; coastal +4 (both add up); neither: -4 "no fresh water"
--	  yields      0.4 * ( ring 1 plots + 0.5 * ring 2 plots ) of ( food + 0.7 * production ); unknown plots count as average
--	  resources   within 2 tiles: luxury +3, strategic +2, bonus +1; the third ring counts half. The city plot itself: -1
--	  site        hills +2 (production, defense); mountain next to it +1 each (max 2); natural wonder within 3: +3
--	  hazards     (Gathering Storm API, when present) flooding river or coastal lowlands on the city plot -3, volcano
--	              within 2 -4
--	  crowding    own cities closer than 5 tiles: -1.5 per missing tile; foreign borders within 2 tiles: -0.7 per plot
--	  danger      visible barbarian/enemy soldiers within 3: -4 each (max 2); a barbarian camp within 3: -5
--	  travel      -1.2 per turn needed to reach it (the settler's own pathfinding); unreachable spots are dropped
--	  advisor     +6 and "recommended" for the advisor's picks
--	Candidates within 2 tiles of a better one are dropped (they are the same city site), except the settler's plot and
--	the advisor picks.
-- ===========================================================================

include( "ScreenReader" );
include( "PlotDescription" );

local SCAN_RADIUS		:number = 6;
local MAX_CANDIDATES	:number = 12;
local PATH_CANDIDATES	:number = 30;	-- path finding is only done for the best of this many by static score
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

-- Plots within `radius` of (x, y) as { plot = , d = } (the centre has d = 0).
local function _Around( x:number, y:number, radius:number )
	local width:number, height:number = Map.GetGridSize();
	local list:table = {};
	for dy = -radius, radius do
		local py:number = y + dy;
		if py >= 0 and py < height then
			for dx = -radius - 1, radius + 1 do
				local px:number = x + dx;
				if Map.IsWrapX() then px = px % width; end
				if px >= 0 and px < width then
					local d:number = Map.GetPlotDistance( x, y, px, py );
					if d <= radius then
						local plot:table = Map.GetPlot( px, py );
						if plot ~= nil then table.insert( list, { plot = plot, d = d } ); end
					end
				end
			end
		end
	end
	return list;
end

-- All cities of all players: { x, y, name, owner }.
local function _AllCities()
	local cities:table = {};
	for playerID = 0, 63 do
		local player:table = Players[ playerID ];
		if player ~= nil and player:IsAlive() and not player:IsBarbarian() then
			for _, city in player:GetCities():Members() do
				table.insert( cities, { x = city:GetX(), y = city:GetY(), name = Locale.Lookup( city:GetName() ), owner = playerID } );
			end
		end
	end
	return cities;
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

-- ===========================================================================
--	Can a city be founded here? (the game's rules, for any plot)
-- ===========================================================================
-- Returns true, or false and a short reason ("too close to Rome", "water", "mountain" ...).
function SettleScan_CheckPlot( plot:table, cities:table )
	if plot == nil then return false, "edge of the map"; end
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
		return false, "owned by " .. PlotDescription_GetCivName( owner );
	end
	local minRange:number = _MinRange();
	for _, city in ipairs( cities or _AllCities() ) do
		if Map.GetPlotDistance( plot:GetX(), plot:GetY(), city.x, city.y ) <= minRange then
			local cityPlot:table = Map.GetPlot( city.x, city.y );
			if cityPlot ~= nil and _IsRevealed( cityPlot ) then
				return false, "too close to " .. city.name;
			end
			return false, "too close to a city";
		end
	end
	return true;
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

	-- water
	local waterText:string = nil;
	if plot:IsRiver() then waterText = "river";
	else
		for _, around in ipairs( ctx.GetAround( x, y, 1 ) ) do
			if around.plot:IsLake() then waterText = "lake"; break; end
			local feature:number = around.plot:GetFeatureType();
			if feature ~= nil and feature >= 0 and GameInfo.Features[ feature ] ~= nil and GameInfo.Features[ feature ].FeatureType == "FEATURE_OASIS" then
				waterText = "oasis";
				break;
			end
		end
		if waterText == nil and _IsFreshWater( plot ) then waterText = "fresh water"; end
	end
	local coastal:boolean = plot:IsCoastalLand();
	if waterText ~= nil then Add( 8, waterText, "fresh water: " .. waterText ); end
	if coastal then Add( 4, "coast" ); end
	if waterText == nil and not coastal then Add( -4, "no fresh water" ); end

	-- site
	local terrain:table = GameInfo.Terrains[ plot:GetTerrainType() ];
	if terrain ~= nil and ( terrain.TerrainType == "TERRAIN_GRASS_HILLS" or terrain.TerrainType == "TERRAIN_PLAINS_HILLS"
			or terrain.TerrainType == "TERRAIN_DESERT_HILLS" or terrain.TerrainType == "TERRAIN_TUNDRA_HILLS" or terrain.TerrainType == "TERRAIN_SNOW_HILLS" ) then
		Add( 2, "hills", "hills: production and defense" );
	end
	local centerResource:string = _Resource( plot );
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
	local foodTotal:number, prodTotal:number, known:number, total:number = 0, 0, 0, 0;
	local weighted:number = 0;
	local mountains:number = 0;
	local volcano:boolean = false;
	local foreign:number = 0;
	local camp:boolean = false;
	local wonder:string = nil;
	local resources:table = {};
	for _, around in ipairs( ctx.GetAround( x, y, 3 ) ) do
		local p:table = around.plot;
		local d:number = around.d;
		if d >= 1 and d <= 2 then
			total = total + 1;
			local weight:number = ( d == 1 ) and 1 or 0.5;
			if _IsRevealed( p ) then
				local food:number = p:GetYield( ctx.foodIndex );
				local prod:number = p:GetYield( ctx.prodIndex );
				known = known + 1;
				foodTotal = foodTotal + food;
				prodTotal = prodTotal + prod;
				weighted = weighted + weight * ( food + 0.7 * prod );
			else
				weighted = weighted + weight * 2.4;		-- unknown: an average plot
			end
		end
		if _IsRevealed( p ) then
			if d >= 1 then
				local name:string, class:string = _Resource( p );
				if name ~= nil then
					local near:boolean = d <= 2;
					local value:number = 1;
					if class == "luxury" then value = 3; elseif class == "strategic" then value = 2; elseif class == "artifact" then value = 0.5; end
					if not near then value = value / 2; end
					table.insert( resources, { name = name, class = class, value = value, d = d } );
				end
				if d == 1 and p:IsMountain() then mountains = mountains + 1; end
				if p:IsNaturalWonder() then
					local feature:table = GameInfo.Features[ p:GetFeatureType() ];
					wonder = wonder or ( ( feature ~= nil ) and Locale.Lookup( feature.Name ) or "natural wonder" );
				end
				if d <= 2 and MapFeatureManager ~= nil and MapFeatureManager.CanSufferEruption ~= nil then
					local ok:boolean, erupts = pcall( MapFeatureManager.CanSufferEruption, p );
					if ok and erupts then volcano = true; end
				end
				local improvement:number = p:GetImprovementType();
				if improvement ~= nil and improvement >= 0 and GameInfo.Improvements[ improvement ] ~= nil
						and GameInfo.Improvements[ improvement ].ImprovementType == "IMPROVEMENT_BARBARIAN_CAMP" then
					camp = true;
				end
			end
			local owner:number = p:GetOwner();
			if d <= 2 and owner ~= nil and owner >= 0 and owner ~= ctx.localPlayer then foreign = foreign + 1; end
		end
	end
	score = score + 0.4 * weighted;
	if total > 0 then
		local avgFood:number = ( known > 0 ) and ( foodTotal / known ) or 0;
		local avgProd:number = ( known > 0 ) and ( prodTotal / known ) or 0;
		if known >= 8 then
			if avgFood >= 2.2 then table.insert( items, { weight = 3, text = "good food", long = "good food around" } ); end
			if avgProd >= 1 then table.insert( items, { weight = 3, text = "good production", long = "good production around" } ); end
			if avgFood < 1.3 then table.insert( items, { weight = -3, text = "poor food", long = "poor food around" } ); end
		end
		if known < 8 then table.insert( items, { weight = -1, text = "little explored", long = "little explored around" } ); end
	end

	-- resources: best first, each name once
	table.sort( resources, function( a, b ) return a.value > b.value; end );
	local seen:table = {};
	for _, r in ipairs( resources ) do
		if not seen[ r.name ] then
			seen[ r.name ] = true;
			Add( r.value, string.lower( r.name ), r.name .. " (" .. r.class .. "), " .. r.d .. ( r.d == 1 and " tile" or " tiles" ) .. " away" );
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
			local d:number = Map.GetPlotDistance( x, y, city.x, city.y );
			if d < nearestD then nearest, nearestD = city, d; end
		end
	end
	if nearest ~= nil and nearestD < 5 then
		Add( -1.5 * ( 5 - nearestD ), "close to " .. nearest.name, "only " .. nearestD .. " tiles from " .. nearest.name .. ", they share tiles" );
	end

	-- danger
	local enemies:number = 0;
	local barbarians:boolean = false;
	for _, enemy in ipairs( ctx.hostiles ) do
		if Map.GetPlotDistance( x, y, enemy.x, enemy.y ) <= 3 then
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
	return score, items, { food = foodTotal, production = prodTotal, known = known, total = total };
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
	if c.recommended then table.insert( parts, "recommended by the advisor" ); end
	if c.advisor ~= nil then
		if c.advisor.tooltip ~= nil then table.insert( parts, c.advisor.tooltip ); end
		for _, r in ipairs( c.advisor.reasons ) do
			table.insert( parts, "advisor " .. ( r.positive and "plus" or "minus" ) .. ": " .. r.title .. ( r.explanation ~= "" and ( ", " .. r.explanation ) or "" ) );
		end
	end
	for _, item in ipairs( c.items ) do
		table.insert( parts, ( item.weight < 0 and "minus: " or "" ) .. item.long );
	end
	if c.totals ~= nil and c.totals.known > 0 then
		table.insert( parts, "within 2 tiles " .. c.totals.food .. " food and " .. c.totals.production .. " production on " .. c.totals.known .. " known tiles" );
	end
	return table.concat( parts, ". " );
end

function SettleScan_Scan( unit:table )
	local result:table = { list = {} };
	local localPlayer:number = _LocalPlayer();
	if unit == nil or localPlayer == nil then return result; end

	local ctx:table = {
		localPlayer = localPlayer,
		cities = _AllCities(),
		hostiles = _HostileUnits(),
		foodIndex = GameInfo.Yields[ "YIELD_FOOD" ].Index,
		prodIndex = GameInfo.Yields[ "YIELD_PRODUCTION" ].Index,
	};
	local aroundCache:table = {};
	ctx.GetAround = function( x:number, y:number, radius:number )
		local key:string = x .. "," .. y;
		local entry:table = aroundCache[ key ];
		if entry == nil then
			entry = _Around( x, y, 3 );
			aroundCache[ key ] = entry;
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
		local ok:boolean, reason:string = SettleScan_CheckPlot( plot, ctx.cities );
		if plot:GetIndex() == unitIndex then
			result.hereReason = ( not ok ) and reason or nil;
		end
		if not ok then return; end
		-- the engine can test a remote plot too (it agreed with the rules above everywhere in testing): it has the last word
		local engineOk:boolean, engine = pcall( UnitManager.CanStartOperation, unit, UnitOperationTypes.FOUND_CITY, plot, false, true );
		if engineOk and engine == false then return; end
		local score:number, items:table, totals:table = _Score( plot, ctx );
		local pick:table = advisor[ plot:GetIndex() ];
		if pick ~= nil then score = score + ADVISOR_BONUS; end
		table.insert( candidates, {
			key = tostring( plot:GetIndex() ), plotIndex = plot:GetIndex(), plot = plot, x = plot:GetX(), y = plot:GetY(),
			distance = Map.GetPlotDistance( unit:GetX(), unit:GetY(), plot:GetX(), plot:GetY() ),
			static = score, score = score, items = items, totals = totals, advisor = pick, recommended = pick ~= nil,
			here = plot:GetIndex() == unitIndex,
		} );
	end
	for plotIndex, _ in pairs( advisor ) do Consider( Map.GetPlotByIndex( plotIndex ) ); end
	for _, around in ipairs( _Around( unit:GetX(), unit:GetY(), SCAN_RADIUS ) ) do Consider( around.plot ); end
	if result.hereReason == nil and not seenIndex[ unitIndex ] then
		local _, reason = SettleScan_CheckPlot( unitPlot, ctx.cities );
		result.hereReason = reason;
	end

	-- travel: path finding only for the best candidates
	table.sort( candidates, function( a, b ) return a.static > b.static; end );
	local reachable:table = {};
	local pathed:number = 0;
	for _, c in ipairs( candidates ) do
		if c.here then
			c.turns = 0;
			table.insert( reachable, c );
		elseif c.recommended or pathed < PATH_CANDIDATES then
			pathed = pathed + 1;
			local path:table = UnitManager.GetMoveToPathEx( unit, c.plotIndex );
			if path ~= nil and path.plots ~= nil and #path.plots >= 2 then
				c.turns = path.turns[ #path.turns ] or 1;
				c.score = c.static - TURN_COST * c.turns;
				table.insert( reachable, c );
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
				if Map.GetPlotDistance( c.x, c.y, other.x, other.y ) <= 2 then keep = false; break; end
			end
		end
		if keep and ( #chosen < MAX_CANDIDATES or c.here ) then table.insert( chosen, c ); end
	end

	local origin:table = unitPlot;
	for _, c in ipairs( chosen ) do
		c.relative = PlotDescription_GetRelative( origin, c.plot );
		c.reasons = {};
		for i, item in ipairs( c.items ) do
			if i <= 6 then table.insert( c.reasons, item.text ); end
		end
		c.detail = _Detail( c );
		if c.here then result.here = c; end
	end
	result.list = chosen;
	result.best = chosen[1];
	return result;
end
