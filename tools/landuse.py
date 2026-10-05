"""Využití ploch (pole, louky, sady, zahrádky) z OpenStreetMap → data/landuse.bin.

Zdroj: OpenStreetMap (ODbL) z regionálního extraktu geodata/pbf/zlinsky-latest.osm.pbf – plochy
landuse=farmland | meadow | grass | orchard | vineyard | allotments, natural=grassland
(ways i multipolygony; u multipolygonů se díry odečítají).

Výstup je rastr 4 m/px zarovnaný s výškovou mřížkou hry (levý horní roh = x0, z0 z map.json),
řádek = z, sloupec = x. Ve hře ho čte `scripts/priroda/fields.gd` a kreslí jím pole podle kalendáře.

Formát data/landuse.bin (little endian):
  4 B   magic "LUSE"
  int32 verze (1)
  f32   x0, z0 (souřadnice hrany buňky 0,0), f32 cell (m)
  int32 nx, nz
  nx·nz × 2 B: [třída, id pole mod 256]
Třídy: 0 nic, 1 orná půda (farmland), 2 louka / pastvina, 3 sad / vinice, 4 zahrádky (allotments).
Id pole = pořadí polygonu farmland (1..255, cyklicky) – každé pole má vlastní plodinu.

  python3 tools/landuse.py
"""
import json
import math
import os
import struct
import sys

import numpy as np
import osmium
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
GAME = os.path.dirname(HERE)
PIPE = os.path.join(GAME, "pipeline")
PDATA = os.path.join(PIPE, "data")
GEO = os.path.join(GAME, "geodata")
PSCRIPTS = os.path.join(PIPE, "scripts")
sys.path.insert(0, PSCRIPTS)
from phase2_osm_to_local import make_transform  # noqa: E402

PBF = os.path.join(GEO, "pbf", "zlinsky-latest.osm.pbf")
DATA = os.path.join(GAME, "data")
CELL = 4.0

# (tag, hodnota) → třída
CLASSES = {
    ("landuse", "farmland"): 1,
    ("landuse", "meadow"): 2, ("landuse", "grass"): 2, ("natural", "grassland"): 2,
    ("landuse", "orchard"): 3, ("landuse", "vineyard"): 3,
    ("landuse", "allotments"): 4,
}
NAMES = {1: "orná půda", 2: "louka / pastvina", 3: "sad / vinice", 4: "zahrádky"}
# pořadí kreslení – pozdější přepisuje dřívější (menší plochy nahoře)
DRAW_ORDER = [2, 1, 4, 3]


class Collector(osmium.SimpleHandler):
    def __init__(self, bbox):
        super().__init__()
        self.bbox = bbox
        self.areas = []     # {cls, rings: [outer, [holes…]]}

    def area(self, a):
        cls = 0
        for (k, v), c in CLASSES.items():
            if a.tags.get(k) == v:
                cls = c
                break
        if not cls:
            return
        try:
            for outer in a.outer_rings():
                pts = [(n.lat, n.lon) for n in outer]
                b = self.bbox
                if not any(b[0] <= lo <= b[2] and b[1] <= la <= b[3] for la, lo in pts):
                    continue
                holes = [[(n.lat, n.lon) for n in inner] for inner in a.inner_rings(outer)]
                self.areas.append({"cls": cls, "outer": pts, "holes": holes})
        except osmium.InvalidLocationError:
            return


