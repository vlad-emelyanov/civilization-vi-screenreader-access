-- ===========================================================================
--	ScreenReaderAccess: keyboard navigation and speech for the World Climate screen (Gathering Storm)
--
--	Replaces DLC/Expansion2/UI/Additions/ClimateScreen.lua (ReplaceUIScript, LuaContext ClimateScreen). The original is
--	not copied: it is included by name (like DLC/GranColombia_Maya/UI/Replacements/ClimateScreen_GranColombia_Maya.lua
--	does) and its global functions are wrapped. Its file-local state (m_tabs, m_currentTabName, ...) is not reachable, so
--	everything spoken is read from GameClimate / GameRandomEvents / GameInfo again.
--
--	Tab / Control+Tab (Shift+Tab is the Steam overlay) switch between Overview, CO2 levels and Event history, Up/Down/Home/End
--	walk the items, Space or Enter = details, Escape closes. Every key is swallowed while the screen is open except
--	function keys, Page Down (the toggle hotkey) and Control / Alt chords.
--	Wording: Accessibility/ClimateText.lua
-- ===========================================================================
include( "ClimateScreen" );
include( "ScreenReader" );
include( "KeyNavList" );
include( "ClimateText" );
print( "ScreenReaderAccess: ClimateScreen copy loaded" );

local SRA_MAX_PHASES	:number = 7;		-- MAX_PHASES of the original (a file-local there)
local SRA_NUCLEAR		:string = "NUCLEAR_ACCIDENT";
local SRA_SEA_LEVEL		:string = "SEA_LEVEL";

local m_srList			:table = nil;
local m_srTab			:string = "Overview";

local SRA_TABS:table = {
	{ name = "Overview",		label = "Overview",			select = function() TabSelectOverview(); end },
	{ name = "CO2Levels",		label = "CO2 levels",		select = function() TabSelectCO2Levels(); end },
	{ name = "EventHistory",	label = "Event history",	select = function() TabSelectEventHistory(); end },
};

local function SRA_Safe( fn, what:string )
	local ok:boolean, err = xpcall( fn, KeyNavErrorHandler );
	if not ok then print( "ClimateScreen " .. what .. " error: " .. tostring( err ) ); end
	return ok;
end

local function SRA_Say( text:string, nointerrupt:boolean )
	OutputMessageToScreenReader( text, nointerrupt );
end

local function SRA_Clean( text )
	return CleanTextForSpeech( text or "" );
end

local function SRA_Lookup( tag, ... )
	if tag == nil then return ""; end
	return SRA_Clean( Locale.Lookup( tag, ... ) );
end

-- ---------------------------------------------------------------------------
--	Climate data (same sources as the original screen)
-- ---------------------------------------------------------------------------

-- Current climate phase (0..7) and its random event row, like UpdateClimateChangeEventsData.
local function SRA_Phase()
	local points:number = GameClimate.GetClimateChangeForLastSeaLevelEvent();
	local firstIndex:number = -1;
	local currentIndex:number = -1;
	local phase:number = 0;
	for row in GameInfo.RandomEvents() do
		if row.EffectOperatorType == SRA_SEA_LEVEL then
			if firstIndex == -1 then firstIndex = row.Index; end
			if row.ClimateChangePoints == points then
				currentIndex = row.Index;
				phase = currentIndex - firstIndex + 1;
			end
		end
	end
	local event = nil;
	if currentIndex >= 0 then event = GameInfo.RandomEvents[ currentIndex ]; end
	return phase, event, currentIndex;
end

