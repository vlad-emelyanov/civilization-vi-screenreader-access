-- ===========================================================================
--	CityReportGather: reads one city into the plain table that CityReportData.lua formats (Control+I).
--	The numbers come from the game's own GetCityData (CitySupport.lua; Gathering Storm / Rise and Fall use their
--	replacement copy through the same include), i.e. what the city panel and CityPanelOverview show. Loyalty,
--	specialists, great works and the queue size are not in GetCityData and are read from the city here.
--
--	CityReport_Gather( pCity ) -> table (fields: see the code) or nil, error text
-- ===========================================================================

include( "ScreenReader" );
include( "PlotDescription" );
include( "SupportFunctions" );		-- Round(), Clamp() used by GetCityData
include( "Civ6Common" );			-- GetYieldString(), GetUnitStats() used by GetCityData
-- GetCityData reads these two as globals; CityPanel.lua / CityPanelOverview.lua define them as file locals
if TXT_NO_PRODUCTION == nil then TXT_NO_PRODUCTION = Locale.Lookup( "LOC_HUD_CITY_PRODUCTION_NOTHING_PRODUCED" ); end
if SIZE_PRODUCTION_ICON == nil then SIZE_PRODUCTION_ICON = 32; end
include( "CitySupport" );

local function Guard( name:string, f )
	local ok:boolean, result = pcall( f );
	if not ok then print( "CityReportGather " .. name .. " error: " .. tostring( result ) ); return nil; end
	return result;
end

local function Entry( label:string, value:number, sign:number )
	return { label = label, value = ( value or 0 ) * ( sign or 1 ) };
end

local function GatherAmenities( data:table )
	local mood:string = "";
	local row:table = GameInfo.Happinesses[ data.Happiness ];
	if row ~= nil then mood = Locale.Lookup( row.Name ); end
	return {
		have = data.AmenitiesNum, needed = data.AmenitiesRequiredNum, mood = mood,
		growthPercent = data.HappinessGrowthModifier, yieldPercent = data.HappinessNonFoodYieldModifier,
		advice = data.AmenityAdvice,
		sources = {
			Entry( "luxuries", data.AmenitiesFromLuxuries ), Entry( "entertainment", data.AmenitiesFromEntertainment ),
			Entry( "districts", data.AmenitiesFromDistricts ), Entry( "civics", data.AmenitiesFromCivics ),
			Entry( "great people", data.AmenitiesFromGreatPeople ), Entry( "city states", data.AmenitiesFromCityStates ),
			Entry( "religion", data.AmenitiesFromReligion ), Entry( "national parks", data.AmenitiesFromNationalParks ),
			Entry( "natural wonders", data.AmenitiesFromNaturalWonders ), Entry( "improvements", data.AmenitiesFromImprovements ),
			Entry( "starting era", data.AmenitiesFromStartingEra ), Entry( "governors", data.AmenitiesFromGovernors ),
			Entry( "traits", data.AmenitiesFromTraits ),
		},
		losses = {
			Entry( "war weariness", data.AmenitiesLostFromWarWeariness, -1 ), Entry( "bankruptcy", data.AmenitiesLostFromBankruptcy, -1 ),
		},
	};
end

local function GatherGrowth( pCity:table, data:table )
	local growth:table = {
		occupied = data.Occupied == true, turnsUntilGrowth = data.TurnsUntilGrowth, housingMultiplier = data.HousingMultiplier,
		housing = data.Housing, foodPerTurn = data.FoodPerTurn, foodNeeded = data.GrowthThreshold,
		happinessGrowthModifier = data.HappinessGrowthModifier, otherGrowthModifier = data.OtherGrowthModifiers,
		occupationMultiplier = data.OccupationMultiplier, housingAdvice = data.HousingAdvice,
		housingSources = {
			fromBuildings = data.HousingFromBuildings, fromDistricts = data.HousingFromDistricts,
			fromImprovements = data.HousingFromImprovements, fromWater = data.HousingFromWater, fromCivics = data.HousingFromCivics,
			fromGreatPeople = data.HousingFromGreatPeople, fromStartingEra = data.HousingFromStartingEra,
			fromGreatWorks = data.HousingFromGreatWorks,
		},
	};
	-- Rise and Fall: loyalty changes growth (CityPanelOverview_Expansion1)
	local percent:number = Guard( "loyalty growth", function()
		local grow:table = pCity:GetGrowth();
		if grow.GetLoyaltyGrowthModifier == nil then return nil; end
		return Round( grow:GetLoyaltyGrowthModifier() * 100 - 100, 0 );
	end );
	growth.loyaltyGrowthPercent = percent;
	return growth;
