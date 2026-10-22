-- Copyright 2017-2019, Firaxis Games

include("Civ6Common");
include("InstanceManager");
include("ScreenReader");	-- ScreenReaderAccess
include("KeyNavList");		-- ScreenReaderAccess
include("PromotionText");	-- ScreenReaderAccess
include("SRListen");		-- ScreenReaderAccess
	
-- ===========================================================================
--	CONSTANTS
-- ===========================================================================
local SIZE_NODE_X				:number = 150;				-- Item node dimensions
local SIZE_NODE_Y				:number = 146;
local SIZE_NODE_X_HALF			:number = SIZE_NODE_X/2;	-- Item node dimensions
local SIZE_NODE_Y_HALF			:number = SIZE_NODE_Y/2;
local SIZE_PATH					:number = 40;
local SIZE_PATH_HALF			:number = 20;
local SIZE_ROW_Y				:number = 106;
local SIZE_COLUMN_X				:number = 212;
local LINE_BEFORE_CURVE			:number = 20;		-- MIN-MAX 40-(SIZE_NODE_Y/3)

local MAX_WIDTH					:number = 1024;
local MAX_HEIGHT				:number = 768;

local WIDTH_PADDING				:number = 50;
local HEIGHT_PADDING			:number = 120;

-- ===========================================================================
--	MEMBERS
-- ===========================================================================
local m_PromotionListInstanceMgr			:table	= InstanceManager:new( "PromotionSelectionInstance",			"PromotionSelection",	Controls.PromotionContainer );
local m_CompletedPromotionListInstanceMgr	:table	= InstanceManager:new( "CompletedPromotionSelectionInstance",	"PromotionSelection",	Controls.PromotionContainer );
local m_kLineIM		:table	= InstanceManager:new( "LineImageInstance", 					"LineImage",			Controls.PromotionContainer );
local m_uiNodes		:table	= {};

-- ===========================================================================
--	FUNCTIONS
-- ===========================================================================

-- ===========================================================================
--	Closes the immediate popup, will raise more if queued.
-- ===========================================================================
function Close()
	if UIManager:IsInPopupQueue(ContextPtr) then
		UIManager:DequeuePopup( ContextPtr );
	end
end

-- ===========================================================================
--	UI Callback
-- ===========================================================================
function OnClose()
	Close();
end

-- ===========================================================================
function OnLocalPlayerTurnEnd()
	if(GameConfiguration.IsHotseat()) then
		Close();
	end
end

-- ===========================================================================
function OnPromoteUnit(ePromotion, unitID)
	if Game.GetLocalPlayer() == -1 then
		return;
	end

	local pLocalPlayer:table = Players[Game.GetLocalPlayer()];
	if pLocalPlayer then
		local pUnit:table = pLocalPlayer:GetUnits():FindID(unitID);
		if (pUnit ~= nil) then
			local tParameters = {};
			tParameters[UnitCommandTypes.PARAM_PROMOTION_TYPE] = ePromotion;
			UnitManager.RequestCommand( pUnit, UnitCommandTypes.PROMOTE, tParameters );
		end
	end
end

