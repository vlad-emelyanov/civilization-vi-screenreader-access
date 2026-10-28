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
-- Words are compared whole and case-insensitively, with simple plural variants ("Amenities" = "Amenity").
-- Only the original text is passed in (never the words this function inserted for other icons).
local function _WordKey(w: string)
	w = string.lower(w);
	if string.sub(w, -3) == "ies" then return string.sub(w, 1, -4).."y"; end
	if #w > 3 and string.sub(w, -1) == "s" then return string.sub(w, 1, -2); end
	return w;
end

local function _AlreadySaid(word: string, before: string, after: string)
	local key = _WordKey(word);
	local count = 0;
	after = string.gsub(string.sub(after, 1, 60), "%[[^%]]*%]", " ");
	for w in string.gmatch(after, "%a+") do
		if _WordKey(w) == key then return true; end
		count = count + 1;
		if count >= 2 then break; end
	end
	before = string.gsub(string.sub(before, -40), "%[[^%]]*%]", " ");
	local lastWord = nil;
	for w in string.gmatch(before, "%a+") do lastWord = w; end
	return lastWord ~= nil and _WordKey(lastWord) == key;
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
		if word ~= nil and not _AlreadySaid(word, string.sub(message, 1, s - 1), string.sub(message, e + 1)) then
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
	if type(message) == "string" then
		-- Raw game text: line breaks become pauses; icons become words or nothing; leftover markup tags such as
		-- [COLOR:Red] or [ENDCOLOR] are dropped (text already cleaned by CleanTextForSpeech has none left).
		message = string.gsub(message, "%[NEWLINE%]", ", ");
		message = _StripIconMarkup(message);
		-- Only the game's known markup is dropped; anything else in brackets is real text (a player called "[KOS] Bob").
		message = string.gsub(message, "%[COLOR[:_][^%]]*%]", "");
		message = string.gsub(message, "%[ENDCOLOR%]", "");
		message = string.gsub(message, "%[TAB%]", " ");
		message = string.gsub(message, "%[ENDLINK%]", "");
		message = string.gsub(message, "%[LINK[^%]]*%]", "");
		message = string.gsub(message, ",%s*,", ",");
		message = string.gsub(message, "%s+", " ");
		message = string.gsub(message, "^[%s,]+", "");
		message = string.gsub(message, "[%s,]+$", "");
	else
		message = _StripIconMarkup(message);
	end
	-- The game's print() treats "%" as a printf escape: "50% of" came out as "50<number>f". Say it in words instead.
	if type(message) == "string" then message = string.gsub(message, "%s*%%", " percent"); end
	if message == nil or message == "" then return; end
	if nointerrupt == true then
		print(SCREENREADER_NO_INTERRUPT_LOG_PREFIX .. message);
	else
		print(SCREENREADER_LOG_PREFIX .. message);
	end
end

-- A key name in spoken text. The console app speaks `keyboard` when the player last used the keyboard, and the controller
-- button when they last used the pad: `button` (a Gamepad.Map name such as "X", "LT", "RSClick", or a literal phrase),
-- else the default button of `keyboard` (Enter = A, Escape = B, Tab = D-pad right ...), else `keyboard`.
function SRKey( keyboard:string, button:string )
	if button ~= nil and button ~= "" then return "[KEY:" .. keyboard .. "|" .. button .. "]"; end
	return "[KEY:" .. keyboard .. "]";
end

-- Text spoken ONLY when the player last used the gamepad (the console app keeps `text` for the pad, removes the token for the keyboard).
-- For hints that make no sense on the keyboard, e.g. SRPadHint( ", Y for details" ). `text` must not contain ']'.
function SRPadHint( text:string )
	return "[PAD:" .. text .. "]";
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

-- True when the plot has a resource the local player has not discovered yet (the engine still names it in placement conditions).
function SRPlotResourceHidden( plot:table )
	if plot == nil then return false; end
	local resource:number = plot:GetResourceType();
	if resource == nil or resource < 0 then return false; end
	local row:table = GameInfo.Resources[ resource ];
	local localPlayer:number = Game.GetLocalPlayer();
	if row == nil or localPlayer == nil or localPlayer == -1 then return false; end
	local resources:table = Players[ localPlayer ]:GetResources();
	return resources ~= nil and not resources:IsResourceVisible( row.Hash );
