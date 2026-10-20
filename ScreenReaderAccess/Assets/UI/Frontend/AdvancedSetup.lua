-- ===========================================================================
--	Single Player Create Game w/ Advanced Options
-- ===========================================================================
include("InstanceManager");
include("PlayerSetupLogic");
include("Civ6Common");
include("SupportFunctions");
include("PopupDialog");
include("KeyboardNavigation");
include("ScreenReader");

-- ===========================================================================
-- ===========================================================================

local PULLDOWN_TRUNCATE_OFFSET:number = 40;

local MIN_SCREEN_Y			:number = 768;
local SCREEN_OFFSET_Y		:number = 61;
local MIN_SCREEN_OFFSET_Y	:number = -53;

local MAX_SIDEBAR_Y			:number = 960;

-- ===========================================================================
-- ===========================================================================

-- Instance managers for dynamic simple game options.
g_SimpleBooleanParameterManager = InstanceManager:new("SimpleBooleanParameterInstance", "CheckBox", Controls.CheckBoxParent);
g_SimpleGameModeParameterManager = InstanceManager:new("GameModeSelectorInstance", "Top", Controls.CheckBoxParent);
g_SimplePullDownParameterManager = InstanceManager:new("SimplePullDownParameterInstance", "Root", Controls.PullDownParent);
g_SimpleSliderParameterManager = InstanceManager:new("SimpleSliderParameterInstance", "Root", Controls.SliderParent);
g_SimpleStringParameterManager = InstanceManager:new("SimpleStringParameterInstance", "Root", Controls.EditBoxParent);

-- Instance managers for Game Mode placard and details flyouts
local m_gameModeToolTipHeaderIM = InstanceManager:new("HeaderInstance", "Top", Controls.GameModeInfoStack );
local m_gameModeToolTipHeaderIconIM = InstanceManager:new("IconInstance", "Top", Controls.GameModeInfoStack );

g_kMapData = {};	-- Global set of map data; enough for map selection context to do it's thing. (Parameter list still truly owns the data.)

local m_NonLocalPlayerSlotManager	:table = InstanceManager:new("NonLocalPlayerSlotInstance", "Root", Controls.NonLocalPlayersSlotStack);
local m_singlePlayerID				:number = 0;			-- The player ID of the human player in singleplayer.
local m_AdvancedMode				:boolean = false;
local m_RulesetData					:table = {};
local m_BasicTooltipData			:table = {};
local m_WorldBuilderImport          :boolean = false;

local m_pWarningPopup:table = PopupDialog:new("CityStateWarningPopup");

-- ===========================================================================
-- Override hiding game setup to release simplified instances.
-- ===========================================================================
GameSetup_HideGameSetup = HideGameSetup;
function HideGameSetup(func)
	GameSetup_HideGameSetup(func);
	g_SimpleBooleanParameterManager:ResetInstances();
	g_SimpleGameModeParameterManager:ResetInstances();
	g_SimplePullDownParameterManager:ResetInstances();
	g_SimpleSliderParameterManager:ResetInstances();
	g_SimpleStringParameterManager:ResetInstances();
end

-- ===========================================================================
-- Keyboard navigation (basic Create Game window and Advanced Setup window)
-- ===========================================================================
local m_keyNavFocus			:object = nil;		-- Key (see item.key) of the item that currently has keyboard focus.
local m_pendingMouseMove	:table = nil;		-- { control, frames } move mouse once layout has settled.
local m_pendingFocus		:table = nil;		-- { key, prefix, frames, tries } focus an item once the UI has refreshed.
local m_keyNavSlots			:table = {};		-- Player slots built by RefreshPlayerSlots: { id, isLocal, instance, canRemove }.
local m_keyNavPopupWasOpen	:boolean = false;

local function KeyNavIsUsable( control:object )
	return control ~= nil and not control:IsHidden() and not control:IsDisabled();
end

-- Returns the previous/next valid (non-invalid) value of a parameter, without wrapping.
local function KeyNavGetValueByOffset( parameter:table, offset:number )
	local values:table = parameter.Values;
	if values == nil or parameter.Value == nil then return nil; end
	local current:number = nil;
	for i, v in ipairs(values) do
		if v.Value == parameter.Value.Value then current = i; break; end
	end
	if current == nil then return nil; end
	local i:number = current + offset;
	while i >= 1 and i <= #values and values[i].Invalid do
		i = i + offset;
	end
	if i >= 1 and i <= #values then
		return values[i];
	end
	return nil;
end

-- Order by on-screen position (rows first, then left to right); insertion sort so the result is deterministic.
local function KeyNavSortByPosition( list:table )
	for i = 1, #list do
		local x:number, y:number = list[i].control:GetScreenOffset();
		list[i].x = x;
		list[i].y = y;
	end
	for i = 2, #list do
		local item:table = list[i];
		local j:number = i - 1;
		while j >= 1 do
			local other:table = list[j];
			local before:boolean;
			if math.abs(item.y - other.y) > 8 then before = item.y < other.y; else before = item.x < other.x; end
			if not before then break; end
			list[j + 1] = other;
			j = j - 1;
		end
		list[j + 1] = item;
	end
end

local function KeyNavButtonItem( control:object, activate, message:string )
	return {
		control = control, kind = "button", activate = activate, activateMessage = message,
		getText = function() return control:GetText(); end,
	};
end

-- Selection mode (Enter on a pulldown): the mod lists the parameter's valid values itself instead of using the engine's popup.
local m_selection:table = nil;		-- { item, label, options, index, originalIndex }

local PULLDOWN_HINT:string = ", dropdown, Left/Right or Enter to change";

-- Returns the list of selectable (non-invalid) values and the index of the current one.
local function KeyNavGetOptions( parameter:table )
	local options:table = {};
	local current:number = 1;
	if parameter.Values ~= nil then
		for i, v in ipairs(parameter.Values) do
			if not v.Invalid then
				table.insert(options, v);
				if parameter.Value ~= nil and v.Value == parameter.Value.Value then current = #options; end
			end
		end
	end
	return options, current;
end

local function KeyNavPulldownItem( control:object, parameter:table, label:string )
	return {
		control = control, kind = "pulldown", label = label, focusSuffix = PULLDOWN_HINT,
		getText = function()
			return label..": "..(parameter.Value and tostring(parameter.Value.Name) or "");
		end,
		getOptions = function() return KeyNavGetOptions(parameter); end,
		apply = function( v )
			g_GameParameters:SetParameterValue(parameter, v);
			Network.BroadcastGameConfig();
		end,
		step = function( delta )
			local v = KeyNavGetValueByOffset(parameter, delta);
			if v ~= nil then
				g_GameParameters:SetParameterValue(parameter, v);
				Network.BroadcastGameConfig();
			end
		end,
	};
end

-- Leader / civilization pulldown of a player; Enter opens the game's pulldown.
local function KeyNavLeaderItem( control:object, playerParams:table, leaderParam:table, label:string )
	local item:table = KeyNavPulldownItem(control, leaderParam, label);
	local function Apply( v )
		playerParams:SetParameterValue(leaderParam, v);
		local colorParameter = playerParams.Parameters["PlayerColorAlternate"];
		if colorParameter then
			playerParams:SetParameterValue(colorParameter, 0);
		end
	end
	item.apply = Apply;
	item.step = function( delta )
		local v = KeyNavGetValueByOffset(leaderParam, delta);
		if v ~= nil then Apply(v); end
	end;
	return item;
end

local function KeyNavMapItem( control:object, params:table, label:string, activate )
	local parameter:table = params["Map"];
	return {
		control = control, kind = "popup", activate = activate,
		getText = function()
			local name:string = parameter.Value and parameter.Value.Name or control:GetText();
			return label..": "..tostring(name);
		end,
		step = function( delta )
			local v = KeyNavGetValueByOffset(parameter, delta);
			if v ~= nil then
				g_GameParameters:SetParameterValue(parameter, v);
				Network.BroadcastGameConfig();
			end
		end,
	};
end

-- Builds the items for the basic Create Game window.
-- Each item: { control, kind, getText(), step(delta), toggle(), activate() }
local function KeyNavBuildBasicItems()
	local params:table = g_GameParameters and g_GameParameters.Parameters or nil;

	local middle:table = {};
	if params ~= nil then
		local function AddPulldown( pid:string, container:object, pulldown:object )
			local parameter:table = params[pid];
			if parameter ~= nil and parameter.Value ~= nil and not container:IsHidden() and KeyNavIsUsable(pulldown) then
				table.insert(middle, KeyNavPulldownItem(pulldown, parameter, parameter.Name));
			end
		end
		AddPulldown("Ruleset",			Controls.CreateGame_RulesetContainer,			Controls.CreateGame_GameRuleset);
		AddPulldown("GameDifficulty",	Controls.CreateGame_GameDifficultyContainer,	Controls.CreateGame_GameDifficulty);
		AddPulldown("GameSpeeds",		Controls.CreateGame_SpeedPulldownContainer,		Controls.CreateGame_SpeedPulldown);
		AddPulldown("MapSize",			Controls.CreateGame_MapSizeContainer,			Controls.CreateGame_MapSize);

		-- Civilization / leader (a player parameter).
		if not Controls.CreateGame_LocalPlayerContainer:IsHidden() and KeyNavIsUsable(Controls.Basic_LocalPlayerPulldown) then
			local playerParams:table = GetPlayerParameters(m_singlePlayerID);
			local leaderParam:table = playerParams and playerParams.Parameters["PlayerLeader"] or nil;
			if leaderParam ~= nil then
				table.insert(middle, KeyNavLeaderItem(Controls.Basic_LocalPlayerPulldown, playerParams, leaderParam, Locale.Lookup("LOC_SETUP_CIVILIZATION")));
			end
		end

		-- Map type: Left/Right cycles maps, Enter opens the map select popup.
		if params["Map"] ~= nil and not Controls.CreateGame_MapSelectContainer:IsHidden() and KeyNavIsUsable(Controls.MapSelectButton) then
			table.insert(middle, KeyNavMapItem(Controls.MapSelectButton, params, Locale.Lookup("LOC_SETUP_MAP_TYPE"), OnMapSelect));
		end

		-- Game modes, checkboxes, sliders and pulldowns created dynamically from the first (simple) driver.
		for pid, parameter in pairs(params) do
			local drivers:table = g_GameParameters.Controls[pid];
			local driver:table = drivers and drivers[1] or nil;
			local c:table = driver and driver.Control or nil;
			if type(c) == "table" and parameter.Value ~= nil then
				if c.OptionSlider ~= nil then
					if c.Root ~= nil and not c.Root:IsHidden() and not c.OptionSlider:IsHidden() then
						local minimumValue:number = parameter.Values.MinimumValue;
						local maximumValue:number = parameter.Values.MaximumValue;
						table.insert(middle, {
							control = c.OptionSlider, mouseTarget = c.OptionTitle, kind = "slider", focusSuffix = ", slider, minimum "..tostring(minimumValue)..", maximum "..tostring(maximumValue),
							getText = function() return parameter.Name..": "..tostring(parameter.Value); end,
							step = function( delta )
								local newValue:number = math.max(minimumValue, math.min(maximumValue, parameter.Value + delta));
								if newValue ~= parameter.Value then
									g_GameParameters:SetParameterValue(parameter, newValue);
									Network.BroadcastGameConfig();
								end
							end,
						});
					end
				elseif c.CheckBox ~= nil then
					if KeyNavIsUsable(c.CheckBox) then
						table.insert(middle, {
							control = c.CheckBox, kind = "checkbox",
							getText = function()
								return parameter.Name..": "..(parameter.Value and "checked" or "unchecked");
							end,
							toggle = function()
								g_GameParameters:SetParameterValue(parameter, not parameter.Value);
								Network.BroadcastGameConfig();
							end,
						});
					end
				elseif c.PullDown ~= nil and c.Root ~= nil and parameter.Values ~= nil then
					if not c.Root:IsHidden() and KeyNavIsUsable(c.PullDown) then
						table.insert(middle, KeyNavPulldownItem(c.PullDown, parameter, parameter.Name));
					end
				end
			end
		end
	end

	KeyNavSortByPosition(middle);
	for i, item in ipairs(middle) do
		item.panel = Controls.CreateGame_ParametersScrollPanel;
		item.stack = Controls.CreateGameOptions;
	end

	local items:table = {};
	table.insert(items, KeyNavButtonItem(Controls.DefaultButton, OnDefaultButton, "Settings restored to defaults"));
	table.insert(items, KeyNavButtonItem(Controls.CloseButton, OnBackButton));
	for i, v in ipairs(middle) do table.insert(items, v); end
	if KeyNavIsUsable(Controls.AdvancedSetupButton) then table.insert(items, KeyNavButtonItem(Controls.AdvancedSetupButton, OnAdvancedSetup)); end
	if KeyNavIsUsable(Controls.StartButton) then table.insert(items, KeyNavButtonItem(Controls.StartButton, OnStartButton)); end
	return items;
