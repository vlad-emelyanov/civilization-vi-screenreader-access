"""Offline tests for civregress --impact / --impact-diff and the `changed` core-diff refinement."""
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "util"))
import civregress as cr  # noqa: E402


class ImpactTests(unittest.TestCase):
    def setUp(self):
        self.d = tempfile.mkdtemp()
        with open(os.path.join(self.d, "s1.txt"), "w", encoding="utf-8") as f:
            f.write("# expect old text\nload x\nkey A\nexpect ^Found a city\\b\nexpect-not Old label\nlua InGame foo\n")
        with open(os.path.join(self.d, "s1.recorded.txt"), "w", encoding="utf-8") as f:
            f.write("expect Old label\n")

    def test_substring_and_regex(self):
        hits = cr.find_impact(["Old label", "Found a city now"], self.d)
        self.assertEqual([(h[0], h[1]) for h in hits], [("s1", 4), ("s1", 5)])

    def test_comment_and_sidecar_ignored(self):
        self.assertEqual(cr.find_impact(["old text"], self.d), [])

    def test_removed_literals(self):
        diff = ['--- a/x.lua', '+++ b/x.lua', '-  say("Old label", \'ab\')', '+  say("New label")',
                '-  keep("same text")', '+  keep("same text") -- x']
        self.assertEqual(cr.removed_literals(diff), ["Old label"])


if __name__ == "__main__":
    unittest.main()
