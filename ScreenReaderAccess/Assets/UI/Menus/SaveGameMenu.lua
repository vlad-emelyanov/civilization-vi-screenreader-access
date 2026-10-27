include( "InstanceManager" );
include( "SupportFunctions" );

-- Shared code between the LoadGameMenu and the SaveGameMenu
include( "LoadSaveMenu_Shared" );

-- Screen reader / keyboard navigation (SRA mod change)
include( "SRListen" );
include( "KeyboardNavigation" );
include( "KeyNavEditBox" );
include( "ScreenReader" );

local RELOAD_CACHE_ID: string = "SaveGameMenu";		-- hotloading
local MIN_SCREEN_Y   : number = 768;
g_IsDeletingFile = false;

-- SRA: keyboard navigation state
local m_focus:table = nil;			-- { ref = "name" | <file table> | control id string }
local m_pending:table = nil;		-- announcement/focus to do when the next file query completes
local m_focusWhenBuilt:boolean = false;
local m_moveDelay:number = 0;
local m_moveTarget = nil;
local m_savePending:boolean = false;	-- a save was requested from this screen and SaveComplete is not announced yet

local function KeyNavResetState()
	m_focus = nil;
	m_pending = nil;
	m_focusWhenBuilt = false;
	m_moveTarget = nil;
	m_moveDelay = 0;
end

-- Speaks the overwrite / delete confirmation (the game shows it in the DeleteConfirm box, not in a popup).
local function SpeakConfirm()
	local name:string = "";
	if g_iSelectedFileEntry ~= -1 and g_FileList ~= nil and g_FileList[g_iSelectedFileEntry] ~= nil then
		name = GetDisplayName(g_FileList[g_iSelectedFileEntry])..". ";
	end
	OutputMessageToScreenReader(name..(Controls.Message:GetText() or "")..". " .. SRKey( "Enter" ) .. " for yes, " .. SRKey( "Escape" ) .. " for no.", false);
end

----------------------------------------------------------------        
----------------------------------------------------------------        
function OnBack()
    UIManager:DequeuePopup( ContextPtr );
end

----------------------------------------------------------------        
----------------------------------------------------------------
function OnActionButton()
	if (g_iSelectedFileEntry == -1) then
		local fileName = Controls.FileName:GetText();
		for i, v in ipairs(g_FileList) do
			local displayName = GetDisplayName(v); 
			if(Locale.Length(displayName) > 0) then
				if(Locale.ToUpper(fileName) == Locale.ToUpper(displayName)) then
					SetSelected(i);
					break;
				end
			end
		end
	end
	
	if(g_iSelectedFileEntry ~= -1) then
		g_IsDeletingFile = false;

		-- A file is selected, if it is a directory, go into it, else confirm overwrite.
		local selectedFile = g_FileList[ g_iSelectedFileEntry ];
		if selectedFile ~= nil then
			if selectedFile.IsDirectory then
				-- Open the directory
				ChangeDirectoryTo(selectedFile.Path);
				return;
			else
				Controls.DeleteHeader:SetText(Locale.ToUpper( "LOC_CONFIRM_TITLE_TXT" ));
				Controls.Message:LocalizeAndSetText( "LOC_OVERWRITE_TXT" );
				Controls.DeleteConfirm:SetHide(false);
				SpeakConfirm();
				return;
			end
		end

	else
		local gameFile = {};
		gameFile.Name = Controls.FileName:GetText();
		if(g_ShowCloudSaves) then
			gameFile.Location = UI.GetDefaultCloudSaveLocation();
		else
			gameFile.Location = SaveLocations.LOCAL_STORAGE;
			-- If it is a WorldBuilder map, allow for a specific path.
			if g_GameType == SaveTypes.WORLDBUILDER_MAP then
				gameFile.Path = g_CurrentDirectoryPath .. "/" .. gameFile.Name ;
			end
		end
		gameFile.Type = g_GameType;
		gameFile.FileType = g_FileType;
		UIManager:SetUICursor( 1 );
		m_savePending = true;
		OutputMessageToScreenReader("Saving...", true);
		Network.SaveGame(gameFile);
		UIManager:SetUICursor( 0 );
		UI.PlaySound("Confirm_Bed_Positive");
	end
	
	Controls.FileName:ClearString();
	SetupFileList();
	OnBack();
