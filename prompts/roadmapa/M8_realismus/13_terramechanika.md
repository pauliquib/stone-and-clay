# M8.13 – Terramechanika: bláto, zaboření, koleje a stopy

> Roadmapa **M8 Realistický svět** · krok 13/19 · vlna 5
> Předpoklady: **M8.7 (`SoilWater.mud_at`, `moisture_at`, `snow_at`)**, M8.2 (`Site` – textura půdy, únosnost) · Navazují: M8.14 (sešlapané pěšiny), M8.19

## 0. Než začneš – přečti
1. `00_SPOLECNE.md`, `M8_realismus/00_PRINCIPY.md` (kap. 6, 8 – terramechanika)
2. `scripts/car.gd` – kola a přilnavost (`grep -n "class Wheel\|func _surface_grip\|tire_grip\|suspension\|_physics_process" scripts/car.gd | head -30`; výřezy kolem),
   `scripts/tractor_model.gd`, `scripts/hand_cart.gd` (vozík), `scripts/fauna/horse.gd` (kopyta, bláto)
3. `scripts/priroda/tracks.gd` (stopy ve sněhu – MultiMesh, kruhový buffer, vyblednutí) – vzor pro stopy v blátě
4. `shaders/terrain.gdshader` (`grep -n "uniform\|wetness\|snow" shaders/terrain.gdshader | head -40`), `scripts/terrain.gd`
5. `scripts/player.gd` – chůze na mokru / sněhu (`grep -n "grip\|slip\|wetness" scripts/player.gd | head`)

## 1. Proč
Dnes je terén pro auto „asfalt s menší přilnavostí“. Po týdnu deště ale auto na rozmáčené louce **zapadne**, traktor nechává **hluboké koleje**,
které tam zůstanou do sucha, polní cesta má vyjeté koleje s loužemi a hráč v blátě klouže a boří se. To je fyzika, kterou na vsi zná každý.

## 2. Co udělat
- **`scripts/eko/terramech.gd`** (`class_name Terramech`, statické funkce + konstanty): pro kontakt kola / nohy s terénem v bodě:
  - únosnost a tuhost půdy z textury (`Site.soil` → `SOIL_PROPS`) × vlhkost (`SoilWater.moisture_at`) × mráz (zamrzlá = tvrdá) × sníh;
  - **zaboření** (sinkage) podle tlaku kola (hmotnost na kolo / kontaktní plocha z šířky pneumatiky) – Bekkerův vztah zjednodušeně
    `z = (p / (k_c/b + k_φ))^(1/n)`, s konstantami v tabulce;
  - **odpor valení** ∝ zaboření (kompakční odpor), **tažná síla** omezená smykem půdy (Mohr–Coulomb: c + p·tan φ) a **prokluz**;
  - výstup `{sinkage_m, roll_resist_n, max_traction_n, slip_k}`.
- **Auta a traktor (`car.gd`, za přepínačem `terramech`, jen kola na terénu – ne na asfaltu/štěrku):** v `_physics_process` kola na terénu
  počítají zaboření (kolo vizuálně klesne, podvozek níž), přidaný odpor valení a omezenou trakci → v hlubokém blátě auto **zapadne** (hrabe na místě),
  traktor s velkými koly projede, úzké kolo motorky se boří. Vyproštění: hráč tlačí (síla na auto), traktor táhne (lano jako `attach_trailer`
  – jen pokud je jednoduché, jinak otevřený bod), nebo jízda „kývání“ (dopředu-dozadu). Hlášky „Zapadl jsi v blátě.“
- **Koleje a stopy:** trvalá **deformační mapa** v okolí hráče (textura ~0,25 m/px na dlaždici 128×128 m, víc dlaždic v kruhovém cache,
  uložené jen změněné): kolo / kopyto / bota zapisuje hloubku podle zaboření; `terrain.gdshader` čte deformaci → **tmavší, mokrá, vyjetá stopa**
  (parallax / posun normál, ne skutečná geometrie; volitelně vertex posun na nejbližší dlaždici terénu na Vysoké). Koleje **pomalu mizí** podle
  sucha a deště (déšť je rozmáčí a zarovná, sucho je ztvrdí – zůstanou); vyjeté koleje zvyšují místní louže (M8.7 – prohlubeň).
  Stopy ve sněhu (`tracks.gd`) ponech; bláto používá stejnou myšlenku (MultiMesh otisků pro chodce / zvěř, deformační mapa pro kola).
- **Chodec a kůň:** bota v blátě – zpomalení a skluz podle `mud_at` (dnes globální `wetness` → lokální), zvuk čvachtání (`Sfx`), boty zablácené
  (barva v `humanoid`, jen jednoduchá vrstva – volitelné); kůň v hlubokém blátě zpomalí (už má – převést na lokální `mud_at`).
- **Ruční vozík** (`hand_cart.gd`): úzká kola se v blátě boří → těžké tlačení.
- **Ukládání:** deformační dlaždice s výraznými kolejemi (komprimovaně, max. ~2 MB v savu; staré dlaždice zapomenout po 60 dnech).
- Ladicí vrstva `unosnost` (aktuální únosnost půdy) a měřicí scéna `pole_leto` (jízda autem s kolejemi).

## 3. Minimum
`Terramech` se zaborem, odporem a trakcí; auto zapadne v rozmáčené louce a traktor projede; koleje v deformační mapě s vizuálem v terénu a postupným mizením;
chodec a kůň berou lokální bláto.

## 4. Hotovo, když
- Po týdnu deště osobní auto na louce v nivě zapadne, traktor projede a nechá koleje, které jsou vidět ještě po několika dnech sucha.
- Na stejné louce v suchém létě auto projede bez potíží.

## 5. Návrh checklistu ručních testů
1. F2 → 5 dní deště → osobní auto na louku v nivě → zpomalí, hrabe, zapadne.
2. Couvání / kývání → někdy se vyprostí; tlačení pěšky pomůže.
3. Traktůrek na stejné louce → projede, koleje jsou vidět.
4. Za 3 dny sucha → koleje pořád vidět, tmavé; za týden deště se rozmáčejí.
5. Léto v suchu → stejné auto projede bez potíží, jen prach.
6. Chůze blátem → zpomalení, čvachtání.
7. Ruční vozík s dřevem blátem → těžké tlačení.
8. F5/F9 → koleje zůstanou.
9. Přepínač Terramechanika vypnout → staré chování.
10. `--perfscene=pole_leto` → ms (cíl +≤ 0,3 ms CPU, +≤ 0,3 ms GPU).

## 6. Závěr
`docs/SYSTEMS.md` (Bláto a koleje), `VLASTNI_VOZIDLA.md` (šířka pneumatik, tlak na kolo – nové parametry `CarModel`), PROJECT_LOG, `docs/testy_M8.md`,
commit „M8.13 Terramechanika: …“.
