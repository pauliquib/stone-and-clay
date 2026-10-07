"""Fáze 1c – určení orientace (sever) a posunu porovnáním půdorysu domu.

Půdorys domu v OSM (RÚIAN, way 279053823 – budova obsahující adresní bod) se
porovná s půdorysem modelu (obrysy obvodových zdí z pipeline/data/scene_inspect.json).
Hledá se rotace θ a posun (dx, dy), které maximalizují IoU (překryv) obou
rastrovaných půdorysů. Hrubě: θ0 + k·90° (k = 0..3), pak jemně ±4° / ±1.5 m.

Výstup: pipeline/data/scene_reference.json (+ diagnostika do stdout)
"""
import json
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from phase1_reference import mar, pip  # noqa: E402
from phase2_osm_to_local import aeqd  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)          # pipeline/ – data/, assets/, renders/, logs/
GAME = os.path.dirname(ROOT)          # kořen repozitáře hry – geodata/, blend/
GEO = os.path.join(GAME, "geodata")
OSM_HOUSE_WAY = 279053823
# obvodové zdi: hlavní blok (sklep) + přístavba (základy/sklep přístavby)
FOOTPRINT_OBJS = ["Stěny sklep", "zaklady", "sklep"]
CELL = 0.2


def raster(polys, x0, y0, nx, ny):
    cells = set()
    for poly in polys:
        xs = [p[0] for p in poly]
        ys = [p[1] for p in poly]
        i0, i1 = max(0, int((min(xs) - x0) / CELL)), min(nx, int((max(xs) - x0) / CELL) + 1)
        j0, j1 = max(0, int((min(ys) - y0) / CELL)), min(ny, int((max(ys) - y0) / CELL) + 1)
        for i in range(i0, i1):
            for j in range(j0, j1):
                if pip(x0 + (i + .5) * CELL, y0 + (j + .5) * CELL, poly):
                    cells.add((i, j))
    return cells


