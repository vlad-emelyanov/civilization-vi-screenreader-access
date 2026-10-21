-- ===========================================================================
--
--	ResearchChooser
--	Slideout panel containing available research options, with the current
--	or most recently completed research at the top.
--
-- ===========================================================================
include("ToolTipHelper");
include("TechAndCivicSupport");
include("AnimSidePanelSupport");
include("SupportFunctions");
include("Civ6Common");
include("GameCapabilities");
include("ScreenReader");	-- ScreenReaderAccess
include("KeyNavList");		-- ScreenReaderAccess


-- ===========================================================================
--	CONSTANTS
-- ===========================================================================
local RELOAD_CACHE_ID			:string = "ResearchChooser";	-- Must be unique (usually the same as the file name)
local SIZE_ICON_LARGE			:number = 38;
local SIZE_ICON_SMALL			:number = 30;

local TUTORIAL_ID				:string = "17462E0F-1EE1-4819-AAAA-052B5896B02A";
local TUTORIAL_TECHS			:table = {
	[2] = UITutorialManager:GetHash("TECH_MINING"),
	[4] = UITutorialManager:GetHash("TECH_POTTERY"),
	[3] = UITutorialManager:GetHash("TECH_IRRIGATION")
}
-- ===========================================================================
--	MEMBERS
-- ===========================================================================
local m_researchIM		:table	= InstanceManager:new( "ResearchListInstance", "TopContainer",	Controls.ResearchStack );
local m_kSlideAnimator	:table; --AnimSidePanelSupport
local m_currentID		:number = -1;
local m_isExpanded		:boolean = false;
local m_lastCompletedID	:number = -1;
local m_isTutorial		:boolean = false;
local m_needsRefresh	:boolean = false; --used to track whether a given series of events (terminated by GameCoreEventPublishComplete)

-- ===========================================================================
--	METHODS
-- ===========================================================================



-- ===========================================================================
--	Determine the current data.
-- ===========================================================================
function GetData()
	local kData			:table  = {};
	local ePlayer		:number = Game.GetLocalPlayer();
	local pPlayer		:table  = Players[ePlayer];
	local pPlayerTechs	:table	= pPlayer:GetTechs();
	local pResearchQueue:table	= {};

	-- Get recommendations
	local techRecommendations:table = {};
	local pGrandAI:table = pPlayer:GetGrandStrategicAI();
	if pGrandAI then
		techRecommendations = pGrandAI:GetTechRecommendations();
	end

	pResearchQueue = pPlayerTechs:GetResearchQueue(pResearchQueue);
	
	-- Fill in the "other" (not-current) items
	for kTech in GameInfo.Technologies() do
		
		local iTech	:number = kTech.Index;
		if	iTech == m_currentID or 
			iTech == m_lastCompletedID or 
			(iTech ~= m_currentID and pPlayerTechs:CanResearch(iTech)) then

			local kResearchData :table = GetResearchData( ePlayer, pPlayerTechs, kTech );
			kResearchData.IsCurrent			= (iTech == m_currentID);
			kResearchData.IsLastCompleted	= (iTech == m_lastCompletedID);
			kResearchData.ResearchQueuePosition = -1;
			for i, techNum in pairs(pResearchQueue) do
				if techNum == iTech then
					kResearchData.ResearchQueuePosition = i;
				end
			end

			-- Determine if this tech is recommended
			kResearchData.IsRecommended = false;
			if techRecommendations ~= nil then
				for i,recommendation in pairs(techRecommendations) do
					if kResearchData.Hash == recommendation.TechHash then
						 kResearchData.IsRecommended = true;
						 kResearchData.AdvisorType = kTech.AdvisorType;
					end
				end
			end

			table.insert( kData, kResearchData ); 
		end
	end

	return kData;
end


