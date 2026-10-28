-- ===========================================================================
--	ReportText: pure text helpers for the Reports screen (Screens/ReportScreen.lua).
--	No engine calls except CleanTextForSpeech (ScreenReader.lua); everything gets its inputs as arguments so
--	test/lua/test_reporttext.lua can check the wording.
-- ===========================================================================

include( "ScreenReader" );

local function Round1( value:number )
	return math.floor( value * 10 + 0.5 ) / 10;
end

local function Num( value:number )
	value = Round1( value );
	if value == math.floor( value ) then return tostring( math.floor( value ) ); end
	return tostring( value );
end

-- "plus 4", "minus 2.5", "0" from a number, or from the screen's text ("+4", "-2.5", " ", "0"). nil for empty text.
function ReportText_Signed( value )
	if value == nil then return nil; end
	if type( value ) == "number" then
		value = Round1( value );
		if value == 0 then return "0"; end
		if value > 0 then return "plus " .. Num( value ); end
		return "minus " .. Num( -value );
	end
	local text:string = string.gsub( tostring( value ), "^%s+", "" );
	text = string.gsub( text, "%s+$", "" );
	if text == "" then return nil; end
	local sign:string = string.sub( text, 1, 1 );
	if sign == "+" then return "plus " .. string.sub( text, 2 ); end
	if sign == "-" then return "minus " .. string.sub( text, 2 ); end
	return text;
end

function ReportText_Plural( n:number, one:string, many:string )
	return n .. " " .. ( n == 1 and one or many );
end

-- "Yields, 1 of 4 tabs"
function ReportText_Tab( label:string, index:number, count:number )
	return label .. ", " .. index .. " of " .. count .. " tabs";
end

-- "gold plus 8, science plus 6" from { { label, value } ... }; entries without a value (or 0 when skipZero) are left out.
function ReportText_YieldList( entries:table, skipZero:boolean )
	local parts:table = {};
	for _, entry in ipairs( entries ) do
		local signed = ReportText_Signed( entry.value );
		if signed ~= nil and not ( skipZero and signed == "0" ) then
			table.insert( parts, entry.label .. " " .. signed );
		end
	end
	return table.concat( parts, ", " );
end

-- "Rome: production plus 12, food plus 4, gold plus 8" (zero yields are left out)
function ReportText_CityIncome( name:string, entries:table )
	local list:string = ReportText_YieldList( entries, true );
	if list == "" then list = "no yields"; end
	return name .. ", " .. list;
end

-- One row of the source breakdown: "Library: science plus 2, culture plus 1" (name alone when it yields nothing)
function ReportText_LineItem( name:string, entries:table )
	local list:string = ReportText_YieldList( entries, true );
	if list == "" then return name; end
	return name .. ", " .. list;
end

-- "Gold: income plus 30, expenses minus 12, net plus 18, balance 245"
function ReportText_Currency( label:string, income, expenses, net, balance )
	local parts:table = {};
	local function Add( what:string, value )
		local text = ReportText_Signed( value );
		if text ~= nil then table.insert( parts, what .. " " .. text ); end
	end
	Add( "income", income );
	Add( "expenses", expenses );
	Add( "net", net );
	if balance ~= nil and tostring( balance ) ~= "" then table.insert( parts, "balance " .. tostring( balance ) ); end
	if #parts == 0 then return label; end
	return label .. ": " .. table.concat( parts, ", " );
end

-- "Warrior, 3 units, minus 3 gold"
function ReportText_UnitExpense( name:string, count:number, maintenance:number )
	return name .. ", " .. ReportText_Plural( count, "unit", "units" ) .. ", minus " .. Num( maintenance ) .. " gold";
end

-- "Rome, Library, minus 1 gold"
function ReportText_BuildingExpense( city:string, building:string, maintenance:number )
	return city .. ", " .. building .. ", minus " .. Num( maintenance ) .. " gold";
end

-- thing: "4 gold per turn" or "2 Silk"
function ReportText_Deal( civ:string, outgoing:boolean, thing:string, turnsLeft:number )
	local who:string = outgoing and "you give" or "they give";
	local text:string = "Deal with " .. civ .. ": " .. who .. " " .. thing;
	if turnsLeft ~= nil then
		text = text .. ", " .. ReportText_Plural( turnsLeft, "turn", "turns" ) .. " left";
	end
	return text;
end