-- ===========================================================================
function OnPromoteUnitPopup()
	local pUnit:table	= UI.GetHeadSelectedUnit();

	local bCanStart, tResults = UnitManager.CanStartCommand( pUnit, UnitCommandTypes.PROMOTE, true, true);
	local tPromotions		= tResults[UnitCommandResults.PROMOTIONS];

	local unitExperience = pUnit:GetExperience();
	local currentPromotionList :table = unitExperience:GetPromotions();
	local promotionClass = GameInfo.Units[pUnit:GetUnitType()].PromotionClass;

	local strengthString:string = "";
	local experienceString:string = "";
	if pUnit:GetCombat() > 0 then
		strengthString = strengthString .. "[ICON_Strength]" ..pUnit:GetCombat()
	end
	if pUnit:GetRangedCombat() > 0 then
		strengthString = strengthString .. "[ICON_Ranged]" ..pUnit:GetRangedCombat()
	end
	if pUnit:GetBombardCombat() > 0 then
		strengthString = strengthString .. "[ICON_Bombard]" ..pUnit:GetBombardCombat()
	end
	if pUnit:GetAntiAirCombat() > 0 then
		strengthString = strengthString .. "[ICON_AntiAir_Large]" ..pUnit:GetAntiAirCombat()
	end
	if pUnit:GetReligiousStrength() > 0 then
		strengthString = strengthString .. "[ICON_Religion]" ..pUnit:GetReligiousStrength()
	end
	if pUnit:GetMaxMoves() > 0 then
		strengthString = strengthString .. "[ICON_Movement]" ..pUnit:GetMaxMoves()
	end

	experienceString = Locale.Lookup("LOC_HUD_UNIT_PANEL_XP") .. " " .. unitExperience:GetExperiencePoints();

	Controls.StrMoveLabel:SetText(Locale.Lookup(strengthString));
	Controls.ExperienceLabel:SetText(Locale.Lookup(experienceString));

	m_PromotionListInstanceMgr:ResetInstances();
	m_CompletedPromotionListInstanceMgr:ResetInstances();
	m_kLineIM:ResetInstances();
	m_uiNodes = {};
	local hasPromotion:boolean;

	for row in GameInfo.UnitPromotions() do

		if row.PromotionClass == promotionClass then
			m_uiNodes[row.UnitPromotionType] = row;
		end
	end

	local numUnlocks = 0;
	for _, i in pairs(m_uiNodes) do
		for row in GameInfo.UnitPromotionPrereqs() do
			hasPromotion = false;
			numUnlocks = 0
			
			if row.PrereqUnitPromotion == i.UnitPromotionType then
				local previousRow	:number = i.Level;
				local previousColumn:number = i.Column;
				local currentRow:number = m_uiNodes[row.UnitPromotion].Level;
				local currentColumn:number = m_uiNodes[row.UnitPromotion].Column;
			
				for _, promotion in pairs(currentPromotionList) do
					if row.UnitPromotion == GameInfo.UnitPromotions[promotion].UnitPromotionType or i.UnitPromotionType == GameInfo.UnitPromotions[promotion].UnitPromotionType then
						numUnlocks = numUnlocks+1;
					end
				end
				hasPromotion = numUnlocks >= 2;

				if (currentColumn > previousColumn or currentColumn < previousColumn) and  (currentRow > previousRow or currentRow < previousRow) then
					local inst	:table = m_kLineIM:GetInstance();
					local line1	:table = inst.LineImage;
					inst = m_kLineIM:GetInstance();
					local line2:table = inst.LineImage;
					inst = m_kLineIM:GetInstance();
					local line3:table = inst.LineImage;
					inst = m_kLineIM:GetInstance();
					local line4:table = inst.LineImage;
					inst = m_kLineIM:GetInstance();
					local line5:table = inst.LineImage;

					local PrereqX = currentColumn*SIZE_NODE_X - SIZE_NODE_X_HALF;
					local MyX = previousColumn*SIZE_NODE_X - SIZE_NODE_X_HALF;
					local PrereqY = (math.min(previousRow,currentRow)-1)*SIZE_NODE_Y + SIZE_ROW_Y;
					local MyY = (math.max(previousRow,currentRow)-1)*SIZE_NODE_Y;
					local CurveY = PrereqY + LINE_BEFORE_CURVE;

					line1:SetOffsetVal(MyX, PrereqY);
					line1:SetSizeVal(SIZE_PATH, CurveY - PrereqY-SIZE_PATH_HALF);

					line2:SetOffsetVal(MyX, CurveY-SIZE_PATH_HALF);
					line2:SetSizeVal(SIZE_PATH, SIZE_PATH);

					line3:SetOffsetVal(math.min(PrereqX, MyX)+SIZE_PATH, CurveY-SIZE_PATH_HALF);
					line3:SetSizeVal(math.abs(PrereqX - MyX)-SIZE_PATH, SIZE_PATH);

					line4:SetOffsetVal(PrereqX, CurveY-SIZE_PATH_HALF);
					line4:SetSizeVal(SIZE_PATH, SIZE_PATH);

					line5:SetOffsetVal(PrereqX, CurveY + SIZE_PATH_HALF);
					line5:SetSizeVal(SIZE_PATH, MyY - CurveY - SIZE_PATH_HALF);
					
					if hasPromotion then
						line1:SetTexture("Controls_TreePathNS");
						line3:SetTexture("Controls_TreePathEW");
						line5:SetTexture("Controls_TreePathNS");

						if( PrereqX < MyX) then
							line2:SetTexture("Controls_TreePathEN");
							line4:SetTexture("Controls_TreePathNE");
						else
							line2:SetTexture("Controls_TreePathSE");
							line4:SetTexture("Controls_TreePathES");
						end

						line1:SetColor(UI.GetColorValueFromHexLiteral(0xFF71A2BF));
						line2:SetColor(UI.GetColorValueFromHexLiteral(0xFF71A2BF));
						line3:SetColor(UI.GetColorValueFromHexLiteral(0xFF71A2BF));
						line4:SetColor(UI.GetColorValueFromHexLiteral(0xFF71A2BF));
						line5:SetColor(UI.GetColorValueFromHexLiteral(0xFF71A2BF));
					else
						line1:SetTexture("Controls_TreePathDashNS");
						line3:SetTexture("Controls_TreePathDashEW");
						line5:SetTexture("Controls_TreePathDashNS");

						if( PrereqX < MyX) then
							line2:SetTexture("Controls_TreePathDashEN");
							line4:SetTexture("Controls_TreePathDashNE");
						else
							line2:SetTexture("Controls_TreePathDashSE");
							line4:SetTexture("Controls_TreePathDashES");
						end

						--line1:SetColor(63,83,100,255);
						--line2:SetColor(63,83,100,255);
						--line3:SetColor(63,83,100,255);
						--line4:SetColor(63,83,100,255);
						--line5:SetColor(63,83,100,255);
					end
				else
					local inst:table = m_kLineIM:GetInstance();
					local line:table = inst.LineImage;
					if(currentColumn > previousColumn or currentColumn < previousColumn) then
						local startX:number= (math.min(previousColumn,currentColumn))*SIZE_NODE_X;
						local endX :number = (math.max(previousColumn,currentColumn)-1)*SIZE_NODE_X;
						local yVal:number = (currentRow-1)*SIZE_NODE_Y + SIZE_NODE_Y_HALF;
						
						line:SetOffsetVal(startX, yVal);				
						line:SetSizeVal( endX - startX, SIZE_PATH);
						if hasPromotion then
							line:SetTexture("Controls_TreePathEW");
							line:SetColor(UI.GetColorValueFromHexLiteral(0xFF71A2BF));
						else
							line:SetTexture("Controls_TreePathDashEW");
							--line:SetColor(63,83,100,255);
						end
					else
						local startY:number= (math.min(previousRow,currentRow)-1)*SIZE_NODE_Y + SIZE_ROW_Y;
						local endY :number = (math.max(previousRow,currentRow)-1)*SIZE_NODE_Y;
						local XVal:number = currentColumn*SIZE_NODE_X - SIZE_NODE_X_HALF;
						
						line:SetOffsetVal(XVal, startY);				
						line:SetSizeVal(SIZE_PATH,  endY - startY);
						if hasPromotion then
							line:SetTexture("Controls_TreePathNS");
							line:SetColor(UI.GetColorValueFromHexLiteral(0xFF71A2BF));
						else
							line:SetTexture("Controls_TreePathDashNS");
							--line:SetColor(63,83,100,255);
						end
					end
				end
			end
		end
	end

	for row in GameInfo.UnitPromotions() do
		hasPromotion = false;
		for i, promotion in pairs(currentPromotionList) do
			if row == GameInfo.UnitPromotions[promotion] then
				hasPromotion = true;
			end
		end

		if row.PromotionClass == promotionClass then
			local promotionInstance;
			local promotionDefinition = row;
			m_uiNodes[row.UnitPromotionType] = row;
			
			if hasPromotion then
				promotionInstance = m_CompletedPromotionListInstanceMgr:GetInstance();
			else
				promotionInstance = m_PromotionListInstanceMgr:GetInstance();
			end

			promotionInstance.PromotionSelection:SetOffsetVal((row.Column-1)*SIZE_NODE_X, (row.Level-1)*SIZE_NODE_Y);
			if (promotionDefinition ~= nil) then
				promotionInstance.PromotionName:SetText(Locale.ToUpper(promotionDefinition.Name));
				promotionInstance.PromotionDescription:SetText(Locale.Lookup(promotionDefinition.Description));
				local iconName = "ICON_" .. promotionDefinition.UnitPromotionType;
				local textureOffsetX, textureOffsetY, textureSheet = IconManager:FindIconAtlas(iconName,32);
				if (textureOffsetX ~= nil) then
					promotionInstance.PromotionIcon:SetTexture( textureOffsetX, textureOffsetY, textureSheet );
				end
			end

			local bAvailable:boolean = false;
			-- are they available to be clicked?
			for i, item in pairs(tPromotions) do
				if(item == row.Index) then
					bAvailable = true;
					local ePromotion = item;
					promotionInstance.PromotionSlot:RegisterCallback( Mouse.eLClick, OnPromoteUnit );
					promotionInstance.PromotionSlot:SetVoid1( ePromotion );
					promotionInstance.PromotionSlot:SetVoid2( pUnit:GetID() );
				end
			end

			if bAvailable then
				promotionInstance.PromotionSlot:SetDisabled(false);
			else
				promotionInstance.PromotionSlot:SetDisabled(true);
			end
		end
	end

	Controls.PromotionScrollPanel:CalculateSize();
	UIManager:QueuePopup(ContextPtr, PopupPriority.Low)
	SRA_Announce();		-- ScreenReaderAccess
