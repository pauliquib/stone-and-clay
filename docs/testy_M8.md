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

### Naměřeno 8. 10. 2026 (kalibrace pro M8.19 – přečti před uzavřením milníku)

| Scéna | FPS (min/max) | Frame |
|---|---|---|
| ves_poledne | 26,8 (10–31) | 37,3 ms |
| les_rano_mlha | 26,1 (1–31) | 38,2 ms |
| udoli_noc | 28,6 (19–30) | 34,9 ms |

HW: NVIDIA Quadro M2200 (ne GTX 1050, ale podobná třída). Log hlásí `Vulkan ... Forward Mobile`,
**ne Forward+** jak počítá `00_SPOLECNE.md` – Godot si zřejmě sám zvolil slabší renderer na této
kartě/ovladači; `SSAO` hlásí varování, že vyžaduje Forward+. **Baseline už před M8.1 (bez eko-taktu
a jakéhokoli M8 obsahu) běží ~27 fps / ~36 ms, ne 60 fps / 16,6 ms** z rozpočtu kap. 6 – rozpočet
„0,5 ms CPU / 1,0 ms GPU navíc za krok M8“ je tedy nad už přetíženým základem, ne nad ideálním 60 fps
základem. M8.19 musí tohle zohlednit (buď vyšetřit Forward Mobile/renderer, nebo počítat rozpočet
relativně k naměřenému základu, ne k teoretickým 16,6 ms). Drobná varování v logu (zóny obecní
údržby/paseka se nevešly) nesouvisí s M8, jsou staré a nesouvisí s tímto měřením.

## M8.6 – Pohyb člověka: fázová chůze, IK na svahu, postoj

Co udělat (3. osoba, klávesa V): checklist z `M8_realismus/06_pohyb_cloveka.md` kap. 5, zkráceně:

1. Pomalá chůze po rovině → chodidla stojí na místě, při kroku neujíždějí dopředu/dozadu.
2. Chůze napříč svahem (např. od návsi dolů k potoku) → jedna noha níž, pánev/trup nakloněné do svahu.
3. Rozběh (Shift) → plynulý přechod chůze → běh, při běhu chvilka, kdy se obě nohy nedotýkají země.
4. Prudké zastavení ze sprintu a otočka na místě → přešlapování, ne otočení „na kolíku“.
5. Naložit špalek/pytel na rameno (G u hromady/pytle) → viditelné shrbení a kratší krok s nákladem.
6. Vyčerpat výdrž sprintem do nuly → shrbení a pomalejší krok; venku v mrazu bez bundy → ruce blíž k tělu,
   občas se postava otřese.
7. Opilost (vypít přes 1 ‰) → vrávorání s nápravnými kroky (staré potácení, teď nad `Gait`).
8. Dojít k vesničanovi na návsi → chůze vypadá stejně věrohodně jako u hráče.
9. Esc → Nastavení → „Realismus (M8)…“ → vypnout „Pohyb člověka“ → postava se vrátí ke staré (jednodušší)
   animaci chůze; znovu zapnout → vrátí se nová.
10. Vejít do bytového domu po schodech (pokud je po ruce) – chůze nevypadá rozbitě (žádná specializovaná
    animace schodů v M8.6 – otevřený bod, viz log).

Co změřit: `tools/launcher.sh --perfscene=ves_poledne` (víc vesničanů najednou – nejvíc postav v `_process`
`Humanoid`/`Gait` současně). Zajímá nás, jestli se oproti baseline z 8. 10. 2026 (ves_poledne 26,8 fps /
37,3 ms, viz výš) frame znatelně nezhoršil – `Gait.animate` je jen pár goniometrických funkcí a nejvýš
4 volání `Terrain.height_at` na postavu, rozpočet je ≤ 0,05 ms/postavu (00_PRINCIPY kap. 6).
