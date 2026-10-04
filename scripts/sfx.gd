## Zvuky generované za běhu (hra nemá zvukové soubory):
## sebrání předmětu, skok, dopad, kroky, pití, jídlo, zapalovač, kašel, zvracení, pokladna,
## náraz, rozbití skla, dveře auta, píšťalka; smyčky motoru, smyku pneumatik a sirény.
class_name Sfx
extends Node

const RATE := 22050

var _players: Array[AudioStreamPlayer] = []
var _streams := {}
static var _static := {}


func _ready() -> void:
	for i in 8:
		var p := AudioStreamPlayer.new()
		p.volume_db = -8.0
		add_child(p)
		_players.append(p)
	_streams["pickup"] = _tone([880.0, 1318.5], 0.09, 0.5)
	_streams["pickup_big"] = _tone([659.3, 880.0, 1108.7, 1318.5, 1760.0], 0.08, 0.55)
	_streams["jump"] = _sweep(220.0, 420.0, 0.12, 0.25)
	_streams["land"] = _noise(0.12, 0.5, 900.0)
	_streams["step"] = _noise(0.05, 0.18, 1400.0)
	_streams["gulp"] = _gulp()
	_streams["burp"] = _burp()
	_streams["eat"] = _crunch()
	_streams["lighter"] = _lighter()
	_streams["cough"] = _cough()
	_streams["vomit"] = _vomit()
	_streams["cash"] = _tone([1567.98, 2093.0], 0.07, 0.35)
	_streams["crash"] = _noise(0.6, 1.0, 600.0)
	_streams["glass"] = _glass()
	_streams["door"] = _noise(0.15, 0.7, 300.0)
	_streams["whistle"] = _whistle()
	_streams["fail"] = _tone([392.0, 311.1, 261.6], 0.18, 0.4)
	_streams["success"] = _tone([523.3, 659.3, 784.0, 1046.5], 0.12, 0.45)
	_streams["hurt"] = _sweep(300.0, 140.0, 0.25, 0.35)
	_streams["splash"] = NatureSfx.get_stream("splash")
	# M2.1 kácení: úder sekery, motorová pila, praskání kmene, dopad stromu
	_streams["chop"] = _noise(0.09, 0.9, 1700.0)
	_streams["saw"] = _sweep(140.0, 210.0, 0.3, 0.3)
	_streams["crack"] = _noise(0.55, 1.0, 2600.0)
	_streams["thud"] = _noise(0.9, 1.0, 200.0)
	# M2.2 oheň: praskání polínek, syčení hašení
	_streams["crackle"] = _noise(0.06, 0.55, 3400.0)
	_streams["hiss"] = _noise(1.2, 0.5, 6000.0)
	# M2.8 zbraně: výstřel pušky, tětiva luku / kuše, dopad šípu
	_streams["gunshot"] = _gunshot()
	_streams["bow_shot"] = _sweep(620.0, 170.0, 0.16, 0.35)
	_streams["arrow_hit"] = _noise(0.08, 0.8, 1100.0)
	# M6.1 dron: spoušť fotoaparátu
	_streams["shutter"] = _shutter()


func play(name: String, pitch := 1.0, vol := 0.0) -> void:
	for p in _players:
		if not p.playing:
			p.stream = _streams[name]
			p.pitch_scale = pitch
			p.volume_db = -8.0 + vol
			p.play()
			return


# ------------------------------------------------------------------ smyčky (sdílené)

