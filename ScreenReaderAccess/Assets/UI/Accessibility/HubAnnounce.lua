-- ===========================================================================
--	HubAnnounce: what is next (N), turn / unit / city selection announcements.
--	Part of the InGameAccess hub (see docs/ingame-plan.md, Architecture): included by
--	UI/Additions/InGameAccess.lua. State and functions other hub modules use are fields of HubAnnounce.
-- ===========================================================================
HubAnnounce = {};

local m_pendingUnit			:number = nil;		-- unit selected while the game was still loading: announced once it is ready

-- ===========================================================================
--	WHAT IS NEXT (N)
-- ===========================================================================

-- What the Next Action key (Enter) will do, as the game's action panel says it ("Unit needs orders", "Choose
-- production", "Next turn", ...). Read from the panel's own label so that expansion blockers are covered too.
-- Pure decision table: what Enter does before the end-turn / next-blocker path. Attack under way wins over an armed build.
function HubAnnounce.EnterIntentKind( attackPending:boolean, buildArmed:boolean )
	if attackPending then return "attack"; end
	if buildArmed then return "build"; end
	return nil;
end

-- Single source of truth for N and the Enter key (InGameAccess.HandleInput): kind ("attack" / "build" / nil), spoken text.
function HubAnnounce.EnterIntent()
	local kind:string = HubAnnounce.EnterIntentKind( HubCore.AttackPendingActive(), HubSettle.BuildEnterArmed() );
	if kind == "attack" then return kind, "Attack under way, wait for the result"; end
	if kind == "build" then return kind, HubSettle.ArmedEnterText(); end
	return nil, nil;
end

function HubAnnounce.SpeakWhatsNext()
	if not HubCore.IsLocalPlayerActive() then return; end
	-- placing a district / wonder, or choosing a tile for an order: say what Enter does there, not the end-turn label
	local placing:string = HubPlacement.NextText();
	if placing ~= nil then OutputMessageToScreenReader( placing ); return; end
	local targetMode, targetLabel = HubTargets.GetTargetMode();
	if targetLabel ~= nil then
		OutputMessageToScreenReader( "Choosing a tile: " .. targetLabel .. ". " .. SRKey( "Enter" ) .. " confirms, " .. SRKey( "Escape" ) .. " cancels" );
		return;
	end
	HubSettle.RestoreJustCleared();
	local intentKind:string, intentText:string = HubAnnounce.EnterIntent();
	if intentText ~= nil then OutputMessageToScreenReader( intentText ); return; end
	local label:table = ContextPtr:LookUpControl( "/InGame/HUD/ActionPanel/EndTurnText" );
	local text:string = nil;
	if label ~= nil then text = CleanTextForSpeech( label:GetText() ); end
	if text == nil or text == "" then
		OutputMessageToScreenReader( "Next action unknown" );
		return;
	end
	-- The game's "Please wait" while a World Congress session is open: say what actually blocks the turn
	local okWait:boolean, isWait:boolean = pcall( function()
		-- (the label also stays on the plain end-turn text after Escape closed the popup, while the Resume Congress blocker is pending)
		for _, key in ipairs( { "LOC_ACTION_PANEL_PLEASE_WAIT", "LOC_ACTION_PANEL_NEXT_TURN", "LOC_ACTION_PANEL_END_TURN" } ) do
			if string.lower( text ) == string.lower( CleanTextForSpeech( Locale.Lookup( key ) ) ) then return true; end
		end
		return string.lower( text ) == "end turn";
	end );
	if okWait and isWait then
		local okCongress:boolean, inSession:boolean = pcall( function() return Game.GetWorldCongress():IsInSession(); end );
		if okCongress and inSession then
			OutputMessageToScreenReader( "World Congress in session. " .. SRKey( "Enter" ) .. " or " .. SRKey( "Control+N", "RB" ) .. " resumes it" );
			return;
		end
	end
	local spoken:string = HubCore.Capitalize( text );
	local okDetail:boolean, detailed = pcall( HubAnnounce.BlockerDetail, spoken, text );
	if okDetail and detailed ~= nil then spoken = detailed; end
	local okRaid:boolean, raid = pcall( function() return HubEnemies ~= nil and HubEnemies.RaidExpectedLine() or nil; end );
	if okRaid and raid ~= nil then spoken = spoken .. ". " .. raid; end
	OutputMessageToScreenReader( spoken );
end

-- Pure wording: "Unit needs orders" + "Archer, 2 tiles east of Rome" + "Enter selects it" -> "Unit needs orders: Archer, ...
-- Enter selects it". No thing: the plain text.
function HubAnnounce.BlockerWithThing( text:string, thing:string, hint:string )
	if text == nil or text == "" or thing == nil or thing == "" then return text; end
	local result:string = text .. ": " .. thing;
	if hint ~= nil and hint ~= "" then result = result .. ". " .. hint; end
	return result;
