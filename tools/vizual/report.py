"""Vizuální validátor – souhrnný report: data.json + geometry.json + images.json → report.json, report.html,
contact_sheet.png. Stav PASS / WARN / FAIL celkem i po vrstvách; chybějící vrstva = SKIP (ne FAIL).

  python3 tools/vizual/report.py [--out=logs/vizual/latest]

Exit kód 1 při celkovém FAIL, jinak 0.
"""
import argparse
import datetime
import html
import json
import os
import sys

from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import GAME, RANK, load_json, save_json, worst  # noqa: E402

MAX_FINDINGS = 400            # nálezů v report.json / HTML celkem
THUMB = (320, 180)            # náhled v kontaktním archu
SHEET_COLS = 4
FONT_PATHS = ("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
              "/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf",
              "/usr/share/fonts/truetype/freefont/FreeSans.ttf")
COLORS = {"PASS": (46, 160, 67), "WARN": (219, 160, 0), "FAIL": (210, 50, 50), "SKIP": (130, 130, 130),
          "INFO": (90, 130, 200)}


def font(size):
    for p in FONT_PATHS:
        if os.path.exists(p):
            try:
                return ImageFont.truetype(p, size)
            except OSError:
                pass
    return ImageFont.load_default()


def layer_geometry(out):
    g = load_json(os.path.join(out, "geometry.json"))
    if g is None:
        return {"status": "SKIP", "note": "geometry.json chybí (engine neběžel)", "totals": {}, "findings": []}
    fs = [f for f in g.get("findings", []) if isinstance(f, dict)]
    totals = {s: sum(1 for f in fs if f.get("severity") == s) for s in ("FAIL", "WARN", "INFO")}
    st = "FAIL" if totals["FAIL"] else "WARN" if totals["WARN"] else "PASS"
    if g.get("status") in RANK:
        st = worst([st, g["status"]])
    checks = {}
    for f in fs:
        c = checks.setdefault(f.get("check", "?"), {"FAIL": 0, "WARN": 0, "INFO": 0})
        c[f.get("severity", "INFO")] = c.get(f.get("severity", "INFO"), 0) + 1
    for f in fs:
        f.setdefault("check", "?")
        if f.get("node") and "id" not in f:
            f["id"] = f["node"]
    return {"status": st, "totals": totals, "summary": g.get("stats", {}),
            "checks": {k: {"status": "FAIL" if v["FAIL"] else "WARN" if v["WARN"] else "PASS", "counts": v}
                       for k, v in checks.items()},
            "findings": fs}


def layer_gallery(out):
    """Nálezy galerie modelů z gallery.json (models[].findings)."""
    g = load_json(os.path.join(out, "gallery.json"))
    if g is None:
        return None
    fs = []
    for m in g.get("models", []):
        for f in m.get("findings", []) or []:
            if isinstance(f, dict):
                f = dict(f)
                f.setdefault("check", "?")
                f["id"] = m.get("id")
                fs.append(f)
    totals = {s: sum(1 for f in fs if f.get("severity") == s) for s in ("FAIL", "WARN", "INFO")}
    checks = {}
    for f in fs:
        c = checks.setdefault(f["check"], {"FAIL": 0, "WARN": 0, "INFO": 0})
        c[f.get("severity", "INFO")] = c.get(f.get("severity", "INFO"), 0) + 1
    return {"status": "FAIL" if totals["FAIL"] else "WARN" if totals["WARN"] else "PASS", "totals": totals,
            "summary": dict(g.get("stats", {}), models=len(g.get("models", []))), "findings": fs,
            "checks": {k: {"status": "FAIL" if v["FAIL"] else "WARN" if v["WARN"] else "PASS", "counts": v}
                       for k, v in checks.items()}}


def layer_engine(out, geo, views_present):
    es = load_json(os.path.join(out, "engine_status.json"))
    if es is None:
        return None
    if es.get("skipped"):
        return {"status": "SKIP", "note": es.get("reason", "engine vynechán"), "totals": {}, "findings": [],
                "summary": es}
    code = es.get("exit_code", 0)
    fs = []
    if code != 0 and geo["status"] == "SKIP" and not views_present:
        fs.append({"severity": "FAIL", "check": "engine", "msg": f"Godot skončil s kódem {code} a nevyrobil výstup "
                   f"(viz engine.log)"})
    elif code != 0:
        fs.append({"severity": "INFO", "check": "engine", "msg": f"Godot skončil s kódem {code} (výstupy jsou)"})
    summ = load_json(os.path.join(out, "summary.json"))
    if isinstance(summ, dict):
        es = dict(es, validator=summ.get("layers", summ))
    st = "FAIL" if any(f["severity"] == "FAIL" for f in fs) else "PASS"
    return {"status": st, "totals": {"FAIL": int(st == "FAIL"), "WARN": 0, "INFO": len(fs) - int(st == "FAIL")},
            "summary": es, "findings": fs}


