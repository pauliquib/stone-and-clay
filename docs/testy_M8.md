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

## M8.2 – Mapa stanovišť: terén, voda, oslunění a půda

Nejdřív spusť generátor (agent ho jen napsal a staticky ověřil na syntetických datech – offline
generátor smí uživatel spustit sám, 00_PRINCIPY kap. 7):

```
python3 tools/site.py
```

Vypíše čas běhu, velikost `data/site.bin`, podíl půdních tříd, rozsah TWI a průměrné oslunění
jižních vs. severních svahů (mělo by platit jižní > severní). **Pošli tento výpis** – řekne, jestli
model dává smysl dřív, než se podíváš do hry.

Checklist (max. 10 bodů):
1. `python3 tools/site.py` doběhne bez chyby; zkontroluj vypsaný čas a velikost souboru.
2. F2 → Příroda – ladění → **TWI** (`site_twi`): modré linie v údolích by měly kopírovat potoky.
3. Vrstva **Půda** (`site_soil`): u řeky jiná barva (niva/fluvizem) než na kopcích; obec = antropozem
   (jiná barva než okolní pole).
4. Vrstva **Oslunění** (`site_insol`): jižní svahy světlejší (žlutší) než severní.
5. Vrstva **Mrazové kotliny** (`site_cold`): fialový odstín na dnech údolí, ne na hřbetech.
6. Vrstva **Vítr** (`site_wind`): červenější na hřbetech/kopcích než v zákrytu.
7. Stůj na nivě (louka těsně u potoka) a promluv s dědou/vesničanem (T), téma „půda“ (klíčové slovo
   „půda“ nebo „hlína“) → věta o vlhké/jílovité zemi; zkus to i na kopci → jiná věta (mělká/kamenitá).
8. `--perfscene=ves_poledne` (launcher) – FPS/ms by se nemělo znatelně lišit od naměřeného základu
   8. 10. 2026 (~27 fps / ~36 ms) – `Site` jen čte mřížku, nic nepočítá za běhu navíc.
9. Přejmenuj/smaž `data/site.bin` → hra běží dál (fallback): vrstvy na mapě M jsou prázdné (alfa 0),
   žádný pád ani varování navíc než jedno `push_warning`.
10. Ulož hru (F5) a znovu načti (F9) – žádný pád (`Site` nemá vlastní uložený stav, nic nového
    v save souboru).

Co nahlásit: výstup `tools/site.py` (statistika), FPS/ms z bodu 8, a jestli vrstvy z bodů 2–6
opticky odpovídají realitě (potoky, obec, jih/sever, dno údolí).

**Pozn. k velikosti dat:** `data/site.bin` má 16 vrstev na mřížce 4 m přes celý katastr
(~2,8 k × 1,9 k buněk) – odhadem ~100 MB (5 vrstev `uint16`, 11 `uint8`). To je víc, než
00_PRINCIPY kap. 6 předpokládá pro *všechny* nové mřížky M8 dohromady (≤ 64 MB) – je to otevřený bod
pro M8.19 (zúžit `dist_water`/`hand` na `uint8`, nebo tyto dvě vrstvy počítat jen „na dotaz“ místo
uložení). Hru to nezpomalí (čte se jen při startu), jen to zabírá víc místa na disku, než je cíl.
