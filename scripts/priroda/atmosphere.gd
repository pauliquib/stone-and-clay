## Atmosféra u klienta – jak počasí a roční období vypadají a zní (simulaci drží World: Clock + Weather):
## - slunce a měsíc podle skutečné polohy (Clock.sun_enu / moon_enu), barva a síla světla, stíny
## - obloha (shaders/sky.gdshader): fyzikální rozptyl (Rayleigh + Mie + ozon), mraky osvětlené sluncem podle oblačnosti,
##   soumrak se zemským stínem, hvězdy, měsíc s fází, opar; barvy mlhy, slunce a světla na mraky z téhož modelu
##   (`SkyModel.clear_sky`, `_sky_light`), stín mraku přes slunce, adaptace oka; stará obloha = sky_legacy.gdshader
## - mlha a zatažená obloha tlumí světlo, blesky rozsvítí oblohu a se zpožděním zahřmí
## - déšť a sníh: částice kolem kamery, nepadají pod střechy (výšková kolize částic sleduje kameru)
## - zvuk deště a větru
## - globální parametry shaderů (project.godot → shader_globals): snow_cover, wetness, grass_green,
##   foliage, autumn, wind_strength → terén, stromy, střechy a silnice
## - M8.4: globální uniformy větru `wind_dir`, `wind_speed`, `wind_gust` (textura z `WindField`), `wind_offset`,
##   `wind_time`, `wind_hier` (shaders/include/wind.gdshaderinc); šum v korunách podle nárazu a lesa u kamery,
##   padající listí v bouřce (max. `LEAF_MAX` částic u kamery)
class_name Atmosphere
extends Node3D

## Prahy a síly – ladění vzhledu (M8.D2c: `static var`, laditelné v F3 → Příroda/Obloha a světlo)
static var SUN_ENERGY := 1.3
static var MOON_ENERGY := 0.16
static var FOG_BASE := 0.00022
static var FOG_MIST := 0.012         # hustota v husté mlze
static var FOG_RAIN := 0.0022
const RAIN_DROPS := 12000
const SNOW_FLAKES := 7000
## M8.4: vítr u kamery
const LEAF_MAX := 300                # padající listí / jehličí v bouřce
static var LEAF_GUST_MS := 20.0      # od jaké rychlosti nárazu u kamery (m/s) padá listí naplno
static var WIND_SND_FOREST := 0.6    # o kolik hlasitěji šumí vítr v lese (koruny)

## M8.5: expozice (adaptace oka) – cíl EV100 → vyhlazená `exposure_ev`, pak na tonemapping.
## `EXPOSURE_MID_EV` je kalibrována na jasné poledne (SkyModel), aby se tam `tonemap_exposure`
## chovalo jako dřív (≈1,0); v soumraku a v noci násobič roste, ať je scéna čitelná (Purkyně).
static var EXPOSURE_MID_EV := 15.5
static var EXPOSURE_DARK_GAIN := 0.07
static var EXPOSURE_MAX_MULT := 3.2
static var ADAPT_RATE_LIGHT := 10.0  # EV/s – adaptace do světla rychlá (~2 s na typický skok)
static var ADAPT_RATE_DARK := 1.0    # EV/s – adaptace do tmy pomalá (~20 s)
static var INDOOR_REF_LUX := 150.0   # hrubý odhad osvětlení uvnitř budovy (umělé světlo) – jen pro skok expozice při vstupu/výstupu

## M8.D2c: čísla ze vzorců `update` vytažená k ladění – výchozí = dřívější čísla.
static var INDOOR_FADE_RATE := 3.0   # přechod světla / zvuku při vstupu do budovy (1/s)
static var CLOUD_DARK_RAIN := 1.4    # ztmavnutí mraků deštěm
static var CLOUD_DARK_STORM := 0.5   # … bouřkou
static var WARM_ELEV := 22.0         # pod touto výškou slunce teplé světlo a mlha (°)
static var OVERCAST_FROM := 0.55     # zatažení (tlumí stíny, měsíc) od oblačnosti
static var HAZE_FOG := 0.9           # opar = mlha × FOG + déšť × RAIN
static var HAZE_RAIN := 0.35
static var MOON_OVERCAST_DIM := 0.85 # zatažená obloha tlumí měsíc
static var SHADOW_OVERCAST_DIM := 0.85   # zatažená obloha změkčí stíny
static var CLOUD_DRIFT := 0.00035    # rychlost tahu mraků po větru (UV za m)
static var LP_RATE := 0.4            # světelný smog obce: rychlost přechodu (1/s)
static var AMBIENT_NIGHT := 0.3      # světlo prostředí v noci (ve dne 1)
static var AMBIENT_DARK_DIM := 0.25  # tmavé mraky ubírají světlu prostředí
static var AMBIENT_INDOOR := 0.4     # světlo prostředí uvnitř (×)
static var FLASH_AMBIENT := 1.5      # záblesk blesku rozsvítí okolí
static var HIGH_FROM_M := 150.0      # dohled ve výšce: mlha se ředí od výšky nad terénem
static var HIGH_TO_M := 500.0        # … naplno
static var FOG_HIGH_THIN := 0.7      # … o kolik se mlha zředí
static var FOG_SKY_FOG := 0.8        # mlha zakryje oblohu (× mlha)
static var FOG_SKY_RAIN := 0.3       # … (× déšť)
static var FOG_SKY_HIGH := 0.25      # … (× výška)
static var FOG_SKY_MAX := 0.9
static var AERIAL_LOW := 0.5         # vzdušná perspektiva u země
static var AERIAL_HIGH := 0.85       # … ve výšce
static var EXPOSURE_OVERCAST := 0.08 # zatažená obloha přidá expozici (×)
static var PURKINJE_EV := 8.0        # Purkyňův posun: plná desaturace při EV100 −hodnota
static var PURKINJE_SAT := 0.35      # … sytost barev v hluboké tmě
static var LEGACY_EXPOSURE_NIGHT := 1.7  # stará obloha (realismus „sky“ vypnut): expozice v noci
static var LEGACY_EXPOSURE_OVERCAST := 0.12
static var TREE_FAR_HIGH := 2.6      # ve výšce vidět stromy dál (×)
## 10/2026: fyzikální obloha (shaders/sky.gdshader) – kalibrace jasu, adaptace oka v soumraku, mraky a mlha.
static var SKY_SUN_E := 14.0         # jas slunce v jednotkách obrazu (obloha je pak při expozici 1 jako fotka)
static var SKY_TURB := 1.5           # opar za jasna (aerosol, 1 ≈ 3× čistý vzduch) – letní moravská nížina
static var SKY_TURB_HAZE := 5.0      # … přídavek při plném oparu / mlze / dešti
static var SKY_GAIN_K := 0.6        # adaptace oka v soumraku: komprese jasu oblohy (0 = žádná, 1 = úplná)
static var SKY_GAIN_MAX := 22.0      # … nejvýš
static var SUN_DISK_K := 3.0         # jas slunečního kotouče (× jas slunce)
static var CLOUD_SUN_K := 0.11       # světlo slunce na mraky (× jas slunce)
static var CLOUD_AMB_K := 0.85       # světlo oblohy na mraky
static var GROUND_ALBEDO := Vector3(0.12, 0.13, 0.09)   # průměr krajiny pod obzorem (odrazy, světlo zdola)
static var GROUND_SUN_K := 0.12      # … podíl přímého slunce
static var NIGHT_SKY := Vector3(0.0028, 0.0042, 0.0095)   # vzdušné světélkování + hvězdné pozadí
static var MOON_SKY := 0.012         # měsícem nasvícená obloha při úplňku
static var CLOUD_SHADOW_MIN := 0.12  # přímé slunce za mrakem (podíl) – když mrak zakryje slunce, ztmavne krajina
static var FOG_SUN_SCATTER := 0.12   # mlha prosvícená sluncem (záře ve směru slunce)
static var AMBIENT_NIGHT_SKY := 4.5  # světlo prostředí v noci u fyzikální oblohy (oko vidí víc, než unese expozice)
static var AMBIENT_TWILIGHT := 1.8   # … v soumraku (slunce 0° až −8°: krajina ještě čitelná, ne černá)
static var SKY_LIGHT_HZ := 4.0       # jak často přepočítat barvy oblohy pro skript (slunce se hýbe pomalu)
static var GRASS_SNOW_DIM := 0.3     # sníh ubírá zeleň trávy (shader grass_green)
static var WIND_STRENGTH_FULL := 12.0    # shader wind_strength = vítr / tato rychlost (m/s)
static var LEAF_STORM_FROM := 0.7    # listí začne padat od podílu LEAF_GUST_MS
static var LEAF_FOREST_BASE := 0.4   # listí mimo les (× bouřka); v lese 1
static var SOUND_SPEED := 343.0      # rychlost zvuku – zpoždění hromu (m/s)
static var FLASH_DECAY := 9.0        # dosvit záblesku (1/s)
static var FLASH_POWER_DIST := 4000.0    # síla záblesku klesá se vzdáleností (m)