end

-- The cultural identity of the city (Rise and Fall, Gathering Storm). nil in the base game.
local function GatherLoyalty( pCity:table )
	if pCity.GetCulturalIdentity == nil then return nil; end
	local identity:table = pCity:GetCulturalIdentity();
	if identity == nil then return nil; end
	local loyalty:table = {
		current = Round( identity:GetLoyalty(), 1 ), max = identity:GetMaxLoyalty(), perTurn = Round( identity:GetLoyaltyPerTurn(), 1 ),
		sources = {}, influence = {},
	};
	local level:number = identity:GetLoyaltyLevel();
	local levelRow:table = GameInfo.LoyaltyLevels[ level ];
	if levelRow ~= nil then
		loyalty.level = Locale.Lookup( levelRow.Name );
		if level < 3 then
			loyalty.effect = Locale.Lookup( "LOC_LOYALTY_GROWTH_AND_YIELD_EFFECTS_TEXT", levelRow.GrowthChange * 100, levelRow.YieldChange * 100 );
		else
			loyalty.effect = Locale.Lookup( "LOC_LOYALTY_EFFECT_NONE" );
		end
	end
	Guard( "loyalty sources", function()
		for _, inner in ipairs( identity:GetIdentitySourcesDetailedBreakdown() ) do
			local source, value = next( inner );
			if source ~= nil and value ~= nil then table.insert( loyalty.sources, { label = Locale.Lookup( source ), value = value } ); end
		end
	end );
	Guard( "loyalty influence", function()
		local present:table = identity:GetPlayerIdentitiesInCity();
		table.sort( present, function( a, b ) return a.IdentityTotal > b.IdentityTotal; end );
		for _, p in ipairs( present ) do
			local config:table = PlayerConfigurations[ p.Player ];
			if config ~= nil then table.insert( loyalty.influence, { name = Locale.Lookup( config:GetCivilizationDescription() ), value = p.IdentityTotal } ); end
		end
	end );
	Guard( "loyalty rival", function()
		local rival:number = identity:GetPotentialTransferPlayer();
		if rival ~= nil and rival ~= -1 and PlayerConfigurations[ rival ] ~= nil then
			loyalty.rival = Locale.Lookup( PlayerConfigurations[ rival ]:GetCivilizationDescription() );
		end
	end );
	Guard( "loyalty advice", function() loyalty.advice = pCity:GetLoyaltyAdvice(); end );
	return loyalty;
end

local function GatherDistricts( data:table )
	local districts:table = {};
	local specialists:table = {};
	local totalSpecialists:number = 0;
	for _, district in ipairs( data.BuildingsAndDistricts ) do
		if district.isBuilt then
			local buildings:table = {};
			local workers:number = 0;
			for _, b in ipairs( district.Buildings ) do
				if b.isBuilt then
					table.insert( buildings, { name = b.Name, pillaged = b.isPillaged == true } );
					workers = b.Citizens or workers;		-- same plot for every building of the district
				end
			end
			table.insert( districts, { name = district.Name, pillaged = district.isPillaged == true, buildings = buildings,
				yield = CleanTextForSpeech( district.YieldBonus or "" ) } );
			-- the city center is worked for free; its plot count is not a specialist
			if district.Type ~= "DISTRICT_CITY_CENTER" and workers > 0 then
				table.insert( specialists, { name = district.Name, count = workers } );
				totalSpecialists = totalSpecialists + workers;
			end
		end
	end
	local wonders:table = {};
	for _, w in ipairs( data.Wonders ) do
		if w.isBuilt then table.insert( wonders, { name = w.Name, pillaged = w.isPillaged == true } ); end
	end
	return districts, wonders, specialists, totalSpecialists;
