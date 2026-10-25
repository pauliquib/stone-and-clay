"""Vizuální validátor – datová vrstva: kontroly herních dat bez enginu → <out>/data.json.

  python3 tools/vizual/validate_data.py [--out=logs/vizual/latest] [--data=data] [--quick]

Vstupy: data/buildings.json, data/map.json, data/water.json; je-li k dispozici, i terrain_height.bin,
trees.bin, vegetation.bin a DBM1 sítě (walls/roofs/asphalt/gravel.bin) – bez nich se příslušné
kontroly přeskočí (SKIP). Nálezy: severity FAIL (opravdu rozbité) / WARN (podezřelé) / INFO,
v JSON jen TOP_N nejhorších na kontrolu + počty; souhrnné metriky (kolik % domů sedí) v "summary".
Prahy jsou konstanty níže.
"""
import argparse
import math
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import (GAME, DRIVABLE, ROAD_W, Findings, Terrain, RoadIndex, BuildingRaster,  # noqa: E402
                    load_json, save_json, poly_area, points_in_poly, grid_in_poly, seg_point_dist,
                    self_intersections, densify, read_trees, read_vegetation, read_dbm1, r3)

TOP_N = 50                    # nálezů na kontrolu v JSON

# --- domy: výška zdí (eave − ground) podle typu: (min, WARN nad, FAIL nad) v m
WALL_H = {"house": (2.2, 9.0, 16.0), "shed": (1.8, 5.5, 12.0), "garage": (2.0, 4.5, 10.0),
          "barn": (2.0, 12.0, 20.0), "hall": (2.5, 14.0, 25.0), "public": (2.5, 15.0, 30.0),
          "church": (2.5, 40.0, 70.0)}
WALL_H_DEFAULT = (2.0, 12.0, 25.0)
SLENDER_WARN = 1.6            # výška zdí / √plocha – „věž“ z malého půdorysu (typicky výška ze stromu)
ROOF_PITCH = (8.0, 62.0)      # rozumný sklon střechy (°) – mimo → WARN
ROOF_PITCH_FAIL = 75.0        # nad → FAIL (hrot)
FLAT_TOL = 0.3                # flat: |ridge − eave| (m)
# --- překryvy
OVL_STEP = 0.2                # krok vzorkování průniku (m)
OVL_WARN_M2 = 0.5             # překryv domů nad → WARN
OVL_FAIL_FRAC = 0.3           # překryv / plocha menšího domu nad → FAIL (duplicita)
ROAD_STEP = 0.25              # krok vzorkování půdorysu proti silnicím (m)
ROAD_WARN_M2 = 1.0            # zásah do vozovky (sjízdné) nad → WARN …
ROAD_WARN_DEPTH = 0.3         # … a aspoň tak hluboko (m)
ROAD_FAIL_M2 = 10.0           # zásah nad → FAIL, je-li zároveň hloubka nad ROAD_FAIL_DEPTH
ROAD_FAIL_DEPTH = 1.5
MINOR_WARN_M2 = 3.0           # cesty (track/path/footway…) – zásah nad → WARN, jinak INFO
# --- dveře
DOOR_EDGE_WARN = 0.3          # vzdálenost dveří od obvodu (m)
DOOR_EDGE_FAIL = 2.0
DOOR_FACE_COS = -0.3          # cos(normála hrany, směr k silnici) pod → WARN (dveře míří od cesty)
DOOR_FACE_MIN_DIST = 2.0      # blíž silnici se směr nehodnotí (šum)
DOOR_EXTRA_WARN = 8.0         # dveře o tolik dál od silnice než nejbližší bod obvodu → WARN
# --- terén pod domy
TERR_INSET = 1.0         # m – vzorky terénu pod domem až tak daleko od zdi
TERR_STEP = 1.0               # krok vzorků uvnitř půdorysu (m)
TERR_MEAN_WARN, TERR_MAX_WARN = 0.15, 0.5
TERR_MEAN_FAIL, TERR_MAX_FAIL = 0.6, 2.0
TERR_SPIKE = 15.0             # |Laplacián| výšek (m) nad → špička v terénu
# --- silnice na terénu
PROF_STEP = 2.0               # krok profilu (m)
STEP_H = 0.35                 # schod mezi sousedními vzorky (m)
STEP_EXCESS = 0.25            # … o kolik se liší od okolního sklonu
SLOPE_BASE = 10.0             # základna sklonu (m)
SLOPE_WARN, SLOPE_FAIL = 0.15, 0.25
SLOPE_MIN_LEN = 20.0          # m délky nad SLOPE_WARN, než je to WARN (kratší úseky jen INFO)
SLOPE_MIN_LEN_FAIL = 10.0     # m délky nad SLOPE_FAIL (sjízdné) → FAIL
CROSS_WARN, CROSS_FAIL = 0.10, 0.25   # příčný sklon (90. percentil po silnici)
# --- stromy, vegetace, předměty
TREE_DY = (-0.6, 0.1)         # y stromu − terén (m)
TREE_DY_FAIL = -3.0           # zanořený pod
TREE_ROAD_DEPTH = 0.3         # strom na sjízdné vozovce hlouběji než (m) → WARN
TREE_AXIS_FAIL = 1.0          # strom blíž ose sjízdné silnice (mimo service) → FAIL
TREE_IN_HOUSE_FAIL = 1.0      # strom hlouběji v domě (m od obvodu) → FAIL
ITEMS_ON_ROAD_OK = {"dukat"}  # předměty, které export_map.py klade záměrně na osu silnice
VEG_SAMPLE, VEG_SAMPLE_QUICK = 400_000, 60_000
VEG_DY = (-0.3, 0.15)
VEG_FRAC_WARN = 0.002         # podíl instancí v domě / na silnici / mimo terén nad → WARN
VEG_FRAC_FAIL = 0.05
# --- DBM1 sítě
DEGEN_AREA = 1e-6             # m² – degenerovaný trojúhelník
DEGEN_FRAC_WARN = 0.001
NORMAL_TOL = 0.02
WALL_GAP_WARN, WALL_GAP_FAIL = 0.15, 0.5   # spodní hrana zdi nad terénem (m)
WALL_DEEP_WARN = 1.5          # spodní hrana zdi hlouběji pod terénem (m)
ROOF_TOP_TOL = 0.6            # max výška střechy vs ridge_y (m)
GABLE_R = 30.0                # hrana ve výšce okapu domu do této vzdálenosti = základna štítu, ne spodek zdi
GABLE_OUT = 1.0               # základna štítu dál od půdorysu než (m) → WARN (štít trčí do prázdna)


