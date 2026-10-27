-- HubLenses.lua: one item per lens action of LensText, on/off text, legend, toggling through the input action
stub("engine")
include("LensText")
include("KeyNavList")
HubCore = { IsModeOpen = function() return true end, CloseMode = function() end }
Input = { GetActionId = function(name) return name == "LensAppeal" and 42 or nil end }
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

local function activate(key)
	local items = HubLenses.BuildItems()
	return find(items, key)
end

test("Enter fires the lens action id through Events.InputActionTriggered.Call", function()
	local called
	Events = { InputActionTriggered = { Call = function(id) called = id end } }
	ClearPrinted()
	HubLenses.Toggle(activate("LensAppeal"))
	eq(called, 42)
	eq(#Spoken(), 0)
end)

test("a missing .Call says to use the number key", function()
	Events = { InputActionTriggered = {} }
	ClearPrinted()
	HubLenses.Toggle(activate("LensAppeal"))
	local s = Spoken()[1]
	assert(s and s:find("number key"), tostring(s))
	assert(s:find("^Appeal lens"), tostring(s))
end)

test("an unknown action id says to use the number key", function()
	local called = false
	Events = { InputActionTriggered = { Call = function() called = true end } }
	ClearPrinted()
	HubLenses.Toggle(activate("LensContinent"))		-- the stub returns nil for it
	eq(called, false)
	assert(Spoken()[1]:find("number key"))
end)
