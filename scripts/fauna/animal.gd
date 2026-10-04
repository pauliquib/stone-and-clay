## Divoké čtyřnohé zvíře (srnec, divočák, sele, zajíc) – fyzika pohybu a chování podle AnimalSpecs.
##
## Fyzika: rychlost se mění jen s omezeným zrychlením / brzděním (hmotnost), zatáčí se s omezenou
## úhlovou rychlostí a dostředivým zrychlením (rychlé zvíře zatáčí širokým obloukem), do kopce zpomalí,
## na příliš prudký svah nevyleze, překážky (kmeny, zdi) obchází podle paprsků, přes nízké přeskočí
## (balistický skok podle výšky ve specifikaci), padá gravitací, auto ho může srazit (knock).
##
## Chování (stavový automat): pastva / rytí → přesun v okrsku podle stanoviště (les, okraj, pole) →
## odpočinek mimo dobu aktivity (leží) → pozornost (hlava nahoru, dívá se na člověka) → útěk (od hrozby
## a k lesu; srnec štěkne, zajíc kličkuje) → uklidnění. Zajíc v pelechu strne a vyrazí až zblízka,
## bachyně se selaty může zaútočit. Vnímání: zrak (tma, les a přikrčení ho zkracují), sluch (běh,
## auto), čich (po větru cítí dál). Jezdce na koni se zvěř bojí méně.
##
## Klid: zvěř je plachá, ale ne hysterická – útěk je klusem / cvalem podle blízkosti hrozby (flee_speed),
## nehybného člověka dál než flight si časem přivykne (calm) a po chvíli se vrátí k pastvě.
##
## Úroveň detailu: do 110 m od hráče plná fyzika, do 260 m bez kolizí (výška z terénu), dál neviditelné
## a „přemýšlí“ jen jednou za 1,5 s. Vzdálenost se bere od NEJBLIŽŠÍHO hráče (`World.nearest_player_dist`
## prochází celé `world.players`), takže s více hráči je zvíře FULL, kdykoli je do 110 m od kteréhokoli z nich
## (na serveru v MP tedy fyziku a AI dostane každé zvíře poblíž kohokoli; daleko od všech jen zjednodušeně).
##
## Multiplayer (příprava): zvíře má `net_id` a `authority`. Autorita (výchozí true = singleplayer / server)
## simuluje AI a fyziku jako vždy. Klientské „loutka“ (`authority = false`, vyrábí ji `Fauna._spawn_puppet`)
## nemá AI ani fyziku: `puppet_push` mu předá snímek ze serveru, `_puppet_process` z posledních snímků
## interpoluje polohu a yaw (zpoždění PUPPET_DELAY) a rig animuje ze rychlosti; LOD podle nejbližšího lokálního hráče.
class_name Animal
extends CharacterBody3D

enum Lod { FULL, NEAR, FAR }
const FULL_R := 110.0
const NEAR_R := 260.0
const GRAVITY := 20.0
## Stavy pro síť (index ve snímku = pozice v poli); nové stavy jen na konec.
const STATES := ["graze", "move", "rest", "alert", "flee", "freeze", "charge", "dead"]
const FLAG_DEAD := 1
const FLAG_MALE := 2
const FLAG_YOUNG := 4
const FLAG_WINTER := 8
const PUPPET_DELAY := 0.15           # loutka se zobrazuje o tolik s pozadu (interpolace mezi snímky)
const PUPPET_EXTRAP := 0.25          # nejvýš tolik s se dopředu odhaduje pohyb, když snímek nepřišel
const PUPPET_BUF := 4                # kolik posledních snímků se drží
# ---- M2.9 postřelení (`shot`): energie (J) potřebná k okamžitému usmrcení srnce (24 kg); pro těžší zvíře × (hmotnost / 24)^0,6.
const KILL_HEAD_J := 40.0            # zásah do hlavy
const KILL_HEART_J := 75.0           # komora (srdce a plíce)
const WOUND_RUN_HEART_M := [20.0, 60.0]   # srdce: tolik m ještě uběhne a padne
const WOUND_RUN_BELLY_M := [200.0, 600.0] # břicho: uteče daleko a zalehne
const WOUND_LIE_MIN := [60.0, 180.0]      # zalehlé zvíře zhyne za 1–3 herní hodiny
const WOUND_RISE_M := 15.0           # při přiblížení na tolik m se zalehlé zvíře může zvednout a utéct dál
const WOUND_RISE_RUN_M := [100.0, 250.0]
const WOUND_RISE_P := 0.5
const WOUND_RISES_MAX := 2
const LIMP_S := 900.0                # postřelená noha: tolik s kulhá (zpomalené, stopa)
const LIMP_SPEED_K := 0.55
const BLOOD_STEP_M := 2.5            # krvavá kapka každých tolik m běhu
const STAND_HEIGHT_M := 3.0          # hráč výš než tolik m nad terénem (posed) je zvěři hůř vidět a cítit
const STAND_SIGHT_K := 0.6

var spec: Dictionary
var species := ""
var fauna: Fauna
var herd: Herd
var slot_i := 0
var rig: QuadrupedRig
var rng := RandomNumberGenerator.new()
var home := Vector3.ZERO
var male := false
var young := false
var dead := false
var net_id := 0                      # stabilní síťové číslo (Fauna ho přiděluje; 0 = nepřiděleno)
var authority := true                # true = simuluje se tady; false = loutka podle snímků serveru
var keep_corpse := false             # srážka s autem: tělo zůstane ležet, dokud si ho nevyzvedne myslivec (Hunter)
# M2.9 postřelení: "" zdravé, "srdce" (uběhne a padne), "bricho" (uteče daleko, zalehne, zhyne), "noha" (kulhá)
var wound := ""
var wound_left := 0.0                # kolik m ještě uběhne
var wound_lie := false               # zalehlé (ještě žije)
var wound_die_min := 0.0             # herní minuta (Clock.minutes), kdy zalehlé zvíře zhyne
var wound_src := Vector3.ZERO        # odkud přišla rána (od toho uteče)
var shot_by := {}                    # {id, weapon, legal, reasons, zone} – kdo a čím zvíře postřelil (čte `Hunting`)
var limp_t := 0.0                    # do konce kulhání (s)
var _wound_last := Vector3.INF       # poloha při minulém kroku (krvavá stopa, uběhnutá vzdálenost)
var _blood_acc := 0.0
var _wound_rises := 0
var _rise_rolled := false

