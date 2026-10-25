-- PlotDescription.lua: the "must stand on a completed <district>" wording for great persons
stub("engine")
local world = stub("world").new{ width = 20, height = 12 }
world:install()
include("PlotDescription")

test("hotkey wording with the nearest district", function()
	eq(PlotDescription_DistrictReason("Campus", { cityName = "Rome", relative = "1 tile north-west" }, true),
		"must stand on a completed Campus district. Nearest: Rome's Campus, 1 tile north-west")
end)

test("menu wording drops the word district", function()
	eq(PlotDescription_DistrictReason("Campus", { cityName = "Rome", relative = "1 tile north-west" }, false),
		"must stand on a completed Campus. Nearest: Rome's Campus, 1 tile north-west")
end)

test("no completed district", function()
	eq(PlotDescription_DistrictReason("Campus", nil, true),
		"must stand on a completed Campus district. You have no completed Campus")
end)

test("replaces only the district refusal", function()
	eq(PlotDescription_ReplaceDistrictRefusal("Must be on a completed Campus.", "X, 1 tile east"), "X, 1 tile east")
	eq(PlotDescription_ReplaceDistrictRefusal("no moves left, Must be on a completed Campus.", "X"), "no moves left, X")
	eq(PlotDescription_ReplaceDistrictRefusal("Danger", "X"), "Danger")
end)
