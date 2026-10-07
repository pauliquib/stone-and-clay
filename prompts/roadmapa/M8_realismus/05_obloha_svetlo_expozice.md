# M8.5 – Fyzikální obloha, světlo a expozice

> Roadmapa **M8 Realistický svět** · krok 5/19 · vlna 2
> Předpoklady: M8.1 · Navazují: M8.9 (mlha, inverze), M8.16 (záření na tělo), M8.18 (soumrak pro ptáky), M8.19
> Zavádí API: `SkyModel` (v `Atmosphere`), `Atmosphere.exposure_ev`, `Atmosphere.sun_illuminance_lux()`, `sky_illuminance_lux()`

## 0. Než začneš – přečti
1. `00_SPOLECNE.md`, `M8_realismus/00_PRINCIPY.md` (kap. 6 výkon, kap. 8 obloha)
2. `scripts/priroda/atmosphere.gd` (celý, 330 ř.) a `shaders/sky.gdshader` (celý)
3. `scripts/local_client.gd` – tvorba `Environment` (`grep -n "env\." scripts/local_client.gd`), `scripts/game_settings.gd` (tonemapping, předvolby)
4. `scripts/clock.gd` – `sun_enu`, `moon_enu`, `sun_elevation`; `scripts/priroda/street_lights.gd` (M5.12 – světelný smog na obloze)
5. `shaders/terrain.gdshader` – jak se počítá barva terénu a mlha (`grep -n "fog\|FOG\|sun" shaders/terrain.gdshader`)

## 1. Proč
Obloha je dnes ručně namíchaný gradient a slunce má pevnou sílu. Skutečné světlo se mění o **6 řádů** (poledne ~100 000 lx, úplněk 0,25 lx),
má barvu podle tloušťky vzduchu (oranžové slunce nízko, modrá hodina po západu), vzdálené kopce modrají a blednou (vzdušná perspektiva)
a oko se přizpůsobuje. To je rozdíl mezi „hrou“ a „fotkou“.

## 2. Co udělat
- **Fyzikální model oblohy** v `sky.gdshader` (nová větev za přepínačem `sky`, stará zůstane jako fallback):
  - jednoduchý **Rayleigh + Mie** jednorozptyl s ozonem (Hillaire 2020 zjednodušeně / Preetham-like) – koeficienty jako uniformy,
    **předpočtená transmitance do LUT** (64×256, počítá se v GDScript / compute jednou při startu nebo shaderem do `SubViewport` jednou),
    obloha samotná vzorkovaná z LUT (levná per-pixel),
  - barva a síla **slunečního disku** podle vzdušné hmoty (air mass), limb darkening, **občanský / nautický / astronomický soumrak** plynule
    z `Clock.sun_elevation` (modrá hodina, zářící obzor po západu, Belt of Venus naproti),
  - mraky ponech dnešní (`cloud_cover`, `cloud_dark`) – jen je **osvětli** barvou slunce z transmitance (zlaté okraje při západu),
  - opar (`haze`) jako zvýšení Mie (vlhko, mlha), světelný smog (M5.12) zůstává jako přídavek.
- **Světlo scény ve fyzikálních jednotkách:** `sun.light_intensity_lux` = sluneční osvětlenost × transmitance (bez mraků ~100 000 lx v poledne
  léta), měsíc podle fáze (úplněk ~0,25 lx), hvězdy + noční obloha ~0,001 lx; ambient z oblohy (sky contribution) podle stejného modelu.
  Godot 4.3: **physical light units** (`ProjectSettings rendering/lights_and_shadows/use_physical_light_units`) + `CameraAttributesPhysical`
  nebo `CameraAttributesPractical` – vyber, co v 4.3 funguje stabilně (ověř v dokumentaci verze 4.3, napiš proč). Pokud by přechod na fyzikální
  jednotky rozbil interiéry / lampy (M5.12 pool světel) / auta, zaveď převod `lux → energy` v jedné funkci a fyzikální jednotky zapni jen
  pro venkovní slunce/měsíc/oblohu. Interiéry a umělá světla nesmí zčernat ani přepálit – zkontroluj všechna `OmniLight3D`/`SpotLight3D`
  (`grep -rn "OmniLight3D.new\|SpotLight3D.new" scripts`) a uprav jejich energie jednou tabulkou.
- **Expozice (adaptace oka):** `Atmosphere.exposure_ev` – cílová EV z osvětlenosti (EV100 = log2(lux/2,5)), plynulá adaptace (do tmy pomalu
  ~20 s reálně, do světla rychle ~2 s), omezení min/max (noc nesmí být černá – hra je hratelná za úplňku i bez lampy, jen tmavá a modravá:
  **Purkyňův posun** = desaturace a posun do modra pod ~1 lx). Vstup do interiéru / výstup ven = viditelné oslnění a přizpůsobení.
- **Vzdušná perspektiva:** vzdálený terén a krajina za okrajem (M6.2) modrají a světlají podle vzdálenosti a vlhkosti – buď `Environment`
  fog s barvou z modelu oblohy ve směru pohledu (levné, `fog_sky_affect`), nebo funkce v `terrain.gdshader` / `surroundings.gdshader`.
- **Stíny mraků:** posouvaná maska stejného šumu jako mraky (`cloud_offset`) promítnutá na terén a vegetaci (global uniform), jen přes den.
- **Předvolby:** Nízké = dnešní obloha; Střední = fyzikální obloha + expozice; Vysoké = + stíny mraků + vzdušná perspektiva v terénu.
- **API pro další kroky:** `sun_illuminance_lux()`, `sky_illuminance_lux()`, `global_horizontal_irradiance_wm2()` (W/m², pro M8.16 a fotosyntézu
  M8.12), `is_civil_twilight()`.
- Měřicí scény: `ves_poledne`, `udoli_noc`, nová `zapad_slunce` (datum + hodina západu, kamera na západ).

## 3. Minimum
Fyzikální obloha s LUT a soumraky, slunce a měsíc v luxech (nebo převodem) s expozicí a adaptací, noc hratelná (Purkyně), interiéry beze změny vzhledu,
přepínač zpět na starou oblohu.

## 4. Hotovo, když
- Západ slunce má oranžové slunce, růžový pás naproti a modrou hodinu; v poledne je obloha u obzoru světlejší než v zenitu.
- Vyjití ze dveří za slunného dne oslní a do ~2 s se srovná; za úplňku je krajina tmavě modrošedá, ale čitelná.

## 5. Návrh checklistu ručních testů
1. F2 → Čas 20:30 v červnu, jasno → západ: oranžový disk, pás Venuše na východě, pak modrá hodina.
2. Poledne v létě vs. v prosinci → zimní slunce nízko, slabší a teplejší barvou.
3. Noc za úplňku na louce → vidět cestu a obrysy, barvy potlačené.
4. Noc v novu v lese → velmi tma (baterka / lampy důležité).
5. Ze sklepa / interiéru ven v poledne → krátké oslnění.
6. Vzdálené kopce (dron 200 m) → modravé a světlejší s vzdáleností.
7. Polojasno → stíny mraků běží po krajině.
8. Lampy v obci (M5.12) a světla aut svítí stejně jako dřív (ne přepálené / zhasnuté).
9. Přepínač Obloha vypnout → stará obloha.
10. `--perfscene=ves_poledne` a `zapad_slunce` → ms GPU (cíl +≤ 0,8 ms na Střední).

## 6. Závěr
`docs/SYSTEMS.md` (Obloha a světlo), README (předvolby), PROJECT_LOG, `docs/testy_M8.md`, commit „M8.5 Fyzikální obloha a expozice: …“.
