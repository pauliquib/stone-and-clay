"""Syntetický svět pro čistý klon (cloud, CI) → chybějící data/*.bin z commitnutých dat.

Hra potřebuje data/*.bin, která vyrábí tools/export_map.py v Blenderu ze soukromého .blend (nejsou v gitu).
Tento nástroj z toho, co v repu JE, postaví věrohodnou náhradu, aby šla hra spustit a vizuálně kontrolovat:
  data/map.json        – výšková mřížka (rozměr, krok 2 m, x0/z0), silnice podle `kind`, hranice katastru
  data/buildings.json  – 496 domů: půdorys, ground_y / eave_y / ridge_y, tvar střechy, hřeben, dveře
  data/water.json      – osy toků s hladinou po bodech a rybníky (hladina) → údolnice a výšková kostra terénu
Nic se nestahuje. Hodnoty jsou deterministické (pevné seedy).

Pravidla (kontroluje tools/vizual/validate_data.py):
  - terén pod každým domem leží přesně na `ground_y` (plošina + plynulý náběh okolo),
  - silnice a cesty jsou hladké (profil vyhlazený podél osy, vodorovný příčný řez, bez schodů na křižovatkách),
  - koryta potoků leží pod hladinou z water.json, rybníky mají dno pod hladinou,
  - stromy nestojí v domech, na cestách ani ve vodě.

NIKDY nepřepíše existující soubor bez `--force` – uživatel má na svém stroji pravá data.

Výstupy (formáty podle čteček ve hře – terrain.gd, map_loader.gd, surface_map.gd, fields.gd, surroundings.gd, tree_gen.gd):
  terrain_height.bin   f32 h×w (řádek = z), vizuální výšky s mikroreliéfem
  terrain_collision.bin  f32 h×w = výška / krok (HeightMapShape3D), bez mikroreliéfu
  terrain_normal.bin   u8 RGB h×w normály ((n·0,5+0,5)·255)
  terrain_chunks.bin   f32 ncz×ncx×2 (min, max) po dlaždicích chunk_cells
  walls.bin, roofs.bin, asphalt.bin, gravel.bin   DBM1 (dlaždice 256 m podle těžiště trojúhelníku)
  tree_protos.bin (DBT1), trees.bin (DBI1, n × 11 f32)
  landuse.bin (LUSE), surface.bin (SURF), surround_height.bin (SURH), surround_surface.bin (SURS)
  + pokud chybí a jdou spustit: site.bin (tools/site.py), tree_eco.bin (tools/tree_species.py),
    vegetation.bin (tools/vegetation.py --eco)

Závislosti: numpy, Pillow, scipy (pip install scipy).

  python3 tools/vizual/synth_world.py [--force] [--out=adresář] [--only=terrain,buildings,roads,trees,landuse,surround,extra]
"""
import json
import math
import os
import struct
import subprocess
import sys
import time

import numpy as np
from PIL import Image, ImageDraw

try:
    from scipy import ndimage
    from scipy.spatial import cKDTree
except ImportError:  # pragma: no cover
    raise SystemExit("synth_world: chybí scipy – pip install scipy")

HERE = os.path.dirname(os.path.abspath(__file__))
GAME = os.path.dirname(os.path.dirname(HERE))
DATA = os.path.join(GAME, "data")
OUT = DATA                  # kam se zapisuje (--out=adresář – zkušební běh vedle pravých dat)

CHUNK = 256.0               # dlaždice DBM1 (m)
COARSE = 16.0               # krok hrubé mřížky kostry terénu (m)
EXTENT = 4000.0             # o kolik hrubá mřížka přesahuje detailní terén (okolí, surround_height)
HILL_AMP = (18.0, 55.0)     # výška kopců mezi údolnicemi (m) – rozsah podle šumu
HILL_DIST = 320.0           # m – jak rychle terén od údolnice stoupá (1 − e^(−d/HILL_DIST))
MICRO_AMP = 0.07            # mikroreliéf jen ve vizuální výšce (m)
PAD_DILATE = 0.8            # plošina domu přesahuje půdorys (m)
PAD_BLEND = 6.0             # náběh terénu k plošině (m)
PAD_ATTRACT = 10.0          # do této vzdálenosti od domu se profil silnice přitahuje k jeho ground_y (m)
ROAD_SMOOTH = 14.0          # σ vyhlazení profilu silnice podél osy (m)
ROAD_SHOULDER = 4.0         # náběh terénu od okraje vozovky (m)
ROAD_MAX_GRADE = 0.12       # nejvyšší podélný sklon po vyhlazení
ROAD_ITERS = 3              # kola sladění profilů na křižovatkách
ROAD_W = {"secondary": 7.0, "tertiary": 6.5, "unclassified": 5.5, "residential": 5.5, "living_street": 5.0,
          "service": 3.5, "track": 3.0, "path": 1.5, "footway": 1.8, "cycleway": 2.0}
GRAVEL_KINDS = {"track", "path"}
STREAM = {  # stejné jako tools/water.py KINDS: rovné dno, zahloubení, hloubka vody, sklon břehu
    "river": {"flat": 3.0, "cut": 1.1, "water": 0.55, "bank": 0.55},
    "canal": {"flat": 1.6, "cut": 0.7, "water": 0.4, "bank": 0.7},
    "stream": {"flat": 1.0, "cut": 0.5, "water": 0.22, "bank": 0.8},
    "ditch": {"flat": 0.8, "cut": 0.35, "water": 0.1, "bank": 0.9},
    "drain": {"flat": 0.8, "cut": 0.35, "water": 0.1, "bank": 0.9},
}
POND_DEPTH = 1.2
FOREST_SPACING = 15.0        # m – rozestup stromů v lese (zápoj korun z dronu; skutečná data z DMP ~20 m, řídká)

# Fasády (sRGB) – omítky okolních vsí; střechy – pálené tašky, tmavý eternit / plech, hnědé šindele
FACADES = [(0.86, 0.82, 0.72), (0.90, 0.87, 0.80), (0.82, 0.76, 0.62), (0.88, 0.80, 0.64), (0.78, 0.74, 0.68),
           (0.92, 0.90, 0.86), (0.84, 0.72, 0.58), (0.80, 0.80, 0.76), (0.86, 0.78, 0.70), (0.74, 0.70, 0.60)]
ROOFS = [(0.58, 0.27, 0.18), (0.52, 0.24, 0.17), (0.63, 0.32, 0.21), (0.46, 0.22, 0.16), (0.36, 0.34, 0.33),
         (0.28, 0.27, 0.27), (0.42, 0.30, 0.24), (0.55, 0.30, 0.22)]
BARN_FACADES = [(0.66, 0.60, 0.52), (0.58, 0.52, 0.44), (0.72, 0.68, 0.60)]


def log(*a):
    print("synth_world:", *a, flush=True)


def srgb_to_lin(c):
    c = np.asarray(c, np.float64)
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def fbm(shape, cell, octaves, seed, gain=0.5):
    """Hladký šum (−1..1) o tvaru `shape`; `cell` = velikost buňky nejhrubší oktávy v pixelech."""
    rng = np.random.default_rng(seed)
    out = np.zeros(shape, np.float32)
    amp, tot = 1.0, 0.0
    for _ in range(octaves):
        gh = int(math.ceil(shape[0] / cell)) + 3
        gw = int(math.ceil(shape[1] / cell)) + 3
        g = rng.standard_normal((gh, gw)).astype(np.float32)
        z = ndimage.zoom(g, cell, order=3, mode="reflect", prefilter=False)
        out += amp * z[:shape[0], :shape[1]]
        tot += amp
        amp *= gain
        cell = max(cell / 2.0, 1.0)
    out /= tot
    return np.clip(out / (out.std() * 2.5 + 1e-6), -1.0, 1.0)


def resample(pts, step):
    """Polyline [[x, z, …]] → body po `step` m (lineárně, i další sloupce)."""
    P = np.asarray(pts, np.float64)
    if len(P) < 2:
        return P
    seg = np.hypot(*np.diff(P[:, :2], axis=0).T)
    s = np.concatenate([[0.0], np.cumsum(seg)])
    if s[-1] < 1e-6:
        return P[:1]
    n = max(2, int(math.ceil(s[-1] / step)) + 1)
    t = np.linspace(0.0, s[-1], n)
    return np.stack([np.interp(t, s, P[:, k]) for k in range(P.shape[1])], axis=1)


