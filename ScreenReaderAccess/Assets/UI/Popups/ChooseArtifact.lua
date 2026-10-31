include( "ScreenReader" );		-- ScreenReaderAccess mod change
include( "Gamepad" );			-- ScreenReaderAccess mod change
include( "SRListen" );			-- ScreenReaderAccess mod change

g_ActingPlayerID = -1;
g_TargetPlayerID = -1;

-- Begin ScreenReaderAccess mod change
-- ===========================================================================
--	ScreenReaderAccess: keyboard and speech. The popup has no close (the choice is mandatory), so Escape only says so.
--	Left/Right/Up/Down/Tab move between the visible buttons (wrapping), Home/End first/last, Enter runs the focused button's own
--	callback (OnButton1 / OnButton2, what a click does), Space repeats the explanation. Every other key is swallowed while shown.
-- ===========================================================================
local SR_BUTTON_IDS		:table = { "Button1", "Button2" };
local m_srFocusId		:string = "Button1";

local function SRA_Text( control:table )
	if control == nil then return ""; end
	local ok:boolean, text = pcall( function() return control:GetText(); end );
	if not ok or text == nil then return ""; end
	return CleanTextForSpeech( text );
end

-- the visible buttons in order: { id, label, callback }
local function SRA_Items()
	local items:table = {};
	for i, id in ipairs( SR_BUTTON_IDS ) do
		local button:table = Controls[ id ];
		if button ~= nil and not button:IsHidden() then
			local label:string = SRA_Text( button:GetTextControl() );
			local callback = ( i == 1 ) and function() OnButton1(); end or function() OnButton2(); end;
			table.insert( items, { id = id, label = label, callback = callback } );
		end
	end
	return items;
end

local function SRA_IndexOf( items:table )
	for i, item in ipairs( items ) do
		if item.id == m_srFocusId then return i; end
	end
	return 1;
end

-- "Name, 1 of 2"; the single OK button of the no-choice variant has no count
local function SRA_ItemText( items:table, index:number )
	local text:string = items[ index ].label;
	if #items > 1 then text = text .. ", " .. index .. " of " .. #items; end
	return text;
end

-- the game's header text is upper case ("CHOOSE ARTIFACT"): spoken as a sentence
local function SRA_Sentence( text:string )
	text = string.lower( text );
	return ( string.gsub( text, "^%l", string.upper ) );
end

-- Enter / Space act on KeyUp only after their KeyDown reached the popup: the KeyUp of the key that opened it must not choose unheard
local m_srKeyDown		:table = {};

local function SRA_Trim( text:string )
	return ( string.gsub( text, "[%s%.!:;,]+$", "" ) );
end

-- Explanation and era (what Space repeats)
local function SRA_Details()
	local parts:table = {};
	for _, control in ipairs( { Controls.Explanation, Controls.EraString } ) do
		local text:string = SRA_Trim( SRA_Text( control ) );
		if text ~= "" then table.insert( parts, text ); end
	end
	return table.concat( parts, ". " );
end

-- Title, explanation, era, choice header (each once, a part that repeats an earlier one is dropped), then the focused button.
-- Called by SRA_Display after the display is set up (a test reaches it without an archaeologist).
function SRAnnounceOpen()
	local items:table = SRA_Items();
	if items[ 1 ] == nil then return; end
	m_srFocusId = items[ 1 ].id;
	m_srKeyDown = {};
	local title:string = SRA_Sentence( SRA_Trim( SRA_Text( Controls.PanelHeader ) ) );
	if title ~= "" then OutputMessageToScreenReader( title, true ); end
	local said:string = string.lower( title );
	local parts:table = {};
	for _, control in ipairs( { Controls.Explanation, Controls.EraString, Controls.ChoiceHeader } ) do
		local text:string = SRA_Trim( SRA_Text( control ) );
		local lower:string = string.lower( text );
		if text ~= "" and not string.find( said, lower, 1, true ) then
			table.insert( parts, text );
			said = said .. " | " .. lower;
		end
	end
	if #parts > 0 then OutputMessageToScreenReader( table.concat( parts, ". " ) .. ".", true ); end
	local text:string = SRA_ItemText( items, 1 );
	if #items == 1 then text = text .. ". " .. SRKey( "Enter" ) .. " confirms"; end
	OutputMessageToScreenReader( text, true );
end

local function SRA_Move( step:number, absolute:string )
	local items:table = SRA_Items();
	if #items == 0 then return; end
	local index:number = SRA_IndexOf( items );
	if absolute == "home" then index = 1;
	elseif absolute == "end" then index = #items;
	else
		index = index + step;
		if index < 1 then index = #items; end
		if index > #items then index = 1; end
	end
	m_srFocusId = items[ index ].id;
	OutputMessageToScreenReader( SRA_ItemText( items, index ) );
