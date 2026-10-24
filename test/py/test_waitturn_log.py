"""wait-turn must print every SR line logged during the wait, also the ones logged while the poll ran."""
import os
import re
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))


class WaitTurnLog(unittest.TestCase):
    def body(self):
        with open(os.path.join(HERE, "..", "..", "util", "civctl.ps1"), encoding="utf-8-sig") as f:
            text = f.read()
        m = re.search(r"function Invoke-WaitTurn.*?\n}\r?\n", text, re.S)
        self.assertIsNotNone(m)
        return m.group(0)

    def test_log_read_after_poll_before_reporting(self):
        b = self.body()
        poll = b.index("'poll'")
        after = b.index("Read-NewLogLines", poll)
        self.assertLess(after, b.index("if ($code -eq 0)"))
        self.assertLess(after, b.index("popup>"))

    def test_log_read_before_poll_too(self):
        b = self.body()
        self.assertLess(b.index("Read-NewLogLines"), b.index("'poll'"))


if __name__ == "__main__":
    unittest.main()
