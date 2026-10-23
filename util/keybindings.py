#!/usr/bin/env python
"""Civ VI key bindings without the game: action -> key(s) in `civctl key` syntax.

  python util/keybindings.py [--json] [action]       list all actions / one action (case-insensitive id)
  python util/keybindings.py --key <action>          just the civctl key of the primary binding (exit 2 when unbound)
  python util/keybindings.py --write-keymap [path]   regenerate .claude/skills/civ-test/keymap.md (civctl keymap)

Resolution (per action, KBMouse gestures only; "Controller" gestures are ignored):
  1. InputSettings.json in %LOCALAPPDATA%\\Firaxis Games\\Sid Meier's Civilization VI holds the user's bindings. An action
     that appears there uses ONLY what is stored (two slots: primary, alternate); `[{}, {}]` means explicitly unbound.
  2. An action missing from the JSON (e.g. a mod action added after the file was last written) uses its default gestures:
     the mod's ScreenReaderAccess/Database/*.sql (InputActions / InputActionDefaultGestures INSERTs) and the game's own
     Base/Assets/Configuration/Data/InputConfiguration.xml plus DLC/*/Config|Data/*_Config.xml (InsertOrIgnore rows).
  Names, descriptions and categories come from those same definitions; LOC_ tags are resolved with the game's en_US text.
  The game directory is optional (env CIV_GAME_DIR, default the Steam path): without it only mod actions and the JSON are known.

Flags: `jaws` = the key must never be sent (JAWS commands, see JAWS_RESERVED); duplicates = two actions on one key (check whether
they share a context before worrying: the game only has one World context, so most are real conflicts).
"""
import argparse
import glob
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MOD_SQL_GLOB = os.path.join(ROOT, "ScreenReaderAccess", "Database", "*.sql")
KEYMAP_MD = os.path.join(ROOT, ".claude", "skills", "civ-test", "keymap.md")
CIV_DOCS = "Sid Meier's Civilization VI"
DEFAULT_GAME_DIR = r"C:\Program Files (x86)\Steam\steamapps\common\Sid Meier's Civilization VI"

# Keys that JAWS grabs (NumPad +/- toggle the JAWS cursor, arrows/Home/End then stop reaching any window; the other numpad keys
# and Insert are JAWS commands too). Divide stays allowed (a game hotkey). Keep in sync with $JawsReservedKeys in
# util/civctl.ps1 (test/py/test_keybindings.py compares them).
JAWS_RESERVED = ("Add", "Subtract", "Multiply", "Decimal", "Insert", "Clear",
                 "NumPad0", "NumPad1", "NumPad2", "NumPad3", "NumPad4", "NumPad5", "NumPad6", "NumPad7", "NumPad8", "NumPad9")

# LOC_OPTIONS_KEY_<id> (without prefix) -> System.Windows.Forms.Keys name as `civctl key` parses it.
_KEYS = {
    "PLUS": "OemPlus", "MINUS": "OemMinus", "COMMA": "OemComma", "PERIOD": "OemPeriod", "SLASH": "OemQuestion",
    "TILDE": "Oemtilde", "SEMICOLON": "OemSemicolon", "QUOTE": "OemQuotes", "LBRACKET": "OemOpenBrackets",
    "RBRACKET": "OemCloseBrackets", "BACKSLASH": "OemPipe", "UNDERSCORE": "OemMinus",
    "RETURN": "Enter", "ESCAPE": "Escape", "SPACE": "Space", "TAB": "Tab", "BACKSPACE": "Back", "DELETE": "Delete",
    "INSERT": "Insert", "HOME": "Home", "END": "End", "PAGEUP": "Prior", "PAGEDOWN": "Next",
    "LEFT": "Left", "RIGHT": "Right", "UP": "Up", "DOWN": "Down",
    "NP_MULTIPLY": "Multiply", "NP_PLUS": "Add", "NP_MINUS": "Subtract", "NP_DECIMAL": "Decimal", "NP_DIVIDE": "Divide",
    "NP_CENTER": "Clear", "PAUSE": "Pause", "PRINTSCREEN": "PrintScreen", "CAPSLOCK": "Capital",
    "SHIFT": "Shift", "LSHIFT": "Shift", "RSHIFT": "Shift", "CONTROL": "Control", "LCONTROL": "Control",
    "RCONTROL": "Control", "ALT": "Alt", "LALT": "Alt", "RALT": "Alt",
}
_MODS = ("Control", "Shift", "Alt")


