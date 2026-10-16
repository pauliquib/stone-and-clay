"""Procedurální textury stromů (M8.8): atlas listí / jehličí a atlas kůry – dlaždice TILE² px na tvar.

Vše vlastní výroba (numpy + Pillow), nic se nestahuje. Deterministické (seed z čísla dlaždice).

Listí (karty trsů): silueta listu podle druhu (buk vejčitý, dub laločnatý, habr pilovitý, bříza trojúhelníkovitá,
olše okrouhlá, jabloň oválná) na větvičce, jehličnany „větvičkové“ karty (smrk hustý vějíř krátkých jehlic, borovice
štětky dlouhých jehlic). Pata větvičky je dole uprostřed dlaždice (UV v = 1), špička nahoře (v = 0).
Barva listí je TÉMĚŘ ŠEDÁ (jas + jemný odstín) – zelenou dodá shader (odstín instance × fenologie), textura nese jen
kresbu (žilky, světlé/tmavé listy). Průměrný jas krytých pixelů se normalizuje na LEAF_MEAN (shader dělí stejnou
konstantou). RGB průhledných pixelů se „rozlije“ z nejbližšího krytého (mipmapy bez tmavých lemů).

Kůra: periodický šum (FFT filtr → dlaždice navazuje sama na sebe) podle motivu: buk hladký šedý, dub brázditý,
habr žebrovaný, bříza bílá s černými pásky, olše tmavá, jabloň šupinatá, smrk červenohnědý šupinatý,
borovice oranžové šupiny / plotny. Barva kůry je skutečná (shader ji jen stíní okluzí).
"""
import math

import numpy as np
from PIL import Image, ImageDraw, ImageFilter
from scipy import ndimage

TILE = 512                 # px dlaždice ve výsledném atlasu
SS = 2                     # supersampling kresby listí
LEAF_MEAN = 0.62           # průměrný jas listí v atlasu (shodně s TG_LEAF_MEAN v shaders/include/tree_gen.gdshaderinc)


# ------------------------------------------------------------------ tvary listů (obrys v jednotkách délky listu)

def _leaf_outline(kind, rng):
    """Obrys listu: body (x, y), y = 0 u řapíku, y = 1 špička, x = šířka (symetricky)."""
    n = 28
    t = np.linspace(0.0, 1.0, n)
    if kind == "vejcity":            # buk: vejčitý, zvlněný okraj
        w = 0.36 * np.sin(np.pi * t ** 0.8) * (1.0 + 0.05 * np.sin(t * 40.0))
    elif kind == "lalocnaty":        # dub: 4–5 laloků na každé straně
        w = 0.30 * np.sin(np.pi * t ** 0.9) * (0.62 + 0.38 * np.abs(np.sin(t * np.pi * 4.5))) + 0.04
        w[0] = 0.02
    elif kind == "pilovity":         # habr: protáhlý, pilovitý okraj
        w = 0.27 * np.sin(np.pi * t ** 0.85) * (1.0 + 0.09 * ((t * 22.0) % 1.0))
    elif kind == "trojuhelnik":      # bříza: trojúhelníkovitě vejčitý (široký u báze), dvojitě pilovitý
        w = 0.42 * np.clip(1.0 - t, 0.0, 1.0) ** 1.1 * np.clip(t * 4.0, 0.0, 1.0) ** 0.5 * (1.0 + 0.07 * ((t * 16.0) % 1.0))
    elif kind == "okrouhly":         # olše: obvejčitý, tupá / vykrojená špička
        w = 0.42 * np.sin(np.pi * np.clip(t * 0.92, 0, 1) ** 1.25)
        w[-1] = 0.08
    else:                            # "ovalny" – jabloň
        w = 0.3 * np.sin(np.pi * t ** 0.95)
    w = np.maximum(w, 0.0) * (0.9 + 0.2 * rng.random())
    right = np.stack([w, t], 1)
    left = np.stack([-w[::-1], t[::-1]], 1)
    return np.concatenate([right, left], 0)


