-- ===========================================================================
--	CombatText: pure wording for the attack preview (strengths and modifier lines). The engine values are read in
--	HubTargets (CombatManager.SimulateAttackInto results); these functions only turn plain numbers / strings into speech.
-- ===========================================================================

-- Pure. Does the target line of a target mode describe a target (so the plot description starts with the target and this line follows
-- it), as opposed to "no target" / "unreachable" / "here" (said first, the plot after it)?
function CombatText_InfoFollowsTarget( info:string )
	if info == nil then return false; end
	return string.find( info, "^valid target" ) ~= nil or string.find( info, "^attack" ) ~= nil or string.find( info, "^would declare war" ) ~= nil;
end

-- Pure. The end of the opening line of an attack mode: "X next target, Enter attacks, Escape cancels" (keys already expanded by the caller).
function CombatText_OpeningLine( label:string, targetLine:string, hints:string )
	if targetLine == nil or targetLine == "" then return label .. ". " .. hints; end
	return label .. ": " .. targetLine .. ". " .. hints;
end

-- Pure. "3 of 5", the last one adds that X wraps.
function CombatText_PositionInList( index:number, count:number )
	if count == nil or count < 2 then return nil; end
	local text:string = index .. " of " .. count;
	if index == count then text = text .. ", X wraps to the first"; end
	return text;
end

-- "plus 2 flanking": the game's modifier lines start with a signed number ("+2 Flanking", "-3 Across a river").
function CombatText_ModifierLine( text:string )
	if text == nil then return ""; end
	text = string.gsub( text, "^%s+", "" );
	text = string.gsub( text, "^%+%s*(%d)", "plus %1" );
	text = string.gsub( text, "^[%-\226\128\147\226\128\148]%s*(%d)", "minus %1" );	-- hyphen, en dash, em dash
	return text;
end

-- "Strength 20 against 17" (defenderTotal nil: only our strength is told; <= 0: "against no defense").
-- prefix: "Strength", "Ranged strength", "Bombard strength".
function CombatText_StrengthPhrase( prefix:string, attackerTotal:number, defenderTotal:number )
	if attackerTotal == nil then return nil; end
	attackerTotal = math.max( 0, math.floor( attackerTotal + 0.5 ) );
	if defenderTotal == nil then return prefix .. " " .. attackerTotal; end
	if defenderTotal <= 0 then return prefix .. " " .. attackerTotal .. " against no defense"; end
	return prefix .. " " .. attackerTotal .. " against " .. math.max( 0, math.floor( defenderTotal + 0.5 ) );
end

-- Base strength plus the modifier total, never below zero (as the game's combat preview shows it).
function CombatText_Total( base:number, modifier:number )
	return math.max( 0, ( base or 0 ) + ( modifier or 0 ) );
end

-- lists of already localised, cleaned lines -> "Your modifiers: ... Their modifiers: ..." (empty on both sides: none).
function CombatText_Modifiers( mine:table, theirs:table )
	local function side( label:string, lines:table )
		if lines == nil or #lines == 0 then return nil; end
		local out:table = {};
		for _, line in ipairs( lines ) do
			local text:string = CombatText_ModifierLine( line );
			if text ~= "" then table.insert( out, text ); end
		end
		if #out == 0 then return nil; end
		return label .. ": " .. table.concat( out, ", " );
	end
	local a:string = side( "Your modifiers", mine );
	local b:string = side( "Their modifiers", theirs );
	if a == nil and b == nil then return "No modifiers on either side"; end
	if a ~= nil and b ~= nil then return a .. ". " .. b; end
	return ( a or b ) .. ( a ~= nil and ". No modifiers for them" or ". No modifiers for you" );
end

-- The unit a shot at a stack really hits: the strongest military unit, never a civilian while a soldier shares the tile
-- (verified in play: a city shot at a captured Builder + Man-At-Arms hit the Man-At-Arms). units: a list of units; accept: optional filter.
function CombatText_PickDefender( units:table, accept )
	local best:table, bestScore:number = nil, -1;
	for _, other in ipairs( units ) do
		if accept == nil or accept( other ) then
			local score:number = ( other:GetCombat() or 0 ) * 1000 + math.max( other:GetRangedCombat() or 0, other:GetBombardCombat() or 0 );		-- melee defense first, ranged only as tie-break
			if score > bestScore then best, bestScore = other, score; end
		end
	end
	return best;
end
