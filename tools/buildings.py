"""Data budov pro fasády (okna, dveře, komíny) → data/buildings.json.

Zdroj: podklady, ze kterých vznikají `walls.bin` a `roofs.bin` (proto sedí na stěny ve hře):
  data/buildings_3d.json, data/buildings_3d_full.json   (kořen repozitáře; OSM půdorys + výšky DMP 1G)
  tools/out/domov_hrace.json                  (dům hráče – usedlost, `home: true`)
  data/pois.json                           (osm_id míst → `poi: klíč`)
  data/map.json                            (silnice → strana, kde jsou dveře)
Nic se nestahuje, OSM se znovu nečte (půdorysy a výšky už jsou v podkladech). Jen standardní knihovna.

Souřadnice: scéna (x, y, z nahoru) → Godot (x, z = −y, výška y = z scény), stejně jako v export_map.py.

Formát data/buildings.json – pole objektů:
  id          int      osm_id budovy (dům hráče má osm_id z domov_hrace.json)
  type        str      house | garage | shed | barn | church | public | hall
  area        float    plocha půdorysu (m²)
  poly        [[x,z]…] půdorys v souřadnicích hry (bez opakování prvního bodu)
  ground_y    float    střední výška terénu u budovy (m n. m. ve hře)
  eave_y      float    výška okapu (horní hrana stěn)
  ridge_y     float    výška hřebene
  shape       str      gable_long | gable_short | hipped | flat
  ridge_c     [x,z]    střed hřebene;  ridge_dir [dx,dz] směr hřebene;  ridge_half  polovina délky hřebene (m)
  poi         str|null klíč místa z pois.json (hospoda, obchod, …)
  home        bool     dům hráče
  door        [x,z]|null bod obvodu nejblíž nejbližší silnici (hra ho použije pro dveře / vrata)
  road_dist   float|null vzdálenost od té silnice (m)

Typ se odvozuje z OSM `building=*` a plochy (viz konstanty níže).

  python3 tools/buildings.py
"""
import json
import math
import os
from collections import Counter

HERE = os.path.dirname(os.path.abspath(__file__))
GAME = os.path.dirname(HERE)
ROOT = os.path.dirname(GAME)
DATA = os.path.join(GAME, "data")

DRIVABLE = {"secondary", "tertiary", "unclassified", "residential", "service", "living_street"}

# Budovy vyřazené ručně (artefakty podkladů – geometrii z walls/roofs.bin maže
# tools/clean_road_clashes.py, REMOVE_BUILDINGS):
#   dmp_176 – kůlna z DMP uprostřed silnice obchod ↔ úřad (na ortofotu nic není, v OSM není)
EXCLUDE = {"dmp_176"}

# OSM building=* → typ (u ostatních / „yes“ rozhoduje plocha)
TAG_TYPES = {
    "garage": "garage", "garages": "garage", "carport": "garage",
    "shed": "shed", "hut": "shed", "cabin": "shed", "roof": "shed", "service": "shed", "greenhouse": "shed",
    "barn": "barn", "farm_auxiliary": "barn", "stable": "barn", "cowshed": "barn", "sty": "barn", "silo": "barn",
    "church": "church", "chapel": "church", "cathedral": "church",
    "civic": "public", "public": "public", "school": "public", "kindergarten": "public", "hospital": "public",
    "government": "public", "townhall": "public", "commercial": "public", "retail": "public",
    "office": "public", "fire_station": "public",
    "industrial": "hall", "warehouse": "hall", "hangar": "hall", "manufacture": "hall",
}
SHED_MAX_AREA = 25.0     # m² – menší budova je vždy kůlna   # DOPLNIT: výchozí odhad
HALL_MIN_AREA = 450.0    # m² – větší „obyčejná“ budova je hala


def classify(tag: str, area: float) -> str:
    if area < SHED_MAX_AREA:
        return "shed"
    t = TAG_TYPES.get(tag)
    if t:
        return t
    return "hall" if area > HALL_MIN_AREA else "house"


def poly_area(pts):
    s = 0.0
    for i in range(len(pts)):
        x1, z1 = pts[i]
        x2, z2 = pts[(i + 1) % len(pts)]
        s += x1 * z2 - x2 * z1
    return abs(s) / 2.0


