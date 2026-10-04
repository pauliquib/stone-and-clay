// Obloha: přechod zenit–obzor podle výšky slunce, červánky, halo a kotouč slunce, měsíc s fází,
// hvězdy, vrstva mraků (pokrytí, ztmavnutí deštěm, posun větrem), opar / mlha a záblesk blesku.
// Směry slunce a měsíce posílá skript (Atmosphere) – nezávisí na pořadí světel ve scéně.
shader_type sky;
render_mode use_debanding;

uniform vec3 sun_dir = vec3(0.0, 0.5, -0.8);
uniform vec3 moon_dir = vec3(0.0, 0.3, 0.9);
uniform float moon_light = 0.5;          // osvětlená část kotouče 0..1
uniform vec3 zenith_day : source_color = vec3(0.19, 0.38, 0.78);
uniform vec3 horizon_day : source_color = vec3(0.64, 0.77, 0.92);
uniform vec3 zenith_night : source_color = vec3(0.003, 0.006, 0.016);
uniform vec3 horizon_night : source_color = vec3(0.016, 0.024, 0.045);
uniform vec3 sunset_col : source_color = vec3(1.0, 0.42, 0.14);
uniform vec3 ground_col : source_color = vec3(0.16, 0.16, 0.15);
uniform sampler2D cloud_noise : filter_linear_mipmap, repeat_enable;
uniform float cloud_cover = 0.3;         // 0 jasno … 1 zataženo
uniform float cloud_dark = 0.0;          // 0..1 dešťová / bouřková oblačnost
uniform vec2 cloud_offset = vec2(0.0);   // posun větrem (skript)
uniform float haze = 0.0;                // opar, mlha 0..1
uniform float flash = 0.0;               // blesk 0..1
uniform float brightness = 1.0;

float hash3(vec3 p) {
	p = fract(p * vec3(443.897, 441.423, 437.195));
	p += dot(p, p.yzx + 19.19);
	return fract((p.x + p.y) * p.z);
}

float clouds(vec2 uv) {
	float n = texture(cloud_noise, uv * 0.35 + cloud_offset * 0.9).r * 0.55;
	n += texture(cloud_noise, uv * 0.9 + cloud_offset * 1.4).r * 0.3;
	n += texture(cloud_noise, uv * 2.6 + cloud_offset * 2.0).r * 0.15;
	return n;
}

void sky() {
	vec3 d = normalize(EYEDIR);
	vec3 sd = normalize(sun_dir);
	float sun_h = sd.y;
	float day = smoothstep(-0.12, 0.1, sun_h);
	float h = max(d.y, 0.0);

	// --- čistá obloha
	vec3 zen = mix(zenith_night, zenith_day, day);
	vec3 hor = mix(horizon_night, horizon_day, day);
	vec3 col = mix(hor, zen, pow(h, 0.42));
	float cs = max(dot(d, sd), 0.0);
	float low_sun = (1.0 - smoothstep(0.02, 0.32, sun_h)) * smoothstep(-0.16, -0.01, sun_h);
	col += sunset_col * low_sun * pow(1.0 - h, 5.0) * (0.25 + 0.75 * pow(cs, 4.0)) * 1.3;
	col += vec3(1.0, 0.86, 0.62) * (pow(cs, 10.0) * 0.35 + pow(cs, 90.0) * 0.8) * day;

	// --- noc: hvězdy a měsíc (jen v obraze, ne v odrazech)
	float night = 1.0 - smoothstep(-0.2, 0.02, sun_h);
	vec3 md = normalize(moon_dir);
	float mcos = dot(d, md);
	if (!AT_CUBEMAP_PASS && h > 0.0) {
		vec3 sp = floor(d * 420.0);
		float st = hash3(sp);
		float star = step(0.9965, st) * (0.4 + 0.6 * hash3(sp + 3.1));
		col += vec3(0.85, 0.9, 1.0) * star * night * (1.0 - cloud_cover) * smoothstep(0.0, 0.25, h) * 1.6;
	}
	float moon_disk = smoothstep(0.99993, 0.99996, mcos);
	col += vec3(0.95, 0.95, 0.88) * (moon_disk * (0.25 + 2.5 * moon_light) + pow(max(mcos, 0.0), 60.0) * 0.06 * moon_light) * night;

	// --- slunce
	if (!AT_CUBEMAP_PASS) {
		float disk = smoothstep(0.99985, 0.99992, cs);
		col += vec3(1.0, 0.93, 0.8) * disk * 40.0 * smoothstep(-0.02, 0.02, sun_h);
	}

	// --- mraky (vrstva nad hlavou; k obzoru prořídnou do oparu)
	if (d.y > 0.0) {
		vec2 uv = d.xz / (d.y + 0.12);
		float n = clouds(uv);
		float thr = 1.0 - cloud_cover;
		float c = smoothstep(thr - 0.08, thr + 0.25, n + cloud_cover * 0.28);
		c = clamp(c + smoothstep(0.75, 1.0, cloud_cover) * 0.8, 0.0, 1.0);
		c *= smoothstep(0.0, 0.12, d.y);
		// osvětlení mraků: prosvícené k slunci, spodek tmavší, déšť tmaví
		float lit = 0.55 + 0.45 * pow(cs, 3.0);
		float dens = smoothstep(0.35, 1.0, n) * 0.5 + cloud_dark * 0.55;
		vec3 cday = mix(vec3(1.0), vec3(0.42, 0.44, 0.48), dens) * lit;
		cday = mix(cday, cday * vec3(1.15, 0.72, 0.5), low_sun * 0.8);
		vec3 cnight = vec3(0.02, 0.022, 0.03) + vec3(0.05) * moon_light * night;
		vec3 ccol = mix(cnight, cday, day);
		col = mix(col, ccol, c);
	}
	// zataženo: celá obloha šedne
	float oc = smoothstep(0.7, 1.0, cloud_cover);
	vec3 grey = mix(vec3(0.02, 0.022, 0.028), mix(vec3(0.62, 0.64, 0.67), vec3(0.3, 0.31, 0.33), cloud_dark), day);
	col = mix(col, grey * (0.8 + 0.2 * h), oc * 0.85);

	// --- opar / mlha
	vec3 fogc = mix(vec3(0.03, 0.035, 0.045), vec3(0.72, 0.74, 0.76) * (1.0 - cloud_dark * 0.4), day);
	col = mix(col, fogc, clamp(haze * (1.0 - h * 0.5), 0.0, 1.0));

	// --- pod obzorem
	if (d.y < 0.0) {
		col = mix(col, ground_col * (0.08 + 0.92 * day) * (1.0 - cloud_cover * 0.4), smoothstep(0.0, -0.1, d.y));
	}
	col += vec3(0.75, 0.8, 1.0) * flash * (0.6 + 0.4 * h);
	COLOR = col * brightness;
}
