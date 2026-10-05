#!/usr/bin/env python3
"""B3 – fyzická zástavba + silniční pásy pro union území → walls/roofs/asphalt/gravel.bin

Staré trojúhelníky zůstávají VERBATIM (snapshot pipeline/data/pre_b3/), nové se
generují čistě v Pythonu bez Blenderu – vzor phase13_build_full.py a export_map.py.

Vstupy:
  pipeline/data/okoli_union_local.geojson – buildings (Polygon, osm_id) + highways
  geodata/{dtm,dsm}_union_scene.npy      – nDSM pro fit střech (vzor phase12)
  geodata/ortho_union_scene.jpg          – barva střech (medián pod půdorysem)
  data/terrain_height.bin                – union mřížka (posazení patek zdí a pásů)
  pipeline/data/buildings_3d{,_full}.json + scene_reference.exclude_osm_ids
  data/{walls,roofs,asphalt,gravel}.bin  – staré chunky (dedup + verbatim merge)

Dedup budov: osm_id ∈ starých podkladech (367 OSM + 129 dmp_*), exclude_osm_ids
(dům hráče way/279053823), NEBO půdorys se kryje ≥50 % s rastrem starých střech
+zdí (přejmenované way id / artefakty). Ověřeno: 375 union budov má centroid
v katastru+150 m, z toho 367 osm_id match, 6 překryv půdorysu, 1 dům hráče,
1 nová kaple (přidá se).

Dedup silnic: čistě prostorový – staré pásy pokrývají katastr + ~150 m návesť
(ověřeno na centroidech starých trojúhelníků: max 152 m venku). Nové pásy drží
jen body mimo katastr a dál než 142 m od hranice → ~8 m přesah do starého pásu,
zúžený na špici (navázání bez z-fightingu – obě vrstvy drape na stejný terén).
Ověřeno: všech 145 union silnic s centroidem v katastru+150 m má osm_id ve
starém extraktu → uvnitř nic nepřibývá.

Zápis: celý soubor se re-tiluje po 256 m dlaždicích (chunk indexy nikdo
externě nereferencuje; formát DBM1 jako export_map.write_chunked).

Spuštění: python3 tools/expand_buildings.py [--limit=N] [--report-only]
"""
import json
import math
import os
import shutil
import struct
import sys

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage

Image.MAX_IMAGE_PIXELS = None
HERE = os.path.dirname(os.path.abspath(__file__))
GAME = os.path.dirname(HERE)
PIPE = os.path.join(GAME, "pipeline")
PDATA = os.path.join(PIPE, "data")
GEO = os.path.join(GAME, "geodata")
DATA = os.path.join(GAME, "data")
PRE_B3 = os.path.join(PDATA, "pre_b3")
PSCRIPTS = os.path.join(PIPE, "scripts")
sys.path.insert(0, PSCRIPTS)
from phase6_analyze import (fit_roof, roof_from_fit, mar, pip, dist_to_edges,  # noqa: E402
                            open_ring, FACADE_TINTS)

CHUNK = 256.0
BINS = ("walls.bin", "roofs.bin", "asphalt.bin", "gravel.bin")

# silniční pásy – šířky a mapování druhů jako phase13_build_full.py / expand_map.py
ROAD_W = {"secondary": 7, "tertiary": 6.5, "unclassified": 5.5, "residential": 5.5,
          "living_street": 5, "service": 3.5, "track": 3, "path": 1.5, "footway": 1.8,
          "cycleway": 2}
ROAD_STEP = 2.5            # zahuštění osy pásu (phase13.densify)
ADMIN_BUFFER = 150.0       # staré pásy/budovy sahaly max tolik za hranici katastru
ROAD_OVERLAP_IN = 8.0      # nový pás sahá tolik metrů DO starého pokrytí (navázání)
ROAD_TAPER = 7.0           # na posledních N metrech se pás zuzuje na špici (anti z-fight)
GRID_MARGIN = 4.0          # pásy končí tolik metrů před okrajem mřížky
MIN_EDGE = 0.05            # m – degenerovaná hrana půdorysu se přeskočí
DUP_FRAC = 0.5             # půdorys krytý z ≥50 % starým rastrem = duplicita

H_REF = json.load(open(os.path.join(PDATA, "terrain_ref.json")))["H_ref"]


# ------------------------------------------------------------------ bin IO

def read_dbm(path):
    b = open(path, "rb").read()
    assert b[:4] == b"DBM1"
    n_chunks = struct.unpack_from("<i", b, 4)[0]
    off = 8
    P, N, C = [], [], []
    for _ in range(n_chunks):
        n = struct.unpack_from("<i", b, off)[0]
        off += 4
        for arr in (P, N, C):
            arr.append(np.frombuffer(b, "<f4", n * 3, off).reshape(-1, 3, 3))
            off += n * 12
    return np.concatenate(P), np.concatenate(N), np.concatenate(C)


