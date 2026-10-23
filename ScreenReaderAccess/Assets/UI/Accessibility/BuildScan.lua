-- ===========================================================================
--	BuildScan: which tiles of a city can the selected builder improve? Pure data, no speech.
--
--	BuildScan_Improvements( unit )              -> { { hash, name, type } } | nil   the improvements the unit type can ever build
--	                                               (Improvement_ValidBuildUnits); nil when the unit is no builder of ours (combat
--	                                               units and units without BuildCharges are none). Cached per unit type.
--	BuildScan_CanBuild( unit, plot, improvement ) -> boolean                         the engine's own check for one improvement
--	BuildScan_Cities( unit )                    -> { { city, name, distance } }     our cities, nearest to the unit first
--	BuildScan_DefaultCity( unit )               -> city | nil                         the city owning the unit's plot, else the nearest
--	BuildScan_Scan( unit, city, quick )         -> { city, cityName, list = { entries } }
--	    entry: { key, plot, plotIndex, x, y, distance, turns, here, relative, name (resource name, else terrain and feature),
--	             resource, resourceClass, improvesResource (an offered improvement works the resource), worked (a citizen works
--	             it), improvements = { { name, hash, yieldText ("plus 1 food" or ""), repair = true for a pillaged one } } }
--	    Tiles are the city's purchased plots where the builder can build at least one improvement now or repair a
--	    pillaged one. Plots with a (not pillaged) improvement, districts and cities are skipped. Sorted: tiles with a
--	    resource that an improvement works (luxury, strategic, bonus) first, then worked tiles, then the rest; within a
--	    group by turns, then distance. Unreachable tiles are dropped (quick = true: no path finding, turns = nil, for a
--	    cheap count). With no moves left the engine refuses everything: the list is empty and result.noMoves is true.
--
--	Yield changes are the base values of Improvement_YieldChanges (not adjacency, techs, policies or the resource's own
--	bonus), so "plus 1 food" for a Farm is what the improvement adds by itself.
--	The result is cached per unit + plot + turn + moves + city.
-- ===========================================================================

include( "PlotDescription" );

-- ===========================================================================
--	The unit's improvements
-- ===========================================================================
local m_builderLists:table = {};

function BuildScan_Improvements( unit:table )
	if unit == nil or unit:GetOwner() ~= Game.GetLocalPlayer() then return nil; end
	local unitType:number = unit:GetUnitType();
	local cached = m_builderLists[ unitType ];
	if cached ~= nil then return cached.list; end
	local entry:table = { list = nil };
	local row:table = GameInfo.Units[ unitType ];
	if row ~= nil and row.BuildCharges ~= nil and row.BuildCharges > 0 and ( row.Combat or 0 ) == 0 then
		local found:table = {};
		for valid in GameInfo.Improvement_ValidBuildUnits() do
			local improvement:table = ( valid.UnitType == row.UnitType ) and GameInfo.Improvements[ valid.ImprovementType ] or nil;
			if improvement ~= nil then
				table.insert( found, { hash = improvement.Hash, name = Locale.Lookup( improvement.Name ), type = improvement.ImprovementType } );
			end
		end
		if #found > 0 then entry.list = found; end
	end
	m_builderLists[ unitType ] = entry;
	return entry.list;
end

function BuildScan_CanBuild( unit:table, plot:table, improvement:table )
	local params:table = {};
	params[ UnitOperationTypes.PARAM_IMPROVEMENT_TYPE ] = improvement.hash;
	return UnitManager.CanStartOperation( unit, UnitOperationTypes.BUILD_IMPROVEMENT, plot, params, false ) == true;
end

-- Can the unit repair the pillaged improvement on the plot?
local function _CanRepair( unit:table, plot:table )
	local operation = UnitOperationTypes.REPAIR;
	if operation == nil and GameInfo.UnitOperations ~= nil and GameInfo.UnitOperations[ "UNITOPERATION_REPAIR" ] ~= nil then
		operation = GameInfo.UnitOperations[ "UNITOPERATION_REPAIR" ].Hash;
	end
	if operation == nil then return false; end
	local ok:boolean, result = pcall( UnitManager.CanStartOperation, unit, operation, plot, false );
	return ok and result == true;
end

-- ===========================================================================
--	Yields and resources
-- ===========================================================================
-- improvement type -> "plus 1 food and 1 production" (base values), built once
local m_yieldTexts:table = nil;

