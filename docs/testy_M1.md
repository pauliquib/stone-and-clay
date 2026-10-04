# Checklisty ručních testů – M1 Živý svět

## M1.1 Terén bez ortofota
1. (Volitelně) `python3 tools/surface.py` → vznikne `data/surface.bin`, výpis tříd v % katastru (les by měl být řádově desítky %, orná půda a louky podle OSM). Bez něj hra běží s fallbackem.
2. `./run.sh` → u domu hráče: tráva, dvůr, cesta; žádné fotografické skvrny aut / střech na zemi, hranice tříd nejsou čtverečkované.
3. F2 → Teleport → do lesa: lesní podrost; na pole: pole s plodinou podle data (barvy jako dřív, jen na ornici).
4. Strmý svah / okolí potoka: nad ~35° skála / hlína, méně trávy nad ~20°; břeh potoka vlhčí a tmavší.
5. F2 → Roční období: leden (sníh), červenec, říjen – tráva hnědne mimo sezónu, sníh a mokro (déšť) fungují.
6. F2 → „Terén: procedurální“ → přepne na ortofoto (vzhled jako dřív) a zpět; hra při tom nespadne.
7. M (mapa) → čitelná mapa z barev tříd (pole, les, zástavba) i bez ortofota; po přepnutí na ortofoto se podklad mapy vrátí.
8. Pohled do dálky (kopec, 1 km+): žádné blikání ani zřetelné dlaždice, vzdálený terén má jen barvu tříd.
9. Výkon: FPS podobné jako dřív; načtení světa se nepředlouží o víc než ~2 s (minimapa se generuje při startu).
10. (Až po stažení textur do `assets/textures/terrain/`, viz `ASSETY.md`) tráva, ornice, les a skála mají texturu; s částí souborů chybějících se použije barva + šum.

## M1.2 Okna, dveře, komíny
1. `python3 tools/buildings.py` → vznikne `data/buildings.json`, výpis počtu budov podle typu (house, shed, garage, barn…), míst (`hospoda=…`) a domova. Bez souboru hra běží beze změny (žádná okna).
2. `./run.sh` → u domu hráče a v obci: domy mají okna (u vyšších dvě patra), dveře na straně k silnici se schodem, na některých domech komín na hřebeni. Okna a komíny sedí na stěnách / střechách (nic nevisí ve vzduchu ani není zabořené).
3. Přibliž se k oknu: sklo je tmavé, neprůhledné, s odleskem; většina oken má záclonu v horní části; příčky ve tvaru kříže; nikde není vidět dovnitř.
4. F2 → Denní doba 20:00 (přes zimní datum, ať je tma) → část oken svítí teplou barvou; 03:00 → skoro žádné; 06:00 → některá; 12:00 → žádné. Při změně času se svícení přepočte do ~1 s.
5. Hospoda a Potraviny: dveře jsou tam, kde se ukazuje nabídka E (bod `door_x/z`); totéž dveře domu hráče u spawnu.
6. Garáž / stodola → vrata (rovný panel se dvěma pruhy), žádný komín; kůlna → nanejvýš jedno malé okénko, bez dveří a komína.
7. Sousedící budovy (řadová zástavba, přístavky): žádná okna uvnitř sousední budovy na společné zdi.
8. Vzdálené budovy (> ~450 m) jsou bez oken a komínů (mizí najednou); FPS v obci podobné jako dřív; načtení světa se nepředlouží o víc než ~2 s.
9. Konzole (výstup) bez chyb typu „shader“ / „Invalid access“ při startu; F2 → přepnutí data / počasí nic nerozbije.