def build_arrays(buildings):
    polys = []
    for b in buildings:
        p = np.asarray(b["poly"], dtype=np.float64)
        if poly_area(p) < 0:      # sjednotit orientaci (kladná plocha) → vnější normála hrany = (dz, −dx)
            p = p[::-1].copy()
        polys.append(p)
    return polys


def check_buildings(F, B, polys, roads_all, roads_drv):
    n = len(B)
    ok_h = ok_roof = 0
    for b, p in zip(B, polys):
        bid, t, shape = b["id"], b["type"], b["shape"]
        c = p.mean(0)
        pos = [c[0], b["ground_y"], c[1]]
        g, e, r = b["ground_y"], b["eave_y"], b["ridge_y"]
        wh = e - g
        # pořadí výšek
        if not (g < e):
            F.add("dum_vysky", "FAIL", f"okap {e:.2f} není nad terénem {g:.2f}", pos, 100 - wh, id=bid, type=t)
            continue
        if r < e - 0.01:
            F.add("dum_vysky", "FAIL", f"hřeben {r:.2f} pod okapem {e:.2f}", pos, e - r, id=bid, type=t)
            continue
        lo, hw, hf = WALL_H.get(t, WALL_H_DEFAULT)
        area = abs(poly_area(p))
        slender = wh / math.sqrt(max(area, 1.0))
        sev = None
        if wh > hf:
            sev, why = "FAIL", f"zdi {wh:.1f} m (> {hf} pro {t})"
        elif wh > hw:
            sev, why = "WARN", f"zdi {wh:.1f} m (> {hw} pro {t})"
        elif wh < lo:
            sev, why = "WARN", f"zdi jen {wh:.2f} m (< {lo} pro {t})"
        elif slender > SLENDER_WARN:
            sev, why = "WARN", f"štíhlá věž: zdi {wh:.1f} m na {area:.0f} m² (poměr {slender:.2f})"
        if sev:
            F.add("dum_vyska_zdi", sev, why, pos, wh, id=bid, type=t, shape=shape, area=area)
        else:
            ok_h += 1
        # střecha
        rh = r - e
        nf0 = sum(F.counts.get("dum_strecha", {}).values())
        if shape == "flat":
            if abs(rh) > FLAT_TOL:
                F.add("dum_strecha", "WARN", f"plochá střecha, ale hřeben {rh:.2f} m nad okapem", pos, rh, id=bid, type=t)
            ok_roof += sum(F.counts.get("dum_strecha", {}).values()) == nf0
            continue
        rd = np.asarray(b.get("ridge_dir") or [1, 0], dtype=float)
        rd = rd / (np.linalg.norm(rd) or 1.0)
        perp = np.array([-rd[1], rd[0]])
        proj = (p - c) @ perp
        half = (proj.max() - proj.min()) / 2
        pitch = math.degrees(math.atan2(rh, max(half, 0.1)))
        if rh <= 0.05:
            F.add("dum_strecha", "WARN", f"{shape}: hřeben jen {rh:.2f} m nad okapem", pos, 1, id=bid, type=t)
        elif pitch > ROOF_PITCH_FAIL:
            F.add("dum_strecha", "FAIL", f"{shape}: sklon {pitch:.0f}° (hřeben +{rh:.1f} m, polorozpětí {half:.1f} m)",
                  pos, pitch, id=bid, type=t, pitch=pitch)
        elif not (ROOF_PITCH[0] <= pitch <= ROOF_PITCH[1]):
            F.add("dum_strecha", "WARN", f"{shape}: sklon {pitch:.0f}° (hřeben +{rh:.1f} m, polorozpětí {half:.1f} m)",
                  pos, abs(pitch - 35), id=bid, type=t, pitch=pitch)
        # hřeben by měl ležet nad půdorysem
        rc = b.get("ridge_c")
        if rc and not points_in_poly(np.array([rc[0]]), np.array([rc[1]]), p)[0]:
            d = min(seg_point_dist(rc[0], rc[1], *p[i], *p[(i + 1) % len(p)])[0] for i in range(len(p)))
            if d > 0.5:
                F.add("dum_strecha", "WARN", f"střed hřebene {d:.1f} m mimo půdorys", pos, d, id=bid, type=t)
        ok_roof += sum(F.counts.get("dum_strecha", {}).values()) == nf0
    F.metrics("dum_vyska_zdi", ok_pct=100.0 * ok_h / max(n, 1))
    F.metrics("dum_strecha", ok_pct=100.0 * ok_roof / max(n, 1))

    # samoprotínání
    bad = 0
    for b, p in zip(B, polys):
        si = self_intersections(p)
        if si:
            bad += 1
            i, j = si[0]
            q = (p[i] + p[(i + 1) % len(p)]) / 2
            F.add("dum_pudorys", "FAIL" if len(si) > 2 else "WARN",
                  f"půdorys se protíná sám se sebou ({len(si)}×, hrany {i}/{j})",
                  [q[0], b["ground_y"], q[1]], len(si), id=b["id"])
        if len(p) < 3 or abs(poly_area(p)) < 2.0:
            F.add("dum_pudorys", "WARN", f"degenerovaný půdorys ({len(p)} bodů, {abs(poly_area(p)):.1f} m²)",
                  [p[0][0], b["ground_y"], p[0][1]], 1, id=b["id"])
    F.metrics("dum_pudorys", self_intersecting=bad)

    # překryvy domů (kandidáti podle AABB, plocha vzorkováním)
    mn = np.array([p.min(0) for p in polys])
    mx = np.array([p.max(0) for p in polys])
    pairs = 0
    tot = 0.0
    for i in range(n):
        cand = np.nonzero((mn[i + 1:, 0] < mx[i, 0]) & (mx[i + 1:, 0] > mn[i, 0]) &
                          (mn[i + 1:, 1] < mx[i, 1]) & (mx[i + 1:, 1] > mn[i, 1]))[0] + i + 1
        for j in cand:
            lo = np.maximum(mn[i], mn[j])
            hi = np.minimum(mx[i], mx[j])
            xs = np.arange(lo[0] + OVL_STEP / 2, hi[0], OVL_STEP)
            zs = np.arange(lo[1] + OVL_STEP / 2, hi[1], OVL_STEP)
            if xs.size == 0 or zs.size == 0:
                continue
            gx, gz = np.meshgrid(xs, zs)
            gx, gz = gx.ravel(), gz.ravel()
            m = points_in_poly(gx, gz, polys[i])
            if not m.any():
                continue
            m[m] = points_in_poly(gx[m], gz[m], polys[j])
            a = m.sum() * OVL_STEP * OVL_STEP
            if a <= OVL_WARN_M2:
                continue
            pairs += 1
            tot += a
            small = min(abs(poly_area(polys[i])), abs(poly_area(polys[j])))
            frac = a / max(small, 1e-6)
            q = (gx[m].mean(), gz[m].mean())
            F.add("dum_prekryv", "FAIL" if frac > OVL_FAIL_FRAC else "WARN",
                  f"domy {B[i]['id']} a {B[j]['id']} se překrývají o {a:.1f} m² ({100 * frac:.0f} % menšího)",
                  [q[0], B[i]["ground_y"], q[1]], a, id=B[i]["id"], other=B[j]["id"], overlap_m2=a)
    F.metrics("dum_prekryv", pairs=pairs, total_m2=tot)

    # zásah do silnic
    hit_drv = hit_minor = 0
    for b, p in zip(B, polys):
        gx, gz = grid_in_poly(p, ROAD_STEP)
        dep, ri = roads_all.depth(gx, gz)
        on = dep > 0
        if not on.any():
            continue
        kinds = np.array([roads_all.roads[k]["kind"] if k >= 0 else "" for k in ri[on]])
        drv = np.isin(kinds, list(DRIVABLE))
        for is_drv, mask in ((True, drv), (False, ~drv)):
            if not mask.any():
                continue
            a = mask.sum() * ROAD_STEP * ROAD_STEP
            d = float(dep[on][mask].max())
            k = np.argmax(np.where(mask, dep[on], -1))
            road = roads_all.roads[ri[on][k]]
            q = [gx[on][k], b["ground_y"], gz[on][k]]
            desc = f"{road['kind']}{' ' + road['name'] if road.get('name') else ''}"
            if is_drv:
                if a > ROAD_FAIL_M2 and d > ROAD_FAIL_DEPTH:
                    sev = "FAIL"
                elif a > ROAD_WARN_M2 and d > ROAD_WARN_DEPTH:
                    sev = "WARN"
                else:
                    sev = "INFO"
                hit_drv += sev != "INFO"
            else:
                sev = "WARN" if a > MINOR_WARN_M2 and d > ROAD_WARN_DEPTH else "INFO"
                hit_minor += sev != "INFO"
            F.add("dum_silnice", sev, f"dům zasahuje do {desc} – {a:.1f} m², až {d:.2f} m do vozovky "
                  f"(šířka {ROAD_W.get(road['kind'], 3)} m)", q, a, id=b["id"], type=b["type"], overlap_m2=a, depth=d)
    F.metrics("dum_silnice", warn_drivable=hit_drv, warn_minor=hit_minor,
              ok_pct=100.0 * (len(B) - hit_drv) / max(len(B), 1),
              note_widths="šířky podle tools/expand_buildings.py ROAD_W")

    # dveře
    ok_d = no_door = 0
    for b, p in zip(B, polys):
        door = b.get("door")
        if door is None:
            no_door += 1
            continue
        dx, dz = door
        nP = len(p)
        best = (1e9, 0, 0.0)
        for i in range(nP):
            d, t = seg_point_dist(dx, dz, *p[i], *p[(i + 1) % nP])
            if float(d) < best[0]:
                best = (float(d), i, float(t))
        d_edge, ei, et = best
        pos = [dx, b["ground_y"], dz]
        bad = False
        if d_edge > DOOR_EDGE_WARN:
            F.add("dvere_obvod", "FAIL" if d_edge > DOOR_EDGE_FAIL else "WARN",
                  f"dveře {d_edge:.2f} m od obvodu", pos, d_edge, id=b["id"])
            bad = True
        if roads_drv.empty:
            continue
        rdist, rp, rix = roads_drv.nearest(dx, dz)
        # nejbližší bod obvodu k silnici (vrcholy + středy hran) – kontrola „dveře na straně k cestě“
        ex = np.vstack([p, (p + np.roll(p, -1, 0)) / 2])
        pd = np.array([roads_drv.nearest(x, z)[0] for x, z in ex])
        if rdist > DOOR_FACE_MIN_DIST:
            # vnější normála hran u dveří (v rohu bereme lepší ze dvou)
            cand = [ei]
            if et < 0.05:
                cand.append((ei - 1) % nP)
            elif et > 0.95:
                cand.append((ei + 1) % nP)
            v = (rp - np.array([dx, dz])) / max(rdist, 1e-6)
            cos = -1.0
            for i in cand:
                e = p[(i + 1) % nP] - p[i]
                nrm = np.array([e[1], -e[0]]) / (np.linalg.norm(e) or 1)
                cos = max(cos, float(nrm @ v))
            extra = rdist - pd.min()
            if cos < DOOR_FACE_COS and extra > DOOR_EXTRA_WARN:
                F.add("dvere_smer", "WARN", f"dveře míří od silnice (cos {cos:.2f}), "
                      f"nejbližší bod obvodu je o {extra:.1f} m blíž", pos, extra, id=b["id"], cos=cos,
                      road=roads_drv.roads[rix]["kind"])
                bad = True
            elif cos < DOOR_FACE_COS:
                F.add("dvere_smer", "INFO", f"dveře na hraně odvrácené od silnice (cos {cos:.2f})",
                      pos, -cos, id=b["id"], cos=cos)
        ok_d += not bad
    with_door = len(B) - no_door
    F.metrics("dvere_obvod", with_door=with_door, without_door=no_door, ok_pct=100.0 * ok_d / max(with_door, 1))


