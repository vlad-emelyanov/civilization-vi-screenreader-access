include( "InstanceManager" );
include( "SupportFunctions" );
include( "Civ6Common" );
include( "LoadSaveMenu_Shared" );	-- Shared code between the LoadGameMenu and the SaveGameMenu
include( "PopupDialog" );
include( "LocalPlayerActionSupport" );

include("KeyboardNavigation")
include("ScreenReader")


local RELOAD_CACHE_ID: string = "LoadGameMenu";		-- hotloading

local MIN_SCREEN_Y       :number = 768;
local SCREEN_OFFSET_Y    :number = 63;
local MIN_SCREEN_OFFSET_Y:number = -53;

-------------------------------------------------
-- Globals
-------------------------------------------------
local serverType : number = ServerType.SERVER_TYPE_NONE;
local m_thisLoadFile;
local m_QuickloadId;
local m_isActionButtonDisabled:boolean = false;	-- Action button state before yes/no prompt
g_IsDeletingFile = false;

g_QuickLoadQueryRequestID = nil;

-- Keyboard navigation state
local m_focus:table = nil;			-- { ref = <file table | control id string> }
local m_pending:table = nil;		-- announcement/focus to do when the next file query completes
local m_deletePopup:boolean = false;
local m_focusWhenBuilt:boolean = false;
local m_moveDelay:number = 0;
local m_moveTarget = nil;

local function KeyNavResetState()
	m_focus = nil;
	m_pending = nil;
	m_focusWhenBuilt = false;
	m_moveTarget = nil;
	m_moveDelay = 0;
	m_deletePopup = false;
end

----------------------------------------------------------------        
----------------------------------------------------------------        
function OnLoadNo()
	m_kPopupDialog:Close();
end

