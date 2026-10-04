#!/usr/bin/env python3
# Generátor jednoduchých textur interiéru (128×128 PNG) pro FuncGodot mapy.
# Omítka (wall), dřevěná podlaha (floor), strop (ceiling), dřevo nábytku (wood).
import random
from PIL import Image, ImageDraw

S = 128
import os
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets/textures/interiors")


def noise_img(base, var, seed):
    """Základní barva + jemný pixelový šum."""
    rnd = random.Random(seed)
    img = Image.new("RGB", (S, S))
    px = img.load()
    for y in range(S):
        for x in range(S):
            d = rnd.randint(-var, var)
            px[x, y] = tuple(max(0, min(255, c + d)) for c in base)
    return img


def wall():
    # světlá omítka: jemný šum + pár světlejších/tmavších fíglů
    img = noise_img((219, 204, 170), 7, 11)
    d = ImageDraw.Draw(img)
    rnd = random.Random(12)
    for _ in range(140):
        x, y = rnd.randrange(S), rnd.randrange(S)
        w, h = rnd.randrange(2, 9), rnd.randrange(1, 4)
        c = tuple(v + rnd.choice((-12, 10)) for v in (219, 204, 170))
        d.rectangle([x, y, x + w, y + h], fill=c)
    img.save(f"{OUT}/wall.png")


def ceiling():
    # strop: bělená omítka, skoro rovnoměrná
    img = noise_img((232, 228, 216), 5, 21)
    img.save(f"{OUT}/ceiling.png")


def planks(base, seed, plank_w, gap_col):
    # dřevěná prkna vodorovně: střídání odstínu po prknech + šum + spáry
    rnd = random.Random(seed)
    img = Image.new("RGB", (S, S))
    d = ImageDraw.Draw(img)
    y = 0
    i = 0
    while y < S:
        shade = rnd.randint(-14, 10)
        col = tuple(max(0, min(255, c + shade)) for c in base)
        d.rectangle([0, y, S, y + plank_w - 1], fill=col)
        # vlákna: vodorovné jemné linky jiného odstínu
        for _ in range(9):
            yy = y + rnd.randrange(1, plank_w - 1)
            x0 = rnd.randrange(S - 20)
            ln = rnd.randrange(8, 24)
            dc = tuple(max(0, min(255, c + rnd.choice((-18, 12)))) for c in col)
            d.line([x0, yy, x0 + ln, yy], fill=dc)
        # spára mezi prkny
        d.line([0, y, S, y], fill=gap_col)
        # krátké svislé spáry (spoje prken) – jinde v každém prkně
        xj = rnd.randrange(S)
        d.line([xj, y, xj, y + plank_w - 1], fill=gap_col)
        y += plank_w
        i += 1
    return img


def floor():
    planks((150, 108, 66), 31, 16, (96, 66, 38)).save(f"{OUT}/floor.png")


def wood():
    planks((128, 88, 52), 41, 32, (88, 58, 32)).save(f"{OUT}/wood.png")


wall()
ceiling()
floor()
wood()
print("hotovo")
