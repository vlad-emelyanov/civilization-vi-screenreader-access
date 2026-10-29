#!/usr/bin/env python3
"""Speech audit: finds spoken lists whose items are hard to listen to (no game needed).

Input: test/regress/*.recorded.txt (the `#      | text` lines under each `#   -> PASS/FAIL` header, one window per
check), plain `SR> text` lines, and/or Lua.log (`#SCREENREADER - text` / `#SCREENREADER[NOINTERRUPT] - text`).

List items are lines ending in a position suffix ", n of m". Consecutive items with the same m form a run; a run
breaks on a non-item line, on a new window, or when m changes. Flags:
  same-first   most items of the run (>= 60%, run of >= 2) share the same first comma-separated phrase
  repeats-title the first phrase of an item repeats the opening line spoken just before the list
  late-diff     an item over 20 words whose words only differ from a neighbour after the 5th word

    python util/speechaudit.py [paths...] [--markdown out.md] [--max-lists 60] [--no-guess]
Without paths: test/regress/*.recorded.txt and the game's Lua.log.
"""
import argparse
import glob
import os
import re
import sys
from collections import OrderedDict

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ITEM = re.compile(r"^(.*), (\d+) of (\d+)$", re.S)
KEY_TOKEN = re.compile(r"\[KEY:([^\]|]*)(?:\|[^\]]*)?\]")
PAD_TOKEN = re.compile(r"\[PAD:[^\]]*\]")
KB_TOKEN = re.compile(r"\[KB:([^\]]*)\]")
LOG_LINE = re.compile(r"#SCREENREADER(?:\[NOINTERRUPT\])? - (.*)$")
SR_LINE = re.compile(r"^(?:\(earlier\) )?SR> (?:\[NOINTERRUPT\] )?(.*)$")
REC_LINE = re.compile(r"^#\s+\| (.*)$")
MIN_LONG_WORDS = 20
LATE_DIFF_WORD = 5


def clean(text):
    """[KEY:kb|button] -> kb, [PAD:...] dropped."""
    text = KEY_TOKEN.sub(lambda m: m.group(1), text)
    text = PAD_TOKEN.sub("", text)
    text = KB_TOKEN.sub(lambda m: m.group(1), text)
    return re.sub(r"\s+", " ", text).strip()


def read_windows(path):
    """-> [list of texts]; one window per recorded check, one for a log."""
    windows, cur = [], []
    with open(path, encoding="utf-8", errors="replace") as f:
        for raw in f:
            raw = raw.rstrip("\r\n")
            m = REC_LINE.match(raw)
            if m:
                cur.append(clean(m.group(1)))
                continue
            if raw.startswith("#   ->"):  # a new window of a recorded file
                if cur:
                    windows.append(cur)
                cur = []
                continue
            m = LOG_LINE.search(raw)
            if m:
                cur.append(clean(m.group(1)))
                continue
            m = SR_LINE.match(raw)
            if m:
                cur.append(clean(m.group(1)))
    if cur:
        windows.append(cur)
    return windows


def phrases(text):
    return [p.strip() for p in text.split(",") if p.strip()]


def split_title(body):
    """First item of a list carries the opening line: 'Choose X: 5 missions. First item' -> (title, item)."""
    m = re.match(r"^(.{3,100}?\b\d+ [a-z]+(?: [a-z]+)?)\. (.+)$", body)
    if m and len(m.group(1).split()) <= 14:
        return m.group(1), m.group(2)
    return None, body


def runs_of(window):
    """-> [{title, items: OrderedDict idx -> body, m}]"""
    runs, cur, prev_line = [], None, None
    for text in window:
        mm = ITEM.match(text)
        if not mm:
            cur = None
            prev_line = text
            continue
        body, idx, total = mm.group(1), int(mm.group(2)), int(mm.group(3))
        if idx < 1 or idx > total:
            cur = None
            prev_line = text
            continue
        if cur is not None and cur["m"] != total:
            cur = None
        if cur is None:
            title = prev_line
            if idx == 1:
                t, rest = split_title(body)
                if t is not None:
                    title, body = t, rest
            cur = {"title": title, "m": total, "items": OrderedDict()}
            runs.append(cur)
        cur["items"].setdefault(idx, body)
        prev_line = None if cur else text
    return runs


def norm_phrase(p):
    return re.sub(r"\d+", "N", p.lower())


def common_prefix_words(a, b):
    wa, wb = a.split(), b.split()
    n = 0
    for x, y in zip(wa, wb):
        if x != y:
            break
        n += 1
    return n


