## Lov zvěře (M2.9), jeden uzel ve `World` (`World.hunting`). Navazuje na zbraně (M2.8) a zvěř (příroda 01–04):
##
##  1. **Zásah:** `Weapons._hit_animal` zavolá `animal_shot` → `Animal.shot(zóna, energie, …)`. Hlava a komora s dost energie
##     zvíře usmrtí (srdce: uběhne 20–60 m), se slabým šípem se to jen někdy povede; břicho = uteče 200–600 m, zalehne a po
##     1–3 herních hodinách zhyne (při přiblížení na 15 m se může zvednout a utéct dál); noha = kulhá. Postřelené zvíře
##     zanechává **krvavou stopu** (`add_blood`, tmavé kapky, mizí za 2 herní hodiny, v dešti rychleji).
##  2. **Úlovek:** mrtvé zvíře (`Animal.die_shot` → `on_animal_died`) se stane `Carcass` (druh, hmotnost, čas úmrtí, legálnost,
##     vyvrženo). E u těla = nabídka: **vyvrhnout** (nůž, pár sekund, ztmavení, −20 % hmotnosti, XP myslivosti), **zpracovat**
##     (jen doma na dvoře: zvěřina podle hmotnosti + trofej), **zvednout na rameno** (G; jen zajíc, sele, srnec – divočák až
##     divočáka naloží G na ruční vozík / do auta – `Cargo`, M2.10), odhodit. Nevyvržené maso se po 3 herních h (v létě 2) zkazí. Těla mimo domov po 2 dnech zmizí.
##  3. **Legalita:** `is_legal_hunt` (puška + zbrojní oprávnění + lovecký lístek + povolenka, doba lovu z `data/lov.json`, ne v noci
##     mimo divočáka, ne v obci, ne z auta; luk a kuše NIKDY). Nelegální úlovek = pytláctví: karma −3 za kus hned (svědomí),
##     přestupek (`pytlactvi` / `pytlactvi_luk_kuse`) jen když střelbu uvidí svědek (`Forestry.witness_near`) nebo hráče s nelegálním
##     úlovkem uvidí vesničan (hajný a policie M4.6 – háčky: události `poaching`, `wounded_unfound`). Postřelení bez dohledání = karma −5.
##  4. **Prodej:** legální zvěřina s dokladem o původu (`doklad_puvod` vzniká u legálního úlovku) v hospodě / Potravinách
##     (`World.sell_items` → `sell_venison`); nelegální u překupníka (večer za hospodou, +30 %, 10 % „prásknutí“) nebo sousedům bokem.
##
## Ukládání: `to_dict` / `restore` (klíč `hunting` v `SaveGame`): těla (záznamy i model) a počty nelegálního masa.
## Data: `data/lov.json` (bez souboru vestavěná záloha `FALLBACK`).
class_name Hunting
extends Node3D

const PATH := "res://data/lov.json"
const FALLBACK := {
	"dokument": "doklad_puvod", "vyvrhnuti_hmotnost": 0.8, "zkaza_h": 3.0, "zkaza_leto_h": 2.0, "zkaza_leto_mesice": [6, 7, 8],
	"vyvrzene_zkaza_h": 24.0, "zmizi_dny": 2.0, "domov_dosah_m": 30.0,
	"prekupnik": {"jmeno": "Kamarád Franta", "od_h": 19.0, "do_h": 24.0, "bonus": 1.3, "prask_p": 0.1, "soused_max_ks": 3, "soused_koef": 0.8},
	"druhy": {
		"srnec": {"nazev": "Srnec obecný", "doba_samec": [5, 16, 9, 30], "doba_samice": [9, 1, 12, 31], "noc": false,
			"item": "zverina_srnci", "vynos": 0.5, "trofej": "trofej_parozky", "cargo": "srnec", "vyvrhnout_s": [25, 45], "xp": [20, 40], "rameno": true},
		"divocak": {"nazev": "Divoké prase", "doba_samec": null, "doba_samice": null, "noc": true, "item": "zverina_divocak",
			"vynos": 0.5, "trofej": "", "cargo": "divocak", "vyvrhnout_s": [45, 90], "xp": [40, 60], "rameno": false},
		"sele": {"nazev": "Sele", "doba_samec": null, "doba_samice": null, "noc": true, "item": "zverina_divocak",
			"vynos": 0.5, "trofej": "", "cargo": "zajic", "vyvrhnout_s": [25, 35], "xp": [20, 30], "rameno": true},
		"zajic": {"nazev": "Zajíc polní", "doba_samec": [11, 1, 12, 31], "doba_samice": [11, 1, 12, 31], "noc": false,
			"item": "zverina_zajic", "vynos": 0.5, "trofej": "", "cargo": "zajic", "vyvrhnout_s": [25, 30], "xp": [20, 25], "rameno": true},
	},
}
## Všechny druhy zvěřiny v ItemsDB (pro výkup s dokladem).
const VENISON_ITEMS := ["zverina_srnci", "zverina_divocak", "zverina_zajic"]

const INTERACT_R := 2.6              # dosah nabídky u těla (m)
const LIFT_R := 3.0                  # dosah zvednutí na rameno (G)
const FOUND_R := 15.0                # tak blízko musí hráč k postřelenému zvířeti, aby se „dohledalo“
const SEE_CARCASS_R := 25.0          # do kolika m vesničan uvidí hráče s nelegálním úlovkem
const NEAR_CARCASS_R := 8.0          # hráč je „u svého úlovku“ do tolika m
const SHOT_WITNESS_R := {"luk": 60.0, "kuse": 60.0, "puska": 250.0}   # kdo střelbu uvidí / uslyší (puška je slyšet dál)
const SHOT_WITNESS_DEFAULT_R := 100.0
const TICK_S := 3.0
const KARMA_POACH := -3.0            # za každý nelegálně ulovený kus
const KARMA_UNFOUND := -5.0          # postřelené zvíře, které hráč nedohledal („trpí“)
const KARMA_NEIGHBOR := -1.0
const RESPECT_NEIGHBOR := 1.0        # štamgasti +1 za „sousedy, kteří se neptají“
const GUT_TIME_K := 0.35             # vyvrhnutí trvá reálně tolik z tabulky `vyvrhnout_s` (DOPLNIT: prompt chce 30–90 s)
const GUT_BLACKOUT_S := 2.5
const DOC_COVER_PCS := 15            # jeden doklad o původu kryje tolik kusů zvěřiny při prodeji
const CARRY_MAX_KG := 35.0           # víc na rameno nevezmeš (těžší: vozík / auto, `Cargo`, M2.10)
const CARRY_SHOULDER := Vector3(0.0, 1.3, 0.0)
const CARRY_STAMINA_K := 0.03        # úbytek výdrže za s při chůzi s nákladem × (kg / 20)
const BLOOD_MAX := 300
const BLOOD_LIFE_MIN := 120.0        # krvavá kapka zmizí za 2 herní hodiny
const BLOOD_RAIN_K := 3.0            # v dešti 3× rychleji
const BLOOD_COLOR := Color(0.32, 0.03, 0.03)
const ROADKILL_R := 60.0             # sražená zvěř do tolika m od hráče se dá „přivlastnit“ (pytláctví)
const PICK_ROADKILL_R := 3.0

