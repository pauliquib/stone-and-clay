"""BPEJ (bonitované půdně ekologické jednotky) katastru → data/bpej_meta.json (+ data/bpej_raw.*).

Příprava datového podkladu pro M8.2 "Mapa stanovišť" (půdní třídy) – tento nástroj sám nekreslí
žádnou herní mapu, jen stahuje/sestavuje podklad, se kterým bude M8.2 pracovat.

Co je BPEJ: pětimístný číselný kód (X.XX.XX) – 1. číslice klimatický region (0-9), 2.-3. hlavní
půdní jednotka HPJ (01-89), 4. sdružený kód sklonitosti a expozice (0-9), 5. sdružený kód
skeletovitosti a hloubky půdy (0-9). Celkem 2995 kódů pro ČR+SR (zdroj: eKatalog BPEJ, viz níže).

Zdroje (ověřeno v tomto běhu, říjen 2026):
  1) Číselník BPEJ (kód → klimatický region, HPJ, výměra v ČR, cena Kč/m2, bodová výnosnost,
     třída ochrany ZPF) – veřejná webová aplikace "eKatalog BPEJ" provozovaná VÚMOP, v. v. i.
     (Výzkumný ústav meliorací a ochrany půdy) pro Ministerstvo zemědělství:
       https://bpej.vumop.cz/  (bez přihlášení, bez poplatku; informační/veřejná databáze)
     Stránka vrací rovnou celou tabulku v HTML (~2683 řádků); tento nástroj ji stáhne a naparsuje.
     Licence/podmínky použití nejsou na stránce explicitně vyznačeny jako CC, ale jde o veřejně
     přístupnou informační databázi MZe/VÚMOP bez přihlášení a bez poplatku – stejná kategorie
     veřejných dat ČR jako číselníky ČÚZK použité jinde v tomto repu. Číselník (bez geometrie)
     je čistě dokumentační/malá tabulka → smí do gitu (na rozdíl od data/*.bin).

  2) Prostorová data (které BPEJ polygony leží v katastru) – autoritativním zdrojem je celostátní
     databáze BPEJ Státního pozemkového úřadu (SPÚ), shapefile, aktualizace měsíčně, licence
     CC BY 4.0 (uvést zdroj SPÚ + rok): https://geoportal.spucr.cz/web/cz/bpej-open-data
     POZOR – OTEVŘENÝ BOD: v době psaní (říjen 2026) je celá doména geoportal.spucr.cz
     nedostupná (HTTP 500 / timeout, ověřeno i mimo tento nástroj přímým dotazem, ne jen
     selháním tohoto scriptu) a starší přímý odkaz na stažení (used by QGIS pluginem
     github.com/mredoslav/bpej_ruian_plugin) na spucr.cz/spu.gov.cz vede na 404 (stránka SPÚ
     byla mezitím přesunuta/zrušena). Žádný jiný ověřený celostátní WMS/WFS/REST zdroj
     s geometrií BPEJ nebyl v tomto běhu nalezen:
       - ags.cuzk.cz (ČÚZK ArcGIS) nemá BPEJ mezi službami (jen výškopis/DMR).
       - wms.vumop.cz/public/*.php nabízí jen erozi a KPP (komplexní průzkum půd), ne BPEJ.
       - bpej.vumop.cz/cgi-bin/mapserv.fcgi (MapServer) existuje, ale vyžaduje interní parametr
         "map" (cestu k mapfile), který není z venku odhalitelný – frontend ho zřejmě dostává
         jinak než staticky z JS.
       - Regionální ArcGIS služby s BPEJ existují (např. Plzeňský kraj
         maps.plzensky-kraj.cz/arcgis/rest/services/BPEJ/MapServer), ale krajsky omezené –
         nepokrývají tento katastr (Zlínský kraj) a Zlínský kraj (mapy.kr-zlinsky.cz) BPEJ
         vrstvu nenabízí.
     Tento nástroj se o stažení geometrie (data/bpej_raw.*) PŘESTO pokusí (--try-shapefile),
     ale dokud nebude k dispozici funkční URL, skončí jasnou chybou a vytvoří jen bpej_meta.json.
     Až se zdroj obnoví / najde se jiný fungující, doplň sem URL a implementaci ořezu polygonů
     na bbox katastru (shapely je v repu k dispozici, knihovna na čtení shapefile/GML ale není –
     bude potřeba např. `pyshp`, nebo stahovat/parsovat GML/GeoJSON místo shp).

Výstup:
  data/bpej_meta.json (v gitu – malý číselník, ne geodata):
    {
      "source": {...popis výše...},
      "code_structure": {...popis pětimístného kódu...},
      "codes": [ {"kod": "4.37.46", "klima": "4", "hpj": "37", "vymera_ha": "216",
                   "cena_kc_m2": "1.22", "vynos_body": "11", "trida_ochrany": "V."}, ... ],
      "katastr_codes": null  # dokud se nesežene geometrie – M8.2 nemá odkud vzít, které kódy
                              # reálně leží v tomto katastru
    }
  data/bpej_raw.bin (NEVZNIKÁ v tomto běhu – v .gitignore jako ostatní data/*.bin; vznikne, až
    se najde funkční zdroj geometrie; formát navrhnut, ale neimplementován – viz TODO níže).

Spuštění (z kořene repozitáře):
  python3 tools/fetch_bpej.py              # stáhne číselník + zkusí geometrii (nejspíš selže)
  python3 tools/fetch_bpej.py --meta-only  # jen číselník, geometrii ani nezkouší
"""
import argparse
import json
import os
import re
import sys
import time
import urllib.error
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
GAME = os.path.dirname(HERE)
DATA = os.path.join(GAME, "data")

