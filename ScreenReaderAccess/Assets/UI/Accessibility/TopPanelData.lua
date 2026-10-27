-- ===========================================================================
--	TopPanelData: the values of the game's top panel as short sentences for the screen reader.
--	Used by the InGameAccess hub (Control+Y region, Control+G summary). The numbers come from the same player
--	APIs and tooltip helpers that TopPanel.lua (Expansion2 copy when Gathering Storm is active) uses, so they match
--	the screen; the tooltips are the game's own breakdowns (ToolTipHelper_PlayerYields).
--
--	TopPanelData_BuildItems() -> array of { key, text, detail, open = "research"|"civic"|nil, summary = <short> }
--	  text:    "Gold 45, plus 6 per turn"
--	  detail:  the tooltip breakdown, cleaned for speech (Space)
--	  open:    which game screen Enter opens
--	TopPanelData_Summary() -> "Gold 45, plus 6. Science plus 4. ..." (the four basic yields)
-- ===========================================================================

include( "ScreenReader" );
include( "ToolTipHelper_PlayerYields" );

local function Num( value:number )
	return Locale.ToNumber( value, "#,###.#" );
end

local function Round1( value:number )
	return math.floor( value * 10 + 0.5 ) / 10;
end

-- The number as the TopPanel's FormatValuePerTurn shows it ("+2.5", "-1.2", "0"), said as "plus 2.5".
local function SignedWords( value:number )
	value = Round1( value );
	if value == 0 then return "0"; end		-- also -0.04 and 0.04, which would read "plus 0"
	local text:string = Locale.Lookup( "{1: number +#,###.#;-#,###.#}", value );
	local sign:string = string.sub( text, 1, 1 );
	if sign == "+" then return "plus " .. string.sub( text, 2 ); end
	if sign == "-" then return "minus " .. string.sub( text, 2 ); end
	return text;
end

-- "plus 6 per turn" / "minus 2 per turn" / "0 per turn"
local function PerTurn( value:number )
	return SignedWords( value ) .. " per turn";
end

-- Same without the unit, for the one-line summary; nil when there is no change.
local function PerTurnShort( value:number )
	if value == 0 then return nil; end
	return SignedWords( value );
end

local function WithBalance( name:string, balance:number, value:number )
	local text:string = name .. " " .. Num( balance );
	local short:string = PerTurnShort( value );
	if short ~= nil then text = text .. ", " .. short; end
	return text;
end

local function Clean( text:string )
	text = CleanTextForSpeech( text );
	text = string.gsub( text, "%.%s*%.", "." );		-- "[NEWLINE][NEWLINE]" gives ". ."
	return text;
end

local function Add( items:table, item:table )
	table.insert( items, item );
end

-- Diplomatic favor exists in Gathering Storm only; the player API may answer (with 0) in other rulesets, where the
-- game's TopPanel shows nothing.
local function HasFavor()
	return GameConfiguration.GetRuleSet() == "RULESET_EXPANSION_2" or GameCapabilities.HasCapability( "CAPABILITY_WORLD_CONGRESS" );
end

