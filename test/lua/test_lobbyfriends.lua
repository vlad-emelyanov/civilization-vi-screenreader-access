-- KeyNavSetup_ListingHasPlayer: finds a friend's game in the lobby list by host name and player list.
stub("engine")
include("ScreenReader")
include("KeyNavSetup")

test("the host's default game name matches", function()
	eq(KeyNavSetup_ListingHasPlayer("Joe4", "Joe4's Game", ""), true)
end)

test("a longer name that starts the same does not match", function()
	eq(KeyNavSetup_ListingHasPlayer("Joe", "Joe4's Game", "Ann[NEWLINE]Joe4@123"), false)
end)

test("any seat of the player list matches, also the last one with its id", function()
	eq(KeyNavSetup_ListingHasPlayer("Ann", "Weekend game", "Ann[NEWLINE]Joe4@123"), true)
	eq(KeyNavSetup_ListingHasPlayer("Joe4", "Weekend game", "Ann[NEWLINE]Joe4@123"), true)
end)

test("names with pattern characters are compared as plain text", function()
	eq(KeyNavSetup_ListingHasPlayer("A.b%", "Weekend game", "A.b%[NEWLINE]Bob"), true)
	eq(KeyNavSetup_ListingHasPlayer("A.b%", "Weekend game", "Axb%[NEWLINE]Bob"), false)
end)

test("no name or no list is no match", function()
	eq(KeyNavSetup_ListingHasPlayer("", "Game", "Ann"), false)
	eq(KeyNavSetup_ListingHasPlayer(nil, "Game", "Ann"), false)
	eq(KeyNavSetup_ListingHasPlayer("Ann", nil, nil), false)
end)
