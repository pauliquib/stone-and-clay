"""Kostra stromu (M8.8): listnáče kolonizací prostoru, jehličnany přeslenovým růstem.

Podle čeho (00_PRINCIPY kap. 8 „Generování stromů“):
  - **space colonization** (Runions, Lane, Prusinkiewicz 2007): body „pupenů“ v obálce koruny přitahují nejbližší uzly
    do dosahu `dosah`, uzel roste o `krok` ve směru průměru jednotkových vektorů k bodům (+ tropismy), body blíž než
    `zabiti` od uzlu zanikají; růst končí, když body dojdou nebo se nic nepohne.
  - **pipe model** (Shinozaki 1964): průřez rodiče = součet průřezů dětí, r_rodič^n = Σ r_dítě^n (n = PIPE_N),
    pak se poloměry škálují tak, aby kmen u paty odpovídal výčetní tloušťce z Näslundovy alometrie (dreviny.json).
  - **přeslenový růst** jehličnanů: kmen (vodič) s přesleny po ročních přírůstcích, délka větve 1. řádu podle výšky
    v koruně (kužel smrku, deštník borovice), úhel a převis podle druhu; větve 2. řádu nahrazují karty „větviček“.
  - vitalita (TreeEco 0..1): nízká → kratší přírůstky, méně bodů (řidší koruna), víc kroucení, odumřelé větve
    bez listí, výš nasazená (kratší) koruna, mírně nakloněný a křivý kmen.

Výstup `Skeleton`: uzly (poloha v metrech, rodič, poloměr, vzdálenost od kmene, číslo větve 1. řádu, odumřelý)
a místa karet listí (pata, směr, normála, velikost).
"""
import math

import numpy as np
from scipy.spatial import cKDTree

PIPE_N = 2.4                  # exponent pipe modelu (Runions 2007 uvádí 2–3)
TIP_R = 0.006                 # m – poloměr koncové větvičky před škálováním
MAX_ITER = 220
MIN_R = 0.005                 # m – nejtenčí větev po škálování
TIP_NODES = 2                 # listy rostou na uzlech nejvýš tolik uzlů od špičky větve


class Skeleton:
    def __init__(self):
        self.pos = []          # (x, y, z) m
        self.parent = []       # index rodiče, −1 kořen
        self.trunk = []        # True = uzel kmene (vodiče)
        self.dead = []         # True = odumřelá větev (bez listí)
        self.r = None          # poloměry (np.array) po `finish`
        self.off = None        # vzdálenost po větvi od kmene (m)
        self.branch = None     # id větve 1. řádu (fáze ve větru)
        self.cards = []        # (pata, směr, normála, velikost, uzel)
        self.crown = (0.0, 0.0, 1.0, 1.0)   # (cy, ry, rx, ...) obálka pro okluzi: střed y, poloosa y, poloměr

    def add(self, p, parent, trunk=False):
        self.pos.append(np.asarray(p, np.float64))
        self.parent.append(parent)
        self.trunk.append(trunk)
        self.dead.append(False)
        return len(self.pos) - 1

    def arrays(self):
        return np.array(self.pos), np.array(self.parent), np.array(self.trunk), np.array(self.dead)


def _rot_y(v, a):
    c, s = math.cos(a), math.sin(a)
    return np.array([c * v[0] + s * v[2], v[1], -s * v[0] + c * v[2]])


def _unit(v):
    n = np.linalg.norm(v)
    return v / n if n > 1e-9 else np.array([0.0, 1.0, 0.0])


# ------------------------------------------------------------------ obálky koruny

