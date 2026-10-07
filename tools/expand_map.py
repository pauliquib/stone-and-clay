"""B2.3 – rozšíření DETAILNÍ mapy na union mřížku (5 okolních obcí s rezervou).

HYBRID strategie (rozhodnuto ve fázi B1):
  * stará mřížka (2626×2302, x0=-3387.279, z0=-2410.444) zůstane BAJTOVĚ zachována
    jako blok v nové mřížce (offset col+1381, row+768 – fázově sladěná 2 m buňka),
  * nové území se vygeneruje čistě v Pythonu z geodata/*_union_scene.npy
    (bez Blenderu) – DMR 5G + mikroreliéf (stejná funkce/seed jako export_map.py)
    + srovnání pod silnicemi (vzor export_map.py, z okoli_union_local.geojson),
  * normály se počítají z CELÉ hm_vis → švy mezi blokem a novým územím jsou
    konzistentní (žádný viditelný zlom osvětlení).

Vstupy (připraví B2.1/B2.2):
  geodata/dtm_union_scene.npy, dsm_union_scene.npy, ortho_union_scene.jpg
  pipeline/data/geodata_meta_union.json, okoli_union_local.geojson, osm_raw_union.json

Výstupy (data/, mimo git – kromě map.json):
  terrain_height.bin     – vizuální výšky f32 w·h (mikroreliéf jen na nových buňkách)
  terrain_collision.bin  – čisté DMR/2 (bez mikroreliéfu, se snížením pod silnicemi)
  terrain_normal.bin     – u8 w·h·3 z celé vizuální mřížky
  terrain_chunks.bin     – f32 ncz·ncx·2 min/max po chunk_cells buňkách
  trees.bin              – staré instance VERBATIM + nové dosazené (indexy starých
                           stromů se NESMÍ posunout – save kompatibilita, drop_trees)
  map.json               – height/ortho_full meta + roads přegenerované z union
                           extraktu; ostatní klíče (items, boundary, spawn…) VERBATIM
  textures/ortho_full.jpg ← geodata/ortho_union_scene.jpg

Spuštění: python3 tools/expand_map.py
"""
import json
import math
import os
import random
import shutil
import struct
import sys

import numpy as np
from PIL import Image, ImageDraw

Image.MAX_IMAGE_PIXELS = None
HERE = os.path.dirname(os.path.abspath(__file__))
GAME = os.path.dirname(HERE)
PIPE = os.path.join(GAME, "pipeline")
PDATA = os.path.join(PIPE, "data")
GEO = os.path.join(GAME, "geodata")
DATA = os.path.join(GAME, "data")
TEX = os.path.join(GAME, "textures")
PSCRIPTS = os.path.join(PIPE, "scripts")
sys.path.insert(0, PSCRIPTS)
sys.path.insert(0, HERE)
from fetch_geodata_union import union_grid, load_old_meta  # noqa: E402
import obce  # noqa: E402  (FICTIONAL_NAMES, fname_road – hygienický filtr názvů)

CHUNK_CELLS = 128     # dlaždice terénu 256 m – terrain.gd LOD úrovně odvozuje z chunk_cells
                      # (LOD0 = chunk_cells čtverců = 2 m rozlišení jako dosud); oproti 64
                      # → ~4× méně MeshInstance3D uzlů na 21Mvrcholové mřížce
ROAD_CLIP_M = 8.0     # silnice grafu se oříznou takhle před okrajem mřížky (neviditelná stěna ~4 m)

# silniční pásy pro srovnání terénu – šířky jako pipeline/scripts/phase13_build_full.py
ROAD_W = {"secondary": 7, "tertiary": 6.5, "unclassified": 5.5, "residential": 5.5,
          "living_street": 5, "service": 3.5, "track": 3, "path": 1.5, "footway": 1.8,
          "cycleway": 2}
ROAD_STEP = 2.5       # zahuštění osy pro flatten (jako phase13.densify)

# vegetace (parametry scatteru = phase13)
FOREST_TARGET = 16000      # pro plochu ~20 km² staré masky; na union se škáluje poměrem plochy
GARDEN_TARGET = 4000
NDSM_TREES = True          # příměs stromů z nDSM (koruny > NDSM_MIN mimo OSM les/zástavbu/pole)
NDSM_MIN = 5.0
NDSM_TARGET_FRACTION = 0.5  # nDSM scatter cíl = tolik procent z cíle lesa přepočteného na jeho plochu