end

local function GatherReligion( data:table )
	local religion:table = { beliefs = {}, others = {} };
	local dominant:table = data.Religions[ DATA_DOMINANT_RELIGION ];
	if dominant ~= nil then
		religion.majorityName = Locale.Lookup( Game.GetReligion():GetName( dominant.ID ) );
		religion.majorityFollowers = dominant.Followers;
		for _, belief in ipairs( data.BeliefsOfDominantReligion ) do
			local row:table = GameInfo.Beliefs[ belief ];
			if row ~= nil then table.insert( religion.beliefs, Locale.Lookup( row.Name ) ); end
		end
	end
	for _, r in ipairs( data.Religions ) do
		if r.ReligionType ~= "RELIGION_PANTHEON" and ( dominant == nil or r.ReligionType ~= dominant.ReligionType ) then
			table.insert( religion.others, { name = Locale.Lookup( Game.GetReligion():GetName( r.ID ) ), followers = r.Followers } );
		end
	end
	if data.PantheonBelief ~= nil and data.PantheonBelief > -1 then
		local row:table = GameInfo.Beliefs[ data.PantheonBelief ];
		if row ~= nil then religion.pantheon = Locale.Lookup( row.Name ); end
	end
	return religion;
end

local function GatherGreatWorks( pCity:table )
	local result:table = { slots = 0, filled = 0, names = {} };
	local buildings:table = pCity:GetBuildings();
	for info in GameInfo.Buildings() do
		if buildings:HasBuilding( info.Index ) then
			local slots:number = buildings:GetNumGreatWorkSlots( info.Index );
			if slots ~= nil and slots > 0 then
				result.slots = result.slots + slots;
				for slot = 0, slots - 1 do
					local index:number = buildings:GetGreatWorkInSlot( info.Index, slot );
					if index ~= nil and index ~= -1 then
						result.filled = result.filled + 1;
						local row:table = GameInfo.GreatWorks[ buildings:GetGreatWorkTypeFromIndex( index ) ];
						if row ~= nil then table.insert( result.names, Locale.Lookup( row.Name ) ); end
					end
				end
			end
		end
	end
	return result;
end

-- ---------------------------------------------------------------------------
-- City management (focus, tiles, specialists, buyable tiles). Same queries as the game's own panels:
--   workable tiles + worker counts: PlotInfo.lua ShowCitizens (WorldView/PlotInfo.lua:354-424), command MANAGE
--   buyable tiles + cost:           PlotInfo.lua ShowPurchases (:247-303), command PURCHASE, cost = city:GetGold():GetPlotPurchaseCost
--   yield focus state:              CitySupport.lua:584-596 (IsFavoredYield / IsDisfavoredYield)
-- ---------------------------------------------------------------------------
local MANAGE_YIELDS:table = {
	{ key = "food", name = "Food", type = "FOOD" }, { key = "production", name = "Production", type = "PRODUCTION" },
	{ key = "gold", name = "Gold", type = "GOLD" }, { key = "science", name = "Science", type = "SCIENCE" },
	{ key = "culture", name = "Culture", type = "CULTURE" }, { key = "faith", name = "Faith", type = "FAITH" },
};

function CityManage_YieldType( key:string )
	for _, y in ipairs( MANAGE_YIELDS ) do
		if y.key == key then return YieldTypes[ y.type ]; end
	end
	return nil;
end

local function PlotYieldTotal( plot:table )
	local total:number = 0;
	for row in GameInfo.Yields() do total = total + ( plot:GetYield( row.Index ) or 0 ); end
	return total;
end