def _envelope_points(kind, n, H, y0, R, rng):
    """Body pupenů v obálce koruny (m). y0 = nasazení koruny, H = výška, R = poloměr koruny."""
    cy = 0.5 * (y0 + H)
    ry = 0.5 * (H - y0)
    pts = []
    blobs = None
    if kind == "nepravidelna":       # dub: sjednocení několika koulí v elipsoidu (nepravidelná, děravá koruna)
        nb = 7
        blobs = []
        for _ in range(nb):
            d = _unit(rng.normal(size=3) * np.array([1.0, 0.6, 1.0]))
            c = np.array([0.0, cy, 0.0]) + d * np.array([R * 0.55, ry * 0.45, R * 0.55])
            blobs.append((c, rng.uniform(0.45, 0.62) * R))
    tries = 0
    while len(pts) < n and tries < n * 60:
        tries += 1
        p = np.array([rng.uniform(-R, R), rng.uniform(y0, H), rng.uniform(-R, R)])
        t = (p[1] - y0) / max(H - y0, 1e-3)            # 0 nasazení … 1 vrchol
        rad = math.hypot(p[0], p[2])
        if kind == "kopule":         # buk: superelipsoid, plná horní polovina
            e = (rad / R) ** 2.4 + abs((p[1] - cy) / ry) ** (2.6 if p[1] > cy else 1.8)
            ok = e <= 1.0
        elif kind == "vejcita":      # habr / olše: vejčitá, nejširší ve třetině
            rr = R * math.sin(math.pi * min(max(t, 0.0), 1.0) ** 0.75)
            ok = rad <= rr
        elif kind == "previsla":     # bříza: úzká vejčitá, řídká uvnitř
            rr = R * math.sin(math.pi * min(max(t, 0.0), 1.0) ** 0.85)
            ok = rad <= rr and (rad > 0.35 * rr or rng.random() < 0.35)
        elif kind == "kulata":       # jabloň: široká kulatá, níž posazená
            e = (rad / R) ** 2 + ((p[1] - cy) / ry) ** 2
            ok = e <= 1.0
        elif kind == "nepravidelna":
            ok = any(np.linalg.norm(p - c) <= r for (c, r) in blobs)
        else:
            e = (rad / R) ** 2 + ((p[1] - cy) / ry) ** 2
            ok = e <= 1.0
        if ok:
            pts.append(p)
    return np.array(pts)


# ------------------------------------------------------------------ listnáče: kolonizace prostoru

