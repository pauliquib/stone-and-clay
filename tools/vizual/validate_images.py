"""Vizuální validátor – obrazová vrstva: metriky a kontroly snímků → <out>/images.json.

  python3 tools/vizual/validate_images.py [--out=logs/vizual/latest] [--views=DIR] [--gallery=DIR]
                                          [--dir=DIR …] [--prev=DIR] [--quick]

Snímky: <out>/views/*.png (popis v <out>/views.json: name, png, time, weather …), <out>/gallery/*.png
a libovolné další adresáře (--dir). Metriky: histogram jasu, ořez v černé/bílé, expozice, sytost,
odhad oblohy a horizontu, ploché jednobarevné skvrny (chybějící textura, magenta, čistá černá),
izolované extrémní pixely (NaN/inf z renderu), vysokofrekvenční šum a aliasing (energie u Nyquista).
Prahy podle druhu pohledu (noc smí být tmavá, sníh světlý). Je-li <prev>/views/<jméno>.png
(výchozí <out>/../prev), spočte rozdíl proti minulému běhu (střední ΔE a SSIM).
"""
import argparse
import glob
import os
import re
import sys

import numpy as np
from PIL import Image
from scipy import ndimage

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import GAME, Findings, load_json, save_json, r3  # noqa: E402

TOP_N = 50
MAX_SIDE = 1600               # větší snímky se pro analýzu zmenší

# expozice – průměrná luma: (WARN pod, WARN nad, FAIL pod, FAIL nad) podle denní doby
EXPO = {"day": (0.16, 0.80, 0.05, 0.94), "dusk": (0.05, 0.75, 0.012, 0.94),
        "night": (0.004, 0.45, -1.0, 0.80), "model": (0.05, 0.92, 0.01, 0.98)}
# ořez – podíl pixelů v černé (<2/255) a bílé (>253/255): (WARN, FAIL)
CLIP_BLACK = {"day": (0.12, 0.45), "dusk": (0.30, 0.75), "night": (0.85, 0.995), "model": (0.6, 0.95)}
CLIP_WHITE = {"day": (0.06, 0.30), "dusk": (0.06, 0.30), "night": (0.04, 0.25), "model": (0.9, 1.01)}
CLIP_WHITE_SNOW = (0.25, 0.60)
BLANK_STD = 0.008             # směrodatná odchylka jasu pod → prázdný snímek (FAIL)
SAT_HIGH = 0.70               # průměrná sytost nad → WARN (přesycené)
SAT_LOW = 0.035               # pod (den, bez deště/sněhu/mlhy) → WARN (šedivé)
SKY_HIGH = 0.85               # podíl oblohy nad → WARN (chybí svět?), mimo dron/model
SKY_GRAD = 0.02               # „hladký“ pixel oblohy: |∇jas| / (jas + 0,03) po vyhlazení pod
FLAT_WARN, FLAT_FAIL = 0.04, 0.20     # největší plochá skvrna mimo oblohu (podíl obrazu)
MAGENTA_WARN, MAGENTA_FAIL = 0.0005, 0.005
BLACK_FLAT_WARN, BLACK_FLAT_FAIL = 0.02, 0.15
ISO_DIFF = 0.30               # izolovaný pixel: |jas − medián okolí| nad
ISO_BLACK = (20.0, 200.0)     # izolované černé pixely na Mpx: (WARN, FAIL)
ISO_WHITE = (200.0, 2000.0)   # bílé (odlesky jsou běžné): (WARN, FAIL)
HF_CUT = 0.25                 # cykly/px – hranice „vysokých frekvencí“
HF_WARN, HF_FAIL = 0.12, 0.45  # podíl energie nad HF_CUT (bílý šum ≈ 0,8)
NYQ_CUT = 0.42
NYQ_WARN, NYQ_FAIL = 0.03, 0.30   # podíl energie u Nyquista (aliasing; bílý šum ≈ 0,3)
NYQ_DOMINANT = 0.5            # Nyquist / HF nad → vysoké frekvence jsou aliasing, ne šum
LAP_WARN = 0.10               # střední |Laplacián| jasu nad → WARN (šum / třpyt)
SSIM_WARN = 0.55              # proti minulému běhu pod → WARN (velká změna)
DE_WARN = 12.0                # střední ΔE (CIE76) nad → WARN