end

-- The game's "Will harvest the X on this tile" sentence for the plot's resource when the player cannot see that resource, else nil.
function SRHiddenHarvestSentence( plot:table )
	if not SRPlotResourceHidden( plot ) then return nil; end
	return Locale.Lookup( "LOC_DISTRICT_ZONE_WILL_HARVEST_RESOURCE", Locale.Lookup( GameInfo.Resources[ plot:GetResourceType() ].Name ) );
end

-- Placement confirmation text ([NEWLINE]-separated lines) without the sentence that names an undiscovered resource.
function SRStripHiddenHarvest( plot:table, text:string )
	local sentence:string = SRHiddenHarvestSentence( plot );
	if sentence == nil or text == nil then return text; end
	local out:table = {};
	local start:number = 1;
	while true do
		local a:number, b:number = string.find( text, "[NEWLINE]", start, true );
		local line:string = string.sub( text, start, a and a - 1 or nil );
		if line ~= sentence then table.insert( out, line ); end
		if a == nil then break; end
		start = b + 1;
	end
	return table.concat( out, "[NEWLINE]" );
end

-- A game tooltip (name line, stats, description, reasons) turned into "Name: description. rest": the description first,
-- the name line dropped from the tooltip (it is said once) and the description not repeated where the tooltip has it.
-- name, description (a loc key or text, may be nil) and tooltip are the raw game strings; Locale.Lookup is applied here.
function SRDescriptionFirst( name:string, description:string, tooltip:string )
	local plainName:string = CleanTextForSpeech( Locale.Lookup( name or "" ) );
	local rest:string = CleanTextForSpeech( Locale.Lookup( tooltip or "" ) );
	local plainDescription:string = "";
	if description ~= nil and description ~= "" then plainDescription = CleanTextForSpeech( Locale.Lookup( description ) ); end
	-- the tooltip starts with the upper-cased name
	if plainName ~= "" and string.lower( string.sub( rest, 1, #plainName ) ) == string.lower( plainName ) then
		rest = string.gsub( string.sub( rest, #plainName + 1 ), "^[%s%.,:]+", "" );
	end
	if plainDescription ~= "" then
		local from:number, to:number = string.find( rest, plainDescription, 1, true );
		if from ~= nil then
			rest = string.sub( rest, 1, from - 1 ) .. string.sub( rest, to + 1 );
			rest = string.gsub( rest, "%.%s*%.", "." );
			rest = string.gsub( rest, "^[%s%.,]+", "" );
			rest = string.gsub( rest, "[%s,]+$", "" );
		end
	end
	local text:string = plainName;
	if plainDescription ~= "" then text = text .. ": " .. plainDescription; end
	if rest ~= "" then
		if plainDescription ~= "" and not string.find( plainDescription, "[%.!?]$" ) then text = text .. "."; end
		text = text .. ( plainDescription ~= "" and " " or ": " ) .. rest;
	end
	return text;
end

-- What a great person's / general's action says once it ran: "Activate Mary Leakey: <effect>" becomes "Mary Leakey activated: <effect>",
-- "Retire Timur: <effect>" "Timur retired: <effect>"; any other action name is spoken as it is. Shared by the Tab menu (HubMenus)
-- and the U hotkey (UnitPanel).
function SRActionResultText( name:string )
	local verb:string, person:string, effect:string = string.match( name or "", "^(%a+) ([^:]+): (.*)$" );
	if verb == nil then verb, person = string.match( name or "", "^(%a+) ([^:]+)$" ); effect = nil; end
	local past:string = ( verb == "Activate" and "activated" ) or ( verb == "Retire" and "retired" ) or nil;
	if past == nil then return name; end
	return person .. " " .. past .. ( ( effect ~= nil and effect ~= "" ) and ( ": " .. effect ) or "" );
end