-- { id, name, amount } for every major civilization that was ever alive, biggest emitter first
local function SRA_Footprints()
	local list:table = {};
	local localID:number = Game.GetLocalPlayer();
	local diplomacy = Players[ localID ]:GetDiplomacy();
	for _, player in ipairs( PlayerManager.GetWasEverAliveMajors() ) do
		local id:number = player:GetID();
		local config:table = PlayerConfigurations[ id ];
		local name:string = Locale.Lookup( config:GetCivilizationDescription() );
		if id == localID then
			name = Locale.Lookup( "LOC_CLIMATE_YOU", name );
		elseif not diplomacy:HasMet( id ) then
			name = Locale.Lookup( "LOC_WORLD_RANKING_UNMET_PLAYER" );
		end
		table.insert( list, { id = id, name = SRA_Clean( name ), amount = GameClimate.GetPlayerCO2Footprint( id, false ) } );
	end
	table.sort( list, function( a, b )
		if a.amount ~= b.amount then return a.amount > b.amount; end
		return a.id < b.id;
	end );
	return list;
end

-- Rank of the local player among the living major civilizations, and how many there are
local function SRA_Rank()
	local localID:number = Game.GetLocalPlayer();
	local mine:number = GameClimate.GetPlayerCO2Footprint( localID, false );
	local rank:number = 1;
	local count:number = 0;
	for _, player in ipairs( PlayerManager.GetAliveMajors() ) do
		count = count + 1;
		if player:GetID() ~= localID and GameClimate.GetPlayerCO2Footprint( player:GetID(), false ) > mine then rank = rank + 1; end
	end
	return rank, count;
end

-- CO2 per resource: rows { name, amount, detail }; perPlayer = only the local player
local function SRA_ResourceRows( perPlayer:boolean )
	local rows:table = {};
	local localID:number = Game.GetLocalPlayer();
	local players:table = PlayerManager.GetAliveMajors();
	for resourceInfo in GameInfo.Resources() do
		local consumption:table = GameInfo.Resource_Consumption[ resourceInfo.ResourceType ];
		if consumption ~= nil and consumption.CO2perkWh ~= nil and consumption.CO2perkWh > 0 then
			local amount:number = 0;
			local lastAmount:number = 0;
			local lastResource:number = 0;
			if perPlayer then
				amount = GameClimate.GetPlayerResourceCO2Footprint( localID, resourceInfo.Index, false );
				lastAmount = GameClimate.GetPlayerResourceCO2Footprint( localID, resourceInfo.Index, true );
				lastResource = GameClimate.GetPlayerRawResourceConsumption( localID, resourceInfo.Index, true );
			else
				for _, player in ipairs( players ) do
					local id:number = player:GetID();
					amount = amount + GameClimate.GetPlayerResourceCO2Footprint( id, resourceInfo.Index, false );
					lastAmount = lastAmount + GameClimate.GetPlayerResourceCO2Footprint( id, resourceInfo.Index, true );
					lastResource = lastResource + GameClimate.GetPlayerRawResourceConsumption( id, resourceInfo.Index, true );
				end
			end
			if amount > 0 then
				local name:string = SRA_Lookup( resourceInfo.Name );
				local tag:string = perPlayer and "LOC_CLIMATE_RESOURCE_CONSUMED_LAST_TURN" or "LOC_CLIMATE_RESOURCE_CONSUMED_LAST_TURN_GLOBAL";
				table.insert( rows, { name = name, amount = amount, detail = SRA_Lookup( tag, lastResource, name, lastAmount ) } );
			end
		end
	end
	table.sort( rows, function( a, b ) return a.amount > b.amount; end );
	return rows;
end

-- Continent / territory / water name of a plot index, like the original's event rows
local function SRA_Location( plotIndex:number )
	local plot = Map.GetPlotByIndex( plotIndex );
	if plot == nil then return ""; end
	local continent:number = plot:GetContinentType();
	if continent ~= nil and continent ~= -1 then
		return SRA_Lookup( GameInfo.Continents[ continent ].Description );
	end
	local territory = Territories.GetTerritoryAt( plotIndex );
	if territory ~= nil then return SRA_Lookup( territory:GetName() ); end
	return SRA_Lookup( "LOC_CLIMATE_SCREEN_WATER" );
end

