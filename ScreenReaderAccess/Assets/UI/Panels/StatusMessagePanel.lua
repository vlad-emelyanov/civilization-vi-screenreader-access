-- Copyright 2016-2019, Firaxis Games
-- Non-interactive messages (e.g., Gossip and combat results) that appear in the upper-center of the screen.

include( "InstanceManager" );

include("ScreenReader");

-- =========================================================================== 
--	CONSTANTS
-- =========================================================================== 
local debug_testActive				:boolean = false;	-- (false) Enable test messages and hot keys D, and G
local DEFAULT_TIME_TO_DISPLAY		:number = 7;		-- Seconds to display the message
local TXT_PLAYER_CONNECTED_CHAT		:string = Locale.Lookup( "LOC_MP_PLAYER_CONNECTED_CHAT" );
local TXT_PLAYER_DISCONNECTED_CHAT  :string	= Locale.Lookup( "LOC_MP_PLAYER_DISCONNECTED_CHAT" );
local TXT_PLAYER_KICKED_CHAT		:string	= Locale.Lookup( "LOC_MP_PLAYER_KICKED_CHAT" );


-- =========================================================================== 
--	MEMBERS
-- =========================================================================== 
local m_gossipIM		:table = InstanceManager:new( "GossipMessageInstance", "Root", Controls.GossipStack );
local m_statusIM		:table = InstanceManager:new( "StatusMessageInstance", "Root", Controls.DefaultStack );
local m_kGossip			:table = {};
local m_isGossipExpanded:boolean = false;
local m_kMessages		:table = {};


-- =========================================================================== 
--	FUNCTIONS
-- =========================================================================== 


-- Begin ScreenReaderAccess mod change
-- Unit-versus-unit combat status messages whose content the hub speaks itself ("X attacks Y: Y takes N damage, ...",
-- kills). They are dropped only when the hub really spoke a combat line in the last SR_COMBAT_WINDOW seconds
-- (LuaEvents.SRA_CombatSpoken). City and district targets are never listed (the hub does not report damage to
-- cities), nor withdrawals from anti-air, captures, WMD. The templates are turned into patterns with the
-- placeholders as ".-" and "a"/"an" (LOC_GRAMMAR_A_AN) as "an?".
local SR_COMBAT_WINDOW:number = 2.0;
local SR_COVERED_COMBAT_TAGS:table = {
	"LOC_COMBAT_YOUR_UNIT_WAS_STRAFED_BY_ENEMY", "LOC_COMBAT_YOUR_UNIT_WAS_BOMBARDED_BY_ENEMY", "LOC_COMBAT_YOUR_UNIT_BOMBARDED_ENEMY",
	"LOC_COMBAT_YOUR_UNIT_BOMBED_ENEMY", "LOC_COMBAT_YOUR_UNIT_STRAFED_ENEMY", "LOC_COMBAT_YOUR_UNIT_DAMAGED_ENEMY",
	"LOC_COMBAT_YOUR_UNIT_DESTROYED_ENEMY", "LOC_COMBAT_YOUR_UNIT_DIED_ATTACKING", "LOC_COMBAT_YOUR_UNIT_DIED_DEFENDING",
	"LOC_COMBAT_YOUR_UNIT_DIED_INTERCEPTING", "LOC_COMBAT_YOU_KILLED_ENEMY_UNIT", "LOC_MISC_YOUR_UNIT_DIED_BY_UNKNOWN",
	"LOC_COMBAT_YOUR_UNIT_WITHDREW", "LOC_COMBAT_ENEMY_UNIT_WITHDREW",
};
local m_srCoveredPatterns:table = nil;
local m_srLastCombatSpoken:number = -100;

function SRCombatSpoken()
	m_srLastCombatSpoken = UI.GetElapsedTime();
end

local function SRNormalize( text:string )
	return string.gsub( string.gsub( text, "^%s+", "" ), "%s+", " " );
end