var clock: Clock
var weather: Weather
var env: Environment
var sun: DirectionalLight3D
var moon: DirectionalLight3D
var terrain: Terrain               # M6.2: pro výšku kamery nad terénem (dohled ve výšce); může být null
var north_deg := 78.37
var indoor := false                  # hráč je v interiéru (M1.4): tlumené světlo prostředí, bez padajících srážek, tlumený déšť a vítr
var _indoor_s := 0.0
var light_pollution := 0.0           # M5.12: cílový světelný smog 0..1 (StreetLights.pollution podle kamery); obloha ho plynule přebírá
var _lp := 0.0
var realism: Dictionary = {}         # M8.5: odkaz na `GameSettings.realism` (nastaví `LocalClient`); chybějící klíč "sky" = zapnuto (fallback)
var exposure_ev := EXPOSURE_MID_EV   # M8.5 API: aktuální vyhlazená EV100 scény (SkyModel) – čtou další kroky (8.9, 8.12, 8.16, 8.18)


## M8.5 – zjednodušený fyzikální model oblohy (Rayleigh + Mie rozptyl + ozon, à la Hillaire 2020 /
## Preetham, viz 00_PRINCIPY kap. 8 „Obloha a světlo“). Žádná plná předpočítaná LUT textura (časový
## rozpočet M8, kap. 6 – jen pár vyhodnocení za snímek, ne za pixel); transmitance a jas se počítají
## analytickými vzorci přímo tady. Čisté statické funkce – volatelné odkudkoli i bez uzlu kamery
## (`Atmosphere.SkyModel.sun_illuminance_lux(...)`), takže je můžou číst i budoucí serverové kroky M8
## (8.9 mikroklima, 8.12 plodiny, 8.16 tělo, 8.18 zvuk), ne jen tento klientský vzhled.
class SkyModel:
	# M8.D2c: `static var` (laditelné v F3 → Příroda/Obloha a světlo) – výchozí beze změny.
	static var SUN_LUX_ZENITH := 100000.0   # jasné nebe, slunce v zenitu
	static var SKY_LUX_CLEAR := 18000.0     # difuzní nebe jasného dne při slunci vysoko
	static var SKY_LUX_OVERCAST := 10000.0  # celé zatažené nebe (jen difuzní)
	static var SKY_LUX_TWILIGHT := 3.4      # konec občanského soumraku (elevace −6°)
	static var SKY_LUX_NIGHT := 0.0005      # konec nautického soumraku (elevace −12°) – jen zbytek difuze
	static var MOON_LUX_FULL := 0.25        # úplněk vysoko na obloze
	static var STARLIGHT_LUX := 0.001       # jasná bezměsíčná noc, jen hvězdy
	static var EV_REF_LUX := 2.5            # ISO: EV100 = log2(lux / 2,5)
	static var TAU_CLEAR := 0.10            # optická hloubka jasné oblohy (Rayleigh + ozon)
	static var TAU_HAZE := 0.5              # … přídavek při plném oparu / mlze (Mie)
	static var TINT_R := 0.55               # zčervenání slunce: útlum červené (× optická hloubka)
	static var TINT_G := 0.9                # … zelené
	static var TINT_B := 1.6                # … modré
	static var CLOUD_DIRECT_MIN := 0.08     # přímé slunce pod plnou oblačností (podíl)
	static var CLOUD_DIRECT_FROM := 0.2     # oblačnost začne zakrývat slunce od
	static var CLOUD_DIRECT_TO := 0.9       # … zakryje naplno při
	static var OVERCAST_SKY_FROM := 0.3     # difuzní jas: přechod na zataženo od oblačnosti
	static var OVERCAST_SKY_TO := 0.9       # … do
	static var HAZE_SKY_DIM := 0.3          # opar tlumí difuzní jas
	static var HORIZON_SUNSET := 0.05       # jas u obzoru při západu (× jasná obloha)
	static var LIGHT_POLLUTION_LUX := 0.05  # světelný smog obce při plné intenzitě (lux)
	static var LUMINOUS_EFFICACY := 110.0   # světelná účinnost slunce (lm/W) pro W/m²

	## Kasten & Young 1989 – vzdušná hmota podle zenitového úhlu (zjednodušeně, bez tlakové korekce).
	static func air_mass(elev_deg: float) -> float:
		var z := clampf(90.0 - elev_deg, 0.0, 94.0)
		var cz := cos(deg_to_rad(z))
		return 1.0 / (cz + 0.50572 * pow(maxf(96.07995 - z, 0.001), -1.6364))

	## Rayleigh + ozon (optická hloubka ~0,10 jasná obloha) + Mie podle oparu / mlhy (0..1 → +0,5).
	static func _extinction(am: float, haze: float) -> float:
		var tau := TAU_CLEAR + TAU_HAZE * clampf(haze, 0.0, 1.0)
		return exp(-tau * am)

	## Barva slunce a jeho přímého světla podle vzdušné hmoty – Rayleigh ~ 1/λ⁴, nízko nad obzorem
	## ubývá modré a zelené složky rychleji než červené → slunce zčervená (fyzikální, ne namíchané).
	static func sun_tint(elev_deg: float, haze: float) -> Color:
		if elev_deg <= -5.0:
			return Color(1.0, 0.55, 0.3)
		var am := air_mass(maxf(elev_deg, 0.2))
		var tau := TAU_CLEAR + TAU_HAZE * clampf(haze, 0.0, 1.0)
		var r := exp(-tau * am * TINT_R)
		var g := exp(-tau * am * TINT_G)
		var b := exp(-tau * am * TINT_B)
		var c := Color(r, g, b)
		return c / maxf(c.g, 0.001)   # normalizovat na zelenou, ať je slunce v poledne bílé, ne přitmavené

	## Přímá sluneční osvětlenost vodorovné plochy (lux) – 00_PRINCIPY kap. 8: jasné poledne ~100 000 lx.
	static func sun_illuminance_lux(elev_deg: float, cloud_cover: float, haze: float) -> float:
		if elev_deg <= -5.0:
			return 0.0
		var am := air_mass(maxf(elev_deg, 0.2))
		var trans := _extinction(am, haze)
		var geo := clampf(sin(deg_to_rad(elev_deg)), 0.0, 1.0)
		var direct := SUN_LUX_ZENITH * trans * geo
		direct *= lerpf(1.0, CLOUD_DIRECT_MIN, smoothstep(CLOUD_DIRECT_FROM, CLOUD_DIRECT_TO, clampf(cloud_cover, 0.0, 1.0)))
		return direct

	## Difuzní osvětlenost oblohy (bez přímého slunce) – ve dne podle výšky slunce a zatažení
	## (zataženo ~10 000 lx), v soumraku a v noci interpolace mezi kalibračními body kap. 8
	## (občanský soumrak ~3 lx) až po hvězdnou noc.
	static func sky_illuminance_lux(elev_deg: float, cloud_cover: float, haze: float) -> float:
		var cc := clampf(cloud_cover, 0.0, 1.0)
		if elev_deg >= 0.0:
			var clear := SKY_LUX_CLEAR * clampf(sin(deg_to_rad(elev_deg)), 0.05, 1.0)
			var overcast := SKY_LUX_OVERCAST * clampf(sin(deg_to_rad(elev_deg)) * 0.6 + 0.4, 0.1, 1.0)
			return lerpf(clear, overcast, smoothstep(OVERCAST_SKY_FROM, OVERCAST_SKY_TO, cc)) * (1.0 - haze * HAZE_SKY_DIM)
		if elev_deg >= -6.0:
			var t0 := SKY_LUX_CLEAR * HORIZON_SUNSET   # jas u obzoru v okamžiku západu (elev = 0)
			var t := clampf((-elev_deg) / 6.0, 0.0, 1.0)
			return lerpf(t0, SKY_LUX_TWILIGHT, t)
		if elev_deg >= -12.0:
			var t := clampf((-6.0 - elev_deg) / 6.0, 0.0, 1.0)
			return SKY_LUX_TWILIGHT * pow(SKY_LUX_NIGHT / SKY_LUX_TWILIGHT, t)
		return SKY_LUX_NIGHT

	## Měsíční osvětlenost (lux) – úplněk vysoko na obloze ~0,25 lx (kap. 8).
	static func moon_illuminance_lux(phase01: float, moon_elev_deg: float) -> float:
		var up := smoothstep(-2.0, 5.0, moon_elev_deg)
		return MOON_LUX_FULL * clampf(phase01, 0.0, 1.0) * up

	## Celková osvětlenost scény (slunce + obloha + měsíc + hvězdy + světelný smog obce) – vstup pro expozici.
	static func total_illuminance_lux(elev_deg: float, cloud_cover: float, haze: float, moon_phase01: float,
			moon_elev_deg: float, light_pollution01: float) -> float:
		var lux := sun_illuminance_lux(elev_deg, cloud_cover, haze) + sky_illuminance_lux(elev_deg, cloud_cover, haze)
		lux += moon_illuminance_lux(moon_phase01, moon_elev_deg) + STARLIGHT_LUX
		lux += clampf(light_pollution01, 0.0, 1.0) * LIGHT_POLLUTION_LUX
		return lux

	## EV100 = log2(lux / 2,5) (ISO 12232) – vstup pro expozici / adaptaci oka.
	static func ev100_from_lux(lux: float) -> float:
		return log(maxf(lux, 0.0001) / EV_REF_LUX) / log(2.0)

	## Sluneční elevace v pásu (−6°, 0°] = občanský soumrak (nejkratší telefonní budka civilního soumraku).
	static func is_civil_twilight(elev_deg: float) -> bool:
		return elev_deg <= 0.0 and elev_deg > -6.0

	## Hrubý odhad globálního horizontálního záření (W/m²) z osvětlenosti přes světelnou účinnost
	## slunečního záření (~110 lm/W, Michalsky 1988) – pro M8.12 (fotosyntéza) stačí řádová shoda.
	static func global_horizontal_irradiance_wm2(elev_deg: float, cloud_cover: float, haze: float) -> float:
		if elev_deg <= 0.0:
			return 0.0
		var lux := sun_illuminance_lux(elev_deg, cloud_cover, haze) + sky_illuminance_lux(elev_deg, cloud_cover, haze)
		return lux / LUMINOUS_EFFICACY

	# --- Rozptyl ve směru pohledu (10/2026): týž model jako `clear_sky` v shaders/sky.gdshader (jednoduchý rozptyl
	# Rayleigh + Mie + ozon, Chapmanova funkce ke slunci). Skript ho vyhodnotí jen pro pár směrů ~4× za sekundu –
	# barva mlhy u obzoru, světlo na mraky, barva slunce a zisk adaptace oka v soumraku tak sedí s oblohou.
	const R_KM := 6360.0                 # poloměr Země
	const RA_KM := 6460.0                # horní hranice atmosféry
	const H0_KM := 0.3                   # výška pozorovatele (Morava ~300 m n. m.)
	const BETA_R := Vector3(5.802e-3, 13.558e-3, 33.1e-3)   # Rayleigh 1/km (R, G, B)
	const BETA_O := Vector3(2.0e-3, 1.881e-3, 0.085e-3)     # ozon – Chappuisova pásma (stanový profil 10–40 km)
	const MULTI_SCAT := 0.4              # vícenásobný rozptyl (izotropní podíl)

	## Chapmanova funkce × exp(−h) v jednotkách výšky škály (Schüler 2012): optická hloubka ke zdroji z výšky h
	## pod úhlem s kosinem `cz`; pod obzorem paprsek projde tečným bodem (zemský stín → velká hodnota).
	static func chapman(x: float, h: float, cz: float) -> float:
		var c := sqrt(x + h)
		if cz >= 0.0:
			return c / (c * cz + 1.0) * exp(-h)
		var x0 := sqrt(maxf(1.0 - cz * cz, 0.0)) * (x + h)
		return 2.0 * sqrt(x0) * exp(minf(x - x0, 60.0)) - c / (1.0 - c * cz) * exp(-h)

	static func _vexp(tau: Vector3) -> Vector3:
		return Vector3(exp(-minf(tau.x, 80.0)), exp(-minf(tau.y, 80.0)), exp(-minf(tau.z, 80.0)))

	static func _ozone_tau(h_km: float, mus: float) -> Vector3:
		var mp := maxf(mus, 0.0)
		var amo := 1.0 / sqrt(mp * mp + 0.0035) * (1.0 + clampf(-mus * 10.0, 0.0, 1.0)) * clampf((45.0 - h_km) / 20.0, 0.0, 1.0)
		return BETA_O * 15.0 * amo

	## Propustnost atmosféry (R, G, B) pro světlo slunce do výšky `h_km` nad mořem; `mus` = sin výšky slunce,
	## `turb` = opar (1 ≈ 3× čistý vzduch). Nízké slunce zčervená, pod obzorem (zemský stín) → 0.
	static func transmittance(h_km: float, mus: float, turb: float) -> Vector3:
		var bme := 0.004 * 3.0 * turb * 1.11
		var tau := BETA_R * (8.0 * chapman(R_KM / 8.0, h_km / 8.0, mus)) \
			+ Vector3.ONE * (bme * 1.2 * chapman(R_KM / 1.2, h_km / 1.2, mus)) + _ozone_tau(h_km, mus)
		return _vexp(tau)

	## Jasná obloha ve směru `d` (bez kotoučů a mraků) pro slunce ve směru `sd` – relativní radiance (R, G, B)
	## pro jas slunce 1; `n` vzorků podél paprsku. Shodné s `clear_sky` v shaders/sky.gdshader.
	static func clear_sky(d: Vector3, sd: Vector3, turb: float, n := 8) -> Vector3:
		var mu := maxf(d.y, 0.0)
		var r0 := R_KM + H0_KM
		var b := r0 * mu
		var tmax := -b + sqrt(b * b + RA_KM * RA_KM - r0 * r0)
		var dh := Vector2(d.x, d.z)
		dh = dh / dh.length() if dh.length() > 1e-5 else Vector2(1.0, 0.0)
		var sh := dh.dot(Vector2(sd.x, sd.z))
		var sqmu := sqrt(maxf(1.0 - mu * mu, 0.0))
		var cs := Vector3(d.x, mu, d.z).normalized().dot(sd)
		var pr := 0.0597 * (1.0 + cs * cs)
		var g := 0.78
		var pm := (1.0 - g * g) / (12.566 * pow(maxf(1.0 + g * g - 2.0 * g * cs, 1e-4), 1.5))
		var bms := 0.004 * 3.0 * turb
		var bme := bms * 1.11
		var tauv := Vector3.ZERO
		var l := Vector3.ZERO
		var fn := float(n)
		for i in n:
			var fi := float(i)
			var f0 := (fi + 0.5) / fn
			var t := tmax * f0 * f0
			var dt := tmax * ((fi + 1.0) * (fi + 1.0) - fi * fi) / (fn * fn)
			var px := t * sqmu
			var py := r0 + t * mu
			var r := sqrt(px * px + py * py)
			var h := r - R_KM
			var mus := (px * sh + py * sd.y) / r
			var dr := exp(-h / 8.0)
			var dm := exp(-h / 1.2)
			var dz := maxf(1.0 - absf(h - 25.0) / 15.0, 0.0)
			var ext := BETA_R * dr + Vector3.ONE * (bme * dm) + BETA_O * dz
			var tmid := tauv + ext * (dt * 0.5)
			tauv += ext * dt
			var to := _ozone_tau(h, mus)
			var ts := _vexp(BETA_R * (8.0 * chapman(795.0, h / 8.0, mus)) + Vector3.ONE * (bme * 1.2 * chapman(5300.0, h / 1.2, mus)) + to)
			var ims := _vexp(BETA_R * (4.0 * chapman(795.0, h / 8.0, minf(mus + 0.03, 1.0))) + to)
			var tv := _vexp(tmid)
			var sr := BETA_R * dr
			var sm := Vector3.ONE * (bms * dm)
			l += tv * (ts * (sr * pr + sm * pm) + (sr + sm) * ims * (MULTI_SCAT / 12.566)) * dt
		return l

	static func luminance(c: Vector3) -> float:
		return c.x * 0.2126 + c.y * 0.7152 + c.z * 0.0722

