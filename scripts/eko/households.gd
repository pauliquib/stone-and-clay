## M8.17 Život vesnice – **domácnosti, potřeby, vztahy a drby** (instance `World.households`, přepínač realismu
## `village_life`). Vesnice se chová stejně, i když se hráč nedívá: v domě bydlí rodina, ráno se rozsvítí kuchyň
## a přiloží se do kamen, v sobotu na podzim se štípe dřevo, sousedé si pomáhají a hádají se, drby se šíří od hospody.
##
## Podle čeho (00_PRINCIPY kap. 1): **utility AI** (užitek činnosti = Σ potřeba × uspokojení + povinnost domu,
## × okno hodin × počasí × sezóna × povaha) a **denní rozvrh spánku**; topení jako jednoduchá **denostupňová
## potřeba tepla** `(T_základ − T_venku) / rozsah` (vytápěcí den v ČR se počítá od 13 °C venku, vnitřní 18–20 °C);
## šíření drbů jako **epidemie po síti kontaktů** (SI model – kdo se potká v hospodě / na návštěvě / na ulici).
##
## - **Domácnosti** se skládají deterministicky (seed = id budovy z `Estate`): obydlené rodinné domy (`INHABITED`)
##   a byty bytového domu; členové = postavy s modelem (`Villager`, domov = `Estate.pick_customer_house` jako v BT)
##   + **neviditelní obyvatelé** (jen data). Zdroj tepla (dřevo / plyn / elektřina), zahrada, auto, pes, slepice.
## - **Plán dne po hodinách** (`World.eco_hour` → `EcoClock.slice`, `HOUR_SLICE` domácností za snímek, žádná práce
##   za snímek): vesničan s modelem dostane cíl (`Villager.set_plan` → `move_to`), neviditelní jen „kde jsou“.
## - **Dům jako stav:** kdo je doma, které místnosti svítí (`window_rooms` → `BuildingDetails` / shader oken),
##   jak silně kouří komín (`chimney_heat` → `ChimneySmoke`), zásoba dřeva, zvuky štípání a sekačky (nedělní klid
##   přes `World.noise.offense_for`).
## - **Vztahy a drby:** sousedé (`NEIGHBOURS` nejbližších), příbuzní, rivalové; události (pomoc se sněhem, spor kvůli
##   sekačce, chybí dřevo…) a činy hráče (`on_event` z `World.emit_game_event`) jdou do **paměti drbů**, ta se šíří
##   sítí a vesničan je řekne v rozhovoru (`gossip_line` → `Dialog.rumor`). Popularitu M7 jen čte (nic nemění).
##
## Data: `data/potreby.json` (potřeby, činnosti, počasí, složení, jména, texty drbů). Ladění: F3 → Člověk/Život vesnice
## (`scripts/dev/tune_m8_17.gd`), F2 → Příroda – ladění → Domácnosti, vrstva mapy „obyvatele“.
class_name Households
extends Node

const DATA_PATH := "res://data/potreby.json"
const ROOMS := ["kuchyn", "obyvak", "loznice", "ostatni"]       # ↔ kanály RGBA textury oken (BuildingDetails)
const HOME_KDE := ["doma"]

## ---- laditelné (F3 → Člověk/Život vesnice) – `static var`, výchozí = herní odhad
static var INHABITED := 0.7            # podíl obydlených rodinných domů (jako InteriorStreamer.INHABITED)
static var FLAT_INHABITED := 0.85      # podíl obydlených bytů v bytovém domě
static var HOUR_SLICE := 8             # domácností za snímek při hodinovém kroku (EcoClock.slice)
static var JITTER := 0.12              # ± náhodná složka užitku (deterministická – seed dům, člen, hodina)
static var DUTY_K := 1.0               # váha povinností domu proti potřebám
static var NEED_MAX := 1.5             # strop potřeby
## rozvrh spánku (h) – vstávání a ulehání podle role; víkend později
static var WAKE_WORKER := 5.6
static var WAKE_ADULT := 6.4
static var WAKE_SENIOR := 6.1
static var WAKE_CHILD := 6.5
static var WAKE_JITTER := 0.7
static var WEEKEND_LATE := 1.3
static var SLEEP_ADULT := 22.7
static var SLEEP_SENIOR := 21.7
static var SLEEP_CHILD := 20.7
static var SLEEP_JITTER := 0.9
static var NIGHT_OWL_H := 1.4          # povaha „mlady“ / „veselak“ chodí spát později o tolik
static var MORNING_KITCHEN_H := 0.85   # po vstávání tolik h v kuchyni (snídaně → svítí kuchyň)
static var BED_BEFORE_H := 0.5         # před spaním tolik h svítí ložnice
static var BED_AFTER_H := 0.15         # po probuzení tolik h svítí ložnice
## práce a dojíždění
static var COMMUTE_P := 0.7            # dospělý bez místní práce dojíždí (pryč 6:30–15:30 v pracovní den)
static var LOCAL_JOB_P := 0.12         # dospělý neviditelný obyvatel pracuje v obci (úřad, obchod, statek…)
## topení
static var HEAT_BASE_C := 16.0         # °C venku, pod kterou se topí (vytápěcí den ~13 °C, obec teplejší)
static var HEAT_RANGE_C := 22.0        # °C pod základem → plná potřeba tepla 1
static var FIRE_DECAY_H := 0.35        # pokles ohně v kamnech za hodinu bez přiložení
static var STOKE_FIRE := 1.0           # přiložení (ráno, po návratu) – síla ohně
static var STOKE_DEMAND_K := 1.4       # síla přiložení × potřeba tepla
static var NIGHT_FIRE := 0.25          # v noci kamna dohořívají (× potřeba)
static var NIGHT_KEEP_P := 0.35        # podíl domácností s kamny, které přes noc udržují oheň (ostatní vyhasnou)
static var MORNING_SMOKE_H := 1.2      # ráno po vstávání tolik h silnější kouř (zatápění)
static var GAS_SMOKE := 0.3            # plynový kotel – slabá vlečka × potřeba tepla
static var GAS_NIGHT_K := 0.6          # útlum kotle v noci
static var WOOD_BURN_H := 0.0045       # prms dřeva za hodinu při plném ohni (~10–14 prms za sezónu)
static var WOOD_START := 9.0           # prms na začátku topné sezóny (říjen)
static var WOOD_TARGET := 11.0         # prms – do zimy chtějí mít tolik (štípou do této zásoby)
static var WOOD_LOW := 1.5             # prms – pod tím „nemají dřevo“ (drb)
static var WOOD_CHOP_H := 0.5          # prms naštípaných za hodinu štípání
static var CHOP_MAX_H_DAY := 3         # nejvýš tolik hodin štípání za den
## povinnosti domu
static var FOOD_USE_D := 0.22          # zásoba jídla – úbytek za den (na 1 člena × 0,5 + 0,5)
static var FOOD_SHOP := 0.6            # nákup přidá
static var FOOD_LOW := 0.35            # pod tím se chce nakoupit
static var MOW_EVERY_D := 8.0          # tráva se seká po tolika dnech
static var MOW_GDD := 160.0            # suma teplot (Phenology.gdd, základ 5 °C), od které tráva roste na seč
static var GARDEN_GDD := 60.0          # … od které se pracuje na zahradě
static var RAKE_EVERY_D := 6.0         # listí se hrabe po tolika dnech (říjen, listopad)
static var SNOW_MIN := 0.3             # snow_cover, od kterého se odhazuje sníh
static var SENIOR_SNOW_K := 0.25       # osamělý senior se do sněhu skoro nepustí (pomoc souseda)
static var DUTY_SNOW := 1.3            # síla povinností
static var DUTY_MOW := 0.7
static var DUTY_WOOD := 0.75
static var DUTY_WOOD_LOW := 1.1
static var DUTY_GARDEN := 0.45
static var DUTY_RAKE := 0.5
static var DUTY_SHOP := 0.9
static var WET_MAX := 0.45             # Weather.wetness_ground nad tím se neseká ani nehrabe
## vztahy a drby
static var NEIGHBOURS := 4             # sousedé = tolik nejbližších domácností
static var NEIGHBOUR_R := 110.0        # m – dál už to není soused
static var RELATIVE_P := 0.35          # domácnost má v obci příbuzné
static var REL_MIN := -0.45            # počáteční vztah sousedů (seed) od
static var REL_MAX := 0.85             # … do
static var REL_RELATIVE := 0.7         # vztah s příbuznými
static var RIVAL_BELOW := -0.15        # pod tím rivalové (spory)
static var FRIEND_ABOVE := 0.35        # nad tím pomáhají, půjčují, navštěvují
static var REL_HELP := 0.08            # pomoc zlepší vztah o
static var REL_FIGHT := -0.12          # spor zhorší vztah o
static var REL_VISIT := 0.03           # návštěva zlepší vztah o
static var P_FIGHT_NOISE := 0.22       # šance sporu, když rival seká (za hodinu)
static var P_FIGHT_DOG := 0.012        # šance sporu kvůli psovi (za den, pár rivalů se psem)
static var P_LEND := 0.03              # šance půjčky nářadí (za den, přátelé)
static var P_VISIT_GOSSIP := 0.25      # návštěva se stane drbem
static var P_PUB_GOSSIP := 0.06        # pozdní hospoda se stane drbem
static var P_GARDEN_GOSSIP := 0.015    # zahrada „jak ze škatulky“
static var P_NO_WOOD := 0.6            # došlé dřevo v topné sezóně se stane drbem (za den)
static var P_SNOW_HELP := 0.7          # soused pomůže seniorovi se sněhem
static var EVENTS_PER_DAY := 5         # strop nových drbů mezi domácnostmi za den
static var SPREAD_PUB := 0.55          # šance předání drbu v hospodě (za hodinu, posluchač)
static var SPREAD_VISIT := 0.8         # … na návštěvě
static var SPREAD_STREET := 0.25       # … potkání na ulici / v obchodě se sousedem
static var SPREAD_HUB := 0.5           # hospodský / prodavačka (Npc) zná drby, co prošly hospodou / obchodem
static var GOSSIP_MAX := 40            # paměť drbů (nejnovější)
static var GOSSIP_DAYS := 21.0         # starší drby se zapomenou
static var TELL_MIN_DAYS := 0.0        # vesničan vypráví drby staré aspoň tolik dní
static var TELL_P := 0.75              # šance, že na „co je nového“ řekne skutečný drb (jinak staré hlášky)
static var WITNESS_R := 120.0          # m – kdo „viděl“ hráčův čin (domácnosti v okruhu znají drb hned)
## zvuky u domů (štípání, sekačka) – jen v okolí hráče
static var SOUND_R := 140.0            # m – domácnosti, které je slyšet
static var SOUND_NEAR_S := 3.0         # s – obnova seznamu blízkých domů
static var CHOP_EVERY_S := 2.1         # s mezi údery sekery
static var MOW_EVERY_S := 0.65         # s mezi „zabručeními“ sekačky
static var CHOP_VOL := -4.0            # dB u zdroje
static var MOW_VOL := -13.0
static var SOUND_ATTEN := 0.12         # dB/m útlum
static var MOW_PITCH := 1.0            # M8.18: sekačka má vlastní zvuk (NatureSfx „mower“); dřív 0,42 = zpomalená pila
static var RAKE_EVERY_S := 1.3         # M8.18: s mezi tahy hrábí (± 20 %)
static var SHOVEL_EVERY_S := 2.4       # M8.18: s mezi odhozením sněhu
static var RAKE_VOL := -14.0           # M8.18: dB u zdroje
static var SHOVEL_VOL := -10.0
## vesničan s modelem
static var HIDE_INSIDE := true         # doma (spánek, jídlo, odpočinek) se schová do domu
static var SNAP_DEEP := true           # za simulační bublinou se přesune rovnou na místo (bez chůze)
static var DRESS_WARM_C := 15.0        # °C – pod tím větrovka
static var DRESS_COLD_C := 5.0         # °C – pod tím bunda, čepice, rukavice