-- ===========================================================================
--	Populate the list of research options.
-- ===========================================================================
function View( playerID:number, kData:table )
		
	m_researchIM:ResetInstances();

	local kActive : table = GetActiveData(kData);		
	if kActive == nil then
		RealizeCurrentResearch( nil );	-- No research done yet
	end

	table.sort(kData, function(a, b) return Locale.Compare(a.Name, b.Name) == -1; end);	

	for i, data in ipairs(kData) do
		if data.IsCurrent or data.IsLastCompleted then
			RealizeCurrentResearch( playerID, data );
			if data.Repeatable then
				AddAvailableResearch( playerID, data );
			end
		else
			AddAvailableResearch( playerID, data );
		end
	end		

	-- TUTORIAL HACK: Ensure tutorial techs are in a specific position in the list:
	if m_isTutorial then
		local tutorialIndex:number = -1;
		local tutorialControl:table = nil;
		local tutorialControlHash:number = -1;
		for i:number = 1, m_researchIM.m_iAllocatedInstances do
			local instance:table = m_researchIM:GetAllocatedInstance(i);
			local tag:number = instance.Top:GetTag();
			for index:number, techHash:number in pairs(TUTORIAL_TECHS) do
				if tag == techHash then
					tutorialIndex = index;
					tutorialControl = instance.TopContainer;
					tutorialControlHash = techHash;
					break;
				end
			end
			if tutorialControl then break; end
		end
		if tutorialControl then
			Controls.ResearchStack:AddChildAtIndex(tutorialControl, tutorialIndex);
		end
	end

	RealizeSize();	
end


-- ===========================================================================
-- Begin ScreenReaderAccess change: keyboard list of the researchable techs.
-- Rebuilt from GetData() whenever a key is pressed (the same data View() shows, same order).
-- ===========================================================================
local m_srList:table = nil;

local function SRA_GetItems()
	local items:table = {};
	local playerID:number = Game.GetLocalPlayer();
	if playerID < 0 then return items; end
	local kData:table = GetData();
	table.sort(kData, function(a, b) return Locale.Compare(a.Name, b.Name) == -1; end);
	for _, data in ipairs(kData) do
		if (not (data.IsCurrent or data.IsLastCompleted)) or data.Repeatable then
			local parts:table = { data.Name };
			if data.TurnsLeft ~= nil and data.TurnsLeft > 0 then
				table.insert(parts, data.TurnsLeft .. (data.TurnsLeft == 1 and " turn" or " turns"));
			end
			if data.Boostable then
				if data.BoostTriggered then
					table.insert(parts, "boosted");
				else
					table.insert(parts, "boost: " .. CleanTextForSpeech(Locale.Lookup(data.TriggerDesc)));
				end
			end
			local unlockNames:table = {};
			for _, unlock in ipairs(GetUnlockablesForTech_Cached(data.TechType, playerID) or {}) do
				if unlock[2] ~= nil then table.insert(unlockNames, CleanTextForSpeech(Locale.Lookup(unlock[2]))); end
			end
			if #unlockNames > 0 then
				table.insert(parts, "unlocks: " .. KeyNavList_ShortList(unlockNames, 4));
			end
			if data.IsRecommended then table.insert(parts, "recommended"); end
			local detailData:table = data;
			table.insert(items, {
				key = data.Hash,
				text = table.concat(parts, ", "),
				data = data,
				detail = function()
					local text:string = CleanTextForSpeech(Locale.Lookup(detailData.ToolTip));
					if detailData.Boostable then
						text = text .. ". " .. (detailData.BoostTriggered and "Boosted" or "Boost") .. ": " .. CleanTextForSpeech(Locale.Lookup(detailData.TriggerDesc));
					end
					-- cost and the player's rate come first (Space only, the list line stays short)
					local prefix:string = "";
					if detailData.ResearchCost ~= nil then
						prefix = "Cost " .. detailData.ResearchCost .. " science";
						if detailData.Progress ~= nil and detailData.Progress > 0 then
							prefix = prefix .. ", " .. math.floor(detailData.Progress * detailData.ResearchCost + 0.5) .. " done";
						end
						local yield:number = Players[Game.GetLocalPlayer()]:GetTechs():GetScienceYield();
						prefix = prefix .. ". You make " .. (yield <= 0 and "no science" or (math.floor(yield * 10 + 0.5) / 10 .. " per turn")) .. ". ";
					end
					text = prefix .. text;
					return text;
				end,
			});
		end
	end
	return items;
