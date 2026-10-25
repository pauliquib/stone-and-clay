"""Sdílené pomůcky vizuálního validátoru: čtení formátů dat, geometrie v rovině (x, z), sběr nálezů.

Jen numpy + scipy (žádný shapely). Souřadnice jsou herní: x, z vodorovně, y nahoru.
Formáty (viz scripts/map_loader.gd, scripts/terrain.gd, scripts/vegetation/vegetation_manager.gd):
  terrain_height.bin  float32 h×w, řádek r → z = z0 + r·spacing, sloupec c → x = x0 + c·spacing
  trees.bin           magic 4 B, i32 n, n × 11 float32 (x, y, z, rot, sx, sy, sz, r, g, b, proto)
  vegetation.bin      magic VEG1/VEG2, i32 verze, i32 N, N × 28 B (i32 typ, f32 x,y,z,rot,scale, u8 r,g,b,aux)
  walls/roofs/asphalt/gravel.bin  DBM1, i32 dlaždic; každá: i32 n, n×pos f32×3, n×normála, n×barva
"""
import json
import os
import time

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
GAME = os.path.dirname(os.path.dirname(HERE))

SEVERITIES = ("FAIL", "WARN", "INFO")
RANK = {"PASS": 0, "SKIP": -1, "INFO": 0, "WARN": 1, "FAIL": 2}

# šířky silnic (m) podle druhu – stejné jako tools/expand_buildings.py (z nich vznikly asphalt/gravel.bin)
ROAD_W = {"secondary": 7.0, "tertiary": 6.5, "unclassified": 5.5, "residential": 5.5,
          "living_street": 5.0, "service": 3.5, "track": 3.0, "path": 1.5, "footway": 1.8,
          "cycleway": 2.0}
ROAD_W_DEFAULT = 3.0
DRIVABLE = {"secondary", "tertiary", "unclassified", "residential", "service", "living_street"}


def worst(statuses):
    """Nejhorší stav ze seznamu (SKIP se nepočítá; prázdné → SKIP)."""
    st = [s for s in statuses if s and s != "SKIP"]
    if not st:
        return "SKIP"
    return max(st, key=lambda s: RANK.get(s, 0)) if any(RANK.get(s, 0) > 0 for s in st) else "PASS"


def load_json(path, default=None):
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return default


def save_json(path, obj):
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(obj, f, ensure_ascii=False, indent=1, default=_json_default)


def _json_default(o):
    if isinstance(o, (np.integer,)):
        return int(o)
    if isinstance(o, (np.floating,)):
        return None if not np.isfinite(o) else round(float(o), 4)
    if isinstance(o, np.ndarray):
        return o.tolist()
    raise TypeError(type(o))


def r3(v, nd=3):
    """Zaokrouhlení pro JSON (NaN/inf → None)."""
    if v is None:
        return None
    try:
        f = float(v)
    except (TypeError, ValueError):
        return v
    return round(f, nd) if np.isfinite(f) else None


# ---------------------------------------------------------------- nálezy

class Findings:
    """Sběrač nálezů: drží počty po kontrolách a jen TOP_N nejhorších nálezů na kontrolu (podle `score`)."""

    def __init__(self, layer, top_n=50):
        self.layer = layer
        self.top_n = top_n
        self.items = {}       # check → [nález]
        self.counts = {}      # check → {FAIL, WARN, INFO}
        self.checks = {}      # check → {"status", "metrics", "note"}
        self.t0 = time.time()

    def add(self, check, severity, msg, pos=None, score=0.0, **extra):
        c = self.counts.setdefault(check, {"FAIL": 0, "WARN": 0, "INFO": 0})
        c[severity] = c.get(severity, 0) + 1
        f = {"severity": severity, "check": check, "msg": msg}
        if pos is not None:
            f["pos"] = [r3(p, 2) for p in pos]
        for k, v in extra.items():
            if v is not None:
                f[k] = r3(v) if isinstance(v, (float, np.floating)) else v
        f["_score"] = float(score) + (1e9 if severity == "FAIL" else 1e6 if severity == "WARN" else 0)
        self.items.setdefault(check, []).append(f)

    def metrics(self, check, note=None, **m):
        d = self.checks.setdefault(check, {"metrics": {}})
        d["metrics"].update({k: (r3(v, 4) if isinstance(v, (float, np.floating)) else v) for k, v in m.items()})
        if note:
            d["note"] = note

    def skip(self, check, reason):
        self.checks[check] = {"status": "SKIP", "note": reason, "metrics": {}}

    def status_of(self, check):
        d = self.checks.get(check, {})
        if d.get("status") == "SKIP":
            return "SKIP"
        c = self.counts.get(check, {})
        return "FAIL" if c.get("FAIL") else "WARN" if c.get("WARN") else "PASS"

    def result(self, summary=None):
        out_checks = {}
        allf = []
        names = list(dict.fromkeys(list(self.checks) + list(self.counts)))
        for ch in names:
            d = dict(self.checks.get(ch, {"metrics": {}}))
            d["status"] = self.status_of(ch)
            d["counts"] = self.counts.get(ch, {"FAIL": 0, "WARN": 0, "INFO": 0})
            items = sorted(self.items.get(ch, []), key=lambda f: -f["_score"])
            d["shown"] = min(len(items), self.top_n)
            out_checks[ch] = d
            for f in items[:self.top_n]:
                f = dict(f)
                f.pop("_score", None)
                allf.append(f)
        status = worst([d["status"] for d in out_checks.values()])
        totals = {s: sum(c.get(s, 0) for c in self.counts.values()) for s in SEVERITIES}
        return {"layer": self.layer, "status": status, "totals": totals,
                "generated": time.strftime("%Y-%m-%d %H:%M:%S"), "seconds": round(time.time() - self.t0, 1),
                "summary": summary or {}, "checks": out_checks, "findings": allf}


