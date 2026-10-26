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

    DIR = "ScreenReaderAccess/Assets/UI/Accessibility/"
    CH = [DIR + "HubFoo.lua", DIR + "HubEvents.lua"]

    def test_registration_only(self):
        d = ["--- a/x", "+++ b/x", "@@ -1 +1,4 @@", '+include( "HubFoo" );', '+	HubCore.AddEvent( "UnitMoveComplete",		HubFoo.OnMove );	-- why',
             '+	HubCore.Listen( LuaEvents.SRA_X, HubCore.Safe( "X", HubEvents.X ) );', "+", "+-- comment"]
        ok, lines = cr.registration_only(d, self.CH)
        self.assertTrue(ok)
        self.assertEqual(len(lines), 3)
        self.assertEqual(lines[0], 'include( "HubFoo" );')

    def test_registration_of_unchanged_or_unnamed_module_is_core(self):
        self.assertEqual(cr.registration_only(['+include( "HubBar" );'], self.CH), (False, []))
        self.assertEqual(cr.registration_only(['+	HubCore.AddEvent( "A", HubBar.OnA );'], self.CH), (False, []))
        self.assertEqual(cr.registration_only(["+	LuaEvents.Foo.Add( Bar );"], self.CH), (False, []))
        self.assertEqual(cr.registration_only(['+include( "HubFoo" );'], [CORE]), (False, []))

    def test_other_changes_are_core(self):
        for extra in ("+local x = 1;", "-local x = 1;", "+--[[ block", '+	HubCore.AddEvent( "A",		function()'):
            self.assertFalse(cr.registration_only(['+include( "HubFoo" );', extra], self.CH)[0], extra)
        self.assertFalse(cr.registration_only([], self.CH)[0])

    def test_select_ignores_registration_only_core(self):
        notes = []
        sel, unc = cr.select_changed(self.scripts(), [CORE, self.DIR + "HubEvents.lua"],
                                     lambda p: ['+include( "HubEvents" );'], notes)
        self.assertEqual(list(sel), ["b"])
        self.assertEqual(unc, [])
        self.assertIn("core file %s: registration-only diff, ignored" % CORE, notes[0])
        self.assertEqual(notes[1].strip(), 'include( "HubEvents" );')

    def test_select_all_when_registered_file_unchanged(self):
        sel, _ = cr.select_changed(self.scripts(), [CORE], lambda p: ['+include( "HubEvents" );'], [])
        self.assertEqual(list(sel), ["a", "b"])

    def test_select_all_for_real_core_change(self):
        sel, _ = cr.select_changed(self.scripts(), [CORE], lambda p: ["+local x = 1;"], [])
        self.assertEqual(list(sel), ["a", "b"])
        sel, _ = cr.select_changed(self.scripts(), [CORE])   # no diff function: as before
        self.assertEqual(list(sel), ["a", "b"])


class SidecarIgnoreTests(unittest.TestCase):
    def test_recorded_sidecars_are_ignored(self):
        root = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")
        with open(os.path.join(root, "." + "gitignore"), encoding="utf-8") as f:
            self.assertIn("test/regress/*.recorded.txt", f.read().split())


if __name__ == "__main__":
    unittest.main()
