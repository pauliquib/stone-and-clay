"""Místa pro questy (hospoda, obchod, pálenice, vinný sklep, chata, obecní úřad, domov) → data/pois.json.

Budovy se berou ze skutečných dat (OSM/RÚIAN, pipeline/data/buildings_3d*.json):
  Potraviny (OSM way 279053665, shop=convenience)      – skutečný obchod
  Obecní úřad Dukelčice (761155002, amenity=townhall)   – skutečný
  Myslivecká chata (788743489)                        – skutečná
  Hospoda U Hřiště   – občanská budova u fotbalového hřiště (224455861)   [herní fikce]
  Pálenice           – sklad u obchodu (876175146)                        [herní fikce]
  Vinný sklep        – sklady na severu katastru (279053798)               [herní fikce]
  usedlost          – domov hráče

Pro každé místo spočítá: střed budovy, „dveře“ (bod na obvodu budovy nejblíž silnici,
posunutý 1,8 m ven) a parkovací místo (u krajnice nejbližší silnice).
Souřadnice Godotu: x, z = −y scény.

  python3 tools/pois.py
"""
import json
import math
import os

HERE = os.path.dirname(os.path.abspath(__file__))
GAME = os.path.dirname(HERE)
PIPE = os.path.join(GAME, "pipeline")
PDATA = os.path.join(PIPE, "data")
GEO = os.path.join(GAME, "geodata")
PSCRIPTS = os.path.join(PIPE, "scripts")

PLACES = [
    ("hospoda", "Hospoda U Hřiště", 224455861),
    ("obchod", "Potraviny", 279053665),
    ("palenice", "Pálenice U Kotla", 876175146),
    ("sklep", "Vinný sklep Jílka", 279053798),
    ("chata", "Myslivecká chata", 788743489),   # v lese – parkuje se u lesní cesty
    ("urad", "Obecní úřad Dukelčice", 761155002),
]
DRIVABLE = {"secondary", "tertiary", "unclassified", "residential", "service", "living_street"}


def seg_closest(p, a, b):
    ax, ay = b[0] - a[0], b[1] - a[1]
    L2 = ax * ax + ay * ay or 1e-9
    t = max(0.0, min(1.0, ((p[0] - a[0]) * ax + (p[1] - a[1]) * ay) / L2))
    q = (a[0] + ax * t, a[1] + ay * t)
    return q, math.hypot(p[0] - q[0], p[1] - q[1]), (ax, ay)


def main():
    blds = json.load(open(os.path.join(PDATA, "buildings_3d.json"))) + \
        json.load(open(os.path.join(PDATA, "buildings_3d_full.json")))
    by_id = {b.get("osm_id"): b for b in blds}
    meta = json.load(open(os.path.join(GAME, "data/map.json")))
    roads_all = meta["roads"]
    # map.json roads jsou už v souřadnicích Godotu (x, z)
    out = {}
    for key, name, oid in PLACES:
        b = by_id[oid]
        poly = [(q[0], -q[1]) for q in b["polygon"]]
        cx = sum(q[0] for q in poly) / len(poly)
        cz = sum(q[1] for q in poly) / len(poly)
        kinds = DRIVABLE | {"track"} if key == "chata" else DRIVABLE
        best = None
        for r in (r for r in roads_all if r["kind"] in kinds):
            pts = r["pts"]
            for i in range(len(pts) - 1):
                q, d, dirv = seg_closest((cx, cz), pts[i], pts[i + 1])
                if best is None or d < best[1]:
                    best = (q, d, dirv, r["kind"])
        road_pt, _, dirv, kind = best
        # dveře: bod obvodu nejblíž silnici
        door, dd = None, 1e9
        for i in range(len(poly)):
            q, d, _ = seg_closest(road_pt, poly[i], poly[(i + 1) % len(poly)])
            if d < dd:
                door, dd = q, d
        vx, vz = road_pt[0] - door[0], road_pt[1] - door[1]
        L = math.hypot(vx, vz) or 1.0
        door_out = (door[0] + vx / L * 1.8, door[1] + vz / L * 1.8)
        # parkování: na straně silnice u budovy, podél silnice
        ln = math.hypot(*dirv) or 1.0
        tx, tz = dirv[0] / ln, dirv[1] / ln
        nx, nz = -tz, tx
        if (door[0] - road_pt[0]) * nx + (door[1] - road_pt[1]) * nz < 0:
            nx, nz = -nx, -nz
        half = {"secondary": 3.2, "tertiary": 2.8}.get(kind, 2.3)
        park = (road_pt[0] + nx * (half + 1.3) + tx * 6.0, road_pt[1] + nz * (half + 1.3) + tz * 6.0)
        out[key] = {
            "name": name, "osm_id": oid,
            "x": round(cx, 2), "z": round(cz, 2),
            "door_x": round(door_out[0], 2), "door_z": round(door_out[1], 2),
            "face_yaw": round(math.atan2(vx, vz), 3),
            "park_x": round(park[0], 2), "park_z": round(park[1], 2),
            "park_yaw": round(math.atan2(tx, tz), 3),
            "road_kind": kind, "road_dist": round(math.hypot(cx - road_pt[0], cz - road_pt[1]), 1),
        }
        print(f"{key:9s} {name:24s} center=({cx:8.1f},{cz:8.1f}) door=({door_out[0]:8.1f},{door_out[1]:8.1f})"
              f" road {kind} {out[key]['road_dist']} m")
    h = meta["domov_hrace"]
    sp = meta["spawn"]
    out["domov"] = {"name": "Domov – usedlost", "x": h["x"], "z": h["z"],
                    "door_x": sp["x"] - 4.0, "door_z": sp["z"], "face_yaw": math.pi / 2,
                    "park_x": sp["x"] + 6.0, "park_z": sp["z"] + 4.0, "park_yaw": 0.0}
    json.dump(out, open(os.path.join(GAME, "data/pois.json"), "w"), ensure_ascii=False, indent=1)
    print("WROTE data/pois.json")


if __name__ == "__main__":
    main()
