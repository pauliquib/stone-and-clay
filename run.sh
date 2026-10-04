#!/usr/bin/env bash
# Spustí hru Stone & Clay (Godot 4.3). První spuštění naimportuje textury (~30 s).
set -e
cd "$(dirname "$0")"
GODOT="${GODOT:-godot}"
CACHE=.godot/global_script_class_cache.cfg
if [ ! -d .godot/imported ]; then
  echo "První spuštění – importuji textury…"
  "$GODOT" --headless --path . --import
elif [ ! -f "$CACHE" ] || [ -n "$(find scripts -name '*.gd' -newer "$CACHE" -print -quit)" ] || \
     { [ -d models ] && [ -n "$(find models -newer "$CACHE" -print -quit)" ]; }; then
  # nové / změněné skripty s class_name → obnovit seznam tříd (jinak „Could not find type …“);
  # nové modely v models/ (.glb z Blenderu) je třeba naimportovat
  echo "Změněné skripty / modely – obnovuji import…"
  "$GODOT" --headless --path . --import >/dev/null 2>&1 || true
  touch "$CACHE"
fi
if [ ! -f data/buildings.json ]; then
  # bez něj nejsou fasády (okna/dveře/komíny) ani registr nemovitostí → start padá na usedlost
  echo "Generuji data/buildings.json (fasády, dveře, nemovitosti)…"
  python3 tools/buildings.py || echo "  POZOR: tools/buildings.py selhal – hra poběží bez fasád." >&2
fi
if [ ! -f data/terrain_height.bin ]; then
  echo "Chybí herní data (data/*.bin). Vygeneruj je:" >&2
  echo "  python3 tools/domov_hrace.py && blender --background --python tools/export_map.py" >&2
  exit 1
fi
# Na Waylandu nativní ovladač okna (ne XWayland) – pod XWayland KWin přeposílá snímky jen při
# pohybu myši a obraz se zasekává. Vypnout: STONECLAY_X11=1 ./run.sh
DRIVER=()
if [ "${XDG_SESSION_TYPE:-}" = "wayland" ] && [ -z "${STONECLAY_X11:-}" ]; then
  DRIVER=(--display-driver wayland)
fi
# Vykreslovat na dedikované NVIDIA kartě (PRIME render offload) místo slabé Intel iGPU.
# Vypnout: STONECLAY_IGPU=1 ./run.sh (vrátí se na výchozí/integrovanou grafiku).
if [ -z "${STONECLAY_IGPU:-}" ] && [ -e /proc/driver/nvidia/version ]; then
  export __NV_PRIME_RENDER_OFFLOAD=1
  export __GLX_VENDOR_LIBRARY_NAME=nvidia
  export __VK_LAYER_NV_optimus=NVIDIA_only
fi
# Vykreslovací backend podle volby v Nastavení → Grafika → Renderer (uloženo v nastaveni.cfg);
# Godot ho nejde přepnout za běhu, proto se čte tady a předává jako startovní parametr.
CFG="$HOME/.local/share/godot/app_userdata/Stone & Clay/nastaveni.cfg"
RENDERER=$(sed -n 's/^renderer="\(.*\)"$/\1/p' "$CFG" 2>/dev/null | tail -1)
if [ "$RENDERER" != "mobile" ]; then
  RENDERER=forward_plus
fi
exec "$GODOT" --path . "${DRIVER[@]}" --rendering-method "$RENDERER" "$@"
