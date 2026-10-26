#!/usr/bin/env python
"""Speech regression runner: replays key scripts against a loaded fixture and checks the SR> lines.

  python util/civregress.py [name ...|all] [--share-load|--no-share-load] [--dry-run] [--list] [--record] [--update] [--clear-advisors] [--no-batch]

Scripts live in test/regress/<name>.txt, one step per line (blank lines and '#' comments are ignored):

  load <fixture>          civctl load <fixture>          (its SR> lines count, e.g. the "Turn 1" announcement)
  scenario <name>         civctl scenario <name>   (util/scenarios/<name>.lua in GameCore_Tuner)
  key <args>              civctl key <args>              e.g. key Enter -Settle 2000, key Shift+Down
  action <ActionId> [-Settle ms]  civctl action <ActionId>: presses the action's CURRENT key (InputSettings.json / mod and game
                          defaults, util/keybindings.py) like `key`. Use it for rebindable game/mod hotkeys (NextUnit, KeyNavCityReport,
                          ToggleTechTree, ...); keep `key` for plain navigation keys inside our own screens (Up, Down, Enter, Escape, Tab, letters).
                          An unbound action fails the step (civctl exit 1).
  wait <args>             civctl wait <args>             e.g. wait Turn \\d+ -Timeout 30 (no | or & in the regex: cmd.exe)
  lua <state> <expr>      civctl lua <state> <expr>      (the expression goes through a temp -File: quotes are safe)
  clear-advisors          closes the advisor popups of the game, one tuner call each (KeyNavActivate(1) in AdvisorPopup, like Escape on
                          the popup; max 12): the advisor popups that a loaded or tuner-changed game queues swallow keys. With no
                          popup up it does nothing. Warns when the cap is hit. ~1.7 s per popup (was ~4.5 s with probe + real Enter).
  no-lua-errors           PASS if Lua.log got no new "Runtime Error" line since the script began (put it last)
  expect <regex>          PASS if some SR> line since the last check matches (re.search, case-sensitive, use (?i))
  expect-not <regex>      PASS if no SR> line since the last check matches
  expect-lua <regex>      PASS if a non-SR> output line of the most recent `lua` / `scenario` step matches (the Lua print() / return
                          value the tuner shows, e.g. `lua InGame return Game.GetCurrentGameTurn()` then `expect-lua ^62$`). The
                          lines of an earlier step are replaced by the next lua/scenario step. Nothing to match = FAIL.

Matching sees the text only: "SR> ", "(earlier) " and "[NOINTERRUPT] " prefixes are stripped, so ^ anchors work.
Window: lines accumulate across key/wait/load/scenario/lua steps. expect/expect-not do not clear them, so several
checks in a row look at the same lines; the first action step after a check starts a fresh window.

Failure handling: a failed expect prints FAIL with the lines it saw and the script goes on. A failed load/scenario
(non-zero exit) aborts the script, as does civctl exit 5 (game crashed/hung) at any step; exit 6 (lock held by another
owner) and 7 (no owner given) abort the whole run. After an abort the next script starts with a fresh load. Other non-zero exits of
key/action/wait/lua count as a failed step and the script goes on.

A script whose checks were all skipped by a shared load is reported as SKIPPED-ALL with a warning (it checked nothing).
Two separate header kinds (the first says "may START on a shared game", the second "may the NEXT script reuse what it leaves"):
`# own-load: <reason>`: the script does its own load because it checks what the load itself says (the turn announcement, a popup the
load opens); the checks right after a skipped load would be skipped. It does not dirty the game: the next script may share it.
`# no-share-load: <reason>`: the script changes game state the reset check cannot see (gold, tiles, units, focus, a deal, turns, a
save, a scenario). It may start on a clean shared game (no load of its own), but the next script loads fresh.
`# options:` scripts do both (own load, next loads fresh). Scenario scripts count as `# no-share-load`.

Loads: `all` shares one load per fixture by default (--no-share-load disables it); named scripts load fresh unless --share-load.
Sharing skips the first `load` of a script (and the `expect` lines right after it, they would see no lines) when the previous script
loaded the same fixture, finished without an abort AND a reset check proved the game is back in the state a fresh load gives. The
check is ONE tuner call (HubCore.TestResetState in the InGameAccess state): in game and our turn, no popup/screen/options menu open, hub in
plain map mode (no mode, target or placement), and turn/gold/units/cities equal to a baseline taken right after the load (HubCore.TestSnapshotText,
after the first clear-advisors). If clean it puts the map cursor and the selection back; otherwise (or on no answer) the next script loads
fresh. A dirty check never fails a script. Inside a fixture group the `# own-load` (clean) scripts run first, then the sharing ones, then the `# no-share-load` and scenario ones.
A script that fails on a shared game is run once more with its own load (RETRY in the output; the
second result counts, TIMING marks it): drift must not fail a script that passes alone. Scripts run grouped by their first fixture.
The run ends with a TIMING table (seconds per script) and TOTAL. `key Shift+Tab` is rejected when the script is parsed (Steam overlay).
`--clear-advisors` only closes the advisor popups of the loaded game (what `civctl clear-advisors` runs).
The TIMING table splits each script's time into load / keys (key + action steps; "settle" = the part of it that is the scripted
-Settle waits) / wait / lua (lua + scenario) / other, and a BREAKDOWN line sums it up: that shows where a slow run goes, how many
loads sharing saved and how many reset checks ran (and what they cost).

Speed: the runner keeps ONE `civctl.ps1 batch` process (a JSON array of civctl arguments per stdin line; the output of a step ends with
`@@CIVCTL-DONE <rc>`) instead of a powershell.exe per step. A step timeout kills the process tree and the next step starts a new
process, as does exit 5; if it cannot start or the protocol breaks, the steps run per call (said once). `--no-batch` = per call always.
`key`/`action` return once an SR line has arrived and -Quiet ms (default 150; 700 when -Settle >= 1500; explicit wins) passed without another one; -Settle is only the maximum
(no SR line at all = the full -Settle). `-Quiet <ms>` raises the window for a late second line, `-NoQuiet` is the old fixed wait.
civctl reports the real wait as `@@waited <ms>` (the runner strips and sums it): "settle" in TIMING/BREAKDOWN is the time really waited.

Selective runs: every script carries a header `# covers: <glob> [<glob> ...]` naming the mod files it exercises (globs on repo-relative
paths with / ; `**/` = any directories, `*` = within one name; a glob without a leading `**/` matches as a path suffix).
  python util/civregress.py changed [--base <rev>]    run only the scripts the changes since <rev> can affect
Base: --base, else the commit of the last green `regress all` (%TEMP%/civctl/regress-last-green.txt, per machine, written by an
all-green, unaborted `regress all`), else (nothing recorded / unknown rev) every script. Changes = `git diff <base>` (committed AND
uncommitted tracked changes) + untracked files. Selected: a script whose covers glob matches a changed file; every script without a
`# covers:` header; a script that changed itself (test/regress/<name>.txt); scripts using a changed util/scenarios/<s>.lua; scripts
with `action` steps when a ScreenReaderAccess/Database/*.sql changed. CORE files (ScreenReader.lua, KeyNavList.lua, SRListen.lua,
KeyboardNavigation.lua, UI/Additions/InGameAccess.lua, Accessibility/HubCore.lua) select EVERYTHING; other Hub*.lua go by `# covers:` (the end-of-round `regress all` backs this up: a script it fails that `changed` skipped needs the missing file in its `# covers:`). Changed mod files that no script
covers are listed ("not covered"): they are not run by `changed`, only by `all`. `--dry-run` shows the selection and the reasons.

Record mode (for a script written blind, never run against the game): `--record` runs the script (never shares loads) and
writes test/regress/<name>.recorded.txt: the script with, under every expect/expect-not line, comment lines with PASS/FAIL
and the SR> texts of the window that check saw. `--update` does the same and also rewrites the script in place (the original
is kept as <name>.txt.bak): each FAILING `expect` gets the regex of the most similar window line (escaped, digit runs -> \\d+,
anchored) and the old line stays above it as `# was: ...`. Failing expect-not lines and checks with an empty window are left
alone (see the sidecar). Review the diff: a recorded line can be the wrong one. Through civctl: `civctl regress <name> --record`.

Game options: unless --real-options, a run applies util/testopts.py `on` (advisor disabled, quick combat/movement, no combat camera
look-at, no historic moment animation) and restores the user's values in a finally. If a run is killed: python util/testopts.py restore.
Header `# options: animations` and/or `# options: advisor` (implies own load and no sharing afterwards): that script runs with
those option groups at the user's real values (switched before its load, back after it). Without `advisor` the clear-advisors steps are
skipped (no popups with the advisor off). Helper script_needs_fresh(steps) = must load fresh.

Env: CIVCTL_OWNER (or --owner) is the lock owner passed to civctl and is REQUIRED (no default; refused with exit 7 without
it). Through `civctl regress` it is the caller's owner, so the caller's lock lease is reused.
Exit code: 0 all passed, 1 something failed, 2 usage/parse error, 7 no owner.
"""
import argparse
import glob
import json
import os
import queue
import re
import shutil
import subprocess
import sys
import tempfile
import threading
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REGRESS_DIR = os.path.join(ROOT, "test", "regress")
SCENARIO_DIR = os.path.join(ROOT, "util", "scenarios")
CIVCTL = os.path.join(ROOT, "util", "civctl.ps1")
POWERSHELL = "powershell.exe"
TIMEOUT_RC = 124
START_FAILURE_RCS = (0xC0000142, 0xC0000142 - 0x100000000)  # as unsigned and signed exit code
MAX_ADVISOR_PRESSES = 12
LUA_LOG = os.path.join(os.environ.get("LOCALAPPDATA", ""), "Firaxis Games", "Sid Meier's Civilization VI", "Logs", "Lua.log")

