-- ===========================================================================
--	NotificationSubject.lua: what a notification is about, appended to its title in the Control+N list.
--	Pure text logic (luatest); NotificationPanel.lua resolves the city / unit name and calls this.
--	Order: own city (location or target) -> unit name -> the short summary for types whose title alone is ambiguous.
-- ===========================================================================

-- Types (substring of the type name) and title words whose summary names the distinguishing part
NOTIFICATION_SUBJECT_SUMMARY_TYPES = { "WONDER_COMPLETED", "AMENITIES", "LOYAL", "FREE_CITY", "PEACE" };
NOTIFICATION_SUBJECT_SUMMARY_TITLES = { "peace", "loyalty", "amenities", "free city", "wonder completed" };
NOTIFICATION_SUBJECT_MAX_WORDS = 12;

local function NS_Contains( text:string, part:string )
	return text ~= nil and part ~= nil and part ~= "" and string.find( string.lower( text ), string.lower( part ), 1, true ) ~= nil;
end

local function NS_WordCount( text:string )
	local n:number = 0;
	for _ in string.gmatch( text, "%S+" ) do n = n + 1; end
	return n;
end

local function NS_Usable( name:string )
	return name ~= nil and name ~= "" and string.sub( name, 1, 4 ) ~= "LOC_";
end

-- Returns the list item: "<message>: <subject>" or the message alone. cityName / unitName may be nil.
function NotificationSubject_Line( typeName:string, message:string, summary:string, cityName:string, unitName:string )
	summary = summary or "";
	if NS_Usable( cityName ) and not NS_Contains( message, cityName ) and not NS_Contains( summary, cityName ) then
		return message .. ": " .. cityName;
	end
	if NS_Usable( unitName ) and not NS_Contains( message, unitName ) then
		return message .. ": " .. unitName;
	end
	-- the summary names the city / wonder / both sides: use it when short and different from the title
	if NS_Usable( summary ) and NS_WordCount( summary ) <= NOTIFICATION_SUBJECT_MAX_WORDS and string.lower( summary ) ~= string.lower( message ) then
		local wanted:boolean = false;
		for _, t in ipairs( NOTIFICATION_SUBJECT_SUMMARY_TYPES ) do
			if typeName ~= nil and string.find( typeName, t, 1, true ) then wanted = true; end
		end
		for _, t in ipairs( NOTIFICATION_SUBJECT_SUMMARY_TITLES ) do
			if NS_Contains( message, t ) then wanted = true; end
		end
		if wanted then return summary; end	-- a full sentence that already says what kind of notification it is
	end
	return message;
end
