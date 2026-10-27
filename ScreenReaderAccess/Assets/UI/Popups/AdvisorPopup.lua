-- ===========================================================================
--	Popup that occurs with the tutorial system
-- ===========================================================================
include( "InstanceManager" );
include( "Civ6Common" ); -- IsTutorialRunning()
include( "KeyboardNavigation" );
include( "ScreenReader" );
include( "SRListen" );	-- ScreenReaderAccess mod: removable listeners


-- ===========================================================================
--	Action Hotkeys
-- ===========================================================================
local m_actionHotkeyContinue	:number = Input.GetActionId("TutorialContinue");
local m_actionHotkeyContinueAlt	:number = Input.GetActionId("TutorialContinueAlt");
local m_actionHotkeyShowMore	:number = Input.GetActionId("TutorialShowMore");



-- ===========================================================================
--	CONSTANTS
-- ===========================================================================
local RELOAD_CACHE_ID	:string = "AdvisorPopup";

-- FIXME(asherburne): Move declaration of AdvisorItem to a location
-- available to both AdvisorPopup.lua and TutorialUIRoot.lua so it does
-- not have to be duplicated and kept in-sync.
hstructure AdvisorItem
	Message			: string;		-- TXT key to look up for advisor message (if raised via an advisor)
	MessageAudio	: string;		-- Name of the accompanying audio to play with the message.
	Image			: string;		-- (optional) Name of texture used in image.
	OptionsNum		: number;		-- Number of options.
	Button1Text		: string;		-- TXT key to look up for button 1
	Button2Text		: string;		-- " " " 2
	Button1Func		: ifunction;	-- Callback on button 1
	Button2Func		: ifunction;	-- " " " 2
	CalloutHeader	: string;		-- TXT key to look up for callout header
	CalloutBody		: string;		-- TXT key to look up for callout body
	PlotCallback	: ifunction;	-- Function to return the ID of a world plot to which dialog will be anchored
	ShowPortrait	: boolean;		-- Whether or not the advisor portrait should appear in the dialog (expected when VO is played)
	UITriggers		: table;		-- IDs and/or Trigger names for the UI when advisor item is up.
end

-- ===========================================================================
--	MEMBERS
-- ===========================================================================
local m_dialogButtonIM		: table	= InstanceManager:new( "DialogButtonInstance", "DialogButton", Controls.ButtonStack );
local m_metaDialogButtonIM	: table	= InstanceManager:new( "DialogButtonInstance", "DialogButton", Controls.MetaButtonStack );
local ms_eventID			: number = 0;
local m_bTutorialEnabled	: boolean = true;
local m_currentItem			: AdvisorItem;		-- Currently only exists for hotloading
local m_isDiplomacyUp		: boolean = false;	-- Is the diplomacy system currently not showing
local m_hotkeyCallback		: ifunction = nil;
local m_kQueuedPopups		: table	 = {};
local m_kKeyNavButtons		: table	 = {};	-- Screen reader: { Label, Callback } for each button of the current advisor item
local m_keyNavFocus			: number = 1;
local m_isModalPopupUp		: boolean = false;	-- an InGamePopup is open above us (see OnInGamePopupShown)
local m_keyNavHotkeyFired	: boolean = false;	-- The continue hotkey already activated a button for the key press being released
local m_keyNavAnnouncement	: string = "";	-- Title and full text of the current item (Space reads it)
local m_keyNavSummary		: string = "";	-- Condensed announcement spoken when the item is shown

-- ===========================================================================
--	Screen reader / keyboard navigation
-- ===========================================================================
function KeyNavActivate( index:number )
	local entry :table = m_kKeyNavButtons[index];
	if entry ~= nil then
		entry.Callback();
	end
end

function KeyNavAnnounceFocus( noInterrupt:boolean )
	local entry :table = m_kKeyNavButtons[m_keyNavFocus];
	if entry ~= nil then
		local text :string = entry.Label;
		if #m_kKeyNavButtons > 1 then
			text = text .. ", " .. m_keyNavFocus .. " of " .. #m_kKeyNavButtons;
		end
		OutputMessageToScreenReader( text, noInterrupt );
	end
end

