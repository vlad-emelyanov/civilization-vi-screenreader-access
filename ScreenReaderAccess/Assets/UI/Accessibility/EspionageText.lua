-- ===========================================================================
--	EspionageText: pure text helpers for the Espionage overview (F3, PartialScreens/EspionageOverview.lua) and the
--	Espionage chooser (Choosers/EspionageChooser.lua). Plain data in, strings out; the screens read the game's state.
--
--	EspionageText_Header( d )        d: { spies, capacity, idle } "Espionage: 2 of 3 spies, 1 awaiting orders"
--	EspionageText_Spy( s )           s: { name, rank, state = "idle"|"mission"|"travel"|"captured", city, mission,
--	                                      turns, destination, capturedBy }
--	EspionageText_City( c )          c: { name, owner, capital, districts, spies, boostTurns }
--	EspionageText_History( m )       m: { name, rank, mission, turnsAgo, success, description, status }
--	EspionageText_EnemySpy( e )      e: { name, civ, canTrade }
--	EspionageText_Destination( d )   d: { name, owner, capital, turns }
--	EspionageText_Mission( m )       m: { name, district, chance, turns, reason }
--	EspionageText_Outcomes( o )      o: { success, failure, lost } (whole percents; nil or 0 are left out)
-- ===========================================================================

function EspionageText_Plural( n:number, word:string )
	return n .. " " .. word .. ( n == 1 and "" or "s" );
end

local function Turns( n:number, suffix:string )
	return n .. ( n == 1 and " turn" or " turns" ) .. ( suffix or "" );
end

function EspionageText_Header( d:table )
	local text:string = "Espionage: ";
	if d.capacity ~= nil then
		text = text .. d.spies .. " of " .. d.capacity .. ( d.capacity == 1 and " spy" or " spies" );
	else
		text = text .. d.spies .. ( d.spies == 1 and " spy" or " spies" );
	end
	if d.spies > 0 then text = text .. ", " .. d.idle .. " awaiting orders"; end
	return text;
end

function EspionageText_Spy( s:table )
	local parts:table = { "Spy " .. s.name };
	if s.rank ~= nil and s.rank ~= "" then table.insert( parts, s.rank ); end
	if s.state == "captured" then
		table.insert( parts, "captured" .. ( s.capturedBy ~= nil and ( " by " .. s.capturedBy ) or "" ) );
	elseif s.state == "travel" then
		table.insert( parts, "travelling" .. ( s.destination ~= nil and ( " to " .. s.destination ) or "" ) );
		if s.turns ~= nil then table.insert( parts, Turns( s.turns, " left" ) ); end
	elseif s.state == "mission" then
		if s.city ~= nil then table.insert( parts, "in " .. s.city ); end
		if s.mission ~= nil then table.insert( parts, s.mission ); end
		if s.turns ~= nil then table.insert( parts, Turns( s.turns, " left" ) ); end
	else
		if s.city ~= nil then table.insert( parts, "in " .. s.city ); end
		table.insert( parts, "awaiting orders" );
	end
	return table.concat( parts, ", " );
end

function EspionageText_City( c:table )
	local parts:table = { c.name };
	if c.owner ~= nil and c.owner ~= "" then table.insert( parts, c.owner ); end
	if c.capital then table.insert( parts, "capital" ); end
	if c.spies ~= nil and #c.spies > 0 then table.insert( parts, "your spy " .. table.concat( c.spies, ", " ) ); end
	if c.boostTurns ~= nil and c.boostTurns > 0 then table.insert( parts, "gain sources boost, " .. Turns( c.boostTurns, " left" ) ); end
	if c.districts ~= nil and #c.districts > 0 then table.insert( parts, "districts: " .. table.concat( c.districts, ", " ) ); end
	return table.concat( parts, ", " );
end

function EspionageText_History( m:table )
	local parts:table = { m.name };
	if m.rank ~= nil and m.rank ~= "" then table.insert( parts, m.rank ); end
	table.insert( parts, m.mission );
	if m.turnsAgo ~= nil then table.insert( parts, m.turnsAgo == 0 and "this turn" or Turns( m.turnsAgo, " ago" ) ); end
	if m.success ~= nil then table.insert( parts, m.success and "success" or "failure" ); end
	if m.status ~= nil and m.status ~= "" then table.insert( parts, m.status ); end
	local text:string = table.concat( parts, ", " );
	if m.description ~= nil and m.description ~= "" then text = text .. ". " .. m.description; end
	return text;
end

function EspionageText_EnemySpy( e:table )
	local text:string = "Captured enemy spy " .. e.name;
	if e.civ ~= nil and e.civ ~= "" then text = text .. ", " .. e.civ; end
	if e.canTrade then text = text .. ", Enter to offer a trade"; end
	return text;
end

function EspionageText_Destination( d:table )
	local parts:table = { d.name };
	if d.owner ~= nil and d.owner ~= "" then table.insert( parts, d.owner ); end
	if d.capital then table.insert( parts, "capital" ); end
	if d.turns ~= nil then table.insert( parts, Turns( d.turns ) ); end
	return table.concat( parts, ", " );
end

function EspionageText_Mission( m:table )
	local parts:table = { m.name };
	if m.district ~= nil and m.district ~= "" then table.insert( parts, m.district ); end
	if m.reason ~= nil then
		table.insert( parts, "unavailable: " .. m.reason );
		return table.concat( parts, ", " );
	end
	if m.chance ~= nil then table.insert( parts, m.chance .. " percent success" ); end
	if m.turns ~= nil then table.insert( parts, Turns( m.turns ) ); end
	return table.concat( parts, ", " );
end

function EspionageText_Outcomes( o:table )
	local parts:table = {};
	if o.success ~= nil then table.insert( parts, o.success .. " percent success" ); end
	if o.failure ~= nil and o.failure > 0 then table.insert( parts, o.failure .. " percent failure" ); end
	if o.lost ~= nil and o.lost > 0 then table.insert( parts, o.lost .. " percent spy captured or killed" ); end
	return table.concat( parts, ", " );
end