# ------------------------------------------------------------------ kopie z export_map.py
# (export_map.py nelze importovat – nahoře má `import bpy`)

def _box_mean(a, r):
    """Separabilní klouzavý průměr (okno 2r+1) přes obě osy, okraje zrcadlené (reflect)."""
    for ax in (0, 1):
        pad = [(0, 0), (0, 0)]
        pad[ax] = (r, r)
        p = np.pad(a, pad, mode="reflect")
        c = np.concatenate([np.zeros_like(p[:1] if ax == 0 else p[:, :1]), p.cumsum(axis=ax)], axis=ax)
        lo = [slice(None), slice(None)]
        hi = [slice(None), slice(None)]
        lo[ax] = slice(0, -(2 * r + 1))
        hi[ax] = slice(2 * r + 1, None)
        a = (c[tuple(hi)] - c[tuple(lo)]) / float(2 * r + 1)
    return a


def microrelief(rows, cols):
    """Stejná funkce/seed jako export_map.py (§12.1): dvě oktávy boxem vyhlazeného
    hodnotového šumu ±0,2 m. Aplikuje se JEN na nové buňky – starý blok má svůj
    mikroreliéf zapečený v terrain_height.bin a zůstává bajtově."""
    rng = np.random.default_rng(0x9E5A)
    wide = _box_mean(_box_mean(rng.standard_normal((rows, cols)), 7), 8)
    fine = _box_mean(rng.standard_normal((rows, cols)), 2)
    m = wide / np.abs(wide).max() * 0.14 + fine / np.abs(fine).max() * 0.06
    return m


def srgb_to_lin(c):
    c = np.asarray(c, float)
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def bilinear(arr, x0, y1, res, x, y):
    """arr[řádek od severu, sloupec]; středy pixelů v x0+(c+.5)res, y1-(r+.5)res."""
    x, y = np.asarray(x, float), np.asarray(y, float)
    r = np.clip((y1 - y) / res - 0.5, 0, arr.shape[0] - 1.001)
    c = np.clip((x - x0) / res - 0.5, 0, arr.shape[1] - 1.001)
    r0, c0 = np.floor(r).astype(int), np.floor(c).astype(int)
    fr, fc = r - r0, c - c0
    return (arr[r0, c0] * (1 - fr) * (1 - fc) + arr[r0, c0 + 1] * (1 - fr) * fc +
            arr[r0 + 1, c0] * fr * (1 - fc) + arr[r0 + 1, c0 + 1] * fr * fc)


def point_in_poly(x, y, poly):
    x, y = np.asarray(x, float), np.asarray(y, float)
    ins = np.zeros(x.shape, bool)
    n = len(poly)
    for i in range(n):
        x1, y1 = poly[i]
        x2, y2 = poly[(i + 1) % n]
        cond = (y1 > y) != (y2 > y)
        xi = (x2 - x1) * (y - y1) / ((y2 - y1) if y2 != y1 else 1e-12) + x1
        ins ^= cond & (x < xi)
    return ins


# ------------------------------------------------------------------ pomocné

def jload(rel):
    return json.load(open(os.path.join(PDATA, rel), encoding="utf-8"))


def load_gj():
    return jload("okoli_union_local.geojson")["features"]


def place_names():
    """Reálná toponyma pro hygienický filtr názvů – preferuje place_names
    z celého kraje (osm_raw_union.json), jinak place uzly uvnitř bbox."""
    out = set()
    p = os.path.join(PDATA, "osm_raw_union.json")
    if os.path.exists(p):
        raw = json.load(open(p, encoding="utf-8"))
        out.update(raw.get("place_names", ()))
        for e in raw["elements"]:
            if e["type"] == "node" and "place" in e.get("tags", {}) and e["tags"].get("name"):
                out.add(e["tags"]["name"])
    return out


def densify(pts, step=ROAD_STEP):
    out = [pts[0]]
    for (x1, y1), (x2, y2) in zip(pts[:-1], pts[1:]):
        L = math.hypot(x2 - x1, y2 - y1)
        k = max(1, int(L / step))
        for i in range(1, k + 1):
            out.append((x1 + (x2 - x1) * i / k, y1 + (y2 - y1) * i / k))
    return out


