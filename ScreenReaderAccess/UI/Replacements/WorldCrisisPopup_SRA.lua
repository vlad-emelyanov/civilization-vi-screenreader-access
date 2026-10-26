-- Copyright 2017-2018, Firaxis Games

include("InstanceManager");
include("LeaderIcon");
include("CivilizationIcon");
include("WorldCrisisSupport");
include("ScreenReader");		-- ScreenReaderAccess mod change
include("SRListen");		-- ScreenReaderAccess mod change
include("WorldCongressText");	-- ScreenReaderAccess mod change

-- ===========================================================================
--	CONSTANTS
-- ===========================================================================
local RELOAD_CACHE_ID:string = "WorldCrisisPopup";

local TIER_REWARD_STRINGS:table = {};
TIER_REWARD_STRINGS[1] = "LOC_SCORED_COMPETITION_YOU_EARNED_GOLD";
TIER_REWARD_STRINGS[2] = "LOC_SCORED_COMPETITION_YOU_EARNED_SILVER";
TIER_REWARD_STRINGS[3] = "LOC_SCORED_COMPETITION_YOU_EARNED_BRONZE";

local TIER_RIM_NAMES:table = {};
TIER_RIM_NAMES[1] = {rim="Controls_CircleRim40_Gold", arrow="Controls_YouArrowSmall_Gold"};
TIER_RIM_NAMES[2] = {rim="Controls_CircleRim40_Silver", arrow="Controls_YouArrowSmall_Silver"};
TIER_RIM_NAMES[3] = {rim="Controls_CircleRim40_Bronze", arrow="Controls_YouArrowSmall_Bronze"};
TIER_RIM_NAMES[4] = {rim="Controls_CircleRim40_None", arrow="Controls_YouArrowSmall_None"};

local BG_PREFIX:string = "XP2_BG_";

-- ===========================================================================
--	MEMBERS
-- ===========================================================================
local m_targetPlayerID	:number = -1;
local m_emergencyType	:number = -1;
local m_isAnswerRequired:boolean = false;
local m_LeaderIM		:table = InstanceManager:new("LeaderButton", "Root", Controls.LeaderIconStack);

-- Begin ScreenReaderAccess mod change
local m_srOpening		:string = "";		-- spoken when the popup is shown
local m_srLines			:table = {};		-- detail lines for Up/Down (scoring, members and scores, rewards)
local m_srIndex			:number = 0;
local m_srChoice		:number = 1;		-- answer required: 1 = Join, 2 = Reject
local m_srHold			:boolean = false;
local m_srUnread		:boolean = false;	-- the opening may not have been heard: nothing was read or answered since it was spoken
local m_srRespeak		:number = -1;		-- seconds until the opening is spoken again
local m_srClosedAt		:number = -100;		-- when the World Congress last said it closed (that line interrupts the opening)
-- End ScreenReaderAccess mod change


-- ===========================================================================
--	FUNCTIONS
-- ===========================================================================


-- ===========================================================================
--	Game Event
-- ===========================================================================
function OnEmergencyAvailable( targetPlayerID:number, emergencyType:number, startingTurn:number )

	local localPlayerID	:number = Game.GetLocalPlayer();
	if localPlayerID == -1 then return; end -- Autoplay		

	m_targetPlayerID = targetPlayerID;
	m_emergencyType = emergencyType;

	local kData				:table = nil;	
	local bPlayerisTarget	:boolean = localPlayerID == m_targetPlayerID;
	local kEmergencyInfo	:table = Game.GetEmergencyManager():GetEmergencyInfoTable(localPlayerID);
	
	if kEmergencyInfo == nil then
		UI.DataError("No emeregency data for local player "..tostring(localPlayerID).." but EmergencyAvailable was raised.  Assign @tyler.berry");
		return;
	end	

	if kEmergencyInfo and table.count(kEmergencyInfo) > 0 then
		for _, kEmergency in ipairs(kEmergencyInfo) do
			if kEmergency.EmergencyType == emergencyType and kEmergency.TargetID == m_targetPlayerID then
				kData = ProcessEmergency_WorldCrisisPopup(kEmergency, localPlayerID);
				break;
			end
		end
	end
	
	if kData then
		ShowEmergency( kData );
	else
		UI.DataError("Failed to find emergency data for target "..tostring(targetPlayerID)..", emergency " .. tostring(emergencyType) .. ".  Assign @tyler.berry");
	end