## Motor: základní frekvence 42 Hz (zápalná frekvence 4válce ~1260 ot/min), harmonické + šum.
static func engine_loop() -> AudioStreamWAV:
	if _static.has("engine"):
		return _static["engine"]
	var out := PackedFloat32Array()
	var f := 42.0
	var n := int(RATE / f) * 12
	var y := 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in n:
		var t := float(i) / RATE
		var ph := TAU * f * t
		var s := sin(ph) * 0.5 + sin(ph * 2.0) * 0.3 + sin(ph * 3.0) * 0.18 + sin(ph * 0.5) * 0.25
		s += signf(sin(ph)) * 0.12
		y += 0.2 * (rng.randf_range(-1.0, 1.0) - y)
		out.append((s + y * 0.35) * 0.45)
	var st := _wav_static(out)
	st.loop_mode = AudioStreamWAV.LOOP_FORWARD
	st.loop_end = n
	_static["engine"] = st
	return st


static func skid_loop() -> AudioStreamWAV:
	if _static.has("skid"):
		return _static["skid"]
	var out := PackedFloat32Array()
	var n := RATE
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var y := 0.0
	for i in n:
		var t := float(i) / RATE
		y += 0.5 * (rng.randf_range(-1.0, 1.0) - y)
		out.append((sin(TAU * 900.0 * t + sin(TAU * 7.0 * t) * 3.0) * 0.3 + y * 0.5) * 0.5)
	var st := _wav_static(out)
	st.loop_mode = AudioStreamWAV.LOOP_FORWARD
	st.loop_end = n
	_static["skid"] = st
	return st


## Policejní siréna (kvílení nahoru-dolů).
static func siren_loop() -> AudioStreamWAV:
	if _static.has("siren"):
		return _static["siren"]
	var out := PackedFloat32Array()
	var dur := 2.4
	var n := int(dur * RATE)
	var ph := 0.0
	for i in n:
		var t := float(i) / RATE
		var u := t / dur
		var f := lerpf(650.0, 1350.0, sin(u * PI))
		ph += TAU * f / RATE
		out.append((sin(ph) * 0.6 + sin(ph * 2.0) * 0.15) * 0.6)
	var st := _wav_static(out)
	st.loop_mode = AudioStreamWAV.LOOP_FORWARD
	st.loop_end = n
	_static["siren"] = st
	return st


## Bzučení vrtulí dronu (M6.1): vysoký dvojitý tón + zubový šum, smyčka ~0,5 s.
## `Drone.snd` (AudioStreamPlayer3D) ji ladí pitch_scale podle „plynu“.
static func drone_loop() -> AudioStreamWAV:
	if _static.has("drone"):
		return _static["drone"]
	var out := PackedFloat32Array()
	var f := 210.0                       # základní tón vrtulí (~blades)
	var n := int(RATE / f) * 6
	var y := 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for i in n:
		var t := float(i) / RATE
		var ph := TAU * f * t
		var s := sin(ph) * 0.5 + sin(ph * 2.0) * 0.3 + sin(ph * 4.0) * 0.12
		s += signf(sin(ph * 0.5)) * 0.18                       # „pískání“ motorů
		y += 0.3 * (rng.randf_range(-1.0, 1.0) - y)            # vzdušný šum lopatek
		out.append((s + y * 0.5) * 0.35)
	var st := _wav_static(out)
	st.loop_mode = AudioStreamWAV.LOOP_FORWARD
	st.loop_end = n
	_static["drone"] = st
	return st


static func horn() -> AudioStreamWAV:
	if _static.has("horn"):
		return _static["horn"]
	var out := PackedFloat32Array()
	var n := int(0.5 * RATE)
	for i in n:
		var t := float(i) / RATE
		var env := minf(1.0, t * 60.0) * minf(1.0, (0.5 - t) * 30.0)
		var s := signf(sin(TAU * 420.0 * t)) * 0.3 + signf(sin(TAU * 500.0 * t)) * 0.3
		out.append(s * env * 0.5)
	_static["horn"] = _wav_static(out)
	return _static["horn"]


