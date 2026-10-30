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
--		ctrlKeys   = { [Keys.VK_TAB] = function() ... end },    -- optional: Control+key (acted on at KeyUp; Shift+Tab is Steam's overlay, so Control+Tab = previous)
--		horizontal = true,                                -- optional: Left/Right also move (like Up/Down)
--		noDetailHint = true,                              -- optional: no pad-only ", Y for details" after the first item when the list opens
--		sectionCounts = true,                             -- optional: a group's item count is spoken when the focus enters it ("Warrior, in Units, 12 items, 3 of 40"; a group jump: "Units, 12: Warrior ...")
--		tabEdge    = function(step) return bool end,      -- optional: true when the sections cannot go further in that direction (+1 / -1); the hub then moves the LB / RB ring on
--		wheel      = true,                                -- optional: the pad's wheel (hold LT, point the left stick) works here; short lists of the main interface only
--		enterGuard = 0.6,                                 -- optional: seconds after Open() during which Enter is ignored silently (a quick double Enter on Next Action must not pick the recommended item)
--	};
--	items: { key = <stable identity>, text = <spoken>, section = <optional group name>, uncounted = <true: not counted in its group's count>, detail = <string or function,
--	         spoken by Space>, choosable = <false: Enter says item.reason> }
--	m_list.Open( "Choose research" )     -- announces the title, the number of items and the focused item
--	m_list.HandleInput( pInputStruct )   -- call first thing in the context's input handler; returns true when it
--	                                     -- consumed the key (both KeyDown and KeyUp of the keys it uses are consumed)
--
--	Entering a new group by Up / Down / Home / End speaks the item first and the group after it ("Settler, 5 turns, in Units, 7 of 40"; an item that
--	already starts with its group name stays whole: "Builder, 5 tiles east, 3 items, 2 of 9"). PageUp / PageDown, Tab to another section, Focus() and
--	Open() keep the group name first ("Units, 12: Warrior ...").
--	Focus is tracked by item.key, never by index (the list is rebuilt from visible state on every key).
--	PageUp / PageDown (the pad: a held bumper plus up / down) jump to the first item of the previous / next group (item.section) and are
--	always consumed ("No groups in this list"), so PageDown never opens the Climate screen underneath.
--	In controller mode (Gamepad.Follow) D-pad up / down (Home / End) are Up / Down, D-pad right / left (Tab / Control+Tab) are Right /
--	Left, LB / RB are Control+Tab / Tab ("No tabs here" when the list has no Tab handler): Gamepad.TranslateListKey.
--	The pad's wheel (hold LT, point the left stick; Shift+F13..F24 / Control+Shift+F13..F24, Gamepad.WheelOf), in lists with wheel = true:
--	jumps to the item in that direction, the items spread clockwise around the wheel from straight up (Gamepad.WheelIndex); the same
--	item is not spoken twice in a row (the first wheel key after any other key always speaks, even the focused item). Other lists consume the wheel keys and say "No wheel in this list" once per sweep.
--	Up/Down act on KeyDown (so holding the key repeats), Enter/Space on KeyUp (the game's ActionPanel acts on the
--	KeyUp of Enter; consuming both keeps Next Action from firing).
-- ===========================================================================

include( "ScreenReader" );
include( "KeyboardNavigation" );
include( "SRListen" );
include( "Gamepad" );