var state := "graze"                 # graze, move, rest, alert, flee, freeze, charge, dead
var state_t := 0.0                   # jak dlouho trvá stav (s)
var target := Vector3.INF
var yaw := 0.0
var speed := 0.0                     # rychlost vpřed (m/s)
var want_speed := 0.0
var want_dir := Vector3.FORWARD
var aware := 0.0                     # 0..1 jak moc si všiml hrozby
var threat: Node3D = null
var threat_d := INF

var _lod := Lod.FAR
var _lod_t := 0.0
var _think_t := 0.0
var _far_dt := 0.0
var _avoid := 0.0                    # úhlový posun kvůli překážce (rad)
var _avoid_t := 0.0
var _probe_t := 0.0
var _zig_t := 0.0
var _stuck_t := 0.0
var _last_pos := Vector3.ZERO
var _prev_threat_d := INF
var _approaching := false            # hrozba se přibližuje (z posledního _think)
var _calm_t := 0.0                   # jak dlouho v pozoru hrozba nepřibližuje se (s)
var _alert_cd := 0.0                 # do té doby (s) se nepřibližující hrozba znovu nevšímá
var _yaw_rate := 0.0
var _slope := 0.0
var _graze := 0.0
var _alert := 0.0
var _lie := 0.0
var _crouch := 0.0
var _sit := 0.0                     # zajíc „panáček" (sedí na zadních a rozhlíží se)
var _pronk_t := 0.0                 # odstup času do příštího odrazového skoku při útěku
var _anim_dt := 0.0                 # akumulace času pro animaci ve vzdáleném LOD
var _charged := false
var _noise_pos := Vector3.ZERO         # odkud zazněl výstřel / hluk (M2.8), odtud zvíře prchá
var _noise_t := 0.0                    # do kdy (s) zvíře prchá před hlukem
var _snd: AudioStreamPlayer3D
var _snd_t := 5.0
var _dead_t := 0.0
var _foot: CollisionShape3D
var _torso: CollisionShape3D
var _soil: GPUParticles3D           # odhrnutá hlína při rytí (divočák)
var _pbuf: Array = []                # loutka: poslední snímky [čas příjmu, poloha, yaw, rychlost]
var _p_hop := 0.0                    # loutka: výška nad terénem v minulém kroku (odhad svislé rychlosti skoku)


func setup(f: Fauna, id: String, pos: Vector3, h: Herd, variant: Dictionary, seed_: int) -> void:
	fauna = f
	species = id
	spec = AnimalSpecs.get_spec(id)
	herd = h
	rng.seed = seed_
	male = variant.get("male", false)
	young = spec.has("base")
	home = pos
	position = pos + Vector3(0, 0.05, 0)
	yaw = rng.randf() * TAU
	want_dir = Vector3(sin(yaw), 0, cos(yaw))
	rig = QuadrupedModel.build(spec, variant)
	rig.name = "Model"


func _ready() -> void:
	collision_layer = 4                # jako psi a vesničané → auta před zvířetem brzdí, srazí ho
	collision_mask = 1 | 2 | 8 | 16
	if not authority:
		collision_layer = 0            # loutka je jen vizuální (kolize a zásahy řeší server)
		collision_mask = 0
	floor_max_angle = deg_to_rad(float(spec["max_slope"]) + 5.0)
	floor_snap_length = 0.5
	safe_margin = 0.02
	var g := QuadrupedModel.geometry(spec)
	# dolní kapsle pod trupem nese zvíře (kontakt se zemí), kvádr trupu naráží do překážek
	var sh := CapsuleShape3D.new()
	sh.radius = clampf(float(spec["chest"][0]) * 0.8, 0.05, 0.3)
	sh.height = maxf(g["shoulder_h"], sh.radius * 2.0 + 0.02)
	_foot = CollisionShape3D.new()
	_foot.shape = sh
	_foot.position.y = sh.height * 0.5
	add_child(_foot)
	var bx := BoxShape3D.new()
	var ch: Array = spec["chest"]
	bx.size = Vector3(ch[0] * 2.0, ch[1] * 1.6, float(spec["length"]) + ch[1] * 0.6)
	_torso = CollisionShape3D.new()
	_torso.shape = bx
	_torso.position = Vector3(0, float(g["y_mid"]) + ch[1] * 0.1, 0)
	add_child(_torso)
	add_child(rig)
	rig.rotation.y = yaw
	rig.footfall.connect(_on_footfall)
	rig.ground_fn = fauna.terrain.height_at
	rig.foot_ik = false                # zapne se až v LOD FULL (štedří výkon)
	rig.visible = false
	if spec["behaviour"] == "rooter":
		_soil = _soil_particles()
		_soil.position = Vector3(0, -float(spec["head"][1]) * 0.5, float(spec["head"][0]) * 0.85)
		rig.head.add_child(_soil)
	_last_pos = global_position
	_think_t = rng.randf() * 1.0
	_lod_t = rng.randf() * 0.5


# ------------------------------------------------------------------ smyčka

func _physics_process(delta: float) -> void:
	if fauna == null:
		return
	_lod_t -= delta
	if _lod_t <= 0.0:
		_lod_t = 0.5
		_update_lod()
	if not authority:
		_puppet_process(delta)
		return
	if dead:
		_dead_update(delta)
		return
	if _lod == Lod.FAR:
		_far_dt += delta
		if _far_dt < 1.5:
			return
		delta = _far_dt
		_far_dt = 0.0
		state_t += delta
		_think(delta)
		_steer(delta)
		_kinematic_move(delta)
		return
	state_t += delta
	_think_t -= delta
	if _think_t <= 0.0:
		_think_t = 0.25 if _lod == Lod.FULL else 0.6
		_think(0.25 if _lod == Lod.FULL else 0.6)
	_steer(delta)
	if _lod == Lod.FULL:
		_physics_move(delta)
	else:
		_kinematic_move(delta)
	# vzdálená zvířata (LOD NEAR) se animují jen ~10× za sekundu – na dálku to není poznat
	_anim_dt += delta
	if _lod == Lod.FULL or _anim_dt >= 0.1:
		_animate(_anim_dt)
		_anim_dt = 0.0
	_sounds(delta)


