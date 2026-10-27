--[[
-- Created by Samuel Batista on Friday Apr 19 2017
-- Copyright (c) Firaxis Games
--]]

include("ControlsManager");
include("InstanceManager");
include("SupportFunctions");
include("CivilizationIcon");
include("TeamSupport");
include("EraSupport");
include("ScreenReader");		-- ScreenReaderAccess
include("SRListen");		-- ScreenReaderAccess
include("KeyboardNavigation");		-- ScreenReaderAccess

-- ===========================================================================
--	CONSTANTS
-- ===========================================================================
local RELOAD_CACHE_ID:string = "EraReviewPopup"; -- Must be unique (usually the same as the file name)
local DEFAULT_HEADER_HEIGHT:number = 220;
local DEFAULT_CONTENTS_HEIGHT:number = 349;

local ERA_ILLUSTRATIONS:table = {
	"Moment_EraEntry_Classical",
	"Moment_EraEntry_Medieval",
	"Moment_EraEntry_Renaissance",
	"Moment_EraEntry_Industrial",
	"Moment_EraEntry_Modern",
	"Moment_EraEntry_Atomic",
	"Moment_EraEntry_Information",
};

local TEAM_RIBBON_PREFIX:string = "ICON_TEAM_RIBBON_";
local TEAM_RIBBON_SIZE:number = 53;

-- ===========================================================================
--	MEMBERS
-- ===========================================================================
local m_LocalPlayerID:number = -1;
local m_PreviousEraIndex:number = -1;
local m_CurrentEraIndex:number = -1;

local m_CivilizationIconIM:table = InstanceManager:new("CivilizationIconAge", "CivIconBacking", Controls.CivIconStack);

-- ScreenReaderAccess: what the popup shows, as speech
local SRA_ANNOUNCE_DELAY:number = 0.3;
local m_srAnnouncePending:boolean = false;
local m_srAnnounceDelay:number = 0;
local m_srAgeName:string = "";			-- "Dark Age"
local m_srEffects:string = "";			-- the "effects active this age" text
local m_srCivAges:table = {};			-- { "Phoenicia: Golden Age", ... } for met civs
local m_srUnmet:number = 0;				-- civilizations not met

