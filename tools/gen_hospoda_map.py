#!/usr/bin/env python3
# Generátor data/maps/hospoda.map (Quake 1 formát) – hospoda 10 × 8 m.
# Souřadnice .map jsou Quake (Z-up): Godot x = quake y, Godot y = quake z, Godot z = quake x.
# 32 qu = 1 m (inverse_scale_factor ve FuncGodotMapSettings).
# Výsledný soubor se commituje; skript je jen pomocný nástroj.

import os
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "data/maps/hospoda.map")


def q(gx, gy, gz):
    """Godot souřadnice (m) → Quake souřadnice (qu)."""
    return (gz * 32.0, gx * 32.0, gy * 32.0)


# 6 stěn kvádru [mn, mx] v Quake souřadnicích; body p0,p1,p2 zvolené tak, aby normála
# (p0-p2) × (p0-p1) mířila ven z kvádru (ověřeno proti parseru FuncGodot, Plane(p0,p1,p2)).
def box_faces(mn, mx):
    x0, y0, z0 = mn
    x1, y1, z1 = mx
    return [
        [(x1, y0, z0), (x1, y0, z1), (x1, y1, z0)],   # +X
        [(x0, y0, z0), (x0, y1, z0), (x0, y0, z1)],   # -X
        [(x0, y1, z0), (x1, y1, z0), (x0, y1, z1)],   # +Y
        [(x0, y0, z0), (x0, y0, z1), (x1, y0, z0)],   # -Y
        [(x0, y0, z1), (x0, y1, z1), (x1, y0, z1)],   # +Z
        [(x0, y0, z0), (x1, y0, z0), (x0, y1, z0)],   # -Z
    ]


def fmt(p):
    return "( %d %d %d )" % (round(p[0]), round(p[1]), round(p[2]))


def brush(mn, mx, tex):
    out = ["{"]
    for f in box_faces(mn, mx):
        out.append("%s %s %s %s 0 0 0 1 1" % (fmt(f[0]), fmt(f[1]), fmt(f[2]), tex))
    out.append("}")
    return "\n".join(out)


def gbox(gc0, gc1, tex):
    """Kvádr zadaný v Godot metrech (dva rohy) → brush v Quake jednotkách."""
    q0 = q(*gc0)
    q1 = q(*gc1)
    mn = tuple(min(a, b) for a, b in zip(q0, q1))
    mx = tuple(max(a, b) for a, b in zip(q0, q1))
    return brush(mn, mx, tex)


def entity(props, brushes=None):
    out = ["{"]
    for k, v in props.items():
        out.append('"%s" "%s"' % (k, v))
    for b in brushes or []:
        out.append(b)
    out.append("}")
    return "\n".join(out)


def marker(classname, targetname, gx, gy, gz, angle):
    o = q(gx, gy, gz)
    return entity({"classname": classname, "targetname": targetname,
                   "origin": "%d %d %d" % (round(o[0]), round(o[1]), round(o[2])),
                   "angle": str(angle)})


def table(cx, cz):
    """Hospodský stůl s lavicemi (deska + 2 lavice), Godot souřadnice středu."""
    b = []
    b.append(gbox((cx - 0.4, 0.72, cz - 0.95), (cx + 0.4, 0.80, cz + 0.95), "wood"))   # deska
    for s in (-1.0, 1.0):
        b.append(gbox((cx + s * 0.62 - 0.14, 0.0, cz - 0.95), (cx + s * 0.62 + 0.14, 0.44, cz + 0.95), "wood"))
    return b


world_brushes = []

# --- podlaha a strop (vnitřek x∈[-5,5], z∈[-4,4], strop 2,625 m = 84 qu) ---
world_brushes.append(gbox((-5.25, -0.25, -4.25), (5.25, 0.0, 4.25), "floor"))
world_brushes.append(gbox((-5.25, 2.625, -4.25), (5.25, 2.875, 4.25), "ceiling"))
# --- obvodové stěny (tl. 0,25 m) ---
world_brushes.append(gbox((-5.25, -0.25, -4.25), (5.25, 2.875, -4.0), "wall"))     # sever
world_brushes.append(gbox((-5.25, -0.25, 4.0), (-0.5, 2.875, 4.25), "wall"))       # jih Z od dveří
world_brushes.append(gbox((0.5, -0.25, 4.0), (5.25, 2.875, 4.25), "wall"))         # jih V od dveří
world_brushes.append(gbox((-0.5, 2.0, 4.0), (0.5, 2.875, 4.25), "wall"))           # jih nad dveřmi (otvor 1,0 × 2,0 m)
world_brushes.append(gbox((-5.25, -0.25, -4.25), (-5.0, 2.875, 4.25), "wall"))     # západ
world_brushes.append(gbox((5.0, -0.25, -4.25), (5.25, 2.875, 4.25), "wall"))       # východ

