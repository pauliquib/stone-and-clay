"""Datová vrstva okolních vesnic → data/obce.json.

Pět fiktivně pojmenovaných obcí v okolí Dukelčic (reálné názvy se ve hře nesmí
objevit – viz PRAVNI_DOPORUCENI.md a FICTIONAL_NAMES v tools/export_map.py /
tools/water.py). Obce jsou zatím jen vizuální: hranice katastru, půdorysy budov,
silnice, vodní a lesní plochy v herních souřadnicích (metry, Godot x,z).

Zdroj dat (jen lokálně, nic se nestahuje):
  geodata/pbf/zlinsky-latest.osm.pbf  – OSM (© přispěvatelé OpenStreetMap, ODbL)

Postup:
  1. průchod PBF: place uzly (kotvy obcí) + admin relace (boundary=administrative,
     admin_level=8) cílových obcí; do logu se vypíší všechny place uzly do ~8 km
     od domova pro kontrolu přiřazení,
  2. průchod PBF s locations=True: hranice katastru (osmium area assembler sešije
     outer ways relace do prstenců – kdyby sešití selhalo / relace chyběla,
     zkusí se ruční sešití member ways, jinak fallback = konvexní obálka
     budov+silnic nafouknutá o HULL_PAD m, případně kruh RADIUS_HINT kolem kotvy),
     budovy a silnice uvnitř katastru (silnice s ~ROAD_OVERHANG m přesahem, ať
     ulice navazují), plochy natural=water a landuse=forest,
  3. vše se transformuje lat/lon → scéna (make_transform z
     scripts/phase2_osm_to_local.py) → hra (x = scene x, z = −scene y).

Souřadnicový transform (ověřený): ref Doubravy 122 → lat0=49.14354261,
lon0=17.67175015 → scene (11.071, 11.816); e = R·Δlon·cos(lat0), n = R·Δlat
(aeqd, R=6371008.8); scene_x = 11.071 + e·cos(78.37°) − n·sin(78.37°),
scene_y = 11.816 + e·sin(78.37°) + n·cos(78.37°); game x = scene_x, z = −scene_y.

Formát data/obce.json:
  version   int    1
  generated str    nástroj + zdroj (bez reálných názvů)
  units     str    "m, herní souřadnice Godot (x, z)"
  obce      pole objektů:
    id       str    slug z fiktivního jména (brehatice, bohulecice, …)
    name     str    FIKTIVNÍ jméno obce (reálné se do souboru neukládá)
    place    str    village | hamlet | town (typ place uzlu v OSM)
    center   [x,z]  kotva = pozice place uzlu (m)
    radius   m      ekvivalentní poloměr katastru (sqrt(plocha/π)); u fallbacku
                    odhad z place typu / rozlohy zástavby
    boundary_src str  relation | stitch | hull | circle – odkud hranice pochází
    boundary [[x,z]…]  polygon katastru (hlavní outer ring, bez opakování bodu)
    buildings [{poly:[[x,z]…], kind}]  kind: house|barn|garage|shed|public|
                    church|chapel|tower|commercial|industrial
    roads    [{kind, name, pts:[[x,z]…]}]  name = OSM jméno přepsané na fiktivní
                    (FICTIONAL_NAMES); jméno s nenamapovaným reálným toponymem
                    se zahodí → null
    water    [[[x,z]…]]  outer kroužky vodních ploch protínajících katastr
    forest   [[[x,z]…]]  outer kroužky lesů protínajících katastr

Spuštění (z kořene repozitáře; závislosti numpy + osmium jako tools/surface.py):
  python3 tools/obce.py
"""
import json
import math
import os
import sys
import unicodedata

import numpy as np
import osmium

HERE = os.path.dirname(os.path.abspath(__file__))
GAME = os.path.dirname(HERE)
ROOT = os.path.dirname(GAME)
DATA = os.path.join(GAME, "data")
PBF = os.path.join(ROOT, "geodata", "pbf", "zlinsky-latest.osm.pbf")
OUT = os.path.join(DATA, "obce.json")

