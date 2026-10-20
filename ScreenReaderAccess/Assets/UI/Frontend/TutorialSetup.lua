-- Copyright 2016-2018, Firaxis Games
-- Tutorial Setup Screen

include("SetupParameters");
include("KeyboardNavigation");
include("ScreenReader");

g_TutorialModId = "17462E0F-1EE1-4819-AAAA-052B5896B02A";
g_ScreenReaderModId = "49224623-c629-4e7a-a5cb-ad822828072e";
g_GameParameters = nil;		-- Game Parameters.
local m_isMoviePaused:boolean = false;

-- Keyboard navigation state.
local m_keyNavFocus		:string = nil;		-- identity of the focused item: "leader1", "leader2" or "back"
local m_keyNavAnnounced	:boolean = true;	-- screen title/description announced since the movie ended?
local m_keyNavFrames	:number = 0;


-------------------------------------------------------------------------------
-- Setup Parameter overrides.
-------------------------------------------------------------------------------
function SinglePlayerGameParameters(o, parameter)

	-- Ignore player specific parameters.
	if(parameter.ConfigurationGroup == "Player") then
		return false;
	end

	-- Single-Player only.
	return parameter.SupportsSinglePlayer;
end

-------------------------------------------------------------------------------
-- Event Listeners
-------------------------------------------------------------------------------
Events.FinishedGameplayContentConfigure.Add(function(result)
	if(result.Success) then
		if(ConstructParameters()) then
			Controls.StatusPanel:SetHide(true);
			Controls.TutorialPanel:SetHide(false);		
		end
	else
		 Controls.Status:SetText("[COLOR_RED]There was an error loading the tutorial.[ENDCOLOR]");	
	end
end);

------------------------------------------------------------------    
function EnsureTutorialIsEnabled()

	 --Configure UI first
	 Controls.TutorialPanel:SetHide(true);
	 Controls.StatusPanel:SetHide(false);
	 Controls.Status:SetText("Enabling the Tutorial Mod...");

	 -- Configure Mods
	local tutorialHandle = Modding.GetModHandle(g_TutorialModId);
	if(tutorialHandle == nil) then
		 Controls.Status:SetText("[COLOR_RED]The tutorial mod could not be found.[ENDCOLOR]");
	else
		if(not tutorialEnabled) then
			GameConfiguration.AddEnabledMods(tutorialHandle, true);
		end
		-- Screen reader: keep this mod enabled in the tutorial game, otherwise none of its in-game UI overrides (advisor popup etc.) load.
		local srHandle = Modding.GetModHandle(g_ScreenReaderModId);
		if(srHandle ~= nil) then
			GameConfiguration.AddEnabledMods(srHandle);
		end
	end
end

function ConstructParameters()
	
	-- Construct new parameters.
	g_GameParameters = SetupParameters.new();	
	g_GameParameters.Parameter_GetRelevant = SinglePlayerGameParameters;


	g_GameParameters:Initialize();		-- Perform any initialization.
	g_GameParameters:FullRefresh();		-- Perform a full refresh before configuring.

	-- Obtain the parameter 'Ruleset' and set it to the value 'RULESET_TUTORIAL'.
	local ruleset = g_GameParameters.Parameters["Ruleset"];

	if(ruleset == nil) then
		print("Cannot find Tutorial ruleset :( :( ");
		return false;
	end

	local tutorial_ruleset;
	if(ruleset) then
		for i,v in ipairs(ruleset.Values) do
			if(v.Value == "RULESET_TUTORIAL") then
				tutorial_ruleset = v;
			end
		end
	end
	
	-- Set the ruleset to be the tutorial.
	if(ruleset and tutorial_ruleset) then
		g_GameParameters:SetParameterValue(ruleset, tutorial_ruleset);

		-- We've set the new value, now refresh and reconcile.
		g_GameParameters:FullRefresh();

		-- KLUDGE CODE
		-- The map size change in setup parameters is not executing this properly.
		-- Ideally, setting the map size will also set min,max, and default players.
		-- The parameter code will then call the proper methods to adjust.
		MapConfiguration.SetMaxMajorPlayers(2);
		GameConfiguration.SetParticipatingPlayerCount(2);
		-- END KLUDGE CODE
			
		return true;
	else
		return false;
	end
