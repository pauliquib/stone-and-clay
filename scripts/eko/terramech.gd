## Terramechanika (M8.13): kontakt kola / nohy / kopyta s měkkou půdou – zaboření, odpor valení, tažná síla, prokluz.
##
## Podle čeho (00_PRINCIPY kap. 8 „Terramechanika“): **Bekker** (tlak–zaboření desky `p = (k_c/b + k_φ)·z^n`),
## **Bekkerova tuhá kola** (zaboření `z = [3W / ((3−n)(k_c + b·k_φ)·√D)]^(2/(2n+1))`, kompakční odpor
## `R = b·(k_c/b + k_φ)·z^(n+1)/(n+1)`), pružná pneumatika = deska s tlakem huštění (`z = (p_g/k)^(1/n)`, bere se
## menší z obou), **Mohr–Coulomb** smyk půdy pro tažnou sílu (`H = A·c + W·tan φ`, A = šířka × délka stopy).
## Konstanty půd: J. Y. Wong, *Theory of Ground Vehicles* (tab. 2.3 – hlinitopísčité, jílovité a hlinité půdy, sníh),
## zjednodušeně na 6 půdních tříd `Site.SOIL_*` × stav „sucho“ / „rozmáčeno“; mezi nimi se interpoluje podle vlhkosti
## (`SoilWater.moisture_at`) a bláta (`mud_at`), tuhosti k geometricky. Zamrzlá půda (`SoilWater.frost`) je tvrdá,
## sníh (`snow_at`) je samostatná vrstva navrch (zaboří se nejvýš do `SNOW_COMPACT` své výšky).
##
## Použití (bez alokací za snímek): volající si drží `Soil` (stav půdy v místě, obnovuje ho s throttlingem přes
## `sample_soil`) a `Contact` (výsledek), za snímek volá jen `wheel_contact` / `plate_contact` (pár `pow`).
## Chodci, kůň a vozík používají `Probe` (vše v jednom, obnova po `PROBE_DT`). Svět se váže přes `bind(world)` –
## dotazy jdou přes `World.site` / `World.soil_water` s kontrolou `!= null` (00_PRINCIPY kap. 3); bez nich fallback
## z `Weather.wetness`. Přepínač `World.realism["terramech"]` (`enabled()`).
## Laditelné: F3 → Vozidla/Terén a bláto, Člověk/Bláto pod nohama, Zvěř/Kůň – bláto (`scripts/dev/tune_m8_13.gd`).
class_name Terramech
extends RefCounted

# ------------------------------------------------------------------ půdy (Wong, tab. 2.3 – zjednodušeno)
# Pořadí = Site.SOIL_*: hnědozem / kambizem, ranker / litozem, arenosol, pseudoglej / glej, fluvizem (niva), antropozem.
# k_c kN/m^(n+1), k_φ kN/m^(n+2), c kPa, φ °. „Sucho“ = ulehlý drn v létě, „rozmáčeno“ = nasycená půda po dlouhém dešti.
static var N_DRY := [0.9, 1.0, 1.0, 0.8, 0.85, 0.9]
static var N_WET := [0.6, 0.75, 0.85, 0.45, 0.5, 0.6]
static var KC_DRY := [60.0, 60.0, 10.0, 50.0, 45.0, 60.0]
static var KC_WET := [3.0, 10.0, 3.0, 1.2, 1.5, 4.0]
static var KPHI_DRY := [12000.0, 15000.0, 6000.0, 9000.0, 10000.0, 13000.0]
static var KPHI_WET := [350.0, 1200.0, 1000.0, 90.0, 130.0, 420.0]
static var C_DRY := [10.0, 6.0, 2.0, 14.0, 10.0, 10.0]
static var C_WET := [5.0, 3.0, 1.5, 6.0, 5.0, 5.0]
static var PHI_DRY := [32.0, 34.0, 32.0, 27.0, 29.0, 32.0]
static var PHI_WET := [15.0, 27.0, 29.0, 7.0, 9.0, 14.0]

# stav půdy
static var WET_FROM := 0.45            # vlhkost (× AWC), od které půda měkne
static var WET_FULL := 1.0             # … plně rozmáčená
static var MUD_W := 1.0                # váha bláta (`mud_at`) – rozmáčenost = max(vlhkost, bláto × tohle)
static var FROZEN_K := 30.0            # zamrzlá půda: tuhost × (1 + tohle × zamrznutí)
static var FALLBACK_SOIL := 0          # bez site.bin: půdní třída (0 = hnědozem)

