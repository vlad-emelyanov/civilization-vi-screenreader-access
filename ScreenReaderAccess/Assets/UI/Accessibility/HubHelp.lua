-- ===========================================================================
--	HubHelp: the accessibility help list (Control+H, action KeyNavHelp), read-only.
--	Part of the InGameAccess hub (see docs/ingame-plan.md, Architecture): included by UI/Additions/InGameAccess.lua.
--	The text is Accessibility/HelpText.lua (the one place for shortcut descriptions, keep it up to date); this module
--	only shows it, in the pattern of the places list (HubPlaces): sections with entries.
--
--	Tab / Control+Tab change the section (wraps), Up/Down/Home/End the entry, a letter jumps to the next section whose title
--	starts with it, Space repeats the entry, Escape or Control+H closes. Opens inside a target mode too (it only reads).
--	Front end: not needed now (the front-end screens say their keys themselves).
-- ===========================================================================
include( "HelpText" );

HubHelp = {};

local m_data			:table = nil;		-- the open help: sections from HelpText_Build
local m_section			:number = 1;
local m_list			:table;

-- The key as the game shows it for the action now (nil: unknown action or unbound; HelpText falls back to the default).
local function CurrentBinding( actionName:string )
	local id = Input.GetActionId( actionName );
	if id == nil then return nil; end
	return Input.GetGestureDisplayString( id, 0 );
end

local function SectionHead( section:table )
	return section.title .. ", " .. m_section .. " of " .. #m_data .. " sections";
end

-- Says the focused entry as "text, i of n", after the prefix.
local function SpeakFocus( prefix:string )
	local items:table = m_data[ m_section ].items;
	local focus = m_list.GetFocusKey();
	for i, item in ipairs( items ) do
		if item.key == focus then
			OutputMessageToScreenReader( prefix .. item.text .. ", " .. i .. " of " .. #items );
			return;
		end
	end
end

local function SwitchSection( delta:number )
	if m_data == nil then return; end
	m_section = ( m_section - 1 + delta ) % #m_data + 1;
	local section:table = m_data[ m_section ];
	m_list.Open( "Help", section.items[1].key, true, true );
	SpeakFocus( SectionHead( section ) .. ". " );
end

-- A letter: the next section (after this one, wrapping) whose title starts with it.
local function JumpToLetter( letter:string )
	if m_data == nil then return; end
	for step = 1, #m_data do
		local index:number = ( m_section - 1 + step ) % #m_data + 1;
		if m_data[ index ].title:sub( 1, 1 ):lower() == letter then
			SwitchSection( index - m_section );
			return;
		end
	end
	OutputMessageToScreenReader( "No section starting with " .. letter:upper() );
end

local m_facade:table = {
	Open = function( title:string )
		local section:table = m_data[ m_section ];
		m_list.Open( title, section.items[1].key, true );
		SpeakFocus( title .. ". " .. SectionHead( section ) .. ". " );
	end,
	Reset = function() m_list.Reset(); end,
	HandleInput = function( input:table ) return m_list.HandleInput( input ); end,
};

local function CloseHelp()
	HubCore.CloseMode( false, false );
	OutputMessageToScreenReader( "Help closed" );
end

local function LetterKeys()
	local keys:table = {};
	for code = string.byte( "a" ), string.byte( "z" ) do
		local letter:string = string.char( code );
		local key = Keys[ letter:upper() ];
		if key ~= nil then keys[ key ] = function() JumpToLetter( letter ); end end
	end
	keys[ Keys.VK_TAB ] = function() SwitchSection( 1 ); end;
	return keys;
end

m_list = KeyNavList_Create{
	build		= function() return ( m_data ~= nil and m_data[ m_section ] ~= nil ) and m_data[ m_section ].items or {}; end,
	isActive	= function() return HubCore.IsModeOpen( "help" ); end,
	onActivate	= function( item ) OutputMessageToScreenReader( item.text ); end,
	onClose		= CloseHelp,
	extraKeys	= LetterKeys(),
	ctrlKeys	= { [Keys.VK_TAB] = function() SwitchSection( -1 ); end },
};

-- Control+H (action KeyNavHelp): opens the help, or closes it when open.
function HubHelp.Toggle()
	if HubCore.IsModeOpen( "help" ) then CloseHelp(); return; end
	if not HubTargets.CanOpenMode( true ) then return; end
	m_data = HelpText_Build( CurrentBinding );
	-- Controller mode: the Controller section comes first, otherwise last (Gamepad.lua is written by the controller work: guarded)
	local pad = Gamepad;
	local padActive:boolean = ( pad ~= nil and pad.IsActive ~= nil and pad.IsActive() ) or false;
	for i, section in ipairs( m_data ) do
		if section.title == "Controller" then
			table.remove( m_data, i );
			if padActive then table.insert( m_data, 1, section ); else table.insert( m_data, section ); end
			break;
		end
	end
	m_section = 1;
	HubCore.OpenMode( "help", m_facade, "Accessibility help" );
end
