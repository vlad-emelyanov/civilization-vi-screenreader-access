-- Modeled after RazeCity.lua

include( "ScreenReader" );		-- ScreenReaderAccess mod change
include( "KeyNavList" );		-- ScreenReaderAccess mod change

local g_pSelectedCity;

-- ScreenReaderAccess mod change: keyboard list (Keep / Refuse) and speech
local m_srList		:table = nil;
local m_srSpeakIn	:number = -1;		-- seconds until the popup is read (the texts are set by OnOpen before the context shows)
local m_srCityName	:string = "";
local SR_BUTTONS	:table = { "KeepButton", "RejectButton" };

function OnKeepButton()
	local tParameters = {};
	tParameters[UnitOperationTypes.PARAM_FLAGS] = CityDestroyDirectives.KEEP;
	if (CityManager.CanStartCommand( g_pSelectedCity, CityCommandTypes.DESTROY, tParameters)) then
		CityManager.RequestCommand( g_pSelectedCity, CityCommandTypes.DESTROY, tParameters);
	end
	OnClose();
end
function OnRejectButton()
	local tParameters = {};
	tParameters[UnitOperationTypes.PARAM_FLAGS] = CityDestroyDirectives.REJECT;
	if (CityManager.CanStartCommand( g_pSelectedCity, CityCommandTypes.DESTROY, tParameters)) then
		UI.DeselectAllCities();
		CityManager.RequestCommand( g_pSelectedCity, CityCommandTypes.DESTROY, tParameters);
	end
	OnClose();
end

function OnClose()
	ContextPtr:SetHide(true);
end

function OnOpen()
	local localPlayerID = Game.GetLocalPlayer();
	local localPlayer = Players[localPlayerID];
	if (localPlayer == nil) then
		return;
	end 

	g_pSelectedCity = localPlayer:GetCities():GetNextRebelledCity();
	-- ScreenReaderAccess mod change: no rebelled city (already answered): stay closed, the original would fail on the nil city
	if g_pSelectedCity == nil then
		print( "DisloyalCityChooser: GetNextRebelledCity returned nil, popup not opened" );
		return;
	end

	Controls.PanelHeader:LocalizeAndSetText("LOC_DISLOYAL_CITY_HEADER");
    Controls.CityHeader:LocalizeAndSetText("LOC_DISLOYAL_CITY_NAME_LABEL");
    Controls.CityName:LocalizeAndSetText(g_pSelectedCity:GetName());
    Controls.CityPopulation:LocalizeAndSetText("LOC_DISLOYAL_CITY_POPULATION_LABEL");
    Controls.NumPeople:SetText(tostring(g_pSelectedCity:GetPopulation()));
    Controls.CityDistricts:LocalizeAndSetText("LOC_DISLOYAL_CITY_DISTRICTS_LABEL");
	local iNumDistricts = g_pSelectedCity:GetDistricts():GetNumZonedDistrictsRequiringPopulation();
    Controls.NumDistricts:SetText(tostring(iNumDistricts));

	Controls.KeepButton:LocalizeAndSetText("LOC_DISLOYAL_CITY_CHOOSER_KEEP_BUTTON_LABEL");
	Controls.KeepButton:LocalizeAndSetToolTip("LOC_DISLOYAL_CITY_CHOOSER_KEEP_EXPLANATION");

	Controls.RejectButton:LocalizeAndSetText("LOC_DISLOYAL_CITY_CHOOSER_REFUSE_BUTTON_LABEL");
	Controls.RejectButton:LocalizeAndSetToolTip("LOC_DISLOYAL_CITY_CHOOSER_REFUSE_EXPLANATION");

	Controls.PopupStack:CalculateSize();
	Controls.PopupStack:ReprocessAnchoring();
	Controls.DisloyalCityPanel:ReprocessAnchoring();
	ContextPtr:SetHide(false);
	Controls.PopupAlphaIn:SetToBeginning();
	Controls.PopupAlphaIn:Play();
	Controls.PopupSlideIn:SetToBeginning();
	Controls.PopupSlideIn:Play();
end

-- ScreenReaderAccess mod change: items, speech, input
local function SRA_Items()
	local items:table = {};
	for _, id in ipairs( SR_BUTTONS ) do
		local button = Controls[ id ];
		if button ~= nil and not button:IsHidden() then
			local label:string = CleanTextForSpeech( button:GetTextControl():GetText() );
			local tip:string = CleanTextForSpeech( button:GetToolTipString() );
			table.insert( items, { key = id, id = id, label = label, text = label, detail = tip } );
		end
	end
	return items;
