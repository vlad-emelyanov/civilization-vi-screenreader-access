-- KeyNavEditBox: keyboard / screen reader editing of EditBox controls.
--------------------------------------------------------------
-- While an EditBox has keyboard focus the engine consumes all key input: the context's input handler sees nothing, and
-- the engine itself handles Enter (fires the commit callback) and Escape (restores the old text, then fires the commit
-- callback too, then the Escape KeyUp still reaches the context). This module works with that:
--   * typed / deleted characters are announced from the string-changed callback,
--   * Enter / Escape are told apart in the commit callback (Escape reverts the text just before committing),
--   * the KeyUp of the key that ended the edit is swallowed so it does not also act as navigation (Escape = leave screen).
--
-- Usage (one edit session at a time):
--   include("KeyNavEditBox");
--   Focus announcement:  OutputMessageToScreenReader(KeyNavEditBox_Describe(label, editBox) .. ", Enter to edit");
--   Enter on the field:  KeyNavEditBox_Begin(editBox, { label = label, commit = commitFn, numeric = true|false, onEnd = fn(committed) });
--   First thing in the context's input handler (and in the key handler: stay out of the way while editing):
--       local handled = KeyNavEditBox_HandleInput(pInputStruct);   -- nil: not relevant, carry on
--       if handled ~= nil then return handled; end
-- `commit` must be the function the original UI registers with RegisterCommitCallback (it receives the text):
-- Begin re-registers the EditBox's commit callback so it can announce the result, and calls `commit` itself.

local m_edit = nil;			-- the active session, or nil
local m_swallowUp = false;	-- the KeyUp of the key that ended an edit (Enter or Escape) must not reach the screen

local function Say(text:string)
	OutputMessageToScreenReader(text, false);
end

local function Speakable(s:string)
	if s == " " then return "space"; end
	return s;
end

local function OrBlank(text:string)
	if text == nil or text == "" then return "blank"; end
	return text;
end

-- "Label, edit, value" (value is "blank" when empty).
function KeyNavEditBox_Describe(label:string, editBox:object)
	local result:string = label..", edit, "..OrBlank(editBox:GetText());
	if editBox:IsDisabled() then result = result..", disabled"; end
	return result;
end

function KeyNavEditBox_IsEditing()
	return m_edit ~= nil;
end

local function EndEdit(committed:boolean)
	local edit:table = m_edit;
	if edit == nil then return; end
	m_edit = nil;
	m_swallowUp = true;
	pcall(function() edit.box:DropFocus(); end);
	if edit.onEnd ~= nil then pcall(edit.onEnd, committed); end
end

local function OnTextChanged(...)
	local edit:table = m_edit;
	if edit == nil then return; end
	local new:string = edit.box:GetText() or "";
	local old:string = edit.last;
	if new == old then return; end
	edit.last = new;
	edit.reverted = (new == edit.original);	-- Escape restores the original text right before committing

	-- common prefix / suffix to find what was typed or deleted
	local p:number = 0;
	local maxp:number = math.min(#old, #new);
	while p < maxp and string.sub(old, p + 1, p + 1) == string.sub(new, p + 1, p + 1) do p = p + 1; end
	local s:number = 0;
	local maxs:number = math.min(#old, #new) - p;
	while s < maxs and string.sub(old, #old - s, #old - s) == string.sub(new, #new - s, #new - s) do s = s + 1; end
	local added:string = string.sub(new, p + 1, #new - s);
	local removed:string = string.sub(old, p + 1, #old - s);

	if edit.reverted and removed ~= "" and added == "" and #removed > 1 then
		return;	-- Escape: the commit callback that follows announces the cancel
	end
	if edit.numeric and string.find(added, "[^%d]") ~= nil then
		Say("Invalid, digits only");
	elseif added ~= "" then
		Say(Speakable(added));
	elseif removed ~= "" then
		if new == "" then Say("blank"); else Say("deleted "..Speakable(removed)); end
	end
end

-- Starts editing: gives the box keyboard focus and announces it. opts: label, commit(text), numeric, onEnd(committed)
function KeyNavEditBox_Begin(editBox:object, opts:table)
	if m_edit ~= nil then EndEdit(false); end
	if editBox:IsDisabled() then
		Say(KeyNavEditBox_Describe(opts.label or "", editBox));
		return;
	end
	local text:string = editBox:GetText() or "";
	local edit:table = {
		box = editBox, label = opts.label or "", original = text, last = text, reverted = false,
		numeric = opts.numeric == true, commit = opts.commit, onEnd = opts.onEnd,
	};
	m_edit = edit;
	m_swallowUp = false;
	editBox:RegisterStringChangedCallback(OnTextChanged);
	editBox:RegisterCommitCallback(function(committedText)
		if m_edit ~= edit then return; end
		local cancelled:boolean = edit.reverted;
		if edit.commit ~= nil then edit.commit(committedText); end
		if cancelled then
			Say("Cancelled, "..edit.label..", "..OrBlank(editBox:GetText()));
		else
			Say(edit.label.." set to "..OrBlank(editBox:GetText()));
		end
		EndEdit(not cancelled);
	end);
	editBox:RegisterHasFocusCallback(function()
		-- focus lost some other way (mouse click elsewhere): the edit is over, keep whatever the engine did with the text
		if m_edit == edit and not editBox:HasFocus() then
			Say(edit.label..", "..OrBlank(editBox:GetText()));
			EndEdit(false);
			m_swallowUp = false;
		end
	end);
	editBox:TakeFocus();
	Say("editing "..edit.label);
end

-- Call first thing in a context's input handler. Returns nil when the input is not for this module (carry on as usual),
-- true when it must be swallowed.
function KeyNavEditBox_HandleInput(pInputStruct:table)
	if m_swallowUp and pInputStruct:GetMessageType() == KeyEvents.KeyUp then
		m_swallowUp = false;
		local key:number = pInputStruct:GetKey();
		if key == Keys.VK_RETURN or key == Keys.VK_ESCAPE then return true; end
	end
	return nil;
end