local function _YieldText( improvementType:string )
	if m_yieldTexts == nil then
		m_yieldTexts = {};
		local lists:table = {};
		for row in GameInfo.Improvement_YieldChanges() do
			if row.YieldChange ~= nil and row.YieldChange > 0 then
				lists[ row.ImprovementType ] = lists[ row.ImprovementType ] or {};
				local yield:table = GameInfo.Yields[ row.YieldType ];
				local name:string = ( yield ~= nil ) and string.lower( Locale.Lookup( yield.Name ) ) or row.YieldType;
				table.insert( lists[ row.ImprovementType ], row.YieldChange .. " " .. name );
			end
		end
		for improvement, parts in pairs( lists ) do m_yieldTexts[ improvement ] = "plus " .. table.concat( parts, " and " ); end
	end
	return m_yieldTexts[ improvementType ] or "";
end

local m_resourceImprovements:table = nil;		-- resource type -> { improvement type = true }

local function _ImprovesResource( resourceType:string, improvementType:string )
	if m_resourceImprovements == nil then
		m_resourceImprovements = {};
		for row in GameInfo.Improvement_ValidResources() do
			m_resourceImprovements[ row.ResourceType ] = m_resourceImprovements[ row.ResourceType ] or {};
			m_resourceImprovements[ row.ResourceType ][ row.ImprovementType ] = true;
		end
	end
	local set:table = m_resourceImprovements[ resourceType ];
	return set ~= nil and set[ improvementType ] == true;
end

-- Visible resource of the plot: name, class rank (1 luxury, 2 strategic, 3 bonus), resource type, class word.
local function _Resource( plot:table )
	local resourceType:number = plot:GetResourceType();
	if resourceType == nil or resourceType < 0 then return nil; end
	local row:table = GameInfo.Resources[ resourceType ];
	if row == nil then return nil; end
	local resources:table = Players[ Game.GetLocalPlayer() ]:GetResources();
	if resources ~= nil and not resources:IsResourceVisible( row.Hash ) then return nil; end
	local rank:number, class:string = 3, "bonus";
	if row.ResourceClassType == "RESOURCECLASS_LUXURY" then rank, class = 1, "luxury";
	elseif row.ResourceClassType == "RESOURCECLASS_STRATEGIC" then rank, class = 2, "strategic";
	elseif row.ResourceClassType == "RESOURCECLASS_ARTIFACT" then class = "artifact"; end
	return Locale.Lookup( row.Name ), rank, row.ResourceType, class;
end

-- "Plains hills" / "Grassland, Forest": the terrain, and the feature when there is one.
local function _TerrainName( plot:table )
	local terrain:table = GameInfo.Terrains[ plot:GetTerrainType() ];
	local name:string = ( terrain ~= nil ) and Locale.Lookup( terrain.Name ) or "";
	local feature:number = plot:GetFeatureType();
	if feature ~= nil and feature >= 0 and GameInfo.Features[ feature ] ~= nil then
		name = name .. ", " .. Locale.Lookup( GameInfo.Features[ feature ].Name );
	end
	return ( string.gsub( name, "[()]", "" ) );
end

-- ===========================================================================
--	Cities
-- ===========================================================================
function BuildScan_Cities( unit:table )
	local list:table = {};
	local player:table = Players[ Game.GetLocalPlayer() ];
	if unit == nil or player == nil then return list; end
	for _, city in player:GetCities():Members() do
		table.insert( list, {
			city = city, name = Locale.Lookup( city:GetName() ),
			distance = Map.GetPlotDistance( unit:GetX(), unit:GetY(), city:GetX(), city:GetY() ),
		} );
	end
	table.sort( list, function( a, b )
		if a.distance ~= b.distance then return a.distance < b.distance; end
		return a.name < b.name;
	end );
	return list;
end

function BuildScan_DefaultCity( unit:table )
	if unit == nil then return nil; end
	local plot:table = Map.GetPlot( unit:GetX(), unit:GetY() );
	if plot ~= nil and plot:GetOwner() == Game.GetLocalPlayer() and Cities ~= nil then
		local ok:boolean, city = pcall( Cities.GetPlotPurchaseCity, plot );
		if ok and city ~= nil and city:GetOwner() == Game.GetLocalPlayer() then return city; end
	end
	local cities:table = BuildScan_Cities( unit );
	return ( cities[1] ~= nil ) and cities[1].city or nil;
end

-- ===========================================================================
--	Scan
-- ===========================================================================
local m_scanKey:string = nil;
local m_scan:table = nil;