def key_token(tag):
    """One LOC_OPTIONS_KEY_X tag -> civctl key name, or '?' when civctl cannot send it."""
    k = re.sub(r"^LOC_OPTIONS_KEY_", "", tag.strip())
    if k in _KEYS:
        return _KEYS[k]
    if re.fullmatch(r"[A-Z]", k) or re.fullmatch(r"F([1-9]|1\d|2[0-4])", k):
        return k
    if re.fullmatch(r"[0-9]", k):
        return "D" + k
    m = re.fullmatch(r"NP_([0-9])", k)
    if m:
        return "NumPad" + m.group(1)
    return "?"


def gesture_to_civctl(data):
    """'LOC_OPTIONS_KEY_CONTROL+LOC_OPTIONS_KEY_N' -> 'Control+N' (modifiers first, in civctl's order)."""
    toks = [key_token(t) for t in data.split("+") if t.strip()]
    mods = [m for m in _MODS if m in toks[:-1]]
    return "+".join(mods + toks[-1:]) if toks else ""


def jaws_reserved(civctl_key):
    return civctl_key.split("+")[-1] in JAWS_RESERVED


# ---- sources --------------------------------------------------------------------------------------------------------

def default_settings_path():
    return os.path.join(os.environ.get("LOCALAPPDATA", ""), "Firaxis Games", CIV_DOCS, "InputSettings.json")


def default_game_dir():
    d = os.environ.get("CIV_GAME_DIR") or DEFAULT_GAME_DIR
    return d if os.path.isdir(d) else None


def load_settings(path):
    """InputSettings.json -> {action: [gesture data or '' for KBMouse slot 0, 1, ...]}; None when the file is missing."""
    if not path or not os.path.isfile(path):
        return None
    with open(path, encoding="utf-8-sig") as f:
        raw = json.load(f)
    out = {}
    for action, slots in raw.items():
        kb = [e.get("data", "") for e in slots if e.get("type") == "KBMouse"]
        out[action] = kb
    return out


def _read(path):
    with open(path, encoding="utf-8-sig", errors="replace") as f:
        return f.read()


_SQL_STR = r"'((?:[^']|'')*)'"


def _unq(s):
    return s.replace("''", "'")


def parse_sql(text):
    """Mod SQL -> (actions {id: dict}, gestures [(id, index, type, data)])."""
    actions, gestures = {}, []
    rx_a = re.compile(r'INSERT\s+(?:OR\s+\w+\s+)?INTO\s+"?InputActions"?\s+VALUES\s*\(\s*' + _SQL_STR + r"\s*,\s*" + _SQL_STR + r"\s*,\s*" +
                      _SQL_STR + r"\s*,\s*" + _SQL_STR + r"\s*,\s*" + _SQL_STR + r"\s*,\s*" + _SQL_STR, re.I)
    for m in rx_a.finditer(text):
        i, n, d, c, ctx, lay = (_unq(g) for g in m.groups())
        actions[i] = dict(id=i, name=n, description=d, category=c, context=ctx, layout=lay)
    rx_g = re.compile(r'INSERT\s+(?:OR\s+\w+\s+)?INTO\s+"?InputActionDefaultGestures"?\s+VALUES\s*\(\s*' + _SQL_STR +
                      r"\s*,\s*(\d+)\s*,\s*" + _SQL_STR + r"\s*,\s*" + _SQL_STR, re.I)
    for m in rx_g.finditer(text):
        gestures.append((_unq(m.group(1)), int(m.group(2)), m.group(3), _unq(m.group(4))))
    return actions, gestures


