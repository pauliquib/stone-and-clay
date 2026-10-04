# Stone & Clay – herní verze mapy (MVP)

Open-world MVP v **Godot 4.3** nad mapou celého katastru obce Dukelčic
(`mapa_okoli.blend` – terén DMR 5G, budovy s výškami z DMP 1G,
silnice z OSM, ~21 800 stromů; barva terénu je procedurální, ortofoto ČÚZK jen na přepnutí).

> *„Tato hra je satirickým uměleckým dílem. Všechny postavy, události a vyobrazené soukromé objekty
> jsou smyšlené. Jakákoliv podobnost se skutečnými osobami či konkrétními obydlími je čistě náhodná.“*

## Spuštění

```bash
./run.sh            # nebo: godot --path stone-and-clay
```

První spuštění naimportuje textury (~30 s). Načtení světa trvá ~2 s.

## Ovládání

| klávesa | pěšky | v autě |
|---|---|---|
| WASD / šipky | chůze | W plyn, S brzda / couvání, A/D řízení |
| myš | rozhlížení (klikni do okna) | rozhlížení kamerou |
| Shift | sprint (výdrž) | – |
| Mezerník | skok (delší stisk = výš) | ruční brzda |
| Ctrl / C | přikrčení, ve sprintu skluz | – |
| V | 1. ↔ 3. osoba | kamera za autem ↔ z interiéru |
| kolečko myši | vzdálenost kamery | – |
| E | interakce: místo (nabídka, nákup, úkoly; u domova a veřejných budov „Vejít dovnitř“, uvnitř postel, obsluha u pultu, lednička, kafe, rádio, **počítač** (M3.4, Esc = vypnout), vyjít ven), bankomat, balík u dveří, dveře ostatních budov (M1.8: vejít / zamčeno → zaklepat; v bytovém domě schodiště a dveře bytů, u stolu posedět), děda, Pepa, vesničan (drby), policista, nocleh (seník, palanda) | – |
| T / Enter | **říct něco nahlas** – napíšeš větu, odpoví nejbližší postava (nebo ta, kterou oslovíš jménem); `!!` nebo VELKÁ PÍSMENA = křik (slyší dál) | také |
| F5 / F9 | rychlé uložení / načtení pozice (další pozice v menu F2) | také |
| F | nastoupit do svého auta (do 4 m) / nasednout na dědovo kolo či motorku (do 2,6 m) / na koně (do 3 m) | vystoupit / sesednout (do ~7 km/h, kůň do ~5 km/h) |
| L / B / N / R | – | světla (na kole dynamo) / klakson (na kole zvonek) / stěrače / postavit převrácené vozidlo |
| G | **náklad** (M2.10, sdílená klávesa – DOPLNIT: G zůstává i hvízdnutím): u zvěře, špalku nebo pytle (do 3 m) ho zvedne na rameno, s nákladem na rameni ho u auta / vozíku naloží, jinak položí; těžký (divočák) naloží rovnou na vozík / do auta u sebe. **Když u tebe nic k nesení není, hvízdne na koně** – kůň do 300 m přiklusá po zemi k hráči (ze zavřeného výběhu brankou) | – |
| E u ručního vozíku / auta | **vozík**: uchopit oj a táhnout (znovu E: pustit / pustit se zabrzděním / plachta / vyložit); **auto**: „Vyložit z vozidla“ | – |
| X (držet) | **dalekohled** – zorný úhel 72° → 12°, pomalejší myš, tmavé okraje (jen pěšky) | – |
| Q | **další nástroj v ruce** (prázdné ruce → nástroje z inventáře v pořadí katalogu → prázdné ruce); nástroj je vidět v pravé ruce a vpravo dole „V ruce: …“ | – |
| 1–5 | rychlý slot nástroje (prvních 5 nástrojů v inventáři; stisk už drženého ho schová) | – |
| levé tlačítko myši | **spustí kontextovou akci** (výzva dole „[LMB] Natrhat trávu (Zahradničení 1)“, šedě s důvodem, když nejde); akci přeruší pohyb, skok, nabídka, výměna nástroje; **rybaření** (udice v ruce, pohled na vodu): LMB nahodí, při záběru zasekne, při zdolávání se drží = navíjí; **zbraň v ruce** (luk / kuše / puška): LMB = výstřel (luk: držet = natahovat, pustit = vystřelit) | – |
| pravé tlačítko myši (držet) | **míření se zbraní v ruce**: kamera se přiblíží (luk / kuše 45°, puška s optikou 9° jako dalekohled), pomalejší chůze a myš, muška kolísá; **Shift při míření = zadržet dech** (3 s klidnější, pak horší) | – |
| Tab | inventář seskupený podle druhu, nahoře „Neseš x / 25 kg“ (napít se, sníst, zapálit si, rozložit spacák, **obléct / svléct** oblečení – 5 s) | |
| I | **oblečení** – přehled, co máš na sobě (izolace, nepromokavost, štítky); převléknout jde doma ve skříni (E) nebo v inventáři (Tab) | |
| J | deník úkolů a statistika; Backspace v deníku = vzdát úkol | |
| K | dovednosti (16 dovedností, úroveň 1–50, postup a XP do další úrovně; oddíl je i v deníku J) | |
| M | mapa katastru (místa ★, cíl úkolu) | |
| H | zpět domů (k bytu / domu, kde bydlíš – M1.7) | |
| U | **vysvobození ze zaseknutí** – přenese na poslední místo, kde jsi stál volně (když uvízneš mezi nábytkem / ve dveřích); když tam něco překáží, zkusí vchod interiéru, jinak spawn | – |
| F1 | nápověda | |
| Esc | **pauza** (v singleplayeru se hra zastaví): pokračovat, uložit / načíst hru, nastavení (citlivost a obrácení myši, FOV, hlasitost, celá obrazovka, vsync, FPS; **Grafika a výkon**: předvolba Nízká/Střední/Vysoká/Ultra/Vlastní, rozlišení 3D + FSR 1/2, vyhlazování, stíny, dohlednost, vegetace, záře, SSAO, strop FPS – vše v `user://nastaveni.cfg`), ovládání, herní menu, hlavní menu (připravujeme), ukončit hru; otevře se i při ztrátě fokusu okna | také |
| F2 | **herní menu**: uložit / načíst hru, roční období a datum, denní doba, rychlost času, počasí, přistavení vozidla / koně, teleport, hráč (vystřízlivět, uzdravit, peníze), **Terén: procedurální / ortofoto** (přepínač vzhledu terénu i podkladu minimapy) | |

**Na koni:** W jet (drž), Shift pobídnout o chod výš (krok → klus → cval → trysk), S o chod níž / zastavit /
couvat (drž), A/D otěže, Mezerník skok (od klusu), myš a kolečko kamera, V pohled jezdce, F sesednout.
Koně je třeba **krmit a napájet** (E u žlabu / napáječky ve výběhu nebo u koně): nakrmený kůň rychleji obnovuje
výdrž, hladový či žíznivý nejde do trysku; vyčesání (E u koně, 3 s) dá krátký bonus. **Opilý jezdec:**
nad 0,5 ‰ kůň sám zpomalí (max. klus) a jezdec může spadnout, nad 1,5 ‰ kůň nevyjde. Jezdec na koni je
účastník provozu – hlídka ho může zastavit a dát dýchnout jako řidiče (pokuta a zákaz řízení stejné).

Funguje i herní ovladač (levá páčka = chůze, pravá = rozhlížení, A = skok, B = přikrčení, stisk levé páčky = sprint, Y = pohled, Back = mapa).

**S dronem (M6.1):** start z inventáře (Tab → detail dronu → *Vzlétnout*). WASD let vpřed / do stran,
myš = otáčení dronu a naklápění kamery (pravá páčka ovladače taky), Mezerník stoupat, Ctrl klesat,
Shift sportovní režim, kolečko = zoom kamery, V = pohled z kamery dronu ↔ za dronem,
O nebo levé tlačítko = **fotka** (ukládá se do `user://fotky_dron/`), F = přistát / návrat domů (RTH).
OSD vlevo dole ukazuje výšku AGL, rychlost, vzdálenost od pilota, baterii, signál a varování.

**V letounu (M6.3):** nastup a vystup klávesou F (jen na zemi a v klidu). W/S = plyn (na zemi rozjezd,
vzlet sám při v_min ≈ 25 km/h), A/D = překlápění → zatáčení, Mezerník = zatáhnout / na zemi brzda,
Ctrl = přiklonit, V = kamera za strojem ↔ pohled pilota, myš = volný pohled (sám se vrací).
Letoun drží auto-trim rychlosti; zpomalíš-li pod v_min, přetáhne se (výstraha, nos padne dolů).
Letecký panel vlevo dole ukazuje ALT MSL, AGL, IAS, zemskou rychlost, **variometr** (pípá ve stoupání),
kurz, šipku větru a palivo. Palivo chřadne s plynem; s prázdnou nádrží jen klouzavý let a přistání.

**S paramotorem (M6.4):** křídlo se rozloží z batohu (Tab → detail → *Připravit k letu* – rovná louka,
sklon < 10°, ~50 m bez stromů). F = navléct nosiče. **Start:** otočit se čelem *proti* větru (šipka na
přístrojích) a rozběhnout (W) – křídlo se zvedne nad hlavu; boční vítr nebo slabý rozběh ho shodí na
stranu, vítr > 8 m/s křídlo vytrhne. Pak plyn (Shift) a doběhnutí vzletu. **Let:** A/D = levá/pravá
brzda (zatáčení), S = obě brzdy (zpomalení; dlouhý hluboký tah = propad křídla), W nebo Shift = plyn,
držený Mezerník = povolené trimry (větší rychlost), Ctrl = „uši“ (rychlejší klesání). V turbulenci se
křídlo může částečně zavřít (propad na stranu) – srovná opačná brzda. **Přistání:** proti větru, se
staženým plynem, ve výšce ~1 m obě brzdy naplno (flare) → dosednutí na nohy a doběh. E u ležícího
stroje = složit křídlo zpátky do batohu (25 kg). Průkaz (`pilot_pg_motor`), registrace a pojištění:
počítač doma → *Letectví – ÚCL* (škola 35 000 Kč: eTest „paramotor“ + 5 výcvikových vzletů).

**S motorovým rogalem / trikem (M6.5):** ojetý stroj koupíš na inzertní ceduli u hangáru polního
letiště (dráha ~260 m jihozápadně od návsi; F2 → Teleport → *Letiště*), případně F2 → Vozidla.
F = nastoupit do předního sedadla. **Plyn drží páka:** Shift přidat, Ctrl ubrat (poloha zůstává,
na přístrojích „PÁČKA %“). **Na zemi** A/D = řízení příďového kola, Mezerník = brzda kol;
rozjedeš se po dráze a po ~55 km/h se stroj sám odpoutá. **Ve vzduchu řídíš hrazdou**
(přenos váhy – realisticky *obráceně* proti letadlu): S = hrazda od sebe → nos nahoru / zpomalit,
W = hrazda k sobě → klesat / zrychlit, A/D = zatáčka *naopak* (A = doprava). V Esc → Nastavení
jde přepnout „Intuitivní řízení rogala“ (W = nahoru, A = vlevo). **Přistání** jen na letišti:
proti větru ~65 km/h, dosedni na hlavní kola a příďák polož jemně. Přistání mimo dráhu (mimo
nouzi), let bez průkazu/registrace/pojištění, v noci, v mracích, nízko nad obcí (<150 m AGL)
nebo nad lidmi = přestupky `ul_*` (svědek = hluk motoru ~800 m). **Spolujezdec:** u stojícího
triku nabídneš E „vyhlídkový let“ vesničanovi s přátelstvím ≥ 60 – sedí vzadu, komentuje let
bublinami, po přistání se vysadí (+ přátelství, + pověst). Průkaz ULL (`pilot_ul`, škola
75 000 Kč = eTest „ultralehké“ + 10 výcvikových letů s instruktorem rádiem), registrace
`ul_registrace` (1 500 Kč) a pojištění `ul_pojisteni` (3 000 Kč/rok): PC → *Letectví – ÚCL*.
Ukládá se se stroji (`aircrafts`); spolujezdec se před uložením vysadí.

## Systémy

- **Fyziologie** (`body_state.gd`): Widmark se vstřebáváním ze žaludku; jídlo zpomaluje vstřebávání
  a urychluje odbourání (~0,15 ‰/h), kalorie → hmotnost/BMI, nikotin a chuť na cigaretu, nevolnost
  → zvracení, nad 3 ‰ otrava a „okno“. Opilost zhoršuje chůzi i řízení (zpoždění, kmitání, mikrospánek).
- **Místa** (`place.gd`, otevírací doby): hospoda 10–2, Potraviny 6–21, pálenice 8–22, vinný sklep 12–24,
  úřad 7–17, Myslivecká chata a domov nonstop. Doma: spánek do 7:00, lednička, kafe, oprava auta.
- **Doprava** (`traffic.gd`, `car.gd`): 5 AI aut jezdí pravým pruhem, brzdí před zatáčkami a před
  překážkou v pruhu (auto, chodec, pes, popelnice), stojící překážku objedou, vzájemné zablokování
  na křižovatce řeší přednost; zaseknutá auta mimo dohled hráče se přesunou. **M1.6:** modely se losují
  podle vah (`Traffic.AI_WEIGHTS` – hodně osobních, občas dodávka / pickup); **malotraktor Traktůrek** jezdí
  jen v sezóně polních prací (duben–říjen, 6–19 h) a jen po okreskách a polních cestách, max. ~27 km/h.
- **Nová vozidla a bazar (M1.6):** katalog `CarModel.MODELS` má pole `kategorie`, `skupina_rp` (AM/A1/A2/B/T pro M4.1),
  `cena`, `rok`, `kufr_l`, `nosic`, `tazne_kg`, `hitch`, `glb` (volitelný model). Přibyla dodávka **Bednář**, pickup **Lesák**
  (ložná plocha `bed`), kombi **Rodinka**, malotraktor **Traktůrek** (`tractor_model.gd`, ~30 km/h, velký moment), moped
  **Pionýrek 50** a skútr **Včelka 125**, vojenská **Armádka 750** (styl amerických 750 V-twin 40. let) a litrová
  kroska **Krosák 1000** (`bike_model.gd`, jednostopá se naklánějí). **Bazar** (`bazaar.gd`): cedule u silnice nedaleko obce
  (F2 → Teleport → „K bazaru vozidel“), E → 3–5 vozidel na týden (seed podle týdne), koupě → vozidlo stojí u domova (M1.7: u bytového domu / vlastního domu);
  výkup vlastních koupených vozidel za 60 % ceny podle poškození (vozidlo musí stát u cedule). Vlastněná vozidla se ukládají (F5 / F9).
  API pro náklad (M2.10): `Car.trunk_liters()`, `trunk_point()`, `cargo_bed()`, `has_rack()`, `hitch_point()`, `tow_limit_kg()`, `attach_trailer()`.
