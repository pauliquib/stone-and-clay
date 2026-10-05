"""Fáze 1b – odvození referenčního bodu, měřítka a severu (čistý Python).

Vstupy: pipeline/data/scene_inspect.json (z phase1_inspect_scene.py), pipeline/data/osm_raw.json,
        pipeline/data/geocode.json
Výstup: pipeline/data/scene_reference.json

Postup:
1. Najde dům (a pozemek, staré okolí) ve scéně podle názvů kolekcí/objektů,
   jinak heuristikou podle rozměrů.
2. Najde v OSM půdorys domu = budova obsahující adresní bod (nebo nejbližší).
3. Orientace: porovná směr delší osy minimálního obdélníku půdorysu v OSM
   (reálný sever) a ve scéně. Z kandidátů (mod 180°, u čtvercového půdorysu
   mod 90°) vybere nejmenší rotaci – předpoklad, že model je kreslený zhruba
   „severem nahoru“. Výsledek je v JSON včetně alternativ a míry jistoty.
4. Měřítko: jednotky scény + kontrola poměru rozměrů OSM vs. model.
Parametry lze ručně přepsat v pipeline/data/scene_reference_override.json.
"""
import json
import math
import os
import sys
import unicodedata

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from phase2_osm_to_local import aeqd  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)          # pipeline/ – data/, assets/, renders/, logs/
GAME = os.path.dirname(ROOT)          # kořen repozitáře hry – geodata/, blend/
GEO = os.path.join(GAME, "geodata")


def norm(s):
    return unicodedata.normalize("NFKD", s).encode("ascii", "ignore").decode().lower()


HOUSE_KW = ("dum", "house", "doubravy", "budova", "stavba", "building", "rd_", "rodinny", "objekt", "home",
            "stena", "walls", "strecha", "roof", "okno", "okna", "window", "dvere", "door", "fasada", "podlaha",
            "komin", "chimney")
PLOT_KW = ("pozemek", "plot", "parcel", "parcela", "zahrada", "garden", "oploceni", "plot_", "fence", "plot ",
           "terasa", "chodnik", "dlazba", "prijezd", "zpevnen", "bazen", "pool")
OLD_STRONG = ("okoli", "surround", "neighbo", "soused", "context", "kontext", "environment", "prostredi")
OLD_KW = ("silnic", "road", "ulice", "street", "strom", "tree", "les_", "lesy", "forest", "teren", "terrain",
          "ground", "krajina", "landscape", "background", "pozadi")


def hull(pts):
    pts = sorted(set(map(tuple, pts)))
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


def mar(pts):
    h = hull(pts)
    best = None
    for i in range(len(h)):
        x1, y1 = h[i]
        x2, y2 = h[(i + 1) % len(h)]
        a = math.atan2(y2 - y1, x2 - x1)
        c, s = math.cos(a), math.sin(a)
        us = [x * c + y * s for x, y in h]
        vs = [-x * s + y * c for x, y in h]
        area = (max(us) - min(us)) * (max(vs) - min(vs))
        if best is None or area < best[0]:
            best = (area, a, min(us), max(us), min(vs), max(vs))
    _, a, u0, u1, v0, v1 = best
    c, s = math.cos(a), math.sin(a)
    uc, vc = (u0 + u1) / 2, (v0 + v1) / 2
    L, W = u1 - u0, v1 - v0
    if W > L:
        L, W, a = W, L, a + math.pi / 2
    return (uc * c - vc * s, uc * s + vc * c), L, W, math.degrees(a) % 180


def pip(x, y, pts):
    ins = False
    for i in range(len(pts)):
        x1, y1 = pts[i]
        x2, y2 = pts[(i + 1) % len(pts)]
        if (y1 > y) != (y2 > y) and x < (x2 - x1) * (y - y1) / (y2 - y1 + 1e-12) + x1:
            ins = not ins
    return ins


def walk_colls(t, path=()):
    yield t, path
    for c in t["children"]:
        yield from walk_colls(c, path + (t["name"],))


