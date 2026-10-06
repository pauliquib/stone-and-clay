#!/usr/bin/env python3
"""Odstraní z herních dat budovy a stromy, které stojí ve vozovce.

Ve zdrojové mapě jsou místy chybně umístěné objekty: malé budovy (kůlny, garáže) pootočené
o 45° nebo posunuté doprostřed silnice a stromy s kmenem na asfaltu. Na ortofotu tam nic
není – silnice (síť asfaltu a cest z exportu) naopak s ortofotem sedí. Auta (hráč i AI)
do takových objektů narážejí a zasekávají se.

Postup:
  1. rastr vozovky 0,5 m z trojúhelníků data/orig/asphalt.bin + gravel.bin,
  2. budovy = souvislé komponenty trojúhelníků stěn a střech (sdílené vrcholy),
     půdorys = průmět střechy; „hloubka“ = jak daleko uvnitř půdorysu leží vozovka
     (distanční transformace od okraje půdorysu),
  3. budova se vyřadí, když vozovka pokrývá ≥ FRAC půdorysu, nebo sahá ≥ DEPTH_M dovnitř
     na ploše ≥ MIN_OV_M2 (obyčejný dům u silnice má překryv nanejvýš v úzkém pruhu u fasády),
  4. ručně vyřazené budovy z `REMOVE_BUILDINGS` (půdorys v herních souřadnicích) – artefakty,
     které pravidlo vozovky pod prahem neodchytí; fasády/interiér z nich maže `EXCLUDE`
     v tools/buildings.py,
  5. duplicitní budovy: dvě budovy, jejichž půdorysy se kryjí z ≥ DUP_FRAC menší z nich
     (typicky na hranici jádra a rozšíření mapy) → menší se vyřadí,
  6. budova se vyřadí, když její půdorys zasahuje do pásu kolem OSY silnice z data/map.json
     (`AXIS_BUF` podle druhu silnice) na ploše ≥ AXIS_MIN_M2 – síť asfaltu je místy užší než
     skutečná silnice, takže dům 0,8–2 m od osy pravidlo vozovky (3.) neodchytí, ale AI auta
     v pruhu (1–1,6 m od osy) do něj narážejí. Účelové cesty (service) jsou často skutečné
     vjezdy do dvorů a garáží: pás je úzký a konce cest (`SERVICE_END_M`) se nepočítají.
     Budovy s místem (`poi`) a dům hráče (`home`) z data/buildings.json se nevyřazují – jen
     se vypíšou k ruční kontrole,
  7. strom se vyřadí, když je jeho kmen na vozovce nebo blíž ose silnice než `TREE_AXIS_BUF`,
  8. z data/buildings.json (fasády, nemovitosti) se vyřadí záznamy vyřazených budov
     (jejich id se vypíšou – patří do `EXCLUDE` v tools/buildings.py, aby přežily přegenerování).

Čte vždy z data/orig/ (při prvním spuštění se tam originály zkopírují), zapisuje do data/ →
lze spouštět opakovaně. Spouští se po tools/export_map.py:

    python3 tools/clean_road_clashes.py
"""
import json
import os
import shutil
import struct
import sys

import numpy as np
from scipy import ndimage

HERE = os.path.dirname(os.path.abspath(__file__))
DATA = os.path.join(HERE, "..", "data")
ORIG = os.path.join(DATA, "orig")
RES = 0.5            # m na buňku rastru
DEPTH_M = 1.0        # vozovka sahá aspoň 1 m dovnitř půdorysu…
MIN_OV_M2 = 2.0      # …na ploše aspoň 2 m² (síť silnic sedí na ortofotu – správně umístěný dům
                     # do ní nikdy nezasahuje o metr; takové jsou pootočené / posunuté)
FRAC = 0.3           # nebo pokrývá aspoň 30 % půdorysu
DUP_FRAC = 0.5       # dvě budovy se kryjí z ≥ 50 % menší z nich
CHUNK = 256.0
# pás kolem osy silnice (m od osy), do kterého dům nesmí zasahovat (bod 6) – pruh AI je 1,0 m
# (residential) / 1,6 m (secondary, tertiary) od osy, auto je ~1,8 m široké
AXIS_BUF = {"secondary": 2.6, "tertiary": 2.6, "unclassified": 2.0, "residential": 2.0,
            "living_street": 2.0, "service": 0.75}
