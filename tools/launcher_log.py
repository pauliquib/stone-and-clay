"""M8.1: zhutní syrový stdout/stderr hry do kompaktního logu pro `tools/launcher.sh`.

Proč: uživatel po hraní / měření (`--perfscene=…`) nemá ručně přepisovat čísla z konzole do chatu –
`launcher.sh` zachytí výstup a tenhle skript ho zapíše do `logs/m8_perf_<datum_čas>.log` ve třech
oddílech (PERF souhrn, chyby/varování, ostatní), s deduplikací opakujících se hlášek
("5× stejná hláška" místo 5 řádků), aby šel log poslat nebo si ho přečetl orchestrátor.

Použití:
    python3 tools/launcher_log.py <syrovy.log> <vystup.log>

Deterministické, jen standardní knihovna (žádné závislosti, aby šlo spustit vždy).
"""
import collections
import re
import sys


def dedup(lines: list[str]) -> list[str]:
	"""Zachová pořadí prvního výskytu; opakující se řádek dostane předponu 'N× '."""
	counts = collections.Counter(lines)
	seen: set[str] = set()
	out: list[str] = []
	for line in lines:
		if line in seen:
			continue
		seen.add(line)
		n = counts[line]
		out.append("%d× %s" % (n, line) if n > 1 else line)
	return out


def main(argv: list[str]) -> int:
	if len(argv) != 3:
		print("použití: launcher_log.py <syrovy.log> <vystup.log>", file=sys.stderr)
		return 2
	raw_path, out_path = argv[1], argv[2]
	with open(raw_path, "r", encoding="utf-8", errors="replace") as f:
		lines = [l.rstrip("\n") for l in f]

	perf_lines = [l for l in lines if l.startswith("PERF")]
	err_re = re.compile(r"SCRIPT ERROR|ERROR:|WARNING:")
	err_lines = [l for l in lines if err_re.search(l) and not l.startswith("PERF")]
	perf_set = set(perf_lines)
	err_set = set(err_lines)
	other = [l for l in lines if l not in perf_set and l not in err_set]

	err_dedup = dedup(err_lines)
	other_dedup = dedup(other)

	with open(out_path, "w", encoding="utf-8") as f:
		f.write("=== PERF (měřicí scény, --perfscene / --perf) ===\n")
		f.write("\n".join(perf_lines) + "\n" if perf_lines else "(žádné – nebyl použit --perfscene / --perf)\n")
		f.write("\n=== Chyby a varování (deduplikované) ===\n")
		f.write("\n".join(err_dedup) + "\n" if err_dedup else "(žádné)\n")
		f.write("\n=== Ostatní výstup (deduplikovaný, pořadí prvního výskytu) ===\n")
		f.write("\n".join(other_dedup) + "\n" if other_dedup else "(prázdné)\n")

	print("Zapsáno: %s  (perf %d řádků, chyby %d → %d, ostatní %d → %d)" % (
		out_path, len(perf_lines), len(err_lines), len(err_dedup), len(other), len(other_dedup)))
	return 0


if __name__ == "__main__":
	raise SystemExit(main(sys.argv))