end

-- ===========================================================================
--	LUA Event
-- ===========================================================================
function OnShowEmergency( kData: table )
	if kData == nil then
		UI.DataError("No data was passed to OnShowEmergency()");
		return;
	end
	ShowEmergency( kData );
end

-- ===========================================================================
function ShowEmergency( kData: table )

	local localPlayerID:number = Game.GetLocalPlayer();
	local emergencyType:number = kData.emergencyType;

	--Clear the stacks
	ResetEmergencyInstances();

	--Do we need input?
	Controls.JoinButton:SetHide(not kData.inputRequired);
	Controls.RejectButton:SetHide(not kData.inputRequired);
	Controls.OKButton:SetHide(kData.inputRequired);
	m_isAnswerRequired = kData.inputRequired;

	--Only show target if we are hostile
	Controls.TargetIcon:SetShow(GameInfo.Emergencies_XP2[emergencyType].Hostile);

	--Title and subtitles
	Controls.TitleString:SetText(Locale.Lookup(kData.titleString));
	Controls.TrinketString:SetText(kData.trinketString);
	Controls.CrisisTargetTitle2:SetText(kData.targetCityName);
	Controls.CrisisTargetTitle2:SetHide(kData.targetCityName == "");
	Controls.CrisisTrinketTitle:SetText(kData.crisisTrinketTitle);
	Controls.CrisisTrinketTitle:SetHide(kData.crisisTrinketTitle == "");

	--Populate our initial data block
	PopulateWorldCrisisText(g_kCrisisManagers, kData.crisisDetails, Controls.CrisisDetailsStack, true);

	--Turns remaining
	local bgColor:string = "Emergency_Default";
	if (kData.timeRemaining > 0) then
		if (kData.timeRemaining == 1) then
			Controls.CrisisDuration:SetText(Locale.Lookup("LOC_EMERGENCY_NO_TURNS_REMAINING"));
		else
			Controls.CrisisDuration:SetText(Locale.Lookup("LOC_EMERGENCY_TURNS_REMAINING", kData.timeRemaining));
		end
		bgColor = "Emergency_In_Progress";
		Controls.VictorStack:SetHide(true);
		Controls.CrisisDetailsStack:SetHide(false);
	else
		Controls.VictorStack:SetHide(false);
		Controls.CrisisDetailsStack:SetHide(true);
		Controls.CrisisDuration:SetText(Locale.Lookup("LOC_EMERGENCY_TURNS_OVER"));
		if GameInfo.Emergencies_XP2[emergencyType].Hostile then
			local isTarget :boolean =  localPlayerID == m_targetPlayerID;
			if (not kData.crisisSuccess and isTarget) then
				Controls.VictorTitle:SetText(Locale.Lookup("LOC_SCORED_COMPETITION_YOU_WIN"));
				Controls.VictorTier:SetText(Locale.Lookup("LOC_SCORED_COMPETITION_YOU_EARNED_TARGET"));
				bgColor = "Emergency_Gold";
			elseif not kData.crisisSuccess then
				Controls.VictorTitle:SetText(Locale.Lookup("LOC_SCORED_COMPETITION_TARGET_WINS"));
				Controls.VictorTier:SetText(Locale.Lookup("LOC_SCORED_COMPETITION_YOU_EARNED_NONE"));
				bgColor = "Emergency_Failed";
			else
				Controls.VictorTitle:SetText(Locale.Lookup("LOC_SCORED_COMPETITION_MEMBERS_WIN"));
				Controls.VictorTier:SetText(Locale.Lookup(isTarget and "LOC_SCORED_COMPETITION_YOU_EARNED_NONE" or "LOC_SCORED_COMPETITION_YOU_EARNED_MEMBER"));
				bgColor = isTarget and "Emergency_Gold" or "Emergency_Failed";
			end
		else
			for playerTierID:number,tierValue:number in pairs(kData.memberTiers) do
				local bIsLocalPlayer:boolean = playerTierID == localPlayerID;
				--Find first place
				if tierValue == 1 then
					if bIsLocalPlayer then
						Controls.VictorTitle:SetText(Locale.Lookup("LOC_SCORED_COMPETITION_YOU_WIN"));
					else
						local winnerName:string = GetVisiblePlayerName(playerTierID);
						Controls.VictorTitle:SetText(Locale.Lookup("LOC_SCORED_COMPETITION_LEADER_WINS", winnerName));
					end
				end
			
				if bIsLocalPlayer then
					Controls.VictorTier:SetText(Locale.Lookup(tierValue > 0 and TIER_REWARD_STRINGS[tierValue] or "LOC_SCORED_COMPETITION_YOU_EARNED_NONE"));
					if tierValue == 1 then
						bgColor = "Emergency_Gold";
					elseif tierValue == 2 then
						bgColor = "Emergency_Silver";
					elseif tierValue == 3 then
						bgColor = "Emergency_Bronze"
					end
				end
			end
		end
	end

	if GameInfo.Emergencies_XP2[emergencyType].Hostile then
		--Give "first place" to all members who earned points in non-ranked emergency
		for playerTierID:number,tierValue:number in pairs(kData.memberTiers) do
			if(tierValue > 1) then 
				kData.memberTiers[playerTierID] = 1;
			end
		end
	end

	--Background
	Controls.CrisisBG:SetTexture(BG_PREFIX .. GameInfo.EmergencyAlliances[emergencyType].EmergencyType);
	Controls.CrisisBG:SetColorByName(bgColor);

	--Place in the competition
	Controls.PlayerPlaceLabel:SetHide(kData.targetPlayer == localPlayerID);
	Controls.PlayerPlaceLabel:SetText(kData.placeString);

	--Target assignment
	if kData.targetPlayer >= 0 then
		local localDiplomacy:table =  Players[kData.targetPlayer]:GetDiplomacy();
		local leaderName:string = PlayerConfigurations[kData.targetPlayer]:GetLeaderTypeName();
		local iconName:string = "ICON_" .. leaderName;

		--Build and update
		local ownerLeader = LeaderIcon:AttachInstance(Controls.LeaderTargetIcon);
		ownerLeader:UpdateIcon(iconName, kData.targetPlayer, true);
		Controls.LeaderTargetIcon.Relationship:SetHide(true);
		Controls.CrisisTargetTitle:SetText(Locale.ToUpper(kData.crisisTargetTitle));
		Controls.NoTargetIcon:SetHide(true);
		Controls.CivilizationIconContainer:SetHide(false);
	else
		Controls.CrisisTargetTitle:LocalizeAndSetText(Locale.ToUpper(kData.nameText));	
		Controls.CivilizationIconContainer:SetHide(true);
		Controls.NoTargetIcon:SetIcon("ICON_" .. GameInfo.EmergencyAlliances[emergencyType].EmergencyType);
		Controls.NoTargetIcon:SetHide(false);
	end

	--Assign our Member list
	if GameInfo.Emergencies_XP2[emergencyType].Hostile then
		Controls.MemberLabel:SetText(Locale.ToUpper(Locale.Lookup("LOC_EMERGENCY_PARTICIPANTS")));
	else
		Controls.MemberLabel:SetText(Locale.ToUpper(Locale.Lookup("LOC_EMERGENCY_COMPETING_PARTICIPANTS")));
	end

	--Populate our bottom block of data
	PopulateWorldCrisisText(g_kRewardsManagers, kData.rewardsDetails, Controls.RewardsDetailsStack, true);
	PopulateLeaderBar(kData.participantPlayers, kData.participantScores, kData.memberTiers);

	SRA_BuildText( kData );		-- ScreenReaderAccess mod change
	LuaEvents.SRA_SpeechHold( "WorldCrisisPopup", true, "/InGame/AdditionalUserInterfaces/" .. ContextPtr:GetID() );		-- ScreenReaderAccess mod change: the hub's announcements wait
	m_srHold = true;
	UIManager:QueuePopup(ContextPtr, PopupPriority.Low, { DelayShow = true });