-- ---------------------------------------------------------------------------
--	Items per tab
-- ---------------------------------------------------------------------------
local function SRA_Chances( items:table )
	local section:string = "Disaster chances";
	local function add( key:string, text:string, detail:string )
		table.insert( items, { key = key, section = section, text = text, detail = detail } );
	end
	add( "storm", ClimateText_Chance( "Storms", GameClimate.GetStormPercentChance(), GameClimate.GetStormClimateIncreasedChance() ),
		"Chance of a storm each turn. The part from climate change grows with every phase" );
	add( "flood", ClimateText_Chance( "River floods", GameClimate.GetFloodPercentChance(), GameClimate.GetFloodClimateIncreasedChance() ),
		ClimateText_Plural( RiverManager.GetNumFloodableRivers(), "river can flood", "rivers can flood" ) .. " of " .. RiverManager.GetNumRivers() );
	add( "drought", ClimateText_Chance( "Droughts", GameClimate.GetDroughtPercentChance(), GameClimate.GetDroughtClimateIncreasedChance() ), nil );
	if GameClimate.GetFirePercentChance ~= nil then
		add( "fire", ClimateText_Chance( "Forest fires", GameClimate.GetFirePercentChance(), GameClimate.GetFireClimateIncreasedChance() ), nil );
	end
	local total:number = MapFeatureManager.GetNumNormalVolcanoes();
	local active:number = MapFeatureManager.GetNumActiveVolcanoes();
	add( "volcano", ClimateText_Volcanoes( GameClimate.GetEruptionPercentChance(), active, total - active,
		MapFeatureManager.GetNumNaturalWonderVolcanoes(), MapFeatureManager.GetNumEruptions() ), nil );
end

local function SRA_CurrentEvent()
	local event = GameRandomEvents.GetCurrentTurnEvent();
	if event == nil then return nil; end
	local def = GameInfo.RandomEvents[ event.RandomEvent ];
	if def == nil or def.EffectOperatorType == SRA_SEA_LEVEL or def.EffectOperatorType == SRA_NUCLEAR then return nil; end
	local revealed:boolean = false;
	local plot = Map.GetPlotByIndex( event.CurrentLocation );
	local visibility = PlayersVisibility[ Game.GetLocalPlayer() ];
	if plot ~= nil and visibility ~= nil and visibility:IsRevealed( plot:GetX(), plot:GetY() ) then revealed = true; end
	local text:string = "Current disaster: " .. SRA_Lookup( def.Name );
	if revealed and event.Name ~= nil then text = text .. ", " .. SRA_Lookup( event.Name ); end
	if def.Global then
		text = text .. ", global";
	elseif revealed then
		local location:string = SRA_Location( event.CurrentLocation );
		if location ~= "" then text = text .. ", over " .. location; end
	else
		text = text .. ", location not revealed";
	end
	local detail = nil;
	if def.EffectString ~= nil then detail = SRA_Lookup( def.EffectString ); end
	return text, detail;
end