end

-- ---------------------------------------------------------------------------
-- Advanced Setup window
-- ---------------------------------------------------------------------------

-- Parameters of these groups are announced with their section name, e.g. "Victory Conditions, Science Victory: checked".
local function KeyNavSectionPrefix( parameter:table )
	if parameter.GroupId == "Victories" then
		return Locale.Lookup("LOC_SETUP_VICTORY_CONDITIONS");
	elseif parameter.GroupId == "GameModes" then
		return Locale.Lookup("LOC_SETUP_GAME_MODES");
	end
	return nil;
end

-- The control(s) of a parameter are either one driver or an array { basicDriver, advancedDriver }.
local function KeyNavGetAdvancedDriver( control:table )
	if control == nil then return nil; end
	if control.Control ~= nil then return control; end
	local bestKey:number = nil;
	for k, v in pairs(control) do
		if type(k) == "number" and (bestKey == nil or k > bestKey) then bestKey = k; end
	end
	return bestKey and control[bestKey] or nil;
end

local function KeyNavOpenPicker( pid:string, parameter:table )
	if pid == "Map" then
		OnMapSelect();
	elseif pid == "CityStates" then
		LuaEvents.CityStatePicker_Initialize(g_GameParameters.Parameters[pid], g_GameParameters);
		Controls.CityStatePicker:SetHide(false);
	elseif pid == "LeaderPool1" or pid == "LeaderPool2" then
		LuaEvents.LeaderPicker_Initialize(g_GameParameters.Parameters[pid], g_GameParameters);
		Controls.LeaderPicker:SetHide(false);
	elseif parameter.Array then
		LuaEvents.MultiSelectWindow_Initialize(g_GameParameters.Parameters[pid]);
		Controls.MultiSelectWindow:SetHide(false);
	else
		return false;
	end
	return true;
end

local function KeyNavPlayerCount()
	return #GameConfiguration.GetParticipatingPlayerIDs();
end

local function KeyNavQueueFocus( key:object, prefix:string )
	m_pendingFocus = { key = key, prefix = prefix, frames = 6, tries = 0 };
end

local function KeyNavAddPlayer()
	local before:table = {};
	for i, id in ipairs(GameConfiguration.GetParticipatingPlayerIDs()) do before[id] = true; end
	OnAddAIButton();
	local newKey:object = "addai";
	for i, id in ipairs(GameConfiguration.GetParticipatingPlayerIDs()) do
		if not before[id] then newKey = "leader:"..tostring(id); end
	end
	KeyNavQueueFocus(newKey, "Player added, "..KeyNavPlayerCount().." players.");
end

