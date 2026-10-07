"""B2.1 – geodata ČÚZK pro UNION mřížku (detail mapa + 5 okolních obcí s rezervou).

Stejné zdroje a princip jako pipeline/scripts/phase10_fetch_geodata_full.py
(DMR 5G, DMP 1G, Ortofoto ČR, © ČÚZK CC BY 4.0), ale nad novou cílovou mřížkou
~11,3 × 7,5 km (x[-6149,5199], z[-3946,3596]) — obdélník přes katastry všech
5 okolních obcí z data/obce.json + katastr Dukelčic, fázově sladěný se starou
mřížkou (stejná fáze 2 m buněk → starý blok se do nové mřížky kopíruje bajtově,
viz tools/expand_map.py).

Rozdíly oproti fázi 10:
  * původní scénový bbox = hranice katastru + MARGIN; tady je mřížka určená
    přesně (vychází z data/map.json height + rozsah katastrů), pixel centra DEM
    = vrcholy herní výškové mřížky → expand_map bere výšky bez interpolace.
  * 5514 bbox je po rotaci ~78° vyšší než limit ImageServeru (4100 px) →
    DMR/DMP se stahují po PÁSECH a slepují do jedné mozaiky (resample až pak).
  * ortofoto se nestahuje v nativních 0,125 m/px (bylo by ~100 tis. px),
    ale rovnou v 2× supersamplingu cílového rozlišení (~20 dlaždic).

Výstupy (geodata/, mimo git):
  dtm_union_scene.npy, dsm_union_scene.npy – float32, 2 m/px, přesně W×H nové mřížky
  ortho_union_scene.jpg                  – mozaika, ~1,4 m/px
  pipeline/data/geodata_meta_union.json  – schéma jako geodata_meta_full.json
                                           + blok "union" (offsety starého bloku)
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
GAME = os.path.dirname(HERE)
PIPE = os.path.join(GAME, "pipeline")
PDATA = os.path.join(PIPE, "data")
GEO = os.path.join(GAME, "geodata")
DATA = os.path.join(GAME, "data")
os.makedirs(GEO, exist_ok=True)

DMR = "https://ags.cuzk.cz/arcgis2/rest/services/dmr5g/ImageServer/exportImage"
DMP = "https://ags.cuzk.cz/arcgis2/rest/services/dmp1g/ImageServer/exportImage"
ORTO = "https://ags.cuzk.cz/arcgis1/rest/services/ORTOFOTO/MapServer/export"

DEM_RES = 2.0           # m/px – nativní rozlišení DMR5G/DMP1G, žádné dosourcování
# Reálné limity ImageServeru 2025-06 (empiricky): dokumentované 15000×4100 už
# neplatí – HTTP 500 kolem ~8 Mpx resp. šířky ~4096. Bezpečná dlaždice 2048×2048.
DEM_TILE = 2048
ORTHO_TILE = 4096       # limit MapServeru
ORTHO_TARGET_PX = 8000  # max delší strana výsledné mozaiky (jako fáze 10)
ORTHO_SS = 2.0          # supersampling zdrojových dlaždic ortofota


# ------------------------------------------------------------------ mřížka

def load_old_meta():
    """Stará map.json meta – preferuje snapshot pre_expand (po expanzi je
    data/map.json už rozšířená; bez snapshotu vezme aktuální = novou mřížku)."""
    pe = os.path.join(PDATA, "pre_expand", "map.json")
    src = pe if os.path.exists(pe) else os.path.join(DATA, "map.json")
    return json.load(open(src, encoding="utf-8"))


def union_grid(meta_old, extra_polys=()):
    """Nová cílová mřížka: obdélník přes katastry (data/obce.json boundary +
    map.json boundary + extra_polys), nafouklý ven na fázi staré mřížky.

    Vrátí dict: x0, z0 (vrchol 0,0), w, h, spacing, col_off, row_off
    (kam starý blok [w_old×h_old] v nové mřížce padne), a DEM rozměry.
    """
    hm = meta_old["height"]
    x0o, z0o = float(hm["x0"]), float(hm["z0"])
    sp = float(hm["spacing"])
    wo, ho = int(hm["w"]), int(hm["h"])
    x1o, z1o = x0o + (wo - 1) * sp, z0o + (ho - 1) * sp

    xs, zs = [x0o, x1o], [z0o, z1o]
    polys = [meta_old.get("boundary", [])]
    obce = json.load(open(os.path.join(DATA, "obce.json")))
    polys += [o["boundary"] for o in obce["obce"]]
    polys += list(extra_polys)
    for poly in polys:
        for px, pz in poly:
            xs.append(px)
            zs.append(pz)
    xmin, xmax, zmin, zmax = min(xs), max(xs), min(zs), max(zs)
    print(f"union target extent: x[{xmin:.1f},{xmax:.1f}] z[{zmin:.1f},{zmax:.1f}]")

    kx0 = max(0, math.ceil((x0o - xmin) / sp))
    kx1 = max(0, math.ceil((xmax - x1o) / sp))
    kz0 = max(0, math.ceil((z0o - zmin) / sp))
    kz1 = max(0, math.ceil((zmax - z1o) / sp))
    g = {
        "x0": x0o - kx0 * sp, "z0": z0o - kz0 * sp,
        "w": wo + kx0 + kx1, "h": ho + kz0 + kz1, "spacing": sp,
        "col_off": kx0, "row_off": kz0,
    }
    g["x1"] = g["x0"] + (g["w"] - 1) * sp
    g["z1"] = g["z0"] + (g["h"] - 1) * sp
    # hrany DEM pixelů (pixel centra = vrcholy mřížky)
    g["grid_x0"], g["grid_y1"] = g["x0"] - sp / 2, -g["z0"] + sp / 2
    g["grid_x1"], g["grid_y0"] = g["x1"] + sp / 2, -g["z1"] - sp / 2
    # kontrola fázového sladění – musí vyjít celočíselně
    assert abs((x0o - g["x0"]) / sp - kx0) < 1e-9 and abs((z0o - g["z0"]) / sp - kz0) < 1e-9
    print(f"union grid: {g['w']}×{g['h']} @ {sp} m, x0={g['x0']:.3f} z0={g['z0']:.3f} "
          f"(x1={g['x1']:.3f} z1={g['z1']:.3f}), starý blok → col+{kx0} row+{kz0}")
    return g


def scene_to_5514_affine(ref, x0, x1, y0, y1):
    """Kopie z phase10: afinní fit scéna→S-JTSK přes 25×25 bodů (max residuál ~cm)."""
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
    print(f"affine scene->5514 max residual {res:.3f} m over union extent")
    return cx, cy, float(res)


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


def resample(img, src_bbox, src_res, cx, cy, x0, y1, out_res, out_w, out_h, resample_mode):
    """Kopie z phase10: afinní PIL transform 5514→scénová mřížka."""
    bx0, by1 = src_bbox[0], src_bbox[3]
    ax, bx_, c0 = cx
    ay, by_, d0 = cy
    k = out_res / src_res
    coeffs = (ax * k, -bx_ * k, (ax * x0 + bx_ * y1 + c0 - bx0) / src_res,
              -ay * k, by_ * k, (by1 - ay * x0 - by_ * y1 - d0) / src_res)
    return img.transform((out_w, out_h), Image.AFFINE, coeffs, resample=resample_mode)


def fetch_dem(url, name, bbox, Ws, Hs):
    """Stáhne DEM pro 5514 bbox po dlaždicích DEM_TILE² (limity serveru ~8 Mpx)."""
    raw_dir = os.path.join(GEO, "union_tiles")
    os.makedirs(raw_dir, exist_ok=True)
    ntx = math.ceil(Ws / DEM_TILE)
    nty = math.ceil(Hs / DEM_TILE)
    mosaic = np.empty((Hs, Ws), np.float32)
    n_dl = 0
    for ty in range(nty):
        for tx in range(ntx):
            c0, c1 = tx * DEM_TILE, min((tx + 1) * DEM_TILE, Ws)
            r0, r1 = ty * DEM_TILE, min((ty + 1) * DEM_TILE, Hs)
            tb = [bbox[0] + c0 * DEM_RES, bbox[3] - r1 * DEM_RES,
                  bbox[0] + c1 * DEM_RES, bbox[3] - r0 * DEM_RES]
            raw_path = os.path.join(raw_dir, f"{name}_{tx}x{ty}.tif")
            if not os.path.exists(raw_path):
                print(f"  download {name} tile {tx},{ty} / {ntx - 1},{nty - 1}: "
                      f"{c1 - c0}×{r1 - r0}")
                data = get(url, {"bbox": ",".join(map(str, tb)), "bboxSR": 5514,
                                 "imageSR": 5514, "size": f"{c1 - c0},{r1 - r0}",
                                 "format": "tiff", "pixelType": "F32", "noData": -9999,
                                 "interpolation": "RSP_BilinearInterpolation",
                                 "f": "image"}, tries=6)
                open(raw_path, "wb").write(data)
                n_dl += 1
            arr = np.array(Image.open(raw_path), dtype=np.float32)
            if arr.shape != (r1 - r0, c1 - c0):
                raise RuntimeError(f"{raw_path}: neočekávaný rozměr {arr.shape}, "
                                   f"čeká se {(r1 - r0, c1 - c0)}")
            mosaic[r0:r1, c0:c1] = arr
    print(f"  {name}: mozaika {mosaic.shape} z {ntx * nty} dlaždic "
          f"(staženo {n_dl} nových) min {np.nanmin(mosaic[mosaic > -9000]):.2f} "
          f"max {mosaic.max():.2f} nodata {(mosaic < -9000).sum()}")
    if (mosaic < -9000).any():
        from scipy import ndimage
        bad = mosaic < -9000
        idx = ndimage.distance_transform_edt(bad, return_distances=False, return_indices=True)
        mosaic = mosaic[tuple(idx)]
    return mosaic


def main():
    ref = json.load(open(os.path.join(PDATA, "scene_reference.json"), encoding="utf-8"))
    meta_old = load_old_meta()
    g = union_grid(meta_old)
    x0, x1 = g["grid_x0"], g["grid_x1"]
    y0, y1 = g["grid_y0"], g["grid_y1"]
    W, H = g["w"], g["h"]
    print(f"scene bbox X {x0:.1f}..{x1:.1f} ({x1 - x0:.0f} m)  Y {y0:.1f}..{y1:.1f} ({y1 - y0:.0f} m)")

    cx, cy, resid = scene_to_5514_affine(ref, x0, x1, y0, y1)
    corners = np.array([[x0, y0], [x1, y0], [x1, y1], [x0, y1]])
    X = corners @ cx[:2] + cx[2]
    Y = corners @ cy[:2] + cy[2]
    m = 15.0
    bbox = [math.floor(X.min() - m), math.floor(Y.min() - m), math.ceil(X.max() + m), math.ceil(Y.max() + m)]
    print("5514 bbox", bbox, "size", bbox[2] - bbox[0], bbox[3] - bbox[1])

    # ---------- DMR/DMP – nativní 2 m; zdrojový 5514 rozměr může přesáhnout limit → pásy
    Ws = int(math.ceil((bbox[2] - bbox[0]) / DEM_RES))
    Hs = int(math.ceil((bbox[3] - bbox[1]) / DEM_RES))
    print(f"DEM output grid (scene) {W}×{H}, source download grid (5514) {Ws}×{Hs} "
          f"→ {math.ceil(Ws / DEM_TILE)}×{math.ceil(Hs / DEM_TILE)} dlaždic {DEM_TILE}px")
    bbox_dem = [bbox[0], bbox[1], bbox[0] + Ws * DEM_RES, bbox[1] + Hs * DEM_RES]
    out = {}
    for name, url in (("dtm_union", DMR), ("dsm_union", DMP)):
        mosaic = fetch_dem(url, name, bbox_dem, Ws, Hs)
        sc = resample(Image.fromarray(mosaic, mode="F"), bbox_dem, DEM_RES, cx, cy,
                      x0, y1, DEM_RES, W, H, Image.BILINEAR)
        scv = np.array(sc, dtype=np.float32)
        # pojistka: reálný terén 200–600 m n.m., nižší = artefakt mimo staženou oblast
        bad2 = scv < 100.0
        if bad2.any():
            from scipy import ndimage as _ndi
            print(f"  {name}: {bad2.sum()} pixelů mimo oblast (< 100 m) – dosamplováno")
            idx2 = _ndi.distance_transform_edt(bad2, return_distances=False, return_indices=True)
            scv = scv[tuple(idx2)]
        out[name] = scv
        np.save(os.path.join(GEO, f"{name}_scene.npy"), scv)

    # ---------- ověření shody na překryvu se starou mřížkou (dtm_full)
    full_path = os.path.join(GEO, "dtm_full_scene.npy")
    if os.path.exists(full_path):
        mf = json.load(open(os.path.join(PDATA, "geodata_meta_full.json")))
        dtm_f = np.load(full_path).astype(np.float64)
        rng = np.random.default_rng(7)
        # náhodné body uvnitř staré mřížky (s okrajem), vzorkováno bilineárně v obou
        fx0, fy1, fr = mf["grid_x0"], mf["grid_y1"], mf["dem_res"]
        qx = rng.uniform(fx0 + 50, fx0 + mf["dem_w"] * fr - 50, 4000)
        qy = rng.uniform(fy1 - mf["dem_h"] * fr + 50, fy1 - 50, 4000)

        def bilin(arr, gx0, gy1, res, x, y):
            r = np.clip((gy1 - y) / res - 0.5, 0, arr.shape[0] - 1.001)
            c = np.clip((x - gx0) / res - 0.5, 0, arr.shape[1] - 1.001)
            r0, c0 = np.floor(r).astype(int), np.floor(c).astype(int)
            fr_, fc_ = r - r0, c - c0
            return (arr[r0, c0] * (1 - fr_) * (1 - fc_) + arr[r0, c0 + 1] * (1 - fr_) * fc_ +
                    arr[r0 + 1, c0] * fr_ * (1 - fc_) + arr[r0 + 1, c0 + 1] * fr_ * fc_)

        a = bilin(dtm_f, fx0, fy1, fr, qx, qy)
        b = bilin(out["dtm_union"].astype(np.float64), x0, y1, DEM_RES, qx, qy)
        d = np.abs(a - b)
        print(f"OVERLAP CHECK dtm_union vs dtm_full: {d.size} bodů, "
              f"mean {d.mean():.4f} m, p95 {np.percentile(d, 95):.4f}, max {d.max():.4f} m")

    # ---------- ortofoto (dlaždice v 2× supersamplingu cílového rozlišení)
    ortho_res = max(x1 - x0, y1 - y0) / ORTHO_TARGET_PX
    OW = int(round((x1 - x0) / ortho_res))
    OH = int(round((y1 - y0) / ortho_res))
    src_res = ortho_res / ORTHO_SS
    print(f"ortho scene target {OW}×{OH} px @ {ortho_res:.3f} m/px (zdroj {src_res:.3f} m/px)")

    tile_geo = ORTHO_TILE * src_res          # geografická hrana dlaždice v 5514
    ntx = int(math.ceil((bbox[2] - bbox[0]) / tile_geo))
    nty = int(math.ceil((bbox[3] - bbox[1]) / tile_geo))
    OWs, OHs = ntx * ORTHO_TILE, nty * ORTHO_TILE
    bbox_o = [bbox[0], bbox[3] - OHs * src_res, bbox[0] + OWs * src_res, bbox[3]]
    tile_small = ORTHO_TILE // int(ORTHO_SS)
    mosaic_res = src_res * ORTHO_SS
    print(f"source ortho {ntx}×{nty} dlaždic @ {tile_geo:.0f} m → malá mozaika "
          f"{ntx * tile_small}×{nty * tile_small} @ {mosaic_res:.3f} m/px")

    small_path = os.path.join(GEO, "ortho_union_5514_small.jpg")
    if not os.path.exists(small_path):
        mosaic_small = Image.new("RGB", (ntx * tile_small, nty * tile_small))
        for j in range(nty):
            for i in range(ntx):
                tb = [bbox_o[0] + i * tile_geo, bbox_o[3] - (j + 1) * tile_geo,
                      bbox_o[0] + (i + 1) * tile_geo, bbox_o[3] - j * tile_geo]
                print(f"download ortho tile {i},{j} / {ntx - 1},{nty - 1}")
                data = get(ORTO, {"bbox": ",".join(f"{v:.3f}" for v in tb), "bboxSR": 5514,
                                  "imageSR": 5514, "size": f"{ORTHO_TILE},{ORTHO_TILE}",
                                  "format": "jpg", "transparent": "false", "dpi": 96, "f": "image"})
                tile = Image.open(io.BytesIO(data)).convert("RGB")
                tile = tile.resize((tile_small, tile_small), Image.LANCZOS)
                mosaic_small.paste(tile, (i * tile_small, j * tile_small))
                del data, tile
                mosaic_small.save(small_path, quality=90)   # průběžně – jde navázat
    mosaic_small = Image.open(small_path).convert("RGB")
    osc = resample(mosaic_small, bbox_o, mosaic_res, cx, cy, x0, y1, ortho_res, OW, OH,
                   Image.BICUBIC)
    osc.save(os.path.join(GEO, "ortho_union_scene.jpg"), quality=92)
    print("ortho scene", osc.size, f"{ortho_res:.4f} m/px")

    meta = {
        "grid_x0": x0, "grid_y0": y0, "grid_x1": x1, "grid_y1": y1,
        "dem_res": DEM_RES, "dem_w": W, "dem_h": H,
        "ortho_w": OW, "ortho_h": OH, "ortho_res": ortho_res,
        "affine_scene_to_5514": {"X": cx.tolist(), "Y": cy.tolist(), "max_residual_m": resid},
        "bbox_5514": bbox, "sources": {"dtm": DMR, "dsm": DMP, "ortho": ORTO},
        "license": "© ČÚZK, CC BY 4.0",
        "union": {
            "old_block": {"w": int(meta_old["height"]["w"]), "h": int(meta_old["height"]["h"]),
                          "x0": float(meta_old["height"]["x0"]), "z0": float(meta_old["height"]["z0"]),
                          "col_off": g["col_off"], "row_off": g["row_off"]},
            "target_extent": "katastry 5 okolních obcí (data/obce.json) + katastr Dukelčic",
        },
    }
    json.dump(meta, open(os.path.join(PDATA, "geodata_meta_union.json"), "w"), indent=2)
    print(json.dumps(meta, indent=1))


if __name__ == "__main__":
    sys.exit(main())
