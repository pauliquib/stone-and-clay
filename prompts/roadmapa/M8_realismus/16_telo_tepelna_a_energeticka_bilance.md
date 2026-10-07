# M8.16 – Tělo 2: tepelná a energetická bilance, žízeň, únava a zranění pádem

> Roadmapa **M8 Realistický svět** · krok 16/19 · vlna 5
> Předpoklady: **M8.9 (`Microclimate`)** (M8.4 vítr, M8.5 záření – použij, pokud jsou) · Navazují: M8.6 (postoj podle stavu – už čte `BodyState`), M8.17

## 0. Než začneš – přečti
1. `00_SPOLECNE.md`, `M8_realismus/00_PRINCIPY.md` (kap. 8 – člověk, tělo)
2. `scripts/body_state.gd` (celý, 413 ř. – `wetness`, `cold`, izolace `INSUL_*`, přehřátí, výdrž, kalorie, hmotnost, alkohol, nikotin)
3. `scripts/wardrobe.gd` / oblečení (`grep -rn "insul\|izolace\|waterproof" scripts/*.gd | cut -c1-120 | head`), `scripts/consumables.gd` (pití – voda?)
4. `scripts/player.gd` – výdrž a sprint (`grep -n "stamina\|drain_stamina\|_on_land\|land(" scripts/player.gd | head -30`), dopad ze skoku / pád
5. `scripts/hud.gd` – ukazatele těla (`grep -n "cold\|wet\|stamina" scripts/hud.gd | head`), `scripts/save_game.gd` `BODY_KEYS`

## 1. Proč
Tělo už má promáčení, chlad, přehřátí a kalorie – ale jako oddělená pravidla s „pocitovou teplotou“. Fyzikálně je to jedna **tepelná bilance**:
tělo vyrábí teplo podle námahy (chůze do kopce s nákladem hřeje, sezení na posedu v mrazu chladí), ztrácí ho větrem, vodou a vyzařováním,
oblečení izoluje (a mokré izoluje mnohem hůř), slunce hřeje. K tomu chybí **žízeň** (léto, práce, alkohol dehydratuje), **únava a spánek**
a zranění **pádem z výšky** (střecha, posed, strom).

## 2. Co udělat
- **Tepelná bilance (`body_state.gd`, nová funkce `_heat_balance(dt_h, env)`, za přepínačem `thermo`; stará pravidla jako fallback):**
  - `M` metabolické teplo z činnosti (MET tabulka: stání 1,2, chůze 2,5–4 podle rychlosti a sklonu, běh 8, sekání dřeva 6, nošení nákladu +1–3,
    spánek 0,9) – vstup z `Player` (rychlost, sklon z terénu, náklad, aktuální akce);
  - ztráty: **konvekce** ∝ (T_kůže − T_vzduch) × (1 + k·√vítr) / izolace, **odpařování** (pocení při M vysokém, odpar mokrého oblečení – chladí a suší),
    **záření** (zisk ze slunce podle `Atmosphere.global_horizontal_irradiance_wm2` a stínu, ztráta do jasné noční oblohy), **vedení** (sezení / ležení
    na studené zemi, sníh);
  - **izolace oblečení v clo** (dnešní `INSUL_*` převést: 0,4 ≈ triko + džíny ≈ 0,6 clo …), **mokré oblečení ztrácí 50–80 % izolace**, vítr
    stlačuje izolaci (kromě nepromokavé / větruodolné vrstvy – vlastnost v katalogu oblečení);
  - stav: **tělesná teplota jádra** `t_core` (37,0 °C; 35 = podchlazení, 38,5+ = přehřátí) s tepelnou kapacitou těla; z ní odvoď dnešní `cold`
    a přehřátí (zachovej API pro ostatní systémy); prostředí z `Microclimate.temp_at`, `wind_chill_at`, `WindField`, `Weather.rain`, oheň (`heat` jako dnes).
- **Voda v těle – žízeň:** `hydration` (l): ztráty dýcháním a pocením (∝ M a teplotě), **alkohol zvyšuje diurézu** (napoj na `body_alc`), příjem z nápojů
  (`Consumables` – voda, čaj, pivo – pivo hydratuje méně, kořalka dehydratuje) a jídla; žízeň snižuje výdrž, dehydratace = bolest hlavy (efekt obrazu
  mírný), únava; **studánka (M5.10)** a kohoutek doma = voda zdarma. Předmět `lahev_voda` (pokud není) a pití z potoka (riziko nevolnosti malé).
- **Energie a únava:** dnešní kalorie a hmotnost ponech; přidej **spánkový dluh** (hodiny bdění → ospalost, mikrospánek za volantem jako opilost
  – sdílej `drunk_fx` / reakce s menší silou), kofein (kafe doma už je) ho dočasně snižuje; spánek ho maže. Ospalost v deníku a HUD (ikona).
- **Pád z výšky:** při dopadu (`Humanoid.land(impact)` / `Player`) rychlost dopadu → zranění: > ~6 m/s (≈ 2 m) bolest a krátké kulhání (`Player.speed_mods`),
  > ~9 m/s (≈ 4 m) zranění (zdraví), > ~13 m/s (≈ 9 m) vážné / bezvědomí (dnešní mechanika probuzení v nemocnici). Měkký dopad (sníh, voda, seno)
  tlumí. Zvuk a efekt obrazu.
- **HUD a deník:** ikony stavu jen když je co hlásit (zima, horko, žízeň, ospalost, zranění), deník J → Zdraví s větami („Jsi promoklý a fouká – v tomhle
  oblečení prochladneš za půl hodiny.“). Žádná čísla jádra na HUD (jen v F2 ladění).
- **NPC (malé):** vesničané v zimě oblečení tepleji podle teploty v místě (už podle sezóny? – jen ověřit), v horku hledají stín (háček pro M8.17).
- Ukládání: `t_core`, `hydration`, `sleep_debt`, zranění (rozšířit `BODY_KEYS` s výchozími hodnotami).

## 3. Minimum
Tepelná bilance s metabolismem podle činnosti, konvekcí s větrem, odpařováním a izolací v clo (mokrá horší), `t_core` → dnešní `cold`/přehřátí;
žízeň s nápoji a alkoholem; zranění pádem podle rychlosti dopadu.

## 4. Hotovo, když
- V mrazu je hráči teplo při výstupu do kopce s nákladem, ale na posedu při čekání rychle prochladne; mokrý ve větru prochladne mnohem rychleji než suchý.
- V létě při práci roste žízeň, pivo ji neuhasí jako voda; skok ze střechy zraní, do sněhu méně.

## 5. Návrh checklistu ručních testů
1. Leden −5 °C, bunda: chůze do kopce s pytlem → chlad neroste; stát 30 herních min na posedu → roste.
2. Promoknout v dešti a stát ve větru → rychlé prochladnutí; u ohně rychlé zahřátí a schnutí.
3. Červenec 30 °C, sekání dřeva → žízeň; napít se vody ze studánky → klesne.
4. Pět piv v horku → žízeň a únava rostou.
5. 20 h bez spánku → ospalost; jízda autem → občasné mikrospánky; kafe pomůže.
6. Seskok z 2 m → nic / bolest; ze střechy (~5 m) → zranění a kulhání; do závěje → méně.
7. Deník J → Zdraví → srozumitelné věty.
8. F5/F9 → stav těla zůstane.
9. Přepínač Tepelná bilance vypnout → stará pravidla.

## 6. Závěr
`docs/SYSTEMS.md` (Fyziologie – doplnit), README (HUD ikony), PROJECT_LOG, `docs/testy_M8.md`, commit „M8.16 Tělo 2: …“.
