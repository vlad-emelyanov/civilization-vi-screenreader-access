-- Copyright 2019, Firaxis Games
include("InstanceManager");
include("KeyNavList");		-- ScreenReaderAccess: keyboard list of the beliefs

-- ===========================================================================
--	CONSTANTS
-- ===========================================================================

local SIZE_BELIEF_ICON_LARGE					:number = 64;
local BELIEFS_PANEL_RELATIVE_SIZE_UNSELECTED	:number = -236;
local BELIEFS_PANEL_RELATIVE_SIZE_SELECTED		:number = -326;

local DATA_FIELD_BELIEF_INDEX:string = "DataField_BeliefIndex";

-- ===========================================================================
--	VARIABLES
-- ===========================================================================

local m_pSelectBeliefsIM:table = InstanceManager:new("BeliefSlot", "BeliefButton", Controls.BeliftStack);

local m_pGameReligion:table = Game.GetReligion();

local m_uiSelectedBeliefInstance:table = nil;

local m_srList:table = nil;				-- ScreenReaderAccess
local m_srInstances:table = {};			-- ScreenReaderAccess: belief index -> button instance (filled by Realize)

-- ===========================================================================
function Realize()

	-- Update available pantheon beliefs
	m_pSelectBeliefsIM:ResetInstances();
	m_srInstances = {};
	for row in GameInfo.Beliefs() do
		if CanSelectBelief(row) then
			local beliefInst:table = m_pSelectBeliefsIM:GetInstance();
			beliefInst[DATA_FIELD_BELIEF_INDEX] = row.Index;
			m_srInstances[row.Index] = beliefInst;		-- ScreenReaderAccess
			beliefInst.BeliefLabel:LocalizeAndSetText(Locale.ToUpper(row.Name));
			beliefInst.BeliefDescription:LocalizeAndSetText(row.Description);
			SetBeliefIcon(beliefInst.BeliefIcon, row.BeliefType, SIZE_BELIEF_ICON_LARGE);
			beliefInst.BeliefButton:SetSelected(beliefInst == m_uiSelectedBeliefInstance);
			beliefInst.BeliefButton:RegisterCallback( Mouse.eLClick, function() OnBeliefSelected(beliefInst); end );
			beliefInst.BeliefButton:RegisterCallback( Mouse.eMouseEnter, function() UI.PlaySound("Main_Menu_Mouse_Over"); end );
		end
	end

	RealizeCurrentSelection();
end

-- ===========================================================================
function RealizeCurrentSelection()
	if m_uiSelectedBeliefInstance == nil then
		Controls.ReligionOrPatheonTitle:SetText(Locale.ToUpper("LOC_UI_RELIGION_CHOOSING_PANTHEON"));
		Controls.SelectedBeliefGrid:SetHide(true);

		Controls.ConfirmGrid:SetHide(true);
		Controls.BottomGrid:SetParentRelativeSizeY(BELIEFS_PANEL_RELATIVE_SIZE_UNSELECTED);
	else
		local kBeliefDef:table = GameInfo.Beliefs[m_uiSelectedBeliefInstance[DATA_FIELD_BELIEF_INDEX]];
		Controls.ReligionOrPatheonTitle:SetText(Locale.ToUpper(Locale.Lookup("LOC_UI_RELIGION_PANTHEON_NAME", kBeliefDef.Name)));
	
		-- Show selected belief
		Controls.SelectedBeliefLabel:LocalizeAndSetText(Locale.ToUpper(kBeliefDef.Name));
		Controls.SelectedBeliefDescription:LocalizeAndSetText(kBeliefDef.Description);
		SetBeliefIcon(Controls.SelectedBeliefIcon, kBeliefDef.BeliefType, SIZE_BELIEF_ICON_LARGE);
		Controls.SelectedBeliefGrid:SetHide(false);

		Controls.ConfirmGrid:SetHide(false);
		Controls.BottomGrid:SetParentRelativeSizeY(BELIEFS_PANEL_RELATIVE_SIZE_SELECTED);
	end
end

-- ===========================================================================
function CanSelectBelief( kBeliefDef:table )
	if (not m_pGameReligion:IsInSomePantheon(kBeliefDef.Index) and
		not m_pGameReligion:IsInSomeReligion(kBeliefDef.Index) and
		kBeliefDef.BeliefClassType == "BELIEF_CLASS_PANTHEON") then
		return true;
	end

	return false;
