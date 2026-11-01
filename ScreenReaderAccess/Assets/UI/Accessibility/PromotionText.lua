-- ===========================================================================
--	PromotionText: spoken text for the unit promotion tree (UnitPromotionPopup). Pure functions, no engine calls.
--
--	A promotion is a table:
--		name, desc (already localized and cleaned), tier (number or nil),
--		state = "have" | "available" | "locked" | "unavailable",
--		needs = { "Tortoise", "Charge" }   -- for "locked": the prerequisites the unit lacks (any one of them unlocks it)
-- ===========================================================================

local function JoinOr( names:table )
	if #names == 0 then return ""; end
	if #names == 1 then return names[1]; end
	return table.concat( names, " or " );
end

function PromotionText_State( p:table )
	if p.state == "have" then return "have"; end
	if p.state == "available" then return "available"; end
	if p.state == "locked" then
		local needs:table = p.needs or {};
		if #needs > 0 then return "locked: needs " .. JoinOr( needs ); end
		return "locked";
	end
	return "not available now";
end

-- "Battlecry: +7 combat strength vs melee and ranged, tier 1, available"
function PromotionText_Item( p:table )
	local text:string = p.name;
	if p.desc ~= nil and p.desc ~= "" then text = text .. ": " .. p.desc; end
	if p.tier ~= nil then text = text .. ", tier " .. p.tier; end
	return text .. ", " .. PromotionText_State( p );
end

-- Space: the full description with the state and the prerequisites.
function PromotionText_Detail( p:table )
	local text:string = p.name;
	if p.tier ~= nil then text = text .. ", tier " .. p.tier; end
	if p.desc ~= nil and p.desc ~= "" then text = text .. ". " .. p.desc; end
	return text .. ". " .. PromotionText_State( p );
end

-- Enter on a promotion that can't be taken: why not.
function PromotionText_Reason( p:table )
	if p.state == "have" then return "Already have " .. p.name; end
	if p.state == "locked" then
		local needs:table = p.needs or {};
		if #needs > 0 then return p.name .. " is locked, needs " .. JoinOr( needs ); end
		return p.name .. " is locked";
	end
	if p.state == "unavailable" then return p.name .. " can't be taken now"; end
	return nil;
end

-- "Promote Swordsman: 2 available. Battlecry: ..., available, 1 of 5"
-- usesMoves: the unit still has moves, which a promotion uses up (said before Enter).
function PromotionText_Opening( unitName:string, available:number, itemText:string, index:number, total:number, usesMoves:boolean )
	local text:string = "Promote " .. unitName .. ": " .. available .. " available";
	if usesMoves then text = text .. ", promoting uses the unit's moves"; end
	if itemText ~= nil then text = text .. ". " .. itemText .. ", " .. index .. " of " .. total; end
	return text;
end

function PromotionText_Done( name:string )
	return "Promoted: " .. name;
end

-- The promotion key on a unit that picks from a random list (spy, apostle ...): the game shows a visual list, so the key says the choices
-- and where to choose. "Promote Spy: choose Cover Story, Disguise or Smooth Talker. Tab opens the list"
function PromotionText_Choices( unitName:string, names:table, tabKey:string )
	local list:string = "";
	if #names == 1 then
		list = names[1];
	elseif #names > 1 then
		local head:table = {};
		for i = 1, #names - 1 do head[i] = names[i]; end
		list = table.concat( head, ", " ) .. " or " .. names[#names];
	end
	return "Promote " .. unitName .. ": choose " .. list .. ". " .. tabKey .. " opens the list";
end

-- The promotion key while a spy's mission or destination list is open (it takes the keys): why nothing happens.
function PromotionText_ListOpen( destination:boolean, escapeKey:string )
	return "Close the " .. ( destination and "destination" or "mission" ) .. " list first, " .. escapeKey .. " closes it";
end
