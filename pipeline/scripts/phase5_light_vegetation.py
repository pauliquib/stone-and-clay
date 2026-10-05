"""Fáze 5 – HDRI osvětlení, vegetace, doladění.

Spuštění:
    blender --background blend/Doubravy_3D_okoli_v2.blend --python pipeline/scripts/phase5_light_vegetation.py

- HDRI z pipeline/assets/hdrs (preferuje venkovní/denní: sky, outdoor, field, meadow,
  park, sunny…); expozice/síla nastavená pro Filmic/AgX
- stromy: OSM natural=tree body + model stromu z pipeline/assets/models (pokud existuje),
  jinak procedurální strom (válec + koule/kužel) jako instance kolekce
- lesní plochy (landuse=forest / natural=wood) se osázejí náhodně rozmístěnými
  stromy (deterministický seed), zahrady řidčeji
- uloží blend/Doubravy_3D_okoli_final.blend + render pipeline/renders/phase5_final.png
"""
import math
import os
import random
import sys

import bpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import okoli_common as oc  # noqa: E402

ref = oc.load_json("data/scene_reference.json")
gj = oc.load_json("data/okoli_local.geojson")
mpu = ref.get("meters_per_unit", 1.0)
GZ = ref.get("ground_z", 0.0)
HX, HY = ref["house_scene_xy"]
KEEP = ref.get("keep_out_bbox")


def m(v):
    return v / mpu


# ------------------------------------------------------------------ HDRI

def pick_hdri():
    base = os.path.join(oc.ASSETS, "hdrs")
    cands = []
    for dp, _, fs in os.walk(base):
        for f in fs:
            if f.lower().endswith((".hdr", ".exr")):
                cands.append(os.path.join(dp, f))
    if not cands:
        # pipeline/assets/hdrs je prázdné → venkovní HDRI dodávané s Blenderem
        import glob
        for name in ("forest.exr", "courtyard.exr"):
            hits = sorted(glob.glob(os.path.join(os.path.dirname(bpy.app.binary_path), "..", "share", "blender",
                                                 "*", "datafiles", "studiolights", "world", name)) +
                          glob.glob(os.path.join(bpy.utils.resource_path("LOCAL"), "datafiles", "studiolights",
                                                 "world", name)) +
                          glob.glob(f"/usr/share/blender/*/datafiles/studiolights/world/{name}"))
            if hits:
                print("HDRI fallback (assets/hdrs empty):", hits[0])
                return os.path.realpath(hits[0])
        return None
    good = ("sky", "outdoor", "field", "meadow", "park", "sunny", "country", "rural", "village", "farm",
            "afternoon", "noon", "day", "partly", "cloud", "hill", "grass")
    bad = ("night", "studio", "indoor", "interior", "room", "sunset", "dusk", "moon", "garage", "hall")

    def score(p):
        n = os.path.basename(p).lower()
        s = sum(2 for g in good if g in n) - sum(5 for b in bad if b in n)
        s -= 1 if any(r in n for r in ("8k", "16k")) else 0  # paměť
        s += 1 if any(r in n for r in ("2k", "4k")) else 0
        return s

    cands.sort(key=score, reverse=True)
    print("HDRI candidates:", [(os.path.basename(c), score(c)) for c in cands[:8]])
    return cands[0]


def setup_world(hdri):
    scene = bpy.context.scene
    world = bpy.data.worlds.get("OKOLI_World") or bpy.data.worlds.new("OKOLI_World")
    world.use_nodes = True
    nt = world.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputWorld")
    bg = nt.nodes.new("ShaderNodeBackground")
    nt.links.new(bg.outputs["Background"], out.inputs["Surface"])
    if hdri:
        env = nt.nodes.new("ShaderNodeTexEnvironment")
        env.image = bpy.data.images.load(hdri, check_existing=True)
        tc = nt.nodes.new("ShaderNodeTexCoord")
        mp = nt.nodes.new("ShaderNodeMapping")
        nt.links.new(tc.outputs["Generated"], mp.inputs["Vector"])
        nt.links.new(mp.outputs["Vector"], env.inputs["Vector"])
        nt.links.new(env.outputs["Color"], bg.inputs["Color"])
        bg.inputs["Strength"].default_value = 0.8
    else:
        sky = nt.nodes.new("ShaderNodeTexSky")
        nt.links.new(sky.outputs["Color"], bg.inputs["Color"])
        bg.inputs["Strength"].default_value = 0.3
    scene.world = world
    vs = scene.view_settings
    # AgX/Filmic nemusí být k dispozici (OCIO fallback v CLI má jen "Standard")
    for vt, look in (("AgX", "AgX - Medium High Contrast"), ("Filmic", "Medium High Contrast")):
        try:
            vs.view_transform = vt
            try:
                vs.look = look
            except TypeError:
                pass
            break
        except TypeError:
            continue
    print("VIEW transform:", vs.view_transform)
    # scéna má 2 slunce (~6,5 W/m²) + HDRI; se Standard je potřeba víc ztlumit
    vs.exposure = -1.0 if vs.view_transform == "Standard" else -0.5
    # slunce – pokud ve scéně žádné není, přidej jemné (HDRI má často slabé stíny)
    if not any(o.type == "LIGHT" and o.data.type == "SUN" for o in bpy.data.objects if not o.hide_render):
        ld = bpy.data.lights.get("OKOLI_Slunce") or bpy.data.lights.new("OKOLI_Slunce", "SUN")
        ld.energy = 3.0
        ld.angle = math.radians(1.5)
        so = bpy.data.objects.get("OKOLI_Slunce") or bpy.data.objects.new("OKOLI_Slunce", ld)
        if not so.users_collection:
            oc.get_coll(oc.ROOT_COLL).objects.link(so)
        # odpolední slunce z jihozápadu (vůči severu scény)
        north = math.radians(ref.get("north_angle_deg", 0.0))
        so.rotation_euler = (math.radians(50), 0, north + math.radians(180 + 45))
        return hdri, True
    return hdri, False