def _draw_leaf(dr, base, ang, length, kind, lum, rng):
    """Jeden list: řapík + čepel + střední žilka. `ang` = směr od řapíku (rad, 0 = nahoru v obrázku)."""
    ca, sa = math.cos(ang), math.sin(ang)
    pet = length * 0.15
    bx, by = base[0] + sa * pet, base[1] - ca * pet

    def tr(p):
        return (bx + (p[0] * ca + p[1] * sa) * length, by + (p[0] * sa - p[1] * ca) * length)
    pts = [tr(p) for p in _leaf_outline(kind, rng)]
    g = int(255 * lum)
    tone = rng.uniform(-0.04, 0.04)            # jemný odstín (žlutější / modřejší list)
    col = (int(np.clip(g * (1.0 + tone), 0, 255)), g, int(np.clip(g * (1.0 - tone * 1.5), 0, 255)), 255)
    dr.line([base, (bx, by)], fill=(90, 80, 60, 255), width=max(1, int(length * 0.025)))
    dr.polygon(pts, fill=col)
    vein = tuple(int(min(255, c * 1.12)) for c in col[:3]) + (255,)
    dr.line([tr((0, 0.02)), tr((0, 0.9))], fill=vein, width=max(1, int(length * 0.02)))
    for k in range(4):                          # postranní žilky
        y = 0.2 + k * 0.17
        for s in (-1, 1):
            dr.line([tr((0, y)), tr((s * 0.18, y + 0.12))], fill=vein, width=1)


def _leaf_tile(kind, seed):
    rng = np.random.default_rng(seed)
    S = TILE * SS
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    dr = ImageDraw.Draw(img)
    twig = (85, 70, 55, 255)
    if kind.startswith("jehlice"):
        _needle_tile(dr, kind, rng, S)
    else:
        # hlavní větvička od paty (dole uprostřed) nahoru, postranní střídavě; listy na uzlech
        leaf_len = {"vejcity": 0.14, "lalocnaty": 0.17, "pilovity": 0.13, "trojuhelnik": 0.11,
                    "okrouhly": 0.14, "ovalny": 0.13}.get(kind, 0.14) * S
        pts = []
        x, y = S * 0.5, S * 0.99
        ang = 0.0
        for i in range(9):
            nx = x + math.sin(ang) * S * 0.1
            ny = y - math.cos(ang) * S * 0.1
            dr.line([(x, y), (nx, ny)], fill=twig, width=max(2, int(S * 0.012 * (1.0 - i / 10.0))))
            pts.append(((nx, ny), ang, i))
            x, y = nx, ny
            ang += rng.uniform(-0.18, 0.18)
            ang = float(np.clip(ang, -0.35, 0.35))
        side = []
        for (p, a, i) in pts[1:-1]:
            for s in (-1, 1):
                if rng.random() < 0.85:
                    sa_ = a + s * rng.uniform(0.6, 1.0)
                    L = S * rng.uniform(0.16, 0.3) * (1.0 - i / 12.0)
                    q = (p[0] + math.sin(sa_) * L, p[1] - math.cos(sa_) * L)
                    q = (float(np.clip(q[0], S * 0.08, S * 0.92)), float(np.clip(q[1], S * 0.06, S * 0.95)))
                    dr.line([p, q], fill=twig, width=max(1, int(S * 0.006)))
                    side.append((p, q, sa_))
        # listy: podél postranních větviček a na konci hlavní
        leaves = []
        for (p, q, a) in side:
            for k in range(3):
                f = 0.35 + 0.3 * k
                b = (p[0] + (q[0] - p[0]) * f, p[1] + (q[1] - p[1]) * f)
                for s in (-1, 1):
                    leaves.append((b, a + s * rng.uniform(0.5, 1.1)))
            leaves.append((q, a + rng.uniform(-0.2, 0.2)))
        for (p, a, i) in pts[2:]:
            leaves.append((p, a + rng.choice([-1, 1]) * rng.uniform(0.4, 1.0)))
        order = rng.permutation(len(leaves))
        for k in order:
            b, a = leaves[k]
            L = leaf_len * rng.uniform(0.75, 1.15)
            lum = rng.uniform(0.5, 0.85)
            _draw_leaf(dr, b, a, L, kind, lum, rng)
    img = img.resize((TILE, TILE), Image.LANCZOS)
    return np.asarray(img).astype(np.float32) / 255.0


