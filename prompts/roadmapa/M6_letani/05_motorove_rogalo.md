# M6.5 – Motorové rogalo (trike) a další stroje

> Roadmapa „Život na vsi“ · **M6 Létání** · krok 5/5
> Předpoklady: M6.3, M6.4 (průkaz, pravidla) · Navazují: V2 (létání ve dvou – druhé sedadlo)

## 0. Než začneš – přečti
1. `prompts/roadmapa/00_SPOLECNE.md`
2. `docs/VIZE_A_ROADMAPA.md` – kap. 4.6 „Motorové rogalo (trike) a další“
3. `scripts/flight/aircraft.gd`, `flight_hud.gd` (M6.3), paramotor z M6.4 (jak je napojený – vzor)
4. `scripts/car.gd` – kola, `VehicleWheel3D`, řízení příďového kola (vzor pro pojezd po zemi)
5. `scripts/humanoid.gd` – sezení (pilot v triku), ruce na hrazdě (IK)
6. `scripts/permits.gd`, `data/zakon.json` (letectví)

## 1. Proč
Motorové rogalo (trike) – tříkolka s motorem a rogalovým křídlem nad sebou, řízení **hrazdou** (weight-shift).
Rychlejší a stabilnější než paramotor, startuje z polní dráhy, uveze spolujezdce.

## 2. Návrh
### 2.1 Stroj (parametry pro `Aircraft`)
- Křídlo – rogalo (trojúhelník, plocha ~15 m²), cestovní ~90 km/h, pádová ~55 km/h, max ~130 km/h, tah ~1 800 N
  (motor ~60–100 k), hmotnost prázdná ~200 kg, MTOW ~450 kg, nádrž 50 l, spotřeba 12–15 l/h, 2 sedadla za sebou (**orientační**).
- **Model:** podvozek tříkolka (příďové kolo řízené nohama), vozík s kapotáží, motor s tlačnou vrtulí vzadu, stožár, rogalo
  (MeshKit – trojúhelníkové plachtoviny, lanka, hrazda), přístroje v kokpitu.
- **Řízení hrazdou (weight-shift):** logika je **obrácená** oproti letadlu – hrazdu od sebe (S) = nos nahoru / zpomalit,
  k sobě (W) = rychleji / klesat; hrazdu doleva (D!) = zatáčka doprava. Nabídni v nastavení přepínač „intuitivní řízení“
  (arkádová mapa W = nahoru) – výchozí **realistické** s nápovědou na HUD. Plyn: **Shift / Ctrl** (přidat / ubrat, páčka drží polohu).
- **Pojezd po zemi:** příďové kolo (A/D na zemi), brzda (Mezerník), rozjezd na trávě delší.
- **Start:** polní dráha – najdi vhodný dlouhý rovný pás louky / polní cesty (≥ 250 m) blízko obce (terén: sklon < 3 %)
  a udělej z něj „letiště“ (ranveje posekaná tráva, větrný rukáv – ukazuje směr a sílu větru, hangár pro trike). Pokud není
  jasné kde → zeptej se uživatele (souřadnice z mapy M).
- **Přistání:** proti větru, rychlost ~65 km/h, vyrovnat, dosednout na hlavní kola.
- **Spolujezdec:** vesničan s přátelstvím ≥ 60 (M0.6) – „vyhlídkový let“ (respekt, přátelství, humor v bublinách: „Tady bydlím!“);
  v V2 druhý hráč.

### 2.2 Další stroje (volitelné – jen když zbude kontext, jinak otevřené body)
- **Ultralehké letadlo (UL)** – dvousedadlové, klasické řízení (knipl), z letiště; parametry přes `Aircraft`.
- **Vírník** – rotor volně se otáčející (autorotace), krátký start; jednoduchá varianta modelu.

### 2.3 Pravidla (`data/zakon.json` – „ověřit“: ultralehká letadla, LAA ČR)
- Průkaz **pilota ULL** (`pilot_ul` – výcvik na letišti: teorie eTest + 10 letů s instruktorem na druhém sedadle,
  orientačně 60–90 tisíc Kč), registrace stroje, pojištění. Létat jen za dne a VFR (ne v mracích, dohlednost > 5 km –
  napoj na `Weather.fog`, `cloud`).
- Přistání mimo letiště povoleno jen v nouzi (jinak přestupek – svědci).
- Koupě: bazar – ojetý trike ~350 000 Kč (orientačně).

## 3. Hotovo, když
- Trike jede po zemi, startuje z polní dráhy, letí se řízením hrazdou (realisticky nebo intuitivně), přistává; uveze spolujezdce;
  letiště má větrný rukáv a hangár; pravidla a průkaz fungují; stav se ukládá.

## 4. Návrh checklistu ručních testů
1. F2 → Teleport letiště: dráha, větrný rukáv (ukazuje vítr), hangár s trikem.
2. Nasedni, pojezd (A/D příďové kolo), rozjezd proti větru, Shift plyn → vzlet při ~60 km/h.
3. Hrazda: S = nos nahoru, W = rychleji; zatáčky (obrácená logika) → nápověda na HUD.
4. Přepni „intuitivní řízení“ v nastavení → W nahoru.
5. Pomalu → pád (propad), vybrat.
6. Přistání proti větru; tvrdé → poškození.
7. Vyhlídkový let s kamarádem (přátelství 60).
8. Let v mlze → přestupek / varování.
9. F5/F9 → trike v hangáru / na místě, palivo.

## 5. Závěr
README (Systémy → Motorové rogalo, Ovládání), `data/zakon.json`, VIZE odškrtnout, roadmapa README, PROJECT_LOG, deník AI,
commit „M6.5 Motorové rogalo: …“, checklist a čekat.
