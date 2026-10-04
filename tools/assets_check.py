#!/usr/bin/env python3
"""Kontrola registru assetů (M0.1). Bez závislostí, Python 3.

  python3 tools/assets_check.py

- najde soubory v assets/ (.glb .gltf .png .jpg .ogg .wav .mp3), které nejsou v assets/licenses.json,
- ohlásí záznamy s nepovolenou licencí (chyba) a záznamy, jejichž soubory neexistují (varování),
- vygeneruje data/credits.json – záznamy s licencí vyžadující uvedení autora
  (CC-BY-*, OGA-BY, royalty-free-game), pokud nemají "v_titulcich": false,
- vypíše souhrn; při chybě končí kódem 1.
Soubory záznamů jsou relativní k assets/ (např. "textures/sky.hdr", "models/zvirata/liska/liska.glb").
"""
import json
import sys
from pathlib import Path

GAME = Path(__file__).resolve().parent.parent
ASSETS = GAME / "assets"
REGISTRY = ASSETS / "licenses.json"
CREDITS_OUT = GAME / "data" / "credits.json"

EXT = {".glb", ".gltf", ".png", ".jpg", ".jpeg", ".ogg", ".wav", ".mp3"}
ALLOWED = {"CC0", "PD", "CC-BY-3.0", "CC-BY-4.0", "OGA-BY", "royalty-free-game"}
NEEDS_ATTRIBUTION = {"CC-BY-3.0", "CC-BY-4.0", "OGA-BY", "royalty-free-game"}
REQUIRED_KEYS = ["id", "soubory", "nazev", "autor", "zdroj", "licence", "stazeno", "upravy", "pouziti"]


def main() -> int:
	errors: list[str] = []
	warnings: list[str] = []
	try:
		records = json.loads(REGISTRY.read_text(encoding="utf-8"))
	except (OSError, ValueError) as e:
		print(f"CHYBA: nelze načíst {REGISTRY}: {e}")
		return 1

	registered: set[str] = set()
	ids: set[str] = set()
	credits: list[dict] = []
	for rec in records:
		rid = rec.get("id", "?")
		for k in REQUIRED_KEYS:
			if k not in rec:
				errors.append(f"[{rid}] chybí klíč '{k}'")
		if rid in ids:
			errors.append(f"[{rid}] duplicitní id")
		ids.add(rid)
		lic = rec.get("licence", "")
		if lic not in ALLOWED:
			errors.append(f"[{rid}] nepovolená licence '{lic}' (povolené: {', '.join(sorted(ALLOWED))})")
		for f in rec.get("soubory", []):
			registered.add(Path(f).as_posix())
			if not (ASSETS / f).exists():
				warnings.append(f"[{rid}] soubor neexistuje: assets/{f}")
		if lic in NEEDS_ATTRIBUTION and rec.get("v_titulcich", True) and lic in ALLOWED:
			credits.append({k: rec.get(k, "") for k in ("id", "nazev", "autor", "zdroj", "licence")})

	unlisted = []
	for p in sorted(ASSETS.rglob("*")):
		if p.is_file() and p.suffix.lower() in EXT:
			rel = p.relative_to(ASSETS).as_posix()
			if rel not in registered:
				unlisted.append(rel)
	for rel in unlisted:
		errors.append(f"neevidovaný soubor: assets/{rel}")

	CREDITS_OUT.parent.mkdir(exist_ok=True)
	CREDITS_OUT.write_text(json.dumps(credits, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

	print(f"Záznamů v registru: {len(records)}, souborů: {len(registered)}")
	print(f"Titulky (data/credits.json): {len(credits)} záznamů")
	for w in warnings:
		print("VAROVÁNÍ:", w)
	for e in errors:
		print("CHYBA:", e)
	print("OK" if not errors else f"{len(errors)} chyb")
	return 1 if errors else 0


if __name__ == "__main__":
	sys.exit(main())
