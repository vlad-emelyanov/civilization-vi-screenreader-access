-- ===========================================================================
--	InGameAccess: screen reader hub for the in-game UI (see docs/ingame-plan.md).
--	A context without visuals, added to InGame (UI/Additions/InGameAccess.xml). It owns
--	  - the map cursor (Shift+Arrows) and its plot announcements,
--	  - the in-game hotkeys (I plot details, . cursor to selection, N what is next),
--	  - event announcements: unit/city selected, new turn, end of turn.
--	Input order (verified, see docs/ingame-plan.md): this context's input handler runs before WorldInput and
--	ActionPanel; a key it consumes (KeyDown and KeyUp) also never becomes an input action.
-- ===========================================================================

include( "ScreenReader" );
include( "KeyboardNavigation" );
include( "PlotDescription" );

-- ===========================================================================
--	MEMBERS
-- ===========================================================================
local MOUSE_MOVE_DELAY		:number = 0.8;		-- seconds to let the camera settle before the real mouse follows the cursor

local m_cursorX				:number = nil;		-- map cursor (plot coordinates)
local m_cursorY				:number = nil;
local m_mouseTimer			:number = -1;		-- >= 0: seconds until the mouse is moved onto the cursor plot
local m_actions				:table = {};		-- actionId -> handler
local m_lastAnnouncedTurn	:number = -1;

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

-- ===========================================================================
--	MAP CURSOR
-- ===========================================================================

-- Keeps the real mouse on the cursor plot (for sighted helpers and for the few things that still click),
-- once the camera has had time to arrive. The plot tooltip must not read the plot again: it is already announced.
local function QueueMouseMove( plot:table )
	LuaEvents.SRA_CursorPlot( plot:GetIndex() );
	m_mouseTimer = MOUSE_MOVE_DELAY;
end

local function UpdateMouse( deltaTime:number )
	if m_mouseTimer < 0 then return; end
	m_mouseTimer = m_mouseTimer - deltaTime;
	if m_mouseTimer >= 0 then return; end
	m_mouseTimer = -1;
	if m_cursorX == nil then return; end
	local plot:table = Map.GetPlot( m_cursorX, m_cursorY );
	if plot == nil then return; end
	-- The camera put the cursor plot at the centre of the screen (see SetCursor), so that is where the mouse goes.
	local screenWidth:number, screenHeight:number = UIManager:GetScreenSizeVal();
	KeyNavMoveMouseToScreen( math.floor( screenWidth / 2 ), math.floor( screenHeight / 2 ) );
end

local function GetCursor()
	if m_cursorX == nil then
		local plot:table = GetSelectionPlot();
		local capital:table = nil;
		if IsLocalPlayerActive() then capital = Players[ Game.GetLocalPlayer() ]:GetCities():GetCapitalCity(); end
		if plot ~= nil then
			m_cursorX, m_cursorY = plot:GetX(), plot:GetY();
		elseif capital ~= nil then
			m_cursorX, m_cursorY = capital:GetX(), capital:GetY();
		else
			m_cursorX, m_cursorY = UI.GetPlotCoordFromNormalizedScreenPos( 0.5, 0.5 );	-- what the camera is looking at
		end
	end
	return m_cursorX, m_cursorY;
end

local function DescribeCursorPlot( plot:table )
	local selectionPlot:table, unit:table = GetSelectionPlot();
	local options:table = {};
	local localPlayer:number = Game.GetLocalPlayer();
	if unit ~= nil and unit:GetOwner() == localPlayer then options.excludeUnitId = unit:GetID(); end
	local text:string = PlotDescription_GetShort( plot, options );
	local relative:string = PlotDescription_GetRelative( selectionPlot, plot );
	if relative ~= nil then text = text .. ". " .. relative; end
	return text;
end

-- Puts the cursor on (x, y), moves the camera there and optionally speaks the plot.
local function SetCursor( x:number, y:number, speak:boolean, interrupt:boolean )
	local plot:table = Map.GetPlot( x, y );
	if plot == nil then return; end
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
	if playerID ~= Game.GetLocalPlayer() or not isSelected then return; end
	local unit:table = Players[playerID]:GetUnits():FindID( unitID );
	if unit == nil then return; end
	local plot:table = Map.GetPlot( unit:GetX(), unit:GetY() );
	if plot == nil then return; end
	SetCursor( plot:GetX(), plot:GetY(), false );
	local text:string = UnitText( unit ) .. ". " .. PlotDescription_GetShort( plot, { excludeUnitId = unit:GetID() } );
	OutputMessageToScreenReader( text );
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
	if owner ~= Game.GetLocalPlayer() or not isSelected then return; end
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
	if turn == m_lastAnnouncedTurn then return; end
	m_lastAnnouncedTurn = turn;
	OutputMessageToScreenReader( "Turn " .. turn .. ", " .. Calendar.MakeYearStr( turn ), true );
end

local function OnLocalPlayerTurnEnd()
	OutputMessageToScreenReader( "Turn ended", true );
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
	Events.InputActionTriggered.Add( OnInputActionTriggered );

	Events.UnitSelectionChanged.Add( Safe( "UnitSelectionChanged", OnUnitSelectionChanged ) );
	Events.CitySelectionChanged.Add( Safe( "CitySelectionChanged", OnCitySelectionChanged ) );
	Events.LocalPlayerTurnBegin.Add( Safe( "LocalPlayerTurnBegin", AnnounceTurn ) );
	Events.LoadScreenClose.Add( Safe( "LoadScreenClose", AnnounceTurn ) );
	Events.LocalPlayerTurnEnd.Add( Safe( "LocalPlayerTurnEnd", OnLocalPlayerTurnEnd ) );

	ContextPtr:SetUpdate( Safe( "Update", UpdateMouse ) );
end
Initialize();