- **Nemovitosti, popisná čísla a start v bytě (M1.7):** `estate.gd` (`Estate`, `World.estate`) – registr všech budov z `BuildingDetails`
  (id = osm_id, typ `rodinny_dum` / `bytovy_dum` / `hospodarska` / `verejna`, dveře, střed, půdorys, podlaží, u bytového domu 4–8 bytů).
  **Čísla popisná jsou smyšlená** a deterministická: 1..N bez děr od návsi (dveře úřadu) po prstencích 120 m, v prstenci podle úhlu
  od `NUMBER_SEED`; kůlny, garáže a stodoly číslo nemají; skutečné číslo původního domu hráče se nikdy nezobrazí (`AVOID_NO_*`).
  Vedle dveří každé očíslované budovy je **červená smaltovaná cedulka** (obecný vzhled, bez znaku obce, `Label3D`, jen do 40 m).
  **Domov = vlastnictví / nájem:** `Estate.home_of(pid)` → nemovitost + byt; `World.apply_home` přesune místo „domov“ (E u dveří,
  parkování, rádio u vchodu) a interiér (byt = radiátor místo kamen, bez topení dřevem a komína). **Nová hra začíná v nájemním bytě**
  v bytovém domě vylosovaném **náhodně z celé mapy** při každém startu světa (kandidáti: obytné budovy s ≥ 2 podlažími a dveřmi,
  jinak los mezi většími domy; uložená hra má domov v savu);
  nájem 1 200 Kč / 7 herních dní se strhne sám, bez peněz dluh a upomínka (událost `rent_overdue` – hák pro M3). **Usedlost** (původní
  dům hráče z podkladů, `Estate.lot_id`): hospodářství, včelař a překupník zůstávají u ní; **zahrada a výběh koně jsou pronajaté
  u domova** – `World.home_grounds` je kotví u vchodu domova a `World.apply_home` je při každé změně domova přestěhuje
  (`Paddock.relocate`, `Garden.relocate` – místo se vždy hledá bez kolizí). Hospodářská zvířata jen s vlastním
  domem (M4.7 koupě a prodej). **Děda Vomáčka** bydlí v nejbližším rodinném domě ke své lavičce (nové číslo). Texty úkolů, rozhovorů
  a nabídek dosazují `Estate.home_label` („byt 5 v č. p. 48“). Uložení verze 2 (`estate` v savu); staré uložení → hráč vlastní usedlost,
  nic se neztratí. Bez `data/buildings.json` jen místa z `pois.json` a podnájem (byt 1) v usedlosti.
- **Interiéry všech budov se streamováním (M1.8):** `interior_streamer.gd` (`InteriorStreamer`, `World.interior_streamer`) staví interiér,
  až když je hráč do 8 m od dveří (stavba po místnostech, jeden krok za snímek), ruší ho nad 25 m, když hráč není uvnitř; najednou
  nejvýš 3 interiéry. Pod stejného správce přešly i domov (M1.4 / M1.7) a veřejné budovy (M1.5) – nic se už nestaví předem, stálé sloty
  0–6 zůstaly (uložené pozice uvnitř platí). `interior_gen.gd` (`InteriorGen`) generuje z půdorysu nemovitosti (`Estate`, seed = id budovy)
  **vymyšlené** vnitřky: **rodinný dům** (chodba od vchodu, obývák, kuchyň se stolem, ložnice, koupelna, případně pokojík; dveře mezi
  místnostmi jako dekor), **bytový dům** (chodba se schodištěm po patrech – E u schodů = výběr patra, dveře bytů s cedulkou „Byt N“,
  schránky; vlastní byt vede do domova z M1.7, z bytu se vychází zpět do chodby), **hospodářská budova** (stodola / garáž / hala – ponk
  s nářadím, regál, seno, vůz, pneumatiky, dřevo). Jedno OmniLight bez stínů na místnost, meshe sloučené po místnostech, kolize jen stěny
  a velký nábytek. **Vstup dveřmi:** E u dveří budovy → vejít (bytový dům, hospodářské budovy do 60 m od usedlosti / domova), jinak
  „Zamčeno“ (cizí stodola, kostel); **cizí dům** → „Zaklepat“: obyvatel (Persona vesničana, v domě dědy děda; ~70 % domů obydlených,
  doma podle hodiny) otevře a pozve dál podle nálady, přátelství, pověsti a denní doby (v noci jen přítel); pozvání platí 3 herní hodiny,
  pak tě vyprovodí (hák: událost `trespass` – porušování domovní svobody, M4.4). Uvnitř sedí obyvatel u stolu (E = rozhovor), E u stolu
  = posedět (přátelství +1). Cizí byty: zazvonit, odpověď jen přes dveře. Události `knocked` (hák M4.5), `visited`. Vloupání není.
  Laditelné tabulky nahoře v `InteriorStreamer` (`BUILD_R`, `FREE_R`, `MAX_BUILT`, `HOME_PROB`, `KNOCK_*`, `INVITE_MIN`) a `InteriorGen`
  (rozměry, barvy). Nový druh generovaného interiéru: větev v `InteriorGen.steps` + typ v `InteriorStreamer.GEN_KIND`.
- **Dědovo kolo a motorka** (`bike_model.gd`, `car.gd`): u domova stojí vedle auta kolo Favorín a motorka
  Javor 250 Kývačka. Kolo se šlape (W, max. ~30 km/h, bez motoru, zvonek), motorka má 4 stupně a ~95 km/h.
  Jednostopá vozidla se naklánějí do zatáček; při tvrdším nárazu jezdec spadne. Postava drží řídítka
  a šlape / má nohy na stupačkách (IK v `humanoid.gd`).
- **Potoky, řeka a rybníky** (`water.gd`, `tools/water.py`): skutečné toky z OSM (převzaté z DIBAVOD) – Březnice,
  Černý, Kaňovický, Oskorušný, Neradovský a Zlámanecký potok s přítoky (~35 km) a dvě nádrže. Osa toku je
  „sklouznutá“ do údolnice DMR 5G, koryto je vyhloubené v terénu (kolize i vzhled), hladina klesá po proudu;
  pod silnicemi a cestami tok podtéká (propustek). Voda se vlní podle proudu, v dešti a větru víc, v mrazu
  zamrzá (rybník pod −1 °C, potok pod −5 °C). Brodění zpomaluje chůzi, kroky šplouchají, u potoka je slyšet
  šumění, na mapě (M) jsou toky modře.
- **Rádio doma** (`radio.gd`, `radio_music.gd`, `radio_view.gd`): staré lampové rádio na stolku u vchodu domova (M1.7: přesouvá se s domovem).
  E u rádia kameru přiblíží před jeho přední stěnu a ovládá se ručně: levý knoflík = vypínač (cvaknutí) a hlasitost,
  pravý = ladění – ručička jede po skleněné stupnici s názvy stanic, mezi stanicemi šumí (šum ruší i sousedy),
  magické oko se při přesném naladění rozsvítí, lampy se po zapnutí ~2 s nahřívají. Táhni myší přes knoflík
  (Shift = jemně), kolečko, A/D ladění, W/S hlasitost; Esc / E / pravé tlačítko = odejít. Doma zůstává nabídka „Rádio…“.
  Smyšlené stanice s hudbou generovanou ve hře – *Rádio Kovadlina* (metal) a *Rádio Pohoda* (klidná hudba) –
  a internetové stanice ze souboru `data/radia.json` (veřejné streamy Českého rozhlasu; přehrávají se přes
  program **ffmpeg**, bez něj nebo bez internetu nehrají). Hlasitost 0–10. Hluk = hlasitost × hlučnost stanice;
  nad únosnou mez roste zlost sousedů (v noční klid 22–6 h 3× rychleji a mez je nízko): stížnosti vesničanů
  a dědy, pak pověst („rušení klidu“), v noci policie – pokuta 2 000 Kč a ztlumení. Tichá příjemná hudba přes
  den dědu potěší. Stav rádia se ukládá.
- **Policie** (`police.gd`): hlídka (rychlost, kličkování, nehoda, náhodná kontrola), silniční kontrola
  na trase úkolu. Při zastavení policista dojde k okénku řidiče a dá mu dýchnout; nulová tolerance
  (do 0,24 ‰ tolerance přístroje), pokuta, zákaz řízení, nad 1 ‰ záchytka.
- **Úkoly** (`quests.gd`, deník J): Cigarety pro dědu, Páteční pivo, Slivovice pro starostu,
  Autem z hospody, Mejdan na chatě, Degustace ve sklepě – každý s podmínkami; nesplněný lze zkusit znovu.
- **Zvěř a hráč** (`fauna/hunter.gd`, `fauna/paddock.gd`, `priroda/tracks.gd`, `priroda/nature_log.gd`):
  - **Srážka se zvěří**: poškození auta podle hmotnosti a rychlosti (`World.HIT_DAMAGE_K`), divočák při rychlé srážce
    zraní i řidiče. Vznikne úkol „Srážka se zvěří“ – nahlas ji do 1 herní hodiny na Myslivecké chatě (E), jinak pokuta
    2 000 Kč a zápis do pověsti. Uhynulé zvíře leží, dokud pro něj nepřijde myslivec (dojde pěšky, naloží, odejde).
  - **Myslivec Franta a krmelce**: dva krmelce a posed v lese u chaty; v zimě (prosinec–únor, nebo sníh, nebo krmelec
    naplněný úkolem) se srnčí skupiny z okruhu 600 m stahují ke krmelci a za soumraku k němu jdou. Úkoly u chaty:
    *Sčítání zvěře* (dalekohled X, 6 kusů do 250 m), *Krmivo ke krmelci* (pytel, o pětinu pomalejší chůze),
    *Shozené parůžky* (jen březen–duben, 4 kusy v okolí chaty).
  - **Včelař Vilém** u včelnice nejblíž obci (duben–září, 7–19 h): úkol *Vytočit med* – kukla a kouřák, okuřování
    úlů (E 5 s), plástve zpět; s kuklou včely nebodají. Odměna: peníze a sklenice medu.
  - **Stopy ve sněhu** (jeden MultiMesh na druh, max. ~600 stop): hráč, kůň (kopyto), srnec, divočák, zajíc („Y“);
    vybledají za 2,5–5 min reálného času, mizí s táním.
  - **Výběh u domova** (nájemník bytu má louku pronajatou blízko bydliště; `Paddock.relocate` se stěhuje s domovem): ohrada ~20×15 m s pevnou kolizí a otevřenou brankou, žlab se senem a napáječka.
  - **Deník pozorování přírody** (J): první setkání s 9 druhy (zajíc, srnec, divočák, vrána, kos, vlaštovka, káně,
    včely, mravenci) s datem; ukládá se do savu.

- **Kalendář a slunce** (`clock.gd`): skutečné datum (výchozí dnešek, `--date`), poloha slunce a měsíce
  (fáze) astronomicky pro Dukelčice (49,14° s. š.) a SEČ/SELČ → délka dne a výška slunce podle ročního
  období; státní svátky. HUD ukazuje datum, čas, počasí a teplotu.
- **Počasí** (`priroda/weather.gd`): situace jasno / polojasno / oblačno / zataženo / mlha / přeháňky /
  déšť / bouřka se střídají podle tabulky přechodů a klimatu střední Moravy po měsících (`priroda/seasons.gd`);
  teplota s denním chodem, vítr, sníh pod ~1 °C (sněhová pokrývka přibývá a taje), mokrý povrch.
  Vzhled (`priroda/atmosphere.gd`, `shaders/sky.gdshader`): obloha s mraky, červánky, hvězdy, měsíc,
  mlha, déšť a sníh (nepadají pod střechy), blesky s hromem se zpožděním podle vzdálenosti, zvuk deště
  a větru; stromy se ve větru víc kývají.
  Hratelnost: přilnavost je jedna sdílená tabulka (`Weather.SURF_GRIP` + `surface_grip`) – auto na mokru,
  sněhu a náledí déle brzdí a hůř točí, AI doprava i policie zpomalují a drží větší rozestupy, v mlze a noci
  svítí; stěrače na N, kapky na čelním skle z interiéru, déšť na střeše auta. Chodec na mokru / sněhu /
  náledí klouže (menší trakce, delší zastavení) a ve sněhu nechává stopy. Kůň v bahně a na náledí klouže
  a zpomalí, hrom ho poleká (skočí stranou). Mlha zkracuje dohled zvěři i policie. Déšť, sníh a vítr hráče
  promáčí a ochlazují (`body_state.gd`: `wetness`, `cold`) → prochladnutí snižuje výdrž a rychlost, kamera
  se třese, při podchlazení ubývá zdraví; pod střechou / v autě / v posteli se osuší a zahřeje. Deník J
  ukazuje počasí a předpověď na zítřek (`Weather.forecast`).
- **Roční období** (globální parametry shaderů v `project.godot`): listnáče na jaře raší, na podzim se
  barví a opadávají, v zimě jsou holé; tráva a pole mimo sezónu hnědnou; sníh na terénu, střechách,
  jehličí a cestách (silnice jsou protažené); mokré silnice a střechy tmavnou a lesknou se.
- **Pole a louky podle kalendáře** (`priroda/fields.gd`, `shaders/terrain.gdshader`): plochy z OSM
  (`tools/landuse.py` → `data/landuse.bin`, rastr 4 m: orná půda, louky, sady, zahrádky; ~34 polí, orná půda je jen
  ~7 % katastru, ostatní jsou převážně louky). Plodina každého pole (ozimá pšenice, jarní ječmen, řepka, kukuřice, slunečnice,
  jetel) se volí podle (číslo pole, rok) s váhami osevního postupu; tabulka `Fields.CROPS` má barvy po dnech roku
  (orba s rýhami, vzcházení, žlutá řepka v květnu, zlaté obilí v červenci, žně ~ 205. den → strniště → podmítka).
  `SeasonFx` (klient) denně přepočítá tabulku barev polí; na loukách, v sadech a zahrádkách rostou květy
  (`meadow_flowers.gd`, MultiMesh do 70 m, hustota podle `Seasons.bloom`), v sadech a zahradách ovoce v korunách
  (srpen–říjen) a pod listnáči padané listí (`tree_decor.gd`).
