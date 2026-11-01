-- ===========================================================================
--	ProductionText: pure wording helpers for the production panel (Panels/ProductionPanel.lua).
--	No engine calls: test/lua/test_productiontext.lua checks the wording.
-- ===========================================================================

-- "Currently building Coal Power Plant, 3 turns" (turns may be nil).
function ProductionText_Current( name:string, turns:string )
	local text:string = "Currently building " .. name;
	if turns ~= nil and turns ~= "" then text = text .. ", " .. turns; end
	return text;
end

-- "Renaissance Walls, replaces Coal Power Plant" (oldName nil or equal to name: unchanged).
function ProductionText_Replaces( text:string, oldName:string, name:string )
	if oldName == nil or oldName == "" or oldName == name then return text; end
	return text .. ", replaces " .. oldName;
end

-- A unit cannot be bought (built) because a unit of its formation class already stands in the city:
-- "Archer stands in Rome". others: { { formation = "FORMATION_CLASS_LAND_COMBAT", name = "Archer" }, ... } on the city plot.
-- Returns nil when none of them shares the class (the failure is something else).
-- withWayOut: adds what to do about it ("Archer stands in Rome: move it out or upgrade it first").
function ProductionText_StackBlocker( formation:string, cityName:string, others:table, withWayOut )
	if formation == nil then return nil; end
	for _, other in ipairs( others or {} ) do
		if other.formation == formation and other.name ~= nil and other.name ~= "" then
			return other.name .. " stands in " .. ( cityName or "the city" ) .. ( withWayOut and ( formation == "FORMATION_CLASS_CIVILIAN" and ": move it out first" or ": move it out or upgrade it first" ) or "" );
		end
	end
	return nil;
end

-- The identity of a list item across the production and purchase tabs ("buy:unit:123" and "unit:123" are the same unit).
function ProductionText_Identity( key:string )
	if key == nil then return nil; end
	return ( string.gsub( key, "^buy:", "" ) );
end

-- ---------------------------------------------------------------------------
-- The list order of the production panel: repairs on top, then only what can be built (or bought), then one toggle item;
-- the hidden items follow the toggle as the section "Unavailable" when the player switched them on.
-- items: the panel's items in the game's category order; fields used: section, choosable, repair (a repair item),
-- cantAfford (purchase item that is only short of funds: stays visible, after the affordable ones of its section).
-- ---------------------------------------------------------------------------
local PRODUCTION_TOGGLE_KEY = "toggle:unavailable";
local PRODUCTION_SECTION_REPAIRS = "Repairs";
local PRODUCTION_SECTION_UNAVAILABLE = "Unavailable";

local function ProductionText_Count( count:number )
	return count .. ( count == 1 and " unavailable item" or " unavailable items" );
end

-- "Show 14 unavailable items" / "Hide 14 unavailable items"; Space: what the toggle does.
function ProductionText_Toggle( count:number, shown:boolean, purchase:boolean )
	return {
		key = PRODUCTION_TOGGLE_KEY,
		toggle = true,
		uncounted = true,
		count = count,
		choosable = true,
		text = ( shown and "Hide " or "Show " ) .. ProductionText_Count( count ),
		detail = purchase and "Lists the items this city cannot buy now, with the reason" or "Lists the items this city cannot build now, with the reason",
	};
end

-- Said after Enter on the toggle.
function ProductionText_ToggleSaid( count:number, shown:boolean )
	if shown then return "Showing " .. ProductionText_Count( count ); end
	return "Unavailable items hidden";
end