var sky_mat: ShaderMaterial
var _rain: GPUParticles3D
var _snow: GPUParticles3D
var _rain_mat: ParticleProcessMaterial
var _snow_mat: ParticleProcessMaterial
var _collider: GPUParticlesCollisionHeightField3D
var _rain_snd: AudioStreamPlayer
var _wind_snd: AudioStreamPlayer
var wind_field: WindField            # M8.4: najde se sám přes Weather → World (null = staré chování)
var _leaves: GPUParticles3D
var _leaf_mat: ParticleProcessMaterial
var _leaf_sm: StandardMaterial3D
var _thunder: Array[AudioStreamPlayer] = []
var _flash := 0.0
var _flash_seq: Array = []           # [čas, síla] – záblesky jednoho blesku
var _cloud_off := Vector2.ZERO
var _t := 0.0
# fyzikální obloha (10/2026)
static var _cloud_img: Image
static var _cloud_tex: ImageTexture
static var _cover_q: PackedFloat32Array
var _legacy_tex: NoiseTexture2D
var _sky_phys := false
var _lum_ref := 1.0
var _wb := Vector3.ONE                   # vyvážení bílé (polední slunce bílé)
var _sl_t := -1.0                        # odpočet do přepočtu barev oblohy (s)
var _sun_col := Vector3.ONE              # propustnost atmosféry ke slunci u země (× vyvážení bílé)
var _horizon := Vector3(0.7, 0.75, 0.8)  # barva obzoru (mlha), jednotky obrazu
var _sky_gain := 1.0
var _cloud_thr := 0.5
var _sun_occl := 0.0                     # mrak před sluncem 0..1 (vyhlazeno)
var _last_min := NAN                     # herní minuty minulého snímku (skok času → expozice hned)
var _jump_prev := NAN
var _prev_cloud := -1.0
var _prev_fog := -1.0
var _sky_rt := 0                         # snímků do návratu cubemapy oblohy do postupného obnovování


