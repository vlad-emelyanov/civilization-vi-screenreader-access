-- ===========================================================================
--	HubCore: shared helpers, state and the keyboard mode plumbing (OpenMode/CloseMode).
--	Part of the InGameAccess hub (see docs/ingame-plan.md, Architecture): included by
--	UI/Additions/InGameAccess.lua. State and functions other hub modules use are fields of HubCore.
-- ===========================================================================
HubCore = {};

HubCore.m_lastAnnouncedTurn = "";		-- "<local player>:<turn>" of the last turn announcement (hotseat: every player hears their turn)
HubCore.m_cursorPlayer = -1;		-- local player the cursor belongs to
HubCore.m_ready = false;	-- a game is loaded (LoadScreenClose seen): event announcements are allowed
HubCore.m_mode = nil;		-- the active keyboard mode { name, list, onClose }, see MODES below; nil: none
HubCore.m_delayed = {};		-- { time = seconds left, fn = function }
HubCore.m_enterWatch = -1;		-- >= 0: Enter (Next Action) was pressed; seconds until we check that something was said
HubCore.m_placeCommitTime = -100;		-- UI.GetElapsedTime() of the last placement commit (its result must outlive the selection that follows)
HubCore.m_lastResultTime = -100;		-- UI.GetElapsedTime() of the last announced result of a player's action
HubCore.m_repeatTurnLine = nil;		-- { turn, since, quiet } once the turn-start congress results popup closed: say the turn-start line again (HubAnnounce.RepeatTurnStartLine) after 0.5 s without popup
HubCore.m_turnBegin = { time = -1000, turn = -1 };		-- UI.GetElapsedTime() and game turn when the local player's turn became active
HubCore.m_movers = {};		-- unit id -> { dest = plot index, issued = time }: units on a move order given in this session
HubCore.m_lastKeyTime = -100;		-- UI.GetElapsedTime() of the last key press seen by the input handler
HubCore.m_unitNames = {};		-- "player:unit" -> spoken name, remembered while the unit is alive (it is gone when its death is reported)
HubCore.m_spotted = {};		-- "player:unit" -> turn the enemy was last announced
HubCore.m_arrivals = {};		-- texts of notifications that arrived and are not yet announced
HubCore.m_arrivalTimer = -1;		-- >= 0: seconds until the arrivals are announced together
HubCore.m_lastSelectionSpeech = -100;		-- UI.GetElapsedTime() of the last unit/city selection announcement
HubCore.m_placeConfirm = nil;		-- plot index the placement browser asked "Enter to confirm" for
HubCore.m_placeReplaced = false;	-- the placement mode is closing because another placement mode replaced it
HubCore.m_speech = { holds = {}, queue = {}, recent = {}, releaseTimer = -1, watch = 0 };		-- speech hold, see HubCore.Announce
-- PlacementPlotText: defined with the placement browser: what the cursor plot means there

-- ===========================================================================
--	HELPERS
-- ===========================================================================

-- Runs f, printing any error instead of silently losing it. The error handler is captured at load: after a hot reload a
-- stale instance must not look the global up again (it is gone there) and fail with a second error.
local m_errorHandler = KeyNavErrorHandler;
function HubCore.Safe( name:string, f )
	return function( ... )
		local count:number = select( "#", ... );
		local args:table = { ... };
		local ok:boolean, err = xpcall( function() return f( unpack(args, 1, count) ); end, m_errorHandler or tostring );
		if not ok then print( "InGameAccess " .. name .. " error: " .. tostring(err) ); end
	end
end

-- Every Events.* / LuaEvents.* listener goes through Listen, so OnShutdown can remove them all. Listeners of a context
-- that was hot reloaded would otherwise survive in the engine, fire in a dead environment and run next to the new ones.
local m_listeners:table = {};
function HubCore.Listen( event, fn )
	event.Add( fn );
	table.insert( m_listeners, { event = event, fn = fn } );
end

