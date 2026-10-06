# M4.8 – Návykové látky: tabák, konopí, lysohlávky (obsah pro dospělé)

> Roadmapa „Život na vsi“ · **M4 Zákon a společnost** · krok 8/8 (doplněk od uživatele, 6. 10. 2026)
> Předpoklady: M2.4 (zahrada – `Garden.CROPS`), **M4.4 (`witness_check`, nenahlášené činy, model hluku / kouře)**,
> M4.2–M4.3 (správní řízení, soud – důsledky), M0.5 (zákon jako data)
> Navazují: M7.2 (kompromitující drby v kampani), V2
> Stav kódu ověřen po vlně 0 (commit `357f7eb`). Když grep ukáže něco jiného, věř kódu a rozdíl zapiš do logu.

## 0. Než začneš – přečti
1. `prompts/roadmapa/00_SPOLECNE.md` (kap. 3 – zákony ČR zjednodušeně, „ověřit aktuální znění“)
2. `scripts/body_state.gd` (366 ř. – konstanty nahoře, `smoke()` ~ř. 222, nikotin / chuť / závislost, `skip_hours`)
3. `scripts/drunk_fx.gd` (50 ř.) + `shaders/drunk.gdshader` (uniformy `drunk`, `double_vision`, `blur`, `tunnel`, `nausea`…)
4. `scripts/player.gd` – `use_item` (~ř. 499, typ `smoke`), třes obrazu (`shake_enabled`); `scripts/game_settings.gd`
   (`withdrawal_shake` – vzor nastavení, klíč v `nastaveni.cfg`), `scripts/pause_menu.gd` (~ř. 322 – zaškrtávátko)
5. `scripts/items_db.gd` – oddíl tabák (`cigarety`, typ `smoke`), `scripts/consumables.gd`
6. `scripts/garden.gd` – hlavička a `CROPS` (~ř. 81), `sow_months`, sklizeň
7. `scripts/world.gd` – sezónní předměty (tabulka nahoře `"hrib": {"from", "to", "regrow"}`, ~ř. 32; `refresh_season_items`)
8. `scripts/police.gd` – `breath_test` (~ř. 625), `_plan`; `data/zakon.json` (formát řádku s `drb`, `karma`)
9. `scripts/place.gd` – `OFFERS["obchod"]` (cigarety se prodávají **jen v Potravinách** – rozhodnutí uživatele, vlna 0 A3-01)

## 1. Proč
Uživatel chce pěstování, sušení, zpracování a kouření tabáku a konopí (se stavem po vykouření / snědení) a sběr
a snědení lysohlávek (se stavem). Simulace venkova i se stinnými stránkami – ale **s důsledky, ne jako reklama**.

## 2. Rozhodnutí uživatele (závazná)
- **Celé je za volbou „Obsah pro dospělé“** v Nastavení (Esc → Nastavení), **výchozí vypnuto**. Vypnuto = obsah **ve hře
  není**: žádná semena, rostliny, houby, předměty, dialogy, drby, řádky v nápovědě ani v deníku. Zapnutí se ukládá
  do `nastaveni.cfg` (`GameSettings.adult_content`, vzor `withdrawal_shake`); přepnutí za běhu jen schová / ukáže
  obsah, nic nemaže (předměty v inventáři zůstanou skryté, po zapnutí se vrátí).
- **Hra nenabádá k trestné činnosti:** zákony a důsledky ano, glorifikace ne. Texty věcné, efekty nepříjemné spíš než
  „cool“ (nevolnost, úzkost, zhoršená koordinace), žádné odměny v XP / pověsti za užívání, NPC reagují spíš odmítavě.
  V nápovědě a README doložka: „zjednodušená herní simulace; nejde o návod ani právní radu“.
