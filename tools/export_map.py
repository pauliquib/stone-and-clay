"""Herní verze mapy – úprava mapa_okoli.blend a export dat pro Godot.

1. Otevře mapa_okoli.blend (celý katastr Dukelčic).
2. ODEBERE detailní model domu hráče (všechny kolekce mimo OKOLI_*)
   a místo něj postaví dům ve stejném zjednodušeném stylu jako ostatní budovy
   (tools/out/domov_hrace.json z tools/domov_hrace.py). Terén jádra pod bývalým
   modelem (byl snížený pod pozemek) vrátí na původní DMR 5G.
   Kolekce HRA_* (ruční úpravy – návod BLENDER_UPRAVY.md) zůstanou a exportují se:
   HRA_Steny, HRA_Strechy, HRA_Asfalt, HRA_Strk (meshe), HRA_Stromy (instance prototypů stromů),
   HRA_Smazat (meshe-kvádry: budovy a stromy, jejichž střed leží uvnitř, se z exportu vyřadí).
3. Uloží herní verzi mapy: blend/mapa.blend
4. Exportuje data pro hru (souřadnice Godotu: X = x, Y = z, Z = −y; metry):
   data/terrain_height.bin   výšková mřížka 2 m (float32, řádky od severu) – kolize i zobrazení
   data/walls.bin, roofs.bin, asphalt.bin, gravel.bin   geometrie po dlaždicích 256 m
   data/tree_protos.bin, data/trees.bin                 stromy (6 prototypů, ~21 800 instancí)
   data/map.json             metadata, silnice (graf pro boty), předměty, spawn, hranice katastru
   textures/                 ortofoto (jádro 12,7 cm/px + celý katastr 0,66 m/px), PBR textury

Spuštění:
  python3 tools/domov_hrace.py
  blender --background --python-exit-code 1 --python tools/export_map.py
"""
import json
import math
import os
import random
import shutil
import struct
import sys

import bmesh
import bpy
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
GAME = os.path.dirname(HERE)
ROOT = os.path.dirname(GAME)
SRC_BLEND = os.path.join(ROOT, "mapa_okoli.blend")
OUT_BLEND = os.path.join(GAME, "blend", "mapa.blend")
DATA = os.path.join(GAME, "data")
TEX = os.path.join(GAME, "textures")
CHUNK = 256.0


def jload(rel):
    return json.load(open(os.path.join(ROOT, rel)))


ref = jload("data/scene_reference.json")
H_ref = jload("data/terrain_ref.json")["H_ref"]
meta_c = jload("data/geodata_meta.json")
meta = jload("data/geodata_meta_full.json")
admin = jload("data/obec_admin_boundary.json")
HX, HY = ref["house_scene_xy"]
X0, Y1, RES, GW, GH = meta["grid_x0"], meta["grid_y1"], meta["dem_res"], meta["dem_w"], meta["dem_h"]


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


# ------------------------------------------------------------------ 1–2: úprava mapy

def remove_house_model():
    sc = bpy.context.scene
    removed_obj, removed_coll = 0, 0

    def collect(c, out):
        out.append(c)
        for ch in c.children:
            collect(ch, out)

    doomed = []
    for c in list(sc.collection.children):
        if not c.name.startswith(("OKOLI", "HRA_")):
            collect(c, doomed)
    for c in doomed:
        for ob in list(c.objects):
            bpy.data.objects.remove(ob, do_unlink=True)
            removed_obj += 1
    for c in reversed(doomed):
        bpy.data.collections.remove(c)
        removed_coll += 1
    for ob in list(sc.collection.objects):   # případné volné objekty v kořeni
        bpy.data.objects.remove(ob, do_unlink=True)
        removed_obj += 1
    bpy.ops.outliner.orphans_purge(do_local_ids=True, do_linked_ids=True, do_recursive=True)
    print(f"HOUSE MODEL REMOVED: {removed_obj} objects, {removed_coll} collections")


