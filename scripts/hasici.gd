## Sbor dobrovolných hasičů (M5.3): zbrojnice u úřadu, spolek s členstvím, siréna a výjezd k požáru trávy.
## Spolek je smyšlený („SDH Pod Kopcem“, bez znaku a bez názvu obce). Jeden uzel ve `World` (`World.hasici`).
##
## - Čte herní událost `fire_report` (M2.2, `FireManager._spread`) a rozešle výjezd: siréna na zbrojnici, zpráva členům.
## - Posádka dorazí po `ARRIVE_MIN` herních minutách a každých `SUPPRESS_EVERY_MIN` zmenší nejbližší `GrassFire`.
## - Hráč, který je člen se zaplaceným příspěvkem, v zásahovém obleku (tag `hasic`, M2.3) a stojí u ohně, dostane
##   odměnu (respekt `hasici`, pověst, XP `hasicina`). Bez obleku u plamenů ho oheň zraňuje a hasiči ho napomenou.
## - Požár způsobený hráčem: respekt `hasici` −5 (`on_caused_fire`, volá `FireManager._end_grass`).
## - Schůze: první pátek v měsíci 19:00 v klubovně, účast = respekt +1 (jednou za měsíc).
## Členství se ukládá per hráč (klíč `hasici` v `save_game.gd`).
class_name Hasici
extends Node3D

const NAME := "SDH Pod Kopcem"
const FEE_KC := 200                  # členský příspěvek (Kč / rok)
const FEE_DAYS := 365                # platnost příspěvku (herní dny)
const RESPECT_MIN := 0.0             # respekt „hasici“ potřebný k přijetí
const SOBER_MAX := 0.2               # ‰ – u velitele se nepřijde opilý
const ARRIVE_MIN := 6.0              # herních minut od sirény k příjezdu posádky
const SUPPRESS_EVERY_MIN := 1.5      # posádka hasí každých x herních minut
const SIREN_S := 25.0                # s – jak dlouho siréna houká
const SIREN_R := 700.0               # m – slyšitelnost sirény
const ON_SCENE_R := 25.0             # m od ohně – účast na výjezdu
const FIRE_FIND_R := 80.0            # m – posádka hledá požár v tomhle okruhu od místa volání
const CALL_HEAR_R := 350.0           # m – hráči v dosahu slyší výjezd
const REWARD_RESPECT := 5.0
const REWARD_POVEST := 3.0
const XP_MIN := 50.0
const XP_MAX := 150.0
const SCHUZE_RESPECT := 1.0
const CAUSED_RESPECT := -5.0
const HURT_NO_SUIT := 3.0            # zranění bez zásahového obleku v ohni (jednou za kontrolu)
const DOOR_R := 4.0                  # m – u vchodu zbrojnice se nabízí nabídka
const FRIDAY := 4                    # Clock.weekday(): 0 = pondělí
const SCHUZE_HOUR := 19.0
const STATION_DIST := [40.0, 55.0, 70.0, 90.0]     # m od dveří úřadu (před úřadem, směr od návsi)
const STATION_LAT := [0.0, -20.0, 20.0, -40.0, 40.0]
const ROOF_H := 4.5

var world: World
var station_pos := Vector3.ZERO      # střed zbrojnice (světově, na terénu)
var station_yaw := 0.0
var has_station := false

var _members := {}                   # id → {"since_jd": int, "paid_jd": int, "schuze": String}
var _call := {}                      # aktivní výjezd: {} nebo {"pos", "left", "crew", "fire", "next", "helpers"}
var _siren: AudioStreamPlayer3D
var _siren_left := 0.0
var _last_min := -1.0
var _tick := 0.0
var _rng := RandomNumberGenerator.new()


func setup(w: World) -> void:
	world = w
	_rng.randomize()
	station_pos = _find_station()
	has_station = station_pos != Vector3.INF
	if not has_station:
		push_warning("Zbrojnice SDH: úřad není v datech, zbrojnice se nepostaví.")
		return
	position = station_pos
	rotation.y = station_yaw
	_build()
	_siren = AudioStreamPlayer3D.new()
	_siren.stream = Sfx.siren_loop()
	_siren.max_distance = SIREN_R
	_siren.volume_db = -4.0
	_siren.position = Vector3(-4.0, ROOF_H + 1.0, 0.0)
	add_child(_siren)


