# M5.7 – Skateboard s animacemi

> Roadmapa „Život na vsi“ · **M5 Obec a volný čas** · krok 7/9
> Předpoklady: M0.3 (dovednost `skateboarding`) · Navazují: M5.8 (U-rampa za domem)

## 0. Než začneš – přečti
1. `prompts/roadmapa/00_SPOLECNE.md`
2. `docs/VIZE_A_ROADMAPA.md` – kap. 4.5 „Skateboard (2)“
3. `scripts/car.gd` – jak funguje kolo Favorín (`two_wheeler`, šlapání bez motoru, `_balance`, pád jezdce při nárazu) –
   grep `bike|kolo|pedal|two_wheeler`; `scripts/bike_model.gd` (hlavička, rozměry)
4. `scripts/player.gd` – `enter_car` / `exit_car` / `_exit_spot`, `fall(duration, reason)`, `knock`
5. `scripts/humanoid.gd` – `_process` (pózy v autě / na kole: grep `seated|riding|bike`), `_leg_ik`, `_arm_ik`, `land`
6. `scripts/world.gd` – `player_action("car_enter")` (nasednutí na kolo/motorku do 2,6 m), `nearest_enterable_car`

## 1. Proč
Uživatel: „přidat skateboard i s animacemi“. Nový způsob pohybu s vlastní dovedností a triky; v M5.8 k němu
přibude U-rampa za domem.

## 2. Návrh – dvě možnosti, vyber **B**, pokud A nevychází
- **A)** skateboard jako další „vozidlo“ v `Car` (jako kolo) – výhoda: nasednutí F, kamera, kolize; nevýhoda: `VehicleBody3D`
  se špatně hodí na rampu a triky.
- **B) doporučeno:** skateboard jako **režim pohybu hráče** (`Player.board := true`) – vlastní fyzika v `Player._physics_process`
  (větev `if board:`), deska je vizuál pod nohama (`BoardModel` přes MeshKit: deska 80 × 20 cm, 4 kolečka, trucky).
  Hráč zůstává `CharacterBody3D` → funguje na rampě, schodech (spadne), obrubnících.

## 3. Fyzika a ovládání (režim B)
- **F** u ležícího skateboardu / Tab → „Stoupnout na prkno“ (skateboard je předmět v inventáři typu `gear`; když ho hráč
  nemá v ruce, položí ho před sebe). F znovu = seskočit (prkno zůstane ležet / vezme do ruky).
- **W** = odraz nohou (impulz +1,5 m/s, animace odrazu zadní nohou), max. rychlost po rovině ~6 m/s (odraz), z kopce víc
  (gravitace podél svahu – rychlost roste, nad 12 m/s „wobble“ – kmitání, nad 15 m/s pád), **S** = brzda (patou – tření),
  **A/D** = zatáčení (poloměr podle rychlosti, náklon těla), **Mezerník** = **ollie** (skok 0,3–0,5 m podle úrovně, deska drží
  pod nohama), **Shift** = přikrčení (rychlost v zatáčce).
- Povrch: asfalt ideální, štěrk / tráva → rychle zastaví a hráč přepadne dopředu (pád), mokro → klouže, sníh → nejde.
- **Pád:** náraz do zdi / obrubníku nad 3 m/s, dopad z výšky > 1,5 m bez správného natočení, prudký úhel → `fall(1.5, "pad_skate")`,
  `hurt` malé, prkno odjede (fyzikální objekt). Opilost → víc pádů.
- **Triky** (od úrovně): `kickflip` (Mezerník + A/D ve vzduchu, úroveň 3), `shove-it` (Mezerník + S, 2), `manual` (Shift + W
  na rovině – balanc pruh, 4), `grind` na obrubníku / zábradlí (skok na hranu, 8 – detekce hrany: paprsek dolů, výška
  0,1–0,6 m, dlouhá hrana), `180` (A/D držet ve vzduchu). Trik = animace desky (rotace kolem osy) + hráče; úspěšný dopad =
  deska pod nohama rovně ± 25° → skóre a XP, jinak pád.
- **Skóre:** HUD kombinace („Kickflip + Grind 180 = 350“), rekord uložen.
- **Animace (humanoid):** postoj bokem (levá noha vpředu), odraz, přikrčení, balanc paží, skok s přitaženými koleny, pád.
  Nohy drží na desce IK (`_leg_ik` – cíl = body na desce).
- Kamera: 3. osoba mírně níž a dál, FOV podle rychlosti (existující logika).
- **Zákon / pověst:** jízda po silnici v obci je OK; po chodníku mezi lidmi rychle → vesničané nadávají (pověst −1 drobně);
  hluk v noci (22–6) → sousedé si stěžují (mladez +, sousedé −).

## 4. Nákup
Skateboard v e-shopu (M3.4) nebo ve stavebninách v „Sportu“ (M5.1) za 1 890 Kč; test: F2 → Hráč → „dát skateboard“.

## 5. Hotovo, když
- Na skateboardu jde jezdit (odraz, zatáčení, brzda, jízda z kopce), dělat ollie a základní triky, padat; animace hráče
  odpovídají; skóre a XP; stav se ukládá (skateboard v inventáři / ležící ve světě).

## 6. Návrh checklistu ručních testů
1. F2 → dát skateboard; F u prkna → stoupnout; W odraz, A/D zatáčení, S brzda.
2. Z kopce u silnice → rychlost roste, wobble, pád nad hranicí.
3. Na trávu → přepadneš dopředu.
4. Ollie na obrubník; po úrovni 3 kickflip.
5. Grind na obrubníku (úroveň 8 – cheat XP).
6. Opilý → častější pády.
7. V noci v obci → stížnost sousedů.
8. F5/F9 → skateboard a rekord zůstanou.

## 7. Závěr
README (Systémy → Skateboard, Ovládání), VIZE odškrtnout, roadmapa README, PROJECT_LOG, deník AI, commit „M5.7 Skateboard: …“, checklist a čekat.