def _needle_tile(dr, kind, rng, S):
    """Jehličnaté karty: smrk = plochý vějíř (větvička 1. řádu s postranními výhony a krátkými jehlicemi),
    borovice = štětky dlouhých jehlic na koncích výhonů."""
    twig = (90, 70, 52, 255)
    if kind == "jehlice_smrk":
        axis = [(S * 0.5, S * 0.99)]
        for i in range(10):
            x, y = axis[-1]
            axis.append((x + rng.uniform(-0.01, 0.01) * S, y - S * 0.098))
        dr.line(axis, fill=twig, width=int(S * 0.01))
        shoots = []
        for i, p in enumerate(axis[1:-1]):
            for s in (-1, 1):
                L = S * (0.44 - 0.03 * i) * rng.uniform(0.85, 1.1)
                a = s * rng.uniform(0.85, 1.1)
                q = (p[0] + math.sin(a) * L, p[1] - math.cos(a) * L)
                q = (float(np.clip(q[0], S * 0.03, S * 0.97)), q[1])
                dr.line([p, q], fill=twig, width=max(2, int(S * 0.005)))
                shoots.append((p, q))
                # výhony 3. řádu
                for f in (0.35, 0.65):
                    b = (p[0] + (q[0] - p[0]) * f, p[1] + (q[1] - p[1]) * f)
                    a2 = a + s * 0.7
                    L2 = L * 0.35
                    e = (b[0] + math.sin(a2) * L2, b[1] - math.cos(a2) * L2)
                    e = (float(np.clip(e[0], S * 0.03, S * 0.97)), float(np.clip(e[1], S * 0.02, S * 0.98)))
                    shoots.append((b, e))
        shoots.append((axis[0], axis[-1]))
        for (p, q) in shoots:
            dx, dy = q[0] - p[0], q[1] - p[1]
            L = math.hypot(dx, dy)
            ux, uy = dx / max(L, 1), dy / max(L, 1)
            nsteps = int(L / (S * 0.006))
            for k in range(nsteps):
                f = k / max(nsteps, 1)
                b = (p[0] + dx * f, p[1] + dy * f)
                for s in (-1, 1):
                    nl = S * rng.uniform(0.035, 0.055) * (1.0 - 0.4 * f)
                    a = math.atan2(uy, ux) + s * rng.uniform(0.45, 1.0)
                    e = (b[0] + math.cos(a) * nl, b[1] + math.sin(a) * nl)
                    g = int(255 * rng.uniform(0.45, 0.8))
                    dr.line([b, e], fill=(int(g * 0.95), g, int(g * 1.05) if g < 243 else 255, 255), width=max(3, int(S * 0.006)))
    else:
        axis = [(S * 0.5, S * 0.99)]
        for i in range(6):
            x, y = axis[-1]
            axis.append((x + rng.uniform(-0.04, 0.04) * S, y - S * 0.12))
        dr.line(axis, fill=twig, width=int(S * 0.014))
        tufts = [axis[-1], axis[-3]]
        for i in (2, 3, 4):
            for s in (-1, 1):
                if rng.random() < 0.8:
                    p = axis[i]
                    a = s * rng.uniform(0.5, 0.9)
                    L = S * rng.uniform(0.18, 0.26)
                    q = (p[0] + math.sin(a) * L, p[1] - math.cos(a) * L)
                    dr.line([p, q], fill=twig, width=max(2, int(S * 0.008)))
                    tufts.append(q)
        for c in tufts:
            for k in range(70):
                a = rng.uniform(-math.pi, math.pi) * 0.85 + rng.normal(0, 0.15)
                nl = S * rng.uniform(0.09, 0.16)
                e = (c[0] + math.sin(a) * nl, c[1] - math.cos(a) * nl * 0.95)
                g = int(255 * rng.uniform(0.45, 0.82))
                dr.line([c, e], fill=(int(g * 0.95), g, min(255, int(g * 1.04)), 255), width=max(2, int(S * 0.0035)))