local function KeyNavRemovePlayer( playerId:number )
	local index:number = 1;
	for i, slot in ipairs(m_keyNavSlots) do
		if slot.id == playerId then index = i; end
	end
	RemovePlayer(playerId);
	local target:table = m_keyNavSlots[math.min(index, #m_keyNavSlots)];
	KeyNavQueueFocus(target and ("leader:"..tostring(target.id)) or "addai", "Player removed, "..KeyNavPlayerCount().." players.");
end

-- Builds the items for the Advanced Setup window, in reading order:
-- header buttons, players (left panel), game parameters (right panel), footer buttons.
local function KeyNavBuildAdvancedItems()
	local params:table = g_GameParameters and g_GameParameters.Parameters or nil;
	local items:table = {};

	table.insert(items, KeyNavButtonItem(Controls.DefaultButton, OnDefaultButton, "Settings restored to defaults"));
	table.insert(items, KeyNavButtonItem(Controls.CloseButton, OnBackButton));

	-- Players.
	for index, slot in ipairs(m_keyNavSlots) do
		local playerParams:table = GetPlayerParameters(slot.id);
		local leaderParam:table = playerParams and playerParams.Parameters["PlayerLeader"] or nil;
		local playerLabel:string = "Player "..tostring(index);
		-- The parameter name (LOC_LEADER_TYPE) has no text in the game, so fall back to a plain label.
		local leaderName:string = leaderParam ~= nil and Locale.Lookup(tostring(leaderParam.Name)) or "Leader";
		if string.sub(leaderName, 1, 4) == "LOC_" then leaderName = "Leader"; end
		local pulldown:object = slot.isLocal and Controls.Advanced_LocalPlayerPulldown or (slot.instance and slot.instance.PlayerPullDown);
		if leaderParam ~= nil and leaderParam.Value ~= nil and KeyNavIsUsable(pulldown) then
			local item:table = KeyNavLeaderItem(pulldown, playerParams, leaderParam, playerLabel..", "..leaderName);
			item.key = "leader:"..tostring(slot.id);
			if not slot.isLocal then
				item.panel = Controls.NonLocalPlayersPanel;
				item.stack = Controls.NonLocalPlayersStack;
			end
			table.insert(items, item);
		end
		if not slot.isLocal and slot.canRemove and slot.instance ~= nil and KeyNavIsUsable(slot.instance.RemoveButton) then
			local removeButton:object = slot.instance.RemoveButton;
			table.insert(items, {
				control = removeButton, kind = "button", key = "remove:"..tostring(slot.id),
				panel = Controls.NonLocalPlayersPanel, stack = Controls.NonLocalPlayersStack,
				getText = function() return playerLabel..", "..Locale.Lookup("LOC_DELETE_AI"); end,
				activate = function() KeyNavRemovePlayer(slot.id); end,
			});
		end
	end
	if KeyNavIsUsable(Controls.AddAIButton) then
		local item:table = KeyNavButtonItem(Controls.AddAIButton, KeyNavAddPlayer);
		item.key = "addai";
		item.panel = Controls.NonLocalPlayersPanel;
		item.stack = Controls.NonLocalPlayersStack;
		table.insert(items, item);
	end

	-- Game parameters.
	local middle:table = {};
	if params ~= nil then
		for pid, parameter in pairs(params) do
			local driver:table = KeyNavGetAdvancedDriver(g_GameParameters.Controls[pid]);
			local c:table = driver and driver.Control or nil;
			if type(c) == "table" and (parameter.Value ~= nil or c.Button ~= nil) then
				local section:string = KeyNavSectionPrefix(parameter);
				local label:string = section and (section..", "..tostring(parameter.Name)) or tostring(parameter.Name);
				local item:table = nil;
				if c.OptionSlider ~= nil then
					if parameter.Value ~= nil and c.Root ~= nil and not c.Root:IsHidden() and not c.OptionSlider:IsHidden() and parameter.Values ~= nil then
						item = {
							control = c.OptionSlider, mouseTarget = c.OptionTitle, kind = "slider", focusSuffix = ", slider, minimum "..tostring(parameter.Values.MinimumValue)..", maximum "..tostring(parameter.Values.MaximumValue),
							getText = function() return label..": "..tostring(parameter.Value); end,
							step = function( delta )
								local newValue:number = math.max(parameter.Values.MinimumValue, math.min(parameter.Values.MaximumValue, parameter.Value + delta));
								if newValue ~= parameter.Value then
									g_GameParameters:SetParameterValue(parameter, newValue);
									Network.BroadcastGameConfig();
								end
							end,
						};
					end
				elseif c.CheckBox ~= nil then
					if parameter.Value ~= nil and KeyNavIsUsable(c.CheckBox) then
						item = {
							control = c.CheckBox, kind = "checkbox",
							getText = function() return label..": "..(parameter.Value and "checked" or "unchecked"); end,
							toggle = function()
								g_GameParameters:SetParameterValue(parameter, not parameter.Value);
								Network.BroadcastGameConfig();
							end,
						};
					end
				elseif c.StringEdit ~= nil then
					if parameter.Value ~= nil and c.StringRoot ~= nil and not c.StringRoot:IsHidden() and KeyNavIsUsable(c.StringEdit) then
						item = {
							control = c.StringEdit, kind = "edit",
							getText = function() return label..": "..tostring(c.StringEdit:GetText()); end,
						};
					end
				elseif c.PullDown ~= nil and c.Root ~= nil and parameter.Value ~= nil and parameter.Values ~= nil and not parameter.Array then
					if not c.Root:IsHidden() and KeyNavIsUsable(c.PullDown) then
						item = KeyNavPulldownItem(c.PullDown, parameter, label);
					end
				elseif c.Button ~= nil and c.ButtonRoot ~= nil then
					if not c.ButtonRoot:IsHidden() and KeyNavIsUsable(c.Button) then
						if pid == "Map" then
							item = KeyNavMapItem(c.Button, params, label, OnMapSelect);
						else
							item = {
								control = c.Button, kind = "popup",
								getText = function() return label..": "..tostring(c.Button:GetText()); end,
								activate = function() if not KeyNavOpenPicker(pid, parameter) then KeyNavLeftClick(); end end,
							};
						end
					end
				end
				if item ~= nil then
					item.key = "param:"..pid;
					item.panel = Controls.ParametersScrollPanel;
					item.stack = Controls.ParametersStack;
					table.insert(middle, item);
				end
			end
		end
	end
	KeyNavSortByPosition(middle);
	for i, item in ipairs(middle) do table.insert(items, item); end

	-- Footer buttons.
	if KeyNavIsUsable(Controls.LoadConfig) then table.insert(items, KeyNavButtonItem(Controls.LoadConfig, OnLoadConfig)); end
	if KeyNavIsUsable(Controls.SaveConfig) then table.insert(items, KeyNavButtonItem(Controls.SaveConfig, OnSaveConfig)); end
	if KeyNavIsUsable(Controls.StartButton) then table.insert(items, KeyNavButtonItem(Controls.StartButton, OnStartButton)); end
	return items;
end

-- Builds the navigable items from the current UI state. Each item has a stable key used to track focus.
local function KeyNavBuildItems()
	local items:table = m_AdvancedMode and KeyNavBuildAdvancedItems() or KeyNavBuildBasicItems();
	for i, item in ipairs(items) do
		if item.key == nil then item.key = item.control; end
	end
	return items;
end

-- Announce an item, scroll its panel if needed, and move the mouse onto it.
local function KeyNavFocus( item:table, nointerrupt:boolean, prefix:string )
	m_keyNavFocus = item.key;
	local frames:number = 0;
	if item.panel ~= nil and item.y ~= nil then
		local panel:object = item.panel;
		local stack:object = item.stack;
		local _:number, panelY:number = panel:GetScreenOffset();
		local panelH:number = panel:GetSizeY();
		local itemH:number = item.control:GetSizeY();
		if item.y < panelY or item.y + itemH > panelY + panelH then
			local __:number, stackY:number = stack:GetScreenOffset();
			local range:number = stack:GetSizeY() - panelH;
			if range > 0 then
				local scroll:number = (item.y - stackY + itemH / 2 - panelH / 2) / range;
				panel:SetScrollValue(math.max(0, math.min(1, scroll)));
				frames = 3;	-- let the layout update before reading the new position
			end
		end
	end
	m_pendingMouseMove = { control = item.mouseTarget or item.control, frames = frames };
	local text:string = item.getText();
	if item.focusSuffix ~= nil then text = text..item.focusSuffix; end
	if prefix ~= nil then text = prefix.." "..text; end
	OutputMessageToScreenReader(text, nointerrupt);
end

local function KeyNavFindIndex( items:table )
	for i, item in ipairs(items) do
		if item.key == m_keyNavFocus then return i; end
	end
	return 0;
end

local function KeyNavMove( delta:number )
	local items:table = KeyNavBuildItems();
	local current:number = KeyNavFindIndex(items);
	local nextIndex:number;
	if current == 0 then
		nextIndex = (delta > 0) and 1 or #items;
	else
		nextIndex = current + delta;
		if nextIndex < 1 then nextIndex = #items; end
		if nextIndex > #items then nextIndex = 1; end
	end
	KeyNavFocus(items[nextIndex], false);
end

local function KeyNavFindFocused()
	local items:table = KeyNavBuildItems();
	local index:number = KeyNavFindIndex(items);
	return index > 0 and items[index] or nil;
end

-- Focus the first item of the current window and announce the window.
local function KeyNavEnterWindow( title:string )
	local items:table = KeyNavBuildItems();
	OutputMessageToScreenReader(title, true);
	KeyNavFocus(items[1], true);
end

local function KeyNavPopupOpen()
	return not Controls.MapSelectWindow:IsHidden() or not Controls.ConflictPopup:IsHidden()
		or not Controls.LeaderPicker:IsHidden() or not Controls.CityStatePicker:IsHidden()
		or not Controls.MultiSelectWindow:IsHidden() or m_pWarningPopup:IsOpen();
end

-- Only handle keys while the Create Game or Advanced Setup window is what the player is looking at.
local function KeyNavIsActive()
	if KeyNavPopupOpen() then return false; end
	if m_AdvancedMode then
		return not Controls.AdvancedOptionsWindow:IsHidden();
	end
	return not Controls.CreateGameWindow:IsHidden();
end

-- ---------------------------------------------------------------------------
-- Selection mode (Enter on a pulldown)
-- ---------------------------------------------------------------------------
local function KeyNavSelectionText()
	local v:table = m_selection.options[m_selection.index];
	return tostring(v.Name)..", "..tostring(m_selection.index).." of "..tostring(#m_selection.options);
end

local function KeyNavOpenSelection( item:table )
	local options:table, current:number = item.getOptions();
	if #options == 0 then return; end
	local label:string = item.label or "";
	m_selection = { item = item, options = options, index = current, originalIndex = current };
	OutputMessageToScreenReader(label..", "..KeyNavSelectionText()..". Up/Down to choose, Enter to select, Escape to cancel", false);
end

local function KeyNavSelectionKey( key:number )
	local sel:table = m_selection;
	if key == Keys.VK_UP or key == Keys.VK_DOWN or key == Keys.VK_HOME or key == Keys.VK_END then
		if key == Keys.VK_UP then
			sel.index = sel.index - 1; if sel.index < 1 then sel.index = #sel.options; end
		elseif key == Keys.VK_DOWN then
			sel.index = sel.index + 1; if sel.index > #sel.options then sel.index = 1; end
		elseif key == Keys.VK_HOME then
			sel.index = 1;
		else
			sel.index = #sel.options;
		end
		OutputMessageToScreenReader(KeyNavSelectionText(), false);
	elseif key == Keys.VK_RETURN then
		m_selection = nil;
		if sel.index ~= sel.originalIndex then
			sel.item.apply(sel.options[sel.index]);
		end
		OutputMessageToScreenReader(sel.item.getText(), false);
	elseif key == Keys.VK_ESCAPE then
		m_selection = nil;
		OutputMessageToScreenReader("Cancelled, "..sel.item.getText(), false);
	end
	return true;
end

function KeyHandler( key:number )
	if m_selection ~= nil and not KeyNavIsActive() then m_selection = nil; end
	if m_selection ~= nil then
		return KeyNavSelectionKey(key);
	end
	if key == Keys.VK_ESCAPE then
		if not KeyNavPopupOpen() then
			OnBackButton();
		end
		return true;
	end
	if not KeyNavIsActive() then
		return true;
	end

	if key == Keys.VK_UP then
		KeyNavMove(-1);
	elseif key == Keys.VK_DOWN then
		KeyNavMove(1);
	elseif key == Keys.VK_LEFT or key == Keys.VK_RIGHT then
		local item:table = KeyNavFindFocused();
		if item ~= nil and item.step ~= nil then
			item.step(key == Keys.VK_LEFT and -1 or 1);
			OutputMessageToScreenReader(item.getText(), false);
		end
	elseif key == Keys.VK_RETURN or key == Keys.VK_SPACE then
		local item:table = KeyNavFindFocused();
		if item ~= nil then
			if key == Keys.VK_RETURN and item.getOptions ~= nil then
				KeyNavOpenSelection(item);
			elseif item.kind == "checkbox" then
				item.toggle();
				OutputMessageToScreenReader(item.getText(), false);
			elseif key == Keys.VK_RETURN and (item.kind == "button" or item.kind == "popup" or item.kind == "edit") then
				if item.activate ~= nil then
					item.activate();
					if item.activateMessage ~= nil then
						OutputMessageToScreenReader(item.activateMessage, false);
					end
				else
					KeyNavLeftClick();
				end
			end
		end
	end
	return true;
end

-- ===========================================================================
-- Input Handler
-- ===========================================================================
function OnInputHandler( pInputStruct:table )
	local uiMsg = pInputStruct:GetMessageType();
	if uiMsg == KeyEvents.KeyUp then
		local ok, result = xpcall(function() return KeyHandler( pInputStruct:GetKey() ); end, function(e) return debug.traceback(tostring(e), 2); end);
		if not ok then print("KEYNAV ERROR: "..tostring(result)); return true; end
		return result;
	end
	return true;
end

local function KeyNavUpdate()
	-- Focus an item once the UI has caught up with a change (e.g. a player was added or removed).
	if m_pendingFocus ~= nil then
		m_pendingFocus.frames = m_pendingFocus.frames - 1;
		if m_pendingFocus.frames <= 0 then
			local items:table = KeyNavBuildItems();
			local found:table = nil;
			for i, item in ipairs(items) do
				if item.key == m_pendingFocus.key then found = item; end
			end
			if found ~= nil then
				KeyNavFocus(found, false, m_pendingFocus.prefix);
				m_pendingFocus = nil;
			elseif m_pendingFocus.tries >= 10 then
				KeyNavFocus(items[1], false, m_pendingFocus.prefix);
				m_pendingFocus = nil;
			else
				m_pendingFocus.tries = m_pendingFocus.tries + 1;
				m_pendingFocus.frames = 5;
			end
		end
	end

	-- When a popup (map select, pickers, ...) closes, re-announce the focused item and put the mouse back on it.
	local popupOpen:boolean = KeyNavPopupOpen();
	if m_keyNavPopupWasOpen and not popupOpen and m_pendingFocus == nil and m_keyNavFocus ~= nil then
		local item:table = KeyNavFindFocused();
		if item ~= nil then
			KeyNavFocus(item, false);
		end
	end
	m_keyNavPopupWasOpen = popupOpen;
end

function OnKeyNavUpdate( deltaTime:number )
	local ok, err = pcall(KeyNavUpdate);
	if not ok then print("KEYNAV ERROR: "..tostring(err)); end
	if m_pendingMouseMove ~= nil then
		if m_pendingMouseMove.frames <= 0 then
			KeyNavMoveMouse(m_pendingMouseMove.control);
			m_pendingMouseMove = nil;
		else
			m_pendingMouseMove.frames = m_pendingMouseMove.frames - 1;
		end
	end
	KeyNav_Tick(deltaTime);
end


local _UI_BeforeRefresh = UI_BeforeRefresh;
function UI_BeforeRefresh()
	
	if(_UI_BeforeRefresh) then
		_UI_BeforeRefresh();
	end

	-- Reset basic setup container states
	Controls.CreateGame_GameDifficultyContainer:SetHide(true);
	Controls.CreateGame_SpeedPulldownContainer:SetHide(true);
	Controls.CreateGame_MapTypeContainer:SetHide(true);
	Controls.CreateGame_MapSizeContainer:SetHide(true);
end

local _UI_AfterRefresh = GameParameters_UI_AfterRefresh;
function GameParameters_UI_AfterRefresh(o)
	
	if(_UI_AfterRefresh) then
		_UI_AfterRefresh(o);
	end
	
	-- All parameters are provided with a sort index and are manipulated
	-- in that particular order.
	-- However, destroying and re-creating parameters can get expensive
	-- and thus is avoided.  Because of this, some parameters may be 
	-- created in a bad order.  
	-- It is up to this function to ensure order is maintained as well
	-- as refresh/resize any containers.
	-- FYI: Because of the way we're sorting, we need to delete instances
	-- rather than release them.  This is because releasing merely hides it
	-- but it still gets thrown in for sorting, which is frustrating.
	local sort = function(a,b)
	
		-- ForgUI requires a strict weak ordering sort.
		local ap = g_SortingMap[tostring(a)];
		local bp = g_SortingMap[tostring(b)];

		if(ap == nil and bp ~= nil) then
			return true;
		elseif(ap == nil and bp == nil) then
			return tostring(a) < tostring(b);
		elseif(ap ~= nil and bp == nil) then
			return false;
		else
			return o.Utility_SortFunction(ap, bp);
		end
	end

	local stacks = {};
	table.insert(stacks, Controls.CreateGame_ExtraParametersStack);
	table.insert(stacks, Controls.CreateGame_GameModeParametersStack);

	for i,v in ipairs(stacks) do
		v:SortChildren(sort);
	end

	for i,v in ipairs(stacks) do
		v:CalculateSize();
		v:ReprocessAnchoring();
	end
	   
	Controls.CreateGameOptions:CalculateSize();
	Controls.CreateGameOptions:ReprocessAnchoring();

	if Controls.CreateGame_ParametersScrollPanel then
		Controls.CreateGame_ParametersScrollPanel:CalculateInternalSize();
	end

end

-- Override for SetupParameters to filter ruleset values by non-scenario only.
function GameParameters_FilterValues(o, parameter, values)
	values = o.Default_Parameter_FilterValues(o, parameter, values);
	if(parameter.ParameterId == "Ruleset") then
		local new_values = {};
		for i,v in ipairs(values) do
			local data = GetRulesetData(v.Value);
			if(not data.IsScenario) then
				table.insert(new_values, v);
			end
		end
		values = new_values;
	end

	return values;
end

function GetRulesetData(rulesetType)
	if not m_RulesetData[rulesetType] then
		local query:string = "SELECT Description, LongDescription, IsScenario, ScenarioSetupPortrait, ScenarioSetupPortraitBackground from Rulesets where RulesetType = ? LIMIT 1";
		local result:table = DB.ConfigurationQuery(query, rulesetType);
		if result and #result > 0 then
			m_RulesetData[rulesetType] = result[1];
		else
			m_RulesetData[rulesetType] = {};
		end
	end
	return m_RulesetData[rulesetType];
end

-- Cache frequently accessed data.
local _cachedMapDomain = nil;
local _cachedMapData = nil;
function GetMapData( domain:string, file:string )
	-- Refresh the cache if needed.
	if(_cachedMapData == nil or _cachedMapDomain ~= domain) then
		_cachedMapDomain = domain;
		_cachedMapData = {};
		local query = "SELECT File, Image, StaticMap from Maps where Domain = ?";
		local results = DB.ConfigurationQuery(query, domain);
		if(results) then		
			for i,v in ipairs(results) do
				_cachedMapData[v.File] = v;
			end
		end
	end 

	local mapInfo = _cachedMapData[file];
	if(mapInfo) then
		local isOfficial = mapInfo.IsOfficial;
		if(isOfficial == nil) then
			local modId,path = Modding.ParseModUri(mapInfo.File);
			isOfficial = (modId == nil) or Modding.IsModOfficial(modId);
			mapInfo.IsOfficial = isOfficial;
		end
		
		return mapInfo;
	else
		-- return nothing.
		return nil;
	end
end

-- ===========================================================================
--	Build a sub-set of SetupParameters that can be used to populate a
--	map selection screen.
--
--	To send maps:		LuaEvents.MapSelect_PopulatedMaps( g_kMapData );
--	To receive choice:	LuaEvents.MapSelect_SetMapByValue( value );
-- ===========================================================================
function BuildMapSelectData( kMapParameters:table )
	-- Sanity checks
	if kMapParameters == nil then 
		UI.DataError("Unable to build data for map selection; NIL kMapParameter passed in.);");
		return;
	end

	g_kMapData = {};	-- Clear out existing data.

	-- Loop through maps, create subset of data that is enough to show
	-- content in a map select context as well as match up with the
	-- selection.
	-- Note that "Value" in the table below may be one of the following:
	--	somename.lua									- A map script that is generated
	--	{GUID}somefile.Civ6Map							- World builder map prefixed with a GUID
	--	../..Assets/Maps/SomeFolder/myMap.Civ6Map		- World builder map in another folder
	--	{GUID}../..Assets/Maps/SomeFolder/myMap.Civ6Map	- World builder map in another folder
	local kMapCollection:table = kMapParameters.Values;
	for i,kMapData in ipairs( kMapCollection ) do
		local kExtraInfo :table = GetMapData(kMapData.Domain, kMapData.Value);

		local mapData = {
			RawName			= kMapData.RawName,
			RawDescription	= kMapData.RawDescription,
			SortIndex		= kMapData.SortIndex,
			QueryIndex		= kMapData.QueryIndex,
			Hash			= kMapData.Hash,
			Value			= kMapData.Value,
			Name			= kMapData.Name,
			Texture			= nil,
			IsWorldBuilder	= false,
			IsOfficial		= false,
		};

		if(kExtraInfo) then
			mapData.IsOfficial		= kExtraInfo.IsOfficial;
			mapData.Texture			= kExtraInfo.Image;
			mapData.IsWorldBuilder	= kExtraInfo.StaticMap;
		end
		table.insert(g_kMapData, mapData);
	end

	table.sort(g_kMapData, SortMapsByName);
end

-- ===========================================================================
function SortMapsByName(a, b)
	return Locale.Compare(a.Name, b.Name) == -1;
end

-- ===========================================================================
--	LuaEvent
--	Called from the MapSelect popup for what map was selected.
--	value	the map to set for the game.
-- ===========================================================================
function OnSetMapByValue( value: string )
	local kParameters	:table = g_GameParameters["Parameters"];
	local kMapParameters:table = kParameters["Map"];
	local kMapCollection:table = kMapParameters.Values;
	local isFound		:boolean = false;
	for i,kMapData in ipairs( kMapCollection ) do
		if kMapData.Value == value then
			g_GameParameters:SetParameterValue(kMapParameters, kMapData);
			Network.BroadcastGameConfig();			
			isFound = true;
			break;	
		end
	end
	if (not isFound) then
		UI.DataError("Unable to set the game's map to a map with the value '"..tostring(value).."'");
	end
end

function OnSetParameterValues(pid: string, values: table)
	local indexed_values = {};
	if(values) then
		for i,v in ipairs(values) do
			indexed_values[v] = true;
		end
	end

	if(g_GameParameters) then
		local kParameter: table = g_GameParameters.Parameters and g_GameParameters.Parameters[pid] or nil;
		if(kParameter and kParameter.Values ~= nil) then
			local resolved_values = {};
			for i,v in ipairs(kParameter.Values) do
				if(indexed_values[v.Value]) then
					table.insert(resolved_values, v);
				end
			end		
			g_GameParameters:SetParameterValue(kParameter, resolved_values);
			Network.BroadcastGameConfig();	
		end
	end	
end

-- ===========================================================================
function OnSetParameterValue(pid: string, value: number)
	if(g_GameParameters) then
		local kParameter: table = g_GameParameters.Parameters and g_GameParameters.Parameters[pid] or nil;
		if(kParameter and kParameter.Value ~= nil) then	
            g_GameParameters:SetParameterValue(kParameter, value);
			Network.BroadcastGameConfig();	
		end
	end	
end

-- ===========================================================================
function CreatePulldownDriver(o, parameter, c, container)

	local cache = {};
	local driver = {
		Control = c,
		Container = container,
		UpdateValue = function(value)
			local valueText = value and value.Name or nil;
			local button = c:GetButton();
			if(cache.ValueText ~= valueText or cache.ValueDescription ~= valueDescription) then
				local truncateWidth = button:GetSizeX() - PULLDOWN_TRUNCATE_OFFSET;
				TruncateStringWithTooltip(button, truncateWidth, valueText);
				cache.ValueText = valueText;
			end		
			button:LocalizeAndSetToolTip(value.RawDescription);
		end,
		UpdateValues = function(values)
			-- If container was included, hide it if there is only 1 possible value.
			if(#values == 1 and container ~= nil) then
				container:SetHide(true);
			else
				if(container) then
					container:SetHide(false);
				end

				local refresh = false;
				local cValues = cache.Values;
				if(cValues and #cValues == #values) then
					for i,v in ipairs(values) do
						local cv = cValues[i];
						if(cv == nil) then
							refresh = true;
							break;
						elseif(cv.QueryId ~= v.QueryId or cv.QueryIndex ~= v.QueryIndex or cv.Invalid ~= v.Invalid or cv.InvalidReason ~= v.InvalidReason) then
							refresh = true;
							break;
						end
					end
				else
					refresh = true;
				end

				if(refresh) then
					c:ClearEntries();
					for i,v in ipairs(values) do
						local entry = {};
						c:BuildEntry( "InstanceOne", entry );
						entry.Button:SetText(v.Name);
						if v.RawDescription then
							entry.Button:SetToolTipString(Locale.Lookup(v.RawDescription));
						else
							entry.Button:SetToolTipString(v.Description);
						end

						entry.Button:RegisterCallback(Mouse.eLClick, function()
							o:SetParameterValue(parameter, v);
							Network.BroadcastGameConfig();
						end);
					end
					c:CalculateInternals();
					cache.Values = values;
				end
			end			
		end,
		SetEnabled = function(enabled, parameter)
			c:SetDisabled(not enabled or #parameter.Values <= 1);
		end,
		SetVisible = function(visible, parameter)
			container:SetHide(not visible or parameter.Value == nil);
		end,	
		Destroy = nil,		-- It's a fixed control, no need to delete.
	};
	
	return driver;	
end

-- ===========================================================================
--	Driver for the simple menu's "Map Select"
-- ===========================================================================
function CreateSimpleMapPopupDriver(o, parameter )
	local uiMapPopupButton:object = Controls.MapSelectButton;
	local kDriver :table = {
		UpdateValues = function(o, parameter) 
			BuildMapSelectData(parameter);
		end,
		UpdateValue = function( kValue:table )
			local valueText			:string = kValue and kValue.Name or nil;
			local valueDescription	:string = kValue and kValue.Description or nil
			uiMapPopupButton:SetText( valueText );
			uiMapPopupButton:SetToolTipString( valueDescription );
		end
	}
	return kDriver;
end

-- ===========================================================================
--	Used to launch popups
--	o				main object of all the parameters
--	parameter		the parameter being changed
--	activateFunc	The function to be called when the button is pressed
--	parent			(optional) The parent control to connect to
--
--	RETURNS:		A 'driver' that represents a UI control and various common
--					functions that manipulate the control in a setup screen.
-- ===========================================================================
function CreateButtonPopupDriver(o, parameter, activateFunc, parent )

	-- Sanity check
	if(activateFunc == nil) then
		UI.DataError("Ignoring creating popup button because no callback function was passed in. Parameters: name="..parameter.Name..", groupID="..tostring(parameter.GroupId));
		return {}
	end

	-- Apply defaults
	if(parent == nil) then
		parent = GetControlStack(parameter.GroupId);
	end
			
	-- Get the UI instance
	local c :object = g_ButtonParameterManager:GetInstance();	

	-- Store the root control, NOT the instance table.
	g_SortingMap[tostring(c.ButtonRoot)] = parameter;

	c.ButtonRoot:ChangeParent(parent);
	if c.StringName ~= nil then
		c.StringName:SetText(parameter.Name);
	end

	local cache = {};

	local kDriver :table = {
		Control = c,
		Cache = cache,
		UpdateValue = function(value)
			local valueText = value and value.Name or nil;
			local valueDescription = value and value.Description or nil
			if(cache.ValueText ~= valueText or cache.ValueDescription ~= valueDescription) then
				local button = c.Button;
				button:RegisterCallback( Mouse.eLClick, activateFunc );					
				button:SetText(valueText);
				button:SetToolTipString(valueDescription);
				cache.ValueText = valueText;
				cache.ValueDescription = valueDescription;
			end
		end,
		UpdateValues = function(values, p) 
			BuildMapSelectData(p);
		end,
		SetEnabled = function(enabled, parameter)
			c.Button:SetDisabled(not enabled or #parameter.Values <= 1);
		end,
		SetVisible = function(visible)
			c.ButtonRoot:SetHide(not visible);
		end,
		Destroy = function()
			g_ButtonParameterManager:ReleaseInstance(c);
		end,
	};	

	return kDriver;
end

-- ===========================================================================
-- This driver is for launching a multi-select option in a separate window.
-- ===========================================================================
function CreateMultiSelectWindowDriver(o, parameter, parent)

	if(parent == nil) then
		parent = GetControlStack(parameter.GroupId);
	end
			
	-- Get the UI instance
	local c :object = g_ButtonParameterManager:GetInstance();	

	local parameterId = parameter.ParameterId;
	local button = c.Button;
	button:RegisterCallback( Mouse.eLClick, function()
		LuaEvents.MultiSelectWindow_Initialize(o.Parameters[parameterId]);
		Controls.MultiSelectWindow:SetHide(false);
	end);
	button:SetToolTipString(parameter.Description);

	-- Store the root control, NOT the instance table.
	g_SortingMap[tostring(c.ButtonRoot)] = parameter;

	c.ButtonRoot:ChangeParent(parent);
	if c.StringName ~= nil then
		c.StringName:SetText(parameter.Name);
	end

	local cache = {};

	local kDriver :table = {
		Control = c,
		Cache = cache,
		UpdateValue = function(value, p)
			local valueText = value and value.Name or nil;
			local valueAmount :number = 0;
		
			if(valueText == nil) then
				if(value == nil) then
					if (parameter.UxHint ~= nil and parameter.UxHint == "InvertSelection") then
						valueText = "LOC_SELECTION_EVERYTHING";
					else
						valueText = "LOC_SELECTION_NOTHING";
					end
				elseif(type(value) == "table") then
					local count = #value;
					if (parameter.UxHint ~= nil and parameter.UxHint == "InvertSelection") then
						if(count == 0) then
							valueText = "LOC_SELECTION_EVERYTHING";
						elseif(count == #p.Values) then
							valueText = "LOC_SELECTION_NOTHING";
						else
							valueText = "LOC_SELECTION_CUSTOM";
							valueAmount = #p.Values - count;
						end
					else
						if(count == 0) then
							valueText = "LOC_SELECTION_NOTHING";
						elseif(count == #p.Values) then
							valueText = "LOC_SELECTION_EVERYTHING";
						else
							valueText = "LOC_SELECTION_CUSTOM";
							valueAmount = count;
						end
					end
				end
			end				

			if(cache.ValueText ~= valueText) or (cache.ValueAmount ~= valueAmount) then
				local button = c.Button;			
				button:LocalizeAndSetText(valueText, valueAmount);
				cache.ValueText = valueText;
				cache.ValueAmount = valueAmount;
			end
		end,
		UpdateValues = function(values, p) 
			-- Values are refreshed when the window is open.
		end,
		SetEnabled = function(enabled, p)
			c.Button:SetDisabled(not enabled or #p.Values <= 1);
		end,
		SetVisible = function(visible)
			c.ButtonRoot:SetHide(not visible);
		end,
		Destroy = function()
			g_ButtonParameterManager:ReleaseInstance(c);
		end,
	};	

	return kDriver;
end

-- ===========================================================================
-- This driver is for launching the city-state picker in a separate window.
-- ===========================================================================
function CreateCityStatePickerDriver(o, parameter, parent)

	if(parent == nil) then
		parent = GetControlStack(parameter.GroupId);
	end
			
	-- Get the UI instance
	local c :object = g_ButtonParameterManager:GetInstance();	

	local parameterId = parameter.ParameterId;
	local button = c.Button;
	button:RegisterCallback( Mouse.eLClick, function()
		LuaEvents.CityStatePicker_Initialize(o.Parameters[parameterId], g_GameParameters);
		Controls.CityStatePicker:SetHide(false);
	end);
	button:SetToolTipString(parameter.Description);

	-- Store the root control, NOT the instance table.
	g_SortingMap[tostring(c.ButtonRoot)] = parameter;

	c.ButtonRoot:ChangeParent(parent);
	if c.StringName ~= nil then
		c.StringName:SetText(parameter.Name);
	end

	local cache = {};

	local kDriver :table = {
		Control = c,
		Cache = cache,
		UpdateValue = function(value, p)
			local valueText = value and value.Name or nil;
			local valueAmount :number = 0;
		
			if(valueText == nil) then
				if(value == nil) then
					if (parameter.UxHint ~= nil and parameter.UxHint == "InvertSelection") then
						valueText = "LOC_SELECTION_EVERYTHING";
					else
						valueText = "LOC_SELECTION_NOTHING";
					end
				elseif(type(value) == "table") then
					local count = #value;
					if (parameter.UxHint ~= nil and parameter.UxHint == "InvertSelection") then
						if(count == 0) then
							valueText = "LOC_SELECTION_EVERYTHING";
						elseif(count == #p.Values) then
							valueText = "LOC_SELECTION_NOTHING";
						else
							valueText = "LOC_SELECTION_CUSTOM";
							valueAmount = #p.Values - count;
						end
					else
						if(count == 0) then
							valueText = "LOC_SELECTION_NOTHING";
						elseif(count == #p.Values) then
							valueText = "LOC_SELECTION_EVERYTHING";
						else
							valueText = "LOC_SELECTION_CUSTOM";
							valueAmount = count;
						end
					end
				end
			end				

			if(cache.ValueText ~= valueText) or (cache.ValueAmount ~= valueAmount) then
				local button = c.Button;			
				button:LocalizeAndSetText(valueText, valueAmount);
				cache.ValueText = valueText;
				cache.ValueAmount = valueAmount;
			end
		end,
		UpdateValues = function(values, p) 
			-- Values are refreshed when the window is open.
		end,
		SetEnabled = function(enabled, p)
			c.Button:SetDisabled(not enabled or #p.Values <= 1);
		end,
		SetVisible = function(visible)
			c.ButtonRoot:SetHide(not visible);
		end,
		Destroy = function()
			g_ButtonParameterManager:ReleaseInstance(c);
		end,
	};	

	return kDriver;
end

-- ===========================================================================
-- This driver is for launching the leader picker in a separate window.
-- ===========================================================================
function CreateLeaderPickerDriver(o, parameter, parent)

	if(parent == nil) then
		parent = GetControlStack(parameter.GroupId);
	end
			
	-- Get the UI instance
	local c :object = g_ButtonParameterManager:GetInstance();	

	local parameterId = parameter.ParameterId;
	local button = c.Button;
	button:RegisterCallback( Mouse.eLClick, function()
		LuaEvents.LeaderPicker_Initialize(o.Parameters[parameterId], g_GameParameters);
		Controls.LeaderPicker:SetHide(false);
	end);
	button:SetToolTipString(parameter.Description);

	-- Store the root control, NOT the instance table.
	g_SortingMap[tostring(c.ButtonRoot)] = parameter;

	c.ButtonRoot:ChangeParent(parent);
	if c.StringName ~= nil then
		c.StringName:SetText(parameter.Name);
	end

	local cache = {};

	local kDriver :table = {
		Control = c,
		Cache = cache,
		UpdateValue = function(value, p)
			local valueText = value and value.Name or nil;
			local valueAmount :number = 0;

			-- Remove random leaders from the Values table that is used to determine number of leaders selected
			for i = #p.Values, 1, -1 do
				local kItem:table = p.Values[i];
				if kItem.Value == "RANDOM" or kItem.Value == "RANDOM_POOL1" or kItem.Value == "RANDOM_POOL2" then
					table.remove(p.Values, i);
				end
			end
		
			if(valueText == nil) then
				if(value == nil) then
					if (parameter.UxHint ~= nil and parameter.UxHint == "InvertSelection") then
						valueText = "LOC_SELECTION_EVERYTHING";
					else
						valueText = "LOC_SELECTION_NOTHING";
					end
				elseif(type(value) == "table") then
					local count = #value;
					if (parameter.UxHint ~= nil and parameter.UxHint == "InvertSelection") then
						if(count == 0) then
							valueText = "LOC_SELECTION_EVERYTHING";
						elseif(count == #p.Values) then
							valueText = "LOC_SELECTION_NOTHING";
						else
							valueText = "LOC_SELECTION_CUSTOM";
							valueAmount = #p.Values - count;
						end
					else
						if(count == 0) then
							valueText = "LOC_SELECTION_NOTHING";
						elseif(count == #p.Values) then
							valueText = "LOC_SELECTION_EVERYTHING";
						else
							valueText = "LOC_SELECTION_CUSTOM";
							valueAmount = count;
						end
					end
				end
			end				

			if(cache.ValueText ~= valueText) or (cache.ValueAmount ~= valueAmount) then
				local button = c.Button;			
				button:LocalizeAndSetText(valueText, valueAmount);
				cache.ValueText = valueText;
				cache.ValueAmount = valueAmount;
			end
		end,
		UpdateValues = function(values, p) 
			-- Values are refreshed when the window is open.
		end,
		SetEnabled = function(enabled, p)
			c.Button:SetDisabled(not enabled or #p.Values <= 1);
		end,
		SetVisible = function(visible)
			c.ButtonRoot:SetHide(not visible);
		end,
		Destroy = function()
			g_ButtonParameterManager:ReleaseInstance(c);
		end,
	};	

	return kDriver;
end

-- ===========================================================================
-- Override parameter behavior for basic setup screen.
g_ParameterFactories["Ruleset"] = function(o, parameter)
	
	local drivers = {};
	-- Basic setup version.
	-- Use an explicit table.
	table.insert(drivers, CreatePulldownDriver(o, parameter, Controls.CreateGame_GameRuleset, Controls.CreateGame_RulesetContainer));

	-- Advanced setup version.
	-- Create the parameter dynamically like we normally would...
	table.insert(drivers, GameParameters_UI_CreateParameterDriver(o, parameter));

	return drivers;
end
g_ParameterFactories["GameDifficulty"] = function(o, parameter)

	local drivers = {};
	-- Basic setup version.
	-- Use an explicit table.
	table.insert(drivers, CreatePulldownDriver(o, parameter, Controls.CreateGame_GameDifficulty, Controls.CreateGame_GameDifficultyContainer));

	-- Advanced setup version.
	-- Create the parameter dynamically like we normally would...
	table.insert(drivers, GameParameters_UI_CreateParameterDriver(o, parameter));

	return drivers;
end

-- ===========================================================================
g_ParameterFactories["GameSpeeds"] = function(o, parameter)

	local drivers = {};
	-- Basic setup version.
	-- Use an explicit table.
	table.insert(drivers, CreatePulldownDriver(o, parameter, Controls.CreateGame_SpeedPulldown, Controls.CreateGame_SpeedPulldownContainer));

	-- Advanced setup version.
	-- Create the parameter dynamically like we normally would...
	table.insert(drivers, GameParameters_UI_CreateParameterDriver(o, parameter));

	return drivers;
end

-- ===========================================================================
g_ParameterFactories["Map"] = function(o, parameter)

	local drivers = {};

    if (m_WorldBuilderImport) then
        return drivers;
    end

	-- Basic setup version.
	table.insert(drivers, CreateSimpleMapPopupDriver(o, parameter) );
	
	-- Advanced setup version.	
	table.insert( drivers, CreateButtonPopupDriver(o, parameter, OnMapSelect) );

	return drivers;
end

-- ===========================================================================
g_ParameterFactories["MapSize"] = function(o, parameter)

	local drivers = {};

    if (m_WorldBuilderImport) then
        return drivers;
    end

	-- Basic setup version.
	-- Use an explicit table.
	table.insert(drivers, CreatePulldownDriver(o, parameter, Controls.CreateGame_MapSize, Controls.CreateGame_MapSizeContainer));

	-- Advanced setup version.
	-- Create the parameter dynamically like we normally would...
	table.insert(drivers, GameParameters_UI_CreateParameterDriver(o, parameter));

	return drivers;
end

function CreateSimpleParameterDriver(o, parameter, parent)

	if(parent == nil) then
		parent = GetControlStack(parameter.GroupId);
	end

	local control;
	
	-- If there is no parent, don't visualize the control.  This is most likely a player parameter.
	if(parent == nil) then
		return;
	end;

	if(parameter.GroupId == "GameModes") then
		local c = g_SimpleGameModeParameterManager:GetInstance();	
		
		-- Store the root control, NOT the instance table.
		g_SortingMap[tostring(c.Top)] = parameter;		
		
		local name = Locale.ToUpper(parameter.Name);
		c.CheckBox:RegisterCallback(Mouse.eLClick, function()
			o:SetParameterValue(parameter, not c.CheckBox:IsSelected());
			Network.BroadcastGameConfig();
		end);	
		c.GameModeIcon:SetIcon("ICON_" .. parameter.ParameterId);
		c.Top:ChangeParent(parent);

		control = {
			UpdateValue = function(value, parameter)
				c.CheckBox:SetSelected(value);
			end,
			Control = c,
			SetEnabled = function(enabled)
				c.CheckBox:SetDisabled(not enabled);
			end,
			SetVisible = function(visible)
				c.CheckBox:SetHide(not visible);
			end,
			Destroy = function()
				g_SimpleGameModeParameterManager:ReleaseInstance(c);
			end,
		};
		c.CheckBox:RegisterCallback( Mouse.eMouseEnter, function() OnGameModeMouseEnter(parameter) end);
		c.CheckBox:RegisterCallback( Mouse.eMouseExit, function() OnGameModeMouseExit(parameter) end);

		if(Controls.NoGameModesContainer:IsHidden() == false)then
			Controls.NoGameModesContainer:SetHide(true);
		end

	elseif(parameter.Domain == "bool") then
		local c = g_SimpleBooleanParameterManager:GetInstance();	
		
		-- Store the root control, NOT the instance table.
		g_SortingMap[tostring(c.CheckBox)] = parameter;		
		
		local name = Locale.ToUpper(parameter.Name);
		c.CheckBox:SetText(name);
		c.CheckBox:SetToolTipString(parameter.Description);
		c.CheckBox:RegisterCallback(Mouse.eLClick, function()
			o:SetParameterValue(parameter, not c.CheckBox:IsSelected());
			Network.BroadcastGameConfig();
		end);
		c.CheckBox:ChangeParent(parent);

		control = {
			Control = c,
			UpdateValue = function(value, parameter)
				
				-- Sometimes the parameter name is changed, be sure to update it.
				c.CheckBox:SetText(parameter.Name);
				c.CheckBox:SetToolTipString(parameter.Description);
				
				-- We have to invalidate the selection state in order
				-- to trick the button to use the right vis state..
				-- Please change this to a real check box in the future...please
				c.CheckBox:SetSelected(not value);
				c.CheckBox:SetSelected(value);
			end,
			SetEnabled = function(enabled)
				c.CheckBox:SetDisabled(not enabled);
			end,
			SetVisible = function(visible)
				c.CheckBox:SetHide(not visible);
			end,
			Destroy = function()
				g_SimpleBooleanParameterManager:ReleaseInstance(c);
			end,
		};

	elseif(parameter.Domain == "int" or parameter.Domain == "uint" or parameter.Domain == "text") then
		local c = g_SimpleStringParameterManager:GetInstance();		

		-- Store the root control, NOT the instance table.
		g_SortingMap[tostring(c.Root)] = parameter;
		
		local name = Locale.ToUpper(parameter.Name);	
		c.StringName:SetText(name);
		c.Root:SetToolTipString(parameter.Description);
		c.StringEdit:SetEnabled(true);

		local canChangeEnableState = true;

		if(parameter.Domain == "int") then
			c.StringEdit:SetNumberInput(true);
			c.StringEdit:SetMaxCharacters(16);
			c.StringEdit:RegisterCommitCallback(function(textString)
				o:SetParameterValue(parameter, tonumber(textString));	
				Network.BroadcastGameConfig();
			end);
		elseif(parameter.Domain == "uint") then
			c.StringEdit:SetNumberInput(true);
			c.StringEdit:SetMaxCharacters(16);
			c.StringEdit:RegisterCommitCallback(function(textString)
				local value = math.max(tonumber(textString) or 0, 0);
				o:SetParameterValue(parameter, value);	
				Network.BroadcastGameConfig();
			end);
		else
			c.StringEdit:SetNumberInput(false);
			c.StringEdit:SetMaxCharacters(64);
			if UI.HasFeature("TextEntry") == true then
				c.StringEdit:RegisterCommitCallback(function(textString)
					o:SetParameterValue(parameter, textString);	
					Network.BroadcastGameConfig();
				end);
			else
				canChangeEnableState = false;
				c.StringEdit:SetEnabled(false);
			end
		end

		c.Root:ChangeParent(parent);

		control = {
			Control = c,
			UpdateValue = function(value)
				c.StringEdit:SetText(Locale.Lookup(value));
			end,
			SetEnabled = function(enabled)
				if canChangeEnableState then
					c.Root:SetDisabled(not enabled);
					c.StringEdit:SetDisabled(not enabled);
				end
			end,
			SetVisible = function(visible)
				c.Root:SetHide(not visible);
			end,
			Destroy = function()
				g_SimpleStringParameterManager:ReleaseInstance(c);
			end,
		};
	elseif (parameter.Values and parameter.Values.Type == "IntRange") then -- Range
		
		local minimumValue = parameter.Values.MinimumValue;
		local maximumValue = parameter.Values.MaximumValue;

		-- Get the UI instance
		local c = g_SimpleSliderParameterManager:GetInstance();	
		
		-- Store the root control, NOT the instance table.
		g_SortingMap[tostring(c.Root)] = parameter;
		
		c.Root:ChangeParent(parent);

		local name = Locale.ToUpper(parameter.Name);
		if c.StringName ~= nil then
			c.StringName:SetText(name);
		end
			
		c.OptionTitle:SetText(name);
		c.Root:SetToolTipString(parameter.Description);
		c.OptionSlider:RegisterSliderCallback(function()
			local stepNum = c.OptionSlider:GetStep();
			
			-- This method can get called pretty frequently, try and throttle it.
			if(parameter.Value ~= minimumValue + stepNum) then
				o:SetParameterValue(parameter, minimumValue + stepNum);
				Network.BroadcastGameConfig();
			end
		end);


		control = {
			Control = c,
			UpdateValue = function(value)
				if(value) then
					c.OptionSlider:SetStep(value - minimumValue);
					c.NumberDisplay:SetText(tostring(value));
				end
			end,
			UpdateValues = function(values)
				c.OptionSlider:SetNumSteps(values.MaximumValue - values.MinimumValue);
			end,
			SetEnabled = function(enabled, parameter)
				c.OptionSlider:SetHide(not enabled or parameter.Values == nil or parameter.Values.MinimumValue == parameter.Values.MaximumValue);
			end,
			SetVisible = function(visible, parameter)
				c.Root:SetHide(not visible or parameter.Value == nil );
			end,
			Destroy = function()
				g_SimpleSliderParameterManager:ReleaseInstance(c);
			end,
		};	
	elseif (parameter.Values) then -- MultiValue
		
		-- Get the UI instance
		local c = g_SimplePullDownParameterManager:GetInstance();	
		
		-- Store the root control, NOT the instance table.
		g_SortingMap[tostring(c.Root)] = parameter;

		c.Root:ChangeParent(parent);
		if c.StringName ~= nil then
			local name = Locale.ToUpper(parameter.Name);
			c.StringName:SetText(name);
		end

		control = {
			Control = c,
			UpdateValue = function(value)
				local button = c.PullDown:GetButton();
				button:SetText( value and value.Name or nil);
				button:SetToolTipString(value and value.Description or nil);
			end,
			UpdateValues = function(values)
				c.PullDown:ClearEntries();

				for i,v in ipairs(values) do
					local entry = {};
					c.PullDown:BuildEntry( "InstanceOne", entry );
					entry.Button:SetText(v.Name);
					entry.Button:SetToolTipString(v.Description);

					entry.Button:RegisterCallback(Mouse.eLClick, function()
						o:SetParameterValue(parameter, v);
						Network.BroadcastGameConfig();
					end);
				end
				c.PullDown:CalculateInternals();
			end,
			SetEnabled = function(enabled, parameter)
				c.PullDown:SetDisabled(not enabled or #parameter.Values <= 1);
			end,
			SetVisible = function(visible)
				c.Root:SetHide(not visible);
			end,
			Destroy = function()
				g_SimplePullDownParameterManager:ReleaseInstance(c);
			end,
		};	
	end

	return control;
end

function GameParameters_UI_CreateParameterDriver(o, parameter, ...)

	if(parameter.ParameterId == "CityStates") then
		if GameConfiguration.IsWorldBuilderEditor() then
			return nil;
		end
		return CreateCityStatePickerDriver(o, parameter);
	elseif(parameter.ParameterId == "LeaderPool1" or parameter.ParameterId == "LeaderPool2") then
		if GameConfiguration.IsWorldBuilderEditor() then
			return nil;
		end
		return CreateLeaderPickerDriver(o, parameter);
	elseif(parameter.Array) then
		return CreateMultiSelectWindowDriver(o, parameter);
	else
		return GameParameters_UI_DefaultCreateParameterDriver(o, parameter, ...);
	end
end

-- The method used to create a UI control associated with the parameter.
-- Returns either a control or table that will be used in other parameter view related hooks.
function GameParameters_UI_CreateParameter(o, parameter)
	local func = g_ParameterFactories[parameter.ParameterId];

	local control;
	if(func)  then
		control = func(o, parameter);
	elseif(parameter.GroupId == "BasicGameOptions" or parameter.GroupId == "BasicMapOptions") then	
		control = {
			CreateSimpleParameterDriver(o, parameter, Controls.CreateGame_ExtraParametersStack),
			GameParameters_UI_CreateParameterDriver(o, parameter)
		};
	elseif(parameter.GroupId == "GameModes") then	
		control = {
			CreateSimpleParameterDriver(o, parameter, Controls.CreateGame_GameModeParametersStack),
			GameParameters_UI_CreateParameterDriver(o, parameter)
		};	
	else
		control = GameParameters_UI_CreateParameterDriver(o, parameter);
	end

	o.Controls[parameter.ParameterId] = control;
end

-- ===========================================================================
-- Remove player handler.
function RemovePlayer(voidValue1, voidValue2, control)
	print("Removing Player " .. tonumber(voidValue1));
	local playerConfig = PlayerConfigurations[voidValue1];
	playerConfig:SetLeaderTypeName(nil);
	
	GameConfiguration.RemovePlayer(voidValue1);

	GameSetup_PlayerCountChanged();
end

-- ===========================================================================
-- Add UI entries for all the players.  This does not set the
-- UI values of the player.
-- ===========================================================================
function RefreshPlayerSlots()

	RebuildPlayerParameters();
	m_NonLocalPlayerSlotManager:ResetInstances();
	m_keyNavSlots = {};

	local player_ids = GameConfiguration.GetParticipatingPlayerIDs();

	local minPlayers = MapConfiguration.GetMinMajorPlayers() or 2;
	local maxPlayers = MapConfiguration.GetMaxMajorPlayers() or 2;
	local can_remove = #player_ids > minPlayers;
	local can_add = #player_ids < maxPlayers;

	Controls.AddAIButton:SetHide(not can_add);

	print("There are " .. #player_ids .. " participating players.");

	Controls.BasicTooltipContainer:DestroyAllChildren();
	Controls.BasicPlacardContainer:DestroyAllChildren();
	Controls.AdvancedTooltipContainer:DestroyAllChildren();
	
	local basicTooltip = {};
	ContextPtr:BuildInstanceForControl( "CivToolTip", basicTooltip, Controls.BasicTooltipContainer );
	local basicPlacard	:table = {};
	ContextPtr:BuildInstanceForControl( "LeaderPlacard", basicPlacard, Controls.BasicPlacardContainer );

	m_BasicTooltipData = {
		InfoStack			= basicTooltip.InfoStack,
		InfoScrollPanel		= basicTooltip.InfoScrollPanel;
		CivToolTipSlide		= basicTooltip.CivToolTipSlide;
		CivToolTipAlpha		= basicTooltip.CivToolTipAlpha;
		UniqueIconIM		= InstanceManager:new("IconInfoInstance",	"Top",	basicTooltip.InfoStack );		
		HeaderIconIM		= InstanceManager:new("IconInstance",		"Top",	basicTooltip.InfoStack );
		CivHeaderIconIM		= InstanceManager:new("CivIconInstance",	"Top",	basicTooltip.InfoStack );
		HeaderIM			= InstanceManager:new("HeaderInstance",		"Top",	basicTooltip.InfoStack );
		HasLeaderPlacard	= true;
		LeaderBG			= basicPlacard.LeaderBG;
		LeaderImage			= basicPlacard.LeaderImage;
		DummyImage			= basicPlacard.DummyImage;
		CivLeaderSlide		= basicPlacard.CivLeaderSlide;
		CivLeaderAlpha		= basicPlacard.CivLeaderAlpha;
	};

	local advancedTooltip	:table = {};
	ContextPtr:BuildInstanceForControl( "CivToolTip", advancedTooltip, Controls.AdvancedTooltipContainer );

	local advancedTooltipData : table = {
		InfoStack			= advancedTooltip.InfoStack,
		InfoScrollPanel		= advancedTooltip.InfoScrollPanel;
		CivToolTipSlide		= advancedTooltip.CivToolTipSlide;
		CivToolTipAlpha		= advancedTooltip.CivToolTipAlpha;
		UniqueIconIM		= InstanceManager:new("IconInfoInstance",	"Top",	advancedTooltip.InfoStack );		
		HeaderIconIM		= InstanceManager:new("IconInstance",		"Top",	advancedTooltip.InfoStack );
		CivHeaderIconIM		= InstanceManager:new("CivIconInstance",	"Top",	advancedTooltip.InfoStack );
		HeaderIM			= InstanceManager:new("HeaderInstance",		"Top",	advancedTooltip.InfoStack );
		HasLeaderPlacard	= false;
	};

	for i, player_id in ipairs(player_ids) do	
		if(m_singlePlayerID == player_id) then
			table.insert(m_keyNavSlots, { id = player_id, isLocal = true });
			SetupLeaderPulldown(player_id, Controls, "Basic_LocalPlayerPulldown", "Basic_LocalPlayerCivIcon",  "Basic_LocalPlayerCivIconBG", "Basic_LocalPlayerLeaderIcon", "Basic_LocalPlayerScrollText", m_BasicTooltipData);
			SetupLeaderPulldown(player_id, Controls, "Advanced_LocalPlayerPulldown", "Advanced_LocalPlayerCivIcon", "Advanced_LocalPlayerCivIconBG", "Advanced_LocalPlayerLeaderIcon", "Advanced_LocalPlayerScrollText", advancedTooltipData, "Advanced_LocalColorPullDown");
		else
			local ui_instance = m_NonLocalPlayerSlotManager:GetInstance();
			table.insert(m_keyNavSlots, { id = player_id, isLocal = false, instance = ui_instance, canRemove = can_remove });
			
			-- Assign the Remove handler
			if(can_remove) then
				ui_instance.RemoveButton:SetVoid1(player_id);
				ui_instance.RemoveButton:RegisterCallback(Mouse.eLClick, RemovePlayer);
			end
			ui_instance.RemoveButton:SetHide(not can_remove);
			
			SetupLeaderPulldown(player_id, ui_instance,"PlayerPullDown",nil,nil,nil,nil,advancedTooltipData);
		end
	end

	Controls.NonLocalPlayersSlotStack:CalculateSize();
	Controls.NonLocalPlayersSlotStack:ReprocessAnchoring();
	Controls.NonLocalPlayersStack:CalculateSize();
	Controls.NonLocalPlayersStack:ReprocessAnchoring();
	Controls.NonLocalPlayersPanel:CalculateInternalSize();
	Controls.NonLocalPlayersPanel:CalculateSize();

	-- Queue another refresh
	GameSetup_RefreshParameters();
end

-- ===========================================================================
-- Called every time parameters have been refreshed.
-- This is a useful spot to perform validation.
function UI_PostRefreshParameters()
	-- Most of the options self-heal due to the setup parameter logic.
	-- However, player options are allowed to be in an 'invalid' state for UI
	-- This way, instead of hiding/preventing the user from selecting an invalid player
	-- we can allow it, but display an error message explaining why it's invalid.

	-- This is primarily used to present ownership errors and custom constraint errors.
	Controls.StartButton:SetDisabled(false);
	Controls.StartButton:SetToolTipString(nil);

	local game_err = GetGameParametersError();
	if(game_err) then
		Controls.StartButton:SetDisabled(true);
		Controls.StartButton:LocalizeAndSetToolTip("LOC_SETUP_PARAMETER_ERROR");
	end
	
	local player_ids = GameConfiguration.GetParticipatingPlayerIDs();
	for i, player_id in ipairs(player_ids) do	
		local err = GetPlayerParameterError(player_id);
		if(err) then
			Controls.StartButton:SetDisabled(true);
			Controls.StartButton:LocalizeAndSetToolTip("LOC_SETUP_PLAYER_PARAMETER_ERROR");
			Controls.ConflictPopup:SetHide(false);
		end
	end

	-- TTP[20948]: Display leader placard for the currently selected leader
	local playerConfig = PlayerConfigurations[m_singlePlayerID];
	if(playerConfig and m_BasicTooltipData) then
		local selectedLeader = playerConfig:GetLeaderTypeID();
		if(selectedLeader ~= -1) then
			local leaderType = playerConfig:GetLeaderTypeName();
			local info = GetPlayerInfo(playerConfig:GetValue("LEADER_DOMAIN"), leaderType);
			DisplayCivLeaderToolTip(info, m_BasicTooltipData, false);
		end
	end
	
	Controls.CreateGameOptions:CalculateSize();
	Controls.CreateGameOptions:ReprocessAnchoring();
end

-------------------------------------------------------------------------------
-- Event Listeners
-------------------------------------------------------------------------------
function OnFinishedGameplayContentConfigure(result)
	if(ContextPtr and not ContextPtr:IsHidden() and result.Success) then
		GameSetup_RefreshParameters();
	end
end

-- ===========================================================================
function GameSetup_PlayerCountChanged()
	print("Player Count Changed");
	RefreshPlayerSlots();
end

-- ===========================================================================
function OnShow()

	 m_WorldBuilderImport = false;
	local bWorldBuilder = GameConfiguration.IsWorldBuilderEditor();

	if (bWorldBuilder) then
		Controls.WindowTitle:LocalizeAndSetText("{LOC_SETUP_CREATE_MAP:upper}");

        if (MapConfiguration.GetScript() == "WBImport.lua") then
            m_WorldBuilderImport = true;
        end

		-- KLUDGE: Ideally setup parameters in a group should have some sort of control mechanism for whether or not the group should show.
		Controls.CreateGame_LocalPlayerContainer:SetHide(true);
		Controls.PlayersSection:SetHide(true);
		Controls.VictoryParametersHeader:SetHide(true);
		
    else
		Controls.CreateGame_LocalPlayerContainer:SetHide(false);
		Controls.PlayersSection:SetHide(false);
		Controls.VictoryParametersHeader:SetHide(false);
		
		Controls.WindowTitle:LocalizeAndSetText("{LOC_SETUP_CREATE_GAME:upper}");
	end

	-- Keyboard navigation: announce the screen and focus the first item.
	m_keyNavFocus = Controls.DefaultButton;
	m_pendingMouseMove = { control = Controls.DefaultButton, frames = 10 };
	OutputMessageToScreenReader(Controls.WindowTitle:GetText(), true);
	OutputMessageToScreenReader(Controls.DefaultButton:GetText(), true);

	RefreshPlayerSlots();	-- Will trigger a game parameter refresh.
	AutoSizeGridButton(Controls.DefaultButton,133,36,15,"H");
	AutoSizeGridButton(Controls.CloseButton,133,36,10,"H");
	-- the map size and type dropdowns don't make sense on a map import

    if (m_WorldBuilderImport) then
        Controls.CreateGame_MapType:SetDisabled(true);
        Controls.CreateGame_MapSize:SetDisabled(true);
        Controls.StartButton:LocalizeAndSetText("LOC_LOAD_TILED");
		MapConfiguration.SetScript("WBImport.lua");
    elseif(bWorldBuilder) then
		Controls.CreateGame_MapType:SetDisabled(false);
        Controls.CreateGame_MapSize:SetDisabled(false);
        Controls.StartButton:LocalizeAndSetText("LOC_SETUP_WORLDBUILDER_START");
	else
        Controls.CreateGame_MapType:SetDisabled(false);
        Controls.CreateGame_MapSize:SetDisabled(false);
        Controls.StartButton:LocalizeAndSetText("LOC_START_GAME");
    end
end

-- ===========================================================================
function OnHide()
	HideGameSetup();
	ReleasePlayerParameters();
	m_RulesetData = {};
end


-- ===========================================================================
-- Button Handlers
-- ===========================================================================

-- ===========================================================================
function OnAddAIButton()
	-- Search for an empty slot number and mark the slot as computer.
	-- Then dispatch the player count changed event.
	local iPlayer = 0;
	while(true) do
		local playerConfig = PlayerConfigurations[iPlayer];
		
		-- If we've reached the end of the line, exit.
		if(playerConfig == nil) then
			break;
		end

		-- Find a suitable slot to add the AI.
		if (playerConfig:GetSlotStatus() == SlotStatus.SS_CLOSED) then
			playerConfig:SetSlotStatus(SlotStatus.SS_COMPUTER);
			playerConfig:SetMajorCiv();

			GameSetup_PlayerCountChanged();
			break;
		end

		-- Increment the AI, this assumes that either player config will hit nil 
		-- or we'll reach a suitable slot.
		iPlayer = iPlayer + 1;
	end
end

-- ===========================================================================
function OnAdvancedSetup()
	local bWorldBuilder = GameConfiguration.IsWorldBuilderEditor();

	Controls.CreateGameWindow:SetHide(true);
	Controls.AdvancedOptionsWindow:SetHide(false);
	Controls.LoadConfig:SetHide(bWorldBuilder);
	Controls.SaveConfig:SetHide(bWorldBuilder);
	Controls.ButtonStack:CalculateSize();

	m_AdvancedMode = true;
	m_pendingFocus = nil;
	KeyNavEnterWindow(Locale.Lookup("LOC_SETUP_ADVANCED_OPTIONS"));
end

-- ===========================================================================
function OnMapSelect()
	local mapParameter:table = g_GameParameters and g_GameParameters.Parameters and g_GameParameters.Parameters["Map"] or nil;
	if mapParameter ~= nil and mapParameter.Value ~= nil then
		LuaEvents.MapSelect_SetCurrentMap( mapParameter.Value.Value );	-- so the picker opens on the current map
	end
	LuaEvents.MapSelect_PopulatedMaps( g_kMapData );
	Controls.MapSelectWindow:SetHide(false);
end

-- ===========================================================================
function OnDefaultButton()
	print("Reseting Setup Parameters");

	local bWorldBuilder = GameConfiguration.IsWorldBuilderEditor();
	GameConfiguration.SetToDefaults();
	GameConfiguration.SetWorldBuilderEditor(bWorldBuilder);
	
	-- In World Builder we want to default to Standard Rules.
	if(not bWorldBuilder) then
		-- Kludge:  SetToDefaults assigns the ruleset to be standard.
		-- Clear this value so that the setup parameters code can guess the best 
		-- default.
		GameConfiguration.SetValue("RULESET", nil);
	end

	GameConfiguration.RegenerateSeeds();
	return GameSetup_PlayerCountChanged();
end

-- ===========================================================================
function OnStartButton()
	-- Is WorldBuilder active?
	if (GameConfiguration.IsWorldBuilderEditor()) then
        if (m_WorldBuilderImport) then
            MapConfiguration.SetScript("WBImport.lua");
			local loadGameMenu = ContextPtr:LookUpControl( "/FrontEnd/MainMenu/LoadGameMenu" );
			UIManager:QueuePopup(loadGameMenu, PopupPriority.Current);	
		else
			UI.SetWorldRenderView( WorldRenderView.VIEW_2D );
			UI.PlaySound("Set_View_2D");
			Events.SetGameEntryMethod("Create A Game - WorldBuilder");
			Network.HostGame(ServerType.SERVER_TYPE_NONE);
		end
    else
        local showCityStatesWarning:boolean = ShouldShowCityStatesWarning();
        local showLeaderPoolWarning:boolean = ShouldShowLeaderPoolWarning();
		if showCityStatesWarning then
			ShowCityStateWarning(showLeaderPoolWarning);
        elseif showLeaderPoolWarning then
            ShowLeaderPoolWarning();
        else
            HostGame();
		end
	end
end

-- ===========================================================================
function ShowCityStateWarning(showLeaderPoolWarningNext:boolean)
    if showLeaderPoolWarningNext then
        m_pWarningPopup:ShowOkCancelDialog(Locale.Lookup("LOC_CITY_STATE_PICKER_TOO_FEW_WARNING"), ShowLeaderPoolWarning);
    else
        m_pWarningPopup:ShowOkCancelDialog(Locale.Lookup("LOC_CITY_STATE_PICKER_TOO_FEW_WARNING"), HostGame);
    end
end

-- ===========================================================================
function ShowLeaderPoolWarning()
    m_pWarningPopup:ShowOkCancelDialog(Locale.Lookup("LOC_LEADER_POOL_TOO_FEW_WARNING"), HostGame);
end

-- ===========================================================================
function HostGame()
	Events.SetGameEntryMethod("Create a Game");
	-- Start a normal game
	UI.PlaySound("Set_View_3D");
	Network.HostGame(ServerType.SERVER_TYPE_NONE);
end

-- ===========================================================================
function ShouldShowCityStatesWarning()
	local kParameters:table = g_GameParameters["Parameters"];

    -- No City-States for this game so don't worry about it
	if kParameters["CityStates"] == nil then
		return false;
	end

	local cityStateSlots:number = kParameters["CityStateCount"].Value;
	local totalCityStates:number = #kParameters["CityStates"].AllValues;
	local excludedCityStates:number = kParameters["CityStates"].Value ~= nil and #kParameters["CityStates"].Value or 0;

    -- Too few city-states selected in the city-state picker
	if (totalCityStates - excludedCityStates) < cityStateSlots then
		return true;
	end

	return false;
end

-- ===========================================================================
function ShouldShowLeaderPoolWarning()
    -- Determine how many players are trying to use leader pool 1 and 2
    local numPool1Players:number = 0;
    local numPool2Players:number = 0
    local player_ids = GameConfiguration.GetParticipatingPlayerIDs();
    for i, player_id in ipairs(player_ids) do	
	    local playerConfig = PlayerConfigurations[player_id];
	    if(playerConfig) then
            local pool_id:number = playerConfig:GetLeaderRandomPoolID();
			if pool_id == LeaderRandomPoolTypes.LEADER_RANDOM_POOL_1 then
				numPool1Players = numPool1Players + 1;
			elseif pool_id == LeaderRandomPoolTypes.LEADER_RANDOM_POOL_2 then
				numPool2Players = numPool2Players + 1;
	        end
        end
    end

    local kParameters:table = g_GameParameters["Parameters"];

    -- Check if leader pool 1 has enough leaders for all the players who selected it
    if numPool1Players > 0 then
        local kPool1Param:table = kParameters["LeaderPool1"];
        if kPool1Param then
            if kPool1Param.Value ~= nil then
                local numLeadersInPool:number = #kPool1Param.AllValues - #kPool1Param.Value;
                if numLeadersInPool ~= 0 and numPool1Players > numLeadersInPool then
                    return true;
                end
            end
        end
    end

    -- Check if leader pool 2 has enough leaders for all the players who selected it
    if numPool2Players > 0 then
        local kPool2Param:table = kParameters["LeaderPool2"];
        if kPool2Param then
            if kPool2Param.Value ~= nil then
                local numLeadersInPool:number = #kPool2Param.AllValues - #kPool2Param.Value;
                if numLeadersInPool ~= 0 and numPool2Players > numLeadersInPool then
                    return true;
                end
            end
        end
    end

    return false;
end

----------------------------------------------------------------    
function OnBackButton()
	if(m_AdvancedMode) then
		Controls.CreateGameWindow:SetHide(false);
		Controls.AdvancedOptionsWindow:SetHide(true);
		Controls.LoadConfig:SetHide(true);
		Controls.SaveConfig:SetHide(true);
		Controls.ButtonStack:CalculateSize();
		
		UpdateCivLeaderToolTip();					-- Need to make sure we update our placard/flyout card if we make a change in advanced setup and then come back
		m_AdvancedMode = false;
		-- Back in the basic window: announce it and focus the Advanced Setup button we came from.
		m_pendingFocus = nil;
		m_keyNavFocus = Controls.AdvancedSetupButton;
		OutputMessageToScreenReader(Controls.WindowTitle:GetText(), true);
		OutputMessageToScreenReader(Controls.AdvancedSetupButton:GetText(), true);
		m_pendingMouseMove = { control = Controls.AdvancedSetupButton, frames = 3 };
	else
		LuaEvents.MapSelect_ClearMapData();
		UIManager:DequeuePopup( MapSelectWindow );
		UIManager:DequeuePopup( ContextPtr );
		Controls.NoGameModesContainer:SetHide(false);
	end
end

-- ===========================================================================
--	Realize the animated flyouts with description, icons, and portraits for 
--  the currently hovered game mode toggle.
-- ===========================================================================
function OnGameModeMouseEnter(kGameModeData : table)
	m_gameModeToolTipHeaderIM:ResetInstances();
	m_gameModeToolTipHeaderIconIM:ResetInstances();
	if(Controls.GameModeToolTipSlide:IsReversing())then
		Controls.GameModeSlide:Reverse();
		Controls.GameModeAlpha:Reverse();
		Controls.GameModeToolTipSlide:Reverse();
		Controls.GameModeToolTipAlpha:Reverse();
	else
		Controls.GameModeSlide:Play();
		Controls.GameModeAlpha:Play();
		Controls.GameModeToolTipSlide:Play();
		Controls.GameModeToolTipAlpha:Play();
	end
	local gameModeHeader : table = m_gameModeToolTipHeaderIM:GetInstance();
	gameModeHeader.Header:SetText(Locale.Lookup(kGameModeData.RawName));

	local gameModeDescription : table = m_gameModeToolTipHeaderIconIM:GetInstance();
	gameModeDescription.Description:SetText(kGameModeData.Description);
	gameModeDescription.Header:SetHide(true);

	local gameModeInfo : table = GetGameModeInfo(kGameModeData.ConfigurationId);
	if(gameModeInfo ~= nil)then
		gameModeDescription.Icon:SetIcon(gameModeInfo.Icon);

		if(gameModeInfo.UnitIcon)then
			local gameModeUnitDescription : table = m_gameModeToolTipHeaderIconIM:GetInstance();
			gameModeUnitDescription.Description:SetText(Locale.Lookup(gameModeInfo.UnitDescription));
			gameModeUnitDescription.Icon:SetIcon(gameModeInfo.UnitIcon);
			gameModeUnitDescription.Header:SetText(Locale.ToUpper(gameModeInfo.UnitName));
		end
		if(gameModeInfo.Portrait)then
			Controls.GameModeImage:SetTexture(gameModeInfo.Portrait);
		end
		if(gameModeInfo.Background)then
			Controls.GameModeBG:SetTexture(gameModeInfo.Background);
		end
	end
end

function OnGameModeMouseExit(kGameModeData : table)
	if(not Controls.GameModeToolTipSlide:IsReversing())then
		Controls.GameModeSlide:Reverse();
		Controls.GameModeAlpha:Reverse();
		Controls.GameModeToolTipSlide:Reverse();
		Controls.GameModeToolTipAlpha:Reverse();
	else
		Controls.GameModeSlide:Play();
		Controls.GameModeAlpha:Play();
		Controls.GameModeToolTipSlide:Play();
		Controls.GameModeToolTipAlpha:Play();
	end
end

-- ===========================================================================
function OnLoadConfig()

	local loadGameMenu = ContextPtr:LookUpControl( "/FrontEnd/MainMenu/LoadGameMenu" );
	local kParameters = {
		FileType = SaveFileTypes.GAME_CONFIGURATION
	};

	UIManager:QueuePopup(loadGameMenu, PopupPriority.Current, kParameters);
end

-- ===========================================================================
function OnSaveConfig()

	local saveGameMenu = ContextPtr:LookUpControl( "/FrontEnd/MainMenu/SaveGameMenu" );
	local kParameters = {
		FileType = SaveFileTypes.GAME_CONFIGURATION
	};
    
	UIManager:QueuePopup(saveGameMenu, PopupPriority.Current, kParameters);	
end

----------------------------------------------------------------    
-- ===========================================================================
--	Handle Window Sizing
-- ===========================================================================

function Resize()
	local screenX, screenY:number = UIManager:GetScreenSizeVal();
	if(screenY >= MIN_SCREEN_Y + (Controls.LogoContainer:GetSizeY() + Controls.LogoContainer:GetOffsetY() * 2)) then
		Controls.MainWindow:SetSizeY(screenY - (Controls.LogoContainer:GetSizeY() + Controls.LogoContainer:GetOffsetY() * 2));
		Controls.CreateGameWindow:SetSizeY(SCREEN_OFFSET_Y + Controls.MainWindow:GetSizeY() - (Controls.ButtonStack:GetSizeY() + Controls.LogoContainer:GetSizeY()));
		Controls.AdvancedOptionsWindow:SetSizeY(SCREEN_OFFSET_Y + Controls.MainWindow:GetSizeY() - (Controls.ButtonStack:GetSizeY() + Controls.LogoContainer:GetSizeY()));
	else
		Controls.MainWindow:SetSizeY(screenY);
		Controls.CreateGameWindow:SetSizeY(MIN_SCREEN_OFFSET_Y + Controls.MainWindow:GetSizeY() - (Controls.ButtonStack:GetSizeY()));
		Controls.AdvancedOptionsWindow:SetSizeY(MIN_SCREEN_OFFSET_Y + Controls.MainWindow:GetSizeY() - (Controls.ButtonStack:GetSizeY()));
	end

	local iSidebarSize = Controls.CreateGameWindow:GetSizeY();
	if iSidebarSize > MAX_SIDEBAR_Y then
		iSidebarSize = MAX_SIDEBAR_Y;
	end
	Controls.BasicPlacardContainer:SetSizeY(iSidebarSize);
	Controls.BasicTooltipContainer:SetSizeY(iSidebarSize);
	Controls.GameModePlacardContainer:SetSizeY(iSidebarSize);
	Controls.GameModeTooltipContainer:SetSizeY(iSidebarSize);
end

-- ===========================================================================
function OnUpdateUI( type:number, tag:string, iData1:number, iData2:number, strData1:string )   
  if type == SystemUpdateUI.ScreenResize then
    Resize();
  end
end

-- ===========================================================================
function OnBeforeMultiplayerInviteProcessing()
	-- We're about to process a game invite.  Get off the popup stack before we accidentally break the invite!
	UIManager:DequeuePopup( ContextPtr );
end

-- ===========================================================================
function OnShutdown()
	Events.FinishedGameplayContentConfigure.Remove(OnFinishedGameplayContentConfigure);
	Events.SystemUpdateUI.Remove( OnUpdateUI );
	Events.BeforeMultiplayerInviteProcessing.Remove( OnBeforeMultiplayerInviteProcessing );

	LuaEvents.MapSelect_SetMapByValue.Remove( OnSetMapByValue );
	LuaEvents.MultiSelectWindow_SetParameterValues.Remove(OnSetParameterValues);
	LuaEvents.CityStatePicker_SetParameterValues.Remove(OnSetParameterValues);
    LuaEvents.CityStatePicker_SetParameterValue.Remove(OnSetParameterValue);
	LuaEvents.LeaderPicker_SetParameterValues.Remove(OnSetParameterValues);
end

-- ===========================================================================
--
-- ===========================================================================
function Initialize()

	ContextPtr:SetShutdown( OnShutdown );
	ContextPtr:SetInputHandler( OnInputHandler, true );
	ContextPtr:SetShowHandler( OnShow );
	ContextPtr:SetUpdate( OnKeyNavUpdate );
	ContextPtr:SetHideHandler( OnHide );

	Controls.AddAIButton:RegisterCallback( Mouse.eLClick, OnAddAIButton );
	Controls.AddAIButton:RegisterCallback( Mouse.eMouseEnter, function() UI.PlaySound("Main_Menu_Mouse_Over"); end);
	Controls.AdvancedSetupButton:RegisterCallback( Mouse.eLClick, OnAdvancedSetup );
	Controls.AdvancedSetupButton:RegisterCallback( Mouse.eMouseEnter, function() UI.PlaySound("Main_Menu_Mouse_Over"); end);
	Controls.DefaultButton:RegisterCallback( Mouse.eLClick, OnDefaultButton);
	Controls.DefaultButton:RegisterCallback( Mouse.eMouseEnter, function() UI.PlaySound("Main_Menu_Mouse_Over"); end);
	Controls.StartButton:RegisterCallback( Mouse.eLClick, OnStartButton );
	Controls.StartButton:RegisterCallback( Mouse.eMouseEnter, function() UI.PlaySound("Main_Menu_Mouse_Over"); end);
	Controls.CloseButton:RegisterCallback( Mouse.eLClick, OnBackButton );
	Controls.CloseButton:RegisterCallback( Mouse.eMouseEnter, function() UI.PlaySound("Main_Menu_Mouse_Over"); end);
	Controls.LoadConfig:RegisterCallback( Mouse.eLClick, OnLoadConfig );
	Controls.LoadConfig:RegisterCallback( Mouse.eMouseEnter, function() UI.PlaySound("Main_Menu_Mouse_Over"); end);
	Controls.SaveConfig:RegisterCallback( Mouse.eLClick, OnSaveConfig );
	Controls.SaveConfig:RegisterCallback( Mouse.eMouseEnter, function() UI.PlaySound("Main_Menu_Mouse_Over"); end);
	Controls.MapSelectButton:RegisterCallback( Mouse.eLClick, OnMapSelect );
	Controls.MapSelectButton:RegisterCallback( Mouse.eMouseEnter, function() UI.PlaySound("Main_Menu_Mouse_Over"); end);
	Controls.ConflictConfirmButton:RegisterCallback( Mouse.eLClick, function() Controls.ConflictPopup:SetHide(true); end);
	Controls.ConflictConfirmButton:RegisterCallback( Mouse.eMouseEnter, function() UI.PlaySound("Main_Menu_Mouse_Over"); end);
	
	Events.FinishedGameplayContentConfigure.Add(OnFinishedGameplayContentConfigure);
	Events.SystemUpdateUI.Add( OnUpdateUI );
	Events.BeforeMultiplayerInviteProcessing.Add( OnBeforeMultiplayerInviteProcessing );

	LuaEvents.MapSelect_SetMapByValue.Add( OnSetMapByValue );
	LuaEvents.MultiSelectWindow_SetParameterValues.Add(OnSetParameterValues);
	LuaEvents.CityStatePicker_SetParameterValues.Add(OnSetParameterValues);
    LuaEvents.CityStatePicker_SetParameterValue.Add(OnSetParameterValue);
	LuaEvents.LeaderPicker_SetParameterValues.Add(OnSetParameterValues);

	Resize();
end
Initialize();