"""Fáze 6d – analýza geodat (čistý Python, numpy/scipy).

Vstupy: geodata/{dtm,dsm}_scene.npy, geodata/ortho_scene.jpg, pipeline/data/geodata_meta.json,
        pipeline/data/okoli_local.geojson, pipeline/data/apron.json, pipeline/data/scene_inspect.json
Výstupy:
  pipeline/data/terrain_ref.json    – H_ref (nadm. výška [m n. m. Bpv] odpovídající z = 0 ve scéně)
  geodata/terrain_z.npy    – výška terénu ve scéně (z), 1 m mřížka, pod modelem pozemku snížená
  pipeline/data/buildings_3d.json   – pro každou budovu: podklad, okap, hřeben, typ a osa střechy,
                             barva střechy z ortofota, tón fasády; + nezmapované stavby z DMP
  pipeline/data/trees_ndsm.json     – stromy z DMP − DMR (poloha, výška, poloměr koruny, barva)

Výšky střech: v půdorysu (zmenšeném o 0,6 m) se na DMP fitují modely střech
(plochá, sedlová podél delší/kratší osy, valbová) – vybere se nejlepší, z něj
plyne výška okapu a hřebene. Budovy, které v DMP nejsou (novostavby po
leteckém snímkování), dostanou výšku z OSM tagů.
"""
import json
import math
import os

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage

Image.MAX_IMAGE_PIXELS = None
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)          # pipeline/ – data/, assets/, renders/, logs/
GAME = os.path.dirname(ROOT)          # kořen repozitáře hry – geodata/, blend/
GEO = os.path.join(GAME, "geodata")
R_MAX = 470.0

meta = json.load(open(os.path.join(ROOT, "data", "geodata_meta.json")))
X0, Y1, RES, N = meta["grid_x0"], meta["grid_y1"], meta["dem_res"], meta["dem_n"]
CX, CY = meta["center"]
ORES = meta["ortho_res"]


def rc(x, y, res=RES):
    """scéna → spojité (řádek, sloupec) se středy pixelů na celých číslech."""
    return (Y1 - np.asarray(y)) / res - 0.5, (np.asarray(x) - X0) / res - 0.5


def sample(arr, x, y, order=1, res=RES):
    r, c = rc(x, y, res)
    return ndimage.map_coordinates(arr, [np.atleast_1d(r), np.atleast_1d(c)], order=order, mode="nearest")


def pip(px, py, poly):
    """Vektorový test bod v polygonu (even-odd)."""
    px = np.asarray(px)
    py = np.asarray(py)
    inside = np.zeros(px.shape, bool)
    n = len(poly)
    for i in range(n):
        x1, y1 = poly[i]
        x2, y2 = poly[(i + 1) % n]
        cond = (y1 > py) != (y2 > py)
        xint = (x2 - x1) * (py - y1) / ((y2 - y1) if y2 != y1 else 1e-12) + x1
        inside ^= cond & (px < xint)
    return inside


def dist_to_edges(px, py, poly):
    d = np.full(np.shape(px), np.inf)
    n = len(poly)
    for i in range(n):
        ax, ay = poly[i]
        bx, by = poly[(i + 1) % n]
        dx, dy = bx - ax, by - ay
        L = dx * dx + dy * dy or 1e-12
        t = np.clip(((px - ax) * dx + (py - ay) * dy) / L, 0, 1)
        d = np.minimum(d, np.hypot(px - ax - t * dx, py - ay - t * dy))
    return d


def open_ring(r):
    pts = [tuple(p) for p in r]
    return pts[:-1] if len(pts) > 1 and pts[0] == pts[-1] else pts


def hull(pts):
    pts = sorted(set(pts))
    if len(pts) < 3:
        return pts

    def cr(o, a, b):
        return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])

    lo, up = [], []
    for p in pts:
        while len(lo) >= 2 and cr(lo[-2], lo[-1], p) <= 0:
            lo.pop()
        lo.append(p)
    for p in reversed(pts):
        while len(up) >= 2 and cr(up[-2], up[-1], p) <= 0:
            up.pop()
        up.append(p)
    return lo[:-1] + up[:-1]