end

-- ===========================================================================
--	ScreenReaderAccess: "Scored competition ongoing. Target: Dido. <goal>. 12 turns remaining. You are in 2nd place. <how to score>
--	<members and scores>. <rewards>. Enter to close"
-- ===========================================================================
function SRA_Clean( text:string )
	if text == nil then return ""; end
	return CleanTextForSpeech( tostring(text) );
end

function SRA_AddLines( lines:table, details:table, over:boolean )
	for _, line in ipairs(details or {}) do
		local text:string = SRA_Clean(line.string);
		-- a finished competition: the game still shows "When time runs out, Members will be rewarded ...": say it in the past
		if over and ( line.string == Locale.Lookup("LOC_EMERGENCY_REWARD_NON_HOSTILE_DESCRIPTION") or line.string == Locale.Lookup("LOC_EMERGENCY_MEMBER_REWARDS_HOSTILE_EXPLANATION") ) then text = "Rewards"; end
		if text ~= "" then table.insert(lines, text); end
	end
end

function SRA_BuildText( kData:table )
	local head:table = {};
	local function add( text:string )
		text = SRA_Clean(text);
		if text ~= "" then table.insert(head, text); end
	end
	add(Locale.Lookup(kData.titleString));		-- may be a raw LOC key (CompletedText of an ended crisis)
	if GameInfo.Emergencies_XP2[kData.emergencyType].Hostile or kData.targetPlayer >= 0 then add(kData.crisisTargetTitle); end
	add(kData.targetCityName);
	add(kData.crisisTrinketTitle);
	add(kData.trinketString);
	if kData.timeRemaining > 0 then
		add(kData.timeRemaining == 1 and Locale.Lookup("LOC_EMERGENCY_NO_TURNS_REMAINING") or Locale.Lookup("LOC_EMERGENCY_TURNS_REMAINING", kData.timeRemaining));
	else
		add(Locale.Lookup("LOC_EMERGENCY_TURNS_OVER"));
		add(Controls.VictorTitle:GetText());
		add(Controls.VictorTier:GetText());
	end
	if kData.placeString ~= nil and kData.targetPlayer ~= Game.GetLocalPlayer() then add(kData.placeString); end

	local lines:table = {};
	SRA_AddLines(lines, kData.crisisDetails);
	local members:table = {};
	local unmetScores:table = {};		-- members we have not met: the game shows each as "Unmet Player"
	local localID:number = Game.GetLocalPlayer();
	local localDiplomacy:table = Players[localID]:GetDiplomacy();
	for _, playerID in ipairs(kData.participantPlayers or {}) do
		if playerID ~= -1 then
			local score = kData.participantScores ~= nil and kData.participantScores[playerID] or nil;
			if playerID ~= localID and not localDiplomacy:HasMet(playerID) then
				table.insert(unmetScores, score ~= nil and tostring(score) or "");
			else
				local name:string = (playerID == localID) and "You" or SRA_Clean(GetVisiblePlayerName(playerID));
				table.insert(members, name .. (score ~= nil and (" " .. tostring(score)) or ""));
			end
		end
	end
	for _, group in ipairs(WCText_UnmetGroups(unmetScores)) do table.insert(members, group); end
	if #members > 0 then
		table.insert(lines, (string.gsub(SRA_Clean(Controls.MemberLabel:GetText()), "%s*:%s*$", "")) .. ": " .. table.concat(members, "; "));
	end
	SRA_AddLines(lines, kData.rewardsDetails, kData.timeRemaining <= 0);

	m_srLines = lines;
	m_srIndex = 0;
	m_srChoice = 1;
	local text:string = table.concat(head, ". ") .. ".";
	if #lines > 0 then text = text .. " " .. table.concat(lines, ". ") .. "."; end
	if kData.inputRequired then
		text = text .. " Join: Enter. Down for Reject.";
	else
		text = text .. " Enter to close.";
	end
	m_srOpening = text;
