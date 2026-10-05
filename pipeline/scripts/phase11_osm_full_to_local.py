"""Fáze 11 – převod OSM dat CELÉHO katastru (osm_raw_full.json) do lokálních
souřadnic scény. Stejná logika jako pipeline/scripts/phase2_osm_to_local.py (fáze 2),
jen jiný vstup/výstup a bez omezení na 450 m okruh.

Výstup: pipeline/data/okoli_full_local.geojson
"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from phase2_osm_to_local import make_transform, way_latlons, classify  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)          # pipeline/ – data/, assets/, renders/, logs/
GAME = os.path.dirname(ROOT)          # kořen repozitáře hry – geodata/, blend/
GEO = os.path.join(GAME, "geodata")


def main():
    raw = json.load(open(os.path.join(ROOT, "data", "osm_raw_full.json"), encoding="utf-8"))
    ref = json.load(open(os.path.join(ROOT, "data", "scene_reference.json"), encoding="utf-8"))
    tf = make_transform(ref)
    els = raw["elements"]
    nodes = {e["id"]: (e["lat"], e["lon"]) for e in els if e["type"] == "node" and "lat" in e}
    ways = {e["id"]: e for e in els if e["type"] == "way"}

    feats = []

    def add(kind, osm_type, osm_id, tags, geom_type, coords):
        feats.append({"type": "Feature", "properties": {"kind": kind, "osm_type": osm_type, "osm_id": osm_id,
                                                          **tags}, "geometry": {"type": geom_type, "coordinates": coords}})

    for e in els:
        tags = e.get("tags", {})
        kind = classify(tags)
        if not kind:
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

    out = {"type": "FeatureCollection", "properties": {"crs": "scene-local"}, "features": feats}
    path = os.path.join(ROOT, "data", "okoli_full_local.geojson")
    with open(path, "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False)

    counts = {}
    for ft in feats:
        k = ft["properties"]["kind"]
        counts[k] = counts.get(k, 0) + 1
    print("counts:", counts)
    print("WROTE", path, os.path.getsize(path), "bytes")


if __name__ == "__main__":
    main()
