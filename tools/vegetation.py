"""Body vegetace (vysoká tráva, kopřivy, keře, obilné řádky, plevel, zahrádkové rostliny)
→ data/vegetation.bin. Fáze 9 upgrade plánu (§9.2).

Zdroje (vše lokální):
  data/surface.bin          – třídy povrchu 4 m/px (tools/surface.py): 0 louka, 1 ornice, 2 sad/zahrada,
                              3 les, 4 zástavba, 5 břeh, 7 polní cesta
  data/landuse.bin          – využití ploch + číslo pole (tools/landuse.py): plodina pole se určí stejnou
                              hash funkcí jako Fields.crop_of (obilné řádky jen na polích s obilninou)
  data/trees.bin            – stromy (DBI1, 11 × f32): podrost se rozmisťuje pod koruny
  data/terrain_height.bin   – výšková mřížka DMR (+ data/water_carve.bin zahloubení koryt) → y instancí
  data/asphalt.bin, gravel.bin – vozovky (DBM1 trojúhelníky): rasterizují se do masky "bez vegetace"
  data/map.json             – obvod katastru (vegetace jen uvnitř)

Formát data/vegetation.bin (little endian):
  4 B   magic "VEG1"
  int32 verze (1)
  int32 počet záznamů N
  N × 28 B záznam:
    int32 typ (0 GRASS_TALL, 1 NETTLE, 2 BUSH_HAZEL, 3 BUSH_BLACKTHORN, 4 CROP_WHEAT,
               5 WEED_FIELD, 6 GARDEN_VEG – shodné s VegetationManager.VegType)
    f32 x, f32 y, f32 z   – světová poloha patky (y = terén, mírně zapuštěná)
    f32 rot               – rotace kolem osy Y (rad)
    f32 scale             – rovnoměrné měřítko
    u8 r, u8 g, u8 b      – tint instance (násobí vertexovou barvu modelu)
    u8 aux                – číslo pole (1–255) u plodin na orné půdě, jinak 0

Rozmístění je deterministické (SEED): stejné vstupy → stejný soubor. Hustoty se počítají jako
očekávaný počet na buňku 4×4 m a globálně se škálují na cílové počty TARGET – výstup drží
rozpočet bez ohledu na plochu ploch. Vegetace neroste na zástavbě (t. 4 + rozšíření 1 buňka),
v březích (t. 5), na polních cestách (t. 7), na vozovkách (asphalt/gravel rasterizace + 1 buňka)
a mimo katastr; u strmých svahů se řídí SLOPE_MAX.

  python3 tools/vegetation.py [--year=RRRR] [--out=data/vegetation.bin]
"""
import datetime
import json
import math
import os
import struct
import sys

import numpy as np
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
GAME = os.path.dirname(HERE)
DATA = os.path.join(GAME, "data")

SEED = 20240917          # deterministický seed celého generování
CELL = 4.0               # rastr surface/landuse (m)

# Typy (shodné s VegetationManager.VegType) a rozpočty instancí.
GRASS_TALL, NETTLE, BUSH_HAZEL, BUSH_BLACKTHORN, CROP_WHEAT, WEED_FIELD, GARDEN_VEG = range(7)
TYPES = [GRASS_TALL, NETTLE, BUSH_HAZEL, BUSH_BLACKTHORN, CROP_WHEAT, WEED_FIELD, GARDEN_VEG]
NAMES = ["tráva vysoká", "kopřivy", "lískové keře", "trnky", "obilí (klasy)", "plevel na poli", "zahrádky"]

TARGET = {               # cílové počty instancí (± binomická chyba)
    GRASS_TALL: 26000,      # louky – trsy v chomáčích (patchiness)
    NETTLE: 7000,           # okraje cest, okraje lesa, podrost
    BUSH_HAZEL: 5000,       # podrost v lese, hlavně pod korunami stromů
    BUSH_BLACKTHORN: 3500,  # meze polí a okraje polních cest
    CROP_WHEAT: 22000,      # řádky obilí (jen pole s obilninou daného roku)
    WEED_FIELD: 8000,       # plevel mezi řádky na celé orné půdě
    GARDEN_VEG: 4000,       # sady a zahrádky
}
MAX_CAP = 90000          # součet všech instancí – bezpečnostní strop souboru

