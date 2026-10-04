# M2.4 – Zahrada a pole: rytí, setí, péče, sklizeň

> Roadmapa „Život na vsi“ · **M2 Řemesla a venkov** · krok 4/10
> Předpoklady: M0.2, M0.3, M0.4 · Navazují: M2.5 (sázení stromů), M2.6 (krmivo pro zvířata), M3.2 (práce na farmě), M4.5 (pomoc sousedům)

## 0. Než začneš – přečti
1. `prompts/roadmapa/00_SPOLECNE.md`
2. `docs/VIZE_A_ROADMAPA.md` – kap. 4.2 „Pole a zahrada“
3. `scripts/priroda/fields.gd` (celý, 220 ř.) – plodiny (`CROPS`), kalendář, osevní postup, `landuse.bin`
4. `scripts/priroda/seasons.gd` (61 ř.) – `grass_green`, vegetační sezóna
5. `scripts/priroda/weather.gd` – `temp`, `rain`, `rain_recent`, `forecast()`
6. `scripts/clock.gd` – `day()`, `jd()`, `month()`, `day_of_year()`
7. `scripts/actions.gd`, `scripts/items_db.gd` (semena, nástroje z M0.2), `scripts/skills.gd`
8. `scripts/world.gd` – `skip_time`, `rest` (růst musí běžet i při spánku / skoku času)

## 1. Proč
Obdělávání zahrady a pole je hlavní klidná, legální RuneScape činnost (Farming): pěstuješ jídlo,
krmivo pro zvířata, prodáváš úrodu. Využívá kalendář a počasí, které už hra má.

## 2. Návrh
### 2.1 Záhony (vlastní zahrada)
- U domu hráče vyhraď **zahradu** (obdélník ~12 × 8 m za domem; najdi volné místo – nesmí kolidovat s koněm,
  stájí z přírody 04, autem, budoucí U-rampou M5.8 – ponech pro rampu místo ~8 × 6 m a zapiš ho do konstanty).
- Záhon = buňka 1 × 1 m v mřížce zahrady (`Garden` – nový `scripts/garden.gd`, `class_name Garden`). Stav buňky:
  `trava` → (akce `ryt`, rýč/lopata/motyka, 20 s) → `zryto` → (`sit`, semeno) → `zaseto(plodina, den)` →
  růst ve fázích → `zralé` → (`sklidit`) → úroda + zpět `zryto`. Plevel přibývá (akce `plet`), bez zálivky
  v suchu vadne (akce `zalevat`, konev naplněná u studny / kohoutku u domu – akce `naplnit` → `konev_plna`).
- **Plodiny** (tabulka `CROPS` v `garden.gd`, laditelné): `brambory` (výsev IV–V, 100 dní, úroda 6–12 ks),
  `mrkev` (IV–VI, 80 d), `cibule` (III–IV, 90 d), `salat` (IV–VIII, 45 d), `rajcata` (V, sazenice, 90 d,
  mráz = zničí), `dyne` (V, 120 d), `cesnek` (X → VII, přes zimu). Každá: `sow_months`, `days`, `water_need`,
  `frost_kill` (°C), `yield` [min, max], `xp`, `seed_price`. Mimo měsíc výsevu nejde zasít (hláška).
- **Růst** – denní krok (při změně herního dne a při skoku času – spánek, F2 datum): přírůstek × vláha (déšť
  nebo zálivka ten den) × teplota (pod 5 °C stojí) × plevel; mráz pod `frost_kill` zničí. Výnos podle péče
  a úrovně `zahradnictvi`.
- **Vzhled:** zrytá hlína (tmavý quad), rostlinky po fázích (MeshKit: klíček → listy → plná rostlina,
  barva plodiny; rajčata s kůlem, dýně s plody) – vše v jednom MultiMesh / mesh na zahradu, přestavba při
  změně stavu.

### 2.2 Pole (pronájem)
- Pole z `Fields` (landuse třída 1) – hráč si může **pronajmout** jedno malé pole (na úřadě, 1 500 Kč / rok –
  jen háček ve `World`, UI stačí v nabídce úřadu „Pronájem pole“). Na poli jde to samé co na zahradě, ale ve
  větším měřítku jen s traktorem (M1.6) – **zatím mimo rozsah**: jen pronájem, zobrazení hranice pole na mapě M
  a záhony na okraji pole (mřížka 1 m jako zahrada, max. 10 × 10 m). Velkoplošné obdělávání traktorem = otevřený bod.

### 2.3 Úroda a využití
- Předměty `brambory`, `mrkev`, `cibule`, `salat`, `rajce`, `dyne`, `cesnek` (typ `food`, kcal, dají se jíst syrové
  nebo vařit doma – vaření doma: sporák v interiéru, recept „bramborová polévka“ = brambory + cibule + voda →
  `polevka` (M0.2 recepty, pokud existují; jinak jednoduchá akce na sporáku)).
- Výkup: Potraviny kupují zeleninu (nižší cena než prodávají), sousedé (děda) ocení dárek (respekt `sousede`,
  háček `give_to_npc` z M0.6).
- Semena v Potravinách (sezónně IV–VI) a později ve stavebninách (M5.1).

### 2.4 Ukládání
Stav všech buněk (plodina, den, fáze, voda, plevel), pronájem pole.

## 3. Minimum
Zahrada se 3 plodinami, rytí / setí / zálivka / sklizeň, růst podle dní a mrazu, ukládání.

## 4. Hotovo, když
- Na zahradě u domu jde celý cyklus od rytí po sklizeň; plodiny rostou i během spánku; mráz a sucho škodí.
- Úrodu jde sníst, uvařit polévku (pokud hotovo), prodat.

## 5. Návrh checklistu ručních testů
1. F2 → Datum 20. dubna; kup rýč/motyku, semena brambor a mrkve; za domem zryj 4 záhony (LMB).
2. Zasej; mimo sezónu (F2 → srpen) zkus zasít brambory → hláška „teď se nesází“.
3. Konev: naplnit u domu, zalít; spi 5 nocí → rostlinky vyrostly.
4. F2 → červenec, sucho bez zálivky → vadnou; po zalití se vzpamatují.
5. F2 → srpen → sklizeň brambor → v Tab; +XP Zahradničení.
6. Rajčata + mráz (F2 → květen, teplota −2) → zničená.
7. Prodej zeleniny v Potravinách.
8. F5/F9 → záhony ve stejném stavu.

## 6. Závěr
README (Systémy → Zahrada), VIZE odškrtnout, roadmapa README, PROJECT_LOG, deník AI, commit „M2.4 Zahrada: …“, checklist a čekat.
