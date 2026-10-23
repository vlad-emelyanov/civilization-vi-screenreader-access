"""Offline tests: `regress changed` selection, expect-lua, timing breakdown, endturn blocker text, key aliases, advance check."""
import os
import re
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "util"))
import civregress as cr  # noqa: E402
import civturn as ct  # noqa: E402
import keybindings as kb  # noqa: E402
from test_civregress import FakeRunner  # noqa: E402


def script(text):
    return cr.parse_script(text)


SCRIPTS = [
    ("deal", script("# covers: **/SRA_DealView.lua **/DealSpeech.lua\nload f\nkey A")),
    ("tech", script("# covers: **/TechTree.lua **/TreeNav.lua\nload f\nkey A")),
    ("hotkey", script("# covers: **/UnitPanel.lua\nload f\naction NextUnit")),
    ("scen", script("# covers: **/CityStates.lua\nload f\nscenario envoys-to-give")),
    ("nocovers", script("load f\nkey A")),
]
MOD = "ScreenReaderAccess/"


class CoversTests(unittest.TestCase):
    def test_parse_covers(self):
        s = script("# x\n# covers: a/**/b.lua  *.xml\n# covers: c\nkey A")
        self.assertEqual(s.covers, ("a/**/b.lua", "*.xml", "c"))
        self.assertEqual(script("key A").covers, ())

    def test_glob(self):
        m = cr.path_matches
        self.assertTrue(m(MOD + "Assets/UI/Screens/TechTree.lua", ["**/TechTree.lua"]))
        self.assertFalse(m(MOD + "Assets/UI/Screens/TechTree2.lua", ["**/TechTree.lua"]))
        self.assertTrue(m(MOD + "Assets/UI/Replacements/SRA_DealView.lua", ["**/SRA_*View*"]))
        self.assertTrue(m(MOD + "UI/Additions/InGameAccess.lua", ["UI/Additions/InGameAccess.lua"]))  # suffix match
        self.assertFalse(m(MOD + "UI/Additions/XInGameAccess.lua", ["InGameAccess.lua"]))
        self.assertTrue(m(MOD + "Assets/UI/Accessibility/HubMap.lua", ["**/Hub*.lua"]))
        self.assertFalse(m(MOD + "A/B/c.lua", ["A/*.lua"]))  # * stays within one directory name
        self.assertTrue(m(MOD.replace("/", "\\") + "x\\TechTree.lua", ["**/TechTree.lua"]))

    def sel(self, *changed):
        s, unc = cr.select_changed(SCRIPTS, list(changed))
        return set(s), unc, s

    def test_only_matching_and_uncovered_scripts(self):
        names, unc, _ = self.sel(MOD + "Assets/UI/Screens/TechTree.lua")
        self.assertEqual(names, {"tech", "nocovers"})  # no-covers scripts always run
        self.assertEqual(unc, [])

    def test_uncovered_mod_file_is_reported(self):
        names, unc, _ = self.sel(MOD + "Assets/UI/Popups/NaturalWonderPopup.lua", "docs/x.md")
        self.assertEqual(names, {"nocovers"})
        self.assertEqual(unc, [MOD + "Assets/UI/Popups/NaturalWonderPopup.lua"])

    def test_core_file_selects_everything(self):
        for core in ("Assets/UI/Accessibility/ScreenReader.lua", "Assets/UI/Accessibility/KeyNavList.lua",
                     "Assets/UI/Accessibility/SRListen.lua", "UI/Additions/InGameAccess.lua", "Assets/UI/Accessibility/HubCursor.lua"):
            names, _, sel = self.sel(MOD + core)
            self.assertEqual(names, {n for n, _ in SCRIPTS}, core)
            self.assertIn("core", sel[next(iter(sel))])

    def test_script_itself_and_scenario(self):
        self.assertEqual(self.sel("test/regress/deal.txt")[0], {"deal", "nocovers"})
        names, _, sel = self.sel("util/scenarios/envoys-to-give.lua")
        self.assertEqual(names, {"scen", "nocovers"})
        self.assertIn("scenario", sel["scen"])

    def test_database_change_selects_action_scripts(self):
        self.assertEqual(self.sel(MOD + "Database/Hotkeys.sql")[0], {"hotkey", "nocovers"})

    def test_unrelated_changes_select_only_headerless(self):
        self.assertEqual(self.sel("docs/a.md", "util/civctl.ps1", MOD + "ScreenReaderAccess.civ6proj")[0], {"nocovers"})

    def test_order_follows_script_order(self):
        _, _, sel = self.sel(MOD + "Assets/UI/Screens/TechTree.lua", MOD + "Assets/UI/DealSpeech.lua")
        self.assertEqual(list(sel), ["deal", "tech", "nocovers"])

    def test_last_green_roundtrip(self):
        with tempfile.TemporaryDirectory() as d:
            self.assertIsNone(cr.read_last_green(d))
            cr.write_last_green("abc123", d)
            self.assertEqual(cr.read_last_green(d), "abc123")

    def test_select_for_changed_without_base_runs_all(self):
        log = []
        old = cr.read_last_green
        cr.read_last_green = lambda d=None: None
        try:
            got = cr.select_for_changed(SCRIPTS, None, out=log.append)
        finally:
            cr.read_last_green = old
        self.assertEqual(len(got), len(SCRIPTS))
        self.assertIn("running ALL", log[0])

    def test_every_real_script_has_covers(self):
        scripts = cr.discover([])
        self.assertTrue(scripts)
        self.assertEqual([n for n, s in scripts if not s.covers], [])


