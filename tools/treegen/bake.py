"""Pečení impostorů a náhledů (M8.8) – jednoduchý softwarový „splatting“ v numpy (bez Blenderu, bez GPU).

Každý trojúhelník LOD0 se nahradí body (počet podle plochy a velikosti pixelu), body listí se prořežou alfou textury.
Pro pohled se body promítnou ortograficky a z-buffer vezme nejbližší bod v pixelu (lexsort). Kreslí se v SUPER×
rozlišení a zmenší průměrem (měkká alfa, bez schodů).

Impostor: IMP_VIEWS pohledů kolem osy Y (pohled k: kamera ve směru (sin θ, 0, cos θ), θ = k·2π/IMP_VIEWS, vpravo
= (cos θ, 0, −sin θ)). Snímek pokrývá x ∈ [−w, w] (w = největší vodorovná vzdálenost od osy) a y ∈ [y0, y1].
  barva  RGBA: listí = šedý jas (textura / LEAF_MEAN × okluze; zelenou dodá shader), kůra = skutečná barva × okluze;
               A = pokrytí
  normála RGBA: R, G = normála v rámci snímku (vpravo, nahoru) × 0,5 + 0,5; B = maska listí (1 list, 0 kůra);
               A = pokrytí jen kůrou (zimní silueta holých větví)
"""
import math

import numpy as np

from textures import LEAF_MEAN, sample

IMP_VIEWS = 8
SUPER = 2


def surface_points(lods, leaf_atlas, bark_atlas, grid, px_world, rng):
    """Body povrchu modelu (normalizované souřadnice). lods = (kůra arrays, listí arrays)."""
    out = []
    for kind, a in (("bark", lods[0]), ("leaf", lods[1])):
        if len(a["i"]) == 0:
            continue
        tri = a["i"].reshape(-1, 3)
        p0, p1, p2 = a["v"][tri[:, 0]], a["v"][tri[:, 1]], a["v"][tri[:, 2]]
        area = 0.5 * np.linalg.norm(np.cross(p1 - p0, p2 - p0), axis=1)
        cnt = np.clip(np.ceil(area / (px_world * px_world) * 2.5), 1, 4000).astype(np.int64)
        ti = np.repeat(np.arange(len(tri)), cnt)
        u = rng.random(len(ti))
        v = rng.random(len(ti))
        flip = u + v > 1.0
        u[flip] = 1.0 - u[flip]
        v[flip] = 1.0 - v[flip]
        w = 1.0 - u - v
        t = tri[ti]
        P = a["v"][t[:, 0]] * w[:, None] + a["v"][t[:, 1]] * u[:, None] + a["v"][t[:, 2]] * v[:, None]
        N = a["n"][t[:, 0]] * w[:, None] + a["n"][t[:, 1]] * u[:, None] + a["n"][t[:, 2]] * v[:, None]
        N /= np.maximum(np.linalg.norm(N, axis=1, keepdims=True), 1e-6)
        UV = a["uv"][t[:, 0]] * w[:, None] + a["uv"][t[:, 1]] * u[:, None] + a["uv"][t[:, 2]] * v[:, None]
        tile = a["uv2"][t[:, 0], 0].astype(np.int64)
        occ = (a["c"][t[:, 0], 3] * w + a["c"][t[:, 1], 3] * u + a["c"][t[:, 2], 3] * v) / 255.0
        if kind == "leaf":
            tex = _sample_multi(leaf_atlas, tile, grid, UV, False)
            keep = tex[:, 3] > 0.5
            lum = tex[:, :3].mean(1) / LEAF_MEAN
            col = np.stack([lum, lum, lum], 1) * (0.45 + 0.55 * occ)[:, None]
            out.append((P[keep], N[keep], col[keep], np.ones(keep.sum(), bool)))
        else:
            tex = _sample_multi(bark_atlas, tile, grid, UV, True)
            col = tex[:, :3] * (0.45 + 0.55 * occ)[:, None]
            out.append((P, N, col, np.zeros(len(P), bool)))
    P = np.concatenate([o[0] for o in out])
    N = np.concatenate([o[1] for o in out])
    C = np.concatenate([o[2] for o in out])
    L = np.concatenate([o[3] for o in out])
    return P, N, C, L


def _sample_multi(atlas, tile, grid, uv, wrap):
    res = np.zeros((len(uv), 4), np.float32)
    for tl in np.unique(tile):
        m = tile == tl
        res[m] = sample(atlas, int(tl), grid, uv[m], wrap)
    return res


