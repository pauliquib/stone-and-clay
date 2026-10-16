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

M8.14 `--eco` (formát VEG2 = stejný záznam, magic "VEG2", verze 2; bez přepínače dál VEG1 beze změny):
  data/site.bin      – stanoviště M8.2 (TWI, vzdálenost k vodě, oslunění, hloubka a druh půdy, sklon)
  data/tree_eco.bin  – M8.3: mřížky CANO (zápoj, 16 m) a DOMI (dominantní druh, 32 m)
  typ louky: vlhká (TWI ≥ TWI_WET / blízko vody / glej, fluvizem) → HERB_WET (pcháč, kohoutek), suchá (oslunění
  z-skóre ≥ INSOL_DRY_Z a mělká půda / strmý svah / ranker) → HERB_DRY (šalvěj, mateřídouška), ruderální (u dvorů a cest)
  → víc kopřiv, jinak mezofilní (GRASS_TALL). Lesní podrost podle dominantního druhu nad buňkou a světla pod korunou
  (1 − zápoj): buk → hrabanka (LITTER) a skoro nic, smrk / jedle → jehličí, mech, borůvčí, kapradí, borovice / modřín
  → borůvčí a mech, dub / habr / lípa / javor → jarní podrost (SPRING_FLOWERS), olše / vrby a luh u vody → devětsil
  a kopřivy (BUTTERBUR). Nové typy: 7 HERB_WET, 8 HERB_DRY, 9 FERN, 10 BILBERRY, 11 MOSS, 12 SPRING_FLOWERS, 13 LITTER,
  14 BUTTERBUR (shodné s VegetationManager.VegType); rozpočet ECO_TARGET, celkem ≤ MAX_CAP_ECO (= MAX_CAP + 30 %).

Rozmístění je deterministické (SEED): stejné vstupy → stejný soubor. Hustoty se počítají jako
očekávaný počet na buňku 4×4 m a globálně se škálují na cílové počty TARGET – výstup drží
rozpočet bez ohledu na plochu ploch. Vegetace neroste na zástavbě (t. 4 + rozšíření 1 buňka),
v březích (t. 5), na polních cestách (t. 7), na vozovkách (asphalt/gravel rasterizace + 1 buňka)
a mimo katastr; u strmých svahů se řídí SLOPE_MAX.

  python3 tools/vegetation.py [--eco] [--year=RRRR] [--out=data/vegetation.bin] [--data=adresář vstupů]
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
DATA = os.path.join(GAME, "data")       # --data= přepíše (jen vstupy)

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

# --- M8.14 --eco: typy přízemní vegetace podle stanoviště a druhu stromu (shodné s VegetationManager.VegType) ---
HERB_WET, HERB_DRY, FERN, BILBERRY, MOSS, SPRING_FLOWERS, LITTER, BUTTERBUR = range(7, 15)
ECO_TYPES = [HERB_WET, HERB_DRY, FERN, BILBERRY, MOSS, SPRING_FLOWERS, LITTER, BUTTERBUR]
ECO_NAMES = {HERB_WET: "vlhká louka (pcháč)", HERB_DRY: "suchá stráň (šalvěj)", FERN: "kapradí", BILBERRY: "borůvčí",
             MOSS: "mech", SPRING_FLOWERS: "jarní podrost", LITTER: "hrabanka / jehličí", BUTTERBUR: "devětsil (luh)"}
ECO_TARGET = {HERB_WET: 6000, HERB_DRY: 6000, FERN: 3500, BILBERRY: 5000, MOSS: 4000, SPRING_FLOWERS: 5000,
              LITTER: 5000, BUTTERBUR: 1500}
