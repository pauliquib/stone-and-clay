"""Fáze 1 – read-only inspekce blend/Doubravy_3D.blend (nic neukládá).

Spuštění:
    blender --background blend/Doubravy_3D.blend --python pipeline/scripts/phase1_inspect_scene.py

Vypíše kolekce, objekty (typ, poloha, rotace, měřítko, bounding box ve světových
souřadnicích), jednotky scény a případné custom properties / georeferenční údaje.
Výsledek uloží do pipeline/data/scene_inspect.json pro další analýzu.
"""
import json
import os

import bpy
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)          # pipeline/ – data/, assets/, renders/, logs/
GAME = os.path.dirname(ROOT)          # kořen repozitáře hry – geodata/, blend/
GEO = os.path.join(GAME, "geodata")
OUT = os.path.join(ROOT, "data", "scene_inspect.json")


def world_bbox(obj):
    if not hasattr(obj, "bound_box") or obj.type not in {"MESH", "CURVE", "FONT", "SURFACE", "META"}:
        return None
    pts = [obj.matrix_world @ Vector(c) for c in obj.bound_box]
    mn = [min(p[i] for p in pts) for i in range(3)]
    mx = [max(p[i] for p in pts) for i in range(3)]
    return {"min": [round(v, 3) for v in mn], "max": [round(v, 3) for v in mx],
            "size": [round(mx[i] - mn[i], 3) for i in range(3)]}


def convex_hull(pts):
    pts = sorted(set(pts))
    if len(pts) < 3:
        return [list(p) for p in pts]

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
    return [list(p) for p in lo[:-1] + up[:-1]]


def props(idblock):
    out = {}
    for k in idblock.keys():
        if k.startswith("_"):
            continue
        try:
            v = idblock[k]
            out[k] = v if isinstance(v, (int, float, str)) else str(v)
        except Exception:
            pass
    return out


def coll_tree(coll, depth=0):
    return {
        "name": coll.name,
        "objects": [o.name for o in coll.objects],
        "children": [coll_tree(c, depth + 1) for c in coll.children],
    }


scene = bpy.context.scene
us = scene.unit_settings
data = {
    "file": bpy.data.filepath,
    "scene": scene.name,
    "units": {"system": us.system, "scale_length": us.scale_length, "length_unit": us.length_unit},
    "scene_props": props(scene),
    "collections": coll_tree(scene.collection),
    "objects": [],
    "materials": [m.name for m in bpy.data.materials],
    "worlds": [w.name for w in bpy.data.worlds],
    "images": [(i.name, i.filepath) for i in bpy.data.images],
    "cameras": [o.name for o in bpy.data.objects if o.type == "CAMERA"],
    "lights": [o.name for o in bpy.data.objects if o.type == "LIGHT"],
    "render": {"engine": scene.render.engine, "res": [scene.render.resolution_x, scene.render.resolution_y]},
}

for o in bpy.data.objects:
    entry = {
        "name": o.name,
        "type": o.type,
        "parent": o.parent.name if o.parent else None,
        "collections": [c.name for c in o.users_collection],
        "location": [round(v, 3) for v in o.location],
        "rotation_deg": [round(v * 57.29578, 2) for v in o.rotation_euler],
        "scale": [round(v, 4) for v in o.scale],
        "bbox": world_bbox(o),
        "props": props(o),
        "hide_render": o.hide_render,
    }
    if o.type == "MESH":
        entry["verts"] = len(o.data.vertices)
        entry["polys"] = len(o.data.polygons)
        entry["materials"] = [s.material.name for s in o.material_slots if s.material]
        if 0 < len(o.data.vertices) <= 300000:
            mw = o.matrix_world
            xy = [(round(p.x, 3), round(p.y, 3)) for p in (mw @ v.co for v in o.data.vertices)]
            entry["hull_xy"] = convex_hull(xy)
    data["objects"].append(entry)

with open(OUT, "w", encoding="utf-8") as f:
    json.dump(data, f, ensure_ascii=False, indent=1)

print("=== UNITS", data["units"])
print("=== SCENE PROPS", data["scene_props"])


def pc(t, d=0):
    print("  " * d + f"[{t['name']}] {len(t['objects'])} obj")
    for c in t["children"]:
        pc(c, d + 1)


pc(data["collections"])
print("=== OBJECTS", len(data["objects"]))
for e in data["objects"]:
    bb = e["bbox"]
    print(f"{e['type']:7} {e['name'][:40]:40} col={','.join(e['collections'])[:30]:30} "
          f"loc={e['location']} rot={e['rotation_deg']} "
          f"size={bb['size'] if bb else '-'} min={bb['min'] if bb else '-'} {e['props'] or ''}")
print("WROTE", OUT)
