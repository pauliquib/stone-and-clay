"""Fáze 6b – stažení přesných geodat ČÚZK a převzorkování do mřížky scény.

Zdroje (ČÚZK, otevřená data, © ČÚZK, CC BY 4.0):
  - DMR 5G  (digitální model reliéfu, terén)       ags.cuzk.cz/arcgis2/.../dmr5g/ImageServer
  - DMP 1G  (digitální model povrchu, střechy/stromy) ags.cuzk.cz/arcgis2/.../dmp1g/ImageServer
  - Ortofoto ČR (0,125 m/px)                        ags.cuzk.cz/arcgis1/.../ORTOFOTO/MapServer
Stahuje se v S-JTSK / Křovák East-North (EPSG:5514), pak se afinně (přes pyproj,
reziduum < 1 cm) převzorkuje do čtvercové mřížky zarovnané s osami scény.

Výstupy (geodata/, mimo git):
  dtm_scene.npy, dsm_scene.npy  – float32, 1 m/px, řádek 0 = max Y scény
  ortho_scene.jpg              – 8192×8192 px (~0,127 m/px)
  pipeline/data/geodata_meta.json       – rozsah mřížky, afinní transformace, kontrolní hodnoty
"""
import io
import json
import math
import os
import sys
import time
import urllib.parse
import urllib.request

import numpy as np
from PIL import Image
from pyproj import CRS, Transformer

Image.MAX_IMAGE_PIXELS = None
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)          # pipeline/ – data/, assets/, renders/, logs/
GAME = os.path.dirname(ROOT)          # kořen repozitáře hry – geodata/, blend/
GEO = os.path.join(GAME, "geodata")
os.makedirs(GEO, exist_ok=True)

DMR = "https://ags.cuzk.cz/arcgis2/rest/services/dmr5g/ImageServer/exportImage"
DMP = "https://ags.cuzk.cz/arcgis2/rest/services/dmp1g/ImageServer/exportImage"
ORTO = "https://ags.cuzk.cz/arcgis1/rest/services/ORTOFOTO/MapServer/export"

HALF = 520.0          # polovina strany čtverce scény (m) – pokrývá kruh r 480 m
DEM_RES = 1.0         # m/px výšková mřížka ve scéně
ORTHO_PX = 8192       # px ortofota ve scéně
SRC_ORTHO_RES = 0.125 # m/px zdrojové ortofoto
TILE = 4096


def get(url, params, tries=4):
    q = url + "?" + urllib.parse.urlencode(params)
    for i in range(tries):
        try:
            with urllib.request.urlopen(q, timeout=180) as r:
                data = r.read()
            if data[:1] == b"{":
                raise RuntimeError(data[:300])
            return data
        except Exception as e:
            print("  retry", i + 1, e)
            time.sleep(3 * (i + 1))
    raise RuntimeError("download failed: " + q)


def scene_to_5514_affine(ref):
    """Afinní transformace scéna (x, y) → EPSG:5514 (X, Y) fitovaná na síti bodů."""
    lat0, lon0 = ref["house_latlon"]
    hx, hy = ref["house_scene_xy"]
    mpu = ref.get("meters_per_unit", 1.0)
    a = math.radians(ref["north_angle_deg"])
    ca, sa = math.cos(a), math.sin(a)
    # 1) AEQD (koule, stejně jako fáze 2) → lat/lon (hodnoty = WGS84 z OSM)
    from pyproj import Proj
    aeqd = Proj(f"+proj=aeqd +lat_0={lat0} +lon_0={lon0} +R=6371008.8 +units=m +no_defs")
    # 2) WGS84 → S-JTSK Křovák (EPSG:5514) oficiální Helmertovou transformací
    tr = Transformer.from_crs(CRS.from_epsg(4326), CRS.from_epsg(5514), always_xy=True)
    xs, ys = np.meshgrid(np.linspace(hx - HALF, hx + HALF, 21), np.linspace(hy - HALF, hy + HALF, 21))
    xs, ys = xs.ravel(), ys.ravel()
    dx, dy = (xs - hx) * mpu, (ys - hy) * mpu
    e = dx * ca + dy * sa
    n = -dx * sa + dy * ca
    lon, lat = aeqd(e, n, inverse=True)
    X, Y = tr.transform(lon, lat)
    A = np.c_[xs, ys, np.ones_like(xs)]
    cx, *_ = np.linalg.lstsq(A, X, rcond=None)
    cy, *_ = np.linalg.lstsq(A, Y, rcond=None)
    res = np.hypot(A @ cx - X, A @ cy - Y).max()
    print(f"affine scene->5514 max residual {res * 100:.2f} cm; transform: {tr.description}")
    return cx, cy, float(res)


def resample(img, src_bbox, src_res, cx, cy, x0, y1, out_res, out_n, resample_mode):
    """PIL affine: výstupní pixel (c, r) scény → vstupní pixel zdroje."""
    # spojité souřadnice: výstup (p, q) ↔ scéna x = x0 + p*out_res, y = y1 - q*out_res
    #                    vstup (u, v) ↔ 5514  u = (X - bx0)/src_res, v = (by1 - Y)/src_res
    bx0, by1 = src_bbox[0], src_bbox[3]
    ax, bx_, c0 = cx
    ay, by_, d0 = cy
    k = out_res / src_res
    coeffs = (ax * k, -bx_ * k, (ax * x0 + bx_ * y1 + c0 - bx0) / src_res,
              -ay * k, by_ * k, (by1 - ay * x0 - by_ * y1 - d0) / src_res)
    return img.transform((out_n, out_n), Image.AFFINE, coeffs, resample=resample_mode)


