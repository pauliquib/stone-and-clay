"""Fáze 9 – OSM data pro CELÝ katastr obce Doubravy (rozšíření okolí).

Overpass API je v době psaní nedostupné (406 na všech mirror serverech),
navíc dotaz "around" na plochu ~5x4 km by stejně byl na hraně timeoutu.
Použit robustnější zdroj: regionální extrakt Geofabrik (Zlínský kraj,
~53 MB) prohledaný lokálně přes pyosmium – žádný limit na velikost dotazu.

Vstup:
    geodata/pbf/zlinsky-latest.osm.pbf   – Geofabrik extrakt (mimo git)
    pipeline/data/scene_reference.json       – referenční bod/orientace domu
    pipeline/data/doubravy_admin_boundary.json – hranice katastru (scéna i lat/lon)
Výstup:
    pipeline/data/osm_raw_full.json  – ve stejném schématu jako Overpass JSON
                              (elements: node/way/relation s "geometry"),
                              aby ho šel číst stávající pipeline/scripts/phase2_osm_to_local.py
                              beze změny (jen se přepne vstupní soubor).
"""
import json
import math
import os
import sys

import osmium

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)          # pipeline/ – data/, assets/, renders/, logs/
GAME = os.path.dirname(ROOT)          # kořen repozitáře hry – geodata/, blend/
GEO = os.path.join(GAME, "geodata")
PBF = os.path.join(GEO, "pbf", "zlinsky-latest.osm.pbf")

RELEVANT_KEYS = ("building", "building:part", "highway", "landuse", "leisure", "natural")

MARGIN_M = 200.0  # přesah za hranici katastru, ať navazující silnice/domy nejsou uřezané


def bbox_latlon():
    """Bbox katastru (z Nominatim admin polygonu) + marže, v lat/lon."""
    poly = json.load(open(os.path.join(ROOT, "data", "doubravy_admin_boundary.json"), encoding="utf-8"))
    lons = [p[0] for p in poly["lonlat_poly"]]
    lats = [p[1] for p in poly["lonlat_poly"]]
    # marže v stupních (hrubě, 1 deg lat ~ 111.3 km, 1 deg lon ~ 111.3*cos(lat) km)
    lat0 = sum(lats) / len(lats)
    dlat = MARGIN_M / 111_320.0
    dlon = MARGIN_M / (111_320.0 * math.cos(math.radians(lat0)))
    return (min(lons) - dlon, min(lats) - dlat, max(lons) + dlon, max(lats) + dlat)


class Extractor(osmium.SimpleHandler):
    def __init__(self, bbox):
        super().__init__()
        self.bbox = bbox  # (minlon, minlat, maxlon, maxlat)
        self.elements = []
        self.n_seen = {"node": 0, "way": 0, "relation": 0}

    def _in_bbox(self, lon, lat):
        return self.bbox[0] <= lon <= self.bbox[2] and self.bbox[1] <= lat <= self.bbox[3]

    def _relevant(self, tags):
        return any(k in tags for k in RELEVANT_KEYS)

    def node(self, n):
        self.n_seen["node"] += 1
        tags = dict(n.tags)
        if tags.get("natural") == "tree" and n.location.valid() and self._in_bbox(n.location.lon, n.location.lat):
            self.elements.append({"type": "node", "id": n.id, "lat": n.location.lat, "lon": n.location.lon,
                                   "tags": tags})

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
        members = []
        any_in = False
        for m in r.members:
            if m.type != "w":
                continue
            members.append({"type": "way", "ref": m.ref, "role": m.role})
        if not members:
            return
        # geometrie členů se dopočítá přes way handler (druhý průchod) - viz main()
        self.elements.append({"type": "relation", "id": r.id, "tags": tags, "members": members,
                               "_member_refs": [m.ref for m in r.members if m.type == "w"]})


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


def main():
    if not os.path.exists(PBF):
        sys.exit(f"chybí {PBF}")
    bbox = bbox_latlon()
    print("bbox lat/lon (+margin):", bbox)

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

    # relation() nemohl v prvním průchodu ověřit bbox (geometrie členů se
    # dopočítává až v druhém průchodu) - vyřadit teď relace, které bbox
    # vůbec nezasahují (typicky velké lesní komplexy/katastry mimo Doubravy).
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
    for e in h.elements:
        t = e["tags"]
        k = "building" if ("building" in t or "building:part" in t) else \
            "highway" if "highway" in t else \
            "tree" if t.get("natural") == "tree" else "landuse"
        counts[k] = counts.get(k, 0) + 1
    print("counts:", counts)

    out = {"generator": "phase9_fetch_osm_full (pyosmium, zlinsky-latest.osm.pbf)",
           "bbox_latlon_margin": bbox, "elements": h.elements}
    out_path = os.path.join(ROOT, "data", "osm_raw_full.json")
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False)
    print("WROTE", out_path, os.path.getsize(out_path), "bytes")


if __name__ == "__main__":
    main()
