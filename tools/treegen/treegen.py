"""Generátor stromů podle druhu, věku a vitality → data/tree_species_protos.bin + atlasy. M8.8 (00_PRINCIPY §7, §8).

Podle čeho: listnáče **space colonization** (Runions et al. 2007) + pipe model tlouštěk, jehličnany **přeslenový
růst**, parametry ve stylu Weber & Penn 1995 (tools/treegen/growth.py); mesh – zobecněné válce + karty listí
(meshing.py); textury procedurálně (textures.py); impostory pečené splattingem z LOD0 (bake.py). Bez Blenderu.

Vstup: data/dreviny.json, oddíl "tvary" (parametry tvaru; pořadí = dlaždice atlasů) a "tvary.druhy" (druh → tvar).
Varianty: každý tvar × VIT_LEVELS (nízká / vysoká vitalita) × AGE_LEVELS (mladý / dospělý). Staré stromy = dospělý
model s měřítkem (instance má měřítko = skutečná výška).

Výstupy:
  data/tree_species_protos.bin             – DBT2 (formát níže)
  assets/textures/trees/listi.png          – atlas karet listí / jehličí (GRID dlaždic TILE², RGBA, šedý jas)
  assets/textures/trees/kura.png           – atlas kůry (GRID dlaždic, RGB)
  assets/textures/trees/impostor_barva.png – impostory: IMP_VIEWS sloupců × varianty řádků po IMP_PX², RGBA
  assets/textures/trees/impostor_normala.png – normály / maska listí / zimní silueta (viz bake.py)
  --preview: tools/out/treegen/nahled_<tvar>.png (LOD0, LOD1, impostor vedle sebe; všechny varianty) + atlasy

Formát data/tree_species_protos.bin (little endian):
  4 B  magic "DBT2", int32 verze (1)
  int32 S tvarů; S × (u8 délka, ASCII id, u8 jehličnan, u8 dlaždice, u16 0, f32 tuhost)
  int32 M druhů; M × (u8 délka, ASCII id druhu, u8 index tvaru)
  int32 počet tříd vitality V, (V−1) × f32 hranice (0..1); int32 počet věkových tříd A, (A−1) × f32 hranice (roky)
  int32 IMP_VIEWS, int32 IMP_PX, int32 sloupce a řádky atlasů listí / kůry
  int32 N variant; N × (u8 tvar, u8 vitalita, u8 věk, u8 0, f32 poloměr koruny, f32 imp_w, f32 imp_y0, f32 imp_y1,
     2 × LOD (LOD0, LOD1): int32 počet ploch (2: kůra, listí), plocha: int32 nv, int32 ni, nv×3 f32 poloha,
     nv×3 f32 normála, nv×2 f32 UV, nv×2 f32 UV2, nv×4 u8 barva vrcholu, ni × u32 index)
  Index varianty = řádek v atlasu impostorů. Model má výšku 1 (měřítko instance = výška v m), pata v počátku.

  python3 tools/treegen/treegen.py [--preview] [--only=buk,smrk] [--out=data/tree_species_protos.bin] [--seed=N]
"""
import json
import math
import os
import struct
import sys
import time

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bake  # noqa: E402
import growth  # noqa: E402
import meshing  # noqa: E402
import textures  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
CATALOG = os.path.join(ROOT, "data", "dreviny.json")
OUT_BIN = os.path.join(ROOT, "data", "tree_species_protos.bin")
TEX_DIR = os.path.join(ROOT, "assets", "textures", "trees")
PREVIEW_DIR = os.path.join(ROOT, "tools", "out", "treegen")

VIT_LEVELS = [0.3, 0.85]          # vitalita, se kterou se generuje třída (nízká, vysoká)
VIT_SPLIT = [0.45]                # hranice tříd ve hře (TreeEco.vigor)
AGE_LEVELS = ["mlady", "dospely"]
AGE_SPLIT = [30.0]                # roky – mladší strom dostane model „mladý“
GRID = (4, 2)                     # dlaždice atlasů listí / kůry (sloupce, řádky) → max 8 tvarů
IMP_VIEWS = bake.IMP_VIEWS
IMP_PX = 128
BUDGET = {                        # trojúhelníky (00 prompt M8.8: LOD0 listnáč ≤ 6000, jehličnan ≤ 4000; LOD1 ~25 %)
    ("kolonizace", 0): 4200, ("kolonizace", 1): 1050,
    ("presleny", 0): 3000, ("presleny", 1): 750,
}
SEED = 8808


def load_catalog():
    cat = json.load(open(CATALOG, encoding="utf-8"))
    tv = cat.get("tvary", {})
    shapes = [(k, v) for k, v in tv.get("parametry", {}).items() if not k.startswith("_")]
    return shapes, dict(tv.get("druhy", {}))