# ------------------------------------------------------------------ trees

def find_tree_asset():
    base = os.path.join(oc.ASSETS, "models")
    if not os.path.isdir(base):
        return None
    for dp, _, fs in os.walk(base):
        for f in sorted(fs):
            n = f.lower()
            if any(k in n for k in ("tree", "strom", "oak", "birch", "maple", "linden", "lipa", "dub", "bříza", "pine")):
                return os.path.join(dp, f)
    return None


def import_tree(path, lib_coll):
    before = set(bpy.data.objects)
    ext = path.lower().rsplit(".", 1)[-1]
    try:
        if ext == "blend":
            with bpy.data.libraries.load(path, link=False) as (src, dst):
                dst.objects = [n for n in src.objects]
            for o in dst.objects:
                if o and o.type in {"MESH", "CURVE", "EMPTY"}:
                    lib_coll.objects.link(o)
        elif ext in {"glb", "gltf"}:
            bpy.ops.import_scene.gltf(filepath=path)
        elif ext == "fbx":
            bpy.ops.import_scene.fbx(filepath=path)
        elif ext == "obj":
            (bpy.ops.wm.obj_import if hasattr(bpy.ops.wm, "obj_import") else bpy.ops.import_scene.obj)(filepath=path)
        else:
            return None
    except Exception as e:
        print("WARN tree import failed", path, e)
        return None
    new = [o for o in bpy.data.objects if o not in before]
    for o in new:
        for c in list(o.users_collection):
            if c != lib_coll:
                c.objects.unlink(o)
        if lib_coll not in o.users_collection:
            lib_coll.objects.link(o)
    meshes = [o for o in new if o.type == "MESH"]
    if not meshes:
        return None
    # normalizuj: pata stromu v počátku, výška ~ 1 BU-metr (škáluje se při instanci)
    from mathutils import Vector
    pts = [o.matrix_world @ Vector(c) for o in meshes for c in o.bound_box]
    zmin = min(p.z for p in pts)
    h = max(p.z for p in pts) - zmin
    cx = sum(p.x for p in pts) / len(pts)
    cy = sum(p.y for p in pts) / len(pts)
    roots = [o for o in new if o.parent is None]
    for o in roots:
        o.location.x -= cx
        o.location.y -= cy
        o.location.z -= zmin
    return max(h, 1e-3)


