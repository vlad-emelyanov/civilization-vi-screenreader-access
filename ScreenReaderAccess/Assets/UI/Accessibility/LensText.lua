-- ===========================================================================
--	LensText: speech for the map lenses (number keys 1-9, 0). The game only shows them: colours and a key panel.
--
--	LensText_Actions                          input action name -> { id, name } (id = the lens, name = the spoken name)
--	LensText_Toggled( action, modal )         -> text | nil. Call a moment after the hotkey, modal = the interface mode is
--	                                             VIEW_MODAL_LENS. "Settler lens on. <legend>" / "Settler lens off"; nil when
--	                                             nothing happened (a key the game ignored). Remembers the lens that is on.
--	LensText_ActiveLens()                     -> lens id | nil: the lens this module saw switched on, while the game is in
--	                                             lens mode (a lens turned on with the mouse is not known).
--	LensText_Legend( lens )                   -> one sentence: what the colours mean (the game's key panel, ModalLensPanel.lua)
--	LensText_PlotText( lens, plot, settlerSelected ) -> the lens value of one plot ("appeal: Breathtaking 4") | nil
--	LensText_Prefix( text, plot, settlerSelected )   -> text with the lens value in front when a lens is on
--
--	Values are spoken for Appeal, Religion, Continent, Settler, Loyalty (own cities) and Government. Political, Tourism,
--	Empire and Power colour things the plot text already says (owner) or whose per-tile value is unclear: they only get
--	the on/off line and the legend.
-- ===========================================================================

include( "PlotDescription" );

LensText_Actions = {
	LensReligion	= { id = "Religion",	name = "Religion" },
	LensContinent	= { id = "Continent",	name = "Continent" },
	LensAppeal		= { id = "Appeal",		name = "Appeal" },
	LensSettler		= { id = "Settler",		name = "Settler" },
	LensGovernment	= { id = "Government",	name = "Government" },
	LensPolitical	= { id = "Political",	name = "Political" },
	LensTourism		= { id = "Tourism",		name = "Tourism" },
	LensLoyalty		= { id = "Loyalty",		name = "Loyalty" },
	LensEmpire		= { id = "Empire",		name = "Empire" },
	LensPower		= { id = "Power",		name = "Power" },
};

local m_active:string = nil;		-- lens id
local m_names:table = {};
for _, lens in pairs( LensText_Actions ) do m_names[ lens.id ] = lens.name; end

-- Lenses that speak a value per plot (their legend ends with the hint)
local m_perPlot:table = { Appeal = true, Religion = true, Continent = true, Settler = true, Loyalty = true, Government = true };

-- Game text without icons and line breaks
local function _Clean( text:string )
	text = tostring( text or "" );
	text = string.gsub( text, "%[ICON_[%w_]+%]", "" );
	text = string.gsub( text, "%[NEWLINE%]", ", " );
	text = string.gsub( text, "%[[%w_]+%]", "" );
	text = string.gsub( text, "%s+", " " );
	return ( string.gsub( text, "^%s*(.-)%s*$", "%1" ) );
end

local function _Names( keys:table )
	local out:table = {};
	for _, key in ipairs( keys ) do
		local text:string = _Clean( Locale.Lookup( key ) );
		if text ~= "" then table.insert( out, text ); end
	end
	return out;
end

local function _LocalPlayer()
	local id:number = Game.GetLocalPlayer();
	if id == nil or id < 0 then return nil; end
	return id;
end

-- ===========================================================================
--	Legends
-- ===========================================================================
local function _ReligionNames()
	local names:table = {};
	local ok:boolean, err = pcall( function()
		local religion:table = Game.GetReligion();
		for _, info in ipairs( religion:GetReligions() ) do
			local row:table = GameInfo.Religions[ info.Religion ];
			if row ~= nil and row.Pantheon == false and religion:HasBeenFounded( info.Religion ) then
				table.insert( names, _Clean( Locale.Lookup( religion:GetName( info.Religion ) ) ) );
			end
		end
	end );
	if not ok then print( "LensText religion legend: " .. tostring( err ) ); end
	return names;
end

local function _GovernmentNames()
	local names:table, seen:table = {}, {};
	local ok:boolean, err = pcall( function()
		local me:number = _LocalPlayer();
		local diplomacy:table = Players[ me ]:GetDiplomacy();
		for _, player in ipairs( Game.GetPlayers() ) do
			if player:GetID() == me or diplomacy:HasMet( player:GetID() ) then
				local index:number = player:GetCulture():GetCurrentGovernment();
				local row:table = ( index ~= nil and index >= 0 ) and GameInfo.Governments[ index ] or nil;
				if row ~= nil and not seen[ index ] then
					seen[ index ] = true;
					table.insert( names, _Clean( Locale.Lookup( row.Name ) ) );
				end
			end
		end
	end );
	if not ok then print( "LensText government legend: " .. tostring( err ) ); end
	return names;
end

local function _ContinentNames()
	local names:table = {};
	local ok:boolean, err = pcall( function()
		for row in GameInfo.Continents() do
			local plots:table = Map.GetVisibleContinentPlots( row.Index );
			if plots ~= nil and #plots > 0 then table.insert( names, _Clean( Locale.Lookup( row.Description ) ) ); end
		end
	end );
	if not ok then print( "LensText continent legend: " .. tostring( err ) ); end
	return names;
end

function LensText_Legend( lens:string )
	local function List( names:table, empty:string )
		if #names == 0 then return empty; end
		return table.concat( names, ", " );
	end
	if lens == "Appeal" then
		return "Shows appeal: " .. List( _Names( { "LOC_TOOLTIP_APPEAL_BREATHTAKING", "LOC_TOOLTIP_APPEAL_CHARMING", "LOC_TOOLTIP_APPEAL_AVERAGE",
			"LOC_TOOLTIP_APPEAL_UNINVITING", "LOC_TOOLTIP_APPEAL_DISGUSTING" } ), "" ) .. ".";
	elseif lens == "Settler" then
		return "Shows where cities can be founded: " .. List( _Names( { "LOC_HUD_UNIT_PANEL_TOOLTIP_FRESH_WATER", "LOC_HUD_UNIT_PANEL_TOOLTIP_COASTAL_WATER",
			"LOC_HUD_UNIT_PANEL_TOOLTIP_NO_WATER", "LOC_HUD_UNIT_PANEL_TOOLTIP_TOO_CLOSE_TO_CITY" } ), "" ) .. ".";
	elseif lens == "Religion" then
		local names:table = _ReligionNames();
		if #names == 0 then return "Colours cities by majority religion. No religion founded yet."; end
		return "Colours cities by majority religion: " .. List( names, "" ) .. ".";
	elseif lens == "Government" then
		return "Colours civilizations by government: " .. List( _GovernmentNames(), "none known" ) .. ".";
	elseif lens == "Continent" then
		local names:table = _ContinentNames();
		if #names == 0 then return "Colours each continent."; end
		return "Colours continents: " .. List( names, "" ) .. ".";
	elseif lens == "Political" then
		return "Colours territory by owner.";
	elseif lens == "Tourism" then
		return "Shows tourism.";
	elseif lens == "Loyalty" then
		return "Marks cities that gain or lose loyalty.";
	elseif lens == "Empire" then
		return "Shows the details of your empire.";
	elseif lens == "Power" then
		return "Shows power: " .. List( _Names( { "LOC_POWER_LENS_KEY_POWER_SOURCE", "LOC_POWER_LENS_KEY_FULLY_POWERED", "LOC_POWER_LENS_KEY_UNDERPOWERED",
			"LOC_POWER_LENS_KEY_POWER_RANGE" } ), "" ) .. ".";
	end
	return "";
end

-- ===========================================================================
--	On / off
-- ===========================================================================
function LensText_Toggled( action:string, modal:boolean )
	local lens:table = LensText_Actions[ action ];
	if lens == nil then return nil; end
	if modal then
		m_active = lens.id;
		local text:string = lens.name .. " lens on";
		local legend:string = LensText_Legend( lens.id );
		if legend ~= "" then text = text .. ". " .. legend; end
		if m_perPlot[ lens.id ] then text = text .. " Move the cursor to hear each tile."; end
		return text;
	end
	if m_active == nil then return nil; end		-- nothing was on and nothing is on: the game ignored the key
	local was:string = m_names[ m_active ] or lens.name;
	m_active = nil;
	return was .. " lens off";
end

function LensText_ActiveLens()
	if m_active == nil then return nil; end
	if UI.GetInterfaceMode() ~= InterfaceModeTypes.VIEW_MODAL_LENS then
		m_active = nil;
		return nil;
	end
	return m_active;
end

-- ===========================================================================
--	Per plot
-- ===========================================================================
local function _Revealed( plot:table )
	local me:number = _LocalPlayer();
	if me == nil then return false; end
	local vis:table = PlayersVisibility[ me ];
	return vis ~= nil and vis:IsRevealed( plot:GetIndex() );
end

local function _OwnerCity( plot:table )
	local owner:number = plot:GetOwner();
	if owner == nil or owner < 0 then return nil; end
	local ok:boolean, city = pcall( Cities.GetPlotPurchaseCity, plot );
	if ok then return city; end
	return nil;
end

local function _Num( value:number )
	value = math.floor( value * 10 + 0.5 ) / 10;
	if value == math.floor( value ) then return tostring( math.floor( value ) ); end
	return tostring( value );
end

local function _Appeal( plot:table )
	if plot:IsWater() or not GameCapabilities.HasCapability( "CAPABILITY_LENS_APPEAL" ) then return nil; end
	local appeal:number = plot:GetAppeal();
	local best:table = nil;
	for row in GameInfo.AppealHousingChanges() do
		if appeal >= row.MinimumValue and ( best == nil or row.MinimumValue > best.MinimumValue ) then best = row; end
	end
	if best == nil then return "appeal " .. appeal; end
	return "appeal: " .. _Clean( Locale.Lookup( best.Description ) ) .. " " .. appeal;
end

local function _Religion( plot:table )
	local city:table = _OwnerCity( plot );
	if city == nil then return nil; end
	local ok:boolean, text = pcall( function()
		local cityReligion:table = city:GetReligion();
		local majority:number = cityReligion:GetMajorityReligion();
		local row:table = ( majority ~= nil and majority >= 0 ) and GameInfo.Religions[ majority ] or nil;
		if row == nil or row.Pantheon then return "no religion"; end
		local followers:number = 0;
		for _, data in ipairs( cityReligion:GetReligionsInCity() ) do
			if data.Religion == majority then followers = data.Followers or 0; end
		end
		local name:string = _Clean( Locale.Lookup( Game.GetReligion():GetName( majority ) ) );
		if followers == 1 then return name .. ", 1 follower"; end
		return name .. ", " .. followers .. " followers";
	end );
	if not ok then print( "LensText religion: " .. tostring( text ) ); return nil; end
	return text;
end

local function _Continent( plot:table )
	if plot:IsWater() then return nil; end
	local continent:number = plot:GetContinentType();
	if continent == nil or continent < 0 then return nil; end
	local row:table = GameInfo.Continents[ continent ];
	if row == nil then return nil; end
	return "continent " .. _Clean( Locale.Lookup( row.Description ) );
end

local function _Settler( plot:table )
	if plot:IsWater() then return nil; end
	local ok:boolean, reason = SettleScan_CheckPlot( plot );
	if not ok then return SettleScan_CannotText( reason ); end
	local water:string = "no water";
	local freshOk:boolean, fresh = pcall( plot.IsFreshWater, plot );
	if plot:IsRiver() or plot:IsLake() or ( freshOk and fresh == true ) then water = "fresh water";
	elseif plot:IsCoastalLand() then water = "coastal"; end
	return "can settle, " .. water;
end

local function _Loyalty( plot:table )
	local city:table = _OwnerCity( plot );
	if city == nil or city:GetOwner() ~= _LocalPlayer() or city.GetCulturalIdentity == nil then return nil; end
	local ok:boolean, text = pcall( function()
		local identity:table = city:GetCulturalIdentity();
		if identity == nil then return nil; end
		local result:string = Locale.Lookup( city:GetName() ) .. " loyalty " .. _Num( identity:GetLoyalty() );
		local perTurn:number = math.floor( identity:GetLoyaltyPerTurn() * 10 + 0.5 ) / 10;
		if perTurn > 0 then result = result .. ", plus " .. _Num( perTurn );
		elseif perTurn < 0 then result = result .. ", minus " .. _Num( -perTurn ); end
		return result;
	end );
	if not ok then print( "LensText loyalty: " .. tostring( text ) ); return nil; end
	return text;
end

local function _Government( plot:table )
	local owner:number = plot:GetOwner();
	local me:number = _LocalPlayer();
	if owner == nil or owner < 0 or me == nil then return nil; end
	local ok:boolean, text = pcall( function()
		if owner ~= me and not Players[ me ]:GetDiplomacy():HasMet( owner ) then return nil; end
		local player:table = Players[ owner ];
		if player:IsBarbarian() then return nil; end
		local index:number = player:GetCulture():GetCurrentGovernment();
		if index == nil or index < 0 then
			if player:IsMajor() then return nil; end
			return "government: city state";
		end
		local row:table = GameInfo.Governments[ index ];
		if row == nil then return nil; end
		return "government: " .. _Clean( Locale.Lookup( row.Name ) );
	end );
	if not ok then print( "LensText government: " .. tostring( text ) ); return nil; end
	return text;
end

-- settlerSelected: a settler is selected, the cursor text already says whether it can settle there
function LensText_PlotText( lens:string, plot:table, settlerSelected:boolean )
	if lens == nil or plot == nil or not _Revealed( plot ) then return nil; end
	if lens == "Appeal" then return _Appeal( plot );
	elseif lens == "Religion" then return _Religion( plot );
	elseif lens == "Continent" then return _Continent( plot );
	elseif lens == "Settler" then
		if settlerSelected then return nil; end
		return _Settler( plot );
	elseif lens == "Loyalty" then return _Loyalty( plot );
	elseif lens == "Government" then return _Government( plot );
	end
	return nil;
end

function LensText_Prefix( text:string, plot:table, settlerSelected:boolean )
	local lens:string = LensText_ActiveLens();
	if lens == nil then return text; end
	local value:string = LensText_PlotText( lens, plot, settlerSelected );
	if value == nil then return text; end
	return value .. ". " .. text;
end
