-- ===========================================================================
--	HubTargets: target modes (move to, attacks): entering, confirming, cancelling.
--	Part of the InGameAccess hub (see docs/ingame-plan.md, Architecture): included by
--	UI/Additions/InGameAccess.lua. State and functions other hub modules use are fields of HubTargets.
-- ===========================================================================
HubTargets = {};
include( "CombatText" );

local m_attackIntent		:boolean = false;	-- the MOVE_TO mode was entered with the Attack key: only enemies are valid targets

--	TARGET MODES: interface modes in which the game wants a plot (move to, attacks ...)
-- ===========================================================================
local m_targetModes:table = {};		-- InterfaceModeTypes value -> spoken name
do
	local names:table = {
		MOVE_TO = "Move to", RANGE_ATTACK = "Ranged attack", AIR_ATTACK = "Air attack", CITY_RANGE_ATTACK = "City ranged attack",
		DISTRICT_RANGE_ATTACK = "District ranged attack", WMD_STRIKE = "Nuclear strike", ICBM_STRIKE = "Missile strike",
		COASTAL_RAID = "Coastal raid", DEPLOY = "Deploy", REBASE = "Rebase", AIRLIFT = "Airlift", FORM_CORPS = "Form corps",
		FORM_ARMY = "Form army", TELEPORT_TO_CITY = "Transfer to city",
		NAVAL_GOLD_RAID = "Naval raid", SACRIFICE_SELECTION = "Sacrifice", KILL_WEAKER_UNIT = "Kill weaker unit",
		TRANSFORM_UNIT = "Transform unit", RESTORE_UNIT_MOVES = "Restore moves", PRIORITY_TARGET = "Priority target",
	};
	for name, label in pairs( names ) do
		local mode = InterfaceModeTypes[name];
		if mode ~= nil then m_targetModes[mode] = label; end
	end
end

-- Not target modes although the game wants a choice in them: the trade chooser panels (Choosers/TradeRouteChooser.lua,
-- TradeOriginChooser.lua) own these two modes with their own keyboard lists, speech, Enter and Escape. The hub stays
-- silent and lets every key through (as in the production panel); it only closes its unit menu when one starts.
local m_chooserModes:table = {};
for _, name in ipairs( { "MAKE_TRADE_ROUTE", "SPY_TRAVEL_TO_CITY", "SPY_CHOOSE_MISSION" } ) do
	if InterfaceModeTypes[name] ~= nil then m_chooserModes[ InterfaceModeTypes[name] ] = true; end
end

-- TELEPORT_TO_CITY ("Transfer to Another City"): the trade origin chooser owns the mode for traders only (it opens when the unit
-- has MakeTradeRoute); for great persons nobody does, so the hub does (a list of cities, see OpenTransfer).
local function IsTeleportMode( mode:number )
	return mode ~= nil and InterfaceModeTypes.TELEPORT_TO_CITY ~= nil and mode == InterfaceModeTypes.TELEPORT_TO_CITY;
end

local function IsTraderUnit( unit:table )
	if unit == nil then return true; end		-- nothing selected: leave the mode to the panels
	local row:table = GameInfo.Units[ unit:GetUnitType() ];
	return row ~= nil and row.MakeTradeRoute == true;
end

local function IsChooserMode( mode:number )
	if mode == nil then return false; end
	if IsTeleportMode( mode ) then return IsTraderUnit( UI.GetHeadSelectedUnit() ); end
	return m_chooserModes[mode] == true;
end

