-- ===========================================================================
--	INCLUDES
-- ===========================================================================

include("AnimSidePanelSupport");
include("InstanceManager");
include("SupportFunctions");
include("CivilizationIcon");
include("TeamSupport");
include("EraSupport");
include("GameCapabilities");
include("ScreenReader");		-- ScreenReaderAccess mod change
include("KeyNavList");			-- ScreenReaderAccess mod change
include("SRListen");			-- ScreenReaderAccess mod change

-- ===========================================================================
--	CONSTANTS
-- ===========================================================================
local m_ToggleVisibilityAction;
local RELOAD_CACHE_ID:string = "EraProgressPanel"; -- Must be unique (usually the same as the file name)

local ERA_TYPE_DARK_AGE:number		= 1;
local ERA_TYPE_NORMAL_AGE:number	= 2;
local ERA_TYPE_GOLDEN_AGE:number	= 3;
local ERA_TYPE_HEROIC_AGE:number	= 4;

local TEAM_RIBBON_PREFIX:string = "ICON_TEAM_RIBBON_";
local TEAM_RIBBON_SIZE:number = 53;

-- ===========================================================================
--	VARIABLES
-- ===========================================================================

local m_AnimSupport:table; -- AnimSidePanelSupport

local m_EraData:table = {
	PlayerID = -1;
	NextEraMinTurn = 0;
	NextEraMaxTurn = 0;
	CurrentEraName = "";
	CurrentEraIcon = "";
	CurrentEraType = -1;
	NextEraType = -1;
	CurrentEraScore = 0;
	EraRibbonTexture = "";
	EraRibbonText = "";
	AgeName = "";
	ShortAgeName = "";
	AgeEffects = "";
	ScoreBreakdown = {};
	NextEraThreshold = 0;
	DarkAgeThreshold = 0;
	DarkAgeThresholdTooltip = "";
	GoldenAgeThreshold = 0;
	GoldenAgeThresholdTooltip = "";
	NextGoldenAgeName = "";
	FinalEraReached = false;
};

-- ScreenReaderAccess mod change: keyboard list over the panel's data, spoken summary on open
local m_srList:table = nil;
local m_srOpen:boolean = false;
local m_srActionId = nil;			-- KeyNavEraProgress (Control+E): the game's own toggle is the numpad Divide

local m_CivilizationIconIM:table = InstanceManager:new("CivilizationIconAge", "CivIconBacking", Controls.CivIconStack);