end

function TeardownParameters()
	if(g_GameParameters) then
		g_GameParameters:Shutdown();
		g_GameParameters = nil;
	end
end

------------------------------------------------------------------    
function OnShow()
	m_keyNavFocus = nil;
	m_keyNavAnnounced = false;
	m_keyNavFrames = 0;
	EnsureTutorialIsEnabled();
	Controls.IntroMovieContainer:RegisterCallback(  Mouse.eLClick, OnClickStopMovie );
	Controls.IntroMovieContainer:SetHide( false );

    UI.StartStopMenuMusic(false);
	Controls.IntroMovie:SetMovieFinishedCallback( OnFinishMoviePlayback );	
	Controls.IntroMovie:SetMovie("TUT_INTRO.bk2");	
	Controls.IntroMovie:Play();	
	UI.PlaySound("Play_Cinematic_Tutorial_Intro");
	m_isMoviePaused = false;
	OutputMessageToScreenReader(CleanTextForSpeech(Locale.Lookup("LOC_SETUP_TUTORIAL_TITLE")).." introduction movie. Press Enter or Escape to skip it", true);
end

-- ===========================================================================
function OnHide()
	TeardownParameters();
end


------------------------------------------------------------------    
---- Button Handlers
------------------------------------------------------------------    
function OnLeader1()
	local player0 = PlayerConfigurations[0];
	if(player0) then
		player0:SetLeaderTypeName("LEADER_CLEOPATRA");
	end

	-- Kludge.
	-- Ideally, Player slot 1 would be set to "RANDOM_UNIQUE".
	local player1 = PlayerConfigurations[1];
	if(player1) then
		player1:SetLeaderTypeName("LEADER_GILGAMESH");
	end

	Events.SetGameEntryMethod("Tutorial Leader 1");
	Network.HostGame(ServerType.SERVER_TYPE_NONE);
end
Controls.Leader1Start:RegisterCallback( Mouse.eLClick, OnLeader1 );
----------------------------------------------------------------   
function OnLeader2()
	local player0 = PlayerConfigurations[0];
	if(player0) then
		player0:SetLeaderTypeName("LEADER_GILGAMESH");
	end

	-- Kludge.
	-- Ideally, Player slot 1 would be set to "RANDOM_UNIQUE".
	local player1 = PlayerConfigurations[1];
	if(player1) then
		player1:SetLeaderTypeName("LEADER_CLEOPATRA");
	end

	Events.SetGameEntryMethod("Tutorial Leader 2");
	Network.HostGame(ServerType.SERVER_TYPE_NONE);
end

----------------------------------------------------------------    
function OnBackButton()
	
	-- We are exiting out of the tutorial setup menu.
	-- Let's make sure the game config matches what the 
	-- user enabled.
	GameConfiguration.UpdateEnabledMods();
	UIManager:DequeuePopup( ContextPtr );
end

-- ===========================================================================
function StopMovie()
	Controls.IntroMovieContainer:ClearCallback(  Mouse.eLClick );	
	Controls.IntroMovieContainer:SetHide( true );
    UI.StartStopMenuMusic(true);
	UI.PlaySound("Stop_Cinematic_Tutorial_Intro");
	KeyNavAnnounceScreen();
end

-- ===========================================================================
--	Stopping movie by clicking it.
-- ===========================================================================
function OnClickStopMovie()
	StopMovie();
end

-- ===========================================================================
--	Stopping movie because it finished playing.
-- ===========================================================================
function OnFinishMoviePlayback()
	StopMovie();
end

