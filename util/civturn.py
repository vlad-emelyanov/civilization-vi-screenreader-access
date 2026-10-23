#!/usr/bin/env python
"""End-turn and turn-wait helpers for civctl (talks to the game through the FireTuner, see civtuner.py).

  python util/civturn.py endturn          request the end of the local player's turn (what the End Turn button does when nothing blocks)
  python util/civturn.py advance-check <before> <n> <after>
                                          exit 0 if the game advanced by exactly n turns (used by `civctl advance`)
  python util/civturn.py poll <N>         one look at the game: exit 0 = it is turn N and the local player's turn is active,
                                          10 = keep waiting, 11 = waiting and a popup/screen is open (AI-turn popups), 1 = the game is
                                          already past turn N / error, 2 = tuner unreachable. Prints one status line.

`civctl endturn` / `civctl wait-turn <N>` / `civctl advance <n>` wrap these (the wait loop, the SR> lines and the lock lease live in civctl.ps1).

endturn is for SETUP and VERIFICATION only (getting to a turn that has a situation you test). A play-test must end turns with Enter
like a player, because that exercises what a blind player hears (the End Turn button, blockers, "Turn N" announcements).

`civctl advance <n>` (SETUP/VERIFICATION only, play-tests never use it) lets the game's own autoplay AI play our civ for exactly n
turns: the AI resolves every blocker itself (production, research, civics, envoy tokens, commemorations, escape routes, units), then
control comes back and civctl checks that the turn counter moved by n. Nothing here fabricates operation parameters.

endturn mirrors ActionPanel.lua DoEndTurn: it refuses while an end-turn blocker is pending (units need orders, research, production,
...) and says which one; it never selects units or opens the blocker's screen. When the turn was already ended it says so.
"""
from __future__ import annotations

import asyncio
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))  # python -I does not add the script directory

STATE = "InGame"

ENDTURN_LUA = '''
local pid = Game.GetLocalPlayer()
local p = (pid ~= nil and pid >= 0) and Players[pid] or nil
if p == nil then return "NOPLAYER" end
if not p:IsTurnActive() then return "NOTACTIVE turn=" .. Game.GetCurrentGameTurn() end
if UI.HasSentTurnComplete() then return "ALREADY turn=" .. Game.GetCurrentGameTurn() end
local b = NotificationManager.GetFirstEndTurnBlocking(pid)
if b ~= EndTurnBlockingTypes.NO_ENDTURN_BLOCKING then
  local name = tostring(b)
  for k, v in pairs(EndTurnBlockingTypes) do if v == b then name = k end end
  local tags = {
    ENDTURN_BLOCKING_UNITS = "LOC_ACTION_PANEL_NEEDS_ORDERS", ENDTURN_BLOCKING_UNIT_NEEDS_ORDERS = "LOC_ACTION_PANEL_NEEDS_ORDERS",
    ENDTURN_BLOCKING_STACKED_UNITS = "LOC_ACTION_PANEL_STACKED_UNIT", ENDTURN_BLOCKING_RESEARCH = "LOC_ACTION_PANEL_NEEDS_RESEARCH",
    ENDTURN_BLOCKING_CIVIC = "LOC_ACTION_PANEL_NEEDS_CIVIC", ENDTURN_BLOCKING_FILL_CIVIC_SLOT = "LOC_ACTION_PANEL_FILL_CIVIC_SLOT",
    ENDTURN_BLOCKING_CONSIDER_GOVERNMENT_CHANGE = "LOC_ACTION_PANEL_CONSIDER_GOVERNMENT_CHANGE",
    ENDTURN_BLOCKING_CONSIDER_RAZE_CITY = "LOC_ACTION_PANEL_CONSIDER_RAZE_CITY", ENDTURN_BLOCKING_PRODUCTION = "LOC_ACTION_PANEL_NEEDS_PRODUCTION",
    ENDTURN_BLOCKING_PANTHEON = "LOC_ACTION_PANEL_NEEDS_PANTHEON", ENDTURN_BLOCKING_RELIGION = "LOC_ACTION_PANEL_NEEDS_RELIGION",
    ENDTURN_BLOCKING_BELIEF = "LOC_ACTION_PANEL_NEEDS_BELIEF", ENDTURN_BLOCKING_GIVE_INFLUENCE_TOKEN = "LOC_ACTION_PANEL_GIVE_INFLUENCE_TOKEN",
    ENDTURN_BLOCKING_CLAIM_GREAT_PERSON = "LOC_ACTION_PANEL_CLAIM_GREAT_PERSON", ENDTURN_BLOCKING_SPY_CHOOSE_ESCAPE_ROUTE = "LOC_ACTION_PANEL_CHOOSE_ESCAPE_ROUTE",
    ENDTURN_BLOCKING_SPY_CHOOSE_DRAGNET_PRIORITY = "LOC_ACTION_PANEL_CHOOSE_DRAGNET_PRIORITY", ENDTURN_BLOCKING_ARTIFACT = "LOC_ACTION_PANEL_CHOOSE_ARTIFACT_PLAYER",
    ENDTURN_BLOCKING_GOVERNOR_APPOINTMENT = "LOC_ACTION_PANEL_GOVERNOR_APPOINTMENT", ENDTURN_BLOCKING_GOVERNOR_OPPORTUNITY = "LOC_ACTION_PANEL_GOVERNOR_OPPORTUNITY",
    ENDTURN_BLOCKING_GOVERNOR_PROMOTION = "LOC_ACTION_PANEL_GOVERNOR_PROMOTION", ENDTURN_BLOCKING_GOVERNOR_IDLE = "LOC_ACTION_PANEL_GOVERNOR_IDLE",
    ENDTURN_BLOCKING_CONSIDER_DISLOYAL_CITY = "LOC_ACTION_PANEL_CONSIDER_DISLOYAL_CITY",
    ENDTURN_BLOCKING_EMERGENCY_NEEDS_ATTENTION = "LOC_NOTIFICATION_EMERGENCY_NEEDS_ATTENTION_MESSAGE",
    ENDTURN_BLOCKING_COMMEMORATION_AVAILABLE = "LOC_NOTIFICATION_COMMEMORATION_AVAILABLE_MESSAGE",
    ENDTURN_BLOCKING_WORLD_CONGRESS_LOOK = "LOC_ACTION_PANEL_WORLD_CONGRESS_SPECIAL_SESSION", ENDTURN_BLOCKING_WORLD_CONGRESS_SESSION = "LOC_RESUME_CONGRESS",
  }
  local text = tags[name] and Locale.Lookup(tags[name]) or ""
  return "BLOCKED " .. name .. " | " .. text
end
if not UI.CanEndTurn() then return "BLOCKED CanEndTurn=false" end
UI.RequestAction(ActionTypes.ACTION_ENDTURN)
return "REQUESTED turn=" .. Game.GetCurrentGameTurn()
'''

