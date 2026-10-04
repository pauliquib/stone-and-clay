// Okno na fasádě: neprůhledné tmavé sklo s leskem, příčky, záclona v horní části a noční svícení.
// Jeden quad = jedno okno (UV 0–1, y nahoru). Barva vrcholu nese vlastnosti okna:
//   R = náhodné číslo okna (svítí, když R + kolísání < lit_frac), G = variace (teplota světla, výška záclony),
//   B = druhé náhodné číslo (kolísání po půlhodinách), A = barva rámu / příček (1 bílá, ~0.6 hnědá, ~0.3 šedá).
// `lit_frac` a `slot` nastavuje BuildingDetails jednou za herní půlhodinu – žádné uzly na okno, žádná přestavba meshe.
shader_type spatial;
render_mode cull_back, specular_schlick_ggx;

uniform float lit_frac = 0.0;
uniform float slot = 0.0;
uniform vec3 glass_color : source_color = vec3(0.035, 0.045, 0.06);
uniform vec3 curtain_color : source_color = vec3(0.86, 0.82, 0.72);
uniform vec3 lit_color : source_color = vec3(1.0, 0.72, 0.38);
uniform float lit_energy = 2.4;

varying flat float v_lit;
varying flat vec4 v_prop;

void vertex() {
	float jitter = fract(sin((COLOR.b + slot * 0.137) * 91.7) * 43758.5453) - 0.5;
	v_lit = step(COLOR.r + jitter * 0.12, lit_frac);
	v_prop = COLOR;
}

void fragment() {
	vec2 uv = UV;
	float bar = max(step(abs(uv.x - 0.5), 0.03), step(abs(uv.y - 0.5), 0.03));
	bar = max(bar, max(step(uv.x, 0.045), max(step(1.0 - uv.x, 0.045), max(step(uv.y, 0.045), step(1.0 - uv.y, 0.045)))));
	float has_curtain = step(0.18, v_prop.g);
	float curtain_h = 0.28 + 0.3 * v_prop.g;
	float in_curtain = has_curtain * step(1.0 - curtain_h, uv.y) * (1.0 - bar);
	vec3 frame = vec3(0.85);
	if (v_prop.a < 0.8) {
		frame = vec3(0.30, 0.19, 0.11);
	}
	if (v_prop.a < 0.45) {
		frame = vec3(0.38, 0.39, 0.41);
	}
	float folds = 0.86 + 0.14 * sin(uv.x * 38.0 + v_prop.b * 6.0);
	vec3 warm = mix(lit_color, vec3(1.0, 0.9, 0.7), v_prop.g);
	if (bar > 0.5) {
		ALBEDO = frame;
		ROUGHNESS = 0.7;
		SPECULAR = 0.3;
	} else if (in_curtain > 0.5) {
		ALBEDO = curtain_color * folds;
		ROUGHNESS = 0.95;
		SPECULAR = 0.1;
		EMISSION = warm * v_lit * lit_energy * 0.55 * folds;
	} else {
		ALBEDO = glass_color;
		ROUGHNESS = 0.06;
		METALLIC = 0.15;
		SPECULAR = 0.9;
		EMISSION = warm * v_lit * lit_energy * (0.7 + 0.3 * v_prop.g);
	}
}