static var _data := {}

var world: World
var carcasses: Array = []            # Array[Carcass]
var wounded: Array = []              # postřelená živá zvířata {animal, id}
var blood: Array = []                # {node, t} krvavé kapky
var dealer: Npc                      # překupník (večer za hospodou)
var dealer_pos := Vector3.INF
var black := {}                      # id hráče → {item: počet kusů bez dokladu (nelegální)}
var _carry := {}                     # id hráče → {c: Carcass, walk0, sprint0}
var _roadkill: Array = []            # mrtvá zvířata po srážce v okolí hráče (z posledního ticku)
var _blood_mesh: CylinderMesh
var _blood_mat: StandardMaterial3D
var _tick_t := 0.0
var _last_min := -1.0
var _dealer_tried := false
var _msg_cd := {}                    # id hráče → čas (s), do kdy se nehlásí další výstraha před pytláctvím
var _rng := RandomNumberGenerator.new()
var _seed_n := 0


# ------------------------------------------------------------------ data

static func data() -> Dictionary:
	if _data.is_empty():
		var d = null
		if FileAccess.file_exists(PATH):
			var txt := FileAccess.get_file_as_string(PATH)
			d = JSON.parse_string(txt) if txt != "" else null
		if d is Dictionary and d.get("druhy") is Dictionary and not (d["druhy"] as Dictionary).is_empty():
			_data = d
		else:
			push_warning("Chybí nebo je vadné data/lov.json – použita vestavěná tabulka lovu.")
			_data = FALLBACK
	return _data


## Popis druhu z `data/lov.json`; neznámý druh se chová jako srnec (ale bez trofeje).
static func species_info(sp: String) -> Dictionary:
	var t: Dictionary = data().get("druhy", {})
	if t.has(sp):
		return t[sp]
	var d: Dictionary = (FALLBACK["druhy"]["srnec"] as Dictionary).duplicate()
	d["trofej"] = ""
	d["nazev"] = sp
	return d


static func cfg(key: String, def = null):
	return data().get(key, FALLBACK.get(key, def))


## Je datum v intervalu [měsíc od, den od, měsíc do, den do]? `null` / prázdný = celoročně. Interval může přesahovat Nový rok.
static func in_season(interval, month: int, day: int) -> bool:
	if not (interval is Array) or (interval as Array).size() < 4:
		return true
	var a := int(interval[0]) * 100 + int(interval[1])
	var b := int(interval[2]) * 100 + int(interval[3])
	var n := month * 100 + day
	if a <= b:
		return n >= a and n <= b
	return n >= a or n <= b


static func is_venison(item_id: String) -> bool:
	return item_id in VENISON_ITEMS


func setup(w: World) -> void:
	world = w
	name = "Lov"
	_rng.randomize()
	_blood_mesh = CylinderMesh.new()
	_blood_mesh.top_radius = 0.09
	_blood_mesh.bottom_radius = 0.09
	_blood_mesh.height = 0.01
	_blood_mesh.radial_segments = 8
	_blood_mesh.rings = 1
	_blood_mat = StandardMaterial3D.new()
	_blood_mat.albedo_color = BLOOD_COLOR
	_blood_mat.roughness = 0.35
	_blood_mat.cull_mode = BaseMaterial3D.CULL_DISABLED


func _now() -> float:
	return world.clock.minutes


func _msg(id: int, text: String, dur := 3.0) -> void:
	world.notify(id, "show_message", [text, dur])


func _player(id: int) -> Player:
	return world.players.get(id)


func _gut_k() -> float:
	return float(cfg("vyvrhnuti_hmotnost", 0.8))


# ------------------------------------------------------------------ legalita

## Je lov tohoto druhu tady a teď legální? {ok, reasons[]}. `pos` = poloha lovce. Luk a kuše nikdy; puška jen se zbrojním oprávněním,
## loveckým lístkem a povolenkou (`World.has_permit`, doklady M4.6 – zatím cheat F2 → Hráč → Zbrojní oprávnění), v době lovu
## druhu, ne v noci (kromě divočáka), ne v obci a ne z auta.
func is_legal_hunt(id: int, weapon: String, species: String, pos: Vector3, male := true) -> Dictionary:
	var reasons: Array = []
	var p := _player(id)
	var spec: Dictionary = Weapons.WEAPONS.get(weapon, {})
	if not bool(spec.get("firearm", false)):
		reasons.append("Lov lukem a kuší je v ČR zakázán.")
	elif not world.has_permit(id, "zbrojni", pos):
		reasons.append("Chybí zbrojní oprávnění.")
	if not world.has_permit(id, "lovecky_listek", pos):
		reasons.append("Chybí lovecký lístek.")
	if not world.has_permit(id, "povolenka_lov", pos):
		reasons.append("Chybí povolenka k lovu.")
	var sp := species_info(species)
	var dt: Dictionary = world.clock.date()
	var iv = sp.get("doba_samec" if male else "doba_samice")
	if not in_season(iv, int(dt["month"]), int(dt["day"])):
		reasons.append("Mimo dobu lovu.")
	if world.clock.is_night() and not bool(sp.get("noc", false)):
		reasons.append("V noci se nelove.")
	if world.fauna and world.fauna.settle_at(pos.x, pos.z) > 0.5:
		reasons.append("V obci se nelove.")
	if p != null and p.car != null:
		reasons.append("Z auta se nelove.")
	return {"ok": reasons.is_empty(), "reasons": reasons}


