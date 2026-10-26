-- ===========================================================================
-- World Congress Popup
-- ===========================================================================
include("PopupDialog");
include("LeaderIcon");
include("CivilizationIcon");
include("InstanceManager");
include("SupportFunctions");
include("WorldCrisisSupport");
include("PopupPriorityLoader_", true);
include("InputSupport");
include("Civ6Common"); --FormatTimeRemaining
include("ScreenReader");		-- ScreenReaderAccess
include("SRListen");			-- ScreenReaderAccess
include("KeyNavList");			-- ScreenReaderAccess
include("WorldCongressText");	-- ScreenReaderAccess

-- ===========================================================================
-- Constants
-- ===========================================================================
local DEBUG_DATA:boolean = false; -- Auto-populate voting data between hot reloads (DO NOT CHECK-IN SET TO TRUE)
local DEBUG_RESET_DATA:boolean = true;	
local RELOAD_CACHE_ID:string = "WorldCongressPopup";

local WORLD_CONGRESS_STAGE_1:number = DB.MakeHash("TURNSEG_WORLDCONGRESS_1");
local WORLD_CONGRESS_STAGE_2:number = DB.MakeHash("TURNSEG_WORLDCONGRESS_2");
local WORLD_CONGRESS_RESOLUTION:number = DB.MakeHash("TURNSEG_WORLDCONGRESS_RESOLUTION");

local REVIEW_TAB_RESULTS:number = DB.MakeHash("REVIEW_TAB_RESULTS");
local REVIEW_TAB_CURRENT_EFFECTS:number = DB.MakeHash("REVIEW_TAB_CURRENT_EFFECTS");
local REVIEW_TAB_AVAILABLE_PROPOSALS:number = DB.MakeHash("REVIEW_TAB_AVAILABLE_PROPOSALS");

local NO_VOTE:number = 0;
local UP_VOTE:number = 1;
local DOWN_VOTE:number = -1;
local PHASE_STEP_MAX:number = 2;

local COLOR_RED:number = UI.GetColorValue(1, 0, 0, 1);
local COLOR_GREEN:number = UI.GetColorValue(97/255, 197/255, 97/255, 1);

-- ===========================================================================
-- Members
-- ===========================================================================
local m_CurrentPhase:number = 0; -- valid values are 1 (select your votes), and 2 (preview before submission)
local m_CurrentStage:number = 0; -- valid values are 1 (regular congress), 2 (special session) and 4 (for results)
local m_WorkingFavor:number = 0; -- pending favor
local m_StartingFavor:number = 0; -- starting favor
local m_IsInSession:boolean = false; -- if m_CurrentStage == 1 or 2
local m_HasAccepted:boolean = false; -- set to true when accept button is clicked if m_CurrentPhase == 2
local m_IsEmergencySession:boolean = false; -- if m_CurrentStage == 2
local m_HasSpecialSessionNotification:boolean = false;
local m_ReviewTab:number = REVIEW_TAB_RESULTS;
local m_kPreviousTooltipEvaluators:table = {};

-- The members below store state that initialize when the screen opens
local m_kProposalVotes:table;
local m_kResolutionVotes:table;
local m_kResolutionChoices:table;
local m_kResolutionsTitle:table;

local m_kPopupDialog:table = PopupDialog:new("WorldCongressPopup");

local m_kLeaderBGItemIM:table = InstanceManager:new("LeaderBanner", "Root");
local m_kLeaderButtonIM:table = InstanceManager:new("LeaderButton", "Root", Controls.LeaderStack);
local m_kProposalItemIM:table = InstanceManager:new("ProposalItem", "Root",	Controls.ResolutionStack);
local m_kResolutionItemIM:table = InstanceManager:new("ResolutionItem", "Root",	Controls.ResolutionStack);
local m_kProposalTitleIM:table = InstanceManager:new("ProposalTitle", "Root", Controls.ResolutionStack);
local m_kReviewResolutionIM:table = InstanceManager:new("ReviewResolution", "Root", Controls.ReviewResolutionStack);
local m_kReviewOutcomeIM:table = InstanceManager:new("ReviewOutcome", "Root");
local m_kReviewProposalIM:table = InstanceManager:new("ReviewProposal", "Root", Controls.ReviewProposalStack);
local m_kEmergencyProposalIM:table = InstanceManager:new("EmergencyProposalItem", "Root",	Controls.ReviewProposalStack);
local m_ProposalVoterIM:table = InstanceManager:new("ProposalVoter", "Root");
local m_ResolutionVoterIM:table = InstanceManager:new("ResolutionVoter", "Root");
local m_VerticalPaddingReviewIM:table = InstanceManager:new("VerticalPaddingReview", "Root");
local m_VerticalPaddingSmallIM:table = InstanceManager:new("VerticalPadding1px", "Root");

local m_kActivePulldown:table;

-- ===========================================================================
--	Checks the current turn segment and opens World Congress if necessary
-- ===========================================================================
function CheckShouldOpen()
	local pPlayer = PlayerConfigurations[Game.GetLocalPlayer()];
	if(pPlayer and pPlayer:IsAlive())then
		local turnSegment = Game.GetCurrentTurnSegment();
		if turnSegment == WORLD_CONGRESS_STAGE_1 then
			SetupWorldCongress(1);
		elseif turnSegment == WORLD_CONGRESS_STAGE_2 then
			SetupWorldCongress(2);
		end
	end
end

-- ===========================================================================
-- Opens the popup	
-- ===========================================================================
function SetupWorldCongress(stageNum:number, beginCongress:boolean)
	-- Account for AutoPlay
	local localPlayerID = Game.GetLocalPlayer();
	if localPlayerID == PlayerTypes.NONE then return; end;

	--Account for Observer Mode
	local pPlayer : table = PlayerConfigurations[localPlayerID];
	if(pPlayer and pPlayer:IsAlive())then
		if SetStage(stageNum, beginCongress) then
			ShowPopup();
		else
			ClosePopup();
		end
	end
end

-- ===========================================================================
-- Opens the DiplomacyActionView on the chosen player (if any)
-- ===========================================================================
function OpenDiplomacyLiteMode(playerID:number)
	if m_IsInSession then
		LuaEvents.WorldCongress_OpenDiplomacyActionViewLite(playerID);
	else
		LuaEvents.WorldCongress_OpenDiplomacyActionView(playerID);
	end
end

-- ===========================================================================
--	Defines the sizes and bounds of the data container
-- ===========================================================================
function RealizeSize(screenX:number, screenY:number)
	local bannerSize:number = Controls.CongressMembers:GetSizeX() + Controls.CongressMembers:GetOffsetX();
	local dataSize:number;
	if screenX < 1366 then
		dataSize = 1024 - Controls.CongressMembers:GetSizeX();
	elseif screenX < 1920 then
		dataSize = 1366 - Controls.CongressMembers:GetSizeX();
	else
		dataSize = 1640 - Controls.CongressMembers:GetSizeX();
	end

	Controls.TitleContainer:SetSizeX(dataSize);
	Controls.TitleContainer:SetOffsetX(bannerSize);
	Controls.Description:SetWrapWidth(dataSize - 60);
	Controls.DataContainer:SetSizeX(dataSize);
	Controls.DataContainer:SetOffsetX(bannerSize);
	Controls.DataContainer:SetSizeY(screenY - Controls.DataContainer:GetOffsetY());
	Controls.ButtonStack:SetOffsetX(bannerSize * 0.5);

	Controls.LaunchBacking:SetSizeX(Controls.TabBar:GetSizeX() + 144);
	Controls.LaunchBackingTile:SetSizeX(Controls.TabBar:GetSizeX() + 10);
	Controls.LaunchBarDropShadow:SetSizeX(Controls.TabBar:GetSizeX());

	local descriptionSizeY:number = Controls.DescriptionContainer:GetSizeY();
	Controls.DescriptionBG:SetOffsetX(bannerSize);
	Controls.DescriptionBG:SetSizeY(descriptionSizeY);

	local dataSizeY:number = Controls.DataContainer:GetSizeY() - descriptionSizeY - (m_CurrentStage ~= 4 and 72 or 114);
	Controls.ReviewBG:SetSizeY(dataSizeY);
	Controls.ResolutionBG:SetSizeY(dataSizeY);
	Controls.ReviewScroll:SetSizeY(dataSizeY);
	Controls.ResolutionScroll:SetSizeY(dataSizeY);
	Controls.DataStack:CalculateSize();

	local maxTitleWidth:number = (dataSize / 2) + 170 - Controls.WorkingFavor:GetSizeX();
	TruncateStringWithTooltip(Controls.Title, maxTitleWidth, Controls.Title:GetText()); 
end

-- ===========================================================================
-- Shows and hides content relevant to the current stage
-- ===========================================================================
function SetStage(stageNum:number, beginCongress:boolean)

	local prevIsInSession:boolean = m_IsInSession;
	local prevIsEmergencySession:boolean = m_IsEmergencySession;

	m_HasAccepted = false;
	m_CurrentStage = stageNum;
	m_IsInSession = stageNum ~= 4;
	m_IsEmergencySession = stageNum == 2;
	
	if m_IsInSession then
		m_HasSpecialSessionNotification = false;
	end

	m_kProposalVotes = m_kProposalVotes or {};
	m_kResolutionVotes = m_kResolutionVotes or {};
	m_kResolutionChoices = m_kResolutionChoices or {};
	m_StartingFavor = Players[Game.GetLocalPlayer()]:GetFavor();
	UpdateWorkingFavor();

	Controls.ReviewScroll:SetScrollValue(0);
	Controls.ResolutionScroll:SetScrollValue(0);

	Controls.ReviewContainer:SetHide(stageNum ~= 4);
	Controls.ReviewTabsContainer:SetHide(stageNum ~= 4);
	Controls.ResolutionContainer:SetHide(stageNum >= 3);

	if stageNum == 1 then
		Controls.Title:SetText(Locale.Lookup("LOC_WORLD_CONGRESS_TITLE"));
		return beginCongress and SetPhase(m_CurrentPhase > 0 and m_CurrentPhase or 1);
	elseif stageNum == 2 then
		Controls.Title:SetText(Locale.Lookup("LOC_WORLD_CONGRESS_SPECIAL_SESSION_TITLE"));
		Controls.Description:SetText(Locale.Lookup("LOC_WORLD_CONGRESS_SPECIAL_SESSION_INSTRUCTIONS"));
		return beginCongress and SetPhase(m_CurrentPhase > 0 and m_CurrentPhase or 1);
	elseif stageNum == 3 then
		UI.DataError("World Congress Stage 3 is deprecated, assign @sbatista");
		return false;
	elseif stageNum == 4 then
		
		Controls.ReviewResolutionTitle:SetHide(true);

		if prevIsInSession then
			Controls.Title:SetText(Locale.Lookup(prevIsEmergencySession and "LOC_WORLD_CONGRESS_SPECIAL_SESSION_END" or "LOC_WORLD_CONGRESS_END"));
		else
			Controls.Title:SetText(Locale.Lookup("LOC_WORLD_CONGRESS_NOT_IN_SESSION"));
		end

		local pCongressMeetingData:table = Game.GetWorldCongress():GetMeetingStatus();
		local turnsToNextCongress:number = pCongressMeetingData.TurnsLeft + 1;
		Controls.EmptyLabel:SetText(Locale.Lookup("LOC_WORLD_CONGRESS_EMPTY", turnsToNextCongress));

		if m_ReviewTab == REVIEW_TAB_AVAILABLE_PROPOSALS and HasEmergencyProposals() then
			UI.PlaySound("WC_Open");
			Controls.Description:SetText(Locale.Lookup(m_HasSpecialSessionNotification and "LOC_NOTIFICATION_WORLD_CONGRESS_SPECIAL_SESSION_BLOCKING_SUMMARY" or "LOC_WORLD_CONGRESS_AVAILABLE_PROPOSALS_DESCRIPTION"));
			PopulateEmergencyProposals();
		elseif m_ReviewTab == REVIEW_TAB_CURRENT_EFFECTS then
			UI.PlaySound("WC_Open");
			Controls.Description:SetText(Locale.Lookup("LOC_WORLD_CONGRESS_EFFECTS_DESCRIPTION"));
			PopulateActiveEffects();
		elseif m_ReviewTab == REVIEW_TAB_RESULTS then
			UI.PlaySound("WC_Open");
			Controls.Description:SetText(Locale.Lookup("LOC_WORLD_CONGRESS_RESULTS_DESCRIPTION", turnsToNextCongress));
			PopulateReview();
		else
			UI.DataError("Invalid review tab '"..tostring(m_ReviewTab).."'");
			return false;
		end
	else
		UI.DataError("Invalid stage '"..tostring(stageNum).."', it should be 1,2 or 4");
		return false;
	end

	-- If we reach this code, it means congress is not in session (it returns early if stage is 1 - 3)
	-- The EmptyLabel should only show when Congress is not in session and there is no review data
	Controls.EmptyLabel:SetShow(m_ReviewTab ~= REVIEW_TAB_AVAILABLE_PROPOSALS and m_kReviewResolutionIM.m_iAllocatedInstances == 0 and m_kReviewProposalIM.m_iAllocatedInstances == 0);
	Controls.DescriptionBG:SetHide(not m_IsInSession or m_CurrentPhase ~= PHASE_STEP_MAX);

	UpdateNavButtons();
	SRA_RequestAnnounce( true );		-- ScreenReaderAccess
	return true;
end

-- Begin ScreenReaderAccess mod change
-- Spoken when the session has nothing for the local player to vote on and the game submits the turn by itself.
function SRA_SayNoVote()
	local ok:boolean, err = pcall( function()
		local text:string = m_CurrentStage == 2 and "Special session" or "World Congress";
		if m_CurrentStage == 2 then
			local localID:number = Game.GetLocalPlayer();
			for _, crisis in ipairs( Game.GetEmergencyManager():GetEmergencyInfoTable( localID ) ) do
				if crisis.HasBegun then
					local topic:string = crisis.ShortDescriptionText ~= nil and Locale.Lookup( crisis.ShortDescriptionText ) or "";
					local target:string = ( crisis.TargetID ~= nil and PlayerConfigurations[ crisis.TargetID ] ~= nil ) and GetVisiblePlayerName( crisis.TargetID ) or "";
					if topic ~= "" then text = text .. ": " .. topic .. ( target ~= "" and ( " for " .. target ) or "" ); end
					break;
				end
			end
		end
		OutputMessageToScreenReader( CleanTextForSpeech( text ) .. ". You have no vote in this session.", true );
	end );
	if not ok then
		print( "WorldCongress no-vote announce error: " .. tostring( err ) );
		OutputMessageToScreenReader( "You have no vote in this session.", true );
	end
end
-- End ScreenReaderAccess mod change

-- ===========================================================================
-- Shows and hides content relevant to the current phase
-- ===========================================================================
function SetPhase(phaseNum:number)
	if phaseNum < 0 or phaseNum > PHASE_STEP_MAX then
		UI.DataError("Invalid phase '" .. phaseNum .. "', it should be between 1 and " .. PHASE_STEP_MAX);
		return false;
	end

	if(GameConfiguration.IsPaused())then
		UI.DataError("Phase is being set to '" .. phaseNum .. "' while game is paused.");
	end

	m_VerticalPaddingSmallIM:ResetInstances();
	m_CurrentPhase = phaseNum;

	Controls.ResolutionContainer:SetHide(phaseNum ~= 1);

	if phaseNum == 1 then
		Controls.Description:SetText(Locale.Lookup(m_CurrentStage == 1 and "LOC_WORLD_CONGRESS_VOTE_NORMAL_SESSION_DESCRIPTION" or "LOC_WORLD_CONGRESS_VOTE_SPECIAL_SESSION_DESCRIPTION"));
		if m_CurrentStage == 1 then
			PopulateResolutions();
		else
			m_kResolutionsTitle = nil;
			m_kProposalTitleIM:ResetInstances();
			m_kResolutionItemIM:ResetInstances();
		end
		PopulateProposals();

		if HasChoices() then
			m_VerticalPaddingSmallIM:GetInstance(Controls.ResolutionStack);
		else
			-- Begin ScreenReaderAccess mod change: nothing to vote on (e.g. a special session that does not involve us); the game submits silently, so say why
			SRA_SayNoVote();
			-- End ScreenReaderAccess mod change
			UI.RequestPlayerOperation(Game.GetLocalPlayer(), PlayerOperations.WORLD_CONGRESS_SUBMIT_TURN, {});
			UI.RequestAction(ActionTypes.ACTION_ENDTURN);

			if not GameConfiguration.IsHotseat() then
				LuaEvents.WorldCongressPopup_ShowWorldCongressBetweenTurns(m_CurrentStage);
			end
			return false;
		end
	elseif phaseNum == 2 then
		Controls.Description:SetText(Locale.Lookup(m_CurrentStage == 1 and "LOC_WORLD_CONGRESS_SUBMIT_PROPOSALS_CONFIRM" or "LOC_WORLD_CONGRESS_SPECIAL_SESSION_CONFIRM"));
		Controls.ReviewContainer:SetHide(false);
		PopulateSummary();
	end

	-- Set Phase only gets called when congress is in session - hide it
	Controls.EmptyLabel:SetHide(true);
	UpdateNavButtons();
	SRA_RequestAnnounce( true );		-- ScreenReaderAccess
	return true;
end

-- ===========================================================================
--	Can the player do something?
-- ===========================================================================
function HasChoices()
	if not m_IsInSession then
		return HasEmergencyProposals();
	end
	return m_kResolutionItemIM.m_iAllocatedInstances ~= 0 or m_kProposalItemIM.m_iAllocatedInstances ~= 0;
end

-- ===========================================================================
--	Is the player allowed to progress in navigation?
-- ===========================================================================
function CanMoveToNextPhase()
	for _, kVoteData in pairs(m_kResolutionVotes) do
		local choiceData:table = m_kResolutionChoices[kVoteData.Hash];
		if (kVoteData.A.votes + kVoteData.B.votes) <= 0 or not choiceData or (choiceData.choice < 0 or choiceData.target < 0) then
			return false;
		end
	end

	for _, kVoteData in pairs(m_kProposalVotes) do
		if kVoteData.votes == 0 and not (kVoteData.voteBlocker and kVoteData.voteBlocker.NoUpvote and kVoteData.voteBlocker.NoDownvote) then
			return false;
		end
	end

	-- Can not progress while the game is paused.
	if(GameConfiguration.IsPaused()) then
		return false;
	end

	return m_CurrentPhase < PHASE_STEP_MAX;
end

-- ===========================================================================
--	Is the player allowed to submit their choices? Stage 3 only
-- ===========================================================================
function CanSubmit()
	if m_CurrentStage == 4 and m_ReviewTab == REVIEW_TAB_AVAILABLE_PROPOSALS then
		if table.count(m_kProposalVotes) > 0 then
			for _, kVoteData in pairs(m_kProposalVotes) do
				if kVoteData.votes ~= 0 and not kVoteData.disabled then
					return true;
				end
			end
			return false;
		else
			return m_CurrentStage ~= 4;
		end
	end
	return true;
end

-- ===========================================================================
-- Updates the running total of favor for the player
-- ===========================================================================
function UpdateWorkingFavor()
	local totalCost:number = 0;

	for _, kResolutionVote in pairs(m_kResolutionVotes) do
		totalCost = totalCost + kResolutionVote.A.cost + kResolutionVote.B.cost;
	end

	if m_kResolutionsTitle then
		m_kResolutionsTitle.Cost:SetText(Locale.Lookup("LOC_WORLD_CONGRESS_CATEGORY_FAVOR", totalCost));
		m_kResolutionsTitle.Cost:SetToolTipString(Locale.Lookup("LOC_WORLD_CONGRESS_TT_RESOLUTIONS_FAVOR_COST_WITH_REFUND", totalCost));
		
	end

	for _, kProposalVote in pairs(m_kProposalVotes) do
		if not kProposalVote.disabled then
			totalCost = totalCost + kProposalVote.cost;
		end
	end
	
	m_WorkingFavor = m_StartingFavor - totalCost;
	Controls.WorkingFavor:SetText(Locale.Lookup("LOC_WORLD_CONGRESS_FAVOR_TITLE", m_WorkingFavor));
	Controls.WorkingFavor:SetToolTipString(Locale.Lookup("LOC_WORLD_CONGRESS_TT_PLAYER_FAVOR_TO_SPEND"));
end

-- ===========================================================================
-- Updates State of Navigation Buttons
-- ===========================================================================
function UpdateNavButtons()
	Controls.PrevButton:SetHide(m_CurrentStage >= 3 or m_CurrentPhase == 1);

	local canNextPhase = CanMoveToNextPhase();
	local nextButtonTT = "";
	if(GameConfiguration.IsPaused()) then
		nextButtonTT = Locale.Lookup("LOC_WORLD_CONGRESS_TT_GAME_PAUSED")
	elseif(not canNextPhase) then
		nextButtonTT = Locale.Lookup("LOC_WORLD_CONGRESS_TT_SELECT_ALL")
	end
	Controls.NextButton:SetHide(m_CurrentStage >= 3 or m_CurrentPhase == PHASE_STEP_MAX);
	Controls.NextButton:SetDisabled(not canNextPhase);
	Controls.NextButton:SetToolTipString(nextButtonTT);

	if m_CurrentStage == 4 then
		local hasChoices:boolean = HasEmergencyProposalChoices();
		Controls.ReturnButton:SetShow(m_ReviewTab ~= REVIEW_TAB_AVAILABLE_PROPOSALS);
		Controls.AcceptButton:SetShow(hasChoices and m_ReviewTab == REVIEW_TAB_AVAILABLE_PROPOSALS);
		Controls.PassButton:SetShow(hasChoices and m_HasSpecialSessionNotification and m_ReviewTab == REVIEW_TAB_AVAILABLE_PROPOSALS);

		local hasProposals:boolean = HasEmergencyProposals();
		Controls.AvailableProposalsButton:SetHide(not hasProposals);
		Controls.AvailableProposalsButton:SetToolTipString(hasProposals and "" or Locale.Lookup("LOC_WORLD_CONGRESS_NO_AVAILABLE_PROPOSALS_TT"));

		Controls.LastResultsSelected:SetHide(m_ReviewTab ~= REVIEW_TAB_RESULTS);
		Controls.CurrentEffectsSelected:SetHide(m_ReviewTab ~= REVIEW_TAB_CURRENT_EFFECTS);
		Controls.AvailableProposalsSelected:SetHide(m_ReviewTab ~= REVIEW_TAB_AVAILABLE_PROPOSALS);
	else
		Controls.AcceptButton:SetShow(m_CurrentPhase == PHASE_STEP_MAX);
		Controls.ReturnButton:SetShow(false);
		Controls.PassButton:SetShow(false);
	end

	if Controls.AcceptButton:IsVisible() then
		Controls.AcceptButton:SetDisabled(not CanSubmit());
		Controls.AcceptButton:SetToolTipString(Controls.AcceptButton:IsDisabled() and Locale.Lookup("LOC_WORLD_CONGRESS_TT_SELECT_ONE") or "");
		Controls.AcceptButton:SetText(Locale.Lookup(m_HasSpecialSessionNotification and "LOC_WORLD_CONGRESS_ADD_PROPOSALS" or "LOC_WORLD_CONGRESS_SUBMIT"));
		if(GameConfiguration.IsPaused()) then
			Controls.AcceptButton:SetDisabled(true);
			Controls.AcceptButton:SetToolTipString(Locale.Lookup("LOC_WORLD_CONGRESS_TT_GAME_PAUSED"));
		else
			Controls.AcceptButton:SetToolTipString(Locale.Lookup(""));
		end
	end
