-- ===========================================================================
--	InGameAccess: screen reader hub for the in-game UI (see docs/ingame-plan.md).
--	A context without visuals, added to InGame (UI/Additions/InGameAccess.xml). It owns
--	  - the map cursor (Shift+Arrows) and its plot announcements,
--	  - the in-game hotkeys (I plot details, J cursor to selection, N what is next, Tab unit actions),
--	  - the unit actions menu and the target modes (move to, attack ...), which take over Up/Down/Enter/Escape and
--	    Shift+Arrows through this context's input handler (see the bottom of the file),
--	  - the regions: top panel (Control+Y), notifications (Control+N) and the city report (Control+I), with arrivals announced,
--	  - event announcements: unit/city selected, new turn, end of turn, unit results, enemies spotted.
--	Input order (verified, see docs/ingame-plan.md): this context's input handler runs before WorldInput and
--	ActionPanel; a key it consumes (KeyDown and KeyUp) also never becomes an input action.
-- ===========================================================================

Hub = {};		-- shared state and functions of the hub (the modules below add their own tables)

include( "ScreenReader" );
include( "KeyboardNavigation" );
include( "PlotDescription" );
include( "KeyNavList" );
include( "Civ6Common" );		-- MoveUnitToPlot (war declaration check + the right move/attack operation)
include( "SettleScan" );		-- settler: can settle here, best spots
include( "PlacementScan" );		-- city: where a district or wonder can go
include( "TopPanelData" );		-- top panel values as sentences (Control+Y, Control+G)
-- City report (Control+I): CityReportGather includes the game's CitySupport (GetCityData), which is heavy and may fail in
-- a ruleset: a failure here only loses the report, never the rest of the hub.
local m_cityReportLoaded:boolean = pcall( function()
	include( "CityReportData" );
	include( "CityReportGather" );
end );
if not m_cityReportLoaded then print( "InGameAccess: the city report files did not load" ); end

-- ===========================================================================
--	MEMBERS
-- ===========================================================================

local m_actions				:table = {};		-- actionId -> handler
local m_lastAnnouncedTurn	:string = "";		-- "<local player>:<turn>" of the last turn announcement (hotseat: every player hears their turn)
local m_ready				:boolean = false;	-- a game is loaded (LoadScreenClose seen): event announcements are allowed
local m_unitActions			:table = {};		-- plain list of the selected unit's actions, sent by UnitPanel (SRA_UnitActions)
local m_enterLabel			:string = "";		-- what the action panel said Enter would do
local m_placeCommitTime		:number = -100;		-- UI.GetElapsedTime() of the last placement commit (its result must outlive the selection that follows)
local m_menuItems			:table = {};		-- items of the unit actions menu, fetched when it opens
local m_spotted				:table = {};		-- "player:unit" -> turn the enemy was last announced
local m_spottedTurn			:number = -1;		-- turn m_spottedCount counts
local m_spottedCount		:number = 0;
local m_settleItems			:table = {};		-- its items, from the scan made when it opened
local m_notifData			:table = {};		-- notifications sent by NotificationPanel (SRA_Notifications), plain data
local m_notifAnswered		:boolean = false;	-- NotificationPanel answered the last SRA_RequestNotifications
local m_arrivals			:table = {};		-- texts of notifications that arrived and are not yet announced
local m_arrivalTimer		:number = -1;		-- >= 0: seconds until the arrivals are announced together
local m_lastSelectionSpeech	:number = -100;		-- UI.GetElapsedTime() of the last unit/city selection announcement
local m_pendingUnit			:number = nil;		-- unit selected while the game was still loading: announced once it is ready
local m_placeScan			:table = nil;		-- PlacementScan result of the open placement mode (district / wonder browser)
local m_placeParams			:table = nil;		-- insert-mode parameters read from the interface mode when placement began
local m_placeBusy			:boolean = false;	-- a tile purchase is waiting for its rescan: Enter says "Wait"

-- ===========================================================================
--	WHAT IS NEXT (N)
-- ===========================================================================

-- What the Next Action key (Enter) will do, as the game's action panel says it ("Unit needs orders", "Choose
-- production", "Next turn", ...). Read from the panel's own label so that expansion blockers are covered too.
local function SpeakWhatsNext()
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

local function UnitText( unit:table )
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
	return table.concat( parts, ", " );
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

local function OnUnitSelectionChanged( playerID:number, unitID:number, hexI:number, hexJ:number, hexK:number, isSelected:boolean, isEditable:boolean )
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
	local text:string = UnitText( unit ) .. ". " .. PlotDescription_GetShort( plot, { excludeUnitId = unit:GetID() } );
	if not m_ready then
		-- the game is still loading: it would be spoken before "CONTINUE GAME. Press Enter to start."; said once ready, see OnLoadScreenClose
		m_pendingUnit = unitID;
		return;
	end
	m_lastSelectionSpeech = UI.GetElapsedTime();
	local sinceCommit:number = UI.GetElapsedTime() - m_placeCommitTime;
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

local function OnCitySelectionChanged( owner:number, cityID:number, i:number, j:number, k:number, isSelected:boolean, isEditable:boolean )
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
	m_lastSelectionSpeech = UI.GetElapsedTime();
	OutputMessageToScreenReader( table.concat( parts, ", " ) );
end

-- "Turn 5, 3600 BC". Said once per turn: a new turn and a finished load both announce it, and a loaded game
-- gets no turn-begin event at all.
local function AnnounceTurn()
	if not HubCore.IsLocalPlayerActive() then return; end
	local turn:number = Game.GetCurrentGameTurn();
	local key:string = Game.GetLocalPlayer() .. ":" .. turn;
	if key == m_lastAnnouncedTurn then return; end
	m_lastAnnouncedTurn = key;
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
	OutputMessageToScreenReader( UnitText( unit ) .. ". " .. PlotDescription_GetShort( plot, { excludeUnitId = unit:GetID() } ), true );
	SpeakSettleSentence( unit );
end

-- A game was loaded or started: forget everything about the previous one.
local function OnLoadScreenClose()
	m_lastAnnouncedTurn = "";
	m_lastSettleSpoken = nil;
	HubCursor.ResetCursor();
	m_ready = true;
	HubCore.m_movers = {};
	m_spotted = {};
	m_arrivals = {};
	m_arrivalTimer = -1;
	HubCore.CloseMode( false, true );
	-- The unit that was selected while the game loaded (the turn 1 settler!) was announced into the load screen and
	-- without the settle sentence: say it again once the turn announcement is out.
	if m_pendingUnit ~= nil then HubCore.After( 1.0, function() AnnouncePendingUnit(); end ); end
	-- A save made between turns loads before the player's turn has begun (LocalPlayerTurnBegin follows and announces
	-- the right turn); announce here only when the turn is already running, with a late fallback.
	local player:table = Players[ Game.GetLocalPlayer() ];
	if player ~= nil and player:IsTurnActive() then
		AnnounceTurn();
	else
		HubCore.After( 3, AnnounceTurn );
	end
end

local function OnLocalPlayerTurnEnd()
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

-- ===========================================================================
--	SETTLE SPOT BROWSER (X with a settler selected): candidates from SettleScan, best first
-- ===========================================================================
local m_settleList:table;

-- Browsing moved the cursor over the candidates: back to the settler (not when the mode went stale).
local function SettleClosed( quiet:boolean )
	if quiet then return; end
	local unit:table = UI.GetHeadSelectedUnit();
	if unit ~= nil then HubCursor.SetCursor( unit:GetX(), unit:GetY(), false ); end
end

local function BuildSettleItems()
	return m_settleItems;
end

-- "2 tiles north-east, 1 turn, river, coast, silk, recommended" / "Here, river, wine"
local function SettleItemText( c:table )
	local text:string = c.here and "Here" or ( c.relative .. ", " .. HubCore.Plural( c.turns, "turn", "turns" ) );
	text = text .. HubCore.SettleReasons( c, 3, 2 );
	if c.recommended then text = text .. ", recommended"; end
	return text;
end

local function OpenSettleBrowser( unit:table )
	local scan:table = SettleScan_Scan( unit, true );		-- the player asked: look again, the map may have changed
	m_settleItems = {};
	for _, c in ipairs( scan.list ) do
		table.insert( m_settleItems, { key = c.key, text = SettleItemText( c ), detail = c.detail, candidate = c } );
	end
	if #m_settleItems == 0 then
		OutputMessageToScreenReader( "No spot to settle found nearby" .. ( ( scan.hereReason ~= nil and scan.hereReason ~= "" ) and ( ", here: " .. scan.hereReason ) or "" ) );
		return;
	end
	HubCore.OpenMode( "settle", m_settleList, "Settle spots", SettleClosed );
end