def seg_closest(p, a, b):
    ax, ay = b[0] - a[0], b[1] - a[1]
    l2 = ax * ax + ay * ay or 1e-9
    t = max(0.0, min(1.0, ((p[0] - a[0]) * ax + (p[1] - a[1]) * ay) / l2))
    q = (a[0] + ax * t, a[1] + ay * t)
    return q, math.hypot(p[0] - q[0], p[1] - q[1])


def ridge_of(b, poly):
    """Střed, směr a poloviční délka hřebene v souřadnicích hry (podle obdélníku a tvaru střechy)."""
    cx, cy, length, width, ang = b["rect"]
    shape = b.get("shape", "flat")
    if shape == "gable_short":
        length, width, ang = width, length, ang + math.pi / 2
    dx, dz = math.cos(ang), -math.sin(ang)          # scéna y → Godot −z
    if shape in ("gable_long", "gable_short"):
        half = length / 2.0
    elif shape == "hipped":
        half = max(length - width, 0.0) / 2.0
    else:
        half = 0.0
    return [round(cx, 2), round(-cy, 2)], [round(dx, 4), round(dz, 4)], round(half, 2)


def main():
    src = json.load(open(os.path.join(ROOT, "data", "buildings_3d.json"))) + \
        json.load(open(os.path.join(ROOT, "data", "buildings_3d_full.json")))
    home_path = os.path.join(HERE, "out", "domov_hrace.json")
    home_id = None
    if os.path.exists(home_path):
        h = json.load(open(home_path))
        home_id = h["osm_id"]
        src = [b for b in src if b.get("osm_id") != home_id] + [h]
    pois = json.load(open(os.path.join(DATA, "pois.json")))
    poi_by_osm = {p["osm_id"]: k for k, p in pois.items() if "osm_id" in p}
    meta = json.load(open(os.path.join(DATA, "map.json")))
    roads = [r for r in meta["roads"] if r["kind"] in DRIVABLE]   # už v souřadnicích hry

    out = []
    seen = set()
    for b in src:
        bid = b.get("osm_id")
        if bid in seen or bid in EXCLUDE or "eave_z" not in b:
            continue
        seen.add(bid)
        poly = [(p[0], -p[1]) for p in b["polygon"]]
        if len(poly) > 1 and poly[0] == poly[-1]:
            poly = poly[:-1]
        if len(poly) < 3:
            continue
        area = poly_area(poly)
        cx = sum(p[0] for p in poly) / len(poly)
        cz = sum(p[1] for p in poly) / len(poly)
        # dveře: bod obvodu nejblíž nejbližší silnici
        best = None
        for r in roads:
            pts = r["pts"]
            for i in range(len(pts) - 1):
                q, d = seg_closest((cx, cz), pts[i], pts[i + 1])
                if best is None or d < best[1]:
                    best = (q, d)
        door, road_dist = None, None
        if best is not None and best[1] < 80.0:
            dd = 1e9
            for i in range(len(poly)):
                q, d = seg_closest(best[0], poly[i], poly[(i + 1) % len(poly)])
                if d < dd:
                    door, dd = q, d
            road_dist = round(dd, 1)
        rc, rd, rh = ridge_of(b, poly)
        out.append({
            "id": bid,
            "type": classify(str(b.get("building", "yes")), area),
            "area": round(area, 1),
            "poly": [[round(x, 2), round(z, 2)] for x, z in poly],
            "ground_y": b["ground_z"], "eave_y": b["eave_z"], "ridge_y": b["ridge_z"],
            "shape": b.get("shape", "flat"),
            "ridge_c": rc, "ridge_dir": rd, "ridge_half": rh,
            "poi": poi_by_osm.get(bid),
            "home": bid == home_id,
            "door": [round(door[0], 2), round(door[1], 2)] if door else None,
            "road_dist": road_dist,
        })
    path = os.path.join(DATA, "buildings.json")
    json.dump(out, open(path, "w"), ensure_ascii=False, separators=(",", ":"))
    cnt = Counter(b["type"] for b in out)
    print(f"WROTE data/buildings.json: {len(out)} budov")
    for t, n in cnt.most_common():
        print(f"  {t:8s} {n}")
    print("  místa:", ", ".join(f"{b['poi']}={b['id']}" for b in out if b["poi"]) or "žádná")
    print("  domov:", next((b["id"] for b in out if b["home"]), "nenalezen"))


if __name__ == "__main__":
    main()
