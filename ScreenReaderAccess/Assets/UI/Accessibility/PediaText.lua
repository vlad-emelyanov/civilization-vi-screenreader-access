-- ===========================================================================
--	PediaText: pure text helpers for the Civilopedia (Civilopedia/CivilopediaSupport.lua).
--	No engine calls except CleanTextForSpeech (ScreenReader.lua); inputs come as arguments so
--	test/lua/test_pediatext.lua can check the wording.
-- ===========================================================================

include( "ScreenReader" );

-- Game text for speech; bullets of the pedia lists become nothing, runs of dots collapse.
function PediaText_Clean( text:string )
	if text == nil then return ""; end
	text = string.gsub( text, "%[ICON_BULLET%]", "" );
	text = CleanTextForSpeech( text );
	for i = 1, 2 do
		text = string.gsub( text, "%.%s*%.", "." );
		text = string.gsub( text, "%s+([%.,:])", "%1" );
	end
	return text;
end

-- "1 line", "12 lines"
function PediaText_Count( n:number, one:string, many:string )
	return n .. " " .. ( n == 1 and one or many );
end

-- A stat row: caption and value ("Combat strength 20"); the caption's trailing colon goes.
function PediaText_StatLine( caption:string, value )
	local cap:string = string.gsub( PediaText_Clean( caption ), "%s*:$", "" );
	local val:string = PediaText_Clean( tostring( value ) );
	if cap == "" then return val; end
	if val == "" then return cap; end
	return cap .. " " .. val;
end

function PediaText_LinkLine( name:string )
	return "Link: " .. PediaText_Clean( name );
end

-- "Civilopedia. Concepts, 1 of 18 sections"
function PediaText_Opening( sectionName:string, index:number, count:number )
	return "Civilopedia. " .. sectionName .. ", " .. index .. " of " .. count .. ( count == 1 and " section" or " sections" );
end

-- Section change: "Units, 7 of 18 sections"
function PediaText_Section( sectionName:string, index:number, count:number )
	return sectionName .. ", " .. index .. " of " .. count .. ( count == 1 and " section" or " sections" );
end

-- "Warrior page, 12 lines. <first line>" / "Warrior page, no text"
function PediaText_PageOpening( title:string, lines:table )
	local name:string = PediaText_Clean( title );
	if #lines == 0 then return name .. " page, no text"; end
	local first:string = lines[1].text;
	if lines[1].link ~= nil then first = lines[1].text; end
	return name .. " page, " .. PediaText_Count( #lines, "line", "lines" ) .. ". " .. first;
end

-- All lines from index i on as one text (Space): lines get a full stop unless they end in punctuation.
function PediaText_JoinFrom( lines:table, i:number )
	local parts:table = {};
	for n = i, #lines do
		local t:string = lines[ n ].text;
		if t ~= nil and t ~= "" then
			if not string.find( t, "[%.!%?:;]$" ) then t = t .. "."; end
			table.insert( parts, t );
		end
	end
	return table.concat( parts, " " );
end

-- Entries of a section as KeyNavList items. pages: the game's page tables ( PageId, PageGroupId, TabName ), sorted
-- as the game shows them. groupName( page ) returns the group's name or nil.
function PediaText_Entries( sectionId:string, pages:table, groupName )
	local items:table = {};
	for _, page in ipairs( pages or {} ) do
		local group = nil;
		if page.PageGroupId ~= nil and groupName ~= nil then group = groupName( page ); end
		table.insert( items, {
			key = sectionId .. "::" .. page.PageId,
			text = PediaText_Clean( page.TabName or page.PageId ),
			section = group and PediaText_Clean( group ) or nil,
			sectionId = sectionId, pageId = page.PageId,
		} );
	end
	return items;
end

-- Search results ( { key = "Section|Page", name } ) as KeyNavList items, duplicates dropped, at most max.
function PediaText_SearchItems( results:table, sectionName, max:number )
	local items:table = {};
	local seen:table = {};
	for _, r in ipairs( results or {} ) do
		local sectionId, pageId = string.match( r.key or "", "([^|]+)|([^|]+)" );
		if sectionId ~= nil and not seen[ r.key ] then
			seen[ r.key ] = true;
			local label:string = PediaText_Clean( r.name or pageId );
			local sName = sectionName ~= nil and sectionName( sectionId ) or nil;
			if sName ~= nil and sName ~= "" then label = label .. ", " .. PediaText_Clean( sName ); end
			table.insert( items, { key = r.key, text = label, sectionId = sectionId, pageId = pageId } );
			if max ~= nil and #items >= max then break; end
		end
	end
	return items;
end
