## Potoky, řeka a rybníky podle skutečných dat (OSM / DIBAVOD, tools/water.py → data/water.json).
## Koryta jsou už vyhloubená v terénu (Terrain._apply_water_carve); tady se staví hladina:
## pás podél osy toku (hladina po bodech klesá po proudu) a plochy nádrží.
## Dotazy: info_at (hloubka a jméno toku v bodě – brodění, kroky), nearest_stream (šumění potoka).
## V mrazu voda zamrzá (rybníky dřív, tekoucí voda později), v dešti a větru víc vlnek.
## M8.7: průtok a hladina toků z vodní bilance (`World.soil_water`, lineární nádrže): `flow_at` (m³/s),
## `level_at` (m vůči normálu); hladina pásu vody se zvedá/klesá (instance uniform `level_ofs`, max ±0,4 m),
## po přívalu kalní (`turbid`), proud zrychlí (`flow_mult`), v suchu malý potok vyschne (pás se schová).
## Bez bilance (přepínač Realismus → `soil_water` vypnutý) se chová jako dřív.
## Vzhled: shaders/include/water.gdshaderinc – levná varianta (water.gdshader) pro Nízkou / Střední, od Vysoké
## `water_hq.gdshader` (lom, odraz okolí, kapky deště); přepíná se podle globálního `gfx_quality` za běhu.
class_name Water
extends Node3D

const CELL := 32.0                    # mřížka pro hledání nejbližšího úseku
const VIS_RANGE := 1100.0
const FLOW := {"river": 0.55, "canal": 0.3, "stream": 0.9, "ditch": 0.4, "drain": 0.4}
const SHADER_LO := "res://shaders/water.gdshader"
const SHADER_HQ := "res://shaders/water_hq.gdshader"
## Vzhled vody (moravská pahorkatina – hnědozelená, zakalená): [mělká, rozptyl v hloubce, útlum 1/m R, G, B].
const LOOK := {
	"stream": [Color(0.31, 0.32, 0.21), Color(0.14, 0.15, 0.08), Vector3(1.2, 0.9, 1.6)],
	"river": [Color(0.32, 0.33, 0.23), Color(0.13, 0.14, 0.08), Vector3(1.5, 1.1, 2.0)],
	"pond": [Color(0.27, 0.31, 0.19), Color(0.12, 0.145, 0.075), Vector3(1.8, 1.3, 2.4)],
}
const LEVEL_STEP := 0.012             # m: výškový posun hladiny toku podle pořadí (překryv úseků → žádný z-fighting)
const SLOPE_REF := 0.035              # sklon hladiny, při kterém teče proud „normálně“ (násobek 1)
const END_FADE := 4.0                 # m: volný konec pásu toku (pramen, ústí do jiného toku) dozní a zúží se
const JOIN_DIST := 1.5                # m: konec u konce jiného úseku = navazující úsek téhož toku (bez doznění)
## M8.7: normální průtok (m³/s) bez vodní bilance (fallback `flow_at`) a vizuál hladiny.
## M8.D2c: chování = `static var` (F3 → Příroda/Voda a půda), výchozí beze změny.
static var FLOW_NOMINAL := {"river": 1.2, "canal": 0.3, "stream": 0.03, "ditch": 0.01, "drain": 0.01}
static var STREAM_VIS_S := 1.0        # jak často se přepočte vzhled hladin toků (s)
static var STREAM_VIS_RATE := 0.08    # m za tick – plynulý posun hladiny (vizuál)
const BROOK_DB_MAX := 6.0             # o kolik dB hlasitější šumění při velké vodě
static var STREAM_NEAR_M := 30.0      # flow_at / level_at: nejbližší tok do (m)
static var POND_FREEZE_C := 1.0       # rybník začne zamrzat pod −tolik °C
static var POND_FREEZE_SPAN := 4.0    # … úplně zamrzlý o tolik °C níž
static var STREAM_FREEZE_C := 5.0     # tekoucí voda začne zamrzat pod −tolik °C
static var STREAM_FREEZE_SPAN := 6.0  # … úplně zamrzlá o tolik °C níž
static var ICE_RATE_H := 0.08         # rychlost zamrzání / tání rybníka (za herní hodinu)
static var ICE_FLOW_RATE_H := 0.05    # … tekoucí vody
static var WAVES_RAIN := 0.8          # vlnky: přídavek při plném dešti
static var WAVES_WIND := 0.7          # … při plném větru
static var WAVES_WIND_FULL := 10.0    # … „plný vítr“ (m/s)
static var TURB_VIS_RATE := 0.05      # vizuál: přiblížení kalnosti za tick
static var FLOW_VIS_RATE := 0.1       # vizuál: přiblížení rychlosti proudu za tick

