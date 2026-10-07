"""Fáze 10 – geodata ČÚZK pro CELÝ katastr obce Doubravy (rozšíření okolí).

Stejné zdroje a princip jako pipeline/scripts/phase6_fetch_geodata.py (DMR 5G, DMP 1G,
Ortofoto ČR, © ČÚZK CC BY 4.0), ale nad mnohem větší, ne-čtvercovou oblastí
(celý katastr ~5,2 × 4,6 km vč. marže). Zjištěné limity ImageServeru
(maxImageHeight 4100, maxImageWidth 15000, nativní rozlišení 2 m) umožňují
stáhnout DMR/DMP v JEDNOM požadavku (bez dláždění). Ortofoto (limit 4096×4096)
se skládá z dlaždic jako ve fázi 6, cílové rozlišení voleno tak, aby výsledná
mozaika nepřekročila ~8000 px na delší straně (jinak by nešla použít jako
jedna textura).

Výstupy (geodata/, mimo git):
  dtm_full_scene.npy, dsm_full_scene.npy – float32, 2 m/px (nativní rozlišení
                                            DMR5G/DMP1G, žádné dosourcování)
  ortho_full_scene.jpg                   – mozaika, ~0,6-0,7 m/px
  pipeline/data/geodata_meta_full.json   – rozsah mřížky, afinní transformace
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

MARGIN = 200.0     # m, přesah za hranici katastru (stejně jako phase9)
DEM_RES = 2.0       # m/px – nativní rozlišení DMR5G/DMP1G, žádné dosourcování
SRC_ORTHO_RES = 0.125
ORTHO_TILE = 4096   # limit MapServeru
ORTHO_TARGET_PX = 8000  # max delší strana výsledné mozaiky


def get(url, params, tries=4):
    q = url + "?" + urllib.parse.urlencode(params)
    for i in range(tries):
        try:
            with urllib.request.urlopen(q, timeout=240) as r:
                data = r.read()
            if data[:1] == b"{":
                raise RuntimeError(data[:300])
            return data
        except Exception as e:
            print("  retry", i + 1, e)
            time.sleep(3 * (i + 1))
    raise RuntimeError("download failed: " + q)


def scene_to_5514_affine(ref, x0, x1, y0, y1):
    lat0, lon0 = ref["house_latlon"]
    hx, hy = ref["house_scene_xy"]
    mpu = ref.get("meters_per_unit", 1.0)
    a = math.radians(ref["north_angle_deg"])
    ca, sa = math.cos(a), math.sin(a)
    from pyproj import Proj
    aeqd = Proj(f"+proj=aeqd +lat_0={lat0} +lon_0={lon0} +R=6371008.8 +units=m +no_defs")
    tr = Transformer.from_crs(CRS.from_epsg(4326), CRS.from_epsg(5514), always_xy=True)
    xs, ys = np.meshgrid(np.linspace(x0, x1, 25), np.linspace(y0, y1, 25))
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
    print(f"affine scene->5514 max residual {res:.3f} m over full extent")
    return cx, cy, float(res)


def resample(img, src_bbox, src_res, cx, cy, x0, y1, out_res, out_w, out_h, resample_mode):
    bx0, by1 = src_bbox[0], src_bbox[3]
    ax, bx_, c0 = cx
    ay, by_, d0 = cy
    k = out_res / src_res
    coeffs = (ax * k, -bx_ * k, (ax * x0 + bx_ * y1 + c0 - bx0) / src_res,
              -ay * k, by_ * k, (by1 - ay * x0 - by_ * y1 - d0) / src_res)
    return img.transform((out_w, out_h), Image.AFFINE, coeffs, resample=resample_mode)


def main():
    ref = json.load(open(os.path.join(ROOT, "data", "scene_reference.json"), encoding="utf-8"))
    admin = json.load(open(os.path.join(ROOT, "data", "doubravy_admin_boundary.json"), encoding="utf-8"))
    xs = [p[0] for p in admin["scene_poly"]]
    ys = [p[1] for p in admin["scene_poly"]]
    x0, x1 = min(xs) - MARGIN, max(xs) + MARGIN
    y0, y1 = min(ys) - MARGIN, max(ys) + MARGIN
    print(f"scene bbox X {x0:.0f}..{x1:.0f} ({x1-x0:.0f} m)  Y {y0:.0f}..{y1:.0f} ({y1-y0:.0f} m)")

    cx, cy, resid = scene_to_5514_affine(ref, x0, x1, y0, y1)
    corners = np.array([[x0, y0], [x1, y0], [x1, y1], [x0, y1]])
    X = corners @ cx[:2] + cx[2]
    Y = corners @ cy[:2] + cy[2]
    m = 15.0
    bbox = [math.floor(X.min() - m), math.floor(Y.min() - m), math.ceil(X.max() + m), math.ceil(Y.max() + m)]
    print("5514 bbox", bbox, "size", bbox[2] - bbox[0], bbox[3] - bbox[1])

    # ---------- DMR/DMP – nativní 2 m, v jednom požadavku (limit 4100x15000 px)
    # POZOR: scéna je vůči 5514 pootočená (~78 deg), takže rozměr zdrojového
    # (5514) obdélníku NENÍ stejný jako rozměr cílové (scéna) mřížky - musí
    # se počítat z `bbox` (5514), jinak zdrojový snímek nepokryje celou
    # rotovanou cílovou oblast a chybějící roh se dosampluje jako 0 m n. m.
    W = int(round((x1 - x0) / DEM_RES))   # cílová (scéna) mřížka - pro output/resample
    H = int(round((y1 - y0) / DEM_RES))
    Ws = int(math.ceil((bbox[2] - bbox[0]) / DEM_RES))  # zdrojový (5514) rozměr ke stažení
    Hs = int(math.ceil((bbox[3] - bbox[1]) / DEM_RES))
    print("DEM output grid (scene)", W, "x", H, " source download grid (5514)", Ws, "x", Hs,
          f"(limit 15000x4100, {'OK' if Ws<=15000 and Hs<=4100 else 'PREKROCENO!'})")
    bbox_dem = [bbox[0], bbox[1], bbox[0] + Ws * DEM_RES, bbox[1] + Hs * DEM_RES]
    out = {}
    for name, url in (("dtm_full", DMR), ("dsm_full", DMP)):
        raw_path = os.path.join(GEO, f"{name}_5514.tif")
        if not os.path.exists(raw_path):
            print("download", name, Ws, "x", Hs)
            data = get(url, {"bbox": ",".join(map(str, bbox_dem)), "bboxSR": 5514, "imageSR": 5514,
                             "size": f"{Ws},{Hs}", "format": "tiff", "pixelType": "F32", "noData": -9999,
                             "interpolation": "RSP_BilinearInterpolation", "f": "image"})
            open(raw_path, "wb").write(data)
        img = Image.open(raw_path)
        arr = np.array(img, dtype=np.float32)
        print(f"  {name}: {arr.shape} min {np.nanmin(arr[arr > -9000]):.2f} max {arr.max():.2f} "
              f"nodata {(arr < -9000).sum()}")
        if (arr < -9000).any():
            from scipy import ndimage
            bad = arr < -9000
            idx = ndimage.distance_transform_edt(bad, return_distances=False, return_indices=True)
            arr = arr[tuple(idx)]
        sc = resample(Image.fromarray(arr, mode="F"), bbox_dem, DEM_RES, cx, cy, x0, y1, DEM_RES, W, H,
                      Image.BILINEAR)
        scv = np.array(sc, dtype=np.float32)
        # bezpečnostní pojistka: reálný terén tady je 200-600 m n.m., cokoliv
        # nižší je artefakt vzorkování mimo staženou oblast - dosampluj nejbližší platnou hodnotou
        bad2 = scv < 100.0
        if bad2.any():
            from scipy import ndimage as _ndi
            print(f"  {name}: {bad2.sum()} pixelů mimo staženou oblast (< 100 m) - dosamplováno")
            idx2 = _ndi.distance_transform_edt(bad2, return_distances=False, return_indices=True)
            scv = scv[tuple(idx2)]
        out[name] = scv
        np.save(os.path.join(GEO, f"{name}_scene.npy"), out[name])

    # ---------- ortofoto (mozaika z dlaždic 4096 px, cíl <= 8000 px na delší straně)
    # Pozor na paměť: plná mozaika v nativních 0,125 m/px by pro celý katastr
    # byla ~45000x41000 px (přes 5 GB nekomprimovaně) - na tomto stroji
    # neproveditelné. Každá dlaždice se proto hned po stažení zmenší na
    # cílové rozlišení a skládá se rovnou zmenšená mozaika (v paměti jen
    # stovky MB), teprve ta se na konci afinně přeorientuje do scény.
    ortho_res_scene = max(x1 - x0, y1 - y0) / ORTHO_TARGET_PX
    OW = int(round((x1 - x0) / ortho_res_scene))
    OH = int(round((y1 - y0) / ortho_res_scene))
    print(f"ortho scene target {OW}x{OH} px @ {ortho_res_scene:.3f} m/px")

    OWs = int(math.ceil((bbox[2] - bbox[0]) / SRC_ORTHO_RES / ORTHO_TILE)) * ORTHO_TILE
    OHs = int(math.ceil((bbox[3] - bbox[1]) / SRC_ORTHO_RES / ORTHO_TILE)) * ORTHO_TILE
    bbox_o = [bbox[0], bbox[3] - OHs * SRC_ORTHO_RES, bbox[0] + OWs * SRC_ORTHO_RES, bbox[3]]
    ntx, nty = OWs // ORTHO_TILE, OHs // ORTHO_TILE
    downsample = max(1, round(ortho_res_scene / SRC_ORTHO_RES))
    tile_small = ORTHO_TILE // downsample
    mosaic_small_res = SRC_ORTHO_RES * downsample
    print(f"source ortho mosaic {OWs}x{OHs} px ({ntx}x{nty} tiles @ {ORTHO_TILE}), "
          f"downsample {downsample}x -> small mosaic {ntx*tile_small}x{nty*tile_small} @ {mosaic_small_res:.3f} m/px")

    small_path = os.path.join(GEO, "ortho_full_5514_small.jpg")
    if not os.path.exists(small_path):
        mosaic_small = Image.new("RGB", (ntx * tile_small, nty * tile_small))
        for j in range(nty):
            for i in range(ntx):
                tb = [bbox_o[0] + i * ORTHO_TILE * SRC_ORTHO_RES, bbox_o[3] - (j + 1) * ORTHO_TILE * SRC_ORTHO_RES,
                      bbox_o[0] + (i + 1) * ORTHO_TILE * SRC_ORTHO_RES, bbox_o[3] - j * ORTHO_TILE * SRC_ORTHO_RES]
                print(f"download ortho tile {i},{j} / {ntx-1},{nty-1}")
                data = get(ORTO, {"bbox": ",".join(f"{v:.3f}" for v in tb), "bboxSR": 5514, "imageSR": 5514,
                                  "size": f"{ORTHO_TILE},{ORTHO_TILE}", "format": "jpg", "transparent": "false",
                                  "dpi": 96, "f": "image"})
                tile = Image.open(io.BytesIO(data)).convert("RGB")
                tile = tile.resize((tile_small, tile_small), Image.LANCZOS)
                mosaic_small.paste(tile, (i * tile_small, j * tile_small))
                del data, tile
                mosaic_small.save(small_path, quality=90)  # průběžné ukládání, ať se dá navázat po výpadku
    mosaic_small = Image.open(small_path).convert("RGB")
    osc = resample(mosaic_small, bbox_o, mosaic_small_res, cx, cy, x0, y1, ortho_res_scene, OW, OH, Image.BICUBIC)
    osc.save(os.path.join(GEO, "ortho_full_scene.jpg"), quality=92)
    print("ortho scene", osc.size, f"{ortho_res_scene:.4f} m/px")

    meta = {
        "grid_x0": x0, "grid_y0": y0, "grid_x1": x1, "grid_y1": y1,
        "dem_res": DEM_RES, "dem_w": W, "dem_h": H,
        "ortho_w": OW, "ortho_h": OH, "ortho_res": ortho_res_scene,
        "affine_scene_to_5514": {"X": cx.tolist(), "Y": cy.tolist(), "max_residual_m": resid},
        "bbox_5514": bbox, "sources": {"dtm": DMR, "dsm": DMP, "ortho": ORTO},
        "license": "© ČÚZK, CC BY 4.0",
        "margin_m": MARGIN,
    }
    json.dump(meta, open(os.path.join(ROOT, "data", "geodata_meta_full.json"), "w"), indent=2)
    print(json.dumps(meta, indent=1))


if __name__ == "__main__":
    sys.exit(main())