end

function SRA_ReadLine( step:number )
	if #m_srLines == 0 then return; end
	m_srIndex = m_srIndex + step;
	if m_srIndex < 1 then m_srIndex = #m_srLines; end
	if m_srIndex > #m_srLines then m_srIndex = 1; end
	OutputMessageToScreenReader(m_srLines[m_srIndex] .. ", " .. m_srIndex .. " of " .. #m_srLines);
end

function SRA_ReleaseHold()
	m_srRespeak = -1;		-- the popup closes: no pending re-speak
	if m_srHold then
		m_srHold = false;
		LuaEvents.SRA_SpeechHold( "WorldCrisisPopup", false );
	end
end

-- ===========================================================================
function SRA_Respeak()
	if ContextPtr:IsHidden() or not m_srUnread or m_srOpening == "" then return; end
	OutputMessageToScreenReader(m_srOpening, true);		-- nointerrupt: must not cut the player's own key speech
end

function SRA_OnUpdate( deltaTime:number )
	if m_srRespeak < 0 then return; end
	m_srRespeak = m_srRespeak - deltaTime;
	if m_srRespeak < 0 then
		m_srRespeak = -1;
		SRA_Respeak();
	end
end

-- The congress closes with a line that interrupts speech: a crisis popup shown at the same time says its opening again.
function SRA_OnCongressClosed()
	m_srClosedAt = UI.GetElapsedTime();
	if not ContextPtr:IsHidden() and m_srUnread then m_srRespeak = 0.6; end
end

function OnShow()
	m_srRespeak = -1;
	Controls.AnimSoundOnShow:SetToBeginning();	
	Controls.SlideOnShow:SetToBeginning();
	Controls.AnimSoundOnShow:Play();	
	Controls.SlideOnShow:Play();	
	UI.PlaySound("ScoredCompetition_open");
	if m_srOpening ~= "" then OutputMessageToScreenReader(m_srOpening); end		-- ScreenReaderAccess mod change
	m_srUnread = true;
	-- (no re-speak for a popup shown right after the congress: the opening interrupts, nothing cuts it off but a later closing line, see SRA_OnCongressClosed; a second reading doubled the text)
end

-- ===========================================================================
function PopulateLeaderBar( kParticipantPlayers:table, kParticipantScores:table, kMemberTiers:table)
	m_LeaderIM:ResetInstances();
	
	--Add our leaders
	local isUniqueLeader:table = {};
	local localPlayerID:number = Game.GetLocalPlayer();
	local localDiplomacy:table =  Players[localPlayerID]:GetDiplomacy();

	for _, playerID in ipairs(kParticipantPlayers) do
		if playerID ~= -1 then
			local leaderName:string = PlayerConfigurations[playerID]:GetLeaderTypeName();
			local iconName:string = "ICON_" .. leaderName;
			local playerMet:boolean = localDiplomacy:HasMet(playerID);
			if (playerMet) then
				if (isUniqueLeader[leaderName] == nil) then
					isUniqueLeader[leaderName] = true;
				else
					isUniqueLeader[leaderName] = false;
				end	
			elseif playerID ~= localPlayerID then
				iconName = "ICON_LEADER_DEFAULT";
			end

			--Build and update
			local uiLeaderInstance:table = m_LeaderIM:GetInstance();
			local kLeaderIconManager, uiLeaderIcon = LeaderIcon:AttachInstance(uiLeaderInstance.Icon);
			kLeaderIconManager:UpdateIcon(iconName, playerID, isUniqueLeader[leaderName]);
			uiLeaderInstance.ScoreLabel:SetText(kParticipantScores[playerID]);
			uiLeaderInstance.YouIndicator:SetHide(playerID ~= localPlayerID);
			uiLeaderInstance.Icon.YouIndicator:SetHide(false);
			
			local tierIndex:number = kMemberTiers[playerID];
			if tierIndex > 0 then
				uiLeaderInstance.Icon.YouIndicator:SetTexture(TIER_RIM_NAMES[tierIndex].rim);
				uiLeaderInstance.YouIndicator:SetTexture(TIER_RIM_NAMES[tierIndex].arrow);
			else
				uiLeaderInstance.Icon.YouIndicator:SetTexture(TIER_RIM_NAMES[4].rim);
				uiLeaderInstance.YouIndicator:SetTexture(TIER_RIM_NAMES[4].arrow);
			end
		end
	end
end

-- ===========================================================================
--	UI Callback
-- ===========================================================================
function OnDoneCloseAnim()
	if Controls.SlideOnShow:IsReversing() then
		UIManager:DequeuePopup(ContextPtr);
	end
end

-- ===========================================================================
function Close()
	SRA_ReleaseHold();		-- ScreenReaderAccess mod change
	if (not m_isAnswerRequired) then
		local kParameters:table = {};
		kParameters[PlayerOperations.PARAM_OTHER_PLAYER] = m_targetPlayerID;
		kParameters[PlayerOperations.PARAM_EMERGENCY_TYPE] = m_emergencyType;
		UI.RequestPlayerOperation(Game.GetLocalPlayer(), PlayerOperations.ACCEPT_EMERGENCY, kParameters);
	end
	local offsetx = Controls.SlideOnShow:GetOffsetX();
	if(offsetx ~= 0) then
		Controls.SlideOnShow:SetToEnd();
	end
	Controls.SlideOnShow:Reverse();	
	UI.PlaySound("ScoredCompetition_close");
end

-- ===========================================================================
--	UI Callback
-- ===========================================================================
function OnClose()
	Close();
end

-- ===========================================================================
--	UI Callback
-- ===========================================================================
function OnJoinClicked()
	-- Send a command saying that we've seen this emergency
	local kParameters:table = {};
	kParameters[PlayerOperations.PARAM_OTHER_PLAYER] = m_targetPlayerID;
	kParameters[PlayerOperations.PARAM_EMERGENCY_TYPE] = m_emergencyType;
	UI.RequestPlayerOperation(Game.GetLocalPlayer(), PlayerOperations.ACCEPT_EMERGENCY, kParameters);
	OutputMessageToScreenReader( "Joined the emergency", true );		-- ScreenReaderAccess

	Close();
end

-- ===========================================================================
--	UI Callback
-- ===========================================================================
function OnRejectClicked()
	-- Send a command saying we reject it
	local kParameters:table = {};
	kParameters[PlayerOperations.PARAM_OTHER_PLAYER] = m_targetPlayerID;
	kParameters[PlayerOperations.PARAM_EMERGENCY_TYPE] = m_emergencyType;
	UI.RequestPlayerOperation(Game.GetLocalPlayer(), PlayerOperations.REJECT_EMERGENCY, kParameters);
	OutputMessageToScreenReader( "Rejected the emergency", true );		-- ScreenReaderAccess

	Close();
end

-- ===========================================================================
--	UI Input Event Handler
-- ===========================================================================
function OnInputHandler( pInputStruct:table )

	if ContextPtr:IsHidden() then return; end

	local key = pInputStruct:GetKey();
	local msg = pInputStruct:GetMessageType();
	if msg == KeyEvents.KeyUp and key == Keys.VK_ESCAPE then 
		if m_isAnswerRequired then		-- ScreenReaderAccess mod change: Escape must not decide the answer
			OutputMessageToScreenReader("Not answered yet, Up and Down choose Join or Reject, Enter confirms");
		elseif not Controls.SlideOnShow:IsReversing() then Close(); end
	-- Begin ScreenReaderAccess mod change: Enter closes (or answers), Up/Down read the details or choose Join / Reject
	elseif msg == KeyEvents.KeyUp and not Controls.SlideOnShow:IsReversing() then
		m_srUnread = false;
		if key == Keys.VK_RETURN then
			if m_isAnswerRequired then
				if m_srChoice == 1 then OnJoinClicked(); else OnRejectClicked(); end
			else
				Close();
			end
		elseif key == Keys.VK_UP or key == Keys.VK_DOWN then
			if m_isAnswerRequired then
				m_srChoice = 3 - m_srChoice;
				OutputMessageToScreenReader(m_srChoice == 1 and "Join" or "Reject");
			else
				SRA_ReadLine(key == Keys.VK_UP and -1 or 1);
			end
		end
	end
	-- End ScreenReaderAccess mod change

	return true; -- consume all input
end

-- ===========================================================================
--	UI EVENT
-- ===========================================================================
function OnShutdown()
	SRUnlistenAll();
	LuaEvents.GameDebug_AddValue(RELOAD_CACHE_ID, "isVisible", not ContextPtr:IsHidden());
	LuaEvents.GameDebug_AddValue(RELOAD_CACHE_ID, "m_targetPlayerID", m_targetPlayerID);
	LuaEvents.GameDebug_AddValue(RELOAD_CACHE_ID, "m_emergencyType", m_emergencyType);
end

-- ===========================================================================
--	LUA EVENT
--	Reload support
-- ===========================================================================
function OnGameDebugReturn(context:string, contextTable:table)
	if context ~= RELOAD_CACHE_ID then
		return;
	end
		
	if contextTable["isVisible"] then
		local targetPlayer	:number = contextTable["m_targetPlayerID"];
		local emergencyType :number = contextTable["m_emergencyType"]
		OnEmergencyAvailable(targetPlayer, emergencyType);
	end
end

-- ===========================================================================
--	UI EVENT
-- ===========================================================================
function OnInit(isReload:boolean)
	if isReload then
		LuaEvents.GameDebug_GetValues(RELOAD_CACHE_ID);
	end
end

-- ===========================================================================
function Initialize()

	ContextPtr:SetInitHandler(OnInit);
	ContextPtr:SetInputHandler( OnInputHandler, true );
	ContextPtr:SetShowHandler(OnShow);
	ContextPtr:SetShutdown(OnShutdown);
	ContextPtr:SetUpdate(SRA_OnUpdate);		-- ScreenReaderAccess mod change
	SRListen( LuaEvents.SRA_CongressClosedSpoken, SRA_OnCongressClosed );

	Controls.JoinButton:RegisterCallback( Mouse.eLClick, OnJoinClicked );
	Controls.RejectButton:RegisterCallback( Mouse.eLClick, OnRejectClicked );
	Controls.OKButton:RegisterCallback( Mouse.eLClick, OnClose );
	Controls.CloseButton:RegisterCallback( Mouse.eLClick, OnClose );
	Controls.SlideOnShow:RegisterEndCallback( OnDoneCloseAnim );

	Events.EmergencyAvailable.Add(OnEmergencyAvailable);
	
	LuaEvents.GameDebug_Return.Add(OnGameDebugReturn);	
	LuaEvents.WorldCongress_ShowEmergency.Add( OnEmergencyAvailable );
	LuaEvents.WorldCrisisTracker_EmergencyClicked.Add( OnEmergencyAvailable );
	LuaEvents.NotificationPanel_EmergencyClicked.Add( OnEmergencyAvailable );
	LuaEvents.DiploScene_SceneOpened.Add(OnClose);
end
Initialize();