function OnShowEraReviewPopup()
	local gameEras:table = Game.GetEras();
	if (gameEras == nil) then
		return;
	end

	local currentEraIndex:number = gameEras:GetCurrentEra();
	local prevEraIndex:number = currentEraIndex - 1;

	--If prevEra is -1 we just started a fresh game
	if prevEraIndex == -1 then
		return;
	end

	m_LocalPlayerID = Game.GetLocalPlayer();
	if m_LocalPlayerID < 0 then return; end

	m_PreviousEraIndex = prevEraIndex;
	m_CurrentEraIndex = currentEraIndex;

	Controls.Title:SetText(Locale.ToUpper(Locale.Lookup("LOC_ERA_REVIEW_POPUP_TITLE", GameInfo.Eras[m_CurrentEraIndex].Name)));
	Controls.EraImage:SetTexture(ERA_ILLUSTRATIONS[m_CurrentEraIndex]);

	local gameEras:table = Game.GetEras();
	local score	= gameEras:GetPlayerCurrentScore(m_LocalPlayerID);
	local prevGoldenAgeThreshold = gameEras:GetPlayerPreviousGoldenAgeThreshold(m_LocalPlayerID);
	local localPlayer	: table = Players[m_LocalPlayerID];

	if gameEras:HasHeroicGoldenAge(m_LocalPlayerID) then
		Controls.EraRibbon:SetTexture("Ages_BannerLongHeroic");
		Controls.Background:SetTexture("Ages_ParchmentHeroic");
		Controls.WindowFrame:SetTexture("Ages_FrameHeroic");
		Controls.EraRibbonText:SetColorByName("Black");
		Controls.EraRibbonValue:SetColorByName("Black");
		Controls.HeroicFlare:SetHide(false);
		m_srAgeName = "Heroic Age";
		Controls.EraRibbonValue:SetText(Locale.Lookup("LOC_ERAS_HEROIC") .. " [ICON_GLORY_SUPER_GOLDEN_AGE]");
		SRA_SetEffects(Locale.Lookup("LOC_ERA_REVIEW_HAVE_HEROIC_AGE_EFFECT_PARAM", {Name = "Amount", Value=localPlayer:GetCivilianLoyalty()}));
	elseif gameEras:HasGoldenAge(m_LocalPlayerID) then
		Controls.EraRibbon:SetTexture("Ages_BannerLongGolden");
		Controls.Background:SetTexture("Ages_ParchmentGolden");
		Controls.WindowFrame:SetTexture("Ages_FrameGolden");
		Controls.EraRibbonText:SetColorByName("White_Black");
		Controls.EraRibbonValue:SetColorByName("White_Black");
		Controls.HeroicFlare:SetHide(true);
		m_srAgeName = "Golden Age";
		Controls.EraRibbonValue:SetText(Locale.Lookup("LOC_ERAS_GOLDEN") .. " [ICON_GLORY_GOLDEN_AGE]");
		SRA_SetEffects(Locale.Lookup("LOC_ERA_REVIEW_HAVE_GOLDEN_AGE_EFFECT_PARAM", {Name = "Amount", Value=localPlayer:GetCivilianLoyalty()}));
	elseif gameEras:HasDarkAge(m_LocalPlayerID) then
		Controls.EraRibbon:SetTexture("Ages_BannerLongDark");
		Controls.Background:SetTexture("Ages_ParchmentDark");
		Controls.WindowFrame:SetTexture("Ages_FrameDark");
		Controls.EraRibbonText:SetColorByName("White_Black");
		Controls.EraRibbonValue:SetColorByName("White_Black");
		Controls.HeroicFlare:SetHide(true);
		m_srAgeName = "Dark Age";
		Controls.EraRibbonValue:SetText(Locale.Lookup("LOC_ERAS_DARK") .. " [ICON_GLORY_DARK_AGE]");
		SRA_SetEffects(Locale.Lookup("LOC_ERA_REVIEW_HAVE_DARK_AGE_EFFECT_PARAM", {Name = "Amount", Value=localPlayer:GetCivilianLoyalty()}));
	else
		Controls.EraRibbon:SetTexture("Ages_BannerLongNormal");
		Controls.Background:SetTexture("Ages_ParchmentNormal");
		Controls.WindowFrame:SetTexture("Ages_FrameNormal");
		Controls.EraRibbonText:SetColorByName("White_Black");
		Controls.EraRibbonValue:SetColorByName("White_Black");
		Controls.HeroicFlare:SetHide(true);
		m_srAgeName = "Normal Age";
		Controls.EraRibbonValue:SetText(Locale.Lookup("LOC_ERAS_NORMAL") .. " [ICON_GLORY_NORMAL_AGE]");
		SRA_SetEffects(Locale.Lookup("LOC_ERA_REVIEW_HAVE_NORMAL_AGE_EFFECT_PARAM", {Name = "Amount", Value=localPlayer:GetCivilianLoyalty()}));
	end

	PopulateLocalPlayerIcon();
	PopulateCivilizationIcons();

	m_srAnnouncePending = true;		-- ScreenReaderAccess: spoken from the update loop once the popup is really shown
	m_srAnnounceDelay = SRA_ANNOUNCE_DELAY;
	OnShow();
end

-- Largely copied from DiplomacyRibbon.lua
function PopulateLocalPlayerIcon()

	local pPlayer:table = Players[m_LocalPlayerID];
	local pPlayerConfig:table = PlayerConfigurations[m_LocalPlayerID];

	local backColor, frontColor = UI.GetPlayerColors(m_LocalPlayerID);
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