-- First sentence of a text, cut to about 25 words.
function KeyNavFirstSentence( text:string )
	local sentence :string = text;
	local stop :number = string.find( text, "[%.!%?]%s" );
	if stop ~= nil then sentence = string.sub( text, 1, stop - 1 ); end
	sentence = string.gsub( sentence, "[%.!%?]+$", "" );
	local words :table = {};
	for word in string.gmatch( sentence, "%S+" ) do table.insert( words, word ); end
	if #words > 25 then
		local cut :table = {};
		for i = 1, 25 do cut[i] = words[i]; end
		sentence = table.concat( cut, " " ) .. " ...";
	end
	return sentence;
end

-- Space: the full text, then the buttons.
function KeyNavAnnouncePopup( noInterrupt:boolean )
	local parts :table = {};
	for _, entry in ipairs( m_kKeyNavButtons ) do table.insert( parts, entry.Label ); end
	local text :string = m_keyNavAnnouncement;
	if #parts > 0 then text = string.gsub( text, "[%.%s]+$", "" ) .. ". Buttons: " .. table.concat( parts, ", " ); end
	if text ~= "" then
		OutputMessageToScreenReader( text, noInterrupt );
	end
end

function KeyNavMoveFocus( delta:number )
	local count :number = #m_kKeyNavButtons;
	if count == 0 then return; end
	m_keyNavFocus = ((m_keyNavFocus - 1 + delta + count) % count) + 1;
	KeyNavAnnounceFocus( false );
end

-- ===========================================================================
--	FUNCTIONS
-- ===========================================================================

function AddAdvisorButton( data:AdvisorItem, text:string, callbackFunc:ifunction, isHotkeyed:boolean )	

	local BUTTON_PADDING	:number = 40;
	local BUTTON_MIN_SIZE_X	:number = 200;

	local buttonInstance	:table;
	local buttonStackControl = Controls.ButtonStack;
	if data.ShowPortrait then
		buttonInstance = m_dialogButtonIM:GetInstance();
	else
		buttonInstance = m_metaDialogButtonIM:GetInstance();
		buttonStackControl = Controls.MetaButtonStack;
	end

	buttonInstance.DialogButton:SetText( text );	
	local sizeX :number = math.max( BUTTON_MIN_SIZE_X, buttonInstance.DialogButton:GetTextControl():GetSizeX() + BUTTON_PADDING );
	buttonInstance.DialogButton:SetSizeX( sizeX );	
	buttonInstance.DialogButton:RegisterCallback( Mouse.eLClick, 
		function() 
			OnHideAdvisorDialog(); 
			callbackFunc(data); 
		end );
	table.insert( m_kKeyNavButtons, { Label = CleanTextForSpeech( buttonInstance.DialogButton:GetText() ), Callback = 
		function() 
			-- Screen reader: short and interrupting, so whatever the next popup says replaces it.
			OutputMessageToScreenReader( "Closed" );
			OnHideAdvisorDialog(); 
			callbackFunc(data); 
		end } );

	if isHotkeyed then
		-- Screen reader: the continue hotkey (Enter/Space) activates the focused button, not just the first one.
		m_hotkeyCallback = 
		function() 
			if m_kKeyNavButtons[m_keyNavFocus] ~= nil then
				m_keyNavHotkeyFired = true;
				KeyNavActivate( m_keyNavFocus );
			else
				OnHideAdvisorDialog(); 
				callbackFunc(data); 
			end
		end
	end

	buttonStackControl:CalculateSize();
	buttonStackControl:ReprocessAnchoring();
end


