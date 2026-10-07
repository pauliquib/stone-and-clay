# M4.7 – Katastr: koupě a prodej domů, bytů, polí, pozemků a lesů

> Roadmapa „Život na vsi“ · **M4 Zákon a společnost** · krok 7/8 (doplněk od uživatele)
> Předpoklady: M1.7 (`Estate`), **M4.2 (úřad, žádosti, lhůty a `Debts` – hypotéka je jen další druh dluhu)**, M3.1 (příjem
> z práce) · doporučeno M1.8 (prohlídka interiéru), M4.4 (přestupek na cizím pozemku)
> Navazují: M7 (majetek zvyšuje vliv v obci, úplatky pozemky, sliby v kampani)
> Stav kódu ověřen po vlně 0 (commit `357f7eb`). Když grep ukáže něco jiného, věř kódu a rozdíl zapiš do logu.

## 0. Než začneš – přečti
1. `prompts/roadmapa/00_SPOLECNE.md`
2. `scripts/estate.gd` (M1.7) – registr budov, `home_of`, `owns_house`, `is_flat`, `set_estate_owner` / `owner_of`,
   `pick_customer_house`, `rent_debt`; `World.apply_home` (~ř. 1109), `World.lot_door` (~1073)
3. `scripts/priroda/fields.gd` – čtení `data/landuse.bin` (`rect()`, `class_at`; třídy 0 nic, 1 orná, 2 louka, 3 sad, 4 zahrádky
   – **les v landuse není**, les = `Fauna.forest_at`), hlavička `tools/landuse.py` (formát, rozsah)
4. `scripts/garden.gd` – pronájem pole na úřadě (M2.4, `RENT_*`, `service`) a `scripts/forestry.gd` – `zone_at` (~ř. 538:
   „own“ = okruh kolem domova / pronajatý plot, „settled“, „forest“, „other“)
5. `scripts/debts.gd` (M4.2) a záznamy M4.2 + M3.4 (počítač – banka, Bazárek) v `PROJECT_LOG.md`
6. `scripts/world.gd` – `obce`, `obec_bounds`, `obec_at` (~ř. 624–670); `scripts/hud.gd` – hranice domácího katastru
   (`meta["boundary"]` z `data/map.json`, ~ř. 1547, 2179)
7. README → „Právní zásady obsahu“ (žádná reálná parcelní čísla ani vlastníci – vše smyšlené)

## 1. Proč
Uživatel chce kupovat a prodávat **domy, byty, pole, pozemky a lesy**. Majetek je cíl i nástroj: vlastní dům = zahrada,
farma, dílna; les = dřevo; pole = úroda nebo pronájem. Zároveň je to cesta k vlivu v obci (M7).

## 2. Co už v kódu je a rozhodnutí
- **Mapa po rozšíření na 5 okolních obcí:** výšková mřížka terénu a `landuse.bin` pokrývají **union** (OSM bbox
  `osm_raw_union.json` + rezerva, rastr 4 m zarovnaný s mřížkou z `map.json`). Okolní obce (`World.obce` z `data/obce.json`)
  mají hranice, silnice a budovy jen jako data pro mapu / okolí, ne jako hratelnou obec.
- **Rozhodnutí uživatele: nemovitosti jen v domácím katastru.** Hranice domácího katastru = polygon `meta.boundary`
  v `data/map.json` (kreslí ho mapa M; `World` na něj zatím funkci nemá). Přidej `World.in_home_cadastre(pos) -> bool`
  (`Geometry2D.is_point_in_polygon`, keš polygonu; levný předtest obdélníkem) a parcely / inzeráty generuj jen uvnitř.
  Ověř taky, jestli `Estate` čísluje jen budovy domácí obce (zdroj `BuildingDetails` / `buildings.json`) – budovy
  okolních obcí se nesmí objevit v katastru ani v inzerátech.
- Vlastnictví dnes: `Estate.set_estate_owner(id, who)` / `owner_of(id)` (budovy), domov = vlastnictví / nájem bytu.
  Pozemky (pole, les) vlastnictví nemají – „own“ v `Forestry.zone_at` je jen okruh kolem domova nebo pronajatý plot.

