-- ===========================================================================
--	HubTargets: target modes (move to, attacks): entering, confirming, cancelling.
--	Part of the InGameAccess hub (see docs/ingame-plan.md, Architecture): included by
--	UI/Additions/InGameAccess.lua. State and functions other hub modules use are fields of HubTargets.
-- ===========================================================================
HubTargets = {};

local m_attackIntent		:boolean = false;	-- the MOVE_TO mode was entered with the Attack key: only enemies are valid targets

--	TARGET MODES: interface modes in which the game wants a plot (move to, attacks ...)
-- ===========================================================================
local m_targetModes:table = {};		-- InterfaceModeTypes value -> spoken name
do
	local names:table = {
		MOVE_TO = "Move to", RANGE_ATTACK = "Ranged attack", AIR_ATTACK = "Air attack", CITY_RANGE_ATTACK = "City ranged attack",
		DISTRICT_RANGE_ATTACK = "District ranged attack", WMD_STRIKE = "Nuclear strike", ICBM_STRIKE = "Missile strike",
		COASTAL_RAID = "Coastal raid", DEPLOY = "Deploy", REBASE = "Rebase", AIRLIFT = "Airlift", FORM_CORPS = "Form corps",
		FORM_ARMY = "Form army",
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
for _, name in ipairs( { "MAKE_TRADE_ROUTE", "TELEPORT_TO_CITY", "SPY_TRAVEL_TO_CITY", "SPY_CHOOSE_MISSION" } ) do
	if InterfaceModeTypes[name] ~= nil then m_chooserModes[ InterfaceModeTypes[name] ] = true; end
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
	local label:string = m_targetModes[mode];
	if label ~= nil then return mode, label; end
	return nil, nil;
end

-- A list mode cannot be opened in the middle of a target mode. allowTarget: the places list (J) may, it only moves the
-- target cursor (to bring a unit home, say).
function HubTargets.CanOpenMode( allowTarget:boolean )
	if not HubCore.IsLocalPlayerActive() then return false; end
	if not allowTarget and HubTargets.GetTargetMode() ~= nil then
		OutputMessageToScreenReader( "Choose a tile, or Escape to cancel first" );
		return false;
	end
	if HubCore.IsModeOpen( "placement" ) then
		OutputMessageToScreenReader( "Place it, or Escape to cancel first" );
		return false;
	end
	return true;
end

-- Modes in which a city or district (not a unit) acts.
local function IsCityMode( mode:number )
	return mode == InterfaceModeTypes.CITY_RANGE_ATTACK or mode == InterfaceModeTypes.DISTRICT_RANGE_ATTACK;
end

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

local function CombatPreviewText( unit:table, plot:table, combatType )
	local ok:boolean, results = pcall( CombatManager.SimulateAttackInto, unit:GetComponentID(), combatType, plot:GetX(), plot:GetY() );
	if not ok or results == nil then return nil; end
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
			table.insert( parts, "deals " .. wallsDamage .. " damage to the walls, " .. math.max( 0, wallsMax - wallsFinal ) .. " of " .. wallsMax .. " left" );
		end
		if dealt > wallsDamage or wallsDamage == 0 then
			table.insert( parts, "deals " .. dealt .. " damage to the city, " .. math.max( 0, defenderMax - defenderFinal ) .. " of " .. defenderMax .. " health left" );
		end
	elseif defenderFinal >= defenderMax then
		if IsCityOrDistrictPlot( plot ) then
			table.insert( parts, "health to 0" );
		else
			table.insert( parts, "kills the target" );
		end
	else
		table.insert( parts, "deals " .. dealt .. " damage, target left with " .. ( defenderMax - defenderFinal ) .. " of " .. defenderMax );
	end
	local taken:number = attacker[CombatResultParameters.DAMAGE_TO] or 0;
	local attackerMax:number = attacker[CombatResultParameters.MAX_HIT_POINTS] or 0;
	local attackerFinal:number = attacker[CombatResultParameters.FINAL_DAMAGE_TO] or 0;
	if attackerMax > 0 and attackerFinal >= attackerMax then
		table.insert( parts, "you would die" );
	elseif taken > 0 then
		table.insert( parts, "you take " .. taken );
	else
		table.insert( parts, "no damage to you" );
	end
	return table.concat( parts, ", " );
end

-- "Attacking Barbarian Horseman": the name of what stands on the plot (a visible foreign unit, else the city).
local function TargetName( plot:table )
	if not HubCore.IsPlotVisibleToLocal( plot ) then return nil; end
	for _, other in ipairs( Units.GetUnitsInPlot( plot ) ) do
		if other:GetOwner() ~= Game.GetLocalPlayer() and HubCore.IsForeignUnitVisible( other ) then return PlotDescription_GetUnitName( other ); end
	end
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

-- Modes whose valid targets the game lists (WorldInput's OnInterfaceModeChange_* highlight them): the plots of
-- GetOperationTargets / GetCommandTargets, or for Form Corps / Form Army the plots of the partner units.
local m_listedOperations:table = { COASTAL_RAID = "COASTAL_RAID", DEPLOY = "DEPLOY", REBASE = "REBASE" };
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

-- Mode specific words for the cursor plot: path length for a move, valid target and odds for an attack.
function HubTargets.TargetInfo( mode:number, plot:table, unit:table )
	if unit == nil then
		if mode == InterfaceModeTypes.CITY_RANGE_ATTACK or mode == InterfaceModeTypes.DISTRICT_RANGE_ATTACK then
			local city:table = UI.GetHeadSelectedCity();
			local targets:table = ( city ~= nil ) and GetCityAttackTargets( city ) or nil;
			if targets == nil then return nil; end
			if targets[ plot:GetIndex() ] then return "valid target"; end
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
			return "unreachable";
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
	if not HubCore.IsLocalPlayerActive() then return; end
	local capital:table = Players[ Game.GetLocalPlayer() ]:GetCities():GetCapitalCity();
	if capital == nil then OutputMessageToScreenReader( "No capital" ); return; end
	if HubTargets.GetTargetMode() ~= nil then
		HubCursor.SetCursor( capital:GetX(), capital:GetY(), true, true, false, true );
		return;
	end
	-- a placement or chooser mode (trade route ...): selecting the capital would cancel it
	if UI.GetInterfaceMode() ~= InterfaceModeTypes.SELECTION or HubCore.IsModeOpen( "placement" ) then
		OutputMessageToScreenReader( "Escape first" );
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
	OutputMessageToScreenReader( "War not declared. Still choosing a target: Enter to confirm, Escape to cancel" );
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
		OutputMessageToScreenReader( "No enemy in range. Escape to cancel", true );
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
	if noWalls then return "it needs walls"; end
	local targets:table = GetCityAttackTargets( city );
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
	if not HubCore.IsLocalPlayerActive() or HubCore.IsGamePopupOpen() or HubTargets.GetTargetMode() ~= nil or UI.GetHeadSelectedUnit() ~= nil then return; end
	local city:table = UI.GetHeadSelectedCity();
	if city == nil then OutputMessageToScreenReader( "No unit selected" ); return; end		-- UnitPanel is hidden without a selection: W would be silent
	if city:GetOwner() ~= Game.GetLocalPlayer() then return; end
	local name:string = Locale.Lookup( city:GetName() );
	if CityManager.CanStartCommand( city, CityCommandTypes.RANGE_ATTACK ) then
		UI.SetInterfaceMode( InterfaceModeTypes.CITY_RANGE_ATTACK );
	else
		OutputMessageToScreenReader( name .. " can't attack: " .. HubTargets.CityAttackReason( city ) );
	end
end

function HubTargets.OnInterfaceModeChanged( oldMode:number, newMode:number )
	-- the unit menu is about the mode the game was in; any list is out of place in a target mode
	if HubCore.m_mode ~= nil and ( HubCore.m_mode.name == "menu" or m_targetModes[ newMode ] ~= nil or m_chooserModes[ newMode ] ) then HubCore.CloseMode( false, true ); end
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
	if HubTargets.warReturn ~= nil and m_targetModes[ newMode ] == nil and UI.GetElapsedTime() - HubTargets.warReturn.time < 3 then
		HubCore.After( 0.5, function() WatchWarReturn( 0 ); end );
	end
	if newMode ~= InterfaceModeTypes.MOVE_TO then m_attackIntent = false; end
	local label:string = m_targetModes[ newMode ];
	if label == nil then return; end
	-- the cursor starts at the acting unit or city, and the tiles are chosen from there
	local plot:table = HubCore.GetSelectionPlot();
	if plot ~= nil then HubCursor.SetCursor( plot:GetX(), plot:GetY(), false ); end
	-- CityPanel flips SELECTION -> CITY_RANGE_ATTACK when a city is selected in that mode: one mode line, not two
	local now:number = UI.GetElapsedTime();
	if HubTargets.lastModeLine == newMode and now - HubTargets.lastModeTime < 0.5 then return; end
	HubTargets.lastModeLine, HubTargets.lastModeTime = newMode, now;
	if newMode == InterfaceModeTypes.MOVE_TO and m_attackIntent then
		OutputMessageToScreenReader( "Attack: choose a target with Shift+Arrows or X, Enter to attack, Escape to cancel" );
		return;
	end
	OutputMessageToScreenReader( label .. ": choose a tile with Shift+Arrows, Enter to confirm, Escape to cancel" );
	if IsCityMode( newMode ) then HubCore.After( 0.3, HubTargets.CursorToNearestCityTarget ); end
end

local m_directRequests:table;

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
	local record:table = nil;
	if war == nil and not enemy then
		record = { dest = plot:GetIndex(), issued = UI.GetElapsedTime(), from = Map.GetPlot( unit:GetX(), unit:GetY() ):GetIndex() };
		HubCore.m_movers[ unitID ] = record;
	end
	MoveUnitToPlot( unit, plot:GetX(), plot:GetY() );
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
				HubCore.SayResult( "Unreachable" );
				return;
			end
		end
		local attackName:string = ( enemy or war ~= nil ) and TargetName( plot ) or nil;
		if war ~= nil then RememberWarReturn( mode ); end
		HubTargets.IssueMoveOrder( unit, plot, war, enemy );
		UI.SetInterfaceMode( InterfaceModeTypes.SELECTION );
		-- an attack move from afar is a move order first (the settler's "Moving, N turns" has its own line in HubEvents)
		if war == nil and enemy and reachable then
			local turns:number = path.turns[ #path.turns ] or 1;
			if turns > 1 or #path.plots > 2 then
				HubCore.SayResult( "Moving to attack" .. ( attackName ~= nil and ( " " .. attackName ) or "" ) .. ", " .. HubCore.Plural( turns, "turn", "turns" ) );
			else
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
			if mode == InterfaceModeTypes.DISTRICT_RANGE_ATTACK then
				HubTargets.districtAttackTurn[ AttackKey( attacker ) ] = Game.GetCurrentGameTurn();
			else
				HubTargets.cityAttackTurn[ AttackKey( attacker ) ] = Game.GetCurrentGameTurn();
			end
			UI.SetInterfaceMode( InterfaceModeTypes.SELECTION );
		else
			HubCore.SayResult( "Cannot attack there" );
		end
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
			OutputMessageToScreenReader( "Attack: choose a target with Shift+Arrows or X, Enter to attack, Escape to cancel" );
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