# sníh (Wong: sníh US)
static var SNOW_N := 1.6
static var SNOW_KC := 4.37
static var SNOW_KPHI := 196.7
static var SNOW_C := 1.03
static var SNOW_PHI := 19.7
static var SNOW_COMPACT := 0.6         # sníh se slehne nejvýš na tento podíl výšky (zaboření ≤ výška × tohle)
static var SNOW_MIN_M := 0.03          # tenčí sníh se nepočítá

# kolo
static var SINK_MAX_R := 0.9           # nejhlubší zaboření (× poloměr kola) – pak sedí na podvozku
static var SHEAR_AREA_K := 1.0         # plocha smyku: × šířka × délka stopy (dezén zvětšuje)

# chodec (bota) – tlak a šířka stopy, zpomalení podle zaboření
static var FOOT_KPA := 25.0            # tlak podrážky (80 kg na ~0,03 m²)
static var FOOT_B := 0.1               # šířka stopy (m)
static var FOOT_SLOW_K := 4.0          # rychlost × (1 − zaboření × tohle)
static var FOOT_SLOW_MIN := 0.55       # nejpomaleji (×)
# kůň (kopyto)
static var HOOF_KPA := 180.0           # tlak kopyta (~550 kg na 2–3 kopyta)
static var HOOF_B := 0.12
static var HOOF_SLOW_K := 2.5
static var HOOF_SLOW_MIN := 0.45
# ruční vozík (úzká kola)
static var CART_KPA := 300.0
static var CART_B := 0.04
static var CART_R := 0.2
static var CART_SLOW_MIN := 0.35       # vozík v blátě: chůze nejpomaleji (×)
static var CART_SLOW_K := 1.5          # chůze × (1 − odpor/tíha × tohle)

static var PROBE_DT := 0.25            # jak často chodec / kůň / vozík znovu přečte půdu (s)
static var SQUELCH_SINK := 0.015       # od tohoto zaboření boty čvachtá (m)

static var world: World                # vázaný svět (bind) – dotazy přes world.site / world.soil_water
static var focus := Vector3.ZERO       # poloha lokálního hráče (LOD aut AI – obnovuje RutMap)


## Stav půdy v jednom místě (obnovuje volající s throttlingem; za snímek se jen čte).
class Soil extends RefCounted:
	var n := 0.9
	var kc := 60.0
	var kphi := 12000.0
	var c := 10.0
	var tanphi := 0.62
	var wet := 0.0                    # rozmáčenost 0..1
	var mud := 0.0                    # bláto 0..1 (SoilWater)
	var frost := 0.0                  # zamrzlá půda 0..1
	var snow_m := 0.0                 # výška sněhu (m)
	var soil := 0                     # půdní třída
	var bearing := 1.0                # orientační únosnost 0..1 (ladicí vrstva)


## Výsledek kontaktu (sdílený objekt – žádné slovníky za snímek).
class Contact extends RefCounted:
	var sinkage_m := 0.0
	var roll_resist_n := 0.0
	var max_traction_n := 0.0
	var slip_k := 0.0                 # 0 = jede, 1 = odpor ≥ trakce (hrabe na místě)
	var area_m2 := 0.0


## Chodec / kůň / vozík: obnova po PROBE_DT, výstup násobky pro pohyb.
class Probe extends RefCounted:
	var t := 0.0
	var soil := Soil.new()
	var cont := Contact.new()
	var sink_m := 0.0
	var speed_k := 1.0
	var grip_k := 1.0
	var resist_k := 0.0               # odpor / tíha (vozík)
	var fresh := false                # v tomto snímku se obnovilo


static func bind(w: World) -> void:
	world = w


static func enabled() -> bool:
	return world != null and world.realism_on("terramech")