function OnLoadConfirmModCompatibility()

	-- Disallow loading challenge games in multiplayers	
	if(serverType ~= ServerType.SERVER_TYPE_NONE and 
	   not Challenges.IsNullChallengeUuid(m_thisLoadFile.GameChallengeUuid)) then
		m_kPopupDialog:AddText(Locale.Lookup("LOC_CHALLENGE_MP_SAVEGAME_START_ERROR"));
		m_kPopupDialog:AddTitle(Locale.ToUpper(Locale.Lookup("LOC_GAME_START_ERROR_TITLE")));
		m_kPopupDialog:AddButton(Locale.Lookup("LOC_OK_BUTTON"), OnLoadNo);
		m_kPopupDialog:Open();

		return;
	end


	if(Modding.ShouldShowCompatibilityWarnings() and m_thisLoadFile) then

		local installedMods = Modding.GetInstalledMods();
		local enabledModsByHandle = {};

		for i,v in ipairs(installedMods) do
			enabledModsByHandle[v.Handle] = v.Enabled;
		end

		local incompatibleMods = {};
		local mods = m_thisLoadFile.RequiredMods or {};
		for i,v in ipairs(mods) do
			local mod = Modding.GetModHandle(v.Id);
			local isCompatible = Modding.IsModCompatible(mod);
			if(not isCompatible and enabledModsByHandle[mod] == false) then
				table.insert(incompatibleMods, mod);
			end
		end

		if(#incompatibleMods > 0) then

			local whitelistMods = false;

			function OnYes()
				if(whitelistMods) then
					for i,v in ipairs(incompatibleMods) do
						Modding.SetIgnoreCompatibilityWarnings(v, true);
					end
				end

				OnLoadYes();
			end
			
			m_kPopupDialog:AddText(Locale.Lookup("LOC_MODS_ENABLE_WARNING_NOT_COMPATIBLE_MANY"));
			m_kPopupDialog:AddTitle(Locale.ToUpper(Locale.Lookup("LOC_CONFIRM_TITLE_LOAD_TXT")));
			m_kPopupDialog:AddButton(Locale.Lookup("LOC_YES_BUTTON"), OnYes, nil, nil, "PopupButtonInstanceGreen"); 
			m_kPopupDialog:AddButton(Locale.Lookup("LOC_NO_BUTTON"), OnLoadNo);
			m_kPopupDialog:AddCheckBox(Locale.Lookup("LOC_MODS_WARNING_WHITELIST_MANY"), false, function(checked) whitelistMods = checked; end);
			m_kPopupDialog:Open();
		else
			OnLoadYes();
		end

	else
		OnLoadYes();
	end
	
end
----------------------------------------------------------------        
----------------------------------------------------------------        
function OnLoadYes()
	UITutorialManager:EnableOverlay( false );	
	UITutorialManager:HideAll();
	m_kPopupDialog:Close();

	-- Leave your current game if this is not a game configuration load.
	-- Game Configuration should keep the game in the current state (hostgame/advanced setup).
	if(g_FileType ~= SaveFileTypes.GAME_CONFIGURATION) then
		print("LoadGameMenu::OnLoadYes() leaving the network session.");
		Network.LeaveGame();
	end

    Network.LoadGame(m_thisLoadFile, serverType);
    Controls.ActionButton:SetDisabled( true );

    -- Don't DequeuePopup here.  
    -- In singleplayer, the entire lua context gets blasted once we transition to the LoadGameViewState.
    -- In multiplayer, the join room screen will send a JoiningRoom_Showing() to let us know it's safe to DequeuePopup.  See OnJoiningRoom_Showing().
end

----------------------------------------------------------------        
----------------------------------------------------------------        
function OnActionButton()
	if(not Controls.ActionButton:IsHidden() and not Controls.ActionButton:IsDisabled()) then
		UIManager:SetUICursor( 1 );
		m_thisLoadFile = g_FileList[ g_iSelectedFileEntry ];

		if (m_thisLoadFile) then
			if m_thisLoadFile.IsDirectory then
				-- Open the directory
				ChangeDirectoryTo(m_thisLoadFile.Path);
			else
    			local isInGame = false;
    			if(GameConfiguration ~= nil) then
    				isInGame = GameConfiguration.GetGameState() ~= GameStateTypes.GAMESTATE_PREGAME;
    			end

				if isInGame then
		   			if ( not m_kPopupDialog:IsOpen()) then
						m_kPopupDialog:AddText(Locale.Lookup("LOC_CONFIRM_LOAD_TXT"));
						m_kPopupDialog:AddTitle(Locale.ToUpper(Locale.Lookup("LOC_CONFIRM_TITLE_LOAD_TXT")));
						m_kPopupDialog:AddButton(Locale.Lookup("LOC_YES_BUTTON"), OnLoadConfirmModCompatibility, nil, nil, "PopupButtonInstanceGreen"); 
						m_kPopupDialog:AddButton(Locale.Lookup("LOC_NO_BUTTON"), OnLoadNo);
						m_kPopupDialog:Open();
					end
				else
					if (g_GameType ~= SaveTypes.TILED_MAP) then
						OnLoadConfirmModCompatibility();
					end
    			end

				if (g_GameType == SaveTypes.TILED_MAP) then
					MapConfiguration.SetImportFilename(m_thisLoadFile.Path);
					UI.SetWorldRenderView( WorldRenderView.VIEW_2D );
					Events.SetGameEntryMethod("Load Saved Game");
					Network.HostGame(ServerType.SERVER_TYPE_NONE);
				end
			end
        end
	end	
end

----------------------------------------------------------------        
----------------------------------------------------------------        
function OnBack()
	if m_kPopupDialog:IsOpen() then
		UI.DataError("Popup confirmation was open when closing the load game menu; it will be forced closed but it shouldn't be possible to close the load screen while this prompt is up.");
		m_kPopupDialog:Close();
	end

    UIManager:DequeuePopup( ContextPtr );
end

---------------------------------------------------------------- 
-- Show/Hide Handlers
---------------------------------------------------------------- 
function OnShow()
	LoadSaveMenu_OnShow();

	g_MenuType = LOAD_GAME;
	UpdateGameType();
	Controls.ActionButton:SetHide( false );
	Controls.ActionButton:SetDisabled( false );
	Controls.ActionButton:SetToolTipString(nil);
	m_isActionButtonDisabled = false;

	g_ShowCloudSaves = false;
	g_ShowAutoSaves = false;

	Controls.AutoCheck:SetSelected(false);
	Controls.CloudCheck:SetSelected(false);

	local cloudEnabled = UI.AreCloudSavesEnabled() and not GameConfiguration.IsAnyMultiplayer() and g_FileType ~= SaveFileTypes.GAME_CONFIGURATION and g_GameType ~= SaveTypes.WORLDBUILDER_MAP and g_GameType ~= SaveTypes.TILED_MAP;
	local cloudServicesEnabled,cloudServicesResult = UI.AreCloudSavesEnabled("LOAD");

	-- we want to show this in all cases
	Controls.CloudCheck:SetHide(false);
	
	local isNew = Options.GetAppOption("Misc", "UserSawCloudNew");
	Controls.CheckNewIndicator:SetHide(true);
	Controls.DummyNewIndicator:SetHide(true);
		
	if cloudEnabled then
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
			Controls.CloudCheck:SetText(Locale.Lookup("LOC_STEAMCLOUD"));
			if (isNew == 0) then
				Controls.DummyNewIndicator:SetHide(false);
			end
		end
	else
		Controls.CloudDummy:SetHide(true);
		if (isNew == 0) then
			Controls.CheckNewIndicator:SetHide(false);
		end

		if cloudServicesResult ~= nil then
			if cloudServicesResult == DB.MakeHash("REQUIRES_LINKED_ACCOUNT") then
				Controls.CloudCheck:LocalizeAndSetToolTip("LOC_CLOUD_SAVES_REQUIRE_LINKED_ACCOUNT");
			else
				Controls.CloudCheck:LocalizeAndSetToolTip("LOC_CLOUD_SAVES_SERVICE_NOT_CONNECTED");
			end
			Controls.CloudCheck:SetDisabled(true);
		end

		if g_GameType == SaveTypes.WORLDBUILDER_MAP or g_GameType == SaveTypes.TILED_MAP or g_FileType == SaveFileTypes.GAME_CONFIGURATION then
			Controls.CloudCheck:SetHide(true);
		else
			Controls.CloudCheck:SetHide(false);
		end
	end
		
	if (isNew == 0) then
		Options.SetAppOption("Misc", "UserSawCloudNew", 1);
	end
			
	local autoSavesDisabled = ((g_GameType == SaveTypes.WORLDBUILDER_MAP) or (g_GameType == SaveTypes.TILED_MAP));
	Controls.AutoCheck:SetHide(autoSavesDisabled);	

	RefreshSortPulldown();
	InitializeDirectoryBrowsing();
	SetupDirectoryBrowsePulldown();

	local autoSavesVisible = Controls.AutoCheck:IsVisible();
	local cloudSavesVisible = Controls.CloudCheck:IsVisible();
	local sortByVisible = Controls.SortByPullDown:IsVisible();
	local directoryVisible = Controls.DirectoryPullDown:IsVisible();
    local dummyCloudVisible = Controls.CloudDummy:IsVisible();

	local count:number = 0;
	if(autoSavesVisible) then
		count = count + 1;
	end
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
	
	local decoSize:number = Controls.InspectorArea:GetSizeY();
	
	Controls.DecoContainer:SetSizeY(decoSize - (count * 25) - count);	

	KeyNavResetState();
	m_pending = { prefix = nil, focusFirst = true };
	OutputMessageToScreenReader(Controls.WindowHeader:GetText(), true);
	SetupFileList();
end

function OnHide()
	KeyNavResetState();
	LoadSaveMenu_OnHide();
end


----------------------------------------------------------------        
----------------------------------------------------------------
function OnDelete()
	m_isActionButtonDisabled = Controls.ActionButton:IsDisabled();
	Controls.ActionButton:SetDisabled(true);
	m_deletePopup = true;
	if ( not m_kPopupDialog:IsOpen()) then
		m_kPopupDialog:AddText(Locale.Lookup("LOC_CONFIRM_TXT"));
		m_kPopupDialog:AddTitle(Locale.ToUpper(Locale.Lookup("LOC_CONFIRM_DELETE_TITLE_TXT")));
		m_kPopupDialog:AddButton(Locale.Lookup("LOC_YES_BUTTON"), OnDeleteYes, nil, nil, "PopupButtonInstanceRed"); 
		m_kPopupDialog:AddButton(Locale.Lookup("LOC_NO_BUTTON"), OnDeleteNo);
		m_kPopupDialog:Open();
	end
end

----------------------------------------------------------------        
----------------------------------------------------------------
function OnDeleteYes()
	m_deletePopup = false;
	m_pending = { prefix = "Deleted", focusFirst = true };
	m_kPopupDialog:Close();
	if (g_iSelectedFileEntry ~= -1) then
		local kSelectedFile = g_FileList[ g_iSelectedFileEntry ];		
		UI.DeleteSavedGame( kSelectedFile );
	end
	
	Controls.ActionButton:SetDisabled(m_isActionButtonDisabled);
	SetupFileList();
end

----------------------------------------------------------------        
----------------------------------------------------------------
function OnDeleteNo( )
	m_deletePopup = false;
	Controls.ActionButton:SetDisabled(m_isActionButtonDisabled);
	m_kPopupDialog:Close();
end

----------------------------------------------------------------        
----------------------------------------------------------------
function OnAutoCheck( )
	-- print("Auto Saves - " .. tostring(g_ShowAutoSaves));
	g_ShowAutoSaves = not g_ShowAutoSaves;
	Controls.AutoCheck:SetSelected(g_ShowAutoSaves);

	-- Mutually exclusive with other locations.
	if(g_ShowAutoSaves) then
		g_ShowCloudSaves = false;
		Controls.CloudCheck:SetSelected(g_ShowCloudSaves);
	end

	SetupFileList();
end

----------------------------------------------------------------        
----------------------------------------------------------------
function OnCloudCheck( )
	-- print("Cloud Saves - " .. tostring(g_ShowCloudSaves));

	local bWantShowCloudSaves = not g_ShowCloudSaves;

	if (bWantShowCloudSaves) then
		-- Make sure we can switch to it.
		if (not CanShowCloudSaves()) then
			return;
		end
	end

	g_ShowCloudSaves = bWantShowCloudSaves;

	Controls.CloudCheck:SetSelected(g_ShowCloudSaves);

	-- Mutually exclusive with other locations.
	if(g_ShowCloudSaves) then
		g_ShowAutoSaves = false;
		Controls.AutoCheck:SetSelected(g_ShowAutoSaves);
	end

	SetupDirectoryBrowsePulldown();
	SetupFileList();
	UpdateActionButtonState();
end


---------------------------------------------------------------- 
-- Event Handler: ChangeMPLobbyMode
---------------------------------------------------------------- 
function OnSetLoadGameServerType(newServerType)
	serverType = newServerType;
end

-- ===========================================================================
--	Input Processing
-- ===========================================================================
-- ===========================================================================
--	Keyboard navigation
--	Up/Down: all saves, then Autosaves, Cloud, Sort, Load, Delete, Back (wrapping)
--	Tab: jump between the groups (saves / options / buttons). Home/End: first/last save.
--	Enter: load the save / activate. Space: toggle checkbox. Left/Right: change sort. Space on a save: full details.
-- ===========================================================================

-- Item list, rebuilt from the visible state at every key press.
local function KeyNavBuildItems()
	local items:table = {};
	local files:table = g_FileList or {};
	local count:number = math.min(#files, g_FileEntryInstanceList and #g_FileEntryInstanceList or 0);
	for i = 1, count do
		table.insert(items, { ref = files[i], group = 1, kind = "file", index = i });
	end
	local function ctl(id, control, group, kind)
		if control ~= nil and not control:IsHidden() then
			table.insert(items, { ref = id, group = group, kind = kind, control = control });
		end
	end
	ctl("auto",  Controls.AutoCheck, 2, "check");
	ctl("cloud", Controls.CloudCheck, 2, "check");
	ctl("sort",  Controls.SortByPullDown, 2, "sort");
	ctl("action", Controls.ActionButton, 3, "button");
	ctl("delete", Controls.Delete, 3, "button");
	ctl("back",  Controls.BackButton, 3, "button");
	return items;
end

local function KeyNavItemText(item:table, items:table)
	if item.kind == "file" then
		local total:number = 0;
		for _, it in ipairs(items) do if it.kind == "file" then total = total + 1; end end
		return GetSaveSummaryText(item.ref, false)..", "..item.index.." of "..total;
	elseif item.ref == "auto" then
		return Controls.AutoCheck:GetText()..": "..(g_ShowAutoSaves and "checked" or "unchecked");
	elseif item.ref == "cloud" then
		local t:string = Controls.CloudCheck:GetText()..": "..(g_ShowCloudSaves and "checked" or "unchecked");
		if Controls.CloudCheck:IsDisabled() then t = t..", unavailable"; end
		return t;
	elseif item.ref == "sort" then
		return GetSortOptionText()..", Left or Right to change";
	else
		local t:string = item.control:GetText();
		if item.control:IsDisabled() then t = t..", unavailable"; end
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
		if g_iSelectedFileEntry ~= item.index then SetSelected(item.index); end
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
g_ExtraTick = KeyNavTick;

local function KeyNavCountText()
	local n:number = g_FileList and #g_FileList or 0;
	if n == 0 then
		return Locale.Lookup("LOC_NO_SAVED_GAMES");
	elseif n == 1 then
		return "1 save";
	end
	return n.." saves";
end

-- Called when a file query finishes: announce the count and (re)focus.
local function KeyNavOnListReady()
	local pending:table = m_pending;
	m_pending = nil;
	if pending == nil then return; end
	local items:table = KeyNavBuildItems();
	local text:string = KeyNavCountText();
	if pending.prefix ~= nil then text = pending.prefix..". "..text; end
	OutputMessageToScreenReader(text, true);
	-- The entries are created over the next frames; focus once they exist.
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
	local target:number = (group % 3) + 1;
	for attempt = 1, 3 do
		for _, it in ipairs(items) do
			if it.group == target then
				KeyNavFocus(it, items, (target == 1 and "Saves") or (target == 2 and "Options") or "Buttons");
				return;
			end
		end
		target = (target % 3) + 1;
	end
end

local function KeyNavActivate(item:table, items:table, key:number)
	if item.kind == "file" then
		if key == Keys.VK_RETURN then
			if g_iSelectedFileEntry ~= item.index then SetSelected(item.index); end
			OnActionButton();
		end
	elseif item.kind == "check" then
		if item.control:IsDisabled() then
			OutputMessageToScreenReader(KeyNavItemText(item, items), false);
			return;
		end
		if item.ref == "auto" then OnAutoCheck(); else OnCloudCheck(); end
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
	if key == Keys.VK_ESCAPE then
		if m_kPopupDialog:IsOpen() then
			if m_deletePopup then OnDeleteNo(); else m_kPopupDialog:Close(); end
			local items:table = KeyNavBuildItems();
			local item:table = KeyNavFindFocused(items);
			if item ~= nil then OutputMessageToScreenReader(KeyNavItemText(item, items), false); end
		else
			OnBack();
		end
		return true;
	end
	if m_kPopupDialog:IsOpen() then
		return m_kPopupDialog:KeyHandler(key);
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
		if item ~= nil and key == Keys.VK_SPACE and item.kind == "file" then
			-- Space on a save reads its full details
			OutputMessageToScreenReader(GetSaveSummaryText(item.ref, true), false);
		elseif item ~= nil and (key == Keys.VK_RETURN or item.kind == "check") then
			KeyNavActivate(item, items, key);
		end
	end
	return true;
end

function OnInputHandler( pInputStruct:table )
	local uiMsg = pInputStruct:GetMessageType();
	if uiMsg == KeyEvents.KeyUp then
		local ok, result = xpcall(function() return KeyHandler( pInputStruct:GetKey() ); end, function(e) return debug.traceback(tostring(e), 2); end);
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
function OnJoiningRoom_Showing()
	-- Remove ourself if the joining room screen is showing.
	UIManager:DequeuePopup( ContextPtr );
end

-- Call-back for when the list of files have been updated.
function OnQuickLoadQueryResults( fileList, queryID )
	if g_QuickLoadQueryRequestID ~= nil then
		if (g_QuickLoadQueryRequestID == queryID) then
			if (fileList ~= nil and #fileList > 0) then
				local save = fileList[1];
			
				local mods = save.RequiredMods or {};
	
				-- Test for errors.
				-- Will return a combination array/map of any errors regarding this combination of mods.
				-- Array messages are generalized error codes regarding the set.
				-- Map messages are error codes specific to the mod Id.
				local errors = Modding.CheckRequirements(mods, SaveTypes.SINGLE_PLAYER);
				local success = (errors == nil or errors.Success);

				if(success) then
					Network.LoadGame(save, serverType);
				end
			end

			UI.CloseFileListQuery(g_QuickLoadQueryRequestID);
			g_QuickLoadQueryRequestID = nil;
		end
	end
end

-- ===========================================================================
--	Hotkey Event
-- ===========================================================================
function OnInputActionTriggered( actionId )
    if actionId == m_QuickloadId then
        -- Quick load
        if CanLocalPlayerLoadGame() then
			g_QuickLoadQueryRequestID = nil;
			local options = SaveLocationOptions.QUICKSAVE + SaveLocationOptions.LOAD_METADATA ;
			g_QuickLoadQueryRequestID = UI.QuerySaveGameList( SaveLocations.LOCAL_STORAGE, SaveTypes.SINGLE_PLAYER, options );
        end
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

-- ===========================================================================
function OnRefresh()
	SetupDirectoryBrowsePulldown();
	SetupFileList();
end

-- ===========================================================================
function OnLoadComplete(eResult, eType, eOptions, eFileType )

	-- Did a configuration load?
	if eFileType == SaveFileTypes.GAME_CONFIGURATION then

		if ContextPtr:IsVisible() then

			-- Doing this code inside the IsVisible if, because there are multiple instances of the LoadGameMenu

			-- Make sure the Game State is pre-game.  If the user loaded a auto-save of the configuration, or 
			-- got the configuration out of a save, it will be in a state where they can't edit some values.
			if (GameConfiguration ~= nil) then
				GameConfiguration.SetToPreGame();

				--Reset the seeds and leader selection when loading a config so that configs are more usable
				GameConfiguration.RegenerateSeeds();
				local playerIDs : table = GameConfiguration.GetParticipatingPlayerIDs();
				for k,v in ipairs(playerIDs)do
					local kPlayerConfig : table = PlayerConfigurations[v];
					local leaderTypeName : string = kPlayerConfig:GetLeaderTypeName();
					if(leaderTypeName ~= nil)then
						kPlayerConfig:SetLeaderTypeName(nil);
						kPlayerConfig:SetCivilizationTypeName(nil);
					end
				end
			end

			UIManager:DequeuePopup( ContextPtr );

		end
	end

end

-- ===========================================================================
function OnSelectedFileStackSizeChanged()
	ResizeGameInfoScrollPanel();
end

-- ===========================================================================
function Initialize()
	m_kPopupDialog = PopupDialog:new( "LoadGameMenu" );

	AutoSizeGridButton(Controls.BackButton,133,36);
	SetupSortPulldown();
	InitializeDirectoryBrowsing();
	Resize();

	LuaEvents.FileListQueryComplete.Add( OnFileListQueryComplete );

	-- UI Events
	ContextPtr:SetInputHandler( OnInputHandler, true );
	ContextPtr:SetShowHandler(OnShow);
	ContextPtr:SetHideHandler(OnHide);
	ContextPtr:SetInitHandler(OnInit);
	ContextPtr:SetRefreshHandler( OnRefresh );
	ContextPtr:SetShutdown(OnShutdown);
	LuaEvents.GameDebug_Return.Add(OnGameDebugReturn);
	LuaEvents.JoiningRoom_Showing.Add(OnJoiningRoom_Showing);

	-- UI Callbacks
	Controls.ActionButton:RegisterCallback( Mouse.eLClick, OnActionButton );
	Controls.AutoCheck:RegisterCallback( Mouse.eLClick, OnAutoCheck );
	Controls.BackButton:RegisterCallback( Mouse.eLClick, OnBack );
	Controls.CloudCheck:RegisterCallback( Mouse.eLClick, OnCloudCheck );
	Controls.Delete:RegisterCallback( Mouse.eLClick, OnDelete );
	Controls.SelectedFileStack:RegisterSizeChanged( OnSelectedFileStackSizeChanged );

	-- LUA Events
	LuaEvents.HostGame_SetLoadGameServerType.Add( OnSetLoadGameServerType );
	LuaEvents.MainMenu_SetLoadGameServerType.Add( OnSetLoadGameServerType );
	LuaEvents.InGameTopOptionsMenu_SetLoadGameServerType.Add( OnSetLoadGameServerType );

	LuaEvents.FileListQueryResults.Add( OnQuickLoadQueryResults );

	Events.SystemUpdateUI.Add( OnUpdateUI );

    m_QuickloadId = Input.GetActionId("QuickLoad");
    Events.InputActionTriggered.Add( OnInputActionTriggered );
    Events.LoadComplete.Add( OnLoadComplete );
end
Initialize();

