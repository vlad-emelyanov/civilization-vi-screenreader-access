"""Offline tests for util/civregress.py (parser, expect matching, script flow with a fake civctl)."""
import os
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "util"))
import civregress as cr  # noqa: E402


class FakeRunner:
    """Maps the first matching (prefix of args) to (rc, lines); records every call."""

    def __init__(self, table=None, default=(0, [])):
        self.table, self.default, self.calls = table or [], default, []

    def run(self, args):
        self.calls.append(list(args))
        for prefix, result in self.table:
            if args[:len(prefix)] == prefix:
                if callable(result):
                    result = result()
                return result
        return self.default


class ParserTests(unittest.TestCase):
    def test_parse(self):
        steps = cr.parse_script("# c\n\nload early-start\nKey Enter -Settle 2000\nexpect ^Turn \\d+\n")
        self.assertEqual([s.kind for s in steps], ["load", "key", "expect"])
        self.assertEqual(steps[1].arg, "Enter -Settle 2000")
        self.assertEqual(steps[2].line, 5)

    def test_action_step(self):
        steps = cr.parse_script("action KeyNavCityReport -Settle 1500\n")
        self.assertEqual(steps[0].kind, "action")
        self.assertEqual(cr.civctl_args(steps[0])[0], ["action", "KeyNavCityReport", "-Settle", "1500"])

    def test_errors(self):
        for bad in ("frobnicate x", "key", "expect (", "lua InGame", "load a b"):
            with self.assertRaises(cr.ScriptError, msg=bad):
                cr.parse_script(bad)

    def test_first_fixture(self):
        self.assertEqual(cr.first_fixture(cr.parse_script("key A\nload x\nload y")), "x")
        self.assertIsNone(cr.first_fixture(cr.parse_script("key A")))


class MatchTests(unittest.TestCase):
    def test_prefix_stripping(self):
        lines = cr.parse_sr_lines(["noise", "SR> [NOINTERRUPT] Turn 5, 3600 BC", "(earlier) SR> Hello", "SR> Warrior"])
        self.assertEqual([t for _, t in lines], ["Turn 5, 3600 BC", "Hello", "Warrior"])
        ok, hit = cr.check("expect", r"^Turn 5", lines)
        self.assertTrue(ok)
        self.assertEqual(hit, "SR> [NOINTERRUPT] Turn 5, 3600 BC")

    def test_expect_not(self):
        lines = cr.parse_sr_lines(["SR> Turn ended"])
        self.assertFalse(cr.check("expect-not", "Turn ended", lines)[0])
        self.assertTrue(cr.check("expect-not", "Closed", lines)[0])
        self.assertFalse(cr.check("expect", "Closed", lines)[0])

    def test_wait_args_joined(self):
        args, _ = cr.civctl_args(cr.Step("wait", r"^Turn \d+ now -Timeout 30", 1))
        self.assertEqual(args, ["wait", r"^Turn \d+ now", "-Timeout", "30"])

    def test_args(self):
        args, tmp = cr.civctl_args(cr.Step("key", "Enter -Settle 2000", 1))
        self.assertEqual(args, ["key", "Enter", "-Settle", "2000"])
        args, tmp = cr.civctl_args(cr.Step("lua", 'InGame Game.GetCurrentGameTurn("x y")', 1))
        try:
            self.assertEqual(args[:3], ["lua", "InGame", "-File"])
            with open(tmp, encoding="utf-8") as f:
                self.assertEqual(f.read(), 'Game.GetCurrentGameTurn("x y")')
        finally:
            os.remove(tmp)


