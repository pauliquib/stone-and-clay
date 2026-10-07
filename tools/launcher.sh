#!/usr/bin/env bash
# M8.1: spustí hru (přes run.sh) s danými parametry a zapíše KOMPAKTNÍ log do logs/ (mimo git),
# aby ho uživatel po hraní/měření jen poslal / aby šel snadno načíst příště (orchestrátor čte log,
# ne ruční přepis čísel z konzole). Hru samotnou spouští jen uživatel – tenhle skript ji nikdy
# nevolá sám od sebe, jen na vyžádání (stejně jako run.sh).
#
# Použití:
#   tools/launcher.sh --perfscene=ves_poledne           měřicí scéna (docs/testy_M8.md)
#   tools/launcher.sh --perfscene=les_rano_mlha,30      scéna, 30 s měření místo výchozích 20
#   tools/launcher.sh --date=2026-06-01 --time=12       libovolné parametry run.sh / main.gd se předají dál
#   tools/launcher.sh --help
#
# Log: logs/m8_perf_<RRRRMMDD_HHMMSS>.log (nový při každém běhu), logs/latest.log ukazuje na poslední.
# Obsah: PERF souhrn (CPU/GPU ms), chyby/varování a ostatní výstup – vše deduplikované
# (`tools/launcher_log.py`): "N× stejná hláška" místo N opakovaných řádků.
set -euo pipefail
cd "$(dirname "$0")/.."

usage() {
	cat <<'EOF'
tools/launcher.sh – spustí hru (run.sh) a zapíše kompaktní log výkonu/chyb do logs/

  tools/launcher.sh --perfscene=ves_poledne[,sekund]   měřicí scéna M8 (viz docs/testy_M8.md)
  tools/launcher.sh [libovolné další parametry run.sh / main.gd...]
  tools/launcher.sh --help                             tahle nápověda

Log se zapíše do logs/m8_perf_<datum_čas>.log (mimo git); logs/latest.log ukazuje na poslední běh.
Hru nespouští nic jiného než tenhle příkaz – launcher ji za tebe nerozjíždí sám.
EOF
}

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
	usage
	exit 0
fi

mkdir -p logs
TS="$(date +%Y%m%d_%H%M%S)"
RAW="logs/.raw_$TS.log"
OUT="logs/m8_perf_$TS.log"

echo "Spouštím: ./run.sh -- $*"
echo "(syrový výstup běží do $RAW, kompaktní log se zapíše do $OUT)"
: > "$RAW"

# "--" odděluje parametry Godotu od parametrů hry (main.gd čte jen OS.get_cmdline_user_args() za "--"),
# launcher ho doplní sám, ať se nemusí psát při každém spuštění.
set +e
./run.sh -- "$@" 2>&1 | tee "$RAW"
STATUS=${PIPESTATUS[0]}
set -e

python3 "$(dirname "$0")/launcher_log.py" "$RAW" "$OUT"
ln -sf "$(basename "$OUT")" logs/latest.log
rm -f "$RAW"
echo "Hotovo (návratový kód hry: $STATUS). Kompaktní log: $OUT (i logs/latest.log)."
exit "$STATUS"
