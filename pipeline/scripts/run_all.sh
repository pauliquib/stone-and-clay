#!/usr/bin/env bash
# Spustí všechny fáze 1–7 headless, po každé fázi zapíše stručný záznam do
# pipeline/PROJECT_LOG.md. NIC necommituje – commit dělá výhradně člověk/agent
# ručně a selektivně (v repu hry bývají nesouvisející WIP soubory).
#
# Rozmístění:
#   pipeline/scripts/  – tyto skripty (cwd se automaticky přepne na kořen hry)
#   pipeline/data/     – mezidata (json/npz; mimo git)
#   pipeline/assets/   – Poly Haven textury/HDRI (mimo git)
#   pipeline/renders/  – kontrolní rendery (mimo git)
#   pipeline/logs/     – logy fází (mimo git)
#   geodata/           – ČÚZK/OSM podklady (mimo git)
#   blend/             – vstupní a generované .blend (mimo git)
#
# Vstupní model domu: blend/Doubravy_3D.blend (není v repu, ~726 MB;
# přepíše se proměnnou BASE_BLEND). Výsledek pipeline = blend/mapa_okoli.blend
# (fáze 13, přímý vstup tools/export_map.py).
set -euo pipefail
cd "$(dirname "$0")/../.."          # kořen repozitáře hry (GAME)
mkdir -p pipeline/logs pipeline/renders
BL=${BLENDER:-blender}
BASE_BLEND=${BASE_BLEND:-blend/Doubravy_3D.blend}
DATE=$(date +%F)
LOGMD=pipeline/PROJECT_LOG.md

logentry() { # $1 nadpis, $2 soubor s výstupem, $3 grep vzor
  {
    echo
    echo "## $DATE – $1 (automatický běh pipeline/scripts/run_all.sh)"
    echo
    echo '```'
    grep -E "$3" "$2" | head -40 || true
    echo '```'
  } >> "$LOGMD"
}

echo "== Fáze 1"
"$BL" --background "$BASE_BLEND" --python pipeline/scripts/phase1_inspect_scene.py > pipeline/logs/phase1_inspect.log 2>&1
# ground_z a zdůvodnění volby severu se zachovávají z existujícího pipeline/data/scene_reference.json
python3 pipeline/scripts/phase1_align.py > pipeline/logs/phase1_reference.log 2>&1
logentry "Fáze 1: referenční bod a orientace" pipeline/logs/phase1_reference.log '"(house_scene_xy|house_latlon|ground_z|meters_per_unit|north_angle_deg|north_confidence|iou_best|iou_second)"'

echo "== Fáze 2"
python3 pipeline/scripts/phase2_osm_to_local.py > pipeline/logs/phase2.log 2>&1
logentry "Fáze 2: OSM → lokální souřadnice scény" pipeline/logs/phase2.log 'counts|range|excluded|types|WROTE'

echo "== Fáze 3"
"$BL" --background "$BASE_BLEND" --python-exit-code 1 --python pipeline/scripts/phase3_buildings.py > pipeline/logs/phase3.log 2>&1
logentry "Fáze 3: hmoty okolních budov" pipeline/logs/phase3.log '^(MAT|BUILDINGS|SAVED|RENDER|Error|Traceback)'

echo "== Fáze 4"
"$BL" --background blend/Doubravy_3D_okoli_v1.blend --python-exit-code 1 --python pipeline/scripts/phase4_roads_terrain.py > pipeline/logs/phase4.log 2>&1
logentry "Fáze 4: komunikace a terén" pipeline/logs/phase4.log '^(MAT|LANDUSE|SAVED|RENDER|Error|Traceback)'

echo "== Fáze 5"
"$BL" --background blend/Doubravy_3D_okoli_v2.blend --python-exit-code 1 --python pipeline/scripts/phase5_light_vegetation.py > pipeline/logs/phase5.log 2>&1
logentry "Fáze 5: osvětlení a vegetace" pipeline/logs/phase5.log '^(MAT|HDRI|TREE|SAVED|RENDER|Error|Traceback)'

echo "== Fáze 6–7 (přesné okolí z geodat ČÚZK)"
"$BL" --background "$BASE_BLEND" --python pipeline/scripts/phase6_apron.py > pipeline/logs/phase6_apron.log 2>&1
python3 pipeline/scripts/phase6_fetch_geodata.py > pipeline/logs/phase6_fetch.log 2>&1
python3 pipeline/scripts/phase6_textures.py > pipeline/logs/phase6_textures.log 2>&1
python3 pipeline/scripts/phase6_check_alignment.py > pipeline/logs/phase6_check.log 2>&1
python3 pipeline/scripts/phase6_analyze.py > pipeline/logs/phase6_analyze.log 2>&1
"$BL" --background "$BASE_BLEND" --python-exit-code 1 --python pipeline/scripts/phase7_build_accurate.py > pipeline/logs/phase7.log 2>&1
logentry "Fáze 7: přesné okolí" pipeline/logs/phase7.log '^(MAT|TERRAIN|BUILDINGS|ROADS|TREES|WORLD|SAVED|RENDER|Error|Traceback)'

echo "== Fáze 9–13 (rozšířené okolí – celý katastr)"
python3 pipeline/scripts/phase9_fetch_osm_full.py > pipeline/logs/phase9.log 2>&1
python3 pipeline/scripts/phase10_fetch_geodata_full.py > pipeline/logs/phase10.log 2>&1
python3 pipeline/scripts/phase11_osm_full_to_local.py > pipeline/logs/phase11.log 2>&1
python3 pipeline/scripts/phase12_analyze_full.py > pipeline/logs/phase12.log 2>&1
"$BL" --background --python-exit-code 1 --python pipeline/scripts/phase13_build_full.py > pipeline/logs/phase13.log 2>&1
logentry "Fáze 13: okolí celého katastru" pipeline/logs/phase13.log '^(MAT|TERRAIN|BUILDINGS|ROADS|TREES|FOREST|SAVED|RENDER|OPENED|Error|Traceback)'

echo "== Článek ve svec-studio → Zajímavosti (koncept, nepublikuje se)"
python3 pipeline/scripts/publish_article.py > pipeline/logs/publish_article.log 2>&1 || echo "WARN: článek se nepodařilo vytvořit, viz pipeline/logs/publish_article.log"
echo "HOTOVO – viz pipeline/renders/ a pipeline/PROJECT_LOG.md (nic se necommitlo)"
