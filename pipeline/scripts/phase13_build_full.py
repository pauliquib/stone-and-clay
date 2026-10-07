"""Fáze 13 – sestavení rozšířeného okolí (celý katastr Doubrav) v Blenderu.

Otevře HOTOVOU scénu blend/Doubravy_3D_okoli_final_v2.blend (jádro r<=480 m,
fáze 1-7 beze změny) a PŘIDÁ novou kolekci OKOLI_FULL s:
  - terénem mimo jádro (r>450 m, mírně překrytý s jádrem kvůli spoji)
    texturovaným ortofotem celého katastru,
  - budovami mimo jádro (pipeline/data/buildings_3d_full.json),
  - silnicemi mimo jádro (pipeline/data/okoli_full_local.geojson, oříznuto na katastr),
  - lesní a zahradní vegetací (pipeline/data/forest_mask_full.npz) – procedurální
    scatter, protože individuální detekce korun (jako v jádru) není na ploše
    ~20 km2 proveditelná (miliony stromů); hustota je zastropovaná, aby scéna
    zůstala použitelná.

Materiály (fasáda/střecha/asfalt/štěrk/kůra/listí) se PŘEBÍRAJÍ z jádra
(stejné PBR sady Poly Haven) - žádné duplicity, jednotný vzhled celé mapy.

Spuštění:
  blender --background --python-exit-code 1 --python pipeline/scripts/phase13_build_full.py

Výstup: blend/mapa_okoli.blend (+ checkpoint blend/Doubravy_3D_okoli_full_v1.blend),
        pipeline/renders/phase13_full_v2.png
"""
import math
import os
import random
import sys

import bmesh
import bpy
import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import okoli_common as oc  # noqa: E402

ROOT = oc.ROOT
GEO = oc.GEO
BLEND_DIR = oc.BLEND_DIR
ref = oc.load_json("data/scene_reference.json")
tref = oc.load_json("data/terrain_ref.json")
meta = oc.load_json("data/geodata_meta_full.json")
admin = oc.load_json("data/doubravy_admin_boundary.json")
H_ref = tref["H_ref"]
HX, HY = ref["house_scene_xy"]
ADMIN_POLY = [tuple(p) for p in admin["scene_poly"]]
X0, Y1 = meta["grid_x0"], meta["grid_y1"]
DEM_RES, GW, GH = meta["dem_res"], meta["dem_w"], meta["dem_h"]
ORTHO_RES, OW, OH = meta["ortho_res"], meta["ortho_w"], meta["ortho_h"]

R_CORE = 480.0     # jádro (fáze 1-7) je hotové do tohoto poloměru
R_CUTOFF = 450.0   # rozšířený terén se generuje od tohoto poloměru (překryv ~30 m)
MESH_RES = 4.0     # m/vrchol venku (nativní DMR5G je 2 m; 4 m drží síť ~1,5 M vrcholů zvládnutelnou na tomto stroji)
Z_BIAS = -0.03     # m, rozšířený terén mírně "pod" jádrem - žádné blikání na spoji

DTM = np.load(os.path.join(GEO, "dtm_full_scene.npy")).astype(np.float64) - H_ref


def tzf(x, y):
    x = np.asarray(x, float)
    y = np.asarray(y, float)
    r = (Y1 - y) / DEM_RES - 0.5
    c = (x - X0) / DEM_RES - 0.5
    r = np.clip(r, 0, DTM.shape[0] - 1.001)
    c = np.clip(c, 0, DTM.shape[1] - 1.001)
    r0, c0 = np.floor(r).astype(int), np.floor(c).astype(int)
    fr, fc = r - r0, c - c0
    t = DTM
    return (t[r0, c0] * (1 - fr) * (1 - fc) + t[r0, c0 + 1] * (1 - fr) * fc +
            t[r0 + 1, c0] * fr * (1 - fc) + t[r0 + 1, c0 + 1] * fr * fc)


def srgb_to_lin(c):
    c = np.asarray(c, float)
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


# ------------------------------------------------------------------ materiál terénu (nová ortofoto mozaika)

