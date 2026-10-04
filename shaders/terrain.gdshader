// Terén: výšky z DMR 5G (2 m) přímo z textury ve vertex shaderu (stejná data jako kolize),
// normály z předpočítané normálové mapy (osvětlení nezávislé na LOD). Barva: ve výchozím stavu procedurální materiály
// podle tříd povrchu (data/surface.bin, fallback landuse + hustota lesa + sklon); ortofoto ČÚZK jen po přepnutí use_ortho.
shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D height_tex : filter_nearest, repeat_disable;
uniform sampler2D normal_tex : filter_linear_mipmap, repeat_disable;
uniform sampler2D ortho_full : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D ortho_core : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D detail_noise : filter_linear_mipmap, repeat_enable;
uniform vec2 grid_origin;
uniform float spacing = 2.0;
uniform vec2 grid_size;
uniform vec4 full_rect;   // x0, z0, size_x, size_z
uniform vec4 core_rect;
uniform float skirt_depth = 4.0;
// pole a louky podle kalendáře (Fields: data/landuse.bin, tabulka barev plodin field_lut se přepočítává denně)
uniform sampler2D landuse_tex : filter_nearest, repeat_disable;   // R = třída plochy, G = číslo pole
uniform sampler2D field_lut : filter_nearest, repeat_disable;     // 256×2: barva + síla, rýhy + směr
uniform vec4 landuse_rect = vec4(0.0);   // x0, z0, šířka, výška (m); šířka 0 = vypnuto
uniform float meadow_bloom = 0.0;        // květy na loukách 0..1 (Seasons.bloom)
// procedurální povrch (M1.1): třídy 0 tráva, 1 orná půda, 2 sad / zahrada, 3 les, 4 dvůr, 5 břeh, 6 skála, 7 cesta
uniform bool use_ortho = false;                                     // true = barva z ortofota (porovnání, F2)
uniform sampler2D surface_tex : filter_nearest, repeat_disable;     // R8 = třída (data/surface.bin, 4 m)
uniform vec4 surface_rect = vec4(0.0);                              // x0, z0, šířka, výška (m); šířka 0 = soubor chybí
uniform sampler2D forest_tex : filter_linear, repeat_disable;       // fallback: R = hustota lesa 0..1 (Fauna.forest, 32 m)
uniform vec4 forest_rect = vec4(0.0);
uniform sampler2D tex_grass : source_color, hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_soil : source_color, hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_forest : source_color, hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_yard : source_color, hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_mud : source_color, hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_rock : source_color, hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform int tex_mask = 0;          // bity načtených textur: 1 tráva, 2 ornice, 4 les, 8 dvůr, 16 bahno, 32 skála (chybí = procedurální barva)
uniform float tex_scale = 4.0;     // velikost dlaždice textury v metrech
// roční období a počasí (globální parametry – nastavuje Atmosphere, výchozí hodnoty v project.godot)
global uniform float snow_cover;   // sníh na zemi 0..1
global uniform float wetness;      // mokrý povrch 0..1
global uniform float grass_green;  // svěžest trávy 0..1 (zima / sucho → hnědá)

varying vec3 wpos;

vec3 s2l(vec3 c) {
	return pow(c, vec3(2.2));
}

// plochá barva třídy (bez textur; vzdálené LOD a chybějící textury)
vec3 flat_color(int c) {
	if (c == 1) return s2l(vec3(0.45, 0.34, 0.24));
	if (c == 2) return s2l(vec3(0.40, 0.52, 0.24));
	if (c == 3) return s2l(vec3(0.22, 0.25, 0.13));
	if (c == 4) return s2l(vec3(0.52, 0.46, 0.38));
	if (c == 5) return s2l(vec3(0.30, 0.25, 0.18));
	if (c == 6) return s2l(vec3(0.46, 0.44, 0.41));
	if (c == 7) return s2l(vec3(0.50, 0.44, 0.34));
	return s2l(vec3(0.36, 0.50, 0.20));
}

