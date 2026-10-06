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
