# M4.4 – Další přestupky: kácení s povolením, oheň, zvířata, krádeže, klid

> Roadmapa „Život na vsi“ · **M4 Zákon a společnost** · krok 4/6
> Předpoklady: M0.5, M4.2, M2.1, M2.2, M2.4, M2.6 · Navazují: M6.1 (drony – přidají vlastní řádky)

## 0. Než začneš – přečti
1. `prompts/roadmapa/00_SPOLECNE.md`
2. `data/zakon.json` a `scripts/law.gd` – co už je v katalogu (grep klíčů), `World.commit_offense`
3. Záznamy M2.1, M2.2, M2.4, M2.6 v `PROJECT_LOG.md` – jaké háčky pro zákon zůstaly otevřené (grep `háček|hook|M4.4`)
4. `scripts/reputation.gd` – `_witnesses` (svědci), `scripts/villager.gd` (jak vesničan vidí hráče)
5. `scripts/permits.gd` (M4.1), úřad (M4.2 – rámec žádosti o povolení ke kácení)

## 1. Proč
Dosavadní kroky nechaly v zákonech mezery a háčky. Tady je sjednotíme, aby všechny činnosti měly
konzistentní právní důsledky a **systém svědků** fungoval všude stejně.

## 2. Co udělat
### 2.1 Jednotný systém svědků `World.witness_check(id, pos, kind, radius_see, radius_hear) -> Array`
- Vrátí seznam NPC (vesničané, obsluha, myslivec, policie, stráže M4.6), kteří čin **vidí** (zorný kužel, vzdálenost,
  tma – `Clock.daylight`, mlha, překážky – raycast na vrstvu 1) nebo **slyší** (výstřel, motorová pila, rádio…).
- Každý svědek rozhodne podle povahy (`Persona.trait`) a přátelství s hráčem (M0.6), zda **nahlásí** (přísný skoro vždy,
  kamarád s přátelstvím ≥ 60 skoro nikdy, drbna to aspoň roznese – pověst bez úředního záznamu).
- Nahlášení → `commit_offense` se zpožděním (policie přijede / příkaz poštou). Pokud nikdo nevidí → „nenahlášený čin“
  (seznam `Law.hidden`) – hajný / stráž (M4.6) nebo náhoda (karma) ho může odhalit později.
- **Převeď** všechna dřívější místa (kácení, oheň, rybolov, lov, střelba) na tuto funkci.

### 2.2 Povolení ke kácení
- Úřad → „Žádost o povolení ke kácení“: hráč musí být u stromu a zvolit ho (akce „označit strom“ – tužka / barva)
  → žádost, poplatek, vyřízení za 7–30 herních dní (poštou), strom dostane značku; povolení platí do konce
  období vegetačního klidu (X–III) – kácení v hnízdní době (IV–VII) i s povolením jen se souhlasem (zjednodušeně: nelze).
- Strom na vlastní zahradě s obvodem kmene do 80 cm ve výšce 130 cm → povolení netřeba; ovocné stromy na zahradě
  u domu → netřeba (zjednodušení vyhl. 189/2013 Sb. – „ověřit“). Vypočti obvod z `sx` stromu (průměr × π).

### 2.3 Nové řádky katalogu (každý s „ověřit“)
`kradez_uroda` (sklizeň na cizím poli / zahradě), `vstup_na_cizi_pozemek` (jen v noci na cizí zahradě – drobnost),
`tyrani_zvirat` (M2.6), `prodej_masa_bez_povoleni` (M2.6), `ruseni_nocniho_klidu` (už je – rozšířit na motorovou pilu,
střelbu, hlasitou hudbu z auta), `znecisteni_vody` (vylití… volitelné), `jizda_na_koni_opily` (z přírody 04 – ověř, zda už je),
`chuze_opily_po_silnici` (ohrožení – jen svědek policista), `vytrznictvi` (rvačka – M5.5).

### 2.4 Kontrola konzistence
Projdi `data/zakon.json` – každý záznam: `nazev`, `zakon`, `par`, `pokuta`, `misto`, `trestny_cin`, `poznamka`. Deník J
ukazuje u každého záznamu i „kdo tě viděl“ (jméno svědka).

## 3. Hotovo, když
- Všechny činnosti používají `witness_check`; povolení ke kácení jde získat a respektuje se; nové přestupky fungují;
  svědci se chovají podle povahy a přátelství.

## 4. Návrh checklistu ručních testů
1. Kácení v lese před přísným vesničanem → nahlásí; před kamarádem (přátelství ≥ 60) → nenahlásí.
2. Motorová pila ve 23:00 u domu → rušení nočního klidu (sousedé slyší).
3. Úřad → žádost o povolení → za pár dní dopis → pokácet označený strom legálně.
4. Ovocný strom na vlastní zahradě → bez povolení OK.
5. Sklizeň na cizí zahradě → krádež úrody.
6. Nech zvířata hladovět a soused to uvidí → týrání.
7. Deník: u záznamů jména svědků.

## 5. Závěr
README, `data/zakon.json`, VIZE odškrtnout, roadmapa README, PROJECT_LOG, deník AI, commit „M4.4 Další přestupky a svědci: …“, checklist a čekat.
