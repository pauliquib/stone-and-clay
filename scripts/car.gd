## Auto: RigidBody3D + vlastní raycastová kola s pružením (Jolt, dřív VehicleWheel3D)
## + model motoru a převodovky.
## - motor: momentová křivka (Nm) podle otáček, omezovač, brzdění motorem
## - automatická převodovka (řazení podle otáček a plynu, prodleva při řazení), zpátečka, prokluz spojky
## - brzdy (impulz na kolo ~ zpomalení 9 m/s²), ruční brzda (zadní kola, menší boční přilnavost → smyk)
## - aerodynamický odpor + valivý odpor, přilnavost podle povrchu (asfalt / štěrk / tráva)
## - počasí (Weather.surface_grip): mokro / sníh / náledí / bahno zmenší přilnavost i brzdy;
##   kapky na čelním skle (interiér), stěrače (klávesa N), zvuk deště na střeše,
##   AI řidič v dešti / mlze / sněhu zpomaluje a drží větší rozestup, v mlze a noci svítí
## - poškození z prudké změny rychlosti (náraz), deformace karoserie, kouř z motoru
## - AI řidič: sleduje trasu (pure pursuit), rychlost podle zatáček, brzdí před překážkou
## - hráč-řidič: ovládání čte z jeho InputState (lokálně klávesnice, v MP síť); kameru má auto,
##   jen když řídí lokální hráč
## - jednostopá vozidla (kolo, motorka – model.kind "bike" / "moto"): fyzikálně 4 paprsková kola na úzkém
##   rozchodu + stabilizace náklonu, vizuálně 2 kola uprostřed, náklon do zatáčky, natáčená vidlice,
##   kolo: šlapání (síla do max. rychlosti, bez motoru a brzdění motorem), zvonek místo klaksonu
class_name Car
extends RigidBody3D

## Raycastové kolo (náhrada VehicleWheel3D pro Jolt): paprsek z uchycení nápravy po ose
## podvozku (−Y auta), pružina + tlumič tlačí po normále terénu, pneumatika přenáší
## podélnou (motor/brzda) a boční (proti smyku) sílu omezenou přilnavostí × zatížením.
class Wheel extends RayCast3D:
	var attach := Vector3.ZERO        # lokální uchycení nápravy (= position uzlu)
	var front := false                # řízené kolo (dřív use_as_steering)
	var traction := false             # poháněné kolo (dřív use_as_traction)
	var radius := 0.3                 # poloměr kola (m)
	var rest := 0.16                  # klidová délka pružení attach→střed kola = max. vypružení (m)
	var travel := 0.3                 # zdvih pružení směrem nahoru – mez stlačení (m)
	var stiff := 35000.0              # tuhost pružiny (N/m)
	var damp := 4500.0                # tlumení (N·s/m)
	var engine_force := 0.0           # požadovaná tažná síla (N) – nastavuje _powertrain
	var brake := 0.0                  # požadovaná brzdná síla (N) – nastavuje _powertrain
	var grip := 1.0                   # aktuální µ = povrch × pneu (dřív wheel_friction_slip)
	var load := 0.0                   # normálové zatížení z posledního kroku (N)
	var skid := 1.0                   # 1 = žádný smyk, → 0 = plný smyk (náhrada get_skidinfo)
	var spin := 0.0                   # úhel odvalení pro vizuál kola (rad)
	var v_lon := 0.0                  # podélná rychlost v místě kola (m/s)
	var v_lat := 0.0                  # boční rychlost v místě kola (m/s, diagnostika smyku)
	var sus_len := 0.0                # aktuální délka pružení attach→střed (m)
	var contact_body: Object = null   # collider pod kolem (pro _surface_grip)

	func is_in_contact() -> bool:
		return is_colliding()


signal crashed(impact: float, what: String, other: Object)
signal hit_person(who: Node, speed: float)

enum Drive { NONE, PLAYER, AI }

const IDLE_RPM := 800.0
## Stěrače: úhel od dolního okraje skla (rad kolem normály skla), rozsah stírání, rychlost.
const WIPER_PARK := 1.15                # parkovací úhel ramena (rad kolem normály skla; rameno leží při spodku skla)
const WIPER_SWEEP := -1.6               # rozsah stírání (rad, záporný = nahoru do kopce skla)
const WIPER_LEN := 0.56                 # délka ramena i s gumičkou (m)
const WIPER_X := [0.55, 0.0]            # x os stěračů (řidič, spolujezdec)
const WIPER_SPEED := 4.2                # rad/s (≈ cyklus tam a zpět za 3 s)
const AI_SLOW := 0.45                   # AI řidič v plném dešti / mlze / sněhu zpomalí na ~55 %
const AI_GAP := 0.8                     # a drží ~o tolik delší rozestup
const AI_SHARP := 0.7                   # lom trasy větší než ~40° = ostrá zatáčka (AI zpomalí, míří na roh, ne za něj)
const ROOF_DB_IN := -7.0                # déšť na střeše uvnitř auta
const ROOF_DB_OUT := -24.0              # vnější tlumený

var model_id := "octavia"
var paint := Color(0.7, 0.1, 0.1)
var is_police := false
var plate := ""
var model: CarModel
var drive := Drive.NONE
var body_state: BodyState          # stav řidiče (hráče) pro opilé řízení
var driver_id := 0                 # id hráče za volantem (0 = nikdo / AI)
var driver_input: InputState       # vstup hráče za volantem
var damage := 0.0                  # 0..100 %
var lights_on := false
var siren := false
var owner_id := 0                  # id hráče, kterému auto patří (0 = nikomu)
var input_locked := false          # řidič "vypnutý" (okno)
var police_hold := false           # stojí u policejní kontroly (brzda, ruční brzda)
var weather: Weather               # přiřazuje Traffic.make_car – mokro/sníh/náledí do přilnavosti
var clock: Clock                   # AI svítí v noci
var wipers_on := false             # stěrače (hráč přepíná klávesou N → World.player_action)

var rpm := IDLE_RPM
var gear := 1                      # -1 zpátečka, 1..n
var throttle := 0.0
var brake_in := 0.0
var steer_in := 0.0
var handbrake := false
var speed := 0.0                   # m/s podél osy vozu
var cam_mode := 0                  # 0 za autem, 1 z interiéru

# AI
var ai_path := PackedVector3Array()
var ai_i := 0
var ai_speed_limit := 13.9
var ai_target_speed := 0.0
var ai_direct_target := Vector3.INF   # přímé pronásledování (policie)
var ai_stop := false
var ai_blocked := 0.0                 # jak dlouho stojí kvůli překážce v pruhu (s)
var ai_blocker: Object = null          # co ho blokuje (auto, člověk, pes, bedna)
var _ai_stuck := 0.0
var _ai_reverse := 0.0
var _ai_offset := 0.0                  # boční posun od pruhu doleva (objíždění stojící překážky)
var _ai_pass_until := -1               # index bodu trasy, kde objíždění končí
var _ai_yield_ignore := 0.0            # vzájemné zablokování na křižovatce → jedno auto projede
var _ai_obst_t := 0.0
var _ai_obst := {}

var steering := 0.0               # úhel natočení řízených kol (rad, + = doleva) – dřív na VehicleBody3D
var vis: Node3D
var wheels: Array[Wheel] = []
var _wheel_vis: Array[MeshInstance3D] = []
var _prev_xf := Transform3D()
var _cur_xf := Transform3D()
var _wheel_attach: Array[Vector3] = []
var _prev_wxf: Array[Transform3D] = []
var _cur_wxf: Array[Transform3D] = []
var _prev_vel := Vector3.ZERO
var _shift_t := 0.0
var _crash_cool := 0.0
var _person_cool := {}
var _engine: AudioStreamPlayer3D
var _skid: AudioStreamPlayer3D
var _siren_snd: AudioStreamPlayer3D
var _horn: AudioStreamPlayer3D
var _head_l: SpotLight3D
var _head_r: SpotLight3D
var _beacon_l: OmniLight3D
var _beacon_r: OmniLight3D
var _beacon_mat_b: StandardMaterial3D
var _beacon_mat_r: StandardMaterial3D
var _smoke: CPUParticles3D
var _input_buf: Array = []         # zpožděné vstupy opilého řidiče
var _drunk_noise := FastNoiseLite.new()
var _t := 0.0
var _microsleep := 0.0
var _microsleep_cool := 3.0
var _flip_t := 0.0
var _driven_front := true
var _cam_rig: Node3D
var _cam: Camera3D
var _cam_yaw := 0.0
var _cam_pitch := -0.18
var _cam_idle := 0.0
var _cam_pos := Vector3.ZERO
var seat_pos := Vector3(0.38, 0.15, 0.0)
var two_wheeler := false           # kolo / motorka
# M1.6 – vlastnictví z bazaru (0 = základní vozidlo rodiny) a přívěs na tažném zařízení (M2.10)
var bazaar_price := 0              # cena, za kterou hráč vozidlo koupil (základ pro výkup 60 %)
var bazaar_year := 0               # rok výroby konkrétního kusu (z nabídky bazaru)
var trailer: PhysicsBody3D = null  # připojený přívěs / vozík (attach_trailer)
var cargo_kg := 0.0                # naložený náklad (kg) – `Cargo` ho nastavuje přes `set_cargo_kg`, zvyšuje `mass` (M2.10)
var _mass0 := 0.0                  # hmotnost prázdného vozidla
var _trailer_joint: PinJoint3D = null
var pedal_angle := 0.0             # natočení klik (kolo) – čte ho postava jezdce
var lean := 0.0                    # vizuální náklon jednostopého vozidla (rad kolem podélné osy, − = doleva)
var _roll := 0.0                   # fyzikální náklon tělesa (rad, + = vpravo) – jen lean-steer motorky
var _si_prev := 0.0                # minulý vstup řízení (derivace pro protizatáčení)
var _asleep := false               # fyzika auta uspaná (set_asleep – kolize zůstává aktivní)
var kinematic := false             # uspané AI auto posouvá Traffic po trase bez fyziky
var _fork: MeshInstance3D
var _crank: MeshInstance3D
var _wipers: Array[Node3D] = []    # osy stěračů pod čelním sklem (levý řidič, pravý)
var _wiper_basis := Basis()        # orientace roviny skla (Y = normála, Z = do kopce skla)
var _wangle := 0.0                 # aktuální úhel stěračů
var _wphase := 0.0
var _glass_drops: GPUParticles3D   # kapky na čelním skle (vidět z interiéru)
var _rain_roof: AudioStreamPlayer3D