# ------------------------------------------------------------------ zásah (volá Weapons)

## Zásah zvířete střelou (`Weapons._hit_animal`, data události `shot_hit`): legalita, zranění / smrt, pytláctví se svědkem.
func animal_shot(id: int, d: Dictionary) -> void:
	var an = d.get("target")
	var p := _player(id)
	if an == null or not is_instance_valid(an) or not (an is Animal) or p == null:
		return
	var a := an as Animal
	if a.dead:
		return
	var weapon := String(d.get("weapon", ""))
	var legal := is_legal_hunt(id, weapon, a.species, p.global_position, a.male)
	var info := {"id": id, "weapon": weapon, "legal": bool(legal["ok"]), "reasons": legal["reasons"]}
	var res := a.shot(String(d.get("part", "telo")), float(d.get("energy", 0.0)), p.global_position, info)
	if res != "dead":
		_track_wound(a, id)
	if not bool(legal["ok"]):
		_poach_shot(id, a, weapon, legal["reasons"], d.get("pos", a.global_position))
	world.emit_game_event(id, "hunt_shot", {"species": a.species, "zone": String(d.get("part", "")), "result": res,
		"legal": bool(legal["ok"]), "weapon": weapon})


func _track_wound(a: Animal, id: int) -> void:
	for r in wounded:
		if r["animal"] == a:
			return
	wounded.append({"animal": a, "id": id})


## Nelegální výstřel na zvěř: výstraha hráči a přestupek, když střelbu vidí / slyší svědek.
func _poach_shot(id: int, a: Animal, weapon: String, reasons: Array, at: Vector3) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	if t >= float(_msg_cd.get(id, 0.0)):
		_msg_cd[id] = t + 20.0
		_msg(id, "Střílíš na zvěř bez práva – je to pytláctví. (%s)" % String(reasons[0]), 4.0)
	var r := float(SHOT_WITNESS_R.get(weapon, SHOT_WITNESS_DEFAULT_R))
	if world.forestry != null and world.forestry.witness_near(at, r):
		if not bool(a.shot_by.get("reported", false)):
			a.shot_by["reported"] = true
			_commit_poaching(id, weapon)
			_msg(id, "Někdo tě viděl střílet na zvěř!", 3.5)
	world.emit_game_event(id, "poaching", {"species": a.species, "weapon": weapon, "pos": at, "reasons": reasons})   # háček M4.6 (hajný)


func _commit_poaching(id: int, weapon: String) -> void:
	var spec: Dictionary = Weapons.WEAPONS.get(weapon, {})
	var off := "pytlactvi" if bool(spec.get("firearm", false)) else "pytlactvi_luk_kuse"
	world.commit_offense(id, off, {"severity": 0.5})


# ------------------------------------------------------------------ smrt zvířete, úlovek

## Zvíře padlo (`Animal.die_shot`): vznikne `Carcass`; legální úlovek dá doklad o původu, nelegální karmu −3.
func on_animal_died(a: Animal) -> void:
	for i in range(wounded.size() - 1, -1, -1):
		if wounded[i]["animal"] == a:
			wounded.remove_at(i)
	var c := Carcass.new()
	c.species = a.species
	c.male = a.male
	c.young = a.young
	c.live_kg = float(a.spec["mass"]) * _rng.randf_range(0.9, 1.1)
	c.died_min = _now()
	c.pos = a.global_position
	c.node = a
	c.owner_id = int(a.shot_by.get("id", 0))
	c.weapon = String(a.shot_by.get("weapon", ""))
	c.legal = bool(a.shot_by.get("legal", false))
	c.reported = bool(a.shot_by.get("reported", false))
	c.unfound_penalty = bool(a.shot_by.get("natural", false))
	c.cargo_kind = String(species_info(a.species).get("cargo", ""))
	carcasses.append(c)
	var id := c.owner_id
	var p := _player(id)
	if p == null:
		return
	if c.legal:
		p.add_item(String(cfg("dokument", "doklad_puvod")))
		_msg(id, "Zvěř leží (E = co s ní). Legální úlovek – dostal jsi doklad o původu.", 4.0)
	else:
		var rep: Reputation = world.reputations.get(id)
		if rep:
			rep.change_karma(KARMA_POACH, "pytláctví: %s" % String(species_info(a.species).get("nazev", a.species)))
		_msg(id, "Zvěř leží (E = co s ní). Je to pytláctví – drž se stranou od lidí.", 4.0)
	world.give_xp(id, "myslivost", 10.0, "úlovek")
	world.emit_game_event(id, "hunt_kill", {"species": a.species, "legal": c.legal, "weapon": c.weapon, "pos": c.pos,
		"kg": c.live_kg})


## Postřelená noha se zahojila a hráč zvíře nedohledal (`Animal._wound_think`): karma −5, hajný se to může dozvědět.
func on_wound_healed(a: Animal) -> void:
	for i in range(wounded.size() - 1, -1, -1):
		if wounded[i]["animal"] == a:
			_unfound(int(wounded[i]["id"]), a.species)
			wounded.remove_at(i)


func _unfound(id: int, species: String) -> void:
	var rep: Reputation = world.reputations.get(id)
	if rep:
		rep.change_karma(KARMA_UNFOUND, "postřelené zvíře trpí")
	world.emit_game_event(id, "wounded_unfound", {"species": species})   # háček M4.6 (hajný to může najít)


## Sražená autem a ležící (Animal.keep_corpse): vezmi si ji = přivlastnění = pytláctví, myslivec pro ni pak nepřijede.
func _adopt(id: int, a: Animal) -> void:
	if not is_instance_valid(a) or not a.dead:
		return
	for c in carcasses:
		if c.node == a:
			return
	var nc := Carcass.new()
	nc.species = a.species
	nc.male = a.male
	nc.young = a.young
	nc.live_kg = float(a.spec["mass"])
	nc.died_min = _now() - 10.0
	nc.pos = a.global_position
	nc.node = a
	nc.owner_id = id
	nc.legal = false
	nc.cargo_kind = String(species_info(a.species).get("cargo", ""))
	carcasses.append(nc)
	_roadkill.erase(a)
	var rep: Reputation = world.reputations.get(id)
	if rep:
		rep.change_karma(KARMA_POACH, "přivlastnění sražené zvěře")
	_msg(id, "Vzal sis zvěř po srážce – to je přivlastnění (pytláctví). Myslivec pro ni nepřijede.", 4.0)
	world.emit_game_event(id, "poaching", {"species": a.species, "weapon": "", "pos": nc.pos, "reasons": ["Přivlastnění sražené zvěře."]})