## M1.3 Kouř z komínů
1. F2 → Datum leden, Počasí Jasno, Teplota −10 °C, čas 7:00, jdi do obce: skoro všechny komíny (na domech se sedlovou střechou) kouří, sytě a při zatápění tmavší; 12:00 světlejší.
2. F2 → Teplota +10 °C: kouří jen některé domy; +20 °C: jen výjimečně (pár komínů z celé obce).
3. F2 → Počasí Bouřka: kouř se ohýbá po větru a trhá se, leží níž.
4. F2 → Počasí Mlha (ráno): kouř stoupá jen pár metrů a rozlévá se nízko nad střechami.
5. F2 → Počasí Déšť: kouř je méně viditelný a kratší.
6. Stůj u jednoho domu 2 herní hodiny (F2 → rychlost 20×): kouř nepřeskakuje mezi domy (mění se jen při změně teploty nebo denní doby); po půlnoci (nový den) se výběr domů změní.
7. Noc: kouř není zářivě šedý, ale ztlumený. F2 → Teplota podle klimatu / Počasí Automaticky vrátí přirozenou teplotu.
8. Bez `data/buildings.json` hra běží bez chyb a bez kouře.
9. FPS v obci s kouřem podobné jako bez něj (max. 24 emitorů); konzole bez chyb typu „Invalid access“ / shader.

## M1.4 Systém interiérů + domov
1. `./run.sh` → dveře domu hráče (bod u spawnu; s `buildings.json` i dveře modelu, hlásí „Vchod domů“) → E → první položka „Vejít dovnitř“ → krátké ztmavení (~0,3 s), stojíš v předsíni, dveře za zády.
2. Projdi místnosti (předsíň → obývák, kuchyň, ložnice přes dveře v příčce): nábytek v reálných rozměrech (linka 0,9 m, postel 1,6 × 2 m), nic neprochází zdí, kamera 3. osoby nezajíždí za stěny (V = 1. osoba), z dveřních otvorů nejde propadnout ven.
3. Postel → „Vyspat se (do 7:00)“ → ztmavení, ráno hláška, zdraví se doplní jako dřív; „Zdřímnout si“ a (přes den) „Odpočívat do večera“ fungují.
4. Lednička (rohlíky, chleba, voda), kávovar (kafe), dřez (voda; při silné opilosti „Vyzvracet se“) → nabídky fungují; kamna, šatní skříň a PC hlásí „(brzy)“.
5. Komoda v obýváku: rádio stojí na ní, E → ovládání jako dřív, hudba je slyšet uvnitř; po odchodu ven stojí rádio zase na zahradním stolku u dveří a hraje dál.
6. F2 → Počasí → Déšť, stůj uvnitř 10 min → nepromokneš, nad hlavou neprší, déšť je slyšet jen tlumeně; venku za dveřmi prší a mokneš.
7. F2 → Denní doba 22:00 → uvnitř svítí stropní světla a lampa, okna jsou tmavá; 12:00 → okna světlá, světla slabá.
8. E u vnitřních dveří („Vyjít ven“) → ztmavení, stojíš ~1 m před dveřmi domu otočený od domu; policejní auto / zvěř / provoz se během pobytu uvnitř nechovají divně (žádné auto se neteleportuje pod zem, hlídka nejezdí mimo mapu).
9. Uvnitř F5, vyjdi ven, F9 → znovu uvnitř na stejném místě (rádio zpět v interiéru); F2 → Teleport → „Domov – uvnitř“ funguje i z auta; H uvnitř tě vrátí ven ke spawnu.
10. Bez `data/buildings.json` (nebo s ním): vstup i odchod fungují (fallback na bod `door_x/z` z `pois.json`); konzole bez chyb typu „Invalid access“ / „shader“.