end

-- ===========================================================================
function SetBeliefIcon(targetControl:table, beliefType:string, iconSize:number)
	local textureOffsetX:number, textureOffsetY:number, textureSheet:string = IconManager:FindIconAtlas("ICON_" .. beliefType, iconSize);
	if(textureSheet == nil or textureSheet == "") then
		error("Could not find icon in SetBeliefIcon: beliefType=\""..beliefType.."\", iconSize="..tostring(iconSize) );
	else
		targetControl:SetTexture(textureOffsetX, textureOffsetY, textureSheet);
		targetControl:SetSizeVal(iconSize, iconSize);
	end
end

-- ===========================================================================
function OnBeliefSelected( instance:table )
	-- Ignore select if this belief is already selected
	if m_uiSelectedBeliefInstance == instance then
		return;
	end
	
	SetSelectedBeliefInstance(instance);
end

-- ===========================================================================
function SetSelectedBeliefInstance( instance:table )
	-- Unselect the previous selection
	if m_uiSelectedBeliefInstance ~= nil then
		m_uiSelectedBeliefInstance.BeliefButton:SetSelected(false);
	end

	-- Select new belief instance
	m_uiSelectedBeliefInstance = instance;
	m_uiSelectedBeliefInstance.BeliefButton:SetSelected(true);

	RealizeCurrentSelection();
end

-- ===========================================================================
function ClearBeliefSelection()
	if m_uiSelectedBeliefInstance ~= nil then
		m_uiSelectedBeliefInstance.BeliefButton:SetSelected(false);
		m_uiSelectedBeliefInstance = nil;
	end

	RealizeCurrentSelection();
end

-- ===========================================================================
function ConfirmPantheon()
	if m_uiSelectedBeliefInstance ~= nil then
		local beliefIndex:number = m_uiSelectedBeliefInstance[DATA_FIELD_BELIEF_INDEX];

		local tParameters:table = {};
		tParameters[PlayerOperations.PARAM_BELIEF_TYPE] = GameInfo.Beliefs[beliefIndex].Hash;
		tParameters[PlayerOperations.PARAM_INSERT_MODE] = PlayerOperations.VALUE_EXCLUSIVE;
		UI.RequestPlayerOperation(Game.GetLocalPlayer(), PlayerOperations.FOUND_PANTHEON, tParameters);
		UI.PlaySound("Confirm_Religion");

		Close();

		LuaEvents.PantheonChooser_OpenReligionPanel();
	end
end

-- ===========================================================================
function Close()
	if not ContextPtr:IsHidden() and not Controls.PantheonChooserSlideAnim:IsReversing() then
		Controls.PantheonChooserSlideAnim:SetToEnd();
        Controls.PantheonChooserSlideAnim:Reverse();

		UI.PlaySound("Tech_Tray_Slide_Closed");

        LuaEvents.PantheonChooser_CloseReligion();
	end
end

-- ===========================================================================
function Open()
	if ContextPtr:IsHidden() then
		ContextPtr:SetHide(false);
        m_uiSelectedBeliefInstance = nil;

        LuaEvents.PantheonChooser_OpenReligion();

		-- Play Open Animation
		Controls.PantheonChooserSlideAnim:SetToBeginning();
		Controls.PantheonChooserSlideAnim:Play();

		UI.PlaySound("Tech_Tray_Slide_Open");

		Realize();
		SRA_Announce();		-- ScreenReaderAccess
	end
end