func setup(c: Clock, w: Weather, e: Environment, s: DirectionalLight3D, m: DirectionalLight3D, north: float,
		t: Terrain = null) -> void:
	clock = c
	weather = w
	env = e
	sun = s
	moon = m
	terrain = t
	north_deg = north
	_build_sky()
	_build_precip()
	_build_leaves()
	_build_sounds()
	if weather:
		weather.lightning.connect(_on_lightning)
	update(0.0)


func _build_sky() -> void:
	sky_mat = ShaderMaterial.new()
	_sky_phys = not _sky_on()
	_set_sky_shader(_sky_on())
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	env.sky = sky
	# hodnota pro normalizaci adaptace: průměrný jas jasné oblohy se sluncem 60° nad obzorem
	var sd60 := Vector3(0.0, sin(deg_to_rad(60.0)), -cos(deg_to_rad(60.0)))
	_lum_ref = _sky_avg_lum(sd60, SKY_TURB)
	_wb = SkyModel.transmittance(SkyModel.H0_KM, sd60.y, SKY_TURB)
	_wb = Vector3(_wb.y / _wb.x, 1.0, _wb.y / _wb.z)       # vyvážení bílé: polední slunce = bílé


## Fyzikální obloha (sky.gdshader) nebo stará ruční (sky_legacy.gdshader, Nízká předvolba / realismus „Obloha“ vypnut).
## Přepíná se za běhu podle přepínače; stará obloha má svůj původní šum, ať vypadá i stojí přesně jako dřív.
func _set_sky_shader(phys: bool) -> void:
	if phys == _sky_phys:
		return
	_sky_phys = phys
	if phys:
		sky_mat.shader = load("res://shaders/sky.gdshader")
		sky_mat.set_shader_parameter("cloud_noise", cloud_noise_texture())
		_sl_t = -1.0                        # hned přepočítat barvy oblohy
	else:
		sky_mat.shader = load("res://shaders/sky_legacy.gdshader")
		if _legacy_tex == null:
			var noise := FastNoiseLite.new()
			noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
			noise.frequency = 0.012
			noise.fractal_octaves = 5
			noise.fractal_gain = 0.55
			_legacy_tex = NoiseTexture2D.new()
			_legacy_tex.width = 512
			_legacy_tex.height = 512
			_legacy_tex.seamless = true
			_legacy_tex.generate_mipmaps = true
			_legacy_tex.noise = noise
		sky_mat.set_shader_parameter("cloud_noise", _legacy_tex)


## Šum mraků 256×256 RGBA (bezešvý, s mipmapami) – R makro fBm (4 buňky na dlaždici), G kupy (Worley 8),
## B detail fBm (16), A jemné kupy (Worley 20). Vzniká jednou za běh (~0,1 s); obrázek čte i skript (stín mraků).
static func cloud_noise_image() -> Image:
	if _cloud_img != null:
		return _cloud_img
	const N := 256
	var layers: Array[PackedByteArray] = []
	var specs := [[FastNoiseLite.TYPE_PERLIN, 4.0, 4, false], [FastNoiseLite.TYPE_CELLULAR, 8.0, 2, true],
		[FastNoiseLite.TYPE_PERLIN, 16.0, 3, false], [FastNoiseLite.TYPE_CELLULAR, 20.0, 1, true]]
	var seed_ := 1307
	for sp in specs:
		var fn := FastNoiseLite.new()
		fn.seed = seed_
		seed_ += 101
		fn.noise_type = sp[0]
		fn.frequency = float(sp[1]) / float(N)
		fn.fractal_type = FastNoiseLite.FRACTAL_FBM if int(sp[2]) > 1 else FastNoiseLite.FRACTAL_NONE
		fn.fractal_octaves = int(sp[2])
		fn.fractal_gain = 0.5
		if sp[0] == FastNoiseLite.TYPE_CELLULAR:
			fn.cellular_distance_function = FastNoiseLite.DISTANCE_EUCLIDEAN
			fn.cellular_return_type = FastNoiseLite.RETURN_DISTANCE
		var img := fn.get_seamless_image(N, N, bool(sp[3]), false, 0.15, true)
		img.convert(Image.FORMAT_L8)
		layers.append(img.get_data())
	var out := PackedByteArray()
	out.resize(N * N * 4)
	var r := layers[0]
	var g := layers[1]
	var b := layers[2]
	var a := layers[3]
	for i in N * N:
		var o := i * 4
		out[o] = r[i]
		out[o + 1] = g[i]
		out[o + 2] = b[i]
		out[o + 3] = a[i]
	_cloud_img = Image.create_from_data(N, N, false, Image.FORMAT_RGBA8, out)
	# kvantily tvaru mraků (shape = 0,58 R + 0,42 G jako v shaderu) → práh pro dané pokrytí oblohy
	var vals := PackedFloat32Array()
	vals.resize(4096)
	for i in 4096:
		var j := (i * 16 + (i * 7) % 16) % (N * N)
		vals[i] = (float(r[j]) * 0.58 + float(g[j]) * 0.42) / 255.0
	vals.sort()
	_cover_q = PackedFloat32Array()
	for k in 33:
		_cover_q.append(vals[mini(int(k / 32.0 * 4095.0), 4095)])
	return _cloud_img


static func cloud_noise_texture() -> ImageTexture:
	if _cloud_tex == null:
		var img := cloud_noise_image().duplicate() as Image
		img.generate_mipmaps()
		_cloud_tex = ImageTexture.create_from_image(img)
	return _cloud_tex


## Práh tvaru mraků, nad kterým šum pokryje podíl oblohy `cover` (0..1).
static func cloud_threshold(cover: float) -> float:
	cloud_noise_image()
	var x := clampf(1.0 - cover, 0.0, 1.0) * 32.0
	var i := mini(int(x), 31)
	return lerpf(_cover_q[i], _cover_q[i + 1], x - float(i))


