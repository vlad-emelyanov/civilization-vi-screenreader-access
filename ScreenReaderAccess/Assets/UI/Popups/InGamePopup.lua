--[[
-- Last modifed by Samuel Batista on Jun 28 2017
-- Original Author: Samuel Batista
-- Copyright (c) Firaxis Games
--]]

include("PopupDialog");
local m_PopupDialog:table;

-- ===========================================================================
-- PopupDialog functionality
-- ===========================================================================
function OnPopupOpen( uniqueStringName:string, options:table )

	-- If no options were passed in, fill with generic options.
	if options == nil or #options == 0 then
		options = {};
		options[1] = { Type="Text",	Content=TXT_ARE_YOU_SURE};
		options[2] = { Type="Button", Content=TXT_ACCEPT, CommandString=PopupDialog.COMMAND_CONFIRM };
		options[3] = { Type="Button", Content=TXT_CANCEL, CommandString=PopupDialog.COMMAND_CANCEL };
		UI.DataError("Using generic popup because no options were passed in.");
	end

	m_PopupDialog:Reset();
	
	for _, option in ipairs(options) do
		local optionType:string = option.Type;
		if optionType ~= nil then
			if		optionType == "Text"	then m_PopupDialog:AddText( option.Content );
			elseif	optionType == "Button"	then
				-- Make sure to call OnClosePopup so DequeuePopup gets called
				local closeAndCallback:ifunction = function() OnClosePopup(); if option.Callback then option.Callback(); end end
				m_PopupDialog:AddButton( option.Content, closeAndCallback, option.CommandString );
			elseif	optionType == "Count"	then m_PopupDialog:AddCountDown( option.Content, option.Callback );
			elseif	optionType == "Title"	then m_PopupDialog:AddTitle(option.Content);
			else
				UI.DataError("Unhandled type '"..optionType.."' for '"..uniqueStringName.."'");
			end
		else
			UI.DataError( "An option was passed to PopupGeneric without a Type specified for '"..uniqueStringName.."'" );
		end
	end
	
	UIManager:PushModal(ContextPtr);
	m_PopupDialog:Open();
	-- ScreenReaderAccess mod change: an advisor that is up keeps the tutorial input mode on, which swallows every key
	-- (this popup never sees them and they act on the map); AdvisorPopup lets go of it while this popup is open
	LuaEvents.SRA_InGamePopupShown( true );
end

function OnClosePopup()
	UIManager:PopModal(ContextPtr);
	LuaEvents.SRA_InGamePopupShown( false );		-- ScreenReaderAccess mod change
	if m_PopupDialog:IsOpen() then
		m_PopupDialog:Close();
	end
end

-- ScreenReaderAccess mod change
function SRA_FocusedCancel()
	local active:table = m_PopupDialog.KeyNavElements[ m_PopupDialog.ActiveKeyNavElement + 1 ];
	return active ~= nil and active.Command == PopupDialog.COMMAND_CANCEL;
end

-- ===========================================================================
-- ESC handler
-- ===========================================================================
-- ScreenReaderAccess mod change: the key handling is a function so another popup that sits above (WorldCongressIntro) can pass Enter/Escape on
function SRA_HandleKeyUp( wParam:number )
	local single:boolean = #m_PopupDialog.KeyNavElements == 1;		-- a notice with one OK button: say that it closed
	SRA_HandleKeyUpInner( wParam );
	if single and (wParam == Keys.VK_ESCAPE or wParam == Keys.VK_RETURN) and not m_PopupDialog:IsOpen() then
		OutputMessageToScreenReader( "Closed" );
	end
end

function SRA_HandleKeyUpInner( wParam:number )
	if wParam == Keys.VK_ESCAPE then -- Try CANCEL. Then DEFAULT. Then give up and close window.
		if ( not m_PopupDialog:ActivateCommand( PopupDialog.COMMAND_CANCEL ) ) then
			if ( not m_PopupDialog:ActivateCommand( PopupDialog.COMMAND_DEFAULT ) ) then
				OnClosePopup();
			end
		end
	-- ScreenReaderAccess mod change: Up/Down move between the buttons (spoken); Enter on the focused Cancel button
	-- (a Yes/No question starts on No) activates it instead of always confirming
	elseif wParam == Keys.VK_UP or wParam == Keys.VK_DOWN then
		m_PopupDialog:KeyHandler( wParam );
	elseif wParam == Keys.VK_RETURN and SRA_FocusedCancel() then
		m_PopupDialog:KeyHandler( wParam );
	elseif wParam == Keys.VK_RETURN then -- Try CONFIRM. Then DEFAULT. Then give up and close window.
		if ( not m_PopupDialog:ActivateCommand( PopupDialog.COMMAND_CONFIRM ) ) then
			if ( not m_PopupDialog:ActivateCommand( PopupDialog.COMMAND_DEFAULT ) ) then
				OnClosePopup();
			end
		end
	end
end

function InputHandler( uiMsg, wParam, lParam )
	if(m_PopupDialog and m_PopupDialog:IsOpen()) then
		if uiMsg == KeyEvents.KeyUp then
			SRA_HandleKeyUp( wParam );
		end
		return true; -- eat all the input, just in case. popups are blocking!
	end
	return false;
end

-- ScreenReaderAccess mod change: WorldCongressIntro receives the keys before this popup (it is shown while this modal is up) and passes them on
function SRA_OnKeyFromAbove( key:number )
	if m_PopupDialog and m_PopupDialog:IsOpen() then SRA_HandleKeyUp( key ); end
end

-- ===========================================================================
function Initialize()
	m_PopupDialog = PopupDialog:new("InGamePopup");
	ContextPtr:SetInputHandler(InputHandler);
	LuaEvents.OnRaisePopupInGame.Add(OnPopupOpen);
	LuaEvents.SRA_InGamePopupKey.Add(SRA_OnKeyFromAbove);		-- ScreenReaderAccess mod change
	LuaEvents.Tutorial_TutorialEndHideBulkUI.Add(OnClosePopup);
end
Initialize();