-- "+2 science" for the specialists of a district (the base value of District_CitizenYieldChanges)
local function SpecialistYields( districtType:string )
	local parts:table = {};
	for row in GameInfo.District_CitizenYieldChanges() do
		if row.DistrictType == districtType and row.YieldChange ~= nil and row.YieldChange ~= 0 then
			local yield:table = GameInfo.Yields[ row.YieldType ];
			if yield ~= nil then
				table.insert( parts, string.format( "%+d", row.YieldChange ) .. " " .. string.lower( Locale.Lookup( yield.Name ) ) );
			end
		end
	end
	return table.concat( parts, " " );
end

function CityManage_Gather( pCity:table )
	local m:table = { focus = {}, tiles = {}, districts = {}, buy = {}, gold = 0 };
	local cityPlot:table = Map.GetPlot( pCity:GetX(), pCity:GetY() );
	m.gold = math.floor( Players[ pCity:GetOwner() ]:GetTreasury():GetGoldBalance() );

	local citizens:table = pCity:GetCitizens();
	for _, y in ipairs( MANAGE_YIELDS ) do
		local state:string = "normal";
		local yieldType:number = YieldTypes[ y.type ];
		if citizens:IsFavoredYield( yieldType ) then state = "favored"; elseif citizens:IsDisfavoredYield( yieldType ) then state = "ignored"; end
		table.insert( m.focus, { key = y.key, name = y.name, state = state, yieldType = yieldType } );
	end

	local params:table = {};
	params[ CityCommandTypes.PARAM_MANAGE_CITIZEN ] = UI.GetInterfaceModeParameter( CityCommandTypes.PARAM_MANAGE_CITIZEN );
	local targets:table = CityManager.GetCommandTargets( pCity, CityCommandTypes.MANAGE, params );
	if targets ~= nil and targets[ CityCommandResults.PLOTS ] ~= nil then
		local plots:table, units:table = targets[ CityCommandResults.PLOTS ], targets[ CityCommandResults.CITIZENS ] or {};
		local maxUnits:table, lockedUnits:table = targets[ CityCommandResults.MAX_CITIZENS ] or {}, targets[ CityCommandResults.LOCKED_CITIZENS ] or {};
		for i, plotId in pairs( plots ) do
			local plot:table = Map.GetPlotByIndex( plotId );
			if plot ~= nil and not plot:IsCity() then
				local count:number, max:number = units[i] or 0, maxUnits[i] or 1;
				local locked:boolean = ( lockedUnits[i] or 0 ) > 0;
				local districtType:number = plot:GetDistrictType();
				local district:table = ( districtType ~= nil and districtType >= 0 ) and GameInfo.Districts[ districtType ] or nil;
				if district ~= nil then
					if max > 0 then
						table.insert( m.districts, { key = "d" .. plotId, plotIndex = plotId, name = Locale.Lookup( district.Name ), count = count, max = max,
							locked = locked, perSlot = SpecialistYields( district.DistrictType ) } );
					end
				else
					local desc:string = ( string.gsub( PlotDescription_GetShort( plot, {} ), ", yours", "" ) );
					table.insert( m.tiles, { key = "t" .. plotId, plotIndex = plotId, relative = PlotDescription_GetRelative( cityPlot, plot ), desc = desc,
						count = count, max = max, locked = locked, total = PlotYieldTotal( plot ) } );
				end
			end
		end
		table.sort( m.tiles, function( a, b )
			if ( a.count > 0 ) ~= ( b.count > 0 ) then return a.count > 0; end
			if a.total ~= b.total then return a.total > b.total; end
			return a.plotIndex < b.plotIndex;
		end );
		table.sort( m.districts, function( a, b ) return a.plotIndex < b.plotIndex; end );
	end

	local buyParams:table = {};
	buyParams[ CityCommandTypes.PARAM_PLOT_PURCHASE ] = UI.GetInterfaceModeParameter( CityCommandTypes.PARAM_PLOT_PURCHASE );
	local buyTargets:table = CityManager.GetCommandTargets( pCity, CityCommandTypes.PURCHASE, buyParams );
	if buyTargets ~= nil and buyTargets[ CityCommandResults.PLOTS ] ~= nil then
		for _, plotId in pairs( buyTargets[ CityCommandResults.PLOTS ] ) do
			local plot:table = Map.GetPlotByIndex( plotId );
			if plot ~= nil then
				local desc:string = ( string.gsub( PlotDescription_GetShort( plot, {} ), ", yours", "" ) );
				table.insert( m.buy, { key = "b" .. plotId, plotIndex = plotId, relative = PlotDescription_GetRelative( cityPlot, plot ), desc = desc,
					cost = math.floor( pCity:GetGold():GetPlotPurchaseCost( plotId ) ),
					distance = Map.GetPlotDistance( cityPlot:GetX(), cityPlot:GetY(), plot:GetX(), plot:GetY() ) } );
			end
		end
		table.sort( m.buy, function( a, b )
			if a.distance ~= b.distance then return a.distance < b.distance; end
			return a.plotIndex < b.plotIndex;
		end );
	end
	return m;
