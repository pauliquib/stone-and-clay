# M1.6 – Nová auta a motorky (legální modely) + bazar

> Roadmapa „Život na vsi“ · **M1 Živý svět** · krok 6/6
> Předpoklady: M0.1 · Navazují: M2.10 (kufr, nosič motorky), M3.4 (bazar na PC), M4.1 (řidičská oprávnění podle typu)

## 0. Než začneš – přečti
1. `prompts/roadmapa/00_SPOLECNE.md` (kap. 3 – **odbrandování**, parodické názvy)
2. `VLASTNI_VOZIDLA.md` (celý) – jak přidat auto procedurálně i z `.glb`
3. `scripts/car_model.gd` – `MODELS` (ř. 12–105), `_build_from_scene`
4. `scripts/car.gd` – `setup`, parametry motoru / převodovky / hmotnosti (grep `MODELS`, `mass`, `torque`)
5. `scripts/bike_model.gd` (hlavička + tabulky) – motorka Javor, kolo Favorín
6. `scripts/traffic.gd` – jak se vybírá model a barva AI aut (grep `MODELS|pick`)
7. `scripts/world.gd` – `spawn_vehicle`, `_connect_car`; `scripts/game_menu.gd` – `open_vehicles`
8. `ASSETY.md` a `assets/LICENSES.md` (z M0.1)

## 1. Proč
Víc druhů aut a motorek do dopravy i pro hráče. Uživatel chce použít **legálně dostupné free modely**.

## 2. Co udělat
1. **Katalog vozidel** – rozšiř `CarModel.MODELS` (nebo nový `data/vozidla.json`, pokud je to čistší)
   o pole: `kategorie` (osobní / dodávka / pickup / traktor / motorka / skútr / moped), `skupina_rp`
   (řidičské oprávnění: `AM`, `A1`, `A2`, `A`, `B`, `T` – pro M4.1), `cena` (bazarová, Kč), `rok`,
   `kufr_l` (objem kufru – M2.10), `nosic` (motorka má zadní nosič – M2.10), `glb` (cesta, volitelné).
2. **Nová vozidla** – nejméně 3 auta a 2 jednostopá, parodické názvy ve stylu hry (Oktávka, Fábička,
   Stodvacka, Javor…). Názvy musí být obecné nebo jen volně parodické – nesmí kopírovat skutečnou značku
   ani typ. Návrh: **dodávka „Bednář“**, **pickup „Lesák“**, **kombi „Rodinka“**, **malotraktor „Traktůrek“**,
   **moped „Pionýrek“**, **skútr „Včelka“**.
   Nejdřív **procedurálně** (loft v `CarModel` stačí), `.glb` jen pokud uživatel dodá model do
   `assets/models/vozidla/` (napiš mu v logu doporučené CC0 zdroje – Kenney Car Kit, Quaternius Cars – a
   postup odbrandování). Fyzikální parametry realisticky (hmotnost, výkon, max. rychlost, převody).
   Traktor: pomalý (max 30 km/h), silný moment, vysoko posazený.
3. **AI doprava:** váhy výskytu podle kategorie (hodně osobních, občas dodávka, traktor jen v sezóně
   polních prací a jen na okreskách / polních cestách – pokud to graf silnic umí; jinak jen okresky).
4. **Bazar** (zatím bez PC): na úřadě nebo nová cedule „Bazar“ u silnice (vyber místo blízko obce, `pois` nerozšiřuj
   ručně, stačí konstanta pozice) → nabídka 3–5 vozidel (mění se týdně – seed podle týdne), koupě za peníze,
   vozidlo se přistaví k domu hráče. Prodej vlastního vozidla za 60 % ceny (podle poškození). Hráč může mít
   víc vozidel (seznam ve `World`, ukládat). Najdi, jak se dnes ukládá auto hráče (`save_game.gd` grep `car`),
   a rozšiř na seznam.
5. F2 → Vozidla: nová vozidla k přistavení (test).

## 3. Hotovo, když
- Nová vozidla jezdí v AI dopravě a jdou řídit; jednostopá se naklánějí; traktor je pomalý a silný.
- V bazaru jde koupit / prodat vozidlo, uloží se.
- Žádné logo, značka ani skutečný název modelu.

## 4. Návrh checklistu ručních testů
1. F2 → Vozidla → přistav každé nové vozidlo, projeď se: zrychlení, max. rychlost, řazení odpovídá typu.
2. Moped a skútr: náklon, pád při nárazu, nohy na stupačkách.
3. Traktor: pomalý, vyjede do kopce na louku.
4. Pozoruj 10 min dopravu → občas dodávka, v sezóně traktor.
5. Bazar: kup dodávku → stojí u domu; prodej ji → peníze.
6. F5/F9 → vlastněná vozidla zůstanou.

## 5. Závěr
README (Systémy → Doprava, Bazar), `VLASTNI_VOZIDLA.md` (nové parametry), `assets/LICENSES.md` (pokud modely),
VIZE odškrtnout, roadmapa README, PROJECT_LOG, deník AI, commit „M1.6 Nová vozidla a bazar: …“, checklist a čekat.
