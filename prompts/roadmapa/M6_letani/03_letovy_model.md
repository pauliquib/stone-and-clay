# M6.3 – Společný letový model (vztlak, odpor, vítr, termika)

> Roadmapa „Život na vsi“ · **M6 Létání** · krok 3/5
> Předpoklady: M6.2 (hranice letu), M6.1 (vítr / turbulence – znovu použij) · Navazují: M6.4 paramotor, M6.5 motorové rogalo

## 0. Než začneš – přečti
1. `prompts/roadmapa/00_SPOLECNE.md`
2. `docs/VIZE_A_ROADMAPA.md` – kap. 4.6
3. `scripts/car.gd` – struktura vozidla (vstup / výstup hráče, kamera, `InputState`, `_physics_process`) – **letadla budou
   vozidla** stejného typu vstupu (F nasednout, F vystoupit na zemi), aby fungovalo ukládání, kamera, `World.enter_car`
   (zjisti, jestli jde přidat nový typ vedle `Car`/`Horse` – grep `p.car` / `p.horse` v `world.gd`, `player.gd`, `local_client.gd`)
4. `scripts/priroda/weather.gd` – `wind_vector()`, `wind`, `cloud`, `temp`, `storm`, `kind`
5. Dron z M6.1 (turbulence, HUD) – `scripts/drone.gd` (nebo jak se jmenuje – grep `class_name` v nových souborech)
6. `scripts/terrain.gd` – `height_at` (výška nad terénem, přistání), `scripts/fauna/fauna.gd` – `forest_at` (termika nad polem vs. lesem)

## 1. Proč
Motorový paraglide i motorové rogalo potřebují stejný základ: aerodynamiku, vítr, termiku, vzlet a přistání,
přístroje. Uděláme jeden **letový model** a dva stroje nad ním (M6.4, M6.5).

## 2. Návrh
- Nový `scripts/flight/aircraft.gd` (`class_name Aircraft extends RigidBody3D`) – **společná třída** pro ultralehké stroje:
  - parametry v tabulce (per stroj): hmotnost (prázdná + pilot + palivo), plocha křídla `S`, `CL(α)` (lineárně do α_krit,
    pak pád – pokles vztlaku), `CD0`, indukovaný odpor (`CL² / (π·AR·e)`), tah motoru (N) podle plynu a rychlosti,
    minimální rychlost (pádová), trimová rychlost, max. rychlost, klouzavost, rychlost stoupání, spotřeba paliva (l/h), nádrž.
  - síly: vztlak ⟂ na relativní vzduch (rychlost − **vítr**), odpor proti, tah ve směru motoru, gravitace; momenty jen
    zjednodušeně (stroj se natáčí podle ovládání s „tlumičem“ – arkádově-realistické, ne plná 6DOF simulace).
  - **Vítr:** `Weather.wind_vector()` + výškový profil (u země slabší – mocninný zákon `v(h) = v10·(h/10)^0.14`) +
    **turbulence** (šum – silnější za bouřky, nad lesem a v závětří kopců – jednoduše podle sklonu terénu proti větru).
  - **Termika:** za slunečného dne 11–17 h v létě (`Weather.kind` jasno/polojasno, teplota > 18 °C) stoupavé proudy
    0,5–3 m/s nad poli / zástavbou (ne nad lesem a vodou) – bubliny (sloupce) s náhodnou polohou, driftují po větru,
    žijí 5–15 min; nad nimi kumuly (volitelně spojit s mraky). Pod mrakem v bouřce silné stoupání (nebezpečí).
  - **Kontakt se zemí:** podvozek (kola / nohy pilota) – koeficient tření podle povrchu (tráva / asfalt), rozjezd, přistání;
    tvrdé přistání (vertikální rychlost > 3 m/s) → poškození / zranění; náraz do stromu / budovy → havárie (`hurt`, poškození stroje).
  - **Palivo:** spotřeba podle plynu; 0 = bezmotorový let (klouzání) – musí přistát.
  - **Přístroje / HUD** (`scripts/flight/flight_hud.gd`): výška MSL / AGL, rychlost vůči vzduchu (IAS) a vůči zemi, variometr
    (stoupání m/s + zvuk pípání v termice), kompas, palivo, vítr (šipka), varování pádu (rychlost blízko pádové).
- Integrace jako vozidlo: `Player.aircraft` (vedle `car` a `horse`), `World.enter_aircraft/exit_aircraft`, kamera za strojem /
  z pohledu pilota (V), ukládání pozice a paliva stroje. **Opilý pilot** → zpožděné reakce (jako v autě), přestupek (letectví
  pod vlivem – `data/zakon.json`, „ověřit“ – zákon o civilním letectví 49/1997 Sb.).
- Hranice letu a strop z M6.2.
- **Testovací stroj:** „létající bedna“ – jednoduchý model s parametry paramotoru (pro ověření) – F2 → Vozidla → „Testovací
  letoun“. V M6.4 se nahradí paramotorem.

## 3. Hotovo, když
- Testovací stroj se rozjede, vzlétne, reaguje na plyn a řízení, vítr ho unáší, v termice stoupá, při malé rychlosti padá,
  přistane (měkce / tvrdě), spotřebovává palivo; HUD a variometr fungují; ukládá se.

## 4. Návrh checklistu ručních testů
1. F2 → Vozidla → Testovací letoun na louce; F nasednout; plyn (W) → rozjezd → vzlet.
2. Stoupání, otáčení (A/D), zpomalení → varování pádu → propad.
3. F2 → vítr silný → let proti větru pomalý vůči zemi, po větru rychlý.
4. Letní poledne jasno nad polem → variometr pípá, stoupáš bez plynu.
5. Palivo 0 → klouzání, přistání na louce.
6. Tvrdé přistání → poškození / zranění.
7. F5/F9 ve vzduchu / na zemi → stroj na místě, palivo.

## 5. Závěr
README (Systémy → Létání – model), VIZE odškrtnout, roadmapa README, PROJECT_LOG, deník AI, commit „M6.3 Letový model: …“, checklist a čekat.
