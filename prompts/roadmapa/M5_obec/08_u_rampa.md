# M5.8 – U-rampa na zahradě za domem hráče

> Roadmapa „Život na vsi“ · **M5 Obec a volný čas** · krok 8/9
> Předpoklady: M5.7 (skateboard), M5.1 (rámec staveb `BuildingKit`) nepovinně · Navazují: –

## 0. Než začneš – přečti
1. `prompts/roadmapa/00_SPOLECNE.md`
2. `docs/VIZE_A_ROADMAPA.md` – kap. 4.5 „U-rampa (2)“ a otevřená otázka „hotová, nebo postavit?“ (kap. 7 – zkontroluj, jestli ji uživatel už nerozhodl; když ne, **zeptej se** – viz 2.)
3. `scripts/player.gd` – větev skateboardu z M5.7 (fyzika, detekce povrchu, grind)
4. `scripts/world.gd` – `_horse_spot`, `_ground_spot` (jak se hledá volné místo u domu), `meta["domov_hrace"]`
5. Záznamy M2.4 (zahrada), M2.6 (výběh) v `PROJECT_LOG.md` – rezervované místo pro rampu (konstanta)
6. `scripts/building_kit.gd` (M5.1), `scripts/mesh_kit.gd`

## 1. Proč
Uživatel: „přidat na zahradu u domu U-rampu hned vedle domu, tedy za domem“. Místo pro trénink triků.

## 2. Rozhodnutí
- Pokud uživatel nerozhodl, zda má být rampa hotová od začátku, nebo si ji hráč postaví: **zeptej se na začátku**
  (jedna otázka). Výchozí doporučení: **stojí hotová** (a v M5.1 rámci jde postavit další / menší – quarter-pipe, zábradlí).

## 3. Co udělat
1. **Umístění:** za domem hráče (strana odvrácená od silnice), hned vedle domu, v rezervovaném místě (M2.4) – ověř, že nekoliduje
   se zahradou, výběhem, stájí koně, autem; terén zarovnat podkladem (betonová deska pod rampou – kolize) – rampa nesmí viset.
2. **Tvar (reálné rozměry mini U-rampy):** šířka 4,8 m, výška stěn 1,5 m, poloměr přechodu (transition) 2,4 m, plochý střed
   (flat) 2,4 m, **coping** (kovová trubka ø 6 cm na hraně – pro grind/stall), plošiny nahoře (deck) 1,2 m hluboké se zábradlím
   vzadu a žebříkem. Stavba z překližky (barva dřeva), boční konstrukce (trámky).
   Mesh: profil oblouku jako `loft` / vlastní quad strip po segmentech (24 segmentů na oblouk), **kolize přesně podle meshe**
   (`ConcavePolygonShape3D` – jen pro rampu; nebo sada nakloněných boxů po segmentech – plynulost je důležitá: použij
   concave z meshe).
3. **Fyzika skateboardu na rampě** (rozšíření M5.7): na zakřiveném povrchu se deska natáčí podle normály (orientace hráče =
   normála povrchu), rychlost se zachovává (gravitace podél povrchu – pumpování: Shift přikrčení dole / vstát nahoře = +rychlost),
   **vert:** když hráč vyjede nad hranu (normála vodorovně a rychlost vzhůru), letí svisle a dopadne zpět do rampy (pomoc: v blízkosti
   copingu jemně korigovat vodorovnou složku, aby dopadl zpátky – „air assist“, laditelné). Ve vzduchu triky (M5.7) + nové:
   `rock-to-fakie`, `50-50 stall` na copingu, `air` s grabem (klávesa E ve vzduchu).
   Přistání: deska rovnoběžně s povrchem ± 30° → OK, jinak pád (s koleny – sjede po rampě).
4. **Skóre:** „Session“ – součet triků za 2 min, rekord, XP `skateboarding` × 1,5 na rampě. Kamarádi (mládež – respekt `mladez`)
   občas přijdou koukat (2–3 NPC u rampy odpoledne v létě) a komentují (bubliny).
5. **Noční klid:** jízda na rampě 22–6 h → hluk → sousedé (M4.4 rušení nočního klidu – drobnost, varování, pak přestupek).
6. Pokud „postavit“: plán v `BuildingKit` (materiál: 20× překližka, 10× trámky, coping, šrouby; kutilství 6; 4 fáze stavby).

## 4. Hotovo, když
- Za domem stojí U-rampa v reálných rozměrech, jde na ní jezdit (pumpování, vert, stall, air, triky), padat a skórovat;
  nekoliduje s ostatním; v noci ruší sousedy.

## 5. Návrh checklistu ručních testů
1. `./run.sh` → za domem hráče U-rampa (zahrada, výběh, kůň, auto v pořádku).
2. Skateboard: sjeď z decku do rampy (drop-in), jízda tam a zpět.
3. Pumpování → vyšší výjezd; nad hranu → vert a návrat do rampy.
4. Stall na copingu; grab ve vzduchu; kickflip v rampě.
5. Špatný dopad → pád a sjetí.
6. Session 2 min → skóre, rekord, XP.
7. 23:00 jízda → stížnost sousedů.

## 6. Závěr
README (Systémy → U-rampa), VIZE odškrtnout (a vyřešenou otázku v kap. 7), roadmapa README, PROJECT_LOG, deník AI,
commit „M5.8 U-rampa za domem: …“, checklist a čekat.
