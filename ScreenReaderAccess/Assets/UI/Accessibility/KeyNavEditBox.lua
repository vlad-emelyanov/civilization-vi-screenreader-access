-- KeyNavEditBox: keyboard / screen reader editing of EditBox controls.
--------------------------------------------------------------
-- While an EditBox has keyboard focus the engine consumes all key input: the context's input handler sees nothing, and
-- the engine itself handles Enter (fires the commit callback) and Escape (restores the old text, then fires the commit
-- callback too, then the Escape KeyUp still reaches the context). This module works with that:
--   * typed / deleted characters are announced from the string-changed callback,
--   * Enter / Escape are told apart in the commit callback (Escape reverts the text just before committing),
--   * the KeyUp of the key that ended the edit is swallowed so it does not also act as navigation (Escape = leave screen).
--   * call KeyNavEditBox_Update(deltaTime) from the context's update handler (announces unchanged-text commits),
--   * call KeyNavEditBox_Cancel() from OnShow / OnHide of the context so no edit state survives a screen change.
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
local m_swallowUp = false;	-- the next Enter / Escape KeyUp belongs to the edit that just ended and must not reach the screen
local m_pending = nil;		-- announcement waiting for that KeyUp (Enter vs Escape is only known from the key when the text is unchanged)

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

local function NoOp(...) end

-- "Label, edit, value" (value is "blank" when empty).
function KeyNavEditBox_Describe(label:string, editBox:object)
	local result:string = label..", edit, "..OrBlank(editBox:GetText());
	if editBox:IsDisabled() then result = result..", disabled"; end
	return result;
end

function KeyNavEditBox_IsEditing()
	return m_edit ~= nil;
end

-- Ends the session: puts the original commit callback back, drops focus, calls onEnd. keyDriven: Enter / Escape ended it.
local function EndEdit(committed:boolean, keyDriven:boolean)
	local edit:table = m_edit;
	if edit == nil then return; end
	m_edit = nil;
	m_swallowUp = (keyDriven == true);
	if not keyDriven then m_pending = nil; end
	pcall(function() edit.box:RegisterCommitCallback(edit.commit or NoOp); end);
	pcall(function() edit.box:DropFocus(); end);
	if edit.onEnd ~= nil then pcall(edit.onEnd, committed); end
end

-- Abandons any edit and forgets all state (call from OnShow / OnHide). The text stays as the engine left it.
function KeyNavEditBox_Cancel()
	if m_edit ~= nil then EndEdit(false, false); end
	m_swallowUp = false;
	m_pending = nil;
end

