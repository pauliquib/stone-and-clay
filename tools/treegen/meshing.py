"""Kostra → mesh (M8.8): větve jako zobecněné válce, listí jako karty; LOD0 a LOD1.

Plocha 0 = kůra, plocha 1 = listí (stejně jako DBT1 – materiály kůra / koruna).
Barvy vrcholů podle 00_PRINCIPY kap. 4 (shaders/include/wind.gdshaderinc):
  r = ohebnost (0 kmen u země … 1 konec tenké větve) × `ohebnost` tvaru
  g = fáze větve 1. řádu (hash 0..1)
  b = váha třepetání (0 dřevo, 1 list)
  a = okluze v koruně (0 jádro … 1 okraj)
UV: kůra – opakující se (u kolem obvodu, v podél větve, jednotky = dlaždice); listí – 0..1 v dlaždici (pata dole, v = 1).
UV2: x = číslo dlaždice v atlasu (kůra / listí podle plochy), y = 0.
Souřadnice se na konci dělí výškou stromu → model má výšku 1 (měřítko instance = výška v m, jako DBT1).
"""
import math

import numpy as np

BARK_TILE_M = 1.6            # m kůry na jednu dlaždici textury (dospělý strom)


def _hash01(i):
    x = (int(i) * 2654435761) & 0xFFFFFFFF
    x ^= x >> 15
    x = (x * 2246822519) & 0xFFFFFFFF
    x ^= x >> 13
    return (x & 0xFFFF) / 65535.0


class MeshBuf:
    def __init__(self):
        self.v, self.n, self.uv, self.uv2, self.c, self.i = [], [], [], [], [], []

    def nv(self):
        return len(self.v)

    def add(self, p, n, uv, uv2, c):
        self.v.append(p)
        self.n.append(n)
        self.uv.append(uv)
        self.uv2.append(uv2)
        self.c.append(c)
        return len(self.v) - 1

    def tri(self, a, b, c):
        self.i.extend([a, b, c])

    def ntri(self):
        return len(self.i) // 3

    def arrays(self, scale):
        if not self.v:
            return dict(v=np.zeros((0, 3), np.float32), n=np.zeros((0, 3), np.float32), uv=np.zeros((0, 2), np.float32),
                        uv2=np.zeros((0, 2), np.float32), c=np.zeros((0, 4), np.uint8), i=np.zeros(0, np.uint32))
        return dict(v=(np.array(self.v) / scale).astype(np.float32), n=np.array(self.n, np.float32),
                    uv=np.array(self.uv, np.float32), uv2=np.array(self.uv2, np.float32),
                    c=np.clip(np.array(self.c) * 255.0 + 0.5, 0, 255).astype(np.uint8), i=np.array(self.i, np.uint32))


def _chains(sk, r_cut):
    """Rozdělí kostru na řetězce (větve) – pokračování = dítě s největším poloměrem. Uzly tenčí než r_cut vynechá."""
    pos = np.array(sk.pos)
    chains = []
    stack = [(0, None)]
    while stack:
        start, from_parent = stack.pop()
        chain = [from_parent] if from_parent is not None else []
        i = start
        while True:
            chain.append(i)
            kids = [c for c in sk.children[i] if sk.r[c] >= r_cut]
            if not kids:
                break
            kids.sort(key=lambda c: -sk.r[c])
            for c in kids[1:]:
                stack.append((c, i))
            i = kids[0]
        if len(chain) >= 2:
            chains.append(chain)
    return chains, pos


def _simplify(chain, pos, tol_ang, max_len):
    """Vynechá uzly, kde se větev skoro neohýbá (úhel < tol_ang) a od posledního zachovaného není daleko."""
    if len(chain) <= 2:
        return chain
    out = [chain[0]]
    for k in range(1, len(chain) - 1):
        a = pos[out[-1]]
        b = pos[chain[k]]
        c = pos[chain[k + 1]]
        d1 = b - a
        d2 = c - b
        l1 = np.linalg.norm(d1)
        if l1 < 1e-6:
            continue
        cosang = float(np.dot(d1, d2) / max(l1 * np.linalg.norm(d2), 1e-9))
        if cosang < math.cos(tol_ang) or l1 + np.linalg.norm(d2) > max_len:
            out.append(chain[k])
    out.append(chain[-1])
    return out


