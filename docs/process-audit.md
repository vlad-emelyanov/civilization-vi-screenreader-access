# Process audit (2026-10-22)

Scope: the team-lead loop of 2026-10-22 (one play-test, three verify rounds, eleven offline feature branches). Numbers come from agent reports.

## Where the time went

| Activity | Time | Notes |
|---|---|---|
| Play-test, 13 turns (medieval-t100 -> t113) | ~80 min, 243 tool calls | 4 blockers needed tuner workarounds to keep playing |
| Verify round 1 (3 branches) | ~17 min, stopped early | Load/Save only; trade + deal not reached (fixture state) |
| Verify round 2 (5 branches + review fixes) | ~110 min, 276 tool calls | every feature passed, ~1 bug per feature fixed in game |
| Verify round 3 (2 branches + fixes) | ~79 min, 146 tool calls | everything green; ~45 min of it was harness friction |
| `regress all` | ~22 min for 18 scripts | mostly fixture loads (30-45 s each) |
| Offline feature agent | 5-17 min each, parallel | cheap; not the bottleneck |

The bottleneck is the single game slot. Offline work scales with agents; game time does not. So every improvement below either removes a game cycle or makes one shorter.

## What cost a whole cycle

1. **Override method guessed wrong** (deal screen): our ImportFiles copy lost to Gathering Storm's same-name replacement; the first fix name matched the file's own `include("X_", true)` wildcard and crashed the game. -> `util/overridecheck.py` (run by lint) now flags both. DONE.
2. **Fixture state assumed by offline agents**: trade scenario assumed a free trade slot (capacity 1/1), religion scenario assumed a Holy Site, espionage needs spies. -> `civctl fixture-info` writes a `facts:` block into each fixture sidecar so briefs and agents can check before writing a scenario. IN PROGRESS.
3. **Blind regress scripts** fail on their first run (wrong tab labels, wrong item order, extra lines). -> `civregress --record/--update` fills expectations from one real run. DONE.
4. **Hover-only speech invisible to the harness** (in-game menu): the real mouse never reaches that menu, so the speech never happened for a real user either. Keynav guide rule "announce directly on focus change" is now applied there; lesson: any screen whose items only speak via MouseEnter is a bug, not a harness gap.
5. **Things that cannot be provoked** (AI deal offer, natural disaster, first-in-world moments): two attempts each, then filed as gaps. Accept this; play-tests surface them naturally.

## Harness friction (per verify round)

| Issue | Lost | Fix |
|---|---|---|
| Shift stuck after Shift+Tab (Steam overlay) | ~20 min | civctl key releases modifiers, refuses Shift+Tab; screens use Control+Tab. IN PROGRESS |
| Enter as end-turn walks into notification screens | ~5-10 min | `civctl endturn`, `civctl wait-turn N` (setup only; play-tests still use Enter). IN PROGRESS |
| Advisor popups after every load | ~1 min/load | `civctl load` clears advisors; `civctl clear-advisors`. IN PROGRESS |
| `regress all` reloads per script | ~10 of 22 min | group by fixture, share loads by default. IN PROGRESS |
| `.civ6proj` one-line conflicts on every merge | ~5 min/branch, one broken commit with conflict markers | `util/civ6proj.py add/merge-union`. IN PROGRESS |
| `CIVCTL_OWNER` export lost between Bash calls | ~3 min | document prefix form; exit-7 message shows it. IN PROGRESS |
| Hot reload breaks some contexts (deal view) | ~2 min/restart | documented in engine-notes; test those after a restart |
| Process-start failures (0xC0000142) in long regress runs | one burst | retry in the runner. DONE |
| Screenshots piling up (~400) | disk only | keep newest 20. DONE |
| `civctl.cmd` breaks on quoted args from Git Bash | ~5 min | cannot be fixed in cmd; use `util/civctl`. DOCUMENTED |

## Loop changes (team lead)

- Review every merged range with a read-only agent before or during verification: the round-2 review found three real bugs (silent random promotions, Religion re-announce, L closing the screen) that would otherwise have cost a play-test cycle.
- Run feature agents in parallel while the verifier holds the game; merge in one batch per round so there is one `build` + restart per round.
- Worktree agents start with `git rebase master` (several forked from an old master and had to fast-forward).
- Briefs name the fixture AND the facts the scenario needs (from the sidecar facts block), and ask for a load line (`ScreenReaderAccess: X copy loaded`) in every new override.
- Verifier rounds: merge -> overridecheck -> build/start -> load lines -> per-feature checks with `--record` on first runs -> `regress all`. Ask for a friction list every round.

## Not worth doing

- A second game instance (Steam allows one) or faster loads (engine-bound).
- Replacing the real-keyboard harness with direct Lua calls: it hides exactly the bugs a blind player hits (input routing, swallowed keys, hover-only speech).
