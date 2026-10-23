#!/usr/bin/env python
"""Static check of the mod's file registrations in ScreenReaderAccess.civ6proj against the game install.

  python util/overridecheck.py [-v] [--game DIR] [--expansions Expansion1,Expansion2]

Exit codes: 0 = ok (warnings are printed), 1 = at least one error.
The game install is read from --game, env CIV_GAME_DIR or the default Steam path; without it only the
checks that need no game files run (and a warning says so).

Rules (derived from docs/engine-notes.md and the registrations that are verified to work in game):
 * ImportFiles of a Lua file whose NAME is also imported by an enabled expansion (the deal view case:
   XP2 imports UI/Replacements/DiplomacyDealView.lua) loses; use ReplaceUIScript.
 * ImportFiles of X.lua where an enabled expansion has `ReplaceUIScript LuaContext=X` works only if the
   replacement script reaches `include("X")` (directly or through other expansion scripts, e.g.
   UnitPanel_Expansion2 -> UnitPanel_Expansion1 -> UnitPanel): then OUR copy is the file that gets
   included (UnitPanel, CityStates, WorldInput ...). If the chain never includes X the copy is dead code.
 * A DLC UI/Additions script (loaded by path from the DLC's AddUserInterfaces) cannot be overridden
   with ImportFiles; use ReplaceUIScript with LuaContext = the file stem.
 * A mod Lua file whose stem starts with a wildcard include prefix (`include("Prefix_", true)`) of the
   game or of another mod file is pulled in by that wildcard (C stack overflow when it is the file itself).
 * Registered files must exist; every .lua under ScreenReaderAccess/ must be registered; every registered
   file needs <Content Include>; no duplicates inside one action; an Accessibility/ helper included by a
   registered script must be registered in the same context (FrontEndActionData / InGameActionData).
"""
import glob
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULT_GAME = r"C:\Program Files (x86)\Steam\steamapps\common\Sid Meier's Civilization VI"
ENABLED_DLC = ("Expansion1", "Expansion2")
MOD_DIR = "ScreenReaderAccess"
PROJ = "ScreenReaderAccess.civ6proj"

# Scripts registered in FrontEndActionData although the front end has no such context (no map): a missing
# helper there is harmless, but better fix: drop the FrontEnd registration.
NO_FRONTEND_CONTEXT = {("FrontEnd", "Assets/UI/ToolTips/PlotToolTip.lua")}

INCLUDE_RE = re.compile(r'\binclude\s*\(\s*"([^"]+)"\s*(?:,\s*(true))?\s*\)')


class Finding:
    def __init__(self, level, msg):
        self.level, self.msg = level, msg

    def __repr__(self):
        return "%s: %s" % (self.level, self.msg)


def read(path):
    with open(path, encoding="utf-8-sig", errors="replace") as fh:
        return fh.read()


def stem(path):
    return os.path.splitext(os.path.basename(path.replace("\\", "/")))[0]


def norm(path):
    return path.replace("\\", "/")


def strip_xml_comments(s):
    return re.sub(r"<!--.*?-->", "", s, flags=re.S)


def strip_lua_comments(s):
    s = re.sub(r"--\[(=*)\[.*?\]\1\]", "", s, flags=re.S)
    return re.sub(r"--[^\n]*", "", s)


def includes(src):
    """-> (plain include names without .lua, wildcard prefixes)"""
    plain, wild = [], []
    for name, w in INCLUDE_RE.findall(strip_lua_comments(src)):
        name = re.sub(r"\.lua$", "", name, flags=re.I)
        (wild if w else plain).append(name)
    return plain, wild


# ---------------------------------------------------------------- .civ6proj / .modinfo parsing

def _files(block):
    return [norm(f.strip()) for f in re.findall(r"<File\b[^>]*>([^<]+)</File>", block)]