def parse_config_xml(text):
    """Game config XML (<Row>/<InsertOrIgnore> under InputActions, InputActionDefaultGestures, InputCategories)."""
    actions, gestures, cats = {}, [], {}
    attr = re.compile(r'(\w+)="([^"]*)"')
    text = re.sub(r"<!--.*?-->", "", text, flags=re.S)
    for sec, rows in re.findall(r"<(InputActions|InputActionDefaultGestures|InputCategories)>(.*?)</\1>", text, flags=re.S):
        for row in re.findall(r"<(?:Row|InsertOrIgnore|Replace)\b([^>]*?)/?>", rows):
            a = dict(attr.findall(row))
            if sec == "InputActions" and "ActionId" in a:
                actions[a["ActionId"]] = dict(id=a["ActionId"], name=a.get("Name", ""), description=a.get("Description", ""),
                                              category=a.get("CategoryId", ""), context=a.get("ContextId", ""),
                                              layout=a.get("LayoutType", "PC"))
            elif sec == "InputActionDefaultGestures" and "ActionId" in a:
                gestures.append((a["ActionId"], int(a.get("Index", "0")), a.get("GestureType", ""), a.get("GestureData", "")))
            elif sec == "InputCategories" and "CategoryId" in a:
                cats[a["CategoryId"]] = a.get("Name", "")
    return actions, gestures, cats


class Text:
    """Lazy English text lookup (LOC_ tag -> string) from the game's en_US text files; no game dir = tags stay as they are."""

    def __init__(self, game_dir):
        self.files = []
        if game_dir:
            self.files = [os.path.join(game_dir, "Base", "Assets", "Text", "en_US", "UI_Options_Text.xml")]
            self.files += sorted(glob.glob(os.path.join(game_dir, "Base", "Assets", "Text", "en_US", "*.xml")))
            self.files += sorted(glob.glob(os.path.join(game_dir, "DLC", "*", "Text", "en_US", "*.xml")))
        self.cache = {}
        self._next = 0

    def get(self, tag):
        if not tag or not tag.startswith("LOC_"):
            return tag
        while tag not in self.cache and self._next < len(self.files):
            f = self.files[self._next]
            self._next += 1
            if os.path.isfile(f):
                for t, s in re.findall(r'<Row\s+Tag="([^"]+)"[^>]*>\s*<Text>(.*?)</Text>', _read(f), flags=re.S):
                    self.cache.setdefault(t, _xml_unescape(s.strip()))
        return self.cache.get(tag, tag)


def _xml_unescape(s):
    return s.replace("&lt;", "<").replace("&gt;", ">").replace("&quot;", '"').replace("&apos;", "'").replace("&amp;", "&")


def _humanize(action_id):
    return re.sub(r"(?<=[a-z0-9])(?=[A-Z])", " ", action_id)


def _kb_defaults(gestures):
    """[(id, index, type, data)] -> {id: [data or '' for KBMouse slots]} ordered by index (INSERT OR IGNORE: first row wins)."""
    slots = {}
    for aid, idx, typ, data in gestures:
        if typ == "KBMouse":
            slots.setdefault(aid, {}).setdefault(idx, data)
    return {aid: [d[i] for i in sorted(d)] for aid, d in slots.items()}


# ---- resolution -----------------------------------------------------------------------------------------------------

class Binding:
    def __init__(self, action_id, name, description, category, layout, context, keys, displays, source):
        self.id, self.name, self.description, self.category = action_id, name, description, category
        self.layout, self.context = layout, context
        self.keys, self.displays, self.source = keys, displays, source   # parallel lists, primary first; '' slots are dropped
        self.flags = []

    @property
    def key(self):
        return self.keys[0] if self.keys else ""

    @property
    def alternate(self):
        return self.keys[1] if len(self.keys) > 1 else ""

    def to_dict(self):
        return dict(action=self.id, name=self.name, description=self.description, category=self.category, key=self.key,
                    alternate=self.alternate, keys=self.keys, display=self.displays, source=self.source, flags=self.flags)


