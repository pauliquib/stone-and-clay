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
relativně k naměřenému základu, ne k teoretickým 16,6 ms).

## M8.5 – Fyzikální obloha, světlo a expozice

Co změřit: `tools/launcher.sh --perfscene=ves_poledne` a nová `--perfscene=zapad_slunce` (louka,
21. 6. 2026, 20:30, jasno – otevřený pohled k obzoru). Cíl kap. 6: nejvýš +0,8 ms GPU navíc vůči
naměřenému základu (`ves_poledne` ~37,3 ms z 8. 10. 2026) na předvolbě Střední.

1. F2 → Teleport/Datum/Čas: 21. 6. 2026, 20:30, počasí jasno, kamera na otevřeném místě (nebo
   `--perfscene=zapad_slunce`) → oranžové sluneční kotouč u obzoru, naproti němu (na východě)
   narůžovělý pás (pás Venuše), po západu modrá hodina (obloha zmodrá a ztmavne postupně, ne naráz).
2. Poledne v létě vs. v prosinci (stejné místo) → v prosinci je slunce níž, slabší a teplejší
   barvou (`Atmosphere.SkyModel.sun_tint`), obloha u obzoru v poledne světlejší než v zenitu.
3. Noc za úplňku (F2 → Datum na den s úplňkem) na louce → krajina tmavě modrošedá, ale cesta a
   obrysy budov/stromů čitelné (Purkyňův posun = potlačené barvy, ne černo).
4. Noc v novu v lese → velmi tma, baterka/lampy znovu důležité (ne jako za úplňku).
5. Ze sklepa / interiéru ven v jasném poledni → krátké oslnění (obraz na okamžik jasnější), do ~2 s
   se srovná na normální jas; naopak při vstupu dovnitř přizpůsobení netrvá tak dlouho jako při
   vstupu do tmy v noci (to je v pořádku, rychlá/pomalá adaptace jsou různé).
6. Lampy v obci (M5.12) a světla aut svítí stejně jako dřív (ne přepálené ani zhasnuté) – fyzikální
   jednotky se netýkají interiérů ani umělých světel, jen slunce/měsíce/oblohy.
7. Esc → Nastavení → Realismus → „Fyzikální obloha a expozice“ vypnout → obloha i noční jas se
   vrátí ke starému vzhledu (bez pásu Venuše, bez adaptace, statická expozice jako dřív); zpátky
   zapnout → vrátí se nové chování.
8. `--perfscene=ves_poledne` a nová `--perfscene=zapad_slunce` → poslat FPS/ms (porovnání s
   naměřeným základem výš).

Co nahlásit: screenshot/popis západu slunce a nočních scén (úplněk vs. nov), zda lampy/auta
vypadají při zapnutém i vypnutém přepínači stejně, čísla z obou `--perfscene`.