def point_in_poly(X, Z, poly):
    """Maska bodů uvnitř polygonu (paprsek, vektorově)."""
    poly = np.asarray(poly, np.float64)
    ins = np.zeros(np.shape(X), bool)
    j = len(poly) - 1
    for i in range(len(poly)):
        xi, zi = poly[i]
        xj, zj = poly[j]
        cond = ((zi > Z) != (zj > Z)) & (X < (xj - xi) * (Z - zi) / ((zj - zi) + 1e-12) + xi)
        ins ^= cond
        j = i
    return ins


class Grid:
    """Detailní mřížka 2 m (řádek r ↔ z = z0 + r·sp, sloupec c ↔ x = x0 + c·sp)."""

    def __init__(self, meta):
        hm = meta["height"]
        self.w, self.h = int(hm["w"]), int(hm["h"])
        self.sp = float(hm["spacing"])
        self.x0, self.z0 = float(hm["x0"]), float(hm["z0"])
        self.chunk_cells = int(hm["chunk_cells"])
        self.ncx, self.ncz = int(hm["ncx"]), int(hm["ncz"])

    def to_px(self, x, z):
        return (np.asarray(x) - self.x0) / self.sp, (np.asarray(z) - self.z0) / self.sp

    def sample(self, arr, x, z):
        """Bilineární vzorek mřížky v bodech (x, z)."""
        c, r = self.to_px(x, z)
        c = np.clip(c, 0, self.w - 1.001)
        r = np.clip(r, 0, self.h - 1.001)
        c0, r0 = np.floor(c).astype(int), np.floor(r).astype(int)
        tc, tr = c - c0, r - r0
        a = arr[r0, c0] * (1 - tc) + arr[r0, c0 + 1] * tc
        b = arr[r0 + 1, c0] * (1 - tc) + arr[r0 + 1, c0 + 1] * tc
        return a * (1 - tr) + b * tr

    def raster(self, scale=1.0):
        """Prázdný PIL obraz přes mřížku (pro kreslení polygonů); scale = px na buňku."""
        return Image.new("F", (int(self.w * scale), int(self.h * scale)), 0.0)

    def poly_px(self, poly, scale=1.0):
        return [((x - self.x0) / self.sp * scale, (z - self.z0) / self.sp * scale) for x, z in poly]


# ---------------------------------------------------------------------------------------------- terén

def stream_ground(s):
    """Body osy toku [x, z, terén před zahloubením] – terén = hladina − voda + zahloubení (inverze water.py)."""
    k = STREAM.get(s["kind"], STREAM["stream"])
    P = np.asarray(s["pts"], np.float64)
    return np.c_[P[:, 0], P[:, 1], P[:, 2] - k["water"] + k["cut"]]


def solve_skeleton(g, buildings, water):
    """Hrubá kostra terénu na mřížce COARSE přes detail + EXTENT: kopce mezi údolnicemi + reziduum
    (multigrid Laplace s pevnými body), aby kostra procházela potoky, rybníky a patami domů."""
    cx0, cz0 = g.x0 - EXTENT, g.z0 - EXTENT
    nx = int(math.ceil(((g.w - 1) * g.sp + 2 * EXTENT) / COARSE)) + 1
    nz = int(math.ceil(((g.h - 1) * g.sp + 2 * EXTENT) / COARSE)) + 1
    # pevné body
    pts = [stream_ground(s) for s in water["streams"]]
    for p in water["ponds"]:
        rim = resample([tuple(q) for q in p["poly"]] + [tuple(p["poly"][0])], 8.0)
        pts.append(np.c_[rim[:, :2], np.full(len(rim), p["level"] + 0.25)])
    bpts = []
    for b in buildings:
        poly = np.asarray(b["poly"], np.float64)
        bpts.append(np.c_[poly, np.full(len(poly), b["ground_y"])])
        bpts.append([[poly[:, 0].mean(), poly[:, 1].mean(), b["ground_y"]]])
    P = np.concatenate(pts + [np.asarray(q, np.float64) for q in bpts])
    ci = np.round((P[:, 0] - cx0) / COARSE).astype(int)
    cj = np.round((P[:, 1] - cz0) / COARSE).astype(int)
    ok = (ci >= 0) & (ci < nx) & (cj >= 0) & (cj < nz)
    ci, cj, P = ci[ok], cj[ok], P[ok]
    vsum = np.zeros((nz, nx))
    vcnt = np.zeros((nz, nx))
    np.add.at(vsum, (cj, ci), P[:, 2])
    np.add.at(vcnt, (cj, ci), 1.0)
    fixed = vcnt > 0
    val = np.where(fixed, vsum / np.maximum(vcnt, 1), 0.0)

    # kopce: amplituda ze šumu × vzdálenost od údolnice (pevných bodů toků)
    sm = np.zeros((nz, nx), bool)
    for s in water["streams"]:
        Q = np.asarray(s["pts"])
        a = np.round((Q[:, 0] - cx0) / COARSE).astype(int)
        b = np.round((Q[:, 1] - cz0) / COARSE).astype(int)
        k = (a >= 0) & (a < nx) & (b >= 0) & (b < nz)
        sm[b[k], a[k]] = True
    dist = ndimage.distance_transform_edt(~sm) * COARSE
    amp = HILL_AMP[0] + (HILL_AMP[1] - HILL_AMP[0]) * (0.5 + 0.5 * fbm((nz, nx), 90, 4, 11))
    ridge = 1.0 - np.abs(fbm((nz, nx), 40, 3, 12))           # hřbety (ridged šum) – členitější kopce
    hill = amp * (1.0 - np.exp(-dist / HILL_DIST)) * (0.55 + 0.45 * ridge)
    res = np.where(fixed, val - hill, 0.0)

    # multigrid: Laplace s Dirichletovými body, od hrubé úrovně k jemné
    def relax(v, fx, fv, iters):
        for _ in range(iters):
            p = np.pad(v, 1, mode="edge")
            v = 0.25 * (p[:-2, 1:-1] + p[2:, 1:-1] + p[1:-1, :-2] + p[1:-1, 2:])
            v[fx] = fv[fx]
        return v

    levels = []
    fx, fv = fixed, res
    while min(fx.shape) > 24:
        levels.append((fx, fv))
        h2, w2 = (fx.shape[0] + 1) // 2, (fx.shape[1] + 1) // 2
        s = np.zeros((h2 * 2, w2 * 2))
        c = np.zeros((h2 * 2, w2 * 2))
        s[:fx.shape[0], :fx.shape[1]] = np.where(fx, fv, 0.0)
        c[:fx.shape[0], :fx.shape[1]] = fx
        s = s.reshape(h2, 2, w2, 2).sum((1, 3))
        c = c.reshape(h2, 2, w2, 2).sum((1, 3))
        fx, fv = c > 0, np.where(c > 0, s / np.maximum(c, 1), 0.0)
    v = np.full(fx.shape, fv[fx].mean() if fx.any() else 0.0)
    v = relax(v, fx, fv, 400)
    for fx, fv in reversed(levels):
        up = np.repeat(np.repeat(v, 2, 0), 2, 1)[:fx.shape[0], :fx.shape[1]]
        v = relax(up, fx, fv, 160)
    # vyhlazení kuželů v pevných bodech (bez pevných bodů, pak znovu přitáhnout)
    v = ndimage.gaussian_filter(v, 1.0)
    v = relax(v, fixed, res, 40)
    skel = (hill + v).astype(np.float32)
    return skel, (cx0, cz0, nx, nz)


def coarse_to_grid(skel, cmeta, g):
    """Bikubické převzorkování kostry na detailní mřížku 2 m."""
    cx0, cz0, _, _ = cmeta
    c = (g.x0 + np.arange(g.w) * g.sp - cx0) / COARSE
    r = (g.z0 + np.arange(g.h) * g.sp - cz0) / COARSE
    out = np.empty((g.h, g.w), np.float32)
    coef = ndimage.spline_filter(skel.astype(np.float64), order=3)
    step = 256
    for r0 in range(0, g.h, step):
        rr = r[r0:r0 + step]
        R, C = np.meshgrid(rr, c, indexing="ij")
        out[r0:r0 + step] = ndimage.map_coordinates(coef, [R, C], order=3, prefilter=False)
    return out