def ortho_material_full():
    mat = bpy.data.materials.get("OKOLI_Teren_ortofoto_FULL")
    if mat:
        return mat
    mat = bpy.data.materials.new("OKOLI_Teren_ortofoto_FULL")
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = nt.nodes.get("Principled BSDF")
    im = nt.nodes.new("ShaderNodeTexImage")
    im.image = bpy.data.images.load(os.path.join(GEO, "ortho_full_scene.jpg"), check_existing=True)
    im.interpolation = "Cubic"
    im.extension = "EXTEND"
    uv = nt.nodes.new("ShaderNodeUVMap")
    uv.uv_map = "ortho_full"
    nt.links.new(uv.outputs["UV"], im.inputs["Vector"])
    nt.links.new(im.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.92
    tc = nt.nodes.new("ShaderNodeTexCoord")
    nz = nt.nodes.new("ShaderNodeTexNoise")
    nz.inputs["Scale"].default_value = 25.0
    nz.inputs["Detail"].default_value = 8.0
    nt.links.new(tc.outputs["Object"], nz.inputs["Vector"])
    bump = nt.nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.15
    bump.inputs["Distance"].default_value = 0.03
    nt.links.new(nz.outputs["Fac"], bump.inputs["Height"])
    nt.links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
    return mat


# ------------------------------------------------------------------ terén (mimo jádro)

def build_terrain_full(coll):
    xs = np.arange(X0, X0 + GW * DEM_RES, MESH_RES)
    ys = np.arange(Y1 - GH * DEM_RES, Y1, MESH_RES)
    gx, gy = np.meshgrid(xs, ys)
    dist = np.hypot(gx - HX, gy - HY)
    keep_mask = dist >= R_CUTOFF
    idx = -np.ones(gx.shape, np.int64)
    idx[keep_mask] = np.arange(keep_mask.sum())
    vx, vy = gx[keep_mask], gy[keep_mask]
    vz = tzf(vx, vy) + Z_BIAS
    a, b, c, d = idx[:-1, :-1], idx[:-1, 1:], idx[1:, 1:], idx[1:, :-1]
    ok = (a >= 0) & (b >= 0) & (c >= 0) & (d >= 0)
    quads = np.stack([a[ok], b[ok], c[ok], d[ok]], axis=1)
    me = bpy.data.meshes.new("OKOLI_FULL_Teren")
    me.vertices.add(len(vx))
    me.vertices.foreach_set("co", np.c_[vx, vy, vz].astype(np.float32).ravel())
    me.loops.add(quads.size)
    me.loops.foreach_set("vertex_index", quads.astype(np.int32).ravel())
    me.polygons.add(len(quads))
    me.polygons.foreach_set("loop_start", (np.arange(len(quads)) * 4).astype(np.int32))
    me.update(calc_edges=True)
    me.validate()
    uvl = me.uv_layers.new(name="ortho_full")
    li = quads.ravel()
    u = (vx[li] - X0) / (GW * DEM_RES)
    v = 1.0 - (Y1 - vy[li]) / (GH * DEM_RES)
    uvl.data.foreach_set("uv", np.c_[u, v].astype(np.float32).ravel())
    me.polygons.foreach_set("use_smooth", np.ones(len(quads), bool))
    me.materials.append(ortho_material_full())
    ob = bpy.data.objects.new("OKOLI_FULL_Teren", me)
    coll.objects.link(ob)
    print(f"TERRAIN_FULL {len(vx)} verts, {len(quads)} quads, step {MESH_RES} m, "
          f"r>={R_CUTOFF} m, z {vz.min():.1f}..{vz.max():.1f}")
    return ob


# ------------------------------------------------------------------ budovy (mimo jádro, z fáze 12)

class MeshBuf:
    def __init__(self):
        self.v, self.f, self.mi, self.col = [], [], [], []

    def add(self, verts, faces, mat_idx, rgb):
        o = len(self.v)
        self.v += verts
        for fc in faces:
            self.f.append(tuple(i + o for i in fc))
            self.mi.append(mat_idx)
            self.col.append(rgb)

    def to_object(self, name, coll, mats, attr="tint"):
        if not self.f:
            return None
        me = bpy.data.meshes.new(name)
        me.from_pydata(self.v, [], self.f)
        me.update()
        for m in mats:
            me.materials.append(m)
        me.polygons.foreach_set("material_index", np.array(self.mi, np.int32))
        ca = me.color_attributes.new(attr, "FLOAT_COLOR", "CORNER")
        tot = np.array([p.loop_total for p in me.polygons])
        cols = np.repeat(np.array(self.col, np.float32), tot, axis=0)
        cols = np.c_[cols, np.ones(len(cols), np.float32)]
        ca.data.foreach_set("color", cols.ravel())
        ob = bpy.data.objects.new(name, me)
        coll.objects.link(ob)
        return ob


def roof_parts(rect, eave, ridge, shape, overhang=0.45):
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
    rv = [P(-hl, -hw, ze), P(hl, -hw, ze), P(hl, hw, ze), P(-hl, hw, ze), P(-hl, 0, ridge), P(hl, 0, ridge)]
    roof = [(0, 1, 5, 4), (2, 3, 4, 5), (3, 2, 1, 0)]
    gv = [P(-L / 2, -W / 2, eave), P(-L / 2, W / 2, eave), P(-L / 2, 0, ridge),
          P(L / 2, -W / 2, eave), P(L / 2, W / 2, eave), P(L / 2, 0, ridge)]
    return [rv], [roof], [gv], [[(0, 2, 1), (3, 4, 5)]]


def build_buildings_full(coll):
    blds = oc.load_json("data/buildings_3d_full.json")
    walls, roofs = MeshBuf(), MeshBuf()
    n = 0
    for b in blds:
        poly = oc.ccw(oc.open_ring(b["polygon"]))
        if len(poly) < 3:
            continue
        fac = tuple(srgb_to_lin(b["facade_rgb"]))
        rcol = tuple(srgb_to_lin(np.clip(np.array(b["roof_rgb"]) * 1.08, 0, 1)))
        base, eave, ridge, shape = b["base_z"], b["eave_z"], b["ridge_z"], b["shape"]
        k = len(poly)
        v = [(x, y, base) for x, y in poly] + [(x, y, eave) for x, y in poly]
        f = [(i, (i + 1) % k, k + (i + 1) % k, k + i) for i in range(k)]
        walls.add(v, f, 0, fac)
        if shape == "flat" or ridge - eave < 0.3:
            roofs.add([(x, y, eave + 0.15) for x, y in poly] + [(x, y, eave) for x, y in poly],
                      [tuple(range(k))] + [(i, k + i, k + (i + 1) % k, (i + 1) % k) for i in range(k)], 0, rcol)
        else:
            rv, rf, gv, gf = roof_parts(b["rect"], eave, ridge, shape)
            for vv, ff in zip(rv, rf):
                roofs.add(vv, ff, 0, rcol)
            for vv, ff in zip(gv, gf):
                walls.add(vv, ff, 0, fac)
        n += 1
    mat_wall = bpy.data.materials.get("OKOLI_Fasada_omitka")
    mat_roof = bpy.data.materials.get("OKOLI_Strecha_tasky")
    ow = walls.to_object("OKOLI_FULL_Budovy_steny", coll, [mat_wall])
    orf = roofs.to_object("OKOLI_FULL_Budovy_strechy", coll, [mat_roof])
    for ob in (ow, orf):
        if ob is None:
            continue
        bm = bmesh.new()
        bm.from_mesh(ob.data)
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        bm.to_mesh(ob.data)
        bm.free()
    print(f"BUILDINGS_FULL {n} (walls {len(walls.f)} faces, roofs {len(roofs.f)} faces)")


# ------------------------------------------------------------------ silnice (mimo jádro)

ROAD_W = {"secondary": 7, "tertiary": 6.5, "unclassified": 5.5, "residential": 5.5, "living_street": 5,
          "service": 3.5, "track": 3, "path": 1.5, "footway": 1.8, "cycleway": 2}


def densify(pts, step=2.5):
    out = [pts[0]]
    for (x1, y1), (x2, y2) in zip(pts[:-1], pts[1:]):
        L = math.hypot(x2 - x1, y2 - y1)
        k = max(1, int(L / step))
        for i in range(1, k + 1):
            out.append((x1 + (x2 - x1) * i / k, y1 + (y2 - y1) * i / k))
    return out


def clip_by_pred(pts, pred):
    parts, cur = [], []
    for p in pts:
        if pred(*p):
            cur.append(p)
        elif cur:
            parts.append(cur)
            cur = []
    if cur:
        parts.append(cur)
    return [c for c in parts if len(c) >= 2]


def build_roads_full(coll):
    gj = oc.load_json("data/okoli_full_local.geojson")

    def keep_pt(x, y):
        if math.hypot(x - HX, y - HY) < R_CORE - 8:
            return False
        return oc.point_in_poly(x, y, ADMIN_POLY) or _dist_to_admin(x, y) < 150.0

    bufs = {"asfalt": MeshBuf(), "strk": MeshBuf()}
    cnt = {"asfalt": 0, "strk": 0}
    for f in gj["features"]:
        p = f["properties"]
        if p["kind"] != "highway" or f["geometry"]["type"] != "LineString":
            continue
        hw = p.get("highway")
        w = ROAD_W.get(hw, 4.0)
        kind = "strk" if hw in {"track", "path"} and p.get("surface") not in {"asphalt", "paved", "concrete"} \
            else "asfalt"
        raw = []
        for c in f["geometry"]["coordinates"]:
            if not raw or math.hypot(c[0] - raw[-1][0], c[1] - raw[-1][1]) > 1e-3:
                raw.append(tuple(c))
        if len(raw) < 2:
            continue
        for part in clip_by_pred(densify(raw), keep_pt):
            left, right = [], []
            for i in range(len(part)):
                a = part[max(i - 1, 0)]
                b = part[min(i + 1, len(part) - 1)]
                dx, dy = b[0] - a[0], b[1] - a[1]
                ln = math.hypot(dx, dy) or 1
                nx, ny = -dy / ln * w / 2, dx / ln * w / 2
                left.append((part[i][0] + nx, part[i][1] + ny))
                right.append((part[i][0] - nx, part[i][1] - ny))
            P = np.array(part)
            Lp, Rp = np.array(left), np.array(right)
            z = np.maximum.reduce([tzf(P[:, 0], P[:, 1]), tzf(Lp[:, 0], Lp[:, 1]), tzf(Rp[:, 0], Rp[:, 1])]) + 0.06
            k = len(part)
            verts = [(Lp[i, 0], Lp[i, 1], z[i]) for i in range(k)] + [(Rp[i, 0], Rp[i, 1], z[i]) for i in range(k)]
            faces = [(i + k, i + k + 1, i + 1, i) for i in range(k - 1)]
            bufs[kind].add(verts, faces, 0, (1, 1, 1))
            cnt[kind] += 1
    m_as = bpy.data.materials.get("OKOLI_Asfalt")
    m_gr = bpy.data.materials.get("OKOLI_Strk")
    for kind, m in (("asfalt", m_as), ("strk", m_gr)):
        ob = bufs[kind].to_object(f"OKOLI_FULL_Komunikace_{kind}", coll, [m])
        if ob is None:
            continue
        for poly in ob.data.polygons:
            if poly.normal.z < 0:
                poly.flip()
    print(f"ROADS_FULL {cnt}")


def _dist_to_admin(x, y):
    d = 1e18
    n = len(ADMIN_POLY)
    for i in range(n):
        ax, ay = ADMIN_POLY[i]
        bx, by = ADMIN_POLY[(i + 1) % n]
        dx, dy = bx - ax, by - ay
        Ls = dx * dx + dy * dy or 1e-12
        t = max(0.0, min(1.0, ((x - ax) * dx + (y - ay) * dy) / Ls))
        d = min(d, math.hypot(x - ax - t * dx, y - ay - t * dy))
    return d


# ------------------------------------------------------------------ vegetace (les + zahrady, procedurální scatter)

FOREST_TARGET = 16000
GARDEN_TARGET = 4000


def _protos():
    lib = bpy.data.collections.get("OKOLI_StromyKnihovna")
    protos = {"dec": [], "con": []}
    if lib is None:
        return protos, lib
    for c in lib.children:
        if c.name.startswith("OKOLI_Strom_dec_"):
            protos["dec"].append(c)
        elif c.name.startswith("OKOLI_Strom_con_"):
            protos["con"].append(c)
    return protos, lib


def scatter(coll, mask, kind_mix, height_rng, target_count, name_prefix, seed):
    area_m2 = mask.sum() * DEM_RES * DEM_RES
    if area_m2 < 1.0:
        print(f"{name_prefix}: mask empty, skip")
        return 0
    spacing = max(3.5, math.sqrt(area_m2 / max(target_count, 1)))
    rnd = random.Random(seed)
    protos, lib = _protos()
    if not protos["dec"] and not protos["con"]:
        print(f"{name_prefix}: no tree prototypes found (OKOLI_StromyKnihovna missing), skip")
        return 0
    xs = np.arange(X0 + spacing / 2, X0 + GW * DEM_RES, spacing)
    ys = np.arange(Y1 - GH * DEM_RES + spacing / 2, Y1, spacing)
    gx, gy = np.meshgrid(xs, ys)
    gx = gx.ravel() + (np.random.default_rng(seed).random(gx.size) - 0.5) * spacing * 0.8
    gy = gy.ravel() + (np.random.default_rng(seed + 1).random(gy.size) - 0.5) * spacing * 0.8
    rows = np.clip(((Y1 - gy) / DEM_RES).astype(int), 0, GH - 1)
    cols = np.clip(((gx - X0) / DEM_RES).astype(int), 0, GW - 1)
    keep = mask[rows, cols]
    gx, gy = gx[keep], gy[keep]
    n = 0
    for x, y in zip(gx, gy):
        kind = "dec" if rnd.random() < kind_mix else "con"
        if not protos[kind]:
            kind = "con" if kind == "dec" else "dec"
        if not protos[kind]:
            continue
        h = rnd.uniform(*height_rng[kind])
        r = h * (rnd.uniform(0.28, 0.38) if kind == "dec" else rnd.uniform(0.18, 0.26))
        e = bpy.data.objects.new(f"{name_prefix}_{n}", None)
        e.instance_type = "COLLECTION"
        e.instance_collection = rnd.choice(protos[kind])
        e.location = (float(x), float(y), float(tzf(np.array([x]), np.array([y]))[0]) - 0.1)
        e.scale = (r, r * rnd.uniform(0.9, 1.1), h)
        e.rotation_euler = (0, 0, rnd.uniform(0, 2 * math.pi))
        base = (rnd.uniform(0.13, 0.30), rnd.uniform(0.24, 0.42), rnd.uniform(0.06, 0.16))
        lin = srgb_to_lin(np.array(base))
        e.color = (*lin, 1.0)
        coll.objects.link(e)
        n += 1
    print(f"{name_prefix}: area {area_m2/10000:.1f} ha, spacing {spacing:.1f} m -> {n} stromů")
    return n


def build_vegetation_full(coll):
    npz = np.load(os.path.join(ROOT, "data", "forest_mask_full.npz"))
    forest, resid = npz["forest"], npz["residential"]
    scatter(coll, forest, kind_mix=0.45, height_rng={"dec": (10, 22), "con": (12, 26)},
            target_count=FOREST_TARGET, name_prefix="OKOLI_FULL_Les", seed=201)
    scatter(coll, resid, kind_mix=0.85, height_rng={"dec": (4, 10), "con": (5, 11)},
            target_count=GARDEN_TARGET, name_prefix="OKOLI_FULL_Zahrada", seed=401)


# ------------------------------------------------------------------ main

def main():
    src = os.path.join(BLEND_DIR, "Doubravy_3D_okoli_final_v2.blend")
    bpy.ops.wm.open_mainfile(filepath=src)
    print("OPENED", src)

    root = bpy.data.collections.get("OKOLI_FULL") or bpy.data.collections.new("OKOLI_FULL")
    if root.name not in [c.name for c in bpy.context.scene.collection.children]:
        bpy.context.scene.collection.children.link(root)

    def sub(name):
        c = bpy.data.collections.get(name) or bpy.data.collections.new(name)
        if c.name not in [ch.name for ch in root.children]:
            root.children.link(c)
        for o in list(c.objects):
            bpy.data.objects.remove(o, do_unlink=True)
        return c

    build_terrain_full(sub("OKOLI_FULL_Teren"))
    build_buildings_full(sub("OKOLI_FULL_Budovy"))
    os.makedirs(os.path.join(ROOT, "renders"), exist_ok=True)
    os.makedirs(BLEND_DIR, exist_ok=True)
    out1 = os.path.join(BLEND_DIR, "Doubravy_3D_okoli_full_v1.blend")
    bpy.ops.wm.save_as_mainfile(filepath=out1, copy=True)
    print("SAVED", out1)

    build_roads_full(sub("OKOLI_FULL_Komunikace"))
    build_vegetation_full(sub("OKOLI_FULL_Vegetace"))
    # finální artefakt = přímý vstup tools/export_map.py – ukládá se rovnou
    # pod cílovým jménem mapa_okoli.blend
    out2 = os.path.join(BLEND_DIR, "mapa_okoli.blend")
    bpy.ops.wm.save_as_mainfile(filepath=out2, copy=True)
    print("SAVED", out2)

    oc.control_render(ref, os.path.join(ROOT, "renders", "phase13_full_v2.png"), radius=2600.0, samples=24)


main()
