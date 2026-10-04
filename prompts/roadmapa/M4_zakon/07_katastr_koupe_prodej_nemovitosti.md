# M4.7 – Katastr: koupě a prodej domů, bytů, polí, pozemků a lesů

> Roadmapa „Život na vsi“ · **M4 Zákon a společnost** · krok 7/7 (doplněk od uživatele)
> Předpoklady: M1.7 (`Estate`), M4.2 (správní řízení na úřadě), M3.1 (příjem z práce) · doporučeno M1.8
> Navazují: M7 (majetek zvyšuje vliv v obci, úplatky pozemky, sliby v kampani)

## 0. Než začneš – přečti
1. `prompts/roadmapa/00_SPOLECNE.md`
2. `scripts/estate.gd` (M1.7) – budovy, čísla popisná, domov
3. `data/landuse.bin` a jeho čtení (`scripts/surface_map.gd` / `map_loader.gd`) – pole, louky, sady, les
4. `scripts/garden.gd` – pronájem pole na úřadě (M2.4) a `scripts/forestry.gd` – kácení jen na vlastním
5. Záznamy M4.2 (úřad, žádosti, lhůty) a M3.4 (počítač – e-shop / portál) v `PROJECT_LOG.md`
6. README → „Právní zásady obsahu“ (žádná reálná parcelní čísla ani vlastníci – vše smyšlené)

## 1. Proč
Uživatel chce kupovat a prodávat **domy, byty, pole, pozemky a lesy**. Majetek je cíl i nástroj: vlastní dům =
zahrada, farma, dílna; les = dřevo; pole = úroda nebo pronájem. Zároveň je to cesta k vlivu v obci (M7).

## 2. Co udělat
- **Parcely:** rozdělit `landuse` na smyšlené parcely (mřížka / Voronoi podél cest, 0,2–3 ha), každá s číslem
  parcely (smyšlené), druhem (orná, louka, zahrada, les, stavební), výměrou, cenou (Kč/m² podle druhu a polohy),
  vlastníkem (obec, vesničan z `Characters`, „někdo z města“, hráč).
- **Katastr na úřadě a v počítači:** nabídka „Na prodej“ (inzeráty se mění po týdnech), detail (mapa M zvýrazní
  parcelu / dům), koupě = kupní smlouva → návrh na vklad → **lhůta 20 herních dní** (zjednodušeně; zkrácení za
  poplatek), správní poplatek za vklad (daň z nabytí nemovitosti se neplatí – zrušena). Prodej: hráč nabídne, kupec se
  najde za dny podle ceny (drahé = déle), nebo prodej obci / sousedovi hned za nižší cenu.
- **Byty a domy:** koupě domu → stane se domovem (volba), starý byt jde vypovědět; dům lze pronajmout (měsíční
  příjem, nájemník = vesničan). Prohlídka domu před koupí (M1.8 – interiér se odemkne).
- **Hypotéka (jednoduše):** banka v počítači: akontace 20 %, splátka měsíčně, při 3 nezaplacených upomínka →
  exekuce (majetek zpět za 70 %). Bez skutečných bank – smyšlené „Venkovská spořitelna“.
- **Důsledky vlastnictví:** kácet smíš na **vlastním** lese / zahradě (napojit `forestry`), sklizeň z vlastního
  pole, chov jen na vlastním / pronajatém pozemku; cizí pozemek = varování, poškození = přestupek (M4.4).
- **Cedule „Na prodej“** u domů a na polích, drby v rozhovoru (`DialogData` – nové téma „reality“ / rady HOWTO).
- **Uložení:** vlastnictví, rozjednané vklady, hypotéky, nájemníci.

## 3. Minimum
Parcely + katastr na úřadě, koupě / prodej domu a pole se lhůtou vkladu, domov přes koupený dům,
kácení a sklizeň podle vlastnictví.

## 4. Hotovo, když
- Hráč si koupí dům, po lhůtě se do něj přestěhuje (postel, zahrada, farma), a pole / les s dopadem na řemesla.
- Prodej funguje (kupec za dny nebo obec hned); hypotéka a pronájem mají peněžní tok.

## 5. Návrh checklistu ručních testů
1. Úřad → Katastr → „Na prodej“ → vybrat dům → mapa zvýrazní dům.
2. Koupit (cheat peníze F2) → smlouva, vklad za 20 dní (přeskočit čas) → dům je hráčův.
3. „Nastavit jako domov“ → spaní a úkoly „domů“ vedou do nového domu, cedulka má číslo.
4. Koupit les → kácení tam bez přestupku; v cizím lese přestupek jako dřív.
5. Prodat pole obci → peníze hned, pole zmizí z majetku.
6. Hypotéka → splátka po měsíci; 3× nezaplatit → upomínky a exekuce.
7. Rozhovor (T): „prodává se tu něco?“ → vesničan zmíní inzerát.
8. Uložit / načíst → majetek, lhůty a hypotéka zůstanou.

## 6. Závěr
README, VIZE a roadmapa README odškrtnout, PROJECT_LOG, deník AI, commit „M4.7 Katastr a nemovitosti: …“,
checklist a čekat.