def parse_actions(xml):
    """Parse an ActionData string -> dict(imports=[...], replaces=[(context, file)], adduis=[...], other=[...]).
    Files of AddGameplayScripts / UpdateDatabase / ... go to `other`."""
    xml = strip_xml_comments(xml)
    res = {"imports": [], "replaces": [], "adduis": [], "other": [], "import_blocks": []}
    for m in re.finditer(r"<(ImportFiles|ReplaceUIScript|AddUserInterfaces|AddGameplayScripts|UpdateDatabase|"
                         r"UpdateText|UpdateArt|UpdateColors)\b([^>]*)>(.*?)</\1>", xml, flags=re.S):
        tag, body = m.group(1), m.group(3)
        if tag == "ImportFiles":
            fs = _files(body)
            res["imports"] += fs
            res["import_blocks"].append(fs)
        elif tag == "ReplaceUIScript":
            c = re.search(r"<LuaContext>([^<]*)</LuaContext>", body)
            r = re.search(r"<LuaReplace>([^<]*)</LuaReplace>", body)
            if c and r:
                res["replaces"].append((c.group(1).strip(), norm(r.group(1).strip())))
        elif tag == "AddUserInterfaces":
            res["adduis"] += _files(body)
        elif tag in ("AddGameplayScripts", "UpdateDatabase", "UpdateText", "UpdateArt", "UpdateColors"):
            res["other"] += _files(body)
    return res


def parse_proj(text):
    out = {}
    for key, name in (("fe", "FrontEndActionData"), ("ig", "InGameActionData")):
        m = re.search(r"<%s>\s*<!\[CDATA\[(.*?)\]\]>\s*</%s>" % (name, name), text, flags=re.S)
        out[key] = parse_actions(m.group(1) if m else "")
    out["content"] = [norm(c) for c in re.findall(r'<Content\s+Include="([^"]+)"', text)]
    return out


def parse_modinfo(text):
    """DLC modinfo: ImportFiles / ReplaceUIScript / AddUserInterfaces anywhere in the file."""
    return parse_actions(text)


def load_game(game_dir, dlcs):
    """Index the game install -> dict or None."""
    if not game_dir or not os.path.isdir(game_dir):
        return None
    g = {"dir": game_dir, "dlc": {}, "stems": {}, "wild": set(), "additions": {}}
    ui_dirs = [("Base", os.path.join(game_dir, "Base", "Assets", "UI"))]
    for d in sorted(glob.glob(os.path.join(game_dir, "DLC", "*"))):
        name = os.path.basename(d)
        infos = glob.glob(os.path.join(d, "*.modinfo"))
        if infos:
            info = {"imports": [], "replaces": [], "adduis": []}
            for mi in infos:
                a = parse_modinfo(read(mi))
                info["imports"] += a["imports"]
                info["replaces"] += a["replaces"]
                info["adduis"] += a["adduis"]
            g["dlc"][name] = info
        ui_dirs.append((name, os.path.join(d, "UI")))
    for owner, base in ui_dirs:
        for dirpath, _, files in os.walk(base):
            for f in files:
                if not f.lower().endswith(".lua"):
                    continue
                p = os.path.join(dirpath, f)
                g["stems"].setdefault(stem(f).lower(), []).append((owner, p))
                _, wild = includes(read(p))
                g["wild"].update((w.lower(), owner + "/" + f) for w in wild)
                if owner in dlcs and norm(p).lower().find("/ui/additions/") >= 0:
                    g["additions"].setdefault(f.lower(), []).append(owner)
    return g


def reaches(game, dlcs, start_file, target, depth=6):
    """Does the include chain from start_file (path) reach `target` (a stem)? Follows includes into the
    enabled expansions' files (by stem); base files are not followed (they cannot include our wrapper)."""
    seen = set()

    def walk(path, d):
        if d > depth or path in seen:
            return False
        seen.add(path)
        plain, _ = includes(read(path))
        for inc in plain:
            if inc.lower() == target.lower():
                return True
        for inc in plain:
            for owner, p in game["stems"].get(inc.lower(), []):
                if owner in dlcs and walk(p, d + 1):
                    return True
        return False
    return walk(start_file, 0)


# ---------------------------------------------------------------- the checks