def procedural_tree(lib_coll):
    """Listnatý strom (kmen + koruna ze 3 koulí) a jehličnan (kmen + kužel), výška 1."""
    bark = oc.make_material("OKOLI_Kura", ["bark", "wood"], (0.25, 0.18, 0.12), 0.9, 0.3)
    leaf = oc.make_material("OKOLI_Listi", ["leaves", "foliage", "leaf"], (0.16, 0.3, 0.09), 0.8, 0.3)
    conif = oc.make_material("OKOLI_Jehlici", ["needle", "pine", "conifer"], (0.09, 0.2, 0.08), 0.8, 0.3)
    for m_ in (leaf, conif):
        try:
            b = m_.node_tree.nodes.get("Principled BSDF")
            b.inputs["Subsurface Weight"].default_value = 0.1
        except Exception:
            pass
    import bmesh

    def build(name, parts):
        bm = bmesh.new()
        me = bpy.data.meshes.new(name)
        for kind, mat_i, args in parts:
            geom = None
            if kind == "cyl":
                r1, r2, h, z = args
                geom = bmesh.ops.create_cone(bm, cap_ends=True, segments=8, radius1=r1, radius2=r2, depth=h)
                bmesh.ops.translate(bm, verts=geom["verts"], vec=(0, 0, z + h / 2))
            elif kind == "sph":
                r, x, y, z = args
                geom = bmesh.ops.create_icosphere(bm, subdivisions=2, radius=r)
                bmesh.ops.translate(bm, verts=geom["verts"], vec=(x, y, z))
            fs = {f for v in geom["verts"] for f in v.link_faces}
            for f in fs:
                f.material_index = mat_i
                f.smooth = kind == "sph"
        bm.to_mesh(me)
        bm.free()
        ob = bpy.data.objects.new(name, me)
        lib_coll.objects.link(ob)
        return ob

    dec = build("OKOLI_StromListnaty", [("cyl", 0, (0.035, 0.025, 0.45, 0)),
                                         ("sph", 1, (0.3, 0, 0, 0.62)),
                                         ("sph", 1, (0.22, 0.13, 0.05, 0.78)),
                                         ("sph", 1, (0.2, -0.1, -0.08, 0.8))])
    dec.data.materials.append(bark)
    dec.data.materials.append(leaf)
    con = build("OKOLI_StromJehlicnan", [("cyl", 0, (0.03, 0.02, 0.2, 0)),
                                          ("cyl", 1, (0.22, 0.0, 0.85, 0.15))])
    con.data.materials.append(bark)
    con.data.materials.append(conif)
    return [dec, con]


def instancer(proto_coll, name, coll, loc, h, rot):
    e = bpy.data.objects.new(name, None)
    e.instance_type = "COLLECTION"
    e.instance_collection = proto_coll
    e.location = loc
    e.scale = (h, h, h)
    e.rotation_euler = (0, 0, rot)
    coll.objects.link(e)
    return e


def in_keep(x, y):
    return KEEP and KEEP[0] - m(2) <= x <= KEEP[2] + m(2) and KEEP[1] - m(2) <= y <= KEEP[3] + m(2)


def building_polys():
    return [oc.open_ring(f["geometry"]["coordinates"][0]) for f in gj["features"]
            if f["properties"]["kind"] == "building" and f["geometry"]["type"] == "Polygon"]


def road_segments():
    segs = []
    for f in gj["features"]:
        if f["properties"]["kind"] == "highway" and f["geometry"]["type"] == "LineString":
            c = f["geometry"]["coordinates"]
            segs += [(c[i], c[i + 1]) for i in range(len(c) - 1)]
    return segs


def dist_seg(px, py, a, b):
    ax, ay = a
    bx, by = b
    dx, dy = bx - ax, by - ay
    L = dx * dx + dy * dy
    t = 0 if L == 0 else max(0, min(1, ((px - ax) * dx + (py - ay) * dy) / L))
    return math.hypot(px - ax - t * dx, py - ay - t * dy)


