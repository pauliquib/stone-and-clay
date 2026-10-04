## Hudba pro smyšlené stanice rádia (Radio) – generovaná za běhu, hra nemá zvukové soubory.
##   metal  – „Rádio Kovadlina“: 150 BPM, e moll, zkreslené kvintové akordy s tlumením dlaní,
##            dvojšlapka, virbl na 2 a 4, činely, basa; 16 taktů (sloka + refrén), smyčka.
##   pohoda – „Rádio Pohoda“: 72 BPM, jazzové akordy (Cmaj7 – Am7 – Dm7 – G7…), elektrické piano,
##            měkká melodie, basa a metličky; 8 taktů, smyčka.
## Výroba trvá pár sekund – Radio ji spouští ve vlákně (WorkerThreadPool) a výsledek si pamatuje.
class_name RadioMusic
extends RefCounted

const RATE := 22050


static func make(kind: String) -> AudioStreamWAV:
	var s := metal() if kind == "metal" else pohoda()
	var w := Sfx._wav_static(s)
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	w.loop_end = s.size()
	return w


static func _midi(n: float) -> float:
	return 440.0 * pow(2.0, (n - 69.0) / 12.0)


## Přičte do `out` od vzorku `at` tón délky `dur` vytvořený funkcí f(t, fáze) s obálkou.
static func _add_note(out: PackedFloat32Array, at: int, dur: float, freq: float, amp: float, kind: String) -> void:
	var n := mini(int(dur * RATE), out.size() - at)
	var ph := 0.0
	var dph := freq / RATE
	for j in n:
		var t := float(j) / RATE
		ph += dph
		var x := 0.0
		match kind:
			"ep":        # elektrické piano: sinus + 2. a 3. harmonická, zvonivý nástup
				var p := TAU * ph
				x = (sin(p) + 0.35 * sin(2.0 * p) * exp(-t * 6.0) + 0.12 * sin(3.0 * p) * exp(-t * 10.0)) \
					* exp(-t * 1.6) * minf(t * 200.0, 1.0)
			"lead":      # měkká melodie (flétna / vibrafon)
				var vib := 1.0 + 0.004 * sin(TAU * 5.0 * t)
				x = sin(TAU * ph * vib) * minf(t * 25.0, 1.0) * exp(-t * 1.2)
			"bass":      # kontrabas / baskytara
				var p := TAU * ph
				x = (sin(p) + 0.25 * sin(2.0 * p)) * minf(t * 150.0, 1.0) * exp(-t * 2.5)
			"mbass":     # metalová basa (zkreslená)
				x = tanh(3.0 * (2.0 * fposmod(ph, 1.0) - 1.0)) * minf(t * 300.0, 1.0) * exp(-t * 3.0)
		out[at + j] += x * amp


# ------------------------------------------------------------------ metal

## Zkreslený kvintový akord (kytara): pila základního tónu + kvinta + oktáva → tanh; tlumení dlaní = krátké.
static func _chord(out: PackedFloat32Array, at: int, dur: float, root: float, amp: float, muted: bool, drive: float) -> void:
	var n := mini(int(dur * RATE), out.size() - at)
	var f := [root, root * 1.4983, root * 2.0]
	var ph := [0.0, 0.13, 0.41]
	var lp := 0.0
	var cut := 0.18 if muted else 0.55
	for j in n:
		var t := float(j) / RATE
		var s := 0.0
		for k in 3:
			ph[k] += f[k] * (1.0 + 0.002 * k) / RATE
			s += 2.0 * fposmod(ph[k], 1.0) - 1.0
		var env := minf(t * 400.0, 1.0) * (exp(-t * 14.0) if muted else exp(-t * 0.9))
		var x := tanh(s * drive * env)
		lp += cut * (x - lp)
		out[at + j] += lp * amp