end
 

----------------------------------------------------------------        
function OnFileNameChange( fileNameEntry )
	
	if( g_iSelectedFileEntry ~= -1 ) then
		local kSelectedFile = g_FileList[ g_iSelectedFileEntry ];
		local displayName = GetDisplayName(kSelectedFile); 
		if (fileNameEntry:GetText() ~= displayName) then
			DismissCurrentSelected();
		end
	end
	
	local fileName = "";
	if(fileNameEntry:GetText() ~= nil) then
		fileName = fileNameEntry:GetText();
	end

	g_FilenameIsValid = ValidateFileName(fileName);

	UpdateActionButtonState();
	Controls.Delete:SetHide(true); 
	
end

----------------------------------------------------------------        
----------------------------------------------------------------
function OnCloudCheck( )
	local bWantShowCloudSaves = not g_ShowCloudSaves;

	if (bWantShowCloudSaves) then
		-- Make sure we can switch to it.
		if (not CanShowCloudSaves()) then
			return;
		end
	end

	g_ShowCloudSaves = bWantShowCloudSaves;
	Controls.CloudCheck:SetSelected(g_ShowCloudSaves);
    SetDontUpdateFileName(true);
	SetupDirectoryBrowsePulldown();
	SetupFileList();
	UpdateActionButtonState();
    SetDontUpdateFileName(false);
end


