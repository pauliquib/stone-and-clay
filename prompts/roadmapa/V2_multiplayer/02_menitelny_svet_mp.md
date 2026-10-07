# V2.02 – Měnitelný svět přes síť: stromy, zahrady, zvířata, ohně, stavby, interiéry

> Verze 2 · **Multiplayer** · krok 2
> Předpoklady: V2.01, `prompts/09_ukladani_reputace.md`, `priroda/05` · Navazují: V2.03–V2.05

## 0. Než začneš – přečti
1. `prompts/roadmapa/00_SPOLECNE.md`, `V2_multiplayer/README.md`, `GAME_DESIGN.md` kap. 6
2. Síťová vrstva (oblast zájmu 400 m – grep `interest|visibility` v souborech sítě)
3. `scripts/tree_manager.gd` (`felled`, zasazené stromy), `scripts/garden.gd`, `scripts/farm/*` (ohrady, zvířata),
   `scripts/fire.gd` (`Fire`, `GrassFire`), `scripts/building_kit.gd` (stavby), `scripts/interior.gd`, `scripts/building_details.gd` (komíny)
4. `scripts/save_game.gd` – jak je po úkolu 09 rozdělené ukládání světa (host) a hráčů

## 1. Cíl
Vše, co hráči ve světě mění, je sdílené a trvalé: pokácený strom zmizí všem, zasazený roste všem, zahrady, zvířata,
ohně a stavby se synchronizují a ukládají se se světem hosta.

## 2. Co udělat
1. **Stromy:** `felled` a zasazené stromy = stav světa na serveru; při připojení klient dostane seznam (kompaktně – pole indexů);
   změna = RPC všem (`hide_tree(i)`), padající kmen: fyzika u serveru, klientům transformace 10 Hz v oblasti zájmu.
2. **Zahrady a pole:** buňky na serveru; klient dostane stav zahrad v oblasti zájmu; změna buňky = RPC (delta).
   Vlastnictví: zahrada domu hráče patří **hostiteli**? → rozhodni: každý hráč má „domov“ (v MP 2–8 hráčů) – návrh: hráči sdílí
   dům hráče jako „rodina“ (jedna zahrada) nebo host přidělí další domy z `buildings.json` (volitelně – zapiš do GDD).
3. **Zvířata ve výbězích:** simulace na serveru (jako fauna v `priroda/05`), klientům pozice 5–10 Hz v oblasti zájmu; péče
   (krmení…) = akce V2.01. Vlastník zvířete = hráč, který ho koupil (porážka jen vlastník; ostatní mohou krmit – karma).
4. **Ohně a požáry:** stav (`fuel`, buňky `GrassFire`) na serveru; efekty u klientů.
5. **Stavby** (plot, kůlna, rampa…): serverový seznam, vlastník, stavba = série akcí; náhled („duch“) jen lokálně.
6. **Interiéry:** hráč uvnitř = stav na serveru; ostatní hráči ve stejném interiéru se vidí (interiér je sdílený prostor pod mapou),
   hráči venku vidí jen, že je uvnitř (ikona na mapě). Lednička / šatník v domově: sdílené úložiště domácnosti.
7. **Ukládání světa:** vše výše do save světa hosta; profily hráčů zvlášť.

## 3. Hotovo, když
- Dva hráči vidí stejný stav stromů, zahrad, zvířat, ohňů a staveb, včetně pozdního připojení; vše přežije uložení a načtení světa.

## 4. Návrh checklistu (2 klienti)
1. A pokácí strom → B ho vidí padat a pak pařez.
2. B se připojí později → pokácené stromy chybí i u něj.
3. A zasadí stromek, B zalije → roste oběma.
4. A krmí slepice, B sebere vejce → konzistentní.
5. A rozdělá oheň, B se u něj ohřeje.
6. B postaví plot → A ho vidí a naráží do něj.
7. Oba v domově → vidí se uvnitř.
8. Host uloží, oba odejdou, host načte, B se připojí → vše na místě.

## 5. Závěr
GDD kap. 6 (autorita, vlastnictví domů), README, PROJECT_LOG, commit „V2.02 Měnitelný svět v MP: …“, checklist a čekat.
