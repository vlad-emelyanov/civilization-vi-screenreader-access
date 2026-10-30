-- Copyright 2016-2018, Firaxis Games

include( "ScreenReader" );		-- ScreenReaderAccess mod change
include( "KeyNavList" );		-- ScreenReaderAccess mod change
include( "SRListen" );			-- ScreenReaderAccess mod change

-- ===========================================================================
--	GLOBALS
-- ===========================================================================
g_pSelectedCity = nil;

-- ScreenReaderAccess mod change: keyboard list over the visible buttons, speech of the captured city
local m_srList		:table = nil;
local m_srSpeakIn	:number = -1;		-- seconds until the popup is read (the expansion fills the texts after the base OnOpen)
local m_srCityName	:string = "";
-- display order for the keyboard: keep, raze, then the liberate options
local SR_BUTTONS	:table = { "Button3", "Button4", "Button1", "Button2" };


-- ===========================================================================
--	FUNCTIONS
-- ===========================================================================


-- ===========================================================================
function OnButton1()
	local tParameters = {};
	tParameters[UnitOperationTypes.PARAM_FLAGS] = CityDestroyDirectives.LIBERATE_FOUNDER;
	if (CityManager.CanStartCommand( g_pSelectedCity, CityCommandTypes.DESTROY, tParameters)) then
		UI.DeselectAllCities();
		CityManager.RequestCommand( g_pSelectedCity, CityCommandTypes.DESTROY, tParameters);
	end
	Close();
end

-- ===========================================================================
function OnButton2()
	local tParameters = {};
	tParameters[UnitOperationTypes.PARAM_FLAGS] = CityDestroyDirectives.LIBERATE_PREVIOUS_OWNER;
	if (CityManager.CanStartCommand( g_pSelectedCity, CityCommandTypes.DESTROY, tParameters)) then
		UI.DeselectAllCities();
		CityManager.RequestCommand( g_pSelectedCity, CityCommandTypes.DESTROY, tParameters);
	end
	Close();
end

-- ===========================================================================
function OnButton3()
	local tParameters = {};
	tParameters[UnitOperationTypes.PARAM_FLAGS] = CityDestroyDirectives.KEEP;
	if (CityManager.CanStartCommand( g_pSelectedCity, CityCommandTypes.DESTROY, tParameters)) then
		CityManager.RequestCommand( g_pSelectedCity, CityCommandTypes.DESTROY, tParameters);
	end
	Close();
end

-- ===========================================================================
function OnButton4()
	local tParameters = {};
	tParameters[UnitOperationTypes.PARAM_FLAGS] = CityDestroyDirectives.RAZE;
	if (CityManager.CanStartCommand( g_pSelectedCity, CityCommandTypes.DESTROY, tParameters)) then
		UI.DeselectAllCities();
		CityManager.RequestCommand( g_pSelectedCity, CityCommandTypes.DESTROY, tParameters);
       UI.PlaySound("RAZE_CITY");
	end
	Close();
end

-- ===========================================================================
function Close()
	UIManager:DequeuePopup(ContextPtr);
end