---------------------------------------------------------------- 
-- Show/Hide Handlers
---------------------------------------------------------------- 
function OnShow()

	g_ShowCloudSaves = false;
	g_ShowAutoSaves = false;

	LoadSaveMenu_OnShow();

	g_MenuType = SAVE_GAME;
	UpdateGameType();
	Controls.Delete:SetHide( true );
	Controls.ActionButton:SetDisabled( true );
	Controls.ActionButton:SetToolTipString( nil );

	InitializeDirectoryBrowsing();
	RefreshSortPulldown();
	SetupDirectoryBrowsePulldown();
	SetupFileList();
		
	Controls.CloudCheck:SetSelected(false);

	g_FilenameIsValid = ValidateFileName( Controls.FileName:GetText() );

	UpdateActionButtonState();

	local cloudServicesEnabled,cloudServicesResult = UI.AreCloudSavesEnabled("SAVE");
	local cloudEnabled = UI.AreCloudSavesEnabled() and not GameConfiguration.IsAnyMultiplayer() and g_FileType ~= SaveFileTypes.GAME_CONFIGURATION and g_GameType ~= SaveTypes.WORLDBUILDER_MAP;
	Controls.CloudCheck:SetHide(false);
	Controls.CloudCheck:SetEnabled(cloudEnabled);

    local isNew = Options.GetAppOption("Misc", "UserSawCloudNew");
	Controls.CheckNewIndicator:SetHide(true);
	Controls.DummyNewIndicator:SetHide(true);

	if cloudEnabled == false then
		if cloudServicesResult ~= nil then
			if cloudServicesResult == DB.MakeHash("REQUIRES_LINKED_ACCOUNT") then
				Controls.CloudCheck:LocalizeAndSetToolTip("LOC_CLOUD_SAVES_REQUIRE_LINKED_ACCOUNT");
			else
				Controls.CloudCheck:LocalizeAndSetToolTip("LOC_CLOUD_SAVES_SERVICE_NOT_CONNECTED");
			end
		end
        if (isNew == 0) then
            Controls.CheckNewIndicator:SetHide(false);
        end

		if g_GameType == SaveTypes.WORLDBUILDER_MAP or g_FileType == SaveFileTypes.GAME_CONFIGURATION then
			Controls.CloudCheck:SetHide(true);
		else
			Controls.CloudCheck:SetHide(false);
		end
	else
		if UI.Is2KCloudAvailable() then
			Controls.CloudCheck:SetToolTipString(Locale.Lookup("LOC_2K_CLOUD_SAVES_HELP"));
			Controls.CloudCheck:SetText(Locale.Lookup("LOC_2K_CLOUD"));
			Controls.CloudDummy:SetHide(true);
			if (isNew == 0) then
				Controls.CheckNewIndicator:SetHide(false);
			end
		else
			Controls.CloudDummy:SetHide(false);
			Controls.CloudDummy:SetDisabled(true);
			Controls.CloudDummy:SetToolTipString(Locale.Lookup("LOC_2K_CLOUD_SAVES_HELP"));
			Controls.CloudCheck:SetToolTipString(Locale.Lookup("LOC_STANDARD_CLOUD_SAVES_HELP"));
			if (isNew == 0) then
				Controls.DummyNewIndicator:SetHide(false);
			end
		end
	end

    if (isNew == 0) then
        Options.SetAppOption("Misc", "UserSawCloudNew", 1);
    end

	local cloudSavesVisible = Controls.CloudCheck:IsVisible();
	local sortByVisible = Controls.SortByPullDown:IsVisible();
	local directoryVisible = Controls.DirectoryPullDown:IsVisible();
    local dummyCloudVisible = Controls.CloudDummy:IsVisible();

	local count:number = 0;
	if(cloudSavesVisible) then
		count = count + 1;
	end
	if(sortByVisible) then
		count = count + 1;
	end
	if(directoryVisible) then
		count = count + 1;
	end
	if(dummyCloudVisible) then
		count = count + 1;
	end		
	
	-- SRA: no engine focus in the edit box (it would swallow every key); KeyNavEditBox takes it on Enter.
	pcall(function() Controls.FileName:DropFocus(); end);
	
	local decoSize:number = Controls.InspectorArea:GetSizeY();

	Controls.DecoContainer:SetSizeY(decoSize - (count * 25) - count);	

	if g_GameType == SaveTypes.WORLDBUILDER_MAP then
		Controls.GameDetailIconsArea:SetHide(true);
	else
		Controls.GameDetailIconsArea:SetHide(false);
	end

	-- SRA: opening announcement, focus on the name field
	KeyNavEditBox_Cancel();
	KeyNavResetState();
	m_savePending = false;
	m_focus = { ref = "name" };
	m_pending = { opening = true };
	OutputMessageToScreenReader(Controls.WindowHeader:GetText()..". Name: "..(Controls.FileName:GetText() or "")..", edit box. " .. SRKey( "Enter" ) .. " edits the name. " .. SRKey( "Down" ) .. ": existing saves. " .. SRKey( "Tab" ) .. ": jump between name, saves, options and buttons.", true);
end
----------------------------------------------------------------        
function OnHide()
	KeyNavEditBox_Cancel();
	KeyNavResetState();
	LoadSaveMenu_OnHide();
end

function OnDelete()
	g_IsDeletingFile = true;
	Controls.DeleteHeader:SetText( Locale.ToUpper(Locale.Lookup("LOC_CONFIRM_DELETE_TITLE_TXT")));
	Controls.Message:LocalizeAndSetText( "LOC_CONFIRM_TXT" );
	Controls.DeleteConfirm:SetHide(false);
	Controls.DeleteConfirmAlpha:SetToBeginning();
	Controls.DeleteConfirmAlpha:Play();
	Controls.DeleteConfirmSlide:SetToBeginning();
	Controls.DeleteConfirmSlide:Play();
	SpeakConfirm();
end    
----------------------------------------------------------------
function OnYes()
	Controls.DeleteConfirm:SetHide(true);

	if (g_iSelectedFileEntry ~= -1) then
		local kSelectedFile = g_FileList[ g_iSelectedFileEntry ];		
		if(g_IsDeletingFile) then
			UI.DeleteSavedGame( kSelectedFile );
		else
			UI.PlaySound("Confirm_Bed_Positive");

			if(g_ShowCloudSaves) then
				local gameFile = {};
				gameFile.Name = Controls.FileName:GetText();
				gameFile.Location = UI.GetDefaultCloudSaveLocation();
				gameFile.LocationIndex = g_iSelectedFileEntry;
				gameFile.Type = g_GameType;
				gameFile.FileType = g_FileType;
				UIManager:SetUICursor( 1 );
				Network.SaveGame(gameFile);
				UIManager:SetUICursor( 0 );
			else
				m_savePending = true;
				OutputMessageToScreenReader("Saving...", true);
				Network.SaveGame( kSelectedFile );
			end

			OnBack();
		end
	end
	
	SetupFileList();
	Controls.FileName:ClearString();
	Controls.ActionButton:SetDisabled(true);
