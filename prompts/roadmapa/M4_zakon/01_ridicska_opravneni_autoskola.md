# M4.1 – Řidičská oprávnění a autoškola

> Roadmapa „Život na vsi“ · **M4 Zákon a společnost** · krok 1/8
> Předpoklady: M0.5 (zákon), M1.6 (`skupina_rp` u vozidel), M3.4 (eTesty), M6.1 (`Permits` – už existuje)
> Navazují: M4.2 (vrácení řidičáku na úřadě, dluhy), M4.6 (zbrojní / lovecký / rybářský doklad stejným mechanismem), M3.3 (rozvoz)
> Stav kódu ověřen po vlně 0 (commit `357f7eb`). Když grep ukáže něco jiného, věř kódu a rozdíl zapiš do logu.

## 0. Než začneš – přečti
1. `prompts/roadmapa/00_SPOLECNE.md`
2. `docs/VIZE_A_ROADMAPA.md` – kap. 4.4 „Řidičská oprávnění“
3. `scripts/permits.gd` (97 ř., **celý**) – tohle rozšiřuješ
4. `scripts/law.gd` (107 ř., celý) + začátek `data/zakon.json` (pole `drb`, `karma`, `misto`, `blokova`)
5. `scripts/world.gd` – jen výřezy: `has_permit` (grep `func has_permit`, ~ř. 2898), `enter_car` (~ř. 1820),
   `_on_busted` (~ř. 1553), založení `permits` (grep `permits = Permits.new`), létací škola paramotoru
   (grep `PG_TRAIN_FLIGHTS`, ~ř. 2150–2240) – **vzor kurzu** (platba, teorie, praxe počítaná instruktorem, udělení)
6. `scripts/police.gd` – `license_ok` (ř. ~191), `_plan` (~341), `_stopping` (~520), `breath_test` (~625)
7. `scripts/car_model.gd` – `MODELS[*].skupina_rp`, `CarModel.catalog(id)`
8. `scripts/computer.gd` – `TESTS` (ř. ~50), `record_test` (~736); `scripts/test_ui.gd` – formát testu (hlavička souboru)
   a `data/testy/pravidla_cvicny.json` (vzor JSON)
9. `scripts/jobs.gd` – `can_apply` (~ř. 322–368, klíč `pozadavky.ridicak`)
10. `scripts/save_game.gd` – klíč `permits` (grep `permits`)

## 1. Proč
Simulace reálného života v ČR: řídit se smí jen s příslušným řidičským oprávněním. Hráč ho na začátku má
jen pro **B** (auto) a **AM** (moped) – motorky a traktor vyžadují další skupiny, které si může udělat v autoškole.
Bez oprávnění = přestupek (opakovaně trestný čin). Hra nic nezakazuje, jen nese důsledky.

## 2. Co už v kódu je (nepřepisuj, rozšiřuj)
- **`Permits`** (`class_name Permits extends Node`, M6.1) – **jediná instance** `World.permits` (ne slovník per hráč),
  stav `grants[pid][kind] = {"no", "jd"}`. API: `has(pid, kind)`, `grant(pid, kind, no := "")`, `number(pid, kind)`,
  `granted_day(pid, kind)`, `describe(pid)`, `to_dict(pid)` / `from_dict(pid, d)`, `add_player(pid)`.
  **Pozor:** `from_dict` zahazuje druhy, které nejsou v `KINDS` → každý nový druh **musí** být v `KINDS`.
  V `KINDS` jsou dnes jen `dron_provozovatel`, `dron_a1a3`, `pilot_pg_motor`, `pg_registrace`, `pg_pojisteni`,
  `pilot_ul`, `ul_registrace`, `ul_pojisteni`.
