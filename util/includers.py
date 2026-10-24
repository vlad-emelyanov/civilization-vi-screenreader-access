"""Which mod Lua files `include` a given mod Lua file (used by civctl deploy/reload).

The game only re-initialises a UI context when ITS OWN script file is rewritten; a changed helper that the context
`include`s (Accessibility/Hub*.lua, HelpText.lua, ...) does not trigger it. So deploy also rewrites the includers.

    python util/includers.py <mod root> <rel path>...   -> one line per includer: "<includer rel>\t<helper basename>"
Transitive: an includer that is itself a helper pulls in its own includers.
"""
import os
import re
import sys

BS = chr(92)
INCLUDE_RE = re.compile(r'''\binclude\s*\(\s*["']([^"']+)["']\s*(?:,|\))''')


def strip_comment(line):
    i = line.find('--')
    return line if i < 0 else line[:i]


def included_names(text):
    """Lower-case names passed to include("...") outside of `--` comments (wildcard form include("X_", true) skipped)."""
    names = set()
    for line in text.splitlines():
        for m in INCLUDE_RE.finditer(strip_comment(line)):
            rest = line[m.end() - 1:m.end() + 8]
            if rest.startswith(',') and 'true' in rest:
                continue
            names.add(m.group(1).lower())
    return names


def scan(root):
    """{rel path (backslashes) -> set of included names} for every .lua under root."""
    out = {}
    for d, _, files in os.walk(root):
        if os.sep + '.vs' in d:
            continue
        for f in files:
            if f.lower().endswith('.lua'):
                p = os.path.join(d, f)
                try:
                    with open(p, encoding='utf-8-sig', errors='replace') as fh:
                        out[os.path.relpath(p, root).replace('/', BS)] = included_names(fh.read())
                except OSError:
                    pass
    return out


def find_includers(root, rels):
    """[(includer rel, helper basename)] for the changed files `rels`, transitively, without the inputs themselves."""
    graph = scan(root)
    result = []
    seen = {r.lower() for r in rels}
    todo = [r for r in rels]
    while todo:
        helper = todo.pop()
        name = os.path.splitext(os.path.basename(helper))[0].lower()
        for rel, names in sorted(graph.items()):
            if name in names and rel.lower() not in seen:
                seen.add(rel.lower())
                result.append((rel, os.path.splitext(os.path.basename(helper))[0]))
                todo.append(rel)
    return result


if __name__ == '__main__':
    for rel, helper in find_includers(sys.argv[1], [a.replace('/', BS) for a in sys.argv[2:]]):
        print('%s\t%s' % (rel, helper))
