"""The controller key table must agree between the Lua side (Accessibility/Gamepad.lua) and the console app
(ScreenreaderAccess.Console/Gamepad/GamepadMap.cs): same 26 button names, same key, same Control flag.

Lua lines:  	X = { key = "VK_F13", control = false },
C# lines:   ["RSUp"] = new PadKey(Keys.F13, control: true),
"""
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
LUA = ROOT / "ScreenReaderAccess" / "Assets" / "UI" / "Accessibility" / "Gamepad.lua"
CS = ROOT / "ScreenreaderAccess.Console" / "Gamepad" / "GamepadMap.cs"

NAMES = {
	"A", "B", "X", "Y", "LB", "RB", "LT", "RT", "View", "Menu", "LSClick", "RSClick",
	"RSUp", "RSDown", "RSLeft", "RSRight", "LUp", "LDown", "LLeft", "LRight",
	"DUp", "DDown", "DLeft", "DRight", "ModeOn", "ModeOff",
}
# Lua engine key name -> C# System.Windows.Forms.Keys name
LUA_TO_CS = {
	"VK_RETURN": "Enter", "VK_ESCAPE": "Escape", "VK_SPACE": "Space", "VK_UP": "Up", "VK_DOWN": "Down",
	"VK_LEFT": "Left", "VK_RIGHT": "Right", "VK_HOME": "Home", "VK_END": "End", "VK_TAB": "Tab",
}
for _n in range(1, 25):
	LUA_TO_CS["VK_F%d" % _n] = "F%d" % _n


def parse_lua():
	text = LUA.read_text(encoding="utf-8-sig")
	entries = re.findall(r'^\t(\w+) = \{ key = "(VK_\w+)", control = (true|false) \},\s*$', text, re.M)
	return {name: (LUA_TO_CS[key], control == "true") for name, key, control in entries}


def parse_cs():
	text = CS.read_text(encoding="utf-8-sig")
	entries = re.findall(r'\["(\w+)"\]\s*=\s*new PadKey\(\s*Keys\.(\w+)\s*(?:,\s*control:\s*(true|false))?\s*\)', text)
	return {name: (key, control == "true") for name, key, control in entries}


class GamepadMapTest(unittest.TestCase):
	def test_lua_table_has_all_buttons(self):
		lua = parse_lua()
		self.assertEqual(set(lua), NAMES)

	def test_lua_and_console_maps_agree(self):
		if not CS.exists():
			self.skipTest("%s does not exist in this checkout (the console branch adds it; the test runs after the merge)" % CS.relative_to(ROOT))
		lua, cs = parse_lua(), parse_cs()
		self.assertEqual(set(cs), NAMES, "button names differ between GamepadMap.cs and Gamepad.lua")
		for name in sorted(NAMES):
			self.assertEqual(cs[name], lua[name], "button %s: GamepadMap.cs %s, Gamepad.lua %s" % (name, cs[name], lua[name]))


if __name__ == "__main__":
	unittest.main()
