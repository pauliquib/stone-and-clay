# Ruční testy – M8 Realistický svět

> Testování dělá výhradně uživatel (00_SPOLECNE kap. 2 bod 3). Agent jen čte kód a offline generátory
> (`tools/*.py`), hru ani `--…test` nespouští. Výkon se měří přes `--perfscene=<jméno>` (viz M8.1) –
> čísla (CPU/GPU ms, FPS) pošli zpátky, agent je porovná s rozpočtem v `M8_realismus/00_PRINCIPY.md`
> kap. 6 (16,6 ms/snímek na GTX 1050, 1080p, předvolba Střední; každý krok M8 smí přidat nejvýš
> 0,5 ms CPU / 1,0 ms GPU). Pro rychlejší posílání výsledků použij `tools/launcher.sh` (M8.1) – spustí
> hru a zapíše kompaktní log do `logs/` (viz README → „Add-ony a nástroje“).

Doporučené pořadí: M8.1 (základ) jako první, další kroky M8 doplní vlastní oddíl níž, jak přibývají.

## M8.1 – Základ: přepínače, eko-takt, měřicí scény, ladicí vrstvy

Co změřit: `tools/launcher.sh --perfscene=ves_poledne` (nebo přímo `./run.sh -- --perfscene=ves_poledne`),
pak `les_rano_mlha` a `udoli_noc`. M8.1 sám nic těžkého nepočítá (eko-takt běží bez odběratelů), takže
čísla by měla vyjít stejná jako bez M8 (jen pro základní měření do budoucích kroků).

1. Esc → Nastavení → dole „Realismus (M8)…“ – otevře se stránka s vysvětlením (zatím bez řádků
   k vypnutí, to je v pořádku – přidají je další kroky M8).
2. `tools/launcher.sh --perfscene=ves_poledne` (nebo `./run.sh -- --perfscene=ves_poledne`) → po
   ~23 s (3 s ustálení + 20 s měření) výpis na konzoli (fps, frame ms) a soubor
   `user://perf/ves_poledne.csv`; `logs/m8_perf_<datum_čas>.log` (launcher) obsahuje stejný souhrn.
3. Totéž pro `--perfscene=les_rano_mlha` (les u myslivecké chaty, ráno, mlha) a
   `--perfscene=udoli_noc` (noc, bezvětří) – kamera/hráč stojí na stejném místě při opakování běhu.
4. F2 → Herní menu → „Příroda – ladění…“ → zvol vrstvu „Ukázka (prázdná vrstva, M8.1)“ → otevře se
   mapa (M) – nekreslí se žádná barevná mřížka (vrstva je prázdná, jen ukázka API). Zvol „Vypnuto“ →
   mapa zase normální (ortofoto / podklad).
5. Vyspi se doma přes noc (celou noc, ne jen chvilku) → hra se nezasekne (eko-takt dohání hodiny po
   snímcích, ne najednou). Nikde se nic vizuálně nezmění (M8.1 sám nic nekreslí) – jde jen o to, že
   hra neztuhne.
6. F5 (rychlé uložení), pak F9 (rychlé načtení) → hra se načte normálně; po načtení hra neuvázne ani
   krátce (eko-takt se po načtení rozjede od aktuálního času, ne od začátku hry).
7. `--perfscene=neexistujici` → na konzoli/v logu jasná hláška „neznámá scéna“ a výpis platných jmen,
   hra se ukončí (ne pád).
8. `tools/launcher.sh --help` → vypíše nápovědu a skončí bez spouštění hry.

Co nahlásit: FPS / frame ms ze všech tří scén (ves_poledne, les_rano_mlha, udoli_noc) – ideálně obsah
`logs/latest.log` po doběhnutí, nebo aspoň poslední řádek „PERFSCENE … hotovo: fps …“ z konzole pro
každou scénu. Pokud se něco zaseklo nebo spadlo, popis + co bylo na obrazovce.
