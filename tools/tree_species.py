"""Druhy dřevin a porosty podle stanoviště → data/tree_eco.bin. M8.3 (00_PRINCIPY §3, §8 „Dřeviny").

Každému stromu z data/trees.bin (číslování = pořadí v souboru, stejné jako TreeManager/Fauna/TreeDecor)
přiřadí druh z data/dreviny.json, věk, vitalitu, výšku a výčetní tloušťku. Za běhu se jen čte
(`scripts/eko/tree_eco.gd`, `World.tree_eco`).

Zdroje (vše lokální, nic se nestahuje):
  data/trees.bin     – stromy (11 × f32: x, y, z, rot, sx, sy, sz, r, g, b, proto; proto 0–2 listnáč, 3–5 jehličnan)
  data/site.bin      – stanoviště M8.2 (TWI, HAND, vzdálenost k vodě, AWC, pH, živiny, oslunění, mrazová kotlina…)
  data/surface.bin   – třídy povrchu (2 sad/zahrada, 3 les, 4 zástavba, 5 břeh, 7 polní cesta)
  data/landuse.bin   – 3 sad / vinice, 4 zahrádky
  data/map.json      – silnice (aleje podél cest)
  data/dreviny.json  – katalog druhů (Ellenberg, tolerance, růst, alometrie)

Model (podle čeho – 00_PRINCIPY §8 „Dřeviny"):
  1. stanoviště → Ellenbergovy hodnoty buňky: L z hustoty korun v okolí (zápoj), F z TWI/HAND/AWC/oslunění,
     R z pH, N ze živin, T z výšky (−6,5 K/km) + oslunění − mrazová kotlina
  2. vhodnost druhu = exp(−½ Σ ((stanoviště − optimum) / σ)²); σ se na „mokré“ straně rozšiřuje tolerancí
     k zamokření, na suché toleranci k suchu, na tmavé toleranci ke stínu, na studené toleranci k mrazu
  3. porosty: les (třída 3 nebo hustý zápoj) se dělí Voronoiem s deformovanými souřadnicemi (domain warp,
     ~POROST_SPACING m) × třída stanoviště (luh / sever / jih / plošina) → porost 0,5–5 ha; porost má
     hospodářský typ (smrková monokultura na části kopců / smíšený listnatý / luh) a 1–3 hlavní druhy,
     stromy v porostu mají jeden věk ± rozptyl
  4. omezení geometrií: proto 3–5 → jen jehličnany, 0–2 → listnáče a ovocné; ovocné jen v sadech, zahradách,
     zástavbě a v alejích u cest
  5. barva z ortofota jen jako nápověda (tmavá → smrk/jedle/buk, světlá → bříza/modřín/akát)
  6. vitalita = vhodnost^0,5 × hloubka půdy × náhoda; věk z inverze Chapman–Richards h(t) = H·(1−e^(−kt))^p
     se stanovištním H (výška z trees.bin je měření, ne výsledek); dbh z Näslundovy alometrie
     h = 1,3 + d²/(a + b·d)² (solitéry tlustší – volný růst)

Formát data/tree_eco.bin (little endian):
  4 B   magic "TECO"
  int32 verze (1)
  int32 N (= počet stromů v trees.bin)
  int32 velikost záznamu R (12)
  int32 počet druhů S, pak S × (u8 délka, ASCII id druhu) – index druhu = pořadí tady (= pořadí v dreviny.json)
  int32 počet porostů P
  N × R B záznam: u8 druh, u8 věk (roky, max 255), u8 vitalita 0–255, u8 příznaky, f16 výška (m),
                  f16 dbh (cm), u16 porost (0xFFFF = mimo porost), u16 rezerva
     příznaky: 1 les (porost), 2 solitér, 4 alej, 8 sad/zahrada, 16 zástavba, 32 okraj porostu, 64 luh
  int32 počet mřížek G, pak G × (4 B kód, f32 x0, z0, cell, int32 nx, nz, nx·nz × u8):
     CANO – zápoj korun 0..255 (16 m), DOMI – dominantní druh (32 m, 255 = bez stromů), VIGO – průměrná vitalita (32 m)

  python3 tools/tree_species.py [--out=data/tree_eco.bin] [--seed=N]
"""
import json
import math
import os
import struct
import sys

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage
from scipy.spatial import cKDTree

HERE = os.path.dirname(os.path.abspath(__file__))
GAME = os.path.dirname(HERE)
DATA = os.path.join(GAME, "data")

