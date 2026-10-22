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
| Fix batch (implement + verify in game + commit) | general-purpose, foreground |
| New screen keynav from your design | general-purpose, foreground |
| Code review of a commit range (read-only, no game) | general-purpose, background, can run in parallel with a game agent |
| Builds, keymap regen, any `civctl` use | general-purpose |

Do not run `civctl` yourself. The user wants that delegated.

## Brief checklist (every agent starts cold)

1. Repo path, branch, and the files to read first: `CLAUDE.md`, `.claude/skills/civ-test/SKILL.md`, the relevant sections of `docs/ingame-plan.md`, `docs/keynav-guide.md`, and the reference implementation to copy (e.g. "use the Governor*_SRA.lua overrides as your model").
2. Game state: running or not, which turn, quick-saved or not, and what is in the save (test cities, spawned units).
3. Each item: the symptom with the exact SR> lines from the report, the required result (exact speech), and a hint where it probably lives.
4. Known traps:
   - Never call engine operations with hand-made parameters; use the game's own button functions.
   - Never send NumPad Add/Subtract (JAWS).
   - Kill `FiraxisBugReporter.exe` if `start` times out.
   - No parallel `civctl` commands.
   - `deploy`, not `build`, while the game runs.
   - DLC `UI/Additions` files need `ReplaceUIScript`.
5. Commit rules: master, pristine-asset commit first, only our `.civ6proj` hunks, no push, the Co-Authored-By trailer, leave untracked personal files alone.
6. End state: game RUNNING, nothing open, quick-saved (so the next agent can continue).
7. Report format: per item the cause, the change (file:function), the SR> evidence or "not verified, why", and the commit hashes. For play-throughs: severity (blocker/major/minor), keys, exact SR> lines, what was needed, and known gaps hit with counts. Ask for a word limit.

## The loop

1. **Play segment.** A sonnet agent plays ~10 turns as a blind player (decides only from SR> output), reports findings, edits nothing. Give it a focus list of features not yet exercised.
2. **Triage.** You sort the findings:
   - small fixes go into a batch;
   - design work gets your design and its own agent;
   - known gaps are noted, not chased.
   Look up the original game file when the cause is unclear.
3. **Fix batches**, one agent at a time. **Only one agent may drive the game.** Group items by area (hub/units, popups/menus, one new screen per agent). Run them in the foreground when your next step depends on them.
4. **Review** each finished range with a read-only background agent. Run it in parallel with the next play segment, which needs the game but not the code. Add the review findings to the next fix batch.
5. **Next play segment.** It confirms the fixes in real play ("confirmed / broken / not exercised" per fix) and finds new issues. Repeat until the phase goal is met. Then have the last fix agent update `docs/ingame-plan.md` (Status, a result line, a gap list).

## Managing agents

- **Background agents:** don't predict or poll their results; wait for the notification. Tell the user what is running.
- **Usage or rate limit:** if an agent stops early, resume it with `SendMessage` to its id. Tell it to check `git status`/`git log` and `civctl status` first, then finish and send the full report.
- **Read reports critically.**
  - "Verified" may mean a direct function call rather than a real trigger; carry that distinction to the user.
  - Things an agent noticed but didn't fix become items in the next batch.
  - Watch for side effects in the save (tuner-founded cities, spawned units) and mention them.
- **Durable findings:** engine findings (`Keys` codes, ReplaceUIScript, which events fire) should end up in `docs/ingame-plan.md` or the civ-test skill. Tell the fixing agent to write them there.