def check_water(F, B, polys, water):
    if not water:
        F.skip("voda_domy", "chybí data/water.json")
        return
    kinds = water.get("kinds", {})
    hits = 0
    for pond in water.get("ponds", []):
        pp = np.asarray(pond["poly"], dtype=float)[:, :2]
        mn, mx = pp.min(0), pp.max(0)
        for b, p in zip(B, polys):
            if (p[:, 0].max() < mn[0] or p[:, 0].min() > mx[0] or p[:, 1].max() < mn[1] or p[:, 1].min() > mx[1]):
                continue
            gx, gz = grid_in_poly(p, 0.5)
            m = points_in_poly(gx, gz, pp)
            if m.sum() * 0.25 > 1.0:
                hits += 1
                F.add("voda_domy", "WARN", f"dům stojí v rybníku ({m.sum() * 0.25:.1f} m², hladina {pond.get('level')})",
                      [gx[m].mean(), b["ground_y"], gz[m].mean()], m.sum(), id=b["id"], pond=pond.get("osm_id"))
    # potoky přes půdorys
    allp = np.vstack(polys)
    bmn, bmx = allp.min(0) - 10, allp.max(0) + 10
    for s in water.get("streams", []):
        pts = np.asarray(s["pts"], dtype=float)
        if not ((pts[:, 0] > bmn[0]) & (pts[:, 0] < bmx[0]) & (pts[:, 1] > bmn[1]) & (pts[:, 1] < bmx[1])).any():
            continue
        hw = kinds.get(s.get("kind"), {}).get("half_w", 1.5)
        P, _ = densify(pts[:, :2], 0.5)
        for b, p in zip(B, polys):
            mn, mx = p.min(0) - hw, p.max(0) + hw
            m = (P[:, 0] > mn[0]) & (P[:, 0] < mx[0]) & (P[:, 1] > mn[1]) & (P[:, 1] < mx[1])
            if not m.any():
                continue
            inside = points_in_poly(P[m, 0], P[m, 1], p)
            if inside.sum() >= 2:
                hits += 1
                q = P[m][inside][0]
                F.add("voda_domy", "WARN", f"{s.get('kind')} {s.get('name') or s.get('osm_id')} teče domem "
                      f"({inside.sum() * 0.5:.0f} m osy v půdorysu)", [q[0], b["ground_y"], q[1]], inside.sum(), id=b["id"])
    F.metrics("voda_domy", hits=hits, ponds=len(water.get("ponds", [])), streams=len(water.get("streams", [])))