## 3. Co udělat
- **Parcely:** rozdělit plochy domácího katastru na smyšlené parcely (mřížka / Voronoi podél cest, 0,2–3 ha) podle
  `landuse` (orná, louka, sad, zahrada) a lesa (`Fauna.forest_at`), stavební = okolí budov z `Estate`. Každá: smyšlené
  číslo parcely, druh, výměra, cena (Kč/m² podle druhu a polohy – tabulka nahoře), vlastník (obec, vesničan z `Characters`,
  „někdo z města“, hráč). Deterministicky ze seedu (stejné rozdělení po každém spuštění), ukládá se jen vlastnictví a změny.
  `World.parcel_at(pos)` → parcela (rastrová mapa id parcel, ne polygon test pro každou).
- **Katastr na úřadě a v počítači:** nabídka „Na prodej“ (inzeráty se mění po týdnech), detail (mapa M zvýrazní parcelu / dům),
  koupě = kupní smlouva → návrh na vklad → **lhůta 20 herních dní** (zjednodušeně; zkrácení za poplatek), správní poplatek
  za vklad (daň z nabytí nemovitosti se neplatí – zrušena; „ověřit“). Prodej: hráč nabídne, kupec se najde za dny podle
  ceny (drahé = déle), nebo prodej obci / sousedovi hned za nižší cenu.
- **Byty a domy:** koupě domu → stane se domovem (volba, `World.apply_home`), starý byt jde vypovědět; dům lze pronajmout
  (měsíční příjem, nájemník = vesničan). Prohlídka domu před koupí (M1.8 – interiér se odemkne).
- **Hypotéka (jednoduše):** banka v počítači („Venkovská spořitelna“ – smyšlená): akontace 20 %, měsíční splátka =
  **`Debts.add(pid, "hypoteka", …)` každý měsíc** (žádný vlastní upomínkový / exekuční kód – použij M4.2), po 3 nezaplacených
  splátkách exekuce: nemovitost zpět za 70 % (rozšíř `Debts` o „zástavu“ – `ref` na parcelu / dům).
- **Důsledky vlastnictví:** `Forestry.zone_at` vrací „own“ i na **vlastních parcelách** (les, zahrada); sklizeň z vlastního
  pole; chov jen na vlastním / pronajatém pozemku; cizí pozemek = varování, poškození = přestupek (M4.4 `vstup_na_cizi_pozemek`).
- **Cedule „Na prodej“** u domů a na polích, drby v rozhovoru (`DialogData` – téma „reality“ / rady HOWTO).
- **Uložení:** vlastnictví parcel a budov, rozjednané vklady, hypotéky (v `Debts`), nájemníci.

## 4. Minimum
`in_home_cadastre`, parcely + katastr na úřadě, koupě / prodej domu a pole se lhůtou vkladu, domov přes koupený dům,
kácení a sklizeň podle vlastnictví. Hypotéka a pronájem domu můžou do otevřených bodů.

## 5. Hotovo, když
- Hráč si koupí dům, po lhůtě se do něj přestěhuje (postel, zahrada, farma), a pole / les s dopadem na řemesla.
- Prodej funguje (kupec za dny nebo obec hned); hypotéka a pronájem mají peněžní tok přes `Debts`.
- Žádná parcela ani inzerát neleží mimo domácí katastr.

## 6. Návrh checklistu ručních testů
1. Úřad → Katastr → „Na prodej“ → vybrat dům → mapa zvýrazní dům (v domácí obci).
2. Koupit (cheat peníze F2) → smlouva, vklad za 20 dní (přeskočit čas) → dům je hráčův.
3. „Nastavit jako domov“ → spaní a úkoly „domů“ vedou do nového domu, cedulka má číslo.
4. Koupit les → kácení tam bez přestupku; v cizím lese přestupek jako dřív.
5. Prodat pole obci → peníze hned, pole zmizí z majetku.
6. Hypotéka → splátka po měsíci v dluzích; 3× nezaplatit → upomínky a exekuce.
7. F2 → Teleport do okolní obce → mapa M tam žádné parcely na prodej neukazuje.
8. Rozhovor (T): „prodává se tu něco?“ → vesničan zmíní inzerát.
9. Uložit / načíst → majetek, lhůty a hypotéka zůstanou.

## 7. Závěr
README, VIZE a roadmapa README odškrtnout, PROJECT_LOG, commit „M4.7 Katastr a nemovitosti: …“, checklist a čekat.