def flags_of(run):
    bodies = [run["items"][k] for k in sorted(run["items"])]
    out = []
    firsts = [norm_phrase(phrases(b)[0]) if phrases(b) else "" for b in bodies]
    if len(bodies) >= 2:
        best = max(set(firsts), key=firsts.count)
        if best and firsts.count(best) >= 0.6 * len(bodies):
            out.append(("same-first", 'first phrase "%s" in %d of %d items' % (best, firsts.count(best), len(bodies))))
    title = (run["title"] or "").lower()
    if title and len(title.split()) <= 25:
        hits = [f for f in set(firsts) if len(f) >= 4 and f in title]
        if hits:
            out.append(("repeats-title", 'first phrase "%s" repeats the opening "%s"' % (hits[0], run["title"])))
    for i, b in enumerate(bodies):
        if len(b.split()) <= MIN_LONG_WORDS:
            continue
        nb = [bodies[j] for j in (i - 1, i + 1) if 0 <= j < len(bodies)]
        if nb and max(common_prefix_words(b, o) for o in nb) >= LATE_DIFF_WORD:
            out.append(("late-diff", "long item (%d words) differs from its neighbour only after word %d" % (
                len(b.split()), max(common_prefix_words(b, o) for o in nb) + 1)))
            break
    return out


def analyse(paths):
    """-> [{flag, detail, source, title, first3, kind}]"""
    found = []
    for path in paths:
        windows = read_windows(path)
        if path.endswith(".recorded.txt"):
            # consecutive checks of one script continue the same list: join them, dropping immediate repeats
            flat = []
            for w in windows:
                for t in w:
                    if not flat or flat[-1] != t:
                        flat.append(t)
            windows = [flat]
        for window in windows:
            for run in runs_of(window):
                bodies = [run["items"][k] for k in sorted(run["items"])]
                for flag, detail in flags_of(run):
                    first = bodies[0] if bodies else ""
                    found.append({
                        "flag": flag, "detail": detail, "source": os.path.basename(path),
                        "title": run["title"], "first3": bodies[:3],
                        "kind": flag + "|" + re.sub(r"\d+", "N", (run["title"] or " ".join(first.split()[:3]))),
                    })
    return found


def dedupe(found):
    """group by kind, most frequent first; each group keeps its first example and the sources."""
    groups = OrderedDict()
    for f in found:
        g = groups.setdefault(f["kind"], {"example": f, "count": 0, "sources": []})
        g["count"] += 1
        if f["source"] not in g["sources"]:
            g["sources"].append(f["source"])
    return sorted(groups.values(), key=lambda g: -g["count"])


_LUA_CACHE = {}


def lua_files():
    if not _LUA_CACHE:
        for p in glob.glob(os.path.join(ROOT, "ScreenReaderAccess", "**", "*.lua"), recursive=True):
            try:
                with open(p, encoding="utf-8-sig", errors="replace") as f:
                    _LUA_CACHE[p] = f.read().lower()
            except OSError:
                pass
    return _LUA_CACHE


def guess_file(example):
    """Best guess of the mod file that builds the list: the file containing most distinctive static phrases."""
    words = set()
    texts = ([example["title"]] if example["title"] else []) + example["first3"]
    for t in texts:
        for p in phrases(t):
            p = re.sub(r"\d+", "", p).strip().lower()
            if len(p) >= 8 and not re.search(r"\d", p):
                words.add(p)
    score = {}
    for path, src in lua_files().items():
        n = sum(1 for w in words if w in src)
        if n:
            score[path] = n
    if not score:
        return None
    best = max(score, key=score.get)
    return os.path.relpath(best, ROOT).replace("\\", "/")


def default_inputs():
    paths = sorted(glob.glob(os.path.join(ROOT, "test", "regress", "*.recorded.txt")))
    log = os.path.join(os.environ.get("LOCALAPPDATA", ""), "Firaxis Games", "Sid Meier's Civilization VI", "Logs", "Lua.log")
    if os.path.isfile(log):
        paths.append(log)
    return paths


def render_markdown(groups, guess=True, cap=60):
    lines = ["# Speech audit", "",
             "Generated by `python util/speechaudit.py --markdown <out.md>` (write it to a scratch path; it is not committed). Flags: same-first (most items share the "
             "first phrase), repeats-title (first phrase repeats the opening line), late-diff (long items differ only after "
             "the 5th word). The file column is a guess from static text only.", ""]
    for i, g in enumerate(groups[:cap], 1):
        ex = g["example"]
        lines.append("## %d. %s: %s" % (i, ex["flag"], ex["title"] or "(no opening line)"))
        lines.append("- %s (seen %d time(s); %s)" % (ex["detail"], g["count"], ", ".join(g["sources"][:3])))
        for it in ex["first3"]:
            lines.append("  - %s" % it)
        if guess:
            lines.append("- suspected file: %s" % (guess_file(ex) or "unknown"))
        lines.append("")
    return "\n".join(lines)


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("paths", nargs="*")
    ap.add_argument("--markdown")
    ap.add_argument("--max-lists", type=int, default=60)
    ap.add_argument("--no-guess", action="store_true")
    a = ap.parse_args(argv)
    paths = a.paths or default_inputs()
    groups = dedupe(analyse(paths))
    if a.markdown:
        with open(a.markdown, "w", encoding="utf-8", newline="\n") as f:
            f.write(render_markdown(groups, not a.no_guess, a.max_lists))
        print("%d list kind(s) flagged -> %s" % (len(groups), a.markdown))
    else:
        sys.stdout.reconfigure(encoding="utf-8")
        print(render_markdown(groups, not a.no_guess, a.max_lists))
    return 0


if __name__ == "__main__":
    sys.exit(main())
