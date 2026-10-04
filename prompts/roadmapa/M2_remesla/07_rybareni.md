# M2.7 – Rybaření

> Roadmapa „Život na vsi“ · **M2 Řemesla a venkov** · krok 7/10
> Předpoklady: M0.2–M0.4, M2.2 (pečení na ohni) · Navazují: M4.6 (rybářský lístek, povolenka, rybářská stráž)

## 0. Než začneš – přečti
1. `prompts/roadmapa/00_SPOLECNE.md`
2. `docs/VIZE_A_ROADMAPA.md` – kap. 4.2 „Rybaření (U1)“
3. `scripts/water.gd` (celý, 265 ř.) – `info_at(x, z)` (hloubka, jméno toku), `nearest_stream`, rybníky (`ponds`), zamrzání
4. `data/water.json` – jen klíče a první záznam (struktura `streams`, `ponds`, `kinds`) – **nečti celý** (`python3 -c` výpis klíčů)
5. `scripts/actions.gd`, `scripts/tool_models.gd` (udice z M0.4), `scripts/skills.gd`
6. `scripts/humanoid.gd` – akce `cast` (z M0.4) nebo jak se dělá držení předmětu
7. `scripts/clock.gd`, `scripts/priroda/weather.gd` – denní doba, tlak/počasí (`kind`, `rain`, `temp`)

## 1. Proč
Rybaření je klidná RuneScape činnost u potoků a rybníků, které hra už má. Úlovek se sní, prodá nebo pustí.
Legálně jen s rybářským lístkem a povolenkou (M4.6) – teď připravíme háčky.

## 2. Návrh
### 2.1 Vybavení
`udice` (nástroj, `rybareni` 1), `udice_lepsi` (úroveň 10, vyšší šance na větší rybu), `navnada_zizaly`
(vykopat na zahradě akcí `kopat_zizaly` – rýč, 20 s, 3–6 ks; po dešti víc), `navnada_testo` (z Potravin –
mouka + voda nebo koupit), `navnada_kukurice` (Potraviny). Podběrák (volitelný, větší ryby bez něj častěji utečou).

### 2.2 Rybolov – minihra
1. Hráč stojí u vody (`Water.info_at` v bodě 2–8 m před ním má hloubku > 0,3 m; zamrzlá voda = nejde),
   v ruce udice, v inventáři návnada → LMB = **nahodit** (animace `cast`, splávek dopadne do vody – malý
   `MeshInstance3D` na hladině, kroužky).
2. Čekání na záběr: náhodný čas (5–90 s reálně) podle **šance** = druh místa × denní doba (ráno a večer ×1,5,
   poledne ×0,7, noc – jen úhoř/sumec) × počasí (před deštěm / zataženo ×1,2, jasno a horko ×0,7, silný vítr ×0,8)
   × sezóna (zima ×0,3) × návnada × úroveň. Splávek jemně poskakuje, při záběru se ponoří + zvuk.
3. **Záseck:** do 1,2 s od ponoření stisknout LMB (včas = háček), jinak ryba sežere návnadu.
4. **Zdolávání:** pruh napětí vlasce na HUD (0..1) – LMB drží = navijí (napětí roste), pustit = povolí.
   Ryba občas „zabere“ (napětí skočí). Napětí > 1 → vlasec praskne (ztráta návnady, háčku). Ryba se
   přitahuje, když je napětí v „zelené zóně“ 0,4–0,8. Délka podle velikosti ryby (5–40 s).
5. **Úlovek:** druh a velikost (cm, kg); hláška „Kapr obecný 48 cm, 2,1 kg“. Nabídka: **ponechat** (do inventáře,
   `perishable_h` 12 h) / **pustit** (karma +0,5 u malých a hájených). XP `rybareni` podle velikosti.

### 2.3 Ryby (tabulka `FISH` – druh, kde, míra, hájení, velikost, cena)
| Druh | Voda | Lovná míra | Doba hájení (orientačně) |
|---|---|---|---|
| Kapr obecný | rybník, nádrž | 40 cm | – |
| Lín | rybník | 25 cm | – |
| Plotice, perlín, cejn | rybník, řeka | – | – |
| Okoun | rybník, řeka | – | – |
| Štika | rybník, řeka | 50 cm | 1. 1. – 15. 6. |
| Candát | řeka, nádrž | 45 cm | 1. 1. – 15. 6. |
| Pstruh obecný | potok | 25 cm | 1. 9. – 15. 4. (loví se 16. 4. – 31. 8.) |
| Jelec, klen | potok, řeka | – | – |
| Úhoř | řeka, rybník (noc) | 50 cm | – |
| Sumec | nádrž (noc) | 70 cm | 1. 1. – 15. 6. |
Hodnoty jsou **orientační** – do datového souboru `data/ryby.json` s poznámkou „ověřit v rybářském řádu (vyhl. 197/2004 Sb.)“.
Malé potoky (`stream`, `ditch`) → hlavně pstruh, jelec, plotice, malé kusy.

### 2.4 Zákon – háčky (M4.6 dodělá doklady a stráž)
- Ponechání ryby pod mírou nebo v době hájení → přestupek `rybolov_mira_hajeni` (99/2004 Sb. – „ověřit“),
  zjistí jen svědek (`World.commit_offense` přes svědky jako u kácení) – zatím bez stráže.
- `World.has_permit(id, "rybarsky_listek")` a `"povolenka_rybolov"` – zatím vždy false → rybaření bez nich je
  **pytláctví** (`rybarske_pytlactvi`), ale zjistí se jen při svědkovi (vesničan u vody). M4.6 přidá stráž a doklady.

### 2.5 Využití
Pečení na ohni (`cook_to` z M2.2 → `ryba_pecena`), prodej v hospodě (hostinský koupí kapra na Vánoce dráž –
v prosinci ×2), dárek sousedům.

## 3. Hotovo, když
- U potoka i rybníka jde nahodit, dočkat se záběru, zaseknout, zdolat nebo ztratit rybu, ponechat / pustit.
- Šance odpovídá denní době, počasí a sezóně; úlovek jde upéct a prodat; míra a hájení se kontrolují (se svědkem).

## 4. Návrh checklistu ručních testů
1. Kup udici a kukuřici; F2 → Teleport → k rybníku; Q udice; LMB → splávek na vodě.
2. Počkej na záběr → LMB včas → pruh napětí; zdolej rybu (drž/pouštěj) → úlovek, hláška.
3. Drž LMB stále → vlasec praskne.
4. Na zamrzlém rybníku (leden −10 °C) → nahodit nejde.
5. Potok → pstruh / jelec; v poledne v létě méně záběrů než ráno.
6. Štika v březnu pod mírou, ponechat, vesničan u vody → přestupek.
7. Upeč rybu na ohni, prodej v hospodě.
8. Kopání žížal po dešti → víc kusů.

## 5. Závěr
README (Systémy → Rybaření), `data/ryby.json`, `data/zakon.json`, VIZE odškrtnout, roadmapa README, PROJECT_LOG,
deník AI, commit „M2.7 Rybaření: …“, checklist a čekat.
