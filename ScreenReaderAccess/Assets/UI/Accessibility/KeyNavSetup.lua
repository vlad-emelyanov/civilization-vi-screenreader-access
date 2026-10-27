-- KeyNavSetup: keyboard / screen reader navigation for game setup screens (Create Game, Advanced Setup, Host Game).
--------------------------------------------------------------
-- Shared by Frontend/AdvancedSetup.lua and Frontend/HostGame.lua. Needs these includes in the screen's file first:
--   include("KeyboardNavigation"); include("KeyNavEditBox"); include("ScreenReader");
-- and the global g_GameParameters of the setup logic (GameSetupLogic / PlayerSetupLogic).
--
-- 1. Item constructors. An item is { control, kind, key, getText(), step(delta), toggle(), activate(), getOptions(), apply(v),
--    focusSuffix, mouseTarget, panel, stack } where kind is "button", "pulldown", "popup", "slider", "checkbox" or "edit".
--      KeyNavSetup_ButtonItem(control, activate, message)
--      KeyNavSetup_PulldownItem(control, parameter, label)               pulldown backed by a setup parameter
--      KeyNavSetup_LeaderItem(control, playerParams, leaderParam, label) leader / civilization pulldown of a player
--      KeyNavSetup_MapItem(control, params, label, activate)             map button: Left/Right cycle, Enter activates
--      KeyNavSetup_ParameterItem(pid, parameter, c, label, opts)         any game parameter from its driver's control table c
--      KeyNavSetup_BuildParameterItems(params, panel, stack, opts)       all visible parameters, sorted by screen position
--    opts: { openMap = fn (opens the Map Select popup, for a "Map" parameter that is a button), section = false (no section prefix),
--            kinds = { slider = true, ... } (only items of these kinds) }
--    Helpers: KeyNavSetup_IsUsable, KeyNavSetup_SortByPosition, KeyNavSetup_SectionPrefix, KeyNavSetup_GetDriver,
--    KeyNavSetup_OpenPicker(pid, parameter), KeyNavSetup_GetOptions(parameter), KeyNavSetup_GetValueByOffset(parameter, offset).
--
-- 2. KeyNavSetup_NewController(cfg): focus tracking, announcements, scrolling, deferred mouse moves, the pulldown selection
--    mode (Enter on a pulldown), key dispatch and picker-popup handling. cfg:
--      buildItems()  -> list of items, built from the current visible state (called on every key press)
--      isActive()    -> true while the window this controller serves is what the player sees
--      popupOpen()   -> true while a picker / popup of the screen is open (the controller then ignores keys and re-announces
--                       the focused item when it closes)
--      onBack()      -> Escape
--      onPopupKey(key) (optional) -> called for a key while popupOpen(); return true/false to consume it, nil to ignore
--    Returned object: Focus(item, nointerrupt, prefix), Move(delta), FindFocused(), EnterWindow(title), SetFocus(key, mouseControl, frames),
--    QueueFocus(key, prefix), CancelSelection(), HandleKey(key), HandleInput(pInputStruct), Update(deltaTime).
--    Wire up: ContextPtr:SetInputHandler(function(p) return nav.HandleInput(p); end, true); ContextPtr:SetUpdate(nav.Update).

local function PulldownHint()
	return ", dropdown, " .. SRKey( "Left/Right" ) .. " or " .. SRKey( "Enter" ) .. " to change";
end

function KeyNavSetup_IsUsable( control:object )
	return control ~= nil and not control:IsHidden() and not control:IsDisabled();
end

-- Returns the previous/next valid (non-invalid) value of a parameter, without wrapping.
function KeyNavSetup_GetValueByOffset( parameter:table, offset:number )
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

-- Returns the list of selectable (non-invalid) values and the index of the current one.
function KeyNavSetup_GetOptions( parameter:table )
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

-- Order by on-screen position (rows first, then left to right); insertion sort so the result is deterministic.
function KeyNavSetup_SortByPosition( list:table )
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

-- A disabled button is still an item (so the player can find out why): it reads "<text>, disabled, <tooltip reason>" and
-- activating it only repeats that.
function KeyNavSetup_ButtonItem( control:object, activate, message:string )
	return {
		control = control, kind = "button", activate = activate, activateMessage = message,
		getText = function()
			local text:string = CleanTextForSpeech(control:GetText());
			if control:IsDisabled() then
				text = text..", disabled";
				local ok, tip = pcall(function() return control:GetToolTipString(); end);
				tip = ok and tip and CleanTextForSpeech(tip) or "";
				if tip ~= "" then text = text..", "..tip; end
			end
			return text;
		end,
	};