CATALOG_URL = "https://bpej.vumop.cz/"
DL_TIMEOUT = 60
DL_TRIES = 3

# Kandidátní zdroje prostorových dat BPEJ – žádný z nich nebyl v tomto běhu ověřen jako funkční
# (viz docstring výše); nástroj je zkusí v tomto pořadí, než se vzdá.
SHAPEFILE_CANDIDATES = [
    "https://geoportal.spucr.cz/web/cz/bpej-open-data",
    "https://spu.gov.cz/bpej/celostatni-databaze-bpej/aktualni-databaze-bpej-ke-stazeni.html",
]


def jload(rel):
    return json.load(open(os.path.join(GAME, rel), encoding="utf-8"))


def get(url, tries=DL_TRIES, timeout=DL_TIMEOUT):
    last = None
    for i in range(tries):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "stone-and-clay/fetch_bpej.py"})
            with urllib.request.urlopen(req, timeout=timeout) as r:
                return r.read()
        except Exception as e:  # noqa: BLE001
            last = e
            print(f"  retry {i + 1}/{tries}: {e}")
            time.sleep(2 * (i + 1))
    raise RuntimeError(f"stažení selhalo: {url} ({last})")


def fetch_catalog():
    """Stáhne a naparsuje celostátní číselník BPEJ z eKatalogu VÚMOP (bpej.vumop.cz)."""
    print(f"Stahuji číselník BPEJ: {CATALOG_URL}")
    html = get(CATALOG_URL).decode("utf-8", "replace")
    rows = re.findall(r'<tr id="tr-id-\d+"[^>]*>(.*?)</tr>', html, re.S)
    codes = []
    for r in rows:
        tds = re.findall(r"<td[^>]*>(.*?)</td>", r, re.S)
        if len(tds) < 7:
            continue

        def clean(s):
            return re.sub(r"<[^>]+>", "", s).strip()

        kod_m = re.search(r">([\d.]+)\s*</a>", tds[0])
        kod = kod_m.group(1) if kod_m else clean(tds[0])
        if not re.match(r"^\d\.\d{2}\.\d{2}$", kod):
            continue
        codes.append({
            "kod": kod,
            "klima": clean(tds[1]),
            "hpj": clean(tds[2]),
            "vymera_ha": clean(tds[3]),
            "cena_kc_m2": clean(tds[4]),
            "vynos_body": clean(tds[5]),
            "trida_ochrany": clean(tds[6]),
        })
    if not codes:
        raise RuntimeError("číselník BPEJ: 0 řádků naparsováno – změnila se struktura stránky?")
    print(f"Číselník BPEJ: {len(codes)} kódů")
    return codes