## Stav půdy v bodě do `s` (volat s throttlingem – čte Site a SoilWater).
static func sample_soil(s: Soil, x: float, z: float) -> void:
	var cls := FALLBACK_SOIL
	var moist := 0.5
	var mud := 0.0
	var frost := 0.0
	var snow := 0.0
	if world != null:
		if world.site != null:
			cls = world.site.soil(x, z)
		var sw: SoilWater = world.soil_water
		if sw != null:
			moist = sw.moisture_at(x, z)
			mud = sw.mud_at(x, z)
			snow = sw.snow_at(x, z)
			if sw.active():
				frost = sw.frost
		elif world.weather != null:
			moist = clampf(0.45 + 0.5 * world.weather.wetness, 0.0, 1.0)
			mud = world.weather.wetness if world.weather.wetness > 0.45 else 0.0
			snow = world.weather.snow_cover * 0.1
	cls = clampi(cls, 0, N_DRY.size() - 1)
	var wet := maxf(smoothstep(WET_FROM, WET_FULL, moist), clampf(mud * MUD_W, 0.0, 1.0))
	wet *= 1.0 - frost
	s.soil = cls
	s.wet = wet
	s.mud = mud
	s.frost = frost
	s.snow_m = snow
	s.n = lerpf(float(N_DRY[cls]), float(N_WET[cls]), wet)
	var hard := 1.0 + FROZEN_K * frost
	s.kc = pow(float(KC_DRY[cls]), 1.0 - wet) * pow(float(KC_WET[cls]), wet) * hard
	s.kphi = pow(float(KPHI_DRY[cls]), 1.0 - wet) * pow(float(KPHI_WET[cls]), wet) * hard
	s.c = lerpf(float(C_DRY[cls]), float(C_WET[cls]), wet)
	s.tanphi = tan(deg_to_rad(lerpf(float(PHI_DRY[cls]), float(PHI_WET[cls]), wet)))
	s.bearing = clampf(log(s.kphi / 50.0) / log(20000.0 / 50.0), 0.0, 1.0)


## Kolo (Bekker tuhé kolo / pneumatika jako deska, menší zaboření vyhrává) + Mohr–Coulomb trakce.
## `load_n` zatížení kola (N), `b` šířka pneu (m), `r` poloměr (m), `pg_kpa` tlak pneu na zem (kPa),
## `extra_z` přídavné zaboření (vyhrabaná díra +, ujetá kolej −). Výsledek do `c`.
static func wheel_contact(s: Soil, load_n: float, b: float, r: float, pg_kpa: float, extra_z: float, c: Contact) -> void:
	var w := maxf(load_n, 0.0) * 0.001            # kN
	if w <= 0.0001:
		c.sinkage_m = 0.0
		c.roll_resist_n = 0.0
		c.max_traction_n = 0.0
		c.slip_k = 0.0
		c.area_m2 = 0.0
		return
	var d := 2.0 * r
	var zmax := SINK_MAX_R * r
	# --- sníh navrch
	var zs := 0.0
	var rs := 0.0
	var hs := 1.0e9
	if s.snow_m > SNOW_MIN_M:
		var ks := SNOW_KC / b + SNOW_KPHI
		zs = minf(_sink(w, b, d, pg_kpa, SNOW_N, SNOW_KC, SNOW_KPHI), s.snow_m * SNOW_COMPACT)
		rs = b * ks * pow(zs, SNOW_N + 1.0) / (SNOW_N + 1.0)
		var ls := maxf(sqrt(d * zs), w / (b * pg_kpa))
		hs = b * ls * SNOW_C * SHEAR_AREA_K + w * tan(deg_to_rad(SNOW_PHI))
	# --- půda
	var keq := s.kc / b + s.kphi
	var z := minf(_sink(w, b, d, pg_kpa, s.n, s.kc, s.kphi), zmax)
	var zr := clampf(z + extra_z, 0.0, zmax)
	var rr := b * keq * pow(zr, s.n + 1.0) / (s.n + 1.0)
	var l := maxf(sqrt(d * maxf(zr, 0.001)), w / (b * pg_kpa))
	var h := b * l * s.c * SHEAR_AREA_K + w * s.tanphi
	c.sinkage_m = minf(zr + zs, zmax)
	c.roll_resist_n = (rr + rs) * 1000.0
	c.max_traction_n = minf(h, hs) * 1000.0
	c.area_m2 = b * l
	c.slip_k = clampf(c.roll_resist_n / maxf(c.max_traction_n, 1.0), 0.0, 1.0)