def build_terrain(g, meta, buildings, water):
    t0 = time.time()
    skel, cmeta = solve_skeleton(g, buildings, water)
    log(f"kostra terénu {skel.shape[1]}×{skel.shape[0]} ({time.time() - t0:.1f} s)")
    H = coarse_to_grid(skel, cmeta, g)
    # jemné zvlnění (desítky metrů) mimo pevné body – vrstevnice nejsou „gumové“
    det = fbm((g.h, g.w), 24, 3, 21) * 1.6
    H += det

    # --- korekce u domů: reziduum (ground_y − H) v rozích půdorysu, normalizovaná konvoluce σ ≈ 14 m
    rs = np.zeros((g.h, g.w), np.float32)
    rw = np.zeros((g.h, g.w), np.float32)
    for b in buildings:
        P = resample([tuple(q) for q in b["poly"]] + [tuple(b["poly"][0])], 2.0)
        c, r = g.to_px(P[:, 0], P[:, 1])
        c, r = np.round(c).astype(int), np.round(r).astype(int)
        hv = g.sample(H, P[:, 0], P[:, 1])
        np.add.at(rs, (r, c), b["ground_y"] - hv)
        np.add.at(rw, (r, c), 1.0)
    sig = 7.0
    bs = ndimage.gaussian_filter(rs, sig)
    bw = ndimage.gaussian_filter(rw, sig)
    H += np.where(bw > 1e-6, bs / np.maximum(bw, 1e-6), 0.0) * smoothstep(0.0, 0.02, bw)
    del rs, rw, bs, bw

    H_pre = H.copy()                     # profil silnic z terénu před zahloubením koryt (propustky)
    # --- koryta toků (dno = hladina − voda, rovné dno `flat`, svah `bank`) a rybníky
    sm = np.zeros((g.h, g.w), bool)
    sbed = np.zeros((g.h, g.w), np.float32)
    sflat = np.zeros((g.h, g.w), np.float32)
    sbank = np.zeros((g.h, g.w), np.float32)
    for s in water["streams"]:
        k = STREAM.get(s["kind"], STREAM["stream"])
        P = resample(s["pts"], 1.0)
        c, r = g.to_px(P[:, 0], P[:, 1])
        c, r = np.round(c).astype(int), np.round(r).astype(int)
        ok = (c >= 0) & (c < g.w) & (r >= 0) & (r < g.h)
        c, r, P = c[ok], r[ok], P[ok]
        sm[r, c] = True
        sbed[r, c] = P[:, 2] - k["water"]
        sflat[r, c] = k["flat"]
        sbank[r, c] = k["bank"]
    d, (ir, ic) = ndimage.distance_transform_edt(~sm, return_indices=True)
    d = d.astype(np.float32) * g.sp
    target = sbed[ir, ic] + np.maximum(d - sflat[ir, ic] * 0.5, 0.0) * sbank[ir, ic]
    near = d < 14.0
    H = np.where(near, np.minimum(H, target), H)
    stream_dist = d
    stream_hw = np.where(near, sflat[ir, ic] * 0.5 + 0.8, 0.0).astype(np.float32)
    del ir, ic, target, sbed, sflat, sbank, sm
    pond = np.zeros((g.h, g.w), bool)
    for p in water["ponds"]:
        poly = np.asarray(p["poly"])
        lo = np.maximum(np.floor((poly.min(0) - [g.x0, g.z0]) / g.sp).astype(int) - 2, 0)
        hi = np.minimum(np.ceil((poly.max(0) - [g.x0, g.z0]) / g.sp).astype(int) + 2, [g.w - 1, g.h - 1])
        xs = g.x0 + np.arange(lo[0], hi[0] + 1) * g.sp
        zs = g.z0 + np.arange(lo[1], hi[1] + 1) * g.sp
        X, Z = np.meshgrid(xs, zs)
        ins = point_in_poly(X, Z, poly)
        dd = ndimage.distance_transform_edt(ins) * g.sp
        sl = (slice(lo[1], hi[1] + 1), slice(lo[0], hi[0] + 1))
        tgt = p["level"] - 0.15 - POND_DEPTH * np.clip(dd / 6.0, 0, 1)
        # břeh: kolem rybníka nejvýš +0,4 m nad hladinou do 6 m (žádná voda nad terénem ani zídka)
        out_d = ndimage.distance_transform_edt(~ins) * g.sp
        rim = p["level"] + 0.12 + out_d * 0.15
        cur = H[sl]
        H[sl] = np.where(ins, np.minimum(cur, tgt), np.where(out_d < 10.0, np.minimum(cur, np.maximum(rim, cur - 3.0)), cur))
        pond[sl] |= ins
    log(f"koryta a rybníky ({time.time() - t0:.1f} s)")

    # --- rastr domů (id, vzdálenost, ground_y nejbližšího) – pro profily silnic i plošiny
    img = Image.new("F", (g.w, g.h), 0.0)
    idimg = Image.new("I", (g.w, g.h), 0)
    dr = ImageDraw.Draw(img)
    di = ImageDraw.Draw(idimg)
    for i, b in enumerate(buildings):
        poly = g.poly_px(b["poly"])
        dr.polygon(poly, fill=1.0)
        di.polygon(poly, fill=i + 1)
    pad = np.asarray(img) > 0.5
    pid = np.asarray(idimg, np.int32)
    pad = ndimage.binary_dilation(pad, iterations=1) | pad            # +2 m buňka (půdorys po rastrování)
    gy = np.array([0.0] + [b["ground_y"] for b in buildings], np.float32)
    bd, (ir, ic) = ndimage.distance_transform_edt(pid == 0, return_indices=True)
    bd = bd.astype(np.float32) * g.sp
    gnear = gy[pid[ir, ic]]
    del ir, ic
    # přesně ground_y: buňky půdorysu a lem jedné buňky (bilineární vzorek u zdi), lem ne pod vozovkou
    # profil silnice se vzorkuje z terénu přitaženého k patám domů do PAD_ATTRACT m (domy u ulice pak
    # stojí na úrovni vozovky – hrubá kostra 16 m to sama nezaručí a u zdi by vznikl schod)
    wb = (1.0 - smoothstep(0.0, PAD_ATTRACT, bd)).astype(np.float32)
    Hb = H_pre * (1.0 - wb) + gnear * wb
    del wb
    # --- silnice: profil podél osy z terénu, vyhlazený a omezený sklonem; plochý příčný řez.
    # Profily křížících se silnic se sladí iterací: každé kolo vzorkuje profily z terénu po minulém kole
    # (na křižovatce je tam už vozovka té druhé silnice), takže se výšky na styku sbíhají.
    order = sorted(meta["roads"], key=lambda r: ROAD_W.get(r["kind"], 4.0))   # širší silnice kreslit poslední (vyhraje)
    lines = []
    for rd in order:
        P = resample(rd["pts"], 1.0)
        if len(P) >= 2:
            lines.append((rd, P, ROAD_W.get(rd["kind"], 4.0) * 0.5))
    Hsrc = Hb
    for it in range(ROAD_ITERS):
        rm = np.zeros((g.h, g.w), bool)
        rprof = np.zeros((g.h, g.w), np.float32)
        rhw = np.zeros((g.h, g.w), np.float32)
        road_lines = []
        for rd, P, hw in lines:
            prof = g.sample(Hsrc, P[:, 0], P[:, 1]).astype(np.float64)
            n = len(P)
            sig = ROAD_SMOOTH if n > 8 else 2.0
            prof = ndimage.gaussian_filter1d(prof, sig, mode="nearest")
            # omez sklon (dopředně i zpětně, pak průměr – symetrické)
            f = prof.copy()
            bk = prof.copy()
            for i in range(1, n):
                f[i] = min(max(f[i], f[i - 1] - ROAD_MAX_GRADE), f[i - 1] + ROAD_MAX_GRADE)
            for i in range(n - 2, -1, -1):
                bk[i] = min(max(bk[i], bk[i + 1] - ROAD_MAX_GRADE), bk[i + 1] + ROAD_MAX_GRADE)
            prof = 0.5 * (f + bk)
            road_lines.append((rd, P, prof, hw))
            c, r = g.to_px(P[:, 0], P[:, 1])
            c, r = np.round(c).astype(int), np.round(r).astype(int)
            ok = (c >= 0) & (c < g.w) & (r >= 0) & (r < g.h)
            rm[r[ok], c[ok]] = True
            rprof[r[ok], c[ok]] = prof[ok]
            rhw[r[ok], c[ok]] = hw
        d, (ir, ic) = ndimage.distance_transform_edt(~rm, return_indices=True)
        d = d.astype(np.float32) * g.sp
        hwn = rhw[ir, ic]
        tgt = rprof[ir, ic]
        del ir, ic, rprof, rhw, rm
        core = d <= hwn + 1.0
        wgt = np.where(core, 1.0, 1.0 - smoothstep(hwn + 1.0, hwn + 1.0 + ROAD_SHOULDER, d)).astype(np.float32)
        base = Hb if it < ROAD_ITERS - 1 else H
        Hr = base * (1.0 - wgt) + tgt * wgt
        # křižovatky: maskované rozmazání uvnitř vozovky (různé profily dvou silnic se slijí)
        m = (d <= hwn + 2.0).astype(np.float32)
        hb = ndimage.gaussian_filter(Hr * m, 3.0)
        mb = ndimage.gaussian_filter(m, 3.0)
        Hr = np.where(m > 0, hb / np.maximum(mb, 1e-6), Hr).astype(np.float32)
        del tgt, wgt, m, hb, mb
        if it < ROAD_ITERS - 1:
            Hsrc = Hr
        else:
            H = Hr
    del H_pre, Hsrc, Hb
    road_core = core
    road_dist = d
    road_hw = hwn
    log(f"silnice ({time.time() - t0:.1f} s)")

    d = bd
    inside = (d < 0.5 * g.sp) | ((d <= PAD_DILATE + g.sp) & ~road_core)
    wgt = np.where(inside, 1.0, 1.0 - smoothstep(PAD_DILATE + g.sp, PAD_DILATE + g.sp + PAD_BLEND, d))
    wgt = np.where(inside, 1.0, wgt * (1.0 - road_core))                 # vozovka má přednost (náběh ne)
    H = (H * (1.0 - wgt) + gnear * wgt).astype(np.float32)
    pad_w = wgt.astype(np.float32)
    del wgt, gnear
    log(f"plošiny domů ({time.time() - t0:.1f} s)")

    masks = {"road_core": road_core, "road_dist": road_dist, "road_hw": road_hw, "pad": pad, "pad_w": pad_w,
             "pid": pid, "stream_dist": stream_dist, "stream_hw": stream_hw, "pond": pond, "bld_dist": d,
             "road_lines": road_lines}
    return H, skel, cmeta, masks