-- r: { name, class = "luxury"|"strategic"|"bonus", total, stockpile, maximum, amenityCities, exported, imported }
-- "Silk, luxury, 2, amenities to 4 cities, 1 traded away"
function ReportText_Resource( r:table )
	local parts:table = { r.name, r.class };
	if r.class == "strategic" and r.maximum ~= nil then
		table.insert( parts, ReportText_Signed( r.total ) .. " per turn" );
		table.insert( parts, "stockpile " .. Num( r.stockpile or 0 ) .. " of " .. Num( r.maximum ) );
	elseif r.class == "strategic" then
		table.insert( parts, ReportText_Signed( r.total ) );
	else
		table.insert( parts, Num( r.total ) );
	end
	if r.amenityCities ~= nil and r.amenityCities > 0 then
		table.insert( parts, "amenities to " .. ReportText_Plural( r.amenityCities, "city", "cities" ) );
	end
	if r.exported ~= nil and r.exported > 0 then table.insert( parts, Num( r.exported ) .. " traded away" ); end
	if r.imported ~= nil and r.imported > 0 then table.insert( parts, Num( r.imported ) .. " received in trades" ); end
	return table.concat( parts, ", " );
end

-- entries: { { source, kind = "owned"|"exported"|"imported"|"city-state"|"other", amount } }, allocations: { "2 to Rome" }
function ReportText_ResourceDetail( name:string, entries:table, allocations:table )
	local parts:table = {};
	for _, entry in ipairs( entries ) do
		local kind:string = entry.kind ~= "" and entry.kind or "other";
		table.insert( parts, entry.source .. ", " .. kind .. ", " .. ReportText_Signed( entry.amount ) );
	end
	local text:string = name .. ": " .. ( #parts > 0 and table.concat( parts, ". " ) or "no sources" );
	if allocations ~= nil and #allocations > 0 then
		text = text .. ". Amenities: " .. table.concat( allocations, ", " );
	end
	return text;
end

-- d: { name, population, housing, growthStatus, turnsUntilGrowth, amenities, amenitiesRequired, happiness, warWeariness,
--      loyalty, maxLoyalty, loyaltyPerTurn, siege, occupied, strength, damage, production, productionTurns }
function ReportText_CityStatus( d:table )
	local parts:table = { d.name, "population " .. d.population, "housing " .. Num( d.housing ) };
	if d.growthStatus ~= nil and d.growthStatus ~= "" then table.insert( parts, "growth " .. string.lower( d.growthStatus ) ); end
	local turns = d.turnsUntilGrowth;
	if turns ~= nil and turns > 0 then
		table.insert( parts, "grows in " .. ReportText_Plural( turns, "turn", "turns" ) );
	elseif turns ~= nil and turns < 0 then
		table.insert( parts, "starving in " .. ReportText_Plural( -turns, "turn", "turns" ) );
	end
	table.insert( parts, "amenities " .. Num( d.amenities ) .. " of " .. Num( d.amenitiesRequired ) .. " needed" );
	if d.happiness ~= nil and d.happiness ~= "" then table.insert( parts, string.lower( d.happiness ) ); end
	if d.warWeariness ~= nil and d.warWeariness > 0 then table.insert( parts, "war weariness minus " .. Num( d.warWeariness ) .. " amenities" ); end
	if d.loyalty ~= nil and d.maxLoyalty ~= nil then
		local text:string = "loyalty " .. Num( d.loyalty ) .. " of " .. Num( d.maxLoyalty );
		if d.loyaltyPerTurn ~= nil and d.loyaltyPerTurn ~= 0 then text = text .. ", " .. ReportText_Signed( d.loyaltyPerTurn ) .. " per turn"; end
		table.insert( parts, text );
	end
	if d.production ~= nil and d.production ~= "" then
		local text:string = "producing " .. d.production;
		if d.productionTurns ~= nil and d.productionTurns > 0 then text = text .. " in " .. ReportText_Plural( d.productionTurns, "turn", "turns" ); end
		table.insert( parts, text );
	end
	table.insert( parts, "defense " .. Num( d.strength or 0 ) );
	if d.damage ~= nil and d.damage > 0 then table.insert( parts, "damage " .. Num( d.damage ) ); end
	if d.siege then table.insert( parts, "under siege" ); end
	if d.occupied then table.insert( parts, "occupied" ); end
	return table.concat( parts, ", " );
end

-- "Turn 98: Dido built a Campus in Tyre"
function ReportText_Gossip( turn, text:string )
	return "Turn " .. tostring( turn ) .. ": " .. CleanTextForSpeech( text );
end