def extents(v):
    w = float(np.max(np.hypot(v[:, 0], v[:, 2]))) * 1.02
    return w, float(min(0.0, v[:, 1].min())), float(v[:, 1].max()) * 1.01


def _zbuffer(px, py, depth, W):
    idx = py * W + px
    order = np.lexsort((-depth, idx))           # v pixelu nejbližší ke kameře (největší hloubka směrem ke kameře)
    idx_s = idx[order]
    first = np.ones(len(idx_s), bool)
    first[1:] = idx_s[1:] != idx_s[:-1]
    return idx_s[first], order[first]


def render_view(P, N, C, L, theta, w, y0, y1, res):
    """Jeden pohled → (barva RGBA, normála RGBA) o rozlišení res × res."""
    W = res * SUPER
    d = np.array([math.sin(theta), 0.0, math.cos(theta)])
    right = np.array([math.cos(theta), 0.0, -math.sin(theta)])
    up = np.array([0.0, 1.0, 0.0])
    x = P @ right
    y = P[:, 1]
    depth = P @ d
    px = np.clip(((x + w) / (2 * w) * W).astype(np.int64), 0, W - 1)
    py = np.clip(((y1 - y) / (y1 - y0) * W).astype(np.int64), 0, W - 1)
    col = np.zeros((W * W, 4), np.float32)
    nrm = np.zeros((W * W, 4), np.float32)
    pix, sel = _zbuffer(px, py, depth, W)
    col[pix, :3] = C[sel]
    col[pix, 3] = 1.0
    nx = N[sel] @ right
    ny = N[sel] @ up
    nrm[pix, 0] = nx * 0.5 + 0.5
    nrm[pix, 1] = ny * 0.5 + 0.5
    nrm[pix, 2] = L[sel].astype(np.float32)
    bark = ~L
    if bark.any():
        pixb, _ = _zbuffer(px[bark], py[bark], depth[bark], W)
        nrm[pixb, 3] = 1.0
    col = col.reshape(W, W, 4)
    nrm = nrm.reshape(W, W, 4)
    return _down(col), _down(nrm, alpha_from=col)


def _down(img, alpha_from=None):
    """SUPER× → 1×: alfa průměrem, barva vážená alfou (bez tmavých lemů)."""
    W = img.shape[0]
    r = W // SUPER
    a_src = img[..., 3] if alpha_from is None else alpha_from[..., 3]
    blk = img.reshape(r, SUPER, r, SUPER, 4)
    ab = a_src.reshape(r, SUPER, r, SUPER)
    wsum = ab.sum((1, 3))
    rgb = (blk[..., :3] * ab[..., None]).sum((1, 3)) / np.maximum(wsum, 1e-6)[..., None]
    a = blk[..., 3].mean((1, 3))
    return np.concatenate([rgb, a[..., None]], -1)


def bleed(img):
    """RGB prázdných pixelů z nejbližšího krytého (mipmapy impostorů bez černých lemů)."""
    from scipy import ndimage
    cov = img[..., 3] > 0.02
    if not cov.any():
        return img
    _, (iy, ix) = ndimage.distance_transform_edt(~cov, return_indices=True)
    out = img.copy()
    out[..., :3] = img[iy, ix, :3]
    return out


def bleed_normal(nrm, cov_alpha):
    from scipy import ndimage
    cov = cov_alpha > 0.02
    if not cov.any():
        return nrm
    _, (iy, ix) = ndimage.distance_transform_edt(~cov, return_indices=True)
    out = nrm.copy()
    out[..., :3] = nrm[iy, ix, :3]
    return out


def preview_shade(col, nrm, leaf_rgb=(0.24, 0.42, 0.14)):
    """Náhled impostoru „jako ve hře“: listí obarvené zeleně, jednoduché osvětlení z normály."""
    lr = np.array(leaf_rgb, np.float32)
    mask = nrm[..., 2:3]
    base = col[..., :3] * (1 - mask) + col[..., :1] * lr[None, None, :] * mask * 1.6
    nx = nrm[..., 0] * 2 - 1
    ny = nrm[..., 1] * 2 - 1
    nz = np.sqrt(np.clip(1 - nx * nx - ny * ny, 0, 1))
    light = np.clip(0.45 * nx + 0.6 * ny + 0.66 * nz, 0, 1) * 0.75 + 0.35
    rgb = np.clip(base * light[..., None], 0, 1)
    bg = np.array([0.82, 0.88, 0.95], np.float32)
    a = col[..., 3:4]
    return rgb * a + bg * (1 - a)