def _normalize_and_bleed(t):
    a = t[..., 3]
    cov = a > 0.5
    if cov.any():
        lum = t[..., :3].mean(-1)
        t[..., :3] *= LEAF_MEAN / max(float(lum[cov].mean()), 1e-3)
        t[..., :3] = np.clip(t[..., :3], 0.0, 1.0)
    return _bleed(t)


def _bleed(t):
    """RGB průhledných pixelů = RGB nejbližšího krytého (bez tmavých lemů v mipmapách)."""
    cov = t[..., 3] > 0.3
    if not cov.any():
        return t
    _, (iy, ix) = ndimage.distance_transform_edt(~cov, return_indices=True)
    out = t.copy()
    out[..., :3] = t[iy, ix, :3]
    return out


# ------------------------------------------------------------------ kůra

def _pnoise(shape, cx, cy, rng, power=1.0):
    """Periodický (dlaždicový) šum: bílý šum s gaussovským dolním propustem ve frekvenci → dlaždice navazuje sama
    na sebe. cx, cy = kolik „útvarů“ se vejde na šířku / výšku dlaždice (větší = jemnější; cx ≫ cy → svislé pruhy).
    `power` přidá růžovost (větší útvary silnější)."""
    h, w = shape
    n = rng.standard_normal(shape)
    fy = np.fft.fftfreq(h)[:, None] * h / max(cy, 0.5)
    fx = np.fft.fftfreq(w)[None, :] * w / max(cx, 0.5)
    f = np.sqrt(fx * fx + fy * fy)
    spec = np.fft.fft2(n) * np.exp(-f * f) / (1.0 + f) ** power
    spec[0, 0] = 0
    r = np.real(np.fft.ifft2(spec))
    r -= r.min()
    return r / max(r.max(), 1e-6)