AXIS_MIN_M2 = 1.0        # zásah půdorysu do pásu aspoň 1 m² (dotyk rohem se nepočítá)
SERVICE_MIN_M2 = 2.0     # u service: osa vede půdorysem aspoň ~2 m (průjezd, ne konec vjezdu)
SERVICE_END_M = 4.0      # posledních 4 m na koncích service cesty se nepočítá (vjezd do garáže / dvora)
TREE_AXIS_BUF = {"secondary": 2.3, "tertiary": 2.3, "unclassified": 1.7, "residential": 1.7,
                 "living_street": 1.7}
NEAR_REPORT_M = 2.0      # budovy blíž ose, které pravidlo nevyřadí, se vypíšou k ruční kontrole
SEG_CELL = 32.0          # m – mřížka pro hledání úseků osy u budovy
FILES = ["walls.bin", "roofs.bin", "trees.bin", "asphalt.bin", "gravel.bin"]

# Ručně vyřazené budovy: popis + půdorys v herních souřadnicích (x, z) – artefakty podkladů,
# které čistič pod prahem neodchytí (malý překryv vozovky), nebo po kterých zbyla torza
# (samotné zdi bez střechy). Půdorys je uvedený přímo, ať jde o data nezávislá na buildings.json.
REMOVE_BUILDINGS = [
    # kůlna z DMP (dmp_176, 133 m²) uprostřed silnice obchod ↔ úřad – na ortofotu ani v OSM není
    ("dmp_176 – kůlna uprostřed silnice obchod ↔ úřad",
     [[98.07, 309.18], [107.57, 299.68], [100.57, 292.68], [91.07, 302.18]]),
]


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


def write_dbm(path, pos, nrm, col):
    """Stejné dělení na dlaždice jako export_map.write_chunked."""
    cen = pos.mean(axis=1)
    kx = np.floor(cen[:, 0] / CHUNK).astype(int)
    kz = np.floor(cen[:, 2] / CHUNK).astype(int)
    keys = sorted(set(zip(kx.tolist(), kz.tolist())))
    with open(path, "wb") as f:
        f.write(b"DBM1")
        f.write(struct.pack("<i", len(keys)))
        for a, c in keys:
            sel = (kx == a) & (kz == c)
            p = pos[sel].reshape(-1, 3).astype("<f4")
            f.write(struct.pack("<i", len(p)))
            f.write(p.tobytes())
            f.write(nrm[sel].reshape(-1, 3).astype("<f4").tobytes())
            f.write(col[sel].reshape(-1, 3).astype("<f4").tobytes())


class Grid:
    def __init__(self, x0, z0, x1, z1):
        self.x0, self.z0 = x0, z0
        self.w = int(np.ceil((x1 - x0) / RES)) + 1
        self.h = int(np.ceil((z1 - z0) / RES)) + 1

    def ij(self, x, z):
        return ((np.asarray(z) - self.z0) / RES).astype(int), ((np.asarray(x) - self.x0) / RES).astype(int)


def raster_tris(tris_xz, h, w, x0, z0):
    """Vyplní trojúhelníky (n, 3, 2) do bool rastru h×w (středy buněk)."""
    out = np.zeros((h, w), bool)
    for t in tris_xz:
        (ax, az), (bx, bz), (cx, cz) = t
        i0 = max(int((min(az, bz, cz) - z0) / RES), 0)
        i1 = min(int((max(az, bz, cz) - z0) / RES) + 1, h - 1)
        j0 = max(int((min(ax, bx, cx) - x0) / RES), 0)
        j1 = min(int((max(ax, bx, cx) - x0) / RES) + 1, w - 1)
        if i1 < i0 or j1 < j0:
            continue
        zz, xx = np.mgrid[i0:i1 + 1, j0:j1 + 1]
        px = x0 + (xx + 0.5) * RES
        pz = z0 + (zz + 0.5) * RES
        d1 = (px - bx) * (az - bz) - (ax - bx) * (pz - bz)
        d2 = (px - cx) * (bz - cz) - (bx - cx) * (pz - cz)
        d3 = (px - ax) * (cz - az) - (cx - ax) * (pz - az)
        neg = (d1 < 0) | (d2 < 0) | (d3 < 0)
        pos = (d1 > 0) | (d2 > 0) | (d3 > 0)
        out[i0:i1 + 1, j0:j1 + 1] |= ~(neg & pos)
    return out


