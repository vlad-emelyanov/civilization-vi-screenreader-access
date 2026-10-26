-- TreeText: pure text helpers for the tech tree and the civics tree (TechTree.lua / CivicsTree.lua via TreeNav.lua).
-- No engine calls, tested in test/lua/test_treetext.lua. Names arrive already localized and cleaned for speech.
--------------------------------------------------------------

-- Total turns of a queue from the per-entry turns the game reports. Those are cumulative (turns until that entry is done),
-- so they never decrease along the queue and the total is the last one; summing them double counts. Values that do
-- decrease somewhere are independent estimates and are summed.
function TreeText_QueueTotal( each:table )
	local n:number = #each;
	if n == 0 then return 0; end
	local cumulative:boolean = true;
	for i = 2, n do
		if each[i] < each[i - 1] then cumulative = false; end
	end
	if cumulative then return each[n]; end
	local sum:number = 0;
	for i = 1, n do sum = sum + each[i]; end
	return sum;
end

-- "1 turn" / "5 turns"
function TreeText_Turns( n:number )
	if n == 1 then return "1 turn"; end
	return n .. " turns";
end

-- 1st, 2nd, 3rd, 4th ... 11th, 12th, 13th, 21st
function TreeText_Ordinal( n:number )
	local tens:number = n % 100;
	local last:number = n % 10;
	local suffix:string = "th";
	if tens < 11 or tens > 13 then
		if last == 1 then suffix = "st"; elseif last == 2 then suffix = "nd"; elseif last == 3 then suffix = "rd"; end
	end
	return n .. suffix;
end

