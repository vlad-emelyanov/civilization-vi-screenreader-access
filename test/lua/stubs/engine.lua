-- Minimal engine stubs: Locale, Keys/KeyEvents, UI timing, Game. Returns the Strings table so tests can add translations.
local Strings = {
	LOC_DIRECTION_EAST = "East", LOC_DIRECTION_NORTH_EAST = "North-East", LOC_DIRECTION_NORTH = "North",
	LOC_DIRECTION_NORTH_WEST = "North-West", LOC_DIRECTION_WEST = "West", LOC_DIRECTION_SOUTH_WEST = "South-West",
	LOC_DIRECTION_SOUTH = "South", LOC_DIRECTION_SOUTH_EAST = "South-East",
	LOC_DIPLOPANEL_UNMET_PLAYER = "Unmet Player",
}

-- Locale.Lookup(tag, ...) -> the translation (or the tag itself when unknown, like the real game); {1_x} {2_x} are
-- replaced by the extra arguments.
Locale = {
	Lookup = function(tag, ...)
		if tag == nil then return "" end
		local text = Strings[tag] or tag
		local args = { ... }
		text = text:gsub("{(%d+)_[%w_]*}", function(n) return tostring(args[tonumber(n)] or "") end)
		return text
	end,
}

Keys = { VK_UP = 38, VK_DOWN = 40, VK_LEFT = 37, VK_RIGHT = 39, VK_HOME = 36, VK_END = 35, VK_RETURN = 13,
	VK_SPACE = 32, VK_ESCAPE = 27, VK_DELETE = 46, VK_TAB = 9, VK_PRIOR = 33, VK_NEXT = 34, I = 73 }
for i = 13, 24 do Keys["VK_F" .. i] = 100 + i end
KeyEvents = { KeyDown = 1, KeyUp = 2 }

-- A fake input struct: Input{ key = Keys.VK_UP, up = true, shift = true }
function Input(spec)
	return {
		GetMessageType = function() return spec.up and KeyEvents.KeyUp or KeyEvents.KeyDown end,
		GetKey = function() return spec.key end,
		IsShiftDown = function() return spec.shift == true end,
		IsControlDown = function() return spec.ctrl == true end,
		IsAltDown = function() return spec.alt == true end,
	}
end

Clock = { now = 0 }
UI = { GetElapsedTime = function() return Clock.now end }
Game = { GetLocalPlayer = function() return 0 end, GetCurrentGameTurn = function() return 1 end }

-- Calls that code once assumed and the engine does NOT have (verified with civctl lua). A hand-made stub accepts any method, so a test stub
-- for such an object goes through NoSuchEngineCalls: calling one of them raises instead of answering. Add a name here when the game proves
-- one wrong; every NEW engine call is verified once in the game with `civctl lua` (stubs cannot tell).
NO_SUCH_ENGINE_CALLS = {
	BuildQueue = { "CurrentlyBuilding" },			-- the production is GetCurrentProductionTypeHash
	CityGrowth = { "GetHousingMultiplier" },		-- the housing growth factor is GetHousingGrowthModifier
}
function NoSuchEngineCalls( object, kind )
	for _, name in ipairs( NO_SUCH_ENGINE_CALLS[ kind ] or {} ) do
		object[ name ] = function() error( "the engine has no " .. kind .. ":" .. name .. "()" ) end
	end
	return object
end

return Strings