local function SRA_OverviewItems()
	local items:table = {};
	local phase:number, phaseEvent, phaseIndex:number = SRA_Phase();
	local localID:number = Game.GetLocalPlayer();
	local total:number = GameClimate.GetTotalCO2Footprint();
	local mine:number = GameClimate.GetPlayerCO2Footprint( localID, false );
	local rank:number, count:number = SRA_Rank();
	local temperature:number = GameClimate.GetTemperatureChange();

	local seaLevelKey:string = ( phaseEvent ~= nil and phaseEvent.Description ) or "0";
	local seaLevel:string = SRA_Lookup( "LOC_CLIMATE_SEA_LEVEL_RISE", Locale.Lookup( seaLevelKey ) );
	local nextRise:number = GameClimate.GetNextSeaLevelRiseTurns();
	local nextIce:number = GameClimate.GetNextIceLossTurns();
	if phase >= SRA_MAX_PHASES then nextRise = 0; nextIce = 0; end

	table.insert( items, { key = "summary", text = ClimateText_Summary{
		phase = phase, maxPhases = SRA_MAX_PHASES, phaseName = phaseEvent and SRA_Lookup( phaseEvent.Name ) or nil,
		temperature = temperature, seaLevel = seaLevel, nextRiseTurns = nextRise,
		contribution = ClimateText_Contribution( mine, total, rank, count ) },
		detail = phaseEvent and SRA_Lookup( phaseEvent.LongDescription ) or "No climate change phase has been reached yet" } );

	-- climate change points
	local pointsText:string = "Climate change points " .. GameClimate.GetClimateChangeLevel() .. ", "
		.. ClimateText_Signed( GameClimate.GetClimateChangeFromRealism() ) .. " from world realism, "
		.. ClimateText_Signed( GameClimate.GetClimateChangeFromTemperature() ) .. " from global temperature";
	local pointsDetail = nil;
	if phase < SRA_MAX_PHASES and phaseIndex ~= nil then
		local nextEvent = GameInfo.RandomEvents[ phaseIndex + 1 ];
		if phase == 0 then
			for row in GameInfo.RandomEvents() do
				if row.EffectOperatorType == SRA_SEA_LEVEL then nextEvent = row; break; end
			end
		end
		if nextEvent ~= nil and nextEvent.EffectOperatorType == SRA_SEA_LEVEL then
			pointsDetail = "Phase " .. ( phase + 1 ) .. " needs " .. nextEvent.ClimateChangePoints .. " points";
		end
	end
	table.insert( items, { key = "points", text = pointsText, detail = pointsDetail } );

	-- CO2
	local topID:number = GetWorstCO2PlayerID();
	local top:string = SRA_Lookup( "LOC_CLIMATE_NO_ONE" );
	if topID ~= -1 and PlayerConfigurations[ topID ] ~= nil then top = SRA_Lookup( PlayerConfigurations[ topID ]:GetPlayerName() ); end
	table.insert( items, { key = "co2", text = "CO2: global total " .. total .. ", top contributor " .. top .. ", yours " .. mine,
		detail = SRA_Lookup( "LOC_CLIMATE_CO2_TOTAL_TOOLTIP", GameClimate.GetCO2FootprintModifier() ) } );

	-- temperature
	local tempDetail = nil;
	local deforestation:number = GameClimate.GetDeforestationType();
	if deforestation ~= nil and deforestation >= 0 then
		local level:table = GameInfo.DeforestationLevels[ deforestation ];
		tempDetail = SRA_Lookup( "LOC_CLIMATE_TEMPERATURE_TOOLTIP", level.Name, level.Description, GameClimate.GetCO2FootprintModifier() );
	end
	table.insert( items, { key = "temperature", text = string.upper( string.sub( ClimateText_Temperature( temperature ), 1, 1 ) )
		.. string.sub( ClimateText_Temperature( temperature ), 2 ), detail = tempDetail } );

	-- sea level and polar ice
	local seaText:string = seaLevel .. ", " .. ClimateText_Plural( GameClimate.GetTilesFlooded(), "coastal tile flooded", "coastal tiles flooded" )
		.. ", " .. ClimateText_Plural( GameClimate.GetTilesSubmerged(), "tile submerged", "tiles submerged" );
	if nextRise > 0 then seaText = seaText .. ", next rise in " .. ClimateText_Plural( nextRise, "turn", "turns" ); end
	table.insert( items, { key = "sea", text = seaText,
		detail = SRA_Lookup( "LOC_CLIMATE_SEA_LEVEL_RISE_DESCRIPTION_TOOLTIP", seaLevelKey ) } );
	local iceText:string = "Polar ice lost " .. ( phaseEvent and phaseEvent.IceLoss or 0 );
	if nextIce > 0 then iceText = iceText .. ", next loss in " .. ClimateText_Plural( nextIce, "turn", "turns" ); end
	table.insert( items, { key = "ice", text = iceText } );

	local current, currentDetail = SRA_CurrentEvent();
	if current ~= nil then table.insert( items, { key = "current", text = current, detail = currentDetail } ); end

	SRA_Chances( items );
	return items;