## Kategorie Persona pro neviditelné (vyprávění, klepání).
const TRAIT_KEYS := ["pratelsky", "drbna", "bruclavy", "prisny", "veselak", "plachy", "moudry", "mlady"]

static var _data: Dictionary = {}

var world: World
var hh: Array = []                     # domácnosti (Dictionary – viz _make_household)
var _by_eid := {}                      # id budovy → Array[int] indexy domácností (byty)
var _persona_hh := {}                  # Persona → index domácnosti (postavy s modelem, děda)
var _empty_eids := {}                  # id neobydlených rodinných domů (okna tmavá, komín studený)
var _cells := {}                       # Vector2i (8 m) → index domácnosti, −2 = neobydlený dům (vrstva mapy)
var _rel := {}                         # klíč dvojice (a * 65536 + b, a < b) → vztah −1..1 (seed + vývoj)
var _rel_seed := {}                    # tentýž klíč → výchozí (seed) – ukládá se jen rozdíl
var gossip: Array = []                 # paměť drbů [{id, jd, h, text, kind, subj, known: PackedByteArray, hub}]
var _gid := 0
var version := 0                       # roste s každým dokončeným hodinovým krokem (BuildingDetails obnoví okna)
var _pool_pub: PackedInt32Array = PackedInt32Array()
var _pool_shop: PackedInt32Array = PackedInt32Array()
var _pool_street: PackedInt32Array = PackedInt32Array()
var _visits: PackedInt32Array = PackedInt32Array()      # dvojice [host, návštěva, host, návštěva …]
var _events_today := 0
var _events_jd := -1
var _rng := RandomNumberGenerator.new()
var _tell_rng := RandomNumberGenerator.new()   # vyprávění drbů (vlastní – neruší řadu simulace `_rng`, M8.19)
var _tell_n := 0                         # pořadí dotazu na drb (seed vyprávění)
var _near: PackedInt32Array = PackedInt32Array()        # domácnosti v doslechu hráče
var _snd_next: PackedFloat32Array = PackedFloat32Array()
var _near_t := 0.0
var _clock_s := 0.0
var _home_keys := {}                   # "eid:flat" domovů hráčů (jejich dům se nesimuluje – svítí a topí hráč)
var built := false
var _released := false


# ------------------------------------------------------------------ data

## Katalog `data/potreby.json` (statický – čte ho i registr F3).
static func data() -> Dictionary:
	if _data.is_empty():
		var f := FileAccess.get_file_as_string(DATA_PATH)
		var d = JSON.parse_string(f) if f != "" else null
		_data = d if d is Dictionary else {"potreby": {}, "cinnosti": {}}
	return _data


func enabled() -> bool:
	return built and world != null and world.realism_on("village_life")


# ------------------------------------------------------------------ sestavení

## Postaví domácnosti z registru nemovitostí (po `Estate`, vesničanech a místech). Deterministické.
func setup(w: World) -> void:
	world = w
	name = "Domacnosti"
	data()
	var est: Estate = w.estate
	if est == null:
		return
	# 1) postavy s modelem → domov (stejný los jako BT: Estate.pick_customer_house(seed, 700))
	var vill_home := {}                # eid → Array[Villager]
	if w.bots_root != null:
		var n := 0
		for c in w.bots_root.get_children():
			var v := c as Villager
			if v == null:
				continue
			n += 1
			if n > World.N_VILLAGERS:
				break                  # víkendoví navíc nemají domov v registru
			var eid: int = est.pick_customer_house(v._seed, 700.0)
			if eid == 0:
				continue
			if not vill_home.has(eid):
				vill_home[eid] = []
			(vill_home[eid] as Array).append(v)
	# 2) domy a byty
	var ids: Array = est.estates.keys()
	ids.sort()
	for id_v in ids:
		var eid: int = id_v
		var e: Dictionary = est.estates[id_v]
		if not est._dwelling_ok(eid, e) and eid != est.deda_id:
			continue
		var typ := String(e.get("type", ""))
		if typ == "bytovy_dum":
			var flats := maxi(int(e.get("flats", 0)), 1)
			for f in range(1, flats + 1):
				if _hash01(eid, f, 11) < FLAT_INHABITED:
					_make_household(e, f, [])
			continue
		var vs: Array = vill_home.get(eid, [])
		var deda := eid == est.deda_id
		if vs.is_empty() and not deda and _hash01(eid, 0, 7) >= INHABITED:
			_mark_cells(e, -2)
			_empty_eids[eid] = true
			continue
		_make_household(e, 0, vs, deda)
	_build_relations()
	_snd_next.resize(hh.size())
	built = true
	w.eco_hour.connect(_on_eco_hour)
	w.eco_day.connect(_on_eco_day)
	w.debug_layers["obyvatele"] = Callable(self, "debug_layer")
	_check_homes(true)
	# první plán hned (jinak by se čekalo na celou herní hodinu)
	_on_eco_hour(0.0)


static func _hash01(a: int, b: int, salt: int) -> float:
	var h := absi(hash("%d:%d:%d" % [a, b, salt]))
	return float(h % 100000) / 100000.0