def mar(pts):
    h = hull(pts)
    best = None
    for i in range(len(h)):
        x1, y1 = h[i]
        x2, y2 = h[(i + 1) % len(h)]
        a = math.atan2(y2 - y1, x2 - x1)
        c, s = math.cos(a), math.sin(a)
        us = [x * c + y * s for x, y in h]
        vs = [-x * s + y * c for x, y in h]
        area = (max(us) - min(us)) * (max(vs) - min(vs))
        if best is None or area < best[0]:
            best = (area, a, min(us), max(us), min(vs), max(vs))
    _, a, u0, u1, v0, v1 = best
    c, s = math.cos(a), math.sin(a)
    uc, vc = (u0 + u1) / 2, (v0 + v1) / 2
    L, W = u1 - u0, v1 - v0
    if W > L:
        L, W, a = W, L, a + math.pi / 2
    return uc * c - vc * s, uc * s + vc * c, L, W, a


FACADE_TINTS = [(0.93, 0.91, 0.86), (0.95, 0.93, 0.84), (0.93, 0.88, 0.74), (0.86, 0.86, 0.84),
                (0.94, 0.86, 0.76), (0.90, 0.90, 0.88), (0.96, 0.95, 0.92), (0.88, 0.83, 0.72)]


def fit_roof(px, py, h, rect):
    """Fit modelů střech na výšky h v bodech (px, py). Vrací dict nebo None."""
    cx, cy, L, W, a = rect
    c, s = math.cos(a), math.sin(a)
    u = (px - cx) * c + (py - cy) * s
    v = -(px - cx) * s + (py - cy) * c
    models = {
        "flat": None,
        "gable_long": np.abs(v),
        "gable_short": np.abs(u),
        "hipped": np.maximum(np.abs(v), np.abs(u) - (L - W) / 2),
    }
    res = {}
    for name, feat in models.items():
        keep = np.ones(h.shape, bool)
        for _ in range(2):  # robustně: druhé kolo bez odlehlých bodů (větve stromů, komíny)
            if feat is None:
                a0 = np.median(h[keep])
                pred = np.full(h.shape, a0)
                b = 0.0
            else:
                A = np.c_[np.ones(keep.sum()), -feat[keep]]
                (a0, b), *_ = np.linalg.lstsq(A, h[keep], rcond=None)
                pred = a0 - b * feat
            r = h - pred
            sd = max(np.std(r[keep]), 0.15)
            keep = np.abs(r) < 2.5 * sd
            if keep.sum() < 6:
                keep = np.ones(h.shape, bool)
        rss = float(np.mean(np.abs(r[keep]))) + 0.02 * (1 - keep.mean()) * 10
        res[name] = (rss, float(a0), float(b))
    # výběr
    cands = []
    for name, (rss, a0, b) in res.items():
        if name == "flat":
            cands.append((rss, name, a0, a0))
            continue
        if b <= 0.05:
            continue
        half = W / 2 if name in ("gable_long", "hipped") else L / 2
        eave = a0 - b * half
        rise = a0 - eave
        pen = 1.0 if name != "hipped" else 1.12  # valba jen při zřetelně lepší shodě
        if rise < 0.7:
            continue
        cands.append((rss * pen, name, a0, eave))
    cands.sort()
    rss, name, ridge, eave = cands[0]
    if name != "flat" and res["flat"][0] < rss * 1.05:
        name, ridge, eave = "flat", res["flat"][1], res["flat"][1]
    pitched = [c for c in cands if c[1] != "flat"]
    best_pitched = pitched[0][1] if pitched else "gable_long"
    return {"shape": name, "ridge_z": ridge, "eave_z": eave, "fit_err": rss,
            "best_pitched": best_pitched, "flat_err": res["flat"][0],
            "pitched_err": pitched[0][0] if pitched else 9.9,
            "ridge_p90": float(np.percentile(h, 90))}


RESIDENTIAL = {"house", "residential", "detached", "semidetached_house", "farm", "yes", "civic", "barn"}


