# M8.4 – Pole větru: nárazy, závětří a hierarchický ohyb vegetace

> Roadmapa **M8 Realistický svět** · krok 4/19 · vlna 3
> Předpoklady: M8.1 (M8.2 `Site.wind_exp` použij, pokud je; jinak fallback) · Navazují: M8.8, M8.9, M8.13, M8.14, M8.18, létání
> Zavádí API: `WindField` / `World.wind_field`, shader globals `wind_dir`, `wind_speed`, `wind_gust`, `wind_time`, **konvence barev vrcholů** (00_PRINCIPY kap. 4)

## 0. Než začneš – přečti
1. `00_SPOLECNE.md`, `M8_realismus/00_PRINCIPY.md` (kap. 3, 4, 8 – vítr)
2. `scripts/priroda/weather.gd` – `wind`, `wind_bearing`, `wind_vector()` (`grep -n "wind"`)
3. `shaders/tree.gdshader` (celý, 81 ř.), `shaders/vegetation.gdshader`, `scripts/vegetation/vegetation_manager.gd` (`grep -n "wind"`)
4. `project.godot` → `[shader_globals]` (`wind_strength` – dnešní globální vítr)
5. Kdo vítr ještě používá: `grep -rn "wind_vector\|weather.wind\b" scripts | cut -c1-120` (letadla `flight/`, dron, kouř, oheň, rybaření, zvěř-čich)

## 1. Proč
Dnes je vítr jedno číslo a stromy se kývou sinusovkou, všechny stejně. Skutečný vítr má **nárazy, které běží krajinou** (vlna přes obilí,
v lese šumí koruny postupně), je slabší v závětří a u země, silnější na hřebeni, a strom se ohýbá **po úrovních** (kmen pomalu, větve
rychleji, listí se třepetá). Je to jeden z nejsilnějších vizuálních signálů „živého“ světa.

## 2. Co udělat
- **`scripts/eko/wind_field.gd`** (`class_name WindField`, `World.wind_field`, simulace – deterministická z času a seedu):
  - `wind_at(pos: Vector3) -> Vector3` (m/s): směr a střední rychlost z `Weather` (10 m nad zemí) × **logaritmický profil** podle výšky nad
    terénem a drsnosti (`z0`: louka 0,03 m, pole 0,1, les 1,0, zástavba 0,8 – z `surface`) × **expozice** (`Site.wind_exp`, fallback 1)
    × **nárazy**: 2D šum posouvaný ve směru větru rychlostí větru (Taylor), intenzita turbulence 0,15–0,35 podle drsnosti a bouřky.
  - `gust_at(pos)` 0..1, `turbulence_at(pos)` (pro dron / paraglide / trike – stoupavé a padavé proudy v závětří lesa a hran).
  - Rychlé: žádné alokace, šum přes `FastNoiseLite` se seedem, volání stovkykrát za snímek musí stát < 0,1 ms.
- **Klient – shader globals** (`project.godot` + nastavení v `Atmosphere`/`SeasonFx` každý snímek): `wind_dir` (vec2, jednotkový),
  `wind_speed` (m/s), `wind_gust` (**sampler2D** – stejný šum jako `WindField` vypečený do 256² textury posouvané `wind_time`, aby
  vizuál souhlasil se simulací), `wind_time`. `wind_strength` ponech pro zpětnou kompatibilitu (= speed/12).
- **Hierarchický ohyb** – nová sdílená funkce `shaders/include/wind.gdshaderinc`: `vec3 wind_bend(vec3 vertex_local, vec3 origin_w,
  vec4 col, float height, float stiffness)`:
  1. kmen: ohyb ∝ (y/height)² ve směru větru × rychlost² (síla větru ∝ v²), pomalý kmit (vlastní frekvence ∝ 1/výška),
  2. větve: podle `COLOR.r` (ohebnost) a `COLOR.g` (fáze), rychlejší kmit,
  3. listy: třepetání podle `COLOR.b`, vysoká frekvence, amplituda podle nárazu,
  4. náraz z `wind_gust` ve světové poloze → vlna prochází korunami postupně.
  Napoj do `tree.gdshader` (dnešní meshe barvy vrcholů nemají → **odvoď `r` z výšky vrcholu a vzdálenosti od osy**, `g` z hashe polohy,
  `b` = `is_leaf`; přesné barvy dodá generátor M8.8) a do `vegetation.gdshader` (tráva a obilí: ohyb od kořene, **vlny přes pole**).
- **Konvence barev vrcholů** (00_PRINCIPY kap. 4) zapiš i do hlavičky `wind.gdshaderinc`, ať ji M8.8 dodrží.
- **Napojení simulace** (malé hunky, každý jen pokud jde čistě): letadla / paraglide / trike / dron berou vítr z `wind_field.wind_at`
  místo `Weather.wind_vector()` (fallback zachovat); kouř z komínů a ohně (`chimney_smoke.gd`, `fire_fx.gd`) unáší směr + náraz;
  čich zvěře (`animal.gd` – vítr v zádech) z `wind_at` v poloze zvířete. Každé napojení za přepínačem `wind`.
- **Bouřka:** při nárazu > 20 m/s víc třepetání, padající listí / jehličí (částice u kamery, max. 300), zvuk větru v korunách
  hlasitější v lese (`Atmosphere` `_wind_snd` podle `gust_at` u kamery a hustoty stromů).
- **Ladicí vrstva** `vitr` (šipky / barva rychlosti 10 m nad zemí) a měřicí scéna `louka_vitr` (M8.1) se silným větrem.

## 3. Minimum
`WindField.wind_at` s profilem a nárazy, shader globals + vypečená textura nárazů, hierarchický ohyb ve stromech a v trávě/obilí (vlny přes pole),
létání a kouř berou vítr z pole.

## 4. Hotovo, když
- Za větru jde přes obilí viditelná vlna ve směru větru; stromy se nehýbou synchronně; za bezvětří je klid.
- Paraglide nad hřebenem cítí silnější vítr než v údolí; kouř z komínů se sklání po větru.

## 5. Návrh checklistu ručních testů
1. F2 → Počasí → Bouřka → stát u pole s obilím (léto) → vlny běží přes pole po větru.
2. Les v bouřce → koruny se ohýbají postupně, padá listí; hučení v korunách.
3. F2 → Jasno, bezvětří → stromy téměř nehybné.
4. Mapa M → vrstva Vítr: hřebeny silnější, údolí a les slabší.
5. Paraglide (M6.4) nad hřebenem vs. v údolí → jiný drift.
6. Komíny v zimě za větru → kouř se sklání po větru.
7. `--perfscene=louka_vitr` → zapsat ms (cíl: +≤ 0,3 ms GPU proti stavu před krokem).

## 6. Závěr
`docs/SYSTEMS.md` (Vítr), README, PROJECT_LOG, `docs/testy_M8.md`, commit „M8.4 Pole větru: …“.
