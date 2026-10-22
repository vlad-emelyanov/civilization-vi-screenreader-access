-- ===========================================================================
--	TradeText: pure text and ordering helpers for the trade route choosers (Choosers/TradeRouteChooser.lua,
--	Choosers/TradeOriginChooser.lua). Plain data in, strings out; the choosers read the game's state.
--
--	route: { name, owner = "yours" | civilization name | "city-state", distance, yields = { { name, amount } },
--	         pressure = { name, amount } | nil, tradingPost, quest, previous }
--	TradeText_Route( route )              "Bologna, city-state, 12 tiles, plus 4 Gold, plus 1 Science, trading post, quest"
--	TradeText_YieldList( yields )         "plus 4 Gold, plus 1 Science" ("" when none)
--	TradeText_SortRoutes( routes )        best first: sum of the yield amounts descending, then distance, then name
--	TradeText_Detail( d )                 d: { tooltip, theirName, theirYields, pathLength }
--	TradeText_Origin( city )              city: { name, distance } -> "Florence, 5 tiles"
-- ===========================================================================

local function Tiles( n:number )
	return n .. ( n == 1 and " tile" or " tiles" );
end

local function Signed( amount:number )
	local rounded:number = math.floor( math.abs( amount ) * 10 + 0.5 ) / 10;
	return ( amount < 0 and "minus " or "plus " ) .. tostring( rounded );
end

function TradeText_YieldList( yields:table )
	local parts:table = {};
	for _, y in ipairs( yields or {} ) do
		if y.amount ~= 0 then table.insert( parts, Signed( y.amount ) .. " " .. y.name ); end
	end
	return table.concat( parts, ", " );
end

local function YieldSum( route:table )
	local sum:number = 0;
	for _, y in ipairs( route.yields or {} ) do sum = sum + y.amount; end
	return sum;
end

function TradeText_Route( route:table )
	local parts:table = { route.name, route.owner, Tiles( route.distance ) };
	local yields:string = TradeText_YieldList( route.yields );
	if yields ~= "" then table.insert( parts, yields ); end
	if route.pressure ~= nil and route.pressure.amount > 0 then
		table.insert( parts, "pressure " .. route.pressure.amount .. " " .. route.pressure.name );
	end
	if route.tradingPost then table.insert( parts, "trading post" ); end
	if route.quest then table.insert( parts, "quest" ); end
	if route.previous then table.insert( parts, "previous route" ); end
	return table.concat( parts, ", " );
end

function TradeText_SortRoutes( routes:table )
	table.sort( routes, function( a, b )
		local sa:number, sb:number = YieldSum( a ), YieldSum( b );
		if sa ~= sb then return sa > sb; end
		if a.distance ~= b.distance then return a.distance < b.distance; end
		return a.name < b.name;
	end );
	return routes;
end

function TradeText_Detail( d:table )
	local parts:table = {};
	if d.tooltip ~= nil and d.tooltip ~= "" then table.insert( parts, d.tooltip ); end
	local theirs:string = TradeText_YieldList( d.theirYields );
	if theirs ~= "" then
		table.insert( parts, ( d.theirName ~= nil and ( d.theirName .. " gets: " ) or "They get: " ) .. theirs );
	end
	if d.pathLength ~= nil and d.pathLength > 0 then table.insert( parts, "Path " .. Tiles( d.pathLength ) ); end
	return table.concat( parts, ". " );
end

function TradeText_Origin( city:table )
	return city.name .. ", " .. Tiles( city.distance );
end
