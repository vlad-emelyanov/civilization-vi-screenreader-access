-- ===========================================================================
--	WorldCongressText: pure text helpers for the World Congress screens (UI/Replacements/WorldCongress*_SRA.lua).
--	No engine calls: plain data in, sentences out (offline tests: test/lua/test_worldcongresstext.lua).
-- ===========================================================================

-- "Trailing dots and spaces dropped", so pieces can be joined with ", " or ". ".
function WCText_Strip( text )
	if text == nil then return ""; end
	text = string.gsub( tostring( text ), "^%s+", "" );
	text = string.gsub( text, "[%s%.]+$", "" );
	return text;
end

function WCText_Letter( option )
	if option == 2 then return "B"; end
	return "A";
end

function WCText_Plural( n, one, many )
	if n == 1 then return n .. " " .. one; end
	return n .. " " .. ( many or ( one .. "s" ) );
end

-- Number of entries of a cost table ({ [0] = cost of 1 vote, [1] = cost of 2 votes, ..., MaxVotes = n }).
local function CostCount( costData )
	local n = 0;
	while costData[ n ] ~= nil do n = n + 1; end
	return n;
end

-- "1st vote free, 2nd 10 favor, 3rd 30 favor" (at most maxShown entries)
function WCText_CostList( costData, maxShown )
	if costData == nil then return ""; end
	maxShown = maxShown or 4;
	local count:number = CostCount( costData );
	local parts:table = {};
	local previous:number = 0;
	for i = 1, math.min( count, maxShown ) do
		local total:number = costData[ i - 1 ];
		local step:number = total - previous;
		previous = total;
		local ord:string = ( i == 1 ) and "1st" or ( i == 2 ) and "2nd" or ( i == 3 ) and "3rd" or ( i .. "th" );
		if step == 0 then
			table.insert( parts, ord .. " vote free" );
		else
			table.insert( parts, ord .. " vote " .. step .. " favor" );
		end
	end
	local text:string = table.concat( parts, ", " );
	if count > maxShown then text = text .. ", up to " .. ( costData.MaxVotes or count ) .. " votes"; end
	return text;
end

-- Why a resolution vote change is refused (mirrors OnVoteResolution of WorldCongressPopup), or nil when it is allowed.
-- votes: current votes on this option; direction: +1 / -1; costData: GetVotesandFavorCost(); favorLeft: working favor.
function WCText_VoteBlock( votes, direction, costData, favorLeft )
	local nextVotes:number = votes + direction;
	if nextVotes < 1 then
		if votes <= 0 then return "No votes to remove"; end
		return "At least one vote is needed. Vote for the other option to switch";
	end
	local maxVotes:number = costData.MaxVotes or CostCount( costData );
	if nextVotes > CostCount( costData ) or nextVotes > maxVotes then
		return "No more votes available, the maximum is " .. maxVotes;
	end
	if direction > 0 then
		local nextCost:number = costData[ nextVotes - 1 ];
		local currCost:number = ( votes > 0 ) and costData[ votes - 1 ] or 0;
		if nextCost - currCost > favorLeft then
			return "Not enough favor, the next vote costs " .. ( nextCost - currCost ) .. " and you have " .. favorLeft;
		end
	end
	return nil;
end

-- "2 votes for A, costs 10 favor"
function WCText_VotesPhrase( votes, letter, cost )
	local text:string = WCText_Plural( votes, "vote" ) .. " for " .. letter;
	if cost ~= nil and cost > 0 then
		text = text .. ", costs " .. cost .. " favor";
	elseif votes > 0 then
		text = text .. ", free";
	end
	return text;
end

-- Cost of the next vote after `votes` votes: returns favor (number, 0 = free) or nil when no more votes can be added.
local function NextVoteCost( votes, costData )
	if costData == nil then return nil; end
	local count:number = CostCount( costData );
	local maxVotes:number = costData.MaxVotes or count;
	if votes + 1 > count or votes + 1 > maxVotes then return nil; end
	local current:number = ( votes > 0 ) and costData[ votes - 1 ] or 0;
	return costData[ votes ] - current;
end

-- "next vote 20 favor" / "next vote free" / "maximum votes" (spoken after a vote changed); "" without cost data or votes.
function WCText_NextCostPhrase( votes, costData )
	if costData == nil or votes == nil or votes <= 0 then return ""; end
	local cost = NextVoteCost( votes, costData );
	if cost == nil then return "maximum votes"; end
	if cost == 0 then return "next vote free"; end
	return "next vote " .. cost .. " favor";
end

-- What the equals / minus keys do next on a held vote: "equals adds a vote for 20 favor, minus removes one".
-- addKey / removeKey / what: for a resolution "equals", "minus", "a vote"; for a proposal against: "minus", "equals", "a vote against".
local function NextStep( votes, costData, addKey, removeKey, what )
	if costData == nil or votes <= 0 then return ""; end
	local cost = NextVoteCost( votes, costData );
	local text:string;
	if cost == nil then
		text = "maximum votes";
	elseif cost == 0 then
		text = addKey .. " adds " .. what .. ", free";
	else
		text = addKey .. " adds " .. what .. " for " .. cost .. " favor";
	end
	if votes > 1 then text = text .. ", " .. removeKey .. " removes one"; end
	return text;
end

