# Checklisty ručních testů – M5 Obec a volný čas

## M5.9 – Rocková rádia (částečně)

Cheat: F2 → Hráč / Teleport. Ověř jen to, co je v kroku hotové.

1. Doma: zapni rádio (E) → v seznamu jsou ČRo stanice z `data/radia.json` beze změny (nové rockové stanice zatím nejsou).
2. Přepni na ČRo Radiožurnál → hraje (potřebuje internet a ffmpeg).
3. Odpoj internet → přepni stanici → hláška „Stanice nehraje“ (nebo po ~12 s ukončení), hra běží dál bez pádu.
4. Bez ffmpeg (pokud jde otestovat) → hláška „Internetové rádio potřebuje program ffmpeg“.
5. Hlasitost 8 v noci u stanice s vyšším `noise` → sousedé reagují (zvýšený hluk).
6. README → Právní zásady → Rádio: poznámka k nepřidaným stanicím je srozumitelná.
# Ruční testy – M5 (Obec a volný čas)

Každý krok má vlastní oddíl. Testuje uživatel po dokončení vlny; agent hru nespouští.

## M5.7 Skateboard

1. F2 → Hráč → přidat „skateboard“ do inventáře (případně e-shop / stavebniny až po napojení).
2. Stiskni F na volném místě → hláška „Stoupl jsi na skateboard…“. Hráč stojí na desce, deska je vidět pod nohama.
3. W = odraz (rychlost roste po krocích), S = brzda patou, A/D = zatáčení; zastaví se bez vstupu.
4. Jedeš z kopce u silnice → rychlost roste; nad ~12 m/s deska kmitá, nad ~15 m/s pád.
5. Najeď do zdi nebo obrubníku rychleji než ~3 m/s → pád, hráč leží.
6. Na trávě nebo mokru (déšť) při rychlosti přes ~2,5 m/s → přepadneš dopředu.
7. Mezerník na rovině (rychlost pod 2 m/s nebo i za jízdy) → ollie; dopad rovně přidá +10 bodů (zatím jen v logu / signálu, HUD ještě ne).
8. F při rychlosti pod 2 m/s → seskok; při vyšší rychlosti hláška „Nejdřív zpomal“.
9. Ulož (F5), ukonči hru, načti (F9) → rekord zůstane, skateboard zůstane v inventáři, hráč jde pěšky.
10. Starý save (před M5.7) se musí načíst bez chyby a rekord bude 0.

## M5.9 – Autorádio a vnitřní světlo v autě (body 5–6)

Cheat: F2 → Teleport (k autu) / Datum (noc, např. 23:00) / Hráč. Auto s kabinou (osobní auto, ne kolo / motorka / traktor).

1. Nasedni do auta (F) → za volantem zmáčkni **1** → hraje první předvolba (Rádio Kovadlina); hlášení s názvem stanice.
2. Předvolba **2** (Rádio Pohoda) → hraje klidná hudba; **0** → rádio vypnuto (hláška „vypnuto“).
3. Za volantem **Shift + kolečko** nahoru/dolů → hlasitost se mění (hláška „hlasitost x/10“); bez Shift kolečko kamera nepřibližuje.
4. Mimo auto (za hry) klávesy 1–5 pořád přepínají rychlé sloty opasku, 0 nic nedělá.
5. Hlasitě (hlasitost 10, Rádio Kovadlina) v noci jezdi obcí → sousedé si stěžují dřív než u tiché hudby.
6. Nastup v noci (Datum 23:00) → v kabině se rozsvítí teplé světlo; po ~10 s stojícího auta zhasne.
7. Stiskni **F4** → světlo svítí i po 10 s; F4 znovu → zhasne. Při rozjezdu se světlo vypne.
8. Ve dne (Datum 12:00) při nástupu světlo nesvítí; F4 ho přesto zapne ručně.
9. Ulož hru (F5), zapni rádio v autě na stanici, načti (F9) → rádio ve stejné stanici a hlasitosti.

