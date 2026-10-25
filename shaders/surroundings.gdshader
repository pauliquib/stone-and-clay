// Krajina za okrajem katastru (M6.2): hrubá výšková mřížka okolí (data/surround_height.bin,
// krok ~25 m) čtená ve vertex shaderu – vzor terrain.gdshader. Barva z masky povrchu
// (data/surround_surface.bin, třídy jako SurfaceMap + 8 voda); bez ní jen tráva.
// Oblast katastru se zapustí `hole_sink` pod detailní terén (ať se nepřekrývá), okraje
// dlaždic mají sukně. Barvy tříd počítá stejný kód jako detailní terén (terrain_surface.gdshaderinc)
// se zprůměrovaným jemným šumem a stejnými makro skvrnami → na hranici katastru bez švu.
// Orná půda = mozaika polí (pseudo-parcely ~400 × 250 m) s barvami plodin z téže tabulky `field_lut` jako v katastru.
shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D height_tex : filter_nearest, repeat_disable;
uniform sampler2D surface_tex : filter_nearest, repeat_disable;   // R8 třída; ≤2 px = bez masky
uniform sampler2D detail_noise : filter_linear_mipmap, repeat_enable;   // RGBA šum (Terrain.detail_noise_texture)
uniform sampler2D field_lut : filter_nearest, repeat_disable;     // tabulka barev plodin (Fields.lut_image, přes Terrain)
uniform bool use_fields = false;  // tabulka plodin je nastavená
uniform vec2 grid_origin;       // x0, z0 hrany buňky (0,0) v metrech (Godot souřadnice)
uniform float spacing = 25.0;
uniform vec2 grid_size;         // nx, nz (počet BODŮ mřížky)
uniform vec4 kat_rect;          // x0, z0, šířka, výška – obdélník detailního terénu (katastr)
uniform float hole_sink = 3.0;  // zapuštění pod detailní terén uvnitř katastru (m)
uniform float hole_blend = 30.0;// náběh zapuštění od hranice katastru dovnitř (m)
uniform float skirt_depth = 60.0;
// napojení na detailní terén: u hranice katastru vrcholy přebírají jeho výšku (stejná textura jako Terrain, bez kopie)
uniform sampler2D kat_height : filter_nearest, repeat_disable;
uniform vec3 kat_grid = vec3(0.0);   // krok mřížky terénu (m), počet bodů x, z; 0 = bez napojení
uniform float kat_join = 160.0;      // na jak dlouhém pásu za hranicí se výška přelévá z terénu do okolí (m)
uniform vec2 north_xz = vec2(-0.98, -0.20);   // sever (sněhové jazyky jako v terrain.gdshader)

// roční období a počasí – sdílené globální parametry (nastavuje Atmosphere)
global uniform float snow_cover;
global uniform float wetness;
global uniform float grass_green;
#include "res://shaders/include/terrain_surface.gdshaderinc"

varying vec3 wpos;
varying vec3 wnrm;

// stejné natočení makro šumu jako terrain.gdshader (ROT_A)
const mat2 ROT_A = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8));
const mat2 ROT_F = mat2(vec2(0.94, 0.34), vec2(-0.34, 0.94));   // směr parcel polí v okolí