func _build_precip() -> void:
	# déšť – protáhlé průsvitné čárky
	_rain = GPUParticles3D.new()
	_rain.name = "Dest"
	_rain.amount = RAIN_DROPS
	_rain.lifetime = 1.6
	_rain.preprocess = 1.6
	_rain.local_coords = false
	_rain.visibility_aabb = AABB(Vector3(-30, -30, -30), Vector3(60, 50, 60))
	_rain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_rain_mat = ParticleProcessMaterial.new()
	_rain_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	_rain_mat.emission_box_extents = Vector3(22, 1, 22)
	_rain_mat.direction = Vector3(0, -1, 0)
	_rain_mat.spread = 3.0
	_rain_mat.initial_velocity_min = 9.0
	_rain_mat.initial_velocity_max = 11.0
	_rain_mat.gravity = Vector3(0, -2.0, 0)
	_rain_mat.collision_mode = ParticleProcessMaterial.COLLISION_HIDE_ON_CONTACT
	_rain.process_material = _rain_mat
	var q := QuadMesh.new()
	q.size = Vector2(0.012, 0.55)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.75, 0.8, 0.88, 0.28)
	m.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	m.billboard_keep_scale = true
	m.disable_receive_shadows = true
	q.material = m
	_rain.draw_pass_1 = q
	_rain.emitting = false
	add_child(_rain)
	# sníh – vločky pomalu padají a víří
	_snow = GPUParticles3D.new()
	_snow.name = "Snih"
	_snow.amount = SNOW_FLAKES
	_snow.lifetime = 9.0
	_snow.preprocess = 9.0
	_snow.local_coords = false
	_snow.visibility_aabb = AABB(Vector3(-30, -30, -30), Vector3(60, 50, 60))
	_snow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_snow_mat = ParticleProcessMaterial.new()
	_snow_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	_snow_mat.emission_box_extents = Vector3(24, 5, 24)
	_snow_mat.direction = Vector3(0, -1, 0)
	_snow_mat.spread = 20.0
	_snow_mat.initial_velocity_min = 0.8
	_snow_mat.initial_velocity_max = 1.4
	_snow_mat.gravity = Vector3(0, -0.4, 0)
	_snow_mat.turbulence_enabled = true
	_snow_mat.turbulence_noise_strength = 1.2
	_snow_mat.turbulence_noise_scale = 4.0
	_snow_mat.turbulence_influence_min = 0.05
	_snow_mat.turbulence_influence_max = 0.12
	_snow_mat.scale_min = 0.6
	_snow_mat.scale_max = 1.3
	_snow_mat.collision_mode = ParticleProcessMaterial.COLLISION_HIDE_ON_CONTACT
	_snow.process_material = _snow_mat
	var sq := QuadMesh.new()
	sq.size = Vector2(0.035, 0.035)
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.albedo_color = Color(0.95, 0.96, 1.0, 0.85)
	sm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	sm.billboard_keep_scale = true
	sq.material = sm
	_snow.draw_pass_1 = sq
	_snow.emitting = false
	add_child(_snow)
	# střechy, stromy, auto – částice pod nimi zmizí (výšková mapa sleduje kameru)
	_collider = GPUParticlesCollisionHeightField3D.new()
	_collider.size = Vector3(48, 40, 48)
	_collider.resolution = GPUParticlesCollisionHeightField3D.RESOLUTION_256
	_collider.follow_camera_enabled = true
	_collider.update_mode = GPUParticlesCollisionHeightField3D.UPDATE_MODE_WHEN_MOVED
	add_child(_collider)


## M8.4: listí / jehličí, které v bouřce letí kolem kamery po větru.
func _build_leaves() -> void:
	_leaves = GPUParticles3D.new()
	_leaves.name = "Listi"
	_leaves.amount = LEAF_MAX
	_leaves.lifetime = 5.0
	_leaves.local_coords = false
	_leaves.visibility_aabb = AABB(Vector3(-40, -30, -40), Vector3(80, 50, 80))
	_leaves.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_leaf_mat = ParticleProcessMaterial.new()
	_leaf_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	_leaf_mat.emission_box_extents = Vector3(18, 6, 18)
	_leaf_mat.direction = Vector3(1, 0, 0)
	_leaf_mat.spread = 35.0
	_leaf_mat.initial_velocity_min = 2.0
	_leaf_mat.initial_velocity_max = 6.0
	_leaf_mat.gravity = Vector3(0, -1.2, 0)
	_leaf_mat.angular_velocity_min = -360.0
	_leaf_mat.angular_velocity_max = 360.0
	_leaf_mat.turbulence_enabled = true
	_leaf_mat.turbulence_noise_strength = 2.0
	_leaf_mat.turbulence_noise_scale = 3.0
	_leaf_mat.scale_min = 0.7
	_leaf_mat.scale_max = 1.4
	_leaf_mat.collision_mode = ParticleProcessMaterial.COLLISION_HIDE_ON_CONTACT
	_leaves.process_material = _leaf_mat
	var q := QuadMesh.new()
	q.size = Vector2(0.06, 0.045)
	_leaf_sm = StandardMaterial3D.new()
	_leaf_sm.cull_mode = BaseMaterial3D.CULL_DISABLED
	_leaf_sm.albedo_color = Color(0.3, 0.42, 0.12)
	_leaf_sm.roughness = 0.9
	q.material = _leaf_sm
	_leaves.draw_pass_1 = q
	_leaves.emitting = false
	add_child(_leaves)


func _build_sounds() -> void:
	_rain_snd = AudioStreamPlayer.new()
	_rain_snd.volume_db = -80.0
	add_child(_rain_snd)
	_wind_snd = AudioStreamPlayer.new()
	_wind_snd.volume_db = -80.0
	add_child(_wind_snd)
	for i in 2:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_thunder.append(p)


# ------------------------------------------------------------------ M8.5 API (fyzikální světlo)

func _sky_on() -> bool:
	return bool(realism.get("sky", true))


func _haze_now() -> float:
	var fog := weather.fog if weather else 0.0
	var rain := weather.rain if weather else 0.0
	return clampf(fog * HAZE_FOG + rain * HAZE_RAIN, 0.0, 1.0)


## Přímá sluneční osvětlenost vodorovné plochy právě teď (lux) – vždy fyzikální (SkyModel), nezávisle
## na přepínači "sky" (ten řídí jen vzhled oblohy a adaptaci expozice, ne tuhle hodnotu pro ostatní kroky).
func sun_illuminance_lux() -> float:
	if clock == null:
		return SkyModel.SUN_LUX_ZENITH
	return SkyModel.sun_illuminance_lux(clock.sun_elevation(), weather.cloud if weather else 0.3, _haze_now())


## Difuzní osvětlenost oblohy právě teď (lux).
func sky_illuminance_lux() -> float:
	if clock == null:
		return SkyModel.SKY_LUX_CLEAR
	return SkyModel.sky_illuminance_lux(clock.sun_elevation(), weather.cloud if weather else 0.3, _haze_now())


## Globální horizontální záření (W/m²) – pro M8.12 (fotosyntéza) a M8.16 (tepelná bilance těla).
func global_horizontal_irradiance_wm2() -> float:
	if clock == null:
		return 0.0
	return SkyModel.global_horizontal_irradiance_wm2(clock.sun_elevation(), weather.cloud if weather else 0.3, _haze_now())


## Je právě občanský soumrak (slunce −6°..0°)? Pro M8.18 (ptáci / cvrčci / rozsvícení lamp).
func is_civil_twilight() -> bool:
	if clock == null:
		return false
	return SkyModel.is_civil_twilight(clock.sun_elevation())


# ------------------------------------------------------------------ každý snímek