-- "A, B, C"; with maxShown "A, B, C and 2 more".
function TreeText_List( names:table, maxShown:number )
	if maxShown ~= nil and #names > maxShown then
		local shown:table = {};
		for i = 1, maxShown do shown[i] = names[i]; end
		return table.concat( shown, ", " ) .. " and " .. ( #names - maxShown ) .. " more";
	end
	return table.concat( names, ", " );
end

-- "Ancient Era, 1 of 8 eras"
function TreeText_Era( eraName:string, index:number, count:number )
	return eraName .. ", " .. index .. " of " .. count .. ( count == 1 and " era" or " eras" );
end

-- "Researching Archery, 5 turns" / "Not researching anything" (label e.g. "Researching", idle e.g. "Not researching anything")
function TreeText_Current( label:string, idle:string, name:string, turns:number )
	if name == nil or name == "" then return idle; end
	local text:string = label .. " " .. name;
	if turns ~= nil and turns > 0 then text = text .. ", " .. TreeText_Turns( turns ); end
	return text;
end

-- One node, spoken when the focus lands on it.
--	info: name, status ("researched" | "current" | "available" | "blocked" | "unrevealed"), turns, boosted (true/false/nil),
--	      queuePos (position in the queue, current = 1), needs (names of missing prerequisites), currentWord
-- "Masonry, researched" / "Bronze Working, available, 4 turns, boosted" / "Iron Working, 9 turns, needs Bronze Working" /
-- "Archery, currently researching, 5 turns" / "Mining, available, 3 turns, queued 2nd"
function TreeText_Item( info:table )
	local status:string = info.status;
	if status == "unrevealed" then return "Not revealed yet"; end
	local parts:table = { info.name };
	if status == "researched" then
		table.insert( parts, "researched" );
		return table.concat( parts, ", " );
	end
	if status == "current" then
		table.insert( parts, info.currentWord or "currently researching" );
	elseif status == "available" then
		table.insert( parts, "available" );
	end
	if info.turns ~= nil and info.turns > 0 then
		-- a blocked node's turns are for that node alone (not the way to it): say so (info.alone = "tech" / "civic")
		local alone:string = ( status == "blocked" and info.alone ~= nil ) and ( " for this " .. info.alone .. " alone" ) or "";
		table.insert( parts, TreeText_Turns( info.turns ) .. alone );
	end
	if status == "available" and info.boosted == true then table.insert( parts, "boosted" ); end
	if status == "blocked" and info.needs ~= nil and #info.needs > 0 then
		table.insert( parts, "needs " .. table.concat( info.needs, " and " ) );
	end
	if status ~= "current" and info.queuePos ~= nil and info.queuePos > 0 then
		table.insert( parts, "queued " .. TreeText_Ordinal( info.queuePos ) );
	end
	return table.concat( parts, ", " );
end

-- unlocks: { { kind = "KIND_UNIT", name = "Archer" }, ... } -> "Units: Archer, Slinger. Buildings: Barracks"
local KIND_ORDER:table = {
	"KIND_GOVERNMENT", "KIND_POLICY", "KIND_UNIT", "KIND_BUILDING", "KIND_WONDER", "KIND_DISTRICT", "KIND_IMPROVEMENT",
	"KIND_PROJECT", "KIND_RESOURCE", "KIND_DIPLOMATIC_ACTION",
};
local KIND_LABEL:table = {
	KIND_GOVERNMENT = "Governments", KIND_POLICY = "Policies", KIND_UNIT = "Units", KIND_BUILDING = "Buildings",
	KIND_WONDER = "Wonders", KIND_DISTRICT = "Districts", KIND_IMPROVEMENT = "Improvements", KIND_PROJECT = "Projects",
	KIND_RESOURCE = "Reveals resources", KIND_DIPLOMATIC_ACTION = "Diplomatic actions",
};

function TreeText_Unlocks( unlocks:table )
	if unlocks == nil or #unlocks == 0 then return "Unlocks nothing"; end
	local byKind:table = {};
	for _, u in ipairs( unlocks ) do
		local kind:string = u.kind;
		if KIND_LABEL[ kind ] == nil then kind = "OTHER"; end
		byKind[ kind ] = byKind[ kind ] or {};
		table.insert( byKind[ kind ], u.name );
	end
	local groups:table = {};
	for _, kind in ipairs( KIND_ORDER ) do
		if byKind[ kind ] ~= nil then table.insert( groups, KIND_LABEL[ kind ] .. ": " .. table.concat( byKind[ kind ], ", " ) ); end
	end
	if byKind.OTHER ~= nil then table.insert( groups, "Also: " .. table.concat( byKind.OTHER, ", " ) ); end
	return "Unlocks " .. table.concat( groups, ". " );
end

-- Space on a node. d: name, statusText (the TreeText_Item line), cost, progress, rate, rateWord ("science" / "culture"),
-- unlocks, boost { word = "Eureka"/"Inspiration", text = condition, done = bool }, prereqs (names), leads (names), leadsHidden (number of
-- unrevealed followers), hiddenWord ("tech" / "civic"), description
function TreeText_Detail( d:table )
	local parts:table = { d.statusText or d.name };
	if d.cost ~= nil and d.cost > 0 then
		local cost:string = "Cost " .. d.cost .. " " .. ( d.rateWord or "" );
		if d.progress ~= nil and d.progress > 0 then cost = cost .. ", " .. d.progress .. " done"; end
		if d.rate ~= nil then
			if d.rate <= 0 then
				cost = cost .. ". You make no " .. ( d.rateWord or "yield" );
			else
				cost = cost .. ". You make " .. d.rate .. " per turn";
			end
		end
		table.insert( parts, cost );
	end
	table.insert( parts, TreeText_Unlocks( d.unlocks ) );
	if d.boost ~= nil and d.boost.text ~= nil and d.boost.text ~= "" then
		table.insert( parts, d.boost.word .. ( d.boost.done and " done: " or ", not done yet: " ) .. d.boost.text );
	end
	if d.prereqs ~= nil and #d.prereqs > 0 then
		table.insert( parts, "Requires " .. table.concat( d.prereqs, ", " ) );
	else
		table.insert( parts, "No prerequisites" );
	end
	local leads:string = ( d.leads ~= nil and #d.leads > 0 ) and table.concat( d.leads, ", " ) or nil;
	if d.leadsHidden ~= nil and d.leadsHidden > 0 then
		-- Tech/Civic Shuffle: the tree shows these as "Not revealed yet", so they are counted, not named
		local word:string = d.hiddenWord or "item";
		local hidden:string = d.leadsHidden .. " unrevealed " .. word .. ( d.leadsHidden == 1 and "" or "s" );
		leads = ( leads ~= nil ) and ( leads .. " and " .. hidden ) or hidden;
	end
	if leads ~= nil then table.insert( parts, "Leads to " .. leads ); end
	if d.description ~= nil and d.description ~= "" then table.insert( parts, d.description ); end
	return table.concat( parts, ". " );
end

-- Result of Enter / Shift+Enter, read back from the queue. prefix "Target" or "Added to queue".
-- "Target: Iron Working, path: Bronze Working, Iron Working, 13 turns"
function TreeText_Queue( prefix:string, target:string, path:table, turns:number )
	local text:string = prefix .. ": " .. target;
	if path ~= nil and #path > 1 then text = text .. ", path: " .. table.concat( path, ", " ); end
	if turns ~= nil and turns > 0 then text = text .. ", " .. TreeText_Turns( turns ); end
	return text;
end

-- Missing nodes on the way to key: every not yet researched prerequisite (transitively) and key itself, each once,
-- prerequisites first. prereqsOf(key) -> keys, done(key) -> boolean (researched).
function TreeText_Path( key, prereqsOf, done )
	local seen:table = {};
	local path:table = {};
	local function Visit( k )
		if seen[ k ] or done( k ) then return; end
		seen[ k ] = true;
		for _, p in ipairs( prereqsOf( k ) or {} ) do Visit( p ); end
		table.insert( path, k );
	end
	Visit( key );
	return path;
end

local function PathCount( count:number, word:string )
	return count .. " " .. word .. ( count == 1 and "" or "s" );
end

local function PathTurns( turns:number )
	if turns == nil or turns <= 0 then return ""; end
	return ", about " .. TreeText_Turns( turns );
end

-- Enter on a node that is not researchable yet:
-- "Political Philosophy set as the target: 3 civics on the way, about 26 turns. Next: Code of Laws, 4 turns."
-- word "tech" / "civic"; nextName / nextTurns = what the game started on (optional)
function TreeText_FarTarget( name:string, word:string, count:number, turns:number, nextName, nextTurns, replaced )
	local text:string = name .. " set as the target: " .. PathCount( count, word ) .. " on the way" .. PathTurns( turns ) .. ".";
	if nextName ~= nil and nextName ~= "" then
		text = text .. " Next: " .. nextName;
		if nextTurns ~= nil and nextTurns > 0 then text = text .. ", " .. TreeText_Turns( nextTurns ); end
		if replaced ~= nil and replaced ~= "" then text = text .. ", replaces " .. replaced; end
		text = text .. ".";
	end
	return text;
end

-- Shift+Enter on a node that is not researchable yet: "Queued Political Philosophy: 3 civics, about 26 turns."
function TreeText_FarQueued( name:string, word:string, count:number, turns:number )
	return "Queued " .. name .. ": " .. PathCount( count, word ) .. PathTurns( turns ) .. ".";
end

-- Appended to the current research line when the queue ends in a further target:
-- "Target: Political Philosophy, about 26 turns"
function TreeText_TargetSuffix( name:string, turns:number )
	return "Target: " .. name .. PathTurns( turns );
end

-- entries: { { key, name, era (number), eraName, column, row }, ... } -> eras in order, each with its items in tree order
-- (column, then row, then name): { { era = 0, name = "Ancient Era", items = { entry, ... } }, ... }
function TreeText_Group( entries:table )
	local byEra:table = {};
	local eras:table = {};
	for _, e in ipairs( entries ) do
		local g:table = byEra[ e.era ];
		if g == nil then
			g = { era = e.era, name = e.eraName, items = {} };
			byEra[ e.era ] = g;
			table.insert( eras, g );
		end
		table.insert( g.items, e );
	end
	table.sort( eras, function( a, b ) return a.era < b.era; end );
	for _, g in ipairs( eras ) do
		table.sort( g.items, function( a, b )
			if ( a.column or 0 ) ~= ( b.column or 0 ) then return ( a.column or 0 ) < ( b.column or 0 ); end
			if ( a.row or 0 ) ~= ( b.row or 0 ) then return ( a.row or 0 ) < ( b.row or 0 ); end
			return a.name < b.name;
		end );
	end
	return eras;
end

-- First entry (in the order given, i.e. the tree's) whose name starts with the query, else the first that contains it.
-- Case-insensitive, plain text. Returns the entry or nil.
function TreeText_Match( entries:table, query:string )
	if query == nil then return nil; end
	query = string.gsub( query, "^%s+", "" );
	query = string.gsub( query, "%s+$", "" );
	query = string.lower( query );
	if query == "" then return nil; end
	local contains:table = nil;
	for _, e in ipairs( entries ) do
		local name:string = string.lower( e.name );
		local pos = string.find( name, query, 1, true );
		if pos == 1 then return e; end
		if pos ~= nil and contains == nil then contains = e; end
	end
	return contains;
end