end

local function SRA_OnActivate( item:table )
	if CanPlayerResearchAnything(Game.GetLocalPlayer()) then	-- (sic) true when there is no science: items are disabled
		OutputMessageToScreenReader("Can't choose research: no science");
		return;
	end
	local data:table = item.data;
	OnChooseResearch(data.Hash);
	local text:string = "Researching " .. data.Name;
	if data.TurnsLeft ~= nil and data.TurnsLeft > 0 then
		text = text .. ", " .. data.TurnsLeft .. (data.TurnsLeft == 1 and " turn" or " turns");
	end
	OutputMessageToScreenReader(text);
end

local function SRA_OnClose()
	OnClosePanel();
	OutputMessageToScreenReader("Research closed");
end

local function SRA_OpenList()
	local title:string = Locale.Lookup("LOC_RESEARCH_CHOOSER_CHOOSE_RESEARCH");
	if CanPlayerResearchAnything(Game.GetLocalPlayer()) then title = title .. ", no science"; end	-- (sic) true when science is 0
	-- the live state, not m_currentID: that is stale right after a tech was completed
	local techs:table = Players[Game.GetLocalPlayer()]:GetTechs();
	local currentID:number = techs:GetResearchingTech();
	if currentID ~= nil and currentID >= 0 and GameInfo.Technologies[currentID] ~= nil and not techs:HasTech(currentID) then
		title = title .. ", currently " .. Locale.Lookup(GameInfo.Technologies[currentID].Name);
	end
	m_srList.Reset();
	m_srList.Open(title);
end
-- End ScreenReaderAccess change

-- ===========================================================================
--	Get the latest data and visualize.
-- ===========================================================================
function Refresh()
	local player:number = Game.GetLocalPlayer();
	if (player >= 0) then
		local kData :table	= GetData();	
		View( player, kData );
	end

	m_needsRefresh = false;
end


-- ===========================================================================
--	No science? No research for you!
-- ===========================================================================
function CanPlayerResearchAnything( playerID:number )
	local pPlayer				:table  = Players[playerID];
	local playerTechnology		:table	= pPlayer:GetTechs();
	local currentScienceYield	:number = playerTechnology:GetScienceYield();
	return currentScienceYield <= 0;
end

-- ===========================================================================
--
-- ===========================================================================
function AddAvailableResearch( playerID:number, kData:table )	

	if playerID == -1 then return; end	-- Autoplay

	local isDisabled:boolean = CanPlayerResearchAnything( playerID );
	
	-- Create main instance and the Instance Manager for any unlocks.
	local kItemInstance	:table = m_researchIM:GetInstance();
	local techUnlockIM	:table = GetUnlockIM( kItemInstance );
		
	kItemInstance.TechName:SetText(Locale.ToUpper(kData.Name));
	kItemInstance.Top:LocalizeAndSetToolTip(kData.ToolTip);
	kItemInstance.Top:SetTag( UITutorialManager:GetHash(kData.TechType) );	-- Mark for tutorial dynamic element

	RealizeMeterAndBoosts( kItemInstance, kData );
	RealizeIcon( kItemInstance.Icon, kData.TechType, SIZE_ICON_SMALL );
	RealizeTurnsLeft( kItemInstance, kData );

	local callback:ifunction = nil;
	if not isDisabled then
		callback = function() 
			ResetOverflowArrow( kItemInstance );
			OnChooseResearch(kData.Hash); 
		end;
	end 

	local numUnlockables:number = PopulateUnlockablesForTech( playerID, kData.ID, techUnlockIM, callback );
	if numUnlockables ~= nil then
		HandleOverflow(numUnlockables, kItemInstance, 5, 5);
	end

	if kData.ResearchQueuePosition ~= -1 then
		kItemInstance.QueueBadge:SetHide(false);
		kItemInstance.NodeNumber:SetHide(false);
		if(kData.ResearchQueuePosition < 10) then
			kItemInstance.NodeNumber:SetOffsetX(-2);
		else
			kItemInstance.NodeNumber:SetOffsetX(-5);
		end
		kItemInstance.NodeNumber:SetText(tostring(kData.ResearchQueuePosition));
	else
		kItemInstance.QueueBadge:SetHide(true);
		kItemInstance.NodeNumber:SetHide(true);
	end 

    kItemInstance.Top:RegisterCallback( Mouse.eMouseEnter,	function() UI.PlaySound("Main_Menu_Mouse_Over"); end);

	-- Set up callback that changes the current research	
	kItemInstance.Top:RegisterCallback(		Mouse.eLClick,	
											function()
												ResetOverflowArrow( kItemInstance );
												OnChooseResearch(kData.Hash); 
											end);
	-- Only wire up Civilopedia handlers if not in a on-rails tutorial
	if IsTutorialRunning()==false then
		kItemInstance.Top:RegisterCallback(Mouse.eRClick, function() LuaEvents.OpenCivilopedia(kData.TechType); end);
	end
	kItemInstance.Top:SetDisabled( isDisabled );

	-- Hide/Show Recommendation Icon
	if kData.IsRecommended and kData.AdvisorType then
		kItemInstance.RecommendedIcon:SetIcon(kData.AdvisorType);
		kItemInstance.RecommendedIcon:SetHide(false);
	else
		kItemInstance.RecommendedIcon:SetHide(true);
	end

	return kItemInstance;
