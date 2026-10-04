## Procedurální model auta: karoserie jako "loft" příčných řezů podél délky vozu
## (+Z dopředu, +X doleva, Y nahoru, počátek na zemi uprostřed rozvoru).
## Řezy mají body: spodek – práh – bok (vyboulení) – linie oken – okno – okraj střechy – střed střechy;
## podběhy kol jsou vyříznuté ze spodní hrany, okna / čelní sklo / zadní okno podle zón,
## k tomu světla, maska, SPZ, zrcátka, kliky, interiér (sedadla, palubní deska, volant).
## Mesh drží pole vrcholů → lze ho deformovat při nárazech (deform()).
class_name CarModel
extends RefCounted

## Klíčové řezy: [z, y_spodek, y_linie_oken, y_střecha, půlšířka_spodek, půlšířka_linie, půlšířka_střecha, skleník 0..1, zóna]
## zóna: 0 plech, 1 boční okna, 2 čelní/zadní sklo
const MODELS := {
	"octavia": {
		"kategorie": "osobní", "skupina_rp": "B", "cena": 89000, "rok": 2008, "kufr_l": 610, "nosic": false, "tazne_kg": 1400, "hitch": Vector3(0, 0.45, -2.5), "glb": "",
		"name": "Oktávka Kombi", "wb": 2.69, "track": 1.54, "wheel_r": 0.315, "mass": 1350.0,
		"power_kw": 110.0, "torque": 250.0, "rpm_max": 6200.0, "gears": [3.62, 2.12, 1.28, 0.97, 0.77, 0.64],
		"final": 3.9, "drag": 0.39,
		"keys": [
			[-2.46, 0.44, 0.9, 0.93, 0.76, 0.8, 0.74, 0.0, 0],
			[-2.42, 0.32, 0.97, 1.0, 0.84, 0.87, 0.62, 1.0, 0],
			[-2.36, 0.27, 1.0, 1.38, 0.86, 0.89, 0.6, 1.0, 2],
			[-2.22, 0.25, 1.0, 1.47, 0.88, 0.9, 0.65, 1.0, 1],
			[0.3, 0.24, 0.98, 1.47, 0.89, 0.905, 0.68, 1.0, 1],
			[0.48, 0.24, 0.975, 1.42, 0.89, 0.905, 0.69, 1.0, 2],
			[1.22, 0.24, 0.95, 0.99, 0.89, 0.9, 0.8, 1.0, 2],
			[1.35, 0.25, 0.94, 0.965, 0.89, 0.895, 0.78, 0.0, 0],
			[1.95, 0.27, 0.85, 0.87, 0.87, 0.87, 0.78, 0.0, 0],
			[2.15, 0.33, 0.76, 0.77, 0.8, 0.8, 0.72, 0.0, 0],
			[2.25, 0.42, 0.64, 0.65, 0.66, 0.68, 0.6, 0.0, 0],
		],
		"b_pillars": [-0.28, -1.72], "head_z": 2.12, "head_y": 0.74, "tail_z": -2.42, "tail_y": 0.93,
	},
	"fabia": {
		"kategorie": "osobní", "skupina_rp": "B", "cena": 64000, "rok": 2010, "kufr_l": 300, "nosic": false, "tazne_kg": 900, "hitch": Vector3(0, 0.45, -2.0), "glb": "",
		"name": "Fábička", "wb": 2.46, "track": 1.47, "wheel_r": 0.3, "mass": 1100.0,
		"power_kw": 70.0, "torque": 175.0, "rpm_max": 6000.0, "gears": [3.46, 1.96, 1.28, 0.95, 0.76],
		"final": 4.1, "drag": 0.36,
		"keys": [
			[-1.95, 0.44, 0.92, 0.95, 0.74, 0.78, 0.7, 0.0, 0],
			[-1.9, 0.3, 0.97, 1.02, 0.8, 0.84, 0.6, 1.0, 0],
			[-1.82, 0.27, 0.99, 1.38, 0.82, 0.85, 0.58, 1.0, 2],
			[-1.6, 0.25, 0.99, 1.46, 0.84, 0.86, 0.62, 1.0, 1],
			[0.25, 0.24, 0.97, 1.46, 0.85, 0.865, 0.65, 1.0, 1],
			[0.42, 0.24, 0.965, 1.41, 0.85, 0.865, 0.66, 1.0, 2],
			[1.08, 0.24, 0.94, 0.98, 0.85, 0.86, 0.76, 1.0, 2],
			[1.2, 0.25, 0.93, 0.955, 0.85, 0.855, 0.74, 0.0, 0],
			[1.75, 0.27, 0.84, 0.86, 0.83, 0.83, 0.74, 0.0, 0],
			[1.95, 0.33, 0.75, 0.76, 0.76, 0.76, 0.68, 0.0, 0],
			[2.04, 0.42, 0.63, 0.64, 0.62, 0.64, 0.56, 0.0, 0],
		],
		"b_pillars": [-0.35], "head_z": 1.92, "head_y": 0.73, "tail_z": -1.9, "tail_y": 0.95,
	},
	"sedan120": {
		"kategorie": "osobní", "skupina_rp": "B", "cena": 22000, "rok": 1987, "kufr_l": 350, "nosic": false, "tazne_kg": 500, "hitch": Vector3(0, 0.45, -2.15), "glb": "",
		"name": "Stodvacka", "wb": 2.4, "track": 1.33, "wheel_r": 0.3, "mass": 900.0,
		"power_kw": 40.0, "torque": 87.0, "rpm_max": 5200.0, "gears": [3.8, 2.12, 1.41, 0.96], "final": 4.2,
		"drag": 0.45,
		"keys": [
			[-2.1, 0.4, 0.78, 0.8, 0.72, 0.76, 0.72, 0.0, 0],
			[-2.02, 0.3, 0.85, 0.87, 0.78, 0.8, 0.76, 0.0, 0],
			[-1.35, 0.28, 0.88, 0.9, 0.79, 0.8, 0.76, 0.0, 0],
			[-1.2, 0.28, 0.89, 0.93, 0.79, 0.8, 0.7, 1.0, 2],
			[-0.8, 0.28, 0.9, 1.38, 0.79, 0.8, 0.6, 1.0, 2],
			[-0.65, 0.28, 0.9, 1.39, 0.79, 0.8, 0.6, 1.0, 1],
			[0.55, 0.28, 0.9, 1.39, 0.79, 0.8, 0.62, 1.0, 1],
			[0.65, 0.28, 0.9, 1.37, 0.79, 0.8, 0.63, 1.0, 2],
			[1.15, 0.28, 0.87, 0.9, 0.79, 0.8, 0.74, 1.0, 2],
			[1.25, 0.28, 0.86, 0.87, 0.79, 0.8, 0.74, 0.0, 0],
			[2.0, 0.3, 0.8, 0.8, 0.78, 0.78, 0.74, 0.0, 0],
			[2.1, 0.4, 0.72, 0.72, 0.7, 0.72, 0.66, 0.0, 0],
		],
		"b_pillars": [-0.05], "head_z": 2.04, "head_y": 0.68, "tail_z": -2.06, "tail_y": 0.76,
	},
	"van": {
		"kategorie": "dodávka", "skupina_rp": "B", "cena": 110000, "rok": 2004, "kufr_l": 6000, "nosic": false, "tazne_kg": 1500, "hitch": Vector3(0, 0.5, -2.7), "boxy": true, "glb": "",
		"name": "Dodávka", "wb": 3.3, "track": 1.7, "wheel_r": 0.34, "mass": 2100.0,
		"power_kw": 96.0, "torque": 340.0, "rpm_max": 4500.0, "gears": [4.2, 2.3, 1.4, 1.0, 0.8, 0.66],
		"final": 3.7, "drag": 0.9,
		"keys": [
			[-2.62, 0.45, 1.05, 2.0, 0.9, 0.94, 0.88, 0.0, 0],
			[-2.58, 0.33, 1.08, 2.08, 0.96, 0.98, 0.9, 0.0, 0],
			[-2.4, 0.3, 1.08, 2.15, 0.98, 1.0, 0.92, 0.0, 0],
			[0.9, 0.3, 1.08, 2.15, 0.98, 1.0, 0.92, 0.0, 0],
			[1.0, 0.3, 1.08, 2.15, 0.98, 1.0, 0.92, 1.0, 1],
			[1.3, 0.3, 1.06, 2.08, 0.98, 1.0, 0.9, 1.0, 1],
			[1.45, 0.3, 1.05, 2.0, 0.98, 1.0, 0.88, 1.0, 2],
			[2.0, 0.3, 1.02, 1.18, 0.98, 0.99, 0.9, 1.0, 2],
			[2.12, 0.32, 1.0, 1.05, 0.97, 0.98, 0.9, 0.0, 0],
			[2.42, 0.36, 0.9, 0.92, 0.92, 0.92, 0.84, 0.0, 0],
			[2.52, 0.45, 0.72, 0.74, 0.8, 0.82, 0.72, 0.0, 0],
		],
		"b_pillars": [], "head_z": 2.44, "head_y": 0.85, "tail_z": -2.6, "tail_y": 1.1,
	},
	# ---- M1.6: nová vozidla (parodické názvy; katalogová pole viz VLASTNI_VOZIDLA.md). Hodnoty jsou odhad – DOPLNIT (ladění po testu).
	"bednar": {
		"name": "Bednář", "kategorie": "dodávka", "skupina_rp": "B", "cena": 135000, "rok": 2006, "kufr_l": 7500, "nosic": false,
		"tazne_kg": 1500, "hitch": Vector3(0, 0.5, -2.45), "boxy": true, "single_row": true, "glb": "",
		"wb": 3.0, "track": 1.65, "wheel_r": 0.33, "mass": 1850.0,
		"power_kw": 85.0, "torque": 300.0, "rpm_max": 4600.0, "gears": [4.0, 2.2, 1.4, 1.0, 0.78],
		"final": 3.8, "drag": 0.85, "com_y": 0.6,
		"keys": [
			[-2.4, 0.45, 1.0, 1.85, 0.86, 0.9, 0.84, 0.0, 0],
			[-2.36, 0.33, 1.02, 1.95, 0.92, 0.94, 0.86, 0.0, 0],
			[-2.2, 0.3, 1.02, 2.0, 0.94, 0.96, 0.88, 0.0, 0],
			[0.75, 0.3, 1.02, 2.0, 0.94, 0.96, 0.88, 0.0, 0],
			[0.85, 0.3, 1.02, 2.0, 0.94, 0.96, 0.88, 1.0, 1],
			[1.15, 0.3, 1.0, 1.95, 0.94, 0.96, 0.86, 1.0, 1],
			[1.3, 0.3, 1.0, 1.88, 0.94, 0.96, 0.84, 1.0, 2],
			[1.85, 0.3, 0.98, 1.12, 0.94, 0.95, 0.86, 1.0, 2],
			[1.97, 0.32, 0.96, 1.02, 0.93, 0.94, 0.86, 0.0, 0],
			[2.25, 0.36, 0.86, 0.88, 0.88, 0.88, 0.8, 0.0, 0],
			[2.35, 0.45, 0.7, 0.72, 0.78, 0.8, 0.7, 0.0, 0],
		],
		"b_pillars": [], "head_z": 2.28, "head_y": 0.8, "tail_z": -2.38, "tail_y": 1.0,
	},
	"lesak": {
		"name": "Lesák", "kategorie": "pickup", "skupina_rp": "B", "cena": 165000, "rok": 2003, "kufr_l": 0, "nosic": false,
		"tazne_kg": 2000, "hitch": Vector3(0, 0.5, -2.6), "single_row": true, "glb": "",
		# ložná plocha (M2.10): střed podlahy a rozměry prostoru (x šířka, y výška, z délka), lokálně
		"bed": {"c": Vector3(0, 1.02, -1.62), "size": Vector3(1.6, 0.5, 1.7)},
		"wb": 3.1, "track": 1.62, "wheel_r": 0.36, "mass": 2000.0,
		"power_kw": 110.0, "torque": 340.0, "rpm_max": 4400.0, "gears": [4.2, 2.4, 1.5, 1.0, 0.8],
		"final": 3.9, "drag": 0.75, "com_y": 0.66,
		"keys": [
			[-2.55, 0.42, 0.98, 1.0, 0.82, 0.86, 0.8, 0.0, 0],
			[-2.5, 0.32, 1.0, 1.02, 0.9, 0.92, 0.88, 0.0, 0],
			[-0.75, 0.3, 1.0, 1.02, 0.9, 0.92, 0.88, 0.0, 0],
			[-0.68, 0.3, 1.0, 1.5, 0.9, 0.92, 0.8, 1.0, 0],
			[-0.6, 0.3, 1.0, 1.86, 0.9, 0.92, 0.72, 1.0, 2],
			[-0.5, 0.3, 1.0, 1.9, 0.9, 0.92, 0.7, 1.0, 2],
			[-0.42, 0.3, 1.0, 1.92, 0.9, 0.92, 0.7, 1.0, 1],
			[0.35, 0.3, 1.0, 1.92, 0.9, 0.92, 0.68, 1.0, 1],
			[0.5, 0.3, 1.0, 1.86, 0.9, 0.92, 0.68, 1.0, 2],
			[1.05, 0.3, 0.98, 1.05, 0.9, 0.91, 0.8, 1.0, 2],
			[1.15, 0.3, 0.97, 1.0, 0.9, 0.9, 0.8, 0.0, 0],
			[2.0, 0.3, 0.9, 0.92, 0.88, 0.88, 0.78, 0.0, 0],
			[2.2, 0.36, 0.8, 0.82, 0.82, 0.82, 0.72, 0.0, 0],
			[2.3, 0.45, 0.7, 0.71, 0.7, 0.72, 0.62, 0.0, 0],
		],
		"b_pillars": [], "head_z": 2.2, "head_y": 0.82, "tail_z": -2.52, "tail_y": 0.92,
	},
	"rodinka": {
		"name": "Rodinka Kombi", "kategorie": "osobní", "skupina_rp": "B", "cena": 98000, "rok": 2010, "kufr_l": 650, "nosic": false,
		"tazne_kg": 1600, "hitch": Vector3(0, 0.45, -2.65), "glb": "",
		"wb": 2.75, "track": 1.56, "wheel_r": 0.32, "mass": 1420.0,
		"power_kw": 90.0, "torque": 210.0, "rpm_max": 6000.0, "gears": [3.7, 2.05, 1.3, 0.95, 0.75],
		"final": 4.0, "drag": 0.4, "fwd": true,
		"keys": [
			[-2.62, 0.44, 0.92, 0.95, 0.78, 0.82, 0.78, 0.0, 0],
			[-2.58, 0.32, 0.99, 1.02, 0.86, 0.89, 0.66, 1.0, 0],
			[-2.52, 0.27, 1.02, 1.4, 0.88, 0.91, 0.64, 1.0, 2],
			[-2.38, 0.25, 1.02, 1.52, 0.9, 0.92, 0.68, 1.0, 1],
			[0.3, 0.24, 1.0, 1.52, 0.91, 0.925, 0.7, 1.0, 1],
			[0.48, 0.24, 0.995, 1.46, 0.91, 0.925, 0.71, 1.0, 2],
			[1.22, 0.24, 0.96, 1.0, 0.91, 0.92, 0.82, 1.0, 2],
			[1.35, 0.25, 0.95, 0.975, 0.91, 0.915, 0.8, 0.0, 0],
			[1.95, 0.27, 0.87, 0.89, 0.89, 0.89, 0.8, 0.0, 0],
			[2.15, 0.33, 0.78, 0.79, 0.82, 0.82, 0.74, 0.0, 0],
			[2.25, 0.42, 0.66, 0.67, 0.68, 0.7, 0.62, 0.0, 0],
		],
		"b_pillars": [-0.25, -1.85], "head_z": 2.12, "head_y": 0.74, "tail_z": -2.58, "tail_y": 0.95,
	},
	# malotraktor: model staví TractorModel (spec "builder"), pomalý (rpm limiter ≈ 30 km/h), velký moment, vysoké těžiště
	"traktorek": {
		"builder": "tractor", "name": "Traktůrek", "kategorie": "traktor", "skupina_rp": "T", "cena": 180000, "rok": 1994,
		"kufr_l": 0, "nosic": false, "tazne_kg": 3000, "hitch": Vector3(0, 0.55, -1.75), "glb": "",
		"wb": 1.9, "track": 1.3, "wheel_r": 0.5, "mass": 1500.0,
		"power_kw": 33.0, "torque": 260.0, "rpm_max": 2400.0, "gears": [3.2, 2.1, 1.45, 1.0],
		"final": 15.0, "drag": 1.4, "fwd": false, "com_y": 0.78, "susp": 42.0, "ai_vmax": 7.5, "snd_pitch": 0.55,
		"head_z": 1.55, "head_y": 1.18, "tail_z": -1.5, "tail_y": 1.0,
	},
	# ---- jednostopá vozidla (model staví BikeModel; fyzika: 4 paprsková kola na úzkém rozchodu
	# + stabilizace náklonu v Car, viditelná jsou jen 2 kola uprostřed)
	"kolo": {
		"kategorie": "kolo", "skupina_rp": "", "cena": 0, "rok": 1974, "kufr_l": 0, "nosic": true, "glb": "",
		"kind": "bike", "name": "Dědovo kolo Favorín", "wb": 1.1, "track": 0.62, "wheel_r": 0.35, "mass": 95.0,
		"power_kw": 0.25, "torque": 0.0, "rpm_max": 120.0, "gears": [1.0], "final": 1.0, "drag": 0.3,
		"push": 210.0, "vmax": 8.5, "com_y": 0.45,
		"head_z": 0.52, "head_y": 0.8, "tail_z": -0.86, "tail_y": 0.62, "hull": [0.3, 0.35, 0.95, 0.95],
	},
	"jawa": {
		"kategorie": "motorka", "skupina_rp": "A2", "cena": 32000, "rok": 1974, "kufr_l": 0, "nosic": true, "glb": "",
		"kind": "moto", "name": "Dědova Javor 250 Kývačka", "wb": 1.33, "track": 0.66, "wheel_r": 0.32, "mass": 235.0,
		"power_kw": 10.3, "torque": 21.0, "rpm_max": 5300.0, "gears": [2.9, 1.75, 1.25, 1.0], "final": 6.0,
		"drag": 0.33, "com_y": 0.42, "snd_pitch": 1.5,
		"head_z": 0.64, "head_y": 1.01, "tail_z": -0.93, "tail_y": 0.64, "hull": [0.34, 0.3, 1.05, 1.0],
	},
	# M1.6: moped a skútr (builder "moped" / "scooter" v BikeModel; kategorie a skupiny ŘP pro M4.1). Hodnoty – DOPLNIT (ladění po testu).
	"pionyrek": {
		"kind": "moto", "builder": "moped", "name": "Pionýrek 50", "kategorie": "moped", "skupina_rp": "AM", "cena": 9000,
		"rok": 1982, "kufr_l": 0, "nosic": true, "glb": "", "tire_w": 0.06,
		"wb": 1.15, "track": 0.6, "wheel_r": 0.27, "mass": 85.0,
		"power_kw": 1.5, "torque": 4.2, "rpm_max": 5500.0, "gears": [2.6, 1.0], "final": 12.9,
		"drag": 0.35, "com_y": 0.4, "snd_pitch": 1.9,
		"head_z": 0.5, "head_y": 0.9, "tail_z": -0.8, "tail_y": 0.62, "hull": [0.28, 0.28, 0.85, 0.95],
	},
	"vcelka": {
		"kind": "moto", "builder": "scooter", "name": "Včelka 125", "kategorie": "skútr", "skupina_rp": "A1", "cena": 38000,
		"rok": 2015, "kufr_l": 25, "nosic": true, "glb": "", "tire_w": 0.09,
		"wb": 1.3, "track": 0.62, "wheel_r": 0.24, "mass": 115.0,
		"power_kw": 7.0, "torque": 9.5, "rpm_max": 8000.0, "gears": [2.0, 1.0], "final": 8.9,
		"drag": 0.34, "com_y": 0.38, "snd_pitch": 1.7,
		"head_z": 0.6, "head_y": 0.92, "tail_z": -0.85, "tail_y": 0.72, "hull": [0.3, 0.25, 0.95, 1.05],
	},
	# vojenská motorka 40. let (ve stylu amerických 750 „flathead“ V-twin): vidlice springer, balonové
	# gumy, hluboké blatníky s návazností, kožené brašny, pružené sedlo, nášlapné plošinky, 3 stupně, ~105 km/h
	"armadka": {
		"kind": "moto", "builder": "armadka", "name": "Armádka 750", "kategorie": "motorka", "skupina_rp": "A2",
		"cena": 145000, "rok": 1943, "kufr_l": 0, "nosic": true, "glb": "", "tire_w": 0.13, "susp": 24.0,
		"wb": 1.47, "track": 0.7, "wheel_r": 0.33, "mass": 255.0,
		"power_kw": 17.0, "torque": 48.0, "rpm_max": 4600.0, "gears": [2.9, 1.7, 1.0], "final": 5.3,
		"drag": 0.36, "com_y": 0.44, "snd_pitch": 0.8, "grip": 1.15,
		"steer_v": 30.0, "steer_hi": 0.03, "lean_max": 0.55, "lean_yaw": 1.0,
		"lean_steer": 0.28, "countersteer": 0.02,
		"head_z": 0.62, "head_y": 1.0, "tail_z": -0.95, "tail_y": 0.6, "hull": [0.38, 0.28, 1.15, 1.1],
	},
	# ultra-rychlá kroska se litrovým motorem (~200 km/h+): vysoký přední blatník na vidlici, USD teleskop,
	# úzká výstroj (paprsčité kryty chladiče), vysoko vedený výfuk, široká rovná řídítka, 6 stupňů
	"krosak": {
		"kind": "moto", "builder": "krosak", "name": "Krosák 1000", "kategorie": "motorka", "skupina_rp": "A",
		"cena": 380000, "rok": 2023, "kufr_l": 0, "nosic": false, "glb": "", "tire_w": 0.12, "susp": 20.0,
		"wb": 1.44, "track": 0.68, "wheel_r": 0.31, "mass": 205.0,
		"power_kw": 135.0, "torque": 125.0, "rpm_max": 13000.0, "gears": [2.9, 2.15, 1.7, 1.4, 1.18, 1.0],
		"final": 5.5, "drag": 0.28, "com_y": 0.46, "snd_pitch": 1.2, "grip": 1.2,
		"steer_v": 25.0, "steer_hi": 0.025, "lean_max": 0.62, "lean_yaw": 1.0,
		"lean_steer": 0.3, "countersteer": 0.025,
		"head_z": 0.52, "head_y": 1.04, "tail_z": -0.86, "tail_y": 0.8, "hull": [0.34, 0.3, 1.1, 1.2],
	},
}