def write_terrain(g, H, masks):
    micro = fbm((g.h, g.w), 3, 2, 31) * MICRO_AMP
    quiet = np.clip(1.0 - masks["pad_w"] - masks["road_core"], 0.0, 1.0) * (masks["stream_dist"] > 4.0)
    vis = (H + micro * quiet).astype(np.float32)
    vis.tofile(os.path.join(OUT, "terrain_height.bin"))
    (H / g.sp).astype(np.float32).tofile(os.path.join(OUT, "terrain_collision.bin"))
    gz, gx = np.gradient(vis.astype(np.float64), g.sp)
    n = np.stack([-gx, np.ones_like(gx), -gz], axis=-1)
    n /= np.linalg.norm(n, axis=-1, keepdims=True)
    ((n * 0.5 + 0.5) * 255).round().astype(np.uint8).tofile(os.path.join(OUT, "terrain_normal.bin"))
    CH = g.chunk_cells
    mm = np.zeros((g.ncz, g.ncx, 2), np.float32)
    for iz in range(g.ncz):
        for ix in range(g.ncx):
            blk = vis[iz * CH:iz * CH + CH + 1, ix * CH:ix * CH + CH + 1]
            if blk.size:
                mm[iz, ix] = blk.min(), blk.max()
    mm.tofile(os.path.join(OUT, "terrain_chunks.bin"))
    log(f"terén zapsán: výšky {vis.min():.1f}..{vis.max():.1f} m")
    return vis


# ---------------------------------------------------------------------------------------------- DBM1

class TriBuf:
    """Trojúhelníky (Godot souřadnice) s normálou a barvou na vrchol."""

    def __init__(self):
        self.p, self.n, self.c = [], [], []

    def tri(self, a, b, c, col, nrm=None, out=None):
        """Trojúhelník a-b-c proti směru hodin při pohledu zvenku; `out` = žádaný směr normály (otočí pořadí)."""
        a, b, c = np.asarray(a, float), np.asarray(b, float), np.asarray(c, float)
        fn = np.cross(b - a, c - a)
        ln = np.linalg.norm(fn)
        if ln < 1e-9:
            return
        if out is not None and np.dot(fn, out) < 0:
            b, c, fn = c, b, -fn
        fn = fn / ln if nrm is None else np.asarray(nrm, float)
        # Godot: přední strana = po směru hodinových ručiček při pohledu zvenku → pořadí a, c, b
        self.p.append([a, c, b])
        self.n.append([fn, fn, fn])
        self.c.append([col, col, col])

    def quad(self, a, b, c, d, col, out=None):
        """Čtyřúhelník a-b-c-d proti směru hodin při pohledu z vnější strany."""
        self.tri(a, b, c, col, out=out)
        self.tri(a, c, d, col, out=out)

    def arrays(self):
        if not self.p:
            return np.zeros((0, 3, 3), np.float32), np.zeros((0, 3, 3), np.float32), np.zeros((0, 3, 3), np.float32)
        return (np.asarray(self.p, np.float32), np.asarray(self.n, np.float32), np.asarray(self.c, np.float32))


def write_dbm1(path, buf):
    pos, nrm, col = buf.arrays()
    cen = pos.mean(axis=1)
    kx = np.floor(cen[:, 0] / CHUNK).astype(int)
    kz = np.floor(cen[:, 2] / CHUNK).astype(int)
    keys = sorted(set(zip(kx.tolist(), kz.tolist())))
    with open(path, "wb") as f:
        f.write(b"DBM1")
        f.write(struct.pack("<i", len(keys)))
        for a, b in keys:
            sel = (kx == a) & (kz == b)
            p, n, c = pos[sel].reshape(-1, 3), nrm[sel].reshape(-1, 3), col[sel].reshape(-1, 3)
            f.write(struct.pack("<i", len(p)))
            f.write(p.astype(np.float32).tobytes())
            f.write(n.astype(np.float32).tobytes())
            f.write(c.astype(np.float32).tobytes())
    log(f"{os.path.basename(path)}: {len(pos)} trojúhelníků v {len(keys)} dlaždicích")


def ccw(poly):
    """Půdorys proti směru hodin při pohledu shora (osa y nahoru, x vpravo, z k pozorovateli → plocha < 0)."""
    P = np.asarray(poly, np.float64)
    a = np.sum(P[:, 0] * np.roll(P[:, 1], -1) - np.roll(P[:, 0], -1) * P[:, 1]) * 0.5
    return P if a < 0 else P[::-1]


def building_rect(b, P):
    """Obdélník střechy zarovnaný s hřebenem: střed, osa u (hřeben), osa v, půldélky."""
    u = np.asarray(b.get("ridge_dir") or [1.0, 0.0], np.float64)
    u = u / (np.linalg.norm(u) + 1e-9)
    v = np.array([-u[1], u[0]])
    pu, pv = P @ u, P @ v
    cu, cv = (pu.min() + pu.max()) * 0.5, (pv.min() + pv.max()) * 0.5
    c = u * cu + v * cv
    return c, u, v, (pu.max() - pu.min()) * 0.5, (pv.max() - pv.min()) * 0.5