-- ===========================================================================
function ShowAdvisorPopup( advisorData:AdvisorItem )

	m_currentItem = advisorData;	-- For hotloading

	local localPlayer = Game.GetLocalPlayer();
	if localPlayer == PlayerTypes.NONE then
		return;	-- Nobody there to click on it, just exit.
	end

	 m_dialogButtonIM:ResetInstances();
	 m_metaDialogButtonIM:ResetInstances();
	 m_kKeyNavButtons = {};
	 m_keyNavFocus = 1;
	 m_keyNavAnnouncement = "";
	 m_keyNavSummary = "";
	 m_keyNavHotkeyFired = false;

	if advisorData == nil then
		UI.DataError("Attempt to show advisor with NIL advisor data.");
		return;
	end

	local bHideAdvisor:boolean = ( advisorData.Button1Func == nil and advisorData.Button2Func == nil );

	local imageControl			:table = Controls.InfoImage;
	local contentStack			:table = Controls.WindowContentStack;
	local dialogWindowControl	:table = Controls.Window;
	local audio					:string= advisorData.MessageAudio;
	local buttonStack			:table = Controls.ButtonStack;

	if advisorData.ShowPortrait then
		Controls.AdvisorBase:SetHide( false );
		Controls.MetaBase:SetHide( true );
		Controls.InfoString:SetText( advisorData.Message );
		Controls.AdvisorPortrait:SetHide(false);
		Controls.AdvisorAnim:SetToBeginning();
		Controls.AdvisorAnim:Play();
		Controls.AdvisorAlpha:SetToBeginning();
		Controls.AdvisorAlpha:Play();
		Controls.AdvisorAlpha:RegisterEndCallback(
			function()
				UI.PlaySound("Alert_Advisor");
				if audio ~= nil and audio ~= "" then
					UI.PlaySound( audio );
				end
			end
		);
	else
		Controls.AdvisorBase:SetHide( true );
		Controls.MetaBase:SetHide( false );
		Controls.MetaInfoString:SetText( advisorData.Message );
		Controls.MetaAnim:SetToBeginning();
		Controls.MetaAnim:Play();
		Controls.MetaAlpha:SetToBeginning();
		Controls.MetaAlpha:Play();
		imageControl = Controls.MetaInfoImage;
		contentStack = Controls.MetaWindowContentStack;
		buttonStack = Controls.MetaButtonStack;
		dialogWindowControl = Controls.MetaWindow;
	end
	
	-- display an image if provided
	if advisorData.Image then
		imageControl:SetHide(false);
		imageControl:SetTexture( advisorData.Image );
	else
		imageControl:SetHide(true);
	end

	if advisorData.PlotCallback ~= nil then
		local plotID = advisorData.PlotCallback();
		local pX, pY = Map.GetPlotLocation(plotID);
		local worldX : number, worldY : number, worldZ : number = UI.GridToWorld(pX, pY);
		Controls.Anchor:SetWorldPositionVal(worldX, worldY, worldZ);
	end

	Controls.CalloutHeader:SetText( advisorData.CalloutHeader );
	Controls.CalloutBody:SetText( advisorData.CalloutBody );

	-- NIL functions?  Assume it just means to close and raise message back.
	if advisorData.Button1Func == nil then 
		advisorData.Button1Func = function() 
			LuaEvents.AdvisorPopup_ClearActive( advisorData ); 
		end 
	end
	if advisorData.Button2Func == nil then 
		advisorData.Button2Func = function() 
			LuaEvents.AdvisorPopup_ClearActive( advisorData ); 
		end 
	end

	-- Only create button if it has contents.
	if advisorData.Button1Text ~= nil then
		AddAdvisorButton( advisorData, advisorData.Button1Text, advisorData.Button1Func, true );		
	end
	if advisorData.Button2Text ~= nil then
		AddAdvisorButton( advisorData, advisorData.Button2Text, advisorData.Button2Func );
	end

	-- Screen reader: announce what is being shown (the advisor text, the tutorial callout) and the focused button.
	local srParts :table = {};
	local srSummary :string = "";
	if not bHideAdvisor then
		local title :string = "Advisor";
		if advisorData.ShowPortrait then title = CleanTextForSpeech( Controls.TitleText:GetText() ); end
		local body :string = CleanTextForSpeech( advisorData.ShowPortrait and Controls.InfoString:GetText() or Controls.MetaInfoString:GetText() );
		body = string.gsub( body, "%.[%s%.]*%.", "." );	-- [NEWLINE][NEWLINE] became ". . "
		table.insert( srParts, title .. ": " .. body );
		srSummary = title .. ": " .. KeyNavFirstSentence( body );
	end
	local calloutBody :string = "";
	if advisorData.CalloutBody ~= nil and advisorData.CalloutBody ~= "" then
		calloutBody = CleanTextForSpeech( Controls.CalloutBody:GetText() );
	end
	if string.find( calloutBody, "text not set", 1, true ) ~= nil then calloutBody = ""; end	-- Placeholder callouts (dev text) are not shown on screen
	if calloutBody ~= "" then
		local calloutHeader :string = "";
		if advisorData.CalloutHeader ~= nil and advisorData.CalloutHeader ~= "" then
			calloutHeader = CleanTextForSpeech( Controls.CalloutHeader:GetText() );
		end
		if calloutHeader ~= "" then calloutHeader = calloutHeader .. ". "; end
		table.insert( srParts, "Tutorial: " .. calloutHeader .. calloutBody );
		if srSummary == "" then srSummary = "Tutorial: " .. KeyNavFirstSentence( calloutHeader ~= "" and calloutHeader or calloutBody ); end
	end
	m_keyNavAnnouncement = table.concat( srParts, ". " );
	if srSummary ~= "" then
		m_keyNavSummary = srSummary .. ". " .. SRKey( "Space" ) .. " reads all, " .. SRKey( "Enter" ) .. " closes.";
		OutputMessageToScreenReader( m_keyNavSummary, false );
	end

	-- If there are any associated <tutorial> triggers... trigger them.
	for _,trigger in ipairs(advisorData.UITriggers) do	
		UITutorialManager:ShowControlsByID( trigger, false );	
	end

	UIManager:QueuePopup( ContextPtr, PopupPriority.Tutorial );

	-- Put a hold on the event so further events don't process
	ms_eventID = UI.ReferenceCurrentEvent();

	if advisorData.ShowPortrait then
		Controls.ButtonStack:ReprocessAnchoring();
	else
		Controls.MetaButtonStack:ReprocessAnchoring();
	end

	-- After all the buttons have been added and the dialog is finished being built, calculate the correct size of the dialog
	buttonStack:CalculateSize();
	contentStack:CalculateSize();
	local contentSize = math.max( contentStack:GetSizeY() + 60, 120 );
	dialogWindowControl:SetSizeY( contentSize );
	dialogWindowControl:ReprocessAnchoring();

	if bHideAdvisor then
		OnHideAdvisorDialog();
	end
    