function HubCore.OnShutdown()
	print( "InGameAccess: shutdown, removing " .. #m_listeners .. " listeners" );
	for _, l in ipairs( m_listeners ) do l.event.Remove( l.fn ); end
	m_listeners = {};
end

function HubCore.Capitalize( text:string )
	text = string.lower( text );
	return string.upper( string.sub(text, 1, 1) ) .. string.sub( text, 2 );
end

function HubCore.IsLocalPlayerActive()
	local localPlayer:number = Game.GetLocalPlayer();
	return localPlayer ~= nil and localPlayer ~= -1 and Players[localPlayer] ~= nil;
end

-- The selected unit or city: what "relative to me" refers to.
function HubCore.GetSelectionPlot()
	local unit:table = UI.GetHeadSelectedUnit();
	if unit ~= nil then return Map.GetPlot( unit:GetX(), unit:GetY() ), unit; end
	local city:table = UI.GetHeadSelectedCity();
	if city ~= nil then return Map.GetPlot( city:GetX(), city:GetY() ), nil; end
	return nil, nil;
end

function HubCore.FormatNumber( value:number )
	return tostring( math.floor( value * 10 + 0.5 ) / 10 );
end

-- Is one of the game's popups or screens open (the options menu included)? Contexts that are always shown are skipped.
local ALWAYS_SHOWN:table = { TopPanel = true, DiplomacyRibbon = true, PartialScreenHooks = true, InGameAccess = true };

function HubCore.IsGamePopupOpen()
	local menu = ContextPtr:LookUpControl( "/InGame/TopOptionsMenu" );
	if menu ~= nil and not menu:IsHidden() then return true; end
	for _, name in ipairs( { "WorldPopups", "FakePopups", "Screens", "PartialScreens", "Diplomacy", "EndGame" } ) do
		local parent = ContextPtr:LookUpControl( "/InGame/" .. name );
		if parent ~= nil then
			for _, child in ipairs( parent:GetChildren() ) do
				if not child:IsHidden() and not ALWAYS_SHOWN[ child:GetID() ] then return true; end
			end
		end
	end
	-- Gathering Storm popups added straight to the InGame context (not under a container)
	for _, name in ipairs( { "EraReviewPopup", "DedicationPopup", "WorldCongressPopup", "WorldCongressIntro", "WorldCongressBetweenTurns" } ) do
		local popup = ContextPtr:LookUpControl( "/InGame/" .. name );
		if popup ~= nil and not popup:IsHidden() then return true; end
	end
	return false;
end

-- ===========================================================================
--	TEST HARNESS (util/civregress.py): between two regression scripts on one loaded fixture. TestResetState says whether the
--	game is back in the state a fresh load gives and puts the cheap state (map cursor, selection) back. It never changes
--	game state (no orders, no turn); anything it cannot restore is reported as "dirty <reason>" and the next script loads fresh.
-- ===========================================================================
local TEST_SCREEN_PARENTS:table = { "WorldPopups", "FakePopups", "Screens", "PartialScreens", "Diplomacy", "EndGame", "AdditionalUserInterfaces" };
local TEST_SCREEN_SINGLES:table = { "Civilopedia", "EraReviewPopup", "DedicationPopup", "WorldCongressPopup", "WorldCongressIntro", "WorldCongressBetweenTurns", "AdvisorPopup" };

-- The names of the open popups and screens (the options menu included), empty when none.
function HubCore.TestOpenScreens()
	local open:table = {};
	local menu = ContextPtr:LookUpControl( "/InGame/TopOptionsMenu" );
	if menu ~= nil and not menu:IsHidden() then table.insert( open, "TopOptionsMenu" ); end
	for _, name in ipairs( TEST_SCREEN_PARENTS ) do
		local parent = ContextPtr:LookUpControl( "/InGame/" .. name );
		if parent ~= nil then
			for _, child in ipairs( parent:GetChildren() ) do
				if not child:IsHidden() and not ALWAYS_SHOWN[ child:GetID() ] then table.insert( open, name .. "/" .. child:GetID() ); end
			end
		end
	end
	for _, name in ipairs( TEST_SCREEN_SINGLES ) do
		for _, path in ipairs( { "/InGame/" .. name, "/InGame/Popups/" .. name, "/TutorialUIRoot/" .. name } ) do
			local c = ContextPtr:LookUpControl( path );
			if c ~= nil and not c:IsHidden() then table.insert( open, name ); break; end
		end
	end
	return open;
end

local function TestSelectionTag()
	local unit:table = UI.GetHeadSelectedUnit();
	if unit ~= nil then return "u:" .. unit:GetID(); end
	local city:table = UI.GetHeadSelectedCity();
	if city ~= nil then return "c:" .. city:GetID(); end
	return "none";
end

-- "t=<turn>;g=<gold>;u=<units>;c=<cities>" (what a script that only browses leaves untouched) and the selection tag.
local function TestSnapshot()
	local id:number = Game.GetLocalPlayer();
	local player:table = Players[ id ];
	-- h=: hash of every unit (id, plot, moves, damage, activity), every city (id, production), research, civic and policy slots
	local parts:table = {};
	for _, unit in player:GetUnits():Members() do
		table.insert( parts, "u" .. unit:GetID() .. "," .. unit:GetX() .. "," .. unit:GetY() .. "," .. unit:GetMovesRemaining()
			.. "," .. unit:GetDamage() .. "," .. tostring( UnitManager.GetActivityType( unit ) ) );
	end
	for _, city in player:GetCities():Members() do
		table.insert( parts, "c" .. city:GetID() .. "," .. tostring( city:GetBuildQueue():GetCurrentProductionTypeHash() ) );
	end
	table.insert( parts, "r" .. tostring( player:GetTechs():GetResearchingTech() ) );
	local culture:table = player:GetCulture();
	table.insert( parts, "v" .. tostring( culture:GetProgressingCivic() ) );
	local ok:boolean, slots = pcall( function()
		local list:table = {};
		for i = 0, ( culture:GetNumPolicySlots() or 0 ) - 1 do table.insert( list, tostring( culture:GetSlotPolicy( i ) ) ); end
		return table.concat( list, "," );
	end );
	table.insert( parts, "p" .. ( ok and slots or "?" ) );
	-- government and founded religion: a script that adopts or founds one makes the next script load fresh
	local okGov:boolean, gov = pcall( function() return tostring( culture:GetCurrentGovernment() ) .. "/" .. tostring( player:GetReligion():GetReligionTypeCreated() ); end );
	table.insert( parts, "g" .. ( okGov and gov or "?" ) );
	local text:string, hash:number = table.concat( parts, ";" ), 17;
	for i = 1, #text do hash = ( hash * 31 + string.byte( text, i ) ) % 2147483629; end
	return "t=" .. Game.GetCurrentGameTurn() .. ";g=" .. math.floor( player:GetTreasury():GetGoldBalance() )
		.. ";u=" .. player:GetUnits():GetCount() .. ";c=" .. player:GetCities():GetCount() .. ";h=" .. hash;
end

-- Why the game is not in plain map mode, or nil.
function HubCore.TestDirtyReason()
	if not HubCore.IsLocalPlayerActive() then return "no local player"; end
	if not HubCore.m_ready then return "hub not ready (no game loaded)"; end
	if not Players[ Game.GetLocalPlayer() ]:IsTurnActive() then return "not our turn"; end
	local open:table = HubCore.TestOpenScreens();
	if #open > 0 then return "open: " .. table.concat( open, ", " ); end
	if HubCore.m_mode ~= nil then return "hub mode " .. tostring( HubCore.m_mode.name ); end
	if UI.GetInterfaceMode() ~= InterfaceModeTypes.SELECTION then return "interface mode " .. tostring( UI.GetInterfaceMode() ); end
	if #HubCore.m_delayed > 0 then return "pending delayed calls"; end
	if #HubCore.m_arrivals > 0 or HubCore.m_arrivalTimer >= 0 then return "pending arrival announcements"; end
	if next( HubCore.m_movers ) ~= nil then return "pending move orders"; end
	if HubCore.m_enterWatch >= 0 then return "Enter watch pending"; end
	return nil;
end

-- The snapshot and selection of a game as it is (no checks, nothing changed): the baseline TestResetState compares with.
function HubCore.TestSnapshotText()
	local ok:boolean, result = xpcall( function() return "snap " .. TestSnapshot() .. "|" .. TestSelectionTag(); end, KeyNavErrorHandler or tostring );
	if not ok then return "dirty error: " .. tostring( result ); end
	return result;
end

-- baseline: nil to just look, or the text a previous call returned after "clean " (taken right after a load). Returns
-- "clean <snapshot>|<selection>" or "dirty <reason>". Puts the map cursor and the selection back when it is clean.
local function TestResetStateInner( baseline )
	local reason:string = HubCore.TestDirtyReason();
	if reason ~= nil then return "dirty " .. reason; end
	local snapshot:string = TestSnapshot();
	if baseline ~= nil then
		local baseSnapshot:string, baseSel:string = string.match( baseline, "^(.*)|(.*)$" );
		if baseSnapshot ~= snapshot then return "dirty changed: " .. snapshot .. " (was " .. tostring( baseSnapshot ) .. ")"; end
		if TestSelectionTag() ~= baseSel then
			if UI.DeselectAll ~= nil then UI.DeselectAll(); else UI.DeselectAllUnits(); UI.DeselectAllCities(); end
			local kind:string, objectId:string = string.match( baseSel, "^(%a):(%d+)$" );
			local player:table = Players[ Game.GetLocalPlayer() ];
			if kind == "u" then
				local unit:table = player:GetUnits():FindID( tonumber( objectId ) );
				if unit ~= nil then UI.SelectUnit( unit ); end
			elseif kind == "c" then
				local city:table = player:GetCities():FindID( tonumber( objectId ) );
				if city ~= nil then UI.SelectCity( city ); end
			end
			if TestSelectionTag() ~= baseSel then return "dirty selection " .. TestSelectionTag() .. " not restored to " .. baseSel; end
		end
	end
	HubCursor.ResetCursor();
	return "clean " .. snapshot .. "|" .. TestSelectionTag();
end

function HubCore.TestResetState( baseline )
	local ok:boolean, result = xpcall( function() return TestResetStateInner( baseline ); end, KeyNavErrorHandler or tostring );
	if not ok then return "dirty error: " .. tostring( result ); end
	return result;
end

-- Runs fn after the given seconds (from the update loop).
function HubCore.After( seconds:number, fn )
	table.insert( HubCore.m_delayed, { time = seconds, fn = fn } );
end

-- Speaks the result of something the player just did. Selection announcements that follow within a moment (the
-- game selects the next unit) do not cut it off. Only results that follow the player's own key press interrupt;
-- the ones that happen on their own (a multi-turn move at the start of a turn, auto-explore) wait their turn.
function HubCore.SayResult( text:string )
	local now:number = UI.GetElapsedTime();
	local own:boolean = now - HubCore.m_lastKeyTime < 1.0;
	if own then
		HubCore.m_lastResultTime = now;
		OutputMessageToScreenReader( text, false );
	else
		HubCore.Announce( text, true );		-- happened on its own: waits for a popup that is speaking
	end
end

-- ===========================================================================
--	SPEECH HOLD: a popup that speaks (Eureka, tech completed, natural wonder) sends LuaEvents.SRA_SpeechHold( name, true )
--	when it shows and ( name, false ) when it closes. While a hold is active, event announcements (HubCore.Announce) wait in
--	a short queue and are spoken, in order and without interrupting, 0.4 s after the last hold ended. Results of the
--	player's own keys (SayResult) are never held. An event announcement spoken just before a hold began was cut off by
--	the popup's speech and is queued again.
-- ===========================================================================
local HOLD_SECONDS:number = 180;			-- fallback: a hold that was never released expires (holds with a context path are also released when it is hidden)
local HOLD_WATCH_INTERVAL:number = 0.5;
local HOLD_SHOW_GRACE:number = 3;		-- a popup queued with DelayShow is hidden for a moment
local HOLD_QUEUE_MAX:number = 6;
local HOLD_RELEASE_DELAY:number = 0.4;
local REPEAT_FRESH_SECONDS:number = 20;		-- a congress results popup this soon after the turn began is the turn-start one
local REPEAT_QUIET_SECONDS:number = 0.5;		-- no popup/hold for this long before the turn-start line is repeated
local REPEAT_EXPIRE_SECONDS:number = 30;		-- a pending repeat that did not fire by then is dropped
local HOLD_RECENT_WINDOW:number = 1.5;		-- announcements this recent are cut by a popup that begins now

function HubCore.IsSpeechHeld()
	local now:number = UI.GetElapsedTime();
	local holds:table = HubCore.m_speech.holds;
	for name, hold in pairs( holds ) do
		if now >= hold.expires then holds[ name ] = nil; end
	end
	return next( holds ) ~= nil;
end

-- Adds an entry; a new selection announcement replaces older (not yet spoken) selection and settle entries, exact duplicates are dropped.
local function QueueSpeech( queue:table, text:string, kind:string )
	if kind == "selection" then
		for i = #queue, 1, -1 do
			if queue[i].kind == "selection" or queue[i].kind == "settle" then table.remove( queue, i ); end
		end
	end
	for _, entry in ipairs( queue ) do
		if entry.text == text then return; end
	end
	table.insert( queue, { text = text, kind = kind } );
	while #queue > HOLD_QUEUE_MAX do table.remove( queue, 1 ); end
end

-- Speaks an event announcement (not the answer to a key): at once, or after the popup that holds the speech.
-- kind: "selection" (unit/city selected), "settle", "turn", "ready", or nil.
function HubCore.Announce( text:string, nointerrupt:boolean, kind:string )
	if text == nil or text == "" then return; end
	local speech:table = HubCore.m_speech;
	if HubCore.IsSpeechHeld() or #speech.queue > 0 then
		QueueSpeech( speech.queue, text, kind );
		return;
	end
	local now:number = UI.GetElapsedTime();
	OutputMessageToScreenReader( text, nointerrupt );
	table.insert( speech.recent, { text = text, kind = kind, time = now } );
	while #speech.recent > 4 do table.remove( speech.recent, 1 ); end
end

-- contextPath (optional): "/InGame/WorldPopups/<ID>" of the popup; the hold is released when that context is hidden or gone.
-- silent (optional): the popup shows again without speaking: take the hold but do not queue the recent lines again.
function HubCore.SetSpeechHold( name:string, on:boolean, contextPath:string, silent:boolean )
	local speech:table = HubCore.m_speech;
	if not on then
		-- the congress results are spoken before the unit line at a turn start: say that line again once they are closed
		-- (only for the results shown at the turn start, not for a reopen from a notification later in the turn)
		local old:table = speech.holds[ name ];
		if name == "WorldCongressResults" and old ~= nil and old.fresh and old.turn == Game.GetCurrentGameTurn() then
			HubCore.m_repeatTurnLine = { turn = old.turn, since = UI.GetElapsedTime(), quiet = 0 };
		end
		speech.holds[ name ] = nil;
		return;
	end
	if not silent and not HubCore.IsSpeechHeld() then
		-- the popup's own speech cut off what was said a moment ago: say it again after the popup
		local now:number = UI.GetElapsedTime();
		local old:table = speech.queue;
		speech.queue = {};
		for _, entry in ipairs( speech.recent ) do
			if now - entry.time <= HOLD_RECENT_WINDOW then QueueSpeech( speech.queue, entry.text, entry.kind ); end
		end
		for _, entry in ipairs( old ) do QueueSpeech( speech.queue, entry.text, entry.kind ); end
	end
	if not silent then speech.recent = {}; end
	local now:number = UI.GetElapsedTime();
	local old:table = speech.holds[ name ];
	local turn:number = Game.GetCurrentGameTurn();
	local fresh:boolean = ( old ~= nil and old.fresh == true ) or ( now - HubCore.m_turnBegin.time < REPEAT_FRESH_SECONDS and HubCore.m_turnBegin.turn == turn );
	speech.holds[ name ] = { expires = now + HOLD_SECONDS, path = contextPath, since = now, fresh = fresh, turn = turn };
	speech.releaseTimer = -1;
end

-- Forgets holds and everything queued (load; a hot reload of the hub starts empty as well).
-- The local player's turn became active (PlayerTurnActivated / turn announcement): a congress results popup shown
-- within REPEAT_FRESH_SECONDS of this is the turn-start one.
function HubCore.MarkTurnBegin()
	local turn:number = Game.GetCurrentGameTurn();
	local now:number = UI.GetElapsedTime();
	if HubCore.m_turnBegin.turn == turn and now - HubCore.m_turnBegin.time < REPEAT_FRESH_SECONDS then return; end
	HubCore.m_turnBegin = { time = now, turn = turn };
end

function HubCore.ClearSpeechHold()
	HubCore.m_repeatTurnLine = nil;
	HubCore.m_speech = { holds = {}, queue = {}, recent = {}, releaseTimer = -1, watch = 0 };
end

-- Turn end: the holds go, queued selection/settle/ready lines are stale, the rest (fights the status panel already
-- dropped its copy of) is spoken now.
function HubCore.ReleaseSpeechAtTurnEnd()
	HubCore.m_repeatTurnLine = nil;
	local queue:table = HubCore.m_speech.queue;
	HubCore.ClearSpeechHold();
	for _, entry in ipairs( queue ) do
		if entry.kind ~= "selection" and entry.kind ~= "settle" and entry.kind ~= "ready" then OutputMessageToScreenReader( entry.text, true ); end
	end
end

-- Releases the holds whose popup context is hidden or gone (a popup closed some other way than the one that releases).
local function ReleaseHiddenHolds()
	local now:number = UI.GetElapsedTime();
	for name, hold in pairs( HubCore.m_speech.holds ) do
		if hold.path ~= nil and now - hold.since > HOLD_SHOW_GRACE then
			local context = ContextPtr:LookUpControl( hold.path );
			if context == nil or context:IsHidden() then HubCore.m_speech.holds[ name ] = nil; end
		end
	end
end

-- From the update loop: speaks the queue once no hold is left (after a short pause), then the other periodic watches.
function HubCore.UpdateSpeech( deltaTime:number )
	local speech:table = HubCore.m_speech;
	speech.watch = ( speech.watch or 0 ) - deltaTime;
	if speech.watch <= 0 then
		speech.watch = HOLD_WATCH_INTERVAL;
		ReleaseHiddenHolds();
	end
	if HubCore.IsSpeechHeld() or #speech.queue == 0 then
		speech.releaseTimer = -1;
	else
		if speech.releaseTimer < 0 then speech.releaseTimer = HOLD_RELEASE_DELAY; end
		speech.releaseTimer = speech.releaseTimer - deltaTime;
		if speech.releaseTimer <= 0 then
			local queue:table = speech.queue;
			speech.queue = {};
			speech.releaseTimer = -1;
			for _, entry in ipairs( queue ) do
				-- "All done" that waited for a popup is only true if nothing blocks the turn now
				if entry.kind ~= "ready" or HubAnnounce == nil or HubAnnounce.IsReadyNow == nil or HubAnnounce.IsReadyNow() then
					OutputMessageToScreenReader( entry.text, true );
				end
			end
		end
	end
	local repeatLine:table = HubCore.m_repeatTurnLine;
	if repeatLine ~= nil then
		local now:number = UI.GetElapsedTime();
		if now - repeatLine.since > REPEAT_EXPIRE_SECONDS or repeatLine.turn ~= Game.GetCurrentGameTurn() then
			HubCore.m_repeatTurnLine = nil;
		elseif HubCore.IsSpeechHeld() or #speech.queue > 0 or speech.releaseTimer >= 0 or HubCore.IsGamePopupOpen() then
			repeatLine.quiet = 0;
		else
			repeatLine.quiet = repeatLine.quiet + deltaTime;
			if repeatLine.quiet >= REPEAT_QUIET_SECONDS then
				HubCore.m_repeatTurnLine = nil;
				if HubAnnounce ~= nil and HubAnnounce.RepeatTurnStartLine ~= nil then HubAnnounce.RepeatTurnStartLine(); end
			end
		end
	end
	if HubAnnounce ~= nil and HubAnnounce.UpdateReadyWatch ~= nil then HubAnnounce.UpdateReadyWatch( deltaTime ); end
end

function HubCore.IsPlotVisibleToLocal( plot:table )
	local vis:table = PlayersVisibility[ Game.GetLocalPlayer() ];
	return vis ~= nil and plot ~= nil and vis:IsVisible( plot:GetIndex() );
end

-- Is this player an enemy of the local player: barbarians and civilizations at war with us.
function HubCore.IsHostile( playerID:number )
	local player:table = Players[ playerID ];
	if player == nil or playerID == Game.GetLocalPlayer() then return false; end
	if player:IsBarbarian() then return true; end
	local localPlayer:table = Players[ Game.GetLocalPlayer() ];
	if localPlayer == nil then return false; end
	local diplomacy:table = localPlayer:GetDiplomacy();
	return diplomacy ~= nil and diplomacy:IsAtWarWith( playerID );
end

-- A foreign unit the local player can really see (not fogged, not an invisible submarine ...).
function HubCore.IsForeignUnitVisible( unit:table )
	return unit:GetOwner() ~= Game.GetLocalPlayer() and PlotDescription_IsUnitVisible( unit );
end

-- Remembers a unit's spoken name while it is alive: when it dies the unit object is already gone.
function HubCore.RememberUnit( unit:table )
	if unit ~= nil then HubCore.m_unitNames[ unit:GetOwner() .. ":" .. unit:GetID() ] = PlotDescription_GetUnitName( unit ); end
end

-- Is (x, y) within the distance of one of the local player's units or cities?
function HubCore.IsNearLocal( x:number, y:number, distance:number )
	local player:table = Players[ Game.GetLocalPlayer() ];
	if player == nil then return false; end
	for _, unit in player:GetUnits():Members() do
		if Map.GetPlotDistance( x, y, unit:GetX(), unit:GetY() ) <= distance then return true; end
	end
	for _, city in player:GetCities():Members() do
		if Map.GetPlotDistance( x, y, city:GetX(), city:GetY() ) <= distance then return true; end
	end
	return false;
end

function HubCore.Plural( n:number, one:string, many:string )
	if n == 1 then return n .. " " .. one; end
	return n .. " " .. many;
end

-- Is this one of the local player's units that can found a city?
function HubCore.IsSettler( unit:table )
	if unit == nil or unit:GetOwner() ~= Game.GetLocalPlayer() then return false; end
	local row:table = GameInfo.Units[ unit:GetUnitType() ];
	return row ~= nil and row.FoundCity == true;
end

-- "Builder can build: Farm, Mine" / "Builder can build nothing here" for the plot, as the engine answers for this unit
-- (the same check the unit panel makes). Nil when the unit is no builder or the plot is not known.
function HubCore.BuilderBuildText( unit:table, plot:table )
	local list:table = BuildScan_Improvements( unit );
	if list == nil or plot == nil then return nil; end
	local vis:table = PlayersVisibility[ Game.GetLocalPlayer() ];
	if vis == nil or not vis:IsRevealed( plot:GetIndex() ) then return nil; end
	local name:string = Locale.Lookup( GameInfo.Units[ unit:GetUnitType() ].Name );
	if unit:GetMovesRemaining() <= 0 then return name .. " has no moves left"; end
	local names:table = {};
	for _, improvement in ipairs( list ) do
		if BuildScan_CanBuild( unit, plot, improvement ) then table.insert( names, improvement.name ); end
	end
	if #names == 0 then return name .. " can build nothing here"; end
	if #names > 6 then
		local extra:number = #names - 5;
		names = { names[1], names[2], names[3], names[4], names[5], extra .. " more" };
	end
	return name .. " can build: " .. table.concat( names, ", " );
end

-- The first n good and m bad reasons of a settle candidate as "river, coast, silk, but floods, poor food" (empty when
-- there are none).
local function SettleReasonList( candidate:table, n:number, m:number )
	return SettleScan_ReasonList( candidate, n, m );
end

-- The same with a leading comma (empty when there are none).
function HubCore.SettleReasons( candidate:table, n:number, m:number )
	local text:string = SettleReasonList( candidate, n, m or 2 );
	if text == "" then return ""; end
	return ", " .. text;
end

-- One sentence about the settler's plot and the best spot nearby, said when a settler is selected.
-- The terrain and river of the settler's plot are in the unit announcement already: only "can settle" and what is
-- wrong with the plot are said about it.
function HubCore.SettleSentence( unit:table )
	local key:string = "B";
	if HubEnemies ~= nil and HubEnemies.KeyText ~= nil then key = HubEnemies.KeyText( "FoundCity", "B" ); end
	return SettleScan_Sentence( SettleScan_Scan( unit ), key, unit:GetMovesRemaining() > 0 );
end

-- Adds a handler to an event when the game has that event.
function HubCore.AddEvent( name:string, handler )
	if Events[name] == nil then
		print( "InGameAccess: unknown event " .. name );
		return;
	end
	HubCore.Listen( Events[name], HubCore.Safe( name, handler ) );
end

-- ===========================================================================
--	MODES: the keyboard lists of the hub (unit actions menu, diplomacy list, settle spot browser, top panel,
--	notifications). Exactly one can be active: m_mode holds it, opening one closes the one before, and the input handler
--	gives keys to m_mode.list only. Whatever makes a mode stale (selection change, turn end, load, player change,
--	entering a target mode) closes it through CloseMode, which also resets the list so that it reopens fresh.
--	The engine's target modes (move to, attacks ...) are the other kind of state: they are exclusive with m_mode by
--	CanOpenMode (refuses to open a mode in a target mode) and OnInterfaceModeChanged (entering one closes the mode).
-- ===========================================================================

function HubCore.IsModeOpen( name:string )
	return HubCore.m_mode ~= nil and HubCore.m_mode.name == name;
end

-- speak: say "Closed" (the player closed it). quiet: closed because it went stale, so a mode's restoring work (the
-- settle browser puts the cursor back on the settler) is not done.
function HubCore.CloseMode( speak:boolean, quiet:boolean )
	local mode:table = HubCore.m_mode;
	if mode == nil then return; end
	HubCore.m_mode = nil;
	mode.list.Reset();
	if mode.onClose ~= nil then
		local ok:boolean, err = xpcall( function() mode.onClose( quiet == true ); end, KeyNavErrorHandler );
		if not ok then print( "InGameAccess mode close error: " .. tostring( err ) ); end
	end
	if speak then OutputMessageToScreenReader( "Closed" ); end
end

-- Makes the list the active mode (closing the previous one) and announces it.
function HubCore.OpenMode( name:string, list:table, title:string, onClose )
	HubCore.CloseMode( false, false );
	HubCore.m_mode = { name = name, list = list, onClose = onClose };
	list.Open( title );
end
