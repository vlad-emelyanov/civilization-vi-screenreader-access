-- DiplomacyIntel.lua: wording and order of the intel report items, the visibility rules of the gathering, empty cases
local Strings = stub("engine")
include("ScreenReader")
include("DiplomacyIntel")

local function Texts(items)
	local out = {}
	for i, item in ipairs(items) do out[i] = item.text end
	return out
end

test("signed numbers and turns left", function()
	eq(DiplomacyIntel.Signed(6), "plus 6")
	eq(DiplomacyIntel.Signed(-3), "minus 3")
	eq(DiplomacyIntel.Signed(0), "zero")
	eq(DiplomacyIntel.TurnsLeft(30, 100, 116), 14)
	eq(DiplomacyIntel.TurnsLeft(30, 100, 140), 0)
	eq(DiplomacyIntel.TurnsLeft(0, 100, 116), nil)
	eq(DiplomacyIntel.TurnsLeft(nil, 100, 116), nil)
end)

test("relationship: state and total first, reasons by magnitude, grievances last", function()
	local items = DiplomacyIntel.BuildItems({ relationship = {
		state = "Friendly", note = "Friends for 8 more turns",
		modifiers = { { score = -3, text = "Your military is weak" }, { score = 12, text = "Same religion" }, { score = 6, text = "Open borders" }, { score = -3, text = "Settled near them" } },
		grievances = { direction = "them", total = 40, perTurn = -1, log = { { turn = 90, amount = 20, text = "You declared war" } } },
	} })
	listeq(Texts(items), { "Relationship: Friendly. Listed reasons add up to plus 12", "Plus 12: Same religion", "Plus 6: Open borders",
		"Minus 3: Your military is weak", "Minus 3: Settled near them", "Grievances: they hold 40 against you" })
	eq(items[1].detail, "Friends for 8 more turns")
	eq(items[1].section, "Relationship")
	contains(items[6].detail, "Turn 90, 20: You declared war")
	contains(items[6].detail, "Changing by -1 per turn")
end)

test("relationship: the same reason twice is one line with the sum", function()
	local items = DiplomacyIntel.BuildItems({ relationship = { state = "Neutral",
		modifiers = { { score = 3, text = "Unknown Reason" }, { score = 2, text = "Open borders" }, { score = 3, text = "Unknown Reason" } } } })
	listeq(Texts(items), { "Relationship: Neutral. Listed reasons add up to plus 8", "Plus 6: Unknown Reason", "Plus 2: Open borders" })
end)