-- ===========================================================================
function GetData()
	local pGameEras:table = Game.GetEras();
	local currentEraIndex:number = pGameEras:GetCurrentEra();
	local currentEraDef:table = GameInfo.Eras[currentEraIndex];
	local currentTurn:number = Game.GetCurrentGameTurn();

	m_EraData.PlayerID = Game.GetLocalPlayer();

	m_EraData.CurrentEraName = currentEraDef.Name;
	m_EraData.CurrentEraScore = pGameEras:GetPlayerCurrentScore(m_EraData.PlayerID);

	-- Combine previous era scores
	m_EraData.ScoreBreakdown = {};
	local previousScoreBreakdown = pGameEras:GetPlayerPreviousEraScoreBreakdown(m_EraData.PlayerID);
	local previousScoreTotal = 0;
	for i,source in ipairs(previousScoreBreakdown) do
		for sourceString, sourceValue in pairs(source) do
			previousScoreTotal = previousScoreTotal + sourceValue;
		end
	end

	-- Display previous era scores as a single entry
	if previousScoreTotal > 0 then
		local previousScore:table = {};
		previousScore[Locale.Lookup("LOC_ERAS_PREVIOUS_ERA_TOTAL_SCORE")] = previousScoreTotal;
		table.insert(m_EraData.ScoreBreakdown, previousScore);
	end

	-- Add current era breakdown as individual entries
	local currentScoreBreakdown = pGameEras:GetPlayerCurrentEraScoreBreakdown(m_EraData.PlayerID);
	for i,source in ipairs(currentScoreBreakdown) do
		for sourceString, sourceValue in pairs(source) do
			if sourceValue > 0 then
				local currentSource:table = {};
				currentSource[sourceString] = sourceValue;
				table.insert(m_EraData.ScoreBreakdown, currentSource);
			end
		end
	end

	local nextEraCountdown = pGameEras:GetNextEraCountdown() + 1; -- 0 turns remaining is the last turn, shift by 1 to make sense to non-programmers
	if nextEraCountdown > 0 then
		-- If the era countdown has started only show that number
		m_EraData.NextEraMinTurn = nextEraCountdown;
		m_EraData.NextEraMaxTurn = nextEraCountdown;
	else
		local inactiveCountdownLength = GlobalParameters.NEXT_ERA_TURN_COUNTDOWN; -- Even though the countdown has not started yet, account for it in our time estimates
		m_EraData.NextEraMinTurn = pGameEras:GetCurrentEraMinimumEndTurn() - currentTurn;
		if (m_EraData.NextEraMinTurn < inactiveCountdownLength) then
			m_EraData.NextEraMinTurn = inactiveCountdownLength;
		end
		m_EraData.NextEraMaxTurn = pGameEras:GetCurrentEraMaximumEndTurn() - currentTurn;
		if (m_EraData.NextEraMaxTurn < 0) then
			m_EraData.NextEraMaxTurn = 0;
		end
	end

	m_EraData.DarkAgeThreshold = pGameEras:GetPlayerDarkAgeThreshold(m_EraData.PlayerID);
	m_EraData.DarkAgeThresholdTooltip = GetDarkAgeThresholdTooltip(m_EraData.PlayerID);
	m_EraData.GoldenAgeThreshold = pGameEras:GetPlayerGoldenAgeThreshold(m_EraData.PlayerID);
	m_EraData.GoldenAgeThresholdTooltip = GetGoldenAgeThresholdTooltip(m_EraData.PlayerID);

	if (pGameEras:GetCurrentEra() == pGameEras:GetFinalEra()) then
		m_EraData.FinalEraReached = true;
	end

	-- Determine which era we'll currently have next
	if m_EraData.CurrentEraScore >= m_EraData.GoldenAgeThreshold then
		m_EraData.NextEraType = ERA_TYPE_GOLDEN_AGE;
	elseif m_EraData.CurrentEraScore >= m_EraData.DarkAgeThreshold then
		m_EraData.NextEraType = ERA_TYPE_NORMAL_AGE;
	else
		m_EraData.NextEraType = ERA_TYPE_DARK_AGE;
	end

	local loyalty : number = 0;
	if (m_EraData.PlayerID ~= PlayerTypes.NONE) then
		local localPlayer	: table = Players[m_EraData.PlayerID];
		loyalty = localPlayer:GetCivilianLoyalty();
	end

	if pGameEras:HasHeroicGoldenAge(m_EraData.PlayerID) then
		-- Heroic
		m_EraData.CurrentEraType = ERA_TYPE_HEROIC_AGE;
		m_EraData.CurrentEraIcon = "[ICON_GLORY_SUPER_GOLDEN_AGE]";
		m_EraData.NextEraThreshold = m_EraData.GoldenAgeThreshold
		m_EraData.EraRibbonTexture = "Controls_AgesBanner_Heroic";
		m_EraData.EraRibbonText = Locale.Lookup("LOC_ERA_REVIEW_HAVE_HEROIC_AGE_PARAM", {Name = "Amount", Value=loyalty});
		m_EraData.AgeName = Locale.Lookup("LOC_ERA_PROGRESS_HEROIC_AGE");
		m_EraData.ShortAgeName = Locale.Lookup("LOC_ERAS_HEROIC");
		m_EraData.AgeEffects = Locale.Lookup("LOC_ERA_TT_HAVE_HEROIC_AGE_EFFECT_PARAM", {Name = "Amount", Value=loyalty});
		m_EraData.NextGoldenAgeName = Locale.Lookup("LOC_ERA_REVIEW_HAVE_GOLDEN_AGE_LABEL");
	elseif pGameEras:HasGoldenAge(m_EraData.PlayerID) then
		-- Golden
		m_EraData.CurrentEraType = ERA_TYPE_GOLDEN_AGE;
		m_EraData.CurrentEraIcon = "[ICON_GLORY_GOLDEN_AGE]";
		m_EraData.NextEraThreshold = m_EraData.GoldenAgeThreshold
		m_EraData.EraRibbonTexture = "Controls_AgesBanner_Golden";
		m_EraData.EraRibbonText = Locale.Lookup("LOC_ERA_REVIEW_HAVE_GOLDEN_AGE_PARAM", {Name = "Amount", Value=loyalty});
		m_EraData.AgeName = Locale.Lookup("LOC_ERA_PROGRESS_GOLDEN_AGE");
		m_EraData.ShortAgeName = Locale.Lookup("LOC_ERAS_GOLDEN");
		m_EraData.AgeEffects = Locale.Lookup("LOC_ERA_TT_HAVE_GOLDEN_AGE_EFFECT_PARAM", {Name = "Amount", Value=loyalty});
		m_EraData.NextGoldenAgeName = Locale.Lookup("LOC_ERA_REVIEW_HAVE_GOLDEN_AGE_LABEL");
	elseif pGameEras:HasDarkAge(m_EraData.PlayerID) then
		-- Dark
		m_EraData.CurrentEraType = ERA_TYPE_DARK_AGE;
		m_EraData.CurrentEraIcon = "[ICON_GLORY_DARK_AGE]";
		m_EraData.NextEraThreshold = m_EraData.DarkAgeThreshold
		m_EraData.EraRibbonTexture = "Controls_AgesBanner_Dark";
		m_EraData.EraRibbonText = Locale.Lookup("LOC_ERA_REVIEW_HAVE_DARK_AGE_PARAM", {Name = "Amount", Value=loyalty});
		m_EraData.AgeName = Locale.Lookup("LOC_ERA_PROGRESS_DARK_AGE");
		m_EraData.ShortAgeName = Locale.Lookup("LOC_ERAS_DARK");
		m_EraData.AgeEffects = Locale.Lookup("LOC_ERA_TT_HAVE_DARK_AGE_EFFECT_PARAM", {Name = "Amount", Value=loyalty});
		m_EraData.NextGoldenAgeName = Locale.Lookup("LOC_ERA_REVIEW_HAVE_HEROIC_AGE_LABEL");
	else
		-- Normal
		m_EraData.CurrentEraType = ERA_TYPE_NORMAL_AGE;
		m_EraData.CurrentEraIcon = "[ICON_GLORY_NORMAL_AGE]";
		m_EraData.NextEraThreshold = m_EraData.GoldenAgeThreshold
		m_EraData.EraRibbonTexture = "Controls_AgesBanner_Normal";
		m_EraData.EraRibbonText = Locale.Lookup("LOC_ERA_REVIEW_HAVE_NORMAL_AGE_PARAM", {Name = "Amount", Value=loyalty});
		m_EraData.AgeName = Locale.Lookup("LOC_ERA_PROGRESS_NORMAL_AGE");
		m_EraData.ShortAgeName = Locale.Lookup("LOC_ERAS_NORMAL");
		m_EraData.AgeEffects = Locale.Lookup("LOC_ERA_TT_HAVE_NORMAL_AGE_EFFECT_PARAM", {Name = "Amount", Value=loyalty});
		m_EraData.NextGoldenAgeName = Locale.Lookup("LOC_ERA_REVIEW_HAVE_GOLDEN_AGE_LABEL");
	end

	-- Add dedications to the age effects
	local activeCommemorations = pGameEras:GetPlayerActiveCommemorations(m_EraData.PlayerID);
	for i,activeCommemoration in ipairs(activeCommemorations) do
		local commemorationInfo = GameInfo.CommemorationTypes[activeCommemoration];
		m_EraData.AgeEffects = m_EraData.AgeEffects .. "[NEWLINE][NEWLINE][ICON_BULLET]";
		if (commemorationInfo ~= nil) then
			local bonusText = nil;
			if (pGameEras:HasGoldenAge(m_EraData.PlayerID)) then
				bonusText = Locale.Lookup(commemorationInfo.GoldenAgeBonusDescription);
				if (pGameEras:IsPlayerAlwaysAllowedCommemorationQuest(m_EraData.PlayerID)) then
					bonusText = bonusText .. "[NEWLINE][NEWLINE][ICON_BULLET]" .. Locale.Lookup(commemorationInfo.NormalAgeBonusDescription);
				end
			elseif (pGameEras:HasDarkAge(m_EraData.PlayerID)) then
				bonusText = Locale.Lookup(commemorationInfo.DarkAgeBonusDescription);
			else
				bonusText = Locale.Lookup(commemorationInfo.NormalAgeBonusDescription);
			end
			if (bonusText ~= nil) then
				m_EraData.AgeEffects = m_EraData.AgeEffects .. bonusText;
			end
		end
	end