// albedo třídy v bodě p (world XZ); texw 0..1 = kolik textury (0 = jen plochá barva); grassy = zda je to tráva (sezóna, květy)
vec3 class_albedo(int c, vec2 p, vec2 pdx, vec2 pdy, float d1, float d2, float d3, float texw, out float grassy) {
	vec3 col = flat_color(c);
	grassy = (c == 0 || c == 2) ? 1.0 : 0.0;
	if (texw > 0.0) {
		vec2 uv = p / tex_scale;
		vec2 gx = pdx / tex_scale;   // derivace se počítají mimo větvení (textureGrad), jinak by na hranicích tříd vznikaly artefakty mip-map
		vec2 gy = pdy / tex_scale;
		vec3 t = vec3(-1.0);
		if ((c == 0 || c == 2) && (tex_mask & 1) != 0) t = textureGrad(tex_grass, uv, gx, gy).rgb * (c == 2 ? vec3(1.04, 1.08, 0.94) : vec3(1.0));
		else if (c == 1 && (tex_mask & 2) != 0) t = textureGrad(tex_soil, uv, gx, gy).rgb;
		else if (c == 3 && (tex_mask & 4) != 0) t = textureGrad(tex_forest, uv, gx, gy).rgb;
		else if ((c == 4 || c == 7) && (tex_mask & 8) != 0) t = textureGrad(tex_yard, uv, gx, gy).rgb * (c == 7 ? vec3(1.0, 0.96, 0.9) : vec3(1.0));
		else if (c == 5 && (tex_mask & 16) != 0) t = textureGrad(tex_mud, uv, gx, gy).rgb;
		else if (c == 6 && (tex_mask & 32) != 0) t = textureGrad(tex_rock, uv, gx, gy).rgb;
		if (t.r >= 0.0) col = mix(col, t, texw);
	}
	// velké skvrny (sušší / sytější), střední a jemný šum
	float blotch = 0.8 + 0.4 * d3;
	col *= blotch * (0.9 + 0.2 * d2) * (0.92 + 0.16 * d1);
	if (grassy > 0.5) {
		col = mix(col, col * vec3(1.18, 1.06, 0.7), smoothstep(0.55, 0.38, d3) * 0.5 * grass_green);
		// mimo vegetační sezónu tráva hnědne
		vec3 dry = vec3(dot(col, vec3(0.3, 0.5, 0.2))) * vec3(1.18, 1.0, 0.7);
		col = mix(col, dry, (1.0 - grass_green) * 0.8);
	} else if (c == 3) {
		vec3 dry = vec3(dot(col, vec3(0.3, 0.5, 0.2))) * vec3(1.25, 1.0, 0.75);
		col = mix(col, dry, (1.0 - grass_green) * 0.3);   // opadané listí
	}
	return col;
}

// třída povrchu blokující pole (les, dvůr, břeh, cesta)
float blocks_field(int c) {
	return (c == 3 || c == 4 || c == 5 || c == 7) ? 1.0 : 0.0;
}

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX.x, 0.0, VERTEX.z, 1.0)).xyz;
	vec2 cell = clamp(round((w.xz - grid_origin) / spacing), vec2(0.0), grid_size - 1.0);
	float h = texelFetch(height_tex, ivec2(cell), 0).r;
	float skirt = VERTEX.y < -0.5 ? skirt_depth : 0.0;
	VERTEX.y = h - skirt;
	wpos = vec3(w.x, VERTEX.y, w.z);
}

