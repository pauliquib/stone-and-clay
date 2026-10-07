"""Fáze 12 – analýza geodat pro CELÝ katastr (rozšíření za stávající jádro r<=480 m).

Znovu používá čisté matematické funkce z pipeline/scripts/phase6_analyze.py (fit_roof,
roof_from_fit, mar/hull, pip, dist_to_edges, FACADE_TINTS) nad novou, větší
mřížkou (geodata/{dtm,dsm}_full_scene.npy, ortho_full_scene.jpg,
pipeline/data/geodata_meta_full.json). Jádro (r<=R_CORE) už je hotové z fáze 6-7 a
znovu se negeneruje - buildings/trees z něj se tu jen vynechávají.

Výstupy:
  pipeline/data/buildings_3d_full.json  – budovy mimo jádro (stejné schéma jako
                                  pipeline/data/buildings_3d.json z fáze 6)
  pipeline/data/forest_mask_full.npz    – rasterová maska lesa/remízků (pro fázi 13,
                                  scatter stromů) + maska zástavby (zahrady)
"""
import json
import math
import os

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage

from phase6_analyze import fit_roof, roof_from_fit, mar, hull, pip, dist_to_edges, open_ring, FACADE_TINTS

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)          # pipeline/ – data/, assets/, renders/, logs/
GAME = os.path.dirname(ROOT)          # kořen repozitáře hry – geodata/, blend/
GEO = os.path.join(GAME, "geodata")
R_CORE = 480.0  # jádro už hotové (fáze 6-7) - budovy/stromy uvnitř se přeskočí
ADMIN_BUFFER = 150.0  # m, přesah za hranici katastru pro budovy na okraji

meta = json.load(open(os.path.join(ROOT, "data", "geodata_meta_full.json")))
X0, Y1 = meta["grid_x0"], meta["grid_y1"]
DEM_RES, W, H = meta["dem_res"], meta["dem_w"], meta["dem_h"]
ORTHO_RES, OW, OH = meta["ortho_res"], meta["ortho_w"], meta["ortho_h"]


def rc(x, y, res, h_rows):
    return (Y1 - np.asarray(y)) / res - 0.5, (np.asarray(x) - X0) / res - 0.5


def sample(arr, x, y, order=1, res=DEM_RES):
    r, c = rc(x, y, res, arr.shape[0])
    return ndimage.map_coordinates(arr, [np.atleast_1d(r), np.atleast_1d(c)], order=order, mode="nearest")


