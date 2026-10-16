// Vegetace (Fáze 9 – §9.4): trsy, kopřivy, keře, obilné řádky a plevel v MultiMeshích
// (VegetationManager). Modely z tools/gen_vegetation_meshes.gd – UV.y = poměrná výška
// vrcholu (0 patka, 1 špička), albedo v barvách vrcholů, INSTANCE_CUSTOM.rgb = tint
// instance a INSTANCE_CUSTOM.a = číslo pole / 255 (jen plodiny na orné půdě).
//
// Vítr (M8.4): `wind_grass` z include/wind.gdshaderinc – ohyb od kořene ∝ v², náraz z globální textury
// `wind_gust` (stejné pole jako WindField) a krátká vlna běžící po větru. Stará cesta (wind_hier = 0):
// `wind_strength` (VegetationManager, 0..2) + globální `wind_dir`. Fáze mávání = INSTANCE_ID + poloha instance – trsy se nevlní synchronně.
// Ohyb roste s UV.y² (patka stojí, špička mává). Směr větru se přepočítává do lokálního
// prostoru instance transponovanou bází (instance mají náhodnou rotaci kolem Y).
//
// Sezóny: `season_mode` 0 = bylina (tint podle globálního grass_green), 1 = keř (podle
// foliage zmenší a zhnědne), 2 = plodina (barva a růst z `field_lut` = ta samá tabulka
// 256×2, kterou Fields.lut_image dodává terénnímu shaderu – zralost i posklizňové
// strniště se drží skutečného pole). Sníh bělí špičky a vegetaci mírně shrnuje.
//
// M8.14 Přízemní vegetace (include/ground_veg.gdshaderinc, globální vstupy plní Meadows / Footpaths / GroundVegFx):
//   * `veg_color_mode` 1 = nové typy podle konvence barev vrcholů (00_PRINCIPY kap. 4: r ohebnost, g fáze, b list,
//     a okluze) – albedo z uniformů `veg_lo` → `veg_hi` po výšce (UV.y), `veg_acc` pro květ / bobule (UV.x > 0,5);
//     0 = staré modely (albedo v barvách vrcholů).
//   * `season_mode` 3 = jarní efemér (sasanky, dymnivky – kvetou před olistěním), 4 = beze změny (hrabanka, mech).
//   * `veg_mow` – výška podle porostu louky (`meadow_h`: po seči nízká a zelenější), `veg_path` – na pěšině nižší
//     a řidší, `veg_trample` – ohyb od hráče / NPC / zvířat / kol (sešlapání kolem kamery).
shader_type spatial;
render_mode cull_disabled, diffuse_burley;

uniform float wind_strength = 0.0;             // 0..2 (Weather.wind / 10) – stará cesta (wind_hier = 0)
// M8.4: směr větru je globální `wind_dir` (include/wind.gdshaderinc, nastavuje Atmosphere z World.wind_field)
uniform float bend_k = 1.0;                    // citlivost typu na vítr (keř < tráva)
uniform int season_mode = 0;                   // 0 bylina, 1 keř, 2 plodina (field_lut)
uniform sampler2D field_lut : filter_nearest, repeat_disable;
uniform int veg_color_mode = 0;                // M8.14: 0 albedo v barvách vrcholů, 1 konvence kap. 4 + barvy z uniformů
uniform vec3 veg_lo : source_color = vec3(0.2, 0.35, 0.1);    // M8.14: barva u patky
uniform vec3 veg_hi : source_color = vec3(0.4, 0.55, 0.2);    // M8.14: barva špičky
uniform vec3 veg_acc : source_color = vec3(0.6, 0.3, 0.7);    // M8.14: květ / bobule (UV.x > 0,5)
uniform float veg_mow = 0.0;                   // M8.14: 1 = výška podle seče louky (meadow_h)
uniform float veg_path = 0.0;                  // M8.14: 1 = pěšina sníží a proředí
uniform float veg_trample = 0.0;               // M8.14: citlivost na sešlapání (0 = nehýbe se)

global uniform float snow_cover;               // sníh na zemi 0..1 (Atmosphere)
global uniform float grass_green;              // svěžest trávy 0..1 (Seasons.GREEN)
global uniform float foliage;                  // olistění listnáčů 0..1 (Seasons.FOLIAGE)
global uniform float autumn;                   // podzim 0..1 (Seasons.autumn) – M8.14 jarní efeméry v létě a na podzim nejsou
global uniform float micro_dew;                // M8.9: rosa 0..1 (Microclimate → MicroFx)
global uniform float micro_frost;              // M8.9: 1 = rosa na dně údolí zmrzlá (jinovatka)
global uniform float micro_frost_y;            // M8.9: svět Y, pod kterým je zem zmrzlá

#include "res://shaders/include/wind.gdshaderinc"
#include "res://shaders/include/ground_veg.gdshaderinc"

varying vec3 v_col;
varying float v_snow;
varying float v_dew;                           // M8.9: rosa (lesk)
varying float v_rime;                          // M8.9: jinovatka (bělavé špičky)