const HALF_PTS := 9

var model_id := "octavia"
var kind := "car"             # car / bike / moto
var spec: Dictionary
var paint := Color(0.7, 0.1, 0.1)
var police := false
var plate := "4QQ 3457"

var body_mesh: ArrayMesh
var paint_mat: StandardMaterial3D
var glass_mat: StandardMaterial3D
var head_mat: StandardMaterial3D
var tail_mat: StandardMaterial3D
var hull_points := PackedVector3Array()
var seat := Vector3(0.38, 0.15, -0.4)   # poloha řidiče (chodidla postavy)
var length := 4.5
var half_width := 0.9
var height := 1.47
var rider := {}               # póza řidiče pro Humanoid.ride (souřadnice vůči `seat`)
var eye := Vector3.ZERO       # oči řidiče pro pohled z interiéru (lokálně)
# jen jednostopá vozidla (BikeModel): natáčená vidlice s řídítky, kliky s pedály, poloha SPZ
var fork_mesh: ArrayMesh
var fork_pivot := Vector3.ZERO
var fork_axis := Vector3.UP
var crank_mesh: ArrayMesh
var crank_pivot := Vector3.ZERO
var plate_pos := Vector3.INF
var scene_root: Node3D        # karoserie z vlastního modelu (spec "scene", glTF z Blenderu) – přidá ji Car

