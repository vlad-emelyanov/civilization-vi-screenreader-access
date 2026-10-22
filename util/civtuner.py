"""Minimal FireTuner client for Civilization VI: run Lua in any Lua state over TCP 127.0.0.1:4318.

Needs `EnableTuner 1` under [Debug] in AppOptions.txt (restart the game after changing it).
Only one tuner connection can exist at a time (do not run this while FireTuner2.exe is connected).

Usage:
  python util/civtuner.py states
  python util/civtuner.py menu       # is the in-game options menu / a popup open? (exit 4 if so)
  python util/civtuner.py lua <state name or index> "<lua code>"      e.g. lua InGame "print(Game.GetCurrentGameTurn())"
  python util/civtuner.py lua -f script.lua GameCore_Tuner

Protocol code (framing, handshake, CMD) adapted from civ6-mcp, src/civ_mcp/tuner_client.py and connection.py:

MIT License

Copyright (c) 2026 Liam Wilkinson

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
"""
from __future__ import annotations

import asyncio
import struct
import sys

HEADER_FMT = "<Ii"  # LE uint32 length, LE int32 tag
HEADER_SIZE = struct.calcsize(HEADER_FMT)
TAG_HANDSHAKE, TAG_COMMAND = 4, 3
HOST, PORT = "127.0.0.1", 4318
SENTINEL = "__CIVTUNER_DONE__"


class Conn:
    """Tuner connection. A background task reads whole messages into a queue, so a timeout while waiting can never
    cancel a read halfway through a message (that would desync the stream)."""

    def __init__(self, reader, writer):
        self.writer = writer
        self.queue: asyncio.Queue = asyncio.Queue()
        self.task = asyncio.ensure_future(self._pump(reader))

    async def _pump(self, reader) -> None:
        try:
            while True:
                length, tag = struct.unpack(HEADER_FMT, await reader.readexactly(HEADER_SIZE))
                data = await reader.readexactly(length)
                self.queue.put_nowait((tag, data.rstrip(b"\x00").decode("utf-8", errors="replace")))
        except (asyncio.IncompleteReadError, OSError, struct.error):
            pass
        self.queue.put_nowait(None)  # connection closed

    async def send(self, tag: int, payload: str) -> None:
        data = payload.encode("utf-8") + b"\x00"
        self.writer.write(struct.pack(HEADER_FMT, len(data), tag) + data)
        await self.writer.drain()

    async def recv(self, timeout: float):
        """Next (tag, text); None on timeout; raises ConnectionError when the game closed the connection."""
        try:
            msg = await asyncio.wait_for(self.queue.get(), timeout=timeout)
        except asyncio.TimeoutError:
            return None
        if msg is None:
            self.queue.put_nowait(None)
            raise ConnectionError("tuner connection closed")
        return msg

    async def drain(self, timeout: float = 0.3) -> None:
        while await self.recv(timeout) is not None:
            pass

    def close(self) -> None:
        self.task.cancel()
        self.writer.close()


async def handshake(conn: Conn) -> dict[int, str]:
    """Returns {state index: state name}."""
    await conn.drain(0.3)
    await conn.send(TAG_HANDSHAKE, "APP:")
    await conn.recv(5.0)
    await conn.send(TAG_HANDSHAKE, "LSQ:")
    msg = await conn.recv(5.0)
    raw = [s.strip() for s in (msg[1] if msg else "").split("\x00") if s.strip()]
    if len(raw) <= 1 and msg and "\n" in msg[1]:
        raw = [s.strip() for s in msg[1].split("\n") if s.strip()]
    states: dict[int, str] = {}
    i = 0
    while i + 1 < len(raw):  # alternating [index, name]
        try:
            states[int(raw[i])] = raw[i + 1]
            i += 2
        except ValueError:
            i += 1
    return states


def parse_output(payload: str) -> str | None:
    """print() output arrives as 'O\x00<context>: <value>'."""
    if not payload.startswith("O"):
        return None
    sep = payload.find(": ", 2)
    if sep >= 0:
        return payload[sep + 2:]
    return payload.lstrip("O").lstrip("\x00").strip()


async def execute(conn: Conn, idx: int, code: str, timeout: float) -> tuple[list[str], str | None]:
    """Runs a chunk; returns (printed lines, error text or None). Error 'no completion within Ns' when the end marker never came."""
    # The sentinel print marks the end of this chunk's output (a state that errors never prints it).
    await conn.send(TAG_COMMAND, f"CMD:{idx}:{code}\nprint('{SENTINEL}')")
    loop = asyncio.get_running_loop()
    deadline = loop.time() + timeout
    lines: list[str] = []
    while (remaining := deadline - loop.time()) > 0:
        msg = await conn.recv(min(remaining, 2.0))
        if msg is None:
            continue
        if msg[1].startswith("ERR:"):
            return lines, msg[1]
        text = parse_output(msg[1])
        if text is None:
            continue
        if text.strip() == SENTINEL:
            await conn.drain(0.2)
            return lines, None
        lines.append(text)
    return lines, f"ERR: no completion within {timeout:g}s"