func _update_lod() -> void:
	var d: float = fauna.world.nearest_player_dist(global_position)
	var want := Lod.FAR
	if d < FULL_R:
		want = Lod.FULL
	elif d < NEAR_R:
		want = Lod.NEAR
	if want == _lod:
		return
	_lod = want
	rig.visible = _lod != Lod.FAR
	rig.foot_ik = _lod == Lod.FULL
	var on := _lod == Lod.FULL
	_foot.disabled = not on
	_torso.disabled = not on
	if on and authority:
		# zpátky na terén (daleko se pohybovalo bez kolizí)
		global_position.y = fauna.terrain.height_at(global_position.x, global_position.z) + 0.05
		velocity = Vector3.ZERO


# ------------------------------------------------------------------ síť: loutka a snímek

## Kompaktní záznam pro klienty: [net_id, index druhu (Fauna.SPECIES_IDS), x, y, z (dm), yaw (1/1024 otáčky),
## rychlost (dm/s), index stavu (STATES), příznaky]. Všechno celá čísla (var_to_bytes je pak malé).
func net_record() -> Array:
	var flags := 0
	if dead:
		flags |= FLAG_DEAD
	if male:
		flags |= FLAG_MALE
	if young:
		flags |= FLAG_YOUNG
	if fauna.clock.month() >= 11 or fauna.clock.month() <= 3:
		flags |= FLAG_WINTER
	var p := global_position
	return [net_id, Fauna.SPECIES_IDS.find(species), roundi(p.x * 10.0), roundi(p.y * 10.0), roundi(p.z * 10.0),
		roundi(fposmod(yaw, TAU) / TAU * 1024.0), roundi(speed * 10.0), maxi(STATES.find(state), 0), flags]


## Loutka dostala snímek ze serveru (čas příjmu `t` v s, poloha, yaw, rychlost, index stavu, příznaky).
func puppet_push(t: float, pos: Vector3, yaw_: float, spd: float, state_i: int, flags: int) -> void:
	var st: String = STATES[clampi(state_i, 0, STATES.size() - 1)]
	var known := not _pbuf.is_empty()
	_pbuf.append([t, pos, yaw_, spd])
	while _pbuf.size() > PUPPET_BUF:
		_pbuf.pop_front()
	dead = (flags & FLAG_DEAD) != 0
	if dead:
		st = "dead"
	if st != state:
		state = st
		state_t = 0.0
		if known:                       # zvuk podle změny stavu (nový záznam nebouchá)
			if st == "flee":
				_play("alarm")
			elif st == "charge":
				_play("attack")


## Vzorek z vyrovnávací paměti snímků v čase `rt`: [poloha, yaw, rychlost]. Mezi dvěma snímky lineárně,
## za posledním krátce dopředu podle rychlosti (PUPPET_EXTRAP), pak drží. Sdílí ho Horse.
static func puppet_sample(buf: Array, rt: float) -> Array:
	var first: Array = buf[0]
	if buf.size() == 1 or rt <= float(first[0]):
		return [first[1], first[2], first[3]]
	for i in range(1, buf.size()):
		var b: Array = buf[i]
		if rt <= float(b[0]):
			var a: Array = buf[i - 1]
			var span := float(b[0]) - float(a[0])
			var k := clampf((rt - float(a[0])) / maxf(span, 0.0001), 0.0, 1.0)
			var pa: Vector3 = a[1]
			var pb: Vector3 = b[1]
			return [pa.lerp(pb, k), lerp_angle(float(a[2]), float(b[2]), k), lerpf(float(a[3]), float(b[3]), k)]
	var last: Array = buf[buf.size() - 1]
	var over := minf(rt - float(last[0]), PUPPET_EXTRAP)
	var lp: Vector3 = last[1]
	var ly: float = last[2]
	var ls: float = last[3]
	return [lp + Vector3(sin(ly), 0.0, cos(ly)) * ls * over, ly, ls]


## Krok loutky (jen `authority == false`): žádná AI ani fyzika, jen interpolace a animace.
func _puppet_process(delta: float) -> void:
	if _pbuf.is_empty():
		return
	var s := Animal.puppet_sample(_pbuf, Time.get_ticks_msec() / 1000.0 - PUPPET_DELAY)
	var np: Vector3 = s[0]
	var ny: float = s[1]
	speed = s[2]
	_yaw_rate = lerpf(_yaw_rate, wrapf(ny - yaw, -PI, PI) / maxf(delta, 0.001), 0.3)
	yaw = ny
	global_position = np
	if _lod == Lod.FAR:
		return
	if dead:
		rig.dead = move_toward(rig.dead, 1.0, delta * 3.0)
		rig.speed = 0.0
		rig.animate(delta)
		return
	# sklon těla a případný skok (výška nad terénem) – jen pro viditelná zvířata
	var fwd := Vector3(sin(yaw), 0, cos(yaw))
	var L: float = spec["length"]
	var h0: float = fauna.terrain.height_at(np.x, np.z)
	var h1: float = fauna.terrain.height_at(np.x + fwd.x * L, np.z + fwd.z * L)
	_slope = atan2(h1 - h0, L)
	var hop := np.y - h0 - 0.05
	velocity = Vector3(0.0, (hop - _p_hop) / maxf(delta, 0.001), 0.0)
	_p_hop = hop
	_anim_dt += delta
	if _lod == Lod.FULL or _anim_dt >= 0.1:
		_animate(_anim_dt)
		_anim_dt = 0.0
	_sounds(delta)


# ------------------------------------------------------------------ vnímání a rozhodování