var _surf: Array = []         # [{v, n, c, i, mat}] – pro deformaci
var _mats: Array = []


func _init(id := "octavia", color := Color(0.7, 0.1, 0.1), is_police := false, plate_text := "") -> void:
	model_id = id
	spec = MODELS[id]
	# volitelný model z .glb (M1.6): jen když soubor existuje a je naimportovaný; jinak zůstává procedurální fallback
	var glb: String = spec.get("glb", "")
	if glb != "" and kind_of(id) == "car" and not spec.has("builder") and ResourceLoader.exists(glb):
		spec = spec.duplicate()
		spec["scene"] = glb
		spec.erase("keys")
	kind = spec.get("kind", "car")
	paint = color
	police = is_police
	if plate_text != "":
		plate = plate_text


## Druh vozidla podle id ("car" / "bike" / "moto") bez stavby modelu.
static func kind_of(id: String) -> String:
	return String(MODELS[id].get("kind", "car"))


## Katalogová položka pro seznamy a bazar: název, kategorie, skupina ŘP, cena, rok, kufr, nosič.
static func catalog(id: String) -> Dictionary:
	var m: Dictionary = MODELS[id]
	return {"id": id, "name": m.get("name", id), "kategorie": m.get("kategorie", "osobní"), "skupina_rp": m.get("skupina_rp", "B"),
		"cena": int(m.get("cena", 0)), "rok": int(m.get("rok", 2000)), "kufr_l": int(m.get("kufr_l", 0)),
		"nosic": bool(m.get("nosic", false)), "tazne_kg": int(m.get("tazne_kg", 0))}


