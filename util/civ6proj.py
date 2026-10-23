#!/usr/bin/env python
"""Edit and merge ScreenReaderAccess.civ6proj without hand-editing its one-line CDATA blocks (stdlib only).

  python util/civ6proj.py list [--proj PATH]
  python util/civ6proj.py add <file> --context InGame|FrontEnd|Both [--replace-ui <LuaContext>] [--proj PATH]
  python util/civ6proj.py merge-union <ours> <theirs> [--base <base>] [--out PATH]
  python util/civ6proj.py merge-driver <base> <ours> <theirs>        (git merge driver: result is written to <ours>)

<file> is relative to the mod folder ScreenReaderAccess/ (a leading "ScreenReaderAccess/" or backslashes are fine), e.g.
Assets/UI/Popups/FooPopup.lua or UI/Replacements/Foo_SRA.lua.
  add            Without --replace-ui: a <File priority="10001"> in the ImportFiles of the context(s) (FrontEndActionData /
                 InGameActionData; "Both" = both). With --replace-ui Foo: a <ReplaceUIScript id="SRAccess_IG_Foo"> (LuaContext Foo,
                 LuaReplace <file>) instead (id prefix SRAccess_FE_ for the front end). Always also a <Content Include> entry (that is
                 what ModBuddy ships). Already registered = nothing changes. Prints what it changed.
  list           Every registered entry per context, plus warnings: Content entries missing for registered files, files that do not exist.
  merge-union    Writes the union of the File / ReplaceUIScript / AddUserInterfaces / AddGameplayScripts / UpdateDatabase entries and
                 the Content entries of both versions into <ours> (or --out). Everything else is taken from <ours>. With --base an
                 entry that <theirs> deleted relative to the base is removed (otherwise nothing is ever removed).
  merge-driver   The same for `git`: set it up once per clone with
                   git config merge.civ6proj.name "civ6proj union"
                   git config merge.civ6proj.driver "python util/civ6proj.py merge-driver %O %A %B"
                 (.gitattributes already maps *.civ6proj to it). On a plain conflict:
                   git checkout --ours/--theirs copies, then `python util/civ6proj.py merge-union <ours> <theirs> --out <file>`.

The file is edited as text: the UTF-8 BOM, CRLF line endings and every byte outside the touched entries are preserved.
"""
from __future__ import annotations

import argparse
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULT_PROJ = os.path.join(ROOT, "ScreenReaderAccess", "ScreenReaderAccess.civ6proj")
BOM = b"\xef\xbb\xbf"
PRIORITY = "10001"

CONTEXTS = {"FrontEnd": ("FrontEndActionData", "FrontEndActions", "FE"), "InGame": ("InGameActionData", "InGameActions", "IG")}

CDATA_RE = {k: re.compile(r"(<%s><!\[CDATA\[)(.*?)(\]\]></%s>)" % (v[0], v[0]), re.S) for k, v in CONTEXTS.items()}
# one top-level action element: <Tag id="x">...</Tag> (no element of the same name nests inside another)
ELEM_RE = re.compile(r'<(\w+) id="([^"]*)">(.*?)</\1>', re.S)
FILE_RE = re.compile(r"<File(?: [^>]*)?>([^<]*)</File>")
CONTENT_RE = re.compile(r'[ \t]*<Content Include="([^"]+)">.*?</Content>', re.S)
FILE_ELEMS = ("ImportFiles", "AddGameplayScripts", "UpdateDatabase")  # elements whose body is a list of <File>


class ProjError(Exception):
    pass


# ----------------------------------------------------------------------------- text <-> pieces

def read_text(path):
    """(text, had_bom). Decoded without newline translation, so CRLF survives a round trip."""
    with open(path, "rb") as f:
        b = f.read()
    bom = b.startswith(BOM)
    return b[len(BOM):].decode("utf-8") if bom else b.decode("utf-8"), bom


def write_text(path, text, bom):
    with open(path, "wb") as f:
        f.write((BOM if bom else b"") + text.encode("utf-8"))


def eol_of(text):
    return "\r\n" if "\r\n" in text else "\n"


