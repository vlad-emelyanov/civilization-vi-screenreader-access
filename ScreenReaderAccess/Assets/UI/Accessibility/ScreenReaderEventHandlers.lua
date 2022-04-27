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

function Initialize()
	print("Initializing screen reader event handlers");
	
	-- hook into game and lua events to call above methods
	Events.UnitSelectionChanged.Add( OnUnitSelectionChanged );
end

Initialize();