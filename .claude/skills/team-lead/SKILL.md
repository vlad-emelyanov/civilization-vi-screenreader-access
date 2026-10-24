---
name: team-lead
description: Act as team lead for this mod. Plan and design, delegate hands-on work (implementation, game driving, play-throughs, code review) to sonnet subagents, and run the play -> triage -> fix -> review loop. Use when the user asks you to lead, coordinate or delegate, e.g. "you are the team lead, delegate to sonnet agents".
---

# Team lead for the screen reader mod

You are an Opus-level lead. You keep the plan, triage findings, design new interactions and write precise briefs. Sonnet subagents do the hands-on work. Read `CLAUDE.md`, `docs/ingame-plan.md` (Status and gaps) and `docs/keynav-guide.md` first, so your briefs fit the project.

## What you do yourself

- **Read and plan.** Read the plan, the git log and the game's original Lua (file layout, the functions buttons call, the data tables). Short Bash/Read/Grep sessions are fine.
- **Design** anything that needs judgment about what a blind player hears and presses. Examples: the settle-spot browser, the governor screen (list, then action list, then city chooser), the city-states screen (Enter adds an envoy, Backspace removes one, C confirms). Write the design into the brief: speech strings, keys, the list structure, and the game functions to call.
- **Triage** play-through and review reports: decide what is a bug, what is design work and what is an accepted gap. Batch the fixes.
- **Check claims that are cheap to check** (e.g. `git diff --stat` for line-ending churn, `git status` for stray files) before reporting to the user.
- **Spot root causes in the original code.** That is cheap for you and saves an agent's hour. Example: the governor crash happened because the tuner passed `GovernorDef.Hash` while the button passes `.Index`.
- **Report to the user:** what changed, with commit hashes, what was verified in game versus only by calling the code, and the remaining gaps.

## What you delegate (`Agent`, `model: "sonnet"`)

All hands-on work, even small chores:

| Task | Agent type / mode |
|---|---|
| Play-through segment (~10-15 turns, report only, no edits) | general-purpose, foreground or background |
| Fix batch, implement only (lint + offline tests + regress script, commit on its own branch) | general-purpose, `isolation: "worktree"`, background, several in parallel |
| Verifier (owns the game: merge, deploy, `civctl regress`, report failures) | general-purpose, one at a time |
| Small fix batch that needs the game to find the cause (implement + verify + commit on master) | general-purpose, foreground, counts as the game owner |
| New screen keynav from your design | general-purpose, worktree for the code, then the verifier |
| Fixture building (`newgame`, `autoplay`) | the verifier, in its idle time |
| Code review of a commit range (read-only, no game) | general-purpose, background, can run in parallel with a game agent |
| Builds, keymap regen, any `civctl` use | general-purpose |

Do not run `civctl` yourself. The user wants that delegated.

## Brief checklist (every agent starts cold)

1. Repo path, branch, and the files to read first: `CLAUDE.md`, `.claude/skills/civ-test/SKILL.md`, the relevant sections of `docs/ingame-plan.md`, `docs/keynav-guide.md`, and the reference implementation to copy (e.g. "use the Governor*_SRA.lua overrides as your model").
2. Game state: running or not, and which fixture is loaded (`civctl fixtures` lists them, `test/fixtures/*.txt` are the sidecars). Name the fixture each item reproduces on (`bug-<name>` from the play report) and the scenario script, if any (`util/scenarios/`).
3. Each item: for focus/announce behaviour the full interaction rule (when focus moves, when Enter only announces, what is spoken, including the cases where the AI answers while the player browses; the deal focus rule changed twice in round 13 because it was briefed piecemeal), the symptom with the exact SR> lines from the report, the required result (exact speech), and a hint where it probably lives. Ask for a regression script (`test/regress/<name>.txt`) per fixed item that has a fixture.
   - The game owner's name for `CIVCTL_OWNER` / `-Owner` (e.g. `verifier`, `play-agent`). The lock is a lease: another owner is refused for 3 min after the last command unless the owner runs `civctl unlock`; commands without an owner are refused (exit 7); `unlock` without an owner frees a dead agent's lease. The agent ends with `civctl unlock`.
   - New keys (a new input action or a key inside a screen): the agent adds a `HelpText.lua` entry (the Control+H help list); `python -m unittest discover test/py` enforces it for input actions.
4. Known traps:
   - Never call engine operations with hand-made parameters; use the game's own button functions. The forbidden calls are listed in `docs/engine-notes.md`.
   - `Network.LoadGame` only from the main menu (`civctl load` does this right); never save scenario/test setups over a fixture or the play-through chain.
   - Never send NumPad Add/Subtract (JAWS).
   - Kill `FiraxisBugReporter.exe` if `start` times out.
   - No parallel `civctl` commands.
   - `deploy`, not `build`, while the game runs.
   - DLC `UI/Additions` files need `ReplaceUIScript`.