function BuildScan_Scan( unit:table, city:table, quick:boolean )
	local result:table = { city = city, list = {} };
	local improvements:table = BuildScan_Improvements( unit );
	if unit == nil or city == nil or improvements == nil then return result; end
	result.cityName = Locale.Lookup( city:GetName() );
	if unit:GetMovesRemaining() <= 0 then
		result.noMoves = true;
		return result;
	end

	local localPlayer:number = Game.GetLocalPlayer();
	local key:string = table.concat( { localPlayer, unit:GetID(), unit:GetX(), unit:GetY(), Game.GetCurrentGameTurn(), unit:GetMovesRemaining(),
		city:GetID(), tostring( quick == true ) }, ":" );
	if key == m_scanKey and m_scan ~= nil then return m_scan; end

	local citizens:table = city:GetCitizens();
	local unitPlot:table = Map.GetPlot( unit:GetX(), unit:GetY() );
	local unitIndex:number = unitPlot:GetIndex();
	for _, plotID in ipairs( Map.GetCityPlots():GetPurchasedPlots( city ) ) do
		local plot:table = Map.GetPlotByIndex( plotID );
		local improvementType:number = plot:GetImprovementType();
		local pillaged:boolean = improvementType ~= nil and improvementType >= 0 and plot:IsImprovementPillaged();
		local skip:boolean = plot:IsCity() or ( plot:GetDistrictType() ~= nil and plot:GetDistrictType() >= 0 )
			or ( improvementType ~= nil and improvementType >= 0 and not pillaged );
		if not skip then
			local offered:table = {};
			if pillaged and _CanRepair( unit, plot ) then
				local row:table = GameInfo.Improvements[ improvementType ];
				table.insert( offered, { name = "pillaged " .. Locale.Lookup( row.Name ), hash = row.Hash, yieldText = "", repair = true, type = row.ImprovementType } );
			end
			for _, improvement in ipairs( improvements ) do
				if BuildScan_CanBuild( unit, plot, improvement ) then
					table.insert( offered, { name = improvement.name, hash = improvement.hash, yieldText = _YieldText( improvement.type ), type = improvement.type } );
				end
			end
			if #offered > 0 then
				local resourceName:string, rank:number, resourceType:string, class:string = _Resource( plot );
				local improves:boolean = false;
				if resourceType ~= nil then
					-- the improvement that works the resource comes first
					table.sort( offered, function( a, b )
						local ia, ib = _ImprovesResource( resourceType, a.type ), _ImprovesResource( resourceType, b.type );
						if ia ~= ib then return ia; end
						return false;
					end );
					improves = _ImprovesResource( resourceType, offered[1].type );
				end
				local worked:boolean = false;
				if citizens ~= nil then
					local ok:boolean, result2 = pcall( citizens.IsPlotWorked, citizens, plot:GetX(), plot:GetY() );
					worked = ok and result2 == true;
				end
				local here:boolean = plot:GetIndex() == unitIndex;
				local turns:number = nil;
				local reachable:boolean = true;
				if here then
					turns = 0;
				elseif not quick then
					local path:table = UnitManager.GetMoveToPathEx( unit, plot:GetIndex() );
					if path ~= nil and path.plots ~= nil and #path.plots >= 2 then
						turns = path.turns[ #path.turns ] or 1;
					else
						reachable = false;
					end
				end
				if reachable then
					local group:number = 5;
					if improves then group = rank; elseif worked then group = 4; end
					table.insert( result.list, {
						key = tostring( plot:GetIndex() ), plot = plot, plotIndex = plot:GetIndex(), x = plot:GetX(), y = plot:GetY(),
						distance = Map.GetPlotDistance( unit:GetX(), unit:GetY(), plot:GetX(), plot:GetY() ), turns = turns, here = here,
						name = resourceName or _TerrainName( plot ), resource = resourceName, resourceClass = class, improvesResource = improves,
						worked = worked, improvements = offered, group = group,
					} );
				end
			end
		end
	end
	table.sort( result.list, function( a, b )
		if a.group ~= b.group then return a.group < b.group; end
		if ( a.turns or 0 ) ~= ( b.turns or 0 ) then return ( a.turns or 0 ) < ( b.turns or 0 ); end
		if a.distance ~= b.distance then return a.distance < b.distance; end
		return a.plotIndex < b.plotIndex;
	end );
	for _, entry in ipairs( result.list ) do entry.relative = PlotDescription_GetRelative( unitPlot, entry.plot ); end
	m_scanKey, m_scan = key, result;
	return result;
end