- **Tabák:** cigarety se prodávají jen v Potravinách (už platí). Vlastní tabák jen pěstováním.
- **Zákony ČR zjednodušeně, každé číslo s „ověřit aktuální znění“.** U konopí se legislativa v letech 2025–2026 měnila –
  **neuváděj konkrétní limity jako fakt**: agent si aktuální stav ověří (WebSearch je pro tenhle účel povolený, zdroj
  zapiš do `PROJECT_LOG.md`) a čísla vloží jen do `data/zakon.json` s polem `poznamka: "ověřit aktuální znění – stav k <datum>"`.
  Když ověření nejde, nech v datech zástupné hodnoty označené „NEOVĚŘENO“ a zapiš otevřený bod. Lysohlávky: držení
  psilocybinu je nelegální (zjednodušeně – přesný § „ověřit“).

## 3. Co udělat
### 3.1 Nastavení a brána obsahu
- `GameSettings.adult_content := false`, zaškrtávátko v `pause_menu.gd` („Obsah pro dospělé (návykové látky)“) s krátkým
  vysvětlením. Jedna statická brána `World.adult_ok() -> bool`; všechny nové věci se registrují jen přes ni
  (`Garden.CROPS` záznamy s klíčem `adult: true`, předměty v `ItemsDB` s `adult: true`, sezónní předměty, dialogová témata).
- `ItemsDB` / inventář / obchody filtrují `adult` předměty při vypnuté volbě.

### 3.2 Pěstování a zpracování (zahrada M2.4)
- Nové plodiny v `Garden.CROPS` (s `adult: true`): **tabák** (sazenice / semena, výsev IV–V, sklizeň listů VIII–IX) a
  **konopí** (semena, IV–V, sklizeň IX–X). Semena: tabák – obchod se zahradními potřebami / Potraviny (sezóna); konopí –
  rozhodni podle ověřeného právního stavu (např. jen technické konopí, nebo jen nález / dar od NPC), zapiš do logu.
- **Sušení:** listy / květy se suší (nový objekt **sušák** v kůlně / na půdě domova nebo pod přístřeškem, N dní podle
  vlhkosti – `Weather`; mokré = plíseň a ztráta). Model sušení může sdílet logiku s hromadou klestí z M4.4 (vlhkost v čase).
- **Zpracování:** tabák → řezaný tabák → ruční cigarety (akce „ubalit“ – papírky z Potravin); konopí → sušené květy →
  „ubalit“ / **jedlá varianta** (pečení – napoj na vaření, pokud je; jinak jednoduchá akce u kamen).
- Pěstování konopí je **vidět** (rostliny na zahradě) → `witness_check` (M4.4): soused / drbna / policie (podle počtu
  rostlin a právního stavu z dat) → přestupek nebo trestný čin (`nedovolene_pestovani` – 40/2009 Sb. § 285 –
  „ověřit“), zabavení rostlin.

### 3.3 Lysohlávky
- Sezónní předmět v lese / na pastvinách (vzor `hrib` v tabulce sezónních předmětů `World`, např. IX–XI, vzácné),
  jen při `adult_ok()`. Vzhled podobný jiným houbám; **riziko záměny** s jedovatou houbou (malá šance otravy – `BodyState`
  nevolnost, zdraví), houbařská znalost (`Skills` – ověř, zda existuje vhodná dovednost; jinak bez).
- Držení = přestupek / trestný čin podle množství (`prechovavani_navykove_latky` – 40/2009 Sb. § 284 – „ověřit“),
  zjistí se při policejní prohlídce (M4.6 prohlídka kufru / kapes, pokud existuje) nebo svědkem.

### 3.4 Stavy po užití (`BodyState`)
- Nové hladiny vedle alkoholu a nikotinu: `thc` (kouření – rychlý nástup, ~2–3 h; snědení – pomalý nástup ~1 h,
  delší a silnější), `psilocybin` (nástup ~30–60 min, ~4–6 h). Odbourávání v `skip_hours` (spánek), ukládání (klíče
  s výchozí hodnotou – vzor `addiction`, který vlna 0 přidala do `SaveGame`).