end

local function SRA_CO2Items()
	local items:table = {};
	local total:number = GameClimate.GetTotalCO2Footprint();
	local modifier:number = GameClimate.GetCO2FootprintModifier();
	local totalText:string = "CO2: global total " .. total;
	if modifier ~= 0 then totalText = totalText .. ", modifier " .. ClimateText_Signed( modifier ); end
	totalText = totalText .. ", yours " .. GameClimate.GetPlayerCO2Footprint( Game.GetLocalPlayer(), false );
	table.insert( items, { key = "total", text = totalText, detail = SRA_Lookup( "LOC_CLIMATE_CO2_TOTAL_TOOLTIP", modifier ) } );

	for _, civ in ipairs( SRA_Footprints() ) do
		table.insert( items, { key = "civ" .. civ.id, section = "By civilization", text = ClimateText_Row( civ.name, civ.amount, total ) } );
	end
	for i, row in ipairs( SRA_ResourceRows( false ) ) do
		table.insert( items, { key = "res" .. row.name, section = "By resource, all civilizations", text = ClimateText_Row( row.name, row.amount, total ), detail = row.detail } );
	end
	local mineRows:table = SRA_ResourceRows( true );
	local mineTotal:number = 0;
	for _, row in ipairs( mineRows ) do mineTotal = mineTotal + row.amount; end
	for _, row in ipairs( mineRows ) do
		table.insert( items, { key = "mine" .. row.name, section = "Your CO2 by resource", text = ClimateText_Row( row.name, row.amount, mineTotal ), detail = row.detail } );
	end
	return items;
end

local function SRA_EventItems()
	local items:table = {};
	local visibility = PlayersVisibility[ Game.GetLocalPlayer() ];
	for turn = Game.GetCurrentGameTurn(), 0, -1 do
		local event = GameRandomEvents.GetEventsForTurn( turn );
		if event ~= nil then
			local def = GameInfo.RandomEvents[ event.RandomEvent ];
			if def ~= nil then
				if def.ClimateChangePoints > 0 then
					table.insert( items, { key = "t" .. turn .. "p", section = "Climate phases",
						text = ClimateText_Event{ turn = turn, typeName = SRA_Lookup( def.Name ) .. " reached" } } );
				elseif def.EffectOperatorType ~= SRA_NUCLEAR then
					local plot = Map.GetPlotByIndex( event.CurrentLocation );
					local known:boolean = def.Global == true
						or ( plot ~= nil and visibility ~= nil and visibility:IsRevealed( plot:GetX(), plot:GetY() ) );
					if known then
						table.insert( items, { key = "t" .. turn .. "e" .. #items, section = "Disasters",
							text = ClimateText_Event{ turn = turn, typeName = SRA_Lookup( def.Name ), name = SRA_Lookup( event.Name ),
								location = def.Global and "global" or SRA_Location( event.StartLocation ),
								effects = ClimateText_Effects( event.FertilityAdded, event.TilesDamaged, event.UnitsLost, event.PopLost ) },
							detail = def.EffectString and SRA_Lookup( def.EffectString ) or nil } );
					end
				end
			end
		end
	end
	if #items == 0 then items[1] = { key = "none", text = "No climate events yet" }; end
	return items;
end

local function SRA_Items()
	local items:table;
	if m_srTab == "CO2Levels" then
		items = SRA_CO2Items();
	elseif m_srTab == "EventHistory" then
		items = SRA_EventItems();
	else
		items = SRA_OverviewItems();
	end
	return items;
end

-- ---------------------------------------------------------------------------
--	Tabs, open, close, input
-- ---------------------------------------------------------------------------
local function SRA_TabIndex()
	for i, tab in ipairs( SRA_TABS ) do
		if tab.name == m_srTab then return i; end
	end
	return 1;
end

