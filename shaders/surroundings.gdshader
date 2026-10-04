// Krajina za okrajem katastru (M6.2): hrubá výšková mřížka okolí (data/surround_height.bin,
// krok ~25 m) čtená ve vertex shaderu – vzor terrain.gdshader. Barva z masky povrchu
// (data/surround_surface.bin, třídy jako SurfaceMap + 8 voda); bez ní jen tráva.
// Oblast katastru se zapustí `hole_sink` pod detailní terén (ať se nepřekrývá), okraje
// dlaždic mají sukně. Bez textur – jen ploché barvy tříd + šum (daleko za mlhou stačí).
shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D height_tex : filter_nearest, repeat_disable;
uniform sampler2D surface_tex : filter_nearest, repeat_disable;   // R8 třída; ≤2 px = bez masky
uniform sampler2D detail_noise : filter_linear_mipmap, repeat_enable;
uniform vec2 grid_origin;       // x0, z0 hrany buňky (0,0) v metrech (Godot souřadnice)
uniform float spacing = 25.0;
uniform vec2 grid_size;         // nx, nz (počet BODŮ mřížky)
uniform vec4 kat_rect;          // x0, z0, šířka, výška – obdélník detailního terénu (katastr)
uniform float hole_sink = 3.0;  // zapuštění pod detailní terén uvnitř katastru (m)
uniform float hole_blend = 30.0;// náběh zapuštění od hranice katastru dovnitř (m)
uniform float skirt_depth = 60.0;

// roční období a počasí – sdílené globální parametry (nastavuje Atmosphere)
global uniform float snow_cover;
global uniform float wetness;
global uniform float grass_green;

varying vec3 wpos;

vec3 s2l(vec3 c) {
	return pow(c, vec3(2.2));
}

// stejná paleta tříd jako flat_color() v terrain.gdshader (+ 8 voda)
vec3 flat_color(int c) {
	if (c == 1) return s2l(vec3(0.45, 0.34, 0.24));   // orná půda
	if (c == 2) return s2l(vec3(0.40, 0.52, 0.24));   // sad / zahrada
	if (c == 3) return s2l(vec3(0.20, 0.26, 0.12));   // les (tmavší skvrna)
	if (c == 4) return s2l(vec3(0.50, 0.45, 0.37));   // zástavba / dvůr (obce jako skvrny)
	if (c == 5) return s2l(vec3(0.30, 0.25, 0.18));   // břeh / mokřad
	if (c == 6) return s2l(vec3(0.46, 0.44, 0.41));   // skála
	if (c == 7) return s2l(vec3(0.50, 0.44, 0.34));   // polní cesta
	if (c == 8) return s2l(vec3(0.16, 0.30, 0.36));   // voda
	return s2l(vec3(0.36, 0.50, 0.20));               // tráva / louka
}

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX.x, 0.0, VERTEX.z, 1.0)).xyz;
	vec2 cell = clamp(round((w.xz - grid_origin) / spacing), vec2(0.0), grid_size - 1.0);
	float h = texelFetch(height_tex, ivec2(cell), 0).r;
	// díra pro katastr: uvnitř obdélníku detailního terénu se plocha zapustí pod něj;
	// u hranice náběh (díky stejnému DMR na okraji navazuje bez švu)
	vec2 inn = min(w.xz - kat_rect.xy, kat_rect.xy + kat_rect.zw - w.xz);
	float sink = 0.0;
	if (inn.x > 0.0 && inn.y > 0.0) {
		sink = hole_sink * smoothstep(0.0, hole_blend, min(inn.x, inn.y));
	}
	if (VERTEX.y < -0.5) {
		sink += skirt_depth;        // sukně okrajů dlaždic
	}
	VERTEX.y = h - sink;
	wpos = vec3(w.x, VERTEX.y, w.z);
}

void fragment() {
	vec2 gcell = clamp((wpos.xz - grid_origin) / spacing, vec2(0.0), grid_size - 1.0);
	ivec2 ic = ivec2(gcell + 0.5);
	int c = 0;
	ivec2 sz = textureSize(surface_tex, 0);
	if (sz.x > 2) {
		c = int(texelFetch(surface_tex, clamp(ic, ivec2(0), sz - 1), 0).r * 255.0 + 0.5);
	}
	float d1 = texture(detail_noise, wpos.xz * 0.037).r;
	float d2 = texture(detail_noise, wpos.xz * 0.006 + 0.31).r;
	vec3 col = flat_color(c);
	col *= (0.82 + 0.36 * d2) * (0.92 + 0.16 * d1);
	// sezóna: zeleň hnědne, les drží barvu (v listopadu lehce zrzne)
	float grassy = (c == 0 || c == 2) ? 1.0 : ((c == 1) ? 0.3 : 0.0);
	vec3 dry = vec3(dot(col, vec3(0.3, 0.5, 0.2))) * vec3(1.18, 1.0, 0.7);
	col = mix(col, dry, (1.0 - grass_green) * 0.7 * grassy);
	if (c == 3) {
		col = mix(col, dry * vec3(1.05, 0.85, 0.7), (1.0 - grass_green) * 0.25);
	}
	// levná normála z výškové mřížky (diference sousedních buněk)
	float hx = texelFetch(height_tex, ivec2(min(ic.x + 1, int(grid_size.x) - 1), ic.y), 0).r
		- texelFetch(height_tex, ivec2(max(ic.x - 1, 0), ic.y), 0).r;
	float hz = texelFetch(height_tex, ivec2(ic.x, min(ic.y + 1, int(grid_size.y) - 1)), 0).r
		- texelFetch(height_tex, ivec2(ic.x, max(ic.y - 1, 0)), 0).r;
	vec3 n = normalize(vec3(-hx / (2.0 * spacing), 1.0, -hz / (2.0 * spacing)));
	// sníh na rovinách, mokro tmaví
	float snow = clamp((snow_cover * 1.35 - (1.0 - d2) * 0.35 - (1.0 - d1) * 0.12) * 1.6, 0.0, 1.0) * smoothstep(0.55, 0.85, n.y);
	float wet = wetness * (1.0 - snow);
	col *= 1.0 - 0.32 * wet;
	col = mix(col, vec3(0.9, 0.92, 0.96) * (0.92 + 0.08 * d1), snow);
	ALBEDO = col * 1.05;
	if (c == 8) {
		// voda: lehký lesk místo matného povrchu
		ROUGHNESS = 0.35;
		SPECULAR = 0.6;
	} else {
		ROUGHNESS = mix(mix(0.95, 0.6, wet), 0.8, snow);
		SPECULAR = 0.3;
	}
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
}