def write_chunked(path, pos, nrm, col):
    """DBM1 jako export_map.write_chunked – re-tile celého souboru po 256 m."""
    cen = pos.mean(axis=1)
    kx = np.floor(cen[:, 0] / CHUNK).astype(int)
    kz = np.floor(cen[:, 2] / CHUNK).astype(int)
    keys = sorted(set(zip(kx.tolist(), kz.tolist())))
    with open(path, "wb") as f:
        f.write(b"DBM1")
        f.write(struct.pack("<i", len(keys)))
        for a, c in keys:
            sel = (kx == a) & (kz == c)
            f.write(struct.pack("<i", int(sel.sum()) * 3))
            f.write(pos[sel].reshape(-1, 3).astype("<f4").tobytes())
            f.write(nrm[sel].reshape(-1, 3).astype("<f4").tobytes())
            f.write(col[sel].reshape(-1, 3).astype("<f4").tobytes())
    print(f"WROTE {os.path.basename(path)}: {len(pos)} tris, {len(keys)} chunks, "
          f"{os.path.getsize(path) / 1e6:.2f} MB")


def backup_pre_b3():
    """Snapshot starých binů před B3 merge – idempotence jako expand_map.pre_expand."""
    os.makedirs(PRE_B3, exist_ok=True)
    made = []
    for fn in BINS:
        src, dst = os.path.join(DATA, fn), os.path.join(PRE_B3, fn)
        if os.path.exists(src) and not os.path.exists(dst):
            shutil.copy(src, dst)
            made.append(fn)
    if made:
        print("pre-b3 snapshot →", PRE_B3, ":", ", ".join(made))
    return PRE_B3


# ------------------------------------------------------------------ geometrické pomocné

def srgb_to_lin(c):
    c = np.asarray(c, float)
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def ccw(pts):
    a = sum(pts[i][0] * pts[(i + 1) % len(pts)][1] - pts[(i + 1) % len(pts)][0] * pts[i][1]
            for i in range(len(pts)))
    return pts if a > 0 else pts[::-1]


def earclip(poly):
    """CCW půdorys → indexové trojúhelníky (ucho; fallback vějíř při selhání)."""
    idx = list(range(len(poly)))
    tris = []

    def a2(a, b, c):
        return (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0])

    guard = 0
    while len(idx) > 3 and guard < 4 * len(poly):
        guard += 1
        m = len(idx)
        clipped = False
        for k in range(m):
            i0, i1, i2 = idx[(k - 1) % m], idx[k], idx[(k + 1) % m]
            a, b, c = poly[i0], poly[i1], poly[i2]
            if a2(a, b, c) <= 1e-9:
                continue
            ok = True
            for j in idx:
                if j in (i0, i1, i2):
                    continue
                p = poly[j]
                if a2(a, b, p) >= -1e-9 and a2(b, c, p) >= -1e-9 and a2(c, a, p) >= -1e-9:
                    ok = False
                    break
            if not ok:
                continue
            tris.append((i0, i1, i2))
            idx.pop(k)
            clipped = True
            break
        if not clipped:
            break
    if len(idx) == 3:
        tris.append(tuple(idx))
    else:
        for k in range(1, len(idx) - 1):          # fallback – radši vějíř než nic
            tris.append((idx[0], idx[k], idx[k + 1]))
    return tris


def densify(pts, step=ROAD_STEP):
    out = [pts[0]]
    for (x1, y1), (x2, y2) in zip(pts[:-1], pts[1:]):
        L = math.hypot(x2 - x1, y2 - y1)
        k = max(1, int(L / step))
        for i in range(1, k + 1):
            out.append((x1 + (x2 - x1) * i / k, y1 + (y2 - y1) * i / k))
    return out


