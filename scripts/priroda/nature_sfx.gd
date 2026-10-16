## Zvuky přírody generované za běhu (hra nemá zvukové soubory): déšť, vítr, hrom, hlasy zvířat a ptáků,
## kopyta koně, bzučení včel. Každý zvuk se vyrobí jednou a sdílí (static cache).
## Zvuky zvířat přehrává Animal / Bird / Horse přes AudioStreamPlayer3D (`NatureSfx.player3d`).
##
## M8.18 Zvuková krajina (`Soundscape`): ptačí chorál (drozd, pěnkava, sýkora, červenka, budníček, strakapoud, hřivnáč,
## kukačka, skřivan, žluva, puštík), hmyz (cvrček, kobylka, bzučení louky, komár), žáby a ropuchy, pes a kohout, šumění
## korun (listnáče šustí, jehličnany syčí) a práce u domů (sekačka, hrábě, lopata na sníh). Každý hlas = charakteristický
## motiv (frekvenční obálky, trylky, opakování), **ne nahrávka**; varianty ze seedu (`synth(name, variant)`).
## `synth` je čistá statická funkce (bez uzlů) → `Soundscape` ji volá ve vlákně `WorkerThreadPool` po kouscích při startu
## a hotová PCM data jen vloží do cache (`put_pcm`) – bez záseku hlavního vlákna. `get_variant` je záloha (syntéza hned).
class_name NatureSfx
extends RefCounted

const RATE := Sfx.RATE

static var _cache := {}


static func get_stream(name: String) -> AudioStreamWAV:
	if _cache.has(name):
		return _cache[name]
	var s: AudioStreamWAV
	match name:
		"rain": s = _loop(_rain(), true)
		"wind": s = _loop(_wind(), true)
		"thunder": s = _loop(_thunder(), false)
		"crow": s = _loop(_crow(), false)
		"blackbird": s = _loop(_blackbird(), false)
		"swallow": s = _loop(_swallow(), false)
		"deer_bark": s = _loop(_deer_bark(), false)
		"boar_grunt": s = _loop(_boar_grunt(), false)
		"boar_squeal": s = _loop(_boar_squeal(), false)
		"bees": s = _loop(_bees(), true)
		"neigh": s = _loop(_neigh(), false)
		"snort": s = _loop(_snort(), false)
		"hoof": s = _loop(_hoof(false), false)
		"hoof_soft": s = _loop(_hoof(true), false)
		"flap": s = _loop(_flap(), false)
		"buzzard": s = _loop(_buzzard(), false)
		"brook": s = _loop(_brook(), true)
		"splash": s = _loop(_splash(), false)
		_:
			if SYNTH_LOOPED.has(name):
				s = _loop(synth(name, 0), bool(SYNTH_LOOPED[name]))
				_cache[name] = s
				return s
			push_warning("NatureSfx: neznámý zvuk %s" % name)
			s = _loop(PackedFloat32Array([0.0]), false)
	_cache[name] = s
	return s


## M8.18: zvuky z `synth` → smyčka? (true = smyčka). Klíč varianty v cache: „jméno#v“.
const SYNTH_LOOPED := {
	"song_thrush": false, "chaffinch": false, "great_tit": false, "robin": false, "chiffchaff": false,
	"woodpecker": false, "woodpigeon": false, "cuckoo": false, "skylark": true, "oriole": false, "tawny_owl": false,
	"cricket": false, "bushcricket": false, "meadow_hum": true, "mosquito": true, "frog": false, "toad": false,
	"dog_bark": false, "rooster": false, "canopy_rustle": true, "canopy_hiss": true, "mower": false, "rake": false,
	"shovel": false,
}


## Klíč varianty v cache.
static func variant_key(name: String, v: int) -> String:
	return name if v <= 0 else "%s#%d" % [name, v]


static func has_stream(key: String) -> bool:
	return _cache.has(key)


## Varianta zvuku (0 = základní); není-li v cache (Soundscape ji ještě nesyntetizoval ve vlákně), vyrobí se hned.
static func get_variant(name: String, v: int) -> AudioStreamWAV:
	var key := variant_key(name, v)
	if _cache.has(key):
		return _cache[key]
	if v <= 0 or not SYNTH_LOOPED.has(name):
		return get_stream(name)
	var s := _loop(synth(name, v), bool(SYNTH_LOOPED[name]))
	_cache[key] = s
	return s


## PCM 16 bit ze vzorků (smí běžet ve vlákně – nesahá na uzly ani zdroje).
static func pcm16(samples: PackedFloat32Array) -> PackedByteArray:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32000.0))
	return data


## Vloží hotová PCM data (z vlákna) do cache jako AudioStreamWAV (hlavní vlákno, levné).
static func put_pcm(key: String, data: PackedByteArray, looped: bool) -> void:
	if _cache.has(key):
		return
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = RATE
	s.data = data
	if looped:
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_end = data.size() / 2
	_cache[key] = s


