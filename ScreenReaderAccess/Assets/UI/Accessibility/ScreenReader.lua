-- ScreenReader module
--------------------------------------------------------------

local SCREENREADER_LOG_PREFIX: string = "#SCREENREADER - ";
local SCREENREADER_NO_INTERRUPT_LOG_PREFIX: string = "#SCREENREADER[NOINTERRUPT] - ";

-- Icons whose meaning matters when spoken; any other [ICON_xxx] is decorative and dropped.
local ICON_WORDS: table = {
	ICON_Food = "Food", ICON_Production = "Production", ICON_Gold = "Gold",
	ICON_Science = "Science", ICON_Culture = "Culture", ICON_Faith = "Faith",
	ICON_Housing = "Housing", ICON_Amenities = "Amenities", ICON_Amenity = "Amenities",
	ICON_Tourism = "Tourism", ICON_Strength = "Strength", ICON_Movement = "Movement",
	ICON_Range = "Range",
};

-- Replaces [ICON_xxx] markup (it would be spoken literally) with a word or nothing, and tidies the whitespace.
local function _StripIconMarkup(message: string)
	if type(message) ~= "string" then return message; end
	if string.find(message, "[ICON_", 1, true) == nil then return message; end
	message = string.gsub(message, "%[(ICON_[^%]]*)%]", function(tag)
		local word = ICON_WORDS[tag];
		if word ~= nil then return " "..word.." "; end
		return " ";
	end);
	message = string.gsub(message, "%s+", " ");
	message = string.gsub(message, "^%s+", "");
	message = string.gsub(message, "%s+$", "");
	return message;
end

-- message: The message to be output to screenreaders
-- nointerrupt: Defaults to false. If set, will not try to interrupt currently speaking prompts. Useful for things that aren't in response to user action
function OutputMessageToScreenReader(message: string, nointerrupt: boolean)
	message = _StripIconMarkup(message);
	if message == nil or message == "" then return; end
	if nointerrupt == true then
		print(SCREENREADER_NO_INTERRUPT_LOG_PREFIX .. message);
	else
		print(SCREENREADER_LOG_PREFIX .. message);
	end
end

-- Prepares game text (with [NEWLINE] and [ICON_x] style markup) for speech.
function CleanTextForSpeech(text: string)
	if text == nil then return ""; end
	text = string.gsub(text, "%[NEWLINE%]", ". ");
	text = _StripIconMarkup(text);
	text = string.gsub(text, "%[[^%]]*%]", "");
	text = string.gsub(text, "%s+", " ");
	text = string.gsub(text, "^%s+", "");
	text = string.gsub(text, "%s+$", "");
	return text;
end
