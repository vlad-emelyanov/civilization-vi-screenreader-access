#!/usr/bin/env python
"""Static check of the mod's Lua with luacheck (downloaded to util/tools/ on first use).

  python util/lint.py [files...]     (default: every .lua under ScreenReaderAccess/)

Exit codes: 0 = ok (warnings in upstream game-file copies are only printed with -v),
            1 = errors: a syntax error anywhere, or any warning in a strict file,
            2 = tool problem (download failed, ...).
Strict files = mod-only code: Assets/UI/Accessibility/*.lua and UI/Additions/*.lua.
"""
import hashlib, os, re, shutil, subprocess, sys, urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TOOLS = os.path.join(ROOT, "util", "tools")
EXE = os.path.join(TOOLS, "luacheck.exe")
VERSION = "v1.2.0"
URL = "https://github.com/lunarmodules/luacheck/releases/download/%s/luacheck.exe" % VERSION
SHA256 = "0f1c69c4d09f1ebb4d8df14c215e4553e2e639bd4cb7bf3c639b0daa6198317b"
STRICT = ("ScreenReaderAccess/Assets/UI/Accessibility/", "ScreenReaderAccess/UI/Additions/")


def ensure_tool():
    if os.path.exists(EXE):
        return
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
    tmp = os.path.join(ROOT, "util", "tools", "stripped")
    shutil.rmtree(tmp, ignore_errors=True)
    for f in files:
        dst = os.path.join(tmp, f)
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        with open(os.path.join(ROOT, f), encoding="utf-8-sig", errors="replace") as fh:
            src = fh.read()
        with open(dst, "w", encoding="utf-8", newline=None) as fh:
            fh.write(strip_annotations(src))
    r = subprocess.run([EXE, "--formatter", "plain", "--codes", "--no-color", "--no-cache",
                        "--config", os.path.join(ROOT, ".luacheckrc")] + files,
                       cwd=tmp, capture_output=True, text=True)
    errors, warns = [], []
    for line in r.stdout.splitlines():
        m = re.match(r"^(.*?):(\d+):(\d+)(?:-\d+)?: \(([EW])(\d+)\) ", line)
        if not m:
            continue
        path, code = m.group(1).replace("\\", "/"), m.group(4)
        if code == "E" or path.startswith(STRICT):
            errors.append(line)
        else:
            warns.append(line)
    for l in errors:
        print("ERROR " + l)
    if verbose:
        for l in warns:
            print("warn  " + l)
    print("lint: %d file(s), %d error(s), %d upstream warning(s)%s" % (
        len(files), len(errors), len(warns), "" if verbose else " (use -v to list)"))
    if r.returncode > 2:
        print(r.stderr, file=sys.stderr)
        return 2
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