def roof_from_fit(fit, rect, ground, btype, pitch_rng=(25.0, 45.0)):
    """Z fitu udělá konzistentní střechu: hřeben = p90 DMP (vyhlazení DMP snižuje
    špičky), sklon omezený na obvyklý rozsah, okap = hřeben − výška střechy."""
    L, W = rect[2], rect[3]
    shape = fit["shape"]
    ridge = max(fit["ridge_z"], fit["ridge_p90"])
    if shape == "flat" and btype in RESIDENTIAL and ridge - ground > 4.5 \
            and fit["flat_err"] > 0.6 * fit["pitched_err"]:
        shape = fit["best_pitched"]
    if shape == "flat":
        return "flat", max(ridge, ground + 2.2), max(ridge, ground + 2.2)
    half = W / 2 if shape in ("gable_long", "hipped") else L / 2
    rise_fit = ridge - fit["eave_z"]
    pitch = math.degrees(math.atan2(max(rise_fit, 0.1), max(half, 0.5)))
    pitch = min(max(pitch, pitch_rng[0]), pitch_rng[1])
    rise = half * math.tan(math.radians(pitch))
    eave = ridge - rise
    if eave < ground + 2.5:  # nízká stavba – zmenši sklon, ať stěna má aspoň 2,5 m
        eave = ground + 2.5
        ridge = max(ridge, eave + 0.5)
    return shape, eave, ridge