def roof_parts(rect, eave, ridge, shape, overhang=0.45):
    """Kopie export_map.roof_parts (scéna x,y,z): sedlová/valbová střecha + štíty."""
    cx, cy, L, W, a = rect
    if shape == "gable_short":
        L, W, a = W, L, a + math.pi / 2
    c, s = math.cos(a), math.sin(a)
    half = W / 2
    slope = (ridge - eave) / max(half, 0.3)
    hl, hw = L / 2 + overhang, W / 2 + overhang
    ze = eave - overhang * slope

    def P(u, v, z):
        return (cx + u * c - v * s, cy + u * s + v * c, z)

    if shape == "hipped":
        inset = min(W / 2, L / 2 * 0.95)
        rv = [P(-hl, -hw, ze), P(hl, -hw, ze), P(hl, hw, ze), P(-hl, hw, ze),
              P(-L / 2 + inset, 0, ridge), P(L / 2 - inset, 0, ridge)]
        if L / 2 - inset <= -L / 2 + inset + 1e-3:
            rv[4] = rv[5] = P(0, 0, ridge)
            return [rv[:5]], [[(0, 1, 4), (1, 2, 4), (2, 3, 4), (3, 0, 4), (3, 2, 1, 0)]], [], []
        return [rv], [[(0, 1, 5, 4), (1, 2, 5), (2, 3, 4, 5), (3, 0, 4), (3, 2, 1, 0)]], [], []
    rv = [P(-hl, -hw, ze), P(hl, -hw, ze), P(hl, hw, ze), P(-hl, hw, ze),
          P(-hl, 0, ridge), P(hl, 0, ridge)]
    roof = [(0, 1, 5, 4), (2, 3, 4, 5), (3, 2, 1, 0)]
    gv = [P(-L / 2, -W / 2, eave), P(-L / 2, W / 2, eave), P(-L / 2, 0, ridge),
          P(L / 2, -W / 2, eave), P(L / 2, W / 2, eave), P(L / 2, 0, ridge)]
    return [rv], [roof], [gv], [[(0, 2, 1), (3, 4, 5)]]


# ------------------------------------------------------------------ emitor trojúhelníků

class Emit:
    """Skládá trojúhelníky v herních souřadnicích Godot (x, y=výška, z=-scéna y).

    Konvence starých binů (ověřena): cross(v2-v1, v3-v1)·normála < 0
    → pro požadovanou normálu n se winding otočí tak, aby platilo <0."""

    def __init__(self):
        self.p, self.n, self.c = [], [], []

    def tri(self, a, b, c, n, col):
        a, b, c = np.asarray(a, float), np.asarray(b, float), np.asarray(c, float)
        g = np.cross(b - a, c - a)
        if g @ n < 0:
            order = (a, b, c)
        else:
            order = (a, c, b)
        nn = np.asarray(n, float)
        ln = np.linalg.norm(nn)
        nn = nn / ln if ln > 1e-12 else np.array([0, 1, 0])
        self.p.append(order)
        self.n.append([nn, nn, nn])
        self.c.append([col, col, col])

    def face(self, verts, col, inside_pt=None, up=False):
        """Konvexní face (vrcholy po obvodě, Godot souřadnice) → vějíř trojúhelníků.
        Normála z roviny face; `inside_pt` = bod uvnitř objemu budovy → normála
        ven od něj (svislé plochy jen horizontálně); `up` vynutí normálu +y."""
        if len(verts) < 3:
            return
        vs = [np.asarray(v, float) for v in verts]
        g = np.cross(vs[1] - vs[0], vs[2] - vs[1])
        ln = np.linalg.norm(g)
        if ln < 1e-9:
            return
        g = g / ln
        if inside_pt is not None:
            fc = np.mean(vs, axis=0)
            d = fc - np.asarray(inside_pt, float)
            if abs(g[1]) < 0.3:            # svislá plocha → jen horizontální směr
                d[1] = 0.0
            if np.linalg.norm(d) > 1e-6 and g @ d < 0:
                g = -g
        if up and g[1] < 0:
            g = -g
        for i in range(1, len(vs) - 1):
            self.tri(vs[0], vs[i], vs[i + 1], g, col)

    def arrays(self):
        return (np.array(self.p, np.float32).reshape(-1, 3, 3),
                np.array(self.n, np.float32).reshape(-1, 3, 3),
                np.array(self.c, np.float32).reshape(-1, 3, 3))


def scene_to_godot(v):
    """(x, y_scéna, z_výška) → Godot (x, výška, -y)."""
    return (v[0], v[2], -v[1])


# ------------------------------------------------------------------ samplování mřížek

class Grid:
    """Bilineární vzorkování herní mřížky terrain_height.bin (x,z)."""

    def __init__(self, arr, x0, z0, sp):
        self.a, self.x0, self.z0, self.sp = arr, x0, z0, sp

    def at(self, x, z):
        a = self.a
        fx = np.clip((np.asarray(x, float) - self.x0) / self.sp, 0, a.shape[1] - 1.001)
        fz = np.clip((np.asarray(z, float) - self.z0) / self.sp, 0, a.shape[0] - 1.001)
        ix, iz = np.floor(fx).astype(int), np.floor(fz).astype(int)
        tx, tz = fx - ix, fz - iz
        p, q = a[iz, ix], a[iz, ix + 1]
        r, s = a[iz + 1, ix], a[iz + 1, ix + 1]
        return (p * (1 - tx) + q * tx) * (1 - tz) + (r * (1 - tx) + s * tx) * tz