var world: World
var terrain: Terrain
var data := {}
var streams := []                     # [{name, kind, half_w, pts: PackedVector3Array}]
var ponds := []                       # [{name, level, poly: PackedVector2Array, aabb: Rect2}]
var drop_trees := {}                  # pořadí stromu v trees.bin → true (stojí ve vodě)
var ice := 0.0                        # zamrznutí rybníků 0..1 (tekoucí voda: ice_flow)
var ice_flow := 0.0

var _cells := {}                      # Vector2i → [[stream, i], …]
var _mat_stream: ShaderMaterial
var _mats := []                       # všechny materiály (led, vlnky)
var _last_min := -1.0
var _tick := 0.0
var _stream_mi: Array[MeshInstance3D] = []   # M8.7: mesh hladiny po úsecích (index = streams)
var level_ofs := PackedFloat32Array()        # M8.7: aktuální (vyhlazený) posun hladiny úseku (m)
var _turb_vis := PackedFloat32Array()
var _flow_vis := PackedFloat32Array()
var _vis_tick := 0.0
var _hq := false                             # právě použitá varianta shaderu (od Vysoké)


## Načte data (bez stavby) – hned po terénu, ať MapLoader ví, které stromy vynechat.
func load_data() -> bool:
	if not FileAccess.file_exists("res://data/water.json"):
		push_warning("Chybí data/water.json (python3 tools/water.py) – svět bude bez potoků.")
		return false
	data = JSON.parse_string(FileAccess.get_file_as_string("res://data/water.json"))
	for i in data.get("drop_trees", []):
		drop_trees[int(i)] = true
	return true


func build(w: World, t: Terrain) -> void:
	world = w
	terrain = t
	if data.is_empty():
		return
	_hq = _want_hq()
	var ntex := _wave_texture()
	var kinds: Dictionary = data.get("kinds", {})
	var by_kind := {}
	for s in data.get("streams", []):
		var kind := String(s["kind"])
		var pts := PackedVector3Array()
		for p in s["pts"]:
			pts.append(Vector3(p[0], p[2], p[1]))
		var st := {"name": String(s.get("name", "")), "kind": kind,
			"half_w": float(kinds.get(kind, {}).get("half_w", 1.5)), "pts": pts}
		var si := streams.size()
		streams.append(st)
		for i in pts.size() - 1:
			var key := Vector2i(floori(pts[i].x / CELL), floori(pts[i].z / CELL))
			for dx in [-1, 0, 1]:
				for dz in [-1, 0, 1]:
					var k2 := key + Vector2i(dx, dz)
					if not _cells.has(k2):
						_cells[k2] = []
					_cells[k2].append([si, i])
		if not by_kind.has(kind):
			by_kind[kind] = []
		by_kind[kind].append(si)
	# hladiny toků: jeden mesh na tok (po druzích kvůli rychlosti proudu)
	_stream_mi.resize(streams.size())
	level_ofs.resize(streams.size())
	_turb_vis.resize(streams.size())
	_flow_vis.resize(streams.size())
	_flow_vis.fill(1.0)
	for kind in by_kind:
		var m := _material(ntex, float(FLOW.get(kind, 0.6)), "river" if kind == "river" else "stream")
		for si in by_kind[kind]:
			var mi := MeshInstance3D.new()
			_stream_mi[si] = mi
			mi.extra_cull_margin = 0.5          # M8.7: hladina se v shaderu posouvá o ±0,4 m
			mi.name = "Tok_%d" % si
			mi.mesh = _ribbon(streams[si], float(si % 4) * LEVEL_STEP, _free_end(si, 0), _free_end(si, -1))
			mi.material_override = m
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.visibility_range_end = _vis_end(mi.mesh)
			add_child(mi)
	# rybníky
	var mp := _material(ntex, 0.0, "pond")
	for pd in data.get("ponds", []):
		var poly := PackedVector2Array()
		for q in pd["poly"]:
			poly.append(Vector2(q[0], q[1]))
		if Geometry2D.is_polygon_clockwise(poly):
			poly.reverse()
		var level := float(pd["level"])
		var tri := Geometry2D.triangulate_polygon(poly)
		if tri.is_empty():
			continue
		var v := PackedVector3Array()
		var uv := PackedVector2Array()
		for i in range(tri.size() - 1, -1, -1):       # Godot: přední strana po směru hodin
			var q := poly[tri[i]]
			v.append(Vector3(q.x, level, q.y))
			uv.append(q)
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = v
		arr[Mesh.ARRAY_TEX_UV] = uv
		var nn := PackedVector3Array()
		nn.resize(v.size())
		nn.fill(Vector3.UP)
		arr[Mesh.ARRAY_NORMAL] = nn
		var tg := PackedFloat32Array()
		for _i in v.size():
			tg.append_array([1.0, 0.0, 0.0, 1.0])         # shader: směr „proudu“ (vlnky) = +X
		arr[Mesh.ARRAY_TANGENT] = tg
		var cc := PackedColorArray()
		cc.resize(v.size())
		cc.fill(Color.WHITE)                              # shader: COLOR.a = doznění okraje (rybník bez)
		arr[Mesh.ARRAY_COLOR] = cc
		var am := ArrayMesh.new()
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		var mi := MeshInstance3D.new()
		mi.name = "Rybnik"
		mi.mesh = am
		mi.material_override = mp
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visibility_range_end = _vis_end(am)
		add_child(mi)
		var r := Rect2(poly[0], Vector2.ZERO)
		for q in poly:
			r = r.expand(q)
		ponds.append({"name": String(pd.get("name", "")), "level": level, "poly": poly, "aabb": r.grow(1.0)})


