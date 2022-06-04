-- Utility methods specifically for helping out with plots and getting information about them

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

-- Turns an enumerated direction into its localized string form
function GetLocalizedDirectionString(direction)
	local directionTextPrefix = "LOC_DIRECTION_";

	local directionTextSuffix = DIRECTION_MAP[direction];
	if directionTextSuffix == nil then
		return "";
	end

	local localizedDirectionText = Locale.Lookup(directionTextPrefix .. directionTextSuffix);
	return localizedDirectionText;
end

-- Returns a short description of the unit on the map
function StringifyUnit(unit)
    local owner = unit:GetOwner();
    local adjective = PlayerConfigurations[owner]:GetCivilizationDescription();
    local stringified = Locale.Lookup(adjective) ..
        " " .. Locale.Lookup(unit:GetName());
    return stringified;
end

-- Returns a short description of the city on the map
function StringifyCity(city)
    local owner = city:GetOwner();
    local adjective = PlayerConfigurations[owner]:GetCivilizationDescription();
    local stringified = Locale.Lookup(adjective) ..
        " " .. Locale.Lookup("LOC_CITY_NAME_BLANK") ..
        " " .. Locale.Lookup(city:GetName());
    return stringified;
end