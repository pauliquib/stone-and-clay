# Checklisty ručních testů – noční běh M0

## M0.1 Assety a licence
1. `python3 tools/assets_check.py` → souhrn (7 záznamů), žádná CHYBA; vznikne `data/credits.json` (zatím `[]`, Poly Haven a ČÚZK jsou v pevných titulcích).
2. Vlož do `assets/sounds/ruzne/` libovolný `.ogg` bez záznamu → nástroj ohlásí „neevidovaný soubor“ a skončí chybou.
3. Přidej do `licenses.json` testovací záznam s licencí `CC-BY-NC-4.0` → „nepovolená licence“.
4. Přidej testovací záznam `CC-BY-4.0` (bez `v_titulcich`) → po spuštění je v `data/credits.json`.
5. `./run.sh` → hra se spustí jako dřív; F1 → dole jsou pevné titulky + řádek z `credits.json` (z bodu 4).
6. Smaž `data/credits.json` → F1 funguje, ukazuje jen pevné titulky.
7. Zkontroluj, že `assets/` má složky se `.gitkeep` a že `git status` neukazuje nic nečekaného.

## M0.2 Katalog předmětů a inventář
1. `./run.sh` → Tab: nahoře „Neseš x,x / 25 kg“, položky seskupené pod nadpisy (Jídlo a pití, Tabák, Vybavení…), u položek hmotnost.
2. Kup v Potravinách pivo a rohlík → přibudou, hmotnost vzroste; vypij / sněz z Tab → funguje jako dřív.
3. F2 → Hráč → peníze; kup 10× slivovici → nad 25 kg hláška „Neseš moc – zpomalíš.“, chůze pomalejší, sprint nejde; v Tab oranžová hlavička.
4. Vypij / prodej část, klesni pod 25 kg → rychlost a sprint se vrátí.
5. Seber hřib, jablko a dukát → skóre a hlášky „+10 Hřib (…)“ jako dřív; hřib / jablko jdou v Tab sníst.
6. Cigarety: koupit, Tab → Zapálit si (ubývá po kusech).
7. Spacák: koupit, Tab → Rozložit a vyspat se, vyspat se.
8. F9 načti starou pozici (před touto změnou) → inventář a otevřené lahve sedí, nic nespadne; F5 / F9 s novou pozicí taky.
9. Kompas / šipka k nejbližšímu předmětu ukazuje správný název (Hřib, Dukát…).

## M0.3 Dovednosti a XP
1. `./run.sh`, K → panel „Dovednosti“ se 16 řádky, všude úroveň 1, 0 %; J → stejný oddíl je i v deníku pod úkoly; K / J přepíná mezi nimi.
2. Jeď střízlivě autem ~1 km → dole nad výzvami „+N XP Řízení (úr. 1, x %)“ (sčítá se, nepřekrývá zprávy); v K roste pruh.
3. Popij pár piv (promile nad 0,2) a jeď → XP Řízení nepřibývá. Po nehodě (náraz do auta / zdi) ~1 min také ne.
4. Nasedni na koně (F), jeď krokem, klusem (Shift) a cvalem → hlášky „+N XP Jezdectví“, rychleji za klus / cval.
5. Sprint pěšky (Shift) ~10 s → po chvíli „+1 XP Kondice a fotbal“.
6. Oprav auto v garáži doma (po nehodě, 2 500 Kč) → „+25 XP Kutilství“.
7. Řekni sousedovi (T) „dobrý den“ / „děkuju“ → „+2 XP Výřečnost“ (další až po ~12 s); urážka XP nedá; splněný úkol +30 XP Výřečnost.
8. F2 → Hráč → „+1 000 XP Řízení“ → popup „Nová úroveň: Řízení N!“ + zvuk, v K úroveň 9.
9. F5, restart, F9 → XP i úrovně zůstanou; F9 na starou pozici (před M0.3) → všechny dovednosti na 1, nic nespadne.
10. F1 nápověda ukazuje „K – dovednosti“.