# ------------------------------------------------------------------ krvavá stopa

## Kapka krve na zemi (volá `Animal._blood_trail` postřeleného zvířete).
func add_blood(pos: Vector3) -> void:
	if world == null or world.terrain == null:
		return
	var mi := MeshInstance3D.new()
	mi.mesh = _blood_mesh
	mi.material_override = _blood_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var sc := _rng.randf_range(0.5, 1.3)
	mi.scale = Vector3(sc, 1.0, sc * _rng.randf_range(0.7, 1.2))
	add_child(mi)
	mi.global_position = Vector3(pos.x + _rng.randf_range(-0.25, 0.25), world.terrain.height_at(pos.x, pos.z) + 0.04,
		pos.z + _rng.randf_range(-0.25, 0.25))
	blood.append({"node": mi, "t": 0.0})
	if blood.size() > BLOOD_MAX:
		var old: Dictionary = blood.pop_front()
		if is_instance_valid(old["node"]):
			(old["node"] as Node).queue_free()


func _blood_tick(dt_game_min: float) -> void:
	var k := 1.0
	if world.weather != null and world.weather.rain > 0.3:
		k = BLOOD_RAIN_K
	for i in range(blood.size() - 1, -1, -1):
		var b: Dictionary = blood[i]
		b["t"] = float(b["t"]) + dt_game_min * k
		var f: float = float(b["t"]) / BLOOD_LIFE_MIN
		if not is_instance_valid(b["node"]) or f >= 1.0:
			if is_instance_valid(b["node"]):
				(b["node"] as Node).queue_free()
			blood.remove_at(i)
		elif f > 0.6:
			(b["node"] as GeometryInstance3D).transparency = clampf((f - 0.6) / 0.4, 0.0, 0.95)


# ------------------------------------------------------------------ smyčka

func _process(delta: float) -> void:
	if world == null or not world.ready_done:
		return
	_carry_follow(delta)
	_tick_t -= delta
	if _tick_t > 0.0:
		return
	_tick_t = TICK_S
	var now := _now()
	var dmin := 0.0 if _last_min < 0.0 else maxf(now - _last_min, 0.0)
	_last_min = now
	_blood_tick(dmin)
	_carcass_tick(now)
	_wound_tick()
	_roadkill_scan()
	_dealer_tick()


func _month_spoil_h() -> float:
	var m := int(world.clock.date()["month"])
	if m in (cfg("zkaza_leto_mesice", [6, 7, 8]) as Array):
		return float(cfg("zkaza_leto_h", 2.0))
	return float(cfg("zkaza_h", 3.0))


func _carcass_tick(now: float) -> void:
	var spoil_h := _month_spoil_h()
	var vyvrz_h := float(cfg("vyvrzene_zkaza_h", 24.0))
	var gone_h := float(cfg("zmizi_dny", 2.0)) * 24.0
	var home: Vector3 = world.places["domov"].door if world.places.has("domov") else Vector3.ZERO
	var home_r := float(cfg("domov_dosah_m", 30.0))
	for i in range(carcasses.size() - 1, -1, -1):
		var c: Carcass = carcasses[i]
		if c.node == null or not is_instance_valid(c.node):
			if c.carried_by != 0:
				_release_player(c.carried_by)
			carcasses.remove_at(i)
			continue
		if c.carried_by == 0:
			c.pos = c.node.global_position
		# zkáza masa
		if not c.spoiled:
			if not c.gutted and c.age_h(now) >= spoil_h:
				c.spoiled = true
			elif c.gutted and (now - c.gutted_min) / 60.0 >= vyvrz_h:
				c.spoiled = true
		# hráč došel k postřelenému zvířeti
		if not c.found:
			for p in world.players.values():
				if world.player_world_pos(p).distance_to(c.pos) < FOUND_R:
					c.found = true
		# nelegální úlovek viděný svědkem
		if not c.legal and not c.reported and c.owner_id != 0:
			_witness_carcass(c)
		# zmizí po 2 dnech mimo domov
		if c.carried_by == 0 and c.stored == "" and c.age_h(now) >= gone_h and world.nearest_player_dist(c.pos) > 40.0 \
				and Vector2(c.pos.x - home.x, c.pos.z - home.z).length() > home_r:
			if c.unfound_penalty and not c.found:
				_unfound(c.owner_id, c.species)
			c.node.queue_free()
			carcasses.remove_at(i)


## Vesničan uvidí hráče u nelegálního úlovku (na rameni nebo do 8 m od těla) → přestupek (jednou za kus).
func _witness_carcass(c: Carcass) -> void:
	var p := _player(c.owner_id)
	if p == null or world.forestry == null:
		return
	var near := c.carried_by == c.owner_id or p.global_position.distance_to(c.pos) < NEAR_CARCASS_R
	if not near:
		return
	if world.forestry.witness_near(p.global_position, SEE_CARCASS_R):
		c.reported = true
		_commit_poaching(c.owner_id, c.weapon)
		_msg(c.owner_id, "Někdo tě viděl s nelegálním úlovkem!", 3.5)


func _wound_tick() -> void:
	for i in range(wounded.size() - 1, -1, -1):
		if not is_instance_valid(wounded[i]["animal"]):
			wounded.remove_at(i)


func _roadkill_scan() -> void:
	_roadkill.clear()
	if world.fauna == null:
		return
	for a in world.fauna.animals:
		if not is_instance_valid(a) or not a.dead or not a.keep_corpse:
			continue
		if a.shot_by.size() > 0:
			continue
		if world.nearest_player_dist(a.global_position) > ROADKILL_R:
			continue
		var tracked := false
		for c in carcasses:
			if c.node == a:
				tracked = true
				break
		if not tracked:
			_roadkill.append(a)


