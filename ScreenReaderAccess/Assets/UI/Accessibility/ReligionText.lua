-- ReligionText: pure text helpers for the religion screen (ReligionScreen.lua). No engine calls, tested in test/lua/test_religiontext.lua.
--------------------------------------------------------------

-- "A", "A and B", "A, B and C" ("none" for an empty list).
function ReligionText_Join( names:table )
	local n:number = #names;
	if n == 0 then return "none"; end
	if n == 1 then return names[1]; end
	local head:table = {};
	for i = 1, n - 1 do head[i] = names[i]; end
	return table.concat( head, ", " ) .. " and " .. names[n];
end

-- "1 city" / "3 cities"
function ReligionText_Count( n:number, one:string, many:string )
	if n == 1 then return n .. " " .. one; end
	return n .. " " .. many;
end

-- entries: { { name = "Buddhism", followers = 6 }, ... } -> "6 Buddhism, 2 Hinduism" (most followers first, zero dropped), "no followers" when empty.
function ReligionText_Followers( entries:table )
	local list:table = {};
	for _, e in ipairs( entries ) do
		if e.followers ~= nil and e.followers > 0 then table.insert( list, e ); end
	end
	if #list == 0 then return "no followers"; end
	table.sort( list, function( a, b ) return a.followers > b.followers; end );
	local parts:table = {};
	for i, e in ipairs( list ) do parts[i] = e.followers .. " " .. e.name; end
	return table.concat( parts, ", " );
end

-- "Rome: majority Buddhism, 6 Buddhism, 2 Hinduism" / "Rome: no religion"; majority = name or nil.
function ReligionText_CityLine( cityName:string, majority, entries:table )
	local followers:string = ReligionText_Followers( entries );
	if majority == nil then
		if followers == "no followers" then return cityName .. ": no religion"; end
		return cityName .. ": no majority, " .. followers;
	end
	return cityName .. ": majority " .. majority .. ", " .. followers;
end

-- "founded by you" / "founded by Phoenicia"
function ReligionText_Founder( isYou:boolean, civName:string )
	if isYou then return "founded by you"; end
	return "founded by " .. civName;
end

-- "Choral Music and Tithe" style summary of the beliefs of a religion, or "no beliefs yet".
function ReligionText_Beliefs( names:table )
	if #names == 0 then return "no beliefs yet"; end
	return ReligionText_Join( names );
end

-- "2 beliefs to choose" / "1 belief to choose"
function ReligionText_ToChoose( n:number )
	if n == 1 then return "1 belief to choose"; end
	return n .. " beliefs to choose";
end

-- First character upper, the rest as given: "follower belief" -> "Follower belief".
function ReligionText_Capital( text:string )
	if text == nil or text == "" then return ""; end
	return string.upper( string.sub( text, 1, 1 ) ) .. string.sub( text, 2 );
end
