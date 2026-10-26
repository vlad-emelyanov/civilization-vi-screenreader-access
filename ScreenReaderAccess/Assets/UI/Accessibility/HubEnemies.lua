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
			if e.alarmNow then text = nil; end		-- the alarm line said it
		else
			local moved:number = dist( before.x, before.y, e.x, e.y );
			if moved > 0 then
				text = e.name .. " moved " .. moved .. " " .. Plural( moved );
				if e.anchorX ~= nil then
					local was:number = dist( before.x, before.y, e.anchorX, e.anchorY );
					local now:number = dist( e.x, e.y, e.anchorX, e.anchorY );
					if e.scout and e.alarmed and now > was then
						-- a scout that has seen a city and walks off: it is going home
						text = e.name .. " heading away from " .. e.anchorName;
						if e.campText ~= nil then text = text .. ", toward a known camp " .. e.campText; end
					elseif now < was then text = text .. " toward " .. e.anchorName;
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
		if text ~= nil then table.insert( items, { text = text, near = e.near or 99, changed = changed, key = key } ); end
	end
	for key, e in pairs( old ) do
		local seenNow:boolean = seen ~= nil and seen[ key ] == true;
		-- an alarmed scout that vanished has its own "escaped" line
		if new[ key ] == nil and not dead[ key ] and not ( e.alarmed and not seenNow ) then
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
						local key:string = id .. ":" .. unit:GetID();
						local scout:boolean = HubEnemies.IsBarbarianScout ~= nil and HubEnemies.IsBarbarianScout( unit );
						local alarmed:boolean = scout and HubEnemies.m_alarmed[ key ] == true;
						result[ key ] = {
							scout = scout, alarmed = alarmed, alarmNow = HubEnemies.m_alarmedNow[ key ] == true,
							campText = alarmed and HubEnemies.CampTextFor( x, y, best.x, best.y ) or nil,
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
	local key:string = killedPlayer .. ":" .. killedId;
	HubEnemies.m_killed[ key ] = true;
	local scout:table = HubEnemies.m_scouts[ key ];
	if scout ~= nil then
		-- the alarmed scout died: no raid comes from it (said after the combat lines)
		HubEnemies.m_scouts[ key ] = nil;
		HubCore.After( 0.8, function() HubCore.Announce( HubEnemies.KilledText( scout.name ), true, "alarm" ); end );
	end
end

-- End of our turn: remember what we see.
function HubEnemies.TakeSnapshot()
	HubEnemies.m_killed = {};
	HubEnemies.m_snapshot = { turn = Game.GetCurrentGameTurn(), units = HubEnemies.Gather() };
end

function HubEnemies.Reset()
	HubEnemies.m_killed = {};
	HubEnemies.m_snapshot = nil;
	HubEnemies.m_scouts, HubEnemies.m_alarmed, HubEnemies.m_alarmedNow = {}, {}, {};
	HubEnemies.m_raidExpected = nil;
	HubEnemies.m_raidSig, HubEnemies.m_dangerSig, HubEnemies.m_escortHinted = {}, {}, {};
end

-- Start of our turn (after the "Turn N" line): the line, or nothing.
function HubEnemies.SpeakAtTurnStart()
	local snap:table = HubEnemies.m_snapshot;
	HubEnemies.m_snapshot = nil;
	-- the scout alarm comes first (after the "Turn N" line, which it must not cut off)
	local okScouts:boolean, alarms = pcall( HubEnemies.CheckScouts, true );
	if okScouts then
		for _, line in ipairs( alarms ) do HubCore.Announce( line, true, "alarm" ); end
	else
		print( "HubEnemies scout error: " .. tostring( alarms ) );
	end
	if snap ~= nil and snap.turn == Game.GetCurrentGameTurn() - 1 then
		local new:table, seen:table = HubEnemies.Gather();
		-- raiders have their own raid line below: not repeated here
		local okRaid:boolean, threats = pcall( HubEnemies.ScanThreats );
		if okRaid then
			for _, raid in ipairs( threats.raids ) do
				for _, m in ipairs( raid.members ) do new[ m.key ] = nil; snap.units[ m.key ] = nil; end
			end
		end
		local text:string = HubEnemies.Describe( snap.units, new, HubEnemies.m_killed, Dist, seen );
		if text ~= nil then HubCore.Announce( text, true, "enemies" ); end
	end
	HubEnemies.m_alarmedNow = {};
	local okThreats:boolean, err = pcall( HubEnemies.SpeakThreats, true );
	if not okThreats then print( "HubEnemies threat error: " .. tostring( err ) ); end
end

-- ===========================================================================
-- G3a / G3b / G4: scout alarm, raid warning, civilians in danger, escort awareness.
-- The wording is pure (functions taking plain values); the gathering below it reads the engine and only ever looks at
-- units we really see (never fogged positions); remembered camps come from HubPlaces' memory.
-- ===========================================================================
local RAID_RADIUS:number = 5;			-- 2+ hostile soldiers this close to a city: a raid
local DANGER_RADIUS:number = 2;			-- a hostile soldier this close to an unescorted civilian: danger
local PATH_DANGER:number = 4;			-- a hostile soldier / camp this close to a moving civilian's path or target
local RAID_EXPECTED_TURNS:number = 10;
local MAX_RAID_GROUPS:number = 3;

HubEnemies.m_scouts = {};				-- "owner:id" -> { name, x, y (last seen), cx, cy (the city it saw), turn } of alarmed scouts not yet escaped or dead
HubEnemies.m_alarmed = {};				-- "owner:id" -> true: this scout already had its alarm (once per scout)
HubEnemies.m_alarmedNow = {};			-- "owner:id" -> true: alarmed at this turn start (the Enemies line skips it)
HubEnemies.m_raidExpected = nil;		-- { turn, dir } after a scout escaped; ends when a raid arrives or after RAID_EXPECTED_TURNS
HubEnemies.m_raidSig = {};				-- "city:owner" -> signature of the raid line last spoken
HubEnemies.m_dangerSig = {};			-- civilian unit id -> signature of the danger line last spoken
HubEnemies.m_escortHinted = {};			-- "unit:partner" -> true: "X here too" was said
HubEnemies.m_checkArmed = false;

function HubEnemies.KeyText( actionName:string, default:string )
	local ok:boolean, text = pcall( function()
		local id = Input.GetActionId( actionName );
		if id == nil then return nil; end
		return Input.GetGestureDisplayString( id, 0 );
	end );
	if ok and text ~= nil and text ~= "" then return text; end
	return default;
end

-- ---------------------------------------------------------------------------
-- Pure wording
-- ---------------------------------------------------------------------------
function HubEnemies.AlarmText( name:string, cityName:string, relative:string, attackKey:string )
	local text:string = "Alarm: " .. name .. " has seen " .. cityName;
	if relative ~= nil and relative ~= "" then text = text .. ", " .. relative; end
	return text .. ". If it gets back to its camp, a raid follows. Kill it: " .. attackKey .. " targets it";
end

function HubEnemies.EscapedText( name:string, dir:string )
	return name .. " escaped. Expect a raid" .. ( dir ~= nil and ( " from the " .. dir ) or "" ) .. " in a few turns";
end

function HubEnemies.KilledText( name:string )
	return name .. " killed, no raid from it";
end

function HubEnemies.RaidExpectedText( dir:string )
	return "Raid expected" .. ( dir ~= nil and ( " from the " .. dir ) or "" );
end

-- "Horseman" x1 / "Spearman" x2 -> "Spearmen"
function HubEnemies.PluralName( name:string, count:number )
	if count == 1 then return name; end
	if string.sub( name, -3 ) == "man" then return string.sub( name, 1, -4 ) .. "men"; end
	if string.sub( name, -1 ) == "s" then return name; end
	return name .. "s";
end

-- groups: { { name, count, relative (nil: in the city) } ... } sorted nearest first; total = soldiers in all groups.
-- owner: nil for barbarians, else the civilization's short name. defense: the city's strength or nil.
-- own: { "Warrior in Rome", "Slinger 2 tiles west" } (nearest first, maybe empty).
function HubEnemies.RaidText( owner:string, cityName:string, total:number, groups:table, defense:number, own:table )
	local head:string;
	if owner == nil then
		head = "Raid: " .. total .. " barbarians near " .. cityName;
	else
		head = owner .. ": " .. total .. " units near " .. cityName;
	end
	local parts:table = {};
	for i = 1, math.min( #groups, MAX_RAID_GROUPS ) do
		local g:table = groups[i];
		local item:string = ( g.count > 1 and ( g.count .. " " ) or "" ) .. HubEnemies.PluralName( g.name, g.count );
		table.insert( parts, item .. " " .. ( g.relative or ( "in " .. cityName ) ) );
	end
	local text:string = head .. ": " .. table.concat( parts, ", " );
	if #groups > MAX_RAID_GROUPS then text = text .. " and more"; end
	text = text .. ".";
	if defense ~= nil then text = text .. " " .. cityName .. " defense " .. defense .. "."; end
	if own ~= nil and #own > 0 then
		text = text .. " Your nearest soldiers: " .. table.concat( own, ", " );
	else
		text = text .. " You have no soldiers near";
	end
	return text;
end

-- hint: "Move it into Rome" or nil.
function HubEnemies.DangerText( civilianName:string, nearName:string, enemyName:string, relative:string, hint:string )
	local text:string = civilianName .. ( nearName ~= nil and ( " near " .. nearName ) or "" ) .. " in danger: " .. enemyName;
	if relative ~= nil and relative ~= "" then text = text .. " " .. relative; end
	if hint ~= nil and hint ~= "" then text = text .. ". " .. hint; end
	return text;
end

-- danger: "Barbarian Warrior 2 tiles from the path" (already worded)
function HubEnemies.AloneText( unitName:string, turns:number, danger:string, formationKey:string )
	local text:string = unitName .. " moving alone";
	if turns ~= nil then text = text .. ", " .. HubCore.Plural( turns, "turn", "turns" ); end
	return text .. ". " .. danger .. ". Escort first: " .. formationKey .. " with a soldier on the same tile";
end

-- "2 tiles from the path" / "on the path" / "at the target"
function HubEnemies.FromPathText( distance:number, onTarget:boolean )
	if distance == 0 then return onTarget and "at the target" or "on the path"; end
	return distance .. " " .. Plural( distance ) .. " from the " .. ( onTarget and "target" or "path" );
end

function HubEnemies.EscortHintText( partnerName:string, formationKey:string )
	return partnerName .. " here too: " .. formationKey .. " forms an escort";
end

-- ---------------------------------------------------------------------------
-- Engine helpers
-- ---------------------------------------------------------------------------
local function UnitRow( unit:table )
	return GameInfo.Units[ unit:GetUnitType() ];
end

local function IsSoldier( unit:table )
	return unit:GetCombat() > 0 or unit:GetRangedCombat() > 0;
end

-- A barbarian scout: the Barbarian Scout type, or the plain Scout row owned by the barbarian player.
function HubEnemies.IsBarbarianScout( unit:table )
	local player:table = Players[ unit:GetOwner() ];
	if player == nil or not player:IsBarbarian() then return false; end
	local row:table = UnitRow( unit );
	return row ~= nil and ( row.UnitType == "UNIT_BARBARIAN_SCOUT" or row.UnitType == "UNIT_SCOUT" );
end

-- Settler or Builder of ours (what a barbarian can capture).
function HubEnemies.IsCivilian( unit:table )
	local row:table = UnitRow( unit );
	return row ~= nil and ( row.FoundCity == true or ( row.BuildCharges ~= nil and row.BuildCharges > 0 ) );
end

local function InFormation( unit:table )
	local ok:boolean, count = pcall( function() return unit:GetFormationUnitCount(); end );
	return ok and count ~= nil and count > 1;
end

-- Visible hostile units: { unit, owner, id, x, y, key, soldier, scout }.
local function VisibleHostiles()
	local list:table = {};
	local localID:number = Game.GetLocalPlayer();
	if localID == nil or localID == -1 then return list; end
	for id = 0, 63 do
		if id ~= localID and Players[ id ] ~= nil and HubCore.IsHostile( id ) then
			for _, unit in Players[ id ]:GetUnits():Members() do
				if PlotDescription_IsUnitVisible( unit ) then
					local scout:boolean = HubEnemies.IsBarbarianScout( unit );
					table.insert( list, { unit = unit, owner = id, id = unit:GetID(), x = unit:GetX(), y = unit:GetY(),
						key = id .. ":" .. unit:GetID(), soldier = IsSoldier( unit ) and not scout, scout = scout } );
				end
			end
		end
	end
	return list;
end

local function OwnCities()
	local cities:table = {};
	local me:table = Players[ Game.GetLocalPlayer() ];
	if me == nil then return cities; end
	for _, city in me:GetCities():Members() do table.insert( cities, city ); end
	return cities;
end

local function ShortName( entry:table )
	local name:string = PlotDescription_GetUnitName( entry.unit );
	if Players[ entry.owner ]:IsBarbarian() then name = string.gsub( name, "^Barbarian ", "" ); end
	return name;
end

-- ---------------------------------------------------------------------------
-- G3a: scouts
-- ---------------------------------------------------------------------------
local function ScoutSight( unit:table )
	local row:table = UnitRow( unit );
	local sight:number = ( row ~= nil and row.BaseSightRange ~= nil ) and row.BaseSightRange or 2;
	return math.max( sight, 2 );
end

-- A remembered camp that lies away from the city, seen from the scout: "4 tiles north-east", else nil.
function HubEnemies.CampTextFor( x:number, y:number, cityX:number, cityY:number )
	if HubPlaces == nil or HubPlaces.RememberedCampPlots == nil then return nil; end
	local here:table = Map.GetPlot( x, y );
	local best:table, bestDistance:number = nil, 99;
	for _, plot in ipairs( HubPlaces.RememberedCampPlots() ) do
		local d:number = Dist( x, y, plot:GetX(), plot:GetY() );
		if d <= 12 and d < bestDistance and Dist( plot:GetX(), plot:GetY(), cityX, cityY ) > Dist( x, y, cityX, cityY ) then
			best, bestDistance = plot, d;
		end
	end
	if best == nil then return nil; end
	return PlotDescription_GetRelative( here, best );
end

-- Looks at the barbarian scouts in view: the alarm for one that sees a city of ours (or stands in our borders), once per
-- scout. atTurnStart: scouts with an alarm that are not in view any more have escaped (a raid is expected). Returns the
-- lines to speak.
function HubEnemies.CheckScouts( atTurnStart:boolean )
	local lines:table = {};
	local localID:number = Game.GetLocalPlayer();
	local cities:table = OwnCities();
	local visible:table = {};
	for _, h in ipairs( VisibleHostiles() ) do
		if h.scout then
			visible[ h.key ] = true;
			local known:table = HubEnemies.m_scouts[ h.key ];
			if known ~= nil then
				known.x, known.y, known.turn = h.x, h.y, Game.GetCurrentGameTurn();
			elseif not HubEnemies.m_alarmed[ h.key ] then
				local sight:number = ScoutSight( h.unit );
				local best:table, bestDistance:number = nil, 99;
				for _, city in ipairs( cities ) do
					local d:number = Dist( h.x, h.y, city:GetX(), city:GetY() );
					if d < bestDistance then best, bestDistance = city, d; end
				end
				local plot:table = Map.GetPlot( h.x, h.y );
				local inBorders:boolean = plot ~= nil and plot:GetOwner() == localID;
				if best ~= nil and ( bestDistance <= sight or inBorders ) then
					HubEnemies.m_alarmed[ h.key ] = true;
					HubEnemies.m_alarmedNow[ h.key ] = true;
					HubEnemies.m_scouts[ h.key ] = { name = PlotDescription_GetUnitName( h.unit ), x = h.x, y = h.y,
						cx = best:GetX(), cy = best:GetY(), turn = Game.GetCurrentGameTurn() };
					local relative:string = PlotDescription_GetRelative( Map.GetPlot( best:GetX(), best:GetY() ), plot );
					table.insert( lines, HubEnemies.AlarmText( PlotDescription_GetUnitName( h.unit ), Locale.Lookup( best:GetName() ),
						relative, HubEnemies.KeyText( "Attack", "W" ) ) );
				end
			end
		end
	end
	if atTurnStart then
		for key, known in pairs( HubEnemies.m_scouts ) do
			if not visible[ key ] then
				HubEnemies.m_scouts[ key ] = nil;
				if not HubEnemies.m_killed[ key ] then
					local dir:string = PlotDescription_GetDirectionWord( known.cx, known.cy, known.x, known.y );
					HubEnemies.m_raidExpected = { turn = Game.GetCurrentGameTurn(), dir = dir };
					table.insert( lines, HubEnemies.EscapedText( known.name, dir ) );
				end
			end
		end
	end
	return lines;
end

-- "Raid expected from the north-east" while the state lasts, else nil.
function HubEnemies.RaidExpectedLine()
	local state:table = HubEnemies.m_raidExpected;
	if state == nil then return nil; end
	if Game.GetCurrentGameTurn() - state.turn > RAID_EXPECTED_TURNS then
		HubEnemies.m_raidExpected = nil;
		return nil;
	end
	return HubEnemies.RaidExpectedText( state.dir );
end

-- ---------------------------------------------------------------------------
-- G3b: raids and civilians in danger
-- ---------------------------------------------------------------------------
local function CityDefense( city:table )
	local ok:boolean, value = pcall( function()
		local district = CityManager.GetDistrictAt( city:GetX(), city:GetY() );
		if district == nil then return nil; end
		return math.floor( district:GetDefenseStrength() + 0.5 );
	end );
	if ok then return value; end
	return nil;
end

-- Our nearest soldiers to a city: { "Warrior in Rome", "Slinger 2 tiles west" } (at most two).
local function NearestOwnSoldiers( city:table )
	local found:table = {};
	local me:table = Players[ Game.GetLocalPlayer() ];
	local cityPlot:table = Map.GetPlot( city:GetX(), city:GetY() );
	for _, unit in me:GetUnits():Members() do
		if IsSoldier( unit ) and unit:GetMaxMoves() > 0 and not HubEnemies.IsCivilian( unit ) then
			local d:number = Dist( unit:GetX(), unit:GetY(), city:GetX(), city:GetY() );
			if d <= 8 then table.insert( found, { unit = unit, d = d } ); end
		end
	end
	table.sort( found, function( a, b )
		if a.d ~= b.d then return a.d < b.d; end
		return a.unit:GetID() < b.unit:GetID();
	end );
	local texts:table = {};
	for i = 1, math.min( 2, #found ) do
		local unit:table = found[i].unit;
		local name:string = Locale.Lookup( unit:GetName() );
		if found[i].d == 0 then
			table.insert( texts, name .. " in " .. Locale.Lookup( city:GetName() ) );
		else
			table.insert( texts, name .. " " .. PlotDescription_GetRelative( cityPlot, Map.GetPlot( unit:GetX(), unit:GetY() ) ) );
		end
	end
	return texts;
end

-- Live scan of the dangers. Returns { raids = { { key, sig, text, barbarian, members = { entry } } },
-- civilians = { { key, sig, text, enemy = entry, unit } } }.
function HubEnemies.ScanThreats()
	local result:table = { raids = {}, civilians = {} };
	local cities:table = OwnCities();
	local soldiers:table = {};
	for _, h in ipairs( VisibleHostiles() ) do if h.soldier then table.insert( soldiers, h ); end end
	if #soldiers == 0 then return result; end
	-- raids: per city and owner, the soldiers whose nearest city is that one
	local byCity:table = {};
	for _, s in ipairs( soldiers ) do
		local best:table, bestDistance:number = nil, 99;
		for _, city in ipairs( cities ) do
			local d:number = Dist( s.x, s.y, city:GetX(), city:GetY() );
			if d < bestDistance or ( d == bestDistance and best ~= nil and city:GetID() < best:GetID() ) then best, bestDistance = city, d; end
		end
		if best ~= nil and bestDistance <= RAID_RADIUS then
			s.near = bestDistance;
			local key:string = best:GetID() .. ":" .. s.owner;
			byCity[ key ] = byCity[ key ] or { city = best, owner = s.owner, members = {} };
			table.insert( byCity[ key ].members, s );
		end
	end
	for key, raid in pairs( byCity ) do
		if #raid.members >= 2 then
			local city:table = raid.city;
			local cityPlot:table = Map.GetPlot( city:GetX(), city:GetY() );
			local groups:table, order:table = {}, {};
			table.sort( raid.members, function( a, b )
				if a.near ~= b.near then return a.near < b.near; end
				return a.key < b.key;
			end );
			for _, m in ipairs( raid.members ) do
				local relative:string = PlotDescription_GetRelative( cityPlot, Map.GetPlot( m.x, m.y ) );
				local gkey:string = ShortName( m ) .. "|" .. tostring( relative );
				if groups[ gkey ] == nil then
					groups[ gkey ] = { name = ShortName( m ), count = 0, relative = relative };
					table.insert( order, groups[ gkey ] );
				end
				groups[ gkey ].count = groups[ gkey ].count + 1;
			end
			local barbarian:boolean = Players[ raid.owner ]:IsBarbarian();
			local ownerName:string = nil;
			if not barbarian then ownerName = Locale.Lookup( PlayerConfigurations[ raid.owner ]:GetCivilizationShortDescription() ); end
			local text:string = HubEnemies.RaidText( ownerName, Locale.Lookup( city:GetName() ), #raid.members, order, CityDefense( city ),
				NearestOwnSoldiers( city ) );
			-- the signature changes with the soldiers and their positions, not with the wording of our own units
			local sigParts:table = {};
			-- who is in it and how close (a band), so a raid that walks on is not spoken again every turn
			for _, m in ipairs( raid.members ) do table.insert( sigParts, m.key .. ( m.near <= 2 and "a" or "b" ) ); end
			table.insert( result.raids, { key = key, sig = table.concat( sigParts, ";" ), text = text, barbarian = barbarian, members = raid.members } );
		end
	end
	table.sort( result.raids, function( a, b ) return a.key < b.key; end );
	-- civilians (not inside a city of ours, not in a formation, no soldier of ours on the tile)
	local me:table = Players[ Game.GetLocalPlayer() ];
	for _, unit in me:GetUnits():Members() do
		if HubEnemies.IsCivilian( unit ) and not InFormation( unit ) then
			local plot:table = Map.GetPlot( unit:GetX(), unit:GetY() );
			local escorted:boolean = plot == nil or plot:IsCity();
			if not escorted then
				for _, other in ipairs( Units.GetUnitsInPlot( plot ) ) do
					if other:GetOwner() == unit:GetOwner() and other:GetID() ~= unit:GetID() and IsSoldier( other ) then escorted = true; end
				end
			end
			if not escorted then
				local nearest:table, nearestDistance:number = nil, 99;
				for _, s in ipairs( soldiers ) do
					local d:number = Dist( s.x, s.y, unit:GetX(), unit:GetY() );
					if d <= DANGER_RADIUS and d < nearestDistance then nearest, nearestDistance = s, d; end
				end
				if nearest ~= nil then
					local nearCity:table, cityDistance:number = nil, 99;
					for _, city in ipairs( cities ) do
						local d:number = Dist( unit:GetX(), unit:GetY(), city:GetX(), city:GetY() );
						if d < cityDistance then nearCity, cityDistance = city, d; end
					end
					local ownSoldier:table, soldierDistance:number = nil, 99;
					for _, other in me:GetUnits():Members() do
						if IsSoldier( other ) and not HubEnemies.IsCivilian( other ) and other:GetMaxMoves() > 0 then
							local d:number = Dist( unit:GetX(), unit:GetY(), other:GetX(), other:GetY() );
							if d < soldierDistance then ownSoldier, soldierDistance = other, d; end
						end
					end
					local hint:string = nil;
					if ownSoldier ~= nil and soldierDistance <= 3 and ( nearCity == nil or soldierDistance < cityDistance ) then
						hint = "Move it next to your " .. Locale.Lookup( ownSoldier:GetName() ) .. ", "
							.. ( PlotDescription_GetRelative( plot, Map.GetPlot( ownSoldier:GetX(), ownSoldier:GetY() ) ) or "here" );
					elseif nearCity ~= nil then
						hint = "Move it into " .. Locale.Lookup( nearCity:GetName() );
					end
					local text:string = HubEnemies.DangerText( Locale.Lookup( unit:GetName() ),
						nearCity ~= nil and Locale.Lookup( nearCity:GetName() ) or nil, PlotDescription_GetUnitName( nearest.unit ),
						PlotDescription_GetRelative( plot, Map.GetPlot( nearest.x, nearest.y ) ), hint );
					table.insert( result.civilians, { key = unit:GetID(), sig = nearest.key .. "@" .. nearest.x .. "," .. nearest.y,
						text = text, enemy = nearest, unit = unit } );
				end
			end
		end
	end
	return result;
end

-- Speaks the raid and danger lines that are new or changed since they were last spoken. nointerrupt: wait for the line
-- that is being spoken (turn start); false: an event in the middle of our turn.
function HubEnemies.SpeakThreats( nointerrupt:boolean )
	local threats:table = HubEnemies.ScanThreats();
	local liveRaids:table, liveCivilians:table = {}, {};
	for _, raid in ipairs( threats.raids ) do
		liveRaids[ raid.key ] = true;
		if HubEnemies.m_raidSig[ raid.key ] ~= raid.sig then
			HubEnemies.m_raidSig[ raid.key ] = raid.sig;
			if raid.barbarian then HubEnemies.m_raidExpected = nil; end		-- it has come
			HubCore.Announce( raid.text, nointerrupt, "raid" );
		end
	end
	for _, danger in ipairs( threats.civilians ) do
		liveCivilians[ danger.key ] = true;
		if HubEnemies.m_dangerSig[ danger.key ] ~= danger.sig then
			HubEnemies.m_dangerSig[ danger.key ] = danger.sig;
			HubCore.Announce( danger.text, nointerrupt, "danger" );
		end
	end
	for key in pairs( HubEnemies.m_raidSig ) do if not liveRaids[ key ] then HubEnemies.m_raidSig[ key ] = nil; end end
	for key in pairs( HubEnemies.m_dangerSig ) do if not liveCivilians[ key ] then HubEnemies.m_dangerSig[ key ] = nil; end end
end

-- A hostile unit came into view (HubEvents.OnUnitVisibilityChanged): check scouts and threats a moment later, once.
function HubEnemies.IsOurTurn()
	local player:table = Players[ Game.GetLocalPlayer() ];
	return player ~= nil and player:IsTurnActive();
end

-- During the AI turns nothing is said (the turn start does it, without interrupting).
function HubEnemies.OnHostileVisible( unit:table )
	if HubEnemies.m_checkArmed or not HubEnemies.IsOurTurn() then return; end
	HubEnemies.m_checkArmed = true;
	HubCore.After( 0.4, function()
		HubEnemies.m_checkArmed = false;
		if not HubCore.m_ready or not HubEnemies.IsOurTurn() then return; end
		local ok:boolean, err = pcall( function()
			for _, line in ipairs( HubEnemies.CheckScouts( false ) ) do HubCore.Announce( line, false, "alarm" ); end
			HubEnemies.SpeakThreats( true );
		end );
		if not ok then print( "HubEnemies check error: " .. tostring( err ) ); end
	end );
end

-- Items for the places list (J): { key, name, x, y, text } of the alarmed scouts in view, the raiders and the enemies near
-- a civilian of ours. Empty when nothing is active.
function HubEnemies.ThreatItems()
	local items:table, seen:table = {}, {};
	local function Add( entry:table, text:string )
		if seen[ entry.key ] then return; end
		seen[ entry.key ] = true;
		table.insert( items, { key = "t:" .. entry.key, name = PlotDescription_GetUnitName( entry.unit ), x = entry.x, y = entry.y, text = text } );
	end
	for _, h in ipairs( VisibleHostiles() ) do
		if h.scout and HubEnemies.m_alarmed[ h.key ] and HubEnemies.m_scouts[ h.key ] ~= nil then
			Add( h, PlotDescription_GetUnitName( h.unit ) .. ", has seen your city" );
		end
	end
	local threats:table = HubEnemies.ScanThreats();
	for _, raid in ipairs( threats.raids ) do
		for _, m in ipairs( raid.members ) do Add( m, PlotDescription_GetUnitName( m.unit ) .. ", raiding" ); end
	end
	for _, danger in ipairs( threats.civilians ) do
		Add( danger.enemy, PlotDescription_GetUnitName( danger.enemy.unit ) .. ", threatens your " .. Locale.Lookup( danger.unit:GetName() ) );
	end
	return items;
end

-- ---------------------------------------------------------------------------
-- G4: escort awareness
-- ---------------------------------------------------------------------------
-- Said when a settler or builder is ordered to move: nil unless it goes alone and something hostile (a visible soldier, a
-- remembered camp) lies within PATH_DANGER tiles of the path or the target.
function HubEnemies.AloneWarning( unit:table, plot:table )
	if unit == nil or plot == nil or unit:GetOwner() ~= Game.GetLocalPlayer() or not HubEnemies.IsCivilian( unit ) or InFormation( unit ) then return nil; end
	local path:table = UnitManager.GetMoveToPathEx( unit, plot:GetIndex() );
	if path == nil or path.plots == nil or #path.plots < 2 then return nil; end
	local points:table = {};
	for i, index in ipairs( path.plots ) do
		local p:table = Map.GetPlotByIndex( index );
		if p ~= nil then table.insert( points, { x = p:GetX(), y = p:GetY(), target = ( i == #path.plots ) } ); end
	end
	local best:table = nil;
	local function Consider( name:string, x:number, y:number )
		for _, pt in ipairs( points ) do
			local d:number = Dist( x, y, pt.x, pt.y );
			if d <= PATH_DANGER and ( best == nil or d < best.d ) then best = { d = d, name = name, target = pt.target }; end
		end
	end
	for _, h in ipairs( VisibleHostiles() ) do
		if h.soldier then Consider( PlotDescription_GetUnitName( h.unit ), h.x, h.y ); end
	end
	if HubPlaces ~= nil and HubPlaces.RememberedCampPlots ~= nil then
		for _, camp in ipairs( HubPlaces.RememberedCampPlots() ) do Consider( "Barbarian camp", camp:GetX(), camp:GetY() ); end
	end
	if best == nil then return nil; end
	local danger:string = best.name .. " " .. HubEnemies.FromPathText( best.d, best.target );
	return HubEnemies.AloneText( Locale.Lookup( unit:GetName() ), path.turns[ #path.turns ] or 1, danger,
		HubEnemies.KeyText( "ExtraHotkeysEnterFormation", "Shift+E" ) );
end

-- Added to the announcement of a selected unit: "escorted by Warrior" / "escorting Settler" in a formation (HYPOTHESIS: the
-- members of a formation share a tile and report GetFormationUnitCount() > 1), else once "Warrior here too: Shift+E forms an
-- escort" for a civilian and a soldier of ours that share a tile without one.
function HubEnemies.EscortText( unit:table )
	if unit == nil or unit:GetOwner() ~= Game.GetLocalPlayer() then return nil; end
	local plot:table = Map.GetPlot( unit:GetX(), unit:GetY() );
	if plot == nil then return nil; end
	local civilian:boolean = HubEnemies.IsCivilian( unit );
	local soldier:boolean = IsSoldier( unit ) and not civilian;
	if not civilian and not soldier then return nil; end
	local together:boolean, partners:table = InFormation( unit ), {};
	for _, other in ipairs( Units.GetUnitsInPlot( plot ) ) do
		if other:GetOwner() == unit:GetOwner() and other:GetID() ~= unit:GetID() then
			local otherCivilian:boolean = HubEnemies.IsCivilian( other );
			if ( civilian and IsSoldier( other ) and not otherCivilian ) or ( soldier and otherCivilian ) then
				if not together or InFormation( other ) then table.insert( partners, other ); end
			end
		end
	end
	if #partners == 0 or plot:IsCity() then return nil; end
	local name:string = Locale.Lookup( partners[1]:GetName() );
	if together then
		return ( civilian and "escorted by " or "escorting " ) .. name;
	end
	local key:string = unit:GetID() .. ":" .. partners[1]:GetID();
	if HubEnemies.m_escortHinted[ key ] then return nil; end
	HubEnemies.m_escortHinted[ key ] = true;
	return HubEnemies.EscortHintText( name, HubEnemies.KeyText( "ExtraHotkeysEnterFormation", "Shift+E" ) );
end