class FlowTests(unittest.TestCase):
    def quiet(self):
        self.log = []
        return self.log.append

    def test_window_and_continue_after_fail(self):
        r = FakeRunner([(["load"], (0, ["SR> Turn 1, 4000 BC"])), (["key", "Down"], (0, ["SR> Rome"])),
                        (["key", "Enter"], (0, ["SR> [NOINTERRUPT] Closed"]))])
        steps = cr.parse_script("load f\nexpect ^Turn 1\nkey Down\nexpect ^Athens\nexpect Rome\nkey Enter\nexpect-not Rome\nexpect Closed")
        res = cr.run_script("t", steps, r, self.quiet())
        # pass, fail, pass (same window as the failed check), pass (new window), pass
        self.assertEqual((res.passed, res.failed), (4, 1))
        self.assertIsNone(res.aborted)
        self.assertEqual(res.loaded, "f")
        self.assertTrue(any("FAIL" in l for l in self.log))
        self.assertTrue(any("SR> Rome" in l for l in self.log))  # actual lines shown on failure

    def test_accumulates_across_actions(self):
        r = FakeRunner([(["key", "A"], (0, ["SR> one"])), (["key", "B"], (0, ["SR> two"]))])
        steps = cr.parse_script("key A\nkey B\nexpect ^one\nexpect ^two")
        res = cr.run_script("t", steps, r, self.quiet())
        self.assertEqual((res.passed, res.failed), (2, 0))

    def test_crash_aborts(self):
        r = FakeRunner([(["key", "B"], (5, ["GAME CRASHED"]))])
        steps = cr.parse_script("load f\nkey B\nexpect x\nkey C")
        res = cr.run_script("t", steps, r, self.quiet())
        self.assertTrue(res.aborted)
        self.assertIsNone(res.loaded)
        self.assertEqual(len(r.calls), 2)  # stopped before the next key
        self.assertFalse(res.ok)

    def test_failed_load_aborts_failed_key_continues(self):
        r = FakeRunner([(["load"], (1, ["nope"]))])
        res = cr.run_script("t", cr.parse_script("load f\nkey A"), r, self.quiet())
        self.assertTrue(res.aborted)
        r = FakeRunner([(["key"], (1, ["REFUSED"]))])
        res = cr.run_script("t", cr.parse_script("key Add\nkey A"), r, self.quiet())
        self.assertIsNone(res.aborted)
        self.assertEqual(res.failed, 2)

    def test_locked_raises(self):
        r = FakeRunner([(["key"], (6, ["game in use by 'x'"]))])
        with self.assertRaises(cr.LockedError):
            cr.run_script("t", cr.parse_script("key A"), r, self.quiet())

    def test_no_owner_raises(self):
        r = FakeRunner([(["key"], (7, ["REFUSED: set CIVCTL_OWNER=<your agent name>"]))])
        with self.assertRaises(cr.LockedError):
            cr.run_script("t", cr.parse_script("key A"), r, self.quiet())

    def test_main_requires_owner(self):
        old = os.environ.pop("CIVCTL_OWNER", None)
        try:
            self.assertEqual(cr.main(["early-turn-announce"]), 7)
        finally:
            if old is not None:
                os.environ["CIVCTL_OWNER"] = old

    def test_scenario_missing_aborts(self):
        res = cr.run_script("t", cr.parse_script("scenario no-such-scenario-xyz\nkey A"), FakeRunner(), self.quiet())
        self.assertTrue(res.aborted)


class AdvisorAndSkipTests(unittest.TestCase):
    def test_no_popup_presses_nothing(self):
        r = FakeRunner([(["lua", "AdvisorPopup"], (0, ["false"]))])
        res = cr.run_script("t", cr.parse_script("clear-advisors"), r, lambda s: None)
        self.assertFalse([c for c in r.calls if c[0] == "key"])
        self.assertTrue(res.ok)

    def test_presses_while_popup_up(self):
        state = {"up": 2}

        def probe():
            return 0, ["true" if state["up"] > 0 else "false"]

        def press():
            state["up"] -= 1
            return 0, ["SR> ADVISOR: x"]
        r = FakeRunner([(["lua", "AdvisorPopup"], probe), (["key", "Enter"], press)])
        cr.run_script("t", cr.parse_script("clear-advisors"), r, lambda s: None)
        self.assertEqual(len([c for c in r.calls if c[0] == "key"]), 2)

    def test_cap_warns(self):
        r = FakeRunner([(["lua", "AdvisorPopup"], (0, ["true"]))])
        log = []
        cr.run_script("t", cr.parse_script("clear-advisors"), r, log.append)
        self.assertEqual(len([c for c in r.calls if c[0] == "key"]), cr.MAX_ADVISOR_PRESSES)
        self.assertTrue(any("WARNING" in l and "still up" in l for l in log))

    def test_skipped_all(self):
        text = "load x" + chr(10) + "expect ^T"
        scripts = [("a", cr.parse_script(text)), ("b", cr.parse_script(text))]
        r = FakeRunner([(["load"], (0, ["SR> Turn 1"]))])
        log = []
        res = cr.run_all(scripts, r, share_load=True, out=log.append)
        self.assertFalse(res[0].skipped_all)
        self.assertTrue(res[1].skipped_all)
        self.assertTrue(any("SKIPPED-ALL" in l for l in log))

    def test_no_lua_errors(self):
        import tempfile
        fd, path = tempfile.mkstemp()
        os.close(fd)
        try:
            with open(path, "w") as f:
                f.write("old Runtime Error: ancient\n")
            r = FakeRunner()
            r.lua_log = path

            def key():
                with open(path, "a") as f:
                    f.write("[x] Runtime Error: boom\n")
                return 0, []
            r.table = [(["key"], key)]
            res = cr.run_script("t", cr.parse_script("no-lua-errors"), r, lambda s: None)
            self.assertEqual((res.passed, res.failed), (1, 0))
            res = cr.run_script("t", cr.parse_script("key A" + chr(10) + "no-lua-errors"), r, lambda s: None)
            self.assertEqual((res.passed, res.failed), (0, 1))
        finally:
            os.remove(path)


