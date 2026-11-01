-- HubEvents.lua: the production auto-swap decision and wording
stub("engine")
include("ScreenReader")
include("HubCore")
include("HubEvents")

test("a swap is a different unit without a completion", function()
	eq(HubEvents.ProductionSwapped(11, 12, false), true)
	eq(HubEvents.ProductionSwapped(11, 11, false), false)
	eq(HubEvents.ProductionSwapped(11, 12, true), false)
	eq(HubEvents.ProductionSwapped(nil, 12, false), false)
	eq(HubEvents.ProductionSwapped(11, nil, false), false)
	eq(HubEvents.ProductionSwapped(0, 12, false), false)
end)

test("swap wording", function()
	eq(HubEvents.ProductionSwapText("Rome", "Archer", "Crossbowman"), "Rome now builds Crossbowman instead of Archer")
end)