end

local function SRA_CanDo( flag:number )
	if g_pSelectedCity == nil then return false; end
	local tParameters:table = {};
	tParameters[UnitOperationTypes.PARAM_FLAGS] = flag;
	return CityManager.CanStartCommand( g_pSelectedCity, CityCommandTypes.DESTROY, tParameters ) == true;
end

-- speaks after the check, never before a command that cannot start
local function SRA_OnActivate( item:table )
	local keep:boolean = item.id == "KeepButton";
	if not SRA_CanDo( keep and CityDestroyDirectives.KEEP or CityDestroyDirectives.REJECT ) then
		OutputMessageToScreenReader( m_srCityName .. ": the game does not allow this choice right now, nothing happened. " .. SRKey( "Escape" ) .. " closes the popup" );
		return;
	end
	if keep then
		OutputMessageToScreenReader( "Kept " .. m_srCityName );
		OnKeepButton();
	else
		OutputMessageToScreenReader( m_srCityName .. " refused, it stays a free city" );
		OnRejectButton();
	end
end

local function SRA_OnEscape()
	OutputMessageToScreenReader( "Closed. The choice is still pending: " .. SRKey( "Enter" ) .. " on the end turn blocker opens it again" );
	OnClose();
end

-- "<City> asks to join you. Population N, D districts. <game's explanation>. Keep City, Refuse City. Up and Down choose, Enter confirms"
local function SRA_Speak()
	if ContextPtr:IsHidden() or g_pSelectedCity == nil then return; end
	local city:string = Locale.Lookup( g_pSelectedCity:GetName() );
	local rawName:string = string.match( city, "^LOC_CITY_NAME_(.+)$" );
	if rawName ~= nil then
		city = string.upper( string.sub( rawName, 1, 1 ) ) .. string.lower( string.sub( rawName, 2 ) );
		city = string.gsub( city, "_(%l)", function( c ) return " " .. string.upper( c ); end );
	end
	m_srCityName = city;
	local text:string = city .. " asks to join you. Population " .. Controls.NumPeople:GetText() .. ", " .. Controls.NumDistricts:GetText() .. " districts. ";
	text = text .. CleanTextForSpeech( Locale.Lookup( "LOC_NOTIFICATION_CONSIDER_DISLOYAL_CITY_SUMMARY" ) );
	local items:table = SRA_Items();
	local names:table = {};
	for _, item in ipairs( items ) do table.insert( names, item.text ); end
	text = text .. " " .. table.concat( names, " or " ) .. ". Up and Down choose, " .. SRKey( "Enter" ) .. " confirms, " .. SRKey( "Space" ) .. " for details";
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

local function SRA_OnShow()
	LuaEvents.SRA_SpeechHold( "DisloyalCity", true );
	if m_srList ~= nil then
		m_srList.Reset();
		m_srList.Open( "", nil, true );
	end
	m_srSpeakIn = 0.3;
end

local function SRA_OnHide()
	m_srSpeakIn = -1;
	LuaEvents.SRA_SpeechHold( "DisloyalCity", false );
end

-- ScreenReaderAccess mod change: the original compared its first argument (an input struct) with KeyEvents.KeyUp, so Escape never closed the popup
function OnInputHandler( pInputStruct:table )
	if m_srList ~= nil and m_srList.HandleInput( pInputStruct ) then return true; end
	return true;
end

-- ===========================================================================
function Initialize()
	ContextPtr:SetHide(true);
	ContextPtr:SetInputHandler( OnInputHandler, true );
	Controls.KeepButton:RegisterCallback(Mouse.eLClick, OnKeepButton);
	Controls.RejectButton:RegisterCallback(Mouse.eLClick, OnRejectButton);
	Controls.ModalScreenClose:RegisterCallback(Mouse.eLClick, OnClose);
	LuaEvents.NotificationPanel_OpenDisloyalCityChooser.Add(OnOpen);

	-- ScreenReaderAccess mod change
	ContextPtr:SetShowHandler( SRA_OnShow );
	ContextPtr:SetHideHandler( SRA_OnHide );
	ContextPtr:SetUpdate( SRA_OnUpdate );
	m_srList = KeyNavList_Create{
		wheel = true,
		build = SRA_Items,
		isActive = function() return not ContextPtr:IsHidden(); end,
		onActivate = SRA_OnActivate,
		onClose = SRA_OnEscape,
	};
	print( "DisloyalCityChooser: ScreenReaderAccess copy loaded" );end
Initialize();