class Dem:
    """Scénové rastry (dtm/dsm union): řádek od severu, středy px na +0.5."""

    def __init__(self, arr, gx0, gy1, res):
        self.a, self.x0, self.y1, self.res = arr, gx0, gy1, res

    def at(self, x, y):
        r = (self.y1 - np.asarray(y)) / self.res - 0.5
        c = (np.asarray(x) - self.x0) / self.res - 0.5
        return ndimage.map_coordinates(self.a, [np.atleast_1d(r), np.atleast_1d(c)],
                                       order=1, mode="nearest")


# ------------------------------------------------------------------ dedup rastr

def build_old_mask(old_roofs, old_walls):
    """Rastr půdorysů starých budov (střechy+zdi) na 1 m – pro dedup překryvem."""
    xz = np.concatenate([old_roofs[:, :, [0, 2]], old_walls[:, :, [0, 2]]]).reshape(-1, 3, 2)
    x0, z0 = xz.reshape(-1, 2).min(0) - 3.0
    x1, z1 = xz.reshape(-1, 2).max(0) + 3.0
    w, h = int(x1 - x0) + 1, int(z1 - z0) + 1
    img = Image.new("L", (w, h), 0)
    dr = ImageDraw.Draw(img)
    for t in xz:
        dr.polygon([(v[0] - x0, v[1] - z0) for v in t], fill=1)
    m = np.array(img, bool)
    m = ndimage.binary_dilation(m, iterations=1)   # ~1 m tolerance na hranách
    return {"mask": m, "x0": float(x0), "z0": float(z0),
            "sx0": float(x0), "sx1": float(x1), "sy0": float(-z1), "sy1": float(-z0)}


def poly_mask_frac(poly_xz, mask, x0, z0):
    """Podíl půdorysu (scéna pts → game xz) krytého rastrem mask (1 m buňky)."""
    xs = [p[0] for p in poly_xz]
    zs = [p[1] for p in poly_xz]
    j0, j1 = int(min(xs) - x0), int(max(xs) - x0) + 2
    i0, i1 = int(min(zs) - z0), int(max(zs) - z0) + 2
    if j1 <= j0 or i1 <= i0:
        return 0.0, 0
    sub_img = Image.new("L", (j1 - j0, i1 - i0), 0)
    ImageDraw.Draw(sub_img).polygon([(x - x0 - j0, z - z0 - i0) for x, z in poly_xz], fill=1)
    fp = np.array(sub_img, bool)
    area = fp.sum()
    if area == 0:
        return 0.0, 0
    c0, c1 = max(j0, 0), min(j1, mask.shape[1])
    r0, r1 = max(i0, 0), min(i1, mask.shape[0])
    if c1 <= c0 or r1 <= r0:
        return 0.0, area
    ov = fp[r0 - i0:r1 - i0, c0 - j0:c1 - j0] & mask[r0:r1, c0:c1]
    return ov.sum() / area, area


# ------------------------------------------------------------------ budovy

