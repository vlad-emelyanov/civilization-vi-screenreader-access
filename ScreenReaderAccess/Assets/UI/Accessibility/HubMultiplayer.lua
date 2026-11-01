-- ===========================================================================
--	HubMultiplayer: what the in-game multiplayer panels do not say or cannot do from the keyboard (UNVERIFIED, needs a real
--	network game; see docs/features.md, Multiplayer in game).
--	Part of the InGameAccess hub (see docs/features.md, Architecture): included by UI/Additions/InGameAccess.lua.
--	  * chat: incoming messages are spoken (without interrupting) and logged in the messages history (Control+M); Control+T opens
--	    a list "Chat, N messages": "Type a message" first, then the chat history, newest first. The text is typed in an EditBox of
--	    this context (InGameAccess.xml, SRChatBox) through KeyNavEditBox and sent with Network.SendChat to everybody.
--	  * the turn timer: Events.TurnTimerUpdated (what the action panel's meter listens to) gives the warnings at 60, 30 and 10
--	    seconds and the "Turn timer" entry of the top panel list. Without a timer (maxTurnTime <= 0) the handler returns at once.
--	  * host migration: "Anna is now the host" (Events.MultiplayerMatchHostMigrated), spoken and logged.
--	  * players dropping out: the status panel already says connected / disconnected / kicked; this module logs those lines in
--	    the messages history and says when a dropped human slot is played by the computer.
--	Wording lives in Accessibility/MultiplayerText.lua (tested offline).
-- ===========================================================================
HubMultiplayer = {};

include( "MultiplayerText" );
include( "KeyNavEditBox" );

local MAX_CHAT:number = 100;
local m_chat:table = {};			-- oldest first: { id, text }
local m_chatId:number = 1;
local m_timer:table = { remaining = nil, stamp = 0, warned = {} };		-- the last TurnTimerUpdated reading
local m_list:table;

local function IsNetwork()
	return GameConfiguration ~= nil and GameConfiguration.IsNetworkMultiplayer();
end

local function PlayerName( playerID:number )
	local cfg:table = PlayerConfigurations[ playerID ];
	if cfg == nil then return "Unknown player"; end
	return CleanTextForSpeech( Locale.Lookup( cfg:GetPlayerName() ) );
end

local function RealPlayer( playerID:number )
	return playerID ~= nil and playerID ~= -1 and playerID ~= 1000;
end

-- ===========================================================================
--	CHAT
-- ===========================================================================
function HubMultiplayer.Count()
	return #m_chat;
end

-- Events.MultiplayerChat (what the game's chat panel listens to). The engine echoes the local player's own message back: it goes
-- into the chat list but is not spoken. Others' messages are spoken once the load is done (the front end's staging room spoke
-- everything before the game started, and that screen is gone by then).
function HubMultiplayer.OnChat( fromPlayer:number, toPlayer:number, text:string, targetType )
	if not IsNetwork() then return; end
	local mine:boolean = ( fromPlayer == Game.GetLocalPlayer() );
	local kind:string = "all";
	if targetType == ChatTargetTypes.CHATTARGET_TEAM then
		kind = "team";
	elseif targetType == ChatTargetTypes.CHATTARGET_PLAYER then
		kind = "private";
	end
	local line:string = MPText_ChatLine( mine and "You" or PlayerName( fromPlayer ), kind, text );
	table.insert( m_chat, { id = m_chatId, text = line } );
	m_chatId = m_chatId + 1;
	while #m_chat > MAX_CHAT do table.remove( m_chat, 1 ); end
	if not mine and HubCore.m_ready then HubCore.Announce( line, true, "chat" ); end
end

-- The first item opens the text field, the rest is the history, newest first.
function HubMultiplayer.BuildChatItems()
	local items:table = { { key = "type", text = "Type a message", detail = "Type a message to everybody. Enter sends it, Escape cancels." } };
	for i = #m_chat, 1, -1 do
		table.insert( items, { key = "c:" .. m_chat[i].id, text = m_chat[i].text } );
	end
	return items;
end

-- Sends the text to all players (the game's chat panel sends through Network.SendChat as well; its slash commands for whispers and
-- team chat are not available here).
function HubMultiplayer.Send( text:string )
	if text == nil or text == "" then return; end
	Network.SendChat( text, ChatTargetTypes.CHATTARGET_ALL, -1 );
end

function HubMultiplayer.StartTyping()
	HubCore.CloseMode( false, false );
	local box:table = Controls.SRChatBox;
	if box == nil then
		OutputMessageToScreenReader( "Chat input is not available" );
		return;
	end
	box:ClearString();
	box:SetHide( false );
	-- a control that was hidden a moment ago takes the keyboard focus a frame later
	HubCore.After( 0.15, function()
		KeyNavEditBox_Begin( box, {
			label = "message", commit = HubMultiplayer.Send, unchangedText = "Nothing sent",
			doneText = "Message sent", cancelText = "Message cancelled",
			onEnd = function() box:ClearString(); box:SetHide( true ); end,
		} );
	end );
end

m_list = KeyNavList_Create{
	build		= HubMultiplayer.BuildChatItems,
	isActive	= function() return HubCore.IsModeOpen( "chat" ); end,
	onActivate	= function( item )
		if item.key == "type" then
			HubMultiplayer.StartTyping();
		else
			OutputMessageToScreenReader( item.text );
		end
	end,
	onClose		= function() HubCore.CloseMode( true, false ); end,
};

-- Control+T (KeyNavChat).
function HubMultiplayer.ToggleChat()
	if HubCore.IsModeOpen( "chat" ) then HubCore.CloseMode( true, false ); return; end
	if not IsNetwork() then
		OutputMessageToScreenReader( "Chat is for multiplayer games" );
		return;
	end
	if not HubTargets.CanOpenMode() then return; end
	HubCore.OpenMode( "chat", m_list, MPText_ChatTitle( #m_chat ) );
end

-- First thing in the hub's input handler: the key that ended a text edit is swallowed (KeyNavEditBox).
function HubMultiplayer.HandleInput( input:table )
	return KeyNavEditBox_HandleInput( input ) == true;
end

function HubMultiplayer.Update( deltaTime:number )
	KeyNavEditBox_Update( deltaTime );
end

-- ===========================================================================
--	TURN TIMER
-- ===========================================================================
-- Events.TurnTimerUpdated( elapsedTime, maxTurnTime ): maxTurnTime <= 0 when the game has no timer.
function HubMultiplayer.OnTurnTimerUpdated( elapsedTime:number, maxTurnTime:number )
	if maxTurnTime == nil or maxTurnTime <= 0 then
		m_timer.remaining = nil;
		return;
	end
	local remaining:number = maxTurnTime - elapsedTime;
	m_timer.remaining = remaining;
	m_timer.stamp = UI.GetElapsedTime();
	local due = MPText_TimerPending( remaining, m_timer.warned );
	if due == nil or not HubCore.m_ready or not HubCore.IsLocalPlayerActive() then return; end
	-- only while this player's turn is running and not yet ended (after the end, the action panel says "Waiting for players");
	-- a warning that is not spoken stays due
	local player:table = Players[ Game.GetLocalPlayer() ];
	if player == nil or not player:IsTurnActive() or HubAnnounce.IsWaiting() then return; end
	MPText_TimerMark( due, m_timer.warned );
	OutputMessageToScreenReader( MPText_TimerWarning( remaining ), true );
end

-- A new turn starts: the warnings are due again (also for a timer of 60 seconds or less, which never rises above 60).
function HubMultiplayer.OnTurnBegin()
	m_timer.warned = {};
end

-- The "Turn timer" entry of the top panel list; nil without a timer or when the last reading is old.
function HubMultiplayer.TimerText()
	if m_timer.remaining == nil then return nil; end
	local age:number = UI.GetElapsedTime() - m_timer.stamp;
	if age > 5 then return nil; end
	local left:number = m_timer.remaining - age;
	if left <= 0 then return nil; end
	local text:string = MPText_TimerItem( left );
	local player:table = Players[ Game.GetLocalPlayer() ];
	if player ~= nil and not player:IsTurnActive() then text = text .. ", waiting for the other players"; end
	return text;
end

-- ===========================================================================
--	PLAYERS DROPPING OUT
-- ===========================================================================
local function Log( text:string )
	if HubCore.m_ready and HubMessages ~= nil then HubMessages.Add( text ); end
end

function HubMultiplayer.OnPlayerConnected( playerID:number )
	if not RealPlayer( playerID ) or not IsNetwork() then return; end
	Log( MPText_PlayerNotice( PlayerName( playerID ), "reconnected" ) );		-- the status panel speaks it
end

function HubMultiplayer.OnPlayerDisconnecting( playerID:number )
	if not RealPlayer( playerID ) or not IsNetwork() then return; end
	local cfg:table = PlayerConfigurations[ playerID ];
	if cfg == nil or not cfg:IsHuman() then return; end
	Log( MPText_PlayerNotice( PlayerName( playerID ), Network.IsPlayerKicked( playerID ) and "kicked" or "disconnected" ) );		-- the status panel speaks it
end

-- True when the local turn is ready (not active any more, or the action panel waits for players) and another living human
-- besides `droppedID` is still playing theirs.
function HubMultiplayer.StillWaitingForOthers( droppedID:number )
	local localID:number = Game.GetLocalPlayer();
	local me:table = Players[ localID ];
	if me == nil or ( me:IsTurnActive() and not HubAnnounce.IsWaiting() ) then return false; end
	for _, other in ipairs( PlayerManager.GetAliveMajors() ) do
		local id:number = other:GetID();
		local cfg:table = PlayerConfigurations[ id ];
		if id ~= localID and id ~= droppedID and cfg ~= nil and cfg:IsHuman() and other:IsTurnActive() then return true; end
	end
	return false;
end

-- Events.MultiplayerMatchHostMigrated( newHostID, oldHostID ) (the chat panel's event): spoken without interrupting, logged in Control+M.
function HubMultiplayer.OnHostMigrated( newHostID:number, oldHostID:number )
	if not IsNetwork() or not RealPlayer( newHostID ) then return; end
	local text:string = MPText_HostNotice( PlayerName( newHostID ), newHostID == Game.GetLocalPlayer() );
	if HubCore.m_ready then HubCore.Announce( text, true, "chat" ); end		-- Announce logs it for Control+M
end

-- Events.MultiplayerPostPlayerDisconnected: a moment later the slot may be played by the computer (the game shows nothing).
function HubMultiplayer.OnPlayerDisconnected( playerID:number )
	if not RealPlayer( playerID ) or not IsNetwork() then return; end
	HubCore.After( 1.5, function()
		local ok:boolean, err = pcall( function()
			local cfg:table = PlayerConfigurations[ playerID ];
			if cfg == nil or not HubCore.m_ready then return; end
			-- 4 = computer slot (the game's ChatPanel compares with the literal; SlotStatus may not exist in this context)
			if cfg:GetSlotStatus() == 4 or not cfg:IsHuman() then
				HubCore.Announce( MPText_PlayerNotice( PlayerName( playerID ), "ai" ), true, "chat" );
			end
			-- our turn is done and another human still has to finish theirs
			if HubMultiplayer.StillWaitingForOthers( playerID ) then
				HubCore.Announce( MPText_StillWaiting(), true, "chat" );
			end
		end );
		if not ok then print( "HubMultiplayer AI check error: " .. tostring( err ) ); end
	end );
end

-- Wires the events (called from the hub's Initialize).
function HubMultiplayer.Init()
	HubCore.Listen( Events.MultiplayerChat, HubCore.Safe( "MultiplayerChat", HubMultiplayer.OnChat ) );
	HubCore.Listen( Events.TurnTimerUpdated, HubCore.Safe( "TurnTimerUpdated", HubMultiplayer.OnTurnTimerUpdated ) );
	HubCore.Listen( Events.MultiplayerPlayerConnected, HubCore.Safe( "MultiplayerPlayerConnected", HubMultiplayer.OnPlayerConnected ) );
	HubCore.Listen( Events.MultiplayerPrePlayerDisconnected, HubCore.Safe( "MultiplayerPrePlayerDisconnected", HubMultiplayer.OnPlayerDisconnecting ) );
	HubCore.Listen( Events.MultiplayerPostPlayerDisconnected, HubCore.Safe( "MultiplayerPostPlayerDisconnected", HubMultiplayer.OnPlayerDisconnected ) );
	HubCore.Listen( Events.MultiplayerMatchHostMigrated, HubCore.Safe( "MultiplayerMatchHostMigrated", HubMultiplayer.OnHostMigrated ) );
	HubCore.Listen( Events.LocalPlayerTurnBegin, HubCore.Safe( "MPTurnBegin", HubMultiplayer.OnTurnBegin ) );
	TopPanelData_TimerText = HubMultiplayer.TimerText;
end
