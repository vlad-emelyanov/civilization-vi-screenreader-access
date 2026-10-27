-- HubLenses.lua: one item per lens action of LensText, on/off text, legend, toggling through the input action
stub("engine")
include("LensText")
include("KeyNavList")
include("HubLenses")

local active = nil
LensText_ActiveLens = function() return active end
LensText_Legend = function(lens) if lens == "Power" then return "" end return lens .. " legend" end

local function find(items, key)
	for _, it in ipairs(items) do if it.key == key then return it end end
end

test("one item per lens action, sorted by name", function()
	local items = HubLenses.BuildItems()
	local n = 0
	for _ in pairs(LensText_Actions) do n = n + 1 end
	eq(#items, n)
	for i = 2, #items do assert(items[i - 1].text < items[i].text, "sorted") end
end)

test("text says off, then on for the active lens", function()
	active = nil
	eq(find(HubLenses.BuildItems(), "LensAppeal").text, "Appeal lens, off")
	active = "Appeal"
	local items = HubLenses.BuildItems()
	eq(find(items, "LensAppeal").text, "Appeal lens, on")
	eq(find(items, "LensContinent").text, "Continent lens, off")
	active = nil
end)

test("detail is the legend, or No legend", function()
	local items = HubLenses.BuildItems()
	eq(find(items, "LensAppeal").detail, "Appeal legend")
	eq(find(items, "LensPower").detail, "No legend")
end)
