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
function HubAnnounce.SpeakWhatsNext()
	if not HubCore.IsLocalPlayerActive() then return; end
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
			OutputMessageToScreenReader( "World Congress in session. Enter or Control+N resumes it" );
			return;
		end
	end
	OutputMessageToScreenReader( HubCore.Capitalize( text ) );
end

-- ===========================================================================
--	ANNOUNCEMENTS
-- ===========================================================================

function HubAnnounce.UnitText( unit:table )
	local parts:table = { Locale.Lookup( unit:GetName() ) };
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
	-- what it is doing (exploring, fortified, moving to ...); a unit picked from the places list also hears how to cancel
	if HubPlaces ~= nil then
		local activity:string = HubPlaces.UnitActivity( unit, false );
		if activity ~= nil then
			table.insert( parts, activity );
			if HubPlaces.TakeCancelHint( unit ) then table.insert( parts, "Tab menu to cancel its orders" ); end
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
	if ok and can and results ~= nil and results[UnitCommandResults.PROMOTIONS] ~= nil and #results[UnitCommandResults.PROMOTIONS] ~= 0 then return "Promotion available, Shift+U"; end
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
		OutputMessageToScreenReader( sentence, true );
	else
		print( "InGameAccess settle scan error: " .. tostring( sentence ) );
	end
end

function HubAnnounce.OnUnitSelectionChanged( playerID:number, unitID:number, hexI:number, hexJ:number, hexK:number, isSelected:boolean, isEditable:boolean )
	if playerID ~= Game.GetLocalPlayer() then return; end
	HubCore.CloseMode( false, true );
	if not isSelected then
		HubTargets.ResetStaleMode();
		return;
	end
	HubCore.m_enterWatch = -1;
	local unit:table = Players[playerID]:GetUnits():FindID( unitID );
	if unit == nil then return; end
	-- a move order that is no longer under way is forgotten
	if HubCore.m_movers[ unitID ] ~= nil and UnitManager.GetQueuedDestination( unit ) == nil then HubCore.m_movers[ unitID ] = nil; end
	local plot:table = Map.GetPlot( unit:GetX(), unit:GetY() );
	if plot == nil then return; end
	HubCursor.SetCursor( plot:GetX(), plot:GetY(), false );
	local text:string = HubAnnounce.UnitText( unit ) .. ". " .. PlotDescription_GetShort( plot, { excludeUnitId = unit:GetID() } );
	local position:string = HubAnnounce.PositionText( plot );
	if position ~= nil then text = text .. ", " .. position; end
	local promotion:string = HubAnnounce.PromotionHint( unit );
	if promotion ~= nil then text = text .. ". " .. promotion; end
	if not HubCore.m_ready then
		-- the game is still loading: it would be spoken before "CONTINUE GAME. Press Enter to start."; said once ready, see OnLoadScreenClose
		m_pendingUnit = unitID;
		return;
	end
	HubCore.m_lastSelectionSpeech = UI.GetElapsedTime();
	local sinceCommit:number = UI.GetElapsedTime() - HubCore.m_placeCommitTime;
	OutputMessageToScreenReader( text, UI.GetElapsedTime() - HubCore.m_lastResultTime < 1.5 or sinceCommit < 3.0 );
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

function HubAnnounce.OnCitySelectionChanged( owner:number, cityID:number, i:number, j:number, k:number, isSelected:boolean, isEditable:boolean )
	if owner ~= Game.GetLocalPlayer() then return; end
	HubCore.CloseMode( false, true );
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
	HubCore.m_lastSelectionSpeech = UI.GetElapsedTime();
	OutputMessageToScreenReader( table.concat( parts, ", " ) );
end

-- "Turn 5, 3600 BC". Said once per turn: a new turn and a finished load both announce it, and a loaded game
-- gets no turn-begin event at all.
function HubAnnounce.AnnounceTurn()
	if not HubCore.IsLocalPlayerActive() then return; end
	local turn:number = Game.GetCurrentGameTurn();
	local key:string = Game.GetLocalPlayer() .. ":" .. turn;
	if key == HubCore.m_lastAnnouncedTurn then return; end
	HubCore.m_lastAnnouncedTurn = key;
	if HubCore.m_cursorPlayer ~= Game.GetLocalPlayer() then HubCursor.ResetCursor(); end
	OutputMessageToScreenReader( "Turn " .. turn .. ", " .. Calendar.MakeYearStr( turn ), true );
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
	OutputMessageToScreenReader( HubAnnounce.UnitText( unit ) .. ". " .. PlotDescription_GetShort( plot, { excludeUnitId = unit:GetID() } ), true );
	SpeakSettleSentence( unit );
end

-- A game was loaded or started: forget everything about the previous one.
function HubAnnounce.OnLoadScreenClose()
	HubCore.m_lastAnnouncedTurn = "";
	m_lastSettleSpoken = nil;
	HubCursor.ResetCursor();
	HubCore.m_ready = true;
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

function HubAnnounce.OnLocalPlayerTurnEnd()
	HubCore.CloseMode( false, true );
	HubCore.m_enterWatch = -1;
	if HubTargets.GetTargetMode() ~= nil then UI.SetInterfaceMode( InterfaceModeTypes.SELECTION ); end
	-- The event also fires when ending the turn is refused a moment later (a unit that finished exploring asks for
	-- orders, turn number unchanged). Already inactive at event time: the turn really ended, say it now (a deferred
	-- line could land after the next "Turn N"). Still active: check again shortly and speak only if the same turn
	-- is now over; a new turn has announced itself.
	local turn:number = Game.GetCurrentGameTurn();
	local player:table = Players[ Game.GetLocalPlayer() ];
	if player == nil or not player:IsTurnActive() then
		OutputMessageToScreenReader( "Turn ended", true );
		return;
	end
	HubCore.After( 0.7, function()
		local current:table = Players[ Game.GetLocalPlayer() ];
		if Game.GetCurrentGameTurn() == turn and ( current == nil or not current:IsTurnActive() ) then
			OutputMessageToScreenReader( "Turn ended", true );
		end
	end );
end