- **Sezónní předměty** (`World.SEASON_ITEMS`): hřiby červenec–říjen (víc po dešti – `Weather.rain_recent`), jablka
  srpen–říjen, **šípky** listopad–únor (u jabloní a části hřibových míst, přidané za konec `meta["items"]`);
  mimo sezónu jsou skryté a nesbíratelné, sebrané znovu vyrostou po 3 / 5 / 7 dnech (jen v sezóně).
- **Svátky a události v obci** (`priroda/village_events.gd`, tabulka `VillageEvents.EVENTS`): Vánoce (1. 12.–6. 1.:
  stromek na návsi, světýlka na fasádách, Štědrý den hospoda do 14 h a obchod do 12 h), masopust (sobota před Popeleční
  středou 10–15 h: průvod masek po silnici od úřadu k hospodě a zpět), čarodějnice (30. 4. 18–24 h: hranice na hřišti,
  od 20 h hoří, vesničané kolem), hody (3. neděle v říjnu + sobota: prapory u hospody, hospoda do 4:00),
  Silvestr (23:40–0:40 ohňostroj nad návsí, hospoda do 3:00). HUD u hodin ukazuje svátek a probíhající události.
- **Den v týdnu** (`Place.WEEK_HOURS`): obchod v sobotu 7–11, v neděli a o svátcích zavřeno; hospoda v pá a so
  do 3:00, v neděli do půlnoci, v pátek večer 3 hosté navíc u druhého stolu; o víkendu ve dne (9–18 h)
  přibude ~30 % vesničanů (`World.WEEKEND_CROWD`).
- **Zvěř** (`fauna/`): srnci (skupiny, v zimě tlupy, srnec s parůžky), divočáci (tlupy, bachyně se
  selaty může zaútočit), zajíci (strnou v pelechu, utíkají kličkami ~60 km/h); drží se lesa a okrajů podle
  mapy stanovišť z dat stromů a budov, mají dobu aktivity (srnci za soumraku, divočáci v noci), vnímají
  zrakem (tma, les, přikrčení), sluchem (běh, auto) a čichem po větru. Fyzika: omezené zrychlení
  a zatáčení, svahy, obcházení kmenů, skoky přes překážky; auto zvíře srazí (zpráva, bez policie).
- **Ptáci**: hejna vran na polích (vzlétnou do stromů), kosi v zahradách (zpěv za svítání), vlaštovky
  (duben–září, před deštěm létají nízko), káně kroužící nad polem za slunečného dne.
- **Hmyz**: včelnice s úly (včely létají za teplého suchého počasí, když něco kvete; u úlu tě
  pobodají), mraveniště v lesích se stezkami ke stromům (kdo si na ně stoupne, toho kousnou).
- **Kůň** (`fauna/horse.gd`): ve výběhu u domova se pase kůň hráče se sedlem; chody krok ~6, klus ~14, cval ~25,
  trysk ~50 km/h, výdrž, skok, náraz do zdi v trysku jezdce shodí. Návod k úpravám: [`ZVIRATA.md`](ZVIRATA.md).

- **Obyvatelé** (`characters.gd`, `persona.gd`): 28 vesničanů jsou různé smyšlené postavy – jméno, věk,
  povolání, povaha (přátelský, drbna, bručoun, přísný, veselá kopa, plachý, moudrý, mladý), vlastní vzhled
  (ženy i muži, účesy, vousy, klobouky, postava) a tempo chůze; nad hlavou jmenovka. Obsluha míst, štamgasti,
  děda a policisté mají také povahu. Každá postava si pamatuje, jestli se s hráčem zná a jak se na něj dívá
  (nálada – urážky ji zhorší, omluva a slušnost zlepší, časem se vrací k normálu).
- **Rozhovor na ulici** (`dialog.gd`, T): hráč napíše, co řekne (bublina nad hlavou, v opilosti šišlá).
  Odpoví postavy do ~11 m (křik ~26 m) – nejbližší, nebo ta oslovená jménem. Rozpozná se záměr (pozdrav,
  jak se máš, jméno, práce, věk, čas, počasí, kde je hospoda / obchod / … a jestli mají otevřeno, cesta domů,
  nocleh, policie, drby, úkoly, pozvání na pivo, jídlo, peníze, vtip, lichotka, omluva, urážka, vyhrůžka,
  oblíbená témata postavy…) a odpověď se složí podle povahy, nálady, pověsti hráče, jeho promile a stavu
  světa. Urážky slyší i okolí; urážka policisty = pokuta, vyhrůžka nebo řízení opilý před svědkem = volají
  policii. Záznam posledních replik je vlevo dole. Bez internetu a jazykového modelu – klíčová slova
  (bez diakritiky) jsou v `Dialog.WORDS`, témata v `Dialog.TOPICS`.
- **Dovednosti a XP** (`skills.gd`, `World.skills[id]`, klávesa K / deník J): 16 dovedností ve stylu RuneScape, úroveň
  1–50, křivka `Skills.BASE` / `GROWTH` (úroveň 10 ≈ 1 040 XP, 30 ≈ 15 500, 50 ≈ 184 000). XP dávají činnosti: jízda autem
  střízlivě (pod 0,2 ‰, bez nehody, `DRIVE_M_PER_XP` = 1 XP / 100 m), jízda na koni (víc za klus a cval), oprava auta
  (Kutilství), slušný rozhovor (Výřečnost, s odstupem), splněný úkol, sprint pěšky (Kondice). HUD ukáže plovoucí „+N XP“,
  nová úroveň popup + zvuk. Ostatní systémy volají `World.give_xp(id, dovednost, xp)`, úroveň zjistí `Skills.has_level` /
  `level` / `bonus` (0..1). Ukládá se do pozice (`skills`); starý save = vše na úrovni 1. F2 → Hráč → „+1 000 XP Řízení“ (ladění).
- **Zákon jako data** (`law.gd`, `data/zakon.json`, `World.law[id]`, `World.commit_offense`): katalog přestupků (název, zákon a §, pokuta
  [min, max], body, zákaz řízení v hodinách, trestný čin, místo řešení). Všechny tresty (policie – alkohol / řízení přes zákaz / záchytka,
  rušení nočního klidu rádiem, urážka a vyhrožování policistovi, nenahlášená srážka zvěře) jdou přes `commit_offense` → `Law.LawRecord`:
  zapíše záznam, vybere pokutu (`severity` 0..1), přičte body, při 12 bodech dá zákaz řízení na rok (a body vynuluje), pošle událost
  `offense`. Body se po herním roce bez přestupku snižují o 4. Deník J → „Úřední záznamy“ (body, nezaplacené pokuty, posledních 10 záznamů
  s § zákona). Ukládá se (`law`), starý save = 0 bodů. Ladění: hodnoty v `data/zakon.json` (částky jsou orientační, u paragrafů „?“ ověřit).
- **Kontextové akce a nástroje** (`actions.gd`, `action_runner.gd`, `tool_models.gd`, `World.action_runner`, Q / 1–5 / LMB): hráč drží
  nástroj (`Player.equipped`, model z `ToolModels` nebo `assets/models/nastroje/<id>.glb`), míří na cíl (registrovaný přes
  `World.register_target` nebo země / voda paprskem z hlavy hráče, dosah 4 m), LMB spustí akci z registru `Actions.DEFS`
  (`target`, `tool`, `time_s`, `stamina`, `skill`, `xp`, `level`, `anim`, `fail_chance`, `gives`). Akce trvá (zkracuje ji dovednost,
  až na polovinu), průběžně stojí výdrž, na konci šance na neúspěch (půl XP), výnos do inventáře, opotřebení nástroje, XP a událost
  `action_done` (pro zákon a úkoly); speciální výsledky přidá `Actions.set_handler`. Akce: `natrhat_travu`, kácení a dřevo (M2.1, viz níže; doplňkové klíče `tool_level`, `Actions.set_time_mod`, `set_target_check`). Náklad (G) řeší `Cargo` (M2.10, viz níže; G je zároveň hvízdnutí na koně). Nástroj v ruce se ukládá (`equipped`).
- **Dřevo – kácení a zpracování** (M2.1: `tree_manager.gd` `World.trees`, `forestry.gd` `World.forestry`, akce `pokacet` / `odvetvit` /
  `rozrezat` / `stipat` v `Actions.DEFS`): LMB na strom (nástroj v ruce: stará sekera, sekera nebo motorová pila – Q / 1–5; dosah 2,5 m,
  pohled ke kmeni). Doba podle průměru kmene a nástroje (stará ×1,6, sekera ×1, pila ×0,35), dovednost Dřevorubectví, úroveň 1 / 5 / 20
  podle nástroje. Strom se skryje z MultiMeshů (kolize kmene vypnutá), zůstane **pařez** a strom padá ~3 s od hráče (praskání, dopad,
  prach a listí); kdo stojí v dráze pádu (hráč, vesničan, auto), dostane zásah. Padlý kmen: **odvětvit** (→ větve) → **rozřezat** (→ špalky
  podle délky, sekerou pomalu) → **rozštípnout** špalek (→ 4 polena). Pokácené stromy, pařezy, kmeny a špalky se ukládají (`forestry` v savu).
  Ovoce a listí v korunách i zvěř (`Fauna.trees_near`) pokácené stromy vynechávají. **Zákon:** vlastní zahrada (35 m od dveří vlastního domu,
  `Forestry.OWN_GARDEN_R`; nájemník bytu jen pronajatá zahrada) je bez postihu; cizí zahrada = poškození cizí věci + krádež dřeva, les bez povolení = kácení bez povolení + krádež
  dřeva, u silnice (< 8 m) ohrožení provozu; součet hodnoty dřeva za den nad 10 000 Kč = trestná krádež. Zjistí se jen při svědkovi
  (vesničan, myslivec, policejní hlídka; pilu je slyšet do 300 m, sekeru do 120 m) – jinak se čin uloží jako „nenahlášený“
  (`Forestry.pending_offenses`, háček pro M4.6) a klesne karma. Bez ochranných pomůcek (M2.3) hláška a šance úrazu. Železářství (sekery,
  motorová pila, sirky, zapalovač) je zatím v nabídce Potravin, pálenice vykupuje polena za 30 Kč / ks (režim `"sell"` v `Place.OFFERS`).
- **Oheň a topení** (M2.2: `fire_manager.gd` `World.fire_mgr`, `fire.gd` `Fire` = ohniště v `World.fires`, `grass_fire.gd`, `fire_fx.gd` sdílený vzhled
  s hranicí čarodějnic; akce `rozdelat_ohen` / `zapalit_ohniste` / `opekat` / `uhasit` / `hasit`): sirky nebo zapalovač do ruky (Q), LMB na trávu
  → oheň (roznětka 2× větve + 2× polena, nebo 4× větve; šance 90 % − déšť 40 − vítr nad 6 m/s 25 − mokro 20, dovednost Topení a oheň přidává).
  Oheň hoří podle paliva (poleno 25 herních minut, větve 8, déšť ubírá rychleji), pak 20 min žhavé uhlíky, kamenný kruh zůstane. **E u ohně:**
  přiložit, opékat (předměty s klíčem `cook_to` v `ItemsDB`: buřt, párek, chleba se sádlem; 60 s, šanci spálení snižuje Vaření; M2.7 / M2.9 jen
  přidají `cook_to` u ryb a masa), uhasit (vodou z kapsy rychle, jinak zašlapat 10 s). **Teplo:** do 3 m od ohně (`Player.heat` → `BodyState`)
  se schne 4× rychleji a hřeje. **Zákon:** oheň v lese nebo do 50 m od okraje (`FireManager.near_forest`) = přestupek `ohen_u_lesa` (svědek do 150 m
  hned, jinak 30 % za hodinu hoření podle kouře). **Požár trávy:** nehlídaný oheň (hráč dál než 40 m) v létě za sucha (`rain_recent < 0.2`) a větru
  nad 4 m/s může přeskočit na trávu (`GrassFire`, do 30 m, hoří 20 herních minut, zraňuje) – hasí se lopatou v ruce nebo vodou (`hasit`); jinak dohoří
  a původce dostane `zpusobeni_pozaru` a karmu −5; událost `fire_report` je háček pro hasiče (M5.3). **Kamna doma** (E na kamna v interiéru domova):
  2 polena = 3 herní hodiny, teplý domov (pocitově 22 °C) a komín domova kouří (`World.home_chimney_id` → `ChimneySmoke`; v bytě radiátor, bez kamen); nevytopený domov je
  v zimě chladný (venku + 8 °C, nejvýš 18) a spánek při < 5 °C mírně prochladí. Ohně a kamna se ukládají (`fire` v savu). Ladění: konstanty
  `FireManager`, `Fire`, `GrassFire`.