class ShiftTabTests(unittest.TestCase):
    def test_shift_tab_refused(self):
        for bad in ("Shift+Tab", "shift+tab -Settle 5", "Control+Shift+Tab"):
            with self.assertRaises(cr.ScriptError, msg=bad):
                cr.parse_script("key " + bad)
        cr.parse_script("key Control+Tab" + chr(10) + "key Shift+E" + chr(10) + "key Tab")

    def test_load_passes_keep_advisors(self):
        self.assertEqual(cr.civctl_args(cr.Step("load", "early-start", 1))[0], ["load", "early-start", "-KeepAdvisors"])


class ClearAdvisorsTests(unittest.TestCase):
    def test_standalone_function_presses_until_gone(self):
        ups = iter([(0, ["true"]), (0, ["true"]), (0, ["false"])])
        r = FakeRunner([(["lua", "AdvisorPopup"], lambda: next(ups)), (["key", "Enter"], (0, ["SR> Advisor text"]))])
        status, lines = cr.clear_advisors(r, lambda s: None)
        self.assertEqual(status, "ok")
        self.assertEqual(len([c for c in r.calls if c[0] == "key"]), 2)
        self.assertEqual(lines, ["SR> Advisor text"] * 2)

    def test_crash_and_lock_statuses(self):
        r = FakeRunner([(["lua", "AdvisorPopup"], (0, ["true"])), (["key", "Enter"], (5, ["GAME HUNG"]))])
        self.assertEqual(cr.clear_advisors(r, lambda s: None)[0], "crashed")
        r = FakeRunner([(["lua", "AdvisorPopup"], (6, ["game in use by x"]))])
        self.assertEqual(cr.clear_advisors(r, lambda s: None)[0], "locked")


class OrderTests(unittest.TestCase):
    def test_grouping_and_share_load(self):
        mk = lambda t: cr.parse_script(t)  # noqa: E731
        scripts = [("a", mk("load x\nkey A")), ("b", mk("load y\nkey A")), ("c", mk("load x\nkey A")), ("n", mk("key A"))]
        ordered = cr.order_scripts(scripts)
        self.assertEqual([n for n, _ in ordered], ["a", "c", "b", "n"])
        out = []
        r = FakeRunner()
        cr.run_all(ordered, r, share_load=True, out=out.append)
        loads = [c for c in r.calls if c[0] == "load"]
        self.assertEqual(loads, [["load", "x", "-KeepAdvisors"], ["load", "y", "-KeepAdvisors"]])
        r = FakeRunner()
        cr.run_all(ordered, r, share_load=False, out=out.append)
        self.assertEqual(len([c for c in r.calls if c[0] == "load"]), 3)

    def test_share_load_reloads_after_abort(self):
        scripts = [("a", cr.parse_script("load x\nkey A")), ("b", cr.parse_script("load x\nkey B"))]
        r = FakeRunner([(["key", "A"], (5, ["GAME HUNG"]))])
        cr.run_all(scripts, r, share_load=True, out=lambda s: None)
        self.assertEqual(len([c for c in r.calls if c[0] == "load"]), 2)

    def test_scenario_and_marker_scripts_load_fresh_and_end_sharing(self):
        mk = cr.parse_script
        scripts = [("a", mk("load x\nkey A")), ("s", mk("load x\nscenario foo\nkey A")), ("m", mk("# no-share-load\nload x\nkey A")),
                   ("b", mk("load x\nkey A")), ("c", mk("load x\nkey A"))]
        self.assertTrue(scripts[1][1].fresh)
        r = FakeRunner()
        orig = cr.civctl_args
        try:
            cr.civctl_args = lambda st, o=orig: (["scenario", "foo"], None) if st.kind == "scenario" else o(st)
            cr.run_all(scripts, r, share_load=True, out=lambda s: None)
        finally:
            cr.civctl_args = orig
        # a loads; s fresh; m fresh; b fresh (m ended sharing); c shares b's game
        self.assertEqual(len([c for c in r.calls if c[0] == "load"]), 4)

    def test_failed_shared_script_is_retried_with_own_load(self):
        scripts = [("a", cr.parse_script("load x\nkey A")), ("b", cr.parse_script("load x\nkey B\nexpect ^ok$"))]
        outputs = iter([(0, ["SR> drifted"]), (0, ["SR> ok"])])
        r = FakeRunner([(["key", "B"], lambda: next(outputs))])
        res = cr.run_all(scripts, r, share_load=True, out=lambda s: None)
        self.assertTrue(res[1].ok and res[1].retried)
        self.assertEqual(len([c for c in r.calls if c[0] == "load"]), 2)

    def test_timing_table(self):
        res = cr.run_all([("a", cr.parse_script("key A"))], FakeRunner(), out=lambda s: None)
        self.assertGreaterEqual(res[0].seconds, 0)
        self.assertIn("PASS", cr.timing_table(res)[0])
        self.assertEqual(cr.format_duration(125), "2 m 05 s")

    def test_locked_stops_run(self):
        scripts = [("a", cr.parse_script("key A")), ("b", cr.parse_script("key B"))]
        r = FakeRunner([(["key"], (6, ["busy"]))])
        res = cr.run_all(scripts, r, out=lambda s: None)
        self.assertEqual(len(res), 1)