-- Largely copied from WorldRankings.lua
function PopulateCivilizationIcons()

	m_CivilizationIconIM:ResetInstances();
	m_srCivAges = {};		-- ScreenReaderAccess
	m_srUnmet = 0;			-- ScreenReaderAccess

	local gameEras:table = Game.GetEras();
	local localPlayer:table = Players[m_LocalPlayerID];

	local heroicPlayers:table = {};
	local goldenPlayers:table = {};
	local normalPlayers:table = {};
	local darkPlayers:table = {};
	local unmetPlayers:table = {};

	local aPlayers = PlayerManager.GetAliveMajors();
	for _, pPlayer in ipairs(aPlayers) do
		local playerID:number = pPlayer:GetID();
		if(playerID ~= m_LocalPlayerID) then
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
		AddPlayerEraIcon(playerID, "[ICON_GLORY_SUPER_GOLDEN_AGE]", "LOC_ERA_PROGRESS_HEROIC_AGE");
	end
	for i,playerID in ipairs(goldenPlayers) do
		AddPlayerEraIcon(playerID, "[ICON_GLORY_GOLDEN_AGE]", "LOC_ERA_PROGRESS_GOLDEN_AGE");
	end
	for i,playerID in ipairs(normalPlayers) do
		AddPlayerEraIcon(playerID, "[ICON_GLORY_NORMAL_AGE]", "LOC_ERA_PROGRESS_NORMAL_AGE");
	end
	for i,playerID in ipairs(darkPlayers) do
		AddPlayerEraIcon(playerID, "[ICON_GLORY_DARK_AGE]", "LOC_ERA_PROGRESS_DARK_AGE");
	end
	for i,playerID in ipairs(unmetPlayers) do
		AddPlayerEraIcon(playerID, "", "");
	end
end

-- ===========================================================================
function AddPlayerEraIcon(playerID:number, eraIcon:string, eraTooltip:string)
	local oCivIcon:object = CivilizationIcon:GetInstance(m_CivilizationIconIM);
	oCivIcon:UpdateIconFromPlayerID(playerID);
	oCivIcon:SetLeaderTooltip(playerID);
	oCivIcon:UpdateLeaderTooltip(playerID);
	oCivIcon.EraLabel:SetText(eraIcon);

	-- ScreenReaderAccess: met civilizations with their age; unmet ones are only counted (no names)
	if eraTooltip ~= "" then
		local civName:string = Locale.Lookup(PlayerConfigurations[playerID]:GetCivilizationShortDescription());
		table.insert(m_srCivAges, civName .. ": " .. CleanTextForSpeech(Locale.Lookup(eraTooltip)));
	else
		m_srUnmet = m_srUnmet + 1;
	end

	if eraTooltip ~= "" then
		oCivIcon.EraLabel:SetToolTipString(Locale.Lookup(eraTooltip));
	end

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

function sortBreakdown(a,b) 
	local _, aVal = next(a);
	local _, bVal = next(b);
	local result = aVal > bVal;
	return result;
end

function sortBreakdownInverse(a,b)
	local _, aVal = next(a);
	local _, bVal = next(b);
	local result = aVal < bVal;
	return result;
end

function OnShow()
	UIManager:QueuePopup(ContextPtr, PopupPriority.MediumHigh);
end

function OnClose()
	UIManager:DequeuePopup(ContextPtr);
end

function OnContinue()
	UIManager:DequeuePopup(ContextPtr);
	LuaEvents.EraReviewPopup_MakeDedication(m_PreviousEraIndex, m_CurrentEraIndex);
end

-- ===========================================================================
--	ScreenReaderAccess
-- ===========================================================================
function SRA_SetEffects(text:string)
	Controls.EraEffects:SetText(text);
	m_srEffects = CleanTextForSpeech(text);
end

function SRA_EraName()
	if m_CurrentEraIndex >= 0 and GameInfo.Eras[m_CurrentEraIndex] ~= nil then
		return Locale.Lookup(GameInfo.Eras[m_CurrentEraIndex].Name);
	end
	return "";
end

-- "New era: The world has entered the Renaissance Era. You are in a Dark Age. <effects>. Enter to continue, Space for details"
function SRA_Announce()
	local text:string = "New era: The world has entered the " .. SRA_EraName() .. ". You are in a " .. m_srAgeName .. ".";
	if m_srEffects ~= "" then text = text .. " " .. string.gsub(m_srEffects, "[%.%s]+$", "") .. "."; end
	OutputMessageToScreenReader(text .. " " .. SRKey( "Enter" ) .. " to continue, " .. SRKey( "Space" ) .. " for details.");
end

-- Space: the ages of the other civilizations and the effects again
function SRA_Details()
	local parts:table = { "Your age: " .. m_srAgeName };
	if #m_srCivAges > 0 then
		table.insert(parts, "Current age by civilization: " .. table.concat(m_srCivAges, ", "));
	else
		table.insert(parts, "No other civilization met");
	end
	if m_srUnmet > 0 then table.insert(parts, m_srUnmet .. " unmet"); end
	if m_srEffects ~= "" then table.insert(parts, "Effects active this age: " .. m_srEffects); end
	OutputMessageToScreenReader(table.concat(parts, ". ") .. ". " .. SRKey( "Enter" ) .. " to continue.");