func _make_household(e: Dictionary, flat: int, vs: Array, deda := false) -> void:
	var eid: int = e["id"]
	var r := RandomNumberGenerator.new()
	r.seed = hash("hh:%d:%d" % [eid, flat])
	var d := data()
	var door: Vector3 = e.get("door", Vector3.INF)
	if not (door is Vector3) or door == Vector3.INF:
		var c2: Vector2 = e.get("center", Vector2.ZERO)
		door = Vector3(c2.x, world.terrain.height_at(c2.x, c2.y), c2.y)
	var nrm: Vector3 = e.get("normal", Vector3(0, 0, 1))
	var members: Array = []
	var surname := ""
	var female0 := false
	for v_ in vs:
		var v: Villager = v_
		var prof: Dictionary = v.persona.profile if v.persona else {}
		var age := int(prof.get("age", 40))
		var m := _member(r, _role_of_age(age), String(prof.get("trait", "pratelsky")))
		m["name"] = String(prof.get("name", "?"))
		m["female"] = bool(prof.get("look", {}).get("female", false))
		m["v"] = v
		m["persona"] = v.persona
		var key := v._workplace_key()
		m["job"] = key if key != "" else ("" if m["role"] != "dospely" else ("dojizdi" if r.randf() < COMMUTE_P else ""))
		members.append(m)
		if surname == "":
			surname = _last_word(m["name"])
			female0 = m["female"]
	if deda and world.npcs.has("deda"):
		var dn: Npc = world.npcs["deda"]
		var m := _member(r, "senior", "moudry")
		m["name"] = dn.persona.display_name() if dn.persona else "děda"
		m["persona"] = dn.persona
		members.append(m)
		if surname == "":
			surname = _last_word(m["name"])
	var comp := "vesnican"
	if members.is_empty():
		var vars_: Array = d.get("slozeni", {}).get("varianty", [])
		var tot := 0.0
		for x in vars_:
			tot += float(x[1])
		var pick := r.randf() * tot
		var roles: Array = ["dospely"]
		for x in vars_:
			pick -= float(x[1])
			if pick <= 0.0:
				roles = x[2]
				comp = String(x[0])
				break
		var names: Dictionary = d.get("jmena", {})
		var sn: Array = names.get("prijmeni", ["Novotvar"])
		surname = String(sn[r.randi() % sn.size()])
		for i in roles.size():
			var role := String(roles[i])
			var m := _member(r, role, String(TRAIT_KEYS[r.randi() % TRAIT_KEYS.size()]))
			var fem := (i % 2 == 1) if roles.size() >= 2 and role != "dite" else r.randf() < 0.5
			m["female"] = fem
			var fl: Array = names.get("zena" if fem else "muz", ["Jan"])
			m["name"] = "%s %s" % [String(fl[r.randi() % fl.size()]), _surname_for(surname, fem)]
			if role == "dospely":
				m["job"] = _local_job(r) if r.randf() < LOCAL_JOB_P else ("dojizdi" if r.randf() < COMMUTE_P else "")
			members.append(m)
	elif members.size() == 1 and not deda and r.randf() < 0.55:
		# postava s modelem nežije sama – partner/ka (jen data)
		var m0: Dictionary = members[0]
		var role0 := String(m0["role"])
		var m := _member(r, "senior" if role0 == "senior" else "dospely", String(TRAIT_KEYS[r.randi() % TRAIT_KEYS.size()]))
		var fem := not bool(m0["female"])
		m["female"] = fem
		var fl: Array = d.get("jmena", {}).get("zena" if fem else "muz", ["Jan"])
		m["name"] = "%s %s" % [String(fl[r.randi() % fl.size()]), _surname_for(_male_surname(surname, female0), fem)]
		if role0 != "senior":
			m["job"] = "dojizdi" if r.randf() < COMMUTE_P else ""
		members.append(m)
	var any_senior := false
	var all_senior := true
	for m in members:
		if m["role"] == "senior":
			any_senior = true
		else:
			all_senior = false
	var heat := _pick_heat(r, e, flat, any_senior)
	var vb: Dictionary = d.get("vybava", {})
	var fam := _family_forms(_male_surname(surname, female0))
	var h := {
		"i": hh.size(), "eid": eid, "flat": flat, "pos": door, "normal": nrm,
		"center": e.get("center", Vector2(door.x, door.z)), "fam": fam, "comp": comp,
		"heat": heat, "garden": flat == 0 and r.randf() < float(vb.get("zahrada", 0.85)),
		"car": r.randf() < float(vb.get("auto_senior" if all_senior else "auto", 0.7)),
		"dog": flat == 0 and r.randf() < float(vb.get("pes", 0.38)),
		"hens": flat == 0 and r.randf() < float(vb.get("slepice", 0.22)),
		"senior_alone": all_senior and members.size() == 1,
		"members": members, "wood": WOOD_START * r.randf_range(0.6, 1.2), "fire": 0.0, "food": r.randf_range(0.5, 1.0),
		"mow_jd": -999, "rake_jd": -999, "snow_jd": -999, "chop_jd": -1, "chop_h": 0, "no_wood_jd": -999,
		"neigh": PackedInt32Array(), "rel_of": -1, "visit": -1, "duties": {}, "awake_home": false,
	}
	hh.append(h)
	var idx: int = h["i"]
	if not _by_eid.has(eid):
		_by_eid[eid] = []
	(_by_eid[eid] as Array).append(idx)
	for m in members:
		if m.get("persona") != null:
			_persona_hh[m["persona"]] = idx
		var v = m.get("v")
		if v != null and is_instance_valid(v):
			(v as Villager).household = idx
	_mark_cells(e, idx)


func _member(r: RandomNumberGenerator, role: String, trait_: String) -> Dictionary:
	var wake := WAKE_ADULT
	var sleep := SLEEP_ADULT
	match role:
		"senior":
			wake = WAKE_SENIOR
			sleep = SLEEP_SENIOR
		"dite":
			wake = WAKE_CHILD
			sleep = SLEEP_CHILD
	if trait_ in ["mlady", "veselak"]:
		sleep += NIGHT_OWL_H
	return {"name": "", "female": false, "role": role, "trait": trait_, "job": "", "v": null, "persona": null,
		"wake0": wake + r.randf_range(-0.5, 0.5) * WAKE_JITTER, "sleep0": sleep + r.randf_range(-0.5, 0.5) * SLEEP_JITTER,
		"wake": wake, "sleep": sleep, "act": "spanek", "home": true, "room": "", "kde": "doma",
		"needs": {"jidlo": r.randf() * 0.3, "prace": 0.0, "hygiena": r.randf() * 0.3, "spolecnost": r.randf() * 0.5,
			"odpocinek": r.randf() * 0.3}}


static func _role_of_age(age: int) -> String:
	if age >= 63:
		return "senior"
	if age < 18:
		return "dite"
	return "dospely"


func _local_job(r: RandomNumberGenerator) -> String:
	var keys := ["urad", "obchod", "hospoda", "statek"]
	return String(keys[r.randi() % keys.size()])


func _pick_heat(r: RandomNumberGenerator, e: Dictionary, flat: int, senior: bool) -> String:
	var t: Dictionary = data().get("teplo", {})
	if flat > 0:
		return "plyn"
	var wd := float(t.get("drevo", 0.42))
	if senior:
		wd += float(t.get("senior_drevo", 0.2))
	if int(e.get("floors", 1)) <= 1 and float(e.get("area", 100.0)) < 120.0:
		wd += float(t.get("maly_dum_drevo", 0.12))
	var wg := float(t.get("plyn", 0.42))
	var we := float(t.get("elektrina", 0.16))
	var x := r.randf() * (wd + wg + we)
	if x < wd:
		return "drevo"
	if x < wd + wg:
		return "plyn"
	return "elektrina"


static func _last_word(full: String) -> String:
	var p := full.split(" ", false)
	return p[p.size() - 1] if p.size() > 0 else full


## Mužský tvar příjmení z ženského („Pupíková“ → „Pupík“; „Veselá“ → „Veselý“).
static func _male_surname(s: String, female: bool) -> String:
	if not female:
		return s
	if s.ends_with("ová"):
		return s.substr(0, s.length() - 3)
	if s.ends_with("á"):
		return s.substr(0, s.length() - 1) + "ý"
	return s


## Ženský / mužský tvar příjmení z mužského („Kutílek“ → „Kutílková“).
static func _surname_for(male: String, female: bool) -> String:
	if not female:
		return male
	if male.ends_with("ý"):
		return male.substr(0, male.length() - 1) + "á"
	return _stem(male) + "ová"


static func _stem(male: String) -> String:
	if male.ends_with("ek") and male.length() > 3:
		return male.substr(0, male.length() - 2) + "k"
	if male.ends_with("a") or male.ends_with("o"):
		return male.substr(0, male.length() - 1)
	return male


## Rodina v pádech pro drby: [1. pád „Kutílkovi“, 2. pád „Kutílkových“, 7. pád „Kutílkovými“].
static func _family_forms(male: String) -> Array:
	if male.ends_with("ý") or male.ends_with("í"):
		var b := male.substr(0, male.length() - 1)
		return [b + "í", b + "ých", b + "ými"]
	var s := _stem(male)
	return [s + "ovi", s + "ových", s + "ovými"]


func _mark_cells(e: Dictionary, idx: int) -> void:
	var poly: PackedVector2Array = e.get("poly", PackedVector2Array())
	if poly.is_empty():
		var c: Vector2 = e.get("center", Vector2.ZERO)
		_cells[Vector2i(floori(c.x / 8.0), floori(c.y / 8.0))] = idx
		return
	var mn := poly[0]
	var mx := poly[0]
	for p in poly:
		mn = mn.min(p)
		mx = mx.max(p)
	for cx in range(floori(mn.x / 8.0), floori(mx.x / 8.0) + 1):
		for cz in range(floori(mn.y / 8.0), floori(mx.y / 8.0) + 1):
			if not _cells.has(Vector2i(cx, cz)) or idx >= 0:
				_cells[Vector2i(cx, cz)] = idx