func _think(dt: float) -> void:
	if wound != "" and _wound_think(dt):
		return
	_perceive(dt)
	var h: float = fauna.clock.hour()
	var active := AnimalSpecs.is_active(spec, h)
	var weather: Weather = fauna.weather
	var bad_weather := weather != null and (weather.rain > 0.5 or weather.wind > 12.0)
	var beh: String = spec["behaviour"]
	# --- hrozba
	if herd and herd.alarmed() and state != "flee" and state != "charge":
		_enter("flee")
	if _noise_t > 0.0:
		_noise_t -= dt
		if state != "flee" and state != "charge":
			_enter("flee")
	if threat:
		var flight := _flight_distance()
		var approaching := _prev_threat_d - threat_d > 0.35 * dt
		_approaching = approaching
		if beh == "hare" and state in ["rest", "graze", "freeze", "move"] and threat_d > flight and aware > 0.4:
			if state != "freeze":
				_enter("freeze")
		elif threat_d < flight and (aware > 0.45 or threat_d < flight * 0.5):
			if beh == "rooter" and herd and herd.has_young and not young and not male and threat_d < 11.0 \
					and approaching and not _charged and threat is Player:
				_enter("charge")
			elif state != "flee" and state != "charge":
				_enter("flee")
				if herd:
					herd.alarm(threat.global_position, 6.0)
		elif aware > 0.5 and threat_d < flight * (2.2 if approaching else 1.6) and state in ["graze", "move", "rest"] \
				and (_alert_cd <= 0.0 or approaching):
			_enter("alert")
	else:
		_approaching = false
	_prev_threat_d = threat_d
	_alert_cd = maxf(_alert_cd - dt, 0.0)
	# --- stavy
	match state:
		"flee":
			var src := herd.alarm_pos if herd and herd.alarmed() else Vector3.INF
			if threat:
				src = threat.global_position
			if src == Vector3.INF and _noise_t > 0.0:
				src = _noise_pos
			if src == Vector3.INF:
				_enter("move")
				return
			var safe: float = spec["safe"]
			var d := global_position.distance_to(src)
			if d > safe and (herd == null or not herd.alarmed()) and state_t > 3.0:
				_enter("alert")
				return
			var away := global_position - src
			away.y = 0.0
			want_dir = _flee_dir(away.normalized())
			var top: float = spec["gaits"]["gallop"]
			var fl: float = spec["flight"]
			want_speed = lerpf(float(spec["flee_speed"]), top, clampf(1.0 - d / maxf(fl * 0.6, 1.0), 0.0, 1.0))
			if threat is Car and (threat as Car).linear_velocity.length() > 8.0:
				want_speed = top
			if limp_t > 0.0:
				want_speed *= LIMP_SPEED_K
			if beh == "hare":
				_zig_t -= dt
				if _zig_t <= 0.0 and d < 30.0:
					_zig_t = rng.randf_range(0.5, 1.1)
					_avoid = rng.randf_range(0.5, 0.9) * (1.0 if rng.randf() < 0.5 else -1.0)
					_avoid_t = 0.45
		"charge":
			if threat == null or state_t > 7.0 or threat_d > 25.0:
				_charged = true
				_enter("flee")
				return
			var to := threat.global_position - global_position
			to.y = 0.0
			want_dir = to.normalized()
			want_speed = float(spec["gaits"]["canter"]) * 1.3
			if threat_d < 1.4:
				_attack()
		"freeze":
			want_speed = 0.0
			if threat == null or aware < 0.15 or state_t > 40.0:
				_enter("graze")
		"alert":
			want_speed = 0.0
			# hrozba se 8 s nepřibližuje a je za únikovou vzdáleností → zvíře se uklidní
			if threat != null and not _approaching and threat_d > _flight_distance():
				_calm_t += dt
			else:
				_calm_t = 0.0
			if _calm_t > 8.0:
				aware = minf(aware, 0.3)
				_alert_cd = 30.0
				_enter("graze" if active else "rest")
				return
			if state_t > rng.randf_range(5.0, 12.0) and (threat == null or aware < 0.5):
				_enter("graze" if active else "rest")
		"rest":
			want_speed = 0.0
			if active and not bad_weather and state_t > 20.0:
				_enter("graze")
		"graze":
			_follow_or_idle(dt, active, bad_weather)
		"move":
			_follow_or_idle(dt, active, bad_weather)


## Pastva a přesuny: člen skupiny drží místo u vůdce, vůdce (nebo samotář) vybírá cíle v okrsku.
func _follow_or_idle(_dt: float, active: bool, bad_weather: bool) -> void:
	var leader: Node = herd.get_leader() if herd else null
	if leader != null and leader != self:
		var lp: Vector3 = leader.global_position + Basis(Vector3.UP, leader.yaw) * herd.slot(slot_i)
		var d := Vector3(lp.x - global_position.x, 0, lp.z - global_position.z)
		if leader.state == "rest" and d.length() < 5.0:
			_enter("rest")
			return
		if d.length() > 3.0:
			want_dir = d.normalized()
			want_speed = clampf(d.length() * 0.35, float(spec["gaits"]["walk"]) * 0.6, float(spec["gaits"]["trot"]) * 0.8)
			state = "move"
			return
		want_speed = 0.0
		state = "graze"
		return
	# vůdce / samotář: mimo dobu aktivity (nebo v nečase) si jde lehnout do úkrytu
	if (not active and state_t > 8.0) or (bad_weather and state_t > 15.0):
		var shelter := "forest" if bad_weather or spec["habitat"] != "field" else "field"
		if fauna.score(shelter, global_position.x, global_position.z) > 0.4:
			_enter("rest")
			return
		if target == Vector3.INF:
			target = fauna.random_point(global_position, 150.0, shelter, rng)
			state = "move"
	if state == "move" and target == Vector3.INF:
		_enter("graze")
	if state == "graze" and state_t > rng.randf_range(20.0, 60.0):
		if rng.randf() < 0.35:
			var hab: String = spec["habitat"]
			# srnci se ve dne drží v lese a za soumraku vycházejí na okraje a louky
			if hab == "edge" and not active:
				hab = "forest"
			var c := home if global_position.distance_to(home) > float(spec["home_range"]) * 0.8 else global_position
			target = fauna.random_point(c, float(spec["home_range"]) * 0.5, hab, rng)
			state = "move"
			state_t = 0.0
		else:
			# pár kroků při pastvě
			var a := yaw + rng.randf_range(-1.2, 1.2)
			target = global_position + Vector3(sin(a), 0, cos(a)) * rng.randf_range(1.5, 5.0)
			state = "move"
			state_t = 0.0
	if target != Vector3.INF:
		var d := Vector3(target.x - global_position.x, 0, target.z - global_position.z)
		if d.length() < 1.2:
			target = Vector3.INF
			_enter("graze")
			want_speed = 0.0
			return
		want_dir = d.normalized()
		# přesun krokem, na delší vzdálenost o něco rychleji (ne klusem)
		want_speed = float(spec["gaits"]["walk"]) if d.length() < 60.0 else float(spec["gaits"]["walk"]) * 1.5


