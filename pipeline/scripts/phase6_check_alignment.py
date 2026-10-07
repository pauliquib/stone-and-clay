"""Kontrola zarovnání geodat ČÚZK s OSM a modelem domu (čistý Python).

Vykreslí výřez 320×320 m kolem domu: ortofoto a nDSM (DMP − DMR) s obrysy
OSM budov (červeně), silnic (žlutě) a obrysu modelu domu/zpevněné plochy
(tyrkysově). Spočte posun (dx, dy), při kterém se maska OSM budov nejlépe
překrývá s maskou nDSM > 2,5 m – slouží jako kontrola georeference.
Výstup: pipeline/renders/check_ortho.jpg, pipeline/renders/check_ndsm.jpg, pipeline/data/alignment_check.json
"""
import json
import os

import numpy as np
from PIL import Image, ImageDraw

Image.MAX_IMAGE_PIXELS = None
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)          # pipeline/ – data/, assets/, renders/, logs/
GAME = os.path.dirname(ROOT)          # kořen repozitáře hry – geodata/, blend/
GEO = os.path.join(GAME, "geodata")
S = 160


def main():
    meta = json.load(open(os.path.join(ROOT, "data", "geodata_meta.json")))
    gj = json.load(open(os.path.join(ROOT, "data", "okoli_local.geojson")))
    ins = json.load(open(os.path.join(ROOT, "data", "scene_inspect.json")))
    x0, y1 = meta["grid_x0"], meta["grid_y1"]
    cx, cy = meta["center"]
    dtm = np.load(os.path.join(GEO, "dtm_scene.npy"))
    dsm = np.load(os.path.join(GEO, "dsm_scene.npy"))
    nd = dsm - dtm
    res = meta["ortho_res"]
    sc = 1000 / (2 * S)

    def P(x, y):
        return ((x - (cx - S)) * sc, ((cy + S) - y) * sc)

    def overlay(img):
        d = ImageDraw.Draw(img)
        for f in gj["features"]:
            k = f["properties"]["kind"]
            if k == "building":
                d.line([P(*p) for p in f["geometry"]["coordinates"][0]], fill=(255, 0, 0), width=2)
            elif k == "highway":
                d.line([P(*p) for p in f["geometry"]["coordinates"]], fill=(255, 255, 0), width=1)
        for o in ins["objects"]:
            if o["name"] in ("Stěny sklep", "zaklady", "okolo"):
                h = o["hull_xy"]
                d.line([P(*p) for p in h + [h[0]]], fill=(0, 255, 255), width=2)
        return img

    o = Image.open(os.path.join(GEO, "ortho_scene.jpg"))
    box = (int((cx - S - x0) / res), int((y1 - (cy + S)) / res), int((cx + S - x0) / res), int((y1 - (cy - S)) / res))
    os.makedirs(os.path.join(ROOT, "renders"), exist_ok=True)
    overlay(o.crop(box).resize((1000, 1000))).save(os.path.join(ROOT, "renders", "check_ortho.jpg"), quality=85)
    c0, r0 = int(cx - S - x0), int(y1 - (cy + S))
    sub = nd[r0:r0 + 2 * S, c0:c0 + 2 * S]
    img = Image.fromarray((np.clip(sub, 0, 12) / 12 * 255).astype(np.uint8)).resize((1000, 1000)).convert("RGB")
    overlay(img).save(os.path.join(ROOT, "renders", "check_ndsm.jpg"), quality=85)

    # posun maximalizující shodu OSM budov s nDSM (1 m rastr, celé území)
    n = nd.shape[0]
    mask_b = Image.new("L", (n, n), 0)
    d = ImageDraw.Draw(mask_b)
    for f in gj["features"]:
        if f["properties"]["kind"] == "building":
            d.polygon([(x - x0, y1 - y) for x, y in f["geometry"]["coordinates"][0]], fill=1)
    B = np.array(mask_b, dtype=bool)
    Hm = nd > 2.5
    best = None
    for dy in range(-6, 7):
        for dx in range(-6, 7):
            sh = np.roll(np.roll(B, dy, 0), dx, 1)
            iou = (sh & Hm).sum() / max((sh | Hm).sum(), 1)
            prec = (sh & Hm).sum() / max(sh.sum(), 1)
            if best is None or prec > best[0]:
                best = (prec, iou, dx, -dy)
    zero_prec = (B & Hm).sum() / max(B.sum(), 1)
    out = {"precision_at_zero_shift": round(float(zero_prec), 3),
           "best_shift_scene_m": [best[2], best[3]], "precision_at_best": round(float(best[0]), 3)}
    json.dump(out, open(os.path.join(ROOT, "data", "alignment_check.json"), "w"), indent=2)
    print(out)


if __name__ == "__main__":
    main()
