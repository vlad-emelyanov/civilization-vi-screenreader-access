-- ===========================================================================
--	KeyNavList: keyboard list navigation for in-game choosers (research, civics, production ...).
--
--	local m_list = KeyNavList_Create{
--		build      = function() return items; end,       -- called at key time: rebuild from the game's current state
--		isActive   = function() return panelIsOpen; end, -- the list only handles keys while this is true
--		onActivate = function(item) ... end,             -- Enter
--		onClose    = function() ... end,                 -- optional: Escape (otherwise left to the game's own handler)
--		onFocus    = function(item) ... end,             -- optional: the focus moved to this item (before it is spoken)
--		extraKeys  ={ [Keys.VK_DELETE] = function() ... end },   -- optional: more keys, acted on at KeyUp
--		horizontal = true,                                -- optional: Left/Right also move (like Up/Down)
--		enterGuard = 0.6,                                 -- optional: seconds after Open() during which Enter is ignored silently (a quick double Enter on Next Action must not pick the recommended item)
--	};
--	items: { key = <stable identity>, text = <spoken>, section = <optional group name>, detail = <string or function,
--	         spoken by Space>, choosable = <false: Enter says item.reason> }
--	m_list.Open( "Choose research" )     -- announces the title, the number of items and the focused item
--	m_list.HandleInput( pInputStruct )   -- call first thing in the context's input handler; returns true when it
--	                                     -- consumed the key (both KeyDown and KeyUp of the keys it uses are consumed)
--
--	Focus is tracked by item.key, never by index (the list is rebuilt from visible state on every key).
--	Up/Down act on KeyDown (so holding the key repeats), Enter/Space on KeyUp (the game's ActionPanel acts on the
--	KeyUp of Enter; consuming both keeps Next Action from firing).
-- ===========================================================================

include( "ScreenReader" );
include( "KeyboardNavigation" );

function KeyNavList_Create( config:table )
	local list:table = {};
	local m_focusKey = nil;
	local m_lastSection:string = nil;
	local m_openedAt:number = -100;

	local function Build()
		local items:table = {};
		local ok:boolean, result = xpcall( config.build, KeyNavErrorHandler );
		if ok then
			items = result or {};
		else
			print( "KeyNavList build error: " .. tostring(result) );
		end
		return items;
	end

	local function FindIndex( items:table )
		if m_focusKey ~= nil then
			for i, item in ipairs( items ) do
				if item.key == m_focusKey then return i; end
			end
		end
		return nil;
	end

	local function Speak( items:table, index:number, interrupt:boolean, withSection:boolean )
		local item:table = items[ index ];
		if item == nil then return; end
		m_focusKey = item.key;
		if config.onFocus ~= nil then
			local ok:boolean, err = xpcall( function() config.onFocus( item ); end, KeyNavErrorHandler );
			if not ok then print( "KeyNavList onFocus error: " .. tostring(err) ); end
		end
		local text:string = item.text;
		if item.section ~= nil and ( withSection or item.section ~= m_lastSection ) then
			text = item.section .. ": " .. text;
		end
		m_lastSection = item.section;
		OutputMessageToScreenReader( text .. ", " .. index .. " of " .. #items, not interrupt );
	end

	-- Announces the title and the focused item (the first, or the one that keeps its key from before).
	function list.Open( title:string, initialKey, silent:boolean )
		if UI ~= nil and UI.GetElapsedTime ~= nil then m_openedAt = UI.GetElapsedTime(); end
		local items:table = Build();
		m_lastSection = nil;
		if initialKey ~= nil then m_focusKey = initialKey; end
		local index:number = FindIndex( items );
		if #items == 0 then
			OutputMessageToScreenReader( title .. ", nothing available", true );
			return;
		end
		if index == nil then index = 1; m_focusKey = items[1].key; end
		if silent then return; end		-- the caller speaks (its own opening sentence)
		OutputMessageToScreenReader( title .. ", " .. #items .. ( #items == 1 and " option" or " options" ), true );
		Speak( items, index, false, true );
	end

	-- Moves the focus to the item with this key and speaks it (e.g. back to a slot after choosing in a sub-list).
	function list.Focus( key, prefix:string )
		local items:table = Build();
		m_focusKey = key;
		m_lastSection = nil;
		local index:number = FindIndex( items );
		if index == nil then index = 1; end
		if items[ index ] == nil then return; end
		if prefix ~= nil then OutputMessageToScreenReader( prefix, true ); end
		Speak( items, index, prefix == nil, true );
	end

	function list.GetFocusKey()
		return m_focusKey;
	end

	function list.Reset()
		m_focusKey = nil;
		m_lastSection = nil;
	end

	local function Move( delta:number, absolute )
		local items:table = Build();
		if #items == 0 then
			OutputMessageToScreenReader( "Nothing available" );
			return;
		end
		local index:number = FindIndex( items );
		local target:number;
		if absolute == "home" then
			target = 1;
		elseif absolute == "end" then
			target = #items;
		elseif index == nil then
			target = ( delta > 0 ) and 1 or #items;
		else
			target = index + delta;
			if target < 1 then target = #items; end
			if target > #items then target = 1; end
		end
		Speak( items, target, true, false );
	end

	-- The focused item may have vanished (list rebuilt from the game's state): say so and refocus.
	local function FocusLost( items:table )
		if #items == 0 then
			OutputMessageToScreenReader( "Nothing available" );
			return;
		end
		OutputMessageToScreenReader( "Item no longer available" );
		Speak( items, 1, false, true );
	end

	local function Activate()
		if config.enterGuard ~= nil and UI ~= nil and UI.GetElapsedTime ~= nil and UI.GetElapsedTime() - m_openedAt < config.enterGuard then return; end
		local items:table = Build();
		local index:number = FindIndex( items );
		if index == nil then FocusLost( items ); return; end
		local item:table = items[ index ];
		if item.choosable == false then
			OutputMessageToScreenReader( item.reason or "Can't choose this" );
			return;
		end
		config.onActivate( item );
	end

	local function ReadDetail()
		local items:table = Build();
		local index:number = FindIndex( items );
		if index == nil then FocusLost( items ); return; end
		local detail = items[ index ].detail;
		if type( detail ) == "function" then detail = detail(); end
		if detail == nil or detail == "" then detail = "No further details"; end
		OutputMessageToScreenReader( detail );
	end

	-- Returns true when the key was consumed.
	function list.HandleInput( input:table )
		if config.isActive ~= nil then
			local ok:boolean, active = xpcall( config.isActive, KeyNavErrorHandler );
			if not ok then
				print( "KeyNavList isActive error: " .. tostring(active) );
				return false;
			end
			if not active then return false; end
		end
		local msg:number = input:GetMessageType();
		if msg ~= KeyEvents.KeyDown and msg ~= KeyEvents.KeyUp then return false; end
		if input:IsShiftDown() or input:IsControlDown() or input:IsAltDown() then return false; end
		local key:number = input:GetKey();
		local isDown:boolean = ( msg == KeyEvents.KeyDown );

		local action = nil;
		if key == Keys.VK_UP then			if isDown then action = function() Move( -1 ); end end
		elseif key == Keys.VK_DOWN then		if isDown then action = function() Move( 1 ); end end
		elseif config.horizontal and key == Keys.VK_LEFT then	if isDown then action = function() Move( -1 ); end end
		elseif config.horizontal and key == Keys.VK_RIGHT then	if isDown then action = function() Move( 1 ); end end
		elseif key == Keys.VK_HOME then		if isDown then action = function() Move( 0, "home" ); end end
		elseif key == Keys.VK_END then		if isDown then action = function() Move( 0, "end" ); end end
		elseif key == Keys.VK_RETURN then	if not isDown then action = Activate; end
		elseif key == Keys.VK_SPACE then	if not isDown then action = ReadDetail; end
		elseif key == Keys.VK_ESCAPE and config.onClose ~= nil then
			if not isDown then action = config.onClose; end
		elseif config.extraKeys ~= nil and config.extraKeys[ key ] ~= nil then
			if not isDown then action = config.extraKeys[ key ]; end
		else
			return false;
		end

		if action ~= nil then
			local ok:boolean, err = xpcall( action, KeyNavErrorHandler );
			if not ok then print( "KeyNavList error: " .. tostring(err) ); end
		end
		return true;
	end

	return list;
end

-- "a, b, c and 2 more" from an array of strings.
function KeyNavList_ShortList( names:table, maxShown:number )
	maxShown = maxShown or 4;
	if #names <= maxShown then return table.concat( names, ", " ); end
	local shown:table = {};
	for i = 1, maxShown do shown[i] = names[i]; end
	return table.concat( shown, ", " ) .. " and " .. ( #names - maxShown ) .. " more";
end