def check_items(F, M, B, polys, raster, roads_drv, terr):
    items = M.get("items", [])
    bad = 0
    for it in items:
        x, z = it["x"], it["z"]
        bi = int(raster.lookup(np.array([x]), np.array([z]))[0])
        if bi >= 0:
            bad += 1
            F.add("predmety", "WARN", f"{it['type']} leží v domě {B[bi]['id']}", [x, B[bi]["ground_y"], z], 2, id=B[bi]["id"])
            continue
        dep, ri = roads_drv.depth(np.array([x]), np.array([z]))
        if dep[0] > 0 and it["type"] not in ITEMS_ON_ROAD_OK:
            bad += 1
            F.add("predmety", "WARN", f"{it['type']} leží na silnici ({roads_drv.roads[ri[0]]['kind']})",
                  [x, 0, z], 1)
        if terr is not None and not np.isfinite(terr.sample(np.array([x]), np.array([z]))[0]):
            bad += 1
            F.add("predmety", "WARN", f"{it['type']} mimo výškovou mřížku", [x, 0, z], 1)
    sp = M.get("spawn")
    if sp:
        bi = int(raster.lookup(np.array([sp["x"]]), np.array([sp["z"]]))[0])
        if bi >= 0:
            F.add("predmety", "FAIL", f"spawn hráče leží v domě {B[bi]['id']}", [sp["x"], 0, sp["z"]], 10, id=B[bi]["id"])
    F.metrics("predmety", items=len(items), bad=bad)