SLOPE_MAX = {GRASS_TALL: 42.0, NETTLE: 45.0, BUSH_HAZEL: 48.0, BUSH_BLACKTHORN: 45.0,
             CROP_WHEAT: 18.0, WEED_FIELD: 25.0, GARDEN_VEG: 20.0}

ROW_M = 5.0              # rozteč řádků obilí (m)
ROW_W = 2.2              # šířka pásma řádku (m)
ROW_IN = 1.6             # průměrná vzdálenost trsů v řádku (m)

# tint instancí (násobí vertexové barvy): střed + rozptyl
TINT = {
    GRASS_TALL: ((0.95, 1.0, 0.85), 0.18),
    NETTLE: ((0.8, 1.0, 0.8), 0.15),
    BUSH_HAZEL: ((0.9, 1.05, 0.85), 0.2),
    BUSH_BLACKTHORN: ((0.75, 0.9, 0.75), 0.2),
    CROP_WHEAT: ((1.0, 1.0, 1.0), 0.12),
    WEED_FIELD: ((0.85, 1.0, 0.8), 0.2),
    GARDEN_VEG: ((0.95, 1.0, 0.9), 0.2),
}
SCALE = {GRASS_TALL: (0.7, 1.35), NETTLE: (0.7, 1.2), BUSH_HAZEL: (0.75, 1.5),
         BUSH_BLACKTHORN: (0.7, 1.4), CROP_WHEAT: (0.85, 1.25), WEED_FIELD: (0.8, 1.3),
         GARDEN_VEG: (0.7, 1.2)}

# Plodiny (kopie vah z scripts/priroda/fields.gd – pořadí je významné pro crop_of)
CROPS_W = [("psenice", 0.35), ("jecmen", 0.15), ("repka", 0.15), ("kukurice", 0.20),
           ("slunecnice", 0.05), ("picniny", 0.10)]
CEREALS = {"psenice", "jecmen"}        # 3D klasy jen pro obilniny


def _hash(a: int, b: int) -> int:
    """Stejná funkce jako Fields._hash (determinismus napříč nástrojem a hrou)."""
    h = ((a * 73856093) ^ (b * 19349663)) & 0x7fffffff
    h = ((h ^ (h >> 13)) * 1274126177) & 0x7fffffff
    return h ^ (h >> 16)


def crop_of(field_id: int, year: int) -> str:
    """Stejný osevní postup jako Fields.crop_of."""
    total = sum(w for _k, w in CROPS_W)
    r = float(_hash(field_id, year) % 10000) / 10000.0 * total
    acc = 0.0
    last = "psenice"
    for k, w in CROPS_W:
        acc += w
        last = k
        if r <= acc:
            break
    return last


def load_surface(path):
    b = open(path, "rb").read()
    if b[:4] != b"SURF":
        raise SystemExit("surface.bin: neznámý formát (spusť tools/surface.py)")
    x0, z0, cell = struct.unpack_from("<3f", b, 8)
    nx, nz = struct.unpack_from("<2i", b, 20)
    cls = np.frombuffer(b, np.uint8, nx * nz, 28).reshape(nz, nx).copy()
    return cls, x0, z0, cell


def load_landuse(path, nx, nz):
    b = open(path, "rb").read()
    if b[:4] != b"LUSE":
        return None, None
    d = np.frombuffer(b, np.uint8, nx * nz * 2, 28).reshape(nz, nx, 2)
    return d[..., 0].copy(), d[..., 1].copy()


def dilate(mask, r):
    """Kruhové rozšíření masky o r buněk (posunem; stejné jako ve surface.py)."""
    out = mask.copy()
    r2 = r * r + 1
    for dz in range(-r, r + 1):
        for dx in range(-r, r + 1):
            if dx * dx + dz * dz > r2:
                continue
            sh = np.zeros_like(mask)
            zs = slice(max(dz, 0), mask.shape[0] + min(dz, 0))
            zd = slice(max(-dz, 0), mask.shape[0] + min(-dz, 0))
            xs = slice(max(dx, 0), mask.shape[1] + min(dx, 0))
            xd = slice(max(-dx, 0), mask.shape[1] + min(-dx, 0))
            sh[zd, xd] = mask[zs, xs]
            out |= sh
    return out


