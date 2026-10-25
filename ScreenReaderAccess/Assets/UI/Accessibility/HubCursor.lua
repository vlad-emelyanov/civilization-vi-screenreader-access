-- ===========================================================================
--	HubCursor: map cursor, plot speech, selecting at the cursor.
--	Part of the InGameAccess hub (see docs/ingame-plan.md, Architecture): included by
--	UI/Additions/InGameAccess.lua. State and functions other hub modules use are fields of HubCursor.
-- ===========================================================================
HubCursor = {};

local MOUSE_MOVE_DELAY		:number = 0.8;		-- seconds to let the camera settle before the real mouse follows the cursor
local m_cursorX				:number = nil;		-- map cursor (plot coordinates)
local m_cursorY				:number = nil;
local m_mouseTimer			:number = -1;		-- >= 0: seconds until the mouse is moved onto the cursor plot
local m_scanOrigin			:number = nil;		-- plot the X scan started from
local m_scanMode			:number = nil;		-- interface mode of the last scan: a new mode (an attack mode just opened) starts again at the nearest

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
function HubCursor.FindPlotScreenPos( x:number, y:number )
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

function HubCursor.UpdateMouse( deltaTime:number )
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
	local px:number, py:number = HubCursor.FindPlotScreenPos( m_cursorX, m_cursorY );
	if px ~= nil then KeyNavMoveMouseToScreen( px, py ); end
end

function HubCursor.ResetCursor()
	m_cursorX, m_cursorY = nil, nil;
	m_mouseTimer = -1;
	HubCore.m_cursorPlayer = Game.GetLocalPlayer();
	HubCore.CloseMode( false, true );		-- another player (hotseat) or a new game: a list of the previous one is stale
end

function HubCursor.GetCursor()
	if HubCore.m_cursorPlayer ~= Game.GetLocalPlayer() then HubCursor.ResetCursor(); end	-- hotseat: the next player starts at their own units
	if m_cursorX == nil then
		local plot:table = HubCore.GetSelectionPlot();
		local capital:table = nil;
		if HubCore.IsLocalPlayerActive() then capital = Players[ Game.GetLocalPlayer() ]:GetCities():GetCapitalCity(); end
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
-- jump: the cursor was sent here (a list, a scan, a notification), not stepped: the position from the nearest own city follows,
-- the frame of reference a single Shift+Arrow step does not need.
local function DescribeCursorPlot( plot:table, jump:boolean )
	local selectionPlot:table, unit:table = HubCore.GetSelectionPlot();
	local options:table = {};
	local localPlayer:number = Game.GetLocalPlayer();
	if unit ~= nil and unit:GetOwner() == localPlayer then options.excludeUnitId = unit:GetID(); end
	local text:string = PlotDescription_GetShort( plot, options );
	local mode:number = HubTargets.GetTargetMode();
	local placement:string = HubCore.PlacementPlotText( plot );
	if placement ~= nil then
		text = placement .. ". " .. text;
	elseif mode ~= nil then
		local info:string = HubTargets.TargetInfo( mode, plot, unit );
		if info ~= nil then text = info .. ". " .. text; end
		local build:string = ( unit ~= nil and unit:GetOwner() == localPlayer ) and HubCore.BuilderBuildText( unit, plot ) or nil;		-- builders walking to a tile
		if build ~= nil then text = text .. ", " .. build; end
	elseif HubCore.IsSettler( unit ) then
		local ok:boolean, reason = SettleScan_CanFound( unit, plot );
		if ok then
			text = text .. ", can settle";
			local ring1:table = SettleScan_Ring1Resources( plot );		-- what the city would own at once
			if #ring1 > 0 then text = text .. ", ring 1: " .. table.concat( ring1, ", " ); end
		else
			text = text .. ", " .. SettleScan_CannotText( reason );
		end
	elseif unit ~= nil then
		local build:string = HubCore.BuilderBuildText( unit, plot );
		if build ~= nil then text = text .. ", " .. build; end
	end
	text = LensText_Prefix( text, plot, HubCore.IsSettler( unit ) );		-- a map lens is on: its value first
	local relative:string = PlotDescription_GetRelative( selectionPlot, plot );
	if relative ~= nil then text = text .. ". " .. relative; end
	if jump and mode == nil then
		local position:string = HubAnnounce.PositionText( plot );
		if position ~= nil and string.sub( position, 1, 3 ) ~= "in " then text = text .. ". " .. position; end		-- "in Rome" is the plot description already
	end
	return text;
end