-- ===========================================================================
-- Begin ScreenReaderAccess change: keyboard list of the pantheon beliefs.
-- Enter selects a belief (the panel's own selection), Enter again on the selected belief confirms it, Escape closes.
-- ===========================================================================
function SRA_GetItems()
	local items:table = {};
	for row in GameInfo.Beliefs() do
		if CanSelectBelief(row) then
			local text:string = CleanTextForSpeech(Locale.Lookup(row.Name)) .. ": " .. CleanTextForSpeech(Locale.Lookup(row.Description));
			if m_uiSelectedBeliefInstance ~= nil and m_uiSelectedBeliefInstance[DATA_FIELD_BELIEF_INDEX] == row.Index then
				text = text .. ", selected, Enter to confirm";
			end
			table.insert(items, { key = row.Index, text = text, belief = row });
		end
	end
	return items;
end

function SRA_OnActivate( item:table )
	local name:string = CleanTextForSpeech(Locale.Lookup(item.belief.Name));
	if m_uiSelectedBeliefInstance ~= nil and m_uiSelectedBeliefInstance[DATA_FIELD_BELIEF_INDEX] == item.belief.Index then
		ConfirmPantheon();
		OutputMessageToScreenReader("Pantheon chosen: " .. name);
	elseif m_srInstances[item.belief.Index] ~= nil then
		OnBeliefSelected(m_srInstances[item.belief.Index]);
		OutputMessageToScreenReader(name .. " selected. Enter to confirm, or pick another");
	end
end

function SRA_OnClose()
	Close();
	OutputMessageToScreenReader("Pantheon chooser closed");
end

function SRA_Announce()
	local faith:number = Players[Game.GetLocalPlayer()]:GetReligion():GetFaithBalance();
	m_uiSelectedBeliefInstance = nil;
	m_srList.Reset();
	m_srList.Open("Choose a pantheon, " .. math.floor(faith) .. " faith");
end
-- End ScreenReaderAccess change

-- ===========================================================================
-- Context Event
-- ===========================================================================
function OnInit( isReload:boolean )
	LateInitialize();

	if isReload and not ContextPtr:IsHidden() then
		Realize();
	end
end

-- ===========================================================================
-- Context Event
-- ===========================================================================
function OnInputHandler( pInputStruct:table )
	if m_srList ~= nil and m_srList.HandleInput( pInputStruct ) then return true; end		-- ScreenReaderAccess
	if pInputStruct:GetMessageType() == KeyEvents.KeyUp and pInputStruct:GetKey() == Keys.VK_ESCAPE then 
		Close();
		return true;
	end
	return false;
end

-- ===========================================================================
-- Context Event
-- ===========================================================================
function OnShutdown()
	LuaEvents.NotificationPanel_OpenPantheonChooser.Remove( Open );
	LuaEvents.LaunchBar_OpenPantheonChooser.Remove( Open );
	LuaEvents.LaunchBar_ClosePantheonChooser.Remove( Close );
end

-- ===========================================================================
function OnAnimEnd()
	if Controls.PantheonChooserSlideAnim:IsReversing() then
		-- If we're reversing due to closing the panel then hide the context after that anim ends
		ContextPtr:SetHide(true);
	end
end

-- ===========================================================================
function LateInitialize()
	LuaEvents.NotificationPanel_OpenPantheonChooser.Add( Open );
	LuaEvents.LaunchBar_OpenPantheonChooser.Add( Open );
	LuaEvents.LaunchBar_ClosePantheonChooser.Add( Close );

	Controls.Header_CloseButton:RegisterCallback( Mouse.eLClick, Close );

	Controls.SelectedBeliefGrid:RegisterCallback( Mouse.eLClick, ClearBeliefSelection );
	Controls.ConfirmPantheonButton:RegisterCallback( Mouse.eLClick, ConfirmPantheon );
	Controls.ConfirmPantheonButton:RegisterCallback(Mouse.eMouseEnter, function() UI.PlaySound("Main_Menu_Mouse_Over"); end); 
	Controls.CancelButton:RegisterCallback( Mouse.eLClick, ClearBeliefSelection );
	Controls.CancelButton:RegisterCallback(Mouse.eMouseEnter, function() UI.PlaySound("Main_Menu_Mouse_Over"); end); 

	Controls.PantheonChooserSlideAnim:RegisterEndCallback( OnAnimEnd );
end

-- ===========================================================================
function Initialize()
	m_srList = KeyNavList_Create{		-- ScreenReaderAccess
		build = SRA_GetItems,
		isActive = function() return not ContextPtr:IsHidden() and not Controls.PantheonChooserSlideAnim:IsReversing(); end,
		onActivate = SRA_OnActivate,
		onClose = SRA_OnClose,
	};
	ContextPtr:SetInitHandler( OnInit );
	ContextPtr:SetShutdown( OnShutdown );
	ContextPtr:SetInputHandler( OnInputHandler, true );
end
Initialize();