def restore_core_terrain():
    """Jádro mělo terén snížený pod pozemek modelu – ve hře tam stojí jednoduchý dům, vrátit DMR."""
    ob = bpy.data.objects["OKOLI_Teren_DMR5G"]
    dtm = np.load(os.path.join(ROOT, "geodata", "dtm_scene.npy")).astype(np.float64) - H_ref
    me = ob.data
    co = np.empty(len(me.vertices) * 3, np.float32)
    me.vertices.foreach_get("co", co)
    co = co.reshape(-1, 3)
    near = np.hypot(co[:, 0] - HX, co[:, 1] - HY) < 45
    co[near, 2] = bilinear(dtm, meta_c["grid_x0"], meta_c["grid_y1"], meta_c["dem_res"], co[near, 0], co[near, 1])
    me.vertices.foreach_set("co", co.ravel())
    me.update()
    print(f"CORE TERRAIN restored under former model: {near.sum()} vertices")


def roof_parts(rect, eave, ridge, shape, overhang=0.45):
    """Kopie phase7_build_accurate.roof_parts (fáze 7 se při importu sama spouští)."""
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


def mesh_from(name, parts, rgb, mat, coll):
    verts, faces = [], []
    for vv, ff in parts:
        o = len(verts)
        verts += vv
        faces += [tuple(i + o for i in f) for f in ff]
    me = bpy.data.meshes.new(name)
    me.from_pydata(verts, [], faces)
    me.update()
    me.materials.append(mat)
    ca = me.color_attributes.new("tint", "FLOAT_COLOR", "CORNER")
    ca.data.foreach_set("color", np.tile([*rgb, 1.0], len(me.loops)).astype(np.float32))
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    coll.objects.link(ob)
    return ob


def add_simple_house():
    b = json.load(open(os.path.join(HERE, "out", "domov_hrace.json")))
    coll = bpy.data.collections["OKOLI_Budovy"]
    poly = [tuple(p) for p in b["polygon"]]
    area = sum(poly[i][0] * poly[(i + 1) % len(poly)][1] - poly[(i + 1) % len(poly)][0] * poly[i][1]
               for i in range(len(poly)))
    if area < 0:
        poly = poly[::-1]
    k = len(poly)
    fac = tuple(srgb_to_lin(b["facade_rgb"]))
    rcol = tuple(srgb_to_lin(np.clip(np.array(b["roof_rgb"]) * 1.08, 0, 1)))
    base, eave, ridge, shape = b["base_z"], b["eave_z"], b["ridge_z"], b["shape"]
    wall_parts = [([(x, y, base) for x, y in poly] + [(x, y, eave) for x, y in poly],
                   [(i, (i + 1) % k, k + (i + 1) % k, k + i) for i in range(k)])]
    rv, rf, gv, gf = roof_parts(b["rect"], eave, ridge, shape)
    wall_parts += list(zip(gv, gf))
    mesh_from("OKOLI_DumDomov_steny", wall_parts, fac, bpy.data.materials["OKOLI_Fasada_omitka"], coll)
    mesh_from("OKOLI_DumDomov_strecha", list(zip(rv, rf)), rcol, bpy.data.materials["OKOLI_Strecha_tasky"], coll)
    print(f"HOUSE simple: {shape}, eave {eave:.2f}, ridge {ridge:.2f}")
    return b


# ------------------------------------------------------------------ 4: export

def g3(p):
    """Blender (x, y, z) → Godot (x, z, −y)."""
    p = np.asarray(p, np.float32)
    return np.stack([p[..., 0], p[..., 2], -p[..., 1]], axis=-1)