# One line: TURN <n> active=<bool> sent=<bool> popups=<a,b|->
POLL_LUA = '''
local pid = Game.GetLocalPlayer()
local p = (pid ~= nil and pid >= 0) and Players[pid] or nil
local active = p ~= nil and p:IsTurnActive()
local sent = false
pcall(function() sent = UI.HasSentTurnComplete() end)
local always = { TopPanel = true, DiplomacyRibbon = true, PartialScreenHooks = true, InGameAccess = true }
local open = {}
for _, name in ipairs({"WorldPopups", "FakePopups", "Screens", "PartialScreens", "Diplomacy", "EndGame"}) do
  local c = ContextPtr:LookUpControl("/InGame/" .. name)
  if c then
    for _, k in ipairs(c:GetChildren()) do
      if not k:IsHidden() and not always[k:GetID()] then table.insert(open, k:GetID()) end
    end
  end
end
return "TURN " .. Game.GetCurrentGameTurn() .. " active=" .. tostring(active) .. " sent=" .. tostring(sent) .. " popups=" .. (#open > 0 and table.concat(open, ",") or "-")
'''

POLL_RE = re.compile(r"TURN (\d+) active=(true|false) sent=(true|false) popups=(\S+)")


def parse_poll(text):
    """Tuner output -> dict(turn, active, sent, popups[list]) or None."""
    m = POLL_RE.search(text or "")
    if not m:
        return None
    return {"turn": int(m.group(1)), "active": m.group(2) == "true", "sent": m.group(3) == "true",
            "popups": [] if m.group(4) == "-" else m.group(4).split(",")}


def judge(info, target):
    """(exit code, message) for one poll against the wanted turn."""
    if info is None:
        return 2, "game state unreadable"
    t = info["turn"]
    if t > target:
        return 1, "the game is already at turn %d (past %d)" % (t, target)
    if t == target and info["active"]:
        return 0, "turn %d, your turn is active" % t
    why = "turn %d, waiting for turn %d" % (t, target) if t < target else "turn %d reached, your turn is not active yet" % t
    if info["popups"]:
        return 11, "%s; open: %s (not pressing keys: look at the SR> lines and close it yourself)" % (why, ", ".join(info["popups"]))
    return 10, why