-- One resolution while voting.
-- d: name, focus (1/2, the option being looked at), effect (text of the focused option), chosen (0/1/2, the option
-- holding the votes), votes, cost, target (text or nil), needsTarget (bool);
-- omitName (bool, only "Option B: ..." without the resolution name); optional: costData (GetVotesandFavorCost, adds "equals adds a vote for N favor"), hint (bool, adds the key hint when no votes)
function WCText_ResolutionLine( d )
	local letter:string = WCText_Letter( d.focus );
	local parts:table;
	if d.omitName then		-- a Left / Right switch within the resolution: the name was just spoken
		parts = { "Option " .. letter .. ": " .. WCText_Strip( d.effect ) };
	else
		parts = { d.name .. ", option " .. letter .. ": " .. WCText_Strip( d.effect ) };
	end
	if d.chosen == d.focus and d.votes > 0 then
		table.insert( parts, "your votes: " .. WCText_VotesPhrase( d.votes, letter, d.cost ) );
		if d.needsTarget then
			table.insert( parts, "target: " .. ( d.target or "none" ) );
		end
		local step:string = NextStep( d.votes, d.costData, SRKey( "equals", "X" ), SRKey( "minus", "LT" ), "a vote" );
		if step ~= "" then table.insert( parts, step ); end
	elseif d.chosen ~= 0 and d.votes > 0 then
		table.insert( parts, "your votes are on option " .. WCText_Letter( d.chosen ) );
	else
		table.insert( parts, "no votes yet" );
		if d.hint then table.insert( parts, SRKey( "equals", "X" ) .. " adds a vote, " .. SRKey( "Left and Right" ) .. " switch option" ); end
	end
	return table.concat( parts, ", " );
end

-- A proposal (discussion / emergency) while voting. votes is signed: > 0 for, < 0 against, 0 none.
-- Optional costData / hint as for WCText_ResolutionLine.
function WCText_ProposalLine( title, description, votes, cost, costData, hint )
	local text:string = WCText_Strip( title );
	if description ~= nil and WCText_Strip( description ) ~= "" then text = text .. ": " .. WCText_Strip( description ); end
	if votes == nil or votes == 0 then
		text = text .. ", no votes yet";
		if hint then text = text .. ", " .. SRKey( "equals", "X" ) .. " votes for, " .. SRKey( "minus", "LT" ) .. " votes against"; end
	else
		text = text .. ", your votes: " .. WCText_Plural( math.abs( votes ), "vote" ) .. ( votes > 0 and " for" or " against" );
		if cost ~= nil and cost > 0 then text = text .. ", costs " .. cost .. " favor"; end
		local step:string;
		if votes > 0 then
			step = NextStep( votes, costData, SRKey( "equals", "X" ), SRKey( "minus", "LT" ), "a vote" );
		else
			step = NextStep( -votes, costData, SRKey( "minus", "LT" ), SRKey( "equals", "X" ), "a vote against" );
		end
		if step ~= "" then text = text .. ", " .. step; end
	end
	return text;
end

-- What is missing before the votes can be submitted: entries { name, needsVote, needsTarget }.
-- "Mercenary Companies needs a target, Arms Control needs a vote and a target"
function WCText_Missing( entries )
	local parts:table = {};
	for _, e in ipairs( entries ) do
		local needs:table = {};
		if e.needsVote then table.insert( needs, "a vote" ); end
		if e.needsTarget then table.insert( needs, "a target" ); end
		if #needs > 0 then table.insert( parts, e.name .. " needs " .. table.concat( needs, " and " ) ); end
	end
	return table.concat( parts, ", " );
end

-- A resolution in the results (last session / current effects).
-- d: name, label ("A"), tie (bool), target (text or ""), effect, aVotes, bVotes (numbers or nil), turnsLeft (or nil)
function WCText_ReviewResolution( d )
	local parts:table = {};
	local outcome:string = d.name .. ": option " .. ( d.label or "?" );
	if d.aVotes ~= nil then
		outcome = outcome .. ( d.tie and " passed by tie breaker" or " passed" );
	else
		outcome = outcome .. " in effect";
	end
	table.insert( parts, outcome );
	if d.target ~= nil and WCText_Strip( d.target ) ~= "" then table.insert( parts, "target " .. WCText_Strip( d.target ) ); end
	if d.effect ~= nil and WCText_Strip( d.effect ) ~= "" then table.insert( parts, WCText_Strip( d.effect ) ); end
	if d.aVotes ~= nil then
		table.insert( parts, "votes: A " .. d.aVotes .. ", B " .. d.bVotes );
	end
	if d.turnsLeft ~= nil then
		table.insert( parts, WCText_Plural( d.turnsLeft, "turn" ) .. " left" );
	end
	return table.concat( parts, ", " );
end

-- A proposal in the results. upVotes / downVotes are totals.
function WCText_ReviewProposal( title, description, upVotes, downVotes )
	local text:string = WCText_Strip( title );
	if upVotes ~= nil then
		text = text .. ( upVotes > downVotes and " passed" or " failed" ) .. ", " .. upVotes .. " for, " .. downVotes .. " against";
	end
	if description ~= nil and WCText_Strip( description ) ~= "" then text = text .. ". " .. WCText_Strip( description ); end
	return text;
end

-- Players we have not met all show up as "Unmet Player" in the game. tails: one string per unmet player (what they did,
-- e.g. "1 vote for B" or a score; "" for none). Equal tails are merged: { "3 unmet players: 1 vote for B each" }.
function WCText_UnmetGroups( tails )
	local order:table = {};
	local counts:table = {};
	for _, tail in ipairs( tails or {} ) do
		if counts[ tail ] == nil then
			counts[ tail ] = 0;
			table.insert( order, tail );
		end
		counts[ tail ] = counts[ tail ] + 1;
	end
	local groups:table = {};
	for _, tail in ipairs( order ) do
		local n:number = counts[ tail ];
		local text:string = WCText_Plural( n, "unmet player" );
		if tail ~= "" then text = text .. ": " .. tail .. ( n > 1 and " each" or "" ); end
		table.insert( groups, text );
	end
	return groups;
end