function SRIsCoveredCombatMessage( message:string )
	if message == nil or UI.GetElapsedTime() - m_srLastCombatSpoken > SR_COMBAT_WINDOW then return false; end
	if m_srCoveredPatterns == nil then
		m_srCoveredPatterns = {};
		for _, tag in ipairs( SR_COVERED_COMBAT_TAGS ) do
			local template:string = Locale.Lookup( tag, "", "", "", "", "", "" );
			if template ~= nil and template ~= "" and template ~= tag then
				template = SRNormalize( template );
				template = string.gsub( template, " a ", "  " );		-- {LOC_GRAMMAR_A_AN << adjective}: "a " or "an "
				template = string.gsub( template, "%p", "%%%0" );
				template = string.gsub( template, "", "an?" );
				template = string.gsub( template, "", ".-" );
				table.insert( m_srCoveredPatterns, "^" .. template .. "$" );
			end
		end
	end
	local text:string = SRNormalize( message );
	for _, pattern in ipairs( m_srCoveredPatterns ) do
		if string.find( text, pattern ) ~= nil then return true; end
	end
	return false;
end
-- End ScreenReaderAccess mod change

-- ===========================================================================
--	EVENT
--	subType	when gossip it's the db enum for the gossip type
-- =========================================================================== 
function OnStatusMessage( message:string, displayTime:number, type:number, subType:number )
	if (type == ReportingStatusTypes.GOSSIP) then
		AddGossip( subType, message, displayTime );
	end

	if (type == ReportingStatusTypes.DEFAULT) then
		AddDefault( message, displayTime );
	end

	-- Begin ScreenReaderAccess mod change
	-- unit-versus-unit damage and kill messages are already spoken by the InGameAccess hub (CombatVisBegin + damage events)
	if not SRIsCoveredCombatMessage(message) then
		OutputMessageToScreenReader(message, true);
	end
	-- End ScreenReaderAccess mod change

	RealizeMainAreaPosition();
end

-- =========================================================================== 
--	Realize the first Gossip in the list.
-- =========================================================================== 
function RealizeFirstGossip()
	local num:number = table.count(m_kGossip);
	if num < 1 then
		return;
	end	
	local uiInstance:table= m_kGossip[1].uiInstance;
	if uiInstance.Root:IsHidden() then
		uiInstance.Root:SetHide( false );
	end
	uiInstance.ExpandButton:SetHide( num == 1 );
	uiInstance.ExpandButton:SetSelected( m_isGossipExpanded );
end

-- =========================================================================== 
--	Add a gossip entry.
-- =========================================================================== 
function AddGossip( eGossipType:number, message:string, optionalDisplayTime:number )
	if optionalDisplayTime == nil or optionalDisplayTime == 0 then
		optionalDisplayTime = DEFAULT_TIME_TO_DISPLAY;
	end

	-- Add visually
	local uiInstance	:table = m_gossipIM:GetInstance();
	local kGossipData	:table = GameInfo.Gossips[eGossipType];		-- Lookup via hash
	if kGossipData then
		uiInstance.Icon:SetIcon("ICON_GOSSIP_"..kGossipData.GroupType);
		uiInstance.IconBack:SetIcon("ICON_GOSSIP_"..kGossipData.GroupType);
	else
		UI.DataError("The gossip type '"..tostring(eGossipType).."' could not be found in the database; icon will not be set.");
	end

	uiInstance.Message:SetText( message );
	
	-- Add the data (including reference to visual)
	local kEntry:table = {
		eGossipType = eGossipType,
		message		= message,
		displayTime = optionalDisplayTime,
		uiInstance	= uiInstance
	};
	table.insert( m_kGossip, kEntry);

	local GOSSIP_VERTICAL_PADDING	:number = 20;
	local verticalSpace				:number = uiInstance.Message:GetSizeY() + GOSSIP_VERTICAL_PADDING;
	
	uiInstance.Root:SetHide( false );
	uiInstance.Content:SetSizeY( verticalSpace );
	uiInstance.Anim:SetEndPauseTime( optionalDisplayTime );
	uiInstance.Anim:SetToBeginning();
	uiInstance.ExpandButton:SetHide( true );

	-- This may or may not be the first button and if this is the second gossip
	-- then the first gossip needs to be realized to show the collapse button.
	RealizeFirstGossip( uiInstance );

	-- If showing all gossips or if this is the first in the list, then start animation.
	local isFirstGossip:boolean = table.count(m_kGossip)==1;	
	if m_isGossipExpanded or (m_isGossipExpanded==false and isFirstGossip) then
		uiInstance.Anim:Play();		
	end

	-- Now thata data exists, create lambdas that passes it in.
	uiInstance.Anim:RegisterEndCallback(					function() OnGossipEndAnim(kEntry,uiInstance) end );
	uiInstance.Button:RegisterCallback( Mouse.eLClick,		function() OnGossipClicked(kEntry,uiInstance); end );
	uiInstance.Button:RegisterCallback( Mouse.eRClick,		function() OnGossipClicked(kEntry,uiInstance); end );
	uiInstance.ExpandButton:RegisterCallback( Mouse.eLClick,function() OnToggleGossipExpand(kEntry,uiInstance); end );
	
	-- Hide this if not the first and list is collapsed.
	local numGossips:number = table.count(m_kGossip);
	if m_isGossipExpanded==false and (numGossips > 1) then
		uiInstance.Root:SetHide( true );
	end
