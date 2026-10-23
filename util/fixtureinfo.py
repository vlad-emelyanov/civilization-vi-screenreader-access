#!/usr/bin/env python
"""Fixture facts: ask the loaded game what a fixture contains and append it to test/fixtures/<name>.txt as a `facts:` block.

  python util/fixtureinfo.py <name> [--fixtures DIR] [--state-dir DIR] [--force] [--print]

`civctl fixture-info <name>` runs this. It loads nothing: the game must have <name> loaded right now (`civctl load <name>` writes
%TEMP%\\civctl\\loaded.txt, and the turn must still equal the sidecar's `turn:`; --force skips both checks). The queries are one
Lua chunk, util/fixture_facts.lua, run in the InGame tuner state (every section is wrapped in pcall; "(n/a: ...)" marks an API
that does not exist). A previous `facts:` block of the sidecar is replaced; the other sidecar lines are untouched.
Why: offline agents wrote scenarios that assumed a free trade slot, a Holy Site or spies the fixture did not have.
"""
from __future__ import annotations

import argparse
import asyncio
import datetime
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)  # python -I does not add the script directory
FACTS_LUA = os.path.join(HERE, "fixture_facts.lua")


def read_sidecar(path):
    with open(path, encoding="utf-8") as f:
        return f.read()


def sidecar_turn(text):
    m = re.search(r"^turn:\s*(\d+)", text, re.M)
    return int(m.group(1)) if m else None


def merge_facts(text, facts_lines, header):
    """Sidecar text -> same text with its `facts:` block (the line and the indented lines after it) replaced by the new one."""
    lines = text.splitlines()
    out, i = [], 0
    while i < len(lines):
        if lines[i].startswith("facts:"):
            i += 1
            while i < len(lines) and (lines[i].startswith((" ", "\t")) or not lines[i].strip()):
                i += 1
            continue
        out.append(lines[i])
        i += 1
    while out and not out[-1].strip():
        out.pop()
    out.append("facts: " + header)
    out.extend("  " + l.rstrip() for l in facts_lines if l.strip())
    return "\n".join(out) + "\n"


def check_loaded(name, turn_now, side_turn, loaded_name):
    """None when the loaded game is the fixture, else the reason it is not."""
    if loaded_name != name:
        return "the loaded game was not loaded as fixture '%s' (civctl load wrote: %s); run `civctl load %s` first, or pass --force" % (
            name, loaded_name or "nothing", name)
    if side_turn is not None and turn_now != side_turn:
        return "the game is at turn %s but the fixture's sidecar says turn %s: not the fixture's state any more (reload it, or --force)" % (turn_now, side_turn)
    return None


def run_lua(code, timeout=20.0):
    import civtuner
    out = []
    rc = asyncio.run(civtuner.run("InGame", code, timeout, out))
    return rc, out


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("name")
    ap.add_argument("--fixtures", default=os.path.join(ROOT, "test", "fixtures"))
    ap.add_argument("--state-dir", default=os.path.join(os.environ.get("TEMP", "."), "civctl"))
    ap.add_argument("--force", action="store_true")
    ap.add_argument("--print", action="store_true", help="print the facts, do not touch the sidecar")
    a = ap.parse_args(argv)
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except AttributeError:
        pass
    side = os.path.join(a.fixtures, a.name + ".txt")
    if not os.path.isfile(side):
        print("No sidecar %s (no such fixture?)" % side)
        return 1
    text = read_sidecar(side)
    import civtuner
    where = []
    rc = asyncio.run(civtuner.run("InGame", civtuner.WHERE_LUA, 8.0, where, quiet_missing_state=True))
    parts = "".join(where).split()
    if rc != 0 or len(parts) < 2 or parts[0] != "INGAME":
        print("No game in progress (tuner answer: %s)." % ("".join(where) or "none, rc %d" % rc))
        return 1
    if not a.force:
        try:
            with open(os.path.join(a.state_dir, "loaded.txt"), encoding="utf-8") as f:
                loaded = f.read().strip()
        except OSError:
            loaded = ""
        why = check_loaded(a.name, int(parts[1]), sidecar_turn(text), loaded)
        if why:
            print("REFUSED: " + why)
            return 1
    with open(FACTS_LUA, encoding="utf-8") as f:
        code = f.read()
    rc, lines = run_lua(code)
    flat = [l for chunk in lines for l in chunk.splitlines()]
    if rc != 0 or not flat:
        print("fixture_facts.lua failed (rc %d): %s" % (rc, " | ".join(flat) or "no output"))
        return 1
    if a.print:
        print("\n".join(flat))
        return 0
    header = "(civctl fixture-info %s)" % datetime.date.today().isoformat()
    with open(side, "w", encoding="utf-8", newline="\n") as f:
        f.write(merge_facts(text, flat, header))
    na = sum(1 for l in flat if "(n/a:" in l)
    print("facts written to %s (%d lines%s)" % (side, len(flat), ", %d n/a: fix those calls in util/fixture_facts.lua" % na if na else ""))
    print("\n".join(flat))
    return 0


if __name__ == "__main__":
    sys.exit(main())