def ring_mask(mask):
    """True tam, kde soused (8-okolí) patří do masky, ale buňka sama ne."""
    return dilate(mask, 1) & ~mask


def rasterize_roads(path, nx, nz, x0, z0, cell):
    """DBM1 trojúhelníky vozovek → maska buněk (PIL polygon nad rastrem)."""
    img = Image.new("L", (nx, nz), 0)
    d = ImageDraw.Draw(img)
    b = open(path, "rb").read()
    if b[:4] != b"DBM1":
        return np.zeros((nz, nx), bool)
    nch = struct.unpack_from("<i", b, 4)[0]
    off = 8
    for _c in range(nch):
        n = struct.unpack_from("<i", b, off)[0]
        off += 4
        pos = np.frombuffer(b, np.float32, n * 3, off).reshape(n, 3)
        off += n * 36                     # pozice + normály + barvy (3×12 B na vrchol)
        px = (pos[:, 0] - x0) / cell
        pz = (pos[:, 2] - z0) / cell
        for t in range(0, n - 2, 3):
            d.polygon([(px[t], pz[t]), (px[t + 1], pz[t + 1]), (px[t + 2], pz[t + 2])], fill=1)
    return np.array(img, bool)


def cell_noise(ix, iz, seed, period):
    """Hladký šum 0..1 na rastru buněk: hodnoty z hash v mřížce `period` buněk, bilineárně."""
    gx = ix / period
    gz = iz / period
    x0i = np.floor(gx).astype(np.int64)
    z0i = np.floor(gz).astype(np.int64)
    tx = gx - x0i
    tz = gz - z0i
    tx = tx * tx * (3.0 - 2.0 * tx)
    tz = tz * tz * (3.0 - 2.0 * tz)

    def h(i, j):
        v = (i * np.int64(73856093)) ^ (j * np.int64(19349663)) ^ np.int64(seed * 83492791)
        v = (v ^ (v >> np.int64(13))) * np.int64(1274126177)
        v = v ^ (v >> np.int64(16))
        return (v & np.int64(0x7fffffff)).astype(np.float64) / float(0x7fffffff)

    a = h(x0i, z0i)
    b = h(x0i + 1, z0i)
    c = h(x0i, z0i + 1)
    d = h(x0i + 1, z0i + 1)
    return a + (b - a) * tx + (c - a) * tz + (a - b - c + d) * tx * tz