def points_in_poly(pts, poly):
    """Body (n, 2) → bool maska uvnitř polygonu (paprskový test)."""
    x, y = pts[:, 0], pts[:, 1]
    inn = np.zeros(len(pts), bool)
    j = len(poly) - 1
    for i in range(len(poly)):
        xi, zi = poly[i]
        xj, zj = poly[j]
        m = (zi > y) != (zj > y)
        inn ^= m & (x < (xj - xi) * (y - zi) / (zj - zi + 1e-12) + xi)
        j = i
    return inn


def components(tris):
    """Souvislé komponenty trojúhelníků přes sdílené vrcholy (zaokrouhleno na 5 cm)."""
    v = np.round(tris.reshape(-1, 3) / 0.05).astype(np.int64)
    _, vid = np.unique(v, axis=0, return_inverse=True)
    vid = vid.reshape(-1, 3)
    parent = np.arange(vid.max() + 1)

    def find(a):
        while parent[a] != a:
            parent[a] = parent[parent[a]]
            a = parent[a]
        return a

    for a, b, c in vid:
        ra, rb, rc = find(a), find(b), find(c)
        parent[rb] = ra
        parent[find(rc)] = ra
    roots = np.array([find(a) for a in vid[:, 0]])
    _, comp = np.unique(roots, return_inverse=True)
    return comp


def attach_walls(both, comp, n_w, g, x0, z0):
    has_roof = np.zeros(comp.max() + 1, bool)
    has_roof[comp[n_w:]] = True
    label = np.zeros((g.h, g.w), np.int32)      # 0 = nic, jinak komponenta střechy + 1
    for ci in np.where(has_roof)[0]:
        xz = both[np.where(comp == ci)[0]][:, :, [0, 2]]
        (bx0, bz0), (bx1, bz1) = xz.reshape(-1, 2).min(0), xz.reshape(-1, 2).max(0)
        i0, j0 = g.ij(bx0, bz0)
        i1, j1 = g.ij(bx1, bz1)
        fp = raster_tris(xz, i1 - i0 + 1, j1 - j0 + 1, x0 + j0 * RES, z0 + i0 * RES)
        label[i0:i1 + 1, j0:j1 + 1][fp] = ci + 1
    out = comp.copy()
    lost = 0
    for ci in np.where(~has_roof)[0]:
        sel = np.where(comp == ci)[0]
        pts = both[sel].reshape(-1, 3)[:, [0, 2]]
        i, j = g.ij(pts[:, 0], pts[:, 1])
        votes = []
        for di in (-2, -1, 0, 1, 2):          # stěna leží na okraji půdorysu (±1 m)
            for dj in (-2, -1, 0, 1, 2):
                ii = np.clip(i + di, 0, g.h - 1)
                jj = np.clip(j + dj, 0, g.w - 1)
                votes.append(label[ii, jj])
        v = np.concatenate(votes)
        v = v[v > 0]
        if len(v):
            out[sel] = np.bincount(v).argmax() - 1
        else:
            lost += 1
    print(f"stěny přiřazené ke střechám: {(~has_roof).sum() - lost}, bez střechy: {lost}")
    return np.unique(out, return_inverse=True)[1]