- **Oblečení** (M2.3: `wardrobe.gd` `Wardrobe`, katalog kusů = předměty typu `clothing` v `ItemsDB`, `Humanoid.apply_outfit`, `BodyState.insulation` / `waterproof`):
  sloty hlava / trup / bunda / nohy / boty / ruce, `Player.outfit` {slot: id} se ukládá (`outfit` v savu; starý save = výchozí triko, džíny a polobotky,
  tedy dřívější vzhled). Kus má `insul` (tepelná izolace), `waterproof`, `color`, `style` (tvar na postavě: triko, košile, mikina, bunda, větrovka, pláštěnka,
  plášť, sako, reflexní vesta, džíny, montérky, kraťasy, plavky, tenisky, holínky, pracovní boty, čepice, kulich, klobouk, kukla, pilařská přilba, rukavice)
  a `tags` (`ochrana_pila`, `reflexni`, `pracovni`, `slavnostni`, `hasic`, `plavky`, `vcelar`). Postava se přestaví jen při změně oblečení.
  **Fyziologie:** součet izolace (max 1,5) posouvá pocitové pohodlí o `(izolace − 0,4) × 12 °C` (výchozí oblečení = beze změny), nepromokavost
  (trup + bunda 70 %, hlava 15 %, nohy + boty 15 %) zpomaluje promáčení deštěm; v létě (> 25 °C) a s izolací nad 0,8 se hráč přehřívá (menší výdrž,
  `BodyState.overheat`). **Šatník:** doma E na skříň (okamžitě po slotech), jinde Tab → Obléct / Svléct (5 s, klek, nejde v autě ani na koni), I = přehled.
  **Obchod:** Potraviny – sekce Textil, Pracovní a Slavnostní (záhlaví v `Place.OFFERS` režim `"header"`). **Návaznosti:** přilba + ochranné kalhoty
  (`ochrana_pila`) = `Forestry.has_gear` (bez nich riziko úrazu při kácení); kukla je kus oblečení (`Player.beekeeper_suit` ji navlékne / sundá, včely nebodají);
  postavy komentují plavky ve vsi a slavnostní oblečení (`dialog_context.outfit_tags`); slavnostní oblečení na úřadě nebo při události v obci přidá postavě
  náladu (`Wardrobe.FORMAL_MOOD`, jednou denně). Ladění: konstanty `Wardrobe`, `BodyState.INSUL_*` / `OVERHEAT_*`, tabulka kusů v `ItemsDB`.
- **Zahrada a pole** (M2.4: `garden.gd` `World.garden`, `Garden.CROPS`; akce `ryt` / `sit` / `zalevat` / `sklidit` / `plet` / `naplnit` / `zahon_info`,
  cíl `zahon` = záhon 1 × 1 m, který hráč zaměřuje pohledem): u domova je zahrada 12 × 8 m (místo hledá `Garden._find_spot` bez kolizí, při stěhování `relocate`; když se nevejde, menší plocha / volnější podmínky
  `SPOT_STAGES`, nakonec nejlepší místo – založí se vždy; mezi domem a zahradou
  zůstává rezerva 8 × 6 m pro U-rampu M5.8 – `RAMP_SIZE`), cedule s nabídkou (E: volba semen, konev) a sud s vodou. Cyklus: lopata / motyka (Q) + LMB na
  trávu → **zryto** (20 s, motyka rychleji) → semena z kapsy + LMB → **zaseto** (jen ve `sow_months`, jinak „Teď se nesází“) → zálivka plnou konví
  (naplnit LMB u sudu / u vody, vystačí na 8 záhonů) a plení → **zralé** → LMB prázdné ruce = **sklidit** (úroda do Tab, XP Zahradničení, záhon zpět
  „zryto“). Plodiny: brambory, mrkev, cibule, salát, rajčata, dýně, česnek (`CROPS`: výsev, dny, nároky na vodu, mráz, výnos, XP). **Růst** = jeden krok za
  herní den (i při spánku a skoku času, `MAX_CATCHUP_DAYS`): teplota (pod 5 °C stojí, česnek roste i v chladu) × vláha (déšť / zálivka) × (1 − plevel / 2);
  sucho delší než `water_need` dní plodinu zavadí a ubírá zdraví (nakonec uschne), mráz pod `frost_kill` ji zničí. **Pole:** na úřadě „Pronájem pole (1 rok)“
  1 500 Kč (`Place.OFFERS` režim `"service"` → `Garden.service`) – najde nejbližší ornou půdu z OSM (`Fields.class_at == 1`, bez dat nic) a založí mřížku
  10 × 10 m stejnou jako zahrada (velkoplošné obdělávání traktorem zatím ne). **Využití:** Potraviny prodávají nářadí a semena a vykupují zeleninu (`"sell"`),
  brambory jdou opéct na ohni (`cook_to`), na kamnech doma se vaří bramborová polévka (2× brambory, cibule, voda; `FireManager.cook_soup`).
  Ukládání: klíč `garden` (záhony, pronájem, volba semen, náplň konve). Ladění: konstanty `Garden`, cheat „nástroje“ (F2 → Hráč) přidá i semena.
- **Sázení stromů** (M2.5: `planted_trees.gd` `PlantedTrees` – nová vrstva stromů, `TreeManager.planted`, čísla od
  `TreeManager.DYN_BASE`, takže kácení, míření i pařezy fungují stejně jako u mapových stromů): akce `zasadit`
  (cíl `ground`, lopata, 60 s, ne na silnici / do vody / do záhonu / do 2 m od jiného stromu či zdi) ze sazenice
  (Potraviny, sekce „Sazenice stromů“: jabloň, slivoň, hrušeň, třešeň, dub, buk, smrk, borovice, 150–350 Kč, i
  ochranný obal). Měřítko roste z 0,15 na 1 za `years × 365 / PlantedTrees.GROWTH_SPEEDUP` dní (výchozí 6× rychleji
  než realita); bez vody v prvních 60 dnech zdraví klesá (nakonec uschne), srnci poblíž ožírají neobalenou
  sazenici (`obalit`), zimní měsíce strom nechávají spát. Ovocné druhy plodí od velikosti 70 % v sezóně
  (sdílí `TreeDecor.FRUIT`), `natrhat_ovoce` je sklidí. `strom_info` ukáže stav. Strom, který se 60 dní ujme,
  dá vlastníkovi karmu +1 a pověst +1 (nejvýš 5× za rok); výsadba na cizím zastavěném pozemku sníží respekt
  `sousede` o 1 (jen háček). Model sdílí prototypy a sezónní shader s mapovými stromy (`MapLoader.shared_protos`).
  Ukládání: klíč `planted` uvnitř `TreeManager.to_dict` (ukládání kácení). Ladění: konstanty `PlantedTrees`.
- **Hospodářská zvířata** (M2.6: `farm/farm.gd` `World.farm`, `farm/pen.gd` `Pen`, `farm/farm_animal.gd` `FarmAnimal`,
  `farm/farm_specs.gd` `FarmSpecs`): jeden společný výběh ~20 × 15 m u usedlosti (`Pen._find_spot`; M1.7: koupě zvířat jen s vlastním domem; mimo výběh koně
  a zahradu) s kurníkem (slepice, kohout, králíci), chlívkem (prase) a otevřeným přístřeškem (koza, ovce, kráva) –
  čtyřnožci sdílí `QuadrupedModel` / `QuadrupedRig` se zvěří (nové druhy v `AnimalSpecs.SPECIES`: `prase_farm`,
  `koza`, `ovce`, `krava`, `kralik`), slepice má vlastní jednoduchý model (tělo, hřebínek, zobáček). Cedule u branky
  (E) → nabídka: koupě mláděte / dospělého za druh, krmení (`zrni`, `seno`, `granule`, zelenina z M2.4 s klíčem
  `feed`), napojení (společná napáječka zdarma), sběr vajec, dojení (kbelík), stříhání ovce (nůžky, V–VI),
  pohlazení, přivedení zatoulaného zvířete a porážka (nůž; u prasete navíc pomocník – přítel ≥ 40 – nebo řezník
  za 800 Kč). **Péče**: hlad a žízeň klesají za herní den (pasoucí se druhy se mimo zimu částečně sytí samy),
  dlouhé zanedbání (`starve_h` ≥ 48 h) sníží karmu a může založit přestupek `tyrani_zvirat`; bez péče zvíře uhyne.
  Otevřená branka = šance na útěk, zvíře se vrátí nakrmením nebo vedením zpátky. Slepice se na jaře (kohout + ≥ 3
  slepice) můžou rozmnožit. **Porážka** ztmaví obrazovku na 2 s (`World.blackout`) a dá maso podle hmotnosti a
  zdraví (`maso_drubez` / `_kralici` / `_veprove` / `_kozi` / `_skopove` / `_hovezi`, u prasete i sádlo, jitrnice
  a tlačenka – „zabijačka“ zvedne respekt sousedů); maso se v `ItemsDB` kazí (`perishable_h`), lednička ani udírna
  ještě nejsou (otevřený bod z M1.4 / M2.2). Ukládání: klíč `farm` (zvířata, branka, čekající vejce).
- **Rybaření** (M2.7: `fishing.gd` `Fishing`, `World.fishing`, data `data/ryby.json`; dovednost Rybaření): udice (nebo lepší udice od
  úrovně 10) do ruky (Q), návnada v kapse (žížaly, těstíčko, kukuřice – Potraviny, sekce „Rybaření“; žížaly jde vykopat lopatou / motykou
  na vlastním pozemku, akce `kopat_zizaly`, po dešti víc), pohled na vodu do 8 m (hloubka ≥ 0,3 m, zamrzlá voda nejde) → **[LMB] Nahodit udici**
  (splávek s kroužky, vlasec od prutu). **Záběr** přijde za 5–90 s podle šance = místo × denní doba (ráno a večer ×1,5, poledne ×0,7) ×
  počasí (zataženo / déšť ×1,2, jasno a horko ×0,7, silný vítr ×0,8) × sezóna (zima ×0,3) × návnada × úroveň (`Fishing.bite_factor`);
  splávek se ponoří → do 1,2 s **[LMB] zaseknout**. **Zdolávání:** pruh napětí vlasce (HUD, u zaměřovače): drž LMB = navíjíš (napětí roste),
  pusť = povolí; ryba se přitahuje jen v zelené zóně 40–80 %, občas trhne (skok napětí); přes 100 % vlasec praskne, pod 40 % ryba couvá.
  Boj trvá 5–40 s podle velikosti; velká ryba (> 40 cm) bez **podběráku** v kapse se s šancí utrhne u břehu. **Úlovek** (druh, cm, kg – např.
  „Kapr obecný 48 cm, 2,1 kg“, XP Rybaření podle velikosti) → menu **ponechat** / **pustit** (malá nebo hájená ryba pustit = karma +0,5). Druhy podle vody:
  rybník (kapr, lín, plotice, cejn, okoun, štika…), řeka (jelec, klen, candát…), potok (pstruh, jelec, plotice; příkopy jen malé kusy),
  v noci jen úhoř a sumec. **Zákon (háčky pro M4.6):** ponechání ryby pod lovnou mírou nebo v době hájení = přestupek `rybolov_mira_hajeni`,
  rybaření bez `World.has_permit("rybarsky_listek" / "povolenka_rybolov")` (zatím vždy false) = `rybarske_pytlactvi` – oboje se zjistí jen před svědkem
  do 45 m (`Forestry.witness_near`), rybářská stráž a doklady přijdou v M4.6. **Využití:** syrová ryba se kazí za 12 h, na ohni se opeče
  (`cook_to` → Pečená ryba), hostinský ji vykupuje („Výkup ryb“ v hospodě; kapr v prosinci ×2). Míry a hájení v `data/ryby.json` jsou orientační
  (ověřit v rybářském řádu, vyhl. 197/2004 Sb.). Bez `ryby.json` se použije vestavěná záloha tří druhů. Ladění: konstanty `Fishing`, cheat „nástroje“ (F2 → Hráč) přidá i návnady a podběrák.
- **Zbraně a střelba** (M2.8: `weapons.gd` `Weapons`, `World.weapons`, `shooting_range.gd` `ShootingRange`; dovednost Střelba): **luk** (2 900 Kč,
  šípy; natahování LMB 1,2 s, síla podle doby, slyšet do 25 m), **kuše** (5 900 Kč, šipky; 4 s napínání po ráně, 30 m) a **puška** (kulovnice
  s optikou, zásobník 3 náboje, 1,5 s mezi ranami, přebíjení 4 s, slyšet do 1 500 m, zvěř do 400 m prchá) – Potraviny, sekce „Sport a lov“;
  **puška a náboje jen se zbrojním oprávněním** (`World.has_permit(id, "zbrojni", pos)`, zatím jen ladicí cheat F2 → Hráč, jinak „Bez
  zbrojního oprávnění vám ji neprodám.“; doklady M4.6). Q / 1–5 zbraň do ruky, **pravé tl. míření**, **levé tl. výstřel**. **Kolísání mušky**
  roste s únavou (po sprintu), opilostí, chladem, pohybem a dlouho taženým lukem, klesá s dovedností Střelba a v podřepu; **Shift** zadrží dech.
  **Balistika**: projektil jde po krocích jako paprsek (gravitace, odpor, vítr `Weather.wind_vector` – šíp znatelně, kulka skoro vůbec); šíp a šipka
  jsou vidět letět, kulka jen dopadne. Bez míření se střílí „od boku“ s velkým rozptylem. **Zásah:** terén / strom / zeď – šíp se zapíchne na 2 min
  a jde **sebrat (E)**; terč střelnice; člověk (`ublizeni_na_zdravi`, pád, útěk okolních, hledaný pěšky 8 h); auto, pes, kůň, zvíře z hospodářství
  (`poskozeni_veci` se svědkem); zvěř = událost `shot_hit` {kind "animal", target, species, part (`Weapons.hit_zone`: hlava / srdce_plice /
  bricho / noha), energy, pos, weapon, dist} a zvíře s hejnem prchá (smrt a úlovek až M2.9). **Střelnice** u myslivecké chaty (směr se vybere
  podle terénu – `ShootingRange.FIRING_YAW_DEG`, DOPLNIT): stůl (E = skóre posledních 5 ran), terče 15 / 30 / 50 m a 100 m (pro pušku),
  zásahy jako tečky, XP Střelby podle přesnosti a vzdálenosti; střelba po dráze je legální, puška bez oprávnění ne (myslivec ji zabaví).
  **Zákon** (`data/zakon.json`, paragrafy „ověřit“, od 1. 1. 2026 zákon o zbraních 90/2024 Sb.): `nedovolene_ozbrojovani`, `strelba_v_obci`
  (zástavba nebo do 100 m od silnice, i šíp), `zbran_pod_vlivem`, `ublizeni_na_zdravi`, `poskozeni_veci`, háček `pytlactvi_luk_kuse` (M2.9); vše
  jen se svědkem (`Forestry.witness_near`). Puška v ruce ve vsi vesničany vyděsí (hláška, útěk, podle povahy volají policii); policejní kontrola
  (dechová zkouška, hlídka do 28 m u pěšího) bez oprávnění pušku zabaví (`Weapons.police_check`). Ladění: `Weapons.WEAPONS`, konstanty `Weapons` a
  `ShootingRange`, cheaty F2 → Hráč „Zbraně“ a „Zbrojní oprávnění zap / vyp“.