## M5.12 – Pouliční osvětlení a světelný smog
1. F2 → Čas 21:00, jasno, náves: lampy podél silnic svítí, světlo na silnici u nejbližších lamp, málo hvězd.
2. Teleport do lesa ~1 km od obce: hvězd výrazně víc; nad obcí při horizontu teplý opar.
3. Svítání (F2 → Čas ~6:00): lampy postupně zhasnou, každá s jiným zpožděním.
4. Čas 1:00: úsporný režim – každá druhá lampa zhasnutá (lichá pořadí).
5. Grafika Nízká: jen svítící hlavice bez pool světel; FPS v obci v pořádku. Vysoká: světla u nejbližších lamp.
6. Zataženo v noci: nad obcí nasvícené mraky (spodek oblačnosti teplejší).
7. Ráno a ve dne: lampy zhasnuté, obloha bez smogu.

## M5.1 Stavebniny (místo a nabídka)
1. F2 → Teleport → Stavebniny: budova (plochá hala) jihozápadně od návsi, cedule „Stavebniny Cihla a Hřebík“, parkoviště u silnice.
2. Otevírací doba: po–pá 7–17; sobota 7–12; neděle zavřeno (ověř F2 → Datum na sobotu a neděli).
3. U prodavače Miroslava: nabídka „Nářadí“ – stará sekera 390, sekera 1 290, motorová pila 6 900 Kč (v Potravinách už nejsou).
4. Kup sekeru a zkus ji použít na kácení (Q do ruky, LMB na strom).
5. Vesničan / hospoda: prodavač Miroslav mluví k tématu „drby / počasí / zahrada“ (rozhovor T).
6. Mapa M: značka stavebnin na správném místě (ověř souřadnice oproti červené oblasti).
## M5.2 – Koupaliště na bývalé hasičské nádrži + plavání
1. Teleport na potok č. 275 (jihozápadně od Dukelčic, ~620 m od návsi, u silnice na začátku toku): u potoka stojí betonová nádrž 25 × 12 m se schůdky na krátké straně.
2. Vyleze po schůdcích do nádrže (hladina ~1,5 m): od hloubky 1,2 m se plave, bez pádu ke dnu.
3. Mezerník = nahoru, Ctrl = dolů; pohyb pomalý (1,2 m/s), Shift rychlejší a výdrž rychle ubývá.
4. Ctrl a potopit se pod hladinou: dech ~15 s, pak ubývá zdraví (utopení); po vynoření dech přijde zpět.
5. Skok ve vodě nefunguje (Mezerník jen vynáší); vylezení po schůdcích funguje.
6. F2 → Datum 15. 7., jasno: plavání stejně; pocitová teplota ve vodě ~22 °C, prochladnutí žádné nebo pomalé.
7. F2 → Datum 15. 5.: voda ~15 °C → po pár minutách ve vodě roste prochladnutí (HUD „prochlazen“).
8. Plavání v rybníce v lese (Teleport k rybníku) – stejné ovládání jako v nádrži.
9. Chůze mimo nádrž po zemi se nezměnila; u potoka (mělčina < 1,2 m) se chodí brodem jako dřív.
10. Starý save se načte beze změny (žádný nový klíč v `save_game.gd`).

