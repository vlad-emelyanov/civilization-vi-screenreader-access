import json
import os
import shutil
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "util"))
import civregress as cr  # noqa: E402
import testopts as t  # noqa: E402

SAMPLE = (";comment\r\nVersion 1\r\n\r\n[Gameplay]\r\n;Skips movement\r\nQuickMovement 0\r\n;c\r\nQuickCombat 0\r\n"
          "LookAtPlayerTurnCombat 2\r\nLookAtPlayerOffTurnCombat 1\r\n\r\n[Tutorial]\r\nTutorialLevel 0\r\n"
          "[Gameplay]\r\nOther 5\r\n[Interface]\r\nPlayHistoricMomentAnimation 1\r\n").encode("latin-1")


def quiet(*_):
    pass


class FileTests(unittest.TestCase):
    def setUp(self):
        self.d = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.d)
        self.path = os.path.join(self.d, "UserOptions.txt")
        with open(self.path, "wb") as f:
            f.write(SAMPLE)
        self.old = (t.USER_OPTIONS, t.BACKUP, t.game_running)
        t.USER_OPTIONS, t.BACKUP = self.path, os.path.join(self.d, "sub", "backup.json")
        t.game_running = lambda: False
        self.addCleanup(self.undo)

    def undo(self):
        t.USER_OPTIONS, t.BACKUP, t.game_running = self.old

    def raw(self):
        with open(self.path, "rb") as f:
            return f.read()

    def test_round_trip_keeps_everything_else(self):
        self.assertEqual(t.file_values()["QuickMovement"], "0")
        t.cmd_on(quiet)
        self.assertEqual(t.file_values(), t.TEST_VALUES)
        self.assertEqual(self.raw().count(b"\r\n"), SAMPLE.count(b"\r\n"))
        self.assertIn(b"Other 5", self.raw())
        t.cmd_restore(quiet)
        self.assertEqual(self.raw(), SAMPLE)
        self.assertFalse(os.path.exists(t.BACKUP))

    def test_backup_never_overwritten(self):
        t.cmd_on(quiet)
        t.cmd_on(quiet)   # second run sees test values; the backup must keep the real ones
        with open(t.BACKUP) as f:
            self.assertEqual(json.load(f)["TutorialLevel"], "0")
        t.cmd_restore(quiet)
        self.assertEqual(self.raw(), SAMPLE)

    def test_restore_without_backup_is_noop(self):
        self.assertEqual(t.cmd_restore(quiet), 0)
        self.assertEqual(self.raw(), SAMPLE)

    def test_switch_groups(self):
        t.cmd_on(quiet)
        t.switch(("animations",))
        v = t.file_values()
        self.assertEqual((v["QuickCombat"], v["TutorialLevel"]), ("0", "-1"))
        t.switch(("advisor",))
        v = t.file_values()
        self.assertEqual((v["QuickCombat"], v["TutorialLevel"]), ("1", "0"))
        t.switch(())
        self.assertEqual(t.file_values(), t.TEST_VALUES)

    def test_missing_key_errors(self):
        with self.assertRaises(RuntimeError):
            t.file_write({"Nope": "1"})

    def test_lua_strings(self):
        self.assertIn('Options.SetUserOption("Gameplay", "QuickCombat", 1)', t.lua_write(t.TEST_VALUES))
        self.assertNotIn("Save", t.lua_write(t.TEST_VALUES))
        self.assertIn("pcall", t.lua_write(t.TEST_VALUES))
        self.assertIn('UserConfiguration.SetValue("QuickCombat", 1)', t.lua_write(t.TEST_VALUES))

    def test_clean_values_drops_nil(self):
        self.assertEqual(t.clean_values({"QuickCombat": "nil", "TutorialLevel": "-1", "Bogus": "1"}), {"TutorialLevel": "-1"})

    def test_on_refuses_test_values_without_backup(self):
        t.file_write(t.TEST_VALUES)
        self.assertEqual(t.cmd_on(quiet), 1)
        self.assertFalse(os.path.exists(t.BACKUP))

    def test_on_failure_restores(self):
        orig = t.write_values
        calls = []

        def boom(values, running=None):
            calls.append(values)
            if values == t.TEST_VALUES:
                raise RuntimeError("x")
            orig(values, running)
        t.write_values = boom
        try:
            with self.assertRaises(RuntimeError):
                t.cmd_on(quiet)
        finally:
            t.write_values = orig
        self.assertFalse(os.path.exists(t.BACKUP))
        self.assertEqual(self.raw(), SAMPLE)


class DirectiveTests(unittest.TestCase):
    def test_parse(self):
        s = cr.parse_script("# options: animations advisor\nload x\n")
        self.assertEqual(s.options, frozenset({"animations", "advisor"}))
        self.assertTrue(cr.script_needs_fresh(s))
        self.assertEqual(cr.parse_script("load x\n").options, frozenset())
        self.assertFalse(cr.script_needs_fresh(cr.parse_script("load x\n")))
        with self.assertRaises(cr.ScriptError):
            cr.parse_script("# options: bogus\nload x\n")

    def test_real_scripts_parse(self):
        names = [n for n, _ in cr.discover([])]
        self.assertIn("advisor-popup", names)


class FakeRunner:
    def run(self, args):
        return 0, []


class RunAllTests(unittest.TestCase):
    def setUp(self):
        self.seen = []
        self.orig = cr.clear_advisors
        cr.clear_advisors = lambda *a, **k: (self.seen.append(1), ("ok", []))[1]
        self.addCleanup(lambda: setattr(cr, "clear_advisors", self.orig))

    def test_switch_around_opt_out_scripts(self):
        calls = []
        scripts = [("a", cr.parse_script("load x\nclear-advisors\n")),
                   ("b", cr.parse_script("# options: animations\nload x\nclear-advisors\n")),
                   ("c", cr.parse_script("# options: advisor\nload x\nclear-advisors\n"))]
        res = cr.run_all(scripts, FakeRunner(), share_load=True, out=quiet, switch=calls.append)
        self.assertEqual(calls, [("animations",), (), ("advisor",), ()])
        self.assertEqual(len(self.seen), 1)    # only the advisor opt-out clears advisors
        self.assertNotIn("clear-advisors", res[0].times)
        self.assertEqual(len(res), 3)

    def test_no_switch_means_real_options(self):
        cr.run_all([("a", cr.parse_script("load x\nclear-advisors\n"))], FakeRunner(), out=quiet)
        self.assertEqual(len(self.seen), 1)

    def test_run_with_test_options_restores_on_error(self):
        events = []

        class M:
            @staticmethod
            def cmd_on(out):
                events.append("on")

            @staticmethod
            def cmd_restore(out):
                events.append("restore")

            @staticmethod
            def switch(g):
                pass

        orig = cr.run_all

        def boom(*a, **k):
            raise KeyboardInterrupt()

        cr.run_all = boom
        try:
            with self.assertRaises(KeyboardInterrupt):
                cr.run_with_test_options([], FakeRunner(), False, True, quiet, M)
        finally:
            cr.run_all = orig
        self.assertEqual(events, ["on", "restore"])


if __name__ == "__main__":
    unittest.main()
