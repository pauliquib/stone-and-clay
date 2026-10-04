# M1.3 – Kouř z komínů podle teploty

> Roadmapa „Život na vsi“ · **M1 Živý svět** · krok 3/6
> Předpoklady: M1.2 (pozice komínů) · Navazují: M2.2 (kamna doma – vlastní komín hráče)

## 0. Než začneš – přečti
1. `prompts/roadmapa/00_SPOLECNE.md`
2. `docs/VIZE_A_ROADMAPA.md` – kap. 4.1 „Kouř z komínů podle teploty“
3. `scripts/building_details.gd` (z M1.2) – `chimneys_near`
4. `scripts/priroda/weather.gd` – `temp`, `wind`, `wind_vector()`, `fog`, `rain`, `state()`
5. `scripts/priroda/village_events.gd` – `_fire_particles` (vzor částic ohně/kouře ve hře)
6. `scripts/clock.gd` – `hour()`, `month()`
7. `scripts/local_client.gd` – kde se vytváří klientské efekty (`season_fx`, `atmosphere`) – kouř je vizuál klienta

## 1. Proč
Poznámka uživatele: „v zimě kouř podle aktuální teploty → závislost na tom, jak moc je zima; pokud není
moc, kouř jen u některých“. Malý detail, který udělá hodně atmosféry.

## 2. Pravidla (tabulka `SmokeRules` nahoře v novém souboru)
- **Pravděpodobnost, že dům topí** `p(T)` – lineárně mezi body (laditelné):
  `T ≥ 16 °C → 0.03` (jen vaření / sporák na dřevo), `12 °C → 0.15`, `8 °C → 0.35`, `3 °C → 0.65`,
  `0 °C → 0.85`, `≤ −5 °C → 1.0`.
- **Denní chod:** × 1.2 ráno 5–9 h a večer 16–22 h, × 0.7 v noci 23–4 h (dohořívá), omezit na 1.
- **Který dům:** deterministicky – `hash(id_komína, herní_den) / max < p` → mezi dny se to mění, ale
  během dne neblikne (při změně teploty se přepočítá jen práh).
- **Síla kouře** (množství, sytost): roste s mrazem; ráno při zatápění tmavší, pak světlejší.
- **Vítr:** kouř se ohýbá po větru (`wind_vector`), nad ~6 m/s se trhá a leží níž.
- **Inverze / mlha** (`fog > 0.4` nebo mráz za bezvětří ráno): kouř stoupá jen pár metrů a pak se rozlévá vodorovně.
- **Déšť:** méně viditelný (kratší život částic).

## 3. Implementace
- Nový `scripts/priroda/chimney_smoke.gd` (`class_name ChimneySmoke extends Node3D`), u klienta
  (`LocalClient` jej vytvoří vedle `season_fx`).
- Každé ~2 s vezmi komíny do ~350 m od kamery (`BuildingDetails.chimneys_near`), aktivuj **pool**
  max. ~24 emitorů (`GPUParticles3D`, sdílený `ParticleProcessMaterial` + quad s měkkou texturou kouře
  z `NoiseTexture2D` / gradient – bez externích souborů), přiřaď je nejbližším kouřícím komínům.
  Parametry emitoru (množství, rychlost stoupání, `gravity` = vítr, škála, barva) nastav podle pravidel.
- Daleké komíny (350–900 m): levnější varianta – jeden `MultiMesh` „sloupků“ kouře (billboard quady),
  aktualizace jednou za 10 s. Volitelné, pokud zbývá kontext.
- F2 → Počasí: nic nového; pro test stačí změnit datum / teplotu. Pokud `Weather` nemá způsob nastavit
  teplotu, přidej do F2 → Počasí řádky „Teplota −10 / 0 / +10 / +20 °C“ (vynucení jako `forced_frost` – najdi, jak funguje).

## 4. Hotovo, když
- V mrazu kouří skoro všechny domy, kolem nuly většina, na jaře jen některé, v létě ojediněle.
- Kouř jde po větru, v mlze / inverzi zůstává nízko, během dne „neblikne“ na jiný dům.
- Výkon: max. ~24 aktivních emitorů.

## 5. Návrh checklistu ručních testů
1. F2 → Datum leden, Počasí jasno, Teplota −10 °C, ráno 7:00 → skoro všechny komíny kouří, sytě.
2. Teplota +10 °C → kouří jen některé; +20 °C → výjimečně.
3. Vítr silný (bouřka) → kouř se ohýbá a trhá.
4. Mlha ráno → kouř se drží nízko nad střechami.
5. Stůj 2 herní hodiny u stejného domu → kouř nepřeskakuje mezi domy.
6. FPS v obci s kouřem podobné jako bez něj.

## 6. Závěr
README (Systémy → Počasí / Budovy), `ZVIRATA.md` (kapitola počasí – tabulka kouře), VIZE odškrtnout, roadmapa README,
PROJECT_LOG, deník AI, commit „M1.3 Kouř z komínů: …“, checklist a čekat.
