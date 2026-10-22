# Scenario scripts

`util/scenarios/<name>.lua` set up ONE situation on an already loaded fixture. They run in the `GameCore_Tuner`
state: `util\civctl.cmd lua GameCore_Tuner -File util\scenarios\<name>.lua` (a `scenario <name>` step in a
`test/regress/*.txt` script does the same; `civctl scenario <name>` does the same).

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

All four scripts are verified on `early-t60` (turn 60, AI-played: capital, builder-capable land, nine met-able city-states,
Gathering Storm). Advisor popups of that game can swallow the first keys: close them with Enter (`civctl menu` does not list
them). Never save a scenario-modified game over a fixture.

## Scripts (all verified 2026-10-22 on `early-t60`; run with `civctl scenario <name>`)

| Script | Fixture | Situation | Press afterwards |
|---|---|---|---|
| `enemy-at-capital` | `early-t60` | barbarian warrior next to the capital | `X` (nearest foreign unit), `W` |
| `governor-title` | `early-t60` | 1 governor title ready | `F10` |
| `envoys-to-give` | `early-t60` | 3 envoy tokens, all city-states met | `F2` |
| `builder-by-forest` | `early-t60` | builder on an owned tile next to a forest | `Tab` on the builder / `I` on the forest |
| `trader-in-capital` (unverified) | `medieval-t100` | a Trader in the capital | select it: the game opens its trade route chooser by itself (see `t100-trade-route`) |
| `prophet-ready` | `medieval-t100` (needs a pantheon + a completed Holy Site) | UNVERIFIED: a Great Prophet on the Holy Site | select it, `Tab`, Found Religion |
