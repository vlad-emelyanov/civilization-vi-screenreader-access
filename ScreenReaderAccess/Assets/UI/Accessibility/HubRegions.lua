-- ===========================================================================
--	HubRegions: top panel (Control+Y) and notifications (Control+N) lists, arrivals.
--	Part of the InGameAccess hub (see docs/ingame-plan.md, Architecture): included by
--	UI/Additions/InGameAccess.lua. State and functions other hub modules use are fields of HubRegions.
-- ===========================================================================
HubRegions = {};

local m_notifData			:table = {};		-- notifications sent by NotificationPanel (SRA_Notifications), plain data
local m_notifAnswered		:boolean = false;	-- NotificationPanel answered the last SRA_RequestNotifications

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

-- Always opens (the controller ring, HubPad); the keyboard toggle below closes an open list instead.
function HubRegions.OpenTopPanel()
	if not HubTargets.CanOpenMode() then return; end
	HubCore.OpenMode( "top", m_topList, "Top panel" );
end

function HubRegions.ToggleTopPanel()
	if HubCore.IsModeOpen( "top" ) then HubCore.CloseMode( true, false ); return; end
	HubRegions.OpenTopPanel();
end

-- Control+G: the basic yields in one sentence, without entering the region.
function HubRegions.SpeakYields()
	if not HubCore.IsLocalPlayerActive() then return; end
	OutputMessageToScreenReader( TopPanelData_Summary() );
end

-- Control+W: the Great Works screen has no input action of its own; the launch bar toggles it through these events.
function HubRegions.ToggleGreatWorks()
	local screen = ContextPtr:LookUpControl( "/InGame/GreatWorksOverview" );
	if screen ~= nil and not screen:IsHidden() then
		LuaEvents.LaunchBar_CloseGreatWorksOverview();
	else
		LuaEvents.LaunchBar_OpenGreatWorksOverview();
	end
end

function HubRegions.OnNotificationsReceived( list:table )
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

function HubRegions.OnNotificationActivated( id:number, found:boolean, lookOnly:boolean )
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
		if HubCore.m_lastSelectionSpeech >= started or HubCore.m_mode ~= nil then return; end		-- a selection or screen spoke for itself
		-- the world may have moved on in half a second (turn change, hotseat, a popup or a target mode opened)
		if Game.GetLocalPlayer() ~= player or Game.GetCurrentGameTurn() ~= turn or not HubCore.IsLocalPlayerActive() then return; end
		if not Players[ player ]:IsTurnActive() or UI.GetInterfaceMode() ~= InterfaceModeTypes.SELECTION then return; end
		if HubCore.IsGamePopupOpen() then return; end
		if n.x >= 0 and n.y >= 0 then
			if n.speakOnEnter then		-- e.g. Suzerain Status Lost: the city-state's name before the plot
				local title:string = CleanTextForSpeech( n.message );
				local summary:string = CleanTextForSpeech( n.summary );
				OutputMessageToScreenReader( title .. ( summary ~= "" and summary ~= title and ( ". " .. summary ) or "" ) );
			end
			HubCursor.SetCursor( n.x, n.y, true, false, false, true );		-- a jump: the position from the nearest city follows
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

-- The notifications that have a place on the map, newest first: { id, text, x, y } (the places list, J, shows them too).
function HubRegions.GetLocatedNotifications()
	local located:table = {};
	for _, item in ipairs( BuildNotificationItems() ) do
		local n:table = item.note;
		if n.x >= 0 and n.y >= 0 then table.insert( located, { id = n.id, text = item.text, x = n.x, y = n.y } ); end
	end
	return located;
end

-- M: send one of your units to the place of the focused notification.
local function SendUnitToNotification()
	local focus = m_notifList.GetFocusKey();
	for _, item in ipairs( BuildNotificationItems() ) do
		if item.key == focus then
			if item.note.x < 0 or item.note.y < 0 then
				OutputMessageToScreenReader( "This notification has no place on the map" );
			else
				HubPlaces.OpenSend( { name = item.text, x = item.note.x, y = item.note.y, back = "notifications" } );
			end
			return;
		end
	end
	OutputMessageToScreenReader( "Nothing selected" );
end