def gen_buildings(feats, terr, dsm, ndsm, ortho, ometa, old_ids, old_mask, g):
    """→ (walls Emit, roofs Emit, report dict)."""
    rng = np.random.default_rng(122)
    walls, roofs = Emit(), Emit()
    rep = {"osm_id_skip": 0, "exclude_skip": 0, "overlap_skip": 0, "outside_skip": 0,
           "degenerate": 0, "added": 0, "dsm": 0, "fallback": 0, "added_ids": []}
    ores = ometa["ortho_res"]

    for ft in feats:
        p = ft["properties"]
        if p.get("kind") != "building" or ft["geometry"]["type"] != "Polygon":
            continue
        ring = ft["geometry"]["coordinates"][0]
        oid = str(p.get("osm_id"))
        poly = open_ring(ring)
        if len(poly) < 3:
            rep["degenerate"] += 1
            continue
        cx = sum(q[0] for q in poly) / len(poly)
        cy = sum(q[1] for q in poly) / len(poly)
        in_grid = (g["x0"] - 2 <= cx <= g["x1"] + 2 and -g["z1"] - 2 <= cy <= -g["z0"] + 2)
        if not in_grid:
            # hrana mřížky: přidej jen když je většina půdorysu uvnitř
            ins = sum(1 for q in poly
                      if g["x0"] <= q[0] <= g["x1"] and -g["z1"] <= q[1] <= -g["z0"])
            if ins * 2 < len(poly):
                rep["outside_skip"] += 1
                continue
        if oid in old_ids["ids"]:
            rep["osm_id_skip"] += 1
            continue
        if oid in old_ids["exclude"]:
            rep["exclude_skip"] += 1
            continue
        poly = ccw(poly)
        # dedup překryvem – jen uvnitř starého pokryvného bboxu (levné; scéna souřadnice)
        if old_mask is not None:
            bxs = [q[0] for q in poly]
            bys = [q[1] for q in poly]
            if not (max(bxs) < old_mask["sx0"] or min(bxs) > old_mask["sx1"] or
                    max(bys) < old_mask["sy0"] or min(bys) > old_mask["sy1"]):
                frac, _ = poly_mask_frac([(q[0], -q[1]) for q in poly], old_mask["mask"],
                                         old_mask["x0"], old_mask["z0"])
                if frac >= DUP_FRAC:
                    rep["overlap_skip"] += 1
                    continue

        # ---------- výšky: nDSM fit (vzor phase12), fallback OSM tagy
        xs = [q[0] for q in poly]
        ys = [q[1] for q in poly]
        bx_, by_ = [], []
        for i in range(len(poly)):
            (x1, y1), (x2, y2) = poly[i], poly[(i + 1) % len(poly)]
            k = max(2, int(math.hypot(x2 - x1, y2 - y1)))
            bx_ += list(np.linspace(x1, x2, k, endpoint=False))
            by_ += list(np.linspace(y1, y2, k, endpoint=False))
        # pata zdí a okapová hladina z VIZUÁLNÍ mřížky (to, co hráč vidí)
        gz = terr.at(np.asarray(bx_), -np.asarray(by_))
        base_z, ground = float(gz.min()) - 1.0, float(np.median(gz))
        gxs, gys = np.meshgrid(np.arange(min(xs), max(xs), 0.5) + 0.25,
                               np.arange(min(ys), max(ys), 0.5) + 0.25)
        gxs, gys = gxs.ravel(), gys.ravel()
        ins_ = pip(gxs, gys, poly)
        gxs, gys = gxs[ins_], gys[ins_]
        dd = dist_to_edges(gxs, gys, poly)
        core = dd >= 0.6
        if core.sum() < 8:
            core = dd >= 0.2
        px, py = gxs[core], gys[core]
        rect = mar(poly)
        ndv = ndsm.at(px, py) if len(px) else np.array([0.0])
        if len(px) >= 6 and np.median(ndv) > 1.8:
            h = dsm.at(px, py) - H_REF
            fit = fit_roof(px, py, h, rect)
            if fit["ridge_p90"] - ground > 30:      # nesmysl (stožár/strom) – omez
                fit["ridge_p90"] = fit["ridge_z"] = ground + 30
            shape, eave, ridge = roof_from_fit(fit, rect, ground, p.get("building", "yes"))
            rep["dsm"] += 1
        else:
            lv = p.get("building:levels")
            try:
                lv = float(lv)
            except (TypeError, ValueError):
                lv = None
            small = p.get("building") in {"garage", "garages", "shed", "carport"}
            wall = 2.6 if small else (lv * 2.9 if lv else 3.5)
            L, W = rect[2], rect[3]
            rise = 0.0 if small else (W / 2) * math.tan(math.radians(38))
            shape = "flat" if small else "gable_long"
            eave, ridge = ground + wall, ground + wall + rise
            rep["fallback"] += 1
        # pojistky – degenerace/artefakty DMP
        eave = min(max(eave, base_z + 2.2), ground + 25.0)
        ridge = min(max(ridge, eave), ground + 35.0)

        # ---------- barvy (stejné zdroje jako phase12/13)
        if len(px):
            rr_ = np.clip(np.round((ometa["y1"] - py) / ores - 0.5).astype(int), 0,
                          ortho.shape[0] - 1)
            cc_ = np.clip(np.round((px - ometa["x0"]) / ores - 0.5).astype(int), 0,
                          ortho.shape[1] - 1)
            col_r = np.median(ortho[rr_, cc_], axis=0) / 255.0
        else:
            col_r = np.array([0.5, 0.3, 0.25])
        rcol = tuple(srgb_to_lin(np.clip(col_r * 1.08, 0, 1)))
        fac = tuple(srgb_to_lin(FACADE_TINTS[int(rng.integers(len(FACADE_TINTS)))]))

        # ---------- geometrie
        k = len(poly)
        inside = (cx, (base_z + eave) / 2, -cy)          # bod uvnitř objemu (Godot)
        # zdi – čtyřstěn base→eave na každé hraně; normála = vnější normála hrany
        for i in range(k):
            j = (i + 1) % k
            ex, ey = poly[j][0] - poly[i][0], poly[j][1] - poly[i][1]
            if math.hypot(ex, ey) < MIN_EDGE:
                continue
            n_out = np.array([ey, 0.0, ex])              # scéna (dy,-dx) → Godot (dy,0,dx)
            n_out /= np.linalg.norm(n_out) or 1.0
            quad = [scene_to_godot((poly[i][0], poly[i][1], base_z)),
                    scene_to_godot((poly[j][0], poly[j][1], base_z)),
                    scene_to_godot((poly[j][0], poly[j][1], eave)),
                    scene_to_godot((poly[i][0], poly[i][1], eave))]
            walls.tri(quad[0], quad[1], quad[2], n_out, fac)
            walls.tri(quad[0], quad[2], quad[3], n_out, fac)

        if shape == "flat" or ridge - eave < 0.3:
            top = [(q[0], q[1], eave + 0.15) for q in poly]
            bot = [(q[0], q[1], eave) for q in poly]
            for i0, i1, i2 in earclip(poly):
                tri = [scene_to_godot(top[i0]), scene_to_godot(top[i1]),
                       scene_to_godot(top[i2])]
                roofs.face(tri, rcol, up=True)
            for i in range(k):
                j = (i + 1) % k
                if math.hypot(poly[j][0] - poly[i][0], poly[j][1] - poly[i][1]) < MIN_EDGE:
                    continue
                quad = [scene_to_godot(top[i]), scene_to_godot(top[j]),
                        scene_to_godot(bot[j]), scene_to_godot(bot[i])]
                roofs.face(quad, rcol, inside_pt=inside)
        else:
            rv, rf, gv, gf = roof_parts(rect, eave, ridge, shape)
            for vv, ff in zip(rv, rf):
                for fc in ff:
                    roofs.face([scene_to_godot(vv[q]) for q in fc], rcol, inside_pt=inside)
            for vv, ff in zip(gv, gf):
                for fc in ff:
                    walls.face([scene_to_godot(vv[q]) for q in fc], fac, inside_pt=inside)
        rep["added"] += 1
        rep["added_ids"].append(oid)
    return walls, roofs, rep