func wheel_positions() -> Array:
	var wb: float = spec["wb"]
	var tr: float = spec["track"] * 0.5
	if spec.get("lean_max", 0.0) > 0.0:
		# reálná jednostopá fyzika: jen dvě kola v ose (přední + zadní); stabilitu drží
		# náklonový regulátor v Car._balance místo čtveřice skrytých „pomocných“ kol
		return [Vector3(0, 0, wb * 0.5), Vector3(0, 0, -wb * 0.5)]
	return [Vector3(tr, 0, wb * 0.5), Vector3(-tr, 0, wb * 0.5), Vector3(tr, 0, -wb * 0.5), Vector3(-tr, 0, -wb * 0.5)]


func _key_at(z: float) -> PackedFloat32Array:
	var keys: Array = spec["keys"]
	if z <= keys[0][0]:
		return PackedFloat32Array(keys[0])
	for i in keys.size() - 1:
		var a: Array = keys[i]
		var b: Array = keys[i + 1]
		if z <= b[0]:
			var t: float = (z - float(a[0])) / (float(b[0]) - float(a[0]))
			var out := PackedFloat32Array()
			for k in 8:
				out.append(lerpf(float(a[k]), float(b[k]), t))
			out.append(a[8] if t < 0.5 else b[8])
			return out
	return PackedFloat32Array(keys[keys.size() - 1])


