# M5.1 – Stavebniny (nová budova a obchod) + kutilské stavby

> Roadmapa „Život na vsi“ · **M5 Obec a volný čas** · krok 1/9
> Předpoklady: M0.2, M0.4, M1.4/M1.5 (interiér – nepovinně) · Navazují: M5.2 (koupaliště hned za stavebninami), M5.8 (U-rampa ze stavebního materiálu), M2.6 (ohrady), M3.3 (prodavač)

## 0. Než začneš – přečti
1. `prompts/roadmapa/00_SPOLECNE.md` (kap. 3 – smyšlený název, žádné logo)
2. `docs/VIZE_A_ROADMAPA.md` – kap. 4.5 „Stavebniny (15)“
3. `data/pois.json` (struktura záznamu místa) a `tools/pois.py` (jak místa vznikají z OSM – `osm_id`, dveře, parkování)
4. `scripts/place.gd` – `OFFERS`, `HOURS`, `KEEPERS`, `_sign` (cedule), `setup`; `scripts/world.gd` – `_spawn_places`
5. `scripts/items_db.gd` (materiály, nástroje), `scripts/actions.gd` (recepty / stavění)
6. `scripts/hud.gd` – mapa M (`_draw_map`, značky míst ★)

## 1. Proč
Uživatel: „stavebniny prosím také přidat“ – v dolině za obcí u cesty k sousední obci, **hned za nimi**
bude koupaliště (M5.2). Stavebniny jsou obchod s nářadím, materiálem, semeny a zdroj pro kutilské stavby.

## 2. Umístění – **zeptej se uživatele**, pokud to nejde zjistit
- Uživatel popsal: *„v dolině za Dukelčicemi směr (sousední obec), hned za stavebninami je bývalá hasičská nádrž u potoka“*.
- Postup: 1) zkus v OSM (`geodata/pbf/zlinsky-latest.osm.pbf` – `shop=doityourself|hardware|trade`, `building=*` s názvem, nebo
  `landuse=industrial` u silnice ven z obce) – napiš malý dotaz v Pythonu (vzor `tools/pois.py`), **nespouštěj ho**, ale pokud
  už existuje výstup / data, použij je; 2) **jinak se zeptej uživatele na souřadnice** – ve hře je ukáže mapa M
  (souřadnice hráče dole, `_map_pos`): „Postav se ve hře ke vchodu stavebnin a pošli mi souřadnice z mapy M.“
  Do té doby dej do kódu konstantu `STAVEBNINY_POS` s komentářem „DOPLNIT“ a funkce ať se bez ní nevytváří.
- Pozor: skutečný název firmy **nepoužívat** – smyšlený název, např. „Stavebniny Cihla & Hřebík“, obecná cedule.

## 3. Co udělat
1. **Místo `stavebniny`** v `pois.json` (nebo v kódu jako doplňkové místo, pokud `pois.json` generuje nástroj – pak do
   `tools/pois.py` přidej ruční záznam): budova (pokud v OSM není, postav procedurálně halu ~20 × 12 m + venkovní
   sklad s paletami, hromadou písku, štěrku, prken), cedule, parkoviště, otevírací doba **po–pá 7–17, so 7–12**.
2. **Nabídka** (`Place.OFFERS["stavebniny"]`): nářadí (sekery, pila, rýč, lopata, motyka, hrábě, vidle, konev, kolečko /
   ruční vozík, nůžky, nůž), materiál (prkna, trámky, hřebíky, šrouby, cement, písek, štěrk, pletivo, sloupky, plotovky,
   OSB desky, plachta, barva), zahrada (semena, sazenice, hnojivo, substrát), díly (autobaterie, pneumatika – `dily_auto`),
   ochranné pomůcky (rukavice, brýle, helma, reflexní vesta), sport (luk, šípy, terče – M2.8). Ceny realistické.
   Přesuň „železářské“ položky, které byly dočasně v Potravinách (grep v `OFFERS["obchod"]`), sem (v Potravinách ponech jen drobnosti).
3. **Velký materiál** (prkna, pytle cementu, sloupky) má hmotnost → náklad (M2.10) – odvoz autem / vozíkem; nebo
   **doprava** za 390 Kč (za 1 herní den u domu).
4. **Kutilské stavby** – rámec `scripts/building_kit.gd` (`class_name BuildingKit`): „plán stavby“ = recept
   (materiál + nástroj + úroveň `kutilstvi` + čas) → hráč vybere plán (Tab → „Stavět…“), umístí „ducha“ stavby
   (průhledný náhled, otáčení kolečkem, zelená/červená podle kolize a terénu), potvrdí → staveniště → akce „stavět“
   (několik kol akcí M0.4) → hotová stavba s kolizí, ukládá se. Plány teď: **plot (úsek 2 m)**, **branka**, **kurník**,
   **kotec**, **lavička**, **kůlna na nářadí** (úložiště), **vyvýšený záhon**. U-rampa přijde v M5.8 (stejný rámec).
   Stavět jen na vlastním pozemku (zahrada / výběh domu hráče – poloměr z M2.1) nebo na pronajatém poli (M2.4).
5. Mapa M: nová značka ★ Stavebniny; F2 → Teleport: Stavebniny.

## 4. Minimum
Místo (i s dočasnou pozicí), obchod s nabídkou, doprava materiálu; rámec staveb s plotem a kůlnou.

## 5. Hotovo, když
- Stavebniny existují (na správném místě po doplnění souřadnic), prodávají, materiál jde odvézt / nechat dovézt;
  z materiálu jde postavit plot a kůlnu u domu; stavby se ukládají.

## 6. Návrh checklistu ručních testů
1. (Po doplnění souřadnic) F2 → Teleport → Stavebniny: budova, cedule, sklad, parkoviště.
2. Otevírací doba: sobota 13:00 zavřeno.
3. Kup sekeru, prkna a pletivo; prkna jako náklad do auta.
4. Doprava materiálu → druhý den u domu.
5. Tab → Stavět → plot: náhled zelený/červený, postav 3 úseky + branku.
6. Kůlna: postav, ulož do ní nářadí.
7. F5/F9 → stavby zůstanou.

## 7. Závěr
README (Systémy → Stavebniny, Stavby), VIZE odškrtnout, roadmapa README, PROJECT_LOG (souřadnice, pokud chybí – otevřený bod),
deník AI, commit „M5.1 Stavebniny a kutilské stavby: …“, checklist a čekat.
