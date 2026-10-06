# M4.4 – Další přestupky a svědci; obecní vyhlášky (pálení, sucho, hluk)

> Roadmapa „Život na vsi“ · **M4 Zákon a společnost** · krok 4/8
> Předpoklady: M0.5, M4.2 (příkazy poštou, žádosti na úřadě, `records.svedci`), M2.1, M2.2, M2.4, M2.6
> Navazují: M4.6 (hajný a stráže používají `witness_check` a nenahlášené činy), M4.8 (návykové látky), M7.3 (úkol
> „pálení větví jako opékání“), M5.3 (hasiči – ohlášené pálení)
> Stav kódu ověřen po vlně 0 (commit `357f7eb`). Když grep ukáže něco jiného, věř kódu a rozdíl zapiš do logu.
> **Velký krok** – část A je jádro, část B (vyhlášky) lze při nedostatku kontextu dokončit v druhé session
> („pokračuj podle otevřených bodů“).

## 0. Než začneš – přečti
1. `prompts/roadmapa/00_SPOLECNE.md`
2. `data/zakon.json` (seznam klíčů: `grep -o '^  "[a-z_0-9]*":' data/zakon.json`) a `scripts/law.gd`, `World.commit_offense`
3. `scripts/forestry.gd` – `witness_near` (~ř. 554), `offenses_for`, `_check_law`, `unreported`, `pending_offenses`,
   `commit_pending` (~ř. 600–640), `zone_at`
4. Kdo dnes volá svědky: `scripts/weapons.gd` (`_witness`, ~ř. 734), `scripts/cargo.gd` (`cargo_seen`, ~ř. 1036),
   `scripts/fire_manager.gd` (`WITNESS_R`, ~ř. 258), `World.drone_witnessed` (~ř. 3801), `Reputation._witnesses(r)` (~ř. 337)
5. `scripts/radio.gd` – model hluku a rozzlobení sousedů (`loudness`, `_consequences`, ~ř. 590–680) – **vzor pro hluk**
6. `scripts/fire_manager.gd` (hlavička, `KINDLING_*`, `opekat`), `scripts/priroda/weather.gd` (`rain_recent`, `temp`),
   `scripts/garden.gd` (hlavička – sud s kohoutkem, studna Fáze 8, `zalevat`), `scripts/prace/udrzba.gd` (zóny trávy, `posekat`)
7. `scripts/computer.gd` – `NOTICE_BOARD` (úřední deska, háček `M4.4`), `GOSSIP_EVENTS`
8. `scripts/persona.gd` (`profile.trait`, `get_friendship`), `scripts/villager.gd` (`BT_VILLAGERS` = 5)

## 1. Proč
Dosavadní kroky nechaly v zákonech mezery a háčky. Tady je sjednotíme, aby všechny činnosti měly konzistentní právní
důsledky a **systém svědků** fungoval všude stejně. K tomu obecní vyhlášky, které dělají vesnický život vesnickým:
pálení větví, sucho, nedělní klid.

## 2. Co už v kódu je
- **`World.witness_check` neexistuje.** Svědky dnes řeší `Forestry.witness_near(pos, r) -> bool` (vesničané, obsluha míst,
  policejní hlídka; používají ho kácení, zbraně, náklad, oheň), zvlášť `World.drone_witnessed` a `Reputation._witnesses(r) -> int`.
- **Nenahlášené činy** nejsou `Law.hidden`, ale `Forestry.unreported[id]` (`{kind, offenses, pos, t, value, severity, tool,
  discover_p}`), API `pending_offenses(id)` / `commit_pending(id, idx)`; ukládá se v klíči `forestry`.
- V katalogu už jsou `tyrani_zvirat` (uděluje `farm.gd`), `ruseni_nocniho_klidu` (uděluje jen `radio.gd`). **`ujeti_policii`,
  `nehoda_skoda`, `srazeni_chodce` v katalogu jsou, ale nikdo je neuděluje** (`police.report_crash`, `report_hit_person` jen
  spustí honičku).
