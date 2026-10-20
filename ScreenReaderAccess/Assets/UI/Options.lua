-- ===========================================================================
--	Options
-- ===========================================================================
include("Civ6Common");
include("InstanceManager");
include("PopupDialog");
include("PlayerSetupLogic");

include("ScreenReader")
include("KeyboardNavigation")
include("KeyNavEditBox")


-- Quick utility function to determine if Rise and Fall is installed.
function HasExpansion1()
	local xp1ModId = "1B28771A-C749-434B-9053-D1380C553DE9";
	return Modding.IsModInstalled(xp1ModId);
end

-- Quick utility function to determine if Rise and Fall is installed.
function HasExpansion2()
	local xpModId = "4873eb62-8ccc-4574-b784-dda455e74e68";
	return Modding.IsModInstalled(xpModId);
end

function IsInGame()
	if(GameConfiguration ~= nil) then
		return GameConfiguration.GetGameState() ~= GameStateTypes.GAMESTATE_PREGAME;
	end
	return false;
end

-- ===========================================================================
--	DEBUG 
--	Toggle these for temporary debugging help.
-- ===========================================================================

local m_debugAlwaysAllowAllOptions	:boolean= false;	-- (false) When true no options are disabled, even when in game. :/


-- ===========================================================================
--	MEMBERS / VARIABLES
-- ===========================================================================


local _KeyBindingCategories = InstanceManager:new("KeyBindingCategory", "CategoryName", Controls.KeyBindingsStack);
local _KeyBindingActions = InstanceManager:new("KeyBindingAction", "Root", Controls.KeyBindingsStack);
local m_tabs;
local m_pendingGameConfigChanges;

local m_mainFocusKey = "tab:1";		-- focused element at tab level: "tab:<n>", "confirm", "reset", "back"
local m_inMainKeyNav = true;
local m_bindingInstances = {};
local m_bindingInfo = {};			-- parallel to m_bindingInstances: {actionId, name, category, g1, g2}
local m_lastBindingCategory = nil;
local m_selection = nil;			-- open pulldown selection: {item, state, index, originalIndex}
local m_secondsSinceKey = 999;	-- the console app moves the real mouse; hover announcements right after a key press are echoes of that
local m_sliderCallbacks = {};		-- slider control -> callback, so the keyboard can drive it
local m_selectedBindingIndex = 1;
local m_selectedBindingColumn = 1;
local m_currentTab = nil;
local m_comboState = {};		-- pulldown control -> {values, index, handler}
local m_checkState = {};		-- checkbox control -> handler
local m_contentFocus = nil;		-- id of the control focused in the current tab's content
local m_contentFocusIndex = 1;	-- its position, to clamp to when it disappears
local m_resetDirty = false;		-- Reset to defaults was applied and not yet confirmed
local m_captureKeyDown = nil;	-- last key pressed while the key binding popup was shown
local m_swallowKeyUp = nil;		-- key whose KeyUp completes a binding capture and must not act as navigation

-- Registers a slider callback and remembers it (the keyboard changes the value and calls it).
local function RegisterSliderCb(control, callback)
	m_sliderCallbacks[control] = callback;
	control:RegisterSliderCallback(callback);
end

local BORDERLESS_OPTION = 2;
local FULLSCREEN_OPTION = 1;
local WINDOWED_OPTION = 0;

local MIN_CHAT_TEXT_SIZE = 12;
local MAX_CHAT_TEXT_SIZE = 18;
local MIN_SCROLL_SPEED = 0;
local MAX_SCROLL_SPEED = 1.0;
local MIN_SCROLL_TEXT_SPEED = 0;
local MAX_SCROLL_TEXT_SPEED = 1.0;
local MIN_SCREEN_Y = 768;
local SCREEN_OFFSET_Y = 63;
local MIN_SCREEN_OFFSET_Y = -53;

_PromptRestartApp = false;
_PromptRestartGame = false;
_PromptResolutionAck = false;

-- Options for WebHook Frequency Pulldown
local webhookFreq_options = 
{
	{"LOC_WEBHOOK_FREQ_MY_TURN", TurnNotifyFrequencyModes.TurnNotify_MyTurn},
	{"LOC_WEBHOOK_FREQ_EVERY_TURN", TurnNotifyFrequencyModes.TurnNotify_EveryTurn}
};

-------------------------------------------------------------------------------
--
-------------------------------------------------------------------------------
function OnOptionChangeRequiresAppRestart()
	_PromptRestartApp = true
end

-------------------------------------------------------------------------------
--
-------------------------------------------------------------------------------
function OnOptionChangeRequiresGameRestart()
	_PromptRestartGame = true;
end

-------------------------------------------------------------------------------
--
-------------------------------------------------------------------------------
function OnOptionChangeRequiresResolutionAck()
	_PromptResolutionAck = true;
end

-------------------------------------------------------------------------------
--
-------------------------------------------------------------------------------
function OnPBCNotifyRemind_ShowOptions()
	-- Go to first tab where play-by-cloud options exist
	OnSelectTab(1);
	UIManager:QueuePopup( ContextPtr, PopupPriority.Current );
end

-------------------------------------------------------------------------------
--
-------------------------------------------------------------------------------
function OnCancel()
	Options.RevertOptions();
	UserConfiguration.RestoreCheckpoint();

    RefreshKeyBinding();

	_PromptRestartApp = false;
	_PromptRestartGame = false;
    _PromptResolutionAck = false;

    local value = Options.GetAudioOption("Sound", "Master Volume");
	Controls.MasterVolSlider:SetValue(value / 100.0);
    Options.SetAudioOption("Sound", "Master Volume", value, 0);

    value = Options.GetAudioOption("Sound", "Music Volume"); 
    Controls.MusicVolSlider:SetValue(value / 100.0);
    Options.SetAudioOption("Sound", "Music Volume", value, 0);

    value = Options.GetAudioOption("Sound", "SFX Volume"); 
    Controls.SFXVolSlider:SetValue(value / 100.0);
    Options.SetAudioOption("Sound", "SFX Volume", value, 0);

    value = Options.GetAudioOption("Sound", "Ambience Volume"); 
    Controls.AmbVolSlider:SetValue(value / 100.0);
    Options.SetAudioOption("Sound", "Ambience Volume", value, 0);

    value = Options.GetAudioOption("Sound", "Speech Volume"); 
    Controls.SpeechVolSlider:SetValue(value / 100.0);
    Options.SetAudioOption("Sound", "Speech Volume", value, 0);

	value = Options.GetGraphicsOption("General", "MinimapSize") or 0.0;
	Controls.MinimapSizeSlider:SetValue(value);
	UI.SetMinimapSize(value);

	value = Options.GetUserOption("Interface", "ChatTextValue") or 12;
	Controls.ChatTextSizeSlider:SetValue(value);
	Options.SetUserOption("Interface", "ChatTextValue", value);

    value = Options.GetAudioOption("Sound", "Mute Focus"); 
    if (value == 0) then
        Controls.MuteFocusCheckbox:SetSelected(false);
    else
        Controls.MuteFocusCheckbox:SetSelected(true);
    end
    Options.SetAudioOption("Sound", "Mute Focus", value, 0);

	UIManager:DequeuePopup(ContextPtr);
end

-------------------------------------------------------------------------------
--
-------------------------------------------------------------------------------
function OnReset()
    local confirmWasDisabled = Controls.ConfirmButton:IsDisabled();
    function EnableControls(confirmDisabled)
        Controls.ResetButton:SetDisabled(false);
        Controls.WindowCloseButton:SetDisabled(false);
        Controls.ConfirmButton:SetDisabled(confirmDisabled);
    end
	function ResetOptions()
		Options.ResetOptions();

		_PromptRestartApp = false;
		_PromptRestartGame = false;
        _PromptResolutionAck = false;

        PopulateGraphicsOptions();

		TemporaryHardCodedGoodness();
        m_resetDirty = true;
        EnableControls(true);
        OutputMessageToScreenReader("Options reset to defaults");
	end
    function CancelReset()
        EnableControls(confirmWasDisabled);
        OutputMessageToScreenReader("Reset cancelled");
    end

    _kPopupDialog:AddText(Locale.Lookup("LOC_OPTIONS_RESET_OPTIONS_POPUP_TEXT"));
    _kPopupDialog:AddButton(Locale.Lookup("LOC_OPTIONS_RESET_OPTIONS_POPUP_YES"), function() ResetOptions(); end, nil, nil,"PopupButtonInstanceRed");  
		_kPopupDialog:AddButton(Locale.Lookup("LOC_OPTIONS_RESET_OPTIONS_POPUP_NO"), function() CancelReset(); end); 
    _kPopupDialog:Open();
    Controls.ResetButton:SetDisabled(true);
    Controls.ConfirmButton:SetDisabled(true);

    Controls.WindowCloseButton:SetDisabled(true);
end                       

-------------------------------------------------------------------------------
--
-------------------------------------------------------------------------------
function OnConfirm()
    
    function KeepGraphicsChanges()
        -- Make sure the next game start uploads the changed settings telemetry
        Options.SetAppOption("Misc", "TelemetryUploadNecessary", 1);

        -- Save after applying the options to make sure they are valid
        Options.SaveOptions();
        PopulateGraphicsOptions();

        _PromptRestartApp = false;
	    _PromptRestartGame = false;
        _PromptResolutionAck = false;
        
        -- Do not call DequeuePopup, because PopupDialog calls self.Close() before calling this function
        --UIManager:DequeuePopup(ContextPtr);
    end

    function RevertGraphicsChanges()
        OutputMessageToScreenReader("Display settings reverted");
        -- Revert the graphics option changes
        Options.RevertResolutionChanges();

        -- Save after reverting the options to make sure they are valid
        Options.SaveOptions();
        PopulateGraphicsOptions();

        _PromptRestartApp = false;
	    _PromptRestartGame = false;
        _PromptResolutionAck = false;
    end

	function ConfirmChanges()
		-- Confirm clicked: set audio system's .ini to slider values --
		Options.SetAudioOption("Sound", "Master Volume", Controls.MasterVolSlider:GetValue() * 100.0, 1);
		Options.SetAudioOption("Sound", "Music Volume", Controls.MusicVolSlider:GetValue() * 100.0, 1);
		Options.SetAudioOption("Sound", "SFX Volume", Controls.SFXVolSlider:GetValue() * 100.0, 1);
		Options.SetAudioOption("Sound", "Ambience Volume", Controls.AmbVolSlider:GetValue() * 100.0, 1);
		Options.SetAudioOption("Sound", "Speech Volume", Controls.SpeechVolSlider:GetValue() * 100.0, 1);
        if (Controls.MuteFocusCheckbox:IsSelected()) then
            Options.SetAudioOption("Sound", "Mute Focus", 1, 1);
        else
            Options.SetAudioOption("Sound", "Mute Focus", 0, 1);
        end

        -- Now we apply the userconfig options
		UserConfiguration.SetValue("QuickCombat",					Options.GetUserOption("Gameplay", "QuickCombat"));
		UserConfiguration.SetValue("QuickMovement",					Options.GetUserOption("Gameplay", "QuickMovement"));
		UserConfiguration.SetValue("AutoEndTurn",					Options.GetUserOption("Gameplay", "AutoEndTurn"));
		UserConfiguration.SetValue("CityRangeAttackTurnBlocking",	Options.GetUserOption("Gameplay", "CityRangeAttackTurnBlocking"));
		UserConfiguration.SetValue("TutorialLevel",					Options.GetUserOption("Gameplay", "TutorialLevel"));
		UserConfiguration.SetValue("EdgePan",						Options.GetUserOption("Gameplay", "EdgePan"));
        UserConfiguration.SetValue("AutoProdQueue", 				Options.GetUserOption("Gameplay", "AutoProdQueue"));

		UserConfiguration.SetValue("AutoUnitCycle",		Options.GetUserOption("Gameplay", "AutoUnitCycle"));
		UserConfiguration.SetValue("RibbonStats",		Options.GetUserOption("Interface", "RibbonStats"));
		UserConfiguration.SetValue("PlotTooltipDelay",	Options.GetUserOption("Interface", "PlotTooltipDelay"));
		UserConfiguration.SetValue("ChatTextValue",		Options.GetUserOption("Interface", "ChatTextValue"));
		UserConfiguration.SetValue("ScrollSpeed",		Options.GetUserOption("Interface", "ScrollSpeed"));
		UserConfiguration.SetValue("ScrollTextSpeed",	Options.GetUserOption("Interface", "ScrollTextSpeed"));


        -- Apply the graphics options (modifies in-memory values and modifies the engine, but does not save to disk)
        local bSuccess = Options.ApplyGraphicsOptions();

        -- tell the colorblindness adapatation code to switch to the new base palette 
		-- Do not do this if the game has started as it will reset player colors.
		if(not IsInGame()) then
			UI.RefreshColorSet();   
		end

		UI.TouchEnableChanged();

        -- Re-populate the graphics options to update any settings that the engine had to modify from the user's selected values
	    PopulateGraphicsOptions();

        -- Show the resolution acknowledgment pop-up
        if bSuccess then
			if _PromptResolutionAck then
				_kPopupDialog:AddText(Locale.Lookup("LOC_OPTIONS_RESOLUTION_OK"));
				_kPopupDialog:AddButton(Locale.Lookup("LOC_OPTIONS_RESET_OPTIONS_POPUP_YES"), 
					function() 
						KeepGraphicsChanges(); 
						OutputMessageToScreenReader("Display settings kept");
						UserConfiguration.SaveCheckpoint();
					end);
				_kPopupDialog:AddButton(Locale.Lookup("LOC_OPTIONS_RESET_OPTIONS_POPUP_NO"), function() RevertGraphicsChanges(); end);
				_kPopupDialog:AddCountDown(15, function() RevertGraphicsChanges(); end );
				_kPopupDialog:Open();
				OutputMessageToScreenReader("Settings revert automatically in 15 seconds unless you choose Yes", true);
			else
				KeepGraphicsChanges();
				UserConfiguration.SaveCheckpoint();
			end
        end

		-- Save game config options if they have been modified
		if m_pendingGameConfigChanges and table.count(m_pendingGameConfigChanges) > 0 then
			for group, values in pairs(m_pendingGameConfigChanges) do
				for id, value in pairs(values) do
					BASE_Config_Write(SetupParameters, group, id, value);
				end
			end
			Network.BroadcastGameConfig();
		end

		Controls.ConfirmButton:SetDisabled(true);
        _PromptResolutionAck = false;
		m_resetDirty = false;
		if not _kPopupDialog:IsOpen() then
			OutputMessageToScreenReader(bSuccess and "Settings applied" or "Some settings could not be applied", true);
		end
    end

	if(_PromptRestartApp) then
		_kPopupDialog:AddText(Locale.Lookup("LOC_OPTIONS_CHANGES_REQUIRE_APP_RESTART"));
		_kPopupDialog:AddButton(Locale.Lookup("LOC_OPTIONS_RESET_OPTIONS_POPUP_OK"), function() ConfirmChanges(); end); 
		_kPopupDialog:Open();
		Controls.ConfirmButton:SetDisabled(true);

	elseif(_PromptRestartGame and IsInGame()) then
		_kPopupDialog:AddText(Locale.Lookup("LOC_OPTIONS_CHANGES_REQUIRE_GAME_RESTART"));
		_kPopupDialog:AddButton(Locale.Lookup("LOC_OPTIONS_RESET_OPTIONS_POPUP_OK"), function() ConfirmChanges(); end);
		_kPopupDialog:Open();
	else
		ConfirmChanges();
	end
end

-------------------------------------------------------------------------------
--
-------------------------------------------------------------------------------
function PopulateComboBox(control, values, selected_value, selection_handler, is_locked)

	if (is_locked == nil) then
		is_locked = false;
	end

	control:ClearEntries();
	local selectedIndex = 1;
	local matched = false;
	for i, v in ipairs(values) do
		local instance = {};
		control:BuildEntry( "InstanceOne", instance );
		instance.Button:SetVoid1(i);
        instance.Button:LocalizeAndSetText(v[1]);

		if(v[2] == selected_value) then
			selectedIndex = i;
			matched = true;
			local button = control:GetButton();
            button:LocalizeAndSetText(v[1]);
		end
	end
	control:CalculateInternals();	
		
	control:SetDisabled(is_locked ~= false);
	m_comboState[control] = { values = values, index = selectedIndex, matched = matched, handler = selection_handler };

	if(selection_handler) then
		control:GetButton():RegisterCallback(Mouse.eMouseEnter, function()
            UI.PlaySound("Main_Menu_Mouse_Over");
		end);
		control:RegisterSelectionCallback(
			function(voidValue1, voidValue2, control)
				local option = values[voidValue1];
				m_comboState[control].index = voidValue1;
				m_comboState[control].matched = true;

				local button = control:GetButton();
                button:LocalizeAndSetText(option[1]);
								
				selection_handler(option[2]);
			end
		);
	end
    	
end

