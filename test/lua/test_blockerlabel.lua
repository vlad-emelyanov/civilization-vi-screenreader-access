-- HubAnnounce.BlockerFromLabel: only a real action-panel blocker text is spoken after "Turn not ended".
-- The pure function is extracted here from the source (HubAnnounce itself needs the whole hub stub, see test_hubmodules.lua).
local f = assert(io.open("ScreenReaderAccess/Assets/UI/Accessibility/HubAnnounce.lua", "rb"))
local src = f:read("*a")
f:close()
src = src:gsub("\r\n", "\n")
local body = src:match("(function HubAnnounce%.BlockerFromLabel.-\nend)\n")
assert(body, "BlockerFromLabel not found")
HubAnnounce = {}
assert(loadstring((body:gsub("(%w+):(%w+)", "%1")), "BlockerFromLabel"))()
local fn = HubAnnounce.BlockerFromLabel

test("BlockerFromLabel: only a real blocker text is returned", function()
	local ignored = { "please wait", "next turn", "waiting for other players" }
	eq(fn("UNIT NEEDS ORDERS", ignored), "Unit needs orders", "blocker")
	eq(fn("Please wait", ignored), "", "please wait")
	eq(fn("NEXT TURN", ignored), "", "next turn")
	eq(fn("Waiting for other players", ignored), "", "waiting for players")
	eq(fn("", ignored), "", "empty")
	eq(fn(nil, ignored), "", "nil")
end)