def norm_file(p):
    """Mod-relative path with forward slashes (the form used inside the CDATA blocks)."""
    p = p.strip().replace("\\", "/")
    if p.lower().startswith("screenreaderaccess/"):
        p = p[len("screenreaderaccess/"):]
    return p[2:] if p.startswith("./") else p


def key_of(p):
    return norm_file(p).lower()


def get_block(text, ctx):
    """(prefix, body, suffix, start, end) of the CDATA of a context, or None."""
    m = CDATA_RE[ctx].search(text)
    return (m.group(1), m.group(2), m.group(3), m.start(), m.end()) if m else None


def split_elements(body):
    """body of <InGameActions>...</InGameActions> -> (head, [(tag, id, inner, full)], tail)."""
    open_m = re.match(r"(\s*<\w+Actions>)(.*)(</\w+Actions>\s*)$", body, re.S)
    if not open_m:
        raise ProjError("unexpected action block layout: " + body[:80])
    head, inner, tail = open_m.groups()
    elems = [(m.group(1), m.group(2), m.group(3), m.group(0)) for m in ELEM_RE.finditer(inner)]
    return head, elems, tail


def file_entries(inner):
    return [m.group(1) for m in FILE_RE.finditer(inner)]


def file_xml(tag, path):
    return '<File priority="%s">%s</File>' % (PRIORITY, path) if tag == "ImportFiles" else "<File>%s</File>" % path


def replace_xml(ctx, lua_ctx, path):
    return ('<ReplaceUIScript id="SRAccess_%s_%s"><Properties><LuaContext>%s</LuaContext><LuaReplace>%s</LuaReplace>'
            "</Properties></ReplaceUIScript>" % (CONTEXTS[ctx][2], lua_ctx, lua_ctx, path))


def content_xml(path, eol):
    return '    <Content Include="%s">%s      <SubType>Content</SubType>%s    </Content>' % (path.replace("/", "\\"), eol, eol)


def content_includes(text):
    return [m.group(1) for m in CONTENT_RE.finditer(text)]


def add_content(text, path):
    """Appends a <Content Include> after the last one. Returns (text, added)."""
    want = path.replace("/", "\\").lower()
    ms = list(CONTENT_RE.finditer(text))
    if any(m.group(1).lower() == want for m in ms):
        return text, False
    if not ms:
        raise ProjError("no <Content Include> entries to anchor the new one")
    eol = eol_of(text)
    last = ms[-1]
    return text[:last.end()] + eol + content_xml(path, eol) + text[last.end():], True


# ----------------------------------------------------------------------------- list / add

def registered(text):
    """{ctx: [(tag, id, [files])]} for the two action blocks."""
    res = {}
    for ctx in CONTEXTS:
        blk = get_block(text, ctx)
        if not blk:
            continue
        _, elems, _ = split_elements(blk[1])
        res[ctx] = [(t, i, file_entries(inner) if t in FILE_ELEMS else [inner_summary(inner)]) for t, i, inner, _ in elems]
    return res


def inner_summary(inner):
    m = re.search(r"<LuaContext>([^<]*)</LuaContext>.*?<LuaReplace>([^<]*)</LuaReplace>", inner, re.S)
    if m:
        return "%s -> %s" % (m.group(1), m.group(2))
    f = FILE_RE.search(inner)
    return f.group(1) if f else re.sub(r"<[^>]+>", " ", inner).strip()


def add_entry(text, ctx, path, replace_ui=None):
    """Registers path in one context. Returns (text, [messages])."""
    blk = get_block(text, ctx)
    if not blk:
        raise ProjError("no %s block in the project" % CONTEXTS[ctx][0])
    pre, body, suf, start, end = blk
    head, elems, tail = split_elements(body)
    msgs = []
    if replace_ui:
        eid = "SRAccess_%s_%s" % (CONTEXTS[ctx][2], replace_ui)
        found = [e for e in elems if e[0] == "ReplaceUIScript" and (e[1] == eid or
                 re.search(r"<LuaContext>%s</LuaContext>" % re.escape(replace_ui), e[2]))]
        if found:
            if key_of(path) not in key_of(found[0][2]):
                raise ProjError("%s already replaces %s with a different file: %s" % (CONTEXTS[ctx][0], replace_ui, inner_summary(found[0][2])))
        else:
            inner = body[len(head):len(body) - len(tail)]
            body = head + inner + replace_xml(ctx, replace_ui, path) + tail
            msgs.append("%s: ReplaceUIScript %s -> %s" % (CONTEXTS[ctx][0], replace_ui, path))
    else:
        imp = next((e for e in elems if e[0] == "ImportFiles"), None)
        if not imp:
            raise ProjError("no ImportFiles element in " + CONTEXTS[ctx][0])
        if key_of(path) not in [key_of(f) for f in file_entries(imp[2])]:
            new_full = imp[3].replace("</ImportFiles>", file_xml("ImportFiles", path) + "</ImportFiles>")
            body = body.replace(imp[3], new_full, 1)
            msgs.append("%s: ImportFiles + %s" % (CONTEXTS[ctx][0], path))
    return text[:start] + pre + body + suf + text[end:], msgs


