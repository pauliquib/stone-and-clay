"""Automatické vytvoření / aktualizace článku v svec-studio → Zajímavosti.

Z aktuálních výstupů projektu (pipeline/data/*.json, pipeline/renders/*) sestaví článek o tom,
jak vzniklo reálné 3D okolí domu z otevřených geodat, a uloží ho přes API
svec-studio (`Articles.save_article`) stejně jako tlačítko „Uložit článek“:
  - source/studio/articles/<slug>.md
  - zajimavosti/<slug>/index.html (šablona webu) + zajimavosti/<slug>/img/*
  - položka katalogu (js/notes-data.js) a vyhledávání (js/search-data.js)
  - záznam v deníku změn Studia (fronta „Historie a FTP“)

Článek se ukládá jako **nepublikovaný koncept** (published: false) – zveřejnění
(checklist / FTP) zůstává ručně ve Studiu. Skript je idempotentní: opakované
spuštění článek jen aktualizuje (zachová pořadí v katalogu).

Soukromí: výchozí režim neuvádí číslo popisné, přesné souřadnice ani letecký
snímek se zvýrazněným domem. `--verejna-adresa` je do článku zahrne.

Spuštění:
    python3 pipeline/scripts/publish_article.py [--slug …] [--site …] [--verejna-adresa] [--dry-run]
"""
import argparse
import json
import os
import sys
from datetime import date

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)          # pipeline/ – data/, assets/, renders/, logs/
GAME = os.path.dirname(ROOT)          # kořen repozitáře hry – geodata/, blend/
GEO = os.path.join(GAME, "geodata")
DEFAULT_SITE = "/mnt/63bc27e0-61a0-48bd-9def-833f5a186631/vyvoj_programy/svec-elektro.cz"
DEFAULT_SLUG = "3d-okoli-domu-z-otevrenych-geodat"


def load(rel, default=None):
    p = os.path.join(ROOT, rel)
    if not os.path.exists(p):
        return default
    with open(p, encoding="utf-8") as f:
        return json.load(f)