end

-- ===========================================================================
--	Populates the side bar with the sequence of congress actions we need to 
--	address
-- ===========================================================================
function PopulateLeaderStack()
	
	local kIsUniqueLeader:table = {};
	local localPlayerID:number = Game.GetLocalPlayer();
	local aPlayers:table = PlayerManager.GetAliveMajors();
	local pDiplomacy:table = Players[localPlayerID]:GetDiplomacy();
	local pLocalPlayer:table = PlayerConfigurations[localPlayerID];
	local isLocalPlayerAlive:boolean = pPlayer and pPlayer:IsAlive();

	m_kLeaderButtonIM:ResetInstances();
	
	for _, pPlayer in ipairs(aPlayers) do
		local playerID:number = pPlayer:GetID();
		local pPlayerConfig:table = PlayerConfigurations[playerID];
		local isLocalPlayer:boolean = playerID == localPlayerID;
		local hasMetPlayer:boolean = isLocalPlayer or pDiplomacy:HasMet(playerID) or not isLocalPlayerAlive; -- If local player is dead (and observing), show all leaders
		local instance:table = m_kLeaderButtonIM:GetInstance();
		local uiLeaderIcon:table = LeaderIcon:AttachInstance(instance.Icon);

		
		if hasMetPlayer or (GameConfiguration.IsAnyMultiplayer() and pPlayerConfig:IsHuman()) then
			local leaderName:string = pPlayerConfig:GetLeaderTypeName();
			if (kIsUniqueLeader[leaderName] == nil) then
				kIsUniqueLeader[leaderName] = true;
			else
				kIsUniqueLeader[leaderName] = false;
			end

			uiLeaderIcon:RegisterCallback(Mouse.eLClick, function()
				if playerID == localPlayerID or Players[localPlayerID]:GetDiplomacy():HasMet(playerID) then
					OpenDiplomacyLiteMode(playerID);
				end
			end);

			if hasMetPlayer then
				local favor:number = m_CurrentStage == 4 and pPlayer:GetFavor() or pPlayer:GetFavorEnteringCongress();
				instance.FavorLabel:SetText(Locale.Lookup("LOC_WORLD_CONGRESS_FAVOR", favor));
				instance.FavorLabel:SetToolTipString(Locale.Lookup(playerID == localPlayerID and "LOC_WORLD_CONGRESS_TT_PLAYER_FAVOR" or "LOC_WORLD_CONGRESS_TT_LEADER_FAVOR", favor));
				instance.FavorContainer:SetHide(false);

				local grievanceTT:string = "";
				local grievances:number = pDiplomacy:GetGrievancesAgainst(playerID);
				if grievances > 0 then
					instance.GrievanceLabel:SetText(Locale.Lookup("LOC_WORLD_CONGRESS_GRIEVANCE_VALUE", grievances));
					instance.GrievanceLabel:SetToolTipString(Locale.Lookup("LOC_WORLD_CONGRESS_GRIEVANCE_DEFINITION", grievances));
					instance.GrievanceContainer:SetHide(false);
				else
					instance.GrievanceLabel:SetText("");
					instance.GrievanceContainer:SetHide(true);
				end
			else
				instance.FavorContainer:SetHide(true);
				instance.GrievanceContainer:SetHide(true);
			end

			local icon:string = (isLocalPlayer or pDiplomacy:HasMet(playerID)) and "ICON_" .. leaderName or "ICON_LEADER_DEFAULT";
			uiLeaderIcon:UpdateIcon(icon, playerID, kIsUniqueLeader[leaderName], grievanceTT);
		else
			instance.FavorLabel:SetText("");
			instance.GrievanceLabel:SetText("");
			instance.FavorContainer:SetHide(true);
			instance.GrievanceContainer:SetHide(true);
			uiLeaderIcon:UpdateIcon("ICON_LEADER_DEFAULT", playerID);
		end
	end
end

function PopulateBG()

	m_kLeaderBGItemIM:ResetInstances();

	local counter:number = 0;
	local localPlayerID:number = Game.GetLocalPlayer();
	local aPlayers:table = PlayerManager.GetAliveMajors();
	local numPlayers:number = PlayerManager.GetAliveMajorsCount();
	local pDiplomacy:table = Players[localPlayerID]:GetDiplomacy();

	local width:number = UIManager:GetScreenSizeVal();
	local dataWidth:number = Controls.DataContainer:GetSizeX() + (Controls.CongressMembers:GetSizeX() - 6);
	local leftWidth:number = (width / 2) - (dataWidth / 2);
	local rightWidth:number = width - (leftWidth + Controls.CongressMembers:GetSizeX());
	local numLeftBanners:number = math.ceil(leftWidth / 380);
	local numRightBanners:number = math.ceil(rightWidth / 380);

	-- Populate BG Stack to the Left of CongressMembers
	local i:number = 1
	while i <= numLeftBanners do
		if AddBGElement(aPlayers, (counter % numPlayers) + 1, Controls.BGLeft) then
			i = i + 1;
		end
		counter = counter + 1;
	end
	Controls.BGLeft:SetOffsetX(width - leftWidth);

	-- Populate BG Stack to the Right of CongressMembers
	i = 1
	while i <= numRightBanners do
		if AddBGElement(aPlayers, (counter % numPlayers) + 1, Controls.BGRight) then
			i = i + 1;
		end
		counter = counter + 1;
	end
	Controls.BGRight:SetOffsetX(leftWidth + Controls.CongressMembers:GetSizeX());
end

function AddBGElement(aPlayers:table, aPlayersIndex:number, parentControl:table)
	local localPlayerID:number = Game.GetLocalPlayer();
	local pDiplomacy:table = Players[localPlayerID]:GetDiplomacy();
	local playerID:number = aPlayers[aPlayersIndex]:GetID();
	if playerID == localPlayerID or pDiplomacy:HasMet(playerID) then
		local instance:table = m_kLeaderBGItemIM:GetInstance(parentControl);

		if m_IsInSession then
			local civIconManager:table = CivilizationIcon:AttachInstance(instance);
			civIconManager:UpdateIconFromPlayerID(playerID);
		end
		instance.CivIconBG:SetShow(m_IsInSession);
		instance.CivIconBacking:SetShow(m_IsInSession);

		local screenHeight:number = parentControl:GetSizeY();
		local centerY:number = (screenHeight / 2) - 489;
		instance.Center:SetOffsetY(centerY);
		instance.Top:SetOffsetY(screenHeight - centerY);
		instance.Top:SetSizeY(centerY > 0 and centerY or 1);
		instance.Bottom:SetOffsetY((screenHeight / 2) + 489);
		instance.Bottom:SetSizeY(centerY > 0 and centerY or 1);

		instance.Top:SetTexture(m_IsInSession and (m_IsEmergencySession and "WC_BGBannerTop_Special" or "WC_BGBannerTop_Normal") or "WC_BGBannerTop_NoSession");
		instance.Center:SetTexture(m_IsInSession and (m_IsEmergencySession and "WC_BGBanner_Special" or "WC_BGBanner_Normal") or "WC_BGBanner_NoSession");
		instance.Bottom:SetTexture(m_IsInSession and "WC_BGBannerBottom" or "WC_BGBannerBottom_NoSession");
		return true;
	end
	return false;
end

-- ===========================================================================
--	Populates resolutions (stage 1 & 2, phase 1)
-- ===========================================================================
function PopulateResolutions()
	local focusStop					:number = 0;
	local localPlayerID			:number = Game.GetLocalPlayer();
	local pDiplomacy				:table = Players[localPlayerID]:GetDiplomacy();
	local pWorldCongress		:table = Game.GetWorldCongress();
	local kResolutions			:table = pWorldCongress:GetResolutions(localPlayerID);
	local kCostData					:table = pWorldCongress:GetVotesandFavorCost(localPlayerID);

	m_kProposalTitleIM:ResetInstances();
	m_kResolutionItemIM:ResetInstances();

	for i, kResolutionData in pairs(kResolutions) do
		if type(i) == "number" then -- There's a "Stage" key kResolutions
			if m_kProposalTitleIM.m_iAllocatedInstances == 0 then
				m_kResolutionsTitle = m_kProposalTitleIM:GetInstance(Controls.ResolutionStack);
				m_kResolutionsTitle.Title:SetText(Locale.ToUpper(Locale.Lookup("LOC_WORLD_CONGRESS_RESULTS_WORLD_EVENT_RESOLUTIONS")));
				m_kResolutionsTitle.Icon:SetIcon("ICON_STAT_RESOLUTIONS");
				UpdateWorkingFavor();
			end

			local instance:table = m_kResolutionItemIM:GetInstance();
			local kResolution:table = GameInfo.Resolutions[kResolutionData.Type];
			local kVoteData:table = m_kResolutionVotes[i];
			if not kVoteData then
				local makeData = function(choice)
					return {
						kResolutionData = kResolutionData,
						data = kResolution,
						instance = instance,
						votes = DEBUG_DATA and choice - 1 or 0,
						cost = 0,
						choice = choice,
					};
				end
				kVoteData = {
					A = makeData(1),
					B = makeData(2),
					Hash = kResolution.Hash
				};
				m_kResolutionVotes[i] = kVoteData;
			else -- Refresh instance to support hot reload
				kVoteData.A.instance = instance;
				kVoteData.B.instance = instance;
			end

			UpdateVotingWidget(instance.Vote1, kVoteData.A, kCostData, TestResolutionVote, 1);
			instance.Vote1.UpButton:RegisterCallback(Mouse.eLClick, OnVoteResolution(1, UP_VOTE, kVoteData.A, kCostData));
			instance.Vote1.DownButton:RegisterCallback(Mouse.eLClick, OnVoteResolution(1, DOWN_VOTE, kVoteData.A, kCostData));
			
			UpdateVotingWidget(instance.Vote2, kVoteData.B, kCostData, TestResolutionVote, 2);
			instance.Vote2.UpButton:RegisterCallback(Mouse.eLClick, OnVoteResolution(2, UP_VOTE, kVoteData.B, kCostData));
			instance.Vote2.DownButton:RegisterCallback(Mouse.eLClick, OnVoteResolution(2, DOWN_VOTE, kVoteData.B, kCostData));

			EvaluateResolutionHistory(pWorldCongress, kResolutionData, instance);

			instance.Choice1Container:SetSizeY(kResolutionData.TargetType == "PlayerType" and 65 or 30);
			instance.Choice2Container:SetSizeY(kResolutionData.TargetType == "PlayerType" and 65 or 30);

			if table.count(kResolutionData.FavoredPlayerIDs) > 0 then
				local favoredTT:string = "";
				for _, playerID in pairs(kResolutionData.FavoredPlayerIDs) do
					if favoredTT ~= "" then
						favoredTT = favoredTT .. "[NEWLINE]";
					end
					favoredTT = favoredTT .. GetVisiblePlayerName(playerID);
				end
				instance.FavoredLabel:SetText(table.count(kResolutionData.FavoredPlayerIDs));
				instance.FavoredContainer:SetToolTipString(Locale.Lookup("LOC_WORLD_CONGRESS_PREFERRED_VOTES_TT", favoredTT));
				instance.FavoredContainer:SetHide(false);
				else
				instance.FavoredContainer:SetHide(true);
			end

			if table.count(kResolutionData.DisfavoredPlayerIDs) > 0 then
				local disfavotedTT:string = "";
				for _, playerID in pairs(kResolutionData.DisfavoredPlayerIDs) do
					if disfavotedTT ~= "" then
						disfavotedTT = disfavotedTT .. "[NEWLINE]";
					end
					disfavotedTT = disfavotedTT .. GetVisiblePlayerName(playerID);
				end
				instance.DisfavoredLabel:SetText(table.count(kResolutionData.DisfavoredPlayerIDs));
				instance.DisfavoredContainer:SetToolTipString(Locale.Lookup("LOC_WORLD_CONGRESS_PREFERRED_VOTES_TT", disfavotedTT));
				instance.DisfavoredContainer:SetHide(false);
				else
				instance.DisfavoredContainer:SetHide(true);
			end

			-- Populate choices
			local kResolutionChoice:table = m_kResolutionChoices[kResolution.Hash];
			if not kResolutionChoice then
				kResolutionChoice = {
					instance = instance,
					hash = kResolution.Hash,
					choice = DEBUG_DATA and 1 or -1,
					target = DEBUG_DATA and 1 or -1
				};
				m_kResolutionChoices[kResolution.Hash] = kResolutionChoice;
			else
				kResolutionChoice.instance = instance; -- Refresh instance to support hot reload
			end
			UpdateResolutionChoice(kResolutionChoice);
			
			-- Title
			instance.Title:SetText(Locale.ToUpper(Locale.Lookup(kResolution.Name)));

			-- Icon
			instance.Icon:SetIcon(kResolution.Icon and kResolution.Icon or "ICON_PROPOSAL_RESOLUTION");

			-- A/B Effects
			instance.Effect1:SetText(Locale.Lookup(kResolution.Effect1Description));
			instance.Effect2:SetText(Locale.Lookup(kResolution.Effect2Description));
		end
	end
end

-- ===========================================================================
-- Build the tooltip describing the previous time this resolution appeared
-- in World Congress, if it has shown up before.
-- ===========================================================================
function EvaluateResolutionHistory(pWorldCongress:table, kResolutionData:table, uiResolutionInstance:table)
	if pWorldCongress == nil then
		UI.DataError("World Congress is nil. Something has gone incredibly wrong when Evaluating Resolution History.");
		return;
	end

	--Get the stats for the last time this resolution was seen
	if kResolutionData ~= nil then
		local kPreviousResolutionData:table = pWorldCongress:GetPreviousVotesOnResolution(kResolutionData.Type);
		if kPreviousResolutionData == nil then
			uiResolutionInstance.MoreInfoButton:SetHide(true);
			uiResolutionInstance.MoreInfoButton:SetToolTipString("");
			return;
		end

		uiResolutionInstance.MoreInfoButton:SetHide(false);

		--Our data format for evaluation
		local kEvaluationData:table = {
			aVotes = 0, 
			bVotes = 0,
			aVoters = 0,
			bVoters = 0,
			soleAPlayerID = -1,
			soleBPlayerID = -1,
			biggestAVotes = 0,
			biggestBVotes = 0,
			biggestAVoter = -1,
			biggestBVoter = -1
		};

		--Generate data
		for playerID, kData in pairs(kPreviousResolutionData.PlayerSelections) do
			if kData.OptionChosen == 1 then
				kEvaluationData.aVotes = kEvaluationData.aVotes + kData.Votes;
				kEvaluationData.aVoters = kEvaluationData.aVoters + 1;
				kEvaluationData.soleAPlayerID = playerID;
				if kData.Votes > kEvaluationData.biggestAVotes then
					kEvaluationData.biggestAVotes = kData.Votes;
					kEvaluationData.biggestAVoter = playerID;
				end
			else
				kEvaluationData.bVotes = kEvaluationData.bVotes + kData.Votes;
				kEvaluationData.bVoters = kEvaluationData.bVoters + 1;
				kEvaluationData.soleBPlayerID = playerID;
				if kData.Votes > kEvaluationData.biggestBVotes then
					kEvaluationData.biggestBVotes = kData.Votes;
					kEvaluationData.biggestBVoter = playerID;
				end
			end
		end

		--Go through all of our evaluators and append to the tooltip string
		local chosenThingString:string = Locale.Lookup(kPreviousResolutionData.ChosenThing);
		if kPreviousResolutionData.TargetType == "PlayerType" then
			local playerID:number = tonumber(kPreviousResolutionData.ChosenThing);
			if playerID ~= PlayerTypes.NONE and playerID ~= PlayerTypes.OBSERVER then
				chosenThingString = GetVisiblePlayerName(playerID);
			end
		end
		local tooltipString:string = kEvaluationData.aVotes > kEvaluationData.bVotes and Locale.Lookup("LOC_WORLD_CONGRESS_PREVIOUS_TOOLTIP_A_WON", chosenThingString) or Locale.Lookup("LOC_WORLD_CONGRESS_PREVIOUS_TOOLTIP_B_WON", chosenThingString);
		for _, evaluate in pairs(m_kPreviousTooltipEvaluators) do
			tooltipString = tooltipString .. evaluate(kEvaluationData);
		end

		uiResolutionInstance.MoreInfoButton:SetToolTipString(tooltipString);
	else
		UI.DataError("Resolution Data is nil! World Congress unable to evaluate Resolution History");
		return;
	end
end

-- ===========================================================================
function EvaluateTiebroken(kEvaluationData:table)
	--Evaluate if the last round was decided by tiebreaker
	return kEvaluationData.aVotes == kEvaluationData.bVotes and "[NEWLINE]" .. Locale.Lookup("LOC_WORLD_CONGRESS_PREVIOUS_TOOLTIP_WAS_TIE") or "";
end

-- ===========================================================================
function EvaluateSoleVoter(kEvaluationData:table)
	--Did a category only have a single voter?
	local soleVoterString:string = "";

	if kEvaluationData.aVoters == 1 then
		soleVoterString = soleVoterString .. "[NEWLINE]" .. Locale.Lookup("LOC_WORLD_CONGRESS_PREVIOUS_TOOLTIP_A_SOLE_VOTE", GetVisiblePlayerName(kEvaluationData.soleAPlayerID));
	end

	if kEvaluationData.bVoters == 1 then
		soleVoterString = soleVoterString .. "[NEWLINE]" .. Locale.Lookup("LOC_WORLD_CONGRESS_PREVIOUS_TOOLTIP_B_SOLE_VOTE", GetVisiblePlayerName(kEvaluationData.soleBPlayerID));
	end

	return soleVoterString;
end

-- ===========================================================================
function EvaluateNeckAndNeck(kEvaluationData:table)
	--Evaluate if the voting was close
	local voteDelta:number = math.abs(kEvaluationData.aVotes - kEvaluationData.bVotes);
	local voteMargin:number = voteDelta / math.ceil(kEvaluationData.aVotes, kEvaluationData.bVotes);
	
	if voteMargin <= GlobalParameters.WORLD_CONGRESS_NEARLY_TIED_RANGE / 100 then
		return "[NEWLINE]" .. (kEvaluationData.aVotes > kEvaluationData.bVotes and Locale.Lookup("LOC_WORLD_CONGRESS_PREVIOUS_TOOLTIP_NECK_AND_NECK_A") or Locale.Lookup("LOC_WORLD_CONGRESS_PREVIOUS_TOOLTIP_NECK_AND_NECK_B"));
	end

	return "";
end

-- ===========================================================================
function EvaluateUnanimous(kEvaluationData:table)
	--Was the decision unanimous?
	if kEvaluationData.aVoters > 0 and kEvaluationData.bVoters == 0 then
		return "[NEWLINE]" .. Locale.Lookup("LOC_WORLD_CONGRESS_PREVIOUS_TOOLTIP_UNANIMOUS_A");
	end

	if kEvaluationData.aVoters == 0 and kEvaluationData.bVoters > 0 then
		return  "[NEWLINE]" .. Locale.Lookup("LOC_WORLD_CONGRESS_PREVIOUS_TOOLTIP_UNANIMOUS_B");
	end

	return "";	
end

-- ===========================================================================
function EvaluateMajorityLeader(kEvaluationData:table)
	--Was one player outstanding in their contribution?
	local majorityString:string = "";
	local aVoteMargin:number = -1;
	local bVoteMargin:number = -1;

	if kEvaluationData.aVotes > 0 then
		aVoteMargin = kEvaluationData.biggestAVotes / kEvaluationData.aVotes;
	end

	if kEvaluationData.bVotes > 0 then
		bVoteMargin = kEvaluationData.biggestBVotes / kEvaluationData.bVotes;
	end

	if aVoteMargin > GlobalParameters.WORLD_CONGRESS_MAJORITY_LEADER_MINIMUM then
		majorityString = majorityString .. "[NEWLINE]" .. Locale.Lookup("LOC_WORLD_CONGRESS_PREVIOUS_TOOLTIP_MAJORITY_A", GetVisiblePlayerName(kEvaluationData.biggestAVoter));
	end

	if bVoteMargin > GlobalParameters.WORLD_CONGRESS_MAJORITY_LEADER_MINIMUM then
		majorityString = majorityString .. "[NEWLINE]" .. Locale.Lookup("LOC_WORLD_CONGRESS_PREVIOUS_TOOLTIP_MAJORITY_B", GetVisiblePlayerName(kEvaluationData.biggestBVoter));
	end

	return majorityString;
end