# ------------------------------------------------------------------ 0: snapshot před expanzí

PRE_EXPAND = os.path.join(PDATA, "pre_expand")
# zdroje, které expand_map přepisuje – bez snapshotu by re-run četl už rozšířená
# data jako „staré" (dvojité dosazení stromů, špatný grid). Snapshot se udělá
# při prvním běhu a pak se čte VŽDY odtud (idempotentní skript).
KEEP_SRC = ("map.json", "terrain_height.bin", "terrain_collision.bin",
            "trees.bin", "water.json")


def backup_originals():
    os.makedirs(PRE_EXPAND, exist_ok=True)
    made = []
    for fn in KEEP_SRC:
        src = os.path.join(DATA, fn)
        dst = os.path.join(PRE_EXPAND, fn)
        if os.path.exists(src) and not os.path.exists(dst):
            shutil.copy(src, dst)
            made.append(fn)
    if made:
        print("pre-expand snapshot →", PRE_EXPAND, ":", ", ".join(made))
    return PRE_EXPAND


# ------------------------------------------------------------------ 1: mřížka a terén

def build_terrain(g, meta_old, feats, pe):
    """Nová výšková mřížka → (hm_vis f32, hm_coll_src f64, seam report dict)."""
    sp = g["spacing"]
    W, H = g["w"], g["h"]
    ho, wo = meta_old["height"]["h"], meta_old["height"]["w"]
    ro, co = g["row_off"], g["col_off"]

    dtm = np.load(os.path.join(GEO, "dtm_union_scene.npy")).astype(np.float64)
    h_ref = jload("terrain_ref.json")["H_ref"]
    if dtm.shape != (H, W):
        raise RuntimeError(f"dtm_union_scene.npy má {dtm.shape}, čeká se {(H, W)} – "
                           "přegeneruj tools/fetch_geodata_union.py")
    hm = dtm - h_ref                      # čistá DMR v herních výškách (scéna)
    base = hm.copy()                      # výšky vozovky se vzorkují z NEupraveného DMR

    # --- srovnání pod silnicemi (vzor export_map.py): jen nové buňky
    # starý blok už má flatten zapečený z DBM1 geometrie – tam se nesahá.
    new_cell = np.ones((H, W), bool)
    new_cell[ro:ro + ho, co:co + wo] = False
    gx0 = g["x0"]                        # vrcholová souřadnice (x = scéna x; řádek ↔ z)
    gz0 = g["z0"]

    def _h_at_grid(arr, g_, x, z):
        # arr[r,c]: r ↔ z (od z0 dolů); bilineárně v (x, z)
        fx = np.clip((np.asarray(x, float) - g_["x0"]) / sp, 0, W - 1.001)
        fz = np.clip((np.asarray(z, float) - g_["z0"]) / sp, 0, H - 1.001)
        ix, iz = np.floor(fx).astype(int), np.floor(fz).astype(int)
        tx, tz = fx - ix, fz - iz
        a, b = arr[iz, ix], arr[iz, ix + 1]
        c, d = arr[iz + 1, ix], arr[iz + 1, ix + 1]
        return (a * (1 - tx) + b * tx) * (1 - tz) + (c * (1 - tx) + d * tx) * tz

    lowered = 0
    ch_max = 0.0
    n_flat_segs = 0
    for ft in feats:
        p = ft["properties"]
        if p["kind"] != "highway" or ft["geometry"]["type"] != "LineString":
            continue
        hw = p.get("highway", "")
        w_road = ROAD_W.get(hw)
        if w_road is None:
            continue
        pts = ft["geometry"]["coordinates"]
        if len(pts) < 2:
            continue
        dens = densify([tuple(q) for q in pts])     # scéna (x, y)
        n_flat_segs += len(dens) - 1
        rad = w_road / 2 + 1.4                      # pokrytí pásu (≈ pás + ~1 buňka)
        for i in range(1, len(dens)):
            px, py = dens[i]
            gz_ = -py                                # Godot z = −scéna y
            # úzký bbox okolo bodu → jen lokální buňky
            cx = int((px - gx0) / sp)
            cz = int((gz_ - gz0) / sp)
            k = int(math.ceil(rad / sp)) + 1
            x_lo, x_hi = max(cx - k, 0), min(cx + k + 1, W)
            z_lo, z_hi = max(cz - k, 0), min(cz + k + 1, H)
            if x_hi <= x_lo or z_hi <= z_lo:
                continue
            if not new_cell[z_lo:z_hi, x_lo:x_hi].any():
                continue
            # výška vozovky: max z osy a obou okrajů pásu (+0,06 jako phase13)
            ax_, ay_ = dens[i - 1]
            bx_, by_ = dens[i]
            dx, dy = bx_ - ax_, by_ - ay_
            L = math.hypot(dx, dy) or 1.0
            nx_, ny_ = -dy / L * w_road / 2, dx / L * w_road / 2
            zc = _h_at_grid(base, g, px, gz_)
            zl = _h_at_grid(base, g, px + nx_, gz_ - ny_)
            zr = _h_at_grid(base, g, px - nx_, gz_ + ny_)
            z_road = max(float(zc), float(zl), float(zr)) + 0.06 - 0.08
            xs = gx0 + np.arange(x_lo, x_hi) * sp
            zs = gz0 + np.arange(z_lo, z_hi) * sp
            XS, ZS = np.meshgrid(xs, zs)
            dd = np.hypot(XS - px, ZS - gz_)
            hit = (dd <= rad) & new_cell[z_lo:z_hi, x_lo:x_hi]
            if not hit.any():
                continue
            sl = (slice(z_lo, z_hi), slice(x_lo, x_hi))
            cur = hm[sl]
            newv = np.where(hit, np.minimum(cur, z_road), cur)
            dd2 = cur - newv
            hm[sl] = newv
            lowered += int((dd2 > 0).sum())
            if (dd2 > 0).any():
                ch_max = max(ch_max, float(dd2.max()))
    print(f"ROAD FLATTEN (nové území): {lowered} buněk sníženo, max {ch_max:.2f} m, "
          f"vzorků os {n_flat_segs}")

    # --- kolize: čistá DMR / sp (HeightMapShape3D se škáluje ×spacing)
    hm_coll = hm / sp

    # --- vizuální: + mikroreliéf jen na nových buňkách
    mr = microrelief(H, W)
    hm_vis = hm + mr * new_cell
    # starý blok VERBATIM ze snapshotu (ne z přepisovaných binů)
    th_old = np.fromfile(os.path.join(pe, "terrain_height.bin"), np.float32).reshape(ho, wo)
    tc_old = np.fromfile(os.path.join(pe, "terrain_collision.bin"), np.float32).reshape(ho, wo)
    assert th_old.shape == (ho, wo) and tc_old.shape == (ho, wo)
    hm_vis[ro:ro + ho, co:co + wo] = th_old
    hm_coll[ro:ro + ho, co:co + wo] = tc_old

    def seam_stat(hv, old):
        edges = {
            "left": (hv[ro:ro + ho, co - 1], old[:, 0]),
            "right": (hv[ro:ro + ho, co + wo], old[:, -1]),
            "top": (hv[ro - 1, co:co + wo], old[0, :]),
            "bottom": (hv[ro + ho, co:co + wo], old[-1, :]),
        }
        return {k: {"mean": round(float(np.abs(a.astype(np.float64) - b.astype(np.float64)).mean()), 4),
                    "p95": round(float(np.percentile(np.abs(a.astype(np.float64) - b.astype(np.float64)), 95)), 4),
                    "max": round(float(np.abs(a.astype(np.float64) - b.astype(np.float64)).max()), 3)}
                for k, (a, b) in edges.items()}

    seam_raw = seam_stat(hm_vis, th_old)

    # --- navázání švu: delta (starý okraj − nová hodnota) rozprostřená do pásu
    # K buněk VNĚ bloku s lineárním útlumem. Starý blok se nemění (bajtově),
    # nová strana přibere na hranici → šev pod hladinou mikroreliéfu.
    def feather(field, old_block, K=10):
        from scipy import ndimage
        outside = np.ones((H, W), bool)
        outside[ro:ro + ho, co:co + wo] = False
        ring1 = ndimage.binary_dilation(~outside, iterations=1) & outside
        oldv = np.zeros((H, W), field.dtype)
        oldv[ro:ro + ho, co:co + wo] = old_block
        _d0, ii = ndimage.distance_transform_edt(outside, return_indices=True)
        delta = np.zeros((H, W), np.float64)
        delta[ring1] = oldv[tuple(ii[:, ring1])] - field[ring1]
        dist, idx2 = ndimage.distance_transform_edt(~ring1, return_indices=True)
        field += (delta[tuple(idx2)] * np.clip(1.0 - dist / K, 0.0, 1.0)) * outside

    feather(hm_vis, th_old)
    feather(hm_coll, tc_old)

    # --- šev: |nová − stará| podél hranic bloku PO vyhlazení (0 = plynulé navázání)
    seam = seam_stat(hm_vis, th_old)
    print("SEAM |Δ| před feather:", seam_raw, "→ po:", seam)
    return hm_vis.astype(np.float32), hm_coll, seam, seam_raw