def collect_stats():
    ref = load("data/scene_reference.json", {})
    tref = load("data/terrain_ref.json", {})
    meta = load("data/geodata_meta.json", {})
    align = load("data/alignment_check.json", {})
    blds = load("data/buildings_3d.json", []) or []
    trees = load("data/trees_ndsm.json", []) or []
    gj = load("data/okoli_local.geojson", {"features": []})
    kinds = {}
    for f in gj["features"]:
        k = f["properties"]["kind"]
        kinds[k] = kinds.get(k, 0) + 1
    osm_b = [b for b in blds if b.get("source") == "osm"]
    dmp_b = [b for b in osm_b if b.get("height_source") == "DMP1G"]
    det_b = [b for b in blds if b.get("source") == "dmp_detected"]
    shapes = {}
    for b in blds:
        shapes[b["shape"]] = shapes.get(b["shape"], 0) + 1
    rd = sorted(b["ridge_z"] - b["ground_z"] for b in dmp_b if b.get("building") in ("house", "residential"))
    th = sorted(t["h"] for t in trees)
    zmin = zmax = None
    try:
        import numpy as np
        tz = np.load(os.path.join(GEO, "terrain_z.npy"))
        n = tz.shape[0]
        yy, xx = np.mgrid[0:n, 0:n]
        m = np.hypot(xx - n / 2, yy - n / 2) < 480
        zmin, zmax = float(tz[m].min()), float(tz[m].max())
    except Exception:
        pass
    diag = ref.get("diagnostics", {})
    return {
        "theta": ref.get("north_angle_deg"),
        "iou": diag.get("iou_best"),
        "iou2": diag.get("iou_second_candidate"),
        "house_latlon": ref.get("house_latlon"),
        "h_ref": tref.get("H_ref"),
        "ortho_res": meta.get("ortho_res"),
        "residual_mm": (meta.get("affine_scene_to_5514", {}).get("max_residual_m") or 0) * 1000,
        "shift": align.get("best_shift_scene_m"),
        "n_osm_buildings": kinds.get("building", 0),
        "n_roads": kinds.get("highway", 0),
        "n_landuse": kinds.get("landuse", 0),
        "n_bld_dmp": len(dmp_b),
        "n_bld_fallback": len(osm_b) - len(dmp_b),
        "n_bld_detected": len(det_b),
        "n_bld_total": len(blds),
        "shapes": shapes,
        "rd_ridge_median": rd[len(rd) // 2] if rd else None,
        "n_trees": len(trees),
        "tree_h_median": th[len(th) // 2] if th else None,
        "n_conifers": sum(1 for t in trees if t.get("type") == "con"),
        "zmin": zmin, "zmax": zmax,
    }


def fmt(v, nd=1, unit=""):
    if v is None:
        return "?"
    s = f"{v:.{nd}f}".replace(".", ",")
    if unit == "°":
        return s + unit
    return s + (f" {unit}" if unit else "")


IMAGES = [
    # (zdroj v pipeline/renders/, cíl v img/, popis, jen s veřejnou adresou)
    ("phase7_final_v2_persp.png", "okoli-perspektiva.jpg",
     "Výsledek: dům (uprostřed) v okolí postaveném z dat ČÚZK – terén DMR 5G, ortofoto, výšky budov a stromů z DMP 1G.",
     False),
    ("phase7_final_v2.png", "okoli-izometrie.jpg",
     "Izometrický pohled na okruh zhruba 350 m: 347 budov, 1806 stromů, silnice položené na terénu.", False),
    ("phase3_v1.png", "prvni-verze-osm.jpg",
     "První verze jen z OpenStreetMap: správné půdorysy, ale rovinný terén a odhadnuté výšky.", False),
    ("check_ndsm.jpg", "ndsm-kontrola.jpg",
     "Rozdíl modelu povrchu a reliéfu (DMP 1G − DMR 5G): světlé = vysoké objekty. Červeně obrysy budov z OSM.",
     True),
    ("check_ortho.jpg", "ortofoto-kontrola.jpg",
     "Kontrola zarovnání: ortofoto ČÚZK, obrysy OSM budov (červeně), silnice (žlutě) a model domu (tyrkysově).",
     True),
]


def build_body(s, slug, public_addr):
    img = f"/zajimavosti/{slug}/img/"
    loc = ("u domu Doubravy 122 v Březůvkách (lat {:.6f}, lon {:.6f})".format(*s["house_latlon"])
           if public_addr and s.get("house_latlon") else "u rodinného domu na Zlínsku")
    shapes = s["shapes"]
    L = []
    a = L.append
    a(f"Mám v Blenderu hotový model domu – sklep, patra, interiér, zpevněné plochy. Chyběl mu ale svět "
      f"kolem. Místo ručního modelování sousedů jsem nechal AI agenta (Claude Code) postavit okolí {loc} "
      f"čistě z **otevřených dat**: OpenStreetMap, výškových modelů a ortofota ČÚZK a volných textur. "
      f"Celé to běží headless skripty v Pythonu a Blenderu, dá se to kdykoli zopakovat – a tenhle článek "
      f"se na konci pipeline generuje automaticky.")
    a("")
    a(f"![Výsledek – perspektiva]({img}okoli-perspektiva.jpg)")
    a("")
    a("## Jaká data jsou volně k dispozici")
    a("")
    a("- **OpenStreetMap** (Overpass API) – půdorysy budov převzaté z RÚIAN, silnice, využití ploch. "
      f"V okruhu 450 m: {s['n_osm_buildings']} budov, {s['n_roads']} komunikací, {s['n_landuse']} ploch.")
    a("- **DMR 5G** – digitální model reliéfu ČR (holý terén) z leteckého laserového skenování.")
    a("- **DMP 1G** – digitální model povrchu: terén *včetně* střech a korun stromů.")
    a(f"- **Ortofoto ČR** – letecké snímky s rozlišením 12,5 cm/px (ve scéně {fmt(s['ortho_res'] * 100 if s['ortho_res'] else None)} cm/px).")
    a("- **Poly Haven** – PBR textury (tašky, omítka, asfalt, štěrk, kůra) a HDRI oblohy, licence CC0.")
    a("")
    a("Data ČÚZK jsou od roku 2023 otevřená (CC BY 4.0) a dají se stáhnout přímo přes ArcGIS REST "
      "služby `ags.cuzk.cz` – výřez v souřadnicích S-JTSK, výšky jako 32bitový TIFF.")
    a("")
    a("## Kde je u modelu sever?")
    a("")
    a("Model domu byl kreslený podle projektu, ne podle mapy – měl metry, ale žádnou vazbu na svět. "
      "Orientaci jsem zjistil tak, že se půdorys modelu (obvodové zdi sklepa a přístavby) rastrově "
      "přiložil na půdorys domu z katastru a hledala se rotace a posun s největším překryvem (IoU).")
    a("")
    a(f"- nejlepší shoda: rotace **{fmt(s['theta'], 1, '°')}**, překryv IoU {fmt(s['iou'], 2)}")
    a(f"- past: dům je skoro obdélník, takže otočení o 180° má v hrubém kroku stejné skóre ({fmt(s['iou2'], 2)})")
    a("- rozhodl vjezd: jen při správné orientaci leží nejbližší silnice na straně, kde má model zídku u vjezdu")
    a("- později to nezávisle potvrdilo ortofoto – obrys modelu sedí přesně na střechu skutečného domu")
    a("")
    a("## Chyba o 110 metrů")
    a("")
    a("Nejzákeřnější chyba celé práce: převod z lokální projekce do S-JTSK přes pyproj proběhl bez varování, "
      "jen transformace měla v popisu *„Ballpark geographic offset“*. To znamená, že se úplně přeskočil "
      "převod mezi elipsoidy – a data ČÚZK byla posunutá zhruba o **110 m**. Oprava: nejdřív zpět na "
      "WGS84 zeměpisné souřadnice, teprve pak oficiální Helmertova transformace EPSG:4326 → 5514. "
      f"Po opravě sedí obrysy budov z OSM na ortofoto i výškový model s chybou do 1 m "
      f"(nejlepší dorovnání {'; '.join(str(v) for v in (s['shift'] or []))} m), afinní převzorkování má reziduum {fmt(s['residual_mm'], 2, 'mm')}.")
    a("")
    a("Poučení: u každé transformace kontrolovat, *jakou* operaci knihovna zvolila, a výsledek ověřit "
      "překryvem nad snímkem.")
    a("")
    if public_addr:
        a(f"![Kontrola zarovnání]({img}ortofoto-kontrola.jpg)")
        a("")
    a("## Výšky budov z rozdílu dvou modelů")
    a("")
    a("OSM zná u většiny domů jen počet podlaží. Přesnější je odečíst od modelu povrchu (DMP) model reliéfu "
      "(DMR) – co zbyde, jsou výšky objektů nad terénem. Pro každou budovu se v bodech jejího půdorysu "
      "(0,5 m od sebe, 0,6 m od hrany) nafitují čtyři modely střechy – plochá, sedlová podél delší "
      "nebo kratší osy a valbová – a vybere se ten s nejmenší chybou.")
    a("")
    a(f"- výšky z DMP má **{s['n_bld_dmp']}** budov z OSM, {s['n_bld_fallback']} v DMP chybí (novostavby) "
      "a dostaly výšku z počtu podlaží")
    a(f"- **{s['n_bld_detected']}** staveb (kůlny, garáže, i celé domy) v OSM vůbec nebylo – našly se v DMP "
      "jako pravoúhlé ne-zelené objekty vyšší než 2,2 m")
    a(f"- tvary střech: sedlová {shapes.get('gable_long', 0) + shapes.get('gable_short', 0)}, "
      f"valbová {shapes.get('hipped', 0)}, plochá {shapes.get('flat', 0)}")
    a(f"- medián výšky hřebene rodinného domu: {fmt(s['rd_ridge_median'], 1, 'm')} nad terénem")
    a("")
    a("DMP 1G je ovšem vyhlazený: snižuje hřebeny, zvedá okapy a ze sedlových střech dělá „kopule“, které "
      "se tváří jako ploché. Proto se hřeben bere z 90. percentilu výšek, sklon se omezuje na obvyklých "
      "25–45° a u rodinných domů má šikmá střecha přednost.")
    a("")
    if public_addr:
        a(f"![nDSM]({img}ndsm-kontrola.jpg)")
        a("")
    a("## Terén a napojení na pozemek")
    a("")
    a(f"Terén je mřížka 1,5 m v kruhu o poloměru 480 m z DMR 5G; převýšení okolí je "
      f"{fmt(s['zmin'], 0, 'm')} až +{fmt(s['zmax'], 0, 'm')} vůči domu. Výšky modelu a terénu se "
      "svázaly přes okraj zpevněné plochy kolem domu: posun se spočítal jako medián rozdílů mezi DMR a "
      "výškou okraje v modelu. Pod samotným modelem se terén lehce sníží, aby nikde neprorazil dlažbu.")
    a("")
    a("## Stromy")
    a("")
    a(f"V OSM nebyl ani jeden strom. Z rozdílu DMP − DMR a „zelenosti“ ortofota se našly lokální vrcholy "
      f"korun; protože vyhlazený DMP slévá sousední koruny, velké korunové plochy se rozdělí na víc stromů. "
      f"Výsledek: **{s['n_trees']}** stromů se skutečnou polohou, výškou (medián {fmt(s['tree_h_median'], 1, 'm')}) "
      f"a šířkou koruny, barva listí je převzatá z ortofota. {s['n_conifers']} z nich jsou jehličnany.")
    a("")
    a(f"![Izometrie]({img}okoli-izometrie.jpg)")
    a("")
    a("## Textury")
    a("")
    a("- terén: ortofoto 8192 × 8192 px napnuté UV mapou na celý terén")
    a("- střechy: PBR tašky, jejichž barva se pro každou budovu tónuje mediánem ortofota uvnitř půdorysu")
    a("- fasády: PBR omítka v paletě světlých odstínů, barva jako atribut na ploše")
    a("- silnice a polní cesty: asfalt a štěrk položené na terén (výška = maximum terénu přes šířku + 6 cm)")
    a("- obloha: HDRI Kloofendal (partly cloudy)")
    a("")
    a("## Pro srovnání: první verze jen z OSM")
    a("")
    a(f"![První verze]({img}prvni-verze-osm.jpg)")
    a("")
    a("Stejné půdorysy, ale rovinný terén, výšky podle počtu podlaží, procedurální barvy a náhodně "
      "rozházené stromy. Rozdíl dělají hlavně výškové modely a ortofoto.")
    a("")
    a("## Co jsem se naučil")
    a("")
    a("- otevřená data ČÚZK stačí na věrohodné okolí bez jediného ručně modelovaného objektu")
    a("- každý převod souřadnic ověřit překryvem – tichá chyba o 110 m by jinak prošla")
    a("- DMP 1G není lidar: na tvary střech a jednotlivé stromy je potřeba kompenzace")
    a("- vše v headless skriptech + JSON mezivýstupech = snadno přenositelné do jiného 3D programu")
    a("")
    a("## Zdroje a licence")
    a("")
    a("- ČÚZK – DMR 5G, DMP 1G, Ortofoto ČR, RÚIAN (CC BY 4.0)")
    a("- © přispěvatelé OpenStreetMap (ODbL)")
    a("- Poly Haven – textury a HDRI (CC0)")
    a("- Blender 5.2, Python (numpy, scipy, pyproj, Pillow), Claude Code")
    a("")
    a(f"*Článek vygenerován automaticky z výstupů projektu {date.today().strftime('%-d. %-m. %Y')}.*")
    return "\n".join(L) + "\n"


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--site", default=os.environ.get("SVEC_SITE_ROOT", DEFAULT_SITE))
    ap.add_argument("--slug", default=DEFAULT_SLUG)
    ap.add_argument("--verejna-adresa", action="store_true", help="uvést adresu, souřadnice a kontrolní snímky")
    ap.add_argument("--dry-run", action="store_true", help="jen vypsat Markdown, nic neukládat")
    args = ap.parse_args()

    stats = collect_stats()
    body = build_body(stats, args.slug, args.verejna_adresa)
    if args.dry_run:
        print(body)
        return

    studio = os.path.join(args.site, "projekty", "svec-studio")
    sys.path.insert(0, studio)
    from svec_studio.articles import Articles
    from svec_studio.catalog import Catalog
    from svec_studio.change_history import ChangeLog, article_hostable_files
    from svec_studio.paths import SitePaths

    paths = SitePaths(__import__("pathlib").Path(args.site))
    catalog = Catalog(paths)
    arts = Articles(paths, catalog)

    img_dir = paths.note_dir(args.slug) / "img"
    img_dir.mkdir(parents=True, exist_ok=True)
    written = []
    for src, dst, _alt, needs_public in IMAGES:
        sp = os.path.join(ROOT, "renders", src)
        if needs_public and not args.verejna_adresa:
            (img_dir / dst).unlink(missing_ok=True)
            continue
        if not os.path.exists(sp):
            print("WARN chybí render", src)
            continue
        im = Image.open(sp).convert("RGB")
        im.thumbnail((1600, 1600))
        im.save(img_dir / dst, quality=85, optimize=True, progressive=True)
        written.append(f"zajimavosti/{args.slug}/img/{dst}")

    existing = catalog.note(args.slug) or {}
    payload = {
        "id": args.slug,
        "title": "Reálné 3D okolí domu z otevřených geodat ČÚZK",
        "titleEn": "Real 3D surroundings of a house from Czech open geodata",
        "summary": "Terén, výšky budov, stromy a textury pro Blender model domu – automaticky z OSM, "
                   "DMR 5G, DMP 1G a ortofota. Včetně chyby o 110 metrů.",
        "summaryEn": "Terrain, building heights, trees and textures for a Blender house model – generated "
                     "from OSM, DMR 5G, DMP 1G and orthophoto. Including a 110-metre mistake.",
        "lead": "Jak z volně dostupných dat postavit věrohodné okolí 3D modelu domu – bez ručního modelování.",
        "leadEn": "Building believable surroundings for a 3D house model from open data – no manual modelling.",
        "category": "prakticke",
        "type": "prakticke",
        "pageMeta": "3D / GIS",
        "pageMetaEn": "3D / GIS",
        "publishedAt": existing.get("publishedAt") or date.today().isoformat(),
        "published": bool(existing.get("published", False)),  # nikdy nezveřejňuje sám
        "featured": bool(existing.get("featured", False)),
        "cover": "img/okoli-perspektiva.jpg",
        "keywords": "blender 3d gis čúzk dmr5g dmp1g ortofoto openstreetmap terén budovy stromy pyproj s-jtsk",
        "body": body,
    }
    res = arts.save_article(payload)
    files = article_hostable_files(args.slug) + written
    try:
        ChangeLog(paths).record("article.save", f"Automaticky aktualizován článek {args.slug} (Doubravy 3D okolí)",
                                files, extra={"slug": args.slug, "source": "Doubravy 122/scripts/publish_article.py"})
    except Exception as e:  # deník změn je jen pomůcka pro FTP frontu
        print("WARN deník změn:", e)
    print(json.dumps({"html": res["htmlPath"], "source": res["sourcePath"], "images": written,
                      "published": res["note"].get("published")}, ensure_ascii=False, indent=1))


if __name__ == "__main__":
    main()