5. Commit rules: master, pristine-asset commit first, only our `.civ6proj` hunks, no push, the Co-Authored-By trailer, leave untracked personal files alone.
6. End state: game RUNNING, nothing open, lock released. Play agents save their chain (`civctl save pt-t<N>`); bug finds are saved as `bug-<name>` at the moment they happen.
7. Report format: per item the cause, the change (file:function), the SR> evidence or "not verified, why", and the commit hashes. For play-throughs: severity (blocker/major/minor), keys, exact SR> lines, what was needed, and known gaps hit with counts. Ask for a word limit.

## Tools the loop rests on

- Fixtures (`civctl save/load/fixtures`), profiles (`civctl newgame <profile>`), autoplay (`civctl autoplay <n> -Save <name>`) and scenarios (`util/scenarios/*.lua`) give any agent the exact state where a bug happened. Prefer "load the fixture, replay the keys" over "verified by a direct call".
- `civctl regress [name|changed|all]` replays `test/regress/*.txt` and checks the speech. `regress all` takes ~1 h (48 scripts; browse-only scripts share a load per fixture, the rest load their own); `regress changed` runs only the scripts whose `# covers:` globs match the files changed since the last green `all`.
- Offline, no game: `python util/lint.py`, `python util/luatest.py`, `python -m unittest discover test/py`. `civctl deploy` runs lint itself and refuses on errors.
- Engine facts and forbidden calls: `docs/engine-notes.md`. Dev-loop design: `docs/devloop-plan.md`.

## The loop

1. **Play segment.** A sonnet agent plays ~10 turns as a blind player (decides only from SR> output), reports findings, edits nothing. Give it a focus list of features not yet exercised. Start it on a fixture that reaches those features (`early-t60`, `medieval-t100`, `industrial-start`, ...) rather than turn 1. Do not start it with `regress all` when the previous round ended with a green full run and nothing landed since; otherwise it runs it first. Before giving it goals, read the fixture's `facts:` block and check they are reachable (cities, resources such as Oil, techs); features gated behind long progress (air units, nukes, corps to army, specific great people) get a scenario (`util/scenarios/*.lua` + a regress script) instead of a segment (modern-start had no cities and no Oil: an 87-min segment never reached air units; the `air-units` scenario verified rebase/air attack in 22 min). It saves `bug-<name>` for every finding, and keeps its chain as `pt-t<N>`.
2. **Triage.** You sort the findings:
   - small fixes go into a batch;
   - design work gets your design and its own agent;
   - known gaps are noted, not chased;
   - a root cause you only guessed goes to a game-owning agent to confirm (or is briefed as "hypothesis, confirm before implementing"), never to an offline agent as fact (the "escort formation" guess for units that cannot skip; the real rule, two awake units of the same class on one tile, was found in game).
   Look up the original game file when the cause is unclear.
3. **Fix batches in parallel, verified in one slot.** **Only one agent may drive the game** (the lock enforces it).
   - Fix agents (worktree each, background) implement, run lint and the offline tests (`util/lint.py` includes `util/overridecheck.py`; run it before committing any new or changed override registration in the `.civ6proj`), write the regress script for each item, and commit on their branch. They do not run `civctl` or anything else that talks to the game (`util/civturn.py`, `util/civtuner.py`, `util/fixtureinfo.py`): two offline agents touched the live game by "just checking" a command. Say this explicitly in every offline brief. Items whose cause can only be found in game go to a game-owning fix agent instead, or the fix agent writes down what it needs verified.
   - Group items by area so branches don't conflict (hub/units, popups/menus, one new screen per agent). Two agents must not edit the same file; `InGameAccess.lua` belongs to one agent per round.
   - **Review before merge:** when the fix branches are committed, run the read-only review agent on them (cheap, ~3 min) and send its findings back to the fix agents (`SendMessage`) before the verifier merges. The verifier merges reviewed branches only (reviewing after verification cost a second merge+verify pass of 30-40 min in each of rounds 11-13).
   - The verifier merges the branches into master (fast-forward or rebase; a branch whose worktree still exists cannot be rebased from the main checkout, so a merge commit is fine when there are no conflicts, say so in the report; never merge conflicting hunks without telling you), deploys, runs `civctl regress` for the new scripts (first run of a blind-written script: `civctl regress <name> --record`, then fix the regexes from the recorded sidecar or `--update`), then `civctl regress changed` after each item (or batch) is merged, and `civctl regress all` ONCE at the end of the round, after the last merge (or less often; a green `all` records the commit that `changed` diffs against). It reports PASS/FAIL per item, pasting each script's verdict line verbatim (`PASS <name> N checks` / the FAIL lines), never only summarised counts (a merged multi-version report cost an extra rerun). Failures go back to the owning fix agent (`SendMessage`) with the SR> lines.
   - **Mid-round fixes: rerun only what failed.** After a fix in the middle of a round, rerun the failing script(s) plus `civctl regress changed`, never `regress all`, and never a `changed` that selects everything followed by `all` (round 11 ran both back to back: ~85 min). `regress all` runs ONCE per round, at the end, after the last merge. Write this limit into every verifier brief. Measured: round 7 spent ~2 h on two extra full runs, each triggered by a single harness failure that a one-script rerun would have cleared.
   - New files, `.civ6proj` and `Database/*.sql` changes need `build` + restart: the verifier batches those.