def deciduous(p, H, young, vig, rng):
    sk = Skeleton()
    low = vig < 0.5
    y0 = H * float(p["koruna_od_mlady" if young else "koruna_od"])
    if low:
        y0 = min(H * 0.6, y0 + H * 0.08)              # nižší (kratší) koruna
    R = H * float(p["sirka"]) * (0.8 if young else 1.0) * (0.85 if low else 1.0)
    step = float(p["krok"]) * (0.6 if young else 1.0) * (0.8 if low else 1.0)
    infl = float(p["dosah"]) * step * (1.0 if not young else 1.2)
    kill = float(p["zabiti"]) * step
    trop = float(p["tropismus"])
    grav = float(p.get("gravitace", 0.0))
    gnarl = float(p["kroutivost"]) * (1.9 if low else 1.0)
    n_att = int(int(p["body"]) * (0.55 if young else 1.0) * (0.65 if low else 1.0))
    att = _envelope_points(str(p["obalka"]), n_att, H, y0, R, rng)

    # kmen: od paty k nasazení koruny a dál podle apikální dominance (vodič); u nízké vitality náklon a křivost
    lead_top = y0 + (H - y0) * float(p["vodic"]) * (0.85 if low else 1.0)
    lean = _unit(np.array([rng.normal(), 0.0, rng.normal()])) * (0.05 if low else 0.015)
    seg = max(step * 1.5, H / 22.0)
    prev = sk.add([0.0, 0.0, 0.0], -1, True)
    y = 0.0
    x = np.zeros(3)
    while y < lead_top - 1e-6:
        y = min(y + seg, lead_top)
        x = x + lean * seg + rng.normal(size=3) * np.array([1, 0, 1]) * gnarl * 0.05 * seg
        prev = sk.add([x[0], y, x[2]], prev, True)

    # kolonizace
    pos = np.array(sk.pos)
    alive = np.ones(len(att), bool)
    up = np.array([0.0, 1.0, 0.0])
    grew_from = {}
    for it in range(MAX_ITER):
        if not alive.any():
            break
        tree = cKDTree(pos)
        a_idx = np.nonzero(alive)[0]
        d, nn = tree.query(att[a_idx], distance_upper_bound=infl)
        ok = np.isfinite(d)
        if not ok.any():
            # žádný bod v dosahu (mezera v obálce): nejbližší uzel vyroste o krok k nejbližšímu bodu
            d_all, nn_all = tree.query(att[a_idx])
            k = int(np.argmin(d_all))
            ni = int(nn_all[k])
            q = pos[ni] + _unit(att[a_idx[k]] - pos[ni]) * step
            sk.add(q, ni)
            pos = np.array(sk.pos)
            continue
        dirs = {}
        for ai, ni in zip(a_idx[ok], nn[ok]):
            v = att[ai] - pos[ni]
            dirs.setdefault(int(ni), np.zeros(3))
            dirs[int(ni)] += v / max(np.linalg.norm(v), 1e-6)
        new = []
        for ni, v in dirs.items():
            dvec = _unit(v) + up * trop - up * grav * min(1.0, (pos[ni][1] - y0) / max(H - y0, 1.0) + 0.3) \
                + rng.normal(size=3) * gnarl
            dvec = _unit(dvec)
            q = pos[ni] + dvec * step
            key = (ni, tuple(np.round(q, 3)))
            if key in grew_from:                     # stejný růst jako minule = zaseklý uzel
                continue
            grew_from[key] = True
            new.append((q, ni))
        if not new:
            break
        for q, ni in new:
            sk.add(q, ni)
        pos = np.array(sk.pos)
        tree = cKDTree(pos[-len(new):])
        d2, _ = tree.query(att[a_idx], distance_upper_bound=kill)
        alive[a_idx[np.isfinite(d2)]] = False

    # převislé větvičky (bříza, gravitace): z koncových uzlů dolů visící výhony
    if grav > 0.2:
        _, par, _, _ = sk.arrays()
        nchild = np.bincount(par[par >= 0], minlength=len(sk.pos))
        tips = [i for i in range(len(sk.pos)) if nchild[i] == 0 and sk.pos[i][1] > y0 + 0.3 * (H - y0)]
        for i in tips:
            if rng.random() > 0.7:
                continue
            q = sk.pos[i]
            pr = i
            L = rng.uniform(0.8, 1.8) * (0.6 if young else 1.0)
            dvec = _unit(np.array([q[0], 0.0, q[2]]) * 0.3 + np.array([0, -1.0, 0]))
            for k in range(3):
                q = q + dvec * (L / 3.0)
                q[1] = max(q[1], 0.4 * H)
                pr = sk.add(q, pr)
    sk.crown = (0.5 * (y0 + H), 0.5 * (H - y0), R, y0)
    _finish(sk, p, H, young, vig, rng)
    _deciduous_cards(sk, p, H, young, vig, rng)
    return sk


# ------------------------------------------------------------------ jehličnany: přesleny

