-- ===========================================================================
--	StandingText: pure wording for "how do I compare with the other civs" (V list numbers, Control+R standing line).
--	No engine calls; HubMenus gathers the numbers (like the game's DiplomacyRibbon) and passes them in, so
--	test/lua/test_standingtext.lua can check ties, a single civ and hidden categories.
--	An entry is { name = "Japan", isYou = false, vals = { score = 212, military = 180, ... } }; a category the game
--	hides (see DiplomacyRibbon) is simply absent from vals of every entry.
-- ===========================================================================

STANDING_CATEGORIES = {
	{ key = "score",	label = "score",	perTurn = false },
	{ key = "military",	label = "military",	perTurn = false },
	{ key = "science",	label = "science",	perTurn = true },
	{ key = "culture",	label = "culture",	perTurn = true },
	{ key = "gold",		label = "gold",		perTurn = false },
	{ key = "faith",	label = "faith",	perTurn = false },
};

-- 1st, 2nd, 3rd, 4th ... 11th, 12th, 13th, 21st
function StandingText_Ordinal( n:number )
	local suffix:string = "th";
	if n % 100 < 11 or n % 100 > 13 then
		local last:number = n % 10;
		if last == 1 then suffix = "st"; elseif last == 2 then suffix = "nd"; elseif last == 3 then suffix = "rd"; end
	end
	return n .. suffix;
end

local function Round( v:number )
	return math.floor( v + 0.5 );
end

-- "score 190, military 150, ..." for the categories this entry has numbers for
function StandingText_Numbers( vals:table )
	local parts:table = {};
	for _, cat in ipairs( STANDING_CATEGORIES ) do
		if vals[ cat.key ] ~= nil then table.insert( parts, cat.label .. " " .. Round( vals[ cat.key ] ) .. ( cat.perTurn and " per turn" or "" ) ); end
	end
	return table.concat( parts, ", " );
end

-- V list item: "You, Rome: score 190, ..." / "<leader>, <civ>, <relation>. Score 212, ..."
function StandingText_ListItem( entry:table, head:string )
	local numbers:string = StandingText_Numbers( entry.vals );
	if numbers == "" then return head; end
	if entry.isYou then return head .. ": " .. numbers; end
	return head .. ". " .. numbers:sub( 1, 1 ):upper() .. numbers:sub( 2 );
end

-- Rank of entries[index] in a category: 1 + the number of civs strictly ahead (rounded values), and whether another civ is level.
function StandingText_Rank( entries:table, index:number, key:string )
	local mine:number = Round( entries[ index ].vals[ key ] );
	local rank:number, tied:boolean = 1, false;
	for i, e in ipairs( entries ) do
		if i ~= index and e.vals[ key ] ~= nil then
			local v:number = Round( e.vals[ key ] );
			if v > mine then rank = rank + 1; elseif v == mine then tied = true; end
		end
	end
	return rank, tied;
end

-- The Control+R line. entries includes the local player at selfIndex; only known civs are in it.
function StandingText_Line( entries:table, selfIndex:number )
	if #entries < 2 then return "You have met no other civilization yet"; end
	local parts:table = {};
	local worst:table = nil;
	for _, cat in ipairs( STANDING_CATEGORIES ) do
		if entries[ selfIndex ].vals[ cat.key ] ~= nil then
			local rank:number, tied:boolean = StandingText_Rank( entries, selfIndex, cat.key );
			table.insert( parts, cat.label .. " " .. ( tied and "tied " or "" ) .. StandingText_Ordinal( rank ) );
			if rank > 1 and ( worst == nil or rank > worst.rank ) then worst = { cat = cat, rank = rank }; end
		end
	end
	if #parts == 0 then return "This game shows no standings"; end
	local line:string = "Among " .. #entries .. " known civilizations: " .. table.concat( parts, ", " );
	if worst == nil then return line .. ". You lead or share the lead in every category"; end
	-- the best other civ in the weakest category
	local leader:table, best:number = nil, nil;
	for i, e in ipairs( entries ) do
		local v = e.vals[ worst.cat.key ];
		if i ~= selfIndex and v ~= nil and ( best == nil or Round( v ) > best ) then leader = e; best = Round( v ); end
	end
	return line .. ". Weakest: " .. worst.cat.label .. ", " .. leader.name .. " leads with " .. best
		.. ( worst.cat.perTurn and " per turn" or "" );
end
