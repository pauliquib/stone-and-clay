#!/usr/bin/env bash
# Spouštěč pro zástupce na ploše / v nabídce (Stone & Clay.desktop).
# Godot 4.3 se pod Waylandem při spuštění mimo terminál občas zasekne hned po úvodním řádku (okno se
# neotevře, proces visí). Tenhle spouštěč hlídá log: když se hra do LIMIT s nerozběhne (v logu chybí
# řádek „Vulkan …“), zabije ji a zkusí znovu; po POKUSY neúspěších spustí hru přes X11 (XWayland).
# Výstup posledního běhu: ~/.local/share/godot/app_userdata/Stone & Clay/logs/godot.log
cd "$(dirname "$0")/.." || exit 1
LOG="$HOME/.local/share/godot/app_userdata/Stone & Clay/logs/godot.log"
LIMIT=8
POKUSY=3
ZNACKA="${XDG_RUNTIME_DIR:-/tmp}/stoneclay_start"

for i in $(seq 1 "$POKUSY"); do
	touch "$ZNACKA"
	sleep 1
	bash ./run.sh "$@" &
	PID=$!
	# run.sh na konci dělá `exec godot` → počkat, až se z procesu stane hra (předtím případný import)
	for _ in $(seq 1 600); do
		kill -0 "$PID" 2>/dev/null || exit 0
		[ "$(cat /proc/$PID/comm 2>/dev/null)" = "godot" ] && break
		sleep 1
	done
	GPID=$PID
	for _ in $(seq 1 "$LIMIT"); do
		sleep 1
		if [ "$LOG" -nt "$ZNACKA" ] && grep -q "^Vulkan\|^OpenGL" "$LOG" 2>/dev/null; then
			wait "$PID"
			exit $?
		fi
		kill -0 "$PID" 2>/dev/null || exit 0
	done
	echo "Stone & Clay: start se zasekl (pokus $i/$POKUSY), zkouším znovu…" >&2
	kill "$GPID" "$PID" 2>/dev/null
	sleep 2
	kill -9 "$GPID" 2>/dev/null
done

echo "Stone & Clay: spouštím přes X11 (XWayland)." >&2
STONECLAY_X11=1 exec bash ./run.sh "$@"