-------------------------------------------------------------------------------
--
-------------------------------------------------------------------------------
function PopulateCheckBox(control, current_value, check_handler, is_locked)
    
    if (is_locked == nil) then
		is_locked = false;
	end

    if(current_value == 0) then
        control:SetSelected(false);
    else
        control:SetSelected(true);
    end

    control:SetDisabled(is_locked ~= false);
	m_checkState[control] = check_handler;

    if(check_handler) then
        control:RegisterCallback(Mouse.eLClick, 
            function()
			    local selected = not control:IsSelected();
			    control:SetSelected(selected);
                check_handler(selected);
            end
        );
		control:RegisterCallback(Mouse.eMouseEnter, function()
            UI.PlaySound("Main_Menu_Mouse_Over");
		end);
    end

end

-------------------------------------------------------------------------------
--
-------------------------------------------------------------------------------
local m_editCommit = {};	-- EditBox -> its commit handler (for keyboard editing)
function PopulateEditBox(control, current_value, commit_handler, is_locked)
    
    if (is_locked == nil) then
		is_locked = false;
	end

	control:SetText(current_value);
    control:SetDisabled(is_locked ~= false);

    control:RegisterMouseEnterCallback(function()
        UI.PlaySound("Main_Menu_Mouse_Over");
    end);

    m_editCommit[control] = commit_handler;
    if(commit_handler) then
        control:RegisterCommitCallback( 
            function(editString)
                commit_handler(editString);
            end
        );
    end

end

-------------------------------------------------------------------------------
--
-------------------------------------------------------------------------------
function InvertOptionInt(option)

    if(option == 0) then
        return 1;
    else
        return 0;
    end

end

-------------------------------------------------------------------------------
--
-------------------------------------------------------------------------------
function ImpactValueToSliderStep(slider, impact_value)

    if(impact_value == -1) then
        return slider:GetNumSteps();
    else
        return impact_value;
    end
end

-------------------------------------------------------------------------------
--
-------------------------------------------------------------------------------
function SliderStepToImpactValue(slider, slider_step)

    if(slider_step == slider:GetNumSteps()) then
        return -1;
    else
        return slider_step;
    end
end

-------------------------------------------------------------------------------
--
-------------------------------------------------------------------------------
local TIME_SCALE = 23.0 + (59.0 / 60.0); -- 11:59 PM
function UpdateTimeLabel(value)
	local iHours = math.floor(value);
	local iMins  = math.floor((value - iHours) * 60);
	local meridiem = "";

	if (UserConfiguration.GetClockFormat() == 0) then
		meridiem = " am";
		if ( iHours >= 12 ) then
			meridiem = " pm";
			if( iHours > 12 ) then iHours = iHours - 12; end
		end
		if( iHours < 1 ) then iHours = 12; end
	end

	local strTime = string.format("%.2d:%.2d%s", iHours, iMins, meridiem);
	Controls.TODText:SetText(strTime);
end

-- Change the state of the resolution pulldown based on whether we have selected borderless mode or not
function AdjustResolutionPulldown(window_mode, is_in_game )
	
	local named_modes = {};
	local modes = Options.GetAvailableDisplayModes();

	for i, v in ipairs(modes) do
		local s = v.Width .. "x" .. v.Height;
		if( window_mode == FULLSCREEN_OPTION) then
			s = s .. " (" .. v.RefreshRate .. " Hz)";
		end
		named_modes[s] = v;
	end

	local indexed_modes = {};
	for k, v in pairs(named_modes) do
		table.insert(indexed_modes, {k, v});
	end
	table.sort(indexed_modes, function(a, b) return a[1] > b[1]; end);

	--remove duplicate modes if in windowed (same res, different refresh rate)
	local final_indexed_modes = {};
	if( window_mode == WINDOWED_OPTION ) then
		local last = "";
		for i,v in ipairs(indexed_modes) do
			if( v[1] ~= last ) then
				table.insert(final_indexed_modes, v );
			end
			last = v[1];
		end
	else
		final_indexed_modes = indexed_modes;
	end

    Controls.ResolutionPullDown:ClearEntries();
	for i, v in ipairs(final_indexed_modes) do
		local instance = {};
		Controls.ResolutionPullDown:BuildEntry( "InstanceOne", instance );
		instance.Button:SetVoid1(i);
		instance.Button:SetText(v[1]);
	end
	Controls.ResolutionPullDown:CalculateInternals();

	local applyResolution = function(mode)
		Options.SetAppOption("Video", "RenderWidth", mode.Width);
		Options.SetAppOption("Video", "RenderHeight", mode.Height);
		Options.SetGraphicsOption("Video", "RefreshRateInHz", mode.RefreshRate);

		local fullscreen_option = Options.GetAppOption("Video", "FullScreen");
		_PromptResolutionAck = (fullscreen_option == FULLSCREEN_OPTION);
		Controls.ConfirmButton:SetDisabled(false);
	end

	Controls.ResolutionPullDown:RegisterSelectionCallback(
		function(voidValue1, voidValue2, control)
			local option = final_indexed_modes[voidValue1];

			local resolution_button = control:GetButton();
			resolution_button:SetText(option[1]);

			applyResolution(option[2]);
		end
	);
	
	local current_width = Options.GetAppOption("Video", "RenderWidth");
	local current_height = Options.GetAppOption("Video", "RenderHeight");
	local refresh_rate = Options.GetGraphicsOption("Video", "RefreshRateInHz");
	
	local resolution_button = Controls.ResolutionPullDown:GetButton();
	if( window_mode ~= FULLSCREEN_OPTION ) then
		resolution_button:SetText(current_width .. "x" .. current_height);
	else
		resolution_button:SetText(current_width .. "x" .. current_height .. " (" .. refresh_rate .. " Hz)");
	end

	-- Let the keyboard drive the pulldown (value list for Enter / Left / Right)
	do
		local resText = current_width .. "x" .. current_height;
		if window_mode == FULLSCREEN_OPTION then resText = resText .. " (" .. refresh_rate .. " Hz)"; end
		local resIndex = 1;
		local resMatched = false;
		for i, v in ipairs(final_indexed_modes) do
			if v[1] == resText then resIndex = i; resMatched = true; break; end
		end
		m_comboState[Controls.ResolutionPullDown] = { values = final_indexed_modes, index = resIndex, matched = resMatched, handler = applyResolution };
	end

	local debug_enabled = Options.GetAppOption("Debug", "EnableDebugMenu");	-- When debugging allow game resolution change. TODO: Evaluate allowing change for everyone.
    if is_in_game and debug_enabled==0 then
        Controls.ResolutionPullDown:SetDisabled(true);
    else
        if(window_mode == BORDERLESS_OPTION) then
            Controls.ResolutionPullDown:SetDisabled(true);
            local resolution_button = Controls.ResolutionPullDown:GetButton();
	        local display_width  = Options.GetDisplayWidth();
            local display_height = Options.GetDisplayHeight();
            resolution_button:SetText(display_width .. "x" .. display_height );
        else
            Controls.ResolutionPullDown:SetDisabled(false);
            local current_width = Options.GetAppOption("Video", "RenderWidth");
	        local current_height = Options.GetAppOption("Video", "RenderHeight");
	        local refresh_rate = Options.GetGraphicsOption("Video", "RefreshRateInHz");
	
	        local resolution_button = Controls.ResolutionPullDown:GetButton();
			local resolution_text = current_width .. "x" .. current_height;
			if( window_mode == FULLSCREEN_OPTION ) then
				resolution_text = resolution_text .. " (" .. refresh_rate .. " Hz)";
			end
	        resolution_button:SetText(resolution_text);
        end

    end

end