def load_bindings(settings_path="default", sql_files=None, game_dir="default"):
    """-> (list of Binding sorted by category/name, dict category id -> display title).
    settings_path/game_dir 'default' = the user's real locations; None = do not use."""
    if settings_path == "default":
        settings_path = default_settings_path()
    if game_dir == "default":
        game_dir = default_game_dir()
    if sql_files is None:
        sql_files = sorted(glob.glob(MOD_SQL_GLOB))
    text = Text(game_dir)
    actions, cats, gestures = {}, {}, []
    if game_dir:
        cfgs = [os.path.join(game_dir, "Base", "Assets", "Configuration", "Data", "InputConfiguration.xml")]
        for sub in ("Config", "Data"):   # Expansion1/2 and the scenarios (BlackDeathScenario defines LensPlague)
            cfgs += sorted(glob.glob(os.path.join(game_dir, "DLC", "*", sub, "*_Config.xml")))
        for c in cfgs:
            if os.path.isfile(c):
                a, g, ct = parse_config_xml(_read(c))
                for k, v in a.items():
                    actions.setdefault(k, v)
                gestures += g
                for k, v in ct.items():
                    cats.setdefault(k, v)
    for f in sql_files:
        a, g = parse_sql(_read(f))
        actions.update(a)
        gestures += g
    defaults = _kb_defaults(gestures)
    settings = load_settings(settings_path)
    result = []
    for aid in sorted(set(actions) | set(settings or {})):
        meta = actions.get(aid)
        if meta and meta["layout"].lower() == "console":
            continue
        if aid in (settings or {}):
            datas, source = settings[aid], "user"
        else:
            datas, source = defaults.get(aid, []), "default"
        if not meta and not any(datas):
            continue   # stored, but not a keyboard action we know (gamepad-only or removed)
        datas = [d for d in datas if d]
        name = text.get(meta["name"]) if meta else _humanize(aid)
        desc = text.get(meta["description"]) if meta else ""
        b = Binding(aid, name or _humanize(aid), desc or "", meta["category"] if meta else "", meta["layout"] if meta else "",
                    meta["context"] if meta else "", [gesture_to_civctl(d) for d in datas],
                    [" + ".join(text.get(t) for t in d.split("+")).replace(" + ", "+") for d in datas], source)
        result.append(b)
    flag_bindings(result)
    titles = {k: text.get(v).rstrip(":").strip() if v else k for k, v in cats.items()}
    return sorted(result, key=lambda b: (b.category, b.name.lower(), b.id)), titles


def flag_bindings(bindings):
    """Adds 'jaws', 'unsendable' (civctl cannot send it) and 'dup:<other actions>' to Binding.flags."""
    by_key = {}
    for b in bindings:
        for k in b.keys:
            by_key.setdefault(k, []).append(b)
    for b in bindings:
        for k in b.keys:
            if jaws_reserved(k):
                b.flags.append("jaws:" + k)
            if "?" in k.split("+"):
                b.flags.append("unsendable:" + k)
            others = sorted({o.id for o in by_key[k] if o is not b})
            if others:
                b.flags.append("dup:%s with %s" % (k, ",".join(others)))


def find(bindings, action):
    """Case-insensitive match on the action id (then on the display name)."""
    low = action.lower()
    for b in bindings:
        if b.id.lower() == low:
            return b
    for b in bindings:
        if b.name.lower() == low:
            return b
    return None


# ---- keymap.md ------------------------------------------------------------------------------------------------------