-- ===========================================================================
function IsMovieHandling( pInputStruct:table)

	if Controls.IntroMovie:IsPlaying() then
		local uiMsg = pInputStruct:GetMessageType();	
		if uiMsg == KeyEvents.KeyUp then
			local uiKey = pInputStruct:GetKey();
			if uiKey == Keys.VK_ESCAPE or uiKey == Keys.VK_RETURN then
				StopMovie();
				return true;			
			end
		elseif uiMsg == MouseEvents.LButtonUp then
			StopMovie();
			return true;			
		end
	end
	return false;		
end

-- ===========================================================================
-- Keyboard navigation
-- ===========================================================================
local function KeyNavItems()
	local items:table = {};
	if not Controls.TutorialPanel:IsHidden() then
		if not Controls.Leader1Start:IsHidden() and not Controls.Leader1Start:IsDisabled() then
			table.insert(items, { id = "leader1", control = Controls.Leader1Start, callback = OnLeader1, descLoc = "LOC_SETUP_TUTORIAL_LEADER_1" });
		end
		if not Controls.Leader2Start:IsHidden() and not Controls.Leader2Start:IsDisabled() then
			table.insert(items, { id = "leader2", control = Controls.Leader2Start, callback = OnLeader2, descLoc = "LOC_SETUP_TUTORIAL_LEADER_2" });
		end
	end
	table.insert(items, { id = "back", control = Controls.CloseButton, callback = OnBackButton });
	return items;
end

local function KeyNavItemText( item:table )
	local text:string = CleanTextForSpeech(item.control:GetText());
	if item.descLoc ~= nil then
		text = text..". "..CleanTextForSpeech(Locale.Lookup(item.descLoc));
	end
	return text;
end

local function KeyNavFocusItem( item:table, interrupt:boolean )
	m_keyNavFocus = item.id;
	OutputMessageToScreenReader(KeyNavItemText(item), not interrupt);
	-- Park the real mouse on the control for sighted helpers (no animation on this screen).
	KeyNavMoveMouse(item.control);
end

function KeyNavAnnounceScreen()
	m_keyNavAnnounced = true;
	local title:string = CleanTextForSpeech(Controls.TitleLabel:GetText());
	if Controls.TutorialPanel:IsHidden() then
		local status:string = CleanTextForSpeech(Controls.Status:GetText());
		OutputMessageToScreenReader(title..". "..status, true);
		m_keyNavFocus = "back";
		return;
	end
	OutputMessageToScreenReader(title..". "..CleanTextForSpeech(Locale.Lookup("LOC_SETUP_TUTORIAL_DESCRIPTION")), true);
	local items:table = KeyNavItems();
	KeyNavFocusItem(items[1], false);
end