SEED = 20261015

# --- laditelné konstanty -------------------------------------------------------------------------------
DENS_R = 40.0             # m – okolí pro hustotu stromů (zápoj); trees.bin je řídký (soused ~20 m – jen vrcholy korun z DMP)
DENS_FULL_PCT = 80.0      # percentil počtu sousedů u stromů ve třídě les (3) = plný zápoj (samokalibrace na data)
FOREST_DENS = 0.35        # zápoj, od kterého je strom v lese i mimo třídu 3
EDGE_DENS = 0.55          # zápoj pod tímto prahem uvnitř lesa = okraj porostu (víc světla)
POROST_SPACING = 220.0    # m – rozestup zárodků porostů (Voronoi) → ~1–2 ha, dělení stanovištěm zmenší
WARP_AMP = 45.0           # m – deformace hranic porostů (šum)
WARP_SCALE = 160.0        # m – vlnová délka deformace
SITE_SMOOTH = 120.0       # m – vyhlazení stanoviště (oslunění, sklon) před dělením porostů na třídy
LUH_SMOOTH = 24.0         # m – vyhlazení HAND / vzdálenosti k vodě pro luh (úzký pás podél potoka)
LUH_HAND = 2.5            # m – luh: výška nad vodou pod tímto…
LUH_DISW = 35.0           # m – …a do této vzdálenosti od vody
SMRK_P_BASE = 0.38        # pravděpodobnost smrkové monokultury v porostu (realita českých lesů)
SMRK_P_NORTH = 0.18       # + na severních / chladných svazích
SMRK_P_SOUTH = -0.2       # − na jižních
SMRK_P_CONIF = 1.5        # + (podíl jehličnatých prototypů v porostu − průměr) × tohle
ALEJ_ROAD_M = 10.0        # m od cesty = alej (mimo les a zástavbu)
ORTHO_HINT = 0.25         # síla nápovědy z ortofota (0 = vypnuto)
SUIT_POW = 0.8            # jak silně vhodnost stanoviště rozhoduje u jednotlivého stromu
SOLITER_DBH = 1.3         # solitér (volný růst) má tlustší kmen
AGE_STAND_W = 0.6         # váha věku porostu proti vlastnímu odhadu stromu
AGE_JITTER = 0.12         # ± podíl rozptylu věku v porostu
T_LAPSE = 6.5             # K/km – vertikální gradient (00_PRINCIPY §8 Mikroklima)
ELEV_ABS0 = 330.0         # m n. m. počátku světa (dům hráče) – ELEV v site.bin je relativní k němu; odhad, ověřit
T_REF_ELEV = 330.0        # m n. m., kde je Ellenberg T = T_REF
T_REF = 6.0               # Ellenberg T v referenční výšce (3. vegetační stupeň dubobukový – pahorkatina)
ROAD_KINDS = ("tertiary", "secondary", "unclassified", "track", "residential", "service")

# kontextové priority mimo les (sad, zástavba, alej, pole, břeh) – podíly, ne pravděpodobnosti
CONTEXT = {
    "sad": {"jablon": 0.34, "svestka": 0.24, "hrusen": 0.12, "tresen": 0.12, "orech": 0.06, "lipa": 0.03,
            "briza": 0.03, "smrk": 0.6, "borovice": 0.15, "jedle": 0.1, "modrin": 0.05},
    "obec": {"lipa": 0.14, "briza": 0.1, "javor_klen": 0.08, "jablon": 0.15, "svestka": 0.12, "orech": 0.09,
             "hrusen": 0.05, "tresen": 0.07, "akat": 0.05, "jasan": 0.05, "topol": 0.04,
             "smrk": 0.55, "borovice": 0.2, "jedle": 0.1, "modrin": 0.05},
    "alej": {"tresen": 0.18, "svestka": 0.14, "jablon": 0.14, "hrusen": 0.1, "lipa": 0.15, "javor_klen": 0.1,
             "jasan": 0.05, "dub_letni": 0.08, "orech": 0.06, "smrk": 0.4, "borovice": 0.4, "modrin": 0.2},
    "pole": {"dub_letni": 0.22, "lipa": 0.15, "hrusen": 0.08, "briza": 0.12, "tresen_ptaci": 0.1, "jiva": 0.08,
             "javor_klen": 0.08, "akat": 0.07, "habr": 0.05, "dub_zimni": 0.05, "smrk": 0.4, "borovice": 0.45, "modrin": 0.15},
    "breh": {"olse": 0.35, "vrba_bila": 0.25, "topol": 0.12, "jasan": 0.1, "jiva": 0.1, "dub_letni": 0.05,
             "smrk": 0.6, "borovice": 0.2, "jedle": 0.2},
}
# hospodářské typy porostů: hlavní druhy (podíly) – zbytek doplní vhodnost × podil_les
STAND_TYPES = {
    "smrcina": {"smrk": 0.82, "modrin": 0.06, "borovice": 0.04, "buk": 0.04, "jedle": 0.02, "briza": 0.02},
    "luh": {"olse": 0.4, "jasan": 0.2, "vrba_bila": 0.12, "topol": 0.08, "dub_letni": 0.08, "javor_klen": 0.05,
            "smrk": 0.04, "jiva": 0.03},
}
ORTHO_DARK = ("smrk", "jedle", "buk")
ORTHO_LIGHT = ("briza", "modrin", "akat", "vrba_bila")