-- ===========================================================================
function PopulateChoicePulldown(kResolutionChoice:table, kVoteData:table)
	local kResolutionData:table = kVoteData.kResolutionData;
	local instance:table = kResolutionChoice.choice == 1 and kVoteData.instance.Choice1 or kVoteData.instance.Choice2;

	if kResolutionData.TargetType == "PlayerType" then
		instance.Pulldown:SetHide(true);
		instance.PlayerPulldown:SetHide(false);
		instance.PlayerPulldown:GetButton():RegisterCallback(Mouse.eLClick, function() AssignActivePulldown(instance.PlayerPulldown); end);

		local metPlayers, isUniqueLeader = GetMetPlayersAndUniqueLeaders();
		 
		instance.PlayerPulldown:ClearEntries();
		kResolutionChoice.sraTargets = {};		-- ScreenReaderAccess
		local possibleTargets:table = kResolutionData.PossibleTargets;
		if possibleTargets and table.count(possibleTargets) > 0 then
			for i, v in pairs(possibleTargets) do
				local playerID:number = tonumber(v);
				local entry:table = {};
				instance.PlayerPulldown:BuildEntry( "InstanceOne", entry );

				entry.Button:SetVoid1(i);
				local text, leaderIcon, civIcon = GetPulldownNameAndIcons(kResolutionData, i );
				entry.Button:SetText(text);
				table.insert( kResolutionChoice.sraTargets, { text = text, a1 = i, id = i } );		-- ScreenReaderAccess

				local civIconManager:table = CivilizationIcon:AttachInstance(entry.CivIcon);
				civIconManager:UpdateIconFromPlayerID(playerID);
				local leaderIconManager:table = LeaderIcon:AttachInstance(entry.LeaderIcon);
				leaderIconManager:UpdateIconSimple(leaderIcon, playerID, isUniqueLeader[playerID] or false);
			end
			instance.PlayerPulldown:CalculateInternals(); -- Is this still necessary? @kjones
		else
			UI.DataError("Resolution choice of Type '" .. kResolution.Type .. "' has no PossibleTargets -  aborting WorldCongress");
		end

		local tmpID:number = tonumber(kResolutionChoice.target);
		local playerID:number = tmpID < 0 and -1 or tonumber(kResolutionData.PossibleTargets[tmpID]);
		local text, leaderIcon, civIcon = GetPulldownNameAndIcons(kResolutionData, kResolutionChoice.target );

		local civIconManager:table = CivilizationIcon:AttachInstance(instance.CivIcon);
		civIconManager:UpdateIconFromPlayerID(playerID);
		local leaderIconManager:table = LeaderIcon:AttachInstance(instance.LeaderIcon);
		leaderIconManager:UpdateIconSimple(leaderIcon, playerID, isUniqueLeader[playerID] or false);

		instance.PlayerPulldown:GetButton():SetText(text);
		instance.PlayerPulldown:GetButton():SetToolTipString(Locale.Lookup("LOC_WORLD_CONGRESS_TT_NO_VOTING_DOWN"));
		kResolutionChoice.sraSelect = function(i)		-- ScreenReaderAccess: kept so the keyboard can call it
			local playerID:number = tonumber(kResolutionData.PossibleTargets[i]);
			kResolutionChoice.target = i;
			local text, leaderIcon, civIcon = GetPulldownNameAndIcons(kResolutionData, i );
			instance.PlayerPulldown:GetButton():SetText(text);
			instance.PlayerPulldown:GetButton():SetToolTipString("");

			local civIconManager:table = CivilizationIcon:AttachInstance(instance.CivIcon);
			civIconManager:UpdateIconFromPlayerID(playerID);
			local leaderIconManager:table = LeaderIcon:AttachInstance(instance.LeaderIcon);
			leaderIconManager:UpdateIconSimple(leaderIcon, playerID, isUniqueLeader[playerID] or false);

			UpdateResolutionChoice(kResolutionChoice);
			UpdateNavButtons();
		end;
		instance.PlayerPulldown:RegisterSelectionCallback(kResolutionChoice.sraSelect);		-- ScreenReaderAccess
	else--kResolutionData.TargetType ~= "PlayerType"
		instance.Pulldown:SetHide(false);
		instance.PlayerPulldown:SetHide(true);
		instance.Pulldown:GetButton():RegisterCallback(Mouse.eLClick, function() AssignActivePulldown(instance.Pulldown); end);

		instance.Pulldown:ClearEntries();
		kResolutionChoice.sraTargets = {};		-- ScreenReaderAccess
		instance.Pulldown:GetButton():SetToolTipString(Locale.Lookup("LOC_WORLD_CONGRESS_TT_NO_VOTING_DOWN"));
				
		-- Dup for sorting and save index order of targets in a reverse lookup table.
		local kSortedTargets:table = {};
		local kSortedIndex	:table = {};
		local kGameIndexToName	:table = {};	-- game core's index to name
		for i,targetName in ipairs(kResolutionData.PossibleTargets) do
			table.insert( kSortedTargets, targetName );
			kSortedIndex[targetName] = i;
			kGameIndexToName[i] = targetName;
		end
		
		--Sort based on name
		table.sort(kSortedTargets, function(a, b)
			return Locale.Lookup(a) < Locale.Lookup(b); 
		end);
		if kSortedTargets and table.count(kSortedTargets) > 0 then
			for pulldownIndex, name in ipairs(kSortedTargets) do
				local entry:table = {};
				instance.Pulldown:BuildEntry( "InstanceOne", entry );
				entry.Button:SetVoid1( pulldownIndex );
				entry.Button:SetVoid2( kSortedIndex[name] );
				local text = Locale.Lookup( kSortedTargets[pulldownIndex] );
				entry.Button:SetText(text);
				table.insert( kResolutionChoice.sraTargets, { text = text, a1 = pulldownIndex, a2 = kSortedIndex[name], id = kSortedIndex[name] } );		-- ScreenReaderAccess
			end
			instance.Pulldown:CalculateInternals();
		else
			UI.DataError("Resolution choice of Type '" .. kResolution.ResolutionType .. "' has no PossibleTargets");
		end
		
		if kResolutionChoice.target == nil or kResolutionChoice.target < 0 then
			instance.Pulldown:GetButton():SetText( Locale.Lookup("LOC_WORLD_CONGRESS_SELECT_TARGET") );
			instance.Pulldown:GetButton():SetToolTipString(Locale.Lookup("LOC_WORLD_CONGRESS_TT_NO_VOTING_DOWN"));
		else
			local gameIndex:number = kResolutionChoice.target;		-- Game core's index
			local name	:string = kGameIndexToName[ gameIndex ];	-- sorted index lookup
			instance.Pulldown:GetButton():SetText( Locale.Lookup( name ) );
			instance.Pulldown:GetButton():SetToolTipString("");
		end
				
		kResolutionChoice.sraSelect = 		-- ScreenReaderAccess: kept so the keyboard can call it
			function( pulldownIndex:number, gameIndex:number )
				kResolutionChoice.target = gameIndex;
				local text:string = Locale.Lookup( kSortedTargets[pulldownIndex] );
				instance.Pulldown:GetButton():SetText(text);
				instance.Pulldown:GetButton():SetToolTipString("");			
				UpdateResolutionChoice( kResolutionChoice );
				UpdateNavButtons();
			end;
		instance.Pulldown:RegisterSelectionCallback( kResolutionChoice.sraSelect );		-- ScreenReaderAccess
	end
end

-- ===========================================================================
function GetPulldownNameAndIcons(kResolutionData:table, index:number )
	if index == nil or index < 0 then
		return Locale.Lookup("LOC_WORLD_CONGRESS_SELECT_TARGET"), "ICON_LEADER_DEFAULT", "ICON_CIVILIZATION_UNKNOWN";
	end

	-- If target type is the player type then either use index to obtain target index or itself is the index:
	if kResolutionData.TargetType == "PlayerType" then
		local playerID:number = kResolutionData.PossibleTargets and tonumber(kResolutionData.PossibleTargets[index]) or index;
		return GetVisiblePlayerNameAndIcons( playerID );
	end

	-- Only returning a name (no icons), the possible targets actually holds unlocalized names.
	return Locale.Lookup(kResolutionData.PossibleTargets[index]);	
end

-- ===========================================================================
function OnLeaderClicked(playerID : number )
	-- Send an event to open the leader in the diplomacy view (only if they met)
	local localPlayerID:number = Game.GetLocalPlayer();
	if playerID == localPlayerID or Players[localPlayerID]:GetDiplomacy():HasMet(playerID) then
		LuaEvents.WorldCongress_OpenDiplomacyActionView( playerID );
	end
end

-- ===========================================================================
--	Generate a callback that updates kVoteData according to boxed parameters 
-- ===========================================================================
function OnVoteResolution(choice:number, direction:number, kVoteData:table, kCostData:table, isTest:boolean)
	return function()
		local nextVotes:number = kVoteData.votes + direction;
		if nextVotes < 1 or nextVotes > table.count(kCostData) or nextVotes > kCostData.MaxVotes then return; end
		
		local nextCost:number = kCostData[nextVotes - 1];
		local currCost:number = kVoteData.votes > 0 and kCostData[kVoteData.votes - 1] or 0;

		if direction < 0 or (nextCost - currCost) <= m_WorkingFavor then
			kVoteData.votes = nextVotes;

			if kVoteData.votes == 0 then
				kVoteData.voteDirection = NO_VOTE;
				kVoteData.cost = 0;
			else
				kVoteData.cost = kCostData[nextVotes > 0 and nextVotes - 1 or 0];
			end
		end
		
		if not isTest then
			local kChoiceData:table = m_kResolutionChoices[kVoteData.data.Hash];
			
			-- Reset target selection if player chooses a different option
			if kChoiceData.choice ~= choice then
				kChoiceData.target = -1;
			end

			kChoiceData.choice = choice;
			UpdateResolutionChoice(kChoiceData);
			PopulateChoicePulldown(kChoiceData, kVoteData);

			for _, kVoteData in pairs(m_kResolutionVotes) do
				kChoiceData = m_kResolutionChoices[kVoteData.Hash];
				if kChoiceData.choice == 1 then
					kVoteData.B.votes = 0;
					kVoteData.B.cost = 0;
				else
					kVoteData.A.votes = 0;
					kVoteData.A.cost = 0;
				end
			end

			UpdateWorkingFavor();
			UpdateNavButtons();
			UpdateAllVotingWidgets(kCostData);
		end
	end
end

-- ===========================================================================
--	Generates a callback that tests whether a vote is successful
-- ===========================================================================
function TestResolutionVote(choice:number, direction:number, kVoteData:table, kCostData:table)
	local kCopyData:table = { votes = kVoteData.votes, cost = kVoteData.cost };
	OnVoteResolution(choice, direction, kCopyData, kCostData, true)();
	return kCopyData.votes ~= kVoteData.votes or kCopyData.cost ~= kVoteData.cost;
end

-- ===========================================================================
--	Debug helper
-- ===========================================================================
function TableToString( t:table )
	local s:string = "";
	if t==nil then return "NIL" end	
	for k,v in pairs(t) do
		s = s..tostring(k).." = "..tostring(v).." \n";
	end
	return s;
end

-- ===========================================================================
--	Update a voting widget
-- ===========================================================================
function UpdateVotingWidget(instance:table, kVoteData:table, kCostData:table, TestVoteCallback:ifunction, resolutionChoice:number)

	if instance == nil then
		local msg:string = "Unable to UpdateVotingWidget due to nil instance.\n";
		msg = msg.."=== kVoteData === \n"..TableToString( kVoteData );
		msg = msg.."=== kCostData === \n"..TableToString( kCostData );
		UI.DataError(msg);
		return;
	end
	
	-- Make sure we have a vote direction
	kVoteData.voteDirection = kVoteData.voteDirection and kVoteData.voteDirection or 1;

	local voteIcon:string = kVoteData.voteDirection < 0 and "[ICON_VOTE_DOWN]" or "[ICON_VOTE_UP]";
	local voteTooltip:string = Locale.Lookup("LOC_WORLD_CONGRESS_TT_VOTE_COST", kVoteData.voteDirection < 0 and "[ICON_VOTE_DOWN]" or "[ICON_VOTE_UP]", kVoteData.votes, kVoteData.cost);

	instance.Label:SetText(kVoteData.votes == 0 and "0" or (voteIcon .. kVoteData.votes));
	instance.Label:SetToolTipString(voteTooltip);
	
	-- This check may become unnecessary once we only have 1 voting widget - sbatista
	if instance.Cost then
		instance.Cost:SetText(kVoteData.cost ~= 0 and Locale.Lookup("LOC_WORLD_CONGRESS_FAVOR", kVoteData.cost) or "");
		instance.Cost:SetToolTipString(voteTooltip);
	end

	if TestVoteCallback then
		if resolutionChoice then
			instance.UpButton:SetDisabled(not TestVoteCallback(resolutionChoice, UP_VOTE, kVoteData, kCostData));
			instance.DownButton:SetDisabled(not TestVoteCallback(resolutionChoice, DOWN_VOTE, kVoteData, kCostData));
		else
			instance.UpButton:SetDisabled(not TestVoteCallback(UP_VOTE, kVoteData, kCostData));
			instance.DownButton:SetDisabled(not TestVoteCallback(DOWN_VOTE, kVoteData, kCostData));
		end
	end

	local cost:number = 0;
	local tooltip:string = "";
	local nextVotes:number = kVoteData.votes + kVoteData.voteDirection;
	if nextVotes < table.count(kCostData) then
		if kVoteData.voteDirection > 0  then
			cost = kCostData[nextVotes > 0 and nextVotes - 1 or 0] - kVoteData.cost;
		else
			cost = kVoteData.cost - kCostData[nextVotes > 0 and nextVotes - 1 or 0];
		end
		if cost ~= 0 then
			if instance.UpButton:IsDisabled() then
				tooltip = Locale.Lookup("LOC_WORLD_CONGRESS_TT_INSUFFICIENT_FAVOR_COST", cost);
			else
				tooltip = Locale.Lookup(kVoteData.voteDirection >= 0 and "LOC_WORLD_CONGRESS_TT_VOTE_UP" or "LOC_WORLD_CONGRESS_TT_VOTE_DOWN", cost);
			end
		end
	end
	instance.UpCost:SetText(cost == 0 and " " or Locale.Lookup("LOC_WORLD_CONGRESS_FAVOR", cost * (kVoteData.voteDirection < 0 and -1 or 1)));
	instance.UpButton:SetToolTipString(tooltip);
	
	cost = 0;
	tooltip = "";
	local prevVotes:number = kVoteData.votes - kVoteData.voteDirection;
	if prevVotes < table.count(kCostData) then
		if kVoteData.voteDirection > 0  then
			cost = kVoteData.cost - kCostData[prevVotes > 0 and prevVotes - 1 or 0];
		else
			cost = kCostData[prevVotes > 0 and prevVotes - 1 or 0] - kVoteData.cost;
		end
		if cost ~= 0 then
			if instance.DownButton:IsDisabled() then
				tooltip = Locale.Lookup("LOC_WORLD_CONGRESS_TT_INSUFFICIENT_FAVOR_COST", cost);
			else
				tooltip = Locale.Lookup(kVoteData.voteDirection >= 0 and "LOC_WORLD_CONGRESS_TT_VOTE_DOWN" or "LOC_WORLD_CONGRESS_TT_VOTE_UP", cost);
			end
		end
	end
	instance.DownCost:SetText(cost == 0 and " " or Locale.Lookup("LOC_WORLD_CONGRESS_FAVOR", cost * (kVoteData.voteDirection > 0 and -1 or 1)));
	instance.DownButton:SetToolTipString(tooltip);

	if kVoteData.voteBlocker then
		if kVoteData.voteBlocker.NoUpvote and kVoteData.voteBlocker.NoDownvote then
			instance.UpButton:SetDisabled(true);
			instance.DownButton:SetDisabled(true);
			instance.UpButton:SetToolTipString(Locale.Lookup(kVoteData.voteBlocker.Description));
			instance.DownButton:SetToolTipString(Locale.Lookup(kVoteData.voteBlocker.Description));
		elseif kVoteData.voteBlocker.NoUpvote and kVoteData.votes == 0 then
			instance.UpButton:SetDisabled(true);
			instance.UpButton:SetToolTipString(Locale.Lookup(kVoteData.voteBlocker.Description));
		elseif kVoteData.voteBlocker.NoDownvote and kVoteData.votes == 0 then
			instance.DownButton:SetDisabled(true);
			instance.DownButton:SetToolTipString(Locale.Lookup(kVoteData.voteBlocker.Description));
		end
	end

	if kVoteData.votes == 0 then
		if not kVoteData.voteBlocker or not kVoteData.voteBlocker.NoUpvote then
			instance.UpButton:SetToolTipString(Locale.Lookup(resolutionChoice and "LOC_WORLD_CONGRESS_TT_NO_VOTING_DOWN" or "LOC_WORLD_CONGRESS_TT_PLEASE_VOTE_FOR"));
		end
		if not kVoteData.voteBlocker or not kVoteData.voteBlocker.NoDownvote then
			local bIsTarget:boolean = kVoteData.data.Target == Game.GetLocalPlayer();
			if bIsTarget then
				instance.DownButton:SetToolTipString(Locale.Lookup("LOC_WORLD_CONGRESS_TT_PLEASE_VOTE_AGAINST_TARGET"));
			else
				instance.DownButton:SetToolTipString(Locale.Lookup(resolutionChoice and "" or "LOC_WORLD_CONGRESS_TT_PLEASE_VOTE_AGAINST"));
			end
		end
	end
end

-- ===========================================================================
--	Updates all voting widgets
-- ===========================================================================
function UpdateAllVotingWidgets( kCostData:table )
	for _, kVoteData in pairs(m_kResolutionVotes) do
		UpdateVotingWidget(kVoteData.A.instance.Vote1, kVoteData.A, kCostData, TestResolutionVote, 1);
		UpdateVotingWidget(kVoteData.B.instance.Vote2, kVoteData.B, kCostData, TestResolutionVote, 2);
	end
	for _, kVoteData in pairs(m_kProposalVotes) do
		UpdateVotingWidget(kVoteData.instance.Vote, kVoteData, kCostData, TestProposalVote);
	end
end

-- ===========================================================================
-- Populate proposal items (stage 1 & 2, phase 2)
-- TODO: Merge this with PopulateResolutions
--			 Maybe name it PopulateStandardCongress
-- ===========================================================================
function PopulateProposals()
	m_kProposalItemIM:ResetInstances();

	local kSortedCategories:table = GetSortedProposalCategories(Game.GetWorldCongress():GetProposals(Game.GetLocalPlayer()).Proposals);

	for _, kSorted in ipairs(kSortedCategories) do
		local proposalType:number = kSorted.type;
		local kProposalDef:table = kSorted.kData;
		local kProposalCategory:table = kSorted.kCategory;

		local titleInstance:table = m_kProposalTitleIM:GetInstance(Controls.ResolutionStack);
		local kCategoryProposals:table = kProposalCategory.ProposalsOfType;

		local updateFn:ifunction = function() UpdateCategoryTitle(titleInstance, kCategoryProposals, kProposalDef); end
		if PopulateProposalStack(kCategoryProposals, m_kProposalItemIM, kProposalCategory, updateFn) > 0 then
			updateFn();
		else
			titleInstance.Root:SetHide(true);
		end
	end
end

function GetCostOfProposals(kProposals:table)
	local total:number = 0;
	for _, kProposal in pairs(kProposals) do
		local kVoteData:table = m_kProposalVotes[GetProposalVoteKey(kProposal)];
		total = total + (kVoteData and  kVoteData.cost or 0);
	end
	return total;
end

function UpdateSenderTitle(instance:table, titleInstance:table, kProposals:table, kCategoryProposals:table, kProposalDef:table, pPlayerConfig:table)
	local total:number = GetCostOfProposals(kProposals);
	local leaderName:string = Locale.Lookup(pPlayerConfig:GetLeaderName());
	instance.Cost:SetText(Locale.Lookup("LOC_WORLD_CONGRESS_CATEGORY_FAVOR", total));
	instance.Cost:SetToolTipString(Locale.Lookup((not m_IsInSession and m_ReviewTab == REVIEW_TAB_AVAILABLE_PROPOSALS) and "LOC_WORLD_CONGRESS_TT_DISCUSIONS_FAVOR_COST_NO_REFUND" or "LOC_WORLD_CONGRESS_TT_DISCUSIONS_FAVOR_COST_WITH_REFUND", total));
	instance.Title:SetText(Locale.ToUpper(Locale.Lookup("LOC_WORLD_CONGRESS_PROPOSED_BY", leaderName)));
	UpdateCategoryTitle(titleInstance, kCategoryProposals, kProposalDef);
end

function UpdateCategoryTitle(instance:table, kProposals:table, kProposalDef:table, costEach:number)
	local total:number = costEach or GetCostOfProposals(kProposals);
	instance.Cost:SetText(Locale.Lookup("LOC_WORLD_CONGRESS_CATEGORY_FAVOR", total));
	instance.Cost:SetToolTipString(Locale.Lookup((not m_IsInSession and m_ReviewTab == REVIEW_TAB_AVAILABLE_PROPOSALS) and "LOC_WORLD_CONGRESS_TT_DISCUSIONS_FAVOR_COST_NO_REFUND" or "LOC_WORLD_CONGRESS_TT_DISCUSIONS_FAVOR_COST_WITH_REFUND", total));
	instance.Title:SetText(Locale.ToUpper(Locale.Lookup(kProposalDef.Name)));
	instance.Icon:SetIcon("ICON_" .. kProposalDef.ProposalType);
end

function PopulateProposalStack(kProposals:table, kProposalIM:table, kProposalCategory:table, updateTitleFn:ifunction)
	local numAllocated:number = 0;
	local metPlayers:table = nil;
	local isUniqueLeader:table = nil;
	local localPlayerID:number = Game.GetLocalPlayer();
	local pDiplomacy:table = Players[localPlayerID]:GetDiplomacy();
	local pEmergencyManager:table = Game.GetEmergencyManager();

	if m_IsInSession and not kProposalCategory.FavorCost then
		kProposalCategory.FavorCost = Game.GetWorldCongress():GetVotesandFavorCost(localPlayerID);
	end

	for _, kProposal in pairs(kProposals) do
		-- Create proposal vote data
		local voteKey:string = GetProposalVoteKey(kProposal);
		local kVoteData:table = m_kProposalVotes[voteKey];
		if not kVoteData then
			kVoteData = {
				cost = 0,
				votes = kProposal.Disabled and 1 or DEBUG_DATA and 1 or 0,
				data = kProposal,
				voteDirection = NO_VOTE,
				disabled = kProposal.Disabled and true or false,
				voteBlocker = kProposal.VotingRestriction and GameInfo.VotingBlockers[kProposal.VotingRestriction] or nil,
				proposalBlocker = kProposal.ProposalBlockerType and GameInfo.ProposalBlockers[kProposal.ProposalBlockerType] or nil
			};
		end

		local canVote:boolean = not kVoteData.disabled and not (kVoteData.voteBlocker and kVoteData.voteBlocker.NoUpvote and kVoteData.voteBlocker.NoDownvote);
		if canVote or (not m_IsInSession and m_ReviewTab == REVIEW_TAB_AVAILABLE_PROPOSALS) then
			numAllocated = numAllocated + 1;
			local instance:table = kProposalIM:GetInstance();
			
			-- Only store vote data for proposals players can vote on
			kVoteData.instance = instance;
			m_kProposalVotes[voteKey] = kVoteData;
			kVoteData.sraFavorCost = kProposalCategory.FavorCost;		-- ScreenReaderAccess

			-- This allows us to update the total cost 
			instance.UpdateTitle = updateTitleFn;

			if not metPlayers then
				metPlayers, isUniqueLeader = GetMetPlayersAndUniqueLeaders();
			end

			-- Target Icon
			local pIconManager:table = LeaderIcon:AttachInstance(instance.LeaderIcon);
			local pPlayerConfig:table = PlayerConfigurations[kProposal.Target];
			if pPlayerConfig then
				local playerTypeName:string = pPlayerConfig:GetLeaderTypeName();
				local isLocalPlayer:boolean = kProposal.Target == localPlayerID;		
				local name, leaderIcon, civIcon = GetVisiblePlayerNameAndIcons( kProposal.Target );		
				pIconManager:UpdateIconSimple(leaderIcon, kProposal.Target, isUniqueLeader[kProposal.Target] or false, Locale.Lookup("LOC_WORLD_CONGRESS_TARGET_PROPOSAL_TT"));
				instance.Title:SetText(Locale.ToUpper(Locale.Lookup(kProposal.Name, name)));
				instance.Description:SetText(Locale.Lookup(kProposal.Description, name));
				instance.LeaderIcon.SelectButton:SetHide(false);
				instance.LeaderIcon.TargetIcon:SetColor(kProposal.TypeName == "WC_EMERGENCY_REQUEST_AID" and COLOR_GREEN or COLOR_RED);
				instance.LeaderIcon.TargetIcon:SetTexture(kProposal.TypeName == "WC_EMERGENCY_REQUEST_AID" and "Emergency_TargetAid44" or "Emergency_Target44");
				instance.TypeIcon:SetHide(true);
			else
				instance.Title:SetText(Locale.ToUpper(Locale.Lookup(kProposal.Name)));
				instance.Description:SetText(Locale.Lookup(kProposal.Description));
				instance.LeaderIcon.SelectButton:SetHide(true);
				instance.TypeIcon:SetIcon("ICON_" .. kProposal.TypeName);
				instance.TypeIcon:SetHide(false);
			end

			if not m_IsInSession and m_ReviewTab == REVIEW_TAB_AVAILABLE_PROPOSALS then
				instance.ExpandButton:RegisterCallback(Mouse.eLClick, function()
					UI.PlaySound("Main_Main_Panel_Collapse"); 
					instance.isCollapsed = not instance.isCollapsed;
					RealizeCollapseableProposal(instance);
				end);
 				instance.ExpandButton:RegisterCallback(Mouse.eMouseEnter, function() UI.PlaySound("Main_Menu_Mouse_Over"); end);

				instance.isCollapsed = true;
				RealizeCollapseableProposal(instance);
				PopulateEmergencyData(instance, kVoteData.data.Target, kVoteData.data.EmergencyType);

				UpdateAvailableProposal(kVoteData, kProposalCategory);
				kVoteData.sraToggle = OnToggleProposal(instance, kProposal, kProposalCategory);		-- ScreenReaderAccess
				instance.SelectBox:RegisterCallback(Mouse.eLClick, kVoteData.sraToggle);
			else
				UpdateProposal(kVoteData);
				local kCostData = kProposalCategory.FavorCost;
				kVoteData.sraCostData = kCostData;		-- ScreenReaderAccess
				UpdateVotingWidget(instance.Vote, kVoteData, kCostData, TestProposalVote);
				instance.Vote.UpButton:RegisterCallback(Mouse.eLClick, OnVoteProposal(UP_VOTE, kVoteData, kCostData));
				instance.Vote.DownButton:RegisterCallback(Mouse.eLClick, OnVoteProposal(DOWN_VOTE, kVoteData, kCostData));

				-- Emergency Data
				if m_IsInSession or m_ReviewTab ~= REVIEW_TAB_AVAILABLE_PROPOSALS then
					PopulateEmergencyData(instance, kProposal.Target, kProposal.EmergencyType);
					instance.EmergencyContainer:SetHide(false);
					instance.EmergencyButton:SetHide(true);
				end
			end
		end
	end
	return numAllocated;
