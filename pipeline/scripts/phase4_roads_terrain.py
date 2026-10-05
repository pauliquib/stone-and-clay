"""Fáze 4 – komunikace a terén (landuse plochy).

Spuštění:
    blender --background blend/Doubravy_3D_okoli_v1.blend --python pipeline/scripts/phase4_roads_terrain.py

- základní terén: rovinná deska (kruh r = 480 m) mírně pod úrovní pozemku,
  materiál louka/tráva (výškový model není k dispozici – viz log)
- landuse plochy (meadow/grass/farmland/residential/forest/orchard…) jako
  polygony těsně nad deskou s odpovídajícím materiálem
- silnice z OSM jako pásy (šířka podle typu highway), asfalt vs. štěrk podle
  typu/`surface`
- vrstvy leží těsně POD úrovní ground_z, takže pozemek domu (na ground_z)
  zůstává vždy navrchu a nic ho nepřekrývá
- uloží blend/Doubravy_3D_okoli_v2.blend + render pipeline/renders/phase4_v2.png
"""
import math
import os
import sys

import bpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import okoli_common as oc  # noqa: E402

ref = oc.load_json("data/scene_reference.json")
gj = oc.load_json("data/okoli_local.geojson")
mpu = ref.get("meters_per_unit", 1.0)
GZ = ref.get("ground_z", 0.0)
HX, HY = ref["house_scene_xy"]


def m(v):
    return v / mpu


Z_BASE = GZ - m(0.12)
Z_LANDUSE = GZ - m(0.09)
Z_ROAD = GZ - m(0.04)

ROAD_W = {  # šířka v metrech
    "motorway": 12, "trunk": 10, "primary": 8, "secondary": 7, "tertiary": 6.5,
    "unclassified": 5.5, "residential": 5.5, "living_street": 5, "service": 3.5,
    "track": 3, "path": 1.5, "footway": 1.8, "cycleway": 2, "steps": 1.5, "bridleway": 2,
}
GRAVEL_HW = {"track", "path", "bridleway"}
GRAVEL_SURF = {"gravel", "unpaved", "ground", "dirt", "compacted", "fine_gravel", "grass", "earth", "mud"}

LANDUSE_MAT = {
    "forest": "les", "wood": "les", "scrub": "les",
    "meadow": "louka", "grass": "louka", "grassland": "louka", "village_green": "louka",
    "recreation_ground": "louka", "park": "louka",
    "farmland": "pole",
    "orchard": "zahrada", "garden": "zahrada", "allotments": "zahrada", "vineyard": "zahrada",
    "residential": "zahrada", "farmyard": "dvur", "industrial": "dvur", "commercial": "dvur",
    "cemetery": "louka",
}
LANDUSE_ORDER = ["pole", "louka", "zahrada", "dvur", "les"]  # co je výš, kreslí se navrch


R_CLIP = m(480)
CIRCLE = [(HX + R_CLIP * math.cos(2 * math.pi * i / 96), HY + R_CLIP * math.sin(2 * math.pi * i / 96))
          for i in range(96)]


def clip_poly_circle(pts):
    """Sutherland–Hodgman ořez polygonu na kruh (96-úhelník) kolem domu."""
    out = oc.ccw(list(pts))
    for i in range(len(CIRCLE)):
        a, b = CIRCLE[i], CIRCLE[(i + 1) % len(CIRCLE)]

        def inside(p):
            return (b[0] - a[0]) * (p[1] - a[1]) - (b[1] - a[1]) * (p[0] - a[0]) >= 0

        def inter(p, q):
            x1, y1, x2, y2 = p[0], p[1], q[0], q[1]
            x3, y3, x4, y4 = a[0], a[1], b[0], b[1]
            den = (x1 - x2) * (y3 - y4) - (y1 - y2) * (x3 - x4)
            t = ((x1 - x3) * (y3 - y4) - (y1 - y3) * (x3 - x4)) / den
            return (x1 + t * (x2 - x1), y1 + t * (y2 - y1))

        inp, out = out, []
        if not inp:
            break
        for j in range(len(inp)):
            p, q = inp[j - 1], inp[j]
            if inside(q):
                if not inside(p):
                    out.append(inter(p, q))
                out.append(q)
            elif inside(p):
                out.append(inter(p, q))
    return out


