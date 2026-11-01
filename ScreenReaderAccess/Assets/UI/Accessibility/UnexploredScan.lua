-- ===========================================================================
--	UnexploredScan: where to explore next (category "Unexplored" of the places list, J; docs/features.md, Places list).
--	A sighted player sees the black edges of the map at a glance; this finds, for each of six directions around a reference plot,
--	the nearest frontier plot: a revealed passable land plot (a water plot for a ship) with an unrevealed neighbour.
--	Needs only Map, a visibility object and the plot objects, so test/lua/test_unexplored.lua runs it on a stub map.
--	The terrain of an unrevealed plot is never read (it would leak what the player has not seen): a land frontier next to
--	unrevealed ocean counts too.
-- ===========================================================================
UnexploredScan = {};

local ROOT3_2:number = 0.8660254;

-- By the angle from east, counter-clockwise, 60 degrees each.
UnexploredScan.SECTORS = { "east", "north-east", "north-west", "west", "south-west", "south-east" };
-- The order the items are listed in when they are equally far
UnexploredScan.ORDER = { ["north-east"] = 1, ["east"] = 2, ["south-east"] = 3, ["south-west"] = 4, ["west"] = 5, ["north-west"] = 6 };

UnexploredScan.NONE_TEXT = "No unexplored land next to known tiles";

-- 1 to 6 (an index into SECTORS) of plot B seen from plot A (real hex geometry, the shorter way around a wrapping map); nil for the same plot.
function UnexploredScan.SectorIndex( x1:number, y1:number, x2:number, y2:number )
	if x1 == x2 and y1 == y2 then return nil; end
	local width:number = Map.GetGridSize();
	local dx:number = ( x2 + ( ( y2 % 2 ) * 0.5 ) ) - ( x1 + ( ( y1 % 2 ) * 0.5 ) );
	if Map.IsWrapX() then
		if dx > width / 2 then dx = dx - width; elseif dx < -width / 2 then dx = dx + width; end
	end
	local dy:number = ( y2 - y1 ) * ROOT3_2;
	local angle:number = math.deg( math.atan2( dy, dx ) );		-- 0 = east, 90 = north
	if angle < 0 then angle = angle + 360; end
	return math.floor( ( ( angle + 30 ) % 360 ) / 60 ) + 1;
end

function UnexploredScan.Sector( x1:number, y1:number, x2:number, y2:number )
	local index:number = UnexploredScan.SectorIndex( x1, y1, x2, y2 );
	return index ~= nil and UnexploredScan.SECTORS[ index ] or nil;
end

-- "Unexplored north-east, nearest edge 7 tiles"
function UnexploredScan.Text( sector:string, distance:number )
	return "Unexplored " .. sector .. ", nearest edge " .. distance .. ( distance == 1 and " tile" or " tiles" );
end

local function Neighbour( plot:table, dx:number, dy:number )
	local x:number = plot:GetX() + dx;
	if Map.IsWrapX() then
		local width:number = Map.GetGridSize();
		x = x % width;
	end
	local other:table = Map.GetPlot( x, plot:GetY() + dy );
	if other ~= nil and Map.GetPlotDistance( plot:GetX(), plot:GetY(), other:GetX(), other:GetY() ) == 1 then return other; end
	return nil;
end

-- A revealed plot a unit of that kind can stand on (naval: water; land: not water, mountain or impassable) with an unrevealed neighbour.
function UnexploredScan.IsFrontier( plot:table, vis:table, naval:boolean )
	if not vis:IsRevealed( plot:GetIndex() ) then return false; end
	if naval then
		if not plot:IsWater() or plot:IsImpassable() then return false; end
	elseif plot:IsWater() or plot:IsMountain() or plot:IsImpassable() then
		return false;
	end
	for dy = -1, 1 do
		for dx = -1, 1 do
			if dx ~= 0 or dy ~= 0 then
				local other:table = Neighbour( plot, dx, dy );
				if other ~= nil and not vis:IsRevealed( other:GetIndex() ) then return true; end
			end
		end
	end
	return false;
end

-- The nearest frontier plot in each of the six directions around (refX, refY): { { sector, x, y, index, distance } } nearest first
-- (equal distances: north-east, east, south-east, south-west, west, north-west). The map is searched in growing squares around the
-- reference and the search stops as soon as every direction has its nearest plot (a plot outside the square of radius r is at least r
-- tiles away), so a map that is explored all around the reference costs a few rings; a direction without any frontier costs the whole map.
-- Call it once per opening of the list, never per frame.
function UnexploredScan.Find( refX:number, refY:number, vis:table, naval:boolean )
	local result:table = {};
	if vis == nil then return result; end
	local width:number, height:number = Map.GetGridSize();
	local limit:number = Map.IsWrapX() and math.max( math.floor( width / 2 ) + 1, height ) or math.max( width, height );
	local best:table = {};
	local found:number = 0;
	local function Consider( px:number, py:number )
		if Map.IsWrapX() then px = px % width; end
		local plot:table = Map.GetPlot( px, py );
		if plot == nil then return; end
		local sector:number = UnexploredScan.SectorIndex( refX, refY, plot:GetX(), plot:GetY() );
		if sector == nil then return; end
		local distance:number = Map.GetPlotDistance( refX, refY, plot:GetX(), plot:GetY() );
		local old:table = best[ sector ];
		if ( old == nil or distance < old.distance or ( distance == old.distance and plot:GetIndex() < old.index ) )
				and UnexploredScan.IsFrontier( plot, vis, naval ) then
			if old == nil then found = found + 1; end
			best[ sector ] = { sector = UnexploredScan.SECTORS[ sector ], x = plot:GetX(), y = plot:GetY(), index = plot:GetIndex(), distance = distance };
		end
	end
	for r = 0, limit do
		for dy = -r, r do
			if dy == -r or dy == r then
				for dx = -r, r do Consider( refX + dx, refY + dy ); end
			elseif r > 0 then
				Consider( refX - r, refY + dy );
				Consider( refX + r, refY + dy );
			end
		end
		if found == #UnexploredScan.SECTORS then
			local done:boolean = true;
			for _, entry in pairs( best ) do
				if entry.distance > r then done = false; end
			end
			if done then break; end
		end
	end
	for _, entry in pairs( best ) do table.insert( result, entry ); end
	table.sort( result, function( a, b )
		if a.distance ~= b.distance then return a.distance < b.distance; end
		return UnexploredScan.ORDER[ a.sector ] < UnexploredScan.ORDER[ b.sector ];
	end );
	return result;
end