def check_terrain(F, terr, B, polys, roads, quick):
    a = terr.a
    # celková sanita mřížky (po pásech kvůli paměti)
    nan = 0
    spikes = 0
    spike_pos = []
    hmin, hmax = np.inf, -np.inf
    band = 512
    for r0 in range(0, terr.h, band):
        blk = np.asarray(a[max(r0 - 1, 0):min(r0 + band + 1, terr.h)], dtype=np.float64)
        core = blk[(1 if r0 > 0 else 0):][:band]
        fin = np.isfinite(core)
        nan += int((~fin).sum())
        if fin.any():
            hmin, hmax = min(hmin, core[fin].min()), max(hmax, core[fin].max())
        if blk.shape[0] >= 3:
            lap = np.abs(4 * blk[1:-1, 1:-1] - blk[:-2, 1:-1] - blk[2:, 1:-1] - blk[1:-1, :-2] - blk[1:-1, 2:])
            m = lap > TERR_SPIKE
            k = int(m.sum())
            if k:
                spikes += k
                rr, cc = np.nonzero(m)
                for r, c in zip(rr[:5], cc[:5]):
                    R = max(r0 - 1, 0) + r + 1
                    spike_pos.append((float(lap[r, c]), R, c + 1))
    if nan:
        F.add("teren_mrizka", "FAIL", f"{nan} buněk výšek je NaN/inf", None, nan)
    for v, R, C in sorted(spike_pos, reverse=True)[:TOP_N]:
        x, z = terr.x0 + C * terr.sp, terr.z0 + R * terr.sp
        F.add("teren_mrizka", "WARN", f"špička v terénu (|Laplacián| {v:.1f} m)", [x, float(a[R, C]), z], v)
    F.metrics("teren_mrizka", w=terr.w, h=terr.h, h_min=hmin, h_max=hmax, nan=nan, spikes=spikes)

    # terén pod domy
    ok = 0
    devs = []
    for b, p in zip(B, polys):
        gx, gz = grid_in_poly(p, TERR_STEP)
        # jen body aspoň TERR_INSET od zdi: bilineární vzorek u zdi míchá buňku za ní (mřížka 2 m),
        # kde smí terén klesat/stoupat (sokl, vozovka u domu); u malých staveb aspoň těžiště
        if len(gx):
            dmin = np.full(len(gx), np.inf)
            for i in range(len(p)):
                a0, b0 = p[i], p[(i + 1) % len(p)]
                ab = b0 - a0
                t = np.clip(((gx - a0[0]) * ab[0] + (gz - a0[1]) * ab[1]) / max(float(ab @ ab), 1e-9), 0, 1)
                dmin = np.minimum(dmin, np.hypot(gx - a0[0] - ab[0] * t, gz - a0[1] - ab[1] * t))
            keep = dmin >= TERR_INSET
            gx, gz = gx[keep], gz[keep]
        if not len(gx):
            gx, gz = np.array([p[:, 0].mean()]), np.array([p[:, 1].mean()])
        h = terr.sample(gx, gz)
        if not np.isfinite(h).all():
            F.add("teren_domy", "WARN", "dům leží (částečně) mimo výškovou mřížku", [gx[0], b["ground_y"], gz[0]], 1, id=b["id"])
            continue
        d = h - b["ground_y"]
        mean, mxa = float(np.mean(d)), float(np.max(np.abs(d)))
        k = int(np.argmax(np.abs(d)))
        devs.append(mean)
        pos = [gx[k], h[k], gz[k]]
        slope = float(np.ptp(h)) / max(math.sqrt(abs(poly_area(p))), 1.0)
        if abs(mean) > TERR_MEAN_FAIL or mxa > TERR_MAX_FAIL:
            sev = "FAIL"
        elif abs(mean) > TERR_MEAN_WARN or mxa > TERR_MAX_WARN:
            sev = "WARN"
        else:
            ok += 1
            continue
        F.add("teren_domy", sev, f"terén vs ground_y: střed {mean:+.2f} m, max |Δ| {mxa:.2f} m "
              f"(rozdíl výšek pod domem {np.ptp(h):.2f} m)", pos, mxa, id=b["id"], type=b["type"],
              mean_dy=mean, max_dy=mxa, slope=slope)
    F.metrics("teren_domy", ok_pct=100.0 * ok / max(len(B), 1),
              mean_dy=float(np.mean(devs)) if devs else None,
              median_abs_dy=float(np.median(np.abs(devs))) if devs else None)

    # silnice: podélný profil, schody, příčný sklon
    nsamp = steps = steep = cross_bad = 0
    per_kind = {}
    for ri, r in enumerate(roads):
        kind = r.get("kind")
        P, s = densify(r["pts"], PROF_STEP)
        if len(P) < 3:
            continue
        h = terr.sample(P[:, 0], P[:, 1])
        if not np.isfinite(h).all():
            continue
        nsamp += len(P)
        drv = kind in DRIVABLE
        name = f"{kind}{' ' + r['name'] if r.get('name') else ''} (#{ri})"
        ds = np.maximum(np.diff(s), 1e-3)
        dh = np.diff(h)
        # schod = skok, který se výrazně liší od místního sklonu (medián okolních úseků)
        if len(dh) >= 5:
            from scipy.ndimage import median_filter
            loc = median_filter(dh, size=5, mode="nearest")
            st = (np.abs(dh) > STEP_H) & (np.abs(dh - loc) > STEP_EXCESS)
            if st.any():
                steps += int(st.sum())
                k = int(np.argmax(np.where(st, np.abs(dh - loc), 0)))
                F.add("silnice_schody", "WARN" if not drv else ("FAIL" if abs(dh[k]) > 1.0 else "WARN"),
                      f"{name}: schod {dh[k]:+.2f} m na {ds[k]:.1f} m ({int(st.sum())}× na silnici)",
                      [P[k, 0], h[k], P[k, 1]], abs(dh[k] - loc[k]), road=ri, kind=kind)
        # sklon na základně SLOPE_BASE
        kb = max(1, int(round(SLOPE_BASE / PROF_STEP)))
        if len(h) > kb:
            sl = np.abs(h[kb:] - h[:-kb]) / np.maximum(s[kb:] - s[:-kb], 1e-3)
            mx = float(sl.max())
            k = int(np.argmax(sl))
            pk = per_kind.setdefault(kind, [0, 0])
            pk[0] += len(sl)
            pk[1] += int((sl > SLOPE_WARN).sum())
            len_w = float((sl > SLOPE_WARN).sum() * PROF_STEP)
            len_f = float((sl > SLOPE_FAIL).sum() * PROF_STEP)
            if mx > SLOPE_WARN:
                sev = ("FAIL" if (drv and len_f >= SLOPE_MIN_LEN_FAIL) else
                       "WARN" if len_w >= SLOPE_MIN_LEN else "INFO")
                steep += sev != "INFO"
                F.add("silnice_sklon", sev, f"{name}: podélný sklon {100 * mx:.0f} % "
                      f"({100 * (sl > SLOPE_WARN).mean():.0f} % délky nad {100 * SLOPE_WARN:.0f} %)",
                      [P[k, 0], h[k], P[k, 1]], mx, road=ri, kind=kind, slope=mx)
        # příčný sklon přes šířku
        hw = ROAD_W.get(kind, 3.0) / 2
        if hw >= 1.5:
            tdir = np.gradient(P, axis=0)
            tdir /= np.maximum(np.linalg.norm(tdir, axis=1, keepdims=True), 1e-9)
            nrm = np.c_[-tdir[:, 1], tdir[:, 0]]
            hl = terr.sample(P[:, 0] + nrm[:, 0] * hw, P[:, 1] + nrm[:, 1] * hw)
            hr = terr.sample(P[:, 0] - nrm[:, 0] * hw, P[:, 1] - nrm[:, 1] * hw)
            cs = np.abs(hl - hr) / (2 * hw)
            cs = cs[np.isfinite(cs)]
            if cs.size:
                p90 = float(np.percentile(cs, 90))
                if p90 > CROSS_WARN:
                    cross_bad += 1
                    k = int(np.nanargmax(np.abs(hl - hr)))
                    F.add("silnice_pricny", "FAIL" if (p90 > CROSS_FAIL and drv) else "WARN",
                          f"{name}: příčný sklon 90. percentil {100 * p90:.0f} %, max {100 * cs.max():.0f} %",
                          [P[k, 0], h[k], P[k, 1]], p90, road=ri, kind=kind)
    F.metrics("silnice_schody", samples=nsamp, steps=steps)
    F.metrics("silnice_sklon", roads_steep=steep,
              pct_over_warn_by_kind={k: r3(100.0 * v[1] / max(v[0], 1), 2) for k, v in per_kind.items()})
    F.metrics("silnice_pricny", roads_bad=cross_bad)