# ------------------------------------------------------------------ E u těla: nabídka

func interactables(id: int) -> Array:
	var out := []
	var p := _player(id)
	if p == null or p.car != null or p.horse != null:
		return out
	var now := _now()
	for c in carcasses:
		if c.carried_by != 0 or c.stored != "" or c.node == null or not is_instance_valid(c.node):
			continue
		if c.pos.distance_to(p.global_position) > 8.0:
			continue
		out.append({"pos": c.pos + Vector3(0, 0.3, 0), "r": INTERACT_R, "kind": "custom", "text": _carcass_label(c, now),
			"action": _carcass_menu.bind(c)})
	for a in _roadkill:
		if is_instance_valid(a) and (a as Node3D).global_position.distance_to(p.global_position) < 8.0:
			out.append({"pos": (a as Node3D).global_position + Vector3(0, 0.3, 0), "r": PICK_ROADKILL_R, "kind": "custom",
				"text": "Sražená zvěř – vzít si ji (přivlastnění = pytláctví)", "action": _adopt.bind(a)})
	if dealer != null and is_instance_valid(dealer) and dealer.visible:
		out.append({"pos": dealer.global_position, "r": 2.8, "kind": "custom", "text": "%s (překupník)" % dealer.display_name,
			"action": _on_dealer})
	return out


func _carcass_label(c: Carcass, _now_min: float) -> String:
	var sp := species_info(c.species)
	var st := "zkažené" if c.spoiled else ("vyvržené" if c.gutted else "čerstvé")
	return "%s – %s, %d kg (%s)%s" % [String(sp.get("nazev", c.species)), "samec" if c.male else "samice",
		roundi(c.weight_kg(_gut_k())), st, "" if c.legal else "  · nelegální"]


func _is_home(p: Player) -> bool:
	if not world.places.has("domov"):
		return false
	var door: Vector3 = world.places["domov"].door
	return Vector2(p.global_position.x - door.x, p.global_position.z - door.z).length() < float(cfg("domov_dosah_m", 30.0))


func _carcass_menu(id: int, c: Carcass) -> void:
	var p := _player(id)
	var cl = world.clients.get(id)
	if p == null or cl == null or c.node == null or not is_instance_valid(c.node):
		return
	var sp := species_info(c.species)
	var opts := []
	var text := _carcass_label(c, _now())
	if c.spoiled:
		text += "\nMaso se znehodnotilo – nevyvržená zvěř se v teple rychle kazí."
		opts.append(["Odhodit (odnést z cesty)", _discard.bind(id, c)])
	else:
		if not c.gutted:
			opts.append(["Vyvrhnout (nůž%s)" % ("" if p.item_count("nuz") > 0 else " – chybí!"), _gut.bind(id, c)])
		else:
			opts.append(["Zpracovat na maso%s" % ("" if _is_home(p) else " (jen doma na dvoře)"), _process_home.bind(id, c)])
		if bool(sp.get("rameno", false)):
			opts.append(["Zvednout na rameno (G)", lift.bind(id, c)])
		else:
			opts.append(["Zvednout (moc těžké na rameno – G u vozíku / auta)", _too_heavy.bind(id)])
		opts.append(["Nechat ležet", func(): pass])
	cl.hud.open_menu("Ulovená zvěř", text, opts)


func _too_heavy(id: int) -> void:
	_msg(id, "Sám ho neuneseš. Vyvrhni ho a naložíš ho (G) na ruční vozík nebo do auta (kombi, dodávka, pickup).", 3.5)


func _discard(id: int, c: Carcass) -> void:
	if c.carried_by != 0:
		drop(c.carried_by)
	if c.node != null and is_instance_valid(c.node):
		c.node.queue_free()
	carcasses.erase(c)
	_msg(id, "Odhozeno.", 1.5)


# ------------------------------------------------------------------ vyvrhnutí a zpracování

## Vyvrhnutí (nůž): pár sekund s ukazatelem průběhu, ke konci se obraz ztmaví (bez naturalismu). −20 % hmotnosti, XP myslivosti.
func _gut(id: int, c: Carcass) -> void:
	var p := _player(id)
	if p == null or p.controls_locked or c.gutted or c.node == null or not is_instance_valid(c.node):
		return
	if p.item_count("nuz") <= 0:
		_msg(id, "Nemáš nůž (koupíš v Potravinách).", 3.0)
		return
	var sp := species_info(c.species)
	var sk: Skills = world.skills.get(id)
	var bonus := sk.bonus("myslivost") if sk else 0.0
	var dur_a: Array = sp.get("vyvrhnout_s", [25, 45])
	var dur := lerpf(float(dur_a[0]), float(dur_a[1]), clampf(c.live_kg / 90.0, 0.0, 1.0)) * GUT_TIME_K * (1.0 - 0.4 * bonus)
	p.controls_locked = true
	var t := 0.0
	var dark := false
	while t < dur:
		world.notify(id, "action_progress", ["Vyvrhuješ…", t / dur])
		if not dark and t > dur - GUT_BLACKOUT_S:
			dark = true
			world.blackout(id, GUT_BLACKOUT_S)
		await get_tree().process_frame
		if not is_instance_valid(p) or c.node == null or not is_instance_valid(c.node):
			world.notify(id, "action_progress", ["", -1.0])
			if is_instance_valid(p):
				p.controls_locked = false
			return
		t += get_process_delta_time()
	world.notify(id, "action_progress", ["", -1.0])
	p.controls_locked = false
	c.gutted = true
	c.gutted_min = _now()
	p.wear_tool("nuz", 1)
	var xp: Array = sp.get("xp", [20, 40])
	world.give_xp(id, "myslivost", _rng.randf_range(float(xp[0]), float(xp[1])), "vyvrhnutí")
	world.play_sfx(id, "pickup")
	_msg(id, "Vyvrženo: %d kg. Zpracuj maso doma na dvoře, ať se nezkazí." % roundi(c.weight_kg(_gut_k())), 4.0)
	world.emit_game_event(id, "hunt_gutted", {"species": c.species, "legal": c.legal})