end

-- ===========================================================================
function Refresh()
	GetData();

	Controls.EraName:SetText(Locale.Lookup("LOC_ERA_PROGRESS_THE_ERA", m_EraData.CurrentEraName));
	Controls.EraScoreValue:SetText(m_EraData.CurrentEraScore);
	
	Controls.TimeToNextEraContainer:SetHide(m_EraData.FinalEraReached);
	if m_EraData.NextEraMinTurn == m_EraData.NextEraMaxTurn then
		Controls.TimeToNextEra:SetText(m_EraData.NextEraMaxTurn);
	else
		Controls.TimeToNextEra:SetText(m_EraData.NextEraMinTurn .. " - " .. m_EraData.NextEraMaxTurn);
	end

	local eraRibbonText:string = m_EraData.ShortAgeName .. " " .. m_EraData.CurrentEraIcon;
	Controls.EraRibbonValue:SetText(eraRibbonText);
	Controls.EraRibbon:SetTexture(m_EraData.EraRibbonTexture);

	PopulateLocalPlayerIcon();

	PopulateCivilizationIcons();

	if m_EraData.NextEraType == ERA_TYPE_GOLDEN_AGE then
		Controls.GoldenCheckmark:SetHide(false);
		Controls.GoldenCheckmark:SetToolTipString(Locale.Lookup("LOC_ERAS_YOU_WILL_EARN_BLANK_AGE_NEXT_ERA", Locale.Lookup("LOC_ERA_PROGRESS_GOLDEN_AGE")));
		Controls.NormalCheckmark:SetHide(true);
		Controls.DarkCheckmark:SetHide(true);
	elseif m_EraData.NextEraType == ERA_TYPE_NORMAL_AGE then
		Controls.GoldenCheckmark:SetHide(true);
		Controls.NormalCheckmark:SetHide(false);
		Controls.NormalCheckmark:SetToolTipString(Locale.Lookup("LOC_ERAS_YOU_WILL_EARN_BLANK_AGE_NEXT_ERA", Locale.Lookup("LOC_ERA_PROGRESS_NORMAL_AGE")));
		Controls.DarkCheckmark:SetHide(true);
	else
		Controls.GoldenCheckmark:SetHide(true);
		Controls.NormalCheckmark:SetHide(true);
		Controls.DarkCheckmark:SetHide(false);
		Controls.DarkCheckmark:SetToolTipString(Locale.Lookup("LOC_ERAS_YOU_WILL_EARN_BLANK_AGE_NEXT_ERA", Locale.Lookup("LOC_ERA_PROGRESS_DARK_AGE")));
	end

	if (m_EraData.FinalEraReached) then
		Controls.ThresholdStack:SetHide(true);
	else
		local darkAgeThresholdForDisplay = m_EraData.DarkAgeThreshold - 1;
		if (darkAgeThresholdForDisplay < 0) then
			darkAgeThresholdForDisplay = 0;
		end
		Controls.DarkThreshold:SetText("0 - " .. (darkAgeThresholdForDisplay));
		Controls.DarkThreshold:SetToolTipString(m_EraData.DarkAgeThresholdTooltip);
		Controls.NormalThreshold:SetText(m_EraData.DarkAgeThreshold .. " - " .. (m_EraData.GoldenAgeThreshold - 1));
		Controls.GoldenLabel:SetText(m_EraData.NextGoldenAgeName);
		Controls.GoldenThreshold:SetText(m_EraData.GoldenAgeThreshold .. "+");
		Controls.GoldenThreshold:SetToolTipString(m_EraData.GoldenAgeThresholdTooltip);
		Controls.ThresholdStack:SetHide(false);
	end

	-- hide the normal age text if we're in Dramatic Ages
	Controls.NormalAgeThreshold:SetHide(HasCapability("CAPABILITY_DRAMATICAGES"));

	Controls.EraEffects:SetText(m_EraData.AgeEffects);
