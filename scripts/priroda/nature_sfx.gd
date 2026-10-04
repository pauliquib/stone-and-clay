## Zvuky přírody generované za běhu (hra nemá zvukové soubory): déšť, vítr, hrom, hlasy zvířat a ptáků,
## kopyta koně, bzučení včel. Každý zvuk se vyrobí jednou a sdílí (static cache).
## Zvuky zvířat přehrává Animal / Bird / Horse přes AudioStreamPlayer3D (`NatureSfx.player3d`).
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
			push_warning("NatureSfx: neznámý zvuk %s" % name)
			s = _loop(PackedFloat32Array([0.0]), false)
	_cache[name] = s
	return s


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
