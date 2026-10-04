# M3.2 – První tři práce: farma, obecní údržba, výčep

> Roadmapa „Život na vsi“ · **M3 Práce a počítače** · krok 2/4
> Předpoklady: M3.1, M2.4, M2.6 (farma), M1.5 (interiér hospody), M1.7 (`Estate`), M1.8 (interiéry) · Navazují: M3.3

## 0. Než začneš – přečti
1. `prompts/roadmapa/00_SPOLECNE.md`
2. `scripts/jobs.gd` + `data/prace.json` (M3.1) a záznam M3.1 v `PROJECT_LOG.md` (jak se definují pracovní úkoly)
3. `scripts/actions.gd` (registr akcí), `scripts/garden.gd` (M2.4), `scripts/farm/*` (M2.6)
4. `scripts/place.gd` – hospoda (`KEEPERS`, `OFFERS`, `serve`), `scripts/world.gd` – `serve`, `buy`
5. `scripts/road_graph.gd` – hlavička (jak najít body na silnicích obce – pro údržbu)
6. `scripts/priroda/weather.gd` – `snow_cover` (odklízení sněhu), `scripts/priroda/season_fx.gd` (listí)

## 1. Proč
Tři práce, které využívají hotové systémy a jsou dostupné bez řidičáku a speciálních dovedností.

## 2. Práce
### 2.1 Pomocník na farmě („Statek Na Kopci“ – smyšlený)
- **Místo:** vyber samotu / větší hospodářskou budovu na okraji obce z registru `Estate` (typ `hospodarska`; data
  z `data/buildings.json`), která **není** usedlost hráče (`Estate.lot_id`) ani bytový dům; když data budov chybí,
  konstanta pozice u pole z `Fields`. Statek zapiš do `Estate` jako budovu s vlastníkem „hospodář“ (kvůli M4.7). Postav výběh se zvířaty (znovu použij `Pen` a zvířata z M2.6 – statek
  má 2 krávy, 6 slepic, 3 prasata), stodolu (hromada sena), vedoucí NPC („hospodář“, smyšlené jméno, povaha bručoun).
- **Směna** po–pá 6–14 h. Úkoly: nakrmit (seno z hromady → koryto), napojit, podojit krávy, sebrat vejce,
  vykydat hnůj (akce s vidlemi – nový nástroj `vidle` zapůjčený na směnu), v sezóně pomoc na poli (rytí / sklizeň –
  záhony u statku). XP `chovatelstvi`, `zahradnictvi`. Mzda 160 Kč/h. Požadavky: `chovatelstvi ≥ 1`, pracovní boty.

### 2.2 Obecní údržba (zaměstnavatel obecní úřad)
- **Směna** po–pá 7–15 h, začátek u úřadu. Úkoly podle sezóny (generované z `Clock` a `Weather`):
  - jaro–podzim: **posekat trávu** u hřiště / návsi (akce se sekačkou/kosou na vyznačené ploše – dlaždice trávy se
    „posekají“ = kratší / světlejší, stačí vizuál zóny), **vysbírat odpadky** (malé objekty po obci, 8–15 kusů,
    kompas na nejbližší), **opravit lavičku** (Prop lavička – akce kutilství),
  - podzim: **shrabat listí** (M1 `season_fx` listí – akce hrábě v zóně),
  - zima: **odklidit sníh** z chodníku před úřadem / obchodem / zastávkou (akce lopata na zónách; zóna zůstane
    odklizená, dokud nenapadne nový sníh – shader / decal), **posypat** (písek).
- Mzda 170 Kč/h; respekt `sousede`; pověst +1 za odpracovaný týden bez varování.
- Po skončení práce (i bez zaměstnání) může hráč odklízet sníh sousedům dobrovolně (M4.5 háček: respekt, karma).

### 2.3 Výčepní v hospodě U Hřiště
- Požadavky: `vyrecnost ≥ 3`, pověst ≥ 0, čistý rejstřík bez trestného činu (M0.5), střízlivost.
- **Směna** čt–so 17–24 h. Minihra **čepování**: host (štamgast / páteční host) si objedná (bublina „Dvě desítky!“),
  hráč u pípy drží LMB → pruh plnění, pustit v zelené zóně (pivo s čepicí); moc = přeteče (ztráta), málo = host
  nespokojen. Donést na stůl (G / nesení tácu – jednoduše: položit na stůl E), inkasovat (správně vrátit
  – volitelně). Spropitné podle spokojenosti a `vyrecnost`. Pití v práci = varování (hostinský to vidí).
- Mzda 140 Kč/h + spropitné; respekt `stamgasti`, XP `vyrecnost`.
- Pokud interiér hospody není (M1.5), čepování na venkovní zahrádce.

## 3. Minimum
Všechny tři práce s aspoň dvěma typy úkolů; minihra čepování jednoduchá.

## 4. Hotovo, když
- Všechny tři práce jdou získat, odpracovat a zaplatit; úkoly odpovídají sezóně / počasí; porušení pravidel funguje jako v M3.1.

## 5. Návrh checklistu ručních testů
1. Statek → přijetí (pracovní boty) → ráno 6:00 → krmení, dojení, vejce; výdělek.
2. F2 → Datum červen → posekat trávu u hřiště; F2 → leden se sněhem → odklidit sníh u obchodu (zůstane odklizené).
3. Obec: vysbírat odpadky podle kompasu.
4. Hospoda (pověst ≥ 0) → výčepní → pátek večer čepování: přetečení, správná čepice, spropitné.
5. Napij se v práci → varování.
6. Pátek → výplata; J → Práce ukazuje správně.

## 6. Závěr
README, `data/prace.json`, VIZE odškrtnout, roadmapa README, PROJECT_LOG, deník AI, commit „M3.2 První tři práce: …“, checklist a čekat.
