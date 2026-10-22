#!/usr/bin/env python
"""Speech regression runner: replays key scripts against a loaded fixture and checks the SR> lines.

  python util/civregress.py [name ...|all] [--share-load] [--dry-run] [--list]

Scripts live in test/regress/<name>.txt, one step per line (blank lines and '#' comments are ignored):

  load <fixture>          civctl load <fixture>          (its SR> lines count, e.g. the "Turn 1" announcement)
  scenario <name>         civctl scenario <name>   (util/scenarios/<name>.lua in GameCore_Tuner)
  key <args>              civctl key <args>              e.g. key Enter -Settle 2000, key Shift+Down
  wait <args>             civctl wait <args>             e.g. wait Turn \\d+ -Timeout 30 (no | or & in the regex: cmd.exe)
  lua <state> <expr>      civctl lua <state> <expr>      (the expression goes through a temp -File: quotes are safe)
  clear-advisors          presses Enter only while the AdvisorPopup context is visible (tuner probe, max 12 presses): the
                          advisor popups that a loaded or tuner-changed game queues swallow keys. With no popup up it presses
                          nothing (Enter would end the turn). Warns when the cap is hit with a popup still up. Its lines
                          stay in the window.
  no-lua-errors           PASS if Lua.log got no new "Runtime Error" line since the script began (put it last)
  expect <regex>          PASS if some SR> line since the last check matches (re.search, case-sensitive, use (?i))
  expect-not <regex>      PASS if no SR> line since the last check matches

Matching sees the text only: "SR> ", "(earlier) " and "[NOINTERRUPT] " prefixes are stripped, so ^ anchors work.
Window: lines accumulate across key/wait/load/scenario/lua steps. expect/expect-not do not clear them, so several
checks in a row look at the same lines; the first action step after a check starts a fresh window.

Failure handling: a failed expect prints FAIL with the lines it saw and the script goes on. A failed load/scenario
(non-zero exit) aborts the script, as does civctl exit 5 (game crashed/hung) at any step; exit 6 (lock held by another
owner) and 7 (no owner given) abort the whole run. After an abort the next script starts with a fresh load. Other non-zero exits of
key/wait/lua count as a failed step and the script goes on.

A script whose checks were all skipped by a shared load is reported as SKIPPED-ALL with a warning (it checked nothing).
A script that has a comment line `# no-share-load` always does its own load, and the next script does not share its game
(use it when the script changes the game: scenario, Enter, F-keys that open screens).

Loads: by default every script does its own `load`, because keys change the game state. --share-load skips the first
`load` of a script (and the `expect` lines right after it, they would see no lines) when the previous script loaded the same fixture and finished without an abort (faster, but state
drifts: use it for read-only scripts). Scripts are run grouped by their first fixture so shared loads are adjacent.

Env: CIVCTL_OWNER (or --owner) is the lock owner passed to civctl and is REQUIRED (no default; refused with exit 7 without
it). Through `civctl regress` it is the caller's owner, so the caller's lock lease is reused.
Exit code: 0 all passed, 1 something failed, 2 usage/parse error, 7 no owner.
"""
import argparse
import glob
import os
import re
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REGRESS_DIR = os.path.join(ROOT, "test", "regress")
SCENARIO_DIR = os.path.join(ROOT, "util", "scenarios")
CIVCTL = os.path.join(ROOT, "util", "civctl.ps1")
POWERSHELL = "powershell.exe"
TIMEOUT_RC = 124
MAX_ADVISOR_PRESSES = 12
LUA_LOG = os.path.join(os.environ.get("LOCALAPPDATA", ""), "Firaxis Games", "Sid Meier's Civilization VI", "Logs", "Lua.log")

ACTIONS = ("load", "scenario", "key", "wait", "lua", "clear-advisors", "no-lua-errors")
NO_ARG = ("clear-advisors", "no-lua-errors")
CHECKS = ("expect", "expect-not")
STEP_TIMEOUT = 600  # seconds per civctl call (a load is ~45 s, a newgame 70 s)


class ScriptError(Exception):
    pass


class Step:
    def __init__(self, kind, arg, line):
        self.kind, self.arg, self.line = kind, arg, line

    def __repr__(self):
        return "Step(%r, %r, line %d)" % (self.kind, self.arg, self.line)


class Steps(list):
    fresh = False  # '# no-share-load' in the script


