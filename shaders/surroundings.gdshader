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

// roční období a počasí – sdílené globální parametry (nastavuje Atmosphere)
global uniform float snow_cover;
global uniform float wetness;
global uniform float grass_green;
#include "res://shaders/include/terrain_surface.gdshaderinc"

varying vec3 wpos;

// stejné natočení makro šumu jako terrain.gdshader (ROT_A)
const mat2 ROT_A = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8));
const mat2 ROT_F = mat2(vec2(0.94, 0.34), vec2(-0.34, 0.94));   // směr parcel polí v okolí

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
	// levná normála z výškové mřížky (diference sousedních buněk)
	ivec2 hc = ivec2(clamp((wpos.xz - grid_origin) / spacing, vec2(0.0), grid_size - 1.0) + 0.5);
	float hx = texelFetch(height_tex, ivec2(min(hc.x + 1, int(grid_size.x) - 1), hc.y), 0).r
		- texelFetch(height_tex, ivec2(max(hc.x - 1, 0), hc.y), 0).r;
	float hz = texelFetch(height_tex, ivec2(hc.x, min(hc.y + 1, int(grid_size.y) - 1)), 0).r
		- texelFetch(height_tex, ivec2(hc.x, max(hc.y - 1, 0)), 0).r;
	vec3 n = normalize(vec3(-hx / (2.0 * spacing), 1.0, -hz / (2.0 * spacing)));
	// sníh na rovinách, mokro tmaví (jako terén: hlína víc než tráva)
	float d1 = s.n0.r;
	float d2 = s.n1.r;
	float snow = clamp((snow_cover * 1.35 - (1.0 - d2) * 0.35 - (1.0 - d1) * 0.12) * 1.6, 0.0, 1.0) * smoothstep(0.55, 0.85, n.y);
	if (c == 8) {
		snow *= step(0.6, snow_cover);    // voda zamrzá a zasněží až při souvislé pokrývce
	}
	float wet = wetness * (1.0 - snow);
	float porous = 1.0 - 0.45 * grassy;
	col *= 1.0 - (0.18 + 0.24 * porous) * wet;
	col = mix(col, vec3(0.88, 0.91, 0.96) * (0.96 + 0.04 * d2), snow);
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