func _zone_between(z0: float, z1: float) -> int:
	var keys: Array = spec["keys"]
	var zm := (z0 + z1) * 0.5
	for i in keys.size() - 1:
		if zm >= keys[i][0] and zm < keys[i + 1][0]:
			var za: int = keys[i][8]
			var zb: int = keys[i + 1][8]
			return mini(za, zb) if za != zb else za
	return 0


## Poloviční řez (x ≥ 0) v místě z, s vyříznutými podběhy.
func _half_ring(z: float) -> PackedVector3Array:
	var k := _key_at(z)
	var yb := k[1]
	var ybelt := k[2]
	var ytop := k[3]
	var hwb := k[4]
	var hwbelt := k[5]
	var hwtop := k[6]
	var g := k[7]
	var wr: float = spec["wheel_r"]
	var arch := -1.0
	for wz in [spec["wb"] * 0.5, -spec["wb"] * 0.5]:
		var dz: float = z - wz
		var ra := wr + 0.07
		if absf(dz) < ra:
			arch = maxf(arch, wr + 0.02 + sqrt(ra * ra - dz * dz))
	var y_sill := yb + 0.07
	var y_mid := lerpf(yb, ybelt, 0.55)
	if arch > 0.0:
		yb = maxf(yb, arch)
		y_sill = maxf(y_sill, arch + 0.01)
		y_mid = maxf(y_mid, arch + 0.04)
		y_mid = minf(y_mid, ybelt - 0.02)
	var hw_mid := maxf(hwb, hwbelt) + 0.012
	var pts := PackedVector3Array()
	pts.append(Vector3(0.0, yb, z))
	pts.append(Vector3(hwb * 0.93, yb, z))
	pts.append(Vector3(hwb, y_sill, z))
	pts.append(Vector3(hw_mid, y_mid, z))
	pts.append(Vector3(hwbelt, ybelt, z))
	# skleník (g=1) vs. kapota/víko (g=0)
	var c5 := Vector3(lerpf(hwbelt, hwtop, 0.1), ybelt + 0.02, z)
	var c6 := Vector3(lerpf(hwbelt, hwtop, 0.88), lerpf(ybelt, ytop, 0.9), z)
	var c7 := Vector3(hwtop * 0.86, ytop - 0.006, z)
	var h5 := Vector3(hwbelt * 0.96, lerpf(ybelt, ytop, 0.35), z)
	var h6 := Vector3(hwbelt * 0.72, lerpf(ybelt, ytop, 0.8), z)
	var h7 := Vector3(hwbelt * 0.38, ytop - 0.002, z)
	pts.append(h5.lerp(c5, g))
	pts.append(h6.lerp(c6, g))
	pts.append(h7.lerp(c7, g))
	pts.append(Vector3(0.0, ytop, z))
	return pts


func _stations() -> PackedFloat32Array:
	var keys: Array = spec["keys"]
	var z0: float = keys[0][0]
	var z1: float = keys[keys.size() - 1][0]
	var zs := PackedFloat32Array()
	var z := z0
	var wr: float = spec["wheel_r"] + 0.07
	while z < z1:
		zs.append(z)
		var near_wheel := false
		for wz in [spec["wb"] * 0.5, -spec["wb"] * 0.5]:
			if absf(z - wz) < wr + 0.05:
				near_wheel = true
		z += 0.035 if near_wheel else 0.08
	zs.append(z1)
	return zs


