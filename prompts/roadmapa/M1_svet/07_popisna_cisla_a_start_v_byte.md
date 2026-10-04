# M1.7 – Popisná čísla všech domů a start v bytě (konec závislosti na domě hráče)

> Roadmapa „Život na vsi“ · **M1 Živý svět** · krok 7/8 (doplněk od uživatele)
> Předpoklady: M1.4, M1.5 · Navazují: M1.8 (interiéry všech budov), M4.7 (katastr, koupě a prodej), M7 (cesta na starostu)
> **Rozhodnutí od uživatele:** který dům bude bytový (návrh níže) – bez odpovědi zvol algoritmem a napiš do logu.

## 0. Než začneš – přečti
1. `prompts/roadmapa/00_SPOLECNE.md`
2. README → „Právní zásady obsahu“: **žádná reálná čísla popisná** – čísla musí být smyšlená (ne z RÚIAN / ČÚZK).
3. `scripts/building_details.gd` (`building_of_home`, `door_of`, `door_info`, `_prepare` – odkud jsou budovy a dveře)
4. `scripts/world.gd`: `home_door`, `places["domov"]`, `home_chimney_id`, `sleep`, výběh / farma / zahrada u domu
5. `grep -n "221" scripts/*.gd` – dnes ~60 výskytů (world, quests, dialog, dialog_data, garden, bazaar, forestry,
   paddock, farm/pen, cargo, radio, fire_manager, interior, hud, local_client…). Každý projdi.
6. `scripts/save_game.gd` – jak se ukládá domov, zahrada, výběh (kvůli migraci starých uložení)

## 1. Proč
Hra je dnes postavená kolem jednoho domu „domov hráče“: domov, postel, zahrada, výběh, farma, děda, úkoly,
rádio i rozhovory. Uživatel chce: **všechny domy s popisnou značkou**, možnost domy (a pole, pozemky, lesy)
**kupovat a prodávat** (to je M4.7) a **začátek v bytě v bytovém domě**. Tento krok připraví základ:
domov je „nemovitost, kterou hráč vlastní / má pronajatou“, ne pevné číslo.

## 2. Co udělat
- **Registr nemovitostí** `scripts/estate.gd` (`class_name Estate`): každá budova z `building_details` dostane
  stálé `id`, **smyšlené popisné číslo** (deterministicky ze seedu: číslování po ulicích / od středu obce,
  1..N bez děr; *žádné* číslo nesmí pocházet z reálných dat), typ (`rodinny_dum`, `bytovy_dum`, `hospodarska`,
  `verejna` – veřejné budovy z `places`), dveře, střed, půdorys, počet bytů (u bytového domu 4–8).
- **Popisná značka na fasádě:** malá cedulka (modrá / červená smaltovaná *obecného* vzhledu, bez znaku obce)
  vedle dveří, `Label3D` s číslem, LOD jako okna (jen blízko).
- **Domov = vlastnictví:** `Estate.home_of(id)` → {budova, byt (nebo -1)}. Všechno, co dnes míří na
  `places["domov"]` / dům hráče, jde přes něj (dveře, postel, spaní, komín, rádio, interiér domova).
- **Start v bytě:** nový hráč bydlí v **nájemním bytě** v bytovém domě (návrh: největší obytná budova s více
  podlažími v obci; když žádná nesedí, zvol nejbližší velkou budovu k návsi). Interiér domova (M1.4) se
  zmenší na byt 2+1 (kuchyňský kout, postel, skříň, kamna → v bytě radiátor; komín a topení dřevem jen
  v rodinném domě). Nájem z peněz jednou týdně (hák pro M3 – když nejsou peníze, dluh a upomínka).
- **Co bylo „u domu hráče“** (zahrada, výběh, farma, kůň, kolo a motorka dědy, sklad dřeva): přesunout na
  **obecní / pronajaté pozemky** poblíž bytového domu, nebo zpřístupnit až s koupí domu (M4.7). Rozhodni
  podle logiky a zapiš: návrh – kůň a výběh na pronajaté louce, zahrada = zahrádkářská kolonie, farma jen
  s vlastním domem. **Děda Vomáčka** zůstane jako soused na své lavičce u svého domu (nové smyšlené číslo).
- **Texty:** úkoly (`quests.gd`), rozhovory (`dialog.gd`, `dialog_data.gd` – slovo „221“ v `PLACE_WORDS`,
  rady HOWTO), HUD a nápovědy: místo „221“ dosazovat `Estate.home_label(id)` („domů, byt 3 v č. p. 48“).
- **Uložení:** verze save +1; staré uložení → hráč vlastní svůj dosavadní dům (smyšlené číslo nahradí 221),
  zahrada / výběh zůstanou, kde byly (nic se neztratí).

## 3. Minimum
Registr s čísly + cedulky, domov přes `Estate`, start v bytě, žádné „221“ v kódu mimo migraci starých uložení.

## 4. Hotovo, když
- `grep -n "221" scripts/*.gd` najde jen migraci uložení (a případně seed).
- Nová hra začíná v bytě, spaní, převlékání, rádio a úkoly „domů“ vedou do bytu; staré uložení funguje.

## 5. Návrh checklistu ručních testů
1. Nová hra → hráč stojí u bytového domu, na fasádě cedulka s číslem; E u dveří → „Domů (byt N)“.
2. V bytě postel → vyspat do 7:00; skříň → šatník (I).
3. Projít ulici → každý dům má cedulku, čísla se neopakují.
4. Úkol „cigarety pro dědu“ → vede k dědovi na jeho nové číslo.
5. Rozhovor (T): „jak se dostanu domů?“ → směr a vzdálenost k bytu.
6. Načíst staré uložení → hráč má svůj původní dům, zahrada a výběh jsou na místě.
7. Týden herního času → odečte se nájem (nebo upomínka při nedostatku peněz).

## 6. Závěr
README (+ „Právní zásady“: čísla popisná jsou smyšlená), VIZE a roadmapa README odškrtnout, PROJECT_LOG,
deník AI, commit „M1.7 Popisná čísla a start v bytě: …“, checklist a čekat.
