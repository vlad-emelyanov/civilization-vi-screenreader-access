-- ===========================================================================
--	PlacementScan: where can the selected city place a district or a wonder, and where is it best? Pure data, no speech.
--
--	PlacementScan_Scan( city, kind, hash, purchaseYield ) -> scan
--	    kind: "district" or "wonder", hash: the district / building type hash,
--	    purchaseYield: the YieldTypes index when the district is being bought (placement started from the Purchase tab).
--	scan: { kind, hash, name, typeName, city, cityName, purchaseYield, list = { candidates, best first }, byIndex = { plot index ->
--	        candidate }, best = candidate|nil, owned = number of tiles the city owns among them }
--	candidate: { key = "p:<plot index>", plotIndex, x, y, owned = true when the city owns the tile and can build now,
--	             tileCost = gold for the tile (only when not owned), yields = { { index, name, amount } }, total = sum of the
--	             adjacency yields (plus housing), housing = number|nil, adjacency = { yield sentence, ... } as text for
--	             speech ("plus 3 Science"), explanation = the game's adjacency explanation (Space), removes = { "Woods", "Deer" },
--	             notes = { other engine conditions }, relative = "2 tiles north-east", distance }
--	PlacementScan_Cannot( scan, plot ) -> why the plot cannot take the item ("" when the engine gives no reason)
--	PlacementScan_Explain( scan ) -> { canOwned, canBuy, reasons, noSuitable, raw }: why the engine says the city cannot build the item at
--	all (BuildQueue:CanProduce); PlacementScan_Blockers( scan, plot ) -> reasons other than ownership for a plot ("" when none).
--	Purchasable tiles with such a reason are left out of the list (scan.blocked counts them, scan.blockedReason is the first reason).
--
--	Sources (verified in game):
--	  * valid now: CityManager.GetOperationTargets( city, BUILD, { PARAM_DISTRICT_TYPE | PARAM_BUILDING_TYPE } ) -> PLOTS
--	    (what StrategicView_MapPlacement highlights as Placement_Valid);
--	  * tiles that could be bought: CityManager.GetCommandTargets( city, PURCHASE, { PARAM_PLOT_PURCHASE } ) filtered by
--	    plot:CanHaveDistrict / CanHaveWonder (Placement_Purchase). BUILD is refused for them: the game buys the tile as a
--	    separate command (PlotInfo.lua OnClickPurchasePlot) and then places;
--	  * what placing destroys: the SUCCESS_CONDITIONS of CanStartOperation( city, BUILD, { X, Y, type }, true ) ("Will
--	    remove the Woods on this tile", the same lines the game shows in its confirmation dialog). That is only asked for
--	    tiles the city owns; for a tile that has to be bought the same rule is applied to its contents (a removable
--	    feature, the resource, the improvement), see _Contents;
--	  * adjacency: plot:GetAdjacencyYield / GetAdjacencyBonusTooltip (AdjacencyBonusSupport.GetAdjacentYieldBonusString,
--	    reimplemented here because that file defines many globals), housing from Districts.Housing and the plot's appeal for
--	    districts that are not one-per-city (neighbourhoods).
--
--	Sorting. Districts: total adjacency (descending), owned before purchasable, fewer losses, nearer to the city. Wonders:
--	owned before purchasable, fewer losses, nearer.
-- ===========================================================================

include( "ScreenReader" );
include( "PlotDescription" );

local YIELD_START	:number = GameInfo.Yields["YIELD_FOOD"].Index;
local YIELD_END		:number = GameInfo.Yields["YIELD_FAITH"].Index;

-- ===========================================================================
--	Helpers
-- ===========================================================================
local function _Items( results:table, key )
	if results == nil then return {}; end
	return results[ key ] or {};
end

local function _Contents( plot:table )
	-- What would be lost if a district or wonder went onto this plot, by the engine's rule as seen on owned tiles:
	-- removable features (woods, rainforest, marsh), any resource, any improvement.
	local list:table = {};
	local feature:number = plot:GetFeatureType();
	if feature ~= nil and feature >= 0 then
		local row:table = GameInfo.Features[ feature ];
		if row ~= nil and row.Removable then table.insert( list, Locale.Lookup( row.Name ) ); end
	end
	local resource:number = plot:GetResourceType();
	if resource ~= nil and resource >= 0 and not SRPlotResourceHidden( plot ) then
		local row:table = GameInfo.Resources[ resource ];
		if row ~= nil then table.insert( list, Locale.Lookup( row.Name ) ); end
	end
	local improvement:number = plot:GetImprovementType();
	if improvement ~= nil and improvement >= 0 then
		local row:table = GameInfo.Improvements[ improvement ];
		if row ~= nil then table.insert( list, Locale.Lookup( row.Name ) ); end
	end
	return list;
end

-- "Will remove the Woods on this tile." -> "Woods" by matching the game's own sentence for the contents of the plot.
local function _RemovalName( plot:table, text:string )
	local feature:number = plot:GetFeatureType();
	if feature ~= nil and feature >= 0 and GameInfo.Features[ feature ] ~= nil then
		local name:string = Locale.Lookup( GameInfo.Features[ feature ].Name );
		if Locale.Lookup( "LOC_DISTRICT_ZONE_WILL_REMOVE_FEATURE", name ) == text then return name; end
	end
	local resource:number = plot:GetResourceType();
	if resource ~= nil and resource >= 0 and GameInfo.Resources[ resource ] ~= nil and not SRPlotResourceHidden( plot ) then
		local name:string = Locale.Lookup( GameInfo.Resources[ resource ].Name );
		if Locale.Lookup( "LOC_DISTRICT_ZONE_WILL_HARVEST_RESOURCE", name ) == text then return name; end
	end
	local improvement:number = plot:GetImprovementType();
	if improvement ~= nil and improvement >= 0 and GameInfo.Improvements[ improvement ] ~= nil then
		local name:string = Locale.Lookup( GameInfo.Improvements[ improvement ].Name );
		if Locale.Lookup( "LOC_DISTRICT_ZONE_WILL_REMOVE_IMPROVEMENT", name ) == text then return name; end
	end
	return nil;
end

local function _LowerFirst( text:string )
	return string.lower( string.sub( text, 1, 1 ) ) .. string.sub( text, 2 );
end

-- The engine's conditions for placing at this plot: { removed names }, { other sentences }.
local function _Conditions( city:table, kind:string, hash:number, plot:table )
	local params:table = {};
	params[ CityOperationTypes.PARAM_X ] = plot:GetX();
	params[ CityOperationTypes.PARAM_Y ] = plot:GetY();
	if kind == "district" then
		params[ CityOperationTypes.PARAM_DISTRICT_TYPE ] = hash;
	else
		params[ CityOperationTypes.PARAM_BUILDING_TYPE ] = hash;
	end
	local removes:table, notes:table = {}, {};
	local ok:boolean, _, results = pcall( function() return CityManager.CanStartOperation( city, CityOperationTypes.BUILD, params, true ); end );
	if not ok or results == nil then return removes, notes; end
	local hidden:string = SRHiddenHarvestSentence( plot );	-- an undiscovered resource is not mentioned at all
	for _, text in ipairs( _Items( results, CityOperationResults.SUCCESS_CONDITIONS ) ) do
		local name:string = _RemovalName( plot, text );
		if text == hidden then
			text = "";
		elseif name ~= nil then
			table.insert( removes, name );
		else
			text = string.gsub( CleanTextForSpeech( text ), "[%.%s]+$", "" );
			if text ~= "" then table.insert( notes, _LowerFirst( text ) ); end
		end
	end
	return removes, notes;
end

-- The engine's failure reasons (cleaned for speech) for BUILD at this plot, { } when it gives none. For a tile the city
-- does not own it gives none (verified: false, no results), so anything listed there is a reason other than ownership.
local function _Failures( city:table, kind:string, hash:number, plot:table )
	local params:table = {};
	params[ CityOperationTypes.PARAM_X ] = plot:GetX();
	params[ CityOperationTypes.PARAM_Y ] = plot:GetY();
	if kind == "district" then
		params[ CityOperationTypes.PARAM_DISTRICT_TYPE ] = hash;
	else
		params[ CityOperationTypes.PARAM_BUILDING_TYPE ] = hash;
	end
	local reasons:table = {};
	local ok:boolean, _, results = pcall( function() return CityManager.CanStartOperation( city, CityOperationTypes.BUILD, params, true ); end );
	if not ok or results == nil then return reasons; end
	for _, text in ipairs( _Items( results, CityOperationResults.FAILURE_REASONS ) ) do
		local clean:string = string.gsub( CleanTextForSpeech( Locale.Lookup( text ) ), "[%.%s]+$", "" );
		if clean ~= "" then table.insert( reasons, clean ); end
	end
	return reasons;
end

-- Housing the district adds on this plot (only the districts the game shows it for), or nil.
local function _Housing( district:table, plot:table )
	local base:number = district.Housing or 0;
	local total:number = base;
	for row in GameInfo.AppealHousingChanges() do
		if row.DistrictType == district.DistrictType and plot:GetAppeal() >= row.MinimumValue then
			total = base + row.AppealChange;
			break;
		end
	end
	if total ~= 0 then return total; end
	return nil;
end

local function _Adjacency( city:table, district:table, plot:table, candidate:table )
	local localPlayer:number = Game.GetLocalPlayer();
	local texts:table = {};
	local lines:table = {};
	local total:number = 0;
	if district.OnePerCity == false then
		-- neighbourhood style districts: housing by appeal, no adjacency yields
		local ok:boolean, tooltip = pcall( function() return plot:GetAdjacencyBonusTooltip( localPlayer, city:GetID(), district.Index, 0 ); end );
		if ok and tooltip ~= nil and tooltip ~= "" then table.insert( lines, CleanTextForSpeech( tooltip ) ); end
	else
		for index = YIELD_START, YIELD_END do
			local amount:number = plot:GetAdjacencyYield( localPlayer, city:GetID(), district.Index, index );
			if amount ~= nil and amount > 0 then
				local name:string = Locale.Lookup( GameInfo.Yields[ index ].Name );
				table.insert( candidate.yields, { index = index, name = name, amount = amount } );
				table.insert( texts, "plus " .. amount .. " " .. name );
				total = total + amount;
				local ok:boolean, tooltip = pcall( function() return plot:GetAdjacencyBonusTooltip( localPlayer, city:GetID(), district.Index, index ); end );
				if ok and tooltip ~= nil and tooltip ~= "" then table.insert( lines, CleanTextForSpeech( tooltip ) ); end
			end
		end
	end
	local housing:number = _Housing( district, plot );
	if housing ~= nil then
		candidate.housing = housing;
		if district.OnePerCity == false then
			total = total + housing;
			table.insert( texts, "plus " .. housing .. " housing" );
		end
	end
	candidate.adjacency = texts;
	candidate.total = total;
	candidate.explanation = table.concat( lines, ". " );
end

-- ===========================================================================
--	The scan
-- ===========================================================================
local function _MakeCandidate( scan:table, plot:table, owned:boolean )
	local city:table = scan.city;
	local candidate:table = {
		key = "p:" .. plot:GetIndex(), plotIndex = plot:GetIndex(), x = plot:GetX(), y = plot:GetY(), owned = owned,
		yields = {}, adjacency = {}, total = 0, explanation = "", removes = {}, notes = {},
	};
	local cityPlot:table = Map.GetPlot( city:GetX(), city:GetY() );
	candidate.distance = Map.GetPlotDistance( city:GetX(), city:GetY(), plot:GetX(), plot:GetY() );
	candidate.relative = PlotDescription_GetRelative( cityPlot, plot ) or "in the city";
	if scan.kind == "district" then _Adjacency( city, scan.district, plot, candidate ); end
	if owned then
		candidate.removes, candidate.notes = _Conditions( city, scan.kind, scan.hash, plot );
	else
		candidate.removes = _Contents( plot );
		local ok:boolean, cost = pcall( function() return city:GetGold():GetPlotPurchaseCost( plot:GetIndex() ); end );
		candidate.tileCost = ( ok and cost ~= nil ) and cost or 0;
	end
	return candidate;
end

local function _Sort( scan:table )
	local isDistrict:boolean = ( scan.kind == "district" );
	table.sort( scan.list, function( a, b )
		if isDistrict and a.total ~= b.total then return a.total > b.total; end
		if a.owned ~= b.owned then return a.owned; end
		if #a.removes ~= #b.removes then return #a.removes < #b.removes; end
		if a.distance ~= b.distance then return a.distance < b.distance; end
		return a.plotIndex < b.plotIndex;
	end );
end

function PlacementScan_Scan( city:table, kind:string, hash:number, purchaseYield:number )
	local scan:table = {
		kind = kind, hash = hash, city = city, cityName = Locale.Lookup( city:GetName() ), purchaseYield = purchaseYield,
		list = {}, byIndex = {}, best = nil, owned = 0, blocked = 0, blockedReason = nil,
	};
	local row:table;
	if kind == "district" then
		row = GameInfo.Districts[ hash ];
		scan.district = row;
	else
		row = GameInfo.Buildings[ hash ];
		scan.building = row;
	end
	if row == nil then return scan; end
	scan.typeName = row.DistrictType or row.BuildingType;
	scan.name = Locale.Lookup( row.Name );

	local params:table = {};
	if kind == "district" then
		params[ CityOperationTypes.PARAM_DISTRICT_TYPE ] = hash;
	else
		params[ CityOperationTypes.PARAM_BUILDING_TYPE ] = hash;
	end
	local seen:table = {};
	local targets:table = CityManager.GetOperationTargets( city, CityOperationTypes.BUILD, params );
	for _, plotIndex in ipairs( _Items( targets, CityOperationResults.PLOTS ) ) do
		local plot:table = Map.GetPlotByIndex( plotIndex );
		if plot ~= nil and not seen[ plotIndex ] then
			seen[ plotIndex ] = true;
			local candidate:table = _MakeCandidate( scan, plot, true );
			table.insert( scan.list, candidate );
			scan.byIndex[ plotIndex ] = candidate;
			scan.owned = scan.owned + 1;
		end
	end

	local purchaseParams:table = {};
	purchaseParams[ CityCommandTypes.PARAM_PLOT_PURCHASE ] = UI.GetInterfaceModeParameter( CityCommandTypes.PARAM_PLOT_PURCHASE );
	local buyable:table = CityManager.GetCommandTargets( city, CityCommandTypes.PURCHASE, purchaseParams );
	for _, plotIndex in ipairs( _Items( buyable, CityCommandResults.PLOTS ) ) do
		local plot:table = Map.GetPlotByIndex( plotIndex );
		if plot ~= nil and not seen[ plotIndex ] then
			local can:boolean;
			if kind == "district" then
				can = plot:CanHaveDistrict( row.Index, city:GetOwner(), city:GetID() );
			else
				can = plot:CanHaveWonder( row.Index, city:GetOwner(), city:GetID() );
			end
			if can then
				seen[ plotIndex ] = true;
				-- the tile has to be bought first, which only helps when ownership is all that stands in the way
				local reasons:table = _Failures( city, kind, hash, plot );
				if #reasons > 0 then
					scan.blocked = scan.blocked + 1;
					scan.blockedReason = scan.blockedReason or table.concat( reasons, ", " );
					if scan.blocked == 1 then print( "PlacementScan: not offering " .. plot:GetX() .. "," .. plot:GetY() .. " for " .. scan.typeName .. ": " .. scan.blockedReason ); end
				else
					local candidate:table = _MakeCandidate( scan, plot, false );
					table.insert( scan.list, candidate );
					scan.byIndex[ plotIndex ] = candidate;
				end
			end
		end
	end

	_Sort( scan );
	scan.best = scan.list[1];
	return scan;
end

-- For debugging: a table as text.
local function _Dump( value )
	if type( value ) ~= "table" then return tostring( value ); end
	local parts:table = {};
	for k, v in pairs( value ) do table.insert( parts, tostring( k ) .. "=" .. _Dump( v ) ); end
	return "{" .. table.concat( parts, "; " ) .. "}";
end

-- The engine hands the reason over localized, not as the LOC tag, so compare the text too.
local function _NoSuitableText( tag:string )
	return string.gsub( CleanTextForSpeech( Locale.Lookup( tag ) ), "[%.%s]+$", "" );
end

-- Why can the city not build the item at all (no owned tile fits)? Asks the build queue, once without and once allowing
-- the purchase of tiles. -> { canOwned, canBuy, reasons = { text }, noSuitable = true when the engine only says there
-- is no suitable location, raw = the results as text }. Verified results: failure reasons come as localized text
-- ("Requires Population of 4 or greater."), or as the LOC tag LOC_DISTRICT_ZONE_NO_SUITABLE_LOCATION.
function PlacementScan_Explain( scan:table )
	local info:table = { canOwned = false, canBuy = false, reasons = {}, noSuitable = false, raw = "" };
	local queue:table = scan.city:GetBuildQueue();
	local seen:table = {};
	local function Collect( results:table )
		if results == nil then return; end
		if results[ CityOperationResults.NO_SUITABLE_LOCATION ] == true then info.noSuitable = true; end
		for _, text in ipairs( _Items( results, CityOperationResults.FAILURE_REASONS ) ) do
			local clean:string = string.gsub( CleanTextForSpeech( Locale.Lookup( text ) ), "[%.%s]+$", "" );
			if text == "LOC_DISTRICT_ZONE_NO_SUITABLE_LOCATION" or text == "LOC_BUILDING_CONSTRUCT_NO_SUITABLE_LOCATION"
					or clean == _NoSuitableText( "LOC_DISTRICT_ZONE_NO_SUITABLE_LOCATION" ) or clean == _NoSuitableText( "LOC_BUILDING_CONSTRUCT_NO_SUITABLE_LOCATION" ) then
				info.noSuitable = true;
			else
				if clean ~= "" and not seen[ clean ] then
					seen[ clean ] = true;
					table.insert( info.reasons, clean );
				end
			end
		end
	end
	local ok1:boolean, can1, results1 = pcall( function() return queue:CanProduce( scan.hash, false, true ); end );
	local ok2:boolean, can2, results2 = pcall( function() return queue:CanProduce( scan.hash, false, true, true ); end );
	info.canOwned = ok1 and can1 == true;
	info.canBuy = ok2 and can2 == true;
	Collect( ok1 and results1 or nil );
	Collect( ok2 and results2 or nil );
	info.raw = "CanProduce(" .. tostring( scan.typeName ) .. ") owned: " .. tostring( can1 ) .. " " .. _Dump( results1 ) .. "; buy: " .. tostring( can2 ) .. " " .. _Dump( results2 );
	print( "PlacementScan: " .. info.raw );
	return info;
end

-- Why can't a tile the city has just bought take the item? (the owned-tile reasons of the engine, "" when it gives none)
function PlacementScan_Blockers( scan:table, plot:table )
	return table.concat( _Failures( scan.city, scan.kind, scan.hash, plot ), ", " );
end

-- Why can the item not go on this plot? The engine's failure reasons for the owned case, a few plain words otherwise.
function PlacementScan_Cannot( scan:table, plot:table )
	if plot == nil then return ""; end
	local owner:number = plot:GetOwner();
	local localPlayer:number = Game.GetLocalPlayer();
	if owner ~= nil and owner >= 0 and owner ~= localPlayer then return "owned by another civilization"; end
	local params:table = {};
	params[ CityOperationTypes.PARAM_X ] = plot:GetX();
	params[ CityOperationTypes.PARAM_Y ] = plot:GetY();
	if scan.kind == "district" then
		params[ CityOperationTypes.PARAM_DISTRICT_TYPE ] = scan.hash;
	else
		params[ CityOperationTypes.PARAM_BUILDING_TYPE ] = scan.hash;
	end
	local ok:boolean, can, results = pcall( function() return CityManager.CanStartOperation( scan.city, CityOperationTypes.BUILD, params, true ); end );
	if ok and results ~= nil then
		local reasons:table = {};
		for _, text in ipairs( _Items( results, CityOperationResults.FAILURE_REASONS ) ) do
			local clean:string = string.gsub( CleanTextForSpeech( text ), "[%.%s]+$", "" );
			if clean ~= "" then table.insert( reasons, clean ); end
		end
		if #reasons > 0 then return table.concat( reasons, ", " ); end
	end
	if plot:IsWater() and scan.kind == "district" and not ( scan.district ~= nil and scan.district.Aquatic ) then return "water"; end
	if owner == nil or owner < 0 then return "not your territory, and the tile cannot be bought for this"; end
	return "";
end