def render_keymap(bindings, titles, today, settings_path=None):
    shown = [b for b in bindings if b.category]   # actions with a category are on the Key Bindings tab
    out = ["# Civ VI key bindings (generated)", "",
           "Generated by `util\\civctl.cmd keymap` on %s from `InputSettings.json` (the user's bindings) plus the default gestures "
           "of the mod's `Database/*.sql` and the game's InputConfiguration (`util/keybindings.py`; no running game needed). "
           "Do not edit by hand; regenerate after rebinding keys or changing mod hotkeys (`Database/*.sql`)." % today, "",
           "\"civctl key\" is the argument for `util\\civctl.cmd key <arg>`; prefer `util\\civctl.cmd action <Action id>` in scripts "
           "(it looks the key up here, so a rebinding cannot break the script). These are in-game (World) hotkeys: they need a game "
           "in progress and no popup open. A blank key means unbound; `?` means civctl cannot send it yet (extend `_KEYS` in "
           "util/keybindings.py). Source: `user` = stored in InputSettings.json, `default` = not in the file yet (mod/game default)."]
    unbound = [b for b in shown if not b.keys]
    if unbound:
        out += ["", "**Unbound actions: %s**" % ", ".join(b.name for b in unbound)]
    jaws = [b for b in shown if any(f.startswith("jaws:") for f in b.flags)]
    if jaws:
        out += ["", "**Never send these (JAWS reserved keys; the harness refuses them): %s**" %
                ", ".join("%s = %s" % (b.id, ", ".join(k for k in b.keys if jaws_reserved(k))) for b in jaws)]
    dups = {}
    for b in shown:
        for k in b.keys:
            dups.setdefault(k, []).append(b.id)
    dups = {k: v for k, v in dups.items() if len(v) > 1}
    if dups:
        out += ["", "**Duplicate bindings (one key, several actions; the game may use only one of them): %s**" %
                "; ".join("%s: %s" % (k, ", ".join(v)) for k, v in sorted(dups.items()))]
    cats = []
    for b in shown:
        if b.category not in cats:
            cats.append(b.category)
    order = ["UNIT", "GLOBAL", "UI", "LENSES", "ONLINE", "UI_XP1", "UI_XP2"]
    cats.sort(key=lambda c: order.index(c) if c in order else len(order))
    for c in cats:
        out += ["", "## " + titles.get(c, c), "", "| Action | Action id | Key | civctl key | Alternate | Source | Description |",
                "|---|---|---|---|---|---|---|"]
        for b in shown:
            if b.category != c:
                continue
            disp = b.displays[0] if b.displays else ""
            mark = " (JAWS: never send)" if any(f.startswith("jaws:") for f in b.flags) else ""
            out.append("| %s | %s | %s | %s | %s | %s | %s |" % (
                b.name, b.id, disp, (b.key + mark) if b.key else "", b.alternate, b.source, b.description.replace("|", "/")))
    return "\n".join(out) + "\n"


def write_keymap(path=KEYMAP_MD, **kw):
    import datetime
    bindings, titles = load_bindings(**kw)
    md = render_keymap(bindings, titles, datetime.date.today().isoformat())
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(md)
    shown = [b for b in bindings if b.category]
    return path, len(shown), sum(1 for b in shown if not b.keys)


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("action", nargs="?")
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--key", metavar="ACTION", help="print only the civctl key of ACTION's primary binding")
    ap.add_argument("--write-keymap", nargs="?", const=KEYMAP_MD, metavar="PATH")
    ap.add_argument("--settings", default="default", help="InputSettings.json path (default: the user's)")
    ap.add_argument("--game-dir", default="default")
    a = ap.parse_args(argv)
    kw = dict(settings_path=a.settings or None, game_dir=a.game_dir or None)   # "" = do not use
    if a.write_keymap:
        path, n, unb = write_keymap(a.write_keymap, **kw)
        print("Wrote %s (%d actions, %d unbound)." % (path, n, unb))
        return 0
    bindings, _ = load_bindings(**kw)
    name = a.key or a.action
    if name:
        b = find(bindings, name)
        if not b:
            print("Unknown action '%s'. Known: %s" % (name, ", ".join(x.id for x in bindings if x.keys)))
            return 3
        if a.key:
            if not b.key:
                print("Action %s is unbound (set a key in the game's Key Bindings, or add a default in Database/*.sql)" % b.id)
                return 2
            print(b.key)
            return 0
        bindings = [b]
    if a.json:
        print(json.dumps([b.to_dict() for b in bindings], indent=2))
    else:
        for b in bindings:
            print("%-34s %-22s %-14s %s%s" % (b.id, b.key or "(unbound)", b.alternate, b.source,
                                              ("  [" + "; ".join(b.flags) + "]") if b.flags else ""))
    return 0


if __name__ == "__main__":
    sys.exit(main())
