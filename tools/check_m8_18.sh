#!/usr/bin/env bash
# M8.18 Zvuková krajina: kontrola překladu změněných / nových skriptů (00_SPOLECNE kap. 6) a shaderů.
# Spuštění z kořene repozitáře: bash tools/check_m8_18.sh [--shaders]
# Výstup kontroly překladu musí být prázdný (kromě oddělovačů „== soubor“).
set -u
cd "$(dirname "$0")/.."
timeout 600 godot --headless --path . --import >/dev/null 2>&1
FILES="scripts/priroda/soundscape.gd scripts/priroda/small_life.gd scripts/priroda/nature_sfx.gd scripts/priroda/nature_log.gd
scripts/dev/tune_m8_18.gd scripts/eko/households.gd scripts/sfx.gd scripts/local_client.gd scripts/game_settings.gd scripts/tests.gd"
for f in $FILES; do
	echo "== $f"
	timeout 60 godot --headless --path . --check-only --script "res://$f" 2>&1 | grep -E "SCRIPT ERROR|ERROR:" -A2 | head -20
done
if [ "${1:-}" = "--shaders" ]; then
	for m in mobile forward_plus; do
		echo "== shadery ($m)"
		timeout 120 godot --path . --rendering-method "$m" -s res://tools/shader_check.gd 2>&1 | grep -E "SHADER ERROR|E +[0-9]+->"
	done
fi