end

-- ===========================================================================
function PopulateCivilizationIcons()

	m_CivilizationIconIM:ResetInstances();

	local gameEras:table = Game.GetEras();
	local localPlayer:table = Players[m_EraData.PlayerID];

	local heroicPlayers:table = {};
	local goldenPlayers:table = {};
	local normalPlayers:table = {};
	local darkPlayers:table = {};
	local unmetPlayers:table = {};

	local aPlayers = PlayerManager.GetAliveMajors();
	for _, pPlayer in ipairs(aPlayers) do
		local playerID:number = pPlayer:GetID();
		if(playerID ~= m_EraData.PlayerID) then
			if localPlayer and localPlayer:GetDiplomacy():HasMet(playerID) then
				if gameEras:HasHeroicGoldenAge(playerID) then
					table.insert(heroicPlayers, playerID);
				elseif gameEras:HasGoldenAge(playerID) then
					table.insert(goldenPlayers, playerID);
				elseif gameEras:HasDarkAge(playerID) then
					table.insert(darkPlayers, playerID);
				else
					table.insert(normalPlayers, playerID);
				end
			else
				table.insert(unmetPlayers, playerID);
			end
		end
	end

	for i,playerID in ipairs(heroicPlayers) do
		AddPlayerEraIcon(playerID, "[ICON_GLORY_SUPER_GOLDEN_AGE]");
	end
	for i,playerID in ipairs(goldenPlayers) do
		AddPlayerEraIcon(playerID, "[ICON_GLORY_GOLDEN_AGE]");
	end
	for i,playerID in ipairs(normalPlayers) do
		AddPlayerEraIcon(playerID, "[ICON_GLORY_NORMAL_AGE]");
	end
	for i,playerID in ipairs(darkPlayers) do
		AddPlayerEraIcon(playerID, "[ICON_GLORY_DARK_AGE]");
	end
	for i,playerID in ipairs(unmetPlayers) do
		AddPlayerEraIcon(playerID, "");
	end
