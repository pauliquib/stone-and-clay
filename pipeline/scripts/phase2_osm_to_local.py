"""Fáze 2 – převod OSM dat (lat/lon) do lokálních metrických souřadnic scény.

Čistý Python (bez bpy). Vstupy:
    pipeline/data/osm_raw.json          – Overpass JSON (way s `geometry` nebo `nodes` + node elementy)
    pipeline/data/scene_reference.json  – referenční bod domu ve scéně, měřítko, úhel severu
Výstup:
    pipeline/data/okoli_local.geojson   – FeatureCollection, souřadnice v jednotkách scény (X, Y)

Projekce: lokální azimutální ekvidistantní se středem v bodě domu (na 450 m je
rozdíl oproti přesné geodézii zanedbatelný, < 1 mm). Pak rotace o úhel severu
a posun do lokálních souřadnic domu ve scéně.

scene_reference.json:
    house_latlon:       [lat, lon] reálné polohy domu (adresní bod)
    house_scene_xy:     [x, y] bod domu ve scéně (Blender units)
    meters_per_unit:    kolik metrů odpovídá 1 BU (typicky 1.0)
    north_angle_deg:    úhel směru severu ve scéně měřený od osy +Y proti směru
                        hodinových ručiček (0 = sever je +Y)
"""
import json
import math
import os

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)          # pipeline/ – data/, assets/, renders/, logs/
GAME = os.path.dirname(ROOT)          # kořen repozitáře hry – geodata/, blend/
GEO = os.path.join(GAME, "geodata")
R_EARTH = 6371008.8


def aeqd(lat, lon, lat0, lon0):
    """Azimutální ekvidistantní projekce → (east, north) v metrech."""
    p, p0 = math.radians(lat), math.radians(lat0)
    dl = math.radians(lon - lon0)
    cos_c = math.sin(p0) * math.sin(p) + math.cos(p0) * math.cos(p) * math.cos(dl)
    cos_c = max(-1.0, min(1.0, cos_c))
    c = math.acos(cos_c)
    k = 1.0 if c < 1e-12 else c / math.sin(c)
    x = R_EARTH * k * math.cos(p) * math.sin(dl)
    y = R_EARTH * k * (math.cos(p0) * math.sin(p) - math.sin(p0) * math.cos(p) * math.cos(dl))
    return x, y


def make_transform(ref):
    lat0, lon0 = ref["house_latlon"]
    hx, hy = ref["house_scene_xy"]
    mpu = ref.get("meters_per_unit", 1.0)
    a = math.radians(ref.get("north_angle_deg", 0.0))
    ca, sa = math.cos(a), math.sin(a)

    def tf(lat, lon):
        e, n = aeqd(lat, lon, lat0, lon0)
        # sever (0, n) se má zobrazit na vektor (-sin a, cos a) → rotace o +a
        x = e * ca - n * sa
        y = e * sa + n * ca
        return round(hx + x / mpu, 3), round(hy + y / mpu, 3)

    return tf


def way_latlons(el, nodes):
    if "geometry" in el:
        return [(g["lat"], g["lon"]) for g in el["geometry"] if g]
    return [nodes[n] for n in el.get("nodes", []) if n in nodes]


def classify(tags):
    if "building" in tags or "building:part" in tags:
        return "building"
    if "highway" in tags:
        return "highway"
    if "landuse" in tags or "natural" in tags and tags["natural"] in {"wood", "scrub", "grassland"} \
            or "leisure" in tags:
        return "landuse"
    if tags.get("natural") == "tree":
        return "tree"
    return None


def main():
    raw = json.load(open(os.path.join(ROOT, "data", "osm_raw.json"), encoding="utf-8"))
    ref = json.load(open(os.path.join(ROOT, "data", "scene_reference.json"), encoding="utf-8"))
    tf = make_transform(ref)
    els = raw["elements"]
    nodes = {e["id"]: (e["lat"], e["lon"]) for e in els if e["type"] == "node" and "lat" in e}
    ways = {e["id"]: e for e in els if e["type"] == "way"}

    feats = []
    skipped_house = []
    house_ids = set(ref.get("exclude_osm_ids", []))

    def add(kind, osm_type, osm_id, tags, geom_type, coords):
        feats.append({
            "type": "Feature",
            "properties": {"kind": kind, "osm_type": osm_type, "osm_id": osm_id, **tags},
            "geometry": {"type": geom_type, "coordinates": coords},
        })

    for e in els:
        tags = e.get("tags", {})
        kind = classify(tags)
        if not kind:
            continue
        if f"{e['type']}/{e['id']}" in house_ids:
            skipped_house.append(e["id"])
            continue
        if e["type"] == "node":
            if kind == "tree":
                add(kind, "node", e["id"], tags, "Point", list(tf(e["lat"], e["lon"])))
            continue
        if e["type"] == "way":
            pts = [list(tf(*ll)) for ll in way_latlons(e, nodes)]
            if len(pts) < 2:
                continue
            closed = len(pts) >= 4 and pts[0] == pts[-1]
            if kind in {"building", "landuse"}:
                if not closed:
                    continue
                add(kind, "way", e["id"], tags, "Polygon", [pts])
            else:
                add(kind, "way", e["id"], tags, "LineString", pts)
        elif e["type"] == "relation" and kind in {"building", "landuse"}:
            outers, inners = [], []
            for m in e.get("members", []):
                if m.get("type") != "way":
                    continue
                if "geometry" in m:
                    lls = [(g["lat"], g["lon"]) for g in m["geometry"] if g]
                elif m.get("ref") in ways:
                    lls = way_latlons(ways[m["ref"]], nodes)
                else:
                    continue
                ring = [list(tf(*ll)) for ll in lls]
                if len(ring) >= 4 and ring[0] == ring[-1]:
                    (inners if m.get("role") == "inner" else outers).append(ring)
            for o in outers:
                add(kind, "relation", e["id"], tags, "Polygon", [o] + inners)

    out = {"type": "FeatureCollection",
           "properties": {"crs": "scene-local", "reference": ref,
                          "projection": "AEQD centered on house_latlon, rotated by north_angle_deg"},
           "features": feats}
    path = os.path.join(ROOT, "data", "okoli_local.geojson")
    with open(path, "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False)

    # shrnutí
    counts = {}
    xs, ys = [], []
    for ft in feats:
        k = ft["properties"]["kind"]
        counts[k] = counts.get(k, 0) + 1
        g = ft["geometry"]
        cs = [g["coordinates"]] if g["type"] == "Point" else \
            g["coordinates"] if g["type"] == "LineString" else g["coordinates"][0]
        for x, y in cs:
            xs.append(x)
            ys.append(y)
    print("counts:", counts)
    if xs:
        print(f"X range: {min(xs):.1f} .. {max(xs):.1f}   Y range: {min(ys):.1f} .. {max(ys):.1f}")
    print("excluded (house itself):", skipped_house)
    hw = {}
    for ft in feats:
        if ft["properties"]["kind"] == "highway":
            t = ft["properties"]["highway"]
            hw[t] = hw.get(t, 0) + 1
    print("highway types:", hw)
    lu = {}
    for ft in feats:
        if ft["properties"]["kind"] == "landuse":
            t = ft["properties"].get("landuse") or ft["properties"].get("natural") or ft["properties"].get("leisure")
            lu[t] = lu.get(t, 0) + 1
    print("landuse types:", lu)
    print("WROTE", path)


if __name__ == "__main__":
    main()