- **`World.has_permit(id, kind, pos)`** – 3 parametry, 3 zdroje v tomto pořadí: `les.work_permit` (jen `kind == "kaceni"`,
  lesní dělník na směně), `permits.has`, `_cheat_permits` (F2 → Hráč). **Všechny tři zachovej**; cheat zůstává jen v F2.
  Názvy druhů, které už kód volá (zatím je drží jen cheat): `kaceni` (ne `povoleni_kaceni`), `zbrojni`, `lovecky_listek`,
  `povolenka_lov`, `rybarsky_listek`, `povolenka_rybolov`. Ty do `KINDS` přidej už teď (název, vydavatel, poznámka),
  i když je udělí až M4.4 / M4.6 – ať se uložené doklady nezahodí.
- **Vozidla:** `skupina_rp` v `CarModel.MODELS`: osobní / dodávky / pickup `B`, Traktůrek `T`, Pionýrek 50 `AM`,
  Včelka 125 `A1`, Dědova Javor 250 a Armádka 750 `A2`, Krosák 1000 `A`, kolo `""` (bez oprávnění).
- **Zákaz řízení:** jen `Player.license_suspended_until` (herní minuty) – nastavuje ho `Law.LawRecord.commit`
  (`zakaz_rizeni_h`, při 12 bodech `zakaz_za_body_h` = 1 rok a body na 0). `Police.license_ok(p)` = jen „není zákaz“.
  `World.enter_car` jen upozorní na zákaz, skupinu **nekontroluje**. `police.gd` doklady **nekontroluje** (plán `"ok"` =
  „jen doklady“ je jen text).
- **Klávesa P** nikde není (`project.godot` ani `local_client.gd`) – panel dokladů napiš celý. Panel úkolu je na **Z**
  (fyzicky Y, akce `quest_panel`), nepleť si je.
- **eTest autoškoly:** `Computer.TESTS["autoskola"]` je placeholder s prázdnou cestou; `data/testy/autoskola.json`
  **neexistuje**. `TestUI` po vlně 0 umí `pocet` (losování z banku), `prah_pct` a sám míchá pořadí odpovědí.
- **`Jobs.can_apply`**: `pozadavky.ridicak` dnes kontroluje jen `license_ok` (komentář „do M4.1“). Žádná práce v
  `data/prace.json` zatím `ridicak` nevyžaduje (všude `""`).
- `data/zakon.json`: `rizeni_bez_opravneni` ani sekce `ridicska_opravneni` **nejsou**. `rizeni_pres_zakaz` je.

## 3. Návrh
### 3.1 Rozšíření `Permits` (zpětně kompatibilní)
- Položka dokladu: `{"no", "jd", "sub": {skupina: jd}, "valid_until": jd | -1, "revoked": {} }`, kde `revoked` =
  `{"reason": String, "jd": int, "until_jd": int, "retest": bool}` (prázdné = platný).
- API (stávající signatury nesmí přestat fungovat – drony / paramotor / UL volají `has(pid, kind)` a `grant(pid, kind, no)`):
  - `has(pid, kind, sub := "") -> bool` – platný (ne odebraný, ne prošlý) a pokud `sub != ""`, má i skupinu.
  - `grant(pid, kind, no := "", sub := "", valid_until := -1)` – druhé volání se skupinou skupinu **přidá** (dnes `grant` končí
    při existujícím druhu → uprav).
  - `revoke(pid, kind, reason, until_jd := -1, retest := false)`, `restore(pid, kind)` (po přezkoušení / rozhodnutí úřadu),
    `is_revoked(pid, kind) -> Dictionary`, `subs(pid, kind) -> Array`, `list(pid) -> Array[Dictionary]` (pro panel P a deník).
  - `describe(pid)` ukáže i skupiny a stav („odebráno – nutné přezkoušení“).
- `KINDS` doplň: `ridicsky` („Řidičský průkaz“, „obecní úřad obce s rozšířenou působností (smyšlený)“), `kaceni`, `zbrojni`,
  `lovecky_listek`, `povolenka_lov`, `rybarsky_listek`, `povolenka_rybolov` (vydavatelé obecně, bez reálných názvů úřadů).
