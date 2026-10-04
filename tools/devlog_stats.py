#!/usr/bin/env python3
"""Vypíše metriky aktuální AI relace pro deník hry Stone & Clay.

Claude Code: sečte usage z nejnovějšího přepisu relace v
~/.claude/projects/<escaped-cwd>*/  (tokeny = input + output + cache).
Devin CLI:   přečte poslední relaci pro tento adresář z
~/.local/share/devin/cli/sessions.db  (tokeny lokálně nejsou — jen
doba, model a ACU/credit náklady).

Použití:
  python3 tools/devlog_stats.py --agent claude
  python3 tools/devlog_stats.py --agent devin
"""
from __future__ import annotations

import argparse
import glob
import json
import os
import sqlite3
import sys
from datetime import datetime
from pathlib import Path

HOME = Path.home()
CLAUDE_PROJECTS = HOME / ".claude" / "projects"
DEVIN_DB = HOME / ".local" / "share" / "devin" / "cli" / "sessions.db"


def esc_dir(p: str) -> str:
    """Název projektové složky Claude Code pro daný cwd."""
    return p.replace("/", "-").replace("_", "-").replace(" ", "-")


def claude_stats(cwd: str) -> dict | None:
    """Nejnovější relace (dle poslední zprávy) v adresářích odpovídajících cwd."""
    esc = esc_dir(cwd)
    # cwd i nadřazené adresáře (agent může běžet v  i v kořeni)
    candidates = set()
    parts = cwd.split("/")
    for i in range(1, len(parts) + 1):
        candidates.add(esc_dir("/".join(parts[:i])))
    files = []
    for d in CLAUDE_PROJECTS.iterdir() if CLAUDE_PROJECTS.is_dir() else []:
        if d.is_dir() and any(d.name == c or d.name.startswith(c + "-") or c.startswith(d.name + "-") for c in candidates):
            files.extend(d.glob("*.jsonl"))
    best = None
    for f in files:
        t_in = t_out = t_cr = t_rd = 0
        t0 = t1 = None
        model = None
        nmsg = 0
        try:
            fh = open(f, encoding="utf-8", errors="replace")
        except OSError:
            continue
        for line in fh:
            try:
                rec = json.loads(line)
            except ValueError:
                continue
            ts = rec.get("timestamp")
            if ts:
                try:
                    t = datetime.fromisoformat(ts.replace("Z", "+00:00"))
                    t0 = t0 or t
                    t1 = t
                except ValueError:
                    pass
            m = rec.get("message")
            if isinstance(m, dict) and isinstance(m.get("usage"), dict):
                u = m["usage"]
                nmsg += 1
                t_in += u.get("input_tokens", 0)
                t_out += u.get("output_tokens", 0)
                t_cr += u.get("cache_creation_input_tokens", 0)
                t_rd += u.get("cache_read_input_tokens", 0)
                mm = m.get("model")
                if mm and mm != "<synthetic>":
                    model = mm
        fh.close()
        if nmsg and t1 and (best is None or t1 > best["t1"]):
            best = {"f": f, "t0": t0, "t1": t1, "model": model,
                    "tokens": t_in + t_out + t_cr + t_rd, "nmsg": nmsg}
    if not best:
        return None
    return {
        "minutes": max(0, int((best["t1"] - best["t0"]).total_seconds() // 60)),
        "tokens": best["tokens"],
        "model": best["model"] or "",
        "detail": f"session {best['f'].stem}, {best['nmsg']} zpráv s usage",
    }


def devin_stats(cwd: str) -> dict | None:
    """Poslední Devin relace pro tento adresář (created_at/last_activity_at, ACU)."""
    if not DEVIN_DB.is_file():
        return None
    try:
        con = sqlite3.connect(f"file:{DEVIN_DB}?mode=ro", uri=True)
        row = con.execute(
            "SELECT model, created_at, last_activity_at, metadata FROM sessions "
            "WHERE ? LIKE working_directory || '%' ORDER BY last_activity_at DESC LIMIT 1",
            (cwd,),
        ).fetchone()
        con.close()
    except sqlite3.Error:
        return None
    if not row:
        return None
    model, c, a, meta = row
    try:
        m = json.loads(meta or "{}")
    except ValueError:
        m = {}
    return {
        "minutes": max(0, int((a - c) // 60)),
        "tokens": None,  # tokeny lokálně nedostupné — doplnit ze /session-stats
        "model": model or "",
        "cost": m.get("total_acu_cost") or m.get("total_credit_cost") or None,
        "detail": "tokeny doplnit z příkazu /session-stats (uživatel)",
    }


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--agent", required=True, choices=("claude", "devin"))
    ap.add_argument("--cwd", default=os.getcwd(),
                    help="pracovní adresář relace (výchozí: aktuální)")
    args = ap.parse_args()

    st = claude_stats(args.cwd) if args.agent == "claude" else devin_stats(args.cwd)
    if not st:
        print("minutes= tokens= model=  # relace nenalezena – hodnoty doplnit od uživatele",
              file=sys.stderr)
        return 1
    print(f"minutes={st['minutes']}")
    print(f"tokens={st['tokens'] if st['tokens'] is not None else ''}")
    print(f"model={st['model']}")
    if st.get("cost") is not None:
        print(f"cost={st['cost']}")
    if st.get("detail"):
        print(f"# {st['detail']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