## Deska (bota, kopyto): zaboření z tlaku `p_kpa` a šířky `b`, trakce na ploše `area`.
static func plate_contact(s: Soil, p_kpa: float, b: float, c: Contact) -> void:
	var keq := s.kc / b + s.kphi
	var z := pow(maxf(p_kpa, 0.0) / keq, 1.0 / s.n)
	if s.snow_m > SNOW_MIN_M:
		z += minf(pow(p_kpa / (SNOW_KC / b + SNOW_KPHI), 1.0 / SNOW_N), s.snow_m * SNOW_COMPACT)
	c.sinkage_m = minf(z, 0.5)
	c.roll_resist_n = 0.0
	c.max_traction_n = 0.0
	c.slip_k = 0.0


static func _sink(w: float, b: float, d: float, pg: float, n: float, kc: float, kphi: float) -> float:
	var zr := pow(3.0 * w / ((3.0 - n) * (kc + b * kphi) * sqrt(d)), 2.0 / (2.0 * n + 1.0))
	var zf := pow(pg / (kc / b + kphi), 1.0 / n)
	return minf(zr, zf)


## Kontrakt kroku (00/M8.13): výstup jako slovník – jen pro ladění / testy, ne za snímek.
static func contact_at(x: float, z: float, load_n: float, b: float, r: float, pg_kpa: float) -> Dictionary:
	var s := Soil.new()
	var c := Contact.new()
	sample_soil(s, x, z)
	wheel_contact(s, load_n, b, r, pg_kpa, 0.0, c)
	return {"sinkage_m": c.sinkage_m, "roll_resist_n": c.roll_resist_n, "max_traction_n": c.max_traction_n,
		"slip_k": c.slip_k}


## Chodec: zaboření boty, zpomalení a přilnavost (lokální bláto místo globálního mokra).
## Vrací true, když se v tomto volání obnovilo. `surf` = povrch pod nohama (asfalt / šterk / teren …).
static func probe_foot(p: Probe, dt: float, pos: Vector3, surf: String, p_kpa: float, b: float,
		slow_k: float, slow_min: float) -> bool:
	p.t -= dt
	p.fresh = false
	if p.t > 0.0:
		return false
	p.t = PROBE_DT
	p.fresh = true
	if not enabled() or surf != "teren":
		p.sink_m = 0.0
		p.speed_k = 1.0
		p.grip_k = _grip_k(surf, pos)
		return true
	sample_soil(p.soil, pos.x, pos.z)
	plate_contact(p.soil, p_kpa, b, p.cont)
	p.sink_m = p.cont.sinkage_m
	p.speed_k = clampf(1.0 - p.sink_m * slow_k, slow_min, 1.0)
	p.grip_k = _grip_k(surf, pos)
	return true


## Vozík: odpor valení úzkých kol / tíha (0..), obnova po PROBE_DT.
static func probe_cart(p: Probe, dt: float, pos: Vector3, mass_kg: float) -> void:
	p.t -= dt
	if p.t > 0.0:
		return
	p.t = PROBE_DT
	if not enabled():
		p.resist_k = 0.0
		p.speed_k = 1.0
		p.sink_m = 0.0
		return
	sample_soil(p.soil, pos.x, pos.z)
	var wl := mass_kg * 9.81 * 0.5                  # dvě kola
	wheel_contact(p.soil, wl, CART_B, CART_R, CART_KPA, 0.0, p.cont)
	p.sink_m = p.cont.sinkage_m
	p.resist_k = p.cont.roll_resist_n / maxf(wl, 1.0)
	p.speed_k = clampf(1.0 - p.resist_k * CART_SLOW_K, CART_SLOW_MIN, 1.0)


## Přilnavost podrážky / kopyta vůči suchu (1 = sucho) – bláto v místě (`Weather.surface_grip_at`).
static func _grip_k(surf: String, pos: Vector3) -> float:
	if world == null or world.weather == null:
		return 1.0
	var dry := maxf(float(Weather.SURF_GRIP.get(surf, 0.9)), 0.1)
	return clampf(world.weather.surface_grip_at(surf, pos) / dry, 0.0, 1.0)


## Hláška hráči (car.gd nemá World – jde přes vázaný svět).
static func notify(pid: int, text: String) -> void:
	if world != null and pid > 0:
		world.notify(pid, "show_message", [text, 3.0])


## Ladicí vrstva „unosnost“ (F2 → Příroda – ladění): zelená = únosná, červená = bořivá.
static func debug_bearing(x: float, z: float) -> Color:
	var s := Soil.new()
	sample_soil(s, x, z)
	var b := s.bearing
	return Color(1.0 - b, 0.25 + 0.6 * b, 0.15, 0.55)