func update(delta: float) -> void:
	_t += delta
	_indoor_s = move_toward(_indoor_s, 1.0 if indoor else 0.0, delta * INDOOR_FADE_RATE)
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	var day := clock.daylight()
	var cloud := weather.cloud if weather else 0.3
	var rain := weather.rain if weather else 0.0
	var fog := weather.fog if weather else 0.0
	var wind := weather.wind if weather else 2.0
	var dark := clampf(rain * CLOUD_DARK_RAIN + (weather.storm if weather else 0.0) * CLOUD_DARK_STORM, 0.0, 1.0)

	# --- slunce a měsíc
	var sd := Clock.enu_to_world(clock.sun_enu(), north_deg)
	var md := Clock.enu_to_world(clock.moon_enu(), north_deg)
	_aim(sun, sd)
	_aim(moon, md)
	var elev := clock.sun_elevation()
	var warm := 1.0 - clampf(elev / WARM_ELEV, 0.0, 1.0)
	var overcast := smoothstep(OVERCAST_FROM, 1.0, cloud)
	var haze := _haze_now()
	var moon_elev := rad_to_deg(asin(clampf(md.y, -1.0, 1.0)))
	var sky_on := _sky_on()

	# --- M8.5: fyzikální osvětlenost (lux) a adaptace expozice – počítá se vždy (levné, čisté funkce),
	# ať ji budoucí kroky M8 (8.9, 8.12, 8.16, 8.18) můžou číst i když je vizuální přepínač "sky" vypnutý;
	# jen vzhled oblohy / tonemapping / Purkyňův posun níž se mění podle `sky_on`.
	var sun_lux := SkyModel.sun_illuminance_lux(elev, cloud, haze)
	var sky_lux := SkyModel.sky_illuminance_lux(elev, cloud, haze)
	var moon_lux := SkyModel.moon_illuminance_lux(clock.moon_illumination(), moon_elev)
	var total_lux := sun_lux + sky_lux + moon_lux + SkyModel.STARLIGHT_LUX + _lp * SkyModel.LIGHT_POLLUTION_LUX
	var target_ev := lerpf(SkyModel.ev100_from_lux(total_lux), SkyModel.ev100_from_lux(INDOOR_REF_LUX), _indoor_s)
	var adapt_rate := ADAPT_RATE_LIGHT if target_ev > exposure_ev else ADAPT_RATE_DARK
	# první snímek a skok času (spánek, F2, načtení hry) → oko je už přizpůsobené, žádné 20 s černé noci
	var jumped := is_nan(_last_min) or absf(clock.minutes - _last_min) > 20.0
	_last_min = clock.minutes
	exposure_ev = target_ev if jumped else move_toward(exposure_ev, target_ev, delta * adapt_rate)
	# po skoku času by postupně (INCREMENTAL) obnovovaná cubemapa oblohy ještě pár snímků svítila „starým“ nebem
	# (noc osvětlená poledním nebem) – na pár snímků ji přepočítat celou
	if env.sky != null:
		var wjump := absf(cloud - _prev_cloud) > 0.2 or absf(fog - _prev_fog) > 0.2
		_prev_cloud = cloud
		_prev_fog = fog
		if (jumped and not is_nan(_jump_prev)) or wjump:
			_sky_rt = 8
			env.sky.process_mode = Sky.PROCESS_MODE_REALTIME
		elif _sky_rt > 0:
			_sky_rt -= 1
			if _sky_rt == 0:
				env.sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
	_jump_prev = clock.minutes

	var sun_up := smoothstep(-2.0, 3.0, elev)
	var moon_up := smoothstep(-2.0, 4.0, moon_elev)
	_set_sky_shader(sky_on)
	var wv0 := weather.wind_vector() if weather else Vector3(-2.0, 0, 0.5)
	_cloud_off += (Vector2(wv0.x, wv0.z) * CLOUD_DRIFT + Vector2(-0.0004, 0.0001)) * delta
	_lp = move_toward(_lp, light_pollution, delta * LP_RATE)
	if sky_on:
		# 10/2026: barvy z modelu rozptylu (stejného jako obloha) – slunce zčervená, mraky, mlha a země ladí s oblohou
		_sl_t -= delta
		if _sl_t <= 0.0 or jumped:
			_sl_t = 1.0 / SKY_LIGHT_HZ
			_sky_light(sd, md, elev, haze, cloud, dark, moon_up)
		# stín mraku: když mrak na obloze zakryje slunce, přímé světlo zeslábne (plynule, jak mrak táhne)
		var occl := _cloud_at(sd, cloud)
		_sun_occl = occl if jumped else move_toward(_sun_occl, occl, delta * 0.8)
		var clear_lux := SkyModel.sun_illuminance_lux(elev, 0.0, haze)
		var direct := lerpf(1.0, CLOUD_SHADOW_MIN, smoothstep(0.05, 0.7, _sun_occl))
		var sc := _sun_col / maxf(maxf(_sun_col.x, _sun_col.y), maxf(_sun_col.z, 1e-4))
		sun.light_color = Color(sc.x, sc.y, sc.z)
		sun.light_energy = SUN_ENERGY * clampf(clear_lux / SkyModel.SUN_LUX_ZENITH, 0.0, 1.0) * direct * sun_up
		moon.light_energy = MOON_ENERGY * clampf(moon_lux / SkyModel.MOON_LUX_FULL, 0.0, 1.0) * moon_up * (1.0 - day) * (1.0 - overcast * MOON_OVERCAST_DIM)
	else:
		sun.light_color = Color(1.0, 0.96, 0.9).lerp(Color(1.0, 0.58, 0.32), warm)
		sun.light_energy = SUN_ENERGY * sun_up * (1.0 - overcast * 0.78) * (1.0 - fog * 0.5)
		moon.light_energy = MOON_ENERGY * moon_up * (0.25 + 0.75 * clock.moon_illumination()) * (1.0 - day) * (1.0 - overcast * MOON_OVERCAST_DIM)
	sun.visible = sun.light_energy > 0.01
	sun.shadow_opacity = 1.0 - overcast * SHADOW_OVERCAST_DIM
	moon.visible = moon.light_energy > 0.005 and not sun.visible

	# --- obloha (mraky táhnou po větru, minimálně pomalý posun i za bezvětří)
	sky_mat.set_shader_parameter("sun_dir", sd)
	sky_mat.set_shader_parameter("moon_dir", md)
	sky_mat.set_shader_parameter("moon_light", clock.moon_illumination())
	sky_mat.set_shader_parameter("cloud_cover", cloud)
	sky_mat.set_shader_parameter("cloud_dark", dark)
	sky_mat.set_shader_parameter("cloud_offset", _cloud_off)
	sky_mat.set_shader_parameter("haze", haze)
	sky_mat.set_shader_parameter("sky_on", sky_on)
	sky_mat.set_shader_parameter("light_pollution", _lp)
	_update_flash(delta)
	sky_mat.set_shader_parameter("flash", _flash)

	# --- světlo prostředí a mlha
	var amb_night := AMBIENT_NIGHT if not sky_on else lerpf(AMBIENT_NIGHT_SKY, AMBIENT_TWILIGHT,
		smoothstep(-12.0, -5.0, elev)) * lerpf(1.0, 1.0 / AMBIENT_TWILIGHT, smoothstep(0.0, 8.0, elev))
	env.ambient_light_energy = (lerpf(amb_night, 1.0, day) * (1.0 - dark * AMBIENT_DARK_DIM) * lerpf(1.0, AMBIENT_INDOOR, _indoor_s)
		+ _flash * FLASH_AMBIENT * (1.0 - _indoor_s))
	env.ambient_light_sky_contribution = 1.0
	if sky_on:
		# mlha má barvu oblohy u obzoru (vzdušná perspektiva) a ve směru slunce se prosvítí
		var m := maxf(maxf(_horizon.x, _horizon.y), maxf(_horizon.z, 1e-5))
		env.fog_light_color = Color(_horizon.x / m, _horizon.y / m, _horizon.z / m)
		env.fog_light_energy = m
		env.fog_sun_scatter = FOG_SUN_SCATTER * (1.0 - overcast) * sun_up
	else:
		var fog_col := Color(0.72, 0.8, 0.9).lerp(Color(0.7, 0.72, 0.75), overcast)
		fog_col = fog_col.lerp(Color(0.04, 0.05, 0.08), 1.0 - day).lerp(Color(0.9, 0.6, 0.45), warm * day * 0.45 * (1.0 - overcast))
		env.fog_light_color = fog_col
		env.fog_light_energy = 1.0
		env.fog_sun_scatter = 0.0
	# M6.2: dohled z výšky – nad ~150 m AGL se mlha ředí a horizont se táhne, ať je okolí
	# mapy (Surroundings) čitelné; v mlze zůstane dohled omezený (fog drží svoji část)
	var high := 0.0
	if cam != null:
		var ground := terrain.height_at(cam.global_position.x, cam.global_position.z) if terrain else 0.0
		high = smoothstep(HIGH_FROM_M, HIGH_TO_M, cam.global_position.y - ground)
	env.fog_density = (FOG_BASE + FOG_MIST * fog * fog + FOG_RAIN * rain) * (1.0 - FOG_HIGH_THIN * high)
	env.fog_sky_affect = clampf(fog * FOG_SKY_FOG + rain * FOG_SKY_RAIN + high * FOG_SKY_HIGH, 0.0, FOG_SKY_MAX)
	env.fog_aerial_perspective = lerpf(AERIAL_LOW, AERIAL_HIGH, high) * (1.0 - fog)
	_micro_fx_update(cam, delta)          # M8.9: údolní mlha (výšková) a rosa / jinovatka podle World.micro
	# podání barev z Nastavení (GameSettings.apply_graphics uloží základ do meta prostředí) – Purkyňův posun ho
	# jen násobí, nepřepisuje (dřív se barevný režim každým snímkem ztratil)
	var base_sat := float(env.get_meta("color_saturation", 1.0))
	var base_con := float(env.get_meta("color_contrast", 1.0))
	env.adjustment_enabled = true
	env.adjustment_brightness = 1.0
	env.adjustment_contrast = base_con
	if sky_on:
		# M8.5: expozice z vyhlazené EV100 (SkyModel) – kalibrováno, ať je jasné poledne ≈ jako dřív (1,0),
		# v soumraku a v noci násobič roste (oko se roztáhne), ať zůstane scéna čitelná (Purkyně).
		var exp_mult := 1.0 + EXPOSURE_DARK_GAIN * maxf(EXPOSURE_MID_EV - exposure_ev, 0.0)
		env.tonemap_exposure = clampf(exp_mult, 1.0, EXPOSURE_MAX_MULT) * (1.0 + overcast * EXPOSURE_OVERCAST)
		# Purkyňův posun: pod cca 1 lx ztrácí oko barvocit (tyčinkové vidění) – postupná desaturace do ~8 EV tmy
		var purkinje := clampf(-exposure_ev / PURKINJE_EV, 0.0, 1.0)
		env.adjustment_saturation = base_sat * lerpf(1.0, PURKINJE_SAT, purkinje)
	else:
		env.tonemap_exposure = lerpf(LEGACY_EXPOSURE_NIGHT, 1.0, day) * (1.0 + overcast * LEGACY_EXPOSURE_OVERCAST)
		env.adjustment_saturation = base_sat
	MapLoader.set_tree_far_mult(lerpf(1.0, TREE_FAR_HIGH, high))      # M6.2: ve výšce vidět stromy dál

	# --- srážky kolem kamery
	var snowing := weather != null and weather.is_snowing()
	var raining := weather != null and weather.is_raining()
	if cam:
		var cp := cam.global_position
		var wv := weather.wind_vector() if weather else Vector3.ZERO
		_rain.global_position = cp + Vector3(0, 12, 0) - wv * 0.9 + cam.global_transform.basis.z * -8.0
		_snow.global_position = cp + Vector3(0, 7, 0) - wv * 2.0 + cam.global_transform.basis.z * -6.0
		_rain_mat.direction = (Vector3(0, -10, 0) + wv).normalized()
		_snow_mat.gravity = Vector3(wv.x * 0.25, -0.4, wv.z * 0.25)
	_rain.emitting = raining and _indoor_s < 0.5
	_snow.emitting = snowing and _indoor_s < 0.5
	_rain.amount_ratio = clampf(rain * 1.2, 0.05, 1.0)
	_snow.amount_ratio = clampf(rain * 1.5, 0.08, 1.0)

	# --- zvuky
	var muffle := -16.0 * _indoor_s          # uvnitř budovy je déšť i vítr slyšet jen tlumeně
	_loop(_rain_snd, "rain", (rain if raining else 0.0), -30.0 + muffle, 0.0 + muffle)
	var wind_amt := clampf((wind - 3.0) / 12.0, 0.0, 1.0)
	if wind_field == null and weather != null:
		wind_field = weather.get_parent().get("wind_field") as WindField
	var wf_on := wind_field != null and wind_field.enabled()
	if wf_on and cam:
		# M8.4: šum podle nárazu u kamery; v lese (drsný povrch) hučí koruny hlasitěji
		var cp2 := cam.global_position
		var gv := wind_field.wind_at(cp2, 10.0)
		var gs := Vector2(gv.x, gv.z).length()
		var forest := clampf(wind_field.roughness_at(cp2), 0.0, 1.0)
		wind_amt = clampf((gs - 3.0) / 12.0, 0.0, 1.0) * (1.0 + WIND_SND_FOREST * forest)
		wind_amt = minf(wind_amt, 1.0)
		var storm_k := smoothstep(LEAF_GUST_MS * LEAF_STORM_FROM, LEAF_GUST_MS, gs) * (LEAF_FOREST_BASE + (1.0 - LEAF_FOREST_BASE) * forest)
		var fol := Seasons.foliage(clock.day_of_year())
		_leaves.emitting = storm_k > 0.02 and _indoor_s < 0.5
		_leaves.amount_ratio = clampf(storm_k, 0.05, 1.0)
		if _leaves.emitting:
			var d2 := wind_field.dir()
			_leaves.global_position = cp2 + Vector3(-d2.x * 10.0, 5.0, -d2.y * 10.0)
			_leaf_mat.direction = Vector3(d2.x, 0.15, d2.y)
			_leaf_mat.initial_velocity_min = gs * 0.25
			_leaf_mat.initial_velocity_max = gs * 0.55
			_leaf_sm.albedo_color = Color(0.3, 0.42, 0.12).lerp(Color(0.62, 0.38, 0.1), clampf(Seasons.autumn(clock.day_of_year()) + (1.0 - fol) * 0.5, 0.0, 1.0))
	else:
		_leaves.emitting = false
	_loop(_wind_snd, "wind", wind_amt, -32.0 + muffle, -6.0 + muffle)

	# --- globální parametry shaderů (terén, stromy, střechy)
	var doy := clock.day_of_year()
	var rs := RenderingServer
	rs.global_shader_parameter_set("snow_cover", weather.snow_cover if weather else 0.0)
	rs.global_shader_parameter_set("wetness", weather.wetness if weather else 0.0)
	rs.global_shader_parameter_set("grass_green", Seasons.green(doy) * (1.0 - (weather.snow_cover if weather else 0.0) * GRASS_SNOW_DIM))
	rs.global_shader_parameter_set("foliage", Seasons.foliage(doy))
	rs.global_shader_parameter_set("autumn", Seasons.autumn(doy))
	rs.global_shader_parameter_set("wind_strength", clampf(wind / WIND_STRENGTH_FULL, 0.0, 1.0))   # zpětná kompatibilita (M8.4: = speed/12)
	_set_wind_globals()