local function OnTextChanged(...)
	local edit:table = m_edit;
	if edit == nil then return; end
	local new:string = edit.box:GetText() or "";
	local old:string = edit.last;
	if new == old then return; end
	edit.last = new;

	-- common prefix / suffix to find what was typed or deleted
	local p:number = 0;
	local maxp:number = math.min(#old, #new);
	while p < maxp and string.sub(old, p + 1, p + 1) == string.sub(new, p + 1, p + 1) do p = p + 1; end
	local s:number = 0;
	local maxs:number = math.min(#old, #new) - p;
	while s < maxs and string.sub(old, #old - s, #old - s) == string.sub(new, #new - s, #new - s) do s = s + 1; end
	local added:string = string.sub(new, p + 1, #new - s);
	local removed:string = string.sub(old, p + 1, #old - s);

	if new == edit.original and removed ~= "" and added == "" and #removed > 1 then
		return;	-- most likely Escape restoring the old text: the commit that follows announces it
	end
	if edit.numeric and string.find(added, "[^%d]") ~= nil then
		Say("Invalid, digits only");
	elseif added ~= "" then
		Say(Speakable(added));
	elseif removed ~= "" then
		if new == "" and new ~= edit.original then Say("blank"); else Say("deleted "..Speakable(removed)); end
	end
end

-- Starts editing: gives the box keyboard focus and announces it. opts: label, commit(text), numeric, onEnd(committed)
function KeyNavEditBox_Begin(editBox:object, opts:table)
	if m_edit ~= nil then EndEdit(false, false); end
	if editBox:IsDisabled() then
		Say(KeyNavEditBox_Describe(opts.label or "", editBox));
		return;
	end
	local text:string = editBox:GetText() or "";
	local edit:table = {
		box = editBox, label = opts.label or "", original = text, last = text,
		numeric = opts.numeric == true, commit = opts.commit, onEnd = opts.onEnd, committedText = nil,
	};
	m_edit = edit;
	m_swallowUp = false;
	m_pending = nil;
	editBox:RegisterStringChangedCallback(OnTextChanged);
	editBox:RegisterCommitCallback(function(committedText)
		if m_edit ~= edit then
			-- stale wrapper (should have been replaced in EndEdit): behave like the original callback
			if edit.commit ~= nil then edit.commit(committedText); end
			return;
		end
		local final:string = editBox:GetText() or "";
		local changed:boolean = (final ~= edit.original);
		EndEdit(changed, true);	-- end first: whatever happens below, the session is over
		if changed then
			edit.committedText = final;
			if edit.commit ~= nil then
				local ok, err = pcall(edit.commit, committedText);
				if not ok then print("KeyNavEditBox commit error: "..tostring(err)); end
			end
			Say(edit.label.." set to "..OrBlank(final));
		else
			-- text equals the original: either Escape (reverted) or Enter without changes (or typed back); the key tells
			m_pending = { label = edit.label, text = final, age = 0 };
		end
	end);
	editBox:RegisterHasFocusCallback(function()
		-- focus lost some other way (mouse click elsewhere): the edit is over
		if m_edit == edit and not editBox:HasFocus() then
			local final:string = editBox:GetText() or "";
			local changed:boolean = (final ~= edit.original);
			EndEdit(changed, false);
			if changed then
				-- commit unless the engine's own commit already ran for this text
				if edit.committedText ~= final and edit.commit ~= nil then
					local ok, err = pcall(edit.commit, final);
					if not ok then print("KeyNavEditBox commit error: "..tostring(err)); end
				end
				Say(edit.label.." set to "..OrBlank(final));
			else
				Say(edit.label..", "..OrBlank(final));
			end
		end
	end);
	editBox:TakeFocus();
	Say("editing "..edit.label);
end

local function FlushPending(escape:boolean)
	local pending:table = m_pending;
	m_pending = nil;
	if pending == nil then return; end
	if escape then
		Say("Cancelled, "..pending.label..", "..OrBlank(pending.text));
	else
		Say(pending.label.." set to "..OrBlank(pending.text));
	end
end

-- Call from the context's update handler. Enter's KeyUp never reaches the context, so an unchanged-text commit that no
-- Escape KeyUp claims within a moment was an Enter.
function KeyNavEditBox_Update(deltaTime:number)
	if m_pending ~= nil then
		m_pending.age = m_pending.age + deltaTime;
		if m_pending.age > 0.35 then FlushPending(false); end
	end
end

-- Call first thing in a context's input handler. Returns nil when the input is not for this module (carry on as usual),
-- true when it must be swallowed.
function KeyNavEditBox_HandleInput(pInputStruct:table)
	if m_swallowUp then
		local msg = pInputStruct:GetMessageType();
		if msg == KeyEvents.KeyUp then
			local key:number = pInputStruct:GetKey();
			if key == Keys.VK_RETURN or key == Keys.VK_ESCAPE then
				m_swallowUp = false;
				FlushPending(key == Keys.VK_ESCAPE);
				return true;
			end
		elseif msg == KeyEvents.KeyDown then
			-- some other key was pressed: the ending key's KeyUp is not coming any more
			m_swallowUp = false;
			FlushPending(false);
		end
	end
	return nil;
end