MAX_CAP_ECO = int(MAX_CAP * 1.3)          # 00_PRINCIPY / prompt M8.14: celkem ≤ MAX_CAP + 30 %
TWI_WET = 10.0                             # shodně s Meadows (scripts/eko/meadows.gd)
DIST_WATER_WET = 15.0
TWI_WET_SOIL = 8.0                         # glej / fluvizem je vlhká louka od tohoto TWI
INSOL_MU, INSOL_SD = 5233.0, 623.0         # oslunění – z-skóre jako TreeEco.INSY_MED / INSY_STD
INSOL_DRY_Z = 0.5
SOIL_DRY_CM = 60.0
SLOPE_DRY_DEG = 8.0
SOIL_RANKER, SOIL_GLEJ, SOIL_FLUVIZEM = 1, 3, 4
LIGHT_MIN = 0.15                           # podrost i pod plným zápojem (×)
# skupiny dominantních dřevin (id z data/dreviny.json) → lesní podrost
GRP_BEECH = {"buk"}
GRP_SPRUCE = {"smrk", "jedle"}
GRP_PINE = {"borovice", "modrin"}
GRP_BROAD = {"dub_zimni", "dub_letni", "habr", "lipa", "javor_klen", "jasan", "tresen_ptaci", "orech"}
GRP_ALDER = {"olse", "vrba_bila", "jiva", "topol"}
GRP_NAMES = ["bez stromů", "buk", "smrk/jedle", "borovice/modřín", "listnaté (dub, habr, lípa…)", "olše/vrby (luh)", "ostatní"]
# podrost na buňku lesa při plném světle: skupina → {typ: λ}
UNDER = {
    1: {LITTER: 0.7},
    2: {LITTER: 0.35, MOSS: 0.5, BILBERRY: 0.35, FERN: 0.15},
    3: {BILBERRY: 0.55, MOSS: 0.25},
    4: {SPRING_FLOWERS: 0.7, FERN: 0.1},
    5: {BUTTERBUR: 0.6},
    6: {FERN: 0.1},
}
# tint hrabanky podle skupiny (násobí veg_lo/hi materiálu): buk – rezavé listí, smrk – tmavé jehličí
LITTER_TINT = {1: (1.15, 1.0, 0.9), 2: (0.72, 0.62, 0.55)}
ECO_TINT = {HERB_WET: ((0.95, 1.0, 0.95), 0.15), HERB_DRY: ((1.0, 1.0, 0.9), 0.15), FERN: ((0.9, 1.0, 0.9), 0.15),
            BILBERRY: ((0.9, 1.0, 0.9), 0.15), MOSS: ((0.9, 1.0, 0.85), 0.2), SPRING_FLOWERS: ((1.0, 1.0, 1.0), 0.1),
            LITTER: ((1.0, 1.0, 1.0), 0.12), BUTTERBUR: ((0.9, 1.0, 0.9), 0.12)}
ECO_SCALE = {HERB_WET: (0.75, 1.3), HERB_DRY: (0.7, 1.3), FERN: (0.7, 1.4), BILBERRY: (0.7, 1.3), MOSS: (0.7, 1.5),
             SPRING_FLOWERS: (0.8, 1.3), LITTER: (0.8, 1.6), BUTTERBUR: (0.8, 1.4)}
ECO_SLOPE = {HERB_WET: 30.0, HERB_DRY: 45.0, FERN: 50.0, BILBERRY: 50.0, MOSS: 55.0, SPRING_FLOWERS: 48.0,
             LITTER: 55.0, BUTTERBUR: 30.0}