end       
----------------------------------------------------------------
function OnNo( )
	Controls.DeleteConfirm:SetHide(true);
	Controls.MainGrid:SetHide(false);
end


-- ===========================================================================
--	Input Processing (SRA: keyboard navigation)
--	Up/Down: name field, saves, Cloud, Sort, Save, Delete, Back (wrapping). Tab: jump between the groups.
--	Enter on the name: edit it (type, Enter to finish). Enter on a save: overwrite (asks first). Enter on Save: save.
--	Space on a save: full details. Left/Right on Sort: change. Escape: back (or No on the overwrite/delete question).
-- ===========================================================================

-- Item list, rebuilt from the visible state at every key press.
local function KeyNavBuildItems()
	local items:table = {};
	table.insert(items, { ref = "name", group = 1, kind = "name", control = Controls.FileName });
	local files:table = g_FileList or {};
	local count:number = math.min(#files, g_FileEntryInstanceList and #g_FileEntryInstanceList or 0);
	for i = 1, count do
		table.insert(items, { ref = files[i], group = 2, kind = "file", index = i });
	end
	local function ctl(id, control, group, kind)
		if control ~= nil and not control:IsHidden() then
			table.insert(items, { ref = id, group = group, kind = kind, control = control });
		end
	end
	ctl("cloud",  Controls.CloudCheck, 3, "check");
	ctl("sort",   Controls.SortByPullDown, 3, "sort");
	ctl("action", Controls.ActionButton, 4, "button");
	ctl("delete", Controls.Delete, 4, "button");
	ctl("back",   Controls.BackButton, 4, "button");
	return items;
end

local function KeyNavItemText(item:table, items:table)
	if item.kind == "name" then
		local text:string = Controls.FileName:GetText();
		if text == nil or text == "" then text = "blank"; end
		return "Name: "..text..", edit box";
	elseif item.kind == "file" then
		local total:number = 0;
		for _, it in ipairs(items) do if it.kind == "file" then total = total + 1; end end
		return GetSaveSummaryText(item.ref, false)..", "..item.index.." of "..total;
	elseif item.ref == "cloud" then
		local t:string = Controls.CloudCheck:GetText()..": "..(g_ShowCloudSaves and "checked" or "unchecked");
		if Controls.CloudCheck:IsDisabled() then t = t..", unavailable"; end
		return t;
	elseif item.ref == "sort" then
		return GetSortOptionText()..", " .. SRKey( "Left or Right", "left stick left or right" ) .. " to change";
	else
		local t:string = item.control:GetText();
		if item.control:IsDisabled() then
			t = t..", unavailable";
			if item.ref == "action" and not g_FilenameIsValid then t = t..", the name is not valid"; end
		end
		return t;
	end
end

local function KeyNavFindFocused(items:table)
	if m_focus ~= nil then
		for i, item in ipairs(items) do
			if item.ref == m_focus.ref then return item, i; end
		end
	end
	return nil, 0;
end

local function KeyNavFocus(item:table, items:table, prefix:string, noInterrupt:boolean)
	m_focus = { ref = item.ref };
	if item.kind == "file" then
		-- Browsing must not copy the save's name into the Name field (Enter on the save does that, see KeyNavActivate).
		if g_iSelectedFileEntry ~= item.index then
			SetDontUpdateFileName(true);
			pcall(SetSelected, item.index);
			SetDontUpdateFileName(false);
		end
		EnsureCarouselSelectionVisible(item.index);
		local entry = g_FileEntryInstanceList[item.index];
		m_moveTarget = entry and entry.Button or nil;
	else
		m_moveTarget = item.control;
	end
	m_moveDelay = 6;	-- let the scroll/animations settle before the real mouse follows
	local text:string = KeyNavItemText(item, items);
	if prefix ~= nil then text = prefix..". "..text; end
	OutputMessageToScreenReader(text, noInterrupt == true);
end

local function KeyNavTick(deltaTime)
	KeyNavEditBox_Update(deltaTime);
	if m_focusWhenBuilt and g_FileList ~= nil and g_FileEntryInstanceList ~= nil and #g_FileEntryInstanceList >= #g_FileList then
		m_focusWhenBuilt = false;
		local items:table = KeyNavBuildItems();
		if #items > 0 then KeyNavFocus(items[1], items, nil, true); end
	end
	if m_moveTarget ~= nil then
		m_moveDelay = m_moveDelay - 1;
		if m_moveDelay <= 0 then
			local t = m_moveTarget;
			m_moveTarget = nil;
			KeyNavMoveMouse(t);
		end
	end
end

-- Called when a file query finishes: announce the count (and refocus after a delete).
local function KeyNavOnListReady()
	local pending:table = m_pending;
	m_pending = nil;
	if pending == nil then return; end
	local n:number = g_FileList and #g_FileList or 0;
	local text:string;
	if n == 0 then
		text = "No existing saves";
	elseif n == 1 then
		text = "1 existing save";
	else
		text = n.." existing saves";
	end
	if pending.prefix ~= nil then text = pending.prefix..". "..text; end
	OutputMessageToScreenReader(text, true);
	m_focusWhenBuilt = pending.focusFirst == true;
end

local function KeyNavMove(step:number, items:table)
	local item, idx = KeyNavFindFocused(items);
	if item == nil then
		idx = (step > 0) and 0 or (#items + 1);
	end
	idx = idx + step;
	if idx < 1 then idx = #items; end
	if idx > #items then idx = 1; end
	if items[idx] ~= nil then KeyNavFocus(items[idx], items); end
end

local function KeyNavTab(items:table)
	local item, idx = KeyNavFindFocused(items);
	local group:number = item and item.group or 0;
	local target:number = (group % 4) + 1;
	local names:table = { "Name", "Saves", "Options", "Buttons" };
	for attempt = 1, 4 do
		for _, it in ipairs(items) do
			if it.group == target then
				KeyNavFocus(it, items, names[target]);
				return;
			end
		end
		target = (target % 4) + 1;
	end
end

-- Enter on the name field: edit it with KeyNavEditBox (the game's own string-changed callback is put back afterwards).
local function KeyNavEditName()
	KeyNavEditBox_Begin(Controls.FileName, {
		label = "Name",
		onEnd = function(committed:boolean)
			pcall(function()
				Controls.FileName:RegisterStringChangedCallback( OnFileNameChange );
				OnFileNameChange( Controls.FileName );
			end);
		end,
	});
end

local function KeyNavActivate(item:table, items:table, key:number)
	if item.kind == "name" then
		KeyNavEditName();
	elseif item.kind == "file" then
		if g_iSelectedFileEntry ~= item.index then SetSelected(item.index); end
		-- Enter on a save is the explicit "use this name / overwrite" action
		pcall(function()
			local displayName:string = GetDisplayName(g_FileList[item.index]);
			if displayName ~= nil and Controls.FileName:GetText() ~= displayName then
				Controls.FileName:SetText(displayName);
				g_FilenameIsValid = ValidateFileName(displayName);
				UpdateActionButtonState();
			end
		end);
		if Controls.ActionButton:IsHidden() or Controls.ActionButton:IsDisabled() then
			OutputMessageToScreenReader("Cannot save over this one", false);
		else
			OnActionButton();
		end
	elseif item.kind == "check" then
		if item.control:IsDisabled() then
			OutputMessageToScreenReader(KeyNavItemText(item, items), false);
			return;
		end
		OnCloudCheck();
		m_pending = { prefix = nil };
		OutputMessageToScreenReader(KeyNavItemText(item, items), false);
	elseif item.kind == "sort" then
		if key == Keys.VK_RETURN then
			CycleSortOption(1);
			OutputMessageToScreenReader(KeyNavItemText(item, items), false);
		end
	elseif key == Keys.VK_RETURN then
		if item.ref == "action" then
			if Controls.ActionButton:IsDisabled() then
				OutputMessageToScreenReader(KeyNavItemText(item, items), false);
			else
				OnActionButton();
			end
		elseif item.ref == "delete" then
			OnDelete();
		else
			OnBack();
		end
	end
end

function KeyHandler( key:number )
	if KeyNavEditBox_IsEditing() then return true; end

	-- Overwrite / delete question (the DeleteConfirm box)
	if not Controls.DeleteConfirm:IsHidden() then
		if key == Keys.VK_ESCAPE then
			OnNo();
			local items:table = KeyNavBuildItems();
			local item:table = KeyNavFindFocused(items);
			local text:string = "Cancelled";
			if item ~= nil then text = text..". "..KeyNavItemText(item, items); end
			OutputMessageToScreenReader(text, false);
		elseif key == Keys.VK_RETURN then
			if g_IsDeletingFile then m_pending = { prefix = "Deleted", focusFirst = true }; end
			OnYes();
		end
		return true;
	end

	if key == Keys.VK_ESCAPE then
		OnBack();
		return true;
	end

	local items:table = KeyNavBuildItems();
	if #items == 0 then return true; end
	local item:table = KeyNavFindFocused(items);

	if key == Keys.VK_UP then
		KeyNavMove(-1, items);
	elseif key == Keys.VK_DOWN then
		KeyNavMove(1, items);
	elseif key == Keys.VK_TAB then
		KeyNavTab(items);
	elseif key == Keys.VK_HOME or key == Keys.VK_END then
		if item ~= nil and item.kind == "file" then
			local target:table = nil;
			for _, it in ipairs(items) do
				if it.kind == "file" then
					if target == nil or key == Keys.VK_END then target = it; end
				end
			end
			if target ~= nil then KeyNavFocus(target, items); end
		end
	elseif key == Keys.VK_LEFT or key == Keys.VK_RIGHT then
		if item ~= nil and item.kind == "sort" then
			CycleSortOption(key == Keys.VK_LEFT and -1 or 1);
			OutputMessageToScreenReader(KeyNavItemText(item, items), false);
		end
	elseif key == Keys.VK_RETURN or key == Keys.VK_SPACE then
		if item == nil then
			KeyNavMove(1, items);
		elseif key == Keys.VK_SPACE and item.kind == "file" then
			-- Space on a save reads its full details
			OutputMessageToScreenReader(GetSaveSummaryText(item.ref, true), false);
		elseif key == Keys.VK_SPACE and item.kind == "name" then
			OutputMessageToScreenReader(KeyNavItemText(item, items), false);
		elseif key == Keys.VK_RETURN or item.kind == "check" then
			KeyNavActivate(item, items, key);
		end
	end
	return true;
end

function OnInputHandler( pInputStruct:table )
	local handled = KeyNavEditBox_HandleInput(pInputStruct);
	if handled ~= nil then return handled; end
	local uiMsg = pInputStruct:GetMessageType();
	if uiMsg == KeyEvents.KeyUp then
		local ok, result = xpcall(function() return KeyHandler( pInputStruct:GetKey() ); end, KeyNavErrorHandler);
		if not ok then print("KEYNAV ERROR: "..tostring(result)); end
	end
	return true;
end

-- ===========================================================================
function OnInit(isReload:boolean)
	if isReload then
		LuaEvents.GameDebug_GetValues( RELOAD_CACHE_ID );
	end
end

-- ===========================================================================
function OnShutdown()
	SRUnlistenAll();
	-- Cache values for hotloading...
	LuaEvents.GameDebug_AddValue(RELOAD_CACHE_ID, "isHidden", ContextPtr:IsHidden());
end

-- ===========================================================================
function OnGameDebugReturn( context:string, contextTable:table )
	if context == RELOAD_CACHE_ID and contextTable["isHidden"] == false then
		UIManager:QueuePopup(ContextPtr, PopupPriority.Current);
	end	
end

-- ===========================================================================
--	Handle Window Sizing
-- ===========================================================================

function Resize()
	local screenX, screenY:number  = UIManager:GetScreenSizeVal();
	local hideLogo        :boolean = true;
	
	if(screenY >= MIN_SCREEN_Y + (Controls.LogoContainer:GetSizeY()+ Controls.LogoContainer:GetOffsetY() * 2)) then
		Controls.MainWindow:SetSizeY(screenY-(Controls.LogoContainer:GetSizeY() + Controls.LogoContainer:GetOffsetY() * 2));
		hideLogo = false;
	else
		Controls.MainWindow:SetSizeY(screenY);
	end
	
	Controls.LogoContainer:SetHide(hideLogo);
	Controls.DeleteConfirm:SetSizeVal(screenX,screenY);
	Controls.DeleteConfirm:ReprocessAnchoring();
end

-- ===========================================================================
function OnUpdateUI( type:number, tag:string, iData1:number, iData2:number, strData1:string )   
  if type == SystemUpdateUI.ScreenResize then
    Resize();
  end
end

-- ===========================================================================
function OnFileListQueryComplete()
	UpdateActionButtonState();
	KeyNavOnListReady();
end

-- SRA: Events.SaveComplete fires once the save we asked for is written (the top menu speaks its own for Quick Save).
function OnSaveComplete( ... )
	if m_savePending then
		m_savePending = false;
		OutputMessageToScreenReader("Game saved", true);
	end
end

-- ===========================================================================
function OnRefresh()
	SetupDirectoryBrowsePulldown();
	SetupFileList();
end

-- ===========================================================================
function OnSelectedFileStackSizeChanged()
	ResizeGameInfoScrollPanel();
end

-- ===========================================================================
function Initialize()
	ContextPtr:SetInitHandler(OnInit);
	ContextPtr:SetShutdown(OnShutdown);
	SRListen( LuaEvents.GameDebug_Return, OnGameDebugReturn );
	SetupSortPulldown();
	InitializeDirectoryBrowsing();
	Resize();

	SRListen( LuaEvents.FileListQueryComplete, OnFileListQueryComplete );
	SRListen( Events.SaveComplete, OnSaveComplete );

	Controls.ActionButton:RegisterCallback( Mouse.eLClick, OnActionButton );
	Controls.ActionButton:RegisterCallback( Mouse.eMouseEnter, function() UI.PlaySound("Main_Menu_Mouse_Over"); end);
	Controls.BackButton:RegisterCallback( Mouse.eLClick, OnBack );
	Controls.BackButton:RegisterCallback( Mouse.eMouseEnter, function() UI.PlaySound("Main_Menu_Mouse_Over"); end);
	Controls.CloudCheck:RegisterCallback( Mouse.eLClick, OnCloudCheck );
	Controls.FileName:RegisterStringChangedCallback( OnFileNameChange )
	Controls.No:RegisterCallback( Mouse.eLClick, OnNo );
	Controls.No:RegisterCallback( Mouse.eMouseEnter, function() UI.PlaySound("Main_Menu_Mouse_Over"); end);
	Controls.Yes:RegisterCallback( Mouse.eLClick, OnYes );
	Controls.Yes:RegisterCallback( Mouse.eMouseEnter, function() UI.PlaySound("Main_Menu_Mouse_Over"); end);
	Controls.Delete:RegisterCallback( Mouse.eLClick, OnDelete );
	Controls.Delete:RegisterCallback( Mouse.eMouseEnter, function() UI.PlaySound("Main_Menu_Mouse_Over"); end);
	Controls.SelectedFileStack:RegisterSizeChanged( OnSelectedFileStackSizeChanged );

	SRListen( Events.SystemUpdateUI, OnUpdateUI );

	-- UI Events
	ContextPtr:SetShowHandler( OnShow );
	ContextPtr:SetHideHandler( OnHide );
	ContextPtr:SetInputHandler( OnInputHandler, true );
	ContextPtr:SetRefreshHandler( OnRefresh );
	g_ExtraTick = KeyNavTick;

end
Initialize();