## M5.1 pokračování (pila a dvůr stavebnin)
1. F2 → Teleport → Pila: budova (stodola) severně od haly stavebnin, cedule „Pila Na Bidýlku“, parkování mezi halou a pilou.
2. Dvůr: u haly na jihu hromady písku, štěrku, cihel na paletách, prken a dříví; u pily kulatina, řezivo, piliny.
3. Pila → obsluha Pilař Ondřej: nabídka „Dřevo a řezivo“ (prkno 180, hranol 260, dříví 90 Kč); motorovou pilu koupit jen ve stavebninách.
4. Stavebniny → „Materiál (dvůr)“: písek 10 Kč.
5. Otevírací doba pily: po–pá 7–17, so 7–12, v neděli zavřeno (F2 → Datum na sobotu a neděli).
6. Mapa M: značka pily na stodole severně od haly; hromady stojí mimo budovy (ne uvnitř zdí).
## M5.5 Kalendář událostí a zábava s kapelou
1. F2 → Datum na sobotu 1. nebo 3. v měsíci (např. 3. 10. 2026) v 19:30; teleport k hospodě: mezi 20 h a 3 h se postaví pódium, kapela a parket.
2. Nástěnka u obecního úřadu: nápis „NÁSTĚNKA OBCE“ s nejbližšími akcemi (zábava na sobotu); ověř, že text je čitelný z blízka.
3. Web obce (počítač doma → kalendář): den zábavy je v seznamu s názvem kapely.
4. Kapela (4 postavy) stojí na pódiu, kytarista a basista drží nástroje; tři barevná světla blikají.
5. Hudba hraje asi 40 s, pak 20 s pauza (ticho); pak zase hraje.
6. Dvě třetiny návštěvníků se kývají na parketu, zbytek stojí u stolů.
7. Mimo den zábavy (např. 4. 10. 2026) nic z toho není vidět, hospoda se chová jako dřív.
8. V den hodů (3. sobota → neděle hodů v říjnu) zábava není, jen hody.
9. F2 → Datum: po půlnoci (≈ 2 h) zábava ještě běží, po 3 h zmizí pódium.
10. Starý save se načte beze změny; zábava není uložena (plyne z kalendáře).
## M5.8 – U-rampa na mýtince severovýchodně od obce
1. Teleport na U-rampu (mýtinka v lese na SV okraji obce, ~180 m od návsi, mezi domy a horní cestou): stojí hotová dřevěná U-rampa na betonových patkách, žebřík na boku u plošiny.
2. Rampa stojí na patkách, nevisí ve vzduchu a neprolíná se s terénem (na spodní straně svahu jsou patky vyšší).
3. Výstup žebříkem na plošinu, zábradlí na vnější (zadní) hraně; skateboard F → drop-in ze plošiny do přechodu, jízda tam a zpět.
4. Deska se na přechodu natáčí podle povrchu; přechody (i strmé u copingu) jsou jízdní, nespadneš na rovném místě mezi nimi.
5. Coping (kovová trubka) a rovný střed jsou vidět; stěny z překližky, trámky a sloupky odpovídají konstrukci.
6. Chůze pěšky k rampě: plošina a přechody jsou pro chodce neprůchodné nad cca 0,7 m (chůze se nezměnila).
7. Po seskoku (F) na rovině se deska vrátí do vodorovné polohy; po sjetí z rampy normální jízda po terénu a cestě beze změny.
8. Stromy kolem rampy (cca 6 m od středu) nejsou v půdorysu; kolize s kmeny nepřekáží.
9. Save a načtení: starý save se načte beze změny (rampa je statický objekt, nic se neukládá).
10. Teleport k cestě / budově v okolí: nic neblokuje, pohyb a zvuky jinde beze změny.
## M5.3 – Hasiči: zbrojnice, spolek SDH, výjezdy k požárům
1. F2 → Teleport k úřadu: před úřadem (cca 40–90 m od dveří, mimo silnici) stojí garáž s červenými vrat, věžičkou a sirénou na střeše, cedule „SDH Pod Kopcem“.
2. U vchodu zbrojnice (do 4 m) se nabídne „zbrojnice, členství a schůze“; bez respektu „hasici“ ≥ 0 nebo s alkoholem (> 0,2 ‰) velitel členství odmítne.
3. Žádost o členství (200 Kč) → zpráva „Vítej v SDH“; druhé zaplacení nejde, dokud příspěvek platí; „Vystoupit“ členství zruší.
4. F2 → Datum: nastav první pátek v měsíci 19:00 a jdi do zbrojnice (do 40 m) → respekt hasičů +1, další schůze stejný měsíc už ne.
5. F2 → cheat „požár trávy“ (nebo oheň v suchu a větru) → siréna slyšitelná, popup členům „Výjezd! … dojdi do zbrojnice“.
6. Po cca 6 herních minutách hlášky „Hasiči jsou na místě, hasí“; nejbližší požár se postupně zmenšuje (každých cca 1,5 min) a zhasne.
7. Člen v zásahovém obleku (I) stojí u ohně do 25 m a dohoření / uhašení → respekt hasičů +5, pověst +3, XP Hasičina 50–150; bez obleku v ohni ubývá zdraví a přijde hláška.
8. Požár způsobený hráčem (přestupek „způsobení požáru“) → respekt hasičů −5 navíc.
9. Save a načtení: členství a zaplacený příspěvek zůstanou; starý save se načte, hráč je nečlen.
10. Mimo výjezd (bez požáru) nic neruší: siréna jen při `fire_report`, zbrojnice nic nevypisuje do chatu.
