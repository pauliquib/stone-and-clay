#!/usr/bin/env bash
# Spustí Godot 4.3 s opravdovým vykreslováním i bez GPU a monitoru (cloud, CI):
# virtuální X server (Xvfb) + softwarový Vulkan (Mesa lavapipe / llvmpipe).
# Na stroji s grafikou a displejem stačí obyčejný `godot` – skript ho pak jen spustí.
#
#   tools/vizual/godot_xvfb.sh [argumenty Godotu…]
#   např. tools/vizual/godot_xvfb.sh --path . -s res://tools/vizual/validator.gd -- --out=logs/vizual
#
# Proměnné: GODOT (cesta k binárce), VIZUAL_RES (rozlišení X serveru, výchozí 1600x900),
#           VIZUAL_NO_XVFB=1 (nepoužít Xvfb ani lavapipe – vlastní displej a GPU).
set -euo pipefail
cd "$(dirname "$0")/../.."
GODOT="${GODOT:-}"
if [ -z "$GODOT" ]; then
  for c in godot godot4 /opt/godot-bin/Godot_v4.3-stable_linux.x86_64; do
    if command -v "$c" >/dev/null 2>&1; then GODOT="$(command -v "$c")"; break; fi
  done
fi
if [ -z "$GODOT" ]; then
  # Godot chybí (čerstvý cloudový kontejner) → stáhnout oficiální 4.3-stable
  mkdir -p /opt/godot-bin
  echo "godot_xvfb: stahuji Godot 4.3-stable…" >&2
  curl -sSL -o /tmp/godot43.zip \
    "https://github.com/godotengine/godot/releases/download/4.3-stable/Godot_v4.3-stable_linux.x86_64.zip"
  unzip -o -q /tmp/godot43.zip -d /opt/godot-bin
  GODOT=/opt/godot-bin/Godot_v4.3-stable_linux.x86_64
fi
if [ -n "${VIZUAL_NO_XVFB:-}" ]; then
  exec "$GODOT" "$@"
fi
ICD=/usr/share/vulkan/icd.d/lvp_icd.json
if [ ! -f "$ICD" ]; then
  echo "godot_xvfb: instaluji softwarový Vulkan (mesa-vulkan-drivers)…" >&2
  (apt-get update -q >/dev/null 2>&1 || true)
  apt-get install -y -q mesa-vulkan-drivers xvfb >/dev/null 2>&1 || {
    echo "godot_xvfb: nelze nainstalovat mesa-vulkan-drivers – zkus VIZUAL_NO_XVFB=1" >&2; exit 2; }
fi
export VK_ICD_FILENAMES="$ICD"
RES="${VIZUAL_RES:-1600x900}"
exec xvfb-run -a -s "-screen 0 ${RES}x24" "$GODOT" --audio-driver Dummy "$@"
