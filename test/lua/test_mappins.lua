-- MapPins.lua: wording and the data layer over a fake PlayerConfigurations
stub("engine")
include("MapPins")

test("wording", function()
	eq(MapPins.DisplayName(""), "Unnamed pin")
	eq(MapPins.DisplayName(nil), "Unnamed pin")
	eq(MapPins.DisplayName("Iron here"), "Iron here")
	eq(MapPins.PlotPhrase({}), nil)
	eq(MapPins.PlotPhrase({ "Iron here" }), "pin: Iron here")
	eq(MapPins.PlotPhrase({ "" }), "pin")
	eq(MapPins.PlotPhrase({ "A", "" }), "pin: A, pin")
	eq(MapPins.ItemText("Iron here", "5 tiles south-east of Rome"), "Iron here, 5 tiles south-east of Rome")
	eq(MapPins.ItemText("", "in Rome"), "Unnamed pin, in Rome")
	eq(MapPins.ItemText("Camp", "2 tiles east of Rome", "Anna"), "Camp, 2 tiles east of Rome, placed by Anna")
end)

-- a fake game: player 0 is us, player 1 a teammate; pins have an owner, id, position, name and a visibility
local pins = { [0] = {}, [1] = {} }
local nextId = 1
local broadcasts, sounds = 0, {}
local function pinObject(owner, rec)
	return {
		GetID = function() return rec.id end, GetHexX = function() return rec.x end, GetHexY = function() return rec.y end,
		GetName = function() return rec.name end, SetName = function(_, n) rec.name = n end,
		IsVisible = function(_, viewer) return owner == viewer or rec.shared == true end,
		SetVisibility = function(_, v) rec.visibility = v end,
	}
end
local function config(owner)
	return {
		GetMapPins = function() local t = {}; for id, rec in pairs(pins[owner]) do t[id] = pinObject(owner, rec) end; return t end,
		GetMapPin = function(_, x, y)
			for _, rec in pairs(pins[owner]) do if rec.x == x and rec.y == y then return pinObject(owner, rec) end end
			local rec = { id = nextId, x = x, y = y, name = "" }
			nextId = nextId + 1
			pins[owner][rec.id] = rec
			return pinObject(owner, rec)
		end,
		GetMapPinID = function(_, id) local rec = pins[owner][id]; return rec and pinObject(owner, rec) or nil end,
		DeleteMapPin = function(_, id) pins[owner][id] = nil end,
	}
end
Game = Game or {}
Game.GetLocalPlayer = function() return 0 end
Game.GetPlayers = function() return { { GetID = function() return 0 end }, { GetID = function() return 1 end } } end
PlayerConfigurations = { [0] = config(0), [1] = config(1) }
Network = { BroadcastPlayerInfo = function() broadcasts = broadcasts + 1 end }
UI = UI or {}
UI.PlaySound = function(name) table.insert(sounds, name) end
GameConfiguration = { IsAnyMultiplayer = function() return false end }

test("create: the game's own call makes the pin, name set, broadcast", function()
	assert(MapPins.Create(5, 6, "Iron here"))
	eq(broadcasts, 1)
	eq(sounds[#sounds], "Map_Pin_Add")
	local own = MapPins.OwnAt(5, 6)
	eq(own.name, "Iron here")
	eq(own.mine, true)
	eq(MapPins.OwnAt(1, 1), nil)
	-- an empty name is valid
	assert(MapPins.Create(7, 7, ""))
	eq(MapPins.OwnAt(7, 7).name, "")
end)

test("rename and delete", function()
	local own = MapPins.OwnAt(5, 6)
	assert(MapPins.Rename(own.id, "Copper"))
	eq(MapPins.OwnAt(5, 6).name, "Copper")
	assert(MapPins.Delete(own.id))
	eq(sounds[#sounds], "Map_Pin_Remove")
	eq(MapPins.OwnAt(5, 6), nil)
	eq(MapPins.Delete(own.id), false)		-- already gone
	eq(MapPins.Rename(own.id, "x"), false)
end)

test("teammates' pins show only when visible to us; names at a plot", function()
	pins[1][50] = { id = 50, x = 9, y = 9, name = "Ours?", shared = false }
	eq(#MapPins.AtPlot(9, 9), 0)
	pins[1][50].shared = true
	eq(#MapPins.AtPlot(9, 9), 1)
	eq(MapPins.AtPlot(9, 9)[1].mine, false)
	eq(MapPins.OwnAt(9, 9), nil)
	eq(MapPins.NamesAt(9, 9)[1], "Ours?")
end)

test("a broken API never raises", function()
	PlayerConfigurations = {}
	eq(#MapPins.All(), 0)
	eq(MapPins.Create(1, 1, "x"), false)
end)