- **Lov zvěře** (M2.9: `hunting.gd` `Hunting`, `World.hunting`, `carcass.gd` `Carcass`, `Animal.shot`, `data/lov.json`; dovednost Myslivost):
  zásah zvěře (`Weapons._hit_animal` → `Hunting.animal_shot`) závisí na **zóně** a **energii**: hlava a komora (srdce a plíce) s dost energie
  (puška vždy, šíp / šipka jen někdy – `Animal.KILL_HEAD_J`, `KILL_HEART_J`, těžší zvíře víc) zvíře usmrtí (srdce: ještě uběhne 20–60 m),
  jinak je **postřelené do břicha**: uteče 200–600 m, zalehne a po 1–3 herních hodinách zhyne (při přiblížení na 15 m se může až 2× zvednout a
  utéct dál); **noha** = kulhá (zpomalené) a žije. Postřelené zvíře nechává **krvavou stopu** (tmavé kapky po trase útěku, mizí za 2 herní hodiny,
  v dešti 3× rychleji) – dohledej ho po ní. Nenaturalisticky: jen pád a ležící zvíře. Mrtvé zvíře = **`Carcass`** (druh, hmotnost, čas úmrtí,
  legálnost, vyvrženo); **E u těla** otevře nabídku: **Vyvrhnout** (nůž z Potravin, pár sekund s ukazatelem, ztmavení obrazu, −20 % hmotnosti, XP
  Myslivosti; nevyvržené maso se po 3 herních h – v létě 2 – zkazí), **Zpracovat** (jen doma na dvoře do 30 m od dveří: zvěřina `zverina_srnci` /
  `zverina_divocak` / `zverina_zajic` podle hmotnosti + paroží u srnce), **Zvednout na rameno** (**G**; jen zajíc, sele, srnec – chůze × (1 − kg / 60),
  žádný sprint, výdrž ubývá, při nule zvěř upustíš; divočák je na rameno moc těžký – jen na vozík / do auta, viz Náklad a vozík). Těla mimo dvůr po 2 dnech zmizí,
  ukládají se (F5 / F9, klíč `hunting`). **Legalita** (`World.is_legal_hunt(id, weapon, species, pos)` → {ok, reasons}): jen puška a zbrojní oprávnění a
  lovecký lístek a povolenka (`World.has_permit`; zatím cheat F2 → Hráč → „Zbrojní oprávnění zap / vyp“ je zapne všechna tři, doklady M4.6), v době
  lovu druhu (`data/lov.json`: srnec 16. 5.–30. 9., srna 1. 9.–31. 12., divočák celoročně, zajíc listopad–prosinec – ověřit ve vyhl. 245/2002 Sb.),
  ne v noci (kromě divočáka), ne v obci, ne z auta; **luk a kuše nikdy**. Legální úlovek dá **doklad o původu**; nelegální = **pytláctví**: karma −3 za kus,
  přestupek (`pytlactvi`, u luku a kuše `pytlactvi_luk_kuse`, 40/2009 Sb. § 304 – ověřit) jen když střelbu uvidí svědek (`Forestry.witness_near`) nebo
  hráče s nelegálním úlovkem (do 8 m od těla / na rameni) uvidí vesničan do 25 m; postřelené zvíře, které nedohledáš = karma −5; sraženou zvěř si
  vzít (E) = přivlastnění (pytláctví). Hajný a policie (M4.6) dostanou události `poaching` a `wounded_unfound`. **Posed:** hráč výš než 3 m nad terénem je
  zvěři hůř vidět a cítit (`Animal.STAND_HEIGHT_M`). **Vítr** při míření: šipka a rychlost ve stavu zbraně dole. **Prodej:** legální zvěřina s dokladem
  o původu v hospodě („Výkup zvěřiny“) a v Potravinách (`Hunting.sell_venison`, jeden doklad kryje 15 ks); nelegální jen u **překupníka** (večer 19–24 h
  za hospodou, +30 %, 10 % „prásknutí“ = pytláctví) nebo **sousedům bokem** (max 3 ks, −20 %, štamgasti +1, karma −1). Ladění: konstanty `Hunting`, `Animal`
  (KILL_*, WOUND_*), `data/lov.json`; cheaty F2 → Hráč „Nástroje“ (nůž) a „Zbrojní oprávnění“ (puška + doklady).
- **Náklad a ruční vozík** (M2.10: `cargo.gd` `Cargo`, `World.cargo`, `hand_cart.gd` `HandCart`, `Car.set_cargo_kg`, `World.visible_cargo(id)`;
  tabulka `Cargo.CARGO`: zajíc 4 kg, srnec ~22, **divočák ~80 (na rameno ne)**, špalek 15, pytel 25): **G** u věci (do 3 m) ji zvedne **na rameno**
  (zvěř přes `Hunting.lift`, špalek a pytel tady; max 35 kg; chůze × clamp(1 − kg / 60, 0,35, 0,9), žádný sprint, jen malý hop, výdrž ubývá s kg,
  při nule náklad upustíš); těžkou věc (divočák) G naloží rovnou na vozík / do auta u tebe, jinak „Sám ho neuneseš.“ – **ve dvou zatím ne** (otevřený
  bod, háček `Cargo.two_person_partner`). **Auto:** G s nákladem u kufru vlastního auta naloží (kapacita `kufr_l × 0,15` kg – DOPLNIT, prompt chtěl ×0,1; velký kus jen kombi / dodávka /
  pickup – `LARGE_MIN_L`); náklad v kufru není vidět, **pickup** ho vozí na ložné ploše (vidět), hmotnost zvyšuje `mass` (`Car.set_cargo_kg`, delší brzdná dráha);
  **E** u auta = „Vyložit z vozidla“ (náklad se položí za auto). **Motorka a kolo:** jen náklad s `bike_rack` (ne divočák), viditelně na nosiči, kolo do 15 kg,
  motorka do 35 kg; těžiště dozadu a horší stabilizace v `Car._balance` (víc kmitá). **Ruční vozík** (Potraviny „Doprava a náklad“ 2 490 Kč; po koupi stojí u domu):
  E u něj = **uchopit oj a táhnout** (`HandCart`: fyzikální těleso ~25 kg s kluznou podložkou, boční skluz se ruší jako u kol, pružina mezi madlem a hráčem),
  do kopce pomalu a za výdrž (`Cargo._grip_update`), z kopce vozík dojede a tlačí; **E znovu** = pustit (na svahu **ujede**), pustit a **podložit kolo** (stojí),
  plachta (`plachta` z Potravin) náklad schová; **G** s ojí v ruce nebo u vozíku naloží věc ze země / to, co neseš (nosnost 200 kg: divočák, 6 špalků, 5 pytlů),
  E vyloží. AI auta ho objíždějí jako každou rekvizitu (vrstva 8). Viditelný náklad (na rameni, na nosiči, na vozíku bez plachty) hlásí událost `cargo_seen`
  (M4.6), naložení `cargo_load`, zvednutí `cargo_lift`. Ukládá se (`cargo` + `cargo` u vozidla). Ladění: konstanty `Cargo` a `HandCart`; F2 → Příroda „Položit mrtvého
  srnce / divočáka“, F2 → Hráč „Náklad: špalek / pytel / ruční vozík“.
- **Práce – systém zaměstnání** (M3.1: `jobs.gd` `Jobs`, per hráč `World.jobs[id]`; katalog `data/prace.json` – práce v `prace`,
  pracovní úkoly v `ukoly`, zaměstnavatelé smyšlení; zatím jedna testovací práce **Pomocník v hospodě**, po–pá 16–20 h, 150 Kč/h hrubého):
  **E u místa** (u dveří i u výčepu uvnitř) → „Hledáte pracovníky?“ → práce s požadavky (dovednosti, řidičák – do M4.1 jen „bez zákazu“,
  oblečení se štítkem, čistý rejstřík, pověst, respekt komunity; splněné zeleně, nesplněné šedě) → „Ucházet se“ = krátký pohovor (tři odpovědi;
  šance `sance_pohovoru` + výřečnost + pověst + respekt, opilý skoro jistě neuspěje, neúspěch = znovu až zítra). **Směna:** do 15 min od začátku
  do 30 m od místa práce (nebo uvnitř budovy) → „Začal jsi směnu“; později = **pozdní příchod** (napomenutí), po 60 min **absence**;
  s > 0,2 ‰ tě vedoucí **pošle domů** (napomenutí). Během směny pracovní úkoly za sebou (`ukoly`): **akce** M0.4 na cílech (Uklidit stoly =
  LMB u stolu – uvnitř hospody, když je interiér postavený a jsi v něm, jinak na zahrádce; kolik stolů, tolik jich je potřeba) nebo **dojdi**
  (Vynést odpadky k nejbližší popelnici u silnice). Výdělek = hodiny v areálu (45 m, na pochůzce 200 m) × mzda; kdo se 60 herních min
  neposune v úkolu, tomu se hodiny nepočítají; odchod z areálu na 20 herních min = odchod ze směny (absence); pití alkoholu v práci =
  napomenutí; **3 napomenutí = výpověď**, zadržení policií (`busted`) i vězení (`jailed`, M4.3) = výpověď (respekt komunity −5).
  Směny prospané / zmeškané během skoku času (spánek, záchytka) = absence. **Výplata** týdně v pátek po směně hotově u zaměstnavatele
  („Vyzvednout výplatu“): čistá mzda (zjednodušeně −15 %, `cista_mzda_k`) + prémie 0–20 % podle hodnocení 0–100; respekt komunity podle
  hodnocení; při **dluhu na nájmu** nabídne „Zaplatit dluh na nájmu“ (`Estate.pay_rent_debt`). Svátky volno (`Clock.holiday_on`).
  HUD: řádek směny nad panelem úkolu, kompas „práce“ ukazuje pracoviště / stůl / popelnici; deník J → oddíl **Práce** (zaměstnání, směny,
  napomenutí, hodnocení, výplata, docházka). Ukládá se (klíč `jobs`). Události: `job_hired`, `job_rejected`, `job_quit`, `job_fired`,
  `job_warning`, `shift_started`, `shift_done`, `job_task_done`, `job_paid`. Ladění: konstanty nahoře v `Jobs`, `data/prace.json`;
  F2 → Hráč „Práce: přijmout hned / 5 min před směnu + k pracovišti / výplata připravená / napomenutí“. Další práce (M3.2+) = záznam
  v `prace.json` + úkoly; nové cíle přes `Jobs.set_provider(jméno, Callable)`, nové akce do `Actions.DEFS`.
- **První tři práce** (M3.2, `data/prace.json` + `scripts/prace/`): **Pomocník na farmě** (`statek_pomocnik`, smyšlený *Statek Na Kopci*
  – `Statek`, `World.statek`: největší hospodářská budova na okraji obce z `Estate` s vlastníkem „hospodář“, místo „statek“ s hospodářem
  Vladimírem a prodejem ze dvora, výběh `Pen` se 2 kravami, 6 slepicemi a 3 prasaty, stodola se senem, koryta, hnojiště, záhony;
  po–pá 6–14 h, 160 Kč/h, chovatelství ≥ 1 a **pracovní boty**; úkoly: seno z hromady → 3 koryta, napojit, podojit krávy na stání,
  vejce, vykydat hnůj vidlemi, IV–IX okopat záhony motykou), **Obecní údržba** (`obec_udrzba`, úřad, starosta; `ObecniUdrzba`,
  `World.udrzba`: po–pá 7–15 h od úřadu, 170 Kč/h, pověst +1 za týden bez napomenutí; úkoly podle sezóny a sněhu: posekat trávu kosou
  u hřiště a na návsi (posekaná plocha je 7 dní světlejší), vysbírat 8–15 odpadků po obci (kompas na nejbližší), opravit lavičku na
  návsi kladivem, IX–XI shrabat listí, v zimě odklidit sníh z chodníku před úřadem, Potravinami a u zastávky (zůstane odklizený, dokud
  nenapadne nový) a posypat pískem; sníh jde odklízet i **dobrovolně** bez práce – respekt sousedů a karma, událost `snow_volunteer`)
  a **Výčepní** (`vycepni`, hospoda; `Vycep`, `World.vycep`: čt–so 17–24 h, 140 Kč/h + spropitné, výřečnost ≥ 3, pověst ≥ 0, čistý
  rejstřík, střízlivý; host si objedná bublinou „Dvě desítky!“, u pípy **drž LMB** a pusť v zelené zóně 78–92 % (pivo s čepicí;
  moc = přeteče, málo = host nespokojen), pak **LMB na hosta** = postavit pivo na stůl → spropitné podle kvality a výřečnosti, respekt
  štamgastů; uvnitř postaveného interiéru u pultu, jinak u výčepního stolku na zahrádce). Nářadí (vidle, kosa, hrábě, kladivo, kbelík,
  lopata, písek) zapůjčí vedoucí na směnu a po ní se vrátí (`zapujcit`). Ladění: konstanty nahoře v `Statek`, `ObecniUdrzba`, `Vycep`;
  F2 → Hráč „Práce: přijmout hned – vybrat práci“ a „Práce: splnit požadavky“; F2 → Teleport → Statek Na Kopci.
