-- ===========================================================================
--	HubPins: Control+P (KeyNavMapPin) puts a named map pin on the map cursor tile, the blind player's bookmark.
--	Part of the InGameAccess hub (see docs/features.md, Architecture): included by UI/Additions/InGameAccess.lua.
--	  * a tile without a pin of ours: the name is typed in the hub's hidden EditBox (SRChatBox, shared with the chat) through
--	    KeyNavEditBox; Enter creates the pin through the game's own functions (MapPins.Create = MapPinPopup's OK path);
--	  * a tile with a pin of ours: a list "Rename" / "Delete".
--	  The pins are listed in the places list (J, category "Pins", HubPlaces) and named in the cursor text ("pin: <name>").
--	The data layer and the wording are MapPins.lua (tested offline).
-- ===========================================================================
HubPins = {};

include( "MapPins" );
include( "KeyNavEditBox" );

HubPins.m_pin = nil;		-- the pin the open Rename / Delete list is about: { id, x, y, name }
local m_menu:table;

local function Trim( text:string )
	return ( ( text or "" ):gsub( "^[ \t\r\n\v\f]+", "" ):gsub( "[ \t\r\n\v\f]+$", "" ) );
end

-- "2 tiles south of Rome", else the short plot text
local function TileName( plot:table )
	return HubAnnounce.PositionText( plot ) or PlotDescription_GetShort( plot, {} );
end

-- Shows the shared EditBox with the starting text and begins the edit a moment later (a control that was hidden takes the focus a frame later).
local function Edit( initial:string, opts:table )
	local box:table = Controls.SRChatBox;
	if box == nil then
		OutputMessageToScreenReader( "Text input is not available" );
		return;
	end
	box:ClearString();
	if initial ~= nil and initial ~= "" then box:SetText( initial ); end
	box:SetHide( false );
	opts.onEnd = function() box:ClearString(); box:SetHide( true ); end;
	HubCore.After( 0.15, function() KeyNavEditBox_Begin( box, opts ); end );
end

-- A new pin at (x, y). An empty name is valid ("Pin placed").
function HubPins.StartNew( x:number, y:number )
	local plot:table = Map.GetPlot( x, y );
	if plot == nil then
		OutputMessageToScreenReader( "Edge of the map" );
		return;
	end
	local made:boolean = false;
	local function Place( text:string )
		local name:string = Trim( text );
		made = MapPins.Create( x, y, name );
		return name;
	end
	Edit( "", {
		label = "Name for the pin, " .. TileName( plot ),
		commit = Place,
		doneText = function( text:string )
			local name:string = Trim( text );
			if not made then return "The pin could not be placed"; end
			return name ~= "" and ( "Pin placed: " .. name ) or "Pin placed";
		end,
		-- Enter on an empty name
		onUnchangedEnter = function()
			Place( "" );
			OutputMessageToScreenReader( made and "Pin placed" or "The pin could not be placed" );
		end,
		cancelText = "No pin placed",
	} );
end

local function StartRename( pin:table )
	Edit( pin.name or "", {
		label = "New name for the pin, " .. TileName( Map.GetPlot( pin.x, pin.y ) ),
		commit = function( text:string ) pin.renamed = MapPins.Rename( pin.id, Trim( text ) ); end,
		doneText = function( text:string )
			if not pin.renamed then return "The pin could not be renamed"; end
			local name:string = Trim( text );
			return name ~= "" and ( "Pin renamed to " .. name ) or "Pin name cleared";
		end,
		unchangedText = "Name kept",
		cancelText = "Rename cancelled",
	} );
end

local function Remove( pin:table )
	OutputMessageToScreenReader( MapPins.Delete( pin.id ) and "Pin removed" or "The pin could not be removed" );
end

-- The list on a tile that already has a pin of ours.
local function MenuItems()
	local pin:table = HubPins.m_pin;
	local what:string = ( pin ~= nil ) and MapPins.DisplayName( pin.name ) or "pin";
	return {
		{ key = "rename", text = "Rename", detail = "Type a new name for " .. what .. ". Enter confirms, Escape cancels" },
		{ key = "delete", text = "Delete", detail = "Remove " .. what },
	};
end

m_menu = KeyNavList_Create{
	build		= MenuItems,
	isActive	= function() return HubCore.IsModeOpen( "pin" ); end,
	onActivate	= function( item )
		local pin:table = HubPins.m_pin;
		HubCore.CloseMode( false, false );
		if pin == nil then return; end
		if item.key == "rename" then StartRename( pin ); else Remove( pin ); end
	end,
	onClose		= function() HubCore.CloseMode( true, false ); end,
	noDetailHint = true,
};

-- Control+P
function HubPins.Key()
	if HubCore.IsModeOpen( "pin" ) then HubCore.CloseMode( true, false ); return; end
	if not HubTargets.CanOpenMode() then return; end
	local x:number, y:number = HubCursor.GetCursor();
	if Map.GetPlot( x, y ) == nil then
		OutputMessageToScreenReader( "Edge of the map" );
		return;
	end
	local pin:table = MapPins.OwnAt( x, y );
	if pin == nil then
		HubPins.StartNew( x, y );
		return;
	end
	HubPins.m_pin = pin;
	HubCore.OpenMode( "pin", m_menu, "Pin " .. MapPins.DisplayName( pin.name ) .. ", " .. TileName( Map.GetPlot( x, y ) ) );
end
