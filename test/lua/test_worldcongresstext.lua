-- WorldCongressText.lua: sentences for the World Congress screens
stub("engine")
include("WorldCongressText")

-- GetVotesandFavorCost: [0] = total cost of 1 vote, [1] of 2 votes ...
local costs = { [0] = 0, [1] = 10, [2] = 30, [3] = 60, [4] = 100, MaxVotes = 5 }

test("Strip drops trailing dots and spaces", function()
	eq(WCText_Strip("  Hello world. "), "Hello world")
	eq(WCText_Strip(nil), "")
end)

test("CostList: free first vote, then steps", function()
	eq(WCText_CostList(costs, 3), "1st vote free, 2nd vote 10 favor, 3rd vote 20 favor, up to 5 votes")
	eq(WCText_CostList({ [0] = 0, MaxVotes = 1 }, 4), "1st vote free")
end)

test("VoteBlock: allowed changes give nil", function()
	eq(WCText_VoteBlock(0, 1, costs, 5), nil)
	eq(WCText_VoteBlock(1, 1, costs, 10), nil)
	eq(WCText_VoteBlock(2, -1, costs, 0), nil)
end)

test("VoteBlock: reasons", function()
	eq(WCText_VoteBlock(0, -1, costs, 5), "No votes to remove")
	eq(WCText_VoteBlock(1, -1, costs, 5), "At least one vote is needed. Vote for the other option to switch")
	eq(WCText_VoteBlock(1, 1, costs, 9), "Not enough favor, the next vote costs 10 and you have 9")
	eq(WCText_VoteBlock(5, 1, costs, 500), "No more votes available, the maximum is 5")
end)

test("VotesPhrase", function()
	eq(WCText_VotesPhrase(1, "A", 0), "1 vote for A, free")
	eq(WCText_VotesPhrase(2, "B", 10), "2 votes for B, costs 10 favor")
end)

test("ResolutionLine: voted option with target", function()
	local line = WCText_ResolutionLine{ name = "Mercenary Companies", focus = 1, effect = "Cheaper units.", chosen = 1,
		votes = 1, cost = 0, target = nil, needsTarget = true }
	eq(line, "Mercenary Companies, option A: Cheaper units, your votes: 1 vote for A, free, target: none")
end)

test("ResolutionLine: focus on the other option, and no votes", function()
	local d = { name = "Arms Control", focus = 2, effect = "No nukes", chosen = 1, votes = 2, cost = 10, needsTarget = true }
	eq(WCText_ResolutionLine(d), "Arms Control, option B: No nukes, your votes are on option A")
	d.chosen = 0; d.votes = 0
	eq(WCText_ResolutionLine(d), "Arms Control, option B: No nukes, no votes yet")
end)

test("ResolutionLine: key hint and next vote cost", function()
	local costs = { [0] = 0, [1] = 10, [2] = 30, MaxVotes = 3 }
	local d = { name = "Arms Control", focus = 1, effect = "No nukes", chosen = 0, votes = 0, cost = 0, needsTarget = false, costData = costs, hint = true }
	eq(WCText_ResolutionLine(d), "Arms Control, option A: No nukes, no votes yet, equals adds a vote, Left and Right switch option")
	d.hint = false
	eq(WCText_ResolutionLine(d), "Arms Control, option A: No nukes, no votes yet")
	d.chosen = 1; d.votes = 1; d.cost = 0
	eq(WCText_ResolutionLine(d), "Arms Control, option A: No nukes, your votes: 1 vote for A, free, equals adds a vote for 10 favor")
	d.votes = 2; d.cost = 10
	eq(WCText_ResolutionLine(d), "Arms Control, option A: No nukes, your votes: 2 votes for A, costs 10 favor, equals adds a vote for 20 favor, minus removes one")
	d.votes = 3; d.cost = 30
	eq(WCText_ResolutionLine(d), "Arms Control, option A: No nukes, your votes: 3 votes for A, costs 30 favor, maximum votes, minus removes one")
end)

test("NextCostPhrase", function()
	local costs = { [0] = 0, [1] = 10, [2] = 30, MaxVotes = 3 }
	eq(WCText_NextCostPhrase(1, costs), "next vote 10 favor")
	eq(WCText_NextCostPhrase(2, costs), "next vote 20 favor")
	eq(WCText_NextCostPhrase(3, costs), "maximum votes")
	eq(WCText_NextCostPhrase(0, costs), "")
	eq(WCText_NextCostPhrase(1, nil), "")
end)

test("ProposalLine: hint and next step", function()
	local costs = { [0] = 0, [1] = 10, [2] = 30, MaxVotes = 3 }
	eq(WCText_ProposalLine("Denounce Rome", nil, 0, 0, costs, true), "Denounce Rome, no votes yet, equals votes for, minus votes against")
	eq(WCText_ProposalLine("Denounce Rome", nil, 2, 10, costs, false), "Denounce Rome, your votes: 2 votes for, costs 10 favor, equals adds a vote for 20 favor, minus removes one")
	eq(WCText_ProposalLine("Denounce Rome", nil, -1, 0, costs, false), "Denounce Rome, your votes: 1 vote against, minus adds a vote against for 10 favor")
end)

test("ProposalLine", function()
	eq(WCText_ProposalLine("Denounce Rome", "Everybody does.", 0, 0), "Denounce Rome: Everybody does, no votes yet")
	eq(WCText_ProposalLine("Denounce Rome", "", -2, 10), "Denounce Rome, your votes: 2 votes against, costs 10 favor")
	eq(WCText_ProposalLine("Denounce Rome", nil, 1, 0), "Denounce Rome, your votes: 1 vote for")
end)

test("Missing lists what is needed", function()
	eq(WCText_Missing{ { name = "A", needsTarget = true }, { name = "B", needsVote = true, needsTarget = true }, { name = "C" } },
		"A needs a target, B needs a vote and a target")
	eq(WCText_Missing{}, "")
end)

test("ReviewResolution: passed, tie, in effect", function()
	eq(WCText_ReviewResolution{ name = "Mercenary Companies", label = "A", target = "Phoenicia", effect = "Cheaper units.", aVotes = 12, bVotes = 5 },
		"Mercenary Companies: option A passed, target Phoenicia, Cheaper units, votes: A 12, B 5")
	eq(WCText_ReviewResolution{ name = "X", label = "B", tie = true, aVotes = 3, bVotes = 3 }, "X: option B passed by tie breaker, votes: A 3, B 3")
	eq(WCText_ReviewResolution{ name = "X", label = "B", target = "", turnsLeft = 1 }, "X: option B in effect, 1 turn left")
end)

test("ReviewProposal", function()
	eq(WCText_ReviewProposal("Emergency", "Help.", 5, 2), "Emergency passed, 5 for, 2 against. Help")
	eq(WCText_ReviewProposal("Emergency", nil, 1, 4), "Emergency failed, 1 for, 4 against")
end)

test("ResolutionLine: omitName speaks only the option, hints are SRKey tokens", function()
	local d = { name = "Arms Control", focus = 2, effect = "No nukes", chosen = 0, votes = 0, cost = 0, needsTarget = false, hint = true, omitName = true }
	eq(WCText_ResolutionLine(d), "Option B: No nukes, no votes yet, equals adds a vote, Left and Right switch option")
	eq(WCText_ResolutionLine(d), "Option B: No nukes, no votes yet, [KEY:equals|X] adds a vote, [KEY:Left and Right] switch option")
	d.omitName = false
	eq(WCText_ResolutionLine(d), "Arms Control, option B: No nukes, no votes yet, equals adds a vote, Left and Right switch option")
end)
