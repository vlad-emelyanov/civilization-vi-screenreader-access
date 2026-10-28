-- ===========================================================================
--	GreatPeopleText: spoken text for the Great People popup (GreatPeoplePopup). Pure functions, no engine calls.
--
--	A person (current view):
--		className, name, eraName, points, cost, perTurn (the local player's), leaderName/leaderPoints (the best OTHER
--		civilization, nil when nobody else has points), standings = { {name=, points=, perTurn=, isPlayer=}, ... },
--		abilities = { "text", ... }, earnConditions (string or nil), none = true when every person of the class is claimed,
--		canRecruit, recruitCost, canReject, rejectCost, readOnly,
--		gold / faith = { shown=, cost=, can=, have=, off= }  (shown: the game shows the patronage button)
--	A past person: className, name, eraName, date, claimant ("Rome", "you", "an unknown civilization"), abilities.
-- ===========================================================================

function GreatPeopleText_Num( n:number )
	if n == nil then return "0"; end
	local rounded:number = math.floor( n * 10 + 0.5 ) / 10;
	if rounded == math.floor( rounded ) then return tostring( math.floor( rounded ) ); end
	return tostring( rounded );
end

-- "can't afford, need 120 more gold" / "affordable"
function GreatPeopleText_Afford( opt:table, unit:string )
	if opt.can then return "affordable"; end
	local need:number = ( opt.cost or 0 ) - ( opt.have or 0 );
	if need > 0 then return "can't afford, need " .. GreatPeopleText_Num( need ) .. " more " .. unit; end
	return "not possible now";
end

-- Why a shown patronage button is disabled.
function GreatPeopleText_PatronageReason( p:table, opt:table, unit:string )
	if opt.off then return "Patronage with " .. unit .. " is turned off"; end
	if p.readOnly then return "Not possible during the World Congress"; end
	local need:number = ( opt.cost or 0 ) - ( opt.have or 0 );
	if need > 0 then return "Can't afford, need " .. GreatPeopleText_Num( need ) .. " more " .. unit; end
	if p.earnConditions ~= nil and p.earnConditions ~= "" then return "Can't earn this person: " .. p.earnConditions; end
	return "Not possible now, someone may already have enough points or you passed this person";
end

-- The game's era names already end in "Era" ("Atomic Era"): do not say it twice.
function GreatPeopleText_Era( eraName:string )
	if eraName == nil or eraName == "" then return nil; end
	if string.lower( string.sub( eraName, -4 ) ) == " era" then return eraName; end
	return eraName .. " era";
end

local function Leader( p:table )
	if p.leaderName == nil then return nil; end
	if p.leaderPoints > p.points then return p.leaderName .. " leads with " .. GreatPeopleText_Num( p.leaderPoints ); end
	if p.points > 0 then return "you lead"; end
	return nil;
end

-- "Great Scientist Hypatia, 120 of 480 points, 640 gold" (+ ", can buy" when the gold patronage is affordable).
-- Rate, leader, faith and shortfalls are in the Space detail.
function GreatPeopleText_Item( p:table )
	if p.none then return p.className .. ": none left, all claimed"; end
	local text:string = p.className .. " " .. p.name .. ", " .. GreatPeopleText_Num( p.points ) .. " of "
		.. GreatPeopleText_Num( p.cost ) .. " points";
	if p.canRecruit then
		text = text .. ", you can recruit now";
		if p.canReject then text = text .. " or pass"; end
	elseif p.canReject then
		text = text .. ", you can pass";
	elseif p.gold ~= nil and p.gold.shown then
		text = text .. ", " .. GreatPeopleText_Num( p.gold.cost ) .. " gold";
		if p.gold.can then text = text .. ", can buy"; end
	end
	return text;
end

-- Patronage lines for the detail: "640 gold, can't afford, need 120 more gold", "320 faith, affordable"
function GreatPeopleText_PatronageLines( p:table )
	local lines:table = {};
	if p.canRecruit or p.canReject then return lines; end
	if p.gold ~= nil and p.gold.shown then
		table.insert( lines, GreatPeopleText_Num( p.gold.cost ) .. " gold, " .. GreatPeopleText_Afford( p.gold, "gold" ) );
	end
	if p.faith ~= nil and p.faith.shown then
		table.insert( lines, GreatPeopleText_Num( p.faith.cost ) .. " faith, " .. GreatPeopleText_Afford( p.faith, "faith" ) );
	end
	return lines;