# ---------------------------------------------------------------- binární formáty

class Terrain:
    """Výšková mřížka terrain_height.bin (memmap) s bilineárním vzorkováním."""

    def __init__(self, path, meta):
        self.w, self.h = int(meta["w"]), int(meta["h"])
        self.sp = float(meta["spacing"])
        self.x0, self.z0 = float(meta["x0"]), float(meta["z0"])
        size = os.path.getsize(path)
        if size != self.w * self.h * 4:
            raise ValueError(f"terrain_height.bin má {size} B, map.json čeká {self.w}×{self.h}×4 = {self.w * self.h * 4} B")
        self.a = np.memmap(path, dtype="<f4", mode="r", shape=(self.h, self.w))

    def sample(self, x, z):
        """Bilineární výška v bodech (x, z); mimo mřížku NaN."""
        x = np.asarray(x, dtype=np.float64)
        z = np.asarray(z, dtype=np.float64)
        c = (x - self.x0) / self.sp
        r = (z - self.z0) / self.sp
        ok = (c >= 0) & (r >= 0) & (c <= self.w - 1) & (r <= self.h - 1)
        out = np.full(x.shape, np.nan)
        if not ok.any():
            return out
        cc, rr = c[ok], r[ok]
        c0 = np.minimum(np.floor(cc).astype(np.int64), self.w - 2)
        r0 = np.minimum(np.floor(rr).astype(np.int64), self.h - 2)
        fx, fz = cc - c0, rr - r0
        a = self.a
        h00 = a[r0, c0].astype(np.float64)
        h01 = a[r0, c0 + 1].astype(np.float64)
        h10 = a[r0 + 1, c0].astype(np.float64)
        h11 = a[r0 + 1, c0 + 1].astype(np.float64)
        out[ok] = (h00 * (1 - fx) + h01 * fx) * (1 - fz) + (h10 * (1 - fx) + h11 * fx) * fz
        return out


def read_trees(path):
    """trees.bin → (magic, pole n×11 float32)."""
    b = np.fromfile(path, dtype=np.uint8)
    magic = bytes(b[:4]).decode("ascii", "replace")
    n = int(np.frombuffer(b[4:8].tobytes(), "<i4")[0])
    d = np.frombuffer(b[8:8 + n * 44].tobytes(), "<f4")
    if d.size != n * 11:
        raise ValueError(f"trees.bin useknutý: hlavička {n} stromů, dat na {d.size // 11}")
    return magic, d.reshape(n, 11)


VEG_DTYPE = np.dtype([("typ", "<i4"), ("x", "<f4"), ("y", "<f4"), ("z", "<f4"), ("rot", "<f4"),
                      ("scale", "<f4"), ("r", "u1"), ("g", "u1"), ("b", "u1"), ("aux", "u1")])


def read_vegetation(path):
    """vegetation.bin → (magic, verze, strukturované pole záznamů)."""
    with open(path, "rb") as f:
        head = f.read(12)
        if len(head) < 12:
            raise ValueError("vegetation.bin kratší než hlavička")
        magic = head[:4].decode("ascii", "replace")
        ver, n = np.frombuffer(head[4:12], "<i4")
        rec = np.fromfile(f, dtype=VEG_DTYPE, count=int(n))
    if rec.size != n:
        raise ValueError(f"vegetation.bin useknutý: hlavička {n}, záznamů {rec.size}")
    return magic, int(ver), rec