- `from_dict` načte nová pole s výchozími hodnotami (`d.get(...)`), starý tvar `{"no","jd"}` zůstane platný.
- **Výchozí doklady:**
  - **Nová hra:** v `Permits.add_player(pid)` (volá ho `World` při přidání hráče) udělit `ridicsky` se skupinami B + AM.
  - **Starý save:** `SaveGame` volá `from_dict(id, d.get("permits", {}))` i u starých pozic (prázdný slovník) – ten
    `add_player` grant přepíše. Proto ve `from_dict`: když v datech **chybí klíč `ridicsky`** → udělit B + AM + **A**
    (aby se nerozbila hra s motorkou) a zapsat do logu. Odebraný řidičák musí zůstat uložený jako položka s `revoked`,
    ne smazaný – jinak by ho tahle migrace po načtení vrátila.

### 3.2 Skupiny (zjednodušeně podle 361/2000 Sb. – nová sekce `ridicska_opravneni` v `data/zakon.json`, u každé „ověřit“)
| Skupina | Vozidla ve hře | Min. věk (jen info) |
|---|---|---|
| AM | Pionýrek 50 (moped) | 15 |
| A1 | Včelka 125 | 16 |
| A2 | Javor 250, Armádka 750 (do 35 kW) | 18 |
| A | Krosák 1000 | 24 (nebo 2 roky A2) |
| B | osobní auta, dodávky, pickup | 18 |
| T | Traktůrek | 17 |
Zjednodušení: A zahrnuje A2 a A1, A2 zahrnuje A1, B zahrnuje AM (tabulka `zahrnuje` v datech).
- `World.license_check(id, car) -> {ok, group, reason}`: skupina z `car.model.spec.skupina_rp` (prázdná = kolo → ok),
  oprávnění `permits.has(id, "ridicsky", group)` (vč. `zahrnuje`), zákaz `police.license_ok`, odebrání.
- `enter_car` → při chybějící skupině hláška „Na tohle nemáš řidičák (skupina A2)“ a **jde to**; jízda bez oprávnění se
  zjistí při kontrole (3.4). Nový řádek `rizeni_bez_opravneni` v `zakon.json` (361/2000 Sb. § 125c odst. 1 písm. e) –
  přestupek; opakovaně do 2 let trestný čin § 337 TZ – „ověřit“), s poli `nazev`, `drb`, `karma`, `zakon`, `par`,
  `pokuta`, `body`, `misto`, `trestny_cin`, `poznamka` (vzor ostatních řádků).

### 3.3 Autoškola
- Místo: nabídka na úřadě „Autoškola Volant (smyšlená)“ (`Place` úřad, úřední dny už platí – `Place.WEEK_HOURS["urad"]`),
  nebo vlastní `Place` – rozhodni podle toho, co je méně kódu; instruktor NPC.
- Stav kurzu ulož po vzoru létací školy paramotoru (`World.pg_*`, `PG_TRAIN_FLIGHTS`): zaplaceno, teorie, počet jízd.
- Kurz skupiny (ceny orientačně, v datech): A1 8 900 Kč, A2 9 900 Kč, A 7 900 Kč, T 6 900 Kč (AM a B hráč má):
  1. **teorie** – eTest na PC: vytvoř `data/testy/autoskola.json` (≥ 25 vlastních otázek – **ne** oficiální testové otázky,
     `pocet: 20`, `prah_pct: 85`, `zdroj` + „ověřit aktuální znění“), doplň cestu v `Computer.TESTS["autoskola"]`,
     a v `record_test` (vzor `drony` / `paramotor`) zavolej `World.driving_theory_passed(pid)`.
  2. **jízdy s instruktorem** – 3 jízdy: trasa po obci s kontrolními body (vzor kompasu / cílů z `Jobs`/`Quests`),
     instruktor mluví „vysílačkou“ jako u paramotoru (auta nemají místo spolujezdce – viditelný spolujezdec je M5.11;
     když chceš postavu vedle řidiče, vzor `Trike._pax_vis`). Chyby: > 50 km/h v obci, srážka, promile > 0, nezastavení
     na STOP (ověř grepem `znack|sign` v `prop_models.gd`, jestli značky stojí ve světě; když ne, kontrola jen rychlosti a srážek).
  3. **zkouška** = jízda + komisař, 2 hrubé chyby = neprospěl, opakování za poplatek.