NIGHT_WORDS = ("noc", "night", "pulnoc")
DUSK_WORDS = ("soumrak", "dusk", "svitani", "svítání", "dawn", "vecer", "večer", "sunset", "zapad", "západ")


def classify(meta, name, group):
    """Profil pohledu: denní doba (day/dusk/night/model) a příznaky počasí."""
    if group == "gallery":
        return {"tod": "model", "rain": False, "snow": False, "fog": False, "drone": False}
    txt = (name + " " + " ".join(str(meta.get(k, "")) for k in ("time", "weather", "season", "label", "name"))).lower()
    tod = "day"
    t = meta.get("time", meta.get("hour"))
    hour = None
    if isinstance(t, (int, float)):
        hour = float(t)
    elif isinstance(t, str):
        m = re.match(r"^\s*(\d{1,2})(?:[:.](\d{1,2}))?\s*$", t)
        if m:
            hour = int(m.group(1)) + (int(m.group(2) or 0) / 60.0)
    if hour is not None:
        hour %= 24
        tod = "night" if (hour < 4.5 or hour >= 21.5) else "dusk" if (hour < 7.0 or hour >= 18.5) else "day"
    if any(w in txt for w in NIGHT_WORDS):
        tod = "night"
    elif any(w in txt for w in DUSK_WORDS):
        tod = "dusk" if tod != "night" else tod
    w = str(meta.get("weather", "")).lower() + " " + txt
    return {"tod": tod,
            "rain": any(k in w for k in ("rain", "dest", "déšť", "dést", "storm", "bourk")),
            "snow": any(k in w for k in ("snow", "snih", "sníh", "zima", "winter")),
            "fog": any(k in w for k in ("fog", "mlha", "overcast", "zatazeno", "zataženo")),
            "drone": any(k in txt for k in ("dron", "drone", "aerial", "letec"))}


def load_rgb(path):
    im = Image.open(path)
    if im.mode not in ("RGB", "RGBA", "L"):
        im = im.convert("RGBA")
    if im.mode == "RGBA":
        bg = Image.new("RGB", im.size, (0, 0, 0))
        bg.paste(im, mask=im.split()[3])
        im = bg
    im = im.convert("RGB")
    full = im.size
    if max(im.size) > MAX_SIDE:
        s = MAX_SIDE / max(im.size)
        im = im.resize((max(1, int(im.width * s)), max(1, int(im.height * s))), Image.BILINEAR)
    return np.asarray(im, dtype=np.float32) / 255.0, full


def luma_of(rgb):
    return rgb[..., 0] * 0.2126 + rgb[..., 1] * 0.7152 + rgb[..., 2] * 0.0722


def srgb_to_lab(rgb):
    a = np.where(rgb <= 0.04045, rgb / 12.92, ((rgb + 0.055) / 1.055) ** 2.4)
    M = np.array([[0.4124, 0.3576, 0.1805], [0.2126, 0.7152, 0.0722], [0.0193, 0.1192, 0.9505]])
    xyz = a @ M.T / np.array([0.95047, 1.0, 1.08883])
    f = np.where(xyz > 0.008856, np.cbrt(xyz), 7.787 * xyz + 16 / 116)
    return np.stack([116 * f[..., 1] - 16, 500 * (f[..., 0] - f[..., 1]), 200 * (f[..., 1] - f[..., 2])], -1)


def ssim(a, b):
    """SSIM jasu s gaussovským oknem (σ 1,5) – průměr přes obraz."""
    C1, C2 = 0.01 ** 2, 0.03 ** 2
    g = lambda x: ndimage.gaussian_filter(x, 1.5)  # noqa: E731
    ma, mb = g(a), g(b)
    va, vb, cab = g(a * a) - ma * ma, g(b * b) - mb * mb, g(a * b) - ma * mb
    s = ((2 * ma * mb + C1) * (2 * cab + C2)) / ((ma * ma + mb * mb + C1) * (va + vb + C2))
    return float(s.mean())


