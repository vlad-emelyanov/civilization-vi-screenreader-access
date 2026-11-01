-- ===========================================================================
--	TradeText: pure text and ordering helpers for the trade route choosers (Choosers/TradeRouteChooser.lua,
--	Choosers/TradeOriginChooser.lua). Plain data in, strings out; the choosers read the game's state.
--
--	route: { name, owner = "yours" | civilization name | "city-state", distance, yields = { { name, amount } },
--	         pressure = { name, amount } | nil, tradingPost, quest, previous }
--	TradeText_Route( route )              "Bologna, city-state, 12 tiles, plus 4 Gold, plus 1 Science, trading post, quest"
--	TradeText_YieldList( yields )         "plus 4 Gold, plus 1 Science" ("" when none)
--	TradeText_SortRoutes( routes )        best first: sum of the yield amounts descending, then distance, then name
--	TradeText_Detail( d )                 d: { tooltip, theirName, theirYields, pathLength, passCities = { "Rome" }, hazards = { { name, distance } } }
--	TradeText_PassText( cities )          "Passes through Rome and Antium" ("" when none)
--	TradeText_HazardText( hazards )       "Passes 2 tiles from a Barbarian Camp, 1 tile from 2 Barbarian Warriors" ("" when none)
--	TradeText_Origin( city )              city: { name, distance } -> "Florence, 5 tiles"
-- ===========================================================================

-- N while "Start trade route to X?" is asked: "Enter confirms the route to Rome, Escape cancels" (keys are passed in: SRKey tokens).
function TradeText_WhatsNext( name:string, enterKey:string, escapeKey:string )
	return enterKey .. " confirms the route to " .. name .. ", " .. escapeKey .. " goes back to the list";
end

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

function TradeText_PassText( cities:table )
	if cities == nil or #cities == 0 then return ""; end
	if #cities == 1 then return "Passes through " .. cities[1]; end
	return "Passes through " .. table.concat( cities, ", ", 1, #cities - 1 ) .. " and " .. cities[ #cities ];
end

-- hazards: { { name = "Barbarian Camp", distance = 2 } ... }, one entry per sighted thing; the same name counts once per nearest distance.
function TradeText_HazardText( hazards:table )
	if hazards == nil or #hazards == 0 then return ""; end
	local groups:table, order:table = {}, {};
	for _, h in ipairs( hazards ) do
		local key:string = h.name .. "@" .. h.distance;
		if groups[ key ] == nil then
			groups[ key ] = { name = h.name, distance = h.distance, count = 0 };
			table.insert( order, groups[ key ] );
		end
		groups[ key ].count = groups[ key ].count + 1;
	end
	table.sort( order, function( a, b )
		if a.distance ~= b.distance then return a.distance < b.distance; end
		return a.name < b.name;
	end );
	local parts:table = {};
	for _, g in ipairs( order ) do
		local what:string = ( g.count == 1 ) and ( ( string.find( g.name, "^[AEIOUaeiou]" ) and "an " or "a " ) .. g.name ) or ( g.count .. " " .. g.name .. "s" );
		local where:string = ( g.distance == 0 ) and "on the path: " or ( Tiles( g.distance ) .. " from " );
		table.insert( parts, where .. what );
	end
	return "Passes " .. table.concat( parts, ", " );
end

function TradeText_Detail( d:table )
	local parts:table = {};
	if d.tooltip ~= nil and d.tooltip ~= "" then table.insert( parts, d.tooltip ); end
	local theirs:string = TradeText_YieldList( d.theirYields );
	if theirs ~= "" then
		table.insert( parts, ( d.theirName ~= nil and ( d.theirName .. " gets: " ) or "They get: " ) .. theirs );
	end
	if d.pathLength ~= nil and d.pathLength > 0 then table.insert( parts, "Path " .. Tiles( d.pathLength ) ); end
	local pass:string = TradeText_PassText( d.passCities );
	if pass ~= "" then table.insert( parts, pass ); end
	local hazard:string = TradeText_HazardText( d.hazards );
	if hazard ~= "" then table.insert( parts, hazard ); end
	return table.concat( parts, ". " );
end

function TradeText_Origin( city:table )
	return city.name .. ", " .. Tiles( city.distance );
end