## Kdo je hrozba a jak moc si jí zvíře všimlo (zrak, sluch, čich po větru).
func _perceive(dt: float) -> void:
	var p: Node3D = fauna.world.nearest_player(global_position)
	threat = null
	threat_d = INF
	if p == null:
		aware = move_toward(aware, 0.0, dt * 0.2)
		return
	var tpos := p.global_position
	var d := tpos.distance_to(global_position)
	var day: float = fauna.clock.daylight()
	var w: Weather = fauna.weather
	var sight: float = spec["sight"] * lerpf(0.3, 1.0, day)
	if w:
		sight *= lerpf(1.0, 0.35, w.fog)      # v husté mlze zvěř vidí zhruba na třetinu
	var cover: float = fauna.forest_at(tpos.x, tpos.z)
	sight *= lerpf(1.0, 0.55, cover)
	# M2.9: hráč na posedu (výš než STAND_HEIGHT_M nad terénem) je zvěři hůř vidět a cítit
	var on_stand: bool = tpos.y - fauna.terrain.height_at(tpos.x, tpos.z) > STAND_HEIGHT_M
	if on_stand:
		sight *= STAND_SIGHT_K
	var hear := 0.0
	var car: Node3D = p.get("car")
	var horse: Node3D = p.get("horse")
	var mover: Node3D = car if car else (horse if horse else p)
	var v := 0.0
	if mover is RigidBody3D:
		v = (mover as RigidBody3D).linear_velocity.length()
	elif mover is CharacterBody3D:
		v = Vector3((mover as CharacterBody3D).velocity.x, 0, (mover as CharacterBody3D).velocity.z).length()
	if car:
		hear = float(spec["hearing"]) * (1.2 + minf(v / 10.0, 1.2))
		sight *= 0.8
	elif horse:
		hear = float(spec["hearing"]) * clampf(v / 6.0, 0.2, 1.2)
		sight *= 0.6                  # koně se zvěř tolik nebojí
	else:
		var vis: Humanoid = p.get("visual")
		if vis and vis.crouching:
			sight *= 0.5
		hear = float(spec["hearing"]) * clampf((v - 2.0) / 5.0, 0.0, 1.2)
	# čich: vítr vane od člověka ke zvířeti → cítí ho dál
	var smell := 0.0
	if w and w.wind > 0.5:
		var wv := w.wind_vector().normalized()
		var to_me := (global_position - tpos)
		to_me.y = 0.0
		if to_me.length() > 0.1 and wv.dot(to_me.normalized()) > 0.6:
			smell = float(spec["sight"]) * 1.3 * (STAND_SIGHT_K if on_stand else 1.0)
	var detect := maxf(maxf(sight, hear), smell)
	if d < detect:
		var inc := dt * (0.3 + 1.2 * (1.0 - d / detect))
		var cap := 1.0
		# návyk: nehybný člověk dál než flight zvíře tolik nevzrušuje
		if v < 0.8 and d > float(spec["flight"]):
			inc *= 1.0 - float(spec["calm"]) * 0.7
			cap = 0.7
		if aware < cap:
			aware = minf(aware + inc, cap)
	else:
		aware = move_toward(aware, 0.0, dt * 0.08)
	threat = mover
	threat_d = d


func _flight_distance() -> float:
	var f: float = spec["flight"]
	if threat is Car:
		# auto na silnici: zvěř je zvyklá, uteče až zblízka nebo když jede rychle
		return f * clampf((threat as Car).linear_velocity.length() / 12.0, 0.4, 1.3)
	if threat and threat.has_method("is_horse"):
		return f * 0.45
	return f


## Směr útěku: pryč od hrozby, ale radši do lesa a ne do vesnice ani na prudký svah.
func _flee_dir(away: Vector3) -> Vector3:
	var best := away
	var bs := -INF
	for k in 7:
		var a := (k - 3) * 0.35
		var dir := Basis(Vector3.UP, a) * away
		var p := global_position + dir * 35.0
		var s := dir.dot(away) * 1.2 + fauna.score("forest", p.x, p.z) * 0.8
		if not fauna.terrain.contains(p.x, p.z, 60.0):
			s -= 3.0
		var dh: float = fauna.terrain.height_at(p.x, p.z) - global_position.y
		if absf(dh) / 35.0 > tan(deg_to_rad(float(spec["max_slope"]))):
			s -= 1.5
		if s > bs:
			bs = s
			best = dir
	return best.normalized()


func _enter(s: String) -> void:
	if s == state:
		return
	state = s
	state_t = 0.0
	_calm_t = 0.0
	match s:
		"flee":
			target = Vector3.INF
			_play("alarm")
		"charge":
			_play("attack")
		"graze", "rest":
			target = Vector3.INF
			want_speed = 0.0


## Bachyně narazila do člověka: odhodí ho a zraní (kly), pak uteče.
func _attack() -> void:
	var p: Player = fauna.world.nearest_player(global_position)
	if p and p.car == null:
		var dir: Vector3 = p.global_position - global_position
		dir.y = 0.0
		dir = dir.normalized()
		p.knock(dir * 5.0 + Vector3.UP * 3.0, 4.5)
		p.body.hurt(12.0, "útok divočáka")
		fauna.world.emit_game_event(p.id, "animal_attack", {"species": species})
	_charged = true
	_enter("flee")


# ------------------------------------------------------------------ pohyb

