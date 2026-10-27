-- ===========================================================================
--	DiplomacyText: pure wording for diplomacy and notification lines (no engine calls, test/lua/test_diplomacytext.lua).
--	- DiplomacyText_Opening: first words of a leader scene the AI opened ("Dido of Phoenicia, agenda comment (negative): ").
--	- DiplomacyText_NotificationLine: "Declaration of War: <who declared on whom>".
--	- DiplomacyText_SuzerainNote: ", you become suzerain" for a pending city-state envoy count.
-- ===========================================================================

-- statement type (DiplomacyStatementTypes, Gameplay/Data/DiplomacyStatements_*.xml) -> what the AI is doing.
-- Entries containing "(" are comments / warnings ("Dido of Phoenicia, agenda comment (negative): ..."), the rest are things the
-- leader does ("Suleiman of the Ottomans proposes a deal: ...").
DIPLOMACY_TEXT_REASONS = {
	DIPLOMATIC_KUDO = "compliment (positive)",
	DIPLOMATIC_WARNING = "warning (negative)",
	DIPLOMATIC_HIDDEN_AGENDA_KUDO = "agenda comment (positive)",
	DIPLOMATIC_HIDDEN_AGENDA_WARNING = "agenda comment (negative)",
	WARNING_DONT_SETTLE_NEAR_ME = "warning (negative), don't settle near me",
	WARNING_STOP_CONVERTING_MY_CITIES = "warning (negative), stop converting my cities",
	WARNING_STOP_DIGGING_UP_ARTIFACTS = "warning (negative), stop digging up my artifacts",
	WARNING_STOP_SPYING_ON_ME = "warning (negative), stop spying on me",
	WARNING_TOO_MANY_TROOPS_NEAR_ME = "warning (negative), too many troops near me",
	DIPLOMATIC_DELEGATION = "sends a delegation",
	RESIDENT_EMBASSY = "offers to exchange embassies",
	DECLARE_FRIEND = "asks for a declaration of friendship",
	DENOUNCE = "denounces you",
	MAKE_DEAL = "proposes a deal",
	MAKE_PEACE = "proposes peace",
	MAKE_ALLIANCE = "proposes an alliance",
	OPEN_BORDERS = "proposes open borders",
	MAKE_DEMAND = "makes a demand",
	RENEW_ALLIANCE = "proposes to renew the alliance",
	NO_TARGET = "has something to say",
	DEFEAT = "admits defeat",
	GREETING = "greets you",
	FIRST_MEET_NEAR_INITIATOR = "meets you", FIRST_MEET_NEAR_RECIPIENT = "meets you", FIRST_MEET_NO_MANS = "meets you",
	FIRST_MEET_NO_MANS_INFO_EXCHANGE = "meets you", FIRST_MEET_VISIT_RECIPIENT = "meets you",
};

-- "Ottomans" -> "the Ottomans", "Netherlands" -> "the Netherlands", "Phoenicia" stays (plural names end in s)
function DiplomacyText_CivWithArticle( civ:string )
	if civ ~= nil and string.find( civ, "s$" ) and not string.find( civ, "^[Tt]he " ) then return "the " .. civ; end
	return civ;
end

-- "DECLARE_FOO_WAR" -> "declare foo war"
function DiplomacyText_HumanizeType( statementType:string )
	local words:string = string.gsub( statementType, "_", " " );
	return string.lower( words );
end

-- Returns the opening, ending with ": ": "Dido of Phoenicia, agenda comment (negative): ", "Suleiman of the Ottomans proposes a deal: ",
-- or "Dido of Phoenicia says: " when the AI is only answering (aiInitiated false / subType is a deal answer) or the type is nil.
-- A known-unmapped type is humanized: "Suleiman of the Ottomans, some type words: ".
-- Wars (DECLARE_*_WAR): "declares war on you"; JOINT wars: "asks you to join a war".
function DiplomacyText_Opening( leader:string, civ:string, statementType:string, subType:string, aiInitiated:boolean )
	local who:string = leader .. " of " .. DiplomacyText_CivWithArticle( civ );
	local firstWords:boolean = (subType == nil or subType == "NONE" or subType == "POSITIVE" or subType == "NEGATIVE");
	if aiInitiated and firstWords and statementType ~= nil then
		local reason:string = DIPLOMACY_TEXT_REASONS[ statementType ];
		if reason == nil and string.find( statementType, "^DECLARE_JOINT_" ) then
			reason = "asks you to join a war";
		elseif reason == nil and string.find( statementType, "^DECLARE_.*WAR" ) then
			reason = "declares war on you";
		end
		if reason ~= nil then
			if string.find( reason, "(", 1, true ) then return who .. ", " .. reason .. ": "; end
			return who .. " " .. reason .. ": ";
		end
		return who .. ", " .. DiplomacyText_HumanizeType( statementType ) .. ": ";
	end
	return who .. " says: ";
end

-- Notification types whose title ("Declaration of War") alone does not say who: the summary names the parties
DIPLOMACY_TEXT_PARTY_NOTIFICATIONS = {
	NOTIFICATION_DECLARE_WAR = true, NOTIFICATION_DECLARE_WAR_CITY_STATE = true, NOTIFICATION_MAKE_PEACE = true, NOTIFICATION_MAKE_PEACE_CITY_STATE = true,
};

-- "Declaration of War: Montezuma (Aztecs) has declared war on Suleiman (Ottomans)." or the plain title
function DiplomacyText_NotificationLine( typeName:string, message:string, summary:string )
	if DIPLOMACY_TEXT_PARTY_NOTIFICATIONS[ typeName ] and summary ~= nil and summary ~= "" then
		return message .. ": " .. summary;
	end
	return message;
end

-- ", you become suzerain" when the envoys (given + pending) reach what the suzerain needs and you are not suzerain yet
function DiplomacyText_SuzerainNote( isSuzerain:boolean, tokens:number, pending:number, needed:number )
	if isSuzerain or pending <= 0 or needed == nil or needed <= 0 then return ""; end
	if tokens + pending >= needed then return ", you become suzerain"; end
	return "";
end