- Řádky katalogu mají po vlně 0 povinná pole **`drb`** (text pro drby na PC – `Computer`) a **`karma`** (`Reputation`) –
  každý nový řádek je musí mít, plus `nazev`, `zakon`, `par`, `pokuta`, `body`, `misto`, `trestny_cin`, `poznamka` („ověřit“).
- Povolení ke kácení = `World.has_permit(id, "kaceni", pos)` (lesní dělník na směně má výjimku přes `les.work_permit`).
  M4.1 přidal `kaceni` do `Permits.KINDS`.
- **Vlhkost dřeva / větví ve hře není.** Odvětvení dává předmět `vetve` („Větve (klestí)“), oheň potřebuje `KINDLING_*`.
- **Ukazatel sucha ve `Weather` není** – jen `rain_recent` (0..1, klesá ~0,5 za den – pro hřiby). Zahrada (Fáze 8) má
  **sud s kohoutkem** (dešťová voda, cíl `kohoutek`) a **studnu** (`naplnit_studna`) – kohoutek z vodovodu neexistuje.
- Sekačka na trávu neexistuje; obecní údržba (M3.2) seká **kosou** zóny trávy (`udrzba_trava`, `posekat`).

## 3. Část A – svědci a katalog
### 3.1 Jednotný systém svědků `World.witness_check(id, pos, kind, see_r, hear_r := 0.0) -> Array`
- Vrátí `[{node, name, persona, sees: bool, hears: bool, reports: bool}]` – vesničané, obsluha míst, myslivec, policie,
  později hajný / stráže (M4.6 je přidá registrací `World.add_witness_source(Callable)`).
- **Vidí:** vzdálenost ≤ `see_r` × (den 1,0 / šero 0,5 / noc 0,25 – `Clock`), mlha `Weather.fog`, zorný kužel (NPC dívá
  se zhruba tam), raycast na vrstvu 1 (zdi). **Slyší:** ≤ `hear_r` (výstřel, motorová pila, sekačka, rádio) bez kuželu.
  Výkon: NPC jen v bublině kolem `pos`, raycast nejvýš pro pár nejbližších.
- **Nahlásí?** podle povahy (`Persona.profile.trait` – `prisny` skoro vždy, `drbna` roznese drb bez úředního záznamu,
  přítel s přátelstvím ≥ 60 skoro nikdy; vzor pravděpodobností `Weapons.CALL_P`) a závažnosti.
- Nahlášení → `commit_offense` se zpožděním (policie přijede / příkaz poštou M4.2), jméno svědka do `records[].svedci`.
- Nikdo → **nenahlášený čin**: přesuň registr z `Forestry.unreported` do společného `World.unreported` (nebo `LawRecord.hidden`)
  s API `add_unreported(id, entry)`, `pending_offenses(id)`, `commit_pending(id, idx)`; `Forestry` ať volá společné API
  (staré funkce ponech jako tenké obaly), migrace z klíče `forestry` při načtení.
- **Převeď** na `witness_check`: `Forestry.witness_near` (obal: `not witness_check(...).filter(reports).is_empty()`),
  `Weapons._witness`, `cargo_seen`, `FireManager`, `drone_witnessed`, `Reputation._witnesses`.

### 3.2 Povolení ke kácení
- Úřad (rámec z M4.2) → „Žádost o povolení ke kácení“: hráč musí být u stromu a zvolit ho (akce „označit strom“) → žádost,
  poplatek, vyřízení za 7–30 herních dní (poštou), strom dostane značku; `permits.grant(pid, "kaceni", …)` **s vazbou na
  konkrétní strom** (pole v položce dokladu – id / pozice stromů), `has_permit(id, "kaceni", pos)` pak kontroluje i pozici.
  Platí do konce vegetačního klidu (X–III); v hnízdní době (IV–VII) zjednodušeně nelze.
- Strom na vlastní zahradě s obvodem kmene do 80 cm ve 130 cm → netřeba; ovocné stromy u domu → netřeba (zjednodušení
  vyhl. 189/2013 Sb. – „ověřit“). Obvod z poloměru stromu (`Forestry`).