def write_terrain_bins(g, hm_vis, hm_coll):
    sp = g["spacing"]
    W, H = g["w"], g["h"]
    hm_vis.tofile(os.path.join(DATA, "terrain_height.bin"))
    hm_coll.astype(np.float32).tofile(os.path.join(DATA, "terrain_collision.bin"))
    gz, gx = np.gradient(hm_vis.astype(np.float64), sp)
    n = np.stack([-gx, np.ones_like(hm_vis), -gz], axis=-1)
    n /= np.linalg.norm(n, axis=-1, keepdims=True)
    ((n * 0.5 + 0.5) * 255).round().astype(np.uint8).tofile(
        os.path.join(DATA, "terrain_normal.bin"))
    ncx = math.ceil((W - 1) / CHUNK_CELLS)
    ncz = math.ceil((H - 1) / CHUNK_CELLS)
    mm = np.zeros((ncz, ncx, 2), np.float32)
    for iz in range(ncz):
        for ix in range(ncx):
            blk = hm_vis[iz * CHUNK_CELLS:iz * CHUNK_CELLS + CHUNK_CELLS + 1,
                         ix * CHUNK_CELLS:ix * CHUNK_CELLS + CHUNK_CELLS + 1]
            mm[iz, ix] = blk.min(), blk.max()
    mm.tofile(os.path.join(DATA, "terrain_chunks.bin"))
    print(f"WROTE terrain bins: {W}×{H} (height/collision {W * H * 4 / 1e6:.0f} MB), "
          f"chunks {ncx}×{ncz} po {CHUNK_CELLS}")
    return ncx, ncz