end

-- ===========================================================================
function Close()
	m_currentItem = nil;	

	if ms_eventID ~= 0 then
		UI.ReleaseEventID(ms_eventID);
		ms_eventID = 0;
	end
	
	m_hotkeyCallback = nil;

	UIManager:DequeuePopup( ContextPtr );		
end

-- ===========================================================================
function OnHideAdvisorDialog()
	m_kKeyNavButtons = {};
	m_keyNavFocus = 1;
	m_keyNavHotkeyFired = false;
	-- If there are any associated <tutorial> triggers... trigger them.
	for _,trigger in ipairs(m_currentItem.UITriggers) do	
		UITutorialManager:HideControlsByID( trigger, false );	
	end

	if ms_eventID ~= 0 then
		UI.ReleaseEventID(ms_eventID);
		ms_eventID = 0;
	end
	
	m_hotkeyCallback = nil;
	
	-- If the tutorial is running, there will be another event to dequeue the dialog.
	-- It is possible that the tutorial system simply wants to hide the AdvisorBase and keep some other
	-- part of the tutorial popup visible.
	if not IsTutorialRunning() then
		UIManager:DequeuePopup( ContextPtr );		
	end

	-- If the advisor (AdvisorBase) is not showing, don't force active tutorial input mode,
	-- it may or may not still be active depending on if any controls are showing.
	UITutorialManager:SetActiveAlways( false );
	Controls.AdvisorBase:SetHide( true );
	Controls.MetaBase:SetHide( true );
end

-- ===========================================================================
-- Show the next advisor in the queue
function ShowNextQueuedPopup()

	-- Find first entry in table, display that, then remove it from the internal queue
	for i, entry in ipairs(m_kQueuedPopups) do
		ShowAdvisorPopup(entry);
		table.remove(m_kQueuedPopups, i);
		break;
	end

end

-- ===========================================================================
-- Show the supplied advisor if possible, else queue it.
function ShowOrQueuePopup(advisorData:AdvisorItem)

	-- ScreenReaderAccess mod change: while the diplomacy scene is open the advisor is invisible and keys go to it, so the player was stuck. Hold it until the scene closes (OnDiploSceneClosed).
	if m_isDiplomacyUp then
		table.insert(m_kQueuedPopups, advisorData);
	elseif UI.CanShowPopup(PopupPriority.Tutorial) or IsTutorialRunning() then
		ShowAdvisorPopup(advisorData);
	else
		-- Add to queue
		table.insert(m_kQueuedPopups, advisorData);
	end

end