## Volné místo před úřadem (směr od návsi, mimo silnice). Zbrojnice je vždy otočená čelem k návsi.
func _find_station() -> Vector3:
	if world == null or not world.places.has("urad") or world.terrain == null:
		return Vector3.INF
	var pl: Place = world.places["urad"]
	var face: float = pl.data.get("face_yaw", 0.0)
	var b := Basis(Vector3.UP, face)
	for d in STATION_DIST:
		for l in STATION_LAT:
			var p := pl.door + b * Vector3(float(l), 0.0, float(d))
			if world.dist_to_roads(Vector2(p.x, p.z)) > 8.0:
				station_yaw = face + PI
				return Vector3(p.x, world.terrain.height_at(p.x, p.z), p.z)
	var f := pl.door + b * Vector3(0.0, 0.0, 60.0)
	station_yaw = face + PI
	return Vector3(f.x, world.terrain.height_at(f.x, f.z), f.z)


## Procedurální garáž s vraty, věžička na sušení hadic, siréna na střeše a cedule bez znaku.
func _build() -> void:
	var kit := MeshKit.new()
	var wall := Color(0.84, 0.80, 0.72)
	var door_c := Color(0.72, 0.16, 0.13)
	var roof_c := Color(0.42, 0.24, 0.20)
	var tower_c := Color(0.90, 0.88, 0.84)
	kit.box(Vector3(0, ROOF_H * 0.5, 0), Vector3(12.0, ROOF_H, 7.0), wall)
	kit.box(Vector3(0, ROOF_H + 0.2, 0), Vector3(12.4, 0.4, 7.4), roof_c)
	kit.box(Vector3(-2.7, 1.5, 3.52), Vector3(3.6, 3.0, 0.12), door_c)
	kit.box(Vector3(2.7, 1.5, 3.52), Vector3(3.6, 3.0, 0.12), door_c)
	kit.box(Vector3(4.6, 6.5, -2.2), Vector3(2.2, 4.0, 2.2), tower_c)
	kit.box(Vector3(4.6, 8.7, -2.2), Vector3(2.6, 0.35, 2.6), roof_c)
	kit.cylinder(Vector3(-4.0, ROOF_H + 0.9, 0.0), 0.3, 0.3, 1.0, Color(0.85, 0.85, 0.85))
	kit.box(Vector3(0, 3.7, 3.56), Vector3(4.6, 0.6, 0.08), Color(0.92, 0.86, 0.55))
	MeshKit.mesh_instance(self, kit.commit(MeshKit.vc_material(0.85, 0.0, 0.0, false)))
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(12.0, ROOF_H, 7.0)
	cs.shape = bs
	cs.position = Vector3(0, ROOF_H * 0.5, 0)
	body.add_child(cs)
	add_child(body)
	var lab := Label3D.new()
	lab.text = NAME
	lab.position = Vector3(0, 3.7, 3.62)
	lab.pixel_size = 0.012
	lab.font_size = 40
	lab.modulate = Color(0.22, 0.12, 0.06)
	add_child(lab)


## Vchod zbrojnice (světově).
func door() -> Vector3:
	return station_pos + Basis(Vector3.UP, station_yaw) * Vector3(0.0, 0.0, 4.0)


# ------------------------------------------------------------------ členství

func _member(id: int) -> Dictionary:
	return _members.get(id, {})


## Člen se zaplaceným příspěvkem (jen ten přijíždí na výjezd a dostává odměny).
func is_paid_member(id: int) -> bool:
	var m := _member(id)
	return not m.is_empty() and int(m.get("paid_jd", -1)) + FEE_DAYS > world.clock.jd()


func is_member(id: int) -> bool:
	return not _member(id).is_empty()


## Nabídka u vchodu (Callable dostává id hráče).
func interactables(id: int) -> Array:
	var out: Array = []
	if not has_station or world == null:
		return out
	var p: Player = world.players.get(id)
	if p == null or p.inside != "" or p.car != null:
		return out
	var d := door()
	if p.global_position.distance_to(d) > DOOR_R:
		return out
	out.append({"pos": d + Vector3(0, 0.3, 0), "r": 3.0, "kind": "custom",
		"text": "%s – zbrojnice, členství a schůze" % NAME, "action": _menu})
	return out