TARGET.update(ECO_TARGET)
TINT.update(ECO_TINT)
SCALE.update(ECO_SCALE)
SLOPE_MAX.update(ECO_SLOPE)


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

    def __init__(self, year, eco=False):
        meta = json.load(open(os.path.join(DATA, "map.json")))
        hm = meta["height"]
        self.hx0 = float(hm["x0"])
        self.hz0 = float(hm["z0"])
        self.hs = float(hm["spacing"])
        self.hw = int(hm["w"])
        self.hh = int(hm["h"])
        self.year = year
        self.eco = eco
        self.rng = np.random.default_rng(SEED)
        self.records = {t: [] for t in TYPES + ECO_TYPES}

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
        if self.eco:
            self.eco_prepare()

    # ---------------------------------------------------------------- M8.14 --eco: stanoviště a dřeviny
    def _resample(self, x0, z0, cell, nx, nz, data):
        """Rastr (nz, nx) s vlastní mřížkou → hodnoty ve středech buněk surface (nejbližší buňka)."""
        cz, cx = np.mgrid[0:self.nz, 0:self.nx]
        wx = self.x0 + (cx + 0.5) * CELL
        wz = self.z0 + (cz + 0.5) * CELL
        ix = np.clip(((wx - x0) / cell).astype(np.int64), 0, nx - 1)
        iz = np.clip(((wz - z0) / cell).astype(np.int64), 0, nz - 1)
        return data[iz, ix]

    def eco_prepare(self):
        """Typ louky (vlhká / suchá / ruderální / mezofilní), dominantní dřevina, zápoj a světlo pod korunou."""
        nz, nx = self.nz, self.nx
        twi = np.full((nz, nx), 6.0)
        disw = np.full((nz, nx), 9999.0)
        insz = np.zeros((nz, nx))
        sdep = np.full((nz, nx), 50.0)
        soil = np.zeros((nz, nx), np.int64)
        slope = self.slope_deg
        sp = os.path.join(DATA, "site.bin")
        if os.path.exists(sp):
            b = open(sp, "rb").read()
            _v, sx0, sz0, scell, snx, snz, nl = struct.unpack("<i3f3i", b[4:32])
            hdrs = []
            off = 32
            for _ in range(nl):
                code = b[off:off + 4].decode("ascii")
                dt = b[off + 4]
                sc, of = struct.unpack("<ff", b[off + 8:off + 16])
                hdrs.append((code, dt, sc, of))
                off += 16
            lay = {}
            for code, dt, sc, of in hdrs:
                n = snx * snz
                if dt == 1:
                    raw = np.frombuffer(b, np.uint16, n, off).reshape(snz, snx)
                    off += n * 2
                else:
                    raw = np.frombuffer(b, np.uint8, n, off).reshape(snz, snx)
                    off += n
                lay[code] = of + raw.astype(np.float64) * sc

            def rs(code, default):
                if code not in lay:
                    return np.full((nz, nx), default)
                return self._resample(sx0, sz0, scell, snx, snz, lay[code])
            twi = rs("TWI_", 6.0)
            disw = rs("DISW", 9999.0)
            insz = (rs("INSY", INSOL_MU) - INSOL_MU) / INSOL_SD
            sdep = rs("SDEP", 50.0)
            soil = np.round(rs("SOIL", 0.0)).astype(np.int64)
            if "SLOP" in lay:
                slope = rs("SLOP", 0.0)
        else:
            print("POZOR: site.bin chybí – typy luk jen mezofilní (spusť tools/site.py)")
        wet = (twi >= TWI_WET) | (disw < DIST_WATER_WET) | (((soil == SOIL_GLEJ) | (soil == SOIL_FLUVIZEM)) & (twi >= TWI_WET_SOIL))
        dry = ~wet & (insz >= INSOL_DRY_Z) & ((sdep < SOIL_DRY_CM) | (slope > SLOPE_DRY_DEG) | (soil == SOIL_RANKER))
        ruderal = dilate(self.cls == 4, 3) | self.road | self.near_track
        self.kind = np.where(ruderal, 3, np.where(wet, 1, np.where(dry, 2, 0)))
        self.disw = disw
        # dřeviny: CANO (zápoj) a DOMI (dominantní druh) z tree_eco.bin
        self.group = np.zeros((nz, nx), np.int64)
        self.cano = np.zeros((nz, nx))
        tp = os.path.join(DATA, "tree_eco.bin")
        if os.path.exists(tp):
            b = open(tp, "rb").read()
            if b[:4] == b"TECO":
                _v, n, rsz, S = struct.unpack_from("<4i", b, 4)
                off = 20
                names = []
                for _ in range(S):
                    ln = b[off]
                    names.append(b[off + 1:off + 1 + ln].decode("ascii"))
                    off += 1 + ln
                off += 4                                  # počet porostů
                off += n * rsz
                ng = struct.unpack_from("<i", b, off)[0]
                off += 4
                grp_of = []
                for nm in names:
                    g = 6
                    for gi, st in ((1, GRP_BEECH), (2, GRP_SPRUCE), (3, GRP_PINE), (4, GRP_BROAD), (5, GRP_ALDER)):
                        if nm in st:
                            g = gi
                    grp_of.append(g)
                grp_of = np.array(grp_of + [0] * (256 - len(grp_of)), np.int64)
                grp_of[255] = 0
                for _ in range(ng):
                    code = b[off:off + 4].decode("ascii")
                    gx0, gz0, gcell = struct.unpack_from("<3f", b, off + 4)
                    gnx, gnz = struct.unpack_from("<2i", b, off + 16)
                    off += 24
                    data = np.frombuffer(b, np.uint8, gnx * gnz, off).reshape(gnz, gnx)
                    off += gnx * gnz
                    if code == "CANO":
                        self.cano = self._resample(gx0, gz0, gcell, gnx, gnz, data).astype(np.float64) / 255.0
                    elif code == "DOMI":
                        self.group = grp_of[self._resample(gx0, gz0, gcell, gnx, gnz, data).astype(np.int64)]
        else:
            print("POZOR: tree_eco.bin chybí – lesní podrost bez druhů (spusť tools/tree_species.py)")
        forest = self.cls == 3
        self.group = np.where(forest | (self.cano > 0.3), self.group, 0)
        self.group = np.where(forest & (self.group == 0), 6, self.group)
        self.light = np.clip(1.0 - self.cano * 0.85, LIGHT_MIN, 1.0)

    def eco_mul(self, typ):
        """Násobek hustoty starých typů podle stanoviště (jen --eco; jinak 1)."""
        one = np.ones((self.nz, self.nx))
        if not self.eco:
            return one
        k, g = self.kind, self.group
        if typ == GRASS_TALL:
            return np.where(k == 1, 0.45, np.where(k == 2, 0.4, np.where(k == 3, 0.8, 1.0)))
        if typ == NETTLE:          # pod bukem a smrkem skoro nic, v luhu a u dvorů víc
            return np.where(g == 1, 0.1, np.where(g == 2, 0.3, np.where(g == 5, 2.0, np.where(k == 3, 1.5, 1.0))))
        if typ == BUSH_HAZEL:
            return np.where(g == 1, 0.15, np.where(g == 2, 0.4, 1.0)) * self.light
        return one

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
    def emit_cells(self, typ, mask, lam, tint_map=None):
        """Emise na buňkách `mask`: `lam` = očekávaný počet na buňku (skalár nebo rastr).
        Součet se globálně škáluje na TARGET[typ]. `tint_map` (nz, nx, 3) volitelně násobí tint (M8.14)."""
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
        if typ in ECO_TYPES:
            aux = np.zeros(n, np.int32)          # číslo pole jen u plodin
        self._append(typ, x, z, aux, None if tint_map is None else tint_map[ciz, cix])

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
        if self.eco and typ in (NETTLE, BUSH_HAZEL):     # M8.14: pod bukem / smrkem podrost řídne
            pk = np.clip(self.eco_mul(typ)[ciz, cix], 0.0, 1.0)
            keep &= self.rng.random(x.size) < pk
        self._append(typ, x[keep], z[keep])

    def _append(self, typ, x, z, aux=None, tint_mul=None):
        x = np.asarray(x, np.float64)
        z = np.asarray(z, np.float64)
        n = x.size
        if n == 0:
            return
        y = self.height_at(x, z) - 0.03                 # mírně zapuštěné proti vlnám terénu
        if typ in (LITTER, MOSS):
            y = y + 0.05                                 # M8.14: ploché typy těsně nad terénem (jinak by zmizely v zemi)
        rot = self.rng.random(n) * math.tau
        lo, hi = SCALE[typ]
        sc = lo + self.rng.random(n) * (hi - lo)
        mid, jit = TINT[typ]
        tint = np.clip(np.asarray(mid)[None, :]
                       + (self.rng.random((n, 3)) * 2.0 - 1.0) * jit, 0.0, 1.0)
        if tint_mul is not None:
            tint = np.clip(tint * tint_mul, 0.0, 1.0)
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
        if self.eco:
            lam = lam * self.eco_mul(GRASS_TALL)
        self.emit_cells(GRASS_TALL, (cls == 0) & free, lam)

        # --- NETTLE: okraje polních cest, okraje lesa, podrost pod stromy
        nettle_mask = ~self.blocked_soft & (self.slope_deg <= SLOPE_MAX[NETTLE]) \
            & ((((cls == 0) | (cls == 2)) & self.near_track) | ((cls == 3) & self.forest_edge))
        if self.eco:            # M8.14: ruderální porost u dvorů a cest, olšiny; pod bukem a smrkem řídce
            nettle_mask = nettle_mask | (~self.blocked_soft & (self.slope_deg <= SLOPE_MAX[NETTLE])
                                         & (((cls == 0) & (self.kind == 3)) | ((cls == 3) & (self.group == 5))))
        self.emit_cells(NETTLE, nettle_mask, 0.55 * self.eco_mul(NETTLE) if self.eco else 0.55)
        self.emit_under_trees(NETTLE, 0.30, 1.0, 3.0, (3, 0))

        # --- BUSH_HAZEL: podrost v lese (pod korunami + řidce i na okrajích a mýtinách)
        self.emit_cells(BUSH_HAZEL, free & (cls == 3) & self.forest_edge
                        & (self.slope_deg <= SLOPE_MAX[BUSH_HAZEL]), 0.10 * self.eco_mul(BUSH_HAZEL) if self.eco else 0.10)
        self.emit_cells(BUSH_HAZEL, free & (cls == 3) & ~self.forest_edge
                        & (self.slope_deg <= SLOPE_MAX[BUSH_HAZEL]), 0.02 * self.eco_mul(BUSH_HAZEL) if self.eco else 0.02)
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

    def run_eco(self):
        """M8.14: louky podle stanoviště (vlhká / suchá) a lesní podrost podle dominantní dřeviny a světla."""
        cls = self.cls
        free = ~self.blocked
        gx, gz = np.meshgrid(np.arange(self.nx), np.arange(self.nz))
        patch = 0.5 + 0.5 * cell_noise(gx, gz, 23, 4.0)
        meadow = (cls == 0) & free
        self.emit_cells(HERB_WET, meadow & (self.kind == 1) & (self.slope_deg <= SLOPE_MAX[HERB_WET]), 0.9 * patch)
        self.emit_cells(HERB_DRY, meadow & (self.kind == 2) & (self.slope_deg <= SLOPE_MAX[HERB_DRY]), 1.0 * patch)
        forest = (cls == 3) & free
        lam = {t: np.zeros((self.nz, self.nx)) for t in ECO_TYPES}
        fpatch = 0.4 + 0.6 * cell_noise(gx, gz, 41, 3.0)
        for g, mix in UNDER.items():
            m = forest & (self.group == g)
            for t, l in mix.items():
                lam[t] += np.where(m, l * fpatch * (self.light if t != LITTER else 1.0), 0.0)
        # luh: les u vody (olše, vrby nebo cokoli do 30 m od toku) → devětsil
        lam[BUTTERBUR] += np.where(forest & (self.disw < 30.0), 0.4 * self.light, 0.0)
        tint = np.ones((self.nz, self.nx, 3))
        for g, tm in LITTER_TINT.items():
            tint[self.group == g] = tm
        for t in (FERN, BILBERRY, MOSS, SPRING_FLOWERS, LITTER, BUTTERBUR):
            m = forest & (self.slope_deg <= SLOPE_MAX[t])
            self.emit_cells(t, m, lam[t], tint if t == LITTER else None)

    def eco_stats(self):
        """Statistika pro log: typy luk (buňky louky) a skupiny dřevin (buňky lesa)."""
        meadow = (self.cls == 0) & self.inside
        kinds = ["mezofilní", "vlhká", "suchá", "ruderální"]
        out = ["Typy luk (buňky 4 m): " + ", ".join(
            f"{kinds[k]} {int(((self.kind == k) & meadow).sum())}" for k in range(4))]
        forest = (self.cls == 3) & self.inside
        out.append("Lesní podrost podle dřeviny (buňky): " + ", ".join(
            f"{GRP_NAMES[g]} {int(((self.group == g) & forest).sum())}" for g in range(1, 7)))
        out.append(f"Světlo pod korunou (les): průměr {float(self.light[forest].mean()) if forest.any() else 0.0:.2f}")
        return out

    def write(self, path, eco=False):
        types = TYPES + ECO_TYPES if eco else TYPES
        cap_all = MAX_CAP_ECO if eco else MAX_CAP
        # strop na typ (typ emitovaný ve více vlnách – podrost, řádky – může TARGET překročit)
        for t in types:
            recs = self.records[t]
            cap = int(TARGET[t] * 1.15)
            if len(recs) > cap:
                idx = sorted(self.rng.choice(len(recs), cap, replace=False))
                self.records[t] = [recs[i] for i in idx]
        total = sum(len(v) for v in self.records.values())
        if total > cap_all:                              # strop bezpečnosti – proporcionálně
            for t in types:
                recs = self.records[t]
                want = int(len(recs) * cap_all / total)
                if len(recs) > want:
                    idx = sorted(self.rng.choice(len(recs), want, replace=False))
                    self.records[t] = [recs[i] for i in idx]
            total = sum(len(v) for v in self.records.values())
        with open(path, "wb") as f:
            f.write(b"VEG2" if eco else b"VEG1")
            f.write(struct.pack("<2i", 2 if eco else 1, total))
            for t in types:
                for rec in self.records[t]:
                    f.write(struct.pack("<i5f4B", t, rec[0], rec[1], rec[2], rec[3], rec[4],
                                        rec[5], rec[6], rec[7], rec[8]))
        return total


