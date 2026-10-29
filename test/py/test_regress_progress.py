"""Offline tests for the regress progress file / estimate / regress-status (util/civregress.py Progress)."""
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "util"))
import civregress as cr  # noqa: E402


class Clock:
    def __init__(self, t=1_000_000.0):
        self.t = t

    def __call__(self):
        return self.t


def scripts4():
    mk = cr.parse_script
    return [("a", mk("load x\nkey A")), ("b", mk("load x\nkey B")), ("c", mk("load y\nkey C")), ("d", mk("load y\nkey D"))]


def result(name, ok=True, loads=1, load_s=30.0, total_s=40.0, skipped=False):
    r = cr.ScriptResult(name)
    r.passed, r.failed = (1, 0) if ok else (0, 1)
    r.loads, r.load_skipped = loads, skipped
    r.times["load"] = load_s
    r.seconds = total_s
    return r


class ProgressTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.clock = Clock()
        self.p = cr.Progress(scripts4(), True, "all", retry=True, directory=self.tmp.name, pid=4242, clock=self.clock)

    def tearDown(self):
        self.tmp.cleanup()

    def text(self):
        with open(self.p.path, encoding="utf-8") as fh:
            return fh.read()

    def test_expected_loads_per_script(self):
        self.assertEqual(sum(self.p.each), cr.simulate_loads(scripts4(), True)[0])
        self.assertEqual(len(self.p.each), 4)

    def test_counter_and_file_after_scripts(self):
        self.assertEqual(self.p.counter(), "[1/4] ")
        self.assertIn("estimate: not yet", self.text())
        self.p.begin("a", "x")
        self.clock.t += 60
        self.p.script_done(result("a"))
        self.p.begin("b", "x")
        self.assertEqual(self.p.counter(), "[2/4] ")
        t = self.text()
        self.assertIn("scripts: 1 of 4 done (1 passed, 0 failed), 0 retries pending", t)
        self.assertIn("loads: 1 done (0 shared so far)", t)
        self.assertIn("now: b (fixture x)", t)
        self.assertIn("estimate: ~", t)
        self.assertIn("runner pid: 4242", t)
        print("\n" + t)

    def test_estimate_numbers(self):
        # after a (1 load of 30 s, 10 s other): remaining expected loads x 30 + 3 scripts x 10 s
        self.p.script_done(result("a"))
        self.assertAlmostEqual(self.p.estimate_seconds(), sum(self.p.each[1:]) * 30.0 + 3 * 10.0)

    def test_failed_adds_retry(self):
        self.p.script_done(result("a", ok=False))
        t = self.text()
        self.assertIn("(0 passed, 1 failed), 1 retries pending", t)
        self.assertIn("failed so far: a", t)
        no_retry = cr.Progress(scripts4(), True, "all", retry=False, directory=self.tmp.name, pid=1, clock=self.clock)
        no_retry.script_done(result("a", ok=False))
        self.assertGreater(self.p.estimate_seconds(), no_retry.estimate_seconds())

    def test_retry_phase_and_finish(self):
        for n in "abcd":
            self.p.script_done(result(n, ok=(n != "b")))
        self.p.retry_phase(["b"])
        self.assertEqual(self.p.counter(), "[retry 1/1] ")
        self.p.retry_begin("b", "x")
        t = self.text()
        self.assertIn("retrying 1 failed script", t)
        self.assertIn("now: retry of b (fixture x)", t)
        self.p.retry_done(result("b"))
        self.assertEqual(self.p.failed, [])
        self.clock.t += 3600 * 1.5
        self.p.end("SUMMARY: 4 scripts, 4 checks passed, 0 failed")
        t = self.text()
        self.assertIn("finished ", t.splitlines()[0])
        self.assertIn("SUMMARY: 4 scripts", t)
        self.assertNotIn("estimate", t)
        self.assertIn("1h 30m", t)

    def test_status(self):
        self.p.script_done(result("a"))
        live = cr.progress_status(self.tmp.name, alive=lambda pid: pid == 4242)
        self.assertIn("scripts: 1 of 4 done", live)
        self.assertIn("updated", live)
        dead = cr.progress_status(self.tmp.name, alive=lambda pid: False)
        self.assertTrue(dead.startswith("no regress run in progress"))
        self.assertIn("ended without a summary", dead)
        self.p.end("SUMMARY: x")
        done = cr.progress_status(self.tmp.name, alive=lambda pid: True)
        self.assertTrue(done.startswith("no regress run in progress. Last run:"))
        self.assertIn("SUMMARY: x", done)
        with tempfile.TemporaryDirectory() as empty:
            self.assertIn("no regress run in progress", cr.progress_status(empty))

    def test_run_all_prefixes_verdict_and_writes_progress(self):
        class R:
            calls = []

            def run(self, args):
                return 0, ["SR> ok"]
        log = []
        cr.run_all(scripts4()[:2], R(), out=log.append, progress=self.p)
        verdicts = [l for l in log if "-> " in l]
        self.assertTrue(verdicts[0].lstrip().startswith("[1/4] -> 0 passed, 0 failed"), verdicts[0])
        self.assertTrue(verdicts[1].lstrip().startswith("[2/4] -> "))
        self.assertEqual(self.p.done, 2)


class ResultsLogTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.p = cr.Progress(scripts4(), True, "all", retry=True, directory=self.tmp.name, pid=1, clock=Clock())

    def tearDown(self):
        self.tmp.cleanup()

    def lines(self):
        with open(self.p.results_path, encoding="utf-8") as fh:
            return fh.read().splitlines()

    def test_pass_line_format(self):
        r = result("a", total_s=12.34)
        r.passed = 5
        self.assertEqual(cr.result_line("[81/184] ", r, "early-t60"), "[81/184] PASS a 5 checks (early-t60, 12.3 s, fresh load)")
        r.load_skipped = True
        self.assertTrue(cr.result_line("[1/4] ", r, None).endswith("(no fixture, 12.3 s, shared load)"))

    def test_fail_details_from_a_real_run(self):
        class R:
            calls = []

            def run(self, args):
                return 0, ["SR> Rome"]
        log = []
        scripts = [("zz-fail-demo", cr.parse_script("load x\nkey A\nexpect ^Paris$\nexpect Rome\n"))]
        p = cr.Progress(scripts, False, "zz", directory=self.tmp.name, pid=1, clock=Clock())
        res = cr.run_all(scripts, R(), out=log.append, progress=p)
        with open(p.results_path, encoding="utf-8") as fh:
            text = fh.read().splitlines()
        self.assertTrue(text[1].startswith("[1/1] FAIL zz-fail-demo: 1 passed, 1 failed (x, "), text[1])
        self.assertIn("    FAIL line 3: expect ^Paris$", text)
        self.assertIn("        SR> Rome", text)
        self.assertNotIn("PASS line", "\n".join(text))
        self.assertEqual(len(res), 1)
        print("\n" + "\n".join(text))

    def test_retry_lines_flaky_and_copy(self):
        bad = result("b", ok=False)
        self.p.script_done(bad)
        self.p.retry_phase(["b"])
        self.p.retry_begin("b", "x", "0 passed, 1 failed")
        ok = result("b")
        ok.first_verdict, ok.retry_verdict = "0 passed, 1 failed", "1 passed, 0 failed"
        self.p.retry_done(ok)
        self.p.end("SUMMARY: done")
        t = self.lines()
        k = next(n for n, l in enumerate(t) if l.startswith("RETRY b"))
        self.assertTrue(t[k].startswith("RETRY b (end of run, fresh load); first attempt: 0 passed, 1 failed"))
        self.assertTrue(t[k + 1].startswith("[retry 1/1] PASS b"))
        self.assertTrue(t[k + 2].startswith("FLAKY b:"))
        self.assertTrue(t[-1].endswith("SUMMARY: done"))
        copies = [f for f in os.listdir(self.tmp.name) if f.startswith("regress-results-")]
        self.assertEqual(len(copies), 1)

    def test_status_lists_failures(self):
        self.p.script_done(result("a", ok=False))
        txt = cr.progress_status(self.tmp.name, alive=lambda pid: True)
        self.assertIn("failures so far (details and SR> lines in", txt)
        self.assertIn("FAIL a: 0 passed, 1 failed", txt)
        self.assertIn("regress-results.txt", txt)


if __name__ == "__main__":
    unittest.main()
