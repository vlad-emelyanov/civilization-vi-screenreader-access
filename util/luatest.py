#!/usr/bin/env python
"""Offline Lua unit tests: runs test/lua/test_*.lua under Lua 5.1 (lupa.lua51; `pip install lupa` on first use).

  python util/luatest.py [name-substring ...]     e.g. python util/luatest.py settle

Each test file gets a fresh Lua state with test/lua/lib.lua loaded (test(), eq(), include(), print capture) and
loads the stubs it needs with stub("engine") / stub("world") (test/lua/stubs/). The mod's Lua is read through
lint.strip_annotations, so Civ's `local x:number` syntax works.
Exit codes: 0 = all passed, 1 = a test failed or a file did not load, 2 = tool problem (lupa missing).
"""
import glob, os, subprocess, sys, time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "util"))
from lint import strip_annotations  # noqa: E402

LUA_DIR = os.path.join(ROOT, "test", "lua")


def get_runtime_class():
    try:
        from lupa.lua51 import LuaRuntime
    except ImportError:
        print("installing lupa ...", file=sys.stderr)
        r = subprocess.run([sys.executable, "-m", "pip", "install", "--quiet", "lupa"])
        if r.returncode != 0:
            return None
        from lupa.lua51 import LuaRuntime
    return LuaRuntime


def read_source(path):
    if not os.path.isabs(path):
        path = os.path.join(ROOT, path)
    with open(path, encoding="utf-8-sig", errors="replace") as f:
        return strip_annotations(f.read().replace("\r\n", "\n"))


def run_file(LuaRuntime, path):
    lua = LuaRuntime(unpack_returned_tuples=True)
    g = lua.globals()
    g.sr_read = read_source
    g.ROOT = ROOT.replace("\\", "/")
    lua.execute(read_source(os.path.join(LUA_DIR, "lib.lua")))
    try:
        lua.execute('RunTestFile(...)', path.replace("\\", "/"))
    except Exception as e:  # load error in the test file itself
        print("  LOAD ERROR %s: %s" % (os.path.basename(path), e))
        return 0, 1
    t = g.T
    return int(t.passed), int(t.failed)


def main(argv):
    LuaRuntime = get_runtime_class()
    if LuaRuntime is None:
        print("lupa is not available", file=sys.stderr)
        return 2
    files = sorted(glob.glob(os.path.join(LUA_DIR, "test_*.lua")))
    if argv:
        files = [f for f in files if any(a in os.path.basename(f) for a in argv)]
    start = time.time()
    passed = failed = 0
    for f in files:
        print(os.path.basename(f))
        p, fl = run_file(LuaRuntime, f)
        passed += p
        failed += fl
    print("luatest: %d passed, %d failed in %d file(s), %.1fs" % (passed, failed, len(files), time.time() - start))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
