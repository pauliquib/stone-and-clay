"""Krajina za okrajem katastru (M6.2) → data/surround_height.bin + data/surround_surface.bin.

Levná hrubá krajina okolí pro pohled z výšky (dron, paraglide). Detailní terén končí na
hranici katastru (~5,2 × 4,6 km) – tento nástroj připraví nízkorozlišenou výškovou mřížku
okolí ~10 × 10 km (přesah `EXTENT` za každý okraj katastru, krok `STEP` m) a hrubou masku
povrchu (les / pole / louka / zástavba / voda) ze stejných licencovaných zdrojů jako mapa.

Zdroje (jen ČÚZK a OSM – viz README → Právní zásady obsahu):
  DMR 5G ČÚZK (© ČÚZK, CC BY 4.0)  – nástroj sám stáhne z ImageServeru (jako
        scripts/phase10_fetch_geodata_full.py), oblast = katastr + EXTENT; server
        interpoluje na krok STEP, takže stačí jeden požadavek.
        URL: https://ags.cuzk.cz/arcgis2/rest/services/dmr5g/ImageServer/exportImage
  OSM (© přispěvatelé OpenStreetMap, ODbL) – geodata/pbf/zlinsky-latest.osm.pbf
        (už ho používají tools/water.py, landuse.py, surface.py; případně stáhni
        znovu z https://download.geofabrik.de/europe/czech-republic.html – příslušný kraj).
  geodata/dtm_full_scene.npy + data/geodata_meta_full.json – přesná výška na hranici
        katastru, k níž se okolí do `EDGE_BLEND` m navazuje (žádný šev).

Výstup (oba v .gitignore – data/*.bin):
  data/surround_height.bin   magic "SURH", int32 verze(1), f32 x0, z0 (Godot souřadnice,
                             hrana buňky 0,0), f32 krok, int32 nx, nz, pak nx·nz float32
                             výšky (řádky od severu – stejně jako terrain_height.bin)
  data/surround_surface.bin  magic "SURS", stejná hlavička, pak nx·nz 1 B tříd:
                             0 tráva/louka, 1 orná půda, 2 sad, 3 les, 4 zástavba,
                             5 břeh/mokřad, 7 cesta (track/path), 8 voda
                             (třídy 0–7 = stejné číslování jako data/surface.bin)

Spuštění (z kořene repozitáře; závislosti numpy, Pillow, osmium – jako tools/surface.py):
  python3 tools/surroundings.py
  python3 tools/surroundings.py --step 30 --extent 3000
  --no-download   jen maska ze staženého DEM (geodata/dtm_surround_scene.npy + .json)
"""
import argparse
import io
import json
import math
import os
import struct
import sys
import time
import urllib.parse
import urllib.request

import numpy as np
from PIL import Image, ImageDraw

Image.MAX_IMAGE_PIXELS = None
HERE = os.path.dirname(os.path.abspath(__file__))
GAME = os.path.dirname(HERE)
ROOT = os.path.dirname(GAME)
DATA = os.path.join(GAME, "data")
GEO = os.path.join(ROOT, "geodata")

DMR_URL = "https://ags.cuzk.cz/arcgis2/rest/services/dmr5g/ImageServer/exportImage"
PBF = os.path.join(GEO, "pbf", "zlinsky-latest.osm.pbf")
DEM_NPY = os.path.join(GEO, "dtm_surround_scene.npy")
DEM_META = os.path.join(GEO, "dtm_surround_meta.json")

# --- laditelné konstanty -----------------------------------------------------
EXTENT = 2500.0      # přesah okolí za každý okraj katastru (m) → ~10 × 10 km celkem
STEP = 25.0          # krok mřížky okolí (m) – 20–30 m podle zadání
EDGE_BLEND = 300.0   # do této vzdálenosti od katastru přesná výška z DMR 5G (m)
H_REF_CORR = 0.0     # pojistka – výšky už jsou v herních metrech (odečteno H_ref při stahování)
WATERWAY_W = 10.0    # šířka čáry pro waterway=river|stream v masce (m)
DL_TIMEOUT = 240
DL_TRIES = 4


def jload(rel):
    return json.load(open(os.path.join(ROOT, rel)))


