"""Herní verze – dům hráče ve stejném zjednodušeném stylu jako ostatní budovy.

Detailní 3D model domu se do hry nepřebírá. Místo něj se dům postaví úplně
stejnou metodou jako zbytek zástavby (fáze 6): půdorys z OSM/RÚIAN
(way/279053823), výška okapu/hřebene a tvar střechy fitem na DMP 1G, barva
střechy z ortofota. Výstup má stejné schéma jako pipeline/data/buildings_3d.json.

Spuštění (systémový python – numpy/scipy/PIL):
  python3 tools/domov_hrace.py
Výstup: tools/out/domov_hrace.json
"""
import json
import math
import os
import sys

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
GAME = os.path.dirname(HERE)
PIPE = os.path.join(GAME, "pipeline")
PDATA = os.path.join(PIPE, "data")
GEO = os.path.join(GAME, "geodata")
PSCRIPTS = os.path.join(PIPE, "scripts")
sys.path.insert(0, PSCRIPTS)
import phase6_analyze as p6  # noqa: E402  (čisté funkce fit_roof, roof_from_fit, mar, pip, …)

Image.MAX_IMAGE_PIXELS = None
HOUSE_OSM_ID = 279053823


def main():
    gj = json.load(open(os.path.join(PDATA, "okoli_full_local.geojson")))
    feat = next(f for f in gj["features"] if f["properties"].get("osm_id") == HOUSE_OSM_ID)
    poly = p6.open_ring(feat["geometry"]["coordinates"][0])
    H_ref = json.load(open(os.path.join(PDATA, "terrain_ref.json")))["H_ref"]
    geo = GEO
    dtm = np.load(os.path.join(geo, "dtm_scene.npy")).astype(np.float64)   # původní DMR (bez snížení pod model)
    dsm = np.load(os.path.join(geo, "dsm_scene.npy")).astype(np.float64)
    ortho = np.asarray(Image.open(os.path.join(geo, "ortho_scene.jpg")).convert("RGB"))
    terrain = dtm - H_ref

    rect = p6.mar(poly)
    xs = [q[0] for q in poly]
    ys = [q[1] for q in poly]
    bx, by = [], []
    for i in range(len(poly)):
        (x1, y1), (x2, y2) = poly[i], poly[(i + 1) % len(poly)]
        k = max(2, int(math.hypot(x2 - x1, y2 - y1)))
        bx += list(np.linspace(x1, x2, k, endpoint=False))
        by += list(np.linspace(y1, y2, k, endpoint=False))
    g = p6.sample(terrain, np.array(bx), np.array(by))
    base_z, ground = float(g.min()), float(np.median(g))

    gxs, gys = np.meshgrid(np.arange(min(xs), max(xs), 0.5) + 0.25, np.arange(min(ys), max(ys), 0.5) + 0.25)
    gxs, gys = gxs.ravel(), gys.ravel()
    ins = p6.pip(gxs, gys, poly)
    gxs, gys = gxs[ins], gys[ins]
    core = p6.dist_to_edges(gxs, gys, poly) >= 0.6
    px, py = gxs[core], gys[core]
    h = p6.sample(dsm, px, py) - H_ref
    fit = p6.fit_roof(px, py, h, rect)
    shape, eave, ridge = p6.roof_from_fit(fit, rect, ground, "residential")

    rr, cc = p6.rc(px, py, p6.ORES)
    col = np.median(ortho[np.clip(np.round(rr).astype(int), 0, ortho.shape[0] - 1),
                          np.clip(np.round(cc).astype(int), 0, ortho.shape[1] - 1)], axis=0) / 255.0
    out = {"osm_id": HOUSE_OSM_ID, "source": "osm", "name": "domov hráče",
           "polygon": [list(q) for q in poly], "building": "residential",
           "base_z": round(base_z - 0.3, 3), "ground_z": round(ground, 3),
           "rect": [round(v, 4) for v in rect], "shape": shape,
           "eave_z": round(eave, 3), "ridge_z": round(ridge, 3), "fit_err": round(fit["fit_err"], 3),
           "height_source": "DMP1G", "roof_rgb": [round(float(v), 3) for v in col],
           "facade_rgb": [0.95, 0.93, 0.84]}
    os.makedirs(os.path.join(HERE, "out"), exist_ok=True)
    json.dump(out, open(os.path.join(HERE, "out", "domov_hrace.json"), "w"), indent=1)
    print(f"domov hráče: {shape}, ground {ground:.2f}, eave {eave - ground:.2f} m, ridge {ridge - ground:.2f} m "
          f"nad terénem, fit_err {fit['fit_err']:.2f}, roof rgb {out['roof_rgb']}")


if __name__ == "__main__":
    main()