end

-- ===========================================================================
function RemoveGossip( kEntry:table, uiInstance:table )
	-- Remove callbacks and visuals
	uiInstance.Anim:ClearEndCallback();	
	uiInstance.Anim:ClearAnimCallback();	
	m_gossipIM:ReleaseInstance( uiInstance );	
	-- Remove data
	for i,kTableEntry in ipairs(m_kGossip) do
		if kTableEntry == kEntry then
			table.remove( m_kGossip, i, 1);
			break;
		end
	end

	-- Look through and set animation appropriately.
	for i,kTableEntry in ipairs(m_kGossip) do
		local uiInstance :table = kTableEntry.uiInstance;
		uiInstance.Anim:SetToEnd();
		if i==1 then
			uiInstance.Anim:Play();
		else
			uiInstance.Anim:Stop();
		end
		uiInstance.Root:SetHide( m_isGossipExpanded==false );
	end
	RealizeFirstGossip();

	Controls.DefaultStack:CalculateSize();
end

-- ===========================================================================
function RemoveAllGossip()
	if table.count(m_kGossip) == 0 then
		return;
	end
	for i,kTableEntry in ipairs(m_kGossip) do
		local uiInstance :table = kTableEntry.uiInstance;
		uiInstance.Anim:Stop();
		uiInstance.Root:SetHide( true );
	end
	m_gossipIM:ResetInstances();
	m_kGossip = {};
end

-- ===========================================================================
--	UI Callback
--	Clicked to dismiss message
-- ===========================================================================
function OnGossipClicked( kEntry:table, uiInstance:table )
	UI.PlaySound("Play_UI_Click");
	RemoveGossip(kEntry, uiInstance );
end

-- ===========================================================================
--	UI Callback
--	Clicked to dismiss message
-- ===========================================================================
function OnToggleGossipExpand( kEntry:table, uiInstance:table )

	m_isGossipExpanded = not m_isGossipExpanded;

	-- Expanded: Show all and reset animation.
	if m_isGossipExpanded then
		for i,kGossip in ipairs(m_kGossip) do
			local uiInstance:table = kGossip.uiInstance;
			uiInstance.Root:SetHide( false );
			uiInstance.ExpandButton:SetSelected( true );
			uiInstance.Anim:SetToEnd();
			if i==1 then
				uiInstance.Anim:Play();
			else
				uiInstance.Anim:Stop();
			end
		end
		return;
	end

	-- Collapsed: only showing the first gossip.
	for i,kGossip in ipairs(m_kGossip) do
		local uiInstance:table = kGossip.uiInstance;
		uiInstance.Root:SetHide( i>1 );
		uiInstance.ExpandButton:SetSelected( false );
		uiInstance.Anim:SetToEnd();
		if i==1 then
			uiInstance.Anim:Play();
		else
			uiInstance.Anim:Stop();
			uiInstance.ExpandButton:SetHide( true );
		end
	end
