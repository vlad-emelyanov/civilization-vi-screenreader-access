"""Offline tests for util/overridecheck.py with a synthetic repo and a synthetic game install."""
import os
import shutil
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "util"))
import overridecheck as oc  # noqa: E402


def put(root, rel, text=""):
    p = os.path.join(root, *rel.split("/"))
    os.makedirs(os.path.dirname(p), exist_ok=True)
    with open(p, "w", encoding="utf-8") as fh:
        fh.write(text)


def proj(fe=(), ig=(), replaces=(), content=(), gameplay=()):
    def imp(files):
        return "<ImportFiles id=\"x\">%s</ImportFiles>" % "".join(
            '<File priority="10001">%s</File>' % f for f in files)
    rep = "".join("<ReplaceUIScript id=\"r%d\"><Properties><LuaContext>%s</LuaContext><LuaReplace>%s</LuaReplace>"
                  "</Properties></ReplaceUIScript>" % (i, c, r) for i, (c, r) in enumerate(replaces))
    gp = "<AddGameplayScripts id=\"g\">%s</AddGameplayScripts>" % "".join(
        "<File>%s</File>" % f for f in gameplay) if gameplay else ""
    cont = "".join('<Content Include="%s"><SubType>Content</SubType></Content>' % c.replace("/", "\\")
                   for c in content)
    return ("<Project><PropertyGroup><FrontEndActionData><![CDATA[<FrontEndActions>%s</FrontEndActions>]]>"
            "</FrontEndActionData><InGameActionData><![CDATA[<InGameActions>%s%s%s</InGameActions>]]>"
            "</InGameActionData></PropertyGroup><ItemGroup>%s</ItemGroup></Project>"
            % (imp(fe) if fe else "", imp(ig) if ig else "", rep, gp, cont))


MODINFO = """<Mod><ActionCriteria/><InGameActions>
<!-- <ImportFiles id="old"><File>UI/Replacements/Commented.lua</File></ImportFiles> -->
%s</InGameActions></Mod>"""


class Base(unittest.TestCase):
    def setUp(self):
        self.t = tempfile.mkdtemp()
        self.repo = os.path.join(self.t, "repo")
        self.game = os.path.join(self.t, "game")
        os.makedirs(self.game)

    def tearDown(self):
        shutil.rmtree(self.t, ignore_errors=True)

    def mod(self, rel, text="print('x')\n"):
        put(self.repo, "ScreenReaderAccess/" + rel, text)

    def project(self, **kw):
        files = list(kw.get("fe", [])) + list(kw.get("ig", [])) + [r for _, r in kw.get("replaces", [])]
        kw["content"] = kw.get("content", sorted(set(files + list(kw.get("gameplay", [])))))
        put(self.repo, "ScreenReaderAccess/ScreenReaderAccess.civ6proj", proj(**kw))

    def basefile(self, rel, text=""):
        put(self.game, "Base/Assets/UI/" + rel, text)

    def dlc(self, name, imports=(), replaces=(), files=None):
        imp = "<ImportFiles id=\"i\">%s</ImportFiles>" % "".join("<File>%s</File>" % f for f in imports)
        rep = "".join("<ReplaceUIScript id=\"r\"><Properties><LuaContext>%s</LuaContext><LuaReplace>%s"
                      "</LuaReplace></Properties></ReplaceUIScript>" % (c, r) for c, r in replaces)
        put(self.game, "DLC/%s/%s.modinfo" % (name, name), MODINFO % (imp + rep))
        for rel, text in (files or {}).items():
            put(self.game, "DLC/%s/%s" % (name, rel), text)

    def run_check(self):
        return oc.check(self.repo, self.game)

    def errors(self):
        return [f.msg for f in self.run_check() if f.level == "error"]


class ParseTests(unittest.TestCase):
    def test_actions(self):
        a = oc.parse_actions(MODINFO % '<ImportFiles id="a"><File>A/b.lua</File><File>C\\d.lua</File></ImportFiles>'
                             '<ReplaceUIScript id="r"><Properties><LuaContext>X</LuaContext><LuaReplace>UI/R/X_e.lua'
                             '</LuaReplace></Properties></ReplaceUIScript>')
        self.assertEqual(a["imports"], ["A/b.lua", "C/d.lua"])
        self.assertEqual(a["replaces"], [("X", "UI/R/X_e.lua")])

    def test_include_regex(self):
        plain, wild = oc.includes('include("A"); include( "B.lua" ); include("C_", true) -- include("D")\n')
        self.assertEqual((plain, wild), (["A", "B"], ["C_"]))