def conifer(p, H, young, vig, rng):
    sk = Skeleton()
    low = vig < 0.5
    pr = p["presleny"]
    y0 = H * float(p["koruna_od_mlady" if young else "koruna_od"])
    if low:
        y0 = min(H * 0.75, y0 + H * 0.1)
    R = H * float(p["sirka"]) * (0.85 if young else 1.0) * (0.85 if low else 1.0)
    ws = float(pr["rozestup"]) * (0.5 if young else 1.0) * (0.85 if low else 1.0)
    nb = int(pr["vetvi"])
    ang0 = math.radians(float(pr["uhel"]))
    droop = math.radians(float(pr["previs"]))
    gnarl = float(p["kroutivost"]) * (2.0 if low else 1.0)
    umbrella = str(p["obalka"]) == "destnik"

    lean = _unit(np.array([rng.normal(), 0.0, rng.normal()])) * (0.04 if low else 0.01)
    # kmen až do vrcholu (vodič), uzel na každém přeslenu a v půlce mezi přesleny (mezipřeslenové větve)
    trunk_nodes = []
    prev = sk.add([0.0, 0.0, 0.0], -1, True)
    trunk_nodes.append((0.0, prev, True))
    y = 0.0
    x = np.zeros(3)
    seg = max(ws, H / 30.0) * 0.5
    whorl = False
    while y < H - 1e-6:
        y = min(y + seg, H)
        whorl = not whorl
        x = x + lean * seg + rng.normal(size=3) * np.array([1, 0, 1]) * gnarl * 0.03 * seg
        prev = sk.add([x[0], y, x[2]], prev, True)
        trunk_nodes.append((y, prev, whorl))
    # přesleny
    phase = rng.uniform(0, 2 * math.pi)
    for (yy, ti, is_whorl) in trunk_nodes[1:-1]:
        base = sk.pos[ti]
        if not is_whorl:
            # mezipřeslenové větve: smrk 2 kratší, borovice nic
            if umbrella or yy < y0:
                continue
            t = (yy - y0) / max(H - y0, 1e-3)
            L = (R * ((1.0 - t) ** 0.9) + 0.1) * 0.55
            for b in range(2):
                a = phase + 1.1 + b * math.pi + rng.normal() * 0.4
                _branch(sk, ti, base, a, ang0, droop * 0.7, L, 2, gnarl, low and t < 0.25 and rng.random() < 0.4, rng)
            continue
        if yy < y0:
            # pod korunou: suché pahýly (jen u smrku, ne všude) – bez listí
            if not umbrella and yy > H * 0.08 and rng.random() < 0.35:
                a = phase + rng.uniform(0, 2 * math.pi)
                d = _rot_y(np.array([1.0, -0.2, 0.0]), a)
                n = sk.add(base + d * rng.uniform(0.3, 0.7) * (0.5 if young else 1.0), ti)
                sk.dead[n] = True
            continue
        t = (yy - y0) / max(H - y0, 1e-3)             # 0 nasazení … 1 vrchol
        if umbrella:     # borovice: deštník – nejdelší větve vysoko, plochý vrchol
            L = R * (0.35 + 0.65 * math.sin(math.pi * min(t * 0.9 + 0.08, 1.0))) * (1.0 - t ** 5)
        else:            # smrk: kužel
            L = R * ((1.0 - t) ** 0.9) + 0.12 * (0.5 if young else 1.0)
        L *= rng.uniform(0.85, 1.12)
        if L < 0.15:
            continue
        phase += 2.4                                   # zlatý úhel mezi přesleny
        for b in range(nb):
            if low and rng.random() < 0.18:
                continue                               # chybějící větve
            a = phase + b * 2 * math.pi / nb + rng.normal() * 0.25
            # úhel: horní větve víc vzhůru, dolní u smrku víc dolů
            elev = ang0 + (0.35 * (t - 0.5) if not umbrella else 0.15 * t)
            dead = low and t < 0.25 and rng.random() < 0.4
            nodes = _branch(sk, ti, base, a, elev, droop, L, 3, gnarl, dead, rng)
            if umbrella and not dead:
                # borovice: větve 2. řádu (šikmo vzhůru, do stran) se štětkami na koncích
                for k in (0, 1, 2):
                    if k >= len(nodes):
                        continue
                    for s in (-1, 1):
                        if rng.random() < 0.85:
                            _branch(sk, nodes[k], sk.pos[nodes[k]], a + s * rng.uniform(0.6, 1.0), math.radians(35.0),
                                    math.radians(10.0), L * rng.uniform(0.3, 0.45), 2, gnarl, False, rng)
    sk.crown = (0.5 * (y0 + H), 0.5 * (H - y0), R, y0)
    _finish(sk, p, H, young, vig, rng)
    _conifer_cards(sk, p, H, young, vig, rng)
    return sk


def _branch(sk, parent, base, azim, elev, droop, L, nseg, gnarl, dead, rng):
    """Větev jehličnanu: `nseg` segmentů, úhel `elev` nad vodorovnou, převis `droop` narůstá ke konci (∝ f²)."""
    prev_n = parent
    q = np.array(base, np.float64)
    out = []
    for k in range(nseg):
        f = (k + 1) / nseg
        e = elev + droop * f * f + rng.normal() * gnarl * 0.3
        d = _rot_y(np.array([math.cos(e), math.sin(e), 0.0]), azim)
        q = q + d * (L / nseg)
        prev_n = sk.add(q, prev_n)
        sk.dead[prev_n] = dead
        out.append(prev_n)
    return out


