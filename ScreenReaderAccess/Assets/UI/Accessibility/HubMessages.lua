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

function HubMessages.Clear()
	m_messages = {};
end

-- plotIndex (optional): the plot the message is about. An exact repeat of the previous entry in the same turn is dropped.
function HubMessages.Add( text:string, plotIndex:number )
	if text == nil or text == "" then return; end
	local turn:number = Game.GetCurrentGameTurn();
	local last:table = m_messages[ #m_messages ];
	if last ~= nil and last.text == text and last.turn == turn then return; end
	table.insert( m_messages, { id = m_nextId, text = text, turn = turn, plotIndex = plotIndex } );
	m_nextId = m_nextId + 1;
	while #m_messages > MAX_MESSAGES do table.remove( m_messages, 1 ); end
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
