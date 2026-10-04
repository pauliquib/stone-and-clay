# V2.05 – Létání, skateboard a dron přes síť + zátěž s novými systémy

> Verze 2 · **Multiplayer** · krok 5 (před `prompts/10_server_zatez_vydani.md`)
> Předpoklady: V2.01–V2.04, `prompts/05` (auta v MP – autorita řidiče) · Navazují: `prompts/10`

## 0. Než začneš – přečti
1. `prompts/roadmapa/00_SPOLECNE.md`, `V2_multiplayer/README.md`, `GAME_DESIGN.md` kap. 6.3–6.4
2. Auta v MP (úkol 05 – jak se replikuje vozidlo s autoritou řidiče, interpolace, extrapolace)
3. `scripts/flight/aircraft.gd`, dron (M6.1), paramotor (M6.4), trike (M6.5), skateboard (větev v `player.gd`, M5.7), U-rampa (M5.8)
4. `scripts/surroundings.gd` (M6.2 – hranice letu)

## 1. Cíl
Rychlé a vysoko létající objekty a skateboard fungují v síti plynule; oblast zájmu počítá s tím, že z výšky je vidět daleko;
zátěžový test zahrne nové systémy.

## 2. Co udělat
1. **Letadla (paramotor, trike, UL):** autorita pilota (jako řidič auta), replikace transformace + rychlosti 20 Hz,
   extrapolace u ostatních (rychlé stroje), stav křídla (zavření, houpání pilota) jako malý stav; hluk motoru 3D u všech.
2. **Dron:** autorita operátora; dron je samostatný objekt (hráč stojí jinde) – oblast zájmu musí brát v úvahu **pozici dronu**
   (klient potřebuje svět kolem dronu, ne jen kolem těla) → rozšiř oblast zájmu o „kamery“ hráče (tělo + dron / letadlo).
3. **Oblast zájmu z výšky:** hráč ve výšce > 150 m – větší poloměr pro statický svět (stromy, stavby – levné), ale NPC / zvěř
   jen do 400 m (výkon) – vzdálené NPC neviditelné z výšky nevadí; ověř, že to nepůsobí rušivě (případně LOD bez animace).
4. **Skateboard:** stav desky (triky, grind) replikovaný (animace), autorita klienta (je to pohyb hráče), skóre session per hráč.
5. **Pravidla** (120 m, nad lidmi, soukromí) se vyhodnocují na serveru i vůči **ostatním hráčům** (dron nad jiným hráčem = nad lidmi).
6. **Zátěž:** doplň do zátěžového testu z úkolu 10 scénář „8 hráčů: 2 v letadlech, 1 dron, 2 na skateu, 3 kácí / farmaří“ –
   připrav parametry a botové klienty (úkol 10 má headless klienty – rozšiř jejich chování o nové činnosti), **nespouštěj**.

## 3. Hotovo, když
- Letadla a dron se u ostatních hráčů pohybují plynule; oblast zájmu funguje i pro dron a výšku; skateboard a triky
  jsou vidět u všech; zátěžový scénář je připravený pro uživatele.

## 4. Návrh checklistu (2 klienti)
1. A letí trikem, B stojí na zemi → plynulý let, zvuk motoru.
2. A pilotuje dron 1 km od sebe → A vidí svět kolem dronu (NPC, stromy), B vidí dron.
3. A s dronem nad B → varování „nad lidmi“.
4. A na rampě dělá triky → B vidí animace.
5. A ve 800 m výšce → okolí bez děr, výkon ok.
6. Spuštění zátěžového scénáře (postup v README) → výstup měření.

## 5. Závěr
GDD kap. 6, README, PROJECT_LOG, deník AI, commit „V2.05 Létání a skateboard v MP: …“, checklist a čekat.