def cmd_add(a):
    path = norm_file(a.file)
    ctxs = ["FrontEnd", "InGame"] if a.context == "Both" else [a.context]
    text, bom = read_text(a.proj)
    msgs = []
    for ctx in ctxs:
        text, m = add_entry(text, ctx, path, a.replace_ui)
        msgs += m
    text, added = add_content(text, path)
    if added:
        msgs.append("Content Include " + path.replace("/", "\\"))
    if not os.path.exists(os.path.join(os.path.dirname(a.proj), *path.split("/"))):
        print("warning: %s does not exist yet under %s" % (path, os.path.dirname(a.proj)))
    if msgs:
        write_text(a.proj, text, bom)
        print("\n".join(msgs))
    else:
        print("already registered: " + path)
    return 0


def problems(text, mod_dir=None):
    """Warnings: registered files without a Content entry / missing on disk."""
    inc = {c.replace("\\", "/").lower() for c in content_includes(text)}
    out = []
    for ctx, items in registered(text).items():
        for tag, ident, files in items:
            if tag == "ReplaceUIScript":
                files = [f.split(" -> ")[-1] for f in files]
            elif tag not in FILE_ELEMS:
                files = []
            for f in files:
                if f.lower() not in inc:
                    out.append("%s: %s has no <Content Include>" % (CONTEXTS[ctx][0], f))
                if mod_dir and not os.path.exists(os.path.join(mod_dir, *f.split("/"))):
                    out.append("%s: %s does not exist under %s" % (CONTEXTS[ctx][0], f, mod_dir))
    return out


def cmd_list(a):
    text, _ = read_text(a.proj)
    for ctx, items in registered(text).items():
        print("%s:" % CONTEXTS[ctx][0])
        for tag, ident, files in items:
            print("  %s %s (%d)" % (tag, ident, len(files)))
            for f in files:
                print("    " + f)
    print("Content entries: %d" % len(content_includes(text)))
    for w in problems(text, os.path.dirname(a.proj)):
        print("warning: " + w)
    return 0


# ----------------------------------------------------------------------------- merge

def entry_keys(elem):
    """Identity of every sub-entry of an action element (files); [] for elements that are one unit."""
    return [key_of(f) for f in file_entries(elem[2])] if elem[0] in FILE_ELEMS else []


