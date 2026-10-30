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