## M1.5 Interiéry veřejných budov
1. `./run.sh` → F2 → Denní doba 18:00 → Teleport k Hospodě U Hřiště → E u dveří → první položka „Vejít dovnitř“. Uvnitř: výčep s pípou u východní stěny, hostinský Láďa za pultem, 3 štamgasti sedí u prvního stolu; E u pultu → stejná nabídka jako dřív, kup pivo (funguje ubírání peněz, promile).
2. F2 → datum na pátek, 20:00 → do hospody: u druhého stolu přibudou 3 hosté; v sobotu 20:00 tam nejsou. Za průchodem uprostřed příčky je sál s pódiem, reproduktory a stoly (na pódium jde vyjít po schůdku – když ne, napiš).
3. F2 → Roční období červenec, 14:00, jasno → štamgasti sedí venku na zahrádce (uvnitř nejsou); v lednu / za deště / večer po 22:00 zahrádka zeje prázdná a sedí uvnitř. Pátek večer: hosté jsou vždy uvnitř.
4. Potraviny → „Vejít dovnitř“: prodavačka Jarka za pokladnou, 4 regály, vitrína, košíky; E u pokladny → nákup funguje; pult zavírá cestu za prodavačku.
5. Obecní úřad v 18:00 → E u dveří: „ZAVŘENO – dveře jsou zamčené“, žádné „Vejít dovnitř“ a ukáže otevírací dobu; v 10:00 dovnitř: chodba, přepážka (obsluha), kancelář starosty bez vlajky a znaku, úřední deska (E).
6. Pálenice, vinný sklep, myslivecká chata → vejít (v otevírací době), obsluha stojí uvnitř, E → nabídka; v chatě krb, parůžky, palandy (E = jen dekor), venku pod přístřeškem palanda stále slouží k noclehu.
7. Stůj v hospodě až do zavírací doby (nebo F2 → 1:00 v neděli po půlnoci → uvnitř): obsluha řekne „Zavíráme“ a po ~6 s tě vyvede ven; dveře jsou pak zamčené.
8. Pověst „postrach vsi“ (F2 → Hráč, pokud jde nastavit; jinak přeskoč) → „Vejít dovnitř“ se nenabídne, dveře tě nepustí (hláška); F2 → Teleport dovnitř a E u obsluhy → obsluha tě vyhodí ven.
9. Úkol „Páteční pivo“ (nebo jiný úkol s hospodou / obchodem) → cíl a počítání piv fungují i tehdy, když pivo piješ uvnitř; po odchodu ven stojí hostinský zase u dveří.
10. F5 uvnitř hospody, vyjdi, F9 → jsi zpět uvnitř, obsluha za pultem; konzole bez chyb „Invalid access“ / „Identifier not declared“; bez `buildings.json` vstup i odchod fungují (fallback na `door_x/z`).

## M1.6 Nová vozidla a bazar
1. `./run.sh` → F2 → Vozidla → přistav postupně Bednář, Lesák, Rodinku, Traktůrek, Pionýrek, Včelku: vozidlo stojí vedle tebe koly na zemi, dá se nastoupit (F), postava sedí na správném místě, světla (L) svítí. Zrychlení a řazení odpovídají typu (dodávka a pickup pomalejší rozjezd, kombi svižné).
2. Pionýrek (moped) a Včelka (skútr): naklánějí se do zatáček, stojí na stojánku, nohy na pedálech / podlážce; při nárazu jezdec spadne. Pionýrek max. ~45 km/h (2 stupně), Včelka ~85 km/h.
3. Traktůrek: max. ~30 km/h, silně se rozjíždí, vyjede do kopce na louku; sedí se vysoko pod stříškou, výfuk trčí nahoru, vzadu je oj.
4. Lesák: vzadu je otevřená ložná plocha (tmavá podlaha, boční lišty); Bednář a dodávka nemají zadní okna.
5. Pozoruj dopravu ~10 min (F2 → rychlost času ×1): mezi osobními občas jede dodávka / pickup / kombi; v dubnu–říjnu ve dne (F2 → datum např. 15. 6., 10:00) po čase přijede traktor po okresce / polňačce (pokud graf silnic okresku poblíž má – jinak se neobjeví); v zimě nebo v noci ne.
6. Bazar: F2 → Teleport → „K bazaru vozidel“ → u cedule „BAZAR“ E → nabídka 3–5 vozidel (rok, cena, poškození, skupina ŘP). Kup vozidlo (F2 → Hráč → +5 000 Kč, případně vícekrát pro dražší) → peníze ubudou, vozidlo stojí u domu hráče (Teleport → Domů), nabídka o něj přijde.
7. Přejeď koupeným vozidlem k ceduli, vystup, E → Prodat moje vozidlo → dostaneš ~60 % ceny (poškozené míň); vozidlo zmizí. Rodinná vozidla (Oktávka, kolo, Javor) v nabídce výkupu nejsou.
8. F2 → Datum o týden dopředu → nabídka bazaru je jiná; do týdne zůstává stejná i po opuštění menu a návratu.
9. Kup dvě vozidla, F5, F2 → Datum jinam / prodej jedno, F9 → obě koupená vozidla stojí, kde jsi je nechal, s poškozením; když jsi v jednom seděl, sedíš v něm znovu. Nový přístav: konzole bez chyb „Invalid access“ / „Identifier not declared“.
10. Bez dat z tools/ hra běží beze změny (bazar se sám přichytí k nejbližší silnici u návsi; `Bazaar.HINT` lze doladit).


