# Ovládání

Základní tabulka (pěšky / v autě) je v [`README.md`](../README.md#ovládání). Tady jsou doplňková ovládání pro ostatní dopravní prostředky.

## Kůň, dron, letadlo, paramotor, motorové rogalo

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