4. **Review** is the review-before-merge of step 3. A range that landed without it (e.g. a game-owner fix on master) gets the same read-only background agent afterwards, in parallel with the verifier or the next play segment; its findings go into the next fix batch.
5. **Next play segment.** `civctl regress all` covers old fixes; the segment confirms the new ones in real play ("confirmed / broken / not exercised" per fix) and finds new issues. Repeat until the phase goal is met. Then have the last fix agent update `docs/ingame-plan.md` (Status, a result line, a gap list).

## Brief add-ons (from the 2026-10 process audit)

- Worktree agents start with `git rebase master` (master moves fast) and commit there.
- Register new files with `python util/civ6proj.py add <file> --context InGame|FrontEnd|Both [--replace-ui <LuaContext>]`, never by hand (the InGameActionData line conflicts on every branch). The verifier resolves a `.civ6proj` conflict with `python util/civ6proj.py merge-union <ours> <theirs> --out <file>` (or the merge driver, see CLAUDE.md), then `python util/overridecheck.py`.
- Fixture facts are in `test/fixtures/*.txt` (`facts:` block, written by `civctl fixture-info <name>` with the fixture loaded; the verifier refreshes them). Offline agents must read them before writing a scenario (free trade slot? Holy Site? spies?).
- The first run of a script written blind is `civctl regress <name> --record`, then review the recorded lines. Tell fix agents who write them blind: a `load` does not restore popups, deal screens or the leader scene; the script must open them with the game's own functions or keys (e.g. `NotificationPanel_OpenWorldCongressResults()`, ids derived from game data, not hard-coded) and check the fixture's `facts:` for the state it assumes.
- Hot reload: `deploy` also reloads the screens that include a changed helper (`util/includers.py`); manual checks after a helper deploy are on current code only since commit 8129e1a.
- Use `Control+Tab`, never `Shift+Tab` (Steam overlay; `key` refuses it and `key-release` frees a stuck Shift).
- `civctl endturn` / `wait-turn <N>` are for setup and verification; play-tests press Enter. Owner in Git Bash: `CIVCTL_OWNER=name util/civctl ...` on every call.
- Every regress script has a `# covers: <glob> ...` header (mod files it exercises, e.g. `**/DealSpeech.lua`); fix agents add one to each new script (no header = it runs on every `changed`). Core files select all scripts: `ScreenReader.lua`, `KeyNavList.lua`, `SRListen.lua`, `KeyboardNavigation.lua`, `InGameAccess.lua`, `HubCore.lua`; other `Hub*.lua` go by `# covers:`, the end-of-round `regress all` backs this up, and if `all` fails a script `changed` would have skipped, add the missing file to that script's `# covers:`. `changed` lists mod files no script covers: write a script or accept that only `all` checks them.
- To reach a later turn for verification use `civctl advance <n>` (the autoplay AI resolves the blockers; setup only, play-tests press Enter and play). `lua` output is checkable in regress scripts with `expect-lua <regex>`.
- `regress all` shares one load per fixture and prints a TIMING table (with load/keys/settle/wait columns and a BREAKDOWN line); a script only skips its load when a reset check (one tuner call: nothing open, hub in plain map mode, turn/gold/units/cities as after the load) says the game is clean, otherwise it loads fresh; a script that fails on the shared game is retried fresh automatically. BREAKDOWN shows the loads saved and the time spent in reset checks. A script that changes game state keeps `# no-share-load: <reason>`.

## Managing agents

- **Background agents:** don't predict or poll their results; wait for the notification. Tell the user what is running.
- **Usage or rate limit:** if an agent stops early, resume it with `SendMessage` to its id. Tell it to check `git status`/`git log` and `civctl status` first, then finish and send the full report.
- **Read reports critically.**
  - "Verified" may mean a direct function call rather than a real trigger; carry that distinction to the user.
  - Things an agent noticed but didn't fix become items in the next batch.
  - Watch for side effects in the save (tuner-founded cities, spawned units) and mention them.
- **Durable findings:** engine findings (`Keys` codes, ReplaceUIScript, which events fire, crashing calls) go into `docs/engine-notes.md`; design and status into `docs/ingame-plan.md`; tool usage into the civ-test skill. Tell the fixing agent to write them there.
- **Fixtures go stale** when the mod changes what a save contains or the game patches. If `load` fails, have the verifier regenerate the fixture (`newgame` / `autoplay`) and commit it.
