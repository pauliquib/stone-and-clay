#!/usr/bin/env python3
"""Kalibrace modelů přírody na realitu (M8.19A) – offline, bez hry, jen standardní knihovna.

Zreplikuje v Pythonu **jen klíčové rovnice** modelů M8 a prožene je normálovým rokem ze `Seasons`
(měsíční teploty, rozkmit, srážkové dny) a náhradou herního počasí (`Weather` – Markovův řetězec situací),
pak vypíše srovnání s referenčními hodnotami. Konstanty se **čtou z `.gd` souborů** (`static var` / `const`,
po M8.D jsou laditelné hodnoty `static var`) a z `data/*.json` – po úpravě kódu stačí skript pustit znovu.

Co se replikuje (soubor → co):
  scripts/priroda/seasons.gd    TEMP_MEAN, TEMP_RANGE, WET_DAYS, STORM_SHARE, FOLIAGE, GREEN (normálový rok)
  scripts/priroda/weather.gd    situace TYPES / NEXT / _weights, denní chod teploty, déšť (RAIN_MM_H), mlha, vítr,
                                rain_recent, drought, sníh (zjednodušeně: šum FastNoiseLite ≈ FBM hodnotový šum)
  scripts/eko/phenology.gd      GDD (BASE_C) od 1. 1., zimní chlad, rašení / kvetení / zbarvení (`_calc`)
  data/dreviny.json             prahy fenologie druhů
  scripts/eko/soil_water.gd     kyblík (AWC), SCS-CN s AMC, zachycení v korunách, tání degree-day, Hargreaves,
                                prosakování, lineární nádrže toku (rychlá + pomalá), normál Q_SPEC
  scripts/eko/microclimate.gd   inverze (`_step`), profil údolí (mlha, rosný bod), noční minima kotlina × hřbet
  scripts/priroda/soundscape.gd Dolbear (DOLBEAR_A, DOLBEAR_B) + data/zvuky_prirody.json (násobek `dolbear`)
  scripts/eko/crop_model.gd     `step_day` (RUE × PAR × zachycení × stres), fáze podle GDD; data/plodiny.json
  scripts/eko/habitat.gd        populace (`_pop_step`: pulz rození, úmrtnost, zima, plán lovu, auta), semenné roky

Zjednodušení proti hře (vědomá – výpis je orientační):
  - jedna reprezentativní buňka na povrch (orná / les / louka, AWC = SoilWater.SPINUP_AWC, skupina B, rovina),
    podpovrchový odtok jde rovnou do toku (ve hře po spádnici přes další buňky);
  - povodí potoka = směs 60 % orná, 25 % les, 15 % louka;
  - šum počasí (FastNoiseLite SIMPLEX FBM 5 oktáv) je nahrazen FBM hodnotovým šumem se stejnou frekvencí;
  - populace: kapacita K = předpokládané průměrné HSI × DENS_MAX (HSI zná jen hra – `--hsi`), silnice a krmelce průměrně.

Referenční hodnoty (vše ORIENTAČNĚ – OVĚŘIT, zaokrouhleno; tabulky REF_* níže):
  fenologie   ČHMÚ – fenologický atlas / fenologické fáze 1991–2020, nížiny a pahorkatiny střední Moravy (200–400 m):
              rašení = první listy (BBCH 11), kvetení = počátek až plné kvetení (BBCH 61–65), zbarvení = obecné
              podzimní zbarvení (~50 %, BBCH 94–95); den v roce
  voda        ČHMÚ hydrologické ročenky – malé toky Hané: specifický odtok ~3–5 l/s/km² (normál hry Q_SPEC),
              odtokový součinitel 0,15–0,25, nejvyšší průtoky III–IV (tání), nejnižší VIII–IX
  mikroklima  ČHMÚ / klimatologie údolních inverzí: dny s mlhou ~40–60 / rok (stanice; dno údolí ~45–75), noci s přízemní inverzí
              ~40–60 %, za jasné bezvětrné noci kotlina chladnější než hřbet o 3–6 K
  plodiny     ČSÚ – sklizně zemědělských plodin, okresy Olomouc / Prostějov / Přerov, průměr 2015–2024:
              pšenice ozimá ~6,8 t/ha, ječmen jarní ~5,6, řepka ~3,4, kukuřice na zrno ~8,5, slunečnice ~2,7,
              jetel 1. seč ~4 t/ha sena (ročně ~6,5), brambory ~30 t/ha; suchý rok ~ −15 až −25 %, vlhký ~ +5 až +15 %
  zvěř        ČSÚ / MZe myslivecká statistika (normované a skutečné stavy) – srnec 10–30 ks/100 ha,
              prase 2–15 (podle semenných roků), zajíc 5–30 (Haná) – jarní kmenové stavy
  Dolbear     Dolbear A. E. (1897): T(°F) = 50 + (N − 40)/4 → N = 7,2·T(°C) − 32 cvrknutí/min (cvrčkovec Oecanthus)

Použití:
  python3 tools/eco_calibrate.py               # výpis srovnání (10 let náhradního počasí, seed 1991)
  python3 tools/eco_calibrate.py --years 30 --seed 7 --hsi 0.5,0.35,0.4
  python3 tools/eco_calibrate.py --only fenologie,voda

Výstup: jen text na stdout (nic nezapisuje). Deterministický (seed). Kód: `tools/eco_calibrate.py` (M8.19A).
"""
from __future__ import annotations

import argparse
import ast
import json
import math
import os
import random
import re
import statistics
import sys

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))

# ============================================================================ reference (ORIENTAČNĚ – OVĚŘIT)
# den v roce: [rašení (BBCH 11), kvetení (BBCH 61–65), zbarvení ~50 %]; None = fáze se nesleduje
REF_PHENO = {
	"dub_zimni":     [119, 127, 291],
	"dub_letni":     [116, 125, 291],
	"buk":           [113, 121, 286],
	"habr":          [106, 108, 285],
	"lipa":          [111, 180, 279],
	"javor_klen":    [108, 118, 281],
	"jasan":         [122, 100, 283],
	"olse":          [105, 65, 296],
	"vrba_bila":     [98, 103, 293],
	"jiva":          [103, 82, 285],
	"briza":         [105, 108, 279],
	"tresen_ptaci":  [100, 104, 278],     # třešeň ptačí (Prunus avium)
	"akat":          [125, 143, 287],
	"topol":         [102, 85, 285],
	"smrk":          [130, 135, None],
	"borovice":      [120, 140, None],
	"modrin":        [96, 105, 294],
	"jedle":         [135, 140, None],
	"jablon":        [103, 115, 290],
	"hrusen":        [100, 107, 288],
	"svestka":       [100, 105, 285],
	"tresen":        [98, 102, 278],
	"orech":         [120, 125, 284],
}
PHENO_TOL_D = 7

# t/ha čerstvé hmoty (zrno 14 % vody, seno, hlízy) a podíl sušiny pro převod z g sušiny / m²
REF_YIELD = {
	"psenice":    (6.8, 0.86),
	"jecmen":     (5.6, 0.86),
	"repka":      (3.4, 0.91),
	"kukurice":   (8.5, 0.86),
	"slunecnice": (2.7, 0.91),
	"picniny":    (4.0, 0.85),       # 1. seč jetele (ročně 2–3 seče ~6,5 t/ha sena) – hra sklízí jednou
	"brambory":   (30.0, 0.21),
}
# scénáře roku pro plodiny: srážky × a teplota + (suchý ~ 2018 / 2015 na Hané ~430 mm, vlhký ~ 2010 ~700 mm)
DRY_P, DRY_T = 0.75, 1.0
WET_P, WET_T = 1.25, -0.3
REF_DRY = (0.75, 0.85)     # suchý rok / normál
REF_WET = (1.05, 1.15)     # vlhký rok / normál

REF_WATER = {
	"q_rel_mean": (0.8, 1.25),      # průměrný průtok / normál Q_SPEC (4 l/s/km² ~ 3–5)
	"runoff_coef": (0.15, 0.25),    # odtok / srážky
	"regime_ratio": (2.5, 6.0),     # nejvodnější / nejsušší měsíc
	"precip_mm": (520, 620),        # roční srážky střední Morava (normál 1991–2020)
}
REF_MICRO = {
	"fog_days": (45, 75),          # stanice v nížině 40–60 dní, dno údolí s potokem o něco víc
	"inv_nights_frac": (0.40, 0.60),
	"clear_dt_k": (3.0, 6.0),
	"mean_dt_k": (1.0, 3.0),
}
REF_POP = {"srnec": (10, 30), "divocak": (2, 15), "zajic": (5, 30)}
REF_DOLBEAR = (7.2, 32.0)