end

-- ===========================================================================
function AddPlayerEraIcon(playerID:number, eraIcon:string)
	local oCivIcon:object = CivilizationIcon:GetInstance(m_CivilizationIconIM);
	oCivIcon:UpdateIconFromPlayerID(playerID);
	oCivIcon:SetLeaderTooltip(playerID);
	oCivIcon:UpdateLeaderTooltip(playerID);
	oCivIcon.EraLabel:SetText(eraIcon);

	local iTeamID:number = Players[playerID]:GetTeam();
	if #Teams[iTeamID] > 1 then
		local teamRibbonName:string = TEAM_RIBBON_PREFIX .. tostring(iTeamID);
		oCivIcon.TeamRibbon:SetIcon(teamRibbonName);
		oCivIcon.TeamRibbon:SetHide(false);
		oCivIcon.TeamRibbon:SetColor(GetTeamColor(iTeamID));
	else
		oCivIcon.TeamRibbon:SetHide(true);
	end
end

-- ===========================================================================
function OnTopContainerSizeChanged()
	ResizeBottomScrollPanel();
end

-- ===========================================================================
function ResizeBottomScrollPanel()
	Controls.BottomScrollPanel:SetSizeY(Controls.BodyContainer:GetSizeY() - Controls.TopContainer:GetSizeY());
end

-- ===========================================================================
function PopulateLocalPlayerIcon()
	local pPlayer:table = Players[m_EraData.PlayerID];
	local pPlayerConfig:table = PlayerConfigurations[m_EraData.PlayerID];

	local backColor, frontColor = UI.GetPlayerColors(m_EraData.PlayerID);
	Controls.CivIndicator:SetColor(backColor);
	Controls.CivIcon:SetColor(frontColor);
	Controls.CivIcon:SetIcon("ICON_"..pPlayerConfig:GetCivilizationTypeName());
	Controls.LeaderPortrait:SetIcon("ICON_"..pPlayerConfig:GetLeaderTypeName());

	-- Set the tooltip
	if(pPlayerConfig ~= nil) then
		local leaderTypeName:string = pPlayerConfig:GetLeaderTypeName();
		if(leaderTypeName ~= nil) then
			local leaderDesc:string = pPlayerConfig:GetLeaderName();
			local civDesc:string = pPlayerConfig:GetCivilizationDescription();
			Controls.PlayerLeaderButton:LocalizeAndSetToolTip("LOC_DIPLOMACY_DEAL_PLAYER_PANEL_TITLE", leaderDesc, civDesc);
		end
	end

	-- Team Ribbon
	local teamID:number = pPlayerConfig:GetTeam();
	if #Teams[teamID] > 1 then
		local teamRibbonName:string = TEAM_RIBBON_PREFIX .. tostring(teamID);
		Controls.TeamRibbon:SetIcon(teamRibbonName, TEAM_RIBBON_SIZE);
		Controls.TeamRibbon:SetHide(false);
		Controls.TeamRibbon:SetColor(GetTeamColor(teamID));
	else
		-- Hide team ribbon if team only contains one player
		Controls.TeamRibbon:SetHide(true);
	end
end

-- ===========================================================================
--	ScreenReaderAccess mod change: speech and keyboard list (built at key time from m_EraData, which Refresh() fills)
-- ===========================================================================
local function SRA_Plain( text:string )
	return CleanTextForSpeech( text or "" );
end

local function SRA_AgeLabel()		-- "Golden Age" / "Heroic Age" for the upper threshold
	local label:string = SRA_Plain( m_EraData.NextGoldenAgeName );
	if label == "" then label = "Golden age"; end
	return label;
end