local function SRA_ReadDetail()
	local key = m_srList.GetFocusKey();
	for _, item in ipairs( SRA_Items() ) do
		if item.key == key then
			SRA_Say( item.detail or "No further details" );
			return;
		end
	end
	SRA_Say( "No further details" );
end

local function SRA_EnsureList()
	if m_srList ~= nil then return; end
	m_srList = KeyNavList_Create{
		build = SRA_Items,
		isActive = function() return not ContextPtr:IsHidden(); end,
		onActivate = function() SRA_ReadDetail(); end,
	};
end

local function SRA_AnnounceTab( prefix:string, nointerrupt:boolean )
	SRA_EnsureList();
	m_srList.Reset();
	local items:table = SRA_Items();
	m_srList.Open( "World Climate", items[1].key, true );
	local index:number = SRA_TabIndex();
	local first:string = items[1].text;
	if items[1].section ~= nil then first = items[1].section .. ": " .. first; end
	SRA_Say( prefix .. ClimateText_Tab( SRA_TABS[ index ].label, index, #SRA_TABS ) .. ". " .. first .. ", 1 of " .. #items, nointerrupt );
end

local function SRA_SwitchTab( delta:number )
	local target:number = SRA_TabIndex() + delta;
	if target < 1 then target = #SRA_TABS; end
	if target > #SRA_TABS then target = 1; end
	SRA_TABS[ target ].select();		-- the original's own tab function: shows the pane (and calls RealizeTabs, which sets m_srTab)
	SRA_AnnounceTab( "", false );
end

local function SRA_IsFunctionKey( key:number )
	for n = 1, 12 do
		if Keys[ "VK_F" .. n ] ~= nil and Keys[ "VK_F" .. n ] == key then return true; end
	end
	return false;
end

local function SRA_HandleInput( input:table )
	if ContextPtr:IsHidden() then return false; end
	local msg:number = input:GetMessageType();
	if msg ~= KeyEvents.KeyDown and msg ~= KeyEvents.KeyUp then return false; end
	local key:number = input:GetKey();
	if SRA_IsFunctionKey( key ) then return false; end
	if Keys.VK_NEXT ~= nil and key == Keys.VK_NEXT then return false; end		-- Page Down: the game's toggle hotkey
	local isUp:boolean = ( msg == KeyEvents.KeyUp );
	if key == Keys.VK_TAB then
		if isUp then SRA_Safe( function() SRA_SwitchTab( ( input:IsShiftDown() or input:IsControlDown() ) and -1 or 1 ); end, "tab" ); end
		return true;
	end
	if input:IsControlDown() or input:IsAltDown() then return false; end
	if key == Keys.VK_ESCAPE then
		if isUp then SRA_Safe( Close, "close" ); end
		return true;
	end
	SRA_EnsureList();
	m_srList.HandleInput( input );
	return true;
end

local function SRA_OnInput( input:table )
	if SRA_HandleInput( input ) then return true; end
	return OnInputHandler( input );		-- the original (Escape closes)
end

-- Wrappers around the original's global functions (it looks them up by name at call time)
local BASE_RealizeTabs = RealizeTabs;
function RealizeTabs( selectedTabName:string )
	m_srTab = selectedTabName;
	BASE_RealizeTabs( selectedTabName );
end

local BASE_Open = Open;
function Open( selectedTabName:string )
	local wasHidden:boolean = ContextPtr:IsHidden();
	BASE_Open( selectedTabName );
	if wasHidden and Game.GetLocalPlayer() ~= -1 then
		SRA_Safe( function() SRA_AnnounceTab( "World Climate. ", true ); end, "open" );
	end
end

local BASE_Close = Close;
function Close()
	if not ContextPtr:IsHidden() then SRA_Say( "Climate closed" ); end
	BASE_Close();
end

-- The original set its input handler while it was included; ours goes first and falls back to the original's.
if GameCapabilities.HasCapability( "CAPABILITY_WORLD_CLIMATE_VIEW" ) then
	ContextPtr:SetInputHandler( SRA_OnInput, true );
end