## Sousedé (nejbližší domácnosti), příbuzní, počáteční vztahy – deterministicky.
func _build_relations() -> void:
	var n := hh.size()
	for i in n:
		var a: Dictionary = hh[i]
		var ca: Vector2 = a["center"]
		var best: Array = []
		for j in n:
			if j == i:
				continue
			var d := ca.distance_to(hh[j]["center"])
			if d > NEIGHBOUR_R:
				continue
			best.append([d, j])
		best.sort_custom(func(x, y): return x[0] < y[0])
		var ng := PackedInt32Array()
		for k in mini(NEIGHBOURS, best.size()):
			ng.append(int(best[k][1]))
		a["neigh"] = ng
	for i in n:
		var a: Dictionary = hh[i]
		for j in (a["neigh"] as PackedInt32Array):
			var k := _rel_key(i, j)
			if not _rel_seed.has(k):
				var lo := mini(i, j)
				var hi := maxi(i, j)
				_rel_seed[k] = lerpf(REL_MIN, REL_MAX, _hash01(int(hh[lo]["eid"]) + int(hh[lo]["flat"]), int(hh[hi]["eid"]) + int(hh[hi]["flat"]), 3))
		if n > 1 and _hash01(int(a["eid"]), int(a["flat"]), 5) < RELATIVE_P:
			var j := int(_hash01(int(a["eid"]), int(a["flat"]), 9) * n) % n
			if j != i:
				a["rel_of"] = j
				if int(hh[j]["rel_of"]) < 0:
					hh[j]["rel_of"] = i
				_rel_seed[_rel_key(i, j)] = REL_RELATIVE
	_rel = _rel_seed.duplicate()


static func _rel_key(a: int, b: int) -> int:
	return mini(a, b) * 65536 + maxi(a, b)


func relation(a: int, b: int) -> float:
	return float(_rel.get(_rel_key(a, b), 0.0))


func _rel_add(a: int, b: int, d: float) -> void:
	var k := _rel_key(a, b)
	_rel[k] = clampf(float(_rel.get(k, 0.0)) + d, -1.0, 1.0)


# ------------------------------------------------------------------ hodinový krok (plán dne)

func _on_eco_hour(dt_h: float) -> void:
	if built and not enabled():
		_release_villagers()
		return
	if hh.is_empty():
		return
	_released = false
	var clock: Clock = world.clock
	var wth: Weather = world.weather
	if clock == null or wth == null:
		return
	_check_homes(false)
	var h := clock.hour()
	var wd := clock.weekday()
	var holiday := clock.holiday() != ""
	var ctx := {
		"h": h, "jd": clock.jd(), "month": clock.month(), "weekend": wd >= 5 or holiday,
		"hidx": clock.jd() * 24 + int(h), "dt": maxf(dt_h, 0.0),
		"temp": wth.temp, "rain": wth.rain if wth.is_raining() else 0.0, "snowing": wth.is_snowing(),
		"snow": wth.snow_cover, "wet": wth.wetness_ground(),
		"gdd": world.phenology.gdd() if world.phenology != null else _gdd_fallback(clock.month()),
		"pub_open": _place_open("hospoda", h), "shop_open": _place_open("obchod", h),
		"mow_ok": world.noise == null or world.noise.offense_for("sekacka") == "",
	}
	_pool_pub.clear()
	_pool_shop.clear()
	_pool_street.clear()
	_visits.clear()
	if world.eco != null and dt_h > 0.0:
		world.eco.slice(hh.size(), HOUR_SLICE, _step.bind(ctx))
	else:
		for i in hh.size():
			_step(i, ctx)


## Přepínač `village_life` vypnut → vesničany s modelem pusť z domů a nech je chodit jako dřív (jednou).
func _release_villagers() -> void:
	if _released:
		return
	_released = true
	for house in hh:
		for m in (house["members"] as Array):
			var v = m.get("v")
			if v != null and is_instance_valid(v):
				(v as Villager).set_plan(Vector3.INF, false, "", false)
				(v as Villager).dress_level(0)


func _place_open(key: String, h: float) -> bool:
	var pl: Place = world.places.get(key)
	return pl != null and pl.is_open(h)


static func _gdd_fallback(month: int) -> float:
	return [0.0, 0.0, 10.0, 80.0, 250.0, 520.0, 850.0, 1200.0, 1450.0, 1600.0, 1650.0, 1650.0][clampi(month - 1, 0, 11)]


func _step(i: int, ctx: Dictionary) -> void:
	if i < 0 or i >= hh.size():
		return
	var house: Dictionary = hh[i]
	var h: float = ctx["h"]
	var dt: float = ctx["dt"]
	var jd: int = ctx["jd"]
	if int(house["chop_jd"]) != jd:
		house["chop_jd"] = jd
		house["chop_h"] = 0
	_duties(house, ctx)
	var awake_home := false
	var anyone_home := false
	var came_home := false
	var acts: Dictionary = data().get("cinnosti", {})
	for mi in (house["members"] as Array).size():
		var m: Dictionary = house["members"][mi]
		var was_home: bool = m["home"]
		_schedule(m, ctx)
		var act := _choose(house, m, mi, ctx, acts)
		_apply_act(house, m, act, acts, ctx)
		if m["home"]:
			anyone_home = true
			if act != "spanek":
				awake_home = true
				if not was_home:
					came_home = true
		_grow_needs(m, act, dt)
		_apply_plan(house, m)
	house["awake_home"] = awake_home
	_heat(house, ctx, anyone_home, awake_home, came_home)
	if i == hh.size() - 1:
		_spread(ctx)
		version += 1


## Vstávání / ulehání pro dnešek (víkend později; povaha).
func _schedule(m: Dictionary, ctx: Dictionary) -> void:
	var late := WEEKEND_LATE if bool(ctx["weekend"]) else 0.0
	var wake: float = float(m["wake0"]) + late
	if m["role"] == "dospely" and String(m["job"]) != "" and not bool(ctx["weekend"]):
		wake = minf(wake, WAKE_WORKER + (float(m["wake0"]) - WAKE_ADULT))
	m["wake"] = wake
	m["sleep"] = float(m["sleep0"]) + late * 0.6


static func asleep(m: Dictionary, h: float) -> bool:
	var s: float = m["sleep"]
	var w: float = m["wake"]
	if s >= 24.0:
		return (h >= s - 24.0 and h < w)
	return h >= s or h < w


## Povinnosti domu (0 = není co dělat) – podle stavu domu, sezóny a počasí.
func _duties(house: Dictionary, ctx: Dictionary) -> void:
	var d: Dictionary = house["duties"]
	var jd: int = ctx["jd"]
	var month: int = ctx["month"]
	var wet: float = ctx["wet"]
	var gdd: float = ctx["gdd"]
	var food: float = house["food"]
	d["nakup"] = DUTY_SHOP * (FOOD_LOW - food) / FOOD_LOW + 0.2 if food < FOOD_LOW else 0.0
	d["zahrada"] = DUTY_GARDEN if bool(house["garden"]) and gdd >= GARDEN_GDD and month >= 3 and month <= 10 else 0.0
	var mow := 0.0
	if bool(house["garden"]) and month >= 4 and month <= 10 and gdd >= MOW_GDD and wet < WET_MAX \
			and float(jd - int(house["mow_jd"])) >= MOW_EVERY_D and bool(ctx["mow_ok"]):
		mow = DUTY_MOW + 0.05 * minf(float(jd - int(house["mow_jd"])) - MOW_EVERY_D, 6.0)
	d["sekani"] = mow
	var wood := 0.0
	if String(house["heat"]) == "drevo" and int(house["chop_h"]) < CHOP_MAX_H_DAY and bool(ctx["mow_ok"]):
		var w: float = house["wood"]
		if w < WOOD_LOW:
			wood = DUTY_WOOD_LOW
		elif w < WOOD_TARGET and month >= 8 and month <= 11:
			wood = DUTY_WOOD * clampf((WOOD_TARGET - w) / WOOD_TARGET + 0.5, 0.0, 1.5)
	d["drevo"] = wood
	d["listi"] = DUTY_RAKE if bool(house["garden"]) and (month == 10 or month == 11) and wet < WET_MAX \
		and float(jd - int(house["rake_jd"])) >= RAKE_EVERY_D else 0.0
	var snow := 0.0
	if float(ctx["snow"]) >= SNOW_MIN and int(house["snow_jd"]) != jd:
		snow = DUTY_SNOW * (SENIOR_SNOW_K if bool(house["senior_alone"]) else 1.0)
	d["snih"] = snow


