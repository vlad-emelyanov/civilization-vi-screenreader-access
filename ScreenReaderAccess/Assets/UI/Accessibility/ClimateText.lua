-- ===========================================================================
--	ClimateText: pure wording helpers for the World Climate screen (UI/Replacements/ClimateScreen_SRA.lua).
--	No engine calls: every function gets its inputs as arguments so test/lua/test_climatetext.lua can check the wording.
-- ===========================================================================

local function Round1( value:number )
	return math.floor( value * 10 + 0.5 ) / 10;
end

local function Num( value:number )
	value = Round1( value );
	if value == math.floor( value ) then return tostring( math.floor( value ) ); end
	return tostring( value );
end

function ClimateText_Plural( n:number, one:string, many:string )
	return n .. " " .. ( n == 1 and one or many );
end

-- "plus 0.4", "minus 1.2", "0"
function ClimateText_Signed( value:number )
	value = Round1( value or 0 );
	if value == 0 then return "0"; end
	if value > 0 then return "plus " .. Num( value ); end
	return "minus " .. Num( -value );
end

-- Whole percent of part in total (0 when total is 0)
function ClimateText_Percent( part:number, total:number )
	if total == nil or total <= 0 or part == nil then return 0; end
	return math.floor( part * 100 / total + 0.5 );
end

-- "Overview, 1 of 3 tabs"
function ClimateText_Tab( label:string, index:number, count:number )
	return label .. ", " .. index .. " of " .. count .. " tabs";
end

-- "phase 2 of 7, Coastal Flooding"  /  "no climate change phase reached yet"
function ClimateText_Phase( phase:number, maxPhases:number, name:string )
	if phase == nil or phase <= 0 then return "no climate change phase reached yet"; end
	local text:string = "phase " .. phase .. " of " .. maxPhases;
	if name ~= nil and name ~= "" then text = text .. ", " .. name; end
	return text;
end

-- "global temperature plus 0.4 degrees"
function ClimateText_Temperature( change:number )
	return "global temperature " .. ClimateText_Signed( change ) .. ( Round1( change or 0 ) == 0 and "" or " degrees" );
end

-- "your CO2 contribution 12 percent, ranked 1 of 5 civilizations"
function ClimateText_Contribution( mine:number, total:number, rank:number, count:number )
	if total == nil or total <= 0 then return "no CO2 emitted yet"; end
	local text:string = "your CO2 contribution " .. ClimateText_Percent( mine, total ) .. " percent";
	if rank ~= nil and count ~= nil and count > 0 then
		text = text .. ", ranked " .. rank .. " of " .. count .. " civilizations";
	end
	return text;
end

-- Opening line of the overview. f = { phase, maxPhases, phaseName, temperature, seaLevel, nextRiseTurns, contribution }
-- "Phase 2 of 7, Coastal Flooding, global temperature plus 0.4 degrees, sea level rise 1 meter, next rise in 30 turns. Your CO2 ..."
function ClimateText_Summary( f:table )
	local parts:table = { ClimateText_Phase( f.phase, f.maxPhases, f.phaseName ), ClimateText_Temperature( f.temperature ) };
	if f.seaLevel ~= nil and f.seaLevel ~= "" then table.insert( parts, f.seaLevel ); end
	if f.nextRiseTurns ~= nil and f.nextRiseTurns > 0 then
		table.insert( parts, "next sea level rise in " .. ClimateText_Plural( f.nextRiseTurns, "turn", "turns" ) );
	end
	local text:string = table.concat( parts, ", " );
	text = string.upper( string.sub( text, 1, 1 ) ) .. string.sub( text, 2 );
	if f.contribution ~= nil and f.contribution ~= "" then
		text = text .. ". " .. string.upper( string.sub( f.contribution, 1, 1 ) ) .. string.sub( f.contribution, 2 );
	end
	return text;
end

-- "Storms: 12 percent chance, 3 of that from climate change"
function ClimateText_Chance( label:string, chance:number, fromClimate:number )
	local text:string = label .. ": " .. Num( chance or 0 ) .. " percent chance";
	if fromClimate ~= nil and fromClimate > 0 then text = text .. ", " .. Num( fromClimate ) .. " of that from climate change"; end
	return text;
end

-- "Volcanoes: 4 percent eruption chance, 2 active, 5 inactive, 1 volatile, 3 erupted"
function ClimateText_Volcanoes( chance:number, active:number, inactive:number, volatile:number, erupted:number )
	return "Volcanoes: " .. Num( chance or 0 ) .. " percent eruption chance, " .. ( active or 0 ) .. " active, "
		.. ( inactive or 0 ) .. " inactive, " .. ( volatile or 0 ) .. " volatile, " .. ( erupted or 0 ) .. " erupted";
end

-- "Rome (You): 120 CO2, 34 percent"
function ClimateText_Row( name:string, amount:number, total:number )
	return name .. ": " .. Num( amount or 0 ) .. " CO2, " .. ClimateText_Percent( amount, total ) .. " percent";
end

-- "Storm, Hurricane Alfred, North America, turn 85, 3 tiles damaged, 1 population lost"
-- f = { turn, typeName, name, location, effects = { "..." } }
function ClimateText_Event( f:table )
	local parts:table = {};
	if f.typeName ~= nil and f.typeName ~= "" then table.insert( parts, f.typeName ); end
	if f.name ~= nil and f.name ~= "" then table.insert( parts, f.name ); end
	if f.location ~= nil and f.location ~= "" then table.insert( parts, f.location ); end
	table.insert( parts, "turn " .. f.turn );
	for _, effect in ipairs( f.effects or {} ) do table.insert( parts, effect ); end
	return table.concat( parts, ", " );
end

-- Effects of a disaster as short phrases from its counts
function ClimateText_Effects( fertilityAdded:number, tilesDamaged:number, unitsLost:number, popLost:number )
	local effects:table = {};
	if fertilityAdded ~= nil and fertilityAdded > 0 then table.insert( effects, ClimateText_Plural( fertilityAdded, "tile fertilized", "tiles fertilized" ) ); end
	if fertilityAdded ~= nil and fertilityAdded < 0 then table.insert( effects, ClimateText_Plural( -fertilityAdded, "tile lost fertility", "tiles lost fertility" ) ); end
	if tilesDamaged ~= nil and tilesDamaged > 0 then table.insert( effects, ClimateText_Plural( tilesDamaged, "tile damaged", "tiles damaged" ) ); end
	if unitsLost ~= nil and unitsLost > 0 then table.insert( effects, ClimateText_Plural( unitsLost, "unit lost", "units lost" ) ); end
	if popLost ~= nil and popLost > 0 then table.insert( effects, popLost .. " population lost" ); end
	return effects;
end
