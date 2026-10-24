"""Every KeyNav* input action of the mod must be described in the help list (Control+H).

The descriptions live in ScreenReaderAccess/Assets/UI/Accessibility/HelpText.lua, the one place for shortcut text.
A new or changed shortcut (input action, or a key inside one of our lists) needs an entry there; this test enforces it
for the input actions declared in ScreenReaderAccess/Database/*.sql.
"""
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SQL_DIR = ROOT / "ScreenReaderAccess" / "Database"
HELP = ROOT / "ScreenReaderAccess" / "Assets" / "UI" / "Accessibility" / "HelpText.lua"


class HelpTextTest(unittest.TestCase):
	def test_every_keynav_action_has_a_help_entry(self):
		actions = set()
		for sql in sorted(SQL_DIR.glob("*.sql")):
			text = sql.read_text(encoding="utf-8-sig")
			actions.update(re.findall(r"INSERT INTO\s+\"?InputActions\"?\s+VALUES\s*\(\s*'(KeyNav\w+)'", text, re.I))
		self.assertTrue(actions, "no KeyNav* input actions found in Database/*.sql")
		described = set(re.findall(r"action\s*=\s*\"(\w+)\"", HELP.read_text(encoding="utf-8-sig")))
		missing = sorted(actions - described)
		self.assertFalse(
			missing,
			"Input action(s) %s have no help entry. Add { action = \"%s\", default = \"<key>\", text = \"...\" } to a section in %s "
			"(the Control+H help list; see CLAUDE.md, Workflow rules)." % (", ".join(missing), missing[0] if missing else "", HELP.relative_to(ROOT)),
		)


if __name__ == "__main__":
	unittest.main()