## Zvonek na kolo: dva kovové tóny s dozvukem („crrn-crrn“).
static func bell() -> AudioStreamWAV:
	if _static.has("bell"):
		return _static["bell"]
	var out := PackedFloat32Array()
	var n := int(0.9 * RATE)
	for i in n:
		var t := float(i) / RATE
		var s := 0.0
		for hit in [0.0, 0.16]:
			var tt: float = t - hit
			if tt >= 0.0:
				var env := exp(-tt * 7.0) * minf(1.0, tt * 400.0)
				s += (sin(TAU * 2350.0 * tt) * 0.6 + sin(TAU * 3480.0 * tt) * 0.3 + sin(TAU * 5900.0 * tt) * 0.12) * env
		out.append(s * 0.45)
	_static["bell"] = _wav_static(out)
	return _static["bell"]


## Pip variometru letouna (M6.3): krátký jemný tón ~1,2 kHz; `FlightHud` mění pitch podle stoupání.
static func vario_beep() -> AudioStreamWAV:
	if _static.has("vario"):
		return _static["vario"]
	var out := PackedFloat32Array()
	var n := int(0.07 * RATE)
	for i in n:
		var t := float(i) / RATE
		var env := minf(1.0, t * 400.0) * exp(-t * 30.0)
		out.append(sin(TAU * 1200.0 * t) * env * 0.4)
	_static["vario"] = _wav_static(out)
	return _static["vario"]


static func _wav_static(samples: PackedFloat32Array) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32000.0))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = RATE
	s.data = data
	return s


# ------------------------------------------------------------------ jednorázové zvuky

func _wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	return _wav_static(samples)


func _tone(freqs: Array, note_len: float, vol: float) -> AudioStreamWAV:
	var out := PackedFloat32Array()
	for f in freqs:
		var n := int(note_len * RATE)
		for i in n:
			var t := float(i) / RATE
			var env := minf(1.0, t * 200.0) * exp(-t * 18.0)
			out.append((sin(TAU * f * t) + 0.3 * sin(TAU * f * 2.0 * t)) * env * vol)
	return _wav(out)


func _sweep(f0: float, f1: float, dur: float, vol: float) -> AudioStreamWAV:
	var out := PackedFloat32Array()
	var n := int(dur * RATE)
	var ph := 0.0
	for i in n:
		var t := float(i) / n
		ph += TAU * lerpf(f0, f1, t) / RATE
		out.append(sin(ph) * (1.0 - t) * vol)
	return _wav(out)


func _noise(dur: float, vol: float, cutoff: float) -> AudioStreamWAV:
	var out := PackedFloat32Array()
	var n := int(dur * RATE)
	var y := 0.0
	var a := clampf(TAU * cutoff / RATE, 0.0, 1.0)
	for i in n:
		var t := float(i) / n
		y += a * (randf_range(-1.0, 1.0) - y)
		out.append(y * vol * 3.0 * (1.0 - t) * (1.0 - t))
	return _wav(out)


## Výstřel z pušky: prásknutí (šum) + dunění (hluboký tón), dozvuk.
func _gunshot() -> AudioStreamWAV:
	var out := PackedFloat32Array()
	var n := int(0.7 * RATE)
	var y := 0.0
	var a := clampf(TAU * 3500.0 / RATE, 0.0, 1.0)
	for i in n:
		var t := float(i) / n
		y += a * (randf_range(-1.0, 1.0) - y)
		var crack := y * 3.0 * pow(1.0 - t, 6.0)
		var boom := sin(TAU * (70.0 - 40.0 * t) * float(i) / RATE) * pow(1.0 - t, 2.5) * 0.7
		out.append(clampf(crack + boom, -1.0, 1.0))
	return _wav(out)


## Tři hlty (bublání).
func _gulp() -> AudioStreamWAV:
	var out := PackedFloat32Array()
	for g in 3:
		var n := int(0.16 * RATE)
		var ph := 0.0
		for i in n:
			var t := float(i) / n
			ph += TAU * lerpf(180.0, 320.0, t) / RATE
			out.append(sin(ph) * sin(t * PI) * 0.45)
		for i in int(0.12 * RATE):
			out.append(0.0)
	return _wav(out)


