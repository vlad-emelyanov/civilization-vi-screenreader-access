-- ===========================================================================
--	InGameAccess: screen reader hub for the in-game UI (see docs/ingame-plan.md).
--	A context without visuals, added to InGame (UI/Additions/InGameAccess.xml). It owns
--	  - the map cursor (Shift+Arrows) and its plot announcements,
--	  - the in-game hotkeys (I plot details, J cursor to selection, N what is next, Tab unit actions),
--	  - the unit actions menu and the target modes (move to, attack ...), which take over Up/Down/Enter/Escape and
--	    Shift+Arrows through this context's input handler (see the bottom of the file),
--	  - event announcements: unit/city selected, new turn, end of turn, unit results, enemies spotted.
--	Input order (verified, see docs/ingame-plan.md): this context's input handler runs before WorldInput and
--	ActionPanel; a key it consumes (KeyDown and KeyUp) also never becomes an input action.
-- ===========================================================================

include( "ScreenReader" );
include( "KeyboardNavigation" );
include( "PlotDescription" );
include( "KeyNavList" );
include( "Civ6Common" );		-- MoveUnitToPlot (war declaration check + the right move/attack operation)

-- ===========================================================================
--	MEMBERS
-- ===========================================================================
local MOUSE_MOVE_DELAY		:number = 0.8;		-- seconds to let the camera settle before the real mouse follows the cursor

local m_cursorX				:number = nil;		-- map cursor (plot coordinates)
local m_cursorY				:number = nil;
local m_mouseTimer			:number = -1;		-- >= 0: seconds until the mouse is moved onto the cursor plot
local m_actions				:table = {};		-- actionId -> handler
local m_lastAnnouncedTurn	:string = "";		-- "<local player>:<turn>" of the last turn announcement (hotseat: every player hears their turn)
local m_cursorPlayer		:number = -1;		-- local player the cursor belongs to
local m_ready				:boolean = false;	-- a game is loaded (LoadScreenClose seen): event announcements are allowed
local m_menuOpen			:boolean = false;	-- the unit actions menu is open
local m_unitActions			:table = {};		-- plain list of the selected unit's actions, sent by UnitPanel (SRA_UnitActions)
local m_delayed				:table = {};		-- { time = seconds left, fn = function }
local m_enterWatch			:number = -1;		-- >= 0: Enter (Next Action) was pressed; seconds until we check that something was said
local m_enterLabel			:string = "";		-- what the action panel said Enter would do
local m_lastResultTime		:number = -100;		-- UI.GetElapsedTime() of the last announced result of a player's action
local m_movers				:table = {};		-- unit id -> { dest = plot index }: units on a move order given in this session
local m_spotted				:table = {};		-- "player:unit" -> turn the enemy was last announced
local m_spottedTurn			:number = -1;		-- turn m_spottedCount counts
local m_spottedCount		:number = 0;

-- ===========================================================================
--	HELPERS
-- ===========================================================================

-- Runs f, printing any error instead of silently losing it.
local function Safe( name:string, f )
	return function( ... )
		local count:number = select( "#", ... );
		local args:table = { ... };
		local ok:boolean, err = xpcall( function() return f( unpack(args, 1, count) ); end, KeyNavErrorHandler );
		if not ok then print( "InGameAccess " .. name .. " error: " .. tostring(err) ); end
	end
end

local function Capitalize( text:string )
	text = string.lower( text );
	return string.upper( string.sub(text, 1, 1) ) .. string.sub( text, 2 );
end

local function IsLocalPlayerActive()
	local localPlayer:number = Game.GetLocalPlayer();
	return localPlayer ~= nil and localPlayer ~= -1 and Players[localPlayer] ~= nil;
end

-- The selected unit or city: what "relative to me" refers to.
local function GetSelectionPlot()
	local unit:table = UI.GetHeadSelectedUnit();
	if unit ~= nil then return Map.GetPlot( unit:GetX(), unit:GetY() ), unit; end
	local city:table = UI.GetHeadSelectedCity();
	if city ~= nil then return Map.GetPlot( city:GetX(), city:GetY() ), nil; end
	return nil, nil;
end

local function FormatNumber( value:number )
	return tostring( math.floor( value * 10 + 0.5 ) / 10 );
end

-- Runs fn after the given seconds (from the update loop).
local function After( seconds:number, fn )
	table.insert( m_delayed, { time = seconds, fn = fn } );
end

-- Speaks the result of something the player just did. Selection announcements that follow within a moment (the
-- game selects the next unit) do not cut it off.
local function SayResult( text:string )
	m_lastResultTime = UI.GetElapsedTime();
	OutputMessageToScreenReader( text, false );
end

local function IsPlotVisibleToLocal( plot:table )
	local vis:table = PlayersVisibility[ Game.GetLocalPlayer() ];
	return vis ~= nil and plot ~= nil and vis:IsVisible( plot:GetIndex() );
end

local function Plural( n:number, one:string, many:string )
	if n == 1 then return n .. " " .. one; end
	return n .. " " .. many;
end

-- Adds a handler to an event when the game has that event.
local function AddEvent( name:string, handler )
	if Events[name] == nil then
		print( "InGameAccess: unknown event " .. name );
		return;
	end
	Events[name].Add( Safe( name, handler ) );
end

-- ===========================================================================
--	MAP CURSOR
-- ===========================================================================

-- Keeps the real mouse on the cursor plot (for sighted helpers and for the few things that still click),
-- once the camera has had time to arrive. The plot tooltip must not read the plot again: it is already announced.
local function QueueMouseMove( plot:table )
	LuaEvents.SRA_CursorPlot( plot:GetIndex() );
	m_mouseTimer = MOUSE_MOVE_DELAY;
end

-- Finds where a plot is on the screen by sampling the engine's screen-to-plot mapping (there is no plot-to-screen
-- call). Normalized screen coordinates run from -1 to 1 with y up. Returns pixel coordinates or nil when off screen.
local function FindPlotScreenPos( x:number, y:number )
	local sumX:number, sumY:number, count:number = 0, 0, 0;
	local STEPS:number = 25;
	for iy = -STEPS, STEPS do
		for ix = -STEPS, STEPS do
			local nx:number, ny:number = ix / STEPS, iy / STEPS;
			local px:number, py:number = UI.GetPlotCoordFromNormalizedScreenPos( nx, ny );
			if px == x and py == y then
				sumX = sumX + nx;
				sumY = sumY + ny;
				count = count + 1;
			end
		end
	end
	if count == 0 then return nil; end
	local screenWidth:number, screenHeight:number = UIManager:GetScreenSizeVal();
	return math.floor( ( sumX / count / 2 + 0.5 ) * screenWidth ), math.floor( ( 0.5 - sumY / count / 2 ) * screenHeight );
