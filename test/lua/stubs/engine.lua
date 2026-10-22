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
	VK_SPACE = 32, VK_ESCAPE = 27, VK_DELETE = 46 }
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

return Strings
