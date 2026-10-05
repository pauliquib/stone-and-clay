"""Vodní toky a nádrže podle skutečných dat → data/water.json + data/water_carve.bin.

Zdroj: OpenStreetMap (ODbL) z regionálního extraktu geodata/pbf/zlinsky-latest.osm.pbf – toky v ČR
v OSM pocházejí převážně z DIBAVOD (VÚV T. G. M.): Březnice (řeka), Černý potok, Kaňovický potok,
Oskorušný, Neradovský, Zlámanecký potok a bezejmenné přítoky; nádrže natural=water.
Ve výstupu se názvy přepisují na fiktivní (FICTIONAL_NAMES) – reálná jména obcí/toků se ve hře neukazují.

Postup:
  1. waterway=river|stream|ditch|drain|canal (bez propustků tunnel=culvert) a natural=water (bez
     občasných suchých nádrží) v obdélníku katastru + 200 m → souřadnice scény (jako fáze 2 / 11).
  2. Osa toku se převzorkuje po 2 m a "sklouzne" do údolnice DMR 5G (nejnižší bod do ±6 m kolmo,
     vyhlazeno) – linie z DIBAVOD bývají o pár metrů vedle skutečného koryta.
  3. Dno koryta: po proudu nikdy nestoupá (směr linie v OSM = směr toku), max. o `maxcut` pod terénem.
  4. Výšková mřížka hry se v okolí toku zahloubí (koryto s rovným dnem a svahy břehů), ne však pod
     silnicemi a cestami (maska z asphalt.bin / gravel.bin) – tam tok vede „propustkem“ pod cestou.
     Změněné body mřížky + nové normály → data/water_carve.bin (Terrain je aplikuje při načtení).
  5. data/water.json: osy toků s hladinou po bodech, nádrže (polygon + hladina), stromy stojící v korytě.

  python3 tools/water.py
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

# druh → poloviční šířka dna, hloubka zahloubení, hloubka vody, sklon břehu (m/m), max. zářez, šířka hladiny/2
KINDS = {
    "river":  {"flat": 3.0, "cut": 1.1, "water": 0.55, "bank": 0.55, "maxcut": 2.2},
    "canal":  {"flat": 1.6, "cut": 0.7, "water": 0.4, "bank": 0.7, "maxcut": 1.6},
    "stream": {"flat": 1.0, "cut": 0.5, "water": 0.22, "bank": 0.8, "maxcut": 1.4},
    "ditch":  {"flat": 0.8, "cut": 0.35, "water": 0.1, "bank": 0.9, "maxcut": 0.9},
    "drain":  {"flat": 0.8, "cut": 0.35, "water": 0.1, "bank": 0.9, "maxcut": 0.9},
}
STEP = 2.0
SNAP_R = 6.0
POND_DEPTH = 0.9

# Ve hře nesmí figurovat reálné názvy obcí/toků → fiktivní názvy (geometrie zůstává z OSM/DIBAVOD)
FICTIONAL_NAMES = {
    "Březnice": "Břehatice",
    "Bohuslavice u Zlína": "Bohulečice",
    "Březůvky": "Březouchy",
    "Velký Ořechov": "Velký Oříškov",
    "Hřivínův Újezd": "Hřiváčův Újezd",
    "Černý potok": "Blatný potok",
    "Kaňovický potok": "Havraní potok",
    "Neradovský potok": "Sojčí potok",
    "Oskorušný potok": "Jeřabinový potok",
    "Zlámanecký potok": "Sokolí potok",
}


def fname(name, place_names=()):
    """Jméno toku/nádrže → fiktivní podoba nebo "" (zahodit).

    Hygienický filtr dle vzoru fname_road v tools/obce.py:
    1) přesná shoda s FICTIONAL_NAMES (obec/řeka/potok),
    2) substring náhrada mapovaných toponym („Kaňovický potok“→„Havraní potok“ aj.),
    3) obsahuje-li název reálné toponymum z okolí (place uzel z union extraktu,
       len ≥ 4 znaky, případně jeho přídavný kmen typu Kaňovice→Kaňovic),
       které fiktivní protějšek nemá → "" (raději bez jména než reálný název)."""
    if not name:
        return ""
    if name in FICTIONAL_NAMES:
        return FICTIONAL_NAMES[name]
    out = name
    replaced = False
    for real, fic in sorted(FICTIONAL_NAMES.items(), key=lambda kv: -len(kv[0])):
        if real in out:
            out = out.replace(real, fic)
            replaced = True
    for pl in place_names:
        if len(pl) < 4:
            continue
        if pl in out:
            return ""
        # přídavné kmeny toponym: Březůvky→Březův(ecký), Doubravy→Doubrav(ský),
        # Hřivínův Újezd→Hřivín(ovský), Kaňovice→Kaňovic(ký)
        words = [pl] + ([pl.split()[0]] if " " in pl else [])
        for w in words:
            for k in (1, 2):
                stem = w[:-k]
                if len(stem) >= 4 and stem in out:
                    return ""
    # přísná hygiena: názvy vod jsou reálná jména z DIBAVOD (Holomňa, Milenov,
    # Jaroslavický potok…) – zobrazit smí jen jméno, ve kterém se skutečně
    # provedla fiktivní náhrada; ostatní zahodit
    if not replaced:
        return ""
    return out


def load_place_names():
    """Reálná toponyma pro fname() – place_names z celého kraje v union extraktu
    (chytnou i města za hranou: Zlín, Luhačovice…), jinak place uzly z bbox."""
    out = set()
    for fn in ("osm_raw_union.json", "osm_raw_full.json"):
        p = os.path.join(PDATA, fn)
        if not os.path.exists(p):
            continue
        try:
            raw = json.load(open(p, encoding="utf-8"))
        except Exception:
            continue
        out.update(raw.get("place_names", ()))
        for e in raw.get("elements", []):
            if e.get("type") == "node" and "place" in e.get("tags", {}) and e["tags"].get("name"):
                out.add(e["tags"]["name"])
        if out:
            break
    return out


def osm_raw_bbox():
    """bbox lat/lon pro Collector – preferuje union extrakt (B2), jinak full (katastr)."""
    for fn in ("osm_raw_union.json", "osm_raw_full.json"):
        p = os.path.join(PDATA, fn)
        if os.path.exists(p):
            return json.load(open(p, encoding="utf-8"))["bbox_latlon_margin"], fn
    raise FileNotFoundError("chybí pipeline/data/osm_raw_{union,full}.json")


class Collector(osmium.SimpleHandler):
    def __init__(self, bbox):
        super().__init__()
        self.bbox = bbox
        self.ways = []

    def way(self, w):
        t = dict(w.tags)
        ww = t.get("waterway", "")
        pond = t.get("natural") == "water" or t.get("landuse") in ("reservoir", "basin")
        if ww not in KINDS and not pond:
            return
        try:
            pts = [(n.location.lat, n.location.lon) for n in w.nodes]
        except osmium.InvalidLocationError:
            return
        b = self.bbox
        if not any(b[0] <= lo <= b[2] and b[1] <= la <= b[3] for la, lo in pts):
            return
        self.ways.append({"id": w.id, "tags": t, "ll": pts, "pond": pond and ww not in KINDS})


# ------------------------------------------------------------------ výšková mřížka hry

class Grid:
    def __init__(self, meta):
        hm = meta["height"]
        self.w, self.h, self.sp = hm["w"], hm["h"], hm["spacing"]
        self.x0, self.z0 = hm["x0"], hm["z0"]
        self.hm = np.fromfile(os.path.join(DATA, "terrain_height.bin"), np.float32).astype(np.float64).reshape(self.h, self.w)
        self.orig = self.hm.copy()

    def sample(self, x, z, arr=None):
        arr = self.hm if arr is None else arr
        fx = np.clip((np.asarray(x, float) - self.x0) / self.sp, 0, self.w - 1.001)
        fz = np.clip((np.asarray(z, float) - self.z0) / self.sp, 0, self.h - 1.001)
        ix, iz = np.floor(fx).astype(int), np.floor(fz).astype(int)
        tx, tz = fx - ix, fz - iz
        a, b = arr[iz, ix], arr[iz, ix + 1]
        c, d = arr[iz + 1, ix], arr[iz + 1, ix + 1]
        return (a * (1 - tx) + b * tx) * (1 - tz) + (c * (1 - tx) + d * tx) * tz

    def inside(self, x, z, margin=20.0):
        return (self.x0 + margin < x < self.x0 + (self.w - 1) * self.sp - margin and
                self.z0 + margin < z < self.z0 + (self.h - 1) * self.sp - margin)


# šířky silničních pásů pro ochranu mřížky v novém území (budovy/silnice se tam
# staví až ve fázi B3 – osy z okoli_union_local.geojson); ≈ phase13 ROAD_W
LINE_ROAD_W = {"motorway": 10, "trunk": 9, "primary": 8, "secondary": 7, "tertiary": 6.5,
               "unclassified": 5.5, "residential": 5.5, "living_street": 5, "service": 3.5,
               "track": 3, "path": 1.5, "footway": 1.8, "cycleway": 2}


def road_mask(g):
    """Body mřížky pod silnicemi / cestami, rozšířené o 2 buňky.

    Dvě vrstvy: trojúhelníky asphalt.bin + gravel.bin (starý blok – přesná geometrie)
    a osy highway=* z okoli_union_local.geojson (nové území – silniční pásy vzniknou
    až v B3; bez ochrany by se koryto toku zařízlo pod budoucí vozovku)."""
    mask = np.zeros((g.h, g.w), bool)
    for fn in ("asphalt.bin", "gravel.bin"):
        b = open(os.path.join(DATA, fn), "rb").read()
        assert b[:4] == b"DBM1"
        n_ch = struct.unpack_from("<i", b, 4)[0]
        off = 8
        for _ in range(n_ch):
            n = struct.unpack_from("<i", b, off)[0]
            off += 4
            pos = np.frombuffer(b, np.float32, n * 3, off).reshape(-1, 3, 3)
            off += n * 12 * 3
            # vzorky trojúhelníků (těžiště + vrcholy + středy hran) stačí – trojúhelníky silnic jsou malé
            pts = [pos[:, 0], pos[:, 1], pos[:, 2], pos.mean(1),
                   (pos[:, 0] + pos[:, 1]) / 2, (pos[:, 1] + pos[:, 2]) / 2, (pos[:, 0] + pos[:, 2]) / 2]
            for p in pts:
                ix = np.round((p[:, 0] - g.x0) / g.sp).astype(int)
                iz = np.round((p[:, 2] - g.z0) / g.sp).astype(int)
                ok = (ix >= 0) & (ix < g.w) & (iz >= 0) & (iz < g.h)
                mask[iz[ok], ix[ok]] = True
    n_dbm = int(mask.sum())
    # --- osy silnic z union extraktu (chrání i nové území, kde DBM1 ještě není)
    gj_path = os.path.join(PDATA, "okoli_union_local.geojson")
    if os.path.exists(gj_path):
        img = Image.new("L", (g.w, g.h), 0)
        dr = ImageDraw.Draw(img)
        n_lines = 0
        for ft in json.load(open(gj_path, encoding="utf-8"))["features"]:
            p = ft["properties"]
            if p.get("kind") != "highway" or ft["geometry"]["type"] != "LineString":
                continue
            wid = LINE_ROAD_W.get(p.get("highway", ""))
            if wid is None:
                continue
            line = [((q[0] - g.x0) / g.sp - 0.5, (-q[1] - g.z0) / g.sp - 0.5)
                    for q in ft["geometry"]["coordinates"]]
            if len(line) >= 2:
                dr.line(line, fill=1, width=max(1, int(round(wid / g.sp))))
                n_lines += 1
        mask |= np.array(img, bool)
        print(f"ROAD MASK lines: {n_lines} os z okoli_union_local.geojson")
    for _ in range(2):
        m = mask.copy()
        m[1:, :] |= mask[:-1, :]
        m[:-1, :] |= mask[1:, :]
        m[:, 1:] |= mask[:, :-1]
        m[:, :-1] |= mask[:, 1:]
        mask = m
    print(f"ROAD MASK: {int(mask.sum())} grid vertices protected "
          f"(z toho DBM1 {n_dbm})")
    return mask


def resample(pts, step):
    out = [pts[0]]
    carry = 0.0
    for a, b in zip(pts[:-1], pts[1:]):
        L = math.hypot(b[0] - a[0], b[1] - a[1])
        t = step - carry
        while t <= L:
            out.append((a[0] + (b[0] - a[0]) * t / L, a[1] + (b[1] - a[1]) * t / L))
            t += step
        carry = L - (t - step)
    if math.hypot(out[-1][0] - pts[-1][0], out[-1][1] - pts[-1][1]) > step * 0.3:
        out.append(pts[-1])
    return np.array(out)


def snap_to_valley(g, P):
    """Posune body osy kolmo (±SNAP_R) do nejnižšího místa terénu; posuny vyhladí."""
    n = len(P)
    if n < 3:
        return P
    tang = np.gradient(P, axis=0)
    tang /= np.maximum(np.linalg.norm(tang, axis=1, keepdims=True), 1e-9)
    nrm = np.stack([-tang[:, 1], tang[:, 0]], axis=1)
    offs = np.arange(-SNAP_R, SNAP_R + 0.01, 1.0)
    cand = P[:, None, :] + nrm[:, None, :] * offs[None, :, None]
    hz = g.sample(cand[..., 0], cand[..., 1], g.orig) + np.abs(offs)[None, :] * 0.04
    best = offs[np.argmin(hz, axis=1)]
    k = 9
    pad = np.pad(best, k // 2, mode="edge")
    sm = np.convolve(pad, np.ones(k) / k, mode="valid")
    return P + nrm * sm[:, None]


def point_in_poly(x, z, poly):
    x, z = np.asarray(x, float), np.asarray(z, float)
    ins = np.zeros(x.shape, bool)
    n = len(poly)
    for i in range(n):
        x1, z1 = poly[i]
        x2, z2 = poly[(i + 1) % n]
        cond = (z1 > z) != (z2 > z)
        xi = (x2 - x1) * (z - z1) / ((z2 - z1) if z2 != z1 else 1e-12) + x1
        ins ^= cond & (x < xi)
    return ins


def carve_stream(g, P, bed, spec, protect):
    """Zahloubí mřížku kolem osy P (Nx2) s dnem `bed` (N): rovné dno do `flat`, pak svah `bank`."""
    reach = spec["flat"] + (spec["maxcut"] + 0.5) / spec["bank"] + g.sp
    lo = np.floor((P.min(0) - reach - np.array([g.x0, g.z0])) / g.sp).astype(int)
    hi = np.ceil((P.max(0) + reach - np.array([g.x0, g.z0])) / g.sp).astype(int)
    lo = np.maximum(lo, 0)
    hi = np.minimum(hi, [g.w - 1, g.h - 1])
    xs = g.x0 + np.arange(lo[0], hi[0] + 1) * g.sp
    zs = g.z0 + np.arange(lo[1], hi[1] + 1) * g.sp
    X, Z = np.meshgrid(xs, zs)
    best_d = np.full(X.shape, np.inf)
    best_b = np.zeros(X.shape)
    for i in range(len(P) - 1):
        a, b = P[i], P[i + 1]
        ab = b - a
        L2 = max(ab @ ab, 1e-9)
        t = np.clip(((X - a[0]) * ab[0] + (Z - a[1]) * ab[1]) / L2, 0, 1)
        d = np.hypot(X - (a[0] + ab[0] * t), Z - (a[1] + ab[1] * t))
        closer = d < best_d
        best_d = np.where(closer, d, best_d)
        best_b = np.where(closer, bed[i] + (bed[i + 1] - bed[i]) * t, best_b)
    target = best_b + np.maximum(best_d - spec["flat"], 0.0) * spec["bank"]
    sl = (slice(lo[1], hi[1] + 1), slice(lo[0], hi[0] + 1))
    cur = g.hm[sl]
    new = np.where(protect[sl], cur, np.minimum(cur, target))
    g.hm[sl] = new


def main():
    meta = json.load(open(os.path.join(DATA, "map.json")))
    ref = json.load(open(os.path.join(PDATA, "scene_reference.json")))
    bbox, bbox_src = osm_raw_bbox()
    pnames = load_place_names()
    print(f"OSM bbox: {bbox_src}; place_names pro filtr: {len(pnames)}")
    tf = make_transform(ref)
    g = Grid(meta)
    protect = road_mask(g)

    col = Collector(bbox)
    col.apply_file(PBF, locations=True, idx="sparse_mem_array")
    print(f"OSM: {len(col.ways)} water ways")

    streams, ponds = [], []
    for w in col.ways:
        t = w["tags"]
        pts = []
        for la, lo in w["ll"]:
            sx, sy = tf(la, lo)
            pts.append((sx, -sy))          # scéna (x, y) → Godot (x, z = −y)
        if w["pond"]:
            if t.get("intermittent") == "yes" or len(pts) < 4 or pts[0] != pts[-1]:
                continue
            poly = pts[:-1]
            if not all(g.inside(x, z) for x, z in poly):
                continue
            ponds.append({"id": w["id"], "name": fname(t.get("name", ""), pnames), "poly": poly})
            continue
        if t.get("tunnel") in ("culvert", "yes") or t.get("layer", "0").startswith("-"):
            continue
        kind = t["waterway"]
        if t.get("name", "").endswith(" p.."):      # zkrácený název z DIBAVOD („Kaňovický p..“)
            t["name"] = t["name"][:-3] + "potok"
        # jen úseky uvnitř mřížky
        run = []
        for p in pts:
            if g.inside(*p):
                run.append(p)
            elif len(run) >= 2:
                streams.append({"id": w["id"], "kind": kind, "name": fname(t.get("name", ""), pnames), "pts": run})
                run = []
            else:
                run = []
        if len(run) >= 2:
            streams.append({"id": w["id"], "kind": kind, "name": fname(t.get("name", ""), pnames), "pts": run})

    out_streams = []
    total_len = 0.0
    for s in streams:
        spec = KINDS[s["kind"]]
        P = resample(s["pts"], STEP)
        if len(P) < 2:
            continue
        P = snap_to_valley(g, P)
        ground = g.sample(P[:, 0], P[:, 1], g.orig)
        bed = np.empty(len(P))
        prev = np.inf
        for i, h0 in enumerate(ground):
            b = min(prev, h0 - spec["cut"])
            b = max(b, h0 - spec["maxcut"])
            bed[i] = b
            prev = b
        carve_stream(g, P, bed, spec, protect)
        # hladina: dno + voda; hladina nad chráněnou silnicí se vynechá (tok „podteče“)
        level = bed + spec["water"]
        ix = np.round((P[:, 0] - g.x0) / g.sp).astype(int)
        iz = np.round((P[:, 1] - g.z0) / g.sp).astype(int)
        under_road = protect[iz, ix]
        seg = []
        for i in range(len(P)):
            if under_road[i]:
                if len(seg) >= 2:
                    out_streams.append({"name": s["name"], "kind": s["kind"], "osm_id": s["id"], "pts": seg})
                seg = []
                continue
            seg.append([round(float(P[i, 0]), 2), round(float(P[i, 1]), 2), round(float(level[i]), 3)])
        if len(seg) >= 2:
            out_streams.append({"name": s["name"], "kind": s["kind"], "osm_id": s["id"], "pts": seg})
        total_len += float(np.sum(np.hypot(*np.diff(P, axis=0).T)))

    out_ponds = []
    for pd in ponds:
        poly = np.array(pd["poly"])
        # hladina = nejnižší místo břehu (ať voda nikde nevisí nad terénem)
        rim = resample([tuple(p) for p in poly] + [tuple(poly[0])], 1.0)
        level = float(np.min(g.sample(rim[:, 0], rim[:, 1], g.orig))) - 0.05
        lo = np.maximum(np.floor((poly.min(0) - np.array([g.x0, g.z0])) / g.sp).astype(int) - 1, 0)
        hi = np.minimum(np.ceil((poly.max(0) - np.array([g.x0, g.z0])) / g.sp).astype(int) + 1, [g.w - 1, g.h - 1])
        xs = g.x0 + np.arange(lo[0], hi[0] + 1) * g.sp
        zs = g.z0 + np.arange(lo[1], hi[1] + 1) * g.sp
        X, Z = np.meshgrid(xs, zs)
        ins = point_in_poly(X, Z, poly)
        # vzdálenost od břehu → hloubka (u břehu mělko)
        d = np.full(X.shape, np.inf)
        for i in range(len(poly)):
            a, b = poly[i], poly[(i + 1) % len(poly)]
            ab = b - a
            t = np.clip(((X - a[0]) * ab[0] + (Z - a[1]) * ab[1]) / max(ab @ ab, 1e-9), 0, 1)
            d = np.minimum(d, np.hypot(X - (a[0] + ab[0] * t), Z - (a[1] + ab[1] * t)))
        target = level - 0.15 - POND_DEPTH * np.clip(d / 5.0, 0, 1)
        sl = (slice(lo[1], hi[1] + 1), slice(lo[0], hi[0] + 1))
        cur = g.hm[sl]
        g.hm[sl] = np.where(ins & ~protect[sl], np.minimum(cur, target), cur)
        out_ponds.append({"name": pd["name"], "osm_id": pd["id"], "level": round(level, 3),
                          "poly": [[round(float(x), 2), round(float(z), 2)] for x, z in poly]})

    # ---------------- změněné body mřížky + normály
    changed = np.abs(g.hm - g.orig) > 1e-4
    near = changed.copy()
    near[1:, :] |= changed[:-1, :]
    near[:-1, :] |= changed[1:, :]
    near[:, 1:] |= changed[:, :-1]
    near[:, :-1] |= changed[:, 1:]
    gz, gx = np.gradient(g.hm, g.sp)
    nrm = np.stack([-gx, np.ones_like(g.hm), -gz], axis=-1)
    nrm /= np.linalg.norm(nrm, axis=-1, keepdims=True)
    nb = ((nrm * 0.5 + 0.5) * 255).round().astype(np.uint8)
    idx = np.flatnonzero(near.ravel()).astype(np.int32)
    with open(os.path.join(DATA, "water_carve.bin"), "wb") as f:
        f.write(b"DBW1")
        f.write(struct.pack("<i", len(idx)))
        f.write(idx.tobytes())
        f.write(g.hm.ravel()[idx].astype(np.float32).tobytes())
        f.write(nb.reshape(-1, 3)[idx].tobytes())
    ch = (g.orig - g.hm)[changed]
    print(f"CARVE: {int(changed.sum())} vertices lowered (max {ch.max():.2f} m, mean {ch.mean():.2f} m), "
          f"{len(idx)} written")

    # ---------------- stromy v korytě / v rybníce (hra je nevykreslí)
    tb = open(os.path.join(DATA, "trees.bin"), "rb").read()
    nt = struct.unpack_from("<i", tb, 4)[0]
    T = np.frombuffer(tb, np.float32, nt * 11, 8).reshape(-1, 11)
    wet = np.zeros(nt, bool)
    lvl = np.full(nt, -np.inf)
    for s in out_streams:
        Q = np.array(s["pts"])
        hw = KINDS[s["kind"]]["flat"] + 0.3
        for i in range(len(Q) - 1):
            a, b = Q[i, :2], Q[i + 1, :2]
            ab = b - a
            t = np.clip(((T[:, 0] - a[0]) * ab[0] + (T[:, 2] - a[1]) * ab[1]) / max(ab @ ab, 1e-9), 0, 1)
            d = np.hypot(T[:, 0] - (a[0] + ab[0] * t), T[:, 2] - (a[1] + ab[1] * t))
            wet |= d < hw
    for p in out_ponds:
        wet |= point_in_poly(T[:, 0], T[:, 2], p["poly"])
    del lvl
    drop = np.flatnonzero(wet).tolist()
    print(f"TREES in water: {len(drop)} hidden")

    out = {
        "version": 1,
        "source": "OpenStreetMap © přispěvatelé (ODbL), toky převzaté z DIBAVOD (VÚV T. G. M.); výšky DMR 5G © ČÚZK",
        "kinds": {k: {"half_w": v["flat"] + v["water"] / v["bank"] + 0.5, "flat": v["flat"]} for k, v in KINDS.items()},
        "streams": out_streams,
        "ponds": out_ponds,
        "drop_trees": drop,
    }
    json.dump(out, open(os.path.join(DATA, "water.json"), "w"), ensure_ascii=False)
    names = sorted({s["name"] for s in out_streams if s["name"]})
    print(f"WROTE water.json: {len(out_streams)} stream segments ({total_len / 1000:.1f} km), "
          f"{len(out_ponds)} ponds; names: {', '.join(names)}")


if __name__ == "__main__":
    main()