local function SRA_TimeText()
	if m_EraData.FinalEraReached then return "Final era, no further era"; end
	if m_EraData.NextEraMinTurn == m_EraData.NextEraMaxTurn then
		return tostring( m_EraData.NextEraMaxTurn ) .. ( m_EraData.NextEraMaxTurn == 1 and " turn" or " turns" ) .. " until the next era";
	end
	return m_EraData.NextEraMinTurn .. " to " .. m_EraData.NextEraMaxTurn .. " turns until the next era";
end

local function SRA_OutcomeText()
	local key:string = "LOC_ERA_PROGRESS_NORMAL_AGE";
	if m_EraData.NextEraType == ERA_TYPE_GOLDEN_AGE then key = "LOC_ERA_PROGRESS_GOLDEN_AGE";
	elseif m_EraData.NextEraType == ERA_TYPE_DARK_AGE then key = "LOC_ERA_PROGRESS_DARK_AGE"; end
	return SRA_Plain( Locale.Lookup( "LOC_ERAS_YOU_WILL_EARN_BLANK_AGE_NEXT_ERA", Locale.Lookup( key ) ) );
end

local function SRA_OtherCivItems( items:table )
	local gameEras:table = Game.GetEras();
	local localPlayer:table = Players[ m_EraData.PlayerID ];
	if localPlayer == nil then return; end
	local groups:table = { heroic = {}, golden = {}, normal = {}, dark = {} };
	local unmet:number = 0;
	for _, pPlayer in ipairs( PlayerManager.GetAliveMajors() ) do
		local id:number = pPlayer:GetID();
		if id ~= m_EraData.PlayerID then
			if localPlayer:GetDiplomacy():HasMet( id ) then
				local name:string = Locale.Lookup( PlayerConfigurations[ id ]:GetCivilizationShortDescription() );
				if gameEras:HasHeroicGoldenAge( id ) then table.insert( groups.heroic, name );
				elseif gameEras:HasGoldenAge( id ) then table.insert( groups.golden, name );
				elseif gameEras:HasDarkAge( id ) then table.insert( groups.dark, name );
				else table.insert( groups.normal, name ); end
			else
				unmet = unmet + 1;
			end
		end
	end
	for _, entry in ipairs( { { "heroic", "Heroic age" }, { "golden", "Golden age" }, { "normal", "Normal age" }, { "dark", "Dark age" } } ) do
		if #groups[ entry[1] ] > 0 then
			table.insert( items, { key = "civs:" .. entry[1], text = entry[2] .. ": " .. table.concat( groups[ entry[1] ], ", " ), section = "Other civilizations" } );
		end
	end
	if unmet > 0 then
		table.insert( items, { key = "civs:unmet", text = unmet .. ( unmet == 1 and " civilization" or " civilizations" ) .. " not met", section = "Other civilizations" } );
	end
end

local function SRA_Items()
	local items:table = {};
	table.insert( items, { key = "era", text = "Era: " .. SRA_Plain( Locale.Lookup( m_EraData.CurrentEraName ) ) .. ", " .. SRA_Plain( m_EraData.ShortAgeName ) .. " age", detail = SRA_Plain( m_EraData.AgeName ) } );
	table.insert( items, { key = "score", text = "Era score " .. tostring( m_EraData.CurrentEraScore ) .. ". " .. SRA_OutcomeText(), detail = SRA_OutcomeText() } );
	if not m_EraData.FinalEraReached then
		local darkTo:number = math.max( m_EraData.DarkAgeThreshold - 1, 0 );
		local onTrack:number = m_EraData.NextEraType;		-- the age the score gives now
		table.insert( items, { key = "dark", section = "Thresholds", text = "Dark age below " .. m_EraData.DarkAgeThreshold .. " (0 to " .. darkTo .. ")" .. ( onTrack == ERA_TYPE_DARK_AGE and ", on track" or "" ), detail = SRA_Plain( m_EraData.DarkAgeThresholdTooltip ) } );
		if not HasCapability("CAPABILITY_DRAMATICAGES") then
			table.insert( items, { key = "normal", section = "Thresholds", text = "Normal age " .. m_EraData.DarkAgeThreshold .. " to " .. ( m_EraData.GoldenAgeThreshold - 1 ) .. ( onTrack == ERA_TYPE_NORMAL_AGE and ", on track" or "" ) } );
		end
		table.insert( items, { key = "golden", section = "Thresholds", text = SRA_AgeLabel() .. " at " .. m_EraData.GoldenAgeThreshold .. " or more" .. ( onTrack == ERA_TYPE_GOLDEN_AGE and ", on track" or "" ), detail = SRA_Plain( m_EraData.GoldenAgeThresholdTooltip ) } );
	end
	table.insert( items, { key = "time", text = SRA_TimeText() } );
	for i, entry in ipairs( m_EraData.ScoreBreakdown ) do
		for source, value in pairs( entry ) do
			table.insert( items, { key = "breakdown:" .. i, section = "Score breakdown", text = SRA_Plain( source ) .. ": " .. tostring( value ) } );
		end
	end
	local effects:string = SRA_Plain( m_EraData.AgeEffects );
	if effects ~= "" then
		table.insert( items, { key = "effects", section = "Age effects", text = effects } );
	end
	SRA_OtherCivItems( items );
	return items;