# ------------------------------------------------------------------ silnice

def gen_roads(feats, terr, admin, g):
    """→ (asphalt Emit, gravel Emit, report dict). Silnice ve scénových souřadnicích;
    drží se body mimo katastr a >ADMIN_BUFFER−ROAD_OVERLAP_IN od hranice."""

    sx0, sx1 = g["x0"] + GRID_MARGIN, g["x1"] - GRID_MARGIN
    sy0, sy1 = -g["z1"] + GRID_MARGIN, -g["z0"] - GRID_MARGIN   # scéna y = −godot z

    def keep_mask(arr):
        """arr (n,2) scéna → bool maska: uvnitř mřížky −margin a MIMO staré pokrytí."""
        xs, ys = arr[:, 0], arr[:, 1]
        inside_grid = (xs >= sx0) & (xs <= sx1) & (ys >= sy0) & (ys <= sy1)
        old = pip(xs, ys, admin) | \
            (dist_to_edges(xs, ys, admin) < ADMIN_BUFFER - ROAD_OVERLAP_IN)
        return inside_grid & ~old

    bufs = {"asfalt": Emit(), "strk": Emit()}
    rep = {"roads_in": 0, "runs": 0, "new_km": {"asfalt": 0.0, "strk": 0.0},
           "kinds": {}}
    for ft in feats:
        p = ft["properties"]
        if p.get("kind") != "highway" or ft["geometry"]["type"] != "LineString":
            continue
        hw = p.get("highway")
        w = ROAD_W.get(hw)
        if w is None:
            continue                            # steps/raceway/bridleway/construction
        kind = "strk" if hw in {"track", "path"} and \
            p.get("surface") not in {"asphalt", "paved", "concrete"} else "asfalt"
        raw = []
        for c in ft["geometry"]["coordinates"]:
            if not raw or math.hypot(c[0] - raw[-1][0], c[1] - raw[-1][1]) > 1e-3:
                raw.append(tuple(c))
        if len(raw) < 2:
            continue
        rep["roads_in"] += 1
        dens = np.asarray(densify(raw))
        mask = keep_mask(dens)
        # rozdělení na souvislé běží držených bodů (≥2 body)
        parts, cur = [], []
        for pt, kp in zip(dens, mask):
            if kp:
                cur.append(tuple(pt))
            elif cur:
                if len(cur) >= 2:
                    parts.append(cur)
                cur = []
        if len(cur) >= 2:
            parts.append(cur)
        for part in parts:
            # kumulativní vzdálenost → zúžení konců na špici (navázání na starý pás)
            s = [0.0]
            for i in range(1, len(part)):
                s.append(s[-1] + math.hypot(part[i][0] - part[i - 1][0],
                                            part[i][1] - part[i - 1][1]))
            L = s[-1]
            left, right = [], []
            for i in range(len(part)):
                a = part[max(i - 1, 0)]
                b = part[min(i + 1, len(part) - 1)]
                dx, dy = b[0] - a[0], b[1] - a[1]
                ln = math.hypot(dx, dy) or 1
                wi = w * min(1.0, s[i] / ROAD_TAPER, (L - s[i]) / ROAD_TAPER)
                nx, ny = -dy / ln * wi / 2, dx / ln * wi / 2
                left.append((part[i][0] + nx, part[i][1] + ny))
                right.append((part[i][0] - nx, part[i][1] - ny))
            P = np.array(part)
            Lp, Rp = np.array(left), np.array(right)
            # výška jen pro úplnost (ve hře se pás stejně drape na terén)
            z = np.maximum.reduce([terr.at(P[:, 0], -P[:, 1]),
                                   terr.at(Lp[:, 0], -Lp[:, 1]),
                                   terr.at(Rp[:, 0], -Rp[:, 1])]) + 0.06
            kk = len(part)
            for i in range(kk - 1):
                quad = [scene_to_godot((Lp[i, 0], Lp[i, 1], z[i])),
                        scene_to_godot((Lp[i + 1, 0], Lp[i + 1, 1], z[i + 1])),
                        scene_to_godot((Rp[i + 1, 0], Rp[i + 1, 1], z[i + 1])),
                        scene_to_godot((Rp[i, 0], Rp[i, 1], z[i]))]
                bufs[kind].face(quad, (1.0, 1.0, 1.0), up=True)
            rep["runs"] += 1
            rep["new_km"][kind] += L / 1000.0
            rep["kinds"][hw] = rep["kinds"].get(hw, 0) + 1
    return bufs["asfalt"], bufs["strk"], rep