# English ActionPanel labels (the text the End Turn button shows), used when the game gave no localized text.
BLOCKER_TEXT = {
    "ENDTURN_BLOCKING_UNITS": "Unit needs orders", "ENDTURN_BLOCKING_UNIT_NEEDS_ORDERS": "Unit needs orders",
    "ENDTURN_BLOCKING_STACKED_UNITS": "Move stacked unit", "ENDTURN_BLOCKING_RESEARCH": "Choose research",
    "ENDTURN_BLOCKING_CIVIC": "Choose civic", "ENDTURN_BLOCKING_FILL_CIVIC_SLOT": "Fill civic slot",
    "ENDTURN_BLOCKING_CONSIDER_GOVERNMENT_CHANGE": "Consider changing government",
    "ENDTURN_BLOCKING_CONSIDER_RAZE_CITY": "Consider razing city", "ENDTURN_BLOCKING_PRODUCTION": "Choose production",
    "ENDTURN_BLOCKING_PANTHEON": "Choose pantheon", "ENDTURN_BLOCKING_RELIGION": "Choose religion",
    "ENDTURN_BLOCKING_BELIEF": "Choose belief", "ENDTURN_BLOCKING_GIVE_INFLUENCE_TOKEN": "Give envoy tokens",
    "ENDTURN_BLOCKING_CLAIM_GREAT_PERSON": "Claim great person", "ENDTURN_BLOCKING_SPY_CHOOSE_ESCAPE_ROUTE": "Choose escape route",
    "ENDTURN_BLOCKING_SPY_CHOOSE_DRAGNET_PRIORITY": "Choose dragnet priority", "ENDTURN_BLOCKING_ARTIFACT": "Choose artifact player",
    "ENDTURN_BLOCKING_GOVERNOR_APPOINTMENT": "Governor appointment available", "ENDTURN_BLOCKING_GOVERNOR_OPPORTUNITY": "Governor opportunity",
    "ENDTURN_BLOCKING_GOVERNOR_PROMOTION": "Governor promotion available", "ENDTURN_BLOCKING_GOVERNOR_IDLE": "Governor idle",
    "ENDTURN_BLOCKING_CONSIDER_DISLOYAL_CITY": "Consider disloyal city", "ENDTURN_BLOCKING_EMERGENCY_NEEDS_ATTENTION": "Emergency needs attention",
    "ENDTURN_BLOCKING_COMMEMORATION_AVAILABLE": "Commemoration available", "ENDTURN_BLOCKING_WORLD_CONGRESS_LOOK": "World Congress special session",
    "ENDTURN_BLOCKING_WORLD_CONGRESS_SESSION": "Resume Congress",
}


def blocker_text(name, localized=""):
    """Human text of an end-turn blocker: the game's own label if given, else the English table, else the enum name."""
    return (localized or "").strip() or BLOCKER_TEXT.get(name, name)


def describe_endturn(text):
    """Tuner output of ENDTURN_LUA -> (exit code, message)."""
    t = (text or "").strip()
    if t.startswith("REQUESTED"):
        return 0, "End turn requested (%s)." % t.partition(" ")[2]
    if t.startswith("ALREADY"):
        return 0, "The end of this turn was already requested (%s)." % t.partition(" ")[2]
    if t.startswith("BLOCKED"):
        name, _, localized = t.partition(" ")[2].partition("|")
        name = name.strip()
        return 1, ("Cannot end the turn: \"%s\" (%s) is pending. Clear it first (give the unit orders, choose research/production, ...); "
                   "or press Enter in the game like a player." % (blocker_text(name, localized), name))
    if t.startswith("NOTACTIVE"):
        return 1, "Your turn is not active (%s): the AI is still playing or the turn already ended." % t.partition(" ")[2]
    if t.startswith("NOPLAYER"):
        return 1, "No local player (autoplay or front end)."
    return 1, "Unexpected answer: %r" % t


def check_advance(before, n, after):
    """`civctl advance`: (exit code, message) for the turn counter before/after n autoplayed turns."""
    if after == before + n:
        return 0, "advanced %d turn%s: %d -> %d" % (n, "" if n == 1 else "s", before, after)
    return 1, "advance FAILED: expected turn %d (%d + %d), the game is at turn %d" % (before + n, before, n, after)


def tuner(code, timeout=8.0):
    import civtuner
    out = []
    rc = asyncio.run(civtuner.run(STATE, code, timeout, out))
    return rc, "\n".join(out)


def main(argv=None):
    a = list(sys.argv[1:] if argv is None else argv)
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except AttributeError:
        pass
    if a[:1] == ["endturn"]:
        rc, text = tuner(ENDTURN_LUA)
        if rc != 0:
            print(text or "tuner error")
            return 2 if rc == 2 else 1
        code, msg = describe_endturn(text)
        print(msg)
        return code
    if len(a) == 4 and a[0] == "advance-check" and all(x.isdigit() for x in a[1:]):
        code, msg = check_advance(int(a[1]), int(a[2]), int(a[3]))
        print(msg)
        return code
    if len(a) == 2 and a[0] == "poll" and a[1].isdigit():
        rc, text = tuner(POLL_LUA)
        if rc != 0:
            print("tuner unreachable or busy: %s" % (text or rc))
            return 2
        code, msg = judge(parse_poll(text), int(a[1]))
        print(msg)
        return code
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main())