# ------------------------------------------------------------------ poloměry, vzdálenosti, větve

def _finish(sk, p, H, young, vig, rng):
    pos, par, trunk, dead = sk.arrays()
    n = len(pos)
    children = [[] for _ in range(n)]
    for i in range(1, n):
        if par[i] >= 0:
            children[par[i]].append(i)
    # pipe model odspodu (uzly jsou přidávané po rodičích → pořadí indexů je topologické)
    r = np.full(n, TIP_R)
    for i in range(n - 1, -1, -1):
        if children[i]:
            r[i] = sum(r[c] ** PIPE_N for c in children[i]) ** (1.0 / PIPE_N)
    # poloměr kmene u paty z Näslundovy alometrie (dbh v cm) – zhruba, ve výčetní výšce
    s = math.sqrt(max(H - 1.3, 0.05))
    a, b = 2.0, 0.16
    dbh = a * s / max(1.0 - b * s, 0.1) * float(p.get("tloustka", 1.0)) * (0.85 if young else 1.0)
    target = dbh / 200.0 * 1.1
    k = target / max(r[0], 1e-6)
    r *= k
    # jehličnany: kmen se k vrcholu lineárně zužuje (pipe model by dal příliš tenký kmen u řídkých přeslenů)
    if str(p.get("model")) == "presleny":
        for i in range(n):
            if trunk[i]:
                r[i] = max(r[i], target * (1.0 - pos[i][1] / H) ** 0.9 + 0.01)
    r = np.maximum(r, MIN_R)
    # vzdálenost od kmene po větvi + id větve 1. řádu
    off = np.zeros(n)
    br = np.zeros(n, np.int64)
    for i in range(1, n):
        q = par[i]
        if trunk[i]:
            off[i] = 0.0
            br[i] = 0
        else:
            off[i] = off[q] + np.linalg.norm(pos[i] - pos[q])
            br[i] = i if trunk[q] else br[q]
    # odumřelé větve listnáčů (nízká vitalita): část větví 1. řádu ve spodní koruně bez listí
    if vig < 0.5 and str(p.get("model")) != "presleny":
        roots = sorted(set(int(x) for x in br if x > 0))
        cy, ry, R, y0 = sk.crown
        budget = 0.2 * n                         # odumře nejvýš pětina uzlů, jen menší větve ve spodní koruně
        for b0 in roots:
            m = br == b0
            sz = int(m.sum())
            if pos[b0][1] < cy and sz < 0.12 * n and sz <= budget and rng.random() < 0.35:
                dead[m] = True
                budget -= sz
    # vzdálenost ke špičce v uzlech (0 = koncový uzel) – kde rostou listy
    tipd = np.zeros(n, np.int64)
    for i in range(n - 1, -1, -1):
        if children[i]:
            tipd[i] = min(tipd[c] for c in children[i]) + 1
    sk.tipd = tipd
    sk.r = r
    sk.off = off
    sk.branch = br
    sk.dead = list(dead)
    sk.children = children


def _occlusion(sk, q):
    cy, ry, R, y0 = sk.crown
    e = math.sqrt((q[0] ** 2 + q[2] ** 2) / max(R, 0.1) ** 2 + ((q[1] - cy) / max(ry, 0.1)) ** 2)
    return float(np.clip(0.2 + 0.8 * e, 0.15, 1.0))