## Pružení kol v SI jednotkách (spec["susp"] z modelu je relativní násobek).
@export var suspension_stiffness := 35000.0   # N/m za kolo (při susp = 26)
@export var suspension_damping := 5200.0      # N·s/m za kolo (při susp = 26)


func setup(id: String, color: Color, police := false, plate_text := "") -> void:
	model_id = id
	paint = color
	is_police = police
	plate = plate_text


func _ready() -> void:
	model = CarModel.new(model_id, paint, is_police, plate)
	var mesh := model.build()
	var spec := model.spec
	seat_pos = model.seat
	two_wheeler = model.kind != "car"
	mass = spec["mass"]
	# projekt má gravitaci 20 m/s² (kvůli pocitu z chůze) – auta jezdí s reálnou 9,81 m/s²
	gravity_scale = 9.81 / float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.81))
	collision_layer = 16
	collision_mask = 1 | 2 | 4 | 8 | 16
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0, spec.get("com_y", 0.62 if spec.get("boxy", false) else 0.48), 0.05 if not two_wheeler else 0.0)
	contact_monitor = true
	max_contacts_reported = 6
	continuous_cd = true                 # Jolt: auto v rychlosti neprostřelí zeď/terén
	can_sleep = false
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	linear_damp = 0.0
	angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	angular_damp = 0.4
	_driven_front = spec.get("fwd", model_id in ["octavia", "fabia"])
	var pm := PhysicsMaterial.new()
	pm.friction = 0.4
	pm.bounce = 0.05
	physics_material_override = pm
	var hull := ConvexPolygonShape3D.new()
	hull.points = model.hull_points
	var cs := CollisionShape3D.new()
	cs.shape = hull
	add_child(cs)
	# vizuál (interpolovaný mezi fyzikálními kroky)
	vis = Node3D.new()
	vis.top_level = true
	add_child(vis)
	var bmi := MeshInstance3D.new()
	bmi.mesh = mesh
	vis.add_child(bmi)
	if model.scene_root:
		vis.add_child(model.scene_root)
	_plates()
	var wr: float = spec["wheel_r"]
	var rest := 0.16
	var wpos := model.wheel_positions()
	var wmesh_l: Mesh = CarModel.wheel_mesh(wr, 1.0) if not two_wheeler else BikeModel.wheel_mesh(wr, float(spec.get("tire_w", 0.045 if model.kind == "bike" else 0.1)), model.kind == "moto")
	var wmesh_r: Mesh = CarModel.wheel_mesh(wr, -1.0) if not two_wheeler else wmesh_l
	if spec.has("wheel_scene"):
		wmesh_l = CarModel.first_mesh(spec["wheel_scene"])
		wmesh_r = wmesh_l
	var single_track := two_wheeler and float(spec.get("lean_max", 0.0)) > 0.0   # dvě kola v ose
	# spec["susp"] (~20–42) = relativní tuhost podle modelu; výchozí auto 26 → exportní default
	var susp_scale := float(spec.get("susp", 30.0 if spec.get("boxy", false) else 26.0)) / 26.0
	for i in wpos.size():
		var w := Wheel.new()
		var p: Vector3 = wpos[i]
		w.position = Vector3(p.x, wr + rest - 0.09, p.z)
		w.attach = w.position
		w.radius = wr
		w.rest = rest
		w.travel = 0.45                                  # doraz/droop – kolo dokáže sledovat prohlubně terénu
		w.target_position = Vector3(0.0, -(rest + w.travel + wr), 0.0)  # paprsek sahá až po plně vypružené kolo (jako VehicleWheel3D)
		w.collision_mask = collision_mask
		w.exclude_parent = true
		# single-track (2 kola v ose): každé kolo nese polovinu hmotnosti → dvojnásobná tuhost pružení,
		# jinak se podvozek propadne k zemi
		w.stiff = suspension_stiffness * susp_scale * (2.0 if single_track else 1.0)
		w.damp = suspension_damping * susp_scale * (1.4 if single_track else 1.0)
		w.sus_len = rest                                   # start na klidové délce
		var front := p.z > 0.0
		w.front = front
		w.traction = front == _driven_front
		add_child(w)
		wheels.append(w)
		_wheel_attach.append(w.position)
		var wm := MeshInstance3D.new()
		wm.mesh = wmesh_l if p.x > 0.0 else wmesh_r
		wm.top_level = true
		wm.visible = not two_wheeler or single_track or p.x > 0.0     # jednostopé na 4 paprscích: jen levá (doprostřed)
		add_child(wm)
		_wheel_vis.append(wm)
		_prev_wxf.append(Transform3D())
		_cur_wxf.append(Transform3D())
	# světla
	var hz: float = spec["head_z"]
	var hy: float = spec["head_y"]
	for s in ([-1.0, 1.0] if not two_wheeler else [0.0]):
		var sl := SpotLight3D.new()
		sl.position = Vector3(s * 0.6, hy, hz + 0.1)
		sl.rotation = Vector3(-0.06, PI, 0)
		sl.spot_range = 45.0
		sl.spot_angle = 32.0
		sl.spot_attenuation = 0.6
		sl.light_energy = 3.0
		sl.light_color = Color(1.0, 0.96, 0.85)
		sl.shadow_enabled = false
		sl.distance_fade_enabled = true
		sl.distance_fade_begin = 120.0
		sl.visible = false
		vis.add_child(sl)
		if s < 0:
			_head_r = sl
		else:
			_head_l = sl
			if two_wheeler:
				_head_r = sl
				sl.spot_range = 30.0 if model.kind == "bike" else 40.0
				sl.light_energy = 1.2 if model.kind == "bike" else 2.2
	if model.fork_mesh:
		_fork = MeshInstance3D.new()
		_fork.mesh = model.fork_mesh
		_fork.position = model.fork_pivot
		vis.add_child(_fork)
	if model.crank_mesh:
		_crank = MeshInstance3D.new()
		_crank.mesh = model.crank_mesh
		_crank.position = model.crank_pivot
		vis.add_child(_crank)
	if is_police:
		_build_beacons()
	if model.kind == "car":
		_build_wipers()
		_build_glass_drops()
		# tlumený zvuk deště na střeše (uvnitř auta) – samostatný kanál na hranici zorného pole kamery
		_rain_roof = _snd(NatureSfx.get_stream("rain"), -80.0, 18.0)
		_rain_roof.attenuation_filter_cutoff_hz = 2400.0
		_rain_roof.pitch_scale = 0.92
		_rain_roof.position = Vector3(0, model.height - 0.05, 0)   # pod stropem kabiny
	# zvuky
	_engine = _snd(Sfx.engine_loop(), -6.0, 60.0)
	if model.kind != "bike":
		_engine.play()
	_skid = _snd(Sfx.skid_loop(), -80.0, 40.0)
	_skid.play()
	_horn = _snd(Sfx.horn() if model.kind != "bike" else Sfx.bell(), 0.0 if model.kind == "car" else -4.0, 120.0)
	if model.kind == "moto":
		_horn.pitch_scale = 1.35
	if is_police:
		_siren_snd = _snd(Sfx.siren_loop(), 2.0, 350.0)
	_smoke = _make_smoke()
	vis.add_child(_smoke)
	_smoke.position = Vector3(0, 0.95, hz - 0.5) if not two_wheeler else Vector3(0, 0.6, 0.1)
	_drunk_noise.frequency = 0.6
	_drunk_noise.seed = randi()
	_cur_xf = global_transform
	_prev_xf = _cur_xf
	vis.global_transform = _cur_xf


func _snd(stream: AudioStream, vol: float, dist: float) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.stream = stream
	p.volume_db = vol
	p.max_distance = dist
	p.unit_size = 6.0
	p.attenuation_filter_cutoff_hz = 8000.0
	add_child(p)
	return p


func _plates() -> void:
	if two_wheeler:
		if model.plate_pos != Vector3.INF:     # motorka: jen zadní SPZ na blatníku
			var lp := Label3D.new()
			lp.text = plate.replace(" ", "\n")
			lp.font_size = 40
			lp.pixel_size = 0.0018
			lp.modulate = Color(0.05, 0.05, 0.05)
			lp.outline_size = 0
			lp.position = model.plate_pos
			lp.rotation = Vector3(0.2, PI, 0)
			lp.double_sided = false
			lp.visibility_range_end = 25.0
			vis.add_child(lp)
		return
	if not model.spec.has("keys"):
		return             # vlastní model: SPZ si namodeluj přímo do karoserie
	var keys: Array = model.spec["keys"]
	var zf: float = keys[keys.size() - 1][0]
	var zr: float = keys[0][0]
	var gy: float = model._key_at(zf - 0.06)[1] + 0.06
	var ry: float = model.spec["tail_y"] - 0.3
	for d in [[Vector3(0.02, gy, zf + 0.013), 0.0], [Vector3(0.02, ry, zr - 0.02), PI]]:
		var l := Label3D.new()
		l.text = plate
		l.font_size = 44
		l.pixel_size = 0.0022
		l.modulate = Color(0.05, 0.05, 0.05)
		l.outline_size = 0
		l.position = d[0]
		l.rotation.y = d[1]
		l.double_sided = false
		l.visibility_range_end = 30.0
		vis.add_child(l)
	if is_police:
		for s in [-1.0, 1.0]:
			var l := Label3D.new()
			l.text = "POLICIE"
			l.font_size = 64
			l.pixel_size = 0.0045
			l.modulate = Color(0.08, 0.2, 0.6)
			l.outline_size = 0
			var k := model._key_at(-0.4)
			l.position = Vector3(s * (k[5] + 0.025), (k[1] + k[2]) * 0.5 + 0.05, -0.4)
			l.rotation.y = PI / 2 * s
			l.double_sided = false
			l.visibility_range_end = 60.0
			vis.add_child(l)
			# žluto-zelený pruh
			var stripe := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(0.01, 0.1, model.length * 0.92)
			stripe.mesh = bm
			var sm := StandardMaterial3D.new()
			sm.albedo_color = Color(0.8, 0.95, 0.1)
			sm.emission_enabled = true
			sm.emission = Color(0.5, 0.6, 0.05)
			sm.emission_energy_multiplier = 0.3
			stripe.material_override = sm
			var km := model._key_at(0.0)
			stripe.position = Vector3(s * (km[5] + 0.005), km[1] + 0.2, -0.1)
			vis.add_child(stripe)