func _menu(id: int) -> void:
	var opts: Array = []
	var m := _member(id)
	var text := "Schůze první pátek v měsíci v 19:00 v klubovně. Výjezd jen se zaplaceným příspěvkem " \
		+ "(%d Kč / rok) a v zásahovém obleku." % FEE_KC
	if m.is_empty():
		opts.append(["Požádat velitele o členství (%d Kč)" % FEE_KC, _apply.bind(id)])
	else:
		if is_paid_member(id):
			text = "Jsi člen a příspěvek máš zaplacený.\n" + text
		else:
			text = "Jsi člen, ale příspěvek vypršel nebo není zaplacen.\n" + text
		opts.append(["Zaplatit členský příspěvek (%d Kč)" % FEE_KC, _pay.bind(id)])
		opts.append(["Vystoupit ze spolku", _leave.bind(id)])
	opts.append(["Zavřít", func(): pass])
	world.notify(id, "open_menu", ["Zbrojnice %s" % NAME, text, opts])


func _apply(id: int) -> void:
	var p: Player = world.players.get(id)
	var rep: Reputation = world.reputations.get(id)
	if p == null or rep == null:
		return
	if rep.respect_of("hasici") < RESPECT_MIN:
		_msg(id, "Velitel: K nám zatím ne. Nejdřív si u nás získej respekt.", 5.0)
		return
	if p.body.promile() > SOBER_MAX:
		_msg(id, "Velitel: Přijď střízlivý, takhle tě na zbrojnici nepustím.", 5.0)
		return
	if p.money < FEE_KC:
		_msg(id, "Velitel: Příspěvek je %d Kč, na to nemáš." % FEE_KC, 5.0)
		return
	p.money -= FEE_KC
	var jd: int = world.clock.jd()
	_members[id] = {"since_jd": jd, "paid_jd": jd, "schuze": ""}
	_msg(id, "Velitel: Vítej v %s. Příspěvek máš zaplacený na rok." % NAME, 6.0)
	world.play_sfx(id, "cash")


func _pay(id: int) -> void:
	var p: Player = world.players.get(id)
	if p == null or not is_member(id):
		return
	if is_paid_member(id):
		_msg(id, "Příspěvek máš zaplacený, není třeba platit znovu.", 4.0)
		return
	if p.money < FEE_KC:
		_msg(id, "Příspěvek je %d Kč, na to nemáš." % FEE_KC, 4.0)
		return
	p.money -= FEE_KC
	_members[id]["paid_jd"] = world.clock.jd()
	_msg(id, "Příspěvek zaplacen na další rok. Díky.", 4.0)
	world.play_sfx(id, "cash")


func _leave(id: int) -> void:
	_members.erase(id)
	_msg(id, "Vystoupil jsi ze spolku.", 4.0)


func _msg(id: int, text: String, dur := 4.0) -> void:
	world.notify(id, "show_message", [text, dur])


# ------------------------------------------------------------------ čas: schůze, siréna, výjezd

func _process(delta: float) -> void:
	if world == null or world.clock == null or not has_station:
		return
	var now: float = world.clock.minutes
	var dm := 0.0
	if _last_min >= 0.0:
		dm = clampf(now - _last_min, 0.0, 1440.0)
	_last_min = now
	if _siren_left > 0.0:
		_siren_left -= delta
		if _siren_left <= 0.0 and _siren.playing:
			_siren.stop()
	_tick -= delta
	if _tick <= 0.0:
		_tick = 2.0
		_check_schuze()
	if not _call.is_empty():
		_update_call(dm)


## Schůze: první pátek v měsíci, 19:00–20:00, člen v klubovně (do 40 m) → respekt +1, jednou za měsíc.
func _check_schuze() -> void:
	var c: Clock = world.clock
	if c.weekday() != FRIDAY or c.day() > 7 or c.hour() < SCHUZE_HOUR or c.hour() >= SCHUZE_HOUR + 1.0:
		return
	var key := "%04d-%02d" % [c.year(), c.month()]
	for id in _members:
		if not is_paid_member(id) or _members[id]["schuze"] == key:
			continue
		var p: Player = world.players.get(id)
		if p == null or p.global_position.distance_to(station_pos) > 40.0:
			continue
		_members[id]["schuze"] = key
		var rep: Reputation = world.reputations.get(id)
		if rep:
			rep.change_respect("hasici", SCHUZE_RESPECT, "účast na schůzi %s" % NAME)


func _nearest_fire(at: Vector3) -> GrassFire:
	var best: GrassFire = null
	var bd := FIRE_FIND_R
	for g in world.grass_fires:
		if not is_instance_valid(g) or g.finished:
			continue
		var d: float = g.global_position.distance_to(at)
		if d < bd:
			bd = d
			best = g
	return best