def sky_mask(rgb, Y):
    """Odhad oblohy: hladké oblasti souvisle napojené na horní okraj, ne zelené.
    Vrací (maska, podíl, výška horizontu 0 = nahoře … 1 = dole)."""
    H, W = Y.shape
    sm = ndimage.gaussian_filter(Y, 1.5)
    gm = np.hypot(ndimage.sobel(sm, 0), ndimage.sobel(sm, 1)) / 8.0
    gm = ndimage.maximum_filter(gm, 3) / (sm + 0.03)
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    greenish = (g > r + 0.03) & (g > b + 0.03)
    cand = (gm < SKY_GRAD) & ~greenish
    lab, n = ndimage.label(cand)
    if n == 0:
        return np.zeros_like(cand), 0.0, 0.0
    top = np.unique(lab[0][lab[0] > 0])
    sky = np.isin(lab, top)
    # horizont po sloupcích: první řádek shora, který není obloha
    notsky = ~sky
    first = np.where(notsky.any(0), notsky.argmax(0), H)
    return sky, float(sky.mean()), float(np.median(first) / H)


def flat_regions(rgb):
    """Maska pixelů s nulovým rozptylem v okně 3×3 (všechny kanály)."""
    v = np.zeros(rgb.shape[:2], np.float32)
    for c in range(3):
        x = rgb[..., c]
        m = ndimage.uniform_filter(x, 3)
        v += np.maximum(ndimage.uniform_filter(x * x, 3) - m * m, 0)
    return v < 1e-7


def largest_component(mask, exclude=None):
    lab, n = ndimage.label(mask, structure=np.ones((3, 3)))
    if n == 0:
        return 0.0, None
    sizes = ndimage.sum(np.ones_like(mask, np.float32), lab, index=np.arange(1, n + 1))
    if exclude is not None:
        ex = ndimage.sum(exclude.astype(np.float32), lab, index=np.arange(1, n + 1))
        sizes = np.where(ex > 0.5 * sizes, 0, sizes)
    k = int(np.argmax(sizes))
    if sizes[k] <= 0:
        return 0.0, None
    ys, xs = np.nonzero(lab == k + 1)
    return float(sizes[k] / mask.size), [int(xs.mean()), int(ys.mean())]


def spectrum(Y):
    """Podíl energie nad HF_CUT (radiálně) a u Nyquista (NYQ_CUT v ose x nebo z)."""
    H, W = Y.shape
    win = np.outer(np.hanning(H), np.hanning(W)).astype(np.float32)
    F = np.fft.fft2((Y - Y.mean()) * win)
    P = (F.real ** 2 + F.imag ** 2)
    fy = np.abs(np.fft.fftfreq(H))[:, None]
    fx = np.abs(np.fft.fftfreq(W))[None, :]
    tot = P.sum() - P[0, 0]
    if tot <= 1e-12:
        return 0.0, 0.0
    rad = np.hypot(fx, fy)
    return float(P[rad > HF_CUT].sum() / tot), float(P[(fx > NYQ_CUT) | (fy > NYQ_CUT)].sum() / tot)


