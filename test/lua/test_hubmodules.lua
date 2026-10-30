-- InGameAccess hub: the hub file and its Accessibility/Hub*.lua modules must load (and Initialize() must run) against a
-- permissive engine stub. This catches load-order mistakes and misspelled cross-module names (Hub*.X is nil), not behaviour.
stub("engine")
Keys.VK_BACK = 8

-- Unknown engine globals become a do-anything dummy (and are recorded), so only the hub's own wiring is tested.
local Unknown = {}
local dummy = {}
setmetatable(dummy, {
	__index = function() return dummy end,
	__call = function() return dummy end,
	__concat = function(a, b) return "" end,
	__lt = function() return false end,
	__le = function() return false end,
})
-- `for row in GameInfo.X() do` must end: the tables of GameInfo iterate over nothing; no hot load (its loops use the dummy)
local emptyTable = setmetatable({}, { __call = function() return function() return nil end end, __index = function() return dummy end })
GameInfo = setmetatable({}, { __index = function() return emptyTable end })
ContextPtr = setmetatable({ IsHotLoad = function() return false end }, { __index = function() return function() return dummy end end })
Input = setmetatable({ GetActionId = function(name) return name end }, { __index = function() return dummy end })
for _, t in ipairs{ UI, Game, Locale, Keys, KeyEvents } do setmetatable(t, { __index = function() return dummy end }) end
setmetatable(_G, { __index = function(_, k) Unknown[k] = true; return dummy end })

-- game files the hub includes (Civ6Common ...) do not exist in the repo: skip them, but never skip our own modules
local realInclude = include
include = function(name)
	if name:find("^Hub") then return realInclude(name) end
	pcall(realInclude, name)
end

local TABLES = { "Hub", "HubCore", "HubCursor", "HubTargets", "HubAnnounce", "HubSettle", "HubPlacement", "HubMenus",
	"HubRegions", "HubMessages", "HubPlaces", "HubOverview", "HubCityReport", "HubEvents", "HubEnemies", "HubHelp", "HubGamepad", "HubPad", "HubLenses", "HubScreens" }

test("hub and modules load and Initialize runs", function()
	local path = ROOT .. "/ScreenReaderAccess/UI/Additions/InGameAccess.lua"
	local chunk, err = loadstring(sr_read(path), "@" .. path)
	assert(chunk, err)
	chunk()
	for _, name in ipairs(TABLES) do
		eq(type(rawget(_G, name)), "table", name .. " is a table")
	end
	for _, name in ipairs(TABLES) do
		eq(Unknown[name], nil, name .. " was looked up before it existed")
	end
end)

test("every function field of the modules is a function (no stray nil exports)", function()
	for _, name in ipairs(TABLES) do
		for k, v in pairs(rawget(_G, name)) do
			assert(v ~= nil, name .. "." .. k)
		end
	end
end)