-------------------------------------------------------------------------------
--
-------------------------------------------------------------------------------
function PopulateGraphicsOptions()
    
    
    local tickInterval_options =
    {
        {"LOC_OPTIONS_DISABLED", 0},        
        {"LOC_OPTIONS_TICK_INTERVAL_20_FPS", 49},
        {"LOC_OPTIONS_TICK_INTERVAL_30_FPS", 32},
        {"LOC_OPTIONS_TICK_INTERVAL_60_FPS", 16},
    };

	local windowed_options =
    {
		{"LOC_OPTIONS_WINDOW_MODE_WINDOWED", WINDOWED_OPTION},
		{"LOC_OPTIONS_WINDOW_MODE_FULLSCREEN", FULLSCREEN_OPTION},
		{"LOC_OPTIONS_WINDOW_MODE_BORDERLESS", BORDERLESS_OPTION}
	};

	local uiscale_options =
    {
        {"LOC_OPTIONS_100_PERCENT", 0.0},        
        {"LOC_OPTIONS_150_PERCENT", 0.5},
        {"LOC_OPTIONS_200_PERCENT", 1.0}
    };

    local performanceImpact_options =
    { 
        [0]="LOC_OPTIONS_MINIMUM",
            "LOC_OPTIONS_LOW", 
            "LOC_OPTIONS_MEDIUM",
            "LOC_OPTIONS_HIGH",
			"LOC_OPTIONS_ULTRA",
            "LOC_OPTIONS_CUSTOM"
    };

    local memoryImpact_options =
    { 
        [0]="LOC_OPTIONS_MINIMUM",
            "LOC_OPTIONS_LOW", 
            "LOC_OPTIONS_MEDIUM",
            "LOC_OPTIONS_HIGH",
			"LOC_OPTIONS_ULTRA",
            "LOC_OPTIONS_CUSTOM"
    };

	local msaa_options =
    {
		{"LOC_OPTIONS_DISABLED", {1,  0}},
		{"LOC_OPTIONS_MSAA_2X",  {2,  0}},
		{"LOC_OPTIONS_MSAA_4X",  {4,  0}},
		{"LOC_OPTIONS_MSAA_8X",  {8,  0}},
		{"LOC_OPTIONS_MSAA_16X", {16, 0}},
		{"LOC_OPTIONS_MSAA_32X", {32, 0}},
	};

    local csaa_options =
    {
		{"LOC_OPTIONS_CSAA_2X",  {2,  4}},
		{"LOC_OPTIONS_CSAA_4X",  {4,  8}},
		{"LOC_OPTIONS_CSAA_8X",  {8,  16}},
		{"LOC_OPTIONS_CSAA_16X", {16, 32}},
	};

    local eqaa_options =
    {
		{"LOC_OPTIONS_EQAA_2X",  {2,  4}},
		{"LOC_OPTIONS_EQAA_4X",  {4,  8}},
		{"LOC_OPTIONS_EQAA_8X",  {8,  16}},
		{"LOC_OPTIONS_EQAA_16X", {16, 32}},
	};

    local vfx_options =
    {
        {"LOC_OPTIONS_LOW", 0},
        {"LOC_OPTIONS_HIGH", 1}
    };

    local aoResolution_options =
    {
        {"1024x1024", 1024},
        {"2048x2048", 2048},
    };

    local shadowResolution_options =
    {
        {"2048x2048", 2048},
        {"4096x4096", 4096},
    };

    local fowMaskResolution_options =
    {
        {"512x512", 512},
        {"1024x1024", 1024},
    };

	local terrainQuality_options =
    {
		{"LOC_OPTIONS_LOW_MEMORY_OPTIMIZED", 0},
		{"LOC_OPTIONS_LOW_PERFORMANCE_OPTIMIZED", 1},
		{"LOC_OPTIONS_MEDIUM_MEMORY_OPTIMIZED", 2},
		{"LOC_OPTIONS_MEDIUM_PERFORMANCE_OPTIMIZED", 3},
		{"LOC_OPTIONS_HIGH", 4},
	};

    local reflectionPasses_options =
    {
		{"LOC_OPTIONS_DISABLED", 0},
		{"LOC_OPTIONS_REFLECTION_1PASS", 1},
		{"LOC_OPTIONS_REFLECTION_2PASSES", 2},
		{"LOC_OPTIONS_REFLECTION_3PASSES", 3},
		{"LOC_OPTIONS_REFLECTION_4PASSES", 4},
	};
	
	local leaderQuality_options =
	{
		{"LOC_OPTIONS_LEADERS_STATIC", 0},
		{"LOC_OPTIONS_LOW",      1},
		{"LOC_OPTIONS_MEDIUM",   2},
		{"LOC_OPTIONS_HIGH",     3},
	}

    -------------------------------------------------------------------------------
    -- Main Options
    -------------------------------------------------------------------------------

    local is_in_game = Options.IsAppInMainMenuState() == 0;
    if m_debugAlwaysAllowAllOptions then
        is_in_game = false
    end

    -- Adapter
    local adapters = Options.GetAvailableDisplayAdapters();

    Controls.AdapterPullDown:ClearEntries();
	for i, v in pairs(adapters) do
		local instance = {};
		Controls.AdapterPullDown:BuildEntry( "InstanceOne", instance );
		instance.Button:SetVoid1(i);
		instance.Button:SetText(v);
	end
	Controls.AdapterPullDown:CalculateInternals();

    local adapter_index = Options.GetAppOption("Video", "DeviceID");

    local adapter_button = Controls.AdapterPullDown:GetButton();
	adapter_button:SetText(adapters[adapter_index]);

    Controls.AdapterPullDown:RegisterSelectionCallback(
		function(voidValue1, voidValue2, control)
			local adapter_button = control:GetButton();
			adapter_button:SetText(adapters[voidValue1]);

			Options.SetAppOption("Video", "DeviceID", voidValue1);
			Controls.ConfirmButton:SetDisabled(false);
            _PromptRestartApp = true;
		end
	);

	-- Let the keyboard drive the pulldown (adapter ids are not necessarily 1..n)
	do
		local adapterValues = {};
		local adapterPos = 1;
		for id, name in pairs(adapters) do
			table.insert(adapterValues, { name, id });
		end
		table.sort(adapterValues, function(a, b) return a[2] < b[2]; end);
		for i, v in ipairs(adapterValues) do
			if v[2] == adapter_index then adapterPos = i; end
		end
		m_comboState[Controls.AdapterPullDown] = { values = adapterValues, index = adapterPos, handler = function(id)
			Options.SetAppOption("Video", "DeviceID", id);
			Controls.ConfirmButton:SetDisabled(false);
			_PromptRestartApp = true;
		end };
	end

    -- Multi-GPU        
    local bMGPUValue = 0;
    if Options.GetGraphicsOption("DX12", "EnableSplitScreenMultiGPU") == 1 then
        bMGPUValue = 1;
    end

    PopulateCheckBox(Controls.MultiGPUCheckbox, bMGPUValue,
        function(option)
            Options.SetGraphicsOption("DX12", "EnableSplitScreenMultiGPU", option);
			Controls.ConfirmButton:SetDisabled(false);
            _PromptRestartApp = true;
        end
    );
    Controls.MultiGPUCheckbox:SetDisabled( Options.IsMultiNodeGPU() == 0 );

	-- UI Upscaling
	local available_scales = {};
	for k, v in pairs(uiscale_options) do
		if (Options.IsUIUpscaleAllowed(v[2] + 1.0)) then
			table.insert(available_scales, v);
		end
	end
	
    Controls.UIScalePulldown:ClearEntries();
    PopulateComboBox(Controls.UIScalePulldown, available_scales, Options.GetAppOption("Video", "UIUpscale"), 
        function(option)
	    	Options.SetAppOption("Video", "UIUpscale", option);
			Controls.ConfirmButton:SetDisabled(false);
	    end
    );
	Controls.UIScalePulldown:SetDisabled( not Options.IsUIUpscaleAllowed() );

    -- Performance Impact
    local performance_customStep = Controls.PerformanceSlider:GetNumSteps();
    local memory_customStep = Controls.MemorySlider:GetNumSteps();

    local performance_sliderStep = ImpactValueToSliderStep(Controls.PerformanceSlider, Options.GetGraphicsOption("Video", "PerformanceImpact"));
    
    Controls.PerformanceSlider:SetStep(performance_sliderStep);
    Controls.PerformanceValue:LocalizeAndSetText(performanceImpact_options[performance_sliderStep]);

    local performance_sliderValue = Controls.PerformanceSlider:GetValue();

    RegisterSliderCb(Controls.PerformanceSlider, 
    	function(option)
        
            -- Guard against multiple calls with the same value
            if(performance_sliderValue ~= option) then

                -- This has to happen before SetStepAndCall(), otherwise we get into an endless loop
                performance_sliderValue = option;

                -- We can't rely on option, because it is a float value [0.0 .. 1.0] and we need the step integer number
                performance_sliderStep = Controls.PerformanceSlider:GetStep();

                -- Update the option set with the new preset, which updates all other options (see OptionSet::ProcessExternally())
                Options.SetGraphicsOption("Video", "PerformanceImpact", SliderStepToImpactValue(Controls.PerformanceSlider, performance_sliderStep));
				Controls.ConfirmButton:SetDisabled(false);

                -- Update the text description
                Controls.PerformanceValue:LocalizeAndSetText(performanceImpact_options[performance_sliderStep]);

                if(performance_sliderStep ~= performance_customStep) then

                    if(Controls.MemorySlider:GetStep() == memory_customStep) then
                        -- The memory slider is set to "custom", so reset it to its default value
                        Controls.MemorySlider:SetStepAndCall(ImpactValueToSliderStep(Controls.MemorySlider, Options.GetGraphicsDefault("Video", "MemoryImpact")));
                    end

                    -- Update all settings in the UI if the performance impact changed to something other than "custom"
                    PopulateGraphicsOptions();

                else
                    -- The performance slider is set to "custom", so set the memory slider to "custom" as well
                    Controls.MemorySlider:SetStepAndCall(memory_customStep);
                end
                
            end
    	end
    );

    -- Memory Impact
    local memory_sliderStep = ImpactValueToSliderStep(Controls.MemorySlider, Options.GetGraphicsOption("Video", "MemoryImpact"));
    
    Controls.MemorySlider:SetStep(memory_sliderStep);
    Controls.MemoryValue:LocalizeAndSetText(memoryImpact_options[memory_sliderStep]);

    local memory_sliderValue = Controls.MemorySlider:GetValue();

    RegisterSliderCb(Controls.MemorySlider, 
    	function(option)
            
            -- Guard against multiple calls with the same value
            if(memory_sliderValue ~= option) then

                -- This has to happen before SetStepAndCall(), otherwise we get into an endless loop
                memory_sliderValue = option;

                -- We can't rely on option, because it is a float value [0.0 .. 1.0] and we need the step integer number
                memory_sliderStep = Controls.MemorySlider:GetStep();

                -- Update the option set with the new preset, which updates all other options (see OptionSet::ProcessExternally())
                Options.SetGraphicsOption("Video", "MemoryImpact", SliderStepToImpactValue(Controls.MemorySlider, memory_sliderStep));
				Controls.ConfirmButton:SetDisabled(false);

                -- Update the text description
                Controls.MemoryValue:LocalizeAndSetText(memoryImpact_options[memory_sliderStep]);

                if(memory_sliderStep ~= memory_customStep) then

                    if(Controls.PerformanceSlider:GetStep() == performance_customStep) then
                        -- The performance slider is set to "custom", so reset it to its default
                        Controls.PerformanceSlider:SetStepAndCall(ImpactValueToSliderStep(Controls.PerformanceSlider, Options.GetGraphicsDefault("Video", "PerformanceImpact")));
                    end

                    -- Update all settings in the UI if the memory impact changed to something other than "custom"
                    PopulateGraphicsOptions();

                else
                    -- The memory slider is set to "custom", so set the performance slider to "custom" as well
                    Controls.PerformanceSlider:SetStepAndCall(performance_customStep);
                end
                
            end
    	end
    );

    -------------------------------------------------------------------------------
    -- Advanced Settings
    -------------------------------------------------------------------------------

    -- VSync
    PopulateCheckBox(Controls.VSyncEnabledCheckbox, Options.GetGraphicsOption("Video", "VSync"),
        function(option)
            Options.SetGraphicsOption("Video", "VSync", option);
			Controls.ConfirmButton:SetDisabled(false);
        end
    );
	
    -- Tick Interval
    PopulateComboBox(Controls.TickIntervalPullDown, tickInterval_options, Options.GetAppOption("Performance", "TickIntervalInMS"), 
        function(option)
	    	Options.SetAppOption("Performance", "TickIntervalInMS", option);
			Controls.ConfirmButton:SetDisabled(false);
	    end
    );
    
    -- Fullscreen
	PopulateComboBox(Controls.FullScreenPullDown, windowed_options,  Options.GetAppOption("Video", "FullScreen"), 
        function(option)
		    Options.SetAppOption("Video", "FullScreen", option);

            -- In borderless mode, snap width/height to desktop size
            if option == BORDERLESS_OPTION then
            	Options.SetAppOption("Video", "RenderWidth",  Options.GetDisplayWidth());
			    Options.SetAppOption("Video", "RenderHeight", Options.GetDisplayHeight());
            end

            AdjustResolutionPulldown(option, is_in_game )

            _PromptResolutionAck = (option == FULLSCREEN_OPTION);
			Controls.ConfirmButton:SetDisabled(false);
	    end
    );	

    -- MSAA
    local nMaxMSAACount = UI.GetMaxMSAACount();
    
    local availableMSAAOptions = {};
	for i, v in ipairs(msaa_options) do
        local bValid = UI.CanHaveMSAAQuality(v[2][1], v[2][2])
        if(bValid) then
			table.insert(availableMSAAOptions, {v[1], v[2]});
        end
	end

    local ihvMSAAModes = nil;
    if UI.IsVendorAMD() then
        ihvMSAAModes = eqaa_options;
    elseif UI.IsVendorNVIDIA() then
        ihvMSAAModes = csaa_options;
    end

    if ihvMSAAModes ~= nil then
        for i, v in ipairs(ihvMSAAModes) do
            local bValid = UI.CanHaveMSAAQuality(v[2][1], v[2][2])
            if(bValid) then
			    table.insert(availableMSAAOptions, {v[1], v[2]});
            end
	    end
    end

    local nMSAACount = Options.GetGraphicsOption("Video", "MSAA");
    if nMSAACount == -1 then
        nMSAACount = nMaxMSAACount;
    end
    local nMSAAQuality = Options.GetGraphicsOption("Video", "MSAAQuality");

    -- PopulateComboBox() does a "pointer" compare with non POD, so we have to find the current sample / quality in the MSAA tables
    -- so that we can pass it into PopulateComboBox()
    local msaaValue = msaa_options[1][2];
    if nMSAAQuality == 0 then
        for i, v in ipairs(msaa_options) do
            if v[2][1] == nMSAACount and v[2][2] == nMSAAQuality then
                msaaValue = v[2];
                break;
            end
        end
    elseif ihvMSAAModes ~= nil then
        for i, v in ipairs(ihvMSAAModes) do
            if v[2][1] == nMSAACount and v[2][2] == nMSAAQuality then
                msaaValue = v[2];
                break;
            end
        end
    end

    PopulateComboBox(Controls.MSAAPullDown, availableMSAAOptions, msaaValue,
        function(option)
            Options.SetGraphicsOption("Video", "MSAA", option[1]);              -- First set the sliders to "custom", then set the new value, otherwise ProcessExternally() will overwrite the new value with a preset
            Options.SetGraphicsOption("Video", "MSAAQuality", option[2]);
			Controls.ConfirmButton:SetDisabled(false);
	    end
    );

    -- High-Resolution Asset Textures
    PopulateCheckBox(Controls.AssetTextureResolutionCheckbox, InvertOptionInt(Options.GetGraphicsOption("Video", "ReducedAssetTextures")),
        function(option)
            Controls.MemorySlider:SetStepAndCall(memory_customStep);                -- It's enough to set just one of the Impact sliders to "custom", the logic sets the other one
            Options.SetGraphicsOption("Video", "ReducedAssetTextures", not option); -- First set the sliders to "custom", then set the new value, otherwise ProcessExternally() will overwrite the new value with a preset
			Controls.ConfirmButton:SetDisabled(false);
            _PromptRestartGame = true;
        end
    );

    -- High-Quality Visual Effects
    PopulateComboBox(Controls.VFXDetailLevelPullDown, vfx_options, Options.GetGraphicsOption("General", "VFXDetailLevel"), 
        function(option)
            Controls.PerformanceSlider:SetStepAndCall(performance_customStep);  -- It's enough to set just one of the Impact sliders to "custom", the logic sets the other one
		    Options.SetGraphicsOption("General", "VFXDetailLevel", option);     -- First set the sliders to "custom", then set the new value, otherwise ProcessExternally() will overwrite the new value with a preset
			Controls.ConfirmButton:SetDisabled(false);
	    end
    );
	
    -------------------------------------------------------------------------------
    -- Advanced Settings - Lighting
    -------------------------------------------------------------------------------
    
    -- Bloom Enabled
    PopulateCheckBox(Controls.LightingBloomEnabledCheckbox, Options.GetGraphicsOption("Bloom", "EnableBloom"),
        function(option)
            Controls.PerformanceSlider:SetStepAndCall(performance_customStep);  -- It's enough to set just one of the Impact sliders to "custom", the logic sets the other one
            Options.SetGraphicsOption("Bloom", "EnableBloom", option);          -- First set the sliders to "custom", then set the new value, otherwise ProcessExternally() will overwrite the new value with a preset
			Controls.ConfirmButton:SetDisabled(false);
        end
    );

    -- Dynamic Lighting Enabled
    PopulateCheckBox(Controls.LightingDynamicLightingEnabledCheckbox, Options.GetGraphicsOption("DynamicLighting", "EnableDynamicLighting"),
        function(option)
            Controls.PerformanceSlider:SetStepAndCall(performance_customStep);              -- It's enough to set just one of the Impact sliders to "custom", the logic sets the other one
            Options.SetGraphicsOption("DynamicLighting", "EnableDynamicLighting", option);  -- First set the sliders to "custom", then set the new value, otherwise ProcessExternally() will overwrite the new value with a preset
			Controls.ConfirmButton:SetDisabled(false);
        end
    );
    
    -------------------------------------------------------------------------------
    -- Advanced Settings - Shadows
    -------------------------------------------------------------------------------

    -- Shadows Enabled
    PopulateCheckBox(Controls.ShadowsEnabledCheckbox, Options.GetGraphicsOption("Shadows", "EnableShadows"),
        function(option)
            Controls.PerformanceSlider:SetStepAndCall(performance_customStep);  -- It's enough to set just one of the Impact sliders to "custom", the logic sets the other one
            Options.SetGraphicsOption("Shadows", "EnableShadows", option);      -- First set the sliders to "custom", then set the new value, otherwise ProcessExternally() will overwrite the new value with a preset
            Controls.ShadowsResolutionPullDown:SetDisabled(not option);
			Controls.ConfirmButton:SetDisabled(false);
        end
    );

    -- Shadow Resolution
    PopulateComboBox(Controls.ShadowsResolutionPullDown, shadowResolution_options, Options.GetGraphicsOption("Video", "ShadowMapResolution"), 
        function(option)
            Controls.MemorySlider:SetStepAndCall(memory_customStep);            -- It's enough to set just one of the Impact sliders to "custom", the logic sets the other one
		    Options.SetGraphicsOption("Video", "ShadowMapResolution", option);  -- First set the sliders to "custom", then set the new value, otherwise ProcessExternally() will overwrite the new value with a preset
			Controls.ConfirmButton:SetDisabled(false);
	    end,
        Options.GetGraphicsOption("Shadows", "EnableShadows") == 0
    );

	-- Cloud Shadows Enabled
	PopulateCheckBox(Controls.CloudShadowsEnabledCheckbox, Options.GetGraphicsOption("CloudShadows", "EnableCloudShadows"),
        function(option)
            Controls.PerformanceSlider:SetStepAndCall(performance_customStep);  -- It's enough to set just one of the Impact sliders to "custom", the logic sets the other one
            Options.SetGraphicsOption("CloudShadows", "EnableCloudShadows", option);      -- First set the sliders to "custom", then set the new value, otherwise ProcessExternally() will overwrite the new value with a preset
			Controls.ConfirmButton:SetDisabled(false);
        end
    );
    -------------------------------------------------------------------------------
    -- Advanced Settings - Overlay
    -------------------------------------------------------------------------------

    -- Overlay Resolution
    
    -- Screen-Space Overlay Enabled
    PopulateCheckBox(Controls.SSOverlayEnabledCheckbox, Options.GetGraphicsOption("General", "ScreenSpaceOverlay"),
        function(option)
            Controls.PerformanceSlider:SetStepAndCall(performance_customStep);  -- It's enough to set just one of the Impact sliders to "custom", the logic sets the other one
            Options.SetGraphicsOption("General", "ScreenSpaceOverlay", option); -- First set the sliders to "custom", then set the new value, otherwise ProcessExternally() will overwrite the new value with a preset
			Controls.ConfirmButton:SetDisabled(false);
        end
    );
        
    -------------------------------------------------------------------------------
    -- Advanced Settings - Terrain
    -------------------------------------------------------------------------------

    -- Terrain Quality
	PopulateComboBox(Controls.TerrainQualityPullDown, terrainQuality_options, Options.GetGraphicsOption("Terrain", "TerrainQuality"), 
        function(option)
             Controls.PerformanceSlider:SetStepAndCall(performance_customStep); -- It's enough to set just one of the Impact sliders to "custom", the logic sets the other one
	    	 Options.SetGraphicsOption("Terrain", "TerrainQuality", option);    -- First set the sliders to "custom", then set the new value, otherwise ProcessExternally() will overwrite the new value with a preset
			 Controls.ConfirmButton:SetDisabled(false);
	    	 _PromptRestartGame = true;
	    end
    );

    -- Terrain Synthesis
    local terrainSynthesis_option = Options.GetGraphicsOption("Terrain", "TerrainSynthesisDetailLevel");

    -- 1 = full-res, 2 = low-res, because of course.
    if(terrainSynthesis_option == 2) then 
        terrainSynthesis_option = 0;
    end

    PopulateCheckBox(Controls.TerrainSynthesisCheckbox, terrainSynthesis_option,
        function(option)
            Controls.PerformanceSlider:SetStepAndCall(performance_customStep);  -- It's enough to set just one of the Impact sliders to "custom", the logic sets the other one
            -- First set the sliders to "custom", then set the new value, otherwise ProcessExternally() will overwrite the new value with a preset
            -- 1 = full-res, 2 = low-res, because of course.
            if(option) then
                Options.SetGraphicsOption("Terrain", "TerrainSynthesisDetailLevel", 1);
            else
                Options.SetGraphicsOption("Terrain", "TerrainSynthesisDetailLevel", 2);
            end

			Controls.ConfirmButton:SetDisabled(false);
            _PromptRestartGame = true;
        end
    );

    -- High-Resolution Textures
    PopulateCheckBox(Controls.TerrainTextureResolutionCheckbox, InvertOptionInt(Options.GetGraphicsOption("Terrain", "ReducedTerrainMaterials")),
        function(option)
            Controls.MemorySlider:SetStepAndCall(memory_customStep);                        -- It's enough to set just one of the Impact sliders to "custom", the logic sets the other one
            Options.SetGraphicsOption("Terrain", "ReducedTerrainMaterials", not option);    -- First set the sliders to "custom", then set the new value, otherwise ProcessExternally() will overwrite the new value with a preset
			Controls.ConfirmButton:SetDisabled(false);
        end
    );

    -- Low-quality Shader
    PopulateCheckBox(Controls.TerrainShaderCheckbox, InvertOptionInt(Options.GetGraphicsOption("Terrain", "LowQualityTerrainShader")),
        function(option)
            Controls.PerformanceSlider:SetStepAndCall(performance_customStep);              -- It's enough to set just one of the Impact sliders to "custom", the logic sets the other one
            Options.SetGraphicsOption("Terrain", "LowQualityTerrainShader", not option);    -- First set the sliders to "custom", then set the new value, otherwise ProcessExternally() will overwrite the new value with a preset

            Controls.TerrainAOEnabledCheckbox:SetDisabled(not option);
            
            local bAODropDownEnabled = option and Options.GetGraphicsOption("AO", "EnableAO") == 1;
            Controls.TerrainAOResolutionPullDown:SetDisabled(not bAODropDownEnabled);
			Controls.ConfirmButton:SetDisabled(false);
        end
    );

    -- Ambient Occlusion Enabled
    PopulateCheckBox(Controls.TerrainAOEnabledCheckbox, Options.GetGraphicsOption("AO", "EnableAO"),
        function(option)
            Controls.PerformanceSlider:SetStepAndCall(performance_customStep);  -- It's enough to set just one of the Impact sliders to "custom", the logic sets the other one
            Options.SetGraphicsOption("AO", "EnableAO", option);                -- First set the sliders to "custom", then set the new value, otherwise ProcessExternally() will overwrite the new value with a preset
			Controls.ConfirmButton:SetDisabled(false);
            Controls.TerrainAOResolutionPullDown:SetDisabled(not option);
        end,
        Options.GetGraphicsOption("Terrain", "LowQualityTerrainShader") == 1
    );

    -- Ambient Occlusion Render and Depth Resolutions
    PopulateComboBox(Controls.TerrainAOResolutionPullDown, aoResolution_options, Options.GetGraphicsOption("Video", "AORenderResolution"), 
        function(option)
            Controls.MemorySlider:SetStepAndCall(memory_customStep);            -- It's enough to set just one of the Impact sliders to "custom", the logic sets the other one
		    Options.SetGraphicsOption("Video", "AORenderResolution", option);   -- First set the sliders to "custom", then set the new value, otherwise ProcessExternally() will overwrite the new value with a preset
            Options.SetGraphicsOption("Video", "AODepthResolution", option);
			Controls.ConfirmButton:SetDisabled(false);
	    end,
        Options.GetGraphicsOption("AO", "EnableAO") == 0 or Options.GetGraphicsOption("Terrain", "LowQualityTerrainShader") == 1
    );

    -- Clutter Detail Level
    PopulateCheckBox(Controls.TerrainClutterCheckbox, Options.GetGraphicsOption("General", "ClutterDetailLevel"),
        function(option)
            Controls.PerformanceSlider:SetStepAndCall(performance_customStep);  -- It's enough to set just one of the Impact sliders to "custom", the logic sets the other one
            Options.SetGraphicsOption("General", "ClutterDetailLevel", option); -- First set the sliders to "custom", then set the new value, otherwise ProcessExternally() will overwrite the new value with a preset
			Controls.ConfirmButton:SetDisabled(false);
        end
    );

    -------------------------------------------------------------------------------
    -- Advanced Settings - Water
    -------------------------------------------------------------------------------

    -- Water Quality
    PopulateCheckBox(Controls.WaterResolutionCheckbox, InvertOptionInt(Options.GetGraphicsOption("General", "UseLowResWater")),
        function(option)
            Controls.MemorySlider:SetStepAndCall(memory_customStep);            -- It's enough to set just one of the Impact sliders to "custom", the logic sets the other one
            Options.SetGraphicsOption("General", "UseLowResWater", not option); -- First set the sliders to "custom", then set the new value, otherwise ProcessExternally() will overwrite the new value with a preset
			Controls.ConfirmButton:SetDisabled(false);
        end
    );

    -- Water Shader
    PopulateCheckBox(Controls.WaterShaderCheckbox, InvertOptionInt(Options.GetGraphicsOption("General", "UseLowQualityWaterShader")),
        function(option)
            -- Only high-quality water shader has reflections
            Controls.ReflectionPassesPullDown:SetDisabled(not option);

            Controls.PerformanceSlider:SetStepAndCall(performance_customStep);              -- It's enough to set just one of the Impact sliders to "custom", the logic sets the other one
            Options.SetGraphicsOption("General", "UseLowQualityWaterShader", not option);   -- First set the sliders to "custom", then set the new value, otherwise ProcessExternally() will overwrite the new value with a preset
			Controls.ConfirmButton:SetDisabled(false);
        end
    );

	-------------------------------------------------------------------------------
    -- Advanced Settings - Reflections
    -------------------------------------------------------------------------------

	 -- Screen-space Reflection Passes
    PopulateComboBox(Controls.ReflectionPassesPullDown, reflectionPasses_options, Options.GetGraphicsOption("General", "SSReflectPasses"), 
        function(option)
            Controls.PerformanceSlider:SetStepAndCall(performance_customStep);  -- It's enough to set just one of the Impact sliders to "custom", the logic sets the other one
		    Options.SetGraphicsOption("General", "SSReflectPasses", option);    -- First set the sliders to "custom", then set the new value, otherwise ProcessExternally() will overwrite the new value with a preset
			Controls.ConfirmButton:SetDisabled(false);
		end,
		Options.GetGraphicsOption("General", "UseLowQualityWaterShader") == 1
    );

    -------------------------------------------------------------------------------
    -- Advanced Settings - Leaders
    -------------------------------------------------------------------------------

	-- Update the Motion Blur checkbox when leader quality changes
	local UpdateMotionBlurCheckbox = function(eLeaderQuality)
		if UI.LeaderQualityAllowsMotionBlur(eLeaderQuality) then
			local bEnabled = Options.GetGraphicsOption("Leaders", "EnableMotionBlur") ~= 0;
			Controls.MotionBlurEnabledCheckbox:SetDisabled(false);
			Controls.MotionBlurEnabledCheckbox:SetSelected(bEnabled);
		else
			Controls.MotionBlurEnabledCheckbox:SetSelected(false);
			Controls.MotionBlurEnabledCheckbox:SetDisabled(true);
		end
	end

	-- Leader Quality
    PopulateComboBox(Controls.LeaderQualityPullDown, leaderQuality_options, Options.GetGraphicsOption("Leaders", "Quality"), 
        function(option)
            Controls.PerformanceSlider:SetStepAndCall(performance_customStep);  -- It's enough to set just one of the Impact sliders to "custom", the logic sets the other one
		    Options.SetGraphicsOption("Leaders", "Quality", option);     -- First set the sliders to "custom", then set the new value, otherwise ProcessExternally() will overwrite the new value with a preset
			if (UI.LeaderQualityRequiresRestart(option)) then
				_PromptRestartGame = true;
			end
			UpdateMotionBlurCheckbox(option);
			Controls.ConfirmButton:SetDisabled(false);
	    end
    );
    
    -- Leader Motion Blur
    PopulateCheckBox(Controls.MotionBlurEnabledCheckbox, Options.GetGraphicsOption("Leaders", "EnableMotionBlur"),
        function(option)
            Controls.MemorySlider:SetStepAndCall(memory_customStep);          -- It's enough to set just one of the Impact sliders to "custom", the logic sets the other one
            Options.SetGraphicsOption("Leaders", "EnableMotionBlur", option); -- First set the sliders to "custom", then set the new value, otherwise ProcessExternally() will overwrite the new value with a preset
			Controls.ConfirmButton:SetDisabled(false);
        end
    );

    -- Disable things we aren't allowed to change when game is running
    Controls.UIScalePulldown:SetDisabled( is_in_game or (not Options.IsUIUpscaleAllowed()) )
    Controls.FullScreenPullDown:SetDisabled( is_in_game )
    Controls.TerrainSynthesisCheckbox:SetDisabled( is_in_game )
    Controls.TerrainQualityPullDown:SetDisabled( is_in_game )
	Controls.TerrainTextureResolutionCheckbox:SetDisabled( is_in_game )
	Controls.TerrainShaderCheckbox:SetDisabled( is_in_game )
    Controls.TerrainSynthesisCheckbox:SetDisabled( is_in_game )
    Controls.AdapterPullDown:SetDisabled( is_in_game )

    -- Put resolution dropdown in the right state for current borderless setting
    AdjustResolutionPulldown( Options.GetAppOption("Video", "FullScreen"), is_in_game )

	-- Put leader motion blur checkbox in right state for current leader quality setting
	UpdateMotionBlurCheckbox( Options.GetGraphicsOption("Leaders", "Quality") );