- **Další práce** (M3.3, `data/prace.json` + `scripts/prace/`): **Lesní dělník** (`lesni_delnik`, smyšlená *Lesní správa Na Hvozdě*,
  vedoucí u Myslivecké chaty; `LesniPrace`, `World.les`: po–pá 6–14 h, 190 Kč/h, dřevorubectví ≥ 8 a pracovní oblečení; paseka v lese
  u chaty, každý den 3 stromy s **oranžovým pruhem** na kmeni – pokácet (sekeru půjčí; kácení vyznačeného stromu na směně je s povolením,
  jiný strom = přestupek jako dřív), odvětvit a rozřezat kmeny, **složit dřevo na hromadu** (špalek na rameni přes G nebo 4 polena =
  LMB na hromadu), III–V a X–XI vysázet zapůjčené sazenice; s **motorovou pilou jen s přilbou a ochrannými kalhotami**; respekt
  zemědělců a myslivců; myslivec prodává i lesní sazenice), **Prodavač/ka v Potravinách** (`prodavac`; `ProdavacPrace`, `World.obchod`:
  výřečnost ≥ 2, pověst ≥ 0, 150 Kč/h, **ranní** po–pá 6–12 + so 7–11, nebo **odpolední** po–pá 12–21 – vybere se po přijetí, změnit
  jde u prodavačky mimo směnu; **pokladna** = minihra v nabídce: zákazník přinese nákup, spočítej součet a vrať drobné mincemi
  200…1 Kč – málo = zákazník si řekne, moc = manko ze mzdy, dlouhé čekání = odejde; **regály**: bedna se zbožím ze skladu vedle
  obchodu na rameno (LMB) → vybalit do regálu uvnitř / do stánku před obchodem; ráno 6–8 h **převzít pečivo** u parkoviště),
  **Zahradník u sousedů** (`zahradnik`, brigáda na zavolání přes **dědu Vomáčku** – E u jeho lavičky → „Vzít zakázku“; `ZahradnikPrace`,
  `World.zahradnik`: zahradničení ≥ 5; zakázka = smyšlený soused z rodinného domu se **smyšleným číslem popisným** (M1.7), 2–3 práce
  podle sezóny na dočasné zahradě u domu – posekat trávník kosou, zastřihnout keře zahradními nůžkami, zrýt záhony, vysadit květiny;
  nářadí půjčí zákazník; lhůta 8 h, odměna **400–900 Kč na ruku** hned po dokončení + respekt sousedů, nestihnutá zakázka = napomenutí)
  a **Pomocník v pálenici** (`palenice_pomocnik`, Pálenice U Kotla; `PalenicePrace`, `World.palenice`: jen **IX–XII**, st–so 8–16 h,
  150 Kč/h + **lahev slivovice k týdenní výplatě** (v práci se nepije!), střízlivý na pohovor; kotel na topeništi před pálenicí:
  soudky s kvasem na rameni do kotle, **topení** = minihra – LMB u topeniště přiloží poleno, drž teplotu v zeleném pásmu 88–96 °C
  celkem 40 s, nad 100 °C se připaluje; plnění lahví). *Plavčík na koupališti* je připravený v `prace.json` → `pripravene` (M5.2).
  Rozšíření `Jobs`: úkoly typu **modul** (pokrok hlásí modul práce – `progress`), `hodiny` úkolu, **varianty směn** (`smeny[].nazev`
  + `smeny_volba`), **zakázky** (`druh: "zakazka"`, `set_contract_maker`, odměna na ruku), sezónní práce (`mesice`), naturálie
  k výplatě (`naturalie`), `set_event_hook` (modul dostává události hráče); `Estate.pick_customer_house`; náklad `bedna` a `sud`
  (`Cargo.shoulder_new`, `carried_kind`, `consume_carried`). Ladění: konstanty nahoře v `LesniPrace`, `ProdavacPrace`, `ZahradnikPrace`,
  `PalenicePrace`; F2 → Hráč „Práce: přijmout hned – vybrat práci“, „Práce: splnit požadavky“ (i dřevorubectví 8, zahradničení 5),
  „Práce: 5 min před směnu / zakázka hned + k zákazníkovi“. *Rozvoz / pošta* a *Opravář aut* zatím nejsou (otevřené body M3.3).
- **Počítač doma** (M3.4, `computer.gd` `Computer` = logika a data ve `World.computer`, `computer_ui.gd` `ComputerUI` = obrazovka,
  `test_ui.gd` `TestUI`): **E u stolu s PC** v domově (byt i usedlost) → hráč si sedne, přes celou obrazovku „starý OS“ (tyrkysová
  plocha, šedé okno s modrým pruhem, ikony Prohlížeč / Pošta / Banka / Hry, dole hodiny a stavový řádek), **Esc = vypnout**. Vše je
  smyšlené (adresy `vesnet://…`). Prohlížeč – záložky: **eŠuplík** (zboží z nabídky Potravin kromě jídla, pití a tabáku o 5 % levněji,
  doprava 89 Kč, platba z účtu nebo na dobírku +39 Kč; balík dorazí za 1–2 herní dny po 9:00 ke dveřím domova – u bytového domu
  k vchodu – E u balíku = vybrat), **Bazárek** (nabídka bazaru vozidel z M1.6, koupě z účtu s přistavením domů, prodej vozidla
  z bazaru odkudkoli na účet, inzeráty na zvířata jen pro čtení), **Práce v kraji** (všechny práce z `prace.json` s požadavky ✔/✘,
  „Odpovědět na inzerát“ = e-mailová pozvánka na pohovor na 7 dní – u zaměstnavatele pak „Jdu na pohovor (inzerát)“ s šancí +15 %),
  **Moje banka** (zůstatek `Player.bank`, pohyby, **trvalý příkaz na nájem** – nájem i dluh se platí z účtu, nezaplacené pokuty
  z rejstříku a jejich zaplacení, přepínač výplaty z práce na účet – přijde sama v den výplaty; přepínač je i u zaměstnavatele),
  **Obecní web** (bez znaku obce: kalendář akcí z `VillageEvents` + státní svátky na 60 dní, otevírací doby dnes, úřední deska
  s háčky M4.4 / M4.7 / M7, anonymní **diskuse s drby** z tvých přestupků, zadržení, práce, dluhů – `Reputation.last_offense_text`
  a události), **eTesty** (rámec `TestUI`, otázky v `data/testy/<id>.json`; teď cvičný test *Pravidla silničního provozu* – 10 vlastních
  otázek, práh 8; **Dron A1/A3** (M6.1, viz níže); ostatní testy „připravujeme“ M4.1 / M4.6). **Pošta**: `World.send_mail(id, od, předmět, text)` – potvrzení
  objednávek a doručení, pozvánky na pohovor, pracovní smlouva, výzvy k zaplacení pokuty, upomínky nájmu, pozvánky na akce
  v obci 3 dny předem (háček M5.5), zprávy od dědy. **Hry**: Miny 9 × 9 (levé tlačítko odkrýt, pravé vlaječka). **Bankomat** (u Potravin
  a u obecního úřadu, E): výběr a vklad hotovosti. Deník J → Statistika: zůstatek, nepřečtené e-maily, balíky. Ladění: konstanty
  nahoře v `Computer` (`ESHOP_DISCOUNT`, `SHIPPING_KC`, `COD_KC`, `DELIVERY_DAYS`, `ATM_SPOTS`, `TESTS`, `NOTICE_BOARD`,
  `GOSSIP_*`, `DEDA_MAILS`), `Jobs.INVITE_DAYS` / `INVITE_BONUS`; F2 → Hráč „Počítač: +5 000 Kč na účet, balíky doručit hned“.
- **Pověst v obci** (`reputation.gd`, HUD vlevo, deník J): −100 až 100, stupně vážený občan / slušný soused /
  nenápadný / problémový / postrach vsi. Ubírá: řízení pod vlivem (i na kole, i bez svědků) a přes zákaz,
  zadržení policií, ujetí policii, sražení chodce či koně, nehody, poškození věcí, rychlá jízda obcí kolem
  lidí, zvracení a bezvědomí na veřejnosti, motání se opilý kolem lidí, urážky a vyhrůžky. Přidává: splněný
  úkol, čistá dechová zkouška, slušnost v rozhovoru (max. +2 denně od jedné postavy). Den bez přestupku →
  špatná pověst se pomalu lepší. Reagují vesničané (pozdravy, odpovědi, drby o tvých přestupcích), ceny
  (vážený −10 %, problémový +10 %, postrach +25 %), hospoda / sklep / pálenice postrachu nenalijí, policie
  špatně pověstné řidiče kontroluje častěji. Deník ukazuje rejstřík přestupků a poslední změny.
- **Respekt a karma** (`reputation.gd`, `persona.gd`, deník J → Vztahy): vedle pověsti dvě další osy. *Respekt* po 6 komunitách
  (`Reputation.COMMUNITIES`: sousedé, štamgasti, hasiči, fotbalisté, zemědělci a myslivci, mládež; postavu do komunity řadí
  `community_of` podle povolání, témat, místa a věku) −100…100: splněný úkol +6 komunitě zadavatele, slušný rozhovor +1 (max. +2 denně
  od jedné postavy), urážka −3; změna se ukáže jako „Hasiči: +3 – …“. *Karma* −100…100 je skrytá (v deníku jen slovně: čisté svědomí …
  prokletý): každý přestupek z katalogu zákona −1 až −5 (`OFFENSE_KARMA`, i bez svědků), urážka −1, nahlášená srážka +2, splněný
  úkol +1; `Reputation.luck()` (−0,2…+0,2) zvyšuje / snižuje šanci na neúspěch akcí (`Actions.fail_chance`). *Přátelství* (0…100,
  `Persona.friendship`, ukládá se s náladami): slušný kontakt +2 max. 1× za herní den, dárek `World.give_to_npc` (zatím bez UI), urážka −8;
  od 60 postava zdraví „kamaráde“ (M2.10 od ní čekej pomoc). Respekt i přátelství zvyšují vřelost postavy (`dialog_context` → `respect`,
  `friendship`, `attitude`). Tabulky dopadů: `Reputation.EVENT_EFFECTS`, `OFFENSE_KARMA`.
- **Noclehy** (`sleep_spot.gd`): kromě postele doma seník pod plachtou za hospodou a palanda pod přístřeškem
  u Myslivecké chaty (E: přečkat noc do 7:00, zdřímnout si 2 h, odpočívat do večera) a spacák z Potravin
  (890 Kč, Tab → rozložit kdekoli venku, ne na silnici). Venku se spí hůř (méně zdraví), v mrazu je zima,
  ve spacáku v dešti mokro.
- **Ukládání** (`save_game.gd`): `user://saves/*.json` – rychlá pozice (F5 / F9), automatická po každém
  vyspání a tři pojmenované pozice (F2 → Uložit / načíst). Ukládá čas a datum, počasí, hráče (poloha,
  peníze, inventář, tělo, zákaz řízení, pátrání), vozidla a koně, úkoly, pověst, sebrané předměty, skóre
  a nálady postav, zaměstnání (M3.1; M3.3 i varianta směn a rozdělaná zakázka), obecní údržba – posekaná tráva, odklizený sníh, lavička, odpadky (M3.2),
  vyznačené stromy a hromada dřeva lesního dělníka (M3.3, klíč `les`), počítač (M3.4, klíč `pc`: účet, pohyby, trvalý příkaz, pošta,
  objednávky a balíky u dveří, drby, výsledky eTestů; v `jobs` i výplata na účet a pozvánky na pohovor). Rozdělaný úkol se po načtení vrátí do nabídky. `--load=slot` načte pozici po startu.

## Co ve hře je

- **Celý katastr** (~5,2 × 4,6 km) bez načítacích obrazovek: terén 2 m mřížka (kolize =
  stejná data jako vzhled), 4 úrovně detailu terénu, stromy v MultiMesh s LOD,
  budovy a silnice s kolizemi.
- **Fasády budov (M1.2):** okna (rám, parapet, neprůhledné sklo se záclonou, občas okenice), dveře se schodem
  na straně k silnici, vrata garáží a stodol, komíny na domech; v noci část oken svítí (večer 17–22 h víc,
  v noci málo, ráno 5–7 některá). `BuildingDetails` staví jeden mesh na dlaždici 256 m z `data/buildings.json`;
  bez souboru se nevytvoří nic. Vzhled a pravidla podle typu budovy jsou v tabulce `BuildingDetails.RULES`,
  křivka svícení v `LIT_CURVE`. Dveře míst (hospoda, Potraviny…) a domova sedí s bodem `door_x/z` z `pois.json`.
- **Kouř z komínů (M1.3):** `priroda/chimney_smoke.gd` (`ChimneySmoke`, vizuál klienta) – pravděpodobnost, že dům topí, roste
  s mrazem (≥ 16 °C 3 %, 8 °C 35 %, 0 °C 85 %, ≤ −5 °C všichni; ráno a večer ×1,2, v noci ×0,7), volba domu je stálá po celý herní den
  (hash komína a dne). Kouř jde po větru, nad ~6 m/s se trhá, v mlze a při ranním mrazu za bezvětří se rozlévá nízko nad střechami,
  v dešti je kratší. Pool max. 24 emitorů nejbližších kouřících komínů do 350 m; bez `buildings.json` nic. Pravidla: tabulka
  `ChimneySmoke.SmokeRules`. Ladění: F2 → Počasí → Teplota −10 / 0 / +10 / +20 °C (`World.set_temperature`).
- **Interiéry (M1.4):** `interior.gd` (`Interior`) – vymyšlený vnitřek budovy v odděleném prostoru 400 m pod mapou a daleko za katastrem
  (`World.INTERIOR_BASE`, mřížka 60 m). E u dveří domova → „Vejít dovnitř“ → krátké ztmavení (0,3 s), teleport; uvnitř E u vnitřních dveří
  = ven před dveře, otočený od domu (dveře modelu z `BuildingDetails`, bez dat bod `door_x/z` z `pois.json`). Domov 9 × 7 m (`_build_home`):
  předsíň, kuchyň (linka 0,9 m, sporák, **lednička**, **kafe**, dřez, stůl), obývák (gauč, **kamna**, komoda s **rádiem**, stůl s **PC**), ložnice
  (**postel**, šatní skříň). Interakce `InteriorMenu` (`interior_menu.gd`): postel = spánek / zdřímnutí, lednička, kafe, dřez, rádio (stejná instance
  `Radio` se po vstupu přesune na komodu, při odchodu zpět na zahradu); kamna, šatník a PC jsou „(brzy)“. Strop a stěny mají `surface = "budova"` →
  uvnitř neprší; uvnitř se ztlumí světlo prostředí, déšť a vítr (`Atmosphere.indoor`); světla a okna sledují `Clock.daylight()`. `Player.inside`
  se ukládá (F5 / F9, autosave po spánku); F2 → Teleport → „Domov – uvnitř“. AI (zvěř, doprava, policie, počasí) používá `World.player_world_pos()`
  = vnější dveře, ne pozici pod mapou. Nový interiér: přidat `kind` do `Interior.build` a řádek do `World._spawn_interiors`.
