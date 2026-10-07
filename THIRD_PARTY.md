# Licence třetích stran

Součásti vytvořené třetími stranami, které jsou součástí tohoto repozitáře (vendored
v `addons/`) nebo jsou pro běh hry nutné. Licence herních assetů (modely, textury, zvuky,
hudba) řeší registr [`assets/LICENSES.md`](assets/LICENSES.md) + `assets/licenses.json`,
licence geodat [`README.md`](README.md) → „Licence dat". Tato tři místa se doplňují –
`assets/` registruje obsah stažený z internetu, tento soubor software a knihovny.

## Herní engine

| komponenta | verze | zdroj | licence | copyright |
|---|---|---|---|---|
| Godot Engine | 4.3 | https://github.com/godotengine/godot | MIT | © 2014–současnost Godot Engine contributors; © 2007–2014 Juan Linietsky, Ariel Manzur |

Engine není součástí repozitáře – hra na něm běží a exportuje se jím. Seznam dalších
licencí vestavěných v enginu: Godot editor → Help → About → Third-party Licenses.

## Add-ony (vendored v `addons/`)

| komponenta | verze | umístění | zdroj | licence | copyright |
|---|---|---|---|---|---|
| Godot Jolt | 0.13.0-stable | `addons/godot-jolt/` | https://github.com/godot-jolt/godot-jolt | MIT | © Mikael Hermansson and Godot Jolt contributors |
| FuncGodot | 2025.1 | `addons/func_godot/` | https://github.com/func-godot/func_godot_plugin | MIT | © 2023 func-godot |
| LimboAI | 1.3.1 | `addons/limboai/` | https://github.com/limboversion/limboai | MIT | © 2023–2025 Serhii Snitsaruk and the LimboAI contributors |
| godot-state-charts | 0.22.5 | `addons/godot_state_charts/` | https://github.com/derkork/godot-state-charts | MIT | © 2023 Jan Thomä |

Poznámky:

- **Godot Jolt** a **LimboAI** jsou GDExtension (nativní knihovny v `addons/*/bin/`),
  **FuncGodot** a **godot-state-charts** editorové pluginy povolené v `project.godot`
  (`editor_plugins/enabled`). Godot Jolt interně používá fyzikální knihovnu
  **Jolt Physics** (MIT, © Jorrit Rouwé, https://github.com/jrouwe/JoltPhysics) – je
  slinkovaná přímo v binárkách addonu.
- Kopie licenčních textů v repu: `addons/godot-jolt/LICENSE.txt`,
  `addons/limboai/LICENSE.md`, `addons/godot_state_charts/LICENSE`. Distribuce
  FuncGodotu v `addons/func_godot/` licenční soubor neobsahuje – platí licence
  upstream repozitáře (MIT výše; autorské zápisy v `plugin.cfg`: Shifty,
  Hannah Crawford, Emberlynn Bland, Tim Maccabe). Při příští aktualizaci addonu
  doplnit do jeho složky `LICENSE` z upstreamu.
- Logo LimboAI (`addons/limboai/icons/`, `LOGO_LICENSE.md`) je **CC BY 4.0**,
  © 2023 Aleksandra Snitsaruk. Logo se ve hře ani v buildu nepoužívá – pokud by se
  někdy zobrazilo, je nutné uvést autorku.
- Zdrojový kód addonů se nemění; případné úpravy držet jako patch vedle addonu,
  ať jde addon kdykoliv povýšit na novou verzi.

## Text MIT licence

Všechny výše uvedené komponenty (kromě loga LimboAI) jsou pod toutéž licencí MIT;
liší se jen držitel copyrightu uvedený v tabulkách:

```text
MIT License

Copyright (c) <rok> <držitel copyrightu – viz tabulky výše>

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```