def clip_line_circle(pts):
    """Rozdělí polyline na části uvnitř kruhu r = R_CLIP (s dopočtem průsečíku)."""
    def ins(p):
        return math.hypot(p[0] - HX, p[1] - HY) <= R_CLIP

    def cut(p, q):
        lo, hi = (p, q) if ins(p) else (q, p)
        for _ in range(30):
            mid = ((lo[0] + hi[0]) / 2, (lo[1] + hi[1]) / 2)
            lo, hi = (mid, hi) if ins(mid) else (lo, mid)
        return lo

    parts, cur = [], []
    for i, p in enumerate(pts):
        if ins(p):
            if not cur and i > 0:
                cur.append(cut(pts[i - 1], p))
            cur.append(p)
        elif cur:
            cur.append(cut(cur[-1], p))
            parts.append(cur)
            cur = []
    if cur:
        parts.append(cur)
    return [c for c in parts if len(c) >= 2]


def ribbon(pts, width):
    """Pás kolem polyline se zkosenými spoji (miter, omezený)."""
    hw = width / 2
    n = len(pts)
    left, right = [], []
    for i in range(n):
        if i == 0:
            dx, dy = pts[1][0] - pts[0][0], pts[1][1] - pts[0][1]
            nx, ny = -dy, dx
            ln = math.hypot(nx, ny) or 1
            nx, ny, k = nx / ln, ny / ln, 1.0
        elif i == n - 1:
            dx, dy = pts[-1][0] - pts[-2][0], pts[-1][1] - pts[-2][1]
            nx, ny = -dy, dx
            ln = math.hypot(nx, ny) or 1
            nx, ny, k = nx / ln, ny / ln, 1.0
        else:
            d1 = (pts[i][0] - pts[i - 1][0], pts[i][1] - pts[i - 1][1])
            d2 = (pts[i + 1][0] - pts[i][0], pts[i + 1][1] - pts[i][1])
            l1 = math.hypot(*d1) or 1
            l2 = math.hypot(*d2) or 1
            n1 = (-d1[1] / l1, d1[0] / l1)
            n2 = (-d2[1] / l2, d2[0] / l2)
            nx, ny = n1[0] + n2[0], n1[1] + n2[1]
            ln = math.hypot(nx, ny)
            if ln < 1e-6:
                nx, ny, k = n1[0], n1[1], 1.0
            else:
                nx, ny = nx / ln, ny / ln
                k = min(1.0 / max(nx * n1[0] + ny * n1[1], 1e-3), 2.5)
        left.append((pts[i][0] + nx * hw * k, pts[i][1] + ny * hw * k))
        right.append((pts[i][0] - nx * hw * k, pts[i][1] - ny * hw * k))
    return left, right


def road_objects(coll, mats, z_by_kind):
    groups = {"asfalt": [], "strk": []}
    for ft in gj["features"]:
        p = ft["properties"]
        if p["kind"] != "highway" or ft["geometry"]["type"] != "LineString":
            continue
        hw = p.get("highway", "")
        if hw in {"proposed", "construction", "platform", "bus_stop", "corridor", "elevator"}:
            continue
        raw_pts = []
        for c in ft["geometry"]["coordinates"]:
            if not raw_pts or math.hypot(c[0] - raw_pts[-1][0], c[1] - raw_pts[-1][1]) > 1e-3:
                raw_pts.append(tuple(c))
        w = parse_width(p.get("width")) or ROAD_W.get(hw, 4.0)
        surf = p.get("surface", "")
        kind = "strk" if (hw in GRAVEL_HW and surf not in {"asphalt", "paved", "concrete"}) or surf in GRAVEL_SURF \
            else "asfalt"
        z = z_by_kind[kind]
        for k, pts in enumerate(clip_line_circle(raw_pts)):
            left, right = ribbon(pts, m(w))
            verts = [(x, y, z) for x, y in left] + [(x, y, z) for x, y in right]
            n = len(pts)
            faces = [(i, i + 1, n + i + 1, n + i) for i in range(n - 1)]
            groups[kind].append(oc.mesh_object(f"OKOLI_Cesta_{p['osm_id']}_{k}", verts, faces, coll, mats[kind]))
    out = {}
    for k, objs in groups.items():
        out[k] = len(objs)
        ob = oc.join_objects(objs, f"OKOLI_Komunikace_{k}")
        if ob:
            fix_normals_up(ob)
    return out


def fix_normals_up(ob):
    me = ob.data
    for p in me.polygons:
        if p.normal.z < 0:
            p.flip()
    me.update()


