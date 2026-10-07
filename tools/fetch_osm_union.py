"""B2.2 – OSM extrakt pro UNION oblast (detail mapa + 5 okolních obcí).

Vzor pipeline/scripts/phase9_fetch_osm_full.py: regionální extrakt Geofabrik
(geodata/pbf/zlinsky-latest.osm.pbf, ~53 MB, celý Zlínský kraj) prohledaný
lokálně přes pyosmium – offline, bez downloadu, bez limitu na velikost dotazu.

Rozdíly oproti fázi 9:
  * bbox = UNION mřížka (z tools/fetch_geodata_union.union_grid) + MARGIN,
    transformovaná do lat/lon přes afinní scéna→5514 + pyproj 5514→4326.
  * RELEVANT_KEYS rozšířené o waterway / place / water – potřebují je
    tools/water.py (toky, názvy pro hygienický filtr), tools/expand_map.py
    (silnice i mimo katastr Dukelčic), surface/landuse/surroundings.
  * place uzly (village/town/hamlet…) se ukládají – jejich jména slouží jako
    zakázaná toponyma v hygienickém filtru názvů (viz obce.fname_road).

Výstupy:
  pipeline/data/osm_raw_union.json       – schéma jako osm_raw_full.json
  pipeline/data/okoli_union_local.geojson – features ve scénových souřadnicích
                                         (phase11 logika + waterway/water)

Spuštění: python3 tools/fetch_osm_union.py
"""
import json
import math
import os
import sys

import osmium
from pyproj import CRS, Transformer

HERE = os.path.dirname(os.path.abspath(__file__))
GAME = os.path.dirname(HERE)
PIPE = os.path.join(GAME, "pipeline")
PDATA = os.path.join(PIPE, "data")
GEO = os.path.join(GAME, "geodata")
DATA = os.path.join(GAME, "data")
PBF = os.path.join(GEO, "pbf", "zlinsky-latest.osm.pbf")
PSCRIPTS = os.path.join(PIPE, "scripts")
sys.path.insert(0, PSCRIPTS)
sys.path.insert(0, HERE)
from phase2_osm_to_local import make_transform, way_latlons  # noqa: E402
from fetch_geodata_union import union_grid, scene_to_5514_affine, load_old_meta  # noqa: E402

RELEVANT_KEYS = ("building", "building:part", "highway", "landuse", "leisure",
                 "natural", "waterway", "water", "place")
MARGIN_M = 200.0   # přesah za mřížku (navazující silnice/toky nejsou uřezané)


def union_bbox_latlon(meta_old):
    """Union mřížka + MARGIN → lat/lon bbox (minlon, minlat, maxlon, maxlat)."""
    ref = json.load(open(os.path.join(PDATA, "scene_reference.json"), encoding="utf-8"))
    g = union_grid(meta_old)
    x0, x1 = g["grid_x0"] - MARGIN_M, g["grid_x1"] + MARGIN_M
    y0, y1 = g["grid_y0"] - MARGIN_M, g["grid_y1"] + MARGIN_M
    cx, cy, resid = scene_to_5514_affine(ref, x0, x1, y0, y1)
    tr = Transformer.from_crs(CRS.from_epsg(5514), CRS.from_epsg(4326), always_xy=True)
    corners = [(x0, y0), (x1, y0), (x1, y1), (x0, y1)]
    lons, lats = [], []
    for sx, sy in corners:
        X = cx[0] * sx + cx[1] * sy + cx[2]
        Y = cy[0] * sx + cy[1] * sy + cy[2]
        lo, la = tr.transform(X, Y)
        lons.append(lo)
        lats.append(la)
    # drobná rezerva (affinní residuál ~mm, ale lat/lon bbox musí pokrýt i zaokrouhlení)
    pad = 0.001
    return (min(lons) - pad, min(lats) - pad, max(lons) + pad, max(lats) + pad)


