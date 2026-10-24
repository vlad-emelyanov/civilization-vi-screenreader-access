import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', '..', 'util'))
import includers  # noqa: E402

BS = chr(92)


def write(root, rel, text):
    p = os.path.join(root, *rel.split('/'))
    os.makedirs(os.path.dirname(p), exist_ok=True)
    with open(p, 'w', encoding='utf-8') as f:
        f.write(text)


class IncludersTest(unittest.TestCase):
    def test_lookup(self):
        with tempfile.TemporaryDirectory() as root:
            write(root, 'UI/Additions/InGameAccess.lua', 'include( "HubTargets" );\ninclude("HubHelp")\n')
            write(root, 'Assets/UI/Accessibility/HubHelp.lua', 'include("HelpText")\n')
            write(root, 'Assets/UI/Accessibility/HubTargets.lua', '-- include("Nope")\n')
            write(root, 'Assets/UI/Accessibility/HelpText.lua', '')
            write(root, 'UI/Other.lua', 'include("PopupPriorityLoader_", true)\ninclude("Unrelated")\n')
            a = includers.find_includers(root, ['Assets' + BS + 'UI' + BS + 'Accessibility' + BS + 'HubTargets.lua'])
            self.assertEqual([r for r, _ in a], ['UI' + BS + 'Additions' + BS + 'InGameAccess.lua'])
            b = [r for r, _ in includers.find_includers(root, ['Assets' + BS + 'UI' + BS + 'Accessibility' + BS + 'HelpText.lua'])]
            self.assertEqual(b, ['Assets' + BS + 'UI' + BS + 'Accessibility' + BS + 'HubHelp.lua', 'UI' + BS + 'Additions' + BS + 'InGameAccess.lua'])

    def test_comment_and_wildcard_ignored(self):
        self.assertEqual(includers.included_names('-- include("A")\ninclude("B", true)\ninclude( "C" ) -- x\n'), {'c'})


if __name__ == '__main__':
    unittest.main()