def main():
    insp = json.load(open(os.path.join(ROOT, "data", "scene_inspect.json"), encoding="utf-8"))
    raw = json.load(open(os.path.join(ROOT, "data", "osm_raw.json"), encoding="utf-8"))
    geo = json.load(open(os.path.join(ROOT, "data", "geocode.json"), encoding="utf-8"))
    lat0, lon0 = geo["lat"], geo["lon"]
    objs = {o["name"]: o for o in insp["objects"]}

    scene_polys = [[tuple(p) for p in objs[n]["hull_xy"]] for n in FOOTPRINT_OBJS if n in objs]
    spts = [p for poly in scene_polys for p in poly]
    way = next(e for e in raw["elements"] if e["id"] == OSM_HOUSE_WAY)
    oxy = [aeqd(g["lat"], g["lon"], lat0, lon0) for g in way["geometry"]][:-1]
    ocx = sum(p[0] for p in oxy) / len(oxy)
    ocy = sum(p[1] for p in oxy) / len(oxy)
    osm_c = [(x - ocx, y - ocy) for x, y in oxy]

    # rastr scény
    x0, y0 = min(p[0] for p in spts) - 6, min(p[1] for p in spts) - 6
    nx = int((max(p[0] for p in spts) + 6 - x0) / CELL)
    ny = int((max(p[1] for p in spts) + 6 - y0) / CELL)
    S = raster(scene_polys, x0, y0, nx, ny)
    scx = x0 + (sum(i for i, _ in S) / len(S) + .5) * CELL
    scy = y0 + (sum(j for _, j in S) / len(S) + .5) * CELL

    def iou(theta, dx, dy):
        c, s = math.cos(math.radians(theta)), math.sin(math.radians(theta))
        poly = [(scx + dx + x * c - y * s, scy + dy + x * s + y * c) for x, y in osm_c]
        O = raster([poly], x0, y0, nx, ny)
        return len(S & O) / len(S | O)

    _, _, _, oa = mar(oxy)
    _, _, _, sa = mar(spts)
    base = sa - oa
    coarse = []
    for k in range(4):
        th = ((base + 90 * k + 180) % 360) - 180
        coarse.append((iou(th, 0, 0), th))
    coarse.sort(reverse=True)
    print("coarse IoU per 90° candidate:", [(round(i, 3), round(t, 2)) for i, t in coarse])

    best = (coarse[0][0], coarse[0][1], 0.0, 0.0)
    for _ in range(2):  # dvě kola souřadnicového hledání
        i0, th0, dx0, dy0 = best
        for dth in [x * 0.5 for x in range(-8, 9)]:
            v = iou(th0 + dth, dx0, dy0)
            if v > best[0]:
                best = (v, th0 + dth, dx0, dy0)
        i0, th0, dx0, dy0 = best
        for ddx in [x * 0.25 for x in range(-6, 7)]:
            for ddy in [x * 0.25 for x in range(-6, 7)]:
                v = iou(th0, dx0 + ddx, dy0 + ddy)
                if v > best[0]:
                    best = (v, th0, dx0 + ddx, dy0 + ddy)
    score, theta, dx, dy = best
    second = coarse[1][0]
    print(f"best IoU={score:.3f} theta={theta:.2f}° offset=({dx:.2f},{dy:.2f}); 2nd candidate IoU={second:.3f}")

    # adresní/OSM centroid (ocx, ocy v m od adresního bodu) ↔ scéna (scx+dx, scy+dy)
    m_lat = 111132.954 - 559.822 * math.cos(2 * math.radians(lat0))
    m_lon = 111412.84 * math.cos(math.radians(lat0))
    house_lat = lat0 + ocy / m_lat
    house_lon = lon0 + ocx / m_lon

    # pozemek = zpevněné plochy kolem domu, rampa, zídka, přístavba, předsíň
    keep_objs = [o for o in insp["objects"] if o.get("bbox") and max(o["bbox"]["size"][:2]) < 60]
    xs = [v for o in keep_objs for v in (o["bbox"]["min"][0], o["bbox"]["max"][0])]
    ys = [v for o in keep_objs for v in (o["bbox"]["min"][1], o["bbox"]["max"][1])]
    ref_path = os.path.join(ROOT, "data", "scene_reference.json")
    prev = json.load(open(ref_path, encoding="utf-8")) if os.path.exists(ref_path) else {}
    conf = "high" if score > 0.8 and score - second > 0.1 else "medium" if score > 0.65 else "low"
    ref = {
        "house_latlon": [round(house_lat, 8), round(house_lon, 8)],
        "address_point_latlon": [lat0, lon0],
        "house_scene_xy": [round(scx + dx, 3), round(scy + dy, 3)],
        "ground_z": prev.get("ground_z", 1.7),
        "meters_per_unit": 1.0,
        "north_angle_deg": round(theta, 2),
        "north_angle_note": "sever ve scéně = osa +Y pootočená o tento úhel proti směru hodinových ručiček "
                            "(záporné = po směru). Směr severu ve scéně: (-sin θ, cos θ).",
        "north_confidence": conf,
        "method": f"IoU shoda půdorysu OSM way/{OSM_HOUSE_WAY} (RÚIAN) s obvodovými zdmi {FOOTPRINT_OBJS}",
        "house_objects": "celá scéna (všechny kolekce) – dům, sklep, přístavba, zpevněné plochy 'okolo', rampa",
        "keep_out_bbox": [round(min(xs) - 1, 2), round(min(ys) - 1, 2), round(max(xs) + 1, 2), round(max(ys) + 1, 2)],
        "old_surroundings": {"objects": [], "collections": []},
        "exclude_osm_ids": [f"way/{OSM_HOUSE_WAY}"],
        "diagnostics": {
            "iou_best": round(score, 3), "iou_second_candidate": round(second, 3),
            "coarse": [(round(i, 3), round(t, 2)) for i, t in coarse],
            "osm_centroid_from_address_m": [round(ocx, 2), round(ocy, 2)],
            "scene_footprint_centroid": [round(scx, 3), round(scy, 3)],
            "osm_mar_axis_deg": round(oa, 2), "scene_mar_axis_deg": round(sa, 2),
            "units": insp["units"],
        },
    }
    for k in ("ground_z", "ground_z_note", "north_angle_decision"):
        if k in prev:
            ref[k] = prev[k]
    with open(ref_path, "w", encoding="utf-8") as f:
        json.dump(ref, f, ensure_ascii=False, indent=2)
    print(json.dumps(ref, ensure_ascii=False, indent=1))


if __name__ == "__main__":
    main()
