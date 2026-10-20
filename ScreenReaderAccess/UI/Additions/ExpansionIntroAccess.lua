-- Copyright 2017-2018 (c) Firaxis Games

include( "KeyboardNavigation" );
include( "ScreenReader" );

-- ===========================================================================
--	CONSTANTS
-- ===========================================================================
-- Screen reader: accessible copy of the DLC's ExpansionIntro popup (UI/Additions/ExpansionIntro.lua of Expansion1 and
-- Expansion2). The DLC context cannot be replaced by a mod (its script is resolved by name and the DLC's file wins over
-- an ImportFiles/ReplaceUIScript of ours), so this is a second context, ExpansionIntroAccess, that shows this popup
-- instead and keeps the DLC's own context from showing it at game start (see OnLoadGameViewStateDone). Rise and Fall
-- (XP1) constants are kept here too, selected by the game's ruleset.
local IS_XP1			:boolean = GameConfiguration.GetRuleSet() == "RULESET_EXPANSION_1";
local EXPANSION_NAME_KEY:string = IS_XP1 and "LOC_EXPANSION1_NAME" or "LOC_EXPANSION2_NAME";
local RULESET_TYPE		:string = IS_XP1 and "RULESET_EXPANSION_1" or "RULESET_EXPANSION_2";
local OPTIONS_SEEN_KEY	:string = IS_XP1 and "HasSeenXP1FeaturesScreen" or "HasSeenXP2FeaturesScreen";
local OPTIONS_HIDE_KEY	:string = IS_XP1 and "HideXP1FeaturesScreen" or "HideXP2FeaturesScreen";

local MIN_TUTORIAL_LEVEL = IS_XP1 and TutorialLevel.LEVEL_NEW_TO_XP1 or TutorialLevel.LEVEL_NEW_TO_XP2;

local INTRO_ILLUSTRATIONS:table = IS_XP1 and {
	"XP1Intro_Diagram_1",
	"XP1Intro_Diagram_2",
	"XP1Intro_Diagram_3",
	"XP1Intro_Diagram_4",
	"XP1Intro_Diagram_5",
	"XP1Intro_Diagram_6",
	"XP1Intro_Diagram_7",
	"XP1Intro_Diagram_8",
	"XP1Intro_Diagram_9",
} or {
	"XP2Intro_Diagram_1",
	"XP2Intro_Diagram_2",
	"XP2Intro_Diagram_3",
	"XP2Intro_Diagram_11",
	"XP2Intro_Diagram_12",
	"XP2Intro_Diagram_4",
	"XP2Intro_Diagram_5",
	"XP2Intro_Diagram_6",
	"XP2Intro_Diagram_7",
	"XP2Intro_Diagram_8",
	"XP2Intro_Diagram_9",
	"XP2Intro_Diagram_10"
};

local NUM_PAGES = #INTRO_ILLUSTRATIONS;

local INTRO_DESCRIPTIONS:table = IS_XP1 and {
	"LOC_TUTORIAL_XP1_INTRO_WELCOME",
	"LOC_TUTORIAL_XP1_INTRO_ERAS",
	"LOC_TUTORIAL_XP1_INTRO_AGES",
	"LOC_TUTORIAL_XP1_INTRO_LOYALTY",
	"LOC_TUTORIAL_XP1_INTRO_GOVERNORS",
	"LOC_TUTORIAL_XP1_INTRO_ALLIANCES",
	"LOC_TUTORIAL_XP1_INTRO_EMERGENCIES",
	"LOC_TUTORIAL_XP1_INTRO_CITYBANNER",
	"LOC_TUTORIAL_XP1_INTRO_END",
} or {
	"LOC_TUTORIAL_XP2_INTRO_WELCOME",
	"LOC_TUTORIAL_XP2_INTRO_WORLD_CONGRESS",
	"LOC_TUTORIAL_XP2_INTRO_FAVOR",
	"LOC_TUTORIAL_XP2_INTRO_DIPLO_VICTORY",
	"LOC_TUTORIAL_XP2_INTRO_GRIEVANCES",
	"LOC_TUTORIAL_XP2_INTRO_ENVIRONMENT",
	"LOC_TUTORIAL_XP2_INTRO_VOLCANOES",
	"LOC_TUTORIAL_XP2_INTRO_GEOTHERMAL",
	"LOC_TUTORIAL_XP2_INTRO_STRATEGIC_RESOURCES",
	"LOC_TUTORIAL_XP2_INTRO_RESOURCES",
	"LOC_TUTORIAL_XP2_INTRO_MORE",
	"LOC_TUTORIAL_XP2_INTRO_END",
};