end

-- ===========================================================================
function OnGossipEndAnim( kEntry:table, uiInstance:table )
	RemoveGossip( kEntry, uiInstance );
end






-- =========================================================================== 
--	Add default message (e.g., combat messages)
-- =========================================================================== 
function AddDefault( message, displayTime )

	-- TODO: Simplify
	local type = ReportingStatusTypes.DEFAULT 
	local kTypeEntry :table = m_kMessages[type];
	if (kTypeEntry == nil) then
		-- New type
		m_kMessages[type] = {
			InstanceManager = nil,
			MessageInstances= {}
		};
		kTypeEntry = m_kMessages[type];

		kTypeEntry.InstanceManager	= m_statusIM;
	end

	local uiInstance:table = kTypeEntry.InstanceManager:GetInstance();
	table.insert( kTypeEntry.MessageInstances, uiInstance );

	if displayTime==nil or displayTime==0 then
		displayTime = DEFAULT_TIME_TO_DISPLAY;
	end
	uiInstance.Message:SetText( message );

	uiInstance.Button:RegisterCallback( Mouse.eLClick, function() OnMessageClicked(kTypeEntry,uiInstance) end );
	uiInstance.Anim:SetEndPauseTime( displayTime );		
	uiInstance.Anim:RegisterEndCallback( function() OnEndAnim(kTypeEntry,uiInstance) end );
	uiInstance.Anim:SetToBeginning();
	uiInstance.Anim:Play();		

	Controls.DefaultStack:CalculateSize();
end

-- ===========================================================================
function RemoveMessage( kTypeEntry:table, uiInstance:table )
	uiInstance.Anim:ClearEndCallback();
	Controls.DefaultStack:CalculateSize();
	kTypeEntry.InstanceManager:ReleaseInstance( uiInstance );
end

-- ===========================================================================
function OnEndAnim( kTypeEntry:table, uiInstance:table )
	RemoveMessage( kTypeEntry, uiInstance );
end

-- ===========================================================================
function OnMessageClicked( kTypeEntry:table, uiInstance:table )
	RemoveMessage( kTypeEntry, uiInstance );
end

-- ===========================================================================
--	EVENT
-- ===========================================================================
function OnMultplayerPlayerConnected( playerID:number )
	if playerID == -1 or playerID == 1000 then
		return;
	end

	if( ContextPtr:IsHidden() == false and GameConfiguration.IsNetworkMultiplayer() ) then
		local pPlayerConfig :table = PlayerConfigurations[playerID];
		local statusMessage :string= Locale.Lookup(pPlayerConfig:GetPlayerName()) .. " " .. TXT_PLAYER_CONNECTED_CHAT;
		OnStatusMessage( statusMessage, DEFAULT_TIME_TO_DISPLAY, ReportingStatusTypes.DEFAULT );
	end
end

-- ===========================================================================
--	EVENT
-- ===========================================================================
function OnMultiplayerPrePlayerDisconnected( playerID:number )
	if playerID == -1 or playerID == 1000 then
		return;
	end

	if( ContextPtr:IsHidden() == false and GameConfiguration.IsNetworkMultiplayer() ) then
		local pPlayerConfig :table = PlayerConfigurations[playerID];
		local statusMessage :string= Locale.Lookup(pPlayerConfig:GetPlayerName());
		if(Network.IsPlayerKicked(playerID)) then
			statusMessage = statusMessage .. " " .. TXT_PLAYER_KICKED_CHAT;
		else
    		statusMessage = statusMessage .. " " .. TXT_PLAYER_DISCONNECTED_CHAT;
		end
		OnStatusMessage(statusMessage, DEFAULT_TIME_TO_DISPLAY, ReportingStatusTypes.DEFAULT);
	end
end

-- ===========================================================================
--	EVENT
-- ===========================================================================
function OnLocalTurnEnd( a,b,c )	
	local playerID	:number = Game.GetLocalPlayer();
	if playerID == -1 or playerID == 1000 then return; end;
	RemoveAllGossip();