func build() -> ArrayMesh:
	if kind != "car":
		return BikeModel.build(self)
	if spec.has("builder"):
		return TractorModel.build(self)
	if spec.has("scene"):
		return _build_from_scene()
	var zs := _stations()
	length = zs[zs.size() - 1] - zs[0]
	var grid: Array = []
	var cols: Array = []
	for z in zs:
		var h := _half_ring(z)
		var ring := PackedVector3Array()
		for j in HALF_PTS:
			ring.append(h[j])
		for j in range(HALF_PTS - 2, 0, -1):
			ring.append(Vector3(-h[j].x, h[j].y, h[j].z))
		grid.append(ring)
		half_width = maxf(half_width, h[3].x)
		height = maxf(height, h[8].y)
	var np: int = grid[0].size()
	var nr := grid.size()
	# vyhlazené normály
	var normals: Array = []
	for i in nr:
		var nn := PackedVector3Array()
		for j in np:
			var tu: Vector3 = grid[mini(i + 1, nr - 1)][j] - grid[maxi(i - 1, 0)][j]
			var tv: Vector3 = grid[i][(j + 1) % np] - grid[i][(j - 1 + np) % np]
			nn.append(tv.cross(tu).normalized())
		normals.append(nn)
	var kp := MeshKit.new()     # lak
	var kg := MeshKit.new()     # sklo
	var kt := MeshKit.new()     # plasty / pryž / chrom (barva z vrcholů)
	var trim := Color(0.06, 0.06, 0.065)
	var pillars: Array = spec["b_pillars"]
	for i in nr - 1:
		var zone := _zone_between(zs[i], zs[i + 1])
		var zm := (zs[i] + zs[i + 1]) * 0.5
		var is_pillar := false
		for pz in pillars:
			if absf(zm - pz) < 0.06:
				is_pillar = true
		var end_i := i < 2 or i >= nr - 3
		for j in np:
			var j2 := (j + 1) % np
			# index segmentu v polovičním řezu (symetricky)
			var seg := j if j < HALF_PTS - 1 else np - 1 - j
			var kit := kp
			var col := Color.WHITE
			if seg <= 1:
				kit = kt
				col = trim
			elif end_i and seg == 2:
				kit = kt
				col = trim
			elif zone == 1 and seg == 5 and not is_pillar:
				kit = kg
			elif zone == 2 and (seg == 5 or seg == 7):
				kit = kg
			elif zone == 2 and seg == 6 and spec.get("boxy", false):
				kit = kg
			_quad(kit, grid[i][j], grid[i + 1][j], grid[i][j2], grid[i + 1][j2],
				normals[i][j], normals[i + 1][j], normals[i][j2], normals[i + 1][j2], col)
	# čela (zadní a přední) – vějíř
	_cap(kp, grid[0], Vector3(0, 0, -1))
	_cap(kp, grid[nr - 1], Vector3(0, 0, 1))
	# podběhy – vnitřní tmavé "tunely" nad koly
	for wp in wheel_positions():
		if wp.x > 0:
			_arch_liner(kt, wp.z, trim.darkened(0.3))
	# hull pro kolizi: zvednutý spodek (průjezd přes hrboly a přechody silnic ~25 cm)
	# a zkosené nárazníky – na hranu auto najede jako na nájezd, nezasekne se
	var z_front := zs[nr - 1]
	var z_rear := zs[0]
	for i in range(0, nr, 5):
		var zz: float = zs[i]
		var end_t := clampf(minf(z_front - zz, zz - z_rear) / 0.7, 0.0, 1.0)
		var min_y := lerpf(0.72, 0.5, end_t)
		for j in [1, 3, 4, 6, 7]:
			var p: Vector3 = grid[i][j]
			p.y = maxf(p.y, min_y)
			hull_points.append(p)
			hull_points.append(Vector3(-p.x, p.y, p.z))
	_details(kt)
	# materiály
	paint_mat = StandardMaterial3D.new()
	paint_mat.albedo_color = paint
	paint_mat.vertex_color_use_as_albedo = false
	paint_mat.metallic = 0.5
	paint_mat.roughness = 0.3
	paint_mat.clearcoat_enabled = true
	paint_mat.clearcoat = 0.8
	paint_mat.clearcoat_roughness = 0.15
	glass_mat = StandardMaterial3D.new()
	glass_mat.albedo_color = Color(0.08, 0.1, 0.12, 0.62)
	glass_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass_mat.metallic = 0.4
	glass_mat.roughness = 0.04
	glass_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	body_mesh = ArrayMesh.new()
	_add_surface(kp, paint_mat)
	_add_surface(kg, glass_mat)
	_add_surface(kt, MeshKit.vc_material(0.55, 0.2, 0.0, false))
	# světla
	var kh := MeshKit.new()
	var ktl := MeshKit.new()
	var hz: float = spec["head_z"]
	var hy: float = spec["head_y"]
	var tz: float = spec["tail_z"]
	var ty: float = spec["tail_y"]
	var hw := _half_ring(hz)[4].x
	var tw := _half_ring(tz + 0.05)[4].x
	for s in [-1.0, 1.0]:
		kh.sphere(Vector3(s * (hw - 0.19), hy, hz), 0.1, Color(1.0, 0.98, 0.9), Vector3(1.6, 0.55, 0.9), Vector3(-0.35, 0, 0), 12, 6)
		ktl.sphere(Vector3(s * (tw - 0.12), ty, tz), 0.09, Color(0.9, 0.05, 0.03), Vector3(1.3, 0.75, 0.6), Vector3.ZERO, 12, 6)
		kh.sphere(Vector3(s * (hw - 0.02), hy - 0.02, hz - 0.1), 0.03, Color(1.0, 0.6, 0.1), Vector3(0.6, 0.6, 1.4), Vector3.ZERO, 8, 4)
	_light_mats()
	_add_surface(kh, head_mat)
	_add_surface(ktl, tail_mat)
	return body_mesh


## Auto z vlastního modelu (návod: VLASTNI_VOZIDLA.md). Karoserie = scéna ze souboru spec["scene"]
## (+Z dopředu, počátek na zemi uprostřed rozvoru, bez kol), kola procedurální nebo spec["wheel_scene"].
## Rozměry a kolizní kvádr z obálky modelu; světla jako svítící body v místech head_* / tail_*.
func _build_from_scene() -> ArrayMesh:
	var ps: PackedScene = load(spec["scene"])
	scene_root = ps.instantiate()
	var box := _scene_aabb(scene_root, Transform3D.IDENTITY)
	length = box.size.z
	half_width = maxf(-box.position.x, box.end.x)
	height = box.end.y
	var bottom := maxf(box.position.y, 0.3) + 0.2      # zvednutý spodek jako u procedurálních aut
	for x in [box.position.x, box.end.x]:
		for y in [bottom, box.end.y]:
			for z in [box.position.z, box.end.z]:
				hull_points.append(Vector3(x, y, z))
	seat = spec.get("seat", Vector3(0.38, 0.14, box.position.z * 0.2))
	var sw: Vector3 = spec.get("steering_wheel", seat + Vector3(0, 0.85, 0.46))
	var pedal := Vector3(0, float(spec.get("floor_y", 0.42)) + 0.07, seat.z + 0.78) - seat
	rider = {"hips": 0.5, "lean": -0.12, "hands": [sw - seat], "feet": [pedal, pedal]}
	eye = seat + Vector3(0, 1.17, 0.06)
	body_mesh = ArrayMesh.new()
	_light_mats()
	var kh := MeshKit.new()
	var ktl := MeshKit.new()
	for s in [-1.0, 1.0]:
		kh.sphere(Vector3(s * (half_width - 0.2), spec["head_y"], spec["head_z"]), 0.06, Color(1.0, 0.98, 0.9))
		ktl.sphere(Vector3(s * (half_width - 0.15), spec["tail_y"], spec["tail_z"]), 0.05, Color(0.9, 0.05, 0.03))
	_add_surface(kh, head_mat)
	_add_surface(ktl, tail_mat)
	return body_mesh


## Obálka všech MeshInstance3D ve scéně (scéna ještě není ve stromu → transformace skládáme ručně).
static func _scene_aabb(n: Node, xf: Transform3D) -> AABB:
	var out := AABB()
	var have := false
	var here := xf * (n as Node3D).transform if n is Node3D else xf
	if n is MeshInstance3D and (n as MeshInstance3D).mesh:
		out = here * (n as MeshInstance3D).mesh.get_aabb()
		have = true
	for ch in n.get_children():
		var b := _scene_aabb(ch, here)
		if b.size != Vector3.ZERO:
			out = b if not have else out.merge(b)
			have = true
	return out


## První mesh ve scéně (kolo z vlastního modelu: střed kola v počátku, osa kola = X).
static func first_mesh(path: String) -> Mesh:
	var n: Node = (load(path) as PackedScene).instantiate()
	var stack: Array[Node] = [n]
	var found: Mesh = null
	while not stack.is_empty() and found == null:
		var c: Node = stack.pop_back()
		if c is MeshInstance3D:
			found = (c as MeshInstance3D).mesh
		stack.append_array(c.get_children())
	n.free()
	return found


