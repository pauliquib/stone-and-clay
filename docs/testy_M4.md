# Checklisty ručních testů – M4 Zákon a společnost

## M4.1 – Řidičská oprávnění a autoškola

Cheat: F2 → Teleport (úřad) / F2 → Hráč. Nová hra = řidičák B + AM.

1. Nová hra → P (doklady): řidičský průkaz se skupinami B a AM; ostatní doklady „nemáš“.
2. Nasedni do Krosáku 1000 (skupina A) nebo Javoru 250 (A2) → hláška „Na tohle nemáš řidičák“; jeď → policejní kontrola → přestupek „bez řidičáku“, pokuta a body.
3. Autoškola (PC doma → vesnet://autoskola-volant/) → zápis do kurzu A2 (9 900 Kč); PC eTest „autoskola“ – nejdřív neprojdi, pak projdi (20 otázek, 85 %).
4. Výcvik: 3× nasedni do auta skupiny A2 (třeba Armádka 750), odjeď aspoň 300 m od úřadu a vrať se k jeho dveřím → hlášky „Jízda 1/3…3/3“.
5. Po splnění teorie + 3 jízd → zpráva v počítači a P ukazuje skupinu A2 (i A1).
6. Jízda z úřadu (krátká, 50 m) nebo výstup mimo úřad → žádná jízda se nepočítá (instruktor hlásí).
7. F2 → Hráč → cheat 12 bodů (nebo opakované přestupky) → P „ODEBRÁNO … nutné přezkoušení“; po zákazu PC → autoškola nabídne přezkoušení (skupina B).
8. Starý save (z doby před M4.1) → načíst → P: B, AM, A; motorka bez přestupku; drony / paramotor doklady zůstaly.
9. Dron / paramotor / rogalo funguje beze změny (registrace, pojištění, teorie).
10. F5 → F9 (uložit a načíst) → P a stav kurzu autoškoly zůstanou.

## M4.5 – Dobré skutky a přátelství (prosby vesničanů, dárek, oblíbené)

Spouští jen uživatel. Stav: staticky ověřeno (kontrola překladu), ruční test čeká.

1. Jdi k vesničanům v obci (blízko postavy, do ~3 m) a stiskni **E** – nabídka ukáže přátelství a případnou prosbu.
2. Najdi vesničana s prosbou („★ Přijmout“), přijmi ji. Ostatní prosby téhož dne by měly být u jiných lidí.
3. Prosba „zahrada“: sklidit na zahradě 2× (zmínka v deníku / hlášce „Prosba splněna“). Prosba „sníh“: dobrovolný úklid sněhu (`snow_volunteer`).
4. Prosba „nákup“: měj v inventáři jídlo (např. rohlík), E u vesničana → „Dát: …“ → hláška „Prosba splněna“, přátelství a pověst nahoru.
5. Nesplň přijatou prosbu a přejdi do dalšího herního dne → hláška „Zklamals mě“, přátelství klesne o 10.
6. E u vesničana → „Dát: …“ s oblíbeným předmětem (povolání / koníček s pivem, vínem, zahrádkou…) → výrazně větší přátelství než u jiného předmětu.
7. Přátelství ≥ 40 se v nabídce ukáže jako „Výhody: pomůže s nošením…“, ≥ 60 navíc „nenahlásí drobný přestupek…“ (zatím jen text, efekt čeká na M4.4).
8. Starý save (bez klíče `favors`) se musí načíst bez chyby; prosby mají být prázdné.
9. F5 → F9 (uložit / načíst) uprostřed dne: nabídky a stav přijatých proseb zůstanou.
10. Deník J / F1 – zkontroluj, že se nic nerozbilo (E u vesničanů stále otevírá rozhovor přes „Promluvit“).

## M4.2 – Správní řízení na úřadě, dluhy a exekuce

Spouští jen uživatel. Stav: staticky ověřeno (kontrola překladu), ruční test čeká.

1. Rychlost v obci (na místě, `rychlost_obec`) → policista: s hotovostí pokuta hned zmizí z peněz (hláška „zaplaceno“); bez hotovosti vznikne dluh „bloková pokuta“ (F2 → Hráč: peníze 0, pak deník J → Úřední záznamy).
2. Řízení pod vlivem do 1 ‰ (`alkohol_do_1`, správní řízení) → hláška „příkaz přijde poštou“; za 1–3 herní dny e-mail „Příkaz k úhradě pokuty“ a dluh v deníku se splatností.
3. Na úřadě (v úředních hodinách, Po/St 7–17) E u úřednice → „Zaplatit pokuty a dluhy z hotovosti“ → peníze klesnou, dluh zmizí. Mimo hodiny nabídka není.
4. Počítač doma → Banka → Pokuty: seznam dluhů se stavem a splatností, „Zaplatit z účtu“ vybere z účtu.
5. F2 → Datum: posuň o 16 dní po splatnosti → e-mail „Upomínka“, dluh +1 000 Kč (stav upomínka).
6. Další F2 → Datum +30 dní → e-mail „Exekuční příkaz“, z účtu se strhne částka, pověst −5 (stav exekuce).
7. Skok přes víc měsíců (F2 → Datum) → dluhy se dohání po dnech, žádný dluh nezmizí ani nezdvojí.
8. Starý save s nezaplacenými pokutami (klíč `law.unpaid` > 0) se načte bez chyby: jeden dluh „Nezaplacené pokuty (starší)“, částka v bance i v deníku stejná.
9. Hráč s M4.1: 12 bodů / odebrání řidičáku se chová jako dřív (nic se nerozbilo).
10. F5 → F9 uprostřed dne: dluhy, upomínky, čekající příkazy a jejich dny zůstanou.

## M4.4 část A – Svědci a nenahlášené činy

1. Pokácení stromu v lese za dne přímo před vesničanem (do ~10 m, čelem) → většinou popup „Někdo tě při kácení viděl!“ a přestupek; bez vesničana v dohledu (pár set metrů) → žádný popup.
2. Stejné kácení v noci (F2 → Datum/čas na půlnoc) před vesničanem ve stejné vzdálenosti → svědek vidí podstatně méně často (noc = ¼ dohledu).
3. Kácení před vesničanem s přátelstvím ≥ 60 (ověř přes rozhovor / dary) → přestupek skoro nikdy nevznikne; před cizím „přísným“ vesničanem ano.
4. Kácení v cizím lese bez svědků → žádný popup ani přestupek; záznam zůstane v nenahlášených (přežije F5 → F9).
5. Výstřel z pušky (bez zbrojního oprávnění) nebo střelba pod vlivem u vesničana v dohledu → hlášení „Někdo tě viděl…“; za stěnou / v mlze (F2 → Počasí, mlha) méně.
6. Oheň u lesa (ohniště u okraje lesa) před obsluhou místa → popup a přestupek; v noci bez svědků jen varování a karma.
7. Nehoda autem před hlídkou (F2 → Teleport k silnici, najet do stromu před policií) → přestupek „Dopravní nehoda se škodou“ v pokutách (Počítač → Banka → Pokuty); srážka chodce → „Srážení chodce“ a pokuta 10 000–40 000 Kč (orientační).
8. Nehoda bez svědků (mimo obec, v noci) → žádné hlášení; zpráva o nenahlášeném činu se neobjeví ve hře, jen v uložené pozici (ověř přes F5 → F9 bez pádu).
9. Starý save (před M4.4, s klíčem `forestry.unreported`, pokud existuje) se načte bez chyby; pokácené stromy a pařezy zůstanou.
10. Pověst: po kácení/střelbě u vesničanů se pověst mění stejně jako dřív (`_witnesses` v pověsti počítá jen ty, kdo vidí); nic nehlásí v prázdné pustině.
## M4.3 – Soud a vězení

1. Řízení s 1,5 ‰ (F2 → Hráč → promile) → záchytka do rána a hlášení „Obvinění (trestný čin)“; rejstřík (P / deník J) zatím prázdný.
2. F2 → Datum posuň o 3–7 dní → přijde pošta „Předvolání k soudu“ s termínem (9:00, za X dní).
3. V den termínu ve 9:00 stůj u úřadu (do ~40 m od dveří) → menu „Soud – …“; zvol „Přiznat a litovat“ → zatemnění, hlášení ROZSUDEK, zákaz řízení (P ukazuje odebraný řidičák).
4. Peněžitý trest se objeví v dluzích (banka → Pokuty, deník J → Úřední záznamy); zaplať na úřadě (E u úřednice).
5. Nepřijď do 11:00 → pošta „Rozsudek“ v nepřítomnosti a zatykač (policie tě zadrží při setkání).
6. Podmínka (vyber „Zapírat“ nebo jiný rozsudek s podmínkou); další trestný čin během podmínky → nepodmíněný trest: „Nastupuješ výkon trestu (N měsíců)“, po zatemnění propuštění u úřadu a pošta se shrnutím (pověst, dluhy).
7. Zaměstnaný hráč (Práce) po nástupu do vězení dostane výpověď „nástup do vězení“ (deník J → Práce).
8. Práce s požadavkem „čistý rejstřík“ (`rejstrik_cisty`) tě nevezme, dokud tě soud neodsoudí; obvinění samo o sobě nevadí.
9. Starý save (bez klíče `court`) se načte bez chyby; případy jsou prázdné.
10. F5 → F9 uprostřed předvolání (před jednáním): případ, termín a stav „předvolán“ zůstanou.

## M4.4 část B – Vyhlášky, pálení, sucho

1. Úřední deska (Počítač → Úřední deska) ukazuje „Nedělní klid“ vždy; „Zákaz pálení“ jen v červenci a srpnu (F2 → Datum).
2. Pokácení stromu v lese → v kapse přibude „Čerstvé větve (klestí)“, ne suché „Větve (klestí)“.
3. Přeskoč ~30 dní (F2 → Datum) → čerstvé větve se změní na „Větve (klestí)“; za sucha a horka proschnou dřív.
4. Přiložení čerstvých větví do ohniště → kouř; vesničan v dohledu → popup „Někdo tě viděl a nahlásil kouř z ohně“ a přestupek „Pálení čerstvých (mokrých) větví“ (Počítač → Banka → Pokuty); bez svědka jen hláška o kouři a záznam v nenahlášených.
5. V červenci přiložit suché větve do ohně dál než 30 m od domu, před vesničanem → přestupek „Porušení obecně závazné vyhlášky obce“; u domu → žádný přestupek.
6. V červenci přiložit polena (ne větve) → žádná vyhláška, oheň funguje jako dřív.
7. Opékání špekáčků na táboráku v červenci u domu → bez přestupku.
8. Dlouhé sucho (F2 → Datum, několik dní bez deště, horko) → na desce přibude „Zákaz zalévání a napouštění z vodovodu“; po dešti zmizí.
9. Starý save (bez klíčů `vyhlasky` a `weather.drought`) se načte bez chyby; čerstvé větve nejsou, sucho = 0.
10. F5 → F9 po odvětvení: čerstvé větve v kapse i jejich stáří sušení zůstanou.

## M4.7 – Katastr: koupě a prodej nemovitostí

1. Úřad → „Katastr – koupě a prodej nemovitostí“ (F2 → Teleport → Úřad, peníze přes F2 → Hráč): nabídka ukazuje domy a parcely jen v domácí obci, žádná z okolních obcí.
2. Koupit dům (cheat peníze) → zaplatí se cena + 1 500 Kč; v menu se objeví „Vklad: … zbývá 20 dní“.
3. Přeskoč 20 dní (F2 → Datum) → přijde pošta „Vklad proveden“ a dům je v menu jako vlastněný.
4. „Nastavit … jako domov“ → domov (dveře, parkování, cedulka) se přesune do nového domu; spaní vede tam.
5. Koupit parcelu (pole / louka) → po 20 dnech v poště; parcela je vlastněná, na trhu už není.
6. „Prodat … obci“ → peníze hned (60 % ceny), parcela zmizí z vlastněných.
7. „Nabídnout … kupci“ u vlastního (ne domácího) domu → po několika dnech pošta „Prodej proveden“ a peníze v hotovosti.
8. Domov nejde nabídnout k prodeji (hláška o odstěhování).
9. Uložit (F5) → načíst (F9): vlastnictví a rozjednané vklady zůstanou; starý save se načte bez chyby (katastr prázdný).
10. Rozhovor / mapa: parcely a domy na prodej nejsou mimo hranici domácí obce (mapa M, hranice `meta.boundary`).
## M4.6 – Zbraně, lov a rybolov podle zákona (doklady, hajný, rybářská stráž)
1. F2 → Teleport do myslivecké chaty, u dveří E → „Myslivecký a rybářský spolek“: zaplať kurz zbrojního průkazu (4 000 Kč) a lovecký kurz (5 000 Kč); bez zaplaceného kurzu test doklad nevydá.
2. Počítač doma (E) → eTesty → Zbrojní průkaz, Lovecký lístek: složit (prah 75 %) → hlášení „Doklad vydán“; panel P ukazuje doklady.
3. V chatě koupit povolenku k lovu (1 500 Kč, 30 dní) a rybářský kurz (1 000 Kč) + test „Rybářský lístek“; pak povolenku k rybolovu na rok (1 800 Kč).
4. Legální lov srnce s puškou a dokladem, v době lovu, ve dne, mimo obec → výstřel bez přestupku.
5. Pytlák: v lese za šera vystřel na zvěř bez dokladů; hajný (F2 → Teleport do lesa u chaty) přijde za výstřelu (slyšet do 1,5 km) a přijde ke hráči (do 15 m) a při kontrole zapíše přestupek „Pytláctví“, pokud má nelegální úlovek.
6. Hajný u hráče: „Ukázat doklady“ s nelegálním úlovkem → zápis přestupku; bez úlovku a s dokladem → „V pořádku, lovu zdar.“
7. Utéct hajnému (volba „Utéct“) → po dobu ~2 h herního času hledá policie (wanted).
8. Rybaření bez lístku o víkendu ráno (sobota/neděle, 5–12 h) → rybářská stráž u hráče při kontrole zapíše přestupek „rybářské pytláctví“ a hlášku „Zapisuji: rybaření bez lístku a povolenky“.
9. Starý save (bez klíče `gamekeeper`) se načte bez chyby, kurzy jsou prázdné; F5 → F9 zachová zaplacené kurzy a doklady s platností.
10. Povolenka k lovu po uplynutí 30 dnů (F2 → Datum +31 dní) přestane platit (`has` vrací false) a jde koupit znovu.
## M4.8 – Návykové látky (obsah pro dospělé; částečně, viz PROJECT_LOG)
1. Nová hra (volba výchozí vypnuta): Potraviny nenabízí semena tabáku ani konopí; F1 a deník J bez zmínek o látkách.
2. Esc → Nastavení → zaškrtnout „Obsah pro dospělé“ → Potraviny: semena tabáku (45 Kč) a semena konopí (60 Kč) jsou v nabídce.
3. Zasadit tabák a konopí na zahradě (duben, F2 → Datum: duben); F2 posun času o ~3 měsíce → sklizeň.
4. Sušený tabák z úrody zapálit → HUD ukáže nikotin a chuť na cigaretu (ne „Pod vlivem THC“).
5. Sušené květy konopí zapálit → HUD „Pod vlivem THC – slabé/střední“, krátké zpomalení, po pár hodinách odezní.
6. Soused nebo hlídka u plotu uvidí konopí při sázení → přestupek „Nedovolené pěstování konopí“ (zakon.json, NEOVĚŘENO) se objeví v rejstříku / dluzích.
7. Vypnout volbu → semena a látky zmizí z inventáře a z nabídek obchodu; znovu zapnout → vrátí se.
8. F5 → F9 zachová THC a stav zahrady; starý save bez klíčů `thc` / `psilo` se načte bez chyby.
9. Lysohlávky: ve hře zatím nejdou sehnat (sběr chybí, viz otevřené body); ověřit jen, že se předmět neobjeví s vypnutou volbou.
10. Zákonné řádky v `data/zakon.json` (`nedovolene_pestovani`, `prechovavani_navykove_latky`, `rizeni_pod_vlivem_navykove_latky`) mají poznámku „NEOVĚŘENO“ – přečíst a ověřit čísla proti zdroji.

## Závěrečná kontrola M4 – opravené chyby (ověřit při testu)

Doporučené pořadí testování celé M4: M4.1 → M4.2 → M4.3 → M4.4 A/B → M4.5 → M4.6 → M4.7 → M4.8, pak tento oddíl.

1. **Konopí není soud:** Obsah pro dospělé zapnout, zasadit 4. rostlinu konopí před sousedem → přestupek přijde jako
   *příkaz poštou* (deník J → Úřední záznamy), **ne** „Obvinění / předvolání k soudu“. 1.–3. rostlina bez přestupku.
2. **Soudní zákaz řízení skončí:** odsouzení s „Zákazem řízení“ → P ukáže „ZÁKAZ (…) – ještě N dní“ (ne „nutné
   přezkoušení“). F2 → Datum za konec zákazu → P ukazuje skupiny normálně, auto bez hlášky „nemáš řidičák“.
3. **Podmínka vyprší:** po rozsudku s podmínkou posunout datum za její konec → nový trestný čin už **není** „podmínka porušena“
   a deník nepíše „Podmínka do …“.
4. **Odchod od soudu:** v den jednání otevřít menu soudu, zavřít ho (Esc) a odejít → do 15:00 přijde rozsudek
   v nepřítomnosti (případ nezůstane navždy „u soudu“).
5. **Načtení pozice bez dluhů:** mít dluh, pak načíst starší save bez dluhů (F9 / pozice z doby před M4.2) → deník J
   neukazuje dluhy z předchozí hry; po načtení není „Podmínka do 0“ ani „OPP zbývá 0 h“.
6. **Větve na podpal:** odvětvit strom → hláška „Máš: N× Čerstvé větve, M× Větve (klestí)“; z těch suchých
   (a polen) jde rozdělat oheň hned.
7. **Nehody:** pád z kola na silnici / náraz do terénu před vesničanem → **žádný** přestupek; série nárazů do plotu během
   hodiny → nejvýš jedna „Dopravní nehoda se škodou“.
8. **Pálení u domova v bytě / koupeném domě:** v červenci přiložit suché větve na ohništi do 30 m od dveří domova →
   bez „Porušení obecně závazné vyhlášky“.
9. **Panel P:** po koupi povolenky k lovu / rybolovu ukazuje „platí ještě N dní“, po vypršení „PROŠLÁ“.
10. **Katastr:** inzeráty domů na úřadě nikdy neobsahují budovu statku (M3.2).

## M4.9b – M4.4 B doplnění (hluk a nedělní klid)

1. F2 → Datum: nastav neděli 10:00. V lese pokácej strom motorovou pilou (u cizího stromu) → buď popup „Sousedé slyšeli motorovou pilu a nahlásili to“ + přestupek „Porušení nedělního klidu“ (Počítač → Banka → Pokuty), nebo hláška „Je slyšet motorová pila. Zatím si toho nikdo nevšiml“ (nenahlášený čin; ověř F2 → Hráč / hajný).
2. Stejná práce ve středu 10:00 → žádná hláška o nedělním klidu.
3. Neděle 21:00 nebo 7:00 pilou → žádná hláška o nedělním klidu (zákaz je jen 8–20 h).
4. F2 → Datum: svátek 28. 9. 10:00 (Den české státnosti) pilou → stejné hlášení jako v bodě 1.
5. Stejný přestupek ze stejného hluku se do 60 herních minut neopakuje (pila v neděli opakovaně → jeden zápis).
6. Úřední deska (Počítač → Úřední deska): „Nedělní klid“ se ukazuje vždy; v lednu bez „Zákazu pálení“.
7. Katalog: F2 → Hráč → Pokuty / rejstřík – řádek „Porušení nedělního klidu (hlučná práce)“ se správným zákonem a „ověřit“ v poznámce.
8. Ulož hru, ukonči a načti (F9) – žádná chyba, hra běží; přestupky z předchozích bodů zůstanou v rejstříku.
9. Starý save (před touto změnou) se načte bez chyby (F5 / `--load`).
10. Kontrola: zalévání z vodovodu a hromada klestí se nevyskytují (otevřené body) – nic nehledej; ověř jen, že pálení a sucho z minula fungují jako dřív.
## M4.9a – M4.6 doplnění (kufr policií, udice u stráže, zkouška střelbou, posudek)
1. F2 → Hráč → „zbrojni“ (cheat). Vezmi pušku do ruky, sedni do auta, nech se zastavit policií (silniční kontrola). Při několika kontrolách (šance ~35 %) se v banneru objeví „v kufru: zbraň bez zbrojního oprávnění“ a puška zmizí z inventáře.
2. Stejně s nelegálním úlovkem (zajíc / srnec, bez lovu v kufru – F2 → Teleport / Hráč): při kontrole se objeví „v kufru: nelegální úlovek“ a v deníku J → Zákon přibude přestupek pytláctví.
3. Bez zbrojního oprávnění bez pušky v ruce: policejní kontrola nezabaví nic (kontrola kufru jen zbraň mimo ruku a nelegální úlovek).
4. Rybaření bez lístku u potoka (F2 → Teleport na potok, bez cheatu) → v okolí stráž (so/ne 5–12 h, nebo teleport do jejího okolí) → hláška „Zapisuji: … zabaveno: Udice, Kapr…“, udice a ryby zmizí z inventáře, rybaření skončí, přestupek v rejstříku.
5. Stejná kontrola s rybářským lístkem a povolenkou (F2 → Hráč, nebo kupte v chatě) → hláška „V pořádku, hezký den u vody.“ a nic se neodebere.
6. U myslivecké chaty (dveře) → Spolek: „Lékařský posudek pro zbrojní průkaz (1 500 Kč)“ zaplať; pak „Zbrojní průkaz – kurz“ (4 000 Kč) jde koupit jen po posudku.
7. Po kurzu zkus „Zbrojní průkaz – zkouška střelbou“ bez výstřelů → hláška „vystřel aspoň 5 ran“. Vystřel 5 ran na terč střelnice u chaty; aspoň 4 zásahy s 5+ body → popup „Zkouška střelbou složena“, doklad v panelu P.
8. Zkouška neprošla (4 mimo terč) → hláška „Zkouška neprošla (x z 5 ran dobrých…)“, doklad se nevydá; eTest (počítač doma) dál funguje.
9. Uložení a načtení: F5 / F9 uprostřed kurzu (zaplacený posudek a kurz) → po načtení zůstane posudek i kurz; starý save bez klíče `gamekeeper` se načte bez chyby.
10. Legální rybař (lístek + povolenka) a legální lovec: kontroly neberou nic, nic se nezapíše do rejstříku.

## M4.9c – M4.8 a zahrádkář (obsah pro dospělé)
1. Nová hra (volba vypnuta): u Ladislava Hrubého (zahrádkář, chata u lesa) v rozhovoru žádná věta o konopí; za chatou (duben / květen) žádný záhon.
2. Esc → Nastavení → zapnout „Obsah pro dospělé“ → F2 → Datum: duben → jdi za chatu: zelený záhon s několika rostlinami je vidět.
3. Stejný den: v rozhovoru s Ladislavem (T, téma zahrada / koníček) přibude jedna věta o konopí na záhonu.
4. Stojí-li poblíž soused / hráč v dohledu (~25 m) při výsevu, přijde hlášení „někdo nahlásil konopí na záhonu“; bez hráče v okolí žádné hlášení.
5. F2 → Datum: září (~110 dní od výsevu) → záhon zmizí (sklizeno), v inventáři žádné konopí a žádný předmět od Ladislava.
6. Sušák: sklidit tabák nebo konopí (F2 posun času o ~3 měsíce po výsevu) → v inventáři „Čerstvé … (sušák)“; po ~14 dnech (F2 → Datum) se změní na „Sušené …“.
7. Policejní dechová kontrola s THC / psilocybinem (zapnutá volba): u části kontrol hlášení „Test na drogy: pozitivní“ a přestupek „Řízení pod vlivem“ v rejstříku.
8. Kufr auta s konopím / tabákem (zapnutá volba) při kontrole kufru → zápis „Držení návykové látky“ (prechovavani_navykove_latky, NEOVĚŘENO) a hlášení „látky“.
9. Snědení lysohlávek (pokud je nějaké v inventáři, např. F2 → Hráč) → lehce zvlněný obraz; vypnutá volba → obraz bez změn, předměty zmizí.
10. F5 → F9 a načtení starého save bez klíče `npc_grow` a bez `psilo` / `thc` projde bez chyby; záhon Ladislava se po načtení obnoví.

## M4.8 zbytek – ubalení, lysohlávky, efekty obrazu, zabavení na záhonu (obsah pro dospělé)
1. Nová hra (volba vypnuta): v Potravinách nejsou papírky ani semena; v inventáři ani na mapě žádné lysohlávky (září–listopad, F2 → Datum: září).
2. Esc → Nastavení → „Obsah pro dospělé“ zapnout → v Potravinách koupit papírky (25 Kč) → v inventáři u sušeného tabáku / konopí tlačítko „Ubalit“ (joint / cigareta).
3. Sušák: sklidit tabák nebo konopí, po ~14 dnech (F2) v inventáři „Sušený tabák (na ubalení)“ / „Sušené květy konopí (na ubalení a pečení)“; tlačítko „Upéct konopné pečivo“ vyžaduje rohlík.
4. Snědené konopné pečivo: THC se projeví až zhruba o hodinu později (F2 → Hráč: stav v přehledu těla); řízení pod vlivem = přestupek při kontrole.
5. Les v září / říjnu (F2 → Datum): lysohlávky u některých hřibových míst; sběr dává XP „Myslivost“ (+4), někdy místo nich přijde muchomůrka – snědení zhorší nevolnost a zdraví.
6. Lysohlávky v Nastavení nezávisle: „Efekty obrazu“ vypnout → při psilocybinu i opilosti žádný shader; zapnout zpět → efekty se vrátí. Volba pro dospělé zůstává zapnutá.
7. Vypnout „Obsah pro dospělé“ → papírky, lysohlávky, konopné pečivo i záhon zahrádkáře zmizí; znovu zapnout → vrátí se (do ~10 s).
8. Zahrádkář: při výsevu konopí s hráčem v dohledu (~25 m) hlášení „Rostliny byly zabaveny“; záhon zůstane prázdný.
9. Na záhonu bez svědka (hráč daleko) zůstanou rostliny a sklizeň proběhne jako dřív.
10. F5 → F9 a načtení starého save bez klíčů `zabaveno` / `thc` / `psilo` projde bez chyby; „Efekty obrazu“ se ukládají do `nastaveni.cfg` (sekce obraz).
