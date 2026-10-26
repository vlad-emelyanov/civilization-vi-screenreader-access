-- ===========================================================================
--	BlindSpots: pure helpers of the places list (J) for barbarian camps and vision (docs/beginner-guide-gaps.md G3c, G10).
--	Needs only Map (and the plot objects it returns) and a visibility object, so test/lua/test_blindspots.lua runs it on a stub map.
--
--	* Camp wording: "Barbarian Camp, 7 tiles north-east of Rome, guarded by Spearman (last seen 2 turns ago)".
--	* Blind spots: clusters (6-neighbour flood fill) of land plots 4 to 8 tiles from our cities that are revealed but not in view,
--	  and of unexplored plots within 6 tiles. Barbarian camps only appear where no one sees (and 4 tiles from a city).
--	  The terrain of an unexplored plot is not read (it would leak what we have not seen), so those clusters count every plot.
-- ===========================================================================
BlindSpots = {};

BlindSpots.MIN_BLIND		= 4;		-- blind spots: tiles from the nearest own city, from ... (BARBARIAN_CAMP_MINIMUM_DISTANCE_CITY)
BlindSpots.MAX_BLIND		= 8;		-- ... to
BlindSpots.MAX_UNEXPLORED	= 6;		-- unexplored plots within this many tiles of a city
BlindSpots.MIN_SIZE			= 4;		-- smallest cluster listed
BlindSpots.MAX_CLUSTERS		= 10;
BlindSpots.SPLIT_OVER		= 24;		-- a cluster bigger than this is cut by direction from the city

local function Plural( n:number, one:string, many:string ) return n .. " " .. ( n == 1 and one or many ); end

-- "this turn" / "1 turn ago" / "2 turns ago"
function BlindSpots.TurnsAgo( turns:number )
	if turns == nil or turns <= 0 then return "this turn"; end
	return Plural( turns, "turn", "turns" ) .. " ago";
end