# --- laditelné konstanty -----------------------------------------------------
LOG_RADIUS = 8000.0      # výpis place uzlů okolo domova pro kontrolu (m)
COLLECT_KM = 4.0         # půlstrana lat/lon čtverce pro předfiltr sběru ways (km)
ROAD_OVERHANG = 200.0    # přesah silnic za hranici katastru, ať ulice navazují (m)
HULL_PAD = 150.0         # nafouknutí konvexní obálky fallback hranice (m)
CIRCLE_PTS = 48          # bodů kruhového fallback polygonu
RADIUS_HINT = {"town": 400.0, "village": 250.0, "hamlet": 150.0}
PLACE_TYPES = set(RADIUS_HINT)

# reálné → fiktivní (POUZE fiktivní jména jdou do výstupu; mapování slouží jen
# k nalezení obce v OSM a k přejmenování případných názvů silnic/toků)
OBCE = [
    ("Březnice", "Břehatice"),            # jako řeka v tools/water.py
    ("Bohuslavice u Zlína", "Bohulečice"),
    ("Březůvky", "Březouchy"),
    ("Velký Ořechov", "Velký Oříškov"),
    ("Hřivínův Újezd", "Hřiváčův Újezd"),
]
REAL2FIC = dict(OBCE)
# přejmenování i pro názvy silnic/toků (sjednoceno s export_map.py a water.py)
FICTIONAL_NAMES = dict(REAL2FIC)
FICTIONAL_NAMES.update({
    "Černý potok": "Blatný potok",
    "Kaňovický potok": "Havraní potok",
    "Neradovský potok": "Sojčí potok",
    "Oskorušný potok": "Jeřabinový potok",
    "Zlámanecký potok": "Sokolí potok",
})

# OSM building=* → hrubý typ (church/chapel/tower pro zvýraznění dominant)
BUILDING_KIND = {
    "church": "church", "cathedral": "church", "basilica": "church",
    "chapel": "chapel", "wayside_shrine": "chapel",
    "tower": "tower", "belfry": "tower", "bell_tower": "tower",
    "garage": "garage", "garages": "garage", "carport": "garage",
    "barn": "barn", "farm_auxiliary": "barn", "cowshed": "barn",
    "stable": "barn", "sty": "barn", "farm": "barn",
    "shed": "shed", "hut": "shed", "greenhouse": "shed", "slurry_tank": "shed",
    "school": "public", "kindergarten": "public", "public": "public",
    "civic": "public", "townhall": "public", "community_centre": "public",
    "fire_station": "public", "office": "public", "sports_hall": "public",
    "commercial": "commercial", "retail": "commercial", "supermarket": "commercial",
    "industrial": "industrial", "warehouse": "industrial",
}


def fname_road(name, place_names):
    """Jméno silnice → fiktivní podoba nebo None (zahodit).

    1) přesná shoda s FICTIONAL_NAMES (silnice/obec/tok),
    2) substring náhrada mapovaných toponym („… Velký Ořechov“ → „… Velký Oříškov“),
    3) obsahuje-li název reálné toponymum z okolí (place uzel, len≥4 znaky),
       které fiktivní protějšek nemá → None (raději bez jména než reálný název)."""
    if name in FICTIONAL_NAMES:
        return FICTIONAL_NAMES[name]
    out = name
    for real, fic in sorted(REAL2FIC.items(), key=lambda kv: -len(kv[0])):
        out = out.replace(real, fic)
    for pl in place_names:
        if len(pl) >= 4 and pl in out:
            return None
    return out


def slug(name):
    """ASCII slug z fiktivního jména: 'Hřiváčův Újezd' → 'hrivacuv-ujezd'."""
    s = unicodedata.normalize("NFKD", name).encode("ascii", "ignore").decode()
    return "-".join("".join(c if c.isalnum() else " " for c in s.lower()).split())


# --- geometrie v herních souřadnicích (metry) ---------------------------------
def pip(pt, poly):
    """Bod v polygonu (ray casting). poly = [[x,z]…]"""
    x, y = pt
    inside = False
    j = len(poly) - 1
    for i in range(len(poly)):
        xi, yi = poly[i]
        xj, yj = poly[j]
        if (yi > y) != (yj > y) and x < xi + (y - yi) * (xj - xi) / (yj - yi):
            inside = not inside
        j = i
    return inside


