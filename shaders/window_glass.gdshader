// Okno na fasádě: neprůhledné tmavé sklo s odrazem oblohy (Fresnel – radiance prostředí při nízké drsnosti),
// rámy a příčky podle typu okna, záclona v horní části a noční svícení.
// Jeden quad = jedno okno (UV 0–1, y nahoru). Barva vrcholu nese vlastnosti okna:
//   R = náhodné číslo okna (svítí, když R + kolísání < lit_frac), G = variace (teplota světla, výška záclony, typ dělení),
//   B = druhé náhodné číslo (kolísání po půlhodinách), A = barva rámu / příček (1 bílá, ~0.6 hnědá, ~0.3 šedá).
// `lit_frac` a `slot` nastavuje BuildingDetails jednou za herní půlhodinu – žádné uzly na okno, žádná přestavba meshe.
// M8.17: UV2 = (index budovy, místnost 0 kuchyň / 1 obývák / 2 ložnice / 3 ostatní); při `house_mode` 1 se podíl
// svítících oken čte z textury `house_lit` (texel = budova, RGBA = místnosti; plní ji Households přes BuildingDetails).
// Soukromí (PRAVNI_DOPORUCENI.md): žádný průhled do interiéru – za sklem jen tma s neurčitým přechodem, záclona
// (od Vysoké s paralaxou 5 cm za sklem) a v noci rozptýlené světlo.
shader_type spatial;
render_mode cull_back, specular_schlick_ggx;

uniform float lit_frac = 0.0;
uniform float slot = 0.0;
uniform vec3 glass_color : source_color = vec3(0.03, 0.038, 0.05);
uniform vec3 curtain_color : source_color = vec3(0.86, 0.82, 0.72);
uniform vec3 lit_color : source_color = vec3(1.0, 0.72, 0.38);
uniform float lit_energy = 2.4;
uniform sampler2D house_lit : filter_nearest;
uniform float house_mode = 0.0;
uniform float dark = 1.0;
uniform int house_w = 64;
global uniform float gfx_quality;
global uniform float wetness;

varying flat float v_lit;
varying flat vec4 v_prop;
varying flat float v_room;

void vertex() {
	float jitter = fract(sin((COLOR.b + slot * 0.137) * 91.7) * 43758.5453) - 0.5;
	float frac = lit_frac;
	if (house_mode > 0.5 && UV2.x >= 0.0) {
		int idx = int(UV2.x + 0.5);
		vec4 l = texelFetch(house_lit, ivec2(idx % house_w, idx / house_w), 0);
		int room = int(UV2.y + 0.5);
		float f = room == 0 ? l.r : (room == 1 ? l.g : (room == 2 ? l.b : l.a));
		frac = f * dark;
	}
	v_lit = step(COLOR.r + jitter * 0.12, frac);
	v_prop = COLOR;
	v_room = UV2.y;
}

// Příčky okna: obvodový rám + dělení podle typu (dřevěné s nadsvětlíkem, plastové dvoukřídlé, jednoduché).
float bars_of(vec2 uv, vec4 prop) {
	float fr = 0.045;
	float b = max(max(step(uv.x, fr), step(1.0 - uv.x, fr)), max(step(uv.y, fr), step(1.0 - uv.y, fr)));
	b = max(b, step(abs(uv.x - 0.5), 0.028));                    // svislý střední sloupek (všechny typy)
	if (prop.a > 0.45 && prop.a < 0.8) {
		b = max(b, step(abs(uv.y - 0.68), 0.026));               // dřevěné: nadsvětlík
		if (prop.g > 0.55) {
			b = max(b, step(abs(uv.y - 0.34), 0.018));           // a ještě vodorovná příčka v dolních křídlech
		}
	} else if (prop.a >= 0.8) {
		if (prop.g < 0.5) {
			b = max(b, step(abs(uv.y - 0.7), 0.026));            // plastové s nadsvětlíkem, jinak jen dvě křídla
		}
	} else {
		b = max(b, step(abs(uv.y - 0.5), 0.03));                 // šedé (starší kovové): kříž
	}
	return b;
}