- **Interiéry veřejných budov (M1.5):** `public_interiors.gd` (`PublicInteriors`) – vymyšlené vnitřky hospody U Hřiště (výčep s pípou, 7 stolů,
  šipky, TV, WC dveře, **sál s pódiem** pro budoucí kapelu), Potravin (pokladna, 4 regály, chladicí vitrína, košíky), obecního úřadu (chodba, podatelna
  s přepážkou, kancelář starosty bez vlajky a znaku, úřední deska), Pálenice U Kotla (měděný kotel, kolona, sudy, stůl s lahvemi), vinného sklepa
  (klenba, ležaté sudy, degustační stůl) a myslivecké chaty (krb, parůžky, stůl, palandy – nocleh zůstal venku). E u dveří místa → první položka
  „Vejít dovnitř“ (nabídka od dveří zůstala, kdo chce nakupovat rychle); mimo otevírací dobu jsou dveře zamčené a nabídka ukáže hodiny. Obsluha
  (`Place.keeper`) se po vstupu přesune za pult (`Place.set_inside`, `Interior.set_keeper`), venku stojí u dveří; E u pultu = stejná nabídka místa
  (`InteriorMenu` klíč `place:<místo>`). Štamgasti hospody sedí u prvního stolu, v pátek večer přibudou hosté u druhého; zahrádka je obsazená jen
  v létě za tepla, ve dne a bez deště (jinak jsou štamgasti uvnitř). Pověst „postrach vsi“ = obsluha nepustí dovnitř a uvnitř vyhodí; po zavírací
  době obsluha upozorní a po ~6 s hráče vyvede ven. Nový interiér veřejné budovy: větev v `PublicInteriors.build` + řádek v `World._spawn_interiors`.
- **Dům domov hráče** je ve hře ve stejném zjednodušeném stylu jako ostatní domy
  (detailní 3D model z mapy je v herní verzi odebraný) – viz níže.
- **Fyzika pohybu**: zrychlení/brzdění s rychlým otočením, hybnost ve vzduchu,
  proměnná výška skoku, coyote time a jump buffer (skok „odpustí“ pozdní/brzký stisk),
  těžší pád, sjíždění z příkrých svahů, přikrčení se kontrolou stropu, skluz ze sprintu,
  propružení kamery při dopadu, FOV podle rychlosti, pohupování hlavy v 1. osobě.
  Vizuál i kamera se interpolují mezi fyzikálními kroky → plynulé při libovolném FPS.
  U domu jsou míč, bedny a sudy do kterých jde strkat.
- **Boti**: 28 vesničanů chodí po silnicích a cestách (graf z OSM), zastaví se,
  otočí k hráči, zamávají a pozdraví; 7 psů pobíhá kolem domů a když přijdeš blízko,
  zaštěkají a běží za tebou. Daleko od hráče se boti hýbou bez fyziky (výkon).
- **Předměty** (88): hřiby v lesích (30), jablka pod stromy v zahradách (20),
  dukáty na silnicích v obci (30) a 8 **zlatých žaludů** ve vzdálených lesích
  katastru (svítící sloup viditelný zdálky). HUD ukazuje skóre, výdrž a směr
  k nejbližšímu předmětu.
- **Katalog předmětů a nosnost** (`items_db.gd`, `ItemsDB`): jeden katalog pro jídlo, pití, cigarety, vybavení,
  sběratelské předměty i data pro další kroky (nástroje, dřevo, semena, zbraně, střelivo…). Klíče: `name`, `type`,
  `kg`, `price`, `stack`, `durability`, `perishable_h`, `skill_req`, `points`. `Consumables.ITEMS` a `Item.INFO`
  jsou aliasy. Hráč unese `Player.CARRY_KG` = 25 kg; nad limit se předmět přidá, ale hráč je přetížený (rychlost
  × 0,6, žádný sprint, hláška „Neseš moc – zpomalíš.“). `Player.wear_tool(id)` opotřebovává nástroje
  (`durability` se ukládá). Nové typy jsou zatím jen v katalogu, bez akce v inventáři.
- **Drony (M6.1):** `dron.gd` (`Drone`, RigidBody3D), `drone_model.gd` (katalog + procedurální model),
  `permits.gd` (registry oprávnění – použije i doklady M4.6). Dva modely: **Ptáček Mini** (249 g, ~12 min letu,
  dosah 1 500 m) a **Ptáček Pro XL** (2,5 kg, ~15 min, dosah 2 000 m, vyžaduje osvědčení A1/A3); prodej
  v Potravinách i eŠuplíku (sekce Drony a technika), náhradní baterie se při startu sama vymění za vybitou.
  Let: „servo“ model (cílová rychlost z páček), vítr a turbulence, hover, automatický vzlet / přistání /
  návrat domů (RTH) při vybití (5 %), ztrátě signálu nebo na přání (F); baterie zkracuje mráz i sport;
  poškozený dron klesá, nad 55 % poškození nevzlétne (oprava na PC). Nárazy: ťuknutí = poškrábání,
  > 4 m/s = havárie a volný pád, strom = zaseknutí na 6 s, osoba / zvíře = zranění + přestupek; bzučení
  plaší zvěř do 45 m. **Pravidla ÚCL (zjednodušená herní simulace, ne právní rada):** registrace
  provozovatele povinná u dronu s kamerou (zdarma na PC → *Letectví – ÚCL*, evidenční číslo + e-mail),
  eTest „drony“ (10 otázek, práh 8) = osvědčení A1/A3 pro > 250 g; max **120 m** nad zemí (dron odepře
  stoupání), vizuální **dohled 500 m** (60 s mimo = přestupek), **ne nad lidmi** (~25 m), **soukromí**
  (> 30 s vrtění pod 30 m nad cizím pozemkem). Sedm nových přestupků v `data/zakon.json` – zapisují se
  jen když drona někdo uvidí nebo uslyší (svědci ~150 m v obci, policejní hlídka 400 m). Telemetrie a
  varování v OSD, fotky do `user://fotky_dron/`, smyčka bzučení `Sfx.drone_loop`. Stav flotily
  (baterie, poškození) i zaparkovaný dron se ukládají (`SaveGame` klíče `drones`, `permits`); nabíjení
  a oprava na počítači doma → *Letectví – ÚCL*. XP Letectví za uletěnou vzdálenost. Cheat F2 → Hráč
  „Drony + registrace ÚCL + A1/A3“. Ladění: `DroneModel.MODELS` (specifikace modelů), konstanty nahoře
  v `dron.gd` (limity, prahy, časovače), `Permits.KINDS`.
- **Létání – model (M6.3):** `scripts/flight/` = `aircraft.gd` (`Aircraft` extends `RigidBody3D`,
  vlastní integrátor), `thermals.gd` (`Thermals` – uzem světa „Termika“), `flight_hud.gd`
  (`FlightHud` – panel přístrojů + pipání variometru). Stroje jsou data v `Aircraft.SPECS`
  (klíč, nosná plocha S, CL(α) do kritického náběhu s přetáčením, CD0 + indukovaný odpor
  CL²/(π·AR·e), tah v N podle plynu a rychlosti, v_min / v_trim / v_max, nádrž a dolet);
  testovací „Létající bedna“ má parametry motorového paraglidu (S = 25 m², v_min 7 m/s).
  Vítr = `Weather.wind_vector()` s výškovým profilem v(h) = v10·(h/10)^0,14 + turbulence
  (bouřka, les, závětří kopce) + svislá termika (`Thermals.lift_at`): bubliny 0,5–3 m/s
  nad poli a sídly, léto 11–17 h, jasno/polojasno a > 18 °C, táhnou s větrem a žijí 5–15 min;
  nad lesem a vodou nevznikají. Podvozek s valivým odporem, rozjezd a vzlet, přistání
  (nad 3 m/s = tvrdé s poškozením a zraněním, náraz > 9 m/s = havárie), hranice letu
  `World.flight_bounds` (1 500 m AGL, 2 km za katastrem). Palivo chřadne s plynem, bez něj
  jen klouzavý let. Pilot opilý = zpožděné reakce (vzor Car) a přestupek
  `letectvi_pod_vlivem` (49/1997 Sb., ověřit) když ho vidí svědek. XP Letectví za uletěné
  metry (zapisuje se při dosednutí). Ukládá se klíč `aircrafts` (pozice, yaw, palivo, dmg,
  „sedí ve stroji“; starý save bez klíče = žádné letouny). Spawn: F2 → Vozidla →
  Testovací letoun. Ladění: `Aircraft.SPECS`, konstanty nahoře v `aircraft.gd` a `thermals.gd`
  (mimo jiné `Thermals.DEBUG_R` > 0 = fixní testovací bublina nad hráčem).
- **Létání – paramotor (M6.4):** `scripts/flight/paramotor.gd` (`Paramotor extends Aircraft`, model
  `paramotor` v `Aircraft.SPECS` – křídlo 24 m², tah 650 N, nádrž 11 l). Start je stavový automat na
  zemi (`pg_state`: laid → carried → wing_up → let): rozložení z batohu (`World.pg_prepare`), nahození
  rozběhem proti větru, fumble při plynu před křídlem, vytržení ve větru > 8 m/s. Řízení brzdami
  (A/D strany, S obě – hluboký tah → stall/propad), trimry (Mezerník), „uši“ (Ctrl), částečné
  zavření křídla v turbulenci (srovnání opačnou brzdou), flare přistání na nohy. Háčky v
  `aircraft.gd`: `_extra_drag/_lift_scale/_v_max_bonus/_bank_target/_flare_ok/_flare_land`;
  továrna `Aircraft.make`. Model MeshKit: motor s klecí a vrtulí, závěsy se ~16 šňůrami, loft křídlo
  ~10 m rozpětí jako kyvadlo ~6,6 m nad pilotem. Koupě: obchod/eŠuplík (`paramotor` 180 000 Kč,
  `paramotor_ojety` 90 000 Kč – položky 25 kg, `Cargo.CARGO["paramotor"]`). Průkaz
  `pilot_pg_motor` + registrace `pg_registrace` + pojištění `pg_pojisteni` (`Permits.KINDS`, PC →
  Letectví – ÚCL; škola 35 000 Kč = eTest `data/testy/paramotor.json` + 5 výcvikových vzletů s
  instruktorem „rádiem“, stav `Computer.pg_school` / save klíč `pg_skola`). Nové přestupky
  `pg_*` v `zakon.json` – svědek hluku ~800 m (`World.pg_noise_witnessed`), „obec“ ~350 m od místa
  (`pg_over_village`). Spawn i bez batohu: F2 → Vozidla → Paramotor.
- **Létání – motorové rogalo / trike (M6.5):** `scripts/flight/trike.gd` (`Trike extends Aircraft`,
  model `trike` v `Aircraft.SPECS` – rogalo 15 m², tah 1 800 N, nádrž 50 l, ~200 kg, 2 sedadla;
  v_min ~55 km/h, cestovní ~90 km/h, max ~130 km/h) a `scripts/flight/airfield.gd` (`Airfield` –
  polní letiště). **Dráha:** práh A (x −440, z 240), směr 30°, délka 260 m, šířka 16 m – louka
  (landuse 2) JZ od návsi, sklon ~1,4 %, bez stromů/zástavby; konstanty `RWY_A/RWY_HEADING/RWY_LEN`
  nahoře v `airfield.gd`. Vizual: posekaný pás MeshKit + pražce, větrný rukáv (točí se po
  `Weather.wind_vector`, pokles podle síly větru), otevřený hangár s kolizí (static layer 1),
  inzertní cedule → `World.ul_buy_trike` (ojetý trike 350 000 Kč hotově, spawn před hangárem).
  **Řízení hrazdou:** realisticky obrácené (S = nahoru, A/D zatáčí naopak; `Trike._bank_target`),
  přepínač „Intuitivní řízení rogala“ v Nastavení → `GameSettings.trike_intuitive`
  (`nastaveni.cfg` klíč `rogalo_intuitivni`). Plyn = páka držící polohu (`_lever`, Shift/Ctrl);
  na zemi A/D příďové kolo + Mezerník brzda (`_mu_ground` = 0,06 – delší rozjezd na trávě).
  Háčky v `aircraft.gd`: `_mu_ground`, `_takeoff_hint`. Vizuál MeshKit: kapotáž, 3 kola (řízené
  příďové), tlačná vrtule, stožár, delta plachtovina (2 trojúhelníkové panely), lanka, A-hrazda.
  **Průkazy:** `pilot_ul` (škola 75 000 Kč = eTest `data/testy/ul.json` práh 8/10 + 10 výcvikových
  vzletů, stav `Computer.ul_school` / save klíč `ul_skola`, řízení `World.ul_enroll /
  ul_theory_passed / ul_training_takeoff / _ul_try_grant`), `ul_registrace` (1 500 Kč),
  `ul_pojisteni` (3 000 Kč) – PC → Letectví – ÚCL. **Přestupky `ul_*`** v `zakon.json`
  (`ul_bez_prukazu/registrace/pojisteni`, `ul_pristani_mimo`, `ul_nizko_nad_obci`, `ul_nad_lidmi`,
  `ul_noc`, `ul_mraky`) – svědek hluku ~800–900 m (`World.pg_noise_witnessed`), `Airfield.on_runway`
  pro přistání na dráze (nouze vyjmuta – zjednodušeně jen svědek). **Spolujezdec:** vesničan s
  přátelstvím ≥ 60 v dosahu 14 m (`World.trike_interactables`, `Trike.board_passenger/_pax_off`) –
  bubliny `PAX_LINES`, +8 přátelství a +3 pověst za svezení. Teleport F2 → *Letiště*
  (`Airfield.teleport_spot`). Další stroje (samostatný UL letoun, vrtulník) = otevřené body.

## Návody

- [`BLENDER_UPRAVY.md`](BLENDER_UPRAVY.md) – ruční úpravy mapy v Blenderu (budovy, silnice, stromy, terén, textury) a export do hry
- [`VLASTNI_VOZIDLA.md`](VLASTNI_VOZIDLA.md) – nová auta (procedurálně i z vlastního `.glb` modelu), kola a motorky
- [`ASSETY.md`](ASSETY.md) – legální assety z internetu: kde hledat, checklist licencí, import, registr `assets/LICENSES.md`, `tools/assets_check.py`
- [`ZVIRATA.md`](ZVIRATA.md) – úprava zvířat, ptáků, počasí a ročních období (tabulky, náhled `zoo.gd`)

## Jak vzniká herní mapa