void fragment() {
	vec2 nuv = ((wpos.xz - grid_origin) / spacing + 0.5) / grid_size;
	vec3 n = normalize(texture(normal_tex, nuv).rgb * 2.0 - 1.0);
	float d1 = texture(detail_noise, wpos.xz * 0.23).r;
	float d2 = texture(detail_noise, wpos.xz * 0.031).r;
	float d3 = texture(detail_noise, wpos.xz * 0.006 + 0.21).r;
	float dist = length(VERTEX);
	float dfade = 1.0 - smoothstep(30.0, 140.0, dist);
	vec2 pdx = dFdx(wpos.xz);
	vec2 pdy = dFdy(wpos.xz);
	vec3 wdx = dFdx(wpos);
	vec3 wdy = dFdy(wpos);
	// mapa využití ploch (pole, louky): hranice buněk 4 m se rozbíjí šumem
	int lcls = 0;
	int lid = 0;
	if (landuse_rect.z > 0.0) {
		vec2 lw = wpos.xz + (vec2(texture(detail_noise, wpos.xz * 0.043).r, texture(detail_noise, wpos.xz * 0.037 + 0.37).r) - 0.5) * 7.0;
		vec2 luv = (lw - landuse_rect.xy) / landuse_rect.zw;
		if (luv.x > 0.0 && luv.y > 0.0 && luv.x < 1.0 && luv.y < 1.0) {
			vec2 lu = texture(landuse_tex, luv).rg * 255.0;
			lcls = int(lu.x + 0.5);
			lid = int(lu.y + 0.5);
		}
	}
	vec3 col;
	float greenish;      // podíl zelené plochy (sezónní hnědnutí, květy na loukách)
	float field_keep = 1.0;   // kolik z pole se smí projevit (les, dvůr, břeh a cesta ho zakrývají)
	if (use_ortho) {
		vec2 fuv = (wpos.xz - full_rect.xy) / full_rect.zw;
		col = texture(ortho_full, fuv).rgb;
		vec2 cuv = (wpos.xz - core_rect.xy) / core_rect.zw;
		float edge = min(min(cuv.x, 1.0 - cuv.x), min(cuv.y, 1.0 - cuv.y)) * core_rect.z;
		float core_w = clamp(edge / 40.0, 0.0, 1.0);
		if (core_w > 0.0) {
			col = mix(col, texture(ortho_core, cuv).rgb, core_w);
		}
		// jemný detail zblízka (ortofoto má 0,13–0,66 m/px)
		col *= mix(1.0, 0.78 + 0.44 * d1, 0.55 * dfade) * (0.9 + 0.2 * d2);
		// roční období: zelené plochy (louky, pole, lesy na ortofotu) mimo vegetační sezónu hnědnou
		greenish = clamp((col.g - max(col.r, col.b)) * 7.0, 0.0, 1.0);
		vec3 dry = vec3(dot(col, vec3(0.3, 0.5, 0.2))) * vec3(1.18, 1.0, 0.7);
		col = mix(col, dry, greenish * (1.0 - grass_green) * 0.8);
		field_keep = smoothstep(0.012, 0.05, dot(col, vec3(0.3, 0.5, 0.2)));   // stíny stromů a tmavé plochy zůstanou z ortofota
	} else {
		// --- třída povrchu: dvě nejbližší třídy a jejich poměr (hranice rozbité šumem)
		vec2 warp = (vec2(texture(detail_noise, wpos.xz * 0.057 + 0.13).r, texture(detail_noise, wpos.xz * 0.051 + 0.71).r) - 0.5) * 6.0;
		vec2 wp = wpos.xz + warp;
		int ca = 0;
		int cb = 0;
		float tb = 0.0;
		if (surface_rect.z > 0.0) {
			ivec2 sz = textureSize(surface_tex, 0);
			vec2 g = (wp - surface_rect.xy) / surface_rect.zw * vec2(sz) - 0.5;
			ivec2 i0 = ivec2(floor(g));
			vec2 f = smoothstep(0.0, 1.0, fract(g));
			int c[4];
			float wt[4];
			for (int k = 0; k < 4; k++) {
				ivec2 q = clamp(i0 + ivec2(k & 1, k >> 1), ivec2(0), sz - 1);
				c[k] = int(texelFetch(surface_tex, q, 0).r * 255.0 + 0.5);
			}
			wt[0] = (1.0 - f.x) * (1.0 - f.y);
			wt[1] = f.x * (1.0 - f.y);
			wt[2] = (1.0 - f.x) * f.y;
			wt[3] = f.x * f.y;
			int ia = 0;
			for (int k = 1; k < 4; k++) {
				if (wt[k] > wt[ia]) ia = k;
			}
			ca = c[ia];
			float wa = 0.0;
			float bw = -1.0;
			int bi = -1;
			for (int k = 0; k < 4; k++) {
				if (c[k] == ca) {
					wa += wt[k];
				} else if (wt[k] > bw) {
					bw = wt[k];
					bi = k;
				}
			}
			if (bi >= 0) {
				cb = c[bi];
				float wb = 0.0;
				for (int k = 0; k < 4; k++) {
					if (c[k] == cb) wb += wt[k];
				}
				tb = smoothstep(0.3, 0.7, wb / max(wa + wb, 0.0001) + (d1 - 0.5) * 0.4);
			} else {
				cb = ca;
			}
		} else {
			// fallback bez surface.bin: pole / sady z landuse_tex, les z hustoty stromů (forest_tex)
			ca = (lcls == 1) ? 1 : ((lcls >= 3) ? 2 : 0);
			cb = ca;
			if (forest_rect.z > 0.0) {
				vec2 fuv2 = (wp - forest_rect.xy) / forest_rect.zw;
				float fd = texture(forest_tex, clamp(fuv2, vec2(0.0), vec2(1.0))).r;
				cb = 3;
				tb = smoothstep(0.3, 0.7, fd + (d1 - 0.5) * 0.3);
			}
		}
		// --- barva tříd (ve velké dálce jen plochá barva bez textur, LOD 3 = 32 m)
		float texw = 1.0 - smoothstep(700.0, 1100.0, dist);
		float ga;
		float gb;
		vec3 colA = class_albedo(ca, wpos.xz, pdx, pdy, d1, d2, d3, texw, ga);
		col = colA;
		greenish = ga;
		if (tb > 0.001 && cb != ca) {
			vec3 colB = class_albedo(cb, wpos.xz, pdx, pdy, d1, d2, d3, texw, gb);
			col = mix(colA, colB, tb);
			greenish = mix(ga, gb, tb);
		}
		field_keep = 1.0 - mix(blocks_field(ca), blocks_field(cb), tb);
		// --- svah: nad ~20° méně trávy (hlína), nad ~35° skála (triplanárně)
		float slope_soil = 1.0 - smoothstep(0.90, 0.95, n.y);
		if (slope_soil > 0.0) {
			float g0;
			vec3 soil = class_albedo(1, wpos.xz, pdx, pdy, d1, d2, d3, texw, g0);
			col = mix(col, soil, slope_soil * 0.6 * greenish);
			greenish *= 1.0 - slope_soil * 0.6;
		}
		float rockw = 1.0 - smoothstep(0.78, 0.86, n.y);
		if (rockw > 0.0) {
			vec3 rock = flat_color(6) * (0.8 + 0.4 * d1) * (0.85 + 0.3 * d2);
			if (texw > 0.0 && (tex_mask & 32) != 0) {
				vec3 bl = pow(abs(n), vec3(4.0));
				bl /= bl.x + bl.y + bl.z;
				vec3 rp = wpos / (tex_scale * 1.5);
				vec3 rdx = wdx / (tex_scale * 1.5);
				vec3 rdy = wdy / (tex_scale * 1.5);
				vec3 rt = textureGrad(tex_rock, rp.zy, rdx.zy, rdy.zy).rgb * bl.x + textureGrad(tex_rock, rp.xz, rdx.xz, rdy.xz).rgb * bl.y + textureGrad(tex_rock, rp.xy, rdx.xy, rdy.xy).rgb * bl.z;
				rock = mix(rock, rt, texw);
			}
			rock = mix(rock, flat_color(1) * (0.8 + 0.4 * d1), step(d2, 0.42) * 0.5);   // místy holá hlína
			col = mix(col, rock, rockw);
			greenish *= 1.0 - rockw;
			field_keep *= 1.0 - rockw;
		}
	}
	// pole podle plodiny a data (před sněhem a mokrem)
	if (lcls == 1) {
		vec4 lut = texelFetch(field_lut, ivec2(lid, 0), 0);
		vec4 fur = texelFetch(field_lut, ivec2(lid, 1), 0);
		vec3 cc = lut.rgb * (0.85 + 0.3 * d1) * (0.92 + 0.16 * d2);
		float across = fur.g > 0.5 ? wpos.x : wpos.z;
		cc *= 1.0 - fur.r * dfade * 0.24 * (0.5 + 0.5 * sin(across * 5.0));   // rýhy po orbě jen zblízka
		col = mix(col, cc, lut.a * field_keep);
	} else if (lcls >= 2) {
		// louky, sady a zahrádky: v době květu drobné bílé, žluté a fialové tečky
		float fn = texture(detail_noise, wpos.xz * 1.1).r;
		float spots = smoothstep(0.64, 0.72, fn) * meadow_bloom * greenish * dfade;
		vec3 fc = mix(vec3(0.85, 0.8, 0.62), vec3(0.9, 0.7, 0.1), step(0.5, d1));
		fc = mix(fc, vec3(0.5, 0.25, 0.6), step(0.75, d2));
		col = mix(col, fc, spots * 0.7);
	}
	// sníh: na rovině víc, na strmých svazích méně, okraje rozbité šumem
	float snow = clamp((snow_cover * 1.35 - (1.0 - d2) * 0.35 - (1.0 - d1) * 0.12) * 1.6, 0.0, 1.0) * smoothstep(0.55, 0.85, n.y);
	// mokro: tmavší a lesklejší povrch
	float wet = wetness * (1.0 - snow);
	col *= 1.0 - 0.32 * wet;
	col = mix(col, vec3(0.9, 0.92, 0.96) * (0.92 + 0.08 * d1), snow);
	ALBEDO = col * 1.05;
	ROUGHNESS = mix(mix(0.93, 0.5, wet), 0.75, snow);
	SPECULAR = mix(0.25, 0.45, wet);
	// drobná detailní normála z šumu
	float e = 0.02;
	float nx = texture(detail_noise, (wpos.xz + vec2(e * 8.0, 0.0)) * 0.23).r - d1;
	float nz = texture(detail_noise, (wpos.xz + vec2(0.0, e * 8.0)) * 0.23).r - d1;
	n = normalize(n + vec3(-nx, 0.0, -nz) * 1.2 * dfade * (1.0 - snow * 0.7));
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
}