end

-- ===========================================================================
function PopulateEmergencyData(instance:table, emergencyTarget:number, emergencyType:number)
	local emergency = Game.GetEmergencyManager():GetSingleEmergency(emergencyTarget, emergencyType);
	if emergency then
		local crisisData:table = ProcessEmergency_WorldCongressPopup(emergency);

		--Title and subtitles
		instance.Description:SetText(emergency.ShortDescriptionText);

		--Populate our initial data block
		PopulateWorldCrisisText(g_kCrisisManagers, crisisData.crisisDetails, instance.Emergency.CrisisDetailsStack);

		--Populate our bottom block of data
		PopulateWorldCrisisText(g_kRewardsManagers, crisisData.rewardsDetails, instance.Emergency.RewardsDetailsStack);

		if instance.TurnsLeft then
			if not m_IsInSession  then
				instance.TurnsLeft:SetText("[ICON_TURN]" .. emergency.TurnsLeft);
				instance.TurnsLeft:SetToolTipString(Locale.Lookup("LOC_WORLD_CONGRESS_TURNS_LEFT_TT", emergency.TurnsLeft));
			else
				instance.TurnsLeft:SetText("");
			end
		end
	elseif not emergency then
		UI.DataError('Failed to get emergency data, assign @draabe: EmergencyType=' .. kProposal.EmergencyType .. ', Target=' .. kProposal.Target);
	end
end

-- ===========================================================================
--	Generate a unique "key" for later lookups based on the proposal attrubtes
-- ===========================================================================
function GetProposalVoteKey( kProposal:table )
	return tostring(kProposal.TypeName) .."_" .. kProposal.Target .. "_" .. (kProposal.Sender ~= nil and kProposal.Sender or "NONE");
end

-- ===========================================================================
-- Select proposal items (stage 1, phase 2)
-- ===========================================================================
function OnToggleProposal(instance:table, kProposal:table, kProposalCategory:table)
	return function()
		
		local kVoteData:table = m_kProposalVotes[GetProposalVoteKey(kProposal)];
		
		if kVoteData.votes == 0 and m_WorkingFavor >= kProposalCategory.FavorCost then
			kVoteData.votes = 1;
			kVoteData.cost = kProposalCategory.FavorCost;
			instance.SelectBox:SetSelected(true);
			instance.Root:SetTexture("WC_ProposalFrame_Selected");
			instance.SelectCheck:SetTexture("WC_ProposalCheck_On");
		else
			kVoteData.votes = 0;
			kVoteData.cost = 0;
			instance.SelectBox:SetSelected(false);
			instance.Root:SetTexture("WC_ProposalFrame_Normal");
			instance.SelectCheck:SetTexture("WC_ProposalCheck_Off");
		end

		UpdateWorkingFavor();
		instance.UpdateTitle();
		for _, kInnerVoteData in pairs(m_kProposalVotes) do
			UpdateAvailableProposal(kInnerVoteData, kProposalCategory);
		end
		UpdateNavButtons();
	end
end

-- ===========================================================================
function UpdateAvailableProposal(kVoteData:table, kProposalCategory:table)
	local instance:table = kVoteData.instance;
	
	--[[ We need an exposure to set 9 slice values in order to use WC_ProposalFrameOpen_* texture
	if instance.isCollapsed then
		instance.Root:SetTexture(not kVoteData.disabled and kVoteData.votes == 0 and "WC_ProposalFrame_Normal" or "WC_ProposalFrame_Selected");
	else
		instance.Root:SetTexture(not kVoteData.disabled and kVoteData.votes == 0 and "WC_ProposalFrameOpen_Normal" or "WC_ProposalFrameOpen_Selected");
	end
	]]
	instance.Root:SetTexture(not kVoteData.disabled and kVoteData.votes == 0 and "WC_ProposalFrame_Normal" or "WC_ProposalFrame_Selected");

	instance.SelectCheck:SetTexture(not kVoteData.disabled and kVoteData.votes == 0 and "WC_ProposalCheck_Off" or "WC_ProposalCheck_On");
	instance.SelectBox:SetSelected(kVoteData.votes ~= 0);

	-- Check to make sure there isn't already a proposal with this target
	local isTargetSelected:boolean = false;
	for _, kInnerVoteData in pairs(m_kProposalVotes) do
		if kVoteData ~= kInnerVoteData and kInnerVoteData.votes > 0 then
			if kInnerVoteData.data.Target == kVoteData.data.Target then
				isTargetSelected = true;
				instance.SelectBox:SetDisabled(true);
				instance.SelectBox:SetToolTipString(Locale.Lookup("LOC_WORLD_CONGRESS_TT_MAX_ONE_PROPOSAL"));
				break;
			end
		end
	end

	if not isTargetSelected then
		instance.SelectBox:SetDisabled(kVoteData.disabled or (kVoteData.votes == 0 and m_WorkingFavor < kProposalCategory.FavorCost));
		if instance.SelectBox:IsDisabled() then
			instance.SelectBox:SetToolTipString(kVoteData.disabled and "" or Locale.Lookup("LOC_WORLD_CONGRESS_TT_INSUFFICIENT_FAVOR_COST", kProposalCategory.FavorCost));
		elseif instance.SelectBox:IsSelected() then
			instance.SelectBox:SetToolTipString(Locale.Lookup("LOC_WORLD_CONGRESS_TT_PROPOSAL_REFUND", kProposalCategory.FavorCost));
		else
			instance.SelectBox:SetToolTipString(Locale.Lookup("LOC_WORLD_CONGRESS_TT_PROPOSAL_COST", kProposalCategory.FavorCost));
		end
	end

	if kVoteData.proposalBlocker then
		instance.SelectBox:SetToolTipString(Locale.Lookup(kVoteData.proposalBlocker.Description));
	end

	local lineColor:table = kVoteData.votes ~= 0 and {220/255, 190/255, 161/255} or {102/255, 91/255, 63/255 };
	instance.Line:SetColor(lineColor[1], lineColor[2], lineColor[3], 1);
end

-- ===========================================================================
--	Generates a callback that tests whether a vote is successful
-- ===========================================================================
function TestProposalVote(direction:number, kVoteData:table, kCostData:table)
	local kCopyData:table = { votes = kVoteData.votes, cost = kVoteData.cost, voteDirection = kVoteData.voteDirection };
	OnVoteProposal(direction, kCopyData, kCostData, true)();
	return kCopyData.votes ~= kVoteData.votes or kCopyData.cost ~= kVoteData.cost;
end

-- ===========================================================================
-- Vote on proposal items (stage 2, phase 2)
-- ===========================================================================
function OnVoteProposal(direction:number, kVoteData:table, kCostData:table, isTest:boolean)
	return function()

		if kVoteData.voteDirection == NO_VOTE then
			kVoteData.voteDirection = direction;
		end

		local voteDirection:number = kVoteData.voteDirection * direction;
		local nextVotes:number = kVoteData.votes + voteDirection;
		if nextVotes > table.count(kCostData) or nextVotes > kCostData.MaxVotes then return; end
		
		local nextCost:number = kCostData[nextVotes - 1];
		local currCost:number = kVoteData.votes == 0 and 0 or kCostData[kVoteData.votes - 1];

		if voteDirection < 0 or (nextCost - currCost) <= m_WorkingFavor then
			kVoteData.votes = nextVotes;

			if kVoteData.votes == 0 then
				kVoteData.voteDirection = NO_VOTE;
				kVoteData.cost = 0;
			else
				kVoteData.cost = kCostData[nextVotes > 0 and nextVotes - 1 or 0];
			end
		end
		
		if not isTest then
			UpdateWorkingFavor();
			kVoteData.instance.UpdateTitle();
			for _, kInnerVoteData in pairs(m_kProposalVotes) do
				UpdateProposal(kInnerVoteData, kProposalCategory);
			end
			UpdateAllVotingWidgets(kCostData);
			UpdateNavButtons();
		end
	end
end

-- ===========================================================================
function UpdateProposal(kVoteData:table)
	local canVote:boolean = not kVoteData.disabled and not (kVoteData.voteBlocker ~= nil and kVoteData.voteBlocker.NoUpvote and kVoteData.voteBlocker.NoDownvote);
	kVoteData.instance.Root:SetTexture(canVote and kVoteData.votes == 0 and "WC_ProposalFrameOpen_Normal" or "WC_ProposalFrameOpen_Selected");
end

-- ===========================================================================
--	Gets proposal categories and sorts them
-- ===========================================================================
function GetSortedProposalCategories(kProposals:table)
	local kSortedCategories:table = {};
	if kProposals ~= nil then
		for proposalType, kProposalCategory in pairs(kProposals) do
			local kProposalDef = GameInfo.ProposalTypes[proposalType];
			if kProposalDef and table.count(kProposalCategory.ProposalsOfType) > 0 then

				local kSorted:table = {
					type = proposalType,
					kData = kProposalDef,
					kCategory = kProposalCategory
				};
				table.insert(kSortedCategories, kSorted);

			elseif kProposalDef == nil then
				UI.DataError("Undefined Proposal Category: " .. proposalType .. " in World Congress Step 2!");
			end
		end

		table.sort(kSortedCategories, function(a, b) return a.kData.Sort < b.kData.Sort; end);
	end
	return kSortedCategories;
end

-- ===========================================================================
--	Both summary and review instances use the same container
-- ===========================================================================
function ResetReviewInstances()
	m_kResolutionsTitle = nil;
	m_kProposalTitleIM:ResetInstances();
	m_kReviewResolutionIM:ResetInstances();
	m_kReviewProposalIM:ResetInstances();
	m_kEmergencyProposalIM:ResetInstances();
	m_ProposalVoterIM:ResetInstances();
	m_ResolutionVoterIM:ResetInstances();
	m_kReviewOutcomeIM:ResetInstances();
	m_VerticalPaddingReviewIM:ResetInstances();
	ResetEmergencyInstances();
end

-- ===========================================================================
--	Updates the stage one summary screen when we navigate there
-- ===========================================================================
function PopulateSummary()
	local localPlayerID:number = Game.GetLocalPlayer();
	local pDiplomacy:table = Players[localPlayerID]:GetDiplomacy();
	local metPlayers, isUniqueLeader = GetMetPlayersAndUniqueLeaders();

	ResetReviewInstances();

	if m_CurrentStage == 1 then
		local kResolutions:table = Game.GetWorldCongress():GetResolutions(localPlayerID);

		local resolutionCost:number = 0;
		for i, kResolutionData in pairs(kResolutions) do
			if type(i) == "number" then -- There's a "Stage" key kResolutions

				local instance:table = m_kReviewResolutionIM:GetInstance();
				local kVoteData:table = m_kResolutionVotes[i];
				local kResolution:table = GameInfo.Resolutions[kResolutionData.Type];
				local kResolutionChoice:table = m_kResolutionChoices[kResolution.Hash];

				local aVotes:number = kResolutionChoice.choice == 1 and kVoteData.A.votes or 0;
				local aTT:string = kResolutionChoice.choice == 1 and Locale.Lookup("LOC_WORLD_CONGRESS_A_VOTES_TT_SUMMARY", aVotes) or "";

				local bVotes:number = kResolutionChoice.choice ~= 1 and kVoteData.B.votes or 0;
				local bTT:string = kResolutionChoice.choice ~= 1 and Locale.Lookup("LOC_WORLD_CONGRESS_B_VOTES_TT_SUMMARY", bVotes) or "";

				instance.UpVoteLabel:SetText(bVotes);
				instance.DownVoteLabel:SetText(aVotes);
				
				instance.UpVoteIcon:SetToolTipString(bTT);
				instance.UpVoteLabel:SetToolTipString(bTT);
				instance.DownVoteIcon:SetToolTipString(aTT);
				instance.DownVoteLabel:SetToolTipString(aTT);

				instance.UpVoteStack:SetHide(bVotes == 0);
				instance.DownVoteStack:SetHide(aVotes == 0);
				instance.ExpandButton:SetHide(true);

				for i=1,4 do
					instance["Line"..i]:SetHide(false);
				end
				instance.CostContainer:SetHide(false);

				if kResolutionData.TargetType == "PlayerType" then
					local playerID:number = tonumber(kResolutionData.PossibleTargets[kResolutionChoice.target] or -1);
					local pIconManager:table = LeaderIcon:AttachInstance(instance.LeaderIcon);
					local pPlayerConfig:table = PlayerConfigurations[playerID];
					if pPlayerConfig then
						local playerTypeName:string = pPlayerConfig:GetLeaderTypeName();
						local isLocalPlayer:boolean = playerID == localPlayerID;
						local pDiplomacy:table = Players[localPlayerID]:GetDiplomacy();
						local icon:string = (isLocalPlayer or pDiplomacy:HasMet(playerID)) and "ICON_" .. playerTypeName or "ICON_LEADER_DEFAULT";
						pIconManager:UpdateIconSimple(icon, playerID, isUniqueLeader[playerID] or false, Locale.Lookup("LOC_WORLD_CONGRESS_TARGET_RESOLUTION_TT"));
					end
					instance.LeaderIcon.SelectButton:SetHide(not pPlayerConfig);
					instance.TypeIcon:SetHide(pPlayerConfig ~= nil);
				else
					instance.LeaderIcon.SelectButton:SetHide(true);
					instance.TypeIcon:SetHide(false);
				end

				local text, icon = GetPulldownNameAndIcons(kResolutionData, kResolutionChoice.target ) or "", "";
				instance.ChosenThing:SetText(text);
				instance.Title:SetText(Locale.ToUpper(Locale.Lookup(kResolution.Name)));
				instance.Status:SetText("");
				instance.TargetLabel:SetText(Locale.Lookup("LOC_WORLD_CONGRESS_PREVIEW_PROPOSAL_TARGET"));
				instance.ChoiceLabel:SetText(Locale.Lookup("LOC_WORLD_CONGRESS_PREVIEW_PROPOSAL_OUTCOME", kResolutionChoice.choice == 1 and Locale.Lookup("LOC_WORLD_CONGRESS_CHOICE_A") or Locale.Lookup("LOC_WORLD_CONGRESS_CHOICE_B")));
				instance.Description:SetText(Locale.Lookup(kResolutionChoice.choice == 1 and kResolution.Effect1Description or kResolution.Effect2Description));
				instance.Cost:SetText(Locale.Lookup("LOC_WORLD_CONGRESS_FAVOR", kVoteData.A.cost + kVoteData.B.cost));
				instance.Cost:SetToolTipString(Locale.Lookup("LOC_WORLD_CONGRESS_TT_PROPOSAL_COST", kVoteData.A.cost + kVoteData.B.cost));
				instance.TurnsLeft:SetText("");
				instance.IconNew:SetHide(true);

				resolutionCost = resolutionCost + kVoteData.A.cost + kVoteData.B.cost;
			end
		end
		Controls.ReviewResolutionFavor:SetText(Locale.Lookup("LOC_WORLD_CONGRESS_CATEGORY_FAVOR", resolutionCost));
		Controls.ReviewResolutionFavor:SetToolTipString(Locale.Lookup("LOC_WORLD_CONGRESS_TT_RESOLUTIONS_FAVOR_COST_WITH_REFUND", resolutionCost));
	end
	
	local kSortedCategories:table = GetSortedProposalCategories(Game.GetWorldCongress():GetProposals(localPlayerID).Proposals);
	for _, kSorted in ipairs(kSortedCategories) do
		local proposalType:number = kSorted.type;
		local kProposalDef:table = kSorted.kData;
		local kProposalCategory:table = kSorted.kCategory;

		local titleInstance:table = m_kProposalTitleIM:GetInstance(Controls.ReviewProposalStack);
		local kCategoryProposals:table = kProposalCategory.ProposalsOfType;

		PopulateSummaryProposals(kCategoryProposals, m_kReviewProposalIM );
		UpdateCategoryTitle(titleInstance, kCategoryProposals, kProposalDef);
	end
	
	Controls.ReviewResolutionTitle:SetHide(m_kReviewResolutionIM.m_iAllocatedInstances == 0);
end

-- ===========================================================================
function PopulateSummaryProposals(kProposals:table, kProposalIM:table)
	local metPlayers		:table = GetMetPlayersAndUniqueLeaders();
	local localPlayerID		:number = Game.GetLocalPlayer();
	local pDiplomacy		:table= Players[localPlayerID]:GetDiplomacy();
	local pEmergencyManager	:table = Game.GetEmergencyManager();

	for _, kProposal in pairs(kProposals) do
		local kVoteData:table = m_kProposalVotes[GetProposalVoteKey(kProposal)];
		if not m_IsInSession or kVoteData then
			local instance:table = kProposalIM:GetInstance();
			instance.IconNew:SetShow(kProposal.IsNew and kProposal.IsNew ~= 0);

			-- Target Icon
			local pIconManager:table = LeaderIcon:AttachInstance(instance.LeaderIcon);
			local pPlayerConfig:table = PlayerConfigurations[kProposal.Target];
			if pPlayerConfig then
				local playerTypeName:string = pPlayerConfig:GetLeaderTypeName();
				local isLocalPlayer:boolean = kProposal.Target == localPlayerID;
				local icon:string = (isLocalPlayer or pDiplomacy:HasMet(kProposal.Target)) and "ICON_" .. playerTypeName or "ICON_LEADER_DEFAULT";
				pIconManager:UpdateIconSimple(icon, kProposal.Target, metPlayers[kProposal.Target], Locale.Lookup("LOC_WORLD_CONGRESS_TARGET_PROPOSAL_TT"));
				instance.Title:SetText(Locale.ToUpper(Locale.Lookup(kProposal.Name, pPlayerConfig:GetLeaderName())));
				instance.Status:SetText("");
				instance.Description:SetText(Locale.Lookup(kProposal.Description, pPlayerConfig:GetLeaderName()));
				instance.LeaderIcon.SelectButton:SetHide(false);
				instance.LeaderIcon.TargetIcon:SetColor(kProposal.TypeName == "WC_EMERGENCY_REQUEST_AID" and COLOR_GREEN or COLOR_RED);
				instance.LeaderIcon.TargetIcon:SetTexture(kProposal.TypeName == "WC_EMERGENCY_REQUEST_AID" and "Emergency_TargetAid44" or "Emergency_Target44");
				instance.TypeIcon:SetHide(true);
			else
				instance.Title:SetText(Locale.ToUpper(Locale.Lookup(kProposal.Name)));
				instance.Status:SetText("");
				instance.Description:SetText(Locale.Lookup(kProposal.Description));
				instance.LeaderIcon.SelectButton:SetHide(true);
				instance.TypeIcon:SetIcon("ICON_" .. kProposal.TypeName);
				instance.TypeIcon:SetHide(false);
			end

			local cost = nil;
			local votes = nil;
			local voteDirection = nil;
			if kVoteData then
				cost = kVoteData.cost;
				votes = kVoteData.votes;
				voteDirection = kVoteData.voteDirection;
			end
			instance.Cost:SetText(cost ~= nil and Locale.Lookup("LOC_WORLD_CONGRESS_FAVOR", cost) or "")
			instance.Cost:SetToolTipString(cost ~= nil and Locale.Lookup("LOC_WORLD_CONGRESS_TT_PROPOSAL_COST", cost) or "");

			local upTT:string = votes and Locale.Lookup("LOC_WORLD_CONGRESS_TT_VOTE_UP_SUMMARY", votes) or "";
			local downTT:string = votes and Locale.Lookup("LOC_WORLD_CONGRESS_TT_VOTE_DOWN_SUMMARY", votes) or "";

			instance.UpVoteIcon:SetToolTipString(upTT);
			instance.UpVoteLabel:SetToolTipString(upTT);
			instance.DownVoteIcon:SetToolTipString(downTT);
			instance.DownVoteLabel:SetToolTipString(downTT);

			instance.UpVoteLabel:SetText(votes and tostring(votes) or "");
			instance.DownVoteLabel:SetText(votes and tostring(votes) or "");
			
			instance.UpVoteStack:SetHide(not voteDirection or voteDirection < 0 or votes <= 0);
			instance.DownVoteStack:SetHide(not voteDirection or voteDirection > 0 or votes <= 0);

			if m_IsInSession then
				for i=1,4 do
					instance["Line"..i]:SetHide(false);
				end
			else
				for i=1,4 do
					instance["Line"..i]:SetHide(i > 2);
				end
			end
			instance.CostContainer:SetHide(false);

			PopulateEmergencyData(instance, kProposal.Target, kProposal.EmergencyType);
			instance.EmergencyButton:SetHide(m_IsInSession);
			instance.ExpandButton:SetHide(m_IsInSession);
			instance.EmergencyContainer:SetHide(false);

			instance.ExpandButton:RegisterCallback(Mouse.eLClick, function()
				UI.PlaySound("Main_Main_Panel_Collapse"); 
				instance.isCollapsed = not instance.isCollapsed;
				RealizeCollapseableProposal(instance);
			end);			
 			instance.ExpandButton:RegisterCallback(Mouse.eMouseEnter, function() UI.PlaySound("Main_Menu_Mouse_Over"); end);
			
			instance.isCollapsed = true;
			RealizeCollapseableProposal(instance);

			if not m_IsInSession then
				instance.EmergencyButton:RegisterCallback(Mouse.eLClick, function()
					local emergency = Game.GetEmergencyManager():GetSingleEmergency(kProposal.Target, kProposal.EmergencyType);
					LuaEvents.WorldCongress_ShowEmergency(emergency.TargetID, emergency.EmergencyType);
					ClosePopup();
				end);
			end
		end
	end