## Dohled hladiny: Godot ho měří od STŘEDU AABB meshe. Tok je jeden mesh dlouhý i několik km
## (union mapa), takže pevný VIS_RANGE by ho schoval i hráči stojícímu na břehu daleko od
## středu toku → dohled + půlka vodorovné úhlopříčky (každý kus toku vidět aspoň do VIS_RANGE).
static func _vis_end(m: Mesh) -> float:
	var ab := m.get_aabb()
	return VIS_RANGE + Vector2(ab.size.x, ab.size.z).length() * 0.5


func _material(ntex: Texture2D, flow: float, look: String) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load(SHADER_HQ if _hq else SHADER_LO)
	m.set_shader_parameter("wave_tex", ntex)
	m.set_shader_parameter("flow_speed", flow)
	var lk: Array = LOOK[look]
	m.set_shader_parameter("shallow_color", lk[0])
	m.set_shader_parameter("deep_color", lk[1])
	m.set_shader_parameter("absorb", lk[2])
	m.set_meta("flowing", flow > 0.01)
	_mats.append(m)
	return m


## Varianta shaderu podle předvolby: od Vysoké (`GameSettings.gfx_quality` ≥ 2 = global `gfx_quality`) lom a odraz
## okolí (screen texture = kopie obrazu za snímek), Nízká / Střední levná hladina bez ní. Čte se ze static var –
## `global_shader_parameter_get` mimo editor nevrací hodnotu. Než se grafika poprvé použije, platí výchozí Vysoká.
## Renderer Mobile (slabá grafika) má vždy levnou variantu – tam je kopie obrazu dražší a jas screen texture
## se kvůli jeho uložení barev (luminance multiplier) liší.
static func _want_hq() -> bool:
	if _mobile_renderer():
		return false
	return GameSettings.gfx_quality > 1.5


static func _mobile_renderer() -> bool:
	var args := OS.get_cmdline_args()
	var i := args.find("--rendering-method")
	if i >= 0 and i + 1 < args.size():
		return args[i + 1] == "mobile"
	return String(ProjectSettings.get_setting("rendering/renderer/rendering_method", "forward_plus")) == "mobile"


## Při změně předvolby za běhu (Nastavení) vymění shader všem materiálům vody.
func _sync_quality() -> void:
	var hq := _want_hq()
	if hq == _hq:
		return
	_hq = hq
	var sh: Shader = load(SHADER_HQ if hq else SHADER_LO)
	for m in _mats:
		m.shader = sh