## M0.4 Kontextové akce a nástroje
1. `./run.sh`, klikni do okna (zachytí myš), prázdné ruce, miř na trávu u domu → dole „[LMB] Natrhat trávu (Zahradničení 1)“.
2. LMB → pod středem obrazovky pruh „Natrhat trávu“ běží ~2 s, postava klečí a šmátrá rukama po zemi, výdrž (spodní pruh) klesne o ~5 %; po dokončení „Máš: 1× Tráva (svazek)“, v Tab je Tráva (Materiál) a „+2 XP Zahradničení“.
3. Znovu LMB a během akce stiskni W (nebo Mezerník, Tab, Esc) → akce se přeruší („Přerušeno.“), nic nepřibyde, žádné XP.
4. Miř na silnici / asfalt / zeď / oblohu → žádná výzva k akci; na cestu u domu → šedé „Natrhat trávu – Tady není tráva.“ (kdy je nejblíž silnice do 3,5 m).
5. Vyčerpej výdrž (sprint do konce) a hned miř na trávu → šedé „…Nemáš dost výdrže.“, LMB jen ukáže hlášku; po odpočinku akce jde.
6. F2 → Hráč → „Nástroje do inventáře“ (sekera, lopata, motyka, konev, udice) → Q: prázdné ruce → sekera (v ruce je vidět model, vpravo dole „V ruce: Sekera (opotřebení 0/200)“) → lopata → … → prázdné ruce; klávesy 1–5 přepínají přímo, stisk už drženého nástroje ho schová. Natrhat trávu jde s libovolným nástrojem i bez něj (a opotřebení se nemění).
7. Nasedni do auta / na koně (F) → LMB nic nedělá, nástroj v ruce zmizí a vpravo dole není „V ruce“; po vystoupení je zase v ruce.
8. Nástroj v ruce a Tab → napij se / sněz něco: během pití je v ruce lahev, pak se nástroj vrátí.
9. F5, restart, F9 → nástroj zůstane v ruce; F9 na starou pozici (před M0.4) → prázdné ruce, nic nespadne.
10. F1 nápověda ukazuje „Q – další nástroj v ruce, 1–5 …, levé tlačítko myši“; Esc → Ovládání totéž.

## M0.5 Zákon jako data
1. `./run.sh`, vypij 2 piva, jeď autem kolem policie (F2 → Teleport) → zadržení, pokuta 10 000 Kč a zákaz 24 h jako dřív; J → „Úřední záznamy“: záznam s § a „7 b.“, body 7 / 12.
2. Rádio doma nahlas v noci (22–6 h) → policie, pokuta 2 000 Kč, v J záznam „Rušení nočního klidu“ (0 bodů).
3. Urážka policisty (T) → pokuta 1 000 Kč na místě, záznam; vyhrožování policistovi → 2 000 Kč.
4. Opakuj alkohol za volantem (po zákazu F2 → čas / vystřízlivět, případně řídit přes zákaz) do 12 bodů → hláška o zákazu řízení na rok, body se vynulují.
5. Opilý nad 1 ‰ → záchytka (+1 500 Kč), v J záznamy „Ohrožení pod vlivem…“ (trestný čin) i „Noc na záchytce“.
6. Nenahlaš srážku se zvěří do hodiny → pokuta 2 000 Kč, záznam v J.
7. Mít méně peněz než pokuta (F2 → peníze) → zaplatí se, co jde, v J „nezaplacené pokuty“.
8. F5 / F9 → body a záznamy zůstanou; F9 na starou pozici (před M0.5) → 0 bodů, nic nespadne.
9. Uprav v `data/zakon.json` pokutu za rušení klidu → po restartu se ve hře projeví.
10. F1 nápověda končí větou „Zákony jsou ve hře zjednodušené – nejde o právní radu.“

## M0.6 Respekt v komunitách a skrytá karma
1. `./run.sh`, J → oddíl „Vztahy“ pod pověstí: 6 komunit „nevšímají si tě“, „Svědomí: nic zvláštního“, „Přátelé: zatím nikoho…“.
2. Splň úkol v hospodě (např. cigarety / pivo) → hláška „Štamgasti: +6 – pomohl…“ a pověst +8; v J štamgasti „váží si tě“. Úkol od dědy → Sousedé, od chaty (myslivec) → Zemědělci.
3. Slušně promluv (T „dobrý den, jak se máte“) s postavou z hasičů / fotbalu (Emil Prskavec, Radek Šťovíček) → „Hasiči: +1 – slušný rozhovor…“; opakuj → po +2 už nic (limit za den), další den zase.
4. Uraz vesničana (T) → „…: −3 – urazil…“, pověst dolů; po několika urážkách v J svědomí „klidné“ → „něco tě tíží“ (karma není vidět číselně).
5. Vypij ≥ 2 piva, jeď kolem policie bez svědků → pověst jako dřív, karma horší (J „Svědomí“ po víc přestupcích).
6. Nahlaš srážku se zvěří včas (F2 → nějaká srážka, pak hospodský) → pověst +2; karma se lehce zlepší.
7. Mluv s jednou postavou několik herních dní každý den slušně → po ~30 dnech je v J „Přátelé: … (přítel)“; F2 → čas dopředu urychlí. Přítel tě pozdraví „kamaráde“.
8. Postava komunity s respektem ≥ 40 (nasbírej úkoly) pozdraví vřeleji; u komunity s respektem < −25 chladněji.
9. F5, restart, F9 → respekt, karma i přátelství zůstanou; F9 na starou pozici (před M0.6) → vše 0, nic nespadne.
10. F2 → nástroje, natrhat trávu s karmou −100 (mnoho přestupků) → chování stejné (nulová šance selhání se nemění).