def main():
    meta = json.load(open(os.path.join(DATA, "map.json")))
    ref = json.load(open(os.path.join(PDATA, "scene_reference.json")))
    raw_name = "osm_raw_union.json" if os.path.exists(os.path.join(PDATA, "osm_raw_union.json")) \
        else "osm_raw_full.json"
    b0 = json.load(open(os.path.join(PDATA, raw_name)))["bbox_latlon_margin"]
    print(f"OSM bbox: {raw_name}")
    m = 0.03      # rezerva ve stupních – bbox z osm_raw je užší než výšková mřížka; pořadí (lon0, lat0, lon1, lat1)
    bbox = [b0[0] - m, b0[1] - m, b0[2] + m, b0[3] + m]
    tf = make_transform(ref)
    hm = meta["height"]
    x0, z0 = float(hm["x0"]), float(hm["z0"])
    nx = int(math.ceil((hm["w"] - 1) * hm["spacing"] / CELL))
    nz = int(math.ceil((hm["h"] - 1) * hm["spacing"] / CELL))

    col = Collector(bbox)
    col.apply_file(PBF, locations=True, idx="sparse_mem_array")
    print(f"OSM: {len(col.areas)} ploch")

    def to_px(pts):
        out = []
        for la, lo in pts:
            sx, sy = tf(la, lo)
            out.append(((sx - x0) / CELL - 0.5, (-sy - z0) / CELL - 0.5))   # scéna y → Godot z = −y
        return out

    cls_img = np.zeros((nz, nx), np.uint8)
    id_img = np.zeros((nz, nx), np.uint8)
    next_id = 0
    n_fields = 0
    polys = []
    for a in col.areas:
        outer = to_px(a["outer"])
        if len(outer) < 3:
            continue
        polys.append((a["cls"], outer, [to_px(h) for h in a["holes"]]))
    polys.sort(key=lambda p: DRAW_ORDER.index(p[0]))
    for cls, outer, holes in polys:
        xs = [p[0] for p in outer]
        zs = [p[1] for p in outer]
        ix0, ix1 = max(int(min(xs)) - 1, 0), min(int(max(xs)) + 2, nx)
        iz0, iz1 = max(int(min(zs)) - 1, 0), min(int(max(zs)) + 2, nz)
        if ix1 <= ix0 or iz1 <= iz0:
            continue
        w, h = ix1 - ix0, iz1 - iz0
        m = Image.new("L", (w, h), 0)
        d = ImageDraw.Draw(m)
        d.polygon([(x - ix0, z - iz0) for x, z in outer], fill=1)
        for hole in holes:
            if len(hole) >= 3:
                d.polygon([(x - ix0, z - iz0) for x, z in hole], fill=0)
        mask = np.array(m, bool)
        cls_img[iz0:iz1, ix0:ix1][mask] = cls
        if cls == 1:
            next_id = next_id % 255 + 1
            id_img[iz0:iz1, ix0:ix1][mask] = next_id
            n_fields += 1
        else:
            id_img[iz0:iz1, ix0:ix1][mask] = 0

    # obvod katastru
    bpoly = [(p[0], p[1]) for p in meta["boundary"]]
    bm = Image.new("L", (nx, nz), 0)
    ImageDraw.Draw(bm).polygon([((x - x0) / CELL - 0.5, (z - z0) / CELL - 0.5) for x, z in bpoly], fill=1)
    inside = np.array(bm, bool)
    cad_ha = inside.sum() * CELL * CELL / 10000.0

    data = np.stack([cls_img, id_img], axis=-1).astype(np.uint8)
    with open(os.path.join(DATA, "landuse.bin"), "wb") as f:
        f.write(b"LUSE")
        f.write(struct.pack("<i3f2i", 1, x0, z0, CELL, nx, nz))
        f.write(data.tobytes())

    print(f"Rastr {nx}×{nz} po {CELL} m, {n_fields} polí (farmland), katastr {cad_ha:.0f} ha")
    for c in (1, 2, 3, 4):
        ha_all = (cls_img == c).sum() * CELL * CELL / 10000.0
        ha_cad = ((cls_img == c) & inside).sum() * CELL * CELL / 10000.0
        print(f"  třída {c} {NAMES[c]:18s} celkem {ha_all:8.1f} ha, v katastru {ha_cad:8.1f} ha "
              f"({100.0 * ha_cad / cad_ha:.1f} % katastru)")
    print(f"→ {os.path.join(DATA, 'landuse.bin')} ({os.path.getsize(os.path.join(DATA, 'landuse.bin')) // 1024} kB)")
    if (((cls_img == 1) & inside).sum() * CELL * CELL / 10000.0) < 0.1 * cad_ha:
        print("POZOR: OSM farmland pokrývá < 10 % katastru – pole v datech chybí (nedoplňováno z ortofota).")


if __name__ == "__main__":
    main()