end

-- ===========================================================================
--	Testing: When on the "G" and "D" keys generate messages.
-- ===========================================================================
function DebugTest()
	OnStatusMessage("Press D,F or G to generate gossip.  Hold Shift+D or G to generate notifications.", 7, ReportingStatusTypes.DEFAULT );
	ContextPtr:SetInputHandler( 
		function( pInputStruct ) 
			local uiMsg = pInputStruct:GetMessageType();
			if uiMsg == KeyEvents.KeyUp then 
				local key = pInputStruct:GetKey();
				local type = pInputStruct:IsShiftDown() and ReportingStatusTypes.DEFAULT or ReportingStatusTypes.GOSSIP ;
				local subType = DB.MakeHash("GOSSIP_MAKE_DOW");
				if key == Keys.D then OnStatusMessage("Testing out status message ajsdkl akds dk dkdkj dkdkd ajksaksdkjkjd dkadkj f djkdkjdkj dak sdkjdjkal dkd kd dk adkj dkkadj kdjd kdkjd jkd jd dkj djkd dkdkdjdkdkjdkd djkd dkd dkjd kdjdkj d", 7, type, subType); return true; end
				if key == Keys.F then OnStatusMessage("The rain in Spain will dry quickly in Madrid.", 7, type, subType); return true; end
				if key == Keys.G then OnStatusMessage("Testing out gossip message", nil, type, subType ); return true; end
			end	
			return false;
		end, true);
end


-- ===========================================================================
--	Position to just below the height of the diplomacy ribbon scroll area
-- ===========================================================================
function RealizeMainAreaPosition()
	
	local m_uiRibbonScroll :table	= ContextPtr:LookUpControl( "/InGame/DiplomacyRibbon/ScrollContainer" );
	if m_uiRibbonScroll == nil then
		return
	end
	local ribbonHeight:number = m_uiRibbonScroll:GetSizeY();

	-- Bail if no change.
	local EXTRA_CLEARANCE	:number = 50;
	local currentOffsetY	:number = Controls.MainArea:GetOffsetY();
	if currentOffsetY == (ribbonHeight + EXTRA_CLEARANCE) then
		return;
	end

	-- Set starting height of stack to just below ribbon.	
	Controls.MainArea:SetOffsetY( ribbonHeight + EXTRA_CLEARANCE );	
end


-- ===========================================================================
--	UI Callback
-- ===========================================================================
function OnShutdown()
	Events.LocalPlayerTurnEnd.Remove( OnLocalTurnEnd );
	Events.StatusMessage.Remove( OnStatusMessage );
	LuaEvents.SRA_CombatSpoken.Remove( SRCombatSpoken );		-- ScreenReaderAccess
	Events.MultiplayerPlayerConnected.Remove( OnMultplayerPlayerConnected );
	Events.MultiplayerPrePlayerDisconnected.Remove( OnMultiplayerPrePlayerDisconnected );
end

-- ===========================================================================
function LateInitialize()
	RealizeMainAreaPosition();

	Events.LocalPlayerTurnEnd.Add( OnLocalTurnEnd );
	Events.StatusMessage.Add( OnStatusMessage );
	LuaEvents.SRA_CombatSpoken.Add( SRCombatSpoken );		-- ScreenReaderAccess
	Events.MultiplayerPlayerConnected.Add( OnMultplayerPlayerConnected );
	Events.MultiplayerPrePlayerDisconnected.Add( OnMultiplayerPrePlayerDisconnected );
end

-- ===========================================================================
--	UI Callback
-- ===========================================================================
function OnInit()
	LateInitialize();
end

-- ===========================================================================
--	
-- ===========================================================================
function Initialize()
	ContextPtr:SetInitHandler( OnInit );
	ContextPtr:SetShutdown( OnShutdown );
	if debug_testActive then DebugTest(); end	-- Enable debug mode?
end
if GameCapabilities.HasCapability("CAPABILITY_DISPLAY_HUD_GOSSIP_LIST") then
	Initialize();
end
