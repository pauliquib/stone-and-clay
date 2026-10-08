"""Mapa stanovišť (terén, voda, oslunění, půda) → data/site.bin. M8.2 (00_PRINCIPY §3, §8).

Co stanoviště určuje: hra z něj (M8.3+) odvozuje, co kde roste a žije – údolní niva u potoka je
vlhká a úrodná, jižní svah suchý a teplý, hřbet větrný a mělký. Vše se dopočítá tady offline
(00_PRINCIPY §1.3) a za běhu se jen čte z mřížky 4 m (`scripts/eko/site.gd`).

Zdroje (vše lokální, nic se nestahuje):
  data/terrain_height.bin  – výšková mřížka DMR 5G, 2 m/px (tools/export_map.py)
  data/water.json          – osy toků a nádrže (tools/water.py) – pro dist_water / hand / niva
  data/surface.bin         – třídy povrchu 4 m/px (tools/surface.py) – zástavba → antropozem
  data/landuse.bin         – orná půda (tools/landuse.py) – prohlubuje ornici
  data/map.json            – x0, z0, rozměr mřížky, north_angle_deg (azimut world −Z)

Model (podle čeho – 00_PRINCIPY §8 „Stanoviště" / „Půda"):
  sklon/orientace (aspect)  – z gradientu výšky; aspect = kompasní azimut směru po spádnici
                              (stejná transformace ENU→world jako `Clock.enu_to_world`, jen obráceně)
  TWI = ln(a / tan β)        – Beven & Kirkby (1979); `a` = D8 plošná akumulace odtoku na jednotku
                              šířky kontury (m), `β` = sklon (min. 0,5° proti dělení nulou)
  dist_water / HAND          – `scipy.ndimage.distance_transform_edt`; HAND zjednodušeně jako
                              elev(buňka) − elev(nejbližší buňka vody) (ne po skutečné spádnici –
                              zjednodušení, 00_PRINCIPY §1.1 – "jednodušší než realita, ne libovolný")
  TPI (topografická poloha)  – buňka − průměr okolí (100 m, 500 m; `uniform_filter`), určuje
                              údolí/svah/hřbet a zárodek mrazové kotliny a expozice větru
  insol (potenciální oslunění) – clear-sky model: sluneční vektor (stejné NOAA rovnice jako
                              `Clock.sun_enu`/`enu_to_world`) × cos(úhlu dopadu na svah), integrace
                              po hodinách pro 12 reprezentativních dnů (15. každého měsíce), vážené
                              počtem dnů v měsíci; TRANSMIT = jednoduchá propustnost atmosféry
                              (bez modelu zastínění terénem – M8.2 „Minimum")
  cold_pool                  – záporné TPI (500 m) + nízké HAND + nízká expozice větru
  půda                       – BPEJ geometrie pro katastr není k dispozici (docs/BPEJ.md: geoportál
                              SPÚ nedostupný, `data/bpej_meta.json.katastr_codes` je `null`) →
                              zjednodušené odvození z terénu/landuse podle české taxonomie
                              (pravidla v tabulce SOIL_RULES níže), `--soils=soubor.geojson`
                              zůstává jako nevyužitý hák pro budoucí reálná data (přepíše třídu a AWC)

Formát data/site.bin (little endian, self-popisný – nové vrstvy se dají přidat beze změny čtečky):
  4 B   magic "SITE"
  int32 verze (1)
  f32   x0, z0, cell (m)
  int32 nx, nz
  int32 počet vrstev L
  L × 16 B hlavička vrstvy: 4 B kód (ASCII), u8 typ (0=u8, 1=u16), 3 B padding, f32 scale, f32 offset
          reálná_hodnota = offset + raw * scale
  pak L datových bloků po řadě (každý nx*nz × 1 nebo 2 B), v pořadí z hlaviček.
  Vrstvy (kódy): ELEV, SLOP, ASPE, TWI_, DISW, HAND, TPI_, WEXP, INSY, INSW, CPOL, SOIL, SDEP, AWC_, PH__, NUTR

  python3 tools/site.py [--out=data/site.bin] [--soils=soubor.geojson]
"""
import datetime
import json
import math
import os
import struct
import sys