def seg_cross(p, q, r, s):
    """Protínají se úsečky p–q a r–s (včetně dotyku)?"""
    def ori(a, b, c):
        return (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0])
    o1, o2 = ori(p, q, r), ori(p, q, s)
    o3, o4 = ori(r, s, p), ori(r, s, q)
    return (o1 * o2 <= 0) and (o3 * o4 <= 0)


def seg_hits_poly(p, q, poly):
    """Úsečka p–q protíná některou hranu polygonu?"""
    j = len(poly) - 1
    for i in range(len(poly)):
        if seg_cross(p, q, poly[j], poly[i]):
            return True
        j = i
    return False


def dist_pt_seg(p, a, b):
    """Vzdálenost bodu p od úsečky a–b."""
    ax, ay = a
    bx, by = b
    dx, dy = bx - ax, by - ay
    L2 = dx * dx + dy * dy
    if L2 < 1e-12:
        return math.hypot(p[0] - ax, p[1] - ay)
    t = max(0.0, min(1.0, ((p[0] - ax) * dx + (p[1] - ay) * dy) / L2))
    return math.hypot(p[0] - ax - t * dx, p[1] - ay - t * dy)


def dist_pt_poly(p, poly):
    """Min vzdálenost bodu od hranice polygonu (0 uvnitř nezjišťuje – jen hrany)."""
    d = float("inf")
    j = len(poly) - 1
    for i in range(len(poly)):
        d = min(d, dist_pt_seg(p, poly[j], poly[i]))
        j = i
    return d


def poly_area(poly):
    """Podepsaná plocha polygonu (shoelace, m²)."""
    a = 0.0
    j = len(poly) - 1
    for i in range(len(poly)):
        a += poly[j][0] * poly[i][1] - poly[i][0] * poly[j][1]
        j = i
    return 0.5 * a


def convex_hull(pts):
    """Konvexní obálka (Andrew monotone chain) → [[x,z]…] proti směru hod. ručiček."""
    P = sorted(set((p[0], p[1]) for p in pts))
    if len(P) < 3:
        return [list(p) for p in P]

    def cross(o, a, b):
        return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])

    lo = []
    for p in P:
        while len(lo) >= 2 and cross(lo[-2], lo[-1], p) <= 0:
            lo.pop()
        lo.append(p)
    hi = []
    for p in reversed(P):
        while len(hi) >= 2 and cross(hi[-2], hi[-1], p) <= 0:
            hi.pop()
        hi.append(p)
    return [list(p) for p in lo[:-1] + hi[:-1]]


def inflate_hull(hull, pad):
    """Nafoukne konvexní obálku o pad m (posun vrcholů od těžiště; aproximace)."""
    cx = sum(p[0] for p in hull) / len(hull)
    cy = sum(p[1] for p in hull) / len(hull)
    out = []
    for x, y in hull:
        d = math.hypot(x - cx, y - cy) or 1.0
        out.append([x + pad * (x - cx) / d, y + pad * (y - cy) / d])
    return out


def circle_poly(c, r, n=CIRCLE_PTS):
    return [[c[0] + r * math.cos(2 * math.pi * i / n),
             c[1] + r * math.sin(2 * math.pi * i / n)] for i in range(n)]


def poly_hit(a, b):
    """Protínají se polygony a, b? (vrchol uvnitř, nebo se kříží hrany)"""
    if any(pip(p, b) for p in a) or any(pip(p, a) for p in b):
        return True
    for i in range(len(a)):
        if seg_hits_poly(a[i - 1], a[i], b):
            return True
    return False