OWNER_REFUSED = ("REFUSED: no owner. In Git Bash prefix EVERY call: CIVCTL_OWNER=<your agent name> util/civctl <command> ... "
                 "(an export does not persist between tool calls). PowerShell: $env:CIVCTL_OWNER='<name>'; or pass -Owner <name>")

ACTIONS = ("load", "scenario", "key", "action", "wait", "lua", "clear-advisors", "no-lua-errors")
NO_ARG = ("clear-advisors", "no-lua-errors")
CHECKS = ("expect", "expect-not", "expect-lua")
STEP_TIMEOUT = 600  # seconds per civctl call (a load is ~45 s, a newgame 70 s)
BATCH_DONE = "@@CIVCTL-DONE"   # civctl batch: ends the output of one command, followed by its exit code
_PROFILE = re.compile(r"^@@profile (.*)$")   # CIVCTL_PROFILE=1: where the fixed cost of a key/action goes (printed, not parsed)
_WAITED = re.compile(r"^@@waited (\d+)\s*$")   # key/action: ms actually spent waiting for the speech


class ScriptError(Exception):
    pass


class Step:
    def __init__(self, kind, arg, line):
        self.kind, self.arg, self.line = kind, arg, line

    def __repr__(self):
        return "Step(%r, %r, line %d)" % (self.kind, self.arg, self.line)


class Steps(list):
    fresh = False  # '# no-share-load' (or a scenario / options): the script dirties the game, the next one loads fresh
    own_load = False  # '# own-load': the script must do its own load (checks the load's speech) but leaves the game clean
    text = ""      # the script source (record mode rewrites it)
    manual = False # '# manual' in the script: only run when named (all / changed skip it)
    options = frozenset()  # '# options: animations advisor' headers: option groups this script wants at the USER's values
    covers = ()    # globs of '# covers:' headers (empty = none given: `regress changed` always runs the script)


def key_problem(arg):
    """Why a `key` argument must not be sent, or None. Shift+Tab opens the Steam overlay: the overlay swallows the key-up and the
    game then thinks Shift is held (Down does nothing, Tab goes backwards) until both Shift keys are released."""
    parts = [p.lower() for p in arg.split()[0].split("+")] if arg.split() else []
    if len(parts) > 1 and "shift" in parts[:-1] and parts[-1] == "tab":
        return "Shift+Tab opens the Steam overlay; our screens use Control+Tab (previous section/tab)"
    return None


OPTION_GROUPS = ("animations", "advisor")


def parse_options(text, name="script"):
    """'# options: animations advisor' header lines -> frozenset of option groups the script wants at the user's real values."""
    found = set()
    for m in re.finditer(r"^#\s*options:(.*)$", text, re.M):
        for g in m.group(1).replace(",", " ").split():
            if g not in OPTION_GROUPS:
                raise ScriptError("%s: unknown '# options:' group '%s' (known: %s)" % (name, g, ", ".join(OPTION_GROUPS)))
            found.add(g)
    return frozenset(found)


def script_needs_fresh(steps):
    """True when the script either must load itself or dirties its game (no-share-load, scenario, own-load, option opt-outs)."""
    return must_load_itself(steps) or dirties_game(steps)


def must_load_itself(steps):
    """True when the script may not START on a shared game: '# own-load' (checks the load's own speech) and '# options:'."""
    return bool(getattr(steps, "own_load", False) or getattr(steps, "options", ()))


def dirties_game(steps):
    """True when the game this script leaves must not be shared: '# no-share-load', a scenario, '# options:'."""
    return bool(getattr(steps, "fresh", False) or getattr(steps, "options", ()))


def parse_script(text, name="script"):
    """Text -> [Step]. Raises ScriptError with file:line for unknown steps, missing arguments and bad regexes."""
    steps = Steps()
    steps.fresh = bool(re.search(r"^#\s*no-share-load", text, re.M))
    steps.own_load = bool(re.search(r"^#\s*own-load", text, re.M))
    steps.text = text
    steps.manual = bool(re.search(r"^#\s*manual", text, re.M))
    steps.covers = tuple(g for m in re.finditer(r"^#\s*covers:(.*)$", text, re.M) for g in m.group(1).split())
    steps.options = parse_options(text, name)
    if steps.options:
        steps.fresh = True   # needs its own load (the options are switched before it)
    scenario = False
    for no, raw in enumerate(text.splitlines(), 1):
        line = raw.strip().lstrip("﻿")
        if not line or line.startswith("#"):
            continue
        kind, _, arg = line.partition(" ")
        kind, arg = kind.lower(), arg.strip()
        if kind not in ACTIONS + CHECKS:
            raise ScriptError("%s:%d: unknown step '%s'" % (name, no, kind))
        if not arg and kind not in NO_ARG:
            raise ScriptError("%s:%d: '%s' needs an argument" % (name, no, kind))
        if kind in CHECKS:
            try:
                re.compile(arg)
            except re.error as e:
                raise ScriptError("%s:%d: bad regex %r: %s" % (name, no, arg, e))
        if kind == "key" and key_problem(arg):
            raise ScriptError("%s:%d: %s" % (name, no, key_problem(arg)))
        if kind == "lua" and len(arg.split(None, 1)) < 2:
            raise ScriptError("%s:%d: 'lua' needs <state> <expression>" % (name, no))
        if kind in ("load", "scenario") and len(arg.split()) != 1:
            raise ScriptError("%s:%d: '%s' takes one name" % (name, no, kind))
        steps.append(Step(kind, arg, no))
        scenario = scenario or kind == "scenario"
    if scenario:
        steps.fresh = True   # a scenario changes the game: such a script always loads fresh, and the next one does not share its game
    return steps


def first_fixture(steps):
    for s in steps:
        if s.kind == "load":
            return s.arg
    return None


_PREFIX = re.compile(r"^(?:\(earlier\) )?SR> (?:\[NOINTERRUPT\] )?")


def parse_sr_lines(output):
    """civctl output lines -> [(raw, text)] for the SR> lines (text = prefixes stripped); other lines are dropped."""
    res = []
    for l in output:
        l = l.rstrip("\r\n")
        m = _PREFIX.match(l)
        if m:
            res.append((l, l[m.end():]))
    return res