def _deciduous_cards(sk, p, H, young, vig, rng):
    pos = np.array(sk.pos)
    cy, ry, R, y0 = sk.crown
    size = float(p["karta"]) * (0.7 if young else 1.0)
    dens = float(p["hustota_listi"]) * (0.65 if vig < 0.5 else 1.0)
    center = np.array([0.0, cy, 0.0])
    # listy na uzlech blízko konců větví (≤ TIP_NODES uzlů od špičky), ne na kmeni ani odumřelých větvích
    thin = np.nonzero((sk.tipd <= TIP_NODES) & ~np.array(sk.trunk) & ~np.array(sk.dead))[0]
    for i in thin:
        if rng.random() > dens:
            continue
        q = pos[i]
        par = sk.parent[i]
        d = _unit(q - pos[par]) if par >= 0 else np.array([0, 1.0, 0])
        out = _unit((q - center) * np.array([1.0, 0.6, 1.0]))
        dvec = _unit(d * 0.5 + out * 0.6 + rng.normal(size=3) * 0.35)
        if dvec[1] < -0.6:
            dvec = _unit(dvec + np.array([0, 0.8, 0]))
        nrm = _unit(np.cross(dvec, _unit(rng.normal(size=3))))
        if np.dot(nrm, out) < 0:
            nrm = -nrm
        s = size * rng.uniform(0.8, 1.2)
        sk.cards.append((q - dvec * s * 0.15, dvec, nrm, s, int(i), 1.0))


def _conifer_cards(sk, p, H, young, vig, rng):
    """Karty větviček podél větví 1. řádu: vodorovný „vějíř“ v rovině větve + menší kolmá karta (objem)."""
    pos = np.array(sk.pos)
    size = float(p["karta"]) * (0.65 if young else 1.0)
    dens = float(p["hustota_listi"]) * (0.7 if vig < 0.5 else 1.0)
    umbrella = str(p["obalka"]) == "destnik"
    for i in range(1, len(pos)):
        if sk.trunk[i] or sk.dead[i]:
            continue
        q0 = pos[sk.parent[i]]
        q1 = pos[i]
        if rng.random() > dens:
            continue
        L = np.linalg.norm(q1 - q0)
        d = _unit(q1 - q0)
        side = _unit(np.cross(np.array([0, 1.0, 0]), d))
        nrm = _unit(np.cross(d, side))                # ~ nahoru
        if nrm[1] < 0:
            nrm = -nrm
        if umbrella:
            # borovice: štětky na koncích výhonů (koncové uzly) a řidčeji podél, karty šikmo vzhůru + křížem
            tip = len(sk.children[i]) == 0
            if not tip and rng.random() > 0.7:
                continue
            up = _unit(d * 0.5 + np.array([0, 1.0, 0]))
            s = size * rng.uniform(0.85, 1.15) * (1.0 if tip else 0.75)
            sk.cards.append((q1 - up * s * 0.3, up, _unit(np.cross(up, side)), s, int(i), 1.0))
            sk.cards.append((q1 - up * s * 0.3, up, side, s * 0.9, int(i), 1.0))
        else:
            # smrk: plochý vějíř v rovině větve (postranní výhony) + šikmá karta křížem (objem)
            fan = min(max(L * 2.2, size * 0.6), size * 1.6)
            s = L * 1.25
            sk.cards.append((q0 - d * L * 0.1, d, nrm, s, int(i), fan / s))
            tilt = _unit(nrm * 0.45 + side * 0.9)
            sk.cards.append((q0, d, tilt, s * 0.95, int(i), fan * 0.7 / s))
            if rng.random() < 0.8:
                # svislý „závěs“ převislých výhonů pod větví – smrk je ze strany hustý, ne jen tenké patro
                hang = fan * 0.55
                sk.cards.append((q0 - np.array([0, hang * 0.35, 0]), d, side, s * 0.9, int(i), hang / s))
    # špička: svislá karta
    top = int(np.argmax(pos[:, 1]))
    s = size * (0.8 if not umbrella else 0.6)
    sk.cards.append((pos[top] - np.array([0, s * 0.85, 0]), np.array([0, 1.0, 0]), np.array([1.0, 0, 0]), s, top, 0.6))
    sk.cards.append((pos[top] - np.array([0, s * 0.85, 0]), np.array([0, 1.0, 0]), np.array([0, 0, 1.0]), s, top, 0.6))


def occlusion(sk, q):
    return _occlusion(sk, q)
