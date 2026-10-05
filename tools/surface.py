"""Maska povrchu terénu (bez satelitního snímku) → data/surface.bin.

Ve hře podle ní `shaders/terrain.gdshader` vybírá procedurální materiál (tráva, ornice, les, dvůr…).
Rastr 4 m/px zarovnaný s výškovou mřížkou hry (levý horní roh = x0, z0 z map.json), řádek = z, sloupec = x
(stejně jako data/landuse.bin).

Formát data/surface.bin (little endian):
  4 B   magic "SURF"
  int32 verze (1)
  f32   x0, z0 (souřadnice hrany buňky 0,0), f32 cell (m)
  int32 nx, nz
  nx·nz × 1 B: třída
Třídy: 0 tráva / louka (výchozí), 1 orná půda, 2 sad / zahrada, 3 les (podrost), 4 zástavba / dvůr,
       5 břeh / mokřad, 6 skála / strmý svah (v datech se nevyskytuje – dopočítá shader ze sklonu),
       7 polní cesta (OSM track / path).

Zdroje (vše lokální, nic se nestahuje):
  data/landuse.bin  – 1 orná půda, 2 louka (→ 0), 3 sad a 4 zahrádky (→ 2)
  OSM (geodata/pbf) – landuse=forest / natural=wood (→ 3), landuse=residential (→ 4 jen mimo pole a louky),
                      highway=track | path | bridleway (→ 7, šířka TRACK_W)
  data/trees.bin    – hustota stromů (→ 3, práh FOREST_MIN stromů na 32×32 m; tam, kde OSM les chybí)
  data/roofs.bin    – okolí budov do BUILDING_R m (→ 4)
  data/water.json   – ± WATER_R m od osy potoků a kolem rybníků (→ 5)

Pořadí (pozdější přepisuje dřívější): základ 0 → landuse.bin → les → zástavba → dvůr u budov → břeh → cesta.
Práh lesa, poloměry a šířky jsou laditelné konstanty níže.

  python3 tools/surface.py
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

FOREST_MIN = 3.0     # stromů na 32×32 m (průměr v okně), od kdy je buňka les   # DOPLNIT: výchozí odhad, doladit podle výpisu tříd
BUILDING_R = 8.0     # dvůr okolo budov (m)
WATER_R = 3.0        # břeh od osy potoka (m) a kolem rybníků
TRACK_W = 3.0        # šířka polní cesty (m)

NAMES = {0: "tráva / louka", 1: "orná půda", 2: "sad / zahrada", 3: "les", 4: "zástavba / dvůr",
         5: "břeh / mokřad", 6: "skála (shader)", 7: "polní cesta"}


class Collector(osmium.SimpleHandler):
    def __init__(self, bbox):
        super().__init__()
        self.bbox = bbox
        self.areas = []     # {cls, outer, holes}
        self.lines = []     # [(lat, lon)…]

    def area(self, a):
        t = a.tags
        cls = 0
        if t.get("landuse") == "forest" or t.get("natural") == "wood":
            cls = 3
        elif t.get("landuse") == "residential":
            cls = 4
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

    def way(self, w):
        if w.tags.get("highway") in ("track", "path", "bridleway"):
            try:
                self.lines.append([(n.lat, n.lon) for n in w.nodes])
            except osmium.InvalidLocationError:
                pass


def box_sum(a, r):
    """Součet v okně (2r+1)² (okraje = 0), přes kumulativní součty."""
    k = 2 * r + 1
    p = np.pad(a.astype(np.float64), r)
    c = p.cumsum(0).cumsum(1)
    c = np.pad(c, ((1, 0), (1, 0)))
    return c[k:, k:] - c[:-k, k:] - c[k:, :-k] + c[:-k, :-k]


def dilate(mask, r):
    out = mask.copy()
    for dz in range(-r, r + 1):
        for dx in range(-r, r + 1):
            if dx * dx + dz * dz > r * r + 1:
                continue
            sh = np.zeros_like(mask)
            zs = slice(max(dz, 0), mask.shape[0] + min(dz, 0))
            zd = slice(max(-dz, 0), mask.shape[0] + min(-dz, 0))
            xs = slice(max(dx, 0), mask.shape[1] + min(dx, 0))
            xd = slice(max(-dx, 0), mask.shape[1] + min(-dx, 0))
            sh[zd, xd] = mask[zs, xs]
            out |= sh
    return out


def main():
    meta = json.load(open(os.path.join(DATA, "map.json")))
    ref = json.load(open(os.path.join(PDATA, "scene_reference.json")))
    raw_name = "osm_raw_union.json" if os.path.exists(os.path.join(PDATA, "osm_raw_union.json")) \
        else "osm_raw_full.json"
    b0 = json.load(open(os.path.join(PDATA, raw_name)))["bbox_latlon_margin"]
    print(f"OSM bbox: {raw_name}")
    m = 0.03
    bbox = [b0[0] - m, b0[1] - m, b0[2] + m, b0[3] + m]
    tf = make_transform(ref)
    hm = meta["height"]
    x0, z0 = float(hm["x0"]), float(hm["z0"])
    nx = int(math.ceil((hm["w"] - 1) * hm["spacing"] / CELL))
    nz = int(math.ceil((hm["h"] - 1) * hm["spacing"] / CELL))

    def px(x, z):
        return (x - x0) / CELL - 0.5, (z - z0) / CELL - 0.5

    def ll_to_px(pts):
        out = []
        for la, lo in pts:
            sx, sy = tf(la, lo)
            out.append(px(sx, -sy))          # scéna y → Godot z = −y
        return out

    def polygon_mask(outer, holes):
        m_ = Image.new("L", (nx, nz), 0)
        d = ImageDraw.Draw(m_)
        d.polygon(outer, fill=1)
        for h in holes:
            if len(h) >= 3:
                d.polygon(h, fill=0)
        return np.array(m_, bool)

    col = Collector(bbox)
    col.apply_file(PBF, locations=True, idx="sparse_mem_array")
    print(f"OSM: {len(col.areas)} ploch, {len(col.lines)} cest")

    # --- základ + landuse.bin
    cls = np.zeros((nz, nx), np.uint8)
    lb = open(os.path.join(DATA, "landuse.bin"), "rb").read()
    if lb[:4] == b"LUSE":
        lx0, lz0, lcell = struct.unpack_from("<3f", lb, 8)
        lnx, lnz = struct.unpack_from("<2i", lb, 20)
        if abs(lx0 - x0) < 0.01 and abs(lz0 - z0) < 0.01 and lnx == nx and lnz == nz:
            lu = np.frombuffer(lb, np.uint8, lnx * lnz * 2, 28).reshape(nz, nx, 2)[..., 0]
            cls[lu == 1] = 1
            cls[(lu == 3) | (lu == 4)] = 2
        else:
            print("POZOR: landuse.bin má jiný rastr – přegeneruj ho (tools/landuse.py)")
    landuse_free = cls == 0

    # --- les: OSM + hustota stromů
    forest = np.zeros((nz, nx), bool)
    tb = open(os.path.join(DATA, "trees.bin"), "rb").read()
    n = struct.unpack_from("<i", tb, 4)[0]
    d = np.frombuffer(tb, np.float32, n * 11, 8).reshape(n, 11)
    tcnt = np.zeros((nz, nx), np.float32)
    ix = np.floor((d[:, 0] - x0) / CELL).astype(int)
    iz = np.floor((d[:, 2] - z0) / CELL).astype(int)
    ok = (ix >= 0) & (iz >= 0) & (ix < nx) & (iz < nz)
    np.add.at(tcnt, (iz[ok], ix[ok]), 1.0)
    dens = box_sum(tcnt, 4) / 81.0 * 64.0      # okno 9×9 buněk = 36×36 m → přepočet na 32×32 m
    forest |= dens >= FOREST_MIN
    res = np.zeros((nz, nx), bool)
    for a in col.areas:
        outer = ll_to_px(a["outer"])
        if len(outer) < 3:
            continue
        mk = polygon_mask(outer, [ll_to_px(h) for h in a["holes"]])
        if a["cls"] == 3:
            forest |= mk
        else:
            res |= mk
    cls[forest] = 3

    # --- zástavba: residential jen mimo pole / louky / sady, dvůr u budov vždy
    cls[res & landuse_free & ~forest] = 4
    rb = open(os.path.join(DATA, "roofs.bin"), "rb").read()
    nch = struct.unpack_from("<i", rb, 4)[0]
    off = 8
    bld = np.zeros((nz, nx), bool)
    for _c in range(nch):
        nv = struct.unpack_from("<i", rb, off)[0]
        off += 4
        pos = np.frombuffer(rb, np.float32, nv * 3, off).reshape(nv, 3)
        off += nv * 36
        bx = np.floor((pos[:, 0] - x0) / CELL).astype(int)
        bz = np.floor((pos[:, 2] - z0) / CELL).astype(int)
        k = (bx >= 0) & (bz >= 0) & (bx < nx) & (bz < nz)
        bld[bz[k], bx[k]] = True
    yard = dilate(bld, int(round(BUILDING_R / CELL)) + 1)
    cls[yard] = 4

    # --- voda: břeh
    wj = json.load(open(os.path.join(DATA, "water.json")))
    bank = Image.new("L", (nx, nz), 0)
    bd = ImageDraw.Draw(bank)
    for s in wj["streams"]:
        half = float(wj["kinds"].get(s["kind"], {}).get("half_w", 1.5)) + WATER_R
        pts = [px(p[0], p[1]) for p in s["pts"]]
        bd.line(pts, fill=1, width=max(1, int(round(2 * half / CELL))))
    for pd_ in wj["ponds"]:
        poly = [px(q[0], q[1]) for q in pd_["poly"]]
        if len(poly) >= 3:
            bd.polygon(poly, fill=1)
    bank_m = np.array(bank, bool)
    pond_edge = dilate(bank_m, int(round(WATER_R / CELL)))
    cls[pond_edge] = 5

    # --- polní cesty
    tr = Image.new("L", (nx, nz), 0)
    td = ImageDraw.Draw(tr)
    for ln in col.lines:
        pts = ll_to_px(ln)
        if len(pts) >= 2:
            td.line(pts, fill=1, width=max(1, int(round(TRACK_W / CELL))))
    cls[(np.array(tr, bool)) & (cls != 5)] = 7

    with open(os.path.join(DATA, "surface.bin"), "wb") as f:
        f.write(b"SURF")
        f.write(struct.pack("<i3f2i", 1, x0, z0, CELL, nx, nz))
        f.write(cls.tobytes())

    bpoly = [(p[0], p[1]) for p in meta["boundary"]]
    bm = Image.new("L", (nx, nz), 0)
    ImageDraw.Draw(bm).polygon([px(x, z) for x, z in bpoly], fill=1)
    inside = np.array(bm, bool)
    tot = max(int(inside.sum()), 1)
    print(f"Rastr {nx}×{nz} po {CELL} m, katastr {tot * CELL * CELL / 10000.0:.0f} ha")
    for c in range(8):
        cnt = int(((cls == c) & inside).sum())
        print(f"  třída {c} {NAMES[c]:18s} {cnt * CELL * CELL / 10000.0:8.1f} ha  ({100.0 * cnt / tot:5.1f} % katastru)")
    out = os.path.join(DATA, "surface.bin")
    print(f"→ {out} ({os.path.getsize(out) // 1024} kB)")


if __name__ == "__main__":
    main()