end

-- ===========================================================================
function OnChooseResearch( techHash:number )
	if techHash == nil then
		UI.DataError("Attempt to choose a research but a NIL hash!");
		return;
	end

	local tParameters :table = {};
	tParameters[PlayerOperations.PARAM_TECH_TYPE] = techHash;
	tParameters[PlayerOperations.PARAM_INSERT_MODE] = PlayerOperations.VALUE_EXCLUSIVE;
	UI.RequestPlayerOperation(Game.GetLocalPlayer(), PlayerOperations.RESEARCH, tParameters);
    UI.PlaySound("Confirm_Tech");

	if m_isExpanded then
		OnClosePanel();
	end	
end

-- ===========================================================================
function RealizeSize()
	local _, screenY:number = UIManager:GetScreenSizeVal();

	Controls.ResearchStack:CalculateSize();
	Controls.ResearchStack:ReprocessAnchoring();

	Controls.ChooseResearchList:SetSizeY(screenY - Controls.ChooseResearchList:GetOffsetY() - 30);
	Controls.ChooseResearchList:CalculateInternalSize();
	
	if(Controls.ChooseResearchList:GetScrollBar():IsHidden()) then
		Controls.ChooseResearchList:SetOffsetX(10);
	else
		Controls.ChooseResearchList:SetOffsetX(20);
	end
end

-- ===========================================================================
function OnOpenPanel()	
	LuaEvents.ResearchChooser_ForceHideWorldTracker();
    UI.PlaySound("Tech_Tray_Slide_Open");
	m_isExpanded = true;
	m_kSlideAnimator.Show();
	SRA_OpenList();		-- ScreenReaderAccess
end

-- ===========================================================================
function OnClosePanel()
	m_kSlideAnimator.Hide();
end

-- ===========================================================================
--	Callback from Slide Animator
-- ===========================================================================
function OnSlideAnimatorClose()
	LuaEvents.ResearchChooser_RestoreWorldTracker();
    UI.PlaySound("Tech_Tray_Slide_Closed");
	m_isExpanded = false;
end

-- ===========================================================================
function OnUpdateUI(type)
	m_kSlideAnimator.OnUpdateUI();	
	if type == SystemUpdateUI.ScreenResize then
		RealizeSize();
	end
end


-- ===========================================================================
--	Game Engine EVENT
--	City added to map, refresh for local player needed if it's the 1st city.
-- ===========================================================================
function OnCityInitialized( owner:number, cityID:number )
	local localPlayer:number = Game.GetLocalPlayer();
	if owner == localPlayer then
		m_needsRefresh = true;
	end