func _burp() -> AudioStreamWAV:
	var out := PackedFloat32Array()
	var n := int(0.45 * RATE)
	var ph := 0.0
	var y := 0.0
	for i in n:
		var t := float(i) / n
		ph += TAU * (95.0 + sin(t * 40.0) * 12.0) / RATE
		y += 0.1 * (randf_range(-1.0, 1.0) - y)
		out.append((signf(sin(ph)) * 0.25 + sin(ph) * 0.3 + y) * sin(t * PI) * 0.6)
	return _wav(out)


func _crunch() -> AudioStreamWAV:
	var out := PackedFloat32Array()
	for c in 3:
		var n := int(0.08 * RATE)
		var y := 0.0
		for i in n:
			var t := float(i) / n
			y += 0.6 * (randf_range(-1.0, 1.0) - y)
			out.append(y * (1.0 - t) * 0.5)
		for i in int(0.15 * RATE):
			out.append(0.0)
	return _wav(out)


func _lighter() -> AudioStreamWAV:
	var out := PackedFloat32Array()
	for i in int(0.03 * RATE):
		out.append(randf_range(-1.0, 1.0) * 0.8 * (1.0 - float(i) / (0.03 * RATE)))
	var y := 0.0
	for i in int(0.6 * RATE):
		var t := float(i) / (0.6 * RATE)
		y += 0.05 * (randf_range(-1.0, 1.0) - y)
		out.append(y * 1.2 * sin(t * PI))
	return _wav(out)


func _cough() -> AudioStreamWAV:
	var out := PackedFloat32Array()
	for c in 2:
		var n := int(0.18 * RATE)
		var y := 0.0
		for i in n:
			var t := float(i) / n
			y += 0.25 * (randf_range(-1.0, 1.0) - y)
			out.append(y * exp(-t * 5.0) * 1.4)
		for i in int(0.1 * RATE):
			out.append(0.0)
	return _wav(out)


func _vomit() -> AudioStreamWAV:
	var out := PackedFloat32Array()
	var n := int(1.3 * RATE)
	var ph := 0.0
	var y := 0.0
	for i in n:
		var t := float(i) / n
		ph += TAU * (120.0 - t * 40.0) / RATE
		y += 0.15 * (randf_range(-1.0, 1.0) - y)
		out.append((sin(ph) * 0.3 + y * 1.2) * sin(t * PI) * 0.7)
	return _wav(out)


func _glass() -> AudioStreamWAV:
	var out := PackedFloat32Array()
	var n := int(0.5 * RATE)
	for i in n:
		var t := float(i) / RATE
		var s := 0.0
		for f in [2300.0, 3100.0, 4200.0, 5400.0]:
			s += sin(TAU * f * t + randf() * 0.2) * 0.2
		out.append((s + randf_range(-1.0, 1.0) * 0.4) * exp(-t * 9.0))
	return _wav(out)


func _whistle() -> AudioStreamWAV:
	var out := PackedFloat32Array()
	var n := int(0.7 * RATE)
	for i in n:
		var t := float(i) / RATE
		var f := 2800.0 + sin(TAU * 35.0 * t) * 120.0
		out.append(sin(TAU * f * t) * 0.35 * minf(1.0, t * 40.0) * minf(1.0, (0.7 - t) * 20.0))
	return _wav(out)


## Spoušť foťáku (M6.1): ostré cvaknutí – dvě krátké špičky šumu + vysoký tón.
func _shutter() -> AudioStreamWAV:
	var out := PackedFloat32Array()
	for i in int(0.12 * RATE):
		var t := float(i) / RATE
		var click := 0.0
		if t < 0.012 or (t > 0.055 and t < 0.07):
			click = randf_range(-1.0, 1.0) * 0.9
		var ring := sin(TAU * 5200.0 * t) * 0.18
		out.append((click + ring) * exp(-t * 26.0))
	return _wav(out)