def gen_variant(sid, p, si, vi, ai, seed):
    young = AGE_LEVELS[ai] == "mlady"
    H = float(p["vyska_mlady" if young else "vyska_ref"])
    vig = VIT_LEVELS[vi]
    rng = np.random.default_rng(seed + si * 100 + vi * 10 + ai)
    if str(p["model"]) == "presleny":
        sk = growth.conifer(p, H, young, vig, rng)
    else:
        sk = growth.deciduous(p, H, young, vig, rng)
    lods = []
    for lod in (0, 1):
        bk, lf = meshing.build_lod(sk, p, H, si, lod, BUDGET[(str(p["model"]), lod)], young)
        lods.append((bk, lf))
    # normalizace na výšku 1 (vrchol LOD0)
    top = 0.0
    for b in lods[0]:
        if b.v:
            top = max(top, float(np.max(np.array(b.v)[:, 1])))
    top = max(top, 1e-3)
    arr = [[b.arrays(top) for b in pair] for pair in lods]
    cy, ry, R, y0 = sk.crown
    return sk, arr, R / top, H


def write_mesh(f, pair):
    f.write(struct.pack("<i", len(pair)))
    for a in pair:
        nv, ni = len(a["v"]), len(a["i"])
        f.write(struct.pack("<ii", nv, ni))
        f.write(a["v"].astype("<f4").tobytes())
        f.write(a["n"].astype("<f4").tobytes())
        f.write(a["uv"].astype("<f4").tobytes())
        f.write(a["uv2"].astype("<f4").tobytes())
        f.write(a["c"].astype(np.uint8).tobytes())
        f.write(a["i"].astype("<u4").tobytes())