class Extractor(osmium.SimpleHandler):
    def __init__(self, bbox):
        super().__init__()
        self.bbox = bbox  # (minlon, minlat, maxlon, maxlat)
        self.elements = []
        self.n_seen = {"node": 0, "way": 0, "relation": 0}
        # toponyma VŠECH place uzlů v celém kraji (i mimo bbox) – hygienický
        # filtr názvů: „silnice Zlín - Luhačovice" nesmí protéci jen proto,
        # že města leží za hranou union bbox
        self.place_names = set()

    def _in_bbox(self, lon, lat):
        return self.bbox[0] <= lon <= self.bbox[2] and self.bbox[1] <= lat <= self.bbox[3]

    def _relevant(self, tags):
        return any(k in tags for k in RELEVANT_KEYS)

    def node(self, n):
        self.n_seen["node"] += 1
        tags = dict(n.tags)
        if "place" in tags and tags.get("name"):
            self.place_names.add(tags["name"])
        keep = tags.get("natural") == "tree" or "place" in tags
        if keep and n.location.valid() and self._in_bbox(n.location.lon, n.location.lat):
            self.elements.append({"type": "node", "id": n.id, "lat": n.location.lat,
                                  "lon": n.location.lon, "tags": tags})

    def way(self, w):
        self.n_seen["way"] += 1
        tags = dict(w.tags)
        if not self._relevant(tags):
            return
        try:
            pts = [(nd.location.lat, nd.location.lon) for nd in w.nodes if nd.location.valid()]
        except osmium.InvalidLocationError:
            return
        if len(pts) < 2:
            return
        if not any(self._in_bbox(lon, lat) for lat, lon in pts):
            return
        self.elements.append({
            "type": "way", "id": w.id, "tags": tags,
            "geometry": [{"lat": lat, "lon": lon} for lat, lon in pts],
        })

    def relation(self, r):
        self.n_seen["relation"] += 1
        tags = dict(r.tags)
        if tags.get("type") != "multipolygon" or not self._relevant(tags):
            return
        members = [{"type": "way", "ref": m.ref, "role": m.role}
                   for m in r.members if m.type == "w"]
        if not members:
            return
        self.elements.append({"type": "relation", "id": r.id, "tags": tags,
                              "members": members,
                              "_member_refs": [m["ref"] for m in members]})


class WayGeomCollector(osmium.SimpleHandler):
    """Druhý průchod: geometrie way členů multipolygon relací (i mimo bbox)."""

    def __init__(self, want_ids):
        super().__init__()
        self.want = want_ids
        self.geoms = {}

    def way(self, w):
        if w.id not in self.want:
            return
        try:
            pts = [(nd.location.lat, nd.location.lon) for nd in w.nodes if nd.location.valid()]
        except osmium.InvalidLocationError:
            return
        self.geoms[w.id] = [{"lat": lat, "lon": lon} for lat, lon in pts]


# ------------------------------------------------------------------ geojson

def classify_union(tags):
    """Rozšířená klasifikace oproti phase2.classify: + waterway a vodní plochy."""
    if "building" in tags or "building:part" in tags:
        return "building"
    if "highway" in tags:
        return "highway"
    if "waterway" in tags:
        return "waterway"
    if tags.get("natural") == "water" or tags.get("landuse") in ("reservoir", "basin") \
            or "water" in tags:
        return "water"
    if "landuse" in tags or "natural" in tags and tags["natural"] in {"wood", "scrub", "grassland"} \
            or "leisure" in tags:
        return "landuse"
    if tags.get("natural") == "tree":
        return "tree"
    return None


