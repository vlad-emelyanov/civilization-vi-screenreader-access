"""Offline tests for util/keybindings.py (InputSettings.json + default gestures -> civctl key syntax)."""
import contextlib
import io
import json
import os
import re
import shutil
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "util"))
import keybindings as kb  # noqa: E402

SETTINGS = os.path.join(HERE, "input_settings_sample.json")
SQL = os.path.join(HERE, "sample_mod.sql")

CONFIG_XML = """<GameInfo>
  <InputCategories><Row CategoryId="UI" Name="LOC_CAT_UI"/><Row CategoryId="UNIT" Name="LOC_CAT_UNIT"/></InputCategories>
  <InputActions>
    <Row ActionId="FoundCity" Name="LOC_FOUND" Description="LOC_FOUND_HELP" CategoryId="UNIT" ContextId="World" LayoutType="PC"/>
    <Row ActionId="ToggleTechTree" Name="LOC_TECH" Description="LOC_TECH_HELP" CategoryId="UI" ContextId="World" LayoutType="PC"/>
    <Row ActionId="ToggleGreatWorks" Name="LOC_GW" Description="LOC_GW_HELP" CategoryId="UI" ContextId="World" LayoutType="PC"/>
    <Row ActionId="NextAction" Name="LOC_NA" Description="" CategoryId="GLOBAL" ContextId="Universal" LayoutType="Console"/>
    <Row ActionId="ToggleGrid" Name="LOC_GRID" Description="" CategoryId="UI" ContextId="World" LayoutType="PC"/>
    <Row ActionId="ToggleYield" Name="LOC_YIELD" Description="" CategoryId="UI" ContextId="World" LayoutType="PC"/>
    <Row ActionId="ToggleResources" Name="LOC_RES" Description="" CategoryId="UI" ContextId="World" LayoutType="PC"/>
  </InputActions>
  <!-- <Row ActionId="Commented" Name="x" CategoryId="UI"/> -->
  <InputActionDefaultGestures>
    <Row ActionId="FoundCity" Index="0" GestureType="KBMouse" GestureData="LOC_OPTIONS_KEY_X"/>
    <Row ActionId="ToggleResources" Index="0" GestureType="KBMouse" GestureData="LOC_OPTIONS_KEY_Q"/>
    <Row ActionId="NextAction" Index="0" GestureType="Controller" GestureData="LOC_OPTIONS_PAD_X"/>
  </InputActionDefaultGestures>
</GameInfo>"""
TEXT_XML = """<GameData><LocalizedText>
  <Row Tag="LOC_CAT_UI"><Text>User Interface:</Text></Row>
  <Row Tag="LOC_CAT_UNIT"><Text>Unit Actions:</Text></Row>
  <Row Tag="LOC_FOUND"><Text>Found City</Text></Row>
  <Row Tag="LOC_TECH"><Text>Toggle Tech Tree</Text></Row>
  <Row Tag="LOC_GW"><Text>Toggle Great Works Screen</Text></Row>
  <Row Tag="LOC_OPTIONS_KEY_CONTROL"><Text>Control</Text></Row>
  <Row Tag="LOC_OPTIONS_KEY_I"><Text>I</Text></Row>
</LocalizedText></GameData>"""


def fake_game_dir():
    d = tempfile.mkdtemp(prefix="kbtest_")
    cfg = os.path.join(d, "Base", "Assets", "Configuration", "Data")
    txt = os.path.join(d, "Base", "Assets", "Text", "en_US")
    os.makedirs(cfg)
    os.makedirs(txt)
    with open(os.path.join(cfg, "InputConfiguration.xml"), "w", encoding="utf-8") as f:
        f.write(CONFIG_XML)
    with open(os.path.join(txt, "UI_Options_Text.xml"), "w", encoding="utf-8") as f:
        f.write(TEXT_XML)
    return d