def bilinear(arr, x0, y1, res, x, y):
    """arr[řádek od severu, sloupec]; středy pixelů v x0+(c+.5)res, y1-(r+.5)res."""
    x, y = np.asarray(x, float), np.asarray(y, float)
    r = np.clip((y1 - y) / res - 0.5, 0, arr.shape[0] - 1.001)
    c = np.clip((x - x0) / res - 0.5, 0, arr.shape[1] - 1.001)
    r0, c0 = np.floor(r).astype(int), np.floor(c).astype(int)
    fr, fc = r - r0, c - c0
    return (arr[r0, c0] * (1 - fr) * (1 - fc) + arr[r0, c0 + 1] * (1 - fr) * fc +
            arr[r0 + 1, c0] * fr * (1 - fc) + arr[r0 + 1, c0 + 1] * fr * fc)


def get(url, params):
    q = url + "?" + urllib.parse.urlencode(params)
    for i in range(DL_TRIES):
        try:
            with urllib.request.urlopen(q, timeout=DL_TIMEOUT) as r:
                data = r.read()
            if data[:1] == b"{":
                raise RuntimeError(data[:300])
            return data
        except Exception as e:
            print("  retry", i + 1, e)
            time.sleep(3 * (i + 1))
    raise RuntimeError("download failed: " + q)


def scene_to_5514(meta_full, x, y):
    """Afinní transformace scéna → S-JTSK (EPSG:5514) z geodata_meta_full.json (pole i body)."""
    ax, bx, cx = meta_full["affine_scene_to_5514"]["X"]
    ay, by, cy = meta_full["affine_scene_to_5514"]["Y"]
    return ax * x + bx * y + cx, ay * x + by * y + cy


def scene_bbox_to_5514(meta_full, x0, x1, y0, y1):
    xs, ys = [], []
    for x, y in [(x0, y0), (x0, y1), (x1, y0), (x1, y1)]:
        X, Y = scene_to_5514(meta_full, x, y)
        xs.append(X)
        ys.append(Y)
    return min(xs), min(ys), max(xs), max(ys)


def download_dtm(x0, x1, y0, y1, meta_full, step):
    """Stáhne DMR 5G ČÚZK pro scénový obdélník (server interpoluje).
    Vrátí float32 matici [řádek od severu, sloupec] + bbox v S-JTSK
    (scénový obdélník je v něm kvůli rotaci natočený)."""
    bx0, by0, bx1, by1 = scene_bbox_to_5514(meta_full, x0, x1, y0, y1)
    nx = int(math.ceil((x1 - x0) / step)) + 1
    ny = int(math.ceil((y1 - y0) / step)) + 1
    print(f"DMR 5G: bbox 5514 X {bx0:.0f}..{bx1:.0f}, Y {by0:.0f}..{by1:.0f} -> {nx}x{ny} px")
    params = {
        "bbox": "%f,%f,%f,%f" % (bx0, by0, bx1, by1),
        "bboxSR": 5514,
        "imageSR": 5514,
        "size": "%d,%d" % (nx, ny),
        "format": "tiff",
        "pixelType": "F32",
        "interpolation": "RSP_BilinearInterpolation",
        "f": "image",
    }
    img = Image.open(io.BytesIO(get(DMR_URL, params)))
    arr = np.asarray(img, np.float32)
    print(f"DMR 5G stažen: {arr.shape}, {np.nanmin(arr):.1f}..{np.nanmax(arr):.1f} m n. m.")
    return arr, (bx0, by0, bx1, by1)


class Collector:
    """OSM plochy pro masku povrchu (jen tag-relevantní multipolygony a jednoduché plochy)."""
    CLS = {0: "tráva/louka", 1: "orná půda", 2: "sad", 3: "les", 4: "zástavba",
           5: "břeh/mokřad", 7: "cesta", 8: "voda"}

    def __init__(self):
        import osmium
        self.areas = []     # (cls, [outer latlon], [holes latlon])
        self.lines = []     # (cls, width_m, [latlon])

        class H(osmium.SimpleHandler):
            def __init__(hs, out):
                super().__init__()
                hs.out = out

            def _area_cls(hs, t):
                if t.get("natural") == "water" or t.get("landuse") in ("reservoir", "basin") \
                        or "water" in t:
                    return 8
                if t.get("landuse") == "forest" or t.get("natural") == "wood":
                    return 3
                if t.get("landuse") in ("farmland",):
                    return 1
                if t.get("landuse") in ("orchard", "vineyard", "allotments", "plant_nursery"):
                    return 2
                if t.get("landuse") in ("residential", "industrial", "commercial", "garages",
                                        "farmyard", "retail", "cemetery") or "building" in t:
                    return 4
                if t.get("natural") in ("wetland", "marsh"):
                    return 5
                return 0

            def area(hs, a):
                cls = hs._area_cls(a.tags)
                if not cls:
                    return
                try:
                    for outer in a.outer_rings():
                        pts = [(n.lat, n.lon) for n in outer]
                        holes = [[(n.lat, n.lon) for n in inner] for inner in a.inner_rings(outer)]
                        hs.out.areas.append((cls, pts, holes))
                except osmium.InvalidLocationError:
                    pass

            def way(hs, w):
                t = w.tags
                if t.get("waterway") in ("river", "stream", "canal"):
                    cls, wid = 8, WATERWAY_W
                elif t.get("highway") in ("track", "path", "bridleway"):
                    cls, wid = 7, 4.0
                else:
                    return
                try:
                    hs.out.lines.append((cls, wid, [(n.lat, n.lon) for n in w.nodes]))
                except osmium.InvalidLocationError:
                    pass

        self._handler = H(self)

    def apply(self, pbf):
        self._handler.apply_file(pbf, locations=True, idx="sparse_mem_array")