local INTRO_DESCRIPTIONS_DETAILS:table = IS_XP1 and {
	"", "", "", "", "", "", "", "",
	"LOC_TUTORIAL_XP1_INTRO_END_DETAILS_1",
} or {
	"",
	"LOC_TUTORIAL_XP2_INTRO_WORLD_CONGRESS_DETAILS",
	"LOC_TUTORIAL_XP2_INTRO_FAVOR_DETAILS",
	"LOC_TUTORIAL_XP2_INTRO_DIPLO_VICTORY_DETAILS",
	"LOC_TUTORIAL_XP2_INTRO_GRIEVANCES_DETAILS",
	"LOC_TUTORIAL_XP2_INTRO_ENVIRONMENT_DETAILS",
	"",
	"",
	"LOC_TUTORIAL_XP2_INTRO_STRATEGIC_RESOURCES_DETAILS",
	"LOC_TUTORIAL_XP2_INTRO_RESOURCES_DETAILS",
	"",
	"LOC_TUTORIAL_XP2_INTRO_END_DETAILS_1",
};

local NEXT_BUTTON_TEXT = Locale.Lookup("LOC_XP1_INTRO_NEXT");
local CONTINUE_BUTTON_TEXT = Locale.Lookup("LOC_XP1_INTRO_CONTINUE");

-- ===========================================================================
--	MEMBERS
-- ===========================================================================
local m_PageIndex:number = 1;
local m_realHide:number = 0;			-- Screen reader: the player's saved "don't show again" value while the DLC's popup is being suppressed
local m_hideSuppressed:boolean = false;	-- OPTIONS_HIDE_KEY is temporarily 1 (in memory only, never saved)
local m_pendingShow:boolean = false;	-- The popup was queued at LoadGameViewStateDone, announce it once the load screen closes
local m_keyNavFocus:string = "next";	-- Screen reader: key of the focused control ("previous", "next", "dontshow", "close")

-- ===========================================================================
--	Screen reader / keyboard navigation
-- ===========================================================================
function KeyNavItems()
	local items:table = {};
	if not Controls.Previous:IsHidden() then table.insert( items, { Key="previous", Control=Controls.Previous, Callback=OnPrevious } ); end
	table.insert( items, { Key="next", Control=Controls.Next, Callback=OnNext } );
	table.insert( items, { Key="dontshow", Control=Controls.DontShowAgain, Callback=KeyNavToggleDontShow } );
	table.insert( items, { Key="close", Control=Controls.Close, Callback=OnClose } );
	return items;
end

function KeyNavLabel( item:table )
	if item.Key == "dontshow" then
		return Locale.Lookup("LOC_XP_INTRO_HIDETHIS") .. ": " .. (Controls.DontShowAgain:IsChecked() and "checked" or "unchecked");
	elseif item.Key == "close" then
		return Locale.Lookup("LOC_CLOSE");
	end
	return CleanTextForSpeech( item.Control:GetText() );
end