end

local function UpdateMouse( deltaTime:number )
	if m_mouseTimer < 0 then return; end
	m_mouseTimer = m_mouseTimer - deltaTime;
	if m_mouseTimer >= 0 then return; end
	m_mouseTimer = -1;
	if m_cursorX == nil then return; end
	-- SetCursor asked the camera to put the cursor plot at the screen centre. Near the edge of the map it cannot, and
	-- the mouse at the centre would sit on another plot (and the game would read that one): find the real position.
	local centerX:number, centerY:number = UI.GetPlotCoordFromNormalizedScreenPos( 0, 0 );
	local screenWidth:number, screenHeight:number = UIManager:GetScreenSizeVal();
	if centerX == m_cursorX and centerY == m_cursorY then
		KeyNavMoveMouseToScreen( math.floor( screenWidth / 2 ), math.floor( screenHeight / 2 ) );
		return;
	end
	local px:number, py:number = FindPlotScreenPos( m_cursorX, m_cursorY );
	if px ~= nil then KeyNavMoveMouseToScreen( px, py ); end
end

local function ResetCursor()
	m_cursorX, m_cursorY = nil, nil;
	m_mouseTimer = -1;
	m_cursorPlayer = Game.GetLocalPlayer();
end

local function GetCursor()
	if m_cursorPlayer ~= Game.GetLocalPlayer() then ResetCursor(); end	-- hotseat: the next player starts at their own units
	if m_cursorX == nil then
		local plot:table = GetSelectionPlot();
		local capital:table = nil;
		if IsLocalPlayerActive() then capital = Players[ Game.GetLocalPlayer() ]:GetCities():GetCapitalCity(); end
		if plot ~= nil then
			m_cursorX, m_cursorY = plot:GetX(), plot:GetY();
		elseif capital ~= nil then
			m_cursorX, m_cursorY = capital:GetX(), capital:GetY();
		else
			m_cursorX, m_cursorY = UI.GetPlotCoordFromNormalizedScreenPos( 0, 0 );	-- what the camera is looking at
		end
	end
	return m_cursorX, m_cursorY;
end

-- ===========================================================================
--	TARGET MODES: interface modes in which the game wants a plot (move to, attacks ...)
-- ===========================================================================
local m_targetModes:table = {};		-- InterfaceModeTypes value -> spoken name
do
	local names:table = {
		MOVE_TO = "Move to", RANGE_ATTACK = "Ranged attack", AIR_ATTACK = "Air attack", CITY_RANGE_ATTACK = "City ranged attack",
		DISTRICT_RANGE_ATTACK = "District ranged attack", WMD_STRIKE = "Nuclear strike", ICBM_STRIKE = "Missile strike",
		COASTAL_RAID = "Coastal raid", DEPLOY = "Deploy", REBASE = "Rebase", AIRLIFT = "Airlift", FORM_CORPS = "Form corps",
		FORM_ARMY = "Form army", TELEPORT_TO_CITY = "Teleport to city", MAKE_TRADE_ROUTE = "Make trade route",
		NAVAL_GOLD_RAID = "Naval raid", SACRIFICE_SELECTION = "Sacrifice", KILL_WEAKER_UNIT = "Kill weaker unit",
		TRANSFORM_UNIT = "Transform unit", RESTORE_UNIT_MOVES = "Restore moves", PRIORITY_TARGET = "Priority target",
	};
	for name, label in pairs( names ) do
		local mode = InterfaceModeTypes[name];
		if mode ~= nil then m_targetModes[mode] = label; end
	end
end

local function GetTargetMode()
	local mode:number = UI.GetInterfaceMode();
	local label:string = m_targetModes[mode];
	if label ~= nil then return mode, label; end
	return nil, nil;
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

-- What the game's combat preview would say for this attack: damage both ways and whether someone dies.
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
	if defenderMax > 0 and defenderFinal >= defenderMax then
		table.insert( parts, "kills the target" );
	else
		table.insert( parts, "deals " .. dealt .. " damage" .. ( defenderMax > 0 and ( ", target left with " .. ( defenderMax - defenderFinal ) .. " of " .. defenderMax ) or "" ) );
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

local function EnemyVisibleAt( plot:table )
	if not IsPlotVisibleToLocal( plot ) then return false; end
	local localPlayer:number = Game.GetLocalPlayer();
	for _, other in ipairs( Units.GetUnitsInPlot( plot ) ) do
		if other:GetOwner() ~= localPlayer then return true; end
	end
	return false;
end