## 3D přehrávač zvuku pro zvíře (přidá se jako potomek `parent`).
static func player3d(parent: Node3D, max_dist := 80.0, vol := 0.0) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.max_distance = max_dist
	p.unit_size = 8.0
	p.volume_db = vol
	p.attenuation_filter_cutoff_hz = 9000.0
	parent.add_child(p)
	return p


static func _loop(samples: PackedFloat32Array, looped: bool) -> AudioStreamWAV:
	var s := Sfx._wav_static(samples)
	if looped:
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_end = samples.size()
	return s


# ------------------------------------------------------------------ počasí

## Déšť: šum s důrazem na vysoké frekvence + náhodné kapky; smyčka 3 s (konce se prolnou).
static func _rain() -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var n := RATE * 3
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	var lp2 := 0.0
	for i in n:
		var w := rng.randf_range(-1.0, 1.0)
		lp += 0.35 * (w - lp)
		lp2 += 0.04 * (w - lp2)
		out[i] = (w - lp) * 0.25 + lp * 0.18 + lp2 * 0.35
	for k in 900:
		var at := rng.randi() % n
		var f := rng.randf_range(1800.0, 5200.0)
		var a := rng.randf_range(0.05, 0.25)
		for j in 260:
			var t := float(j) / RATE
			out[(at + j) % n] += sin(TAU * f * t * (1.0 - t * 8.0)) * exp(-t * 90.0) * a
	return _crossfade(out, 2000)


## Šumění potoka: pásmový šum + drobné „bublinky“ (krátké stoupající tóny); smyčka 4 s.
static func _brook() -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 21
	var n := RATE * 4
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	var lp2 := 0.0
	for i in n:
		var w := rng.randf_range(-1.0, 1.0)
		lp += 0.25 * (w - lp)
		lp2 += 0.05 * (lp - lp2)
		var t := float(i) / RATE
		var mod := 0.75 + 0.25 * sin(TAU * 0.7 * t) * sin(TAU * 1.9 * t + 0.4)
		out[i] = (lp - lp2) * 0.9 * mod
	for k in 420:
		var at := rng.randi() % n
		var f0 := rng.randf_range(500.0, 1600.0)
		var a := rng.randf_range(0.03, 0.12)
		var ln := rng.randi_range(250, 700)
		var ph := 0.0
		for j in ln:
			var t := float(j) / RATE
			ph += TAU * f0 * (1.0 + t * 25.0) / RATE
			out[(at + j) % n] += sin(ph) * exp(-t * 60.0) * a
	return _crossfade(out, 3000)


## Šplouchnutí (krok ve vodě).
static func _splash() -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 23
	var n := int(RATE * 0.35)
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		lp += 0.45 * (rng.randf_range(-1.0, 1.0) - lp)
		var env := minf(t * 60.0, 1.0) * exp(-t * 11.0)
		out[i] = lp * env * 0.9
	for k in 6:
		var at := rng.randi_range(800, n - 1200)
		var f0 := rng.randf_range(700.0, 1500.0)
		var ph := 0.0
		for j in 900:
			var t := float(j) / RATE
			ph += TAU * f0 * (1.0 + t * 18.0) / RATE
			out[at + j] += sin(ph) * exp(-t * 45.0) * 0.18
	return out


static func _wind() -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var n := RATE * 6
	var out := PackedFloat32Array()
	out.resize(n)
	var y := 0.0
	var y2 := 0.0
	for i in n:
		var t := float(i) / n
		y += 0.02 * (rng.randf_range(-1.0, 1.0) - y)
		y2 += 0.2 * (y - y2)
		var mod := 0.6 + 0.4 * sin(TAU * t * 2.0) * sin(TAU * t * 3.0 + 1.0)
		out[i] = y2 * 6.0 * mod
	return _crossfade(out, 4000)


## Hrom: ostré prasknutí (blízký blesk) a dlouhé dunění s náhodnými vlnami.
static func _thunder() -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var n := int(RATE * 4.5)
	var out := PackedFloat32Array()
	out.resize(n)
	var y := 0.0
	var yb := 0.0
	var swell := 0.0
	for i in n:
		var t := float(i) / RATE
		var w := rng.randf_range(-1.0, 1.0)
		y += 0.5 * (w - y)
		yb += 0.012 * (w - yb)
		if i % 2000 == 0:
			swell = rng.randf_range(0.4, 1.0)
		var crack := y * exp(-t * 9.0) * 0.7
		var rumble := yb * 9.0 * minf(t * 4.0, 1.0) * exp(-t * 0.75) * swell
		out[i] = crack + rumble
	return out


# ------------------------------------------------------------------ ptáci

