#!/usr/bin/env bash
# Noční běh roadmapy M0 (M0.1–M0.6): každý krok = samostatná session Claude Code (Sonnet),
# další krok začne až po skončení předchozího. Řada se zastaví, když session skončí chybou
# nebo krok nevytvoří commit. Checklisty ručních testů se sbírají do docs/testy_M0.md.
#
# Spuštění ručně:   tools/noc_M0.sh
# Naplánování:      systemd-run --user --on-calendar="RRRR-MM-DD 02:15" --unit=stoneclay-noc <cesta k tomuto skriptu>
# Průběh:           tail -f docs/noc_M0.log
set -u
REPO="${REPO:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
CLAUDE="${CLAUDE:-claude}"
LOG="docs/noc_M0.log"
TESTS="docs/testy_M0.md"
TOOLS="Read Edit Write Grep Glob Bash(git:*) Bash(grep:*) Bash(python3:*) Bash(ls:*) Bash(sed:*) Bash(head:*) Bash(tail:*) Bash(wc:*) Bash(find:*) Bash(cat:*) Bash(mkdir:*)"

cd "$REPO" || exit 1
[ -f "$TESTS" ] || printf '# Checklisty ručních testů – noční běh M0\n\n' > "$TESTS"
echo "=== $(date '+%F %T') START noční běh M0" >> "$LOG"

for f in prompts/roadmapa/M0_zaklady/0[1-6]_*.md; do
	before=$(git rev-parse HEAD)
	echo "=== $(date '+%F %T') START $f" >> "$LOG"
	"$CLAUDE" -p "Přečti a proveď $f. Pracuješ bez dozoru (noční běh): na nic se neptej a na ruční testy nečekej. Kde bys potřeboval rozhodnutí uživatele, zvol doporučenou výchozí variantu z promptu a zapiš ji do otevřených bodů v PROJECT_LOG.md. Checklist ručních testů připiš na konec souboru $TESTS pod nadpis s názvem kroku. Dokonči log, deník efektivity AI podle CLAUDE.md a commit, pak skonči." \
		--model sonnet \
		--allowedTools "$TOOLS" \
		>> "$LOG" 2>&1
	rc=$?
	if [ $rc -ne 0 ]; then
		echo "!!! $(date '+%F %T') $f skončil s kódem $rc – řada zastavena" >> "$LOG"
		break
	fi
	if [ "$(git rev-parse HEAD)" = "$before" ]; then
		echo "!!! $(date '+%F %T') $f nevytvořil commit – řada zastavena" >> "$LOG"
		break
	fi
	echo "=== $(date '+%F %T') HOTOVO $f ($(git log -1 --format=%s))" >> "$LOG"
done

echo "=== $(date '+%F %T') KONEC" >> "$LOG"