end

-- The units that need orders, the selected one included (it is the only one that needs orders in the common case). Second
-- result: whether the selected unit is one of them. UI.SelectNextReadyUnit has its own order and gives no preview, so a
-- unit is named only when it is the only candidate.
function HubAnnounce.ReadyUnits()
	local player:table = Players[ Game.GetLocalPlayer() ];
	local list:table = {};
	local selectedReady:boolean = false;
	if player == nil then return list, selectedReady; end
	local selected:table = UI.GetHeadSelectedUnit();
	for _, unit in player:GetUnits():Members() do
		if unit:GetMovesRemaining() > 0 and HubPlaces.UnitActivity( unit, true ) == "needs orders" then
			table.insert( list, unit );
			if selected ~= nil and unit:GetID() == selected:GetID() then selectedReady = true; end
		end
	end
	return list, selectedReady;
end

-- Pure wording: none -> the plain text, one -> named (thing; "Enter selects it", or when that one is already selected
-- "selected. Tab opens its actions"), several -> the count.
function HubAnnounce.ReadyUnitsText( text:string, count:number, thing:string, isSelected:boolean )
	if count == 1 then
		if isSelected then
			return HubAnnounce.BlockerWithThing( text, thing and ( thing .. ", selected" ), SRKey( "Tab" ) .. " opens its actions" );
		end
		return HubAnnounce.BlockerWithThing( text, thing, SRKey( "Enter" ) .. " selects it" );
	end
	if count > 1 then return count .. " units need orders. " .. SRKey( "Enter" ) .. " selects the next one"; end
	return text;
end