local function KeyNavMove( delta:number )
	local items:table = KeyNavItems();
	local index:number = 0;
	for i, item in ipairs(items) do
		if item.id == m_keyNavFocus then index = i; break; end
	end
	if index == 0 then
		index = (delta > 0) and 1 or #items;
	else
		index = ((index - 1 + delta) % #items) + 1;
	end
	KeyNavFocusItem(items[index], true);
end

local function KeyNavActivate()
	local items:table = KeyNavItems();
	for i, item in ipairs(items) do
		if item.id == m_keyNavFocus then item.callback(); return; end
	end
	KeyNavFocusItem(items[1], true);
end

-- Returns true when the key was handled.
local function KeyNavKeyHandler( uiKey:number )
	if not m_keyNavAnnounced then
		-- Screen not announced yet (panel still loading): do it now on the first key.
		KeyNavAnnounceScreen();
		if uiKey == Keys.VK_ESCAPE then OnBackButton(); end
		return true;
	end
	if uiKey == Keys.VK_ESCAPE then
		OnBackButton();
	elseif uiKey == Keys.VK_DOWN or uiKey == Keys.VK_RIGHT or uiKey == Keys.VK_TAB then
		KeyNavMove(1);
	elseif uiKey == Keys.VK_UP or uiKey == Keys.VK_LEFT then
		KeyNavMove(-1);
	elseif uiKey == Keys.VK_RETURN or uiKey == Keys.VK_SPACE then
		KeyNavActivate();
	else
		return false;
	end
	return true;
end

-- ===========================================================================
function OnUpdate( deltaTime:number )
	KeyNav_Tick(deltaTime);
	-- Fallback: if the movie never started (or already ended) announce the screen once the panel is ready.
	if not m_keyNavAnnounced and Controls.IntroMovieContainer:IsHidden() then
		m_keyNavFrames = m_keyNavFrames + 1;
		if m_keyNavFrames > 20 then KeyNavAnnounceScreen(); end
	end
end

-- ===========================================================================
-- Input handling
-- ===========================================================================
function OnInputHandler( pInputStruct:table )
	local uiMsg :number = pInputStruct:GetMessageType();
	if uiMsg == KeyEvents.KeyUp then
		local uiKey :number = pInputStruct:GetKey();
		if Controls.IntroMovie:IsPlaying() and not Controls.IntroMovieContainer:IsHidden() then
			if uiKey == Keys.VK_ESCAPE or uiKey == Keys.VK_RETURN then
				StopMovie();
				return true;
			end
		else
			local handled:boolean = false;
			local ok, err = xpcall(function() handled = KeyNavKeyHandler(uiKey); end, function(e) return tostring(e); end);
			if not ok then print("TutorialSetup keynav error: "..tostring(err)); end
			if handled then return true; end
		end
	end
	return false;
end


-- ===========================================================================
--	Handle Window Sizing
-- ===========================================================================
function Resize()
	local screenX, screenY:number = UIManager:GetScreenSizeVal();
	local hideLogo = true;
	if(screenY >= Controls.MainWindow:GetSizeY() + (Controls.LogoContainer:GetSizeY()+ Controls.LogoContainer:GetOffsetY())*2) then
		hideLogo = false;
	end
	Controls.LogoContainer:SetHide(hideLogo);
	Controls.MainGrid:ReprocessAnchoring();
end

-- ===========================================================================
function OnUpdateUI( type:number, tag:string, iData1:number, iData2:number, strData1:string )   
  if type == SystemUpdateUI.ScreenResize then
    Resize();
  end
end


-- ===========================================================================
function OnUserRequestClose()
	if UIManager:IsInPopupQueue( ContextPtr ) then
		if Controls.IntroMovie:IsPlaying() then
			Controls.IntroMovie:Pause();
			UI.PlaySound("Stop_Cinematic_Tutorial_Intro");
			m_isMoviePaused = true;
		end
	end
end

-- ===========================================================================
function OnCancelAppClose()
	if UIManager:IsInPopupQueue( ContextPtr ) and m_isMoviePaused then		
		m_isMoviePaused = false;
		Controls.IntroMovie:Play();
	end
end

-- ===========================================================================
function Initialize()	

	Resize();
	
	ContextPtr:SetShowHandler( OnShow );
	ContextPtr:SetHideHandler( OnHide );
	ContextPtr:SetInputHandler( OnInputHandler, true );
	ContextPtr:SetUpdate( OnUpdate );
	
	-- Static information we don't need to change later.
	Controls.Leader1Portrait:SetIcon("ICON_LEADER_CLEOPATRA");
	Controls.Leader2Portrait:SetIcon("ICON_LEADER_GILGAMESH");
	Controls.Leader2Start:RegisterCallback( Mouse.eLClick, OnLeader2 );
	Controls.Leader1Start:RegisterCallback( Mouse.eMouseEnter, function() UI.PlaySound("Main_Menu_Mouse_Over"); end);
	Controls.Leader2Start:RegisterCallback( Mouse.eMouseEnter, function() UI.PlaySound("Main_Menu_Mouse_Over"); end);
	Controls.CloseButton:RegisterCallback( Mouse.eLClick, OnBackButton );
	Controls.CloseButton:RegisterCallback( Mouse.eMouseEnter, function() UI.PlaySound("Main_Menu_Mouse_Over"); end);

	Events.SystemUpdateUI.Add( OnUpdateUI );
    Events.UserRequestClose.Add( OnUserRequestClose );

	LuaEvents.FrontEndPopup_CloseConfirmationWithoutAction.Add( OnCancelAppClose );
end
Initialize();