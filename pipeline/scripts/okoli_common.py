"""Sdílené pomocné funkce pro bpy skripty okolí (fáze 3–5).

Všechny generované objekty jdou do kolekce `OKOLI_OSM` (a podkolekcí), model
domu a pozemku se nikdy nemění. Staré jednoduché okolí (seznam v
scene_reference.json → `old_surroundings`) se jen skryje, nemaže se.
"""
import json
import math
import os

import bpy

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)          # pipeline/ – data/, assets/, renders/, logs/
GAME = os.path.dirname(ROOT)          # kořen repozitáře hry – geodata/, blend/
GEO = os.path.join(GAME, "geodata")
BLEND_DIR = os.path.join(GAME, "blend")
ASSETS = os.path.join(ROOT, "assets")
ROOT_COLL = "OKOLI_OSM"

IMG_EXT = (".jpg", ".jpeg", ".png", ".tif", ".tiff", ".exr", ".webp")


def load_json(rel):
    with open(os.path.join(ROOT, rel), encoding="utf-8") as f:
        return json.load(f)


def get_coll(name, parent=None):
    parent = parent or bpy.context.scene.collection
    c = bpy.data.collections.get(name)
    if c is None:
        c = bpy.data.collections.new(name)
    if c.name not in [ch.name for ch in parent.children]:
        parent.children.link(c)
    return c


def sub_coll(name):
    return get_coll(name, get_coll(ROOT_COLL))


def clear_coll(coll):
    for o in list(coll.objects):
        bpy.data.objects.remove(o, do_unlink=True)


def hide_old_surroundings(ref):
    names = ref.get("old_surroundings", {})
    hidden = []
    for n in names.get("objects", []):
        o = bpy.data.objects.get(n)
        if o:
            o.hide_render = True
            o.hide_set(True) if bpy.context.view_layer.objects.get(n) else None
            o.hide_viewport = True
            hidden.append(n)
    for n in names.get("collections", []):
        c = bpy.data.collections.get(n)
        if c:
            c.hide_render = True
            c.hide_viewport = True
            hidden.append(n)
    return hidden


# ---------------------------------------------------------------- materials

def _find_texture_sets():
    """Najde v assets/materials sady textur: {jméno_sady: {slot: cesta}}.

    Sada = složka (nebo prefix souboru); sloty podle klíčových slov v názvu.
    """
    base = os.path.join(ASSETS, "materials")
    sets = {}
    if not os.path.isdir(base):
        return sets
    slot_kw = [
        ("normal", ("normal", "nor_gl", "_nrm", "_nor", "norm")),
        ("roughness", ("rough", "_rgh")),
        ("displacement", ("disp", "height", "_dis")),
        ("ao", ("_ao", "ambientocclusion", "occlusion")),
        ("metal", ("metal",)),
        ("color", ("diff", "albedo", "basecolor", "base_color", "color", "col", "_d.")),
    ]
    for dirpath, _, files in os.walk(base):
        for fn in files:
            if not fn.lower().endswith(IMG_EXT):
                continue
            low = fn.lower()
            rel = os.path.relpath(dirpath, base)
            key = rel if rel != "." else low.split("_")[0]
            slot = None
            for s, kws in slot_kw:
                if any(k in low for k in kws):
                    slot = s
                    break
            if slot is None:
                slot = "color"
            d = sets.setdefault(key, {})
            # preferuj menší rozlišení kvůli paměti (1k/2k před 4k/8k)
            if slot in d and not any(r in low for r in ("1k", "2k")):
                continue
            d[slot] = os.path.join(dirpath, fn)
    return sets


_TEX_SETS = None


def texture_sets():
    global _TEX_SETS
    if _TEX_SETS is None:
        _TEX_SETS = _find_texture_sets()
    return _TEX_SETS


def _blend_materials():
    base = os.path.join(ASSETS, "materials")
    out = {}
    if not os.path.isdir(base):
        return out
    for dirpath, _, files in os.walk(base):
        for fn in files:
            if fn.lower().endswith(".blend"):
                p = os.path.join(dirpath, fn)
                try:
                    with bpy.data.libraries.load(p, link=False) as (src, _dst):
                        for m in src.materials:
                            out[m] = p
                except Exception as e:  # poškozený / novější formát
                    print("WARN cannot read", p, e)
    return out


def pick_set(keywords):
    """Vrátí (jméno, sloty) první sady textur odpovídající některému klíčovému slovu."""
    sets = texture_sets()
    for kw in keywords:
        for name in sorted(sets):
            if kw in name.lower() and "color" in sets[name]:
                return name, sets[name]
    return None, None