class KeyMappingTests(unittest.TestCase):
    def test_gestures(self):
        c = kb.gesture_to_civctl
        self.assertEqual(c("LOC_OPTIONS_KEY_CONTROL+LOC_OPTIONS_KEY_N"), "Control+N")
        self.assertEqual(c("LOC_OPTIONS_KEY_SHIFT+LOC_OPTIONS_KEY_CONTROL+LOC_OPTIONS_KEY_F"), "Control+Shift+F")
        self.assertEqual(c("LOC_OPTIONS_KEY_BACKSLASH"), "OemPipe")
        self.assertEqual(c("LOC_OPTIONS_KEY_PERIOD"), "OemPeriod")
        self.assertEqual(c("LOC_OPTIONS_KEY_SHIFT+LOC_OPTIONS_KEY_0"), "Shift+D0")
        self.assertEqual(c("LOC_OPTIONS_KEY_PLUS"), "OemPlus")
        self.assertEqual(c("LOC_OPTIONS_KEY_RETURN"), "Enter")
        self.assertEqual(c("LOC_OPTIONS_KEY_PAGEDOWN"), "Next")
        self.assertEqual(c("LOC_OPTIONS_KEY_NP_DIVIDE"), "Divide")
        self.assertEqual(c("LOC_OPTIONS_KEY_NP_7"), "NumPad7")
        self.assertEqual(c("LOC_OPTIONS_KEY_F11"), "F11")
        self.assertEqual(c("LOC_OPTIONS_KEY_NOSUCHKEY"), "?")

    def test_jaws(self):
        for k in ("Add", "Control+Subtract", "Insert", "NumPad3"):
            self.assertTrue(kb.jaws_reserved(k), k)
        for k in ("Divide", "OemPlus", "Control+N", "D0"):
            self.assertFalse(kb.jaws_reserved(k), k)

    def test_jaws_list_matches_civctl_ps1(self):
        with open(os.path.join(HERE, "..", "..", "util", "civctl.ps1"), encoding="utf-8-sig") as f:
            ps1 = f.read()
        m = re.search(r"\$JawsReservedKeys = @\(([^)]*)\)", ps1)
        self.assertTrue(m)
        self.assertEqual(tuple(re.findall(r"'([^']+)'", m.group(1))), kb.JAWS_RESERVED)


class ParseTests(unittest.TestCase):
    def test_sql(self):
        with open(SQL, encoding="utf-8") as f:
            actions, gestures = kb.parse_sql(f.read())
        self.assertEqual(actions["KeyNavNotifications"]["description"], "Open a list, it's long")
        self.assertIn(("KeyNavCityReport", 0, "KBMouse", "LOC_OPTIONS_KEY_CONTROL+LOC_OPTIONS_KEY_I"), gestures)

    def test_xml_ignores_comments(self):
        actions, gestures, cats = kb.parse_config_xml(CONFIG_XML)
        self.assertNotIn("Commented", actions)
        self.assertEqual(actions["NextAction"]["layout"], "Console")
        self.assertEqual(cats["UI"], "LOC_CAT_UI")
        self.assertEqual(len(gestures), 3)


class ResolveTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.game = fake_game_dir()
        cls.bindings, cls.titles = kb.load_bindings(settings_path=SETTINGS, sql_files=[SQL], game_dir=cls.game)
        cls.by = {b.id: b for b in cls.bindings}

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.game, ignore_errors=True)

    def test_user_binding_wins_over_default(self):
        b = self.by["FoundCity"]
        self.assertEqual((b.key, b.source), ("B", "user"))   # the game default is X

    def test_primary_and_alternate(self):
        b = self.by["NextUnit"]
        self.assertEqual((b.key, b.alternate), ("OemCloseBrackets", "Shift+OemComma"))

    def test_explicit_unbound_is_not_replaced_by_default(self):
        self.assertEqual(self.by["ToggleGreatWorks"].keys, [])

    def test_missing_from_json_uses_mod_default(self):
        b = self.by["KeyNavCityReport"]
        self.assertEqual((b.key, b.source, b.name), ("Control+I", "default", "City report"))
        self.assertEqual(b.displays[0], "Control+I")

    def test_missing_from_json_uses_game_default_with_two_slots(self):
        self.assertEqual(self.by["ToggleResources"].key, "Q")
        self.assertEqual(self.by["KeyNavNotifications"].alternate, "F8")

    def test_console_and_unknown_actions_skipped(self):
        self.assertNotIn("NextAction", self.by)
        self.assertNotIn("OldRemovedAction", self.by)

    def test_names_categories_and_titles(self):
        b = self.by["ToggleTechTree"]
        self.assertEqual((b.name, b.category), ("Toggle Tech Tree", "UI"))
        self.assertEqual(self.titles["UI"], "User Interface")

    def test_flags(self):
        self.assertIn("jaws:Add", self.by["ToggleTechTree"].flags)
        self.assertFalse([f for f in self.by["FoundCity"].flags if f.startswith("jaws")])
        dup = [f for f in self.by["ToggleGrid"].flags if f.startswith("dup:")]
        self.assertEqual(len(dup), 1)
        self.assertIn("ToggleYield", dup[0])
        self.assertFalse([f for f in self.by["LensPlague"].flags if f.startswith("dup:")])   # Control+Shift+F is its own key

    def test_find_case_insensitive_and_by_name(self):
        self.assertEqual(kb.find(self.bindings, "foundcity").id, "FoundCity")
        self.assertEqual(kb.find(self.bindings, "found city").id, "FoundCity")
        self.assertIsNone(kb.find(self.bindings, "nope"))

    def test_keymap_markdown(self):
        md = kb.render_keymap(self.bindings, self.titles, "2026-01-01")
        self.assertIn("**Unbound actions: Toggle Great Works", md)
        self.assertIn("JAWS reserved keys", md)
        self.assertIn("ToggleTechTree = Add", md)
        self.assertIn("Duplicate bindings", md)
        self.assertIn("| Found City | FoundCity | LOC_OPTIONS_KEY_B | B |  | user |", md)
        self.assertIn("## User Interface", md)

    def test_no_game_dir_still_works(self):
        b, _ = kb.load_bindings(settings_path=SETTINGS, sql_files=[SQL], game_dir=None)
        by = {x.id: x for x in b}
        self.assertEqual(by["FoundCity"].key, "B")
        self.assertEqual(by["KeyNavCityReport"].key, "Control+I")

    def test_missing_settings_uses_defaults(self):
        b, _ = kb.load_bindings(settings_path=os.path.join(HERE, "nonexistent.json"), sql_files=[SQL], game_dir=self.game)
        by = {x.id: x for x in b}
        self.assertEqual((by["FoundCity"].key, by["FoundCity"].source), ("X", "default"))


class CliTests(unittest.TestCase):
    def run_cli(self, *args, game_dir=""):
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            rc = kb.main(["--settings", SETTINGS, "--game-dir", game_dir] + list(args))
        return rc, buf.getvalue()

    def test_key_output_and_exit_codes(self):
        self.assertEqual(self.run_cli("--key", "FoundCity"), (0, "B\n"))
        self.assertEqual(self.run_cli("--key", "NoSuchAction")[0], 3)

    def test_unbound_exit_code(self):
        d = fake_game_dir()
        try:
            rc, out = self.run_cli("--key", "ToggleGreatWorks", game_dir=d)
            self.assertEqual(rc, 2)
            self.assertIn("unbound", out)
        finally:
            shutil.rmtree(d, ignore_errors=True)

    def test_json_output(self):
        rc, out = self.run_cli("--json", "NextUnit")
        self.assertEqual(rc, 0)
        self.assertEqual(json.loads(out)[0]["alternate"], "Shift+OemComma")


if __name__ == "__main__":
    unittest.main()