## Natočení a rychlost s fyzikálními omezeními (zrychlení, dostředivé zrychlení, svah, překážky).
func _steer(delta: float) -> void:
	if state in ["graze", "rest", "alert", "freeze"] and want_speed <= 0.0:
		want_dir = Vector3(sin(yaw), 0, cos(yaw))
	_avoid_t -= delta
	if _avoid_t <= 0.0:
		_avoid = move_toward(_avoid, 0.0, delta * 2.0)
	var dir := Basis(Vector3.UP, _avoid) * want_dir
	var want_yaw := atan2(dir.x, dir.z)
	var diff := wrapf(want_yaw - yaw, -PI, PI)
	var turn_max := minf(float(spec["turn"]), float(spec["lat_acc"]) / maxf(absf(speed), 0.3))
	if state == "alert" and threat:
		var to := threat.global_position - global_position
		diff = 0.0
		rig.look_yaw = wrapf(atan2(to.x, to.z) - yaw, -PI, PI)
	elif state == "graze" and threat and aware > 0.3 and threat_d < float(spec["flight"]) * 2.0:
		# při pastvě se občas ohlédne k člověku
		var to2 := threat.global_position - global_position
		rig.look_yaw = move_toward(rig.look_yaw, wrapf(atan2(to2.x, to2.z) - yaw, -PI, PI), delta * 1.5)
	else:
		rig.look_yaw = move_toward(rig.look_yaw, 0.0, delta)
	var dyaw := clampf(diff, -turn_max * delta, turn_max * delta)
	yaw = wrapf(yaw + dyaw, -PI, PI)
	_yaw_rate = dyaw / maxf(delta, 0.001)
	# rychlost: při ostrém úhlu zpomalit, do kopce taky
	var ws := want_speed * clampf(cos(diff), 0.25, 1.0)
	var fwd := Vector3(sin(yaw), 0, cos(yaw))
	var L: float = spec["length"]
	var h0: float = fauna.terrain.height_at(global_position.x, global_position.z)
	var h1: float = fauna.terrain.height_at(global_position.x + fwd.x * L, global_position.z + fwd.z * L)
	_slope = atan2(h1 - h0, L)
	var max_s := deg_to_rad(float(spec["max_slope"]))
	if _slope > max_s * 0.6:
		ws *= clampf(1.0 - (_slope - max_s * 0.6) / (max_s * 0.4), 0.0, 1.0)
		if _slope > max_s and ws <= 0.0 and want_speed > 0.0:
			_avoid = PI * 0.5 * (1.0 if rng.randf() < 0.5 else -1.0)
			_avoid_t = 1.0
	var acc: float = spec["accel"] if ws > speed else spec["brake"]
	speed = move_toward(speed, ws, acc * delta)


func _physics_move(delta: float) -> void:
	var fwd := Vector3(sin(yaw), 0, cos(yaw))
	# překážky: paprsky dopředu ve výšce hrudi
	_probe_t -= delta
	if _probe_t <= 0.0 and speed > 0.4:
		_probe_t = 0.15
		_probe(fwd)
	var vy := velocity.y
	if is_on_floor():
		vy = -0.5
	else:
		vy -= GRAVITY * delta
	# odrazové skoky při útěku (srnec vyskakuje i bez překážky)
	_pronk_t -= delta
	var pronk := float(spec.get("pronk", 0.0))
	if pronk > 0.0 and state == "flee" and speed > float(spec["gaits"]["canter"]) * 0.7 \
			and is_on_floor() and _pronk_t <= 0.0:
		vy = sqrt(2.0 * GRAVITY * (pronk * 0.6 + 0.1))
		_pronk_t = rng.randf_range(0.8, 1.6)
	velocity = fwd * speed + Vector3(0, vy, 0)
	move_and_slide()
	var ground: float = fauna.terrain.height_at(global_position.x, global_position.z)
	if global_position.y < ground - 1.5:
		global_position.y = ground + 0.1
		velocity.y = 0.0
	# zaseknutí (narazil a nehne se) → jiný směr
	var moved := Vector3(global_position.x - _last_pos.x, 0, global_position.z - _last_pos.z).length()
	_last_pos = global_position
	if speed > 1.0 and moved < speed * delta * 0.25:
		_stuck_t += delta
		if _stuck_t > 0.8:
			_stuck_t = 0.0
			_avoid = rng.randf_range(0.9, 1.8) * (1.0 if rng.randf() < 0.5 else -1.0)
			_avoid_t = 1.2
			speed *= 0.3
			if state == "move":
				target = Vector3.INF
	else:
		_stuck_t = maxf(_stuck_t - delta, 0.0)


func _probe(fwd: Vector3) -> void:
	var space := get_world_3d().direct_space_state
	var g_y: float = float(spec["withers"]) * 0.6
	var from := global_position + Vector3(0, g_y, 0) + fwd * float(spec["length"]) * 0.5
	var reach := clampf(speed * 0.7, 1.2, 8.0)
	var q := PhysicsRayQueryParameters3D.create(from, from + fwd * reach, 1 | 8 | 16)
	q.exclude = [get_rid()]
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return
	# přeskočit? (nízká překážka, dost rychlosti, na zemi)
	var jump: float = spec["jump"]
	if jump > 0.0 and speed > 2.5 and is_on_floor():
		var top := global_position + Vector3(0, jump + 0.25, 0)
		var q2 := PhysicsRayQueryParameters3D.create(top, top + fwd * (reach + 1.0), 1 | 8 | 16)
		q2.exclude = [get_rid()]
		if space.intersect_ray(q2).is_empty():
			velocity.y = sqrt(2.0 * GRAVITY * (jump * 0.85 + 0.15))
			return
	# obejít: stranu, kde je volněji
	var best := 0.0
	var bd := -1.0
	for a in [0.6, -0.6, 1.2, -1.2]:
		var d := Basis(Vector3.UP, a) * fwd
		var q3 := PhysicsRayQueryParameters3D.create(from, from + d * reach, 1 | 8 | 16)
		q3.exclude = [get_rid()]
		var h := space.intersect_ray(q3)
		var free := reach if h.is_empty() else from.distance_to(h["position"])
		if free > bd + 0.2:
			bd = free
			best = a
	_avoid = best
	_avoid_t = 0.7