## Zpracování doma (dvůr / kůlna): zvěřina podle hmotnosti (+ trofej srnce). Nelegální maso se eviduje (`black`) – bez dokladu.
func _process_home(id: int, c: Carcass) -> void:
	var p := _player(id)
	if p == null or c.node == null or not is_instance_valid(c.node):
		return
	if not _is_home(p):
		_msg(id, "Zpracovat zvěřinu jde jen doma na dvoře nebo v kůlně.", 3.0)
		return
	if not c.gutted:
		_msg(id, "Nejdřív ji vyvrhni.", 2.5)
		return
	if c.spoiled:
		_msg(id, "Maso se znehodnotilo.", 2.5)
		return
	if c.carried_by != 0:
		drop(c.carried_by)
	var sp := species_info(c.species)
	var item := String(sp.get("item", "zverina_srnci"))
	var n := maxi(1, roundi(c.weight_kg(_gut_k()) * float(sp.get("vynos", 0.5))))
	p.add_item(item, n)
	if not c.legal:
		var b: Dictionary = black.get(id, {})
		b[item] = int(b.get(item, 0)) + n
		black[id] = b
	var troph := String(sp.get("trofej", ""))
	var extra := ""
	if troph != "" and c.male:
		p.add_item(troph)
		extra = " a trofej (%s)" % ItemsDB.name_of(troph)
	c.node.queue_free()
	carcasses.erase(c)
	world.give_xp(id, "myslivost", _rng.randf_range(10.0, 25.0), "zpracování zvěřiny")
	world.play_sfx(id, "pickup")
	_msg(id, "Zpracováno: %d × %s%s." % [n, ItemsDB.name_of(item), extra], 4.0)
	world.emit_game_event(id, "venison_processed", {"item": item, "n": n, "legal": c.legal})


# ------------------------------------------------------------------ nesení na rameni (G přes `Cargo.on_g`; vozík a auto řeší `Cargo`)

## G (akce `whistle` ve `World.player_action`): nese-li hráč zvěř, položí ji; jinak zvedne nejbližší tělo. Vrací true, když akci převzal.
func on_g(id: int) -> bool:
	if _carry.has(id):
		drop(id)
		return true
	var p := _player(id)
	if p == null or p.car != null or p.horse != null:
		return false
	var best: Carcass = null
	var bd := LIFT_R
	for c in carcasses:
		if c.carried_by != 0 or c.stored != "" or c.node == null or not is_instance_valid(c.node):
			continue
		var d: float = c.pos.distance_to(p.global_position)
		if d < bd:
			bd = d
			best = c
	if best == null:
		return false
	lift(id, best)
	return true


## Hráč nese úlovek `c`: pomalejší chůze (× 1 − kg/60, min. 0,35), žádný sprint, při nulové výdrži ho upustí.
## Nakládku na vozík / do auta řeší `Cargo` (přes `release_carried`, `Carcass.cargo_kind`, `weight_kg()`).
func lift(id: int, c: Carcass) -> void:
	var p := _player(id)
	if p == null or c.node == null or not is_instance_valid(c.node) or c.carried_by != 0:
		return
	if _carry.has(id) or (world.cargo != null and world.cargo.hands_busy(id)):
		_msg(id, "Už něco neseš nebo držíš vozík (G = položit).", 2.0)
		return
	var sp := species_info(c.species)
	var kg := c.weight_kg(_gut_k())
	if not bool(sp.get("rameno", false)) or kg > CARRY_MAX_KG:
		_too_heavy(id)
		return
	c.carried_by = id
	_carry[id] = {"c": c, "walk0": p.walk_speed, "sprint0": p.sprint_speed, "jump0": p.jump_velocity}
	var k := clampf(1.0 - kg / 60.0, 0.35, 0.9)
	p.walk_speed *= k
	p.sprint_speed = p.walk_speed          # se zvěří na rameni se neběhá
	p.jump_velocity = Cargo.JUMP_CARRIED   # jen malý hop (M2.10)
	c.node.set_physics_process(false)
	_msg(id, "Neseš %s (%d kg). G = položit." % [String(sp.get("nazev", c.species)), roundi(kg)], 3.0)
	world.emit_game_event(id, "cargo_lift", {"kind": c.cargo_kind, "kg": kg, "tag": "zverina"})


func carried_by(id: int) -> Carcass:
	return (_carry[id]["c"] as Carcass) if _carry.has(id) else null


## M2.10: sundá nesený úlovek z ramene BEZ položení na zem (vrátí rychlost chůze, tělo zůstane s vypnutou fyzikou) a vrátí ho;
## volající (`Cargo`) ho naloží na vozík / do auta (nastaví `stored`) nebo ho zase položí.
func release_carried(id: int) -> Carcass:
	if not _carry.has(id):
		return null
	var c: Carcass = _carry[id]["c"]
	var e: Dictionary = _carry[id]
	var p := _player(id)
	if p != null:
		p.walk_speed = float(e["walk0"])
		p.sprint_speed = float(e["sprint0"])
		p.jump_velocity = float(e.get("jump0", p.jump_velocity))
	c.carried_by = 0
	_carry.erase(id)
	return c


## Kolik kg hráč nese na rameni (M2.10: viditelný náklad, `cargo_seen`).
func carried_kg(id: int) -> float:
	var c := carried_by(id)
	return c.weight_kg(_gut_k()) if c else 0.0


func drop(id: int) -> void:
	if not _carry.has(id):
		return
	var c: Carcass = _carry[id]["c"]
	var p := _player(id)
	_release_player(id)
	if p != null and c.node != null and is_instance_valid(c.node):
		var fwd := Basis(Vector3.UP, p.yaw) * Vector3.FORWARD
		var pos := p.global_position + fwd * 1.0
		pos.y = world.terrain.height_at(pos.x, pos.z) + 0.05
		c.node.global_position = pos
		c.node.yaw = p.yaw + PI * 0.5
		c.node.rig.rotation.y = c.node.yaw
		c.pos = pos
		_msg(id, "Položeno.", 1.5)