def check(repo_root, game_dir=None, dlcs=ENABLED_DLC):
    """-> list of Finding. repo_root contains ScreenReaderAccess/ScreenReaderAccess.civ6proj."""
    out = []
    mod = os.path.join(repo_root, MOD_DIR)
    proj_path = os.path.join(mod, PROJ)
    proj = parse_proj(read(proj_path))
    game = load_game(game_dir, dlcs)
    if game is None:
        out.append(Finding("warn", "game install not found (%s): checks against the game are skipped "
                           "(set CIV_GAME_DIR)" % game_dir))

    ctxs = {"FrontEnd": proj["fe"], "InGame": proj["ig"]}
    content = {c.lower() for c in proj["content"]}
    registered = {}       # normalized rel path -> set of contexts
    for ctx, a in ctxs.items():
        for f in a["imports"] + a["adduis"] + a["other"] + [r for _, r in a["replaces"]]:
            registered.setdefault(f, set()).add(ctx)

    # --- existence, duplicates, Content Include
    for ctx, a in ctxs.items():
        for blk in a["import_blocks"]:
            seen = set()
            for f in blk:
                if f.lower() in seen:
                    out.append(Finding("error", "%s: %s is listed twice in the same ImportFiles" % (ctx, f)))
                seen.add(f.lower())
        seen = set()
        for c, r in a["replaces"]:
            if c in seen:
                out.append(Finding("error", "%s: two ReplaceUIScript for LuaContext %s" % (ctx, c)))
            seen.add(c)
            if r not in a["imports"]:
                out.append(Finding("warn", "%s: ReplaceUIScript %s -> %s: the file is not in the same context's "
                                   "ImportFiles" % (ctx, c, r)))
    for f in sorted(registered):
        if not os.path.exists(os.path.join(mod, *f.split("/"))):
            out.append(Finding("error", "registered file does not exist: %s" % f))
        if f.lower() not in content:
            out.append(Finding("error", "no <Content Include> for %s (the build would not ship it)" % f))
    for c in sorted(content):
        if not os.path.exists(os.path.join(mod, *c.split("/"))):
            out.append(Finding("error", "<Content Include> of a missing file: %s" % c))

    # --- unregistered .lua
    xml_stems = {f[:-4].lower() for f in registered if f.lower().endswith(".xml")}
    for dirpath, _, files in os.walk(mod):
        for fn in files:
            if not fn.lower().endswith(".lua"):
                continue
            rel = norm(os.path.relpath(os.path.join(dirpath, fn), mod))
            if rel in registered or rel[:-4].lower() in xml_stems:
                continue
            out.append(Finding("error", "%s is not registered in the .civ6proj (ImportFiles/ReplaceUIScript/"
                               "AddUserInterfaces/AddGameplayScripts)" % rel))

    # --- includes of Accessibility helpers
    mod_by_stem = {}
    for dirpath, _, files in os.walk(os.path.join(mod, "Assets", "UI", "Accessibility")):
        for fn in files:
            if fn.lower().endswith(".lua"):
                mod_by_stem[stem(fn).lower()] = norm(os.path.relpath(os.path.join(dirpath, fn), mod))
    for ctx, a in ctxs.items():
        have = set(a["imports"] + a["other"])
        reported = set()
        for f in sorted(set(a["imports"])):
            todo, seen = [f], set()
            while todo:
                cur = todo.pop()
                if cur in seen:
                    continue
                seen.add(cur)
                p = os.path.join(mod, *cur.split("/"))
                if not os.path.exists(p):
                    continue
                for inc in includes(read(p))[0]:
                    h = mod_by_stem.get(inc.lower())
                    if not h:
                        continue
                    if h not in have:
                        if (h, cur) in reported:
                            continue
                        reported.add((h, cur))
                        out.append(Finding("warn" if (ctx, f) in NO_FRONTEND_CONTEXT else "error", "%s: %s includes %s (via %s) but it is missing from %s "
                                           "ImportFiles (the script silently aborts there)" % (
                                               ctx, f, h, cur, "FrontEndActionData" if ctx == "FrontEnd"
                                               else "InGameActionData")))
                    else:
                        todo.append(h)

    # --- wildcard include trap
    prefixes = set()
    if game:
        prefixes |= game["wild"]
    mod_files = sorted(f for f in registered if f.lower().endswith(".lua")
                       and os.path.exists(os.path.join(mod, *f.split("/"))))
    for f in mod_files:
        for w in includes(read(os.path.join(mod, *f.split("/"))))[1]:
            prefixes.add((w.lower(), "mod file " + f))
    for f in mod_files:
        s = stem(f).lower()
        for pre, who in sorted(prefixes):
            if s.startswith(pre):
                out.append(Finding("error", "%s: the name starts with the wildcard include prefix %r of %s; the "
                                   "wildcard would load it (stack overflow when it is the file itself). Rename "
                                   "it (e.g. SRA_...)" % (f, pre, who)))

    if not game:
        return out

    # --- checks against the game
    dl = {d: game["dlc"].get(d, {"imports": [], "replaces": [], "adduis": []}) for d in dlcs}
    dlc_import_names = {}
    for d, info in dl.items():
        for f in info["imports"]:
            if f.lower().endswith(".lua"):
                dlc_import_names.setdefault(os.path.basename(f).lower(), []).append((d, f))
    for ctx, a in ctxs.items():
        replace_files = {r for _, r in a["replaces"]}
        for f in a["imports"]:
            if not f.lower().endswith(".lua"):
                continue
            base = os.path.basename(f)
            s = stem(f)
            is_replacement_copy = f in replace_files
            for d, df in dlc_import_names.get(base.lower(), []):
                if f.startswith("Assets/UI/Accessibility/"):
                    continue
                out.append(Finding("error", "%s: ImportFiles copy %s likely loses to DLC/%s/%s; use "
                                   "ReplaceUIScript (see docs/engine-notes.md)" % (ctx, f, d, df)))
            for d in game["additions"].get(base.lower(), []):
                if not is_replacement_copy:
                    out.append(Finding("error", "%s: %s overrides the DLC/%s UI/Additions script of the same "
                                       "name with ImportFiles; use ReplaceUIScript (LuaContext %s)" % (ctx, f, d, s)))
            if is_replacement_copy or f.startswith("Assets/UI/Accessibility/"):
                continue
            for d in dlcs:
                for c, r in dl[d]["replaces"]:
                    if c.lower() != s.lower():
                        continue
                    target = os.path.join(game["dir"], "DLC", d, *r.split("/"))
                    if not os.path.exists(target):
                        continue
                    if not reaches(game, dlcs, target, s):
                        out.append(Finding("error", "%s: ImportFiles copy %s is dead code: DLC/%s replaces the "
                                           "script %s with %s, which never includes %s; use ReplaceUIScript" % (
                                               ctx, f, d, s, r, s)))
            if (s.lower() not in game["stems"] and f not in registered_mod_only(mod_by_stem)
                    and "/Replacements/" not in f):
                out.append(Finding("warn", "%s: %s matches no game script (typo?)" % (ctx, f)))
        for c, r in a["replaces"]:
            if c.lower() not in game["stems"]:
                out.append(Finding("warn", "%s: ReplaceUIScript LuaContext %s matches no game script" % (ctx, c)))
            for d in dlcs:
                for c2, r2 in dl[d]["replaces"]:
                    if c2 == c:
                        out.append(Finding("warn", "%s: LuaContext %s is also replaced by DLC/%s (%s); "
                                           "which one wins is unverified" % (ctx, c, d, r2)))
    return out


def registered_mod_only(mod_by_stem):
    return set(mod_by_stem.values())


def game_dir_from_env(arg=None):
    return arg or os.environ.get("CIV_GAME_DIR") or DEFAULT_GAME


def main(argv):
    game = None
    dlcs = ENABLED_DLC
    verbose = False
    it = iter(argv)
    for a in it:
        if a == "--game":
            game = next(it)
        elif a == "--expansions":
            dlcs = tuple(x for x in next(it).split(",") if x)
        elif a == "-v":
            verbose = True
        else:
            print(__doc__)
            return 2
    findings = check(ROOT, game_dir_from_env(game), dlcs)
    errs = [f for f in findings if f.level == "error"]
    for f in findings:
        if f.level == "error" or verbose or f.level == "warn":
            print("%s %s" % ("ERROR" if f.level == "error" else "warn ", f.msg))
    print("overridecheck: %d error(s), %d warning(s)" % (len(errs), len(findings) - len(errs)))
    return 1 if errs else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