def contact_sheet(out, images, path):
    """Mřížka náhledů s popisky (jméno, stav, jas, sytost)."""
    if not images:
        return False
    cols = min(SHEET_COLS, len(images))
    rows = (len(images) + cols - 1) // cols
    pad, lab = 8, 44
    W = cols * (THUMB[0] + pad) + pad
    H = rows * (THUMB[1] + lab + pad) + pad
    sheet = Image.new("RGB", (W, H), (24, 24, 28))
    d = ImageDraw.Draw(sheet)
    f1, f2 = font(15), font(12)
    for k, im in enumerate(images):
        x = pad + (k % cols) * (THUMB[0] + pad)
        y = pad + (k // cols) * (THUMB[1] + lab + pad)
        p = im["file"] if os.path.isabs(im["file"]) else os.path.join(out, im["file"])
        try:
            t = Image.open(p).convert("RGB")
            t.thumbnail(THUMB)
            sheet.paste(t, (x + (THUMB[0] - t.width) // 2, y + (THUMB[1] - t.height) // 2))
        except OSError:
            d.text((x + 10, y + 10), "nelze načíst", fill=(255, 120, 120), font=f2)
        col = COLORS.get(im["status"], (200, 200, 200))
        d.rectangle([x - 2, y - 2, x + THUMB[0] + 1, y + THUMB[1] + 1], outline=col, width=3)
        name = (im["group"] + "/" if im["group"] != "views" else "") + im["name"]
        d.text((x, y + THUMB[1] + 4), f"{name}  [{im['status']}]", fill=col, font=f1)
        m = im.get("metrics", {})
        extra = f"jas {m.get('mean_luma', 0):.2f}  sytost {m.get('saturation', 0):.2f}  obloha {m.get('sky_frac', 0):.2f}"
        pv = m.get("prev")
        if isinstance(pv, dict) and "ssim" in pv:
            extra += f"  SSIM {pv['ssim']:.2f}"
        d.text((x, y + THUMB[1] + 24), extra, fill=(200, 200, 200), font=f2)
    sheet.save(path)
    return True


def esc(v):
    return html.escape(str(v), quote=True)


def fmt_metrics(m, skip=("hist", "size", "prev", "examples")):
    parts = []
    for k, v in m.items():
        if k in skip or isinstance(v, (dict, list)):
            continue
        parts.append(f"{esc(k)}={esc(v)}")
    return " · ".join(parts)


def badge(st):
    return f'<span class="b b-{esc(st)}">{esc(st)}</span>'


def write_html(path, rep, layers, images, out, prev_dir, has_sheet):
    L = []
    L.append(f"""<!doctype html><html lang="cs"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1"><title>Vizuální validace</title>
<style>
:root{{--bg:#f6f6f4;--fg:#1d1d1f;--mut:#6b6b70;--card:#fff;--line:#e2e2e0;--pass:#2ea043;--warn:#c08a00;--fail:#d23232;--skip:#888;--info:#5a82c8}}
@media (prefers-color-scheme: dark){{:root{{--bg:#16161a;--fg:#e8e8ea;--mut:#9a9aa2;--card:#1f1f24;--line:#33333a}}}}
body{{margin:0;padding:16px;background:var(--bg);color:var(--fg);font:14px/1.45 system-ui,sans-serif}}
h1{{font-size:22px;margin:0 0 4px}} h2{{font-size:17px;margin:28px 0 8px}} .mut{{color:var(--mut)}}
table{{border-collapse:collapse;width:100%;background:var(--card)}} td,th{{border-bottom:1px solid var(--line);padding:5px 8px;text-align:left;vertical-align:top}}
th{{font-weight:600}} .wrap{{overflow-x:auto}}
.b{{display:inline-block;padding:1px 7px;border-radius:9px;color:#fff;font-size:12px;font-weight:600}}
.b-PASS{{background:var(--pass)}} .b-WARN{{background:var(--warn)}} .b-FAIL{{background:var(--fail)}} .b-SKIP{{background:var(--skip)}} .b-INFO{{background:var(--info)}}
.big{{font-size:20px;padding:4px 14px}}
.grid{{display:grid;grid-template-columns:repeat(auto-fill,minmax(300px,1fr));gap:12px}}
.card{{background:var(--card);border:1px solid var(--line);border-radius:8px;padding:8px}}
.card img{{width:100%;height:auto;display:block;border-radius:4px}} .pair{{display:grid;grid-template-columns:1fr 1fr;gap:4px}}
.small{{font-size:12px;color:var(--mut);word-break:break-word}}
.filt label{{margin-right:12px}}
</style></head><body>
<h1>Vizuální validace {badge(rep['status']).replace('class="b ', 'class="b big ')}</h1>
<div class="mut">{esc(rep['generated'])} · výstup <code>{esc(out)}</code></div>
<h2>Vrstvy</h2><div class="wrap"><table><tr><th>Vrstva</th><th>Stav</th><th>FAIL</th><th>WARN</th><th>INFO</th><th>Poznámka</th></tr>""")
    for name, ly in layers.items():
        t = ly.get("totals", {})
        L.append(f"<tr><td>{esc(name)}</td><td>{badge(ly['status'])}</td><td>{t.get('FAIL', 0)}</td>"
                 f"<td>{t.get('WARN', 0)}</td><td>{t.get('INFO', 0)}</td><td class='small'>{esc(ly.get('note', ''))}</td></tr>")
    L.append("</table></div>")

    # kontroly po vrstvách
    for name, ly in layers.items():
        ch = ly.get("checks")
        if not ch:
            continue
        L.append(f"<h2>Kontroly – {esc(name)}</h2><div class='wrap'><table><tr><th>Kontrola</th><th>Stav</th>"
                 "<th>F</th><th>W</th><th>I</th><th>Metriky / poznámka</th></tr>")
        for c, d in ch.items():
            cnt = d.get("counts", {})
            L.append(f"<tr><td>{esc(c)}</td><td>{badge(d.get('status', 'PASS'))}</td><td>{cnt.get('FAIL', 0)}</td>"
                     f"<td>{cnt.get('WARN', 0)}</td><td>{cnt.get('INFO', 0)}</td><td class='small'>"
                     f"{esc(d.get('note', ''))} {fmt_metrics(d.get('metrics', {}))}</td></tr>")
        L.append("</table></div>")
        if ly.get("summary"):
            L.append(f"<div class='small'>souhrn: {esc(json.dumps(ly['summary'], ensure_ascii=False)[:1500])}</div>")

    # nálezy
    L.append("<h2>Nálezy</h2><div class='filt small'>"
             "<label><input type=checkbox data-s=FAIL checked> FAIL</label>"
             "<label><input type=checkbox data-s=WARN checked> WARN</label>"
             "<label><input type=checkbox data-s=INFO> INFO</label></div>"
             "<div class='wrap'><table id=nal><tr><th>Stav</th><th>Vrstva</th><th>Kontrola</th><th>Id / pohled</th>"
             "<th>Zpráva</th><th>Pozice</th></tr>")
    for f in rep["findings"]:
        ident = f.get("id", f.get("view", f.get("node", "")))
        pos = f.get("pos")
        pos_s = ", ".join(f"{p:.1f}" if isinstance(p, (int, float)) else str(p) for p in pos) if pos else ""
        hide = " style='display:none'" if f["severity"] == "INFO" else ""
        L.append(f"<tr data-s='{esc(f['severity'])}'{hide}><td>{badge(f['severity'])}</td><td>{esc(f.get('layer', ''))}</td>"
                 f"<td>{esc(f.get('check', ''))}</td><td>{esc(ident if ident is not None else '')}</td>"
                 f"<td>{esc(f.get('msg', ''))}</td><td class='small'>{esc(pos_s)}</td></tr>")
    L.append("</table></div>")

    # pohledy a galerie
    for group, title in (("views", "Pohledy"), ("gallery", "Galerie modelů"), ("other", "Další snímky")):
        ims = [i for i in images if i["group"] == group]
        if not ims:
            continue
        L.append(f"<h2>{title}</h2><div class='grid'>")
        for i in ims:
            m = i.get("metrics", {})
            src = os.path.relpath(i["file"], out) if os.path.isabs(i["file"]) else i["file"]
            pv = m.get("prev") if isinstance(m.get("prev"), dict) else None
            img = f"<img src='{esc(src)}' alt='{esc(i['name'])}' loading=lazy>"
            if pv and pv.get("file"):
                psrc = os.path.relpath(pv["file"], out)
                img = (f"<div class='pair'><div><img src='{esc(psrc)}' alt='předtím' loading=lazy><div class='small'>předtím</div></div>"
                       f"<div>{img}<div class='small'>teď · SSIM {pv.get('ssim', 0):.2f} · ΔE {pv.get('delta_e', 0):.1f}</div></div></div>")
            meta = " · ".join(f"{k} {esc(i[k])}" for k in ("time", "weather", "date", "pos", "why", "fps",
                                                           "draw_calls", "category", "aabb_size") if k in i)
            prof = i.get("profile", {})
            L.append(f"<div class='card'><a href='{esc(src)}'>{img}</a><div><b>{esc(i['name'])}</b> {badge(i['status'])} "
                     f"<span class='small'>{esc(prof.get('tod', ''))}</span></div><div class='small'>{meta}</div>"
                     f"<div class='small'>{fmt_metrics(m)}</div></div>")
        L.append("</div>")
    if has_sheet:
        L.append("<h2>Kontaktní arch</h2><a href='contact_sheet.png'><img src='contact_sheet.png' style='max-width:100%' alt='kontaktní arch'></a>")
    L.append("""<script>
document.querySelectorAll('.filt input').forEach(function(cb){cb.addEventListener('change',function(){
 var on={};document.querySelectorAll('.filt input').forEach(function(c){on[c.dataset.s]=c.checked});
 document.querySelectorAll('#nal tr[data-s]').forEach(function(r){r.style.display=on[r.dataset.s]?'':'none'})})});
</script></body></html>""")
    with open(path, "w", encoding="utf-8") as fh:
        fh.write("\n".join(L))


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--out", default=os.path.join(GAME, "logs", "vizual", "latest"))
    a = ap.parse_args()
    out = os.path.abspath(a.out)
    prev_dir = os.path.join(os.path.dirname(out), "prev")

    layers = {}
    d = load_json(os.path.join(out, "data.json"))
    layers["data"] = d if d else {"status": "SKIP", "note": "data.json chybí", "totals": {}, "findings": []}
    geo = layer_geometry(out)
    im = load_json(os.path.join(out, "images.json"))
    images = (im or {}).get("images", [])
    eng = layer_engine(out, geo, any(i["group"] == "views" for i in images))
    if eng is not None:
        layers["engine"] = eng
    layers["geometry"] = geo
    gal = layer_gallery(out)
    if gal is not None:
        layers["gallery"] = gal
    if im:
        layers["images"] = im
        if not images:
            im["status"] = "SKIP"
            im.setdefault("note", "žádné snímky (views/, gallery/)")
    else:
        layers["images"] = {"status": "SKIP", "note": "images.json chybí", "totals": {}, "findings": []}

    findings = []
    for name, ly in layers.items():
        for f in ly.get("findings", []):
            f = dict(f)
            f["layer"] = name
            findings.append(f)
    order = {"FAIL": 0, "WARN": 1, "INFO": 2}
    findings.sort(key=lambda f: order.get(f.get("severity"), 3))
    status = worst([ly["status"] for ly in layers.values()])
    rep = {"status": status, "generated": datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
           "out": out, "prev": prev_dir if os.path.isdir(prev_dir) else None,
           "layers": {k: {"status": v["status"], "totals": v.get("totals", {}), "note": v.get("note", ""),
                          "summary": v.get("summary", {}),
                          "checks": {c: {"status": x.get("status"), "counts": x.get("counts", {})}
                                     for c, x in (v.get("checks") or {}).items()}}
                      for k, v in layers.items()},
           "totals": {s: sum(ly.get("totals", {}).get(s, 0) for ly in layers.values()) for s in ("FAIL", "WARN", "INFO")},
           "findings": findings[:MAX_FINDINGS], "findings_total": len(findings),
           "images": [{"name": i["name"], "group": i["group"], "file": i["file"], "status": i["status"],
                       "metrics": {k: v for k, v in i.get("metrics", {}).items() if k != "hist"}} for i in images]}
    save_json(os.path.join(out, "report.json"), rep)
    has_sheet = contact_sheet(out, images, os.path.join(out, "contact_sheet.png"))
    write_html(os.path.join(out, "report.html"), rep, layers, images, out, prev_dir, has_sheet)
    print(f"report: {status}  " + "  ".join(f"{k}={v['status']}" for k, v in layers.items())
          + f"  (FAIL {rep['totals']['FAIL']}, WARN {rep['totals']['WARN']})")
    print(f"  {os.path.join(out, 'report.html')}")
    return 1 if status == "FAIL" else 0


if __name__ == "__main__":
    sys.exit(main())
