-- HubEnemies.lua: "what did the enemies near me do" at the start of our turn.
-- At the end of our turn every visible hostile unit near us (barbarians, civilizations at war with us; within 6 tiles of
-- one of our cities or 3 tiles of one of our units) is written to a snapshot. The next turn start compares it with what
-- is visible now and speaks ONE line: "Enemies: Barbarian Swordsman moved 2 tiles toward Sivas, now 3 tiles east of
-- Sivas; Barbarian Horseman new, 4 tiles north of Istanbul; Barbarian Scout out of sight." Killed units are left to
-- the combat lines. Only units we really see count (never fogged positions). The wording is pure (Describe).

HubEnemies = {};

local CITY_RADIUS:number = 6;
local UNIT_RADIUS:number = 3;
local MAX_LISTED:number = 4;

HubEnemies.m_killed = {};		-- "owner:id" of units killed in combat since the snapshot
HubEnemies.m_snapshot = nil;		-- { turn = n, units = { ["owner:id"] = entry } } of the last turn end

local function Plural( n:number ) return n == 1 and "tile" or "tiles"; end

local function HealthText( entry:table )
	return ( entry.maxhp - entry.damage ) .. " of " .. entry.maxhp;
end

-- ===========================================================================
-- Pure wording. An entry: { name, x, y, damage, maxhp, where (spoken position), anchorName, anchorX, anchorY,
-- near (distance to the anchor, for sorting), mine (stands in our territory) }.
-- old/new: key -> entry; dead: key -> true for units killed in combat; seen: key -> true for hostile units visible now
-- but not near (they get "no longer near", the others "out of sight"). dist(x1, y1, x2, y2) = tiles.
-- Returns "Enemies: ..." or nil when there is nothing to say.
-- ===========================================================================
function HubEnemies.Describe( old:table, new:table, dead:table, dist, seen:table )
	local items:table = {};
	for key, e in pairs( new ) do
		local before:table = old[ key ];
		local text:string = nil;
		local changed:boolean = true;
		if before == nil then
			text = e.name .. " new, " .. e.where;
			if e.mine then text = text .. ", in your territory"; end
		else
			local moved:number = dist( before.x, before.y, e.x, e.y );
			if moved > 0 then
				text = e.name .. " moved " .. moved .. " " .. Plural( moved );
				if e.anchorX ~= nil then
					local was:number = dist( before.x, before.y, e.anchorX, e.anchorY );
					local now:number = dist( e.x, e.y, e.anchorX, e.anchorY );
					if now < was then text = text .. " toward " .. e.anchorName;
					elseif now > was then text = text .. " away from " .. e.anchorName; end
				end
				text = text .. ", now " .. e.where;
				if e.mine then text = text .. ", in your territory"; end
			else
				text = e.name .. " still " .. e.where;
				changed = false;
			end
			if e.damage > before.damage then
				text = text .. ", wounded, " .. HealthText( e );
				changed = true;
			elseif e.damage < before.damage then
				text = text .. ", healed, " .. HealthText( e );
				changed = true;
			end
		end
		table.insert( items, { text = text, near = e.near or 99, changed = changed, key = key } );
	end
	for key, e in pairs( old ) do
		if new[ key ] == nil and not dead[ key ] then
			local what:string = ( seen ~= nil and seen[ key ] ) and " no longer near" or " out of sight";
			table.insert( items, { text = e.name .. what, near = e.near or 99, changed = true, key = key } );
		end
	end
	if #items == 0 then return nil; end
	table.sort( items, function( a, b )
		if a.near ~= b.near then return a.near < b.near; end
		return a.key < b.key;
	end );
	-- units that did not change are only worth a word when there is little else to say
	if #items > 2 then
		local kept:table = {};
		for _, item in ipairs( items ) do if item.changed then table.insert( kept, item ); end end
		items = kept;
	end
	if #items == 0 then return nil; end
	local parts:table = {};
	for i = 1, math.min( #items, MAX_LISTED ) do table.insert( parts, items[i].text ); end
	local text:string = "Enemies: " .. table.concat( parts, "; " );
	if #items > MAX_LISTED then text = text .. "; and " .. ( #items - MAX_LISTED ) .. " more"; end
	return text .. ".";
end

-- ===========================================================================
-- Gathering (engine)
-- ===========================================================================
local function Dist( x1:number, y1:number, x2:number, y2:number )
	return Map.GetPlotDistance( x1, y1, x2, y2 );
end

-- Visible hostile units near us: key -> entry.
function HubEnemies.Gather()
	local result:table, seen:table = {}, {};
	local localID:number = Game.GetLocalPlayer();
	local me:table = Players[ localID ];
	if me == nil or localID == -1 then return result, seen; end
	local anchors:table = {};
	for _, city in me:GetCities():Members() do
		table.insert( anchors, { name = Locale.Lookup( city:GetName() ), x = city:GetX(), y = city:GetY(), radius = CITY_RADIUS, city = true } );
	end
	for _, unit in me:GetUnits():Members() do
		table.insert( anchors, { name = "your " .. Locale.Lookup( unit:GetName() ), x = unit:GetX(), y = unit:GetY(), radius = UNIT_RADIUS } );
	end
	if #anchors == 0 then return result, seen; end
	for id = 0, 63 do
		if id ~= localID and Players[ id ] ~= nil and HubCore.IsHostile( id ) then
			for _, unit in Players[ id ]:GetUnits():Members() do
				if PlotDescription_IsUnitVisible( unit ) then
					local x:number, y:number = unit:GetX(), unit:GetY();
					seen[ id .. ":" .. unit:GetID() ] = true;
					local best:table, bestDistance:number = nil, 99;
					for _, a in ipairs( anchors ) do
						local d:number = Dist( x, y, a.x, a.y );
						if d <= a.radius and ( d < bestDistance or ( d == bestDistance and a.city and not best.city ) ) then best, bestDistance = a, d; end
					end
					if best ~= nil then
						local plot:table = Map.GetPlot( x, y );
						local where:string;
						if bestDistance == 0 then
							where = "in " .. best.name;
						else
							local relative:string = PlotDescription_GetRelative( Map.GetPlot( best.x, best.y ), plot );
							where = ( relative or "near" ) .. " of " .. best.name;
						end
						result[ id .. ":" .. unit:GetID() ] = {
							name = PlotDescription_GetUnitName( unit ), x = x, y = y, owner = id, id = unit:GetID(),
							damage = unit:GetDamage(), maxhp = unit:GetMaxDamage(), where = where,
							anchorName = best.name, anchorX = best.x, anchorY = best.y, near = bestDistance,
							mine = plot ~= nil and plot:GetOwner() == localID,
						};
					end
				end
			end
		end
	end
	return result, seen;
end

-- A unit died in combat (UnitKilledInCombat): not "out of sight" at the next turn start.
function HubEnemies.OnUnitKilledInCombat( killedPlayer:number, killedId:number )
	HubEnemies.m_killed[ killedPlayer .. ":" .. killedId ] = true;
end

-- End of our turn: remember what we see.
function HubEnemies.TakeSnapshot()
	HubEnemies.m_killed = {};
	HubEnemies.m_snapshot = { turn = Game.GetCurrentGameTurn(), units = HubEnemies.Gather() };
end

function HubEnemies.Reset()
	HubEnemies.m_killed = {};
	HubEnemies.m_snapshot = nil;
end

-- Start of our turn (after the "Turn N" line): the line, or nothing.
function HubEnemies.SpeakAtTurnStart()
	local snap:table = HubEnemies.m_snapshot;
	HubEnemies.m_snapshot = nil;
	if snap == nil or snap.turn ~= Game.GetCurrentGameTurn() - 1 then return; end
	local new:table, seen:table = HubEnemies.Gather();
	local text:string = HubEnemies.Describe( snap.units, new, HubEnemies.m_killed, Dist, seen );
	if text ~= nil then HubCore.Announce( text, true, "enemies" ); end
end
