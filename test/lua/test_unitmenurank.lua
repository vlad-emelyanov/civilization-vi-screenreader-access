-- UnitPanel.lua SRMenuRank / SRTribalVillageReason (pure), extracted from the source.
local f = assert(io.open("ScreenReaderAccess/Assets/UI/Panels/UnitPanel.lua", "rb"))
local src = f:read("*a"):gsub("\r\n", "\n")
f:close()
for _, name in ipairs({ "SRIsDestructiveBuild", "SRMenuRank", "SRTribalVillageReason" }) do
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

test("destructive builder actions rank after the main actions", function()
	local function rank(typeName, disabled) return SRMenuRank({ name = "x", typeName = typeName, category = "BUILD", disabled = disabled }, true) end
	eq(rank("UNITOPERATION_REMOVE_IMPROVEMENT"), 3.5, "remove improvement")
	eq(rank("UNITOPERATION_HARVEST_RESOURCE"), 3.5, "harvest")
	eq(rank("UNITOPERATION_PILLAGE"), 3.5, "pillage")
	eq(rank("UNITOPERATION_REMOVE_FEATURE"), 1, "remove feature stays a build")
	eq(rank("UNITOPERATION_REPAIR"), 1, "repair")
	eq(SRMenuRank({ name = "Pillage", typeName = "UNITOPERATION_PILLAGE" }, false), 2, "a soldier's pillage is a main action")
	local a, b, c, d = rank("UNITOPERATION_REMOVE_IMPROVEMENT"), rank("UNITOPERATION_BUILD_IMPROVEMENT"), SRMenuRank({ typeName = "UNITOPERATION_FORTIFY" }, true), SRMenuRank({ typeName = "UNITCOMMAND_DELETE" }, true)
	eq(b < c and c < a and a < d, true, "build < main < destructive < delete")
end)

test("tribal village reason", function()
	eq(SRTribalVillageReason("Too close to Tribal Village", "2 tiles north-west"), "Too close to Tribal Village, 2 tiles north-west", "x")
	eq(SRTribalVillageReason("Danger", "1 tile east"), "Danger", "other")
	eq(SRTribalVillageReason("Too close to Tribal Village", nil), "Too close to Tribal Village", "nil")
end)
