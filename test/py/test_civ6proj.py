"""Offline tests for util/civ6proj.py (add / list / merge-union on a small sample project, BOM + CRLF)."""
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "util"))
import civ6proj as cp  # noqa: E402

F = '<File priority="10001">%s</File>'
UNIT = ("Assets/UI/Panels/UnitPanel.lua",)
UNIT_C = ("Assets\\UI\\Frontend\\MainMenu.lua", "Assets\\UI\\Panels\\UnitPanel.lua")
GONE = ("Assets/UI/Panels/UnitPanel.lua", "Assets/UI/Panels/Gone.lua")
GONE_C = ("Assets\\UI\\Panels\\UnitPanel.lua", "Assets\\UI\\Panels\\Gone.lua")


def sample(fe=("Assets/UI/Frontend/MainMenu.lua",), ig=UNIT, replace=("GovernorPanel",), content=UNIT_C):
    fe_xml = ('<FrontEndActions><ImportFiles id="SRAccess_FE_UpdateFiles">%s</ImportFiles>'
              '<UpdateDatabase id="SRAccessModifyConfigurationDB"><File>Database/a.sql</File></UpdateDatabase></FrontEndActions>') % "".join(F % f for f in fe)
    rep = "".join('<ReplaceUIScript id="SRAccess_IG_%s"><Properties><LuaContext>%s</LuaContext><LuaReplace>UI/Replacements/%s_SRA.lua</LuaReplace></Properties></ReplaceUIScript>' % (r, r, r) for r in replace)
    ig_xml = ('<InGameActions><ImportFiles id="SRAccess_IG_UpdateFiles">%s</ImportFiles>%s'
              '<AddGameplayScripts id="SRAccess_IG_GameplayScripts"><File>Gameplay/x.lua</File></AddGameplayScripts></InGameActions>') % ("".join(F % f for f in ig), rep)
    cont = "".join('    <Content Include="%s">\n      <SubType>Content</SubType>\n    </Content>\n' % c for c in content)
    t = ('<?xml version="1.0" encoding="utf-8"?>\n<Project>\n  <PropertyGroup>\n    <Name>X</Name>\n'
         '    <FrontEndActionData><![CDATA[%s]]></FrontEndActionData>\n    <InGameActionData><![CDATA[%s]]></InGameActionData>\n'
         '  </PropertyGroup>\n  <ItemGroup>\n%s  </ItemGroup>\n  <Import Project="x" />\n</Project>\n') % (fe_xml, ig_xml, cont)
    return t.replace("\n", "\r\n")