end

-------------------------------------------------------------------------------
-- "OMG This is so hard-coded."  Yep. It is.
-- This will be replaced w/ 'real' code eventually.    (... or will it :))
-------------------------------------------------------------------------------
function TemporaryHardCodedGoodness()

    local boolean_options = {
		{"LOC_OPTIONS_ENABLED", 1},
		{"LOC_OPTIONS_DISABLED", 0},
	};

	local tutorial_options = {
		{"LOC_OPTIONS_DISABLED", -1},
		{"LOC_OPTIONS_TUTORIAL_FAMILIAR_STRATEGY", 0},
		{"LOC_OPTIONS_TUTORIAL_FAMILIAR_CIVILIZATION", 1},
	};

	local currentTutorialLevel = Options.GetUserOption("Gameplay", "TutorialLevel");
	if(HasExpansion1() or currentTutorialLevel == 2) then
		table.insert(tutorial_options, {"LOC_OPTIONS_TUTORIAL_NEW_TO_XP1", 2});
	end

	local currentTutorialLevel = Options.GetUserOption("Gameplay", "TutorialLevel");
	if(HasExpansion2() or currentTutorialLevel == 3) then
		table.insert(tutorial_options, {"LOC_OPTIONS_TUTORIAL_NEW_TO_XP2", 3});
	end

	local autosave_settings = {
		{"1", 1},
		{"2", 2},
		{"3", 3},
		{"4", 4},
		{"5", 5},
		{"6", 6},
		{"7", 7},
		{"8", 8},
		{"9", 9},
		{"10", 10},
		{"50", 50},
		{"100", 100},
		{"LOC_OPTIONS_ALL_AUTOSAVES", 999999},
	};

	-- Quick note about language names.
	-- Not all languages return in upper-case.  This is because certain languages don't 
	-- upper-case language names! 
	-- However, since we are using them as single terms, we do want to title case it.
	local currentLanguage = Locale.GetCurrentLanguage();
	local currentLocale = currentLanguage and currentLanguage.Type or "en_US";


	local language_options = {};
	local languages = Locale.GetLanguages();

	for i, v in ipairs(languages) do
		table.insert(language_options, {
			Locale.Lookup("{1: title}", v.Name),
			v.Locale,
		});
	end
	
	function LangName(l)
		return Locale.Lookup("{1: title}", Locale.GetLanguageDisplayName(l, currentLocale));
	end

	local audio_language_options = {};
	local audioLanguages = Locale.GetAudioLanguages();

	for i, v in ipairs(audioLanguages) do
		table.insert(audio_language_options, {
			LangName(v.Locale), 
			v.AudioLanguage
		});
	end	

	local clock_options = {
		{"LOC_OPTIONS_12HOUR", 0},
		{"LOC_OPTIONS_24HOUR", 1},
	};

    local grab_options = {
		{"LOC_OPTIONS_NEVER", 0},
		{"LOC_OPTIONS_WINDOW_MODE_FULLSCREEN", 1},
		{"LOC_OPTIONS_ALWAYS", 2},
	};

	local ribbon_options = {
		{"LOC_OPTIONS_RIBBON_STATS_ALWAYS_HIDE", 0},
		{"LOC_OPTIONS_RIBBON_STATS_MOUSE_OVER", 1},
		{"LOC_OPTIONS_RIBBON_STATS_ALWAYS_SHOW", 2},
	}

	-- Pulldown options for PlayByCloudEndTurnBehavior.
	local playByCloud_endturn_options = {
		{"LOC_OPTIONS_PLAYBYCLOUD_END_TURN_BEHAVIOR_ASK_ME", PlayByCloudEndTurnBehaviorType.PBC_ENDTURN_ASK_ME},
		{"LOC_OPTIONS_PLAYBYCLOUD_END_TURN_BEHAVIOR_DO_NOTHING", PlayByCloudEndTurnBehaviorType.PBC_ENDTURN_DO_NOTHING},
		{"LOC_OPTIONS_PLAYBYCLOUD_END_TURN_BEHAVIOR_EXIT_TO_MAINMENU", PlayByCloudEndTurnBehaviorType.PBC_ENDTURN_EXIT_MAINMENU},	
	};

		-- Pulldown options for PlayByCloudClientReadyBehavior.
	local playByCloud_ready_options = {
		{"LOC_OPTIONS_PLAYBYCLOUD_READY_BEHAVIOR_ASK_ME", PlayByCloudReadyBehaviorType.PBC_READY_ASK_ME},
		{"LOC_OPTIONS_PLAYBYCLOUD_READY_BEHAVIOR_DO_NOTHING", PlayByCloudReadyBehaviorType.PBC_READY_DO_NOTHING},
		{"LOC_OPTIONS_PLAYBYCLOUD_READY_BEHAVIOR_EXIT_TO_LOBBY", PlayByCloudReadyBehaviorType.PBC_READY_EXIT_LOBBY},	
	};

	-- Pulldown options for ColorblindAdaptation.
	local colorblindAdaptation_options = {
		{"LOC_OPTIONS_CBADAPT_DO_NOTHING", 0},
		{"LOC_OPTIONS_CBADAPT_PROTANOPIA", 1},
		{"LOC_OPTIONS_CBADAPT_DEUTERANOPIA", 2},
		{"LOC_OPTIONS_CBADAPT_TRITANOPIA", 3},
	};

	-- Pulldown options for UseRGBLighting
	local lightingRGB_options = {
		{"LOC_OPTIONS_DISABLED", 0},
		{"LOC_OPTIONS_ENABLED", 1},
	};

	-- Populate the pull-downs because we can't do this in XML.
	--Gameplay
	PopulateComboBox(Controls.QuickCombatPullDown, boolean_options, Options.GetUserOption("Gameplay", "QuickCombat"), function(option)
		Options.SetUserOption("Gameplay", "QuickCombat", option);
		Controls.ConfirmButton:SetDisabled(false);
	end, 
	UserConfiguration.IsValueLocked("QuickCombat"));
	
	
	PopulateComboBox(Controls.QuickMovementPullDown, boolean_options, Options.GetUserOption("Gameplay", "QuickMovement"), function(option)
		Options.SetUserOption("Gameplay", "QuickMovement", option);
		Controls.ConfirmButton:SetDisabled(false);
	end,
	UserConfiguration.IsValueLocked("QuickMovement"));

	PopulateComboBox(Controls.AutoEndTurnPullDown, boolean_options, Options.GetUserOption("Gameplay", "AutoEndTurn"), function(option)
		Options.SetUserOption("Gameplay", "AutoEndTurn", option);
		Controls.ConfirmButton:SetDisabled(false);
	end,
	UserConfiguration.IsValueLocked("AutoEndTurn"));

	PopulateComboBox(Controls.CityRangeAttackTurnBlockingPullDown, boolean_options, Options.GetUserOption("Gameplay", "CityRangeAttackTurnBlocking"), function(option)
		Options.SetUserOption("Gameplay", "CityRangeAttackTurnBlocking", option);
		Controls.ConfirmButton:SetDisabled(false);
	end,
	UserConfiguration.IsValueLocked("CityRangeAttackTurnBlocking"));

	PopulateComboBox(Controls.TunerPullDown, boolean_options, Options.GetAppOption("Debug", "EnableTuner"), function(option)
		Options.SetAppOption("Debug", "EnableTuner", option);
		Controls.ConfirmButton:SetDisabled(false);
		_PromptRestartApp = true;
	end);	

	-- Only steam supports the auto download of mods feature.
	if(Network.GetNetworkPlatform() == NetworkPlatform.NETWORK_PLATFORM_STEAM) then
		PopulateComboBox(Controls.AutoDownloadPullDown, boolean_options, Options.GetUserOption("Multiplayer", "AutoModDownload"), function(option)
			Options.SetUserOption("Multiplayer", "AutoModDownload", option);
			Controls.ConfirmButton:SetDisabled(false);
		end);	
	else
		Controls.AutoDownloadPullDown:SetHide(true);
		Controls.AutoDownloadLabel:SetHide(true);
	end

	PopulateComboBox(Controls.TutorialPullDown, tutorial_options, Options.GetUserOption("Gameplay", "TutorialLevel"), function(option)
		Options.SetUserOption("Gameplay", "TutorialLevel", option);
		Options.SetUserOption("Tutorial", "HasChosenTutorialLevel", 1);
		Controls.ConfirmButton:SetDisabled(false);
	end,
	UserConfiguration.IsValueLocked("TutorialLevel"));	

	PopulateComboBox(Controls.SaveFrequencyPullDown, autosave_settings, Options.GetUserOption("Gameplay", "AutoSaveFrequency"), function(option)
		Options.SetUserOption("Gameplay", "AutoSaveFrequency", option);
		Controls.ConfirmButton:SetDisabled(false);
	end);	

	PopulateComboBox(Controls.SaveKeepPullDown, autosave_settings, Options.GetUserOption("Gameplay", "AutoSaveKeepCount"), function(option)
		Options.SetUserOption("Gameplay", "AutoSaveKeepCount", option);
		Controls.ConfirmButton:SetDisabled(false);
	end);	

	local fTOD = Options.GetGraphicsOption("General", "DefaultTimeOfDay");
	Controls.TODSlider:SetValue(fTOD / TIME_SCALE);
	UpdateTimeLabel(fTOD);
    RegisterSliderCb(Controls.TODSlider, function(value)
		local fTime = value * TIME_SCALE;
        Options.SetGraphicsOption("General", "DefaultTimeOfDay", fTime, 0);
        UI.SetAmbientTimeOfDay(fTime);
		UpdateTimeLabel(fTime);
		Controls.ConfirmButton:SetDisabled(false);
    end);

    PopulateCheckBox(Controls.TimeOfDayCheckbox, Options.GetGraphicsOption("General", "AmbientTimeOfDay"), function(option)
        Options.SetGraphicsOption("General", "AmbientTimeOfDay", option);
        UI.SetAmbientTimeOfDayAnimating(option);
		Controls.ConfirmButton:SetDisabled(false);
    end
    );

	Controls.HistoricMomentsAnimStack:SetHide(not HasExpansion1());
	if HasExpansion1() then
		PopulateCheckBox(Controls.HistoricMomentsAnimCheckbox, Options.GetUserOption("General", "PlayHistoricMomentAnimation"), function(option)
			Options.SetUserOption("Interface", "PlayHistoricMomentAnimation", option and 1 or 0);
			Controls.ConfirmButton:SetDisabled(false);
		end);
	end

	PopulateCheckBox(Controls.TouchInputCheckbox, Options.GetAppOption("UI", "IsTouchScreenEnabled"), function(option)
		Options.SetAppOption("UI", "IsTouchScreenEnabled", option and 1 or 0);
		Controls.ConfirmButton:SetDisabled(false);
	end);


	PopulateEditBox(Controls.LANPlayerNameEdit, Options.GetUserOption("Multiplayer", "LANPlayerName"), function(option)
		UserConfiguration.SetValue("LANPlayerName", option);
		Options.SetUserOption("Multiplayer", "LANPlayerName", option);
		Controls.ConfirmButton:SetDisabled(false);
	end,
	UserConfiguration.IsValueLocked("LANPlayerName"));

	-- PlayByCloud Webhook
	PopulateEditBox(Controls.PBCTurnWebhookEdit, Options.GetUserOption("Multiplayer", "TurnWebHookURL"), 
		function(option)
			Options.SetUserOption("Multiplayer", "TurnWebHookURL", option);
			Controls.ConfirmButton:SetDisabled(false);
		end
	);

	PopulateComboBox(Controls.TurnWebhookFreqPullDown, webhookFreq_options,  Options.GetUserOption("Multiplayer", "TurnWebHookFrequency"), 
        function(option)
		    Options.SetUserOption("Multiplayer", "TurnWebHookFrequency", option);
			Controls.ConfirmButton:SetDisabled(false);
	    end
    );	

	-- Language
	PopulateComboBox(Controls.DisplayLanguagePullDown, language_options, Options.GetAppOption("Language", "DisplayLanguage"), function(option)
		Options.SetAppOption("Language", "DisplayLanguage", option);
		Controls.ConfirmButton:SetDisabled(false);
		_PromptRestartApp = true;
	end);	

	PopulateComboBox(Controls.SpokenLanguagePullDown, audio_language_options, Options.GetAppOption("Language", "AudioLanguage"), function(option)
		Options.SetAppOption("Language", "AudioLanguage", option);
		Controls.ConfirmButton:SetDisabled(false);
		_PromptRestartApp = true;
	end);	

    PopulateCheckBox(Controls.EnableSubtitlesCheckbox, Options.GetAppOption("Language", "EnableSubtitles"), function(value)
        if (value == true) then
            Options.SetAppOption("Language", "EnableSubtitles", 1);
        else
            Options.SetAppOption("Language", "EnableSubtitles", 0);
        end
		Controls.ConfirmButton:SetDisabled(false);
    end);

    -- Sound
	Controls.MasterVolSlider:SetValue(Options.GetAudioOption("Sound", "Master Volume") / 100.0);
    RegisterSliderCb(Controls.MasterVolSlider, 
    	function(value)
            Options.SetAudioOption("Sound", "Master Volume", value * 100.0, 0);
			Controls.ConfirmButton:SetDisabled(false);
            UI.PlaySound("Bus_Feedback_Master");
    	end
    );

    Controls.MusicVolSlider:SetValue(Options.GetAudioOption("Sound", "Music Volume") / 100.0);
    RegisterSliderCb(Controls.MusicVolSlider, 
    	function(value)
            Options.SetAudioOption("Sound", "Music Volume", value * 100.0, 0);
			Controls.ConfirmButton:SetDisabled(false);
    	end
    );

    Controls.SFXVolSlider:SetValue(Options.GetAudioOption("Sound", "SFX Volume") / 100.0);
    RegisterSliderCb(Controls.SFXVolSlider, 
    	function(value)
            Options.SetAudioOption("Sound", "SFX Volume", value * 100.0, 0);
			Controls.ConfirmButton:SetDisabled(false);
            UI.PlaySound("Bus_Feedback_SFX");
    	end
    );

	Controls.AmbVolSlider:SetValue(Options.GetAudioOption("Sound", "Ambience Volume") / 100.0);
    RegisterSliderCb(Controls.AmbVolSlider, 
    	function(value)
            Options.SetAudioOption("Sound", "Ambience Volume", value * 100.0, 0);
			Controls.ConfirmButton:SetDisabled(false);
            UI.PlaySound("Bus_Feedback_Ambience");
    	end
    );

	Controls.SpeechVolSlider:SetValue(Options.GetAudioOption("Sound", "Speech Volume") / 100.0);
    RegisterSliderCb(Controls.SpeechVolSlider, 
    	function(value)
            Options.SetAudioOption("Sound", "Speech Volume", value * 100.0, 0);
			Controls.ConfirmButton:SetDisabled(false);
            UI.PlaySound("Bus_Feedback_Speech");
    	end
    );

    PopulateCheckBox(Controls.MuteFocusCheckbox, Options.GetAudioOption("Sound", "Mute Focus"),
        function(value)
            if (value == true) then
                Options.SetAudioOption("Sound", "Mute Focus", 1, 0);
            else
                Options.SetAudioOption("Sound", "Mute Focus", 0, 0);
            end
			Controls.ConfirmButton:SetDisabled(false);
        end
            );

        --    if (Options.GetAudioOption("Sound", "Mute Focus") == 0) then
        --        Controls.MuteFocusCheckbox:SetSelected(false);
        --    else