entities = [entity({"classname": "worldspawn",
                    "message": "Hospoda U Hriste – mapovy interier (Faze 2, FuncGodot)"},
                   world_brushes)]

# --- nábytek: 3 stoly s lavicemi, výčepní pult, police, stoličky, bedny, dveřní křídlo ---
furniture = []
for t in [(-3.0, 0.8), (-0.9, 0.8), (1.5, -1.5)]:
    entities.append(entity({"classname": "func_detail"}, table(*t)))

bar = [
    gbox((3.9, 0.0, -1.5), (4.55, 1.10, 2.5), "wood"),      # korpus pultu
    gbox((3.8, 1.10, -1.6), (4.65, 1.16, 2.6), "wood"),     # deska pultu
    gbox((4.75, 1.30, -1.25), (4.97, 1.36, 2.25), "wood"),  # police s lahvemi (2)
    gbox((4.75, 1.70, -1.25), (4.97, 1.76, 2.25), "wood"),
    gbox((4.55, 0.0, 2.9), (4.95, 0.8, 3.6), "wood"),       # bedny s pivem
]
for i, z in enumerate([-0.9, 0.4, 1.7]):                     # barové stoličky
    bar.append(gbox((3.2, 0.0, z - 0.18), (3.5, 0.6, z + 0.18), "wood"))
entities.append(entity({"classname": "func_detail"}, bar))

# dveřní křídlo (východ přes E „Vyjít ven“; východ je v jižní stěně → quake −X stěna)
entities.append(entity({"classname": "func_detail"},
                       [gbox((-0.5, 0.0, 4.03), (0.5, 1.97, 4.19), "wood")]))

# --- značky (point entity): spawn, E-body, místa k sezení, obsluha, pípa, stoly, lampy ---
entities.append(marker("info_player_start", "spawn", 0.0, 0.05, 3.0, 180))
entities.append(marker("sc_exit", "exit", 0.0, 0.0, 3.4, 180))
# štamgasti u stolu T1 (-3.0, 0.8): 2× západní lavice (yaw +90° → angle 270), 1× východní (yaw −90° → angle 90)
entities.append(marker("sc_seat", "seat_reg_0", -3.62, -0.05, 0.35, 270))
entities.append(marker("sc_seat", "seat_reg_1", -3.62, -0.05, 1.25, 270))
entities.append(marker("sc_seat", "seat_reg_2", -2.38, -0.05, 0.8, 90))
# páteční hosté u stolu T2 (-0.9, 0.8)
entities.append(marker("sc_seat", "seat_fri_0", -1.52, -0.05, 0.35, 270))
entities.append(marker("sc_seat", "seat_fri_1", -1.52, -0.05, 1.25, 270))
entities.append(marker("sc_seat", "seat_fri_2", -0.28, -0.05, 0.8, 90))
entities.append(marker("sc_keeper", "keeper", 4.75, 0.0, 0.5, 90))      # hostinský za pultem (yaw −90°)
entities.append(marker("sc_bar", "bar", 3.4, 0.0, 0.5, 90))             # E „Hostinský Láďa – výčep“
entities.append(marker("sc_pipa", "pipa", 4.2, 1.2, 0.3, 90))           # M3.2 čepování (spot u pípy)
for i, (cx, cz) in enumerate([(-3.0, 0.8), (-0.9, 0.8), (1.5, -1.5)]):  # M3.1 „Uklidit stoly“
    entities.append(marker("sc_stul", "stul_%d" % i, cx, 0.8, cz, 180))
for i, (lx, lz) in enumerate([(-2.5, 0.8), (1.5, 0.8), (-0.5, -2.0)]):  # stropní světla
    entities.append(marker("sc_lamp", "lamp_%d" % i, lx, 2.4, lz, 180))

with open(OUT, "w") as f:
    f.write("// Hospoda U Hriste – Quake 1 .map (FuncGodot). Generovano skriptem, upravovatelne v TrenchBroomu.\n")
    f.write("// M meritko: 32 qu = 1 m; quake X → godot Z, Y → X, Z → Y. Vchod v jizni stene (quake -X), hrac celi -Z.\n")
    f.write("\n".join(entities) + "\n")
print("zapsano", OUT)