## Vlnová textura (RGBA8 256², bezešvá, mipmapy): RG = sklon výškového šumu (normalizovaný na RMS 1, kódovaný
## 0,5 ± s/6 – shader pak drží amplitudu vlnek v radiánech), B = výška šumu (pěna, praskliny ledu), A = druhý šum
## (sníh na ledu). Jedno čtení dá normálu i šum – levná varianta má na hladinu 2 čtení vlnek + hloubku.
static func _wave_texture() -> ImageTexture:
	const N := 256
	var noise := FastNoiseLite.new()
	noise.seed = 7
	noise.frequency = 0.05
	noise.fractal_octaves = 3
	var h := noise.get_seamless_image(N, N)
	h.convert(Image.FORMAT_L8)
	noise.seed = 31
	noise.frequency = 0.03
	var h2 := noise.get_seamless_image(N, N)
	h2.convert(Image.FORMAT_L8)
	var hb := h.get_data()
	var h2b := h2.get_data()
	var hv := PackedFloat32Array()
	hv.resize(N * N)
	for i in N * N:
		hv[i] = float(hb[i]) / 255.0
	var sx := PackedFloat32Array()
	var sy := PackedFloat32Array()
	sx.resize(N * N)
	sy.resize(N * N)
	var ss := 0.0
	for y in N:
		for x in N:
			var gx := hv[y * N + (x + 1) % N] - hv[y * N + (x + N - 1) % N]
			var gy := hv[((y + 1) % N) * N + x] - hv[((y + N - 1) % N) * N + x]
			sx[y * N + x] = gx
			sy[y * N + x] = gy
			ss += gx * gx + gy * gy
	var k := 1.0 / maxf(sqrt(ss / float(N * N) * 0.5), 1e-6)
	var bytes := PackedByteArray()
	bytes.resize(N * N * 4)
	for i in N * N:
		bytes[i * 4] = clampi(int((0.5 + sx[i] * k / 6.0) * 255.0 + 0.5), 0, 255)
		bytes[i * 4 + 1] = clampi(int((0.5 + sy[i] * k / 6.0) * 255.0 + 0.5), 0, 255)
		bytes[i * 4 + 2] = hb[i]
		bytes[i * 4 + 3] = h2b[i]
	var img := Image.create_from_data(N, N, false, Image.FORMAT_RGBA8, bytes)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## Je konec úseku `si` (`which` 0 = začátek, -1 = konec) volný? Volný = nenavazuje na konec jiného úseku (data toky
## dělí na kusy) – pramen, ústí do jiného toku nebo konec v poli; tam pás dozní, aby hladina nekončila hranou.
func _free_end(si: int, which: int) -> bool:
	var pts: PackedVector3Array = streams[si]["pts"]
	var e := pts[0] if which == 0 else pts[pts.size() - 1]
	var e2 := Vector2(e.x, e.z)
	for c in _cells.get(Vector2i(floori(e.x / CELL), floori(e.z / CELL)), []):
		if c[0] == si:
			continue
		var op: PackedVector3Array = streams[c[0]]["pts"]
		for q in [op[0], op[op.size() - 1]]:
			if e2.distance_to(Vector2(q.x, q.z)) < JOIN_DIST:
				return false
	return true