## Vrátí hráči rychlost chůze a uvolní tělo (volá i uložení / načtení hry).
func _release_player(id: int) -> void:
	if not _carry.has(id):
		return
	var e: Dictionary = _carry[id]
	var c: Carcass = e["c"]
	var p := _player(id)
	if p != null:
		p.walk_speed = float(e["walk0"])
		p.sprint_speed = float(e["sprint0"])
		p.jump_velocity = float(e.get("jump0", p.jump_velocity))
	c.carried_by = 0
	if c.node != null and is_instance_valid(c.node):
		c.node.set_physics_process(true)
	_carry.erase(id)


func _carry_follow(delta: float) -> void:
	for id in _carry.keys():
		var e: Dictionary = _carry[id]
		var c: Carcass = e["c"]
		var p := _player(id)
		if p == null or c.node == null or not is_instance_valid(c.node):
			_release_player(id)
			continue
		if p.car != null or p.horse != null:
			drop(id)
			continue
		var left := Basis(Vector3.UP, p.yaw) * Vector3.LEFT
		var n: Animal = c.node
		n.global_position = p.global_position + CARRY_SHOULDER
		n.yaw = atan2(left.x, left.z)
		n.rig.rotation.y = n.yaw
		c.pos = n.global_position
		# výdrž: chůze s břemenem unavuje; při nule ho hráč upustí
		var hv := Vector2(p.velocity.x, p.velocity.z).length()
		if hv > 0.5:
			p.stamina = maxf(p.stamina - delta * CARRY_STAMINA_K * carried_kg(id) / 20.0, 0.0)
		if p.stamina <= 0.01:
			_msg(id, "Došly ti síly – zvěř ti sklouzla z ramene.", 3.0)
			drop(id)


# ------------------------------------------------------------------ prodej zvěřiny

## Výkup zvěřiny (`World.sell_items` pro `zverina_*`): legální kusy jen s dokladem o původu (jeden kryje `DOC_COVER_PCS` ks),
## nelegální (`black`) nikde – jen u překupníka. Vrací true, když prodej vyřídil (i odmítnutím); false = nemá co prodat.
func sell_venison(id: int, item_id: String, unit_price: int, _place := "") -> bool:
	var p := _player(id)
	if p == null:
		return false
	var n := p.item_count(item_id)
	if n <= 0:
		return false
	var b: Dictionary = black.get(id, {})
	var illegal := mini(n, int(b.get(item_id, 0)))
	var legal := n - illegal
	if legal <= 0:
		_msg(id, "„Tohle vám nekoupím. Kdo ví, odkud to máte…“ (nelegální zvěřina bokem – překupník večer za hospodou)", 4.0)
		return true
	var doc := String(cfg("dokument", "doklad_puvod"))
	var docs := p.item_count(doc)
	if docs <= 0:
		_msg(id, "„Bez dokladu o původu zvěřiny to nekoupím.“", 3.5)
		return true
	var sold := mini(legal, docs * DOC_COVER_PCS)
	var used := int(ceil(float(sold) / float(DOC_COVER_PCS)))
	p.remove_item(item_id, sold)
	p.remove_item(doc, used)
	p.money += sold * unit_price
	world.play_sfx(id, "cash")
	_msg(id, "Prodáno: %d× %s za %d Kč (doklady: −%d)." % [sold, ItemsDB.name_of(item_id), sold * unit_price, used], 3.5)
	return true


## Tržní cena zvěřiny v hospodě (základ pro překupníka a sousedy).
func _market_price(item_id: String) -> int:
	for o in Place.OFFERS.get("hospoda", []):
		if String(o[0]) == item_id and String(o[2]) == "sell":
			return int(o[1])
	return int(ItemsDB.info(item_id).get("price", 100)) if ItemsDB.exists(item_id) else 100


func _dealer_cfg() -> Dictionary:
	return cfg("prekupnik", FALLBACK["prekupnik"])


func _build_dealer() -> void:
	_dealer_tried = true
	# DOPLNIT: souřadnice překupníka – výchozí varianta: ~12 m od dveří hospody směrem pryč od domova (za hospodou);
	# podle mapy jde místo upřesnit (u pálenice / za stodolou) změnou `dealer_pos`.
	if not world.places.has("hospoda") or not world.places.has("domov"):
		return
	var hp: Vector3 = world.places["hospoda"].door
	var hm: Vector3 = world.lot_door()      # M1.7: stálý bod (usedlost) – překupník stojí pořád na stejném místě
	var dir := hp - hm
	dir.y = 0.0
	dir = dir.normalized() if dir.length() > 0.1 else Vector3.FORWARD
	var side := Vector3(-dir.z, 0.0, dir.x)
	dealer_pos = hp + dir * 10.0 + side * 6.0
	dealer_pos.y = world.terrain.height_at(dealer_pos.x, dealer_pos.z)
	dealer = Npc.make(String(_dealer_cfg().get("jmeno", "Kamarád Franta")), "", Color(0.3, 0.27, 0.22), 9191, dealer_pos,
		atan2(-dir.x, -dir.z), world)
	add_child(dealer)
	dealer.face_player = true
	dealer.visible = false
	dealer.collision_layer = 0


func _dealer_tick() -> void:
	if not _dealer_tried:
		_build_dealer()
	if dealer == null or not is_instance_valid(dealer):
		return
	var h := world.clock.hour()
	var c := _dealer_cfg()
	var on := h >= float(c.get("od_h", 19.0)) and h < float(c.get("do_h", 24.0))
	if on != dealer.visible:
		dealer.visible = on
		dealer.collision_layer = 4 if on else 0


func _on_dealer(id: int) -> void:
	var p := _player(id)
	var cl = world.clients.get(id)
	if p == null or cl == null:
		return
	var c := _dealer_cfg()
	var opts := []
	var bonus := float(c.get("bonus", 1.3))
	for item in VENISON_ITEMS:
		var n := p.item_count(item)
		if n > 0:
			var price := roundi(_market_price(item) * bonus)
			opts.append(["Prodat %d× %s (%d Kč/ks, bez otázek)" % [n, ItemsDB.name_of(item), price], _sell_dealer.bind(id, item, price)])
	var nmax := int(c.get("soused_max_ks", 3))
	opts.append(["Nabídnout sousedům bokem (max %d ks)" % nmax, _sell_neighbors.bind(id)])
	opts.append(["Nic, díky", func(): pass])
	cl.hud.open_menu(dealer.display_name, "„Tišeji. Co máš v tašce? Zeptám se jen jednou a nikdy jsme se neviděli.“\n(Nelegální zvěřina: víc peněz, ale riziko prásknutí.)", opts)