-- ===========================================================================
function OnUIIdle()
	-- The UI is idle, are we waiting to show a popup?
	if m_isDiplomacyUp then return; end	-- ScreenReaderAccess mod change: held until the diplomacy scene closes
	if UI.CanShowPopup(PopupPriority.Tutorial) then
		ShowNextQueuedPopup();
	end
end

-- ===========================================================================
--	LUA Event
--	Called when a diplomacy scene is closed
-- ===========================================================================
function OnDiploSceneClosed()
	m_isDiplomacyUp = false;
	local isAdvisorVisible	:boolean = (not Controls.AdvisorBase:IsHidden());
	if isAdvisorVisible then
		UITutorialManager:SetActiveAlways( not m_isModalPopupUp );
	elseif #m_kQueuedPopups > 0 and UI.CanShowPopup(PopupPriority.Tutorial) then
		ShowNextQueuedPopup();	-- ScreenReaderAccess mod change: an advisor held during diplomacy (if the UI is not ready, OnUIIdle shows it)
	end
end

-- ===========================================================================
--	LUA Event
--	Called when a diplomacy scene is opened
-- ===========================================================================
function OnDiploSceneOpened()
	m_isDiplomacyUp = true;

	-- If always active was set by this, turn it off to not interfer with the
	-- diplomacy input.  (So it's ALMOST always active.)
	local isAdvisorVisible	:boolean = (not Controls.AdvisorBase:IsHidden());
	if isAdvisorVisible then
		UITutorialManager:SetActiveAlways( false );	
	end
end

-- ===========================================================================
--	LUA Event
-- ===========================================================================
-- ScreenReaderAccess mod change: a generic in-game popup (Unit Captured, ...) opened above the advisor. While the advisor keeps
-- the tutorial input mode on, no key reaches that popup (they act on the map): let go of it like the diplomacy scene does, and
-- take it back, and say the advisor again, when the popup is gone.
function OnInGamePopupShown( isOpen:boolean )
	m_isModalPopupUp = isOpen;
	if (not Controls.AdvisorBase:IsHidden()) and (not m_isDiplomacyUp) then
		UITutorialManager:SetActiveAlways( not isOpen );
		if not isOpen and #m_kKeyNavButtons > 0 then KeyNavAnnouncePopup( true ); end
	end
end

function OnAdvisorRaise( item:AdvisorItem )
	ShowOrQueuePopup( item );
end

-- ===========================================================================
--	LUA Event
-- ===========================================================================
function OnAdvisorLower()
	Close();
end

-- ===========================================================================
--	LUA Event
--	Hotload callback
-- ===========================================================================
function OnGameDebugReturn(context:string, contextTable:table)
	if context == RELOAD_CACHE_ID then 
		m_isDiplomacyUp = contextTable["m_isDiplomacyUp"];
		if contextTable["isHidden"] ~= nil and (not contextTable["isHidden"]) then
			if contextTable["m_currentItem"] then
				m_currentItem = hmake AdvisorItem{};
				m_currentItem.Message		= contextTable["m_currentItem.Message"];
				m_currentItem.Image			= contextTable["m_currentItem.Image"];
				m_currentItem.OptionsNum	= contextTable["m_currentItem.OptionsNum"];
				m_currentItem.Button1Text	= contextTable["m_currentItem.Button1Text"];
				m_currentItem.Button2Text	= contextTable["m_currentItem.Button2Text"];
				m_currentItem.Button1Func	= contextTable["m_currentItem.Button1Func"];
				m_currentItem.Button2Func	= contextTable["m_currentItem.Button2Func"];
				m_currentItem.CalloutHeader = contextTable["m_currentItem.CalloutHeader"];
				m_currentItem.CalloutBody	= contextTable["m_currentItem.CalloutBody"];		
				m_currentItem.PlotCallback	= nil;
				m_currentItem.ShowPortrait  = contextTable["m_currentItem.ShowPortrait"];
				m_currentItem.UITriggers	= contextTable["m_currentItem.UITriggers"];					
				ShowAdvisorPopup( m_currentItem );	
			end			
		end
	end
end


-- ===========================================================================
--	Hotkey
-- ===========================================================================
function OnInputActionTriggered( actionId:number )
	if	actionId == m_actionHotkeyContinue		or
		actionId == m_actionHotkeyContinueAlt	then
		if m_hotkeyCallback ~= nil then 
			m_hotkeyCallback();
		end		
	end		
end


-- ===========================================================================
--	Is the advisor popup blocking all other input?
--
--	1) Since the context is marked to always be processed in the tutorial flow,
--	   it will get first crack at the input (with the other tutorial controls)
--	   before the normal flow of cascade controls.
--
--	2) This also means tutorial items in the normal control tree will not
--	   receive input if this is showing.
-- ===========================================================================
function IsBlockingInput()
	-- Context itself must be showing and then at least one of the sub dialogs also must be up.
	local isContextVisible	:boolean = (not ContextPtr:IsHidden());
	local isAdvisorVisible	:boolean = (not Controls.AdvisorBase:IsHidden());
	local isMetaVisible		:boolean = (not Controls.MetaBase:IsHidden());

	return isContextVisible and (isAdvisorVisible or isMetaVisible) and (m_isDiplomacyUp==false);