test("relationship: grievances the other way, none when zero, no total without a score list", function()
	local items = DiplomacyIntel.BuildItems({ relationship = { state = "Neutral", modifiers = {}, grievances = { direction = "you", total = 15 } } })
	listeq(Texts(items), { "Relationship: Neutral", "Grievances: you hold 15 against them" })
	items = DiplomacyIntel.BuildItems({ relationship = { state = "At war" } })
	listeq(Texts(items), { "Relationship: At war" })
	items = DiplomacyIntel.BuildItems({ relationship = { state = "Neutral", modifiers = { { score = 2, text = "x" } }, grievances = { direction = "you", total = 0 } } })
	eq(#items, 2)
end)

test("agendas: visible with description, hidden ones say what is needed, none", function()
	local items = DiplomacyIntel.BuildItems({ agendas = {
		agendas = { { name = "Darwinist", text = "Likes civs that research" } },
		hidden = { { count = 1, level = "Open", hint = "Reach Access Level Open" }, { count = 2, level = "Secret" } } } })
	listeq(Texts(items), { "Darwinist: Likes civs that research", "Hidden agenda, not known yet: needs access level Open",
		"2 hidden agendas, not known yet: needs access level Secret" })
	eq(items[2].detail, "Reach Access Level Open")
	items = DiplomacyIntel.BuildItems({ agendas = { agendas = {}, hidden = {}, noneText = "No random agenda" } })
	listeq(Texts(items), { "No random agenda" })
	items = DiplomacyIntel.BuildItems({ agendas = { agendas = {}, hidden = {} } })
	listeq(Texts(items), { "No agendas known" })
end)

test("agreements: deal sides, turns left, other agreements, empty", function()
	local items = DiplomacyIntel.BuildItems({ agreements = {
		deals = {
			{ mine = { { kind = "gold", amount = 5 } }, theirs = { { kind = "resource", name = "Silk", amount = 1 } }, left = 14 },
			{ mine = {}, theirs = { { kind = "agreement", name = "Open Borders" } } },
		},
		others = { { text = "Declared Friendship", left = 1 }, { text = "Alliance: Military, level 2", detail = "+3 combat strength", left = 20 }, { text = "Delegation" } },
	} })
	listeq(Texts(items), { "You give 5 gold per turn; they give Silk, 1; 14 turns left", "They give Open Borders",
		"Declared Friendship, 1 turn left", "Alliance: Military, level 2, 20 turns left", "Delegation" })
	eq(items[4].detail, "+3 combat strength")
	listeq(Texts(DiplomacyIntel.BuildItems({ agreements = { deals = {}, others = {} } })), { "No agreements" })
end)

test("their relations: named, unnamed (not met), empty", function()
	local items = DiplomacyIntel.BuildItems({ relations = {
		{ kind = "war", name = "Egypt" }, { kind = "allied", name = "Rome" }, { kind = "friend", name = "Sumeria" },
		{ kind = "denounced", name = "Greece" }, { kind = "war" }, { kind = "other", name = "Kongo", state = "Open Borders" } } })
	listeq(Texts(items), { "At war with Egypt", "Allied with Rome", "Declared friend of Sumeria", "Denounced, Greece",
		"At war with a civilization you have not met", "Relationship with Kongo: Open Borders" })
	listeq(Texts(DiplomacyIntel.BuildItems({ relations = {} })), { "They have no relations with other civilizations you know of" })
end)

test("access: level, what it gives, how to raise it, details", function()
	local items = DiplomacyIntel.BuildItems({ access = { level = "Limited", gives = { "Their cities", "Their wars" }, next = { "Their gold" },
		sources = { "Delegation" }, needs = { "Send an embassy", "Declare friendship" } } })
	eq(#items, 1)
	eq(items[1].text, "Access level: Limited. Gives Their cities, Their wars. To raise it: Send an embassy; Declare friendship")
	eq(items[1].detail, "Giving you access now: Delegation. The next level gives Their gold")
	items = DiplomacyIntel.BuildItems({ access = { level = "None", gives = {}, next = {}, sources = {}, needs = {} } })
	eq(items[1].text, "Access level: None")
	eq(items[1].detail, nil)
end)

test("gossip: newest first, turn in each item, cap of 20, empty", function()
	local list = {}
	for i = 1, 25 do list[i] = { turn = i, text = "Event " .. i } end
	local items = DiplomacyIntel.BuildItems({ gossip = list })
	eq(#items, 20)
	eq(items[1].text, "Turn 25: Event 25")
	eq(items[20].text, "Turn 6: Event 6")
	listeq(Texts(DiplomacyIntel.BuildItems({ gossip = {} })), { "No gossip yet" })
end)

test("groups come in order, keys are unique and a group that is not gathered is left out", function()
	local items = DiplomacyIntel.BuildItems({
		gossip = { { turn = 5, text = "A" } }, relationship = { state = "Neutral" }, access = { level = "None" }, relations = {},
		agreements = { deals = {}, others = {} } })
	local sections = {}
	local keys = {}
	for _, item in ipairs(items) do
		if sections[#sections] ~= item.section then sections[#sections + 1] = item.section end
		eq(keys[item.key], nil)
		keys[item.key] = true
	end
	listeq(sections, { "Relationship", "Agreements", "Their relations", "Access", "Gossip" })
end)

test("a group whose wording fails is logged and skipped, the others stay", function()
	ClearPrinted()
	local items = DiplomacyIntel.BuildItems({ relationship = { state = "Neutral" }, access = { gives = {} } })		-- access has no level: error
	eq(#items, 1)
	eq(items[1].section, "Relationship")
	contains(Printed[1], "DiplomacyIntel build error (access)")
end)

test("summary line", function()
	local text = DiplomacyIntel.SummaryText({
		relationship = { state = "Friendly", modifiers = { { score = 8, text = "a" }, { score = 4, text = "b" } } },
		agendas = { agendas = { { name = "Darwinist", text = "x" } }, hidden = { { count = 1 } } },
		agreements = { deals = { { mine = {}, theirs = {} } }, others = { { text = "Delegation" } } },
		relations = { { kind = "war", name = "Egypt" }, { kind = "allied", name = "Rome" } } })
	eq(text, "Relationship plus 12. Agendas: Darwinist, 1 hidden. 2 agreements. At war with 1 civilization. I opens the full intel report")
	text = DiplomacyIntel.SummaryText({ relationship = { state = "Neutral", modifiers = {} }, agendas = { agendas = {}, hidden = {} },
		agreements = { deals = {}, others = {} }, relations = {} })
	eq(text, "Relationship neutral. No agreements. I opens the full intel report")
end)

test("world relations: wars first, empty wars say so, groups", function()
	local items = DiplomacyIntel.WorldBuild({ wars = { { a = "Egypt", b = "Rome" }, { a = "You", b = "Greece", youA = true } },
		alliances = { { a = "Rome", b = "Sumeria", kind = "allied" }, { a = "You", b = "Egypt", youA = true, kind = "friend" } },
		denunciations = { { a = "Greece", b = "Kongo" } } })
	listeq(Texts(items), { "Egypt at war with Rome", "You are at war with Greece", "Rome allied with Sumeria", "You and Egypt are declared friends",
		"Denunciation between Greece and Kongo" })
	eq(items[1].section, "Wars")
	eq(items[3].section, "Friends and alliances")
	eq(items[5].section, "Denunciations")
	items = DiplomacyIntel.WorldBuild({ wars = {}, alliances = {}, denunciations = {} })
	listeq(Texts(items), { "No wars between civilizations you have met" })
	items = DiplomacyIntel.WorldBuild({ wars = {}, alliances = { { a = "Rome", b = "Sumeria", kind = "allied" } }, denunciations = {} })
	listeq(Texts(items), { "No wars between civilizations you have met", "Rome allied with Sumeria" })
end)

-- ---------------------------------------------------------------------------
-- Gathering from a fake game: the visibility rules of the game's own panels
-- ---------------------------------------------------------------------------
local function Fake()
	local access = 1
	local met = { [1] = { [0] = true, [2] = true, [3] = true }, [0] = { [1] = true, [2] = true }, [2] = { [0] = true, [1] = true }, [3] = { [1] = true } }
	local states = { [0] = { [1] = 1, [2] = 0, [3] = 0 }, [1] = { [0] = 1, [2] = 3, [3] = 2 }, [2] = { [0] = 0, [1] = 3, [3] = 0 }, [3] = { [0] = 0, [1] = 2, [2] = 0 } }
	local rows = {
		[0] = { Name = "Neutral", StateType = "DIPLO_STATE_NEUTRAL", Hash = 0 }, [1] = { Name = "Friendly", StateType = "DIPLO_STATE_FRIENDLY", Hash = 1 },
		[2] = { Name = "At war", StateType = "DIPLO_STATE_WAR", Hash = 2 }, [3] = { Name = "Allied", StateType = "DIPLO_STATE_ALLIED", Hash = 3 },
	}
	GameInfo = {
		DiplomaticStates = rows,
		Agendas = { [10] = { Name = "Darwinist", Description = "Likes research" }, [11] = { Name = "Hoarder", Description = "Likes gold" }, [12] = { Name = "Warlike", Description = "Likes war" } },
		Visibilities = { [0] = { Name = "None" }, [1] = { Name = "Limited" }, [2] = { Name = "Open" }, [3] = { Name = "Secret" } },
		Gossips = function() return function() return nil end end,
		DiplomaticVisibilitySources = function() return function() return nil end end,
	}
	DiplomaticStates = { NEUTRAL = 0 }
	local function Player(id, isAI)
		local p = {}
		function p:GetID() return id end
		function p:IsAI() return isAI end
		function p:IsHuman() return not isAI end
		function p:GetDiplomacy()
			return {
				HasMet = function(_, other) return met[id][other] == true end,
				GetVisibilityOn = function() return access end,
				IsAtWarWith = function(_, other) return states[id][other] == 2 end,
			}
		end
		function p:GetDiplomaticAI()
			return {
				GetDiplomaticStateIndex = function(_, other) return states[id][other] end,
				GetDiplomaticModifiers = function() return { { Score = 4, Text = "LOC_A" }, { Score = 0, Text = "LOC_ZERO" }, { Score = -2, Text = "LOC_B" } } end,
			}
		end
		function p:GetAgendasAndVisibilities()
			return { { Agenda = 10, Visibility = 0 }, { Agenda = 11, Visibility = 2 }, { Agenda = 12, Visibility = 3 } }
		end
		return p
	end
	Players = { [0] = Player(0, false), [1] = Player(1, true), [2] = Player(2, true), [3] = Player(3, true) }
	PlayerManager = { GetAliveMajors = function() return { Players[0], Players[1], Players[2], Players[3] } end }
	PlayerConfigurations = {}
	for id, civ in pairs({ [0] = "Rome", [1] = "Egypt", [2] = "Greece", [3] = "Kongo" }) do
		PlayerConfigurations[id] = {
			GetCivilizationShortDescription = function() return civ end, GetLeaderName = function() return "Leader of " .. civ end,
			IsHuman = function() return id == 0 end,
		}
	end
	Game.GetGossipManager = function() return { GetRecentVisibleGossipStrings = function() return { { "Egypt built a wonder", 7 }, { "Egypt founded a city", 9 } } end } end
	return { SetAccess = function(v) access = v end }
end

test("gather: agendas follow the access level, hidden ones name the level needed", function()
	local fake = Fake()
	local snap = DiplomacyIntel.Gather(1)
	listeq(Texts(DiplomacyIntel.BuildItems({ agendas = snap.agendas })), { "Darwinist: Likes research", "Hidden agenda, not known yet: needs access level Open",
		"Hidden agenda, not known yet: needs access level Secret" })
	fake.SetAccess(2)
	snap = DiplomacyIntel.Gather(1)
	listeq(Texts(DiplomacyIntel.BuildItems({ agendas = snap.agendas })), { "Darwinist: Likes research", "Hoarder: Likes gold", "Hidden agenda, not known yet: needs access level Secret" })
end)

test("gather: relationship uses the non-zero modifiers of the game", function()
	Fake()
	local snap = DiplomacyIntel.Gather(1)
	listeq(Texts(DiplomacyIntel.BuildItems({ relationship = snap.relationship })), { "Relationship: Friendly. Listed reasons add up to plus 2", "Plus 4: LOC_A", "Minus 2: LOC_B" })
end)

test("gather: their relations name only civilizations you have met, neutral ones are not listed", function()
	Fake()
	local snap = DiplomacyIntel.Gather(1)
	-- Egypt (1) toward the others: Greece (2) is allied with Egypt, Kongo (3) at war with Egypt but not met by you (0)
	listeq(Texts(DiplomacyIntel.BuildItems({ relations = snap.relations })), { "Allied with Greece", "At war with a civilization you have not met" })
end)

test("gather: a failing group is skipped, the others stay, gossip comes with turns", function()
	Fake()
	ClearPrinted()
	local snap = DiplomacyIntel.Gather(1)
	eq(snap.agreements, nil)		-- no DealManager in the fake
	istrue(snap.gossip ~= nil)
	local gossip = DiplomacyIntel.BuildItems({ gossip = snap.gossip })
	listeq(Texts(gossip), { "Turn 9: Egypt founded a city", "Turn 7: Egypt built a wonder" })
	local found = false
	for _, line in ipairs(Printed) do if line:find("DiplomacyIntel gather error (agreements)", 1, true) then found = true end end
	istrue(found, "the agreements failure was logged")
end)

test("gather world: pairs among the civilizations you have met, with you", function()
	Fake()
	local world = DiplomacyIntel.GatherWorld()
	-- you (0) met Egypt (1) and Greece (2); Egypt-Greece allied; Egypt-Kongo at war but Kongo is not met
	eq(#world.wars, 0)
	eq(#world.alliances, 1)
	eq(world.alliances[1].a, "Egypt")
	eq(world.alliances[1].b, "Greece")
	listeq(Texts(DiplomacyIntel.WorldItems()), { "No wars between civilizations you have met", "Egypt allied with Greece" })
end)