func _build_beacons() -> void:
	var h := model.height
	for i in 2:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.45, 0.1, 0.2)
		mi.mesh = bm
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.1, 0.2, 1.0) if i == 0 else Color(1.0, 0.1, 0.1)
		m.emission_enabled = true
		m.emission = m.albedo_color
		m.emission_energy_multiplier = 0.2
		mi.material_override = m
		mi.position = Vector3(0.28 if i == 0 else -0.28, h + 0.1, -0.3)
		vis.add_child(mi)
		var ol := OmniLight3D.new()
		ol.light_color = m.albedo_color
		ol.omni_range = 14.0
		ol.light_energy = 0.0
		ol.position = mi.position + Vector3(0, 0.2, 0)
		ol.distance_fade_enabled = true
		ol.distance_fade_begin = 150.0
		vis.add_child(ol)
		if i == 0:
			_beacon_mat_b = m
			_beacon_l = ol
		else:
			_beacon_mat_r = m
			_beacon_r = ol


## Stěrače u čelního skla: dvě otočné osy pod dolním okrajem skla, rameno + gumička ve směru stírání.
## Přímkový model (spec["keys"]) → rovina skla z klíčů; u vlastního modelu se nestaví.
func _build_wipers() -> void:
	if not model.spec.has("keys"):
		return
	var keys: Array = model.spec["keys"]
	var kt: Array = []
	var kb: Array = []
	for k in keys:
		if int(k[8]) == 2 and k[0] > 0.2:      # zóna 2 = čelní sklo (klíč: [z, …, skleník, zóna])
			if kt.is_empty() or k[0] < kt[0]:
				kt = k
			if kb.is_empty() or k[0] > kb[0]:
				kb = k
	if kt.is_empty() or kb.is_empty() or kb[0] <= kt[0]:
		return
	var zt: float = kt[0] + 0.04
	var zb: float = kb[0] - 0.04
	var yt: float = kt[3] - 0.08
	var yb: float = kb[2] + 0.04
	var gup := Vector3(0, yt - yb, zt - zb).normalized()       # do kopce skla (nahoru + dozadu)
	var norm := Vector3.RIGHT.cross(gup).normalized()        # normála skla (ven z auta: nahoru a dopředu)
	_wiper_basis = Basis(norm.cross(gup), norm, gup)         # pravotočivá báze: X, Y = normála, Z = do kopce skla
	var kit := MeshKit.new()
	var dark := Color(0.05, 0.05, 0.06)
	var at_y := Vector3(0.0, 0.025, 0.0)                     # v lokálních osách stěrače: kousek nad sklem (Y = normála)
	# osa stěrače
	kit.box(Vector3(0.0, 0.0, -0.015) + at_y * 1.3, Vector3(0.03, 0.03, 0.03), dark)
	# rameno po rovině skla
	kit.box(Vector3(0.0, 0.005, WIPER_LEN * 0.28) + at_y, Vector3(0.012, 0.012, WIPER_LEN * 0.56), dark)
	# gumička v prodloužení ramena (čmárá se po skle)
	kit.box(Vector3(0.0, 0.012, WIPER_LEN * 0.64) + at_y, Vector3(0.03, 0.02, WIPER_LEN * 0.72), dark)
	var mesh := kit.commit()
	var mat := MeshKit.vc_material(0.7)
	for sx in WIPER_X:
		var pivot := Node3D.new()
		pivot.position = Vector3(sx, yb, zb)
		pivot.basis = _wiper_basis * Basis(Vector3.UP, WIPER_PARK)
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		pivot.add_child(mi)
		vis.add_child(pivot)
		_wipers.append(pivot)


## Kapky na čelním skle – tenká emisní rovina natočená jako sklo; kapky kloužou dolů po skle.
func _build_glass_drops() -> void:
	if _wipers.is_empty():
		return
	var center := Vector3.ZERO
	for w in _wipers:
		center += w.position
	center /= _wipers.size()
	center.x = 0.0                                             # střed skla napříč
	center += _wiper_basis * Vector3(0.0, 0.0, 0.38)           # doprostřed skla nad osami
	var p := GPUParticles3D.new()
	p.transform = Transform3D(_wiper_basis, center)
	p.amount = 120
	p.lifetime = 7.0
	p.local_coords = true
	p.visibility_aabb = AABB(Vector3(-1.0, -0.6, -1.0), Vector3(2.0, 1.2, 2.0))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(0.66, 0.02, 0.4)
	pm.direction = Vector3(0, 0, -1)
	pm.spread = 12.0
	pm.initial_velocity_min = 0.01
	pm.initial_velocity_max = 0.05
	pm.gravity = Vector3(0, 0, -0.09)                          # sklouzávání dolů po skle (lokální -Z)
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.022, 0.022)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.82, 0.88, 0.95, 0.38)
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	q.material = m
	p.draw_pass_1 = q
	p.emitting = false
	vis.add_child(p)
	_glass_drops = p


## Stěrače zapnuto / vypnuto (hráč: klávesa N přes World.player_action).
func toggle_wipers() -> void:
	wipers_on = not wipers_on
	if wipers_on and absf(_wangle) <= 0.001:
		_wphase = 0.0


func _make_smoke() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = 40
	p.lifetime = 2.5
	p.emitting = false
	p.direction = Vector3(0, 1, 0)
	p.spread = 20.0
	p.initial_velocity_min = 0.6
	p.initial_velocity_max = 1.3
	p.gravity = Vector3(0, 0.4, 0)
	p.scale_amount_min = 1.0
	p.scale_amount_max = 2.2
	var grad := Gradient.new()
	grad.set_color(0, Color(0.2, 0.2, 0.2, 0.6))
	grad.set_color(1, Color(0.3, 0.3, 0.3, 0.0))
	p.color_ramp = grad
	var q := QuadMesh.new()
	q.size = Vector2(0.4, 0.4)
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	q.material = m
	p.mesh = q
	return p


# ------------------------------------------------------------------ ovládání

## Uspaní auta podle vzdálenosti od hráčů (výkon na velké mapě): rigid body zamrzne (kolize zůstává
## aktivní – do auta jde nabořit i nastoupit), raycastová kola, _process ani zvuky už neběží.
## kin=true jen pro AI: auto zůstane viditelné a Traffic ho posouvá po trase voláním kinematic_step.
func set_asleep(on: bool, kin := false) -> void:
	if _asleep == on and (not on or kinematic == kin):
		return
	_asleep = on
	kinematic = kin
	if on:
		freeze = true
		set_physics_process(false)
		set_process(false)
		_engine.volume_db = -80.0
		_skid.volume_db = -80.0
		if _rain_roof:
			_rain_roof.stop()
	else:
		freeze = false
		set_process(true)
		set_physics_process(true)
		linear_velocity = Vector3.ZERO
		angular_velocity = Vector3.ZERO
		_prev_vel = Vector3.ZERO
		_cur_xf = global_transform
		_prev_xf = _cur_xf
		vis.global_transform = _cur_xf


## Kinematický posun AI auta po trase pro vzdálená auta (fyzika vypnutá – volá Traffic každý krok).
func kinematic_step(dt: float) -> void:
	if ai_path.size() < 2 or ai_i >= ai_path.size():
		speed = 0.0
		return
	var pos := global_position
	while ai_i < ai_path.size() - 1 and Vector2(ai_path[ai_i].x - pos.x, ai_path[ai_i].z - pos.z).length() < 7.0:
		ai_i += 1
	var tgt := ai_path[ai_i]
	var dx := tgt.x - pos.x
	var dz := tgt.z - pos.z
	var dist := Vector2(dx, dz).length()
	if dist < 0.4:
		speed = 0.0
		return
	speed = minf(ai_speed_limit, dist * 0.5 + 2.0)
	var dir := Vector3(dx / dist, 0.0, dz / dist)
	var np := pos + dir * minf(dist, speed * dt)
	np.y = lerpf(pos.y, tgt.y, minf(dt * 5.0, 1.0))
	var xf := Transform3D(Basis.looking_at(-dir, Vector3.UP).orthonormalized(), np)
	global_transform = xf
	_prev_xf = xf
	_cur_xf = xf
	vis.global_transform = xf
	_t += dt


func set_player_driver(p: Player) -> void:
	set_asleep(false)
	drive = Drive.PLAYER
	body_state = p.body
	driver_id = p.id
	driver_input = p.input
	sleeping = false
	_input_buf.clear()
	if p.camera == null:
		return       # řídí vzdálený hráč – kameru auto nepotřebuje
	_cam_rig = Node3D.new()
	_cam_rig.top_level = true
	add_child(_cam_rig)
	_cam = Camera3D.new()
	_cam.fov = 70.0
	_cam.near = 0.05
	_cam.far = 9000.0
	_cam_rig.add_child(_cam)
	_cam.current = true
	_cam_pos = global_transform * Vector3(0, 2.2, -6.5)
	_cam_yaw = 0.0


