#!/usr/bin/env python
"""Static check of the mod's Lua with luacheck (downloaded to util/tools/ on first use).

  python util/lint.py [files...]     (default: every .lua under ScreenReaderAccess/)

Exit codes: 0 = ok (warnings in upstream game-file copies are only printed with -v),
            1 = errors: a syntax error anywhere, or any warning in a strict file,
            2 = tool problem (download failed, ...).
The .civ6proj registration check (util/overridecheck.py) runs at the end; its errors also give exit 1.
Strict files = mod-only code: Assets/UI/Accessibility/*.lua and UI/Additions/*.lua.
"""
import hashlib, os, re, shutil, subprocess, sys, urllib.request
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import typedlocals

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TOOLS = os.path.join(ROOT, "util", "tools")
EXE = os.path.join(TOOLS, "luacheck.exe")
VERSION = "v1.2.0"
URL = "https://github.com/lunarmodules/luacheck/releases/download/%s/luacheck.exe" % VERSION
SHA256 = "0f1c69c4d09f1ebb4d8df14c215e4553e2e639bd4cb7bf3c639b0daa6198317b"
STRICT = ("ScreenReaderAccess/Assets/UI/Accessibility/", "ScreenReaderAccess/UI/Additions/")


def _sha(path):
    with open(path, "rb") as fh:
        return hashlib.sha256(fh.read()).hexdigest()


def ensure_tool():
    if os.path.exists(EXE):
        if _sha(EXE) == SHA256:
            return
        print("luacheck.exe has the wrong sha256: downloading it again ...", file=sys.stderr)
        os.remove(EXE)
    os.makedirs(TOOLS, exist_ok=True)
    print("downloading luacheck.exe ...", file=sys.stderr)
    urllib.request.urlretrieve(URL, EXE + ".part")
    with open(EXE + ".part", "rb") as fh:
        got = hashlib.sha256(fh.read()).hexdigest()
    if got != SHA256:
        os.remove(EXE + ".part")
        raise RuntimeError("luacheck.exe sha256 mismatch (got %s, expected %s)" % (got, SHA256))
    os.replace(EXE + ".part", EXE)


ANN = re.compile(r"\s*:\s*[A-Za-z_]\w*")


def strip_annotations(src):
    """Civ's Lua accepts `local x:number`, `function f(a:table)`, `for i,v:table in` and
    `hstructure Name ... end`; luacheck does not. Rewrite them (line numbers stay the same)."""
    out = []
    in_struct = False
    in_params = False
    for line in src.split("\n"):
        if in_struct:
            if re.match(r"^\s*end\b", line):
                in_struct = False
                line = "}"
            else:
                line = ""
            out.append(line)
            continue
        m = re.match(r"^(\s*)hstructure\s+(\w+)", line)
        if m:
            in_struct = True
            out.append("%slocal %s = {" % (m.group(1), m.group(2)))
            continue
        if in_params:
            line = ANN.sub("", line)
            in_params = ")" not in line
            out.append(line)
            continue
        line = re.sub(r"\bhmake\s+\w+", "", line)
        m = re.match(r"^(\s*)for\s+([^=]*?)(\s*(?:=|\bin\b).*)$", line)
        if m:
            line = m.group(1) + "for " + ANN.sub("", m.group(2)) + m.group(3)
        m = re.match(r"^(\s*local\s+)([^=;]*?)(\s*(?:[=;].*)?)$", line)
        if m and not m.group(2).startswith("function"):
            line = m.group(1) + ANN.sub("", m.group(2)) + m.group(3)
        m = re.search(r"function\s*[\w.:]*\s*\(([^)]*)$", line)
        if m:  # parameter list continues on the next line
            line = line[:m.start(1)] + ANN.sub("", m.group(1))
            in_params = True
        line = re.sub(r"function\s*([\w.:]*)\s*\(([^)]*)\)",
                      lambda k: "function " + k.group(1) + "(" + ANN.sub("", k.group(2)) + ")", line)
        out.append(line)
    return "\n".join(out)


LOCALS_WARN = 185  # Lua 5.1 allows 200 locals per function; the hub hit the limit twice


def top_level_locals(stripped):
    """Count the locals declared at column 0 (the main chunk's own locals; nested blocks are indented)."""
    n = 0
    for line in stripped.split("\n"):
        m = re.match(r"^local\s+function\s+\w+", line)
        if m:
            n += 1
            continue
        m = re.match(r"^local\s+([^=]*?)\s*(?:=|$)", line)
        if m:
            n += len([x for x in m.group(1).split(",") if x.strip()])
    return n


_LUA = None


