# M2.2 – Oheň, opékání a topení v kamnech

> Roadmapa „Život na vsi“ · **M2 Řemesla a venkov** · krok 2/10
> Předpoklady: M2.1 (polena, klestí), M0.4, M0.5 · Navazují: M2.7 (pečení ryb), M2.9 (zvěřina), M5.3 (hasiči – požáry)

## 0. Než začneš – přečti
1. `prompts/roadmapa/00_SPOLECNE.md`
2. `docs/VIZE_A_ROADMAPA.md` – kap. 4.2 „Oheň“
3. `scripts/priroda/village_events.gd` – `_build_carodejnice`, `_fire_particles`, `_update_bonfire` (hotový vzhled ohně – **znovu použij**)
4. `scripts/body_state.gd` – `wetness`, `cold`, `update(dt_h, activity, env)` (jak se předává teplo z okolí – grep `env`)
5. `scripts/player.gd` – `_update_body` (co se posílá do `env`: pod střechou, v autě…)
6. `scripts/priroda/weather.gd` – `rain`, `wind`, `temp`, `wetness`, `rain_recent`
7. `scripts/actions.gd`, `scripts/fauna/fauna.gd` – `forest_at` (vzdálenost od lesa), `scripts/interior.gd` (kamna v domově z M1.4)

## 1. Proč
Oheň je druhá základní RuneScape činnost (Firemaking): hřeje, suší, svítí, peče jídlo. Nese i riziko –
požár a zákon.

## 2. Co udělat
### 2.1 Ohniště
- Akce `rozdelat_ohen` (cíl `ground`, nástroj `sirky|zapalovac`, spotřeba: 2× `klesti` + 2× `polena`
  nebo 4× `klesti`, dovednost `ohen`, 10 XP). Šance zapálení: základ 90 %, déšť −40 %, vítr > 6 m/s −25 %,
  mokré dřevo (`Weather.wetness`) −20 %, úroveň přidává. Sirky se spotřebují (1 ks na pokus).
- Nový `scripts/fire.gd` (`class_name Fire extends Node3D`): kruh kamenů (MeshKit), polena, plameny a kouř
  (částice z `VillageEvents` – vytáhni sdílenou funkci do statické, např. `FireFx.make(parent, radius, …)`),
  `OmniLight3D` s blikáním, zvuk praskání (`World.sound` nebo smyčka u klienta). `fuel` (minuty hoření):
  poleno +25 herních minut, klestí +8; déšť ubírá rychleji; při 0 dohasíná (žhavé uhlíky 20 min).
  Akce na ohni: `prilozit` (polena/klestí z inventáře), `uhasit` (voda z inventáře nebo zašlapat – 10 s).
- **Teplo:** hráč do 3 m od hořícího ohně → `env.heat` (sušení `wetness` 4× rychleji, `cold` klesá);
  napoj v `Player._update_body` (najdi, jak se tam počítá prostředí). Ohně registruje `World.fires`.
- **Opékání:** akce `opekat` na ohni: `parek` (už je v Potravinách), `buřt` (přidej do `ItemsDB` a obchodu), chleba,
  ryba/maso (M2.7, M2.9 – připrav obecně: předmět s klíčem `cook_to` → výsledný předmět). Délka 60 s, šance
  spálení klesá s dovedností `vareni` (spálený buřt = jídlo s menší kcal). XP `vareni`.
- **Ukládání:** ohně s `fuel > 0` a pozicí (a ohniště bez ohně – kamenný kruh zůstává, jde znovu zapálit).

### 2.2 Šíření a zákon
- **Zákaz:** oheň v lese (`forest_at > 0.5`) nebo **do 50 m od okraje lesa** (vzorkuj `forest_at` v kruhu 50 m –
  8 bodů) → přestupek podle zákona o lesích (289/1995 Sb., § 20 – rozdělávat oheň v lese a do 50 m od okraje;
  do `data/zakon.json` jako `ohen_u_lesa`). Svědci jako u kácení (vesničan, myslivec, policie do 150 m; kouř
  je vidět zdálky – šance zjištění i bez svědka 30 % za hodinu hoření).
- **Nehlídaný oheň** (hráč > 40 m) při suchu (`rain_recent < 0.2`, léto, vítr > 4 m/s): šance, že přeskočí na
  trávu → `GrassFire` (rozšiřující se kruh ohně po terénu na louce / v lese, max. poloměr 30 m, hoří 20 min),
  hráč ho může uhasit (akce `hasit` s vodou / lopatou) – jinak přijedou hasiči (háček pro M5.3: `emit_game_event("fire_report")`,
  zatím požár sám dohoří a hráč dostane přestupek `zpusobeni_pozaru` pokud byl původce + karma −5).
- Pálení čarodějnic (VillageEvents) není přestupek.

### 2.3 Kamna doma
- V interiéru domova (M1.4) kamna: akce `zatopit` (2 polena) → hoří 3 herní h / 2 polena, interiér je teplý
  (`env.heat` pro celý interiér), **vlastní komín domu hráče kouří** (napoj na `ChimneySmoke` z M1.3 – dům hráče
  vynucený kouř, když se topí). V zimě bez topení je doma zima (spánek v nevytopeném domě při < 5 °C venku
  → `cold` stoupá, horší odpočinek – mírně, laditelné).

## 3. Minimum
Ohniště + teplo + opékání buřtů + zákaz u lesa. Šíření trávou a kamna mohou do otevřených bodů.

## 4. Hotovo, když
- Oheň jde rozdělat (déšť to ztěžuje), hřeje a suší, jde opékat, dohoří, jde uhasit, ukládá se.
- U lesa je to přestupek; nehlídaný oheň v suchu umí chytit trávu (pokud hotovo).
- Doma jde zatopit a komín kouří.

## 5. Návrh checklistu ručních testů
1. Kup sirky a buřty; na louce u domu Q (sirky) → LMB na zem → oheň hoří, světlo, zvuk.
2. F2 → Počasí déšť, promokni, stůj u ohně → sušíš se rychle, prochladnutí klesá.
3. Opékání buřtu → hotový buřt v Tab, občas spálený; +XP Vaření.
4. Nepřikládej → oheň dohoří na uhlíky a zhasne.
5. Oheň 20 m od lesa u myslivce → přestupek.
6. Léto, sucho, vítr: odejdi 60 m → tráva chytí (pokud hotovo), uhas lopatou/vodou.
7. Doma v lednu zatop → komín domu kouří, uvnitř se zahřeješ.
8. F5/F9 s hořícím ohněm → oheň je zpět.

## 6. Závěr
README (Systémy → Oheň), `data/zakon.json`, VIZE odškrtnout, roadmapa README, PROJECT_LOG, deník AI,
commit „M2.2 Oheň a topení: …“, checklist a čekat.