func clear_driver() -> void:
	drive = Drive.NONE
	throttle = 0.0
	steer_in = 0.0
	brake_in = 0.0
	handbrake = true
	wipers_on = false
	body_state = null
	driver_id = 0
	driver_input = null
	if _cam_rig:
		_cam_rig.queue_free()
		_cam_rig = null
		_cam = null


func camera() -> Camera3D:
	return _cam


func set_ai_route(points: PackedVector3Array, limit_ms := 13.9) -> void:
	set_asleep(false)
	drive = Drive.AI
	ai_path = points
	ai_i = 0
	ai_speed_limit = limit_ms
	ai_direct_target = Vector3.INF
	sleeping = false


func toggle_lights() -> void:
	lights_on = not lights_on
	_head_l.visible = lights_on
	_head_r.visible = lights_on
	model.head_mat.emission_energy_multiplier = 3.0 if lights_on else 0.3


func honk() -> void:
	if not _horn.playing:
		_horn.play()


func set_siren(on: bool) -> void:
	siren = on
	if _siren_snd:
		if on and not _siren_snd.playing:
			_siren_snd.play()
		elif not on:
			_siren_snd.stop()


# ------------------------------------------------------------------ kufr, ložná plocha, tažné zařízení (M1.6 → M2.10)

## Objem kufru v litrech (0 = vozidlo kufr nemá – motorky, traktor, pickup má ložnou plochu `cargo_bed`).
func trunk_liters() -> int:
	return int(model.spec.get("kufr_l", 0))


## Poloha kufru / zadních dveří ve světě (místo, kam se dává a odkud se bere náklad).
func trunk_point() -> Vector3:
	return global_transform * Vector3(0, 0.6, float(model.spec.get("tail_z", -model.length * 0.5)) - 0.35)


## Motorka / skútr / moped má zadní nosič (upevnění nákladu)?
func has_rack() -> bool:
	return bool(model.spec.get("nosic", false))


## Ložná plocha pickupu: {"c": střed podlahy (lokálně), "size": Vector3 šířka × výška × délka, "xf": Transform3D podlahy ve světě}.
## Prázdný slovník = vozidlo ložnou plochu nemá.
func cargo_bed() -> Dictionary:
	if not model.spec.has("bed"):
		return {}
	var bd: Dictionary = model.spec["bed"]
	return {"c": bd["c"], "size": bd["size"], "xf": global_transform * Transform3D(Basis.IDENTITY, bd["c"])}


## Náklad v kufru / na ložné ploše / na nosiči (M2.10): zvýší hmotnost (delší brzdná dráha), u jednostopého vozidla
## posune těžiště dozadu a zhorší stabilizaci (`_balance`). Volá `Cargo` po každé změně nákladu.
func set_cargo_kg(kg: float) -> void:
	if _mass0 <= 0.0:
		_mass0 = mass
	cargo_kg = maxf(kg, 0.0)
	mass = _mass0 + cargo_kg
	if two_wheeler:
		center_of_mass = Vector3(0, float(model.spec.get("com_y", 0.48)), -clampf(cargo_kg / 25.0, 0.0, 1.5) * 0.12)


## Nosnost tažného zařízení (kg); 0 = vozidlo netáhne nic.
func tow_limit_kg() -> int:
	return int(model.spec.get("tazne_kg", 0))


## Poloha tažného zařízení ve světě (koule / oj) – k ní se připojuje oj přívěsu. Vector3.INF = bez háku.
func hitch_point() -> Vector3:
	if not model.spec.has("hitch"):
		return Vector3.INF
	return global_transform * (model.spec["hitch"] as Vector3)


## Připojí přívěs / vozík (tělo s vlastní fyzikou, jeho oj má být u `hitch_point()`): kloubový spoj ve svislé ose.
## Vrací false, když vozidlo nemá hák, je už něco připojeno nebo přívěs váží víc než `tow_limit_kg()`.
func attach_trailer(body: PhysicsBody3D, trailer_mass_kg := 0.0) -> bool:
	if trailer != null or not model.spec.has("hitch") or (trailer_mass_kg > float(tow_limit_kg())):
		return false
	trailer = body
	_trailer_joint = PinJoint3D.new()
	add_child(_trailer_joint)
	_trailer_joint.global_position = hitch_point()
	_trailer_joint.node_a = get_path()
	_trailer_joint.node_b = body.get_path()
	return true


func detach_trailer() -> void:
	if _trailer_joint != null and is_instance_valid(_trailer_joint):
		_trailer_joint.queue_free()
	_trailer_joint = null
	trailer = null


func reset_upright() -> void:
	set_asleep(false)
	var fwd := global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 0.1 else Vector3.FORWARD
	var pos := global_position + Vector3(0, 1.2, 0)
	global_transform = Transform3D(Basis.looking_at(-fwd, Vector3.UP), pos)
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	_prev_vel = Vector3.ZERO


func repair() -> void:
	damage = 0.0
	model.repair()
	_smoke.emitting = false


func driver_door_world() -> Vector3:
	if two_wheeler:
		return global_transform * Vector3(model.half_width + 0.6, 0.2, seat_pos.z)
	return global_transform * Vector3(model.half_width + 0.9, 0.2, 0.2)


# ------------------------------------------------------------------ fyzika

func _physics_process(delta: float) -> void:
	var __t0 := Tests.prof_t0()
	_physics_impl(delta)
	Tests.prof_add("car", __t0)


func _physics_impl(delta) -> void:
	_t += delta
	var fwd := global_transform.basis.z
	speed = linear_velocity.dot(fwd)
	match drive:
		Drive.PLAYER:
			_player_input(delta)
		Drive.AI:
			_ai_drive(delta)
		_:
			throttle = 0.0
			brake_in = 0.0
			handbrake = true
	_powertrain(delta)
	_wheels(delta)
	# odpor vzduchu a valivý odpor
	var v := linear_velocity
	var vl := v.length()
	if vl > 0.1:
		var drag: float = model.spec["drag"]
		apply_central_force(-v * vl * drag - v.normalized() * mass * 9.81 * 0.012 * minf(vl, 1.0))
	# zvuk
	var pitch := clampf(rpm / 60.0 * 2.0 / 42.0, 0.45, 4.5)
	_engine.pitch_scale = lerpf(_engine.pitch_scale, pitch * float(model.spec.get("snd_pitch", 1.0)), 0.3)
	_engine.volume_db = lerpf(-14.0, -3.0, throttle) if damage < 100.0 else -80.0
	var skid := 0.0
	for w in wheels:
		if w.is_in_contact():
			skid = maxf(skid, 1.0 - w.skid)
	_skid.volume_db = lerpf(-60.0, -4.0, clampf(skid * 1.6 - 0.2, 0.0, 1.0)) if absf(speed) > 3.0 else -80.0
	# déšť na střeše: uvnitř kabiny jiný zvuk než venku
	if _rain_roof:
		var rr := weather.rain if (weather != null and weather.is_raining()) else 0.0
		var tgt := -80.0
		if rr > 0.04:
			tgt = (ROOF_DB_IN if (drive == Drive.PLAYER and cam_mode == 1) else ROOF_DB_OUT) - (1.0 - rr) * 8.0
		if tgt > -70.0 and not _rain_roof.playing:
			_rain_roof.play()
		_rain_roof.volume_db = move_toward(_rain_roof.volume_db, tgt, delta * 20.0)
		if rr <= 0.04 and _rain_roof.volume_db <= -69.0:
			_rain_roof.stop()
	if two_wheeler:
		_balance(delta)
	_detect_crash(delta)
	_detect_people()
	# převrácené auto
	if global_transform.basis.y.y < 0.3 and linear_velocity.length() < 1.0:
		_flip_t += delta
		if _flip_t > 4.0 and drive != Drive.PLAYER:
			reset_upright()
			_flip_t = 0.0
	else:
		_flip_t = 0.0
	_prev_xf = _cur_xf
	_cur_xf = global_transform
	_update_wheel_visuals()
	if siren or (is_police and ai_direct_target != Vector3.INF):
		_beacons()