def main():
    ref = json.load(open(os.path.join(ROOT, "data", "scene_reference.json"), encoding="utf-8"))
    hx, hy = ref["house_scene_xy"]
    cx, cy, resid = scene_to_5514_affine(ref)
    x0, y1 = hx - HALF, hy + HALF
    corners = np.array([[hx - HALF, hy - HALF], [hx + HALF, hy - HALF], [hx + HALF, hy + HALF], [hx - HALF, hy + HALF]])
    X = corners @ cx[:2] + cx[2]
    Y = corners @ cy[:2] + cy[2]
    m = 15.0
    bbox = [math.floor(X.min() - m), math.floor(Y.min() - m), math.ceil(X.max() + m), math.ceil(Y.max() + m)]
    print("5514 bbox", bbox, "size", bbox[2] - bbox[0], bbox[3] - bbox[1])

    # ---------- výškové modely (1 m)
    W = int((bbox[2] - bbox[0]) / DEM_RES)
    H = int((bbox[3] - bbox[1]) / DEM_RES)
    bbox_dem = [bbox[0], bbox[1], bbox[0] + W * DEM_RES, bbox[1] + H * DEM_RES]
    n_dem = int(2 * HALF / DEM_RES)
    out = {}
    for name, url in (("dtm", DMR), ("dsm", DMP)):
        raw_path = os.path.join(GEO, f"{name}_5514.tif")
        if not os.path.exists(raw_path):
            print("download", name, W, "x", H)
            data = get(url, {"bbox": ",".join(map(str, bbox_dem)), "bboxSR": 5514, "imageSR": 5514,
                             "size": f"{W},{H}", "format": "tiff", "pixelType": "F32", "noData": -9999,
                             "interpolation": "RSP_BilinearInterpolation", "f": "image"})
            open(raw_path, "wb").write(data)
        img = Image.open(raw_path)
        arr = np.array(img, dtype=np.float32)
        print(f"  {name}: {arr.shape} min {np.nanmin(arr[arr > -9000]):.2f} max {arr.max():.2f} "
              f"nodata {(arr < -9000).sum()}")
        if (arr < -9000).any():  # díry doplň nejbližší platnou hodnotou
            from scipy import ndimage
            bad = arr < -9000
            idx = ndimage.distance_transform_edt(bad, return_distances=False, return_indices=True)
            arr = arr[tuple(idx)]
        sc = resample(Image.fromarray(arr, mode="F"), bbox_dem, DEM_RES, cx, cy, x0, y1, DEM_RES, n_dem,
                      Image.BILINEAR)
        out[name] = np.array(sc, dtype=np.float32)
        np.save(os.path.join(GEO, f"{name}_scene.npy"), out[name])

    # ---------- ortofoto (dlaždice 4096 px à 0,125 m)
    ortho_path = os.path.join(GEO, "ortho_5514.jpg")
    OW = int(math.ceil((bbox[2] - bbox[0]) / SRC_ORTHO_RES / TILE)) * TILE
    OH = int(math.ceil((bbox[3] - bbox[1]) / SRC_ORTHO_RES / TILE)) * TILE
    bbox_o = [bbox[0], bbox[3] - OH * SRC_ORTHO_RES, bbox[0] + OW * SRC_ORTHO_RES, bbox[3]]
    if not os.path.exists(ortho_path):
        mosaic = Image.new("RGB", (OW, OH))
        for j in range(OH // TILE):
            for i in range(OW // TILE):
                tb = [bbox_o[0] + i * TILE * SRC_ORTHO_RES, bbox_o[3] - (j + 1) * TILE * SRC_ORTHO_RES,
                      bbox_o[0] + (i + 1) * TILE * SRC_ORTHO_RES, bbox_o[3] - j * TILE * SRC_ORTHO_RES]
                print(f"download ortho tile {i},{j}")
                data = get(ORTO, {"bbox": ",".join(f"{v:.3f}" for v in tb), "bboxSR": 5514, "imageSR": 5514,
                                  "size": f"{TILE},{TILE}", "format": "jpg", "transparent": "false",
                                  "dpi": 96, "f": "image"})
                mosaic.paste(Image.open(io.BytesIO(data)).convert("RGB"), (i * TILE, j * TILE))
        mosaic.save(ortho_path, quality=92)
    mosaic = Image.open(ortho_path).convert("RGB")
    ortho_res_scene = 2 * HALF / ORTHO_PX
    osc = resample(mosaic, bbox_o, SRC_ORTHO_RES, cx, cy, x0, y1, ortho_res_scene, ORTHO_PX, Image.BICUBIC)
    osc.save(os.path.join(GEO, "ortho_scene.jpg"), quality=92)
    print("ortho scene", osc.size, f"{ortho_res_scene:.4f} m/px")

    meta = {
        "grid_x0": x0, "grid_y1": y1, "half": HALF, "center": [hx, hy],
        "dem_res": DEM_RES, "dem_n": n_dem, "ortho_px": ORTHO_PX, "ortho_res": ortho_res_scene,
        "affine_scene_to_5514": {"X": cx.tolist(), "Y": cy.tolist(), "max_residual_m": resid},
        "bbox_5514": bbox, "sources": {"dtm": DMR, "dsm": DMP, "ortho": ORTO},
        "license": "© ČÚZK, CC BY 4.0",
        "dtm_at_house": float(out["dtm"][int(HALF / DEM_RES), int(HALF / DEM_RES)]),
    }
    json.dump(meta, open(os.path.join(ROOT, "data", "geodata_meta.json"), "w"), indent=2)
    print(json.dumps(meta, indent=1))


if __name__ == "__main__":
    sys.exit(main())
