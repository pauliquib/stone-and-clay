# M5.12 – Pouliční osvětlení a světelný smog

> Roadmapa „Život na vsi“ · **M5 Obec a volný čas** · krok 12/12 (doplněk od uživatele, 6. 10. 2026)
> Předpoklady: žádné (lze kdykoli po M0; souběžně s M5.11 – jiné soubory) · Navazují: M7.4 (starosta: úsporné LED /
> vypínání lamp v noci jako projekt s dopadem na rozpočet a hvězdy), V2
> Proč zvlášť od M5.11 (řidiči): jiná oblast kódu (svět, obloha, osvětlení), malý krok na jedno okno.

## 0. Než začneš – přečti
1. `prompts/roadmapa/00_SPOLECNE.md` (kap. 5.5 – výkon: MultiMesh, LOD, žádné stovky světel se stíny)
2. `scripts/prop_models.gd` – `street_lamp()` (~ř. 203 – model lampy **existuje, ve světě ale nestojí**)
3. `scripts/world.gd` – rozmístění vybavení ulic (`"Vybaveni_ulic"`, ~ř. 864–900: kandidáti z `graph.nodes_within`,
   odstup od křižovatek, `dist_to_roads`) – **vzor rozmístění lamp**
4. `scripts/priroda/atmosphere.gd` (obloha, `sky_mat`, `cloud_cover` ~ř. 215) + `shaders/sky.gdshader` (hvězdy ~ř. 55–62:
   `star * night * (1 − cloud_cover)`)
5. `scripts/clock.gd` – `is_night()`, sluneční výška; `scripts/game_settings.gd` – grafické předvolby (`PRESETS`, `gfx`)
6. `scripts/building_details.gd` / okna (M1.2 – svítící okna v noci, grep `window|okn|emiss`) – ať lampy ladí s okny

## 1. Proč
V noci je dnes obec tmavá a obloha nad ní stejně hvězdná jako nad lesem. Uživatel chce **pouliční osvětlení** a **světelný
smog** – v obci je vidět méně hvězd, za obcí v poli a v lese víc. Venkov tím dostane noční atmosféru a důvod jít se v noci
dívat na hvězdy za vesnici.

## 2. Co udělat
### 2.1 Lampy veřejného osvětlení
- Rozmísti lampy podél silnic v obci (`residential`, `tertiary`, `unclassified`, `living_street`; ne `service` / `track`)
  po ~30–40 m, střídavě po stranách, ne na křižovatce ani v cestě (vzor „Vybavení ulic“, `dist_to_roads`), deterministicky
  (seed). Odhad 150–300 lamp → model jako **MultiMesh** (`PropModels.street_lamp`), kolize jen jednoduchý válec u bližších
  (nebo žádná – rozhodni a zapiš).
- **Světlo:** svítící hlavice (emisní materiál – vidět z dálky, levné) + skutečné `OmniLight3D` / `SpotLight3D` **jen pro
  nejbližších ~12–16 lamp u kamery** (pool světel, přesun podle polohy hráče, bez stínů nebo stíny jen u 2–3 nejbližších
  podle grafické předvolby `GameSettings`). Na zemi pod lampou volitelně decal / světlý kruh pro vzdálené lampy.
- Rozsvícení za soumraku, zhasnutí za svítání (`Clock` – sluneční výška), postupně s náhodným zpožděním; noční režim
  (např. 0–4 h každá druhá lampa zhasnutá – úspora, nastavitelné konstantou; navazuje M7.4).
- Rozbitá lampa (zásah zbraní / kamenem – `Prop.damaged` vzor) → nesvítí, `poskozeni_cizi_veci` (svědek M4.4), obec ji
  za pár dní opraví.

### 2.2 Světelný smog a hvězdy
- **Index světelného smogu** v místě kamery: 0 (les / pole daleko od obce) … 1 (náves) – z hustoty lamp a svítících oken
  v okolí (předpočítaná hrubá mřížka, např. 64 m buňky, a interpolace), plus slabý příspěvek okolních obcí ve směru
  k nim (`World.obce` – středy; nad obcemi na horizontu světlý opar).
- `sky.gdshader`: nový uniform `light_pollution` (0..1) – snižuje počet a jas hvězd (posun prahu `step(0.9965, …)` a jasu),
  zesvětlí noční horizont teplým oparem (sodíkové / LED – barva konstantou), víc při oblačnosti (mraky nasvícené zespodu).
  `atmosphere.gd` ho nastavuje plynule podle polohy kamery a toho, jestli lampy svítí.
- Zážitek: v lese za obcí je Mléčná dráha výrazná (volitelně jemný pás hvězd – jen když je to levné v shaderu), na návsi
  jen pár nejjasnějších hvězd. Drb / hláška vesničana („za humny je v noci vidět Mléčná dráha“).

### 2.3 Nastavení a výkon
- Grafické předvolby: počet dynamických světel lamp (0 / 8 / 16), stíny lamp ano / ne. Na nejnižší předvolbě jen emisní hlavice.
- Ladicí parametr / F2 → Počasí: přepínač „Světelný smog ×0 / ×1 / ×2“ pro porovnání.

## 3. Minimum
Lampy podél silnic v obci (MultiMesh, emisní hlavice, pool dynamických světel, rozsvícení podle slunce) a uniform
`light_pollution` v obloze podle vzdálenosti od obce.

## 4. Hotovo, když
- V noci svítí lampy v obci, z dálky jsou vidět jako řada světel; FPS na návsi v noci srovnatelné s dneškem.
- Na návsi je vidět méně hvězd a horizont je světlejší; v lese za obcí je obloha plná hvězd.

## 5. Návrh checklistu ručních testů
1. F2 → Čas 21:00, jasno → náves: lampy svítí, světlo na silnici, málo hvězd.
2. Dojdi / teleportuj se do lesa 1 km od obce → hvězd výrazně víc, nad obcí světlý opar.
3. Svítání → lampy postupně zhasnou.
4. 1:00 → noční režim (část lamp zhasnutá).
5. Grafika nízká → jen svítící hlavice, FPS v pořádku; vysoká → světla se stíny u nejbližších.
6. Zásah lampy (zbraň M2.8) → zhasne, svědek → přestupek; za pár dní opravená.
7. Zataženo v noci → nad obcí nasvícené mraky.

## 6. Závěr
README (Systémy → Svět / noc, Ladicí parametry), VIZE odškrtnout, roadmapa README, PROJECT_LOG, commit
„M5.12 Pouliční osvětlení a světelný smog: …“, checklist a čekat.
