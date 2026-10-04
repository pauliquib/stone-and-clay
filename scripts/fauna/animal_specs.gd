## Popis všech čtyřnohých zvířat na JEDNOM místě – vzhled (rozměry, barvy, doplňky), pohyb (chody,
## zrychlení, zatáčení, skok), smysly a chování. Model (QuadrupedModel), animace (QuadrupedRig) i chování
## (Animal, Horse) se staví jen z těchto čísel → zvíře se upraví tady a nic dalšího se měnit nemusí.
##
## Náhled všech zvířat: godot --path . --script res://tools/dev/zoo.gd -- --out=zoo.png [--anim=walk|trot|gallop|graze|lie]
##
## Souřadnice modelu: počátek = země pod středem trupu, +Z dopředu (hlava), +X vlevo, Y nahoru, metry.
## Úhly v radiánech, rychlosti v m/s, hmotnost v kg. Klíče, které druh neuvede, se vezmou z DEFAULT.
class_name AnimalSpecs
extends RefCounted

const DEFAULT := {
	"name": "Zvíře",
	# ---------------- tělo
	"length": 1.0,              # trup: od zadku po hruď
	"withers": 0.7,             # výška hřbetu nad lopatkami (kohoutek)
	"croup": 0.7,               # výška hřbetu nad kyčlemi (záď)
	"chest": [0.16, 0.2],       # hrudník – poloměr do šířky a do výšky
	"belly": [0.15, 0.17],      # břicho (uprostřed trupu)
	"hips": [0.14, 0.17],       # pánev / záď
	"belly_drop": 0.0,          # jak moc břicho visí dolů (m)
	"neck": [0.34, 0.07, 0.95], # krk: délka, poloměr u trupu, úhel od vodorovné (0 = dopředu, 1,57 = svisle)
	"neck_top_r": 0.05,         # poloměr krku u hlavy
	"head": [0.22, 0.075, 0.035, 0.9], # hlava: délka, poloměr lebky, poloměr čenichu, sklon dolů od osy krku
	"ears": [0.1, 0.045, 0.5],  # uši: délka, šířka, rozevření do stran
	"eye_r": 0.013,
	"tail": [0.06, 0.025, 0.4], # ocas: délka, poloměr, sklon dolů (0 vodorovně dozadu, 1,57 svisle dolů)
	"leg_r": [0.045, 0.02],     # nohy: poloměr nahoře (stehno / předloktí) a dole (spěnka)
	"hoof": [0.03, 0.04],       # kopyto / tlapka: poloměr, výška
	"paws": false,              # tlapky místo kopyt (zajíc)
	# segmenty nohou (poměry délek) a klidové úhly segmentů od svislice (+ = konec segmentu dopředu)
	"front_seg": [0.48, 0.36, 0.16],
	"front_rest": [-0.08, 0.02, 0.45],
	"hind_seg": [0.4, 0.4, 0.2],
	"hind_rest": [0.5, -0.6, 0.12],
	# ohnutí nohy ve fázi přenosu (přičítá se ke klidovým úhlům × síla kroku)
	"front_fold": [-0.35, 1.15, 1.1],
	"hind_fold": [0.35, -0.7, 1.0],
	# vleže (nohy složené pod tělem)
	"front_lie": [1.35, -2.4, 1.2],
	"hind_lie": [1.3, -2.2, 1.9],
	# ---------------- barvy (Color) – coat: srst, belly: břicho, dark: nohy/čenich, rump: zrcátko na zadku
	"coat": Color(0.5, 0.35, 0.22),
	"belly_col": Color(0.62, 0.5, 0.38),
	"dark": Color(0.18, 0.13, 0.1),
	"rump": Color(-1, 0, 0),     # záporné r = bez zrcátka
	"nose": Color(0.06, 0.05, 0.05),
	"hoof_col": Color(0.1, 0.09, 0.08),
	"inner_ear": Color(0.35, 0.25, 0.2),
	"stripes": Color(-1, 0, 0),  # pruhy (selata) – záporné r = bez pruhů
	# ---------------- pohyb (fyzika)
	"mass": 30.0,
	"gaits": {"walk": 1.3, "trot": 3.0, "canter": 6.0, "gallop": 12.0},  # horní hranice rychlosti chodu
	"gallop_kind": "gallop",    # gallop (cval ze střídání nohou) nebo bound (zajíc – skoky, zadní nohy spolu)
	"accel": 6.0,               # max. zrychlení (m/s²)
	"brake": 9.0,               # max. zpomalení (m/s²)
	"turn": 3.5,                # max. otáčení na místě (rad/s)
	"lat_acc": 7.0,             # max. boční (dostředivé) zrychlení v zatáčce (m/s²) → poloměr zatáčky
	"jump": 1.0,                # výška, kterou přeskočí (m); 0 = neskáče
	"pronk": 0.0,               # odrazové skoky při útěku i bez překážky (srnec; výška m, 0 = ne)
	"rise_front_first": false,  # vstává předními nohama (kůň; srnec a divočák zadními)
	"max_slope": 40.0,          # nejprudší svah, kam vyleze (°)
	"step_k": 1.0,              # násobič kmitočtu kroků (menší zvíře = rychlejší kroky)
	"bob": 0.03,                # pohupování trupu v chůzi (m)
	# ---------------- smysly a chování
	"behaviour": "grazer",      # grazer (spásá), rooter (ryje), hare (zajíc)
	"habitat": "forest",        # forest, edge (okraj lesa, louky), field (pole)
	"group": [1, 1],            # velikost skupiny min–max
	"sight": 60.0,              # na kolik m si všimne chodícího člověka ve dne na volném prostranství
	"hearing": 45.0,            # na kolik m uslyší běžícího člověka / auto (×2)
	"flight": 30.0,             # úniková vzdálenost – blíž nenechá člověka přijít
	"safe": 140.0,              # po útěku se uklidní v této vzdálenosti
	"flee_speed": 6.0,          # běžná rychlost útěku (m/s); plný trysk (gallop) jen když je hrozba hodně blízko / auto
	"calm": 0.5,                # 0..1 jak rychle si zvykne na nehybného člověka dál než flight (víc = klidnější)
	"home_range": 400.0,        # poloměr okrsku kolem domova (m)
	"active": [0.0, 24.0],      # hlavní doba aktivity (h) – mimo ni hlavně odpočívá
	"graze_angle": 1.25,        # sklopení krku při pastvě (rad)
	"sounds": {},               # alarm, idle, attack → jména z NatureSfx
}