end

function KeyNavSetup_PulldownItem( control:object, parameter:table, label:string )
	return {
		control = control, kind = "pulldown", label = label, focusSuffix = PulldownHint(),
		getText = function()
			return label..": "..(parameter.Value and tostring(parameter.Value.Name) or "");
		end,
		getOptions = function() return KeyNavSetup_GetOptions(parameter); end,
		apply = function( v )
			g_GameParameters:SetParameterValue(parameter, v);
			Network.BroadcastGameConfig();
		end,
		step = function( delta )
			local v = KeyNavSetup_GetValueByOffset(parameter, delta);
			if v ~= nil then
				g_GameParameters:SetParameterValue(parameter, v);
				Network.BroadcastGameConfig();
			end
		end,
	};
end

-- Leader / civilization pulldown of a player; Enter opens the mod-side selection list.
function KeyNavSetup_LeaderItem( control:object, playerParams:table, leaderParam:table, label:string )
	local item:table = KeyNavSetup_PulldownItem(control, leaderParam, label);
	local function Apply( v )
		playerParams:SetParameterValue(leaderParam, v);
		local colorParameter = playerParams.Parameters["PlayerColorAlternate"];
		if colorParameter then
			playerParams:SetParameterValue(colorParameter, 0);
		end
	end
	item.apply = Apply;
	item.step = function( delta )
		local v = KeyNavSetup_GetValueByOffset(leaderParam, delta);
		if v ~= nil then Apply(v); end
	end;
	return item;
end

function KeyNavSetup_MapItem( control:object, params:table, label:string, activate )
	local parameter:table = params["Map"];
	return {
		control = control, kind = "popup", activate = activate,
		getText = function()
			local name:string = parameter.Value and parameter.Value.Name or control:GetText();
			return label..": "..tostring(name);
		end,
		step = function( delta )
			local v = KeyNavSetup_GetValueByOffset(parameter, delta);
			if v ~= nil then
				g_GameParameters:SetParameterValue(parameter, v);
				Network.BroadcastGameConfig();
			end
		end,
	};
end

-- Parameters of these groups are announced with their section name, e.g. "Victory Conditions, Science Victory: checked".
function KeyNavSetup_SectionPrefix( parameter:table )
	if parameter.GroupId == "Victories" then
		return Locale.Lookup("LOC_SETUP_VICTORY_CONDITIONS");
	elseif parameter.GroupId == "GameModes" then
		return Locale.Lookup("LOC_SETUP_GAME_MODES");
	end
	return nil;
end

-- The control(s) of a parameter are either one driver or an array { basicDriver, advancedDriver }: returns the last one.
function KeyNavSetup_GetDriver( control:table )
	if control == nil then return nil; end
	if control.Control ~= nil then return control; end
	local bestKey:number = nil;
	for k, v in pairs(control) do
		if type(k) == "number" and (bestKey == nil or k > bestKey) then bestKey = k; end
	end
	return bestKey and control[bestKey] or nil;
end