## Jas jasné oblohy pro adaptaci oka – geometrický průměr (zenit ×2, obzor ke slunci a od slunce), aby jasný
## západ u obzoru „nepřehlušil“ tmavnoucí zenit, který svítí na zem.
func _sky_avg_lum(sd: Vector3, turb: float) -> float:
	var hz := Vector3(sd.x, 0.0, sd.z)
	hz = hz.normalized() if hz.length() > 1e-4 else Vector3(1.0, 0.0, 0.0)
	return _geo_lum(SkyModel.clear_sky(Vector3.UP, sd, turb), SkyModel.clear_sky(hz, sd, turb),
		SkyModel.clear_sky(-hz, sd, turb))


func _geo_lum(zen: Vector3, hs: Vector3, ha: Vector3) -> float:
	var lz := log(maxf(SkyModel.luminance(zen), 1e-12))
	var ls := log(maxf(SkyModel.luminance(hs), 1e-12))
	var la := log(maxf(SkyModel.luminance(ha), 1e-12))
	return exp((lz * 2.0 + ls + la) * 0.25) * SKY_SUN_E


## 10/2026: barvy pro fyzikální oblohu (~4× za s) – stejný model rozptylu jako shader: zisk adaptace oka
## v soumraku, barva slunce (propustnost atmosféry), světlo na mraky v 1,6 a 8 km, barva obzoru (mlha) a země.
func _sky_light(sd: Vector3, md: Vector3, elev: float, haze: float, cloud: float, dark: float, moon_up: float) -> void:
	var turb := SKY_TURB + SKY_TURB_HAZE * haze
	var hz := Vector3(sd.x, 0.0, sd.z)
	hz = hz.normalized() if hz.length() > 1e-4 else Vector3(1.0, 0.0, 0.0)
	var hp := Vector3(-hz.z, 0.0, hz.x)
	var zen := SkyModel.clear_sky(Vector3.UP, sd, turb)
	var hs := SkyModel.clear_sky(hz, sd, turb)
	var ha := SkyModel.clear_sky(-hz, sd, turb)
	var h90 := SkyModel.clear_sky(hp, sd, turb, 6)
	var lum := _geo_lum(zen, hs, ha)
	# oko se v soumraku roztáhne: tmavnutí oblohy se stlačí (fyzikálně ~1000× za občanský soumrak → ~20×)
	_sky_gain = clampf(pow(maxf(lum, 1e-9) / _lum_ref, -SKY_GAIN_K), 1.0, SKY_GAIN_MAX)
	var e := SKY_SUN_E * _sky_gain
	var wb := _wb
	var night := smoothstep(-4.0, -14.0, elev)
	var ov := smoothstep(0.72, 0.97, cloud)
	_sun_col = SkyModel.transmittance(SkyModel.H0_KM, sd.y, turb) * wb
	var ts_c := SkyModel.transmittance(SkyModel.H0_KM + 1.6, sd.y, turb) * wb
	var ts_ci := SkyModel.transmittance(SkyModel.H0_KM + 8.0, sd.y, turb) * wb
	var moon_e := MOON_SKY * clock.moon_illumination() * moon_up
	var moon_tint := Vector3(0.30, 0.42, 0.75) * moon_e
	var avg_h := (hs + ha + h90 * 2.0) * 0.25 * wb
	var side_h := (ha + h90 * 2.0) / 3.0 * wb           # obzor mimo slunce – barva mlhy (záři ke slunci dodá fog_sun_scatter)
	var zen_w := zen * wb
	var amb := (zen_w * 0.5 + avg_h * 0.5) * (e * CLOUD_AMB_K) + NIGHT_SKY * 2.0 + moon_tint * 1.2
	var csun := ts_c * (e * CLOUD_SUN_K)
	# obzor: jasná obloha, při zatažení šedá vrstva (stejně jako shader), noc a měsíc
	_horizon = side_h * e + NIGHT_SKY * 2.5 + moon_tint * 1.5
	var sl := SkyModel.luminance(csun)
	var st := (csun * 0.4 + Vector3.ONE * sl * 0.6) * 0.2 * 0.75 + amb * 0.38
	st *= 1.0 - dark * 0.55
	_horizon = _horizon.lerp(st, ov)
	var sun_k := maxf(sd.y, 0.0) * GROUND_SUN_K * (1.0 - ov * 0.9)
	var ground := GROUND_ALBEDO * (_sun_col * (e * sun_k) + (zen_w + avg_h) * (0.5 * e) * (1.0 - ov * 0.5) + st * ov) \
		+ NIGHT_SKY * 0.6
	_cloud_thr = cloud_threshold(clampf(cloud, 0.0, 1.0))
	var m := sky_mat
	m.set_shader_parameter("white_bal", wb)
	m.set_shader_parameter("turbidity", turb)
	m.set_shader_parameter("sun_e", SKY_SUN_E)
	m.set_shader_parameter("sky_gain", _sky_gain)
	m.set_shader_parameter("sky_night", night)
	m.set_shader_parameter("sun_disk", _sun_col * (SKY_SUN_E * SUN_DISK_K * _sky_gain))
	m.set_shader_parameter("cloud_sun", csun)
	m.set_shader_parameter("cirrus_sun", ts_ci * (e * CLOUD_SUN_K))
	m.set_shader_parameter("cloud_amb", amb)
	m.set_shader_parameter("horizon_col", _horizon)
	m.set_shader_parameter("ground_col", ground)
	m.set_shader_parameter("night_col", NIGHT_SKY)
	m.set_shader_parameter("moon_e", moon_e)
	m.set_shader_parameter("cloud_thr", _cloud_thr)