## Vrána: „kráá“ – drsný tón ~ 550 Hz s formantem a šumem, dvakrát.
static func _crow() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var rng := RandomNumberGenerator.new()
	rng.seed = 21
	for rep in 2:
		var n := int(RATE * 0.36)
		var ph := 0.0
		for i in n:
			var t := float(i) / n
			var f := lerpf(640.0, 520.0, t) * (1.0 + 0.03 * sin(t * 90.0))
			ph += TAU * f / RATE
			var saw := fposmod(ph / TAU, 1.0) * 2.0 - 1.0
			var env := smoothstep(0.0, 0.08, t) * (1.0 - smoothstep(0.7, 1.0, t))
			out.append((saw * 0.5 + sin(ph * 2.0) * 0.3 + rng.randf_range(-1.0, 1.0) * 0.25) * env * 0.55)
		for i in int(RATE * 0.22):
			out.append(0.0)
	return out


## Kos: melodická fráze flétnových tónů s glissandy a závěrečným cvrlikáním.
static func _blackbird() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var notes := [[1850.0, 2100.0, 0.18], [2400.0, 2250.0, 0.14], [1700.0, 1650.0, 0.22], [2600.0, 3100.0, 0.09],
		[2900.0, 2500.0, 0.09], [2100.0, 2300.0, 0.16], [3400.0, 3800.0, 0.05], [3600.0, 3300.0, 0.05], [3900.0, 4200.0, 0.05]]
	var ph := 0.0
	for nt in notes:
		var n := int(RATE * float(nt[2]))
		for i in n:
			var t := float(i) / n
			ph += TAU * lerpf(nt[0], nt[1], t) / RATE
			var env := sin(PI * t)
			out.append((sin(ph) + 0.15 * sin(ph * 2.0)) * env * 0.4)
		for i in int(RATE * 0.04):
			out.append(0.0)
	return out


## Vlaštovka: rychlé švitoření (krátké cvrky 3–6 kHz).
static func _swallow() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var rng := RandomNumberGenerator.new()
	rng.seed = 8
	var ph := 0.0
	for k in 14:
		var f0 := rng.randf_range(3000.0, 5500.0)
		var f1 := f0 + rng.randf_range(-1500.0, 1500.0)
		var n := int(RATE * rng.randf_range(0.03, 0.07))
		for i in n:
			var t := float(i) / n
			ph += TAU * lerpf(f0, f1, t) / RATE
			out.append(sin(ph) * sin(PI * t) * 0.3)
		for i in int(RATE * rng.randf_range(0.02, 0.08)):
			out.append(0.0)
	return out


## Káně: táhlé mňoukavé „híjé“ – tón klesající z ~2,3 kHz na 1,3 kHz.
static func _buzzard() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var n := int(RATE * 0.95)
	var ph := 0.0
	for i in n:
		var t := float(i) / n
		ph += TAU * lerpf(2300.0, 1300.0, pow(t, 0.8)) / RATE
		var env := smoothstep(0.0, 0.15, t) * (1.0 - smoothstep(0.7, 1.0, t))
		out.append((sin(ph) + 0.2 * sin(ph * 2.0) + 0.08 * sin(ph * 3.0)) * env * 0.35)
	return out


static func _flap() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	var y := 0.0
	var n := int(RATE * 0.5)
	for i in n:
		var t := float(i) / RATE
		var beat := pow(maxf(sin(TAU * 11.0 * t), 0.0), 3.0)
		y += 0.25 * (rng.randf_range(-1.0, 1.0) - y)
		out.append(y * beat * exp(-t * 2.5) * 1.4)
	return out


# ------------------------------------------------------------------ zvěř

## Srnec: štěkavý alarmní hlas „bö“ – chraplavý šum s formantem ~ 700 Hz.
static func _deer_bark() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var rng := RandomNumberGenerator.new()
	rng.seed = 31
	var n := int(RATE * 0.3)
	var ph := 0.0
	var y := 0.0
	for i in n:
		var t := float(i) / n
		ph += TAU * lerpf(420.0, 300.0, t) / RATE
		y += 0.3 * (rng.randf_range(-1.0, 1.0) - y)
		var env := smoothstep(0.0, 0.05, t) * exp(-t * 3.5)
		out.append((sin(ph) * 0.4 + sin(ph * 1.7) * 0.25 + y * 0.9) * env * 0.7)
	return out


## Divočák: krátké chrochtavé pulzy (~ 110 Hz, drsné).
static func _boar_grunt() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var rng := RandomNumberGenerator.new()
	rng.seed = 41
	var y := 0.0
	for k in 3:
		var n := int(RATE * rng.randf_range(0.12, 0.2))
		var ph := 0.0
		for i in n:
			var t := float(i) / n
			ph += TAU * lerpf(125.0, 95.0, t) / RATE
			y += 0.15 * (rng.randf_range(-1.0, 1.0) - y)
			var pulse := pow(maxf(sin(ph), 0.0), 4.0)
			out.append((pulse * 0.9 + y * 1.2) * sin(PI * t) * 0.6)
		for i in int(RATE * rng.randf_range(0.06, 0.14)):
			out.append(0.0)
	return out