-- ===========================================================================
function OnOpen()
	local localPlayerID = Game.GetLocalPlayer();
	local localPlayer = Players[localPlayerID];
	if (localPlayer == nil) then
		return;
	end 

	g_pSelectedCity = localPlayer:GetCities():GetNextCapturedCity();

	Controls.PanelHeader:LocalizeAndSetText("LOC_RAZE_CITY_HEADER");
    Controls.CityHeader:LocalizeAndSetText("LOC_RAZE_CITY_NAME_LABEL");
    Controls.CityName:LocalizeAndSetText(g_pSelectedCity:GetName());
    Controls.CityPopulation:LocalizeAndSetText("LOC_RAZE_CITY_POPULATION_LABEL");
    Controls.NumPeople:SetText(tostring(g_pSelectedCity:GetPopulation()));
    Controls.CityDistricts:LocalizeAndSetText("LOC_RAZE_CITY_DISTRICTS_LABEL");
	local iNumDistricts = g_pSelectedCity:GetDistricts():GetNumZonedDistrictsRequiringPopulation();
    Controls.NumDistricts:SetText(tostring(iNumDistricts));

	local szWarmongerString;
	local eOriginalOwner = g_pSelectedCity:GetOriginalOwner();
	local originalOwnerPlayer = Players[eOriginalOwner];
	local eOwnerBeforeOccupation = g_pSelectedCity:GetOwnerBeforeOccupation();
	local eConqueredFrom = g_pSelectedCity:GetJustConqueredFrom();
	local bWipedOut = (originalOwnerPlayer:GetCities():GetCount() < 1);
	local eLastTransferType = g_pSelectedCity:GetLastTransferType();

	if (eOriginalOwner ~= eOwnerBeforeOccupation and localPlayer:GetDiplomacy():CanLiberateCityTo(eOriginalOwner) and eOriginalOwner ~= eConqueredFrom) then
		Controls.Button1:LocalizeAndSetText("LOC_RAZE_CITY_LIBERATE_FOUNDER_BUTTON_LABEL", PlayerConfigurations[eOriginalOwner]:GetCivilizationShortDescription());
		szWarmongerString = Locale.Lookup("LOC_RAZE_CITY_LIBERATE_WARMONGER_EXPLANATION");
		Controls.Button1:LocalizeAndSetToolTip("LOC_RAZE_CITY_LIBERATE_EXPLANATION", szWarmongerString);
		Controls.Button1:SetHide(false);
	else
		Controls.Button1:SetHide(true);
	end

	if (localPlayer:GetDiplomacy():CanLiberateCityTo(eOwnerBeforeOccupation) and eOwnerBeforeOccupation ~= eConqueredFrom) then
		Controls.Button2:LocalizeAndSetText("LOC_RAZE_CITY_LIBERATE_PREWAR_OWNER_BUTTON_LABEL", PlayerConfigurations[eOwnerBeforeOccupation]:GetCivilizationShortDescription());
		szWarmongerString = Locale.Lookup("LOC_RAZE_CITY_LIBERATE_WARMONGER_EXPLANATION");
		Controls.Button2:LocalizeAndSetToolTip("LOC_RAZE_CITY_LIBERATE_EXPLANATION", szWarmongerString);
		Controls.Button2:SetHide(false);
	else
		Controls.Button2:SetHide(true);
	end

	Controls.Button3:LocalizeAndSetText("LOC_RAZE_CITY_KEEP_BUTTON_LABEL");
	if (eLastTransferType == CityTransferTypes.BY_GIFT) then
		szWarmongerString = Locale.Lookup("LOC_RAZE_CITY_KEEP_EXPLANATION_TRADED");
		Controls.Button3:LocalizeAndSetToolTip(szWarmongerString);
	elseif (bWipedOut ~= true) then
		local iWarmongerPoints = localPlayer:GetDiplomacy():ComputeCityWarmongerPoints(g_pSelectedCity, eConqueredFrom, false);
		szWarmongerString = Locale.Lookup("LOC_RAZE_CITY_KEEP_WARMONGER_EXPLANATION", localPlayer:GetDiplomacy():GetWarmongerLevel(-iWarmongerPoints));
		Controls.Button3:LocalizeAndSetToolTip("LOC_RAZE_CITY_KEEP_EXPLANATION", szWarmongerString);
	else
		szWarmongerString = Locale.Lookup("LOC_RAZE_CITY_KEEP_LAST_CITY_EXPLANATION");
		Controls.Button3:LocalizeAndSetToolTip(szWarmongerString);
	end

	Controls.Button4:LocalizeAndSetText("LOC_RAZE_CITY_RAZE_BUTTON_LABEL");
	if (g_pSelectedCity:CanRaze()) then
		if (bWipedOut ~= true) then
		local iWarmongerPoints = localPlayer:GetDiplomacy():ComputeCityWarmongerPoints(g_pSelectedCity, eConqueredFrom, true);
			szWarmongerString = Locale.Lookup("LOC_RAZE_CITY_RAZE_WARMONGER_EXPLANATION", localPlayer:GetDiplomacy():GetWarmongerLevel(-iWarmongerPoints));
			Controls.Button4:LocalizeAndSetToolTip("LOC_RAZE_CITY_RAZE_EXPLANATION", szWarmongerString);
		else
			szWarmongerString = Locale.Lookup("LOC_RAZE_CITY_RAZE_LAST_CITY_EXPLANATION");
			Controls.Button4:LocalizeAndSetToolTip(szWarmongerString);
		end
		Controls.Button4:SetDisabled(false);
	else
		Controls.Button4:LocalizeAndSetToolTip("LOC_RAZE_CITY_RAZE_DISABLED_EXPLANATION");
		Controls.Button4:SetDisabled(true);

	end
	Controls.PopupStack:CalculateSize();

	UIManager:QueuePopup(ContextPtr, PopupPriority.Medium);

	Controls.PopupAlphaIn:SetToBeginning();
	Controls.PopupAlphaIn:Play();
	Controls.PopupSlideIn:SetToBeginning();
	Controls.PopupSlideIn:Play();	
