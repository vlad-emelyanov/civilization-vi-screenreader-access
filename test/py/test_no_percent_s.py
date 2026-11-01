"""Lua patterns in the mod's spoken-text helpers must not use %s / %S: in the game's locale %s matches byte 0xA0 and splits
UTF-8 letters such as a-grave (Pieta). Use an explicit class of space, tab, CR, LF, VT and FF."""
import glob
import os
import re
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


class NoPercentS(unittest.TestCase):
    def test_accessibility_files(self):
        bad = []
        for path in glob.glob(os.path.join(ROOT, "ScreenReaderAccess", "Assets", "UI", "Accessibility", "*.lua")):
            with open(path, encoding="utf-8-sig") as f:
                for n, line in enumerate(f, 1):
                    if re.search(r"%[sS]", line) and "format(" not in line:
                        bad.append("%s:%d" % (os.path.basename(path), n))
        self.assertEqual(bad, [])


if __name__ == "__main__":
    unittest.main()