def parse_width(s):
    try:
        return float(str(s).replace(",", ".").split()[0].rstrip("m"))
    except Exception:
        return None


def triangulate_polygon_obj(name, rings, z, coll, mat):
    """Polygon (s dírami) → mesh přes bmesh + triangulaci (beauty)."""
    import bmesh
    from mathutils.geometry import tessellate_polygon
    from mathutils import Vector
    loops = []
    for r in rings:
        pts = clip_poly_circle(oc.open_ring(r))
        if len(pts) >= 3:
            loops.append([Vector((x, y, z)) for x, y in pts])
    if not loops:
        return None
    tris = tessellate_polygon(loops)
    verts = [v[:] for loop in loops for v in loop]
    faces = [t for t in tris]
    ob = oc.mesh_object(name, verts, faces, coll, mat)
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-4)
    bm.to_mesh(ob.data)
    bm.free()
    fix_normals_up(ob)
    return ob


def base_plate(coll, mat, radius):
    seg = 96
    verts = [(HX, HY, Z_BASE)] + [(HX + radius * math.cos(2 * math.pi * i / seg),
                                   HY + radius * math.sin(2 * math.pi * i / seg), Z_BASE) for i in range(seg)]
    faces = [(0, 1 + i, 1 + (i + 1) % seg) for i in range(seg)]
    return oc.mesh_object("OKOLI_Teren_zaklad", verts, faces, coll, mat)


def main():
    coll_t = oc.sub_coll("OKOLI_Teren")
    coll_r = oc.sub_coll("OKOLI_Komunikace")
    oc.clear_coll(coll_t)
    oc.clear_coll(coll_r)
    oc.hide_old_surroundings(ref)
    s = m(3.0)
    mats = {
        "louka": oc.make_material("OKOLI_Louka", ["grass", "meadow", "lawn"], (0.23, 0.38, 0.12), 0.95, s),
        "pole": oc.make_material("OKOLI_Pole", ["field", "farmland", "soil", "dirt", "ground"],
                                 (0.42, 0.34, 0.22), 0.95, s),
        "zahrada": oc.make_material("OKOLI_Zahrada", ["garden", "lawn", "grass"], (0.28, 0.42, 0.15), 0.95, s),
        "dvur": oc.make_material("OKOLI_Dvur", ["paving", "gravel", "concrete"], (0.5, 0.48, 0.44), 0.9, s),
        "les": oc.make_material("OKOLI_LesniPuda", ["forest", "moss", "leaves", "forest_floor"],
                                (0.16, 0.24, 0.1), 0.95, s),
        "asfalt": oc.make_material("OKOLI_Asfalt", ["asphalt", "road", "tarmac"], (0.17, 0.17, 0.17), 0.85, s),
        "strk": oc.make_material("OKOLI_Strk", ["gravel", "dirt", "ground"], (0.52, 0.47, 0.38), 0.95, s),
    }
    base_plate(coll_t, mats["louka"], m(480))

    lu_counts = {}
    for ft in gj["features"]:
        p = ft["properties"]
        if p["kind"] != "landuse" or ft["geometry"]["type"] != "Polygon":
            continue
        t = p.get("landuse") or p.get("natural") or p.get("leisure")
        mk = LANDUSE_MAT.get(t)
        if not mk:
            continue
        # různé typy mírně nad sebou, aby se nepralo z-fighting
        z = Z_LANDUSE + m(0.005) * LANDUSE_ORDER.index(mk)
        ob = triangulate_polygon_obj(f"OKOLI_Plocha_{t}_{p['osm_id']}", ft["geometry"]["coordinates"], z,
                                     coll_t, mats[mk])
        if ob:
            ob["landuse"] = t
            lu_counts[t] = lu_counts.get(t, 0) + 1
    roads = road_objects(coll_r, mats, {"asfalt": Z_ROAD + m(0.005), "strk": Z_ROAD})
    print(f"LANDUSE {lu_counts}  ROADS {roads}")

    os.makedirs(oc.BLEND_DIR, exist_ok=True)
    out = os.path.join(oc.BLEND_DIR, "Doubravy_3D_okoli_v2.blend")
    bpy.ops.wm.save_as_mainfile(filepath=out, copy=True)
    print("SAVED", out)
    os.makedirs(os.path.join(oc.ROOT, "renders"), exist_ok=True)
    oc.control_render(ref, os.path.join(oc.ROOT, "renders", "phase4_v2.png"))


main()
