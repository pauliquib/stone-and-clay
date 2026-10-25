#!/usr/bin/env bash
# Vizuální validátor – jeden příkaz pro všechno: data → engine (pohledy, geometrie) → obrazy → report.
#
#   tools/vizual/run.sh [--out=logs/vizual/latest] [--quick] [--no-engine] [--res=WxH]
#
# Kroky: (1) chybí-li data/terrain_height.bin, syntetický svět (tools/vizual/synth_world.py);
#        (2) validate_data.py; (3) Godot s tools/vizual/validator.gd přes godot_xvfb.sh (pokud není --no-engine);
#        (4) validate_images.py; (5) report.py → <out>/report.html, report.json, contact_sheet.png.
# Předchozí výstup se před během přesune do <out>/../prev (porovnání před/po). Exit kód = report (1 při FAIL).
# Proměnné: VIZUAL_TIMEOUT (s, výchozí 1800) – limit běhu Godotu.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
OUT="logs/vizual/latest"
QUICK=""
ENGINE=1
RES="960x540"
for a in "$@"; do
  case "$a" in
    --out=*) OUT="${a#--out=}" ;;
    --quick) QUICK="--quick" ;;
    --no-engine) ENGINE=0 ;;
    --res=*) RES="${a#--res=}" ;;
    -h|--help) sed -n '2,11p' "$0"; exit 0 ;;
    *) echo "run.sh: neznámý argument $a" >&2; exit 2 ;;
  esac
done
case "$OUT" in /*) ;; *) OUT="$ROOT/$OUT" ;; esac
PREV="$(dirname "$OUT")/prev"
V="$ROOT/tools/vizual"

# minulý běh → prev
if [ -d "$OUT" ]; then
  rm -rf "$PREV"
  mv "$OUT" "$PREV"
fi
mkdir -p "$OUT"
echo "== vizuální validace → $OUT"

# (1) syntetický svět, chybí-li výšková data
if [ ! -f data/terrain_height.bin ] && [ -f "$V/synth_world.py" ]; then
  echo "== (1) chybí data/terrain_height.bin → synth_world.py"
  python3 "$V/synth_world.py" 2>&1 | tee "$OUT/synth_world.log" || echo "run.sh: synth_world.py selhal" >&2
fi

# (2) data
echo "== (2) datová vrstva"
python3 "$V/validate_data.py" --out="$OUT" $QUICK || echo "run.sh: validate_data.py skončil s chybou" >&2

# (3) engine
if [ "$ENGINE" = 1 ] && [ -f "$V/validator.gd" ]; then
  echo "== (3) engine (Godot, $RES)"
  W="${RES%x*}"; H="${RES#*x}"
  if [ "${W:-0}" -gt 1600 ] 2>/dev/null || [ "${H:-0}" -gt 900 ] 2>/dev/null; then
    export VIZUAL_RES="${VIZUAL_RES:-$RES}"
  fi
  T0=$(date +%s)
  timeout "${VIZUAL_TIMEOUT:-1800}" "$V/godot_xvfb.sh" --path . --resolution "$RES" \
    -s res://tools/vizual/validator.gd -- --out="$OUT" $QUICK > "$OUT/engine.log" 2>&1
  CODE=$?
  T1=$(date +%s)
  tail -n 15 "$OUT/engine.log"
  printf '{"exit_code": %d, "seconds": %d, "res": "%s", "quick": %s}\n' "$CODE" "$((T1 - T0))" "$RES" \
    "$([ -n "$QUICK" ] && echo true || echo false)" > "$OUT/engine_status.json"
  [ "$CODE" = 0 ] || echo "run.sh: Godot skončil s kódem $CODE (viz $OUT/engine.log)" >&2
else
  REASON="vynechán (--no-engine)"
  [ "$ENGINE" = 1 ] && REASON="chybí tools/vizual/validator.gd"
  echo "== (3) engine $REASON"
  printf '{"skipped": true, "reason": "%s"}\n' "$REASON" > "$OUT/engine_status.json"
fi

# (4) obrazy
echo "== (4) obrazová vrstva"
python3 "$V/validate_images.py" --out="$OUT" $QUICK || echo "run.sh: validate_images.py skončil s chybou" >&2

# (5) report
echo "== (5) report"
python3 "$V/report.py" --out="$OUT"
exit $?