def write_geojson(raw):
    """osm_raw_union elements → okoli_union_local.geojson (scénové souřadnice)."""
    ref = json.load(open(os.path.join(PDATA, "scene_reference.json"), encoding="utf-8"))
    tf = make_transform(ref)
    els = raw["elements"]
    nodes = {e["id"]: (e["lat"], e["lon"]) for e in els if e["type"] == "node" and "lat" in e}
    ways = {e["id"]: e for e in els if e["type"] == "way"}

    feats = []

    def add(kind, osm_type, osm_id, tags, geom_type, coords):
        feats.append({"type": "Feature",
                      "properties": {"kind": kind, "osm_type": osm_type, "osm_id": osm_id, **tags},
                      "geometry": {"type": geom_type, "coordinates": coords}})

    POLY_KINDS = {"building", "landuse", "water"}
    for e in els:
        tags = e.get("tags", {})
        kind = classify_union(tags)
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
            if kind in POLY_KINDS:
                if not closed:
                    continue
                add(kind, "way", e["id"], tags, "Polygon", [pts])
            else:
                add(kind, "way", e["id"], tags, "LineString", pts)
        elif e["type"] == "relation" and kind in POLY_KINDS:
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
           "properties": {"crs": "scene-local",
                          "note": "UNION oblast (detail + 5 obcí); scene x,y – Godot z = -y"},
           "features": feats}
    path = os.path.join(PDATA, "okoli_union_local.geojson")
    with open(path, "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False)
    counts = {}
    for ft in feats:
        k = ft["properties"]["kind"]
        counts[k] = counts.get(k, 0) + 1
    print("geojson counts:", counts)
    print("WROTE", path, os.path.getsize(path), "bytes")


def main():
    if not os.path.exists(PBF):
        sys.exit(f"chybí {PBF}")
    meta_old = load_old_meta()
    bbox = union_bbox_latlon(meta_old)
    print("union bbox lat/lon (+margin):", [round(v, 5) for v in bbox])

    idx = "sparse_mem_array"
    h = Extractor(bbox)
    h.apply_file(PBF, locations=True, idx=idx)
    print("prošlo:", h.n_seen, "-> relevantních prvků:", len(h.elements))

    # relace: dotáhnout geometrie member ways (druhý průchod)
    rel_els = [e for e in h.elements if e["type"] == "relation"]
    want_ids = set()
    for e in rel_els:
        want_ids.update(e["_member_refs"])
    if want_ids:
        wc = WayGeomCollector(want_ids)
        wc.apply_file(PBF, locations=True, idx=idx)
        for e in rel_els:
            for m in e["members"]:
                g = wc.geoms.get(m["ref"])
                if g:
                    m["geometry"] = g
            del e["_member_refs"]

    before = len(h.elements)

    def rel_in_bbox(e):
        for m in e.get("members", []):
            for g in m.get("geometry", []):
                if h._in_bbox(g["lon"], g["lat"]):
                    return True
        return False

    h.elements = [e for e in h.elements if e["type"] != "relation" or rel_in_bbox(e)]
    print(f"relace mimo bbox vyřazeny: {before - len(h.elements)}")

    counts = {}
    n_place = 0
    for e in h.elements:
        t = e["tags"]
        if "place" in t:
            n_place += 1
        k = "building" if ("building" in t or "building:part" in t) else \
            "highway" if "highway" in t else \
            "waterway" if "waterway" in t else \
            "tree" if t.get("natural") == "tree" else "landuse/other"
        counts[k] = counts.get(k, 0) + 1
    print("counts:", counts, f"(place uzly v bbox: {n_place}, "
          f"toponym v kraji: {len(h.place_names)})")

    out = {"generator": "tools/fetch_osm_union.py (pyosmium, zlinsky-latest.osm.pbf)",
           "bbox_latlon_margin": bbox, "elements": h.elements,
           "place_names": sorted(h.place_names)}   # všechna place jména v kraji (filtr)
    out_path = os.path.join(PDATA, "osm_raw_union.json")
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False)
    print("WROTE", out_path, os.path.getsize(out_path), "bytes")

    write_geojson(out)


if __name__ == "__main__":
    main()