end

local function SRA_Activate()
	local items:table = SRA_Items();
	if #items == 0 then return; end
	local item:table = items[ SRA_IndexOf( items ) ];
	if #items == 1 then
		OutputMessageToScreenReader( "Artifact received" );
	else
		OutputMessageToScreenReader( "Artifact from " .. item.label .. " chosen" );
	end
	item.callback();		-- what a click does: the operation, then the popup hides (the key is consumed by the caller)
end

local function SRA_Escape()
	local items:table = SRA_Items();
	if #items == 1 then
		OutputMessageToScreenReader( "Take the artifact first. " .. SRKey( "Enter" ) .. " confirms" );
	else
		OutputMessageToScreenReader( "Choose an artifact first. " .. SRKey( "Enter" ) .. " takes the focused one" );
	end
end

-- true when the key was consumed (all keys are, while the popup is shown)
function SRA_HandleInput( pInputStruct:table )
	if ContextPtr:IsHidden() then return false; end
	local input:table = Gamepad.WrapInput( pInputStruct );
	local msg:number = input:GetMessageType();
	if msg ~= KeyEvents.KeyDown and msg ~= KeyEvents.KeyUp then return false; end
	local key = input:GetKey();
	if input:IsShiftDown() or input:IsAltDown() then return true; end
	local isDown:boolean = ( msg == KeyEvents.KeyDown );
	if key == Keys.VK_RETURN or key == Keys.VK_SPACE then
		if isDown then
			m_srKeyDown[ key ] = true;
		elseif m_srKeyDown[ key ] then
			m_srKeyDown[ key ] = nil;
		else
			return true;		-- a KeyUp without its KeyDown: swallowed, does nothing
		end
	end
	local action = nil;
	if input:IsControlDown() then
		if key == Keys.VK_TAB and isDown then action = function() SRA_Move( -1 ); end end		-- LB on the pad
	elseif key == Keys.VK_UP or key == Keys.VK_LEFT then	if isDown then action = function() SRA_Move( -1 ); end end
	elseif key == Keys.VK_DOWN or key == Keys.VK_RIGHT or key == Keys.VK_TAB then	if isDown then action = function() SRA_Move( 1 ); end end
	elseif key == Keys.VK_HOME then	if isDown then action = function() SRA_Move( 0, "home" ); end end
	elseif key == Keys.VK_END then	if isDown then action = function() SRA_Move( 0, "end" ); end end
	elseif key == Keys.VK_RETURN then	if not isDown then action = SRA_Activate; end
	elseif key == Keys.VK_SPACE then	if not isDown then action = function() OutputMessageToScreenReader( SRA_Details() ); end end
	elseif key == Keys.VK_ESCAPE then	if not isDown then action = SRA_Escape; end
	end
	if action ~= nil then
		local ok:boolean, err = pcall( action );
		if not ok then print( "ChooseArtifact error: " .. tostring( err ) ); end
	end
	return true;
end

-- event announcements wait while the popup is up (released on every way it hides)
local function SRA_OnShow()
	m_srKeyDown = {};
	LuaEvents.SRA_SpeechHold( "ChooseArtifact", true, "/InGame/FakePopups/" .. ContextPtr:GetID() );
end

local function SRA_OnHide()
	LuaEvents.SRA_SpeechHold( "ChooseArtifact", false );
end
-- End ScreenReaderAccess mod change

function OnOpen()

	local localPlayer = Players[Game.GetLocalPlayer()];
	if (localPlayer == nil) then
		return;
	end

	local pkArchaeologist = localPlayer:GetUnits():GetNextExtractingArchaeologist();
	if pkArchaeologist == nil then
		return;
	end

	local pkUnitArchaeology = pkArchaeologist:GetArchaeology();

	local iIndex = pkUnitArchaeology:GetArtifactIndex();
	local kObject = Game.GetArtifactByIndex(iIndex);

	if kObject == nil then
		return;
	end

	g_ActingPlayerID = kObject.ActingPlayerID;
	g_TargetPlayerID = kObject.TargetPlayerID;

	SRA_Display( kObject, pkArchaeologist:GetName() );		-- ScreenReaderAccess mod change: the display part is a function of its own
end