end

-- Space: abilities, era, the points of every civilization.
function GreatPeopleText_Detail( p:table )
	if p.none then return p.className .. ": every great person of this kind has been claimed"; end
	local parts:table = { p.className .. " " .. p.name };
	table.insert( parts, "You earn " .. GreatPeopleText_Num( p.perTurn ) .. " points per turn" );
	local lead:string = Leader( p );
	if lead ~= nil then table.insert( parts, lead ); end
	for _, line in ipairs( GreatPeopleText_PatronageLines( p ) ) do table.insert( parts, line ); end
	local era:string = GreatPeopleText_Era( p.eraName );
	if era ~= nil then table.insert( parts, era ); end
	for _, ability in ipairs( p.abilities or {} ) do table.insert( parts, ability ); end
	if p.earnConditions ~= nil and p.earnConditions ~= "" then table.insert( parts, "You can't earn this person yet: " .. p.earnConditions ); end
	local standings:table = {};
	for _, s in ipairs( p.standings or {} ) do
		table.insert( standings, s.name .. ( s.isPlayer and " (you)" or "" ) .. " " .. GreatPeopleText_Num( s.points )
			.. " of " .. GreatPeopleText_Num( p.cost ) .. ", " .. GreatPeopleText_Num( s.perTurn ) .. " per turn" );
	end
	if #standings > 0 then table.insert( parts, "Points: " .. table.concat( standings, "; " ) ); end
	return table.concat( parts, ". " );
end

local function PatronageAction( p:table, opt:table, run:string, unit:string )
	local enabled:boolean = opt.can and not p.readOnly;
	local text:string = "Patronize with " .. unit .. ", " .. GreatPeopleText_Num( opt.cost );
	local reason:string = GreatPeopleText_PatronageReason( p, opt, unit );
	if not enabled then text = text .. ", unavailable: " .. string.lower( reason ); end
	return { key = run, run = run, enabled = enabled, text = text, reason = reason };
end

-- Enter: the actions of the person. Each: key, text, enabled, reason (when disabled), run = "recruit"|"reject"|"gold"|"faith"|"back".
function GreatPeopleText_Actions( p:table )
	local list:table = {};
	if p.canRecruit then
		table.insert( list, { key = "recruit", run = "recruit", enabled = true,
			text = "Recruit " .. p.name .. ", costs " .. GreatPeopleText_Num( p.recruitCost ) .. " points" } );
	end
	if p.canReject then
		table.insert( list, { key = "reject", run = "reject", enabled = true,
			text = "Pass on " .. p.name .. ", costs " .. GreatPeopleText_Num( p.rejectCost ) .. " points" } );
	end
	if p.gold ~= nil and p.gold.shown then table.insert( list, PatronageAction( p, p.gold, "gold", "gold" ) ); end
	if p.faith ~= nil and p.faith.shown then table.insert( list, PatronageAction( p, p.faith, "faith", "faith" ) ); end
	table.insert( list, { key = "back", run = "back", enabled = true, text = "Back" } );
	return list;
end

function GreatPeopleText_ActionsTitle( p:table )
	return "Actions for " .. p.name;
end

-- Past view: "Hypatia, Great Scientist, recruited by Rome, 3500 BC"
function GreatPeopleText_PastItem( p:table )
	local text:string = p.name .. ", " .. p.className;
	if p.claimant ~= nil then text = text .. ", recruited by " .. p.claimant; end
	if p.date ~= nil and p.date ~= "" then text = text .. ", " .. p.date; end
	return text;
end

function GreatPeopleText_PastDetail( p:table )
	local parts:table = { GreatPeopleText_PastItem( p ) };
	local era:string = GreatPeopleText_Era( p.eraName );
	if era ~= nil then table.insert( parts, era ); end
	for _, ability in ipairs( p.abilities or {} ) do table.insert( parts, ability ); end
	return table.concat( parts, ". " );
end

-- "Great People, 9 available. <item>, 1 of 9" / "Previously recruited, 12 people. <item>, 1 of 12"
function GreatPeopleText_Opening( past:boolean, count:number, itemText:string, index:number, total:number )
	local head:string;
	if past then
		head = "Previously recruited, " .. count .. ( count == 1 and " person" or " people" );
	else
		head = "Great People, " .. count .. " available";
	end
	if itemText == nil then return head; end
	return head .. ". " .. itemText .. ", " .. index .. " of " .. total;
end