def main():
    ref = json.load(open(os.path.join(ROOT, "data", "scene_reference.json"), encoding="utf-8"))
    tref = json.load(open(os.path.join(ROOT, "data", "terrain_ref.json"), encoding="utf-8"))
    H_ref = tref["H_ref"]
    HX, HY = ref["house_scene_xy"]
    house_ids = {i.split("/")[-1] for i in ref.get("exclude_osm_ids", [])}
    admin = json.load(open(os.path.join(ROOT, "data", "doubravy_admin_boundary.json"), encoding="utf-8"))
    admin_poly = [tuple(p) for p in admin["scene_poly"]]

    dtm = np.load(os.path.join(GEO, "dtm_full_scene.npy")).astype(np.float64)
    dsm = np.load(os.path.join(GEO, "dsm_full_scene.npy")).astype(np.float64)
    ortho = np.asarray(Image.open(os.path.join(GEO, "ortho_full_scene.jpg")).convert("RGB"))
    terrain = dtm - H_ref
    nd = dsm - dtm
    print(f"grid {W}x{H} @ {DEM_RES} m, ortho {OW}x{OH} @ {ORTHO_RES:.3f} m/px, terrain z "
          f"{terrain.min():.1f}..{terrain.max():.1f}")

    gj = json.load(open(os.path.join(ROOT, "data", "okoli_full_local.geojson"), encoding="utf-8"))

    def in_admin(cx, cy):
        return bool(pip(np.array([cx]), np.array([cy]), admin_poly)[0]) or \
            dist_to_edges(np.array([cx]), np.array([cy]), admin_poly)[0] < ADMIN_BUFFER

    osm_b = [f for f in gj["features"] if f["properties"]["kind"] == "building"
             and f["geometry"]["type"] == "Polygon"]
    print("OSM buildings total (full katastr):", len(osm_b))

    buildings = []
    stat = {"dsm": 0, "fallback": 0, "skip_core": 0, "skip_outside": 0, "skip_house": 0}
    rng = np.random.default_rng(122)
    for f in osm_b:
        p = f["properties"]
        if str(p.get("osm_id")) in house_ids:
            stat["skip_house"] += 1
            continue
        poly = open_ring(f["geometry"]["coordinates"][0])
        if len(poly) < 3:
            continue
        xs = [q[0] for q in poly]
        ys = [q[1] for q in poly]
        cxm, cym = float(np.mean(xs)), float(np.mean(ys))
        if math.hypot(cxm - HX, cym - HY) <= R_CORE:
            stat["skip_core"] += 1
            continue
        if not in_admin(cxm, cym):
            stat["skip_outside"] += 1
            continue
        rect = mar(poly)
        bx, by = [], []
        for i in range(len(poly)):
            (x1, y1), (x2, y2) = poly[i], poly[(i + 1) % len(poly)]
            k = max(2, int(math.hypot(x2 - x1, y2 - y1)))
            bx += list(np.linspace(x1, x2, k, endpoint=False))
            by += list(np.linspace(y1, y2, k, endpoint=False))
        bx, by = np.array(bx), np.array(by)
        g = sample(terrain, bx, by, res=DEM_RES)
        base_z, ground_mean = float(g.min()), float(np.median(g))
        gxs, gys = np.meshgrid(np.arange(min(xs), max(xs), 0.5) + 0.25, np.arange(min(ys), max(ys), 0.5) + 0.25)
        gxs, gys = gxs.ravel(), gys.ravel()
        ins_ = pip(gxs, gys, poly)
        gxs, gys = gxs[ins_], gys[ins_]
        dd = dist_to_edges(gxs, gys, poly)
        core = dd >= 0.6
        if core.sum() < 8:
            core = dd >= 0.2
        px, py = gxs[core], gys[core]
        entry = {"osm_id": p["osm_id"], "source": "osm", "polygon": [list(q) for q in poly],
                 "building": p.get("building", "yes"), "base_z": round(base_z - 0.3, 3),
                 "ground_z": round(ground_mean, 3), "rect": [round(v, 4) for v in rect]}
        ndv = sample(nd, px, py, res=DEM_RES) if len(px) else np.array([0.0])
        if len(px) >= 6 and np.median(ndv) > 1.8:
            h = sample(dsm, px, py, res=DEM_RES) - H_ref
            fit = fit_roof(px, py, h, rect)
            if fit["ridge_p90"] - ground_mean > 30:
                fit["ridge_p90"] = fit["ridge_z"] = ground_mean + 30
            shape, eave, ridge = roof_from_fit(fit, rect, ground_mean, p.get("building", "yes"))
            entry.update(shape=shape, eave_z=round(eave, 3), ridge_z=round(ridge, 3),
                         fit_err=round(fit["fit_err"], 3), height_source="DMP1G")
            stat["dsm"] += 1
        else:
            lv = p.get("building:levels")
            try:
                lv = float(lv)
            except (TypeError, ValueError):
                lv = None
            small = p.get("building") in {"garage", "garages", "shed", "carport"}
            wall = 2.6 if small else (lv * 2.9 if lv else 3.5)
            L, W_ = rect[2], rect[3]
            rise = 0.0 if small else (W_ / 2) * math.tan(math.radians(38))
            entry.update(shape="flat" if small else "gable_long", eave_z=round(ground_mean + wall, 3),
                         ridge_z=round(ground_mean + wall + rise, 3), height_source="OSM tags (není v DMP)")
            stat["fallback"] += 1
        if len(px):
            rr_, cc_ = rc(px, py, ORTHO_RES, OH)
            rr_ = np.clip(np.round(rr_).astype(int), 0, ortho.shape[0] - 1)
            cc_ = np.clip(np.round(cc_).astype(int), 0, ortho.shape[1] - 1)
            col = np.median(ortho[rr_, cc_], axis=0) / 255.0
        else:
            col = np.array([0.5, 0.3, 0.25])
        entry["roof_rgb"] = [round(float(v), 3) for v in col]
        entry["facade_rgb"] = list(FACADE_TINTS[int(rng.integers(len(FACADE_TINTS)))])
        buildings.append(entry)

    print(f"buildings kept: {len(buildings)} (DMP {stat['dsm']}, OSM-tag fallback {stat['fallback']}); "
          f"skipped: core={stat['skip_core']} outside_admin={stat['skip_outside']} house={stat['skip_house']}")

    out_path = os.path.join(ROOT, "data", "buildings_3d_full.json")
    json.dump(buildings, open(out_path, "w"))
    print("WROTE", out_path)

    # ---------------- masky pro vegetaci (fáze 13): les/remízky a zástavba (zahrady)
    forest_types = {"forest", "wood", "scrub"}
    resid_types = {"residential"}
    mask_forest = Image.new("L", (W, H), 0)
    mask_resid = Image.new("L", (W, H), 0)
    drw_f, drw_r = ImageDraw.Draw(mask_forest), ImageDraw.Draw(mask_resid)
    n_f = n_r = 0
    for ft in gj["features"]:
        if ft["properties"]["kind"] != "landuse":
            continue
        t = ft["properties"].get("landuse") or ft["properties"].get("natural") or ft["properties"].get("leisure")
        ring = ft["geometry"]["coordinates"][0]
        px_poly = [((x - X0) / DEM_RES, (Y1 - y) / DEM_RES) for x, y in ring]
        if t in forest_types:
            drw_f.polygon(px_poly, fill=1)
            n_f += 1
        elif t in resid_types:
            drw_r.polygon(px_poly, fill=1)
            n_r += 1
    mf = np.array(mask_forest, bool)
    mr = np.array(mask_resid, bool)

    # vyloučit budovy (i s odstupem) a silnice ze scatteru stromů, ať nevyrůstají ze střech/silnic
    mask_block = Image.new("L", (W, H), 0)
    drw_bl = ImageDraw.Draw(mask_block)
    for b in buildings:
        drw_bl.polygon([((x - X0) / DEM_RES, (Y1 - y) / DEM_RES) for x, y in b["polygon"]], fill=1)
    for ft in gj["features"]:
        if ft["properties"]["kind"] != "highway":
            continue
        line = [((x - X0) / DEM_RES, (Y1 - y) / DEM_RES) for x, y in ft["geometry"]["coordinates"]]
        if len(line) >= 2:
            drw_bl.line(line, fill=1, width=max(2, int(round(7.0 / DEM_RES))))
    mblock = ndimage.binary_dilation(np.array(mask_block, bool), iterations=max(1, int(round(4.0 / DEM_RES))))
    mf &= ~mblock
    mr &= ~mblock

    # jádro (r<=R_CORE) už má vlastní vegetaci z fáze 5/7 - v maskách ho vynech
    rr, cc = np.mgrid[0:H, 0:W]
    gx = X0 + (cc + 0.5) * DEM_RES
    gy = Y1 - (rr + 0.5) * DEM_RES
    core_mask = np.hypot(gx - HX, gy - HY) <= R_CORE
    mf &= ~core_mask
    mr &= ~core_mask
    print(f"forest polygons {n_f} -> mask area {mf.sum()*DEM_RES*DEM_RES/10000:.1f} ha; "
          f"residential polygons {n_r} -> mask area {mr.sum()*DEM_RES*DEM_RES/10000:.1f} ha (mimo jádro)")
    np.savez_compressed(os.path.join(ROOT, "data", "forest_mask_full.npz"), forest=mf, residential=mr)


if __name__ == "__main__":
    main()
