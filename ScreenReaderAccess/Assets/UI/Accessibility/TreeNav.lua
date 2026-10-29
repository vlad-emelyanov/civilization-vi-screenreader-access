-- ===========================================================================
--	TreeNav: keyboard navigation + speech for the tech tree and the civics tree (TechTree.lua / CivicsTree.lua).
--
--	The tree is read era by era: Left/Right (Tab / Control+Tab) switch eras, Up/Down move through the era's nodes in the
--	tree's column order. The two screens differ only in their data, so each screen copy builds an adapter:
--
--	local nav = TreeNav_Create{
--		name        = "Tech tree",                      -- opening word
--		closedText  = "Tech tree closed",
--		toggleKey   = Keys.T,                           -- also closes the screen (the game's own toggle hotkey)
--		isShown     = function() return not ContextPtr:IsHidden(); end,
--		entries     = function() return { { key, name, era, eraName, column, row }, ... } end,   -- every node
--		item        = function(key) return info for TreeText_Item end,
--		detail      = function(key) return string end,  -- Space
--		current     = function() return key end,        -- what is being researched, or nil
--		currentLine = function() return "Researching Archery, 5 turns" end,
--		idleText    = "Not researching anything",   -- optional: J when nothing is in progress
--		request     = function(key, append) return ok, reasonText end,   -- sets the target (path queued) / appends
--		prereqs     = function(key) return { keys } end,   -- optional: direct prerequisites; with itemWord ("tech" / "civic") Enter on a
--		                                                   blocked node says how many nodes and turns the path takes and what comes next
--		queue       = function() return { keys = {}, names = {}, turns = n } end,   -- read back after a request
--		search      = function(text) return key or nil end,         -- optional fallback after the name match (full text)
--		beginSearch = function(onCommit) end,           -- puts the screen's search box in edit mode; onCommit(text)
--		close       = function() end,                   -- the screen's own Close()
--		scroll      = function(key) end,                -- optional: scroll the sighted view to the node
--		resourceKind = "tech" | "civic",                -- optional: node text says which resources near my cities the node improves
--		                                                   (ResourceTech.lua) and R lists those nodes, cheapest first (Up/Down, Enter sets the
--		                                                   target like Enter on a node, Shift+Enter queues, Escape leaves the list)
--	};
--	nav.Open()                  -- announces (call when the screen was opened)
--	nav.Closed()                -- the screen is gone (any reason): drops pending work
--	nav.QueueChanged()          -- the research / civic queue changed (settles a pending request)
--	nav.HandleInput(input)      -- first thing in the input handler; true = consumed (every key while shown)
--	nav.Update(deltaTime)       -- from ContextPtr:SetUpdate
-- ===========================================================================

include( "ScreenReader" );
include( "KeyboardNavigation" );
include( "KeyNavEditBox" );
include( "Gamepad" );
include( "TreeText" );
include( "ResourceTech" );

local REQUEST_TIMEOUT:number = 1.5;		-- seconds to wait for the queue-changed event before reading the queue anyway
local REQUEST_SETTLE:number = 0.25;		-- seconds of quiet after the last queue-changed event
local SEARCH_DELAY:number = 0.3;		-- the edit box announces "Search set to ..." first

function TreeNav_Create( a:table )
	local nav:table = {};
	local m_focusKey = nil;
	local m_pending = nil;		-- { key, append, wait, settle }
	local m_search = nil;		-- { text, wait }
	local m_resGroups = nil;	-- ResourceTech_Scan result, read once per opening of the screen (the map does not change meanwhile)
	local m_resList = nil;		-- { groups, index } while the R list is open

	local function Say( text:string )
		OutputMessageToScreenReader( text, false );
	end

	local function Groups()
		local ok:boolean, result = xpcall( a.entries, KeyNavErrorHandler );
		if not ok then
			print( "TreeNav entries error: " .. tostring( result ) );
			return {};
		end
		return TreeText_Group( result or {} );
	end

	-- eraIndex, itemIndex of the focus (nil when it is not in the tree any more)
	local function Locate( groups:table )
		if m_focusKey == nil then return nil, nil; end
		for gi, g in ipairs( groups ) do
			for ii, e in ipairs( g.items ) do
				if e.key == m_focusKey then return gi, ii; end
			end
		end
		return nil, nil;
	end

	local function ResourceGroups( fresh:boolean )
		if a.resourceKind == nil then return {}; end
		if m_resGroups == nil or fresh then
			local ok:boolean, result = pcall( ResourceTech_Scan, a.resourceKind );
			if not ok then print( "TreeNav resources error: " .. tostring( result ) ); result = {}; end
			m_resGroups = result;
		end
		return m_resGroups;
	end

	local function ItemLine( key, index:number, count:number )
		local ok:boolean, info = xpcall( function() return a.item( key ); end, KeyNavErrorHandler );
		local text:string = "?";
		if ok and info ~= nil then text = TreeText_Item( info ); else print( "TreeNav item error: " .. tostring( info ) ); end
		if ok and info ~= nil and info.status ~= "researched" and info.status ~= "unrevealed" then
			local phrase = ResourceTech_NodePhrase( ResourceGroups( false ), key );
			if phrase ~= nil then text = text .. ", " .. phrase; end
		end
		return text .. ", " .. index .. " of " .. count;
	end

	-- Moves the focus to groups[gi].items[ii] and speaks it (with the era when withEra).
	-- "Target: Political Philosophy, about 26 turns" when the queue goes beyond the current research, else nil.
	local function TargetLine()
		local ok:boolean, q = xpcall( a.queue, KeyNavErrorHandler );
		if not ok or q == nil or #q.keys < 2 then return nil; end
		return TreeText_TargetSuffix( q.names[ #q.names ], q.turns );
	end

	local function FocusAt( groups:table, gi:number, ii:number, withEra:boolean, prefix, suffix )
		local g:table = groups[ gi ];
		local e:table = g.items[ ii ];
		m_focusKey = e.key;
		if a.scroll ~= nil then pcall( a.scroll, e.key ); end
		local text:string = ItemLine( e.key, ii, #g.items );
		if withEra then text = TreeText_Era( g.name, gi, #groups ) .. ". " .. text; end
		if prefix ~= nil then text = prefix .. text; end
		if suffix ~= nil then text = text .. ". " .. suffix; end
		Say( text );
	end

	local function FirstUnresearchedEra( groups:table )
		for gi, g in ipairs( groups ) do
			for _, e in ipairs( g.items ) do
				local ok:boolean, info = pcall( a.item, e.key );
				if ok and info ~= nil and info.status ~= "researched" then return gi; end
			end
		end
		return #groups;
	end

	function nav.Open()
		local groups:table = Groups();
		m_pending = nil;
		m_search = nil;
		m_resList = nil;
		m_resGroups = nil;
		if #groups == 0 then
			Say( a.name .. ", nothing available" );
			return;
		end
		local gi = nil;
		local curKey = a.current();
		if curKey ~= nil then
			for i, g in ipairs( groups ) do
				for _, e in ipairs( g.items ) do
					if e.key == curKey then gi = i; end
				end
			end
		end
		if gi == nil then gi = FirstUnresearchedEra( groups ); end
		local g:table = groups[ gi ];
		m_focusKey = g.items[1].key;
		if a.scroll ~= nil then pcall( a.scroll, m_focusKey ); end
		local cur:string = a.currentLine();
		local target = TargetLine();
		if target ~= nil then cur = cur .. ". " .. target; end
		Say( a.name .. ". " .. cur .. ". " .. TreeText_Era( g.name, gi, #groups ) .. ". " .. ItemLine( m_focusKey, 1, #g.items ) );
	end

	function nav.Closed()
		m_pending = nil;
		m_search = nil;
		m_resList = nil;
		m_resGroups = nil;
		m_focusKey = nil;
		KeyNavEditBox_Cancel();
	end

	local function MoveItem( delta:number, absolute )
		local groups:table = Groups();
		if #groups == 0 then Say( "Nothing available" ); return; end
		local gi, ii = Locate( groups );
		if gi == nil then
			gi = 1; ii = 0;
			if absolute == nil and delta < 0 then ii = 1; end
		end
		local n:number = #groups[ gi ].items;
		if absolute == "home" then ii = 1;
		elseif absolute == "end" then ii = n;
		else
			ii = ii + delta;
			if ii < 1 then ii = n; end
			if ii > n then ii = 1; end
		end
		FocusAt( groups, gi, ii, false );
	end

	local function MoveEra( delta:number )
		local groups:table = Groups();
		if #groups == 0 then Say( "Nothing available" ); return; end
		local gi = Locate( groups );
		if gi == nil then gi = 1; end
		local target:number = gi + delta;
		if target < 1 then Say( "First era" ); return; end
		if target > #groups then Say( "Last era" ); return; end
		FocusAt( groups, target, 1, true );
	end

	local function FocusKey( key, prefix, suffix )
		local groups:table = Groups();
		for gi, g in ipairs( groups ) do
			for ii, e in ipairs( g.items ) do
				if e.key == key then FocusAt( groups, gi, ii, true, prefix, suffix ); return true; end
			end
		end
		return false;
	end

	local function ReadDetail()
		if m_focusKey == nil then Say( "Nothing selected" ); return; end
		local key = m_focusKey;
		local ok:boolean, text = xpcall( function() return a.detail( key ); end, KeyNavErrorHandler );
		if not ok then print( "TreeNav detail error: " .. tostring( text ) ); text = nil; end
		if text == nil or text == "" then text = "No further details"; end
		Say( text );
	end

	local function Target( append:boolean, forKey )
		if forKey ~= nil then m_focusKey = forKey; end
		if m_focusKey == nil then Say( "Nothing selected" ); return; end
		local key = m_focusKey;
		-- a node that cannot be researched yet: count the path before the request changes the queue
		local far = nil;
		if a.prereqs ~= nil and a.itemWord ~= nil then
			local okp:boolean, path = pcall( function()
				local info = a.item( key );
				if info == nil or info.status ~= "blocked" then return nil; end
				return TreeText_Path( key, a.prereqs, function( k )
					local i = a.item( k );
					return i ~= nil and i.status == "researched";
				end );
			end );
			if okp and path ~= nil and #path > 0 then
				-- standalone estimates of nodes that are not queued yet: summed (the queue read back later replaces this)
				local turns:number = 0;
				for _, k in ipairs( path ) do
					local okt:boolean, i = pcall( a.item, k );
					if okt and i ~= nil and i.turns ~= nil then turns = turns + i.turns; end
				end
				far = { count = #path, turns = turns };
			end
		end
		local before = nil;		-- the research in progress before the request: Enter on a far target may replace it
		local okb:boolean, cur = pcall( a.current );
		if okb then before = cur; end
		local ok:boolean, done, reason = xpcall( function() return a.request( key, append ); end, KeyNavErrorHandler );
		if not ok then
			print( "TreeNav request error: " .. tostring( done ) );
			Say( "Could not set the target" );
			return;
		end
		if not done then
			Say( reason or "Can't choose this" );
			return;
		end
		m_pending = { key = key, append = append, wait = REQUEST_TIMEOUT, settle = nil, far = far, before = before };
	end

	-- The request went out: say what the player's own queue now holds.
	local function FinishRequest()
		local p = m_pending;
		m_pending = nil;
		if p == nil then return; end
		local ok:boolean, q = xpcall( a.queue, KeyNavErrorHandler );
		if not ok or q == nil then print( "TreeNav queue error: " .. tostring( q ) ); q = { keys = {}, names = {}, turns = 0 }; end
		local queueRead:boolean = ok and #q.keys > 0;		-- the queue the game built beats the path computed from the tree
		local found:boolean = false;
		for _, k in ipairs( q.keys ) do
			if k == p.key then found = true; end
		end
		local name:string = "";
		local beforeName:string = nil;
		for _, g in ipairs( Groups() ) do
			for _, e in ipairs( g.items ) do
				if e.key == p.key then name = e.name; end
				if p.before ~= nil and e.key == p.before then beforeName = e.name; end
			end
		end
		local replaced = nil;
		if beforeName ~= nil and q.keys[1] ~= nil and q.keys[1] ~= p.before and q.keys[1] ~= p.key then replaced = beforeName; end
		-- exclusive: the target ends the queue; appended: it is somewhere in it
		if found and ( p.append or q.keys[ #q.keys ] == p.key ) then
			if p.far ~= nil and p.append then
				Say( TreeText_FarQueued( name, a.itemWord, p.far.count, p.far.turns ) );
			elseif p.far ~= nil then
				-- "Next" is read back: whatever the game now has first in the queue
				Say( TreeText_FarTarget( name, a.itemWord, queueRead and #q.keys or p.far.count, queueRead and q.turns or p.far.turns, q.names[1], q.each ~= nil and q.each[1] or nil, replaced ) );
			else
				Say( TreeText_Queue( p.append and "Added to queue" or "Target", name, q.names, q.turns ) );
			end
		else
			Say( "Could not set " .. name .. " as the target" );
		end
	end

	local function JumpToCurrent()
		local key = a.current();
		if key == nil then Say( a.idleText or "Not researching anything" ); return; end
		FocusKey( key, "Current: ", TargetLine() );
	end

	local function ReadQueue()
		local ok:boolean, q = xpcall( a.queue, KeyNavErrorHandler );
		if not ok or q == nil or #q.names == 0 then Say( "The queue is empty" ); return; end
		local text:string = "Queue: " .. table.concat( q.names, ", " );
		if q.turns ~= nil and q.turns > 0 then text = text .. ", " .. TreeText_Turns( q.turns ); end
		Say( text );
	end

	local function BeginSearch()
		a.beginSearch( function( text )
			m_search = { text = text, wait = SEARCH_DELAY };
		end );
	end

	local function RunSearch( text:string )
		local flat:table = {};
		for _, g in ipairs( Groups() ) do
			for _, e in ipairs( g.items ) do table.insert( flat, e ); end
		end
		local hit = TreeText_Match( flat, text );
		local key = nil;
		if hit ~= nil then
			key = hit.key;
		elseif a.search ~= nil then
			local ok:boolean, found = pcall( a.search, text );
			if ok then key = found; end
		end
		if key == nil or not FocusKey( key, "Found: " ) then
			Say( "No match for " .. text );
		end
	end

	-- R: the nodes that improve resources near my cities, cheapest first
	local function ResSay()
		local g:table = m_resList.groups[ m_resList.index ];
		m_focusKey = g.type;
		if a.scroll ~= nil then pcall( a.scroll, g.type ); end
		Say( ResourceTech_GroupText( g ) .. ", " .. m_resList.index .. " of " .. #m_resList.groups );
	end

	local function OpenResources()
		if a.resourceKind == nil then return; end
		local groups:table = ResourceGroups( true );
		if #groups == 0 then
			Say( "No unimproved resources near your cities wait for a " .. ( a.resourceKind == "tech" and "tech" or "civic" ) );
			return;
		end
		m_resList = { groups = groups, index = 1 };
		Say( "Resources to unlock, " .. #groups .. ". " .. SRKey( "Up and Down" ) .. ", " .. SRKey( "Enter" ) .. " sets the target, " .. SRKey( "Escape" ) .. " leaves" );
		ResSay();
	end

	local function ResKey( key:number, isDown:boolean, shift:boolean, padX:boolean )
		if key == Keys.VK_UP or key == Keys.VK_DOWN then
			if not isDown then return; end
			local n:number = #m_resList.groups;
			m_resList.index = ( m_resList.index - 1 + ( key == Keys.VK_UP and -1 or 1 ) ) % n + 1;
			ResSay();
		elseif key == Keys.VK_HOME or key == Keys.VK_END then
			if not isDown then return; end
			m_resList.index = ( key == Keys.VK_HOME ) and 1 or #m_resList.groups;
			ResSay();
		elseif key == Keys.VK_RETURN or padX then
			if isDown then return; end
			local g:table = m_resList.groups[ m_resList.index ];
			m_resList = nil;
			Target( shift or padX, g.type );		-- controller X = Shift+Enter, queue
		elseif key == Keys.VK_ESCAPE or key == Keys.R then
			if isDown then return; end
			m_resList = nil;
			Say( "Back in the tree" );
		end
	end

	local function Close()
		nav.Closed();
		a.close();
		Say( a.closedText );
	end

	function nav.QueueChanged()
		if m_pending ~= nil then m_pending.settle = REQUEST_SETTLE; end
	end

	local function Guarded( fn, label:string )
		local ok:boolean, err = xpcall( fn, KeyNavErrorHandler );
		if not ok then print( "TreeNav " .. label .. " error: " .. tostring( err ) ); end
	end

	function nav.Update( deltaTime:number )
		KeyNavEditBox_Update( deltaTime );
		if m_search ~= nil then
			m_search.wait = m_search.wait - deltaTime;
			if m_search.wait <= 0 then
				local text = m_search.text;
				m_search = nil;
				Guarded( function() RunSearch( text ); end, "search" );
			end
		end
		if m_pending ~= nil then
			if m_pending.settle ~= nil then
				m_pending.settle = m_pending.settle - deltaTime;
				if m_pending.settle <= 0 then Guarded( FinishRequest, "result" ); end
			else
				m_pending.wait = m_pending.wait - deltaTime;
				if m_pending.wait <= 0 then Guarded( FinishRequest, "result" ); end
			end
		end
	end

	-- Returns true when the key was consumed: all keyboard events while the screen is shown.
	function nav.HandleInput( input:table )
		if not a.isShown() then return false; end
		local handled = KeyNavEditBox_HandleInput( input );
		if handled ~= nil then return handled; end
		local msg:number = input:GetMessageType();
		input = Gamepad.WrapInput( input );		-- controller mode: D-pad = arrows (up / down one item), LB / RB = eras
		if msg ~= KeyEvents.KeyDown and msg ~= KeyEvents.KeyUp then return false; end
		if input:IsAltDown() then return false; end
		local key:number = input:GetKey();
		local isDown:boolean = ( msg == KeyEvents.KeyDown );
		local ctrl:boolean = input:IsControlDown();
		local shift:boolean = input:IsShiftDown();
		local pad = Gamepad.ButtonOf( key, ctrl, shift );		-- X, LT, RT; the right stick is the same F-keys with Control

		local action = nil;
		if m_resList ~= nil then
			Guarded( function() ResKey( key, isDown, shift, pad == "X" ); end, "resources" );
			return true;
		end
		if key == Keys.VK_UP then			if isDown then action = function() MoveItem( -1 ); end end
		elseif key == Keys.VK_DOWN then		if isDown then action = function() MoveItem( 1 ); end end
		elseif key == Keys.VK_LEFT then		if isDown then action = function() MoveEra( -1 ); end end
		elseif key == Keys.VK_RIGHT then	if isDown then action = function() MoveEra( 1 ); end end
		elseif key == Keys.VK_TAB then		if isDown then action = function() MoveEra( ( ctrl or shift ) and -1 or 1 ); end end
		elseif key == Keys.VK_HOME then		if isDown then action = function() MoveItem( 0, "home" ); end end
		elseif key == Keys.VK_END then		if isDown then action = function() MoveItem( 0, "end" ); end end
		elseif key == Keys.VK_RETURN then	if not isDown then action = function() Target( shift ); end end
		elseif pad == "X" then	if not isDown then action = function() Target( true ); end end		-- controller X queues like Shift+Enter
		elseif key == Keys.VK_SPACE then	if not isDown then action = ReadDetail; end
		elseif key == Keys.J or pad == "LT" then			if not isDown then action = JumpToCurrent; end
		elseif key == Keys.F then			if not isDown then action = BeginSearch; end
		elseif key == Keys.Q or pad == "RT" then			if not isDown then action = ReadQueue; end
		elseif key == Keys.R and a.resourceKind ~= nil then	if not isDown then action = OpenResources; end
		elseif key == Keys.VK_ESCAPE or ( a.toggleKey ~= nil and key == a.toggleKey ) then
			if not isDown then action = Close; end
		end

		if action ~= nil then Guarded( action, "key" ); end
		return true;
	end

	return nav;
end

-- ===========================================================================
--	Engine helpers shared by the two screen copies. They read the screen's globals g_kItemDefaults / g_kEras
--	(item: Type, Name, Index, EraType, Column, UITreeRow, Prereqs, ...) and PREREQ_ID_TREE_START.
-- ===========================================================================

function TreeNav_ItemName( item:table )
	return CleanTextForSpeech( Locale.Lookup( item.Name ) );
end

-- One decimal ("4.2"), no trailing ".0"
function TreeNav_Round( n:number )
	local r:number = math.floor( n * 10 + 0.5 ) / 10;
	return r;
end

-- Every node of the screen's tree: isRevealed(item) -> boolean, hiddenName = text for nodes that are not revealed yet.
function TreeNav_Entries( isRevealed, hiddenName:string )
	local list:table = {};
	for typeName, item in pairs( g_kItemDefaults ) do
		local era = g_kEras[ item.EraType ];
		local name:string = hiddenName;
		if isRevealed( item ) then name = TreeNav_ItemName( item ); end
		table.insert( list, {
			key = typeName, name = name,
			era = ( era ~= nil ) and era.Index or 0,
			eraName = ( era ~= nil ) and era.Description or tostring( item.EraType ),
			column = item.Column, row = item.UITreeRow,
		} );
	end
	return list;
end

-- Names of the direct prerequisites, or only those for which done(prereqItem) is false.
-- revealed(prereqItem) (optional): an unrevealed prerequisite (Tech/Civic Shuffle) is not named.
function TreeNav_PrereqNames( item:table, done, revealed )
	local names:table = {};
	for _, prereq in ipairs( item.Prereqs ) do
		if prereq ~= PREREQ_ID_TREE_START and g_kItemDefaults[ prereq ] ~= nil then
			local p:table = g_kItemDefaults[ prereq ];
			if revealed ~= nil and not revealed( p ) then
				table.insert( names, "an unrevealed prerequisite" );
			elseif done == nil or not done( p ) then
				table.insert( names, TreeNav_ItemName( p ) );
			end
		end
	end
	return names;
end

-- Keys of the direct prerequisites (tree start excluded).
function TreeNav_PrereqKeys( typeName:string )
	local keys:table = {};
	local item:table = g_kItemDefaults[ typeName ];
	if item == nil then return keys; end
	for _, prereq in ipairs( item.Prereqs ) do
		if prereq ~= PREREQ_ID_TREE_START and g_kItemDefaults[ prereq ] ~= nil then table.insert( keys, prereq ); end
	end
	return keys;
end

-- Names of the nodes that list typeName as a prerequisite, in tree order. revealed(item) (optional): unrevealed nodes
-- (Tech/Civic Shuffle) are not named but counted: the second result is their number.
function TreeNav_LeadsTo( typeName:string, revealed )
	local found:table = {};
	for _, item in pairs( g_kItemDefaults ) do
		for _, prereq in ipairs( item.Prereqs ) do
			if prereq == typeName then table.insert( found, item ); end
		end
	end
	table.sort( found, function( a, b )
		local ea = g_kEras[ a.EraType ];
		local eb = g_kEras[ b.EraType ];
		local ia:number = ( ea ~= nil ) and ea.Index or 0;
		local ib:number = ( eb ~= nil ) and eb.Index or 0;
		if ia ~= ib then return ia < ib; end
		if a.Column ~= b.Column then return a.Column < b.Column; end
		return a.UITreeRow < b.UITreeRow;
	end );
	local names:table = {};
	local hidden:number = 0;
	for _, item in ipairs( found ) do
		if revealed ~= nil and not revealed( item ) then hidden = hidden + 1; else table.insert( names, TreeNav_ItemName( item ) ); end
	end
	return names, hidden;
end

-- unlockables as GetUnlockablesForTech_Cached / GetUnlockablesForCivic_Cached return them ({ typeName, nameTag, ... })
-- -> { { kind = "KIND_UNIT", name = "Archer" }, ... }; wonders are told from buildings.
function TreeNav_UnlockEntries( unlockables:table )
	local list:table = {};
	for _, u in ipairs( unlockables or {} ) do
		local typeName:string = u[1];
		local info = GameInfo.Types[ typeName ];
		local kind:string = ( info ~= nil ) and info.Kind or "";
		if kind == "KIND_BUILDING" then
			local building = GameInfo.Buildings[ typeName ];
			if building ~= nil and building.IsWonder then kind = "KIND_WONDER"; end
		end
		if u[2] ~= nil then table.insert( list, { kind = kind, name = CleanTextForSpeech( Locale.Lookup( u[2] ) ) } ); end
	end
	return list;
end

-- Position of id in a research / civic queue (ids as the game lists them), the item being worked on counting as 1.
function TreeNav_QueuePos( queue:table, currentId:number, id:number )
	local offset:number = 0;
	if currentId ~= nil and currentId >= 0 and queue[1] ~= currentId then offset = 1; end
	for i, qid in ipairs( queue ) do
		if qid == id then return i + offset; end
	end
	return nil;
end