def _sides(r, lod):
    if lod == 0:
        return 8 if r > 0.12 else (6 if r > 0.05 else (4 if r > 0.02 else 3))
    return 6 if r > 0.15 else (4 if r > 0.06 else 3)


def _flex(sk, i, flex_k, H):
    """Ohebnost r: kmen 0 (ohyb kmene řeší wind_bend z výšky), větev podle vzdálenosti od kmene."""
    if sk.trunk[i]:
        return 0.0
    cy, ry, R, y0 = sk.crown
    return float(np.clip((sk.off[i] / max(R * 1.1, 0.5)) ** 0.8, 0.05, 1.0) * flex_k)


def bark(sk, mb, tile, lod, r_cut, flex_k, H, tex_scale):
    chains, pos = _chains(sk, r_cut)
    tol = math.radians(10.0 if lod == 0 else 22.0)
    max_len = H * (0.12 if lod == 0 else 0.3)
    tile_m = BARK_TILE_M * tex_scale
    for ch in chains:
        ch = _simplify(ch, pos, tol, max_len)
        rmax = max(sk.r[j] for j in ch)
        ns = _sides(rmax, lod)
        # rámec paralelním přenosem
        t0 = pos[ch[1]] - pos[ch[0]]
        t0 /= max(np.linalg.norm(t0), 1e-9)
        ref = np.array([0.0, 0.0, 1.0]) if abs(t0[2]) < 0.9 else np.array([1.0, 0.0, 0.0])
        nvec = np.cross(t0, ref)
        nvec /= np.linalg.norm(nvec)
        vlen = 0.0
        rings = []
        circ = 2 * math.pi * rmax
        urep = max(1, int(round(circ / tile_m)))
        for k, j in enumerate(ch):
            if k < len(ch) - 1:
                t = pos[ch[k + 1]] - pos[j]
            else:
                t = pos[j] - pos[ch[k - 1]]
            tl = np.linalg.norm(t)
            t = t / max(tl, 1e-9)
            nvec = nvec - t * np.dot(nvec, t)
            nn = np.linalg.norm(nvec)
            nvec = nvec / nn if nn > 1e-6 else np.cross(t, ref) / max(np.linalg.norm(np.cross(t, ref)), 1e-9)
            bvec = np.cross(t, nvec)
            if k > 0:
                vlen += np.linalg.norm(pos[j] - pos[ch[k - 1]])
            # první uzel větve (rodič) má poloměr dítěte, ať větev nevyrůstá tlustá
            rr = sk.r[ch[1]] if (k == 0 and not sk.trunk[ch[1]]) else sk.r[j]
            if k == len(ch) - 1 and not sk.children[j]:
                rr *= 0.35
            col = (_flex(sk, j, flex_k, H), _hash01(sk.branch[ch[-1]] + 17), 0.0, _occl_bark(sk, pos[j]))
            ring = []
            for s in range(ns + 1):
                a = 2 * math.pi * s / ns
                d = nvec * math.cos(a) + bvec * math.sin(a)
                ring.append(mb.add(pos[j] + d * rr, d, (s / ns * urep, vlen / tile_m), (tile, 0.0), col))
            rings.append(ring)
        for k in range(len(rings) - 1):
            a, b = rings[k], rings[k + 1]
            for s in range(ns):
                mb.tri(a[s], b[s], a[s + 1])
                mb.tri(a[s + 1], b[s], b[s + 1])


def _occl_bark(sk, q):
    cy, ry, R, y0 = sk.crown
    if q[1] < y0:
        return 0.75
    e = math.sqrt((q[0] ** 2 + q[2] ** 2) / max(R, 0.1) ** 2 + ((q[1] - cy) / max(ry, 0.1)) ** 2)
    return float(np.clip(0.15 + 0.85 * e, 0.15, 1.0))