func _light_mats() -> void:
	head_mat = StandardMaterial3D.new()
	head_mat.vertex_color_use_as_albedo = true
	head_mat.emission_enabled = true
	head_mat.emission = Color(1.0, 0.97, 0.88)
	head_mat.emission_energy_multiplier = 0.3
	head_mat.roughness = 0.1
	tail_mat = StandardMaterial3D.new()
	tail_mat.vertex_color_use_as_albedo = true
	tail_mat.emission_enabled = true
	tail_mat.emission = Color(1.0, 0.05, 0.02)
	tail_mat.emission_energy_multiplier = 0.4
	tail_mat.roughness = 0.2


func _quad(kit: MeshKit, a: Vector3, c: Vector3, b: Vector3, d: Vector3,
		na: Vector3, nc: Vector3, nb: Vector3, nd: Vector3, col: Color) -> void:
	# a=(i,j) c=(i+1,j) b=(i,j+1) d=(i+1,j+1); pořadí a,c,b / b,c,d = CW zvenku
	var base := kit.verts.size()
	kit.verts.append_array([a, c, b, d])
	kit.norms.append_array([na, nc, nb, nd])
	kit.cols.append_array([col, col, col, col])
	kit.idx.append_array([base, base + 1, base + 2, base + 2, base + 1, base + 3])


func _cap(kit: MeshKit, ring: PackedVector3Array, dir: Vector3) -> void:
	var c := Vector3.ZERO
	for p in ring:
		c += p
	c /= ring.size()
	for j in ring.size():
		var a := ring[j]
		var b := ring[(j + 1) % ring.size()]
		var n := (b - c).cross(a - c)
		if n.dot(dir) < 0.0:
			kit.tri(c, b, a, Color.WHITE)
		else:
			kit.tri(c, a, b, Color.WHITE)


func _arch_liner(kit: MeshKit, wz: float, col: Color) -> void:
	var wr: float = spec["wheel_r"]
	var ra := wr + 0.065
	var cy := wr + 0.02
	var x0 := half_width - 0.04
	var x1 := half_width - 0.36
	var n := 12
	for i in n:
		var a0 := PI * float(i) / n
		var a1 := PI * float(i + 1) / n
		var p0 := Vector3(0, cy + sin(a0) * ra, wz + cos(a0) * ra)
		var p1 := Vector3(0, cy + sin(a1) * ra, wz + cos(a1) * ra)
		for s in [-1.0, 1.0]:
			var q0 := Vector3(x0 * s, p0.y, p0.z)
			var q1 := Vector3(x0 * s, p1.y, p1.z)
			var q2 := Vector3(x1 * s, p1.y, p1.z)
			var q3 := Vector3(x1 * s, p0.y, p0.z)
			kit.quad(q0, q1, q2, q3, col)
		# vnitřní stěna podběhu
	for s in [-1.0, 1.0]:
		var xw: float = x1 * s
		for i in n:
			var a0 := PI * float(i) / n
			var a1 := PI * float(i + 1) / n
			kit.tri(Vector3(xw, cy, wz), Vector3(xw, cy + sin(a0) * ra, wz + cos(a0) * ra),
				Vector3(xw, cy + sin(a1) * ra, wz + cos(a1) * ra), col)


## Maska, SPZ, zrcátka, kliky, nárazníky, interiér, policejní polepy a majáky.
func _details(k: MeshKit) -> void:
	var keys: Array = spec["keys"]
	var zf: float = keys[keys.size() - 1][0]
	var zr: float = keys[0][0]
	var chrome := Color(0.75, 0.76, 0.78)
	var black := Color(0.05, 0.05, 0.05)
	# maska chladiče
	var gy := _key_at(zf - 0.06)[1] + 0.2
	k.box(Vector3(0, gy, zf - 0.04), Vector3(0.62, 0.16, 0.06), black)
	k.box(Vector3(0, gy + 0.085, zf - 0.035), Vector3(0.64, 0.02, 0.06), chrome)
	# SPZ
	k.box(Vector3(0, gy - 0.14, zf + 0.005), Vector3(0.52, 0.115, 0.012), Color(0.95, 0.95, 0.95))
	k.box(Vector3(-0.235, gy - 0.14, zf + 0.012), Vector3(0.045, 0.11, 0.005), Color(0.1, 0.2, 0.7))
	var rpy: float = spec["tail_y"] - 0.3
	k.box(Vector3(0, rpy, zr - 0.012), Vector3(0.52, 0.115, 0.012), Color(0.95, 0.95, 0.95))
	# nárazníky – spodní lišty
	k.box(Vector3(0, _key_at(zf)[1] + 0.02, zf - 0.08), Vector3(half_width * 1.5, 0.08, 0.16), Color(0.1, 0.1, 0.1))
	k.box(Vector3(0, _key_at(zr)[1] + 0.02, zr + 0.08), Vector3(half_width * 1.5, 0.08, 0.16), Color(0.1, 0.1, 0.1))
	# zrcátka a kliky
	var mz := 0.0
	for kk in keys:
		if kk[8] == 2 and kk[0] > 0.0:
			mz = kk[0]
			break
	var mk := _key_at(mz + 0.05)
	for s in [-1.0, 1.0]:
		k.box(Vector3(s * (mk[5] + 0.07), mk[2] + 0.07, mz + 0.02), Vector3(0.13, 0.1, 0.07), paint.darkened(0.1))
		k.box(Vector3(s * (mk[5] + 0.03), mk[2] + 0.04, mz + 0.05), Vector3(0.06, 0.03, 0.04), black)
		for hz in [0.05, -0.95]:
			if hz > zr + 0.5:
				var hk := _key_at(hz)
				k.box(Vector3(s * (hk[5] + 0.004), hk[2] - 0.07, hz), Vector3(0.018, 0.025, 0.13), chrome)
	# interiér
	var seat_c := Color(0.12, 0.12, 0.13)
	var fz := mz - 0.9
	var floor_y := 0.42
	seat = Vector3(0.38, floor_y + 0.18 - 0.5 + 0.04, fz + 0.02)
	for s in [-1.0, 1.0]:
		k.box(Vector3(s * 0.38, floor_y + 0.12, fz), Vector3(0.48, 0.12, 0.5), seat_c)
		k.box(Vector3(s * 0.38, floor_y + 0.45, fz - 0.28), Vector3(0.46, 0.62, 0.1), seat_c, Vector3(-0.18, 0, 0))
		k.box(Vector3(s * 0.38, floor_y + 0.83, fz - 0.33), Vector3(0.22, 0.16, 0.08), seat_c)
	if not spec.get("single_row", spec.get("boxy", false)):
		k.box(Vector3(0, floor_y + 0.12, fz - 0.95), Vector3(1.3, 0.14, 0.5), seat_c)
		k.box(Vector3(0, floor_y + 0.42, fz - 1.2), Vector3(1.3, 0.55, 0.1), seat_c, Vector3(-0.15, 0, 0))
	# ložná plocha pickupu: tmavá podlaha a boční lišty (loft je plný, viz spec["bed"])
	if spec.has("bed"):
		var bd: Dictionary = spec["bed"]
		var bc: Vector3 = bd["c"]
		var bs: Vector3 = bd["size"]
		k.box(bc + Vector3(0, 0.008, 0), Vector3(bs.x, 0.02, bs.z), Color(0.16, 0.16, 0.17))
		for sx in [-1.0, 1.0]:
			k.box(bc + Vector3(sx * (bs.x * 0.5 + 0.03), 0.07, 0), Vector3(0.06, 0.14, bs.z + 0.08), Color(0.12, 0.12, 0.13))
		k.box(bc + Vector3(0, 0.07, bs.z * 0.5 + 0.03), Vector3(bs.x + 0.12, 0.14, 0.06), Color(0.12, 0.12, 0.13))
	# palubní deska a volant (řidič vlevo = +X)
	k.box(Vector3(0, mk[2] - 0.05, mz - 0.12), Vector3(half_width * 1.8, 0.2, 0.42), Color(0.1, 0.1, 0.11))
	var sw := Vector3(0.38, mk[2] + 0.02, mz - 0.42)
	# řidič: ruce na volantu, chodidla na pedálech pod palubní deskou (nesmí trčet podlahou)
	var pedal := Vector3(0, floor_y + 0.07, seat.z + 0.78) - seat
	rider = {"hips": 0.5, "lean": -0.12, "hands": [sw - seat], "feet": [pedal, pedal]}
	eye = seat + Vector3(0, 1.17, 0.06)
	var swb := Basis.from_euler(Vector3(-1.15, 0, 0))
	var tor := TorusMesh.new()
	tor.inner_radius = 0.16
	tor.outer_radius = 0.19
	tor.rings = 20
	tor.ring_segments = 6
	k.add_prim(tor, Transform3D(swb, sw), black)
	k.add_prim(_cyl(0.04, 0.3), Transform3D(swb * Basis.from_euler(Vector3(0, 0, 0)), sw + swb * Vector3(0, -0.12, 0)), black)
	if police:
		# policejní maják
		k.box(Vector3(0, height + 0.03, -0.3), Vector3(1.1, 0.04, 0.26), Color(0.15, 0.15, 0.15))


