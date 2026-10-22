# Scenario scripts

`util/scenarios/<name>.lua` set up ONE situation on an already loaded fixture. They run in the `GameCore_Tuner`
state: `util\civctl.cmd lua GameCore_Tuner -File util\scenarios\<name>.lua` (a `scenario <name>` step in a
`test/regress/*.txt` script does the same; a dedicated `civctl scenario` command may be added later).

## Format

Every script starts with a header comment:

```lua
-- Scenario: <name>. STATUS: unverified | verified <date>
-- Fixture: <fixture it expects, with the reason, e.g. "a game with a capital">
-- Then press: <key> -> <speech expected>
-- Notes: <API risks, cleanups>
```

then the code. Rules:

- Only safe calls, i.e. ones seen to work (see the recipes in `.claude/skills/civ-test/SKILL.md`,
  `docs/engine-notes.md` "Tuner recipes") or plain data setup (spawn a unit, change gold or envoy tokens).
  Never the calls in the FORBIDDEN list of `docs/engine-notes.md`.
- Print what was done (`print("scenario X: ...")`) and `error("scenario X: <reason>")` when the precondition is
  missing (no capital, no forest), so `civctl lua` exits 1 and the regress run fails the step visibly.
- Do not save over the play-through chain; setup is for the loaded test game only.
- Each script is self-contained (no `include`) and idempotent where possible.

## Fixtures

The committed fixtures (`early-start`, `medieval-start`, `crowded-start`) are turn-1 or no-city games.
Scenarios marked "needs a city" need a fixture with a founded capital: load `early-start`, found the capital
(`B` with the settler selected), then `civctl save early-city -Purpose "capital founded, turn 2"`.
`envoys-to-give` also needs a met city-state (`crowded-start`; the script meets them itself).

## Scripts (all unverified: the game agent verifies and flips the STATUS line)

| Script | Fixture | Situation | Press afterwards |
|---|---|---|---|
| `enemy-at-capital` | `early-city` | barbarian warrior next to the capital | `X` (nearest foreign unit), `W` |
| `governor-title` | `early-city` (Gathering Storm) | 1 governor title ready | `F10` |
| `envoys-to-give` | `crowded-start` | 3 envoy tokens, all city-states met | `F2` |
| `builder-by-forest` | `early-city` | builder on an owned tile next to a forest | `Tab` on the builder / `I` on the forest |