def triangles(ob, lower_walls_to=None):
    """Trojúhelníky objektu: pozice, normály (ploché), barva 'tint' – vše po rozích, Godot souřadnice."""
    me = ob.data
    me.calc_loop_triangles()
    nt = len(me.loop_triangles)
    loops = np.empty(nt * 3, np.int32)
    me.loop_triangles.foreach_get("loops", loops)
    polyi = np.empty(nt, np.int32)
    me.loop_triangles.foreach_get("polygon_index", polyi)
    lv = np.empty(len(me.loops), np.int32)
    me.loops.foreach_get("vertex_index", lv)
    co = np.empty(len(me.vertices) * 3, np.float32)
    me.vertices.foreach_get("co", co)
    co = co.reshape(-1, 3)
    mw = np.array(ob.matrix_world, np.float32)
    co = co @ mw[:3, :3].T + mw[:3, 3]
    pos = co[lv[loops]].reshape(nt, 3, 3)
    pn = np.empty(len(me.polygons) * 3, np.float32)
    me.polygons.foreach_get("normal", pn)
    fn = pn.reshape(-1, 3)[polyi]
    fn = fn @ mw[:3, :3].T
    fn /= np.maximum(np.linalg.norm(fn, axis=1, keepdims=True), 1e-9)
    col = np.ones((nt, 3, 3), np.float32)
    ca = me.color_attributes.get("tint")
    if ca is not None:
        raw = np.empty(len(ca.data) * 4, np.float32)
        ca.data.foreach_get("color", raw)
        raw = raw.reshape(-1, 4)[:, :3]
        if ca.domain == "CORNER":
            col = raw[loops].reshape(nt, 3, 3)
        elif ca.domain == "POINT":
            col = raw[lv[loops]].reshape(nt, 3, 3)
        elif ca.domain == "FACE":
            col = np.repeat(raw[polyi][:, None, :], 3, axis=1)
    if lower_walls_to is not None:
        # spodní hrana zdí o 1 m hlouběji, ať na herním (2 m) terénu nikde nevisí nad zemí
        z = pos[..., 2]
        ground = lower_walls_to(pos[..., 0].ravel(), pos[..., 1].ravel()).reshape(z.shape)
        vertical = np.abs(fn[:, 2]) < 0.3
        low = (z - ground < 0.6) & vertical[:, None]
        pos[..., 2] = np.where(low, z - 1.0, z)
    nrm = np.repeat(fn[:, None, :], 3, axis=1)
    # Godot: přední strana = po směru hodin → prohodit 2. a 3. vrchol
    pos, nrm, col = pos[:, [0, 2, 1]], nrm[:, [0, 2, 1]], col[:, [0, 2, 1]]
    return g3(pos), g3(nrm), col


def write_chunked(path, parts):
    pos = np.concatenate([p[0] for p in parts]).astype(np.float32)
    nrm = np.concatenate([p[1] for p in parts]).astype(np.float32)
    col = np.concatenate([p[2] for p in parts]).astype(np.float32)
    cen = pos.mean(axis=1)
    key_x = np.floor(cen[:, 0] / CHUNK).astype(int)
    key_z = np.floor(cen[:, 2] / CHUNK).astype(int)
    keys = sorted(set(zip(key_x.tolist(), key_z.tolist())))
    with open(path, "wb") as f:
        f.write(b"DBM1")
        f.write(struct.pack("<i", len(keys)))
        for kx, kz in keys:
            sel = (key_x == kx) & (key_z == kz)
            p, n, c = pos[sel].reshape(-1, 3), nrm[sel].reshape(-1, 3), col[sel].reshape(-1, 3)
            f.write(struct.pack("<i", len(p)))
            f.write(p.tobytes())
            f.write(n.tobytes())
            f.write(c.tobytes())
    print(f"WROTE {os.path.basename(path)}: {len(pos)} triangles in {len(keys)} chunks")
    return pos


