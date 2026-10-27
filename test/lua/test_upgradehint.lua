-- HubAnnounce.UpgradeText: wording of the upgrade hint on unit selection (M11)
stub("engine")
include("ScreenReader")
include("HubCore")
include("HubAnnounce")

test("upgrade hint wording", function()
	local pike = { target = "Pike and Shot", available = true, cost = 75 }
	eq(HubAnnounce.UpgradeText(pike, false), "Upgrade to Pike and Shot available, 75 gold, U")
	eq(HubAnnounce.UpgradeText({ target = "Musketman", available = true, cost = 120, resource = "Niter", resourceCost = 10 }, false),
		"Upgrade to Musketman available, 120 gold, 10 Niter, U")
	eq(HubAnnounce.UpgradeText({ target = "Musketman", available = true, cost = 120, resource = "Niter", resourceCost = 0 }, false),
		"Upgrade to Musketman available, 120 gold, U")
	eq(HubAnnounce.UpgradeText(pike, true), "Upgrade available, U")
	local blocked = { target = "Musketman", available = false, reason = "Not enough Gold in treasury" }
	eq(HubAnnounce.UpgradeText(blocked, false), "Upgrade to Musketman: Not enough Gold in treasury")
	eq(HubAnnounce.UpgradeText(blocked, true), nil)
	eq(HubAnnounce.UpgradeText({ target = "Musketman", available = false }, false), "Upgrade to Musketman unavailable")
	eq(HubAnnounce.UpgradeText(nil, false), nil)
end)
