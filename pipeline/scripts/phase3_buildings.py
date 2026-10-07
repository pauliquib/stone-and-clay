"""Fáze 3 – hmoty okolních domů z pipeline/data/okoli_local.geojson.

Spuštění:
    blender --background blend/Doubravy_3D.blend --python pipeline/scripts/phase3_buildings.py

- stěny = extrude půdorysu z OSM na výšku (building:levels × 3 m, height tag,
  jinak 6 m pro RD / 4 m pro garáže, kůlny apod.)
- střecha podle roof:shape: sedlová (výchozí), valbová (hipped), plochá (flat)
  nad minimálním orientovaným obdélníkem půdorysu, hřeben v delší ose
- budova, jejíž půdorys obsahuje bod domu (nebo leží v keep_out oblasti), se
  vynechá – dům je v scéně už vymodelovaný
- uloží blend/Doubravy_3D_okoli_v1.blend + render pipeline/renders/phase3_v1.png
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
KEEP = ref.get("keep_out_bbox")  # [xmin, ymin, xmax, ymax] v BU – dům + pozemek

SMALL = {"garage", "garages", "shed", "hut", "carport", "roof", "greenhouse", "cabin", "barn_small"}
FLATTISH = {"industrial", "warehouse", "commercial", "retail", "supermarket", "school", "hangar"}


def m(v):
    return v / mpu


def parse_float(s):
    try:
        return float(str(s).replace(",", ".").split()[0].rstrip("m"))
    except Exception:
        return None


def building_params(p):
    btype = p.get("building", "yes")
    levels = parse_float(p.get("building:levels"))
    height = parse_float(p.get("height"))
    roof_levels = parse_float(p.get("roof:levels")) or 0
    shape = (p.get("roof:shape") or "").lower()
    if not shape:
        shape = "flat" if btype in FLATTISH else "gabled"
    if shape in {"hipped", "half-hipped", "pyramidal"}:
        shape = "hipped"
    elif shape in {"flat", "skillion"}:
        shape = "flat" if shape == "flat" else "gabled"
    elif shape != "flat":
        shape = "gabled"
    if height:
        wall = height * (0.65 if shape != "flat" else 1.0)
    elif levels:
        wall = levels * 3.0
    elif btype in SMALL:
        wall = 2.6
    else:
        wall = 6.0 if btype in {"house", "detached", "yes", "residential", "semidetached_house", "farm"} else 5.0
    # RD bez tagu – přízemí + podkroví: 3.5 m stěna + střecha
    if not levels and not height and btype not in SMALL and btype not in FLATTISH:
        wall = 3.5 if shape != "flat" else 6.0
    return btype, wall, shape, roof_levels


def roof_geom(pts, wall_z, shape, overhang=0.4, pitch_deg=38.0):
    cx, cy, L, W, a = oc.min_area_rect(pts)
    L += 2 * m(overhang)
    W += 2 * m(overhang)
    rise = (W / 2) * math.tan(math.radians(pitch_deg))
    if W > m(20) or L * W > m(1) ** 2 * 600:
        rise = min(rise, m(4))  # velké haly – nízký sklon
    c, s = math.cos(a), math.sin(a)

    def P(u, v, z):
        return (cx + u * c - v * s, cy + u * s + v * c, z)

    hl, hw = L / 2, W / 2
    z0 = wall_z
    z1 = wall_z + rise
    if shape == "hipped":
        inset = min(hw, hl * 0.45)
        v = [P(-hl, -hw, z0), P(hl, -hw, z0), P(hl, hw, z0), P(-hl, hw, z0),
             P(-hl + inset, 0, z1), P(hl - inset, 0, z1)]
        f = [(0, 1, 5, 4), (1, 2, 5), (2, 3, 4, 5), (3, 0, 4), (3, 2, 1, 0)]
    else:
        v = [P(-hl, -hw, z0), P(hl, -hw, z0), P(hl, hw, z0), P(-hl, hw, z0),
             P(-hl, 0, z1), P(hl, 0, z1)]
        f = [(0, 1, 5, 4), (2, 3, 4, 5), (3, 0, 4), (1, 2, 5), (3, 2, 1, 0)]
    return v, f, rise


def wall_mesh(pts, z0, z1):
    n = len(pts)
    verts = [(x, y, z0) for x, y in pts] + [(x, y, z1) for x, y in pts]
    faces = [(i, (i + 1) % n, n + (i + 1) % n, n + i) for i in range(n)]
    faces.append(tuple(range(n - 1, -1, -1)))  # dno
    faces.append(tuple(range(n, 2 * n)))  # strop (pod střechou / plochá střecha)
    return verts, faces


def main():
    coll = oc.sub_coll("OKOLI_Budovy")
    oc.clear_coll(coll)
    hidden = oc.hide_old_surroundings(ref)
    mat_wall = oc.make_material("OKOLI_Fasada", ["plaster", "facade", "stucco", "wall", "concrete"],
                                (0.82, 0.79, 0.72), 0.9, scale=m(2.0))
    mat_roof = oc.make_material("OKOLI_Strecha", ["roof", "tile", "tiles"], (0.45, 0.2, 0.15), 0.7,
                                scale=m(2.0))
    mat_flat = oc.make_material("OKOLI_StrechaPlocha", ["asphalt_roof", "bitumen", "gravel_roof"],
                                (0.3, 0.3, 0.3), 0.9, scale=m(2.0))
    made, skipped = [], []
    stats = {"gabled": 0, "hipped": 0, "flat": 0}
    for ft in gj["features"]:
        p = ft["properties"]
        if p["kind"] != "building" or ft["geometry"]["type"] != "Polygon":
            continue
        pts = oc.ccw(oc.open_ring(ft["geometry"]["coordinates"][0]))
        if len(pts) < 3 or abs(oc.ring_area(pts)) < m(1) ** 2 * 4:
            continue
        if oc.point_in_poly(HX, HY, pts):
            skipped.append(p["osm_id"])
            continue
        if KEEP:
            cxm = sum(x for x, _ in pts) / len(pts)
            cym = sum(y for _, y in pts) / len(pts)
            if KEEP[0] <= cxm <= KEEP[2] and KEEP[1] <= cym <= KEEP[3]:
                skipped.append(p["osm_id"])
                continue
        btype, wall, shape, _ = building_params(p)
        wz = GZ + m(wall)
        v, f = wall_mesh(pts, GZ - m(0.3), wz)
        name = f"OKOLI_Budova_{p['osm_id']}"
        ob = oc.mesh_object(name, v, f, coll, [mat_wall, mat_roof if shape != "flat" else mat_flat])
        for poly in ob.data.polygons[-1:]:
            poly.material_index = 1
        ob["osm_id"] = p["osm_id"]
        ob["building"] = btype
        if shape != "flat":
            rv, rf, _ = roof_geom(pts, wz, shape)
            rob = oc.mesh_object(name + "_strecha", rv, rf, coll, mat_roof)
            made.append(rob)
        made.append(ob)
        stats[shape] += 1
    # spoj do dvou objektů kvůli výkonu (jednotlivé budovy zůstanou jako atributy nejsou potřeba)
    walls = [o for o in made if not o.name.endswith("_strecha")]
    roofs = [o for o in made if o.name.endswith("_strecha")]
    nb = len(walls)
    oc.join_objects(walls, "OKOLI_Budovy_steny")
    oc.join_objects(roofs, "OKOLI_Budovy_strechy")
    print(f"BUILDINGS {nb} stats={stats} skipped(house)={skipped} hidden_old={hidden}")

    os.makedirs(oc.BLEND_DIR, exist_ok=True)
    out = os.path.join(oc.BLEND_DIR, "Doubravy_3D_okoli_v1.blend")
    bpy.ops.wm.save_as_mainfile(filepath=out, copy=True)
    print("SAVED", out)
    os.makedirs(os.path.join(oc.ROOT, "renders"), exist_ok=True)
    oc.control_render(ref, os.path.join(oc.ROOT, "renders", "phase3_v1.png"))


main()