def analyze(path, prof, F, label, prev_path=None, quick=False):
    rgb, full = load_rgb(path)
    H, W = rgb.shape[:2]
    Y = luma_of(rgb)
    tod = prof["tod"]
    is_model = tod == "model"
    m = {"size": list(full)}
    hist, _ = np.histogram(Y, bins=16, range=(0, 1))
    m["hist"] = [r3(h / Y.size, 4) for h in hist]
    mx, mn = rgb.max(-1), rgb.min(-1)
    m["clip_black"] = float((mx < 2 / 255).mean())
    m["clip_white"] = float((mn > 253 / 255).mean())
    m["mean_luma"] = float(Y.mean())
    m["median_luma"] = float(np.median(Y))
    m["std_luma"] = float(Y.std())
    sat = np.where(mx > 1e-6, (mx - mn) / np.maximum(mx, 1e-6), 0)
    m["saturation"] = float(sat.mean())
    sky, sky_frac, horizon = sky_mask(rgb, Y)
    m["sky_frac"], m["horizon"] = sky_frac, horizon

    def add(check, sev, msg, score=0.0, px=None):
        extra = {"view": label}
        if px is not None:
            extra["px"] = px
        F.add(check, sev, f"{label}: {msg}", None, score, **extra)

    # prázdný snímek – ostatní kontroly by jen opakovaly totéž
    if m["std_luma"] < BLANK_STD:
        add("img_prazdny", "FAIL", f"prázdný / jednobarevný snímek (σ jasu {m['std_luma']:.4f}, průměr {m['mean_luma']:.3f})", 10)
        m.update({"magenta_frac": 0.0, "black_flat_frac": 0.0, "flat_frac": 1.0, "laplacian": 0.0,
                  "hf_ratio": 0.0, "nyquist_ratio": 0.0, "iso_black_per_mpx": 0.0, "iso_white_per_mpx": 0.0})
        return {k: (r3(v, 4) if isinstance(v, float) else v) for k, v in m.items()}

    # expozice
    wl, wh, fl, fh = EXPO[tod]
    if prof["snow"] and tod == "day":
        wh, fh = 0.88, 0.97
    if m["mean_luma"] < fl or m["mean_luma"] > fh:
        add("img_expozice", "FAIL", f"expozice {m['mean_luma']:.3f} mimo {fl}..{fh} ({tod})", abs(m["mean_luma"] - 0.45))
    elif m["mean_luma"] < wl or m["mean_luma"] > wh:
        add("img_expozice", "WARN", f"expozice {m['mean_luma']:.3f} mimo {wl}..{wh} ({tod})", abs(m["mean_luma"] - 0.45))
    bw, bf = CLIP_BLACK[tod]
    if m["clip_black"] > bf:
        add("img_orez", "FAIL", f"{100 * m['clip_black']:.1f} % pixelů v čisté černé", m["clip_black"])
    elif m["clip_black"] > bw:
        add("img_orez", "WARN", f"{100 * m['clip_black']:.1f} % pixelů v čisté černé", m["clip_black"])
    ww, wf = CLIP_WHITE_SNOW if prof["snow"] and not is_model else CLIP_WHITE[tod]
    if m["clip_white"] > wf:
        add("img_orez", "FAIL", f"{100 * m['clip_white']:.1f} % pixelů přepálených do bílé", m["clip_white"])
    elif m["clip_white"] > ww:
        add("img_orez", "WARN", f"{100 * m['clip_white']:.1f} % pixelů přepálených do bílé", m["clip_white"])

    # sytost
    if m["saturation"] > SAT_HIGH:
        add("img_sytost", "WARN", f"přesycené barvy (průměrná sytost {m['saturation']:.2f})", m["saturation"])
    elif (tod == "day" and not (prof["rain"] or prof["snow"] or prof["fog"])
          and m["saturation"] < SAT_LOW and m["std_luma"] >= BLANK_STD):
        add("img_sytost", "WARN", f"téměř šedivý snímek (sytost {m['saturation']:.3f})", SAT_LOW - m["saturation"])

    # obloha
    if not is_model and not prof["drone"] and tod != "night" and sky_frac > SKY_HIGH:
        add("img_obloha", "WARN", f"obloha zabírá {100 * sky_frac:.0f} % – chybí svět / kamera míří do nebe?", sky_frac)

    # ploché skvrny, magenta, čistá černá
    flat = flat_regions(rgb)
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    mag = (r > 0.6) & (b > 0.6) & (g < 0.45 * np.minimum(r, b))
    m["magenta_frac"] = float(mag.mean())
    if m["magenta_frac"] > MAGENTA_WARN:
        fr, c = largest_component(mag)
        add("img_magenta", "FAIL" if fr > MAGENTA_FAIL else "WARN",
            f"magenta {100 * m['magenta_frac']:.2f} % obrazu (největší skvrna {100 * fr:.2f} %) – chybějící textura / chyba shaderu",
            m["magenta_frac"], c)
    bf_frac, bc = largest_component(flat & (mx < 2 / 255), exclude=sky if tod != "day" else None)
    m["black_flat_frac"] = bf_frac
    if not is_model and tod != "night":
        lim = (BLACK_FLAT_WARN, BLACK_FLAT_FAIL) if tod == "day" else (BLACK_FLAT_WARN * 4, 0.6)
        if bf_frac > lim[1]:
            add("img_cerna", "FAIL", f"plochá čistě černá skvrna {100 * bf_frac:.1f} % obrazu", bf_frac, bc)
        elif bf_frac > lim[0]:
            add("img_cerna", "WARN", f"plochá čistě černá skvrna {100 * bf_frac:.1f} % obrazu", bf_frac, bc)
    ff, fc = largest_component(flat & ~mag & (mx >= 2 / 255), exclude=sky)
    m["flat_frac"] = ff
    if not is_model:
        if ff > FLAT_FAIL:
            add("img_plocha", "FAIL", f"plochá jednobarevná skvrna {100 * ff:.1f} % obrazu (chybí textura?)", ff, fc)
        elif ff > FLAT_WARN:
            add("img_plocha", "WARN", f"plochá jednobarevná skvrna {100 * ff:.1f} % obrazu (chybí textura?)", ff, fc)

    # izolované extrémní pixely (NaN/inf z renderu)
    med = ndimage.median_filter(Y, size=3)
    diff = np.abs(Y - med)
    # NaN/inf dá osamělý pixel: žádný z 8 sousedů není extrémní (tahy písma a čáry mřížky v galerii jsou souvislé)
    ext_b = mx < 2 / 255
    ext_w = mn > 253 / 255
    nb_b = ndimage.convolve(ext_b.astype(np.uint8), np.ones((3, 3), np.uint8), mode="constant") - ext_b
    nb_w = ndimage.convolve(ext_w.astype(np.uint8), np.ones((3, 3), np.uint8), mode="constant") - ext_w
    # … a v okolí 5×5 není jiný tmavý/světlý pixel (tečky a háčky drobného písma popisků)
    dark5 = ndimage.convolve((Y < 0.3).astype(np.uint8), np.ones((5, 5), np.uint8), mode="constant")
    lite5 = ndimage.convolve((Y > 0.8).astype(np.uint8), np.ones((5, 5), np.uint8), mode="constant")
    iso_b = ext_b & (diff > ISO_DIFF) & (nb_b == 0) & (dark5 <= 1)
    iso_w = ext_w & (diff > ISO_DIFF) & (nb_w == 0) & (lite5 <= 1)
    mpx = Y.size / 1e6
    m["iso_black_per_mpx"] = float(iso_b.sum() / mpx)
    m["iso_white_per_mpx"] = float(iso_w.sum() / mpx)
    for name, cnt, (tw, tf) in (("černých", m["iso_black_per_mpx"], ISO_BLACK), ("bílých", m["iso_white_per_mpx"], ISO_WHITE)):
        if cnt > tw:
            mask = iso_b if name == "černých" else iso_w
            ys, xs = np.nonzero(mask)
            add("img_nan_pixely", "FAIL" if cnt > tf else "WARN",
                f"{cnt:.0f} izolovaných {name} pixelů na Mpx (NaN/inf v renderu?)", cnt, [int(xs[0]), int(ys[0])])

    # šum a aliasing
    lap = np.abs(ndimage.laplace(Y))
    m["laplacian"] = float(lap.mean())
    m["hf_ratio"], m["nyquist_ratio"] = spectrum(Y) if not quick or Y.size < 3e6 else (0.0, 0.0)
    alias = m["nyquist_ratio"] > NYQ_DOMINANT * max(m["hf_ratio"], 1e-9)
    if m["nyquist_ratio"] > NYQ_WARN:
        add("img_aliasing", "FAIL" if (alias and m["nyquist_ratio"] > NYQ_FAIL) else "WARN",
            f"aliasing – energie u Nyquista {m['nyquist_ratio']:.3f} (vysoké frekvence {m['hf_ratio']:.3f})",
            m["nyquist_ratio"])
    if not alias:
        if m["hf_ratio"] > HF_FAIL:
            add("img_sum", "FAIL", f"obraz je převážně šum (podíl vysokých frekvencí {m['hf_ratio']:.2f})", m["hf_ratio"])
        elif m["hf_ratio"] > HF_WARN or m["laplacian"] > LAP_WARN:
            add("img_sum", "WARN", f"vysokofrekvenční šum (HF {m['hf_ratio']:.3f}, |Laplacián| {m['laplacian']:.3f})",
                m["hf_ratio"])

    # porovnání s minulým během
    if prev_path and os.path.exists(prev_path):
        try:
            prgb, _ = load_rgb(prev_path)
            if prgb.shape != rgb.shape:
                prgb = np.asarray(Image.fromarray((prgb * 255).astype(np.uint8)).resize((W, H), Image.BILINEAR),
                                  np.float32) / 255.0
            de = np.linalg.norm(srgb_to_lab(rgb) - srgb_to_lab(prgb), axis=-1)
            m["prev"] = {"delta_e": float(de.mean()), "delta_e_p95": float(np.percentile(de, 95)),
                         "ssim": ssim(Y, luma_of(prgb)), "file": prev_path}
            if m["prev"]["ssim"] < SSIM_WARN or m["prev"]["delta_e"] > DE_WARN:
                add("img_zmena", "WARN", f"velká změna proti minulému běhu (SSIM {m['prev']['ssim']:.2f}, "
                    f"ΔE {m['prev']['delta_e']:.1f})", 1 - m["prev"]["ssim"])
        except (OSError, ValueError) as e:
            m["prev"] = {"error": str(e)}
    return {k: (r3(v, 4) if isinstance(v, float) else v) for k, v in m.items()}