def make_material(name, keywords, fallback_rgb, roughness=0.8, scale=1.0):
    """Materiál z textur v assets/materials (triplanar přes Box projekci v
    objektových/světových souřadnicích), jinak jednobarevný Principled BSDF."""
    mat = bpy.data.materials.get(name)
    if mat:
        return mat
    # 1) materiál z .blend knihovny v pipeline/assets/materials
    for mname, path in _blend_materials().items():
        if any(kw in mname.lower() for kw in keywords):
            with bpy.data.libraries.load(path, link=False) as (src, dst):
                dst.materials = [mname]
            m = dst.materials[0]
            m.name = name
            print(f"MAT {name}: appended '{mname}' from {os.path.basename(path)}")
            return m
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = nt.nodes.get("Principled BSDF")
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Base Color"].default_value = (*fallback_rgb, 1.0)
    set_name, slots = pick_set(keywords)
    if not slots:
        # procedurální variace barvy (šum) + jemný reliéf – pipeline/assets/materials je prázdné
        tc = nt.nodes.new("ShaderNodeTexCoord")
        noise = nt.nodes.new("ShaderNodeTexNoise")
        noise.inputs["Scale"].default_value = 0.35 / max(scale, 1e-3)
        noise.inputs["Detail"].default_value = 6.0
        nt.links.new(tc.outputs["Object"], noise.inputs["Vector"])
        ramp = nt.nodes.new("ShaderNodeValToRGB")
        dark = tuple(c * 0.72 for c in fallback_rgb)
        light = tuple(min(1.0, c * 1.18) for c in fallback_rgb)
        ramp.color_ramp.elements[0].color = (*dark, 1)
        ramp.color_ramp.elements[1].color = (*light, 1)
        nt.links.new(noise.outputs["Fac"], ramp.inputs["Fac"])
        nt.links.new(ramp.outputs["Color"], bsdf.inputs["Base Color"])
        fine = nt.nodes.new("ShaderNodeTexNoise")
        fine.inputs["Scale"].default_value = 8.0 / max(scale, 1e-3)
        nt.links.new(tc.outputs["Object"], fine.inputs["Vector"])
        bump = nt.nodes.new("ShaderNodeBump")
        bump.inputs["Strength"].default_value = 0.25
        nt.links.new(fine.outputs["Fac"], bump.inputs["Height"])
        nt.links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
        print(f"MAT {name}: no texture for {keywords}, procedural colour")
        return mat
    tc = nt.nodes.new("ShaderNodeTexCoord")
    mp = nt.nodes.new("ShaderNodeMapping")
    mp.inputs["Scale"].default_value = (1.0 / scale, 1.0 / scale, 1.0 / scale)
    nt.links.new(tc.outputs["Object"], mp.inputs["Vector"])

    def img(slot, noncolor):
        if slot not in slots:
            return None
        n = nt.nodes.new("ShaderNodeTexImage")
        n.image = bpy.data.images.load(slots[slot], check_existing=True)
        n.projection = "BOX"
        n.projection_blend = 0.2
        if noncolor:
            n.image.colorspace_settings.name = "Non-Color"
        nt.links.new(mp.outputs["Vector"], n.inputs["Vector"])
        return n

    c = img("color", False)
    nt.links.new(c.outputs["Color"], bsdf.inputs["Base Color"])
    r = img("roughness", True)
    if r:
        nt.links.new(r.outputs["Color"], bsdf.inputs["Roughness"])
    n = img("normal", True)
    if n:
        nm = nt.nodes.new("ShaderNodeNormalMap")
        nm.inputs["Strength"].default_value = 0.6
        nt.links.new(n.outputs["Color"], nm.inputs["Color"])
        nt.links.new(nm.outputs["Normal"], bsdf.inputs["Normal"])
    print(f"MAT {name}: textures from '{set_name}' {sorted(slots)}")
    return mat


# ---------------------------------------------------------------- geometry

def ring_area(pts):
    a = 0.0
    for i in range(len(pts)):
        x1, y1 = pts[i]
        x2, y2 = pts[(i + 1) % len(pts)]
        a += x1 * y2 - x2 * y1
    return a / 2.0


def open_ring(ring):
    pts = [tuple(p) for p in ring]
    if len(pts) > 1 and pts[0] == pts[-1]:
        pts = pts[:-1]
    # odstraň duplicitní sousední body
    out = []
    for p in pts:
        if not out or (abs(p[0] - out[-1][0]) > 1e-3 or abs(p[1] - out[-1][1]) > 1e-3):
            out.append(p)
    return out


def ccw(pts):
    return pts if ring_area(pts) > 0 else pts[::-1]


def point_in_poly(x, y, pts):
    inside = False
    n = len(pts)
    for i in range(n):
        x1, y1 = pts[i]
        x2, y2 = pts[(i + 1) % n]
        if (y1 > y) != (y2 > y) and x < (x2 - x1) * (y - y1) / (y2 - y1 + 1e-12) + x1:
            inside = not inside
    return inside


def convex_hull(pts):
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