def cards(sk, mb, tile, cards_list, flex_k, H, size_mul, outward_mix):
    cy, ry, R, y0 = sk.crown
    center = np.array([0.0, cy, 0.0])
    for (base, d, nrm, s, node, wmul) in cards_list:
        s = s * size_mul
        hw = s * 0.5 * wmul                    # půlšířka karty (wmul = šířka / délka)
        side = np.cross(nrm, d)
        side /= max(np.linalg.norm(side), 1e-9)
        tip = base + d * s
        corners = [base - side * hw, base + side * hw, tip + side * hw, tip - side * hw]
        # při pohledu ze strany normály: rohy 0 vpravo dole, 1 vlevo dole, 2 vlevo nahoře, 3 vpravo nahoře;
        # Godot bere jako přední stranu trojúhelníky po směru hodinových ručiček
        uvs = [(1.0, 1.0), (0.0, 1.0), (0.0, 0.0), (1.0, 0.0)]
        fl = max(_flex(sk, node, flex_k, H), 0.35 * flex_k)
        ph = _hash01(sk.branch[node] + 17)
        idx = []
        for k, p in enumerate(corners):
            out = p - center
            out = out / max(np.linalg.norm(out), 1e-6)
            nn = nrm * (1.0 - outward_mix) + out * outward_mix       # měkké osvětlení koruny (normály ven z koruny)
            nn = nn / max(np.linalg.norm(nn), 1e-6)
            occ = _occl_bark(sk, p)
            tipw = 1.0 if k >= 2 else 0.55                            # pata karty se třepe míň
            idx.append(mb.add(p, nn, uvs[k], (tile, 0.0), (min(1.0, fl * (1.0 if k >= 2 else 0.9)), ph, tipw, occ)))
        mb.tri(idx[0], idx[1], idx[2])
        mb.tri(idx[0], idx[2], idx[3])


def build_lod(sk, p, H, tile, lod, budget, young):
    """Postaví LOD; poloměr ořezu větví a počet karet se zvětšují, dokud model nesplní rozpočet trojúhelníků."""
    flex_k = float(p.get("ohebnost", 1.0))
    tex_scale = 0.6 if young else 1.0
    conifer = str(p.get("model")) == "presleny"
    rng = np.random.default_rng(int(tile * 7919 + lod * 31 + (1 if young else 0)))
    cards_all = list(sk.cards)
    if lod == 0:
        r_cut = 0.012 if not conifer else 0.008
        keep = 1.0
        size_mul = 1.0
    else:
        umbrella = str(p.get("obalka")) == "destnik"
        r_cut = 0.045 if not conifer else (0.035 if umbrella else 0.5)   # smrk LOD1: jen kmen (větve schovají karty)
        keep = 0.28 if not conifer else 0.4
        size_mul = 1.75 if not conifer else 1.45
    order = rng.permutation(len(cards_all))
    # 1) kůra: ořez tenkých větví, dokud se nevejde do BARK_SHARE rozpočtu
    bark_budget = budget * (BARK_SHARE_CON if conifer else BARK_SHARE)
    for _ in range(40):
        bk = MeshBuf()
        bark(sk, bk, tile, lod, r_cut, flex_k, H, tex_scale)
        if bk.ntri() <= bark_budget:
            break
        r_cut *= 1.2
    # 2) karty: zbytek rozpočtu; když jich je víc, vybere se podmnožina a zvětší (stejná pokryvnost)
    nc = int(round(len(cards_all) * keep))
    room = max(0, (budget - bk.ntri()) // 2)
    if nc > room:
        size_mul *= math.sqrt(nc / max(room, 1)) ** 0.8
        nc = room
    chosen = [cards_all[k] for k in sorted(order[:nc])]
    lf = MeshBuf()
    cards(sk, lf, tile, chosen, flex_k, H, size_mul, 0.65 if not conifer else 0.45)
    return bk, lf


BARK_SHARE = 0.35             # podíl kůry na rozpočtu trojúhelníků (listnáč)
BARK_SHARE_CON = 0.45         # jehličnan (větve 1. řádu jsou vidět)
