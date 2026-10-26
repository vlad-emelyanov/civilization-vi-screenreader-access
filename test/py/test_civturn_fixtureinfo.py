"""Offline tests for util/civturn.py (parsing/judging tuner answers) and util/fixtureinfo.py (sidecar facts block)."""
import os
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "util"))
import civturn as ct  # noqa: E402
import fixtureinfo as fi  # noqa: E402


class PollTests(unittest.TestCase):
    def test_parse_and_judge(self):
        info = ct.parse_poll("TURN 61 active=true sent=false popups=-")
        self.assertEqual(info, {"turn": 61, "active": True, "sent": False, "popups": []})
        self.assertEqual(ct.judge(info, 61)[0], 0)
        self.assertEqual(ct.judge(info, 62)[0], 10)
        self.assertEqual(ct.judge(info, 60)[0], 1)

    def test_turn_reached_but_not_active_keeps_waiting(self):
        info = ct.parse_poll("TURN 62 active=false sent=true popups=-")
        code, msg = ct.judge(info, 62)
        self.assertEqual(code, 10)
        self.assertIn("not active", msg)

    def test_popups_are_reported_not_acted_on(self):
        info = ct.parse_poll("TURN 61 active=false sent=true popups=WorldCongressIntro,EraReviewPopup")
        code, msg = ct.judge(info, 62)
        self.assertEqual(code, 11)
        self.assertIn("WorldCongressIntro", msg)
        self.assertIn("not pressing keys", msg)

    def test_unreadable(self):
        self.assertIsNone(ct.parse_poll("garbage"))
        self.assertEqual(ct.judge(None, 5)[0], 2)

    def test_endturn_answers(self):
        self.assertEqual(ct.describe_endturn("REQUESTED turn=5")[0], 0)
        self.assertEqual(ct.describe_endturn("ALREADY turn=5")[0], 0)
        code, msg = ct.describe_endturn("BLOCKED ENDTURN_BLOCKING_UNITS")
        self.assertEqual(code, 1)
        self.assertIn("ENDTURN_BLOCKING_UNITS", msg)
        self.assertEqual(ct.describe_endturn("NOTACTIVE turn=5")[0], 1)
        self.assertEqual(ct.describe_endturn("???")[0], 1)

    def test_lua_chunks_mention_the_game_calls(self):
        self.assertIn("ACTION_ENDTURN", ct.ENDTURN_LUA)
        self.assertIn("GetFirstEndTurnBlocking", ct.ENDTURN_LUA)


class FactsTests(unittest.TestCase):
    SIDECAR = "turn: 59\nciv: ROME\nprofile: -\npurpose: x\nmod commit: abc\ncreated: 2026-10-22\nsize: 10 KB\n"

    def test_appends_block(self):
        out = fi.merge_facts(self.SIDECAR, ["turn: 59", "cities:", "  - Rome pop 5"], "(civctl fixture-info 2026-10-22)")
        self.assertTrue(out.startswith(self.SIDECAR))
        self.assertIn("facts: (civctl fixture-info 2026-10-22)\n  turn: 59\n  cities:\n    - Rome pop 5\n", out)

    def test_replaces_old_block_only(self):
        first = fi.merge_facts(self.SIDECAR, ["turn: 59", "gold: 5"], "(a)")
        second = fi.merge_facts(first, ["turn: 59", "gold: 99"], "(b)")
        self.assertEqual(second.count("facts:"), 1)
        self.assertIn("gold: 99", second)
        self.assertNotIn("gold: 5", second)
        self.assertTrue(second.startswith(self.SIDECAR))

    def test_replaces_block_that_is_not_last(self):
        text = self.SIDECAR + "facts: (old)\n  a: 1\nnote: kept\n"
        out = fi.merge_facts(text, ["b: 2"], "(new)")
        self.assertIn("note: kept", out)
        self.assertNotIn("a: 1", out)

    def test_sidecar_turn_and_loaded_check(self):
        self.assertEqual(fi.sidecar_turn(self.SIDECAR), 59)
        self.assertIsNone(fi.check_loaded("early-t60", 59, 59, "early-t60"))
        self.assertIn("civctl load early-t60", fi.check_loaded("early-t60", 59, 59, "other"))
        self.assertIn("turn 59", fi.check_loaded("early-t60", 61, 59, "early-t60"))

    CANNED = ["turn: 60 (your turn)", "hostile units near cities:", "  - WARRIOR (barbarian) 3 tiles from Rome at 12,8",
              "  - SCOUT (barbarian) 5 tiles from Rome at 14,9", "unimproved resources in city plots: none",
              "barbarian camps seen: (n/a: attempt to index nil)", "blockers: none"]

    def test_section_counts_from_canned_output(self):
        counts = fi.section_counts(self.CANNED)
        self.assertEqual(counts, {"hostile units near cities": 2, "unimproved resources in city plots": 0, "barbarian camps seen": None})
        self.assertEqual(fi.format_counts(counts),
                         "hostile units near cities 2, unimproved resources in city plots 0, barbarian camps seen n/a")

    def test_list_sections_land_in_the_sidecar(self):
        out = fi.merge_facts(self.SIDECAR, self.CANNED[:4], "(x)")
        self.assertIn("  hostile units near cities:\n    - WARRIOR (barbarian) 3 tiles from Rome at 12,8\n", out)

    def test_lua_has_the_new_sections(self):
        with open(fi.FACTS_LUA, encoding="utf-8") as f:
            code = f.read()
        for key in fi.LIST_SECTIONS:
            self.assertIn('sec("%s"' % key, code)
        for call in ("Improvement_ValidResources", "PrereqTech", "PrereqCivic", "IMPROVEMENT_BARBARIAN_CAMP"):
            self.assertIn(call, code)

    def test_lua_file_exists_and_is_guarded(self):
        with open(fi.FACTS_LUA, encoding="utf-8") as f:
            code = f.read()
        self.assertIn("pcall", code)
        for key in ("trade routes", "spies", "religion", "governors", "cities", "units", "blockers"):
            self.assertIn('"%s"' % key, code)


if __name__ == "__main__":
    unittest.main()
