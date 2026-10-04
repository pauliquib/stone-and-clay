# M6.4 – Motorový paraglide (paramotor)

> Roadmapa „Život na vsi“ · **M6 Létání** · krok 4/5
> Předpoklady: M6.3 (letový model `Aircraft`), M4.1 (`Permits`), M3.4 (eTesty) · Navazují: M6.5

## 0. Než začneš – přečti
1. `prompts/roadmapa/00_SPOLECNE.md`
2. `docs/VIZE_A_ROADMAPA.md` – kap. 4.6 „Motorový paraglide“
3. `scripts/flight/aircraft.gd`, `flight_hud.gd` (M6.3) a záznam M6.3 v `PROJECT_LOG.md`
4. `scripts/humanoid.gd` – běh, sezení (pilot v sedačce), `_arm_ik` (ruce na brzdách)
5. `scripts/player.gd` – vstup/výstup z vozidla (`enter_car`/`exit_car` a nová `aircraft` větev z M6.3)
6. `scripts/permits.gd`, `data/zakon.json` (letectví)

## 1. Proč
Motorový paraglide (paramotor) je nejdostupnější způsob, jak na vsi létat: motor na zádech, padákové křídlo,
start z louky rozběhem. Specifický start a řízení brzdami – jiné než rogalo.

## 2. Návrh
### 2.1 Stroj (parametry pro `Aircraft`)
- Křídlo: plocha ~24 m², trimová rychlost ~38 km/h, min. ~25 km/h, max. s trimry / plynem ~50 km/h, klouzavost ~7,
  hmotnost pilot + motor ~110 kg, tah ~60–70 kgf (~650 N), nádrž 11 l, spotřeba 3–4 l/h (laditelné, **orientační**).
- **Model:** motor s klecí a vrtulí na zádech pilota (MeshKit), křídlo – **tkaninový oblouk** (buňky – loft/segmenty, barevné),
  šňůry (tenké čáry z křídla k závěsům – `ImmediateMesh` nebo tenké válce, ~20 kusů), sedačka.
- Křídlo je „kyvadlo“: pilot visí ~7 m pod křídlem; vizuálně křídlo nad pilotem, fyzika = `Aircraft` + kyvadlový náklon
  (při zatáčce se pilot vyhoupne ven – vizuál, a při prudkém brzdění houpání vpřed/vzad).

### 2.2 Start (hlavní rozdíl)
1. Na louce (tráva, sklon < 10°, bez stromů 50 m před sebou) Tab → „Připravit paramotor“ → křídlo se rozloží za hráčem (na zemi).
2. **Nahození křídla:** hráč stojí čelem **proti větru** (HUD šipka), W = rozběh → křídlo se zvedá nad hlavu (fáze 1–2 s),
   když je vítr z boku nebo je rozběh slabý → křídlo spadne na stranu (neúspěch, znovu). Podle větru: silný vítr (> 8 m/s)
   → nebezpečné vytažení (hráč je vlečen, pád).
3. **Plyn** (Shift / dlouhé W) → tah, rozběh pokračuje, při rychlosti > min. hráč odlepí nohy → let (pilot se usadí do sedačky).
4. Chybné pořadí (plyn dřív, než je křídlo nad hlavou) → pád na záda / vrtule do trávy (poškození).

### 2.3 Řízení
- **A/D** = levá / pravá brzda (zatáčení; obě = zpomalení), **S** = obě brzdy (zpomalení, při dlouhém a hlubokém tahu → **pád
  křídla / propad**), **W / Shift** = plyn (stoupání), **Mezerník** = trimry povolit (rychlost), **Ctrl** = „uši“ (rychlejší klesání).
- **Zavírání křídla** v turbulenci (M6.3 turbulence): šance podle síly turbulence → křídlo se částečně zavře (propad na
  jednu stranu, 1–3 s), hráč srovná opačnou brzdou; na malé výšce nebezpečné.
- Termika (M6.3) – se staženým plynem lze kroužit a stoupat (XP bonus).
- **Přistání:** stáhnout plyn, proti větru, těsně nad zemí „vyrovnat“ – obě brzdy naplno ve výšce ~1 m → měkké dosednutí na nohy
  (hráč doběhne). Pozdě / brzy → tvrdé (pád, drobné zranění). Po přistání Tab → „Složit křídlo“ (zabalit – 30 s).
- **Náklad:** paramotor se nese na zádech (náklad 25 kg – M2.10) nebo vozí v kufru.

### 2.4 Pravidla (zjednodušeně – do `data/zakon.json` sekce `letectvi`, „ověřit“)
- Paramotor = sportovní létající zařízení → **pilotní průkaz** (`pilot_pg_motor` – výcvik v „létací škole“: teorie eTest na PC
  + 5 výcvikových letů s instruktorem (instruktor na zemi rádiem – hlášky), cena orientačně 30–40 tisíc Kč), **registrace
  stroje** (poznávací značka na křídle – smyšlená), **pojištění odpovědnosti** (roční platba – volitelně).
- Nelétat nad obcí níž než ~150 m (hluk a bezpečnost), ne nad shromážděním lidí, ne v noci, ne v mracích.
  Porušení → přestupek (svědci slyší motor do ~800 m).
- Koupě: bazar / e-shop (M3.4) – nový 180 000 Kč, bazarový 90 000 Kč (orientačně), v inventáři jako náklad; uložený u domu.

## 3. Hotovo, když
- Paramotor jde rozložit, nahodit proti větru, odstartovat, řídit brzdami, stoupat v termice, zvládat zavírání křídla,
  přistát na nohy a složit; pravidla a průkaz fungují; stav se ukládá.

## 4. Návrh checklistu ručních testů
1. Kup paramotor (F2 peníze), odvez na louku za obcí; Tab → Připravit.
2. Čelem po větru → rozběh → křídlo spadne; proti větru → nahodí se nad hlavu.
3. Plyn → odlepení → let; A/D zatáčení, S zpomalení → hluboký tah → propad.
4. Turbulence (vítr 6 m/s, poledne nad kopcem) → zavření křídla, srovnání.
5. Termika v létě → kroužení bez plynu, variometr.
6. Přistání: vyrovnání v 1 m → měkce na nohy; pozdě → pád.
7. Nízko nad obcí → přestupek (hluk); bez průkazu → přestupek při kontrole.
8. F5/F9 → paramotor na místě.

## 5. Závěr
README (Systémy → Paramotor, Ovládání), `data/zakon.json`, VIZE odškrtnout, roadmapa README, PROJECT_LOG, deník AI,
commit „M6.4 Motorový paraglide: …“, checklist a čekat.