end

function UpdateResolutionChoice(kResolutionChoice:table)
	local hasTarget:boolean = kResolutionChoice.target ~= -1;
	local hasChoice:boolean = kResolutionChoice.choice ~= -1;

	kResolutionChoice.instance.Choice1.Root:SetShow(kResolutionChoice.choice == 1);
	kResolutionChoice.instance.Choice2.Root:SetShow(kResolutionChoice.choice == 2);

	kResolutionChoice.instance.Choice1Slot:SetTexture(hasTarget and kResolutionChoice.choice == 1 and "WC_ProposalSlot_On" or "WC_ProposalSlot_Off");
	kResolutionChoice.instance.Choice2Slot:SetTexture(hasTarget and kResolutionChoice.choice == 2 and "WC_ProposalSlot_On" or "WC_ProposalSlot_Off");

	local kVoteData:table;
	for _, kInnerVoteData in pairs(m_kResolutionVotes) do
		if kInnerVoteData.Hash == kResolutionChoice.hash then
			kVoteData = kInnerVoteData;
			break;
		end
	end

	local isSelected:boolean = hasTarget and hasChoice and kVoteData and (kVoteData.A.votes ~= 0 or kVoteData.B.votes ~= 0);
	kResolutionChoice.instance.Root:SetTexture(isSelected and "WC_ProposalFrameOpen_Selected" or "WC_ProposalFrameOpen_Normal");

	local lineColor:table = isSelected and {220/255, 190/255, 161/255} or {102/255, 91/255, 63/255 };
	kResolutionChoice.instance.Line:SetColor(lineColor[1], lineColor[2], lineColor[3], 1);
end

-- ===========================================================================
--	Populates options that allow players to request a special session
-- ===========================================================================
function PopulateEmergencyProposals()
	ResetReviewInstances();

	local kSortedCategories:table = GetSortedProposalCategories(Game.GetWorldCongress():GetEmergencies(Game.GetLocalPlayer()).Proposals);
	for _, kSorted in ipairs(kSortedCategories) do
		local proposalType:number = kSorted.type;
		local kProposalDef:table = kSorted.kData;
		local kProposalCategory:table = kSorted.kCategory;

		local titleInstance:table = m_kProposalTitleIM:GetInstance(Controls.ReviewProposalStack);
		local kCategoryProposals:table = kProposalCategory.ProposalsOfType;

		local updateFn:ifunction = function() UpdateCategoryTitle(titleInstance, kCategoryProposals, kProposalDef, kProposalCategory.FavorCost); end
		if PopulateProposalStack(kCategoryProposals, m_kEmergencyProposalIM, kProposalCategory, updateFn) > 0 then
			updateFn();
		else
			titleInstance.Root:SetHide(true);
		end
	end
end

-- ===========================================================================
--	Returns true if there are any available Emergency Proposals
-- ===========================================================================
function HasEmergencyProposals()
	local kSortedCategories:table = GetSortedProposalCategories(Game.GetWorldCongress():GetEmergencies(Game.GetLocalPlayer()).Proposals);
	for _, kSorted in ipairs(kSortedCategories) do
		if kSorted.kCategory.ProposalsOfType and table.count(kSorted.kCategory.ProposalsOfType) > 0 then
			return true;
		end
	end
	return false;
end

-- ===========================================================================
--	Returns true if there are any available Emergency Proposals
-- ===========================================================================
function HasEmergencyProposalChoices()
	local kSortedCategories:table = GetSortedProposalCategories(Game.GetWorldCongress():GetEmergencies(Game.GetLocalPlayer()).Proposals);
	for _, kSorted in ipairs(kSortedCategories) do
		if kSorted.kCategory.ProposalsOfType and table.count(kSorted.kCategory.ProposalsOfType) > 0 then
			for _, kProposal in pairs(kSorted.kCategory.ProposalsOfType) do
				local kVoteData:table = m_kProposalVotes[GetProposalVoteKey(kProposal)];
				if kVoteData and not kVoteData.instance.SelectBox:IsDisabled() then
					return true;
				end
			end
		end
	end
	return false;
end

-- ===========================================================================
--	Populates the stage 4 review
-- ===========================================================================
function PopulateReview()
	local localPlayerID:number = Game.GetLocalPlayer();
	local pDiplomacy:table = Players[localPlayerID]:GetDiplomacy();
	local kReviewData:table = Game.GetWorldCongress():GetReview(localPlayerID);
	local metPlayers, isUniqueLeader = GetMetPlayersAndUniqueLeaders();

	ResetReviewInstances();

	for i, kResolutionData in pairs(kReviewData.Resolutions) do
		if type(kResolutionData) == "table" then -- There's a "Stage" key in kResolutions
			local instance:table = m_kReviewResolutionIM:GetInstance();
			local kResolution:table = GameInfo.Resolutions[kResolutionData.Type];

			instance.Title:SetText(Locale.ToUpper(Locale.Lookup(kResolution.Name)));
			instance.Description:SetText(Locale.Lookup(kResolutionData.ChosenOption));
			instance.Cost:SetText("");
			instance.TurnsLeft:SetText("");

			local aVotes:number = 0;
			local bVotes:number = 0;
			for _, kData in pairs(kResolutionData.PlayerSelections) do
				if kData.OptionChosen == 1 then
					aVotes = aVotes + kData.Votes;
				else
					bVotes = bVotes + kData.Votes;
				end
			end

			instance.UpVoteLabel:SetText(bVotes);
			instance.DownVoteLabel:SetText(aVotes);
			
			local aTT:string = Locale.Lookup("LOC_WORLD_CONGRESS_REVIEW_A_VOTES_TT", aVotes);
			local bTT:string = Locale.Lookup("LOC_WORLD_CONGRESS_REVIEW_B_VOTES_TT", bVotes);
			if aVotes == bVotes then
				instance.Status:SetText(Locale.Lookup("LOC_WORLD_CONGRESS_PROPOSAL_PASSED_TIE"));
				instance.Status:SetToolTipString(Locale.Lookup("LOC_WORLD_CONGRESS_TT_TIE_EXPLANATION"));
			else
				instance.Status:SetText(Locale.Lookup("LOC_WORLD_CONGRESS_PROPOSAL_PASSED"));
				instance.Status:SetToolTipString("");
			end
			instance.UpVoteIcon:SetToolTipString(bTT);
			instance.UpVoteLabel:SetToolTipString(bTT);
			instance.DownVoteIcon:SetToolTipString(aTT);
			instance.DownVoteLabel:SetToolTipString(aTT);

			instance.UpVoteStack:SetHide(bVotes == 0);
			instance.DownVoteStack:SetHide(aVotes == 0);
			instance.ExpandButton:SetHide(false);

			for i=1,4 do
				instance["Line"..i]:SetHide(i == 2);
			end
			instance.CostContainer:SetHide(true);

			if kResolutionData.TargetType == "PlayerType" then
				local playerID:number = tonumber(kResolutionData.ChosenThing);
				local text, icon = playerID ~= -1 and GetPulldownNameAndIcons(kResolutionData, playerID ) or "", "";
				instance.ChosenThing:SetText(text);

				local pIconManager:table = LeaderIcon:AttachInstance(instance.LeaderIcon);
				local pPlayerConfig:table = PlayerConfigurations[playerID];
				if pPlayerConfig then
					local playerTypeName:string = pPlayerConfig:GetLeaderTypeName();
					local isLocalPlayer:boolean = playerID == localPlayerID;
					local pDiplomacy:table = Players[localPlayerID]:GetDiplomacy();
					local icon:string = (isLocalPlayer or pDiplomacy:HasMet(playerID)) and "ICON_" .. playerTypeName or "ICON_LEADER_DEFAULT";
					pIconManager:UpdateIconSimple(icon, playerID, isUniqueLeader[playerID] or false, Locale.Lookup("LOC_WORLD_CONGRESS_TARGET_RESOLUTION_TT"));
				end
				instance.LeaderIcon.SelectButton:SetHide(not pPlayerConfig);
				instance.TypeIcon:SetHide(pPlayerConfig ~= nil);
			else
				instance.ChosenThing:SetText(Locale.Lookup(kResolutionData.ChosenThing));
				instance.LeaderIcon.SelectButton:SetHide(true);
				instance.TypeIcon:SetHide(false);
			end
			
			instance.TargetLabel:SetText(Locale.Lookup("LOC_WORLD_CONGRESS_REVIEW_PROPOSAL_TARGET"));
			instance.ChoiceLabel:SetText(Locale.Lookup("LOC_WORLD_CONGRESS_REVIEW_PROPOSAL_OUTCOME", kResolutionData.ChosenLabel));
			instance.IconNew:SetShow(kResolutionData.IsNew and kResolutionData.IsNew ~= 0);

			instance.ExpandButton:RegisterCallback(Mouse.eLClick, function()
				UI.PlaySound("Main_Main_Panel_Collapse"); 
				instance.isCollapsed = not instance.isCollapsed;
				RealizeCollapseableVoters(instance);
			end);			
 			instance.ExpandButton:RegisterCallback(Mouse.eMouseEnter, function() UI.PlaySound("Main_Menu_Mouse_Over"); end);

			-- Player Votes (visible when expanded)
			if table.count(kResolutionData.PlayerSelections) > 0 then

				local rejectedOutcome:table = m_kReviewOutcomeIM:GetInstance(instance.VoterStack);
				rejectedOutcome.ChoiceLabel:SetText(Locale.Lookup("LOC_WORLD_CONGRESS_REVIEW_PROPOSAL_REJECTED_OUTCOME", kResolutionData.RejectedLabel));
				rejectedOutcome.Description:SetText(Locale.Lookup(kResolutionData.RejectedOption));

				local dataContainerWidth:number = instance.VoterStack:GetSizeX();
				for _, kData in pairs(kResolutionData.PlayerSelections) do
					local voterInstance:table = m_ResolutionVoterIM:GetInstance(instance.VoterStack);
					local playerID:number = tonumber(kData.PlayerID);

					voterInstance.UpVoteLabel:SetText(kData.OptionChosen ~= 1 and kData.Votes or 0);
					voterInstance.DownVoteLabel:SetText(kData.OptionChosen == 1 and kData.Votes or 0);
					voterInstance.UpVoteStack:SetHide(kData.OptionChosen == 1 or kData.Votes == 0);
					voterInstance.DownVoteStack:SetHide(kData.OptionChosen ~= 1 or kData.Votes == 0);

					local playerName:string = GetVisiblePlayerName(playerID);
					local aTT:string = Locale.Lookup("LOC_WORLD_CONGRESS_REVIEW_A_VOTES_PLAYER_TT", playerName, kData.Votes);
					local bTT:string = Locale.Lookup("LOC_WORLD_CONGRESS_REVIEW_B_VOTES_PLAYER_TT", playerName, kData.Votes);
					voterInstance.UpVoteIcon:SetToolTipString(bTT);
					voterInstance.UpVoteLabel:SetToolTipString(bTT);
					voterInstance.DownVoteIcon:SetToolTipString(aTT);
					voterInstance.DownVoteLabel:SetToolTipString(aTT);

					for i=1,4 do
						voterInstance["Line"..i]:SetHide(i == 2);
					end
					voterInstance.CostContainer:SetHide(true);

					if kResolutionData.TargetType == "PlayerType" then
						local targetPlayerID:number = tonumber(kData.ResolutionTarget);
						local text, icon = targetPlayerID ~= -1 and GetPulldownNameAndIcons(kResolutionData, targetPlayerID ) or "", "";
						voterInstance.ChosenThing:SetText(text);
					else
						voterInstance.ChosenThing:SetText(Locale.Lookup(kData.ResolutionTarget));
						voterInstance.LeaderIcon.SelectButton:SetHide(true);
						voterInstance.TypeIcon:SetHide(false);
					end

					local pIconManager:table = LeaderIcon:AttachInstance(voterInstance.LeaderIcon);
					local pPlayerConfig:table = PlayerConfigurations[playerID];
					if pPlayerConfig then
						local playerTypeName:string = pPlayerConfig:GetLeaderTypeName();
						local isLocalPlayer:boolean = playerID == localPlayerID;
						local pDiplomacy:table = Players[localPlayerID]:GetDiplomacy();
						local icon:string = (isLocalPlayer or pDiplomacy:HasMet(playerID)) and "ICON_" .. playerTypeName or "ICON_LEADER_DEFAULT";
						pIconManager:UpdateIconSimple(icon, playerID, isUniqueLeader[playerID] or false);
					end
					voterInstance.LeaderIcon.SelectButton:SetHide(not pPlayerConfig);
					voterInstance.TypeIcon:SetHide(pPlayerConfig ~= nil);

					voterInstance.ChoiceLabel:SetText(Locale.Lookup("LOC_WORLD_CONGRESS_REVIEW_VOTER_OUTCOME", kData.OptionChosenLabel));
				end

				m_VerticalPaddingReviewIM:GetInstance(instance.VoterStack);
			end

			instance.isCollapsed = true;
			RealizeCollapseableVoters(instance);
		end
	end

	local kSortedCategories:table = GetSortedProposalCategories(kReviewData.Discussions);
	for _, kSorted in ipairs(kSortedCategories) do
		local proposalType:number = kSorted.type;
		local kProposalDef:table = kSorted.kData;
		local kProposalCategory:table = kSorted.kCategory;

		local titleInstance:table = m_kProposalTitleIM:GetInstance(Controls.ReviewProposalStack);
		titleInstance.Title:SetText(Locale.ToUpper(Locale.Lookup(kProposalDef.Name)));
		titleInstance.Icon:SetIcon("ICON_" .. kProposalDef.ProposalType);
		titleInstance.Cost:SetToolTipString("");
		titleInstance.Cost:SetText("");

		PopulateReviewProposals(kProposalCategory.ProposalsOfType, m_kReviewProposalIM );
	end

	Controls.ReviewResolutionFavor:SetText("");
	Controls.ReviewResolutionTitle:SetHide(m_kReviewResolutionIM.m_iAllocatedInstances == 0);
end

-- ===========================================================================
--	Set a group to it's proper collapse/open state
--	Set + - in group row
-- ===========================================================================
function RealizeCollapseableVoters(instance:table)
	instance.ExpandButton:SetTexture(instance.isCollapsed and "WC_ExpandButton" or "WC_CollapseButton");
	instance.VoterScroll:SetHide(instance.isCollapsed);
end

-- ===========================================================================
--	Set a group to it's proper collapse/open state
--	Set + - in group row
-- ===========================================================================
function RealizeCollapseableProposal(instance:table)
	instance.ExpandButton:SetTexture(instance.isCollapsed and "WC_ExpandButton" or "WC_CollapseButton");
	instance.EmergencyContainer:SetHide(instance.isCollapsed);
end

-- ===========================================================================
--	Populates the stage 4 active effects
-- ===========================================================================
function PopulateActiveEffects()
	local localPlayerID:number = Game.GetLocalPlayer();
	local pDiplomacy:table = Players[localPlayerID]:GetDiplomacy();
	local pCongressData:table = Game.GetWorldCongress():GetMeetingStatus();
	local kResolutions:table = Game.GetWorldCongress():GetResolutions(localPlayerID);

	ResetReviewInstances();

	-- These tables are cached so they only get computed once
	local metPlayers:table = nil;
	local isUniqueLeader:table = nil;

	for i, kResolutionData in pairs(kResolutions) do
		if type(kResolutionData) == "table" then -- There's a "Stage" key in kResolutions
			local instance:table = m_kReviewResolutionIM:GetInstance();
			local kResolution:table = GameInfo.Resolutions[kResolutionData.Type];

			instance.Title:SetText(Locale.ToUpper(Locale.Lookup(kResolution.Name)));
			instance.Status:SetText("");
			instance.Description:SetText(Locale.Lookup(kResolutionData.ChosenOption));
			instance.TurnsLeft:SetText("[ICON_TURN]" .. pCongressData.TurnsLeft + 1);
			instance.TurnsLeft:SetToolTipString(Locale.Lookup("LOC_WORLD_CONGRESS_TURNS_LEFT_TT", pCongressData.TurnsLeft + 1));

			instance.Cost:SetText("");
			instance.UpVoteLabel:SetText("");
			instance.DownVoteLabel:SetText("");
			instance.UpVoteIcon:SetToolTipString("");
			instance.UpVoteLabel:SetToolTipString("");
			instance.DownVoteIcon:SetToolTipString("");
			instance.DownVoteLabel:SetToolTipString("");
			instance.UpVoteStack:SetHide(true);
			instance.DownVoteStack:SetHide(true);
			instance.ExpandButton:SetHide(true);

			for i=1,4 do
				instance["Line"..i]:SetHide(i > 2);
			end
			instance.CostContainer:SetHide(false);

			if kResolutionData.TargetType == "PlayerType" then
				if not metPlayers then
					metPlayers, isUniqueLeader = GetMetPlayersAndUniqueLeaders();
				end

				local playerID:number = tonumber(kResolutionData.ChosenThing);
				local text, icon = playerID ~= -1 and GetPulldownNameAndIcons(kResolutionData, playerID ) or "", "";
				instance.ChosenThing:SetText(text);

				local pIconManager:table = LeaderIcon:AttachInstance(instance.LeaderIcon);
				local pPlayerConfig:table = PlayerConfigurations[playerID];
				if pPlayerConfig then
					local playerTypeName:string = pPlayerConfig:GetLeaderTypeName();
					local isLocalPlayer:boolean = playerID == localPlayerID;
					local pDiplomacy:table = Players[localPlayerID]:GetDiplomacy();
					local icon:string = (isLocalPlayer or pDiplomacy:HasMet(playerID)) and "ICON_" .. playerTypeName or "ICON_LEADER_DEFAULT";
					pIconManager:UpdateIconSimple(icon, playerID, isUniqueLeader[playerID] or false, Locale.Lookup("LOC_WORLD_CONGRESS_TARGET_RESOLUTION_TT"));
				end
				instance.LeaderIcon.SelectButton:SetHide(not pPlayerConfig);
				instance.TypeIcon:SetHide(pPlayerConfig ~= nil);
			else
				instance.ChosenThing:SetText(Locale.Lookup(kResolutionData.ChosenThing));
				instance.LeaderIcon.SelectButton:SetHide(true);
				instance.TypeIcon:SetHide(false);
			end

			instance.TargetLabel:SetText(Locale.Lookup("LOC_WORLD_CONGRESS_REVIEW_PROPOSAL_TARGET"));
			instance.ChoiceLabel:SetText(Locale.Lookup("LOC_WORLD_CONGRESS_REVIEW_PROPOSAL_OUTCOME", kResolutionData.ChosenLabel));
			instance.IconNew:SetShow(kResolutionData.IsNew and kResolutionData.IsNew ~= 0);
		end
	end

	local kSortedCategories:table = GetSortedProposalCategories(Game.GetWorldCongress():GetProposals(Game.GetLocalPlayer()).Proposals);
	for _, kSorted in ipairs(kSortedCategories) do
		local proposalType:number = kSorted.type;
		local kProposalDef:table = kSorted.kData;
		local kProposalCategory:table = kSorted.kCategory;

		local titleInstance:table = m_kProposalTitleIM:GetInstance(Controls.ReviewProposalStack);
		titleInstance.Title:SetText(Locale.ToUpper(Locale.Lookup(kProposalDef.Name)));
		titleInstance.Icon:SetIcon("ICON_" .. kProposalDef.ProposalType);
		titleInstance.Cost:SetToolTipString("");
		titleInstance.Cost:SetText("");

		PopulateSummaryProposals(kProposalCategory.ProposalsOfType, m_kReviewProposalIM );
	end

	Controls.ReviewResolutionFavor:SetText("");
	Controls.ReviewResolutionTitle:SetHide(m_kReviewResolutionIM.m_iAllocatedInstances == 0);
end