static func _kick(out: PackedFloat32Array, at: int, amp: float) -> void:
	var n := mini(int(0.16 * RATE), out.size() - at)
	var ph := 0.0
	for j in n:
		var t := float(j) / RATE
		ph += (55.0 + 140.0 * exp(-t * 40.0)) / RATE
		out[at + j] += (sin(TAU * ph) * exp(-t * 18.0) + randf_range(-1.0, 1.0) * exp(-t * 300.0) * 0.4) * amp


static func _snare(out: PackedFloat32Array, at: int, amp: float) -> void:
	var n := mini(int(0.22 * RATE), out.size() - at)
	var hp := 0.0
	var prev := 0.0
	for j in n:
		var t := float(j) / RATE
		var w := randf_range(-1.0, 1.0)
		hp = 0.7 * (hp + w - prev)
		prev = w
		out[at + j] += (hp * exp(-t * 16.0) * 0.9 + sin(TAU * 185.0 * t) * exp(-t * 25.0) * 0.6) * amp


static func _hat(out: PackedFloat32Array, at: int, dur: float, amp: float) -> void:
	var n := mini(int(dur * RATE), out.size() - at)
	var hp := 0.0
	var prev := 0.0
	var decay := 3.5 / dur
	for j in n:
		var t := float(j) / RATE
		var w := randf_range(-1.0, 1.0)
		hp = 0.4 * (hp + w - prev)
		prev = w
		out[at + j] += hp * exp(-t * decay) * amp


static func metal() -> PackedFloat32Array:
	seed(666)
	var bpm := 150.0
	var s16 := 60.0 / bpm / 4.0              # délka šestnáctinky
	var bars := 16
	var total := int(bars * 16 * s16 * RATE) + 1
	var out := PackedFloat32Array()
	out.resize(total)
	var E := _midi(40)                       # E2
	# sloka (takty 0–7): chug na E s akcenty; refrén (8–15): akordy E – C – D – H
	var verse_roots := [0, 0, 0, 3, 0, 0, 5, 3]     # půltóny nad E: E, E, E, G, E, E, A, G
	var chorus_roots := [0, -4, -2, -5, 0, -4, -2, 2]    # E, C, D, H, E, C, D, F#
	# rytmus sloky v 16tinách: x = tlumený chug, A = otevřený akcent, . = pauza
	var verse_pat := "xxAxxxAxxAxxAxAx"
	for bar in bars:
		var bt := bar * 16
		var chorus := bar >= 8
		for st in 16:
			var at := int((bt + st) * s16 * RATE)
			if chorus:
				if st % 8 == 0:
					var r: int = chorus_roots[(bar - 8) % 8]
					_chord(out, at, s16 * 8.0, E * pow(2.0, r / 12.0) * 2.0, 0.26, false, 6.0)
					_add_note(out, at, s16 * 8.0, E * pow(2.0, r / 12.0) * 0.5 * 2.0, 0.35, "mbass")
			else:
				var c := verse_pat[st]
				if c != ".":
					var r: int = verse_roots[bar % 8] if c == "A" else 0
					_chord(out, at, s16 * (1.0 if c == "x" else 2.0), E * pow(2.0, r / 12.0), 0.3, c == "x", 7.0)
					_add_note(out, at, s16, E * pow(2.0, r / 12.0) * 0.5, 0.3, "mbass")
			# bicí: dvojšlapka (16tiny v refrénu, 8tiny ve sloce), virbl na 2 a 4, hi-hat / crash
			if chorus or st % 2 == 0:
				_kick(out, at, 0.55)
			if st == 4 or st == 12:
				_snare(out, at, 0.5)
			if chorus:
				if st == 0:
					_hat(out, at, 1.2, 0.3)      # crash
				elif st % 4 == 2:
					_hat(out, at, 0.25, 0.18)
			elif st % 2 == 0:
				_hat(out, at, 0.06, 0.16)
		# break na konci sloky a refrénu: víření virblu
		if bar == 7 or bar == 15:
			for k in 8:
				_snare(out, int((bt + 8 + k) * s16 * RATE), 0.25 + k * 0.04)
	_normalize(out, 0.85)
	return out