async def run(state: str | None, code: str | None, timeout: float, collect: list | None = None) -> int:
    try:
        reader, writer = await asyncio.wait_for(asyncio.open_connection(HOST, PORT), 5.0)
    except (OSError, asyncio.TimeoutError):
        print("Cannot connect to the tuner on 127.0.0.1:4318. Is the game running with EnableTuner 1?", file=sys.stderr)
        return 2
    conn = Conn(reader, writer)
    try:
        states = await handshake(conn)
        if not states:
            print("No Lua states returned: FireTuner busy (another client connected?) or not enabled (EnableTuner 1 in AppOptions.txt, then restart the game).", file=sys.stderr)
            return 2
        if code is None:
            for i, n in sorted(states.items()):
                print(f"{i}: {n}")
            return 0
        if state.isdigit():
            idx = int(state)
            if idx not in states:
                print(f"No Lua state with index {idx}. States: " + ", ".join(f"{i}:{n}" for i, n in sorted(states.items())), file=sys.stderr)
                return 2
        else:
            idx = next((i for i, n in sorted(states.items()) if n == state), None)
            if idx is None:
                print(f"No Lua state named '{state}'. States: " + ", ".join(f"{i}:{n}" for i, n in sorted(states.items())), file=sys.stderr)
                return 2
        # REPL behaviour: if the chunk is a single expression, print its value. Not an expression -> syntax error, nothing ran.
        lines, err = await execute(conn, idx, f"local __v = ({code}\n)\nif __v ~= nil then print(tostring(__v)) end", timeout)
        if err is not None and is_syntax_error(err) and not lines:
            # Statements: run as a function body, so `return x` works and its value is printed too.
            lines, err = await execute(conn, idx, "\n".join(["local __v = (function()", code, "end)()", "if __v ~= nil then print(tostring(__v)) end"]), timeout)
        for l in lines:
            if collect is not None:
                collect.append(l)
            else:
                print(l)
        if err is not None:
            print(err)
            return 1
        return 0
    except ConnectionError as e:
        print(f"ERR: {e}", file=sys.stderr)
        return 1
    finally:
        conn.close()


# Is the in-game options menu or a popup/screen open? (Escape with nothing open opens the options menu.)
MENU_LUA = '''
local lines = {}
local top = ContextPtr:LookUpControl("/InGame/TopOptionsMenu")
table.insert(lines, (top and not top:IsHidden()) and "MENU: OPEN (in-game options menu; Escape closes it)" or "MENU: closed")
local always = { TopPanel = true, DiplomacyRibbon = true, PartialScreenHooks = true, InGameAccess = true }
local open = {}
for _, name in ipairs({"WorldPopups", "FakePopups", "Screens", "PartialScreens", "Diplomacy", "EndGame", "AdditionalUserInterfaces"}) do
  local c = ContextPtr:LookUpControl("/InGame/" .. name)
  if c then
    for _, k in ipairs(c:GetChildren()) do
      if not k:IsHidden() and not always[k:GetID()] then table.insert(open, name .. "/" .. k:GetID()) end
    end
  end
end
local pedia = ContextPtr:LookUpControl("/InGame/Civilopedia")
if pedia and not pedia:IsHidden() then table.insert(open, "Civilopedia") end
table.insert(lines, #open > 0 and ("POPUP/SCREEN OPEN: " .. table.concat(open, ", ")) or "no popup or screen open")
return table.concat(lines, "|")
'''


def is_syntax_error(err: str) -> bool:
    return err.startswith("ERR:Syntax Error") or err.startswith("ERR: Syntax Error")


def main() -> int:
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
        sys.stderr.reconfigure(encoding="utf-8", errors="replace")
    except AttributeError:
        pass
    a = sys.argv[1:]
    timeout = 8.0
    if not a or a[0] not in ("states", "lua", "menu"):
        print(__doc__)
        return 2
    if a[0] == "menu":
        out: list[str] = []
        rc = asyncio.run(run("InGame", MENU_LUA, timeout, out))
        if rc == 0:
            parts = "|".join(out).split("|")
            print("\n".join(parts))
            return 4 if any(l.startswith(("MENU: OPEN", "POPUP")) for l in parts) else 0
        return rc
    if a[0] == "states":
        return asyncio.run(run(None, None, timeout))
    if len(a) >= 4 and a[1] == "-f":
        code, state = open(a[2], encoding="utf-8-sig").read(), a[3]
    elif len(a) >= 3:
        state, code = a[1], a[2]
    else:
        print(__doc__)
        return 2
    return asyncio.run(run(state, code, timeout))


if __name__ == "__main__":
    sys.exit(main())