def load_axis():
    """Úseky os silnic z data/map.json → (segs (n, 4) [ax, az, bx, bz], kind (n,), hash {(cx, cz): [indexy]}).
    Service cesty se zkrátí o SERVICE_END_M na obou koncích (vjezd do dvora / garáže); kratší vynechá."""
    roads = json.load(open(os.path.join(DATA, "map.json")))["roads"]
    segs, kinds, ends = [], [], []
    for rd in roads:
        k = rd.get("kind", "")
        if k not in AXIS_BUF:
            continue
        pts = np.asarray(rd["pts"], float)
        if len(pts) < 2:
            continue
        ln = np.linalg.norm(np.diff(pts, axis=0), axis=1)
        cum = np.concatenate([[0.0], np.cumsum(ln)])
        total = cum[-1]
        for i in range(len(pts) - 1):
            a, b = pts[i], pts[i + 1]
            if ln[i] < 1e-3:
                continue
            if k == "service" and total > 2.0 * SERVICE_END_M:
                # konce service cesty vynechat: úsek se zkrátí na střední část (vjezd do dvora / garáže)
                t0 = max(SERVICE_END_M - cum[i], 0.0) / ln[i]
                t1 = 1.0 - max(cum[i + 1] - (total - SERVICE_END_M), 0.0) / ln[i]
                if t1 <= t0:
                    continue
                a, b = pts[i] + (pts[i + 1] - pts[i]) * t0, pts[i] + (pts[i + 1] - pts[i]) * t1
            elif k == "service":
                continue          # krátká service cesta = celá je vjezd
            segs.append([a[0], a[1], b[0], b[1]])
            kinds.append(k)
    segs = np.asarray(segs, float).reshape(-1, 4)
    hsh = {}
    for i, (ax, az, bx, bz) in enumerate(segs):
        for cx in range(int(np.floor(min(ax, bx) / SEG_CELL)), int(np.floor(max(ax, bx) / SEG_CELL)) + 1):
            for cz in range(int(np.floor(min(az, bz) / SEG_CELL)), int(np.floor(max(az, bz) / SEG_CELL)) + 1):
                hsh.setdefault((cx, cz), []).append(i)
    return segs, np.asarray(kinds), hsh


def segs_near(hsh, x0, z0, x1, z1):
    out = set()
    for cx in range(int(np.floor(x0 / SEG_CELL)), int(np.floor(x1 / SEG_CELL)) + 1):
        for cz in range(int(np.floor(z0 / SEG_CELL)), int(np.floor(z1 / SEG_CELL)) + 1):
            out.update(hsh.get((cx, cz), ()))
    return np.fromiter(out, int, len(out))


def seg_dist(px, pz, segs):
    """Vzdálenost bodů (m,) k úsekům (n, 4) → (m, n)."""
    ax, az, bx, bz = (segs[:, i][None, :] for i in range(4))
    dx, dz = bx - ax, bz - az
    t = np.clip(((px[:, None] - ax) * dx + (pz[:, None] - az) * dz) / (dx * dx + dz * dz), 0.0, 1.0)
    return np.hypot(px[:, None] - (ax + t * dx), pz[:, None] - (az + t * dz))


def axis_clash(fp, x0c, z0c, segs, kinds, hsh):
    """Půdorys (bool rastr s rohem buňky [0, 0] v (x0c, z0c)) proti pásům os silnic.
    Vrací (zasáhne, popis, min. vzdálenost od osy)."""
    ii, jj = np.nonzero(fp)
    px = x0c + (jj + 0.5) * RES
    pz = z0c + (ii + 0.5) * RES
    m = max(AXIS_BUF.values()) + 0.5
    idx = segs_near(hsh, px.min() - m, pz.min() - m, px.max() + m, pz.max() + m)
    if len(idx) == 0:
        return False, "", 99.0
    d = seg_dist(px, pz, segs[idx])
    kk = kinds[idx]
    buf = np.array([AXIS_BUF[k] for k in kk])
    for k in sorted(set(kk.tolist())):
        cols = kk == k
        inside = (d[:, cols] < buf[cols][None, :]).any(1)
        m2 = inside.sum() * RES * RES
        need = SERVICE_MIN_M2 if k == "service" else AXIS_MIN_M2
        if m2 >= need:
            dk = float(d[:, cols].min())
            return True, "%.1f m od osy (%s, pás %.1f m), v pásu %.1f m²" % (dk, k, AXIS_BUF[k], m2), dk
    return False, "", float(d.min())


def load_details():
    """data/buildings.json (fasády, nemovitosti) – None, když chybí."""
    path = os.path.join(DATA, "buildings.json")
    if not os.path.exists(path):
        return None
    return json.load(open(path))


def detail_at(details, x, z):
    """Záznam z buildings.json, jehož půdorys obsahuje bod (x, z) (střed budovy z geometrie)."""
    if not details:
        return None
    pt = np.array([[x, z]])
    for b in details:
        poly = b.get("poly", [])
        if len(poly) >= 3 and points_in_poly(pt, poly)[0]:
            return b
    return None


