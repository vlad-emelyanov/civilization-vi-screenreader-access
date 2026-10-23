-- Scenario: end-game. STATUS: unverified
-- Fixture: any loaded game (early-t60).
-- State: run it in a UI state, NOT GameCore_Tuner: `civctl lua InGameAccess -File util\scenarios\end-game.lua`
--   (a regress script uses the one-liner `lua InGameAccess LuaEvents.ShowEndGame(Game.GetLocalPlayer())`).
-- Then press: Escape (or Enter) ends the defeat movie -> "End game menu, Tab switches pages ...", Tab = next page, Control+Tab = previous page,
--   Down/Up move, Space reads more, Enter presses a button (Main menu leaves the game: do not press it on a game you still need).
-- Notes: engine-legit: it is LuaEvents.ShowEndGame(playerID), the event the game's own options menu raises for "Retire" after a win. The
--   local player has not won, so the screen is the defeat variant (PlayerDefeatedData, "DEFEAT_DEFAULT"); no player is really defeated and no
--   game state changes. To see the victory variant a real victory is needed (Events.TeamVictory is raised by the engine only).
--   Closing: One more turn is only offered when the Defeats row allows it; "Main menu" leaves the game.
local me = Game.GetLocalPlayer()
if me == nil or me < 0 then error("scenario end-game: no local player") end
LuaEvents.ShowEndGame(me)
print("scenario end-game: ShowEndGame raised for player " .. tostring(me))