def main():
    dtm = np.load(os.path.join(GEO, "dtm_scene.npy")).astype(np.float64)
    dsm = np.load(os.path.join(GEO, "dsm_scene.npy")).astype(np.float64)
    ortho = np.asarray(Image.open(os.path.join(GEO, "ortho_scene.jpg")).convert("RGB"))
    gj = json.load(open(os.path.join(ROOT, "data", "okoli_local.geojson")))
    apron = json.load(open(os.path.join(ROOT, "data", "apron.json")))
    ins = json.load(open(os.path.join(ROOT, "data", "scene_inspect.json")))
    ref = json.load(open(os.path.join(ROOT, "data", "scene_reference.json")))

    # ---------------- H_ref: navázání DMR na výšky okraje zpevněné plochy modelu
    b = np.array(apron["boundary_xyz"])
    dtm_b = sample(dtm, b[:, 0], b[:, 1])
    offs = dtm_b - b[:, 2]
    H_ref = float(np.median(offs))
    print(f"H_ref = {H_ref:.2f} m n. m. (rozptyl okraje plochy: {np.percentile(offs, 10) - H_ref:+.2f} "
          f"… {np.percentile(offs, 90) - H_ref:+.2f} m)")

    # ---------------- terén ve scéně + snížení pod model pozemku
    terrain = (dtm - H_ref).astype(np.float32)
    model_polys = []
    for o in ins["objects"]:
        if o["type"] == "MESH" and o.get("hull_xy") and len(o["hull_xy"]) >= 3:
            bb = o["bbox"]
            if bb["max"][2] > 1.0 and max(bb["size"][:2]) < 40:
                model_polys.append((o["name"], [tuple(p) for p in o["hull_xy"]], bb["min"][2]))
    apron_poly = hull([(p[0], p[1]) for p in apron["boundary_xyz"]])
    rr, cc = np.mgrid[0:N, 0:N]
    gx = X0 + (cc + 0.5) * RES
    gy = Y1 - (rr + 0.5) * RES
    near = np.hypot(gx - CX, gy - CY) < 60
    sx, sy = gx[near], gy[near]
    region = pip(sx, sy, apron_poly) | (dist_to_edges(sx, sy, apron_poly) < 0.8)
    for name, poly, zmin in model_polys:
        if name in ("okolo", "Předsíň", "rampa", "zidka u vjezdu"):
            region |= pip(sx, sy, poly) | (dist_to_edges(sx, sy, poly) < 0.8)
    # cílová výška = nejbližší okrajový bod plochy − 0,10 m
    from scipy.spatial import cKDTree
    kd = cKDTree(b[:, :2])
    _, idx = kd.query(np.c_[sx[region], sy[region]])
    target = b[idx, 2] - 0.10
    tz = terrain[near]
    tz_reg = np.minimum(tz[region], target)
    tz[region] = tz_reg
    terrain[near] = tz
    np.save(os.path.join(GEO, "terrain_z.npy"), terrain)
    print(f"terrain z range {terrain.min():.1f} … {terrain.max():.1f}; lowered cells under model: {region.sum()}")

    # ---------------- budovy z OSM
    osm_b = [f for f in gj["features"] if f["properties"]["kind"] == "building"
             and f["geometry"]["type"] == "Polygon"]
    mask_b = Image.new("L", (N, N), 0)
    drw = ImageDraw.Draw(mask_b)
    for f in osm_b:
        drw.polygon([((x - X0) / RES, (Y1 - y) / RES) for x, y in f["geometry"]["coordinates"][0]], fill=1)
    B_osm = np.array(mask_b, bool)
    nd = dsm - dtm

    buildings = []
    stat = {"dsm": 0, "fallback": 0}
    rng = np.random.default_rng(122)
    for f in osm_b:
        p = f["properties"]
        poly = open_ring(f["geometry"]["coordinates"][0])
        if len(poly) < 3:
            continue
        xs = [q[0] for q in poly]
        ys = [q[1] for q in poly]
        if math.hypot(np.mean(xs) - CX, np.mean(ys) - CY) > R_MAX:
            continue
        rect = mar(poly)
        # hranice – nejnižší terén
        bx, by = [], []
        for i in range(len(poly)):
            (x1, y1), (x2, y2) = poly[i], poly[(i + 1) % len(poly)]
            k = max(2, int(math.hypot(x2 - x1, y2 - y1)))
            bx += list(np.linspace(x1, x2, k, endpoint=False))
            by += list(np.linspace(y1, y2, k, endpoint=False))
        bx, by = np.array(bx), np.array(by)
        g = sample(terrain, bx, by)
        base_z, ground_mean = float(g.min()), float(np.median(g))
        # body uvnitř (0,5 m mřížka), ≥ 0,6 m od obrysu
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
        ndv = sample(nd, px, py) if len(px) else np.array([0.0])
        if len(px) >= 6 and np.median(ndv) > 1.8:
            h = sample(dsm, px, py) - H_ref
            fit = fit_roof(px, py, h, rect)
            if fit["ridge_p90"] - ground_mean > 30:  # nesmysl (věž/strom) – omez
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
            L, W = rect[2], rect[3]
            rise = 0.0 if small else (W / 2) * math.tan(math.radians(38))
            entry.update(shape="flat" if small else "gable_long", eave_z=round(ground_mean + wall, 3),
                         ridge_z=round(ground_mean + wall + rise, 3), height_source="OSM tags (není v DMP)")
            stat["fallback"] += 1
        # barva střechy z ortofota (medián ve zmenšeném půdorysu)
        if len(px):
            rr_, cc_ = rc(px, py, ORES)
            rr_ = np.clip(np.round(rr_).astype(int), 0, ortho.shape[0] - 1)
            cc_ = np.clip(np.round(cc_).astype(int), 0, ortho.shape[1] - 1)
            col = np.median(ortho[rr_, cc_], axis=0) / 255.0
        else:
            col = np.array([0.5, 0.3, 0.25])
        entry["roof_rgb"] = [round(float(v), 3) for v in col]
        entry["facade_rgb"] = list(FACADE_TINTS[int(rng.integers(len(FACADE_TINTS)))])
        buildings.append(entry)

    # ---------------- nezmapované stavby (kůlny, garáže) z DMP
    small = np.asarray(Image.fromarray(ortho).resize((N, N), Image.BOX)).astype(np.float64) / 255.0
    R_, G_, B_ = small[..., 0], small[..., 1], small[..., 2]
    exg = (2 * G_ - R_ - B_) / np.maximum(R_ + G_ + B_, 1e-3)
    veg = exg > 0.04
    rad = np.hypot(gx - CX, gy - CY)
    model_mask = np.zeros((N, N), bool)
    for name, poly, _ in model_polys:
        m_ = Image.new("L", (N, N), 0)
        ImageDraw.Draw(m_).polygon([((x - X0) / RES, (Y1 - y) / RES) for x, y in poly], fill=1)
        model_mask |= np.array(m_, bool)
    model_mask = ndimage.binary_dilation(model_mask, iterations=3)
    struct = (nd > 2.2) & ~veg & ~ndimage.binary_dilation(B_osm, iterations=2) & ~model_mask & (rad < R_MAX)
    struct = ndimage.binary_opening(struct, iterations=1)
    lab, nlab = ndimage.label(struct)
    extra = 0
    for i, sl in enumerate(ndimage.find_objects(lab), start=1):
        comp = lab[sl] == i
        area = comp.sum() * RES * RES
        if area < 10 or area > 400:
            continue
        rows, cols = np.nonzero(comp)
        xs_ = X0 + (cols + sl[1].start + 0.5) * RES
        ys_ = Y1 - (rows + sl[0].start + 0.5) * RES
        pts = [(x + dx, y + dy) for x, y in zip(xs_, ys_) for dx in (-.5, .5) for dy in (-.5, .5)]
        rect = mar(pts)
        if area / max(rect[2] * rect[3], 1e-6) < 0.6 or rect[3] < 2.0:
            continue  # nepravidelné = spíš vegetace/stín
        cx_, cy_, L, W, a = rect
        c, s = math.cos(a), math.sin(a)
        poly = [(cx_ + u * c - v * s, cy_ + u * s + v * c) for u, v in
                ((-L / 2, -W / 2), (L / 2, -W / 2), (L / 2, W / 2), (-L / 2, W / 2))]
        g = sample(terrain, [q[0] for q in poly], [q[1] for q in poly])
        gxs, gys = xs_, ys_
        h = sample(dsm, gxs, gys) - H_ref
        fit = fit_roof(gxs, gys, h, rect)
        gm = float(np.median(g))
        shape_d, eave, ridge_d = roof_from_fit(fit, rect, gm, "shed", pitch_rng=(10.0, 45.0))
        fit["shape"], fit["ridge_z"] = shape_d, ridge_d
        rr_, cc_ = rc(gxs, gys, ORES)
        col = np.median(ortho[np.clip(np.round(rr_).astype(int), 0, ortho.shape[0] - 1),
                              np.clip(np.round(cc_).astype(int), 0, ortho.shape[1] - 1)], axis=0) / 255.0
        buildings.append({"osm_id": f"dmp_{i}", "source": "dmp_detected", "polygon": [list(q) for q in poly],
                          "building": "shed", "base_z": round(float(g.min()) - 0.2, 3), "ground_z": round(gm, 3),
                          "rect": [round(v, 4) for v in rect], "shape": fit["shape"],
                          "eave_z": round(eave, 3), "ridge_z": round(max(fit["ridge_z"], eave), 3),
                          "height_source": "DMP1G", "roof_rgb": [round(float(v), 3) for v in col],
                          "facade_rgb": [0.8, 0.78, 0.74]})
        extra += 1
    shapes = {}
    for bdg in buildings:
        shapes[bdg["shape"]] = shapes.get(bdg["shape"], 0) + 1
    print(f"buildings: osm={len(osm_b)} used={len(buildings) - extra} (DMP {stat['dsm']}, fallback "
          f"{stat['fallback']}), detected extra={extra}, shapes={shapes}")

    # ---------------- stromy z DMP − DMR
    B_all = Image.new("L", (N, N), 0)
    drw = ImageDraw.Draw(B_all)
    for bdg in buildings:
        drw.polygon([((x - X0) / RES, (Y1 - y) / RES) for x, y in bdg["polygon"]], fill=1)
    B_all = ndimage.binary_dilation(np.array(B_all, bool), iterations=2)
    ndv = ndimage.gaussian_filter(nd, 0.5)
    tree_mask = (nd > 2.5) & ~B_all & (exg > -0.03) & (rad < R_MAX) & ~model_mask
    peaks = (ndv == ndimage.maximum_filter(ndv, size=3)) & tree_mask & (ndv > 3.0)
    pr, pc = np.nonzero(peaks)
    # koruny: přiřazení pixelů vegetace k nejbližšímu vrcholu
    markers = np.zeros((N, N), np.int32)
    markers[pr, pc] = np.arange(1, len(pr) + 1)
    _, (ir, ic) = ndimage.distance_transform_edt(markers == 0, return_indices=True)
    owner = markers[ir, ic] * tree_mask
    # DMP 1G je vyhlazený – v hustých skupinách splyne víc korun do jednoho segmentu.
    # Segment větší než typická koruna (r ≈ 0,3·h + 1) se vyplní více stromy
    # (farthest-point výběr pixelů segmentu), výška = nDSM v daném bodě.
    seeds = []
    for k, sl in enumerate(ndimage.find_objects(owner), start=1):
        if sl is None:
            continue
        rows, cols = np.nonzero(owner[sl] == k)
        rows, cols = rows + sl[0].start, cols + sl[1].start
        A = len(rows) * RES * RES
        h0 = float(nd[pr[k - 1], pc[k - 1]])
        r_t = float(np.clip(0.3 * h0 + 1.0, 1.5, 5.0))
        n = max(1, int(round(A / (math.pi * r_t * r_t) * 0.8)))
        chosen = [(pr[k - 1], pc[k - 1])]
        if n > 1:
            d2 = (rows - chosen[0][0]) ** 2 + (cols - chosen[0][1]) ** 2
            for _ in range(n - 1):
                j = int(np.argmax(d2))
                if d2[j] < (1.4 * r_t / RES) ** 2:
                    break
                chosen.append((rows[j], cols[j]))
                d2 = np.minimum(d2, (rows - rows[j]) ** 2 + (cols - cols[j]) ** 2)
        r_each = math.sqrt(A / len(chosen) / math.pi)
        for (r0, c0) in chosen:
            if nd[r0, c0] > 2.5:
                seeds.append((r0, c0, float(nd[r0, c0]), r_each))
    trees = []
    for (r0, c0, h, r) in seeds:
        x = X0 + (c0 + 0.5) * RES
        y = Y1 - (r0 + 0.5) * RES
        r = float(np.clip(r, 1.0, 0.45 * h + 1.0))
        rr_, cc_ = rc([x], [y], ORES)
        rr0, cc0 = int(rr_[0]), int(cc_[0])
        win = ortho[max(0, rr0 - 6):rr0 + 7, max(0, cc0 - 6):cc0 + 7].reshape(-1, 3) / 255.0
        col = np.median(win, axis=0)
        trees.append({"x": round(x, 2), "y": round(y, 2), "z": round(float(sample(terrain, [x], [y])[0]), 2),
                      "h": round(h, 2), "r": round(r, 2), "rgb": [round(float(v), 3) for v in col]})
    # jehličnany: tmavé, modravé koruny s úzkým poměrem r/h
    if trees:
        v = np.array([sum(t["rgb"]) / 3 for t in trees])
        thr = np.percentile(v, 20)
        for t, vv in zip(trees, v):
            t["type"] = "con" if vv < thr and t["r"] / t["h"] < 0.35 else "dec"
    print(f"trees: {len(trees)} (h median {np.median([t['h'] for t in trees]):.1f} m, "
          f"con {sum(t['type'] == 'con' for t in trees)})")

    json.dump({"H_ref": H_ref, "note": "z_scene = nadm. výška (Bpv) − H_ref; terén: geodata/terrain_z.npy",
               "apron_offset_p10_p90": [float(np.percentile(offs, 10) - H_ref),
                                        float(np.percentile(offs, 90) - H_ref)]},
              open(os.path.join(ROOT, "data", "terrain_ref.json"), "w"), indent=2)
    json.dump(buildings, open(os.path.join(ROOT, "data", "buildings_3d.json"), "w"))
    json.dump(trees, open(os.path.join(ROOT, "data", "trees_ndsm.json"), "w"))


if __name__ == "__main__":
    main()