```
mapa_okoli.blend
   │  tools/domov_hrace.py      – dům hráče stejnou metodou jako ostatní budovy (půdorys OSM/RÚIAN,
   │                           tvar a výška střechy fitem na DMP 1G, barva střechy z ortofota)
   ▼  tools/export_map.py    – (Blender, headless)
blend/mapa.blend   herní verze mapy: model domu odebrán, jednoduchý dům hráče přidán,
                                terén pod bývalým modelem vrácen na DMR 5G
data/*.bin, data/map.json       geometrie a metadata pro Godot
textures/                       PBR textury (Poly Haven) + ortofoto (jen pro porovnání, ve hře se ve výchozím stavu nepoužívá)
```

Regenerace dat (z kořene repozitáře):

```bash
python3 tools/domov_hrace.py
blender --background --python-exit-code 1 --python tools/export_map.py
rm -rf data/orig && python3 tools/clean_road_clashes.py
python3 tools/pois.py
python3 tools/water.py      # vždy až po exportu – čte terrain_height.bin, silnice a trees.bin
```

`water.py` čte vodní toky z `geodata/pbf/zlinsky-latest.osm.pbf` (pyosmium) a zapisuje `data/water.json`
(osy toků s hladinou, nádrže, stromy stojící ve vodě) a `data/water_carve.bin` (DBW1: změněné body výškové
mřížky – index, nová výška, normála RGB8; `Terrain` je aplikuje při načtení na vzhled i kolizi). Původní
`terrain_*.bin` zůstávají beze změny.

`clean_road_clashes.py` vyřadí chybně umístěné budovy a stromy, které stojí ve vozovce (síť silnic
sedí na ortofotu, tyto objekty ne); originály nechá v `data/orig/`. Ruční úpravy v Blenderu
patří do kolekcí `HRA_*` (viz `BLENDER_UPRAVY.md`), exportér je přidá.

Krajina za okrajem katastru (M6.2, pro pohled z výšky – dron, později paraglide): `tools/surroundings.py`
stáhne z ČÚZK DMR 5G (ImageServer, stejný zdroj jako mapa – © ČÚZK CC BY 4.0) nízkorozlišenou výškovou
mřížku okolí (katastr + ~2,5 km na každou stranu, krok 25 m) → `data/surround_height.bin` a z OSM
(`geodata/pbf/zlinsky-latest.osm.pbf`) hrubou masku povrchu (les / pole / louka / zástavba / voda)
→ `data/surround_surface.bin`. Oba .bin nejsou v gitu.

```bash
python3 tools/surroundings.py               # stáhne DMR ČÚZK + maska z OSM
python3 tools/surroundings.py --no-download # jen přegenerovat masku / navázání
```

Kreslí je `scripts/surroundings.gd` (`Surroundings`, uzel „Okoli“ ve World): LOD dlaždice ~2 km,
výšky ve vertex shaderu (`shaders/surroundings.gdshader`), paleta tříd jako `terrain.gdshader`,
oblast katastru zapuštěná pod detailní terén (žádný šev), les jako tmavší povrch + MultiMesh kuželů
do 4 km, bez kolizí a stínů. Bez dat vznikne plochá zvlněná krajina ve výšce okraje (fallback).

Formáty: `terrain_height.bin` (float32, řádky od severu, 2 m), `terrain_collision.bin`
(výšky / 2 pro HeightMapShape3D škálovaný ×2), `terrain_normal.bin` (RGB8),
`walls/roofs/asphalt/gravel.bin` (DBM1: trojúhelníky po dlaždicích 256 m – pozice,
normála, barva `tint`), `tree_protos.bin` (DBT1), `trees.bin` (DBI1: x, y, z, rotY,
sx, výška, sz, barva, prototyp). Souřadnice Godotu: X = x, Y = z, Z = −y scény Blenderu.

## Ladicí parametry

`godot --path . -- --shot=snimek.png [--view=fp] [--pos=x,z] [--yaw=°] [--pitch=°] [--zoom=m] [--time=h] [--top=m] [--map] [--novsync]`
(`--vsync=off|fifo` jiný režim vsync – výchozí je mailbox, `--maxfps=n` strop snímků/s; `run.sh` na Waylandu
spouští nativní Wayland místo XWayland – kvůli zasekávání obrazu při nehybné myši, vypnout `DUKELČICE_X11=1`)
uloží snímek a skončí (`--top=70` = pohled shora na čtverec 70 m, střed `--pos`); `--testmove` projede
chůzi/sprint/skok/skluz, `--bottest` pohyb botů, `--drinktest` křivky promile, `--cartest [--aionly]`
zrychlení/brzdění a AI jízdu hospoda → domov, `--exittest` výstup z auta (poloha, zdraví, stav auta),
`--drive[=id]` start ve vozidle (`kolo`, `jawa` nebo libovolný model z `CarModel.MODELS`), `--questtest [--stopshot=x.png]` všech 6 úkolů
(selhání i splnění přes skutečné nabídky a jízdu), `--traffictest [--dur=s]` provoz – hlásí auta, která visí,
`--faunatest [--shotdir=adr]` zvěř (pastva → útěk) a jízda na koni, `--naturesynctest` loopback přípravy přírody
na multiplayer (snímky zvěře a hejn do klientské Fauny, odchylky poloh, velikost snímku, Clock / Weather round-trip; 60 s, pak skončí),
`--weathertest` přilnavost a brzdná
dráha auta za všech situací + expozice těla. `--date=RRRR-MM-DD` datum 1. dne,
`--weather=druh` vynucené počasí (`jasno`, `polojasno`, `oblacno`, `zatazeno`, `mlha`, `prehanky`, `dest`,
`bourka`, `snih`). Náhled modelů zvířat: `godot --path . --script res://tools/dev/zoo.gd -- --series=adresář`.

Letové hranice (M6.2, platí pro dron a budoucí letouny M6.3+ – napojení přes `World.flight_bounds(pos)`
→ `{ok, warn, push, out, agl}`): strop `World.FLY_CEIL_AGL` = 1 500 m nad terénem (měkké odepření –
tlačí dolů), vodorovná hranice `World.FLY_LIMIT_M` = 2 km za obdélníkem katastru – v pásmu
`World.FLY_WARN_M` (400 m) před ní měkké odpuzení protivětrem (`World.FLY_PUSH_MS`) a varování
„Dál už nelétej – opouštíš oblast“, za hranicí návrat domů. Chodce a auta drží stále neviditelné
zdi `Terrain._add_bounds`. Kontrola okolí z výšky: F2 → Teleport → Ladění → „Volná kamera ~500 m
nad hráčem“ (WASD let, myš pohled, Mezerník/Ctrl výška, Shift rychle, V zpět). Mlha se nad ~150 m
AGL ředí (`Atmosphere`) a dohled dalekých stromů se násobí (`MapLoader.set_tree_far_mult`).

Data polí: `python3 tools/landuse.py` (OSM z `geodata/pbf/zlinsky-latest.osm.pbf`, potřebuje `osmium`, `numpy`,
`Pillow`) vytvoří `data/landuse.bin`. Krok 03 (pole, sezónní předměty, události) ladí tabulky `Fields.CROPS`,
`World.SEASON_ITEMS`, `VillageEvents.EVENTS`, `Place.WEEK_HOURS`; datum se přepíná v F2 → Datum.

Terén bez ortofota (M1.1): barvu terénu skládá `shaders/terrain.gdshader` z tříd povrchu (tráva, orná půda, sad,
les, dvůr, břeh, skála podle sklonu, polní cesta) s prolínáním hranic a sezónou (`grass_green`, sníh, mokro, pole
z `landuse.bin`). Maska povrchu: `python3 tools/surface.py` (stejné závislosti jako `landuse.py`) vytvoří `data/surface.bin`
(magic `SURF`, rastr 4 m, 1 B na buňku; laditelné konstanty `FOREST_MIN`, `BUILDING_R`, `WATER_R`, `TRACK_W`). Bez něj shader
odvodí třídy z `landuse.bin` a hustoty lesa. Dlaždicové textury (Poly Haven, CC0, 1k) patří do `assets/textures/terrain/`,
seznam je v `ASSETY.md`; když chybí, použije se procedurální barva a šum. Minimapa (M) se kreslí z tříd povrchu
(`SurfaceMap.make_map_image`). F2 → „Terén: …“ přepne na ortofoto a zpět.

Fasády (M1.2): `python3 tools/buildings.py` (jen standardní knihovna) sloučí podklady `data/buildings_3d*.json` (půdorys OSM,
výšky okapu a hřebene z DMP 1G, tvar střechy), `tools/out/domov_hrace.json` a `data/pois.json` do `data/buildings.json`
(typ budovy, plocha, hřeben, `poi`, `home`, bod dveří u nejbližší silnice). Generátor `scripts/building_details.gd`
z něj skládá okna, dveře, vrata a komíny; sklo řeší `shaders/window_glass.gdshader` (jeden uniform `lit_frac` pro noční svícení).

Poznámka: po přidání skriptu s novým `class_name` je třeba obnovit seznam tříd
(`godot --headless --path . --import`, dělá to i `run.sh`), jinak Godot hlásí „Could not find type …“.
Testy spuštěné přímo přes `godot` bez okna (`--headless`) vypisují při pití/jídle `Parameter "m" is null`
(bez rendereru) – na výsledek to nemá vliv.

## Architektura (příprava na multiplayer)

| Skript | Za co odpovídá |
|---|---|
| `main.gd` | tenký start: vytvoří `World` a `LocalClient`, přidá hráče id 1, spustí ladicí parametry / testy |
| `world.gd` (`World`) | simulace – v MP server: terén, mapa, čas, `players` (id → Player), `quests` (id → Quests), boti, místa, doprava, policie, předměty, ekonomika a pravidla (nehody, zadržení, okno, spánek); akce hráčů jako metody s id (`enter_car`, `buy`, `sleep`, `player_action`…) |
| `local_client.gd` (`LocalClient`) | lokální hráč: vstup → `InputState`, klávesy E/F/L/B/R/H → akce `World`, HUD a nabídky míst, kamera, `DrunkFx`, zvuky, obloha/světlo, značka cíle, snímky |
| `input_state.gd` (`InputState`) | vstup jednoho hráče (pohyb, řízení, pohled, skok, sprint, přikrčení) – čte ho `Player` i `Car`; v MP se bude plnit ze sítě |
| `quests.gd` | úkoly **jednoho** hráče (každý hráč vlastní uzel a instance úkolů) |
| `police.gd` | pronásleduje / kontroluje konkrétního hráče; zákaz řízení a pátrání má každý hráč (`Player.license_suspended_until`, `wanted_until`) |
| `traffic.gd` | auto každého hráče (`car_of(id)`), AI auta se rozmisťují kolem hráčů |
| `villager.gd`, `dog.gd`, `npc.gd` | reagují na nejbližšího hráče (`World.nearest_player`) |
| `characters.gd`, `persona.gd`, `dialog.gd` | smyšlené postavy, jejich paměť vůči hráčům, odpovědi na volný text (`World.player_say`, `dialog_context`) |
| `reputation.gd` | pověst **jednoho** hráče (`World.reputations[id]`), vyhodnocuje události z `emit_game_event` |
| `save_game.gd` | uložení / načtení pozice do běžícího světa (singleplayer) |

Svět posílá hráči zprávy jen přes `World.notify(id, metoda_hud, …)`, `play_sfx(id, …)`, signál `sound`
(zvuk v místě) a `emit_game_event(id, druh, data)` (úkoly hráče + prezentace u jeho klienta) – tato
místa se v úkolu 03 nahradí RPC.

## Licence dat

Geodata © ČÚZK (CC BY 4.0), OSM © přispěvatelé OpenStreetMap (ODbL), textury a HDRI Poly Haven (CC0).
Ortofoto ČÚZK se ve výchozím stavu nepoužívá (jen na přepnutí F2 → Terén, soubory `textures/ortho_*.jpg` zatím zůstávají).
Všechny externí assety (modely, textury, zvuky, hudba) jsou v registru `assets/LICENSES.md` + `assets/licenses.json`;
`python3 tools/assets_check.py` hlídá neevidované soubory a nepovolené licence a generuje `data/credits.json`
(titulky CC BY se ukážou v nápovědě F1). Načítání v kódu: `AssetLib.load_model / load_sound / has` (`scripts/asset_lib.gd`).

## Právní zásady obsahu

Shrnutí z `PRAVNI_DOPORUCENI.md` – platí pro všechen nový obsah:

- **Zdroje dat:** jen ČÚZK (DMR/DMP, ortofoto – CC BY 4.0) a OSM (ODbL). Nic z Google Maps / Earth /
  Street View ani z Bingu. Uvedení zdrojů je v `data/map.json` (`license`), na úvodní obrazovce a v nápovědě F1
  (`Hud.CREDITS`).
- **Žádné reálné identifikátory:** všechna čísla popisná ve hře jsou smyšlená (M1.7, `Estate` – číslování od návsi ze seedu, nic
  z RÚIAN / ČÚZK; skutečné číslo původního domu hráče se nezobrazí), cedulky s číslem mají obecný vzhled bez znaku obce,
  žádná jména na schránkách a zvoncích, žádné průhledy do soukromých dvorů a oken. SPZ se generují
  s písmenem Q, které se v českých SPZ nevydává (`Traffic.plate()`).
- **Postavy:** jen smyšlená jména, žádné podobizny ani narážky na skutečné obyvatele obce. Vesničané
  (`characters.gd`) mají vymyšlená, spíš humorná jména a obecná povolání; nová jména nesmí odpovídat
  skutečným obyvatelům a texty nesmí zmiňovat skutečné sousední obce, firmy ani úřady.
- **Značky:** místo ochranných známek se používají smyšlené nebo parodické názvy (auta Oktávka / Fábička /
  Stodvacka, motorka Javor, kolo Favorín, Bylinkovka, Hořká; smyšlené podniky Hospoda U Hřiště, Pálenice U Kotla…).
- **Obecní symboly:** znak a prapor obce se ve hře nepoužívají.
- **Rádio:** vlastní stanice ve hře jsou smyšlené a hudba je generovaná. Internetové stanice v `data/radia.json`
  jsou jen odkazy na veřejné streamy Českého rozhlasu, které hra přehrává u hráče jako běžný internetový
  přijímač (nic nenahrává ani nešíří, žádná loga). Názvy stanic jsou ochranné známky provozovatele – před
  veřejným šířením hry je vhodné `radia.json` vyprázdnit, nebo si vyžádat souhlas.
- **Doložka:** úvodní obrazovka, nápověda F1 a začátek tohoto README (`Hud.DISCLAIMER`).