def main():
    ap = argparse.ArgumentParser(description="M6.2: hrubá krajina za okrajem katastru")
    ap.add_argument("--step", type=float, default=STEP, help="krok mřížky okolí (m)")
    ap.add_argument("--extent", type=float, default=EXTENT, help="přesah za katastr (m)")
    ap.add_argument("--no-download", action="store_true",
                    help="DEM nestahovat – použít %s + %s" % (DEM_NPY, DEM_META))
    a = ap.parse_args()
    step = float(a.step)
    extent = float(a.extent)

    meta = json.load(open(os.path.join(DATA, "map.json")))
    meta_full = jload("data/geodata_meta_full.json")
    ref = jload("data/scene_reference.json")
    h_ref = jload("data/terrain_ref.json")["H_ref"]
    hm = meta["height"]

    # scénový obdélník katastru (Godot x = scene x; Godot z = -scene y)
    kx0 = float(hm["x0"])
    kz0 = float(hm["z0"])
    kx1 = kx0 + (int(hm["w"]) - 1) * float(hm["spacing"])
    kz1 = kz0 + (int(hm["h"]) - 1) * float(hm["spacing"])
    sy0, sy1 = -kz1, -kz0            # scénové y (sever = větší)
    sx0, sx1 = kx0, kx1
    # obdélník okolí ve scéně
    ex0, ex1 = sx0 - extent, sx1 + extent
    ey0, ey1 = sy0 - extent, sy1 + extent
    # výstupní mřížka v Godot souřadnicích: x0 = ex0, z0 = -ey1
    gx0, gz0 = ex0, -ey1
    nx = int(math.ceil((ex1 - ex0) / step)) + 1
    nz = int(math.ceil((ey1 - ey0) / step)) + 1
    print(f"Okolí: katastr {kx1 - kx0:.0f}×{kz1 - kz0:.0f} m + {extent:.0f} m -> mřížka {nx}×{nz}, krok {step:.0f} m")

    # ---------------- výšky
    # body výstupní mřížky ve scéně
    xs = ex0 + np.arange(nx) * step
    ys = ey1 - np.arange(nz) * step
    XS_s, YS_s = np.meshgrid(xs, ys)
    if a.no_download:
        # uložený rastr v S-JTSK (viz download_dtm): dosoučet přes affinní transformaci
        dem = np.load(DEM_NPY).astype(np.float64)
        dm = json.load(open(DEM_META))
        bx0, by0, bx1, by1 = dm["bbox_5514"]
    else:
        dem, (bx0, by0, bx1, by1) = download_dtm(ex0, ex1, ey0, ey1, meta_full, step)
        np.save(DEM_NPY, dem.astype(np.float32))
        json.dump({"bbox_5514": [bx0, by0, bx1, by1],
                   "dem_w": int(dem.shape[1]), "dem_h": int(dem.shape[0]),
                   "note": "S-JTSK souřadnice; řádky od severu (Y klesá); nadm. výška Bpv"},
                  open(DEM_META, "w"), indent=1)
    # pro každý bod scény dosoučtat DEM v souřadnicích 5514 (affinně; x a y krok zvlášť)
    XQ, YQ = scene_to_5514(meta_full, XS_s, YS_s)
    res_x = (bx1 - bx0) / (dem.shape[1] - 1)
    res_y = (by1 - by0) / (dem.shape[0] - 1)
    # bilinear() očekává jeden krok – zobecněný dosoučet pro různé kroky x/y
    rr = np.clip((by1 - YQ) / res_y - 0.5, 0, dem.shape[0] - 1.001)
    cc = np.clip((XQ - bx0) / res_x - 0.5, 0, dem.shape[1] - 1.001)
    r0, c0 = np.floor(rr).astype(int), np.floor(cc).astype(int)
    fr, fc = rr - r0, cc - c0
    grid = (dem[r0, c0] * (1 - fr) * (1 - fc) + dem[r0, c0 + 1] * (1 - fr) * fc +
            dem[r0 + 1, c0] * fr * (1 - fc) + dem[r0 + 1, c0 + 1] * fr * fc)
    grid = grid - h_ref + H_REF_CORR

    # navázání na hranici katastru: do EDGE_BLEND metrů přejít na přesné DMR 5G okolí
    dtm = np.load(os.path.join(GEO, "dtm_full_scene.npy")).astype(np.float64) - h_ref
    fx0, fy1, fres = meta_full["grid_x0"], meta_full["grid_y1"], meta_full["dem_res"]
    xs = gx0 + np.arange(nx) * step
    zs = gz0 + np.arange(nz) * step
    XS, ZS = np.meshgrid(xs, zs)
    cx = np.clip(XS, kx0, kx1)
    cz = np.clip(ZS, kz0, kz1)
    dist = np.hypot(XS - cx, ZS - cz)
    edge_h = bilinear(dtm, fx0, fy1, fres, cx, -cz)
    blend = np.clip(dist / EDGE_BLEND, 0.0, 1.0)
    grid = edge_h * (1.0 - blend) + grid * blend

    out_h = os.path.join(DATA, "surround_height.bin")
    with open(out_h, "wb") as f:
        f.write(b"SURH")
        f.write(struct.pack("<i3f2i", 1, gx0, gz0, step, nx, nz))
        f.write(grid.astype(np.float32).tobytes())
    print(f"WROTE {out_h}: {nx}×{nz} bodů, {grid.min():.1f}..{grid.max():.1f} m (x0={gx0:.0f}, z0={gz0:.0f})")

    # ---------------- maska povrchu z OSM
    if not os.path.exists(PBF):
        print(f"POZOR: chybí {PBF} – maska nevznikla (stáhni zlinsky-latest.osm.pbf, viz docstring)")
        return
    col = Collector()
    col.apply(PBF)
    print(f"OSM: {len(col.areas)} ploch, {len(col.lines)} čar")

    sys.path.insert(0, os.path.join(ROOT, "scripts"))
    from phase2_osm_to_local import make_transform  # noqa: E402
    tf = make_transform(ref)

    def to_px(pts):
        out = []
        for la, lo in pts:
            sx, sy = tf(la, lo)
            out.append(((sx - gx0) / step - 0.5, ((-sy) - gz0) / step - 0.5))
        return out

    mask = np.zeros((nz, nx), np.uint8)
    # pořadí vrstev: pozdější přepisuje dřívější (základ 0 → pole → zástavba → les → břeh → voda → cesta)
    order = {1: 1, 2: 2, 4: 3, 3: 4, 5: 5, 8: 6}
    for cls, outer, holes in sorted(col.areas, key=lambda a: order.get(a[0], 0)):
        if len(outer) < 3:
            continue
        lyr = Image.new("L", (nx, nz), 0)
        dr = ImageDraw.Draw(lyr)
        dr.polygon(to_px(outer), fill=1)
        for h in holes:
            if len(h) >= 3:
                dr.polygon(to_px(h), fill=0)
        m = np.array(lyr, bool)
        mask[m] = cls
    # čáry (voda, cesty) – jednoduchá tlustá čára
    for cls, wid, pts in col.lines:
        if len(pts) < 2:
            continue
        lyr = Image.new("L", (nx, nz), 0)
        dr = ImageDraw.Draw(lyr)
        dr.line(to_px(pts), fill=1, width=max(1, int(wid / step)))
        mask[np.array(lyr, bool)] = cls

    out_s = os.path.join(DATA, "surround_surface.bin")
    with open(out_s, "wb") as f:
        f.write(b"SURS")
        f.write(struct.pack("<i3f2i", 1, gx0, gz0, step, nx, nz))
        f.write(mask.tobytes())
    uniq, cnt = np.unique(mask, return_counts=True)
    print(f"WROTE {out_s}: " + ", ".join(
        f"{Collector.CLS.get(int(u), u)}={int(c)}" for u, c in zip(uniq, cnt)))


if __name__ == "__main__":
    main()
