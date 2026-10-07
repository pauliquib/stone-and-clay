# BPEJ – příprava podkladu pro M8.2 (Mapa stanovišť)

Tento dokument je zápisník z přípravného kroku (ne z M8.2 samotného) – shrnuje, co se zjistilo
o veřejných zdrojích BPEJ (bonitovaných půdně ekologických jednotek), co nástroj
`tools/fetch_bpej.py` reálně stáhl, a co bude M8.2 potřebovat doplnit.

## Co je BPEJ

Pětimístný číselný kód `X.XX.XX`:
- 1. číslice – klimatický region (0–9)
- 2.–3. číslice – hlavní půdní jednotka HPJ (01–89)
- 4. číslice – sdružený kód sklonitosti a expozice (0–9)
- 5. číslice – sdružený kód skeletovitosti a hloubky půdy (0–9)

Celkem 2995 kódů pro ČR + SR.

## Zdroje – co funguje a co ne (ověřeno v říjnu 2026)

**Funguje, použito:** číselník BPEJ (kód → klimatický region, HPJ, výměra v ČR, cena Kč/m²,
bodová výnosnost, třída ochrany ZPF) na **eKatalog BPEJ**, veřejná webová aplikace VÚMOP, v. v. i.
pro Ministerstvo zemědělství: https://bpej.vumop.cz/ – bez přihlášení, bez poplatku, odpověď je
přímo HTML tabulka se všemi kódy (žádné API, jen scraping). `tools/fetch_bpej.py` ji stáhne a
naparsuje do `data/bpej_meta.json` (476 kB, 3022 kódů – v gitu, je to jen číselník).

Číselník NEDÁVÁ číselný rozpad 4. a 5. číslice (sklonitost/expozice, skeletovitost/hloubka) jako
tabulku hodnot 0–9 → 0–9; stránka to popisuje jen slovně. Pro konkrétní kód je slovní popis
(„Kambizemě... na středních svazích s jižní expozicí... obsah skeletu 25–50 %... půdy mělké...")
dostupný na detailu `https://bpej.vumop.cz/<kód bez teček>` (např. `.../43746`), ale strojově
čitelná tabulka 0–9 → hodnota nebyla v tomto běhu dohledána.

**NEFUNGUJE / otevřený bod – prostorová data (geometrie BPEJ pro konkrétní katastr):**

Autoritativní zdroj je celostátní databáze BPEJ Státního pozemkového úřadu (SPÚ) – shapefile,
aktualizace měsíčně, licence CC BY 4.0 (uvést zdroj SPÚ + rok):
https://geoportal.spucr.cz/web/cz/bpej-open-data

V době psaní je **celá doména geoportal.spucr.cz nedostupná** (HTTP 500 / timeout – ověřeno i
přímým síťovým dotazem mimo tento nástroj, nejde o chybu scriptu). Starší přímý odkaz na
`spu.gov.cz/bpej/.../aktualni-databaze-bpej-ke-stazeni.html` (použitý např. QGIS pluginem
[bpej_ruian_plugin](https://github.com/mredoslav/bpej_ruian_plugin)) vede na 404 – stránka byla
mezitím na webu SPÚ přesunuta nebo zrušena.

Další zdroje prověřené a vyřazené:
- `ags.cuzk.cz` (ČÚZK ArcGIS) – nemá BPEJ mezi službami, jen výškopis (DMR4G/5G, DMP) a nástroje
  nad ním (sklon, orientace, viditelnost).
- `wms.vumop.cz/public/*.php` – veřejné WMS existují, ale jen eroze (`eroze.php`) a komplexní
  průzkum půd (`kpp.php` na `kpp.vumop.cz`), BPEJ mezi nimi není.
- `bpej.vumop.cz/cgi-bin/mapserv.fcgi` – MapServer backend eKatalogu existuje a odpovídá, ale
  vyžaduje parametr `map` (cestu k mapfile), který frontend zjevně nedostává staticky z JS
  (nenalezen v `configApp.js` ani v HTML detailních stránek) – bez něj vrací jen chybu.
- Regionální ArcGIS služby s BPEJ existují (např. Plzeňský kraj,
  `maps.plzensky-kraj.cz/arcgis/rest/services/BPEJ/MapServer`), ale jsou krajsky omezené.
  Zlínský kraj (`mapy.kr-zlinsky.cz/arcgis/rest/services`) BPEJ vrstvu nenabízí vůbec.

**Nevymyslel jsem fallback** – podle zadání to má udělat M8.2 z terénu+landuse (00_PRINCIPY kap. 8
„Půda"), ne tento přípravný krok.

## Co M8.2 potřebuje přečíst

- `data/bpej_meta.json` – vždy existuje po běhu `tools/fetch_bpej.py`. Klíče:
  - `codes`: list všech BPEJ kódů ČR+SR, každý `{"kod", "klima", "hpj", "vymera_ha",
    "cena_kc_m2", "vynos_body", "trida_ochrany"}` (hodnoty jako stringy, přesně jak byly na
    stránce – `""` když chybí cena).
  - `katastr_codes`: **`null`** – geometrie se nepodařilo získat, takže není seznam kódů, které
    reálně leží v tomto katastru. Pokud se zdroj najde a doplní, bude to list kódů relevantních
    pro katastr (po ořezu na `data/map.json` → `boundary`).
  - `code_structure`, `source`: popis formátu a zdrojů (viz výš).
- `data/bpej_raw.*` – **neexistuje** (viz výše). Pokud se v budoucí session doplní stahování
  geometrie, formát/cesta se musí doplnit sem i do `.gitignore` (položka `data/bpej_raw.*` je tam
  už teď, preventivně).
- Když `katastr_codes` zůstane `null` i v budoucnu, M8.2 použije fallback z terénu (sklon/expozice
  z DMR 5G, které už hra má – `tools/surface.py`/`terrain_height.bin`) + landuse (`data/landuse.bin`
  z `tools/landuse.py`) místo reálných BPEJ kódů, podle 00_PRINCIPY kap. 8 „Půda".

## Jak doplnit geometrii, až/pokud se zdroj najde

1. Najít funkční URL (zkusit znovu `geoportal.spucr.cz/web/cz/bpej-open-data`, nebo nový odkaz na
   SPÚ/VÚMOP, nebo jiný WMS/WFS/REST s geometrií BPEJ pro Zlínský kraj).
2. Doplnit do repa knihovnu na čtení shapefile/GML (žádná momentálně není – `pyshp`, `fiona`,
   `geopandas` ani `osgeo.ogr` nejsou k dispozici; shapely ano, pyproj ano).
3. V `tools/fetch_bpej.py` dopsat ořez staženého celostátního/krajského shapefile na bbox katastru
   (`data/map.json` → `boundary`, transformace scéna→S-JTSK podle vzoru v `tools/surroundings.py`
   `scene_to_5514` – potřebuje `data/scene_reference.json` + `data/geodata_meta_full.json`, které
   jsou lokální/needitované v gitu, viz `tools/export_map.py`/`tools/surroundings.py`).
4. Uložit `data/bpej_raw.*` (formát navrhnout obdobně jako `data/landuse.bin`/`water_carve.bin` –
   magic, verze, souřadnice, pak rastr tříd nebo seznam polygonů) a naplnit `katastr_codes`
   v `data/bpej_meta.json`.