def export_tree_protos(names):
    with open(os.path.join(DATA, "tree_protos.bin"), "wb") as f:
        f.write(b"DBT1")
        f.write(struct.pack("<i", len(names)))
        for nm in names:
            ob = bpy.data.objects[nm]
            me = ob.data
            me.calc_loop_triangles()
            nt = len(me.loop_triangles)
            loops = np.empty(nt * 3, np.int32)
            me.loop_triangles.foreach_get("loops", loops)
            mi = np.empty(nt, np.int32)
            me.loop_triangles.foreach_get("material_index", mi)
            lv = np.empty(len(me.loops), np.int32)
            me.loops.foreach_get("vertex_index", lv)
            co = np.empty(len(me.vertices) * 3, np.float32)
            me.vertices.foreach_get("co", co)
            co = co.reshape(-1, 3)
            cn = np.empty(len(me.loops) * 3, np.float32)
            me.corner_normals.foreach_get("vector", cn)
            cn = cn.reshape(-1, 3)
            pos = co[lv[loops]].reshape(nt, 3, 3)[:, [0, 2, 1]]
            nrm = cn[loops].reshape(nt, 3, 3)[:, [0, 2, 1]]
            f.write(struct.pack("<i", 2))
            for m in (0, 1):   # 0 = kůra, 1 = listí / jehličí
                p, n = g3(pos[mi == m]).reshape(-1, 3), g3(nrm[mi == m]).reshape(-1, 3)
                f.write(struct.pack("<i", len(p)))
                f.write(p.astype(np.float32).tobytes())
                f.write(n.astype(np.float32).tobytes())
    print(f"WROTE tree_protos.bin: {names}")


