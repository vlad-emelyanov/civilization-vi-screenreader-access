import os, sys, unittest

sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))), "util"))
import lint  # noqa: E402


def many_locals(n):
    return "\n".join("local v%d = %d" % (i, i) for i in range(n)) + "\n"


class CompileCheck(unittest.TestCase):
    def test_205_locals_fail(self):
        src = many_locals(205)
        err = lint.compile_check("gen.lua", src)
        self.assertIsNotNone(err)
        self.assertIn("gen.lua:", err)
        self.assertIn("more than 200 local variables", err)
        self.assertEqual(lint.top_level_locals(src), 205)

    def test_150_locals_ok(self):
        self.assertIsNone(lint.compile_check("gen.lua", many_locals(150)))

    def test_counts_multi_and_functions(self):
        self.assertEqual(lint.top_level_locals("local a, b = 1, 2\nlocal function f() local z = 1 end\n"), 3)

    def test_syntax_error(self):
        self.assertIn("x.lua:1", lint.compile_check("x.lua", "local = \n"))


if __name__ == "__main__":
    unittest.main()
