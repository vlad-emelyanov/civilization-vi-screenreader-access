#!/usr/bin/env python
"""Test-friendly game options for regression runs and setup commands (advance/autoplay), restoring the user's own afterwards.

  python util/testopts.py on        save the current values (ONLY if no backup exists yet), then set the test values
  python util/testopts.py restore   write the backed-up values back and delete the backup
  python util/testopts.py status [--json]   current values, test values, whether a backup exists

Test values (TESTOPTS below): advisor disabled (TutorialLevel -1), QuickCombat 1, QuickMovement 1, no camera look-at on combat,
no historic moment animation. The user's real values are never hard-coded: `on` reads them first.

Backup: %TEMP%\\civctl\\testopts-backup.json. `on` never overwrites an existing backup, so a crashed run (still on test values)
followed by another `on` cannot lose the real values. MANUAL RECOVERY after a crash or a killed run:  python util/testopts.py restore

Mechanism: game running (CivilizationVI*.exe process) -> tuner Lua (LUA_READ / LUA_WRITE below, in the first state of LUA_STATES that
answers); game not running -> edit UserOptions.txt in place (only the value token of the `Key value` line, so comments, line endings
and encoding stay; keys are looked up file-wide, the file has duplicate section headers).
"""
import json
import os
import re
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
USER_OPTIONS = os.path.join(os.environ.get("LOCALAPPDATA", ""), "Firaxis Games", "Sid Meier's Civilization VI", "UserOptions.txt")
BACKUP = os.path.join(tempfile.gettempdir(), "civctl", "testopts-backup.json")

# (key, Options.lua section, test value, UserConfiguration name to apply live or None)
TESTOPTS = [
    ("TutorialLevel", "Gameplay", "-1", "TutorialLevel"),
    ("QuickCombat", "Gameplay", "1", "QuickCombat"),
    ("QuickMovement", "Gameplay", "1", "QuickMovement"),
    ("LookAtPlayerTurnCombat", "Gameplay", "0", None),
    ("LookAtPlayerOffTurnCombat", "Gameplay", "0", None),
    ("PlayHistoricMomentAnimation", "Interface", "0", None),
]
KEYS = [k for k, _, _, _ in TESTOPTS]
TEST_VALUES = {k: v for k, _, v, _ in TESTOPTS}

# Tuner side. States are tried in order until one answers (the verifier reports which one has the Options table).
LUA_STATES = ("InGame", "MainMenu")
LUA_READ_LINE = 'print("TESTOPT {key} " .. tostring(Options.GetUserOption("{section}", "{key}")))'
LUA_WRITE_LINE = 'Options.SetUserOption("{section}", "{key}", {value})'
LUA_APPLY_LINE = 'UserConfiguration.SetValue("{config}", {value})'
LUA_SAVE = "Options.SaveUserOptions()"
GAME_PROCESS = re.compile(r"CivilizationVI", re.I)


def _section(key):
    return next(s for k, s, _, _ in TESTOPTS if k == key)


def _config(key):
    return next(c for k, _, _, c in TESTOPTS if k == key)


def lua_read():
    return "\n".join(LUA_READ_LINE.format(key=k, section=s) for k, s, _, _ in TESTOPTS)


def lua_write(values):
    lines = []
    for k, v in values.items():
        lines.append(LUA_WRITE_LINE.format(section=_section(k), key=k, value=v))
        if _config(k):
            lines.append(LUA_APPLY_LINE.format(config=_config(k), value=v))
    lines.append(LUA_SAVE)
    return "\n".join(lines)


# ---- file path -------------------------------------------------------------------------------------------------------

def _read_text(path):
    with open(path, "rb") as f:
        return f.read().decode("latin-1")   # byte-transparent: written back as latin-1 unchanged


def file_values(path=None):
    text = _read_text(path or USER_OPTIONS)
    out = {}
    for k in KEYS:
        m = re.search(r"^" + re.escape(k) + r"[ \t]+(\S+)", text, re.M)
        if m:
            out[k] = m.group(1)
    return out


def file_write(values, path=None):
    path = path or USER_OPTIONS
    text = _read_text(path)
    for k, v in values.items():
        text, n = re.subn(r"^(" + re.escape(k) + r"[ \t]+)\S+", lambda m: m.group(1) + str(v), text, count=1, flags=re.M)
        if not n:
            raise RuntimeError("%s has no '%s' line (start the game once, or add it)" % (os.path.basename(path), k))
    with open(path, "wb") as f:
        f.write(text.encode("latin-1"))


