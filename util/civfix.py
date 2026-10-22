"""Fixture helpers for civctl (stdlib only).

  python util/civfix.py sidecar <fixtures dir> <name> --turn N --civ X --profile P --purpose "..." --commit H
  python util/civfix.py fixtures <fixtures dir>
"""
from __future__ import annotations

import argparse
import datetime
import sys
from pathlib import Path


def sidecar(a) -> int:
    d = Path(a.dir)
    d.mkdir(parents=True, exist_ok=True)
    save = d / f"{a.name}.Civ6Save"
    lines = [
        f"turn: {a.turn}",
        f"civ: {a.civ}",
        f"profile: {a.profile or '-'}",
        f"purpose: {a.purpose or '-'}",
        f"mod commit: {a.commit}",
        f"created: {datetime.date.today().isoformat()}",
        f"size: {save.stat().st_size // 1024} KB" if save.exists() else "size: ?",
    ]
    (d / f"{a.name}.txt").write_text("\n".join(lines) + "\n", encoding="utf-8")
    return 0


def fixtures(a) -> int:
    d = Path(a.dir)
    saves = sorted(d.glob("*.Civ6Save")) if d.exists() else []
    if not saves:
        print(f"No fixtures in {d}")
        return 0
    for s in saves:
        info = {}
        side = s.with_suffix(".txt")
        if side.exists():
            for line in side.read_text(encoding="utf-8").splitlines():
                k, _, v = line.partition(": ")
                info[k] = v
        print(f"{s.stem}: turn {info.get('turn', '?')}, {info.get('civ', '?')}, profile {info.get('profile', '-')}, "
              f"{s.stat().st_size // 1024} KB, commit {info.get('mod commit', '?')}, {info.get('created', '?')}")
        if info.get("purpose", "-") != "-":
            print(f"    {info['purpose']}")
    return 0


def main() -> int:
    p = argparse.ArgumentParser()
    sub = p.add_subparsers(dest="cmd", required=True)
    s = sub.add_parser("sidecar")
    s.add_argument("dir"); s.add_argument("name")
    s.add_argument("--turn", default="?"); s.add_argument("--civ", default="?"); s.add_argument("--profile", default="")
    s.add_argument("--purpose", default=""); s.add_argument("--commit", default="?")
    s.set_defaults(fn=sidecar)
    f = sub.add_parser("fixtures"); f.add_argument("dir"); f.set_defaults(fn=fixtures)
    a = p.parse_args()
    return a.fn(a)


if __name__ == "__main__":
    sys.exit(main())