class RecordTests(unittest.TestCase):
    SCRIPT = ("# blind script\nload f\nexpect ^Turn 1\nkey Down\nexpect ^Rome, 2 tiles away$\nexpect-not Rome\n"
              "key Enter\nexpect Closed\nexpect ^Nothing like it$\n")

    def record(self, table):
        steps = cr.parse_script(self.SCRIPT)
        res = cr.run_script("t", steps, FakeRunner(table), lambda s: None)
        return steps, res

    TABLE = [(["load"], (0, ["SR> Turn 1, 4000 BC"])), (["key", "Down"], (0, ["SR> Rome, 3 tiles away"])),
             (["key", "Enter"], (0, ["SR> [NOINTERRUPT] Closed menu"]))]

    def test_records_collected(self):
        _, res = self.record(self.TABLE)
        self.assertEqual([(r["line"], r["ok"]) for r in res.records],
                         [(3, True), (5, False), (6, False), (8, True), (9, False)])
        self.assertEqual(res.records[1]["window"], ["Rome, 3 tiles away"])

    def test_sidecar_is_still_a_valid_script(self):
        steps, res = self.record(self.TABLE)
        side = cr.render_sidecar(steps.text, res.records)
        self.assertIn("#   -> FAIL; window had 1 SR> line(s):\n#      | Rome, 3 tiles away", side)
        again = cr.parse_script(side)
        self.assertEqual([s.kind for s in again], [s.kind for s in steps])

    def test_update_rewrites_failing_expects_only(self):
        steps, res = self.record(self.TABLE)
        new, changes = cr.propose_update(steps.text, res.records)
        self.assertEqual([c[0] for c in changes], [5])  # line 9 shares no text with any line; expect-not is never touched
        self.assertIn("# was: expect ^Rome, 2 tiles away$", new)
        lines = new.splitlines()
        proposed = [l for l in lines if l.startswith("expect ") and "Rome" in l]
        self.assertEqual(len(proposed), 1)
        import re
        self.assertTrue(re.search(proposed[0][len("expect "):], "Rome, 3 tiles away"))
        self.assertIn("expect ^Nothing like it$", lines)  # untouched
        cr.parse_script(new)  # still parses

    def test_regex_for_generalises_numbers(self):
        import re
        rx = cr.regex_for("Turn 5, 3600 BC (Warrior)")
        self.assertEqual(rx, r"^Turn \d+, \d+ BC \(Warrior\)$")
        self.assertTrue(re.search(rx, "Turn 6, 10 BC (Warrior)"))

    def test_write_record_makes_bak(self):
        import tempfile
        d = tempfile.mkdtemp()
        try:
            path = os.path.join(d, "t.txt")
            with open(path, "w", encoding="utf-8", newline="\n") as f:
                f.write(self.SCRIPT)
            steps, res = self.record(self.TABLE)
            cr.write_record("t", steps, res, update=True, out=lambda s: None, directory=d)
            self.assertTrue(os.path.isfile(path + ".bak"))
            with open(path + ".bak", encoding="utf-8") as f:
                self.assertEqual(f.read(), self.SCRIPT)
            self.assertTrue(os.path.isfile(os.path.join(d, "t.recorded.txt")))
            with open(path, encoding="utf-8") as f:
                self.assertIn("# was: expect ^Rome, 2 tiles away$", f.read())
        finally:
            import shutil
            shutil.rmtree(d, ignore_errors=True)


class RunLock(unittest.TestCase):
    def test_lock_refuses_live_pid_and_replaces_stale(self):
        import tempfile
        d = tempfile.mkdtemp()
        ok, path = cr.acquire_run_lock(d)
        self.assertTrue(ok)
        with open(path, "w") as fh:
            fh.write(str(os.getppid()))  # parent process: alive, not us
        ok2, msg = cr.acquire_run_lock(d)
        self.assertFalse(ok2)
        self.assertIn("another civctl regress run", msg)
        with open(path, "w") as fh:
            fh.write("999999")  # dead
        ok3, _ = cr.acquire_run_lock(d)
        self.assertTrue(ok3)
        cr.release_run_lock(path)
        self.assertFalse(os.path.exists(path))


if __name__ == "__main__":
    unittest.main()