func _sell_dealer(id: int, item: String, price: int) -> void:
	var p := _player(id)
	if p == null:
		return
	var n := p.item_count(item)
	if n <= 0:
		return
	p.remove_item(item, n)
	var b: Dictionary = black.get(id, {})
	b[item] = maxi(int(b.get(item, 0)) - n, 0)
	black[id] = b
	p.money += n * price
	world.play_sfx(id, "cash")
	var rep: Reputation = world.reputations.get(id)
	if rep:
		rep.change_karma(KARMA_NEIGHBOR, "zvěřina bokem")
	_msg(id, "Prodáno překupníkovi: %d× %s za %d Kč." % [n, ItemsDB.name_of(item), n * price], 3.5)
	if _rng.randf() < float(_dealer_cfg().get("prask_p", 0.1)):
		_msg(id, "Překupník tě prásknul! Je to pytláctví.", 4.0)
		world.commit_offense(id, "pytlactvi", {"severity": 0.4})


func _sell_neighbors(id: int) -> void:
	var p := _player(id)
	if p == null:
		return
	var left := int(_dealer_cfg().get("soused_max_ks", 3))
	var coef := float(_dealer_cfg().get("soused_koef", 0.8))
	var total := 0
	var pcs := 0
	for item in VENISON_ITEMS:
		var n := mini(p.item_count(item), left)
		if n <= 0:
			continue
		var price := roundi(_market_price(item) * coef)
		p.remove_item(item, n)
		var b: Dictionary = black.get(id, {})
		b[item] = maxi(int(b.get(item, 0)) - n, 0)
		black[id] = b
		total += n * price
		pcs += n
		left -= n
		if left <= 0:
			break
	if pcs <= 0:
		_msg(id, "Nemáš co nabídnout.", 2.0)
		return
	p.money += total
	world.play_sfx(id, "cash")
	var rep: Reputation = world.reputations.get(id)
	if rep:
		rep.change_karma(KARMA_NEIGHBOR, "zvěřina sousedům bokem")
		rep.change_respect("stamgasti", RESPECT_NEIGHBOR, "sousedé, kteří se neptají")
	_msg(id, "Sousedé si vzali %d ks bez otázek: %d Kč." % [pcs, total], 3.5)


# ------------------------------------------------------------------ ukládání

func to_dict() -> Dictionary:
	var arr := []
	for c in carcasses:
		if c.node == null or not is_instance_valid(c.node) or c.stored != "":
			continue                # úlovek na vozíku / v autě ukládá `Cargo` (M2.10)
		var d: Dictionary = (c as Carcass).to_dict()
		var pl := _player(c.carried_by) if c.carried_by != 0 else null
		if pl != null:
			d["pos"] = [pl.global_position.x, pl.global_position.y, pl.global_position.z]   # nesené tělo se uloží u nohou hráče
		arr.append(d)
	var bl := {}
	for id in black:
		bl[str(id)] = black[id]
	return {"carcasses": arr, "black": bl}


## Starý save bez klíče `hunting` = žádná těla ani nelegální maso.
func restore(d: Dictionary) -> void:
	for id in _carry.keys():
		_release_player(id)
	for c in carcasses:
		if c.node != null and is_instance_valid(c.node):
			c.node.queue_free()
	carcasses.clear()
	wounded.clear()
	black.clear()
	for k in d.get("black", {}):
		black[int(k)] = (d["black"][k] as Dictionary).duplicate()
	if world.fauna == null:
		return
	for cd in d.get("carcasses", []):
		var c := Carcass.from_dict(cd)
		var a := _spawn_corpse(c)
		if a == null:
			continue
		c.node = a
		carcasses.append(c)


## M2.10: obnoví úlovek ze záznamu (`Carcass.to_dict`) včetně těla a zařadí ho mezi úlovky (uložení nákladu ve `Cargo`). Null = nejde.
func spawn_carcass(cd: Dictionary) -> Carcass:
	if world.fauna == null:
		return null
	var c := Carcass.from_dict(cd)
	var a := _spawn_corpse(c)
	if a == null:
		return null
	c.node = a
	carcasses.append(c)
	return c


## Ladění (F2 → Příroda → „položit mrtvého srnce / divočáka“, M2.10): legální, nevyvržený úlovek před hráčem.
func spawn_debug_carcass(id: int, species: String) -> String:
	var p := _player(id)
	if p == null or world.fauna == null:
		return "Zvěř ještě není ve světě."
	if not AnimalSpecs.SPECIES.has(species):
		return "Neznámý druh."
	var fwd := Basis(Vector3.UP, p.yaw) * Vector3.FORWARD
	var pos := p.global_position + fwd * 2.0
	var c := Carcass.new()
	c.species = species
	c.male = true
	c.live_kg = float(AnimalSpecs.SPECIES[species]["mass"])
	c.died_min = _now()
	c.pos = pos
	c.owner_id = id
	c.legal = true
	c.reported = true
	c.found = true
	c.cargo_kind = String(species_info(species).get("cargo", ""))
	var a := _spawn_corpse(c)
	if a == null:
		return "Nejde vytvořit tělo."
	c.node = a
	carcasses.append(c)
	return "Mrtvý %s (%d kg) leží před tebou." % [String(species_info(species).get("nazev", species)), roundi(c.live_kg)]


## Obnoví mrtvé tělo zvířete (model leží na boku) z uloženého záznamu.
func _spawn_corpse(c: Carcass) -> Animal:
	if not AnimalSpecs.SPECIES.has(c.species):
		return null
	var m := int(world.clock.date()["month"])
	var variant := {"male": c.male, "winter": m >= 11 or m <= 3, "tint": 1.0}
	var pos := c.pos
	pos.y = world.terrain.height_at(pos.x, pos.z)
	_seed_n += 1
	var a := Animal.new()
	a.setup(world.fauna, c.species, pos, null, variant, 7700 + _seed_n)
	a.name = "uloveno_%d" % _seed_n
	world.fauna.root_animals.add_child(a)
	world.fauna.animals.append(a)
	a.make_corpse()
	a.rig.dead = 1.0
	return a