-- The spoken name of a hub target mode (nil: not one; the trader's transfer belongs to the chooser panel).
local function TargetLabel( mode:number )
	local label:string = m_targetModes[mode];
	if label ~= nil and IsTeleportMode( mode ) and IsTraderUnit( UI.GetHeadSelectedUnit() ) then return nil; end
	return label;
end

-- A mode in which the unit attacks (ranged, air, strikes, or a move with the Attack key), not a plain move or deploy.
function HubTargets.IsAttackMode( mode:number )
	if mode == nil then return false; end
	if mode == InterfaceModeTypes.MOVE_TO then return m_attackIntent; end
	for _, key in ipairs( { "RANGE_ATTACK", "AIR_ATTACK", "PRIORITY_TARGET", "WMD_STRIKE", "ICBM_STRIKE" } ) do
		if InterfaceModeTypes[key] ~= nil and InterfaceModeTypes[key] == mode then return true; end
	end
	return false;
end

function HubTargets.GetTargetMode()
	local mode:number = UI.GetInterfaceMode();
	local label:string = TargetLabel( mode );
	if label ~= nil then return mode, label; end
	return nil, nil;
end

-- A list mode cannot be opened in the middle of a target mode. allowTarget: the places list (J) may, it only moves the
-- target cursor (to bring a unit home, say).
function HubTargets.CanOpenMode( allowTarget:boolean )
	if not HubCore.IsLocalPlayerActive() then return false; end
	if not allowTarget and HubTargets.GetTargetMode() ~= nil then
		OutputMessageToScreenReader( "Choose a tile, or " .. ( SRKey( "Escape" ) ) .. " to cancel first" );
		return false;
	end
	if HubCore.IsModeOpen( "placement" ) then
		OutputMessageToScreenReader( "Place it, or " .. SRKey( "Escape" ) .. " to cancel first" );
		return false;
	end
	return true;
end

-- Modes in which a city or district (not a unit) acts.
local function IsCityMode( mode:number )
	return mode == InterfaceModeTypes.CITY_RANGE_ATTACK or mode == InterfaceModeTypes.DISTRICT_RANGE_ATTACK;
end
HubTargets.IsCityMode = IsCityMode;

-- The unit or city that chose a target mode is gone (died, deselected, turn ended): leave the mode, or Enter and
-- Escape would be swallowed by a mode that has nothing to act on.
function HubTargets.ResetStaleMode()
	if HubTargets.GetTargetMode() ~= nil and UI.GetHeadSelectedUnit() == nil and UI.GetHeadSelectedCity() == nil then
		UI.SetInterfaceMode( InterfaceModeTypes.SELECTION );
	end
end

-- Plot indexes the unit may attack with this operation (ranged / air attack).
local function GetAttackTargets( unit:table, operation:number )
	local set:table = {};
	local results:table = UnitManager.GetOperationTargets( unit, operation );
	if results == nil then return set; end
	local plots:table = results[UnitOperationResults.PLOTS];
	local modifiers:table = results[UnitOperationResults.MODIFIERS];
	if plots == nil or modifiers == nil then return set; end
	for i, plotId in ipairs( plots ) do
		if modifiers[i] == UnitOperationResults.MODIFIER_IS_TARGET then set[ plotId ] = true; end
	end
	return set;
end

-- What the game's combat preview would say for this attack (mirrors UnitPanel ShowCombatAssessment): damage both
-- ways and whether someone dies; walls and city health are told apart, a city never "dies" (it can be captured).
local function IsCityOrDistrictPlot( plot:table )
	if plot:IsCity() then return true; end
	local districtType:number = plot:GetDistrictType();
	if districtType ~= nil and districtType >= 0 then
		local row:table = GameInfo.Districts[ districtType ];
		return row ~= nil and not row.InternalOnly;
	end
	return false;
end

-- The game (UnitPanel OnShowCombat / GetDistrictFromCity) previews a city attack with the city's DISTRICT object:
-- SimulateAttackVersus( district:GetComponentID(), defenderUnit:GetComponentID() ); a city is not a valid attacker
-- for SimulateAttackInto (it returns nil), a district component is.
local function CityDistrict( city:table )
	if city == nil then return nil; end
	if city.GetDistrictID == nil then return city; end		-- already a district
	local player:table = Players[ city:GetOwner() ];
	if player == nil then return nil; end
	return player:GetDistricts():FindID( city:GetDistrictID() );
end

local function SimulateAttack( unit:table, plot:table, combatType )
	local ok:boolean, results;
	if combatType == CombatTypes.RANGED and unit.GetDistrictID ~= nil then
		-- a city: use its district, versus the unit on the plot when there is one
		local district:table = CityDistrict( unit );
		if district == nil then return nil; end
		local defender:table = CombatText_PickDefender( Units.GetUnitsInPlot( plot ), function( other ) return other:GetOwner() ~= Game.GetLocalPlayer(); end );
		if defender ~= nil then
			ok, results = pcall( CombatManager.SimulateAttackVersus, district:GetComponentID(), defender:GetComponentID() );
		else
			ok, results = pcall( CombatManager.SimulateAttackInto, district:GetComponentID(), combatType, plot:GetX(), plot:GetY() );
		end
	else
		local source:table = unit;
		if unit.GetDistrictID == nil and unit.GetComponentID == nil then return nil; end
		ok, results = pcall( CombatManager.SimulateAttackInto, source:GetComponentID(), combatType, plot:GetX(), plot:GetY() );
	end
	if not ok or results == nil then return nil; end
	return results;
end

-- "Strength 20 against 17" / "Ranged strength 25 against 17": base plus modifier total of each side, as the game's preview shows.
local function StrengthPhrase( results:table, combatType )
	local attacker:table = results[CombatResultParameters.ATTACKER];
	local defender:table = results[CombatResultParameters.DEFENDER];
	if attacker == nil or defender == nil then return nil; end
	local prefix:string = "Strength";
	if combatType ~= nil and combatType == CombatTypes.RANGED then prefix = "Ranged strength";
	elseif combatType ~= nil and CombatTypes.BOMBARD ~= nil and combatType == CombatTypes.BOMBARD then prefix = "Bombard strength"; end
	local mine:number = CombatText_Total( attacker[CombatResultParameters.COMBAT_STRENGTH], attacker[CombatResultParameters.STRENGTH_MODIFIER] );
	local theirs:number = CombatText_Total( defender[CombatResultParameters.COMBAT_STRENGTH], defender[CombatResultParameters.STRENGTH_MODIFIER] );
	return CombatText_StrengthPhrase( prefix, mine, theirs );
end

-- The modifier lines of one side, in the order of UnitPanel GetCombatModifierList (base strength line left out), cleaned for speech.
local m_modifierFields:table = { "PREVIEW_TEXT_INTERCEPTOR", "PREVIEW_TEXT_ANTI_AIR", "PREVIEW_TEXT_HEALTH", "PREVIEW_TEXT_TERRAIN",
	"PREVIEW_TEXT_OPPONENT", "PREVIEW_TEXT_MODIFIER", "PREVIEW_TEXT_ASSIST", "PREVIEW_TEXT_PROMOTION", "PREVIEW_TEXT_DEFENSES", "PREVIEW_TEXT_RESOURCES" };
local function ModifierLines( side:table )
	local lines:table = {};
	if side == nil then return lines; end
	for _, field in ipairs( m_modifierFields ) do
		local key = CombatResultParameters[ field ];
		local list = ( key ~= nil ) and side[ key ] or nil;
		if type( list ) == "table" then
			for _, item in ipairs( list ) do
				local text:string = CleanTextForSpeech( Locale.Lookup( item ) );
				if text ~= "" then table.insert( lines, text ); end
			end
		end
	end
	return lines;
end

local function CombatPreviewText( unit:table, plot:table, combatType )
	local results:table = SimulateAttack( unit, plot, combatType );
	if results == nil then return nil; end
	local attacker:table = results[CombatResultParameters.ATTACKER];
	local defender:table = results[CombatResultParameters.DEFENDER];
	if attacker == nil or defender == nil then return nil; end
	local parts:table = {};
	local dealt:number = defender[CombatResultParameters.DAMAGE_TO] or 0;
	local defenderMax:number = defender[CombatResultParameters.MAX_HIT_POINTS] or 0;
	local defenderFinal:number = defender[CombatResultParameters.FINAL_DAMAGE_TO] or 0;
	local wallsMax:number = defender[CombatResultParameters.MAX_DEFENSE_HIT_POINTS] or 0;
	local wallsDamage:number = defender[CombatResultParameters.DEFENSE_DAMAGE_TO] or 0;
	local wallsFinal:number = defender[CombatResultParameters.FINAL_DEFENSE_DAMAGE_TO] or 0;
	if results[CombatResultParameters.LOCATION_PILLAGED] then
		table.insert( parts, "would pillage" );
	elseif defenderMax == 0 then
		return "no combat";
	elseif wallsMax > 0 then
		-- a city or district with walls: part of the damage goes to the walls
		if wallsDamage > 0 then
			table.insert( parts, "deals about " .. wallsDamage .. " damage to the walls, about " .. math.max( 0, wallsMax - wallsFinal ) .. " of " .. wallsMax .. " left" );
		end
		if dealt > wallsDamage or wallsDamage == 0 then
			table.insert( parts, "deals about " .. dealt .. " damage to the city, about " .. math.max( 0, defenderMax - defenderFinal ) .. " of " .. defenderMax .. " health left" );
		end
	elseif defenderFinal >= defenderMax then
		if IsCityOrDistrictPlot( plot ) then
			table.insert( parts, "likely takes health to 0" );
		else
			table.insert( parts, "likely kills the target" );
		end
	else
		table.insert( parts, "deals about " .. dealt .. " damage, target left with about " .. ( defenderMax - defenderFinal ) .. " of " .. defenderMax );
	end
	local taken:number = attacker[CombatResultParameters.DAMAGE_TO] or 0;
	local attackerMax:number = attacker[CombatResultParameters.MAX_HIT_POINTS] or 0;
	local attackerFinal:number = attacker[CombatResultParameters.FINAL_DAMAGE_TO] or 0;
	if attackerMax > 0 and attackerFinal >= attackerMax then
		table.insert( parts, "you would likely die" );
	elseif taken > 0 then
		table.insert( parts, "you take about " .. taken );
	else
		table.insert( parts, "no damage to you" );
	end
	local text:string = table.concat( parts, ", " );
	local strength:string = StrengthPhrase( results, combatType );
	if strength ~= nil then text = strength .. ": " .. text; end
	return text;
end

-- The combat type TargetInfo uses for a unit's attack in this mode (nil: melee / air).
local function AttackCombatType( mode:number, unit:table )
	if mode ~= InterfaceModeTypes.RANGE_ATTACK then return nil; end
	if unit:GetBombardCombat() > unit:GetRangedCombat() then return CombatTypes.BOMBARD; end
	return CombatTypes.RANGED;
end

-- The attacker of the combat simulation: the selected unit, or the city / district of the city attack modes.
local function CombatAttacker( mode:number )
	if mode == InterfaceModeTypes.CITY_RANGE_ATTACK then return UI.GetHeadSelectedCity(), CombatTypes.RANGED; end
	if mode == InterfaceModeTypes.DISTRICT_RANGE_ATTACK then
		local district:table = UI.GetHeadSelectedDistrict();
		if district == nil then district = UI.GetHeadSelectedCity(); end
		return district, CombatTypes.RANGED;
	end
	local unit:table = UI.GetHeadSelectedUnit();
	if unit == nil then return nil, nil; end
	return unit, AttackCombatType( mode, unit );
end

-- Modes in which Space reads the combat modifiers (the others keep their old behaviour).
function HubTargets.IsModifierMode( mode:number )
	if mode == nil then return false; end
	if mode == InterfaceModeTypes.MOVE_TO then return m_attackIntent; end
	return mode == InterfaceModeTypes.RANGE_ATTACK or mode == InterfaceModeTypes.AIR_ATTACK or IsCityMode( mode );
end

-- Space in an attack target mode: the modifier lines of both sides for the cursor tile.
function HubTargets.SpeakCombatModifiers()
	local mode:number = HubTargets.GetTargetMode();
	if not HubTargets.IsModifierMode( mode ) then return; end
	local x:number, y:number = HubCursor.GetCursor();
	local plot:table = Map.GetPlot( x, y );
	if plot == nil or not HubTargets.IsAttackTarget( plot ) then
		OutputMessageToScreenReader( "No target here to compare" );
		return;
	end
	local source:table, combatType = CombatAttacker( mode );
	local results:table = ( source ~= nil ) and SimulateAttack( source, plot, combatType ) or nil;
	local attacker:table = results ~= nil and results[CombatResultParameters.ATTACKER] or nil;
	local defender:table = results ~= nil and results[CombatResultParameters.DEFENDER] or nil;
	if attacker == nil or defender == nil then
		OutputMessageToScreenReader( IsCityMode( mode ) and "No modifier preview for a city attack" or "No combat preview for this tile" );
		return;
	end
	OutputMessageToScreenReader( CombatText_Modifiers( ModifierLines( attacker ), ModifierLines( defender ) ) );
end

-- "Attacking Barbarian Horseman": the name of what stands on the plot (a visible foreign unit, else the city).
local function TargetName( plot:table )
	if not HubCore.IsPlotVisibleToLocal( plot ) then return nil; end
	local target:table = CombatText_PickDefender( Units.GetUnitsInPlot( plot ), function( other )
		return other:GetOwner() ~= Game.GetLocalPlayer() and HubCore.IsForeignUnitVisible( other ); end );
	if target ~= nil then return PlotDescription_GetUnitName( target ); end
	if plot:IsCity() then
		local city:table = Cities.GetCityInPlot( plot:GetX(), plot:GetY() );
		if city ~= nil then return Locale.Lookup( city:GetName() ); end
	end
	return nil;
end

local function AttackingText( plot:table, fallback:string )
	local name:string = TargetName( plot );
	if name == nil then return fallback; end
	return "Attacking " .. name;
end

-- Players the move or attack of this unit onto the plot would declare war on (nil: none).
function HubTargets.WarTargets( unit:table, plot:table )
	if unit == nil or plot == nil or not HubCore.IsPlotVisibleToLocal( plot ) then return nil; end
	local ok:boolean, results = pcall( CombatManager.IsAttackChangeWarState, unit:GetComponentID(), plot:GetX(), plot:GetY() );
	if ok and results ~= nil and #results > 0 then return results; end
	return nil;
end

local function WarTargetNames( targets:table )
	local names:table = {};
	for _, playerID in ipairs( targets ) do table.insert( names, PlotDescription_GetCivName( playerID ) ); end
	return table.concat( names, " and " );
end

-- A visible unit or city of someone we are at war with (or barbarians) on the plot.
local function EnemyVisibleAt( plot:table )
	if not HubCore.IsPlotVisibleToLocal( plot ) then return false; end
	for _, other in ipairs( Units.GetUnitsInPlot( plot ) ) do
		if HubCore.IsForeignUnitVisible( other ) and HubCore.IsHostile( other:GetOwner() ) then return true; end
	end
	if plot:IsCity() then
		local city:table = Cities.GetCityInPlot( plot:GetX(), plot:GetY() );
		if city ~= nil and HubCore.IsHostile( city:GetOwner() ) then return true; end
	end
	return false;
end

HubTargets.EnemyVisibleAt = EnemyVisibleAt;

-- A hostile city, or a hostile unit that fights back, on the plot (a lone civilian is captured: no combat result).
function HubTargets.HoldsEnemyFighter( plot:table )
	if plot:IsCity() then return true; end
	for _, other in ipairs( Units.GetUnitsInPlot( plot ) ) do
		if HubCore.IsForeignUnitVisible( other ) and HubCore.IsHostile( other:GetOwner() )
				and ( other:GetCombat() > 0 or other:GetRangedCombat() > 0 ) then return true; end
	end
	return false;
end

-- City and district ranged attacks (no unit): the plot indexes the selected city may hit.
local function GetCityAttackTargets( city:table )
	local set:table = {};
	local ok:boolean, results = pcall( function()
		local parameters:table = {};
		parameters[CityCommandTypes.PARAM_RANGED_ATTACK] = UI.GetInterfaceModeParameter( CityCommandTypes.PARAM_RANGED_ATTACK );
		return CityManager.GetCommandTargets( city, CityCommandTypes.RANGE_ATTACK, parameters );
	end );
	if not ok or results == nil then return nil; end
	local plots:table = results[CityCommandResults.PLOTS];
	local modifiers:table = results[CityCommandResults.MODIFIERS];
	if plots == nil or modifiers == nil then return nil; end
	for i, plotId in ipairs( plots ) do
		if modifiers[i] == CityCommandResults.MODIFIER_IS_TARGET then set[ plotId ] = true; end
	end
	return set;
end

-- In a target mode: can the selected unit / city attack (or would its move attack) what is on this plot?
function HubTargets.IsAttackTarget( plot:table )
	local mode:number = HubTargets.GetTargetMode();
	if mode == nil or plot == nil then return false; end
	local ok:boolean, text = pcall( HubTargets.TargetInfo, mode, plot, UI.GetHeadSelectedUnit() );
	if not ok or text == nil or string.find( text, "would declare war", 1, true ) ~= nil then return false; end	-- a peaceful civ is no target
	return string.find( text, "valid target", 1, true ) ~= nil or string.find( text, "attack", 1, true ) == 1;
end

-- Plots a melee attack (the Attack key on a unit without ranged attack) may be aimed at: no list exists in the engine
-- (GetOperationTargets(MOVE_TO) is empty), so the plots within 10 tiles with a visible hostile unit, city or district are
-- candidates, kept when the move info says "attack ..." (a multi-turn approach counts; "would declare war" does not).
local MELEE_SCAN_DISTANCE:number = 10;
function HubTargets.MeleeAttackCandidates( unit:table )
	local set:table = {};
	local localPlayer:number = Game.GetLocalPlayer();
	local function Consider( x:number, y:number )
		if Map.GetPlotDistance( unit:GetX(), unit:GetY(), x, y ) > MELEE_SCAN_DISTANCE then return; end
		local plot:table = Map.GetPlot( x, y );
		if plot == nil or set[ plot:GetIndex() ] ~= nil or not HubCore.IsPlotVisibleToLocal( plot ) then return; end
		set[ plot:GetIndex() ] = HubTargets.IsAttackTarget( plot );
	end
	for playerID = 0, 63 do
		local player:table = Players[ playerID ];
		if playerID ~= localPlayer and player ~= nil and player:IsAlive() and HubCore.IsHostile( playerID ) then
			for _, other in player:GetUnits():Members() do
				if PlotDescription_IsUnitVisible( other ) then Consider( other:GetX(), other:GetY() ); end
			end
			for _, city in player:GetCities():Members() do Consider( city:GetX(), city:GetY() ); end
			pcall( function()
				for _, district in player:GetDistricts():Members() do Consider( district:GetX(), district:GetY() ); end
			end );
		end
	end
	local result:table = {};
	for plotIndex, ok in pairs( set ) do
		if ok then result[ plotIndex ] = true; end
	end
	return result;
end

-- Set of plot indexes the current attack mode can hit this turn (X walks only these). nil: the mode has no such list
-- (nuclear strikes and missiles target any plot): X keeps scanning for units. unit: the selected unit (nil for the city modes).
function HubTargets.AttackTargetPlots( mode:number, unit:table )
	if mode == nil then return nil; end
	if IsCityMode( mode ) then
		local city:table = UI.GetHeadSelectedCity();
		return ( city ~= nil ) and GetCityAttackTargets( city ) or nil;
	end
	if unit == nil then return nil; end
	if mode == InterfaceModeTypes.RANGE_ATTACK then return GetAttackTargets( unit, UnitOperationTypes.RANGE_ATTACK ); end
	if mode == InterfaceModeTypes.AIR_ATTACK then return GetAttackTargets( unit, UnitOperationTypes.AIR_ATTACK ); end
	if mode == InterfaceModeTypes.MOVE_TO and m_attackIntent then return HubTargets.MeleeAttackCandidates( unit ); end
	return nil;
end

-- Modes whose valid targets the game lists (WorldInput's OnInterfaceModeChange_* highlight them): the plots of
-- GetOperationTargets / GetCommandTargets, or for Form Corps / Form Army the plots of the partner units.
local m_listedOperations:table = { COASTAL_RAID = "COASTAL_RAID", DEPLOY = "DEPLOY", REBASE = "REBASE", TELEPORT_TO_CITY = "TELEPORT_TO_CITY" };
local m_listedCommands:table = { AIRLIFT = "AIRLIFT", KILL_WEAKER_UNIT = "KILL_WEAKER_UNIT", TRANSFORM_UNIT = "TRANSFORM_UNIT",
	RESTORE_UNIT_MOVES = "RESTORE_UNIT_MOVES", NAVAL_GOLD_RAID = "NAVAL_GOLD_RAID" };

-- Set of plot indexes the selected unit may choose in this mode (nil: the mode does not list its targets).
function HubTargets.ModeTargetPlots( mode:number, unit:table )
	if unit == nil then return nil; end
	local set:table = {};
	local ok:boolean = pcall( function()
		if mode == InterfaceModeTypes.FORM_CORPS or mode == InterfaceModeTypes.FORM_ARMY then
			local command = ( mode == InterfaceModeTypes.FORM_CORPS ) and UnitCommandTypes.FORM_CORPS or UnitCommandTypes.FORM_ARMY;
			local results:table = UnitManager.GetCommandTargets( unit, command );
			local units:table = results ~= nil and results[UnitCommandResults.UNITS] or nil;
			for _, componentID in ipairs( units or {} ) do
				local partner:table = Players[ unit:GetOwner() ]:GetUnits():FindID( componentID.id );
				if partner ~= nil then set[ Map.GetPlotIndex( partner:GetX(), partner:GetY() ) ] = true; end
			end
			return;
		end
		local results:table = nil;
		local resultKey = nil;
		for key, mapped in pairs( m_listedOperations ) do
			if InterfaceModeTypes[ key ] == mode and UnitOperationTypes[ mapped ] ~= nil then
				results = UnitManager.GetOperationTargets( unit, UnitOperationTypes[ mapped ] );
				resultKey = UnitOperationResults.PLOTS;
			end
		end
		for key, mapped in pairs( m_listedCommands ) do
			if InterfaceModeTypes[ key ] == mode and UnitCommandTypes[ mapped ] ~= nil then
				results = UnitManager.GetCommandTargets( unit, UnitCommandTypes[ mapped ] );
				resultKey = UnitCommandResults.PLOTS;
			end
		end
		if mode == InterfaceModeTypes.SACRIFICE_SELECTION then
			results = UnitManager.GetOperationTargets( unit, "UNITOPERATION_SOOTHSAYER_SACRIFICE" );
			resultKey = UnitOperationResults.PLOTS;
		end
		if results == nil or resultKey == nil then set = nil; return; end
		local plotList:table = results[resultKey];
		-- WorldInput reads CityCommandResults.PLOTS for the kill/transform/restore/raid commands, UnitCommandResults.PLOTS for airlift
		if plotList == nil and resultKey == UnitCommandResults.PLOTS then plotList = results[CityCommandResults.PLOTS]; end
		for _, plotId in ipairs( plotList or {} ) do set[ plotId ] = true; end
	end );
	if not ok then return nil; end
	return set;
end

-- Why a move order finds no path to a plot of ours: the engine allows one unit of each formation class per tile, and an
-- escort formation counts as both its classes (verified: a Spearman + Settler formation, and a lone Builder, find no path
-- to a city holding a Great General: civilian class; a Heavy Chariot does). "" when the cause is not this (stays "Unreachable").
function HubTargets.UnreachableReason( unit:table, plot:table )
	if unit == nil or plot == nil then return ""; end
	local text:string = "";
	pcall( function()
		local classes:table, own:table = {}, { [ unit:GetID() ] = true };
		local function ClassOf( u:table )
			local row:table = GameInfo.Units[ u:GetUnitType() ];
			return ( row ~= nil ) and row.FormationClass or nil;
		end
		classes[ ClassOf( unit ) or "" ] = true;
		if unit:GetFormationUnitCount() > 1 then
			for _, other in ipairs( Units.GetUnitsInPlot( Map.GetPlot( unit:GetX(), unit:GetY() ) ) ) do
				if other:GetOwner() == unit:GetOwner() and other:GetFormationUnitCount() > 1 then
					own[ other:GetID() ] = true;
					classes[ ClassOf( other ) or "" ] = true;
				end
			end
		end
		for _, other in ipairs( Units.GetUnitsInPlot( plot ) ) do
			local class:string = ClassOf( other );
			if other:GetOwner() == unit:GetOwner() and not own[ other:GetID() ] and class ~= nil and classes[ class ] and other:GetFormationUnitCount() <= 1 then
				-- Only when this really is the blocker: the plot is one the unit's domain can enter and a neighbour of it is reachable
				-- (else it is water for a land unit, an island, ZOC ...: plain "Unreachable").
				local unitRow:table = GameInfo.Units[ unit:GetUnitType() ];
				local domain:string = ( unitRow ~= nil ) and unitRow.Domain or "";
				if ( domain == "DOMAIN_LAND" and plot:IsWater() ) or ( domain == "DOMAIN_SEA" and not plot:IsWater() ) or ( domain ~= "DOMAIN_LAND" and domain ~= "DOMAIN_SEA" ) then return; end
				local neighbourReached:boolean = false;
				for dir = 0, 5 do
					local n:table = Map.GetAdjacentPlot( plot:GetX(), plot:GetY(), dir );
					if n ~= nil then
						if n:GetX() == unit:GetX() and n:GetY() == unit:GetY() then neighbourReached = true; break; end
						local path:table = UnitManager.GetMoveToPathEx( unit, n:GetIndex() );
						if path ~= nil and path.plots ~= nil and #path.plots >= 2 then neighbourReached = true; break; end
					end
				end
				if not neighbourReached then return; end
				local kind:string = ( class == "FORMATION_CLASS_CIVILIAN" ) and "civilian" or ( class == "FORMATION_CLASS_LAND_COMBAT" and "land military unit" or "unit of that kind" );
				text = Locale.Lookup( other:GetName() ) .. " is already there, only one " .. kind .. " fits on a tile";
				return;
			end
		end
	end );
	return text;
end

-- Mode specific words for the cursor plot: path length for a move, valid target and odds for an attack.
function HubTargets.TargetInfo( mode:number, plot:table, unit:table )
	if unit == nil then
		if mode == InterfaceModeTypes.CITY_RANGE_ATTACK or mode == InterfaceModeTypes.DISTRICT_RANGE_ATTACK then
			local city:table = UI.GetHeadSelectedCity();
			local targets:table = ( city ~= nil ) and GetCityAttackTargets( city ) or nil;
			if targets == nil then return nil; end
			if targets[ plot:GetIndex() ] then
				local source:table, combatType = CombatAttacker( mode );
				local preview:string = ( source ~= nil ) and CombatPreviewText( source, plot, combatType ) or nil;
				return "valid target" .. ( preview ~= nil and ( ", " .. preview ) or "" );
			end
			return "no target";
		end
		return nil;
	end
	local listed:table = HubTargets.ModeTargetPlots( mode, unit );
	if listed ~= nil then
		if listed[ plot:GetIndex() ] then
			if mode == InterfaceModeTypes.FORM_CORPS or mode == InterfaceModeTypes.FORM_ARMY then return "valid target, unit to join"; end
			return "valid target";
		end
		return "no target";
	end
	if mode == InterfaceModeTypes.MOVE_TO then
		if unit:GetX() == plot:GetX() and unit:GetY() == plot:GetY() then return "here"; end
		local war:table = HubTargets.WarTargets( unit, plot );
		local path:table = UnitManager.GetMoveToPathEx( unit, plot:GetIndex() );
		local reachable:boolean = path ~= nil and path.plots ~= nil and #path.plots >= 2;
		local enemy:boolean = EnemyVisibleAt( plot );
		if not reachable and war == nil then
			if m_attackIntent and enemy then return "enemy, cannot reach"; end
			local why:string = HubTargets.UnreachableReason( unit, plot );
			return "unreachable" .. ( why ~= "" and ( ", " .. why ) or "" );
		end
		local text:string = "";
		local turns:number = 1;
		if reachable then
			turns = path.turns[ #path.turns ] or 1;
			text = HubCore.Plural( turns, "turn", "turns" );
		end
		if enemy or war ~= nil then
			text = ( text ~= "" ) and ( "attack, " .. text ) or "attack";
			if turns <= 1 then
				local preview:string = CombatPreviewText( unit, plot, nil );
				if preview ~= nil then text = text .. ", " .. preview; end
			elseif enemy then
				-- out of reach: the strengths do not depend on the distance, so the simulation as if adjacent gives them
				-- (nothing is said when the engine returns no preview for a far target)
				local results:table = SimulateAttack( unit, plot, nil );
				local strength:string = ( results ~= nil ) and StrengthPhrase( results, nil ) or nil;
				if strength ~= nil then text = text .. ", " .. strength .. " when you reach it"; end
			end
		elseif m_attackIntent then
			return "no enemy";
		end
		if war ~= nil then text = "would declare war on " .. WarTargetNames( war ) .. ", " .. text; end
		return text;
	elseif mode == InterfaceModeTypes.RANGE_ATTACK or mode == InterfaceModeTypes.AIR_ATTACK then
		local operation:number = ( mode == InterfaceModeTypes.RANGE_ATTACK ) and UnitOperationTypes.RANGE_ATTACK or UnitOperationTypes.AIR_ATTACK;
		local war:table = HubTargets.WarTargets( unit, plot );
		if not GetAttackTargets( unit, operation )[ plot:GetIndex() ] and war == nil then return "no target"; end
		local combatType = nil;
		if mode == InterfaceModeTypes.RANGE_ATTACK then
			combatType = CombatTypes.RANGED;
			if unit:GetBombardCombat() > unit:GetRangedCombat() then combatType = CombatTypes.BOMBARD; end
		end
		local preview:string = CombatPreviewText( unit, plot, combatType );
		local text:string = "valid target" .. ( preview ~= nil and ( ", " .. preview ) or "" );
		if war ~= nil then text = "would declare war on " .. WarTargetNames( war ) .. ", " .. text; end
		return text;
	end
	return nil;
end

-- The capital key (WorldInput sends SRA_CapitalKey outside the plain map mode). In a target mode it only moves the target
-- cursor to the capital and says the usual target info for that plot; Enter confirms as usual. Elsewhere it selects the
-- capital like on the plain map.
function HubTargets.CapitalKey()
	print( "CapitalKey: pressed, mode " .. tostring( UI.GetInterfaceMode() ) );		-- diagnostic: bug-backslash-target-silent (silent in Move To)
	if not HubCore.IsLocalPlayerActive() then print( "CapitalKey: no active local player" ); OutputMessageToScreenReader( "Not your turn" ); return; end
	local capital:table = Players[ Game.GetLocalPlayer() ]:GetCities():GetCapitalCity();
	if capital == nil then print( "CapitalKey: no capital" ); OutputMessageToScreenReader( "No capital" ); return; end
	if HubTargets.GetTargetMode() ~= nil then
		-- always speak: if describing the plot fails or gives nothing, say at least the capital's name
		local capitalName:string = Locale.Lookup( capital:GetName() );
		-- watch the speech: SetCursor must produce a line, else the fallback below does
		local spoken:boolean = false;
		local realOutput = OutputMessageToScreenReader;
		OutputMessageToScreenReader = function( message, nointerrupt ) spoken = true; return realOutput( message, nointerrupt ); end;
		local ok:boolean, err = pcall( HubCursor.SetCursor, capital:GetX(), capital:GetY(), true, true, false, true );
		OutputMessageToScreenReader = realOutput;
		if not ok then print( "CapitalKey: SetCursor failed: " .. tostring( err ) ); end
		if not spoken then
			print( "CapitalKey: nothing was spoken, fallback" );
			local info:string = nil;
			pcall( function()
				local unit:table = UI.GetHeadSelectedUnit();
				info = HubTargets.TargetInfo( HubTargets.GetTargetMode(), Map.GetPlot( capital:GetX(), capital:GetY() ), unit );
			end );
			OutputMessageToScreenReader( "Target: " .. capitalName .. ( info ~= nil and info ~= "" and ( ", " .. info ) or "" ) );
		end
		return;
	end
	-- a placement or chooser mode (trade route ...): selecting the capital would cancel it
	if UI.GetInterfaceMode() ~= InterfaceModeTypes.SELECTION or HubCore.IsModeOpen( "placement" ) then
		print( "CapitalKey: Escape first, mode " .. tostring( UI.GetInterfaceMode() ) );
		OutputMessageToScreenReader( SRKey( "Escape" ) .. " first" );
		return;
	end
	local selected:table = UI.GetHeadSelectedCity();
	if selected ~= nil and selected:GetOwner() == capital:GetOwner() and selected:GetID() == capital:GetID() then
		OutputMessageToScreenReader( "Capital: " .. Locale.Lookup( capital:GetName() ) );
	else
		UI.DeselectAllUnits();
		UI.SelectCity( capital );
	end
end

-- ===========================================================================
--	TARGET MODES: entering, confirming (Enter) and cancelling (Escape)
-- ===========================================================================
-- F8: the Reports screen has no input action of its own; the top panel button toggles it through these events.
function HubTargets.ToggleReports()
	local screen = ContextPtr:LookUpControl( "/InGame/ReportScreen" );
	if screen ~= nil and not screen:IsHidden() then
		LuaEvents.TopPanel_CloseReportsScreen();
	else
		LuaEvents.TopPanel_OpenReportsScreen();
	end
end

HubTargets.lastModeLine = -1;		-- the target mode of the last mode line and when it was spoken
HubTargets.lastModeTime = -100;
HubTargets.attackTime = -100;		-- UI.GetElapsedTime() of the last confirmed attack
HubTargets.warReturn = nil;			-- { mode, intent, cursor, time }: Enter opened the declare-war dialog; Escape there ends the game's mode

-- Enter on a target that needs a war declaration: remember the mode, so that cancelling the dialog goes back to it.
local function RememberWarReturn( mode:number )
	local x:number, y:number = HubCursor.GetCursor();
	HubTargets.warReturn = { mode = mode, intent = m_attackIntent, x = x, y = y, time = UI.GetElapsedTime() };
end

-- The mode ended while a war dialog was pending: once the dialog is gone and the war was not declared, choose the target again.
local function WatchWarReturn( tries:number )
	local record:table = HubTargets.warReturn;
	if record == nil then return; end
	local unit:table = UI.GetHeadSelectedUnit();
	if unit == nil or tries > 40 or HubTargets.GetTargetMode() ~= nil then HubTargets.warReturn = nil; return; end
	local plot:table = Map.GetPlot( record.x, record.y );
	if plot == nil or HubTargets.WarTargets( unit, plot ) == nil then HubTargets.warReturn = nil; return; end		-- war declared (or the target is gone)
	local dialog = nil;
	pcall( function() dialog = ContextPtr:LookUpControl( "/InGame/Diplomacy/DeclareWarPopup" ); end );
	if ( dialog ~= nil and not dialog:IsHidden() ) or ( dialog == nil and tries < 4 ) then
		HubCore.After( 0.5, function() WatchWarReturn( tries + 1 ); end );
		return;
	end
	HubTargets.warReturn = nil;
	if dialog == nil then return; end		-- cannot tell whether the dialog was cancelled: leave the mode alone
	m_attackIntent = record.intent;
	UI.SetInterfaceMode( record.mode );
	HubCursor.SetCursor( record.x, record.y, false );
	OutputMessageToScreenReader( "War not declared. Still choosing a target: " .. SRKey( "Enter" ) .. " to confirm, " .. SRKey( "Escape" ) .. " to cancel" );
end

-- City ranged attack: the cursor starts on the nearest tile the city can hit (Enter on the city itself says "No valid target").
function HubTargets.CursorToNearestCityTarget()
	if not IsCityMode( UI.GetInterfaceMode() ) then return; end
	local city:table = UI.GetHeadSelectedCity();
	if city == nil then return; end
	local targets:table = GetCityAttackTargets( city );
	local bestPlot:table, bestDistance:number = nil, 99;
	if targets ~= nil then
		for plotIndex, _ in pairs( targets ) do
			local plot:table = Map.GetPlotByIndex( plotIndex );
			if plot ~= nil then
				local distance:number = Map.GetPlotDistance( city:GetX(), city:GetY(), plot:GetX(), plot:GetY() );
				if distance < bestDistance then bestPlot, bestDistance = plot, distance; end
			end
		end
	end
	if bestPlot == nil then
		OutputMessageToScreenReader( "No enemy in range. " .. SRKey( "Escape" ) .. " to cancel", true );
		return;
	end
	HubCursor.SetCursor( bestPlot:GetX(), bestPlot:GetY(), true, false );
end

HubTargets.cityAttackTurn = {};		-- "owner:city id" -> game turn of the last city ranged attack we confirmed
HubTargets.districtAttackTurn = {};	-- "owner:district id" -> same for district attacks (not used for the city reason)

local function AttackKey( obj:table ) return tostring( obj:GetOwner() ) .. ":" .. tostring( obj:GetID() ); end

-- A visible unit of a civ we are at war with within the city's ranged attack distance (2).
local function HasEnemyInCityRange( city:table )
	local found:boolean = false;
	pcall( function()
		local me:number = city:GetOwner();
		local diplomacy = Players[me]:GetDiplomacy();
		local visibility = PlayersVisibility[me];
		for dx = -2, 2 do
			for dy = -2, 2 do
				local plot:table = Map.GetPlot( city:GetX() + dx, city:GetY() + dy );
				if plot ~= nil and Map.GetPlotDistance( city:GetX(), city:GetY(), plot:GetX(), plot:GetY() ) <= 2 and visibility:IsVisible( plot:GetIndex() ) then
					for _, unit in ipairs( Units.GetUnitsInPlot( plot ) ) do
						local owner:number = unit:GetOwner();
						if owner ~= me and diplomacy:IsAtWarWith( owner ) then found = true; end
					end
				end
			end
		end
	end );
	return found;
end

-- Why a city cannot make its ranged attack: the engine's own failure reasons first, then damaged walls / district,
-- then "already attacked" (targets in range but refused) or "no enemy in range".
function HubTargets.CityAttackReason( city:table )
	local reasons:table = {};
	pcall( function()
		local ok, results = CityManager.CanStartCommand( city, CityCommandTypes.RANGE_ATTACK, true );
		if type( results ) == "table" and results[CityCommandResults.FAILURE_REASONS] ~= nil then
			for _, key in ipairs( results[CityCommandResults.FAILURE_REASONS] ) do
				local text:string = CleanTextForSpeech( Locale.Lookup( key ) );
				if text ~= "" then table.insert( reasons, text ); end
			end
		end
	end );
	if #reasons > 0 then return table.concat( reasons, ", " ); end
	local damaged:string = nil;
	local noWalls:boolean = false;
	pcall( function()
		local district:table = Players[ city:GetOwner() ]:GetDistricts():FindID( city:GetDistrictID() );
		if district == nil then return; end
		local wallsMax:number = district:GetMaxDamage( DefenseTypes.DISTRICT_OUTER );
		noWalls = ( wallsMax <= 0 );
		local walls:number = district:GetDamage( DefenseTypes.DISTRICT_OUTER );
		local healthMax:number = district:GetMaxDamage( DefenseTypes.DISTRICT_GARRISON );
		local health:number = district:GetDamage( DefenseTypes.DISTRICT_GARRISON );
		if wallsMax > 0 and walls >= wallsMax then
			damaged = "its walls are destroyed and must be repaired";
		elseif wallsMax > 0 and walls > 0 then
			damaged = "its walls are damaged, " .. ( wallsMax - walls ) .. " of " .. wallsMax .. " left";
		elseif health > 0 and healthMax > 0 then
			damaged = "the city is damaged, " .. ( healthMax - health ) .. " of " .. healthMax .. " health";
		end
	end );
	-- a city without walls has no ranged attack, whatever is in range
	if noWalls then
		local garrison:boolean = false;
		pcall( function() 
			for _, unit in ipairs( Units.GetUnitsInPlot( Map.GetPlot( city:GetX(), city:GetY() ) ) ) do
				if unit:GetOwner() == city:GetOwner() and unit:GetCombat() > 0 then garrison = true; end		-- civilians are no garrison
			end
		end );
		return garrison and "it needs walls" or "no walls and no garrison";
	end
	local targets:table = nil;
	pcall( function() targets = GetCityAttackTargets( city ); end );		-- may fail for a city without a garrison
	local hasTargets:boolean = targets ~= nil and next( targets ) ~= nil;
	-- The engine has no "attacked this turn" query (District:CanAttack stays true, CanStartCommand gives no reason, and the
	-- target list is EMPTY after the attack). So: our own record of the attack, or a visible enemy in range the engine refuses.
	if not hasTargets and HubTargets.cityAttackTurn[ AttackKey( city ) ] == Game.GetCurrentGameTurn() then
		return "it already attacked this turn" .. ( damaged ~= nil and ( ", or " .. damaged ) or "" );
	end
	-- not recorded: an enemy within 2 tiles the engine gives no target for may be an attack we did not see, or no line of sight
	if not hasTargets and HasEnemyInCityRange( city ) then
		return "no enemy it can target in range, or it already attacked this turn" .. ( damaged ~= nil and ( ", or " .. damaged ) or "" );
	end
	if hasTargets then
		return "it already attacked this turn" .. ( damaged ~= nil and ( ", or " .. damaged ) or "" );
	end
	if damaged ~= nil and not hasTargets then return "no enemy in range, and " .. damaged; end
	return "no enemy in range";
end

-- R and W with a city selected (UnitPanel is hidden then and says nothing): open the city's ranged attack, or say why not.
function HubTargets.CityAttackKey()
	if not HubCore.IsLocalPlayerActive() or HubCore.IsGamePopupOpen() or HubTargets.GetTargetMode() ~= nil or UI.GetHeadSelectedUnit() ~= nil then
		print( "CityAttackKey: ignored (popup, target mode or a unit selected)" );		-- diagnostic: bug city-r-no-garrison
		return;
	end
	local city:table = UI.GetHeadSelectedCity();
	if city == nil then OutputMessageToScreenReader( "No unit selected" ); return; end		-- UnitPanel is hidden without a selection: W would be silent
	if city:GetOwner() ~= Game.GetLocalPlayer() then print( "CityAttackKey: not our city" ); return; end
	local name:string = Locale.Lookup( city:GetName() );
	local can:boolean = false;
	local ok:boolean, err = pcall( function() can = CityManager.CanStartCommand( city, CityCommandTypes.RANGE_ATTACK ); end );
	if not ok then print( "CityAttackKey: CanStartCommand failed: " .. tostring( err ) ); end
	if can then
		UI.SetInterfaceMode( InterfaceModeTypes.CITY_RANGE_ATTACK );
	else
		local reason:string = "";
		local ok2:boolean, err2 = pcall( function() reason = HubTargets.CityAttackReason( city ); end );
		if not ok2 then print( "CityAttackKey: reason failed: " .. tostring( err2 ) ); end
		OutputMessageToScreenReader( name .. " can't attack" .. ( reason ~= "" and ( ": " .. reason ) or "" ) );
	end
end

function HubTargets.OnInterfaceModeChanged( oldMode:number, newMode:number )
	-- the unit menu is about the mode the game was in; any list is out of place in a target mode
	if HubCore.m_mode ~= nil and ( HubCore.m_mode.name == "menu" or TargetLabel( newMode ) ~= nil or IsChooserMode( newMode ) ) then HubCore.CloseMode( false, true ); end
	-- the transfer list belongs to its mode only
	if HubCore.IsModeOpen( "transfer" ) and not IsTeleportMode( newMode ) then HubCore.CloseMode( false, true ); end
	-- placing a district or wonder: the placement browser opens; it ends with the mode (placed, cancelled or replaced)
	if HubCore.IsModeOpen( "placement" ) then
		HubCore.m_placeReplaced = ( newMode == InterfaceModeTypes.DISTRICT_PLACEMENT or newMode == InterfaceModeTypes.BUILDING_PLACEMENT );
		HubCore.CloseMode( false, true );
		HubCore.m_placeReplaced = false;
	end
	if newMode == InterfaceModeTypes.DISTRICT_PLACEMENT or newMode == InterfaceModeTypes.BUILDING_PLACEMENT then
		HubCore.OpenPlacement( newMode );
		return;
	end
	HubCore.m_enterWatch = -1;
	if HubTargets.warReturn ~= nil and TargetLabel( newMode ) == nil and UI.GetElapsedTime() - HubTargets.warReturn.time < 3 then
		HubCore.After( 0.5, function() WatchWarReturn( 0 ); end );
	end
	if newMode ~= InterfaceModeTypes.MOVE_TO then m_attackIntent = false; end
	local label:string = TargetLabel( newMode );
	if label == nil then return; end
	if IsTeleportMode( newMode ) then
		-- at once (the unit menu is closed above): Enter in a gap would reach ConfirmTarget on the cursor plot
		HubTargets.OpenTransfer();
		return;
	end
	-- the cursor starts at the acting unit or city, and the tiles are chosen from there
	local plot:table = HubCore.GetSelectionPlot();
	if plot ~= nil then HubCursor.SetCursor( plot:GetX(), plot:GetY(), false ); end
	-- CityPanel flips SELECTION -> CITY_RANGE_ATTACK when a city is selected in that mode: one mode line, not two
	local now:number = UI.GetElapsedTime();
	if HubTargets.lastModeLine == newMode and now - HubTargets.lastModeTime < 0.5 then return; end
	HubTargets.lastModeLine, HubTargets.lastModeTime = newMode, now;
	if newMode == InterfaceModeTypes.MOVE_TO and m_attackIntent then
		OutputMessageToScreenReader( "Attack: choose a target with " .. SRKey( "Shift+Arrows" ) .. " or " .. SRKey( "X", "X" ) .. ", " .. SRKey( "Enter" ) .. " to attack, " .. SRKey( "Escape" ) .. " to cancel" );
		return;
	end
	OutputMessageToScreenReader( label .. ": choose a tile with " .. SRKey( "Shift+Arrows" ) .. ", " .. SRKey( "Enter" ) .. " to confirm, " .. SRKey( "Escape" ) .. " to cancel" );
	if IsCityMode( newMode ) then HubCore.After( 0.3, HubTargets.CursorToNearestCityTarget ); end
end

local m_directRequests:table;

-- ===========================================================================
--	TRANSFER TO ANOTHER CITY (great persons; Shift+R): a list of the cities the unit can go to
-- ===========================================================================
local m_transfer		:table = nil;		-- { unitID, operation, items }
local m_transferList	:table = nil;

-- Items for the cities: entries { name, distance, plotIndex } -> nearest first, then by name.
function HubTargets.TransferItems( entries:table )
	table.sort( entries, function( a, b )
		if a.distance ~= b.distance then return a.distance < b.distance; end
		if a.name ~= b.name then return a.name < b.name; end
		return a.plotIndex < b.plotIndex;
	end );
	local items:table = {};
	for _, entry in ipairs( entries ) do
		table.insert( items, { key = entry.plotIndex, plotIndex = entry.plotIndex, name = entry.name,
			text = entry.name .. ", " .. HubCore.Plural( entry.distance, "tile", "tiles" ) } );
	end
	return items;
end

local function BuildTransferItems()
	if m_transfer == nil then return {}; end
	local unit:table = UI.GetHeadSelectedUnit();
	if unit == nil then return {}; end
	local entries:table = {};
	pcall( function()
		local results:table = UnitManager.GetOperationTargets( unit, m_transfer.operation );
		local plots:table = results ~= nil and results[UnitOperationResults.PLOTS] or nil;
		for _, plotId in ipairs( plots or {} ) do
			local plot:table = Map.GetPlotByIndex( plotId );
			local city:table = ( plot ~= nil ) and Cities.GetCityInPlot( plot:GetX(), plot:GetY() ) or nil;
			if city ~= nil then
				table.insert( entries, { name = Locale.Lookup( city:GetName() ), plotIndex = plotId,
					distance = Map.GetPlotDistance( unit:GetX(), unit:GetY(), plot:GetX(), plot:GetY() ) } );
			end
		end
	end );
	return HubTargets.TransferItems( entries );
end

local function CancelTransfer()
	HubCore.CloseMode( false, true );
	UI.SetInterfaceMode( InterfaceModeTypes.SELECTION );
	HubCore.SayResult( "Cancelled" );
end

-- Mirrors WorldInput.lua TeleportToCity() exactly (same CanStartOperation / RequestOperation / SetInterfaceMode), then tells where the unit ended up.
function HubTargets.ConfirmTeleport( unit:table, plot:table, operation )
	if operation == nil then operation = UnitOperationTypes.TELEPORT_TO_CITY; end
	local parameters:table = {};
	parameters[UnitOperationTypes.PARAM_X] = plot:GetX();
	parameters[UnitOperationTypes.PARAM_Y] = plot:GetY();
	if not UnitManager.CanStartOperation( unit, operation, nil, parameters ) then
		HubCore.SayResult( "Cannot transfer there, choose a city from the list" );
		return false;
	end
	local unitName:string = Locale.Lookup( unit:GetName() );
	local city:table = Cities.GetCityInPlot( plot:GetX(), plot:GetY() );
	local cityName:string = ( city ~= nil ) and Locale.Lookup( city:GetName() ) or "the city";
	local unitID:number, owner:number = unit:GetID(), unit:GetOwner();
	local plotIndex:number = plot:GetIndex();
	UnitManager.RequestOperation( unit, operation, parameters );
	UI.SetInterfaceMode( InterfaceModeTypes.SELECTION );
	UI.PlaySound( "Unit_Relocate" );
	HubTargets.m_lastDirectTarget = { plot = plotIndex, time = UI.GetElapsedTime() };
	-- the probe saw an instant move: check the position a moment later
	local function Check( attempt:number )
		local moved:table = Players[ owner ]:GetUnits():FindID( unitID );
		if moved ~= nil and Map.GetPlot( moved:GetX(), moved:GetY() ):GetIndex() == plotIndex then
			HubCore.SayResult( unitName .. " moved to " .. cityName );
		elseif attempt < 3 then
			HubCore.After( 0.6, function() Check( attempt + 1 ); end );
		else
			HubCore.SayResult( unitName .. " did not arrive in " .. cityName );
		end
	end
	HubCore.After( 0.4, function() Check( 1 ); end );
	return true;
end

local function TransferActivate( item:table )
	local unit:table = UI.GetHeadSelectedUnit();
	local plot:table = Map.GetPlotByIndex( item.plotIndex );
	if unit == nil or plot == nil or m_transfer == nil then
		HubCore.SayResult( "Unit no longer available" );
		return;
	end
	local operation = m_transfer.operation;
	HubCore.CloseMode( false, true );
	HubCursor.SetCursor( plot:GetX(), plot:GetY(), false, false, true );
	HubTargets.ConfirmTeleport( unit, plot, operation );
end

-- Opens the city list for the unit in the Transfer mode (OnInterfaceModeChanged calls it).
function HubTargets.OpenTransfer()
	local unit:table = UI.GetHeadSelectedUnit();
	if unit == nil then return; end
	local operation = UI.GetInterfaceModeParameter( UnitOperationTypes.PARAM_OPERATION_TYPE );
	if operation == nil or operation < 0 then operation = UnitOperationTypes.TELEPORT_TO_CITY; end
	m_transfer = { unitID = unit:GetID(), operation = operation };
	if #BuildTransferItems() == 0 then
		UI.SetInterfaceMode( InterfaceModeTypes.SELECTION );
		HubCore.SayResult( "No city to transfer to" );
		return;
	end
	if m_transferList == nil then
		m_transferList = KeyNavList_Create{
			build		= BuildTransferItems,
			isActive	= function() return HubCore.IsModeOpen( "transfer" ); end,
			onActivate	= TransferActivate,
			onClose		= CancelTransfer,
		};
	end
	HubCore.OpenMode( "transfer", m_transferList, "Transfer " .. Locale.Lookup( unit:GetName() ) .. " to which city?" );
end

-- For modes without a direct call below: click the plot with the real mouse, like a sighted player would.
local function ClickCursorPlot()
	local x:number, y:number = HubCursor.GetCursor();
	local screenWidth:number, screenHeight:number = UIManager:GetScreenSizeVal();
	local px:number, py:number = math.floor( screenWidth / 2 ), math.floor( screenHeight / 2 );
	local centerX:number, centerY:number = UI.GetPlotCoordFromNormalizedScreenPos( 0, 0 );
	if centerX ~= x or centerY ~= y then
		px, py = HubCursor.FindPlotScreenPos( x, y );
		if px == nil then
			HubCore.SayResult( "That tile is off screen" );
			return;
		end
	end
	HubCore.m_lastKeyTime = UI.GetElapsedTime();	-- the click is the player's own action
	KeyNavMoveMouseToScreen( px, py );
	HubCore.After( 0.4, function() KeyNavLeftClick(); end );
end

-- Orders the unit to the plot through the game's own path (war declaration check included). A plain move is
-- remembered so that arrival or a stop can be told; an attack or a war declaration (the game asks first, and the
-- order only goes out after the answer) is not a move order.
function HubTargets.IssueMoveOrder( unit:table, plot:table, war:table, enemy:boolean )
	local unitID:number = unit:GetID();
	-- a settler or builder that goes alone near enemies or a camp is told (after the move's own result line)
	local alone:string = nil;
	if war == nil and not enemy and HubEnemies ~= nil then
		local okAlone:boolean, text = pcall( HubEnemies.AloneWarning, unit, plot );
		if okAlone then alone = text; end
	end
	local record:table = nil;
	if war == nil and not enemy then
		record = { dest = plot:GetIndex(), issued = UI.GetElapsedTime(), from = Map.GetPlot( unit:GetX(), unit:GetY() ):GetIndex() };
		HubCore.m_movers[ unitID ] = record;
	end
	MoveUnitToPlot( unit, plot:GetX(), plot:GetY() );
	if alone ~= nil then
		local fromIndex:number = Map.GetPlot( unit:GetX(), unit:GetY() ):GetIndex();
		HubCore.After( 0.9, function()
			-- only when the unit really got the order (it moved or has a destination)
			local mover:table = Players[ Game.GetLocalPlayer() ]:GetUnits():FindID( unitID );
			if mover == nil then return; end
			local moved:boolean = Map.GetPlot( mover:GetX(), mover:GetY() ):GetIndex() ~= fromIndex or UnitManager.GetQueuedDestination( mover ) ~= nil;
			if moved then HubCore.Announce( alone, true, "escort" ); end
		end );
	end
	if record ~= nil then
		HubCore.After( 1.0, function()
			-- the order never started: blocked at once
			if HubCore.m_movers[ unitID ] ~= record then return; end
			local mover:table = Players[ Game.GetLocalPlayer() ]:GetUnits():FindID( unitID );
			if mover ~= nil and Map.GetPlot( mover:GetX(), mover:GetY() ):GetIndex() == record.from and UnitManager.GetQueuedDestination( mover ) == nil then
				HubCore.m_movers[ unitID ] = nil;
				HubCore.SayResult( "Move blocked, the unit did not move" );
			end
		end );
	end
end

-- Form Corps / Form Army (WorldInput FormCorps / FormArmy): the selected unit joins a unit of the cursor plot.
local function ConfirmFormation( unit:table, plot:table, army:boolean )
	local command = army and UnitCommandTypes.FORM_ARMY or UnitCommandTypes.FORM_CORPS;
	local noun:string = army and "army" or "corps";
	local unitID:number, owner:number = unit:GetID(), unit:GetOwner();
	for _, partner in ipairs( Units.GetUnitsInPlotLayerID( plot:GetX(), plot:GetY(), MapLayers.ANY ) ) do
		local parameters:table = {};
		parameters[UnitCommandTypes.PARAM_UNIT_PLAYER] = partner:GetOwner();
		parameters[UnitCommandTypes.PARAM_UNIT_ID] = partner:GetID();
		if UnitManager.CanStartCommand( unit, command, parameters ) then
			local partnerName:string = Locale.Lookup( partner:GetName() );
			local partnerID:number = partner:GetID();
			UnitManager.RequestCommand( unit, command, parameters );
			UI.SetInterfaceMode( InterfaceModeTypes.SELECTION );
			HubCore.SayResult( "Forming " .. ( army and "an " or "a " ) .. noun .. " with " .. partnerName );
			-- the formation changes the units a moment later: tell the outcome
			local function CheckOutcome( attempt:number )
				local merged:table = Players[ owner ]:GetUnits():FindID( unitID );
				if merged == nil then merged = Players[ owner ]:GetUnits():FindID( partnerID ); end
				local formation = ( merged ~= nil ) and merged:GetMilitaryFormation() or nil;
				if formation == MilitaryFormationTypes.CORPS_FORMATION then
					HubCore.SayResult( Locale.Lookup( merged:GetName() ) .. " " .. Locale.Lookup( "LOC_HUD_UNIT_PANEL_CORPS_SUFFIX" ) .. " formed" );
				elseif formation == MilitaryFormationTypes.ARMY_FORMATION then
					HubCore.SayResult( Locale.Lookup( merged:GetName() ) .. " " .. Locale.Lookup( "LOC_HUD_UNIT_PANEL_ARMY_SUFFIX" ) .. " formed" );
				elseif attempt < 3 then
					HubCore.After( 1.0, function() CheckOutcome( attempt + 1 ); end );
				end
			end
			HubCore.After( 1.0, function() CheckOutcome( 1 ); end );
			return;
		end
	end
	HubCore.SayResult( "No unit here can join a " .. noun );
end

-- Modes in which WorldInput sends one request for the cursor plot (PARAM_X / PARAM_Y). kind: the request is a unit
-- operation or a unit command; war: the attack can declare war (the game asks first); say: the spoken confirmation.
m_directRequests = {};
do
	local function Add( modeName:string, kind:string, typeName:string, say:string, war:boolean, nilArg:boolean )
		local mode = InterfaceModeTypes[ modeName ];
		if mode == nil then return; end
		m_directRequests[mode] = { kind = kind, typeName = typeName, say = say, war = war, nilArg = nilArg };
	end
	Add( "COASTAL_RAID", "operation", "COASTAL_RAID", "Coastal raid", true );
	Add( "DEPLOY", "operation", "DEPLOY", nil, false );
	Add( "REBASE", "operation", "REBASE", nil, false );
	Add( "SACRIFICE_SELECTION", "operation", "UNITOPERATION_SOOTHSAYER_SACRIFICE", "Sacrificing", false );
	Add( "AIRLIFT", "command", "AIRLIFT", "Airlifting", false, true );		-- WorldInput passes (unit, AIRLIFT, nil, params) to CanStartCommand
	Add( "KILL_WEAKER_UNIT", "command", "KILL_WEAKER_UNIT", "Killing the weaker unit", false );
	Add( "TRANSFORM_UNIT", "command", "TRANSFORM_UNIT", "Transforming", false );
	Add( "RESTORE_UNIT_MOVES", "command", "RESTORE_UNIT_MOVES", "Restoring moves", false );
	Add( "NAVAL_GOLD_RAID", "command", "NAVAL_GOLD_RAID", "Naval raid", false );
end

local function ConfirmDirectRequest( unit:table, plot:table, mode:number )
	local entry:table = m_directRequests[mode];
	local parameters:table = {};
	local isOperation:boolean = ( entry.kind == "operation" );
	local paramX = isOperation and UnitOperationTypes.PARAM_X or UnitCommandTypes.PARAM_X;
	local paramY = isOperation and UnitOperationTypes.PARAM_Y or UnitCommandTypes.PARAM_Y;
	parameters[paramX] = plot:GetX();
	parameters[paramY] = plot:GetY();
	local requestType = isOperation and ( UnitOperationTypes[ entry.typeName ] or entry.typeName ) or UnitCommandTypes[ entry.typeName ];
	if requestType == nil then HubCore.SayResult( "Cannot do that" ); return; end
	if entry.war then
		local war:table = HubTargets.WarTargets( unit, plot );
		if war ~= nil then
			RememberWarReturn( mode );
			LuaEvents.Civ6Common_ConfirmWarDialog( unit:GetOwner(), war[1], WarTypes.SURPRISE_WAR );
			return;
		end
	end
	local can:boolean;
	if isOperation then
		can = UnitManager.CanStartOperation( unit, requestType, nil, parameters );
	elseif entry.nilArg then
		can = UnitManager.CanStartCommand( unit, requestType, nil, parameters );
	else
		can = UnitManager.CanStartCommand( unit, requestType, parameters );
	end
	if not can then
		HubCore.SayResult( "Not possible there, choose a valid target" );
		return;
	end
	if isOperation then
		UnitManager.RequestOperation( unit, requestType, parameters );
	else
		UnitManager.RequestCommand( unit, requestType, parameters );
	end
	HubTargets.m_lastDirectTarget = { plot = plot:GetIndex(), time = UI.GetElapsedTime() };		-- HubEvents reads the confirmed target (Rebasing / Deploying to <city>)
	UI.SetInterfaceMode( InterfaceModeTypes.SELECTION );
	if entry.say then HubCore.SayResult( entry.say ); end
end

-- Enter in a target mode: what WorldInput does on the left click in that mode, for the cursor plot.
function HubTargets.ConfirmTarget()
	local mode:number, label:string = HubTargets.GetTargetMode();
	if mode == nil then return; end
	local x:number, y:number = HubCursor.GetCursor();
	local plot:table = Map.GetPlot( x, y );
	local unit:table = UI.GetHeadSelectedUnit();
	if plot == nil then return; end
	if unit == nil and not IsCityMode( mode ) then
		-- nothing is selected any more (the unit died or was deselected): leave the mode
		UI.SetInterfaceMode( InterfaceModeTypes.SELECTION );
		HubCore.SayResult( "Nothing selected, cancelled" );
		return;
	end
	if mode == InterfaceModeTypes.MOVE_TO and unit ~= nil then
		if unit:GetX() == x and unit:GetY() == y then
			HubCore.SayResult( "Already here, choose another tile" );
			return;
		end
		local war:table = HubTargets.WarTargets( unit, plot );
		local enemy:boolean = EnemyVisibleAt( plot );
		local path:table = UnitManager.GetMoveToPathEx( unit, plot:GetIndex() );
		local reachable:boolean = path ~= nil and path.plots ~= nil and #path.plots >= 2;
		if war == nil then
			if m_attackIntent and not enemy then
				HubCore.SayResult( "No enemy there, choose a target" );
				return;
			end
			if not reachable then
				local why:string = HubTargets.UnreachableReason( unit, plot );
				HubCore.SayResult( "Unreachable" .. ( why ~= "" and ( ": " .. why ) or "" ) );
				return;
			end
		end
		local attackName:string = ( enemy or war ~= nil ) and TargetName( plot ) or nil;
		if war ~= nil then RememberWarReturn( mode ); end
		local couldMove:boolean = unit:GetMovesRemaining() > 0;
		HubTargets.IssueMoveOrder( unit, plot, war, enemy );
		UI.SetInterfaceMode( InterfaceModeTypes.SELECTION );
		-- an attack move from afar is a move order first (the settler's "Moving, N turns" has its own line in HubEvents)
		if war == nil and enemy and reachable then
			local turns:number = path.turns[ #path.turns ] or 1;
			if turns > 1 or #path.plots > 2 then
				HubCore.SayResult( "Moving to attack" .. ( attackName ~= nil and ( " " .. attackName ) or "" ) .. ", " .. HubCore.Plural( turns, "turn", "turns" ) );
			else
				-- only a fight has a result line to wait for (not a capture of a civilian)
				if couldMove and HubTargets.HoldsEnemyFighter( plot ) then HubCore.MarkAttackPending( unit:GetID() ); end
				HubCore.SayResult( AttackingText( plot, "Attacking" ) );
			end
		end
	elseif mode == InterfaceModeTypes.RANGE_ATTACK and unit ~= nil then
		local parameters:table = {};
		parameters[UnitOperationTypes.PARAM_X] = x;
		parameters[UnitOperationTypes.PARAM_Y] = y;
		local war:table = HubTargets.WarTargets( unit, plot );
		if war ~= nil then
			RememberWarReturn( mode );
			LuaEvents.Civ6Common_ConfirmWarDialog( unit:GetOwner(), war[1], WarTypes.SURPRISE_WAR );
		elseif UnitManager.CanStartOperation( unit, UnitOperationTypes.RANGE_ATTACK, nil, parameters ) then
			UnitManager.RequestOperation( unit, UnitOperationTypes.RANGE_ATTACK, parameters );
			HubTargets.attackTime = UI.GetElapsedTime();
			HubCore.MarkAttackPending( unit:GetID() );
			UI.SetInterfaceMode( InterfaceModeTypes.SELECTION );
			HubCore.SayResult( AttackingText( plot, "Ranged attack" ) );		-- the combat line arrives seconds later
		else
			HubCore.SayResult( "No valid target there" );
		end
	elseif mode == InterfaceModeTypes.AIR_ATTACK and unit ~= nil then
		local parameters:table = {};
		parameters[UnitOperationTypes.PARAM_X] = x;
		parameters[UnitOperationTypes.PARAM_Y] = y;
		local war:table = HubTargets.WarTargets( unit, plot );
		if war ~= nil then
			RememberWarReturn( mode );
			LuaEvents.Civ6Common_ConfirmWarDialog( unit:GetOwner(), war[1], WarTypes.SURPRISE_WAR );
		elseif UnitManager.CanStartOperation( unit, UnitOperationTypes.AIR_ATTACK, nil, parameters ) then
			UnitManager.RequestOperation( unit, UnitOperationTypes.AIR_ATTACK, parameters );
			HubCore.MarkAttackPending( unit:GetID() );
			UI.SetInterfaceMode( InterfaceModeTypes.SELECTION );
			HubCore.SayResult( AttackingText( plot, "Air attack" ) );
		else
			HubCore.SayResult( "No valid target there" );
		end
	elseif IsCityMode( mode ) then
		-- city and district ranged attacks: the targets come from the game; the attack itself is a click
		local city:table = UI.GetHeadSelectedCity();
		local targets:table = ( city ~= nil ) and GetCityAttackTargets( city ) or nil;
		if targets ~= nil and not targets[ plot:GetIndex() ] then
			HubCore.SayResult( "No valid target there" );
			return;
		end
		HubTargets.attackTime = UI.GetElapsedTime();
		HubCore.SayResult( AttackingText( plot, "Attacking" ) );		-- the combat line arrives seconds later
		-- the same request WorldInput's CityRangeAttack/DistrictRangeAttack send on a click; the click itself depends on
		-- the real mouse hover (UI.GetCursorPlotID) and did not reach the target in the 2026-10-23 test
		local params:table = {};
		params[UnitOperationTypes.PARAM_X] = plot:GetX();
		params[UnitOperationTypes.PARAM_Y] = plot:GetY();
		local attacker:table = ( mode == InterfaceModeTypes.DISTRICT_RANGE_ATTACK ) and UI.GetHeadSelectedDistrict() or city;
		if attacker ~= nil and CityManager.CanStartCommand( attacker, CityCommandTypes.RANGE_ATTACK, params ) then
			CityManager.RequestCommand( attacker, CityCommandTypes.RANGE_ATTACK, params );
			HubCore.MarkAttackPending( attacker:GetID() );
			if mode == InterfaceModeTypes.DISTRICT_RANGE_ATTACK then
				HubTargets.districtAttackTurn[ AttackKey( attacker ) ] = Game.GetCurrentGameTurn();
			else
				HubTargets.cityAttackTurn[ AttackKey( attacker ) ] = Game.GetCurrentGameTurn();
			end
			UI.SetInterfaceMode( InterfaceModeTypes.SELECTION );
		else
			HubCore.SayResult( "Cannot attack there" );
		end
	elseif unit ~= nil and IsTeleportMode( mode ) then
		-- list closed (X walks the cities): Enter on a city confirms like the list
		HubTargets.ConfirmTeleport( unit, plot, UI.GetInterfaceModeParameter( UnitOperationTypes.PARAM_OPERATION_TYPE ) );
	elseif unit ~= nil and ( mode == InterfaceModeTypes.FORM_CORPS or mode == InterfaceModeTypes.FORM_ARMY ) then
		ConfirmFormation( unit, plot, mode == InterfaceModeTypes.FORM_ARMY );
	elseif unit ~= nil and m_directRequests[mode] ~= nil then
		ConfirmDirectRequest( unit, plot, mode );
	else
		ClickCursorPlot();
	end
end

function HubTargets.CancelTarget()
	UI.SetInterfaceMode( InterfaceModeTypes.SELECTION );
	HubCore.SayResult( "Cancelled" );
end

-- W (Attack). The game's own Attack hotkey only works while the mouse hovers an enemy (a combat preview is shown);
-- UnitPanel sends SRA_AttackKey when that is not the case. A ranged or air unit enters its attack mode, any other
-- military unit the move mode in which only enemies are valid ("Attack"). In a target mode W confirms, like Enter.
function HubTargets.AttackKey()
	if not HubCore.IsLocalPlayerActive() then return; end
	local mode:number = HubTargets.GetTargetMode();
	if mode ~= nil then
		if mode == InterfaceModeTypes.MOVE_TO and not m_attackIntent then
			m_attackIntent = true;
			OutputMessageToScreenReader( "Attack: choose a target with " .. SRKey( "Shift+Arrows" ) .. " or " .. SRKey( "X", "X" ) .. ", " .. SRKey( "Enter" ) .. " to attack, " .. SRKey( "Escape" ) .. " to cancel" );
			HubCursor.ScanUnits( false );
		else
			HubTargets.ConfirmTarget();
		end
		return;
	end
	local unit:table = UI.GetHeadSelectedUnit();
	if unit == nil or unit:GetOwner() ~= Game.GetLocalPlayer() then
		OutputMessageToScreenReader( "No unit selected" );
		return;
	end
	local name:string = Locale.Lookup( unit:GetName() );
	if unit:GetCombat() <= 0 and unit:GetRangedCombat() <= 0 and unit:GetBombardCombat() <= 0 then
		OutputMessageToScreenReader( name .. " cannot attack" );
		return;
	end
	if unit:GetMovesRemaining() <= 0 then
		OutputMessageToScreenReader( name .. " has no moves left" );
		return;
	end
	local row:table = GameInfo.Units[ unit:GetUnitType() ];
	if row ~= nil and row.Domain == "DOMAIN_AIR" then
		UI.SetInterfaceMode( InterfaceModeTypes.AIR_ATTACK );
	elseif unit:GetRangedCombat() > unit:GetCombat() or unit:GetBombardCombat() > unit:GetCombat() then
		UI.SetInterfaceMode( InterfaceModeTypes.RANGE_ATTACK );
	else
		m_attackIntent = true;
		UI.SetInterfaceMode( InterfaceModeTypes.MOVE_TO );
	end
	HubCore.After( 0.3, function() if HubTargets.GetTargetMode() ~= nil then HubCursor.ScanUnits( false ); end end );
end
