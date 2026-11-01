-- Unit details for the screen reader (Shift+I): strength, ranged strength and range, level, experience, promotions, moves, sight,
-- health, charges, great person effect. Wording is pure (UnitDetails_Text(info)); UnitDetails_Gather reads the engine
-- (the same calls as the game's UnitPanel.ReadUnitData and the unit promotion popup); UnitDetails_ForPlot collects the units of a tile.
-- A foreign unit only gets what a sighted player sees when hovering it: owner, level, strengths, health, promotions.
--------------------------------------------------------------

local function _Num( value:number )
	local rounded:number = math.floor( value * 10 + 0.5 ) / 10;
	if rounded == math.floor( rounded ) then return tostring( math.floor( rounded ) ); end
	return tostring( rounded );
end

local function _Plural( n:number, one:string, many:string )
	return _Num( n ) .. " " .. ( n == 1 and one or many );
end

-- info: { name, own, level, xp, xpNext, promotionAvailable, strength, ranged, range, bombard, antiAir, religious, moves, maxMoves, sight,
--         damage, maxDamage, promotions = {names}, buildCharges, spreads, healCharges, actionCharges, passive, embarked, military, formation }
-- Returns one text of sentences, each ending with a period. Zero and missing values are left out.
function UnitDetails_Text( info:table )
	if info == nil then return nil; end
	local sentences:table = {};
	local military:boolean = info.military == true or ( info.strength or 0 ) > 0 or ( info.ranged or 0 ) > 0 or ( info.bombard or 0 ) > 0;

	-- who: name, level, experience (own units only), promotion available
	local head:string = info.name or "Unit";
	if info.embarked then head = head .. ", embarked"; end
	if military and info.level ~= nil and info.level > 0 then
		head = head .. ", level " .. info.level;
		if info.own and info.xp ~= nil and info.xpNext ~= nil and info.xpNext > 0 then
			head = head .. ", " .. info.xp .. " of " .. info.xpNext .. " experience";
		end
	end
	if info.own and info.promotionAvailable then head = head .. ", promotion available"; end
	table.insert( sentences, head .. "." );

	-- strengths
	local strengths:table = {};
	if ( info.strength or 0 ) > 0 then table.insert( strengths, "Strength " .. _Num( info.strength ) .. "." ); end
	local ranged:number = info.ranged or 0;
	local bombard:number = info.bombard or 0;
	if ranged > 0 then
		table.insert( strengths, "Ranged " .. _Num( ranged ) .. ( ( info.range or 0 ) > 0 and ( ", range " .. info.range ) or "" ) .. "." );
	end
	if bombard > 0 then
		table.insert( strengths, "Bombard " .. _Num( bombard ) .. ( ranged <= 0 and ( info.range or 0 ) > 0 and ( ", range " .. info.range ) or "" ) .. "." );
	end
	if ( info.antiAir or 0 ) > 0 then table.insert( strengths, "Anti-air " .. _Num( info.antiAir ) .. "." ); end
	if ( info.religious or 0 ) > 0 then table.insert( strengths, "Religious strength " .. _Num( info.religious ) .. "." ); end
	for _, s in ipairs( strengths ) do table.insert( sentences, s ); end

	-- movement and sight (own units only: a foreign unit's moves are not shown)
	if info.own then
		local move:string = nil;
		if ( info.maxMoves or 0 ) > 0 then move = _Num( info.moves or 0 ) .. " of " .. _Num( info.maxMoves ) .. " moves"; end
		local sight:string = ( info.sight or 0 ) > 0 and ( "sight " .. info.sight ) or nil;
		if move ~= nil and sight ~= nil then
			table.insert( sentences, move .. ", " .. sight .. "." );
		elseif move ~= nil then
			table.insert( sentences, move .. "." );
		elseif sight ~= nil then
			table.insert( sentences, "Sight " .. info.sight .. "." );
		end
	end

	-- health: a fighting unit always, a civilian when hurt
	local maxDamage:number = info.maxDamage or 0;
	if maxDamage > 0 and ( military or ( info.damage or 0 ) > 0 ) then
		table.insert( sentences, "Health " .. ( maxDamage - ( info.damage or 0 ) ) .. " of " .. maxDamage .. "." );
	end

	-- charges
	if ( info.buildCharges or 0 ) > 0 then table.insert( sentences, _Plural( info.buildCharges, "charge", "charges" ) .. " left." ); end
	if ( info.spreads or 0 ) > 0 then table.insert( sentences, "Spreads left " .. info.spreads .. "." ); end
	if ( info.healCharges or 0 ) > 0 then table.insert( sentences, "Heals left " .. info.healCharges .. "." ); end
	if ( info.actionCharges or 0 ) > 0 then table.insert( sentences, _Plural( info.actionCharges, "action charge", "action charges" ) .. " left." ); end
	if info.passive ~= nil and info.passive ~= "" then table.insert( sentences, "Passive effect: " .. info.passive .. "." ); end

	-- promotions held
	if info.promotions ~= nil and #info.promotions > 0 then
		table.insert( sentences, "Promotions: " .. table.concat( info.promotions, ", " ) .. "." );
	end
	return table.concat( sentences, " " );
end

-- Reads the engine: the info table for one unit. Every call is the one the game's UnitPanel uses.
function UnitDetails_Gather( unit:table )
	local localPlayer:number = Game.GetLocalPlayer();
	local own:boolean = unit:GetOwner() == localPlayer;
	local info:table = {
		name = PlotDescription_GetUnitName( unit ), own = own,
		strength = unit:GetCombat(), ranged = unit:GetRangedCombat(), range = unit:GetRange(), bombard = unit:GetBombardCombat(),
		antiAir = unit:GetAntiAirCombat(), religious = unit:GetReligiousStrength(),
		moves = unit:GetMovesRemaining(), maxMoves = unit:GetMaxMoves(),
		damage = unit:GetDamage(), maxDamage = unit:GetMaxDamage(),
		buildCharges = unit:GetBuildCharges(), spreads = unit:GetSpreadCharges(), healCharges = unit:GetReligiousHealCharges(),
		actionCharges = unit:GetActionCharges(),
		embarked = PlotDescription_IsEmbarked( unit ), promotions = {},
	};
	info.military = info.strength > 0 or info.ranged > 0 or info.bombard > 0;
	local row:table = GameInfo.Units[ unit:GetType() ];
	if row ~= nil and row.BaseSightRange ~= nil then info.sight = row.BaseSightRange; end
	local exp:table = unit:GetExperience();
	if exp ~= nil then
		info.level = exp:GetLevel();
		info.xp = exp:GetExperiencePoints();
		info.xpNext = exp:GetExperienceForNextLevel();
		for _, promotion in ipairs( exp:GetPromotions() ) do
			local def:table = GameInfo.UnitPromotions[ promotion ];
			if def ~= nil then table.insert( info.promotions, Locale.Lookup( def.Name ) ); end
		end
	end
	if own and info.military then
		local ok:boolean, can, results = pcall( function() return UnitManager.CanStartCommand( unit, UnitCommandTypes.PROMOTE, true, true ); end );
		info.promotionAvailable = ok and can and results ~= nil and results[ UnitCommandResults.PROMOTIONS ] ~= nil and #results[ UnitCommandResults.PROMOTIONS ] ~= 0;
	end
	local gp = unit:GetGreatPerson();
	if gp ~= nil and gp.HasPassiveEffect ~= nil and gp:HasPassiveEffect() then
		local okName:boolean, passive = pcall( function() return gp:GetPassiveEffectText(); end );
		if okName and passive ~= nil then info.passive = ( string.gsub( CleanTextForSpeech( Locale.Lookup( passive ) ), "%.[ \t\r\n\v\f]*$", "" ) ); end
		local okCharges:boolean, charges = pcall( function() return gp:GetActionCharges(); end );
		if okCharges and charges ~= nil and charges > 0 then info.actionCharges = charges; end
	end
	return info;
end

-- Pure ordering: fighting units first, then the rest, each group in the engine's order.
function UnitDetails_Order( infos:table )
	local first:table, rest:table = {}, {};
	for _, info in ipairs( infos ) do
		if info.military then table.insert( first, info ); else table.insert( rest, info ); end
	end
	for _, info in ipairs( rest ) do table.insert( first, info ); end
	return first;
end

-- The text for the plot under the map cursor: every visible unit there (military first); none: the selected unit
-- (selected: UI.GetHeadSelectedUnit() or nil); none: "No unit here".
function UnitDetails_ForPlot( plot:table, selected:table )
	local infos:table = {};
	if plot ~= nil and PlotDescription_GetVisibility( plot ) == "visible" then
		for _, unit in ipairs( Units.GetUnitsInPlot( plot ) ) do
			if PlotDescription_IsUnitVisible( unit ) then table.insert( infos, UnitDetails_Gather( unit ) ); end
		end
	end
	if #infos == 0 and selected ~= nil then table.insert( infos, UnitDetails_Gather( selected ) ); end
	if #infos == 0 then return "No unit here"; end
	local texts:table = {};
	for _, info in ipairs( UnitDetails_Order( infos ) ) do table.insert( texts, UnitDetails_Text( info ) ); end
	return table.concat( texts, " " );
end

-- Strength of a foreign unit for the tile text: "strength 15" / "strength 15, ranged 25" (nil when it has none).
function UnitDetails_ShortStrength( strength:number, ranged:number, bombard:number )
	local parts:table = {};
	if ( strength or 0 ) > 0 then table.insert( parts, "strength " .. _Num( strength ) ); end
	if ( ranged or 0 ) > 0 then table.insert( parts, "ranged " .. _Num( ranged ) ); end
	if ( bombard or 0 ) > 0 then table.insert( parts, "bombard " .. _Num( bombard ) ); end
	if #parts == 0 then return nil; end
	return table.concat( parts, ", " );
end

-- The defence of a city for the tile text of a foreign city or your own: "strength 28, walls 100 of 100, health 200 of 200".
-- walls: max outer defence (0: none). Missing values are left out.
function UnitDetails_CityDefenseText( strength:number, wallDamage:number, wallMax:number, damage:number, maxDamage:number )
	local parts:table = {};
	if ( strength or 0 ) > 0 then table.insert( parts, "strength " .. _Num( strength ) ); end
	if ( wallMax or 0 ) > 0 then table.insert( parts, "walls " .. ( wallMax - ( wallDamage or 0 ) ) .. " of " .. wallMax ); end
	if ( maxDamage or 0 ) > 0 then table.insert( parts, "health " .. ( maxDamage - ( damage or 0 ) ) .. " of " .. maxDamage ); end
	if #parts == 0 then return nil; end
	return table.concat( parts, ", " );
end