-- ===========================================================================
-- Accept the voting setup as presented
-- ===========================================================================
function PopulateReviewProposals(kProposals:table, kProposalIM:table)
	local metPlayers		:table = GetMetPlayersAndUniqueLeaders();
	local localPlayerID		:number = Game.GetLocalPlayer();
	local pDiplomacy		:table= Players[localPlayerID]:GetDiplomacy();
	local pEmergencyManager	:table = Game.GetEmergencyManager();

	for _, kProposal in pairs(kProposals) do
		local instance:table = kProposalIM:GetInstance();
		instance.IconNew:SetShow(kProposal.IsNew and kProposal.IsNew ~= 0);
		instance.Status:SetText("");
		
		local upVotes:number = 0;
		local downVotes:number = 0;
		for p, v in pairs(kProposal.PlayerVotes) do
			if v.Votes > 0 then
				upVotes = upVotes + v.Votes;
			elseif v.Votes < 0 then
				downVotes = downVotes + (v.Votes * -1);
			end
		end

		instance.UpVoteLabel:SetText(upVotes);
		instance.DownVoteLabel:SetText(downVotes);
		instance.UpVoteStack:SetHide(upVotes == 0);
		instance.DownVoteStack:SetHide(downVotes == 0);

		local upTT:string = Locale.Lookup("LOC_WORLD_CONGRESS_REVIEW_UP_VOTES_TT", upVotes);
		local downTT:string = Locale.Lookup("LOC_WORLD_CONGRESS_REVIEW_DOWN_VOTES_TT", downVotes);
		instance.UpVoteIcon:SetToolTipString(upTT);
		instance.UpVoteLabel:SetToolTipString(upTT);
		instance.DownVoteIcon:SetToolTipString(downTT);
		instance.DownVoteLabel:SetToolTipString(downTT);

		instance.ExpandButton:SetHide(false);

		instance.ExpandButton:RegisterCallback(Mouse.eLClick, function()
			UI.PlaySound("Main_Main_Panel_Collapse"); 
			instance.isCollapsed = not instance.isCollapsed;
			RealizeCollapseableVoters(instance);
		end);			
 		instance.ExpandButton:RegisterCallback(Mouse.eMouseEnter, function() UI.PlaySound("Main_Menu_Mouse_Over"); end);

		-- Title + Target Icon
		local proposalResult:string = upVotes > downVotes and "LOC_WORLD_CONGRESS_PROPOSAL_PASSED" or "LOC_WORLD_CONGRESS_PROPOSAL_FAILED";
		local pIconManager:table = LeaderIcon:AttachInstance(instance.LeaderIcon);
		local pPlayerConfig:table = PlayerConfigurations[kProposal.TargetPlayer];
		if pPlayerConfig then
			local playerTypeName:string = pPlayerConfig:GetLeaderTypeName();
			local isLocalPlayer:boolean = kProposal.TargetPlayer == localPlayerID;
			local icon:string = (isLocalPlayer or pDiplomacy:HasMet(kProposal.TargetPlayer)) and "ICON_" .. playerTypeName or "ICON_LEADER_DEFAULT";
			pIconManager:UpdateIconSimple(icon, kProposal.TargetPlayer, metPlayers[kProposal.TargetPlayer], Locale.Lookup("LOC_WORLD_CONGRESS_TARGET_PROPOSAL_TT"));
			
			local proposalName:string = Locale.ToUpper(Locale.Lookup(kProposal.Name, pPlayerConfig:GetLeaderName()));
			instance.Title:SetText(proposalName);
			instance.Status:SetText(Locale.Lookup(proposalResult));
			instance.Description:SetText(Locale.Lookup(kProposal.Description, pPlayerConfig:GetLeaderName()));
			instance.LeaderIcon.SelectButton:SetHide(false);
			instance.LeaderIcon.TargetIcon:SetColor(kProposal.TypeName == "WC_EMERGENCY_REQUEST_AID" and COLOR_GREEN or COLOR_RED);
			instance.LeaderIcon.TargetIcon:SetTexture(kProposal.TypeName == "WC_EMERGENCY_REQUEST_AID" and "Emergency_TargetAid44" or "Emergency_Target44");
			instance.TypeIcon:SetHide(true);
		else
			instance.Title:SetText(Locale.ToUpper(Locale.Lookup(kProposal.Name)));
			instance.Status:SetText(Locale.Lookup(proposalResult));
			instance.Description:SetText(Locale.Lookup(kProposal.Description));
			instance.LeaderIcon.SelectButton:SetHide(true);
			instance.TypeIcon:SetIcon("ICON_" .. kProposal.TypeName);
			instance.TypeIcon:SetHide(false);
		end

		for i=1,4 do
			instance["Line"..i]:SetHide(i == 2);
		end
		instance.CostContainer:SetHide(true);

		-- Player Votes (visible when expanded)
		if table.count(kProposal.PlayerVotes) > 0 then
			local dataContainerWidth:number = instance.VoterStack:GetSizeX();
			for _, kData in pairs(kProposal.PlayerVotes) do
				local instance:table = m_ProposalVoterIM:GetInstance(instance.VoterStack);
				local playerID:number = tonumber(kData.PlayerType);

				instance.UpVoteLabel:SetText(kData.Votes);
				instance.DownVoteLabel:SetText(kData.Votes * -1);
				instance.UpVoteStack:SetHide(kData.Votes <= 0);
				instance.DownVoteStack:SetHide(kData.Votes >= 0);

				-- Target Icon
				local pIconManager:table = LeaderIcon:AttachInstance(instance.LeaderIcon);
				local pPlayerConfig:table = PlayerConfigurations[playerID];
				local playerName:string = GetVisiblePlayerName(playerID);
				if pPlayerConfig then
					local playerTypeName:string = pPlayerConfig:GetLeaderTypeName();
					local icon:string = (playerID == localPlayerID or pDiplomacy:HasMet(playerID)) and "ICON_" .. playerTypeName or "ICON_LEADER_DEFAULT";
					pIconManager:UpdateIconSimple(icon, playerID, metPlayers[playerID]);
					instance.Title:SetText(Locale.Lookup(playerName));
					-- TODO: Set truncate width of Reason field
					instance.Reason:SetText((kData.Votes == 0 and playerID == localPlayerID) and Locale.Lookup("LOC_WC_VOTING_BLOCKER_NOT_INVITED_TO_EMERGENCY_DESC") or "");
				end

				local upTT:string = Locale.Lookup("LOC_WORLD_CONGRESS_REVIEW_UP_VOTES_PLAYER_TT", playerName, kData.Votes);
				local downTT:string = Locale.Lookup("LOC_WORLD_CONGRESS_REVIEW_DOWN_VOTES_PLAYER_TT", playerName, kData.Votes * -1);
				instance.UpVoteIcon:SetToolTipString(upTT);
				instance.UpVoteLabel:SetToolTipString(upTT);
				instance.DownVoteIcon:SetToolTipString(downTT);
				instance.DownVoteLabel:SetToolTipString(downTT);
			end

			m_VerticalPaddingReviewIM:GetInstance(instance.VoterStack);
		end

		instance.EmergencyButton:SetHide(true);
		instance.EmergencyContainer:SetHide(true);

		instance.isCollapsed = true;
		RealizeCollapseableVoters(instance);
	end
end

-- ===========================================================================
-- Accept the voting setup as presented
-- ===========================================================================
function OnAccept()

	if(GameConfiguration.IsPaused())then return; end

	local kParameters:table = {};
	local playerID:number = Game.GetLocalPlayer();

	if m_CurrentStage == 1 or m_CurrentStage == 2 then
		if m_CurrentStage == 1 and table.count(m_kResolutionVotes) == 0 then
			UI.DataError("Clicked OnAccept() in Stage 1 of WorldCongress but have an empty m_kResolutionVotes table");
		end

		if m_CurrentStage == 2 and table.count(m_kProposalVotes) == 0 then
			UI.DataError("Clicked OnAccept() in Stage 1 of WorldCongress but have an empty m_kProposalVotes table");
		end

		if m_CurrentStage == 1 then
 			for _, kVoteData in pairs(m_kResolutionVotes) do
				if kVoteData.A.votes + kVoteData.B.votes > 0 then
					local kParameters:table = {};
					kParameters[PlayerOperations.PARAM_RESOLUTION_TYPE] = kVoteData.Hash;
					kParameters[PlayerOperations.PARAM_WORLD_CONGRESS_VOTES] = kVoteData.A.votes + kVoteData.B.votes;
					
					local kChoiceData:table = m_kResolutionChoices[kVoteData.Hash];
					if kChoiceData then
						kParameters[PlayerOperations.PARAM_RESOLUTION_OPTION] = kChoiceData.choice;
						kParameters[PlayerOperations.PARAM_RESOLUTION_SELECTION] = kChoiceData.target - 1;
					end

					UI.RequestPlayerOperation(playerID, PlayerOperations.WORLD_CONGRESS_RESOLUTION_VOTE, kParameters);
				end
			end
		end

		for _, kVoteData in pairs(m_kProposalVotes) do
			local kParameters:table = {};
			kParameters[PlayerOperations.PARAM_PLAYER_ONE] = kVoteData.data.Sender;
			kParameters[PlayerOperations.PARAM_PLAYER_TWO] = kVoteData.data.Target;
			kParameters[PlayerOperations.PARAM_WORLD_CONGRESS_VOTES] = kVoteData.votes * kVoteData.voteDirection;
			UI.RequestPlayerOperation(playerID, PlayerOperations.WORLD_CONGRESS_DISCUSSION_VOTE, kParameters);
		end
	
		m_CurrentStage = 0;
		m_CurrentPhase = 0;
		m_kProposalVotes = {}
		m_kResolutionVotes = {};
		m_kResolutionChoices = {};

		UI.RequestPlayerOperation(Game.GetLocalPlayer(), PlayerOperations.WORLD_CONGRESS_SUBMIT_TURN, {});
		UI.RequestAction(ActionTypes.ACTION_ENDTURN);
		Controls.AcceptButton:SetDisabled(true);

	elseif not m_IsInSession and m_ReviewTab == REVIEW_TAB_AVAILABLE_PROPOSALS then

		local totalCost:number = 0;
		for _, kVoteData in pairs(m_kProposalVotes) do
			totalCost = totalCost + kVoteData.cost;
		end
		local dialogText:string = Locale.Lookup("LOC_WORLD_CONGRESS_CONFIRM_SUBMIT_PROPOSALS", totalCost);

		m_kPopupDialog:Close();	-- clear out the popup incase it is already open.
		m_kPopupDialog:ShowOkCancelDialog(dialogText, function() 
			Controls.AcceptButton:SetDisabled(true);
			for _, kVoteData in pairs(m_kProposalVotes) do
				if not kVoteData.disabled and kVoteData.votes > 0 then
					local kParameters:table = {};
					kParameters[PlayerOperations.PARAM_OTHER_PLAYER] = kVoteData.data.Target;
					kParameters[PlayerOperations.PARAM_DISCUSSION_TYPE] = kVoteData.data.Type;
					UI.RequestPlayerOperation(playerID, PlayerOperations.WORLD_CONGRESS_DISCUSSION_SELECTION, kParameters);
				end
			end

			m_CurrentStage = 0;
			m_CurrentPhase = 0;
			m_kProposalVotes = {}

			OutputMessageToScreenReader( "Proposals submitted", true );		-- ScreenReaderAccess: the confirmation closed silently
			ClosePopup();

			if m_HasSpecialSessionNotification then
				LuaEvents.WorldCongressPopup_DismissSpecialSessionNotification();
			end
		end);
		m_kPopupDialog:Open();
	else
		UI.DataError("Invalid stage in OnAccept: '"..tostring(m_CurrentStage).."'");
	end

	if m_CurrentStage < 3 and not GameConfiguration.IsHotseat() then
		m_HasAccepted = true;
		LuaEvents.WorldCongressPopup_ShowWorldCongressBetweenTurns(m_CurrentStage);
		ClosePopup();
	end
end

-- ===========================================================================
-- Next Page Sequence Button
-- ===========================================================================
function OnNext()
	if CanMoveToNextPhase() and SetPhase(m_CurrentPhase + 1) then
		return true;
	end
end

-- ===========================================================================
-- Previous Page Sequence Button
-- ===========================================================================
function OnPrev()
	if m_CurrentPhase > 1 and SetPhase(m_CurrentPhase - 1) then
		return true;
	end
end

-- ===========================================================================
-- Deal with changing phases
-- ===========================================================================
function OnWorldCongressStageChange(playerID:number, stageNum:number)
	-- Account for Autoplay
	if playerID == Game.GetLocalPlayer() then --Problematic check? -sbatista
		SetupWorldCongress(stageNum);
	end
end

-- ===========================================================================
-- Deal with changing phases
-- ===========================================================================
function OnWorldCongressResults(selectedTab:number, delayShow:boolean)

	-- Ensure we're on the Active effects tab of WorldCongress
	if selectedTab then
		m_ReviewTab = selectedTab;
	end

	-- Account for AutoPlay
	if Game.GetLocalPlayer() >= 0 and SetStage(4) then
		ShowPopup(delayShow);
	end
end

-- ===========================================================================
--	The load screen has closed.  Check to see if we have to restore our state
-- ===========================================================================
function OnLoadScreenClose()
	CheckShouldOpen();
end

-- ===========================================================================
-- Open the Diplo Screen
-- ===========================================================================
function OnDiploButtonClicked()
	OpenDiplomacyLiteMode(Game.GetLocalPlayer());
end

-- ===========================================================================
-- Shows the popup
-- ===========================================================================
function ShowPopup(delayShow:boolean, fromHotLoad:boolean)
	if(GameConfiguration.IsPaused()) then
		return;
	end
	if ContextPtr:IsHidden() or fromHotLoad then
		UIManager:QueuePopup(ContextPtr, PopupPriority.WorldCongressPopup, { AlwaysVisibleInQueue = true, DelayShow = delayShow });
		Input.PushActiveContext( InputContext.Popup );

		RealizeSize(UIManager:GetScreenSizeVal());
		PopulateLeaderStack();
		PopulateBG();
	end
end

-- ===========================================================================
-- Closes the popup
-- ===========================================================================
function ClosePopup()
	LuaEvents.SRA_SpeechHold( "WorldCongressResults", false );		-- ScreenReaderAccess
	if ContextPtr:IsVisible() then
		UIManager:DequeuePopup(ContextPtr);
		Input.PopContext();
		UI.PlaySound("WC_Exit");

		-- Notify game core so turn blocker can be deactivated
		if not m_IsInSession then
			UI.RequestPlayerOperation(Game.GetLocalPlayer(), PlayerOperations.WORLD_CONGRESS_LOOKED_AT_AVAILABLE, {});
		end
	end
end

-- ===========================================================================
-- Reload support
-- ===========================================================================
function OnGameDebugReturn(context:string, contextTable:table)
	if context == RELOAD_CACHE_ID then
		if contextTable.IsVisible or ContextPtr:IsVisible() then
			m_ReviewTab = contextTable.ReviewTab;
			m_kProposalVotes = contextTable.ProposalVotes;
			m_kResolutionVotes = contextTable.ResolutionVotes;
			m_kResolutionChoices = contextTable.ResolutionChoices;
			m_HasSpecialSessionNotification = contextTable.HasSpecialSessionNotification;
			SetStage(contextTable.CurrentStage, true);
			SetPhase(contextTable.CurrentPhase);
			ShowPopup(false, true);
		end
	end
end

-- ===========================================================================
-- Reload support
-- ===========================================================================
function OnInit(isReload:boolean)
	LateInitialize();
	if isReload then
		LuaEvents.GameDebug_GetValues(RELOAD_CACHE_ID);
	end
end

-- ===========================================================================
-- Reload support
-- ===========================================================================
function OnShutdown()	
	--Stop listening
	LuaEvents.GameDebug_Return.Remove(OnGameDebugReturn);
	LuaEvents.WorldCongressIntro_ShowWorldCongress.Remove( OnShowFromIntro );
	SRUnlistenAll();		-- ScreenReaderAccess: the Events.X listeners of Initialize
	LuaEvents.CongressButton_ShowCongressResults.Remove(OnWorldCongressResults);
	LuaEvents.DiplomacyActionView_ShowCongressResults.Remove(OnWorldCongressResults);
	LuaEvents.NotificationPanel_ResumeCongress.Remove(OnResumeCongress);
	LuaEvents.CongressButton_ResumeCongress.Remove(OnResumeCongress);
	LuaEvents.DiplomacyActionView_ResumeCongress.Remove(OnResumeCongress);
	LuaEvents.WorldCongressBetweenTurns_ResumeCongress.Remove(OnResumeCongress);
	LuaEvents.DiplomacyActionView_HideCongress.Remove(OnCloseFromDiplomacy);
	LuaEvents.DiploBasePopup_HideUI.Remove(OnCloseFromDiplomacy);
	LuaEvents.NotificationPanel_OpenWorldCongressProposeEmergencies.Remove(OnWorldCongressEmergencyProposals);
	LuaEvents.NotificationPanel_OpenWorldCongressResults.Remove(OnOpenWorldCongressResultsNotification);
	LuaEvents.WorldCongressPopup_OnSpecialSessionNotificationAdded.Remove(OnSpecialSessionNotificationAdded);
	LuaEvents.WorldCongressPopup_OnSpecialSessionNotificationDismissed.Remove(OnSpecialSessionNotificationDismissed);

	LuaEvents.GameDebug_AddValue(RELOAD_CACHE_ID, "IsVisible", ContextPtr:IsVisible());
	LuaEvents.GameDebug_AddValue(RELOAD_CACHE_ID, "ReviewTab", m_ReviewTab);
	LuaEvents.GameDebug_AddValue(RELOAD_CACHE_ID, "CurrentStage", m_CurrentStage);
	LuaEvents.GameDebug_AddValue(RELOAD_CACHE_ID, "CurrentPhase", m_CurrentPhase);
	LuaEvents.GameDebug_AddValue(RELOAD_CACHE_ID, "HasSpecialSessionNotification", m_HasSpecialSessionNotification);
	LuaEvents.GameDebug_AddValue(RELOAD_CACHE_ID, "ResolutionVotes", DEBUG_RESET_DATA and {} or m_kResolutionVotes);
	LuaEvents.GameDebug_AddValue(RELOAD_CACHE_ID, "ProposalVotes", DEBUG_RESET_DATA and {} or m_kProposalVotes);
	LuaEvents.GameDebug_AddValue(RELOAD_CACHE_ID, "ResolutionChoices", DEBUG_RESET_DATA and {} or m_kResolutionChoices);

	if ContextPtr:IsVisible() then
		Input.PopContext();
	end
end

-- ===========================================================================
-- Begin ScreenReaderAccess mod change
--	Keyboard access and speech for the World Congress (docs/ingame-plan.md, World Congress).
--	Modes (SRA_Mode): "vote" (stage 1 / 2, phase 1: resolutions and proposals to vote on), "summary" (phase 2: review
--	before submitting), "review" (stage 4: last results / current effects / available proposals tabs). One KeyNavList
--	per mode, rebuilt from the popup's own state (m_kResolutionVotes, m_kProposalVotes, Game.GetWorldCongress())
--	at key time; the target chooser is a second list. Every action calls the screen's own function (OnVoteResolution,
--	OnVoteProposal, the pulldown selection callback, OnNext, OnAccept, ...), nothing is requested from the engine here.
-- ===========================================================================
local m_sraFocusOption:table = {};		-- resolution hash -> 1 or 2: the option the cursor looks at
local m_sraTargetHash = nil;			-- resolution hash while the target chooser is open
local m_sraPending:number = -1;			-- seconds until the opening announcement (< 0: none pending)
local m_sraPendingAge:number = 0;
local m_sraResetFocus:boolean = true;
local m_sraMainList:table = nil;
local m_sraTargetList:table = nil;

local function SRA_Say( text:string, nointerrupt:boolean )
	OutputMessageToScreenReader( text, nointerrupt );
end

local function SRA_Clean( text )
	if text == nil then return ""; end
	return WCText_Strip( CleanTextForSpeech( Locale.Lookup( text ) ) );
end

local function SRA_PlayerName( playerID )
	if playerID == nil or playerID < 0 or PlayerConfigurations[ playerID ] == nil then return ""; end
	return SRA_Clean( GetVisiblePlayerName( playerID ) );
end

local function SRA_SortedKeys( t:table )
	local keys:table = {};
	if t ~= nil then
		for k, _ in pairs( t ) do table.insert( keys, k ); end
	end
	table.sort( keys, function( a, b )
		if type( a ) == "number" and type( b ) == "number" then return a < b; end
		return tostring( a ) < tostring( b );
	end );
	return keys;
end

local function SRA_Mode()
	if m_CurrentStage == 1 or m_CurrentStage == 2 then
		if m_CurrentPhase == 1 then return "vote"; end
		if m_CurrentPhase == 2 then return "summary"; end
		return nil;
	elseif m_CurrentStage == 4 then
		return "review";
	end
	return nil;
end

local function SRA_HasTargets( kRD:table )
	return kRD.PossibleTargets ~= nil and next( kRD.PossibleTargets ) ~= nil;
end

-- True when pid is a civilization the local player has not met (false without a local player, e.g. autoplay).
local function SRA_IsUnmet( pid:number )
	local localID:number = Game.GetLocalPlayer();
	if localID == nil or localID < 0 or Players[ localID ] == nil or pid == localID then return false; end
	return not Players[ localID ]:GetDiplomacy():HasMet( pid );
end

-- Text of the target with this value of kResolutionChoice.target (nil: none chosen).
-- A player id taken from result data (ChosenThing / ResolutionTarget is the player id itself there, not an index of
-- PossibleTargets): the name, or "an unmet civilization" for one we have not met.
local function SRA_ReviewPlayerText( pid:number )
	if PlayerConfigurations[ pid ] == nil then return ""; end
	if SRA_IsUnmet( pid ) then
		return "an unmet civilization";
	end
	return SRA_Clean( GetVisiblePlayerName( pid ) );
end

local function SRA_TargetText( kRD:table, target )
	if target == nil or target == -1 then return nil; end
	local text = GetPulldownNameAndIcons( kRD, target );
	return SRA_Clean( text );
end

-- ---------------------------------------------------------------------------
--	Resolutions (voting stage)
-- ---------------------------------------------------------------------------
local function SRA_ResolutionFacts( index )
	local kVote:table = m_kResolutionVotes ~= nil and m_kResolutionVotes[ index ] or nil;
	if kVote == nil then return nil; end
	local kChoice:table = m_kResolutionChoices[ kVote.Hash ];
	local f:table = { vote = kVote, choice = kChoice, rd = kVote.A.kResolutionData, res = kVote.A.data, hash = kVote.Hash };
	f.name = SRA_Clean( f.res.Name );
	f.chosen = ( kChoice ~= nil and kChoice.choice ~= nil and kChoice.choice > 0 ) and kChoice.choice or 0;
	f.focus = m_sraFocusOption[ kVote.Hash ] or ( f.chosen ~= 0 and f.chosen ) or 1;
	if f.chosen == 1 then f.held = kVote.A; elseif f.chosen == 2 then f.held = kVote.B; end
	f.target = ( f.chosen ~= 0 ) and SRA_TargetText( f.rd, kChoice.target ) or nil;
	return f;
end

local function SRA_ResolutionDetail( f:table )
	local parts:table = { f.name };
	table.insert( parts, "Option A: " .. SRA_Clean( f.res.Effect1Description ) );
	table.insert( parts, "Option B: " .. SRA_Clean( f.res.Effect2Description ) );
	if SRA_HasTargets( f.rd ) then
		local count:number = 0;
		for _ in pairs( f.rd.PossibleTargets ) do count = count + 1; end
		local kind:string = ( f.rd.TargetType == "PlayerType" ) and "a civilization" or "a choice";
		table.insert( parts, "Needs a target, " .. kind .. ", " .. count .. " to choose from" .. ( f.target and ( ", now " .. f.target ) or ", none chosen yet" ) );
	end
	local ok:boolean, costData = pcall( function() return Game.GetWorldCongress():GetVotesandFavorCost( Game.GetLocalPlayer() ); end );
	if ok and costData ~= nil then table.insert( parts, "Votes: " .. WCText_CostList( costData, 4 ) ); end
	local favored:table, disfavored:table = {}, {};
	for _, id in pairs( f.rd.FavoredPlayerIDs or {} ) do table.insert( favored, SRA_PlayerName( id ) ); end
	for _, id in pairs( f.rd.DisfavoredPlayerIDs or {} ) do table.insert( disfavored, SRA_PlayerName( id ) ); end
	if #favored > 0 then table.insert( parts, "Favored by " .. table.concat( favored, ", " ) ); end
	if #disfavored > 0 then table.insert( parts, "Disfavored by " .. table.concat( disfavored, ", " ) ); end
	return table.concat( parts, ". " );
end

local function SRA_ResolutionItem( index )
	local f:table = SRA_ResolutionFacts( index );
	if f == nil then return nil; end
	local d:table = {
		name = f.name, focus = f.focus, chosen = f.chosen,
		effect = SRA_Clean( ( f.focus == 1 ) and f.res.Effect1Description or f.res.Effect2Description ),
		votes = f.held and f.held.votes or 0, cost = f.held and f.held.cost or 0,
		target = f.target, needsTarget = SRA_HasTargets( f.rd ),
	};
	return { key = "res:" .. f.hash, kind = "res", index = index, text = WCText_ResolutionLine( d ),
		detail = function() return SRA_ResolutionDetail( f ); end };
end

-- ---------------------------------------------------------------------------
--	Proposals (discussions, emergencies)
-- ---------------------------------------------------------------------------
-- Title and description of a proposal; the target player's name is a parameter of the game's text.
local function SRA_ProposalTexts( kProposal:table, targetID )
	if targetID ~= nil and targetID >= 0 and PlayerConfigurations[ targetID ] ~= nil then
		local name:string = GetVisiblePlayerName( targetID );
		return SRA_Clean( Locale.Lookup( kProposal.Name, name ) ), SRA_Clean( Locale.Lookup( kProposal.Description, name ) );
	end
	return SRA_Clean( kProposal.Name ), SRA_Clean( kProposal.Description );
end

