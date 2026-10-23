-- ===========================================================================
--	RankingsText: pure text helpers for the World Rankings screen (PartialScreens/WorldRankings.lua).
--	No engine calls except CleanTextForSpeech (ScreenReader.lua); everything gets its inputs as arguments so
--	test/lua/test_rankingstext.lua can check the wording.
-- ===========================================================================

include( "ScreenReader" );

local ORDINALS:table = { "first", "second", "third", "fourth", "fifth", "sixth", "seventh", "eighth", "ninth" };

-- "first" .. "ninth", then "10th", "11th" ...
function RankingsText_Ordinal( n:number )
	if ORDINALS[ n ] ~= nil then return ORDINALS[ n ]; end
	local last:number = n % 10;
	local suffix:string = "th";
	if n % 100 < 11 or n % 100 > 13 then
		if last == 1 then suffix = "st"; elseif last == 2 then suffix = "nd"; elseif last == 3 then suffix = "rd"; end
	end
	return n .. suffix;
end

-- "1 point", "3 points"
function RankingsText_Count( n:number, one:string, many:string )
	return n .. " " .. ( n == 1 and one or many );
end

-- "a", "a and b", "a, b and c"
function RankingsText_And( names:table )
	if #names == 0 then return ""; end
	if #names == 1 then return names[1]; end
	local head:table = {};
	for i = 1, #names - 1 do head[i] = names[i]; end
	return table.concat( head, ", " ) .. " and " .. names[ #names ];
end

-- Joins the non-empty parts: "a, b, c".
function RankingsText_Join( parts:table, sep:string )
	local kept:table = {};
	for _, part in ipairs( parts ) do
		if part ~= nil and part ~= "" then table.insert( kept, part ); end
	end
	return table.concat( kept, sep or ", " );
end

-- Game text for speech: the check mark and bolt icons of the requirement lists become words, [NEWLINE] a full stop.
function RankingsText_Clean( text:string )
	if text == nil then return ""; end
	text = string.gsub( text, "%[ICON_CheckmarkBlue%]", "done: " );
	text = string.gsub( text, "%[ICON_Bolt%]", "not yet: " );
	text = CleanTextForSpeech( text );
	for i = 1, 2 do
		text = string.gsub( text, "%.%s*%.", "." );
		text = string.gsub( text, "%s+([%.,:])", "%1" );
	end
	return text;
end

-- Whole percent of a/b, 0 when b is not positive.
function RankingsText_Percent( a:number, b:number )
	if b == nil or b <= 0 then return 0; end
	return math.floor( 100 * a / b + 0.5 );
end

-- Name of a civ for a ranking line: the local player is "You (Name)".
function RankingsText_Label( name:string, isYou:boolean )
	if isYou then return "You (" .. name .. ")"; end
	return name;
end

-- Score tab: "1. Phoenicia, 412 points"
function RankingsText_ScoreLine( rank:number, label:string, score:number )
	return rank .. ". " .. label .. ", " .. RankingsText_Count( score, "point", "points" );
end

-- Position (1-based) of the first entry whose isMine(entry) is true, nil when none.
function RankingsText_PositionOf( entries:table, isMine )
	for i, entry in ipairs( entries ) do
		if isMine( entry ) then return i; end
	end
	return nil;
end

-- Overview tab: "Science Victory: Phoenicia leading. You are in third place."
-- leading = the screen's own line (already names the leader or says "You are leading"); position = our place or nil.
function RankingsText_OverviewLine( victory:string, leading:string, position:number, youLeading:boolean )
	local parts:table = { RankingsText_Clean( leading ) };
	if position ~= nil and not youLeading then
		table.insert( parts, "You are in " .. RankingsText_Ordinal( position ) .. " place" );
	end
	return victory .. ": " .. RankingsText_Join( parts, ". " );
end

-- Overview Space: "1. Phoenicia: Tourism per turn 12, Culture per turn 30. 2. You (Rome): ..." from { label, summary } entries.
function RankingsText_OverviewDetail( entries:table )
	local parts:table = {};
	for i, entry in ipairs( entries ) do
		table.insert( parts, i .. ". " .. RankingsText_Join( { entry.label, entry.summary }, ": " ) );
	end
	return table.concat( parts, ". " );
end

-- Science tab: "Rome: 1 of 4 milestones done, next: Moon landing 40 percent, no spaceport"
-- stages = { { name, progress, total }, ... } in milestone order (names may be nil: "milestone N").
function RankingsText_Science( label:string, stages:table, hasSpaceport:boolean )
	local done:number = 0;
	local upcoming:table = nil;
	for i, stage in ipairs( stages ) do
		local finished:boolean = stage.total > 0 and stage.progress >= stage.total;
		if finished then
			done = done + 1;
		elseif upcoming == nil then
			upcoming = { name = stage.name or ( "milestone " .. i ), pct = RankingsText_Percent( stage.progress, stage.total ) };
		end
	end
	local parts:table = { label .. ": " .. done .. " of " .. #stages .. " milestones done" };
	if upcoming ~= nil then
		table.insert( parts, "next: " .. upcoming.name .. " " .. upcoming.pct .. " percent" );
	end
	if not hasSpaceport then table.insert( parts, "no spaceport" ); end
	return RankingsText_Join( parts, ", " );
end

-- Culture tab: "Rome: 3 of 56 visiting tourists needed, 12 domestic tourists, victory in 25 turns"
function RankingsText_Culture( label:string, visiting:number, needed:number, domestic:number, turns:number, fromYou:number )
	local parts:table = {
		label .. ": " .. visiting .. " of " .. needed .. " visiting tourists needed",
		RankingsText_Count( domestic, "domestic tourist", "domestic tourists" ),
	};
	if turns ~= nil and turns > 0 then table.insert( parts, "victory in " .. RankingsText_Count( turns, "turn", "turns" ) ); end
	if fromYou ~= nil then table.insert( parts, RankingsText_Count( fromYou, "of your tourists visits", "of your tourists visit" ) .. " them" ); end
	return RankingsText_Join( parts, ", " );
end

-- Domination tab: "Rome: holds its original capital, captured 2 capitals: Phoenicia and Greece"
function RankingsText_Domination( label:string, hasCapital:boolean, captured:table )
	local parts:table = { label .. ": " .. ( hasCapital and "holds its original capital" or "has lost its original capital" ) };
	if #captured == 0 then
		table.insert( parts, "no capitals captured" );
	else
		table.insert( parts, "captured " .. RankingsText_Count( #captured, "capital", "capitals" ) .. ": " .. RankingsText_And( captured ) );
	end
	return RankingsText_Join( parts, ", " );
end

-- Religion tab: "Rome: founded Judaism, converted 2 of 6 civilizations: Phoenicia and You"
function RankingsText_Religion( label:string, religion:string, converted:table, total:number )
	local parts:table = { label .. ": founded " .. religion };
	local text:string = "converted " .. #converted .. " of " .. total .. " civilizations";
	if #converted > 0 then text = text .. ": " .. RankingsText_And( converted ); end
	table.insert( parts, text );
	return RankingsText_Join( parts, ", " );
end

-- Diplomatic tab: "Rome: 4 of 20 diplomatic victory points"
function RankingsText_Diplomatic( label:string, points:number, total:number )
	return label .. ": " .. points .. " of " .. total .. " diplomatic victory points";
end

-- Tab announcement: "Score, 2 of 7 tabs"
function RankingsText_Tab( label:string, index:number, count:number )
	return label .. ", " .. index .. " of " .. count .. ( count == 1 and " tab" or " tabs" );
end