-- Opens the picker window that belongs to a parameter (same calls as the screen's own button drivers). Returns false if
-- the parameter has no picker. Needs Controls.CityStatePicker / LeaderPicker / MultiSelectWindow in the context.
function KeyNavSetup_OpenPicker( pid:string, parameter:table, openMap )
	if pid == "Map" and openMap ~= nil then
		openMap();
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

-- Same as the commit callback the setup logic registers on a string parameter's EditBox.
local function DefaultStringCommit( parameter:table )
	return function( text:string )
		local value = text;
		if parameter.Domain == "int" then
			value = tonumber(text);
		elseif parameter.Domain == "uint" then
			value = math.max(tonumber(text) or 0, 0);
		end
		g_GameParameters:SetParameterValue(parameter, value);
		Network.BroadcastGameConfig();
	end
end

local function BuildParameterItem( pid:string, parameter:table, c:table, label:string, opts:table )
	opts = opts or {};
	if c.OptionSlider ~= nil then
		if parameter.Value ~= nil and c.Root ~= nil and not c.Root:IsHidden() and not c.OptionSlider:IsHidden() and parameter.Values ~= nil then
			return {
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
		if parameter.Value ~= nil and KeyNavSetup_IsUsable(c.CheckBox) then
			return {
				control = c.CheckBox, kind = "checkbox",
				getText = function() return label..": "..(parameter.Value and "checked" or "unchecked"); end,
				toggle = function()
					g_GameParameters:SetParameterValue(parameter, not parameter.Value);
					Network.BroadcastGameConfig();
				end,
			};
		end
	elseif c.StringEdit ~= nil then
		local editRoot:object = c.StringRoot or c.Root or c.StringEdit;
		if not editRoot:IsHidden() and KeyNavSetup_IsUsable(c.StringEdit) then
			return {
				control = c.StringEdit, kind = "edit", focusSuffix = ", " .. SRKey( "Enter" ) .. " to edit",
				getText = function() return KeyNavEditBox_Describe(label, c.StringEdit); end,
				activate = function()
					KeyNavEditBox_Begin(c.StringEdit, {
						label = label, commit = c.StringCommit or DefaultStringCommit(parameter),
						numeric = (parameter.Domain == "int" or parameter.Domain == "uint"),
					});
				end,
			};
		end
	elseif c.PullDown ~= nil and c.Root ~= nil and parameter.Value ~= nil and parameter.Values ~= nil and not parameter.Array then
		if not c.Root:IsHidden() and KeyNavSetup_IsUsable(c.PullDown) then
			return KeyNavSetup_PulldownItem(c.PullDown, parameter, label);
		end
	elseif c.Button ~= nil and c.ButtonRoot ~= nil then
		if not c.ButtonRoot:IsHidden() and KeyNavSetup_IsUsable(c.Button) then
			if pid == "Map" and opts.openMap ~= nil then
				return KeyNavSetup_MapItem(c.Button, g_GameParameters.Parameters, label, opts.openMap);
			end
			return {
				control = c.Button, kind = "popup",
				getText = function() return label..": "..tostring(c.Button:GetText()); end,
				activate = function() if not KeyNavSetup_OpenPicker(pid, parameter, opts.openMap) then KeyNavLeftClick(); end end,
			};
		end
	end
	return nil;
end

-- Builds the item for one parameter from its driver's control table c (the instance of the slider / checkbox / edit box /
-- pulldown / button), or nil if it is not shown, not usable or of an unknown kind. opts.kinds (optional) limits the result
-- to those item kinds, e.g. { slider = true, checkbox = true, pulldown = true } for the basic Create Game window.
function KeyNavSetup_ParameterItem( pid:string, parameter:table, c:table, label:string, opts:table )
	local item:table = BuildParameterItem(pid, parameter, c, label, opts);
	if item ~= nil and opts ~= nil and opts.kinds ~= nil and not opts.kinds[item.kind] then return nil; end
	return item;
end

-- All shown parameters of g_GameParameters as items (key "param:<pid>"), sorted by screen position. panel / stack: the
-- scroll panel and the stack inside it that hold the parameter controls (used to scroll the focused item into view).
function KeyNavSetup_BuildParameterItems( params:table, panel:object, stack:object, opts:table )
	opts = opts or {};
	local list:table = {};
	if params ~= nil then
		for pid, parameter in pairs(params) do
			local driver:table = KeyNavSetup_GetDriver(g_GameParameters.Controls[pid]);
			local c:table = driver and driver.Control or nil;
			if type(c) == "table" and (parameter.Value ~= nil or c.Button ~= nil or c.StringEdit ~= nil) then
				local section:string = (opts.section ~= false) and KeyNavSetup_SectionPrefix(parameter) or nil;
				local label:string = section and (section..", "..tostring(parameter.Name)) or tostring(parameter.Name);
				local item:table = KeyNavSetup_ParameterItem(pid, parameter, c, label, opts);
				if item ~= nil then
					item.key = "param:"..pid;
					item.panel = panel;
					item.stack = stack;
					table.insert(list, item);
				end
			end
		end
	end
	KeyNavSetup_SortByPosition(list);
	return list;
end

-- ---------------------------------------------------------------------------
-- Controller
-- ---------------------------------------------------------------------------
function KeyNavSetup_NewController( cfg:table )
	local nav:table = {};
	local m_focus			:object = nil;		-- key of the item that has keyboard focus (item.key, defaults to item.control)
	local m_pendingMouseMove:table = nil;		-- { control, frames } move the mouse once the layout has settled
	local m_pendingFocus	:table = nil;		-- { key, prefix, frames, tries } focus an item once the UI has refreshed
	local m_selection		:table = nil;		-- selection mode: { item, options, index, originalIndex }
	local m_popupWasOpen	:boolean = false;

	local function PopupOpen()
		return cfg.popupOpen ~= nil and cfg.popupOpen();
	end

	local function IsActive()
		return not PopupOpen() and cfg.isActive();
	end

	local function BuildItems()
		local items:table = cfg.buildItems();
		for i, item in ipairs(items) do
			if item.key == nil then item.key = item.control; end
		end
		return items;
	end

	-- Announce an item, scroll its panel if needed, and move the mouse onto it.
	function nav.Focus( item:table, nointerrupt:boolean, prefix:string )
		if item == nil then return; end
		m_focus = item.key;
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

	local function FindIndex( items:table )
		for i, item in ipairs(items) do
			if item.key == m_focus then return i; end
		end
		return 0;
	end

	function nav.Move( delta:number )
		local items:table = BuildItems();
		if #items == 0 then return; end
		local current:number = FindIndex(items);
		local nextIndex:number;
		if current == 0 then
			nextIndex = (delta > 0) and 1 or #items;
		else
			nextIndex = current + delta;
			if nextIndex < 1 then nextIndex = #items; end
			if nextIndex > #items then nextIndex = 1; end
		end
		nav.Focus(items[nextIndex], false);
	end

	function nav.FindFocused()
		local items:table = BuildItems();
		local index:number = FindIndex(items);
		return index > 0 and items[index] or nil;
	end

	-- Announce the window and focus its first item.
	function nav.EnterWindow( title:string )
		local items:table = BuildItems();
		OutputMessageToScreenReader(title, true);
		nav.Focus(items[1], true);
	end

	-- Set the focused item by key (without announcing) and optionally queue a mouse move to a control. Drops a queued focus.
	function nav.SetFocus( key:object, mouseControl:object, frames:number )
		m_focus = key;
		m_pendingFocus = nil;
		if mouseControl ~= nil then
			m_pendingMouseMove = { control = mouseControl, frames = frames or 0 };
		end
	end

	-- Focus the item with this key once the UI has refreshed (e.g. after a player was added or removed).
	function nav.QueueFocus( key:object, prefix:string )
		m_pendingFocus = { key = key, prefix = prefix, frames = 6, tries = 0 };
	end

	function nav.CancelSelection()
		m_selection = nil;
	end

	-- The item whose selection list is open, or nil.
	function nav.SelectionItem()
		return m_selection and m_selection.item or nil;
	end

	-- True while the pulldown selection mode (Enter on a pulldown) is open.
	function nav.IsSelecting()
		return m_selection ~= nil;
	end

	-- -----------------------------------------------------------------------
	-- Selection mode (Enter on a pulldown): the mod lists the parameter's valid values itself instead of the engine's popup.
	-- -----------------------------------------------------------------------
	local function SelectionText()
		local v:table = m_selection.options[m_selection.index];
		return tostring(v.Name)..", "..tostring(m_selection.index).." of "..tostring(#m_selection.options);
	end

	local function OpenSelection( item:table )
		-- getOptions may return a third value, true: the current state is not one of the options (e.g. only "Swap" is offered),
		-- so there is no original option and Enter always applies the chosen one.
		local options:table, current:number, noOriginal:boolean = item.getOptions();
		if #options == 0 then return; end
		local label:string = item.label or "";
		m_selection = { item = item, options = options, index = current, originalIndex = (not noOriginal) and current or nil };
		OutputMessageToScreenReader(label..", "..SelectionText()..". " .. SRKey( "Up/Down" ) .. " to choose, " .. SRKey( "Enter" ) .. " to select, " .. SRKey( "Escape" ) .. " to cancel", false);
	end

	local function SelectionKey( key:number )
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
			OutputMessageToScreenReader(SelectionText(), false);
		elseif key == Keys.VK_RETURN then
			m_selection = nil;
			-- item.validate() (optional): false if what the list was opened for changed meanwhile (slot taken, parameters
			-- rebuilt ...). item.apply may return a message that is spoken before the item text.
			if sel.item.validate ~= nil and not sel.item.validate() then
				OutputMessageToScreenReader("Slot changed, cancelled", false);
				return true;
			end
			local message:string = nil;
			if sel.index ~= sel.originalIndex then
				message = sel.item.apply(sel.options[sel.index]);
			end
			local text:string = sel.item.getText();
			if type(message) == "string" then text = message..". "..text; end
			OutputMessageToScreenReader(text, false);
		elseif key == Keys.VK_ESCAPE then
			m_selection = nil;
			OutputMessageToScreenReader("Cancelled, "..sel.item.getText(), false);
		end
		return true;
	end

	-- -----------------------------------------------------------------------
	-- Keys
	-- -----------------------------------------------------------------------
	function nav.HandleKey( key:number )
		if KeyNavEditBox_IsEditing() then return true; end
		if m_selection ~= nil and not IsActive() then m_selection = nil; end
		if m_selection ~= nil then
			return SelectionKey(key);
		end
		if cfg.onPopupKey ~= nil and PopupOpen() then
			local handled = cfg.onPopupKey(key);
			if handled ~= nil then return handled; end
		end
		if key == Keys.VK_ESCAPE then
			if not PopupOpen() then
				cfg.onBack();
			end
			return true;
		end
		if not IsActive() then
			return true;
		end

		if key == Keys.VK_UP then
			nav.Move(-1);
		elseif key == Keys.VK_DOWN then
			nav.Move(1);
		elseif key == Keys.VK_LEFT or key == Keys.VK_RIGHT then
			local item:table = nav.FindFocused();
			if item ~= nil and item.step ~= nil then
				item.step(key == Keys.VK_LEFT and -1 or 1);
				OutputMessageToScreenReader(item.getText(), false);
			end
		elseif key == Keys.VK_RETURN or key == Keys.VK_SPACE then
			local item:table = nav.FindFocused();
			if item ~= nil then
				if key == Keys.VK_RETURN and item.getOptions ~= nil then
					OpenSelection(item);
				elseif item.kind == "checkbox" then
					item.toggle();
					OutputMessageToScreenReader(item.getText(), false);
				elseif key == Keys.VK_RETURN and item.kind == "button" and item.control ~= nil and item.control:IsDisabled() then
					OutputMessageToScreenReader(item.getText(), false);	-- disabled: only say why
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

	-- Use as (or from) the context's input handler (registered with SetInputHandler(fn, true): receives the input struct).
	function nav.HandleInput( pInputStruct:table )
		local editHandled = KeyNavEditBox_HandleInput(pInputStruct);
		if editHandled ~= nil then return editHandled; end
		if pInputStruct:GetMessageType() == KeyEvents.KeyUp then
			local ok, result = xpcall(function() return nav.HandleKey( pInputStruct:GetKey() ); end, KeyNavErrorHandler);
			if not ok then print("KEYNAV ERROR: "..tostring(result)); return true; end
			return result;
		end
		return true;
	end

	-- -----------------------------------------------------------------------
	-- Per-frame update
	-- -----------------------------------------------------------------------
	local function UpdateFocus()
		-- Focus an item once the UI has caught up with a change.
		if m_pendingFocus ~= nil then
			m_pendingFocus.frames = m_pendingFocus.frames - 1;
			if m_pendingFocus.frames <= 0 then
				local items:table = BuildItems();
				local found:table = nil;
				for i, item in ipairs(items) do
					if item.key == m_pendingFocus.key then found = item; end
				end
				if found ~= nil then
					nav.Focus(found, false, m_pendingFocus.prefix);
					m_pendingFocus = nil;
				elseif m_pendingFocus.tries >= 10 then
					nav.Focus(items[1], false, m_pendingFocus.prefix);
					m_pendingFocus = nil;
				else
					m_pendingFocus.tries = m_pendingFocus.tries + 1;
					m_pendingFocus.frames = 5;
				end
			end
		end

		-- When a popup (map select, pickers, ...) closes, re-announce the focused item and put the mouse back on it.
		local popupOpen:boolean = PopupOpen();
		if m_popupWasOpen and not popupOpen and m_pendingFocus == nil and m_focus ~= nil then
			local item:table = nav.FindFocused();
			if item ~= nil then
				nav.Focus(item, false);
			end
		end
		m_popupWasOpen = popupOpen;
	end

	function nav.Update( deltaTime:number )
		KeyNavEditBox_Update(deltaTime);
		local ok, err = pcall(UpdateFocus);
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

	return nav;
end
