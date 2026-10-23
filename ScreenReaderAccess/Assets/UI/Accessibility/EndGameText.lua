-- ===========================================================================
--	EndGameText: pure text helpers for the end-game screen (EndGame/EndGameMenu.lua).
--	No engine calls; everything gets its inputs as arguments so test/lua/test_endgametext.lua can check the wording.
-- ===========================================================================

-- "DOMINATION VICTORY" -> "Domination victory" (the screen shows the headers in capitals)
function EndGameText_Sentence( text:string )
	if text == nil or text == "" then return ""; end
	local lower:string = string.lower( text );
	return string.upper( string.sub( lower, 1, 1 ) ) .. string.sub( lower, 2 );
end

-- The result as separate lines (the Info tab items):
--	d.Head: "VICTORY" / "DEFEAT" (RibbonText), d.TypeHeader: "Science Victory" (empty for a plain defeat),
--	d.WinnerName, d.IsWinnerLocalPlayer, d.Blurb, d.DefeatedName
function EndGameText_Lines( d:table )
	local lines:table = {};
	local head:string = EndGameText_Sentence( d.Head or "" );
	local typeName:string = EndGameText_Sentence( d.TypeHeader or "" );
	local winner:string = d.WinnerName or "";
	if winner ~= "" then
		local who:string = d.IsWinnerLocalPlayer and ( "you, " .. winner ) or ( "won by " .. winner );
		local text:string = head;
		if typeName ~= "" then text = text .. ": " .. typeName; end
		table.insert( lines, text .. ", " .. who );
	else
		local text:string = head;
		if d.DefeatedName ~= nil and d.DefeatedName ~= "" then text = text .. ": " .. d.DefeatedName; end
		table.insert( lines, text );
	end
	if d.Blurb ~= nil and d.Blurb ~= "" then table.insert( lines, d.Blurb ); end
	if winner ~= "" and d.DefeatedName ~= nil and d.DefeatedName ~= "" then
		table.insert( lines, "Defeated: " .. d.DefeatedName );
	end
	return lines;
end

-- "Victory: Science victory, you, Rome. blurb. Defeated: ..." for the opening sentence
function EndGameText_Summary( d:table )
	return table.concat( EndGameText_Lines( d ), ". " );
end

-- "3. Napoleon, score 350"; the row the player lands on gets ", you are here"
function EndGameText_RankLine( n:number, leader:string, score:string, isYou:boolean )
	local text:string = n .. ". " .. leader .. ", score " .. tostring( score );
	if isYou then text = text .. ", you are here"; end
	return text;
end

local function Number( value:number )
	if value == math.floor( value ) then return string.format( "%d", value ); end
	return string.format( "%.1f", value );
end

-- The last value of a { [turn] = value } table, and its turn.
function EndGameText_LastValue( turnData:table )
	local lastTurn:number = nil;
	for turn, value in pairs( turnData or {} ) do
		if value ~= nil and ( lastTurn == nil or turn > lastTurn ) then lastTurn = turn; end
	end
	if lastTurn == nil then return nil, nil; end
	return turnData[ lastTurn ], lastTurn;
end

-- The graph as a ranking by the last value: { { text = "Rome, Trajan: 812", value = 812 }, ... } highest first.
--	infos: g_PlayerInfos ({ Id, IsMinor, ... }), data: g_GraphData ({ [playerID] = { [turn] = value } }),
--	nameOf(info): spoken name; includeMinor: also city-states.
function EndGameText_GraphLines( infos:table, data:table, nameOf, includeMinor:boolean )
	local rows:table = {};
	for _, info in ipairs( infos or {} ) do
		if includeMinor or not info.IsMinor then
			local value:number = EndGameText_LastValue( data ~= nil and data[ info.Id ] or nil );
			if value ~= nil then
				table.insert( rows, { text = nameOf( info ) .. ": " .. Number( value ), value = value } );
			end
		end
	end
	table.sort( rows, function( a, b ) return a.value > b.value; end );
	return rows;
end