# ------------------------------------------------------------------ 2: stromy

def scatter_mask(feats, g, W, H):
    """Rastrové masky na union DEM mřížce: forest / residential / farmland / water /
    block (budovy+silnice, dilatováno). Vzorně podle phase12_analyze_full.py."""
    sp = g["spacing"]
    X0, Y1 = g["grid_x0"], g["grid_y1"]

    def px(pts):    # scéna (x,y) → (col,row) float
        return [((x - X0) / sp, (Y1 - y) / sp) for x, y in pts]

    img_f = Image.new("L", (W, H), 0)
    img_r = Image.new("L", (W, H), 0)
    img_farm = Image.new("L", (W, H), 0)
    img_w = Image.new("L", (W, H), 0)
    img_b = Image.new("L", (W, H), 0)
    df, dr, dfarm, dw, db = (ImageDraw.Draw(i) for i in (img_f, img_r, img_farm, img_w, img_b))
    forest_types = {"forest", "wood", "scrub"}
    resid_types = {"residential"}
    farm_types = {"farmland", "meadow", "grass", "grassland", "pasture"}
    n = {"f": 0, "r": 0, "farm": 0, "w": 0, "b": 0}
    for ft in feats:
        p = ft["properties"]
        k = p["kind"]
        geo = ft["geometry"]
        if k == "landuse" and geo["type"] == "Polygon":
            t = p.get("landuse") or p.get("natural") or p.get("leisure")
            ring = px(geo["coordinates"][0])
            if t in forest_types:
                df.polygon(ring, fill=1)
                n["f"] += 1
            elif t in resid_types:
                dr.polygon(ring, fill=1)
                n["r"] += 1
            elif t in farm_types:
                dfarm.polygon(ring, fill=1)
                n["farm"] += 1
        elif k == "water" and geo["type"] == "Polygon":
            dw.polygon(px(geo["coordinates"][0]), fill=1)
            n["w"] += 1
        elif k == "building" and geo["type"] == "Polygon":
            db.polygon(px(geo["coordinates"][0]), fill=1)
            n["b"] += 1
        elif k == "highway" and geo["type"] == "LineString":
            line = px([tuple(q) for q in geo["coordinates"]])
            if len(line) >= 2:
                db.line(line, fill=1, width=max(2, int(round(7.0 / sp))))
    from scipy import ndimage
    block = np.array(img_b, bool)
    block = ndimage.binary_dilation(block, iterations=max(1, int(round(4.0 / sp))))
    return (np.array(img_f, bool), np.array(img_r, bool), np.array(img_farm, bool),
            np.array(img_w, bool), block, n)