def main():
    os.makedirs(DATA, exist_ok=True)
    os.makedirs(TEX, exist_ok=True)
    os.makedirs(os.path.dirname(OUT_BLEND), exist_ok=True)
    bpy.ops.wm.open_mainfile(filepath=SRC_BLEND)
    remove_house_model()
    restore_core_terrain()
    house = add_simple_house()
    bpy.ops.wm.save_as_mainfile(filepath=OUT_BLEND, compress=False)
    print(f"SAVED {OUT_BLEND}")

    # ---------------- výšková mapa (DMR 5G, 2 m) – jedna pravda pro kolizi i vzhled
    hm = np.load(os.path.join(ROOT, "geodata", "dtm_full_scene.npy")).astype(np.float64) - H_ref

    def hsample(x, y):
        return bilinear(hm, X0, Y1, RES, x, y)

    walls = [triangles(bpy.data.objects[n], lower_walls_to=hsample) for n in
             ("OKOLI_Budovy_steny", "OKOLI_FULL_Budovy_steny", "OKOLI_DumDomov_steny")]
    roofs = [triangles(bpy.data.objects[n]) for n in
             ("OKOLI_Budovy_strechy", "OKOLI_FULL_Budovy_strechy", "OKOLI_DumDomov_strecha")]
    asph = [triangles(bpy.data.objects[n]) for n in ("OKOLI_Komunikace_asfalt", "OKOLI_FULL_Komunikace_asfalt")]
    grav = [triangles(bpy.data.objects[n]) for n in ("OKOLI_Komunikace_strk", "OKOLI_FULL_Komunikace_strk")]

    # ruční úpravy (BLENDER_UPRAVY.md): HRA_Smazat vyřadí původní budovy / stromy, HRA_* přidají nové
    erase = [ob for ob in (bpy.data.collections["HRA_Smazat"].all_objects if "HRA_Smazat" in bpy.data.collections else [])
             if ob.type == "MESH"]

    def erased(cen_xyz):
        """Maska trojúhelníků / bodů (Blender x, y, z), které leží uvnitř některého kvádru HRA_Smazat."""
        hit = np.zeros(len(cen_xyz), bool)
        for ob in erase:
            inv = np.array(ob.matrix_world.inverted(), np.float64)
            loc = cen_xyz @ inv[:3, :3].T + inv[:3, 3]
            lo = np.array([min(v.co[i] for v in ob.data.vertices) for i in range(3)])
            hi = np.array([max(v.co[i] for v in ob.data.vertices) for i in range(3)])
            hit |= np.all((loc >= lo) & (loc <= hi), axis=1)
        return hit

    def drop_erased(parts):
        if not erase:
            return parts
        out = []
        for pos, nrm, col in parts:
            c = pos.mean(axis=1)                        # Godot (x, y, z) → Blender (x, −z, y)
            keep = ~erased(np.stack([c[:, 0], -c[:, 2], c[:, 1]], axis=1))
            out.append((pos[keep], nrm[keep], col[keep]))
        print(f"HRA_Smazat: {sum(len(p[0]) for p in parts) - sum(len(p[0]) for p in out)} triangles removed")
        return out

    walls, roofs = drop_erased(walls), drop_erased(roofs)
    for cname, target, lower in (("HRA_Steny", walls, hsample), ("HRA_Strechy", roofs, None),
                                 ("HRA_Asfalt", asph, None), ("HRA_Strk", grav, None)):
        if cname not in bpy.data.collections:
            continue
        obs = [ob for ob in bpy.data.collections[cname].all_objects if ob.type == "MESH"]
        for ob in obs:
            target.append(triangles(ob, lower_walls_to=lower))
        print(f"{cname}: {len(obs)} objects added")

    # silnice leží na terénu (+6 cm); v 2m mřížce by terén místy prostrčil – snížit vrcholy mřížky pod cestami
    road_tris = np.concatenate([np.concatenate([a[0] for a in asph]), np.concatenate([g[0] for g in grav])])
    rng = np.random.default_rng(122)
    u = rng.random((road_tris.shape[0], 24, 2))
    flip = u.sum(-1) > 1
    u[flip] = 1 - u[flip]
    A, B, C = road_tris[:, None, 0], road_tris[:, None, 1], road_tris[:, None, 2]
    S = A + (B - A) * u[..., :1] + (C - A) * u[..., 1:]
    S = np.concatenate([S.reshape(-1, 3), road_tris.reshape(-1, 3)])
    sx, sz, sy = S[:, 0], S[:, 1], -S[:, 2]       # zpět do x, y (Blender) a výška
    r = (Y1 - sy) / RES - 0.5
    c = (sx - X0) / RES - 0.5
    r0, c0 = np.floor(r).astype(int), np.floor(c).astype(int)
    before = hm.copy()
    for dr in (0, 1):
        for dc in (0, 1):
            rr = np.clip(r0 + dr, 0, GH - 1)
            cc = np.clip(c0 + dc, 0, GW - 1)
            np.minimum.at(hm, (rr, cc), sz - 0.08)
    ch = before - hm
    print(f"ROAD FLATTEN: {int((ch > 0).sum())} grid vertices lowered, max {ch.max():.2f} m, "
          f"mean {ch[ch > 0].mean():.2f} m")

    hm32 = hm.astype(np.float32)
    hm32.tofile(os.path.join(DATA, "terrain_height.bin"))
    # kolize: HeightMapShape3D má rozestup 1 → uzel se škáluje ×2 (uniformně), výšky /2
    (hm32 / RES).astype(np.float32).tofile(os.path.join(DATA, "terrain_collision.bin"))
    # normály terénu (Godot souřadnice) pro plynulé osvětlení nezávislé na LOD sítě
    gz, gx = np.gradient(hm, RES)            # gz: směr řádků (= +Z v Godotu), gx: +X
    n = np.stack([-gx, np.ones_like(hm), -gz], axis=-1)
    n /= np.linalg.norm(n, axis=-1, keepdims=True)
    ((n * 0.5 + 0.5) * 255).round().astype(np.uint8).tofile(os.path.join(DATA, "terrain_normal.bin"))
    # min/max výšky po dlaždicích 64 buněk (pro culling AABB)
    CH = 64
    ncx, ncz = math.ceil((GW - 1) / CH), math.ceil((GH - 1) / CH)
    mm = np.zeros((ncz, ncx, 2), np.float32)
    for iz in range(ncz):
        for ix in range(ncx):
            blk = hm32[iz * CH:iz * CH + CH + 1, ix * CH:ix * CH + CH + 1]
            mm[iz, ix] = blk.min(), blk.max()
    mm.tofile(os.path.join(DATA, "terrain_chunks.bin"))

    write_chunked(os.path.join(DATA, "walls.bin"), walls)
    write_chunked(os.path.join(DATA, "roofs.bin"), roofs)
    write_chunked(os.path.join(DATA, "asphalt.bin"), asph)
    write_chunked(os.path.join(DATA, "gravel.bin"), grav)

    # ---------------- stromy
    proto_names = [f"OKOLI_Strom_{k}_{i}" for k in ("dec", "con") for i in range(3)]
    export_tree_protos(proto_names)
    rows = []
    for coll_name in ("OKOLI_Vegetace", "OKOLI_FULL_Vegetace", "HRA_Stromy"):
        if coll_name not in bpy.data.collections:
            continue
        for e in bpy.data.collections[coll_name].all_objects:
            if e.instance_type != "COLLECTION" or e.instance_collection is None:
                continue
            pi = proto_names.index(e.instance_collection.name)
            rows.append([e.location.x, e.location.y, e.rotation_euler.z,
                         e.scale.x, e.scale.y, e.scale.z, *e.color[:3], pi])
    T = np.array(rows, np.float64)
    if erase:
        gone = erased(np.c_[T[:, 0], T[:, 1], hsample(T[:, 0], T[:, 1])])
        T = T[~gone]
        print(f"HRA_Smazat: {int(gone.sum())} trees removed")
    tz = hsample(T[:, 0], T[:, 1]) - 0.15
    # Godot: x, y, z, rotY, sx, výška, sz, r, g, b, proto
    out = np.c_[T[:, 0], tz, -T[:, 1], T[:, 2], T[:, 3], T[:, 5], T[:, 4], T[:, 6:9], T[:, 9]].astype(np.float32)
    with open(os.path.join(DATA, "trees.bin"), "wb") as f:
        f.write(b"DBI1")
        f.write(struct.pack("<i", len(out)))
        f.write(out.tobytes())
    print(f"WROTE trees.bin: {len(out)} trees")

    # ---------------- silnice jako graf (pro boty), předměty, spawn
    gj = jload("data/okoli_full_local.geojson")
    roads = []
    for ft in gj["features"]:
        p = ft["properties"]
        if p["kind"] != "highway" or ft["geometry"]["type"] != "LineString":
            continue
        pts = ft["geometry"]["coordinates"]
        if not point_in_poly([q[0] for q in pts], [q[1] for q in pts], admin["scene_poly"]).any():
            continue
        roads.append({"kind": p.get("highway", ""), "name": p.get("name", ""),
                      "pts": [[round(q[0], 2), round(-q[1], 2)] for q in pts]})
    print(f"ROADS for bots: {len(roads)} polylines")

    fm = np.load(os.path.join(ROOT, "data", "forest_mask_full.npz"))
    forest = fm["forest"]
    rng = random.Random(122)
    items = []

    def far_enough(x, y, kind_min):
        return all(math.hypot(x - it["x"], y + it["z"]) > kind_min for it in items)

    fr, fc = np.nonzero(forest)
    fx, fy = X0 + (fc + 0.5) * RES, Y1 - (fr + 0.5) * RES
    # předměty jen uvnitř katastru (maska lesa má okraj 150 m do sousedních obcí)
    ins = point_in_poly(fx, fy, admin["scene_poly"])
    fx, fy = fx[ins], fy[ins]
    dist = np.hypot(fx - HX, fy - HY)
    near_forest = np.nonzero(dist < 2200)[0]
    far_forest = np.nonzero(dist > 1500)[0]
    tries = 0
    while sum(1 for i in items if i["type"] == "hrib") < 30 and tries < 20000:
        tries += 1
        i = rng.choice(near_forest)
        if far_enough(fx[i], fy[i], 70):
            items.append({"type": "hrib", "x": round(float(fx[i]), 2), "z": round(float(-fy[i]), 2)})
    core_trees = [t for t in jload("data/trees_ndsm.json") if math.hypot(t["x"] - HX, t["y"] - HY) < 450
                  and t.get("type", "dec") == "dec"]
    rng.shuffle(core_trees)
    for t in core_trees:
        if sum(1 for i in items if i["type"] == "jablko") >= 20:
            break
        a = rng.uniform(0, 2 * math.pi)
        x, y = t["x"] + math.cos(a) * t["r"] * 0.6, t["y"] + math.sin(a) * t["r"] * 0.6
        if far_enough(x, y, 35):
            items.append({"type": "jablko", "x": round(x, 2), "z": round(-y, 2)})
    dense = []
    for rd in roads:
        pts = rd["pts"]
        for (x1, z1), (x2, z2) in zip(pts[:-1], pts[1:]):
            n = max(1, int(math.hypot(x2 - x1, z2 - z1) / 10))
            for k in range(n):
                dense.append((x1 + (x2 - x1) * k / n, -(z1 + (z2 - z1) * k / n)))
    dense_near = [p for p in dense if math.hypot(p[0] - HX, p[1] - HY) < 900]
    rng.shuffle(dense_near)
    for x, y in dense_near:
        if sum(1 for i in items if i["type"] == "dukat") >= 30:
            break
        if far_enough(x, y, 45):
            items.append({"type": "dukat", "x": round(x, 2), "z": round(-y, 2)})
    tries = 0
    while sum(1 for i in items if i["type"] == "zalud") < 8 and tries < 20000:
        tries += 1
        i = rng.choice(far_forest)
        if far_enough(fx[i], fy[i], 500):
            items.append({"type": "zalud", "x": round(float(fx[i]), 2), "z": round(float(-fy[i]), 2)})
    print("ITEMS:", {k: sum(1 for i in items if i["type"] == k) for k in ("hrib", "jablko", "dukat", "zalud")})

    # spawn: nejbližší bod silnice k domu hráče, pohled k domu
    hx = sum(p[0] for p in house["polygon"]) / len(house["polygon"])
    hy = sum(p[1] for p in house["polygon"]) / len(house["polygon"])
    sp = min(dense, key=lambda p: math.hypot(p[0] - hx, p[1] - hy))
    spawn = {"x": round(sp[0], 2), "z": round(-sp[1], 2), "look_x": round(hx, 2), "look_z": round(-hy, 2)}

    mp = {
        "version": 1,
        "source": "mapa_okoli.blend → blend/mapa.blend",
        "license": "Geodata © ČÚZK (CC BY 4.0), OSM © přispěvatelé OpenStreetMap (ODbL), textury Poly Haven (CC0)",
        "height": {"file": "terrain_height.bin", "w": GW, "h": GH, "spacing": RES,
                   "x0": X0 + RES / 2, "z0": -Y1 + RES / 2, "chunk_cells": CH, "ncx": ncx, "ncz": ncz},
        "ortho_full": {"file": "res://textures/ortho_full.jpg", "x0": X0, "z0": -Y1,
                       "size_x": GW * RES, "size_z": GH * RES},
        "ortho_core": {"file": "res://textures/ortho_core.jpg", "x0": meta_c["grid_x0"], "z0": -meta_c["grid_y1"],
                       "size_x": 2 * meta_c["half"], "size_z": 2 * meta_c["half"]},
        "north_angle_deg": ref["north_angle_deg"],
        "domov_hrace": {"x": round(hx, 2), "z": round(-hy, 2)},
        "spawn": spawn,
        "boundary": [[round(p[0], 1), round(-p[1], 1)] for p in admin["scene_poly"]],
        "roads": roads,
        "items": items,
    }
    json.dump(mp, open(os.path.join(DATA, "map.json"), "w"), ensure_ascii=False)
    print("WROTE map.json")

    # ---------------- textury
    shutil.copy(os.path.join(ROOT, "geodata", "ortho_full_scene.jpg"), os.path.join(TEX, "ortho_full.jpg"))
    shutil.copy(os.path.join(ROOT, "geodata", "ortho_scene.jpg"), os.path.join(TEX, "ortho_core.jpg"))
    for tid in ("beige_wall_001", "clay_roof_tiles_02", "asphalt_02", "gravel_road", "bark_brown_02"):
        d = os.path.join(ROOT, "assets", "materials", f"ph_{tid}")
        for fn in os.listdir(d):
            shutil.copy(os.path.join(d, fn), os.path.join(TEX, fn))
    shutil.copy(os.path.join(ROOT, "assets", "hdrs", "ph_kloofendal_48d_partly_cloudy_puresky",
                             "kloofendal_48d_partly_cloudy_puresky_4k.hdr"), os.path.join(TEX, "sky.hdr"))
    print("TEXTURES copied")


main()
