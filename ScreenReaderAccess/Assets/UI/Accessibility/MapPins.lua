-- ===========================================================================
--	MapPins: the game's map pins as a blind player's bookmarks (Control+P, category "Pins" of the places list; docs/features.md).
--	The data layer over the same functions the game's own MapPinPopup / MapPinManager / MapPinListPanel use:
--	PlayerConfigurations[player]:GetMapPins() / GetMapPin( x, y ) (creates the pin when the plot has none: the popup opens on
--	an empty plot this way) / GetMapPinID( id ) / DeleteMapPin( id ), pin:GetName / SetName / GetHexX / GetHexY / GetID / IsVisible( player ),
--	Network.BroadcastPlayerInfo() after every change. Everything is guarded: a missing function says "not available", never an error.
--	Loaded by the hub (HubPins) and used by PlotDescription_GetShort (when this module is loaded): no front-end screen includes it.
-- ===========================================================================
MapPins = {};

local function LocalID()
	return Game.GetLocalPlayer();
end

-- "Unnamed pin" for a pin without a name
function MapPins.DisplayName( name:string )
	if name == nil or name == "" then return "Unnamed pin"; end
	return name;
end

-- Plot text (cursor): "pin: Iron here" / "pin" for an unnamed one; several: joined with ", "
function MapPins.PlotPhrase( names:table )
	if names == nil or #names == 0 then return nil; end
	local parts:table = {};
	for _, name in ipairs( names ) do
		table.insert( parts, ( name == nil or name == "" ) and "pin" or ( "pin: " .. name ) );
	end
	return table.concat( parts, ", " );
end

-- The places list item: "Iron here, 5 tiles south-east of Rome" (a teammate's pin: "..., placed by Anna")
function MapPins.ItemText( name:string, position:string, placedBy:string )
	local text:string = MapPins.DisplayName( name );
	if position ~= nil and position ~= "" then text = text .. ", " .. position; end
	if placedBy ~= nil and placedBy ~= "" then text = text .. ", placed by " .. placedBy; end
	return text;
end

-- Every pin the local player sees: own ones, and the pins of other human players that are visible to us. { owner, id, x, y, name, mine }
function MapPins.All()
	local list:table = {};
	local ok:boolean = pcall( function()
		local me:number = LocalID();
		for _, player in ipairs( Game.GetPlayers{ Alive = true, Human = true } ) do
			local owner:number = player:GetID();
			local cfg:table = PlayerConfigurations[ owner ];
			local pins:table = ( cfg ~= nil ) and cfg:GetMapPins() or nil;
			for _, pin in pairs( pins or {} ) do
				if owner == me or pin:IsVisible( me ) then
					table.insert( list, { owner = owner, id = pin:GetID(), x = pin:GetHexX(), y = pin:GetHexY(), name = pin:GetName(), mine = ( owner == me ) } );
				end
			end
		end
	end );
	if not ok then return {}; end
	table.sort( list, function( a, b )
		if a.owner ~= b.owner then return a.owner < b.owner; end
		return a.id < b.id;
	end );
	return list;
end

-- The pins on one plot (all visible ones), nearest the order of All()
function MapPins.AtPlot( x:number, y:number )
	local found:table = {};
	for _, pin in ipairs( MapPins.All() ) do
		if pin.x == x and pin.y == y then table.insert( found, pin ); end
	end
	return found;
end

-- The local player's own pin on a plot, or nil
function MapPins.OwnAt( x:number, y:number )
	for _, pin in ipairs( MapPins.AtPlot( x, y ) ) do
		if pin.mine then return pin; end
	end
	return nil;
end

-- For the plot text: the names of the visible pins on the plot ("" for unnamed ones)
function MapPins.NamesAt( x:number, y:number )
	local names:table = {};
	for _, pin in ipairs( MapPins.AtPlot( x, y ) ) do table.insert( names, pin.name or "" ); end
	return names;
end

local function Broadcast( sound:string )
	if Network ~= nil and Network.BroadcastPlayerInfo ~= nil then Network.BroadcastPlayerInfo(); end
	if UI ~= nil and UI.PlaySound ~= nil then UI.PlaySound( sound ); end
end

-- MapPinPopup's OK path: GetMapPin( x, y ) makes the pin, SetName, then BroadcastPlayerInfo. A new pin is private to its owner like the
-- popup's default (the visibility pulldown starts on "self only"). Returns true when the pin exists afterwards.
function MapPins.Create( x:number, y:number, name:string )
	local ok:boolean, made = pcall( function()
		local cfg:table = PlayerConfigurations[ LocalID() ];
		local pin:table = cfg:GetMapPin( x, y );
		if pin == nil then return false; end
		pin:SetName( name or "" );
		if GameConfiguration ~= nil and GameConfiguration.IsAnyMultiplayer() then pin:SetVisibility( LocalID() ); end
		Broadcast( "Map_Pin_Add" );
		return true;
	end );
	return ok and made == true;
end

-- MapPinPopup's OK path for an existing pin
function MapPins.Rename( id:number, name:string )
	local ok:boolean, done = pcall( function()
		local pin:table = PlayerConfigurations[ LocalID() ]:GetMapPinID( id );
		if pin == nil then return false; end
		pin:SetName( name or "" );
		Broadcast( "Map_Pin_Add" );
		return true;
	end );
	return ok and done == true;
end

-- MapPinPopup's Delete path
function MapPins.Delete( id:number )
	local ok:boolean, done = pcall( function()
		local cfg:table = PlayerConfigurations[ LocalID() ];
		if cfg:GetMapPinID( id ) == nil then return false; end
		cfg:DeleteMapPin( id );
		Broadcast( "Map_Pin_Remove" );
		return true;
	end );
	return ok and done == true;
end