def check(kind, pattern, sr_lines):
    """expect / expect-not over [(raw, text)]. Returns (ok, matching raw line or None)."""
    rx = re.compile(pattern)
    hit = next((raw for raw, text in sr_lines if rx.search(text)), None)
    return (hit is None if kind == "expect-not" else hit is not None), hit


def join_positional(arg):
    r"""'Turn \d+ -Timeout 30' -> ['Turn \d+', '-Timeout', '30']: the words before the first -Flag are one argument."""
    words = arg.split()
    i = 0
    while i < len(words) and not re.match(r"^-[A-Za-z]", words[i]):
        i += 1
    return ([" ".join(words[:i])] if i else []) + words[i:]


def civctl_args(step):
    """Step -> (argument list for civctl, temp file to delete or None)."""
    k = step.kind
    if k == "load":
        return ["load", step.arg, "-KeepAdvisors"], None   # scripts say `clear-advisors` themselves, where they want it
    if k in ("key", "action", "wait"):
        return [k] + join_positional(step.arg), None
    if k == "scenario":
        path = os.path.join(SCENARIO_DIR, step.arg + ".lua")
        if not os.path.isfile(path):
            raise ScriptError("no such scenario: %s" % path)
        return ["scenario", step.arg], None
    if k == "lua":
        state, expr = step.arg.split(None, 1)
        if re.search(r"(^|\s)-File\s", " " + expr):
            return ["lua", state] + expr.split(), None
        fd, tmp = tempfile.mkstemp(suffix=".lua", prefix="regress_")
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write(expr)
        return ["lua", state, "-File", tmp], tmp
    raise ScriptError("not an action: " + k)