## Jednostopé vozidlo: drží se ve svislé poloze (stabilizační moment kolem podélné osy, jako by jezdec
## vyvažoval), vizuální náklon do zatáčky podle bočního zrychlení; zaparkované stojí nakloněné na stojánku.
## Modely se `lean_max` jedou na reálné jednostopé fyzice (2 kola v ose, náklon je fyzikální – těleso se
## opravdu překlápí): vstup řízení nastavuje cílový náklon omezený přilnavostí (atan(mu)), samovyvažování
## eskaluje s rychlostí (gyroskopický efekt kol), zatáčení vzniká kombinací svodu řízení (přední kolo se
## samo skládá do náklonu, `lean_steer`), protizatáčení při náhlém vstupu (`countersteer`) a camber thrust
## yaw momentu mířícího na rovnovážnou zatáčku g·tan(roll)/v (`lean_yaw`). Přenos zatížení při brzdě/plynu
## mění grip kol v `_powertrain`.
func _balance(delta: float) -> void:
	var fwd := global_transform.basis.z
	var spec := model.spec
	var lean_max := float(spec.get("lean_max", 0.0))
	if lean_max > 0.0:
		# --- reálná jednostopá fyzika: motorka má jen dvě kola v ose, náklon je fyzikální ---
		var hf := fwd - Vector3.UP * fwd.y                      # dopředu promítnuté do vodorovné roviny
		hf = hf.normalized() if hf.length() > 0.05 else fwd
		_roll = -asin(clampf(global_transform.basis.y.cross(Vector3.UP).dot(hf), -1.0, 1.0))   # + = náklon vpravo
		var w_roll := angular_velocity.dot(hf)
		# samovyvažování = gyroskopický efekt kol: roste s rychlostí, u stání zůstává ~polovina
		var stab := 1.0 - clampf(cargo_kg / 60.0, 0.0, 0.4)          # náklad na nosiči: horší stabilizace
		stab *= float(spec.get("stab", 1.0))
		var gyro := lerpf(0.45, 1.0, clampf(absf(speed) / 14.0, 0.0, 1.0))
		if drive == Drive.NONE and absf(speed) < 0.5:
			gyro = 2.2                                   # zaparkovaná: stojánek + ztuhlý rám, stojí pevně
		stab *= gyro
		# cílový náklon: vstup řízení → náklon (point-and-lean), autorská mez přilnavosti atan(mu),
		# aby se na ledu/šotolině motorka nenakláněla víc, než pneu unesou
		var auth := clampf((absf(speed) - 2.5) / 8.0, 0.0, 1.0)      # pod ~3 m/s se nenaklání (nepadá)
		var mu := 1.05 * float(spec.get("grip", 1.0)) * (weather.surface_grip("asfalt") if weather != null else 0.9)
		var tgt := -steer_in * minf(lean_max, atan(minf(mu, 1.6))) * auth if drive != Drive.NONE else 0.0
		var err := global_transform.basis.y.cross(Vector3.UP.rotated(hf, tgt)).dot(hf)
		apply_torque(hf * (err * 14.0 - w_roll * 3.5) * mass * stab)
		if drive != Drive.NONE and absf(speed) > 2.0:
			# camber thrust: nakloněné kolo tlačí do strany → yaw; uzavřená smyčka drží
			# rovnovážnou zatáčku g·tan(roll)/v – větší náklon = prudší zatáčka, v rychlosti klidná
			var yaw_up := angular_velocity.dot(Vector3.UP)
			var want_yaw := clampf(-9.81 * tan(_roll) / absf(speed) * signf(speed), -1.2, 1.2)
			apply_torque(Vector3.UP * (want_yaw - yaw_up) * mass * float(spec.get("lean_yaw", 0.9)))
		# vizuální přídavek už nepotřebujeme (náklon je v tuhém tělese); zaparkovaná na stojánku
		var vwant := -0.09 if (drive == Drive.NONE and absf(speed) < 0.3) else 0.0
		lean = lerpf(lean, vwant, 1.0 - exp(-6.0 * delta))
	else:
		var err := global_transform.basis.y.cross(Vector3.UP).dot(fwd)
		var w_roll := angular_velocity.dot(fwd)
		var stab := 1.0 - clampf(cargo_kg / 60.0, 0.0, 0.4)          # náklad na nosiči: horší stabilizace
		stab *= float(model.spec.get("stab", 1.0))
		apply_torque(fwd * (err * 14.0 - w_roll * 3.5) * mass * stab)
		var yaw_rate := angular_velocity.dot(global_transform.basis.y)
		var want := -atan(speed * yaw_rate / 9.81) if absf(speed) > 1.0 else 0.0
		if drive == Drive.NONE and absf(speed) < 0.3:
			want = -0.09                    # stojánek vlevo
		lean = lerpf(lean, clampf(want, -0.75, 0.75), 1.0 - exp(-6.0 * delta))
	if model.kind == "bike" and drive == Drive.PLAYER and throttle > 0.05 and gear == 1:
		pedal_angle = fmod(pedal_angle + maxf(speed, 1.2) / float(model.spec["wheel_r"]) / 2.6 * delta, TAU)


## Kola (Jolt, náhrada VehicleWheel3D): paprsek z uchycení nápravy dolů o délce
## rest + radius → pružina `stiff × stlačení + damp × rychlost stlačování` (strop
## mass·g·2.5 jako dřív) tlačí po normále terénu v kontaktním bodu. Rychlost
## stlačování se bere z rychlosti uchycení (ne diferencí délky – při doskoku
## z výskoku by to dalo falešný kopanec a auto poskakovalo); odpružení tlumí
## ~1,45× víc než stlačení (dřív damping_relaxation/compression 1.9/1.3).
## Pneumatika pak přenáší boční sílu proti smyku omezenou třecím limitem
## µ (grip) × normálové zatížení a podélnou sílu motoru/brzd přímo – stejně
## jako VehicleBody3D (engine_force nepřes třecí kruh, jinak by rozjezd
## vyšel ~2× pomalejší než dřív). Náplň limitu → w.skid (zvuk smyku),
## v_lon → otáčky kol pro motor (náhrada get_rpm) a odvalení vizuálu.
func _wheels(delta: float) -> void:
	var xf := global_transform
	var up := xf.basis.y.normalized()
	var com := xf * center_of_mass                       # světové těžiště
	var m_eff := mass / float(maxi(wheels.size(), 1))    # podíl hmotnosti na kolo
	var f_max := mass * 9.81 * 2.5                       # strop pružné síly (dřív suspension_max_force)
	for w in wheels:
		var steer_a := steering if w.front else 0.0
		w.force_raycast_update()                           # čerstvý paprsek – po teleportu jinak vrací kontakt ze staré pozice
		var have := w.is_colliding()
		var n := up
		var pt := w.global_position - up * (w.rest + w.travel + w.radius)
		if have:
			var hp := w.get_collision_point()
			# sanity: zásah mimo dosah paprsku = zastaralý kontakt, ignorovat
			if hp.distance_to(w.global_position) <= w.rest + w.travel + w.radius + 0.05:
				pt = hp
				n = w.get_collision_normal()
			else:
				have = false
		var fwd_w := xf.basis * Vector3(sin(steer_a), 0.0, cos(steer_a))
		fwd_w -= n * fwd_w.dot(n)                        # směr kvaltování promítnutý na rovinu terénu
		if fwd_w.length_squared() < 0.001:
			continue
		fwd_w = fwd_w.normalized()
		var right_w := n.cross(fwd_w)
		var rel := pt - com
		var v_pt := linear_velocity + angular_velocity.cross(rel)
		w.v_lon = v_pt.dot(fwd_w)
		w.v_lat = v_pt.dot(right_w)
		w.spin += w.v_lon / w.radius * delta
		var v_lat := w.v_lat
		w.contact_body = w.get_collider() if have else null
		var sus := w.rest + w.travel                       # bez kontaktu: plně vypružené (doraz)
		if have:
			sus = clampf(pt.distance_to(w.global_position) - w.radius, maxf(w.rest - w.travel, 0.02), w.rest + w.travel)
		w.sus_len = sus
		# tlumič: rychlost stlačování z rychlosti kontaktního bodu podél normály
		var cvel := -v_pt.dot(n) if have else 0.0
		var dk := 1.0 if cvel > 0.0 else 1.45            # odpružení tlumí víc než stlačení
		# za klidovou délkou jde síla do mínusu – kolo visí na dorazu a drží karoserii u země
		# (jako VehicleBody3D); tah omezený, aby visící kolo neštíplo auto k zemi
		var compr := w.rest - sus
		var f_sus := clampf(w.stiff * compr + w.damp * dk * cvel, -mass * 9.81 * 0.2, f_max)
		w.load = maxf(f_sus, 0.0)
		if f_sus != 0.0:
			apply_force(n * f_sus, pt - xf.origin)
		if f_sus <= 0.0:
			w.skid = 1.0
			continue
		# pneumatika: boční síla omezená µ·N; podélná (motor/brzda) přímo jako VehicleBody3D
		var cap := maxf(w.grip * f_sus, 0.0)
		var f_lat_d := -v_lat * m_eff / delta
		var f_lat := clampf(f_lat_d, -cap, cap)
		var f_lon := w.engine_force - signf(w.v_lon) * w.brake
		if absf(w.v_lon) < 0.1:
			# pomalý pohyb: brzda drží auto na místě (odpor proti rozběhu, ne sign-flick)
			f_lon = w.engine_force + clampf(-w.v_lon * m_eff / delta, -w.brake, w.brake)
		apply_force(right_w * f_lat + fwd_w * f_lon, pt - xf.origin)
		var dem := sqrt(f_lat_d * f_lat_d + f_lon * f_lon)
		w.skid = 1.0 if dem <= cap or dem < 1.0 else clampf(cap / dem, 0.0, 1.0)


## Poloha kol pro vizuál: attach → střed kola podle délky pružení `w.sus_len` (fyzikální
## paprsek), rotace (odvalení `w.spin` + natočení `steering`) složená ručně.
func _update_wheel_visuals() -> void:
	var xf := global_transform
	var up := xf.basis.y.normalized()
	for i in wheels.size():
		var w := wheels[i]
		var steer_a := steering if w.front else 0.0
		var wxf := Transform3D(xf.basis * Basis(Vector3.UP, steer_a) * Basis(Vector3.RIGHT, w.spin), Vector3.ZERO)
		wxf.origin = (xf * _wheel_attach[i]) - up * minf(w.sus_len, w.rest + w.travel)
		if two_wheeler:
			wxf.origin -= xf.basis.x * _wheel_attach[i].x      # kolo uprostřed mezi paprsky
		_prev_wxf[i] = _cur_wxf[i]
		_cur_wxf[i] = wxf