def main():
    insp = json.load(open(os.path.join(ROOT, "data", "scene_inspect.json"), encoding="utf-8"))
    raw = json.load(open(os.path.join(ROOT, "data", "osm_raw.json"), encoding="utf-8"))
    geo = json.load(open(os.path.join(ROOT, "data", "geocode.json"), encoding="utf-8"))
    lat0 = geo.get("lat") or geo.get("latitude")
    lon0 = geo.get("lon") or geo.get("longitude")
    if lat0 is None:  # jiný tvar souboru
        s = json.dumps(geo)
        lat0, lon0 = 49.1435288, 17.6717138
        print("WARN geocode.json unexpected format, using log values", s[:200])

    objs = {o["name"]: o for o in insp["objects"]}
    meshes = [o for o in insp["objects"] if o["type"] == "MESH" and o.get("bbox")]

    # ---- klasifikace podle kolekcí a názvů
    def classify_name(n):
        n = norm(n)
        if any(k in n for k in OLD_STRONG):
            return "old"
        if any(k in n for k in PLOT_KW):
            return "plot"
        if any(k in n for k in HOUSE_KW):
            return "house"
        if any(k in n for k in OLD_KW):
            return "old"
        return None

    obj_class = {}
    for coll, path in walk_colls(insp["collections"]):
        cls = None
        for nm in path[1:] + (coll["name"],):  # nejbližší pojmenovaná kolekce vyhrává
            cls = classify_name(nm) or cls
        for on in coll["objects"]:
            oc = classify_name(on)
            obj_class[on] = cls if cls else oc
            # dům/pozemek v kolekci "okolí" by bylo divné – objektové jméno má přednost u house/plot
            if cls == "old" and oc in {"house", "plot"}:
                obj_class[on] = oc
    old_colls = [c["name"] for c, p in walk_colls(insp["collections"])
                 if p and classify_name(c["name"]) == "old"]

    house = [o for o in meshes if obj_class.get(o["name"]) == "house"]
    plot = [o for o in meshes if obj_class.get(o["name"]) == "plot"]
    method = "names"
    if not house:
        # heuristika: objekt s rozměry RD nejblíž počátku
        method = "size-heuristic"
        cands = [o for o in meshes if 3 <= o["bbox"]["size"][2] <= 20 and 5 <= max(o["bbox"]["size"][:2]) <= 40]
        cands.sort(key=lambda o: math.hypot(*[(o["bbox"]["min"][i] + o["bbox"]["max"][i]) / 2 for i in (0, 1)]))
        house = cands[:1]
    if not house:
        sys.exit("ERROR: house object not found – fill data/scene_reference_override.json")

    # velké plochy (terén) mezi "house" objekty nechceme – odfiltruj rozměrové extrémy
    med = sorted(max(o["bbox"]["size"][:2]) for o in house)[len(house) // 2]
    house = [o for o in house if max(o["bbox"]["size"][:2]) <= max(60, med * 3)]

    hpts = [p for o in house for p in o.get("hull_xy", [])]
    (hcx, hcy), hL, hW, ha = mar(hpts)
    ground_z = min(o["bbox"]["min"][2] for o in house)
    # podlaha/terén často jde pod nulu – vezmi nejčastější spodní hranu
    zmins = sorted(round(o["bbox"]["min"][2], 2) for o in house)
    ground_z = max(set(zmins), key=zmins.count)

    # ---- OSM půdorys domu
    nodes = {e["id"]: (e["lat"], e["lon"]) for e in raw["elements"] if e["type"] == "node" and "lat" in e}
    best = None
    for e in raw["elements"]:
        if e["type"] != "way" or "building" not in e.get("tags", {}):
            continue
        lls = [(g["lat"], g["lon"]) for g in e["geometry"]] if "geometry" in e else \
            [nodes[n] for n in e.get("nodes", []) if n in nodes]
        if len(lls) < 4:
            continue
        xy = [aeqd(la, lo, lat0, lon0) for la, lo in lls]
        inside = pip(0, 0, xy)
        cx = sum(p[0] for p in xy) / len(xy)
        cy = sum(p[1] for p in xy) / len(xy)
        d = 0 if inside else math.hypot(cx, cy)
        if best is None or d < best[0]:
            best = (d, e, xy, lls)
    d, hw, oxy, olls = best
    (ocx, ocy), oL, oW, oa = mar(oxy)
    # centroid OSM domu zpět na lat/lon (lokální lineární aproximace)
    m_lat = 111132.954 - 559.822 * math.cos(2 * math.radians(lat0))
    m_lon = 111412.84 * math.cos(math.radians(lat0))
    house_lat = lat0 + ocy / m_lat
    house_lon = lon0 + ocx / m_lon

    # ---- měřítko
    us = insp["units"]
    mpu_units = us["scale_length"] if us["system"] != "NONE" else 1.0
    ratio = (hL * mpu_units) / oL if oL else 1.0
    mpu = mpu_units
    scale_note = f"units scale_length={us['scale_length']} system={us['system']}; model/OSM length ratio={ratio:.3f}"
    for f in (0.001, 0.01, 0.0254, 0.3048):
        if abs(ratio * f - 1) < 0.35 and abs(ratio - 1) > 0.5:
            mpu = mpu_units * f
            scale_note += f" -> corrected meters_per_unit={mpu}"

    # ---- orientace
    aspect_o = oL / max(oW, 1e-6)
    aspect_s = hL / max(hW, 1e-6)
    period = 180 if (aspect_o > 1.15 and aspect_s > 1.15) else 90
    base = (ha - oa) % period
    cands = sorted({round(((base + k * period + 180) % 360) - 180, 2) for k in range(360 // period)},
                   key=lambda t: abs(t))
    theta = cands[0]
    conf = "medium" if period == 180 else "low"
    if abs(theta) > 30:
        conf = "low"

    # ---- keep-out oblast (dům + pozemek)
    kp = [o for o in house + plot if max(o["bbox"]["size"][:2]) < 150]
    xs = [v for o in kp for v in (o["bbox"]["min"][0], o["bbox"]["max"][0])]
    ys = [v for o in kp for v in (o["bbox"]["min"][1], o["bbox"]["max"][1])]
    margin = 2.0 / mpu
    keep = [round(min(xs) - margin, 2), round(min(ys) - margin, 2), round(max(xs) + margin, 2),
            round(max(ys) + margin, 2)]

    old_objs = [o["name"] for o in insp["objects"] if obj_class.get(o["name"]) == "old"
                and o["type"] in {"MESH", "CURVE", "EMPTY"}]

    ref = {
        "house_latlon": [round(house_lat, 8), round(house_lon, 8)],
        "address_point_latlon": [lat0, lon0],
        "house_scene_xy": [round(hcx, 3), round(hcy, 3)],
        "ground_z": ground_z,
        "meters_per_unit": mpu,
        "north_angle_deg": theta,
        "north_angle_note": "úhel, o který je sever ve scéně pootočen od osy +Y proti směru hodinových ručiček",
        "north_angle_alternatives": cands,
        "north_confidence": conf,
        "house_objects": sorted(o["name"] for o in house),
        "plot_objects": sorted(o["name"] for o in plot),
        "keep_out_bbox": keep,
        "old_surroundings": {"objects": old_objs, "collections": old_colls},
        "exclude_osm_ids": [f"way/{hw['id']}"],
        "diagnostics": {
            "house_detect_method": method,
            "scene_footprint": {"center": [round(hcx, 2), round(hcy, 2)], "L": round(hL, 2), "W": round(hW, 2),
                                "axis_deg": round(ha, 2)},
            "osm_footprint": {"way": hw["id"], "tags": hw.get("tags", {}), "L_m": round(oL, 2), "W_m": round(oW, 2),
                              "axis_deg": round(oa, 2), "dist_from_address_m": round(d, 1)},
            "scale": scale_note,
            "period_deg": period,
        },
    }
    ov = os.path.join(ROOT, "data", "scene_reference_override.json")
    if os.path.exists(ov):
        ref.update(json.load(open(ov, encoding="utf-8")))
        ref["diagnostics"]["override"] = True
    with open(os.path.join(ROOT, "data", "scene_reference.json"), "w", encoding="utf-8") as f:
        json.dump(ref, f, ensure_ascii=False, indent=2)
    print(json.dumps(ref, ensure_ascii=False, indent=1)[:4000])


if __name__ == "__main__":
    main()