## Utility AI: činnost s nejvyšším užitkem (deterministicky – seed dům, člen, hodina).
func _choose(house: Dictionary, m: Dictionary, mi: int, ctx: Dictionary, acts: Dictionary) -> String:
	var h: float = ctx["h"]
	if asleep(m, h):
		return "spanek"
	var since := fposmod(h - float(m["wake"]), 24.0)
	if since < MORNING_KITCHEN_H:
		return "snidane"
	_rng.seed = hash(Vector3i(int(house["eid"]) + int(house["flat"]) * 7919, mi, int(ctx["hidx"])))
	var needs: Dictionary = m["needs"]
	var duties: Dictionary = house["duties"]
	var role: String = m["role"]
	var trait_: String = m["trait"]
	var weekend: bool = ctx["weekend"]
	var best := "odpocinek"
	var best_s := -1.0
	var pocasi: Dictionary = data().get("pocasi", {})
	for id_v in acts:
		var id: String = id_v
		if id.begins_with("_"):
			continue
		var a: Dictionary = acts[id_v]
		if not (a.get("role", []) as Array).has(role):
			continue
		if not (_in_window(a.get("hodiny", []), h) or _in_window(a.get("hodiny2", []), h)):
			continue
		var dny := String(a.get("dny", "vse"))
		if (dny == "prac" and weekend) or (dny == "vikend" and not weekend):
			continue
		if id == "prace" and String(m["job"]) == "":
			continue
		var misto := String(a.get("misto", ""))
		if misto == "hospoda" and not bool(ctx["pub_open"]):
			continue
		if misto == "obchod" and not bool(ctx["shop_open"]):
			continue
		var kde := String(a.get("kde", "doma"))
		if kde == "navsteva" and _visit_target(house) < 0:
			continue
		var s := float(a.get("zaklad", 0.0))
		var pn: Dictionary = a.get("potreby", {})
		for k in pn:
			s += float(needs.get(k, 0.0)) * float(pn[k])
		var duty := String(a.get("povinnost", ""))
		if duty != "":
			var dv := float(duties.get(duty, 0.0))
			if dv <= 0.0:
				continue
			s += dv * DUTY_K
		if s <= 0.0:
			continue
		var mes: Dictionary = a.get("mesice", {})
		if not mes.is_empty():
			s *= float(mes.get(str(ctx["month"]), 1.0))
		s *= float((a.get("povaha", {}) as Dictionary).get(trait_, 1.0))
		if weekend:
			s *= float((a.get("dny_k", {}) as Dictionary).get("vikend", 1.0))
		if bool(house["dog"]) and a.has("pes"):
			s *= float(a["pes"])
		if bool(a.get("venku", false)):
			s *= _weather_k(ctx, pocasi)
		s *= 1.0 + JITTER * (_rng.randf() * 2.0 - 1.0)
		if s > best_s:
			best_s = s
			best = id
	return best


static func _in_window(w: Array, h: float) -> bool:
	if w.size() < 2:
		return false
	var a := float(w[0])
	var b := float(w[1])
	return h >= a and h < b


static func _weather_k(ctx: Dictionary, p: Dictionary) -> float:
	var k := 1.0
	var rain: float = ctx["rain"]
	if rain > 0.0:
		k *= lerpf(1.0, float(p.get("dest", 0.15)), clampf(rain * 2.0, 0.0, 1.0))
	if bool(ctx["snowing"]):
		k *= float(p.get("snezi", 0.35))
	var t: float = ctx["temp"]
	if t < float(p.get("mraz_c", -6.0)):
		k *= float(p.get("mraz", 0.5))
	var hh_: float = ctx["h"]
	if t > float(p.get("vedro_c", 29.0)) and hh_ >= 11.0 and hh_ < 16.0:
		k *= float(p.get("vedro", 0.45))
	return k


## Koho jde domácnost navštívit (příbuzní, jinak nejlepší soused nad FRIEND_ABOVE); −1 = nikoho.
func _visit_target(house: Dictionary) -> int:
	var i: int = house["i"]
	var rel: int = house["rel_of"]
	if rel >= 0:
		return rel
	var best := -1
	var bv := FRIEND_ABOVE
	for j in (house["neigh"] as PackedInt32Array):
		var r := relation(i, j)
		if r > bv:
			bv = r
			best = j
	return best


## Zapíše činnost do člena a stavu domu (kde je, místnost, uspokojení, povinnosti, sociální pooly, události).
func _apply_act(house: Dictionary, m: Dictionary, act: String, acts: Dictionary, ctx: Dictionary) -> void:
	var i: int = house["i"]
	m["act"] = act
	var kde := "doma"
	var room := ""
	match act:
		"spanek":
			room = ""
		"snidane":
			room = "kuchyn"
		_:
			var a: Dictionary = acts.get(act, {})
			kde = String(a.get("kde", "doma"))
			room = String(a.get("mistnost", ""))
			var pn: Dictionary = a.get("potreby", {})
			var needs: Dictionary = m["needs"]
			for k in pn:
				needs[k] = maxf(float(needs.get(k, 0.0)) - float(pn[k]), 0.0)
	if act == "snidane":
		(m["needs"] as Dictionary)["jidlo"] = 0.0
		(m["needs"] as Dictionary)["hygiena"] = 0.0
	if kde == "prace" and String(m["job"]) == "dojizdi":
		kde = "pryc"
	m["kde"] = kde
	m["room"] = room
	m["home"] = kde == "doma"
	var jd: int = ctx["jd"]
	match act:
		"sekani":
			house["mow_jd"] = jd
			_noise_fight(house, ctx)
		"listi":
			house["rake_jd"] = jd
		"snih":
			house["snow_jd"] = jd
		"drevo":
			house["wood"] = float(house["wood"]) + WOOD_CHOP_H
			house["chop_h"] = int(house["chop_h"]) + 1
		"nakup":
			house["food"] = minf(float(house["food"]) + FOOD_SHOP, 1.0)
			_pool_shop.append(i)
		"hospoda":
			_pool_pub.append(i)
			if float(ctx["h"]) >= 22.0 and _rng.randf() < P_PUB_GOSSIP:
				_event("hospoda", i, -1, ctx)
		"navsteva":
			var t := _visit_target(house)
			if t >= 0:
				house["visit"] = t
				_visits.append(t)
				_visits.append(i)
				_rel_add(i, t, REL_VISIT)
				if _rng.randf() < P_VISIT_GOSSIP * 0.2:
					_event("navsteva", t, i, ctx)
		"prochazka":
			_pool_street.append(i)
		"zahrada":
			if _rng.randf() < P_GARDEN_GOSSIP:
				_event("zahrada", i, -1, ctx)


func _grow_needs(m: Dictionary, act: String, dt: float) -> void:
	if act == "spanek" or dt <= 0.0:
		return
	var rates: Dictionary = data().get("potreby", {})
	var needs: Dictionary = m["needs"]
	for k in rates:
		if String(k).begins_with("_"):
			continue
		if k == "prace" and (String(m["job"]) == "" and m["role"] != "dite"):
			continue
		needs[k] = minf(float(needs.get(k, 0.0)) + float(rates[k]) * dt, NEED_MAX)


## Topení: potřeba tepla z teploty u domu (Microclimate), kdo je doma, přikládání; zásoba dřeva a jídla.
func _heat(house: Dictionary, ctx: Dictionary, anyone_home: bool, awake_home: bool, came_home: bool) -> void:
	var dt: float = maxf(float(ctx["dt"]), 1.0)
	var pos: Vector3 = house["pos"]
	var t_out: float = world.micro.temp_at(pos) if world.micro != null else float(ctx["temp"])
	var demand := clampf((HEAT_BASE_C - t_out) / HEAT_RANGE_C, 0.0, 1.0)
	house["demand"] = demand
	var fire: float = house["fire"]
	match String(house["heat"]):
		"drevo":
			var decay := FIRE_DECAY_H * dt
			if demand <= 0.01:
				fire = maxf(fire - decay, 0.0)
			elif awake_home:
				if came_home:
					fire = maxf(fire, minf(STOKE_FIRE, demand * STOKE_DEMAND_K + 0.3))
				else:
					fire = maxf(fire - decay, demand * 0.8)
			elif anyone_home:
				# v noci dohořívá – přes noc přikládá jen část domácností (ráno pak kouří víc komínů)
				var keep := _hash01(int(house["eid"]), int(house["flat"]), 31) < NIGHT_KEEP_P
				fire = maxf(fire - decay, NIGHT_FIRE * demand if keep else 0.0)
			else:
				fire = maxf(fire - decay, 0.0)
			var w := float(house["wood"]) - WOOD_BURN_H * fire * dt
			if w <= 0.0:
				w = 0.0
				fire = 0.0
			house["wood"] = w
			var month: int = ctx["month"]
			var season := month >= 10 or month <= 4
			if w < WOOD_LOW and season and demand > 0.2 and int(house["no_wood_jd"]) < int(ctx["jd"]) - 6:
				house["no_wood_jd"] = ctx["jd"]
				if _hash01(int(house["eid"]), int(ctx["jd"]), 21) < P_NO_WOOD:
					_event("bez_dreva", int(house["i"]), -1, ctx)
		"plyn":
			fire = demand * GAS_SMOKE * (1.0 if awake_home else GAS_NIGHT_K)
		_:
			fire = 0.0
	house["fire"] = fire
	# jídlo ubývá podle počtu členů
	var n := (house["members"] as Array).size()
	house["food"] = maxf(float(house["food"]) - FOOD_USE_D / 24.0 * dt * (0.5 + 0.5 * n), 0.0)


## Rival vedle seká (hluk) → spor (drb).
func _noise_fight(house: Dictionary, ctx: Dictionary) -> void:
	var i: int = house["i"]
	for j in (house["neigh"] as PackedInt32Array):
		if relation(i, j) < RIVAL_BELOW and _rng.randf() < P_FIGHT_NOISE:
			_rel_add(i, j, REL_FIGHT)
			_event("spor_hluk", j, i, ctx)
			return