## Pás hladiny podél osy: v každém bodě dva vrcholy (vlevo / vpravo) ve výšce hladiny + `y_ofs` (posun podle pořadí
## toku: úseky různých toků se na soutocích překrývají – stejná výška by blikala).
## UV = metry (po proudu, napříč od osy), UV2 = (polovina šířky, násobek rychlosti proudu ze sklonu hladiny),
## TANGENT = směr toku (shader: vlnky a pěna tečou po proudu), COLOR.a = doznění volného konce (`fade_a`, `fade_b`:
## začátek / konec pásu volný → alfa a šířka ke konci klesají, END_FADE m, nejvýš třetina délky).
func _ribbon(st: Dictionary, y_ofs := 0.0, fade_a := false, fade_b := false) -> ArrayMesh:
	var pts: PackedVector3Array = st["pts"]
	var hw: float = st["half_w"]
	var n := pts.size()
	var v := PackedVector3Array()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var nn := PackedVector3Array()
	var tg := PackedFloat32Array()
	var cc := PackedColorArray()
	var idx := PackedInt32Array()
	var along := 0.0
	var dy := Vector3(0.0, y_ofs, 0.0)
	var total := 0.0
	for i in range(1, n):
		total += Vector2(pts[i].x - pts[i - 1].x, pts[i].z - pts[i - 1].z).length()
	var fl := minf(END_FADE, total / 3.0) if n >= 3 and total >= END_FADE * 1.5 else 0.0   # krátké kusy celé
	for i in n:
		var a := pts[maxi(i - 1, 0)]
		var b := pts[mini(i + 1, n - 1)]
		var tng := Vector3(b.x - a.x, 0.0, b.z - a.z).normalized()
		var side := Vector3(-tng.z, 0.0, tng.x) * hw
		if i > 0:
			along += Vector2(pts[i].x - pts[i - 1].x, pts[i].z - pts[i - 1].z).length()
		# sklon hladiny přes ±3 body (data jsou schodovitá) → rychlost proudu ~ √sklon (peřej / tůň)
		var a3 := pts[maxi(i - 3, 0)]
		var b3 := pts[mini(i + 3, n - 1)]
		var run := Vector2(b3.x - a3.x, b3.z - a3.z).length()
		var slope := maxf(a3.y - b3.y, 0.0) / maxf(run, 0.5)
		var sm := clampf(0.55 + 0.45 * sqrt(slope / SLOPE_REF), 0.5, 2.2)
		var fd := 1.0
		if fade_a and fl > 0.01:
			fd = minf(fd, along / fl)
		if fade_b and fl > 0.01:
			fd = minf(fd, (total - along) / fl)
		fd = clampf(fd, 0.0, 1.0)
		side *= lerpf(0.55, 1.0, fd)                # zúžení ke konci (shader bere šířku z UV, okraj zůstane měkký)
		cc.append(Color(1, 1, 1, fd))
		cc.append(Color(1, 1, 1, fd))
		v.append(pts[i] - side + dy)
		v.append(pts[i] + side + dy)
		var hwi := side.length()
		uv.append(Vector2(along, -hwi))
		uv.append(Vector2(along, hwi))
		uv2.append(Vector2(hwi, sm))
		uv2.append(Vector2(hwi, sm))
		nn.append(Vector3.UP)
		nn.append(Vector3.UP)
		tg.append_array([tng.x, 0.0, tng.z, 1.0, tng.x, 0.0, tng.z, 1.0])
	for i in n - 1:
		var k := i * 2
		idx.append_array([k, k + 2, k + 1, k + 1, k + 2, k + 3])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_NORMAL] = nn
	arr[Mesh.ARRAY_TEX_UV] = uv
	arr[Mesh.ARRAY_TEX_UV2] = uv2
	arr[Mesh.ARRAY_TANGENT] = tg
	arr[Mesh.ARRAY_COLOR] = cc
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


# ------------------------------------------------------------------ dotazy

## Voda v bodě: {depth (m, 0 = sucho), name, kind ("river", "stream", …, "pond"), level}.
func info_at(x: float, z: float) -> Dictionary:
	var best := {"depth": 0.0, "name": "", "kind": "", "level": -INF}
	var key := Vector2i(floori(x / CELL), floori(z / CELL))
	var p := Vector2(x, z)
	for e in _cells.get(key, []):
		var st: Dictionary = streams[e[0]]
		var pts: PackedVector3Array = st["pts"]
		var a := pts[e[1]]
		var b := pts[e[1] + 1]
		var a2 := Vector2(a.x, a.z)
		var ab := Vector2(b.x, b.z) - a2
		var t := clampf((p - a2).dot(ab) / maxf(ab.length_squared(), 1e-6), 0.0, 1.0)
		if p.distance_to(a2 + ab * t) > float(st["half_w"]):
			continue
		if _dry(e[0]):
			continue                                 # M8.7: vyschlé koryto – žádná voda
		var level := lerpf(a.y, b.y, t) + level_ofs[e[0]]
		var depth := level - terrain.height_at(x, z)
		if depth > best["depth"]:
			best = {"depth": depth, "name": st["name"], "kind": st["kind"], "level": level}
	for pd in ponds:
		if (pd["aabb"] as Rect2).has_point(p) and Geometry2D.is_point_in_polygon(p, pd["poly"]):
			var depth: float = pd["level"] - terrain.height_at(x, z)
			if depth > best["depth"]:
				best = {"depth": depth, "name": pd["name"], "kind": "pond", "level": pd["level"]}
	return best