def try_shapefile_sources():
    """Zkusí najít a stáhnout prostorová data BPEJ (shapefile SPÚ). Vrací cestu k souboru,
    nebo None, pokud žádný ze známých zdrojů nefunguje (viz docstring – OTEVŘENÝ BOD)."""
    for url in SHAPEFILE_CANDIDATES:
        print(f"Zkouším prostorový zdroj: {url}")
        try:
            html = get(url, tries=1, timeout=20).decode("utf-8", "replace")
        except Exception as e:  # noqa: BLE001
            print(f"  nedostupné: {e}")
            continue
        m = re.search(r'href="([^"]*bpej[_a-zA-Z0-9]*\.zip)"', html, re.I)
        if m:
            print(f"  nalezen odkaz na shapefile: {m.group(1)} – stažení/ořez NENÍ implementováno "
                  "(chybí knihovna na čtení .shp v repu, viz docstring) – dopiš při M8.2.")
            return None
        print("  stránka dostupná, ale odkaz na .zip s BPEJ nenalezen")
    return None


def main():
    ap = argparse.ArgumentParser(description="Příprava BPEJ podkladu pro M8.2 (mapa stanovišť)")
    ap.add_argument("--meta-only", action="store_true",
                     help="nezkoušet stahovat prostorová data, jen číselník")
    a = ap.parse_args()

    os.makedirs(DATA, exist_ok=True)

    codes = fetch_catalog()
    klima_uniq = sorted({c["klima"] for c in codes})
    hpj_uniq = sorted({c["hpj"] for c in codes})
    trida_uniq = sorted({c["trida_ochrany"] for c in codes})
    print(f"Klimatické regiony v číselníku: {klima_uniq}")
    print(f"Počet HPJ v číselníku: {len(hpj_uniq)}")
    print(f"Třídy ochrany ZPF v číselníku: {trida_uniq}")

    katastr_codes = None
    if not a.meta_only:
        try_shapefile_sources()
        print("POZOR: prostorová data BPEJ pro tento katastr se NEPODAŘILO získat – žádný "
              "ověřený veřejný zdroj geometrie nebyl v tomto běhu nalezen/funkční (podrobně "
              "v docstringu a v docs/BPEJ.md). data/bpej_raw.* NEVZNIKLO.")

    meta = {
        "version": 1,
        "source": {
            "ciselnik": {
                "nazev": "eKatalog BPEJ (VÚMOP, v. v. i. pro MZe ČR)",
                "url": CATALOG_URL,
                "pristup": "veřejné, bez přihlášení, bez poplatku",
                "stazeno": time.strftime("%Y-%m-%d"),
            },
            "geometrie": {
                "autoritativni_zdroj": "Celostátní databáze BPEJ, Státní pozemkový úřad (SPÚ), "
                                        "shapefile, aktualizace měsíčně, licence CC BY 4.0 "
                                        "(uvést zdroj SPÚ + rok)",
                "url": "https://geoportal.spucr.cz/web/cz/bpej-open-data",
                "stav": "NEDOSTUPNÉ v době psaní (HTTP 500/timeout celé domény, ověřeno i mimo "
                        "tento nástroj); starší přímý odkaz na spu.gov.cz vede na 404 (přesunuto/"
                        "zrušeno). Žádný jiný celostátní WMS/WFS/REST zdroj s geometrií BPEJ "
                        "nebyl nalezen – viz docstring tools/fetch_bpej.py a docs/BPEJ.md.",
            },
        },
        "code_structure": {
            "format": "X.XX.XX (5 číslic)",
            "1": "klimatický region (0-9)",
            "2-3": "hlavní půdní jednotka HPJ (01-89)",
            "4": "sdružený kód sklonitosti a expozice (0-9) – přesný číselník hodnot 0-9 "
                 "NEBYL na bpej.vumop.cz dohledán jako strojově čitelná tabulka (jen slovní "
                 "popis); číselné hodnoty u jednotlivých kódů jsou v praxi dostupné jen přes "
                 "textový popis na detailní stránce kódu (https://bpej.vumop.cz/<kod bez teček>)",
            "5": "sdružený kód skeletovitosti a hloubky půdy (0-9) – stejná poznámka jako u 4.",
            "pocet_kodu_cr_sr": 2995,
        },
        "codes": codes,
        "katastr_codes": katastr_codes,
    }
    out = os.path.join(DATA, "bpej_meta.json")
    json.dump(meta, open(out, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    print(f"WROTE {out}: {len(codes)} kódů BPEJ (číselník), katastr_codes="
          f"{'None (geometrie chybí)' if katastr_codes is None else len(katastr_codes)}")


if __name__ == "__main__":
    main()