def parse_script(text, name="script"):
    """Text -> [Step]. Raises ScriptError with file:line for unknown steps, missing arguments and bad regexes."""
    steps = Steps()
    steps.fresh = bool(re.search(r"^#\s*no-share-load", text, re.M))
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
        if kind == "lua" and len(arg.split(None, 1)) < 2:
            raise ScriptError("%s:%d: 'lua' needs <state> <expression>" % (name, no))
        if kind in ("load", "scenario") and len(arg.split()) != 1:
            raise ScriptError("%s:%d: '%s' takes one name" % (name, no, kind))
        steps.append(Step(kind, arg, no))
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
    return (hit is not None if kind == "expect" else hit is None), hit


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
        return ["load", step.arg], None
    if k in ("key", "wait"):
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
    """Runs util/civctl.cmd; run(args) -> (exit code, output lines)."""

    def __init__(self, cmd=CIVCTL, owner=None):  # cmd: path of civctl.ps1
        self.cmd = cmd
        self.env = dict(os.environ)
        self.env["CIVCTL_OWNER"] = owner or os.environ.get("CIVCTL_OWNER") or ""  # main() refuses an empty owner

    def run(self, args):
        # powershell.exe -File directly: going through civctl.cmd (%*) loses '^' and quotes in regexes.
        cmd = [POWERSHELL, "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", self.cmd] + args
        p = subprocess.Popen(cmd, cwd=ROOT, env=self.env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        try:
            stdout, _ = p.communicate(timeout=STEP_TIMEOUT)
        except subprocess.TimeoutExpired:
            # kill the whole tree: the child powershell would keep driving the game and holding the lock
            subprocess.run(["taskkill", "/T", "/F", "/PID", str(p.pid)], capture_output=True)
            p.communicate()
            return TIMEOUT_RC, ["civctl timed out after %d s (process tree killed)" % STEP_TIMEOUT]
        return p.returncode, stdout.decode("utf-8", errors="replace").splitlines()


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


def advisor_popup_up(runner):
    """Asks the game whether the AdvisorPopup context is visible. Returns (rc, up, lines)."""
    fd, tmp = tempfile.mkstemp(suffix=".lua", prefix="regress_")
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        f.write("return tostring(not ContextPtr:IsHidden())")
    try:
        rc, lines = runner.run(["lua", "AdvisorPopup", "-File", tmp])
    finally:
        try:
            os.remove(tmp)
        except OSError:
            pass
    return rc, rc == 0 and any(l.strip() == "true" for l in lines), lines


class ScriptResult:
    def __init__(self, name):
        self.name = name
        self.passed = 0
        self.failed = 0
        self.skipped = 0    # checks skipped because of a shared load
        self.skipped_all = False
        self.aborted = None  # reason string
        self.loaded = None   # fixture the game is in at the end (None after an abort)

    @property
    def ok(self):
        return self.failed == 0 and not self.aborted


def run_script(name, steps, runner, out=print, skip_load=False):
    """Executes the steps. Raises LockedError on exit 6. Returns ScriptResult."""
    res = ScriptResult(name)
    window = []         # [(raw, text)] since the last check
    checked = False     # the window has been looked at: the next action starts a new one
    skipped_load = False
    log_offset = log_size(getattr(runner, "lua_log", LUA_LOG))
    after_skip = False  # checks right after a skipped load are skipped too
    out("== %s (%d steps)" % (name, len(steps)))
    for i, s in enumerate(steps):
        if s.kind in CHECKS and after_skip:
            out("  SKIP line %d: %s %s (shared load)" % (s.line, s.kind, s.arg))
            res.skipped += 1
            continue
        after_skip = False
        if s.kind in CHECKS:
            checked = True
            ok, hit = check(s.kind, s.arg, window)
            label = "%s %s" % (s.kind, s.arg)
            if ok:
                res.passed += 1
                out("  PASS line %d: %s" % (s.line, label))
            else:
                res.failed += 1
                out("  FAIL line %d: %s" % (s.line, label))
                if s.kind == "expect-not":
                    out("       matched: %s" % hit)
                if window:
                    for raw, _ in window:
                        out("       %s" % raw)
                else:
                    out("       (no SR> lines)")
            continue
        if skip_load and not skipped_load and s.kind == "load":
            skipped_load = True
            after_skip = True
            res.loaded = s.arg
            out("  SKIP line %d: load %s (shared with the previous script)" % (s.line, s.arg))
            continue
        if checked:
            window, checked = [], False
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
        if s.kind == "clear-advisors":
            out("  > clear-advisors")
            rc, presses = 0, 0
            while True:
                rc, up, lines = advisor_popup_up(runner)
                if rc in (6, 7):
                    raise LockedError(chr(10).join(lines))
                if rc != 0:
                    out("  WARNING line %d: advisor probe failed (exit %d), no Enter pressed: %s" % (s.line, rc, " ".join(l.strip() for l in lines[-2:])))
                    break
                if not up:
                    break
                if presses >= MAX_ADVISOR_PRESSES:
                    out("  WARNING line %d: advisor popup still up after %d Enter presses" % (s.line, presses))
                    break
                rc, lines = runner.run(["key", "Enter", "-Settle", "1500"])
                presses += 1
                if rc in (6, 7):
                    raise LockedError(chr(10).join(lines))
                window.extend(parse_sr_lines(lines))
                if rc != 0:
                    break
            if rc == 5 or rc == TIMEOUT_RC:
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
        try:
            rc, lines = runner.run(args)
        finally:
            if tmp:
                try:
                    os.remove(tmp)
                except OSError:
                    pass
        window.extend(parse_sr_lines(lines))
        if s.kind == "lua" or s.kind == "scenario":
            for l in lines:
                if l.strip() and not _PREFIX.match(l):
                    out("    " + l.rstrip())
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
    if res.aborted or getattr(steps, "fresh", False):
        res.loaded = None
    res.skipped_all = res.skipped > 0 and res.passed + res.failed == 0
    if res.skipped_all:
        out("   WARNING: SKIPPED-ALL: every check of this script was skipped by the shared load; it checked nothing (add '# no-share-load')")
    out("   -> %d passed, %d failed%s%s" % (res.passed, res.failed, ", %d skipped" % res.skipped if res.skipped else "",
                                           ", ABORTED: " + res.aborted if res.aborted else ""))
    return res


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
    return [item for f in order for item in groups[f]]


def run_all(scripts, runner, share_load=False, out=print):
    """Returns a list of ScriptResult. scripts: [(name, steps)] (already ordered)."""
    results = []
    current = None  # fixture the game is in, if known to be clean
    for name, steps in scripts:
        f = first_fixture(steps)
        skip = share_load and f is not None and f == current and not getattr(steps, "fresh", False)
        try:
            r = run_script(name, steps, runner, out, skip_load=skip)
        except LockedError as e:
            out("LOCKED: %s" % e)
            r = ScriptResult(name)
            r.failed, r.aborted = 1, "locked"
            results.append(r)
            break
        results.append(r)
        current = r.loaded
    return results


def discover(names):
    if not names or names == ["all"]:
        files = sorted(glob.glob(os.path.join(REGRESS_DIR, "*.txt")))
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
            scripts.append((name, parse_script(f.read(), name)))
    return scripts


def main(argv=None):
    for stream in (sys.stdout, sys.stderr):
        try:
            stream.reconfigure(encoding="utf-8", errors="replace")  # python -I ignores PYTHONIOENCODING; a pipe is cp1252
        except (AttributeError, ValueError):
            pass
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("names", nargs="*", help="script names in test/regress (default/all: every script)")
    ap.add_argument("--share-load", action="store_true", help="skip the load when the previous script loaded the same fixture")
    ap.add_argument("--dry-run", action="store_true", help="parse and list the scripts, do not touch the game")
    ap.add_argument("--list", action="store_true", help="same as --dry-run")
    ap.add_argument("--owner", help="civctl lock owner (required unless $CIVCTL_OWNER is set; civctl regress passes its own owner)")
    a = ap.parse_args(argv)
    try:
        scripts = order_scripts(discover(a.names))
    except ScriptError as e:
        print("ERROR: %s" % e, file=sys.stderr)
        return 2
    if not scripts:
        print("no scripts in %s" % REGRESS_DIR)
        return 2
    if a.dry_run or a.list:
        for n, steps in scripts:
            print("%s: fixture %s, %d steps" % (n, first_fixture(steps) or "-", len(steps)))
        return 0
    owner = a.owner or os.environ.get("CIVCTL_OWNER")
    if not owner:
        print("REFUSED: set CIVCTL_OWNER=<your agent name> (or -Owner <name>) before driving the game")
        return 7
    results = run_all(scripts, CivctlRunner(owner=owner), a.share_load)
    p = sum(r.passed for r in results)
    f = sum(r.failed for r in results)
    print("\nSUMMARY: %d scripts, %d checks passed, %d failed%s%s" % (
        len(results), p, f, "; aborted: " + ", ".join(r.name for r in results if r.aborted) if any(r.aborted for r in results) else "",
        "; SKIPPED-ALL: " + ", ".join(r.name for r in results if r.skipped_all) if any(r.skipped_all for r in results) else ""))
    return 0 if all(r.ok for r in results) else 1


if __name__ == "__main__":
    sys.exit(main())
