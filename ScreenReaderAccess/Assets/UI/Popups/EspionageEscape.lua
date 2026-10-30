include("ScreenReader");	-- ScreenReaderAccess
include("KeyNavList");		-- ScreenReaderAccess
include("SRListen");		-- ScreenReaderAccess

local district1 = "DISTRICT_AERODROME";
local district2 = "DISTRICT_HARBOR";
local district3 = "DISTRICT_COMMERCIAL_HUB";
local district4 = "DISTRICT_CITY_CENTER";


function OnClose()
	ContextPtr:SetHide(true);
end

function OnButton1()
	local tParameters = {};
	tParameters[ PlayerOperations.PARAM_DISTRICT_TYPE ] = GameInfo.Districts[district1].Index;
	UI.RequestPlayerOperation(Game.GetLocalPlayer(), PlayerOperations.SET_ESCAPE_ROUTE, tParameters);	
	ContextPtr:SetHide(true);
end
function OnButton2()
	local tParameters = {};
	tParameters[ PlayerOperations.PARAM_DISTRICT_TYPE ] = GameInfo.Districts[district2].Index;
	UI.RequestPlayerOperation(Game.GetLocalPlayer(), PlayerOperations.SET_ESCAPE_ROUTE, tParameters);	
	ContextPtr:SetHide(true);
end
function OnButton3()
	local tParameters = {};
	tParameters[ PlayerOperations.PARAM_DISTRICT_TYPE ] = GameInfo.Districts[district3].Index;
	UI.RequestPlayerOperation(Game.GetLocalPlayer(), PlayerOperations.SET_ESCAPE_ROUTE, tParameters);	
	ContextPtr:SetHide(true);
end
function OnButton4()
	local tParameters = {};
	tParameters[ PlayerOperations.PARAM_DISTRICT_TYPE ] = GameInfo.Districts[district4].Index;
	UI.RequestPlayerOperation(Game.GetLocalPlayer(), PlayerOperations.SET_ESCAPE_ROUTE, tParameters);	
	ContextPtr:SetHide(true);
end