-- N: the blocker text plus the thing Enter takes you to, when that is cheap to find ("Unit needs orders: Archer, 2 tiles
-- east of Rome. Enter selects it", "Choose production: Rome"). nil: nothing to add.
function HubAnnounce.BlockerDetail( spoken:string, label:string )
	local lower:string = string.lower( label );
	if lower == string.lower( CleanTextForSpeech( Locale.Lookup( "LOC_ACTION_PANEL_NEEDS_ORDERS" ) ) ) then
		local units:table, selectedReady:boolean = HubAnnounce.ReadyUnits();
		local thing:string = nil;
		if #units == 1 then
			thing = PlotDescription_FormationName( units[1], Locale.Lookup( units[1]:GetName() ) );
			local position:string = HubAnnounce.PositionText( Map.GetPlot( units[1]:GetX(), units[1]:GetY() ) );
			if position ~= nil then thing = thing .. ", " .. position; end
		end
		return HubAnnounce.ReadyUnitsText( spoken, #units, thing, selectedReady );
	elseif lower == string.lower( CleanTextForSpeech( Locale.Lookup( "LOC_ACTION_PANEL_NEEDS_PRODUCTION" ) ) ) then
		local names:table = {};
		for _, city in Players[ Game.GetLocalPlayer() ]:GetCities():Members() do
			local queue:table = city:GetBuildQueue();
			if queue ~= nil and queue:GetCurrentProductionTypeHash() == 0 then table.insert( names, Locale.Lookup( city:GetName() ) ); end
		end
		if #names == 0 then return nil; end
		local thing:string = names[1];
		if #names > 1 then thing = thing .. " and " .. HubCore.Plural( #names - 1, "more city", "more cities" ); end
		return HubAnnounce.BlockerWithThing( spoken, thing, nil );
	end
	return nil;
end

-- ===========================================================================
--	ANNOUNCEMENTS
-- ===========================================================================

function HubAnnounce.UnitText( unit:table )
	local parts:table = { PlotDescription_FormationName( unit, Locale.Lookup( unit:GetName() ) ) };
	local state:string = PlotDescription_UnitStateText( unit );
	if state ~= nil then table.insert( parts, state ); end
	local maxMoves:number = unit:GetMaxMoves();
	if maxMoves > 0 then
		table.insert( parts, HubCore.FormatNumber( unit:GetMovesRemaining() ) .. " of " .. HubCore.FormatNumber( maxMoves ) .. " moves" );
	end
	local row:table = GameInfo.Units[ unit:GetUnitType() ];
	if row ~= nil and row.BuildCharges ~= nil and row.BuildCharges > 0 then
		local charges:number = unit:GetBuildCharges();
		table.insert( parts, charges .. ( charges == 1 and " charge" or " charges" ) );
	end
	local damage:number = unit:GetDamage();
	if damage > 0 then
		table.insert( parts, ( unit:GetMaxDamage() - damage ) .. " of " .. unit:GetMaxDamage() .. " health" );
	end
	-- a carrier: how many aircraft it holds (same API as the unit flag's air counter)
	if unit.GetAirSlots ~= nil then
		local slots:number = unit:GetAirSlots();
		if slots ~= nil and slots > 0 then
			local hasAir:boolean, airUnits:table = unit:GetAirUnits();
			local count:number = ( hasAir and airUnits ~= nil ) and #airUnits or 0;
			if count == 0 then
				table.insert( parts, "no aircraft, " .. slots .. " slots" );
			else
				table.insert( parts, "carrying " .. count .. " of " .. slots .. " aircraft" );
			end
		end
	end
	-- what it is doing (exploring, fortified, moving to ...); a unit picked from the places list also hears how to cancel
	if HubPlaces ~= nil then
		local activity:string = HubPlaces.UnitActivity( unit, false );
		if activity ~= nil then
			table.insert( parts, activity );
			if HubPlaces.TakeCancelHint( unit ) then
				local hint:string = HubPlaces.OrderHint( unit );
				if hint ~= nil then return table.concat( parts, ", " ) .. ". " .. hint; end
			end
		end
	end
	return table.concat( parts, ", " );
end

-- "in Rome" / "2 tiles south-east of Rome": where a plot is, seen from the nearest own city (nil without cities).
function HubAnnounce.PositionText( plot:table )
	local owner:table = Players[ Game.GetLocalPlayer() ];
	if owner == nil or plot == nil then return nil; end
	local bestDistance:number, bestCity:table = 99, nil;
	for _, city in owner:GetCities():Members() do
		local distance:number = Map.GetPlotDistance( plot:GetX(), plot:GetY(), city:GetX(), city:GetY() );
		if distance < bestDistance then bestDistance, bestCity = distance, city; end
	end
	if bestCity == nil then return nil; end
	local name:string = Locale.Lookup( bestCity:GetName() );
	if bestDistance == 0 then return "in " .. name; end
	local relative:string = PlotDescription_GetRelative( Map.GetPlot( bestCity:GetX(), bestCity:GetY() ), plot );
	if relative == nil then return nil; end
	return relative .. " of " .. name;
end

-- " Promotion available, Shift+U" for a unit that can be promoted (empty otherwise).
function HubAnnounce.PromotionHint( unit:table )
	local ok:boolean, can, results = pcall( function() return UnitManager.CanStartCommand( unit, UnitCommandTypes.PROMOTE, true, true ); end );
	if ok and can and results ~= nil and results[UnitCommandResults.PROMOTIONS] ~= nil and #results[UnitCommandResults.PROMOTIONS] ~= 0 then return "Promotion available, " .. SRKey( "Shift+U", "D-pad right menu" ); end
	return nil;
end

-- Pure wording of the upgrade hint on selection (M11). info: { target = "Pike and Shot", available = bool, cost = gold or nil,
-- resourceCost = number or nil, resource = "Niter" or nil }. repeated: the unit
-- already heard the full hint this turn. Returns nil when nothing is to be said.
function HubAnnounce.UpgradeText( info:table, repeated:boolean )
	if info == nil or info.target == nil then return nil; end
	if info.available then
		if repeated then return "Upgrade available, " .. SRKey( "U", "D-pad right menu" ); end
		local text:string = "Upgrade to " .. info.target .. " available";
		if info.cost ~= nil and info.cost > 0 then text = text .. ", " .. info.cost .. " gold"; end
		if info.resourceCost ~= nil and info.resourceCost > 0 and info.resource ~= nil then
			text = text .. ", " .. info.resourceCost .. " " .. info.resource;
		end
		return text .. ", " .. SRKey( "U", "D-pad right menu" );
	end
	if repeated then return nil; end
	return "Upgrade to " .. info.target .. " unavailable, " .. SRKey( "U says why", "the D-pad right menu says why" );
end

-- Has the local player the tech and civic the unit type needs? (a blocked upgrade to a unit not yet unlocked is not worth a hint)
local function TargetUnlocked( row:table, ownerID:number )
	local player:table = Players[ ownerID ];
	if row.PrereqTech ~= nil and GameInfo.Technologies[ row.PrereqTech ] ~= nil
			and not player:GetTechs():HasTech( GameInfo.Technologies[ row.PrereqTech ].Index ) then return false; end
	if row.PrereqCivic ~= nil and GameInfo.Civics[ row.PrereqCivic ] ~= nil
			and not player:GetCulture():HasCivic( GameInfo.Civics[ row.PrereqCivic ].Index ) then return false; end
	return true;
end

local m_upgradeHeard:table = {};		-- unit id -> turn of the last full upgrade hint

-- "Upgrade to Pike and Shot available, 75 gold, U" / "Upgrade to Musketman unavailable, U says why" for a selected unit
-- that has an upgrade; nil without one. The first selection of a unit per turn speaks it in full; later ones "Upgrade available, U"
-- (available) or nothing (blocked).
function HubAnnounce.UpgradeHint( unit:table )
	local ok:boolean, text = pcall( function()
		if not UnitManager.CanStartCommand( unit, UnitCommandTypes.UPGRADE, true ) then return nil; end
		local can, results = UnitManager.CanStartCommand( unit, UnitCommandTypes.UPGRADE, false, true );
		local info:table = { available = can == true };
		if results == nil or results[ UnitCommandResults.UNIT_TYPE ] == nil then
			local _, loose = UnitManager.CanStartCommand( unit, UnitCommandTypes.UPGRADE, true, true );
			results = loose;
		end
		local row:table = ( results ~= nil and results[ UnitCommandResults.UNIT_TYPE ] ~= nil ) and GameInfo.Units[ results[ UnitCommandResults.UNIT_TYPE ] ] or nil;
		if row == nil then return nil; end
		info.target = Locale.Lookup( row.Name );
		if info.available then
			info.cost = unit:GetUpgradeCost();
			local resourceType, resourceCost = nil, nil;
			pcall( function() resourceType, resourceCost = unit:GetUpgradeResourceCost(); end );
			if resourceCost ~= nil and resourceCost > 0 and resourceType ~= nil and GameInfo.Resources[ resourceType ] ~= nil then
				info.resourceCost = resourceCost;
				info.resource = Locale.Lookup( GameInfo.Resources[ resourceType ].Name );
			end
		elseif not TargetUnlocked( row, unit:GetOwner() ) then
			return nil;
		end
		local turn:number = Game.GetCurrentGameTurn();
		local repeated:boolean = m_upgradeHeard[ unit:GetID() ] == turn;
		m_upgradeHeard[ unit:GetID() ] = turn;
		return HubAnnounce.UpgradeText( info, repeated );
	end );
	if ok then return text; end
	return nil;
end

-- The settle sentence for a selected settler (after the unit announcement, so it does not interrupt it).
local m_lastSettleSpoken:string = nil;	-- unit, plot, turn and moves of the last settle sentence

local function SpeakSettleSentence( unit:table )
	if not HubCore.IsSettler( unit ) then return; end
	-- Next Action reselecting the same settler where it stood this turn: nothing new to say
	local spokenKey:string = table.concat( { unit:GetID(), unit:GetX(), unit:GetY(), Game.GetCurrentGameTurn(), unit:GetMovesRemaining() }, ":" );
	if spokenKey == m_lastSettleSpoken then return; end
	local ok:boolean, sentence = xpcall( function() return HubCore.SettleSentence( unit ); end, KeyNavErrorHandler );
	if ok then
		m_lastSettleSpoken = spokenKey;
		HubCore.Announce( sentence, true, "settle" );
	else
		print( "InGameAccess settle scan error: " .. tostring( sentence ) );
	end
end

function HubAnnounce.OnUnitSelectionChanged( playerID:number, unitID:number, hexI:number, hexJ:number, hexK:number, isSelected:boolean, isEditable:boolean )
	if playerID ~= Game.GetLocalPlayer() then return; end
	-- (a lens switches the selection off and on: the lenses list stays open for the next toggle)
	if not HubCore.IsModeOpen( "lenses" ) then HubCore.CloseMode( false, true ); end
	if not isSelected then
		HubTargets.ResetStaleMode();
		return;
	end
	HubCore.m_enterWatch = -1;
	local pendingAttack:table = HubCore.m_attackPending;
	if pendingAttack ~= nil and pendingAttack.id ~= unitID then HubCore.ClearAttackPending(); end		-- the player moved on
	local unit:table = Players[playerID]:GetUnits():FindID( unitID );
	if unit == nil then return; end
	-- a move order that is no longer under way is forgotten
	if HubCore.m_movers[ unitID ] ~= nil and UnitManager.GetQueuedDestination( unit ) == nil then HubCore.m_movers[ unitID ] = nil; end
	local plot:table = Map.GetPlot( unit:GetX(), unit:GetY() );
	if plot == nil then return; end
	HubCore.m_lastAnnouncedUnit = unitID;
	-- an armed build belongs to the builder the player left (unless it waits for later: no moves or not selected on arrival)
	local armed:table = HubSettle.m_pending;
	if armed ~= nil and armed.unitId ~= unitID and not armed.keepOnKeys then HubSettle.m_pending = nil; end
	HubCursor.SetCursor( plot:GetX(), plot:GetY(), false );
	local text:string = HubAnnounce.UnitText( unit ) .. ". " .. PlotDescription_GetShort( plot, { excludeUnitId = unit:GetID() } );
	local position:string = HubAnnounce.PositionText( plot );
	if position ~= nil then text = text .. ", " .. position; end
	local promotion:string = HubAnnounce.PromotionHint( unit );
	if promotion ~= nil then text = text .. ". " .. promotion; end
	local upgrade:string = nil;
	if HubCore.m_ready then upgrade = HubAnnounce.UpgradeHint( unit ); end		-- while loading, AnnouncePendingUnit says it
	if upgrade ~= nil then text = text .. ". " .. upgrade; end
	local builderHint:string = HubSettle.BuilderHint( unit );
	if builderHint ~= nil then text = text .. ". " .. builderHint; end
	if HubEnemies ~= nil then
		local okEscort:boolean, escort = pcall( HubEnemies.EscortText, unit );		-- "escorted by Warrior" / "Warrior here too: Shift+E ..."
		if okEscort and escort ~= nil then text = text .. ". " .. escort; end
	end
	if not HubCore.m_ready then
		-- the game is still loading: it would be spoken before "CONTINUE GAME. Press Enter to start."; said once ready, see OnLoadScreenClose
		m_pendingUnit = unitID;
		return;
	end
	HubCore.m_lastSelectionSpeech = UI.GetElapsedTime();
	local sinceCommit:number = UI.GetElapsedTime() - HubCore.m_placeCommitTime;
	HubCore.Announce( text, UI.GetElapsedTime() - HubCore.m_lastResultTime < 1.5 or sinceCommit < 3.0, "selection" );
	SpeakSettleSentence( unit );
end

local function CityProductionText( city:table )
	local queue:table = city:GetBuildQueue();
	if queue == nil then return nil; end
	local hash:number = queue:GetCurrentProductionTypeHash();
	if hash == nil or hash == 0 then return "No production"; end
	local row:table = GameInfo.Buildings[hash] or GameInfo.Districts[hash] or GameInfo.Units[hash] or GameInfo.Projects[hash];
	if row == nil then return nil; end
	local text:string = Locale.Lookup( row.Name );
	local turns:number = queue:GetTurnsLeft();
	if turns ~= nil and turns > 0 then
		text = text .. ", " .. turns .. ( turns == 1 and " turn" or " turns" );
	end
	return text;
end

local function CityGrowthText( city:table )
	local growth:table = city:GetGrowth();
	if growth == nil then return nil; end
	local turns:number = growth:GetTurnsUntilGrowth();
	if turns ~= nil and turns > 0 and turns ~= -1 then
		return "grows in " .. turns .. ( turns == 1 and " turn" or " turns" );
	end
	local starve:number = growth:GetTurnsUntilStarvation();
	if starve ~= nil and starve > 0 and starve ~= -1 then
		return "starving in " .. starve .. ( starve == 1 and " turn" or " turns" );
	end
	return "not growing";
end

-- "full loyalty" / "loyalty 72 of 100, minus 3 per turn" (Rise and Fall and later; nil without cultural identity). Pure part:
function HubAnnounce.LoyaltyText( current:number, max:number, perTurn:number )
	local function Num( value:number )
		value = math.floor( value * 10 + 0.5 ) / 10;
		if value == math.floor( value ) then return tostring( math.floor( value ) ); end
		return tostring( value );
	end
	perTurn = math.floor( perTurn * 10 + 0.5 ) / 10;
	if current >= max and perTurn >= 0 then return "full loyalty"; end
	local text:string = "loyalty " .. Num( current ) .. " of " .. Num( max );
	if perTurn > 0 then text = text .. ", plus " .. Num( perTurn ) .. " per turn";
	elseif perTurn < 0 then text = text .. ", minus " .. Num( -perTurn ) .. " per turn"; end
	return text;
end

local function CityLoyaltyText( city:table )
	if city.GetCulturalIdentity == nil then return nil; end
	local ok:boolean, text = pcall( function()
		local identity:table = city:GetCulturalIdentity();
		if identity == nil then return nil; end
		return HubAnnounce.LoyaltyText( identity:GetLoyalty(), identity:GetMaxLoyalty(), identity:GetLoyaltyPerTurn() );
	end );
	if not ok then print( "InGameAccess loyalty error: " .. tostring( text ) ); return nil; end
	return text;
end

function HubAnnounce.OnCitySelectionChanged( owner:number, cityID:number, i:number, j:number, k:number, isSelected:boolean, isEditable:boolean )
	if owner ~= Game.GetLocalPlayer() then return; end
	-- (a lens switches the selection off and on: the lenses list stays open for the next toggle)
	if not HubCore.IsModeOpen( "lenses" ) then HubCore.CloseMode( false, true ); end
	if not isSelected then return; end
	HubCore.m_enterWatch = -1;
	local city:table = Players[owner]:GetCities():FindID( cityID );
	if city == nil then return; end
	local plot:table = Map.GetPlot( city:GetX(), city:GetY() );
	if plot ~= nil then HubCursor.SetCursor( plot:GetX(), plot:GetY(), false ); end
	local parts:table = { Locale.Lookup( city:GetName() ), Locale.Lookup( "LOC_HUD_CITY_POPULATION" ) .. " " .. city:GetPopulation() };
	local production:string = CityProductionText( city );
	if production ~= nil then table.insert( parts, production ); end
	local growth:string = CityGrowthText( city );
	if growth ~= nil then table.insert( parts, growth ); end
	local loyalty:string = CityLoyaltyText( city );
	if loyalty ~= nil then table.insert( parts, loyalty ); end
	HubCore.m_lastSelectionSpeech = UI.GetElapsedTime();
	local text:string = table.concat( parts, ", " );
	local cx:number, cy:number = HubCursor.GetCursor();		-- (SetCursor above ran first) pad Y opens the report only with the cursor on the city
	if Hub ~= nil and Hub.m_cityReportLoaded and HubTargets.GetTargetMode() == nil and cx == city:GetX() and cy == city:GetY() then text = text .. SRPadHint( ", Y for its report" ); end		-- pad only: Y on an own city opens the report (HubGamepad.OnPadDetails)
	HubCore.Announce( text, false, "selection" );
end

-- "Turn 5, 3600 BC". Said once per turn: a new turn and a finished load both announce it, and a loaded game
-- gets no turn-begin event at all.
local m_endedTurn:number = -1;			-- game turn for which a turn end was seen and is not yet confirmed or refuted (see TurnNotEnded)

function HubAnnounce.AnnounceTurn()
	if HubCore.IsLocalPlayerActive() then HubCore.MarkTurnBegin(); end
	if not HubCore.IsLocalPlayerActive() then return; end
	local turn:number = Game.GetCurrentGameTurn();
	local key:string = Game.GetLocalPlayer() .. ":" .. turn;
	if key == HubCore.m_lastAnnouncedTurn then return; end
	HubCore.m_lastAnnouncedTurn = key;
	if HubCore.m_cursorPlayer ~= Game.GetLocalPlayer() then HubCursor.ResetCursor(); end
	HubCore.Announce( "Turn " .. turn .. ", " .. Calendar.MakeYearStr( turn ), true, "turn" );
	if HubEnemies ~= nil then
		local ok:boolean, err = pcall( HubEnemies.SpeakAtTurnStart );
		if not ok then print( "HubEnemies error: " .. tostring( err ) ); end
	end		-- what the enemies near us did
end

-- The selection that happened while the game was loading, said again now that it is ready.
local function AnnouncePendingUnit()
	local unitID:number = m_pendingUnit;
	m_pendingUnit = nil;
	if unitID == nil or not HubCore.IsLocalPlayerActive() then return; end
	local unit:table = UI.GetHeadSelectedUnit();
	if unit == nil or unit:GetID() ~= unitID or unit:GetOwner() ~= Game.GetLocalPlayer() then return; end
	local plot:table = Map.GetPlot( unit:GetX(), unit:GetY() );
	if plot == nil then return; end
	local pendingText:string = HubAnnounce.UnitText( unit ) .. ". " .. PlotDescription_GetShort( plot, { excludeUnitId = unit:GetID() } );
	local upgrade:string = HubAnnounce.UpgradeHint( unit );
	if upgrade ~= nil then pendingText = pendingText .. ". " .. upgrade; end
	HubCore.Announce( pendingText, true, "selection" );
	SpeakSettleSentence( unit );
end

-- A game was loaded or started: forget everything about the previous one.
function HubAnnounce.OnLoadScreenClose()
	m_endedTurn = -1;
	HubCore.ClearSpeechHold();
	HubAnnounce.ResetReadyWatch();
	HubCore.m_lastAnnouncedTurn = "";
	HubCore.m_turnLineSpoken = nil;
	if HubEnemies ~= nil then HubEnemies.Reset(); end
	m_lastSettleSpoken = nil;
	HubCursor.ResetCursor();
	HubCore.m_ready = true;
	-- Accept the camps in the fog right now, not at the first J/X: one that spawns later must be reported as new.
	if HubPlaces ~= nil then pcall( HubPlaces.Prime ); end
	HubCore.m_movers = {};
	HubCore.m_spotted = {};
	HubCore.m_arrivals = {};
	HubCore.m_arrivalTimer = -1;
	HubCore.CloseMode( false, true );
	-- The unit that was selected while the game loaded (the turn 1 settler!) was announced into the load screen and
	-- without the settle sentence: say it again once the turn announcement is out.
	if m_pendingUnit ~= nil then HubCore.After( 1.0, function() AnnouncePendingUnit(); end ); end
	-- A save made between turns loads before the player's turn has begun (LocalPlayerTurnBegin follows and announces
	-- the right turn); announce here only when the turn is already running, with a late fallback.
	local player:table = Players[ Game.GetLocalPlayer() ];
	if player ~= nil and player:IsTurnActive() then
		HubAnnounce.AnnounceTurn();
	else
		HubCore.After( 3, HubAnnounce.AnnounceTurn );
	end
end

-- The engine can hand the turn back after LocalPlayerTurnEnd: a unit that finished a queued move or auto-explore during
-- the end-of-turn processing asks for orders (or a screen still needs the player). IsTurnActive is true again within
-- 0.1 s, but PlayerTurnActivated(local, false) and LocalPlayerTurnBegin only follow ~3 s later and the action panel
-- says "Please wait" until then. So after "Turn ended" (or a turn end that did not happen) we watch for it.
local m_notEndedWatch:number = 0;		-- id of the running label wait (a new turn end cancels an older one)

-- Sentence case of the action panel's blocker text ("UNIT NEEDS ORDERS" -> "Unit needs orders"), "" while it only waits.
-- Pure: "" when the label is empty or one of the ignored lower-cased non-blocker texts.
function HubAnnounce.BlockerFromLabel( text:string, ignored:table )
	if text == nil or text == "" then return ""; end
	local lower:string = string.lower( text );
	for _, other in ipairs( ignored ) do
		if lower == other then return ""; end
	end
	return string.upper( string.sub( text, 1, 1 ) ) .. string.lower( string.sub( text, 2 ) );
end

local function BlockerText()
	local label:table = ContextPtr:LookUpControl( "/InGame/HUD/ActionPanel/EndTurnText" );
	if label == nil then return ""; end
	-- not blockers: "Please wait", "Next turn" (the blocker resolved), "Waiting for other players"
	local ignored:table = {};
	for _, key in ipairs( { "LOC_ACTION_PANEL_PLEASE_WAIT", "LOC_ACTION_PANEL_NEXT_TURN", "LOC_ACTION_PANEL_WAITING_FOR_PLAYERS" } ) do
		table.insert( ignored, string.lower( CleanTextForSpeech( Locale.Lookup( key ) ) ) );
	end
	return HubAnnounce.BlockerFromLabel( CleanTextForSpeech( label:GetText() or "" ), ignored );
end

-- The local turn is active again in the same game turn: say what blocks it, once the panel has the text (max 6 s).
local function TurnNotEnded( turn:number )
	m_endedTurn = -1;
	m_notEndedWatch = m_notEndedWatch + 1;
	local id:number = m_notEndedWatch;
	local waited:number = 0;
	local function Check()
		if id ~= m_notEndedWatch or Game.GetCurrentGameTurn() ~= turn then return; end
		local player:table = Players[ Game.GetLocalPlayer() ];
		if player == nil or not player:IsTurnActive() then return; end
		local text:string = BlockerText();
		-- (the panel says "Please wait" for the whole session: the congress screen is what needs the player)
		local okCongress:boolean, inSession:boolean = pcall( function() return Game.GetWorldCongress():IsInSession(); end );
		if text == "" and okCongress and inSession then
			OutputMessageToScreenReader( "Turn not ended: World Congress is waiting for your votes. " .. SRKey( "Enter" ) .. " or " .. SRKey( "Control+N", "RB" ) .. " resumes it", true );
			return;
		end
		if text == "" and waited < 6 then
			waited = waited + 0.25;
			HubCore.After( 0.25, Check );
			return;
		end
		-- no real blocker text: the turn probably did end (slow IsTurnActive); say nothing rather than a bare "Turn not ended"
		if text == "" then return; end
		OutputMessageToScreenReader( "Turn not ended: " .. text, true );
	end
	Check();
end

-- The turn-start line (selected unit, else what blocks the turn) said again: the World Congress results popup is spoken
-- first at a turn start and the engine's own unit selection (spoken before it) was queued behind, or never happened.
function HubAnnounce.RepeatTurnStartLine()
	local player:table = Players[ Game.GetLocalPlayer() or -1 ];
	if player == nil or not player:IsTurnActive() then return; end
	local unit:table = UI.GetHeadSelectedUnit();
	if unit ~= nil then
		HubAnnounce.OnUnitSelectionChanged( player:GetID(), unit:GetID(), unit:GetX(), unit:GetY(), 0, true, true );
		return;
	end
	if UI.GetHeadSelectedCity() ~= nil then return; end
	local text:string = BlockerText();
	if text ~= "" then HubCore.Announce( text .. ". " .. SRKey( "Enter" ) .. " handles it", true, "turn" ); end
end

function HubAnnounce.OnPlayerTurnActivated( playerID:number, isFirstTime:boolean )
	if playerID == Game.GetLocalPlayer() then HubCore.MarkTurnBegin(); end
	if playerID ~= Game.GetLocalPlayer() or isFirstTime or m_endedTurn ~= Game.GetCurrentGameTurn() then return; end
	TurnNotEnded( m_endedTurn );
end

function HubAnnounce.OnLocalPlayerTurnEnd()
	if HubEnemies ~= nil then
		local ok:boolean, err = pcall( HubEnemies.TakeSnapshot );
		if not ok then print( "HubEnemies error: " .. tostring( err ) ); end
	end		-- the enemies we see now, compared at the next turn start
	HubCore.ReleaseSpeechAtTurnEnd();
	HubAnnounce.ResetReadyWatch();
	HubCore.CloseMode( false, true );
	HubCore.m_enterWatch = -1;
	if HubTargets.GetTargetMode() ~= nil then UI.SetInterfaceMode( InterfaceModeTypes.SELECTION ); end
	-- Already inactive at event time: the turn (probably) ended, say it now (a deferred line could land after the next
	-- "Turn N"), and watch for the engine handing the turn back. Still active: check again shortly and speak only if
	-- the same turn is now over; a new turn has announced itself.
	local turn:number = Game.GetCurrentGameTurn();
	m_notEndedWatch = m_notEndedWatch + 1;
	m_endedTurn = turn;
	local player:table = Players[ Game.GetLocalPlayer() ];
	if player == nil or not player:IsTurnActive() then
		-- the turn is back active within 0.1 s when it was refused (a unit that finished its move during the end-of-turn
		-- processing): do not wait for the (late) engine event, and do not say "Turn ended" first. If the game is already
		-- in a new turn the new turn's own line covers it: "Turn ended" would land after "Turn N".
		HubCore.After( 0.3, function()
			if Game.GetCurrentGameTurn() ~= turn then return; end
			local current:table = Players[ Game.GetLocalPlayer() ];
			if m_endedTurn == turn and current ~= nil and current:IsTurnActive() then
				TurnNotEnded( turn );
			elseif m_endedTurn == turn then
				OutputMessageToScreenReader( "Turn ended", true );
			end
		end );
		return;
	end
	HubCore.After( 0.7, function()
		local current:table = Players[ Game.GetLocalPlayer() ];
		if Game.GetCurrentGameTurn() ~= turn then return; end
		if current == nil or not current:IsTurnActive() then
			OutputMessageToScreenReader( "Turn ended", true );
		elseif m_endedTurn == turn then
			TurnNotEnded( turn );
		end
	end );
end

-- ===========================================================================
--	READY WATCH: "All done. Enter ends the turn" once nothing blocks the turn any more. Polls the action panel's label
--	(the game's own blocker text) every 0.25 s during the local player's turn; "Next turn" held for 0.5 s counts as ready
--	("Unit has moves remaining" and every other blocker do not). Said once per ready phase (it re-arms when a blocker
--	shows again or the turn is over), through HubCore.Announce so that a popup is not talked over, and not while a hub
--	mode, a target mode or a game popup/screen is open: it is said when they close if the turn is still ready.
-- ===========================================================================
local READY_POLL:number = 0.25;
local READY_STABLE:number = 0.5;
local m_ready:table = { poll = 0, stable = 0, armed = true };

function HubAnnounce.ResetReadyWatch()
	m_ready.poll, m_ready.stable, m_ready.armed = 0, 0, true;
end

-- Is the action panel saying "Next turn"? (no blockers; nothing while it waits for other players)
local function IsNextTurnLabel()
	local label:table = ContextPtr:LookUpControl( "/InGame/HUD/ActionPanel/EndTurnText" );
	if label == nil then return false; end
	local text:string = label:GetText();
	if text == nil or text == "" then return false; end
	return string.lower( CleanTextForSpeech( text ) ) == string.lower( CleanTextForSpeech( Locale.Lookup( "LOC_ACTION_PANEL_NEXT_TURN" ) ) );
end

-- After a hot reload of the hub: a turn that is already ready was announced before, do not repeat it.
function HubAnnounce.StartReadyWatchDisarmed()
	if HubAnnounce.IsReadyNow() then m_ready.armed = false; end
end

-- Is the turn ready right now (also used when a queued "All done" is released)?
function HubAnnounce.IsReadyNow()
	local player:table = Players[ Game.GetLocalPlayer() or -1 ];
	return HubCore.m_ready and player ~= nil and player:IsTurnActive() and IsNextTurnLabel();
end

function HubAnnounce.UpdateReadyWatch( deltaTime:number )
	m_ready.poll = m_ready.poll - deltaTime;
	if m_ready.poll > 0 then return; end
	local elapsed:number = READY_POLL - m_ready.poll;		-- time since the last poll (at least READY_POLL)
	m_ready.poll = READY_POLL;
	local isReady:boolean = HubAnnounce.IsReadyNow();
	if not isReady then
		m_ready.stable = 0;
		m_ready.armed = true;
		return;
	end
	m_ready.stable = m_ready.stable + elapsed;
	if not m_ready.armed or m_ready.stable < READY_STABLE then return; end
	if HubCore.m_mode ~= nil or HubTargets.GetTargetMode() ~= nil or HubCore.IsGamePopupOpen() then return; end
	m_ready.armed = false;
	HubCore.Announce( "All done. " .. SRKey( "Enter" ) .. " ends the turn", true, "ready" );
end