def scatter_trees(g, hm_vis, feats, meta_old):
    """Scatter stromů na union mřížce (logika phase13.scatter bez bpy) → řádky DBI1."""
    sp = g["spacing"]
    W, H = g["w"], g["h"]
    ro, co = g["row_off"], g["col_off"]
    ho, wo = meta_old["height"]["h"], meta_old["height"]["w"]
    forest, resid, farm, water, block, n_poly = scatter_mask(feats, g, W, H)

    # starý blok nescatterujeme (tam jsou původní instance VERBATIM)
    old_block = np.zeros((H, W), bool)
    old_block[ro:ro + ho, co:co + wo] = True
    avail = ~block & ~old_block
    mf = forest & avail
    mr = resid & avail
    if NDSM_TREES:
        dtm = np.load(os.path.join(GEO, "dtm_union_scene.npy")).astype(np.float64)
        dsm = np.load(os.path.join(GEO, "dsm_union_scene.npy")).astype(np.float64)
        ndsm = dsm - dtm
        extra = (ndsm > NDSM_MIN) & avail & ~mf & ~mr & ~farm & ~water
        from scipy import ndimage as _ndi
        extra = _ndi.binary_opening(extra, iterations=1)   # odstraní 1px šum
        print(f"nDSM supplement: {int(extra.sum())} buněk navíc nad {NDSM_MIN} m")
        mf |= extra

    def h_at(x, z):
        fx = np.clip((x - g["x0"]) / sp, 0, W - 1.001)
        fz = np.clip((z - g["z0"]) / sp, 0, H - 1.001)
        ix, iz = np.floor(fx).astype(int), np.floor(fz).astype(int)
        tx, tz = fx - ix, fz - iz
        a, b = hm_vis[iz, ix], hm_vis[iz, ix + 1]
        c, d = hm_vis[iz + 1, ix], hm_vis[iz + 1, ix + 1]
        return (a * (1 - tx) + b * tx) * (1 - tz) + (c * (1 - tx) + d * tx) * tz

    rows = []

    def scatter(mask, kind_mix, height_rng, target, name, seed):
        area_m2 = float(mask.sum()) * sp * sp
        if area_m2 < 1.0:
            print(f"{name}: prázdná maska")
            return 0
        spacing = max(3.5, math.sqrt(area_m2 / max(target, 1)))
        rnd = random.Random(seed)
        rng_np = np.random.default_rng(seed)
        xs = np.arange(g["x0"] + spacing / 2, g["x1"], spacing)
        zs = np.arange(g["z0"] + spacing / 2, g["z1"], spacing)
        gx, gz = np.meshgrid(xs, zs)
        gx = gx.ravel() + (rng_np.random(gx.size) - 0.5) * spacing * 0.8
        gz = gz.ravel() + (rng_np.random(gz.size) - 0.5) * spacing * 0.8
        r = np.clip(((gz - g["z0"]) / sp).astype(int), 0, H - 1)
        c = np.clip(((gx - g["x0"]) / sp).astype(int), 0, W - 1)
        keep = mask[r, c]
        gx, gz = gx[keep], gz[keep]
        cnt = 0
        for x, z in zip(gx, gz):
            kind = "dec" if rnd.random() < kind_mix else "con"
            h = rnd.uniform(*height_rng[kind])
            rr = h * (rnd.uniform(0.28, 0.38) if kind == "dec" else rnd.uniform(0.18, 0.26))
            tz = float(h_at(x, z)) - 0.15
            base = (rnd.uniform(0.13, 0.30), rnd.uniform(0.24, 0.42), rnd.uniform(0.06, 0.16))
            lin = srgb_to_lin(np.array(base))
            proto = rnd.randint(0, 2) if kind == "dec" else rnd.randint(3, 5)
            rows.append([x, tz, z, rnd.uniform(0, 2 * math.pi), rr, h,
                         rr * rnd.uniform(0.9, 1.1), lin[0], lin[1], lin[2], proto])
            cnt += 1
        print(f"{name}: {area_m2 / 10000:.0f} ha, krok {spacing:.1f} m → {cnt} stromů")
        return cnt

    # cíl = stará hustota přepočtená na plochu (FOREST_TARGET platilo pro ~starý katastr)
    fa_ha = float(mf.sum()) * sp * sp / 10000.0
    ra_ha = float(mr.sum()) * sp * sp / 10000.0
    # stará maska: ~20 km² katastr → hustota ~800/km² les, ~200/km² zahrady;
    # stejné zastropení: cíl ∝ ploše masky
    f_target = int(FOREST_TARGET * max(fa_ha, 1.0) / 2000.0)
    g_target = int(GARDEN_TARGET * max(ra_ha, 1.0) / 200.0)
    scatter(mf, kind_mix=0.45, height_rng={"dec": (10, 22), "con": (12, 26)},
            target=f_target, name=f"union les ({fa_ha:.0f} ha)", seed=201)
    scatter(mr, kind_mix=0.85, height_rng={"dec": (4, 10), "con": (5, 11)},
            target=g_target, name=f"union zahrady ({ra_ha:.0f} ha)", seed=401)
    return np.array(rows, np.float64) if rows else np.zeros((0, 11), np.float64)