--        Controls.MuteFocusCheckbox:SetSelected(true);
--    end
--    Controls.MuteFocusCheckbox:RegisterCallback( Mouse.eLClick,
--        function(value)
--            if (value == true) then
--                Options.SetAudioOption("Sound", "Mute Focus", 1, 0);
--            else
--                Options.SetAudioOption("Sound", "Mute Focus", 0, 0);
--            end
--        end
--    );

    -- Interface
		PopulateComboBox(Controls.ClockFormat, clock_options, Options.GetUserOption("Interface", "ClockFormat"), function(option)
		UserConfiguration.SetValue("ClockFormat", option);
		Options.SetUserOption("Interface", "ClockFormat", option);
		Controls.ConfirmButton:SetDisabled(false);
	end,
	UserConfiguration.IsValueLocked("ClockFormat"));	

	PopulateComboBox(Controls.PlayByCloudEndTurnBehavior, playByCloud_endturn_options, Options.GetUserOption("Interface", "PlayByCloudEndTurnBehavior"), 
		function(option)
			Options.SetUserOption("Interface", "PlayByCloudEndTurnBehavior", option);
			Controls.ConfirmButton:SetDisabled(false);
		end
	);

		PopulateComboBox(Controls.PlayByCloudClientReadyBehavior, playByCloud_ready_options, Options.GetUserOption("Interface", "PlayByCloudClientReadyBehavior"), 
		function(option)
			Options.SetUserOption("Interface", "PlayByCloudClientReadyBehavior", option);
			Controls.ConfirmButton:SetDisabled(false);
		end
	);

	PopulateComboBox(Controls.ColorblindAdaptation, colorblindAdaptation_options, Options.GetAppOption("UI", "ColorblindAdaptation"), function(option)
		Options.SetAppOption("UI", "ColorblindAdaptation", option);
		Controls.ConfirmButton:SetDisabled(false);
		_PromptRestartGame = true;
    end);	

	PopulateComboBox(Controls.RGBControl, lightingRGB_options, Options.GetAppOption("UI", "UseRGBLighting"), function(option)
		Options.SetAppOption("UI", "UseRGBLighting", option);
		Controls.ConfirmButton:SetDisabled(false);
		_PromptRestartApp = true;
    end);	

    -- we can't allow this to be changed in-game, too many things cache the values
    if IsInGame() then
        Controls.ColorblindAdaptation:SetDisabled(true);
    else
        Controls.ColorblindAdaptation:SetDisabled(false);
    end

	PopulateComboBox(Controls.StartInStrategicView, boolean_options, Options.GetUserOption("Gameplay", "StartInStrategicView"), function(option)
		Options.SetUserOption("Gameplay", "StartInStrategicView", option);
		Controls.ConfirmButton:SetDisabled(false);
		_PromptRestartGame = true;
	end);

    PopulateComboBox(Controls.MouseGrabPullDown, grab_options, Options.GetAppOption("Video", "MouseGrab"), function(option)
		Options.SetAppOption("Video", "MouseGrab", option);
		Controls.ConfirmButton:SetDisabled(false);
        _PromptRestartApp = true;
	end);

	PopulateComboBox(Controls.EdgeScrollPullDown, boolean_options, Options.GetUserOption("Gameplay", "EdgePan"), function(option)
		Options.SetUserOption("Gameplay", "EdgePan", option);
		Controls.ConfirmButton:SetDisabled(false);
        _PromptRestartApp = true;
	end, 
	UserConfiguration.IsValueLocked("EdgePan"));

	PopulateComboBox(Controls.AutoProdQueuePullDown, boolean_options, Options.GetUserOption("Gameplay", "AutoProdQueue"), function(option)
		Options.SetUserOption("Gameplay", "AutoProdQueue", option);
		Controls.ConfirmButton:SetDisabled(false);
	end, 
	UserConfiguration.IsValueLocked("AutoProdQueue"));

	PopulateComboBox(Controls.ReplaceDragWithClickPullDown, boolean_options, Options.GetUserOption("Interface", "ReplaceDragWithClick"), function(option)
		Options.SetUserOption("Interface", "ReplaceDragWithClick", option);
		Controls.ConfirmButton:SetDisabled(false);
		_PromptRestartApp = true;
	end, 
	UserConfiguration.IsValueLocked("ReplaceDragWithClick"));

	PopulateComboBox(Controls.UnitCyclingPullDown, boolean_options, Options.GetUserOption("Gameplay", "AutoUnitCycle"), function(option)
		Options.SetUserOption("Gameplay", "AutoUnitCycle", option);
		Controls.ConfirmButton:SetDisabled(false);
	end,
	UserConfiguration.IsValueLocked("AutoUnitCycle"));

	PopulateComboBox(Controls.RibbonStatsPullDown, ribbon_options, Options.GetUserOption("Interface", "RibbonStats"), function(option)
		Options.SetUserOption("Interface", "RibbonStats", option);
		Controls.ConfirmButton:SetDisabled(false);
	end,
	UserConfiguration.IsValueLocked("RibbonStats"));
	
	local chatTextSize  : number = Options.GetUserOption("Interface", "ChatTextValue") or MIN_CHAT_TEXT_SIZE;
	local chatSliderVal : number;
	if(chatTextSize == MAX_CHAT_TEXT_SIZE) then
		chatSliderVal = 1;
	end
	if(chatTextSize == 16) then
		chatSliderVal = .8;
	end
	if(chatTextSize == 14) then
		chatSliderVal = .4;
	end
	if(chatTextSize == MIN_CHAT_TEXT_SIZE) then
		chatSliderVal = 0;
	end
	Controls.ChatTextSizeSlider:SetValue(chatSliderVal);
	Controls.ChatTextValue:LocalizeAndSetText("LOC_OPTIONS_CHAT_TEXT_SIZE_VALUE", chatTextSize);
	RegisterSliderCb(Controls.ChatTextSizeSlider, function(value)
		local adjustedValue : number;
		if(value == 1) then
			adjustedValue = MAX_CHAT_TEXT_SIZE;
		end
		if(value < 1) then
			adjustedValue = 16;
		end
		if(value < .5) then
			adjustedValue = 14;
		end
		if(value < .3) then
			adjustedValue = MIN_CHAT_TEXT_SIZE;
		end
		adjustedValue = math.clamp(adjustedValue, MIN_CHAT_TEXT_SIZE, MAX_CHAT_TEXT_SIZE);
		Options.SetUserOption("Interface", "ChatTextValue", adjustedValue);
		Controls.ConfirmButton:SetDisabled(false);
		Controls.ChatTextValue:LocalizeAndSetText("LOC_OPTIONS_CHAT_TEXT_SIZE_VALUE", adjustedValue);
	end);

	local minimapSize : number = Options.GetGraphicsOption("General", "MinimapSize") or 0.0;
	Controls.MinimapSizeSlider:SetValue(minimapSize);
	UI.SetMinimapSize(minimapSize);
	RegisterSliderCb(Controls.MinimapSizeSlider, function(value)
		Options.SetGraphicsOption("General", "MinimapSize", value);
		Controls.ConfirmButton:SetDisabled(false);
		UI.SetMinimapSize(value);
	end);

	local plotTooltipDelay : number = Options.GetUserOption("Interface", "PlotTooltipDelay") or 0.2;
	Controls.PlotToolTipDelaySlider:SetValue(plotTooltipDelay / 2);
	Controls.PlotToolTipDelayValue:LocalizeAndSetText("LOC_OPTIONS_PLOT_TOOLTIP_DELAY_VALUE", plotTooltipDelay);
	RegisterSliderCb(Controls.PlotToolTipDelaySlider, function(value)
		local adjustedValue : number = value * 2;
		Options.SetUserOption("Interface", "PlotTooltipDelay", adjustedValue);
		Controls.ConfirmButton:SetDisabled(false);
		Controls.PlotToolTipDelayValue:LocalizeAndSetText("LOC_OPTIONS_PLOT_TOOLTIP_DELAY_VALUE", adjustedValue);
	end);

	local scrollSpeed : number = Options.GetUserOption("Interface", "ScrollSpeed") or 1.0;
	if(scrollSpeed > MAX_SCROLL_SPEED or scrollSpeed < MIN_SCROLL_SPEED)then
		scrollSpeed = math.clamp(scrollSpeed, MIN_SCROLL_SPEED, (MAX_SCROLL_SPEED/2.0));
		Options.SetUserOption("Interface", "ScrollSpeed", scrollSpeed);
		Options.SaveOptions();
	end
	Controls.ScrollSpeedSlider:SetValue((scrollSpeed - MIN_SCROLL_SPEED) / MAX_SCROLL_SPEED);
	Controls.ScrollSpeedValue:LocalizeAndSetText("LOC_OPTIONS_SCROLL_SPEED_VALUE", scrollSpeed*100);	-- Show 0 to 100 instead of 0 to 1
	RegisterSliderCb(Controls.ScrollSpeedSlider, function(value)
		local adjustedValue : number = MIN_SCROLL_SPEED + (MAX_SCROLL_SPEED * value);
		adjustedValue = math.clamp(adjustedValue, MIN_SCROLL_SPEED, MAX_SCROLL_SPEED);
		Options.SetUserOption("Interface", "ScrollSpeed", adjustedValue);
		Controls.ConfirmButton:SetDisabled(false);
		Controls.ScrollSpeedValue:LocalizeAndSetText("LOC_OPTIONS_SCROLL_SPEED_VALUE", adjustedValue*100);
	end);
	
	local scrollTextSpeed : number = Options.GetUserOption("Interface", "ScrollTextSpeed") or 1.0;
	Controls.ScrollTextSpeedSlider:SetValue((scrollTextSpeed - MIN_SCROLL_TEXT_SPEED) / MAX_SCROLL_TEXT_SPEED);
	Controls.ScrollTextSpeedValue:LocalizeAndSetText("LOC_OPTIONS_SCROLL_TEXT_SPEED_VALUE", scrollTextSpeed*100);
	RegisterSliderCb(Controls.ScrollTextSpeedSlider, function(value)
		local adjustedValue : number = MIN_SCROLL_TEXT_SPEED + (MAX_SCROLL_SPEED * value);
		adjustedValue = math.clamp(adjustedValue, MIN_SCROLL_TEXT_SPEED, MAX_SCROLL_TEXT_SPEED);
		Options.SetUserOption("Interface", "ScrollTextSpeed", adjustedValue);
		Controls.ConfirmButton:SetDisabled(false);
		Controls.ScrollTextSpeedValue:LocalizeAndSetText("LOC_OPTIONS_SCROLL_TEXT_SPEED_VALUE", adjustedValue*100);
	end);

    -- Application
    PopulateComboBox(Controls.ShowIntroPullDown, boolean_options, Options.GetAppOption("Video", "PlayIntroVideo"), function(option)
        Options.SetAppOption("Video", "PlayIntroVideo", option);
		Controls.ConfirmButton:SetDisabled(false);
    end);

	PopulateCheckBox(Controls.WarnAboutModsCheckbox, Options.GetAppOption("UI", "WarnAboutModCompatibility"), function(option)
        Options.SetAppOption("UI", "WarnAboutModCompatibility", option);
		Controls.ConfirmButton:SetDisabled(false);
    end
    );


end

function EnsureBindingVisible(index)
	local numEntries = #m_bindingInstances;
	if numEntries == 0 then return end

	local scrollPanel = Controls.KeyBindingsScrollPanel;
	local stack = Controls.KeyBindingsStack;
	
	local stackHeight = stack:GetSizeY();
	local viewHeight = scrollPanel:GetSizeY();
	
	if stackHeight <= viewHeight then
		scrollPanel:SetScrollValue(0);
		return;
	end

	-- Simple heuristic: assume rows are roughly equal height
	local scrollValue = 0;
	if numEntries > 1 then
		scrollValue = (index - 1) / (numEntries - 1);
	end
	scrollPanel:SetScrollValue(scrollValue);
end

-- ===========================================================================
-- Keyboard navigation
--
-- Two levels: the tab bar (tabs, Confirm, Reset, Back) and the content of the selected tab.
--   Tab level:   Up/Down move, Enter/Right enter the tab, Enter on Confirm/Reset/Back activates, Escape = Back.
--   Content:     Up/Down/Home/End move, Left/Right change the value, Enter opens a pulldown / toggles a checkbox /
--                presses a button, Escape returns to the tab level.
--   Pulldowns:   Enter opens a mod-side list (Up/Down/Home/End "value, i of n", Enter applies, Escape cancels).
--   Key Bindings: Up/Down actions, Left/Right primary/alternate, Enter rebinds, Delete clears, Tab next category.
-- ===========================================================================

local function Txt(x)
	if type(x) == "function" then return x(); end
	return x;
end

local function PercentText(control)
	return tostring(math.floor(control:GetValue() * 100 + 0.5)).." percent";
end

local function LabelText(controlId)
	return function() return Controls[controlId]:GetText(); end
end

local function PulldownDef(id, label, opts) local d = opts or {}; d.id = id; d.kind = "pulldown"; d.label = label; return d; end
local function CheckDef(id, label, opts) local d = opts or {}; d.id = id; d.kind = "checkbox"; d.label = label; return d; end
local function SliderDef(id, label, opts) local d = opts or {}; d.id = id; d.kind = "slider"; d.label = label; return d; end
local function EditDef(id, label, opts) local d = opts or {}; d.id = id; d.kind = "edit"; d.label = label; return d; end
local function ButtonDef(id, label, activate, opts) local d = opts or {}; d.id = id; d.kind = "button"; d.label = label; d.activate = activate; return d; end

-- Marks a Graphics tab control that is only reachable while "Show advanced graphics options" is on.
local function Adv(d) d.parent = "AdvancedOptionsContainer"; return d; end