static func _boar_squeal() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var n := int(RATE * 0.8)
	var ph := 0.0
	for i in n:
		var t := float(i) / n
		ph += TAU * (1100.0 + 300.0 * sin(t * 9.0)) / RATE
		var saw := fposmod(ph / TAU, 1.0) * 2.0 - 1.0
		out.append((saw * 0.4 + rng.randf_range(-1.0, 1.0) * 0.2) * sin(PI * t) * 0.5)
	return out


## Včely: bzučení roje (~ 230 Hz pila, několik včel rozladěných, amplitudová modulace).
static func _bees() -> PackedFloat32Array:
	var n := RATE * 2
	var out := PackedFloat32Array()
	out.resize(n)
	var freqs := [220.0, 228.0, 236.0, 244.0, 251.0]
	for i in n:
		var t := float(i) / RATE
		var s := 0.0
		for k in freqs.size():
			# celé počty period za smyčku (2 s) → bez lupnutí
			var f: float = round(freqs[k] * 2.0) / 2.0
			var ph := fposmod(f * t + k * 0.2, 1.0)
			s += (ph * 2.0 - 1.0) * (0.6 + 0.4 * sin(TAU * (1.5 + k * 0.5) * t))
		out[i] = s * 0.12
	return out


## Kůň: řehtání – vibráto s klesající výškou a pulzy.
static func _neigh() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var rng := RandomNumberGenerator.new()
	rng.seed = 51
	var n := int(RATE * 1.3)
	var ph := 0.0
	for i in n:
		var t := float(i) / n
		var f := lerpf(1050.0, 480.0, pow(t, 0.7)) * (1.0 + 0.06 * sin(TAU * 13.0 * t * 1.3))
		ph += TAU * f / RATE
		var saw := fposmod(ph / TAU, 1.0) * 2.0 - 1.0
		var pulse := 0.7 + 0.3 * sin(TAU * 11.0 * t)
		var env := smoothstep(0.0, 0.05, t) * (1.0 - smoothstep(0.75, 1.0, t))
		out.append((saw * 0.35 + sin(ph) * 0.3 + rng.randf_range(-1.0, 1.0) * 0.08) * pulse * env * 0.55)
	return out


static func _snort() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var rng := RandomNumberGenerator.new()
	rng.seed = 52
	var y := 0.0
	var n := int(RATE * 0.45)
	for i in n:
		var t := float(i) / n
		y += 0.12 * (rng.randf_range(-1.0, 1.0) - y)
		var flutter := 0.6 + 0.4 * sin(TAU * 38.0 * t * 0.45)
		out.append(y * 3.0 * flutter * smoothstep(0.0, 0.1, t) * (1.0 - t))
	return out


## Kopyto: tvrdé klapnutí (silnice) nebo tupý dusot (tráva, lesní cesta).
static func _hoof(soft: bool) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var rng := RandomNumberGenerator.new()
	rng.seed = 61 if soft else 62
	var n := int(RATE * 0.09)
	var y := 0.0
	for i in n:
		var t := float(i) / RATE
		y += (0.08 if soft else 0.5) * (rng.randf_range(-1.0, 1.0) - y)
		var tone := 0.0 if soft else sin(TAU * 820.0 * t) * 0.5 + sin(TAU * 1330.0 * t) * 0.25
		out.append((tone + y * (3.0 if soft else 1.0)) * exp(-t * (45.0 if soft else 70.0)) * 0.8)
	return out


static func _crossfade(s: PackedFloat32Array, k: int) -> PackedFloat32Array:
	var n := s.size()
	var out := s.slice(0, n - k)
	for i in k:
		var a := float(i) / k
		out[i] = s[i] * a + s[n - k + i] * (1.0 - a)
	return out


# ------------------------------------------------------------------ M8.18 zvuková krajina (syntéza, smí běžet ve vlákně)

## Vzorky zvuku `name` ve variantě `v` (seed = jméno + varianta). Čistá funkce – žádné uzly, žádná cache.
static func synth(name: String, v: int) -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(name) + v * 7919
	match name:
		"song_thrush": return _song_thrush(rng)
		"chaffinch": return _chaffinch(rng)
		"great_tit": return _great_tit(rng)
		"robin": return _robin(rng)
		"chiffchaff": return _chiffchaff(rng)
		"woodpecker": return _woodpecker(rng)
		"woodpigeon": return _woodpigeon(rng)
		"cuckoo": return _cuckoo(rng)
		"skylark": return _skylark(rng)
		"oriole": return _oriole(rng)
		"tawny_owl": return _tawny_owl(rng)
		"cricket": return _cricket(rng)
		"bushcricket": return _bushcricket(rng)
		"meadow_hum": return _meadow_hum(rng)
		"mosquito": return _mosquito(rng)
		"frog": return _frog(rng, v)
		"toad": return _toad(rng)
		"dog_bark": return _dog_bark(rng)
		"rooster": return _rooster(rng)
		"canopy_rustle": return _canopy(rng, false)
		"canopy_hiss": return _canopy(rng, true)
		"mower": return _mower(rng)
		"rake": return _rake(rng)
		"shovel": return _shovel(rng)
	return PackedFloat32Array([0.0])


