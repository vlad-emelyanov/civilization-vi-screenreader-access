-- ===========================================================================
--	DealSpeech: spoken text for the diplomacy deal screen, from plain data (no engine calls, so it is unit tested:
--	test/lua/test_dealspeech.lua). Used by DiplomacyDealView.lua, which fills the records from the game's deal.
--
--	Deal item record:      { kind = "gold"|"favor"|"resource"|"agreement"|"city"|"greatwork"|"captive",
--	                         name = <localized>, amount = <number>, duration = <turns, 0 = one time>, detail = <extra text> }
--	Available item record: the same plus { class = "Luxury"|"Strategic", enabled = false, reason = <text>,
--	                         otherNone = "they"|"you" (the other side has none of this resource) }
-- ===========================================================================

local function Turns( n )
	return n .. ( n == 1 and " turn" or " turns" );
end

-- "50 gold", "5 gold per turn for 30 turns", "Silk, 1, 30 turns", "Open Borders, 30 turns", "City: Rome"
function DealSpeech_ItemText( item )
	local kind = item.kind;
	local duration = item.duration or 0;
	if kind == "gold" then
		if duration > 0 then return ( item.amount or 0 ) .. " gold per turn for " .. Turns( duration ); end
		return ( item.amount or 0 ) .. " gold";
	elseif kind == "favor" then
		return ( item.amount or 0 ) .. " diplomatic favor";
	elseif kind == "resource" then
		local text = ( item.name or "Resource" ) .. ", " .. ( item.amount or 0 );
		if duration > 0 then text = text .. ", " .. Turns( duration ); end
		return text;
	elseif kind == "agreement" then
		local text = item.name or "Agreement";
		if item.detail ~= nil and item.detail ~= "" then text = text .. ", " .. item.detail; end
		if duration > 0 then text = text .. ", " .. Turns( duration ); end
		return text;
	elseif kind == "city" then
		return "City: " .. ( item.name or "unknown" );
	elseif kind == "greatwork" then
		return "Great work: " .. ( item.name or "unknown" );
	elseif kind == "captive" then
		return item.name or "Captive";
	end
	return item.name or "Item";
end

-- "You give: 5 gold; Open Borders, 30 turns" / "They give: Silk, 1" for an item of the deal (mine = you give it).
function DealSpeech_DealItemText( item, mine )
	return ( mine and "You give: " or "They give: " ) .. DealSpeech_ItemText( item );
end

-- "You give: a; b. They give: c." / "Deal is empty."
function DealSpeech_Summary( give, get )
	if #give == 0 and #get == 0 then return "Deal is empty."; end
	local function Side( label, items, none )
		if #items == 0 then return none; end
		local texts = {};
		for i, item in ipairs( items ) do texts[i] = DealSpeech_ItemText( item ); end
		return label .. ": " .. table.concat( texts, "; " );
	end
	return Side( "You give", give, "You give nothing" ) .. ". " .. Side( "They give", get, "They give nothing" ) .. ".";
end

-- mode: "make" (you open the deal), "demand" (you demand), "theirdeal" (the AI proposes), "theirdemand", "theirgift"
function DealSpeech_Intro( leader, civ, mode )
	local who = leader .. " of " .. civ;
	if mode == "theirdeal" then return who .. " proposes a deal."; end
	if mode == "theirdemand" then return who .. " demands:"; end
	if mode == "theirgift" then return who .. " offers a gift."; end
	if mode == "demand" then return "Demand from " .. who .. "."; end
	return "Deal with " .. who .. ".";
end

