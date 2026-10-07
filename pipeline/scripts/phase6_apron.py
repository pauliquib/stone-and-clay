"""Fáze 6a – (jen čtení) okrajové body zpevněné plochy `okolo` a obrys domu.

Spuštění:
    blender --background blend/Doubravy_3D.blend --python pipeline/scripts/phase6_apron.py

Výstup pipeline/data/apron.json: okrajové vrcholy plochy `okolo` (x, y, z) – slouží
k navázání výšky terénu z DMR 5G na výškovou úroveň modelu pozemku.
"""
import json
import os

import bmesh
import bpy

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)          # pipeline/ – data/, assets/, renders/, logs/
GAME = os.path.dirname(ROOT)          # kořen repozitáře hry – geodata/, blend/
GEO = os.path.join(GAME, "geodata")

ob = bpy.data.objects["okolo"]
bm = bmesh.new()
bm.from_mesh(ob.data)
bm.transform(ob.matrix_world)
boundary = {v for e in bm.edges if e.is_boundary for v in e.verts}
pts = [[round(v.co.x, 3), round(v.co.y, 3), round(v.co.z, 3)] for v in boundary]
allz = [v.co.z for v in bm.verts]
bm.free()
out = {"object": "okolo", "boundary_xyz": pts, "z_min": min(allz), "z_max": max(allz)}
with open(os.path.join(ROOT, "data", "apron.json"), "w", encoding="utf-8") as f:
    json.dump(out, f)
print("APRON boundary verts", len(pts), "z", round(min(allz), 3), round(max(allz), 3))
