# M2.5 – Sázení stromů

> Roadmapa „Život na vsi“ · **M2 Řemesla a venkov** · krok 5/10
> Předpoklady: M2.1 (`TreeManager`), M2.4 (zahrada, zálivka) · Navazují: M4.5 (karma a pověst za výsadbu)

## 0. Než začneš – přečti
1. `prompts/roadmapa/00_SPOLECNE.md`
2. `docs/VIZE_A_ROADMAPA.md` – kap. 4.2 „Sázení stromů“
3. `scripts/tree_manager.gd` (z M2.1) a `scripts/map_loader.gd` – `build_trees`, `_proto_mesh`, `tree_material` (jak vypadá strom, prototypy 0–2 listnáče, 3+ jehličnany)
4. `scripts/garden.gd` (z M2.4) – denní růst, zálivka
5. `scripts/priroda/tree_decor.gd` – ovoce v korunách (nový ovocný strom má po letech plodit)
6. `shaders/tree.gdshader` – sezónní barvy listí (nový strom musí reagovat stejně)

## 1. Proč
Hráč může krajinu nejen kácet, ale i obnovovat. Ovocné stromy na zahradě dávají po letech úrodu,
lesní výsadba zlepšuje karmu a pověst a může být i placená práce (M3.3).

## 2. Návrh
- **Sazenice** v `ItemsDB`: `sazenice_jablon`, `sazenice_slivon`, `sazenice_hrusen`, `sazenice_tresen`,
  `sazenice_dub`, `sazenice_buk`, `sazenice_smrk`, `sazenice_borovice` (cena 150–450 Kč, ovocné v Potravinách
  sezónně III–V a X–XI, lesní přes práci / myslivce).
- Akce `zasadit` (cíl `ground`, nástroj rýč/lopata, 60 s, `zahradnictvi` 15 XP). Nesmí se sázet na silnici,
  do vody, do 2 m od jiného stromu / budovy (`TreeManager.nearest_tree`, `World.dist_to_roads`).
- **Dynamická vrstva** `PlantedTrees` (v `tree_manager.gd` nebo nový soubor): seznam `{pos, druh, den_zasazení, zdraví}`,
  vlastní MultiMesh (sdílí prototypy a materiály s `build_trees`, aby vypadal stejně a reagoval na sezóny), kolize
  kmene od výšky 1,5 m.
- **Růst:** měřítko roste z 0,15 (sazenice ~1 m) do plné velikosti za **N herních let** (laditelné: ovocné 4 roky,
  listnáče 8, jehličnany 6 – herní roky jsou dlouhé, ber to jako „hodně dní“ a nabídni konstantu `GROWTH_SPEEDUP`
  pro hratelnost, výchozí 6× rychleji než realita). První 2 měsíce sucho bez zálivky → zdraví klesá → uschne.
  Srnci ožírají nechráněné sazenice (háček: pokud je poblíž zvěř – `Fauna`, šance), ochrana: `ochranny_obal`
  (předmět, akce `obalit`).
- **Ovoce:** ovocný strom od velikosti 0,7 plodí v sezóně (napoj `TreeDecor` – aby ovoce viselo i na zasazených
  stromech; akce `oklepat/natrhat` → `jablko` atd.).
- **Kácení** zasazených stromů funguje stejně jako u mapových (`TreeManager` je musí umět).
- **Karma a pověst:** zasazený strom, který se ujme (po 60 dnech), → karma +1, pověst +1 (max. 5× za rok).
  Na cizím pozemku (zástavba mimo vlastní zahradu) → sousedovi se to nemusí líbit (respekt `sousede` −1) –
  jen háček, žádný přestupek.
- **Ukládání:** seznam zasazených stromů.

## 3. Hotovo, když
- Sazenice jde zasadit, roste, bez vody uschne, dá se chránit, ovocný plodí, zasazený strom jde pokácet; vše se ukládá.

## 4. Návrh checklistu ručních testů
1. F2 → Datum duben; kup sazenici jabloně; zasaď na zahradě → malý stromek.
2. Pokus o sázení na silnici / vedle domu → hláška.
3. Zalévej, spi 10 nocí → vyroste o kus; nezalévej v létě → zhorší se / uschne.
4. F2 → Datum +5 let (opakovaně, nebo cheat růstu) → vzrostlý strom, v září jablka v koruně, natrhat.
5. Podzim → listí se barví jako u ostatních stromů.
6. Pokácej zasazený strom → funguje jako u ostatních.
7. F5/F9 → stromy zůstanou.

## 5. Závěr
README, VIZE odškrtnout, roadmapa README, PROJECT_LOG, deník AI, commit „M2.5 Sázení stromů: …“, checklist a čekat.