def append_trees(new_rows, pe):
    """Staré instance VERBATIM (ze snapshotu) + nové na konec (indexy se nesmí hnout)."""
    tb = open(os.path.join(pe, "trees.bin"), "rb").read()
    assert tb[:4] == b"DBI1"
    n_old = struct.unpack_from("<i", tb, 4)[0]
    old = np.frombuffer(tb, np.float32, n_old * 11, 8).reshape(-1, 11).copy()
    out = np.concatenate([old, new_rows.astype(np.float32)])
    with open(os.path.join(DATA, "trees.bin"), "wb") as f:
        f.write(b"DBI1")
        f.write(struct.pack("<i", len(out)))
        f.write(out.tobytes())
    print(f"WROTE trees.bin: {n_old} starých + {len(new_rows)} nových = {len(out)}")


# ------------------------------------------------------------------ 3: map.json

def rebuild_roads(g, feats, pnames):
    """roads[] z union extraktu: všechny highway LineStringy v nové mřížce
    (oříznuté na rect − ROAD_CLIP_M), jména přes FICTIONAL_NAMES + fname_road."""
    x0, x1 = g["x0"] + ROAD_CLIP_M, g["x1"] - ROAD_CLIP_M
    z0, z1 = g["z0"] + ROAD_CLIP_M, g["z1"] - ROAD_CLIP_M
    roads = []
    dropped_names = {}
    for ft in feats:
        p = ft["properties"]
        if p["kind"] != "highway" or ft["geometry"]["type"] != "LineString":
            continue
        if p.get("highway", "") not in ROAD_W:
            continue  # steps/raceway/bridleway/construction apod. – stejný vesmír druhů
                      # jako měl původní export (traffic boti po nich nejezdí)
        pts = [(q[0], -q[1]) for q in ft["geometry"]["coordinates"]]  # scéna y → Godot z
        nm = p.get("name", "").strip()
        name = ""
        if len(nm) >= 3:                      # „w" apod. junk názvy rovnou zahodit
            fn = obce.fname_road(nm, pnames)
            if fn is None:
                dropped_names[nm] = dropped_names.get(nm, 0) + 1
            else:
                name = fn
        run = []
        for q in pts:
            if x0 <= q[0] <= x1 and z0 <= q[1] <= z1:
                run.append(q)
            elif len(run) >= 2:
                roads.append({"kind": p.get("highway", ""), "name": name,
                              "pts": [[round(a, 2), round(b, 2)] for a, b in run]})
                run = []
            else:
                run = []
        if len(run) >= 2:
            roads.append({"kind": p.get("highway", ""), "name": name,
                          "pts": [[round(a, 2), round(b, 2)] for a, b in run]})
    if dropped_names:
        print("ROAD names dropped (reálné toponymum):",
              ", ".join(f"{k}×{v}" for k, v in sorted(dropped_names.items())))
    kinds = {}
    for r in roads:
        kinds[r["kind"]] = kinds.get(r["kind"], 0) + 1
    named = sum(1 for r in roads if r["name"])
    print(f"ROADS: {len(roads)} úseků ({named} pojmenovaných), druhy: {kinds}")
    return roads