-- Names of the units on a camp: "Spearman", "Spearman and Archer", "2 Spearman and Archer".
function BlindSpots.GuardList( names:table )
	local order:table, counts:table = {}, {};
	for _, name in ipairs( names ) do
		if counts[ name ] == nil then table.insert( order, name ); counts[ name ] = 0; end
		counts[ name ] = counts[ name ] + 1;
	end
	local parts:table = {};
	for _, name in ipairs( order ) do
		table.insert( parts, counts[ name ] > 1 and ( counts[ name ] .. " " .. name ) or name );
	end
	if #parts <= 1 then return parts[1] or ""; end
	return table.concat( parts, ", ", 1, #parts - 1 ) .. " and " .. parts[ #parts ];
end

-- The line of a remembered camp. guards: nil = nothing recorded (an old memory), {} = seen with nobody on it, else the names.
-- fogged: out of sight now, then turnsAgo is how long ago the guards were seen.
function BlindSpots.CampText( name:string, where:string, guards:table, fogged:boolean, turnsAgo:number )
	if guards == nil then
		return name .. ( fogged and ", last seen, " or ", " ) .. where;
	end
	local text:string = name .. ", " .. where;
	if #guards == 0 then
		if fogged then return text .. ", was not guarded (last seen " .. BlindSpots.TurnsAgo( turnsAgo ) .. ")"; end
		return text .. ", not guarded right now";
	end
	text = text .. ", guarded by " .. BlindSpots.GuardList( guards );
	if fogged then text = text .. " (last seen " .. BlindSpots.TurnsAgo( turnsAgo ) .. ")"; end
	return text;
end

-- Space on a camp: why to destroy it (gold: what the game's data says, nil = do not state an amount).
function BlindSpots.CampAdvice( gold:number )
	local reward:string = ( gold ~= nil and gold > 0 ) and ( "gives about " .. gold .. " gold" ) or "gives gold";
	return "Destroying it " .. reward .. " and stops raids from it. Fighting near it gives your units experience";
end

-- "Barbarian camp destroyed" with the gold when the treasury grew by it.
function BlindSpots.DestroyedText( gold:number, count:number )
	local what:string = ( count ~= nil and count > 1 ) and ( count .. " barbarian camps destroyed" ) or "Barbarian camp destroyed";
	if gold ~= nil and gold > 0 then return what .. ", " .. gold .. " gold"; end
	return what;
end

-- "Blind spot: 12 tiles out of sight, 5 tiles north of Antium"
function BlindSpots.SpotText( size:number, position:string )
	local text:string = "Blind spot: " .. Plural( size, "tile", "tiles" ) .. " out of sight";
	if position ~= nil and position ~= "" then text = text .. ", " .. position; end
	return text;
end

-- "8 unexplored tiles, 6 tiles west of Rome"
function BlindSpots.UnexploredText( size:number, position:string )
	local text:string = size .. " unexplored " .. ( size == 1 and "tile" or "tiles" );
	if position ~= nil and position ~= "" then text = text .. ", " .. position; end
	return text;
end

-- Space on a blind spot or unexplored area. cityDistance, campDistance: the game's minimum distances (nil: left out).
function BlindSpots.Advice( cityDistance:number, campDistance:number )
	local text:string = "Barbarians can appear where no one sees";
	if cityDistance ~= nil then
		text = text .. ": at least " .. Plural( cityDistance, "tile", "tiles" ) .. " from any city";
		if campDistance ~= nil then text = text .. " and " .. campDistance .. " from another camp"; end
	end
	return text .. ". Enter moves the cursor to the middle of it, M sends a unit, a unit on alert there keeps watch";
end

-- Plots 1 to 8 tiles from the cities, sorted into two lists:
--   blind:      revealed, not in view, land that a camp could stand on (not water, mountain or impassable), MIN_BLIND to MAX_BLIND tiles
--   unexplored: not revealed, up to MAX_UNEXPLORED tiles
-- cities: { { x, y, id } }; vis: PlayersVisibility[ player ]. Each entry { x, y, index, group, distance }; group = nearest city and
-- the direction from it, so that a ring of plots around a city becomes several clusters, each with a middle that makes sense.
-- One pass over the square around every city; a plot belongs to its nearest city.
function BlindSpots.Candidates( cities:table, vis:table )
	local blind:table, unexplored:table = {}, {};
	if vis == nil then return blind, unexplored; end
	local radius:number = math.max( BlindSpots.MAX_BLIND, BlindSpots.MAX_UNEXPLORED );
	local best:table = {};
	for _, city in ipairs( cities ) do
		for dy = -radius, radius do
			for dx = -radius, radius do
				local plot:table = Map.GetPlot( city.x + dx, city.y + dy );
				if plot ~= nil then
					local distance:number = Map.GetPlotDistance( city.x, city.y, plot:GetX(), plot:GetY() );
					if distance >= 1 and distance <= radius then
						local index:number = plot:GetIndex();
						local old:table = best[ index ];
						if old == nil or distance < old.distance then best[ index ] = { distance = distance, city = city, plot = plot }; end
					end
				end
			end
		end
	end
	local indices:table = {};
	for index in pairs( best ) do table.insert( indices, index ); end
	table.sort( indices );
	for _, index in ipairs( indices ) do
		local entry:table = best[ index ];
		local plot:table = entry.plot;
		local list:table = nil;
		if not vis:IsRevealed( index ) then
			if entry.distance <= BlindSpots.MAX_UNEXPLORED then list = unexplored; end
		elseif not vis:IsVisible( index ) and entry.distance >= BlindSpots.MIN_BLIND and entry.distance <= BlindSpots.MAX_BLIND
				and not plot:IsWater() and not plot:IsMountain() and not plot:IsImpassable() then
			list = blind;
		end
		if list ~= nil then
			local direction:string = PlotDescription_GetDirectionWord( entry.city.x, entry.city.y, plot:GetX(), plot:GetY() ) or "";
			table.insert( list, { x = plot:GetX(), y = plot:GetY(), index = index, distance = entry.distance, group = entry.city.id .. ":" .. direction } );
		end
	end
	return blind, unexplored;
end

-- The connected components (6 neighbours) of the candidates; sameGroup: only plots with the same group connect.
local function Components( cands:table, sameGroup:boolean )
	local byIndex:table = {};
	for _, c in ipairs( cands ) do byIndex[ c.index ] = c; end
	local seen:table = {};
	local result:table = {};
	for _, start in ipairs( cands ) do
		if not seen[ start.index ] then
			seen[ start.index ] = true;
			local members:table, stack:table = {}, { start };
			while #stack > 0 do
				local current:table = table.remove( stack );
				table.insert( members, current );
				for dy = -1, 1 do
					for dx = -1, 1 do
						local plot:table = ( dx ~= 0 or dy ~= 0 ) and Map.GetPlot( current.x + dx, current.y + dy ) or nil;
						if plot ~= nil and Map.GetPlotDistance( current.x, current.y, plot:GetX(), plot:GetY() ) == 1 then
							local other:table = byIndex[ plot:GetIndex() ];
							if other ~= nil and not seen[ other.index ] and ( not sameGroup or other.group == current.group ) then
								seen[ other.index ] = true;
								table.insert( stack, other );
							end
						end
					end
				end
			end
			table.insert( result, members );
		end
	end
	return result;
end

-- Clusters of the candidates (neighbouring plots, 6 neighbours): { size, x, y, index (the member nearest to the middle) },
-- largest first, at least minSize big, at most maxCount. A cluster of more than splitOver plots (a ring around a city, a whole
-- coast) is cut by group (the direction from the nearest city) so that each piece has a middle that is worth walking to.
function BlindSpots.Clusters( cands:table, minSize:number, maxCount:number, splitOver:number )
	splitOver = splitOver or BlindSpots.SPLIT_OVER;
	local pieces:table = {};
	for _, members in ipairs( Components( cands, false ) ) do
		if #members > splitOver then
			for _, part in ipairs( Components( members, true ) ) do table.insert( pieces, part ); end
		else
			table.insert( pieces, members );
		end
	end
	local clusters:table = {};
	for _, members in ipairs( pieces ) do
		if #members >= minSize then
			local sx:number, sy:number = 0, 0;
			for _, m in ipairs( members ) do sx = sx + m.x + ( m.y % 2 ) * 0.5; sy = sy + m.y; end
			sx, sy = sx / #members, sy / #members;
			local centre:table, centreDistance:number = nil, nil;
			for _, m in ipairs( members ) do
				local dx:number, dy:number = m.x + ( m.y % 2 ) * 0.5 - sx, m.y - sy;
				local d:number = dx * dx + dy * dy;
				if centreDistance == nil or d < centreDistance or ( d == centreDistance and m.index < centre.index ) then centre, centreDistance = m, d; end
			end
			table.insert( clusters, { size = #members, x = centre.x, y = centre.y, index = centre.index } );
		end
	end
	table.sort( clusters, function( a, b )
		if a.size ~= b.size then return a.size > b.size; end
		return a.index < b.index;
	end );
	while #clusters > maxCount do table.remove( clusters ); end
	return clusters;
end