local function SRA_EmergencyText( kProposal:table )
	local target = kProposal.Target or kProposal.TargetPlayer;
	if target == nil or kProposal.EmergencyType == nil then return ""; end
	local ok:boolean, text = pcall( function()
		local emergency:table = Game.GetEmergencyManager():GetSingleEmergency( target, kProposal.EmergencyType );
		return ( emergency ~= nil ) and SRA_Clean( emergency.ShortDescriptionText ) or "";
	end );
	return ok and text or "";
end

local function SRA_ProposalVoteItem( voteKey, kVote:table )
	local title:string, desc:string = SRA_ProposalTexts( kVote.data, kVote.data.Target );
	local signed:number = ( kVote.votes or 0 ) * ( kVote.voteDirection or 0 );
	return { key = "prop:" .. voteKey, kind = "prop", voteKey = voteKey,
		text = WCText_ProposalLine( title, desc, signed, kVote.cost ),
		detail = function()
			local extra:string = SRA_EmergencyText( kVote.data );
			return title .. ". " .. desc .. ( extra ~= "" and ( ". " .. extra ) or "" ) ..
				". Equals votes for it, minus votes against it";
		end };
end

-- ---------------------------------------------------------------------------
--	What blocks the Next / Submit step
-- ---------------------------------------------------------------------------
local function SRA_MissingText()
	local entries:table = {};
	for _, i in ipairs( SRA_SortedKeys( m_kResolutionVotes ) ) do
		local kVote:table = m_kResolutionVotes[ i ];
		local kChoice:table = m_kResolutionChoices[ kVote.Hash ];
		local needsVote:boolean = ( kVote.A.votes + kVote.B.votes ) <= 0;
		local needsTarget:boolean = ( not needsVote ) and ( kChoice == nil or kChoice.choice < 0 or kChoice.target < 0 );
		table.insert( entries, { name = SRA_Clean( kVote.A.data.Name ), needsVote = needsVote, needsTarget = needsTarget } );
	end
	for _, key in ipairs( SRA_SortedKeys( m_kProposalVotes ) ) do
		local kVote:table = m_kProposalVotes[ key ];
		if kVote.data ~= nil and kVote.votes == 0 and not ( kVote.voteBlocker and kVote.voteBlocker.NoUpvote and kVote.voteBlocker.NoDownvote ) then
			local title:string = SRA_ProposalTexts( kVote.data, kVote.data.Target );
			table.insert( entries, { name = title, needsVote = true } );
		end
	end
	return WCText_Missing( entries );
end

local function SRA_NextBlockedReason()
	if GameConfiguration.IsPaused() then return SRA_Clean( "LOC_WORLD_CONGRESS_TT_GAME_PAUSED" ); end
	local missing:string = SRA_MissingText();
	if missing ~= "" then return missing; end
	return SRA_Clean( "LOC_WORLD_CONGRESS_TT_SELECT_ALL" );
end

-- ---------------------------------------------------------------------------
--	Item lists
-- ---------------------------------------------------------------------------
local function SRA_VoteItems()
	local items:table = {};
	for _, i in ipairs( SRA_SortedKeys( m_kResolutionVotes ) ) do
		local item:table = SRA_ResolutionItem( i );
		if item ~= nil then table.insert( items, item ); end
	end
	for _, key in ipairs( SRA_SortedKeys( m_kProposalVotes ) ) do
		local kVote:table = m_kProposalVotes[ key ];
		if kVote.instance ~= nil and kVote.data ~= nil then table.insert( items, SRA_ProposalVoteItem( key, kVote ) ); end
	end
	local canNext:boolean = CanMoveToNextPhase();
	table.insert( items, { key = "next", kind = "next", text = "Next: review your votes before submitting", choosable = canNext,
		reason = SRA_NextBlockedReason(), detail = function() return canNext and "All votes and targets are set. Enter or N goes on" or SRA_NextBlockedReason(); end } );
	return items;
end

local function SRA_SummaryItems()
	local items:table = {};
	for _, i in ipairs( SRA_SortedKeys( m_kResolutionVotes ) ) do
		local f:table = SRA_ResolutionFacts( i );
		if f ~= nil and f.chosen ~= 0 and f.held ~= nil then
			local letter:string = WCText_Letter( f.chosen );
			local effect:string = SRA_Clean( ( f.chosen == 1 ) and f.res.Effect1Description or f.res.Effect2Description );
			local text:string = f.name .. ": option " .. letter .. ", " .. effect .. ", target " .. ( f.target or "none" ) ..
				", " .. WCText_VotesPhrase( f.held.votes, letter, f.held.cost );
			table.insert( items, { key = "sres:" .. f.hash, kind = "info", text = text, detail = text } );
		end
	end
	for _, key in ipairs( SRA_SortedKeys( m_kProposalVotes ) ) do
		local kVote:table = m_kProposalVotes[ key ];
		if kVote.data ~= nil then
			local title:string, desc:string = SRA_ProposalTexts( kVote.data, kVote.data.Target );
			local text:string = WCText_ProposalLine( title, desc, ( kVote.votes or 0 ) * ( kVote.voteDirection or 0 ), kVote.cost );
			table.insert( items, { key = "sprop:" .. key, kind = "info", text = text, detail = text } );
		end
	end
	-- Back to voting before Submit: End must land on Submit, not on the way back
	table.insert( items, { key = "back", kind = "back", text = "Back to voting", detail = "Goes back to the resolutions" } );
	table.insert( items, { key = "submit", kind = "submit", text = "Submit votes",
		detail = function() return "Sends your votes and ends your turn. " .. ( m_StartingFavor - m_WorkingFavor ) .. " favor spent, " .. m_WorkingFavor .. " left"; end } );
	return items;
end

-- Each voter's choice for a result resolution.
local function SRA_ReviewVoters( kRD:table )
	local parts:table = {};
	local unmetTails:table = {};
	for _, kData in pairs( kRD.PlayerSelections or {} ) do
		local target:string = "";
		if kRD.TargetType == "PlayerType" then
			local tid = tonumber( kData.ResolutionTarget );
			if tid ~= nil and tid ~= -1 then target = SRA_ReviewPlayerText( tid ); end
		else
			target = SRA_Clean( kData.ResolutionTarget );
		end
		local pid = tonumber( kData.PlayerID );
		local tail:string = WCText_Plural( kData.Votes, "vote" ) .. " for " .. SRA_Clean( kData.OptionChosenLabel );
		if target ~= "" then tail = tail .. ", target " .. target; end
		if pid ~= nil and PlayerConfigurations[ pid ] ~= nil and SRA_IsUnmet( pid ) then
			table.insert( unmetTails, tail );
		else
			table.insert( parts, SRA_PlayerName( pid ) .. ": " .. tail );
		end
	end
	for _, group in ipairs( WCText_UnmetGroups( unmetTails ) ) do table.insert( parts, group ); end
	return table.concat( parts, ". " );
end

-- A resolution of the last session (withVotes) or of the current effects (turnsLeft).
local function SRA_ReviewResolutionItem( kRD:table, withVotes:boolean, turnsLeft )
	local kRes:table = GameInfo.Resolutions[ kRD.Type ];
	if kRes == nil then return nil; end
	local aVotes:number, bVotes:number = 0, 0;
	if withVotes then
		for _, kData in pairs( kRD.PlayerSelections or {} ) do
			if kData.OptionChosen == 1 then aVotes = aVotes + kData.Votes; else bVotes = bVotes + kData.Votes; end
		end
	end
	local target:string = "";
	if kRD.TargetType == "PlayerType" then
		local pid = tonumber( kRD.ChosenThing );
		if pid ~= nil and pid ~= -1 then target = SRA_ReviewPlayerText( pid ); end
	else
		target = SRA_Clean( kRD.ChosenThing );
	end
	local name:string = SRA_Clean( kRes.Name );
	local text:string = WCText_ReviewResolution{ name = name, label = SRA_Clean( kRD.ChosenLabel ), tie = withVotes and aVotes == bVotes,
		target = target, effect = SRA_Clean( kRD.ChosenOption ),
		aVotes = withVotes and aVotes or nil, bVotes = withVotes and bVotes or nil, turnsLeft = turnsLeft };
	return { key = "rres:" .. tostring( kRD.Type ), kind = "info", text = text,
		detail = function()
			local parts:table = { text };
			if kRD.RejectedOption ~= nil then
				table.insert( parts, "Rejected outcome " .. SRA_Clean( kRD.RejectedLabel ) .. ": " .. SRA_Clean( kRD.RejectedOption ) );
			end
			local voters:string = withVotes and SRA_ReviewVoters( kRD ) or "";
			if voters ~= "" then table.insert( parts, voters ); end
			return table.concat( parts, ". " );
		end };
end