-- Entry of the available lists: "Gold, 120 available", "Silk, luxury, 2 available, they have none", "City: Rome",
-- "Research Agreement, unavailable: they have no technology to share".
function DealSpeech_AvailableText( item )
	local kind = item.kind;
	local text;
	if kind == "gold" then
		if ( item.duration or 0 ) > 0 then
			text = "Gold per turn";
			if item.amount ~= nil then text = text .. ", " .. item.amount .. " available"; end
		else
			text = "Gold, " .. ( item.amount or 0 ) .. " available";
		end
	elseif kind == "favor" then
		text = "Diplomatic favor, " .. ( item.amount or 0 ) .. " available";
	elseif kind == "resource" then
		text = ( item.name or "Resource" ) .. ", " .. ( item.class ~= nil and ( string.lower( item.class ) .. ", " ) or "" ) .. ( item.amount or 0 ) .. " available";
		if item.otherNone ~= nil then text = text .. ", " .. item.otherNone .. " have none"; end
	elseif kind == "agreement" then
		text = item.name or "Agreement";
		if ( item.duration or 0 ) > 0 then text = text .. ", " .. Turns( item.duration ); end
	else
		text = DealSpeech_ItemText( item );
	end
	if item.enabled == false then
		text = text .. ", unavailable" .. ( ( item.reason ~= nil and item.reason ~= "" ) and ( ": " .. item.reason ) or "" );
	end
	return text;
end

-- What changed between two lists of item texts (before/after a click): "Added: 50 gold", "Removed: Silk, 1",
-- "Changed: 60 gold" (same count, a text that was not there before) or nil when nothing differs.
function DealSpeech_ChangeText( before, after )
	local function Missing( from, other )
		local counts = {};
		for _, text in ipairs( other ) do counts[ text ] = ( counts[ text ] or 0 ) + 1; end
		for _, text in ipairs( from ) do
			if ( counts[ text ] or 0 ) > 0 then
				counts[ text ] = counts[ text ] - 1;
			else
				return text;
			end
		end
		return nil;
	end
	local added = Missing( after, before );
	local removed = Missing( before, after );
	if #after > #before and added ~= nil then return "Added: " .. added; end
	if #after < #before and removed ~= nil then return "Removed: " .. removed; end
	if added ~= nil then return "Changed: " .. added; end
	return nil;
end

-- What is spoken after a click/key changed the deal: the change (from DealSpeech_ChangeText), then the REST of the deal.
-- giveTexts / getTexts: DealSpeech_DealItemText of every item per side; summary: DealSpeech_Summary of the deal.
-- "Added: X" / "Changed: X" already say which side gives X, so X is not repeated in the rest.
function DealSpeech_ChangeSpeech( change, giveTexts, getTexts, summary, fallback )
	if change ~= nil then
		local prefix = nil;
		if string.sub( change, 1, 7 ) == "Added: " then prefix = "Added: ";
		elseif string.sub( change, 1, 9 ) == "Changed: " then prefix = "Changed: "; end
		if prefix ~= nil then
			local changed = string.sub( change, #prefix + 1 );
			local rest = {};
			local skipped = false;
			for _, list in ipairs( { giveTexts, getTexts } ) do
				for _, text in ipairs( list ) do
					if text == changed and not skipped then skipped = true; else table.insert( rest, text ); end
				end
			end
			if skipped then
				if #rest == 0 then
					return change .. ". " .. ( string.sub( changed, 1, 9 ) == "You give:" and "They give nothing." or "You give nothing." );
				end
				return change .. ". Also: " .. table.concat( rest, "; " );
			end
		end
	end
	return ( change or fallback or "Nothing changed" ) .. ". " .. summary;
end

-- Why an action vanished: "Item no longer available: Coffee, 1 (you have 0 to trade)". invalid = { { text = <item text>, reason = <optional> } ... }
-- nil when the deal has no invalid item (the caller keeps the generic wording).
function DealSpeech_InvalidItemsText( invalid )
	if invalid == nil or #invalid == 0 then return nil; end
	local parts = {};
	for i, entry in ipairs( invalid ) do
		parts[i] = entry.text .. ( ( entry.reason ~= nil and entry.reason ~= "" ) and ( " (" .. entry.reason .. ")" ) or "" );
	end
	return ( #invalid == 1 and "Item no longer available: " or "Items no longer available: " ) .. table.concat( parts, "; " );
end

-- Reason for a resource that is not tradeable (amount in the deal vs what the giver can trade now), nil when it is fine.
function DealSpeech_ResourceReason( giverIsYou, dealAmount, tradeable )
	if tradeable == nil or tradeable >= ( dealAmount or 0 ) then return nil; end
	return ( giverIsYou and "you have " or "they have " ) .. tradeable .. " to trade";
end
