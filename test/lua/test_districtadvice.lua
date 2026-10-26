-- DistrictAdvice.lua: wording of the district spot line and the best spot sentence
stub("engine")
include("DistrictAdvice")

local function e(name, total, rel, extra)
	local t = { name = name, total = total, relative = rel, owned = true, adjacency = {}, removes = {} }
	for k, v in pairs(extra or {}) do t[k] = v end
	return t
end

test("line: best first, location only for the best, no-bonus districts at the end", function()
	local line = DistrictAdvice_Line({
		e("Holy Site", 2, "1 tile east"), e("Theater Square", 0, "adjacent"), e("Campus", 3, "2 tiles north-east"),
		e("Industrial Zone", 1, "3 tiles south"),
	})
	eq(line, "District spots: Campus plus 3 (2 tiles north-east), Holy Site plus 2, Industrial Zone plus 1. Theater Square: no spot with a bonus")
end)

test("line: withWhere gives every location", function()
	local line = DistrictAdvice_Line({ e("Campus", 3, "2 tiles north"), e("Holy Site", 2, "1 tile east") }, true)
	eq(line, "District spots: Campus plus 3 (2 tiles north), Holy Site plus 2 (1 tile east)")
end)

test("line: only no-bonus and none at all", function()
	eq(DistrictAdvice_Line({ e("Harbor", 0), e("Aqueduct", 0) }), "District spots: Aqueduct, Harbor: no spot with a bonus")
	eq(DistrictAdvice_Line({}), "District spots: no district can be built now")
end)

test("best spot: adjacency, direction, tile cost, removals", function()
	eq(DistrictAdvice_BestSpot(e("Campus", 3, "2 tiles north-east", { adjacency = { "plus 3 Science" } })),
		"Best spot: plus 3 Science, 2 tiles north-east")
	eq(DistrictAdvice_BestSpot(e("Campus", 4, "1 tile west", { adjacency = { "plus 3 Science", "plus 1 Gold" }, owned = false, tileCost = 40, removes = { "Woods" } })),
		"Best spot: plus 3 Science, plus 1 Gold, 1 tile west, tile costs 40 gold, removes Woods")
	eq(DistrictAdvice_BestSpot(e("Harbor", 0, "adjacent")), "Best spot: no adjacency bonus, adjacent")
	eq(DistrictAdvice_BestSpot(nil), "Best spot: none available now")
end)

test("city report: the district spots item is lazy and speaks the line", function()
	include("CityReportData")
	local calls = 0
	local d = {
		name = "Rome", population = 1, foodSurplus = 1, yields = { food = { value = 1, tooltip = "" }, production = { value = 1, tooltip = "" },
			gold = { value = 1, tooltip = "" }, science = { value = 1, tooltip = "" }, culture = { value = 1, tooltip = "" }, faith = { value = 1, tooltip = "" } },
		districts = {}, wonders = {}, buildingsNum = 0, districtsCount = 0, districtsMax = 0,
		districtSpots = function() calls = calls + 1; return { e("Campus", 3, "2 tiles north-east") } end,
	}
	local items = CityReport_BuildItems(d)
	local item
	for _, it in ipairs(items) do if it.key == "districtspots" then item = it end end
	eq(item ~= nil, true, "item present")
	eq(calls, 0, "nothing scanned while building")
	eq(item.text, "District spots: Campus plus 3 (2 tiles north-east)")
	eq(item.detail:find("Best spot", 1, true) ~= nil, true, "detail has the best spot")
end)