def update_map_json(g, meta_old, ncx, ncz, roads):
    mp = dict(meta_old)                       # VERBATIM všechny klíče…
    hm = meta_old["height"]
    mp["height"] = {**hm, "w": g["w"], "h": g["h"], "spacing": g["spacing"],
                    "x0": g["x0"], "z0": g["z0"],
                    "chunk_cells": CHUNK_CELLS, "ncx": ncx, "ncz": ncz}
    mp["ortho_full"] = {**meta_old.get("ortho_full", {}),
                        "file": "res://textures/ortho_full.jpg",
                        "x0": g["x0"] - g["spacing"] / 2,
                        "z0": g["z0"] - g["spacing"] / 2,
                        "size_x": g["w"] * g["spacing"], "size_z": g["h"] * g["spacing"]}
    mp["roads"] = roads
    dst = os.path.join(DATA, "map.json")
    json.dump(mp, open(dst, "w"), ensure_ascii=False)
    print(f"WROTE map.json: height {g['w']}×{g['h']} @ x0={g['x0']} z0={g['z0']}, "
          f"ortho_full {mp['ortho_full']}, roads {len(roads)}")
    return mp


# ------------------------------------------------------------------ main

def main():
    pe = backup_originals()
    meta_old = load_old_meta()
    # kontrolní přepočet mřížky vs geodata_meta_union.json (musi souhlasit)
    g = union_grid(meta_old)
    mu_path = os.path.join(PDATA, "geodata_meta_union.json")
    if os.path.exists(mu_path):
        mu = json.load(open(mu_path))
        assert abs(mu["grid_x0"] - (g["x0"] - g["spacing"] / 2)) < 1e-6, \
            "mřížka z union_grid ≠ geodata_meta_union – spusť znovu fetch_geodata_union.py"
    feats = load_gj()
    print(f"geojson features: {len(feats)}")

    hm_vis, hm_coll, seam, seam_raw = build_terrain(g, meta_old, feats, pe)
    ncx, ncz = write_terrain_bins(g, hm_vis, hm_coll)

    new_rows = scatter_trees(g, hm_vis, feats, meta_old)
    append_trees(new_rows, pe)

    pnames = place_names()
    print(f"place_names pro hygienický filtr: {len(pnames)}")
    roads = rebuild_roads(g, feats, pnames)
    update_map_json(g, meta_old, ncx, ncz, roads)

    src = os.path.join(GEO, "ortho_union_scene.jpg")
    if os.path.exists(src):
        shutil.copy(src, os.path.join(TEX, "ortho_full.jpg"))
        print("ortho_full.jpg ← ortho_union_scene.jpg")
    else:
        print("POZOR: chybí ortho_union_scene.jpg – ortho_full.jpg zůstává starý")

    # ---------------- report
    W, H = g["w"], g["h"]
    old_area = (meta_old["height"]["w"] - 1) * (meta_old["height"]["h"] - 1) * 4.0
    new_area = (W - 1) * (H - 1) * 4.0
    print("\n=== EXPAND MAP REPORT ===")
    print(f"mřížka {W}×{H} @ {g['spacing']} m = {W * H:,} bodů, "
          f"{new_area / 1e6:.1f} km² (starých {old_area / 1e6:.2f} km² = "
          f"{100 * old_area / new_area:.0f} % zůstává bajtově)")
    print(f"šev |Δ| před feather: {seam_raw} → po: {seam}")
    for fn in ("terrain_height.bin", "terrain_collision.bin", "terrain_normal.bin",
               "terrain_chunks.bin", "trees.bin"):
        print(f"  {fn}: {os.path.getsize(os.path.join(DATA, fn)) / 1e6:.1f} MB")


if __name__ == "__main__":
    main()