def stitch_rings(ways_refs):
    """Sešije member ways (seznamy node refů) do uzavřených prstenců.
    Ways sdílejí koncové uzly – lepí se za konce (obě orientace)."""
    pool = [list(w) for w in ways_refs if len(w) >= 2]
    rings = []
    while pool:
        ring = pool.pop()
        moved = True
        while ring[0] != ring[-1] and moved:
            moved = False
            for i, w in enumerate(pool):
                if w[0] == ring[-1]:
                    ring += w[1:]
                elif w[-1] == ring[-1]:
                    ring += w[-2::-1]
                elif w[-1] == ring[0]:
                    ring = w[:-1] + ring
                elif w[0] == ring[0]:
                    ring = w[1::-1] + ring
                else:
                    continue
                pool.pop(i)
                moved = True
                break
        if ring[0] == ring[-1] and len(ring) >= 4:
            rings.append(ring)
    return rings


def clip_road(pts, poly, pad):
    """Ořízne lomenou čáru silnice na katastr + pad m přesah.
    Vrátí seznam souvislých úseků (každý ≥ 2 body). Vrchol se drží, když leží
    uvnitř katastru nebo do pad m od jeho hranice; úsečka mezi dvěma drženými
    vrcholy se emituje celá, úsečka křížící hranici přidá oba konce."""
    n = len(pts)
    if n < 2:
        return []
    keep = [pip(p, poly) or dist_pt_poly(p, poly) <= pad for p in pts]
    for i in range(n - 1):
        if not (keep[i] and keep[i + 1]) and seg_hits_poly(pts[i], pts[i + 1], poly):
            keep[i] = keep[i + 1] = True
    out, run = [], []
    for i, p in enumerate(pts):
        if keep[i]:
            run.append(p)
        else:
            if len(run) >= 2:
                out.append(run)
            run = []
    if len(run) >= 2:
        out.append(run)
    return out


# --- 1. průchod: place uzly + admin relace ------------------------------------
class PlacesAndRelations(osmium.SimpleHandler):
    def __init__(self, lat0, lon0):
        super().__init__()
        self.lat0, self.lon0 = lat0, lon0
        self.places = []           # (dist_m, place, name, lat, lon)
        self.rels = {}             # real_name → {"id", "members": [(way_ref, role)]}

    def _dist(self, lat, lon):
        p0 = math.radians(self.lat0)
        return math.hypot(math.radians(lon - self.lon0) * math.cos(p0) * 6371008.8,
                          math.radians(lat - self.lat0) * 6371008.8)

    def node(self, n):
        p = n.tags.get("place")
        if not p or not n.location.valid():
            return
        d = self._dist(n.location.lat, n.location.lon)
        if d <= LOG_RADIUS:
            self.places.append((d, p, n.tags.get("name", ""),
                                n.location.lat, n.location.lon))

    def relation(self, r):
        t = r.tags
        if t.get("boundary") == "administrative" and t.get("admin_level") == "8":
            nm = t.get("name", "")
            if nm in REAL2FIC and nm not in self.rels:
                self.rels[nm] = {"id": r.id,
                                 "members": [(m.ref, m.role) for m in r.members
                                             if m.type == "w"]}


