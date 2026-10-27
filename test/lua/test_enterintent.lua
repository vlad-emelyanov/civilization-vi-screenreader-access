-- What Enter does next (N and Enter share HubAnnounce.EnterIntentKind), attack-pending expiry, armed-build wording, stale arrival.
-- Pure functions extracted from the sources (the modules need the whole hub stub, see test_hubmodules.lua).
local function extract(file, name)
	local f = assert(io.open("ScreenReaderAccess/Assets/UI/Accessibility/" .. file, "rb"))
	local src = f:read("*a"):gsub("\r\n", "\n")
	f:close()
	local body = src:match("(function " .. name:gsub("%.", "%%.") .. ".-\nend)\n")
	assert(body, name .. " not found")
	assert(loadstring((body:gsub("(%w+):(%w+)", "%1")), name))()
end
HubAnnounce, HubSettle, HubCore = {}, {}, {}
extract("HubAnnounce.lua", "HubAnnounce.EnterIntentKind")
extract("HubCore.lua", "HubCore.AttackPendingIsActive")
extract("HubSettle.lua", "HubSettle.ArmedTextFor")
extract("HubSettle.lua", "HubSettle.ArrivalStaleText")
extract("HubSettle.lua", "HubSettle.ArmedBuildProblem")
HubSettle.ActionPhrase = function(a) return "activates " .. a.what end
ATTACK_PENDING_SECONDS = 8

test("EnterIntentKind decision table", function()
	eq(HubAnnounce.EnterIntentKind(false, false), nil, "nothing")
	eq(HubAnnounce.EnterIntentKind(false, true), "build", "armed build")
	eq(HubAnnounce.EnterIntentKind(true, false), "attack", "attack under way")
	eq(HubAnnounce.EnterIntentKind(true, true), "attack", "attack wins")
end)

test("AttackPendingIsActive expires after 8 seconds", function()
	local p = { time = 100, id = 3 }
	eq(HubCore.AttackPendingIsActive(nil, 100), false, "none")
	eq(HubCore.AttackPendingIsActive(p, 100), true, "just now")
	eq(HubCore.AttackPendingIsActive(p, 107.9), true, "7.9 s")
	eq(HubCore.AttackPendingIsActive(p, 108), false, "8 s")
end)

test("Armed text names the improvement and the unit", function()
	eq(HubSettle.ArmedTextFor({ name = "Mine" }, "Builder"), "Enter builds Mine with the Builder", "build")
	eq(HubSettle.ArmedTextFor({ name = "Mine" }, nil), "Enter builds Mine", "no unit name")
	eq(HubSettle.ArmedTextFor({ name = "x", act = { what = "Euclid" } }, "Great Scientist"), "Enter activates Euclid", "act")
end)

test("Stale arrival text", function()
	eq(HubSettle.ArrivalStaleText("Mine", "a district stands there"), "Mine is no longer possible here: a district stands there. X lists other tiles", "reason")
	eq(HubSettle.ArrivalStaleText("Mine", ""), "Mine is no longer possible here. X lists other tiles", "no reason")
end)

test("Water tile or embarked builder: never judged stale", function()
	local unit = setmetatable({}, { __call = function() return true end })
	local plot = setmetatable({}, { __call = function() return false end })
	eq(HubSettle.ArmedBuildProblem(unit, plot, { type = "IMPROVEMENT_FISHING_BOATS", hash = 1 }, true), nil, "embarked")
	unit = setmetatable({}, { __call = function() return false end })
	plot = setmetatable({}, { __call = function() return true end })
	eq(HubSettle.ArmedBuildProblem(unit, plot, { type = "IMPROVEMENT_FISHING_BOATS", hash = 1 }, true), nil, "water")
end)