func _player_input(delta: float) -> void:
	var inp := driver_input if driver_input else InputState.new()
	var t := inp.throttle
	var b := inp.brake
	var s := inp.steer
	var hb := inp.jump
	if input_locked:
		t = 0.0
		b = 0.0
		s = steer_in
		hb = false
	# --- opilost: zpoždění reakce, rozkmit volantu, mikrospánek
	var p := body_state.promile() if body_state else 0.0
	if p > 0.05:
		var delay := clampf(p * 0.16, 0.0, 0.6)
		_input_buf.append([_t, t, b, s, hb])
		while _input_buf.size() > 1 and _t - _input_buf[1][0] >= delay:
			_input_buf.pop_front()
		var d: Array = _input_buf[0]
		if _t - d[0] >= delay or _input_buf.size() == 1:
			t = d[1]
			b = d[2]
			s = d[3]
			hb = d[4]
		s += _drunk_noise.get_noise_1d(_t * 20.0) * clampf(p * 0.35, 0.0, 0.8)
		s = clampf(s * (1.0 + p * 0.25), -1.0, 1.0)     # přehnané korekce
		_microsleep_cool -= delta
		if p > 1.2 and _microsleep <= 0.0 and _microsleep_cool <= 0.0:
			_microsleep_cool = randf_range(4.0, 10.0) / (p - 0.8)
			if randf() < 0.35:
				_microsleep = randf_range(0.5, 0.4 + p * 0.5)
		if _microsleep > 0.0:
			_microsleep -= delta
			t = throttle
			s = steer_in
			b = 0.0
	if police_hold:
		t = 0.0
		b = 1.0 if absf(speed) > 0.3 else 0.0
		hb = true
	steer_in = move_toward(steer_in, s, delta * (3.2 if absf(s) > absf(steer_in) else 5.0))
	# plyn/brzda ↔ zpátečka
	if gear == -1:
		throttle = b
		brake_in = t
		if t > 0.1 and speed > -0.5:
			gear = 1
	else:
		throttle = t
		brake_in = b
		if b > 0.1 and speed < 0.6 and t < 0.1:
			gear = -1
	handbrake = hb


func _torque_at(r: float) -> float:
	var rmax: float = model.spec["rpm_max"]
	var x := r / rmax
	var f := 1.0
	if x < 0.3:
		f = lerpf(0.55, 1.0, x / 0.3)
	elif x > 0.65:
		f = lerpf(1.0, 0.72, (x - 0.65) / 0.35)
	return float(model.spec["torque"]) * f


func _powertrain(delta: float) -> void:
	var spec := model.spec
	var gears: Array = spec["gears"]
	var final_d: float = spec["final"]
	var wr: float = spec["wheel_r"]
	var rmax: float = spec["rpm_max"]
	# otáčky kol → motor (ω = v_lon / r z raycastu kol)
	var wrpm := 0.0
	var n := 0
	for w in wheels:
		if w.traction:
			wrpm += absf(w.v_lon) / w.radius * 60.0 / TAU
			n += 1
	wrpm /= maxf(n, 1)
	var ratio: float = (3.3 if gear == -1 else float(gears[gear - 1])) * final_d
	var eng_rpm := wrpm * ratio
	var dead := damage >= 100.0
	if model.kind == "bike":
		_pedal_force(wrpm, dead)
		return
	# spojka – rozjezd
	if eng_rpm < 1300.0:
		eng_rpm = lerpf(maxf(eng_rpm, IDLE_RPM), 2200.0, throttle * (1.0 - clampf(eng_rpm / 1300.0, 0.0, 1.0)) + 0.0)
	rpm = lerpf(rpm, clampf(eng_rpm, IDLE_RPM, rmax + 200.0), clampf(delta * 12.0, 0.0, 1.0))
	if dead:
		rpm = 0.0
	# automat
	_shift_t = maxf(_shift_t - delta, 0.0)
	if gear >= 1 and _shift_t <= 0.0:
		var up_at := lerpf(2600.0, rmax * 0.93, throttle)
		if rpm > up_at and gear < gears.size() and speed > 2.0:
			gear += 1
			_shift_t = 0.3
		elif gear > 1:
			var r_low := absf(speed) / wr * 60.0 / TAU * float(gears[gear - 2]) * final_d
			if rpm < 1300.0 or (throttle > 0.8 and r_low < rmax * 0.8 and rpm < rmax * 0.55):
				gear -= 1
				_shift_t = 0.25
	# síla motoru
	var force := 0.0
	if not dead and _shift_t <= 0.0 and throttle > 0.01:
		var tq := _torque_at(rpm) * throttle
		if rpm > rmax:
			tq = 0.0
		tq *= 1.0 - clampf((damage - 50.0) / 100.0, 0.0, 0.5)
		force = tq * ratio * 0.9 / wr
		if gear == -1:
			force = -force
	var brake_force := mass * 8.8 / 4.0 * brake_in             # N za kolo (~ zpomalení 9 m/s²)
	var engine_brake := 0.0
	if throttle < 0.05 and not dead:
		engine_brake = mass * 0.9 / 4.0
	var tire_grip := float(spec.get("grip", 1.0))              # přilnavost pneu podle modelu (motorky: lepší guma)
	var lean_phys := float(spec.get("lean_max", 0.0)) > 0.0
	var load_xfer := clampf(absf(speed) / 10.0, 0.0, 1.0)
	for w in wheels:
		var surf := _surface_grip(w)
		var grip := 1.05 * surf * tire_grip
		if not w.front and handbrake:
			grip *= 0.55
		if lean_phys:
			# podélný přenos zatížení: brzda naloží přední kolo (+grip vpředu, zadek odlehčený),
			# plyn zadní – zadek sice drží líp, ale klouže při plném výkonu
			grip *= 1.0 + (0.16 if w.front else -0.10) * brake_in * load_xfer
			grip *= 1.0 + (-0.05 if w.front else 0.08) * throttle * load_xfer
		w.grip = grip
		if w.traction and brake_in < 0.05:
			w.engine_force = force / maxf(n, 1)
			w.brake = 0.0 if force != 0.0 else engine_brake
		else:
			w.engine_force = 0.0
			w.brake = brake_force + (engine_brake if w.traction else 0.0)
		if handbrake and not w.front:
			w.engine_force = 0.0
			w.brake = mass * 7.0 / 4.0
	# řízení – menší rejd při rychlosti (steer_v = rychlost dosažení minima, steer_hi = minimum, steer_rate = rychlost náběhu)
	var max_steer := lerpf(0.6, float(spec.get("steer_hi", 0.09)), clampf(absf(speed) / float(spec.get("steer_v", 33.0)), 0.0, 1.0))
	var s_tgt := steer_in * max_steer
	if lean_phys:
		# svod řízení (trail): přední kolo se fyzikálně samo skládá do náklonu – tohle je u skutečné
		# motorky hlavní mechanismus, jakým náklon vytváří zatáčení (vedle camber thrust z _balance)
		s_tgt += -_roll * float(spec.get("lean_steer", 0.28))
		# protizatáčení: náhlá změna vstupu krátce vychýlí řídítka opačně – překopne motorku do náklonu
		var sdot := (steer_in - _si_prev) / maxf(delta, 0.001)
		s_tgt -= sdot * float(spec.get("countersteer", 0.02))
	steering = move_toward(steering, clampf(s_tgt, -0.7, 0.7), delta * float(spec.get("steer_rate", 2.2)))
	_si_prev = steer_in
	# brzdová světla
	var bl := 3.0 if (brake_in > 0.1 or handbrake) else (0.9 if lights_on else 0.3)
	model.tail_mat.emission_energy_multiplier = bl


## Kolo: síla šlapání (klesá k maximální rychlosti), zpátky jen pomalu (tlačení), volnoběžka – bez brzdění motorem.
func _pedal_force(wrpm: float, dead: bool) -> void:
	var spec := model.spec
	var vmax: float = spec["vmax"]
	var push: float = spec["push"]
	rpm = wrpm / 2.6
	var force := 0.0
	if not dead and throttle > 0.01:
		if gear == -1:
			force = -push * 0.4 * throttle * clampf(1.5 - absf(speed), 0.0, 1.0)
		else:
			force = push * throttle * clampf((vmax - speed) / 2.5, 0.0, 1.0) * (1.0 - damage / 200.0)
	var brake_force := mass * 7.5 / 4.0 * brake_in             # N za kolo
	var tire_grip := float(spec.get("grip", 1.0))
	for w in wheels:
		var grip := 1.05 * _surface_grip(w) * tire_grip
		if not w.front and handbrake:
			grip *= 0.55
		w.grip = grip
		w.engine_force = force * 0.5 if w.traction and brake_in < 0.05 else 0.0
		w.brake = brake_force if brake_in >= 0.05 else 0.0
		if handbrake and not w.front:
			w.engine_force = 0.0
			w.brake = mass * 7.0 / 4.0
	var max_steer := lerpf(0.6, float(spec.get("steer_hi", 0.12)), clampf(absf(speed) / float(spec.get("steer_v", 12.0)), 0.0, 1.0))
	steering = move_toward(steering, steer_in * max_steer, get_physics_process_delta_time() * float(spec.get("steer_rate", 2.6)))
	model.tail_mat.emission_energy_multiplier = 0.9 if lights_on else 0.3


func _surface_grip(w: Wheel) -> float:
	if not w.is_in_contact():
		return 1.0
	var b := w.contact_body
	if b == null:
		return 1.0
	var s: String = b.get_meta("surface", "")
	if weather != null:
		return weather.surface_grip(s)        # mokro / sníh / náledí / bahno
	return float(Weather.SURF_GRIP.get(s, 0.9))      # bez počasí (test) – suchá tabulka


# ------------------------------------------------------------------ nárazy