-- X on the controller dismisses (what Delete does)
local m_notifKeys:table = { [Keys.VK_DELETE] = DismissNotification, [Keys.M] = SendUnitToNotification };
if Gamepad.Key( "X" ) ~= nil then m_notifKeys[ Gamepad.Key( "X" ) ] = DismissNotification; end

m_notifList = KeyNavList_Create{
	build		= BuildNotificationItems,
	isActive	= function() return HubCore.IsModeOpen( "notifications" ); end,
	onActivate	= ActivateNotification,
	onClose		= function() HubCore.CloseMode( true, false ); end,
	extraKeys	= m_notifKeys,
};

-- Always opens (the controller ring, HubPad); the keyboard toggle below closes an open list instead.
function HubRegions.OpenNotifications()
	if not HubTargets.CanOpenMode() then return; end
	if #BuildNotificationItems() == 0 then
		OutputMessageToScreenReader( m_notifAnswered and "No notifications" or "Notifications are not available" );
		return;
	end
	HubCore.OpenMode( "notifications", m_notifList, "Notifications" );
end

function HubRegions.ToggleNotifications()
	if HubCore.IsModeOpen( "notifications" ) then HubCore.CloseMode( true, false ); return; end
	HubRegions.OpenNotifications();
end

-- New notifications are announced when they arrive, without interrupting; a burst (turn start) becomes one sentence.
-- "Barbarians sighted" is left out only when the hub itself said "X spotted ..." for a hostile unit around that time
-- (the notification also covers sightings farther than 4 tiles from our cities and units, and the spotting is capped).
HubRegions.m_lastSpotSpeech = -100;		-- UI.GetElapsedTime() of the last "X spotted" announcement

function HubRegions.OnNotificationAdded( id:number, message:string, summary:string, typeName:string, blocking:boolean )
	if not HubCore.m_ready then return; end
	local text:string = CleanTextForSpeech( message );
	if text == "" then text = CleanTextForSpeech( summary ); end
	if text == "" then return; end
	-- Founding a religion (U, Tab > Found Religion) opens no screen, only this notification: say how to get to the screen
	if typeName == "NOTIFICATION_CHOOSE_RELIGION" then
		text = "Religion founded: choose a name and beliefs. Control+N, then Enter on '" .. text .. "'";
	elseif typeName == "NOTIFICATION_CHOOSE_BELIEF" then
		text = text .. ". Control+N, then Enter to choose";
	end
	-- "New Barbarian Outpost" alone does not say where: from the nearest city of ours, like the camps in the places list (J)
	if typeName == "NOTIFICATION_NEW_BARBARIAN_CAMP" then
		local ok:boolean, position = pcall( function()
			local note:table = NotificationManager.Find( Game.GetLocalPlayer(), id );
			if note == nil or not note:IsLocationValid() then return nil; end
			local x:number, y:number = note:GetLocation();
			return HubAnnounce.PositionText( Map.GetPlot( x, y ) );
		end );
		if ok and position ~= nil then text = text .. ", " .. position; end
	end
	table.insert( HubCore.m_arrivals, { text = text, time = UI.GetElapsedTime(), spotType = ( typeName == "NOTIFICATION_BARBARIANS_SIGHTED" ) } );
	if HubCore.m_arrivalTimer < 0 then HubCore.m_arrivalTimer = 0.8; end		-- flush 0.8 s after the first one: a trickle must not postpone the burst
end

-- Event-style speech (nointerrupt). HubCore.Announce holds it while a Eureka/tech/wonder popup is open (agent C, round 8);
-- until that is merged the plain call is used.
function HubRegions.Announce( text:string )
	if HubCore.Announce ~= nil then HubCore.Announce( text, true ); else OutputMessageToScreenReader( text, true ); end
end

function HubRegions.FlushArrivals()
	local entries:table = HubCore.m_arrivals;
	HubCore.m_arrivals = {};
	local texts:table = {};
	for _, entry in ipairs( entries ) do
		if not ( entry.spotType and math.abs( HubRegions.m_lastSpotSpeech - entry.time ) < 3 ) then table.insert( texts, entry.text ); end
	end
	if #texts == 0 then return; end
	if #texts == 1 then
		HubRegions.Announce( "Notification: " .. texts[1] );
	else
		HubRegions.Announce( #texts .. " new notifications: " .. KeyNavList_ShortList( texts, 3 ) );
	end
end