-- Puts the cursor on (x, y), moves the camera there and optionally speaks the plot.
-- noMouse: the real mouse does not follow (browsing a list of candidates: the mouse must not sit on every one of them).
-- jump: the plot is announced with its position from the nearest own city ("7 tiles north-west of Rome").
function HubCursor.SetCursor( x:number, y:number, speak:boolean, interrupt:boolean, noMouse:boolean, jump:boolean )
	local plot:table = Map.GetPlot( x, y );
	if plot == nil then return; end
	HubCore.m_cursorPlayer = Game.GetLocalPlayer();
	m_cursorX, m_cursorY = x, y;
	LuaEvents.SRA_CursorMoved( x, y );		-- UnitPanel: the keyboard cursor and the hovered attack preview may agree
	if HubCore.m_placeConfirm ~= nil and HubCore.m_placeConfirm ~= plot:GetIndex() then HubCore.m_placeConfirm = nil; end		-- moved away from the tile to confirm
	UI.LookAtPlotScreenPosition( x, y, 0.5, 0.5 );
	if noMouse then
		m_mouseTimer = -1;
	else
		QueueMouseMove( plot );
	end
	if speak then
		OutputMessageToScreenReader( DescribeCursorPlot( plot, jump ), not interrupt );
	end
end

-- Shift+Arrows. Left/Right step along the row; Up/Down step to the next row north/south (alternately north-west
-- and north-east, so that two steps go straight north, as on the screen).
function HubCursor.MoveCursor( dx:number, dy:number )
	if not HubCore.IsLocalPlayerActive() then return; end
	local x:number, y:number = HubCursor.GetCursor();
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
	HubCursor.SetCursor( x, y, true, true );
end

-- Period: the cursor goes to the selected unit or city and says what is there.
function HubCursor.CursorToSelection()
	if not HubCore.IsLocalPlayerActive() then return; end
	local plot:table, unit:table = HubCore.GetSelectionPlot();
	if plot == nil then
		OutputMessageToScreenReader( "Nothing selected" );
		return;
	end
	HubCursor.SetCursor( plot:GetX(), plot:GetY(), false );
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
function HubCursor.CycleAllUnits()
	if not HubCore.IsLocalPlayerActive() then return; end
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
function HubCursor.SelectAtCursor()
	if not HubCore.IsLocalPlayerActive() then return; end
	local x:number, y:number = HubCursor.GetCursor();
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

-- Order of the X scan. Rank 0: listed or attackable without declaring war; 1: hostile (at war, barbarians); 2: would
-- declare war (entry.war); 3: the rest. Within a rank the nearest first, then the plot index (stable).
function HubCursor.ScanEntryRank( entry:table )
	if entry.valid == true then return 0; end
	if entry.war == true then return 2; end
	if entry.hostile then return 1; end
	return 3;
end

function HubCursor.ScanEntryBefore( a:table, b:table )
	local rankA:number, rankB:number = HubCursor.ScanEntryRank( a ), HubCursor.ScanEntryRank( b );
	if rankA ~= rankB then return rankA < rankB; end
	if a.distance ~= b.distance then return a.distance < b.distance; end
	return a.index < b.index;
end

-- W / X in an attack mode with no foreign unit within 10 tiles: name the nearest hostile unit far away, if any.
function HubCursor.NoEnemyText( unitName:string, enemyName:string, relative:string )
	if enemyName == nil then return "No enemy in view"; end
	return "No enemy in range of the " .. unitName .. ". Nearest enemy: " .. enemyName .. ( relative ~= nil and ( ", " .. relative ) or "" );
end