func _kinematic_move(delta: float) -> void:
	var fwd := Vector3(sin(yaw), 0, cos(yaw))
	var p := global_position + fwd * speed * delta
	if not fauna.terrain.contains(p.x, p.z, 50.0):
		yaw = wrapf(yaw + PI, -PI, PI)
		speed = 0.0
		return
	p.y = fauna.terrain.height_at(p.x, p.z)
	global_position = p
	velocity = fwd * speed
	_last_pos = p


# ------------------------------------------------------------------ vzhled a zvuk

func _animate(delta: float) -> void:
	var k := 1.0 - exp(-delta * 3.0)
	var beh: String = spec["behaviour"]
	_graze = lerpf(_graze, 1.0 if state == "graze" and speed < 0.3 else 0.0, k)
	_alert = lerpf(_alert, 1.0 if state in ["alert", "freeze"] or (state == "flee" and speed < 2.0) else 0.0, k * 2.0)
	_lie = lerpf(_lie, 1.0 if state == "rest" and beh != "hare" else 0.0, k * 0.6)
	_crouch = lerpf(_crouch, 1.0 if (state == "freeze" or state == "rest" and beh == "hare") else 0.0, k * 2.0)
	# zajíc v pozornosti se postaví na zadní („panáček"), jinak sedí 0
	_sit = lerpf(_sit, 1.0 if beh == "hare" and state == "alert" and speed < 0.5 else 0.0, k * 2.5)
	rig.rotation.y = yaw
	rig.speed = speed
	rig.turn_rate = _yaw_rate
	rig.slope = _slope
	rig.graze = _graze
	rig.alert = _alert
	rig.lie = _lie
	rig.crouch = _crouch
	rig.sit = _sit
	rig.rooting = beh == "rooter"
	if _soil:
		_soil.emitting = _lod == Lod.FULL and rig.rooting and _graze > 0.5
	rig.airborne = clampf(absf(velocity.y) / 4.0, 0.0, 1.0) if _lod == Lod.FULL and not is_on_floor() else 0.0
	rig.animate(delta)


## Hrudebníček hlíny u rypáku divočáka při rytí (drobné částice letí dozadu).
func _soil_particles() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 16
	p.lifetime = 0.5
	p.local_coords = false
	p.explosiveness = 0.0
	p.emitting = false
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1.0, -0.5)
	pm.spread = 42.0
	pm.initial_velocity_min = 0.5
	pm.initial_velocity_max = 1.5
	pm.gravity = Vector3(0, -8.0, 0)
	pm.scale_min = 0.4
	pm.scale_max = 1.2
	p.process_material = pm
	var m := SphereMesh.new()
	m.radius = 0.018
	m.height = 0.036
	m.radial_segments = 5
	m.rings = 3
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.15, 0.1, 0.06)
	mat.roughness = 1.0
	m.material = mat
	p.draw_pass_1 = m
	p.visibility_aabb = AABB(Vector3(-5, -5, -5), Vector3(10, 10, 10))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p


func _sounds(delta: float) -> void:
	if _lod != Lod.FULL:
		return
	_snd_t -= delta
	if _snd_t <= 0.0:
		_snd_t = rng.randf_range(6.0, 18.0)
		if state in ["graze", "move"] and spec["sounds"].has("idle") and rng.randf() < 0.5:
			_play("idle")


func _play(kind: String) -> void:
	if _lod != Lod.FULL or not spec["sounds"].has(kind):
		return
	if _snd == null:
		_snd = NatureSfx.player3d(self, 90.0, 2.0)
	_snd.stream = NatureSfx.get_stream(spec["sounds"][kind])
	_snd.pitch_scale = rng.randf_range(0.9, 1.1) * (1.4 if young else 1.0)
	_snd.play()


# ------------------------------------------------------------------ srážka a úhyn

## Výstřel / hlasitý zvuk v `pos` (M2.8, `Weapons`): zvíře i celé stádo se splaší a běží pryč od zdroje hluku.
func hear_shot(pos: Vector3, panic_s := 20.0) -> void:
	if dead:
		return
	_noise_pos = pos
	_noise_t = maxf(_noise_t, panic_s)
	aware = 1.0
	if herd:
		herd.alarm(pos, panic_s)


# ------------------------------------------------------------------ postřelení (M2.9)

## Zásah střelou (volá `Hunting.animal_shot`): zóna z `Weapons.zone_of`, energie z balistiky (J), `from` = odkud se střílelo,
## `info` = {id, weapon, legal, …} pro `Hunting`. Vrací "dead" (padlo na místě), "wounded" (postřelené, uteče) nebo "limp".
## Hlava a komora s dost energie zvíře usmrtí (srdce: ještě uběhne 20–60 m), se slabou střelou (šíp) se to jen někdy
## povede, jinak je postřelené do břicha: uteče 200–600 m, zalehne a po 1–3 herních hodinách zhyne. Noha: kulhá, žije.
## Nenaturalisticky: jen pád a ležící zvíře, žádné detaily zranění.
func shot(zone: String, energy: float, from: Vector3, info := {}) -> String:
	if dead:
		return "dead"
	shot_by = info
	shot_by["zone"] = zone
	wound_src = from
	hear_shot(from, 40.0)
	var need := 0.0
	var k := pow(float(spec["mass"]) / 24.0, 0.6)
	match zone:
		"hlava":
			need = KILL_HEAD_J * k
		"srdce_plice":
			need = KILL_HEART_J * k
	if zone == "noha":
		wound = "noha"
		limp_t = LIMP_S
		wound_left = 0.0
		_wound_last = global_position
		_enter("flee")
		return "limp"
	if need > 0.0 and (energy >= need or rng.randf() < energy / need):
		if zone == "hlava":
			die_shot()
			return "dead"
		wound = "srdce"
		wound_left = rng.randf_range(WOUND_RUN_HEART_M[0], WOUND_RUN_HEART_M[1])
	else:
		wound = "bricho"
		wound_left = rng.randf_range(WOUND_RUN_BELLY_M[0], WOUND_RUN_BELLY_M[1])
	wound_lie = false
	_wound_last = global_position
	_enter("flee")
	return "wounded"