def inner_rect(P, u, v, res=0.25):
    """Největší obdélník (osy u, v) uvnitř půdorysu – pro střechu domu do L / T (histogramová metoda nad rastrem)."""
    pu, pv = P @ u, P @ v
    nu = int((pu.max() - pu.min()) / res) + 1
    nv = int((pv.max() - pv.min()) / res) + 1
    U, V = np.meshgrid(pu.min() + (np.arange(nu) + 0.5) * res, pv.min() + (np.arange(nv) + 0.5) * res)
    ins = point_in_poly(U, V, np.c_[pu, pv])          # řádek = v, sloupec = u
    best = (0, 0, 0, 0, 0)                             # plocha, v0, v1, u0, u1 (indexy)
    hgt = np.zeros(nu, int)
    for j in range(nv):
        hgt = np.where(ins[j], hgt + 1, 0)
        st = []
        for i in range(nu + 1):
            cur = hgt[i] if i < nu else 0
            start = i
            while st and st[-1][1] >= cur:
                s0, h0 = st.pop()
                if h0 * (i - s0) > best[0]:
                    best = (h0 * (i - s0), j - h0 + 1, j + 1, s0, i)
                start = s0
            st.append((start, cur))
    _, v0, v1, u0, u1 = best
    a0, a1 = pu.min() + u0 * res, pu.min() + u1 * res
    b0, b1 = pv.min() + v0 * res, pv.min() + v1 * res
    c = u * (a0 + a1) * 0.5 + v * (b0 + b1) * 0.5
    return c, (a1 - a0) * 0.5, (b1 - b0) * 0.5


def poly_area(P):
    return abs(np.sum(P[:, 0] * np.roll(P[:, 1], -1) - np.roll(P[:, 0], -1) * P[:, 1])) * 0.5


def build_buildings(g, H, buildings):
    walls, roofs = TriBuf(), TriBuf()
    rng = np.random.default_rng(122)
    for b in buildings:
        P = ccw(b["poly"])
        k = len(P)
        if k < 3:
            continue
        gy, ey, ry = b["ground_y"], b["eave_y"], b["ridge_y"]
        btype = b.get("type", "house")
        fac = srgb_to_lin(BARN_FACADES[rng.integers(len(BARN_FACADES))] if btype in ("barn", "shed", "hall")
                          else FACADES[rng.integers(len(FACADES))])
        rcol = srgb_to_lin(ROOFS[rng.integers(len(ROOFS))])
        # pata zdí: pod nejnižší terén u stěny − 0,5 m (na svahu nikde nevisí)
        E = resample(np.vstack([P, P[:1]]), 1.0)
        hv = g.sample(H, E[:, 0], E[:, 1])
        base = min(gy, float(hv.min())) - 0.5
        for i in range(k):
            a, c = P[i], P[(i + 1) % k]
            walls.quad((a[0], base, a[1]), (c[0], base, c[1]), (c[0], ey, c[1]), (a[0], ey, a[1]), fac)
        shape = b.get("shape", "flat")
        if shape == "flat" or ry - ey < 0.3:
            top = ey + 0.15
            # atika: boky a plochý strop (fan triangulace – půdorysy jsou skoro konvexní; nekonvexní přes ořez uší)
            for i in range(k):
                a, c = P[i], P[(i + 1) % k]
                roofs.quad((a[0], ey, a[1]), (c[0], ey, c[1]), (c[0], top, c[1]), (a[0], top, a[1]), rcol)
            for tri in ear_clip(P):
                A, B, C = (P[j] for j in tri)
                roofs.tri((A[0], top, A[1]), (B[0], top, B[1]), (C[0], top, C[1]), rcol, nrm=(0, 1, 0), out=(0, 1, 0))
            continue
        c, u, v, hl, hw = building_rect(b, P)
        if poly_area(P) < 0.85 * 4.0 * hl * hw:
            # dům do L / T: sedlo nad největším vepsaným obdélníkem (štíty stojí na zdech), křídla mimo něj
            # dostanou plochou střechu ve výšce okapu (deska přes celý půdorys – pod sedlem není vidět)
            if shape != "hipped":
                c, hl, hw = inner_rect(P, u, v)
                if hw > hl and shape == "gable_long":
                    u, v, hl, hw = v, -u, hw, hl      # hřeben po delší straně vepsaného obdélníku
            top = ey + 0.12
            for i in range(k):
                a, cc = P[i], P[(i + 1) % k]
                roofs.quad((a[0], ey, a[1]), (cc[0], ey, cc[1]), (cc[0], top, cc[1]), (a[0], top, a[1]), rcol)
            for tri in ear_clip(P):
                A, B, C = (P[j] for j in tri)
                roofs.tri((A[0], top, A[1]), (B[0], top, B[1]), (C[0], top, C[1]), rcol, nrm=(0, 1, 0), out=(0, 1, 0))
        ov = 0.45
        slope = (ry - ey) / max(hw, 0.3)
        ze = ey - ov * slope
        HL, HW = hl + ov, hw + ov

        def Q(su, sv, y):
            p = c + u * su + v * sv
            return (p[0], y, p[1])

        if shape == "hipped":
            inset = min(hw, hl * 0.95)
            r0, r1 = -hl + inset, hl - inset
            if r1 <= r0 + 1e-3:
                r0 = r1 = 0.0
            A, B, C, D = Q(-HL, -HW, ze), Q(HL, -HW, ze), Q(HL, HW, ze), Q(-HL, HW, ze)
            E, F = Q(r0, 0, ry), Q(r1, 0, ry)
            up = (0, 1, 0)
            roofs.quad(A, B, F, E, rcol, out=up)
            roofs.quad(C, D, E, F, rcol, out=up)
            roofs.tri(B, C, F, rcol, out=up)
            roofs.tri(D, A, E, rcol, out=up)
        else:
            A, B, C, D = Q(-HL, -HW, ze), Q(HL, -HW, ze), Q(HL, HW, ze), Q(-HL, HW, ze)
            E, F = Q(-HL, 0, ry), Q(HL, 0, ry)
            roofs.quad(A, B, F, E, rcol, out=(0, 1, 0))
            roofs.quad(C, D, E, F, rcol, out=(0, 1, 0))
            # štíty (zeď) – trojúhelník nad okapem na obou koncích
            walls.tri(Q(-hl, hw, ey), Q(-hl, -hw, ey), Q(-hl, 0, ry), fac, out=(-u[0], 0, -u[1]))
            walls.tri(Q(hl, -hw, ey), Q(hl, hw, ey), Q(hl, 0, ry), fac, out=(u[0], 0, u[1]))
            # podhled střechy (spodní strana přesahu) se kreslí díky cull_disabled
    write_dbm1(os.path.join(OUT, "walls.bin"), walls)
    write_dbm1(os.path.join(OUT, "roofs.bin"), roofs)


def ear_clip(P):
    """Triangulace jednoduchého polygonu (indexy). P je proti směru hodin (v x, z se zápornou plochou)."""
    idx = list(range(len(P)))
    out = []

    def area2(a, b, c):
        return (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0])

    sign = -1.0   # orientace podle ccw(): plocha < 0
    guard = 0
    while len(idx) > 3 and guard < 10000:
        guard += 1
        found = False
        for i in range(len(idx)):
            a, b, c = idx[i - 1], idx[i], idx[(i + 1) % len(idx)]
            A, B, C = P[a], P[b], P[c]
            if area2(A, B, C) * sign <= 1e-9:
                continue
            inside = False
            for j in idx:
                if j in (a, b, c):
                    continue
                Pj = P[j]
                d1, d2, d3 = area2(A, B, Pj) * sign, area2(B, C, Pj) * sign, area2(C, A, Pj) * sign
                if d1 >= 0 and d2 >= 0 and d3 >= 0:
                    inside = True
                    break
            if inside:
                continue
            out.append((a, b, c))
            idx.pop(i)
            found = True
            break
        if not found:
            break
    if len(idx) == 3:
        out.append(tuple(idx))
    elif len(idx) > 3:
        for i in range(1, len(idx) - 1):
            out.append((idx[0], idx[i], idx[i + 1]))
    return out


