"""util/typedlocals.py: a `local x:T` later assigned a literal of another type fails to load in the game."""
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "util"))
import typedlocals  # noqa: E402


def lines(src):
    return [ln for ln, _ in typedlocals.check(src)]


class TypedLocals(unittest.TestCase):
    def test_hubenemies_case(self):
        src = "local function f()\n\tlocal alarmed:table = nil;\n\tif x then\n\t\talarmed = false;\n\tend\nend\n"
        self.assertEqual(lines(src), [4])

    def test_literal_kinds(self):
        src = ("local a:number = 1\nlocal b:string = 's'\nlocal c:boolean = true\nlocal d:table = {}\n"
               "local e:function = nil\na = 'x'\nb = 3\nc = {}\nd = 1\ne = true\n")
        self.assertEqual(lines(src), [6, 7, 8, 9, 10])

    def test_declaration_itself(self):
        self.assertEqual(lines("local a:number = false\n"), [1])
        self.assertEqual(lines("local a:number, b:string = 1, 2\n"), [1])

    def test_same_type_and_nil_ok(self):
        self.assertEqual(lines("local a:number = 1\na = 2\na = -3\na = nil\nlocal t:table = nil\nt = {1,{2}}\n"), [])

    def test_untyped_and_expressions_ignored(self):
        self.assertEqual(lines("local a = {}\na = false\nlocal n:number = 1\nn = 2 + x\nn = f()\nn = 1 .. 'a'\n"), [])

    def test_shadowing(self):
        src = "local a:table = nil\nlocal function f()\n\tlocal a = 0\n\ta = false\nend\na = 1\n"
        self.assertEqual(lines(src), [6])

    def test_scope_ends(self):
        src = "do\n\tlocal a:table = nil\nend\na = false\n"
        self.assertEqual(lines(src), [])

    def test_multiple_assignment(self):
        src = "local a:number\nlocal b:string\na, b = 'x', 'y'\n"
        self.assertEqual(lines(src), [3])

    def test_table_fields_and_calls_not_assignments(self):
        src = "local a:number = 1\nlocal t = { a = false }\nf(a)\nt.a = false\nx.a = true\n"
        self.assertEqual(lines(src), [])

    def test_params_and_loop_vars(self):
        src = "function f(p:table)\n\tp = false\nend\nfor i, v:table in pairs(x) do\n\tv = 1\nend\n"
        self.assertEqual(lines(src), [2, 5])

    def test_comments_and_strings(self):
        src = "local a:number = 1\n-- a = false\n--[[ a = false\n]]\nlocal s = 'a = false'\nlocal l = [[\na = false\n]]\n"
        self.assertEqual(lines(src), [])


if __name__ == "__main__":
    unittest.main()