end

-- "Era progress. Medieval Era, normal age. Era score 12. You will earn a Normal Age next Era. Dark age below 10, golden age at 20. 25 turns until the next era"
local function SRA_Summary()
	local parts:table = { "Era progress", SRA_Plain( Locale.Lookup( m_EraData.CurrentEraName ) ) .. ", " .. SRA_Plain( m_EraData.ShortAgeName ) .. " age",
		"Era score " .. tostring( m_EraData.CurrentEraScore ), SRA_OutcomeText() };
	if not m_EraData.FinalEraReached then
		table.insert( parts, "Dark age below " .. m_EraData.DarkAgeThreshold .. ", " .. string.lower( SRA_AgeLabel() ) .. " at " .. m_EraData.GoldenAgeThreshold );
	end
	table.insert( parts, SRA_TimeText() );
	return table.concat( parts, ". " );
end

local function SRA_OnOpened()
	m_srOpen = true;
	LuaEvents.SRA_SpeechHold( "EraProgress", true, "/InGame/PartialScreens/" .. ContextPtr:GetID() );
	m_srList.Reset();
	m_srList.Open( "", nil, true );
	OutputMessageToScreenReader( SRA_Summary() );
end

local function SRA_OnClosed()
	if not m_srOpen then return; end
	m_srOpen = false;
	LuaEvents.SRA_SpeechHold( "EraProgress", false );
	OutputMessageToScreenReader( "Era progress closed" );
end

-- Enter and Space both read the item in full (its detail, else its text again)
local function SRA_OnActivate( item:table )
	local text:string = item.detail;
	if text == nil or text == "" then text = item.text; end
	OutputMessageToScreenReader( text );
end

-- Keys first to the list while the panel is open; the game's Escape handler does the rest
local function SRA_OnInput( input:table )
	if m_srOpen and m_srList ~= nil and m_srList.HandleInput( input ) then return true; end
	return m_AnimSupport.OnInputHandler( input );
end

-- The mod hotkey (Control+E): the same as the numpad Divide, which calls Open() / Close() here
local function SRA_OnInputAction( actionId )
	if actionId ~= m_srActionId or m_srActionId == nil then return; end
	if m_srOpen then
		Close();
	else
		LuaEvents.PartialScreenHooks_CloseAllExcept( "EraProgressPanel" );
		Open();
	end
end

-- ===========================================================================
function Open()
	-- Ensure this panel is displayed below PartialScreenHooks
	-- This is done on Open() because LookUpControl can't always find PartialScreens during Initalization
	if ContextPtr:GetParent():GetID() ~= "PartialScreens" then
		local partialScreen:table = ContextPtr:LookUpControl( "/InGame/PartialScreens" );
		ContextPtr:ChangeParent(partialScreen);
		partialScreen:AddChildAtIndex(ContextPtr, 6);
	end

	-- dont show panel if there is no local player
	local localPlayerID = Game.GetLocalPlayer();
	if (localPlayerID == -1) then
		return
	end

	LuaEvents.MinimapPanel_CloseAllLenses();
	m_AnimSupport.Show();
	Refresh();
	UI.PlaySound("CityStates_Panel_Open");
	LuaEvents.EraProgressPanel_Open();
	SRA_OnOpened();		-- ScreenReaderAccess mod change
end

-- ===========================================================================
function Close()	
    if not ContextPtr:IsHidden() then
        UI.PlaySound("CityStates_Panel_Close");
    end
	m_AnimSupport.Hide();
	LuaEvents.EraProgressPanel_Close();
	SRA_OnClosed();		-- ScreenReaderAccess mod change
end

-- ===========================================================================
function OnOpen()
	Open();
end

-- ===========================================================================
function OnClose()
	Close();
end

-- ===========================================================================
--	LUA Event
--	Explicit close (from partial screen hooks), part of closing everything,
-- ===========================================================================
function OnCloseAllExcept( contextToStayOpen:string )
	if contextToStayOpen == "EraProgressPanel" then 
		return; 
	end
	Close();