func _detect_crash(delta: float) -> void:
	_crash_cool = maxf(_crash_cool - delta, 0.0)
	var dv := linear_velocity - _prev_vel
	_prev_vel = linear_velocity
	# očekávaná změna (gravitace, brzdy) je < 0,3 m/s za krok
	var dvh := Vector3(dv.x, dv.y * 0.35, dv.z)
	var impact := dvh.length()
	if impact < 2.2 or _crash_cool > 0.0:
		return
	var bodies := get_colliding_bodies()
	var what := "neznámo"
	var other: Object = null
	for b in bodies:
		other = b
		if b is Car:
			what = "auto"
			break
		elif b is RigidBody3D:
			what = b.get_meta("kind", "předmět")
		elif b is StaticBody3D:
			var sf: String = b.get_meta("surface", "")
			what = {"budova": "budova", "teren": "terén", "asfalt": "silnice", "sterk": "cesta", "strom": "strom"}.get(sf, "zeď")
		elif b is CharacterBody3D:
			what = "člověk"
	if bodies.is_empty():
		return
	_crash_cool = 0.35
	var dmg := clampf((impact - 2.0) * 4.5, 0.0, 60.0)
	if what in ["silnice", "cesta", "terén"] and dv.y > 0.0 and absf(dv.y) > Vector2(dv.x, dv.z).length():
		dmg *= 0.3    # dopad na podvozek
	damage = minf(damage + dmg, 100.0)
	# deformace v místě nárazu
	var ldir := global_transform.basis.inverse() * (-dv.normalized())
	var hit := Vector3(clampf(ldir.x * 3.0, -1.0, 1.0) * model.half_width, 0.75,
		clampf(ldir.z * 3.0, -1.0, 1.0) * model.length * 0.5)
	model.deform(hit, -ldir.normalized() * Vector3(1, 0.3, 1), clampf(impact * 0.018, 0.02, 0.22), 0.55 + impact * 0.03)
	if damage > 45.0:
		_smoke.emitting = true
	crashed.emit(impact, what, other)
	if other is RigidBody3D and other.has_method("on_hit"):
		other.on_hit(impact)


func _detect_people() -> void:
	for b in get_colliding_bodies():
		if b is CharacterBody3D:
			# rozhoduje jen rychlost auta směrem k člověku – když do stojícího
			# (nebo pomalu couvajícího) auta vejde/vběhne chodec, nic se mu nestane
			var to_b := (b as Node3D).global_position - global_position
			to_b.y = 0.0
			var hv := Vector3(linear_velocity.x, 0.0, linear_velocity.z)
			var rel := hv.dot(to_b.normalized()) if to_b.length() > 0.01 else hv.length()
			var id := b.get_instance_id()
			if rel > 3.0 and Time.get_ticks_msec() > int(_person_cool.get(id, 0)):
				_person_cool[id] = Time.get_ticks_msec() + 2500
				hit_person.emit(b, rel)
				if b.has_method("knock"):
					b.knock(linear_velocity * 0.6 + Vector3.UP * rel * 0.35, rel)


func _beacons() -> void:
	var ph := fmod(_t * 3.0, 1.0)
	var blue := ph < 0.5
	var flash := fmod(_t * 12.0, 1.0) < 0.5
	_beacon_mat_b.emission_energy_multiplier = 6.0 if blue and flash else 0.2
	_beacon_mat_r.emission_energy_multiplier = 6.0 if not blue and flash else 0.2
	_beacon_l.light_energy = 3.0 if blue and flash else 0.0
	_beacon_r.light_energy = 3.0 if not blue and flash else 0.0


func beacons_off() -> void:
	if _beacon_mat_b:
		_beacon_mat_b.emission_energy_multiplier = 0.2
		_beacon_mat_r.emission_energy_multiplier = 0.2
		_beacon_l.light_energy = 0.0
		_beacon_r.light_energy = 0.0


# ------------------------------------------------------------------ AI řidič

func _ai_drive(delta: float) -> void:
	var pos := global_position
	var fwd := global_transform.basis.z
	# počasí: v dešti / sněhu / mlze AI jede opatrněji; v husté mlze a ve tmě rozsvítí světla
	var caution := 0.0
	if weather != null:
		caution = clampf(maxf(weather.rain, weather.snow_cover) + weather.fog, 0.0, 1.0)
	var want_lights := (weather != null and weather.fog > 0.3) or (clock != null and clock.is_night())
	if want_lights != lights_on:
		toggle_lights()
	var target := Vector3.INF
	var want := 0.0
	if ai_direct_target != Vector3.INF:
		target = ai_direct_target
		want = ai_speed_limit
		var dist := Vector2(target.x - pos.x, target.z - pos.z).length()
		want = minf(want, maxf(dist * 0.7, 0.0))
	elif ai_path.size() >= 2:
		# posun po trase
		# u ostrého lomu se bod trasy odbavuje blíž, aby auto nepřeskočilo roh dřív, než ho projede
		while ai_i < ai_path.size() - 1 and Vector2(ai_path[ai_i].x - pos.x, ai_path[ai_i].z - pos.z).length() < (3.0 if _path_turn(ai_i) > AI_SHARP else 7.0):
			ai_i += 1
		if _ai_pass_until >= 0 and ai_i > _ai_pass_until:
			_ai_pass_until = -1
		_ai_offset = move_toward(_ai_offset, 2.9 if _ai_pass_until >= 0 else 0.0, delta * 1.5)
		var look := clampf(absf(speed) * 0.8, 6.0, 18.0)
		var k := ai_i
		# předvídání se nezastaví za rohem: míří na vrchol ostré zatáčky a teprve pak na další úsek
		while k < ai_path.size() - 1 and Vector2(ai_path[k].x - pos.x, ai_path[k].z - pos.z).length() < look:
			if k > ai_i and _path_turn(k) > AI_SHARP:
				break
			k += 1
		target = _lane_pt(k)
		# rychlost podle poloměru zatáček v následujících ~70 m (boční zrychlení ≤ 3,5 m/s², plánované brzdění 2,5 m/s²):
		# v každém lomu trasy oblouk tečný k oběma úsekům (tečné body v půlce kratšího úseku)
		want = ai_speed_limit
		var dist := 0.0
		for j in range(maxi(ai_i - 1, 1), ai_path.size() - 1):
			var pj := Vector2(ai_path[j].x, ai_path[j].z)
			if j == ai_i:
				dist = Vector2(pos.x, pos.z).distance_to(pj)
			elif j > ai_i:
				dist += pj.distance_to(Vector2(ai_path[j - 1].x, ai_path[j - 1].z))
			if dist > 70.0:
				break
			var d0 := pj - Vector2(ai_path[j - 1].x, ai_path[j - 1].z)
			var d1 := Vector2(ai_path[j + 1].x, ai_path[j + 1].z) - pj
			if d0.length() < 0.5 or d1.length() < 0.5:
				continue
			var ang := absf(d0.angle_to(d1))
			if ang < 0.04:
				continue
			var r := maxf(minf(d0.length(), d1.length()) * 0.5 / tan(minf(ang, 3.0) * 0.5), 3.0)
			# ostřejší lom = menší boční zrychlení → hlubší zpomalení (mírná zatáčka ~3,5 m/s², hairpin ~2 m/s²)
			var a_lat := 3.5 if ang < AI_SHARP else (2.8 if ang < 1.3 else 2.0)
			# na kluzkém povrchu projede zatáčku s menším bočním zrychlením
			var v_curve := sqrt(maxf(a_lat - caution * 1.8, 1.0) * r)
			want = minf(want, sqrt(v_curve * v_curve + 2.0 * 2.5 * dist))
		want = maxf(want, 2.0)
		if _ai_offset > 0.3:
			want = minf(want, 5.0)     # objíždí → pomalu
		var end_d := Vector2(ai_path[ai_path.size() - 1].x - pos.x, ai_path[ai_path.size() - 1].z - pos.z).length()
		want = minf(want, end_d * 0.5)
	if target == Vector3.INF or ai_stop:
		want = 0.0
	want *= lerpf(1.0, 1.0 - AI_SLOW, caution)     # mokro / sníh / mlha → pomaleji
	# překážka v pruhu před autem (auto, chodec, pes, bedna) – kvádr šířky auta se posouvá po trase,
	# takže v zatáčce "vidí" do svého pruhu, ne do zahrad; nízkého psa vidí taky
	var obst := {}
	if ai_direct_target == Vector3.INF:
		_ai_obst_t -= delta
		if _ai_obst_t <= 0.0 or (not _ai_obst.is_empty() and not is_instance_valid(_ai_obst["collider"])):
			_ai_obst_t = 0.1
			# za špatné viditelnosti a kluzku "vidí" dál dopředu – větší rozestup
			_ai_obst = _obstacle_ahead((4.0 + absf(speed) * 1.4) * (1.0 + caution * AI_GAP))
		obst = _ai_obst
	_ai_yield_ignore = maxf(_ai_yield_ignore - delta, 0.0)
	if not obst.is_empty() and _ai_yield_ignore > 0.0 and obst["collider"] is Car:
		obst = {}
	if not obst.is_empty():
		var dd: float = obst["d"]
		want = minf(want, maxf(dd - 2.5 - caution * 4.0, 0.0) * 0.6)
		ai_blocked += delta
		ai_blocker = obst["collider"]
		if ai_blocked > 3.0 and fmod(ai_blocked, 6.0) < delta and (ai_blocker is Player or ai_blocker is Car):
			honk()
		_resolve_block()
	else:
		ai_blocked = 0.0
		ai_blocker = null
	ai_target_speed = want
	# řízení – pure pursuit
	var s := 0.0
	if target != Vector3.INF:
		var local := global_transform.affine_inverse() * target
		var ang := atan2(local.x, maxf(local.z, 0.5))
		var L := maxf(Vector2(local.x, local.z).length(), 3.0)
		var wb: float = model.spec["wb"]
		var max_steer := lerpf(0.6, 0.09, clampf(absf(speed) / 33.0, 0.0, 1.0))
		s = clampf(atan2(2.0 * wb * sin(ang), L) / max_steer, -1.0, 1.0)
		if local.z < 0.0:
			s = signf(local.x) if local.x != 0.0 else 1.0
	# zaseknutí (terénní hrana, obrubník) → vycouvat s opačným rejdem
	if _ai_reverse > 0.0:
		_ai_reverse -= delta
		gear = -1
		throttle = 0.6
		brake_in = 0.0
		handbrake = false
		steer_in = move_toward(steer_in, -s, delta * 6.0)
		if _ai_reverse <= 0.0:
			gear = 1
		return
	if throttle > 0.5 and absf(speed) < 0.4 and obst.is_empty() and want > 1.0:
		_ai_stuck += delta
		if _ai_stuck > 2.0:
			_ai_stuck = 0.0
			_ai_reverse = 1.8
	else:
		_ai_stuck = maxf(_ai_stuck - delta, 0.0)
	steer_in = move_toward(steer_in, s, delta * 6.0)
	# plyn / brzda (P regulátor)
	var err := want - speed
	gear = maxi(gear, 1)
	if err > 0.5:
		throttle = clampf(err * 0.35, 0.0, 1.0)
		brake_in = 0.0
	elif err < -0.8:
		throttle = 0.0
		brake_in = clampf(-err * 0.5, 0.0, 1.0) if want > 0.5 else 1.0
	else:
		throttle = 0.12 if want > 1.0 else 0.0
		brake_in = 0.0 if want > 1.0 else 0.6
	handbrake = want < 0.5 and absf(speed) < 0.5

