-- ===========================================================================
--	CombatText: pure wording for the attack preview (strengths and modifier lines). The engine values are read in
--	HubTargets (CombatManager.SimulateAttackInto results); these functions only turn plain numbers / strings into speech.
-- ===========================================================================

-- "plus 2 flanking": the game's modifier lines start with a signed number ("+2 Flanking", "-3 Across a river").
function CombatText_ModifierLine( text:string )
	if text == nil then return ""; end
	text = string.gsub( text, "^%s+", "" );
	text = string.gsub( text, "^%+%s*(%d)", "plus %1" );
	text = string.gsub( text, "^[%-\226\128\147\226\128\148]%s*(%d)", "minus %1" );	-- hyphen, en dash, em dash
	return text;
end

-- "Strength 20 against 17" (defenderTotal nil or <= 0: the target cannot defend, only our strength is told).
-- prefix: "Strength", "Ranged strength", "Bombard strength".
function CombatText_StrengthPhrase( prefix:string, attackerTotal:number, defenderTotal:number )
	if attackerTotal == nil then return nil; end
	attackerTotal = math.max( 0, math.floor( attackerTotal + 0.5 ) );
	if defenderTotal == nil or defenderTotal <= 0 then return prefix .. " " .. attackerTotal; end
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