end

-- ===========================================================================
function OnLocalPlayerTurnEnd()
	if(GameConfiguration.IsHotseat()) then
		Close();
	end
end

-- ===========================================================================
--	Game Event
-- ===========================================================================
function OnInterfaceModeChanged(eOldMode:number, eNewMode:number)
	if eNewMode == InterfaceModeTypes.VIEW_MODAL_LENS then
		Close();
	end
end

-- ===========================================================================
function LateInitialize()
end

-- ===========================================================================
--	UI EVENT
-- ===========================================================================
function OnInit( isReload:boolean )	
	LateInitialize();
	if isReload then
		LuaEvents.GameDebug_GetValues(RELOAD_CACHE_ID);
	end
end

-- ===========================================================================
--	UI EVENT
-- ===========================================================================
function OnShutdown()
	SRUnlistenAll();		-- ScreenReaderAccess mod change
	LuaEvents.GameDebug_AddValue(RELOAD_CACHE_ID, "isHidden", ContextPtr:IsHidden());
end

-- ===========================================================================
--	LUA EVENT
--	Reload support
-- ===========================================================================
function OnGameDebugReturn(context:string, contextTable:table)
	if context == RELOAD_CACHE_ID then
		if contextTable["isHidden"] ~= nil and not contextTable["isHidden"] then			
			Open();
		end
	end
end

-- ===========================================================================
--	Input Hotkey Event
-- ===========================================================================
function OnInputActionTriggered( actionId )
	if (actionId == m_ToggleVisibilityAction) then
		if(ContextPtr:IsHidden()) then
			Open();
		else
			Close()
		end
	end
end

-- ===========================================================================
function OnPolicyChanged( ePlayer )
	if m_AnimSupport.IsVisible() and ePlayer == Game.GetLocalPlayer() then
		Refresh();
	end
end

-- ===========================================================================
function Initialize()

	-- Control Events
	Controls.CloseButton:RegisterCallback(Mouse.eLClick, OnClose);
	Controls.CloseButton:RegisterCallback( Mouse.eMouseEnter, function() UI.PlaySound("Main_Menu_Mouse_Over"); end);
	Controls.TopContainer:RegisterSizeChanged( OnTopContainerSizeChanged );

	-- Lua Events
	LuaEvents.PartialScreenHooks_OpenEraProgressPanel.Add( OnOpen );
	LuaEvents.PartialScreenHooks_CloseEraProgressPanel.Add( OnClose );
	LuaEvents.PartialScreenHooks_CloseAllExcept.Add( OnCloseAllExcept );

	-- Animation Controller
	m_AnimSupport = CreateScreenAnimation(Controls.SlideAnim, Close);

	-- Rundown / Screen Events
	Events.SystemUpdateUI.Add(m_AnimSupport.OnUpdateUI);
	ContextPtr:SetInputHandler(SRA_OnInput, true);		-- ScreenReaderAccess mod change (was m_AnimSupport.OnInputHandler)

	Controls.Title:SetText(Locale.ToUpper("LOC_ERA_PROGRESS_TITLE"));

	-- Game Engine Events	
	Events.GovernmentPolicyChanged.Add( OnPolicyChanged );
	Events.GovernmentPolicyObsoleted.Add( OnPolicyChanged );
	Events.LocalPlayerTurnEnd.Add( OnLocalPlayerTurnEnd );
	Events.InterfaceModeChanged.Add( OnInterfaceModeChanged );

	-- Hot-Reload Events
	ContextPtr:SetInitHandler(OnInit);
	ContextPtr:SetShutdown(OnShutdown);
	LuaEvents.GameDebug_Return.Add(OnGameDebugReturn);

	-- Hot Key Handling
    -- (not for XP1, we're on text lockdown and can't add what this really means)
	m_ToggleVisibilityAction = Input.GetActionId("ToggleEraProgress");
	if m_ToggleVisibilityAction ~= nil then
		Events.InputActionTriggered.Add( OnInputActionTriggered )
	end
end
Initialize();

-- ScreenReaderAccess mod change
m_srList = KeyNavList_Create{
	build = SRA_Items,
	isActive = function() return m_srOpen and not ContextPtr:IsHidden(); end,
	onActivate = SRA_OnActivate,
};
m_srActionId = Input.GetActionId("KeyNavEraProgress");
if m_srActionId ~= nil then
	SRListen( Events.InputActionTriggered, SRA_OnInputAction );
end
print( "EraProgressPanel: ScreenReaderAccess copy loaded" );