def main():
    hdri, sun_added = setup_world(pick_hdri())
    print("HDRI:", hdri, "sun_added:", sun_added)

    lib = bpy.data.collections.get("OKOLI_StromyKnihovna") or bpy.data.collections.new("OKOLI_StromyKnihovna")
    if lib.name not in [c.name for c in bpy.context.scene.collection.children]:
        bpy.context.scene.collection.children.link(lib)
    for o in list(lib.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    for c in list(lib.children):
        lib.children.unlink(c)
    lib.hide_render = True
    lib.hide_viewport = False

    tree_path = find_tree_asset()
    protos = []
    base_h = 1.0
    if tree_path:
        sub = bpy.data.collections.new("OKOLI_Strom_asset")
        lib.children.link(sub)
        h = import_tree(tree_path, sub)
        if h:
            base_h = h
            protos = [(sub, base_h, "asset")]
            print("TREE asset:", tree_path, "height", h)
    if not protos:
        dec, con = procedural_tree(lib)
        for ob, nm in ((dec, "dec"), (con, "con")):
            c = bpy.data.collections.new(f"OKOLI_Strom_{nm}")
            lib.children.link(c)
            lib.objects.unlink(ob)
            c.objects.link(ob)
            protos.append((c, 1.0, nm))
        print("TREE procedural (no model in assets/models)")
    # prototypy nesmí být vidět v renderu – kolekce knihovny je vyřazená z view layeru
    for lc in bpy.context.view_layer.layer_collection.children:
        if lc.collection == lib:
            lc.exclude = True

    coll = oc.sub_coll("OKOLI_Vegetace")
    oc.clear_coll(coll)
    rnd = random.Random(122)
    bpolys = building_polys()
    rsegs = road_segments()

    def free_spot(x, y, clear):
        if in_keep(x, y) or math.hypot(x - HX, y - HY) > m(450):
            return False
        for s in rsegs:
            if dist_seg(x, y, *s) < clear:
                return False
        for bp in bpolys:
            if len(bp) >= 3 and oc.point_in_poly(x, y, bp):
                return False
        return True

    def proto_for(kind):
        if len(protos) == 1:
            return protos[0]
        return protos[1] if kind == "con" else protos[0]

    n_osm = n_fill = 0
    # 1) OSM stromy
    for f in gj["features"]:
        p = f["properties"]
        if p["kind"] != "tree":
            continue
        x, y = f["geometry"]["coordinates"]
        if in_keep(x, y):
            continue
        try:
            h = float(p["height"].replace(",", ".").split()[0].rstrip("m"))
        except (KeyError, ValueError, IndexError):
            h = rnd.uniform(8, 14)
        kind = "con" if p.get("leaf_type") == "needleleaved" else "dec"
        pc, ph, _ = proto_for(kind)
        instancer(pc, f"OKOLI_Strom_osm_{p['osm_id']}", coll, (x, y, GZ), m(h) / ph, rnd.uniform(0, 6.283))
        n_osm += 1
    # 2) les a zahrady – náhodná výsadba v polygonech
    dens = {"forest": 1 / 60.0, "wood": 1 / 60.0, "orchard": 1 / 80.0, "scrub": 1 / 120.0,
            "residential": 1 / 900.0, "garden": 1 / 250.0}
    for f in gj["features"]:
        p = f["properties"]
        if p["kind"] != "landuse" or f["geometry"]["type"] != "Polygon":
            continue
        t = p.get("landuse") or p.get("natural")
        if t not in dens:
            continue
        ring = oc.open_ring(f["geometry"]["coordinates"][0])
        holes = [oc.open_ring(r) for r in f["geometry"]["coordinates"][1:]]
        area = abs(oc.ring_area(ring)) * mpu * mpu
        n = min(int(area * dens[t]), 2500)
        xs = [q[0] for q in ring]
        ys = [q[1] for q in ring]
        tries = 0
        placed = 0
        while placed < n and tries < n * 8:
            tries += 1
            x, y = rnd.uniform(min(xs), max(xs)), rnd.uniform(min(ys), max(ys))
            if not oc.point_in_poly(x, y, ring) or any(oc.point_in_poly(x, y, h) for h in holes):
                continue
            if not free_spot(x, y, m(4)):
                continue
            kind = "con" if (t in {"forest", "wood"} and rnd.random() < 0.45) else "dec"
            hgt = rnd.uniform(14, 24) if t in {"forest", "wood"} else rnd.uniform(4, 9) if t == "orchard" \
                else rnd.uniform(5, 12)
            pc, ph, _ = proto_for(kind)
            instancer(pc, f"OKOLI_Strom_{t}_{placed}", coll, (x, y, GZ), m(hgt) / ph, rnd.uniform(0, 6.283))
            placed += 1
        n_fill += placed
    # 3) pokud OSM nemá skoro žádnou vegetaci, doplň řídké stromy do zahrad kolem domů
    if n_osm + n_fill < 40:
        extra = 0
        for bp in bpolys:
            if len(bp) < 3 or rnd.random() > 0.6:
                continue
            cx = sum(q[0] for q in bp) / len(bp)
            cy = sum(q[1] for q in bp) / len(bp)
            for _ in range(2):
                a = rnd.uniform(0, 6.283)
                d = m(rnd.uniform(9, 18))
                x, y = cx + d * math.cos(a), cy + d * math.sin(a)
                if free_spot(x, y, m(4.5)):
                    pc, ph, _ = proto_for("dec")
                    instancer(pc, f"OKOLI_Strom_zahrada_{extra}", coll, (x, y, GZ), m(rnd.uniform(5, 10)) / ph,
                              rnd.uniform(0, 6.283))
                    extra += 1
        n_fill += extra
    print(f"TREES osm={n_osm} filled={n_fill}")

    scene = bpy.context.scene
    engines = [e.identifier for e in bpy.types.RenderSettings.bl_rna.properties["engine"].enum_items]
    try:
        eevee = scene.eevee
        if hasattr(eevee, "use_shadows"):
            eevee.use_shadows = True
        if hasattr(eevee, "use_gtao"):
            eevee.use_gtao = True
    except Exception:
        pass
    print("engines:", engines)

    os.makedirs(oc.BLEND_DIR, exist_ok=True)
    out = os.path.join(oc.BLEND_DIR, "Doubravy_3D_okoli_final.blend")
    bpy.ops.wm.save_as_mainfile(filepath=out, copy=True)
    print("SAVED", out)
    os.makedirs(os.path.join(oc.ROOT, "renders"), exist_ok=True)
    oc.control_render(ref, os.path.join(oc.ROOT, "renders", "phase5_final.png"), samples=32)


main()