def min_area_rect(pts):
    """Minimální orientovaný obdélník → (cx, cy, length, width, angle) kde
    angle je směr delší strany (hřebene)."""
    hull = convex_hull(pts)
    best = None
    for i in range(len(hull)):
        x1, y1 = hull[i]
        x2, y2 = hull[(i + 1) % len(hull)]
        a = math.atan2(y2 - y1, x2 - x1)
        c, s = math.cos(a), math.sin(a)
        us = [x * c + y * s for x, y in hull]
        vs = [-x * s + y * c for x, y in hull]
        area = (max(us) - min(us)) * (max(vs) - min(vs))
        if best is None or area < best[0]:
            best = (area, a, min(us), max(us), min(vs), max(vs))
    _, a, u0, u1, v0, v1 = best
    c, s = math.cos(a), math.sin(a)
    uc, vc = (u0 + u1) / 2, (v0 + v1) / 2
    cx, cy = uc * c - vc * s, uc * s + vc * c
    L, W = u1 - u0, v1 - v0
    if W > L:
        L, W, a = W, L, a + math.pi / 2
    return cx, cy, L, W, a


def mesh_object(name, verts, faces, coll, mat=None, smooth=False):
    me = bpy.data.meshes.new(name)
    me.from_pydata(verts, [], faces)
    me.validate(clean_customdata=False)
    me.update()
    ob = bpy.data.objects.new(name, me)
    coll.objects.link(ob)
    if mat:
        if isinstance(mat, (list, tuple)):
            for m in mat:
                me.materials.append(m)
        else:
            me.materials.append(mat)
    if smooth:
        for p in me.polygons:
            p.use_smooth = True
    return ob


def join_objects(objs, name):
    """Spojí objekty do jednoho (méně objektů = rychlejší scéna)."""
    import bmesh
    if not objs:
        return None
    bm = bmesh.new()
    mats = []
    for o in objs:
        tmp = bmesh.new()
        tmp.from_mesh(o.data)
        tmp.transform(o.matrix_world)
        slot_map = {}
        for i, m in enumerate(o.data.materials):
            if m not in mats:
                mats.append(m)
            slot_map[i] = mats.index(m)
        for f in tmp.faces:
            f.material_index = slot_map.get(f.material_index, 0)
        me_tmp = bpy.data.meshes.new("_tmp")
        tmp.to_mesh(me_tmp)
        bm.from_mesh(me_tmp)
        bpy.data.meshes.remove(me_tmp)
        tmp.free()
    coll = objs[0].users_collection[0]
    for o in objs:
        me = o.data
        bpy.data.objects.remove(o, do_unlink=True)
        if me.users == 0:
            bpy.data.meshes.remove(me)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    for m in mats:
        me.materials.append(m)
    ob = bpy.data.objects.new(name, me)
    coll.objects.link(ob)
    return ob


# ---------------------------------------------------------------- render

def control_render(ref, out_png, radius=180.0, iso=True, samples=16):
    """Jeden kontrolní render 800×600 (izometrický pohled na okolí domu)."""
    scene = bpy.context.scene
    hx, hy = ref["house_scene_xy"]
    gz = ref.get("ground_z", 0.0)
    cam_data = bpy.data.cameras.get("CAM_Kontrola_OKOLI") or bpy.data.cameras.new("CAM_Kontrola_OKOLI")
    cam = bpy.data.objects.get("CAM_Kontrola_OKOLI")
    if cam is None:
        cam = bpy.data.objects.new("CAM_Kontrola_OKOLI", cam_data)
        get_coll(ROOT_COLL).objects.link(cam)
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = radius * 2.0
    cam_data.clip_end = 5000
    if iso:
        d = radius * 2.0
        cam.location = (hx + d * 0.6, hy - d * 0.6, gz + d * 0.75)
        cam.rotation_euler = (math.radians(52), 0, math.radians(45))
    else:
        cam.location = (hx, hy, gz + 800)
        cam.rotation_euler = (0, 0, 0)
    prev_cam = scene.camera
    prev = (scene.render.resolution_x, scene.render.resolution_y, scene.render.resolution_percentage,
            scene.render.filepath, scene.render.engine)
    scene.camera = cam
    scene.render.resolution_x, scene.render.resolution_y = 800, 600
    scene.render.resolution_percentage = 100
    engines = [e.identifier for e in bpy.types.RenderSettings.bl_rna.properties["engine"].enum_items]
    scene.render.engine = "BLENDER_EEVEE_NEXT" if "BLENDER_EEVEE_NEXT" in engines else "BLENDER_EEVEE"
    try:
        scene.eevee.taa_render_samples = samples
    except Exception:
        pass
    scene.render.filepath = out_png
    try:
        bpy.ops.render.render(write_still=True)
        print("RENDER", out_png)
    except Exception as e:
        print("RENDER EEVEE FAILED", e, "- trying Workbench")
        scene.render.engine = "BLENDER_WORKBENCH"
        bpy.ops.render.render(write_still=True)
    # vrať nastavení scény
    scene.camera = prev_cam or cam
    (scene.render.resolution_x, scene.render.resolution_y, scene.render.resolution_percentage,
     scene.render.filepath, scene.render.engine) = prev