FL_LES, FL_SOLITER, FL_ALEJ, FL_SAD, FL_OBEC, FL_OKRAJ, FL_LUH = 1, 2, 4, 8, 16, 32, 64


def arg(name, default):
    for a in sys.argv[1:]:
        if a.startswith("--" + name + "="):
            return a.split("=", 1)[1]
    return default


def read_raster(path, magic, nbytes_per_cell=1):
    b = open(path, "rb").read()
    assert b[:4] == magic, f"{path}: neznámý formát"
    _ver, x0, z0, cell, nx, nz = struct.unpack("<i3f2i", b[4:28])
    a = np.frombuffer(b, np.uint8, nx * nz * nbytes_per_cell, 28).reshape(nz, nx, nbytes_per_cell)
    return a, x0, z0, cell, nx, nz


def read_site(path):
    b = open(path, "rb").read()
    assert b[:4] == b"SITE", "site.bin: neznámý formát"
    _ver, x0, z0, cell, nx, nz, nl = struct.unpack("<i3f3i", b[4:32])
    hdrs = []
    off = 32
    for _ in range(nl):
        code = b[off:off + 4].decode("ascii")
        dt = b[off + 4]
        sc, of = struct.unpack("<ff", b[off + 8:off + 16])
        hdrs.append((code, dt, sc, of))
        off += 16
    layers = {}
    for code, dt, sc, of in hdrs:
        n = nx * nz
        if dt == 1:
            raw = np.frombuffer(b, np.uint16, n, off).reshape(nz, nx); off += n * 2
        else:
            raw = np.frombuffer(b, np.uint8, n, off).reshape(nz, nx); off += n
        layers[code] = (raw, sc, of)
    return layers, x0, z0, cell, nx, nz


def value_noise(x, z, scale, seed):
    """Hladký 2D šum (bilineární hodnotový šum, 2 oktávy) – deterministický."""
    out = np.zeros_like(x)
    amp = 1.0
    tot = 0.0
    for o in range(2):
        s = scale / (2 ** o)
        gx = x / s
        gz = z / s
        ix = np.floor(gx).astype(np.int64)
        iz = np.floor(gz).astype(np.int64)
        fx = gx - ix
        fz = gz - iz
        fx = fx * fx * (3 - 2 * fx)
        fz = fz * fz * (3 - 2 * fz)

        def h(a, b):
            v = (a * 374761393 + b * 668265263 + (seed + o * 7919) * 1442695041) & 0xFFFFFFFF
            v = ((v ^ (v >> 13)) * 1274126177) & 0xFFFFFFFF
            return (v & 0xFFFF) / 65535.0 * 2.0 - 1.0
        v00 = h(ix, iz); v10 = h(ix + 1, iz); v01 = h(ix, iz + 1); v11 = h(ix + 1, iz + 1)
        out += amp * ((v00 * (1 - fx) + v10 * fx) * (1 - fz) + (v01 * (1 - fx) + v11 * fx) * fz)
        tot += amp
        amp *= 0.5
    return out / tot


def hash01(i, salt):
    v = (np.asarray(i, np.uint64) * np.uint64(2654435761) + np.uint64(salt * 97 + 12345)) & np.uint64(0xFFFFFFFF)
    v = (v ^ (v >> np.uint64(15))) * np.uint64(2246822519) & np.uint64(0xFFFFFFFF)
    v = v ^ (v >> np.uint64(13))
    return (v & np.uint64(0xFFFFFF)).astype(np.float64) / float(0xFFFFFF)