def _bark_tile(kind, seed):
    rng = np.random.default_rng(seed)
    T = TILE
    sh = (T, T)
    yy, xx = np.mgrid[0:T, 0:T] / T

    def col(c):
        return np.array(c, np.float32)[None, None, :]
    if kind == "hladka_seda":        # buk: hladká šedá, jemné skvrny
        n = _pnoise(sh, 6, 6, rng) * 0.6 + _pnoise(sh, 60, 60, rng) * 0.4
        base = col((0.52, 0.52, 0.49)) * (0.8 + 0.35 * n[..., None])
        m = _pnoise(sh, 5, 3, rng) > 0.78
        base[m] *= 0.92
    elif kind == "brazdita":         # dub: hluboké svislé brázdy
        ridges = _pnoise(sh, 26, 3, rng)               # svisle protažené (hodně útvarů napříč, málo podél)
        ridges = np.clip((ridges - 0.35) * 2.2, 0, 1)
        fine = _pnoise(sh, 90, 90, rng)
        base = col((0.44, 0.4, 0.35)) * (0.5 + 0.6 * ridges[..., None]) * (0.85 + 0.3 * fine[..., None])
    elif kind == "zebrovana_seda":   # habr: šedá se svislými „svaly“
        r = _pnoise(sh, 6, 2, rng)
        s = 0.5 + 0.5 * np.sin((xx * 9.0 + r * 1.5) * 2 * np.pi)
        base = col((0.55, 0.55, 0.53)) * (0.75 + 0.3 * s[..., None]) * (0.9 + 0.2 * _pnoise(sh, 80, 80, rng)[..., None])
    elif kind == "bila":             # bříza: bílá, černé vodorovné čočinky a tmavé skvrny
        base = col((0.86, 0.85, 0.82)) * (0.9 + 0.12 * _pnoise(sh, 60, 60, rng)[..., None])
        # čočinky: tenké vodorovné pásky (málo útvarů napříč, hodně podél kmene)
        lent = (_pnoise(sh, 3, 70, rng) > 0.72) & (_pnoise(sh, 8, 8, rng) > 0.35)
        base[lent] = col((0.12, 0.11, 0.1))[0, 0]
        blot = _pnoise(sh, 5, 7, rng) > 0.82
        base[blot] = base[blot] * 0.25 + col((0.1, 0.09, 0.08))[0, 0] * 0.75
    elif kind == "tmava":            # olše: tmavě šedohnědá, jemně rozpraskaná
        n = _pnoise(sh, 22, 8, rng)
        base = col((0.3, 0.28, 0.26)) * (0.65 + 0.5 * n[..., None])
    elif kind == "supinata_seda":    # jabloň: šedohnědé odlupující se šupiny
        n = _pnoise(sh, 14, 10, rng)
        plates = np.clip((n - 0.45) * 4, 0, 1)
        base = col((0.42, 0.38, 0.33)) * (0.55 + 0.55 * plates[..., None])
    elif kind == "cervenohneda":     # smrk: červenohnědá s drobnými šupinami
        n = _pnoise(sh, 40, 30, rng)
        base = col((0.4, 0.27, 0.19)) * (0.6 + 0.55 * n[..., None])
    else:                            # "supinata_oranzova" – borovice: oranžové plotny a tmavé praskliny
        n = _pnoise(sh, 18, 9, rng)
        plates = np.clip((n - 0.3) * 6, 0, 1)
        base = col((0.62, 0.38, 0.2)) * (0.4 + 0.7 * plates[..., None])
    rgb = np.clip(base, 0, 1)
    return np.concatenate([rgb, np.ones(sh + (1,), np.float32)], -1)


# ------------------------------------------------------------------ atlasy

def build_atlases(shapes, grid):
    """shapes: [(id, params)] v pořadí dlaždic; grid = (sloupce, řádky). Vrací (listí RGBA float, kůra RGBA float)."""
    cols, rows = grid
    leaf = np.zeros((rows * TILE, cols * TILE, 4), np.float32)
    bark = np.zeros((rows * TILE, cols * TILE, 4), np.float32)
    for k, (sid, p) in enumerate(shapes):
        cx, cy = (k % cols) * TILE, (k // cols) * TILE
        lt = _normalize_and_bleed(_leaf_tile(str(p.get("list", "vejcity")), 1000 + k))
        leaf[cy:cy + TILE, cx:cx + TILE] = lt
        bark[cy:cy + TILE, cx:cx + TILE] = _bark_tile(str(p.get("kura", "hladka_seda")), 2000 + k)
    return leaf, bark


def save_png(arr, path, alpha=True):
    a = np.clip(arr * 255.0 + 0.5, 0, 255).astype(np.uint8)
    if not alpha:
        a = a[..., :3]
    Image.fromarray(a).save(path, optimize=True)


def sample(atlas, tile, grid, uv, wrap):
    """Bodové vzorkování dlaždice atlasu (pro pečení impostorů). uv (N, 2) v jednotkách dlaždice."""
    cols, _ = grid
    u = uv[:, 0] % 1.0 if wrap else np.clip(uv[:, 0], 0.0, 0.999)
    v = uv[:, 1] % 1.0 if wrap else np.clip(uv[:, 1], 0.0, 0.999)
    x = ((tile % cols) * TILE + u * TILE).astype(np.int32)
    y = ((tile // cols) * TILE + v * TILE).astype(np.int32)
    return atlas[y, x]


def blur_alpha_preview(img):
    return img.filter(ImageFilter.GaussianBlur(0.5))