local function ResourceItems( items:table, player:table )
	if not GameCapabilities.HasCapability( "CAPABILITY_DISPLAY_TOP_PANEL_RESOURCES" ) then return; end
	local resources:table = player:GetResources();
	for resource in GameInfo.Resources() do
		if resource.ResourceClassType == "RESOURCECLASS_STRATEGIC" then
			local amount:number = resources:GetResourceAmount( resource.ResourceType );
			-- Gathering Storm has stockpiles with a cap; the API may exist elsewhere with a cap of 0: then the base format
			local cap:number = 0;
			if resources.GetResourceStockpileCap ~= nil then cap = resources:GetResourceStockpileCap( resource.ResourceType ) or 0; end
			if cap > 0 then
				-- Gathering Storm: stockpile with a cap, accumulation per turn, consumption (TopPanel_Expansion2 RefreshResources)
				local reserved:number = resources:GetReservedResourceAmount( resource.ResourceType );
				local accumulation:number = resources:GetResourceAccumulationPerTurn( resource.ResourceType );
				local imported:number = resources:GetResourceImportPerTurn( resource.ResourceType );
				local bonus:number = resources:GetBonusResourcePerTurn( resource.ResourceType );
				local unitUse:number = resources:GetUnitResourceDemandPerTurn( resource.ResourceType );
				local powerUse:number = resources:GetPowerResourceDemandPerTurn( resource.ResourceType );
				local use:number = unitUse + powerUse;
				local gain:number = accumulation + imported + bonus;
				if amount > 0 or gain > 0 or use > 0 then
					local name:string = Locale.Lookup( resource.Name );
					local text:string = name .. " " .. amount .. " of " .. cap .. ", " .. PerTurn( gain );
					if use > 0 then text = text .. ", uses " .. use .. " per turn"; end
					local total:number = math.min( amount + reserved, cap );
					local detail:string = name .. ". " .. total .. " of " .. cap .. " " .. Locale.Lookup( "LOC_RESOURCE_ITEM_IN_STOCKPILE" );
					if reserved ~= 0 then detail = detail .. ". " .. reserved .. " " .. Locale.Lookup( "LOC_RESOURCE_ITEM_IN_RESERVE" ); end
					detail = detail .. ". " .. Locale.Lookup( "LOC_RESOURCE_ACCUMULATION_PER_TURN", gain );
					if accumulation > 0 then detail = detail .. ". " .. Locale.Lookup( "LOC_RESOURCE_ACCUMULATION_PER_TURN_EXTRACTED", accumulation ); end
					if imported > 0 then detail = detail .. ". " .. Locale.Lookup( "LOC_RESOURCE_ACCUMULATION_PER_TURN_FROM_CITY_STATES", imported ); end
					if bonus > 0 then detail = detail .. ". " .. Locale.Lookup( "LOC_RESOURCE_ACCUMULATION_PER_TURN_FROM_BONUS_SOURCES", bonus ); end
					if use > 0 then
						detail = detail .. ". " .. Locale.Lookup( "LOC_RESOURCE_CONSUMPTION", use );
						if unitUse > 0 then detail = detail .. ". " .. Locale.Lookup( "LOC_RESOURCE_UNIT_CONSUMPTION_PER_TURN", unitUse ); end
						if powerUse > 0 then detail = detail .. ". " .. Locale.Lookup( "LOC_RESOURCE_POWER_CONSUMPTION_PER_TURN", powerUse ); end
					end
					Add( items, { key = "res:" .. resource.ResourceType, text = text, detail = Clean( detail ) } );
				end
			elseif amount > 0 then
				-- base game: only the stock is shown
				local name:string = Locale.Lookup( resource.Name );
				Add( items, { key = "res:" .. resource.ResourceType, text = name .. " " .. amount, detail = Clean( name .. ". " .. Locale.Lookup( "LOC_TOOLTIP_STRATEGIC_RESOURCE" ) ) } );
			end
		end
	end
end

local function CurrentResearchItem( items:table, player:table )
	if not GameCapabilities.HasCapability( "CAPABILITY_SCIENCE" ) then return; end
	local techs:table = player:GetTechs();
	local id:number = techs:GetResearchingTech();
	local row:table = ( id ~= nil and id >= 0 ) and GameInfo.Technologies[ id ] or nil;
	if row == nil then
		local open:boolean = false;
		for tech in GameInfo.Technologies() do
			if not techs:HasTech( tech.Index ) then open = true; break; end
		end
		if not open then
			Add( items, { key = "research", text = "Research: all researched", detail = "Every technology is researched." } );
			return;
		end
		Add( items, { key = "research", text = "Research: none chosen, " .. SRKey( "Enter" ) .. " to choose", open = "research",
			detail = "No technology is being researched. " .. SRKey( "Enter" ) .. " opens the research chooser." } );
		return;
	end
	local name:string = Locale.Lookup( row.Name );
	local turns:number = techs:GetTurnsToResearch( id );
	local text:string = "Research: " .. name;
	if turns ~= nil and turns > 0 then text = text .. ", " .. turns .. ( turns == 1 and " turn" or " turns" ); end
	local cost:number = techs:GetResearchCost( id );
	local detail:string = name .. ". " .. math.floor( techs:GetResearchProgress( id ) ) .. " of " .. cost .. " science";
	if turns ~= nil and turns > 0 then detail = detail .. ", " .. turns .. ( turns == 1 and " turn" or " turns" ) .. " left"; end
	if techs:HasBoostBeenTriggered( id ) then detail = detail .. ". Eureka triggered"; end
	Add( items, { key = "research", text = text, detail = detail .. ". " .. SRKey( "Enter" ) .. " opens the research chooser.", open = "research" } );
end