end

-- ===========================================================================
function OnPromotionContainerSizeChanged()
	local desiredWidth:number = Controls.PromotionContainer:GetSizeX() + WIDTH_PADDING;
	if desiredWidth > MAX_WIDTH then
		desiredWidth = MAX_WIDTH;
	end

	local desiredHeight:number = Controls.PromotionContainer:GetSizeY() + HEIGHT_PADDING;
	if desiredHeight > MAX_HEIGHT then
		desiredHeight = MAX_HEIGHT;
		UI.DataError("Unit promotion tree height exceeds maximum panel height.");
	end

	Controls.PopupFrameGrid:SetSizeX(desiredWidth);
	Controls.PopupFrameGrid:SetSizeY(desiredHeight);
end

-- ===========================================================================
-- ===========================================================================
--	ScreenReaderAccess: keyboard navigation and speech
--	The promotions of the unit's class as a list (tier, then column): Up/Down/Home/End, Space = full text, Enter = take
--	the promotion (what clicking its slot does: OnPromoteUnit), Escape = Close. Every other key is swallowed while shown.
-- ===========================================================================
local m_srList			:table = nil;
local m_srPendingName	:string = nil;		-- promotion requested, the result is spoken from Events.UnitPromoted
local m_srPendingUnit	:number = nil;
local m_srPendingTime	:number = 0;