import numpy as np
from scipy import ndimage

HERE = os.path.dirname(os.path.abspath(__file__))
GAME = os.path.dirname(HERE)
DATA = os.path.join(GAME, "data")

SEED = 20261008          # deterministický seed (šum pro přirozené hranice půd)
CELL = 4.0                # mřížka stanoviště (m)
HCELL = 2.0               # mřížka terrain_height.bin (m)

LAT = 49.1                # shoduje se s Clock.LAT
LON = 17.6                # shoduje se s Clock.LON (přibližná fiktivní obec)

TRANSMIT = 0.75           # zjednodušená propustnost atmosféry (clear-sky), 00_PRINCIPY §8 „Obloha"
SOLAR_CONST = 1361.0      # W/m2, extraterestrické záření

MONTH_DAYS = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
WINTER_MONTHS = {11, 0, 1}   # prosinec, leden, únor (index 0 = leden)

# --- půdní třídy: index = SOIL, pravidla odvození z terénu/landuse (BPEJ geometrie chybí, docs/BPEJ.md) ---
HNEDOZEM, RANKER, ARENOSOL, GLEJ, FLUVIZEM, ANTROPOZEM = range(6)
SOIL_NAMES = ["hnědozem/kambizem", "ranker/litozem", "arenosol", "pseudoglej/glej", "fluvizem", "antropozem"]
# base_depth_cm, awc_mm_per_cm, ph_x10, nutr0..1 – typické hodnoty pro české půdy (zjednodušeně, bez BPEJ)
SOIL_PROPS = {
    HNEDOZEM:   {"depth": 60, "awc_cm": 2.2, "ph": 60, "nutr": 0.60},
    RANKER:     {"depth": 20, "awc_cm": 1.6, "ph": 65, "nutr": 0.30},
    ARENOSOL:   {"depth": 45, "awc_cm": 1.3, "ph": 55, "nutr": 0.25},
    GLEJ:       {"depth": 70, "awc_cm": 1.8, "ph": 55, "nutr": 0.50},
    FLUVIZEM:   {"depth": 100, "awc_cm": 2.4, "ph": 65, "nutr": 0.80},
    ANTROPOZEM: {"depth": 50, "awc_cm": 1.5, "ph": 70, "nutr": 0.40},
}
# SOIL_RULES (pořadí = priorita, první platné pravidlo vyhrává; "sum" = podmínka na poli, "noise" rozostří hranice):
SOIL_RULES_DOC = """
  1. zástavba/dvůr (surface==4)                              -> ANTROPOZEM
  2. niva: hand < 2 m a dist_water < 60 m                     -> FLUVIZEM
  3. vlhká deprese: twi > p80(twi)                            -> GLEJ
  4. prudký svah/hřbet: slope > 20 deg a tpi500 > 0            -> RANKER
  5. šum < ARENOSOL_FRAC v mírném, suchém, plochém terénu      -> ARENOSOL
  6. jinak                                                    -> HNEDOZEM
  (prahy + šum seedem SEED, aby hranice nebyly „šachovnice")
"""
ARENOSOL_FRAC = 0.12


def read_map_json():
    with open(os.path.join(DATA, "map.json"), "r", encoding="utf-8") as f:
        meta = json.load(f)
    return meta


def load_height(meta):
    h = meta["height"]
    w, hh = int(h["w"]), int(h["h"])
    arr = np.fromfile(os.path.join(DATA, "terrain_height.bin"), dtype=np.float32)
    if arr.size != w * hh:
        raise SystemExit("terrain_height.bin: neočekávaná velikost (%d != %d*%d)" % (arr.size, w, hh))
    return arr.reshape(hh, w), float(h["x0"]), float(h["z0"]), float(h["spacing"])


