-- Copyright 2017-2018, Firaxis Games

include("InstanceManager");
include("ScreenReader");		-- ScreenReaderAccess
include("SRListen");		-- ScreenReaderAccess
include("KeyNavList");		-- ScreenReaderAccess


-- ===========================================================================
--	CONSTANTS
-- ===========================================================================

local RELOAD_CACHE_ID:string = "DedicationPopup"; -- Must be unique (usually the same as the file name)

local HEROIC_AGE:number = 1;
local GOLDEN_AGE:number = 2;
local DARK_AGE:number = 3;
local NORMAL_AGE:number = 4;

-- ===========================================================================
--	VARIABLES
-- ===========================================================================

local m_CurrentAge:number = -1;
local m_PreviewEraIndex:number = -1;
local m_CurrentEraIndex:number = -1;
local m_SelectedCommemorationTypes:table = {};
local m_CommemorationInstanceManager:table = InstanceManager:new("Commemoration", "SelectCheck", Controls.CommemorationsStack);

-- ScreenReaderAccess
local SRA_ANNOUNCE_DELAY:number = 0.3;
local m_srAnnouncePending:boolean = false;
local m_srAnnounceDelay:number = 0;
local m_srAgeLine:string = "";			-- "Because you earned a Normal Age, you may make one Dedication."
local m_srOrder:table = {};				-- commemoration indexes in the order the popup lists them
local m_srInstances:table = {};			-- commemoration index -> instance (its SelectCheck is the game's own button)
local m_srInfo:table = {};				-- commemoration index -> { name, bonus (text for the current age), info (the GameInfo row) }
local m_srList:table = nil;

-- ===========================================================================
function OnGameEraChanged(prevEraIndex:number, newEraIndex:number)
	
	m_PreviewEraIndex = prevEraIndex;
	m_CurrentEraIndex = newEraIndex;
	local localPlayerID:number = Game.GetLocalPlayer();
	local gameEras:table = Game.GetEras();

	-- Ignore during first turn, or if playing as an observer
	if	localPlayerID == PlayerTypes.NONE or m_CurrentEraIndex == 0 or
		Game.GetCurrentGameTurn() == GameConfiguration.GetStartTurn() then
		return;
	end

	-- Determine the age type
	if (gameEras:HasHeroicGoldenAge(localPlayerID)) then
		m_CurrentAge = HEROIC_AGE;
	elseif (gameEras:HasGoldenAge(localPlayerID)) then
		m_CurrentAge = GOLDEN_AGE;
	elseif (gameEras:HasDarkAge(localPlayerID)) then
		m_CurrentAge = DARK_AGE;
	else
		m_CurrentAge = NORMAL_AGE;
	end

	if m_CurrentEraIndex > 0 then
		local currentEraName:string = GameInfo.Eras[m_CurrentEraIndex].Name;
		local historyManager:table= Game.GetHistoryManager();
		local commemorateChoices:table = gameEras:GetPlayerCommemorateChoices(localPlayerID);

		Controls.Title:SetText(Locale.ToUpper(Locale.Lookup("LOC_ERA_COMMEMORATION_POPUP_DEDICATION_SUBHEADER", Locale.Lookup(currentEraName))));

		m_CommemorationInstanceManager:ResetInstances();
		m_srOrder = {};			-- ScreenReaderAccess
		m_srInstances = {};
		m_srInfo = {};

		for _,commemorationType in ipairs(commemorateChoices) do
			CreateCommemoration(GameInfo.CommemorationTypes[commemorationType]);
		end

		local selectionsAllowed:number = gameEras:GetPlayerNumAllowedCommemorations(localPlayerID);

		if m_CommemorationInstanceManager.m_iAllocatedInstances > 0 and selectionsAllowed > 0 then
			ShowPopup();
			m_srAnnouncePending = true;		-- ScreenReaderAccess: spoken from the update loop once the popup is really shown
			m_srAnnounceDelay = SRA_ANNOUNCE_DELAY;
			m_SelectedCommemorationTypes = {};
			Controls.Confirm:SetDisabled(true);
			Controls.CommemorationsStack:CalculateSize();
			Controls.CommemorationsScroller:CalculateSize();
		else
			OnClose();
		end

		Controls.CommemorationsScroller:SetScrollValue(0);

		-- Update control styles
		if m_CurrentAge == HEROIC_AGE then
			Controls.AgeAchieved:SetText(Locale.ToUpper(Locale.Lookup("LOC_DEDICATION_POPUP_HEROIC_AGE_ACHIEVED")));
			m_srAgeLine = CleanTextForSpeech(Locale.Lookup("LOC_DEDICATION_POPUP_HEROIC_AGE_ACHIEVED"));		-- ScreenReaderAccess
			Controls.PopupBackground:SetTexture("Ages_ParchmentHeroic");
			Controls.PopupFrame:SetTexture("Ages_FrameHeroic");
			Controls.HeroicFrameGlow:SetHide(false);
		elseif m_CurrentAge == GOLDEN_AGE then
			Controls.AgeAchieved:SetText(Locale.ToUpper(Locale.Lookup("LOC_DEDICATION_POPUP_GOLDEN_AGE_ACHIEVED")));
			m_srAgeLine = CleanTextForSpeech(Locale.Lookup("LOC_DEDICATION_POPUP_GOLDEN_AGE_ACHIEVED"));		-- ScreenReaderAccess
			Controls.PopupBackground:SetTexture("Ages_ParchmentGolden");
			Controls.PopupFrame:SetTexture("Ages_FrameGolden");
			Controls.HeroicFrameGlow:SetHide(true);
		elseif m_CurrentAge == DARK_AGE then
			Controls.AgeAchieved:SetText(Locale.ToUpper(Locale.Lookup("LOC_DEDICATION_POPUP_DARK_AGE_ACHIEVED")));
			m_srAgeLine = CleanTextForSpeech(Locale.Lookup("LOC_DEDICATION_POPUP_DARK_AGE_ACHIEVED"));		-- ScreenReaderAccess
			Controls.PopupBackground:SetTexture("Ages_ParchmentDark");
			Controls.PopupFrame:SetTexture("Ages_FrameDark");
			Controls.HeroicFrameGlow:SetHide(true);
		else
			Controls.AgeAchieved:SetText(Locale.ToUpper(Locale.Lookup("LOC_DEDICATION_POPUP_NORMAL_AGE_ACHIEVED")));
			m_srAgeLine = CleanTextForSpeech(Locale.Lookup("LOC_DEDICATION_POPUP_NORMAL_AGE_ACHIEVED"));		-- ScreenReaderAccess
			Controls.PopupBackground:SetTexture("Ages_ParchmentNormal");
			Controls.PopupFrame:SetTexture("Ages_FrameNormal");
			Controls.HeroicFrameGlow:SetHide(true);
		end
	elseif m_CurrentEraIndex < 0 then
		UI.DataError("DedicationPopup has an invalid current era index: "..tostring(m_CurrentEraIndex));
		OnClose();
	end

	UpdateConfirmButton(0);
end

-- ===========================================================================
function CreateCommemoration(commemorationInfo:table)
	local instance:table = m_CommemorationInstanceManager:GetInstance();

	-- Commemoration Icon
	local iconName:string = "ICON_" .. commemorationInfo.CommemorationType;
	instance.CommemorationIcon:SetIcon(iconName);

	local categoryText:string = "";
	if (commemorationInfo ~= nil and commemorationInfo.CategoryDescription ~= nil) then
		categoryText = Locale.Lookup(commemorationInfo.CategoryDescription);
	end
	instance.MomentCategory:SetText(Locale.ToUpper(categoryText));
	local bonusText:string = "";
	local localPlayerID:number = Game.GetLocalPlayer();
	if (localPlayerID ~= PlayerTypes.NONE) then
		local gameEras:table = Game.GetEras();
		if (gameEras:HasGoldenAge(localPlayerID)) then
			if (commemorationInfo ~= nil and commemorationInfo.GoldenAgeBonusDescription ~= nil) then
				bonusText = Locale.Lookup(commemorationInfo.GoldenAgeBonusDescription);
				if (gameEras:IsPlayerAlwaysAllowedCommemorationQuest(localPlayerID) and commemorationInfo.NormalAgeBonusDescription ~= nil) then
					bonusText = bonusText .. "[NEWLINE]" .. Locale.Lookup(commemorationInfo.NormalAgeBonusDescription);
				end
			end
		elseif (gameEras:HasDarkAge(localPlayerID)) then
			if (commemorationInfo ~= nil and commemorationInfo.DarkAgeBonusDescription ~= nil) then
				bonusText = Locale.Lookup(commemorationInfo.DarkAgeBonusDescription);
			end
		else
			if (commemorationInfo ~= nil and commemorationInfo.NormalAgeBonusDescription ~= nil) then
				bonusText = Locale.Lookup(commemorationInfo.NormalAgeBonusDescription);
			end
		end
	end

	if m_CurrentAge == HEROIC_AGE then
		instance.SelectCheck:SetTexture("Ages_ButtonComHeroic");
	elseif m_CurrentAge == GOLDEN_AGE then
		instance.SelectCheck:SetTexture("Ages_ButtonComGolden");
	elseif m_CurrentAge == DARK_AGE then
		instance.SelectCheck:SetTexture("Ages_ButtonComDark");
	else
		instance.SelectCheck:SetTexture("Ages_ButtonComNormal");
	end

	SRA_Record(commemorationInfo, instance, bonusText);		-- ScreenReaderAccess
	instance.MomentBonuses:SetText(bonusText);
	instance.SelectCheck:SetSelected(false);
	instance.SelectCheck:RegisterCallback(Mouse.eLClick, function() OnCommemorationSelected(instance, commemorationInfo.Index) end);
end

-- ===========================================================================
function OnCommemorationSelected(selectedInstance:table, commemorationType:number)
	-- How many are we allowed to select?
	local selectionsAllowed:number = Game.GetEras():GetPlayerNumAllowedCommemorations(Game.GetLocalPlayer());
	local selectionsMade:number = 0;
	for _,instance in ipairs(m_CommemorationInstanceManager.m_AllocatedInstances) do
		if (instance.SelectCheck:IsSelected()) then
			selectionsMade = selectionsMade + 1;
		end
	end

	-- Have we already selected this one?
	local alreadySelected:boolean = false;
	for i,selectedCommemorationType in ipairs(m_SelectedCommemorationTypes) do
		if (selectedCommemorationType == commemorationType) then
			alreadySelected = true;
			selectedInstance.SelectCheck:SetSelected(false);
			table.remove(m_SelectedCommemorationTypes, i);
			selectionsMade = selectionsMade - 1;
		end
	end

	if (not alreadySelected) then
		if (selectionsMade >= selectionsAllowed) then
			-- At capacity, so first clear our old selections
			for _,instance in ipairs(m_CommemorationInstanceManager.m_AllocatedInstances) do
				instance.SelectCheck:SetSelected(false);
			end
			m_SelectedCommemorationTypes = {};
			selectionsMade = 0;
		end
		-- Make our new selection
		selectedInstance.SelectCheck:SetSelected(true);	
		table.insert(m_SelectedCommemorationTypes, commemorationType);
		selectionsMade = selectionsMade + 1;
	end

	UpdateConfirmButton(selectionsMade);
end

-- ===========================================================================
function UpdateConfirmButton(currentlySelected:number)
	local selectionsAllowed:number = Game.GetEras():GetPlayerNumAllowedCommemorations(Game.GetLocalPlayer());
	Controls.Confirm:SetDisabled(currentlySelected ~= selectionsAllowed);
end

-- ===========================================================================
function OnConfirm()
    UI.PlaySound("Confirm_Dedication");

    OnClose();

	for i,selectedCommemorationType in ipairs(m_SelectedCommemorationTypes) do
		local kParameters:table = {};
		kParameters[PlayerOperations.PARAM_COMMEMORATION_TYPE] = selectedCommemorationType;
		UI.RequestPlayerOperation(Game.GetLocalPlayer(), PlayerOperations.COMMEMORATE, kParameters);
	end

end

-- ===========================================================================
--	ScreenReaderAccess
-- ===========================================================================
function SRA_Record(commemorationInfo:table, instance:table, bonusText:string)
	local index:number = commemorationInfo.Index;
	local name:string = "";
	if commemorationInfo.CategoryDescription ~= nil then name = Locale.Lookup(commemorationInfo.CategoryDescription); end
	m_srInstances[index] = instance;
	m_srInfo[index] = { name = name, bonus = bonusText, info = commemorationInfo };
	table.insert(m_srOrder, index);
end

-- A bonus text without its "Reform the Coinage Dedication Bonus:" style header lines.
function SRA_StripHeaders(text:string)
	local parts:table = {};
	for segment in string.gmatch((text or "") .. "[NEWLINE]", "(.-)%[NEWLINE%]") do
		local clean:string = CleanTextForSpeech(segment);
		if clean ~= "" and string.sub(clean, -1) ~= ":" then
			table.insert(parts, (string.gsub(clean, "[%.%s]+$", "")));
		end
	end
	if #parts == 0 then return ""; end
	return table.concat(parts, ". ") .. ".";
end

function SRA_Allowed()
	return Game.GetEras():GetPlayerNumAllowedCommemorations(Game.GetLocalPlayer());
end

-- How many are selected now and their names, read from the game's own buttons.
function SRA_SelectedState()
	local names:table = {};
	for _, index in ipairs(m_srOrder) do
		if m_srInstances[index].SelectCheck:IsSelected() then table.insert(names, m_srInfo[index].name); end
	end
	return #names, names;
end

function SRA_Variant(info:table, field:string)
	if info[field] == nil then return ""; end
	return SRA_StripHeaders(Locale.Lookup(info[field]));
end

-- Space: every age variant of the bonus
function SRA_Detail(index:number)
	local data:table = m_srInfo[index];
	if data == nil then return ""; end
	local normal:string = SRA_Variant(data.info, "NormalAgeBonusDescription");
	local golden:string = SRA_Variant(data.info, "GoldenAgeBonusDescription");
	local dark:string = SRA_Variant(data.info, "DarkAgeBonusDescription");
	local parts:table = { data.name .. ". Now: " .. SRA_StripHeaders(data.bonus) };
	if normal == dark then
		table.insert(parts, "In a normal or dark age: " .. normal);
	else
		table.insert(parts, "In a normal age: " .. normal);
		table.insert(parts, "In a dark age: " .. dark);
	end
	table.insert(parts, "In a golden age: " .. golden);
	return table.concat(parts, " ");
end

function SRA_BuildItems()
	local items:table = {};
	for _, index in ipairs(m_srOrder) do
		local data:table = m_srInfo[index];
		local selected:boolean = m_srInstances[index].SelectCheck:IsSelected();
		local short:string = SRA_StripHeaders(data.bonus);
		local text:string = data.name;
		if short ~= "" then text = text .. ", " .. string.gsub(short, "[%.%s]+$", ""); end
		table.insert(items, {
			key = index,
			text = text .. ", " .. (selected and "selected" or "not selected"),
			detail = function() return SRA_Detail(index); end,
		});
	end
	local count:number = SRA_SelectedState();
	local missing:number = SRA_Allowed() - count;
	table.insert(items, {
		key = "confirm",
		text = (missing == 0) and "Confirm" or ("Confirm, choose " .. missing .. " more first"),
		detail = (missing == 0) and "Confirm the chosen dedications" or ("Not available yet: choose " .. missing .. " more dedication" .. (missing == 1 and "" or "s")),
	});
	return items;
end

function SRA_Announce()
	m_srList.Reset();
	m_srList.Open("Dedications", nil, true);		-- silent: only puts the focus on the first item
	local items:table = SRA_BuildItems();
	if #items == 0 then return; end
	local allowed:number = SRA_Allowed();
	local text:string = "Choose dedications: " .. allowed .. " to choose.";
	if m_srAgeLine ~= "" then text = text .. " " .. string.gsub(m_srAgeLine, "[%.%s]+$", "") .. "."; end
	OutputMessageToScreenReader(text .. " " .. items[1].text .. ", 1 of " .. #items);
end

function SRA_OnUpdate(deltaTime:number)
	if m_srAnnouncePending and not ContextPtr:IsHidden() then
		m_srAnnounceDelay = m_srAnnounceDelay - deltaTime;
		if m_srAnnounceDelay > 0 then return; end
		m_srAnnouncePending = false;
		local ok:boolean, err = xpcall(SRA_Announce, KeyNavErrorHandler);
		if not ok then print("Dedication announce error: " .. tostring(err)); end
	end
end

function SRA_Confirm()
	local count:number, names:table = SRA_SelectedState();
	local missing:number = SRA_Allowed() - count;
	if missing > 0 then
		OutputMessageToScreenReader("Choose " .. missing .. " more first");
		return;
	end
	OutputMessageToScreenReader("Dedication chosen: " .. table.concat(names, ", "));
	OnConfirm();
end

function SRA_Activate(item:table)
	if item.key == "confirm" then
		SRA_Confirm();
		return;
	end
	local index:number = item.key;
	local instance:table = m_srInstances[index];
	local name:string = m_srInfo[index].name;
	local allowed:number = SRA_Allowed();
	local before:number, names:table = SRA_SelectedState();
	local wasSelected:boolean = instance.SelectCheck:IsSelected();
	local replaced:string = nil;
	if not wasSelected and before >= allowed then
		if allowed > 1 then
			-- the game would clear every selection and keep only this one: say so instead
			OutputMessageToScreenReader("Already " .. before .. " chosen; deselect one first");
			return;
		end
		replaced = names[1];		-- with a single dedication the game switches the choice
	end
	OnCommemorationSelected(instance, index);
	local nowSelected:boolean = instance.SelectCheck:IsSelected();
	if nowSelected == wasSelected then
		OutputMessageToScreenReader("Already " .. before .. " chosen; deselect one first");
		return;
	end
	local count:number = SRA_SelectedState();
	local left:number = allowed - count;
	if nowSelected then
		local text:string = "Selected " .. name;
		if replaced ~= nil then text = text .. " instead of " .. replaced; end
		text = text .. ". " .. left .. " left to choose";
		if left == 0 then text = text .. ". Press C to confirm"; end
		OutputMessageToScreenReader(text);
	else
		OutputMessageToScreenReader("Deselected " .. name .. ". " .. left .. " left to choose");
	end
end

function SRA_Close()
	OnClose();
	OutputMessageToScreenReader("Closed, dedication not chosen. Make Dedication still blocks the turn.");
end

-- ===========================================================================
function ShowPopup()
	UIManager:QueuePopup(ContextPtr, PopupPriority.MediumHigh);
end

-- ===========================================================================
function OnClose()
	UIManager:DequeuePopup(ContextPtr);
end

-- ===========================================================================
--	UI Event
-- ===========================================================================
function OnInit( isReload:boolean )
	if isReload then		
		LuaEvents.GameDebug_GetValues( RELOAD_CACHE_ID );	
	end
end

-- ===========================================================================
--	UI EVENT
-- ===========================================================================
function OnShutdown()
	SRUnlistenAll();		-- ScreenReaderAccess: hot reload leaves the old instance's listeners registered
	LuaEvents.GameDebug_AddValue(RELOAD_CACHE_ID, "isVisible", not ContextPtr:IsHidden());
	LuaEvents.GameDebug_AddValue(RELOAD_CACHE_ID, "m_PreviewEraIndex", m_PreviewEraIndex);
	LuaEvents.GameDebug_AddValue(RELOAD_CACHE_ID, "m_CurrentEraIndex", m_CurrentEraIndex);
end

-- ===========================================================================
--	LUA EVENT
--	Reload support
-- ===========================================================================
function OnGameDebugReturn(context:string, contextTable:table)
	if context == RELOAD_CACHE_ID then
		if contextTable["isVisible"] ~= nil then			
			ContextPtr:SetHide(not contextTable["isVisible"]);
		end

		m_PreviewEraIndex = contextTable["m_PreviewEraIndex"];
		m_CurrentEraIndex = contextTable["m_CurrentEraIndex"];

		if m_CurrentEraIndex >= 0 then
			OnGameEraChanged(m_PreviewEraIndex, m_CurrentEraIndex);
		end
	end
end

-- ===========================================================================
--	Input
--	UI Event Handler
-- ===========================================================================
function OnInputHandler( pInputStruct:table )
	-- ScreenReaderAccess: the list handles Up/Down/Home/End/Enter/Space/Escape/C; every other key is swallowed
	if m_srList ~= nil and not ContextPtr:IsHidden() then m_srList.HandleInput( pInputStruct ); end
	-- Intercept all input while on this screen (is modal)
	return true;
end

-- ===========================================================================
function Initialize()
	ContextPtr:SetHide(true); -- PRODUCTION
	ContextPtr:SetInitHandler( OnInit );
	ContextPtr:SetShutdown( OnShutdown );
	ContextPtr:SetInputHandler( OnInputHandler, true );
	ContextPtr:SetUpdate( SRA_OnUpdate );		-- ScreenReaderAccess
	m_srList = KeyNavList_Create{
		build = SRA_BuildItems,
		isActive = function() return not ContextPtr:IsHidden(); end,
		onActivate = SRA_Activate,
		onClose = SRA_Close,
		extraKeys = { [Keys.C] = SRA_Confirm },
	};

	Controls.CloseButton:RegisterCallback(Mouse.eLClick, OnClose);
	Controls.Confirm:RegisterCallback(Mouse.eLClick, OnConfirm);

	-- Lua Events
	SRListen(LuaEvents.GameDebug_Return, OnGameDebugReturn);		-- ScreenReaderAccess
	SRListen(LuaEvents.EraReviewPopup_MakeDedication, OnGameEraChanged);
end
Initialize();