-- Enter on a spot: the settler walks there (the same path as the move-to mode), or on the spot it stands on: B founds.
local function SettleGo( item:table )
	local unit:table = UI.GetHeadSelectedUnit();
	HubCore.CloseMode( false, false );
	if not HubCore.IsSettler( unit ) then
		HubCore.SayResult( "No settler selected" );
		return;
	end
	local c:table = item.candidate;
	local plot:table = Map.GetPlotByIndex( c.plotIndex );
	local ok:boolean, extra = SettleScan_CanFound( unit, plot );
	if c.here or ( unit:GetX() == c.x and unit:GetY() == c.y ) then
		if not ok then
			HubCore.SayResult( "Cannot settle here" .. ( ( extra ~= nil and extra ~= "" ) and ( ": " .. extra ) or "" ) );
		elseif extra == true then
			HubCore.SayResult( "B to found next turn" );
		else
			HubCore.SayResult( "B to found the city here" );
		end
		return;
	end
	if not ok then
		HubCore.SayResult( "Cannot settle there any more" .. ( ( extra ~= nil and extra ~= "" ) and ( ": " .. extra ) or "" ) );
		return;
	end
	local war:table = HubTargets.WarTargets( unit, plot );
	local path:table = UnitManager.GetMoveToPathEx( unit, plot:GetIndex() );
	if war == nil and ( path == nil or path.plots == nil or #path.plots < 2 ) then
		HubCore.SayResult( "Unreachable" );
		return;
	end
	HubTargets.IssueMoveOrder( unit, plot, war, false );
end

m_settleList = KeyNavList_Create{
	build		= BuildSettleItems,
	isActive	= function() return HubCore.IsModeOpen( "settle" ); end,
	onActivate	= SettleGo,
	onClose		= function() HubCore.CloseMode( true, false ); end,
	onFocus		= function( item ) HubCursor.SetCursor( item.candidate.x, item.candidate.y, false, nil, true ); end,
};

-- X: with a settler selected the spot browser, otherwise the scan for foreign units.
local function ScanKey()
	if not HubCore.IsLocalPlayerActive() then return; end
	if HubCore.IsModeOpen( "settle" ) then HubCore.CloseMode( true, false ); return; end
	local unit:table = UI.GetHeadSelectedUnit();
	if HubCore.IsSettler( unit ) and HubTargets.GetTargetMode() == nil then
		OpenSettleBrowser( unit );
		return;
	end
	HubCursor.ScanUnits( true );
end

-- ===========================================================================
--	PLACEMENT BROWSER: district and wonder placement by keyboard. The game enters DISTRICT_PLACEMENT / BUILDING_PLACEMENT
--	(ProductionPanel, Purchase tab); the candidate tiles come from PlacementScan. Up/Down browse (the cursor follows without
--	the real mouse), Shift+Arrows move the cursor freely ("valid, plus 2 Science" / "purchasable, 60 gold" / "can't place
--	here"), Enter (twice) places on the cursor tile, Space explains, Escape goes back / cancels.
--	Committing mirrors StrategicView_MapPlacement.ConfirmPlaceDistrict / ConfirmPlaceWonder (without their popup); the
--	game buys a tile in its own, separate step (PlotInfo.OnClickPurchasePlot), which Enter on a purchasable tile does too.
-- ===========================================================================
local m_placeList:table;

local function IsPlacementMode( mode:number )
	return mode == InterfaceModeTypes.DISTRICT_PLACEMENT or mode == InterfaceModeTypes.BUILDING_PLACEMENT;
end

-- "plus 3 Science, removes Woods and Deer, buy tile 60 gold" (the parts that apply, comma separated; empty when none).
local function PlacementEffects( c:table, withBuy:boolean )
	local parts:table = {};
	for _, text in ipairs( c.adjacency ) do table.insert( parts, text ); end
	if #c.removes > 0 then table.insert( parts, "removes " .. table.concat( c.removes, " and " ) ); end
	for _, text in ipairs( c.notes ) do table.insert( parts, text ); end
	if withBuy and not c.owned then table.insert( parts, "buy tile " .. c.tileCost .. " gold" ); end
	return table.concat( parts, ", " );
end

-- "2 tiles north-east, plus 3 Science, removes Woods, buy tile 60 gold"
local function PlacementItemText( c:table )
	local effects:string = PlacementEffects( c, true );
	if effects == "" then return c.relative; end
	return c.relative .. ", " .. effects;
end

-- What the cursor plot means for the item being placed (nil when no placement is going on).
HubCore.PlacementPlotText = function( plot:table )
	local scan:table = m_placeScan;
	if scan == nil or not HubCore.IsModeOpen( "placement" ) then return nil; end
	local c:table = scan.byIndex[ plot:GetIndex() ];
	if c == nil then
		local why:string = PlacementScan_Cannot( scan, plot );
		return "can't place here" .. ( why ~= "" and ( ": " .. why ) or "" );
	end
	local text:string;
	if c.owned then
		text = "valid";
	else
		text = "purchasable, " .. c.tileCost .. " gold";
	end
	local effects:string = PlacementEffects( c, false );
	if effects ~= "" then text = text .. ", " .. effects; end
	return text;
end

local function PlacementDetail( c:table )
	local text:string = m_placeScan.name .. " at " .. c.relative;
	if c.explanation ~= "" then
		text = text .. ". " .. c.explanation;
	elseif m_placeScan.kind == "district" then
		text = text .. ". No adjacency bonus";
	end
	if #c.removes > 0 then text = text .. ". Removes " .. table.concat( c.removes, " and " ); end
	for _, note in ipairs( c.notes ) do text = text .. ". " .. note; end
	if not c.owned then text = text .. ". You do not own this tile yet, buying it costs " .. c.tileCost .. " gold"; end
	local plot:table = Map.GetPlotByIndex( c.plotIndex );
	if plot ~= nil then text = text .. ". " .. PlotDescription_GetShort( plot, {} ); end
	return text;
end

local function BuildPlacementItems()
	local items:table = {};
	if m_placeScan == nil then return items; end
	for _, c in ipairs( m_placeScan.list ) do
		table.insert( items, { key = c.key, text = PlacementItemText( c ), candidate = c, detail = function() return PlacementDetail( c ); end } );
	end
	return items;
end

-- Puts the mode away: the cursor goes back to the city. A mode that went stale while the game is still placing leaves
-- the placement mode, or Enter and Escape would have nothing to act on.
local function PlacementClosed( quiet:boolean )
	m_placeScan = nil;
	HubCore.m_placeConfirm = nil;
	m_placeBusy = false;
	-- not when the close is the mode being replaced by another placement mode: that one must stay
	if not HubCore.m_placeReplaced and IsPlacementMode( UI.GetInterfaceMode() ) then UI.SetInterfaceMode( InterfaceModeTypes.SELECTION ); end
	local plot:table = HubCore.GetSelectionPlot();
	if plot ~= nil then HubCursor.SetCursor( plot:GetX(), plot:GetY(), false, nil, true ); end
end

local function PlacementCancel()
	HubCore.SayResult( "Placement cancelled" );
	UI.SetInterfaceMode( InterfaceModeTypes.SELECTION );		-- the mode change closes the browser; the game reopens the production panel
end

-- Escape: back from the confirmation first, then out of the placement.
local function PlacementEscape()
	if HubCore.m_placeConfirm ~= nil then
		HubCore.m_placeConfirm = nil;
		OutputMessageToScreenReader( "Back to the list" );
		return;
	end
	PlacementCancel();
end

-- Asks the engine again (a tile was bought, or the map changed).
local function PlacementRescan()
	local scan:table = m_placeScan;
	if scan == nil then return nil; end
	local city:table = UI.GetHeadSelectedCity();
	if city == nil then return nil; end
	m_placeScan = PlacementScan_Scan( city, scan.kind, scan.hash, scan.purchaseYield );
	return m_placeScan;
end

-- The production / purchase that followed the placement, said once the engine has applied it.
local function PlacementResult( scan:table, before:table, tries:number )
	-- the city captured at commit time: the game may already have selected the next unit (no selected city any more)
	local city:table = before.city;
	if city == nil or not HubCore.IsLocalPlayerActive() then return; end
	-- the selection of the next unit may already have been spoken: do not cut it off, queue behind it
	local SayLocal = function( text:string )
		HubCore.m_lastResultTime = UI.GetElapsedTime();
		OutputMessageToScreenReader( text, m_lastSelectionSpeech > m_placeCommitTime );
	end
	if scan.purchaseYield ~= nil then
		local player:table = Players[ Game.GetLocalPlayer() ];
		local isGold:boolean = ( scan.purchaseYield == YieldTypes.GOLD );
		local balance:number = isGold and math.floor( player:GetTreasury():GetGoldBalance() ) or math.floor( player:GetReligion():GetFaithBalance() );
		if balance < before.balance then
			SayLocal( "Bought " .. scan.name .. ", " .. balance .. ( isGold and " gold" or " faith" ) .. " left" );
			return;
		end
	else
		local queue:table = city:GetBuildQueue();
		local hash:number = queue:GetCurrentProductionTypeHash();
		if hash == scan.hash or queue:GetSize() > before.size then
			local text:string = ( hash == scan.hash and "Producing " or "Queued " ) .. scan.name;
			local turns:number = queue:GetTurnsLeft();
			if hash == scan.hash and turns ~= nil and turns > 0 then text = text .. ", " .. HubCore.Plural( turns, "turn", "turns" ); end
			SayLocal( text );
			return;
		end
	end
	if tries < 3 then
		HubCore.After( 0.5, function() PlacementResult( scan, before, tries + 1 ); end );
	else
		SayLocal( "Not placed. Tab to the production panel to check" );
	end
end

local function PlacementCommit( c:table )
	local scan:table = m_placeScan;
	local city:table = UI.GetHeadSelectedCity();
	local plot:table = Map.GetPlotByIndex( c.plotIndex );
	if scan == nil or city == nil or plot == nil then return; end
	local params:table = {};
	params[ CityOperationTypes.PARAM_X ] = plot:GetX();
	params[ CityOperationTypes.PARAM_Y ] = plot:GetY();
	local purchase:boolean = ( scan.purchaseYield ~= nil );
	if scan.kind == "district" then
		params[ CityOperationTypes.PARAM_DISTRICT_TYPE ] = scan.hash;
		params[ CityCommandTypes.PARAM_YIELD_TYPE ] = scan.purchaseYield;
	else
		params[ CityOperationTypes.PARAM_BUILDING_TYPE ] = scan.hash;
	end
	for key, value in pairs( m_placeParams or {} ) do params[ key ] = value; end		-- insert mode and queue position
	local can:boolean, results;
	if purchase then
		can, results = CityManager.CanStartCommand( city, CityCommandTypes.PURCHASE, params, true );
	else
		can, results = CityManager.CanStartOperation( city, CityOperationTypes.BUILD, params, true );
	end
	local player:table = Players[ Game.GetLocalPlayer() ];
	if not can then
		if purchase then
			local ok:boolean, cost:number = pcall( function() return city:GetGold():GetPurchaseCost( scan.purchaseYield, scan.hash ); end );
			local isGold:boolean = ( scan.purchaseYield == YieldTypes.GOLD );
			local balance:number = isGold and math.floor( player:GetTreasury():GetGoldBalance() ) or math.floor( player:GetReligion():GetFaithBalance() );
			if ok and cost ~= nil and cost > balance then
				HubCore.SayResult( "Can't buy " .. scan.name .. ", need " .. ( cost - balance ) .. ( isGold and " more gold" or " more faith" ) );
				return;
			end
		end
		local reasons:table = {};
		if results ~= nil then
			for _, text in ipairs( results[ CityOperationResults.FAILURE_REASONS ] or results[ CityCommandResults.FAILURE_REASONS ] or {} ) do table.insert( reasons, CleanTextForSpeech( Locale.Lookup( text ) ) ); end
		end
		HubCore.SayResult( "Can't place " .. scan.name .. " here any more" .. ( #reasons > 0 and ( ": " .. table.concat( reasons, ", " ) ) or "" ) );
		PlacementRescan();
		return;
	end
	local before:table = { size = city:GetBuildQueue():GetSize(), balance = 0, city = city };
	if purchase then
		before.balance = ( scan.purchaseYield == YieldTypes.GOLD ) and math.floor( player:GetTreasury():GetGoldBalance() ) or math.floor( player:GetReligion():GetFaithBalance() );
		CityManager.RequestCommand( city, CityCommandTypes.PURCHASE, params );
	else
		CityManager.RequestOperation( city, CityOperationTypes.BUILD, params );
	end
	HubCore.m_lastKeyTime = UI.GetElapsedTime();
	m_placeCommitTime = HubCore.m_lastKeyTime;
	LuaEvents.SRA_ExitPlacement( false );		-- WorldInput: leave the mode as the game does after placing (closes this mode)
	HubCore.After( 0.3, function()		-- the hook may be missing or fail: never stay in the placement mode after a commit
		if IsPlacementMode( UI.GetInterfaceMode() ) then UI.SetInterfaceMode( InterfaceModeTypes.SELECTION ); end
	end );
	HubCore.After( 0.4, function() PlacementResult( scan, before, 1 ); end );
end

local function PlacementBuyTile( c:table )
	local scan:table = m_placeScan;
	local city:table = UI.GetHeadSelectedCity();
	local plot:table = Map.GetPlotByIndex( c.plotIndex );
	if scan == nil or city == nil or plot == nil then return; end
	local player:table = Players[ Game.GetLocalPlayer() ];
	local gold:number = math.floor( player:GetTreasury():GetGoldBalance() );
	-- the engine's reasons that are not about ownership: then buying the tile would waste the gold
	local blockers:string = PlacementScan_Blockers( scan, plot );
	if blockers ~= "" then
		print( "InGameAccess: not buying tile " .. plot:GetX() .. "," .. plot:GetY() .. " for " .. scan.typeName .. ": " .. blockers );
		HubCore.SayResult( "Not buying this tile, " .. scan.name .. " can't go there: " .. blockers );
		return;
	end
	local params:table = {};
	params[ CityCommandTypes.PARAM_PLOT_PURCHASE ] = UI.GetInterfaceModeParameter( CityCommandTypes.PARAM_PLOT_PURCHASE );
	params[ CityCommandTypes.PARAM_X ] = c.x;
	params[ CityCommandTypes.PARAM_Y ] = c.y;
	-- CanStartCommand does not look at the balance (verified: it says yes and the purchase then silently fails)
	if gold < c.tileCost then
		HubCore.SayResult( "Can't buy this tile, need " .. ( c.tileCost - gold ) .. " more gold" );
		return;
	end
	if not CityManager.CanStartCommand( city, CityCommandTypes.PURCHASE, params ) then
		HubCore.SayResult( "Can't buy this tile" );
		return;
	end
	local owner:number = plot:GetOwner();
	CityManager.RequestCommand( city, CityCommandTypes.PURCHASE, params );
	HubCore.m_lastKeyTime = UI.GetElapsedTime();
	m_placeBusy = true;
	local function Report( tries:number )
		if not HubCore.IsModeOpen( "placement" ) then m_placeBusy = false; return; end
		if plot:GetOwner() == owner then
			if tries < 2 then
				HubCore.After( 1.0, function() Report( tries + 1 ); end );		-- the engine may not have applied the purchase yet
				return;
			end
			m_placeBusy = false;
			PlacementRescan();
			HubCore.SayResult( "Tile not bought" .. ( gold < c.tileCost and ( ", need " .. ( c.tileCost - gold ) .. " more gold" ) or "" ) );
			return;
		end
		local fresh:table = PlacementRescan();
		m_placeBusy = false;
		if fresh == nil then return; end
		local c2:table = fresh.byIndex[ c.plotIndex ];
		if c2 ~= nil and c2.owned then
			local effects:string = PlacementEffects( c2, false );
			HubCore.SayResult( "Tile bought for " .. c.tileCost .. " gold. Valid" .. ( effects ~= "" and ( ", " .. effects ) or "" ) .. ". Enter to place " .. fresh.name .. " here" );
		else
			local why:string = PlacementScan_Blockers( fresh, plot );
			if why == "" then why = PlacementScan_Cannot( fresh, plot ); end
			print( "InGameAccess: tile " .. plot:GetX() .. "," .. plot:GetY() .. " bought but refused for " .. fresh.typeName .. ": " .. why );
			HubCore.SayResult( "Tile bought, but " .. fresh.name .. " can't go there" .. ( why ~= "" and ( ": " .. why ) or "" ) );
		end
	end
	HubCore.After( 0.6, function() Report( 1 ); end );
end

-- Enter: the tile under the cursor (browsing puts the cursor on the listed tile; Shift+Arrows move it freely). The first
-- Enter asks, the second one does it.
local function PlacementEnter( item:table )
	local scan:table = m_placeScan;
	if scan == nil then return; end
	if m_placeBusy then HubCore.SayResult( "Wait" ); return; end
	local x:number, y:number = HubCursor.GetCursor();
	local plot:table = Map.GetPlot( x, y );
	if plot == nil then return; end
	local c:table = scan.byIndex[ plot:GetIndex() ];
	if c == nil then
		local why:string = PlacementScan_Cannot( scan, plot );
		HubCore.SayResult( "Can't place " .. scan.name .. " here" .. ( why ~= "" and ( ": " .. why ) or "" ) );
		return;
	end
	if HubCore.m_placeConfirm == c.plotIndex then
		HubCore.m_placeConfirm = nil;
		if c.owned then PlacementCommit( c ); else PlacementBuyTile( c ); end
		return;
	end
	HubCore.m_placeConfirm = c.plotIndex;
	local effects:string = PlacementEffects( c, false );
	if c.owned then
		HubCore.SayResult( "Place " .. scan.name .. " here?" .. ( effects ~= "" and ( " " .. effects .. "." ) or "" ) .. " Enter to confirm, Escape to go back" );
	else
		HubCore.SayResult( "Buy this tile for " .. c.tileCost .. " gold?" .. ( effects ~= "" and ( " " .. effects .. "." ) or "" ) .. " Enter to confirm, then Enter again to place " .. scan.name .. ". Escape to go back" );
	end
end

m_placeList = KeyNavList_Create{
	build		= BuildPlacementItems,
	isActive	= function() return HubCore.IsModeOpen( "placement" ); end,
	onActivate	= PlacementEnter,
	onClose		= PlacementEscape,
	onFocus		= function( item )
		HubCore.m_placeConfirm = nil;
		HubCursor.SetCursor( item.candidate.x, item.candidate.y, false, nil, true );
	end,
};

-- The game entered DISTRICT_PLACEMENT / BUILDING_PLACEMENT: scan, open the mode, say what can be done.
HubCore.OpenPlacement = function( mode:number )
	local city:table = UI.GetHeadSelectedCity();
	if city == nil or not HubCore.IsLocalPlayerActive() then
		OutputMessageToScreenReader( "Placement: nothing to browse, Escape to cancel" );
		return;
	end
	local kind:string, hash:number;
	local purchaseYield:number = nil;
	if mode == InterfaceModeTypes.DISTRICT_PLACEMENT then
		kind = "district";
		hash = UI.GetInterfaceModeParameter( CityOperationTypes.PARAM_DISTRICT_TYPE );
		local yield:number = UI.GetInterfaceModeParameter( CityCommandTypes.PARAM_YIELD_TYPE );
		if yield ~= nil and ( yield == YieldTypes.GOLD or yield == YieldTypes.FAITH ) then purchaseYield = yield; end
	else
		kind = "wonder";
		hash = UI.GetInterfaceModeParameter( CityOperationTypes.PARAM_BUILDING_TYPE );
	end
	m_placeParams = {};		-- read now: leaving the mode forgets them
	for _, key in ipairs( { CityOperationTypes.PARAM_INSERT_MODE, CityOperationTypes.PARAM_QUEUE_LOCATION,
			CityOperationTypes.PARAM_QUEUE_SOURCE_LOCATION, CityOperationTypes.PARAM_QUEUE_DESTINATION_LOCATION } ) do
		m_placeParams[ key ] = UI.GetInterfaceModeParameter( key );
	end
	local scan:table = PlacementScan_Scan( city, kind, hash, purchaseYield );
	if scan.name == nil then
		OutputMessageToScreenReader( "Placement: nothing to browse, Escape to cancel" );
		return;
	end
	local function Leave()
		HubCore.After( 0.1, function() if IsPlacementMode( UI.GetInterfaceMode() ) then UI.SetInterfaceMode( InterfaceModeTypes.SELECTION ); end end );
	end
	-- No owned tile can take it. The game still highlights tiles it could buy, so ask the engine why: either only the
	-- location is missing (a bought tile can help), or there is a real reason (population for another district, a
	-- missing building ...) and buying a tile would waste the gold.
	local ownedNone:boolean = ( scan.owned == 0 );
	if ownedNone then
		local why:table = PlacementScan_Explain( scan );
		if not why.canBuy and #why.reasons > 0 then
			OutputMessageToScreenReader( "Can't build " .. scan.name .. ": " .. table.concat( why.reasons, ", " ) );
			Leave();
			return;
		end
		if #scan.list == 0 then
			local text:string = "Can't build " .. scan.name .. ": no tile fits";
			if scan.blockedReason ~= nil then text = text .. ", " .. scan.blockedReason; end
			OutputMessageToScreenReader( text );
			Leave();
			return;
		end
	end
	if #scan.list == 0 then
		OutputMessageToScreenReader( "No valid tiles for " .. scan.name );
		Leave();
		return;
	end
	m_placeScan = scan;
	HubCore.m_placeConfirm = nil;
	m_placeBusy = false;
	HubCore.CloseMode( false, true );
	HubCore.m_mode = { name = "placement", list = m_placeList, onClose = PlacementClosed };
	local best:table = scan.best;
	m_placeList.Open( "", best.key, true );
	HubCursor.SetCursor( best.x, best.y, false, nil, true );
	local text:string;
	if ownedNone then
		text = "No owned tile fits; " .. HubCore.Plural( #scan.list, "tile", "tiles" ) .. " can be bought. Best: " .. PlacementItemText( best ) .. ".";
	else
		text = "Place " .. scan.name .. " for " .. scan.cityName .. ( purchaseYield ~= nil and ", bought with " .. ( purchaseYield == YieldTypes.GOLD and "gold" or "faith" ) or "" )
			.. ", " .. HubCore.Plural( #scan.list, "tile", "tiles" ) .. ". Best: " .. PlacementItemText( best ) .. ".";
	end
	if scan.blocked > 0 and scan.blockedReason ~= nil then
		text = text .. " " .. HubCore.Plural( scan.blocked, "tile", "tiles" ) .. " not offered: " .. scan.blockedReason .. ".";
	end
	OutputMessageToScreenReader( text );
end

-- ===========================================================================
--	UNIT ACTIONS MENU (Tab): the actions of the game's own unit panel (Panels/UnitPanel.lua)
-- ===========================================================================
local OPERATION_RESULTS = {
	UNITOPERATION_FORTIFY = "Fortified", UNITOPERATION_HEAL = "Fortified until healed", UNITOPERATION_SLEEP = "Sleeping",
	UNITOPERATION_ALERT = "On alert", UNITOPERATION_SKIP_TURN = "Turn skipped", UNITOPERATION_AUTOMATE_EXPLORE = "Exploring automatically",
	UNITOPERATION_REST_REPAIR = "Resting", UNITCOMMAND_WAKE = "Awake", UNITCOMMAND_CANCEL = "Orders cancelled",
};
-- Actions that announce their outcome in another way (events below, popups, target modes).
local RESULT_SILENT = {
	UNITOPERATION_FOUND_CITY = true, UNITOPERATION_BUILD_IMPROVEMENT = true, UNITCOMMAND_UPGRADE = true, PROMOTION = true,
	UNITOPERATION_MOVE_TO = true, UNITCOMMAND_PROMOTE = true,
};

local function OnUnitActionsReceived( unitId:number, list:table )
	m_unitActions = list or {};
end

-- Asks UnitPanel for the selected unit's actions (it answers at once with SRA_UnitActions). refresh: let the panel
-- refresh its state first; only done when the menu opens and when an action is run, not on every key.
local function FetchMenuItems( refresh:boolean )
	local items:table = {};
	if UI.GetHeadSelectedUnit() == nil then return items; end
	m_unitActions = {};
	LuaEvents.SRA_RequestUnitActions( refresh );
	for _, action in ipairs( m_unitActions ) do
		local text:string = action.name;
		if action.hotkey ~= nil and action.hotkey ~= "" then text = text .. ", key " .. action.hotkey; end
		if action.disabled then
			text = text .. ", unavailable" .. ( action.reason ~= "" and ( ": " .. action.reason ) or "" );
		end
		table.insert( items, {
			key = tostring( action.tag ) .. "|" .. action.name, text = text, detail = action.detail,
			choosable = not action.disabled, reason = ( action.reason ~= "" ) and action.reason or "Not available",
			action = action } );
	end
	return items;
end

local function BuildMenuItems()
	return m_menuItems;
end

local m_menu:table;

local function RunMenuItem( item:table )
	local unit:table = UI.GetHeadSelectedUnit();
	if unit == nil then return; end
	-- the state may have changed since the menu was opened: look the action up again, with a refresh
	local fresh:table = nil;
	for _, candidate in ipairs( FetchMenuItems( true ) ) do
		if candidate.key == item.key then fresh = candidate; end
	end
	if fresh == nil or fresh.choosable == false then
		HubCore.CloseMode( false, false );
		HubCore.SayResult( ( fresh ~= nil ) and fresh.reason or "No longer available" );
		return;
	end
	item = fresh;
	HubCore.CloseMode( false, false );
	local modeBefore:number = UI.GetInterfaceMode();
	LuaEvents.SRA_RunUnitAction( item.action.id, unit:GetID() );
	-- Fortify, sleep ... speak their result from the game's UnitOperationStarted event (so the hotkeys are covered too);
	-- target modes, found city, building and the like announce themselves. Anything else: say what was chosen.
	if UI.GetInterfaceMode() == modeBefore and not RESULT_SILENT[ item.action.typeName ]
			and OPERATION_RESULTS[ item.action.typeName ] == nil then
		HubCore.SayResult( item.action.name );
	end
end

local function ToggleUnitMenu()
	if not HubCore.IsLocalPlayerActive() then return; end
	if HubCore.IsModeOpen( "menu" ) then
		HubCore.CloseMode( true, false );
		return;
	end
	local unit:table = UI.GetHeadSelectedUnit();
	if unit == nil then
		local city:table = UI.GetHeadSelectedCity();
		if city ~= nil and city:GetOwner() == Game.GetLocalPlayer() then
			-- A city has no action menu; Tab opens its production panel (Tab inside it switches Production / Purchase).
			HubCore.CloseMode( false, true );
			LuaEvents.CityPanel_ProductionOpen();
		elseif city ~= nil then
			OutputMessageToScreenReader( "Not your city" );
		else
			OutputMessageToScreenReader( "No unit selected" );
		end
		return;
	end
	if unit:GetOwner() ~= Game.GetLocalPlayer() then
		OutputMessageToScreenReader( "Not your unit" );
		return;
	end
	if not HubTargets.CanOpenMode() then return; end
	m_menuItems = FetchMenuItems( true );
	if #m_menuItems == 0 then
		OutputMessageToScreenReader( Locale.Lookup( unit:GetName() ) .. " has no actions" );
		return;
	end
	HubCore.OpenMode( "menu", m_menu, Locale.Lookup( unit:GetName() ) .. " actions" );
end

m_menu = KeyNavList_Create{
	build		= BuildMenuItems,
	isActive	= function() return HubCore.IsModeOpen( "menu" ); end,
	onActivate	= RunMenuItem,
	onClose		= function() HubCore.CloseMode( true, false ); end,
};

-- ===========================================================================
--	DIPLOMACY (V): the civilizations met so far; Enter opens the game's diplomacy screen with that leader
-- ===========================================================================
local m_civMenu:table;

local function BuildCivItems()
	local items:table = {};
	local localPlayer:number = Game.GetLocalPlayer();
	if not HubCore.IsLocalPlayerActive() then return items; end
	local diplomacy:table = Players[ localPlayer ]:GetDiplomacy();
	for _, other in ipairs( PlayerManager.GetAliveMajors() ) do
		local id:number = other:GetID();
		if id ~= localPlayer and diplomacy:HasMet( id ) then
			local config:table = PlayerConfigurations[ id ];
			local state:string = diplomacy:IsAtWarWith( id ) and "at war" or "at peace";
			table.insert( items, {
				key = "civ:" .. id, civ = id,
				text = Locale.Lookup( config:GetLeaderName() ) .. ", " .. PlotDescription_GetCivName( id ) .. ", " .. state,
			} );
		end
	end
	return items;
end

m_civMenu = KeyNavList_Create{
	build		= BuildCivItems,
	isActive	= function() return HubCore.IsModeOpen( "civ" ); end,
	onActivate	= function( item )
		HubCore.CloseMode( false, false );
		LuaEvents.DiplomacyRibbon_OpenDiplomacyActionView( item.civ );
	end,
	onClose		= function() HubCore.CloseMode( true, false ); end,
};

local function ToggleCivMenu()
	if not HubCore.IsLocalPlayerActive() then return; end
	if HubCore.IsModeOpen( "civ" ) then HubCore.CloseMode( true, false ); return; end
	if not HubTargets.CanOpenMode() then return; end
	if #BuildCivItems() == 0 then
		OutputMessageToScreenReader( "You have not met any other civilization" );
		return;
	end
	HubCore.OpenMode( "civ", m_civMenu, "Diplomacy, met civilizations" );
end

-- ===========================================================================
--	REGIONS: the top panel (Control+Y) and the notifications (Control+N) as lists
--	Up/Down (Left/Right in the top panel too) move and wrap, Home/End, Space reads details, Enter opens/activates,
--	Escape returns to the map. Control+Y / Control+N again closes.
-- ===========================================================================
local m_topList:table;
local m_notifList:table;

m_topList = KeyNavList_Create{
	build		= function() return TopPanelData_BuildItems(); end,
	isActive	= function() return HubCore.IsModeOpen( "top" ); end,
	horizontal	= true,
	onActivate	= function( item )
		if item.open == "research" then
			HubCore.CloseMode( false, false );
			LuaEvents.ActionPanel_OpenChooseResearch();
		elseif item.open == "civic" then
			HubCore.CloseMode( false, false );
			LuaEvents.ActionPanel_OpenChooseCivic();
		else
			OutputMessageToScreenReader( "Nothing to open here. Space reads the details" );
		end
	end,
	onClose		= function() HubCore.CloseMode( true, false ); end,
};

local function ToggleTopPanel()
	if HubCore.IsModeOpen( "top" ) then HubCore.CloseMode( true, false ); return; end
	if not HubTargets.CanOpenMode() then return; end
	HubCore.OpenMode( "top", m_topList, "Top panel" );
end

-- Control+G: the basic yields in one sentence, without entering the region.
local function SpeakYields()
	if not HubCore.IsLocalPlayerActive() then return; end
	OutputMessageToScreenReader( TopPanelData_Summary() );
end

-- Control+I: the city report region (yields, growth and housing, amenities, loyalty, defense, production, districts,
-- citizens, religion ...). Data: CityReportGather (the game's GetCityData), text: CityReportData. About the selected city,
-- else your city on the map cursor plot. The city is remembered by id, the items are rebuilt at every key.
local m_reportCity:table = nil;		-- { owner, id } of the city the open report is about
local m_reportList:table;

local function GetReportCity()
	if m_reportCity == nil then return nil; end
	local player:table = Players[ m_reportCity.owner ];
	if player == nil then return nil; end
	return player:GetCities():FindID( m_reportCity.id );
end

-- City management inside the report (Enter on the Focus, Tiles or Specialists item opens a sub-list; Escape goes back to the
-- report). The commands are the ones the game's mouse UI sends, replicated parameter for parameter (the originals live in
-- other contexts: PlotInfo.lua, CityPanel.lua), see the Request* functions. UNVERIFIED in game.
Hub.m_manageView = nil;		-- nil: the report itself; "focus", "tiles" or "specialists"
Hub.m_manageConfirm = nil;		-- key of the buyable tile that waits for its second Enter
Hub.m_manageBusy = false;		-- a request was sent and its result is not known yet

-- Mirrors PlotInfo.OnClickCitizen (Base/Assets/UI/WorldView/PlotInfo.lua:55-67): the click on a citizen button of a tile.
-- The game's click toggles work/lock on a tile and adds specialists to a district.
function Hub.RequestCitizenClick( city:table, plot:table )
	local params:table = {};
	params[ CityCommandTypes.PARAM_MANAGE_CITIZEN ] = UI.GetInterfaceModeParameter( CityCommandTypes.PARAM_MANAGE_CITIZEN );
	params[ CityCommandTypes.PARAM_X ] = plot:GetX();
	params[ CityCommandTypes.PARAM_Y ] = plot:GetY();
	CityManager.RequestCommand( city, CityCommandTypes.MANAGE, params );
end

-- Mirrors PlotInfo.OnClickPurchasePlot (PlotInfo.lua:83-98). False when the engine refuses.
function Hub.RequestPlotPurchase( city:table, plot:table )
	local params:table = {};
	params[ CityCommandTypes.PARAM_PLOT_PURCHASE ] = UI.GetInterfaceModeParameter( CityCommandTypes.PARAM_PLOT_PURCHASE );
	params[ CityCommandTypes.PARAM_X ] = plot:GetX();
	params[ CityCommandTypes.PARAM_Y ] = plot:GetY();
	if not CityManager.CanStartCommand( city, CityCommandTypes.PURCHASE, params ) then return false; end
	CityManager.RequestCommand( city, CityCommandTypes.PURCHASE, params );
	return true;
end

-- Mirror CityPanel.SetYieldFocus / SetYieldIgnore (Base/Assets/UI/Panels/CityPanel.lua:445-478), g_pCity = city.
function Hub.RequestYieldFocus( city:table, yieldType:number )
	local citizens:table = city:GetCitizens();
	local params:table = {};
	params[ CityCommandTypes.PARAM_FLAGS ] = 0;				-- Set Favored
	params[ CityCommandTypes.PARAM_YIELD_TYPE ] = yieldType;
	if citizens:IsFavoredYield( yieldType ) then
		params[ CityCommandTypes.PARAM_DATA0 ] = 0;
	else
		if citizens:IsDisfavoredYield( yieldType ) then Hub.RequestYieldIgnore( city, yieldType ); end
		params[ CityCommandTypes.PARAM_DATA0 ] = 1;
	end
	CityManager.RequestCommand( city, CityCommandTypes.SET_FOCUS, params );
end

Hub.RequestYieldIgnore = function( city:table, yieldType:number )
	local citizens:table = city:GetCitizens();
	local params:table = {};
	params[ CityCommandTypes.PARAM_FLAGS ] = 1;				-- Set Ignored
	params[ CityCommandTypes.PARAM_YIELD_TYPE ] = yieldType;
	if citizens:IsDisfavoredYield( yieldType ) then
		params[ CityCommandTypes.PARAM_DATA0 ] = 0;
	else
		if citizens:IsFavoredYield( yieldType ) then Hub.RequestYieldFocus( city, yieldType ); end
		params[ CityCommandTypes.PARAM_DATA0 ] = 1;
	end
	CityManager.RequestCommand( city, CityCommandTypes.SET_FOCUS, params );
end

function Hub.ManageData()
	local city:table = GetReportCity();
	if city == nil then return nil, nil; end
	return CityManage_Gather( city ), city;
end

-- "Food plus 5, production 13" of the city as it is now
function Hub.ManageTotals( city:table )
	local data:table = CityReport_Gather( city );
	if data == nil then return ""; end
	return CityManage_Totals( data );
end

-- After a request: waits until read() differs from before (the engine applies the command a moment later), then say( now ).
-- Gives up after 2 s with "Nothing changed".
function Hub.ManageWatch( read, before:string, say )
	Hub.m_manageBusy = true;
	HubCore.m_lastKeyTime = UI.GetElapsedTime();
	local function Poll( tries:number )
		HubCore.After( 0.4, function()
			if not HubCore.IsModeOpen( "cityreport" ) then Hub.m_manageBusy = false; return; end
			local ok:boolean, now = pcall( read );
			if ok and now ~= before then
				Hub.m_manageBusy = false;
				local ok2:boolean, err = pcall( say, now );
				if not ok2 then print( "InGameAccess city management error: " .. tostring( err ) ); end
			elseif tries >= 5 then
				Hub.m_manageBusy = false;
				print( "InGameAccess: the city management request changed nothing" );
				OutputMessageToScreenReader( "Nothing changed" );
			else
				Poll( tries + 1 );
			end
		end );
	end
	Poll( 1 );
end

function Hub.FindByPlot( list:table, plotIndex:number )
	for _, entry in ipairs( list or {} ) do
		if entry.plotIndex == plotIndex then return entry; end
	end
	return nil;
end

function Hub.EnterManageView( view:string )
	local city:table = GetReportCity();
	if city == nil then return; end
	Hub.m_manageView = view;
	Hub.m_manageConfirm = nil;
	Hub.m_manageBusy = false;
	if view == "focus" then
		Hub.m_focusList.Reset();
		Hub.m_focusList.Open( "Focus" );
	elseif view == "tiles" then
		Hub.m_tilesList.Reset();
		Hub.m_tilesList.Open( "Tiles" );
	else
		Hub.m_specList.Reset();
		Hub.m_specList.Open( "Specialists" );
	end
end

function Hub.LeaveManageView()
	local view:string = Hub.m_manageView;
	Hub.m_manageView = nil;
	Hub.m_manageConfirm = nil;
	Hub.m_manageBusy = false;
	Hub.m_focusList.Reset();
	Hub.m_tilesList.Reset();
	Hub.m_specList.Reset();
	local city:table = GetReportCity();
	if city ~= nil and view ~= "focus" then HubCursor.SetCursor( city:GetX(), city:GetY(), false, nil, true ); end
	m_reportList.Focus( view );
end

function Hub.CursorToPlotIndex( plotIndex:number )
	local plot:table = Map.GetPlotByIndex( plotIndex );
	if plot ~= nil then HubCursor.SetCursor( plot:GetX(), plot:GetY(), false, nil, true ); end
end

function Hub.FocusState( city:table, yieldType:number )
	local citizens:table = city:GetCitizens();
	if citizens:IsFavoredYield( yieldType ) then return "favored"; end
	if citizens:IsDisfavoredYield( yieldType ) then return "ignored"; end
	return "normal";
end

function Hub.FocusEnter( item:table )
	if Hub.m_manageBusy then OutputMessageToScreenReader( "Wait" ); return; end
	local city:table = GetReportCity();
	if city == nil then return; end
	local f:table = item.yield;
	local name:string = string.lower( f.name );
	local before:string = Hub.FocusState( city, f.yieldType );
	if item.ignore then Hub.RequestYieldIgnore( city, f.yieldType ); else Hub.RequestYieldFocus( city, f.yieldType ); end
	Hub.ManageWatch( function() return Hub.FocusState( city, f.yieldType ); end, before, function( now )
		local text:string;
		if now == "favored" then
			text = f.name .. " focus on";
		elseif now == "ignored" then
			text = "Ignoring " .. name;
		elseif item.ignore then
			text = "No longer ignoring " .. name;
		else
			text = f.name .. " focus off";
		end
		OutputMessageToScreenReader( text .. ". " .. Hub.ManageTotals( city ) );
	end );
end

function Hub.TilesEnter( item:table )
	if Hub.m_manageBusy then OutputMessageToScreenReader( "Wait" ); return; end
	local city:table = GetReportCity();
	local t:table = item.tile;
	local plot:table = Map.GetPlotByIndex( t.plotIndex );
	if city == nil or plot == nil then return; end
	if t.cost ~= nil then
		local gold:number = math.floor( Players[ Game.GetLocalPlayer() ]:GetTreasury():GetGoldBalance() );
		-- CanStartCommand does not look at the balance (docs/engine-notes.md)
		if gold < t.cost then
			Hub.m_manageConfirm = nil;
			OutputMessageToScreenReader( "Can't buy this tile, need " .. ( t.cost - gold ) .. " more gold" );
			return;
		end
		if Hub.m_manageConfirm ~= t.key then
			Hub.m_manageConfirm = t.key;
			OutputMessageToScreenReader( "Buy this tile for " .. t.cost .. " gold? Enter to confirm, Escape to go back" );
			return;
		end
		Hub.m_manageConfirm = nil;
		if not Hub.RequestPlotPurchase( city, plot ) then
			OutputMessageToScreenReader( "Can't buy this tile" );
			return;
		end
		Hub.ManageWatch( function() return tostring( plot:GetOwner() ); end, tostring( plot:GetOwner() ), function()
			Hub.m_tilesList.Focus( "t" .. t.plotIndex, "Bought for " .. t.cost .. " gold" );
		end );
		return;
	end
	local function Sig()
		local m:table = Hub.ManageData();
		local now:table = m ~= nil and Hub.FindByPlot( m.tiles, t.plotIndex ) or nil;
		if now == nil then return "gone"; end
		return now.count .. ":" .. tostring( now.locked );
	end
	local before:string = Sig();
	Hub.RequestCitizenClick( city, plot );
	Hub.ManageWatch( Sig, before, function()
		local m:table = Hub.ManageData();
		local now:table = m ~= nil and Hub.FindByPlot( m.tiles, t.plotIndex ) or nil;
		local state:string = ( now ~= nil ) and CityManage_TileState( now ) or "Changed";
		OutputMessageToScreenReader( state .. ". " .. Hub.ManageTotals( city ) );
	end );
end

function Hub.SpecialistsEnter( item:table )
	if Hub.m_manageBusy then OutputMessageToScreenReader( "Wait" ); return; end
	local city:table = GetReportCity();
	local dist:table = item.district;
	local plot:table = Map.GetPlotByIndex( dist.plotIndex );
	if city == nil or plot == nil then return; end
	local function Count()
		local m:table = Hub.ManageData();
		local now:table = m ~= nil and Hub.FindByPlot( m.districts, dist.plotIndex ) or nil;
		return now ~= nil and tostring( now.count ) or "gone";
	end
	local before:string = Count();
	Hub.RequestCitizenClick( city, plot );
	Hub.ManageWatch( Count, before, function()
		local m:table = Hub.ManageData();
		local now:table = m ~= nil and Hub.FindByPlot( m.districts, dist.plotIndex ) or nil;
		if now == nil then return; end
		OutputMessageToScreenReader( CityManage_DistrictText( now ) .. ". " .. Hub.ManageTotals( city ) );
	end );
end

-- Backspace / Delete: one specialist less. The game has no "remove one" click (a click adds, and past the last slot the
-- district empties), so this clicks until the count has dropped by one (at most as many clicks as slots plus one).
function Hub.SpecialistsRemove()
	if Hub.m_manageBusy then OutputMessageToScreenReader( "Wait" ); return; end
	local m:table, city:table = Hub.ManageData();
	if m == nil then return; end
	local focusKey = Hub.m_specList.GetFocusKey();
	local dist:table = nil;
	for _, candidate in ipairs( m.districts ) do
		if candidate.key == focusKey then dist = candidate; end
	end
	if dist == nil then return; end
	if dist.count == 0 then
		OutputMessageToScreenReader( dist.name .. " has no specialists to remove" );
		return;
	end
	local plot:table = Map.GetPlotByIndex( dist.plotIndex );
	local goal:number = dist.count - 1;
	local clicks:number = 0;
	local function Count()
		local fresh:table = Hub.ManageData();
		local now:table = fresh ~= nil and Hub.FindByPlot( fresh.districts, dist.plotIndex ) or nil;
		return now ~= nil and tostring( now.count ) or "gone";
	end
	local function Say()
		local fresh:table = Hub.ManageData();
		local now:table = fresh ~= nil and Hub.FindByPlot( fresh.districts, dist.plotIndex ) or nil;
		if now == nil then return; end
		OutputMessageToScreenReader( CityManage_DistrictText( now ) .. ". " .. Hub.ManageTotals( city ) );
	end
	local function Step()
		clicks = clicks + 1;
		local before:string = Count();
		Hub.RequestCitizenClick( city, plot );
		Hub.ManageWatch( Count, before, function( now )
			if tonumber( now ) == goal or clicks > dist.max then Say(); else Step(); end
		end );
	end
	Step();
end

m_reportList = KeyNavList_Create{
	build		= function()
		local city:table = GetReportCity();
		if city == nil then return {}; end
		local data:table = CityReport_Gather( city );
		if data == nil then return {}; end
		return CityReport_BuildItems( data );
	end,
	isActive	= function() return HubCore.IsModeOpen( "cityreport" ) and Hub.m_manageView == nil; end,
	onActivate	= function( item )
		if item.manage ~= nil then Hub.EnterManageView( item.manage ); return; end
		OutputMessageToScreenReader( "Nothing to open here. Space reads the details" );
	end,
	onClose		= function() HubCore.CloseMode( true, false ); end,
};

Hub.m_focusList = KeyNavList_Create{
	build		= function()
		local m:table = Hub.ManageData();
		if m == nil then return {}; end
		return CityManage_FocusItems( m );
	end,
	isActive	= function() return HubCore.IsModeOpen( "cityreport" ) and Hub.m_manageView == "focus"; end,
	onActivate	= Hub.FocusEnter,
	onClose		= Hub.LeaveManageView,
};

Hub.m_tilesList = KeyNavList_Create{
	build		= function()
		local m:table = Hub.ManageData();
		if m == nil then return {}; end
		local items:table = CityManage_TileItems( m );
		for _, item in ipairs( items ) do
			local plotIndex:number = item.tile.plotIndex;
			item.detail = function()
				local plot:table = Map.GetPlotByIndex( plotIndex );
				if plot == nil then return nil; end
				return PlotDescription_GetDetailed( plot, {} );
			end;
		end
		return items;
	end,
	isActive	= function() return HubCore.IsModeOpen( "cityreport" ) and Hub.m_manageView == "tiles"; end,
	onActivate	= Hub.TilesEnter,
	onClose		= Hub.LeaveManageView,
	onFocus		= function( item )
		Hub.m_manageConfirm = nil;
		Hub.CursorToPlotIndex( item.tile.plotIndex );
	end,
};

Hub.m_specList = KeyNavList_Create{
	build		= function()
		local m:table = Hub.ManageData();
		if m == nil then return {}; end
		local items:table = CityManage_DistrictItems( m );
		for _, item in ipairs( items ) do
			item.detail = item.text .. ". Enter adds a specialist, Backspace removes one";
		end
		return items;
	end,
	isActive	= function() return HubCore.IsModeOpen( "cityreport" ) and Hub.m_manageView == "specialists"; end,
	onActivate	= Hub.SpecialistsEnter,
	onClose		= Hub.LeaveManageView,
	onFocus		= function( item ) Hub.CursorToPlotIndex( item.district.plotIndex ); end,
	extraKeys	= { [Keys.VK_BACK] = Hub.SpecialistsRemove, [Keys.VK_DELETE] = Hub.SpecialistsRemove },
};

-- What the mode holds: the report list and its sub-lists (each handles keys only while it is the active view).
Hub.m_reportFacade = {
	Open		= function( title:string ) Hub.m_manageView = nil; m_reportList.Open( title ); end,
	Reset		= function()
		Hub.m_manageView = nil;
		Hub.m_manageConfirm = nil;
		Hub.m_manageBusy = false;
		m_reportList.Reset();
		Hub.m_focusList.Reset();
		Hub.m_tilesList.Reset();
		Hub.m_specList.Reset();
	end,
	HandleInput	= function( input:table )
		return m_reportList.HandleInput( input ) or Hub.m_focusList.HandleInput( input ) or Hub.m_tilesList.HandleInput( input ) or Hub.m_specList.HandleInput( input );
	end,
};

local function ToggleCityReport()
	if HubCore.IsModeOpen( "cityreport" ) then HubCore.CloseMode( true, false ); return; end
	if not HubTargets.CanOpenMode() then return; end
	if not m_cityReportLoaded or CityReport_Gather == nil or CityReport_BuildItems == nil then
		OutputMessageToScreenReader( "The city report is not available" );
		return;
	end
	local localPlayer:number = Game.GetLocalPlayer();
	local city:table = UI.GetHeadSelectedCity();
	if city == nil or city:GetOwner() ~= localPlayer then
		city = nil;
		local x:number, y:number = HubCursor.GetCursor();
		local atCursor:table = Cities.GetCityInPlot( x, y );
		if atCursor ~= nil and atCursor:GetOwner() == localPlayer then city = atCursor; end
	end
	if city == nil then
		OutputMessageToScreenReader( "No city selected. Backslash selects the capital" );
		return;
	end
	m_reportCity = { owner = city:GetOwner(), id = city:GetID() };
	HubCore.OpenMode( "cityreport", Hub.m_reportFacade, Locale.Lookup( city:GetName() ) .. " report", function() m_reportCity = nil; end );
end

local function OnNotificationsReceived( list:table )
	m_notifData = list or {};
	m_notifAnswered = true;
end

-- Active notifications, newest first (ids grow with time). Rebuilt from the panel's own list at key time.
local function BuildNotificationItems()
	m_notifData = {};
	m_notifAnswered = false;
	LuaEvents.SRA_RequestNotifications();
	table.sort( m_notifData, function( a, b ) return a.id > b.id; end );
	local items:table = {};
	for _, n in ipairs( m_notifData ) do
		local title:string = CleanTextForSpeech( n.message );
		local summary:string = CleanTextForSpeech( n.summary );
		local detail:string = title;
		if summary ~= "" and summary ~= title then detail = detail .. ". " .. summary; end
		detail = string.gsub( detail, "[%.%s]+$", "" );
		if n.blocking then detail = detail .. ". Blocks ending the turn"; end
		if not n.dismissable then detail = detail .. ". Can't be dismissed"; end
		table.insert( items, {
			key = "n:" .. n.id, text = title, detail = detail, note = n,
			choosable = n.activatable, reason = "Can't activate this now",
		} );
	end
	return items;
end

-- Enter: what a click on the notification does (the panel's own Activate: look at the plot, select the unit,
-- open the chooser or screen). When nothing was selected or opened, the cursor goes to its plot and says it.
local m_activateReply		:table = nil;		-- answer of the panel to the last SRA_ActivateNotification: { found, lookOnly }

local function OnNotificationActivated( id:number, found:boolean, lookOnly:boolean )
	m_activateReply = { id = id, found = found, lookOnly = lookOnly };
end

local function ActivateNotification( item:table )
	local n:table = item.note;
	HubCore.CloseMode( false, false );
	local started:number = UI.GetElapsedTime();
	m_activateReply = nil;
	LuaEvents.SRA_ActivateNotification( n.id );		-- answered synchronously through SRA_NotificationActivated
	local reply:table = m_activateReply;
	if reply ~= nil and reply.id == n.id and not reply.found then
		OutputMessageToScreenReader( "Notification no longer available" );
		return;
	end
	local lookOnly:boolean = ( reply ~= nil and reply.lookOnly );
	local player:number = Game.GetLocalPlayer();
	local turn:number = Game.GetCurrentGameTurn();
	HubCore.After( 0.5, function()
		if m_lastSelectionSpeech >= started or HubCore.m_mode ~= nil then return; end		-- a selection or screen spoke for itself
		-- the world may have moved on in half a second (turn change, hotseat, a popup or a target mode opened)
		if Game.GetLocalPlayer() ~= player or Game.GetCurrentGameTurn() ~= turn or not HubCore.IsLocalPlayerActive() then return; end
		if not Players[ player ]:IsTurnActive() or UI.GetInterfaceMode() ~= InterfaceModeTypes.SELECTION then return; end
		if HubCore.IsGamePopupOpen() then return; end
		if n.x >= 0 and n.y >= 0 then
			HubCursor.SetCursor( n.x, n.y, true, false );
		elseif lookOnly then
			local title:string = CleanTextForSpeech( n.message );
			local summary:string = CleanTextForSpeech( n.summary );
			local text:string = title;
			if summary ~= "" and summary ~= title then text = text .. ". " .. summary; end
			text = string.gsub( text, "[%.%s]+$", "" );
			local gone:boolean = true;
			for _, other in ipairs( BuildNotificationItems() ) do
				if other.note.id == n.id then gone = false; end
			end
			if gone then text = text .. ". Dismissed"; end
			OutputMessageToScreenReader( text );
		end
	end );
end

local function DismissNotification()
	local items:table = BuildNotificationItems();
	local focus = m_notifList.GetFocusKey();
	local index:number = nil;
	for i, item in ipairs( items ) do
		if item.key == focus then index = i; end
	end
	if index == nil then
		OutputMessageToScreenReader( "Nothing selected" );
		return;
	end
	local item:table = items[ index ];
	if not item.note.dismissable then
		OutputMessageToScreenReader( "Can't dismiss this one" );
		return;
	end
	local neighbor = ( items[ index + 1 ] or items[ index - 1 ] );
	local neighborKey = ( neighbor ~= nil ) and neighbor.key or nil;
	LuaEvents.SRA_DismissNotification( item.note.id );
	HubCore.After( 0.3, function()
		if not HubCore.IsModeOpen( "notifications" ) then return; end
		local rest:table = BuildNotificationItems();
		if #rest == 0 then
			HubCore.CloseMode( false, false );
			OutputMessageToScreenReader( "Dismissed. No more notifications" );
			return;
		end
		for _, other in ipairs( rest ) do
			if other.key == item.key then
				OutputMessageToScreenReader( "Could not dismiss" );
				return;
			end
		end
		m_notifList.Focus( neighborKey, "Dismissed" );
	end );
end

m_notifList = KeyNavList_Create{
	build		= BuildNotificationItems,
	isActive	= function() return HubCore.IsModeOpen( "notifications" ); end,
	onActivate	= ActivateNotification,
	onClose		= function() HubCore.CloseMode( true, false ); end,
	extraKeys	= { [Keys.VK_DELETE] = DismissNotification },
};

local function ToggleNotifications()
	if HubCore.IsModeOpen( "notifications" ) then HubCore.CloseMode( true, false ); return; end
	if not HubTargets.CanOpenMode() then return; end
	if #BuildNotificationItems() == 0 then
		OutputMessageToScreenReader( m_notifAnswered and "No notifications" or "Notifications are not available" );
		return;
	end
	HubCore.OpenMode( "notifications", m_notifList, "Notifications" );
end

-- New notifications are announced when they arrive, without interrupting; a burst (turn start) becomes one sentence.
-- "Barbarians sighted" is left out only when the hub itself said "X spotted ..." for a hostile unit around that time
-- (the notification also covers sightings farther than 4 tiles from our cities and units, and the spotting is capped).
local m_lastSpotSpeech		:number = -100;		-- UI.GetElapsedTime() of the last "X spotted" announcement

local function OnNotificationAdded( id:number, message:string, summary:string, typeName:string, blocking:boolean )
	if not m_ready then return; end
	local text:string = CleanTextForSpeech( message );
	if text == "" then text = CleanTextForSpeech( summary ); end
	if text == "" then return; end
	table.insert( m_arrivals, { text = text, time = UI.GetElapsedTime(), spotType = ( typeName == "NOTIFICATION_BARBARIANS_SIGHTED" ) } );
	if m_arrivalTimer < 0 then m_arrivalTimer = 0.8; end		-- flush 0.8 s after the first one: a trickle must not postpone the burst
end

local function FlushArrivals()
	local entries:table = m_arrivals;
	m_arrivals = {};
	local texts:table = {};
	for _, entry in ipairs( entries ) do
		if not ( entry.spotType and math.abs( m_lastSpotSpeech - entry.time ) < 3 ) then table.insert( texts, entry.text ); end
	end
	if #texts == 0 then return; end
	if #texts == 1 then
		OutputMessageToScreenReader( "Notification: " .. texts[1], true );
	else
		OutputMessageToScreenReader( #texts .. " new notifications: " .. KeyNavList_ShortList( texts, 3 ), true );
	end
end

-- ===========================================================================
--	RESULTS of the player's orders and what happens around the player's units
-- ===========================================================================
local function OnUnitOperationStarted( ownerID:number, unitID:number, operationID:number )
	if ownerID ~= Game.GetLocalPlayer() or not m_ready then return; end
	local row:table = GameInfo.UnitOperations[ operationID ];
	if row == nil then return; end
	local text:string = OPERATION_RESULTS[ row.OperationType ];
	if text ~= nil then HubCore.SayResult( text ); end
end

-- Automate Exploration starts no operation event (UnitOperationStarted); the game only adds the operation.
local function OnUnitOperationAdded( ownerID:number, unitID:number, hOperation:number, operationIndex:number )
	if ownerID ~= Game.GetLocalPlayer() or not m_ready then return; end
	local row:table = GameInfo.UnitOperations[ operationIndex ];
	if row ~= nil and row.OperationType == "UNITOPERATION_HEAL" then
		-- Fortify Until Healed only adds the operation (no UnitOperationStarted, like Automate Exploration)
		if UI.GetElapsedTime() - HubCore.m_lastKeyTime <= 2.0 then HubCore.SayResult( OPERATION_RESULTS.UNITOPERATION_HEAL ); end
		return;
	end
	if row == nil or row.OperationType ~= "UNITOPERATION_AUTOMATE_EXPLORE" then return; end
	-- The game also re-adds the operation of units that are already exploring (every turn, after a load): only the
	-- order the player just gave is told. (The old "it has not moved" check after 1 s was dropped: unreliable.)
	if UI.GetElapsedTime() - HubCore.m_lastKeyTime > 2.0 then return; end
	HubCore.SayResult( OPERATION_RESULTS.UNITOPERATION_AUTOMATE_EXPLORE );
end

local function OnUnitCommandStarted( ownerID:number, unitID:number, commandID:number )
	if ownerID ~= Game.GetLocalPlayer() or not m_ready then return; end
	local row:table = GameInfo.UnitCommands[ commandID ];
	if row == nil then return; end
	local text:string = OPERATION_RESULTS[ row.CommandType ];
	if text ~= nil then HubCore.SayResult( text ); end
end

-- The trade choosers hide their contexts (and so stop their update loops) when they close; they ask the hub to tell the
-- outcome a moment later. kind "route": a trade route was requested (unit, origin city owner and id, destination name);
-- kind "move": a trader was moved to another city (unit, plot it left, city name).
local function OnTradeResult( kind:string, unitID:number, a, b, c, d )
	local owner:number = Game.GetLocalPlayer();
	if kind == "route" then
		HubCore.After( 1.0, function()
			local origin:table = CityManager.GetCity( a, b );
			local started:boolean = false;
			if origin ~= nil then
				for _, route in ipairs( origin:GetTrade():GetOutgoingRoutes() ) do
					if route.TraderUnitID == unitID then started = true; end
				end
			end
			if started then
				HubCore.SayResult( "Trade route to " .. c .. " started" );
			else
				HubCore.SayResult( "Trade route to " .. c .. " requested, but the trader has no route yet" );
			end
		end );
	elseif kind == "move" then
		HubCore.After( 0.5, function()
			local unit:table = Players[ owner ]:GetUnits():FindID( unitID );
			if unit ~= nil and ( unit:GetX() ~= a or unit:GetY() ~= b ) then
				HubCore.SayResult( "Trader moved to " .. c );
			else
				HubCore.SayResult( "Trader not moved" );
			end
		end );
	end
end

local function MovesText( unit:table )
	return HubCore.FormatNumber( unit:GetMovesRemaining() ) .. " of " .. HubCore.FormatNumber( unit:GetMaxMoves() ) .. " moves";
end

-- A move ordered with Enter in the move-to mode: arrived, still on the way, or stopped short.
local function OnUnitMoveComplete( playerID:number, unitID:number, x:number, y:number )
	if playerID ~= Game.GetLocalPlayer() then return; end
	local record:table = HubCore.m_movers[ unitID ];
	if record == nil then return; end
	local unit:table = Players[ playerID ]:GetUnits():FindID( unitID );
	if unit == nil then
		HubCore.m_movers[ unitID ] = nil;
		return;
	end
	local plot:table = Map.GetPlot( x, y );
	if plot ~= nil and plot:GetIndex() == record.dest then
		HubCore.m_movers[ unitID ] = nil;
		local text:string = "Arrived, " .. MovesText( unit );
		if HubCore.IsSettler( unit ) then
			local ok:boolean, extra = SettleScan_CanFound( unit, plot );
			if not ok then
				text = text .. ", " .. SettleScan_CannotText( extra );
			elseif extra ~= true then
				text = text .. ", B to found the city";
			else
				text = text .. ", can settle, B to found next turn";
			end
		end
		HubCore.SayResult( text );
		return;
	end
	local queued = UnitManager.GetQueuedDestination( unit );
	if queued == nil then
		HubCore.m_movers[ unitID ] = nil;
		local destPlot:table = Map.GetPlotByIndex( record.dest );
		local text:string = "Stopped";
		if destPlot ~= nil and plot ~= nil then
			text = text .. ", " .. HubCore.Plural( Map.GetPlotDistance( x, y, destPlot:GetX(), destPlot:GetY() ), "tile", "tiles" ) .. " from the destination";
		end
		HubCore.SayResult( text );
		return;
	end
	-- still on the way: only said right after the order (not again every turn of a long move)
	if UI.GetElapsedTime() - ( record.issued or -100 ) > 3 then return; end
	local path:table = UnitManager.GetMoveToPathEx( unit, queued );
	local text:string = "Moving";
	if path ~= nil and path.turns ~= nil and #path.turns > 0 then
		text = text .. ", " .. HubCore.Plural( path.turns[ #path.turns ], "turn", "turns" ) .. " left";
	end
	HubCore.SayResult( text );
end

-- Who fights whom: the game announces a fight (CombatVisBegin) just before the damage events of both sides.
local m_combat:table = nil;

-- Spoken name of one side of a fight (unit or city).
function Hub.CombatSide( data:table )
	if data == nil or data.playerID == nil or data.playerID < 0 or Players[ data.playerID ] == nil then return nil; end
	local player:table = Players[ data.playerID ];
	local side:table = { player = data.playerID, id = data.componentID };
	if data.componentType == ComponentType.UNIT then
		local unit:table = player:GetUnits():FindID( data.componentID );
		if unit == nil then return nil; end
		side.name = PlotDescription_GetUnitName( unit );
		side.short = Locale.Lookup( unit:GetName() );
		side.x, side.y = unit:GetX(), unit:GetY();
		-- never name a unit the player cannot see (or an unmet civ behind it)
		if data.playerID ~= Game.GetLocalPlayer() and not ( HubCore.IsPlotVisibleToLocal( Map.GetPlot( side.x, side.y ) ) and PlotDescription_IsUnitVisible( unit ) ) then
			side.name, side.short, side.unseen = "An unseen unit", "The unseen unit", true;
		end
	else
		local city:table = nil;
		if data.componentType == ComponentType.DISTRICT then
			local district:table = player:GetDistricts():FindID( data.componentID );
			if district == nil then return nil; end
			city = district:GetCity();
			if city == nil then return nil; end
			side.x, side.y = district:GetX(), district:GetY();
		elseif data.componentType == ComponentType.CITY then
			city = player:GetCities():FindID( data.componentID );
			if city == nil then return nil; end
			side.x, side.y = city:GetX(), city:GetY();
		else
			return nil;
		end
		side.name = Locale.Lookup( city:GetName() );
		side.short = side.name;
	end
	if data.playerID == Game.GetLocalPlayer() and not side.unseen then side.name = "Your " .. side.name; end
	return side;
end

function Hub.OnCombatVisBegin( data:table )
	m_combat = nil;
	if not m_ready or data == nil then return; end
	local attacker:table, defender:table = Hub.CombatSide( data[ CombatVisType.ATTACKER ] ), Hub.CombatSide( data[ CombatVisType.DEFENDER ] );
	if attacker == nil or defender == nil then return; end
	m_combat = { attacker = attacker, defender = defender, time = UI.GetElapsedTime(), told = false };
end

-- "3 tiles north-east of Rome": where a plot is, seen from the nearest own city (else the selected unit).
function Hub.PlaceFromOwn( x:number, y:number )
	local localPlayer:number = Game.GetLocalPlayer();
	local bestDistance:number, bestName:string, bestPlot:table = 99, nil, nil;
	for _, city in Players[ localPlayer ]:GetCities():Members() do
		local distance:number = Map.GetPlotDistance( x, y, city:GetX(), city:GetY() );
		if distance < bestDistance then
			bestDistance, bestName, bestPlot = distance, Locale.Lookup( city:GetName() ), Map.GetPlot( city:GetX(), city:GetY() );
		end
	end
	if bestName == nil then
		local selected:table = UI.GetHeadSelectedUnit();
		if selected ~= nil and selected:GetOwner() == localPlayer then
			bestName, bestPlot = "your " .. Locale.Lookup( selected:GetName() ), Map.GetPlot( selected:GetX(), selected:GetY() );
		end
	end
	if bestName == nil then return nil; end
	local relative:string = PlotDescription_GetRelative( bestPlot, Map.GetPlot( x, y ) );
	if relative == nil then return "at " .. bestName; end
	return relative .. " of " .. bestName;
end

function Hub.OnUnitDamageChanged( playerID:number, unitID:number, newDamage:number, oldDamage:number )
	if not m_ready or newDamage <= oldDamage then return; end
	local player:table = Players[ playerID ];
	if player == nil then return; end
	local unit:table = player:GetUnits():FindID( unitID );
	if unit == nil then return; end
	if not HubCore.IsPlotVisibleToLocal( Map.GetPlot( unit:GetX(), unit:GetY() ) ) or not PlotDescription_IsUnitVisible( unit ) then return; end
	HubCore.RememberUnit( unit );
	-- only fights that concern the player: their own units, or anything close to their units and cities
	if playerID ~= Game.GetLocalPlayer() and not HubCore.IsNearLocal( unit:GetX(), unit:GetY(), 3 ) then return; end
	local name:string = PlotDescription_GetUnitName( unit );
	if playerID == Game.GetLocalPlayer() then name = "Your " .. name; end
	local maxDamage:number = unit:GetMaxDamage();
	if newDamage >= maxDamage then return; end		-- H.OnUnitKilledInCombat tells it
	local text:string = name .. " takes " .. ( newDamage - oldDamage ) .. " damage, " .. ( maxDamage - newDamage ) .. " of " .. maxDamage .. " left";
	-- the first damage line of a fight says who attacked whom (and where, when it is not our fight)
	local fight:table = m_combat;
	if fight ~= nil and not fight.told and UI.GetElapsedTime() - fight.time < 10
			and ( ( fight.attacker.player == playerID and fight.attacker.id == unitID ) or ( fight.defender.player == playerID and fight.defender.id == unitID ) ) then
		fight.told = true;
		local localPlayer:number = Game.GetLocalPlayer();
		local ours:boolean = fight.attacker.player == localPlayer or fight.defender.player == localPlayer;
		local victim:table = ( fight.defender.player == playerID and fight.defender.id == unitID ) and fight.defender or fight.attacker;
		local who:string = ( victim.player == localPlayer ) and victim.name or victim.short;
		local place:string = nil;
		if not ours then place = Hub.PlaceFromOwn( fight.defender.x, fight.defender.y ); end
		text = fight.attacker.name .. " attacks " .. fight.defender.name .. ( place ~= nil and ( ", " .. place ) or "" ) .. ": "
			.. who .. " takes " .. ( newDamage - oldDamage ) .. " damage, " .. ( maxDamage - newDamage ) .. " of " .. maxDamage .. " left";
	end
	OutputMessageToScreenReader( text, true );
	LuaEvents.SRA_CombatSpoken();		-- StatusMessagePanel drops its duplicate of this fight
end

-- (killed player, killed unit, killer player, killer unit): told when the local player is on either side.
function Hub.OnUnitKilledInCombat( killedPlayer:number, killedId:number, killerPlayer:number, killerId:number )
	if not m_ready then return; end
	local localPlayer:number = Game.GetLocalPlayer();
	if killedPlayer ~= localPlayer and killerPlayer ~= localPlayer then return; end
	local function NameOf( playerID:number, unitID:number )
		local player:table = Players[ playerID ];
		local unit:table = ( player ~= nil ) and player:GetUnits():FindID( unitID ) or nil;
		if unit ~= nil then return PlotDescription_GetUnitName( unit ); end
		-- the unit is gone by now: the name remembered while it was alive
		return HubCore.m_unitNames[ playerID .. ":" .. unitID ];
	end
	local killed:string = NameOf( killedPlayer, killedId ) or "unit";
	local killer:string = NameOf( killerPlayer, killerId );
	local text:string;
	if killedPlayer == localPlayer then
		text = "Your " .. killed .. " was killed";
	else
		text = killed .. " killed";
	end
	if killer ~= nil then
		if killerPlayer == localPlayer then killer = "your " .. killer; end
		text = text .. " by " .. killer;
	end
	OutputMessageToScreenReader( text, true );
	LuaEvents.SRA_CombatSpoken();		-- StatusMessagePanel drops its duplicate of this fight
end

function Hub.OnCityAddedToMap( ownerID:number, cityID:number, x:number, y:number )
	if ownerID ~= Game.GetLocalPlayer() or not m_ready then return; end
	local city:table = Players[ ownerID ]:GetCities():FindID( cityID );
	local name:string = ( city ~= nil ) and Locale.Lookup( city:GetName() ) or "City";
	HubCore.SayResult( name .. " founded" );
end

-- A builder finished an improvement on its own plot.
function Hub.OnImprovementAddedToMap( x:number, y:number, improvementType:number, owner:number )
	if owner ~= Game.GetLocalPlayer() or not m_ready then return; end
	local unit:table = UI.GetHeadSelectedUnit();
	if unit == nil or unit:GetX() ~= x or unit:GetY() ~= y then return; end
	local row:table = GameInfo.Improvements[ improvementType ];
	if row == nil then return; end
	local name:string = Locale.Lookup( row.Name );
	local unitID:number = unit:GetID();
	HubCore.After( 0.4, function()	-- the charges are counted down a moment later
		local builder:table = Players[ owner ]:GetUnits():FindID( unitID );
		local text:string = name .. " built";
		if builder ~= nil then
			text = text .. ", " .. HubCore.Plural( builder:GetBuildCharges(), "charge", "charges" ) .. " left";
		else
			text = text .. ", the builder is used up";
		end
		HubCore.SayResult( text );
	end );
end

-- "Barbarian Warrior spotted, 2 tiles north of Rome": hostile soldiers that come into view near our cities and units.
function Hub.OnUnitVisibilityChanged( playerID:number, unitID:number, visibility:number )
	local localPlayer:number = Game.GetLocalPlayer();
	if not m_ready or playerID == localPlayer or visibility ~= RevealedState.VISIBLE or not HubCore.IsHostile( playerID ) then return; end
	local unit:table = Players[ playerID ]:GetUnits():FindID( unitID );
	if unit == nil or ( unit:GetCombat() <= 0 and unit:GetRangedCombat() <= 0 ) then return; end
	if not PlotDescription_IsUnitVisible( unit ) then return; end
	HubCore.RememberUnit( unit );
	local turn:number = Game.GetCurrentGameTurn();
	local key:string = playerID .. ":" .. unitID;
	if m_spotted[ key ] ~= nil and turn - m_spotted[ key ] < 10 then return; end
	if m_spottedTurn ~= turn then m_spottedTurn = turn; m_spottedCount = 0; end
	if m_spottedCount >= 4 then return; end
	local x:number, y:number = unit:GetX(), unit:GetY();
	local bestDistance:number, bestName:string, bestPlot:table = 99, nil, nil;
	for _, city in Players[ localPlayer ]:GetCities():Members() do
		local distance:number = Map.GetPlotDistance( x, y, city:GetX(), city:GetY() );
		if distance < bestDistance then
			bestDistance, bestName, bestPlot = distance, Locale.Lookup( city:GetName() ), Map.GetPlot( city:GetX(), city:GetY() );
		end
	end
	for _, mine in Players[ localPlayer ]:GetUnits():Members() do
		local distance:number = Map.GetPlotDistance( x, y, mine:GetX(), mine:GetY() );
		if distance < bestDistance then
			bestDistance, bestName, bestPlot = distance, "your " .. Locale.Lookup( mine:GetName() ), Map.GetPlot( mine:GetX(), mine:GetY() );
		end
	end
	if bestName == nil or bestDistance > 4 then return; end
	m_spotted[ key ] = turn;
	m_spottedCount = m_spottedCount + 1;
	local relative:string = PlotDescription_GetRelative( bestPlot, Map.GetPlot( x, y ) );
	local text:string = PlotDescription_GetUnitName( unit ) .. " spotted";
	if relative ~= nil then text = text .. ", " .. relative .. " of " .. bestName; else text = text .. " at " .. bestName; end
	m_lastSpotSpeech = UI.GetElapsedTime();
	OutputMessageToScreenReader( text, true );
end

-- ===========================================================================
--	ENTER (Next Action) must always say something
-- ===========================================================================
function Hub.IsGovernorLabel()
	local label:table = ContextPtr:LookUpControl( "/InGame/HUD/ActionPanel/EndTurnText" );
	local text:string = ( label ~= nil ) and label:GetText() or "";
	for _, key in ipairs( { "LOC_ACTION_PANEL_GOVERNOR_APPOINTMENT", "LOC_ACTION_PANEL_GOVERNOR_OPPORTUNITY", "LOC_ACTION_PANEL_GOVERNOR_PROMOTION", "LOC_ACTION_PANEL_GOVERNOR_IDLE" } ) do
		if text == Locale.Lookup( key ) then print( "InGameAccess: Enter held back, end-turn label '" .. text .. "' right after an attack" ); return true; end
	end
	return false;
end

function Hub.IsUnitOrdersLabel( text:string )
	return text == Locale.Lookup( "LOC_ACTION_PANEL_NEEDS_ORDERS" ) or text == Locale.Lookup( "LOC_ACTION_PANEL_STACKED_UNIT" )
		or text == Locale.Lookup( "LOC_ACTION_PANEL_UNIT_MOVES_REMAINING" );
end

function Hub.ArmEnterWatch()
	local label:table = ContextPtr:LookUpControl( "/InGame/HUD/ActionPanel/EndTurnText" );
	m_enterLabel = ( label ~= nil ) and label:GetText() or "";
	HubCore.m_enterWatch = 0.8;
end

-- Enter was pressed, nothing announced a new selection, turn end or mode: the game re-selected the same unit
-- (or none could be selected). Say what is going on.
function Hub.EnterFallback()
	if not Hub.IsUnitOrdersLabel( m_enterLabel ) then return; end
	local unit:table = UI.GetHeadSelectedUnit();
	if unit ~= nil then
		local text:string = UnitText( unit ) .. ", needs orders. Tab for its actions";
		-- a unit the game lets neither skip nor sleep (UnitPanel adds a disabled Skip Turn entry with the reason)
		local okHint:boolean, hint = pcall( function()
			for _, item in ipairs( FetchMenuItems( false ) ) do
				if item.action.typeName == "UNITOPERATION_SKIP_TURN" and item.action.disabled then return item.action.reason; end
			end
			return nil;
		end );
		if okHint and hint ~= nil and hint ~= "" then text = text .. ". Cannot skip: " .. hint; end
		HubCore.SayResult( text );
	else
		HubCore.SayResult( HubCore.Capitalize( CleanTextForSpeech( m_enterLabel ) ) );
	end
end

-- ===========================================================================
--	INPUT HANDLER: runs before WorldInput and ActionPanel (see docs/ingame-plan.md, Input order)
-- ===========================================================================
function Hub.HandleInput( input:table )
	if not HubCore.IsLocalPlayerActive() then return false; end
	local msg:number = input:GetMessageType();
	if msg ~= KeyEvents.KeyDown and msg ~= KeyEvents.KeyUp then return false; end
	HubCore.m_lastKeyTime = UI.GetElapsedTime();
	if HubCore.m_mode ~= nil then return HubCore.m_mode.list.HandleInput( input ); end
	if input:IsShiftDown() or input:IsControlDown() or input:IsAltDown() then return false; end
	local key:number = input:GetKey();
	if HubTargets.GetTargetMode() ~= nil then
		-- Enter and Escape belong to the mode; both KeyDown and KeyUp are consumed, so ActionPanel never sees Enter
		if UI.GetHeadSelectedUnit() == nil and UI.GetHeadSelectedCity() == nil then
			HubTargets.ResetStaleMode();		-- nothing left to act: the keys go to the game again
			return false;
		end
		if key == Keys.VK_RETURN or key == Keys.VK_ESCAPE then
			-- consumed even when the handler fails, so that Enter never falls through to Next Action mid-mode
			if msg == KeyEvents.KeyUp then
				local ok:boolean, err = xpcall( function() if key == Keys.VK_RETURN then HubTargets.ConfirmTarget(); else HubTargets.CancelTarget(); end end, KeyNavErrorHandler );
				if not ok then
					print( "InGameAccess target mode error: " .. tostring( err ) );
					OutputMessageToScreenReader( "Something went wrong, Escape to cancel" );
				end
			end
			return true;
		end
		return false;
	end
	-- Just after an attack the end-turn label can flash a governor blocker; Enter would open the Governors screen
	if key == Keys.VK_RETURN and UI.GetElapsedTime() - HubTargets.attackTime < 5 and Hub.IsGovernorLabel() then
		if msg == KeyEvents.KeyUp then HubCore.SayResult( "The attack is still resolving, press Enter again in a moment" ); end
		return true;
	end
	if key == Keys.VK_RETURN and msg == KeyEvents.KeyUp and not HubCore.IsGamePopupOpen() then Hub.ArmEnterWatch(); end		-- an open screen (City-States, governors) takes Enter itself
	return false;
end

function Hub.OnInput( input:table )
	local ok:boolean, consumed = xpcall( function() return Hub.HandleInput( input ); end, KeyNavErrorHandler );
	if not ok then
		print( "InGameAccess input error: " .. tostring( consumed ) );
		return false;
	end
	return consumed == true;
end

function Hub.OnUpdate( deltaTime:number )
	HubCursor.UpdateMouse( deltaTime );
	if m_arrivalTimer >= 0 then
		m_arrivalTimer = m_arrivalTimer - deltaTime;
		if m_arrivalTimer < 0 then
			m_arrivalTimer = -1;
			local ok:boolean, err = xpcall( FlushArrivals, KeyNavErrorHandler );
			if not ok then print( "InGameAccess FlushArrivals error: " .. tostring(err) ); end
		end
	end
	local i:number = 1;
	while i <= #HubCore.m_delayed do
		local entry:table = HubCore.m_delayed[i];
		entry.time = entry.time - deltaTime;
		if entry.time <= 0 then
			table.remove( HubCore.m_delayed, i );
			local ok:boolean, err = xpcall( entry.fn, KeyNavErrorHandler );
			if not ok then print( "InGameAccess delayed call error: " .. tostring( err ) ); end
		else
			i = i + 1;
		end
	end
	if HubCore.m_enterWatch >= 0 then
		HubCore.m_enterWatch = HubCore.m_enterWatch - deltaTime;
		if HubCore.m_enterWatch < 0 then
			HubCore.m_enterWatch = -1;
			Hub.EnterFallback();
		end
	end
end

-- ===========================================================================
--	INPUT ACTIONS
-- ===========================================================================
function Hub.OnInputActionTriggered( actionId:number )
	local handler = m_actions[ actionId ];
	if handler ~= nil then handler(); end
end

function Hub.RegisterAction( name:string, handler )
	local id:number = Input.GetActionId( name );
	if id == nil then
		print( "InGameAccess: unknown input action " .. name );
		return;
	end
	m_actions[ id ] = HubCore.Safe( name, handler );
end

-- Hub modules (Accessibility/Hub*.lua), see docs/ingame-plan.md
include( "HubCore" );
include( "HubCursor" );
include( "HubTargets" );

-- ===========================================================================
function Initialize()
	-- Contexts added with AddUserInterfaces start hidden, and a hidden context gets no input actions or updates.
	ContextPtr:SetHide( false );

	-- A hot reload (civctl deploy) happens in the middle of a game: LoadScreenClose will not come again, so the hub would
	-- stay "not ready" (no event announcements) with a fresh state. Start it as it would be after the load, without
	-- repeating the turn announcement.
	if ContextPtr:IsHotLoad() and HubCore.IsLocalPlayerActive() then
		m_ready = true;
		HubCore.m_cursorPlayer = Game.GetLocalPlayer();
		m_lastAnnouncedTurn = Game.GetLocalPlayer() .. ":" .. Game.GetCurrentGameTurn();
		for _, unit in Players[ Game.GetLocalPlayer() ]:GetUnits():Members() do HubCore.RememberUnit( unit ); end
	end

	Hub.RegisterAction( "KeyNavMoveCellLeft",		function() HubCursor.MoveCursor( -1, 0 ); end );
	Hub.RegisterAction( "KeyNavMoveCellRight",		function() HubCursor.MoveCursor( 1, 0 ); end );
	Hub.RegisterAction( "KeyNavMoveCellUp",			function() HubCursor.MoveCursor( 0, 1 ); end );
	Hub.RegisterAction( "KeyNavMoveCellDown",		function() HubCursor.MoveCursor( 0, -1 ); end );
	Hub.RegisterAction( "KeyNavPlotDetails",		HubCursor.SpeakPlotDetails );
	Hub.RegisterAction( "KeyNavCursorToSelection",	HubCursor.CursorToSelection );
	Hub.RegisterAction( "KeyNavWhatsNext",			SpeakWhatsNext );
	Hub.RegisterAction( "KeyNavUnitActions",		ToggleUnitMenu );
	Hub.RegisterAction( "KeyNavSelectAtCursor",		HubCursor.SelectAtCursor );
	Hub.RegisterAction( "KeyNavCycleAllUnits",		HubCursor.CycleAllUnits );
	Hub.RegisterAction( "KeyNavScanUnits",			ScanKey );
	Hub.RegisterAction( "KeyNavDiplomacy",			ToggleCivMenu );
	Hub.RegisterAction( "KeyNavTopPanel",			ToggleTopPanel );
	Hub.RegisterAction( "KeyNavNotifications",		ToggleNotifications );
	Hub.RegisterAction( "KeyNavYields",				SpeakYields );
	Hub.RegisterAction( "KeyNavCityReport",			ToggleCityReport );
	Hub.RegisterAction( "KeyNavReports",			HubTargets.ToggleReports );
	Hub.RegisterAction( "RangedAttack",			HubTargets.CityAttackKey );		-- R and W with a city selected: UnitPanel is hidden and silent
	Hub.RegisterAction( "Attack",					HubTargets.CityAttackKey );
	HubCore.Listen( Events.InputActionTriggered, Hub.OnInputActionTriggered );

	HubCore.Listen( Events.UnitSelectionChanged, HubCore.Safe( "UnitSelectionChanged", OnUnitSelectionChanged ) );
	HubCore.Listen( Events.CitySelectionChanged, HubCore.Safe( "CitySelectionChanged", OnCitySelectionChanged ) );
	HubCore.Listen( Events.LocalPlayerTurnBegin, HubCore.Safe( "LocalPlayerTurnBegin", AnnounceTurn ) );
	HubCore.Listen( Events.LoadScreenClose, HubCore.Safe( "LoadScreenClose", OnLoadScreenClose ) );
	HubCore.Listen( Events.LocalPlayerTurnEnd, HubCore.Safe( "LocalPlayerTurnEnd", OnLocalPlayerTurnEnd ) );

	HubCore.AddEvent( "InterfaceModeChanged",		HubTargets.OnInterfaceModeChanged );
	HubCore.AddEvent( "UnitOperationStarted",		OnUnitOperationStarted );
	HubCore.AddEvent( "UnitOperationAdded",			OnUnitOperationAdded );
	HubCore.AddEvent( "UnitCommandStarted",			OnUnitCommandStarted );
	HubCore.AddEvent( "UnitMoveComplete",			OnUnitMoveComplete );
	HubCore.AddEvent( "CombatVisBegin",				Hub.OnCombatVisBegin );
	HubCore.AddEvent( "UnitDamageChanged",			Hub.OnUnitDamageChanged );
	HubCore.AddEvent( "CityAddedToMap",				Hub.OnCityAddedToMap );
	HubCore.AddEvent( "ImprovementAddedToMap",		Hub.OnImprovementAddedToMap );
	HubCore.AddEvent( "UnitVisibilityChanged",		Hub.OnUnitVisibilityChanged );
	-- "Promoted: X" is spoken by the UnitPromotionPopup override (the only keyboard way to promote)
	HubCore.AddEvent( "UnitUpgraded",				function( player:number, unitID:number, unitType:number )
		local row:table = GameInfo.Units[ unitType ];
		if player == Game.GetLocalPlayer() and m_ready and row ~= nil then HubCore.SayResult( "Upgraded to " .. Locale.Lookup( row.Name ) ); end
	end );
	HubCore.AddEvent( "UnitKilledInCombat",			Hub.OnUnitKilledInCombat );
	HubCore.Listen( LuaEvents.SRA_UnitActions, OnUnitActionsReceived );
	HubCore.Listen( LuaEvents.SRA_Notifications, OnNotificationsReceived );
	HubCore.Listen( LuaEvents.SRA_NotificationAdded, HubCore.Safe( "NotificationAdded", OnNotificationAdded ) );
	HubCore.Listen( LuaEvents.SRA_NotificationActivated, HubCore.Safe( "NotificationActivated", OnNotificationActivated ) );
	HubCore.Listen( LuaEvents.SRA_AttackKey, HubCore.Safe( "AttackKey", HubTargets.AttackKey ) );
	HubCore.Listen( LuaEvents.SRA_TradeResult, HubCore.Safe( "TradeResult", OnTradeResult ) );		-- trade choosers: outcome of the route / move
	HubCore.Listen( LuaEvents.SRA_CursorTo, HubCore.Safe( "CursorTo", function( x:number, y:number ) HubCursor.SetCursor( x, y, false, false, true ); end ) );		-- City-States screen: Show on map
	HubCore.AddEvent( "UnitRemovedFromMap",			function() HubCore.After( 0.3, HubTargets.ResetStaleMode ); end );
	HubCore.AddEvent( "UnitAddedToMap",				function( playerID:number, unitID:number )
		local player:table = Players[ playerID ];
		if player ~= nil then HubCore.RememberUnit( player:GetUnits():FindID( unitID ) ); end
	end );

	ContextPtr:SetInputHandler( Hub.OnInput, true );
	ContextPtr:SetUpdate( HubCore.Safe( "Update", Hub.OnUpdate ) );
	ContextPtr:SetShutdown( HubCore.OnShutdown );
end
Initialize();