def downsample_mean(a, factor):
    hh, ww = a.shape
    hh2, ww2 = hh // factor * factor, ww // factor * factor
    a = a[:hh2, :ww2]
    return a.reshape(hh2 // factor, factor, ww2 // factor, factor).mean(axis=(1, 3))


def load_water_mask(x0, z0, cell, nx, nz):
    """Rastr 1 = voda (tok nebo nádrž) – pro dist_water / hand / rozpoznání nivy."""
    path = os.path.join(DATA, "water.json")
    mask = np.zeros((nz, nx), dtype=bool)
    if not os.path.exists(path):
        print("site.py: chybí data/water.json – dist_water/hand/niva bez vody (vše „daleko“)")
        return mask
    with open(path, "r", encoding="utf-8") as f:
        data = json.load(f)
    ix_max, iz_max = nx - 1, nz - 1
    for s in data.get("streams", []):
        pts = s.get("pts", [])
        half_w = max(1.0, {"river": 3.0, "canal": 1.6, "stream": 1.0, "ditch": 0.8, "drain": 0.8}
                     .get(s.get("kind", "stream"), 1.0))
        r = max(1, int(round(half_w / cell)))
        for p in pts:
            ix = int(round((p[0] - x0) / cell))
            iz = int(round((p[1] - z0) / cell))
            if 0 <= ix <= ix_max and 0 <= iz <= iz_max:
                mask[max(0, iz - r):min(nz, iz + r + 1), max(0, ix - r):min(nx, ix + r + 1)] = True
    for p in data.get("ponds", []):
        poly = p.get("poly", [])
        if len(poly) < 3:
            continue
        xs = [pt[0] for pt in poly]
        zs = [pt[1] for pt in poly]
        ix0 = max(0, int((min(xs) - x0) / cell) - 1)
        ix1 = min(nx, int((max(xs) - x0) / cell) + 2)
        iz0 = max(0, int((min(zs) - z0) / cell) - 1)
        iz1 = min(nz, int((max(zs) - z0) / cell) + 2)
        if ix1 <= ix0 or iz1 <= iz0:
            continue
        from PIL import Image, ImageDraw
        img = Image.new("1", (ix1 - ix0, iz1 - iz0), 0)
        draw = ImageDraw.Draw(img)
        draw.polygon([((pt[0] - x0) / cell - ix0, (pt[1] - z0) / cell - iz0) for pt in poly], fill=1)
        mask[iz0:iz1, ix0:ix1] |= np.array(img, dtype=bool)
    return mask


def load_class_grid(name, magic, x0, z0, cell, nx, nz):
    """Čte surface.bin / landuse.bin (stejný formát hlavičky, 1 nebo 2 B/buňka) a přemapuje na mřížku site."""
    path = os.path.join(DATA, name)
    if not os.path.exists(path):
        print("site.py: chybí data/%s – přeskakuji (ovlivní jen antropozem/ornici)" % name)
        return None
    b = np.fromfile(path, dtype=np.uint8)
    if b.size < 20 or bytes(b[:4]).decode("ascii", "ignore") != magic:
        print("site.py: %s neznámý formát" % name)
        return None
    sx0, sz0, scell = struct.unpack_from("<fff", b.tobytes(), 8)
    snx, snz = struct.unpack_from("<ii", b.tobytes(), 20)
    rec = 2 if magic == "LUSE" else 1
    body = b[28:28 + snx * snz * rec]
    if body.size < snx * snz * rec:
        print("site.py: %s useknutý" % name)
        return None
    cls = body.reshape(snz, snx, rec)[:, :, 0]
    # převzorkování na (x0,z0,cell,nx,nz) nejbližším sousedem (stejná orientace mřížky jako terrain_height)
    zz, xx = np.mgrid[0:nz, 0:nx]
    wx = x0 + xx * cell
    wz = z0 + zz * cell
    six = np.clip(np.round((wx - sx0) / scell).astype(np.int64), 0, snx - 1)
    siz = np.clip(np.round((wz - sz0) / scell).astype(np.int64), 0, snz - 1)
    return cls[siz, six]


def sun_world_vectors(north_deg):
    """12 reprezentativních dnů (15. každý měsíc) × hodina (6..18, krok 1 h) → (den_index, hod, vektor world [x,y,z], váha_dnů)."""
    out = []
    for mi in range(12):
        doy = sum(MONTH_DAYS[:mi]) + 15
        weight = MONTH_DAYS[mi]
        for h in range(0, 24):
            g = 2.0 * math.pi / 365.0 * (doy - 1 + (h - 1.0 - 12.0) / 24.0)   # tz = UTC+1 zjednodušeně
            eqt = 229.18 * (0.000075 + 0.001868 * math.cos(g) - 0.032077 * math.sin(g)
                             - 0.014615 * math.cos(2 * g) - 0.040849 * math.sin(2 * g))
            decl = (0.006918 - 0.399912 * math.cos(g) + 0.070257 * math.sin(g) - 0.006758 * math.cos(2 * g)
                    + 0.000907 * math.sin(2 * g) - 0.002697 * math.cos(3 * g) + 0.00148 * math.sin(3 * g))
            tst = h * 60.0 + eqt + 4.0 * LON - 60.0
            ha = math.radians(tst / 4.0 - 180.0)
            lat = math.radians(LAT)
            e = -math.cos(decl) * math.sin(ha)
            n = math.sin(decl) * math.cos(lat) - math.cos(decl) * math.cos(ha) * math.sin(lat)
            up = math.sin(decl) * math.sin(lat) + math.cos(decl) * math.cos(ha) * math.cos(lat)
            if up <= 0.0:
                continue
            # ENU -> world (stejná transformace jako Clock.enu_to_world)
            bearing = math.atan2(e, n)
            yaw = math.radians(north_deg) - bearing
            hl = math.hypot(e, n)
            wx = -math.sin(yaw) * hl
            wz = -math.cos(yaw) * hl
            out.append((mi, wx, up, wz, weight))
    return out


def compute_insolation(slope_normal, sun_vectors, winter_only_months):
    """MJ/m2 za rok (a zvlášť za zimu prosinec–únor) – součet clear-sky záření na svah po hodinách."""
    nz, nx = slope_normal[0].shape
    insol_year = np.zeros((nz, nx), dtype=np.float64)
    insol_winter = np.zeros((nz, nx), dtype=np.float64)
    nx_, ny_, nz_ = slope_normal
    for (mi, wx, wy, wz, weight) in sun_vectors:
        cos_i = nx_ * wx + ny_ * wy + nz_ * wz
        np.clip(cos_i, 0.0, None, out=cos_i)
        elev_sin = max(wy, 1e-3)
        irr = SOLAR_CONST * (TRANSMIT ** (1.0 / elev_sin)) * cos_i    # W/m2
        mj = irr * 3600.0 / 1.0e6 * weight                            # 1 h integrace, váha dnů v měsíci
        insol_year += mj
        if mi in winter_only_months:
            insol_winter += mj
    return insol_year, insol_winter


def d8_flow_acc(hm, cell):
    """Zjednodušená D8 akumulace plochy odtoku (m2/m šířky kontury) – cely řazené podle výšky sestupně,
    tok do nejnižšího ze 8 sousedů (sink = bez odtoku)."""
    nz, nx = hm.shape
    acc = np.ones((nz, nx), dtype=np.float64) * (cell * cell)   # vlastní plocha buňky
    flat = hm.ravel()
    order = np.argsort(-flat)                                   # od nejvyššího k nejnižšímu
    nbrs = [(-1, -1), (-1, 0), (-1, 1), (0, -1), (0, 1), (1, -1), (1, 0), (1, 1)]
    dist = [cell * math.sqrt(2), cell, cell * math.sqrt(2), cell, cell, cell * math.sqrt(2), cell, cell * math.sqrt(2)]
    acc_flat = acc.ravel()
    for idx in order:
        iz, ix = divmod(int(idx), nx)
        best_d = -1.0
        best_j = -1
        h0 = hm[iz, ix]
        for (dz, dx), dd in zip(nbrs, dist):
            jz, jx = iz + dz, ix + dx
            if 0 <= jz < nz and 0 <= jx < nx:
                drop = (h0 - hm[jz, jx]) / dd
                if drop > best_d:
                    best_d = drop
                    best_j = jz * nx + jx
        if best_j >= 0 and best_d > 0.0:
            acc_flat[best_j] += acc_flat[idx]
    return acc


def pack_layer(out, code, dtype_code, scale, offset, raw):
    assert len(code) == 4
    out.append((code.encode("ascii"), dtype_code, struct.pack("<ff", scale, offset), raw))


def quantize(values, dtype):
    """Vrátí (raw_array, scale, offset) tak, aby offset + raw*scale ~ values (min..max mapováno na celý rozsah)."""
    vmin = float(np.min(values))
    vmax = float(np.max(values))
    maxraw = 255 if dtype == np.uint8 else 65535
    if vmax <= vmin:
        scale = 1.0
    else:
        scale = (vmax - vmin) / maxraw
    raw = np.clip(np.round((values - vmin) / scale if scale > 0 else values * 0), 0, maxraw).astype(dtype)
    return raw, scale, vmin


def main():
    out_path = os.path.join(DATA, "site.bin")
    soils_geojson = None
    for a in sys.argv[1:]:
        if a.startswith("--out="):
            out_path = a.split("=", 1)[1]
        elif a.startswith("--soils="):
            soils_geojson = a.split("=", 1)[1]
    if soils_geojson:
        print("site.py: --soils=%s zadáno, ale reálná BPEJ geometrie pro katastr není k dispozici "
              "(docs/BPEJ.md) – ignoruji a používám terénní fallback." % soils_geojson)

    t0 = datetime.datetime.now()
    meta = read_map_json()
    north_deg = float(meta.get("north_angle_deg", 78.37))
    hm_full, hx0, hz0, hspacing = load_height(meta)
    print("site.py: terrain_height.bin %dx%d @ %.1f m" % (hm_full.shape[1], hm_full.shape[0], hspacing))

    factor = int(round(CELL / hspacing))
    hm = downsample_mean(hm_full, factor)
    nz, nx = hm.shape
    x0, z0 = hx0, hz0
    print("site.py: mřížka stanoviště %dx%d @ %.1f m (%.1f MB/vrstva u 1 B)" % (nx, nz, CELL, nx * nz / 1.0e6))

    # --- 1. výška, sklon, orientace (z gradientu, world x/z) ---
    gz, gx = np.gradient(hm, CELL)        # gz = dh/dz (řádky), gx = dh/dx (sloupce)
    normal = np.stack([-gx, np.ones_like(gx), -gz], axis=0)
    normal /= np.linalg.norm(normal, axis=0, keepdims=True)
    slope_deg = np.degrees(np.arccos(np.clip(normal[1], -1.0, 1.0)))
    # aspect: azimut směru po spádnici (dx,dz) = (gx,gz) (po spádu dolů = -gradient, ale aspect = odkud sklon „hledí“,
    # tj. směr maximálního klesání = -grad) – inverze Clock.enu_to_world
    down_x, down_z = -gx, -gz
    hl = np.hypot(down_x, down_z)
    hl_safe = np.where(hl < 1e-6, 1.0, hl)
    yaw = np.arctan2(-down_x / hl_safe, -down_z / hl_safe)
    aspect_deg = np.degrees(math.radians(north_deg) - yaw) % 360.0
    aspect_deg = np.where(hl < 1e-6, 0.0, aspect_deg)

    # --- 2. D8 akumulace a TWI ---
    print("site.py: D8 akumulace odtoku (%d buněk, může chvíli trvat)…" % (nx * nz))
    acc = d8_flow_acc(hm, CELL)
    slope_rad = np.radians(np.maximum(slope_deg, 0.5))
    twi = np.log(acc / np.tan(slope_rad))

    # --- 3. vzdálenost k vodě a HAND (zjednodušeně) ---
    water_mask = load_water_mask(x0, z0, CELL, nx, nz)
    if water_mask.any():
        dist_px, (near_z, near_x) = ndimage.distance_transform_edt(~water_mask, return_indices=True)
        dist_water = dist_px * CELL
        hand = np.maximum(0.0, hm - hm[near_z, near_x])
    else:
        dist_water = np.full((nz, nx), 9999.0)
        hand = np.full((nz, nx), 50.0)

    # --- 4. TPI a expozice větru (převládá západní proudění) ---
    r100 = max(1, int(round(100.0 / CELL)))
    r500 = max(1, int(round(500.0 / CELL)))
    tpi100 = hm - ndimage.uniform_filter(hm, size=2 * r100 + 1)
    tpi500 = hm - ndimage.uniform_filter(hm, size=2 * r500 + 1)
    tpi500n = np.clip(tpi500 / (np.std(tpi500) * 2.0 + 1e-6), -1.0, 1.0)
    west_bearing_rad = math.radians(270.0)
    aspect_rad = np.radians(aspect_deg)
    west_align = np.cos(aspect_rad - west_bearing_rad) * 0.5 + 0.5   # 1 = svah hledí na západ (do větru)
    wind_exp = np.clip(0.5 + 0.35 * tpi500n + 0.15 * (west_align - 0.5), 0.0, 1.0)

    # --- 5. oslunění (clear-sky, bez zastínění terénem – Minimum) ---
    print("site.py: integrace oslunění (12 dnů × hodiny)…")
    sun_vecs = sun_world_vectors(north_deg)
    insol_year, insol_winter = compute_insolation((normal[0], normal[1], normal[2]), sun_vecs, WINTER_MONTHS)

    # --- 6. mrazová kotlina ---
    cold_pool = np.clip(np.maximum(0.0, -tpi500n) * (1.0 - wind_exp) * np.clip(1.0 - hand / 10.0, 0.0, 1.0), 0.0, 1.0)

    # --- 7. půda (fallback bez BPEJ geometrie, 00_PRINCIPY §8 „Půda") ---
    surf_cls = load_class_grid("surface.bin", "SURF", x0, z0, CELL, nx, nz)
    luse_cls = load_class_grid("landuse.bin", "LUSE", x0, z0, CELL, nx, nz)
    rng = np.random.default_rng(SEED)
    noise = ndimage.gaussian_filter(rng.random((nz, nx)), sigma=max(1.0, 250.0 / CELL))
    noise = (noise - noise.min()) / (noise.max() - noise.min() + 1e-9)
    twi_p80 = np.percentile(twi, 80.0)

    soil = np.full((nz, nx), HNEDOZEM, dtype=np.uint8)
    niva = (hand < 2.0) & (dist_water < 60.0)
    deprese = (~niva) & (twi > twi_p80)
    hrbet = (~niva) & (~deprese) & (slope_deg > 20.0) & (tpi500 > 0.0)
    arenosol_zone = (~niva) & (~deprese) & (~hrbet) & (slope_deg < 8.0) & (twi < np.percentile(twi, 40.0)) \
        & (noise < ARENOSOL_FRAC)
    soil[niva] = FLUVIZEM
    soil[deprese] = GLEJ
    soil[hrbet] = RANKER
    soil[arenosol_zone] = ARENOSOL
    if surf_cls is not None:
        soil[surf_cls == 4] = ANTROPOZEM   # zástavba / dvůr

    soil_depth = np.zeros((nz, nx), dtype=np.float64)
    awc = np.zeros((nz, nx), dtype=np.float64)
    ph = np.zeros((nz, nx), dtype=np.float64)
    nutr = np.zeros((nz, nx), dtype=np.float64)
    for cls, props in SOIL_PROPS.items():
        m = soil == cls
        depth_var = (noise[m] - 0.5) * 20.0 if m.any() else 0.0
        soil_depth[m] = np.clip(props["depth"] + depth_var, 8, 150)
        ph[m] = np.clip(props["ph"] + (noise[m] - 0.5) * 10.0, 35, 85) if m.any() else props["ph"]
        nutr[m] = np.clip(props["nutr"] + (noise[m] - 0.5) * 0.2, 0.05, 0.95) if m.any() else props["nutr"]
        awc[m] = soil_depth[m] * props["awc_cm"]
    if luse_cls is not None:
        orna = luse_cls == 1
        soil_depth[orna] = np.clip(soil_depth[orna] + 15.0, 8, 150)
        nutr[orna] = np.clip(nutr[orna] + 0.08, 0.05, 0.95)

    # --- sestavení výstupu ---
    layers = []
    raw, scale, off = quantize(hm, np.uint16); pack_layer(layers, "ELEV", 1, scale, off, raw)
    raw, scale, off = quantize(slope_deg, np.uint8); pack_layer(layers, "SLOP", 0, scale, off, raw)
    raw = np.clip(np.round(aspect_deg / 360.0 * 255.0), 0, 255).astype(np.uint8)
    pack_layer(layers, "ASPE", 0, 360.0 / 255.0, 0.0, raw)
    raw, scale, off = quantize(twi, np.uint8); pack_layer(layers, "TWI_", 0, scale, off, raw)
    raw, scale, off = quantize(np.clip(dist_water, 0, 16000), np.uint16); pack_layer(layers, "DISW", 1, scale, off, raw)
    raw, scale, off = quantize(np.clip(hand, 0, 6000), np.uint16); pack_layer(layers, "HAND", 1, scale, off, raw)
    raw, scale, off = quantize(tpi500, np.uint8); pack_layer(layers, "TPI_", 0, scale, off, raw)
    raw = np.clip(np.round(wind_exp * 255.0), 0, 255).astype(np.uint8)
    pack_layer(layers, "WEXP", 0, 1.0 / 255.0, 0.0, raw)
    raw, scale, off = quantize(insol_year, np.uint16); pack_layer(layers, "INSY", 1, scale, off, raw)
    raw, scale, off = quantize(insol_winter, np.uint16); pack_layer(layers, "INSW", 1, scale, off, raw)
    raw = np.clip(np.round(cold_pool * 255.0), 0, 255).astype(np.uint8)
    pack_layer(layers, "CPOL", 0, 1.0 / 255.0, 0.0, raw)
    pack_layer(layers, "SOIL", 0, 1.0, 0.0, soil.astype(np.uint8))
    pack_layer(layers, "SDEP", 0, 1.0, 0.0, np.clip(np.round(soil_depth), 0, 255).astype(np.uint8))
    raw = np.clip(np.round(awc / 2.0), 0, 255).astype(np.uint8)
    pack_layer(layers, "AWC_", 0, 2.0, 0.0, raw)
    pack_layer(layers, "PH__", 0, 1.0, 0.0, np.clip(np.round(ph), 0, 255).astype(np.uint8))
    raw = np.clip(np.round(nutr * 255.0), 0, 255).astype(np.uint8)
    pack_layer(layers, "NUTR", 0, 1.0 / 255.0, 0.0, raw)

    with open(out_path, "wb") as f:
        f.write(b"SITE")
        f.write(struct.pack("<i", 1))
        f.write(struct.pack("<fff", x0, z0, CELL))
        f.write(struct.pack("<ii", nx, nz))
        f.write(struct.pack("<i", len(layers)))
        for code, dtype_code, scale_off, _raw in layers:
            f.write(code)
            f.write(struct.pack("<B", dtype_code))
            f.write(b"\x00\x00\x00")
            f.write(scale_off)
        for _code, _dtype_code, _scale_off, raw in layers:
            f.write(raw.tobytes())

    size_mb = os.path.getsize(out_path) / 1.0e6
    dt = (datetime.datetime.now() - t0).total_seconds()
    print("site.py: hotovo za %.1f s -> %s (%.1f MB, %d vrstev, %dx%d buněk)" % (dt, out_path, size_mb, len(layers), nx, nz))
    soil_counts = {SOIL_NAMES[c]: int(np.sum(soil == c)) for c in range(6)}
    total = nx * nz
    print("site.py: podíl půdních tříd: " + ", ".join(
        "%s %.1f%%" % (n, 100.0 * c / total) for n, c in soil_counts.items()))
    print("site.py: TWI rozsah %.2f..%.2f (medián %.2f)" % (float(np.min(twi)), float(np.max(twi)), float(np.median(twi))))
    south = aspect_deg > 135.0
    south &= aspect_deg < 225.0
    north = (aspect_deg < 45.0) | (aspect_deg > 315.0)
    if south.any() and north.any():
        print("site.py: průměrné oslunění – jižní svahy %.0f MJ/m2/rok, severní %.0f MJ/m2/rok" %
              (float(np.mean(insol_year[south])), float(np.mean(insol_year[north]))))


if __name__ == "__main__":
    main()