end

-- ===========================================================================
-- ScreenReaderAccess mod change: the original compared its first argument (an input struct) with KeyEvents.KeyUp, so Escape never
-- closed the popup; the decision stays mandatory (the close button still works with the mouse)
function OnInputHandler( pInputStruct:table )
	if m_srList ~= nil and m_srList.HandleInput( pInputStruct ) then return true; end
	return true;
end

-- ===========================================================================
--	ScreenReaderAccess mod change: keyboard list and speech
-- ===========================================================================
local function SRA_Items()
	local items:table = {};
	for _, id in ipairs( SR_BUTTONS ) do
		local button = Controls[ id ];
		if button ~= nil and not button:IsHidden() then
			local label:string = CleanTextForSpeech( button:GetTextControl():GetText() );
			local tip:string = CleanTextForSpeech( button:GetToolTipString() );
			local item:table = { key = id, id = id, label = label, text = label, detail = tip };
			if button:IsDisabled() then
				item.text = label .. ", unavailable";
				item.choosable = false;
				item.reason = "Unavailable" .. ( tip ~= "" and ( ": " .. tip ) or "" );
			end
			table.insert( items, item );
		end
	end
	return items;
end

local function SRA_OnActivate( item:table )
	local city:string = m_srCityName;
	local text:string;
	if item.id == "Button3" then
		text = "Kept " .. city;
		OutputMessageToScreenReader( text );
		OnButton3();
	elseif item.id == "Button4" then
		text = "Razing " .. city;
		OutputMessageToScreenReader( text );
		OnButton4();
	elseif item.id == "Button1" then
		OutputMessageToScreenReader( city .. ": " .. item.label );
		OnButton1();
	elseif item.id == "Button2" then
		OutputMessageToScreenReader( city .. ": " .. item.label );
		OnButton2();
	end
end

local function SRA_OnEscape()
	OutputMessageToScreenReader( "Choose an option" );
end