## Denní krok: nové topné období (zásoba dřeva), pomoc se sněhem, psi, půjčky.
func _on_eco_day(jd: int) -> void:
	if not enabled():
		return
	var clock: Clock = world.clock
	var ctx := {"jd": jd, "month": clock.month(), "h": clock.hour(), "hidx": jd * 24}
	_rng.seed = jd * 7717 + 3
	var snow: float = world.weather.snow_cover if world.weather else 0.0
	for i in hh.size():
		var house: Dictionary = hh[i]
		# senior sám a sníh → pomůže soused s dobrým vztahem
		if snow >= SNOW_MIN and bool(house["senior_alone"]):
			for j in (house["neigh"] as PackedInt32Array):
				if relation(i, j) > FRIEND_ABOVE and _rng.randf() < P_SNOW_HELP:
					house["snow_jd"] = jd
					_rel_add(i, j, REL_HELP)
					_event("pomoc_snih", i, j, ctx)
					break
		for j in (house["neigh"] as PackedInt32Array):
			if j <= i:
				continue
			var r := relation(i, j)
			if r < RIVAL_BELOW and (bool(house["dog"]) or bool(hh[j]["dog"])) and _rng.randf() < P_FIGHT_DOG:
				_rel_add(i, j, REL_FIGHT)
				var dog_of := i if bool(house["dog"]) else j
				_event("spor_pes", dog_of, j if dog_of == i else i, ctx)
			elif r > FRIEND_ABOVE and _rng.randf() < P_LEND:
				_rel_add(i, j, REL_HELP * 0.5)
				_event("pujcka", i, j, ctx)
	# zapomínání
	var keep: Array = []
	for g in gossip:
		if float(jd - int(g["jd"])) <= GOSSIP_DAYS:
			keep.append(g)
	gossip = keep


# ------------------------------------------------------------------ postavy s modelem

## Cíl pro vesničana s modelem podle místa činnosti (BT vesničany nechá být – řídí je strom).
func _apply_plan(house: Dictionary, m: Dictionary) -> void:
	var v = m.get("v")
	if v == null or not is_instance_valid(v):
		return
	var vil: Villager = v
	if vil.use_bt:
		return
	var door: Vector3 = house["pos"]
	var nrm: Vector3 = house["normal"]
	var kde: String = m["kde"]
	var target := Vector3.INF
	var inside := false
	var anim := ""
	var acts: Dictionary = data().get("cinnosti", {})
	var a: Dictionary = acts.get(String(m["act"]), {})
	match kde:
		"doma":
			target = door
			inside = HIDE_INSIDE
		"dvur":
			target = door + nrm * 2.5 + nrm.cross(Vector3.UP).normalized() * 2.0
			anim = String(a.get("anim", ""))
		"zahrada":
			target = door + nrm * Villager.GARDEN_D
			anim = String(a.get("anim", ""))
		"prace":
			target = vil._workplace_pos()
		"hospoda":
			target = vil._pub_table_pos()
		"obchod":
			var pl: Place = world.places.get("obchod")
			target = pl.door if pl else Vector3.INF
		"navsteva":
			var t: int = house["visit"]
			if t >= 0 and t < hh.size():
				target = hh[t]["pos"]
				inside = HIDE_INSIDE
	if target != Vector3.INF and world.terrain != null:
		target.y = world.terrain.height_at(target.x, target.z)
	vil.set_plan(target, inside, anim, SNAP_DEEP)
	_dress(vil, house)


## Oblékání podle teploty u domu (háček z M8.16): větrovka / bunda + čepice + rukavice.
func _dress(v: Villager, house: Dictionary) -> void:
	var t: float = world.micro.temp_at(house["pos"]) if world.micro != null else world.weather.temp
	var lvl := 0
	if t < DRESS_COLD_C:
		lvl = 2
	elif t < DRESS_WARM_C:
		lvl = 1
	v.dress_level(lvl)


# ------------------------------------------------------------------ dům jako stav (okna, komín, klepání)

func _check_homes(_force: bool) -> void:
	_home_keys.clear()
	var est: Estate = world.estate
	if est == null:
		return
	for pid in est.homes:
		_home_keys["%d:%d" % [est.home_estate(pid), maxi(est.home_flat(pid), 0)]] = true
		_home_keys["%d:0" % est.home_estate(pid)] = true


func _is_player_home(house: Dictionary) -> bool:
	return _home_keys.has("%d:%d" % [int(house["eid"]), int(house["flat"])])


## Má budova simulované obyvatele? (false = staré chování oken a komína – veřejné budovy, domov hráče.)
func has_house(bid: int) -> bool:
	if not enabled() or not _by_eid.has(bid):
		return false
	for i in (_by_eid[bid] as Array):
		if _is_player_home(hh[i]):
			return false
	return true


## Je obytný dům bez obyvatel (30 % neobydlených) – okna tmavá, komín nekouří.
func is_empty_dwelling(bid: int) -> bool:
	return enabled() and _empty_eids.has(bid) and not _home_keys.has("%d:0" % bid)


## Svícení místností budovy v hodině `h` (0..1 na kanál ROOMS). `false` = budovu nesimuluju (volající použije starou křivku).
func window_rooms(bid: int, h: float, out: PackedFloat32Array) -> bool:
	out[0] = 0.0
	out[1] = 0.0
	out[2] = 0.0
	out[3] = 0.0
	if is_empty_dwelling(bid):
		return true
	if not has_house(bid):
		return false
	for i in (_by_eid[bid] as Array):
		var house: Dictionary = hh[i]
		var nf := float((_by_eid[bid] as Array).size())
		var w := 1.0 / nf if nf > 1.0 else 1.0      # bytový dům: každý byt rozsvítí svůj díl oken
		for m in (house["members"] as Array):
			var r := _room_at(m, h)
			if r >= 0:
				out[r] = minf(out[r] + w, 1.0)
	return true


## Místnost člena v čase `h` (index ROOMS) nebo −1 (spí / není doma).
static func _room_at(m: Dictionary, h: float) -> int:
	var wake: float = m["wake"]
	var sleep: float = m["sleep"]
	var to_sleep := fposmod(sleep - h, 24.0)
	var since := fposmod(h - wake, 24.0)
	if asleep(m, h):
		return -1
	if since < BED_AFTER_H:
		return 2
	if since < MORNING_KITCHEN_H:
		return 0
	if to_sleep < BED_BEFORE_H:
		return 2 if bool(m["home"]) or String(m["act"]) == "spanek" else -1
	if not bool(m["home"]):
		return -1
	match String(m["room"]):
		"kuchyn":
			return 0
		"obyvak":
			return 1
		"loznice":
			return 2
		"ostatni":
			return 3
	return 1


## Síla kouře z komína budovy (0 = netopí, ~1 = přiloženo); −1 = budovu nesimuluju (stará pravděpodobnost).
func chimney_heat(bid: int, h: float) -> float:
	if is_empty_dwelling(bid):
		return 0.0
	if not has_house(bid):
		return -1.0
	var best := 0.0
	for i in (_by_eid[bid] as Array):
		var house: Dictionary = hh[i]
		var f: float = house["fire"]
		if String(house["heat"]) == "drevo" and float(house.get("demand", 0.0)) > 0.02 and float(house["wood"]) > 0.0:
			for m in (house["members"] as Array):
				var since := fposmod(h - float(m["wake"]), 24.0)
				if since < MORNING_SMOKE_H and not asleep(m, h):
					f = maxf(f, minf(STOKE_FIRE, float(house["demand"]) * STOKE_DEMAND_K + 0.3))
		best = maxf(best, f)
	return best


## Je někdo z domácnosti doma (klepání, InteriorStreamer)? −1 = budovu nesimuluju.
func home_state(bid: int, flat: int) -> int:
	if not enabled() or not _by_eid.has(bid):
		return -1
	for i in (_by_eid[bid] as Array):
		var house: Dictionary = hh[i]
		if int(house["flat"]) != flat and not (flat == 0 and (_by_eid[bid] as Array).size() == 1):
			continue
		for m in (house["members"] as Array):
			if bool(m["home"]):
				return 1
		return 0
	return -1


## Obyvatel, který otevře (postava s modelem / děda, jinak neviditelný – Persona se vytvoří až na požádání).
func resident_persona(bid: int, flat: int) -> Persona:
	if not enabled() or not _by_eid.has(bid):
		return null
	for i in (_by_eid[bid] as Array):
		var house: Dictionary = hh[i]
		if int(house["flat"]) != flat and not (flat == 0 and (_by_eid[bid] as Array).size() == 1):
			continue
		var pick: Dictionary = {}
		for m in (house["members"] as Array):
			if m["role"] == "dite":
				continue
			if bool(m["home"]) or pick.is_empty():
				pick = m
			if bool(m["home"]):
				break
		if pick.is_empty():
			return null
		if pick.get("persona") == null:
			var age := 72 if pick["role"] == "senior" else 40
			var p := Persona.make({"name": pick["name"], "trait": pick["trait"], "age": age,
				"job": "důchodce" if pick["role"] == "senior" else ("dojíždí za prací" if pick["job"] == "dojizdi" else "v domácnosti"),
				"look": {"female": pick["female"]}, "topics": ["drby", "pocasi"]})
			pick["persona"] = p
			_persona_hh[p] = i
		return pick["persona"]
	return null


