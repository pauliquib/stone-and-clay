# Registr assetů a licencí

**Jediný zdroj pravdy.** Strojově čitelná kopie je `assets/licenses.json` (z ní `tools/assets_check.py`
generuje `data/credits.json` s titulky ve hře). Při každém přidání assetu uprav **obě** místa.
Postup je v `ASSETY.md`.

## Pravidla (VIZE_A_ROADMAPA kap. 2.2)

| Povolené | Podmíněné (uvést autora) | Zakázané |
|---|---|---|
| `CC0`, `PD` (public domain) – Poly Haven, ambientCG, Kenney, Quaternius, CC0 na Freesound / OpenGameArt | `CC-BY-3.0`, `CC-BY-4.0`, `OGA-BY`, `royalty-free-game` (balík s licencí pro hry) – autor, zdroj a licence v titulcích | CC BY-**NC**, CC BY-**ND**, CC BY-SA (pokud není vyřešeno), „personal use“, bez licence, ripy z her, Google / Bing 3D |

**Odbrandování:** model skutečného auta / předmětu nesmí nést logo, nápis značky, reálnou SPZ ani
rozpoznatelný ochranný prvek – odstranit v Blenderu (tělo neutrálně, SPZ smyšlená s písmenem Q).
Provedené úpravy se zapisují do sloupce „úpravy“.

## Registr

| id | soubor(y) | název | autor | zdroj (URL) | licence | staženo | úpravy | použití ve hře |
|---|---|---|---|---|---|---|---|---|
| ph-asphalt_02 | `textures/asphalt_02_*_2k.jpg` | asphalt_02 (PBR, 2k) | Poly Haven (autora ověřit) | https://polyhaven.com/a/asphalt_02 | CC0 | před 2026-09 | žádné | povrch silnic |
| ph-bark_brown_02 | `textures/bark_brown_02_*_2k.jpg` | bark_brown_02 (PBR, 2k) | Poly Haven (autora ověřit) | https://polyhaven.com/a/bark_brown_02 | CC0 | před 2026-09 | žádné | kůra stromů |
| ph-beige_wall_001 | `textures/beige_wall_001_*_2k.jpg` | beige_wall_001 (PBR, 2k) | Poly Haven (autora ověřit) | https://polyhaven.com/a/beige_wall_001 | CC0 | před 2026-09 | žádné | fasády |
| ph-clay_roof_tiles_02 | `textures/clay_roof_tiles_02_*_2k.jpg` | clay_roof_tiles_02 (PBR, 2k) | Poly Haven (autora ověřit) | https://polyhaven.com/a/clay_roof_tiles_02 | CC0 | před 2026-09 | žádné | střechy |
| ph-gravel_road | `textures/gravel_road_*_2k.jpg` | gravel_road (PBR, 2k) | Poly Haven (autora ověřit) | https://polyhaven.com/a/gravel_road | CC0 | před 2026-09 | žádné | polní a lesní cesty |
| ph-sky-hdr | `textures/sky.hdr` | HDRI obloha | Poly Haven (název a autora ověřit) | https://polyhaven.com/hdris | CC0 | před 2026-09 | možná zmenšeno | obloha, osvětlení |
| cuzk-ortofoto | `textures/ortho_full.jpg`, `ortho_core.jpg` | Ortofoto ČR | ČÚZK | https://geoportal.cuzk.cz/ | CC-BY-4.0 | před 2026-09 | oříznuto, sesazeno | textura terénu, mapa |

Geodata (DMR 5G, ČÚZK), OSM (ODbL) a DIBAVOD nejsou „assety“ ve smyslu této složky – jejich uvedení je
pevně v `Hud.CREDITS` (`scripts/hud.gd`) a v README → „Licence dat“.

Záznamy s `v_titulcich: false` jsou už uvedené v pevném `Hud.CREDITS`, proto je `assets_check.py`
do `data/credits.json` nedává (jinak by se titulky zdvojily).

## Nedokončené ověření
- U Poly Haven textur a HDRI doplnit jméno autora a přesný název HDRI (stránka assetu na polyhaven.com).
