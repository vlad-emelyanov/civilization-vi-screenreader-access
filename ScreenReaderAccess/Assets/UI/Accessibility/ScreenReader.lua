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

-- True when the text around an icon already says its word, so the icon word would only repeat it:
-- "[ICON_Gold] Gold", "[ICON_Strength] Combat Strength", "Production [ICON_Production]".
-- Compared case-insensitively on the first 5 letters, so "[ICON_Amenities] Amenity" is covered too.
local function _AlreadySaid(word: string, before: string, after: string)
	local stem = string.lower(string.sub(word, 1, 5));
	local count = 0;
	after = string.gsub(string.sub(after, 1, 60), "%[[^%]]*%]", " ");
	for w in string.gmatch(after, "%a+") do
		if string.lower(string.sub(w, 1, 5)) == stem then return true; end
		count = count + 1;
		if count >= 2 then break; end
	end
	local lastWord = nil;
	for w in string.gmatch(string.sub(before, -40), "%a+") do lastWord = w; end
	return lastWord ~= nil and string.lower(string.sub(lastWord, 1, 5)) == stem;
end

-- Replaces [ICON_xxx] markup (it would be spoken literally) with a word or nothing, and tidies the whitespace.
local function _StripIconMarkup(message: string)
	if type(message) ~= "string" then return message; end
	if string.find(message, "[ICON_", 1, true) == nil then return message; end
	local out = {};
	local pos = 1;
	while true do
		local s, e, tag = string.find(message, "%[(ICON_[^%]]*)%]", pos);
		if s == nil then break; end
		table.insert(out, string.sub(message, pos, s - 1));
		local word = ICON_WORDS[tag];
		if word ~= nil and not _AlreadySaid(word, table.concat(out), string.sub(message, e + 1)) then
			table.insert(out, " "..word.." ");
		else
			table.insert(out, " ");
		end
		pos = e + 1;
	end
	table.insert(out, string.sub(message, pos));
	message = table.concat(out);
	message = string.gsub(message, "%s+", " ");
	message = string.gsub(message, "^%s+", "");
	message = string.gsub(message, "%s+$", "");
	return message;
end

-- message: The message to be output to screenreaders
-- nointerrupt: Defaults to false. If set, will not try to interrupt currently speaking prompts. Useful for things that aren't in response to user action
function OutputMessageToScreenReader(message: string, nointerrupt: boolean)
	message = _StripIconMarkup(message);
	-- The game's print() treats "%" as a printf escape: "50% of" came out as "50<number>f". Say it in words instead.
	if type(message) == "string" then message = string.gsub(message, "%s*%%", " percent"); end
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