# ------------------------------------------------------------------ main

def main():
    args = {a.split("=")[0].lstrip("-"): (a.split("=")[1] if "=" in a else "")
            for a in sys.argv[1:]}
    limit = int(args.get("limit", 0))
    report_only = "report-only" in args

    pe = backup_pre_b3()
    g = json.load(open(os.path.join(DATA, "map.json"), encoding="utf-8"))["height"]
    g["x1"] = g["x0"] + (g["w"] - 1) * g["spacing"]
    g["z1"] = g["z0"] + (g["h"] - 1) * g["spacing"]
    mu = json.load(open(os.path.join(PDATA, "geodata_meta_union.json")))
    admin = [tuple(p) for p in
             json.load(open(os.path.join(PDATA, "doubravy_admin_boundary.json")))["scene_poly"]]

    feats = json.load(open(os.path.join(PDATA, "okoli_union_local.geojson")))["features"]

    # staré chunky (ze snapshotu – deterministické i při re-run)
    old = {fn: read_dbm(os.path.join(pe, fn)) for fn in BINS}
    for fn in BINS:
        print(f"OLD {fn}: {len(old[fn][0])} tris")

    # terén (vizuální mřížka = to, co hráč vidí a na co se drape)
    hm = np.fromfile(os.path.join(DATA, "terrain_height.bin"), np.float32) \
        .reshape(int(g["h"]), int(g["w"]))
    terr = Grid(hm, g["x0"], g["z0"], g["spacing"])

    # ---------- dedup sada + rastr starých půdorysů
    old_ids = {"ids": set(), "exclude": set()}
    for fn in ("buildings_3d.json", "buildings_3d_full.json"):
        for b in json.load(open(os.path.join(PDATA, fn))):
            old_ids["ids"].add(str(b["osm_id"]))
    ref = json.load(open(os.path.join(PDATA, "scene_reference.json")))
    for eid in ref.get("exclude_osm_ids", []):
        old_ids["exclude"].add(str(eid).split("/")[-1])
    print(f"dedup: {len(old_ids['ids'])} starých osm_id, exclude {sorted(old_ids['exclude'])}")
    old_mask = build_old_mask(old["roofs.bin"][0], old["walls.bin"][0])

    # ---------- budovy
    dtm = np.load(os.path.join(GEO, "dtm_union_scene.npy")).astype(np.float64)
    dsm = np.load(os.path.join(GEO, "dsm_union_scene.npy")).astype(np.float64)
    ndsm_arr = dsm - dtm
    dsm_d = Dem(dsm, mu["grid_x0"], mu["grid_y1"], mu["dem_res"])
    ndsm_d = Dem(ndsm_arr, mu["grid_x0"], mu["grid_y1"], mu["dem_res"])
    ortho = np.asarray(Image.open(os.path.join(GEO, "ortho_union_scene.jpg")).convert("RGB"))
    ometa = {"x0": mu["grid_x0"], "y1": mu["grid_y1"], "ortho_res": mu["ortho_res"]}
    b_feats = [f for f in feats
               if f["properties"].get("kind") == "building"
               and f["geometry"]["type"] == "Polygon"]
    if limit:
        b_feats = b_feats[:limit]
    w_new, r_new, brep = gen_buildings(b_feats, terr, dsm_d, ndsm_d, ortho,
                                       ometa, old_ids, old_mask, g)
    print(f"BUILDINGS: added={brep['added']} (nDSM {brep['dsm']}, fallback {brep['fallback']}), "
          f"skip: osm_id={brep['osm_id_skip']} exclude={brep['exclude_skip']} "
          f"overlap={brep['overlap_skip']} outside={brep['outside_skip']} "
          f"degenerate={brep['degenerate']}")

    # ---------- silnice
    a_new, gr_new, rrep = gen_roads(feats, terr, admin, g)
    print(f"ROADS: {rrep['roads_in']} lines in → {rrep['runs']} runs "
          f"(asfalt {rrep['new_km']['asfalt']:.1f} km, štěrk {rrep['new_km']['strk']:.1f} km), "
          f"kinds={rrep['kinds']}")

    wn, wr, wc = w_new.arrays()
    rn, rr, rc = r_new.arrays()
    an, ar, ac = a_new.arrays()
    gn, gr_, gc = gr_new.arrays()
    print(f"NEW tris: walls {len(wn)}, roofs {len(rn)}, asphalt {len(an)}, gravel {len(gn)}")

    if report_only:
        json.dump(brep, open(os.path.join(PDATA, "expand_b3_report.json"), "w"), indent=1)
        return

    # ---------- merge + re-tile + zápis
    merged = {
        "walls.bin": (np.concatenate([old["walls.bin"][0], wn]),
                      np.concatenate([old["walls.bin"][1], wr]),
                      np.concatenate([old["walls.bin"][2], wc])),
        "roofs.bin": (np.concatenate([old["roofs.bin"][0], rn]),
                      np.concatenate([old["roofs.bin"][1], rr]),
                      np.concatenate([old["roofs.bin"][2], rc])),
        "asphalt.bin": (np.concatenate([old["asphalt.bin"][0], an]),
                        np.concatenate([old["asphalt.bin"][1], ar]),
                        np.concatenate([old["asphalt.bin"][2], ac])),
        "gravel.bin": (np.concatenate([old["gravel.bin"][0], gn]),
                       np.concatenate([old["gravel.bin"][1], gr_]),
                       np.concatenate([old["gravel.bin"][2], gc])),
    }
    for fn, (P, N, C) in merged.items():
        assert not np.isnan(P).any(), f"NaN v {fn}"
        assert np.isfinite(P).all() and np.isfinite(N).all() and np.isfinite(C).all()
        write_chunked(os.path.join(DATA, fn), P, N, C)

    # ---------- konzistenční kontroly
    print("\n=== KONTROLY ===")
    new_wall_xz = wn[:, :, [0, 2]].reshape(-1, 3, 2)
    if len(new_wall_xz) and old_mask is not None:
        # žádný nový trojúhelník se nesmí výrazně překrývat starým půdorysem
        cen = new_wall_xz.mean(axis=1)
        mx, mz = old_mask["x0"], old_mask["z0"]
        i = np.clip((cen[:, 1] - mz).astype(int), 0, old_mask["mask"].shape[0] - 1)
        j = np.clip((cen[:, 0] - mx).astype(int), 0, old_mask["mask"].shape[1] - 1)
        inside = old_mask["mask"][i, j]
        print(f"nové wall tris s centroidem ve starém půdorysu: {inside.sum()}/{len(cen)} "
              "(čeká se ~0 – stěny na hraně deduplikovaných budov mohou ležet těsně u sebe)")
    print(f"nových budov: {brep['added']}, nové pásy: asfalt {rrep['new_km']['asfalt']:.1f} km "
          f"+ štěrk {rrep['new_km']['strk']:.1f} km")
    brep["road_km"] = rrep["new_km"]
    brep["road_runs"] = rrep["runs"]
    brep["road_kinds"] = rrep["kinds"]
    json.dump(brep, open(os.path.join(PDATA, "expand_b3_report.json"), "w"), indent=1)
    print("report → pipeline/data/expand_b3_report.json")
    print("\nDALŠÍ KROK: zkopíruj data/{walls,roofs,asphalt,gravel,trees}.bin do data/orig/ "
          "a spusť tools/clean_road_clashes.py")


if __name__ == "__main__":
    main()
