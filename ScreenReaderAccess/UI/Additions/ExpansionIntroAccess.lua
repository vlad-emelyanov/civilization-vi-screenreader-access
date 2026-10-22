-- Copyright 2017-2018 (c) Firaxis Games

include( "KeyboardNavigation" );
include( "ScreenReader" );

-- ===========================================================================
--	CONSTANTS
-- ===========================================================================
-- Screen reader: accessible copy of the DLC's ExpansionIntro popup (UI/Additions/ExpansionIntro.lua of Expansion1 and
-- Expansion2). The DLC context cannot be replaced by a mod (its script is resolved by name and the DLC's file wins over
-- an ImportFiles/ReplaceUIScript of ours), so this is a second context, ExpansionIntroAccess, that shows this popup
-- instead: the DLC's own context still queues its popup (it also saves the "seen" flag and owns the options), and this
-- context then finds it (ContextPtr:LookUpControl) and dequeues it before showing its own copy. No option is changed
-- in memory or on disk by this context except the player's own "don't show again" checkbox. Rise and Fall
-- (XP1) constants are kept here too, selected by the game's ruleset.
local IS_XP1			:boolean = GameConfiguration.GetRuleSet() == "RULESET_EXPANSION_1";
local EXPANSION_NAME_KEY:string = IS_XP1 and "LOC_EXPANSION1_NAME" or "LOC_EXPANSION2_NAME";
local OPTIONS_HIDE_KEY	:string = IS_XP1 and "HideXP1FeaturesScreen" or "HideXP2FeaturesScreen";

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
local m_waitForDlc:boolean = false;		-- Screen reader: the DLC context is expected to show its popup; replace it with ours when it does
local m_waitIdles:number = 0;			-- UIIdle ticks spent waiting after the load screen closed
local m_loadScreenClosed:boolean = true;
local m_fromMenu:boolean = false;		-- the pending replacement was requested from the game menu
local m_dlcContext = nil;
local m_pendingShow:boolean = false;	-- The popup was queued while the load screen was up, announce it once it closes
local MAX_WAIT_IDLES:number = 120;
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
-- Screen reader: the DLC's own copy of this popup (inaccessible) is a sibling context; find it once.
function GetDlcContext()
	if m_dlcContext == nil then
		m_dlcContext = ContextPtr:LookUpControl( "/InGame/ExpansionIntro" );
		if m_dlcContext == nil then
			print( "ExpansionIntroAccess: DLC context /InGame/ExpansionIntro not found" );
		end
	end
	return m_dlcContext;
end

-- Replace the DLC's popup by ours if it is showing. Returns true when it did.
function ReplaceDlcPopup()
	local dlc = GetDlcContext();
	if dlc == nil or dlc:IsHidden() then
		return false;
	end
	UIManager:DequeuePopup( dlc );
	dlc:SetHide( true );

	m_PageIndex = 1;
	m_keyNavFocus = "next";
	Controls.DontShowAgain:SetCheck( Options.GetUserOption("Tutorial", OPTIONS_HIDE_KEY) == 1 );
	Realize();
	if m_fromMenu then
		UIManager:QueuePopup( ContextPtr, PopupPriority.Current );
	else
		UIManager:QueuePopup( ContextPtr, PopupPriority.TutorialHigh );
	end
	if m_loadScreenClosed then
		KeyNavAnnouncePage( true, false );
	else
		m_pendingShow = true;
	end
	return true;
end

-- ===========================================================================
function OnLoadGameViewStateDone()
	-- The DLC context decides (ruleset, seen/hide options, turn) whether to show its popup; just watch for it.
	m_waitForDlc = true;
	m_waitIdles = 0;
	m_fromMenu = false;
	m_loadScreenClosed = false;
	ContextPtr:RequestRefresh();
end

-- ===========================================================================
function OnLoadScreenClose()
	m_loadScreenClosed = true;
	if m_waitForDlc and ReplaceDlcPopup() then m_waitForDlc = false; end
	if m_pendingShow then
		m_pendingShow = false;
		KeyNavAnnouncePage( true, false );
	end
end

-- ===========================================================================
function OnShowFromMenuRequest()
	m_waitForDlc = true;
	m_waitIdles = 0;
	m_fromMenu = true;
	m_loadScreenClosed = true;
	ContextPtr:RequestRefresh();
end

-- ===========================================================================
-- (Events.UIIdle did not fire reliably, and a hidden context gets no update: RequestRefresh runs the refresh handler next frame.)
function OnRefresh()
	if not m_waitForDlc then return; end
	if ReplaceDlcPopup() then
		m_waitForDlc = false;
		return;
	end
	if m_loadScreenClosed then m_waitIdles = m_waitIdles + 1; end
	if m_waitIdles > MAX_WAIT_IDLES then
		m_waitForDlc = false;
	else
		ContextPtr:RequestRefresh();
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
-- Hot reload: remove the listeners, or the old instance keeps reacting next to the new one.
function OnShutdown()
	Events.LoadGameViewStateDone.Remove( OnLoadGameViewStateDone );
	Events.LoadScreenClose.Remove( OnLoadScreenClose );
	LuaEvents.InGameTopOptionsMenu_ShowExpansionIntro.Remove( OnShowFromMenuRequest );
	LuaEvents.DiplomacyActionView_HideIngameUI.Remove( HideIfVisible );
end

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

	Controls.DontShowAgain:SetCheck(Options.GetUserOption("Tutorial", OPTIONS_HIDE_KEY) == 1);
	Controls.DontShowAgain:RegisterCheckHandler(function(bCheck)
		local value = bCheck and 1 or 0;
		Options.SetUserOption("Tutorial", OPTIONS_HIDE_KEY, value);
		Options.SaveOptions();
	end);

	Events.LoadGameViewStateDone.Add( OnLoadGameViewStateDone );
	Events.LoadScreenClose.Add( OnLoadScreenClose );
	ContextPtr:SetRefreshHandler( OnRefresh );

	-- The game menu's welcome entry also reaches the DLC's popup: swap that one for ours too.
	LuaEvents.InGameTopOptionsMenu_ShowExpansionIntro.Add( OnShowFromMenuRequest );
	LuaEvents.DiplomacyActionView_HideIngameUI.Add( HideIfVisible );
	ContextPtr:SetShutdown( OnShutdown );
end
Initialize();