def merge_text(ours, theirs, base=None):
    """Union of the registered entries of ours and theirs, on the text of ours. Returns merged text."""
    text = ours
    for ctx in CONTEXTS:
        bo, bt = get_block(text, ctx), get_block(theirs, ctx)
        bb = get_block(base, ctx) if base else None
        if not bt:
            continue
        if not bo:
            raise ProjError("ours has no %s block" % CONTEXTS[ctx][0])
        pre, body, suf, start, end = bo
        head, o_el, tail = split_elements(body)
        _, t_el, _ = split_elements(bt[1])
        b_el = split_elements(bb[1])[1] if bb else []
        base_ids = {(e[0], e[1]) for e in b_el}
        base_files = {(e[0], e[1]): set(entry_keys(e)) for e in b_el}
        theirs_ids = {(e[0], e[1]) for e in t_el}
        theirs_files = {(e[0], e[1]): set(entry_keys(e)) for e in t_el}
        # theirs' deletions (only with a base): elements and files that were in base and are gone from theirs
        for e in o_el:
            kid = (e[0], e[1])
            if kid in base_ids and kid not in theirs_ids and e[3] in body:
                body = body.replace(e[3], "", 1)
            elif kid in base_files and kid in theirs_files and e[0] in FILE_ELEMS:
                gone = base_files[kid] - theirs_files[kid]
                if gone:
                    new_full = e[3]
                    for m in list(FILE_RE.finditer(e[3])):
                        if key_of(m.group(1)) in gone:
                            new_full = new_full.replace(m.group(0), "", 1)
                    body = body.replace(e[3], new_full, 1)
        head, o_el, tail = split_elements(body)
        by_id = {(e[0], e[1]): e for e in o_el}
        for te in t_el:
            kid = (te[0], te[1])
            if kid not in by_id:
                if kid in base_ids:
                    continue  # ours deleted it
                inner_end = len(body) - len(tail)
                body = body[:inner_end] + te[3] + body[inner_end:]
            elif te[0] in FILE_ELEMS:
                oe = by_id[kid]
                have = set(entry_keys(oe))
                known = base_files.get(kid, set())
                add = [f for f in file_entries(te[2]) if key_of(f) not in have and not (key_of(f) in known and base)]
                if add:
                    new_full = oe[3].replace("</%s>" % oe[0], "".join(file_xml(oe[0], f) for f in add) + "</%s>" % oe[0])
                    body = body.replace(oe[3], new_full, 1)
        text = text[:start] + pre + body + suf + text[end:]
    # Content entries
    have = {c.lower() for c in content_includes(text)}
    base_inc = {c.lower() for c in content_includes(base)} if base else set()
    their_inc = [m for m in CONTENT_RE.finditer(theirs)]
    for m in their_inc:
        if m.group(1).lower() not in have and not (m.group(1).lower() in base_inc):
            text, _ = add_content(text, m.group(1).replace("\\", "/"))
    if base:
        for c in content_includes(text):
            if c.lower() in base_inc and c.lower() not in {x.group(1).lower() for x in their_inc}:
                m = next(x for x in CONTENT_RE.finditer(text) if x.group(1) == c)
                s, e = m.start(), m.end()
                while s > 0 and text[s - 1] in " \t":
                    s -= 1
                e2 = e + (2 if text.startswith("\r\n", e) else 1 if text.startswith("\n", e) else 0)
                text = text[:s] + text[e2:]
    return text


def merge_files(ours_path, theirs_path, base_path, out_path):
    ours, bom = read_text(ours_path)
    theirs, _ = read_text(theirs_path)
    base = read_text(base_path)[0] if base_path and os.path.getsize(base_path) else None
    merged = merge_text(ours, theirs, base)
    write_text(out_path, merged, bom)


def cmd_merge_union(a):
    merge_files(a.ours, a.theirs, a.base, a.out or a.ours)
    print("merged %s + %s -> %s" % (a.ours, a.theirs, a.out or a.ours))
    return 0


def cmd_merge_driver(a):
    try:
        merge_files(a.ours, a.theirs, a.base, a.ours)
    except Exception as e:  # git treats a non-zero exit as "conflict" and keeps the file for manual resolution
        print("civ6proj merge driver failed: %s" % e, file=sys.stderr)
        return 1
    return 0


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    sub = ap.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("list"); p.add_argument("--proj", default=DEFAULT_PROJ); p.set_defaults(fn=cmd_list)
    p = sub.add_parser("add")
    p.add_argument("file"); p.add_argument("--context", required=True, choices=["InGame", "FrontEnd", "Both"])
    p.add_argument("--replace-ui", metavar="LuaContext"); p.add_argument("--proj", default=DEFAULT_PROJ); p.set_defaults(fn=cmd_add)
    p = sub.add_parser("merge-union")
    p.add_argument("ours"); p.add_argument("theirs"); p.add_argument("--base"); p.add_argument("--out"); p.set_defaults(fn=cmd_merge_union)
    p = sub.add_parser("merge-driver")
    p.add_argument("base"); p.add_argument("ours"); p.add_argument("theirs"); p.set_defaults(fn=cmd_merge_driver)
    a = ap.parse_args(argv)
    try:
        return a.fn(a)
    except ProjError as e:
        print("ERROR: %s" % e, file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
