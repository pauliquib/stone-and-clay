# M6.1 – Dron

> Roadmapa „Život na vsi“ · **M6 Létání** · krok 1/5
> Předpoklady: M0.3 (dovednost `letectvi`), M0.5, M4.1 (`Permits`), M3.4 (eTesty) · Navazují: M6.2 (pozadí mapy z výšky), M4.4 (přestupky)

## 0. Než začneš – přečti
1. `prompts/roadmapa/00_SPOLECNE.md` (kap. 3 – **soukromí**: dron nesmí dávat průhledy do reálných dvorů – interiéry se nevykreslují, okna neprůhledná)
2. `docs/VIZE_A_ROADMAPA.md` – kap. 4.6 „Dron“
3. `scripts/local_client.gd` – kamera (`attach`, jak se přepíná kamera hráč / auto / kůň – grep `camera|current`)
4. `scripts/player.gd` – `controls_locked`, `input`; `scripts/input_state.gd` (osy pohybu a pohledu)
5. `scripts/priroda/weather.gd` – `wind_vector`, `rain`, `temp` (baterie v zimě)
6. `scripts/terrain.gd` – `height_at`, `contains` (hranice mapy); `scripts/fauna/*` – reakce ptáků / zvěře na hluk
7. `scripts/law.gd`, `data/zakon.json`, `scripts/permits.gd`, `scripts/computer_ui.gd` (eTesty)

## 1. Proč
První „létající prostředek“ z poznámek uživatele. Malý, levný, s jasnými pravidly (EU / ÚCL), zábavný
a užitečný (pohled na obec, hledání zvěře, doručení balíčku – humor).

## 2. Návrh
### 2.1 Dron jako objekt a ovládání
- Předmět `dron` (e-shop M3.4 / stavebniny „Sport“, 7 990 Kč, 249 g – kategorie „do 250 g“ – nebo `dron_velky` 2,5 kg, 29 990 Kč).
- Tab → „Vzlétnout s dronem“ → dron se položí před hráče a vzlétne na 2 m; **hráč stojí** (ovládá z ruky – vizuál ovladače
  v rukou, `controls_locked` pro pohyb) a kamera přejde na **pohled z dronu** (V = přepnout na pohled na hráče / z dronu).
- Ovládání (mód 2): **W/S** = vpřed/vzad (pitch), **A/D** = do stran (roll), **myš X** = otáčení (yaw), **Mezerník / Ctrl** =
  stoupat / klesat, **Shift** = sport mód (rychleji, víc spotřeba), **kolečko** = náklon kamery (gimbal), **F** = přistát a sebrat
  (když je dron do 3 m od hráče; jinak „návrat domů“ – RTH: dron automaticky letí k hráči a přistane).
- **Fyzika:** `RigidBody3D` s jednoduchým modelem: tah 4 vrtulí (vertikální síla), naklonění → vodorovná síla, odpor vzduchu,
  **vítr** (síla + turbulence nárazů podle `Weather.wind`, u velkého dronu menší vliv), stabilizace (asistence držení výšky
  a polohy – dron sám drží pozici, když se nic nemačká). Max 15 m/s (sport 19), stoupání 5 m/s.
- **Baterie:** 30 min letu (laditelné; herní čas vs. reálný – 1 herní min = 0,5 s reálně; ber baterii v **reálných sekundách**:
  12 min reálně), v mrazu −30 %, sport mód −40 %. Při 15 % varování, při 5 % automatický návrat, při 0 % pád.
  Nabití doma (zásuvka – E u stolu) 1 herní h.
- **Dosah signálu:** 1 500 m od hráče (za překážkou – terén / budova mezi → 400 m); nad dosahem → ztráta signálu → RTH.
- **HUD dronu:** výška nad zemí (AGL) a nad místem vzletu, vzdálenost, rychlost, baterie, signál, kompas, varování „Nad lidmi!“,
  „Nad 120 m!“, „Zóna – soukromý pozemek“.
- **Kolize:** náraz > 4 m/s → pád (poškození – oprava 1 500 Kč), do stromu → zasekne se (akce vyprostit – ztráta, když je vysoko);
  zásah člověka → zranění, přestupek / trestný čin (ublížení).
- **Model:** MeshKit – tělo, 4 ramena, vrtule (rotují), LED (zelená / červená), kamera s gimbalem. Zvuk bzučení (procedurální –
  `sfx.gd`), slyšet do ~60 m → ptáci vzlétnou, zvěř zpozorní (napoj na `_perceive` jako hluk).
- Fotky: klávesa (volná, ověř registr) = snímek do `user://screenshots` (využij existující `screenshot()`).

### 2.2 Pravidla ÚCL / EU (zjednodušeně – do `data/zakon.json` sekce `drony`, s poznámkou „ověřit – nařízení EU 2019/947, ÚCL“)
- **Registrace provozovatele** (`dron_provozovatel`) – na PC (M3.4) za 0 Kč / symbolicky; číslo provozovatele se „nalepí“ na dron.
  Dron do 250 g bez kamery ji nepotřebuje – dron ve hře má kameru → potřebuje vždy.
- **Online test A1/A3** (`dron_a1a3`) – eTest 20 vlastních otázek (pro velký dron povinný).
- Max **120 m** nad zemí, **ne nad shromážděním lidí** (dav – událost, zábava, zápas), ne nad cizími lidmi (dron > 250 g),
  vizuální dohled (VLOS – když je dron dál než 500 m nebo za překážkou, varování; > 1 min → přestupek), ne v noci bez světel.
- **Soukromí:** dlouhé kroužení (> 30 s) do 30 m nad cizím pozemkem v zástavbě (zahrady, `settle_at`) → vesničan si stěžuje,
  přestupek `narusovani_soukromi` (zákon o ochraně osobnosti / GDPR – zjednodušeně, „ověřit“).
- Porušení → `commit_offense` přes svědky (vesničan vidí / slyší dron; policie). Sestřelení dronu vesničanem? ne (humor – jen
  hláška „Soused na dron hodil hrábě.“ a dron spadne při nízkém letu nad jeho zahradou – volitelně).

## 3. Minimum
Let (fyzika, vítr, baterie, dosah, RTH), HUD, kolize a pád, registrace provozovatele + limit 120 m + nad lidmi.

## 4. Hotovo, když
- Dron jde koupit, vzlétnout, ovládat, vrátit, nabít; vítr a mráz mají vliv; pravidla se hlídají a porušení jsou přestupky; stav se ukládá.

## 5. Návrh checklistu ručních testů
1. F2 → peníze; PC → kup dron; registrace provozovatele; Tab → Vzlétnout.
2. Let nad obcí: W/A/S/D, myš, Mezerník/Ctrl; pusť ovladač → dron drží pozici.
3. Silný vítr (bouřka) → dron uhání, sport mód bojuje.
4. Nad 120 m → varování, pak přestupek.
5. Nad zábavou / zápasem → „Nad lidmi!“ → přestupek.
6. Baterie 5 % → automatický návrat; dosah 1,5 km → ztráta signálu → RTH.
7. Náraz do stromu → zaseknutý / pád.
8. Kroužení nad cizí zahradou → soused si stěžuje.
9. F5/F9 → dron v inventáři, nabití zůstane.

## 6. Závěr
README (Systémy → Dron, Ovládání), `data/zakon.json`, VIZE odškrtnout, roadmapa README, PROJECT_LOG, deník AI, commit „M6.1 Dron: …“, checklist a čekat.