## Nejbližší bod tekoucí vody do `r` m (pro šumění potoka): [bod, druh] nebo [].
func nearest_stream(pos: Vector3, r: float) -> Array:
	var best := []
	var bd := r
	var p := Vector2(pos.x, pos.z)
	var c0 := Vector2i(floori(pos.x / CELL), floori(pos.z / CELL))
	var reach := ceili(r / CELL)
	var seen := {}
	for dx in range(-reach, reach + 1):
		for dz in range(-reach, reach + 1):
			for e in _cells.get(c0 + Vector2i(dx, dz), []):
				var k: int = e[0] * 100000 + e[1]
				if seen.has(k):
					continue
				seen[k] = true
				if _dry(e[0]):
					continue                         # M8.7: vyschlý potok nešumí
				var st: Dictionary = streams[e[0]]
				var pts: PackedVector3Array = st["pts"]
				var a := pts[e[1]]
				var b := pts[e[1] + 1]
				var q := Geometry3D.get_closest_point_to_segment(pos, a, b)
				var d := Vector2(q.x, q.z).distance_to(p)
				if d < bd:
					bd = d
					best = [q, st["kind"], _brook_db(e[0])]
	return best


## M8.7: vyschlé koryto (jen s vodní bilancí).
func _dry(si: int) -> bool:
	var sw: SoilWater = world.soil_water if world != null else null
	return sw != null and sw.active() and si < sw.st_dry.size() and sw.st_dry[si] == 1


## M8.7: o kolik dB hlasitěji šumí úsek při velké vodě (tišeji při malé), 0 bez bilance.
func _brook_db(si: int) -> float:
	var sw: SoilWater = world.soil_water if world != null else null
	if sw == null or not sw.active() or si >= sw.st_q.size():
		return 0.0
	var rel := sw.st_q[si] / maxf(sw.st_qn[si], 1e-6)
	return clampf(6.0 * log(maxf(rel, 0.05)) / log(4.0), -10.0, BROOK_DB_MAX)


## Nejbližší úsek toku do `r` m od bodu (-1 = žádný) – bez alokací pole (jen dotaz do mřížky).
func _stream_near(x: float, z: float, r: float) -> int:
	var key := Vector2i(floori(x / CELL), floori(z / CELL))
	var p := Vector2(x, z)
	var best := -1
	var bd := r
	for e in _cells.get(key, []):
		var pts: PackedVector3Array = streams[e[0]]["pts"]
		var a := pts[e[1]]
		var b := pts[e[1] + 1]
		var a2 := Vector2(a.x, a.z)
		var ab := Vector2(b.x, b.z) - a2
		var t := clampf((p - a2).dot(ab) / maxf(ab.length_squared(), 1e-6), 0.0, 1.0)
		var d := p.distance_to(a2 + ab * t)
		if d < bd:
			bd = d
			best = e[0]
	return best


## M8.7: průtok (m³/s) nejbližšího toku do 30 m (0 = žádný tok / vyschlý). Bez bilance normál podle druhu.
func flow_at(x: float, z: float) -> float:
	var si := _stream_near(x, z, STREAM_NEAR_M)
	if si < 0:
		return 0.0
	var sw: SoilWater = world.soil_water if world != null else null
	if sw != null and sw.active() and si < sw.st_q.size():
		return 0.0 if sw.st_dry[si] == 1 else sw.st_q[si]
	return float(FLOW_NOMINAL.get(String(streams[si]["kind"]), 0.03))


## M8.7: hladina nejbližšího toku do 30 m vůči normálu (m; + velká voda, − sucho). Bez bilance 0.
func level_at(x: float, z: float) -> float:
	var si := _stream_near(x, z, STREAM_NEAR_M)
	var sw: SoilWater = world.soil_water if world != null else null
	if si < 0 or sw == null or not sw.active() or si >= sw.st_level.size():
		return 0.0
	return sw.st_level[si]