class CivctlRunner:
    """Runs util/civctl.ps1; run(args) -> (exit code, output lines).

    batch=True keeps ONE `civctl.ps1 batch` process and sends each step to it as a JSON line (saves the powershell.exe start per
    step); the output of a step ends at a `@@CIVCTL-DONE <rc>` line. A step timeout kills the process tree and the next step starts a
    new process; so does exit 5 (crash). If the process cannot start or the protocol breaks, the steps go through the per-call path
    (said once). After run(), last_waited = seconds the key/action step spent waiting for speech (None if civctl did not say)."""

    def __init__(self, cmd=CIVCTL, owner=None, batch=False, batch_cmd=None, say=print):  # cmd: path of civctl.ps1
        self.cmd = cmd
        self.env = dict(os.environ)
        self.env["CIVCTL_OWNER"] = owner or os.environ.get("CIVCTL_OWNER") or ""  # main() refuses an empty owner
        self.env["CIVCTL_REPORT_WAITED"] = "1"
        self.batch = batch
        self.batch_cmd = batch_cmd or [POWERSHELL, "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", cmd, "batch"]
        self.say = say
        self.last_waited = None
        self._proc = None
        self._queue = None
        self._need_release = False   # the batch process was killed: the next one starts with key-release

    def run(self, args):
        # A process that cannot start (0xC0000142 STATUS_DLL_INIT_FAILED = desktop heap / handle pressure, seen as a burst of
        # 7 failing scripts in one `regress all`) never reached civctl: nothing was sent to the game, so retrying is safe.
        self.last_waited = None
        for attempt in range(3):
            rc, lines = self._run_once(args)
            if rc not in START_FAILURE_RCS:
                break
            print("  (powershell failed to start, rc=0x%08X: retry %d/2 after %d s)" % (rc & 0xFFFFFFFF, attempt + 1, 3 * (attempt + 1)))
            time.sleep(3 * (attempt + 1))
        waited, keep = None, []
        for l in lines:
            mp = _PROFILE.match(l)
            if mp:
                print("  profile: " + mp.group(1))
                continue
            m = _WAITED.match(l)
            if m:
                waited = (waited or 0) + int(m.group(1))
            else:
                keep.append(l)
        self.last_waited = None if waited is None else waited / 1000.0
        return rc, keep

    def _run_once(self, args):
        if self.batch:
            res = self._run_batch(args)
            if res is not None:
                return res
        return self._run_percall(args)

    def _run_percall(self, args):
        # powershell.exe -File directly: going through civctl.cmd (%*) loses '^' and quotes in regexes.
        cmd = [POWERSHELL, "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", self.cmd] + args
        p = subprocess.Popen(cmd, cwd=ROOT, env=self.env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        try:
            stdout, _ = p.communicate(timeout=STEP_TIMEOUT)
        except subprocess.TimeoutExpired:
            # kill the whole tree: the child powershell would keep driving the game and holding the lock
            self._kill_tree(p)
            p.communicate()
            return TIMEOUT_RC, ["civctl timed out after %d s (process tree killed)" % STEP_TIMEOUT]
        return p.returncode, stdout.decode("utf-8", errors="replace").splitlines()

    @staticmethod
    def _kill_tree(p):
        subprocess.run(["taskkill", "/T", "/F", "/PID", str(p.pid)], capture_output=True)

    # -- batch process
    def _give_up_batch(self, why):
        self.batch = False
        self.close()
        self.say("  (civctl batch process unusable: %s; running every step as its own powershell.exe)" % why)

    def _start_batch(self):
        self._proc = subprocess.Popen(self.batch_cmd, cwd=ROOT, env=self.env, stdin=subprocess.PIPE,
                                      stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        q = queue.Queue()
        self._queue = q

        def pump(f=self._proc.stdout):
            try:
                for raw in iter(f.readline, b""):
                    q.put(raw.decode("utf-8", errors="replace").rstrip("\r\n"))
            except (OSError, ValueError):
                pass
            q.put(None)   # end of output
        threading.Thread(target=pump, daemon=True).start()

    def _run_batch(self, args):
        """(rc, lines) for the step, or None to run it through the per-call path (the batch process is then given up)."""
        if self._proc is None:
            try:
                self._start_batch()
            except OSError as e:
                self._give_up_batch("cannot start: %s" % e)
                return None
            if self._need_release:
                # the old process was killed (timeout / crash), maybe in the middle of a chord: let go of Shift/Control/Alt first
                self._need_release = False
                self._run_batch(["key-release"])
                if self._proc is None:
                    return None   # the new process broke on key-release: per-call path
        p, q = self._proc, self._queue
        try:
            p.stdin.write((json.dumps(args) + "\n").encode("ascii"))
            p.stdin.flush()
        except (OSError, ValueError):
            rc = self._reap(p)
            if rc in START_FAILURE_RCS:
                return rc, []
            self._give_up_batch("stdin closed")
            return None
        lines = []
        deadline = time.time() + STEP_TIMEOUT
        while True:
            try:
                l = q.get(timeout=max(0.0, deadline - time.time()))
            except queue.Empty:
                self._kill_tree(p)
                self.close()
                self._need_release = True
                return TIMEOUT_RC, ["civctl timed out after %d s (process tree killed)" % STEP_TIMEOUT]
            if l is None:   # the process ended before the step was done
                rc = self._reap(p)
                if not lines:
                    if rc in START_FAILURE_RCS:
                        return rc, []   # never ran: nothing was sent to the game
                    # the step was sent and may have pressed a key: never run it again
                    self._give_up_batch("it exited with code %s before answering" % rc)
                    return 1, ["civctl batch process died (exit %s) before answering this step; the step was NOT repeated (it may or may not have run)" % rc]
                self._give_up_batch("it exited with code %s in the middle of a step" % rc)
                return 1, lines + ["civctl batch process ended unexpectedly (exit %s)" % rc]
            if l.startswith(BATCH_DONE):
                try:
                    rc = int(l[len(BATCH_DONE):].strip())
                except ValueError:
                    self._give_up_batch("bad sentinel %r" % l)
                    return 1, lines + [l]
                if rc == 5:
                    self.close()   # the game crashed/hung: the next step starts a fresh process
                    self._need_release = True
                return rc, lines
            lines.append(l)

    def _reap(self, p):
        try:
            rc = p.wait(timeout=5)
        except subprocess.TimeoutExpired:
            self._kill_tree(p)
            rc = None
        self._proc = self._queue = None
        return rc

    def close(self):
        """Ends the batch process (stdin closed, killed if it does not leave); the next step would start a new one."""
        p, self._proc, self._queue = self._proc, None, None
        if p is None:
            return
        try:
            p.stdin.close()
        except (OSError, ValueError):
            pass
        try:
            p.wait(timeout=5)
        except subprocess.TimeoutExpired:
            self._kill_tree(p)
            try:
                p.wait(timeout=5)
            except subprocess.TimeoutExpired:
                pass


class LockedError(Exception):
    pass


def log_size(path):
    try:
        return os.path.getsize(path)
    except OSError:
        return 0


def new_lua_errors(path, offset):
    """Runtime Error lines appended to the log after byte offset (the whole file if it shrank = recreated)."""
    try:
        with open(path, "rb") as f:
            if os.path.getsize(path) < offset:
                offset = 0
            f.seek(offset)
            data = f.read().decode("utf-8", errors="replace")
    except OSError:
        return []
    return [l.rstrip() for l in data.splitlines() if "Runtime Error" in l]


def advisor_close_if_up(runner):
    """One tuner call that closes the visible advisor popup like its first button (KeyNavActivate(1), what Escape does) and says
    what it saw. Returns (rc, was_up, lines). Much cheaper than a probe plus a real Enter (1.7 s instead of 4.5 s per popup)."""
    fd, tmp = tempfile.mkstemp(suffix=".lua", prefix="regress_")
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        f.write("if ContextPtr:IsHidden() then return 'none' end KeyNavActivate(1) return 'closed'")
    try:
        rc, lines = runner.run(["lua", "AdvisorPopup", "-File", tmp])
    finally:
        try:
            os.remove(tmp)
        except OSError:
            pass
    return rc, rc == 0 and any(l.strip() == "closed" for l in lines), lines


def clear_advisors(runner, out=print, line=0):
    """Closes the advisor popups that a loaded or tuner-changed game queues (max MAX_ADVISOR_PRESSES), one tuner call each.
    Returns (status, output lines); status: ok | crashed (civctl exit 5 / timeout) | locked (exit 6/7; the last line is civctl's message)."""
    collected, presses = [], 0
    while True:
        rc, was_up, lines = advisor_close_if_up(runner)
        if rc in (6, 7):
            return "locked", collected + [chr(10).join(lines)]
        if rc != 0:
            out("  WARNING line %d: advisor probe failed (exit %d), nothing closed: %s" % (line, rc, " ".join(l.strip() for l in lines[-2:])))
            return ("crashed" if rc in (5, TIMEOUT_RC) else "ok"), collected
        if not was_up:
            # the speech the popups and the game produced meanwhile (no key press returned it): scripts expect it in their window
            rc2, spoken = runner.run(["sr"])
            if rc2 == 0:
                collected += [l for l in spoken if l.strip()]
            return "ok", collected
        presses += 1
        collected += [l for l in lines if l.strip() not in ("closed", "none")]
        if presses >= MAX_ADVISOR_PRESSES:
            out("  WARNING line %d: advisor popup still up after %d closes" % (line, presses))
            return "ok", collected


def shares_game(steps):
    """May the next script run on the game this one leaves? Not after '# no-share-load', a scenario or an '# options:' header."""
    return not dirties_game(steps)


def can_start_shared(steps):
    """May this script skip its load and start on a clean shared game? Not with '# own-load' or '# options:'. A '# no-share-load' or
    scenario script may (it just dirties the game afterwards)."""
    return not must_load_itself(steps)


_RESET_ANSWER = re.compile(r"^(clean|dirty|snap)\b\s*(.*)$")


def reset_check(runner, baseline=None, capture=False):
    """ONE tuner call (InGameAccess state) that asks the hub whether the game is back in the state a fresh load gives and puts the
    map cursor and selection back (HubCore.TestResetState). capture=True only reads the baseline (HubCore.TestSnapshotText).
    Returns (verdict, text, seconds): verdict 'clean' (text = the state to pass as baseline next time), 'snap' (capture) or
    'dirty' (text = why). Never raises for a game problem; exit 6/7 (lock) raises LockedError."""
    if capture:
        expr = "if HubCore == nil or HubCore.TestSnapshotText == nil then return 'dirty hub has no test helper' end return HubCore.TestSnapshotText()"
    else:
        arg = "nil" if baseline is None else "'" + baseline.replace("\\", "").replace("'", "") + "'"
        expr = "if HubCore == nil or HubCore.TestResetState == nil then return 'dirty hub has no test helper' end return HubCore.TestResetState(%s)" % arg
    fd, tmp = tempfile.mkstemp(suffix=".lua", prefix="regress_")
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        f.write(expr)
    t0 = time.time()
    try:
        rc, lines = runner.run(["lua", "InGameAccess", "-File", tmp])
    finally:
        try:
            os.remove(tmp)
        except OSError:
            pass
    seconds = time.time() - t0
    if rc in (6, 7):
        raise LockedError("\n".join(lines))
    if rc != 0:
        return "dirty", "reset check failed (exit %d)" % rc, seconds
    for l in lines:
        m = _RESET_ANSWER.match(l.strip())
        if m:
            return m.group(1), m.group(2), seconds
    return "dirty", "no answer from the hub", seconds


class ScriptResult:
    def __init__(self, name):
        self.name = name
        self.passed = 0
        self.failed = 0
        self.skipped = 0    # checks skipped because of a shared load
        self.skipped_all = False
        self.aborted = None  # reason string
        self.loaded = None   # fixture the game is in at the end (None after an abort)
        self.seconds = 0.0   # wall time of the script
        self.flaky = False   # failed first, passed on the end-of-run retry (retry_failed)
        self.first_verdict = self.retry_verdict = None
        self.second_attempt_failed = False
        self.retried = False  # failed with a shared load, then passed/failed again with a fresh one
        self.loads = 0       # real loads done by the script
        self.load_skipped = False  # the load was skipped (shared with the previous script) and the script ran on that game
        self.clean_seconds = 0.0   # seconds of the reset checks run after this script
        self.clean_checks = 0
        self.times = {}      # seconds spent in civctl per step kind (load, key, action, wait, lua, scenario, clear-advisors, ...)
        self.settle = 0.0    # seconds of the key/action time that are the scripted -Settle sleeps
        self.records = []    # record mode: {"line", "kind", "pattern", "ok", "window": [text]} per check that ran

    @property
    def ok(self):
        return self.failed == 0 and not self.aborted


def settle_seconds(arg):
    """Upper bound of the seconds a key/action step waits for the screen reader lines: -Settle ms (default 600) times -Count (default 1).
    Only used when civctl did not report the real wait (`@@waited`)."""
    m = re.search(r"-Settle\s+(\d+)", arg)
    c = re.search(r"-Count\s+(\d+)", arg)
    return (int(m.group(1)) if m else 600) * (int(c.group(1)) if c else 1) / 1000.0


def run_script(name, steps, runner, out=print, skip_load=False, on_settled=None):
    """Executes the steps. Raises LockedError on exit 6. Returns ScriptResult.
    on_settled: called once after a REAL load, when the game has settled (after the first clear-advisors, or before the first
    step that acts on the game): run_all takes the baseline of the reset check there."""
    res = ScriptResult(name)
    capture_due = False
    window = []         # [(raw, text)] since the last check
    checked = False     # the window has been looked at: the next action starts a new one
    skipped_load = False
    log_offset = log_size(getattr(runner, "lua_log", LUA_LOG))
    after_skip = False  # checks right after a skipped load are skipped too
    lua_lines = []      # [(raw, text)] non-SR> output of the most recent lua/scenario step (expect-lua)
    out("== %s (%d steps)" % (name, len(steps)))
    for i, s in enumerate(steps):
        if s.kind in CHECKS and after_skip:
            out("  SKIP line %d: %s %s (shared load)" % (s.line, s.kind, s.arg))
            res.skipped += 1
            continue
        after_skip = False
        if s.kind in CHECKS:
            checked = True
            seen = lua_lines if s.kind == "expect-lua" else window
            ok, hit = check(s.kind, s.arg, seen)
            res.records.append({"line": s.line, "kind": s.kind, "pattern": s.arg, "ok": ok,
                                "window": [t for _, t in seen]})
            label = "%s %s" % (s.kind, s.arg)
            if ok:
                res.passed += 1
                out("  PASS line %d: %s" % (s.line, label))
            else:
                res.failed += 1
                out("  FAIL line %d: %s" % (s.line, label))
                if s.kind == "expect-not":
                    out("       matched: %s" % hit)
                if seen:
                    for raw, _ in seen:
                        out("       %s" % raw)
                else:
                    out("       (no %s lines)" % ("lua output" if s.kind == "expect-lua" else "SR>"))
            continue
        if skip_load and not skipped_load and s.kind == "load":
            skipped_load = True
            after_skip = True
            res.load_skipped = True
            res.loaded = s.arg
            out("  SKIP line %d: load %s (shared with the previous script)" % (s.line, s.arg))
            continue
        if checked:
            window, checked = [], False
        if capture_due and s.kind != "clear-advisors" and s.kind != "no-lua-errors":
            capture_due = False
            on_settled()
        if s.kind == "no-lua-errors":
            checked = True
            errs = new_lua_errors(getattr(runner, "lua_log", LUA_LOG), log_offset)
            if errs:
                res.failed += 1
                out("  FAIL line %d: no-lua-errors (%d new Runtime Error lines)" % (s.line, len(errs)))
                for l in errs[:5]:
                    out("       " + l)
            else:
                res.passed += 1
                out("  PASS line %d: no-lua-errors" % s.line)
            continue
        if s.kind == "clear-advisors" and getattr(steps, "advisor_off", False):
            # the advisor is disabled by the test options: no popups to close; only drain the load-time speech into the window
            t_step = time.time()
            rc2, spoken = runner.run(["sr"])
            res.times["other"] = res.times.get("other", 0.0) + time.time() - t_step
            if rc2 == 0:
                window.extend(parse_sr_lines([l for l in spoken if l.strip()]))
            if capture_due:
                capture_due = False
                on_settled()
            continue
        if s.kind == "clear-advisors":
            out("  > clear-advisors")
            t_step = time.time()
            status, lines = clear_advisors(runner, out, s.line)
            res.times["clear-advisors"] = res.times.get("clear-advisors", 0.0) + time.time() - t_step
            window.extend(parse_sr_lines(lines))
            if capture_due and status == "ok":
                capture_due = False
                on_settled()
            if status == "locked":
                raise LockedError(lines[-1] if lines else "locked")
            if status == "crashed":
                res.failed += 1
                res.aborted = "game crashed/hung or civctl timed out in clear-advisors (line %d)" % s.line
                out("  FAIL line %d: %s" % (s.line, res.aborted))
                break
            continue
        try:
            args, tmp = civctl_args(s)
        except ScriptError as e:
            res.failed += 1
            out("  FAIL line %d: %s" % (s.line, e))
            if s.kind == "scenario":
                res.aborted = str(e)
                break
            continue
        out("  > civctl %s" % " ".join(args if s.kind != "lua" else ["lua", s.arg]))
        t_step = time.time()
        try:
            rc, lines = runner.run(args)
        finally:
            res.times[s.kind] = res.times.get(s.kind, 0.0) + time.time() - t_step
            if s.kind in ("key", "action"):
                waited = getattr(runner, "last_waited", None)   # what civctl really waited (quiet window), else the scripted -Settle
                res.settle += waited if waited is not None else settle_seconds(s.arg)
            if tmp:
                try:
                    os.remove(tmp)
                except OSError:
                    pass
        window.extend(parse_sr_lines(lines))
        if s.kind == "lua" or s.kind == "scenario":
            lua_lines = [(l.rstrip(), l.strip()) for l in lines if l.strip() and not _PREFIX.match(l)]
            for raw, _ in lua_lines:
                out("    " + raw)
        if rc in (6, 7):
            raise LockedError("\n".join(lines))
        if rc == TIMEOUT_RC:
            res.failed += 1
            res.aborted = "civctl timed out at line %d" % s.line
            out("  FAIL line %d: %s" % (s.line, lines[0]))
            break
        if rc == 5:
            res.failed += 1
            res.aborted = "game crashed or hung (civctl exit 5) at line %d" % s.line
            out("  FAIL line %d: %s" % (s.line, res.aborted))
            for l in lines[-5:]:
                out("       " + l.rstrip())
            break
        if rc != 0:
            res.failed += 1
            out("  FAIL line %d: %s exited %d" % (s.line, s.kind, rc))
            for l in lines[-5:]:
                out("       " + l.rstrip())
            if s.kind in ("load", "scenario"):
                res.aborted = "%s failed at line %d" % (s.kind, s.line)
                break
        elif s.kind == "load":
            res.loaded = s.arg
            res.loads += 1
            capture_due = on_settled is not None
    if capture_due and not res.aborted:
        on_settled()    # the script only loaded and checked: the game is still as the load left it
    if res.aborted or not shares_game(steps):
        res.loaded = None
    res.skipped_all = res.skipped > 0 and res.passed + res.failed == 0
    if res.skipped_all:
        out("   WARNING: SKIPPED-ALL: every check of this script was skipped by the shared load; it checked nothing (add '# own-load: <reason>')")
    out("   -> %d passed, %d failed%s%s" % (res.passed, res.failed, ", %d skipped" % res.skipped if res.skipped else "",
                                           ", ABORTED: " + res.aborted if res.aborted else ""))
    return res


# ---------------------------------------------------------------- record mode

def regex_for(text):
    """A regex that matches exactly this SR> text: escaped, digit runs generalised, anchored."""
    esc = re.escape(text).replace("\\ ", " ")
    return "^" + re.sub(r"\d+", lambda m: "DIGITS", esc).replace("DIGITS", r"\d+") + "$"


def _plain(pattern):
    """The literal-ish content of a regex, for similarity scoring."""
    return re.sub(r"\\[A-Za-z]|[\^$.*+?()\[\]{}|]", " ", pattern.replace("(?i)", "")).strip().lower()


def best_line(pattern, window):
    """The window text most similar to the pattern (difflib), or None if nothing is similar enough."""
    import difflib
    want = _plain(pattern)
    best, score = None, 0.0
    for t in window:
        r = difflib.SequenceMatcher(None, want, t.lower()).ratio()
        if r > score:
            best, score = t, r
    return best if score >= 0.3 else None


def render_sidecar(text, records):
    """The script text with the observed lines under each check that ran (as comments, so it is still a valid script)."""
    by_line = {r["line"]: r for r in records}
    out = []
    for no, raw in enumerate(text.splitlines(), 1):
        out.append(raw)
        r = by_line.get(no)
        if r:
            out.append("#   -> %s; window had %d SR> line(s):" % ("PASS" if r["ok"] else "FAIL", len(r["window"])))
            out.extend("#      | " + t for t in r["window"])
    return "\n".join(out) + "\n"


def propose_update(text, records):
    """Rewrites the failing `expect` lines to match the most similar line they saw. Returns (new text, [(line, old, new)])."""
    by_line = {r["line"]: r for r in records if r["kind"] == "expect" and not r["ok"]}
    out, changes = [], []
    for no, raw in enumerate(text.splitlines(), 1):
        r = by_line.get(no)
        pick = best_line(r["pattern"], r["window"]) if r else None
        if pick is None:
            out.append(raw)
            continue
        new = "expect " + regex_for(pick)
        out.append("# was: " + raw.strip())
        out.append(new)
        changes.append((no, raw.strip(), new))
    return "\n".join(out) + "\n", changes


def write_record(name, steps, result, update, out=print, directory=None):
    d = directory or REGRESS_DIR
    side = os.path.join(d, name + ".recorded.txt")
    with open(side, "w", encoding="utf-8", newline="\n") as f:
        f.write(render_sidecar(steps.text, result.records))
    out("  recorded: %s" % side)
    if update:
        new, changes = propose_update(steps.text, result.records)
        if changes:
            path = os.path.join(d, name + ".txt")
            shutil.copyfile(path, path + ".bak")
            with open(path, "w", encoding="utf-8", newline="\n") as f:
                f.write(new)
            for no, old, nw in changes:
                out("  updated line %d:\n    - %s\n    + %s" % (no, old, nw))
            out("  original kept as %s.bak" % path)
        else:
            out("  nothing to update")


def order_scripts(scripts):
    """scripts: [(name, steps)] -> grouped by first load fixture (groups in order of first appearance; no-load last)."""
    groups, order = {}, []
    for item in scripts:
        f = first_fixture(item[1])
        if f not in groups:
            groups[f] = []
            order.append(f)
        groups[f].append(item)
    order.sort(key=lambda f: f is None)
    # inside a fixture group: own-load scripts that leave the game clean first (their load serves the whole group), then the
    # plain sharing scripts, then the ones that dirty the game but may start on a shared one (no-share-load, scenario; each ends
    # the sharing), then those that need their own load AND dirty it (options). sorted() is stable.
    def rank(it):
        s = it[1]
        if not dirties_game(s):
            return 0 if must_load_itself(s) else 1
        return 3 if must_load_itself(s) else 2
    return [item for f in order for item in sorted(groups[f], key=rank)]


def retry_failed(results, scripts, runner, out=print, switch=None):
    """End-of-run flake retry: every failed (or aborted, not locked) script runs once more with a fresh load. A pass counts
    (r.flaky = verdict of the first attempt, r.first_verdict, the retry replaces the result); a second failure stays a failure
    (r.second_attempt_failed). Both attempts' verdict lines are printed."""
    by_name = dict(scripts)
    for i, r in enumerate(results):
        if r.ok or r.aborted == "locked" or r.name not in by_name:
            continue
        steps = by_name[r.name]
        first = verdict_line(r)
        out("RETRY %s (end of run, fresh load); first attempt: %s" % (r.name, first))
        opts = getattr(steps, "options", frozenset())
        steps.advisor_off = switch is not None and "advisor" not in opts
        t0 = time.time()
        try:
            if switch is not None and opts:
                _switch_options(switch, opts, out)
            r2 = run_script(r.name, steps, runner, out, skip_load=False)
        except LockedError as e:
            out("LOCKED: %s" % e)
            break
        finally:
            if switch is not None and opts:
                _switch_options(switch, (), out)
        r2.seconds = r.seconds + (time.time() - t0)
        r2.first_verdict = first
        r2.retry_verdict = verdict_line(r2)
        r2.retried = True
        if r2.ok:
            r2.flaky = True
            out("FLAKY %s: first attempt %s; retry %s" % (r.name, first, r2.retry_verdict))
        else:
            r.second_attempt_failed = True
            r2.second_attempt_failed = True
            out("STILL FAILING %s: first attempt %s; retry %s" % (r.name, first, r2.retry_verdict))
        results[i] = r2
    return results


def verdict_line(r):
    """'3 passed, 1 failed[, ABORTED: x]' for one ScriptResult."""
    return "%d passed, %d failed%s" % (r.passed, r.failed, ", ABORTED: " + r.aborted if r.aborted else "")


def run_all(scripts, runner, share_load=False, out=print, switch=None, retry=False):
    """Returns a list of ScriptResult. scripts: [(name, steps)] (already ordered).
    Load sharing: a script may skip its load when the previous script left the same fixture AND a reset check proved the game is
    back in the state a fresh load gives (reset_check: nothing open, hub in plain map mode, turn/gold/units/cities as right
    after the load; cursor and selection are put back). A dirty check never fails a script: the next one loads fresh.
    A script that shared the previous script's game and failed is run once more with its own load (a drifted game must not
    fail a script that passes alone); the result of that second run counts and has retried=True.
    switch: None (real options, nothing to do) or switch(groups) of testopts: the test options are active, a script with
    '# options:' groups gets those groups at the user's values before its load and the test values again afterwards;
    clear-advisors steps are skipped unless the script opted out of the advisor-off test option."""
    results = []
    current = None   # fixture the game is in, if known to be clean
    baseline = None  # state text taken right after the load of that game (the reset check compares with it)
    holder = {}
    for idx, (name, steps) in enumerate(scripts):
        f = first_fixture(steps)
        skip = share_load and f is not None and f == current and can_start_shared(steps)
        nxt = scripts[idx + 1][1] if idx + 1 < len(scripts) else None
        want_baseline = (share_load and f is not None and shares_game(steps) and nxt is not None
                         and first_fixture(nxt) == f and can_start_shared(nxt))

        def settled():
            holder["baseline"] = None
            verdict, text, secs = reset_check(runner, capture=True)
            holder["secs"] = holder.get("secs", 0.0) + secs
            if verdict == "snap":
                holder["baseline"] = text
            else:
                out("  (baseline for the reset check not taken: %s)" % text)
        on_settled = settled if want_baseline else None
        holder.clear()
        t0 = time.time()
        opts = getattr(steps, "options", frozenset())
        steps.advisor_off = switch is not None and "advisor" not in opts
        try:
            if switch is not None and opts:
                _switch_options(switch, opts, out)
            r = run_script(name, steps, runner, out, skip_load=skip, on_settled=on_settled)
            if skip and not r.ok and not r.aborted and r.failed:
                out("  RETRY %s with its own load (it failed on the game left by the previous script)" % name)
                holder.clear()
                r = run_script(name, steps, runner, out, skip_load=False, on_settled=on_settled)
                r.retried = True
            if "baseline" in holder:
                baseline = holder["baseline"]
            r.clean_seconds += holder.get("secs", 0.0)
            r.clean_checks += 1 if "secs" in holder else 0
            # can the next script run on this game?
            current = None
            if (share_load and r.loaded and not r.aborted and shares_game(steps) and nxt is not None and can_start_shared(nxt)
                    and first_fixture(nxt) == r.loaded):
                if baseline is None:
                    out("  reset check skipped: no baseline of the loaded game -> the next script loads fresh")
                else:
                    verdict, text, secs = reset_check(runner, baseline)
                    r.clean_seconds += secs
                    r.clean_checks += 1
                    if verdict == "clean":
                        current = r.loaded
                        out("  reset check: clean")
                        # the reset may speak (selection, cursor): drain it so it never shows up as "(earlier)" in the next script
                        t_drain = time.time()
                        runner.run(["sr"])
                        r.clean_seconds += time.time() - t_drain
                    else:
                        out("  reset check: DIRTY (%s) -> the next script loads fresh" % text)
        except LockedError as e:
            out("LOCKED: %s" % e)
            r = ScriptResult(name)
            r.failed, r.aborted = 1, "locked"
            r.seconds = time.time() - t0
            results.append(r)
            break
        finally:
            if switch is not None and opts:
                _switch_options(switch, (), out)
        r.seconds = time.time() - t0
        results.append(r)
    if retry:
        retry_failed(results, scripts, runner, out, switch)
    return results


def run_with_test_options(scripts, runner, share, use_test_options=True, out=print, testopts_mod=None, retry=False):
    """run_all under the test game options (testopts.py on ... restore in a finally, also after a crashed game: restore then
    edits UserOptions.txt). use_test_options=False (--real-options): plain run_all. Manual recovery: python util/testopts.py restore"""
    if not use_test_options:
        return run_all(scripts, runner, share, out, retry=retry)
    try:
        if testopts_mod is None:
            sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))   # python -I (civctl regress) has no util/ on sys.path
            import testopts as testopts_mod
        testopts_mod.RUNNER = runner   # tuner Lua through civctl (the batch child may hold the single tuner connection)
        if testopts_mod.cmd_on(out):
            raise RuntimeError("testopts on refused")
    except Exception as e:
        out("WARNING: test options not applied (%s); running with the real options" % e)
        return run_all(scripts, runner, share, out, retry=retry)
    try:
        return run_all(scripts, runner, share, out, switch=testopts_mod.switch, retry=retry)
    finally:
        try:
            testopts_mod.cmd_restore(out)
        except Exception as e:
            out("WARNING: could not restore the user's options (%s): run  python util/testopts.py restore" % e)