void fragment() {
	vec2 uv = UV;
	bool hq = gfx_quality > 1.5;
	// tečné vektory okna ve view space z derivací (mesh nemá tangenty): délka = rozměr okna v metrech
	vec3 dpx = dFdx(VERTEX);
	vec3 dpy = dFdy(VERTEX);
	vec2 dux = dFdx(UV);
	vec2 duy = dFdy(UV);
	float det = dux.x * duy.y - dux.y * duy.x;
	float bar = bars_of(uv, v_prop);
	// měkký stín rámu na skle (rám stojí před sklem)
	float near_bar = 1.0 - bars_of(uv + vec2(0.012, -0.018), v_prop) * (1.0 - bar);
	vec3 frame = vec3(0.85);
	if (v_prop.a < 0.8) {
		frame = vec3(0.30, 0.19, 0.11);
	}
	if (v_prop.a < 0.45) {
		frame = vec3(0.38, 0.39, 0.41);
	}
	// záclona: od Vysoké o 5 cm za sklem (paralaxa podle směru pohledu)
	vec2 cuv = uv;
	if (hq && abs(det) > 1e-14) {
		vec3 tu = (dpx * duy.y - dpy * dux.y) / det;
		vec3 tv = (dpy * dux.x - dpx * duy.x) / det;
		float lu = max(length(tu), 0.05);
		float lv = max(length(tv), 0.05);
		vec3 v = normalize(-VERTEX);
		float vn = max(dot(v, NORMAL), 0.15);
		cuv -= vec2(dot(v, tu) / lu / lu, dot(v, tv) / lv / lv) * (0.05 / vn);
	}
	float has_curtain = step(0.18, v_prop.g);
	float curtain_h = 0.28 + 0.3 * v_prop.g;
	float in_curtain = has_curtain * step(1.0 - curtain_h, cuv.y) * (1.0 - bar);
	// záclona: krajka dole roztřepená, záhyby
	float hem = 1.0 - curtain_h + 0.015 * sin(cuv.x * 60.0 + v_prop.b * 9.0);
	in_curtain *= step(hem, cuv.y);
	float folds = 0.84 + 0.16 * sin(cuv.x * 38.0 + v_prop.b * 6.0);
	vec3 warm = mix(lit_color, vec3(1.0, 0.9, 0.7), v_prop.g);
	// rozptýlené světlo místnosti: nejjasnější nahoře uprostřed (lampa), ke krajům a dolů slábne
	float glow = 0.62 + 0.38 * clamp(1.0 - length((uv - vec2(0.5, 0.78)) * vec2(1.1, 1.3)), 0.0, 1.0);
	float lit = v_lit;
	if (hq && lit > 0.5 && int(v_room + 0.5) == 1 && v_prop.b > 0.86) {
		// televize v obýváku: namodralé mihotání
		float fl = 0.65 + 0.35 * sin(TIME * 6.3 + v_prop.r * 40.0) * sin(TIME * 2.1 + v_prop.b * 17.0);
		warm = mix(warm, vec3(0.55, 0.7, 1.0), 0.6);
		lit *= fl;
	}
	if (bar > 0.5) {
		ALBEDO = frame;
		ROUGHNESS = 0.65;
		SPECULAR = 0.35;
	} else if (in_curtain > 0.5) {
		ALBEDO = curtain_color * folds * near_bar;
		ROUGHNESS = 0.95;
		SPECULAR = 0.35;      // záclona je za sklem – sklo dál odráží
		EMISSION = warm * lit * lit_energy * 0.55 * folds * glow;
	} else {
		// sklo: tmavá hloubka (dole a u rámu tmavší), odraz oblohy dělá radiance (Fresnel GGX)
		float depth = mix(0.7, 1.15, uv.y) * near_bar;
		ALBEDO = glass_color * depth;
		ROUGHNESS = 0.035;
		METALLIC = 0.0;
		SPECULAR = 0.85;
		if (hq) {
			// staré tabulové sklo: lehké zvlnění odrazů; za deště stékající kapky
			float wav = sin(uv.y * 31.0 + v_prop.b * 20.0 + sin(uv.x * 7.0) * 1.5) * 0.012;
			vec3 tvn = normalize(dpy * dux.x - dpx * duy.x);
			NORMAL = normalize(NORMAL + tvn * wav);
			if (wetness > 0.2) {
				vec2 dc = vec2(uv.x * 22.0, uv.y * 14.0 + TIME * 0.15 * step(0.5, fract(uv.x * 11.0)));
				float h = fract(sin(dot(floor(dc), vec2(12.9898, 78.233))) * 43758.5453);
				float drop = step(0.82, h) * (1.0 - smoothstep(0.15, 0.4, length(fract(dc) - 0.5)));
				ROUGHNESS = mix(0.035, 0.2, drop * wetness);
			}
		}
		EMISSION = warm * lit * lit_energy * (0.7 + 0.3 * v_prop.g) * glow;
	}
}