def main():
    os.makedirs(ORIG, exist_ok=True)
    for f in FILES:
        if not os.path.exists(os.path.join(ORIG, f)):
            shutil.copy2(os.path.join(DATA, f), os.path.join(ORIG, f))
    wp, wn, wc = read_dbm(os.path.join(ORIG, "walls.bin"))
    rp, rn, rc = read_dbm(os.path.join(ORIG, "roofs.bin"))
    road = np.concatenate([read_dbm(os.path.join(ORIG, "asphalt.bin"))[0],
                           read_dbm(os.path.join(ORIG, "gravel.bin"))[0]])
    allxz = np.concatenate([wp.reshape(-1, 3), rp.reshape(-1, 3), road.reshape(-1, 3)])[:, [0, 2]]
    x0, z0 = allxz.min(0) - 2.0
    x1, z1 = allxz.max(0) + 2.0
    g = Grid(x0, z0, x1, z1)
    print(f"rastr vozovky {g.w}×{g.h} buněk ({RES} m)…", flush=True)
    road_mask = raster_tris(road[:, :, [0, 2]], g.h, g.w, x0, z0)

    # budovy: stěny + střechy; komponenty přes sdílené vrcholy, stěny bez společného vrcholu se
    # střechou se přiřadí ke střeše, pod kterou leží
    both = np.concatenate([wp, rp])
    comp = components(both)
    n_w = len(wp)
    comp = attach_walls(both, comp, n_w, g, x0, z0)
    removed = []
    axis_removed = []        # bod 6 – zásah do pásu kolem osy silnice
    protected = []           # zasahují do pásu, ale jsou to místa / dům hráče → jen výpis
    near = []                # blízko osy, ale pod prahem (dotyk rohem) → jen výpis k ruční kontrole
    segs, kinds, hsh = load_axis()
    details = load_details()
    print(f"osy silnic: {len(segs)} úseků, buildings.json: {len(details) if details else 0} budov")
    keep_tri = np.ones(len(both), bool)
    fps = []    # (ci, i0, j0, footprint) pro hledání duplicit
    for ci in range(comp.max() + 1):
        sel = np.where(comp == ci)[0]
        roof_sel = sel[sel >= n_w]
        fp_tris = both[roof_sel] if len(roof_sel) else both[sel]
        xz = fp_tris[:, :, [0, 2]]
        bx0, bz0 = xz.reshape(-1, 2).min(0) - 1.0
        bx1, bz1 = xz.reshape(-1, 2).max(0) + 1.0
        i0, j0 = g.ij(bx0, bz0)
        i1, j1 = g.ij(bx1, bz1)
        fp = raster_tris(xz, i1 - i0 + 1, j1 - j0 + 1, x0 + j0 * RES, z0 + i0 * RES)
        area = fp.sum()
        if area == 0:
            continue
        c = xz.reshape(-1, 2).mean(0)
        fps.append((ci, i0, j0, fp, c))
        ov = fp & road_mask[i0:i1 + 1, j0:j1 + 1]
        if ov.any():
            depth = ndimage.distance_transform_edt(fp)[ov].max() * RES
            frac = ov.sum() / area
            ov_m2 = ov.sum() * RES * RES
            if frac >= FRAC or (depth >= DEPTH_M and ov_m2 >= MIN_OV_M2):
                keep_tri[sel] = False
                removed.append((c[0], c[1], area * RES * RES, "vozovka %.1f m dovnitř, %.0f m² (%d %% půdorysu)" % (
                    depth, ov_m2, frac * 100)))
                continue
        # bod 6: zásah do pásu kolem osy silnice
        hit, why, dmin = axis_clash(fp, x0 + j0 * RES, z0 + i0 * RES, segs, kinds, hsh)
        if not hit and dmin < NEAR_REPORT_M:
            near.append((c[0], c[1], area * RES * RES, dmin))
        if hit:
            det = detail_at(details, c[0], c[1])
            if det is not None and (det.get("poi") or det.get("home")):
                protected.append((c[0], c[1], area * RES * RES, why, det.get("id"), det.get("poi") or "domov"))
                continue
            keep_tri[sel] = False
            axis_removed.append((c[0], c[1], area * RES * RES, "osa silnice: " + why))
    n_axis = len(axis_removed)
    removed += axis_removed
    n_road = len(removed)
    # ručně vyřazené budovy podle půdorysu – odstraní se VŠECHNY komponenty s výrazným
    # překryvem půdorysu (budova může být torzo: zdi a střecha jako dvě komponenty)
    for bid, poly in REMOVE_BUILDINGS:
        if len(poly) < 3:
            continue
        pa = np.asarray(poly)
        bx0, bz0 = pa.min(0) - 1.0
        bx1, bz1 = pa.max(0) + 1.0
        i0, j0 = g.ij(bx0, bz0)
        i1, j1 = g.ij(bx1, bz1)
        cen = pa.mean(0)                        # vějíř z centroidu pokryje i mírně konkávní tvar
        tris = np.stack([pa, np.roll(pa, -1, axis=0),
                         np.broadcast_to(cen, pa.shape)], axis=1)
        pm = raster_tris(tris, i1 - i0 + 1, j1 - j0 + 1, x0 + j0 * RES, z0 + i0 * RES)
        hits = 0
        for ci, ia, ja, fp, c in fps:
            r0, r1 = max(ia, i0), min(ia + fp.shape[0], i1 + 1)
            c0, c1 = max(ja, j0), min(ja + fp.shape[1], j1 + 1)
            if r1 <= r0 or c1 <= c0:
                continue
            # komponenta odpovídající půdorysu: překryvá ho výrazně a má srovnatelnou plochu
            # (spodní mez kvůli torzům samotných zdí ≈ obvod; horní mez odfiltruje sousední
            # budovu, jejíž půdorys se s vyřazovanou kryje)
            fp_m2 = fp.sum() * RES * RES
            pm_m2 = pm.sum() * RES * RES
            if not (0.25 * pm_m2 <= fp_m2 <= 1.8 * pm_m2):
                continue
            inter = (fp[r0 - ia:r1 - ia, c0 - ja:c1 - ja] & pm[r0 - i0:r1 - i0, c0 - j0:c1 - j0]).sum()
            if inter >= 0.4 * fp.sum() or inter >= 0.5 * pm.sum():
                keep_tri[comp == ci] = False
                hits += 1
                removed.append((c[0], c[1], fp_m2, "ručně vyřazená (%s)" % bid))
        # torzo: zbylé trojúhelníky přichycené ke komponentě sousední budovy – odstranit ty,
        # jejichž VŠECHNY vrcholy leží uvnitř půdorysu (dilatovaného ≈ 6 %, stěny stojí na
        # hraně); sousední střecha/zeď má vrcholy venku, takže přežije
        grown = cen + (pa - cen) * 1.06
        inside = np.array([points_in_poly(both[:, vi, [0, 2]], grown) for vi in range(3)]).all(0)
        n_drop = int((inside & keep_tri).sum())
        keep_tri[inside] = False
        hits += n_drop
        if n_drop:
            removed.append((cen[0], cen[1], 0.0, "ručně vyřazená (%s – torzo, %d trojúhelníků)" % (bid, n_drop)))
        if hits == 0:
            print(f"  POZOR: {bid} se v geometrii nenašla")
    # duplicity (budovy přes sebe)
    gone = {ci for ci in range(comp.max() + 1) if not keep_tri[np.where(comp == ci)[0][0]]}
    fps.sort(key=lambda f: f[1])
    for a in range(len(fps)):
        ca, ia, ja, fa, pa = fps[a]
        for b in range(a + 1, len(fps)):
            cb, ib, jb, fb, pb = fps[b]
            if ib > ia + fa.shape[0]:
                break
            if ca in gone or cb in gone or jb > ja + fa.shape[1] or ja > jb + fb.shape[1]:
                continue
            # průnik obou výřezů v globálních indexech
            r0, r1 = max(ia, ib), min(ia + fa.shape[0], ib + fb.shape[0])
            c0, c1 = max(ja, jb), min(ja + fa.shape[1], jb + fb.shape[1])
            if r1 <= r0 or c1 <= c0:
                continue
            inter = (fa[r0 - ia:r1 - ia, c0 - ja:c1 - ja] & fb[r0 - ib:r1 - ib, c0 - jb:c1 - jb]).sum()
            small, big = (fa, fb) if fa.sum() <= fb.sum() else (fb, fa)
            if inter >= DUP_FRAC * small.sum():
                ci, pc = (ca, pa) if small is fa else (cb, pb)
                gone.add(ci)
                keep_tri[comp == ci] = False
                removed.append((pc[0], pc[1], small.sum() * RES * RES, "duplicita – kryje se z %d %% s jinou budovou" % (
                    100 * inter / small.sum())))
    print(f"budov: {comp.max() + 1}, vyřazeno: {len(removed)} (ve vozovce {n_road - n_axis}, u osy silnice {n_axis}, "
          f"duplicit {len(removed) - n_road})")
    for x, z, a, why in removed:
        print(f"  budova u ({x:7.1f}, {z:7.1f})  {a:5.0f} m²  {why}")
    for x, z, a, dmin in sorted(near, key=lambda r: r[3]):
        print(f"  blízko osy (ponechána, roh pod prahem) u ({x:7.1f}, {z:7.1f})  {a:5.0f} m²  {dmin:.1f} m od osy")
    for x, z, a, why, bid, poi in protected:
        print(f"  CHRÁNĚNÁ (nevyřazena, zkontrolovat ručně) u ({x:7.1f}, {z:7.1f})  {a:5.0f} m²  id {bid} ({poi}): {why}")
    kw, kr = keep_tri[:n_w], keep_tri[n_w:]
    write_dbm(os.path.join(DATA, "walls.bin"), wp[kw], wn[kw], wc[kw])
    write_dbm(os.path.join(DATA, "roofs.bin"), rp[kr], rn[kr], rc[kr])

    # bod 8: záznamy vyřazených budov (bod 6) z buildings.json – jinak by na místě zůstaly
    # fasády / dveře / nemovitost bez domu. Shoda = střed geometrie leží v půdorysu záznamu
    # a plochy jsou srovnatelné (ne sousední velký dům).
    if details:
        drop = []
        for x, z, a, _why in axis_removed:
            det = detail_at(details, x, z)
            if det is not None and 0.5 * a <= float(det.get("area", a)) <= 2.0 * a and det not in drop:
                drop.append(det)
        if drop:
            print(f"buildings.json: vyřazeno {len(drop)} záznamů (doplnit do EXCLUDE v tools/buildings.py): "
                  + ", ".join(repr(b.get("id")) for b in drop))
            kept = [b for b in details if b not in drop]
            json.dump(kept, open(os.path.join(DATA, "buildings.json"), "w"), ensure_ascii=False, separators=(",", ":"))

    # stromy
    tb = open(os.path.join(ORIG, "trees.bin"), "rb").read()
    assert tb[:4] == b"DBI1"
    n = struct.unpack_from("<i", tb, 4)[0]
    T = np.frombuffer(tb, "<f4", n * 11, 8).reshape(n, 11)
    i, j = g.ij(T[:, 0], T[:, 2])
    inside = (i >= 0) & (i < g.h) & (j >= 0) & (j < g.w)
    on_road = np.zeros(n, bool)
    on_road[inside] = road_mask[i[inside], j[inside]]
    n_asph = int(on_road.sum())
    # kmen blíž ose silnice než TREE_AXIS_BUF (pruh AI aut)
    tsel = np.where(~on_road)[0]
    t_ax = 0
    if len(segs):
        tk = np.array([TREE_AXIS_BUF.get(k, 0.0) for k in kinds])
        mt = max(TREE_AXIS_BUF.values()) + 0.5
        for ti in tsel:
            tx, tz = float(T[ti, 0]), float(T[ti, 2])
            idx = segs_near(hsh, tx - mt, tz - mt, tx + mt, tz + mt)
            if len(idx) == 0:
                continue
            d = seg_dist(np.array([tx]), np.array([tz]), segs[idx])[0]
            if (d < tk[idx]).any():
                on_road[ti] = True
                t_ax += 1
                print(f"  strom u ({tx:7.1f}, {tz:7.1f})  {float(d.min()):.1f} m od osy silnice")
    print(f"stromů: {n}, vyřazeno: {on_road.sum()} (kmen ve vozovce {n_asph}, u osy silnice {t_ax})")
    with open(os.path.join(DATA, "trees.bin"), "wb") as f:
        f.write(b"DBI1")
        f.write(struct.pack("<i", int((~on_road).sum())))
        f.write(T[~on_road].astype("<f4").tobytes())
    # silnice se nemění – jen zajistit, že data/ má originál
    for f in ("asphalt.bin", "gravel.bin"):
        shutil.copy2(os.path.join(ORIG, f), os.path.join(DATA, f))
    return 0


if __name__ == "__main__":
    sys.exit(main())