class Base(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.addCleanup(self.dir.cleanup)

    def path(self, name, text=None):
        p = os.path.join(self.dir.name, name)
        if text is not None:
            with open(p, "wb") as f:
                f.write(cp.BOM + text.encode("utf-8"))
        return p

    def read(self, p):
        return cp.read_text(p)

    def files(self, text, ctx):
        return cp.file_entries(cp.split_elements(cp.get_block(text, ctx)[1])[1][0][2])


class AddTests(Base):
    def run_add(self, proj, *args):
        return cp.main(["add", *args, "--proj", proj])

    def test_add_import_both_preserves_bom_and_crlf(self):
        p = self.path("a.civ6proj", sample())
        self.assertEqual(self.run_add(p, "Assets/UI/Popups/Foo.lua", "--context", "Both"), 0)
        text, bom = self.read(p)
        self.assertTrue(bom)
        self.assertEqual(text.count("\r\n"), text.count("\n"))
        for ctx in ("FrontEnd", "InGame"):
            self.assertEqual(self.files(text, ctx)[-1], "Assets/UI/Popups/Foo.lua")
        self.assertEqual(text.count("Assets\\UI\\Popups\\Foo.lua"), 1)

    def test_other_content_untouched(self):
        orig = sample()
        p = self.path("a.civ6proj", orig)
        self.run_add(p, "Assets/UI/Popups/Foo.lua", "--context", "InGame")
        new, _ = self.read(p)
        new = new.replace(F % "Assets/UI/Popups/Foo.lua", "")
        new = new.replace('\r\n    <Content Include="Assets\\UI\\Popups\\Foo.lua">\r\n      <SubType>Content</SubType>\r\n    </Content>', "")
        self.assertEqual(new, orig)

    def test_idempotent(self):
        p = self.path("a.civ6proj", sample())
        self.run_add(p, "Assets/UI/Popups/Foo.lua", "--context", "InGame")
        first = open(p, "rb").read()
        self.run_add(p, "ScreenReaderAccess\\Assets\\UI\\Popups\\Foo.lua", "--context", "InGame")
        self.assertEqual(open(p, "rb").read(), first)

    def test_replace_ui(self):
        p = self.path("a.civ6proj", sample())
        self.run_add(p, "UI/Replacements/Bar_SRA.lua", "--context", "InGame", "--replace-ui", "BarPopup")
        text, _ = self.read(p)
        self.assertIn('<ReplaceUIScript id="SRAccess_IG_BarPopup"><Properties><LuaContext>BarPopup</LuaContext>'
                      '<LuaReplace>UI/Replacements/Bar_SRA.lua</LuaReplace></Properties></ReplaceUIScript>', text)
        self.assertNotIn(F % "UI/Replacements/Bar_SRA.lua", text)
        self.assertIn('Include="UI\\Replacements\\Bar_SRA.lua"', text)

    def test_replace_ui_conflict(self):
        p = self.path("a.civ6proj", sample())
        self.assertEqual(self.run_add(p, "UI/Replacements/Other.lua", "--context", "InGame", "--replace-ui", "GovernorPanel"), 1)

    def test_list_and_problems(self):
        p = self.path("a.civ6proj", sample(content=("Assets\\UI\\Frontend\\MainMenu.lua",)))
        text, _ = self.read(p)
        self.assertEqual(len(cp.problems(text)), 4)  # UnitPanel, the replacement, the gameplay script, the sql
        self.assertEqual(cp.main(["list", "--proj", p]), 0)


class MergeTests(Base):
    def test_union_of_independent_adds(self):
        ours = self.path("ours.civ6proj", sample())
        theirs = self.path("theirs.civ6proj", sample())
        cp.main(["add", "Assets/UI/Popups/Ours.lua", "--context", "InGame", "--proj", ours])
        cp.main(["add", "Assets/UI/Popups/Theirs.lua", "--context", "Both", "--proj", theirs])
        cp.main(["add", "UI/Replacements/T_SRA.lua", "--context", "InGame", "--replace-ui", "TPopup", "--proj", theirs])
        out = self.path("out.civ6proj")
        cp.main(["merge-union", ours, theirs, "--out", out])
        text, bom = self.read(out)
        self.assertTrue(bom)
        self.assertEqual(text.count("\r\n"), text.count("\n"))
        for needle in ("Assets/UI/Popups/Ours.lua", "Assets/UI/Popups/Theirs.lua", "SRAccess_IG_TPopup", "Assets\\UI\\Popups\\Ours.lua",
                       "Assets\\UI\\Popups\\Theirs.lua", "UI\\Replacements\\T_SRA.lua"):
            self.assertEqual(text.count(needle), 2 if needle == "Assets/UI/Popups/Theirs.lua" else 1, needle)  # Theirs: both contexts
        self.assertIn("Assets/UI/Popups/Theirs.lua", self.files(text, "FrontEnd"))
        self.assertNotIn("Assets/UI/Popups/Ours.lua", self.files(text, "FrontEnd"))

    def test_same_add_on_both_sides_not_duplicated(self):
        ours = self.path("o.civ6proj", sample())
        theirs = self.path("t.civ6proj", sample())
        for p in (ours, theirs):
            cp.main(["add", "Assets/UI/Popups/Same.lua", "--context", "InGame", "--proj", p])
        cp.main(["merge-union", ours, theirs])
        text, _ = self.read(ours)
        self.assertEqual(text.count("Popups/Same.lua"), 1)
        self.assertEqual(text.count("Popups\\Same.lua"), 1)

    def test_merge_driver_with_base_honours_theirs_deletion(self):
        base = self.path("b.civ6proj", sample(ig=GONE, content=GONE_C))
        ours = self.path("o.civ6proj", sample(ig=GONE, content=GONE_C))
        theirs = self.path("t.civ6proj", sample())
        cp.main(["add", "Assets/UI/Popups/Mine.lua", "--context", "InGame", "--proj", ours])
        self.assertEqual(cp.main(["merge-driver", base, ours, theirs]), 0)
        text, _ = self.read(ours)
        self.assertNotIn("Gone.lua", text)
        self.assertIn("Mine.lua", text)

    def test_ours_deletion_is_kept_with_base(self):
        base = self.path("b.civ6proj", sample(ig=GONE, content=GONE_C))
        ours = self.path("o.civ6proj", sample())
        theirs = self.path("t.civ6proj", sample(ig=GONE, content=GONE_C))
        cp.main(["merge-union", ours, theirs, "--base", base])
        text, _ = self.read(ours)
        self.assertNotIn("Gone.lua", text)

    def test_real_project_parses(self):
        if not os.path.exists(cp.DEFAULT_PROJ):
            self.skipTest("no project")
        text, bom = cp.read_text(cp.DEFAULT_PROJ)
        self.assertTrue(bom)
        self.assertIn("InGame", cp.registered(text))
        self.assertEqual(cp.merge_text(text, text), text)  # merging a file with itself is a no-op


if __name__ == "__main__":
    unittest.main()
