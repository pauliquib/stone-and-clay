"""Fáze 7 – přesné okolí z geodat ČÚZK (terén, výšky, textury) – headless bpy.

Spuštění:
    blender --background blend/Doubravy_3D.blend --python-exit-code 1 --python pipeline/scripts/phase7_build_accurate.py

Vstupy (připraví phase6_*.py): geodata/terrain_z.npy, geodata/ortho_scene.jpg,
pipeline/data/geodata_meta.json, pipeline/data/buildings_3d.json, pipeline/data/trees_ndsm.json,
pipeline/data/okoli_local.geojson, pipeline/data/textures.json, pipeline/assets/materials/ph_*, pipeline/assets/hdrs/ph_*

Výstupy:
  blend/Doubravy_3D_okoli_v3.blend        – terén DMR 5G + ortofoto, budovy s výškami z DMP 1G
  blend/Doubravy_3D_okoli_final_v2.blend  – + silnice na terénu, stromy z DMP, HDRI
  pipeline/renders/phase7_v3.png, phase7_final_v2.png, phase7_final_v2_persp.png
Model domu a pozemku se nemění; vše nové je v kolekci OKOLI_OSM.
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
meta = oc.load_json("data/geodata_meta.json")
tex_info = oc.load_json("data/textures.json")
X0, Y1, RES, HALF = meta["grid_x0"], meta["grid_y1"], meta["dem_res"], meta["half"]
HX, HY = ref["house_scene_xy"]
TERR = np.load(os.path.join(GEO, "terrain_z.npy")).astype(np.float64)
R_TERRAIN = 480.0
STEP = 1.5


def tz(x, y):
    """Bilineární výška terénu (z scény) v bodech x, y (numpy)."""
    x = np.asarray(x, float)
    y = np.asarray(y, float)
    r = (Y1 - y) / RES - 0.5
    c = (x - X0) / RES - 0.5
    n = TERR.shape[0]
    r = np.clip(r, 0, n - 1.001)
    c = np.clip(c, 0, n - 1.001)
    r0 = np.floor(r).astype(int)
    c0 = np.floor(c).astype(int)
    fr, fc = r - r0, c - c0
    t = TERR
    return (t[r0, c0] * (1 - fr) * (1 - fc) + t[r0, c0 + 1] * (1 - fr) * fc +
            t[r0 + 1, c0] * fr * (1 - fc) + t[r0 + 1, c0 + 1] * fr * fc)


def srgb_to_lin(c):
    c = np.asarray(c, float)
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)



def sock(node, name, kind="RGBA", out=False):
    """Socket podle jména a typu (ShaderNodeMix má A/B/Result pro float, vektor i barvu)."""
    socks = node.outputs if out else node.inputs
    return next(x for x in socks if x.name == name and x.type == kind)


# ------------------------------------------------------------------ materiály

def ph_files(tid):
    d = os.path.join(ROOT, tex_info[tid]["dir"])
    out = {}
    for f in os.listdir(d):
        if "_diff_" in f:
            out["diff"] = os.path.join(d, f)
        elif "_nor_gl_" in f:
            out["nor"] = os.path.join(d, f)
        elif "_rough_" in f:
            out["rough"] = os.path.join(d, f)
    return out, tex_info[tid]["size_m"]


def image_mean_lum(img):
    px = np.empty(len(img.pixels), np.float32)
    img.pixels.foreach_get(px)
    px = px.reshape(-1, 4)[::7]
    return float(np.mean(0.2126 * px[:, 0] + 0.7152 * px[:, 1] + 0.0722 * px[:, 2]))


def pbr_material(name, tid, tint_attr=None, tint_strength=1.0, rough_mul=1.0, normal_strength=1.0,
                 base_rgb=None):
    """PBR materiál Poly Haven s box projekcí v objektových souřadnicích (1 BU = 1 m).
    tint_attr: barva z atributu (fasáda / střecha dle ortofota) × jas textury."""
    mat = bpy.data.materials.get(name)
    if mat:
        return mat
    files, size_m = ph_files(tid)
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    L = nt.links
    bsdf = nt.nodes.get("Principled BSDF")
    tc = nt.nodes.new("ShaderNodeTexCoord")
    mp = nt.nodes.new("ShaderNodeMapping")
    mp.inputs["Scale"].default_value = (1 / size_m,) * 3
    L.new(tc.outputs["Object"], mp.inputs["Vector"])

    def img(path, noncolor):
        n = nt.nodes.new("ShaderNodeTexImage")
        n.image = bpy.data.images.load(path, check_existing=True)
        if noncolor:
            n.image.colorspace_settings.name = "Non-Color"
        n.projection = "BOX"
        n.projection_blend = 0.25
        L.new(mp.outputs["Vector"], n.inputs["Vector"])
        return n

    diff = img(files["diff"], False)
    if tint_attr or base_rgb:
        gain = 1.0 / max(image_mean_lum(diff.image), 0.05)
        hs = nt.nodes.new("ShaderNodeHueSaturation")
        hs.inputs["Saturation"].default_value = 1.0 - tint_strength
        hs.inputs["Value"].default_value = gain * 0.92
        L.new(diff.outputs["Color"], hs.inputs["Color"])
        mix = nt.nodes.new("ShaderNodeMix")
        mix.data_type = "RGBA"
        mix.blend_type = "MULTIPLY"
        mix.inputs["Factor"].default_value = 1.0
        L.new(hs.outputs["Color"], sock(mix, "A"))
        if tint_attr:
            at = nt.nodes.new("ShaderNodeAttribute")
            at.attribute_name = tint_attr
            at.attribute_type = "GEOMETRY"
            L.new(at.outputs["Color"], sock(mix, "B"))
        else:
            sock(mix, "B").default_value = (*base_rgb, 1)
        L.new(sock(mix, "Result", out=True), bsdf.inputs["Base Color"])
    else:
        L.new(diff.outputs["Color"], bsdf.inputs["Base Color"])
    rough = img(files["rough"], True)
    if rough_mul != 1.0:
        mm = nt.nodes.new("ShaderNodeMath")
        mm.operation = "MULTIPLY"
        mm.inputs[1].default_value = rough_mul
        L.new(rough.outputs["Color"], mm.inputs[0])
        L.new(mm.outputs["Value"], bsdf.inputs["Roughness"])
    else:
        L.new(rough.outputs["Color"], bsdf.inputs["Roughness"])
    nor = img(files["nor"], True)
    nm = nt.nodes.new("ShaderNodeNormalMap")
    nm.inputs["Strength"].default_value = normal_strength
    L.new(nor.outputs["Color"], nm.inputs["Color"])
    L.new(nm.outputs["Normal"], bsdf.inputs["Normal"])
    print(f"MAT {name}: Poly Haven '{tid}' ({size_m} m)")
    return mat


def ortho_material():
    mat = bpy.data.materials.get("OKOLI_Teren_ortofoto")
    if mat:
        return mat
    mat = bpy.data.materials.new("OKOLI_Teren_ortofoto")
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = nt.nodes.get("Principled BSDF")
    im = nt.nodes.new("ShaderNodeTexImage")
    im.image = bpy.data.images.load(os.path.join(GEO, "ortho_scene.jpg"), check_existing=True)
    im.interpolation = "Cubic"
    im.extension = "EXTEND"
    uv = nt.nodes.new("ShaderNodeUVMap")
    uv.uv_map = "ortho"
    nt.links.new(uv.outputs["UV"], im.inputs["Vector"])
    nt.links.new(im.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.92
    # jemný detail (ortofoto má 12,7 cm/px) – drobný šum do normály
    tc = nt.nodes.new("ShaderNodeTexCoord")
    nz = nt.nodes.new("ShaderNodeTexNoise")
    nz.inputs["Scale"].default_value = 40.0
    nz.inputs["Detail"].default_value = 8.0
    nt.links.new(tc.outputs["Object"], nz.inputs["Vector"])
    bump = nt.nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.15
    bump.inputs["Distance"].default_value = 0.02
    nt.links.new(nz.outputs["Fac"], bump.inputs["Height"])
    nt.links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
    return mat


# ------------------------------------------------------------------ terén

def build_terrain(coll):
    n = int(2 * R_TERRAIN / STEP) + 1
    xs = HX - R_TERRAIN + np.arange(n) * STEP
    ys = HY - R_TERRAIN + np.arange(n) * STEP
    gx, gy = np.meshgrid(xs, ys)
    inside = np.hypot(gx - HX, gy - HY) <= R_TERRAIN + STEP
    idx = -np.ones(gx.shape, np.int64)
    idx[inside] = np.arange(inside.sum())
    vx, vy = gx[inside], gy[inside]
    vz = tz(vx, vy)
    a, b, c, d = idx[:-1, :-1], idx[:-1, 1:], idx[1:, 1:], idx[1:, :-1]
    ok = (a >= 0) & (b >= 0) & (c >= 0) & (d >= 0)
    quads = np.stack([a[ok], b[ok], c[ok], d[ok]], axis=1)
    me = bpy.data.meshes.new("OKOLI_Teren_DMR5G")
    me.vertices.add(len(vx))
    me.vertices.foreach_set("co", np.c_[vx, vy, vz].astype(np.float32).ravel())
    me.loops.add(quads.size)
    me.loops.foreach_set("vertex_index", quads.astype(np.int32).ravel())
    me.polygons.add(len(quads))
    me.polygons.foreach_set("loop_start", (np.arange(len(quads)) * 4).astype(np.int32))
    me.update(calc_edges=True)
    me.validate()
    uvl = me.uv_layers.new(name="ortho")
    li = quads.ravel()
    u = (vx[li] - X0) / (2 * HALF)
    v = 1.0 - (Y1 - vy[li]) / (2 * HALF)
    uvl.data.foreach_set("uv", np.c_[u, v].astype(np.float32).ravel())
    me.polygons.foreach_set("use_smooth", np.ones(len(quads), bool))
    me.materials.append(ortho_material())
    ob = bpy.data.objects.new("OKOLI_Teren_DMR5G", me)
    coll.objects.link(ob)
    print(f"TERRAIN {len(vx)} verts, {len(quads)} quads, step {STEP} m, z {vz.min():.1f}…{vz.max():.1f}")
    return ob


# ------------------------------------------------------------------ budovy

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
    """Střecha nad orientovaným obdélníkem. Vrací (střešní plochy, štítové trojúhelníky)."""
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
        if L / 2 - inset <= -L / 2 + inset + 1e-3:  # jehlan
            rv[4] = rv[5] = P(0, 0, ridge)
            return [rv[:5]], [[(0, 1, 4), (1, 2, 4), (2, 3, 4), (3, 0, 4), (3, 2, 1, 0)]], [], []
        return [rv], [[(0, 1, 5, 4), (1, 2, 5), (2, 3, 4, 5), (3, 0, 4), (3, 2, 1, 0)]], [], []
    rv = [P(-hl, -hw, ze), P(hl, -hw, ze), P(hl, hw, ze), P(-hl, hw, ze), P(-hl, 0, ridge), P(hl, 0, ridge)]
    roof = [(0, 1, 5, 4), (2, 3, 4, 5), (3, 2, 1, 0)]
    # štíty (stěnový materiál) v rovině obvodové zdi
    gv = [P(-L / 2, -W / 2, eave), P(-L / 2, W / 2, eave), P(-L / 2, 0, ridge),
          P(L / 2, -W / 2, eave), P(L / 2, W / 2, eave), P(L / 2, 0, ridge)]
    return [rv], [roof], [gv], [[(0, 2, 1), (3, 4, 5)]]


def build_buildings(coll):
    blds = oc.load_json("data/buildings_3d.json")
    walls, roofs = MeshBuf(), MeshBuf()
    keep = ref.get("keep_out_bbox")
    n = 0
    for b in blds:
        poly = oc.ccw(oc.open_ring(b["polygon"]))
        if len(poly) < 3:
            continue
        cxm = sum(p[0] for p in poly) / len(poly)
        cym = sum(p[1] for p in poly) / len(poly)
        if oc.point_in_poly(HX, HY, poly) or (keep and keep[0] <= cxm <= keep[2] and keep[1] <= cym <= keep[3]):
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
    mat_wall = pbr_material("OKOLI_Fasada_omitka", "beige_wall_001", tint_attr="tint", tint_strength=1.0,
                            normal_strength=0.6)
    mat_roof = pbr_material("OKOLI_Strecha_tasky", "clay_roof_tiles_02", tint_attr="tint", tint_strength=1.0,
                            normal_strength=0.8)
    ow = walls.to_object("OKOLI_Budovy_steny", coll, [mat_wall])
    orf = roofs.to_object("OKOLI_Budovy_strechy", coll, [mat_roof])
    for ob in (ow, orf):
        bm = bmesh.new()
        bm.from_mesh(ob.data)
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        bm.to_mesh(ob.data)
        bm.free()
    print(f"BUILDINGS {n} (walls {len(walls.f)} faces, roofs {len(roofs.f)} faces)")


# ------------------------------------------------------------------ silnice

ROAD_W = {"secondary": 7, "tertiary": 6.5, "unclassified": 5.5, "residential": 5.5, "living_street": 5,
          "service": 3.5, "track": 3, "path": 1.5, "footway": 1.8, "cycleway": 2}


def densify(pts, step=2.0):
    out = [pts[0]]
    for (x1, y1), (x2, y2) in zip(pts[:-1], pts[1:]):
        L = math.hypot(x2 - x1, y2 - y1)
        k = max(1, int(L / step))
        for i in range(1, k + 1):
            out.append((x1 + (x2 - x1) * i / k, y1 + (y2 - y1) * i / k))
    return out


def clip_to_circle(pts, R):
    parts, cur = [], []
    for p in pts:
        if math.hypot(p[0] - HX, p[1] - HY) <= R:
            cur.append(p)
        elif cur:
            parts.append(cur)
            cur = []
    if cur:
        parts.append(cur)
    return [c for c in parts if len(c) >= 2]


def build_roads(coll):
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    gj = oc.load_json("data/okoli_local.geojson")
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
        for part in clip_to_circle(densify(raw), R_TERRAIN - 2):
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
            z = np.maximum.reduce([tz(P[:, 0], P[:, 1]), tz(Lp[:, 0], Lp[:, 1]), tz(Rp[:, 0], Rp[:, 1])]) + 0.06
            k = len(part)
            verts = [(Lp[i, 0], Lp[i, 1], z[i]) for i in range(k)] + [(Rp[i, 0], Rp[i, 1], z[i]) for i in range(k)]
            faces = [(i + k, i + k + 1, i + 1, i) for i in range(k - 1)]
            bufs[kind].add(verts, faces, 0, (1, 1, 1))
            cnt[kind] += 1
    m_as = pbr_material("OKOLI_Asfalt", "asphalt_02", normal_strength=0.5)
    m_gr = pbr_material("OKOLI_Strk", "gravel_road", normal_strength=0.7, tint_strength=0.85,
                        base_rgb=(0.55, 0.52, 0.47))
    for kind, m in (("asfalt", m_as), ("strk", m_gr)):
        if bufs[kind].f:
            ob = bufs[kind].to_object(f"OKOLI_Komunikace_{kind}", coll, [m])
            for poly in ob.data.polygons:
                if poly.normal.z < 0:
                    poly.flip()
    print(f"ROADS {cnt}")


# ------------------------------------------------------------------ stromy

def leaf_material(name, base):
    mat = bpy.data.materials.get(name)
    if mat:
        return mat
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = nt.nodes.get("Principled BSDF")
    # barva koruny z ortofota (vlastnost 'color' instancujícího prázdného objektu)
    at = nt.nodes.new("ShaderNodeAttribute")
    at.attribute_type = "INSTANCER"
    at.attribute_name = "color"
    mix = nt.nodes.new("ShaderNodeMix")
    mix.data_type = "RGBA"
    mix.inputs["Factor"].default_value = 0.65
    sock(mix, "A").default_value = (*base, 1)
    nt.links.new(at.outputs["Color"], sock(mix, "B"))
    nz = nt.nodes.new("ShaderNodeTexNoise")
    nz.inputs["Scale"].default_value = 6.0
    ramp = nt.nodes.new("ShaderNodeMix")
    ramp.data_type = "RGBA"
    ramp.blend_type = "MULTIPLY"
    nt.links.new(nz.outputs["Fac"], ramp.inputs["Factor"])
    nt.links.new(sock(mix, "Result", out=True), sock(ramp, "A"))
    sock(ramp, "B").default_value = (0.6, 0.7, 0.5, 1)
    nt.links.new(sock(ramp, "Result", out=True), bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.75
    try:
        bsdf.inputs["Subsurface Weight"].default_value = 0.15
    except KeyError:
        pass
    tc = nt.nodes.new("ShaderNodeTexCoord")
    vor = nt.nodes.new("ShaderNodeTexVoronoi")
    vor.inputs["Scale"].default_value = 25.0
    nt.links.new(tc.outputs["Object"], vor.inputs["Vector"])
    bump = nt.nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.6
    nt.links.new(vor.outputs["Distance"], bump.inputs["Height"])
    nt.links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
    return mat


def tree_protos(lib):
    """Normalizované prototypy: výška 1, poloměr koruny 1 (instance se škáluje r, r, h)."""
    from mathutils import noise, Vector
    bark = pbr_material("OKOLI_Kura", "bark_brown_02", normal_strength=1.0)
    leaf = leaf_material("OKOLI_Listi", (0.09, 0.18, 0.05))
    needle = leaf_material("OKOLI_Jehlici", (0.05, 0.12, 0.05))
    protos = {}
    rnd = random.Random(7)
    for kind in ("dec", "con"):
        variants = []
        for vi in range(3):
            bm = bmesh.new()
            if kind == "dec":
                g = bmesh.ops.create_cone(bm, cap_ends=True, segments=8, radius1=0.09, radius2=0.05, depth=0.5)
                bmesh.ops.translate(bm, verts=g["verts"], vec=(0, 0, 0.25))
                trunk = set(g["verts"])
                blobs = [((0, 0, 0.66), (0.78, 0.78, 0.30))]
                for _ in range(5):
                    ang = rnd.uniform(0, 2 * math.pi)
                    rr = rnd.uniform(0.25, 0.45)
                    blobs.append(((rr * math.cos(ang), rr * math.sin(ang), rnd.uniform(0.55, 0.8)),
                                  (rnd.uniform(0.45, 0.6),) * 2 + (rnd.uniform(0.2, 0.28),)))
                for (c, sz) in blobs:
                    g = bmesh.ops.create_icosphere(bm, subdivisions=3, radius=1.0)
                    for v in g["verts"]:
                        p = Vector((v.co.x * sz[0], v.co.y * sz[1], v.co.z * sz[2]))
                        d = noise.noise(Vector((p.x * 4 + vi * 10, p.y * 4, p.z * 4))) * 0.12
                        v.co = Vector(c) + p * (1 + d)
            else:
                g = bmesh.ops.create_cone(bm, cap_ends=True, segments=8, radius1=0.07, radius2=0.03, depth=0.25)
                bmesh.ops.translate(bm, verts=g["verts"], vec=(0, 0, 0.125))
                trunk = set(g["verts"])
                for j, (z0, r0, hh) in enumerate(((0.12, 1.0, 0.5), (0.38, 0.75, 0.4), (0.62, 0.45, 0.38))):
                    g = bmesh.ops.create_cone(bm, cap_ends=True, segments=12, radius1=r0, radius2=0.0,
                                              depth=hh)
                    bmesh.ops.translate(bm, verts=g["verts"], vec=(0, 0, z0 + hh / 2))
            for fc in bm.faces:
                fc.material_index = 0 if all(v in trunk for v in fc.verts) else 1
                fc.smooth = True
            me = bpy.data.meshes.new(f"OKOLI_Strom_{kind}_{vi}")
            bm.to_mesh(me)
            bm.free()
            me.materials.append(bark)
            me.materials.append(leaf if kind == "dec" else needle)
            ob = bpy.data.objects.new(me.name, me)
            c = bpy.data.collections.new(f"OKOLI_Strom_{kind}_{vi}")
            lib.children.link(c)
            c.objects.link(ob)
            variants.append(c)
        protos[kind] = variants
    return protos


def build_trees(coll):
    trees = oc.load_json("data/trees_ndsm.json")
    lib = bpy.data.collections.new("OKOLI_StromyKnihovna")
    bpy.context.scene.collection.children.link(lib)
    protos = tree_protos(lib)
    for lc in bpy.context.view_layer.layer_collection.children:
        if lc.collection == lib:
            lc.exclude = True
    rnd = random.Random(122)
    for i, t in enumerate(trees):
        kind = t.get("type", "dec")
        e = bpy.data.objects.new(f"OKOLI_Strom_{i}", None)
        e.instance_type = "COLLECTION"
        e.instance_collection = rnd.choice(protos[kind])
        e.location = (t["x"], t["y"], float(tz([t["x"]], [t["y"]])[0]) - 0.1)
        r = t["r"] if kind == "dec" else min(t["r"], 0.35 * t["h"])
        e.scale = (r, r * rnd.uniform(0.9, 1.1), t["h"])
        e.rotation_euler = (0, 0, rnd.uniform(0, 2 * math.pi))
        lin = srgb_to_lin(t["rgb"])
        e.color = (*lin, 1.0)
        coll.objects.link(e)
    print(f"TREES {len(trees)} (DMP 1G − DMR 5G)")


# ------------------------------------------------------------------ světlo

def setup_world():
    scene = bpy.context.scene
    world = bpy.data.worlds.new("OKOLI_World")
    world.use_nodes = True
    nt = world.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputWorld")
    bg = nt.nodes.new("ShaderNodeBackground")
    env = nt.nodes.new("ShaderNodeTexEnvironment")
    env.image = bpy.data.images.load(os.path.join(ROOT, tex_info["hdri"]["file"]), check_existing=True)
    nt.links.new(env.outputs["Color"], bg.inputs["Color"])
    nt.links.new(bg.outputs["Background"], out.inputs["Surface"])
    bg.inputs["Strength"].default_value = 1.0
    scene.world = world
    vs = scene.view_settings
    for vt in ("AgX", "Filmic"):
        try:
            vs.view_transform = vt
            break
        except TypeError:
            continue
    vs.exposure = -1.0 if vs.view_transform == "Standard" else -0.5
    print("WORLD HDRI", tex_info["hdri"]["id"], "view", vs.view_transform, "exposure", vs.exposure)


def persp_render(path):
    scene = bpy.context.scene
    cd = bpy.data.cameras.new("CAM_Kontrola_persp")
    cd.lens = 28
    cd.clip_end = 3000
    cam = bpy.data.objects.new("CAM_Kontrola_persp", cd)
    oc.get_coll(oc.ROOT_COLL).objects.link(cam)
    # pohled od silnice (strana +X/−Y) šikmo na dům a sousedy
    from mathutils import Vector
    target = Vector((HX, HY, float(tz([HX], [HY])[0]) + 3))
    cam.location = target + Vector((70, -55, 28))
    cam.rotation_euler = (target - cam.location).to_track_quat("-Z", "Y").to_euler()
    prev = scene.camera
    scene.camera = cam
    scene.render.resolution_x, scene.render.resolution_y = 800, 600
    scene.render.resolution_percentage = 100
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    scene.camera = prev or cam
    print("RENDER", path)


def main():
    root = oc.get_coll(oc.ROOT_COLL)
    t_coll = oc.sub_coll("OKOLI_Teren")
    b_coll = oc.sub_coll("OKOLI_Budovy")
    build_terrain(t_coll)
    build_buildings(b_coll)
    setup_world()
    os.makedirs(os.path.join(ROOT, "renders"), exist_ok=True)
    os.makedirs(BLEND_DIR, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(BLEND_DIR, "Doubravy_3D_okoli_v3.blend"), copy=True)
    print("SAVED", os.path.join(BLEND_DIR, "Doubravy_3D_okoli_v3.blend"))
    oc.control_render(ref, os.path.join(ROOT, "renders", "phase7_v3.png"), samples=16)

    build_roads(oc.sub_coll("OKOLI_Komunikace"))
    build_trees(oc.sub_coll("OKOLI_Vegetace"))
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(BLEND_DIR, "Doubravy_3D_okoli_final_v2.blend"), copy=True)
    print("SAVED", os.path.join(BLEND_DIR, "Doubravy_3D_okoli_final_v2.blend"))
    oc.control_render(ref, os.path.join(ROOT, "renders", "phase7_final_v2.png"), samples=32)
    persp_render(os.path.join(ROOT, "renders", "phase7_final_v2_persp.png"))
    _ = root


main()
