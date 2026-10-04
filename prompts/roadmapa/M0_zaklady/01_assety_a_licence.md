# M0.1 – Pipeline a registr legálních assetů

> Roadmapa „Život na vsi“ · **M0 Základy** · krok 1/6
> Předpoklady: žádné · Navazují: všechny kroky, které přidávají modely / zvuky / hudbu (M1.4–M1.6, M2, M5, M6)

## 0. Než začneš – přečti
1. `prompts/roadmapa/00_SPOLECNE.md` (povinné – pravidla, mapa kódu, konvence)
2. `docs/VIZE_A_ROADMAPA.md` – kap. 2.1 a **2.2 Legální assety**
3. `README.md` – oddíly „Licence dat“ a „Právní zásady obsahu“
4. `VLASTNI_VOZIDLA.md` – jak se dnes načítá vlastní `.glb` (`models/`, `CarModel._build_from_scene`)
5. `scripts/hud.gd` – jen konstanty `DISCLAIMER`, `CREDITS` a místo, kde se zobrazují (grep `CREDITS`)
6. Konec `PROJECT_LOG.md`

## 1. Proč
Uživatel chce do hry přidávat volně dostupné modely, textury, zvuky a hudbu z internetu, ale jen takové,
které jde **legálně použít ve hře, která se bude veřejně (i placeně) šířit**. Potřebujeme jednotné místo,
evidenci licencí a automatické titulky, aby se na žádný CC BY asset nezapomnělo a žádný zakázaný
(NC, ND…) se do hry nedostal.

## 2. Současný stav
- Textury a HDRI jsou z Poly Haven (CC0), uvedené v `Hud.CREDITS` ručně.
- Vlastní vozidla lze načíst z `.glb` (viz `VLASTNI_VOZIDLA.md`), jinak je vše procedurální (`MeshKit`).
- Žádný registr licencí neexistuje.

## 3. Co udělat
1. **Struktura složek** v `assets/`:
   ```
   assets/
     LICENSES.md          # registr (tabulka) – jediný zdroj pravdy
     licenses/            # plné texty licencí (CC0.txt, CC-BY-4.0.txt …) a stažené README autorů
     models/<kategorie>/<nazev>/   # .glb/.gltf + textury (kategorie: vozidla, nabytek, zvirata, nastroje, budovy, ruzne)
     textures/<nazev>/
     sounds/<kategorie>/<nazev>.ogg
     music/<nazev>.ogg
   ```
   Do každé prázdné složky dej `.gitkeep`. Zkontroluj `.gitignore`, ať se `assets/` necommitují jen
   importní soubory (`*.import` Godot vytváří sám – ty se v projektu commitují, drž stávající zvyk; ověř `git ls-files | grep import | head`).
2. **`assets/LICENSES.md`** – úvod (pravidla z VIZE kap. 2.2: povolené / podmíněné / zakázané licence,
   co je „odbrandování“) a tabulka:
   `| id | soubor(y) | název | autor | zdroj (URL) | licence | staženo | úpravy | použití ve hře |`
   Vyplň už používané assety (Poly Haven textury a HDRI – najdi je grepem v `textures/`, `shaders/`,
   `map_loader.gd`, `local_client.gd`).
3. **Strojově čitelná kopie** `assets/licenses.json` (pole objektů se stejnými klíči) – z ní se generují
   titulky. Napiš jednoduchý nástroj `tools/assets_check.py` (Python 3, bez závislostí):
   - projde `assets/` a ohlásí soubory (`.glb .gltf .png .jpg .ogg .wav .mp3`), které **nejsou** v `licenses.json`,
   - ohlásí záznamy s licencí mimo povolený seznam (`CC0`, `PD`, `CC-BY-3.0`, `CC-BY-4.0`, `OGA-BY`,
     `royalty-free-game`) → chyba,
   - vygeneruje `data/credits.json` (jen záznamy s licencí vyžadující uvedení autora),
   - vypíše souhrn. (Nástroj je pro uživatele – **nespouštěj ho**, jen napiš a popiš v README.)
4. **Titulky ve hře:** `hud.gd` – k pevnému `CREDITS` připoj řádky z `data/credits.json`
   (když soubor chybí, nic se neděje). Zobrazí se v nápovědě F1 (tam, kde je dnes `CREDITS`).
5. **Návod** `ASSETY.md` (odkaz z README → Návody):
   - kde hledat (Poly Haven, ambientCG, Kenney, Quaternius, Poly Pizza, Sketchfab s filtrem CC0/CC BY,
     Freesound s filtrem CC0/CC BY, OpenGameArt – kontrolovat licenci každého souboru),
   - checklist před použitím (licence dovoluje komerční šíření a úpravy? uvést autora? je na modelu logo /
     SPZ / nápis značky → odstranit v Blenderu),
   - import do Godotu: `.glb`, měřítko 1 j = 1 m, −Z dopředu, počátek na zemi, LOD (`visibility_range_end`),
     kolize (jednoduchý tvar), materiály (vertex colors nebo PBR), zvuky `.ogg` 44,1 kHz mono pro 3D zvuky,
   - zápis do `LICENSES.md` + `licenses.json`, spuštění `tools/assets_check.py`.
6. **Pomocná funkce pro načítání** `scripts/asset_lib.gd` (`class_name AssetLib`, statické funkce):
   - `load_model(path: String) -> Node3D` – načte `.glb` (PackedScene) nebo vrátí `null` s `push_warning`,
     když soubor chybí (hra musí jít i bez assetu – volající pak použije procedurální náhradu),
   - `load_sound(path: String) -> AudioStream` – totéž pro zvuk,
   - `has(path) -> bool`.
   Nikde ji zatím nepoužívej povinně – je to základ pro další kroky.

## 4. Mimo rozsah
Stahování konkrétních assetů (dodá uživatel), výměna existujících procedurálních modelů.

## 5. Hotovo, když
- Existuje `assets/` se strukturou, `LICENSES.md`, `licenses.json` (s Poly Haven záznamy), `ASSETY.md`,
  `tools/assets_check.py`, `scripts/asset_lib.gd`; F1 ukazuje i titulky z `data/credits.json`, když existuje.
- Hra bez jediného nového assetu funguje stejně jako dřív.

## 6. Návrh checklistu ručních testů
1. `python3 tools/assets_check.py` → vypíše souhrn, žádná chyba pro stávající assety, vznikne `data/credits.json`.
2. Přidej do `assets/sounds/ruzne/` libovolný `.ogg` bez záznamu → nástroj ho ohlásí jako neevidovaný.
3. Do `licenses.json` dej testovací záznam s `CC-BY-NC-4.0` → nástroj hlásí chybu licence.
4. `./run.sh` → hra se spustí jako dřív; F1 → dole jsou titulky včetně řádků z `credits.json`.
5. Smaž `data/credits.json` → F1 funguje, ukazuje jen pevné titulky.

## 7. Závěr
README (Návody → `ASSETY.md`, Licence dat), VIZE (odškrtnout M0.1), `prompts/roadmapa/README.md`, PROJECT_LOG,
deník efektivity AI, commit „M0.1 Assety a licence: …“, checklist a čekat.