## Hustota mraků na obloze ve směru `d` (0..1) – týž šum a práh jako shader (bez jemného detailu); pro stín mraku.
func _cloud_at(d: Vector3, cloud: float) -> float:
	if d.y <= 0.0:
		return smoothstep(0.72, 0.97, cloud)
	var img := cloud_noise_image()
	var r0 := SkyModel.R_KM + SkyModel.H0_KM
	var rc := SkyModel.R_KM + 1.6
	var b := r0 * d.y
	var t := -b + sqrt(b * b + rc * rc - r0 * r0)
	var uv := Vector2(d.x, d.z) * (t / 9.0) + _cloud_off
	var n := img.get_width()
	var p := Vector2(fposmod(uv.x, 1.0), fposmod(uv.y, 1.0)) * float(n) - Vector2(0.5, 0.5)
	var x0 := int(floor(p.x))
	var y0 := int(floor(p.y))
	var fx := p.x - float(x0)
	var fy := p.y - float(y0)
	var s := 0.0
	for k in 4:
		var xi := posmod(x0 + (k & 1), n)
		var yi := posmod(y0 + (k >> 1), n)
		var c := img.get_pixel(xi, yi)
		var w := (fx if k & 1 else 1.0 - fx) * (fy if k >> 1 else 1.0 - fy)
		s += (c.r * 0.58 + c.g * 0.42) * w
	var dens := clampf((s - _cloud_thr) / maxf(1.0 - _cloud_thr, 0.05) * 1.7, 0.0, 1.0)
	return maxf(dens, smoothstep(0.72, 0.97, cloud) * 0.9)


## M8.4: globální uniformy větru pro vegetaci (include/wind.gdshaderinc) – stejná data jako `WindField`.
var _gust_set := false
func _set_wind_globals() -> void:
	var rs := RenderingServer
	if wind_field == null:
		rs.global_shader_parameter_set("wind_hier", 0.0)
		return
	if not _gust_set and wind_field.gust_texture != null:
		rs.global_shader_parameter_set("wind_gust", wind_field.gust_texture)
		_gust_set = true
	rs.global_shader_parameter_set("wind_dir", wind_field.dir())
	rs.global_shader_parameter_set("wind_speed", wind_field.speed())
	rs.global_shader_parameter_set("wind_offset", wind_field.offset)
	rs.global_shader_parameter_set("wind_time", wind_field.time)
	rs.global_shader_parameter_set("wind_hier", 1.0 if wind_field.enabled() else 0.0)


## M8.9: vzhled mikroklimatu (`MicroFx`) – `Microclimate` si najde přes Weather → World (null = staré chování).
var _micro_fx: MicroFx
func _micro_fx_update(cam: Camera3D, delta: float) -> void:
	if _micro_fx == null:
		_micro_fx = MicroFx.new()
	if _micro_fx.micro == null and weather != null:
		_micro_fx.micro = weather.get_parent().get("micro") as Microclimate
	_micro_fx.update(env, cam, delta, _indoor_s)


## Natočí směrové světlo tak, aby svítilo ze směru `to_light` (jednotkový vektor ke zdroji).
func _aim(l: DirectionalLight3D, to_light: Vector3) -> void:
	var dir := -to_light.normalized()
	var up := Vector3.UP if absf(dir.y) < 0.98 else Vector3.FORWARD
	l.global_transform = Transform3D(Basis.looking_at(dir, up), l.global_position)


func _loop(p: AudioStreamPlayer, name_: String, amount: float, db_min: float, db_max: float) -> void:
	if amount <= 0.01:
		if p.playing:
			p.volume_db = move_toward(p.volume_db, -60.0, 1.5)
			if p.volume_db <= -59.0:
				p.stop()
		return
	if not p.playing:
		p.stream = NatureSfx.get_stream(name_)
		p.volume_db = -60.0
		p.play()
	var want := lerpf(db_min, db_max, sqrt(amount))
	p.volume_db = move_toward(p.volume_db, want, 1.0)


# ------------------------------------------------------------------ blesky

func _on_lightning(pos: Vector3) -> void:
	var cam := get_viewport().get_camera_3d()
	var dist := cam.global_position.distance_to(pos) if cam else 1500.0
	var power := clampf(1.3 - dist / FLASH_POWER_DIST, 0.25, 1.0)
	# 2–4 záblesky těsně po sobě (zpětné výboje)
	_flash_seq.clear()
	var t := 0.0
	for i in randi_range(2, 4):
		_flash_seq.append([t, power * randf_range(0.6, 1.0)])
		t += randf_range(0.06, 0.18)
	# hrom se zpožděním podle rychlosti zvuku, vzdálený je tišší a hlubší
	var delay := dist / SOUND_SPEED
	get_tree().create_timer(delay).timeout.connect(_play_thunder.bind(dist))


func _play_thunder(dist: float) -> void:
	for p in _thunder:
		if not p.playing:
			p.stream = NatureSfx.get_stream("thunder")
			p.pitch_scale = clampf(1.15 - dist / 6000.0, 0.6, 1.2) * randf_range(0.9, 1.05)
			p.volume_db = clampf(2.0 - dist / 180.0, -26.0, 2.0)
			p.play()
			return


func _update_flash(delta: float) -> void:
	_flash = move_toward(_flash, 0.0, delta * FLASH_DECAY)
	for i in range(_flash_seq.size() - 1, -1, -1):
		_flash_seq[i][0] -= delta
		if _flash_seq[i][0] <= 0.0:
			_flash = maxf(_flash, _flash_seq[i][1])
			_flash_seq.remove_at(i)