local function SRA_Clean( text:string )
	return CleanTextForSpeech( Locale.Lookup( text or "" ) );
end

local function SRA_Items()
	local items:table = {};
	local unit:table = UI.GetHeadSelectedUnit();
	if unit == nil then return items; end
	local bCanStart:boolean, tResults:table = UnitManager.CanStartCommand( unit, UnitCommandTypes.PROMOTE, true, true );
	local available:table = {};
	if tResults ~= nil and tResults[UnitCommandResults.PROMOTIONS] ~= nil then
		for _, index in ipairs( tResults[UnitCommandResults.PROMOTIONS] ) do available[ index ] = true; end
	end
	local have:table = {};
	for _, index in pairs( unit:GetExperience():GetPromotions() ) do have[ index ] = true; end
	local promotionClass = GameInfo.Units[ unit:GetUnitType() ].PromotionClass;
	local rows:table = {};
	for row in GameInfo.UnitPromotions() do
		if row.PromotionClass == promotionClass then table.insert( rows, row ); end
	end
	table.sort( rows, function( a, b )
		if a.Level ~= b.Level then return a.Level < b.Level; end
		return a.Column < b.Column;
	end );
	for _, row in ipairs( rows ) do
		local p:table = { name = SRA_Clean( row.Name ), desc = SRA_Clean( row.Description ), tier = row.Level, needs = {} };
		local prereqs:table = {};
		local prereqMet:boolean = false;
		for prereq in GameInfo.UnitPromotionPrereqs() do
			if prereq.UnitPromotion == row.UnitPromotionType then
				local prereqRow:table = GameInfo.UnitPromotions[ prereq.PrereqUnitPromotion ];
				if prereqRow ~= nil then
					table.insert( prereqs, SRA_Clean( prereqRow.Name ) );
					if have[ prereqRow.Index ] then prereqMet = true; end
				end
			end
		end
		if have[ row.Index ] then
			p.state = "have";
		elseif available[ row.Index ] then
			p.state = "available";
		elseif #prereqs > 0 and not prereqMet then
			p.state = "locked";
			p.needs = prereqs;
		else
			p.state = "unavailable";
		end
		table.insert( items, { key = row.Index, text = PromotionText_Item( p ), detail = PromotionText_Detail( p ),
			choosable = ( p.state == "available" ), reason = PromotionText_Reason( p ), p = p, name = p.name } );
	end
	return items;
end

local function SRA_OnActivate( item:table )
	local unit:table = UI.GetHeadSelectedUnit();
	if unit == nil then return; end
	m_srPendingName = item.name;
	m_srPendingUnit = unit:GetID();
	m_srPendingTime = 0;
	OnPromoteUnit( item.key, unit:GetID() );		-- what a click on the promotion slot does
end

local function SRA_OnEscape()
	Close();
	OutputMessageToScreenReader( "Closed" );
end