function OnOpen(testParam)

	print (testParam);

	local localPlayer = Players[Game.GetLocalPlayer()];
	if (localPlayer == nil) then
		return;
	end

	local spyUnitID = localPlayer:GetDiplomacy():GetNextEscapingSpyID();
	local spyUnit :table = localPlayer:GetUnits():FindID(spyUnitID);

	local currentCity = Cities.GetPlotPurchaseCity(spyUnit:GetX(), spyUnit:GetY());
	local spyName = spyUnit:GetName();
	local lootName = spyUnit:GetLootName();
	local pursuitSpyName = spyUnit:GetPursuingSpyName();

	local choice1Turns = GameInfo.Districts[district1].TravelTime;
	local choice2Turns = GameInfo.Districts[district2].TravelTime;
	local choice3Turns = GameInfo.Districts[district3].TravelTime;
	local choice4Turns = GameInfo.Districts[district4].TravelTime;

	Controls.PanelHeader:LocalizeAndSetText("LOC_ESPIONAGE_ESCAPE_PANEL_HEADER");
	Controls.CityHeader:LocalizeAndSetText("LOC_ESPIONAGE_ESCAPE_CITY_HEADER", currentCity:GetName());
	Controls.AgentLabel:LocalizeAndSetText("LOC_ESPIONAGE_ESCAPE_AGENT_LABEL");
	Controls.AgentDetails:LocalizeAndSetText(spyName);
	Controls.LootLabel:LocalizeAndSetText("LOC_ESPIONAGE_ESCAPE_LOOT_LABEL");
	Controls.LootDetails:LocalizeAndSetText(lootName);
	Controls.PursuitLabel:LocalizeAndSetText("LOC_ESPIONAGE_ESCAPE_PURSUIT_LABEL");
	if (pursuitSpyName == "") then
		Controls.PursuitDetails:LocalizeAndSetText("LOC_ESPIONAGE_ESCAPE_PURSUIT_POLICE");
	else
		Controls.PursuitDetails:LocalizeAndSetText("LOC_ESPIONAGE_ESCAPE_PURSUIT_COUNTERSPY", pursuitSpyName);
	end
	Controls.ChoiceHeader:LocalizeAndSetText("LOC_ESPIONAGE_ESCAPE_CHOICE_HEADER");
	Controls.Button1:LocalizeAndSetText("LOC_ESPIONAGE_ESCAPE_CHOICE_1");
	if (currentCity:GetDistricts():HasDistrict(GameInfo.Districts[district1].Index, true, true)) then
		Controls.Label1:LocalizeAndSetText("LOC_ESPIONAGE_ESCAPE_TURNS", choice1Turns);
		Controls.Label1:SetColorByName("BodyTextBlue");
		Controls.Button1:SetDisabled(false);
		Controls.Button1:LocalizeAndSetToolTip("LOC_ESPIONAGE_ESCAPE_TOOLTIP");
	else
		Controls.Label1:LocalizeAndSetText("LOC_ESPIONAGE_ESCAPE_NO_DISTRICT", GameInfo.Districts[district1].Name);
		Controls.Label1:SetColorByName("BodyTextBlueAlt");
		Controls.Button1:SetDisabled(true);
	end
	Controls.Button2:LocalizeAndSetText("LOC_ESPIONAGE_ESCAPE_CHOICE_2");
	if (currentCity:GetDistricts():HasDistrict(GameInfo.Districts[district2].Index, true, true)) then
		Controls.Label2:LocalizeAndSetText("LOC_ESPIONAGE_ESCAPE_TURNS", choice2Turns);
		Controls.Label2:SetColorByName("BodyTextBlue");
		Controls.Button2:SetDisabled(false);
		Controls.Button2:LocalizeAndSetToolTip("LOC_ESPIONAGE_ESCAPE_TOOLTIP");
	else
		Controls.Label2:LocalizeAndSetText("LOC_ESPIONAGE_ESCAPE_NO_DISTRICT", GameInfo.Districts[district2].Name);
		Controls.Label2:SetColorByName("BodyTextBlueAlt");
		Controls.Button2:SetDisabled(true);
	end
	Controls.Button3:LocalizeAndSetText("LOC_ESPIONAGE_ESCAPE_CHOICE_3");
	if (currentCity:GetDistricts():HasDistrict(GameInfo.Districts[district3].Index, true, true)) then
		Controls.Label3:LocalizeAndSetText("LOC_ESPIONAGE_ESCAPE_TURNS", choice3Turns);
		Controls.Label3:SetColorByName("BodyTextBlue");
		Controls.Button3:SetDisabled(false);
		Controls.Button3:LocalizeAndSetToolTip("LOC_ESPIONAGE_ESCAPE_TOOLTIP");
	else
		Controls.Label3:LocalizeAndSetText("LOC_ESPIONAGE_ESCAPE_NO_DISTRICT", GameInfo.Districts[district3].Name);
		Controls.Label3:SetColorByName("BodyTextBlueAlt");
		Controls.Button3:SetDisabled(true);
	end
	Controls.Button4:LocalizeAndSetText("LOC_ESPIONAGE_ESCAPE_CHOICE_4");
	Controls.Label4:LocalizeAndSetText("LOC_ESPIONAGE_ESCAPE_TURNS", choice4Turns);
	Controls.Button4:LocalizeAndSetToolTip("LOC_ESPIONAGE_ESCAPE_TOOLTIP");

	ContextPtr:SetHide(false);
	Controls.PopupAlphaIn:SetToBeginning();
	Controls.PopupAlphaIn:Play();
	Controls.PopupSlideIn:SetToBeginning();
	Controls.PopupSlideIn:Play();
	SRA_Announce();		-- ScreenReaderAccess
end

-- Begin ScreenReaderAccess mod change
-- ===========================================================================
--	ScreenReaderAccess: keyboard navigation and speech
--	The escape routes (the four buttons) as a list: Up/Down/Home/End, Space = loot and pursuit, Enter = the button's own
--	callback (OnButton1..4, what a click does), Escape = OnClose (what the game does). Other keys are swallowed while shown.
-- ===========================================================================
local m_srList			:table = nil;

local function SRA_Clean( text:string )
	return CleanTextForSpeech( Locale.Lookup( text or "" ) );
end

local function SRA_ButtonText( button:table )
	local ok:boolean, text = pcall( function() return button:GetTextControl():GetText(); end );
	if ok and text ~= nil then return text; end
	return "";
end