local function MinText() return Locale.Lookup("LOC_OPTIONS_MINIMUM"); end
local function CustomText() return Locale.Lookup("LOC_OPTIONS_CUSTOM"); end

-- Controls reachable by keyboard on each tab (keyed by the tab's title loc key), in order.
local TAB_ITEMS = {
	["LOC_OPTIONS_GAME_OPTIONS"] = {
		PulldownDef("QuickCombatPullDown",					"LOC_OPTIONS_QUICK_COMBAT"),
		PulldownDef("QuickMovementPullDown",				"LOC_OPTIONS_QUICK_MOVEMENT"),
		PulldownDef("AutoEndTurnPullDown",					"LOC_OPTIONS_AUTO_END_TURN"),
		PulldownDef("CityRangeAttackTurnBlockingPullDown",	"LOC_OPTIONS_CITY_RANGE_ATTACK"),
		PulldownDef("TunerPullDown",						"LOC_OPTIONS_TUNER"),
		PulldownDef("AutoDownloadPullDown",					"LOC_OPTIONS_AUTO_DOWNLOAD_ADDITIONAL_CONTENT"),
		PulldownDef("TutorialPullDown",						"LOC_OPTIONS_TUTORIAL"),
		PulldownDef("SaveFrequencyPullDown",				"LOC_OPTIONS_TURNS_BETWEEN_AUTOSAVES"),
		PulldownDef("SaveKeepPullDown",						"LOC_OPTIONS_AUTOSAVES_TO_KEEP"),
		SliderDef("TODSlider",								"LOC_OPTIONS_TIME_OF_DAY", { steps = 48, text = LabelText("TODText"), min = "12:00 AM", max = "11:59 PM" }),
		CheckDef("TimeOfDayCheckbox",						"LOC_OPTIONS_TIME_OF_DAY_TEXT"),
		EditDef("LANPlayerNameEdit",						"LOC_OPTIONS_LAN_PLAYER_NAME"),
		EditDef("PBCTurnWebhookEdit",						"LOC_OPTIONS_WEBHOOK_URL"),
		PulldownDef("TurnWebhookFreqPullDown",				"LOC_OPTIONS_WEBHOOK_FREQ"),
	},
	["LOC_OPTIONS_GRAPHICS_OPTIONS"] = {
		PulldownDef("AdapterPullDown",						"LOC_OPTIONS_VIDEO_ADAPTER_TEXT"),
		CheckDef("MultiGPUCheckbox",						"LOC_OPTIONS_VIDEO_MULTI_GPU_TEXT"),
		PulldownDef("ResolutionPullDown",					"LOC_OPTIONS_VIDEO_RESOLUTION_TEXT"),
		PulldownDef("UIScalePulldown",						"LOC_OPTIONS_VIDEO_UI_UPSCALE_TEXT"),
		PulldownDef("FullScreenPullDown",					"LOC_OPTIONS_VIDEO_WINDOW_MODE_TEXT"),
		PulldownDef("MSAAPullDown",							"LOC_OPTIONS_VIDEO_MSAA_TEXT"),
		SliderDef("PerformanceSlider",						"LOC_OPTIONS_VIDEO_PERFORMANCE_TEXT", { stepApi = true, text = LabelText("PerformanceValue"), min = MinText, max = CustomText }),
		SliderDef("MemorySlider",							"LOC_OPTIONS_VIDEO_MEMORY_TEXT", { stepApi = true, text = LabelText("MemoryValue"), min = MinText, max = CustomText }),
		ButtonDef("AdvancedGraphicsOptions",				function() if Controls.AdvancedOptionsContainer:IsHidden() then return "LOC_OPTIONS_SHOW_ADVANCED_GRAPHICS"; end return "LOC_OPTIONS_HIDE_ADVANCED_GRAPHICS"; end, function() OnToggleAdvancedOptions(); end),
		Adv(CheckDef("VSyncEnabledCheckbox",				"LOC_OPTIONS_VIDEO_VSYNC_ENABLED_TEXT")),
		Adv(PulldownDef("TickIntervalPullDown",				"LOC_OPTIONS_PERFORMANCE_TICK_INTERVAL_TEXT")),
		Adv(CheckDef("AssetTextureResolutionCheckbox",		"LOC_OPTIONS_VIDEO_HIGH_RESOLUTION_ASSET_TEXTURES_TEXT")),
		Adv(PulldownDef("VFXDetailLevelPullDown",			"LOC_OPTIONS_VIDEO_VFX_DETAIL_LEVEL_TEXT")),
		Adv(CheckDef("LightingBloomEnabledCheckbox",		"LOC_OPTIONS_LIGHTING_BLOOM_ENABLED_TEXT")),
		Adv(CheckDef("LightingDynamicLightingEnabledCheckbox","LOC_OPTIONS_LIGHTING_DYNAMIC_LIGHTING_ENABLED_TEXT")),
		Adv(CheckDef("ShadowsEnabledCheckbox",				"LOC_OPTIONS_SHADOWS_ENABLED_TEXT")),
		Adv(PulldownDef("ShadowsResolutionPullDown",		"LOC_OPTIONS_SHADOWS_RESOLUTION_TEXT")),
		Adv(CheckDef("CloudShadowsEnabledCheckbox",			"LOC_OPTIONS_CLOUD_SHADOWS_ENABLED_TEXT")),
		Adv(CheckDef("SSOverlayEnabledCheckbox",			"LOC_OPTIONS_SSOVERLAY_ENABLED_TEXT")),
		Adv(PulldownDef("TerrainQualityPullDown",			"LOC_OPTIONS_TERRAIN_QUALITY_TEXT")),
		Adv(CheckDef("TerrainSynthesisCheckbox",			"LOC_OPTIONS_TERRAIN_HIGH_RESOLUTION_TEXT")),
		Adv(CheckDef("TerrainTextureResolutionCheckbox",	"LOC_OPTIONS_TERRAIN_HIGH_RESOLUTION_TEXTURES_TEXT")),
		Adv(CheckDef("TerrainShaderCheckbox",				"LOC_OPTIONS_TERRAIN_HIGH_QUALITY_SHADER_TEXT")),
		Adv(CheckDef("TerrainAOEnabledCheckbox",			"LOC_OPTIONS_LIGHTING_AO_ENABLED_TEXT")),
		Adv(PulldownDef("TerrainAOResolutionPullDown",		"LOC_OPTIONS_LIGHTING_AO_RENDER_RESOLUTION_TEXT")),
		Adv(CheckDef("TerrainClutterCheckbox",				"LOC_OPTIONS_TERRAIN_HIGH_DETAIL_CLUTTER_TEXT")),
		Adv(CheckDef("WaterResolutionCheckbox",				"LOC_OPTIONS_WATER_HIGH_RESOLUTION_TEXT")),
		Adv(CheckDef("WaterShaderCheckbox",					"LOC_OPTIONS_WATER_HIGH_QUALITY_SHADER_TEXT")),
		Adv(PulldownDef("ReflectionPassesPullDown",			"LOC_OPTIONS_REFLECTION_PASSES_TEXT")),
		Adv(PulldownDef("LeaderQualityPullDown",			"LOC_OPTIONS_LEADER_QUALITY_TEXT")),
		Adv(CheckDef("MotionBlurEnabledCheckbox",			"LOC_OPTIONS_LEADER_MOTIONBLUR_TEXT")),
	},
	["LOC_OPTIONS_AUDIO_OPTIONS"] = {
		SliderDef("MasterVolSlider",	"LOC_OPTIONS_MASTER_VOLUME",	{ steps = 20, text = PercentText, min = "0 percent", max = "100 percent" }),
		SliderDef("MusicVolSlider",		"LOC_OPTIONS_MUSIC_VOLUME",		{ steps = 20, text = PercentText, min = "0 percent", max = "100 percent" }),
		SliderDef("SFXVolSlider",		"LOC_OPTIONS_EFFECTS_VOLUME",	{ steps = 20, text = PercentText, min = "0 percent", max = "100 percent" }),
		SliderDef("AmbVolSlider",		"LOC_OPTIONS_AMBIENT_VOLUME",	{ steps = 20, text = PercentText, min = "0 percent", max = "100 percent" }),
		SliderDef("SpeechVolSlider",	"LOC_OPTIONS_SPEECH_VOLUME",	{ steps = 20, text = PercentText, min = "0 percent", max = "100 percent" }),
		CheckDef("MuteFocusCheckbox",	"LOC_OPTIONS_MUTE_FOCUS"),
	},
	["LOC_OPTIONS_INTERFACE_OPTIONS"] = {
		PulldownDef("ClockFormat",						"LOC_OPTIONS_INTERFACE_CLOCK_FORMAT"),
		PulldownDef("StartInStrategicView",				"LOC_OPTIONS_STRATEGIC_VIEW_START"),
		PulldownDef("MouseGrabPullDown",				"LOC_OPTIONS_INTERFACE_GRAB_MOUSE"),
		PulldownDef("EdgeScrollPullDown",				"LOC_OPTIONS_INTERFACE_EDGE_SCROLL"),
		PulldownDef("AutoProdQueuePullDown",			"LOC_OPTIONS_INTERFACE_OPEN_TO_PROD_QUEUE"),
		PulldownDef("ReplaceDragWithClickPullDown",		"LOC_OPTIONS_INTERFACE_FORCE_CLICK_TO_DRAG"),
		PulldownDef("UnitCyclingPullDown",				"LOC_OPTIONS_AUTO_UNIT_CYCLING"),
		PulldownDef("RibbonStatsPullDown",				"LOC_OPTIONS_RIBBON_STATS_LABEL"),
		SliderDef("ChatTextSizeSlider",					"LOC_OPTIONS_CHAT_TEXT_SIZE", { steps = 3, text = LabelText("ChatTextValue"), min = tostring(MIN_CHAT_TEXT_SIZE), max = tostring(MAX_CHAT_TEXT_SIZE) }),
		SliderDef("MinimapSizeSlider",					"LOC_OPTIONS_INTERFACE_MINIMAP_SIZE", { steps = 20, text = PercentText, min = "0 percent", max = "100 percent" }),
		SliderDef("PlotToolTipDelaySlider",				"LOC_OPTIONS_PLOT_TOOLTIP_DELAY", { steps = 10, text = LabelText("PlotToolTipDelayValue"), min = "0 seconds", max = "2 seconds" }),
		SliderDef("ScrollSpeedSlider",					"LOC_OPTIONS_SCROLL_SPEED", { steps = 20, text = LabelText("ScrollSpeedValue"), min = "0", max = "100" }),
		SliderDef("ScrollTextSpeedSlider",				"LOC_OPTIONS_SCROLL_TEXT_SPEED", { steps = 20, text = LabelText("ScrollTextSpeedValue"), min = "0", max = "100" }),
		CheckDef("TouchInputCheckbox",					"LOC_OPTIONS_TOUCH_ENABLED"),
		CheckDef("HistoricMomentsAnimCheckbox",			"LOC_OPTIONS_HISTORIC_MOMENT_ANIMATION", { parent = "HistoricMomentsAnimStack" }),
		PulldownDef("PlayByCloudEndTurnBehavior",		"LOC_OPTIONS_INTERFACE_PLAYBYCLOUD_END_TURN_BEHAVIOR"),
		PulldownDef("PlayByCloudClientReadyBehavior",	"LOC_OPTIONS_INTERFACE_PLAYBYCLOUD_READY_BEHAVIOR"),
		PulldownDef("ColorblindAdaptation",				"LOC_OPTIONS_INTERFACE_COLOR_BLINDNESS_ADAPTATION"),
		PulldownDef("RGBControl",						"LOC_OPTIONS_INTERFACE_LIGHTING"),
		ButtonDef("SwitchUILayout",						"LOC_OPTIONS_SWITCH_UI_LAYOUT", function() OnSwitchUILayout(); end),
	},
	["LOC_OPTIONS_APPLICATION_OPTIONS"] = {
		PulldownDef("ShowIntroPullDown",				"LOC_OPTIONS_APP_SHOW_MOVIE"),
		CheckDef("WarnAboutModsCheckbox",				"LOC_OPTIONS_APP_WARN_MOD_COMPATIBILITY"),
	},
	["LOC_OPTIONS_LANGUAGE_OPTIONS"] = {
		PulldownDef("DisplayLanguagePullDown",			"LOC_OPTIONS_DISPLAY_LANGUAGE"),
		PulldownDef("SpokenLanguagePullDown",			"LOC_OPTIONS_SPOKEN_LANGUAGE"),
		CheckDef("EnableSubtitlesCheckbox",				"LOC_OPTIONS_SUBTITLES"),
	},
};

-- Section headers of the advanced graphics controls, so that e.g. the two "Quality" pulldowns can be told apart.
do
	local sections = {
		LOC_OPTIONS_LIGHTING = { "LightingBloomEnabledCheckbox", "LightingDynamicLightingEnabledCheckbox" },
		LOC_OPTIONS_SHADOWS = { "ShadowsEnabledCheckbox", "ShadowsResolutionPullDown", "CloudShadowsEnabledCheckbox" },
		LOC_OPTIONS_OVERLAY = { "SSOverlayEnabledCheckbox" },
		LOC_OPTIONS_TERRAIN = { "TerrainQualityPullDown", "TerrainSynthesisCheckbox", "TerrainTextureResolutionCheckbox", "TerrainShaderCheckbox", "TerrainAOEnabledCheckbox", "TerrainAOResolutionPullDown", "TerrainClutterCheckbox" },
		LOC_OPTIONS_WATER = { "WaterResolutionCheckbox", "WaterShaderCheckbox" },
		LOC_OPTIONS_REFLECTIONS = { "ReflectionPassesPullDown" },
		LOC_OPTIONS_LEADERS = { "LeaderQualityPullDown", "MotionBlurEnabledCheckbox" },
	};
	for section, ids in pairs(sections) do
		for _, id in ipairs(ids) do
			for _, def in ipairs(TAB_ITEMS["LOC_OPTIONS_GRAPHICS_OPTIONS"]) do
				if def.id == id then def.section = section; end
			end
		end
	end
end

function IsGameTab(tab)
	return tab ~= nil and tab[2] == Controls.GameOptions;
end

function IsKeyBindingsTab(tab)
	return tab ~= nil and tab[2] == Controls.KeyBindings;
end

local function TabName(tab)
	return Locale.Lookup(tab[3]);
end

local function ItemLabel(def)
	local label = (string.gsub(Locale.Lookup(Txt(def.label)), ":%s*$", ""));
	if def.section ~= nil then
		label = (string.gsub(Locale.Lookup(def.section), ":%s*$", ""))..", "..label;
	end
	return label;
end

-- IsHidden() only looks at the control's own flag; IsVisible() also checks its ancestors (e.g. the hidden container around Switch UI Layout).
local function IsControlShown(control)
	local ok, visible = pcall(function() return control:IsVisible(); end);
	if ok then return visible; end
	return not control:IsHidden();
end

-- Rebuilt at key time: some controls are hidden depending on platform/state, or live in a collapsed section.
function GetTabItems(tab)
	local items = {};
	local defs = (tab ~= nil) and TAB_ITEMS[tab[3]] or nil;
	if defs == nil then return items; end
	for _, def in ipairs(defs) do
		local control = Controls[def.id];
		local visible = control ~= nil and IsControlShown(control);
		if visible and def.parent ~= nil then
			local parent = Controls[def.parent];
			if parent ~= nil and parent:IsHidden() then visible = false; end
		end
		if visible then
			table.insert(items, { def = def, id = def.id, kind = def.kind, control = control, label = ItemLabel(def) });
		end
	end
	return items;
end

local function ItemValueText(item)
	local control = item.control;
	local text = "";
	if item.kind == "pulldown" then
		local state = m_comboState[control];
		if state ~= nil and state.matched ~= false and state.values[state.index] ~= nil and not control:IsDisabled() then
			text = Locale.Lookup(state.values[state.index][1]);
		else
			text = control:GetButton():GetText();
		end
	elseif item.kind == "checkbox" then
		text = control:IsSelected() and "checked" or "unchecked";
	elseif item.kind == "slider" then
		text = item.def.text and Txt(item.def.text(control)) or tostring(control:GetValue());
	end
	if item.kind == "edit" then
		text = control:GetText();
		if text == nil or text == "" then text = "blank"; end
	end
	if item.kind ~= "button" and control:IsDisabled() then
		text = text..", disabled";
	end
	return text;
end

-- full: include the control type and a hint (on focus); otherwise just "label: value" (after a change)
function DescribeItem(item, full)
	if item.kind == "button" then
		return item.label..", button";
	end
	local value = ItemValueText(item);
	if not full then
		return item.label..": "..value;
	end
	local disabled = item.control:IsDisabled();
	if item.kind == "edit" then
		return item.label..", edit, "..value..(disabled and "" or ", Enter to edit");
	elseif item.kind == "pulldown" then
		return item.label..", dropdown: "..value..(disabled and "" or ". Enter to choose, Left or Right to change");
	elseif item.kind == "checkbox" then
		return item.label..", checkbox: "..value..(disabled and "" or ". Enter or Space to toggle");
	else
		return item.label..", slider: "..value..", minimum "..Txt(item.def.min)..", maximum "..Txt(item.def.max)..(disabled and "" or ". Left or Right to adjust");
	end
end

local function ParkMouse()
	-- Never leave the mouse resting on a slider: the engine gives the slider all arrow input.
	KeyNavMoveMouse(Controls.WindowTitle);
end

local function ScrollItemIntoView(item)
	if m_currentTab ~= nil and m_currentTab[2] == Controls.GraphicsOptions then
		KeyNavScrollIntoView(Controls.GraphicsOptionsPanel, Controls.GraphicsOptionsStack, item.control);
	end
end

function FocusItem(item, full)
	m_contentFocus = item.id;
	for i, it in ipairs(GetTabItems(m_currentTab)) do
		if it.id == item.id then m_contentFocusIndex = i; end
	end
	OutputMessageToScreenReader(DescribeItem(item, full));
	if item.kind == "slider" then
		ParkMouse();
	else
		ScrollItemIntoView(item);
		KeyNavMoveMouse(item.control);
	end
end

local function SetComboIndex(control, state, index)
	state.index = index;
	state.matched = true;
	local option = state.values[index];
	control:GetButton():LocalizeAndSetText(option[1]);
	if state.handler then state.handler(option[2]); end
end

local function AdjustSlider(item, dir)
	local control = item.control;
	if control:IsDisabled() then return; end
	if item.def.stepApi then
		local n = control:GetNumSteps();
		local s = math.max(0, math.min(n, control:GetStep() + dir));
		control:SetStepAndCall(s);
	else
		local n = item.def.steps;
		local idx = math.max(0, math.min(n, math.floor(control:GetValue() * n + 0.5) + dir));
		local value = idx / n;
		control:SetValue(value);
		local cb = m_sliderCallbacks[control];
		if cb ~= nil then cb(value); end
	end
end

-- ---------------------------------------------------------------------------
-- Selection mode (Enter on a pulldown)
-- ---------------------------------------------------------------------------
local function SelectionText()
	local state = m_selection.state;
	return Locale.Lookup(state.values[m_selection.index][1])..", "..tostring(m_selection.index).." of "..tostring(#state.values);
end

local function OpenSelection(item)
	local state = m_comboState[item.control];
	if state == nil or #state.values == 0 or item.control:IsDisabled() then
		OutputMessageToScreenReader(DescribeItem(item, false));
		return;
	end
	m_selection = { item = item, state = state, index = state.index, originalIndex = state.index };
	OutputMessageToScreenReader(item.label..", "..SelectionText()..". Up/Down to choose, Enter to select, Escape to cancel");
end

local function HandleSelectionKey(key)
	local sel = m_selection;
	local count = #sel.state.values;
	if key == Keys.VK_UP then
		sel.index = sel.index - 1; if sel.index < 1 then sel.index = count; end
		OutputMessageToScreenReader(SelectionText());
	elseif key == Keys.VK_DOWN then
		sel.index = sel.index + 1; if sel.index > count then sel.index = 1; end
		OutputMessageToScreenReader(SelectionText());
	elseif key == Keys.VK_HOME then
		sel.index = 1; OutputMessageToScreenReader(SelectionText());
	elseif key == Keys.VK_END then
		sel.index = count; OutputMessageToScreenReader(SelectionText());
	elseif key == Keys.VK_RETURN then
		m_selection = nil;
		if sel.index ~= sel.originalIndex then
			SetComboIndex(sel.item.control, sel.state, sel.index);
		end
		OutputMessageToScreenReader(DescribeItem(sel.item, false));
	elseif key == Keys.VK_ESCAPE then
		m_selection = nil;
		OutputMessageToScreenReader("Cancelled, "..DescribeItem(sel.item, false));
	end
	return true;
end

-- ---------------------------------------------------------------------------
-- Tab level: tabs, Confirm, Reset, Back
-- ---------------------------------------------------------------------------
local function GetMainElements()
	local els = {};
	for i, tab in ipairs(m_tabs) do
		table.insert(els, { key = "tab:"..tostring(i), kind = "tab", tab = tab, index = i, control = tab[1] });
	end
	table.insert(els, { key = "confirm", kind = "confirm", control = Controls.ConfirmButton, label = Locale.Lookup("LOC_GENERIC_CONFIRM_BUTTON") });
	if not Controls.ResetButton:IsHidden() then
		table.insert(els, { key = "reset", kind = "reset", control = Controls.ResetButton, label = Locale.Lookup("LOC_SETUP_RESTORE_DEFAULT") });
	end
	table.insert(els, { key = "back", kind = "back", control = Controls.WindowCloseButton, label = Locale.Lookup("LOC_MULTIPLAYER_BACK") });
	return els;
end

local function DescribeMainElement(el)
	if el.kind == "tab" then
		return TabName(el.tab)..", tab "..tostring(el.index).." of "..tostring(#m_tabs);
	end
	local text = el.label..", button";
	if el.control:IsDisabled() then
		text = text..", disabled";
		if el.kind == "confirm" then text = text..", no changes to apply"; end
	end
	return text;
end

function FocusMainElement(el, silent)
	m_mainFocusKey = el.key;
	if el.kind == "tab" then
		OnSelectTab(el.tab);
	end
	if not silent then
		OutputMessageToScreenReader(DescribeMainElement(el));
	end
	KeyNavMoveMouse(el.control);
end

-- Moves from the tab bar into the tab's content.
function EnterTabContent(tab)
	OnSelectTab(tab);
	for i, t in ipairs(m_tabs) do
		if t == tab then m_mainFocusKey = "tab:"..tostring(i); end
	end
	if IsKeyBindingsTab(tab) then
		m_inMainKeyNav = false;
		m_selectedBindingIndex = 1;
		m_selectedBindingColumn = 1;
		m_lastBindingCategory = nil;
		local count = #m_bindingInfo;
		if count == 0 then
			OutputMessageToScreenReader(TabName(tab)..", no key bindings");
			return;
		end
		OutputMessageToScreenReader(TabName(tab)..", "..tostring(count).." actions. Up and Down to move, Left and Right for primary or alternate, Enter to rebind, Delete to clear, Tab for next category. "..DescribeBinding(true));
		ParkMouse();
		return;
	end
	local items = GetTabItems(tab);
	if #items == 0 then
		m_inMainKeyNav = true;
		OutputMessageToScreenReader(TabName(tab)..", no options");
		return;
	end
	m_inMainKeyNav = false;
	m_contentFocus = items[1].id;
	m_contentFocusIndex = 1;
	local first = items[1];
	OutputMessageToScreenReader(TabName(tab)..", "..tostring(#items).." options. "..DescribeItem(first, true));
	if first.kind == "slider" then ParkMouse(); else KeyNavMoveMouse(first.control); end
end

function LeaveTabContent()
	m_inMainKeyNav = true;
	m_selection = nil;
	local els = GetMainElements();
	for _, el in ipairs(els) do
		if el.key == m_mainFocusKey then
			FocusMainElement(el);
			return;
		end
	end
	FocusMainElement(els[1]);
end

function CancelOptions()
	if m_resetDirty or not Controls.ConfirmButton:IsDisabled() then
		OutputMessageToScreenReader("Changes discarded");
	end
	OnCancel();
end

local function HandleMainKey(key)
	local els = GetMainElements();
	local count = #els;
	local focused = 1;
	for i, el in ipairs(els) do
		if el.key == m_mainFocusKey then focused = i; end
	end
	local el = els[focused];

	if key == Keys.VK_UP then
		FocusMainElement(els[(focused - 2 + count) % count + 1]);
		return true;
	elseif key == Keys.VK_DOWN then
		FocusMainElement(els[focused % count + 1]);
		return true;
	elseif key == Keys.VK_HOME then
		FocusMainElement(els[1]);
		return true;
	elseif key == Keys.VK_END then
		FocusMainElement(els[count]);
		return true;
	elseif key == Keys.VK_RETURN or key == Keys.VK_SPACE or key == Keys.VK_RIGHT then
		if el.kind == "tab" then
			EnterTabContent(el.tab);
			return true;
		elseif key == Keys.VK_RIGHT then
			return true;
		elseif el.kind == "confirm" then
			if el.control:IsDisabled() then
				OutputMessageToScreenReader(DescribeMainElement(el));
			else
				OnConfirm();
			end
			return true;
		elseif el.kind == "reset" then
			if el.control:IsDisabled() then
				OutputMessageToScreenReader(DescribeMainElement(el));
			else
				OnReset();
			end
			return true;
		elseif el.kind == "back" then
			CancelOptions();
			return true;
		end
	end
	return false;
end

-- ---------------------------------------------------------------------------
-- Tab content
-- ---------------------------------------------------------------------------
local function HandleContentKey(key)
	if key == Keys.VK_ESCAPE then
		LeaveTabContent();
		return true;
	end

	local items = GetTabItems(m_currentTab);
	local count = #items;
	if count == 0 then return false; end

	local focused = nil;
	for i, item in ipairs(items) do
		if item.id == m_contentFocus then focused = i; end
	end
	if focused == nil then
		-- the focused item vanished (e.g. Advanced Options collapsed by mouse): clamp to the nearest and announce it
		FocusItem(items[math.max(1, math.min(count, m_contentFocusIndex))], true);
		return true;
	end
	local item = items[focused];
	local control = item.control;

	if key == Keys.VK_UP then
		FocusItem(items[(focused - 2 + count) % count + 1], true);
		return true;
	elseif key == Keys.VK_DOWN then
		FocusItem(items[focused % count + 1], true);
		return true;
	elseif key == Keys.VK_HOME then
		FocusItem(items[1], true);
		return true;
	elseif key == Keys.VK_END then
		FocusItem(items[count], true);
		return true;
	elseif key == Keys.VK_LEFT or key == Keys.VK_RIGHT then
		local dir = (key == Keys.VK_RIGHT) and 1 or -1;
		if item.kind == "pulldown" then
			local state = m_comboState[control];
			if state ~= nil and not control:IsDisabled() then
				local numValues = #state.values;
				if numValues > 0 then
					local newIndex;
					if state.matched == false then
						newIndex = (dir > 0) and 1 or numValues;	-- current value isn't in the list: start from an end
					else
						newIndex = (state.index - 1 + dir + numValues) % numValues + 1;
					end
					SetComboIndex(control, state, newIndex);
				end
			end
			OutputMessageToScreenReader(DescribeItem(item, false));
		elseif item.kind == "slider" then
			AdjustSlider(item, dir);
			OutputMessageToScreenReader(ItemValueText(item));
		else
			return false;
		end
		return true;
	elseif key == Keys.VK_RETURN or key == Keys.VK_SPACE then
		if item.kind == "pulldown" then
			if key == Keys.VK_RETURN then OpenSelection(item); end
		elseif item.kind == "checkbox" then
			local handler = m_checkState[control];
			if handler ~= nil and not control:IsDisabled() then
				local selected = not control:IsSelected();
				control:SetSelected(selected);
				handler(selected);
			end
			OutputMessageToScreenReader(DescribeItem(item, false));
		elseif item.kind == "edit" then
			if key == Keys.VK_RETURN then
				KeyNavEditBox_Begin(control, {
					label = item.label, commit = m_editCommit[control],
				});
			end
		elseif item.kind == "button" then
			if key == Keys.VK_RETURN and item.def.activate ~= nil then
				item.def.activate();
				for _, it in ipairs(GetTabItems(m_currentTab)) do
					if it.id == item.id then
						m_contentFocus = it.id;
						OutputMessageToScreenReader(DescribeItem(it, true));
					end
				end
			end
		end
		return true;
	end
	return false;
end

-- ---------------------------------------------------------------------------
-- Key bindings tab
-- ---------------------------------------------------------------------------
function DescribeBinding(forceCategory)
	local info = m_bindingInfo[m_selectedBindingIndex];
	if info == nil then return ""; end
	local text = "";
	if forceCategory or info.category ~= m_lastBindingCategory then
		text = info.category..". ";
	end
	m_lastBindingCategory = info.category;
	local gesture = (m_selectedBindingColumn == 1) and info.g1 or info.g2;
	text = text..info.name..", "..((m_selectedBindingColumn == 1) and "primary" or "alternate").." binding: "..(gesture or "none");
	return text;
end

local function FocusBinding()
	OutputMessageToScreenReader(DescribeBinding(false));
	local entry = m_bindingInstances[m_selectedBindingIndex];
	if entry ~= nil then
		KeyNavScrollIntoView(Controls.KeyBindingsScrollPanel, Controls.KeyBindingsStack, entry.Binding);
	end
end

local function HandleBindingsKey(key)
	local count = #m_bindingInfo;
	if key == Keys.VK_ESCAPE then
		LeaveTabContent();
		return true;
	end
	if count == 0 then return false; end

	if key == Keys.VK_UP then
		m_selectedBindingIndex = (m_selectedBindingIndex - 2 + count) % count + 1;
	elseif key == Keys.VK_DOWN then
		m_selectedBindingIndex = m_selectedBindingIndex % count + 1;
	elseif key == Keys.VK_HOME then
		m_selectedBindingIndex = 1;
	elseif key == Keys.VK_END then
		m_selectedBindingIndex = count;
	elseif key == Keys.VK_TAB then
		-- next category
		local current = m_bindingInfo[m_selectedBindingIndex].category;
		local target = nil;
		for offset = 1, count do
			local i = (m_selectedBindingIndex - 1 + offset) % count + 1;
			if m_bindingInfo[i].category ~= current then target = i; break; end
		end
		if target == nil then target = 1; end
		m_selectedBindingIndex = target;
	elseif key == Keys.VK_LEFT then
		if m_selectedBindingColumn == 1 then OutputMessageToScreenReader("Already on primary binding"); return true; end
		m_selectedBindingColumn = 1;
	elseif key == Keys.VK_RIGHT then
		if m_selectedBindingColumn == 2 then OutputMessageToScreenReader("Already on alternate binding"); return true; end
		m_selectedBindingColumn = 2;
	elseif key == Keys.VK_RETURN or key == Keys.VK_SPACE then
		local info = m_bindingInfo[m_selectedBindingIndex];
		StartActiveKeyBinding(info.actionId, m_selectedBindingColumn - 1);
		OutputMessageToScreenReader("Press the new key for "..info.name..", "..((m_selectedBindingColumn == 1) and "primary" or "alternate").." binding. Escape to cancel");
		return true;
	elseif Keys.VK_DELETE ~= nil and key == Keys.VK_DELETE then
		local info = m_bindingInfo[m_selectedBindingIndex];
		Controls.ConfirmButton:SetDisabled(false);
		Input.ClearGesture(info.actionId, m_selectedBindingColumn - 1);
		RefreshKeyBinding();
		OutputMessageToScreenReader(info.name..", "..((m_selectedBindingColumn == 1) and "primary" or "alternate").." binding cleared");
		return true;
	else
		return false;
	end
	FocusBinding();
	return true;
end

function HandleOptionsKey(key)
	if m_selection ~= nil then
		return HandleSelectionKey(key);
	end
	if m_inMainKeyNav then
		return HandleMainKey(key);
	end
	if IsKeyBindingsTab(m_currentTab) then
		return HandleBindingsKey(key);
	end
	return HandleContentKey(key);
end

----------------------------------------------------------------
-- Input handling
----------------------------------------------------------------
local function PopupKey(key)
	if key == Keys.VK_ESCAPE then
		-- Escape answers the last button when there is a choice (No / Cancel); a lone OK is left to Enter.
		local els = _kPopupDialog.KeyNavElements;
		if els ~= nil and #els >= 2 then
			els[#els].Callback();
		end
		return true;
	end
	_kPopupDialog:KeyHandler(key);
	return true;
end

function OnOptionsUpdate( deltaTime:number )
	KeyNavEditBox_Update(deltaTime);
	m_secondsSinceKey = m_secondsSinceKey + deltaTime;
end

function InputHandler( pInputStruct )
	local editHandled = KeyNavEditBox_HandleInput(pInputStruct);
	if editHandled ~= nil then return editHandled; end
	local uiMsg = pInputStruct:GetMessageType();
	if(uiMsg == KeyEvents.KeyDown) then
		-- remember the key pressed during a binding capture: if the engine completes the capture on KeyDown,
		-- its KeyUp reaches us with the popup already hidden and must not act as navigation
		if not Controls.KeyBindingPopup:IsHidden() then m_captureKeyDown = pInputStruct:GetKey(); end
		return false;
	end
	if(uiMsg == KeyEvents.KeyUp) then
		local uiKey = pInputStruct:GetKey();
		local result = false;
		m_secondsSinceKey = 0;
		local ok, err = xpcall(function()
			-- Handle escape being pressed to cancel active key binding.
			if m_swallowKeyUp ~= nil then
				local swallow = (m_swallowKeyUp == uiKey);
				m_swallowKeyUp = nil;
				if swallow then result = true; return; end
			end
			if not Controls.KeyBindingPopup:IsHidden() then
				m_captureKeyDown = nil;	-- a capture completing on KeyUp leaves no KeyUp behind
				if uiKey == Keys.VK_ESCAPE then
					StopActiveKeyBinding();
					OutputMessageToScreenReader("Cancelled, "..DescribeBinding(false));
					result = true;
				end
				-- any other key must reach the engine, which records it as the new binding
				return;
			end

			if _kPopupDialog ~= nil and _kPopupDialog:IsOpen() then
				result = PopupKey(uiKey);
				return;
			end

			if HandleOptionsKey(uiKey) then
				result = true;
				return;
			end

			-- if we're here, we're not in control bindings mode
			if(uiKey == Keys.VK_ESCAPE) then
				CancelOptions();
				result = true;
			end
		end, KeyNavErrorHandler);
		if not ok then print("Options input error: "..tostring(err)); end
		return result;
	end

	return false;
end

-------------------------------------------------------------------------------
-- 
-------------------------------------------------------------------------------
function InitializeKeyBinding()
		
	-- Key binding infrastructure.
	function RefreshKeyBinding()
		local ActionIdIndex = 1;
		local ActionNameIndex = 2;
		local ActionCategoryIndex = 3;
		local Gesture1Index = 4;
		local Gesture2Index = 5;

		local actions = {};
		local count = Input.GetActionCount();
		for i = 0, count - 1, 1 do
			local action = Input.GetActionId(i);
			if(Input.ShouldShowActionKeybinding(action)) then
				local info = {
					action,
					Locale.Lookup(Input.GetActionName(action)),
					Locale.Lookup(Input.GetActionCategory(action)),
					Input.GetGestureDisplayString(action, 0) or false,
					Input.GetGestureDisplayString(action, 1) or false
				};
				table.insert(actions, info);
			end
		end
	
		table.sort(actions, function(a, b)
			local result = Locale.Compare(a[ActionCategoryIndex], b[ActionCategoryIndex]);
			if(result == 0) then
				return Locale.Compare(a[ActionNameIndex], b[ActionNameIndex]) == -1;
			else
				return result == -1;
			end	
		end);


		_KeyBindingCategories:ResetInstances();
		_KeyBindingActions:ResetInstances();
		m_bindingInstances = {};
		m_bindingInfo = {};

		local currentCategory;
		for i, action in ipairs(actions) do
			if(currentCategory ~= action[ActionCategoryIndex]) then
				currentCategory = action[ActionCategoryIndex];
				local category = _KeyBindingCategories:GetInstance();
				category.CategoryName:SetText(currentCategory);
			end

			local entry = _KeyBindingActions:GetInstance();
			table.insert(m_bindingInstances, entry);
			table.insert(m_bindingInfo, { actionId = action[ActionIdIndex], name = action[ActionNameIndex], category = (string.gsub(action[ActionCategoryIndex], ":%s*$", "")), g1 = action[Gesture1Index], g2 = action[Gesture2Index] });

			local actionId = action[ActionIdIndex];
			local binding = entry.Binding;
			entry.ActionName:SetText(action[ActionNameIndex]);
			binding:SetText(action[Gesture1Index] or "");
			binding:SetToolTipString(Locale.Lookup(Input.GetActionDescription(action[ActionIdIndex])) or "");
			binding:RegisterCallback(Mouse.eLClick, function()
				StartActiveKeyBinding(actionId, 0);
			end);
		
			local altBinding = entry.AltBinding;
			altBinding:SetText(action[Gesture2Index] or "");
			altBinding:SetToolTipString(Locale.Lookup(Input.GetActionDescription(action[ActionIdIndex])) or "");
			altBinding:RegisterCallback(Mouse.eLClick, function()
				StartActiveKeyBinding(actionId, 1);
			end);

		end

		Controls.KeyBindingsStack:CalculateSize();
		Controls.KeyBindingsScrollPanel:CalculateSize();
	end

	function StartActiveKeyBinding(actionId, index)
        Controls.BindingTitle:SetText(Locale.Lookup(Input.GetActionName(actionId)));
		Controls.KeyBindingPopup:SetHide(false);
		Controls.KeyBindingAlpha:SetToBeginning();
		Controls.KeyBindingAlpha:Play();
		Controls.KeyBindingSlide:SetToBeginning();
		Controls.KeyBindingSlide:Play();
		_CurrentAction = actionId;
		_CurrentActionIndex = index;
		Input.BeginRecordingGestures(true);
	end

	function StopActiveKeyBinding()
		_CurrentAction = nil
		_CurrentActionIndex = nil;
				
		Input.StopRecordingGestures();
		Input.ClearRecordedGestures();
		Controls.KeyBindingPopup:SetHide(true);
	end

	function BindRecordedGesture(gesture)
		local recordedAction = _CurrentAction;
		if(_CurrentAction and _CurrentActionIndex) then
			Controls.ConfirmButton:SetDisabled(false);
			Input.BindAction(_CurrentAction, _CurrentActionIndex, gesture);
			RefreshKeyBinding();
			m_swallowKeyUp = m_captureKeyDown;
			local info = nil;
			for _, bi in ipairs(m_bindingInfo) do
				if bi.actionId == recordedAction then info = bi; break; end
			end
			if info ~= nil then
				local bound = (_CurrentActionIndex == 0) and info.g1 or info.g2;
				OutputMessageToScreenReader(info.name.." bound to "..tostring(bound or "none")..", "..((_CurrentActionIndex == 0) and "primary" or "alternate").." binding");
			end
		end

		StopActiveKeyBinding();
	end
	Events.InputGestureRecorded.Add(BindRecordedGesture);

	Controls.CancelBindingButton:RegisterCallback(Mouse.eLClick, function()
		StopActiveKeyBinding();
	end);

	Controls.ClearBindingButton:RegisterCallback(Mouse.eLClick, function()
		local currentAction = _CurrentAction;
		local currentActionIndex = _CurrentActionIndex;

		StopActiveKeyBinding();	

		if(currentAction and currentActionIndex) then
            Controls.ConfirmButton:SetDisabled(false);
			Input.ClearGesture(currentAction, currentActionIndex);
			RefreshKeyBinding();
		end		
	end);

	-- Initialize buttons and categories
	RefreshKeyBinding();
	Controls.KeyBindingsScrollPanel:SetScrollValue(0);
end

-------------------------------------------------------------------------------
function OnShow()
	KeyNavEditBox_Cancel();
	RefreshKeyBinding();
	UserConfiguration.SaveCheckpoint();
    PopulateGraphicsOptions();
    TemporaryHardCodedGoodness();

	-- Disable confirm button until user changes any option
	Controls.ConfirmButton:SetDisabled(true);
	m_resetDirty = false;
	m_swallowKeyUp = nil;
	m_captureKeyDown = nil;

	if IsInGame() and GameConfiguration.IsAnyMultiplayer() then
		m_pendingGameConfigChanges = {};
		g_BroadcastNetworkConfigOnSave = false;
		BuildGameSetup(Options_UI_CreateParameter);
		Controls.GameSetupContainer:SetHide(false);
	else
		Controls.GameSetupContainer:SetHide(true);
	end

	-- Always open on the first tab with focus on it
	OnSelectTab(m_tabs[1]);
	m_inMainKeyNav = true;
	m_selection = nil;
	m_mainFocusKey = "tab:1";
	m_secondsSinceKey = 0;
	OutputMessageToScreenReader("Options", true);
	OutputMessageToScreenReader(Locale.Lookup(m_tabs[1][3])..", tab 1 of "..tostring(#m_tabs), true);
	KeyNavMoveMouse(m_tabs[1][1]);
end

-------------------------------------------------------------------------------
function BroadcastGameConfigChanges() end -- Do nothing, we broadcast changes inside OnConfirm

-------------------------------------------------------------------------------
function Options_UI_CreateParameter(o, parameter)
	-- Add the colon to the setting name to match convention of options screen
	parameter.Name = parameter.Name .. ":";
	GameParameters_UI_CreateParameter(o, parameter);
end

-------------------------------------------------------------------------------
BASE_Config_Read = SetupParameters.Config_Read;
function SetupParameters:Config_Read(group, id)
	
	if m_pendingGameConfigChanges[group] and m_pendingGameConfigChanges[group][id] then
		return m_pendingGameConfigChanges[group][id];
	end

	return BASE_Config_Read(self, group, id);
end

-------------------------------------------------------------------------------
BASE_Config_Write = SetupParameters.Config_Write;
function SetupParameters:Config_Write(group, id, value)
	local prevValue = self:Config_Read(group, id);
	if prevValue ~= value then
		Controls.ConfirmButton:SetDisabled(false);

		if not m_pendingGameConfigChanges[group] then
			m_pendingGameConfigChanges[group] = {};
		end
		
		m_pendingGameConfigChanges[group][id] = value;
		return true;
	end
	return false;
end

-------------------------------------------------------------------------------
function OnToggleAdvancedOptions()
	if(Controls.AdvancedGraphicsOptions:IsSelected()) then
		Controls.AdvancedGraphicsOptions:SetSelected(false);
		Controls.AdvancedGraphicsOptions:SetText(Locale.Lookup("LOC_OPTIONS_SHOW_ADVANCED_GRAPHICS"));
		Controls.AdvancedOptionsContainer:SetHide(true);
	else
		Controls.AdvancedGraphicsOptions:SetSelected(true);
		Controls.AdvancedGraphicsOptions:SetText(Locale.Lookup("LOC_OPTIONS_HIDE_ADVANCED_GRAPHICS"));
		Controls.AdvancedOptionsContainer:SetHide(false);
	end
	Controls.GraphicsOptionsStack:CalculateSize();	
	Controls.GraphicsOptionsPanel:CalculateSize();
end
-------------------------------------------------------------------------------
function OnSwitchUILayout()
	LuaEvents.SwitchLayoutPopup_OpenSwitchLayoutPopup();
end
-------------------------------------------------------------------------------
function Resize()
	local screenX, screenY:number = UIManager:GetScreenSizeVal();
	if(screenY >= MIN_SCREEN_Y + (Controls.LogoContainer:GetSizeY()+ Controls.LogoContainer:GetOffsetY() * 2)) then
		Controls.MainWindow:SetSizeY(screenY-(Controls.LogoContainer:GetSizeY() + Controls.LogoContainer:GetOffsetY() * 2));
		Controls.Content:SetSizeY(SCREEN_OFFSET_Y + Controls.MainWindow:GetSizeY()-(Controls.ConfirmButton:GetSizeY() + Controls.LogoContainer:GetSizeY()));
	else
		Controls.MainWindow:SetSizeY(screenY);
		Controls.Content:SetSizeY(MIN_SCREEN_OFFSET_Y + Controls.MainWindow:GetSizeY()-(Controls.ConfirmButton:GetSizeY()));
	end
end

function OnUpdateUI( type:number, tag:string, iData1:number, iData2:number, strData1:string )   
  if type == SystemUpdateUI.ScreenResize then
    Resize();
  end
end

function OnUpdateGraphicsOptions()
    PopulateGraphicsOptions();  -- Ensure that the new monitor's resolutions are shown in the UI
end

-- ===========================================================================
--	UICallback
--	tab, a data struct of a tab OR an index of the struct to use
-- ===========================================================================
function OnSelectTab( tab )
	
	-- If an index, use to look up tab structure
	if type(tab)=="number" then
		originalTabValue = tab; -- save for error message
		tab = m_tabs[tab];
		if tab == nil then
			UI.DataError("Could not switch option tab, invalid tab id passed in: "..tostring(originalTabValue));
			return;
		end
	end

	local button = tab[1];
	local panel = tab[2];
	local title = tab[3]
	for i, v in ipairs(m_tabs) do
		v[2]:SetHide(true);
		v[1]:SetSelected(false);
		if tab[4] == 1 then
			Controls.ResetButton:SetHide(true);
		else
			Controls.ResetButton:SetHide(false);
		end
	end	
	button:SetSelected(true);
	panel:SetHide(false);
	m_currentTab = tab;
	Controls.WindowTitle:SetText(Locale.ToUpper(Locale.Lookup(title)));
end

function Initialize()

	_PromptRestartApp = false;
	_PromptRestartGame = false;
	_PromptResolutionAck = false;

	_kPopupDialog = PopupDialog:new( "Options" );

	Controls.AdvancedGraphicsOptions:RegisterCallback(Mouse.eLClick, OnToggleAdvancedOptions);
	Controls.AdvancedGraphicsOptions:RegisterCallback( Mouse.eMouseEnter, function() UI.PlaySound("Main_Menu_Mouse_Over"); end);

	Controls.WindowCloseButton:RegisterCallback(Mouse.eLClick, CancelOptions);
	Controls.WindowCloseButton:RegisterCallback( Mouse.eMouseEnter, function() UI.PlaySound("Main_Menu_Mouse_Over"); end);

	Controls.SwitchUILayout:RegisterCallback(Mouse.eLClick, OnSwitchUILayout);
	Controls.SwitchUILayout:RegisterCallback( Mouse.eMouseEnter, function() UI.PlaySound("Main_Menu_Mouse_Over"); end);

	Controls.ResetButton:RegisterCallback(Mouse.eLClick, OnReset);
	Controls.ResetButton:RegisterCallback( Mouse.eMouseEnter, function() UI.PlaySound("Main_Menu_Mouse_Over"); end);

	Controls.ConfirmButton:RegisterCallback(Mouse.eLClick, OnConfirm);
	Controls.ConfirmButton:RegisterCallback( Mouse.eMouseEnter, function() UI.PlaySound("Main_Menu_Mouse_Over"); end);

	
	Controls.CancelBindingButton:RegisterCallback( Mouse.eMouseEnter, function() UI.PlaySound("Main_Menu_Mouse_Over"); end);
	Controls.ClearBindingButton:RegisterCallback( Mouse.eMouseEnter, function() UI.PlaySound("Main_Menu_Mouse_Over"); end);
	
	Events.OptionChangeRequiresAppRestart.Add(OnOptionChangeRequiresAppRestart);
	Events.OptionChangeRequiresGameRestart.Add(OnOptionChangeRequiresGameRestart);
	Events.OptionChangeRequiresResolutionAck.Add(OnOptionChangeRequiresResolutionAck);

	LuaEvents.PBCNotifyRemind_ShowOptions.Add(OnPBCNotifyRemind_ShowOptions);

	ContextPtr:SetShowHandler( OnShow );
	ContextPtr:SetHideHandler( function() KeyNavEditBox_Cancel(); end );
	ContextPtr:SetInputHandler(InputHandler, true );
	ContextPtr:SetUpdate( OnOptionsUpdate );

	--AutoSizeGridButton(Controls.AdvancedGraphicsOptions,250,22,10,"H");
	AutoSizeGridButton(Controls.WindowCloseButton,133,36);
	Controls.GraphicsOptionsPanel:CalculateSize();

	m_tabs = {
		{Controls.GameTab,		Controls.GameOptions,				"LOC_OPTIONS_GAME_OPTIONS",         0},
		{Controls.GraphicsTab,	Controls.GraphicsOptions,			"LOC_OPTIONS_GRAPHICS_OPTIONS",     0},
		{Controls.AudioTab,		Controls.AudioOptions,				"LOC_OPTIONS_AUDIO_OPTIONS",        0},
		{Controls.InterfaceTab, Controls.InterfaceOptions,			"LOC_OPTIONS_INTERFACE_OPTIONS",    0},
		{Controls.AppTab,		Controls.ApplicationOptions,		"LOC_OPTIONS_APPLICATION_OPTIONS",  0},
	};

	-- TODO: Some platforms set language outside of the application at which point we must disable this panel.
	local supportsChangingLanguage = true;

	if(supportsChangingLanguage) then
		table.insert(m_tabs, {Controls.LanguageTab, Controls.LanguageOptions,"LOC_OPTIONS_LANGUAGE_OPTIONS",0});
	end

	-- TODO: Some platforms don't allow for key binding.  Disable this panel.
	local supportsKeyBinding = true;

	if(supportsKeyBinding) then
		table.insert(m_tabs, {Controls.KeyBindingsTab, Controls.KeyBindings,"LOC_OPTIONS_KEY_BINDINGS_OPTIONS",1});
		InitializeKeyBinding();
	end
	
	for i, tab in ipairs(m_tabs) do
		local button = tab[1];
		button:RegisterCallback(Mouse.eMouseEnter, function()
			if m_secondsSinceKey < 1.0 then
				-- echo of the mouse move that follows keyboard focus; the focus change was already announced
			else
				OutputMessageToScreenReader(Locale.Lookup(tab[3]));
			end
            UI.PlaySound("Main_Menu_Mouse_Over");
		end);
		button:RegisterCallback(Mouse.eLClick, function() 
			-- a mouse click selects the tab but stays at tab level, so Escape still closes Options
			OnSelectTab(tab);
			m_inMainKeyNav = true;
			m_selection = nil;
			for j, t in ipairs(m_tabs) do
				if t == tab then m_mainFocusKey = "tab:"..tostring(j); end
			end
		end );
		button:SetHide(false);
	end

	if (Network.GetNetworkPlatform() == NetworkPlatform.NETWORK_PLATFORM_EOS) then
		Controls.SteamControllerMessage:SetHide(true);
	end

	m_tabs[1][1]:SetSelected(true);
	m_currentTab = m_tabs[1];
	Controls.WindowTitle:SetText(Locale.ToUpper(Locale.Lookup(m_tabs[1][3])));
	Controls.TabStack:CalculateSize();

	Events.SystemUpdateUI.Add( OnUpdateUI );
    Events.UpdateGraphicsOptions.Add( OnUpdateGraphicsOptions );

	Resize();
end

Initialize();