local function CurrentCivicItem( items:table, player:table )
	if not GameCapabilities.HasCapability( "CAPABILITY_CULTURE" ) then return; end
	local culture:table = player:GetCulture();
	local id:number = culture:GetProgressingCivic();
	local row:table = ( id ~= nil and id >= 0 ) and GameInfo.Civics[ id ] or nil;
	if row == nil then
		local open:boolean = false;
		for civic in GameInfo.Civics() do
			if not culture:HasCivic( civic.Index ) then open = true; break; end
		end
		if not open then
			Add( items, { key = "civic", text = "Civic: all researched", detail = "Every civic is researched." } );
			return;
		end
		Add( items, { key = "civic", text = "Civic: none chosen, " .. SRKey( "Enter" ) .. " to choose", open = "civic",
			detail = "No civic is being researched. " .. SRKey( "Enter" ) .. " opens the civics chooser." } );
		return;
	end
	local name:string = Locale.Lookup( row.Name );
	local turns:number = culture:GetTurnsToProgressCivic( id );
	local text:string = "Civic: " .. name;
	if turns ~= nil and turns > 0 then text = text .. ", " .. turns .. ( turns == 1 and " turn" or " turns" ); end
	local cost:number = culture:GetCultureCost( id );
	local detail:string = name .. ". " .. math.floor( culture:GetCulturalProgress( id ) ) .. " of " .. cost .. " culture";
	if turns ~= nil and turns > 0 then detail = detail .. ", " .. turns .. ( turns == 1 and " turn" or " turns" ) .. " left"; end
	if culture:HasBoostBeenTriggered( id ) then detail = detail .. ". Inspiration triggered"; end
	Add( items, { key = "civic", text = text, detail = detail .. ". " .. SRKey( "Enter" ) .. " opens the civics chooser.", open = "civic" } );
end

-- The turn counter as the TopPanel shows it (RefreshTurnsRemaining), with the date.
local function TurnItem( items:table )
	local endTurn:number = Game.GetGameEndTurn();
	local turn:number = Game.GetCurrentGameTurn();
	if GameCapabilities.HasCapability( "CAPABILITY_DISPLAY_NORMALIZED_TURN" ) then
		turn = ( turn - GameConfiguration.GetStartTurn() ) + 1;
		if endTurn > 0 then endTurn = endTurn - GameConfiguration.GetStartTurn(); end
	end
	local text:string = "Turn " .. turn;
	if endTurn > 0 then text = text .. " of " .. ( endTurn - 1 ); end
	text = text .. ", " .. Calendar.MakeYearStr( turn );
	Add( items, { key = "turn", text = text, detail = text } );
end

-- Era (Rise and Fall / Gathering Storm): era name, golden/dark/heroic age, era score.
local function EraItem( items:table, playerID:number )
	local eras:table = Game.GetEras and Game.GetEras() or nil;
	if eras == nil or eras.GetCurrentEra == nil then return; end
	local row:table = GameInfo.Eras[ eras:GetCurrentEra() ];
	if row == nil then return; end
	local text:string = "Era: " .. Locale.Lookup( row.Name );
	local age:string = nil;
	-- HasHeroicGoldenAge only exists with Gathering Storm / Rise and Fall variants: ask each, tolerate a missing one
	local function Has( method:string )
		if eras[ method ] == nil then return false; end
		local ok:boolean, result = pcall( function() return eras[ method ]( eras, playerID ); end );
		return ok and result == true;
	end
	if Has( "HasHeroicGoldenAge" ) then age = "heroic age";
	elseif Has( "HasGoldenAge" ) then age = "golden age";
	elseif Has( "HasDarkAge" ) then age = "dark age";
	end
	if age ~= nil then text = text .. ", " .. age; end
	local detail:string = text;
	local ok:boolean, extra:string = pcall( function()
		local score:number = eras:GetPlayerCurrentScore( playerID );
		local golden:number = eras:GetPlayerGoldenAgeThreshold( playerID );
		local dark:number = eras:GetPlayerDarkAgeThreshold( playerID );
		return ". Era score " .. score .. ", golden age from " .. golden .. ", dark age below " .. dark;
	end );
	if ok then detail = detail .. extra; end
	Add( items, { key = "era", text = text, detail = detail } );
end

local function EnvoyItem( items:table, player:table )
	if not GameCapabilities.HasCapability( "CAPABILITY_TOP_PANEL_ENVOYS" ) then return; end
	local influence:table = player:GetInfluence();
	local tokens:number = influence:GetTokensToGive();
	local points:number = Round1( influence:GetPointsEarned() );
	local threshold:number = influence:GetPointsThreshold();
	local text:string = ( tokens == 1 and "1 envoy" or ( tokens .. " envoys" ) ) .. " to give";
	local detail:string = text .. ". " .. Num( points ) .. " of " .. threshold .. " influence points for the next envoy, "
		.. PerTurn( influence:GetPointsPerTurn() );
	Add( items, { key = "envoys", text = text, detail = detail } );
end

local function TradeItem( items:table, player:table )
	if not GameCapabilities.HasCapability( "CAPABILITY_TRADE" ) then return; end
	local trade:table = player:GetTrade();
	local capacity:number = trade:GetOutgoingRouteCapacity();
	if capacity <= 0 then return; end
	local text:string = "Trade routes " .. trade:GetNumOutgoingRoutes() .. " of " .. capacity;
	Add( items, { key = "trade", text = text, detail = text } );
end

-- Runs one item builder; an API missing in this ruleset loses that item only, not the whole panel.
local function Guard( name:string, f )
	local ok:boolean, err = pcall( f );
	if not ok then print( "TopPanelData " .. name .. " error: " .. tostring( err ) ); end