# ============================================================================ parser konstant z .gd

_DECL = re.compile(r"^\s*(?:static\s+var|const)\s+([A-Za-z_][A-Za-z0-9_]*)\s*(?::\s*[A-Za-z_][\w\[\], ]*)?\s*:?=\s*(.*)$")


def _strip_comment(line: str) -> str:
	out = []
	q = None
	for ch in line:
		if q:
			out.append(ch)
			if ch == q:
				q = None
			continue
		if ch in "\"'":
			q = ch
		elif ch == "#":
			break
		out.append(ch)
	return "".join(out)


def _to_py(expr: str, env: dict):
	s = expr.strip()
	if not s:
		raise ValueError
	s = re.sub(r"\btrue\b", "True", s)
	s = re.sub(r"\bfalse\b", "False", s)
	s = re.sub(r"\bnull\b", "None", s)
	try:
		return ast.literal_eval(s)
	except Exception:
		pass
	if re.search(r"[A-Za-z_]\w*\s*\(", s) and not re.search(r"\b(sqrt|exp|log|pow)\s*\(", s):
		raise ValueError
	names = {"PI": math.pi, "TAU": math.tau, "INF": math.inf, "sqrt": math.sqrt, "exp": math.exp, "log": math.log,
		"pow": pow, "True": True, "False": False, "None": None}
	names.update(env)
	return eval(s, {"__builtins__": {}}, names)   # jen čísla a jména konstant téhož souboru


def parse_gd(rel: str) -> dict:
	"""`static var` a `const` s literálem (čísla, pole, slovníky, jednoduchá aritmetika) → dict."""
	path = os.path.join(ROOT, rel)
	out: dict = {}
	with open(path, encoding="utf-8") as f:
		lines = f.read().split("\n")
	i = 0
	while i < len(lines):
		raw = lines[i]
		m = _DECL.match(raw) if not raw.startswith(("\t", " ")) else None
		i += 1
		if not m:
			continue
		name, rest = m.group(1), _strip_comment(m.group(2))
		depth = rest.count("[") + rest.count("{") + rest.count("(") - rest.count("]") - rest.count("}") - rest.count(")")
		while depth > 0 and i < len(lines):
			nxt = _strip_comment(lines[i])
			rest += " " + nxt.strip()
			depth += nxt.count("[") + nxt.count("{") + nxt.count("(") - nxt.count("]") - nxt.count("}") - nxt.count(")")
			i += 1
		rest = rest.rstrip().rstrip("\\").strip()
		try:
			out[name] = _to_py(rest, out)
		except Exception:
			pass
	return out


def load_json(rel: str) -> dict:
	with open(os.path.join(ROOT, rel), encoding="utf-8") as f:
		return json.load(f)


SEA = parse_gd("scripts/priroda/seasons.gd")
WX = parse_gd("scripts/priroda/weather.gd")
PH = parse_gd("scripts/eko/phenology.gd")
SW = parse_gd("scripts/eko/soil_water.gd")
MC = parse_gd("scripts/eko/microclimate.gd")
CM = parse_gd("scripts/eko/crop_model.gd")
HB = parse_gd("scripts/eko/habitat.gd")
SS = parse_gd("scripts/priroda/soundscape.gd")
DREV = load_json("data/dreviny.json")
PLOD = load_json("data/plodiny.json")
ZVUK = load_json("data/zvuky_prirody.json")
TABLES = {"seasons": SEA, "weather": WX, "phenology": PH, "soil_water": SW, "microclimate": MC, "crop_model": CM,
	"habitat": HB, "soundscape": SS}

# ============================================================================ pomocné (shodně s GDScript)


def clamp(v, a, b):
	return a if v < a else (b if v > b else v)


def lerp(a, b, t):
	return a + (b - a) * t