end

-- ===========================================================================
function KeyHandler( key:number )
	if m_isModalPopupUp then return false; end		-- ScreenReaderAccess mod change: the popup above takes the keys
	-- Screen reader: keyboard navigation of the advisor's buttons while it is showing.
	if IsBlockingInput() and (not m_isDiplomacyUp) then
		if key == Keys.VK_UP then
			KeyNavMoveFocus( -1 );
			return true;
		elseif key == Keys.VK_DOWN or key == Keys.VK_TAB then
			KeyNavMoveFocus( 1 );
			return true;
		elseif key == Keys.VK_ESCAPE then
			-- Close like the first button (Continue / OK); the item cannot be left unanswered.
			KeyNavActivate( 1 );
			return true;
		elseif key == Keys.VK_SPACE and #m_kKeyNavButtons > 0 then
			KeyNavAnnouncePopup( false );
			return true;
		elseif key == Keys.VK_RETURN and #m_kKeyNavButtons > 0 then
			-- The continue hotkey may have activated the button already on key down; otherwise do it now.
			if m_keyNavHotkeyFired then
				m_keyNavHotkeyFired = false;
			else
				KeyNavActivate( m_keyNavFocus );
			end
			return true;
		end
	end
	m_keyNavHotkeyFired = false;

	if key == Keys.VK_ESCAPE then
		if m_isDiplomacyUp then return false; end	-- Currently cannot handle ESC if diplomacy is up.
		LuaEvents.Tutorial_ToggleInGameOptionsMenu();
		return true;
	end
	
	if key == Keys.VK_RETURN and (not UI.IsFinalRelease()) then
		if m_isDiplomacyUp then return false; end	-- Currently cannot handle ESC if diplomacy is up.
			if m_hotkeyCallback ~= nil then 
				m_hotkeyCallback();
			end
		return true;
	end
	
	return IsBlockingInput();	
end

-- ===========================================================================
--	UI Event
-- ===========================================================================
function OnInputHandler( pInputStruct:table )
	local uiMsg = pInputStruct:GetMessageType();
	if uiMsg == KeyEvents.KeyUp then 
		local ok, result = xpcall( function() return KeyHandler( pInputStruct:GetKey() ); end, KeyNavErrorHandler );
		if not ok then
			print( "AdvisorPopup input error: " .. tostring(result) );
			return IsBlockingInput();
		end
		return result;
	end
	return IsBlockingInput();
end

-- ===========================================================================
--	UI Event
-- ===========================================================================
function OnInit( isReload:boolean )
	if isReload then
		LuaEvents.GameDebug_GetValues(RELOAD_CACHE_ID);
	end
end

-- ===========================================================================
--	UI Event
-- ===========================================================================
function OnShow()
	local isAdvisorVisible	:boolean = (not Controls.AdvisorBase:IsHidden());
	UITutorialManager:EnableOverlay( isAdvisorVisible );
	UITutorialManager:SetActiveAlways( isAdvisorVisible );
	UI.PlaySound("Resume_Advisor_Speech");
    UI.PlaySound("Pause_TechCivic_Speech");
end

-- ===========================================================================
--	UI Event
-- ===========================================================================
function OnHide()
	local isAdvisorVisible	:boolean = (not Controls.AdvisorBase:IsHidden());
	UITutorialManager:EnableOverlay( isAdvisorVisible );
	UITutorialManager:SetActiveAlways( isAdvisorVisible );
	UI.PlaySound("Stop_Advisor_Speech_All");