def build_roads(g, H, masks):
    asph, grav = TriBuf(), TriBuf()
    white = (1.0, 1.0, 1.0)
    for rd, P, prof, hw in masks["road_lines"]:
        P2 = resample(np.c_[P[:, :2], prof], 2.5)
        if len(P2) < 2:
            continue
        n = len(P2)
        dirs = np.zeros((n, 2))
        dirs[1:-1] = P2[2:, :2] - P2[:-2, :2]
        dirs[0] = P2[1, :2] - P2[0, :2]
        dirs[-1] = P2[-1, :2] - P2[-2, :2]
        dirs /= np.linalg.norm(dirs, axis=1, keepdims=True) + 1e-9
        nrm = np.c_[-dirs[:, 1], dirs[:, 0]] * hw
        L, R = P2[:, :2] + nrm, P2[:, :2] - nrm
        y = g.sample(H, P2[:, 0], P2[:, 1]) + 0.06
        buf = grav if rd["kind"] in GRAVEL_KINDS else asph
        for i in range(n - 1):
            a, b = (L[i, 0], y[i], L[i, 1]), (L[i + 1, 0], y[i + 1], L[i + 1, 1])
            c, d = (R[i + 1, 0], y[i + 1], R[i + 1, 1]), (R[i, 0], y[i], R[i, 1])
            # normála nahoru (silnice se stejně „přilepí“ na terén v MapLoader.load_chunks)
            buf.tri(a, b, c, white, nrm=(0, 1, 0), out=(0, 1, 0))
            buf.tri(a, c, d, white, nrm=(0, 1, 0), out=(0, 1, 0))
    # orientace: tri() prohazuje pořadí – u vozovky chceme normálu nahoru a přední stranu shora
    write_dbm1(os.path.join(OUT, "asphalt.bin"), asph)
    write_dbm1(os.path.join(OUT, "gravel.bin"), grav)


# ---------------------------------------------------------------------------------------------- krajina (4 m)

def land_cover(g, H, masks, buildings, meta, water):
    """Třídy povrchu a využití ploch v rastru 4 m + maska lesa (pro stromy)."""
    t0 = time.time()
    cell = 4.0
    nx, nz = int(math.ceil(g.w * g.sp / cell)), int(math.ceil(g.h * g.sp / cell))
    H4 = H[::2, ::2][:nz, :nx]
    if H4.shape != (nz, nx):
        H4 = np.pad(H4, ((0, nz - H4.shape[0]), (0, nx - H4.shape[1])), mode="edge")
    gz, gx = np.gradient(H4.astype(np.float64), cell)
    slope = np.hypot(gx, gz)
    tpi = H4 - ndimage.uniform_filter(H4, 75)                  # topografická poloha ~300 m
    bd = masks["bld_dist"][::2, ::2][:nz, :nx]
    bd = np.pad(bd, ((0, nz - bd.shape[0]), (0, nx - bd.shape[1])), mode="edge")
    sd = masks["stream_dist"][::2, ::2][:nz, :nx]
    sd = np.pad(sd, ((0, nz - sd.shape[0]), (0, nx - sd.shape[1])), mode="edge")
    rd = masks["road_dist"][::2, ::2][:nz, :nx]
    rd = np.pad(rd, ((0, nz - rd.shape[0]), (0, nx - rd.shape[1])), mode="edge")
    rhw = masks["road_hw"][::2, ::2][:nz, :nx]
    rhw = np.pad(rhw, ((0, nz - rhw.shape[0]), (0, nx - rhw.shape[1])), mode="edge")
    pond = masks["pond"][::2, ::2][:nz, :nx]
    pond = np.pad(pond, ((0, nz - pond.shape[0]), (0, nx - pond.shape[1])))

    # les: šum + strmost + hřbety, daleko od vsi
    fn = fbm((nz, nx), 160, 4, 41)
    score = fn * 0.9 + np.clip(slope * 5.0, 0, 1.2) + np.clip(tpi / 25.0, -0.6, 0.8) - 1.6 * (1.0 - smoothstep(120.0, 420.0, bd))
    thr = np.quantile(score, 0.70)
    forest = (score > thr) & (rd > rhw + 3.0) & ~pond & (sd > 6.0)
    forest = ndimage.binary_opening(forest, iterations=2)
    forest = ndimage.binary_closing(forest, iterations=2) & (rd > rhw + 3.0) & ~pond & (sd > 6.0)

    # parcely polí: protáhlé Voronoi buňky (osa natočená po oblastech)
    rng = np.random.default_rng(51)
    xs = g.x0 + (np.arange(nx) + 0.5) * cell
    zs = g.z0 + (np.arange(nz) + 0.5) * cell
    W_ = (g.w - 1) * g.sp
    H_ = (g.h - 1) * g.sp
    nseed = int(W_ * H_ / (170.0 * 170.0))
    S = np.c_[g.x0 + rng.random(nseed) * W_, g.z0 + rng.random(nseed) * H_]
    # protáhlé parcely: anizotropní metrika (natočení θ, poměr 1 : 2,4) + deformace souřadnic (meze nejsou rovné)
    th = 0.35
    ct, st = math.cos(th), math.sin(th)

    def aniso(x, z):
        return np.c_[(x * ct + z * st) / 2.4, -x * st + z * ct]

    wx = fbm((nz, nx), 60, 2, 52) * 35.0
    wz = fbm((nz, nx), 60, 2, 55) * 35.0
    ids = np.zeros((nz, nx), np.int32)
    tree = cKDTree(aniso(S[:, 0], S[:, 1]))
    for r0 in range(0, nz, 128):
        Z, X = np.meshgrid(zs[r0:r0 + 128], xs, indexing="ij")
        q = aniso((X + wx[r0:r0 + 128]).ravel(), (Z + wz[r0:r0 + 128]).ravel())
        _, ii = tree.query(q, k=1, workers=-1)
        ids[r0:r0 + 128] = ii.reshape(X.shape)
    edge = np.zeros((nz, nx), bool)
    edge[:, 1:] |= ids[:, 1:] != ids[:, :-1]
    edge[1:, :] |= ids[1:, :] != ids[:-1, :]
    rnd = np.random.default_rng(53).random(nseed)
    open_ = ~forest & ~pond & (rd > rhw + 0.5)
    arable = open_ & (slope < 0.14) & (bd > 70.0) & (sd > 18.0) & (rnd[ids] < 0.72) & ~edge
    meadow = open_ & ~arable
    orchard = open_ & (bd > 12.0) & (bd < 90.0) & (fbm((nz, nx), 30, 2, 54) > 0.35)
    garden = open_ & (bd > 2.0) & (bd < 22.0) & ~orchard

    landuse = np.zeros((nz, nx, 2), np.uint8)
    landuse[..., 0] = np.where(arable, 1, np.where(meadow & (bd > 45.0), 2, 0))
    landuse[..., 0] = np.where(orchard, 3, landuse[..., 0])
    landuse[..., 0] = np.where(garden, 4, landuse[..., 0])
    landuse[..., 1] = np.where(arable, (ids % 255) + 1, 0).astype(np.uint8)
    hdr = b"LUSE" + struct.pack("<i", 1) + struct.pack("<fff", g.x0, g.z0, cell) + struct.pack("<ii", nx, nz)
    with open(os.path.join(OUT, "landuse.bin"), "wb") as f:
        f.write(hdr)
        f.write(landuse.tobytes())

    surf = np.zeros((nz, nx), np.uint8)
    surf[arable] = 1
    surf[orchard | garden] = 2
    surf[forest] = 3
    surf[bd < 7.0] = 4
    surf[(sd < 4.0) | (ndimage.binary_dilation(pond, iterations=1) & ~pond)] = 5
    trk = (rd < rhw + 0.6) & (rhw > 0) & (rhw <= 1.6)
    surf[trk] = 7
    hdr = b"SURF" + struct.pack("<i", 1) + struct.pack("<fff", g.x0, g.z0, cell) + struct.pack("<ii", nx, nz)
    with open(os.path.join(OUT, "surface.bin"), "wb") as f:
        f.write(hdr)
        f.write(surf.tobytes())
    log(f"landuse.bin + surface.bin {nx}×{nz}: les {forest.mean() * 100:.0f} %, orná {arable.mean() * 100:.0f} % "
        f"({time.time() - t0:.1f} s)")
    return {"cell": cell, "nx": nx, "nz": nz, "forest": forest, "surf": surf, "slope": slope, "tpi": tpi,
            "edge": edge & open_, "H4": H4}


# ---------------------------------------------------------------------------------------------- stromy