-- A proposal of the last session (with PlayerVotes) or of the current effects.
local function SRA_ReviewProposalItem( kProposal:table, withVotes:boolean )
	local target = kProposal.TargetPlayer or kProposal.Target;
	local title:string, desc:string = SRA_ProposalTexts( kProposal, target );
	local upVotes, downVotes = nil, nil;
	local voters:table = {};
	local unmetTails:table = {};
	if withVotes and kProposal.PlayerVotes ~= nil then
		upVotes, downVotes = 0, 0;
		for _, v in pairs( kProposal.PlayerVotes ) do
			if v.Votes > 0 then upVotes = upVotes + v.Votes; elseif v.Votes < 0 then downVotes = downVotes - v.Votes; end
			if v.Votes ~= 0 then
				local vid = tonumber( v.PlayerType );
				local tail:string = WCText_Plural( math.abs( v.Votes ), "vote" ) .. ( v.Votes > 0 and " for" or " against" );
				if vid ~= nil and PlayerConfigurations[ vid ] ~= nil and SRA_IsUnmet( vid ) then
					table.insert( unmetTails, tail );
				else
					table.insert( voters, SRA_PlayerName( vid ) .. ": " .. tail );
				end
			end
		end
		for _, group in ipairs( WCText_UnmetGroups( unmetTails ) ) do table.insert( voters, group ); end
	end
	local text:string = WCText_ReviewProposal( title, desc, upVotes, downVotes );
	return { key = "rprop:" .. tostring( kProposal.TypeName ) .. "_" .. tostring( target ) .. "_" .. tostring( kProposal.Sender ),
		kind = "info", text = text, detail = function()
			local extra:string = SRA_EmergencyText( kProposal );
			return text .. ( extra ~= "" and ( ". " .. extra ) or "" ) .. ( #voters > 0 and ( ". " .. table.concat( voters, ". " ) ) or "" );
		end };
end

local function SRA_AddCategoryProposals( items:table, categories:table, withVotes:boolean )
	for _, kSorted in ipairs( GetSortedProposalCategories( categories ) ) do
		for _, kProposal in pairs( kSorted.kCategory.ProposalsOfType ) do
			table.insert( items, SRA_ReviewProposalItem( kProposal, withVotes ) );
		end
	end
end

-- Why an available proposal cannot be (de)selected, from the same data the game uses for the check box.
local function SRA_ToggleBlockText( kVote:table )
	if kVote.proposalBlocker ~= nil then return SRA_Clean( kVote.proposalBlocker.Description ); end
	if kVote.disabled then return "Not available"; end
	for _, other in pairs( m_kProposalVotes ) do
		if other ~= kVote and other.votes > 0 and other.data.Target == kVote.data.Target then
			return SRA_Clean( "LOC_WORLD_CONGRESS_TT_MAX_ONE_PROPOSAL" );
		end
	end
	if kVote.votes == 0 and kVote.sraFavorCost ~= nil and m_WorkingFavor < kVote.sraFavorCost then
		return "Not enough favor, it costs " .. kVote.sraFavorCost .. " and you have " .. m_WorkingFavor;
	end
	return "Can't be selected now";
end

local function SRA_AvailableItems()
	local items:table = {};
	local categories:table = Game.GetWorldCongress():GetEmergencies( Game.GetLocalPlayer() ).Proposals;
	for _, kSorted in ipairs( GetSortedProposalCategories( categories ) ) do
		for _, kProposal in pairs( kSorted.kCategory.ProposalsOfType ) do
			local voteKey:string = GetProposalVoteKey( kProposal );
			local kVote:table = m_kProposalVotes ~= nil and m_kProposalVotes[ voteKey ] or nil;
			if kVote ~= nil and kVote.instance ~= nil then
				local title:string, desc:string = SRA_ProposalTexts( kProposal, kProposal.Target );
				local blocked:boolean = kVote.instance.SelectBox:IsDisabled();
				local state:string = ( kVote.votes ~= 0 ) and "selected" or "not selected";
				if kVote.sraFavorCost ~= nil and kVote.sraFavorCost > 0 then state = state .. ", costs " .. kVote.sraFavorCost .. " favor"; end
				local text:string = title .. ( desc ~= "" and ( ": " .. desc ) or "" ) .. ", " .. state;
				if blocked and kVote.votes == 0 then text = text .. ", unavailable: " .. SRA_ToggleBlockText( kVote ); end
				table.insert( items, { key = "eprop:" .. voteKey, kind = "eprop", voteKey = voteKey, text = text,
					detail = function()
						local extra:string = SRA_EmergencyText( kProposal );
						return text .. ( extra ~= "" and ( ". " .. extra ) or "" ) .. ". Enter selects or unselects it";
					end } );
			end
		end
	end
	if Controls.AcceptButton:IsVisible() then
		local canSubmit:boolean = CanSubmit();
		table.insert( items, { key = "submit", kind = "submit",
			text = SRA_Clean( m_HasSpecialSessionNotification and "LOC_WORLD_CONGRESS_ADD_PROPOSALS" or "LOC_WORLD_CONGRESS_SUBMIT" ) .. " selected proposals",
			choosable = canSubmit, reason = SRA_Clean( "LOC_WORLD_CONGRESS_TT_SELECT_ONE" ),
			detail = "Spends " .. ( m_StartingFavor - m_WorkingFavor ) .. " favor and calls a special session next turn" } );
	end
	if Controls.PassButton:IsVisible() then
		table.insert( items, { key = "pass", kind = "pass", text = SRA_Clean( "LOC_WORLD_CONGRESS_PASS" ), detail = "Passes on the special session" } );
	end
	return items;
end

local function SRA_ReviewItems()
	local items:table = {};
	local pid:number = Game.GetLocalPlayer();
	local pWorldCongress:table = Game.GetWorldCongress();
	if m_ReviewTab == REVIEW_TAB_RESULTS then
		local kReview:table = pWorldCongress:GetReview( pid );
		if kReview ~= nil then
			for _, k in ipairs( SRA_SortedKeys( kReview.Resolutions ) ) do
				local kRD = kReview.Resolutions[ k ];
				if type( kRD ) == "table" then
					local item:table = SRA_ReviewResolutionItem( kRD, true, nil );
					if item ~= nil then table.insert( items, item ); end
				end
			end
			SRA_AddCategoryProposals( items, kReview.Discussions, true );
		end
	elseif m_ReviewTab == REVIEW_TAB_CURRENT_EFFECTS then
		local turnsLeft:number = pWorldCongress:GetMeetingStatus().TurnsLeft + 1;
		local kResolutions:table = pWorldCongress:GetResolutions( pid );
		for _, k in ipairs( SRA_SortedKeys( kResolutions ) ) do
			local kRD = kResolutions[ k ];
			if type( kRD ) == "table" then
				local item:table = SRA_ReviewResolutionItem( kRD, false, turnsLeft );
				if item ~= nil then table.insert( items, item ); end
			end
		end
		SRA_AddCategoryProposals( items, pWorldCongress:GetProposals( pid ).Proposals, false );
	else
		items = SRA_AvailableItems();
	end
	return items;
end

local function SRA_BuildItems()
	local mode:string = SRA_Mode();
	if mode == "vote" then return SRA_VoteItems(); end
	if mode == "summary" then return SRA_SummaryItems(); end
	if mode == "review" then return SRA_ReviewItems(); end
	return {};
end

local function SRA_FindItem( key )
	for _, item in ipairs( SRA_BuildItems() ) do
		if item.key == key then return item; end
	end
	return nil;
end

-- ---------------------------------------------------------------------------
--	Actions
-- ---------------------------------------------------------------------------
local function SRA_CostData()
	return Game.GetWorldCongress():GetVotesandFavorCost( Game.GetLocalPlayer() );
end

-- Adds (direction 1) or removes (-1) a vote on the option the cursor looks at. Returns true when the vote changed.
local function SRA_VoteResolution( item:table, direction:number )
	local f:table = SRA_ResolutionFacts( item.index );
	if f == nil then return false; end
	local kData:table = ( f.focus == 1 ) and f.vote.A or f.vote.B;
	local kCost:table = SRA_CostData();
	local why = WCText_VoteBlock( kData.votes, direction, kCost, m_WorkingFavor );
	if why ~= nil then SRA_Say( why ); return false; end
	local before:number = kData.votes;
	OnVoteResolution( f.focus, ( direction > 0 ) and UP_VOTE or DOWN_VOTE, kData, kCost )();
	if kData.votes == before and f.chosen == f.focus then
		SRA_Say( "The vote did not change" );
		return false;
	end
	local letter:string = WCText_Letter( f.focus );
	local parts:table = {};
	if f.chosen ~= 0 and f.chosen ~= f.focus then table.insert( parts, "Switched to option " .. letter ); end
	table.insert( parts, WCText_VotesPhrase( kData.votes, letter, kData.cost ) );
	table.insert( parts, m_WorkingFavor .. " favor left" );
	local after:table = SRA_ResolutionFacts( item.index );
	if after ~= nil and after.target == nil and SRA_HasTargets( after.rd ) then table.insert( parts, "target needed, T to choose" ); end
	SRA_Say( table.concat( parts, ", " ) );
	return true;
end

local function SRA_VoteProposal( item:table, direction:number )
	local kVote:table = m_kProposalVotes[ item.voteKey ];
	if kVote == nil then return; end
	local blocker:table = kVote.voteBlocker;
	if blocker ~= nil then
		local starting:boolean = ( kVote.votes == 0 );
		if ( blocker.NoUpvote and blocker.NoDownvote ) or ( starting and direction > 0 and blocker.NoUpvote ) or ( starting and direction < 0 and blocker.NoDownvote ) then
			SRA_Say( SRA_Clean( blocker.Description ) );
			return;
		end
	end
	local kCost:table = kVote.sraCostData or SRA_CostData();
	local before:number = ( kVote.votes or 0 ) * ( kVote.voteDirection or 0 );
	OnVoteProposal( direction, kVote, kCost )();
	if kVote.votes == 0 then kVote.voteDirection = NO_VOTE; end		-- the game leaves a stale direction after a refused first vote
	local after:number = ( kVote.votes or 0 ) * ( kVote.voteDirection or 0 );
	if after == before then
		SRA_Say( direction > 0 and "No more votes: not enough favor or at the maximum" or "No votes to take back" );
		return;
	end
	local title:string = SRA_ProposalTexts( kVote.data, kVote.data.Target );
	local text:string = ( after == 0 ) and "No votes" or ( WCText_Plural( math.abs( after ), "vote" ) .. ( after > 0 and " for" or " against" ) );
	if after ~= 0 and title ~= nil and title ~= "" then text = text .. " " .. title; end
	if kVote.cost ~= nil and kVote.cost > 0 then
		text = text .. ", costs " .. kVote.cost .. " favor";
	elseif after ~= 0 then
		text = text .. ", free";
	end
	SRA_Say( text .. ", " .. m_WorkingFavor .. " favor left" );
end

local function SRA_KeyVote( direction:number )
	local mode:string = SRA_Mode();
	local item:table = SRA_FindItem( m_sraMainList.GetFocusKey() );
	if mode ~= "vote" or item == nil or ( item.kind ~= "res" and item.kind ~= "prop" ) then
		SRA_Say( "Nothing to vote on here" );
		return;
	end
	if item.kind == "res" then SRA_VoteResolution( item, direction ); else SRA_VoteProposal( item, direction ); end
end

-- Left / Right: option A / B of a resolution (voting), the other tab (results).
local function SRA_KeyHorizontal( delta:number )
	local mode:string = SRA_Mode();
	if mode == "review" then
		SRA_SwitchTab( delta );
		return;
	end
	if mode ~= "vote" then return; end
	local item:table = SRA_FindItem( m_sraMainList.GetFocusKey() );
	if item == nil or item.kind ~= "res" then return; end
	local f:table = SRA_ResolutionFacts( item.index );
	m_sraFocusOption[ f.hash ] = ( delta < 0 ) and 1 or 2;
	m_sraMainList.Focus( item.key );
end

function SRA_SwitchTab( delta:number )
	local tabs:table = { REVIEW_TAB_RESULTS, REVIEW_TAB_CURRENT_EFFECTS };
	if HasEmergencyProposals() then table.insert( tabs, REVIEW_TAB_AVAILABLE_PROPOSALS ); end
	local current:number = 1;
	for i, tab in ipairs( tabs ) do
		if tab == m_ReviewTab then current = i; end
	end
	local nextIndex:number = current + ( ( delta < 0 ) and -1 or 1 );
	if nextIndex < 1 then nextIndex = #tabs; end
	if nextIndex > #tabs then nextIndex = 1; end
	if #tabs == 1 then
		SRA_Say( "No other tab" );
		return;
	end
	OnWorldCongressResults( tabs[ nextIndex ] );		-- the screen's own tab buttons; SetStage announces the new tab
end

local function SRA_OpenTargets( item:table )
	local f:table = SRA_ResolutionFacts( item.index );
	if f == nil then return; end
	if not SRA_HasTargets( f.rd ) then
		SRA_Say( "This resolution has no target" );
		return;
	end
	-- the target belongs to the option that holds the votes: vote for the option the cursor looks at first
	if f.chosen ~= f.focus or f.held == nil or f.held.votes < 1 then
		if not SRA_VoteResolution( item, 1 ) then return; end
		f = SRA_ResolutionFacts( item.index );
		if f.chosen ~= f.focus then return; end
	end
	if f.choice.sraTargets == nil then
		PopulateChoicePulldown( f.choice, ( f.chosen == 1 ) and f.vote.A or f.vote.B );
	end
	local targets:table = f.choice.sraTargets;
	if targets == nil or #targets == 0 then
		SRA_Say( "No targets to choose from" );
		return;
	end
	local current = nil;
	for n, entry in ipairs( targets ) do
		if entry.id == f.choice.target then current = n; end
	end
	m_sraTargetHash = f.hash;
	m_sraTargetList.Reset();
	m_sraTargetList.Open( "Target for " .. f.name, current );
end

local function SRA_TargetItems()
	local items:table = {};
	local kChoice:table = ( m_sraTargetHash ~= nil and m_kResolutionChoices ~= nil ) and m_kResolutionChoices[ m_sraTargetHash ] or nil;
	if kChoice == nil or kChoice.sraTargets == nil then return items; end
	for n, entry in ipairs( kChoice.sraTargets ) do
		local name:string = SRA_Clean( entry.text );
		table.insert( items, { key = n, text = name .. ( ( entry.id == kChoice.target ) and ", current" or "" ), entry = entry, name = name } );
	end
	return items;
end

local function SRA_OnTargetActivate( item:table )
	local hash = m_sraTargetHash;
	local kChoice:table = m_kResolutionChoices[ hash ];
	if kChoice == nil or kChoice.sraSelect == nil then return; end
	kChoice.sraSelect( item.entry.a1, item.entry.a2 );		-- the pulldown's own selection callback
	m_sraTargetHash = nil;
	m_sraMainList.Focus( "res:" .. hash, "Target: " .. item.name );
end

local function SRA_OnTargetClose()
	local hash = m_sraTargetHash;
	m_sraTargetHash = nil;
	m_sraMainList.Focus( "res:" .. tostring( hash ), "Back" );
end

local function SRA_CloseSpoken()
	local mode:string = SRA_Mode();
	local blocking:boolean = m_IsInSession and ( mode == "vote" or mode == "summary" );
	m_sraTargetHash = nil;
	m_sraPending = -1;
	ClosePopup();
	if blocking then
		SRA_Say( "Closed. Resume Congress still blocks the turn; Enter or Control+N reopens it." );
	else
		SRA_Say( "World Congress closed" );
		LuaEvents.SRA_CongressClosedSpoken();		-- a crisis popup that opened meanwhile was cut off by this line: it speaks again
	end
end

local function SRA_Submit()
	if GameConfiguration.IsPaused() then
		SRA_Say( SRA_Clean( "LOC_WORLD_CONGRESS_TT_GAME_PAUSED" ) );
		return;
	end
	SRA_Say( "Votes submitted" );
	OnAccept();
end

local function SRA_SubmitProposals()
	if GameConfiguration.IsPaused() then
		SRA_Say( SRA_Clean( "LOC_WORLD_CONGRESS_TT_GAME_PAUSED" ) );
		return;
	end
	if not CanSubmit() then
		SRA_Say( SRA_Clean( "LOC_WORLD_CONGRESS_TT_SELECT_ONE" ) );
		return;
	end
	OnAccept();		-- opens the game's confirmation dialog, which speaks itself
end

-- N: the forward step of the current stage.
local function SRA_Forward()
	local mode:string = SRA_Mode();
	if mode == "vote" then
		if not CanMoveToNextPhase() then
			SRA_Say( SRA_NextBlockedReason() );
			return;
		end
		OnNext();		-- SetPhase announces the review
	elseif mode == "summary" then
		SRA_Submit();
	elseif mode == "review" then
		if m_ReviewTab == REVIEW_TAB_AVAILABLE_PROPOSALS and Controls.AcceptButton:IsVisible() then
			SRA_SubmitProposals();
		else
			SRA_CloseSpoken();
		end
	end
end

local function SRA_ToggleProposal( item:table )
	local kVote:table = m_kProposalVotes[ item.voteKey ];
	if kVote == nil or kVote.sraToggle == nil then return; end
	if kVote.instance.SelectBox:IsDisabled() then
		SRA_Say( SRA_ToggleBlockText( kVote ) );
		return;
	end
	kVote.sraToggle();		-- OnToggleProposal: the check box callback
	m_sraMainList.Focus( item.key );
end

local function SRA_OnActivate( item:table )
	local mode:string = SRA_Mode();
	if item.kind == "res" then
		SRA_OpenTargets( item );
	elseif item.kind == "next" or item.kind == "submit" then
		SRA_Forward();
	elseif item.kind == "back" then
		OnPrev();
	elseif item.kind == "pass" then
		SRA_Say( "Passed" );
		OnPass();
	elseif item.kind == "eprop" then
		SRA_ToggleProposal( item );
	elseif mode == "review" then
		SRA_CloseSpoken();		-- results and current effects: Enter continues, as the game's Enter does
	else
		local detail = item.detail;
		if type( detail ) == "function" then detail = detail(); end
		SRA_Say( detail or item.text );
	end
end

local function SRA_Help()
	local mode:string = SRA_Mode();
	if mode == "vote" then
		SRA_Say( "Up and Down move between resolutions and proposals. Left and Right choose option A or B. Equals or Shift Up adds a vote, minus or Shift Down removes one. T or Enter chooses the target. Space reads the whole resolution. N or the last item reviews your votes. Escape closes the screen; Resume Congress reopens it." );
	elseif mode == "summary" then
		SRA_Say( "Up and Down read your choices. Enter on Submit votes, or N, sends them and ends your turn. Back to voting, just before Submit, returns. End jumps to Submit votes. Escape closes the screen." );
	elseif m_ReviewTab == REVIEW_TAB_AVAILABLE_PROPOSALS then
		SRA_Say( "Up and Down move. Enter selects or unselects a proposal. Space reads details. N or the Submit item sends them. Left and Right switch tabs. Escape closes." );
	else
		SRA_Say( "Up and Down read the results. Space reads who voted how. Left and Right switch tabs. Enter, N or Escape closes the screen." );
	end
end

-- ---------------------------------------------------------------------------
--	Announcements
-- ---------------------------------------------------------------------------
local function SRA_TabName()
	if m_ReviewTab == REVIEW_TAB_CURRENT_EFFECTS then return "Current effects"; end
	if m_ReviewTab == REVIEW_TAB_AVAILABLE_PROPOSALS then return "Available proposals"; end
	return "World Congress results";
end

local function SRA_Announce()
	local mode:string = SRA_Mode();
	if mode == nil or ContextPtr:IsHidden() then return; end
	if m_sraResetFocus then
		m_sraMainList.Reset();
		m_sraFocusOption = {};
		m_sraResetFocus = false;
	end
	m_sraTargetHash = nil;
	local items:table = SRA_BuildItems();
	local head:string, hint:string;
	if mode == "vote" then
		local resolutions:number, proposals:number = 0, 0;
		for _, item in ipairs( items ) do
			if item.kind == "res" then resolutions = resolutions + 1; elseif item.kind == "prop" then proposals = proposals + 1; end
		end
		local parts:table = {};
		if resolutions > 0 then table.insert( parts, "Resolutions: " .. resolutions .. " to vote on" ); end
		if proposals > 0 then table.insert( parts, WCText_Plural( proposals, "proposal" ) .. " to vote on" ); end
		head = ( m_CurrentStage == 2 and "Special session. " or "World Congress. " ) .. table.concat( parts, ", " ) ..
			". You have " .. m_WorkingFavor .. " diplomatic favor";
		if resolutions > 0 then
			local costData:table = SRA_CostData();
			local free:number = 0;
			while costData[ free ] ~= nil and costData[ free ] == 0 do free = free + 1; end
			if free > 0 then head = head .. ", " .. WCText_Plural( free, "free vote" ) .. " each"; end
		end
		hint = "H for keys";
	elseif mode == "summary" then
		head = "Review your votes. " .. ( m_StartingFavor - m_WorkingFavor ) .. " favor spent, " .. m_WorkingFavor .. " left";
		hint = "Enter on Submit votes sends them";
	else
		head = SRA_TabName();
		if #items == 0 then
			local empty:string = Controls.EmptyLabel:IsHidden() and "" or SRA_Clean( Controls.EmptyLabel:GetText() );
			SRA_Say( head .. ". " .. ( empty ~= "" and empty or "Nothing to show" ) .. ". Escape closes", false );
			return;
		end
		if m_ReviewTab == REVIEW_TAB_AVAILABLE_PROPOSALS then
			hint = "Enter selects, Left or Right switches tab, Escape closes";
		else
			hint = "Enter to continue, Space for details, Left or Right for other tabs";
		end
	end
	if #items == 0 then
		SRA_Say( head .. ". Nothing available", true );
		return;
	end
	m_sraMainList.Open( "", nil, true );		-- silent: sets the focus (the first item, or the one kept)
	local index:number = 1;
	for i, item in ipairs( items ) do
		if item.key == m_sraMainList.GetFocusKey() then index = i; end
	end
	-- results (mode "review") interrupt: the player just finished the congress and the results come before the unit line;
	-- the hub speech hold (SRA_RequestAnnounce) says the cut-off lines again after the screen closes.
	SRA_Say( head .. ". " .. items[ index ].text .. ", " .. index .. " of " .. #items .. ". " .. hint, mode ~= "review" );
end

-- Called by the screen after the stage / phase changed or the popup was reopened. The announcement waits a moment so
-- the populate calls and the popup queue have settled.
function SRA_RequestAnnounce( resetFocus:boolean )
	-- results screen: the hub's own announcements (notifications ...) wait until it closes; lines it cut off are repeated then
	if m_CurrentStage == 4 then
		LuaEvents.SRA_SpeechHold( "WorldCongressResults", true, "/InGame/" .. ContextPtr:GetID() );
	end
	m_sraPending = 0.4;
	m_sraPendingAge = 0;
	if resetFocus then m_sraResetFocus = true; end
end

function SRA_OnUpdate( deltaTime:number )
	if m_sraPending < 0 then return; end
	m_sraPendingAge = m_sraPendingAge + deltaTime;
	if m_sraPendingAge > 5 then m_sraPending = -1; return; end		-- the popup never became visible
	if ContextPtr:IsHidden() then return; end
	m_sraPending = m_sraPending - deltaTime;
	if m_sraPending > 0 then return; end
	m_sraPending = -1;
	local ok:boolean, err = xpcall( SRA_Announce, KeyNavErrorHandler );
	if not ok then print( "WorldCongressPopup announce error: " .. tostring( err ) ); end
end

-- ---------------------------------------------------------------------------
--	Input
-- ---------------------------------------------------------------------------
function SRA_CreateLists()
	-- a key the engine does not know would make the table constructor fail: add them one by one
	local extra:table = {};
	local function Bind( key, fn )
		if key ~= nil then extra[ key ] = fn; end
	end
	Bind( Keys.VK_LEFT, function() SRA_KeyHorizontal( -1 ); end );
	Bind( Keys.VK_RIGHT, function() SRA_KeyHorizontal( 1 ); end );
	Bind( Keys.VK_OEM_PLUS, function() SRA_KeyVote( 1 ); end );
	Bind( Keys.VK_OEM_MINUS, function() SRA_KeyVote( -1 ); end );
	Bind( Keys.VK_TAB, function() if SRA_Mode() == "review" then SRA_SwitchTab( 1 ); end end );
	Bind( Keys.T, function()
		local item:table = SRA_FindItem( m_sraMainList.GetFocusKey() );
		if SRA_Mode() == "vote" and item ~= nil and item.kind == "res" then SRA_OpenTargets( item ); else SRA_Say( "No target here" ); end
	end );
	Bind( Keys.N, SRA_Forward );
	Bind( Keys.H, SRA_Help );
	m_sraMainList = KeyNavList_Create{
		build = SRA_BuildItems,
		isActive = function() return not ContextPtr:IsHidden() and m_sraTargetHash == nil; end,
		onActivate = SRA_OnActivate,
		onClose = SRA_CloseSpoken,
		extraKeys = extra,
	};
	m_sraTargetList = KeyNavList_Create{
		build = SRA_TargetItems,
		isActive = function() return not ContextPtr:IsHidden() and m_sraTargetHash ~= nil; end,
		onActivate = SRA_OnTargetActivate,
		onClose = SRA_OnTargetClose,
	};
end

-- Every keyboard event is swallowed while the popup is shown (the game's own handler passed most keys on to the map).
function SRA_HandleInput( pInputStruct:table )
	if ContextPtr:IsHidden() then return false; end
	local msg:number = pInputStruct:GetMessageType();
	if msg ~= KeyEvents.KeyDown and msg ~= KeyEvents.KeyUp then return false; end
	local key:number = pInputStruct:GetKey();

	-- the game's OK / Cancel dialog (submitting proposals) is operated with Up/Down/Enter, Escape cancels
	if m_kPopupDialog:IsOpen() then
		if msg == KeyEvents.KeyUp then
			if key == Keys.VK_ESCAPE then
				m_kPopupDialog:Close();
				SRA_Say( "Cancelled" );
			else
				xpcall( function() m_kPopupDialog:KeyHandler( key ); end, KeyNavErrorHandler );
			end
		end
		return true;
	end

	if pInputStruct:IsShiftDown() and not pInputStruct:IsControlDown() and not pInputStruct:IsAltDown() then
		local direction:number = 0;
		if key == Keys.VK_UP or key == Keys.VK_OEM_PLUS then direction = 1;
		elseif key == Keys.VK_DOWN or key == Keys.VK_OEM_MINUS then direction = -1; end
		if direction ~= 0 and m_sraTargetHash == nil then
			if msg == KeyEvents.KeyUp then
				local ok:boolean, err = xpcall( function() SRA_KeyVote( direction ); end, KeyNavErrorHandler );
				if not ok then print( "WorldCongressPopup vote error: " .. tostring( err ) ); end
			end
			return true;
		end
		if key == Keys.VK_TAB and SRA_Mode() == "review" then
			if msg == KeyEvents.KeyUp then xpcall( function() SRA_SwitchTab( -1 ); end, KeyNavErrorHandler ); end
			return true;
		end
	end

	if m_sraTargetList.HandleInput( pInputStruct ) or m_sraMainList.HandleInput( pInputStruct ) then return true; end
	return true;
end
-- End ScreenReaderAccess mod change

-- ===========================================================================
-- Consume all input except VK_ESCAPE
-- ===========================================================================
function OnInputHandler( pInputStruct:table )
	if SRA_HandleInput( pInputStruct ) then return true; end		-- ScreenReaderAccess
	local uiMsg = pInputStruct:GetMessageType();
	local key = pInputStruct:GetKey();
	if uiMsg == KeyEvents.KeyUp then
		if key == Keys.VK_ESCAPE then
			ClosePopup();
			return true;
		elseif key == Keys.VK_RETURN then
			if m_CurrentStage == 4 then
				if m_ReviewTab == REVIEW_TAB_AVAILABLE_PROPOSALS then
					if CanSubmit() then
						OnAccept();
					end
				else
					ClosePopup();
				end
			elseif m_CurrentPhase == PHASE_STEP_MAX then
				OnAccept();
			elseif CanMoveToNextPhase() then
				SetPhase(m_CurrentPhase + 1);
			end
			return true;
		end
	end
	return false;
end

-- ===========================================================================
--	Callback that gets fired when WorldCongressIntro is closed
-- ===========================================================================
function OnShowFromIntro()
	UI.PlaySound("WC_BeginVoting");
	if m_IsInSession then		
		SetupWorldCongress(m_CurrentStage, true);
	end
end

-- ===========================================================================
--	Callback that closes popup
-- ===========================================================================
function OnClose()
	ClosePopup();
end

-- ===========================================================================
--	LUA Event
-- ===========================================================================
function OnCloseFromDiplomacy()
	ClosePopup();
end

function OnPass()
	ClosePopup();
	LuaEvents.WorldCongressPopup_DismissSpecialSessionNotification();
end

-- ===========================================================================
-- Reopen the screen
-- ===========================================================================
function OnResumeCongress()
	PopulateLeaderStack();
	if not m_HasAccepted and (not m_IsInSession or HasChoices()) then
		UIManager:QueuePopup(ContextPtr, PopupPriority.WorldCongressPopup, { AlwaysVisibleInQueue = true });
		Input.PushActiveContext( InputContext.Popup );
		SRA_RequestAnnounce( false );		-- ScreenReaderAccess
	elseif not GameConfiguration.IsHotseat() then
		LuaEvents.WorldCongressPopup_ShowWorldCongressBetweenTurns(m_CurrentStage);
	end
end

-- ===========================================================================
-- Open the screen in the Emergency Proposals tab
-- ===========================================================================
function OnWorldCongressEmergencyProposals()
	if HasEmergencyProposals() then
		 OnWorldCongressResults(REVIEW_TAB_AVAILABLE_PROPOSALS);
	end
end

-- ===========================================================================
-- Flush vote data to ensure every congress has isolated data
-- ===========================================================================
function OnLocalPlayerTurnEnd()	
	m_kProposalVotes = nil;
	m_kResolutionVotes = nil;
	m_kResolutionChoices = nil;		
	m_kProposalItemIM:ResetInstances();
	m_kEmergencyProposalIM:ResetInstances();
	
	ClosePopup();	-- Always close due to timeout in MP not reseting all data	
end

-- ===========================================================================
-- Update Turn Timers
-- ===========================================================================
function OnTurnTimerUpdated(elapsedTime :number, maxTurnTime :number)
	if ContextPtr:IsHidden() then return; end
	if maxTurnTime <= 0 then
		-- We're in a state where there isn't a turn time, hide all the turn timer elements.
		Controls.NextButton:SetText(Locale.Lookup("LOC_WORLD_CONGRESS_NEXT"));
		Controls.AcceptButton:SetText(Locale.Lookup("LOC_WORLD_CONGRESS_SUBMIT"));
		Controls.ReturnButton:SetText(Locale.Lookup("LOC_WORLD_CONGRESS_RETURN"));
	else
		local timeLeft:number = SoftRound(maxTurnTime - elapsedTime);
		local timeLeftLabel:string = " (" .. FormatTimeRemaining(timeLeft, true) .. ")";
		Controls.NextButton:SetText(Locale.Lookup("LOC_WORLD_CONGRESS_NEXT") .. timeLeftLabel);
		Controls.AcceptButton:SetText(Locale.Lookup("LOC_WORLD_CONGRESS_SUBMIT") .. timeLeftLabel);
		Controls.ReturnButton:SetText(Locale.Lookup("LOC_WORLD_CONGRESS_RETURN") .. timeLeftLabel);
	end
end

-- ===========================================================================
function OnGameConfigChanged()
	if(ContextPtr:IsVisible()) then
		-- Update the navigation buttons.  The pause state might have changed.
		UpdateNavButtons();
	end
end

-- ===========================================================================
function OnUpdateUI( type:number, tag:string, iData1:number, iData2:number, strData1:string)
	if type == SystemUpdateUI.ScreenResize then
		RealizeSize(UIManager:GetScreenSizeVal());
		PopulateLeaderStack();
		PopulateBG();
	end
end

-- ===========================================================================
function AssignActivePulldown(pulldown:table)
	m_kActivePulldown = pulldown;
end

-- ===========================================================================
function CloseActivePulldown()
	if(m_kActivePulldown ~= nil) then
		if(m_kActivePulldown:IsOpen()) then
			m_kActivePulldown:ForceClose();
		end
	end
end

-- ===========================================================================
--	Initialize
-- ===========================================================================
function LateInitialize()
	Controls.AcceptButton:RegisterCallback(Mouse.eLClick, OnAccept);
	Controls.ReturnButton:RegisterCallback(Mouse.eLClick, OnClose);
	Controls.PassButton:RegisterCallback(Mouse.eLClick, OnPass);
	Controls.NextButton:RegisterCallback(Mouse.eLClick, OnNext);
	Controls.PrevButton:RegisterCallback(Mouse.eLClick, OnPrev);
	Controls.DiploButton:RegisterCallback(Mouse.eLClick, OnDiploButtonClicked);
	Controls.HideButton:RegisterCallback(Mouse.eLClick, OnClose);
	Controls.LastResultsButton:RegisterCallback(Mouse.eLClick, function() OnWorldCongressResults(REVIEW_TAB_RESULTS); end);
	Controls.CurrentEffectsButton:RegisterCallback(Mouse.eLClick, function() OnWorldCongressResults(REVIEW_TAB_CURRENT_EFFECTS); end);
	Controls.AvailableProposalsButton:RegisterCallback(Mouse.eLClick, function() OnWorldCongressResults(REVIEW_TAB_AVAILABLE_PROPOSALS); end);
	Controls.DescriptionContainer:RegisterSizeChanged(function() RealizeSize(UIManager:GetScreenSizeVal()); end);

	LuaEvents.GameDebug_Return.Add(OnGameDebugReturn);
	LuaEvents.WorldCongressIntro_ShowWorldCongress.Add( OnShowFromIntro );
	LuaEvents.CongressButton_ShowCongressResults.Add(OnWorldCongressResults);
	LuaEvents.DiplomacyActionView_ShowCongressResults.Add(OnWorldCongressResults);
	LuaEvents.NotificationPanel_ResumeCongress.Add(OnResumeCongress);
	LuaEvents.CongressButton_ResumeCongress.Add(OnResumeCongress);
	LuaEvents.DiplomacyActionView_ResumeCongress.Add(OnResumeCongress);
	LuaEvents.WorldCongressBetweenTurns_ResumeCongress.Add(OnResumeCongress);
	LuaEvents.DiplomacyActionView_HideCongress.Add(OnCloseFromDiplomacy);
	LuaEvents.DiploBasePopup_HideUI.Add(OnCloseFromDiplomacy);
	LuaEvents.NotificationPanel_OpenWorldCongressProposeEmergencies.Add(OnWorldCongressEmergencyProposals);
	LuaEvents.NotificationPanel_OpenWorldCongressResults.Add(OnOpenWorldCongressResultsNotification);
	LuaEvents.WorldCongressPopup_OnSpecialSessionNotificationAdded.Add(OnSpecialSessionNotificationAdded);
	LuaEvents.WorldCongressPopup_OnSpecialSessionNotificationDismissed.Add(OnSpecialSessionNotificationDismissed);

	table.insert(m_kPreviousTooltipEvaluators, EvaluateTiebroken);
	table.insert(m_kPreviousTooltipEvaluators, EvaluateNeckAndNeck);
	table.insert(m_kPreviousTooltipEvaluators, EvaluateUnanimous);
	table.insert(m_kPreviousTooltipEvaluators, EvaluateMajorityLeader);
	table.insert(m_kPreviousTooltipEvaluators, EvaluateSoleVoter);
end

-- ===========================================================================
--	Callback Helpers
-- ===========================================================================
function OnOpenWorldCongressResultsNotification() 
	OnWorldCongressResults(REVIEW_TAB_RESULTS, true); 
end

function OnSpecialSessionNotificationAdded() 
	m_HasSpecialSessionNotification = true;
end

function OnSpecialSessionNotificationDismissed() 
	m_HasSpecialSessionNotification = false; 
end

-- ===========================================================================
--	Initialize
-- ===========================================================================
function Initialize()
	ContextPtr:SetInputHandler(OnInputHandler, true);
	ContextPtr:SetInitHandler(OnInit);
	ContextPtr:SetShutdown(OnShutdown);
	ContextPtr:SetUpdate( SRA_OnUpdate );		-- ScreenReaderAccess
	SRA_CreateLists();							-- ScreenReaderAccess

	-- ScreenReaderAccess: SRListen so that a hot reload does not leave this instance's listeners behind (SRUnlistenAll in OnShutdown)
	SRListen( Events.SystemUpdateUI, OnUpdateUI );
	SRListen( Events.LoadScreenClose, OnLoadScreenClose );
	SRListen( Events.WorldCongressStage1, function(i) OnWorldCongressStageChange(i, 1); end );
	SRListen( Events.WorldCongressStage2, function(i) OnWorldCongressStageChange(i, 2); end );
	SRListen( Events.LocalPlayerTurnEnd, OnLocalPlayerTurnEnd );
	SRListen( Events.TurnTimerUpdated, OnTurnTimerUpdated );
	SRListen( Events.GameConfigChanged, OnGameConfigChanged );
	SRListen( Events.UserRequestClose, CloseActivePulldown );
end

--No capability means never initialize this so it can never be used.
if GameCapabilities.HasCapability("CAPABILITY_WORLD_CONGRESS") then
	Initialize();
end