void vertex() {
	vec3 tint = INSTANCE_CUSTOM.rgb;
	float grow = 1.0;
	vec3 org = MODEL_MATRIX[3].xyz;

	if (season_mode == 2 && INSTANCE_CUSTOM.a > 0.004) {
		// plodina: barva a stav pole z kalendáře (řádek 0 = barva+síla, řádek 1 = rýhy)
		float fid = floor(INSTANCE_CUSTOM.a * 255.0 + 0.5);
		vec2 fuv = vec2((fid + 0.5) / 256.0, 0.25);
		vec4 fc = texture(field_lut, fuv);
		vec4 fm = texture(field_lut, vec2(fuv.x, 0.75));
		float bare = clamp(fm.r * 1.3, 0.0, 1.0);          // rýhy = posečeno/zaoráno → strniště
		grow = mix(grow, 0.06, bare);
		grow *= 1.0 - fm.b;                                  // M8.12: zakrslé obilí (sucho, slabý vzrůst – Fields._short_of)
		tint *= mix(vec3(1.0), fc.rgb * 1.7 + vec3(0.12), 0.8);
	} else if (season_mode == 0) {
		tint *= mix(vec3(1.3, 1.15, 0.75), vec3(1.0), grass_green);   // zima/sucho → sláma
	} else if (season_mode == 1) {
		tint *= mix(vec3(1.0), vec3(0.75, 0.62, 0.45), (1.0 - foliage) * 0.55);  // keř zezelená
		grow *= 0.75 + 0.25 * foliage;                                //   a v zimě „spadne“ listí
	} else if (season_mode == 3) {
		// M8.14 jarní efemér: vidět jen mezi táním a olistěním korun (zelená tráva, holé koruny, ne podzim)
		grow *= clamp(grass_green * (1.0 - foliage) * (1.0 - autumn) * 2.5, 0.0, 1.0);
	}
	// M8.14: louka po seči / pastvě nízká (a svěže zelená), na pěšině nižší a řidší
	if (veg_mow > 0.0) {
		float mrel = gv_meadow_rel(org.xz);
		grow *= mix(1.0, max(mrel, 0.06), veg_mow);
		tint *= mix(vec3(0.9, 1.1, 0.88), vec3(1.0), clamp(mrel * 1.6, 0.0, 1.0));
	}
	if (veg_path > 0.0) {
		float pw = gv_path_wear(org.xz) * veg_path;
		if (pw > 0.003) {
			grow *= 1.0 - 0.7 * clamp(pw, 0.0, 1.0);
			if (wind_hash(org * 1.37 + 0.5) < pw * 0.85) {
				grow = 0.0;                                  // proředění: trs na pěšině chybí
			}
		}
	}

	VERTEX.y *= grow;
	if (grow <= 0.0) {
		VERTEX = vec3(0.0);                                  // zhroucená instance se nevykreslí
	}
	float sc = max(length(MODEL_MATRIX[0].xyz), 0.001);
	float flex = veg_color_mode == 1 ? COLOR.r : UV.y;      // M8.14: ohebnost z barvy vrcholu (kap. 4)
	if (wind_hier > 0.5) {
		// M8.4: ohyb od kořene, náraz z pole větru a vlna po větru (přes obilí běží viditelné vlny)
		float plant_h = max(VERTEX.y * sc / max(UV.y, 0.1), 0.1);
		vec3 off_m = wind_grass(org, flex, plant_h, bend_k);
		VERTEX += transpose(mat3(MODEL_MATRIX)) * off_m / (sc * sc);
	} else {
	float bend = UV.y * UV.y;
	float phase = float(INSTANCE_ID) * 0.618 + org.x * 0.37 + org.z * 0.53;
	float wave = sin(TIME * (1.3 + wind_strength) + phase)
		+ 0.4 * sin(TIME * 3.1 + phase * 1.7 + VERTEX.y * 4.0);
	vec2 wdir = normalize(wind_dir + vec2(0.001));
	vec3 off_w = vec3(wdir.x * (0.6 + 0.4 * wave) + sin(phase * 2.9) * 0.12,
		0.0,
		wdir.y * (0.6 + 0.4 * wave) + cos(phase * 2.3) * 0.12);
	// do lokálního prostoru instance (transponovaná báze = inverze rotace; měřítko vyňato)
	vec3 off = transpose(mat3(MODEL_MATRIX)) * off_w / sc;
	VERTEX += off * (bend * bend_k * (0.15 + wind_strength * 0.13));
	}
	// M8.14: sešlapání – rostlina se sklopí od hráče / NPC / zvířat / kol a pomalu narovná (síla zdroje klesá)
	if (veg_trample > 0.0 && grow > 0.0) {
		vec3 off_t = gv_trample(org, max(VERTEX.y, 0.0) * sc, veg_trample * flex, CAMERA_POSITION_WORLD);
		VERTEX += transpose(mat3(MODEL_MATRIX)) * off_t / (sc * sc);
	}

	if (veg_color_mode == 1) {
		vec3 base = mix(veg_lo, veg_hi, clamp(UV.y, 0.0, 1.0));
		base = UV.x > 0.5 ? veg_acc : base;
		v_col = base * (0.55 + 0.45 * COLOR.a) * tint;
	} else {
		v_col = COLOR.rgb * tint;
	}
	v_snow = snow_cover * smoothstep(0.15, 0.9, UV.y + NORMAL.y * 0.4);
	float rime_k = micro_dew * micro_frost * smoothstep(micro_frost_y + 8.0, micro_frost_y - 8.0, org.y);
	v_rime = rime_k * smoothstep(0.2, 0.9, UV.y) * (1.0 - snow_cover);
	v_dew = max(micro_dew - rime_k, 0.0) * (1.0 - snow_cover);
}

void fragment() {
	vec3 c = v_col;
	c = mix(c, vec3(0.85, 0.87, 0.92), clamp(v_snow * 0.85, 0.0, 0.8));
	c = mix(c, vec3(0.82, 0.86, 0.9), clamp(v_rime * 0.6, 0.0, 0.6));   // M8.9 jinovatka
	ALBEDO = c;
	ROUGHNESS = mix(0.85, 0.4, v_dew);              // M8.9: orosená tráva se leskne
	SPECULAR = mix(0.3, 0.55, v_dew);
	BACKLIGHT = c * 0.3;                            // prosycení proti světlu (listy/tráva)
}