-- "<City> captured from <civ>. Population N, D districts. Options: ... Keep: consequence. ..."
local function SRA_Speak()
	if ContextPtr:IsHidden() or g_pSelectedCity == nil then return; end
	local city:string = Locale.Lookup( g_pSelectedCity:GetName() );
	-- a city name the game has no text for stays a raw key: "LOC_CITY_NAME_ULUNDI" -> "Ulundi"
	local rawName:string = string.match( city, "^LOC_CITY_NAME_(.+)$" );
	if rawName ~= nil then
		city = string.upper( string.sub( rawName, 1, 1 ) ) .. string.lower( string.sub( rawName, 2 ) );
		city = string.gsub( city, "_(%l)", function( c ) return " " .. string.upper( c ); end );
	end
	m_srCityName = city;
	local text:string = city .. " captured";
	local ok:boolean, civ = pcall( function()
		local from:number = g_pSelectedCity:GetJustConqueredFrom();
		if from == nil or from < 0 or PlayerConfigurations[ from ] == nil then return nil; end
		return Locale.Lookup( PlayerConfigurations[ from ]:GetCivilizationShortDescription() );
	end );
	if ok and civ ~= nil and civ ~= "" then text = text .. " from " .. civ; end
	text = text .. ". Population " .. Controls.NumPeople:GetText() .. ", " .. Controls.NumDistricts:GetText() .. " districts.";
	local items:table = SRA_Items();
	local names:table = {};
	for _, item in ipairs( items ) do table.insert( names, item.text ); end
	text = text .. " " .. table.concat( names, ", " ) .. ". " .. SRKey( "Space" ) .. " for details";
	-- the list was opened when the popup showed; this speaks the line and then the focused (first) option
	if m_srList ~= nil and #items > 0 then
		m_srList.Focus( m_srList.GetFocusKey() or items[1].key, text );
	else
		OutputMessageToScreenReader( text, true );
	end
end

local function SRA_OnUpdate( deltaTime:number )
	if m_srSpeakIn < 0 then return; end
	m_srSpeakIn = m_srSpeakIn - deltaTime;
	if m_srSpeakIn >= 0 then return; end
	m_srSpeakIn = -1;
	SRA_Speak();
end

-- the popup is really shown (QueuePopup made it visible): open the list now, hold the hub's speech, read after a moment
-- (the expansion texts are set by then; every show re-arms the timer)
local function SRA_OnShow()
	LuaEvents.SRA_SpeechHold( "RazeCity", true, "/InGame/WorldPopups/" .. ContextPtr:GetID() );
	if m_srList ~= nil then
		m_srList.Reset();
		m_srList.Open( "", nil, true );
	end
	m_srSpeakIn = 0.3;
end

-- every way the popup disappears (choice, close button, queue)
local function SRA_OnHide()
	m_srSpeakIn = -1;
	LuaEvents.SRA_SpeechHold( "RazeCity", false );
end

-- ===========================================================================
function OnClose()
	Close();
end

-- ===========================================================================
function LateInitialize()	
	ContextPtr:SetInputHandler(OnInputHandler, true);		-- ScreenReaderAccess mod change: modal

	Controls.Button1:RegisterCallback(Mouse.eLClick, OnButton1);
	Controls.Button2:RegisterCallback(Mouse.eLClick, OnButton2);
	Controls.Button3:RegisterCallback(Mouse.eLClick, OnButton3);
	Controls.Button4:RegisterCallback(Mouse.eLClick, OnButton4);
	Controls.CloseButton:RegisterCallback(Mouse.eLClick, OnClose);
	
	LuaEvents.NotificationPanel_OpenRazeCityChooser.Add( OnOpen );

	-- ScreenReaderAccess mod change
	ContextPtr:SetShowHandler( SRA_OnShow );
	ContextPtr:SetHideHandler( SRA_OnHide );
	ContextPtr:SetUpdate( SRA_OnUpdate );
	m_srList = KeyNavList_Create{
		wheel = true,		-- the pad wheel: a short menu with fixed directions
		build = SRA_Items,
		isActive = function() return not ContextPtr:IsHidden(); end,
		onActivate = SRA_OnActivate,
		onClose = SRA_OnEscape,
	};
end

-- ===========================================================================
function OnInit( isReload:boolean )
	LateInitialize();
end

-- ===========================================================================
function Initialize()
	ContextPtr:SetInitHandler( OnInit );
	ContextPtr:SetShutdown( function() SRUnlistenAll(); end );		-- ScreenReaderAccess mod change
	print( "RazeCity: ScreenReaderAccess copy loaded" );
end
Initialize();