## Tónový úsek (sinus + 2. harmonická) s glissandem f0 → f1, obálkou sin(πt) a volitelným vibratem.
static func _seg(out: PackedFloat32Array, f0: float, f1: float, dur: float, amp: float, h2 := 0.15,
		vib_hz := 0.0, vib_d := 0.0) -> void:
	var n := maxi(int(RATE * dur), 8)
	var ph := 0.0
	for i in n:
		var t := float(i) / n
		var f := lerpf(f0, f1, t) * (1.0 + vib_d * sin(TAU * vib_hz * t * dur))
		ph += TAU * f / RATE
		out.append((sin(ph) + h2 * sin(ph * 2.0)) * sin(PI * t) * amp)


static func _gap(out: PackedFloat32Array, dur: float) -> void:
	for i in int(RATE * dur):
		out.append(0.0)


## Drozd zpěvný: krátké motivy (2–4 tóny 1,8–5 kHz), každý zopakovaný 2–3× – „opakuje po sobě“.
static func _song_thrush(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for m in 4:
		var notes := []
		for k in rng.randi_range(2, 4):
			var f := rng.randf_range(1800.0, 5000.0)
			notes.append([f, f * rng.randf_range(0.8, 1.25), rng.randf_range(0.04, 0.11)])
		for r in rng.randi_range(2, 3):
			for nt in notes:
				_seg(out, nt[0], nt[1], nt[2], 0.38)
				_gap(out, 0.025)
			_gap(out, 0.09)
		_gap(out, rng.randf_range(0.25, 0.45))
	return out


## Pěnkava: zrychlující klesající trylek „čiči-čerčer-čvíí-ču“ s rozmáchlým koncem.
static func _chaffinch(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var f := rng.randf_range(4300.0, 4900.0)
	for k in 7:
		_seg(out, f, f * 0.85, 0.07 - k * 0.004, 0.32)
		_gap(out, 0.03)
		f *= 0.97
	f = rng.randf_range(3000.0, 3400.0)
	for k in 4:
		_seg(out, f * 1.1, f * 0.8, 0.05, 0.34)
		_gap(out, 0.02)
	_seg(out, 2200.0, rng.randf_range(4200.0, 4800.0), 0.12, 0.36)
	_seg(out, 3600.0, 2400.0, 0.1, 0.3)
	return out


## Sýkora koňadra: „ci-ci-bé“ (vysoký a nižší tón) opakovaně.
static func _great_tit(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var hi := rng.randf_range(5200.0, 6200.0)
	var lo := rng.randf_range(3400.0, 4000.0)
	for r in rng.randi_range(4, 6):
		_seg(out, hi, hi * 0.96, 0.07, 0.3, 0.05)
		_gap(out, 0.05)
		_seg(out, lo, lo * 0.97, 0.11, 0.32, 0.1)
		_gap(out, 0.09)
	return out


## Červenka: tenká vysoká melancholická píseň – rychlé glissanda a krátké trylky 3–7 kHz.
static func _robin(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for k in rng.randi_range(11, 15):
		var f := rng.randf_range(3000.0, 7000.0)
		if rng.randf() < 0.3:
			for j in 4:
				_seg(out, f, f * 1.08, 0.025, 0.22, 0.05)
		else:
			_seg(out, f, f * rng.randf_range(0.7, 1.35), rng.randf_range(0.05, 0.16), rng.randf_range(0.15, 0.3), 0.05)
		_gap(out, rng.randf_range(0.01, 0.06))
	return out


## Budníček menší: „čif-čaf-čif-čaf“ – střídání dvou výšek, krátké klesající tóny.
static func _chiffchaff(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var a := rng.randf_range(5000.0, 5500.0)
	var b := rng.randf_range(4000.0, 4400.0)
	for k in rng.randi_range(8, 11):
		var f := a if (k % 2 == 0) != (rng.randf() < 0.15) else b
		_seg(out, f * 1.1, f * 0.85, 0.06, 0.3, 0.05)
		_gap(out, rng.randf_range(0.22, 0.3))
	return out


## Strakapoud – bubnování: 12–16 úderů za ~0,6 s (šum + rezonance kmene ~ 900 Hz), na konci slábne.
static func _woodpecker(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var hits := rng.randi_range(12, 16)
	var res := rng.randf_range(700.0, 1100.0)
	var step := int(RATE * rng.randf_range(0.038, 0.048))
	out.resize(step * hits + RATE / 5)
	for h in hits:
		var a := 0.75 * (1.0 - 0.5 * float(h) / hits)
		for j in step:
			var t := float(j) / RATE
			out[h * step + j] += (sin(TAU * res * t) * 0.7 + rng.randf_range(-1.0, 1.0) * 0.5) * exp(-t * 160.0) * a
	return out


## Hřivnáč: tlumené „hú-húú-hu, hu-hu“ (~ 500–600 Hz) s dechem.
static func _woodpigeon(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var f := rng.randf_range(480.0, 560.0)
	var lens := [0.25, 0.45, 0.22, 0.2, 0.2]
	for r in 2:
		for k in lens.size():
			var n := int(RATE * float(lens[k]))
			var ph := 0.0
			for i in n:
				var t := float(i) / n
				ph += TAU * f * (1.0 + 0.04 * sin(PI * t)) / RATE
				var env := smoothstep(0.0, 0.25, t) * (1.0 - smoothstep(0.6, 1.0, t))
				out.append((sin(ph) * 0.5 + sin(ph * 2.0) * 0.08 + rng.randf_range(-1.0, 1.0) * 0.04) * env)
			_gap(out, 0.12 if k != 2 else 0.35)
		_gap(out, 0.5)
	return out


## Kukačka: „ku-kú“ – dva měkké tóny (malá tercie dolů), třikrát.
static func _cuckoo(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var f := rng.randf_range(650.0, 720.0)
	for r in 3:
		_seg(out, f, f * 0.98, 0.17, 0.5, 0.2)
		_gap(out, 0.06)
		_seg(out, f * 0.82, f * 0.8, 0.3, 0.5, 0.2)
		_gap(out, rng.randf_range(0.45, 0.6))
	return out


## Skřivan polní: nepřetržité rychlé švitoření z výšky (smyčka 5 s).
static func _skylark(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var target := RATE * 5 + 2500
	while out.size() < target:
		var f := rng.randf_range(2500.0, 6500.0)
		if rng.randf() < 0.25:
			for j in rng.randi_range(3, 7):
				_seg(out, f, f * 0.92, 0.022, 0.2, 0.05)
		else:
			_seg(out, f, f * rng.randf_range(0.75, 1.3), rng.randf_range(0.03, 0.08), rng.randf_range(0.12, 0.24), 0.05)
		if rng.randf() < 0.2:
			_gap(out, 0.02)
	return _crossfade(out, 2500)


## Žluva: flétnové „dy-dli-ó“ s měkkými glissandy (~ 1,2–2 kHz).
static func _oriole(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var k := rng.randf_range(0.92, 1.08)
	_seg(out, 1400.0 * k, 1800.0 * k, 0.16, 0.42, 0.3)
	_seg(out, 2000.0 * k, 1950.0 * k, 0.12, 0.42, 0.3)
	_seg(out, 1650.0 * k, 1200.0 * k, 0.3, 0.42, 0.3)
	return out


## Puštík obecný: „húú … hu … hu-hu-hu-húúú“ (~ 380–420 Hz, třesavé tremolo na konci).
static func _tawny_owl(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var f := rng.randf_range(370.0, 420.0)
	_seg(out, f * 1.05, f, 0.8, 0.5, 0.12)
	_gap(out, rng.randf_range(1.2, 1.7))
	_seg(out, f, f * 0.98, 0.15, 0.4, 0.12)
	_gap(out, 0.3)
	var n := int(RATE * 1.1)
	var ph := 0.0
	for i in n:
		var t := float(i) / n
		ph += TAU * f * (1.02 - 0.06 * t) / RATE
		var trem := 0.55 + 0.45 * sin(TAU * 11.0 * t * 1.1)
		out.append((sin(ph) + 0.12 * sin(ph * 2.0)) * trem * smoothstep(0.0, 0.1, t) * (1.0 - smoothstep(0.7, 1.0, t)) * 0.5)
	return out


## Cvrček polní: jedno cvrknutí = 3–4 pulzy ~ 4,6 kHz (rychlost cvrkání řídí Soundscape Dolbearovým zákonem).
static func _cricket(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var f := rng.randf_range(4300.0, 4900.0)
	for k in rng.randi_range(3, 4):
		var n := int(RATE * 0.018)
		for i in n:
			var t := float(i) / n
			out.append(sin(TAU * f * float(i) / RATE) * sin(PI * t) * 0.45)
		_gap(out, 0.012)
	return out


## Kobylka zelená: bzučivý „šustot“ – rychlé pulzy (~ 30/s) nosné ~ 7–8 kHz s šumem.
static func _bushcricket(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var f := rng.randf_range(7000.0, 8000.0)
	var n := int(RATE * 0.45)
	for i in n:
		var t := float(i) / RATE
		var pulse := pow(maxf(sin(TAU * 32.0 * t), 0.0), 6.0)
		out.append((sin(TAU * f * t) * 0.6 + rng.randf_range(-1.0, 1.0) * 0.4) * pulse * 0.4
			* smoothstep(0.0, 0.05, t) * (1.0 - smoothstep(0.38, 0.45, t)))
	return out


## Bzučení louky: několik včel / much (pila 150–350 Hz) s pomalu se měnící hlasitostí (průlety); smyčka 4 s.
static func _meadow_hum(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var n := RATE * 4 + 3000
	var out := PackedFloat32Array()
	out.resize(n)
	for b in 6:
		var f := rng.randf_range(150.0, 350.0)
		var am_f := rng.randf_range(0.2, 0.9)
		var am_p := rng.randf() * TAU
		var ph := rng.randf()
		for i in n:
			var t := float(i) / RATE
			ph = fposmod(ph + f * (1.0 + 0.02 * sin(TAU * 0.7 * t + am_p)) / RATE, 1.0)
			var amp := pow(maxf(sin(TAU * am_f * t + am_p), 0.0), 2.0)
			out[i] += (ph * 2.0 - 1.0) * amp * 0.07
	var lp := 0.0
	for i in n:
		lp += 0.35 * (out[i] - lp)
		out[i] = lp
	return _crossfade(out, 3000)


## Komár: tenké kňourání ~ 600 Hz s vibratem a kolísáním (několik komárů); smyčka 2 s.
static func _mosquito(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var n := RATE * 2 + 2000
	var out := PackedFloat32Array()
	out.resize(n)
	for b in 3:
		var f := rng.randf_range(520.0, 700.0)
		var ph := 0.0
		var ap := rng.randf() * TAU
		for i in n:
			var t := float(i) / RATE
			ph += TAU * f * (1.0 + 0.015 * sin(TAU * 6.0 * t + ap)) / RATE
			out[i] += (sin(ph) * 0.6 + sin(ph * 2.0) * 0.3 + sin(ph * 3.0) * 0.15) * (0.5 + 0.5 * sin(TAU * 0.6 * t + ap)) * 0.12
	return _crossfade(out, 2000)


## Žáby: varianta 0 = skokan zelený (hlasité drnčivé „kvak-kvak-krrr“), 1 = skokan hnědý (tiché nízké „grr-grr“).
static func _frog(rng: RandomNumberGenerator, v: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var brown := v % 2 == 1
	var pulse_hz := rng.randf_range(25.0, 35.0) if brown else rng.randf_range(55.0, 75.0)
	var form := rng.randf_range(380.0, 480.0) if brown else rng.randf_range(1000.0, 1400.0)
	for k in rng.randi_range(3, 6):
		var dur := rng.randf_range(0.12, 0.22) if k < 3 or brown else rng.randf_range(0.5, 0.8)
		var n := int(RATE * dur)
		for i in n:
			var t := float(i) / RATE
			var pulse := pow(maxf(sin(TAU * pulse_hz * t), 0.0), 8.0)
			var s := sin(TAU * form * t) * 0.7 + sin(TAU * form * 0.5 * t) * 0.4
			out.append(s * pulse * sin(PI * float(i) / n) * (0.4 if brown else 0.55))
		_gap(out, rng.randf_range(0.08, 0.3))
	return out


## Ropucha obecná: tiché „kuk-kuk-kuk“ (~ 700 Hz, krátké tóny).
static func _toad(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var f := rng.randf_range(600.0, 800.0)
	for k in rng.randi_range(4, 7):
		_seg(out, f, f * 0.9, 0.06, 0.4, 0.4)
		_gap(out, rng.randf_range(0.12, 0.18))
	return out


## Pes v dálce: 2–3 štěknutí (tón 450 → 330 Hz s harmonickými a šumem).
static func _dog_bark(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var f0 := rng.randf_range(380.0, 520.0)
	var y := 0.0
	for k in rng.randi_range(2, 3):
		var n := int(RATE * rng.randf_range(0.12, 0.18))
		var ph := 0.0
		for i in n:
			var t := float(i) / n
			ph += TAU * lerpf(f0, f0 * 0.72, t) / RATE
			y += 0.3 * (rng.randf_range(-1.0, 1.0) - y)
			var saw := fposmod(ph / TAU, 1.0) * 2.0 - 1.0
			var env := smoothstep(0.0, 0.06, t) * exp(-t * 3.0)
			out.append((saw * 0.35 + sin(ph * 2.0) * 0.25 + y * 0.6) * env * 0.6)
		_gap(out, rng.randf_range(0.2, 0.35))
	return out


## Kohout: „ki-ke-ri-kíí“ – drsné (pila) úseky, poslední dlouhý s vibratem.
static func _rooster(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var k := rng.randf_range(0.9, 1.1)
	var parts := [[600.0, 700.0, 0.13], [900.0, 880.0, 0.13], [820.0, 860.0, 0.18], [1000.0, 880.0, 0.75]]
	for pi_ in parts.size():
		var p: Array = parts[pi_]
		var dur: float = p[2]
		var n := int(RATE * dur)
		var ph := 0.0
		var vib := 0.03 if pi_ == 3 else 0.0
		for i in n:
			var t := float(i) / n
			var f := lerpf(p[0], p[1], t) * k * (1.0 + vib * sin(TAU * 7.0 * t * dur))
			ph += TAU * f / RATE
			var saw := fposmod(ph / TAU, 1.0) * 2.0 - 1.0
			out.append((saw * 0.3 + sin(ph) * 0.3 + rng.randf_range(-1.0, 1.0) * 0.05) * sin(PI * t) * 1.2)
		_gap(out, 0.03)
	return out


## Šumění korun: `hiss` = jehličnany (hladký vysoký šum, „syčení“), jinak listnáče (šustění – rychle kolísající
## šum s drobným praskáním listů). Smyčka 4 s.
static func _canopy(rng: RandomNumberGenerator, hiss: bool) -> PackedFloat32Array:
	var n := RATE * 4 + 3000
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	var lp2 := 0.0
	var fl := 0.0
	for i in n:
		var t := float(i) / RATE
		var w := rng.randf_range(-1.0, 1.0)
		lp += 0.3 * (w - lp)
		lp2 += 0.02 * (w - lp2)
		var swell := 0.65 + 0.35 * sin(TAU * 0.5 * t) * sin(TAU * 0.25 * t + 1.0)
		if hiss:
			out[i] = (w - lp) * 0.32 * swell
		else:
			fl += 0.004 * (rng.randf_range(0.0, 1.0) - fl)
			var flutter := clampf(0.4 + 6.0 * (fl - 0.5) + 0.4 * sin(TAU * 9.0 * t + lp2 * 30.0), 0.1, 1.0)
			out[i] = (lp - lp2) * 0.55 * flutter * swell
	if not hiss:
		for k in 260:
			var at := rng.randi() % (n - 300)
			var a := rng.randf_range(0.03, 0.1)
			for j in 200:
				out[at + j] += rng.randf_range(-1.0, 1.0) * exp(-float(j) / 40.0) * a
	return _crossfade(out, 3000)


## Sekačka na trávu (M8.17 dřív zpomalená pila): čtyřtakt ~ 48 Hz (pulzy zapalování) + hvízdání nože ~ 190 Hz + šum;
## 0,8 s s náběhem a doběhem – hraje se po `Households.MOW_EVERY_S`, úseky se překrývají.
static func _mower(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var n := int(RATE * 0.8)
	var y := 0.0
	var f := rng.randf_range(44.0, 52.0)
	for i in n:
		var t := float(i) / RATE
		var u := float(i) / n
		var fire := pow(maxf(sin(TAU * f * t), 0.0), 6.0)
		y += 0.2 * (rng.randf_range(-1.0, 1.0) - y)
		var blade := sin(TAU * 190.0 * t) * 0.15 + sin(TAU * 380.0 * t) * 0.06
		out.append((fire * 0.8 + sin(TAU * f * 2.0 * t) * 0.15 + blade + y * 0.5) * smoothstep(0.0, 0.15, u) * (1.0 - smoothstep(0.8, 1.0, u)) * 0.6)
	return out


## Hrábě v listí: šustivý tah (šum 2–4 kHz) s drobnými cvaknutími zubů.
static func _rake(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var n := int(RATE * 0.55)
	var lp := 0.0
	for i in n:
		var u := float(i) / n
		var w := rng.randf_range(-1.0, 1.0)
		lp += 0.4 * (w - lp)
		var click := 0.6 if rng.randf() < 0.004 else 0.0
		out.append(((w - lp) * 0.5 + click * w) * sin(PI * u) * (0.7 + 0.3 * sin(TAU * 13.0 * u)) * 0.7)
	return out


## Lopata na sníh: škrábnutí (šum se zvedající se barvou) a tupé žuchnutí odhozeného sněhu.
static func _shovel(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var n := int(RATE * 0.38)
	var lp := 0.0
	for i in n:
		var u := float(i) / n
		lp += lerpf(0.1, 0.5, u) * (rng.randf_range(-1.0, 1.0) - lp)
		out.append(lp * 1.2 * sin(PI * u) * 0.6)
	_gap(out, 0.18)
	var m := int(RATE * 0.16)
	var lp2 := 0.0
	for i in m:
		var t := float(i) / RATE
		lp2 += 0.05 * (rng.randf_range(-1.0, 1.0) - lp2)
		out.append(lp2 * 5.0 * exp(-t * 25.0) * 0.6)
	return out