local function SRA_Details()
	local loot:string = SRA_Clean( Controls.LootDetails:GetText() );
	local pursuit:string = SRA_Clean( Controls.PursuitDetails:GetText() );
	return "Loot: " .. ( loot ~= "" and loot or "none" ) .. ". Pursued by: " .. pursuit;
end

local function SRA_Items()
	local items:table = {};
	local callbacks:table = { OnButton1, OnButton2, OnButton3, OnButton4 };
	for i = 1, 4 do
		local button:table = Controls[ "Button" .. i ];
		local label:table = Controls[ "Label" .. i ];
		if button ~= nil and not button:IsHidden() then
			local route:string = SRA_Clean( SRA_ButtonText( button ) );
			local info:string = ( label ~= nil ) and SRA_Clean( label:GetText() ) or "";
			local disabled:boolean = button:IsDisabled();
			local text:string = route;
			if disabled then text = text .. ", not available"; end
			if info ~= "" then text = text .. ", " .. info; end
			table.insert( items, { key = i, text = text, route = route, choosable = not disabled, reason = info, detail = SRA_Details, callback = callbacks[ i ] } );
		end
	end
	return items;
end

local function SRA_OnActivate( item:table )
	OutputMessageToScreenReader( "Escaping by " .. item.route );
	item.callback();		-- what a click on the button does: SET_ESCAPE_ROUTE, then the popup hides
end

local function SRA_OnEscape()
	OnClose();
	OutputMessageToScreenReader( "Closed" );
end

-- "Spy X was discovered in London. Choose an escape route: Airplane, Turns to return: 2, 1 of 4"
function SRA_Announce()
	if m_srList == nil then return; end
	local items:table = SRA_Items();
	local first:number = 1;
	for i, item in ipairs( items ) do
		if item.choosable then first = i; break; end
	end
	m_srList.Reset();
	m_srList.Open( "", items[ first ] ~= nil and items[ first ].key or nil, true );
	local text:string = SRA_Clean( Controls.AgentDetails:GetText() ) .. " was discovered " .. SRA_Clean( Controls.CityHeader:GetText() ) .. ". Choose an escape route";
	if items[ first ] ~= nil then text = text .. ": " .. items[ first ].text .. ", " .. first .. " of " .. #items; end
	OutputMessageToScreenReader( text, true );
end

function SRA_HandleInput( pInputStruct:table )
	if ContextPtr:IsHidden() then return false; end
	if m_srList ~= nil and m_srList.HandleInput( pInputStruct ) then return true; end
	local msg:number = pInputStruct:GetMessageType();
	return msg == KeyEvents.KeyDown or msg == KeyEvents.KeyUp;
end
-- End ScreenReaderAccess mod change

-- ===========================================================================
--	Input
--	UI Event Handler
-- ===========================================================================
function OnInputHandler( pInputStruct:table )
	if SRA_HandleInput( pInputStruct ) then return true; end		-- ScreenReaderAccess
	local uiMsg = pInputStruct:GetMessageType();
	if uiMsg == KeyEvents.KeyUp then
		if pInputStruct:GetKey() == Keys.VK_ESCAPE then
			OnClose();
			return true;
		end
	end
	return false;
end

function Initialize()
	ContextPtr:SetInputHandler( OnInputHandler, true );
	Controls.Button1:RegisterCallback(Mouse.eLClick, OnButton1);
	Controls.Button2:RegisterCallback(Mouse.eLClick, OnButton2);
	Controls.Button3:RegisterCallback(Mouse.eLClick, OnButton3);
	Controls.Button4:RegisterCallback(Mouse.eLClick, OnButton4);
	SRListen( LuaEvents.NotificationPanel_OpenEspionageEscape, OnOpen );		-- ScreenReaderAccess (was .Add)
	ContextPtr:SetShutdown( function() SRUnlistenAll(); end );		-- ScreenReaderAccess
	-- ScreenReaderAccess
	print( "EspionageEscape: ScreenReaderAccess copy loaded" );
	m_srList = KeyNavList_Create{
		wheel = true,		-- the pad wheel: a short menu with fixed directions
		build = SRA_Items,
		isActive = function() return not ContextPtr:IsHidden(); end,
		onActivate = SRA_OnActivate,
		onClose = SRA_OnEscape,
	};
end
Initialize();
