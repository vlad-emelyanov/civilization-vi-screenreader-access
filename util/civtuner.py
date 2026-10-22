"""Minimal FireTuner client for Civilization VI: run Lua in any Lua state over TCP 127.0.0.1:4318.

Needs `EnableTuner 1` under [Debug] in AppOptions.txt (restart the game after changing it).
Only one tuner connection can exist at a time (do not run this while FireTuner2.exe is connected).

Usage:
  python util/civtuner.py states
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


async def send_message(writer, tag: int, payload: str) -> None:
    data = payload.encode("utf-8") + b"\x00"
    writer.write(struct.pack(HEADER_FMT, len(data), tag) + data)
    await writer.drain()


async def recv_message(reader) -> tuple[int, str]:
    length, tag = struct.unpack(HEADER_FMT, await reader.readexactly(HEADER_SIZE))
    data = await reader.readexactly(length)
    return tag, data.rstrip(b"\x00").decode("utf-8", errors="replace")


async def recv_timeout(reader, timeout: float):
    try:
        return await asyncio.wait_for(recv_message(reader), timeout=timeout)
    except asyncio.TimeoutError:
        return None


async def drain(reader, timeout: float = 0.3) -> None:
    while await recv_timeout(reader, timeout) is not None:
        pass


async def handshake(reader, writer) -> dict[int, str]:
    """Returns {state index: state name}."""
    await drain(reader, 0.3)
    await send_message(writer, TAG_HANDSHAKE, "APP:")
    await recv_timeout(reader, 5.0)
    await send_message(writer, TAG_HANDSHAKE, "LSQ:")
    msg = await recv_timeout(reader, 5.0)
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


async def run(state: str | None, code: str | None, timeout: float) -> int:
    try:
        reader, writer = await asyncio.wait_for(asyncio.open_connection(HOST, PORT), 5.0)
    except (OSError, asyncio.TimeoutError):
        print("Cannot connect to the tuner on 127.0.0.1:4318. Is the game running with EnableTuner 1?", file=sys.stderr)
        return 2
    try:
        states = await handshake(reader, writer)
        if code is None:
            for i, n in sorted(states.items()):
                print(f"{i}: {n}")
            return 0
        if state.isdigit():
            idx = int(state)
        else:
            idx = next((i for i, n in sorted(states.items()) if n == state), None)
            if idx is None:
                print(f"No Lua state named '{state}'. States: " + ", ".join(f"{i}:{n}" for i, n in sorted(states.items())), file=sys.stderr)
                return 2
        # The sentinel print marks the end of this chunk's output (a state that errors never prints it).
        await send_message(writer, TAG_COMMAND, f"CMD:{idx}:{code}\nprint('{SENTINEL}')")
        loop = asyncio.get_running_loop()
        deadline = loop.time() + timeout
        rc = 0
        while (remaining := deadline - loop.time()) > 0:
            msg = await recv_timeout(reader, min(remaining, 2.0))
            if msg is None:
                break
            if msg[1].startswith("ERR:"):
                print(msg[1])
                rc = 1
                break
            text = parse_output(msg[1])
            if text is None:
                continue
            if text.strip() == SENTINEL:
                break
            print(text)
        await drain(reader, 0.2)
        return rc
    finally:
        writer.close()


def main() -> int:
    a = sys.argv[1:]
    timeout = 8.0
    if not a or a[0] not in ("states", "lua"):
        print(__doc__)
        return 2
    if a[0] == "states":
        return asyncio.run(run(None, None, timeout))
    if len(a) >= 4 and a[1] == "-f":
        code, state = open(a[2], encoding="utf-8").read(), a[3]
    elif len(a) >= 3:
        state, code = a[1], a[2]
    else:
        print(__doc__)
        return 2
    return asyncio.run(run(state, code, timeout))


if __name__ == "__main__":
    sys.exit(main())
