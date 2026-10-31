-- EmergencyText_Item: the Control+Y entry of an active emergency / scored competition (Gathering Storm).
include("EmergencyText")

local function ctx(over)
	local c = {
		localID = 0, hostile = true, noTarget = false, name = "Emergency: Siege", targetName = "Dido",
		clean = function(t) return t end, playerName = function(id) return "Civ" .. id end,
	}
	for k, v in pairs(over or {}) do c[k] = v end
	return c
end

test("joined hostile emergency: name, target, turns, goal and progress", function()
	local e = { TargetID = 2, HasBegun = true, TurnsLeft = 12, ShortGoalDescription = "Capture Carthage.",
		GoalsTable = { { Name = "Capture Carthage", Completed = true }, { Name = "Hold it", Completed = false } } }
	local text, detail = EmergencyText_Item(e, ctx({ name = "Siege" }))
	eq(text, "Emergency: Siege, against Dido, joined, 12 turns left, goal: Capture Carthage, progress 1 of 2", "text")
	assert(detail:find("Goals: Capture Carthage (done); Hold it (open)", 1, true), detail)
end)

test("not joined yet and the last turn", function()
	local e = { TargetID = 2, HasBegun = false, TurnsLeft = 1 }
	local text = EmergencyText_Item(e, ctx({ name = "Siege" }))
	eq(text, "Emergency: Siege, against Dido, not joined yet, accept or reject it, 1 turn left", "pending")
	text = EmergencyText_Item({ TargetID = 2, HasBegun = true, TurnsLeft = 0 }, ctx({ name = "Siege" }))
	eq(text, "Emergency: Siege, against Dido, joined, ends this turn", "ends")
end)

test("the local player is the target", function()
	local e = { TargetID = 0, HasBegun = true, TurnsLeft = 5, TargetShortGoalDescription = "Survive.",
		GoalsTable = { { Name = "A", Completed = true }, { Name = "B", Completed = false } },
		TargetGoalsTable = { { Name = "Keep your cities", Completed = false } } }
	local text, detail = EmergencyText_Item(e, ctx({ name = "Siege" }))
	eq(text, "Emergency: Siege, against you, you are the target, 5 turns left, goal: Survive, the members completed 1 of 2", "target")
	assert(detail:find("Goals: Keep your cities (open)", 1, true), detail)
end)

test("scored competition: score, how to score and rewards on Space", function()
	local e = { TargetID = -1, HasBegun = true, TurnsLeft = 20, ShortGoalDescription = "Most points", GoalDescription = "Score the most points.",
		ScoresTables = { [0] = 14, [1] = 20 }, MemberIDs = { 1, 0 }, ScoreSourcesTable = { "Build districts", "Train units" },
		MemberRewardsTextFirst = { "+2 Era Score" }, MemberRewardsTextBottom = { "Nothing" }, ExtraRewards = "A gift." }
	local text, detail = EmergencyText_Item(e, ctx({ hostile = false, noTarget = true, name = "Race" }))
	eq(text, "Competition: Race, joined, 20 turns left, goal: Most points, your score 14", "text")
	assert(detail:find("How to score: Build districts; Train units", 1, true), detail)
	assert(detail:find("Members: Civ1 20; you 14", 1, true), detail)
	assert(detail:find("Rewards for the best: +2 Era Score", 1, true), detail)
	assert(detail:find("Rewards for the rest: Nothing", 1, true), detail)
	assert(detail:find("A gift", 1, true), detail)
end)

test("ended emergency", function()
	local text = EmergencyText_Item({ TargetID = 2, HasBegun = true, TurnsLeft = -1 }, ctx({ name = "Siege" }))
	eq(text, "Emergency: Siege, against Dido, ended", "ended")
end)