## Úhel lomu trasy v bodu `j` (rad; 0 = rovně, π = otočka).
func _path_turn(j: int) -> float:
	if j < 1 or j >= ai_path.size() - 1:
		return 0.0
	var d0 := Vector2(ai_path[j].x - ai_path[j - 1].x, ai_path[j].z - ai_path[j - 1].z)
	var d1 := Vector2(ai_path[j + 1].x - ai_path[j].x, ai_path[j + 1].z - ai_path[j].z)
	if d0.length() < 0.5 or d1.length() < 0.5:
		return 0.0
	return absf(d0.angle_to(d1))


## Bod trasy `k` posunutý doleva o `_ai_offset` (objíždění).
func _lane_pt(k: int) -> Vector3:
	var p := ai_path[k]
	if _ai_offset < 0.05:
		return p
	var a := ai_path[maxi(k - 1, 0)]
	var b := ai_path[mini(k + 1, ai_path.size() - 1)]
	var d := Vector2(b.x - a.x, b.z - a.z).normalized()
	# vlevo od směru jízdy (pravý pruh je vpravo od osy → objíždí se do protisměru)
	return p + Vector3(d.y, 0, -d.x) * _ai_offset


func _obstacle_ahead(reach: float) -> Dictionary:
	var space := get_world_3d().direct_space_state
	var q := PhysicsShapeQueryParameters3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(model.half_width * 1.7, 1.0, 0.6)
	q.shape = box
	q.collision_mask = 2 | 4 | 8 | 16
	q.exclude = [get_rid()]
	var lift := Vector3(0, 0.85, 0)
	var pts: Array[Vector3] = [global_transform * Vector3(0, 0.85, model.length * 0.5 + 0.4)]
	if ai_path.size() >= 2:
		var fwd := global_transform.basis.z
		for k in range(ai_i, ai_path.size()):
			var lp := _lane_pt(k) + lift
			var rel := lp - pts[0]
			if rel.dot(fwd) < 1.0:
				continue
			pts.append(lp)
			if pts[pts.size() - 1].distance_to(pts[0]) > reach or pts.size() > 5:
				break
	else:
		pts.append(pts[0] + global_transform.basis.z * reach)
	var acc := 0.0
	for k in pts.size() - 1:
		var a := pts[k]
		var seg := pts[k + 1] - a
		var ln := seg.length()
		if ln < 0.1:
			continue
		if acc + ln > reach:
			seg *= (reach - acc) / ln
			ln = reach - acc
		var dir := seg / ln
		q.transform = Transform3D(Basis.looking_at(dir, Vector3.UP), a)
		q.motion = seg
		var r := space.cast_motion(q)
		if r[0] < 1.0:
			q.transform.origin = a + seg * r[1]
			q.motion = Vector3.ZERO
			var info := space.get_rest_info(q)
			var col: Object = instance_from_id(info["collider_id"]) if info.has("collider_id") else null
			if col == null:
				continue
			return {"d": acc + ln * r[0], "collider": col}
		acc += ln
		if acc >= reach:
			break
	return {}


## Dlouho stojí za překážkou: vzájemné zablokování dvou aut (křižovatka, úzká cesta) → projede
## to s nižším ID; stojící auto / věc v pruhu → objede ji protisměrem.
func _resolve_block() -> void:
	var b := ai_blocker
	if b is Car and b.drive == Drive.AI and b.ai_blocked > 1.5 and b.ai_blocker == self and ai_blocked > 2.5:
		if get_instance_id() < b.get_instance_id():
			_ai_yield_ignore = 3.0
		return
	var moving: bool = b is Car and absf(b.speed) > 0.8
	if b is CharacterBody3D and not (b is Player):
		moving = true      # chodec / pes odejde sám
	if ai_blocked > 4.0 and not moving and _ai_pass_until < 0 and ai_path.size() > 2:
		_ai_pass_until = mini(ai_i + 4, ai_path.size() - 1)


func ai_done() -> bool:
	return ai_path.size() > 0 and ai_i >= ai_path.size() - 2 and absf(speed) < 1.0


# ------------------------------------------------------------------ vizuál a kamera

func _process(delta: float) -> void:
	var __t0 := Tests.prof_t0()
	_process_impl(delta)
	Tests.prof_add("car_vis", __t0)


func _process_impl(delta: float) -> void:
	var f := Engine.get_physics_interpolation_fraction()
	var xf := _prev_xf.interpolate_with(_cur_xf, f)
	if two_wheeler:
		var lean_xf := Transform3D(Basis(Vector3.BACK, lean), Vector3.ZERO)     # náklon kolem stopy na zemi
		vis.global_transform = xf * lean_xf
		for i in wheels.size():
			if _wheel_vis[i].visible:
				_wheel_vis[i].global_transform = xf * lean_xf * xf.affine_inverse() * _prev_wxf[i].interpolate_with(_cur_wxf[i], f)
		if _fork:
			_fork.basis = Basis(model.fork_axis, steering)
		if _crank:
			_crank.rotation.x = -pedal_angle
	else:
		vis.global_transform = xf
		for i in wheels.size():
			_wheel_vis[i].global_transform = _prev_wxf[i].interpolate_with(_cur_wxf[i], f)
	if _cam_rig:
		_camera_input()
		_update_camera(delta)
	# stěrače (N) – pohyb po čelním skle; kapky jen při pohledu z interiéru za deště
	if not _wipers.is_empty():
		if wipers_on:
			_wphase += delta * WIPER_SPEED
			_wangle = WIPER_SWEEP * (0.5 - 0.5 * cos(_wphase))
		else:
			_wangle = move_toward(_wangle, 0.0, delta * 4.0)   # vrátí se do parkovací polohy
		var wb := _wiper_basis * Basis(Vector3.UP, WIPER_PARK + _wangle)
		for p in _wipers:
			p.basis = wb
	if _glass_drops:
		_glass_drops.emitting = drive == Drive.PLAYER and cam_mode == 1 \
			and weather != null and weather.is_raining()
		if weather != null:
			_glass_drops.amount_ratio = clampf(weather.rain * 1.3, 0.15, 1.0)


## Pohled myší a přepnutí kamery (V) z InputState řidiče.
func _camera_input() -> void:
	if drive != Drive.PLAYER or driver_input == null:
		return
	var rel := driver_input.take_look()
	if rel != Vector2.ZERO:
		_cam_yaw -= rel.x * 0.003
		_cam_pitch = clampf(_cam_pitch - rel.y * 0.003, -1.2, 0.6)
		_cam_idle = 0.0
	driver_input.take_zoom()
	if driver_input.take_toggle_view():
		cam_mode = 1 - cam_mode
		_cam_yaw = 0.0
		_cam_pitch = -0.18 if cam_mode == 0 else -0.05


func _update_camera(delta: float) -> void:
	var xf := vis.global_transform
	_cam_idle += delta
	if cam_mode == 0 and _cam_idle > 2.0:
		_cam_yaw = lerp_angle(_cam_yaw, 0.0, 1.0 - exp(-2.0 * delta))
		_cam_pitch = lerpf(_cam_pitch, -0.18, 1.0 - exp(-2.0 * delta))
	var sway := Vector3.ZERO
	if body_state:
		var d := body_state.drunk_level()
		sway = Vector3(sin(_t * 0.9) * 0.05, sin(_t * 1.3) * 0.03, sin(_t * 0.7 + 1.0) * 0.08) * d
	if cam_mode == 0:
		var fwd := xf.basis.z
		fwd.y = 0.0
		fwd = fwd.normalized()
		var yaw := atan2(fwd.x, fwd.z) + _cam_yaw
		var dist := (6.2 if not two_wheeler else 4.4) + clampf(absf(speed) * 0.04, 0.0, 1.5)
		var off := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, -_cam_pitch) * Vector3(0, 0, -dist)
		var want := xf.origin + Vector3(0, 1.6, 0) + off
		# nezajet kamerou pod terén / do zdi
		var space := get_world_3d().direct_space_state
		var q := PhysicsRayQueryParameters3D.create(xf.origin + Vector3(0, 1.6, 0), want, 1)
		var hit := space.intersect_ray(q)
		if not hit.is_empty():
			want = hit["position"] + (xf.origin + Vector3(0, 1.6, 0) - want).normalized() * 0.3
		_cam_pos = _cam_pos.lerp(want, 1.0 - exp(-9.0 * delta))
		_cam_rig.global_position = _cam_pos
		_cam_rig.look_at(xf.origin + Vector3(0, 1.1, 0) + fwd * 2.0, Vector3.UP)
		_cam_rig.rotate_object_local(Vector3.FORWARD, sway.z)
		_cam.fov = lerpf(_cam.fov, 68.0 + clampf(absf(speed) - 10.0, 0.0, 30.0) * 0.5, 1.0 - exp(-3.0 * delta))
	else:
		var eye := xf * model.eye
		_cam_rig.global_transform = Transform3D(xf.basis * Basis(Vector3.UP, _cam_yaw + PI) * Basis(Vector3.RIGHT, _cam_pitch), eye)
		_cam_rig.rotate_object_local(Vector3.FORWARD, sway.z)
		_cam_rig.rotate_object_local(Vector3.UP, sway.x)
		_cam.fov = 72.0