- Projevy (mírné, laditelné konstanty nahoře v `body_state.gd`):
  - THC: pomalejší reakce (`speed_mult`, zpoždění řízení), hlad (rychlejší úbytek kcal), občas úzkost (zprávy HUD),
    při vyšší dávce nevolnost; řízení pod vlivem = přestupek / trestný čin (361/2000 Sb. § 5 – „ověřit“).
  - Psilocybin: zkreslené vnímání – **jemné** efekty obrazu přes `DrunkFx` (barevný posun, pomalé vlnění – nové uniformy
    v `drunk.gdshader`), zvuky trochu jinak; žádné blikání ani rychlé záblesky (fotosenzitivita).
  - Tabák (vlastní): stejné jako cigarety (`smoke()`), nikotin a závislost už existují (vlna 0 je zmírnila).
- **Efekty obrazu vypínatelné** jako třes: využij nastavení `withdrawal_shake` nebo přidej vlastní „Efekty obrazu
  (opilost, látky)“ – rozhodni a zapiš; vypnuto = jen HUD stav, bez shaderu.
- HUD: stav v přehledu těla (vedle promile) jen věcně („pod vlivem THC – střední“).

### 3.5 Zákon (`data/zakon.json`, nové řádky s `drb`, `karma`, „ověřit“)
`nedovolene_pestovani`, `prechovavani_navykove_latky` (malé / větší množství podle ověřených dat), `rizeni_pod_vlivem_navykove_latky`
(+ policejní **test na drogy** vedle dechovky v `breath_test` – zjednodušeně pozitivní, když je hladina > 0),
`prodej_tabaku_bez_dani` (prodej vlastního tabáku NPC – volitelné, 353/2003 Sb. – „ověřit“). Prodej látek NPC
**neimplementuj** (hra nenabádá – zapiš jako vědomé vynechání).

### 3.6 Reakce okolí
Zápach kouře konopí (svědek v okruhu → drb, pokles přátelství u přísných, `witness_check`), drby na PC (`drb` z řádku
zákona), rodina / zaměstnavatel (M3.1: pod vlivem v práci = napomenutí jako u alkoholu).

## 4. Minimum
Nastavení „Obsah pro dospělé“ (výchozí vypnuto, vypnuto = nic není), tabák (pěstování, sušení, ubalení, kouření),
konopí (pěstování, sušení, kouření, stav THC, svědci a přestupek), lysohlávky (sběr, stav, držení), řádky zákona
s „ověřit“. Jedlá varianta, test na drogy a záměna hub můžou do otevřených bodů.

## 5. Hotovo, když
- S vypnutou volbou ve hře nic z tohoto kroku není (ani ve starém save).
- Se zapnutou volbou jde tabák a konopí vypěstovat, usušit, zpracovat a vykouřit (konopí i sníst), lysohlávky nasbírat
  a sníst; stavy mají mírné, vypínatelné efekty; zákony mají důsledky přes svědky a policii; žádné texty nevybízejí k užívání.

## 6. Návrh checklistu ručních testů
1. Nová hra (výchozí nastavení) → v obchodě ani zahradě nic nového; deník a F1 bez zmínek.
2. Esc → Nastavení → Obsah pro dospělé zapnout → semena tabáku v sezóně (F2 → Datum: duben).
3. Zasadit tabák a konopí → F2 posun času → sklizeň → sušák → ubalit → kouřit: tabák = nikotin, konopí = stav THC.
4. Soused (přísný) u plotu vidí konopí → přestupek / drb podle dat.
5. Řídit pod vlivem THC → policejní kontrola → test → přestupek.
6. Les v září (F2) → lysohlávky → sníst → jemné efekty obrazu; vypnout efekty v Nastavení → jen HUD stav.
7. Vypnout volbu → předměty zmizí z inventáře i světa; znovu zapnout → jsou zpět.
8. F5/F9 → rostliny, sušák, stavy v těle zůstanou; starý save se načte.

## 7. Závěr
README (Systémy → Návykové látky – doložka; Nastavení), `data/zakon.json` (zdroje a data ověření), VIZE odškrtnout,
roadmapa README, PROJECT_LOG (zdroje právního stavu), commit „M4.8 Návykové látky (obsah pro dospělé): …“, checklist a čekat.