class RuleTests(Base):
    def test_clean(self):
        self.mod("Assets/UI/Panels/UnitPanel.lua", 'include("ScreenReader");')
        self.mod("Assets/UI/Accessibility/ScreenReader.lua")
        self.project(ig=["Assets/UI/Panels/UnitPanel.lua", "Assets/UI/Accessibility/ScreenReader.lua"])
        self.basefile("Panels/UnitPanel.lua")
        self.assertEqual(self.run_check(), [])

    def test_game_missing_is_a_warning(self):
        self.mod("Assets/UI/Accessibility/A.lua")
        self.project(ig=["Assets/UI/Accessibility/A.lua"])
        res = oc.check(self.repo, os.path.join(self.t, "nope"))
        self.assertEqual([f.level for f in res], ["warn"])

    def test_importfiles_loses_to_same_name_expansion_import(self):
        # the deal view case
        self.mod("Assets/UI/DiplomacyDealView.lua")
        self.project(ig=["Assets/UI/DiplomacyDealView.lua"])
        self.basefile("DiplomacyDealView.lua")
        self.dlc("Expansion2", imports=["UI/Replacements/DiplomacyDealView.lua"],
                 files={"UI/Replacements/DiplomacyDealView.lua": "x"})
        errs = self.errors()
        self.assertEqual(len(errs), 1)
        self.assertIn("likely loses to DLC/Expansion2/UI/Replacements/DiplomacyDealView.lua", errs[0])

    def test_deal_view_fix_passes(self):
        self.mod("UI/Replacements/SRA_DealView.lua", 'include("DiplomacyDealView_", true)')
        self.project(ig=["UI/Replacements/SRA_DealView.lua"],
                     replaces=[("DiplomacyDealView", "UI/Replacements/SRA_DealView.lua")])
        self.basefile("DiplomacyDealView.lua")
        self.dlc("Expansion2", imports=["UI/Replacements/DiplomacyDealView.lua"],
                 files={"UI/Replacements/DiplomacyDealView.lua": 'include("DiplomacyDealView_", true)'})
        self.assertEqual(self.errors(), [])

    def test_wildcard_name_trap(self):
        self.mod("UI/Replacements/DiplomacyDealView_SRA.lua", 'include("DiplomacyDealView_", true)')
        self.project(ig=["UI/Replacements/DiplomacyDealView_SRA.lua"],
                     replaces=[("DiplomacyDealView", "UI/Replacements/DiplomacyDealView_SRA.lua")])
        self.basefile("DiplomacyDealView.lua")
        self.dlc("Expansion2", files={"UI/Replacements/DiplomacyDealView.lua": 'include("DiplomacyDealView_", true)'})
        errs = self.errors()
        self.assertTrue(any("wildcard include prefix 'diplomacydealview_'" in e for e in errs), errs)

    def test_wildcard_from_game_file_only(self):
        self.mod("Assets/UI/Panels/NotificationPanel_SRA.lua")
        self.project(ig=["Assets/UI/Panels/NotificationPanel_SRA.lua"])
        self.basefile("Panels/NotificationPanel.lua", 'include("NotificationPanel_", true)')
        self.assertTrue(any("wildcard" in e for e in self.errors()))

    def test_expansion_chain_reaching_base_is_fine(self):
        # UnitPanel_Expansion2 -> UnitPanel_Expansion1 -> UnitPanel: our copy is what gets included
        self.mod("Assets/UI/Panels/UnitPanel.lua")
        self.project(ig=["Assets/UI/Panels/UnitPanel.lua"])
        self.basefile("Panels/UnitPanel.lua")
        self.dlc("Expansion1", replaces=[("UnitPanel", "UI/Replacements/UnitPanel_Expansion1.lua")],
                 files={"UI/Replacements/UnitPanel_Expansion1.lua": 'include("UnitPanel");'})
        self.dlc("Expansion2", replaces=[("UnitPanel", "UI/Replacements/UnitPanel_Expansion2.lua")],
                 files={"UI/Replacements/UnitPanel_Expansion2.lua": 'include("UnitPanel_Expansion1");'})
        self.assertEqual(self.errors(), [])

    def test_expansion_replacement_without_include_is_dead(self):
        self.mod("Assets/UI/Panels/UnitPanel.lua")
        self.project(ig=["Assets/UI/Panels/UnitPanel.lua"])
        self.basefile("Panels/UnitPanel.lua")
        self.dlc("Expansion2", replaces=[("UnitPanel", "UI/Replacements/UnitPanel_Expansion2.lua")],
                 files={"UI/Replacements/UnitPanel_Expansion2.lua": 'print("full rewrite")'})
        errs = self.errors()
        self.assertEqual(len(errs), 1)
        self.assertIn("dead code", errs[0])

    def test_disabled_dlc_ignored(self):
        self.mod("Assets/UI/Panels/UnitPanel.lua")
        self.project(ig=["Assets/UI/Panels/UnitPanel.lua"])
        self.basefile("Panels/UnitPanel.lua")
        self.dlc("PiratesScenario", replaces=[("UnitPanel", "UI/Replacements/UnitPanel_P.lua")],
                 files={"UI/Replacements/UnitPanel_P.lua": 'print("x")'})
        self.assertEqual(self.errors(), [])

    def test_dlc_addition_with_importfiles(self):
        self.mod("Assets/UI/Panels/GovernorPanel.lua")
        self.project(ig=["Assets/UI/Panels/GovernorPanel.lua"])
        self.dlc("Expansion2", files={"UI/Additions/GovernorPanel.lua": "x"})
        errs = self.errors()
        self.assertTrue(any("ReplaceUIScript" in e and "UI/Additions" in e for e in errs), errs)

    def test_dlc_addition_with_replaceuiscript_is_fine(self):
        self.mod("UI/Replacements/GovernorPanel_SRA.lua")
        self.project(ig=["UI/Replacements/GovernorPanel_SRA.lua"],
                     replaces=[("GovernorPanel", "UI/Replacements/GovernorPanel_SRA.lua")])
        self.dlc("Expansion2", files={"UI/Additions/GovernorPanel.lua": "x"})
        self.assertEqual(self.errors(), [])

    def test_missing_unregistered_content_duplicate(self):
        self.mod("Assets/UI/Accessibility/A.lua")
        self.mod("Assets/UI/Accessibility/Orphan.lua")
        self.project(ig=["Assets/UI/Accessibility/A.lua", "Assets/UI/Accessibility/A.lua",
                         "Assets/UI/Accessibility/Gone.lua"],
                     content=["Assets/UI/Accessibility/A.lua"])
        errs = "\n".join(self.errors())
        self.assertIn("listed twice", errs)
        self.assertIn("does not exist: Assets/UI/Accessibility/Gone.lua", errs)
        self.assertIn("no <Content Include> for Assets/UI/Accessibility/Gone.lua", errs)
        self.assertIn("Orphan.lua is not registered", errs)

    def test_same_file_in_importfiles_and_gameplay_is_fine(self):
        self.mod("Assets/UI/Accessibility/Utils.lua")
        self.project(ig=["Assets/UI/Accessibility/Utils.lua"], gameplay=["Assets/UI/Accessibility/Utils.lua"])
        self.assertEqual(self.errors(), [])

    def test_helper_missing_from_frontend(self):
        self.mod("Assets/UI/Frontend/MainMenu.lua", 'include("KeyNavList")')
        self.mod("Assets/UI/Accessibility/KeyNavList.lua", 'include("Deep")')
        self.mod("Assets/UI/Accessibility/Deep.lua")
        self.project(fe=["Assets/UI/Frontend/MainMenu.lua", "Assets/UI/Accessibility/KeyNavList.lua"],
                     ig=["Assets/UI/Accessibility/KeyNavList.lua", "Assets/UI/Accessibility/Deep.lua"])
        errs = self.errors()
        self.assertEqual(len(errs), 1)
        self.assertIn("FrontEnd", errs[0])
        self.assertIn("Deep.lua", errs[0])

    def test_xml_registers_its_lua(self):
        self.mod("UI/Additions/Hub.lua")
        self.mod("UI/Additions/Hub.xml")
        put(self.repo, "ScreenReaderAccess/ScreenReaderAccess.civ6proj",
            proj(content=["UI/Additions/Hub.lua", "UI/Additions/Hub.xml"]).replace(
                "</InGameActions>", '<AddUserInterfaces id="u"><Properties><Context>InGame</Context></Properties>'
                                    '<File>UI/Additions/Hub.xml</File></AddUserInterfaces></InGameActions>'))
        self.assertEqual(self.errors(), [])


@unittest.skipUnless(os.path.isdir(oc.game_dir_from_env()), "game install not present")
class RealRepoTest(unittest.TestCase):
    def test_current_registrations_pass(self):
        errs = [f.msg for f in oc.check(oc.ROOT, oc.game_dir_from_env()) if f.level == "error"]
        self.assertEqual(errs, [])


if __name__ == "__main__":
    unittest.main()