def smoothstep(e0, e1, x):
	if e1 == e0:
		return 0.0 if x < e0 else 1.0
	t = clamp((x - e0) / (e1 - e0), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


def curve(table, doy):
	if doy <= table[0][0]:
		return table[0][1]
	for i in range(1, len(table)):
		if doy <= table[i][0]:
			a, b = table[i - 1], table[i]
			return lerp(a[1], b[1], (doy - a[0]) / float(b[0] - a[0]))
	return table[-1][1]


def monthly(table, doy):
	m = math.fmod((doy - 15.0) / 30.44, 12.0)
	if m < 0:
		m += 12.0
	i = int(m)
	return lerp(table[i], table[(i + 1) % 12], m - i)


def date_txt(doy):
	if doy is None:
		return "  –  "
	md = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
	d = int(round(doy))
	m = 0
	while m < 11 and d > md[m]:
		d -= md[m]
		m += 1
	return "%2d. %2d." % (d, m + 1)


def extraterrestrial_mj(doy):
	phi = math.radians(SW["LAT_DEG"])
	dr = 1.0 + 0.033 * math.cos(math.tau * doy / 365.0)
	dec = 0.409 * math.sin(math.tau * doy / 365.0 - 1.39)
	ws = math.acos(clamp(-math.tan(phi) * math.tan(dec), -1.0, 1.0))
	return 24.0 * 60.0 / math.pi * 0.082 * dr * (ws * math.sin(phi) * math.sin(dec) + math.cos(phi) * math.cos(dec) * math.sin(ws))


def hargreaves(t_mean, t_range, doy):
	return max(SW["HARG_C"] * 0.408 * extraterrestrial_mj(doy) * (t_mean + SW["HARG_T"]) * math.sqrt(max(t_range, 0.0)), 0.0)


def sun_elev(doy, hour):
	decl = math.radians(23.44) * math.sin(math.tau * (284.0 + doy) / 365.0)
	utc = 2 if 87 <= doy <= 300 else 1
	noon = 12.0 + utc - 17.7 / 15.0
	ha = math.radians(15.0 * (hour - noon))
	lat = math.radians(49.1)
	return math.degrees(math.asin(clamp(math.sin(lat) * math.sin(decl) + math.cos(lat) * math.cos(decl) * math.cos(ha), -1.0, 1.0)))


def rain_season_k(doy):
	"""`Weather.rain_season_k`: úhrn na srážkový den podle normálu (PRECIP_MM / WET_DAYS) vůči ročnímu průměru."""
	if WX.get("_NO_SEASON_K"):
		return 1.0
	per = [SW["PRECIP_MM"][m] / max(SEA["WET_DAYS"][m], 1) for m in range(12)]
	return monthly(per, doy) / (sum(per) / 12.0)


class FbmNoise:
	"""Náhrada FastNoiseLite (FBM, 5 oktáv, gain 0,5, lacunarity 2): hodnotový šum ±1 se smoothstep interpolací."""

	def __init__(self, seed: int, freq: float):
		self.freq = freq
		self.r = random.Random(seed)
		self.tab = [self.r.uniform(-1.0, 1.0) for _ in range(4096)]

	def _v(self, x):
		i = math.floor(x)
		t = x - i
		t = t * t * (3 - 2 * t)
		a = self.tab[i % 4096]
		b = self.tab[(i + 1) % 4096]
		return a + (b - a) * t

	def get(self, x):
		x *= self.freq
		s, amp, norm = 0.0, 1.0, 0.0
		for o in range(5):
			s += self._v(x * (2 ** o) + o * 31.7) * amp
			norm += amp
			amp *= 0.5
		return s / norm * 1.3      # FastNoiseLite má po normalizaci širší rozptyl než čistý hodnotový šum


# ============================================================================ počasí (náhrada Weather)

class WeatherSim:
	"""Hodinová řada počasí podle `Weather._advance` (krok 20 min, výstup po hodinách)."""

	def __init__(self, seed: int):
		self.rng = random.Random(seed)
		self.n_show = FbmNoise(seed * 3 + 1, WX["SHOWER_NOISE_FREQ"])
		self.n_anom = FbmNoise(seed * 3 + 2, WX["ANOM_NOISE_FREQ"])
		self.kind = "polojasno"
		self.left = 5.0
		self.cloud, self.rain, self.fog, self.wind, self.temp = 0.4, 0.0, 0.0, 3.0, 0.0
		self.rain_recent, self.drought, self.snow = 0.2, 0.2, 0.0

	def weights(self, frm, doy, h):
		wet = monthly(SEA["WET_DAYS"], doy) / WX["WET_DAYS_REF"]
		storm = monthly(SEA["STORM_SHARE"], doy)
		green = curve(SEA["GREEN"], doy)
		ws = {}
		for k, w in WX["NEXT"].get(frm, {}).items():
			if k in ("dest", "prehanky"):
				w *= wet
			elif k == "bourka":
				w *= storm * WX["STORM_W"] * (WX["STORM_DAY_MULT"] if WX["STORM_FROM_H"] < h < WX["STORM_TO_H"] else WX["STORM_NIGHT_MULT"])
			elif k == "mlha":
				w *= (WX["FOG_W_BASE"] - green * WX["FOG_W_SUMMER"]) * (WX["FOG_W_NIGHT"] if h < WX["FOG_W_MORNING_H"] or h > WX["FOG_W_EVENING_H"] else WX["FOG_W_DAY"])
			elif k == "zatazeno":
				w *= WX["OVERCAST_W_WINTER"] - green
			elif k in ("jasno", "polojasno"):
				w *= WX["CLEAR_W_BASE"] + green * WX["CLEAR_W_SUMMER"]
			ws[k] = max(w, 0.0)
		return ws

	def pick(self, doy, h):
		ws = self.weights(self.kind, doy, h)
		tot = sum(ws.values())
		if tot <= 0:
			return "oblacno"
		r = self.rng.random() * tot
		for k, w in ws.items():
			r -= w
			if r <= 0:
				return k
		return list(ws)[-1]

	def temp_target(self, doy, h, t_h):
		base = monthly(SEA["TEMP_MEAN"], doy)
		rng_c = monthly(SEA["TEMP_RANGE"], doy) * (1.0 - WX["TEMP_CLOUD_DAMP"] * self.cloud)
		anom = self.n_anom.get(t_h / 24.0 * WX["TEMP_ANOM_RATE"]) * WX["TEMP_ANOM_C"]
		rise = clamp(WX["TEMP_MAX_H"] - WX["TEMP_MIN_H"], 0.5, 23.5)
		if WX["TEMP_MIN_H"] <= h <= WX["TEMP_MAX_H"]:
			f = -math.cos(math.pi * (h - WX["TEMP_MIN_H"]) / rise)
		else:
			f = math.cos(math.pi * math.fmod(h - WX["TEMP_MAX_H"] + 24.0, 24.0) / (24.0 - rise))
		return base + anom + 0.5 * rng_c * f - WX["TEMP_RAIN_COOL"] * self.rain - WX["TEMP_FOG_COOL"] * self.fog

	def year(self, y_index: int):
		"""Vrátí seznam 365 dnů, každý = seznam 24 hodin (dict)."""
		days = []
		dt = 1.0 / 3.0
		for d in range(365):
			doy = d + 1
			hours = []
			acc = None
			for k in range(72):
				h = k * dt
				t_h = (y_index * 365 + d) * 24.0 + h
				self.left -= dt
				if self.left <= 0:
					self.kind = self.pick(doy, h)
					hr = WX["TYPES"][self.kind]["hours"]
					self.left = self.rng.uniform(hr[0], hr[1])
				t = WX["TYPES"][self.kind]
				c_t, r_t, f_t, w_t = t["cloud"], t["rain"], t["fog"], t["wind"]
				if t.get("showers", False):
					on = smoothstep(WX["SHOWER_ON_LO"], WX["SHOWER_ON_HI"], self.n_show.get(t_h))
					r_t *= on
					c_t = lerp(c_t * WX["SHOWER_GAP_CLOUD"], 1.0, on)
					w_t *= WX["SHOWER_WIND_BASE"] + on * WX["SHOWER_WIND_GAIN"]
				green = curve(SEA["GREEN"], doy)
				if f_t > 0 and self.kind == "mlha":
					f_t *= 1.0 - smoothstep(WX["FOG_BURN_FROM_H"], WX["FOG_BURN_TO_H"], h) * (WX["FOG_BURN_BASE"] + green * WX["FOG_BURN_SUMMER"])
				if self.kind in ("jasno", "polojasno") and (h < WX["HAZE_MORNING_H"] or h > WX["HAZE_EVENING_H"]):
					f_t = max(f_t, WX["HAZE_FOG"] * (1.0 - green))
				self.cloud = lerp(self.cloud, c_t, 1.0 - math.exp(-dt / WX["TAU_CLOUD"]))
				self.rain = lerp(self.rain, r_t, 1.0 - math.exp(-dt / WX["TAU_RAIN"]))
				if self.rain < 0.005 and r_t == 0.0:
					self.rain = 0.0
				self.fog = lerp(self.fog, f_t, 1.0 - math.exp(-dt / WX["TAU_FOG"]))
				self.wind = lerp(self.wind, w_t * (WX["WIND_ANOM_BASE"] + WX["WIND_ANOM_AMP"] * self.n_anom.get(t_h * WX["WIND_ANOM_RATE"] + 50.0)),
					1.0 - math.exp(-dt / WX["TAU_WIND"]))
				self.rain_recent = clamp(self.rain_recent + self.rain * dt * WX["RAIN_RECENT_GAIN"] - dt / 24.0 * WX["RAIN_RECENT_DECAY_D"], 0.0, 1.0)
				self.drought = clamp(self.drought + dt / 24.0 * (WX["DROUGHT_BASE_D"] + max(self.temp - WX["DROUGHT_HOT_C"], 0.0) * WX["DROUGHT_HOT_D"])
					- self.rain * dt * WX["DROUGHT_RAIN"], 0.0, 1.0)
				self.temp = lerp(self.temp, self.temp_target(doy, h, t_h), 1.0 - math.exp(-dt / WX["TAU_TEMP"]))
				if acc is None:
					acc = {"t": 0.0, "c": 0.0, "r": 0.0, "f": 0.0, "w": 0.0, "mm": 0.0}
				acc["t"] += self.temp / 3.0
				acc["c"] += self.cloud / 3.0
				acc["r"] += self.rain / 3.0
				acc["f"] += self.fog / 3.0
				acc["w"] += self.wind / 3.0
				acc["mm"] += self.rain * WX["RAIN_MM_H"] * rain_season_k(doy) * dt
				if k % 3 == 2:
					acc["h"] = int(h)
					acc["rr"] = self.rain_recent
					acc["dr"] = self.drought
					hours.append(acc)
					acc = None
			days.append(hours)
		return days


def make_years(n_years: int, seed: int):
	sim = WeatherSim(seed)
	sim.year(-1)                     # rozběh (zahodí se)
	return [sim.year(y) for y in range(n_years)]


def clim_year():
	"""Normálový rok jako ve hře při rozběhu: teplota z TEMP_MEAN/TEMP_RANGE, srážky PRECIP_MM rozdělené na WET_DAYS."""
	days = []
	md = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
	doy = 0
	for m in range(12):
		wd = SEA["WET_DAYS"][m]
		p_day = SW["PRECIP_MM"][m] / max(wd, 1)
		step = md[m] / max(wd, 1)
		wet = {int(i * step + step / 2) for i in range(wd)}
		for d in range(md[m]):
			doy += 1
			tm = monthly(SEA["TEMP_MEAN"], doy)
			tr = monthly(SEA["TEMP_RANGE"], doy)
			hours = []
			for h in range(24):
				rise = clamp(WX["TEMP_MAX_H"] - WX["TEMP_MIN_H"], 0.5, 23.5)
				if WX["TEMP_MIN_H"] <= h <= WX["TEMP_MAX_H"]:
					f = -math.cos(math.pi * (h - WX["TEMP_MIN_H"]) / rise)
				else:
					f = math.cos(math.pi * math.fmod(h - WX["TEMP_MAX_H"] + 24.0, 24.0) / (24.0 - rise))
				rain_mm = p_day / 6.0 if (d in wet and 12 <= h < 18) else 0.0
				hours.append({"t": tm + 0.5 * tr * f * 0.8, "c": 0.9 if d in wet else 0.5, "r": rain_mm / WX["RAIN_MM_H"], "f": 0.0,
					"w": 3.5, "mm": rain_mm, "h": h, "rr": 0.3, "dr": 0.3})
			days.append(hours)
	return days


def day_mean(day):
	return sum(h["t"] for h in day) / len(day)


# ============================================================================ fenologie


def pheno_species():
	out = []
	for s in DREV["druhy"]:
		f = s.get("fenologie", {}) or {}
		conifer = s.get("typ", "") == "jehlicnan"
		ever = bool(f.get("stalezeleny", False))
		out.append({
			"id": s["id"], "ever": ever, "rasi": float(f.get("rasi_gdd", 120.0)), "plne": float(f.get("plne_olisteni_gdd", 260.0)),
			"kvete": float(f.get("kvete_gdd", -1.0)), "zden": float(f.get("zbarveni_den", 275.0)),
			"zchlad": -1.0 if ever else float(f.get("zbarveni_chlad", -1.0 if conifer else 36.0)),
			"opad": float(f.get("opad_dni", 25.0)), "chlad": float(f.get("chlad_dni", 0.0)),
		})
	return out


def pheno_dates(prev_temps, temps):
	"""Data fází per druh pro rok `temps` (365 denních průměrů); zimní chlad od 1. 11. předchozího roku."""
	chill = 0
	for doy in range(305, 366):
		if prev_temps[doy - 1] < PH["CHILL_BELOW_C"]:
			chill += 1
	gsum = 0.0
	warm = 0
	aut = 0.0
	res = {s["id"]: [None, None, None] for s in SP}
	gs_by_day = []
	chill_by_day = []
	for doy in range(1, 366):
		t = temps[doy - 1]
		gsum += max(0.0, t - PH["BASE_C"])
		if doy == 182:
			chill = 0
		if (doy >= PH["CHILL_FROM_DOY"] or doy < 182) and t < PH["CHILL_BELOW_C"]:
			chill += 1
		if doy >= PH["AUT_FROM_DOY"]:
			aut += max(0.0, PH["AUT_BASE_C"] - t)
		gs_by_day.append(gsum)
		chill_by_day.append(chill)
		for s in SP:
			r = res[s["id"]]
			rasi = s["rasi"]
			if s["chlad"] > 0:
				rasi *= 1.0 + PH["CHILL_PENALTY"] * clamp(1.0 - chill / s["chlad"], 0.0, 1.0)
			if r[0] is None and gsum > rasi:
				r[0] = doy
			if r[1] is None and s["kvete"] > 0 and gsum >= s["kvete"]:
				r[1] = doy
			if r[2] is None and not s["ever"] and s["zchlad"] >= 0:
				dd = aut + PH["PHOTO_KD"] * max(0.0, doy - s["zden"])
				if (dd - s["zchlad"]) / max(PH["AUT_SPAN_KD"], 1.0) >= 0.5:
					r[2] = doy
	return res


SP = pheno_species()


def run_pheno(years, clim):
	ct = [day_mean(d) for d in clim]
	clim_res = pheno_dates(ct, ct)
	sims = []
	prev = ct
	for y in years:
		t = [day_mean(d) for d in y]
		sims.append(pheno_dates(prev, t))
		prev = t
	print("\n== Fenologie (GDD základ %.0f °C, prahy z data/dreviny.json; den v roce, tolerance ±%d dní) ==" % (PH["BASE_C"], PHENO_TOL_D))
	print("   model K = normálový rok (rozběh hry), model P = medián náhradního počasí (%d let), ref = ČHMÚ orientačně" % len(years))
	print("   %-13s | %-26s | %-26s | %-26s" % ("druh", "rašení  K / P / ref", "kvetení  K / P / ref", "zbarvení 50 %  K / P / ref"))
	bad = []
	for s in SP:
		sid = s["id"]
		ref = REF_PHENO.get(sid, [None, None, None])
		cells = []
		for k in range(3):
			kv = clim_res[sid][k]
			vals = [r[sid][k] for r in sims if r[sid][k] is not None]
			pv = statistics.median(vals) if vals else None
			rf = ref[k]
			flag = " "
			if rf is not None and pv is not None and abs(pv - rf) > PHENO_TOL_D:
				flag = "!"
				bad.append((sid, ["rašení", "kvetení", "zbarvení"][k], kv, pv, rf))
			cells.append("%s%4s/%4s/%4s" % (flag, kv if kv else "–", int(pv) if pv else "–", rf if rf else "–"))
		print("   %-13s | %-26s | %-26s | %-26s" % (sid, cells[0], cells[1], cells[2]))
	gdd_mean_clim = sum(max(0.0, t - PH["BASE_C"]) for t in ct)
	gdd_sim = statistics.mean(sum(max(0.0, day_mean(d) - PH["BASE_C"]) for d in y) for y in years)
	print("   roční GDD>5: normál %.0f, náhradní počasí %.0f (ref. střední Morava ~1 900–2 100)" % (gdd_mean_clim, gdd_sim))
	print("   ! = model P mimo toleranci (%d položek)" % len(bad))
	return bad


# ============================================================================ voda (kyblík + toky)

CLS_ORNA, CLS_LES, CLS_LOUKA = 1, 3, 0


class Cell:
	def __init__(self, cls, forest, awc, perm=0.5):
		self.cls = cls
		self.fo = forest
		self.a = awc
		self.perm = perm
		grp = 0 if perm >= SW["HSG_A"] else (1 if perm >= SW["HSG_B"] else (2 if perm >= SW["HSG_C"] else 3))
		cn = lerp(SW["CN2"][cls][grp], SW["CN2"][3][grp], forest)
		self.s2 = 25400.0 / cn - 254.0
		cn1 = cn / (2.281 - 0.01281 * cn)
		cn3 = min(cn / (0.427 + 0.00573 * cn), 99.0)
		self.s1 = 25400.0 / cn1 - 254.0
		self.s3 = 25400.0 / cn3 - 254.0
		self.w = awc * SW["SPINUP_W0"]
		self.swe = 0.0


def scs(p, s):
	ia = SW["SCS_LAMBDA"] * s
	if p <= ia:
		return 0.0
	return (p - ia) * (p - ia) / (p - ia + s)


class WaterSim:
	"""Hodinový krok `SoilWater._step_chunk` pro 3 buňky + lineární nádrže potoka (`_route_streams`)."""

	MIX = {CLS_ORNA: 0.60, CLS_LES: 0.25, CLS_LOUKA: 0.15}

	def __init__(self, area_m2=3.0e6, p_mult=1.0, t_add=0.0):
		a = SW["SPINUP_AWC"]
		self.cells = {CLS_ORNA: Cell(CLS_ORNA, 0.0, a), CLS_LES: Cell(CLS_LES, 1.0, a), CLS_LOUKA: Cell(CLS_LOUKA, 0.0, a)}
		self.area = area_m2
		self.kq = SW["K_QUICK_H"]["stream"]
		self.ks = SW["K_SLOW_H"]["stream"]
		self.qn = SW["Q_SPEC"] * area_m2
		self.sq = 0.0
		self.ss = self.qn * self.ks * 3600.0 * 0.8
		self.frost = 0.0
		self.event_p = 0.0
		self.dry_h = 0.0
		self.p_mult = p_mult
		self.t_add = t_add
		self.turb = 0.0

	def hour(self, doy, hr):
		p = hr["mm"] * self.p_mult
		temp = hr["t"] + self.t_add
		cloud = hr["c"]
		rain_p = p if temp >= WX["SNOW_BELOW"] else 0.0
		snow_p = p - rain_p
		event0 = self.event_p
		if p > SW["EVENT_MIN_MM"]:
			self.event_p += p
			self.dry_h = 0.0
		else:
			self.dry_h += 1.0
			if self.dry_h >= SW["EVENT_GAP_H"]:
				self.event_p = 0.0
		mean_swe = sum(c.swe * self.MIX[k] for k, c in self.cells.items())
		if temp < 0.0:
			self.frost += -temp * SW["FROST_RATE"] * (SW["SNOW_INSULATE_K"] if mean_swe > SW["SNOW_INSULATE_MM"] else 1.0)
		else:
			self.frost -= temp * SW["THAW_RATE"]
		self.frost = clamp(self.frost, 0.0, 1.0)
		tr = monthly(SEA["TEMP_RANGE"], doy) * (1.0 - SW["PET_CLOUD_DAMP"] * cloud)
		pet = hargreaves(temp, tr, doy) / 24.0
		fol = lerp(SW["INTERCEPT_LEAFLESS"], 1.0, curve(SEA["FOLIAGE"], doy))
		kc_orna = SW["KC_ARABLE_BASE"] + SW["KC_ARABLE_GREEN"] * curve(SEA["GREEN"], doy)
		in_q = 0.0
		in_s = 0.0
		out = {}
		for k, c in self.cells.items():
			p_r, p_s = rain_p, snow_p
			if c.fo > 0 and p_r + p_s > 0:
				free = max(SW["INTERCEPT_MM"] * c.fo * fol - event0, 0.0)
				ic = min(p_r, free)
				p_r -= ic
				p_s -= min(p_s, free - ic)
			sw = c.swe + p_s
			melt = 0.0
			if sw > 0 and temp > 0:
				ddf = SW["DDF_MM"] * lerp(1.0, SW["MELT_FOREST"], c.fo)
				melt = min(sw, ddf * temp / 24.0 + SW["RAIN_ON_SNOW"] * p_r * temp)
				sw -= melt
			c.swe = sw
			p_in = p_r + melt
			mi = c.w / c.a
			if mi < SW["AMC_MID"]:
				s = lerp(c.s1, c.s2, smoothstep(SW["AMC_DRY"], SW["AMC_MID"], mi))
			else:
				s = lerp(c.s2, c.s3, smoothstep(SW["AMC_MID"], SW["AMC_WET"], mi))
			s = lerp(s, SW["S_FROZEN_MM"], self.frost)
			q = 0.0
			if p_in > 0:
				q = clamp(scs(event0 + p_in, s) - scs(event0, s), 0.0, p_in)
			wi = c.w + p_in - q
			kc0 = kc_orna if SW["KC"][c.cls] < 0 else SW["KC"][c.cls]
			kc = lerp(kc0, SW["KC_FOREST"], c.fo)
			et = pet * kc * min(wi / (SW["ET_BETA_FRAC"] * c.a), 1.0)
			if sw > SW["ET_SNOW_MM"]:
				et *= SW["ET_SNOW"]
			wi = max(wi - et, 0.0)
			o = 0.0
			if wi > c.a:
				o = wi - c.a
				wi = c.a
			thr = SW["DRAIN_FROM"] * c.a
			if wi > thr:
				d = min((wi - thr) * SW["K_DRAIN_H"] * c.perm, wi - thr)
				wi -= d
				o += d
			c.w = wi
			rech = o * SW["GW_FRAC"] * (SW["GW_PERM_BASE"] + c.perm)
			mix = self.MIX[k]
			in_q += (q + o - rech) * mix
			in_s += rech * mix
			out[k] = (q, et, o)
		a = self.area * 0.001
		self.sq += in_q * a
		self.ss += in_s * a
		oq = self.sq * (1.0 - math.exp(-1.0 / self.kq))
		os_ = self.ss * (1.0 - math.exp(-1.0 / self.ks))
		self.sq -= oq
		self.ss -= os_
		qt = (oq + os_) / 3600.0
		rel = qt / self.qn
		self.turb = max(smoothstep(SW["TURB_FROM"], SW["TURB_FULL"], rel), self.turb * math.exp(-1.0 / SW["TURB_TAU_H"]))
		return rel, out


def run_water(years, p_mult=1.0, t_add=0.0, quiet=False):
	ws = WaterSim(p_mult=p_mult, t_add=t_add)
	for d, day in enumerate(years[0]):          # rozběh: jeden rok navíc
		for hr in day:
			ws.hour(d + 1, hr)
	res = []
	for y in years:
		daily_rel, moist, p_sum, q_sum, et_sum, turb_days, dry_days = [], {k: [] for k in ws.cells}, 0.0, 0.0, 0.0, 0, 0
		for d, day in enumerate(y):
			rs = []
			tmax_turb = 0.0
			for hr in day:
				rel, out = ws.hour(d + 1, hr)
				rs.append(rel)
				tmax_turb = max(tmax_turb, ws.turb)
				p_sum += hr["mm"] * p_mult
				et_sum += sum(out[k][1] * ws.MIX[k] for k in out)
			r = sum(rs) / len(rs)
			daily_rel.append(r)
			q_sum += r * ws.qn * 86400.0 / ws.area * 1000.0
			for k, c in ws.cells.items():
				moist[k].append(c.w / c.a)
			if tmax_turb > 0.3:
				turb_days += 1
			if r < SW["DRY_REL"]:
				dry_days += 1
		res.append({"rel": daily_rel, "moist": moist, "p": p_sum, "q_mm": q_sum, "et": et_sum, "turb": turb_days, "dry": dry_days})
	return res


def report_water(wr, clim_wr):
	print("\n== Voda (SoilWater: kyblík AWC %.0f mm, SCS-CN, Hargreaves; potok 3 km², Q_SPEC %.1f l/s/km²) ==" % (SW["SPINUP_AWC"], SW["Q_SPEC"] * 1e9))
	md = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
	bad = []

	def stats(rs, label):
		p = statistics.mean(r["p"] for r in rs)
		q = statistics.mean(r["q_mm"] for r in rs)
		et = statistics.mean(r["et"] for r in rs)
		allrel = [x for r in rs for x in r["rel"]]
		mean_rel = statistics.mean(allrel)
		mon = []
		i = 0
		for m in range(12):
			mon.append(statistics.mean(x for r in rs for x in r["rel"][i:i + md[m]]))
			i += md[m]
		ratio = max(mon) / max(min(mon), 1e-6)
		print("   %-22s srážky %4.0f mm, výpar %4.0f mm, odtok %4.0f mm (součinitel %.2f), Q/normál průměr %.2f, min %.2f, max %.1f"
			% (label, p, et, q, q / max(p, 1), mean_rel, min(allrel), max(allrel)))
		print("   %-22s měsíce Q/normál: %s" % ("", " ".join("%.2f" % v for v in mon)))
		print("   %-22s nejvodnější %d., nejsušší %d. měsíc, poměr %.1f; dní s kalnou vodou %.0f / rok, vyschlé koryto %.0f dní / rok"
			% ("", mon.index(max(mon)) + 1, mon.index(min(mon)) + 1, ratio, statistics.mean(r["turb"] for r in rs), statistics.mean(r["dry"] for r in rs)))
		return p, q / max(p, 1), mean_rel, ratio

	stats(clim_wr, "normálový rok:")
	p, coef, mean_rel, ratio = stats(wr, "náhradní počasí:")
	print("   reference: srážky %d–%d mm, odtok. součinitel %.2f–%.2f, Q/normál %.2f–%.2f, poměr měsíců %.1f–%.1f (max III–IV, min VIII–IX)"
		% (REF_WATER["precip_mm"] + REF_WATER["runoff_coef"] + REF_WATER["q_rel_mean"] + REF_WATER["regime_ratio"]))
	for name, v, key in (("srážky z Weather", p, "precip_mm"), ("odtokový součinitel", coef, "runoff_coef"),
			("Q / normál", mean_rel, "q_rel_mean"), ("poměr měsíců", ratio, "regime_ratio")):
		lo, hi = REF_WATER[key]
		if not (lo * 0.8 <= v <= hi * 1.2):
			bad.append((name, v, (lo, hi)))
			print("   ! %s = %.2f mimo %s" % (name, v, (lo, hi)))
	pm = sum(SW["PRECIP_MM"])
	print("   kontrola konzistence: SoilWater.PRECIP_MM (dohánění) = %.0f mm/rok vs. srážky z Weather = %.0f mm/rok (%+.0f %%)"
		% (pm, p, (p / pm - 1.0) * 100.0))
	return bad


# ============================================================================ mikroklima (inverze, mlha)


def run_micro(years):
	valley, ridge, ref = MC["DEF_VALLEY_ELEV"], MC["DEF_RIDGE_ELEV"], MC["DEF_REF_ELEV"]
	ridge_hand = MC["DEF_RIDGE_HAND"]
	rise = clamp(WX["TEMP_MAX_H"] - WX["TEMP_MIN_H"], 0.5, 23.5)

	def t_model(elev, hand, cold, ridge_f, near, t_ref, inv, sunf, nightc):
		low = clamp(1.0 - hand / MC["INV_DEPTH_M"], 0.0, 1.0)
		v = clamp(MC["W_LOW"] * low + MC["W_POOL"] * cold, 0.0, 1.0) * (1.0 - MC["WATER_DAMP"] * near)
		t = t_ref - MC["LAPSE_K_M"] * (elev - ref)
		t -= inv * v
		t += inv * MC["BELT_K"] * ridge_f * (1.0 - low)
		return t

	inv = 0.0
	t_mean = 5.0
	td_air = 0.0
	fog_top = 0.0
	fog_dens = 0.0
	out = []
	for y in years:
		fog_days = 0
		rad_days = 0
		wx_days = 0
		inv_nights = 0
		dts, dts_clear = [], []
		for d, day in enumerate(y):
			doy = d + 1
			fog_today = False
			wfog_today = False
			inv_max_night = 0.0
			vmin, rmin = 99.0, 99.0
			clear_night = True
			for hr in day:
				h = hr["h"] + 0.5
				t_ref, cloud, wind, rain = hr["t"], hr["c"], hr["w"], hr["r"]
				elev = sun_elev(doy, h)
				clear = 1.0 - smoothstep(MC["CLEAR_FROM"], MC["CLEAR_TO"], cloud)
				calm = 1.0 - smoothstep(MC["CALM_FROM_MS"], MC["CALM_TO_MS"], wind)
				dry = 1.0 - clamp(rain * MC["RAIN_DRY_K"], 0.0, 1.0)
				nightc = clear * calm * dry * (1.0 - smoothstep(0.0, MC["NIGHT_ELEV_TO"], elev))
				sunf = clamp(elev / MC["SUN_FULL_ELEV"], 0.0, 1.0) * (1.0 - MC["SUN_CLOUD_K"] * cloud)
				t_mean = lerp(t_mean, t_ref, 1.0 - math.exp(-1.0 / MC["TMEAN_TAU_H"]))
				rngc = monthly(SEA["TEMP_RANGE"], doy) * (1.0 - MC["CLOUD_RANGE_DAMP"] * cloud)
				moist = clamp(MC["MOIST_BASE"] + MC["MOIST_CLOUD"] * cloud + MC["MOIST_RAIN"] * rain + MC["MOIST_FOG"] * hr["f"]
					+ MC["MOIST_RECENT"] * hr["rr"] - MC["MOIST_DROUGHT"] * hr["dr"], 0.0, 1.0)
				td_t = t_mean - 0.5 * rngc - MC["DEP_K"] * (1.0 - moist) - MC["TD_OFFSET_K"]
				td_air = min(lerp(td_air, td_t, 1.0 - math.exp(-1.0 / MC["TD_TAU_H"])), t_ref)
				build = MC["INV_RATE_K_H"] * clear * calm * dry * (1.0 - smoothstep(MC["INV_BUILD_ELEV_FROM"], MC["INV_BUILD_ELEV_TO"], elev)) \
					* (1.0 - inv / MC["INV_MAX_K"])
				decay = (1.0 - clear * calm * dry) / MC["INV_MIX_H"] + smoothstep(MC["INV_BREAK_ELEV_FROM"], MC["INV_BREAK_ELEV_TO"], elev) \
					* (MC["INV_BREAK_BASE"] + (1.0 - MC["INV_BREAK_BASE"]) * clear) / MC["INV_BREAK_H"]
				inv = clamp(inv + build - inv * (1.0 - math.exp(-decay)), 0.0, MC["INV_MAX_K"])
				# dno údolí: mlha
				ta0 = t_model(valley, 0.0, MC["POOL_K"], 0.0, 1.0, t_ref, inv, sunf, nightc)
				td0 = td_air + MC["TD_WATER_K"]
				fd_t = clamp((td0 + MC["FOG_MARGIN_K"] - ta0) / MC["FOG_DENS_SPAN_K"], 0.0, 1.0) * calm * dry
				ft = 0.0
				if fd_t > 0:
					for i in range(int(MC.get("FOG_SCAN_N", 40)) + 1):
						hh = i * MC["FOG_SCAN_M"]
						cold = clamp(1.0 - hh / MC["POOL_DEPTH_M"], 0.0, 1.0) * MC["POOL_K"]
						near = 1.0 if hh < 5.0 else 0.0
						ta = t_model(valley + hh, hh, cold, 0.0, near, t_ref, inv, sunf, nightc)
						if ta <= td_air + MC["TD_WATER_K"] * near + MC["FOG_MARGIN_K"]:
							ft = max(hh, 1.0)
						else:
							break
				fog_top = lerp(fog_top, ft, 1.0 - math.exp(-1.0 / (MC["FOG_TAU_UP_H"] if ft > fog_top else MC["FOG_TAU_DOWN_H"])))
				fog_dens = lerp(fog_dens, fd_t, 1.0 - math.exp(-1.0 / (MC["FOG_TAU_UP_H"] if fd_t > fog_dens else MC["FOG_TAU_DOWN_H"])))
				if fog_top < 0.5:
					fog_dens = min(fog_dens, fog_top * 2.0)
				if h < 11.0 and fog_top >= 5.0 and fog_dens > 0.4:
					fog_today = True
				if h < 11.0 and hr["f"] > 0.4:
					wfog_today = True
				if h < 10.0 or h > 18.0:
					inv_max_night = max(inv_max_night, inv)
				if h < 9.0 or h > 18.0:
					tv = t_model(valley, 0.0, 0.8, 0.0, 1.0, t_ref, inv, sunf, nightc)
					tr_ = t_model(ridge, ridge_hand, 0.0, 1.0, 0.0, t_ref, inv, sunf, nightc)
					vmin = min(vmin, tv)
					rmin = min(rmin, tr_)
					if h < 6.0 and (cloud > 0.3 or wind > 3.0):
						clear_night = False
			if fog_today or wfog_today:
				fog_days += 1
			if fog_today:
				rad_days += 1
			if wfog_today:
				wx_days += 1
			if inv_max_night >= 2.0:
				inv_nights += 1
			dts.append(rmin - vmin)
			if clear_night:
				dts_clear.append(rmin - vmin)
		out.append({"fog": fog_days, "rad": rad_days, "wx": wx_days, "inv": inv_nights / 365.0, "dt": statistics.mean(dts),
			"dt_clear": statistics.mean(dts_clear) if dts_clear else float("nan"), "n_clear": len(dts_clear)})
	print("\n== Mikroklima (inverze, radiační mlha; dno kotliny %.0f m, hřbet %.0f m, střed %.1f m – výšky světa) ==" % (valley, ridge, ref))
	fog = statistics.mean(r["fog"] for r in out)
	invf = statistics.mean(r["inv"] for r in out)
	dt = statistics.mean(r["dt"] for r in out)
	dtc = statistics.mean(r["dt_clear"] for r in out if r["n_clear"] > 0)
	ncl = statistics.mean(r["n_clear"] for r in out)
	bad = []
	print("    z toho radiační mlha Microclimate (vrstva ≥ 5 m, hustota > 0,4): %.0f dní, mlha situace Weather.fog > 0,4: %.0f dní"
		% (statistics.mean(r["rad"] for r in out), statistics.mean(r["wx"] for r in out)))
	for name, v, key in (("dní s mlhou v údolí do 11 h (radiační nebo Weather.fog)", fog, "fog_days"),
			("podíl nocí s inverzí ≥ 2 K", invf, "inv_nights_frac"),
			("hřbet − kotlina, noční minimum, všechny noci (K)", dt, "mean_dt_k"),
			("hřbet − kotlina, jasné bezvětrné noci (K, %d nocí)" % ncl, dtc, "clear_dt_k")):
		lo, hi = REF_MICRO[key]
		flag = "!" if not (lo * 0.8 <= v <= hi * 1.2) else " "
		if flag == "!":
			bad.append((name, v, (lo, hi)))
		print("  %s %-58s %6.2f   ref %s–%s" % (flag, name, v, lo, hi))
	return bad


# ============================================================================ Dolbear


def report_dolbear():
	a, b = SS["DOLBEAR_A"], SS["DOLBEAR_B"]
	ra, rb = REF_DOLBEAR
	print("\n== Cvrčci – Dolbearův zákon (soundscape.gd: N = %.1f·T − %.1f cvrknutí/min; ref. Dolbear 1897: N = %.1f·T − %.0f) ==" % (a, b, ra, rb))
	bad = []
	for t in (13.0, 15.0, 20.0, 25.0, 30.0):
		n = a * t - b
		r = ra * t - rb
		d = (n / r - 1.0) * 100.0
		flag = "!" if abs(d) > 20 else " "
		if flag == "!":
			bad.append(("Dolbear %d °C" % t, n, r))
		print("  %s T = %2.0f °C: model %5.1f/min (%.2f/s), ref %5.1f/min, %+.0f %%" % (flag, t, n, n / 60.0, r, d))
	for s in ZVUK.get("zdroje", []):
		if s.get("typ") == "cvrcek":
			print("    %-16s × dolbear %.2f → při 25 °C %.1f/s, mlčí pod %.1f °C (CHIRP_MIN %.0f/min), t_min %s °C"
				% (s["id"], float(s.get("dolbear", 1.0)), (a * 25 - b) * float(s.get("dolbear", 1.0)) / 60.0, (SS["CHIRP_MIN"] + b) / a, SS["CHIRP_MIN"], s.get("t_min")))
	return bad


# ============================================================================ plodiny


def crop_specs():
	sp = {}
	for g in ("zahrada", "pole"):
		for k, v in PLOD.get(g, {}).items():
			sp[k] = v
	return sp


def water_stress(sp, moist):
	frm = CM["DRY_FROM_M"] * float(sp.get("voda", 1.0))
	ws = clamp((moist - CM["WILT_M"]) / max(frm - CM["WILT_M"], 0.01), 0.0, 1.0)
	if sp.get("zamok", False) and moist > CM["WET_FROM_M"]:
		ws *= 1.0 - CM["WATERLOG_K"] * clamp((moist - CM["WET_FROM_M"]) / max(1.0 - CM["WET_FROM_M"], 0.01), 0.0, 1.0)
	return ws


def temp_stress(sp, t):
	base = float(sp.get("tbase", 5.0))
	topt = sp.get("topt", [base + 10.0, 25.0])
	lo, hi = float(topt[0]), float(topt[1])
	if t <= base or t >= CM["TMAX_C"]:
		return 0.0
	if t < lo:
		return (t - base) / max(lo - base, 0.1)
	if t > hi:
		return 1.0 - (t - hi) / max(CM["TMAX_C"] - hi, 0.1)
	return 1.0


def crop_season(sp, days):
	"""`days` = posloupnost (t_mean, t_min, t_max, rad_mj, moist) od výsevu. Vrací (výnos g/m², den dozrání, příčina smrti)."""
	g = sp.get("gdd", [100, 600, 900, 1200])
	st, gdd, bm, lai, yp, dd = 0, 0.0, 0.0, 0.0, 1.0, 0
	for i, (t, tmin, tmax, rad, moist) in enumerate(days):
		if st == 0 and not sp.get("sadba", False):
			pass
		elif tmin < float(sp.get("mraz", -2.0)):
			return 0.0, i, "mráz"
		base = float(sp.get("tbase", 5.0))
		cap = float(sp.get("tcap", 30.0))
		ws = water_stress(sp, moist)
		ts = temp_stress(sp, t)
		dg = clamp(t, base, cap) - base
		if 2 <= st < 4:
			dg *= 1.0 + CM["DROUGHT_ACCEL"] * (1.0 - ws)
		gdd += dg
		nst = 0 if gdd < g[0] else (1 if gdd < g[1] else (2 if gdd < g[2] else (3 if gdd < g[3] else 4)))
		if st == 0 and nst > 0:
			bm = CM["BM0_GM2"]
		st = nst
		if nst == 0:
			continue
		if ws < CM["DEAD_WS"] and nst < 4:
			dd += 1
			if dd > int(sp.get("sucho_dni", 14)):
				return 0.0, i, "sucho"
		else:
			dd = 0
		if nst >= 4:
			return float(sp.get("hi", 0.5)) * bm * yp, i, ""
		intercept = 1.0 - math.exp(-float(sp.get("k", 0.6)) * lai)
		par = rad * CM["PAR_FRAC"]
		bm += float(sp.get("rue", 2.5)) * par * max(intercept, 0.01) * min(ws, ts)
		if nst < 3:
			lai = min(float(sp.get("lai_max", 4.0)), max(lai, CM["SLA_M2_G"] * CM["LEAF_FRAC"] * bm))
		else:
			lai *= 1.0 - CM["LAI_SENESCE_D"]
		stress = 1.0 - min(ws, ts)
		if nst == 2:
			yp -= CM["FLOWER_STRESS_D"] * stress
			heat = float(sp.get("horko", 32.0))
			if tmax > heat:
				yp -= CM["HEAT_LOSS_D"] * clamp((tmax - heat) / CM["HEAT_SPAN_C"], 0.0, 1.0)
		elif nst == 3:
			yp -= CM["FILL_STRESS_D"] * stress
		yp = max(yp, CM["YP_MIN"])
	return float(sp.get("hi", 0.5)) * bm * yp, len(days), "nedozrálo"


def daily_series(years, moist_years, t_add=0.0):
	"""Posloupnost dnů přes všechny roky: (t_mean, t_min, t_max, rad, moist, doy)."""
	out = []
	for y, mo in zip(years, moist_years):
		for d, day in enumerate(y):
			ts = [h["t"] + t_add for h in day]
			cl = sum(h["c"] for h in day) / len(day)
			rad = extraterrestrial_mj(d + 1) * (CM["ANGSTROM_A"] + CM["ANGSTROM_B"] * (1.0 - clamp(cl, 0.0, 1.0)))
			out.append((sum(ts) / len(ts), min(ts), max(ts), rad, mo[d], d + 1))
	return out


def clim_crop(sp):
	seti = sp.get("seti", [100, 110])
	sow = (float(seti[0]) + float(seti[1])) * 0.5
	days = []
	for i in range(400):
		doy = math.fmod(sow + i - 1.0, 365.0) + 1.0
		t = monthly(SEA["TEMP_MEAN"], doy)
		r = monthly(SEA["TEMP_RANGE"], doy) * 0.8
		rad = extraterrestrial_mj(doy) * (CM["ANGSTROM_A"] + CM["ANGSTROM_B"] * (1.0 - CM["CLIM_CLOUD"]))
		days.append((t, 99.0, t + r * 0.5, rad, CM["CLIM_MOIST"]))
	y, i, _ = crop_season(sp, days)
	return y, (sow + i - 1) % 365 + 1


def run_crops(years, scen):
	specs = crop_specs()
	print("\n== Plodiny (CropModel.step_day; vlhkost z kyblíku orné půdy; t/ha čerstvé hmoty přes podíl sušiny) ==")
	print("   %-11s | %-8s | %-25s | %-11s | %-9s | %-15s | %s" % ("plodina", "ref t/ha", "normál hry  t/ha (dozrání)", "počasí t/ha",
		"počasí/K", "suché / vlhké", "pozn."))
	bad = []
	for key, (ref_t, dm) in REF_YIELD.items():
		sp = specs.get(key)
		if sp is None:
			continue
		cy, cdoy = clim_crop(sp)
		seti = sp.get("seti", [100, 110])
		sow = int((float(seti[0]) + float(seti[1])) * 0.5)
		res = {}
		for name, series in scen.items():
			ys = []
			causes = []
			for k in range(len(series) // 365 - 1):
				start = k * 365 + sow - 1
				yv, _, cause = crop_season(sp, [s[:5] for s in series[start:start + 400]])
				ys.append(yv)
				if cause:
					causes.append(cause)
			res[name] = (statistics.mean(ys) if ys else 0.0, causes)
		to_t = lambda g: g / 100.0 / dm
		n_t = to_t(res["normal"][0])
		dry_r = res["dry"][0] / max(res["normal"][0], 1e-6)
		wet_r = res["wet"][0] / max(res["normal"][0], 1e-6)
		note = []
		flag = " "
		if abs(n_t / ref_t - 1.0) > 0.2:
			flag = "!"
			bad.append((key, "výnos", n_t, ref_t))
		ratio_k = res["normal"][0] / max(cy, 1e-6)
		if abs(ratio_k - 1.0) > 0.2:
			flag = "!"
			bad.append((key, "počasí/normál", ratio_k, 1.0))
			note.append("běžný rok ≠ normál hry")
		if not (REF_DRY[0] - 0.1 <= dry_r <= REF_DRY[1] + 0.1):
			note.append("sucho mimo ref")
		if not (REF_WET[0] - 0.1 <= wet_r <= REF_WET[1] + 0.1):
			note.append("vlhko mimo ref")
		cs = res["normal"][1] + res["dry"][1]
		if cs:
			note.append("ztráty: " + ", ".join(sorted(set(cs))))
		print(" %s %-11s | %8.1f | %8.1f (%s)          | %11.1f | %9.2f | %5.2f / %5.2f   | %s"
			% (flag, key, ref_t, to_t(cy), date_txt(cdoy), n_t, ratio_k, dry_r, wet_r, "; ".join(note)))
	print("   počasí/K = výnos běžného roku vůči normálu hry (CropModel.clim – hráč vidí jako „výnos vůči normálu“), cíl ~1,0")
	print("   ref. suchý rok %.2f–%.2f × normál, vlhký %.2f–%.2f (ČSÚ, orientačně)" % (REF_DRY + REF_WET))
	return bad


# ============================================================================ zvěř


def hash01(a, b, c):
	M = (1 << 64) - 1

	def s64(x):
		x &= M
		return x - (1 << 64) if x >> 63 else x
	h = s64(s64(a * 73856093) ^ s64(b * 19349663) ^ s64(c * 83492791))
	h = s64(s64(h ^ (h >> 13)) * 1274126177)
	h = s64(h ^ (h >> 16))
	return float(h & 0xFFFFFF) / 16777216.0


def is_mast_year(y):
	m = 1990 + int(hash01(1990, 5, 1) * HB["MAST_MIN_GAP"])
	while m < y:
		m += HB["MAST_MIN_GAP"] + int(hash01(m, 9, 2) * max(HB["MAST_GAP_SPAN"], 1))
	return m == y


def mast_year(y):
	v = HB["MAST_NORMAL"] + (hash01(y, 17, 3) - 0.5) * 2.0 * HB["MAST_JITTER"]
	if is_mast_year(y):
		return 1.0
	if is_mast_year(y - 1):
		return HB["MAST_POOR"]
	return v


def run_pop(years, snow_series, hsi, start_year=2026, road_share=0.1, feeder=0.5):
	names = ["srnec", "divocak", "zajic"]
	print("\n== Zvěř (Habitat._pop_step; K = HSI × DENS_MAX, předpokládané HSI %s; silnice %.0f %% buněk, krmelce %.1f) =="
		% ("/".join("%.2f" % h for h in hsi), road_share * 100, feeder))
	bad = []
	md = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
	for s in range(3):
		kk = hsi[s] * HB["DENS_MAX"][s]          # ks / 100 ha
		n = kk * HB["INIT_FILL"][s]
		yearly = []
		mast_store = 0.0
		for yi, y in enumerate(years):
			yr = start_year + yi
			doy = 0
			for m in range(12):
				for dm in range(md[m]):
					doy += 1
					day = y[doy - 1]
					mo = m + 1
					winter = mo == 12 or mo <= 2
					temp = day[0]["t"]                  # hra: Weather.temp v okamžiku denního kroku (půlnoc)
					snow = snow_series[yi][doy - 1]
					if doy >= HB["MAST_FROM_DOY"]:
						mast_store = max(mast_store, mast_year(yr) * clamp((doy - HB["MAST_FROM_DOY"]) / 30.0, 0.0, 1.0))
					elif HB["MAST_SPROUT_DOY"] <= doy < HB["MAST_FROM_DOY"] - 30:
						mast_store = 0.0
					mast_store *= 1.0 - HB["MAST_EAT_D"]
					hard = 0.0
					if winter:
						hard = clamp(snow / max(HB["WINTER_SNOW_M"], 0.01), 0.0, 1.0) * 0.6 + clamp(-temp / max(HB["WINTER_COLD_C"], 0.1), 0.0, 1.0) * 0.4
					bw = HB["BIRTH_DOY"][s]
					if bw[0] <= doy <= bw[1]:
						litter = HB["LITTER"][s]
						if s == 1:
							litter *= 1.0 - HB["MAST_BIRTH_K"] + HB["MAST_BIRTH_K"] * 2.0 * mast_year(yr - 1)
						n += n * HB["FEMALE_SHARE"][s] * litter * max(0.0, 1.0 - n / kk) / max(bw[1] - bw[0] + 1.0, 1.0)
					mort = HB["MORT_BASE"][s] / 365.0
					if n > kk:
						mort += (n - kk) / kk * HB["MORT_CROWD"] / 365.0
					if winter and hard > 0:
						relief = HB["MAST_RELIEF"] * mast_store if s == 1 else HB["FEEDER_RELIEF"] * feeder
						mort += HB["MORT_WINTER"][s] / 90.0 * hard * (1.0 - clamp(relief, 0.0, 1.0))
					auto = n * HB["ROAD_MORT"][s] / 365.0 * clamp(road_share * 5.0, 0.0, 2.0)
					cull = 0.0
					cm = HB["CULL_MONTHS"][s]
					if mo in cm:
						q = HB["CULL_QUOTA"][s]
						if s == 1:
							q *= clamp(n / max(HB["CULL_PRASE_REF"], 0.1), 0.5, 2.0)
						cull = n * q / max(len(cm) * 30.4, 1.0)
					n = max(n - n * mort - auto - cull, 0.0)
					if doy == 90:
						yearly.append(n)          # jarní kmenový stav (konec března)
		lo, hi = REF_POP[names[s]]
		last = yearly[-1] if yearly else n
		flag = "!" if not (lo * 0.8 <= last <= hi * 1.2) else " "
		if flag == "!":
			bad.append((names[s], last, (lo, hi)))
		print("  %s %-8s K %5.1f ks/100 ha, start %5.1f → jaro po letech: %s → n/K %.2f (ref %d–%d)"
			% (flag, names[s], kk, kk * HB["INIT_FILL"][s], " ".join("%.1f" % v for v in yearly), last / kk, lo, hi))
	masts = [yr for yr in range(start_year, start_year + len(years)) if is_mast_year(yr)]
	print("    semenné roky dubu/buku %d–%d: %s" % (start_year, start_year + len(years) - 1, ", ".join(map(str, masts)) or "žádný"))
	return bad


# ============================================================================ hlavní


def main():
	ap = argparse.ArgumentParser(description="Kalibrace modelů přírody M8 proti referencím (offline).")
	ap.add_argument("--years", type=int, default=10, help="let náhradního počasí (výchozí 10)")
	ap.add_argument("--seed", type=int, default=1991, help="seed náhradního počasí (deterministické)")
	ap.add_argument("--hsi", default="0.45,0.35,0.40", help="předpokládané průměrné HSI srnec,prase,zajíc")
	ap.add_argument("--only", default="", help="jen oddíly: fenologie,voda,mikroklima,dolbear,plodiny,zver")
	ap.add_argument("--set", action="append", default=[], metavar="SOUBOR.JMÉNO=HODNOTA",
		help="zkusmo přepsat konstantu (bez úpravy kódu), např. --set weather.RAIN_MM_H=3 --set soil_water.Q_SPEC=4e-9; "
		"soubory: " + ", ".join(sorted(TABLES)))
	a = ap.parse_args()
	for kv in a.set:
		name, _, val = kv.partition("=")
		mod, _, key = name.partition(".")
		if mod not in TABLES or key not in TABLES[mod]:
			ap.error("neznámá konstanta %s" % name)
		TABLES[mod][key] = _to_py(val, {})
		print("  (zkusmo) %s = %s" % (name, val))
	only = set(x.strip() for x in a.only.split(",") if x.strip())
	want = lambda k: not only or k in only
	print("Kalibrace M8 (tools/eco_calibrate.py) – %d let náhradního počasí, seed %d. Reference ORIENTAČNĚ – OVĚŘIT." % (a.years, a.seed))
	print("Normál Seasons: roční průměr %.2f °C, srážky (SoilWater.PRECIP_MM) %.0f mm, srážkových dnů %d"
		% (sum(SEA["TEMP_MEAN"]) / 12.0, sum(SW["PRECIP_MM"]), sum(SEA["WET_DAYS"])))
	years = make_years(a.years, a.seed)
	clim = clim_year()
	t_sim = statistics.mean(day_mean(d) for y in years for d in y)
	print("Náhradní počasí: roční průměr %.2f °C (normál %.2f), srážky %.0f mm/rok"
		% (t_sim, sum(SEA["TEMP_MEAN"]) / 12.0, statistics.mean(sum(h["mm"] for d in y for h in d) for y in years)))
	summary = {}
	if want("fenologie"):
		summary["fenologie"] = run_pheno(years, clim)
	wr = None
	if want("voda") or want("plodiny") or want("zver"):
		wr = run_water(years)
	if want("voda"):
		summary["voda"] = report_water(wr, run_water([clim, clim, clim]))
	if want("mikroklima"):
		summary["mikroklima"] = run_micro(years)
	if want("dolbear"):
		summary["dolbear"] = report_dolbear()
	if want("plodiny"):
		wd = run_water(years, p_mult=DRY_P, t_add=DRY_T)
		ww = run_water(years, p_mult=WET_P, t_add=WET_T)
		mo = lambda res: [r["moist"][CLS_ORNA] for r in res]
		scen = {"normal": daily_series(years, mo(wr)), "dry": daily_series(years, mo(wd), DRY_T), "wet": daily_series(years, mo(ww), WET_T)}
		summary["plodiny"] = run_crops(years, scen)
	if want("zver"):
		snow = [[0.0] * 365 for _ in years]
		ws = WaterSim()
		for yi, y in enumerate(years):
			for d, day in enumerate(y):
				for hr in day:
					ws.hour(d + 1, hr)
				snow[yi][d] = ws.cells[CLS_LOUKA].swe * 0.001 / SW["SNOW_DENSITY"]
		summary["zver"] = run_pop(years, snow, [float(x) for x in a.hsi.split(",")])
	print("\n== Shrnutí: položek mimo toleranci ==")
	for k, v in summary.items():
		print("   %-11s %d" % (k, len(v)))
	return 0


if __name__ == "__main__":
	sys.exit(main())
