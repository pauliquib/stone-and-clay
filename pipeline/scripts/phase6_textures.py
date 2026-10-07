"""Fáze 6c – stažení PBR textur a HDRI z Poly Haven (CC0) do pipeline/assets/.

Textury: pipeline/assets/materials/ph_<id>/<id>_{diff,nor_gl,rough}_2k.jpg
HDRI:    pipeline/assets/hdrs/ph_<id>/<id>_4k.hdr
Poly Haven API: https://api.polyhaven.com/files/<id>
"""
import json
import os
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)          # pipeline/ – data/, assets/, renders/, logs/
GAME = os.path.dirname(ROOT)          # kořen repozitáře hry – geodata/, blend/
GEO = os.path.join(GAME, "geodata")
TEX = {
    # id: účel
    "clay_roof_tiles_02": "střechy – pálené tašky (barva se tónuje podle ortofota)",
    "grey_roof_tiles": "střechy – betonové/šedé krytiny",
    "beige_wall_001": "fasády – omítka (tónuje se)",
    "asphalt_02": "silnice – asfalt",
    "gravel_road": "polní cesty – štěrk",
    "bark_brown_02": "kůra stromů",
    "concrete_wall_008": "sokly / plochy dvorů",
}
HDRI = ["kloofendal_48d_partly_cloudy_puresky", "belfast_farmhouse"]
MAPS = {"Diffuse": "diff", "nor_gl": "nor_gl", "Rough": "rough"}


def fetch(url, path):
    if os.path.exists(path) and os.path.getsize(path) > 0:
        return
    os.makedirs(os.path.dirname(path), exist_ok=True)
    req = urllib.request.Request(url, headers={"User-Agent": "doubravy-okoli/1.0"})
    with urllib.request.urlopen(req, timeout=300) as r, open(path + ".part", "wb") as f:
        f.write(r.read())
    os.replace(path + ".part", path)


def api(path):
    req = urllib.request.Request("https://api.polyhaven.com/" + path, headers={"User-Agent": "doubravy-okoli/1.0"})
    with urllib.request.urlopen(req, timeout=60) as r:
        return json.load(r)


def main():
    info = {}
    for tid, purpose in TEX.items():
        files = api(f"files/{tid}")
        meta = api(f"info/{tid}")
        d = os.path.join(ROOT, "assets", "materials", f"ph_{tid}")
        for key, suffix in MAPS.items():
            url = files[key]["2k"]["jpg"]["url"]
            fetch(url, os.path.join(d, os.path.basename(url)))
        size_m = meta.get("dimensions", [2000, 2000])[0] / 1000.0
        info[tid] = {"purpose": purpose, "size_m": size_m, "dir": os.path.relpath(d, ROOT)}
        print("TEX", tid, f"{size_m:.1f} m", purpose)
    for hid in HDRI:
        try:
            files = api(f"files/{hid}")
        except Exception as e:
            print("HDRI missing", hid, e)
            continue
        url = files["hdri"]["4k"]["hdr"]["url"]
        d = os.path.join(ROOT, "assets", "hdrs", f"ph_{hid}")
        fetch(url, os.path.join(d, os.path.basename(url)))
        info["hdri"] = {"id": hid, "file": os.path.relpath(os.path.join(d, os.path.basename(url)), ROOT)}
        print("HDRI", hid)
        break
    json.dump(info, open(os.path.join(ROOT, "data", "textures.json"), "w"), indent=2, ensure_ascii=False)


if __name__ == "__main__":
    main()