end

function TopPanelData_BuildItems()
	local items:table = {};
	local playerID:number = Game.GetLocalPlayer();
	if playerID == nil or playerID == -1 then return items; end
	local player:table = Players[ playerID ];
	if player == nil then return items; end
	local yields:boolean = GameCapabilities.HasCapability( "CAPABILITY_DISPLAY_TOP_PANEL_YIELDS" );

	if yields and GameCapabilities.HasCapability( "CAPABILITY_SCIENCE" ) then Guard( "science", function()
		local value:number = player:GetTechs():GetScienceYield();
		Add( items, { key = "science", text = "Science, " .. PerTurn( value ), summary = "Science " .. ( PerTurnShort( value ) or "0" ),
			detail = Clean( GetScienceTooltip() ) } );
	end ); end
	if yields and GameCapabilities.HasCapability( "CAPABILITY_CULTURE" ) then Guard( "culture", function()
		local value:number = player:GetCulture():GetCultureYield();
		Add( items, { key = "culture", text = "Culture, " .. PerTurn( value ), summary = "Culture " .. ( PerTurnShort( value ) or "0" ),
			detail = Clean( GetCultureTooltip() ) } );
	end ); end
	if yields and GameCapabilities.HasCapability( "CAPABILITY_FAITH" ) then Guard( "faith", function()
		local religion:table = player:GetReligion();
		local balance:number = religion:GetFaithBalance();
		local value:number = religion:GetFaithYield();
		Add( items, { key = "faith", text = "Faith " .. Num( balance ) .. ", " .. PerTurn( value ),
			summary = WithBalance( "Faith", balance, value ), detail = Clean( GetFaithTooltip() ) } );
	end ); end
	if yields and GameCapabilities.HasCapability( "CAPABILITY_GOLD" ) then Guard( "gold", function()
		local treasury:table = player:GetTreasury();
		local balance:number = math.floor( treasury:GetGoldBalance() );
		local value:number = treasury:GetGoldYield() - treasury:GetTotalMaintenance();
		Add( items, { key = "gold", text = "Gold " .. Num( balance ) .. ", " .. PerTurn( value ),
			summary = WithBalance( "Gold", balance, value ), detail = Clean( GetGoldTooltip() ) } );
	end ); end
	if yields and GameCapabilities.HasCapability( "CAPABILITY_TOURISM" ) then Guard( "tourism", function()
		local stats:table = player:GetStats();
		local rate:number = Round1( stats:GetTourism() );
		if rate > 0 then		-- the TopPanel hides the tourism button at 0
			local detail:string = Locale.Lookup( "LOC_WORLD_RANKINGS_OVERVIEW_CULTURE_TOURISM_RATE", rate );
			local breakdown:string = stats:GetTourismToolTip();
			if breakdown ~= nil and #breakdown > 0 then detail = detail .. "[NEWLINE]" .. breakdown; end
			Add( items, { key = "tourism", text = "Tourism " .. Num( rate ) .. " per turn", detail = Clean( detail ) } );
		end
	end ); end
	if HasFavor() and player.GetFavor ~= nil and player.GetFavorPerTurn ~= nil then Guard( "favor", function()
		local balance:number = player:GetFavor();
		local value:number = player:GetFavorPerTurn();
		local detail:string = Locale.Lookup( "LOC_WORLD_CONGRESS_TOP_PANEL_FAVOR_TOOLTIP" );
		local more:string = player:GetFavorPerTurnToolTip();
		if more ~= nil and #more > 0 then detail = detail .. "[NEWLINE]" .. more; end
		Add( items, { key = "favor", text = "Diplomatic favor " .. Num( balance ) .. ", " .. PerTurn( value ), detail = Clean( detail ) } );
	end ); end
	Guard( "resources", function() ResourceItems( items, player ); end );
	Guard( "research", function() CurrentResearchItem( items, player ); end );
	Guard( "civic", function() CurrentCivicItem( items, player ); end );
	Guard( "turn", function() TurnItem( items ); end );
	Guard( "era", function() EraItem( items, playerID ); end );
	Guard( "envoys", function() EnvoyItem( items, player ); end );
	Guard( "trade", function() TradeItem( items, player ); end );
	return items;
end

-- "Gold 45, plus 6. Science plus 4. Culture plus 3. Faith 12, plus 1" (the basic yields, no screen needed).
function TopPanelData_Summary()
	local parts:table = {};
	local wanted:table = { gold = true, science = true, culture = true, faith = true };
	for _, item in ipairs( TopPanelData_BuildItems() ) do
		if wanted[ item.key ] and item.summary ~= nil then table.insert( parts, item.summary ); end
	end
	return table.concat( parts, ". " );
end
