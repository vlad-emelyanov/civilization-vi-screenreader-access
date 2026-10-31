# Backlog

Every known open item, one bullet each: why it matters, where to look. Current behaviour is in `docs/features.md`; engine facts in `docs/engine-notes.md`. IDs in brackets (M12, G3d, C4 ...) are the original report IDs, searchable in git history. Remove an item when it is done and verified.

## Open bugs

- **Enter opens Governors right after a city attack** (`bug-enter-opens-governors`): not reproduced, only mitigation (a 5 s hold-back logs "Enter held back, end-turn label ..."). Check Lua.log for that line if it recurs.
- **Lugdunum double attack:** an Encampment district attack may fire twice; cause unknown.
- **In-game Load Game hangs at the Continue Game screen** (no speech, Enter does nothing, tuner unreachable; both via Escape > Load Game > confirm and via Network.LeaveGame+LoadGame from the LoadGameMenu state; see engine-notes FORBIDDEN). Unknown whether the game or our LoadScreen.lua causes it: test with the mod disabled. Workaround: load from the main menu. The harness does not detect this hang (status stays running).

## Open features

- **Camp experience hint [G3d]:** one sentence in the camp's Space text in J ("Fighting near it gives your units experience"). Low priority.
- **Combat preview, better tile [G5 stretch]:** "Attacking from the north would add plus 2 flanking"; needs a `SimulateAttackInto` per neighbour tile.
- **District spots, purchasable tiles [G7]:** the "District spots" city report line and production Space only consider owned tiles; the positive wording ("Campus plus 3 ...") is unit-tested only. Check a city that could buy a better tile (`DistrictAdvice.lua`, `PlacementScan.lua`).
- **City-in-danger warning:** the raid line (2+ barbarian soldiers near a city) and the enemy summary exist, but Ostia was captured by England with only attack lines as warning. Needs a rule for at-war civ units near a weakly defended city.
- **Keyboard path for corps/armies from the production panel, queue reordering/removal, the Manager tab** (`Panels/ProductionPanel.lua`).
- **Small speech gaps from play-tests:** a pillaged Library blocking Great Library is not said at pillage time; no danger hint before a Barbarian Galley attack; a city production auto-swap to a newer unit is not announced; auto-explore end is not announced (HubPlaces keeps "exploring" until a player order; idea to probe: a unit the game itself offers as ready for orders (`GetFirstReadyUnit`/next-unit) a few seconds into the turn has stopped exploring, activity alone cannot tell, see engine-notes); WMD/ICBM and PRIORITY_TARGET still use a click.
- **Silent or thin popups:** Suleiman "remove your spies" popup and Escape behaviour unchecked; advisor re-shown over a completed popup not reached.

## Unverified in game (code and unit tests only)

- **Units:** archaeologist, naturalist and rock band activation tiles (no fixture; spawn after Natural History with revealed antiquity sites); blocked-upgrade hint for an unresearched target tech; Deploy/Patrol to a real carrier or airstrip; "Launching" before a real nuke; war-confirm cancel during a nuke strike; corps -> army, fleet/armada names, fleets in real play; coastal raid, sacrifice, hero commands; the `HubPlaces.OrderHint` "Shift+W wakes it" branch (Sleep is refused for every unit tried); which `GetActivityType` an auto-exploring unit has.
- **Barbarians:** scout "escaped" / "killed" lines and "Raid near Rome continues" over real turns (scenario scouts have no tribe and are never flagged: use a fixture's own scout, e.g. `pt-early-t78`); auto-explore "Too close to Tribal Village"; clan conversion; goody hut rewards other than faith and the boost-from-hut line (text function only).
- **Screens:** an actual government change and its anarchy variant; World Congress "You have no vote in this session" (`bug-congress-skipped` is saved after the session), "Proposals submitted", "Joined/Rejected the emergency"; congress turn-start line when a unit is selected (blocker branch verified); deal when Accept vanishes ("names the invalid items", offline only); help entries S (deal) and the congress keys (read in code only); Make peace with a city-state; wonder built popup (`WonderBuiltPopup.lua`, no fixture); end-game victory variant (`Events.TeamVictory`; defeat variant verified); advisor "Tell me more" into the Civilopedia (only the event was fired); Coal/Niter stockpiles, power plants' tile text, railroads; Staging Room client side.
- **Choose Artifact popup (`Popups/ChooseArtifact.lua`):** verified with `choose-artifact.txt` and by hand with a real Archaeologist: Control+N "Choose Artifact" Enter and the End Turn Enter blocker both open it, Enter picks and the great work showcase speaks. Not reached: the one-button variants (goody hut, barbarian camp, heroic relic: no such site in a fixture), the stale-KeyUp guard with a real key hold (the harness never leaves a KeyUp behind), and the pad (LB/RB, Y).
- **Fixtures to build:** Oil + Flight (air and carriers beyond the scenario), an archaeologist with antiquity sites, a wonder built by you.
- **Real pad needed [controller]:** the held-RT-as-Shift rule (Shift+Right while F17 is held), the console app's RT-as-Shift, and the pad aliases of government, religion, trade, great works, rankings, civilopedia and options screens (unit tests only); whether the engine reacts to a pad by itself; Steam Input must be off.
- **Numpad Divide** (closes the era panel, lens keys) never reaches the game from the harness; the real keyboard is untested (Control+E works). A lens turned on with the mouse and the same-frame lens key race cannot be tested.
- **Hotseat / multiplayer** in game, and game modes the user does not own (see `docs/game-content.md`).

## Accepted limitations (do not chase)

- Trade routes have no "turns left" (no field in the route data); the Trade overview filter pulldown, the Reports gossip filters and World Rankings overflow tabs are unreachable.
- Civilopedia reads stats before the description; city specialist "+N each" and builder yield changes are base values; secret-society governors are skipped (not owned).
- The settle browser reads live owner/resource/feature of revealed fogged plots; deal items do not repeat the section name; the deal open focus names the first choosable item; Enter in the Deal section removes an item by design.
- The Religion screen shows stale faith until the next turn (engine); an AI deal "Item no longer available" and an AI deal rejection give no reason (game text); the turn-start block is re-spoken after a popup cut it off (by design).
- Rebase range is not exposed by the engine; the unit-experience API `UnitExperience:CanPromote` does not exist.
- Two upstream Runtime Errors in non-mod files (`CityPanel.lua:1149`, `StrategicView_MapPlacement.lua:321`); upstream `EraReviewPopup.OnGameDebugReturn` errors if hot-reloaded while open.
- A production panel open during a hot reload goes dead (reopen works); the tuner on a hot-reloaded context can reach a stale duplicate state (restart first).
- A city created by a tuner scenario shows a raw `LOC_CITY_NAME_*`; the city capture popup opens through the notification, not by itself.
- Owner complaint "a natural disaster popup holds the turn" is not reproduced: it opens during turn processing (pt-modern-t212 + End Turn), is spoken once and Enter closes it, the turn then continues; the turn naturally waits while it is open. If it still happens, get the exact keys and speech (does Enter reach it while a historic moment or another popup is up?).
- Natural disaster popups have counts only (`GameRandomEvents.GetCurrentTurnEventAtPlot`), no list of pillaged buildings.
- Harness: a contaminated `UserOptions.txt` (`TutorialLevel -1`) makes advisor scripts fail with no advisor popup; check with `python util/testopts.py status`.
