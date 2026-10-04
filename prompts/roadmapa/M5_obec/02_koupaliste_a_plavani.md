# M5.2 – Koupaliště na bývalé hasičské nádrži + plavání

> Roadmapa „Život na vsi“ · **M5 Obec a volný čas** · krok 2/9
> Předpoklady: M5.1 (poloha stavebnin – koupaliště je hned za nimi), M2.3 (plavky) · Navazují: M3.3 (plavčík), M5.3 (hasiči – nádrž jako zdroj vody)

## 0. Než začneš – přečti
1. `prompts/roadmapa/00_SPOLECNE.md`
2. `docs/VIZE_A_ROADMAPA.md` – kap. 4.5 „Koupaliště (15)“
3. `scripts/water.gd` (celý) – rybníky (`ponds`: polygon, `level`), `info_at` (hloubka), zamrzání, shader hladiny
4. `tools/water.py` – jak vznikají nádrže a vyhloubení (`water_carve.bin`); `scripts/terrain.gd` – `_apply_water_carve`
5. `scripts/player.gd` – `wade` (brodění), `_physics_process` (gravitace, pohyb), `_update_body`
6. `scripts/body_state.gd` – `wetness`, `cold`, výdrž; `scripts/humanoid.gd` – pózy (plavání přidáš)
7. Záznam M5.1 v `PROJECT_LOG.md` (souřadnice stavebnin)

## 1. Proč
Uživatel: „vytvořit koupaliště na bývalé hasičské nádrži u potoka v dolině za Dukelčicemi, hned za stavebninami“.
Přinese léto do hry: koupání, plavání, plavčík, skoky, v zimě bruslení.

## 2. Umístění
- Nádrž možná je v `data/water.json` (`ponds`) – najdi rybník nejblíže stavebninám (`STAVEBNINY_POS`) a potoku;
  pokud tam není nebo je nejasné → **zeptej se uživatele** na souřadnice (mapa M) a rozměr. Pak koupaliště postav jako
  novou nádrž (obdélník ~25 × 12 m, hloubka 0,8–2,2 m) – hladina, dno (vyhloubení terénu – buď přes úpravu v
  `tools/water.py` + nový export (nespouštěj), nebo za běhu: vlastní mesh bazénu **nad** terénem s betonovým okrajem
  a vlastní kolizí dna – doporučeno, nezávisí na exportu).

## 3. Co udělat
1. **Areál:** betonový lem nádrže, schůdky, mola / skokanský můstek (1 m), travnatá pláž s dekami, šatny (malá budova –
   interiér není nutný, stačí převlečení: E → „Převléct do plavek“ – M2.3), stánek s občerstvením (nabídka: nanuk, limonáda,
   pivo, párek, hranolky; otevřeno VI–VIII 10–19 za hezkého počasí), plot, vstup (vstupné 60 Kč u pokladny, jinak
   „vlezl přes plot“ – drobnost), sprcha, cedule s řádem (humor), plavčík (NPC na vyvýšené židli, v M3.3 i jako práce).
2. **Plavání** (`Player`): když hloubka `wade` > 1,2 m → stav **plave**: bez gravitace na hladině (vztlak), pomalý pohyb
   (1,2 m/s, Shift 2 m/s – výdrž rychle ubývá), Mezerník = nahoru / výskok k okraji (vylézt po schůdcích nebo u okraje E),
   Ctrl = potopit se (pod hladinou 10–20 s dech, pak dusí se → zdraví; kamera pod vodou modře zabarvená),
   animace plavání (prsa – ruce a nohy v `humanoid.gd`, tělo vodorovně). Týká se **všech** vodních ploch hry
   (rybníky, řeka), ne jen koupaliště.
   - Oblečení: plavat v oblečení jde, ale je to pomalejší a promočí to (`wetness` = 1), plavky OK.
   - Opilý plavec (> 1 ‰) → riziko: výdrž ubývá 2× a může „polknout vodu“; plavčík zasáhne.
3. **Teplota vody** (`Water` – nový výpočet pro nádrže): pomalu sleduje průměr teploty vzduchu posledních dní
   (červenec 20–24 °C, květen 14 °C) → v chladné vodě roste `cold` rychle; po vylezení za větru chladne víc, na slunci
   osychá. HUD u vody: „Voda 21 °C“.
4. **Skoky:** z můstku / mola – pád do vody > 1,5 m hloubky OK; do mělké (< 1,2 m) → zranění (`hurt`), plavčík napomene,
   karma nic, pověst −1 („blbnul na koupališti“).
5. **Zima:** nádrž zamrzne (`Water` – už umí) → **bruslení** (volitelné: klouzavý pohyb na ledě, když má hráč `brusle`
   z Potravin/stavebnin; bez nich klouže jako na náledí). Tenký led při oblevě → prolomení → studená voda (rychlé
   podchlazení) – vylézt.
6. **NPC:** v létě za hezkého počasí 5–12 vesničanů na dece / ve vodě (jednoduše stojí po pás ve vodě nebo leží) –
   znovu použij logiku davu u událostí (`VillageEvents` BONFIRE_CROWD).

## 4. Minimum
Nádrž s okrajem a kolizí, plavání (všude), teplota vody, vstupné a stánek. Bruslení a NPC na pláži do otevřených bodů.

## 5. Hotovo, když
- Koupaliště existuje za stavebninami, hráč plave (i v rybnících), potápí se, skáče, chladne v chladné vodě;
  v létě jsou tam lidé a stánek.

## 6. Návrh checklistu ručních testů
1. F2 → Datum 15. 7., 14:00, jasno → koupaliště: plavčík, lidé, stánek.
2. Převleč se do plavek v šatně; vstupné.
3. Vlez do vody → od 1,2 m plaveš; Shift rychleji; Ctrl potopit – dech, pak zdraví.
4. Skok z můstku do hloubky OK; do mělčiny → zranění.
5. F2 → Datum květen → voda 14 °C → rychle chladneš.
6. Plavání v rybníce v lese.
7. Leden → zamrzlá nádrž, chůze po ledu klouže (brusle, pokud hotovo).
8. Opilý plavec → plavčík zasáhne.

## 7. Závěr
README (Systémy → Koupaliště a plavání, Ovládání – plavání), VIZE odškrtnout, roadmapa README, PROJECT_LOG, deník AI,
commit „M5.2 Koupaliště a plavání: …“, checklist a čekat.
