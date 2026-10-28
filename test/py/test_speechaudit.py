import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "..", "util"))
import speechaudit as sa  # noqa: E402


def audit(lines):
    with tempfile.TemporaryDirectory() as d:
        p = os.path.join(d, "Lua.log")
        with open(p, "w", encoding="utf-8") as f:
            for l in lines:
                f.write("Foo: #SCREENREADER - %s\n" % l)
        return sa.analyse([p])


class SpeechAuditTest(unittest.TestCase):
    def test_clean_tokens(self):
        self.assertEqual(sa.clean("Press [KEY:Enter|A] or [PAD:X] now"), "Press Enter or now")

    def test_same_first(self):
        found = audit(["Pick: 3 missions", "Counterspy, Campus, 8 turns, 1 of 3", "Counterspy, Harbor, 8 turns, 2 of 3",
                       "Counterspy, Theater, 8 turns, 3 of 3"])
        self.assertIn("same-first", [f["flag"] for f in found])

    def test_repeats_title(self):
        found = audit(["Counterspy missions in Rome", "Counterspy, Campus, 1 of 2", "Counterspy, Harbor, 2 of 2"])
        self.assertIn("repeats-title", [f["flag"] for f in found])

    def test_late_diff(self):
        a = "one two three four five six seven eight nine ten eleven twelve thirteen fourteen fifteen sixteen seventeen eighteen nineteen twenty twentyone"
        found = audit(["Items", a + " a, 1 of 2", a + " b, 2 of 2"])
        self.assertIn("late-diff", [f["flag"] for f in found])

    def test_clean_list_not_flagged(self):
        found = audit(["Pick", "Campus, 8 turns, 1 of 3", "Harbor, 5 turns, 2 of 3", "Theater, 2 turns, 3 of 3"])
        self.assertEqual(found, [])

    def test_run_breaks_when_total_changes(self):
        runs = sa.runs_of(["Alpha, 1 of 2", "Beta, 2 of 2", "Gamma, 1 of 5"])
        self.assertEqual(len(runs), 2)


if __name__ == "__main__":
    unittest.main()