function KeyNavAnnounceFocus( noInterrupt:boolean )
	local items:table = KeyNavItems();
	for i, item in ipairs(items) do
		if item.Key == m_keyNavFocus then
			OutputMessageToScreenReader( KeyNavLabel(item) .. ", " .. i .. " of " .. #items, noInterrupt );
			return;
		end
	end
end

-- The page text: description, then the details box when this page has one.
function KeyNavPageText()
	local text:string = CleanTextForSpeech( Controls.Description:GetText() );
	if not Controls.FrameDeco:IsHidden() then
		text = text .. " " .. CleanTextForSpeech( Controls.Description2:GetText() );
	end
	text = string.gsub( text, "%.[%s%.]*%.", "." );	-- [NEWLINE][NEWLINE] became ". . "
	return text;
end

function KeyNavAnnouncePage( includeTitle:boolean, noInterrupt:boolean )
	local text:string = "Page " .. m_PageIndex .. " of " .. NUM_PAGES .. ". " .. KeyNavPageText();
	if includeTitle then
		text = Locale.Lookup(EXPANSION_NAME_KEY) .. ". " .. text;
	end
	OutputMessageToScreenReader( text, noInterrupt );
	KeyNavAnnounceFocus( true );
end

function KeyNavMoveFocus( delta:number )
	local items:table = KeyNavItems();
	local index:number = 1;
	for i, item in ipairs(items) do
		if item.Key == m_keyNavFocus then index = i; end
	end
	index = ((index - 1 + delta + #items) % #items) + 1;
	m_keyNavFocus = items[index].Key;
	KeyNavAnnounceFocus( false );
end

function KeyNavToggleDontShow()
	local value:boolean = not Controls.DontShowAgain:IsChecked();
	Controls.DontShowAgain:SetCheck(value);
	Options.SetUserOption("Tutorial", OPTIONS_HIDE_KEY, value and 1 or 0);
	Options.SaveOptions();
	KeyNavAnnounceFocus( false );
end

function KeyNavActivate()
	for _, item in ipairs( KeyNavItems() ) do
		if item.Key == m_keyNavFocus then
			item.Callback();
			return;
		end
	end
end



-- ===========================================================================
function Realize()
	Controls.Illustration:SetTexture(INTRO_ILLUSTRATIONS[m_PageIndex]);
	Controls.Description:SetText(Locale.Lookup(INTRO_DESCRIPTIONS[m_PageIndex]));

	-- Show detail screens or hide box if we don't have any for this page
	if INTRO_DESCRIPTIONS_DETAILS[m_PageIndex] ~= "" then
		Controls.FrameDeco:SetHide(false);
		Controls.Description2:SetText(Locale.Lookup(INTRO_DESCRIPTIONS_DETAILS[m_PageIndex]));
	else
		Controls.FrameDeco:SetHide(true);
	end

	Controls.Next:SetText(m_PageIndex == NUM_PAGES and CONTINUE_BUTTON_TEXT or NEXT_BUTTON_TEXT);
	Controls.Previous:SetHide(m_PageIndex == 1);
	Controls.ButtonStack:CalculateSize();
end

-- Screen reader: after a page change the focus stays on the pressed button if it is still there (Previous is hidden on page 1).
function KeyNavAfterPageChange()
	if m_keyNavFocus == "previous" and Controls.Previous:IsHidden() then m_keyNavFocus = "next"; end
	KeyNavAnnouncePage( false, false );
end

-- ===========================================================================
function OnShow()
	m_PageIndex = 1;
	m_keyNavFocus = "next";
	Realize();
	UIManager:QueuePopup(ContextPtr, PopupPriority.TutorialHigh);
	KeyNavAnnouncePage( true, false );
end

-- ===========================================================================
function OnShowFromMenu()
	m_PageIndex = 1;
	m_keyNavFocus = "next";
	Realize();
	UIManager:QueuePopup(ContextPtr, PopupPriority.Current);
	KeyNavAnnouncePage( true, false );
end

-- ===========================================================================
function OnClose()
	UIManager:DequeuePopup(ContextPtr);	
end

-- ===========================================================================
function OnNext()
	if m_PageIndex >= NUM_PAGES then
		OnClose();
	else
		m_PageIndex = math.min(m_PageIndex + 1, NUM_PAGES);
		Realize();
		KeyNavAfterPageChange();
	end
end

-- ===========================================================================
function OnPrevious()
	m_PageIndex = math.max(1, m_PageIndex - 1);
	Realize();
	KeyNavAfterPageChange();
end

-- ===========================================================================
function OnLoadGameViewStateDone()

	local isRuleSet		:boolean = GameConfiguration.GetRuleSet() == RULESET_TYPE;
	local isAutoPlayMode:boolean = (Game.GetLocalPlayer() == -1);
	local hasSeenScreen	:boolean = Options.GetUserOption("Tutorial", OPTIONS_SEEN_KEY) == 1;
	local hideScreen	:boolean = m_realHide == 1;
	local showScreen	:boolean = isRuleSet
						and not GameConfiguration.IsNetworkMultiplayer()
						and not isAutoPlayMode
						and (not hasSeenScreen or UserConfiguration.TutorialLevel() <= MIN_TUTORIAL_LEVEL ) 
						and not hideScreen;

	if showScreen and Game.GetCurrentGameTurn() == GameConfiguration.GetStartTurn() then
		-- The "seen" flag is saved in OnLoadScreenClose, once the saved "don't show again" value is back in place.
		Options.SetUserOption("Tutorial", OPTIONS_SEEN_KEY, 1);
		m_pendingShow = true;
		m_PageIndex = 1;
		m_keyNavFocus = "next";
		Realize();
		UIManager:QueuePopup(ContextPtr, PopupPriority.TutorialHigh);
	end
end

-- ===========================================================================
-- Screen reader: by now the DLC's context has handled LoadGameViewStateDone (and found OPTIONS_HIDE_KEY set, so it did
-- not show its own copy of this popup): put the player's value back, save, and announce the popup.
function OnLoadScreenClose()
	if m_hideSuppressed then
		Options.SetUserOption("Tutorial", OPTIONS_HIDE_KEY, m_realHide);
		m_hideSuppressed = false;
		Options.SaveOptions();
	end
	if m_pendingShow then
		m_pendingShow = false;
		KeyNavAnnouncePage( true, false );
	end
end

-- ===========================================================================
function OnInput( pInputStruct:table )
	local key = pInputStruct:GetKey();
	local type = pInputStruct:GetMessageType();
	if type == KeyEvents.KeyUp then
		local ok, err = xpcall( function() KeyNavKeyHandler( key ); end, KeyNavErrorHandler );
		if not ok then print( "ExpansionIntro input error: " .. tostring(err) ); end
	end
	return true; -- consume all input
end

-- Screen reader: Up/Down/Tab move between the controls, Enter/Space activate, Escape closes (as the original does).
function KeyNavKeyHandler( key:number )
	if key == Keys.VK_ESCAPE then
		HideIfVisible();
	elseif key == Keys.VK_UP then
		KeyNavMoveFocus( -1 );
	elseif key == Keys.VK_DOWN or key == Keys.VK_TAB then
		KeyNavMoveFocus( 1 );
	elseif key == Keys.VK_RETURN or key == Keys.VK_SPACE then
		KeyNavActivate();
	end
end

-- ===========================================================================
function HideIfVisible()
	if ContextPtr:IsVisible() then
		OnClose();
	end
end


-- ===========================================================================
function Initialize()
	ContextPtr:SetInputHandler( OnInput, true );

	Controls.Close:RegisterCallback(Mouse.eLClick, OnClose);
	Controls.Next:RegisterCallback(Mouse.eLClick, OnNext);
	Controls.Previous:RegisterCallback(Mouse.eLClick, OnPrevious);

	Controls.Close:RegisterCallback(Mouse.eMouseEnter, function()
		UI.PlaySound("Main_Menu_Mouse_Over"); end);
	Controls.Next:RegisterCallback(Mouse.eMouseEnter, function()
		UI.PlaySound("Main_Menu_Mouse_Over"); end);
	Controls.Previous:RegisterCallback(Mouse.eMouseEnter, function()
		UI.PlaySound("Main_Menu_Mouse_Over"); end);

	m_realHide = Options.GetUserOption("Tutorial", OPTIONS_HIDE_KEY);
	if m_realHide ~= 1 then m_realHide = 0; end
	Controls.DontShowAgain:SetCheck(m_realHide == 1);
	Controls.DontShowAgain:RegisterCheckHandler(function(bCheck)
		local value = bCheck and 1 or 0;
		Options.SetUserOption("Tutorial", OPTIONS_HIDE_KEY, value);
		Options.SaveOptions();
	end);

	Events.LoadGameViewStateDone.Add( OnLoadGameViewStateDone );
	Events.LoadScreenClose.Add( OnLoadScreenClose );

	-- Make the DLC's context see "don't show again" while the game loads (this context is created before it). Not saved.
	if GameConfiguration.GetRuleSet() == RULESET_TYPE and m_realHide ~= 1 then
		Options.SetUserOption("Tutorial", OPTIONS_HIDE_KEY, 1);
		m_hideSuppressed = true;
	end

	-- Not hooked: LuaEvents.InGameTopOptionsMenu_ShowExpansionIntro (the game menu's welcome entry) also reaches the DLC's
	-- own, inaccessible, popup; showing a second one on top of it would leave it open behind this one.
	LuaEvents.DiplomacyActionView_HideIngameUI.Add( HideIfVisible );
end
Initialize();