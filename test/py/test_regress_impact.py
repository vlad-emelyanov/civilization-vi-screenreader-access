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


CORE = "ScreenReaderAccess/UI/Additions/InGameAccess.lua"


class CoreRegistrationTests(unittest.TestCase):
    def scripts(self):
        return [("a", cr.parse_script("# covers: **/HubPlaces.lua\nload x\nkey A")), ("b", cr.parse_script("# covers: **/HubEvents.lua\nload x\nkey B"))]

    def test_registration_only(self):
        d = ["--- a/x", "+++ b/x", "@@ -1 +1,4 @@", '+include( "HubFoo" );', '+\tHubCore.AddEvent( "UnitMoveComplete",\t\tHubFoo.OnMove );\t-- why',
             '+\tHubCore.Listen( LuaEvents.SRA_X, HubCore.Safe( "X", HubFoo.X ) );', "+\tLuaEvents.Foo.Add( Bar );", "+", "+-- comment"]
        self.assertTrue(cr.registration_only(d))

    def test_other_changes_are_core(self):
        self.assertFalse(cr.registration_only(['+include( "HubFoo" );', "+local x = 1;"]))
        self.assertFalse(cr.registration_only(['+include( "HubFoo" );', "-local x = 1;"]))
        self.assertFalse(cr.registration_only(['+\tHubCore.AddEvent( "A",\t\tfunction()']))   # multi-line body
        self.assertFalse(cr.registration_only([]))

    def test_select_ignores_registration_only_core(self):
        notes = []
        sel, unc = cr.select_changed(self.scripts(), [CORE, "ScreenReaderAccess/Assets/UI/Accessibility/HubEvents.lua"],
                                     lambda p: ['+include( "HubEvents" );'], notes)
        self.assertEqual(list(sel), ["b"])
        self.assertEqual(unc, [])
        self.assertEqual(notes, ["core file %s: registration-only diff, ignored" % CORE])

    def test_select_all_for_real_core_change(self):
        sel, _ = cr.select_changed(self.scripts(), [CORE], lambda p: ["+local x = 1;"], [])
        self.assertEqual(list(sel), ["a", "b"])
        sel, _ = cr.select_changed(self.scripts(), [CORE])   # no diff function: as before
        self.assertEqual(list(sel), ["a", "b"])


if __name__ == "__main__":
    unittest.main()