### 3.3 Nové a oživené řádky katalogu (každý s `drb`, `karma`, „ověřit“)
- **Oživit** (nikdo je neuděluje): `ujeti_policii` (konec honičky útěkem – `police._end_chase`, poznaná SPZ → příkaz),
  `nehoda_skoda` (`report_crash` – svědek / policie), `srazeni_chodce` (`report_hit_person`).
- **Nové:** `kradez_uroda` (sklizeň na cizím poli / zahradě), `vstup_na_cizi_pozemek` (noc, cizí zahrada – drobnost),
  `prodej_masa_bez_povoleni` (M2.6), `znecisteni_vody` (volitelné), `jizda_na_koni_opily` (ověř, zda už není),
  `chuze_opily_po_silnici` (jen svědek policista), `vytrznictvi` (rvačka – M5.5), `ruseni_nocniho_klidu` rozšířit na
  motorovou pilu, střelbu, hlasitou hudbu z auta.
- Kontrola konzistence celého `zakon.json` (všechna pole); deník J ukazuje u záznamu „kdo tě viděl“.

## 4. Část B – obecní vyhlášky (úřední deska `Computer.NOTICE_BOARD`)
Obecně závazné vyhlášky obce (OZV) jako **data**: nová sekce `vyhlasky` v `data/zakon.json` (id, název, text pro desku,
platnost – trvale / od–do / podmínka, přestupek `poruseni_vyhlasky_obce` – 251/2016 Sb. § 4 odst. 2, „ověřit“).
Úřední deska na PC zobrazí platné vyhlášky dynamicky (dnes je `NOTICE_BOARD` pevné pole – rozšiř o generované položky),
vyhlášení / zrušení přijde i poštou a do drbů.

### 4.1 Pálení větví a táborák
- **Suché vs. čerstvé:** zaveď vlhkost větví. Návrh: odvětvení dává `vetve_cerstve`; na **hromadě klestí** (nový objekt ve
  světě – „Složit větve na hromadu“, ukládá se) větve schnou podle dnů a počasí (`rain_recent`, teplota) → po ~30 dnech suché;
  z hromady jde odebrat `vetve` (suché). `KINDLING_*` dál bere jen `vetve` (suché). Starý save: existující `vetve` = suché.
- **Pálení hromady** (zapálit hromadu klestí): legální jen **suché** rostlinné zbytky (201/2012 Sb. o ochraně ovzduší –
  zjednodušeně, „ověřit“), mimo platnou **vyhlášku o zákazu pálení** a ne do 50 m od lesa (`ohen_u_lesa` už je).
  Mokré / čerstvé → hustý kouř (viditelný z dálky, sousedé se zlobí jako u rádia) → `paleni_mokreho_odpadu` (nový řádek).
  Hromada nad určitou velikost → povinnost **ohlásit pálení** hasičům (PC formulář, zjednodušeně, „ověřit“) – neohlášené
  pálení, které někdo nahlásí → výjezd hasičů (háček M5.3) + přestupek.
- **Vyhláška o zákazu pálení** (např. duben–září nebo celoročně v obci – vyber, ulož do dat): pálení větví zakázáno.
- **Legální táborák** na špekáčky / grilování (ohniště z M2.2, akce `opekat`) **není** pálení odpadu: povolený i za
  vyhlášky (mimo sucho, viz 4.2). Rozliší se **velikostí ohně** (počet přiložených větví / polen – `FireManager`) a tím,
  jestli se opéká. Velký oheň s hromadou klestí „pod záminkou špekáčků“ = riziko, že svědek pozná pálení
  (pravděpodobnost podle velikosti a kouře) – tohle využije úkol v M7.3.

### 4.2 Sucho
- `Weather.drought` 0..1 (nový stav, ukládá se): roste za dny bez deště a teplem, klesá deštěm (nepoužívej jen
  `rain_recent` – ten je na dny, sucho je na týdny). Ladění nahoře v `weather.gd`. Projev: zahrada vadne rychleji, sud
  s dešťovkou se nedoplňuje, požár trávy (`GrassFire`) se šíří snáz, NPC o suchu mluví (`dialog_themes.gd`).