**Otevřené body (M8.5):** místo předpočítané 64×256 LUT textury se transmitance počítá analytickými
vzorci přímo ve skriptu (levnější, v rozpočtu kap. 6, ale méně přesné u extrémních úhlů – k ověření
na skutečném běhu). Stíny mraků (předvolba Vysoká) a plná vzdušná perspektiva v `terrain.gdshader`
nejsou zavedeny – zůstává jen existující mlha/fog z M6.2. Fyzikální jednotky světel
(`use_physical_light_units`) se nezapínají globálně, jen lux→energy převod pro slunce/měsíc. Drobná varování v logu (zóny obecní
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

### Oprava regrese po vlně 2 M8 (8. 10. 2026, po mergi `f17274d`)

Uživatel naměřil po celé vlně 2 (M8.2 + M8.5 + M8.6) výrazně víc, než povoluje rozpočet
(00_PRINCIPY kap. 6, ≤ 0,5 ms CPU / 1,0 ms GPU na krok):

| | Před vlnou 2 | Po vlně 2 | Δ |
|---|---|---|---|
| FPS | 26,8 | 22,8 | −15 % |
| Frame | 37,3 ms | 44,0 ms | +6,7 ms |
| `villager` (PERF) | 4,5 ms / 72 vol. (63 µs/vol.) | 6,8 ms / 85 vol. (**80 µs/vol.**) | +27 % na instanci |
| `humanoid` (PERF) | 1,0 ms / 50 vol. (19 µs/vol.) | 2,0 ms / 49 vol. (**40 µs/vol.**) | +110 % na instanci |
| `car` (PERF) | 5,7 ms / 33 vol. (172 µs/vol.) | 7,9 ms / 39 vol. (203 µs/vol.) | +18 % na instanci |

**Příčina (villager + humanoid):** `scripts/villager.gd` v M8.6 skutečně jen krmí `Gait` daty (4
řádky, nic drahého), ale `villager` v PERF kategorii zahrnuje i čas jeho dětského uzlu `Humanoid`
(`_visual`) – tam byl skutečný problém, ve dvou místech `scripts/humanoid.gd`/`scripts/gait.gd`
zavedených v M8.6:
1. `Gait.animate()` počítala obě nohy přes `for i in 2` nad třemi nově alokovanými `Array` literály
   (`offs`/`legs`/`knees`) – 3 heap alokace + refcounting na *každé* zavolání, tj. na každý frame
   každé postavy navíc k samotné matematice.
2. `Humanoid._process_impl()` dělala 4× `ground_fn.call(...)` (Callable do `Terrain.height_at`) na
   **každý** frame (60 Hz) u každé stojící/chodící postavy se zapojeným terénem (`ground_fn`) –
   `Callable.call()` má větší overhead než přímé volání metody a sklon terénu pod chodidly se chůzí
   mění pomalu, takže vzorkovat ho 60×/s bylo zbytečné.

**Oprava:**
- `scripts/gait.gd`: smyčka nad dvěma nohama rozbalena přímo (`p_l/p_r`, `s_l/s_r`, `f_l/f_r`) beze
  změny výsledku – žádné `Array` literály v hot cestě.
- `scripts/humanoid.gd`: sklon terénu pod chodidly (`_slope_fwd`/`_slope_roll_raw`) se teď vzorkuje
  jen ~10×/s (`SLOPE_RESAMPLE_S = 0.1`, časovač `_slope_t`), mezitím se použije poslední známá
  hodnota. Fázová chůze, sklon pánve/trupu na svahu, náklad/únava/chlad zůstávají beze změny
  funkčně – jen se nepočítají/nevzorkují zbytečně často.

**Příčina (car):** `git diff ee9b51c^ ee9b51c -- scripts/car.gd` je **prázdný** – M8.2/8.5/8.6
soubor `car.gd` nezměnily. Nárůst volání 33 → 39 ukazuje, že šlo o jiný počet aut na mapě mezi
dvěma běhy měření (hustota dopravy se v `ves_poledne` může lišit běh od běhu), ne o regresi v kódu
auta. Nevylučuje to úplně nepřímý efekt (delší frame → jiné načasování spawnu/despawnu aut), ale
nic v `car.gd` k opravě není – neopravováno.

**Co znovu změřit:** `tools/launcher.sh --perfscene=ves_poledne` – FPS/frame by se měly vrátit
blízko baseline 26,8 fps / 37,3 ms (M8.6 Gait IK přidá očekávaně ~0,05 ms/postavu, M8.2 Site nic za
běhu nepočítá navíc), `villager`/`humanoid` v PERF kategorii by měly klesnout zpět blízko
+0,5 ms/+1,0 ms rozpočtu kroku M8 dohromady, ne +27 %/+110 % na instanci. `car` sledovat jen pro
ověření, že 33 vs. 39 volání byla skutečně jen variace hustoty dopravy (zkusit běh se stejným počtem
aut, pokud launcher umí fixovat seed/hustotu).

**Stav 16. 10. 2026 (po vlně 3 + opravě shaderů `64bbb05`):** uživatel potvrdil, že hra běží a shadery
větru fungují, ale **stále se lehce laguje** (bez čísel). Rozhodnutí uživatele: ruční testy i měření a
ladění výkonu **až po vlně 8 (M8.19)**, ne po každé vlně – čísla a příčiny se dohledají tam.

## M8.3 – Dřeviny a porosty podle stanoviště

Nejdřív vygeneruj data (v hlavním checkoutu, po `tools/site.py`):

```
python3 tools/tree_species.py
```

Vypíše podíly druhů (všechny / les), počet porostů, kontext stromů, věk/vitalitu/dbh a kontrolu
„severní svahy / jižní svahy / luh“. Agent naměřil (15. 10. 2026, `site.bin` z M8.2): smrk 39 %, buk 16 %,
habr 10 %, dub zimní 6 %, bříza 5 %; 3 699 porostů (35 % smrčiny, 46 % smíšené, 18 % luhy); hlavní druh porostu
na severu smrk 78 %, na jihu habr 34 % + dub 25 %, v luhu olše 79 %; ovocné v lese 0.

Checklist (max. 10 bodů):
1. `python3 tools/tree_species.py` doběhne (~4 s) – podíly dávají smysl pro moravskou pahorkatinu?
2. F2 → Příroda – ladění → **druhy**: souvislé barevné plochy (porosty), ne „sůl a pepř“; modré (olše/vrby)
   pásy podél potoků, tmavě zelený smrk / oranžový buk na severních svazích, hnědý dub / žlutavý habr na jižních.
   Legenda barev: `TreeEco.DEBUG_COLORS` (smrk tmavě zelená, buk oranžová, dub hnědá, habr béžová, olše modrá,
   bříza bílá, jabloň červená, švestka fialová).
3. Vrstva **vitalita**: zelená = dobré stanoviště, do červena = slabší (mělká půda, nevhodné).
4. Teleport k potoku (les u vody) → E na kmen („Prohlédnout strom“) → „Olše lepkavá, asi … let“ (u jehličnatého
   tvaru stromu tam bude smrk – tvar zatím určuje prototyp, M8.8).
5. Les na severním svahu → E → buk / smrk; jižní svah → dub / habr. S Dřevorubectvím ≥ 10 i výška, průměr,
   vitalita; ≥ 20 i objem a cena dřeva.
6. Pokácet listnáč a podobně vysoký jehličnan (M2.1) → hláška „Padá buk lesní – 0,xx m³ dřeva, cena na pni ~… Kč“;
   buk a smrk stejné výšky dají jinou cenu.
7. Zahrady u domu v září (`--perfscene=zahrady_zari` nebo F2 → Datum 15. 9.) → ovoce jen na jabloních /
   hrušních / švestkách / třešních (barva podle druhu), lípy a břízy bez ovoce.
8. Zasadit buk na vlhkou nivu u potoka a buk na hlinitý svah → E na sazenici → „stanoviště … (vitalita x %)“
   se liší (niva nižší).
9. Esc → Nastavení → Realismus → vypnout „Dřeviny a porosty“ → kácení zase starou cenou, „Divoký strom –
   žádné údaje.“; F5/F9 uložení a načtení bez pádu (sazenice si vitalitu pamatují).
10. Přejmenuj `data/tree_eco.bin` → hra běží (jedno varování), druh podle tvaru (buk/dub/lípa/smrk/borovice).

**Co změřit:** `tools/launcher.sh --perfscene=zahrady_zari` a `--perfscene=les_rano_mlha` – M8.3 za běhu nic
nesimuluje (jen čte data), čekej změnu FPS/frame ≤ 0,1 ms proti stavu před M8.3 (PERF kategorie `seasonfx`
beze změny řádu). Načítání: řádek „Stromy (51 736)…“ delší nejvýš o ~20 ms (čtení 1,1 MB `tree_eco.bin`);
bez souboru (fallback) o ~100 ms (dopočet mřížek z 51 tis. stromů).

## M8.4 – Pole větru: nárazy, závětří, hierarchický ohyb

1. F2 → Počasí → Bouřka, léto (F2 → Datum, červenec) → stát u pole s obilím → přes pole běží vlny po větru.
2. Les v bouřce → koruny se ohýbají postupně (ne všechny stromy naráz), padá listí kolem kamery, vítr hučí víc než na louce.
3. F2 → Počasí → Jasno (vítr ~2 m/s) → stromy a tráva téměř nehybné; Mlha (0,6 m/s) → klid.
4. F2 → Příroda – ladění → `vitr` → mapa M: hřebeny teplejší barva (silnější), údolí a les modřejší.
5. Paramotor/trike (M6.4–6.5) nad hřebenem vs. nad údolím → silnější drift a na návětří stoupání.
6. Zima, vítr (Přeháňky/Bouřka) → kouř z komínů se sklání po větru, v nárazech víc.
7. Dron v lese / za kopcem → slabší drift než na otevřeném poli.
8. Esc → Nastavení → Realismus → vypnout „Pole větru“ → stromy se vrátí ke staré sinusovce, tráva ke starému mávání.
9. Konzole po startu: žádná chyba překladu shaderů (`tree`, `vegetation`, `wind.gdshaderinc`).

Co změřit: `tools/launcher.sh --perfscene=louka_vitr` (bouřka, otevřená louka) a pro srovnání totéž s vypnutým
„Pole větru“. Očekávání: GPU +≤ 0,3 ms proti vypnutému (jedno čtení textury + pár sinů na vrchol stromů a
trávy), CPU +≤ 0,1 ms (`WindField._tick` + `wind_at` u kamery, letadla, dronu, komínů a zvěře; první
průchod mapou dopočítá buňky 24 m – jednorázově). Kontrolně `--perfscene=les_rano_mlha` (hodně stromů).

## M8.7 – Vodní bilance: vlhkost půdy, odtok, potoky a bláto

Pozn.: vodní bilance se po startu / načtení staví po kouscích ~30–40 s (mřížka 32 m) – do té doby platí staré
globální chování. Hodinový krok běží ~30 s reálného času; po změně počasí počkej aspoň 1–2 herní hodiny.

1. F2 → Počasí → Bouřka, nech běžet ~2 herní hodiny → potok u obce vystoupá (až +0,4 m) a je hnědý, šumí hlasitěji.
   F2 → Příroda – ladění → „Průtoky toků (M8.7)“ → Q nad normálem, kalnost > 0 %.
2. Pak F2 → Počasí → Jasno a přeskočit 2–3 dny → hladina zpět u normálu, voda čistá (kalnost ~0 %).
3. Mapa M s vrstvou `vlhkost` (F2 → Příroda – ladění) po dešti: údolnice/niva modrá, hřbety světlé; po týdnu jasna zesvětlá,
   niva zůstane modřejší déle než svah.
4. Auto po dešti: polní cesta / louka v nivě u potoka → smyk a horší brzdění; stejný povrch na kopci → drží líp.
5. Louže po dešti jen v nížinách / prohlubních a u potoků, ne na každé silnici; postupně vysychají (ne naráz).
6. Zima se sněhem (F2 → Datum leden, Počasí Sníh, pak oteplení): vrstva `snih` – jižní svahy roztají dřív než severní a les.
7. F2 → Datum červenec, nastavit jasno a přeskočit ~3 týdny → malé potoky „VYSCHLÉ“ (pás vody zmizí, nešumí),
   `Průtoky` ukazují sucho > 60 % → vyhláška sucha (web obce / úřední deska).
8. F5 → ukončit → F9: hladiny, kalnost a vrstva `vlhkost` stejné jako před uložením; starý save bez klíče se načte (rozběh).
9. Esc → Nastavení → Realismus → vypnout „Vodní bilance“ → potoky na normálu, louže a bláto zase globální (jako dřív).
10. Konzole bez chyb `SoilWater` / `Water` při startu i během prvních ~60 s.

Co změřit: `tools/launcher.sh --perfscene=pole_leto,60` (60 s, ať měření zachytí hodinový průchod mřížkou; PERF kategorie
`soil_water` a `water`). Očekávání: `soil_water` ≤ 0,3 ms průměr na snímek během průchodu (48 buněk/snímek), mimo průchod
~0; po startu během stavby mřížky (prvních ~40 s) do ~0,5 ms. `water` se nemá zvednout o víc než ~0,05 ms (aktualizace
426 hladin 1× za sekundu jen při změně). FPS/frame proti poslední baseline `pole_leto` bez zhoršení > 0,5 ms.

## M8.8 – Generátor stromů: tvary podle druhu, věku a vitality + LOD a impostory

Pozn.: data jsou v gitu (`data/tree_species_protos.bin`, `assets/textures/trees/`); přegenerovat jen po změně
`data/dreviny.json` → `tvary` (`python3 tools/treegen/treegen.py --preview`). Přepínač „Generované stromy“ se
projeví až po novém načtení světa (nová hra / restart).

1. `python3 tools/treegen/treegen.py --preview` → `tools/out/treegen/nahled_<tvar>.png`: řádky = varianty
   (vitalita nízká/vysoká × mladý/dospělý), sloupce LOD0 | LOD1 | impostor. Poznáš smrk (kužel), borovici
   (holý kmen, deštník), buk (kopule), břízu (bílý kmen, řídká převislá koruna)?
2. Les zblízka (F2 → Teleport → les u myslivecké chaty, léto, poledne): listí jako karty se siluetou listů,
   kůra podle druhu (buk šedý hladký, dub brázditý, bříza bílá s černými pásky, borovice oranžová).
3. Chůze lesem 40–80 m od stromů: přechod LOD0 → LOD1 plynulý (dither), žádné probliknutí ani díry v korunách.
4. Dron 200 m nad lesem (`--perfscene=dron_200m` nebo dron O): v dálce impostory, druhy rozeznatelné
   (tmavé kužely smrků vs. kulaté listnáče), při kroužení kolem lesa se snímky impostorů nepřepínají skokem.
5. F2 → Příroda – ladění → vrstva `vitalita`: hřbet s nízkou vitalitou (červeně) vs. niva – stromy na hřbetu
   menší, řidší a křivější, v nivě vyšší a hustší.
6. Pokácet strom (sekera) → zmizí správný strom (i jeho impostor), zůstane pařez; F5 → ukončit → F9 → strom
   zůstává pokácený. Odejít > 250 m a vrátit se → pokácený strom se neobjeví (buňka se staví znovu).
7. Podzim (F2 → Datum říjen–listopad): barvení a opad po chomáčích i na nových stromech a impostorech;
   zima: holé větve (i impostory ukážou siluetu větví), sníh na horních plochách.
8. Bouřka (F2 → Počasí): ohyb po úrovních – kmen pomalu, větve, listy se třepou; smrk tužší než bříza.
9. Zasadit sazenici (M2.5) → mladý model druhu; po přeskočení času (F2) roste a přejde na dospělý model.
10. Esc → Nastavení → Realismus → vypnout „Generované stromy“ → nová hra / restart → původních 6 modelů;
    konzole bez chyb `TreeGen` / `tree.gdshader` / `tree_impostor.gdshader`.

Co změřit: `tools/launcher.sh --perfscene=les_leto` (nová scéna: les v létě bez mlhy – LOD0/LOD1 a karty listí),
`--perfscene=les_rano_mlha` a `--perfscene=dron_200m`, každé jednou se zapnutými a jednou s vypnutými
„Generovanými stromy“ (restart mezi tím). Očekávání: GPU v lese +≤ 1,0 ms proti vypnutému (karty listí =
víc přepisů pixelů, alfa test), na dronu spíš úspora (impostor 2 trojúhelníky místo ~130–200); CPU spíš
nižší než dřív (uzlů stromů ~1,5 tisíce místo ~15 tisíc – blízké MultiMeshe jen kolem kamery, dálka 1 MultiMesh
na buňku 256 m), streamování buněk ≤ 1 ms/snímek jen při pohybu. Draw calls (PERF) ≤ 2× dnešní. Kdyby GPU v lese
přetékalo: snížit `BUDGET` / `hustota_listi` v generátoru nebo `TreeGen.L0_END` (LOD0 blíž).
## M8.9 – Mikroklima: inverze, mrazové kotliny, údolní mlha, rosa a jinovatka

Pozn.: stav mikroklimatu (síla inverze, mlžná vrstva, rosa) se počítá jednou za herní hodinu (~2 min reálně) a mezi
kroky plynule prolíná; po F2 změně data / času / počasí se hned dopočítá „rozběhem“ (18 h s dnešním počasím).
F2 → Příroda – ladění → „Mikroklima (M8.9)“ ukazuje inverzi, výšku mlhy, mrazovou hranici, rosu a hodnoty v místě hráče.

1. `--perfscene=kopec_inverze` (nebo F2 → Datum 12. 10., Počasí Jasno, čas 6:30 a teleport na hřbet ~1340, −2670) →
   v údolí na JV leží mlha s ostrým horním okrajem („moře mlhy“), hřbet je nad ní. Sejít / sjet dolů → uvnitř vrstvy
   je dohled ~200 m, ne bílá stěna.
2. Leden, jasno, 4:00: HUD teplota na dně údolí (u potoka) vs. na hřebeni → rozdíl 3–8 °C; v poledne téměř stejná.
3. Za větru (Bouřka / Přeháňky) nebo Zataženo: v F2 → Mikroklima inverze < 1 K, mlha v údolí není, teplota všude ~stejná.
4. Ráno 6:00–7:00 po jasné noci: tráva a terén lesklé (rosa), pod mrazovou hranicí (dno údolí, říjen–duben) bělavé
   (jinovatka); v 10:00 už nic. HUD ukazuje „· rosa“ / „· jinovatka“ / „· přízemní mráz“.
5. Kouř z komínů v obci za jasného bezvětrného rána (inverze ≥ 2,5 K) → drží se nízko a rozlévá.
6. Červenec, jasno, 15:00: jižní stráň (vrstva `site_insol` žlutá) o 1–3 °C tepleji než v lese (F2 → Mikroklima „Tady“).
7. Leden, jasno, noc, bez bundy: v kotlině prochladneš rychleji než na kopci (ukazatel chladu / zprávy těla).
8. Mapa M s vrstvou `teplota` v noci za jasna → údolnice a kotliny modré, hřbety a obec načervenalé; vrstvy `mlha`, `mraz`.
9. Esc → Nastavení → Realismus → vypnout „Mikroklima“ → HUD teplota všude stejná jako Počasí, mlha v údolí zmizí, rosa ne.
10. Deník J → Počasí po jasné mrazivé noci (po poledni): „V údolí v noci mrzlo (−3 °C), na kopci ne (1 °C).“; F5 → F9
    zachová stav (klíč `micro`), starý save se načte (rozběh).

Co změřit: `tools/launcher.sh --perfscene=kopec_inverze,30` a `--perfscene=udoli_noc,30` (porovnat FPS/frame s vypnutým
přepínačem „Mikroklima“). Očekávání: CPU ≈ +0,05 ms (HUD řádek 2×/s, tělo hráče 1 dotaz za snímek z mezipaměti, hodinový
krok ~40 vyhodnocení profilu jednou za 2 min); GPU ≤ +0,1 ms (výšková mlha je jen pár instrukcí ve stávající mlze, rosa
a jinovatka pár ALU v terénu a vegetaci) – cíl +≤ 0,5 ms na Střední. Volumetrická mlha se nepoužívá.
`--perfscene=les_rano_mlha` beze změny proti baseline (advekční mlha z Weather jako dřív).
## M8.10 – Lokomoce zvířat 2 a let ptáků

Přepínač Esc → Nastavení → Realismus → „Lokomoce zvířat a let ptáků“ (`animal_gait`). Páteř, dech a pružiny uší /
ocasu jsou vidět jen do 60 m od kamery.

1. Dalekohled (X) na pasoucí se srnce (soumrak, okraj lesa) → uši kmitají a dopruží; přiblížit se během (Shift) → uši
   se natočí k hráči, hlava nahoru, boky klidně dýchají.
2. Vyplašit srnce zblízka → krok → klus → cval bez skoku v animaci (nohy se „přeskládají“ plynule), bílé zrcátko se
   rozevře, ocas nahoru; ve cvalu se přední a zadní nohy střídavě přitahují k sobě (pružná páteř).
3. F2 → Datum červen, srnci u obilí / na louce → útěk polem: vyšší a častější odrazové skoky než na strništi (v říjnu).
4. Zajíc (pole, noc/ráno) → kličky s výrazným náklonem do zatáčky, ocas a uši plandají.
5. Divočáci (les v noci) → klus s nízkou hlavou, ocas při útěku vztyčený; selata cupitají (rychlejší krok).
6. Kůň pod jezdcem: postupně zrychlovat krok → klus → cval → trysk – plynule bez cukání nohou; na místě boky dýchají, uši kmitají.
7. Červenec 13–15 h, jasno (F2 → Počasí) nad polem → káně krouží bez mávání a stoupá (a kde stoupá paraglide/paramotor,
   tam krouží i ona – termika `Thermals`); mimo sezónu termiky krouží kolem okrsku, také bez mávání.
8. Vrány na poli – přiblížit se → vzlétnou pár silnými mávnutími, pak střídají mávání a klouzání a drží hejno; na stromě
   přistanou s brzděním (křídla nahoru a dopředu, tělo vztyčené, ocas dolů) přímo na větev – bez „teleportu“ o metr.
9. F2 → Počasí Bouřka / silný vítr → ptáci letí proti větru znatelně pomaleji, po větru rychleji; přistávají čelem
   proti větru. Říjen ~17:30–18:30 nad polem, jasno → hejno špačků (stovky teček) se vlní, občas se roztrhne vlnou
   (dravec), po západu slunce sestoupí a zmizí (ne každý večer – 2 ze 3).
10. Vypnout přepínač → zvěř i ptáci jako dřív (chod podle rychlosti, bez pružin, staré „body po křivce“), žádné hejno
    špačků; konzole bez chyb (`QuadrupedRig`, `FlightModel`, `Murmuration`, shader `murmuration`).

Co změřit: `tools/launcher.sh --perfscene=pole_leto` – PERF kategorie `animal` a `flock` proti poslední baseline;
očekávání **+≤ 0,3 ms CPU** celkem (rig nově nealokuje a IK vzorkuje terén 3× za 0,1 s místo 4× za snímek, takže
`animal` může vyjít i levněji; `flock` +≤ 0,05 ms – vítr a termika 4× za s na ptáka). Dále
`tools/launcher.sh --perfscene=pole_rijen_vecer` (říjen, soumrak, pole – zvěř na poli, vrány, hejno špačků; pokud se
hejno ten den neobjeví, posunout datum o den): `murmuration` **≤ 0,3 ms** průměr (¼ hejna za snímek, max. 400 ptáků,
1 draw call), GPU +≤ 0,2 ms. Pro srovnání totéž s vypnutým „Lokomoce zvířat a let ptáků“.

## M8.16 – Tělo 2: tepelná bilance, žízeň, spánek, pád

Pozn.: čísla jádra ukazuje jen F2 → Hráč (první řádek: jádro, bilance W, MET, voda, bdění, vítr na těle); HUD píše jen
slova (zima, horko, žízeň, ospalost, zranění). F2 → Hráč → „Napojit, vyspat, zahřát a vyléčit pád“ vrací tělo do normálu.

1. Leden −5 °C, bunda (Wardrobe), F2 → Náklad → pytel 25 kg na rameno: chůze do kopce → F2 bilance kladná, zima se
   neobjeví; stát 30 herních min (~1 min) bez hnutí na posedu / u lesa → jádro klesá, HUD „zima“, deník „prochladneš…“.
2. Promoknout v dešti (bez pláštěnky) a stát ve větru → prochladneš o hodně rychleji než suchý (deník: „Jsi promoklý
   a fouká – … za půl hodiny“); u ohně / kamen se rychle zahřeješ a uschneš.
3. Červenec 30 °C, jasno, sekat / štípat dřevo → po chvíli „žízeň“ a „horko“; v lese (stín) méně. Napít se ze studánky
   nebo sklenice vody z dřezu doma → žízeň zmizí.
4. Pět piv v horku → žízeň neklesne jako po vodě, s panáky roste (deník: „pivo ani kořalka žízeň neuhasí“).
5. ~20 herních h bez spánku → HUD „ospalost“; jízda autem → občas krátké zatmění (mikrospánek); kafe ospalost ubere,
   spánek ji smaže.
6. Seskok z ~2 m → jen záblesk bolesti a krátké kulhání (bez sprintu); ze střechy ~5 m → zranění, ležení, kulhání
   několik herních hodin; to samé do závěje (sníh) nebo do hluboké vody → méně / nic. Pád z ~12 m → nemocnice.
7. Deník J → oddíl „ZDRAVÍ“ – srozumitelné věty, bez čísel.
8. F5 → F9 → jádro, žízeň, ospalost i kulhání zůstanou; starý save se načte (napitý, vyspalý).
9. Esc → Nastavení → Realismus → vypnout „Tělo: teplo, žízeň, spánek“ → staré prochladnutí podle pocitové teploty,
   žádná žízeň / ospalost, pád jako dřív (zranění až nad 6 m).
10. F3 → Člověk / Tělo – teplo a energie (126 parametrů): např. „Teplo – efektivní tepelná kapacita“ ×0,5 → zima
    i horko přicházejí 2× rychleji.

Co změřit: `tools/launcher.sh --perfscene=zima_telo,30` (prof. klíč „body_thermo“) a pro srovnání s vypnutým přepínačem
„Tělo“. Očekávání: CPU ≈ +0,01–0,02 ms průměrně (bilance 4×/s reálně, v kroku 1 dotaz na vlhkost mikroklimatu, zápoj
korun a výška slunce, žádné alokace); GPU beze změny (mikrospánek jen využije stávající zatmění v `DrunkFx`).

## M8.D – Menu pro vývojáře

Část M8.D1: registr `DevTune`, menu F3, Režim vývojáře, Uložit / Export a kategorie **Svět** + **Vozidla** (~520
parametrů). Ostatní kategorie (Létání, Člověk, Činnosti, Příroda, Zvěř) doplní M8.D2 – do té doby v menu nejsou.

1. Esc → Nastavení → Vývoj → zapnout „Režim vývojáře“; F1 ukáže řádek „F3 – menu pro vývojáře“. F3 otevře menu
   vpravo (hra běží dál, kurzor je vidět), F3 i Esc ho zavřou (Esc nejdřív zavře menu, ne pauzu).
2. Sednout do auta (Oktávka), F3 → Vozidla → Auto: „Brzdy – zpomalení“ z 8,8 na 4 → brzdná dráha znatelně delší;
   „Přilnavost – tření pneu“ na 0,5 → auto v zatáčce klouže; ↺ vrátí výchozí, zvýraznění řádku zmizí.
   Vozidla → Auto – modely → „Oktávka Kombi: Motor – max. moment“ 250 → 600 → zrychlení hned silnější.
3. Psaní do hledání / čísla nepohne autem ani postavou (WASD stojí, dokud je fokus v poli); posuvníkem jde měnit
   za jízdy (držet W, táhnout myší).
4. Motorka Armádka / Krosák (F2 → Vozidla): Vozidla → Motorka – modely → „Náklon – největší náklon“ menší → v zatáčce
   se nakloní míň; Vozidla → Motorka → „Náklon – vyvažování: tuhost“ na 3 → vratká. Kolo: „Šlapání – síla“ znát hned.
5. Hledání „brz“ → brzdy auta, traktoru, motorky i kola (s nadpisy podskupin); „gravit“ → gravitace světa i vozidel.
6. Svět → Čas „Rychlost herního času“ 30 → 120 → hodiny v HUD běží 4× rychleji; Svět → Povrchy „Přilnavost – suchý
   asfalt“ 0,4 → auto i chůze kloužou.
7. Uložit → ukončit, znovu spustit → hodnoty drží (zvýrazněné). Exportovat (potvrdit Ano) → v kořeni projektu
   `config.json` jen se změněnými hodnotami, klíče seřazené; smazat `~/.local/share/godot/app_userdata/<hra>/ladeni.cfg`
   → po restartu hodnoty platí z `config.json` (už nejsou zvýrazněné – jsou to nové výchozí). Po testu `config.json` smazat.
8. Výchozí (skupina) a Výchozí (vše) se ptají v dolní liště (Ano / Ne) → vše zpět, zvýraznění zmizí.
9. Ruční vozík (F2 → Hráč → Postavit ruční vozík, E = táhnout): Vozidla → Ruční vozík „Útlum puštěného vozíku“ 0,9 → 0,1 → na svahu
   ujede daleko; „Tažení – pružina“ menší → vozík se za hráčem víc „vleče“.
10. Režim vývojáře vypnout → F3 nic nedělá, F1 o něm nemluví; konzole bez chyb (`DevTune`, `DevMenu`, `Car`).

Co změřit: `tools/launcher.sh --perfscene=…` (scéna s provozem) proti baseline – kategorie `car` beze změny
(konstanty auta jsou teď členy sdíleného objektu `Car.TUNES` a `static var` – čtení za snímek ~stejné, registr se za
snímek nečte); s otevřeným menu F3 jen cena UI.

### M8.D2a – Létání

1. F3 → Létání: podskupiny Společné, Letadlo, Paramotor, Rogalo a trike, Dron, Termika (počty 68 / 16 / 50 / 23 / 73 / 26);
   nic není zvýrazněné jako změněné (výchozí = kód).
2. Letadlo (F2 → Létání → testovací letoun): Létání → Letadlo „Motor – statický tah“ 760 → 1500 → rozjezd kratší a stoupá
   rychleji; Společné „Řízení – rychlost náklonu“ 2 → 0,5 → A/D reaguje líně; ↺ vrátí výchozí.
3. Paramotor: „Nahození – potřebný čelní proud“ 4,2 → 2 → křídlo se zvedne i při pomalém rozběhu; „Zavření křídla – od
   turbulence“ 1,1 → 0,1 → za letu se křídlo zavírá často. Trike: „Hmotnost – spolujezdec“ / „Motor – statický tah“ znát na stoupání.
4. Dron: „Let – rychlost“ (model) 15 → 30 → letí 2× rychleji; „Vítr – unášení v letu“ 0,6 → 2 → ve větru silně ujíždí;
   „Baterie – výdrž“ 720 → 60 → brzy varování a návrat domů.
5. Termika: „Ladění – pevná bublina nad hráčem“ 0 → 150 (léto, jasno) → paramotor / letadlo nad hráčem stoupá (vario pípá);
   „Bublina – nejsilnější stoupání v ose“ 3 → 6 → stoupá rychleji. Výchozí (skupina) vše vrátí, konzole bez chyb.
### M8.D2d – Zvěř

1. Režim vývojáře, F3 → Zvěř: podskupiny Pohyb a rig, Smysly a útěk, Druh – … (10 druhů), Ptáci a let, Hejna
   a murmurace, Hospodářská zvířata, Ostatní. Hledání „Froude“ najde prahy chodů všech druhů, „útěk“ útěk a pozor.
2. Kůň (nasednout F): Druh – Kůň „Chody – trysk: horní mez rychlosti“ 15 → 25 → v trysku hned znatelně rychleji;
   Hospodářská zvířata „Výdrž – úbytek v trysku“ ×4 → kůň se vyčerpá za pár sekund. ↺ vrátí výchozí.
3. Srnci (F2 → setkání se zvěří): Druh – Srnec obecný „Smysly – úniková vzdálenost“ 28 → 80 → utečou mnohem dřív;
   „Odrazové skoky – výška při útěku“ 0,95 → 2 → vysoké skoky. Smysly a útěk „Zrak – v noci ×“ 0,3 → 1 → v noci tě vidí jako ve dne.
4. Pohyb a rig (zvíře blízko kamery): „Páteř – největší boční ohyb“ 0,35 → 1 a Druh „Páteř – boční ohyb v zatáčce“ ×3 →
   v zatáčce se zřetelně prohne; „Chody – krok: podíl stojné fáze“ 0,64 → 0,9 → šourá se; „Uši – škubnutí“ 0,35 → 1.
5. Ptáci: Ptáci a let „Vrána – cestovní rychlost“ 11 → 25 → vrány létají výrazně rychleji; Hejna a murmurace „Boidy –
   váha soudržnosti“ 0,15 → 2 → letící hejno vran se drží v chumlu; „Vyrušení – vrány na zemi do“ 18 → 50.
6. Výchozí (vše) → vše zpět; konzole bez chyb; s desítkami zvířat v okolí výkon jako před krokem (F2 výkon /
   `--perfscene`, kategorie `animal`, `flock`).
### M8.D2b – Člověk a Činnosti

Kategorie **Člověk** (382 parametrů: Pohyb hráče, Tělo, Chůze a postoj, NPC a vesničané, Pes) a **Činnosti** (371:
Rybaření, Lov a balistika, Oheň a požáry, Těžba a řemesla, Návykové látky a efekty). Výchozí stav se nesmí lišit od hry
před krokem.

1. Bez zásahu do menu: chůze, sprint, skok, skluz, plavání, skateboard, rybaření, střelba, oheň a kácení se chovají
   stejně jako dřív (žádný parametr F3 není zvýrazněný, konzole bez chyb).
2. F3 → Člověk → Pohyb hráče: „Rychlost – chůze“ 4,6 → 9 a „Skok – rychlost výskoku“ 6,6 → 12 → hned rychlejší chůze
   a vysoký skok; „Skok – gravitace hráče“ 20 → 8 → skok jako na Měsíci; ↺ vše vrátí.
3. Člověk → Chůze a postoj: „Chůze – boční posun pánve“ 0,045 → 0,15 a „Chůze – protipohyb paží“ → 2 → hráč i vesničané
   se viditelně kolébají a mávají rukama; Člověk → NPC: „Hovor – pozdraví hráče do“ 3,2 → 15 → vesničan zdraví z dálky.
4. Člověk → Tělo: „Opilost – odbourávání alkoholu“ 0,15 → 2 → promile v HUD rychle klesají; „Chlad – prochládání“ ×10
   v zimě → HUD „prochladl jsi“ za chvíli. Pes: „Pes – všimne si hráče do“ 16 → 60 → pes běží za hráčem z dálky.
5. Činnosti → Rybaření: „Záběr – průměrná doba čekání“ 40 → 2 → záběr skoro hned; „Zdolávání – růst napětí při
   navíjení“ ×3 → vlasec praská. Lov a balistika: „Puška – úsťová rychlost“ 800 → 100 → kulka na 100 m výrazně padá;
   „Balistika – gravitace střel“ 0 → šíp letí rovně.
6. Činnosti → Oheň a požáry: „Zapálení – základní šance“ 0,9 → 0,05 → oheň skoro nechytne; „Ohniště – teplo končí v“
   3 → 10 m → hřeje z dálky. Těžba a řemesla: „Kácení – doba: základ“ 0,8 → 0,1 → kácení výrazně kratší. Výchozí (vše) → zpět.
### M8.D2c – Příroda

1. Režim vývojáře zapnout, F3 → Příroda: 11 podskupin (Počasí, Počasí – situace a přechody, Roční doby, Obloha a světlo,
   Vítr, Voda a půda, Mikroklima, Dřeviny a les, Pole a louky, Louže, stopy, Kouř a ostatní); konzole bez chyb `tune_priroda`.
2. Vítr: F2 → Počasí → Bouřka, F3 → Vítr „Nárazy – síla“ 2,2 → 5 → stromy a tráva se v nárazech ohýbají víc; „Nárazy –
   velikost chuchvalců“ 0,045 → 0,15 → vlny přes obilí drobnější. Dřeviny a les „Ohyb vegetace – citlivost: vysoká tráva“ 0 →
   vysoká tráva stojí (do 0,2 s).
3. Mikroklima: jasná bezvětrná noc (F2 → Datum, 3:00, Počasí Jasno), „Inverze – nejsilnější“ 7 → 15 → za herní hodinu
   ukáže HUD v údolí (u potoka) výrazně nižší teplotu než na kopci; F2 → Příroda – ladění → vrstva „teplota“ modřejší kotliny.
4. Obloha a světlo: „Expozice – adaptace do tmy“ 1 → 10 → při vstupu z poledne do tmy (F2 → čas 22:00) se oko „roztáhne“ hned;
   „Mlha – hustota v husté mlze“ ×3 při Počasí Mlha → dohled znatelně kratší.
5. Počasí: „Sníh – přírůstek pokrývky“ 0,35 → 2 a F2 → Počasí Sníh → pokrývka (HUD „sníh N cm“) roste rychle, stopy ve sněhu
   se objeví (Louže, stopy „Stopy – zapisují se od sněhu“). „Situace Jasno – vítr“ 2 → 15 při Jasnu → HUD „silný vítr“.
6. Voda a půda: déšť (F2 → Počasí Déšť) + „Odtok – CN: orná půda, skupina C“ 85 → 98 → po herní hodině F2 → Příroda – ladění
   → Průtoky ukáže vyšší Q a kalnost; ↺ vrátí. Výchozí (vše) → vše zpět, nic zvýrazněné.

## M8.11 – Fenologie a růst stromů v letech

Pozn.: fáze se počítají jednou za herní den (`eco_day`) ze sumy teplot (GDD, základ 5 °C) – po F2 změně data se rok hned
„rozběhne“ z klimatického normálu (+ odchylka roku). F2 → Příroda – ladění → „Fenologický kalendář (M8.11)“ ukazuje GDD,
data rašení / květu / zbarvení letos a tlačítka „Odchylka roku ±K“ (teplé / studené jaro). Vrstva mapy `fenologie`.
Barvy a olistění jsou v shaderu stromů (`pheno_lut`) – generované stromy (M8.8) i staré prototypy, zblízka i impostory.

1. F2 → Datum 20. 4., les u chaty (`--perfscene=les_jaro` má 25. 4.) → břízy a vrby světle zelené, buky teprve raší,
   duby a jasany holé; kalendář: bříza „raší 10.–15. 4.“, dub „GDD x/155“.
2. F2 → 15. 10. → javory červenooranžové, břízy žluté (začínají opadávat), smrky zelené, modříny zlátnou.
3. F2 → 10. 11. → modříny opadané (holé), duby ještě hnědé s listím, buky převážně opadané.
4. F2 → kalendář → „Odchylka roku +5 K“, pak Datum 15. 4. → bříza i buk raší výrazně dřív než v bodě 1 (kalendář i les);
   „Odchylka 0 K“ vrátí.
5. Sad / zahrady (`--perfscene=zahrady_zari` místo) 28. 4. → jabloně a třešně s bílými / růžovými květy v koruně. Pak
   F2 → Počasí → Teplota −4 °C přes noc (do 6:00), ráno teplotu na „podle klimatu“ → deník J → „ROK V PŘÍRODĚ“: „Pozdní mráz
   … spálil květy (jabloně…) v údolí…“; kalendář ukáže mráz údolí / svah v %. V září (F2 → 15. 9.) méně jablek než bez mrazu.
6. Údolní kotlina vs. jižní svah (vrstva `site_insol` / `site_cold`) koncem dubna → na teplém svahu rašení o pár dní napřed
   (porovnat stejný druh dalekohledem X nebo vrstvou `fenologie`).
7. Přeskočit Silvestr (F2 → 31. 12. 23:00, počkat do Nového roku, nebo F2 → Datum o 5 let dál) → za pár sekund jsou
   stromy o kus vyšší (porovnat výšku stromu dalekohledem / „Prohlédnout strom“ – věk +N let); deník „Les … o N let starší“.
8. Zasazená jabloň na vlhké louce (vrstva `vlhkost` modrá) → nezasychá i bez zálivky; v květu fenologie jako sad.
9. Esc → Nastavení → Realismus → vypnout „Fenologie a růst stromů“ → všechny listnáče zase raší a barví se naráz (Seasons),
   modřín se nebarví, květy v korunách zmizí; zapnout → zpět do herní hodiny.
10. F5 → F9 zachová kalendář, mráz a roky růstu (klíč `phenology`); starý save se načte (rozběh roku z klimatu, bez růstu).
    F3 → Příroda/Fenologie „Podzim – fotoperioda“ 2 → 8 v září → listí se do herní hodiny barví dřív.

Co změřit: `--perfscene=les_jaro,30` a `--perfscene=les_leto,30` (s přepínačem „Fenologie“ zapnutým / vypnutým).
Očekávání: CPU ≈ 0 ms za snímek (denní krok ~0,2 ms jednou za 48 s reálně, tabulka 16 × 32 texelů), GPU ≤ +0,1 ms
(3 texelFetch na vrchol, pár ALU na fragment listí). Po Novém roce / načtení savu s růstem: přeškálování ~150 stromů
za snímek přes `EcoClock.slice` (≤ 1 ms/snímek po dobu ~6 s) – změřit `--perfscene=les_leto` těsně po načtení savu.
## M8.12 – Plodiny a zahrada podle růstového modelu

Pozn.: záhony i pole rostou po herních dnech (denní krok o půlnoci; zahrada dožene přeskočené dny podle normálu).
Rychlé sezóny: spánek / F2 → Datum. Prohlídka záhonu = akce „Prohlédnout záhon“ (E na záhon).

1. Duben, zahrada: zrýt 2 záhony, zasadit brambory, jeden pravidelně zalévat (konev), druhý ne; F2 → Počasí Jasno
   opakovaně (sucho), spát do srpna → nezalévaný dá ~1–3 ks, zalévaný ~8–10 ks (horní mez 12 × 0,75 × výnos/normál).
2. Prohlídka záhonu během léta: „Brambory kvetou, půda je suchá. (55 %)“ + „Odhad úrody: 2–5 ks.“; s vyšším
   Zahradničením užší rozpětí odhadu.
3. Květen: rajčata venku i ve skleníku, F2 → čas 3:00, Počasí Jasno, teplota pod 0 °C (F2 → Počasí → Teplota −2)
   → do herní hodiny hláška „Mráz (−2 °C) zničil úrodu…“, venkovní záhony prázdné, skleník přežije.
4. Salát pod korunou stromu (nebo u zdi domu) vs. na slunci: prohlídka ukáže „· stín NN %“ a pomalejší postup %.
5. Pole s pšenicí (F2 → Teleport na pole, červen–červenec): v suchém roce (dlouho Jasno) dřív zlátne a je nižší než
   obvykle, strniště o 1–3 týdny dřív než ~27. 7.; v normálním roce barvy jako dřív.
6. Deník J → Počasí po sklizni: „Letošní úroda: suchý červen, ozimá pšenice slabá úroda (60 %), obilí se začalo
   žnout 12. 7.“ (jen měsíce / plodiny mimo normál; jinak „zatím běžný rok“).
7. F5 → F9 uprostřed sezóny: záhony (fáze, % i odhad) a barvy polí zůstanou; starý save (před M8.12) se načte – záhony
   pokračují podle starého % (převod na normál), pole podle normálu k dnešku.
8. Esc → Nastavení → Realismus → vypnout „Plodiny podle počasí“ → zahrada roste po růstových dnech jako dřív (hláška
   „Brambory – 40 % · vlhko …“), pole podle pevného kalendáře; zapnout zpět → pokračuje bez skoku.
9. F3 → Příroda/Plodiny a zahrada (379 parametrů): „Brambory – RUE“ 2,8 → 6 → za pár dní znatelně větší rostliny;
   „Stres vody – sucho od vlhkosti“ 0,35 → 0,8 → záhony vadnou i po dešti; ↺ vrátí. Konzole bez chyb `tune_m8_12`.
10. Kukuřice / slunečnice v září: pole dozraje a sklidí se podle sezóny (ne pevný den), za deště se nežne.

Co změřit: `tools/launcher.sh --perfscene=pole_pulnoc,30` (pole 15. 7. ve 23:51 – půlnoc a denní krok proběhne během
měření) a `--perfscene=pole_leto` proti stavu před M8.12, totéž s vypnutým přepínačem „Plodiny podle počasí“. Očekávání:
průměr CPU +≤ 0,05 ms (hodinový vzorek záření a teplot, ~100 buněk záhonu), ve snímcích po půlnoci špička +≤ 1 ms po
~22 snímků (12 polí za snímek, `EcoClock.slice`), jednou přepočet LUT polí (~1 ms) a stín záhonu (~300 paprsků,
≤ 2 ms jednorázově, jen u hráče); GPU beze změny (jedno násobení v `vegetation.gdshader`). Paměť ≈ 0 (255 malých slovníků).
## M8.13 – Terramechanika: bláto, zaboření, koleje

Pozn.: rozmáčenost bere vlhkost půdy z vodní bilance (M8.7) – ta se po startu staví ~30–40 s a déšť se do půdy
promítne po herních hodinách (F2 → 5 dní deště, nebo spát). Mapa M s vrstvou `vlhkost` / `unosnost` ukáže, kde je
niva mokrá a bořivá (červená). Kalibrace: osobní auto zapadne od rozmáčenosti ~0,6 na glejích / fluvizemích, traktor
projede i při plné; v suchu je odpor valení na louce ~0,05 × tíha.

1. F2 → Počasí Déšť, 5 dní (spát / posun času) → osobní auto na louku v nivě (vrstva `unosnost` červená) → zpomalí,
   kola klesnou, hrabe na místě, hláška „Zapadl jsi v blátě…“ do ~3 s.
2. Couvání / kývání (plyn ↔ brzda) → díra se zarovná, v okrajových místech se vyprostí; vystoupit a tlačit do auta
   (chůze proti karoserii) → auto bez řidiče se pohne / díra se zmenší.
3. Traktůrek na stejné louce → projede (pomaleji), za ním tmavé vyjeté koleje, za mokra s loužemi.
4. F2 → Jasno 3 dny → koleje pořád vidět (tmavé); F2 → týden deště → zmizí (rozmáčené).
5. Červenec, sucho, stejná louka → osobní auto projede bez potíží (rozjezd na trávě o kus horší než na asfaltu).
6. Chůze blátem po dešti → pomalejší, čvachtání místo kroků, vlastní stopy (tečky) v blátě; kůň v blátě zpomalí a nechá otisky.
7. Ruční vozík s dřevem přes rozmáčenou louku → jde těžko, pomalá chůze, rychleji dochází výdrž.
8. F5 → F9 → koleje zůstanou (klíč `ruts`); starý save se načte bez kolejí.
9. Esc → Nastavení → Realismus → vypnout „Bláto a koleje“ → auto na mokré louce jen klouže jako dřív, koleje se nekreslí.
10. F3 → Vozidla/Terén a bláto: „Půda pseudoglej / glej – k_φ (tření) – rozmáčeno“ 90 → 1000 → auto na glejové louce
    projede; ↺ vrátí.

Co změřit: `--perfscene=pole_blato,30` (déšť na poli; sednout do auta / traktoru a jezdit po poli – profil „car“) a
`--perfscene=pole_leto,30` s přepínačem „Bláto a koleje“ zapnutým / vypnutým. Očekávání: CPU +≤ 0,1 ms (hráčovo vozidlo:
4× pár `pow` za fyzikální krok, půda po 0,2 s; AI auta dál než 80 m nic; okno kolejí: přepis slotu ~0,5 ms jen při
přejezdu hranice 64 m, nahrání textury 768² při změně nejvýš 4×/s, mizení ~1 ms jednou za několik herních hodin
na dlaždici); GPU +≤ 0,1 ms (3–5 vzorků textury na pixel terénu do 120 m). Cíl kroku +≤ 0,3 ms CPU, +≤ 0,3 ms GPU.


## M8.14 – Přízemní vegetace: louky, seč, sukcese, interaktivní tráva

Pozn.: typy porostu potřebují nová data – jednou `python3 tools/vegetation.py --eco` (po `site.py` a `tree_species.py`;
bez toho běží stará `VEG1` vegetace a funguje jen seč, sukcese, sešlapání a pěšiny). Louky se po startu inicializují
po řádcích (~3–5 s), vrstva mapy `louky` (barva = typ, jas = výška, červeně roky bez seče) a `pesiny` ukáže stav.

1. `python3 tools/vegetation.py --eco` → v logu počty nových typů (vlhká louka, suchá stráň, kapradí, borůvčí, mech,
   jarní podrost, hrabanka, devětsil), typy luk a skupiny dřevin; součet ≤ 117 000.
2. Niva u potoka vs. jižní stráň (mapa M, vrstva `louky`: modrá vs. žlutá) → vlhká: vysoké trsy s fialovými hlávkami;
   suchá: nízké šedozelené trsy s drobnými fialovými květy.
3. Bučina vs. smrčina (vrstva `druhy`) → pod bukem holá rezavá hrabanka, skoro žádná líska; pod smrkem tmavé jehličí,
   mech, borůvčí, kapradí. Dubohabřina v dubnu (`--perfscene=les_jaro`) → bílé sasanky, v červenci nejsou.
4. F2 → 18. 6. → část luk na seno je posekaná (nízká, zelenější, vrstva `louky` tmavší), na čerstvě posekaných
   řádky sena; F2 → o 6 dní později → balíky. Tráva u obce posekaná už 20. 5. a 9. 7.
5. F2 → 20. 7. → posekaná louka zase dorůstá (vrstva `louky` světlejší), květy jen na neposekaných.
6. Chůze vysokou trávou (3. osoba) → tráva se od hráče rozhrnuje, za ním zůstane stopa, která se ~30 s narovnává;
   totéž kolem koně, kol auta, vesničana a srnce.
7. Chodit 10× tam a zpět stejnou trasou přes louku → prošlapaná hlína a nižší řidší tráva; F2 → posun o 3 týdny bez
   chůze → pěšina zaroste.
8. Neposekaná louka za obcí (vrstva `louky` – opuštěné parcely), F2 → +6 let → trnky a šípky, mladé břízy (borovice
   na suché stráni); Esc → Realismus → vypnout „Louky, seč a interaktivní tráva“ → tráva všude stejná a nehybná.
9. F5 → F9 → seč a pěšiny zůstanou (klíče `meadows`, `footpaths`); starý save se načte (louky podle data).
10. F3 → Příroda/Vítr – ohyb vegetace: „Tráva – ohyb ∝ F“ 0,55 → 1,5 při bouřce → tráva se ohýbá víc; ↺ vrátí
    (výchozí = dřívější vzhled). F3 → Příroda/Louky a podrost: „Sešlapání – síla sklopení“.

Co změřit: `--perfscene=louka_vitr,30` a `--perfscene=pole_leto,30` s přepínačem zapnutým / vypnutým a
`--perfscene=louka_cerven,30` (seno, keře, sešlapání – profil „groundveg“). Očekávání: GPU +≤ 0,6 ms (nové typy v rámci
LOD do 55–90 m; u rostlin do 40 m od kamery smyčka ≤ 48 zdrojů sešlapání; 1 vzorek `meadow_h` a 4 `path_tex` na vrchol,
terén 4 vzorky do 160 m), CPU +≤ 0,3 ms (zdroje 1× za 2 snímky ~0,1 ms, pěšiny po 0,4 s, přestavba keřů a sena jen po
posunu o 30 m ~1–2 ms; denní krok luk po 700 buňkách za snímek přes EcoClock).
## M8.15 – Ekologie a populace zvěře

Pozn.: mřížka stanovišť se po startu staví ~10 s (do té doby zvěř jako dřív), populace se založí po prvním denním
přepočtu (~10 s). Vrstvy mapy M `habitat_srnec` / `habitat_prase` ukazují vhodnost pro aktuální hodinu.

1. Červen, 20:30, okraj lesa u ozimu / jetele (vrstva `habitat_srnec` zelená na poli): srnci venku na poli; 12:00 tamtéž nikdo.
2. Červen, poledne, mladá houština (vrstva `habitat_srnec` sytá v lese) → projít porostem → zvedneš srnce z lože.
3. Leden se sněhem (F2 → Počasí sníh) → srnci u krmelců u chaty a v závětří (jižní svahy), ne v kotlině za mrazu.
4. F2 → Příroda – ladění → Populace zvěře: čísla po honitbách; ulovit 5 srnců (F2 lov / puška) → „Srnec“ v honitbě o 5 níž, „lov hráč 5“.
5. F2 → posunout datum o rok (přes jaro) → srnců zase víc (mláďata V–VI ve sloupci „mláďata“).
6. F2 → Populace → Vynutit semenný rok, říjen–listopad, noc → prasata v bučinách / doubravách (vrstva `habitat_prase` v noci).
7. F3 → Zvěř/Populace a škody → „Škody – rozrytí louky u lesa“ 0,06 → 0,5, posunout o pár dní → tmavá rozrytá místa na loukách u lesa; drb vesničana „Prasata zas rozryla louku…“.
8. F5 → F9 → populace, žaludy a rozrytá místa zůstanou (klíč `wildlife`); starý save se načte (populace z kapacity).
9. Esc → Nastavení → Realismus → vypnout „Stanoviště a populace zvěře“ → zvěř jako dřív (stará stanoviště, pevné okrsky).
10. Deník J → „Zvěř v honitbách“ (odhad, se zvyšující se Myslivostí přesnější), semenný rok.

Co změřit: `--perfscene=zver_pulnoc,30` (denní přepočet během měření) a `--perfscene=pole_leto,30` se zapnutým / vypnutým
přepínačem. Očekávání: průměr CPU +≤ 0,1 ms (dotazy zvěře jen při rozhodnutí vůdce, sken setkání po 3 s), po půlnoci
~10 s přepočtu po 32 buňkách za snímek (+≤ 0,4 ms v těch snímcích), po startu ~10 s statické mřížky (48 buněk, stromy
v buňce, +≤ 1 ms). Cíl kroku +≤ 0,3 ms průměr. Paměť ≈ 1 MB (mřížka 64 m).

## M8.17 – Život vesnice: domácnosti, potřeby, vztahy, drby

Pozn.: plán domácností se počítá jednou za herní hodinu (po kouscích, 8 domácností za snímek) – po skoku času (F2 → Datum /
čas) chvíli trvá, než se okna a komíny srovnají. F2 → Příroda – ladění → **Domácnosti** ukáže nejbližší domy (kdo bydlí, co
dělá, potřeby, dřevo, síla kouře, poslední drb), vrstva mapy **`obyvatele`**: žlutá vzhůru doma, modrá spí, zelená práce
u domu, červená nikdo doma, šedá neobydlený dům.

1. F2 → leden, 6:00 → 7:00 (jasno) na návsi → mezi 6:00 a 7:00 se v domech rozsvěcují kuchyně (ložnice krátce po probuzení),
   komínů kouří víc a hustěji (ranní přiložení); prázdné domy zůstanou tmavé.
2. 23:30 → svítí jen pár oken (ložnice před spaním, „noční sovy“), komíny slabě / jen některé.
3. Sobota v říjnu dopoledne → u několika domů je slyšet štípání (sekera), vesničan s modelem stojí na dvoře a štípe;
   Domácnosti → „štípe dřevo“, „hrabe listí“.
4. Neděle v létě dopoledne → sekačka nikde (nedělní klid), v sobotu ano (zvuk pily s nízkým tónem u domů).
5. Srazit srnce autem (M2.9) → za 1–2 herní dny vesničan na druhém konci obce na E řekne „Včera prý ten z č. p. … srazil
   autem srnce…“ (napřed to vědí sousedé místa, pak hospoda).
6. Domácnosti → vybraný dům: členové s rolí, prací, činností, vstáváním / ulehání a potřebami; dřevo v prms a kouř.
7. Sníh (F2 → Sněžení + posun o den) → u osamělého seniora odklizeno a drb „odházeli … sníh u …“.
8. Klepání na dům v noci / ve dne → otevře obyvatel z domácnosti, když je doma (v práci nikdo neotvírá); F5 → F9 →
   zásoba dřeva, drby a změněné vztahy zůstanou (klíč `households`); starý save se načte (domácnosti podle seedu).
9. Esc → Nastavení → Realismus → vypnout „Život vesnice“ → okna a komíny jako dřív podle pravděpodobnosti, vesničané
   vyjdou z domů a procházejí se; zapnout → do hodiny zase podle plánu.
10. F3 → Člověk/Život vesnice: „Rozvrh – vstávání seniora“ 6,1 → 9 → ráno se seniorské kuchyně rozsvítí později; ↺ vrátí.

Co změřit: `--perfscene=ves_poledne,30` se zapnutým / vypnutým „Život vesnice“ (profil „villager“ a celkové ms procesu),
`--perfscene=ves_rano_zima,30` (v 7:00 proběhne hodinový krok domácností – špička snímku) a `--perfscene=ves_sobota_rijen,30`
(zvuky, vesničané na dvorech). Očekávání: průměr +≤ 0,1 ms CPU (hodinový krok ~220 domácností po 8 za snímek ≈ 0,3–0,6 ms
jen ~30 snímků za herní hodinu; okna = přepis textury ~300 texelů 1× za herní půlhodinu; vesničané doma bez fyziky =
úspora), špička ≤ 1 ms; GPU ≈ 0 (jedno `texelFetch` na vrchol okna). Cíl kroku +≤ 0,3 ms. BT zůstává na 5 vesničanech
(F3 → `village.bt_villagers`) – zapnout pro všechny až po měření `ves_poledne` s hodnotou 28.

## M8.18 – Zvuková krajina a drobný život

Pozn.: zvuky se syntetizují ve vlákně při startu (~2–3 s) – první vteřiny po načtení může být ticho. Bez hráče venku
(interiér −20 dB, auto −12 dB) je krajina tlumená. Přepínač: Esc → Nastavení → Realismus → „Zvuková krajina a drobný život“.

1. F2 → 10. 5., 4:45, jasno, teleport do lesa (scéna `les_rano_kveten`) → nejdřív kos, za 10–20 min červenka a drozd,
   kolem východu (~5:20) sýkory, pěnkavy, budníček, hřivnáč; kukačka z dálky.
2. 15. 1., 12:00 v lese → skoro ticho: občas sýkora, vrána, bubnování strakapouda; žádný kos.
3. 20. 7., 21:30 na louce, 25 °C → rychlé cvrkání (~2,4 cvrknutí/s) a kobylky; F2 → teplota 15 °C → pomalejší (~1,2/s).
4. 20. 4. ve 20:40 u rybníka (`rybnik_soumrak`) → skokani a ropuchy kvákají; komáří kňourání u vody.
5. Soumrak u rybníka / v obci u lamp (duben–říjen, nad 8 °C, bez deště) → netopýři létají cikcak nad vodou a v obci.
6. 25. 6. ve 22:30 na okraji lesa, teplo, bezvětří (`les_cerven_noc`) → blikající světlušky u země; puštík z lesa.
7. Louka v červnu v poledne, jasno → motýli (bílí, oranžoví, žlutí, modří) nad loukou a bzučení louky; v dešti zmizí.
8. Hustý les → vzdálené ptáky slyšet tlumeně (bez výšek); v údolí ozvěna. Smrčina syčí, bučina šustí (silnější vítr).
9. Deník J → Pozorování přírody → „Nově uslyšeno: Kukačka…“, netopýr, světluška, motýl zapsané s datem (+XP Myslivost).
10. Sobota v říjnu dopoledne v obci (`ves_sobota_rijen`) → sekačka zní jako motor (ne zpomalená pila), hrabání listí;
    po sněžení odhazování sněhu lopatou. F3 → Příroda/Zvuková krajina → `Cvrčci – Dolbear` ovlivní rychlost cvrkání.

Co změřit: `--perfscene=les_rano_kveten,30`, `--perfscene=rybnik_soumrak,30` a `--perfscene=les_cerven_noc,30`
se zapnutou / vypnutou „Zvukovou krajinou“ – profily „soundscape“ a „small_life“. Očekávání: průměr +≤ 0,2 ms CPU
(výběr zdrojů 2×/s ~0,3–0,8 ms jednou za 30 snímků, za snímek jen 16 hlasů a 5 prolnutí), GPU ≈ 0 (5 MultiMesh, ≤ 160
instancí, unshaded). Syntéza zvuků běží ve vlákně (bez záseku hlavního vlákna). Taky `les_rano_mlha` (cíl +≤ 0,2 ms).