## Zvíře padlo po zásahu: zůstane ležet (nezmizí samo) a `Hunting` z něj udělá `Carcass`.
func die_shot(natural := false) -> void:
	if dead:
		return
	shot_by["natural"] = natural       # true = zhynulo samo na následky postřelení (břicho), ne přímým zásahem
	dead = true
	wound = ""
	wound_lie = false
	state = "dead"
	velocity = Vector3.ZERO
	collision_layer = 0
	keep_corpse = true
	_dead_t = 0.0
	if fauna and fauna.world.hunting:
		fauna.world.hunting.on_animal_died(self)


## Mrtvé tělo obnovené z uložené hry (`Hunting.restore`): bez AI, jen ležící model.
func make_corpse() -> void:
	dead = true
	wound = ""
	state = "dead"
	collision_layer = 0
	keep_corpse = true
	_dead_t = 0.0


## Chování postřeleného zvířete (z `_think`). Vrací true, když převzalo řízení (srdce, břicho); noha jen zpomalí běh.
func _wound_think(dt: float) -> bool:
	var pos := global_position
	if _wound_last == Vector3.INF:
		_wound_last = pos
	var moved := pos.distance_to(_wound_last)
	if moved > 0.05 and not wound_lie and (wound != "noha" or limp_t > LIMP_S - 120.0):
		_blood_trail(_wound_last, pos)
	_wound_last = pos
	if wound == "noha":
		limp_t -= dt
		if limp_t <= 0.0:
			wound = ""
			if fauna.world.hunting:
				fauna.world.hunting.on_wound_healed(self)
			return false
		return false
	if wound_lie:
		return _wound_lying(dt)
	wound_left -= moved
	if wound_left <= 0.0:
		if wound == "srdce":
			die_shot()
			return true
		wound_lie = true
		_rise_rolled = false
		wound_die_min = fauna.clock.minutes + rng.randf_range(WOUND_LIE_MIN[0], WOUND_LIE_MIN[1])
		_enter("rest")
		want_speed = 0.0
		return true
	var away := pos - wound_src
	away.y = 0.0
	if away.length() < 0.5:
		away = Vector3(sin(yaw), 0, cos(yaw))
	if state != "flee":
		_enter("flee")
	want_dir = _flee_dir(away.normalized())
	want_speed = float(spec["gaits"]["canter"]) if wound == "srdce" else float(spec["flee_speed"]) * 1.3
	return true


## Zalehlé postřelené zvíře: čeká na smrt, při přiblížení hráče se může zvednout a utéct.
func _wound_lying(_dt: float) -> bool:
	want_speed = 0.0
	if state != "rest":
		_enter("rest")
	if fauna.clock.minutes >= wound_die_min:
		die_shot(true)
		return true
	var p: Player = fauna.world.nearest_player(global_position)
	if p != null:
		var d := fauna.world.player_world_pos(p).distance_to(global_position)
		if d < WOUND_RISE_M and not _rise_rolled:
			_rise_rolled = true
			if _wound_rises < WOUND_RISES_MAX and rng.randf() < WOUND_RISE_P:
				_wound_rises += 1
				wound_lie = false
				wound_left = rng.randf_range(WOUND_RISE_RUN_M[0], WOUND_RISE_RUN_M[1])
				wound_src = fauna.world.player_world_pos(p)
				_enter("flee")
		elif d > WOUND_RISE_M * 2.0:
			_rise_rolled = false
	return true


## Krvavé kapky po trase útěku (mezi dvěma kroky, i když se zvíře ve vzdáleném LOD posunulo o desítky metrů).
func _blood_trail(a: Vector3, b: Vector3) -> void:
	var hunting: Hunting = fauna.world.hunting
	if hunting == null:
		return
	var seg := b - a
	var len_ := seg.length()
	if len_ < 0.01:
		return
	_blood_acc += len_
	while _blood_acc >= BLOOD_STEP_M:
		_blood_acc -= BLOOD_STEP_M
		var t := 1.0 - _blood_acc / len_
		hunting.add_blood(a + seg * clampf(t, 0.0, 1.0))


## Srážka s autem (volá Car): rychlá srážka zvíře usmrtí, pomalá ho odhodí a vyplaší.
func knock(vel: Vector3, spd: float) -> void:
	if dead:
		return
	if spd > 6.0 or float(spec["mass"]) < 10.0 and spd > 3.0:
		dead = true
		state = "dead"
		velocity = vel * clampf(60.0 / float(spec["mass"]), 0.3, 1.5)
		collision_layer = 0
		_dead_t = 0.0
		if herd:
			herd.alarm(global_position, 12.0)
	else:
		velocity = vel
		_enter("flee")
		if herd:
			herd.alarm(global_position - vel.normalized() * 5.0, 10.0)


func _dead_update(delta: float) -> void:
	_dead_t += delta
	if _lod == Lod.FULL:
		velocity.x = move_toward(velocity.x, 0.0, 8.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 8.0 * delta)
		velocity.y -= GRAVITY * delta
		move_and_slide()
	rig.dead = move_toward(rig.dead, 1.0, delta * 3.0)
	rig.speed = 0.0
	rig.animate(delta)
	# mrtvé zvíře po čase zmizí (sebere ho myslivec) – až když ho nikdo nevidí
	if _dead_t > 600.0 and _lod == Lod.FAR and not keep_corpse:
		queue_free()


## Dopad nohy → stopa ve sněhu (jen zvěř v plném detailu; správce stop `World.tracks`).
func _on_footfall(leg: int) -> void:
	if _lod != Lod.FULL or dead:
		return
	var tr: Tracks = fauna.world.tracks
	if tr == null or fauna.weather == null or fauna.weather.snow_cover < Tracks.SNOW_MIN:
		return
	var kind := "deer"
	if species == "divocak" or species == "sele":
		kind = "boar"
	elif species == "zajic":
		if leg != 3:
			return                     # zajíc: jedno „Y“ na skok
		kind = "hare"
	var half := float(spec["length"]) * 0.42
	var side := float(spec["chest"][0]) * 0.6
	var lp := Vector3(side if leg % 2 == 0 else -side, 0.0, half if leg < 2 else -half)
	if kind == "hare":
		lp = Vector3.ZERO
	tr.add(kind, global_position + Basis(Vector3.UP, yaw) * lp, yaw)