-- Mode specific words for the cursor plot: path length for a move, valid target and odds for an attack.
local function TargetInfo( mode:number, plot:table, unit:table )
	if unit == nil then return nil; end
	if mode == InterfaceModeTypes.MOVE_TO then
		if unit:GetX() == plot:GetX() and unit:GetY() == plot:GetY() then return "here"; end
		local path:table = UnitManager.GetMoveToPathEx( unit, plot:GetIndex() );
		if path == nil or path.plots == nil or #path.plots < 2 then return "unreachable"; end
		local turns:number = path.turns[ #path.turns ] or 1;
		local text:string = Plural( turns, "turn", "turns" );
		if EnemyVisibleAt( plot ) then
			text = "attack, " .. text;
			if turns <= 1 then
				local preview:string = CombatPreviewText( unit, plot, nil );
				if preview ~= nil then text = text .. ", " .. preview; end
			end
		end
		return text;
	elseif mode == InterfaceModeTypes.RANGE_ATTACK or mode == InterfaceModeTypes.AIR_ATTACK then
		local operation:number = ( mode == InterfaceModeTypes.RANGE_ATTACK ) and UnitOperationTypes.RANGE_ATTACK or UnitOperationTypes.AIR_ATTACK;
		if not GetAttackTargets( unit, operation )[ plot:GetIndex() ] then return "no target"; end
		local combatType = nil;
		if mode == InterfaceModeTypes.RANGE_ATTACK then
			combatType = CombatTypes.RANGED;
			if unit:GetBombardCombat() > unit:GetRangedCombat() then combatType = CombatTypes.BOMBARD; end
		end
		local preview:string = CombatPreviewText( unit, plot, combatType );
		return "valid target" .. ( preview ~= nil and ( ", " .. preview ) or "" );
	end
	return nil;
end

local function DescribeCursorPlot( plot:table )
	local selectionPlot:table, unit:table = GetSelectionPlot();
	local options:table = {};
	local localPlayer:number = Game.GetLocalPlayer();
	if unit ~= nil and unit:GetOwner() == localPlayer then options.excludeUnitId = unit:GetID(); end
	local text:string = PlotDescription_GetShort( plot, options );
	local mode:number = GetTargetMode();
	if mode ~= nil then
		local info:string = TargetInfo( mode, plot, unit );
		if info ~= nil then text = info .. ". " .. text; end
	end
	local relative:string = PlotDescription_GetRelative( selectionPlot, plot );
	if relative ~= nil then text = text .. ". " .. relative; end
	return text;
end

-- Puts the cursor on (x, y), moves the camera there and optionally speaks the plot.
local function SetCursor( x:number, y:number, speak:boolean, interrupt:boolean )
	local plot:table = Map.GetPlot( x, y );
	if plot == nil then return; end
	m_cursorPlayer = Game.GetLocalPlayer();
	m_cursorX, m_cursorY = x, y;
	UI.LookAtPlotScreenPosition( x, y, 0.5, 0.5 );
	QueueMouseMove( plot );
	if speak then
		OutputMessageToScreenReader( DescribeCursorPlot( plot ), not interrupt );
	end
end

-- Shift+Arrows. Left/Right step along the row; Up/Down step to the next row north/south (alternately north-west
-- and north-east, so that two steps go straight north, as on the screen).
local function MoveCursor( dx:number, dy:number )
	if not IsLocalPlayerActive() then return; end
	local x:number, y:number = GetCursor();
	x = x + dx;
	y = y + dy;
	local width:number, height:number = Map.GetGridSize();
	if y < 0 or y >= height then
		OutputMessageToScreenReader( "Edge of the map" );
		return;
	end
	if x < 0 or x >= width then
		if Map.IsWrapX() then
			x = x % width;
		else
			OutputMessageToScreenReader( "Edge of the map" );
			return;
		end
	end
	SetCursor( x, y, true, true );
end

-- Period: the cursor goes to the selected unit or city and says what is there.
local function CursorToSelection()
	if not IsLocalPlayerActive() then return; end
	local plot:table, unit:table = GetSelectionPlot();
	if plot == nil then
		OutputMessageToScreenReader( "Nothing selected" );
		return;
	end
	SetCursor( plot:GetX(), plot:GetY(), false );
	local options:table = {};
	if unit ~= nil then options.excludeUnitId = unit:GetID(); end
	local name:string = "";	-- a selected city is named by its own plot description
	if unit ~= nil then name = Locale.Lookup( unit:GetName() ) .. ". "; end
	OutputMessageToScreenReader( name .. PlotDescription_GetShort( plot, options ) );
end

local function SelectUnitObject( unit:table )
	UI.DeselectAllCities();
	UI.DeselectUnit( unit );
	UI.SelectUnit( unit );
	if UI.RebuildSelectionList ~= nil then UI.RebuildSelectionList( unit ); end
end

-- Control+K: select the next of all the local player's units (also fortified, sleeping and automated ones), by unit id.
local function CycleAllUnits()
	if not IsLocalPlayerActive() then return; end
	local units:table = {};
	for _, unit in Players[ Game.GetLocalPlayer() ]:GetUnits():Members() do table.insert( units, unit ); end
	if #units == 0 then
		OutputMessageToScreenReader( "You have no units" );
		return;
	end
	table.sort( units, function( a, b ) return a:GetID() < b:GetID(); end );
	local selected:table = UI.GetHeadSelectedUnit();
	local current:number = 0;
	if selected ~= nil then
		for i, unit in ipairs( units ) do
			if unit:GetID() == selected:GetID() then current = i; end
		end
	end
	SelectUnitObject( units[ current % #units + 1 ] );
end

-- K: select the unit (or city) of the local player on the cursor plot; pressed again it cycles through them.
-- Needed to wake fortified units and to pick one of a stack, which Next Action never selects.
local function SelectAtCursor()
	if not IsLocalPlayerActive() then return; end
	local x:number, y:number = GetCursor();
	local plot:table = Map.GetPlot( x, y );
	if plot == nil then return; end
	local localPlayer:number = Game.GetLocalPlayer();
	local candidates:table = {};
	for _, unit in ipairs( Units.GetUnitsInPlot( plot ) ) do
		if unit:GetOwner() == localPlayer then table.insert( candidates, { unit = unit } ); end
	end
	local city:table = Cities.GetCityInPlot( x, y );
	if city ~= nil and city:GetOwner() == localPlayer then table.insert( candidates, { city = city } ); end
	if #candidates == 0 then
		OutputMessageToScreenReader( "Nothing of yours here" );
		return;
	end
	local selectedUnit:table = UI.GetHeadSelectedUnit();
	local selectedCity:table = UI.GetHeadSelectedCity();
	local current:number = 0;
	for i, candidate in ipairs( candidates ) do
		if candidate.unit ~= nil and selectedUnit ~= nil and candidate.unit:GetID() == selectedUnit:GetID() then current = i; end
		if candidate.city ~= nil and selectedUnit == nil and selectedCity ~= nil and candidate.city:GetID() == selectedCity:GetID() then current = i; end
	end
	local target:table = candidates[ current % #candidates + 1 ];
	if target.unit ~= nil then
		SelectUnitObject( target.unit );
	else
		UI.DeselectAllUnits();
		UI.SelectCity( target.city );
	end
end

-- X: the cursor jumps to the nearest foreign unit in view (hostile ones first); pressed again, to the next one.
-- Finds targets for the attack modes, and threats in general. Said like a cursor move, so target modes add their info.
local m_scanKey:string = nil;
local function ScanUnits()
	if not IsLocalPlayerActive() then return; end
	local localPlayer:number = Game.GetLocalPlayer();
	local originPlot:table = GetSelectionPlot();
	if originPlot == nil then
		local x:number, y:number = GetCursor();
		originPlot = Map.GetPlot( x, y );
	end
	local found:table = {};
	for playerID = 0, 63 do
		local player:table = Players[ playerID ];
		if playerID ~= localPlayer and player ~= nil and player:IsAlive() then
			local hostile:boolean = player:IsBarbarian() or ( Players[ localPlayer ]:GetDiplomacy() ~= nil and Players[ localPlayer ]:GetDiplomacy():IsAtWarWith( playerID ) );
			for _, unit in player:GetUnits():Members() do
				local plot:table = Map.GetPlot( unit:GetX(), unit:GetY() );
				local distance:number = Map.GetPlotDistance( originPlot:GetX(), originPlot:GetY(), unit:GetX(), unit:GetY() );
				if IsPlotVisibleToLocal( plot ) and distance <= 10 then
					table.insert( found, { key = playerID .. ":" .. unit:GetID(), x = unit:GetX(), y = unit:GetY(), distance = distance, hostile = hostile } );
				end
			end
		end
	end
	if #found == 0 then
		OutputMessageToScreenReader( "No foreign units in view" );
		return;
	end
	table.sort( found, function( a, b )
		if a.hostile ~= b.hostile then return a.hostile; end
		if a.distance ~= b.distance then return a.distance < b.distance; end
		return a.key < b.key;
	end );
	local next:number = 1;
	for i, entry in ipairs( found ) do
		if entry.key == m_scanKey then next = i % #found + 1; end
	end
	m_scanKey = found[ next ].key;
	SetCursor( found[ next ].x, found[ next ].y, true, true );
end

-- I: details of the cursor plot.
local function SpeakPlotDetails()
	if not IsLocalPlayerActive() then return; end
	local x:number, y:number = GetCursor();
	local plot:table = Map.GetPlot( x, y );
	local selectionPlot:table, unit:table = GetSelectionPlot();
	local options:table = {};
	if unit ~= nil then options.excludeUnitId = unit:GetID(); end
	local text:string = PlotDescription_GetDetailed( plot, options );
	local relative:string = PlotDescription_GetRelative( selectionPlot, plot );
	if relative ~= nil then text = text .. ". " .. relative; end
	OutputMessageToScreenReader( text );
end

-- ===========================================================================
--	WHAT IS NEXT (N)
-- ===========================================================================

-- What the Next Action key (Enter) will do, as the game's action panel says it ("Unit needs orders", "Choose
-- production", "Next turn", ...). Read from the panel's own label so that expansion blockers are covered too.
local function SpeakWhatsNext()
	if not IsLocalPlayerActive() then return; end
	local label:table = ContextPtr:LookUpControl( "/InGame/HUD/ActionPanel/EndTurnText" );
	local text:string = nil;
	if label ~= nil then text = CleanTextForSpeech( label:GetText() ); end
	if text == nil or text == "" then
		OutputMessageToScreenReader( "Next action unknown" );
		return;
	end
	OutputMessageToScreenReader( Capitalize( text ) );
end

-- ===========================================================================
--	ANNOUNCEMENTS
-- ===========================================================================

local function UnitText( unit:table )
	local parts:table = { Locale.Lookup( unit:GetName() ) };
	local maxMoves:number = unit:GetMaxMoves();
	if maxMoves > 0 then
		table.insert( parts, FormatNumber( unit:GetMovesRemaining() ) .. " of " .. FormatNumber( maxMoves ) .. " moves" );
	end
	local row:table = GameInfo.Units[ unit:GetUnitType() ];
	if row ~= nil and row.BuildCharges ~= nil and row.BuildCharges > 0 then
		local charges:number = unit:GetBuildCharges();
		table.insert( parts, charges .. ( charges == 1 and " charge" or " charges" ) );
	end
	local damage:number = unit:GetDamage();
	if damage > 0 then
		table.insert( parts, ( unit:GetMaxDamage() - damage ) .. " of " .. unit:GetMaxDamage() .. " health" );
	end
	return table.concat( parts, ", " );
end

local function OnUnitSelectionChanged( playerID:number, unitID:number, hexI:number, hexJ:number, hexK:number, isSelected:boolean, isEditable:boolean )
	m_menuOpen = false;
	if playerID ~= Game.GetLocalPlayer() or not isSelected then return; end
	m_enterWatch = -1;
	local unit:table = Players[playerID]:GetUnits():FindID( unitID );
	if unit == nil then return; end
	local plot:table = Map.GetPlot( unit:GetX(), unit:GetY() );
	if plot == nil then return; end
	SetCursor( plot:GetX(), plot:GetY(), false );
	local text:string = UnitText( unit ) .. ". " .. PlotDescription_GetShort( plot, { excludeUnitId = unit:GetID() } );
	OutputMessageToScreenReader( text, UI.GetElapsedTime() - m_lastResultTime < 1.5 );
end

local function CityProductionText( city:table )
	local queue:table = city:GetBuildQueue();
	if queue == nil then return nil; end
	local hash:number = queue:GetCurrentProductionTypeHash();
	if hash == nil or hash == 0 then return "No production"; end
	local row:table = GameInfo.Buildings[hash] or GameInfo.Districts[hash] or GameInfo.Units[hash] or GameInfo.Projects[hash];
	if row == nil then return nil; end
	local text:string = Locale.Lookup( row.Name );
	local turns:number = queue:GetTurnsLeft();
	if turns ~= nil and turns > 0 then
		text = text .. ", " .. turns .. ( turns == 1 and " turn" or " turns" );
	end
	return text;
end

local function CityGrowthText( city:table )
	local growth:table = city:GetGrowth();
	if growth == nil then return nil; end
	local turns:number = growth:GetTurnsUntilGrowth();
	if turns ~= nil and turns > 0 and turns ~= -1 then
		return "grows in " .. turns .. ( turns == 1 and " turn" or " turns" );
	end
	local starve:number = growth:GetTurnsUntilStarvation();
	if starve ~= nil and starve > 0 and starve ~= -1 then
		return "starving in " .. starve .. ( starve == 1 and " turn" or " turns" );
	end
	return "not growing";
end

local function OnCitySelectionChanged( owner:number, cityID:number, i:number, j:number, k:number, isSelected:boolean, isEditable:boolean )
	m_menuOpen = false;
	if owner ~= Game.GetLocalPlayer() or not isSelected then return; end
	m_enterWatch = -1;
	local city:table = Players[owner]:GetCities():FindID( cityID );
	if city == nil then return; end
	local plot:table = Map.GetPlot( city:GetX(), city:GetY() );
	if plot ~= nil then SetCursor( plot:GetX(), plot:GetY(), false ); end
	local parts:table = { Locale.Lookup( city:GetName() ), Locale.Lookup( "LOC_HUD_CITY_POPULATION" ) .. " " .. city:GetPopulation() };
	local production:string = CityProductionText( city );
	if production ~= nil then table.insert( parts, production ); end
	local growth:string = CityGrowthText( city );
	if growth ~= nil then table.insert( parts, growth ); end
	OutputMessageToScreenReader( table.concat( parts, ", " ) );
end

-- "Turn 5, 3600 BC". Said once per turn: a new turn and a finished load both announce it, and a loaded game
-- gets no turn-begin event at all.
local function AnnounceTurn()
	if not IsLocalPlayerActive() then return; end
	local turn:number = Game.GetCurrentGameTurn();
	local key:string = Game.GetLocalPlayer() .. ":" .. turn;
	if key == m_lastAnnouncedTurn then return; end
	m_lastAnnouncedTurn = key;
	if m_cursorPlayer ~= Game.GetLocalPlayer() then ResetCursor(); end
	OutputMessageToScreenReader( "Turn " .. turn .. ", " .. Calendar.MakeYearStr( turn ), true );
end

-- A game was loaded or started: forget everything about the previous one.
local function OnLoadScreenClose()
	m_lastAnnouncedTurn = "";
	ResetCursor();
	m_ready = true;
	m_movers = {};
	m_spotted = {};
	-- A save made between turns loads before the player's turn has begun (LocalPlayerTurnBegin follows and announces
	-- the right turn); announce here only when the turn is already running, with a late fallback.
	local player:table = Players[ Game.GetLocalPlayer() ];
	if player ~= nil and player:IsTurnActive() then
		AnnounceTurn();
	else
		After( 3, AnnounceTurn );
	end
end

local function OnLocalPlayerTurnEnd()
	m_menuOpen = false;
	m_enterWatch = -1;
	OutputMessageToScreenReader( "Turn ended", true );
end

-- ===========================================================================
--	TARGET MODES: entering, confirming (Enter) and cancelling (Escape)
-- ===========================================================================
local function OnInterfaceModeChanged( oldMode:number, newMode:number )
	m_menuOpen = false;
	m_enterWatch = -1;
	local label:string = m_targetModes[ newMode ];
	if label == nil then return; end
	-- the cursor starts at the acting unit or city, and the tiles are chosen from there
	local plot:table = GetSelectionPlot();
	if plot ~= nil then SetCursor( plot:GetX(), plot:GetY(), false ); end
	OutputMessageToScreenReader( label .. ": choose a tile with Shift+Arrows, Enter to confirm, Escape to cancel" );
end

-- For modes without a direct call below: click the plot with the real mouse, like a sighted player would.
local function ClickCursorPlot()
	local x:number, y:number = GetCursor();
	local screenWidth:number, screenHeight:number = UIManager:GetScreenSizeVal();
	local px:number, py:number = math.floor( screenWidth / 2 ), math.floor( screenHeight / 2 );
	local centerX:number, centerY:number = UI.GetPlotCoordFromNormalizedScreenPos( 0, 0 );
	if centerX ~= x or centerY ~= y then
		px, py = FindPlotScreenPos( x, y );
		if px == nil then
			SayResult( "That tile is off screen" );
			return;
		end
	end
	KeyNavMoveMouseToScreen( px, py );
	After( 0.4, function() KeyNavLeftClick(); end );
end

-- Enter in a target mode: what WorldInput does on the left click in that mode, for the cursor plot.
local function ConfirmTarget()
	local mode:number, label:string = GetTargetMode();
	if mode == nil then return; end
	local x:number, y:number = GetCursor();
	local plot:table = Map.GetPlot( x, y );
	local unit:table = UI.GetHeadSelectedUnit();
	if plot == nil then return; end
	if mode == InterfaceModeTypes.MOVE_TO and unit ~= nil then
		if unit:GetX() == x and unit:GetY() == y then
			SayResult( "Already here, choose another tile" );
			return;
		end
		if TargetInfo( mode, plot, unit ) == "unreachable" then
			SayResult( "Unreachable" );
			return;
		end
		m_movers[ unit:GetID() ] = { dest = plot:GetIndex() };
		MoveUnitToPlot( unit, x, y );
		UI.SetInterfaceMode( InterfaceModeTypes.SELECTION );
	elseif mode == InterfaceModeTypes.RANGE_ATTACK and unit ~= nil then
		local parameters:table = {};
		parameters[UnitOperationTypes.PARAM_X] = x;
		parameters[UnitOperationTypes.PARAM_Y] = y;
		if UnitManager.CanStartOperation( unit, UnitOperationTypes.RANGE_ATTACK, nil, parameters ) then
			UnitManager.RequestOperation( unit, UnitOperationTypes.RANGE_ATTACK, parameters );
			UI.SetInterfaceMode( InterfaceModeTypes.SELECTION );
			SayResult( "Ranged attack" );
		else
			SayResult( "No valid target there" );
		end
	elseif mode == InterfaceModeTypes.AIR_ATTACK and unit ~= nil then
		local parameters:table = {};
		parameters[UnitOperationTypes.PARAM_X] = x;
		parameters[UnitOperationTypes.PARAM_Y] = y;
		local results:table = nil;
		if IsPlotVisibleToLocal( plot ) then results = CombatManager.IsAttackChangeWarState( unit:GetComponentID(), x, y ); end
		if results ~= nil and #results > 0 then
			LuaEvents.Civ6Common_ConfirmWarDialog( unit:GetOwner(), results[1], WarTypes.SURPRISE_WAR );
		elseif UnitManager.CanStartOperation( unit, UnitOperationTypes.AIR_ATTACK, nil, parameters ) then
			UnitManager.RequestOperation( unit, UnitOperationTypes.AIR_ATTACK, parameters );
			UI.SetInterfaceMode( InterfaceModeTypes.SELECTION );
			SayResult( "Air attack" );
		else
			SayResult( "No valid target there" );
		end
	else
		ClickCursorPlot();
	end
end

local function CancelTarget()
	UI.SetInterfaceMode( InterfaceModeTypes.SELECTION );
	SayResult( "Cancelled" );
end

-- ===========================================================================
--	UNIT ACTIONS MENU (Tab): the actions of the game's own unit panel (Panels/UnitPanel.lua)
-- ===========================================================================
local OPERATION_RESULTS = {
	UNITOPERATION_FORTIFY = "Fortified", UNITOPERATION_HEAL = "Fortified until healed", UNITOPERATION_SLEEP = "Sleeping",
	UNITOPERATION_ALERT = "On alert", UNITOPERATION_SKIP_TURN = "Turn skipped", UNITOPERATION_AUTOMATE_EXPLORE = "Exploring automatically",
	UNITOPERATION_REST_REPAIR = "Resting", UNITCOMMAND_WAKE = "Awake", UNITCOMMAND_CANCEL = "Orders cancelled",
};
-- Actions that announce their outcome in another way (events below, popups, target modes).
local RESULT_SILENT = {
	UNITOPERATION_FOUND_CITY = true, UNITOPERATION_BUILD_IMPROVEMENT = true, UNITCOMMAND_UPGRADE = true, PROMOTION = true,
	UNITOPERATION_MOVE_TO = true, UNITCOMMAND_PROMOTE = true,
};

local function OnUnitActionsReceived( unitId:number, list:table )
	m_unitActions = list or {};
end

local function BuildMenuItems()
	local items:table = {};
	if UI.GetHeadSelectedUnit() == nil then return items; end
	m_unitActions = {};
	LuaEvents.SRA_RequestUnitActions();		-- UnitPanel answers at once with SRA_UnitActions
	for _, action in ipairs( m_unitActions ) do
		local text:string = action.name;
		if action.hotkey ~= nil and action.hotkey ~= "" then text = text .. ", key " .. action.hotkey; end
		if action.disabled then
			text = text .. ", unavailable" .. ( action.reason ~= "" and ( ": " .. action.reason ) or "" );
		end
		table.insert( items, {
			key = action.tag .. "|" .. action.name, text = text, detail = action.detail,
			choosable = not action.disabled, reason = ( action.reason ~= "" ) and action.reason or "Not available",
			action = action } );
	end
	return items;
end

local m_menu:table;

local function CloseMenu( speak:boolean )
	m_menuOpen = false;
	m_menu.Reset();
	if speak then OutputMessageToScreenReader( "Closed" ); end
end

local function RunMenuItem( item:table )
	local unit:table = UI.GetHeadSelectedUnit();
	if unit == nil then return; end
	CloseMenu( false );
	local modeBefore:number = UI.GetInterfaceMode();
	LuaEvents.SRA_RunUnitAction( item.action.id, unit:GetID() );
	-- Fortify, sleep ... speak their result from the game's UnitOperationStarted event (so the hotkeys are covered too);
	-- target modes, found city, building and the like announce themselves. Anything else: say what was chosen.
	if UI.GetInterfaceMode() == modeBefore and not RESULT_SILENT[ item.action.typeName ]
			and OPERATION_RESULTS[ item.action.typeName ] == nil then
		SayResult( item.action.name );
	end
end

local function ToggleUnitMenu()
	if not IsLocalPlayerActive() then return; end
	if m_menuOpen then
		CloseMenu( true );
		return;
	end
	local unit:table = UI.GetHeadSelectedUnit();
	if unit == nil then
		if UI.GetHeadSelectedCity() ~= nil then
			OutputMessageToScreenReader( "A city is selected. Select a unit for its actions" );
		else
			OutputMessageToScreenReader( "No unit selected" );
		end
		return;
	end
	if unit:GetOwner() ~= Game.GetLocalPlayer() then
		OutputMessageToScreenReader( "Not your unit" );
		return;
	end
	if GetTargetMode() ~= nil then
		OutputMessageToScreenReader( "Choose a tile, or Escape to cancel first" );
		return;
	end
	if #BuildMenuItems() == 0 then
		OutputMessageToScreenReader( Locale.Lookup( unit:GetName() ) .. " has no actions" );
		return;
	end
	m_menuOpen = true;
	m_menu.Open( Locale.Lookup( unit:GetName() ) .. " actions" );
end

m_menu = KeyNavList_Create{
	build		= BuildMenuItems,
	isActive	= function() return m_menuOpen; end,
	onActivate	= RunMenuItem,
	onClose		= function() CloseMenu( true ); end,
};

-- ===========================================================================
--	RESULTS of the player's orders and what happens around the player's units
-- ===========================================================================
local function OnUnitOperationStarted( ownerID:number, unitID:number, operationID:number )
	if ownerID ~= Game.GetLocalPlayer() or not m_ready then return; end
	local row:table = GameInfo.UnitOperations[ operationID ];
	if row == nil then return; end
	local text:string = OPERATION_RESULTS[ row.OperationType ];
	if text ~= nil then SayResult( text ); end
end

local function OnUnitCommandStarted( ownerID:number, unitID:number, commandID:number )
	if ownerID ~= Game.GetLocalPlayer() or not m_ready then return; end
	local row:table = GameInfo.UnitCommands[ commandID ];
	if row == nil then return; end
	local text:string = OPERATION_RESULTS[ row.CommandType ];
	if text ~= nil then SayResult( text ); end
end

local function MovesText( unit:table )
	return FormatNumber( unit:GetMovesRemaining() ) .. " of " .. FormatNumber( unit:GetMaxMoves() ) .. " moves";
end

-- A move ordered with Enter in the move-to mode: arrived, still on the way, or stopped short.
local function OnUnitMoveComplete( playerID:number, unitID:number, x:number, y:number )
	if playerID ~= Game.GetLocalPlayer() then return; end
	local record:table = m_movers[ unitID ];
	if record == nil then return; end
	local unit:table = Players[ playerID ]:GetUnits():FindID( unitID );
	if unit == nil then
		m_movers[ unitID ] = nil;
		return;
	end
	local plot:table = Map.GetPlot( x, y );
	if plot ~= nil and plot:GetIndex() == record.dest then
		m_movers[ unitID ] = nil;
		SayResult( "Arrived, " .. MovesText( unit ) );
		return;
	end
	local queued = UnitManager.GetQueuedDestination( unit );
	if queued == nil then
		m_movers[ unitID ] = nil;
		local destPlot:table = Map.GetPlotByIndex( record.dest );
		local text:string = "Stopped";
		if destPlot ~= nil and plot ~= nil then
			text = text .. ", " .. Plural( Map.GetPlotDistance( x, y, destPlot:GetX(), destPlot:GetY() ), "tile", "tiles" ) .. " from the destination";
		end
		SayResult( text );
		return;
	end
	local path:table = UnitManager.GetMoveToPathEx( unit, queued );
	local text:string = "Moving";
	if path ~= nil and path.turns ~= nil and #path.turns > 0 then
		text = text .. ", " .. Plural( path.turns[ #path.turns ], "turn", "turns" ) .. " left";
	end
	SayResult( text );
end

local function OnUnitDamageChanged( playerID:number, unitID:number, newDamage:number, oldDamage:number )
	if not m_ready or newDamage <= oldDamage then return; end
	local player:table = Players[ playerID ];
	if player == nil then return; end
	local unit:table = player:GetUnits():FindID( unitID );
	if unit == nil then return; end
	if not IsPlotVisibleToLocal( Map.GetPlot( unit:GetX(), unit:GetY() ) ) then return; end
	local name:string = PlotDescription_GetUnitName( unit );
	if playerID == Game.GetLocalPlayer() then name = "Your " .. name; end
	local maxDamage:number = unit:GetMaxDamage();
	if newDamage >= maxDamage then return; end		-- OnUnitKilledInCombat tells it
	OutputMessageToScreenReader( name .. " takes " .. ( newDamage - oldDamage ) .. " damage, " .. ( maxDamage - newDamage ) .. " of " .. maxDamage .. " health", true );
end

-- (killed player, killed unit, killer player, killer unit): told when the local player is on either side.
local function OnUnitKilledInCombat( killedPlayer:number, killedId:number, killerPlayer:number, killerId:number )
	if not m_ready then return; end
	local localPlayer:number = Game.GetLocalPlayer();
	if killedPlayer ~= localPlayer and killerPlayer ~= localPlayer then return; end
	local function NameOf( playerID:number, unitID:number )
		local player:table = Players[ playerID ];
		local unit:table = ( player ~= nil ) and player:GetUnits():FindID( unitID ) or nil;
		if unit ~= nil then return PlotDescription_GetUnitName( unit ); end
		return nil;
	end
	local killed:string = NameOf( killedPlayer, killedId ) or "unit";
	local killer:string = NameOf( killerPlayer, killerId );
	local text:string;
	if killedPlayer == localPlayer then
		text = "Your " .. killed .. " was killed";
	else
		text = killed .. " killed";
	end
	if killer ~= nil then
		if killerPlayer == localPlayer then killer = "your " .. killer; end
		text = text .. " by " .. killer;
	end
	OutputMessageToScreenReader( text, true );
end

local function OnCityAddedToMap( ownerID:number, cityID:number, x:number, y:number )
	if ownerID ~= Game.GetLocalPlayer() or not m_ready then return; end
	local city:table = Players[ ownerID ]:GetCities():FindID( cityID );
	local name:string = ( city ~= nil ) and Locale.Lookup( city:GetName() ) or "City";
	SayResult( name .. " founded" );
end

-- A builder finished an improvement on its own plot.
local function OnImprovementAddedToMap( x:number, y:number, improvementType:number, owner:number )
	if owner ~= Game.GetLocalPlayer() or not m_ready then return; end
	local unit:table = UI.GetHeadSelectedUnit();
	if unit == nil or unit:GetX() ~= x or unit:GetY() ~= y then return; end
	local row:table = GameInfo.Improvements[ improvementType ];
	if row == nil then return; end
	local name:string = Locale.Lookup( row.Name );
	local unitID:number = unit:GetID();
	After( 0.4, function()	-- the charges are counted down a moment later
		local builder:table = Players[ owner ]:GetUnits():FindID( unitID );
		local text:string = name .. " built";
		if builder ~= nil then
			text = text .. ", " .. Plural( builder:GetBuildCharges(), "charge", "charges" ) .. " left";
		else
			text = text .. ", the builder is used up";
		end
		SayResult( text );
	end );
end

local function IsHostile( playerID:number )
	local player:table = Players[ playerID ];
	if player == nil then return false; end
	if player:IsBarbarian() then return true; end
	local diplomacy:table = Players[ Game.GetLocalPlayer() ]:GetDiplomacy();
	return diplomacy ~= nil and diplomacy:IsAtWarWith( playerID );
end

-- "Barbarian Warrior spotted, 2 tiles north of Rome": hostile soldiers that come into view near our cities and units.
local function OnUnitVisibilityChanged( playerID:number, unitID:number, visibility:number )
	local localPlayer:number = Game.GetLocalPlayer();
	if not m_ready or playerID == localPlayer or visibility ~= RevealedState.VISIBLE or not IsHostile( playerID ) then return; end
	local unit:table = Players[ playerID ]:GetUnits():FindID( unitID );
	if unit == nil or ( unit:GetCombat() <= 0 and unit:GetRangedCombat() <= 0 ) then return; end
	local turn:number = Game.GetCurrentGameTurn();
	local key:string = playerID .. ":" .. unitID;
	if m_spotted[ key ] ~= nil and turn - m_spotted[ key ] < 10 then return; end
	if m_spottedTurn ~= turn then m_spottedTurn = turn; m_spottedCount = 0; end
	if m_spottedCount >= 4 then return; end
	local x:number, y:number = unit:GetX(), unit:GetY();
	local bestDistance:number, bestName:string, bestPlot:table = 99, nil, nil;
	for _, city in Players[ localPlayer ]:GetCities():Members() do
		local distance:number = Map.GetPlotDistance( x, y, city:GetX(), city:GetY() );
		if distance < bestDistance then
			bestDistance, bestName, bestPlot = distance, Locale.Lookup( city:GetName() ), Map.GetPlot( city:GetX(), city:GetY() );
		end
	end
	for _, mine in Players[ localPlayer ]:GetUnits():Members() do
		local distance:number = Map.GetPlotDistance( x, y, mine:GetX(), mine:GetY() );
		if distance < bestDistance then
			bestDistance, bestName, bestPlot = distance, "your " .. Locale.Lookup( mine:GetName() ), Map.GetPlot( mine:GetX(), mine:GetY() );
		end
	end
	if bestName == nil or bestDistance > 4 then return; end
	m_spotted[ key ] = turn;
	m_spottedCount = m_spottedCount + 1;
	local relative:string = PlotDescription_GetRelative( bestPlot, Map.GetPlot( x, y ) );
	local text:string = PlotDescription_GetUnitName( unit ) .. " spotted";
	if relative ~= nil then text = text .. ", " .. relative .. " of " .. bestName; else text = text .. " at " .. bestName; end
	OutputMessageToScreenReader( text, true );
end

-- ===========================================================================
--	ENTER (Next Action) must always say something
-- ===========================================================================
local function IsUnitOrdersLabel( text:string )
	return text == Locale.Lookup( "LOC_ACTION_PANEL_NEEDS_ORDERS" ) or text == Locale.Lookup( "LOC_ACTION_PANEL_STACKED_UNIT" )
		or text == Locale.Lookup( "LOC_ACTION_PANEL_UNIT_MOVES_REMAINING" );
end

local function ArmEnterWatch()
	local label:table = ContextPtr:LookUpControl( "/InGame/HUD/ActionPanel/EndTurnText" );
	m_enterLabel = ( label ~= nil ) and label:GetText() or "";
	m_enterWatch = 0.8;
end

-- Enter was pressed, nothing announced a new selection, turn end or mode: the game re-selected the same unit
-- (or none could be selected). Say what is going on.
local function EnterFallback()
	if not IsUnitOrdersLabel( m_enterLabel ) then return; end
	local unit:table = UI.GetHeadSelectedUnit();
	if unit ~= nil then
		SayResult( UnitText( unit ) .. ", needs orders. Tab for its actions" );
	else
		SayResult( Capitalize( CleanTextForSpeech( m_enterLabel ) ) );
	end
end

-- ===========================================================================
--	INPUT HANDLER: runs before WorldInput and ActionPanel (see docs/ingame-plan.md, Input order)
-- ===========================================================================
local function HandleInput( input:table )
	if not IsLocalPlayerActive() then return false; end
	local msg:number = input:GetMessageType();
	if msg ~= KeyEvents.KeyDown and msg ~= KeyEvents.KeyUp then return false; end
	if m_menuOpen then return m_menu.HandleInput( input ); end
	if input:IsShiftDown() or input:IsControlDown() or input:IsAltDown() then return false; end
	local key:number = input:GetKey();
	if GetTargetMode() ~= nil then
		-- Enter and Escape belong to the mode; both KeyDown and KeyUp are consumed, so ActionPanel never sees Enter
		if key == Keys.VK_RETURN or key == Keys.VK_ESCAPE then
			if msg == KeyEvents.KeyUp then
				if key == Keys.VK_RETURN then ConfirmTarget(); else CancelTarget(); end
			end
			return true;
		end
		return false;
	end
	if key == Keys.VK_RETURN and msg == KeyEvents.KeyUp then ArmEnterWatch(); end
	return false;
end

local function OnInput( input:table )
	local ok:boolean, consumed = xpcall( function() return HandleInput( input ); end, KeyNavErrorHandler );
	if not ok then
		print( "InGameAccess input error: " .. tostring( consumed ) );
		return false;
	end
	return consumed == true;
end

local function OnUpdate( deltaTime:number )
	UpdateMouse( deltaTime );
	local i:number = 1;
	while i <= #m_delayed do
		local entry:table = m_delayed[i];
		entry.time = entry.time - deltaTime;
		if entry.time <= 0 then
			table.remove( m_delayed, i );
			local ok:boolean, err = xpcall( entry.fn, KeyNavErrorHandler );
			if not ok then print( "InGameAccess delayed call error: " .. tostring( err ) ); end
		else
			i = i + 1;
		end
	end
	if m_enterWatch >= 0 then
		m_enterWatch = m_enterWatch - deltaTime;
		if m_enterWatch < 0 then
			m_enterWatch = -1;
			EnterFallback();
		end
	end
end

-- ===========================================================================
--	INPUT ACTIONS
-- ===========================================================================
local function OnInputActionTriggered( actionId:number )
	local handler = m_actions[ actionId ];
	if handler ~= nil then handler(); end
end

local function RegisterAction( name:string, handler )
	local id:number = Input.GetActionId( name );
	if id == nil then
		print( "InGameAccess: unknown input action " .. name );
		return;
	end
	m_actions[ id ] = Safe( name, handler );
end

-- ===========================================================================
function Initialize()
	-- Contexts added with AddUserInterfaces start hidden, and a hidden context gets no input actions or updates.
	ContextPtr:SetHide( false );

	RegisterAction( "KeyNavMoveCellLeft",		function() MoveCursor( -1, 0 ); end );
	RegisterAction( "KeyNavMoveCellRight",		function() MoveCursor( 1, 0 ); end );
	RegisterAction( "KeyNavMoveCellUp",			function() MoveCursor( 0, 1 ); end );
	RegisterAction( "KeyNavMoveCellDown",		function() MoveCursor( 0, -1 ); end );
	RegisterAction( "KeyNavPlotDetails",		SpeakPlotDetails );
	RegisterAction( "KeyNavCursorToSelection",	CursorToSelection );
	RegisterAction( "KeyNavWhatsNext",			SpeakWhatsNext );
	RegisterAction( "KeyNavUnitActions",		ToggleUnitMenu );
	RegisterAction( "KeyNavSelectAtCursor",		SelectAtCursor );
	RegisterAction( "KeyNavCycleAllUnits",		CycleAllUnits );
	RegisterAction( "KeyNavScanUnits",			ScanUnits );
	Events.InputActionTriggered.Add( OnInputActionTriggered );

	Events.UnitSelectionChanged.Add( Safe( "UnitSelectionChanged", OnUnitSelectionChanged ) );
	Events.CitySelectionChanged.Add( Safe( "CitySelectionChanged", OnCitySelectionChanged ) );
	Events.LocalPlayerTurnBegin.Add( Safe( "LocalPlayerTurnBegin", AnnounceTurn ) );
	Events.LoadScreenClose.Add( Safe( "LoadScreenClose", OnLoadScreenClose ) );
	Events.LocalPlayerTurnEnd.Add( Safe( "LocalPlayerTurnEnd", OnLocalPlayerTurnEnd ) );

	AddEvent( "InterfaceModeChanged",		OnInterfaceModeChanged );
	AddEvent( "UnitOperationStarted",		OnUnitOperationStarted );
	AddEvent( "UnitCommandStarted",			OnUnitCommandStarted );
	AddEvent( "UnitMoveComplete",			OnUnitMoveComplete );
	AddEvent( "UnitDamageChanged",			OnUnitDamageChanged );
	AddEvent( "CityAddedToMap",				OnCityAddedToMap );
	AddEvent( "ImprovementAddedToMap",		OnImprovementAddedToMap );
	AddEvent( "UnitVisibilityChanged",		OnUnitVisibilityChanged );
	AddEvent( "UnitPromoted",				function( player:number ) if player == Game.GetLocalPlayer() and m_ready then SayResult( "Promoted" ); end end );
	AddEvent( "UnitUpgraded",				function( player:number, unitID:number, unitType:number )
		local row:table = GameInfo.Units[ unitType ];
		if player == Game.GetLocalPlayer() and m_ready and row ~= nil then SayResult( "Upgraded to " .. Locale.Lookup( row.Name ) ); end
	end );
	AddEvent( "UnitKilledInCombat",			OnUnitKilledInCombat );
	LuaEvents.SRA_UnitActions.Add( OnUnitActionsReceived );

	ContextPtr:SetInputHandler( OnInput, true );
	ContextPtr:SetUpdate( Safe( "Update", OnUpdate ) );
end
Initialize();