# ---- tuner path ------------------------------------------------------------------------------------------------------

def game_running():
    try:
        out = subprocess.run(["tasklist", "/FO", "CSV", "/NH"], capture_output=True, text=True, timeout=20).stdout
    except (OSError, subprocess.SubprocessError):
        return False
    return any(GAME_PROCESS.search(l.split(",")[0]) for l in out.splitlines())


def tuner_run(code):
    """Runs Lua in the first LUA_STATES state that answers. Returns the printed lines; raises RuntimeError if none did."""
    import asyncio
    sys.path.insert(0, HERE)
    import civtuner
    last = None
    for state in LUA_STATES:
        out = []
        rc = asyncio.run(civtuner.run(state, code, 8.0, out, quiet_missing_state=True))
        if rc == 0:
            return out
        last = "%s: tuner rc %d %s" % (state, rc, " ".join(out[-2:]))
    raise RuntimeError("tuner Lua failed (%s)" % last)


def tuner_values():
    out = {}
    for l in tuner_run(lua_read()):
        m = re.match(r"TESTOPT (\S+) (\S+)", l.strip())
        if m:
            out[m.group(1)] = _num(m.group(2))
    return out


def _num(s):
    try:
        f = float(s)
        return str(int(f)) if f == int(f) else s
    except ValueError:
        return s


# ---- commands --------------------------------------------------------------------------------------------------------

def read_values(running=None):
    running = game_running() if running is None else running
    return tuner_values() if running else file_values()


def write_values(values, running=None):
    running = game_running() if running is None else running
    if running:
        tuner_run(lua_write(values))
    else:
        file_write(values)


def read_backup():
    try:
        with open(BACKUP, encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return None


def cmd_on(out=print):
    running = game_running()
    cur = read_values(running)
    if read_backup() is None:
        os.makedirs(os.path.dirname(BACKUP), exist_ok=True)
        with open(BACKUP, "w", encoding="utf-8") as f:
            json.dump(cur, f, indent=1)
        out("testopts: saved the real values %s -> %s" % (cur, BACKUP))
    else:
        out("testopts: backup already exists (kept; real values are in it)")
    write_values(TEST_VALUES, running)
    out("testopts: test values set (%s)" % ("tuner" if running else "UserOptions.txt"))
    return 0


def cmd_restore(out=print):
    backup = read_backup()
    if backup is None:
        out("testopts: no backup, nothing to restore")
        return 0
    write_values(backup)   # re-detects: the game may have crashed since `on`
    os.remove(BACKUP)
    out("testopts: restored %s" % backup)
    return 0


ANIMATION_KEYS = ("QuickCombat", "QuickMovement", "LookAtPlayerTurnCombat", "LookAtPlayerOffTurnCombat", "PlayHistoricMomentAnimation")
ADVISOR_KEYS = ("TutorialLevel",)
GROUP_KEYS = {"animations": ANIMATION_KEYS, "advisor": ADVISOR_KEYS}


def switch(groups=()):
    """Per-script opt-out: the option groups in `groups` ('animations', 'advisor') get the user's real values (from the backup),
    all others the test values. switch(()) = all test values again. Needs the backup (`on` ran)."""
    backup = read_backup()
    if backup is None:
        raise RuntimeError("no testopts backup: run `testopts.py on` first")
    values = dict(TEST_VALUES)
    for g in groups:
        for k in GROUP_KEYS[g]:
            if k in backup:
                values[k] = backup[k]
    write_values(values)


def cmd_status(as_json=False, out=print):
    running = game_running()
    cur = read_values(running)
    info = {"game_running": running, "current": cur, "test": TEST_VALUES, "backup": read_backup(),
            "is_test": all(cur.get(k) == v for k, v in TEST_VALUES.items())}
    out(json.dumps(info) if as_json else "\n".join("%s: %s" % (k, v) for k, v in info.items()))
    return 0


def main(argv=None):
    a = list(sys.argv[1:] if argv is None else argv)
    if not a or a[0] not in ("on", "restore", "status"):
        print(__doc__)
        return 2
    try:
        if a[0] == "on":
            return cmd_on()
        if a[0] == "restore":
            return cmd_restore()
        return cmd_status("--json" in a)
    except (RuntimeError, OSError) as e:
        print("testopts: ERROR %s" % e, file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