def read_dbm1(path):
    """DBM1 → (počet dlaždic, seznam (pos n×3, nrm n×3, col n×3)) – float32 pole."""
    b = np.fromfile(path, dtype=np.uint8)
    magic = bytes(b[:4]).decode("ascii", "replace")
    if magic != "DBM1":
        raise ValueError(f"špatný magic {magic!r} (čekám DBM1)")
    nch = int(np.frombuffer(b[4:8].tobytes(), "<i4")[0])
    off = 8
    tiles = []
    for _ in range(nch):
        if off + 4 > b.size:
            raise ValueError("DBM1 useknutý (hlavička dlaždice)")
        n = int(np.frombuffer(b[off:off + 4].tobytes(), "<i4")[0])
        off += 4
        need = n * 36
        if n < 0 or off + need > b.size:
            raise ValueError(f"DBM1 useknutý (dlaždice s {n} vrcholy)")
        arr = np.frombuffer(b[off:off + need].tobytes(), "<f4")
        off += need
        tiles.append((arr[:n * 3].reshape(n, 3), arr[n * 3:n * 6].reshape(n, 3), arr[n * 6:].reshape(n, 3)))
    if off != b.size:
        raise ValueError(f"DBM1: {b.size - off} B navíc za poslední dlaždicí")
    return nch, tiles


# ---------------------------------------------------------------- geometrie v rovině

def poly_area(p):
    """Znaménková plocha polygonu (shoelace); p = n×2."""
    x, z = p[:, 0], p[:, 1]
    return 0.5 * float(np.dot(x, np.roll(z, -1)) - np.dot(np.roll(x, -1), z))


def points_in_poly(px, pz, poly):
    """Vektorizovaný test bod v polygonu (crossing number). poly = n×2."""
    px = np.asarray(px, dtype=np.float64)
    pz = np.asarray(pz, dtype=np.float64)
    inside = np.zeros(px.shape, dtype=bool)
    x1, z1 = poly[:, 0], poly[:, 1]
    x2, z2 = np.roll(x1, -1), np.roll(z1, -1)
    for a, b, c, d in zip(x1, z1, x2, z2):
        cond = (b > pz) != (d > pz)
        if not cond.any():
            continue
        with np.errstate(divide="ignore", invalid="ignore"):
            xi = a + (pz - b) * (c - a) / (d - b)
        inside ^= cond & (px < xi)
    return inside


def grid_in_poly(poly, step):
    """Body pravidelné mřížky (středy buněk `step`) uvnitř polygonu → (x, z)."""
    mn, mx = poly.min(0), poly.max(0)
    xs = np.arange(mn[0] + step / 2, mx[0], step)
    zs = np.arange(mn[1] + step / 2, mx[1], step)
    if xs.size == 0 or zs.size == 0:
        c = poly.mean(0)
        return np.array([c[0]]), np.array([c[1]])
    gx, gz = np.meshgrid(xs, zs)
    gx, gz = gx.ravel(), gz.ravel()
    m = points_in_poly(gx, gz, poly)
    return gx[m], gz[m]


def seg_point_dist(px, pz, ax, az, bx, bz):
    """Vzdálenost bodů od úsečky AB a parametr t nejbližšího bodu."""
    dx, dz = bx - ax, bz - az
    L2 = dx * dx + dz * dz
    if L2 < 1e-12:
        t = np.zeros_like(np.asarray(px, dtype=float))
    else:
        t = np.clip(((px - ax) * dx + (pz - az) * dz) / L2, 0.0, 1.0)
    qx, qz = ax + t * dx, az + t * dz
    return np.hypot(px - qx, pz - qz), t


def segments_intersect(p1, p2, p3, p4):
    """Vlastní průsečík dvou úseček (bez dotyku v koncových bodech)."""
    def orient(a, b, c):
        return (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0])
    d1, d2 = orient(p3, p4, p1), orient(p3, p4, p2)
    d3, d4 = orient(p1, p2, p3), orient(p1, p2, p4)
    eps = 1e-9
    return ((d1 > eps and d2 < -eps) or (d1 < -eps and d2 > eps)) and \
           ((d3 > eps and d4 < -eps) or (d3 < -eps and d4 > eps))


def self_intersections(poly):
    """Seznam dvojic hran (i, j), které se protínají (sousední hrany se nepočítají)."""
    n = len(poly)
    out = []
    for i in range(n):
        a, b = poly[i], poly[(i + 1) % n]
        for j in range(i + 2, n):
            if i == 0 and j == n - 1:
                continue
            if segments_intersect(a, b, poly[j], poly[(j + 1) % n]):
                out.append((i, j))
    return out