end

function SRA_OnUpdate(deltaTime:number)
	if m_srAnnouncePending and not ContextPtr:IsHidden() then
		m_srAnnounceDelay = m_srAnnounceDelay - deltaTime;
		if m_srAnnounceDelay > 0 then return; end
		m_srAnnouncePending = false;
		local ok:boolean, err = xpcall(SRA_Announce, KeyNavErrorHandler);
		if not ok then print("EraReview announce error: " .. tostring(err)); end
	end
end

function SRA_HandleKey(key:number)
	if key == Keys.VK_RETURN then
		OnContinue();
	elseif key == Keys.VK_SPACE then
		SRA_Details();
	elseif key == Keys.VK_ESCAPE then
		OnClose();
		local blocked:boolean = false;
		pcall(function()
			local label = ContextPtr:LookUpControl("/InGame/HUD/ActionPanel/EndTurnText");
			blocked = label ~= nil and string.find(string.lower(label:GetText() or ""), "dedication", 1, true) ~= nil;
		end);
		if blocked then
			OutputMessageToScreenReader("Closed. Make Dedication still blocks the turn; " .. SRKey( "Enter" ) .. " on it in " .. SRKey( "Control N", "RB" ) .. " or Next Action reopens it.");
		else
			OutputMessageToScreenReader("Closed");
		end
	end
end

-- ===========================================================================
--	LUA EVENT
--	Reload support
-- ===========================================================================
function OnInit( isReload:boolean )
	if isReload then		
		LuaEvents.GameDebug_GetValues(RELOAD_CACHE_ID);	
	end
end
function OnShutdown()
	SRUnlistenAll();		-- ScreenReaderAccess: hot reload leaves the old instance's listeners registered
	LuaEvents.GameDebug_AddValue(RELOAD_CACHE_ID, "isHidden", ContextPtr:IsHidden());
	LuaEvents.GameDebug_AddValue(RELOAD_CACHE_ID, "m_PreviousEraIndex", m_PreviousEraIndex);
	LuaEvents.GameDebug_AddValue(RELOAD_CACHE_ID, "m_CurrentEraIndex", m_CurrentEraIndex);
end
function OnGameDebugReturn(context:string, reloadState:table)
	if context == RELOAD_CACHE_ID then
		if not reloadState.isHidden and OnGameEraChanged ~= nil then	-- ScreenReaderAccess: upstream calls a function that does not exist
			OnGameEraChanged(reloadState.m_PreviousEraIndex, reloadState.m_CurrentEraIndex);
		end
	end
end

-- ===========================================================================
--	Input
--	UI Event Handler
-- ===========================================================================
function OnInputHandler( pInputStruct:table )
	if ( pInputStruct:GetMessageType() == KeyEvents.KeyUp ) then
		local key:number = pInputStruct:GetKey();
		-- ScreenReaderAccess: Enter = Continue, Space = details, Escape = close
		local ok:boolean, err = xpcall(function() SRA_HandleKey(key); end, KeyNavErrorHandler);
		if not ok then print("EraReview input error: " .. tostring(err)); end
	end
	-- Intercept all input while on this screen (is modal)
	return true;
end

function Initialize()
	--OnShowEraReviewPopup(); -- DEBUG
	ContextPtr:SetHide(true); -- PRODUCTION

	ContextPtr:SetInitHandler( OnInit );
	ContextPtr:SetShutdown( OnShutdown );
	ContextPtr:SetInputHandler( OnInputHandler, true );
	ContextPtr:SetUpdate( SRA_OnUpdate );		-- ScreenReaderAccess

	Controls.Close:RegisterCallback(Mouse.eLClick, OnClose);
	Controls.Continue:RegisterCallback(Mouse.eLClick, OnContinue);

	SRListen(LuaEvents.EraReviewPopup_Show, OnShowEraReviewPopup);		-- ScreenReaderAccess
	SRListen(LuaEvents.GameDebug_Return, OnGameDebugReturn);
end
Initialize();