def check_trees(F, path, B, polys, raster, roads_all, terr, drop):
    try:
        magic, d = read_trees(path)
    except (OSError, ValueError) as e:
        F.add("stromy", "FAIL", f"trees.bin nečitelný: {e}", None, 1)
        return
    n = len(d)
    keep = np.ones(n, bool)
    if drop:
        keep[[i for i in drop if 0 <= i < n]] = False
    idx = np.nonzero(keep)[0]
    x, y, z = d[idx, 0].astype(float), d[idx, 1].astype(float), d[idx, 2].astype(float)
    nanm = ~np.isfinite(d[idx]).all(axis=1)
    if nanm.any():
        F.add("stromy", "FAIL", f"{int(nanm.sum())} stromů má NaN/inf", None, nanm.sum())
    sc = d[idx, 4:7]
    badsc = ((sc <= 0) | (sc > 50)).any(axis=1)
    if badsc.any():
        F.add("stromy", "WARN", f"{int(badsc.sum())} stromů má podivné měřítko (≤0 nebo >50)", None, badsc.sum())
    col = d[idx, 7:10]
    if ((col < 0) | (col > 1.001)).any():
        F.add("stromy", "WARN", "barvy stromů mimo 0..1", None, 1)
    # v domě
    bi = raster.lookup(x, z)
    inh = np.nonzero(bi >= 0)[0]
    for k in inh:
        p = polys[bi[k]]
        de = min(float(seg_point_dist(x[k], z[k], *p[i], *p[(i + 1) % len(p)])[0]) for i in range(len(p)))
        F.add("stromy_domy", "FAIL" if de > TREE_IN_HOUSE_FAIL else "WARN",
              f"strom #{idx[k]} roste v domě {B[bi[k]]['id']} ({de:.1f} m od obvodu)",
              [x[k], y[k], z[k]], de, id=B[bi[k]]["id"], tree=int(idx[k]))
    # na silnici
    dep, ri = roads_all.depth(x, z)
    on = np.nonzero(dep > TREE_ROAD_DEPTH)[0]
    n_drv = n_minor = 0
    for k in on:
        r = roads_all.roads[ri[k]]
        kind = r["kind"]
        if kind not in DRIVABLE:
            n_minor += 1
            continue
        n_drv += 1
        axis = ROAD_W.get(kind, 3) / 2 - dep[k]
        sev = "FAIL" if (axis < TREE_AXIS_FAIL and kind != "service") else "WARN"
        F.add("stromy_silnice", sev, f"strom #{idx[k]} na {kind} {r.get('name') or ''} ({axis:.1f} m od osy)",
              [x[k], y[k], z[k]], dep[k], tree=int(idx[k]), kind=kind)
    F.metrics("stromy_silnice", trees=n, on_drivable=n_drv, on_minor_paths=n_minor)
    F.metrics("stromy_domy", in_house=len(inh))
    # výška vs terén
    if terr is not None:
        h = terr.sample(x, z)
        fin = np.isfinite(h)
        dy = y - h
        lo, hi = TREE_DY
        badl = fin & (dy < lo)
        badh = fin & (dy > hi)
        for k in np.nonzero(badl | badh)[0]:
            sev = "FAIL" if dy[k] < TREE_DY_FAIL else "WARN"
            F.add("stromy_teren", sev, f"strom #{idx[k]}: y − terén = {dy[k]:+.2f} m"
                  + (" (hra ho stáhne na terén)" if dy[k] > hi else ""), [x[k], y[k], z[k]], abs(dy[k]), tree=int(idx[k]))
        F.metrics("stromy_teren", ok_pct=100.0 * (fin & ~badl & ~badh).sum() / max(fin.sum(), 1),
                  too_low=int(badl.sum()), too_high=int(badh.sum()), off_grid=int((~fin).sum()),
                  median_dy=float(np.median(dy[fin])) if fin.any() else None)
    else:
        F.skip("stromy_teren", "chybí terrain_height.bin")
    F.metrics("stromy", magic=magic, count=n, dropped_in_water=int(n - len(idx)))


def check_vegetation(F, path, B, raster, roads_drv, terr, quick):
    try:
        magic, ver, rec = read_vegetation(path)
    except (OSError, ValueError) as e:
        F.add("vegetace", "FAIL", f"vegetation.bin nečitelný: {e}", None, 1)
        return
    if magic not in ("VEG1", "VEG2"):
        F.add("vegetace", "FAIL", f"neznámý magic {magic!r}", None, 1)
        return
    n = len(rec)
    ns = min(n, VEG_SAMPLE_QUICK if quick else VEG_SAMPLE)
    rng = np.random.default_rng(1)
    s = rec[rng.choice(n, ns, replace=False)] if ns < n else rec
    x, y, z = s["x"].astype(float), s["y"].astype(float), s["z"].astype(float)
    fin = np.isfinite(x) & np.isfinite(y) & np.isfinite(z) & np.isfinite(s["scale"])
    if (~fin).any():
        F.add("vegetace", "FAIL", f"{int((~fin).sum())} ze {ns} vzorků má NaN/inf", None, 1)
    typ = s["typ"]
    if (typ < 0).any() or (typ > 64).any():
        F.add("vegetace", "WARN", "typ instance mimo rozsah 0..64", None, 1)
    badsc = fin & ((s["scale"] <= 0) | (s["scale"] > 20))
    if badsc.any():
        F.add("vegetace", "WARN", f"{int(badsc.sum())} instancí má měřítko ≤0 nebo >20", None, badsc.sum())

    def frac_finding(check, mask, what, extra_pos):
        f = mask.sum() / max(ns, 1)
        sev = "FAIL" if f > VEG_FRAC_FAIL else "WARN" if f > VEG_FRAC_WARN else ("INFO" if mask.any() else None)
        if sev:
            ex = np.nonzero(mask)[0][:5]
            F.add(check, sev, f"{100 * f:.2f} % vzorku vegetace {what} ({int(mask.sum())} z {ns})",
                  extra_pos(ex[0]) if len(ex) else None, f,
                  examples=[[r3(x[k], 1), r3(y[k], 2), r3(z[k], 1), int(typ[k])] for k in ex])
        F.metrics(check, pct=100.0 * f, count_in_sample=int(mask.sum()))

    def p_of(k):
        return [x[k], y[k], z[k]]

    frac_finding("vegetace_domy", fin & (raster.lookup(x, z) >= 0), "stojí v domě", p_of)
    dep, _ = roads_drv.depth(x, z)
    frac_finding("vegetace_silnice", fin & (dep > 0.2), "stojí na sjízdné silnici", p_of)
    if terr is not None:
        h = terr.sample(x, z)
        dy = y - h
        ok = np.isfinite(h)
        frac_finding("vegetace_teren", fin & ok & ((dy < VEG_DY[0]) | (dy > VEG_DY[1])),
                     f"nesedí na terén (y − terén mimo {VEG_DY[0]}..{VEG_DY[1]} m)", p_of)
        F.metrics("vegetace_teren", median_dy=float(np.median(dy[ok & fin])) if (ok & fin).any() else None)
    else:
        F.skip("vegetace_teren", "chybí terrain_height.bin")
    F.metrics("vegetace", magic=magic, version=ver, count=n, sampled=ns,
              types={int(t): int(c) for t, c in zip(*np.unique(typ, return_counts=True))})