def _lua():
    global _LUA
    if _LUA is None:
        try:
            from lupa.lua51 import LuaRuntime
        except ImportError:
            r = subprocess.run([sys.executable, "-m", "pip", "install", "--quiet", "lupa"])
            if r.returncode != 0:
                _LUA = False
                return _LUA
            from lupa.lua51 import LuaRuntime
        _LUA = LuaRuntime(unpack_returned_tuples=True)
    return _LUA


def compile_check(name, stripped):
    """Compile with real Lua 5.1 (limits: 200 locals, 60 upvalues, registers, ...). Returns an error line or None;
    None as well when lupa is unavailable. The game only logs 'Syntax Error: ... too many registers' and the context dies."""
    lua = _lua()
    if not lua:
        return None
    res = lua.eval("function(src, name) local f, e = loadstring(src, '=' .. name); return f and '' or e end")(stripped, name)
    return res or None



def rel(p):
    return os.path.relpath(os.path.abspath(p), ROOT).replace("\\", "/")


def main(argv):
    verbose = "-v" in argv
    files = [a for a in argv if a != "-v"]
    try:
        ensure_tool()
    except Exception as e:
        print("cannot fetch luacheck: %s" % e, file=sys.stderr)
        return 2
    if not files:
        files = [os.path.join(d, f) for d, _, fs in os.walk(os.path.join(ROOT, "ScreenReaderAccess"))
                 for f in fs if f.endswith(".lua")]
    files = [rel(f) for f in files]
    # allow_defined_top only sees globals defined in the files of the same luacheck run: always run on the whole mod
    # (a single-file lint reported undefined g_kItemDefaults & co.) and report only the requested files.
    wanted = set(files)
    files = sorted(set(files) | set(rel(os.path.join(d, f)) for d, _, fs in os.walk(os.path.join(ROOT, "ScreenReaderAccess"))
                                    for f in fs if f.endswith(".lua")))
    tmp = os.path.join(ROOT, "util", "tools", "stripped")
    shutil.rmtree(tmp, ignore_errors=True)
    for f in files:
        dst = os.path.join(tmp, f)
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        with open(os.path.join(ROOT, f), encoding="utf-8-sig", errors="replace") as fh:
            src = fh.read()
        with open(dst, "w", encoding="utf-8", newline=None) as fh:
            fh.write(strip_annotations(src))
    compile_errors, typed_warns = [], []
    for f in files:
        if f not in wanted:
            continue
        with open(os.path.join(tmp, f), encoding="utf-8") as fh:
            stripped = fh.read()
        e = compile_check(f, stripped)
        with open(os.path.join(ROOT, f), encoding="utf-8-sig", errors="replace") as fh:
            for ln, msg in typedlocals.check(fh.read()):
                (compile_errors if f.startswith(STRICT) else typed_warns).append("%s:%d: typed local: %s" % (f, ln, msg))
        if e:
            compile_errors.append("%s (Lua 5.1 compile)" % e)
        n = top_level_locals(stripped)
        if n > LOCALS_WARN:
            print("WARN  %s: %d top-level locals (Lua limit 200): split or use a table before it breaks" % (f, n))
    r = subprocess.run([EXE, "--formatter", "plain", "--codes", "--no-color", "--no-cache",
                        "--config", os.path.join(ROOT, ".luacheckrc")] + files,
                       cwd=tmp, capture_output=True, text=True)
    errors, warns = [], []
    for line in r.stdout.splitlines():
        m = re.match(r"^(.*?):(\d+):(\d+)(?:-\d+)?: \(([EW])(\d+)\) ", line)
        if not m:
            continue
        path, code = m.group(1).replace("\\", "/"), m.group(4)
        if path not in wanted:
            continue
        if code == "E" or path.startswith(STRICT):
            errors.append(line)
        else:
            warns.append(line)
    errors = compile_errors + errors
    for l in errors:
        print("ERROR " + l)
    if verbose:
        for l in warns + typed_warns:
            print("warn  " + l)
    print("lint: %d file(s), %d error(s), %d upstream warning(s)%s" % (
        len(wanted), len(errors), len(warns), "" if verbose else " (use -v to list)"))
    if r.returncode > 2:
        print(r.stderr, file=sys.stderr)
        return 2
    override_errors = run_overridecheck()
    return 1 if (errors or override_errors) else 0


def run_overridecheck():
    """Static .civ6proj registration check (util/overridecheck.py): 1 if it found errors."""
    sys.path.insert(0, os.path.join(ROOT, "util"))
    try:
        import overridecheck
        return 1 if overridecheck.main([]) else 0
    except Exception as e:  # a broken checker must not hide lint results
        print("overridecheck failed to run: %s" % e, file=sys.stderr)
        return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