function ProductionText_Arrange( items:table, showUnavailable:boolean, purchase:boolean )
	local repairs:table = {};
	local visible:table = {};
	local hidden:table = {};
	for _, item in ipairs( items ) do
		if item.repair then
			item.section = PRODUCTION_SECTION_REPAIRS;
			table.insert( repairs, item );
		elseif item.choosable ~= false or item.cantAfford then
			table.insert( visible, item );
		else
			table.insert( hidden, item );
		end
	end
	local result:table = {};
	for _, item in ipairs( repairs ) do table.insert( result, item ); end
	if purchase then
		-- inside each section the affordable items come first (a stable partition per run of one section)
		local i:number = 1;
		while i <= #visible do
			local j:number = i;
			while j < #visible and visible[ j + 1 ].section == visible[ i ].section do j = j + 1; end
			for k = i, j do if visible[ k ].choosable ~= false then table.insert( result, visible[ k ] ); end end
			for k = i, j do if visible[ k ].choosable == false then table.insert( result, visible[ k ] ); end end
			i = j + 1;
		end
	else
		for _, item in ipairs( visible ) do table.insert( result, item ); end
	end
	if #hidden > 0 then
		-- the toggle belongs to the group before it (hidden) or opens the "Unavailable" group (shown), so Up and PageUp treat it like a member
		local toggle:table = ProductionText_Toggle( #hidden, showUnavailable, purchase );
		toggle.section = showUnavailable and PRODUCTION_SECTION_UNAVAILABLE or ( #result > 0 and result[ #result ].section or nil );
		table.insert( result, toggle );
		if showUnavailable then
			for _, item in ipairs( hidden ) do
				item.section = PRODUCTION_SECTION_UNAVAILABLE;
				table.insert( result, item );
			end
		end
	end
	return result, #hidden;
end

-- ---------------------------------------------------------------------------
-- Corps and armies (units with a Corps / Army button in the game's row) and the queue entries of the Queue tab.
-- ---------------------------------------------------------------------------

-- "Warrior Corps" / "Destroyer Fleet": the unit name and the game's formation suffix (LOC_UNITFLAG_*_SUFFIX).
function ProductionText_FormationName( name:string, suffix:string )
	if suffix == nil or suffix == "" then return name; end
	return name .. " " .. suffix;
end

-- A corps / army row: "Warrior Corps, 12 turns, 180 production" (progress: "40 of 180 production").
function ProductionText_FormationRow( name:string, turns:string, cost:number, progress:number )
	local parts:table = { name };
	if turns ~= nil and turns ~= "" then table.insert( parts, turns ); end
	if cost ~= nil and cost > 0 then
		local costText:string = tostring( cost );
		if progress ~= nil and progress > 0 then costText = progress .. " of " .. costText; end
		table.insert( parts, costText .. " production" );
	end
	return table.concat( parts, ", " );
end

-- Identity of a queue entry: its type plus which occurrence of that type it is (the same unit can be queued twice).
function ProductionText_QueueKey( typeKey:string, occurrence:number )
	return "queue:" .. tostring( typeKey ) .. ":" .. tostring( occurrence );
end

-- "Library" (queued) / "Library, in production, 5 turns" (the head of the queue).
function ProductionText_QueueItem( name:string, current:boolean, turns:string )
	if not current then return name; end
	local text:string = name .. ", in production";
	if turns ~= nil and turns ~= "" then text = text .. ", " .. turns; end
	return text;
end

-- Where a queue item goes with Alt+Up (delta -1) / Alt+Down (+1); position 0-based, size = entries.
-- Returns the new 0-based position, or nil and "Already first" / "Already last".
function ProductionText_QueueTarget( position:number, delta:number, size:number )
	local target:number = position + delta;
	if target < 0 then return nil, "Already first"; end
	if target >= size then return nil, "Already last"; end
	return target;
end

-- "Library moved to 1 of 3" (position 0-based).
function ProductionText_QueueMoved( name:string, position:number, size:number )
	return name .. " moved to " .. ( position + 1 ) .. " of " .. size;
end

-- "Library removed from the queue, 2 left" / "... Queue empty, nothing in production".
function ProductionText_QueueRemoved( name:string, left:number )
	if left <= 0 then return name .. " removed from the queue. Queue empty, nothing in production"; end
	return name .. " removed from the queue, " .. left .. " left";
end

-- The 0-based position to focus after the item at `position` was removed and `left` entries remain (nil: none left).
function ProductionText_QueueFocusAfterRemove( position:number, left:number )
	if left <= 0 then return nil; end
	if position > left - 1 then return left - 1; end
	return position;
end

-- Reason line for a building whose required building is pillaged: "Library is pillaged, repair it first".
function ProductionText_PillagedPrereq( prereqName )
	return prereqName .. " is pillaged, repair it first";
end