# ------------------------------------------------------------------ pohoda

static func pohoda() -> PackedFloat32Array:
	seed(72)
	var bpm := 72.0
	var beat := 60.0 / bpm
	var bars := 8
	var total := int((bars * 4 + 3) * beat * RATE)
	var out := PackedFloat32Array()
	out.resize(total)
	# akordy (MIDI tóny) po taktech: Cmaj7, Am7, Dm7, G7, Em7, A7, Dm7, G7sus→G7
	var chords := [[48, 52, 55, 59], [45, 52, 55, 60], [50, 53, 57, 60], [43, 53, 55, 59],
		[52, 55, 59, 62], [45, 55, 57, 61], [50, 53, 57, 60], [43, 53, 57, 59]]
	var bass := [36, 33, 38, 31, 40, 33, 38, 31]
	# melodie: [takt, doba, tón, délka v dobách]
	var mel := [[0, 0.0, 76, 1.5], [0, 1.5, 74, 0.5], [0, 2.0, 72, 2.0],
		[1, 0.0, 72, 1.0], [1, 1.0, 76, 1.0], [1, 2.0, 79, 2.0],
		[2, 0.0, 77, 1.5], [2, 1.5, 76, 0.5], [2, 2.0, 74, 1.0], [2, 3.0, 72, 1.0],
		[3, 0.0, 71, 2.0], [3, 2.0, 74, 2.0],
		[4, 0.0, 79, 1.5], [4, 1.5, 78, 0.5], [4, 2.0, 76, 2.0],
		[5, 0.0, 73, 1.0], [5, 1.0, 76, 1.0], [5, 2.0, 79, 1.0], [5, 3.0, 81, 1.0],
		[6, 0.0, 77, 1.5], [6, 1.5, 76, 0.5], [6, 2.0, 74, 2.0],
		[7, 0.0, 72, 1.0], [7, 1.0, 71, 1.0], [7, 2.0, 72, 2.0]]
	for bar in bars:
		var b0 := bar * 4.0 * beat
		var ch: Array = chords[bar]
		# piano: akord na 1 a „a“ dvojky (swing), jemně rozložený
		for hit in [0.0, 1.66]:
			for k in ch.size():
				var at := int((b0 + hit * beat + k * 0.012) * RATE)
				_add_note(out, at, beat * 2.4, _midi(ch[k]), 0.13 if hit == 0.0 else 0.09, "ep")
		# basa: walking na 1 a 3 + přechodový tón
		var br: int = bass[bar]
		var nxt: int = bass[(bar + 1) % bars]
		for q in [[0.0, br], [2.0, br + 7], [3.0, nxt + (1 if nxt < br else -1)]]:
			_add_note(out, int((b0 + q[0] * beat) * RATE), beat * 1.1, _midi(q[1]), 0.35, "bass")
		# metličky: tiché „šššš“ na každou dobu, důraz na 2 a 4
		for d in 4:
			_hat(out, int((b0 + d * beat) * RATE), beat * 0.7, 0.03 if d % 2 == 0 else 0.055)
	for m in mel:
		var at := int((m[0] * 4.0 + m[1]) * beat * RATE)
		_add_note(out, at, m[3] * beat * 1.3, _midi(m[2]), 0.16, "lead")
	# dozvuk konce do začátku (plynulá smyčka)
	var loop_n := int(bars * 4 * beat * RATE)
	var tail := out.slice(loop_n)
	out = out.slice(0, loop_n)
	for i in tail.size():
		out[i] += tail[i]
	_normalize(out, 0.75)
	return out


static func _normalize(out: PackedFloat32Array, peak: float) -> void:
	var m := 0.0001
	for x in out:
		m = maxf(m, absf(x))
	var k := peak / m
	for i in out.size():
		out[i] *= k