-- ScreenReaderAccess mod change: was the rest of OnOpen; also called by the regression test with fake data
function SRA_Display( kObject:table, szArchaeologistName:string )

	local szExplanationString;
	local bNoChoice = false;
	if (kObject.Type == 0) then
	    szExplanationString = "LOC_CHOOSE_ARTIFACT_EXPLANATION_NO_TYPE";
	elseif (kObject.Type == 1) then
	    szExplanationString = "LOC_CHOOSE_ARTIFACT_EXPLANATION_GOODY_HUT";
		bNoChoice = true;
	elseif (kObject.Type == 2) then
	    szExplanationString = "LOC_CHOOSE_ARTIFACT_EXPLANATION_BARBARIAN_CAMP";
		bNoChoice = true;
	elseif (kObject.Type == 3) then
	    szExplanationString = "LOC_CHOOSE_ARTIFACT_EXPLANATION_BATTLE_FOUGHT";
	elseif (kObject.Type == 4) then
	    szExplanationString = "LOC_CHOOSE_ARTIFACT_EXPLANATION_SHIP_SUNK";
	elseif (kObject.Type == 5) then
	    szExplanationString = "LOC_CHOOSE_ARTIFACT_EXPLANATION_HEROIC_RELIC";
		bNoChoice = true;
	end

	local szEraName = GameInfo.Eras[kObject.ActingPlayerEra].Name;
	Controls.EraString:LocalizeAndSetText("LOC_CHOOSE_ARTIFACT_ERA_STRING", szEraName);

	if (bNoChoice == true) then
		local pActingPlayerConfig :table = PlayerConfigurations[kObject.ActingPlayerID];
		Controls.Button1:LocalizeAndSetText("LOC_CHOOSE_ARTIFACT_OK_BUTTON");
		Controls.Button2:SetHide(true);
		Controls.Explanation:LocalizeAndSetText(szExplanationString, szArchaeologistName, pActingPlayerConfig:GetPlayerName());
		Controls.ChoiceHeader:LocalizeAndSetText("LOC_CHOOSE_ARTIFACT_NO_CHOICE", pActingPlayerConfig:GetPlayerName());
		Controls.PanelHeader:LocalizeAndSetText("LOC_CHOOSE_ARTIFACT_NO_CHOICE_HEADER");
	else
		local pActingPlayerConfig :table = PlayerConfigurations[kObject.ActingPlayerID];
		local pTargetPlayerConfig :table = PlayerConfigurations[kObject.TargetPlayerID];
		Controls.Button1:LocalizeAndSetText(pActingPlayerConfig:GetPlayerName());
		Controls.Button2:SetHide(false);
		Controls.Button2:LocalizeAndSetText(pTargetPlayerConfig:GetPlayerName());
		Controls.Explanation:LocalizeAndSetText(szExplanationString, szArchaeologistName, pActingPlayerConfig:GetPlayerName(), pTargetPlayerConfig:GetPlayerName());
		Controls.ChoiceHeader:LocalizeAndSetText("LOC_CHOOSE_ARTIFACT_MAKE_CHOICE");
		Controls.PanelHeader:LocalizeAndSetText("LOC_CHOOSE_ARTIFACT_HEADER");
    end
	Controls.ContentStack:CalculateSize();
	Controls.ContentStack:ReprocessAnchoring();
	Controls.ButtonStack:CalculateSize();
	Controls.ButtonStack:ReprocessAnchoring();
	Controls.ChooseArtifactPanel:ReprocessAnchoring();
	ContextPtr:SetHide(false);
	Controls.PopupAlphaIn:SetToBeginning();
	Controls.PopupAlphaIn:Play();
	Controls.PopupSlideIn:SetToBeginning();
	Controls.PopupSlideIn:Play();
	SRAnnounceOpen();		-- ScreenReaderAccess mod change
end
function OnButton1()
	local tParameters = {};
	tParameters[PlayerOperations.PARAM_PLAYER_ONE] = g_ActingPlayerID;
	UI.RequestPlayerOperation( Game.GetLocalPlayer(), PlayerOperations.CHOOSE_ARTIFACT_PLAYER, tParameters);
	ContextPtr:SetHide(true);
end
function OnButton2()
	local tParameters = {};
	tParameters[PlayerOperations.PARAM_PLAYER_ONE] = g_TargetPlayerID;
	UI.RequestPlayerOperation( Game.GetLocalPlayer(), PlayerOperations.CHOOSE_ARTIFACT_PLAYER, tParameters);
	ContextPtr:SetHide(true);
end

-- ===========================================================================
function Initialize()
	Controls.Button1:RegisterCallback(Mouse.eLClick, OnButton1);
	Controls.Button2:RegisterCallback(Mouse.eLClick, OnButton2);
	SRListen( LuaEvents.NotificationPanel_OpenArtifactPanel, OnOpen );		-- ScreenReaderAccess mod change (was .Add)
	-- ScreenReaderAccess mod change
	ContextPtr:SetInputHandler( SRA_HandleInput, true );		-- modal: the popup has no close and the map keys must not reach the hub
	ContextPtr:SetShowHandler( SRA_OnShow );
	ContextPtr:SetHideHandler( SRA_OnHide );
	ContextPtr:SetShutdown( function() SRUnlistenAll(); end );
	print( "ChooseArtifact: ScreenReaderAccess copy loaded" );
end
Initialize();