def tree_protos():
    """6 prototypů DBT1 (0–2 listnáče, 3–5 jehličnany) v jednotkách: výška 1, poloměr koruny ~0,85."""
    def cyl(r0, r1, y0, y1, seg=7):
        p, n = [], []
        for i in range(seg):
            a0, a1 = 2 * math.pi * i / seg, 2 * math.pi * (i + 1) / seg
            c0, s0, c1, s1 = math.cos(a0), math.sin(a0), math.cos(a1), math.sin(a1)
            A, B = (c0 * r0, y0, s0 * r0), (c1 * r0, y0, s1 * r0)
            C, D = (c1 * r1, y1, s1 * r1), (c0 * r1, y1, s0 * r1)
            for tri in ((A, C, B), (A, D, C)):
                p += tri
                for q in tri:
                    ln = math.hypot(q[0], q[2]) or 1.0
                    n.append((q[0] / ln, 0.0, q[2] / ln))
        return p, n

    def blob(cy, rx, ry, lumps, seed, seg=10, rings=7):
        rng = np.random.default_rng(seed)
        ph = rng.random(4) * 6.28
        V = np.zeros((rings + 1, seg + 1, 3))
        for j in range(rings + 1):
            th = math.pi * j / rings
            for i in range(seg + 1):
                fi = 2 * math.pi * i / seg
                k = 1.0 + lumps * (math.sin(3 * fi + ph[0]) * math.sin(2 * th + ph[1]) * 0.6
                                   + math.sin(5 * fi + ph[2]) * 0.4 * math.sin(3 * th + ph[3]))
                V[j, i] = (math.sin(th) * math.cos(fi) * rx * k, cy + math.cos(th) * ry * k, math.sin(th) * math.sin(fi) * rx * k)
        p, n = [], []
        for j in range(rings):
            for i in range(seg):
                A, B, C, D = V[j, i], V[j, i + 1], V[j + 1, i + 1], V[j + 1, i]
                for tri in ((A, B, C), (A, C, D)):
                    for q in tri:
                        p.append(tuple(q))
                        d = np.array([q[0] / rx, (q[1] - cy) / ry, q[2] / rx])
                        d /= np.linalg.norm(d) + 1e-9
                        n.append(tuple(d))
        return p, n

    def cone_stack(y0, y1, r, tiers, seg=9):
        p, n = [], []
        for t in range(tiers):
            a = y0 + (y1 - y0) * t / tiers * 0.85
            top = a + (y1 - y0) * 0.42
            rr = r * (1.0 - t / tiers * 0.75)
            for i in range(seg):
                a0, a1 = 2 * math.pi * i / seg, 2 * math.pi * (i + 1) / seg
                A = (0.0, top, 0.0)
                B = (math.cos(a0) * rr, a, math.sin(a0) * rr)
                C = (math.cos(a1) * rr, a, math.sin(a1) * rr)
                for q in (A, C, B):
                    p.append(q)
                    nn = np.array([q[0], rr * 0.5, q[2]])
                    nn /= np.linalg.norm(nn) + 1e-9
                    n.append(tuple(nn))
        return p, n

    protos = []
    for k, (cy, ry, lumps) in enumerate(((0.62, 0.36, 0.12), (0.66, 0.32, 0.18), (0.58, 0.40, 0.10))):
        protos.append([cyl(0.06, 0.035, 0.0, 0.62), blob(cy, 0.85, ry, lumps, 60 + k)])
    for k, (y0, r, tiers) in enumerate(((0.12, 0.55, 5), (0.18, 0.5, 6), (0.08, 0.62, 4))):
        protos.append([cyl(0.05, 0.02, 0.0, 0.95), cone_stack(y0, 1.0, r, tiers)])
    with open(os.path.join(OUT, "tree_protos.bin"), "wb") as f:
        f.write(b"DBT1")
        f.write(struct.pack("<i", len(protos)))
        for surfs in protos:
            f.write(struct.pack("<i", 2))
            for p, n in surfs:
                # tri() konvence Godotu: prohodit 2. a 3. vrchol (přední strana po směru hodin)
                P = np.asarray(p, np.float32).reshape(-1, 3, 3)[:, [0, 2, 1]].reshape(-1, 3)
                N = np.asarray(n, np.float32).reshape(-1, 3, 3)[:, [0, 2, 1]].reshape(-1, 3)
                f.write(struct.pack("<i", len(P)))
                f.write(P.tobytes())
                f.write(N.tobytes())
    log("tree_protos.bin: 6 prototypů")