def main():
    args = dict(a.lstrip("-").split("=", 1) if "=" in a else (a.lstrip("-"), "") for a in sys.argv[1:])
    if "help" in args or "h" in args:
        print(__doc__)
        return
    seed = int(args.get("seed", SEED))
    out = args.get("out", OUT_BIN)
    preview = "preview" in args
    shapes, sp_map = load_catalog()
    if not shapes:
        print("treegen: v data/dreviny.json chybí oddíl tvary.parametry")
        sys.exit(1)
    if len(shapes) > GRID[0] * GRID[1]:
        print("treegen: víc tvarů (%d) než dlaždic atlasu (%d) – zvětši GRID" % (len(shapes), GRID[0] * GRID[1]))
        sys.exit(1)
    only = set(x for x in args.get("only", "").split(",") if x)
    t0 = time.time()
    os.makedirs(TEX_DIR, exist_ok=True)
    leaf_atlas, bark_atlas = textures.build_atlases(shapes, GRID)
    print("atlasy: listí %s, kůra %s (%.1f s)" % (leaf_atlas.shape[:2], bark_atlas.shape[:2], time.time() - t0))

    variants = []
    for si, (sid, p) in enumerate(shapes):
        if only and sid not in only:
            continue
        for vi in range(len(VIT_LEVELS)):
            for ai in range(len(AGE_LEVELS)):
                t1 = time.time()
                sk, arr, crown_r, H = gen_variant(sid, p, si, vi, ai, seed)
                allv = np.concatenate([arr[0][0]["v"], arr[0][1]["v"]], 0)
                w, y0, y1 = bake.extents(allv)
                tri0 = sum(len(a["i"]) // 3 for a in arr[0])
                tri1 = sum(len(a["i"]) // 3 for a in arr[1])
                variants.append(dict(sid=sid, si=si, vi=vi, ai=ai, arr=arr, crown_r=crown_r, w=w, y0=y0, y1=y1,
                                     tri0=tri0, tri1=tri1, nodes=len(sk.pos), cards=len(sk.cards), H=H))
                print("  %-9s vit %d věk %-7s H %4.1f m  uzly %5d  karty %4d  LOD0 %5d tr (kůra %d)  LOD1 %4d tr  "
                      "koruna r/h %.2f  (%.1f s)" % (sid, vi, AGE_LEVELS[ai], H, len(sk.pos), len(sk.cards), tri0,
                                                    len(arr[0][0]["i"]) // 3, tri1, crown_r, time.time() - t1))

    # impostory
    t1 = time.time()
    rng = np.random.default_rng(seed + 7)
    imp_c = np.zeros((len(variants) * IMP_PX, IMP_VIEWS * IMP_PX, 4), np.float32)
    imp_n = np.zeros_like(imp_c)
    for row, var in enumerate(variants):
        px_world = (var["y1"] - var["y0"]) / (IMP_PX * bake.SUPER)
        P, N, C, L = bake.surface_points(var["arr"][0], leaf_atlas, bark_atlas, GRID, px_world, rng)
        for k in range(IMP_VIEWS):
            th = 2 * math.pi * k / IMP_VIEWS
            c, n = bake.render_view(P, N, C, L, th, var["w"], var["y0"], var["y1"], IMP_PX)
            ys, xs = row * IMP_PX, k * IMP_PX
            imp_c[ys:ys + IMP_PX, xs:xs + IMP_PX] = c
            imp_n[ys:ys + IMP_PX, xs:xs + IMP_PX] = n
    imp_c = bake.bleed(imp_c)
    imp_n = bake.bleed_normal(imp_n, imp_c[..., 3])
    print("impostory: %d × %d snímků (%.1f s)" % (len(variants), IMP_VIEWS, time.time() - t1))

    textures.save_png(leaf_atlas, os.path.join(TEX_DIR, "listi.png"))
    textures.save_png(bark_atlas, os.path.join(TEX_DIR, "kura.png"), alpha=False)
    textures.save_png(imp_c, os.path.join(TEX_DIR, "impostor_barva.png"))
    textures.save_png(imp_n, os.path.join(TEX_DIR, "impostor_normala.png"))

    with open(out, "wb") as f:
        f.write(b"DBT2")
        f.write(struct.pack("<i", 1))
        f.write(struct.pack("<i", len(shapes)))
        for si, (sid, p) in enumerate(shapes):
            b = sid.encode("ascii")
            f.write(struct.pack("<B", len(b)) + b)
            f.write(struct.pack("<BBHf", 1 if str(p["model"]) == "presleny" else 0, si, 0, float(p.get("tuhost", 1.0))))
        ids = [s for s in shapes]
        names = [s[0] for s in ids]
        f.write(struct.pack("<i", len(sp_map)))
        for sp, shp in sp_map.items():
            b = sp.encode("ascii")
            f.write(struct.pack("<B", len(b)) + b + struct.pack("<B", names.index(shp) if shp in names else 0))
        f.write(struct.pack("<i", len(VIT_LEVELS)))
        for x in VIT_SPLIT:
            f.write(struct.pack("<f", x))
        f.write(struct.pack("<i", len(AGE_LEVELS)))
        for x in AGE_SPLIT:
            f.write(struct.pack("<f", x))
        f.write(struct.pack("<iiii", IMP_VIEWS, IMP_PX, GRID[0], GRID[1]))
        f.write(struct.pack("<i", len(variants)))
        for var in variants:
            f.write(struct.pack("<BBBBffff", var["si"], var["vi"], var["ai"], 0, var["crown_r"], var["w"],
                                var["y0"], var["y1"]))
            for lod in (0, 1):
                write_mesh(f, var["arr"][lod])
    sz = os.path.getsize(out)
    tri0 = [v["tri0"] for v in variants]
    tri1 = [v["tri1"] for v in variants]
    print("hotovo: %s (%.1f MB), %d variant, LOD0 %d–%d tr (průměr %d), LOD1 %d–%d tr, celkem %.1f s"
          % (os.path.relpath(out, ROOT), sz / 1e6, len(variants), min(tri0), max(tri0), int(np.mean(tri0)),
             min(tri1), max(tri1), time.time() - t0))
    for fn in ("listi.png", "kura.png", "impostor_barva.png", "impostor_normala.png"):
        print("  %-22s %.2f MB" % (fn, os.path.getsize(os.path.join(TEX_DIR, fn)) / 1e6))

    if preview:
        _preview(variants, leaf_atlas, bark_atlas, imp_c, imp_n, rng)


def _preview(variants, leaf_atlas, bark_atlas, imp_c, imp_n, rng):
    """Náhled bez Blenderu: pro každý tvar řádky variant, sloupce LOD0 | LOD1 | impostor (pohled 0)."""
    os.makedirs(PREVIEW_DIR, exist_ok=True)
    R = 256
    by_shape = {}
    for row, var in enumerate(variants):
        by_shape.setdefault(var["sid"], []).append((row, var))
    for sid, lst in by_shape.items():
        sheet = np.ones((R * len(lst), R * 3, 3), np.float32)
        for k, (row, var) in enumerate(lst):
            for lod in (0, 1):
                px_world = (var["y1"] - var["y0"]) / (R * bake.SUPER)
                P, N, C, L = bake.surface_points(var["arr"][lod], leaf_atlas, bark_atlas, GRID, px_world, rng)
                c, n = bake.render_view(P, N, C, L, 0.3, var["w"], var["y0"], var["y1"], R)
                sheet[k * R:(k + 1) * R, lod * R:(lod + 1) * R] = bake.preview_shade(c, n)
            c = imp_c[row * IMP_PX:(row + 1) * IMP_PX, 0:IMP_PX]
            n = imp_n[row * IMP_PX:(row + 1) * IMP_PX, 0:IMP_PX]
            im = bake.preview_shade(c, n)
            im = np.asarray(Image.fromarray((im * 255).astype(np.uint8)).resize((R, R), Image.NEAREST)) / 255.0
            sheet[k * R:(k + 1) * R, 2 * R:3 * R] = im
        Image.fromarray((np.clip(sheet, 0, 1) * 255).astype(np.uint8)).save(os.path.join(PREVIEW_DIR, "nahled_%s.png" % sid))
    textures.save_png(leaf_atlas, os.path.join(PREVIEW_DIR, "atlas_listi.png"))
    print("náhledy: %s" % os.path.relpath(PREVIEW_DIR, ROOT))


if __name__ == "__main__":
    main()