class Gen:
    """Generátor: drží rastry, výšky, masky a sbírá záznamy s globálním rozpočtem."""

    def __init__(self, year):
        meta = json.load(open(os.path.join(DATA, "map.json")))
        hm = meta["height"]
        self.hx0 = float(hm["x0"])
        self.hz0 = float(hm["z0"])
        self.hs = float(hm["spacing"])
        self.hw = int(hm["w"])
        self.hh = int(hm["h"])
        self.year = year
        self.rng = np.random.default_rng(SEED)
        self.records = {t: [] for t in TYPES}

        self.cls, self.x0, self.z0, self.cell = load_surface(os.path.join(DATA, "surface.bin"))
        self.nz, self.nx = self.cls.shape
        self.lu, self.lu_id = load_landuse(os.path.join(DATA, "landuse.bin"), self.nx, self.nz)
        if self.lu is None:
            print("POZOR: landuse.bin chybí – pole se generují jen podle třídy povrchu")

        # výšky terénu (+ zahloubení koryt z water_carve.bin)
        h = np.fromfile(os.path.join(DATA, "terrain_height.bin"), np.float32)
        if h.size != self.hw * self.hh:
            raise SystemExit("terrain_height.bin: neočekávaná velikost")
        self.height = h.reshape(self.hh, self.hw)
        wc = os.path.join(DATA, "water_carve.bin")
        if os.path.exists(wc):
            b = open(wc, "rb").read()
            if b[:4] == b"DBW1":
                n = struct.unpack_from("<i", b, 4)[0]
                idx = np.frombuffer(b, np.int32, n, 8)
                hv = np.frombuffer(b, np.float32, n, 8 + n * 4)
                self.height.flat[idx] = hv

        # maska katastru
        bpoly = [(float(p[0]), float(p[1])) for p in meta["boundary"]]
        bm = Image.new("L", (self.nx, self.nz), 0)
        ImageDraw.Draw(bm).polygon(
            [((x - self.x0) / CELL, (z - self.z0) / CELL) for x, z in bpoly], fill=1)
        self.inside = np.array(bm, bool)

        # maska vozovek (asphalt + gravel trojúhelníky)
        roads = rasterize_roads(os.path.join(DATA, "asphalt.bin"), self.nx, self.nz, self.x0, self.z0, CELL)
        roads |= rasterize_roads(os.path.join(DATA, "gravel.bin"), self.nx, self.nz, self.x0, self.z0, CELL)
        self.road = dilate(roads, 1)

        # blokované buňky: strict = + rozšiřující pás kolem zástavby; soft = jen samotné buňky
        # (kopřivy a zahrádkové rostliny rostou i těsně u domů)
        blocked_core = (self.cls == 4) | (self.cls == 5) | (self.cls == 7) | self.road | ~self.inside
        self.blocked = dilate(self.cls == 4, 1) | (self.cls == 5) | (self.cls == 7) \
            | self.road | ~self.inside
        self.blocked_soft = blocked_core

        # sklon na rastru buněk (středové diference výšek)
        hc = self.height_at_cells()
        gz, gx = np.gradient(hc, CELL)
        self.slope_deg = np.degrees(np.arctan(np.hypot(gx, gz)))

        # les – hrany (lesní buňky sousedící s nelesem uvnitř katastru) a vnitřek;
        # pásma kolem polních cest, mezí polí/luk a dvorů (zahrádky u domů)
        forest = self.cls == 3
        self.forest_edge = forest & dilate(~forest & self.inside, 1)
        self.near_track = ring_mask(self.cls == 7)
        self.near_arable = ring_mask(self.cls == 1)      # buňky sousedící s ornou půdou
        self.arable_edge = ring_mask(self.cls == 0)      # buňky sousedící s loukou
        self.near_yard = dilate(self.cls == 4, 2) & (self.cls == 0)   # trávník/zahrada u dvora

    # ---------------------------------------------------------------- výšky
    def height_at(self, x, z):
        """Bilineární výška terénu (stejná interpolace jako Terrain.height_at)."""
        x = np.asarray(x, np.float64)
        z = np.asarray(z, np.float64)
        fx = np.clip((x - self.hx0) / self.hs, 0, self.hw - 1.001)
        fz = np.clip((z - self.hz0) / self.hs, 0, self.hh - 1.001)
        ix = fx.astype(np.int64)
        iz = fz.astype(np.int64)
        tx = fx - ix
        tz = fz - iz
        i = iz * self.hw + ix
        hf = self.height.flat
        a = hf[i]
        b = hf[i + 1]
        c = hf[i + self.hw]
        d = hf[i + self.hw + 1]
        return a + (b - a) * tx + (c - a) * tz + (a - b - c + d) * tx * tz

    def height_at_cells(self):
        yy, xx = np.mgrid[0:self.nz, 0:self.nx]
        return self.height_at(self.x0 + (xx + 0.5) * CELL, self.z0 + (yy + 0.5) * CELL)

    # ---------------------------------------------------------------- emise
    def emit_cells(self, typ, mask, lam):
        """Emise na buňkách `mask`: `lam` = očekávaný počet na buňku (skalár nebo rastr).
        Součet se globálně škáluje na TARGET[typ]."""
        lam = np.asarray(lam, np.float64)
        if lam.ndim == 0:
            lam = np.full((self.nz, self.nx), float(lam))
        lam = np.where(mask, lam, 0.0)
        total = float(lam.sum())
        if total <= 0.0:
            return
        lam = lam * min(1.0, TARGET[typ] / total)
        base = np.floor(lam).astype(np.int64)
        extra = self.rng.random(lam.shape) < (lam - base)
        k = (base + extra.astype(np.int64))
        kk = k[k > 0]
        ciz, cix = np.nonzero(k)
        cix = np.repeat(cix, kk)
        ciz = np.repeat(ciz, kk)
        n = cix.size
        if n == 0:
            return
        x = self.x0 + (cix + self.rng.random(n)) * CELL
        z = self.z0 + (ciz + self.rng.random(n)) * CELL
        aux = self.lu_id[ciz, cix].astype(np.int32) if self.lu_id is not None else np.zeros(n, np.int32)
        self._append(typ, x, z, aux)

    def emit_rows(self, typ, mask, field_id_img):
        """Obilí v řádcích: orientace řádku podle čísla pole (stejný hash jako směr rýh
        v Fields.lut_image), rozteč ROW_M, trsy po ~ROW_IN metrech s jitterem."""
        cells = np.argwhere(mask)
        if cells.size == 0:
            return
        # 1. průchod: kolik řádků protíná buňky → škála na TARGET
        seg_per_cell = []
        for iz, ix in cells:
            fid = int(field_id_img[iz, ix])
            direction = _hash(max(fid, 1), 3) % 2       # 0 = řádky podél osy x
            cz0 = self.z0 + iz * CELL
            cx0 = self.x0 + ix * CELL
            v0, v1 = (cz0, cz0 + CELL) if direction == 0 else (cx0, cx0 + CELL)
            r0 = int(math.floor(v0 / ROW_M))
            seg = 0
            for r in range(r0, r0 + 3):
                vc = (r + 0.5) * ROW_M
                if v0 - 0.5 <= vc <= v1 + 0.5:
                    seg += 1
            seg_per_cell.append((iz, ix, fid, direction, seg))
        est = sum(s[4] for s in seg_per_cell) * (CELL / ROW_IN)
        if est <= 0.0:
            return
        k_scale = min(1.0, TARGET[typ] / est)
        xs, zs, fs = [], [], []
        for iz, ix, fid, direction, seg in seg_per_cell:
            if seg == 0:
                continue
            cx0 = self.x0 + ix * CELL
            cz0 = self.z0 + iz * CELL
            u0, u1 = (cx0, cx0 + CELL) if direction == 0 else (cz0, cz0 + CELL)
            v0, v1 = (cz0, cz0 + CELL) if direction == 0 else (cx0, cx0 + CELL)
            r0 = int(math.floor(v0 / ROW_M))
            for r in range(r0, r0 + 3):
                vc = (r + 0.5) * ROW_M
                if vc < v0 - 0.5 or vc > v1 + 0.5:
                    continue
                lam_row = (u1 - u0) / ROW_IN * k_scale
                k = int(lam_row) + (1 if self.rng.random() < lam_row - int(lam_row) else 0)
                for _i in range(k):
                    u = u0 + self.rng.random() * (u1 - u0)
                    v = vc + (self.rng.random() * 2.0 - 1.0) * ROW_W * 0.5
                    xx, zz = (u, v) if direction == 0 else (v, u)
                    xs.append(xx)
                    zs.append(zz)
                    fs.append(fid)
        if not xs:
            return
        self._append(typ, np.array(xs), np.array(zs), np.array(fs, np.int32))

    def emit_under_trees(self, typ, p_tree, r_min, r_max, cls_ok):
        """Podrost pod stromy: u části stromů (p_tree) jeden trs v pásu r_min..r_max od kmene,
        jen když cílová buňka je povolené třídy `cls_ok` a není blokovaná."""
        tb = open(os.path.join(DATA, "trees.bin"), "rb").read()
        if tb[:4] != b"DBI1":
            return
        n = struct.unpack_from("<i", tb, 4)[0]
        d = np.frombuffer(tb, np.float32, n * 11, 8).reshape(n, 11)
        sel = self.rng.random(n) < p_tree
        idx = np.nonzero(sel)[0]
        ang = self.rng.random(idx.size) * math.tau
        rr = r_min + self.rng.random(idx.size) * (r_max - r_min)
        x = d[idx, 0] + np.cos(ang) * rr
        z = d[idx, 2] + np.sin(ang) * rr
        cix = np.floor((x - self.x0) / CELL).astype(np.int64)
        ciz = np.floor((z - self.z0) / CELL).astype(np.int64)
        ok = (cix >= 0) & (ciz >= 0) & (cix < self.nx) & (ciz < self.nz)
        x, z, cix, ciz = x[ok], z[ok], cix[ok], ciz[ok]
        keep = np.zeros(x.size, bool)
        for i in range(x.size):
            c = int(self.cls[ciz[i], cix[i]])
            keep[i] = (c in cls_ok) and not self.blocked[ciz[i], cix[i]]
        self._append(typ, x[keep], z[keep])

    def _append(self, typ, x, z, aux=None):
        x = np.asarray(x, np.float64)
        z = np.asarray(z, np.float64)
        n = x.size
        if n == 0:
            return
        y = self.height_at(x, z) - 0.03                 # mírně zapuštěné proti vlnám terénu
        rot = self.rng.random(n) * math.tau
        lo, hi = SCALE[typ]
        sc = lo + self.rng.random(n) * (hi - lo)
        mid, jit = TINT[typ]
        tint = np.clip(np.asarray(mid)[None, :]
                       + (self.rng.random((n, 3)) * 2.0 - 1.0) * jit, 0.0, 1.0)
        rgb = np.clip(tint * 255.0, 0.0, 255.0).astype(np.uint8)   # >255 by v u8 přeteklo
        if aux is None:
            aux = np.zeros(n, np.int32)
        recs = self.records[typ]
        for i in range(n):
            recs.append((float(x[i]), float(y[i]), float(z[i]), float(rot[i]), float(sc[i]),
                         int(rgb[i, 0]), int(rgb[i, 1]), int(rgb[i, 2]), int(aux[i])))

    # ---------------------------------------------------------------- hlavní
    def run(self):
        cls = self.cls
        free = ~self.blocked
        gx, gz = np.meshgrid(np.arange(self.nx), np.arange(self.nz))   # (nz, nx)

        # --- GRASS_TALL: louky v chomáčích (patchiness ze 2 oktáv šumu)
        patch = 0.65 * cell_noise(gx, gz, 11, 6.0) + 0.35 * cell_noise(gx, gz, 77, 2.5)
        lam = np.clip((patch - 0.55) / 0.45, 0.0, 1.0) * 1.6
        lam *= (self.slope_deg <= SLOPE_MAX[GRASS_TALL])
        self.emit_cells(GRASS_TALL, (cls == 0) & free, lam)

        # --- NETTLE: okraje polních cest, okraje lesa, podrost pod stromy
        self.emit_cells(NETTLE,
                        ~self.blocked_soft & (self.slope_deg <= SLOPE_MAX[NETTLE])
                        & ((((cls == 0) | (cls == 2)) & self.near_track)
                           | ((cls == 3) & self.forest_edge)), 0.55)
        self.emit_under_trees(NETTLE, 0.30, 1.0, 3.0, (3, 0))

        # --- BUSH_HAZEL: podrost v lese (pod korunami + řidce i na okrajích a mýtinách)
        self.emit_cells(BUSH_HAZEL, free & (cls == 3) & self.forest_edge
                        & (self.slope_deg <= SLOPE_MAX[BUSH_HAZEL]), 0.10)
        self.emit_cells(BUSH_HAZEL, free & (cls == 3) & ~self.forest_edge
                        & (self.slope_deg <= SLOPE_MAX[BUSH_HAZEL]), 0.02)
        self.emit_under_trees(BUSH_HAZEL, 0.30, 1.4, 4.5, (3,))

        # --- BUSH_BLACKTHORN: meze polí (obě strany hrany ornice/louky) a okraje polních cest
        self.emit_cells(BUSH_BLACKTHORN,
                        ~self.blocked_soft & (self.slope_deg <= SLOPE_MAX[BUSH_BLACKTHORN])
                        & ((((cls == 0) | (cls == 2)) & (self.near_track | self.near_arable))
                           | ((cls == 1) & (self.near_track | self.arable_edge))), 0.5)

        # --- CROP_WHEAT: řádky jen na polích, kde daný rok roste obilnina
        wheat_mask = free & (cls == 1) & (self.slope_deg <= SLOPE_MAX[CROP_WHEAT])
        if self.lu is not None:
            fid = self.lu_id
            ids = np.unique(fid[wheat_mask & (fid > 0)])
            cereal_ids = [int(i) for i in ids if crop_of(int(i), self.year) in CEREALS]
            cereal = np.isin(fid, cereal_ids)
            print(f"Obilninová pole {self.year}: {len(cereal_ids)}/{len(ids)} polí, "
                  f"{int((wheat_mask & cereal).sum())} buněk")
            self.emit_rows(CROP_WHEAT, wheat_mask & cereal, fid)
        else:
            self.emit_rows(CROP_WHEAT, wheat_mask, np.zeros((self.nz, self.nx), np.uint8))

        # --- WEED_FIELD: řidčí plevel po celé orné půdě (s číslem pole)
        self.emit_cells(WEED_FIELD,
                        free & (cls == 1) & (self.slope_deg <= SLOPE_MAX[WEED_FIELD]), 0.35)

        # --- GARDEN_VEG: sady a zahrádky (třída 2 je v datech skoro celá mimo katastr) –
        #     proto hlavně trávníky a zahrádky v pásu ~8 m kolem dvorů; u domů měkký zákaz.
        gmask = ~self.blocked_soft & (cls == 2) & (self.slope_deg <= SLOPE_MAX[GARDEN_VEG])
        self.emit_cells(GARDEN_VEG, gmask, 0.5)
        self.emit_cells(GARDEN_VEG, ~self.blocked_soft & self.near_yard
                        & (self.slope_deg <= SLOPE_MAX[GARDEN_VEG]), 0.8)
        if self.lu is not None:
            self.emit_cells(GARDEN_VEG, ~self.blocked_soft & (self.lu == 4)
                            & (self.slope_deg <= SLOPE_MAX[GARDEN_VEG]), 1.2)

    def write(self, path):
        # strop na typ (typ emitovaný ve více vlnách – podrost, řádky – může TARGET překročit)
        for t in TYPES:
            recs = self.records[t]
            cap = int(TARGET[t] * 1.15)
            if len(recs) > cap:
                idx = sorted(self.rng.choice(len(recs), cap, replace=False))
                self.records[t] = [recs[i] for i in idx]
        total = sum(len(v) for v in self.records.values())
        if total > MAX_CAP:                              # strop bezpečnosti – proporcionálně
            for t in TYPES:
                recs = self.records[t]
                want = int(len(recs) * MAX_CAP / total)
                if len(recs) > want:
                    idx = sorted(self.rng.choice(len(recs), want, replace=False))
                    self.records[t] = [recs[i] for i in idx]
            total = sum(len(v) for v in self.records.values())
        with open(path, "wb") as f:
            f.write(b"VEG1")
            f.write(struct.pack("<2i", 1, total))
            for t in TYPES:
                for rec in self.records[t]:
                    f.write(struct.pack("<i5f4B", t, rec[0], rec[1], rec[2], rec[3], rec[4],
                                        rec[5], rec[6], rec[7], rec[8]))
        return total


def main():
    year = datetime.date.today().year
    out = os.path.join(DATA, "vegetation.bin")
    for a in sys.argv[1:]:
        if a.startswith("--year="):
            year = int(a.split("=", 1)[1])
        elif a.startswith("--out="):
            out = a.split("=", 1)[1]
    g = Gen(year)
    g.run()
    n = g.write(out)
    print(f"Vegetace {year}: {n} instancí → {out} ({os.path.getsize(out) // 1024} kB)")
    for t in TYPES:
        print(f"  {t}: {NAMES[t]:20s} {len(g.records[t]):6d}")


if __name__ == "__main__":
    main()
