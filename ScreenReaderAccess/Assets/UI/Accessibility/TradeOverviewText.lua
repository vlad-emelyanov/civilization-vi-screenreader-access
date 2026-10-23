-- ===========================================================================
--	TradeOverviewText: pure text helpers for the Trade Routes overview (F4, TradeOverview.lua). Plain data in, strings
--	out; the screen reads the game's state. Yield lists come from TradeText.
--
--	TradeOverviewText_Opening( d )   d: { used, capacity, tab, count, first, index }
--	                                 "Trade routes: 2 of 3 used. My routes, 2 routes. Rome to Bologna, ..., 1 of 2"
--	TradeOverviewText_Tab( tab, count )    "Routes to my cities, 3 routes" ("no routes" when 0)
--	TradeOverviewText_Route( r )     r: { origin, destination, owner, yields, turns, trader, tradingPost, pressure }
--	                                 "Rome to Bologna, 4 turns left, plus 4 Gold, plus 1 Science, trading post"
--	TradeOverviewText_Slot( s )      s: { trader = "Rome" | nil } "Unused route slot, idle trader in Rome"
--	TradeOverviewText_Detail( d )    d: { tooltip, theirName, theirYields, distance, tradingPost, trader }
-- ===========================================================================

include( "TradeText" );

local function Routes( n:number )
	if n == 0 then return "no routes"; end
	return n .. ( n == 1 and " route" or " routes" );
end

function TradeOverviewText_Tab( tab:string, count:number )
	return tab .. ", " .. Routes( count );
end

-- d.short: a tab switch (leaves out the "Trade routes: 2 of 3 used" head); d.total: the list length when it differs
-- from the route count (unused slots are list items too)
function TradeOverviewText_Opening( d:table )
	local text:string = TradeOverviewText_Tab( d.tab, d.count );
	if not d.short then
		local head:string = "Trade routes";
		if d.used ~= nil and d.capacity ~= nil then head = head .. ": " .. d.used .. " of " .. d.capacity .. " used"; end
		text = head .. ". " .. text;
	end
	if d.first ~= nil then text = text .. ". " .. d.first .. ", " .. ( d.index or 1 ) .. " of " .. ( d.total or d.count ); end
	return text;
end

local function Turns( n:number )
	return n .. ( n == 1 and " turn left" or " turns left" );
end

function TradeOverviewText_Route( r:table )
	local parts:table = { r.origin .. " to " .. r.destination };
	if r.owner ~= nil and r.owner ~= "" then table.insert( parts, r.owner ); end
	if r.distance ~= nil then table.insert( parts, r.distance .. ( r.distance == 1 and " tile" or " tiles" ) ); end
	if r.turns ~= nil then table.insert( parts, Turns( r.turns ) ); end
	local yields:string = TradeText_YieldList( r.yields );
	if yields ~= "" then table.insert( parts, yields ); end
	if r.pressure ~= nil and r.pressure.amount > 0 then
		table.insert( parts, "pressure " .. r.pressure.amount .. " " .. r.pressure.name );
	end
	if r.tradingPost then table.insert( parts, "trading post" ); end
	if r.trader ~= nil and r.trader ~= "" then table.insert( parts, r.trader ); end
	return table.concat( parts, ", " );
end

function TradeOverviewText_Slot( s:table )
	if s.trader ~= nil then
		return "Unused route slot, idle trader in " .. s.trader;
	end
	return "Unused route slot, no idle trader";
end

function TradeOverviewText_Detail( d:table )
	local parts:table = {};
	if d.tooltip ~= nil and d.tooltip ~= "" then table.insert( parts, d.tooltip ); end
	local theirs:string = TradeText_YieldList( d.theirYields );
	if theirs ~= "" then
		table.insert( parts, ( d.theirName ~= nil and ( d.theirName .. " gets: " ) or "They get: " ) .. theirs );
	end
	if d.distance ~= nil then
		table.insert( parts, "Distance " .. d.distance .. ( d.distance == 1 and " tile" or " tiles" ) );
	end
	if d.tradingPost ~= nil then
		table.insert( parts, d.tradingPost and "Trading post established" or "No trading post yet" );
	end
	if d.trader ~= nil and d.trader ~= "" then table.insert( parts, d.trader ); end
	return table.concat( parts, ". " );
end