end

-- ===========================================================================
--	UI Event
-- ===========================================================================
function OnShutdown()
	if ms_eventID ~= 0 then
		UI.ReleaseEventID(ms_eventID);
	end
	UITutorialManager:SetActiveAlways( false );
	
	LuaEvents.GameDebug_AddValue(RELOAD_CACHE_ID, "isHidden", ContextPtr:IsHidden() );
	LuaEvents.GameDebug_AddValue(RELOAD_CACHE_ID, "m_isDiplomacyUp", m_isDiplomacyUp );	

	if m_currentItem ~= nil then
		LuaEvents.GameDebug_AddValue(RELOAD_CACHE_ID, "m_currentItem", true );
		LuaEvents.GameDebug_AddValue(RELOAD_CACHE_ID, "m_currentItem.Message",		m_currentItem.Message );
		LuaEvents.GameDebug_AddValue(RELOAD_CACHE_ID, "m_currentItem.Image",		m_currentItem.Image );
		LuaEvents.GameDebug_AddValue(RELOAD_CACHE_ID, "m_currentItem.OptionsNum",	m_currentItem.OptionsNum );
		LuaEvents.GameDebug_AddValue(RELOAD_CACHE_ID, "m_currentItem.Button1Text",	m_currentItem.Button1Text );
		LuaEvents.GameDebug_AddValue(RELOAD_CACHE_ID, "m_currentItem.Button2Text",	m_currentItem.Button2Text );
		LuaEvents.GameDebug_AddValue(RELOAD_CACHE_ID, "m_currentItem.Button1Func",	m_currentItem.Button1Func );
		LuaEvents.GameDebug_AddValue(RELOAD_CACHE_ID, "m_currentItem.Button2Func",	m_currentItem.Button2Func );
		LuaEvents.GameDebug_AddValue(RELOAD_CACHE_ID, "m_currentItem.CalloutHeader",m_currentItem.CalloutHeader );
		LuaEvents.GameDebug_AddValue(RELOAD_CACHE_ID, "m_currentItem.CalloutBody",	m_currentItem.CalloutBody );		
		if (m_currentItem.PlotCallback ~= nil ) then 
			UI.DataError("Warning, you are hotloading with a plot callback, but ifunction definitions cannot be serialized across hotload.  Your milage will vary."); 
		end
		LuaEvents.GameDebug_AddValue(RELOAD_CACHE_ID, "m_currentItem.ShowPortrait", m_currentItem.ShowPortrait );
		LuaEvents.GameDebug_AddValue(RELOAD_CACHE_ID, "m_currentItem.UITriggers",	m_currentItem.UITriggers );
	else
		LuaEvents.GameDebug_AddValue(RELOAD_CACHE_ID, "m_currentItem", false );
	end

	-- ScreenReaderAccess mod change: all listeners were added with SRListen (a hot reload re-runs this script, stale instances kept firing)
	SRUnlistenAll();
end


-- ===========================================================================
--	
-- ===========================================================================
function Initialize()

	-- DEBUG
	if (m_currentItem ~= nil) then
		m_currentItem.ShowPortrait = false;
		ShowAdvisorPopup(m_currentItem);
	end

	-- UI Events
	ContextPtr:SetInitHandler( OnInit );
	ContextPtr:SetInputHandler( OnInputHandler, true );
	ContextPtr:SetShutdown( OnShutdown );
    ContextPtr:SetShowHandler( OnShow );
	ContextPtr:SetHideHandler( OnHide );

	-- Events
	SRListen( Events.InputActionTriggered, OnInputActionTriggered );
	SRListen( Events.UIIdle, OnUIIdle );

	-- Lua Events
	SRListen( LuaEvents.SRA_InGamePopupShown, OnInGamePopupShown );
	SRListen( LuaEvents.DiploScene_SceneClosed, OnDiploSceneClosed );
	SRListen( LuaEvents.DiploScene_SceneOpened, OnDiploSceneOpened );
	SRListen( LuaEvents.GameDebug_Return, OnGameDebugReturn );
	SRListen( LuaEvents.TutorialUIRoot_AdvisorRaise, OnAdvisorRaise );
	SRListen( LuaEvents.TutorialUIRoot_AdvisorLower, OnAdvisorLower );

end
Initialize();
