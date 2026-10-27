-- ===========================================================================
--	GreatWorksText: pure wording helpers for the Great Works screen (GreatWorksOverview.lua) and the showcase
--	(GreatWorkShowcase.lua). No engine calls: every function gets its inputs as arguments so
--	test/lua/test_greatworkstext.lua can check the wording.
-- ===========================================================================

local SLOT_WORDS:table = {
	GREATWORKSLOT_WRITING	= "writing",
	GREATWORKSLOT_PALACE	= "palace",
	GREATWORKSLOT_ART		= "art",
	GREATWORKSLOT_CATHEDRAL	= "cathedral",
	GREATWORKSLOT_ARTIFACT	= "artifact",
	GREATWORKSLOT_MUSIC		= "music",
	GREATWORKSLOT_RELIC		= "relic",
	GREATWORKSLOT_HERO		= "hero",
};

local function Round1( value:number )
	return math.floor( value * 10 + 0.5 ) / 10;
end

local function Num( value:number )
	value = Round1( value );
	if value == math.floor( value ) then return tostring( math.floor( value ) ); end
	return tostring( value );
end

function GreatWorksText_Plural( n:number, one:string, many:string )
	return n .. " " .. ( n == 1 and one or many );
end

-- "writing" from "GREATWORKSLOT_WRITING"; unknown slot types are taken apart ("GREATWORKSLOT_FOO_BAR" -> "foo bar").
function GreatWorksText_SlotWord( slotType:string )
	if slotType == nil then return "great work"; end
	if SLOT_WORDS[ slotType ] ~= nil then return SLOT_WORDS[ slotType ]; end
	local word:string = string.gsub( slotType, "^GREATWORKSLOT_", "" );
	word = string.gsub( word, "_", " " );
	return string.lower( word );
end

-- "plus 2 culture, plus 2 tourism" from { { label, value } ... } (zero values are left out)
function GreatWorksText_Yields( yields:table )
	local parts:table = {};
	for _, y in ipairs( yields or {} ) do
		if y.value ~= nil and y.value ~= 0 then
			table.insert( parts, ( y.value > 0 and "plus " or "minus " ) .. Num( math.abs( y.value ) ) .. " " .. y.label );
		end
	end
	return table.concat( parts, ", " );
end

-- "'The Odyssey' by Homer, writing, plus 2 culture, plus 2 tourism"
function GreatWorksText_Work( work:table )
	local text:string = "'" .. work.name .. "'";
	if work.creator ~= nil and work.creator ~= "" then text = text .. " by " .. work.creator; end
	if work.typeName ~= nil and work.typeName ~= "" then text = text .. ", " .. string.lower( work.typeName ); end
	local yields:string = GreatWorksText_Yields( work.yields );
	if yields ~= "" then text = text .. ", " .. yields; end
	return text;
end

-- Theming status of one building: nil when there is nothing to say.
-- theming = { themed = boolean, numThemed, numSlots }
function GreatWorksText_Theming( theming:table )
	if theming == nil then return nil; end
	if theming.themed then return "theming bonus active"; end
	if theming.numSlots ~= nil and theming.numSlots > 1 then
		return theming.numThemed .. " of " .. theming.numSlots .. " for theming bonus";
	end
	return nil;
end

-- Section name of a building: "Rome, Museum, 2 of 3 for theming bonus"
function GreatWorksText_Header( cityName:string, buildingName:string, theming:table )
	local text:string = cityName .. ", " .. buildingName;
	local status = GreatWorksText_Theming( theming );
	if status ~= nil then text = text .. ", " .. status; end
	return text;
end

-- One slot of a building. work = nil for an empty slot.
-- "slot 2 of 3, 'The Odyssey' by Homer, writing, plus 2 culture"  /  "art slot 2, empty"
function GreatWorksText_Slot( slotWord:string, slot:number, numSlots:number, work:table )
	if work == nil then
		if numSlots > 1 then return slotWord .. " slot " .. slot .. ", empty"; end
		return slotWord .. " slot, empty";
	end
	local text:string = GreatWorksText_Work( work );
	if numSlots > 1 then text = "slot " .. slot .. " of " .. numSlots .. ", " .. text; end
	return text;
end

-- A destination while carrying a work: "art slot 2, empty"  /  "slot 1 of 3, holds 'Hamlet', would swap"
function GreatWorksText_Destination( slotWord:string, slot:number, numSlots:number, occupantName:string )
	if occupantName == nil then
		return GreatWorksText_Slot( slotWord, slot, numSlots, nil );
	end
	local where:string = ( numSlots > 1 ) and ( "slot " .. slot .. " of " .. numSlots .. ", " ) or ( slotWord .. " slot, " );
	return where .. "holds '" .. occupantName .. "', would swap";
end

-- "Great Works: 5 works, 3 empty slots, tourism plus 12"
function GreatWorksText_Summary( numWorks:number, numEmpty:number, tourism:number )
	local text:string = "Great Works: " .. GreatWorksText_Plural( numWorks, "work", "works" ) .. ", "
		.. GreatWorksText_Plural( numEmpty, "empty slot", "empty slots" );
	if tourism ~= nil and tourism > 0 then text = text .. ", tourism plus " .. Num( tourism ); end
	return text;
end

function GreatWorksText_Pickup( name:string, numTargets:number )
	return "Picked up " .. name .. ". " .. GreatWorksText_Plural( numTargets, "slot", "slots" )
		.. " available. " .. SRKey( "Enter" ) .. " to place, " .. SRKey( "Escape" ) .. " to cancel";
end

function GreatWorksText_Moved( name:string, cityName:string, buildingName:string, otherName:string )
	if otherName ~= nil then
		return "Swapped " .. name .. " with " .. otherName .. ", " .. name .. " is now in " .. cityName .. ", " .. buildingName;
	end
	return "Moved " .. name .. " to " .. cityName .. ", " .. buildingName;
end

-- Showcase: "New great work: The Odyssey. Created by Homer. <quote>. Enter to view your great works, Escape to close"
-- fields = { name, lines = { ... }, quote, position, count, gallery }
function GreatWorksText_Showcase( fields:table )
	local text:string = ( fields.gallery and "Great work: " or "New great work: " ) .. fields.name;
	for _, line in ipairs( fields.lines or {} ) do
		if line ~= nil and line ~= "" then
			local trimmed:string = string.gsub( line, "[%.%s]+$", "" );
			text = text .. ". " .. trimmed;
		end
	end
	if fields.quote ~= nil and fields.quote ~= "" then text = text .. ". " .. fields.quote; end
	if fields.gallery and fields.count ~= nil and fields.count > 1 then
		text = text .. ". " .. fields.position .. " of " .. fields.count .. ". " .. SRKey( "Left and Right" ) .. " for the next work";
	end
	if fields.gallery then
		text = text .. ". " .. SRKey( "Escape" ) .. " to close";
	else
		text = text .. ". " .. SRKey( "Enter" ) .. " to view your great works, " .. SRKey( "Escape" ) .. " to close";
	end
	return text;
end