end

function CityReport_Gather( pCity:table )
	if pCity == nil then return nil, "no city"; end
	local ok:boolean, data = pcall( GetCityData, pCity );
	if not ok or data == nil then
		print( "CityReportGather: GetCityData failed: " .. tostring( data ) );
		return nil, "city data unavailable";
	end

	local d:table = {
		name = Locale.Lookup( data.CityName ), population = data.Population, foodSurplus = data.FoodSurplus,
		yields = {
			food = { value = data.FoodPerTurn, tooltip = data.FoodPerTurnToolTip },
			production = { value = data.ProductionPerTurn, tooltip = data.ProductionPerTurnToolTip },
			gold = { value = data.GoldPerTurn, tooltip = data.GoldPerTurnToolTip },
			science = { value = data.SciencePerTurn, tooltip = data.SciencePerTurnToolTip },
			culture = { value = data.CulturePerTurn, tooltip = data.CulturePerTurnToolTip },
			faith = { value = data.FaithPerTurn, tooltip = data.FaithPerTurnToolTip },
		},
		defense = {
			hp = data.HitpointsCurrent, hpMax = data.HitpointsTotal, wall = data.CityWallCurrentHP, wallMax = data.CityWallTotalHP,
			strength = data.Defense, underSiege = data.IsUnderSiege == true,
		},
		buildingsNum = data.BuildingsNum, districtsCount = data.DistrictsNum, districtsMax = data.DistrictsPossibleNum,
	};
	d.growth = GatherGrowth( pCity, data );
	d.amenities = GatherAmenities( data );
	d.loyalty = Guard( "loyalty", function() return GatherLoyalty( pCity ); end );
	d.religion = GatherReligion( data );

	-- production: "nothing" is reported by the empty hash, not by the name
	local queue:table = pCity:GetBuildQueue();
	if queue:GetCurrentProductionTypeHash() == 0 then
		d.production = { name = "" };
	else
		d.production = {
			name = data.CurrentProductionName, turns = data.CurrentTurnsLeft, percent = data.CurrentProdPercent,
			description = data.CurrentProductionDescription, queued = math.max( 0, queue:GetSize() - 1 ),
		};
	end

	local districts, wonders, specialists, totalSpecialists = GatherDistricts( data );
	d.districts = districts;
	d.wonders = wonders;
	d.citizens = { total = data.Population, specialists = totalSpecialists, working = math.max( 0, data.Population - totalSpecialists ),
		byDistrict = specialists, favored = {} };
	Guard( "favored yields", function()
		for yield in GameInfo.Yields() do
			if data.YieldFilters[ yield.Index ] == YIELD_STATE.FAVORED then table.insert( d.citizens.favored, string.lower( Locale.Lookup( yield.Name ) ) ); end
		end
	end );

	d.manage = Guard( "city management", function() return CityManage_Gather( pCity ); end );
	d.greatWorks = Guard( "great works", function() return GatherGreatWorks( pCity ); end );
	d.tradingPosts = {};
	Guard( "trading posts", function()
		for _, id in ipairs( data.TradingPosts ) do
			local config:table = PlayerConfigurations[ id ];
			if config ~= nil then table.insert( d.tradingPosts, Locale.Lookup( config:GetPlayerName() ) ); end
		end
	end );
	return d;
end
