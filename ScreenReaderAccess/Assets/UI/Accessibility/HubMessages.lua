-- ===========================================================================
--	HubMessages: the history of the mod's spoken event announcements (Control+M, the pad ring after Notifications).
--	Part of the InGameAccess hub (see docs/features.md, Architecture): included by UI/Additions/InGameAccess.lua.
--	HubCore.Announce logs what the game made the mod say (turn line, enemies, combat, notifications ...), not answers to keys.
--	The list shows the newest first, grouped by turn; Space adds the turn and the position, Enter moves the map cursor there.
-- ===========================================================================
HubMessages = {};

local MAX_MESSAGES:number = 100;
local m_messages:table = {};		-- oldest first: { id, text, turn, plotIndex }
local m_nextId:number = 1;

local MAX_PER_TURN:number = 30;
local m_seenKeys:table = {};		-- turn .. text: a line is logged once per turn

-- Notifications that come back every turn as routine blockers: spoken on arrival, but not worth a line in the history.
local ROUTINE:table = {
	NOTIFICATION_COMMAND_UNITS = true, NOTIFICATION_CHOOSE_TECH = true, NOTIFICATION_CHOOSE_CIVIC = true,
	NOTIFICATION_CHOOSE_CITY_PRODUCTION = true, NOTIFICATION_CHOOSE_PRODUCTION = true, NOTIFICATION_FILL_CIVIC_SLOT = true,
};
function HubMessages.IsRoutine( typeName:string )
	return typeName ~= nil and ROUTINE[ typeName ] == true;
end

-- The arrival line and its history line: entries = { text, plotIndex, routine }. The spoken line lists every notification; the history
-- line leaves the routine ones out (nil when nothing remains). Returns said, historyText, historyPlotIndex (nil when none or several).
function HubMessages.ArrivalTexts( entries:table )
	local texts:table, logged:table = {}, {};
	for _, entry in ipairs( entries ) do
		table.insert( texts, entry.text );
		if not entry.routine then table.insert( logged, entry ); end
	end
	if #texts == 0 then return nil; end
	local function Line( list:table )
		if #list == 1 then return "Notification: " .. ( list[1].text or list[1] ); end
		local names:table = {};
		for _, e in ipairs( list ) do table.insert( names, e.text or e ); end
		return #list .. " new notifications: " .. KeyNavList_ShortList( names, 3 );
	end
	local said:string = Line( texts );
	local history:string = nil;
	if #logged == #texts then history = said; elseif #logged > 0 then history = Line( logged ); end
	local plot = ( #logged == 1 ) and logged[1].plotIndex or nil;
	if #logged == 0 then plot = nil; end
	return said, history, plot;
end

function HubMessages.Clear()
	m_messages = {};
	m_seenKeys = {};
end

-- plotIndex (optional): the plot the message is about. The same text twice in one turn is dropped; a turn keeps at most 30
-- entries (the oldest of that turn goes first, the "Turn N, year" line stays).
function HubMessages.Add( text:string, plotIndex:number )
	if text == nil or text == "" then return; end
	local turn:number = Game.GetCurrentGameTurn();
	local key:string = turn .. "|" .. text;
	if m_seenKeys[ key ] then return; end
	m_seenKeys[ key ] = true;
	table.insert( m_messages, { id = m_nextId, text = text, turn = turn, plotIndex = plotIndex } );
	m_nextId = m_nextId + 1;
	local count:number = 0;
	for _, message in ipairs( m_messages ) do
		if message.turn == turn then count = count + 1; end
	end
	if count > MAX_PER_TURN then
		for i, message in ipairs( m_messages ) do
			if message.turn == turn and not string.find( message.text, "^Turn %d+, " ) then
				m_seenKeys[ message.turn .. "|" .. message.text ] = nil;
				table.remove( m_messages, i );
				break;
			end
		end
	end
	while #m_messages > MAX_MESSAGES do
		local gone:table = table.remove( m_messages, 1 );
		m_seenKeys[ gone.turn .. "|" .. gone.text ] = nil;
	end
end

-- The plot index of a map position, nil when there is none (safe to call with anything).
function HubMessages.PlotIndexOf( x:number, y:number )
	if x == nil or y == nil then return nil; end
	local ok:boolean, plot = pcall( Map.GetPlot, x, y );
	if ok and plot ~= nil then return plot:GetIndex(); end
	return nil;
end

function HubMessages.Count()
	return #m_messages;
end

local function PlotOf( plotIndex:number )
	if plotIndex == nil then return nil; end
	return Map.GetPlotByIndex( plotIndex );
end

-- Newest first, one section per turn. Space reads the message with its turn and, with a place, the position from the nearest city.
function HubMessages.BuildItems()
	local items:table = {};
	for i = #m_messages, 1, -1 do
		local message:table = m_messages[i];
		table.insert( items, {
			key = "m:" .. message.id, text = message.text, section = "Turn " .. message.turn, note = message,
			detail = function()
				local text:string = string.gsub( message.text, "[%.%s]+$", "" ) .. ", turn " .. message.turn;
				local plot:table = PlotOf( message.plotIndex );
				if plot ~= nil then
					local position:string = HubAnnounce.PositionText( plot );
					if position ~= nil then text = text .. ", " .. position; end
				end
				return text;
			end,
		} );
	end
	return items;
end

local m_list:table;

local function Activate( item:table )
	local plot:table = PlotOf( item.note.plotIndex );
	if plot == nil then
		OutputMessageToScreenReader( "No place for this message" );
		return;
	end
	HubCore.CloseMode( false, false );
	HubCursor.SetCursor( plot:GetX(), plot:GetY(), true, true, false, true );
end

m_list = KeyNavList_Create{
	build		= HubMessages.BuildItems,
	isActive	= function() return HubCore.IsModeOpen( "messages" ); end,
	onActivate	= Activate,
	onClose		= function() HubCore.CloseMode( true, false ); end,
};

-- Always opens (the controller ring, HubPad); the keyboard toggle below closes an open list instead.
function HubMessages.Open()
	if not HubTargets.CanOpenMode() then return; end
	if #m_messages == 0 then
		OutputMessageToScreenReader( "No messages yet" );
		return;
	end
	HubCore.OpenMode( "messages", m_list, "Messages" );
end

function HubMessages.Toggle()
	if HubCore.IsModeOpen( "messages" ) then HubCore.CloseMode( true, false ); return; end
	HubMessages.Open();
end