def _switch_options(switch, groups, out):
    try:
        switch(tuple(sorted(groups)))
        out("  (options: %s)" % (", ".join(sorted(groups)) + " at the user's values" if groups else "back to the test values"))
    except Exception as e:  # a failed switch must not kill the run; the script then runs with the other options
        out("  WARNING: could not switch the test options (%s)" % e)


def format_duration(sec):
    sec = int(round(sec))
    return "%d m %02d s" % (sec // 60, sec % 60) if sec >= 60 else "%d s" % sec


def timing_table(results):
    """Lines: per-script wall time and verdict."""
    w = max([len(r.name) for r in results] + [4])
    lines = []
    for r in results:
        verdict = "ABORTED" if r.aborted else ("PASS" if r.ok else "FAIL")
        if r.flaky:
            verdict = "FLAKY %s (first attempt: %s; retry: %s)" % (r.name, r.first_verdict, r.retry_verdict)
        elif r.retried:
            verdict += " (after a fresh-load retry)"
        lines.append("  %-*s  %8s  %s  [%s]" % (w, r.name, format_duration(r.seconds), verdict, breakdown(r)))
    return lines


def _bucket(times):
    k = times.get("key", 0.0) + times.get("action", 0.0)
    lua = times.get("lua", 0.0) + times.get("scenario", 0.0)
    known = k + lua + times.get("load", 0.0) + times.get("wait", 0.0) + times.get("clear-advisors", 0.0)
    return {"load": times.get("load", 0.0), "keys": k, "wait": times.get("wait", 0.0), "lua": lua,
            "advisors": times.get("clear-advisors", 0.0), "other": max(0.0, sum(times.values()) - known)}


def breakdown(r):
    """'load 40 s, keys 30 s (settle 22 s), wait 2 s, lua 3 s' for one result."""
    b = _bucket(r.times)
    parts = ["load %d" % round(b["load"]), "keys %d (settle %d)" % (round(b["keys"]), round(r.settle))]
    parts += ["%s %d" % (k, round(b[k])) for k in ("wait", "lua", "advisors") if b[k] >= 0.5]
    return ", ".join(parts) + " s"


def breakdown_total(results):
    """One line summing the breakdown of all results (where the run's time went)."""
    tot = {}
    for r in results:
        for k, v in _bucket(r.times).items():
            tot[k] = tot.get(k, 0.0) + v
    settle = sum(r.settle for r in results)
    loads = sum(r.loads for r in results)
    saved = sum(1 for r in results if r.load_skipped)
    checks = sum(r.clean_checks for r in results)
    clean_secs = sum(r.clean_seconds for r in results)
    return "BREAKDOWN: load %s (%d loads, %d saved by sharing; reset checks: %d, %s), keys %s of which settle sleeps %s, wait %s, lua %s, advisors %s, other %s" % (
        format_duration(tot.get("load", 0)), loads, saved, checks, format_duration(clean_secs), format_duration(tot.get("keys", 0)), format_duration(settle),
        format_duration(tot.get("wait", 0)), format_duration(tot.get("lua", 0)), format_duration(tot.get("advisors", 0)),
        format_duration(tot.get("other", 0)))


# ---------------------------------------------------------------- `regress changed`: which scripts do the changes affect

MOD_DIR = "ScreenReaderAccess/"
# Files every script depends on (the speech layer, list navigation, event bookkeeping, the hub wiring and HubCore): a change selects everything.
# The other Hub*.lua modules are selected through each script's `# covers:` header.
CORE_GLOBS = ("**/ScreenReader.lua", "**/KeyNavList.lua", "**/SRListen.lua", "**/KeyboardNavigation.lua",
              "**/InGameAccess.lua", "**/HubCore.lua")


def glob_regex(glob):
    """Glob -> compiled regex over a repo-relative path with '/'. '**/' = any directories, '*' / '?' stay within one name;
    without a leading '**/' the glob still matches as a path suffix (a directory boundary)."""
    g = glob.replace("\\", "/")
    out, i = "", 0
    if not g.startswith("**/"):
        out = "(?:.*/)?"
    while i < len(g):
        if g.startswith("**/", i):
            out += "(?:.*/)?"
            i += 3
        elif g[i] == "*":
            out += "[^/]*"
            i += 1
        elif g[i] == "?":
            out += "[^/]"
            i += 1
        else:
            out += re.escape(g[i])
            i += 1
    return re.compile("^" + out + "$", re.I)


def path_matches(path, globs):
    p = path.replace("\\", "/")
    return any(glob_regex(g).match(p) for g in globs)


def script_scenarios(steps):
    return {s.arg for s in steps if s.kind == "scenario"}


def select_changed(scripts, changed):
    """scripts: [(name, steps)]; changed: repo-relative changed paths.
    Returns (selected {name: reason}, uncovered [mod paths no script covers]). Every script is selected when a core file changed;
    scripts without a `# covers:` header are always selected."""
    paths = [c.replace("\\", "/") for c in changed]
    selected, uncovered = {}, []
    for name, steps in scripts:
        if not getattr(steps, "covers", ()):
            selected[name] = "no '# covers:' header"
    for p in paths:
        if p.startswith(MOD_DIR) and path_matches(p, CORE_GLOBS):
            return {name: "core file changed: %s" % p for name, _ in scripts}, []
    for p in paths:
        hit = False
        m = re.match(r"^test/regress/([^/]+)\.txt$", p)
        for name, steps in scripts:
            why = None
            if m and m.group(1) == name:
                why = "script changed"
            elif p.startswith("util/scenarios/") and p.endswith(".lua") and os.path.basename(p)[:-4] in script_scenarios(steps):
                why = "scenario changed: %s" % p
            elif p.startswith(MOD_DIR + "Database/") and any(s.kind == "action" for s in steps):
                why = "hotkey database changed: %s" % p
            elif p.startswith(MOD_DIR) and getattr(steps, "covers", ()) and path_matches(p, steps.covers):
                why = "covers %s" % p
            if why:
                hit = True
                selected.setdefault(name, why)
        if not hit and p.startswith(MOD_DIR) and not p.endswith((".civ6proj", ".modinfo")):
            uncovered.append(p)
    return {n: selected[n] for n, _ in scripts if n in selected}, uncovered


def last_green_path(directory=None):
    return os.path.join(directory or os.path.join(tempfile.gettempdir(), "civctl"), "regress-last-green.txt")


def read_last_green(directory=None):
    try:
        with open(last_green_path(directory), encoding="utf-8") as fh:
            return fh.read().strip() or None
    except OSError:
        return None


def write_last_green(rev, directory=None):
    path = last_green_path(directory)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(rev + "\n")
    return path


def git_out(args):
    """stdout lines of `git -C ROOT <args>`, or None when git fails (unknown revision, not a repository)."""
    try:
        r = subprocess.run(["git", "-C", ROOT] + args, capture_output=True, text=True, encoding="utf-8", errors="replace")
    except OSError:
        return None
    return r.stdout.splitlines() if r.returncode == 0 else None


def git_head():
    out = git_out(["rev-parse", "HEAD"])
    return out[0].strip() if out else None


def git_changed_since(base):
    """Repo-relative paths changed between base and the working tree (committed + uncommitted tracked) plus untracked files; None if
    base is unknown."""
    diff = git_out(["diff", "--name-only", base, "--"])
    if diff is None:
        return None
    return sorted(set(diff + (git_out(["ls-files", "--others", "--exclude-standard"]) or [])))


def discover(names):
    if not names or names == ["all"]:
        files = sorted(f for f in glob.glob(os.path.join(REGRESS_DIR, "*.txt")) if not f.endswith(".recorded.txt"))
    else:
        files = []
        for n in names:
            p = n if os.path.isfile(n) else os.path.join(REGRESS_DIR, n[:-4] if n.endswith(".txt") else n) + ".txt"
            if not os.path.isfile(p):
                raise ScriptError("no such script: %s" % p)
            files.append(p)
    scripts = []
    for p in files:
        name = os.path.splitext(os.path.basename(p))[0]
        with open(p, encoding="utf-8-sig") as f:
            steps = parse_script(f.read(), name)
        if steps.manual and (not names or names == ["all"]):
            continue   # manual scripts run only when named
        scripts.append((name, steps))
    return scripts


def _pid_alive(pid):
    if pid <= 0:
        return False
    if os.name == "nt":
        r = subprocess.run(["tasklist", "/FI", "PID eq %d" % pid, "/NH", "/FO", "CSV"], capture_output=True, text=True)
        return ('"%d"' % pid) in r.stdout
    try:
        os.kill(pid, 0)
        return True
    except OSError:
        return False


def acquire_run_lock(directory=None):
    """Pid file %TEMP%/civctl/regress.pid: returns (True, path) or (False, message) when another run is alive (a stale pid is replaced)."""
    d = directory or os.path.join(tempfile.gettempdir(), "civctl")
    os.makedirs(d, exist_ok=True)
    path = os.path.join(d, "regress.pid")
    try:
        with open(path) as fh:
            old = int(fh.read().strip() or 0)
    except (OSError, ValueError):
        old = 0
    if old and old != os.getpid() and _pid_alive(old):
        return False, "REFUSED: another civctl regress run is alive (pid %d, lock %s). Wait for it or stop that process." % (old, path)
    with open(path, "w") as fh:
        fh.write(str(os.getpid()))
    return True, path


def release_run_lock(path):
    try:
        with open(path) as fh:
            mine = int(fh.read().strip() or 0) == os.getpid()
        if mine:  # removed after the handle is closed (Windows refuses otherwise)
            os.remove(path)
    except (OSError, ValueError):
        pass


def select_for_changed(scripts, base=None, out=print):
    """The `regress changed` selection with its report. base: --base or the last green rev (None = run everything)."""
    base_src = "--base"
    if not base:
        base, base_src = read_last_green(), "last green `regress all`"
    changed = git_changed_since(base) if base else None
    if changed is None:
        out("changed: %s -> running ALL %d scripts" % (
            "no recorded green `regress all` (%s)" % last_green_path() if not base else "base %s is unknown to git" % base, len(scripts)))
        return scripts
    selected, uncovered = select_changed(scripts, changed)
    out("changed: base %s (%s), %d changed file(s) -> %d of %d scripts" % (base[:10], base_src, len(changed), len(selected), len(scripts)))
    for n, why in selected.items():
        out("  select %-40s %s" % (n, why))
    for p in uncovered:
        out("  NOT COVERED by any script (only `regress all` runs these): %s" % p)
    return [(n, s) for n, s in scripts if n in selected]


def main(argv=None):
    for stream in (sys.stdout, sys.stderr):
        try:
            stream.reconfigure(encoding="utf-8", errors="replace")  # python -I ignores PYTHONIOENCODING; a pipe is cp1252
        except (AttributeError, ValueError):
            pass
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("names", nargs="*", help="script names in test/regress (default/all: every script; `changed`: the scripts the changes since --base / the last green run can affect)")
    ap.add_argument("--share-load", action="store_true", help="skip the load when the previous script loaded the same fixture")
    ap.add_argument("--no-share-load", action="store_true", help="`all` shares one load per fixture by default; this gives every script its own load")
    ap.add_argument("--dry-run", action="store_true", help="parse and list the scripts, do not touch the game")
    ap.add_argument("--list", action="store_true", help="same as --dry-run")
    ap.add_argument("--record", action="store_true", help="write test/regress/<name>.recorded.txt with the SR> lines each check saw (no shared loads)")
    ap.add_argument("--update", action="store_true", help="like --record, and rewrite the failing expect lines in place (.bak kept)")
    ap.add_argument("--base", help="`changed`: git revision to diff against (default: the last green `regress all`)")
    ap.add_argument("--owner", help="civctl lock owner (required unless $CIVCTL_OWNER is set; civctl regress passes its own owner)")
    ap.add_argument("--no-batch", action="store_true", help="start powershell.exe for every civctl call (default: one long-lived `civctl batch` process)")
    ap.add_argument("--real-options", action="store_true", help="do not apply the test game options (testopts.py: advisor off, quick combat/movement) for this run")
    ap.add_argument("--no-retry", action="store_true", help="`all` / `changed` retry each failed script once with a fresh load at the end (a pass = FLAKY, run still green); this disables it")
    ap.add_argument("--clear-advisors", action="store_true", help="only close the advisor popups of the loaded game (civctl clear-advisors)")
    a = ap.parse_args(argv)
    if a.clear_advisors:
        owner = a.owner or os.environ.get("CIVCTL_OWNER")
        if not owner:
            print(OWNER_REFUSED)
            return 7
        status, lines = clear_advisors(CivctlRunner(owner=owner))
        for raw, _ in parse_sr_lines(lines):
            print(raw)
        if status == "locked":
            print(lines[-1] if lines else "locked")
            return 6
        return 5 if status == "crashed" else 0
    changed_mode = a.names[:1] == ["changed"]
    try:
        scripts = discover([] if changed_mode else a.names)
        if changed_mode:
            if len(a.names) > 1:
                raise ScriptError("`changed` takes no script names (use --base <rev>)")
            scripts = select_for_changed(scripts, a.base)
        scripts = order_scripts(scripts)
    except ScriptError as e:
        print("ERROR: %s" % e, file=sys.stderr)
        return 2
    if not scripts and changed_mode:
        print("changed: no script is affected by the changes; nothing to run (exit 0)")
        return 0
    if not scripts:
        print("no scripts in %s" % REGRESS_DIR)
        return 2
    if a.dry_run or a.list:
        for n, steps in scripts:
            print("%s: fixture %s, %d steps" % (n, first_fixture(steps) or "-", len(steps)))
        return 0
    owner = a.owner or os.environ.get("CIVCTL_OWNER")
    if not owner:
        print(OWNER_REFUSED)
        return 7
    record = a.record or a.update
    run_everything = not a.names or a.names == ["all"]
    share = (a.share_load or run_everything or changed_mode) and not a.no_share_load and not record
    if share:
        print("(sharing one load per fixture when the reset check says the game is clean; '# own-load:' and '# options:' scripts load fresh, '# no-share-load' and scenario scripts end the sharing; --no-share-load disables)")
    t0 = time.time()
    ok, lock = acquire_run_lock()
    if not ok:
        print(lock)
        return 8
    try:
        runner = CivctlRunner(owner=owner, batch=not a.no_batch)
        try:
            results = run_with_test_options(scripts, runner, share, not a.real_options,
                                            retry=(run_everything or changed_mode) and not a.no_retry and not record)
        finally:
            runner.close()
    finally:
        release_run_lock(lock)
    if run_everything and not record and results and all(r.ok for r in results) and len(results) == len(scripts):
        head = git_head()
        if head:
            print("last green recorded: %s (%s)" % (head[:10], write_last_green(head)))
    if record:
        steps_by_name = dict(scripts)
        for r in results:
            write_record(r.name, steps_by_name[r.name], r, a.update)
    print("\nTIMING:   (per script: wall time, verdict, [where it went, seconds])")
    print("\n".join(timing_table(results)))
    print(breakdown_total(results))
    p = sum(r.passed for r in results)
    f = sum(r.failed for r in results)
    print("\nSUMMARY: %d scripts, %d checks passed, %d failed%s%s" % (
        len(results), p, f, "; aborted: " + ", ".join(r.name for r in results if r.aborted) if any(r.aborted for r in results) else "",
        "; SKIPPED-ALL: " + ", ".join(r.name for r in results if r.skipped_all) if any(r.skipped_all for r in results) else ""))
    for r in results:
        if r.flaky:
            print("FLAKY %s  (first attempt: %s; retry: %s)" % (r.name, r.first_verdict, r.retry_verdict))
    print("TOTAL: %s" % format_duration(time.time() - t0))
    return 0 if all(r.ok for r in results) else 1


if __name__ == "__main__":
    sys.exit(main())