def main():
    if "--help" in sys.argv or "-h" in sys.argv:
        print(__doc__)
        return
    seed = int(arg("seed", SEED))
    out_path = arg("out", os.path.join(DATA, "tree_eco.bin"))
    cat = json.load(open(os.path.join(DATA, "dreviny.json"), encoding="utf-8"))["druhy"]
    ids = [s["id"] for s in cat]
    S = len(ids)
    sidx = {k: i for i, k in enumerate(ids)}
    typ = np.array([{"listnac": 0, "jehlicnan": 1, "ovocny": 2}[s["typ"]] for s in cat])

    tb = open(os.path.join(DATA, "trees.bin"), "rb").read()
    N = struct.unpack("<i", tb[4:8])[0]
    T = np.frombuffer(tb, np.float32, N * 11, 8).reshape(N, 11).astype(np.float64)
    tx, tz, th, tsx = T[:, 0], T[:, 2], T[:, 5], T[:, 4]
    conif = T[:, 10] >= 3
    print(f"Stromů: {N}, z toho jehličnatý prototyp {conif.sum()} ({100 * conif.mean():.1f} %)")

    # --- stanoviště v místě stromu (nejbližší buňka 4 m) ---
    layers, sx0, sz0, scell, snx, snz = read_site(os.path.join(DATA, "site.bin"))
    ix = np.clip(((tx - sx0) / scell).astype(int), 0, snx - 1)
    iz = np.clip(((tz - sz0) / scell).astype(int), 0, snz - 1)

    def lay(code, smooth_m=0.0):
        raw, sc, of = layers[code]
        g = of + raw.astype(np.float32) * sc
        if smooth_m > 0:
            g = ndimage.uniform_filter(g, size=max(1, int(smooth_m / scell)))
        return g

    def at(code):
        return lay(code)[iz, ix].astype(np.float64)

    elev, twi, disw, hand = at("ELEV"), at("TWI_"), at("DISW"), at("HAND")
    insy, cpol, awc, nutr = at("INSY"), at("CPOL"), at("AWC_"), at("NUTR")
    ph = at("PH__")
    if np.median(ph) > 14.0:     # site.bin v1 ukládá pH × 10 se scale 1 (M8.2) – přepočet na skutečné pH
        ph = ph / 10.0
    sdep = at("SDEP")
    soil = layers["SOIL"][0][iz, ix]

    # --- povrch, landuse, cesty ---
    surf, ux0, uz0, ucell, unx, unz = read_raster(os.path.join(DATA, "surface.bin"), b"SURF")
    surf = surf[:, :, 0]
    uix = np.clip(((tx - ux0) / ucell).astype(int), 0, unx - 1)
    uiz = np.clip(((tz - uz0) / ucell).astype(int), 0, unz - 1)
    tsurf = surf[uiz, uix]
    lu, lx0, lz0, lcell, lnx, lnz = read_raster(os.path.join(DATA, "landuse.bin"), b"LUSE", 2)
    lix = np.clip(((tx - lx0) / lcell).astype(int), 0, lnx - 1)
    liz = np.clip(((tz - lz0) / lcell).astype(int), 0, lnz - 1)
    tlu = lu[liz, lix, 0]
    meta = json.load(open(os.path.join(DATA, "map.json"), encoding="utf-8"))
    img = Image.new("L", (unx, unz), 0)
    dr = ImageDraw.Draw(img)
    for r in meta.get("roads", []):
        if r.get("kind") not in ROAD_KINDS:
            continue
        pts = [((p[0] - ux0) / ucell, (p[1] - uz0) / ucell) for p in r["pts"]]
        if len(pts) >= 2:
            dr.line(pts, fill=1, width=2)
    road_dist = ndimage.distance_transform_edt(np.array(img) == 0) * ucell
    troad = road_dist[uiz, uix]

    # --- zápoj (hustota stromů v okolí) ---
    kd = cKDTree(np.stack([tx, tz], 1))
    cnt = np.array([len(a) for a in kd.query_ball_point(np.stack([tx, tz], 1), DENS_R)], float) - 1.0
    dens_full = max(float(np.percentile(cnt[tsurf == 3], DENS_FULL_PCT)) if (tsurf == 3).any() else 8.0, 2.0)
    closure = np.clip(cnt / dens_full, 0.0, 1.0)
    print(f"Zápoj: plný = {dens_full:.0f} sousedů do {DENS_R:.0f} m, medián zápoje {np.median(closure):.2f}")

    # --- Ellenbergovy hodnoty stanoviště ---
    insy_z = (insy - np.median(insy)) / max(np.std(insy), 1.0)
    twi_med = np.median(twi)
    site_L = 7.0 - 2.0 * closure       # stromy v zápoji dosáhnou na světlo korunou – L rozhoduje jen o zmlazení
    site_F = 5.0 + 0.55 * (twi - twi_med) + (awc - 120.0) / 80.0 - 0.6 * insy_z
    site_F += np.where((hand < LUH_HAND) & (disw < LUH_DISW), 2.5, 0.0)
    site_F += np.where(soil == 3, 1.5, 0.0)       # pseudoglej / glej
    site_F = np.clip(site_F, 1.0, 9.0)
    site_R = np.clip((ph - 3.5) * 2.2, 1.0, 9.0)
    site_N = np.clip(2.0 + 7.0 * nutr, 1.0, 9.0)
    site_T = T_REF - (elev + ELEV_ABS0 - T_REF_ELEV) * T_LAPSE / 1000.0 * 1.6 + 1.1 * insy_z - 1.5 * cpol
    site_T = np.clip(site_T, 1.0, 9.0)

    # --- vhodnost každého druhu pro každý strom (N × S) ---
    suit = np.zeros((N, S))
    for j, s in enumerate(cat):
        e, t = s["ellenberg"], s["tolerance"]
        dF = site_F - e["F"]
        sF = np.where(dF > 0, 1.2 + 2.8 * t["zamokreni"], 1.2 + 2.8 * t["sucho"])
        dL = site_L - e["L"]
        sL = np.where(dL < 0, 1.6 + 3.0 * t["stin"], 3.5)
        dT = site_T - e["T"]
        sT = np.where(dT < 0, 1.2 + 2.0 * t["mraz"], 2.0 + 1.5 * t["sucho"])
        q = (dF / sF) ** 2 + (dL / sL) ** 2 + (dT / sT) ** 2 + ((site_R - e["R"]) / 2.2) ** 2 + ((site_N - e["N"]) / 2.4) ** 2
        suit[:, j] = np.exp(-0.5 * q)
    suit = np.maximum(suit, 1e-4)

    # --- ortofoto jako nápověda ---
    lum = T[:, 7:10].mean(1)
    lz = np.zeros(N)
    for m in (conif, ~conif):
        if m.any():
            lz[m] = (lum[m] - np.median(lum[m])) / max(np.std(lum[m]), 1e-6)
    hint = np.ones((N, S))
    for k in ORTHO_DARK:
        hint[:, sidx[k]] *= np.exp(-ORTHO_HINT * np.clip(lz, -2, 2))
    for k in ORTHO_LIGHT:
        hint[:, sidx[k]] *= np.exp(ORTHO_HINT * np.clip(lz, -2, 2))

    # --- kontext stromu ---
    in_forest = (tsurf == 3) | (closure >= FOREST_DENS)
    is_luh = (hand < LUH_HAND) & (disw < LUH_DISW)
    is_sad = ((tsurf == 2) | (tlu == 3) | (tlu == 4)) & ~(tsurf == 3)
    is_obec = (tsurf == 4) & ~is_sad
    in_forest &= ~is_sad & ~is_obec
    is_alej = ~in_forest & ~is_sad & ~is_obec & (troad < ALEJ_ROAD_M)
    is_breh = ~in_forest & ~is_sad & ~is_obec & ~is_alej & ((tsurf == 5) | is_luh)
    is_pole = ~in_forest & ~is_sad & ~is_obec & ~is_alej & ~is_breh

    # --- porosty: Voronoi s deformací × třída stanoviště ---
    wx = tx + WARP_AMP * value_noise(tx, tz, WARP_SCALE, seed + 1)
    wz = tz + WARP_AMP * value_noise(tx, tz, WARP_SCALE, seed + 2)
    rng = np.random.default_rng(seed)
    gx = np.arange(tx.min() - POROST_SPACING, tx.max() + POROST_SPACING, POROST_SPACING)
    gz = np.arange(tz.min() - POROST_SPACING, tz.max() + POROST_SPACING, POROST_SPACING)
    SX, SZ = np.meshgrid(gx, gz)
    seeds = np.stack([SX.ravel(), SZ.ravel()], 1) + rng.uniform(-0.45, 0.45, (SX.size, 2)) * POROST_SPACING
    _, vor = cKDTree(seeds).query(np.stack([wx, wz], 1))
    # vyhlazené stanoviště → třída: 0 plošina/hřbet, 1 sever (chladný), 2 jih (teplý), 3 luh
    insy_s = lay("INSY", SITE_SMOOTH)[iz, ix]
    hand_s = lay("HAND", LUH_SMOOTH)[iz, ix]
    disw_s = lay("DISW", LUH_SMOOTH)[iz, ix]
    slope_s = lay("SLOP", SITE_SMOOTH)[iz, ix]
    iz_s = (insy_s - np.median(insy_s)) / max(np.std(insy_s), 1.0)
    sclass = np.where(slope_s < 4.0, 0, np.where(iz_s < -0.25, 1, np.where(iz_s > 0.25, 2, 0)))
    sclass = np.where((hand_s < LUH_HAND + 0.5) & (disw_s < LUH_DISW + 10.0), 3, sclass)
    stand_key = vor * 4 + sclass
    stand = np.full(N, 0xFFFF, np.int64)
    fidx = np.nonzero(in_forest)[0]
    uniq, inv = np.unique(stand_key[fidx], return_inverse=True)
    stand[fidx] = inv
    P = len(uniq)
    print(f"Porostů: {P}, stromů v lese {len(fidx)} ({100 * len(fidx) / N:.1f} %)")

    prior = np.array([s["podil_les"] for s in cat])
    conif_mean = conif[fidx].mean() if len(fidx) else 0.5
    comp = np.zeros((P, S))
    stand_type = []
    stand_sclass = np.zeros(P, int)
    for p in range(P):
        m = fidx[inv == p]
        stand_sclass[p] = sclass[m[0]]
        mean_suit = suit[m].mean(0)
        u = hash01(p, seed + 3)
        if stand_sclass[p] == 3:
            base = np.zeros(S)
            for k, v in STAND_TYPES["luh"].items():
                base[sidx[k]] = v
            wa = mean_suit * prior ** 2
            comp[p] = 0.7 * base + 0.3 * wa / max(wa.sum(), 1e-9)
            stand_type.append("luh")
            continue
        p_smrk = SMRK_P_BASE + (SMRK_P_NORTH if stand_sclass[p] == 1 else SMRK_P_SOUTH if stand_sclass[p] == 2 else 0.0)
        p_smrk += (conif[m].mean() - conif_mean) * SMRK_P_CONIF
        if u < p_smrk:
            base = np.zeros(S)
            for k, v in STAND_TYPES["smrcina"].items():
                base[sidx[k]] = v
            comp[p] = base
            stand_type.append("smrcina")
            continue
        # smíšený: 1–3 hlavní druhy podle vhodnosti × apriorního podílu
        w = mean_suit ** 2 * np.maximum(prior, 0.0)
        w[typ == 2] = 0.0
        order = np.argsort(-w)
        n_main = 1 + int(hash01(p, seed + 4) * 3)
        c = np.zeros(S)
        for r, j in enumerate(order[:n_main]):
            c[j] = w[j] * (1.6 if r == 0 else 1.0)
        # příměs: vhodnost × podíl² (hospodářsky běžné druhy – smrk – převáží vzácné, např. jedli)
        wa = mean_suit * np.maximum(prior, 0.0) ** 2
        c = c / max(c.sum(), 1e-9) * 0.85 + 0.15 * wa / max(wa.sum(), 1e-9)
        comp[p] = c
        stand_type.append("smiseny")

    # --- výběr druhu pro strom ---
    w = np.zeros((N, S))
    w[fidx] = comp[inv]
    ctx_flag = np.zeros(N, int)
    for name, mask, fl in (("sad", is_sad, FL_SAD), ("obec", is_obec, FL_OBEC), ("alej", is_alej, FL_ALEJ),
                           ("breh", is_breh, FL_SOLITER), ("pole", is_pole, FL_SOLITER)):
        base = np.zeros(S)
        for k, v in CONTEXT[name].items():
            base[sidx[k]] = v
        w[mask] = base
        ctx_flag[mask] |= fl
    ctx_flag[in_forest] |= FL_LES
    ctx_flag[in_forest & (closure < EDGE_DENS)] |= FL_OKRAJ
    ctx_flag[is_luh] |= FL_LUH
    w = w * suit ** SUIT_POW * hint
    allowed = np.where(conif[:, None], typ[None, :] == 1, typ[None, :] != 1)
    w = np.where(allowed, w, 0.0)
    # strom bez kandidáta (např. jehličnan v luhu bez jehličnanů v kompozici) → vhodnost × podíl v lese
    empty = w.sum(1) <= 1e-12
    if empty.any():
        fb = suit[empty] * np.where(allowed[empty], np.maximum(prior, 0.02)[None, :], 0.0)
        fb = np.where(typ[None, :] == 2, 0.0, fb)
        w[empty] = fb
    cw = np.cumsum(w, 1)
    u = hash01(np.arange(N), seed + 5) * cw[:, -1]
    sp = (cw < u[:, None]).sum(1)
    sp = np.clip(sp, 0, S - 1)

    # --- vitalita, věk, dbh ---
    s_suit = suit[np.arange(N), sp]
    depth_f = np.clip(sdep / 60.0, 0.5, 1.0)
    vig = np.clip(np.sqrt(s_suit / suit.max(1)) * depth_f * (0.85 + 0.3 * hash01(np.arange(N), seed + 6)), 0.05, 1.0)
    Hm = np.array([s["rust"]["H_max"] for s in cat])[sp]
    kk = np.array([s["rust"]["k"] for s in cat])[sp]
    pp = np.array([s["rust"]["p"] for s in cat])[sp]
    life = np.array([s["rust"]["doziti"] for s in cat])[sp]
    Hs = Hm * (0.6 + 0.4 * vig)
    ratio = np.clip(th / Hs, 0.02, 0.97)
    age_own = -np.log(1.0 - ratio ** (1.0 / pp)) / kk
    age_own = np.minimum(age_own, life)
    age = age_own.copy()
    if P > 0:
        med = np.zeros(P)
        sums = np.bincount(inv, weights=age_own[fidx], minlength=P)
        cnts = np.bincount(inv, minlength=P)
        med = sums / np.maximum(cnts, 1)
        jit = 1.0 + AGE_JITTER * (2.0 * hash01(fidx, seed + 7) - 1.0)
        age[fidx] = (AGE_STAND_W * med[inv] + (1.0 - AGE_STAND_W) * age_own[fidx]) * jit
    age = np.clip(np.round(age), 1, 255)
    na = np.array([s["naslund"][0] for s in cat])[sp]
    nb = np.array([s["naslund"][1] for s in cat])[sp]
    sq = np.sqrt(np.maximum(th - 1.3, 0.05))
    dbh = na * sq / np.maximum(1.0 - nb * sq, 0.08)
    dbh = np.where(in_forest, dbh, dbh * SOLITER_DBH)
    dbh = np.clip(dbh, 1.0, 180.0)

    dom_sp = sp.copy()
    if P:
        dom_sp[fidx] = comp.argmax(1)[inv]

    # --- mřížky pro běh: zápoj 16 m, dominantní druh a vitalita 32 m ---
    grids = []
    gx0, gz0 = sx0, sz0
    ext_x = snx * scell
    ext_z = snz * scell
    for code, cell in (("CANO", 16.0), ("DOMI", 32.0), ("VIGO", 32.0)):
        gnx, gnz = int(math.ceil(ext_x / cell)), int(math.ceil(ext_z / cell))
        gi = np.clip(((tx - gx0) / cell).astype(int), 0, gnx - 1)
        gj = np.clip(((tz - gz0) / cell).astype(int), 0, gnz - 1)
        flat = gj * gnx + gi
        if code == "CANO":
            # plocha korun (poloměr ~ 0,3 × výška, max 4,5 m – jako TreeDecor) / plocha buňky × korekce na nezachycené stromy
            cr = np.clip(0.3 * th, 1.5, 4.5)
            area = np.bincount(flat, weights=math.pi * cr * cr, minlength=gnx * gnz) * 1.6
            g = np.clip(area / (cell * cell), 0, 1)
            g = ndimage.uniform_filter(g.reshape(gnz, gnx), 3).ravel()
            data = np.round(g * 255).astype(np.uint8)
        elif code == "DOMI":
            # les: hlavní druh porostu (mapa ukazuje porosty, ne „sůl a pepř“ prototypů), mimo les vlastní druh
            cnt = np.zeros((gnx * gnz, S))
            np.add.at(cnt, (flat, dom_sp), 1.0)
            data = np.where(cnt.sum(1) > 0, cnt.argmax(1), 255).astype(np.uint8)
        else:
            sv = np.bincount(flat, weights=vig, minlength=gnx * gnz)
            sc = np.bincount(flat, minlength=gnx * gnz)
            data = np.where(sc > 0, np.round(sv / np.maximum(sc, 1) * 255), 0).astype(np.uint8)
        grids.append((code, gx0, gz0, cell, gnx, gnz, data))

    # --- zápis ---
    rec = np.zeros(N, dtype=[("sp", "u1"), ("age", "u1"), ("vig", "u1"), ("fl", "u1"), ("h", "<f2"), ("d", "<f2"),
                             ("st", "<u2"), ("res", "<u2")])
    rec["sp"] = sp
    rec["age"] = age.astype(np.uint8)
    rec["vig"] = np.round(vig * 255).astype(np.uint8)
    rec["fl"] = ctx_flag.astype(np.uint8)
    rec["h"] = th.astype(np.float16)
    rec["d"] = dbh.astype(np.float16)
    rec["st"] = stand.astype(np.uint16)
    with open(out_path, "wb") as f:
        f.write(b"TECO")
        f.write(struct.pack("<iiii", 1, N, 12, S))
        for k in ids:
            kb = k.encode("ascii")
            f.write(struct.pack("<B", len(kb)) + kb)
        f.write(struct.pack("<i", P))
        f.write(rec.tobytes())
        f.write(struct.pack("<i", len(grids)))
        for code, x0, z0, cell, gnx, gnz, data in grids:
            f.write(code.encode("ascii") + struct.pack("<3f2i", x0, z0, cell, gnx, gnz))
            f.write(data.tobytes())

    # --- statistika ---
    print(f"Zapsáno {out_path} ({os.path.getsize(out_path) / 1024:.0f} kB)")
    print("Podíly druhů (všechny stromy / jen les):")
    tot = np.bincount(sp, minlength=S)
    forest = np.bincount(sp[fidx], minlength=S)
    for j in np.argsort(-tot):
        if tot[j] == 0:
            continue
        print(f"  {cat[j]['nazev']:22s} {100 * tot[j] / N:5.1f} %   les {100 * forest[j] / max(len(fidx), 1):5.1f} %")
    st = np.array(stand_type)
    if P:
        cnts = np.bincount(inv, minlength=P)
        forest_ha = max((surf == 3).sum() * ucell * ucell / 10000.0, 1.0)
        ha = cnts / (len(fidx) / forest_ha)
        print(f"Porosty: smrčiny {np.mean(st == 'smrcina') * 100:.0f} %, smíšené {np.mean(st == 'smiseny') * 100:.0f} %, "
              f"luhy {np.mean(st == 'luh') * 100:.0f} %; stromů na porost medián {int(np.median(cnts))}, "
              f"odhad plochy medián {np.median(ha):.1f} ha")
    print(f"Kontext: les {in_forest.sum()}, sad/zahrada {is_sad.sum()}, zástavba {is_obec.sum()}, alej {is_alej.sum()}, "
          f"břeh {is_breh.sum()}, pole {is_pole.sum()}")
    print(f"Věk: medián {np.median(age):.0f} let (p10 {np.percentile(age, 10):.0f}, p90 {np.percentile(age, 90):.0f}); "
          f"vitalita medián {np.median(vig):.2f}; dbh medián {np.median(dbh):.0f} cm")
    # kontrola „Hotovo, když“: sever vs. jih, luh
    north = in_forest & (insy_z < -0.6)
    south = in_forest & (insy_z > 0.6)
    for name, m in (("severní svahy", north), ("jižní svahy", south), ("luh (u vody)", is_luh)):
        if m.sum() == 0:
            continue
        c = np.bincount(sp[m], minlength=S)
        top = np.argsort(-c)[:4]
        print(f"  {name:14s}: " + ", ".join(f"{cat[j]['nazev']} {100 * c[j] / m.sum():.0f} %" for j in top))
        c = np.bincount(dom_sp[m], minlength=S)
        top = np.argsort(-c)[:3]
        print(f"  {'':14s}  hlavní druh porostu: " + ", ".join(f"{cat[j]['nazev']} {100 * c[j] / m.sum():.0f} %" for j in top))
    sad_fruit = (typ[sp[is_sad]] == 2).mean() if is_sad.any() else 0.0
    print(f"  ovocné v sadech/zahradách: {100 * sad_fruit:.0f} % stromů; ovocné v lese: "
          f"{(typ[sp[fidx]] == 2).sum()} stromů")


if __name__ == "__main__":
    main()