const SPECIES := {
	# ------------------------------------------------------------------ srnec obecný (Capreolus capreolus)
	# 20–30 kg, v kohoutku 65–75 cm; léto rezavě hnědý, zima šedohnědý; bílé „zrcátko“ na zadku.
	# Aktivní hlavně za soumraku; při vyrušení štěká a utíká skoky, ve skocích 1,5 m i výš.
	"srnec": {
		"name": "Srnec obecný",
		"length": 0.82, "withers": 0.72, "croup": 0.76,
		"chest": [0.13, 0.17], "belly": [0.14, 0.16], "hips": [0.12, 0.15],
		"neck": [0.33, 0.052, 1.05], "neck_top_r": 0.04,
		"head": [0.2, 0.058, 0.03, 1.4],
		"ears": [0.12, 0.05, 0.6],
		"tail": [0.03, 0.02, 0.9],
		"leg_r": [0.042, 0.016], "hoof": [0.018, 0.035],
		"coat": Color(0.56, 0.33, 0.16), "belly_col": Color(0.66, 0.5, 0.36), "dark": Color(0.3, 0.2, 0.12),
		"rump": Color(0.93, 0.9, 0.84), "nose": Color(0.05, 0.04, 0.04), "inner_ear": Color(0.6, 0.48, 0.4),
		"winter_coat": Color(0.42, 0.37, 0.31),
		"mass": 24.0,
		"gaits": {"walk": 1.2, "trot": 3.5, "canter": 7.0, "gallop": 16.0},
		"accel": 9.0, "brake": 12.0, "turn": 4.5, "lat_acc": 11.0, "jump": 1.8, "pronk": 0.95, "max_slope": 45.0,
		"step_k": 1.1, "bob": 0.025,
		"behaviour": "grazer", "habitat": "edge", "group": [1, 4],
		"sight": 55.0, "hearing": 40.0, "flight": 28.0, "safe": 90.0, "home_range": 350.0,
		"flee_speed": 8.5, "calm": 0.5,
		"active": [4.5, 9.5, 17.5, 23.0], "graze_angle": 1.3,
		"sounds": {"alarm": "deer_bark"},
		"antlers": 0.18,          # parůžky srnce (délka; srny nemají) – shazuje v listopadu, nové v březnu
	},
	# ------------------------------------------------------------------ prase divoké (Sus scrofa)
	# 50–150 kg (bachař až 200), v kohoutku 70–90 cm; tmavé štětiny, hřbetní hříva, klínovitá hlava.
	# Tlupy bachyní se selaty, ryje v lese, aktivní v noci; bachyně se selaty může zaútočit.
	"divocak": {
		"name": "Prase divoké",
		"length": 1.05, "withers": 0.8, "croup": 0.68,
		"chest": [0.22, 0.3], "belly": [0.22, 0.27], "hips": [0.18, 0.23],
		"neck": [0.14, 0.19, 0.25], "neck_top_r": 0.15,
		"head": [0.34, 0.13, 0.06, 0.6],
		"ears": [0.09, 0.05, 0.9],
		"tail": [0.22, 0.018, 1.3],
		"leg_r": [0.07, 0.025], "hoof": [0.025, 0.04],
		"front_seg": [0.5, 0.34, 0.16], "hind_seg": [0.42, 0.38, 0.2],
		"coat": Color(0.2, 0.17, 0.14), "belly_col": Color(0.24, 0.2, 0.17), "dark": Color(0.1, 0.09, 0.08),
		"nose": Color(0.22, 0.17, 0.16), "inner_ear": Color(0.15, 0.12, 0.1),
		"mane": 0.07,             # výška štětinové hřívy na hřbetě
		"tusks": 0.05,            # kly (samec delší)
		"mass": 85.0,
		"gaits": {"walk": 1.1, "trot": 3.0, "canter": 6.0, "gallop": 11.0},
		"accel": 7.0, "brake": 10.0, "turn": 3.5, "lat_acc": 8.0, "jump": 0.6, "max_slope": 40.0,
		"step_k": 1.2, "bob": 0.02,
		"behaviour": "rooter", "habitat": "forest", "group": [3, 8],
		"sight": 22.0, "hearing": 40.0, "flight": 18.0, "safe": 80.0, "home_range": 500.0,
		"flee_speed": 6.5, "calm": 0.6,
		"active": [19.0, 24.0, 0.0, 6.0], "graze_angle": 0.75,
		"sounds": {"alarm": "boar_grunt", "idle": "boar_grunt", "attack": "boar_squeal"},
		"young": "sele",          # druh mláďat ve skupině
	},
	# sele – pruhované mládě divočáka (do ~5 měsíců)
	"sele": {
		"base": "divocak", "name": "Sele",
		"length": 0.45, "withers": 0.34, "croup": 0.32,
		"chest": [0.09, 0.12], "belly": [0.09, 0.11], "hips": [0.08, 0.1],
		"neck": [0.07, 0.08, 0.25], "neck_top_r": 0.065,
		"head": [0.17, 0.06, 0.025, 0.55],
		"ears": [0.045, 0.03, 0.9], "tail": [0.08, 0.008, 1.3],
		"leg_r": [0.03, 0.012], "hoof": [0.012, 0.02],
		"coat": Color(0.45, 0.33, 0.2), "belly_col": Color(0.5, 0.4, 0.3), "stripes": Color(0.78, 0.66, 0.46),
		"mane": 0.0, "tusks": 0.0, "mass": 8.0, "step_k": 1.6,
		"gaits": {"walk": 1.0, "trot": 2.8, "canter": 5.0, "gallop": 8.0},
		"flee_speed": 5.0,
		"young": "",
	},
	# ------------------------------------------------------------------ zajíc polní (Lepus europaeus)
	# 3,5–5 kg, dlouhé uši s černou špičkou, silné zadní nohy. Přes den leží ve „pelechu“ a spoléhá na
	# maskování (strne), zvedne se až zblízka a utíká kličkami až 70 km/h.
	"zajic": {
		"name": "Zajíc polní",
		"length": 0.4, "withers": 0.3, "croup": 0.36,
		"chest": [0.075, 0.09], "belly": [0.08, 0.095], "hips": [0.085, 0.1],
		"neck": [0.07, 0.05, 0.6], "neck_top_r": 0.04,
		"head": [0.11, 0.045, 0.025, 0.7],
		"ears": [0.13, 0.03, 0.25], "ear_tip": Color(0.08, 0.07, 0.06),
		"tail": [0.06, 0.03, -0.4],
		"leg_r": [0.03, 0.012], "hoof": [0.015, 0.02], "paws": true,
		"front_seg": [0.45, 0.4, 0.15], "front_rest": [-0.25, 0.1, 0.9],
		"hind_seg": [0.3, 0.3, 0.4], "hind_rest": [0.55, -0.9, 0.9],
		"front_fold": [-0.4, 0.9, 0.6], "hind_fold": [0.5, -0.6, 0.4],
		"coat": Color(0.55, 0.45, 0.32), "belly_col": Color(0.85, 0.8, 0.72), "dark": Color(0.45, 0.36, 0.26),
		"rump": Color(0.92, 0.9, 0.86), "nose": Color(0.3, 0.2, 0.18), "inner_ear": Color(0.7, 0.55, 0.5),
		"mass": 4.2,
		"gaits": {"walk": 0.8, "trot": 2.5, "canter": 6.0, "gallop": 19.0}, "gallop_kind": "bound",
		"accel": 16.0, "brake": 18.0, "turn": 8.0, "lat_acc": 22.0, "jump": 0.8, "max_slope": 45.0,
		"step_k": 1.9, "bob": 0.02,
		"behaviour": "hare", "habitat": "field", "group": [1, 1],
		"sight": 35.0, "hearing": 28.0, "flight": 7.0, "safe": 60.0, "home_range": 300.0,
		"flee_speed": 9.0, "calm": 0.4,
		"active": [17.0, 24.0, 0.0, 8.0], "graze_angle": 0.5,
		"sounds": {},
	},
	# ------------------------------------------------------------------ kůň (dopravní prostředek)
	# Teplokrevník ~550 kg, v kohoutku 1,62 m. Chody: krok ~1,7 m/s, klus ~4, cval ~7, trysk až 15 m/s.
	"kun": {
		"name": "Kůň",
		"length": 1.45, "withers": 1.62, "croup": 1.6,
		"chest": [0.27, 0.36], "belly": [0.3, 0.37], "hips": [0.27, 0.33], "belly_drop": 0.04,
		"neck": [0.78, 0.2, 0.9], "neck_top_r": 0.1,
		"head": [0.58, 0.11, 0.075, 1.35],
		"ears": [0.15, 0.05, 0.3],
		"tail": [0.25, 0.05, 0.9], "tail_hair": 0.75,   # délka žíní ocasu
		"mane": 0.12,             # hříva (žíně na krku)
		"leg_r": [0.1, 0.035], "hoof": [0.065, 0.08],
		"front_seg": [0.5, 0.33, 0.17], "front_rest": [-0.05, 0.0, 0.5],
		"hind_seg": [0.4, 0.42, 0.18], "hind_rest": [0.42, -0.5, 0.12],
		"coat": Color(0.36, 0.2, 0.1), "belly_col": Color(0.33, 0.19, 0.1), "dark": Color(0.08, 0.06, 0.05),
		"nose": Color(0.12, 0.1, 0.09), "inner_ear": Color(0.2, 0.14, 0.1), "hair": Color(0.06, 0.05, 0.04),
		"blaze": Color(0.92, 0.9, 0.86),   # lysina na čele
		"mass": 550.0,
		"gaits": {"walk": 1.8, "trot": 4.3, "canter": 7.5, "gallop": 15.0},
		"accel": 3.2, "brake": 5.0, "turn": 1.6, "lat_acc": 5.5, "jump": 1.2, "max_slope": 35.0,
		"rise_front_first": true,   # kůň vstává předníma
		"step_k": 1.0, "bob": 0.05,
		"behaviour": "horse", "habitat": "field", "group": [1, 1],
		"sight": 50.0, "hearing": 40.0, "flight": 0.0, "safe": 0.0, "home_range": 25.0,
		"active": [0.0, 24.0], "graze_angle": 1.2,
		"sounds": {"idle": "snort", "call": "neigh"},
		"tack": true,             # sedlo, uzdečka, otěže, třmeny
	},
	# ------------------------------------------------------------------ M2.6 hospodářská zvířata (výběh u usedlosti)
	# Rozměry a barvy jsou odhad (DOPLNIT – nebyly vidět okem), model a chody sdílí s divokou zvěří beze změny;
	# chování (krmení, produkty, výběh) řeší `farm/farm_animal.gd`, ne `Animal` – tahle tabulka dává jen tělo a pohyb.
	# Mládě/dospělý je jen vizuální měřítko v `FarmAnimal` (na rozdíl od "sele" tu není zvlášť druh).
	"prase_farm": {
		"base": "divocak", "name": "Prase domácí",
		"length": 1.05, "withers": 0.72, "croup": 0.68,
		"chest": [0.26, 0.32], "belly": [0.29, 0.3], "hips": [0.22, 0.26],
		"neck": [0.1, 0.2, 0.15], "neck_top_r": 0.18,
		"head": [0.28, 0.14, 0.075, 0.45],
		"ears": [0.13, 0.09, 0.35],
		"tail": [0.1, 0.014, -0.6],
		"coat": Color(0.86, 0.68, 0.62), "belly_col": Color(0.88, 0.74, 0.68), "dark": Color(0.75, 0.55, 0.5),
		"nose": Color(0.8, 0.55, 0.52), "inner_ear": Color(0.75, 0.5, 0.5), "stripes": Color(-1, 0, 0),
		"mane": 0.0, "tusks": 0.0,
		"mass": 90.0,
		"gaits": {"walk": 0.8, "trot": 2.0, "canter": 3.5, "gallop": 4.5},
		"accel": 3.0, "brake": 5.0, "turn": 2.5, "lat_acc": 4.0, "jump": 0.2, "max_slope": 25.0,
		"step_k": 0.9, "bob": 0.015,
		"behaviour": "rooter", "habitat": "field", "group": [1, 1],
		"young": "",
	},
	"koza": {
		"name": "Koza domácí",
		"length": 0.85, "withers": 0.75, "croup": 0.73,
		"chest": [0.14, 0.18], "belly": [0.15, 0.17], "hips": [0.13, 0.16],
		"neck": [0.32, 0.07, 1.0], "neck_top_r": 0.055,
		"head": [0.2, 0.06, 0.032, 0.9],
		"ears": [0.14, 0.05, 0.7],
		"tail": [0.08, 0.02, 1.1],
		"leg_r": [0.035, 0.016], "hoof": [0.02, 0.03],
		"front_seg": [0.46, 0.36, 0.18], "hind_seg": [0.38, 0.4, 0.2],
		"coat": Color(0.82, 0.78, 0.68), "belly_col": Color(0.88, 0.85, 0.78), "dark": Color(0.3, 0.26, 0.2),
		"nose": Color(0.15, 0.12, 0.1), "inner_ear": Color(0.55, 0.4, 0.35),
		"antlers": 0.1,           # DOPLNIT: rohy sdílí tvar parůžků (jiný tvar rohů by chtěl vlastní kód v QuadrupedModel)
		"mass": 55.0,
		"gaits": {"walk": 1.0, "trot": 2.6, "canter": 4.5, "gallop": 6.0},
		"accel": 5.0, "brake": 7.0, "turn": 3.0, "lat_acc": 6.0, "jump": 0.9, "max_slope": 40.0,
		"step_k": 1.1, "bob": 0.02,
		"behaviour": "grazer", "habitat": "field", "group": [1, 3],
	},
	"ovce": {
		"name": "Ovce domácí",
		"length": 0.95, "withers": 0.72, "croup": 0.72,
		"chest": [0.21, 0.25], "belly": [0.25, 0.25], "hips": [0.2, 0.23],
		"neck": [0.2, 0.09, 0.65], "neck_top_r": 0.07,
		"head": [0.17, 0.06, 0.032, 0.9],
		"ears": [0.1, 0.04, 0.7],
		"tail": [0.1, 0.03, 1.0],
		"leg_r": [0.035, 0.015], "hoof": [0.018, 0.03],
		"coat": Color(0.88, 0.86, 0.8), "belly_col": Color(0.9, 0.88, 0.83), "dark": Color(0.2, 0.18, 0.16),
		"nose": Color(0.2, 0.18, 0.16), "inner_ear": Color(0.5, 0.4, 0.35),
		"mass": 65.0,
		"gaits": {"walk": 0.9, "trot": 2.4, "canter": 4.0, "gallop": 5.5},
		"accel": 4.5, "brake": 6.5, "turn": 2.8, "lat_acc": 5.5, "jump": 0.5, "max_slope": 35.0,
		"step_k": 1.05, "bob": 0.02,
		"behaviour": "grazer", "habitat": "field", "group": [1, 4],
	},
	"krava": {
		"name": "Kráva domácí",
		"length": 1.9, "withers": 1.35, "croup": 1.4,
		"chest": [0.36, 0.5], "belly": [0.42, 0.5], "hips": [0.32, 0.42], "belly_drop": 0.05,
		"neck": [0.55, 0.16, 0.6], "neck_top_r": 0.13,
		"head": [0.42, 0.13, 0.08, 1.0],
		"ears": [0.24, 0.1, 0.9],
		"tail": [0.6, 0.025, 1.4], "tail_hair": 0.3,
		"leg_r": [0.09, 0.032], "hoof": [0.05, 0.06],
		"front_seg": [0.48, 0.35, 0.17], "hind_seg": [0.4, 0.4, 0.2],
		"coat": Color(0.55, 0.42, 0.3), "belly_col": Color(0.75, 0.7, 0.62), "dark": Color(0.2, 0.16, 0.12),
		"rump": Color(0.85, 0.8, 0.72), "nose": Color(0.3, 0.28, 0.28), "inner_ear": Color(0.55, 0.45, 0.4),
		"mass": 450.0,
		"gaits": {"walk": 1.3, "trot": 2.8, "canter": 4.5, "gallop": 6.0},
		"accel": 2.5, "brake": 4.0, "turn": 1.4, "lat_acc": 4.0, "jump": 0.3, "max_slope": 25.0,
		"step_k": 0.75, "bob": 0.04,
		"behaviour": "grazer", "habitat": "field", "group": [1, 1],
	},
	# králík domácí – menší a klidnější variace zajíce (base "zajic"); "flight" a "sight" se u chovu nevyužívají
	"kralik": {
		"base": "zajic", "name": "Králík domácí",
		"length": 0.32, "withers": 0.22, "croup": 0.26,
		"ears": [0.09, 0.025, 0.15],
		"coat": Color(0.85, 0.82, 0.76), "belly_col": Color(0.92, 0.9, 0.85), "dark": Color(0.55, 0.5, 0.42),
		"rump": Color(-1, 0, 0),
		"mass": 2.2,
		"gaits": {"walk": 0.5, "trot": 1.5, "canter": 3.0, "gallop": 6.0},
		"flee_speed": 4.0,
	},
}


## Úplný popis druhu: DEFAULT ← případný základní druh ("base") ← vlastní hodnoty.
static func get_spec(id: String) -> Dictionary:
	var own: Dictionary = SPECIES[id]
	var s := DEFAULT.duplicate(true)
	if own.has("base"):
		s.merge(get_spec(own["base"]), true)
	s.merge(own, true)
	s["id"] = id
	return s


## Je v tuto hodinu druh hlavně aktivní? `active` = dvojice [od, do] (h), i několik intervalů.
static func is_active(spec: Dictionary, h: float) -> bool:
	var a: Array = spec["active"]
	for i in range(0, a.size() - 1, 2):
		if h >= a[i] and h <= a[i + 1]:
			return true
	return false
