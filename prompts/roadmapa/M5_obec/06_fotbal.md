# M5.6 – Fotbalové hřiště a hraní fotbalu

> Roadmapa „Život na vsi“ · **M5 Obec a volný čas** · krok 6/12
> Předpoklady: M5.5 (kalendář – zápas jako událost) nepovinně · Navazují: M5.4 (hřiště pro hasičský sport)

## 0. Než začneš – přečti
1. `prompts/roadmapa/00_SPOLECNE.md`
2. `docs/VIZE_A_ROADMAPA.md` – kap. 4.5 „Fotbal (18)“
3. `scripts/priroda/village_events.gd` – `BONFIRE_POS` (hranice čarodějnic stojí **na hřišti** – orientační bod hřiště)
   a data hřiště v OSM (zkus grep `pitch|soccer|hriste` v `tools/*.py` a `data/map.json` – klíče; pokud nic, zeptej se
   uživatele na roh hřiště z mapy M nebo použij `BONFIRE_POS` + rozměr a zapiš do logu)
4. `scripts/world.gd` – `_spawn_props` / `_prop` (míč u domu – `RigidBody3D`, jak se do něj strká)
5. `scripts/player.gd` – kontakt s rekvizitami (grep `apply_impulse|push`)
6. `scripts/characters.gd` – trenér fotbalistů (grep `trenér`), `scripts/dialog.gd` – téma `fotbal`
7. `scripts/villager.gd`, `scripts/npc.gd` – pohyb NPC k cíli (pro hráče na hřišti)

## 1. Proč
Uživatel: „zdokonalit fotbalové hřiště a přidat možnost zahrát si fotbal“. Postavy už o nedělních zápasech mluví
– teď se to stane.

## 2. Co udělat
### 2.1 Hřiště
- Travnatá plocha ~90 × 55 m (menší vesnické), zarovnaná (terén může být svažitý – postav **nad** terénem plochu s kolizí
  jen tam, kde je potřeba, nebo akceptuj mírný sklon; pokud je rozdíl > 1 m, zapiš otevřený bod „zarovnat terén v Blenderu“),
  čáry (bílé pruhy – decal / tenké quady), **branky se sítí** (tyče s kolizí, síť jako tenká kolizní plocha, která míč
  zpomalí – `Area3D` s tlumením), rohové praporky, lavičky pro hráče, tribunka (lavice pro 30 diváků), kabiny (malá budova),
  osvětlení (4 stožáry, večer zapnuté při akci), ukazatel skóre (Label3D).
- Hranice čarodějnic (VillageEvents) nesmí stát v brance – posuň ji na okraj, pokud koliduje.

### 2.2 Míč a ovládání
- Míč: `RigidBody3D` (0,43 kg, ø 22 cm, odrazivost, tření na trávě, déšť – těžší kopání, sníh – brzdí), kolize s hráčem.
- **Kopání:** když je míč do 1 m před hráčem: LMB = kop (síla podle držení 0–1 s, směr kamerou; výška – kop na zem / vysoký),
  jemné vedení míče při běhu (malé impulzy vpřed – dribling), E = zvednout míč do rukou (brankář / aut).
  Pokud je v ruce nástroj (Q), LMB ho použije – míč jen s prázdnýma rukama.
- XP `kondice` za běh s míčem a góly.

### 2.3 Kopaná s NPC
- **Volná hra:** odpoledne v létě 2–6 kluků (vesničané mládež) kope na jednu branku; hráč se přidá (T „můžu si kopnout?“).
  NPC AI: jde k míči, kopne směrem k brance / spoluhráči (jednoduchá logika: nejbližší k míči běží, ostatní drží pozice).
- **Penalty:** minihra – hráč kope na brankáře NPC (brankář skočí náhodně / podle směru); nebo hráč chytá.
- **Zápas** (událost z M5.5 – každá 2. neděle 15:00 VIII–X a IV–VI): domácí × hosté (smyšlené týmy), 2 × 20 min (herních –
  laditelné), 7–11 hráčů na tým (výkon – ve vzdálenosti > 60 m zjednodušit), rozhodčí, diváci (20–40 vesničanů)
  fandí (bubliny „Do toho!“), stánek s pivem a klobásou. Hráč může **fandit** nebo, když je v týmu (trenér – respekt
  `fotbal` ≥ 10 a `kondice` ≥ 5, 2 tréninky), **hrát** (AI spoluhráči, hráč ovládá sebe). Výsledek zápasu: hra hráče
  ovlivní šance (góly), jinak simulace podle síly týmů. Vítězství → respekt `fotbal` +5, pověst +2; oslava v hospodě.
- **Tréninky** (čtvrtek 18:00): běh (kondice), střelba na branku – krátké úkoly od trenéra.

## 3. Minimum
Hřiště s brankami a čarami, míč s kopáním a driblinkem, penalty, volná hra NPC. Zápas jako simulace s diváky.

## 4. Hotovo, když
- Hřiště je úplné, míč jde kopat a vést, penalty fungují, v létě jde kopat s kluky, v neděli je zápas s diváky
  (hráč fandí, po splnění podmínek i hraje).

## 5. Návrh checklistu ručních testů
1. F2 → Teleport hřiště: čáry, branky se sítí, lavičky, tribuna, stožáry.
2. Míč: vedení při běhu, slabý / silný / vysoký kop; míč v síti se zastaví.
3. Penalty proti NPC brankáři.
4. Červenec 17:00 → kluci kopou; přidej se.
5. Neděle zápasu 15:00 → týmy, rozhodčí, diváci fandí, skóre.
6. Trenér → trénink → nabídka do týmu → hraj zápas.
7. Déšť → míč těžší.

## 6. Závěr
README (Systémy → Fotbal, Ovládání), VIZE odškrtnout, roadmapa README, PROJECT_LOG, commit „M5.6 Fotbal: …“, checklist a čekat.