def check_meshes(F, data, B, polys, raster, terr):
    from scipy.spatial import cKDTree
    # KD-strom hran půdorysů → id domu pro body zdí
    EP, EI = [], []
    for i, p in enumerate(polys):
        P, _ = densify(np.vstack([p, p[:1]]), 0.5)
        EP.append(P)
        EI.append(np.full(len(P), i))
    etree = cKDTree(np.vstack(EP))
    eidx = np.concatenate(EI)
    for fname in ("walls.bin", "roofs.bin", "asphalt.bin", "gravel.bin"):
        check = "sit_" + fname.split(".")[0]
        path = os.path.join(data, fname)
        if not os.path.exists(path):
            F.skip(check, f"chybí data/{fname}")
            continue
        try:
            nch, tiles = read_dbm1(path)
        except (OSError, ValueError) as e:
            F.add(check, "FAIL", f"{fname} nečitelný: {e}", None, 1)
            continue
        nv = sum(len(t[0]) for t in tiles)
        if nv == 0:
            F.add(check, "FAIL", f"{fname}: žádné vrcholy", None, 1)
            continue
        pos = np.vstack([t[0] for t in tiles]).astype(np.float64)
        nrm = np.vstack([t[1] for t in tiles]).astype(np.float64)
        col = np.vstack([t[2] for t in tiles])
        bad_tiles = [i for i, t in enumerate(tiles) if len(t[0]) % 3]
        if bad_tiles:
            F.add(check, "FAIL", f"{len(bad_tiles)} dlaždic nemá počet vrcholů dělitelný 3", None, len(bad_tiles))
        nanv = ~np.isfinite(pos).all(1) | ~np.isfinite(nrm).all(1) | ~np.isfinite(col).all(1)
        if nanv.any():
            k = int(np.argmax(nanv))
            F.add(check, "FAIL", f"{int(nanv.sum())} vrcholů s NaN/inf", pos[k] if np.isfinite(pos[k]).all() else None,
                  nanv.sum())
        # trojúhelníky (jen ze správných dlaždic)
        tri = np.vstack([t[0][:len(t[0]) // 3 * 3] for t in tiles]).astype(np.float64).reshape(-1, 3, 3)
        cr = np.cross(tri[:, 1] - tri[:, 0], tri[:, 2] - tri[:, 0])
        area = 0.5 * np.linalg.norm(cr, axis=1)
        degen = ~(area > DEGEN_AREA)
        fd = degen.mean()
        if fd > 0:
            k = int(np.argmax(degen))
            F.add(check, "WARN" if fd > DEGEN_FRAC_WARN else "INFO",
                  f"{int(degen.sum())} degenerovaných trojúhelníků ({100 * fd:.3f} %)", tri[k, 0], fd)
        nl = np.linalg.norm(nrm, axis=1)
        badn = np.isfinite(nl) & (np.abs(nl - 1) > NORMAL_TOL)
        if badn.any():
            k = int(np.argmax(badn))
            F.add(check, "WARN", f"{int(badn.sum())} normál není jednotkových ({100 * badn.mean():.2f} %, "
                  f"délka např. {nl[k]:.3f})", pos[k], badn.mean())
        badc = np.isfinite(col).all(1) & ((col < -1e-4) | (col > 1.0001)).any(1)
        if badc.any():
            k = int(np.argmax(badc))
            F.add(check, "WARN", f"{int(badc.sum())} barev mimo 0..1 (např. {col[k].round(3).tolist()})", pos[k], badc.mean())
        m = {"tiles": nch, "vertices": nv, "triangles": int(len(tri)), "degenerate": int(degen.sum()),
             "bbox_min": pos.min(0).round(1).tolist(), "bbox_max": pos.max(0).round(1).tolist()}
        if fname == "walls.bin" and terr is not None:
            m.update(_walls_vs_terrain(F, check, tri, terr, etree, eidx, B))
        if fname == "roofs.bin":
            m.update(_roofs_vs_json(F, check, pos, raster, B, polys))
        F.metrics(check, **m)


def _walls_vs_terrain(F, check, tri, terr, etree, eidx, B):
    """Spodní hrana zdí vs terén. Spodní hrana = vodorovná hrana trojúhelníku, nad kterou zeď pokračuje
    a pod jejímiž konci už není žádný nižší vrchol (štíty, okapy ani dělení po patrech se tak nepočítají)."""
    from scipy.spatial import cKDTree
    ys = tri[:, :, 1]
    o = np.argsort(ys, axis=1)
    t = np.take_along_axis(tri, o[:, :, None], axis=1)        # vrcholy podle výšky
    y0, y1, y2 = t[:, 0, 1], t[:, 1, 1], t[:, 2, 1]
    up = (np.abs(y1 - y0) < 0.01) & (y2 - y1 > 0.05)           # dolní hrana trojúhelníku nad ní
    ea, eb = t[up, 0], t[up, 1]
    V = tri.reshape(-1, 3)
    kt = cKDTree(V[:, [0, 2]])

    def lowest_below(P):
        """Je pod bodem (do 0,15 m vodorovně) nižší vrchol zdi?"""
        res = np.zeros(len(P), bool)
        for i, nb in enumerate(kt.query_ball_point(P[:, [0, 2]], 0.15)):
            res[i] = (V[nb, 1] < P[i, 1] - 0.05).any()
        return res
    sel = ~lowest_below(ea) & ~lowest_below(eb) if len(ea) else np.zeros(0, bool)
    ea, eb = ea[sel], eb[sel]
    bot = np.vstack([ea, eb, (ea + eb) / 2]) if len(ea) else np.zeros((0, 3))
    h = terr.sample(bot[:, 0], bot[:, 2])
    ok = np.isfinite(h)
    gap = bot[:, 1] - h
    # přiřazení k domům (nejbližší hrana půdorysu do 3 m)
    d, j = etree.query(bot[:, [0, 2]], distance_upper_bound=3.0)
    bidx = np.where(np.isfinite(d), eidx[np.minimum(j, len(eidx) - 1)], -1)
    # základna štítu (tvar podle obdélníku, rohy mimo rohy zdí) leží na okapu některého domu do 3 m – není spodní hrana
    eave = np.array([b["eave_y"] for b in B])
    gable = {}
    for i, nb in enumerate(etree.query_ball_point(bot[:, [0, 2]], GABLE_R)):
        if not nb:
            continue
        bs = np.unique(eidx[nb])
        hit = bs[np.abs(eave[bs] - bot[i, 1]) < 0.3]
        if len(hit):
            ok[i] = False
            if np.isfinite(d[i]) and d[i] < GABLE_OUT:
                continue
            dd = float(etree.query(bot[i, [0, 2]])[0])
            if dd > GABLE_OUT:            # štít / okapová hrana trčí mimo půdorys bez zdi pod sebou
                b = int(hit[0])
                if dd > gable.get(b, (0, None))[0]:
                    gable[b] = (dd, i)
    for b, (dd, i) in gable.items():
        F.add(check, "WARN", f"štít domu {B[b]['id']} bez zdi pod sebou – {dd:.1f} m mimo půdorys", bot[i], dd, id=B[b]["id"])
    worst = {}
    for i in np.nonzero(ok & ((gap > WALL_GAP_WARN) | (gap < -WALL_DEEP_WARN)))[0]:
        b = int(bidx[i])
        w = worst.get(b)
        if w is None or abs(gap[i]) > abs(gap[w]):
            worst[b] = i
    for b, i in worst.items():
        g = gap[i]
        bid = B[b]["id"] if b >= 0 else None
        if g > 0:
            F.add(check, "FAIL" if g > WALL_GAP_FAIL else "WARN", f"zeď visí {g:.2f} m nad terénem"
                  + (f" (dům {bid})" if bid else " (mimo známý půdorys)"), bot[i], g, id=bid)
        else:
            F.add(check, "WARN", f"spodní hrana zdi {-g:.2f} m pod terénem" + (f" (dům {bid})" if bid else ""),
                  bot[i], -g, id=bid)
    fl = ok & (gap > WALL_GAP_WARN)
    return {"bottom_points": int(ok.sum()), "floating_pct": r3(100.0 * fl.sum() / max(ok.sum(), 1), 3),
            "buildings_floating": len([1 for b, i in worst.items() if gap[i] > 0]),
            "median_bottom_gap": r3(float(np.median(gap[ok])) if ok.any() else None)}


def _roofs_vs_json(F, check, pos, raster, B, polys):
    """Nejvyšší bod střechy domu vs ridge_y z buildings.json. Trojúhelník patří domu, nad jehož půdorysem
    leží jeho těžiště (hřebenové vrcholy štítových střech leží na obvodu, samotné vrcholy nestačí)."""
    n = len(pos) // 3 * 3
    tri = pos[:n].reshape(-1, 3, 3)
    c = tri.mean(1)
    tb = raster.lookup(c[:, 0], c[:, 2])
    bidx = np.repeat(tb, 3)
    pos = tri.reshape(-1, 3)
    top = np.full(len(B), -np.inf)
    np.maximum.at(top, bidx[bidx >= 0], pos[bidx >= 0, 1])
    bad = 0
    found = 0
    for i, b in enumerate(B):
        if not np.isfinite(top[i]):
            continue
        found += 1
        dd = top[i] - b["ridge_y"]
        if abs(dd) > ROOF_TOP_TOL:
            bad += 1
            c = polys[i].mean(0)
            F.add(check, "WARN", f"střecha domu {b['id']}: nejvyšší bod {top[i]:.2f} vs ridge_y {b['ridge_y']:.2f} "
                  f"({dd:+.2f} m)", [c[0], top[i], c[1]], abs(dd), id=b["id"])
    return {"buildings_with_roof": found, "roof_top_mismatch": bad}


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--out", default=os.path.join(GAME, "logs", "vizual", "latest"))
    ap.add_argument("--data", default=os.path.join(GAME, "data"))
    ap.add_argument("--quick", action="store_true")
    a = ap.parse_args()
    data = a.data
    F = Findings("data", TOP_N)

    B = load_json(os.path.join(data, "buildings.json"))
    M = load_json(os.path.join(data, "map.json"))
    W = load_json(os.path.join(data, "water.json"))
    if not B or not M:
        F.add("vstupy", "FAIL", "chybí nebo je nečitelný data/buildings.json či data/map.json", None, 1)
        save_json(os.path.join(a.out, "data.json"), F.result())
        print("validate_data: FAIL – chybí vstupy")
        return 1
    if isinstance(B, dict):
        B = B.get("buildings", [])
    roads = M.get("roads", [])
    polys = build_arrays(B)
    roads_all = RoadIndex(roads)
    roads_drv = RoadIndex(roads, DRIVABLE)
    raster = BuildingRaster(polys)
    kinds = {}
    for r in roads:
        kinds[r.get("kind")] = kinds.get(r.get("kind"), 0) + 1

    print(f"validate_data: {len(B)} domů, {len(roads)} silnic {kinds}")
    check_buildings(F, B, polys, roads_all, roads_drv)
    check_water(F, B, polys, W)

    terr = None
    tpath = os.path.join(data, (M.get("height") or {}).get("file", "terrain_height.bin"))
    if os.path.exists(tpath) and M.get("height"):
        try:
            terr = Terrain(tpath, M["height"])
        except (OSError, ValueError) as e:
            F.add("teren_mrizka", "FAIL", str(e), None, 1)
    if terr is not None:
        check_terrain(F, terr, B, polys, roads, a.quick)
    else:
        for c in ("teren_mrizka", "teren_domy", "silnice_schody", "silnice_sklon", "silnice_pricny"):
            if c not in F.counts:
                F.skip(c, "chybí data/terrain_height.bin")
    check_items(F, M, B, polys, raster, roads_drv, terr)

    tp = os.path.join(data, "trees.bin")
    if os.path.exists(tp):
        check_trees(F, tp, B, polys, raster, roads_all, terr, set((W or {}).get("drop_trees", [])))
    else:
        for c in ("stromy", "stromy_domy", "stromy_silnice", "stromy_teren"):
            F.skip(c, "chybí data/trees.bin")
    vp = os.path.join(data, "vegetation.bin")
    if os.path.exists(vp):
        check_vegetation(F, vp, B, raster, roads_drv, terr, a.quick)
    else:
        for c in ("vegetace", "vegetace_domy", "vegetace_silnice", "vegetace_teren"):
            F.skip(c, "chybí data/vegetation.bin")
    check_meshes(F, data, B, polys, raster, terr)

    # souhrn
    summary = {"buildings": len(B), "roads": len(roads), "road_kinds": kinds,
               "items": len(M.get("items", [])),
               "bins_present": sorted(f for f in os.listdir(data) if f.endswith(".bin"))}
    for ch, d in F.checks.items():
        if "ok_pct" in d.get("metrics", {}):
            summary[f"{ch}_ok_pct"] = d["metrics"]["ok_pct"]
    res = F.result(summary)
    save_json(os.path.join(a.out, "data.json"), res)
    print(f"validate_data: {res['status']}  FAIL {res['totals']['FAIL']}  WARN {res['totals']['WARN']}  "
          f"INFO {res['totals']['INFO']}  ({res['seconds']} s) → {os.path.join(a.out, 'data.json')}")
    for ch, d in res["checks"].items():
        c = d["counts"]
        print(f"  {d['status']:4} {ch:18} F{c['FAIL']:<4} W{c['WARN']:<5} I{c['INFO']:<5} "
              + (d.get("note", "") if d["status"] == "SKIP" else
                 " ".join(f"{k}={v}" for k, v in d.get("metrics", {}).items() if not isinstance(v, (dict, list)))))
    return 0


if __name__ == "__main__":
    sys.exit(main())