// výška okolí bilineárně (vrcholy po 32 m nesedí na mřížku 25 m – nejbližší bod by dával zubaté tvary)
float sur_h(vec2 p) {
	vec2 g = clamp((p - grid_origin) / spacing, vec2(0.0), grid_size - 1.001);
	ivec2 i0 = ivec2(floor(g));
	vec2 f = g - vec2(i0);
	float a = texelFetch(height_tex, i0, 0).r;
	float b = texelFetch(height_tex, i0 + ivec2(1, 0), 0).r;
	float c = texelFetch(height_tex, i0 + ivec2(0, 1), 0).r;
	float d = texelFetch(height_tex, i0 + ivec2(1, 1), 0).r;
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// výška okolí s napojením na detailní terén: uvnitř katastru a na pásu `kat_join` za ním se bere výška terénu
// v nejbližším bodě katastru → na hranici bez schodu i bez mezery (šev skrývá sukně terénu)
float join_h(vec2 p) {
	float hs = sur_h(p);
	if (kat_grid.x <= 0.0) {
		return hs;
	}
	vec2 kmax = kat_rect.xy + kat_rect.zw;
	vec2 pc = clamp(p, kat_rect.xy, kmax);
	float dout = length(p - pc);
	if (dout >= kat_join) {
		return hs;
	}
	ivec2 kc = clamp(ivec2(round((pc - kat_rect.xy) / kat_grid.x)), ivec2(0), ivec2(kat_grid.yz) - 1);
	float hk = texelFetch(kat_height, kc, 0).r;
	return mix(hk, hs, smoothstep(0.0, kat_join, dout));
}

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX.x, 0.0, VERTEX.z, 1.0)).xyz;
	float h = join_h(w.xz);
	// normála z téže (bilineární, napojené) výšky po vrcholech – plynulé stínování místo kostek 25 m, fragment bez čtení
	float e = spacing;
	wnrm = normalize(vec3(join_h(w.xz - vec2(e, 0.0)) - join_h(w.xz + vec2(e, 0.0)), 2.0 * e,
		join_h(w.xz - vec2(0.0, e)) - join_h(w.xz + vec2(0.0, e))));
	// díra pro katastr: uvnitř obdélníku detailního terénu se plocha zapustí pod něj; u hranice náběh
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
	// šum jako v terrain.gdshader: jemné oktávy zdálky = průměr (nejmenší mip), skvrny a makro se čtou
	TsSig s;
	vec4 nmean = textureLod(detail_noise, vec2(0.5), 12.0);
	s.n0 = nmean;
	s.nf = nmean;
	s.n1 = texture(detail_noise, wpos.xz * 0.031 + vec2(0.5, 0.13));
	s.n2 = texture(detail_noise, wpos.xz * 0.006 + 0.21);
	s.nm = texture(detail_noise, ROT_A * wpos.xz * 0.0007 + vec2(0.37, 0.61));
	// třída: nejbližší buňka masky s hranicí rozbitou šumem (bez čtverců 25 m)
	vec2 warp = (s.n2.gr - 0.5) * spacing * 1.4 + (s.n1.gr - 0.5) * 8.0;
	vec2 gcell = clamp((wpos.xz + warp - grid_origin) / spacing, vec2(0.0), grid_size - 1.0);
	ivec2 ic = ivec2(gcell + 0.5);
	int c = 0;
	ivec2 sz = textureSize(surface_tex, 0);
	if (sz.x > 2) {
		c = int(texelFetch(surface_tex, clamp(ic, ivec2(0), sz - 1), 0).r * 255.0 + 0.5);
	}
	float hgt;
	float rough;
	float own_wet;
	float grassy;
	vec3 col = ts_class(c, s, grass_green, hgt, rough, own_wet, grassy);
	col = ts_macro(col, s, grassy, c == 3, grass_green);
	if (c == 1 && use_fields) {
		// mozaika polí: pseudo-parcela → číslo pole → barva plodiny pro dnešek (jako pole v katastru)
		vec2 q = ROT_F * (wpos.xz + warp * 1.5) / vec2(410.0, 260.0);
		vec2 pc = floor(q);
		int fid = 1 + int(ts_hash(pc) * 254.0);
		vec4 lut = texelFetch(field_lut, ivec2(fid, 0), 0);
		vec3 cc = lut.rgb * (0.92 + 0.16 * s.n1.r) * (0.94 + 0.12 * s.nm.g);
		col = mix(col, cc, lut.a);
	}
	vec3 n = normalize(wnrm);
	// sníh jako terrain.gdshader (bez prohlubní): stejné skvrny a jazyky po spádu → na hranici katastru bez švu
	float d1 = s.n0.r;
	float d2 = s.n1.r;
	float snow = 0.0;
	if (snow_cover > 0.005) {
		vec2 dhv = n.xz / max(length(n.xz), 0.02);
		vec2 tc = wpos.xz * 0.045;
		tc -= dhv * dot(tc, dhv) * 0.6;
		float dt = texture(detail_noise, tc + 13.7).r;
		float north_face = smoothstep(0.0, 0.7, dot(dhv, north_xz)) * (1.0 - n.y);
		snow = clamp((snow_cover * 1.35 + 0.14 * north_face - (1.0 - dt) * 0.40 - (1.0 - d2) * 0.20
			- (1.0 - d1) * 0.10) * 3.0, 0.0, 1.0) * smoothstep(0.55, 0.85, n.y);
	}
	if (c == 8) {
		snow *= step(0.6, snow_cover);    // voda zamrzá a zasněží až při souvislé pokrývce
	}
	float wet = wetness * (1.0 - snow);
	float porous = 1.0 - 0.45 * grassy;
	col *= 1.0 - (0.18 + 0.24 * porous) * wet;
	col = mix(col, vec3(0.88, 0.91, 0.96) * (0.92 + 0.08 * d1) * (0.96 + 0.04 * d2), snow);
	ALBEDO = col * 1.05;
	if (c == 8) {
		// voda: lehký lesk místo matného povrchu
		ROUGHNESS = mix(0.35, 0.75, snow);
		SPECULAR = 0.6;
	} else {
		ROUGHNESS = mix(mix(rough, 0.5, max(wet, own_wet)), 0.75, snow);
		SPECULAR = mix(0.25, 0.45, max(wet, own_wet));
	}
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
}
