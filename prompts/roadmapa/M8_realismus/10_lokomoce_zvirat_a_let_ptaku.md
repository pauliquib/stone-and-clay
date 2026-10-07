# M8.10 – Lokomoce zvířat 2 a let ptáků

> Roadmapa **M8 Realistický svět** · krok 10/19 · vlna 4
> Předpoklady: M8.1 (M8.4 `WindField` pro let – použij, pokud je) · Navazují: M8.15 (pohyb za potravou), M8.18

## 0. Než začneš – přečti
1. `00_SPOLECNE.md`, `M8_realismus/00_PRINCIPY.md` (kap. 8 – lokomoce), `ZVIRATA.md`
2. `scripts/fauna/quadruped_rig.gd` (celý, 285 ř. – **už má** fázové chody, stojnou fázi bez klouzání a IK chodidel; tenhle krok na něm staví)
3. `scripts/fauna/quadruped_model.gd` (stavba těla z `AnimalSpecs`), `scripts/fauna/animal_specs.gd` (parametry druhů)
4. `scripts/fauna/animal.gd` – fyzika pohybu (`grep -n "^const\|func _physics\|func _move\|accel\|turn" scripts/fauna/animal.gd | head -40`)
5. `scripts/fauna/bird.gd`, `scripts/fauna/bird_flock.gd` (hlavička + `grep -n "^func "`), `scripts/flight/` – termika (`grep -rn "thermal" scripts/flight | head`)
6. `scripts/fauna/horse.gd` (jezdecký kůň – jiný kód, sdílí rig?)

## 1. Proč
Zvěř už chodí věrohodně, ale chybí „život v těle“: páteř se neohýbá, uši a ocas jsou mrtvé, přechody mezi chody jsou skokové, srnec neumí
svůj typický skok přes vysokou trávu a ptáci létají jako body po křivce. Druhý průchod přidá **sekundární pohyb, přechody chodů podle
fyziky a skutečný let** (mávání vs. klouzání, plachtění v termice, přistání s brzděním).

## 2. Co udělat
- **Přechody chodů podle rychlosti a Froudova čísla** (`Fr = v² / (g·L)`, L = délka nohy): krok < ~0,5, klus ~0,5–2,5, cval > ~2,5
  (prahy v `AnimalSpecs` per druh); plynulé prolínání fází při přechodu (ne skok), hysterze (jiný práh nahoru a dolů).
- **Páteř a trup:** ohyb páteře v zatáčce (bočně) a při cvalu (flexe / extenze – „pružina“ cvalu u srnce a zajíce), náklon a dopředný
  sklon trupu podle zrychlení (brzdění → zadek dolů, rozjezd → přední část nahoru), dech v klidu (bok).
- **Sekundární pohyb** jako tlumené pružiny (jednoduchý oscilátor na kost, konstanty v `AnimalSpecs`): uši (při pozornosti natočené ke zdroji
  zvuku – směr z vnímání v `animal.gd`), ocas (srnčí „zrcátko“ se při útěku rozevře – bílá skvrna; divočák ocas nahoru při útěku), hlava
  stabilizovaná při chůzi, krk se natahuje při pastvě.
- **Specifické pohyby:** srnec **odrazový skok** (bounding / stotting) při útěku vysokou trávou a přes překážky; zajíc kličky se
  správným náklonem; divočák „buldozer“ klus a rytí s pohybem hlavy; selata cupitání (vyšší kadence). Kůň (`horse.gd`) – pokud sdílí rig,
  přechody chodů pod jezdcem; pokud ne, jen poznámka do logu.
- **Let ptáků – `scripts/fauna/flight_model.gd`** (sdílený pro `Bird`): zjednodušená aerodynamika (vztlak ∝ v², odpor, hmotnost a plocha
  křídla z tabulky druhů), stavy **mávání** (energie, stoupání) vs. **klouzání** (klesání podle klouzavosti), **plachtění** v termice
  (káně – použij termiku z `flight/` / M6.3, ať káně krouží tam, kde stoupá i paraglide), let **proti větru** z `WindField` (pomalejší
  postup, při přistání proti větru), **přistání** s brzděním (křídla nahoru, nohy dopředu) na bidýlko, vzlet s pár silnými mávnutími.
  Animace křídel podle stavu (mávání s frekvencí podle druhu – vrána ~4 Hz, vlaštovka rychle, káně pomalu / plachtí bez mávání).
- **Hejna – boidy** (Reynolds: oddělení, zarovnání, soudržnost + cíl) pro vrány a špačky; **hejno špačků** na podzim nad polem
  večer (murmurace – stovky bodů jako MultiMesh, jednoduché částice s boidy na GPU nebo CPU s LOD; jen ve scéně u hráče, sezónní událost).
- **Výkon:** sekundární pohyb jen do 60 m; hejno špačků max. 400 ptáků, update boidů v plátcích (prostorová mřížka sousedů).

## 3. Minimum
Plynulé přechody chodů podle Froudova čísla, ohyb páteře a sekundární pohyb uší a ocasu, odrazový skok srnce, let ptáků s mávání/klouzání a
přistáním, káně plachtí v termice.

## 4. Hotovo, když
- Vyplašený srnec přejde z kroku do cvalu plynule a přes vysokou trávu skáče; uši se natáčejí ke zvuku.
- Káně krouží bez mávání v termice nad polem; vrána přistává na strom s brzděním.

## 5. Návrh checklistu ručních testů
1. Dalekohled (X) na pasoucí se srnce → uši se pohybují, při zvuku (běh) se natočí.
2. Vyplašit srnce → krok → klus → cval bez skoku animace, bílé zrcátko při útěku, skoky ve vysoké trávě.
3. Zajíc → kličky s náklonem.
4. Divočáci → klus s nízkou hlavou, selata cupitají.
5. Slunečné odpoledne nad polem → káně krouží bez mávání a stoupá.
6. Vrány vzlétnou (přiblížit se) → silné mávání, pak klouzání; přistání na strom.
7. Říjen večer nad polem → hejno špačků (pokud sezóna a scéna).
8. Silný vítr → ptáci letí proti větru pomaleji.
9. `--perfscene=pole_leto` → ms procesu (cíl +≤ 0,3 ms).

## 6. Závěr
`ZVIRATA.md` (nové parametry druhů), `docs/SYSTEMS.md`, PROJECT_LOG, `docs/testy_M8.md`, commit „M8.10 Lokomoce zvířat a let ptáků: …“.
