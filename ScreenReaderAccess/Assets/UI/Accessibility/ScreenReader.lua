-- ScreenReader module
--------------------------------------------------------------

local SCREENREADER_LOG_PREFIX: string = "#SCREENREADER - ";
local SCREENREADER_NO_INTERRUPT_LOG_PREFIX: string = "#SCREENREADER[NOINTERRUPT] - ";

-- Removes [ICON_xxx] markup (it would be spoken literally) and tidies the whitespace left behind.
local function _StripIconMarkup(message: string)
	if type(message) ~= "string" then return message; end
	if string.find(message, "[ICON_", 1, true) == nil then return message; end
	message = string.gsub(message, "%[ICON_[^%]]*%]", "");
	message = string.gsub(message, "%s+", " ");
	message = string.gsub(message, "^%s+", "");
	message = string.gsub(message, "%s+$", "");
	return message;
end

-- message: The message to be output to screenreaders
-- nointerrupt: Defaults to false. If set, will not try to interrupt currently speaking prompts. Useful for things that aren't in response to user action
function OutputMessageToScreenReader(message: string, nointerrupt: boolean)
	message = _StripIconMarkup(message);
	if nointerrupt == true then
		print(SCREENREADER_NO_INTERRUPT_LOG_PREFIX .. message);
	else
		print(SCREENREADER_LOG_PREFIX .. message);
	end
end