# --- 2. průchod: geometrie -----------------------------------------------------
class Collector(osmium.SimpleHandler):
    def __init__(self, anchors, member_refs):
        super().__init__()
        # lat/lon čtverce kolem kotv pro levný předfiltr (±COLLECT_KM)
        self.box = {}
        for real, (la, lo) in anchors.items():
            dla = COLLECT_KM / 111.32
            dlo = COLLECT_KM / (111.32 * math.cos(math.radians(la)))
            self.box[real] = (la - dla, la + dla, lo - dlo, lo + dlo)
        self.member_refs = member_refs   # way ref → obec (pro ruční sešití)
        self.member_ways = {}            # way ref → [node ref…]
        self.member_nodes = {}           # node ref → (lat, lon)
        self.boundaries = {}             # real → [outer rings latlon]  (z area())
        self.buildings = []              # (kind, [latlon])
        self.roads = []                  # (kind, name, [latlon])
        self.water = []                  # [[latlon] outer]
        self.forest = []

    def _near(self, la, lo):
        for la0, la1, lo0, lo1 in self.box.values():
            if la0 <= la <= la1 and lo0 <= lo <= lo1:
                return True
        return False

    def _bbox_near(self, lla, llo, hla, hlo):
        for la0, la1, lo0, lo1 in self.box.values():
            if hla >= la0 and lla <= la1 and hlo >= lo0 and llo <= lo1:
                return True
        return False

    def way(self, w):
        if w.id in self.member_refs:
            try:
                refs, ll = [], []
                for nd in w.nodes:
                    refs.append(nd.ref)
                    ll.append((nd.location.lat, nd.location.lon))
                self.member_ways[w.id] = refs
                for r_, l_ in zip(refs, ll):
                    self.member_nodes[r_] = l_
            except osmium.InvalidLocationError:
                pass
        t = w.tags
        bld = t.get("building")
        hwy = t.get("highway")
        if not bld and not hwy:
            return
        try:
            ll = [(nd.location.lat, nd.location.lon) for nd in w.nodes]
        except osmium.InvalidLocationError:
            return
        if len(ll) < 2:
            return
        las = [p[0] for p in ll]
        los = [p[1] for p in ll]
        if not self._bbox_near(min(las), min(los), max(las), max(los)):
            return
        if bld:
            self.buildings.append((BUILDING_KIND.get(bld, "house"), ll))
        else:
            self.roads.append((hwy, t.get("name"), ll))

    def area(self, a):
        t = a.tags
        is_bnd = t.get("boundary") == "administrative" and t.get("admin_level") == "8"
        is_water = t.get("natural") == "water" or t.get("landuse") in ("reservoir", "basin")
        is_forest = t.get("landuse") == "forest" or t.get("natural") == "wood"
        if not (is_bnd or is_water or is_forest):
            return
        if is_bnd and t.get("name") not in REAL2FIC:
            return
        try:
            outers = [[(nd.lat, nd.lon) for nd in ring] for ring in a.outer_rings()]
        except osmium.InvalidLocationError:
            return
        if not outers:
            return
        if is_bnd:
            # více outer ringů (exklávy) se uloží všechny – vybere se později
            self.boundaries.setdefault(t["name"], []).extend(outers)
            return
        for ring in outers:
            las = [p[0] for p in ring]
            los = [p[1] for p in ring]
            if not self._bbox_near(min(las), min(los), max(las), max(los)):
                continue
            (self.water if is_water else self.forest).append(ring)


def pick_anchor(real, places):
    """Vybere place uzel obce: přesná shoda name, jinak fuzzy (stejné slovo,
    nejblíž domovu). Vrátí (lat, lon, place, matched_name)."""
    exact = [p for p in places if p[2] == real and p[1] in PLACE_TYPES]
    if exact:
        d, pl, nm, la, lo = min(exact)
        return la, lo, pl, nm
    # fuzzy: place uzel obsahující význačné slovo (např. „Újezd“ u variant jména)
    words = [w for w in real.replace("u Zlína", "").split() if len(w) > 3]
    cand = [p for p in places if p[1] in PLACE_TYPES and p[2] and
            any(w in p[2] for w in words)]
    if cand:
        d, pl, nm, la, lo = min(cand)
        print(f"  FUZZY: '{real}' → place uzel '{nm}' ({pl}, {d:.0f} m od domova)")
        return la, lo, pl, nm
    return None


def transform_latlon(tf):
    """Z make_transform (lat,lon)→(scene_x, scene_y) udělá (lat,lon)→[game_x, game_z]."""
    def g(la, lo):
        sx, sy = tf(la, lo)
        return [sx, -sy]
    return g