def build_trees(g, H, masks, lc, buildings, meta, water):
    """Stromy: les (rozestup podle cílového počtu), břehové porosty, aleje, ovocné stromy u domů, solitéry na mezích."""
    rng = np.random.default_rng(71)
    cell = lc["cell"]
    forest = lc["forest"]
    # zakázané místo pro kmen: dům + 1,5 m, vozovka + 1,2 m, koryto, rybník (na mřížce 2 m)
    bad = (masks["bld_dist"] < 1.5 + g.sp) | (masks["road_dist"] < masks["road_hw"] + 1.2 + g.sp * 0.5) \
        | (masks["stream_dist"] < masks["stream_hw"] + 0.8) | masks["pond"]
    out = []   # [x, z, proto, sx, sy, (r, g, b)]

    def ok(x, z):
        c, r = g.to_px(x, z)
        c = np.clip(np.round(c).astype(int), 0, g.w - 1)
        r = np.clip(np.round(r).astype(int), 0, g.h - 1)
        return ~bad[r, c]

    # les
    spacing = FOREST_SPACING
    nxs = int((g.w - 1) * g.sp / spacing)
    nzs = int((g.h - 1) * g.sp / spacing)
    gx, gz = np.meshgrid(np.arange(nxs), np.arange(nzs))
    X = g.x0 + (gx.ravel() + 0.15 + rng.random(gx.size) * 0.7) * spacing
    Z = g.z0 + (gz.ravel() + 0.15 + rng.random(gz.size) * 0.7) * spacing
    fi = np.clip(((Z - g.z0) / cell).astype(int), 0, lc["nz"] - 1)
    fj = np.clip(((X - g.x0) / cell).astype(int), 0, lc["nx"] - 1)
    sel = forest[fi, fj] & ok(X, Z)
    X, Z, fi, fj = X[sel], Z[sel], fi[sel], fj[sel]
    tpi = lc["tpi"][fi, fj]
    cn = fbm((lc["nz"], lc["nx"]), 220, 3, 72)[fi, fj]
    conifer = (cn + np.clip(tpi / 30.0, -0.5, 0.5) + 0.1) > 0.0
    for i in range(len(X)):
        if conifer[i]:
            p = 3 + int(rng.integers(3))
            sy = 20.0 + rng.random() * 12.0
            sx = 4.0 + rng.random() * 1.6
            col = (0.05 + rng.random() * 0.02, 0.10 + rng.random() * 0.03, 0.06 + rng.random() * 0.02)
        else:
            p = int(rng.integers(3))
            sy = 18.0 + rng.random() * 10.0
            sx = 6.0 + rng.random() * 2.2
            col = (0.08 + rng.random() * 0.04, 0.16 + rng.random() * 0.05, 0.05 + rng.random() * 0.03)
        out.append((X[i], Z[i], p, sx, sy, col))
    nforest = len(out)

    # břehové porosty (olše, vrby) – podél toků mimo les
    for s in water["streams"]:
        P = resample(s["pts"], 9.0)
        hw = STREAM.get(s["kind"], STREAM["stream"])["flat"] * 0.5 + 3.0
        for i in range(1, len(P) - 1):
            if rng.random() > 0.55:
                continue
            d = P[i + 1, :2] - P[i - 1, :2]
            d /= np.linalg.norm(d) + 1e-9
            side = 1.0 if rng.random() < 0.5 else -1.0
            q = P[i, :2] + np.array([-d[1], d[0]]) * side * (hw + rng.random() * 2.5)
            out.append((q[0], q[1], int(rng.integers(3)), 3.5 + rng.random() * 2.0, 11.0 + rng.random() * 8.0,
                        (0.09, 0.18 + rng.random() * 0.04, 0.06)))

    # aleje u silnic mimo les a ves
    for rd, P, prof, hw in masks["road_lines"]:
        if rd["kind"] not in ("tertiary", "secondary", "unclassified", "track"):
            continue
        Q = resample(P[:, :2], 13.0)
        prob = 0.55 if rd["kind"] != "track" else 0.12
        for i in range(1, len(Q) - 1):
            if rng.random() > prob:
                continue
            d = Q[i + 1] - Q[i - 1]
            d /= np.linalg.norm(d) + 1e-9
            side = 1.0 if (i // 3) % 2 == 0 else -1.0
            q = Q[i] + np.array([-d[1], d[0]]) * side * (hw + 2.8)
            if masks_bld_near(masks, g, q, 40.0):
                continue
            out.append((q[0], q[1], int(rng.integers(3)), 3.2 + rng.random() * 1.4, 9.0 + rng.random() * 7.0,
                        (0.1, 0.19, 0.06)))

    # ovocné stromy a zahradní stromy u domů (za domem, dál od silnice)
    for b in buildings:
        if b.get("type") not in ("house", "public"):
            continue
        P = np.asarray(b["poly"])
        c = P.mean(0)
        door = np.asarray(b["door"]) if b.get("door") else c
        away = c - door
        away /= np.linalg.norm(away) + 1e-9
        for _ in range(int(rng.integers(1, 5))):
            ang = (rng.random() - 0.5) * 2.2
            ca, sa = math.cos(ang), math.sin(ang)
            dvec = np.array([away[0] * ca - away[1] * sa, away[0] * sa + away[1] * ca])
            q = c + dvec * (np.sqrt(((P - c) ** 2).sum(1)).max() + 4.0 + rng.random() * 16.0)
            out.append((q[0], q[1], int(rng.integers(3)), 2.2 + rng.random() * 1.2, 5.0 + rng.random() * 4.0,
                        (0.11, 0.2, 0.07)))

    # solitéry na mezích
    edge = lc["edge"]
    ei, ej = np.nonzero(edge)
    pick = rng.choice(len(ei), size=min(2500, len(ei)), replace=False) if len(ei) else []
    for k in pick:
        x = g.x0 + (ej[k] + 0.5) * cell
        z = g.z0 + (ei[k] + 0.5) * cell
        out.append((x, z, int(rng.integers(3)), 3.5 + rng.random() * 2.5, 9.0 + rng.random() * 9.0,
                    (0.09, 0.18, 0.06)))

    A = np.asarray([(o[0], o[1]) for o in out])
    keep = ok(A[:, 0], A[:, 1])
    # uvnitř mřížky
    keep &= (A[:, 0] > g.x0 + 4) & (A[:, 0] < g.x0 + (g.w - 1) * g.sp - 4)
    keep &= (A[:, 1] > g.z0 + 4) & (A[:, 1] < g.z0 + (g.h - 1) * g.sp - 4)
    out = [o for o, k in zip(out, keep) if k]
    rec = np.zeros((len(out), 11), np.float32)
    for i, (x, z, p, sx, sy, col) in enumerate(out):
        y = float(g.sample(H, x, z)) - 0.1
        rec[i] = (x, y, z, rng.random() * 6.2832, sx, sy, sx, col[0], col[1], col[2], p)
    with open(os.path.join(OUT, "trees.bin"), "wb") as f:
        f.write(b"DBI1")
        f.write(struct.pack("<i", len(rec)))
        f.write(rec.tobytes())
    log(f"trees.bin: {len(rec)} stromů (les {nforest}, rozestup v lese {spacing:.1f} m)")


def masks_bld_near(masks, g, q, r):
    c, rr = g.to_px(q[0], q[1])
    c = int(np.clip(round(float(c)), 0, g.w - 1))
    rr = int(np.clip(round(float(rr)), 0, g.h - 1))
    return masks["bld_dist"][rr, c] < r


# ---------------------------------------------------------------------------------------------- okolí

def build_surround(g, skel, cmeta, lc):
    cx0, cz0, nx, nz = cmeta
    step = 25.0
    sx = int(((nx - 1) * COARSE) / step)
    sz = int(((nz - 1) * COARSE) / step)
    xs = cx0 + np.arange(sx) * step
    zs = cz0 + np.arange(sz) * step
    Z, X = np.meshgrid(zs, xs, indexing="ij")
    hh = ndimage.map_coordinates(skel.astype(np.float64), [(Z - cz0) / COARSE, (X - cx0) / COARSE], order=1)
    # povrch: les ze stejného šumu jako uvnitř + pole
    f = fbm((sz, sx), 26, 3, 41)
    cls = np.where(f > 0.25, 3, np.where(f < -0.15, 1, 0)).astype(np.uint8)
    hdr = struct.pack("<i", 1) + struct.pack("<fff", cx0, cz0, step) + struct.pack("<ii", sx, sz)
    with open(os.path.join(OUT, "surround_height.bin"), "wb") as fo:
        fo.write(b"SURH" + hdr)
        fo.write(hh.astype(np.float32).tobytes())
    with open(os.path.join(OUT, "surround_surface.bin"), "wb") as fo:
        fo.write(b"SURS" + hdr)
        fo.write(cls.tobytes())
    log(f"surround_height.bin {sx}×{sz} po {step:.0f} m")


# ---------------------------------------------------------------------------------------------- hlavní

def missing(names, force):
    return force or any(not os.path.exists(os.path.join(OUT, n)) for n in names)


def run_tool(args, out):
    if os.path.exists(os.path.join(OUT, out)):
        return
    log("spouštím", " ".join(args))
    r = subprocess.run([sys.executable] + args, cwd=GAME)
    if r.returncode != 0:
        log(f"POZOR: {args[0]} skončil chybou {r.returncode} – {out} chybí (hra má fallback)")


def main():
    global OUT
    force = "--force" in sys.argv
    for a in sys.argv[1:]:
        if a.startswith("--out="):
            OUT = os.path.abspath(a.split("=", 1)[1])
            os.makedirs(OUT, exist_ok=True)
    only = None
    for a in sys.argv[1:]:
        if a.startswith("--only="):
            only = set(a.split("=", 1)[1].split(","))
    meta = json.load(open(os.path.join(DATA, "map.json"), encoding="utf-8"))
    buildings = json.load(open(os.path.join(DATA, "buildings.json"), encoding="utf-8"))
    water = json.load(open(os.path.join(DATA, "water.json"), encoding="utf-8"))
    g = Grid(meta)
    groups = {
        "terrain": ["terrain_height.bin", "terrain_collision.bin", "terrain_normal.bin", "terrain_chunks.bin"],
        "buildings": ["walls.bin", "roofs.bin"],
        "roads": ["asphalt.bin", "gravel.bin"],
        "landuse": ["landuse.bin", "surface.bin"],
        "trees": ["trees.bin", "tree_protos.bin"],
        "surround": ["surround_height.bin", "surround_surface.bin"],
    }
    todo = [k for k, v in groups.items() if (only is None or k in only) and missing(v, force)]
    for k in todo:
        for n in groups[k]:
            if os.path.exists(os.path.join(OUT, n)) and not force:
                raise SystemExit(f"synth_world: {n} už existuje a skupina '{k}' je neúplná – "
                                 "nic nepřepisuji (pravá data?). Použij --force, nebo soubor smaž.")
    if todo:
        log("generuji:", ", ".join(todo))
        t0 = time.time()
        # terén je základ všeho ostatního – pokud existuje, načte se (nepřepisuje se)
        H, skel, cmeta, masks = build_terrain(g, meta, buildings, water)
        if "terrain" in todo:
            Hv = write_terrain(g, H, masks)
        else:
            Hv = np.fromfile(os.path.join(OUT, "terrain_height.bin"), np.float32).reshape(g.h, g.w)
        if "buildings" in todo:
            build_buildings(g, Hv, buildings)
        if "roads" in todo:
            build_roads(g, Hv, masks)
        lc = None
        if "landuse" in todo or "trees" in todo:
            if "landuse" not in todo:
                log("POZOR: landuse.bin existuje – maska lesa pro stromy se dopočítá, soubor se nepřepíše")
                bak = {n: open(os.path.join(OUT, n), "rb").read() for n in groups["landuse"]}
            lc = land_cover(g, Hv, masks, buildings, meta, water)
            if "landuse" not in todo:
                for n, data in bak.items():
                    open(os.path.join(OUT, n), "wb").write(data)
        if "trees" in todo:
            tree_protos()
            build_trees(g, Hv, masks, lc, buildings, meta, water)
        if "surround" in todo:
            build_surround(g, skel, cmeta, lc)
        log(f"hotovo za {time.time() - t0:.0f} s")
    else:
        log("základní data už existují – nic negeneruji (--force přepíše)")
    if (only is None or "extra" in only) and OUT == DATA:
        # odvozená data původními nástroji (jen když chybí; bez nich má hra fallbacky)
        run_tool(["tools/site.py"], "site.bin")
        run_tool(["tools/tree_species.py"], "tree_eco.bin")
        run_tool(["tools/vegetation.py", "--eco"], "vegetation.bin")


if __name__ == "__main__":
    main()
