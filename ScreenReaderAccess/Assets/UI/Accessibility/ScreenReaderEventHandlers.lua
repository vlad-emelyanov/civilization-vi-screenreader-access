-- This is separated out so that the main ScreenReader functions can be included without re-registering the callbacks
--------------------------------------------------------------

include("ScreenReader");

-- locals

-- used to get the suffix for a direction for getting the localized string version from a direction
local DIRECTION_MAP = {
	[DirectionTypes.DIRECTION_NORTHEAST] = "NORTH_EAST",
	[DirectionTypes.DIRECTION_EAST] = "EAST",
	[DirectionTypes.DIRECTION_SOUTHEAST] = "SOUTH_EAST",
	[DirectionTypes.DIRECTION_NORTHWEST] = "NORTH_WEST",
	[DirectionTypes.DIRECTION_WEST] = "WEST",
	[DirectionTypes.DIRECTION_SOUTHWEST] = "SOUTH_WEST"
}

-- ===========================================================================
--	Game Engine Event
-- ===========================================================================
function OnUnitSelectionChanged( playerID:number, unitID:number, hexI:number, hexJ:number, hexK:number, isSelected:boolean, isEditable:boolean )
	if playerID ~= Game.GetLocalPlayer() or not isSelected then 
		return;
	end

	local pUnit = Players[playerID]:GetUnits():FindID(unitID);
	local tUnitData = GameInfo.Units[pUnit:GetType()]
	local name = Locale.Lookup(tUnitData.Name);
	OutputMessageToScreenReader(name);

	local iPois = GetAdjacentPointsOfInterestFrom(hexI, hexJ);
	local poisString = TurnPointsOfInterestIntoString(iPois);
	if poisString ~= nil then
		OutputMessageToScreenReader(poisString, true);
	end
end

-- ===========================================================================
--	GAME Event
--	City was selected.
-- ===========================================================================
function OnCitySelectionChanged( owner:number, cityID:number, i, j, k, isSelected:boolean, isEditable:boolean)
	if owner ~= Game.GetLocalPlayer() or isSelected == false then
		return
	end

	local pCity = Players[owner]:GetCities():FindID(cityID);
	local name = Locale.Lookup(pCity:GetName());
	local population = pCity:GetPopulation();
	local additionalInfo = " (" .. Locale.Lookup("LOC_HUD_CITY_POPULATION") .. " " .. population .. ")";
	OutputMessageToScreenReader(name .. additionalInfo);
end

function GetAdjacentPointsOfInterestFrom(hexX: number, hexY: number)
	local units = {}
	local cities = {}

	for direction = 0, DirectionTypes.NUM_DIRECTION_TYPES - 1, 1 do
		local adjacentPlot = Map.GetAdjacentPlot(hexX, hexY, direction);
		local iX, iY = adjacentPlot:GetX(), adjacentPlot:GetY();

		if adjacentPlot then
			for i, unit in ipairs(Units.GetUnitsInPlot(adjacentPlot)) do
				table.insert(units, { unit = unit, direction = direction });
			end

			if Cities.GetCityInPlot(adjacentPlot) ~= nil then
				table.insert(cities, { city = Cities.GetCityInPlot(adjacentPlot), direction = direction });
			end
		end
	end

	return { units = units, cities = cities };
end

function TurnPointsOfInterestIntoString(iPois: table)
	local output = {}

	for i, item in ipairs(iPois.units) do
		local owner = item.unit:GetOwner();
		local adjective = PlayerConfigurations[owner]:GetCivilizationDescription();
		local stringified = Locale.Lookup(adjective) ..
			" " .. Locale.Lookup(item.unit:GetName()) ..
			" " .. GetLocalizedDirectionString(item.direction);
		table.insert(output, stringified);
	end

	for i, item in ipairs(iPois.cities) do
		local owner = item.city:GetOwner();
		local adjective = PlayerConfigurations[owner]:GetCivilizationDescription();
		local stringified = Locale.Lookup(adjective) ..
			" " .. Locale.Lookup("LOC_CITY_NAME_BLANK") ..
			" " .. Locale.Lookup(item.city:GetName()) ..
			" " .. GetLocalizedDirectionString(item.direction);
		table.insert(output, stringified);
	end

	if #output > 0 then
		return table.concat(output, "[NEWLINE]");
	else
		return nil;
	end
end

function GetLocalizedDirectionString(direction)
	local directionTextPrefix = "LOC_DIRECTION_";

	local directionTextSuffix = DIRECTION_MAP[direction];
	if directionTextSuffix == nil then
		return "";
	end

	local localizedDirectionText = Locale.Lookup(directionTextPrefix .. directionTextSuffix);
	return localizedDirectionText;
end

function Initialize()
	print("Initializing screen reader event handlers");

	-- hook into game and lua events to call above methods
	Events.UnitSelectionChanged.Add( OnUnitSelectionChanged );
	Events.CitySelectionChanged.Add( OnCitySelectionChanged );
end

Initialize();