def main():
    sys.path.insert(0, os.path.join(ROOT, "scripts"))
    from phase2_osm_to_local import make_transform  # noqa: E402
    ref = json.load(open(os.path.join(ROOT, "data", "scene_reference.json")))
    tf = transform_latlon(make_transform(ref))
    lat0, lon0 = ref["house_latlon"]
    hx, hy = ref["house_scene_xy"]
    home = [hx, -hy]                      # domov hráče v herních souřadnicích

    if not os.path.exists(PBF):
        sys.exit(f"chybí {PBF} – stáhni zlinsky-latest.osm.pbf (viz tools/surroundings.py)")

    # ---- průchod 1: place uzly + relace
    p1 = PlacesAndRelations(lat0, lon0)
    p1.apply_file(PBF)
    print(f"place uzly do {LOG_RADIUS / 1000:.0f} km od domova "
          f"({len(p1.places)}; village/hamlet/town označeny *):")
    for d, pl, nm, la, lo in sorted(p1.places):
        mark = "*" if pl in PLACE_TYPES else " "
        tgt = " ← CÍL" if nm in REAL2FIC else ""
        print(f"  {d:7.0f} m{mark} {pl:18s} {nm or '–':32s} {la:.5f} {lo:.5f}{tgt}")

    anchors, place_type = {}, {}
    for real, fic in OBCE:
        hit = pick_anchor(real, p1.places)
        if not hit:
            print(f"  !! obec '{real}' (→{fic}): place uzel NENALEZEN v okruhu "
                  f"{LOG_RADIUS / 1000:.0f} km – přeskočena")
            continue
        la, lo, pl, matched = hit
        anchors[real] = (la, lo)
        place_type[real] = pl
        print(f"KOTVA {fic:20s} ← '{matched}' ({pl}) @ {la:.5f},{lo:.5f}  "
              f"game=({tf(la, lo)[0]:.0f},{tf(la, lo)[1]:.0f})")
    if not anchors:
        sys.exit("žádná obec nemá place uzel – konec")
    # reálná toponyma z okolí – pro hygienický filtr názvů silnic (viz fname_road)
    place_names = {nm for _, _, nm, _, _ in p1.places if nm}

    # ---- průchod 2: geometrie
    member_refs = {}                     # way_ref → real (pro ruční sešití)
    for real, rel in p1.rels.items():
        for wref, role in rel["members"]:
            if role in ("outer", ""):
                member_refs[wref] = real
    col = Collector(anchors, member_refs)
    col.apply_file(PBF, locations=True, idx="sparse_mem_array")
    print(f"OSM: {len(col.buildings)} budov, {len(col.roads)} silnic, "
          f"{len(col.water)} vodních a {len(col.forest)} lesních ploch v okolí kotv; "
          f"hranice z area(): {sorted(col.boundaries)}")

    # předtransformované polygony ke klasifikaci (levné: jen v okolí kotv)
    out_obce = []
    for real, fic in OBCE:
        if real not in anchors:
            continue
        la, lo = anchors[real]
        center = tf(la, lo)
        hint = RADIUS_HINT.get(place_type[real], 200.0)

        # ---- hranice katastru
        boundary, bsrc = None, None
        rings = []
        for ring in col.boundaries.get(real, []):
            poly = [tf(a, b) for a, b in ring]
            if poly and poly[0] == poly[-1]:
                poly = poly[:-1]
            if len(poly) >= 3:
                rings.append(poly)
        if rings:
            # hlavní ring = ten s kotvou uvnitř, jinak největší plocha
            inside = [r for r in rings if pip(center, r)]
            boundary = inside[0] if inside else max(rings, key=lambda r: abs(poly_area(r)))
            if len(rings) > 1:
                print(f"  {fic}: {len(rings)} outer ringů – vybrán "
                      f"{'s kotvou' if inside else 'největší'}")
            bsrc = "relation"
        elif real in p1.rels:
            # ruční sešití member ways (osmium area() prstenec nevyrobil)
            wrefs = [wr for wr, role in p1.rels[real]["members"] if role in ("outer", "")]
            stitched = stitch_rings([col.member_ways[w] for w in wrefs
                                     if w in col.member_ways])
            polys = []
            for ring in stitched:
                if all(r in col.member_nodes for r in ring):
                    polys.append([tf(*col.member_nodes[r]) for r in ring[:-1]])
            if polys:
                inside = [p for p in polys if pip(center, p)]
                boundary = inside[0] if inside else max(polys, key=lambda p: abs(poly_area(p)))
                bsrc = "stitch"
                print(f"  {fic}: hranice z ručního sešití ({len(stitched)} ringů)")
        if boundary is None:
            # fallback: dočasná sběrná oblast = kruh 2·hint kolem kotvy
            boundary = circle_poly(center, 2 * hint)
            bsrc = "circle-tmp"

        # ---- budovy uvnitř katastru (centroid nebo vrchol uvnitř)
        buildings = []
        for kind, ll in col.buildings:
            if len(ll) < 4:
                continue
            poly = [tf(a, b) for a, b in ll]
            if poly[0] == poly[-1]:
                poly = poly[:-1]
            if len(poly) < 3:
                continue
            cx = sum(p[0] for p in poly) / len(poly)
            cz = sum(p[1] for p in poly) / len(poly)
            if pip((cx, cz), boundary) or any(pip(p, boundary) for p in poly):
                buildings.append({"poly": [[round(x, 2), round(z, 2)] for x, z in poly],
                                  "kind": kind})

        # ---- silnice uvnitř katastru + ROAD_OVERHANG přesah
        roads = []
        for kind, name, ll in col.roads:
            pts = [tf(a, b) for a, b in ll]
            for seg_pts in clip_road(pts, boundary, ROAD_OVERHANG):
                item = {"kind": kind,
                        "pts": [[round(x, 2), round(z, 2)] for x, z in seg_pts]}
                # name=None i když OSM jméno existuje, ale nelze ho anonymizovat
                item["name"] = fname_road(name, place_names) if name else None
                roads.append(item)

        # ---- fallback hranice, když relace chyběla: obálka obsahu + HULL_PAD
        if bsrc == "circle-tmp":
            pts = [p for b_ in buildings for p in b_["poly"]]
            pts += [p for r_ in roads for p in r_["pts"]]
            if len(pts) >= 3:
                boundary = inflate_hull(convex_hull(pts), HULL_PAD)
                bsrc = "hull"
            else:
                boundary = circle_poly(center, hint)
                bsrc = "circle"

        # ---- voda / les protínající katastr
        water, forest = [], []
        for dst, rings_ll in ((water, col.water), (forest, col.forest)):
            for ring in rings_ll:
                poly = [tf(a, b) for a, b in ring]
                if poly and poly[0] == poly[-1]:
                    poly = poly[:-1]
                if len(poly) >= 3 and poly_hit(poly, boundary):
                    dst.append([[round(x, 2), round(z, 2)] for x, z in poly])

        radius = math.sqrt(abs(poly_area(boundary)) / math.pi)
        radius = max(radius, hint if bsrc in ("circle",) else 0.0)
        dist_home = math.hypot(center[0] - home[0], center[1] - home[1])
        if len(buildings) < 20:
            print(f"  POZOR {fic}: jen {len(buildings)} budov – málo dat v OSM?")
        out_obce.append({
            "id": slug(fic), "name": fic, "place": place_type[real],
            "center": [round(center[0], 2), round(center[1], 2)],
            "radius": round(radius, 1),
            "boundary_src": bsrc,
            "boundary": [[round(x, 2), round(z, 2)] for x, z in boundary],
            "buildings": buildings, "roads": roads,
            "water": water, "forest": forest,
        })
        print(f"OBEC {fic:20s} id={slug(fic):16s} center=({center[0]:7.1f},{center[1]:7.1f}) "
              f"{dist_home:5.0f} m od domova | budov {len(buildings):4d} silnic {len(roads):3d} "
              f"voda {len(water)} les {len(forest)} | hranice {bsrc} r={radius:.0f} m")

    doc = {
        "version": 1,
        "generated": "tools/obce.py z OSM (geodata/pbf/zlinsky-latest.osm.pbf; © přispěvatelé ODbL)",
        "note": "Názvy obcí jsou FIKTIVNÍ (PRAVNI_DOPORUCENI.md); geometrie z OSM.",
        "units": "m, herní souřadnice Godot (x, z)",
        "obce": out_obce,
    }
    with open(OUT, "w", encoding="utf-8") as f:
        json.dump(doc, f, ensure_ascii=False, indent=1)
    nb = sum(len(o["buildings"]) for o in out_obce)
    nr = sum(len(o["roads"]) for o in out_obce)
    print(f"WROTE {OUT}: {len(out_obce)} obcí, {nb} budov, {nr} úseků silnic")


if __name__ == "__main__":
    main()
