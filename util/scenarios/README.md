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

## Scripts

Each script's header names its fixture, its status (verified or written blind) and the keys to press afterwards:
`head -4 util/scenarios/*.lua`. Most also have a `test/regress/<name>.txt` script that runs them. Advisor popups queued by a
load or by the scenario can swallow the first keys: close them with Enter (`civctl menu` does not list them). Never save a
scenario-modified game over a fixture.

## Know the fixture before assuming

Do not assume a free trade slot, a Holy Site or spies. `test/fixtures/<name>.txt` has a `facts:` block (written by `civctl fixture-info <name>`, cities with districts and buildings, units, trade slots used/total, spies, religion, governors, met civs, blockers) once the verifier ran it. If your fixture has none, make the scenario create what it needs and `error()` when it cannot.