def densify(pts, step):
    """Zahustí lomenou čáru na body po ~step m → (body m×2, kumulativní délka m)."""
    pts = np.asarray(pts, dtype=np.float64)[:, :2]
    if len(pts) < 2:
        return pts, np.zeros(len(pts))
    out = [pts[:1]]
    for a, b in zip(pts[:-1], pts[1:]):
        L = float(np.hypot(*(b - a)))
        k = max(1, int(np.ceil(L / step)))
        t = np.arange(1, k + 1) / k
        out.append(a + (b - a) * t[:, None])
    P = np.vstack(out)
    s = np.concatenate([[0.0], np.cumsum(np.hypot(*np.diff(P, axis=0).T))])
    return P, s


class RoadIndex:
    """KD-strom zahuštěných os silnic: rychlé „je bod na vozovce?“ a „nejbližší silnice“."""

    def __init__(self, roads, kinds=None, step=0.5):
        from scipy.spatial import cKDTree
        P, hw, ri = [], [], []
        self.roads = roads
        for i, r in enumerate(roads):
            if kinds is not None and r.get("kind") not in kinds:
                continue
            pts, _ = densify(r["pts"], step)
            if len(pts) == 0:
                continue
            P.append(pts)
            hw.append(np.full(len(pts), ROAD_W.get(r.get("kind"), ROAD_W_DEFAULT) / 2))
            ri.append(np.full(len(pts), i))
        self.empty = not P
        if self.empty:
            return
        self.P = np.vstack(P)
        self.hw = np.concatenate(hw)
        self.ri = np.concatenate(ri)
        self.tree = cKDTree(self.P)
        self.max_hw = float(self.hw.max())

    def depth(self, x, z, k=8):
        """Hloubka zásahu do vozovky (halfw − vzdálenost od osy, >0 = na silnici) a index silnice."""
        x = np.atleast_1d(np.asarray(x, dtype=np.float64))
        z = np.atleast_1d(np.asarray(z, dtype=np.float64))
        if self.empty or x.size == 0:
            return np.full(x.shape, -np.inf), np.full(x.shape, -1)
        k = min(k, len(self.P))
        d, idx = self.tree.query(np.c_[x, z], k=k, distance_upper_bound=self.max_hw + 1.0)
        d = np.atleast_2d(d.reshape(len(x), k))
        idx = np.atleast_2d(idx.reshape(len(x), k))
        valid = idx < len(self.P)
        safe = np.where(valid, idx, 0)
        dep = np.where(valid, self.hw[safe] - d, -np.inf)
        j = np.argmax(dep, axis=1)
        rows = np.arange(len(x))
        return dep[rows, j], np.where(valid[rows, j], self.ri[safe[rows, j]], -1)

    def nearest(self, x, z):
        """Nejbližší bod osy: (vzdálenost, bod 2, index silnice)."""
        d, i = self.tree.query([x, z])
        return float(d), self.P[i], int(self.ri[i])


class BuildingRaster:
    """Raster id budov (krok `cell`) pro rychlý test „bod v domě“. Hodnota = index budovy, −1 = venku."""

    def __init__(self, polys, cell=0.5, margin=2.0):
        allp = np.vstack(polys)
        self.cell = cell
        self.x0, self.z0 = allp.min(0) - margin
        x1, z1 = allp.max(0) + margin
        self.nx = int(np.ceil((x1 - self.x0) / cell))
        self.nz = int(np.ceil((z1 - self.z0) / cell))
        self.g = np.full((self.nz, self.nx), -1, dtype=np.int32)
        for i, p in enumerate(polys):
            mn, mx = p.min(0), p.max(0)
            c0, c1 = int((mn[0] - self.x0) / cell), int((mx[0] - self.x0) / cell) + 1
            r0, r1 = int((mn[1] - self.z0) / cell), int((mx[1] - self.z0) / cell) + 1
            cx = self.x0 + (np.arange(c0, c1) + 0.5) * cell
            cz = self.z0 + (np.arange(r0, r1) + 0.5) * cell
            gx, gz = np.meshgrid(cx, cz)
            m = points_in_poly(gx, gz, p)
            sub = self.g[r0:r1, c0:c1]
            sub[m] = i

    def lookup(self, x, z):
        x = np.asarray(x, dtype=np.float64)
        z = np.asarray(z, dtype=np.float64)
        c = np.floor((x - self.x0) / self.cell).astype(np.int64)
        r = np.floor((z - self.z0) / self.cell).astype(np.int64)
        ok = (c >= 0) & (r >= 0) & (c < self.nx) & (r < self.nz)
        out = np.full(x.shape, -1, dtype=np.int64)
        out[ok] = self.g[r[ok], c[ok]]
        return out