- Úspěch → `permits.grant(pid, "ridicsky", "", skupina)`, XP `rizeni` 100 (`Skills.SKILLS`), pověst +1.

### 3.4 Kontrola a důsledky
- `police.gd`: při zastavení (`_stopping`) zkontroluj `World.license_check` pro vozidlo hráče; bez skupiny →
  `commit_offense(id, "rizeni_bez_opravneni")`, auto odtaženo domů (`World.move_player_car_to(id, "domov")`), hláška.
  `_plan` ať vrací „ticket“ i pro chybějící skupinu (dnes jen promile / zákaz / přestupek).
- **12 bodů:** `Law.commit` vrací `points_ban`; v `World.commit_offense` při `points_ban` zavolej
  `permits.revoke(id, "ridicsky", "12 bodů", <konec zákazu>, true)`. Po uplynutí zákazu je řidičák pořád neplatný,
  dokud hráč nesloží **přezkoušení** v autoškole (teorie + jízda, poplatek). V M4.1 přezkoušení rovnou zavolá `restore`;
  M4.2 mezi to vloží žádost na úřadě (zapiš do logu jako háček).
- `Jobs.can_apply`: `pozadavky.ridicak` → `permits.has(pid, "ridicsky", rid)` **a** `license_ok` (text kontroly beze změny formátu).

### 3.5 Panel dokladů – klávesa **P**
- Nová akce `documents` v `project.godot` (`physical_keycode` 80), obsluha v `local_client.gd` (vzor `wardrobe` / `skills`),
  panel v `hud.gd`: kartičky z `permits.list(pid)` – řidičák (skupiny, datum, stav, body z `Law` `x / 12`, zákaz do),
  drony, paramotor, UL, a prázdné šablony budoucích dokladů jako „nemáš“. Esc / P zavře. Neotvírat při jiném menu / mapě.
- Oddíl „Doklady“ i v deníku J (`Hud._journal_bbcode()`), F1 nápověda, README → Ovládání, registr kláves v `00_SPOLECNE.md`
  (P z „rezervováno“ do „obsazeno“).

## 4. Minimum
Rozšířený `Permits` (sub, revoke/restore, list, migrace starého save), skupiny vozidel + `rizeni_bez_opravneni` při policejní
kontrole, panel P, eTest `autoskola.json` + kurz aspoň s teorií a 1 jízdou. Zbytek autoškoly do otevřených bodů.

## 5. Hotovo, když
- P ukazuje doklady se skupinami; vozidla vyžadují skupinu; jízda bez ní je přestupek při kontrole; autoškola udělí
  skupinu; 12 bodů → „odebráno – nutné přezkoušení“; drony / paramotor / UL fungují beze změny; vše se ukládá.

## 6. Návrh checklistu ručních testů
1. Nová hra → P: řidičák B, AM; ostatní doklady „nemáš“.
2. Krosák 1000 / Javor → „Na tohle nemáš řidičák (A / A2)“; jeď → policejní kontrola → přestupek, auto domů.
3. Autoškola → kurz A2 → PC eTest (neprojdi a pak projdi; 20 otázek, odpovědi zamíchané).
4. Jízda s instruktorem: 60 km/h v obci → chyba.
5. Zkouška → P: A2; kontrola policie → v pořádku.
6. Starý save (z doby před M4.1) → P: B, AM, A – motorka bez přestupku; dron / paramotor doklady zůstaly.
7. F2 → cheat 12 bodů (nebo opakované přestupky) → P „odebráno – nutné přezkoušení“; po zákazu přezkoušení → platný.
8. F5/F9 → doklady, skupiny a stav kurzu zůstanou.

## 7. Závěr
README (Systémy → Doklady, Ovládání → P), `data/zakon.json`, `data/testy/autoskola.json`, `00_SPOLECNE.md` (registr kláves,
mapa kódu – `Permits`), VIZE odškrtnout, roadmapa README, PROJECT_LOG, commit „M4.1 Řidičská oprávnění a autoškola: …“,
checklist a čekat.