## Příjem herních událostí (volá `World.emit_game_event`).
func on_event(_id: int, kind: String, data: Dictionary) -> void:
	if kind != "fire_report" or not _call.is_empty():
		return
	var at: Vector3 = data.get("pos", Vector3.INF)
	if at == Vector3.INF:
		return
	_call_out(at)


func _call_out(at: Vector3) -> void:
	_call = {"pos": at, "left": ARRIVE_MIN, "crew": false, "fire": null, "next": 0.0, "helpers": {}}
	_siren.play()
	_siren_left = SIREN_S
	for id in world.players:
		var p: Player = world.players[id]
		var pid := int(id)
		if is_paid_member(pid):
			_msg_popup(pid, "Výjezd! Požár trávy – dojdi do zbrojnice %s (5 min)." % NAME, 6.0)
		elif world.player_world_pos(p).distance_to(station_pos) < CALL_HEAR_R:
			_msg_popup(pid, "Slyšíš sirénu od hasičské zbrojnice.", 4.0)


func _msg_popup(id: int, text: String, dur: float) -> void:
	world.notify(id, "popup", [text, dur])


func _update_call(dm: float) -> void:
	var c: Dictionary = _call
	if not bool(c["crew"]):
		c["left"] = float(c["left"]) - dm
		if float(c["left"]) > 0.0:
			return
		c["crew"] = true
		var g := _nearest_fire(c["pos"])
		c["fire"] = g
		if g == null:
			_announce_all("Hasiči přijeli, ale oheň už dohořel.")
			_call = {}
			return
		_announce_all("Hasiči jsou na místě, hasí.")
	var fire: GrassFire = c["fire"] as GrassFire
	if fire == null or not is_instance_valid(fire) or fire.finished:
		_reward_helpers(c)
		_call = {}
		return
	for id in world.players:
		var p: Player = world.players[id]
		var pid := int(id)
		var pp := world.player_world_pos(p)
		if pp.distance_to(fire.global_position) <= ON_SCENE_R and is_paid_member(pid):
			(c["helpers"] as Dictionary)[pid] = true
		if p.car == null and p.inside == "" and fire.in_fire(pp) and not _suited(p):
			p.body.hurt(HURT_NO_SUIT * minf(dm, 1.0), "bez zásahového obleku u ohně")
			if randf() < 0.3:
				_msg(pid, "Bez zásahového obleku se k ohni nepřibližuj! Oblékni si zásahový oblek.", 3.0)
	c["next"] = float(c["next"]) - dm
	if float(c["next"]) <= 0.0:
		c["next"] = SUPPRESS_EVERY_MIN
		fire.suppress()


func _suited(p: Player) -> bool:
	return Wardrobe.has_tag(p.outfit, "hasic")


func _announce_all(text: String) -> void:
	for id in _members:
		if is_paid_member(id):
			_msg_popup(id, text, 4.0)


## Odměna členům, kteří byli u ohně v zásahovém obleku, až oheň zhasne.
func _reward_helpers(c: Dictionary) -> void:
	for id in (c["helpers"] as Dictionary):
		var p: Player = world.players.get(id)
		if p == null or not _suited(p):
			continue
		var rep: Reputation = world.reputations.get(id)
		if rep:
			rep.change_respect("hasici", REWARD_RESPECT, "výjezd k požáru")
			rep.change(REWARD_POVEST, "pomohl při požáru")
		var sk: Skills = world.skills.get(id)
		if sk:
			sk.add_xp("hasicina", _rng_xp(), "výjezd SDH")
		_msg_popup(int(id), "Výjezd skončil. Oheň uhašen – díky, kamaráde.", 5.0)


func _rng_xp() -> float:
	return _rng.randf_range(XP_MIN, XP_MAX)


## Člen, který způsobil požár (FireManager._end_grass), se u sboru propadne v respektu.
func on_caused_fire(id: int) -> void:
	var rep: Reputation = world.reputations.get(id)
	if rep:
		rep.change_respect("hasici", CAUSED_RESPECT, "požár, který jsi způsobil")


# ------------------------------------------------------------------ ukládání

func to_dict(id: int) -> Dictionary:
	return (_member(id) as Dictionary).duplicate()


func from_dict(id: int, d: Dictionary) -> void:
	if d.is_empty():
		_members.erase(id)
		return
	_members[id] = {"since_jd": int(d.get("since_jd", 0)), "paid_jd": int(d.get("paid_jd", -1)),
		"schuze": String(d.get("schuze", ""))}
