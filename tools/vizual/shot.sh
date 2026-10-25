#!/usr/bin/env bash
# Jeden snímek hry pro vizuální kontrolu (přes godot_xvfb.sh) s frontou: naráz běží nejvýš VIZUAL_SLOTS
# (výchozí 2) Godotů – softwarový Vulkan vytíží všechna jádra a souběžné běhy by se jen zdržovaly.
#
#   tools/vizual/shot.sh výstup.png [herní argumenty…]
#   např. tools/vizual/shot.sh /tmp/a.png --pos=26,-12 --cam=26,1.7,-12 --yaw=60 --pitch=-6 --time=11
#         tools/vizual/shot.sh /tmp/b.png --pos=26,-12 --cam=26,120,-12 --pitch=-35 --preset=stredni
#
# Proměnné: VIZUAL_RES (výchozí 800x450), VIZUAL_WAIT (s reálného času po načtení, výchozí 12),
#           VIZUAL_RENDERER (forward_plus | mobile), VIZUAL_SLOTS (2).
# Volby hry: --cam=x,výška,z (volná kamera nad terénem, --yaw/--pitch ve stupních, --fov), --pos=x,z (hráč – kolem něj
# se streamuje vegetace a LOD stromů, dej ho ke kameře), --time=hh, --date=RRRR-MM-DD, --weather=druh, --preset=…
set -euo pipefail
cd "$(dirname "$0")/../.."
[ $# -ge 1 ] || { echo "použití: $0 výstup.png [argumenty hry…]" >&2; exit 2; }
OUT="$(realpath -m "$1")"
shift
mkdir -p "$(dirname "$OUT")"
RES="${VIZUAL_RES:-800x450}"
SLOTS="${VIZUAL_SLOTS:-2}"
REND=()
[ -n "${VIZUAL_RENDERER:-}" ] && REND=(--rendering-method "$VIZUAL_RENDERER")
LOG="${OUT%.png}.log"
while :; do
  for i in $(seq 0 $((SLOTS - 1))); do
    exec 9>"/tmp/vizual_slot_$i.lock"
    if flock -n 9; then
      timeout "${VIZUAL_TIMEOUT:-1500}" tools/vizual/godot_xvfb.sh --path . --resolution "$RES" "${REND[@]}" -- \
        --shot="$OUT" --wait="${VIZUAL_WAIT:-12}" --nohud "$@" >"$LOG" 2>&1 || true
      flock -u 9
      if [ -f "$OUT" ] && grep -q "SHOT saved" "$LOG"; then
        grep "SHOT saved" "$LOG"
        grep -E "SCRIPT ERROR|SHADER ERROR" "$LOG" | sort | uniq -c | head -20 || true
        exit 0
      fi
      echo "shot.sh: snímek se nepovedl, log: $LOG" >&2
      grep -E "SCRIPT ERROR|SHADER ERROR|ERROR" "$LOG" | sort | uniq -c | sort -rn | head -20 >&2 || true
      exit 1
    fi
  done
  sleep 5
done