# ------------------------------------------------------------------ drby

## Nový drb mezi domácnostmi: `a` (o kom), `b` (druhá strana, −1). Znají ho hned obě strany a jejich sousedé.
func _event(kind: String, a: int, b: int, ctx: Dictionary) -> void:
	var jd: int = ctx["jd"]
	if _events_jd != jd:
		_events_jd = jd
		_events_today = 0
	if _events_today >= EVENTS_PER_DAY:
		return
	var texts: Array = data().get("udalosti", {}).get(kind, [])
	if texts.is_empty() or a < 0 or a >= hh.size():
		return
	_events_today += 1
	var t := String(texts[(jd + a) % texts.size()])
	var fa: Array = hh[a]["fam"]
	var fb: Array = hh[b]["fam"] if b >= 0 and b < hh.size() else ["sousedi", "sousedů", "sousedy"]
	var mes: Array = data().get("mesice", [])
	var month: int = ctx["month"]
	t = t.replace("{a}", String(fa[0])).replace("{a2}", String(fa[1])).replace("{a7}", String(fa[2])) \
		.replace("{b}", String(fb[0])).replace("{b2}", String(fb[1])).replace("{b7}", String(fb[2])) \
		.replace("{mesic}", String(mes[month - 1]) if mes.size() >= 12 else "")
	var g := _new_gossip(kind, t, a, jd, float(ctx.get("h", 12.0)))
	var known: PackedByteArray = g["known"]
	for x in [a, b]:
		if x >= 0 and x < hh.size():
			known[x] = 1
			for j in (hh[x]["neigh"] as PackedInt32Array):
				known[j] = 1


func _new_gossip(kind: String, text: String, subj: int, jd: int, h: float) -> Dictionary:
	var known := PackedByteArray()
	known.resize(hh.size())
	_gid += 1
	var g := {"id": _gid, "jd": jd, "h": h, "text": text, "kind": kind, "subj": subj, "known": known, "hub": false}
	gossip.append(g)
	if gossip.size() > GOSSIP_MAX:
		gossip = gossip.slice(gossip.size() - GOSSIP_MAX)
	return g


## Činy hráče → paměť drbů (volá `World.emit_game_event`). Znají ho domácnosti v okruhu `WITNESS_R` (svědci),
## jinak jen hospoda (hub). Popularitu M7 to nemění – ta se čte z Reputation / Persona.
func on_event(pid: int, kind: String, d: Dictionary) -> void:
	if not enabled():
		return
	var texts: Array = data().get("drby_hrac", {}).get(kind, [])
	if texts.is_empty():
		return
	var co := ""
	match kind:
		"hit_animal", "hunt_kill":
			var sp := String(d.get("species", ""))
			co = String(data().get("zver_4p", {}).get(sp, "zvíře"))
		"fish_caught":
			if float(d.get("kg", 0.0)) < 2.0:
				return
		"offense":
			var o := Law.offense(String(d.get("id", "")))
			co = String(o.get("drb", String(o.get("nazev", "něco provedl")).to_lower()))
		"favor_done":
			co = String(d.get("to", "sousedovi"))
		"job_hired":
			co = String(Jobs.job(String(d.get("job", ""))).get("zamestnavatel", "nich"))
	var jd: int = world.clock.jd()
	var home := world.estate.home_label(pid) if world.estate else "vsi"
	var t := String(texts[(jd + gossip.size()) % texts.size()]).replace("{domov}", home).replace("{co}", co)
	var g := _new_gossip(kind, t, -2, jd, world.clock.hour())
	var known: PackedByteArray = g["known"]
	var pos = d.get("pos", null)
	if not (pos is Vector3):
		var p: Player = world.players.get(pid)
		pos = p.global_position if p else Vector3.INF
	var any := false
	if pos is Vector3 and pos != Vector3.INF:
		for i in hh.size():
			var c: Vector2 = hh[i]["center"]
			if c.distance_to(Vector2(pos.x, pos.z)) < WITNESS_R:
				known[i] = 1
				any = true
	if not any:
		g["hub"] = true          # nikdo z domů to neviděl – ví to hospoda (a od ní dál)


## Šíření drbů za hodinu: hospoda (všichni u stolu), návštěvy (host ↔ návštěva), ulice a obchod (se sousedem).
func _spread(ctx: Dictionary) -> void:
	if gossip.is_empty():
		return
	_rng.seed = int(ctx["hidx"]) * 31 + 17
	for g in gossip:
		var known: PackedByteArray = g["known"]
		if known.size() != hh.size():
			continue
		# hospoda: stačí, aby to věděl jeden u stolu (nebo hospodský – hub)
		var pub_knows: bool = g["hub"]
		for i in _pool_pub:
			if known[i] == 1:
				pub_knows = true
				break
		if pub_knows and not _pool_pub.is_empty():
			g["hub"] = true
			for i in _pool_pub:
				if known[i] == 0 and _rng.randf() < SPREAD_PUB:
					known[i] = 1
		for i in _pool_shop:
			if known[i] == 1:
				g["hub"] = true
			elif bool(g["hub"]) and _rng.randf() < SPREAD_PUB * 0.5:
				known[i] = 1
		var k := 0
		while k + 1 < _visits.size():
			var host := _visits[k]
			var guest := _visits[k + 1]
			if known[host] != known[guest] and _rng.randf() < SPREAD_VISIT:
				known[host] = 1
				known[guest] = 1
			k += 2
		for i in _pool_street:
			var ng: PackedInt32Array = hh[i]["neigh"]
			if ng.is_empty():
				continue
			var j := ng[_rng.randi() % ng.size()]
			if known[i] != known[j] and _rng.randf() < SPREAD_STREET:
				known[i] = 1
				known[j] = 1


## Drb, který zná postava (`Persona`): domácnost postavy, jinak hospoda / obchod (hub). "" = žádný.
func gossip_line(per: Persona) -> String:
	if not enabled() or per == null or gossip.is_empty():
		return ""
	var idx: int = _persona_hh.get(per, -1)
	var jd: int = world.clock.jd()
	var h := world.clock.hour()
	var cands: Array = []
	for g in gossip:
		var age := float(jd - int(g["jd"])) + (h - float(g["h"])) / 24.0
		if age < TELL_MIN_DAYS:
			continue
		if idx >= 0:
			if int(g["subj"]) == idx:
				continue                 # o sobě drby nevypráví
			var known: PackedByteArray = g["known"]
			if idx >= known.size() or known[idx] == 0:
				continue
		elif not bool(g["hub"]):
			continue
		cands.append(g)
	if cands.is_empty():
		return ""
	# M8.19: deterministicky (00_PRINCIPY kap. 1.4) – seed z postavy, dne, čtvrthodiny a pořadí dotazu
	_tell_n += 1
	_tell_rng.seed = hash([String(per.profile.get("name", "")), jd, int(h * 4.0), _tell_n])
	if _tell_rng.randf() > TELL_P or (idx < 0 and _tell_rng.randf() > SPREAD_HUB):
		return ""
	# novější přednostně (z posledních tří náhodně)
	var g: Dictionary = cands[cands.size() - 1 - _tell_rng.randi() % mini(3, cands.size())]
	return _with_when(String(g["text"]), jd - int(g["jd"]))


func _with_when(t: String, days: int) -> String:
	var k: Dictionary = data().get("kdy", {})
	var w := ""
	if days <= 0:
		w = String(k.get("0", "dneska"))
	elif days == 1:
		w = String(k.get("1", "včera"))
	elif days == 2:
		w = String(k.get("2", "předevčírem"))
	else:
		w = String(k.get("n", "před {n} dny")).replace("{n}", str(days))
	t = t.replace("{kdy}", w)
	# velké písmeno na začátku věty
	return t.substr(0, 1).to_upper() + t.substr(1) if t.length() > 0 else t


# ------------------------------------------------------------------ zvuky u domů (klient: World.sound)