func _cyl(r: float, h: float) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = r
	m.bottom_radius = r
	m.height = h
	m.radial_segments = 8
	return m


func _add_surface(kit: MeshKit, mat: Material) -> void:
	if kit.is_empty():
		return
	_surf.append({"v": kit.verts.duplicate(), "n": kit.norms.duplicate(), "c": kit.cols.duplicate(),
		"i": kit.idx.duplicate(), "v0": kit.verts.duplicate()})
	_mats.append(mat)
	kit.commit(mat, body_mesh)


## Promáčkne karoserii v místě `p` (lokálně) ve směru `dir` o `depth` m s poloměrem `radius`.
func deform(p: Vector3, dir: Vector3, depth: float, radius: float) -> void:
	body_mesh.clear_surfaces()
	for si in _surf.size():
		var s: Dictionary = _surf[si]
		var v: PackedVector3Array = s["v"]
		var v0: PackedVector3Array = s["v0"]
		for i in v.size():
			var d := v[i].distance_to(p)
			if d < radius:
				var f := 1.0 - d / radius
				var nv := v[i] + dir * depth * f * f
				# nepromáčknout víc než 25 cm od původního tvaru
				if nv.distance_to(v0[i]) < 0.25:
					v[i] = nv
		s["v"] = v
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = v
		arr[Mesh.ARRAY_NORMAL] = s["n"]
		arr[Mesh.ARRAY_COLOR] = s["c"]
		arr[Mesh.ARRAY_INDEX] = s["i"]
		body_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		body_mesh.surface_set_material(si, _mats[si])


func repair() -> void:
	for s in _surf:
		s["v"] = (s["v0"] as PackedVector3Array).duplicate()
	deform(Vector3(0, -100, 0), Vector3.ZERO, 0.0, 0.01)


## Kolo: pneumatika (rotační profil kolem osy X) + disk s paprsky. `outer` = +1 pro levá kola (+X).
static func wheel_mesh(r: float, outer: float) -> ArrayMesh:
	var k := MeshKit.new()
	var w := r * 0.64
	var tire := PackedVector2Array([Vector2(r * 0.62, -w * 0.5), Vector2(r * 0.9, -w * 0.52), Vector2(r * 0.98, -w * 0.44),
		Vector2(r, -w * 0.3), Vector2(r, w * 0.3), Vector2(r * 0.98, w * 0.44), Vector2(r * 0.9, w * 0.52),
		Vector2(r * 0.62, w * 0.5)])
	var rot := Basis.from_euler(Vector3(0, 0, PI / 2))
	k.lathe(tire, Transform3D(rot, Vector3.ZERO), Color(0.07, 0.07, 0.07), 24)
	var rim := Color(0.72, 0.73, 0.75)
	var face := outer * w * 0.42
	# disk
	k.lathe(PackedVector2Array([Vector2(r * 0.63, 0.0), Vector2(r * 0.6, 0.01), Vector2(r * 0.18, 0.02),
		Vector2(0.0, 0.025)]), Transform3D(Basis.from_euler(Vector3(0, 0, -PI / 2 * outer)), Vector3(face - outer * 0.03, 0, 0)),
		rim.darkened(0.35), 20)
	for i in 5:
		var a := TAU * i / 5.0
		var sp := Vector3(face, cos(a) * r * 0.38, sin(a) * r * 0.38)
		k.box(sp, Vector3(0.025, r * 0.5, 0.05), rim, Vector3(a, 0, 0))
	k.cylinder(Vector3(face, 0, 0), r * 0.13, r * 0.13, 0.03, rim, Vector3(0, 0, PI / 2), 12)
	k.lathe(PackedVector2Array([Vector2(r * 0.6, -0.01), Vector2(r * 0.64, 0.0)]),
		Transform3D(Basis.from_euler(Vector3(0, 0, -PI / 2 * outer)), Vector3(face, 0, 0)), rim, 24)
	return k.commit(MeshKit.vc_material(0.45, 0.35))
