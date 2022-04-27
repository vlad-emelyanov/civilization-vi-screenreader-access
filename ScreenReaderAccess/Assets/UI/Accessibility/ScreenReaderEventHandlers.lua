-- This is separated out so that the main ScreenReader functions can be included without re-registering the callbacks
--------------------------------------------------------------

include("ScreenReader");

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

function Initialize()
	print("Initializing screen reader event handlers");
	
	-- hook into game and lua events to call above methods
	Events.UnitSelectionChanged.Add( OnUnitSelectionChanged );
	Events.CitySelectionChanged.Add( OnCitySelectionChanged );
end

Initialize();