end

-- ===========================================================================
--	Game Engine EVENT
-- ===========================================================================
function OnLocalPlayerTurnBegin()
	local localPlayer:number = Game.GetLocalPlayer();
	if localPlayer >= 0 then
		local pPlayerTechs :table = Players[localPlayer]:GetTechs();
		m_currentID = pPlayerTechs:GetResearchingTech();			

		m_needsRefresh = true;
	end
end

-- ===========================================================================
--	Game Engine EVENT
-- ===========================================================================
function OnPhaseBegin()
	if Game.GetLocalPlayer() >= 0 then
		m_needsRefresh = true;
	end
end

-- ===========================================================================
--	Game Engine EVENT
--	May be active or value boosted for an item further in the list.
-- ===========================================================================
function OnResearchChanged( ePlayer:number, eTech:number )
	m_needsRefresh = ShouldRefreshWhenResearchChanges(ePlayer);
end

-- ===========================================================================
--	This function was separated so behavior can be modified in mods/expasions
-- ===========================================================================
function ShouldRefreshWhenResearchChanges(ePlayer:number)
	local localPlayer = Game.GetLocalPlayer();
	if localPlayer ~= -1 and localPlayer == ePlayer then
		local pPlayerTechs :table = Players[localPlayer]:GetTechs();
		m_currentID			= pPlayerTechs:GetResearchingTech();
		
		-- Only reset last completed tech once a new tech has been selected
		if m_currentID >= 0 then
			m_lastCompletedID = -1;
		end
		
		return true;
	end
	return false;
end

-- ===========================================================================
function OnResearchCompleted( ePlayer:number, eTech:number )
	if ePlayer == Game.GetLocalPlayer() then
		m_lastCompletedID	= eTech;
		m_currentID			= -1;

		m_needsRefresh = true;
	end
end

-- ===========================================================================
function OnResearchYieldChanged( ePlayer:number )
	if ePlayer == Game.GetLocalPlayer() then
		m_needsRefresh = true;
	end
end

-- ===========================================================================
-- This will get called after a series of game events (before any other events or
-- input processing) so we can defer the rebuild until here.
-- ===========================================================================
function FlushChanges()
	if m_needsRefresh and ContextPtr:IsVisible() then
		Refresh();	
	end
end


-- ===========================================================================
--	UI Event
-- ===========================================================================
function OnInputHandler( kInputStruct:table )
	if m_srList ~= nil and m_srList.HandleInput( kInputStruct ) then return true; end		-- ScreenReaderAccess
	return m_kSlideAnimator.OnInputHandler( kInputStruct );
end


-- ===========================================================================
--
--	Init/Uninit/Hot-Loading Events
--    
-- ===========================================================================
function OnInit( isReload:boolean )
	if isReload then
		LuaEvents.GameDebug_GetValues(RELOAD_CACHE_ID);
	else
		local localPlayer	:number = Game.GetLocalPlayer();
		if (localPlayer >= 0) then
			local pPlayerTechs	:table = Players[localPlayer]:GetTechs();
			m_currentID = pPlayerTechs:GetResearchingTech();			
			Refresh();
		end
	end
end

-- ===========================================================================
function OnShow()
	Refresh();
end

-- ===========================================================================
function OnShutdown()
	LuaEvents.GameDebug_AddValue(RELOAD_CACHE_ID, "m_currentID", m_currentID);
	LuaEvents.GameDebug_AddValue(RELOAD_CACHE_ID, "m_isExpanded", m_isExpanded);
	LuaEvents.GameDebug_AddValue(RELOAD_CACHE_ID, "m_lastCompletedID", m_lastCompletedID);
end
-- ===========================================================================
function OnGameDebugReturn(context:string, contextTable:table)	
	if context == RELOAD_CACHE_ID then
		m_currentID			= contextTable["m_currentID"];
		m_lastCompletedID	= contextTable["m_lastCompletedID"];
		Refresh();
		if contextTable["m_isExpanded"] ~= nil and contextTable["m_isExpanded"] then
			OnOpenPanel();			
		else
			LuaEvents.ResearchChooser_RestoreWorldTracker();
		end	
	end
