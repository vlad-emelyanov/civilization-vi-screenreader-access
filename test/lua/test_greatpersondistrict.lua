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

local function J(t) return table.concat(t, "|") end
local M = "Must be on a completed "

test("replaces only the district refusal entry", function()
	eq(J(PlotDescription_ReplaceDistrictRefusal({ "Must be on a completed Campus." }, M, "X, 1 tile east")), "X, 1 tile east")
	eq(J(PlotDescription_ReplaceDistrictRefusal({ "no moves left", "Must be on a completed Campus." }, M, "X")), "no moves left|X")
	eq(J(PlotDescription_ReplaceDistrictRefusal({ "Danger" }, M, "X")), "Danger")
end)

test("an ability text with commas is replaced whole", function()
	local out = J(PlotDescription_ReplaceDistrictRefusal(
		{ "Triggers the Eureka moment, then grants a boost, and more: Must be on a completed Campus." }, M, "X"))
	eq(out, "X")
end)

test("district name differs (unique district): the prefix still matches", function()
	eq(J(PlotDescription_ReplaceDistrictRefusal({ "A, B: Must be on a completed Seowon." }, M, "X")), "X")
end)

test("nearest names the actual district", function()
	eq(PlotDescription_DistrictReason("Campus", { cityName = "Seoul", relative = "2 tiles east", districtName = "Seowon" }, false),
		"must stand on a completed Campus. Nearest: Seoul's Seowon, 2 tiles east")
end)
