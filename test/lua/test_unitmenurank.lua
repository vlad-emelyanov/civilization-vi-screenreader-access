-- UnitPanel.lua SRMenuRank / SRTribalVillageReason (pure), extracted from the source.
local f = assert(io.open("ScreenReaderAccess/Assets/UI/Panels/UnitPanel.lua", "rb"))
local src = f:read("*a"):gsub("\r\n", "\n")
f:close()
for _, name in ipairs({ "SRMenuRank", "SRTribalVillageReason" }) do
	local body = src:match("(function " .. name .. "%(.-\nend)\n")
	assert(body, name .. " not found")
	assert(loadstring((body:gsub("(%w+):(%w+)", "%1")), name))()
end

test("builder order", function()
	local list = {
		{ name = "Move", typeName = "UNITOPERATION_MOVE_TO", category = "MOVE" },
		{ name = "Build Farm", category = "BUILD", disabled = true },
		{ name = "Build Mine", category = "BUILD" },
		{ name = "Fortify", typeName = "UNITOPERATION_FORTIFY" },
		{ name = "Delete", typeName = "UNITCOMMAND_DELETE" },
		{ name = "Promote", typeName = "PROMOTION" },
	}
	local r = {}
	for i, e in ipairs(list) do r[i] = SRMenuRank(e, true) end
	eq(table.concat(r, ","), "2,3,1,2,4,0", "ranks")
	eq(SRMenuRank(list[2], false), 2, "non builder build action is main")
end)

test("tribal village reason", function()
	eq(SRTribalVillageReason("Too close to Tribal Village", "2 tiles north-west"), "Too close to Tribal Village, 2 tiles north-west", "x")
	eq(SRTribalVillageReason("Danger", "1 tile east"), "Danger", "other")
	eq(SRTribalVillageReason("Too close to Tribal Village", nil), "Too close to Tribal Village", "nil")
end)