end

-- ===========================================================================
--	INIT
-- ===========================================================================
function Initialize()

	-- ScreenReaderAccess: keyboard list
	m_srList = KeyNavList_Create{
		build = SRA_GetItems,
		isActive = function() return m_kSlideAnimator ~= nil and m_kSlideAnimator.IsVisible(); end,
		onActivate = SRA_OnActivate,
		onClose = SRA_OnClose,
	};

	-- Hot-reload events
	ContextPtr:SetInitHandler(OnInit);
	ContextPtr:SetShowHandler(OnShow);
	ContextPtr:SetShutdown(OnShutdown);
	LuaEvents.GameDebug_Return.Add(OnGameDebugReturn);

	-- Animation controller and events
	m_kSlideAnimator = CreateScreenAnimation(Controls.SlideAnim, OnSlideAnimatorClose );

	-- Screen events
	LuaEvents.Tutorial_ResearchOpen.Add(OnOpenPanel);
	LuaEvents.ActionPanel_OpenChooseResearch.Add(OnOpenPanel);
	LuaEvents.WorldTracker_OpenChooseResearch.Add(OnOpenPanel);
	LuaEvents.LaunchBar_CloseChoosers.Add(OnClosePanel);
	
	-- Game events
	Events.CityInitialized.Add(			OnCityInitialized );
	Events.LocalPlayerTurnBegin.Add(	OnLocalPlayerTurnBegin );
	Events.LocalPlayerChanged.Add(		OnLocalPlayerTurnBegin);
	Events.PhaseBegin.Add(				OnPhaseBegin );
	Events.ResearchChanged.Add(			OnResearchChanged );
	Events.ResearchCompleted.Add(		OnResearchCompleted );
	Events.ResearchYieldChanged.Add(	OnResearchYieldChanged );
	Events.SystemUpdateUI.Add(			OnUpdateUI );
	Events.GameCoreEventPublishComplete.Add( FlushChanges ); --This event is raised directly after a series of gamecore events.
	
	-- UI Event / Callbacks
	ContextPtr:SetInputHandler( OnInputHandler, true);
	Controls.CloseButton:RegisterCallback(Mouse.eLClick, OnClosePanel);
	Controls.CloseButton:RegisterCallback( Mouse.eMouseEnter, function() UI.PlaySound("Main_Menu_Mouse_Over"); end);
	Controls.TitleButton:RegisterCallback(Mouse.eLClick, OnClosePanel);
	Controls.IconButton:RegisterCallback(Mouse.eLClick, OnClosePanel);
	Controls.IconButton:RegisterCallback( Mouse.eMouseEnter, function() UI.PlaySound("Main_Menu_Mouse_Over"); end);

	if(HasCapability("CAPABILITY_TECH_TREE")) then
		Controls.OpenTreeButton:SetHide(false);
		Controls.OpenTreeButton:RegisterCallback(Mouse.eLClick, function() LuaEvents.ResearchChooser_RaiseTechTree(); OnClosePanel(); end);
		Controls.OpenTreeButton:RegisterCallback( Mouse.eMouseEnter, function() UI.PlaySound("Main_Menu_Mouse_Over"); end);
	else
		Controls.OpenTreeButton:SetHide(true);
	end

	-- Populate static controls
	Controls.Title:SetText(Locale.Lookup(Locale.ToUpper("LOC_RESEARCH_CHOOSER_CHOOSE_RESEARCH")));
	Controls.OpenTreeButton:SetText(Locale.Lookup("LOC_RESEARCH_CHOOSER_OPEN_TECH_TREE"));

	-- To make it render beneath the banner image
	Controls.MainPanel:SetOffsetX(Controls.Background:GetOffsetX() * -1);
	Controls.MainPanel:ChangeParent(Controls.Background);

	local mods = Modding.GetActiveMods();
	for i,v in ipairs(mods) do
		if v.Id == TUTORIAL_ID then
			m_isTutorial = true;
			break;
		end
	end
end
Initialize();