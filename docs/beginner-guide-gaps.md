# Beginner guide gap analysis (2026-10-26)

## Status (2026-10-26)

Done (verified in game): G1, G2, G3a, G3b, G3c (camp guards, attack party, camp destroyed line), G4 (escort via J M), G5, G6/G8 (settle distance and verdict lines; the verdict wording is only unit-tested, the fixtures did not reach it), G7 (District spots; positive wording unit-tested only, purchasable tiles not checked), G9 (far tech and civic target), G10 (Blind spots).
Still open: G3d, the G5 better-tile stretch, G7 purchasable-tile check, in-game check of the G6/G8 verdicts.

Source: the YouTube video "10 tips for Civilization noobs" (`cciyCn3QKG0`, base game, aimed at first-time 4X players).
Question for each tip: can a blind player using only the mod **learn what the tip asks them to look at, and act on it**,
without trial and error and without reading tiles one by one? Reaching a tile is not enough: a sighted player gets
the answer from icons, colours and tooltips at a glance, so the mod has to give the same answer in one or two keys.

Method: the mod's code and the game's own UI scripts were read; nothing here was checked in the game yet. Engine
hooks named below come from the game files (paths relative to the Steam install) and need a tuner check before
building on them.

## Tip by tip

| # | Tip (paraphrased) | Mod today | Verdict |
|---|---|---|---|
| 1 | Everything is accumulate and spend: cost divided by per-turn yield gives turns | production list reads the game's item text (cost, turns); Control+I city report has the yields; Control+G / Control+Y empire yields | covered |
| 2 | Turn on tile yield icons and the always-on HUD ribbon (every civ's yields at the top) | tile yields are in every cursor read | tile yields covered; **the comparison with other civs is missing** (G2) |
| 3a | Settle the first city in place unless a clearly better tile is close | settler selection compares here with the best; X browser with turns and reasons | covered; the advice could be more decisive (G8) |
| 3b | Build a scout first, a slinger or warrior on higher difficulties | production panel | covered |
| 3c | Research the techs that improve the resources around your cities (the resource tooltip names the tech) | the game's tooltip says "(Requires Mining)", **our tile text does not**; the builder browser lists only tiles improvable *now* | **gap** (G1) |
| 3d | Archery when in trouble; rush Political Philosophy; Military Tradition for the flanking bonus | trees: F search, Enter sets the target, Shift+Enter queues; detail lists direct prerequisites | covered; check that a far target speaks the path and total turns (G9) |
| 3e | Found new cities quickly and set up districts | settle browser; placement mode sorted by adjacency, with tile cost and what gets removed | covered; no "which district fits this city best" overview (G7) |
| 4 | Play lean: just enough military, know when you are threatened | turn-start enemy summary; "spotted" lines; the city-in-danger warning is still open in ingame-plan.md | **partial** (G3, G5, G2 military) |
| 5 | Build wide; amenities; cities 3 to 6 tiles apart are fine | city report amenities; F8 resources and city status; the settle score penalises own cities closer than 5 | covered; spacing is scored but never spoken (G6) |
| 6 | Where to settle: a luxury, enough food and production, closeness to enemies and defensibility, fresh water | SettleScan: rings, luxuries, food and production, water, hills, hazards, danger, foreign borders, advisor picks | strongly covered; the *strategic* part (rivals, own empire, borders) is scored but not spoken (G6) |
| 7 | Escort civilians, use the escort formation | Shift+E; J says enemy civilians are "escorted by" | **gap**: nothing warns that *my* settler walks alone, nothing says a formation is possible (G4) |
| 8 | Kill barbarians early: the scout with "!" has seen you and goes home to start a raid; attack with several units; destroy camps; vision stops camps from spawning | "Barbarian X spotted, N tiles of Rome"; camps in J and in the settle danger; attack preview with damage | **partial**: the barbarian section below (G3), G5, G10 |
| 9 | Balanced game: keep up in science, culture and production against the other civs | F1 rankings per victory type; Control+E era | **gap**: no direct "where do I stand" (G2) |
| 10 | Have fun, try different approaches | | n/a |

## G1. Which tech unlocks my resources (tip 3c)

**Player story.** "My capital has Iron, Horses and Wine. What should I research?" A sighted player hovers each resource
icon and reads "(Requires Bronze Working)". With the mod today they hear "Iron" and nothing about what it needs, and
the builder browser simply leaves those tiles out, so they are invisible exactly when the player is planning research.

**Proposal.**
1. Tile text (cursor and I): after the resource, the same rule the game uses: "Iron, needs Bronze Working to mine" or
   "Wine, Plantation available". Only for resources the player can see (revealed by tech) and for improvements this civ
   can build (respect unique improvements and traits). Short on the cursor read ("Iron, needs Bronze Working"), full
   on I.
2. Builder browser (X with a builder): after the tiles it can improve now, a "Later" group:
   "Later: Iron near Rome, Mine needs Bronze Working, 6 turns of research". Enter on a "Later" tile moves the cursor
   there and says "Not yet: needs Bronze Working. T opens the tech tree on it" (a hint, no automatic jump). The group
   tells the player *why* a tile is missing, so the list doesn't feel broken.
3. Tech and civics trees: techs that unlock an improvement for a resource inside or next to my borders get a phrase
   in their node text: "Animal Husbandry, available, 4 turns, improves 2 Horses and 1 Sheep near your cities".
   A key in the tree (R, "resources") lists those techs, nearest research first: "Bronze Working, 6 turns: Iron near
   Rome. Irrigation, needs Pottery: Wheat near Antium, Bananas near Rome". Enter sets it as the target like Enter on
   a node.
4. City report (Control+I): a "Resources" entry: "Improved: Wheat (Farm). Not improved: Iron, needs Bronze Working;
   Horses, builder can pasture now".

**Engine hooks.** `Base/Assets/UI/ToolTips/PlotToolTip.lua` ~248-340 already implements the rule:
`Improvement_ValidResources` for the resource, the improvement's `PrereqTech` (and `PrereqCivic`), validated against
terrain and feature, `localPlayer:GetTechs():HasTech`. Port that loop into a pure helper (new
`Accessibility/ResourceTech.lua`, unit-testable with `stub("world")`) and share it among the tile text, BuildScan,
the trees and the city report. Turns of research for a tech on the path: the tree already computes turns per node
(TreeText); a path needs the sum over missing prerequisites (shared with G9).

**Edge cases.** A resource not yet revealed (no Bronze Working for Iron) must not be named: PlotDescription already
hides it. Improvements unlocked by a civic (e.g. some uniques) say "needs <civic>". Pillaged improvements belong to
the repair entries, not here. Unique improvements of other civs are skipped.

**Testing.** luatest for the helper (resource + tech table stubs); regress on `early-t60`: cursor on an unimproved
iron tile without Bronze Working, X with a builder shows the Later group, T then R lists the tech.

## G2. Compare yourself with the other civs (tips 2, 4, 9: the HUD ribbon)

**Player story.** "Am I behind?" The video's tip 2 turns on the ribbon so the player always sees every civ's score,
military strength, science, culture, gold and faith; tip 9 uses it to keep a balanced game. V (diplomacy list)
says only "leader, civ, relationship"; F1 is per victory type and is slow to read for this question.

**Proposal.**
1. V list items get the numbers: "Hojo Tokimune, Japan, friendly. Score 212, military 180, science 14, culture 9,
   gold 6, faith 3". Space keeps the long detail. The local player is the first entry ("You, Rome: score 190, ...") so
   the comparison has a reference.
2. A standing line (new key in the hub, candidate Control+R "rank", check keymap.md first): "Among 4 known
   civilizations: score 2nd, military 1st, science 3rd, culture 4th, gold 2nd, faith 1st. Weakest: culture, Japan
   leads with 18 per turn". This is the balanced-game check in one key, and shows when the player is falling behind.
3. Optional turn-start nudge (off by default, an option later): when the player drops to last in science or
   military among known civs, once: "Science: you are now last of 4".

**Engine hooks.** `Base/Assets/UI/DiplomacyRibbon.lua` ~514-530: `pPlayer:GetScore()`,
`Players[id]:GetStats():GetMilitaryStrengthWithoutTreasury()`, `GetTechs():GetScienceYield()`,
`GetCulture():GetCultureYield()`, gold and faith yields; Gathering Storm adds `GetFavor()`
(`DLC/Expansion2/UI/Replacements/DiplomacyRibbon_Expansion2.lua` ~77). Shown only for met players
(`GetDiplomacy():HasMet`). Respect the same hide rules: score only with `VICTORY_SCORE` + `CAPABILITY_DISPLAY_SCORE`,
military only with `VICTORY_CONQUEST`, the yields only with `CAPABILITY_DISPLAY_TOP_PANEL_YIELDS`, and the ribbon's
`isMasked` case (check when it applies: hotseat / multiplayer masking). Never rank unmet civs ("4 known
civilizations", not "of 8").

**Testing.** luatest for the ranking wording (ties, one known civ, hidden categories); regress on a fixture with 2+
met civs (`medieval-t100`): V first item is "You", standing line names the weakest category.

## G3. The barbarian experience (tips 4 and 8)

The video's barbarian advice is a whole loop: notice the scout, stop it before it gets home, if it gets away expect
a raid, find and kill the camp with more than one unit, keep vision so new camps can't appear. Today the mod has the
pieces of *seeing* (spotted lines, turn-start movement summary, camps in J, danger in the settle score) but nothing
that turns them into the *alarm* the "!" gives a sighted player, and nothing about the raid that follows.

**What exists.** `HubEvents` "Barbarian Warrior spotted, 2 tiles north of Rome" (once per unit per 10 turns, max 4 per
turn); `HubEnemies` turn-start line with "moved toward / away from <city>", new, wounded, out of sight (snapshot of
hostile units within 6 tiles of a city or 3 of a unit); J places list remembers seen camps (`HubPlaces.m_seen`,
camps by `ImprovementVisibilityChanged` / `ImprovementAddedToMap` / `RemovedFromMap`); notifications BARBARIANS_SIGHTED
and NEW_BARBARIAN_CAMP go through the generic notification speech.

### G3a. Scout alarm

**Player story.** "A barbarian scout came close to my city, then walked off. Should I worry?" In the game, the "!"
over the scout means it found a target and is going home to spawn a raid party. That is the moment to chase it.

**Proposal.**
- When a barbarian scout is (or was last turn) within 3 tiles of one of my cities or inside my borders:
  "Alarm: Barbarian Scout has seen Rome, 3 tiles east. If it gets back to its camp, a raid follows. Kill it: X targets
  it". Spoken once per scout, interrupting, at the top of the turn-start lines.
- Next turns while it is visible: in the HubEnemies line "Barbarian Scout heading away from Rome, toward its camp
  4 tiles north-east" (name the camp only if the player has seen it: `HubPlaces.IsCampRemembered`).
- If it goes out of sight after the alarm: "Barbarian Scout escaped. Expect a raid from the north-east in a few turns".
  This sets a "raid expected" state (G3b).
- If it dies: "Barbarian Scout killed, no raid from it" (closes the state).
- J places list gets a "Threats" category on top while any of this is active: the scout (cursor, M sends the
  fastest unit that can catch it: reuse "send a unit", sorted by turns).

**Engine hook (needs research).** No game UI script reads a "found a target" state (searched Base and both
expansions: only notifications and camp icons). The "!" is probably an animation state of the unit model. Things to
try in the tuner on a barbarian scout (player 63, `Players[63]:GetUnits()`): `unit:GetActivityType()`,
`unit:GetMilitaryFormation()`, any `UnitAI`/operation accessors, and `Events.UnitActivityChanged` /
`Events.UnitAnimation*` listeners in the hub. If nothing exposes it, use the heuristic above (scout within its sight
radius of a city, then moving away), worded as "has seen", which is true the moment our city is in its sight
(scout sight radius from `GameInfo.Units.UNIT_BARBARIAN_SCOUT` / the scout row's `BaseSightRange`, check the
barbarian unit type name).

### G3b. Raid warning and city in danger

**Player story.** "Am I about to lose my builder or city?" The player needs to know a group is coming and how
dangerous it is, and which of their own units can answer.

**Proposal.**
- When 2 or more barbarian soldiers are visible within 5 tiles of a city, or any within 3 tiles of an unescorted
  civilian: "Raid: 3 barbarians near Rome: Horseman 3 tiles north, 2 Spearmen 4 tiles north. Rome defense 15, walls
  none. Your nearest soldiers: Warrior in Rome, Slinger 2 tiles west". One line at turn start, then only on change.
- This closes the long-open city-in-danger warning in ingame-plan.md; same rule for at-war civ units ("Japan: 4 units
  near Antium").
- Civilian safety: for each of my settlers and builders with a hostile soldier within 2 tiles (one move of most early
  units) and no escort: "Builder near Rome in danger: Barbarian Horseman 2 tiles east. Move it into Rome: Enter on
  this line" (Enter orders the move to the nearest city or friendly soldier; G4).
- Raid expected (from G3a): repeated in the N "what's next" line until it ends: "Raid expected from the north-east".

### G3c. Camps: find, judge, destroy

**Player story.** "Where is the camp, how strong is it, can I take it?"
- J camps entry gets distance from my nearest city and what was seen guarding it: "Barbarian camp, 7 tiles north-east
  of Rome, guarded by Spearman (last seen 2 turns ago)". Space: "Destroying it gives 50 gold (base game: the camp reward
  amount; check the actual gold in the event) and stops barbarians from it".
- M on a camp ("send a unit") stays as is, plus an "attack party" variant: "Send 2 units: Warrior 3 turns, Slinger 4
  turns" so the player follows "attack with more than one unit" without picking them one by one.
- Result line when a camp is cleared: "Barbarian camp destroyed: 50 gold" (check whether `Events.GoodyHutReward`, as used
  for villages, also fires for camps; engine-notes has the village case).
- New camp in view: "New barbarian camp 6 tiles north of Antium" (the NEW_BARBARIAN_CAMP notification text may already
  say this; check that the position is relative to a city).
- Clans mode: keep the existing clan line and T (treat), unchanged.

### G3d. Experience farming (tip 8 side note)

"Keep a camp alive for experience." Low priority: the promotion list already says when a unit can be promoted; a hint
in the camp's Space text ("Fighting near it gives your units experience") is enough.

**Testing for G3.** A scenario `barbarian-scout-near-city` (util/scenarios): spawn a barbarian scout 3 tiles from the
capital via the tuner (`Players[63]:GetUnits():Create(...)`), end the turn, check the alarm; move it out of sight,
check "escaped"; kill it, check "killed". `barbarian-raid`: spawn 3 barbarian soldiers 4 tiles from a city and a
builder near them, check the raid and the civilian-danger lines. luatest for the wording (HubEnemies.Describe style:
pure functions with entries in, text out).

## G4. Escort awareness (tip 7)

**Player story.** "I sent my settler 5 tiles away, it got captured on the way." The game never warns about this
either, but a sighted player sees the horseman coming.

**Proposal.**
- When a settler or builder is ordered to move (Move To, the settle browser, the builder browser, J M) and no
  friendly soldier moves with it: if hostile soldiers or a remembered camp are within 4 tiles of the path or the target,
  "Settler moving alone, 3 turns. Barbarian Warrior 2 tiles from the path. Escort first: Shift+E with a soldier on the
  same tile". Without danger, nothing (no nagging).
- When a civilian and one of my soldiers share a tile without a formation, selecting either adds once:
  "Warrior here too: Shift+E forms an escort".
- In formation, the selection line says "escorted by Warrior" and the move turns line counts the slower unit (tip 7
  notes the pair moves at the speed of the slower unit; check that our turns come from the formation's path).
- With a settler selected, J M on the settler's own tile is "Send an escort": nearest soldiers by turns, Enter moves
  it onto the settler.

**Engine hooks.** `UnitManager.GetMoveToPathEx` (already used) for the path plots; formation state:
`unit:GetMilitaryFormation()` or the Enter Formation operation's `CanStartOperation` (the Shift+E command already
knows); hostile units from HubEnemies' scan.

**Testing.** regress on `early-t60` (or a scenario): settler Move To near a spawned barbarian → warning; soldier and
builder stacked → hint; Shift+E → "escorted by".

## G5. Combat preview depth (tips 3d, 4, 8)

**Player story.** "Should I attack now or wait for my second unit?" The preview says "deals 30 damage, target left with
70 of 100, you take 22", which is the outcome, but not *why*: strengths and the modifiers (flanking from Military
Tradition, support, terrain, river crossing, wounds) are what a player uses to decide when to attack, from where, and
with how many units.

**Proposal.**
- The attack line gains strengths: "Strength 20 against 17: deals 30 damage ...".
- Space in the attack target mode reads the modifier lines of both sides as the game lists them: "Your modifiers:
  plus 2 flanking, minus 3 attacking across a river. Their modifiers: plus 3 hills, plus 2 fortified".
- When flanking or support would be higher from another reachable tile, say it: "Attacking from the north would add
  plus 2 flanking" (stretch; needs a simulation per neighbour tile).

**Engine hooks.** `CombatManager.SimulateAttackInto` results (already used in `HubTargets.CombatPreviewText`):
`CombatResultParameters.COMBAT_STRENGTH`, `STRENGTH_MODIFIER`, and the text fields `PREVIEW_TEXT_TERRAIN`,
`PREVIEW_TEXT_ASSIST` (flanking/support), `PREVIEW_TEXT_HEALTH`, `PREVIEW_TEXT_OPPONENT`, `PREVIEW_TEXT_MODIFIER`,
`PREVIEW_TEXT_INTERCEPTOR`, `PREVIEW_TEXT_ANTI_AIR`; `UnitPanel.lua` `GetCombatModifierList` (~1977) shows how they
are split into lines (strip icons with the existing ScreenReader text cleanup).

**Testing.** regress on `t128-attack-targets`'s fixture: W, check "Strength N against M"; Space lists at least one
modifier line.

## G6. Settle spot context (tips 5, 6)

**Player story.** "How far is this from my other cities? Is it blocking Japan or right next to them?" The video
settles 3 to 6 tiles apart and places cities at natural barriers to hold land against the AI.

**Proposal.**
- Every settle candidate says distance to my nearest city and the nearest foreign city if within 10: "2 tiles
  north-east, 1 turn, river, ring 1: wine. 4 tiles from Rome, 7 from Kyoto (Japan)".
- Space adds direction context: "Between Rome and Japan" when the spot is closer to the rival than my nearest city
  is, "Behind Rome" when away from all known rivals; "Fills the gap toward Japan" when it claims plots the rival's
  borders would reach (stretch).
- Defensibility in Space: hills, river in front, mountains or coast around ("3 of 6 sides mountain or water").

**Engine hooks.** Already computed in `SettleScan` (crowding: nearest own city; foreign borders within 2); add the
foreign city distance from the cached city list.

**Testing.** luatest on SettleScan with a stub world (two cities), regress `settle-browser` expects the new phrase.

## G7. District advice per city (tip 3e)

**Player story.** "Which district should Antium build, and where?" Placement mode answers "where" for one chosen
district; choosing *which* means opening each one.

**Proposal.**
- Production panel, Space on a district item (or a summary line at the top of the Districts section): "Best spot:
  plus 3 science, 2 tiles north-east (mountains)".
- City report gets "District spots": "Campus plus 3, Holy Site plus 2, Commercial Hub plus 2 (river), Industrial
  Zone plus 1. Theater Square: no spot with a bonus". Enter on one opens production with it selected (or starts the
  placement).

**Engine hooks.** `PlacementScan_Scan( city, "district", hash )` per district the city can produce
(`BuildQueue:CanProduce`), take `list[1].total`. Cache per city + turn: the scan is not free (watch the hub's speed
when many districts are available; measure first).

## G8. Settle in place or move (tip 3a)

**Player story.** The first turn: "Should I just settle here?" The tip: settle in place unless something clearly
better is very close.

**Proposal.** The settler selection line compares scores: "Here is good: river, ring 1: wheat. Best nearby is about
the same. B founds here" / "Best spot is clearly better: 1 tile north, coast and silk, 1 turn. X to browse". Thresholds
from the score gap (e.g. under 3 points: "about the same"; over 6: "clearly better"), tuned on a few starts.

**Engine hooks.** `SettleScan_Scan(...).here` and `.best` scores.

## G9. Long tech and civic targets (tip 3d)

**Player story.** "Rush Political Philosophy." Setting a far target in the tree must say what that means.

**Proposal.** Enter on a node that isn't available: "Political Philosophy set as the target: 3 civics on the way,
about 26 turns. Next: Code of Laws, 4 turns". The J/Q keys in the tree already read the current item and queue; the
target line should end the same way.

**To check first** in game: what Enter on a blocked node says today (read only in code; the tree speech may already
contain part of this).

## G10. Vision and where camps can appear (tip 8)

**Player story.** "Where should I park my scout so barbarians don't spawn?" Camps only appear on plots no player can
see, at least `BARBARIAN_CAMP_MINIMUM_DISTANCE_CITY` (4) tiles from any city and
`BARBARIAN_CAMP_MINIMUM_DISTANCE_ANOTHER_CAMP` (7) from another camp (Base GlobalParameters; extra distance on low
difficulty: `BARBARIAN_CAMP_EXTRA_DISTANCE_PER_LOW_DIFFICULTY`). A sighted player sees fog and darkness around their
lands.

**Proposal.**
- J gets a "Blind spots" category: clusters of land plots 4 to 8 tiles from my cities that are revealed but not
  visible now: "Blind spot: 12 tiles out of sight, 5 tiles north of Antium". Enter puts the cursor on the cluster
  centre, M sends a unit (an alert/sentry there keeps the area watched: A).
- Optional turn-start line when a cluster becomes unwatched after a unit leaves (off by default).
- Unexplored land near my cities ("8 unexplored tiles 6 tiles west of Rome") in the same category, because camps
  spawn there too.

**Engine hooks.** `PlayersVisibility[local]:IsVisible(index)` / `IsRevealed(index)` (HubCore.IsPlotVisibleToLocal
uses it), `Map.GetPlotDistance`, a simple flood fill to cluster plots. Camp rules are approximate (the engine's spawn
choice is not exposed); word it as "barbarians can appear here", not a certainty.

**Testing.** luatest on the clustering (stub world); regress on `early-t60`: J, Tab to Blind spots, first entry
names a direction from a city.

## Suggested order

1. G1 (research advice: blocks tip 3c completely), G3a and G3b (scout alarm, raid and civilian danger: the most
   dangerous gap for a new player, and closes the long-open city-in-danger issue), G4 (escort).
2. G2 (standing against other civs), G5 (combat preview depth).
3. G6, G8 (small, settle wording), G10 (blind spots), G3c (camp details), G7, G9.

Every new key needs a HelpText.lua entry (workflow rule) and a check against `.claude/skills/civ-test/keymap.md`
for conflicts; key names above are candidates only.