def main():
    global DATA
    year = datetime.date.today().year
    out = None
    eco = False
    for a in sys.argv[1:]:
        if a.startswith("--year="):
            year = int(a.split("=", 1)[1])
        elif a.startswith("--out="):
            out = a.split("=", 1)[1]
        elif a.startswith("--data="):
            DATA = a.split("=", 1)[1]
        elif a == "--eco":
            eco = True
        elif a in ("-h", "--help"):
            print(__doc__)
            return
    if out is None:
        out = os.path.join(GAME, "data", "vegetation.bin")
    g = Gen(year, eco)
    g.run()
    if eco:
        g.run_eco()
    n = g.write(out, eco)
    print(f"Vegetace {year}{' (--eco, VEG2)' if eco else ''}: {n} instancí → {out} ({os.path.getsize(out) // 1024} kB)")
    for t in TYPES:
        print(f"  {t}: {NAMES[t]:20s} {len(g.records[t]):6d}")
    if eco:
        for t in ECO_TYPES:
            print(f"  {t}: {ECO_NAMES[t]:20s} {len(g.records[t]):6d}")
        for line in g.eco_stats():
            print("  " + line)
        print(f"  rozpočet: {n} / {MAX_CAP_ECO} (MAX_CAP {MAX_CAP} + 30 %)")


if __name__ == "__main__":
    main()