## M1.8 Interiéry všech budov se streamováním
Předpoklad: `python3 tools/buildings.py` (vznikne `data/buildings.json`; `run.sh` ho při chybění dogeneruje sám), pak `./run.sh`, nová hra (Esc nebo F2 → „Nová hra“, nebo čisté spuštění bez uložení).
1. Start u bytového domu → E u vchodu → „Vejít dovnitř“ → chodba bytového domu (přízemí: schránky, nástěnka, cedulky „Byt N“, schodiště). E u schodů → vyber patro s tvým bytem (číslo ukazuje F2 → Teleport „Domů (byt N v č. p. …)“) → E u dveří „Byt N“ → byt z M1.7 (radiátor). E u dveří bytu → zpět do chodby před dveře bytu; přízemí → E u vchodu → ven před dům.
2. Cizí rodinný dům (cedulka č. p.) → E u dveří → „Dveře – č. p. X (zamčeno, zaklepat)“ → Zaklepat → „Klep, klep…“ → „Nikdo neotvírá“ nebo odpověď obyvatele (jméno + věta); když otevře, vejdeš do generovaného domu (chodba, obývák, kuchyň se stolem, ložnice, koupelna). Klepni znovu do hodiny → „Pořád klepete?“; v noci (F2 → Denní doba 23:00) otevře jen přítel.
3. Uvnitř pozván: obyvatel sedí u stolu v kuchyni (jméno nad hlavou) → E u něj = drb; E u stolu → posadíš se na ~6 s, obyvatel něco řekne; E u vchodu → ven před dveře. Zůstaň uvnitř a F2 → čas +3 h → „Pozvání vypršelo“ → po ~6 s tě vyvede ven.
4. Náves: F2 → Teleport → Obecní úřad, zapni FPS (F2) a projdi ulicí kolem domů tam a zpět (~300 m): žádné záseky u dveří, FPS jako před M1.8 (zapiš před / po). Volitelně v editoru (Remote) pod „Interiery“ nejvýš 3 uzly `Interier_*`.
5. Hospoda a Potraviny: E u dveří → „Vejít dovnitř“ → interiér jako dřív, obsluha za pultem, štamgasti (mimo léto) u stolu, nákup, odchod; mimo otevírací dobu zamčeno. Na zahrádce v zimě nikdo nesedí.
6. Hospodářská budova u usedlosti (F2 → Teleport → K výběhu koně) → E u vrat stodoly / garáže → hala s ponkem, nářadím na desce, regálem, senem / pneumatikami / dřevem; cizí stodola daleko od usedlosti → „Zamčeno“.
7. F5 v chodbě v 1. patře, v bytě a v cizím domě (pozván) → F9 → hráč je uvnitř správné budovy (v cizím domě ho nikdo nevyhodí hned).
8. Staré uložení z doby před M1.8 uložené uvnitř domova / hospody → načte se uvnitř, bez chyb.
9. Bez `data/buildings.json` (dočasně přejmenuj): hra běží, domov = podnájem v usedlosti → „Vejít dovnitř“ → chodba (2 byty) → byt 1; veřejné budovy fungují.
10. Konzole bez chyb „Invalid access“ / „Identifier not declared“ / „Cannot infer the type“.