-- Pure. The index of the first item of the next (delta > 0) or previous (delta < 0) group, a group being a run of items with the same
-- item.section. Wraps. Returns nil, "none" when no item has a section and nil, "one" when there is only one group.
function KeyNavList_GroupTarget( items:table, index:number, delta:number )
	local starts:table = {};
	local previous = nil;
	for i, item in ipairs( items ) do
		if item.section ~= nil and item.section ~= previous then table.insert( starts, i ); end
		previous = item.section;
	end
	if #starts == 0 then return nil, "none"; end
	if #starts == 1 then return nil, "one"; end
	local current:number = 0;
	for g, start in ipairs( starts ) do
		if start <= index then current = g; end
	end
	if delta > 0 then
		return starts[ current + 1 ] or starts[ 1 ];
	end
	if current == 0 then return starts[ #starts ]; end
	return starts[ current - 1 ] or starts[ #starts ];
end

function KeyNavList_Create( config:table )
	local list:table = {};
	Gamepad.Follow();
	local m_focusKey = nil;
	local m_lastSection:string = nil;
	local m_openedAt:number = -100;
	local m_lostGuard:boolean = false;		-- focusLostSafe: the focus was moved after a loss; the next Enter only reads it
	local m_wheelSpoken = nil;				-- key of the item the PREVIOUS key (a wheel key) spoke; any other speech clears it
	local m_wheelRefused:boolean = false;	-- "No wheel in this list" was said; again only after another key

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

	local function Speak( items:table, index:number, interrupt:boolean, withSection:boolean, padHint:boolean )
		local item:table = items[ index ];
		if item == nil then return; end
		m_focusKey = item.key;
		m_wheelSpoken = nil;
		if config.onFocus ~= nil then
			local ok:boolean, err = xpcall( function() config.onFocus( item ); end, KeyNavErrorHandler );
			if not ok then print( "KeyNavList onFocus error: " .. tostring(err) ); end
		end
		local text:string = item.text;
		if item.section ~= nil and ( withSection or item.section ~= m_lastSection ) then
			local count:number = 0;
			if config.sectionCounts then
				for _, other in ipairs( items ) do
					if other.section == item.section and not other.uncounted then count = count + 1; end
				end
			end
			-- the item names its own group ("Builder, 5 tiles east"): say it once
			local own:string = item.text;
			local selfNamed:boolean = string.lower( string.sub( own, 1, #item.section + 2 ) ) == string.lower( item.section ) .. ", ";
			local countText:string = count .. ( count == 1 and " item" or " items" );
			if withSection then
				-- the player asked for the group (PageUp / PageDown, Tab, opening): the group name first
				local head:string = item.section;
				if config.sectionCounts then head = head .. ", " .. count; end
				if selfNamed then text = string.sub( own, #item.section + 3 ); end
				text = head .. ": " .. text;
			else
				-- scrolling into a new group: the item first (a fast scroller must not miss it), the group after it
				if not selfNamed then text = text .. ", in " .. item.section; end
				if config.sectionCounts then text = text .. ", " .. countText; end
			end
		end
		m_lastSection = item.section;
		text = text .. ", " .. index .. " of " .. #items;
		if padHint and not config.noDetailHint then
			-- first announcement after open only: the pad user learns that Y reads the details (keyboard speech unchanged)
			local detail = item.detail;
			if type( detail ) == "function" then
				local ok:boolean, result = xpcall( detail, KeyNavErrorHandler );
				detail = ok and result or nil;
			end
			if detail ~= nil and detail ~= "" then text = text .. SRPadHint( ", Y for details" ); end
		end
		OutputMessageToScreenReader( text, not interrupt );
	end

	-- Announces the title and the focused item (the first, or the one that keeps its key from before).
	-- queueTitle: the title waits behind what is being spoken (a result line just before the reopen); default: it interrupts.
	function list.Open( title:string, initialKey, silent:boolean, keepGuard:boolean, queueTitle:boolean )
		if not keepGuard and UI ~= nil and UI.GetElapsedTime ~= nil then m_openedAt = UI.GetElapsedTime(); end
		Gamepad.RequestMode();
		m_wheelSpoken = nil;
		local items:table = Build();
		m_lastSection = nil;
		if initialKey ~= nil then m_focusKey = initialKey; end
		local index:number = FindIndex( items );
		if #items == 0 then
			OutputMessageToScreenReader( title .. ", nothing available", queueTitle == true );
			return;
		end
		if index == nil then index = 1; m_focusKey = items[1].key; end
		if silent then return; end		-- the caller speaks (its own opening sentence)
		OutputMessageToScreenReader( title .. ", " .. #items .. ( #items == 1 and " option" or " options" ), queueTitle == true );
		Speak( items, index, false, true, true );
	end

	-- A deliberate key (Tab to another tab) ends the Enter guard: the Enter that follows is meant.
	function list.DisarmGuard()
		m_openedAt = -1000;
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
		m_wheelSpoken = nil;
		m_focusKey = nil;
		m_lastSection = nil;
	end

	local function Move( delta:number, absolute )
		m_lostGuard = false;
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

	-- The pad's wheel pointed at a slot: the item in that direction (silent only when the previous key was a wheel key that already spoke this item).
	local function WheelPick( slot:number )
		m_lostGuard = false;
		local items:table = Build();
		if #items == 0 then
			OutputMessageToScreenReader( "Nothing available" );
			return;
		end
		local target:number = Gamepad.WheelIndex( slot, #items );
		if items[ target ].key == m_wheelSpoken and FindIndex( items ) == target then return; end		-- the stick lingers in the slot
		Speak( items, target, true, false );
		m_wheelSpoken = items[ target ].key;
	end

	-- PageUp / PageDown: the first item of the previous / next group, spoken with its group name.
	local function GroupJump( delta:number )
		m_lostGuard = false;
		local items:table = Build();
		if #items == 0 then
			OutputMessageToScreenReader( "Nothing available" );
			return;
		end
		local target, why = KeyNavList_GroupTarget( items, FindIndex( items ) or 1, delta );
		if target == nil then
			OutputMessageToScreenReader( why == "one" and "Only one group in this list" or "No groups in this list" );
			return;
		end
		Speak( items, target, true, true );
	end

	-- Sections: does the list have a Tab handler, and can it not go further in that direction (the hub's ring takes over then)?
	function list.HasTabs()
		return config.extraKeys ~= nil and config.extraKeys[ Keys.VK_TAB ] ~= nil;
	end

	function list.AtTabEdge( step:number )
		if config.tabEdge == nil then return false; end
		local ok:boolean, edge = xpcall( function() return config.tabEdge( step ); end, KeyNavErrorHandler );
		return ok and edge == true;
	end

	-- The focused item may have vanished (list rebuilt from the game's state): say so and refocus.
	local function FocusLost( items:table )
		if #items == 0 then
			OutputMessageToScreenReader( "Nothing available" );
			return;
		end
		local said:string = "Item no longer available";
		if config.focusLostText ~= nil then
			-- optional: a more specific text (which item, why); nil keeps the generic one
			local ok:boolean, text = xpcall( function() return config.focusLostText( m_focusKey ); end, KeyNavErrorHandler );
			if ok and text ~= nil and text ~= "" then said = text; end
		end
		if config.focusLostSafe then
			-- the focus moved on its own: name where it landed and make the next Enter harmless
			m_lostGuard = true;
			m_focusKey = items[1].key;
			m_lastSection = items[1].section;
			if config.onFocus ~= nil then
				local okF:boolean, errF = xpcall( function() config.onFocus( items[1] ); end, KeyNavErrorHandler );
				if not okF then print( "KeyNavList onFocus error: " .. tostring(errF) ); end
			end
			OutputMessageToScreenReader( said .. ". Now on: " .. items[1].text );
			return;
		end
		OutputMessageToScreenReader( said );
		Speak( items, 1, false, true );
	end

	local function Activate()
		if config.enterGuard ~= nil and UI ~= nil and UI.GetElapsedTime ~= nil and UI.GetElapsedTime() - m_openedAt < config.enterGuard then return; end
		local items:table = Build();
		local index:number = FindIndex( items );
		if index == nil then FocusLost( items ); return; end
		local item:table = items[ index ];
		if m_lostGuard then
			m_lostGuard = false;
			OutputMessageToScreenReader( item.text .. ". " .. SRKey( "Enter" ) .. " again to choose it" );
			return;
		end
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
		m_wheelSpoken = nil;
		OutputMessageToScreenReader( detail );
	end

	-- Returns true when the key was consumed.
	function list.HandleInput( input:table )
		local msg:number = input:GetMessageType();
		if msg ~= KeyEvents.KeyDown and msg ~= KeyEvents.KeyUp then return false; end
		local rawKey = input:GetKey();
		Gamepad.NoteModeKey( rawKey, input:IsControlDown(), input:IsShiftDown() );		-- (no hub in the front end: F22 / F23 are seen here)
		if config.isActive ~= nil then
			local ok:boolean, active = xpcall( config.isActive, KeyNavErrorHandler );
			if not ok then
				print( "KeyNavList isActive error: " .. tostring(active) );
				return false;
			end
			if not active then return false; end
		end
		local isDown:boolean = ( msg == KeyEvents.KeyDown );
		local slot:number = Gamepad.WheelOf( rawKey, input:IsControlDown(), input:IsShiftDown() );
		if slot == nil and isDown and rawKey ~= Keys.VK_SHIFT and rawKey ~= Keys.VK_CONTROL and rawKey ~= Keys.VK_ALT then m_wheelRefused = false; end
		if slot ~= nil and not config.wheel then
			if isDown and not m_wheelRefused then
				m_wheelRefused = true;
				OutputMessageToScreenReader( "No wheel in this list" );
			end
			return true;
		end
		if slot ~= nil then
			if isDown then
				local ok:boolean, err = xpcall( function() WheelPick( slot ); end, KeyNavErrorHandler );
				if not ok then print( "KeyNavList wheel error: " .. tostring(err) ); end
			end
			return true;
		end
		local key = rawKey;
		local isControl:boolean = input:IsControlDown();
		local bumper:boolean = false;
		if not input:IsShiftDown() and not input:IsAltDown() then
			key, isControl, bumper = Gamepad.TranslateListKey( rawKey, isControl, Gamepad.IsActive() );
		end
		if bumper then
			-- LB / RB are the previous / next section: a list without a Tab handler says so (never silent)
			local handler = ( isControl and config.ctrlKeys or config.extraKeys );
			if handler == nil or handler[ Keys.VK_TAB ] == nil then
				if not isDown then
					local other = ( isControl and config.extraKeys or config.ctrlKeys );
					local hasOther:boolean = other ~= nil and other[ Keys.VK_TAB ] ~= nil;
					OutputMessageToScreenReader( hasOther and ( isControl and "No previous tab" or "No next tab" ) or "No tabs here" );
				end
				return true;
			end
		end
		if isControl and not input:IsShiftDown() and not input:IsAltDown() and config.ctrlKeys ~= nil and config.ctrlKeys[ key ] ~= nil then
			if not isDown then
				local ok:boolean, err = xpcall( config.ctrlKeys[ key ], KeyNavErrorHandler );
				if not ok then print( "KeyNavList error: " .. tostring(err) ); end
			end
			return true;
		end
		if input:IsShiftDown() or isControl or input:IsAltDown() then return false; end

		local action = nil;
		if key == Keys.VK_UP then			if isDown then action = function() Move( -1 ); end end
		elseif key == Keys.VK_DOWN then		if isDown then action = function() Move( 1 ); end end
		elseif config.horizontal and key == Keys.VK_LEFT then	if isDown then action = function() Move( -1 ); end end
		elseif config.horizontal and key == Keys.VK_RIGHT then	if isDown then action = function() Move( 1 ); end end
		elseif key == Keys.VK_HOME then		if isDown then action = function() Move( 0, "home" ); end end
		elseif key == Keys.VK_END then		if isDown then action = function() Move( 0, "end" ); end end
		elseif key == Gamepad.PageKey( false ) then	if isDown then action = function() GroupJump( -1 ); end end
		elseif key == Gamepad.PageKey( true ) then	if isDown then action = function() GroupJump( 1 ); end end
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