class ExpectLuaTests(unittest.TestCase):
    def run_script(self, text, table):
        log = []
        return cr.run_script("t", cr.parse_script(text), FakeRunner(table), log.append), log

    def test_expect_lua_matches_tuner_output_not_sr(self):
        res, _ = self.run_script("lua InGame return 5\nexpect-lua ^62$\nexpect-lua nothing", [(["lua"], (0, ["62", "SR> spoken"]))])
        self.assertEqual((res.passed, res.failed), (1, 1))

    def test_expect_lua_ignores_sr_lines_and_is_replaced_by_next_lua_step(self):
        table = [(["lua", "InGame", "-File"], (0, ["first"])), (["scenario"], (0, ["second"]))]
        res, _ = self.run_script("lua InGame x\nscenario envoys-to-give\nexpect-lua ^second$\nexpect-lua ^first$", table)
        self.assertEqual((res.passed, res.failed), (1, 1))

    def test_expect_lua_without_output_fails_with_message(self):
        res, log = self.run_script("key A\nexpect-lua .", [(["key"], (0, ["SR> hi"]))])
        self.assertEqual(res.failed, 1)
        self.assertTrue(any("no lua output" in l for l in log))

    def test_bad_regex_rejected(self):
        with self.assertRaises(cr.ScriptError):
            cr.parse_script("expect-lua (")


class TimingTests(unittest.TestCase):
    def test_settle_seconds(self):
        self.assertEqual(cr.settle_seconds("Enter -Settle 2500"), 2.5)
        self.assertEqual(cr.settle_seconds("Down"), 0.6)
        self.assertEqual(cr.settle_seconds("Down -Count 3 -Settle 1000"), 3.0)

    def test_breakdown_columns(self):
        res = cr.run_all([("a", cr.parse_script("load f\nkey A -Settle 1000\nwait X"))], FakeRunner(), out=lambda s: None)
        r = res[0]
        self.assertEqual(r.settle, 1.0)
        self.assertEqual(set(r.times), {"load", "key", "wait"})
        line = cr.timing_table(res)[0]
        self.assertIn("[load ", line)
        self.assertIn("keys ", line)
        self.assertIn("settle 1", line)
        self.assertTrue(cr.breakdown_total(res).startswith("BREAKDOWN: load "))


class EndTurnTextTests(unittest.TestCase):
    def test_blocker_gets_human_text(self):
        code, msg = ct.describe_endturn("BLOCKED ENDTURN_BLOCKING_UNITS | Unit needs orders")
        self.assertEqual(code, 1)
        self.assertIn('"Unit needs orders"', msg)
        self.assertIn("ENDTURN_BLOCKING_UNITS", msg)
        self.assertNotIn("is pending: ", msg)

    def test_localized_text_wins_and_table_is_fallback(self):
        self.assertIn("Choisir", ct.describe_endturn("BLOCKED ENDTURN_BLOCKING_PRODUCTION | Choisir production")[1])
        self.assertIn('"Choose production"', ct.describe_endturn("BLOCKED ENDTURN_BLOCKING_PRODUCTION")[1])
        self.assertIn('"Choose production"', ct.describe_endturn("BLOCKED ENDTURN_BLOCKING_PRODUCTION | ")[1])
        self.assertIn("ENDTURN_BLOCKING_SOMETHING_NEW", ct.describe_endturn("BLOCKED ENDTURN_BLOCKING_SOMETHING_NEW")[1])

    def test_table_covers_every_enum_the_lua_maps(self):
        tags = set(re.findall(r"(ENDTURN_BLOCKING_\w+) = \"LOC_", ct.ENDTURN_LUA))
        self.assertGreater(len(tags), 20)
        self.assertEqual(tags - set(ct.BLOCKER_TEXT), set())

    def test_other_answers_unchanged(self):
        self.assertEqual(ct.describe_endturn("REQUESTED turn=5")[0], 0)
        self.assertEqual(ct.describe_endturn("NOTACTIVE turn=5")[0], 1)


class AdvanceTests(unittest.TestCase):
    def test_check_advance(self):
        self.assertEqual(ct.check_advance(10, 3, 13)[0], 0)
        self.assertEqual(ct.check_advance(10, 1, 11)[1], "advanced 1 turn: 10 -> 11")
        code, msg = ct.check_advance(10, 3, 12)
        self.assertEqual(code, 1)
        self.assertIn("expected turn 13", msg)

    def test_cli(self):
        self.assertEqual(ct.main(["advance-check", "5", "2", "7"]), 0)
        self.assertEqual(ct.main(["advance-check", "5", "2", "6"]), 1)


class KeyAliasTests(unittest.TestCase):
    def test_aliases(self):
        for name in ("Backslash", "BackSlash", "backslash", "\\"):
            self.assertEqual(kb.canonical_key_name(name), "OemPipe", name)
        self.assertEqual(kb.canonical_key_name("Enter"), "Enter")

    def test_alias_table_matches_civctl_ps1(self):
        with open(os.path.join(HERE, "..", "..", "util", "civctl.ps1"), encoding="utf-8-sig") as f:
            ps1 = f.read()
        m = re.search(r"\$KeyAliases = @\{([^}]*)\}", ps1)
        self.assertTrue(m)
        self.assertEqual(dict(re.findall(r"'([^']+)'\s*=\s*'([^']+)'", m.group(1))), kb.KEY_ALIASES)


if __name__ == "__main__":
    unittest.main()
