#!/usr/bin/env python
"""End-turn and turn-wait helpers for civctl (talks to the game through the FireTuner, see civtuner.py).

  python util/civturn.py endturn          request the end of the local player's turn (what the End Turn button does when nothing blocks)
  python util/civturn.py poll <N>         one look at the game: exit 0 = it is turn N and the local player's turn is active,
                                          10 = keep waiting, 11 = waiting and a popup/screen is open (AI-turn popups), 1 = the game is
                                          already past turn N / error, 2 = tuner unreachable. Prints one status line.

`civctl endturn` / `civctl wait-turn <N>` wrap these (the wait loop, the SR> lines and the lock lease live in civctl.ps1).

endturn is for SETUP and VERIFICATION only (getting to a turn that has a situation you test). A play-test must end turns with Enter
like a player, because that exercises what a blind player hears (the End Turn button, blockers, "Turn N" announcements).

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
  return "BLOCKED " .. name
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


def describe_endturn(text):
    """Tuner output of ENDTURN_LUA -> (exit code, message)."""
    t = (text or "").strip()
    if t.startswith("REQUESTED"):
        return 0, "End turn requested (%s)." % t.partition(" ")[2]
    if t.startswith("ALREADY"):
        return 0, "The end of this turn was already requested (%s)." % t.partition(" ")[2]
    if t.startswith("BLOCKED"):
        return 1, ("Cannot end the turn: %s is pending. Clear it first (units need orders, choose research/production, ...); "
                   "or press Enter in the game like a player." % t.partition(" ")[2])
    if t.startswith("NOTACTIVE"):
        return 1, "Your turn is not active (%s): the AI is still playing or the turn already ended." % t.partition(" ")[2]
    if t.startswith("NOPLAYER"):
        return 1, "No local player (autoplay or front end)."
    return 1, "Unexpected answer: %r" % t


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