def views_meta(out, views_dir):
    """Záznamy z views.json → {jméno souboru: záznam}."""
    vj = load_json(os.path.join(out, "views.json")) or load_json(os.path.join(views_dir, "views.json"))
    recs = vj.get("views", []) if isinstance(vj, dict) else (vj or [])
    res = {}
    for r in recs:
        if not isinstance(r, dict):
            continue
        png = r.get("png") or r.get("file") or (str(r.get("name", "")) + ".png")
        res[os.path.basename(png)] = r
    return vj is not None, res


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--out", default=os.path.join(GAME, "logs", "vizual", "latest"))
    ap.add_argument("--views", default=None, help="adresář pohledů (výchozí <out>/views)")
    ap.add_argument("--gallery", default=None, help="adresář galerie (výchozí <out>/gallery)")
    ap.add_argument("--dir", action="append", default=[], help="další adresář PNG (lze opakovat)")
    ap.add_argument("--prev", default=None, help="minulý běh (výchozí <out>/../prev)")
    ap.add_argument("--quick", action="store_true")
    a = ap.parse_args()
    out = os.path.abspath(a.out)
    vdir = a.views or os.path.join(out, "views")
    gdir = a.gallery or os.path.join(out, "gallery")
    prev = a.prev or os.path.join(os.path.dirname(out), "prev")
    F = Findings("images", TOP_N)

    has_vj, meta = views_meta(out, vdir)
    gj = load_json(os.path.join(out, "gallery.json")) or {}
    gmeta = {os.path.basename(m.get("png", "")): m for m in gj.get("models", []) if isinstance(m, dict)}
    vj = load_json(os.path.join(out, "views.json"))
    if isinstance(vj, dict) and isinstance(vj.get("stats"), dict) and vj["stats"].get("error"):
        F.add("img_engine", "WARN", f"pohledy: engine hlásí chybu: {vj['stats']['error']}", None, 1, view="views")
    groups = [("views", vdir), ("gallery", gdir)] + [("other", d) for d in a.dir]
    images = []
    for group, d in groups:
        files = sorted(glob.glob(os.path.join(d, "*.png")))
        if not files:
            F.skip(f"skupina_{group}" if group != "other" else f"skupina_{os.path.basename(d.rstrip('/'))}",
                   f"žádné PNG v {os.path.relpath(d, out) if d.startswith(out) else d}")
            continue
        for f in files:
            base = os.path.basename(f)
            rec = meta.get(base, {}) if group == "views" else gmeta.get(base, {}) if group == "gallery" else {}
            name = str(rec.get("name") or os.path.splitext(base)[0])
            label = f"{group}/{name}" if group != "views" else name
            prof = classify(rec, name, group)
            pp = os.path.join(prev, os.path.relpath(f, out)) if f.startswith(out + os.sep) else None
            try:
                mets = analyze(f, prof, F, label, pp, a.quick)
            except (OSError, ValueError) as e:
                F.add("img_cteni", "FAIL", f"{label}: nelze načíst ({e})", None, 1, view=label)
                continue
            st = "PASS"
            for f2 in F.items.values():
                for x in f2:
                    if x.get("view") == label and x["severity"] in ("FAIL", "WARN"):
                        st = "FAIL" if x["severity"] == "FAIL" or st == "FAIL" else "WARN"
            img = {"name": name, "group": group, "file": os.path.relpath(f, out) if f.startswith(out) else f,
                   "profile": prof, "status": st, "metrics": mets}
            for k in ("pos", "time", "weather", "date", "yaw", "pitch", "fov", "why", "fps", "draw_calls",
                      "primitives", "category", "aabb_size"):
                if k in rec:
                    img[k] = rec[k]
            images.append(img)
    # záznamy z views.json bez souboru / s chybou z enginu
    present = {os.path.basename(i["file"]) for i in images if i["group"] == "views"}
    for base, rec in meta.items():
        if rec.get("error"):
            F.add("img_engine", "WARN", f"{rec.get('name', base)}: engine hlásí chybu: {rec['error']}", None, 1,
                  view=rec.get("name", base))
        elif base not in present:
            F.add("img_engine", "WARN", f"{rec.get('name', base)}: views.json uvádí {base}, soubor chybí", None, 1,
                  view=rec.get("name", base))
    if not has_vj and any(i["group"] == "views" for i in images):
        F.metrics("img_engine", note="views.json chybí – profily jen podle jmen souborů")

    summary = {"images": len(images), "by_group": {}, "views_json": has_vj}
    for i in images:
        g = summary["by_group"].setdefault(i["group"], {"PASS": 0, "WARN": 0, "FAIL": 0})
        g[i["status"]] += 1
    res = F.result(summary)
    if not images:
        res["status"] = "SKIP"
    res["images"] = images
    save_json(os.path.join(out, "images.json"), res)
    print(f"validate_images: {res['status']}  {len(images)} snímků  FAIL {res['totals']['FAIL']}  "
          f"WARN {res['totals']['WARN']}  → {os.path.join(out, 'images.json')}")
    for i in images:
        mm = i["metrics"]
        print(f"  {i['status']:4} {i['group']}/{i['name']:<22} {i['profile']['tod']:5} jas {mm['mean_luma']:.2f} "
              f"sytost {mm['saturation']:.2f} obloha {mm['sky_frac']:.2f} plocha {mm['flat_frac']:.3f} "
              f"HF {mm['hf_ratio']:.3f} Nyq {mm['nyquist_ratio']:.4f}"
              + (f" SSIM {mm['prev']['ssim']:.2f}" if isinstance(mm.get("prev"), dict) and "ssim" in mm["prev"] else ""))
    return 0


if __name__ == "__main__":
    sys.exit(main())