func _process(delta: float) -> void:
	if not built or hh.is_empty():
		return
	_clock_s += delta
	_near_t -= delta
	if _near_t <= 0.0:
		_near_t = SOUND_NEAR_S
		_refresh_near()
	if _near.is_empty():
		return
	for i in _near:
		if _clock_s < _snd_next[i]:
			continue
		var house: Dictionary = hh[i]
		var snd := ""
		for m in (house["members"] as Array):
			var a := String(m["act"])
			if a == "drevo":
				snd = "chop"
				break
			if a == "sekani":
				snd = "mower"
			elif a == "listi" and snd == "":
				snd = "rake"                   # M8.18: hrabání listí
			elif a == "snih" and snd == "":
				snd = "shovel"                 # M8.18: odhazování sněhu
		if snd == "":
			_snd_next[i] = _clock_s + 1.0
			continue
		var pos: Vector3 = house["pos"]
		var p := world.nearest_player(pos)
		var dist := p.global_position.distance_to(pos) if p else SOUND_R
		if snd == "chop":
			_snd_next[i] = _clock_s + CHOP_EVERY_S * (0.85 + 0.3 * fposmod(float(i) * 0.37 + _clock_s, 1.0))
			world.sound.emit(pos, "chop", 0.9 + 0.2 * fposmod(_clock_s * 3.1, 1.0), CHOP_VOL - dist * SOUND_ATTEN, SOUND_R)
		elif snd == "mower":
			_snd_next[i] = _clock_s + MOW_EVERY_S
			world.sound.emit(pos, "mower", MOW_PITCH, MOW_VOL - dist * SOUND_ATTEN, SOUND_R)
		else:                                  # M8.18: hrábě / lopata (zvuky NatureSfx, Sfx „rake“ / „shovel“)
			var rake := snd == "rake"
			_snd_next[i] = _clock_s + (RAKE_EVERY_S if rake else SHOVEL_EVERY_S) * (0.8 + 0.4 * fposmod(float(i) * 0.61 + _clock_s, 1.0))
			world.sound.emit(pos, snd, 0.9 + 0.2 * fposmod(_clock_s * 2.3, 1.0), (RAKE_VOL if rake else SHOVEL_VOL) - dist * SOUND_ATTEN, SOUND_R)


func _refresh_near() -> void:
	_near.clear()
	if not enabled():
		return
	var h := world.clock.hour() if world.clock else 12.0
	if h < 7.0 or h > 20.0:
		return
	for i in hh.size():
		var pos: Vector3 = hh[i]["pos"]
		if world.nearest_player_dist(pos) < SOUND_R:
			_near.append(i)


# ------------------------------------------------------------------ ladění (F2, mapa M)

## Vrstva mapy „obyvatele“: žlutá = někdo doma vzhůru, modrá = všichni spí, zelená = práce u domu,
## červená = nikdo doma, šedá = neobydlený dům.
func debug_layer(x: float, z: float) -> Color:
	var v = _cells.get(Vector2i(floori(x / 8.0), floori(z / 8.0)), null)
	if v == null:
		return Color(0, 0, 0, 0)
	var i: int = v
	if i == -2:
		return Color(0.45, 0.45, 0.45, 0.8)
	var house: Dictionary = hh[i]
	var home := 0
	var awake := 0
	var yard := 0
	for m in (house["members"] as Array):
		if bool(m["home"]):
			home += 1
			if String(m["act"]) != "spanek":
				awake += 1
		if String(m["kde"]) in ["dvur", "zahrada"]:
			yard += 1
	if yard > 0:
		return Color(0.2, 0.85, 0.25, 0.9)
	if awake > 0:
		return Color(1.0, 0.85, 0.2, 0.9)
	if home > 0:
		return Color(0.25, 0.35, 0.95, 0.9)
	return Color(0.85, 0.15, 0.12, 0.9)


## Výpis nejbližších domů (F2 → Příroda – ladění → Domácnosti): kdo bydlí, co dělá, potřeby, dřevo, komín.
func debug_text(pos: Vector3, n := 5) -> String:
	if not built:
		return "Domácnosti nejsou (chybí registr nemovitostí)."
	var acts: Dictionary = data().get("cinnosti", {})
	var order: Array = []
	for i in hh.size():
		var c: Vector2 = hh[i]["center"]
		order.append([c.distance_to(Vector2(pos.x, pos.z)), i])
	order.sort_custom(func(a, b): return a[0] < b[0])
	var h := world.clock.hour()
	var lines: Array = ["Domácností %d (zapnuto: %s), drbů v paměti %d." % [hh.size(), "ano" if enabled() else "ne", gossip.size()]]
	for k in mini(n, order.size()):
		var house: Dictionary = hh[int(order[k][1])]
		var lbl := world.estate.label(int(house["eid"])) if world.estate else "?"
		if int(house["flat"]) > 0:
			lbl = "byt %d v %s" % [int(house["flat"]), lbl]
		lines.append("\n%s – %s (%d m), topí: %s, oheň %.2f, kouř %.2f, dřevo %.1f prms, jídlo %.2f%s%s" % [
			lbl, house["fam"][0], int(order[k][0]), house["heat"], float(house["fire"]), chimney_heat(int(house["eid"]), h),
			float(house["wood"]), float(house["food"]), ", pes" if house["dog"] else "", ", zahrada" if house["garden"] else ""])
		for m in (house["members"] as Array):
			var a := String(m["act"])
			var an := "spí" if a == "spanek" else ("snídá" if a == "snidane" else String(acts.get(a, {}).get("nazev", a)))
			var nd: Dictionary = m["needs"]
			lines.append("  %s%s (%s, %s) – %s; vstává %.1f, spát %.1f; jídlo %.2f, spol. %.2f, odpoč. %.2f" % [
				m["name"], " [model]" if m.get("v") != null else "", m["role"], m["job"] if m["job"] != "" else "doma",
				an, float(m["wake"]), float(m["sleep"]), float(nd.get("jidlo", 0.0)), float(nd.get("spolecnost", 0.0)),
				float(nd.get("odpocinek", 0.0))])
	if not gossip.is_empty():
		var g: Dictionary = gossip[gossip.size() - 1]
		var cnt := 0
		for b in (g["known"] as PackedByteArray):
			cnt += int(b)
		lines.append("\nPoslední drb (zná %d domácností%s): %s" % [cnt, ", hospoda" if g["hub"] else "",
			_with_when(String(g["text"]), world.clock.jd() - int(g["jd"]))])
	return "\n".join(PackedStringArray(lines))


# ------------------------------------------------------------------ ukládání

func _key(i: int) -> String:
	return "%d:%d" % [int(hh[i]["eid"]), int(hh[i]["flat"])]


## Stav domů (dřevo, oheň, jídlo, povinnosti), vztahy (jen změny proti seedu), paměť drbů.
func to_dict() -> Dictionary:
	if not built:
		return {}
	var houses := {}
	for i in hh.size():
		var h: Dictionary = hh[i]
		houses[_key(i)] = [snappedf(float(h["wood"]), 0.01), snappedf(float(h["fire"]), 0.01), snappedf(float(h["food"]), 0.01),
			int(h["mow_jd"]), int(h["rake_jd"]), int(h["snow_jd"]), int(h["no_wood_jd"])]
	var rel := {}
	for k in _rel:
		var d := float(_rel[k]) - float(_rel_seed.get(k, 0.0))
		if absf(d) > 0.005:
			var a := int(k) / 65536
			var b := int(k) % 65536
			rel["%s|%s" % [_key(a), _key(b)]] = snappedf(d, 0.001)
	var keys := PackedStringArray()
	for i in hh.size():
		keys.append(_key(i))
	var gs: Array = []
	for g in gossip:
		gs.append({"id": g["id"], "jd": g["jd"], "h": g["h"], "text": g["text"], "kind": g["kind"],
			"subj": _key(int(g["subj"])) if int(g["subj"]) >= 0 else str(g["subj"]), "hub": g["hub"],
			"known": Marshalls.raw_to_base64(g["known"])})
	return {"houses": houses, "rel": rel, "keys": keys, "gossip": gs, "gid": _gid}


## Starý save bez klíče = výchozí stav (seed).
func restore(d: Dictionary) -> void:
	if not built or d.is_empty():
		return
	var idx := {}
	for i in hh.size():
		idx[_key(i)] = i
	var houses: Dictionary = d.get("houses", {})
	for k in houses:
		if not idx.has(k):
			continue
		var a: Array = houses[k]
		if a.size() < 7:
			continue
		var h: Dictionary = hh[idx[k]]
		h["wood"] = float(a[0])
		h["fire"] = float(a[1])
		h["food"] = float(a[2])
		h["mow_jd"] = int(a[3])
		h["rake_jd"] = int(a[4])
		h["snow_jd"] = int(a[5])
		h["no_wood_jd"] = int(a[6])
	_rel = _rel_seed.duplicate()
	var rel: Dictionary = d.get("rel", {})
	for k in rel:
		var p := String(k).split("|")
		if p.size() == 2 and idx.has(p[0]) and idx.has(p[1]):
			_rel_add(int(idx[p[0]]), int(idx[p[1]]), float(rel[k]))
	var old_keys: Array = Array(d.get("keys", PackedStringArray()))
	gossip.clear()
	for gd in d.get("gossip", []):
		if not (gd is Dictionary):
			continue
		var raw := Marshalls.base64_to_raw(String(gd.get("known", "")))
		var known := PackedByteArray()
		known.resize(hh.size())
		for j in mini(raw.size(), old_keys.size()):
			if raw[j] == 1 and idx.has(String(old_keys[j])):
				known[int(idx[String(old_keys[j])])] = 1
		var subj_s := String(gd.get("subj", "-1"))
		var subj := int(idx.get(subj_s, -1)) if subj_s.contains(":") else int(subj_s)
		gossip.append({"id": int(gd.get("id", 0)), "jd": int(gd.get("jd", 0)), "h": float(gd.get("h", 12.0)),
			"text": String(gd.get("text", "")), "kind": String(gd.get("kind", "")), "subj": subj,
			"known": known, "hub": bool(gd.get("hub", false))})
	_gid = int(d.get("gid", gossip.size()))
	_check_homes(true)
	_on_eco_hour(0.0)
