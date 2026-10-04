# M1.4 – Systém interiérů + interiér domova

> Roadmapa „Život na vsi“ · **M1 Živý svět** · krok 4/6
> Předpoklady: M0.1, M0.4 (interakce), M1.2 (dveře – nepovinně) · Navazují: M1.5, M2.2 (kamna), M2.3 (šatník), M3.4 (PC), M5 (hasičárna, šatny…)

## 0. Než začneš – přečti
1. `prompts/roadmapa/00_SPOLECNE.md` (kap. 3 – interiéry jsou **vymyšlené**)
2. `docs/VIZE_A_ROADMAPA.md` – kap. 4.1 „Interiéry“
3. `scripts/world.gd` – `_spawn_places`, `interactables`, `sleep`, `rest`, `teleport_player`, `blackout`, `skip_time` (grep)
4. `scripts/local_client.gd` – `_interact`, `open_place_menu` (co se dnes nabízí „doma“: spánek, lednička, kafe, oprava auta, rádio)
5. `scripts/place.gd` – `setup`, `_ready`, `door`, `KEEPERS` (obsluha), `scripts/radio.gd` – kde stojí rádio (grep `position`)
6. `scripts/player.gd` – `_check_roof` (déšť pod střechou), `teleport`
7. `scripts/humanoid.gd` – pózy (grep `lie|sit`) – ležení v posteli / sezení

## 1. Proč
Domy jsou zatím jen zvenku; „doma“ je nabídka u dveří. Chceme **vstoupit dovnitř**: domov hráče jako
základna (postel, lednička, kamna, šatník, stůl s PC, rádio), později hospoda, obchod, úřad…

## 2. Architektura (doporučené řešení – drž se ho)
- Stěny budov jsou spojené meshe s kolizí bez otvorů → interiér **není uvnitř** vnější budovy, ale
  v **odděleném prostoru** pod mapou (např. `y = −400 m`, pod domem; každý interiér jinde, mřížka 60 m).
- Vstup: E u dveří → krátké ztmavení 0,3 s (`blackout`/fade u klienta) → teleport do interiéru
  k vnitřním dveřím. Odchod: E u vnitřních dveří → zpět před dveře ven (pozice `door` + 1 m, otočený od domu).
- Uvnitř: vlastní `WorldEnvironment` není potřeba – stačí vnitřní světla (`OmniLight3D`, večer rozsvícené),
  okna jako světlé quady (denní světlo podle `Clock.daylight()`), zvuk deště tlumený. Počasí na hráče:
  interiér je „pod střechou“ (strop s kolizí → `_check_roof` funguje; ověř).
- Nový `scripts/interior.gd` (`class_name Interior extends Node3D`): `id`, `outside_door: Vector3`,
  `inside_door: Vector3`, `func build()`, seznam **interaktivních objektů** (registruje je do `World.interactables`
  jen když je v něm hráč) – `{pos, r, kind: "interior_obj", key, text}`.
- `World.interiors := {}` (id → Interior), `World.enter_interior(id_hráče, interior_id)`, `exit_interior`,
  `Player.inside := ""` (ukládá se; po načtení hráč uvnitř → správně umístit).
- NPC, doprava, fauna – beze změny (hráč je „pod mapou“; zkontroluj, že policie / zvěř / počasí nedělají
  nesmysly, když je hráč daleko pod terénem: např. `nearest_player` – vrať pozici venkovních dveří,
  pokud je hráč uvnitř: `World.player_anchor`/`player_pos` – grep, kde se používá, a vracej `outside_door`).

## 3. Interiér domova (procedurálně přes MeshKit, vymyšlený)
Přízemí ~9 × 7 m, výška 2,6 m: předsíň (věšák, boty), kuchyň (linka, sporák, **lednička**, stůl, 2 židle,
**kafe**), obývák (gauč, stolek, **rádio** – přesunout sem nebo nechat venku a přidat druhé místo pro ovládání;
drž jednu instanci `Radio` – přesuň ji sem a uprav interakci), ložnice (**postel** – spánek / odpočinek),
**kamna** na dřevo (zatím dekorace, funkci dodá M2.2), **šatní skříň** (M2.3), **pracovní stůl s PC** (M3.4),
okna se světlem, lampa (v noci). Rozměry reálné (dveře 0,8 × 2 m, postel 2 × 1,6 m, linka 0,9 m vysoko).

Interakce uvnitř (E): postel → stávající nabídka spánku (`World.sleep/rest`), lednička a kafe →
stávající nabídky z `open_place_menu("domov")` (přesměruj), rádio → `open_radio_menu`, oprava auta
zůstává **venku** u auta. Kamna / šatník / PC: text „(brzy)“.
Venkovní nabídka „domov“ u dveří: první položka „Vejít dovnitř“, ostatní nech kvůli zvyku (nebo je přesuň – uveď v logu).

## 4. Ukládání a F2
`save_game.gd`: `inside`. F2 → Teleport: „Domov – uvnitř“.

## 5. Hotovo, když
- Hráč vejde do domu a vyjde ven bez načítací obrazovky (jen krátké ztmavení); uvnitř jde spát, jíst,
  pít kafe, pustit rádio; déšť hráče uvnitř nemočí; policie / zvěř nereagují divně.
- F5/F9 uvnitř → po načtení hráč uvnitř.

## 6. Návrh checklistu ručních testů
1. `./run.sh` → dveře domu hráče → E → „Vejít dovnitř“ → ztmavení, jsi v předsíni.
2. Projdi místnosti – nábytek v reálných rozměrech, nic neprochází zdí, kamera 3. osoby nezajíždí za stěny (V pro 1. osobu).
3. Postel → vyspat do 7:00 → funguje jako dřív.
4. Lednička, kafe, rádio → nabídky fungují.
5. F2 → Počasí déšť, stůj uvnitř 10 min → nepromokneš.
6. Večer 21:00 → uvnitř svítí lampa, okna tmavá.
7. Odejdi ven → stojíš před dveřmi, otočený od domu.
8. F5 uvnitř, jdi ven, F9 → zpět uvnitř.

## 7. Závěr
README (Systémy → Interiéry, Ovládání), VIZE odškrtnout, roadmapa README, PROJECT_LOG, deník AI,
commit „M1.4 Interiéry: systém a domov: …“, checklist a čekat.
