"""Offline tests for the end-of-run flake retry of util/civregress.py."""
import os
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "util"))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import civregress as cr  # noqa: E402
from test_civregress import FakeRunner  # noqa: E402


def scripts():
    mk = cr.parse_script
    return [("a", mk("load x\nkey A\nexpect ^ok$")), ("b", mk("load x\nkey B"))]


class RetryTests(unittest.TestCase):
    def test_flaky_passes_on_retry(self):
        outs = iter([(0, ["SR> bad"]), (0, ["SR> ok"])])
        r = FakeRunner([(["key", "A"], lambda: next(outs))])
        log = []
        res = cr.run_all(scripts(), r, out=log.append, retry=True)
        self.assertTrue(all(x.ok for x in res))
        self.assertTrue(res[0].flaky)
        self.assertEqual(len([c for c in r.calls if c[0] == "load"]), 3)  # a, retry of a, b
        self.assertTrue(any(l.startswith("FLAKY a") for l in log))
        self.assertIn("FLAKY a", cr.timing_table(res)[0])

    def test_real_failure_stays_failed(self):
        r = FakeRunner([(["key", "A"], (0, ["SR> bad"]))])
        log = []
        res = cr.run_all(scripts(), r, out=log.append, retry=True)
        self.assertFalse(res[0].ok)
        self.assertFalse(res[0].flaky)
        self.assertTrue(res[0].second_attempt_failed)
        self.assertTrue(any(l.startswith("STILL FAILING a") for l in log))

    def test_no_retry_by_default(self):
        r = FakeRunner([(["key", "A"], (0, ["SR> bad"]))])
        cr.run_all(scripts(), r, out=lambda s: None)
        self.assertEqual(len([c for c in r.calls if c[0] == "load"]), 2)

    def test_locked_not_retried(self):
        r = FakeRunner([(["key", "A"], (6, ["busy"]))])
        res = cr.run_all(scripts(), r, out=lambda s: None, retry=True)
        self.assertEqual(len(res), 1)
        self.assertEqual(len([c for c in r.calls if c[0] == "load"]), 1)


if __name__ == "__main__":
    unittest.main()