-- X: the cursor jumps to the nearest plot with foreign units in view (hostile ones first); pressed again, to the
-- next one. One stop per plot (the plot description lists the stack). Finds targets for the attack modes, and
-- threats in general. Said like a cursor move, so target modes add their info.
local m_scanKey:string = nil;
function HubCursor.ScanUnits( interrupt:boolean )
	if not HubCore.IsLocalPlayerActive() then return; end
	if interrupt == nil then interrupt = true; end
	local localPlayer:number = Game.GetLocalPlayer();
	local originPlot:table = HubCore.GetSelectionPlot();
	if originPlot == nil then
		local x:number, y:number = HubCursor.GetCursor();
		originPlot = Map.GetPlot( x, y );
	end
	-- a scan that starts from somewhere else starts again at the nearest plot
	local scanMode:number = UI.GetInterfaceMode();
	if m_scanOrigin ~= originPlot:GetIndex() or m_scanMode ~= scanMode then
		m_scanMode = scanMode;
		m_scanOrigin = originPlot:GetIndex();
		m_scanKey = nil;
	end
	local byPlot:table = {};
	local found:table = {};
	-- a target mode that lists its valid plots (form corps / army: the partner units; deploy, rebase, airlift ...): X walks those
	local targetMode:number = HubTargets.GetTargetMode();
	local listed:table = ( targetMode ~= nil ) and HubTargets.ModeTargetPlots( targetMode, UI.GetHeadSelectedUnit() ) or nil;
	if listed ~= nil then
		for plotIndex, _ in pairs( listed ) do
			local plot:table = Map.GetPlotByIndex( plotIndex );
			if plot ~= nil then
				table.insert( found, { key = tostring( plotIndex ), index = plotIndex, x = plot:GetX(), y = plot:GetY(),
					distance = Map.GetPlotDistance( originPlot:GetX(), originPlot:GetY(), plot:GetX(), plot:GetY() ), hostile = false, valid = true } );
			end
		end
		if #found == 0 then
			OutputMessageToScreenReader( "No valid target for this" );
			return;
		end
	end
	for playerID = 0, 63 do
		if listed ~= nil then break; end
		local player:table = Players[ playerID ];
		if playerID ~= localPlayer and player ~= nil and player:IsAlive() then
			local hostile:boolean = HubCore.IsHostile( playerID );
			for _, unit in player:GetUnits():Members() do
				local distance:number = Map.GetPlotDistance( originPlot:GetX(), originPlot:GetY(), unit:GetX(), unit:GetY() );
				if distance <= 10 and PlotDescription_IsUnitVisible( unit ) then
					local plotIndex:number = Map.GetPlot( unit:GetX(), unit:GetY() ):GetIndex();
					local entry:table = byPlot[ plotIndex ];
					if entry == nil then
						entry = { key = tostring( plotIndex ), index = plotIndex, x = unit:GetX(), y = unit:GetY(), distance = distance, hostile = false };
						byPlot[ plotIndex ] = entry;
						table.insert( found, entry );
					end
					if hostile then entry.hostile = true; end
				end
			end
		end
	end
	local attackMode:boolean = listed == nil and HubTargets.GetTargetMode() ~= nil;
	if #found == 0 then
		local unit:table = ( attackMode and HubTargets.IsAttackMode( HubTargets.GetTargetMode() ) ) and UI.GetHeadSelectedUnit() or nil;
		if unit ~= nil then
			local enemyName:string, relative:string = PlotDescription_NearestHostile( unit, 30 );
			OutputMessageToScreenReader( HubCursor.NoEnemyText( Locale.Lookup( unit:GetName() ), enemyName, relative ) );
		else
			OutputMessageToScreenReader( "No foreign units in view" );
		end
		return;
	end
	-- in an attack mode: targets attackable without a war first, then hostile ones, then those that would declare war
	if attackMode then
		local unit:table = UI.GetHeadSelectedUnit();
		for _, entry in ipairs( found ) do
			local plot:table = Map.GetPlot( entry.x, entry.y );
			entry.valid = HubTargets.IsAttackTarget( plot );
			entry.war = ( not entry.hostile ) and unit ~= nil and HubTargets.WarTargets( unit, plot ) ~= nil;
		end
	end
	table.sort( found, HubCursor.ScanEntryBefore );
	local next:number = 1;
	for i, entry in ipairs( found ) do
		if entry.key == m_scanKey then next = i % #found + 1; end
	end
	m_scanKey = found[ next ].key;
	HubCursor.SetCursor( found[ next ].x, found[ next ].y, true, interrupt, false, true );
	if next == #found and #found > 1 then
		OutputMessageToScreenReader( "Last target, X wraps to the first", true );
	end
end

-- I: details of the cursor plot.
function HubCursor.SpeakPlotDetails()
	if not HubCore.IsLocalPlayerActive() then return; end
	local x:number, y:number = HubCursor.GetCursor();
	local plot:table = Map.GetPlot( x, y );
	local selectionPlot:table, unit:table = HubCore.GetSelectionPlot();
	local options:table = {};
	if unit ~= nil then options.excludeUnitId = unit:GetID(); end
	local text:string = PlotDescription_GetDetailed( plot, options );
	local relative:string = PlotDescription_GetRelative( selectionPlot, plot );
	if relative ~= nil then text = text .. ". " .. relative; end
	local build:string = ( unit ~= nil and HubTargets.GetTargetMode() == nil ) and HubCore.BuilderBuildText( unit, plot ) or nil;
	if build ~= nil then text = text .. ". " .. build; end
	OutputMessageToScreenReader( text );
end