- Při `drought` nad prahem obec vyhlásí **zákaz zalévání zahrad a napouštění bazénů z vodovodu** (a zákaz rozdělávání
  ohňů v přírodě – i táborák mimo vlastní pozemek). Zruší ho po deštích.
- **Vodovodní kohoutek:** přidej k domovu (byt i dům) zdroj „voda z vodovodu“ (`naplnit_vodovod`); zalévání z něj za
  vyhlášky = `poruseni_vyhlasky_obce` (svědek soused). **Studna** (usedlost, Fáze 8) a sud s dešťovkou vyhláška
  neomezuje – kdo má studnu, řešit nemusí. Bazény hráč nemá – vyhláška platí obecně (drby o sousedovi, co napouštěl bazén).

### 4.3 Hluk a nedělní klid
- **Společný model hluku:** vytáhni z `radio.gd` rozzlobení sousedů do sdílené funkce (`World.noise(pos, loud, kind)` →
  sousedé v dosahu, `anger`, stížnost, pověst, v noci policie) a použij ji pro rádio, motorovou pilu, sekačku, střelbu,
  hudbu z auta (M5.9).
- **Vyhláška o nedělním klidu:** hlučné činnosti (sekačka, motorová pila, křovinořez) v neděli a o svátcích zakázány
  (např. mimo 10–12 h – vyber a dej do dat, „ověřit“ – OZV obcí se liší); noční klid 22–6 h ze zákona.
- **Sekání trávy:** nový nástroj **sekačka** (motorová, prodej v Potravinách nebo M5.1 Stavebniny) – seká trávu na vlastní
  zahradě a v zónách údržby (M3.2) rychleji než kosa, je hlučná. V neděli → sousedé, vyhláška.
- **Atmosféra:** NPC sekající trávu – o víkendu dopoledne u náhodných domů zvuk sekačky (procedurální, `sfx.gd`) a postava
  jezdící po zahradě (nemusí být BT vesničan – stačí jednoduchá postava / jen zvuk ze zahrady); občas soused poruší
  nedělní klid a ostatní NPC si stěžují v drbech.

## 5. Minimum
Část A celá (`witness_check` + převod všech volání + společné nenahlášené činy, povolení ke kácení, oživené a nové řádky)
a z části B pálení větví (suché / čerstvé, vyhláška, táborák). Sucho a hluk do otevřených bodů s přesným popisem.

## 6. Hotovo, když
- Všechny činnosti používají `witness_check`; povolení ke kácení jde získat a respektuje se; nové přestupky fungují;
  svědci se chovají podle povahy a přátelství; vyhlášky jsou na úřední desce a mají důsledky; sucho a nedělní klid
  ovlivňují hru.

## 7. Návrh checklistu ručních testů
1. Kácení v lese před přísným vesničanem → nahlásí; před kamarádem (přátelství ≥ 60) → nenahlásí.
2. Kácení v noci bez svědků → deník nic, F2 / hajný (M4.6) později odhalí.
3. Úřad → žádost o povolení → za pár dní dopis → pokácet označený strom legálně; jiný strom = přestupek.
4. Ovocný strom na vlastní zahradě → bez povolení OK.
5. Sklizeň na cizí zahradě → krádež úrody; srážka auta před policií → `nehoda_skoda`; útěk policii → `ujeti_policii`.
6. Čerstvé větve na hromadu → za 30 dní (F2 → Datum) suché; zapálit čerstvé → kouř, sousedé, přestupek.
7. Za vyhlášky o zákazu pálení: hromada → přestupek; táborák se špekáčky → v pořádku.
8. F2 → Počasí: dlouhé sucho → vyhláška na PC; zalévání z vodovodu → soused nahlásí; ze studny → OK.
9. Sekačka v neděli odpoledne → stížnost, přestupek; ve středu → nic.
10. F5/F9 → hromady klestí, sucho, vyhlášky, nenahlášené činy zůstanou (i ze starého save s `forestry.unreported`).

## 8. Závěr
README, `data/zakon.json`, `00_SPOLECNE.md` (mapa kódu – `witness_check`), VIZE odškrtnout, roadmapa README, PROJECT_LOG,
commit „M4.4 Další přestupky, svědci a vyhlášky: …“, checklist a čekat.