## M8.7: vzhled hladin (klient): plynule k cíli z bilance, jen když se změní (instance uniformy).
func _update_streams_vis() -> void:
	var sw: SoilWater = world.soil_water if world != null else null
	var on := sw != null and sw.active() and sw.st_level.size() == streams.size()
	for si in _stream_mi.size():
		var mi := _stream_mi[si]
		if mi == null:
			continue
		var lv := sw.st_level[si] if on else 0.0
		var tb := sw.st_turb[si] if on else 0.0
		var fl := clampf(sqrt(sw.st_q[si] / maxf(sw.st_qn[si], 1e-6)), 0.3, 2.0) if on else 1.0
		var dry := on and sw.st_dry[si] == 1
		var nl := move_toward(level_ofs[si], lv, STREAM_VIS_RATE)
		var nt := move_toward(_turb_vis[si], tb, TURB_VIS_RATE)
		var nf := move_toward(_flow_vis[si], fl, FLOW_VIS_RATE)
		if absf(nl - level_ofs[si]) > 0.002 or absf(nt - _turb_vis[si]) > 0.005 or absf(nf - _flow_vis[si]) > 0.01:
			level_ofs[si] = nl
			_turb_vis[si] = nt
			_flow_vis[si] = nf
			mi.set_instance_shader_parameter("level_ofs", nl)
			mi.set_instance_shader_parameter("turbid", nt)
			mi.set_instance_shader_parameter("flow_mult", nf)
		if mi.visible == dry:
			mi.visible = not dry


# ------------------------------------------------------------------ led, vlnky, brodění hráčů

func _process(delta: float) -> void:
	var __t0 := Tests.prof_t0()
	_process_impl(delta)
	Tests.prof_add("water", __t0)


func _process_impl(delta: float) -> void:
	if world == null or world.clock == null:
		return
	_tick += delta
	if _tick < 0.2:
		return
	_tick = 0.0
	# hráči ve vodě (Player.wade brzdí chůzi)
	for pl in world.players.values():
		var pp: Vector3 = pl.global_position
		var inf := info_at(pp.x, pp.z)
		pl.wade = 0.0 if pl.car or pl.horse else maxf(float(inf["depth"]), 0.0) * (1.0 - ice_flow)
		pl.water_level = float(inf["level"])
		# teplota vody (M5.2): sezóna + vzduch – chladí tělo ve vodě (Player._update_body)
		if world.weather != null and world.clock != null:
			pl.water_temp = Koupaliste.water_temp(world.clock.day_of_year(), world.weather.temp)
	# zamrzání podle teploty (herní čas): rybník pod −1 °C, potok pod −5 °C, tání nad nulou
	var now: float = world.clock.minutes
	if _last_min < 0.0:
		_last_min = now
		var t0: float = world.micro.temp_valley() if world.micro != null else world.weather.temp   # M8.9: nádrže leží v údolí
		ice = clampf((-t0 - POND_FREEZE_C) / POND_FREEZE_SPAN, 0.0, 1.0)
		ice_flow = clampf((-t0 - STREAM_FREEZE_C) / STREAM_FREEZE_SPAN, 0.0, 1.0)
	var dh := clampf((now - _last_min) / 60.0, 0.0, 48.0)
	_last_min = now
	var temp: float = world.micro.temp_valley() if world.micro != null else world.weather.temp   # M8.9: teplota u vody (inverze)
	ice = move_toward(ice, clampf((-temp - POND_FREEZE_C) / POND_FREEZE_SPAN, 0.0, 1.0), dh * ICE_RATE_H)
	ice_flow = move_toward(ice_flow, clampf((-temp - STREAM_FREEZE_C) / STREAM_FREEZE_SPAN, 0.0, 1.0), dh * ICE_FLOW_RATE_H)
	_vis_tick += 0.2
	if _vis_tick >= STREAM_VIS_S:
		_vis_tick = 0.0
		_update_streams_vis()                     # M8.7: hladina, kalnost, proud podle průtoku
		_sync_quality()                           # předvolba změněná v Nastavení → jiná varianta shaderu
	var waves := 1.0 + world.weather.rain * WAVES_RAIN + clampf(world.weather.wind / WAVES_WIND_FULL, 0.0, 1.0) * WAVES_WIND
	var drops: float = world.weather.rain if world.weather.temp > 0.5 else 0.0   # kapky na hladině (ne sníh)
	for m in _mats:
		var ic := ice_flow if m.get_meta("flowing") else ice
		m.set_shader_parameter("ice", ic)
		m.set_shader_parameter("snow", world.weather.snow_cover * ic)
		m.set_shader_parameter("wave_scale", waves)
		m.set_shader_parameter("rain", drops)