-- "Promote Swordsman: 2 available. Battlecry: +7 combat strength vs melee, tier 1, available, 1 of 5"
function SRA_Announce()
	m_srPendingName = nil;
	if m_srList == nil then return; end
	local unit:table = UI.GetHeadSelectedUnit();
	if unit == nil then return; end
	local items:table = SRA_Items();
	local count:number = 0;
	local first:number = 1;
	for i, item in ipairs( items ) do
		if item.choosable then
			count = count + 1;
			if count == 1 then first = i; end
		end
	end
	m_srList.Reset();
	m_srList.Open( "", items[ first ] ~= nil and items[ first ].key or nil, true );
	local unitName:string = SRA_Clean( GameInfo.Units[ unit:GetUnitType() ].Name );
	OutputMessageToScreenReader( PromotionText_Opening( unitName, count, items[ first ] ~= nil and items[ first ].text or nil, first, #items ), true );
end

function SRA_OnUnitPromoted( playerID:number, unitID:number )
	if m_srPendingName == nil or playerID ~= Game.GetLocalPlayer() then return; end
	if m_srPendingUnit ~= nil and unitID ~= m_srPendingUnit then return; end
	OutputMessageToScreenReader( PromotionText_Done( m_srPendingName ) );
	m_srPendingName = nil;
	Close();
end

-- The request had no effect: say so instead of staying silent.
function SRA_OnUpdate( deltaTime:number )
	if m_srPendingName == nil then return; end
	m_srPendingTime = m_srPendingTime + deltaTime;
	if m_srPendingTime > 2 then
		OutputMessageToScreenReader( "Promotion failed: " .. m_srPendingName );
		m_srPendingName = nil;
	end
end

function SRA_HandleInput( pInputStruct:table )
	if ContextPtr:IsHidden() then return false; end
	if m_srList ~= nil and m_srList.HandleInput( pInputStruct ) then return true; end
	local msg:number = pInputStruct:GetMessageType();
	return msg == KeyEvents.KeyDown or msg == KeyEvents.KeyUp;
end
-- End ScreenReaderAccess

function OnInputHandler( pInputStruct:table )
	if SRA_HandleInput( pInputStruct ) then return true; end		-- ScreenReaderAccess
	local uiMsg = pInputStruct:GetMessageType();
	if uiMsg == KeyEvents.KeyUp then
		if pInputStruct:GetKey() == Keys.VK_ESCAPE then
			OnClose();
			return true;
		end
	end
	return false;
end

-- ===========================================================================
function OnCitySelectionChanged( ownerPlayerID:number, cityID:number, i:number, j:number, k:number, isSelected:boolean, isEditable:boolean)
	OnClose();
end

-- ===========================================================================
function OnShutdown()
	SRUnlistenAll();		-- ScreenReaderAccess
	Events.CitySelectionChanged.Remove( OnCitySelectionChanged );

	LuaEvents.UnitPanel_PromoteUnit.Remove(OnPromoteUnitPopup);
	LuaEvents.UnitPanel_HideUnitPromotion.Remove(OnClose);
end

-- ===========================================================================
function OnInit( isReload:boolean )
	LateInitialize();

	if isReload then
		local pSelectedUnit:table = UI.GetHeadSelectedUnit();
		if pSelectedUnit then
			OnPromoteUnitPopup();
		end
	end
end

-- ===========================================================================
function LateInitialize()
	Controls.CloseButton:RegisterCallback( Mouse.eLClick, OnClose );
	Controls.PromotionContainer:RegisterSizeChanged( OnPromotionContainerSizeChanged );

	Events.CitySelectionChanged.Add( OnCitySelectionChanged );
	SRListen( Events.UnitPromoted, SRA_OnUnitPromoted );		-- ScreenReaderAccess

	LuaEvents.UnitPanel_PromoteUnit.Add(OnPromoteUnitPopup);
	LuaEvents.UnitPanel_HideUnitPromotion.Add(OnClose);
end

-- ===========================================================================
function Initialize()
	ContextPtr:SetInitHandler( OnInit );
	ContextPtr:SetShutdown( OnShutdown );
	ContextPtr:SetInputHandler( OnInputHandler, true );
	-- ScreenReaderAccess
	print( "UnitPromotionPopup: ScreenReaderAccess copy loaded" );
	ContextPtr:SetUpdate( SRA_OnUpdate );
	m_srList = KeyNavList_Create{
		build = SRA_Items,
		isActive = function() return not ContextPtr:IsHidden(); end,
		onActivate = SRA_OnActivate,
		onClose = SRA_OnEscape,
	};
end
Initialize();
