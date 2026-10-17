#!/usr/bin/env bash
# M8.19: dávka měření výkonu po dokončení M8 (docs/testy_M8.md → „Plán testování po dokončení M8“).
# Každý běh = tools/launcher.sh --preset=… [--realism=…] --perfscene=<scéna>,<s> → vlastní log v logs/.
# Na konci se všechny logy dávky spojí do logs/m8_19_<skupina>_<datum_čas>.log – ten pošli zpátky.
# Hru spouští jen uživatel (tenhle skript nikdy nevolá agent).
#
# Použití:
#   tools/perf_m8_19.sh zaklad       1. priorita: ves_poledne na Nízká / Střední / Vysoká + 3 těžké scény na Střední (6 běhů, ~3 min)
#   tools/perf_m8_19.sh stredni      2. priorita: všechny ostatní scény na Střední (18 běhů, ~8 min)
#   tools/perf_m8_19.sh prepinace    3. priorita: přepínače Realismu vyp. proti zap. na Střední (8 běhů, ~4 min)
#   tools/perf_m8_19.sh vysoka       4. priorita: 3 scény na Vysoká a Ultra (6 běhů, ~3 min)
#   tools/perf_m8_19.sh vse          všechno za sebou (38 běhů, ~17 min)
#   tools/perf_m8_19.sh --help
set -uo pipefail
cd "$(dirname "$0")/.."

SEC="${PERF_SEC:-20}"          # délka měření jedné scény (s); PERF_SEC=30 tools/perf_m8_19.sh zaklad = delší
# Bez vsync (FIFO na 60 Hz monitoru zaokrouhlí snímek na 16,7 / 33,3 ms → všechno „30 fps“). Se svislou
# synchronizací: PERF_VSYNC=1 tools/perf_m8_19.sh …
VSYNC_ARGS=(--vsync=off --maxfps=0)
[ -n "${PERF_VSYNC:-}" ] && VSYNC_ARGS=()

ZAKLAD=(
	"nizka|ves_poledne"
	"stredni|ves_poledne"
	"vysoka|ves_poledne"
	"stredni|les_leto"
	"stredni|dron_200m"
	"stredni|les_rano_mlha"
)
STREDNI=(
	"stredni|ves_rano_zima" "stredni|ves_sobota_rijen" "stredni|louka_cerven" "stredni|les_rano_kveten"
	"stredni|rybnik_soumrak" "stredni|les_cerven_noc" "stredni|zver_pulnoc" "stredni|pole_pulnoc"
	"stredni|pole_rijen_vecer" "stredni|les_jaro" "stredni|udoli_noc" "stredni|kopec_inverze"
	"stredni|louka_vitr" "stredni|pole_leto" "stredni|zapad_slunce" "stredni|zima_telo"
	"stredni|zahrady_zari" "stredni|pole_blato"
)
# scéna, kde je systém vidět nejvíc, s jeho přepínačem vypnutým (srovnat se stejnou scénou ze skupiny zaklad/stredni)
PREPINACE=(
	"stredni|ves_poledne|village_life:off"
	"stredni|ves_poledne|gait:off"
	"stredni|les_leto|treegen:off"
	"stredni|les_rano_mlha|micro:off"
	"stredni|les_rano_kveten|soundscape:off"
	"stredni|louka_vitr|wind:off"
	"stredni|zver_pulnoc|habitat:off"
	"stredni|pole_pulnoc|crops:off"
)
VYSOKA=(
	"vysoka|les_leto" "vysoka|louka_cerven" "vysoka|dron_200m"
	"ultra|ves_poledne" "ultra|les_leto" "ultra|dron_200m"
)

usage() { sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; }

case "${1:-}" in
	zaklad) RUNS=("${ZAKLAD[@]}") ;;
	stredni) RUNS=("${STREDNI[@]}") ;;
	prepinace) RUNS=("${PREPINACE[@]}") ;;
	vysoka) RUNS=("${VYSOKA[@]}") ;;
	vse) RUNS=("${ZAKLAD[@]}" "${STREDNI[@]}" "${PREPINACE[@]}" "${VYSOKA[@]}") ;;
	-h|--help) usage; exit 0 ;;
	*) usage; exit 1 ;;
esac

mkdir -p logs
OUT="logs/m8_19_${1}_$(date +%Y%m%d_%H%M%S).log"
: > "$OUT"
i=0
for r in "${RUNS[@]}"; do
	i=$((i + 1))
	IFS='|' read -r preset scene realism <<< "$r"
	args=(--preset="$preset" "${VSYNC_ARGS[@]}" --perfscene="$scene,$SEC")
	label="[$i/${#RUNS[@]}] $scene · předvolba $preset"
	if [ -n "${realism:-}" ]; then
		args+=(--realism="$realism")
		label="$label · $realism"
	fi
	echo "=== $label"
	tools/launcher.sh "${args[@]}" >/dev/null 2>&1
	{
		echo "=================================================================="
		echo "=== $label (tools/launcher.sh ${args[*]})"
		cat "logs/latest.log" 2>/dev/null || echo "(log chybí)"
		echo
	} >> "$OUT"
	grep -h "PERFSCENE .* hotovo" "logs/latest.log" 2>/dev/null | sed 's/^/    /'
done
echo "Hotovo. Souhrnný log dávky: $OUT – pošli ho zpátky (spolu s poznámkou, kterou předvolbu běžně hraješ)."
