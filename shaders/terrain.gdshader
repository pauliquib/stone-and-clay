// Terén: výšky z DMR 5G (2 m) přímo z textury ve vertex shaderu (stejná data jako kolize),
// normály z předpočítané normálové mapy (osvětlení nezávislé na LOD). Barva: ve výchozím stavu procedurální materiály
// podle tříd povrchu (data/surface.bin, fallback landuse + hustota lesa + sklon); ortofoto ČÚZK jen po přepnutí use_ortho.
// Povrch tříd se generuje v shaderu (shaders/include/terrain_surface.gdshaderinc) z jednoho RGBA šumu ve více měřítkách:
// stébla, hroudy, štěrk, listí, mech, makro skvrny vlhkosti na stovky metrů; drobný reliéf z téže procedury dává normálu
// (derivace v obrazovce, bez dalších vzorků). Dlaždicové textury z AssetLib (jsou-li) se míchají bez opakování 4,5 m.
// LOD dlaždic: geomorfing – vrcholy jemnější LOD se před přepnutím plynule stáhnou na tvar hrubší LOD (bez „skoku“).
// Kvalita (`gfx_quality`): Nízká/Střední = 4 vzorky šumu + 1 jemný zblízka (méně než dřív); Vysoká+ jemnější oktávy,
// hex-tiling textur, delší dosah detailní normály a třpyt sněhu.
shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D height_tex : filter_nearest, repeat_disable;
uniform sampler2D normal_tex : filter_linear_mipmap, repeat_disable;
uniform sampler2D ortho_full : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D ortho_core : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D detail_noise : filter_linear_mipmap, repeat_enable;   // RGBA šum (Terrain.detail_noise_texture)
uniform vec2 grid_origin;
uniform float spacing = 2.0;
uniform vec2 grid_size;
uniform vec4 full_rect;   // x0, z0, size_x, size_z
uniform vec4 core_rect;
uniform float skirt_depth = 4.0;
// geomorfing LOD: UV sítě = (krok další LOD v buňkách, konec dosahu této LOD v m); lod_cam = hlavní kamera
// (stejná i ve stínovém průchodu – viditelnost LOD se počítá od ní), y < -50000 = vypnuto
uniform vec3 lod_cam = vec3(0.0, -100000.0, 0.0);
uniform float chunk_size = 256.0;
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
uniform int tex_mask = 0;          // bity načtených textur: 1 tráva, 2 ornice, 4 les, 8 dvůr, 16 bahno, 32 skála (chybí = procedurální povrch)
uniform float tex_scale = 4.0;     // velikost dlaždice textury v metrech
// roční období a počasí (globální parametry – nastavuje Atmosphere, výchozí hodnoty v project.godot)
global uniform float gfx_quality;  // 0 Nízká, 1 Střední, 2 Vysoká, 3 Ultra (GameSettings)
global uniform float snow_cover;   // sníh na zemi 0..1
global uniform float wetness;      // mokrý povrch 0..1
global uniform float grass_green;  // svěžest trávy 0..1 (zima / sucho → hnědá)
global uniform float micro_dew;    // M8.9: rosa na trávě 0..1 (Microclimate → MicroFx)
global uniform float micro_frost;  // M8.9: 1 = rosa na dně údolí je zmrzlá (jinovatka)
global uniform float micro_frost_y; // M8.9: svět Y, pod kterým je zem zmrzlá
#include "res://shaders/include/ground_veg.gdshaderinc"   // M8.14: pěšiny (path_tex) – prošlapaná hlína
#include "res://shaders/include/terrain_surface.gdshaderinc"   // procedurální povrch tříd (sdílí surroundings)
// M8.13: koleje a stopy v blátě (RutMap) – hloubka v m, okno 3 × 3 dlaždic kolem hráče jako kruhový buffer
// (uv = fract(svět / šířka okna), proto repeat_enable); rut_rect.z = 0 → vypnuto
uniform sampler2D rut_tex : filter_linear, repeat_enable;
uniform vec4 rut_rect = vec4(0.0);    // x0, z0, šířka, výška platného okna (m)
uniform float rut_dark = 0.55;        // ztmavení v koleji
uniform float rut_normal = 0.6;       // posun normál (svahy koleje)
uniform float rut_puddle = 1.0;       // louže v hlubších kolejích za mokra
uniform float rut_vis = 120.0;        // do jaké vzdálenosti od kamery (m)
uniform vec2 north_xz = vec2(-0.98, -0.20);   // světový směr severu (z map.json north_angle; pro sněhové jazyky)

varying vec3 wpos;

// natočení vzorkování šumu – měřítka se tak neskládají do pravidelné mřížky (z dronu není vidět opakování)
const mat2 ROT_A = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8));
const mat2 ROT_B = mat2(vec2(0.28, -0.96), vec2(0.96, 0.28));
const mat2 ROT_C = mat2(vec2(-0.5, 0.866), vec2(-0.866, -0.5));

// dlaždicová textura bez viditelného opakování: Nízká/Střední 1 vzorek s pomalu se měnícím posunem (`slow`, dlaždice),
// Vysoká+ hex-tiling – 3 vzorky s náhodným posunem a natočením v trojúhelníkové mřížce, prolnuté podle vah
vec3 tex_tiled(sampler2D t, vec2 uv, vec2 gx, vec2 gy, vec2 slow, bool hq) {
	if (!hq) {
		return textureGrad(t, uv + slow, gx, gy).rgb;
	}
	const mat2 SK = mat2(vec2(1.0, 0.0), vec2(-0.57735027, 1.15470054));
	vec2 sk = SK * (uv * 1.6);
	vec2 base = floor(sk);
	vec3 tmp = vec3(fract(sk), 0.0);
	tmp.z = 1.0 - tmp.x - tmp.y;
	float s = step(0.0, -tmp.z);
	float s2 = 2.0 * s - 1.0;
	vec3 w = vec3(-tmp.z * s2, s - tmp.y * s2, s - tmp.x * s2);
	vec2 vtx[3] = vec2[3](base + vec2(s, s), base + vec2(s, 1.0 - s), base + vec2(1.0 - s, s));
	w = w * w * w;
	w /= max(w.x + w.y + w.z, 1e-5);
	float wv[3] = float[3](w.x, w.y, w.z);
	vec3 acc = vec3(0.0);
	for (int i = 0; i < 3; i++) {
		float a = ts_hash(vtx[i]) * 6.2832;
		mat2 r = mat2(vec2(cos(a), sin(a)), vec2(-sin(a), cos(a)));
		vec2 off = vec2(ts_hash(vtx[i] + 7.13), ts_hash(vtx[i] + 3.71));
		acc += textureGrad(t, r * uv + off, r * gx, r * gy).rgb * wv[i];
	}
	return acc;
}

// albedo třídy: procedurální povrch, případně dlaždicová textura z AssetLib (texw 0..1 = kolik textury)
vec3 class_albedo(int c, TsSig s, vec2 p, vec2 pdx, vec2 pdy, float texw, bool hq,
		out float hgt, out float rough, out float own_wet, out float grassy) {
	vec3 col = ts_class(c, s, grass_green, hgt, rough, own_wet, grassy);
	if (texw > 0.0 && tex_mask != 0) {
		vec2 uv = p / tex_scale;
		vec2 gx = pdx / tex_scale;   // derivace se počítají mimo větvení (textureGrad), jinak by na hranicích tříd vznikaly artefakty mip-map
		vec2 gy = pdy / tex_scale;
		vec2 slow = (s.n2.gr - 0.5) * 4.0;   // posun o několik dlaždic měnící se na ~20 m – opakování se rozpadne
		vec3 t = vec3(-1.0);
		if ((c == 0 || c == 2) && (tex_mask & 1) != 0) t = tex_tiled(tex_grass, uv, gx, gy, slow, hq) * (c == 2 ? vec3(1.04, 1.08, 0.94) : vec3(1.0));
		else if (c == 1 && (tex_mask & 2) != 0) t = tex_tiled(tex_soil, uv, gx, gy, slow, hq);
		else if (c == 3 && (tex_mask & 4) != 0) t = tex_tiled(tex_forest, uv, gx, gy, slow, hq);
		else if ((c == 4 || c == 7) && (tex_mask & 8) != 0) t = tex_tiled(tex_yard, uv, gx, gy, slow, hq) * (c == 7 ? vec3(1.0, 0.96, 0.9) : vec3(1.0));
		else if (c == 5 && (tex_mask & 16) != 0) t = tex_tiled(tex_mud, uv, gx, gy, slow, hq);
		else if (c == 6 && (tex_mask & 32) != 0) t = tex_tiled(tex_rock, uv, gx, gy, slow, hq);
		if (t.r >= 0.0) {
			// textura nese barvu, procedura jen drobnou variaci (ať se dlaždice neopakují ani jasem)
			col = mix(col, t * (0.88 + 0.24 * s.n0.r), texw);
		}
	}
	return ts_macro(col, s, grassy, c == 3, grass_green);
}

// třída povrchu blokující pole (les, dvůr, břeh, cesta)
float blocks_field(int c) {
	return (c == 3 || c == 4 || c == 5 || c == 7) ? 1.0 : 0.0;
}

// --- polní cesta (třída 7): směr a postranní poloha se odhadnou z masky třídy (rastr 4 m).
// Míra "cestovitosti" bodu – 1 pro texel třídy 7, 0 pro ostatní (nearest sampling).
float trackness(vec2 p) {
	if (surface_rect.z <= 0.0) return 0.0;
	vec2 uv = (p - surface_rect.xy) / surface_rect.zw;
	if (uv.x <= 0.0 || uv.y <= 0.0 || uv.x >= 1.0 || uv.y >= 1.0) return 0.0;
	float v = textureLod(surface_tex, uv, 0.0).r * 255.0;
	return clamp(1.0 - abs(v - 7.0), 0.0, 1.0);
}

// Koleje cesty ~0,9 m rozchod. Gradient trackness míří ke středu cesty (napříč), takže
// symetrie vzorků vlevo/vpravo podél něj dává příčnou polohu phi ≈ vzdálenost od osy
// (0 uprostřed, ±1 u kraje). Vrací (kolej, mezikolejní pás) × jistota odhadu.
vec2 track_detail(vec2 p, float jit) {
	float gx = trackness(p + vec2(3.0, 0.0)) - trackness(p - vec2(3.0, 0.0));
	float gz = trackness(p + vec2(0.0, 3.0)) - trackness(p - vec2(0.0, 3.0));
	float gl = length(vec2(gx, gz));
	if (gl < 0.03) return vec2(0.0);                 // uprostřed širokého úseku nebo mimo → bez kolejí
	vec2 side = vec2(gx, gz) / gl;
	float sp = trackness(p + side * 1.3);
	float sm = trackness(p - side * 1.3);
	float den = sp + sm;
	if (den < 0.05) return vec2(0.0);
	float phi = clamp((sp - sm) / den * 1.15 + jit, -1.0, 1.0);   // příčná poloha, ~0,3 ≈ ±0,45 m od osy
	float rut = smoothstep(0.16, 0.05, abs(abs(phi) - 0.30));     // dvě vyjeté koleje
	float mid = smoothstep(0.18, 0.05, abs(phi));                 // mezikolejní pás (zarůstá trávou)
	float conf = clamp(gl * 2.5, 0.0, 1.0) * clamp(den, 0.0, 1.0) * trackness(p);
	return vec2(rut, mid) * conf;
}

// Pole podle plodiny (LUT) – realističtěji: řádky setí 12,5 cm, kolejové řádky po 18 m, na zralém / strništi pruhy
// po kombajnu, orba = brázdy ~0,36 m s hroudami a pruhy záběrů pluhu. Všechny pruhy se antialiasují podle `fwa`
// (m na pixel napříč řádky) – zdálky splynou do průměru místo moaré. `hgt` += reliéf pro normálu.
vec3 field_color(int lid, vec4 lut, vec4 fur, TsSig s, vec2 p, vec2 fw, vec3 soil_proc, inout float hgt) {
	bool dirx = fur.g > 0.5;
	float across = dirx ? p.x : p.y;
	float fwa = max(dirx ? fw.x : fw.y, 1e-4);
	float ph = fract(float(lid) * 0.618034);
	vec3 cc = lut.rgb * (0.88 + 0.24 * s.n0.r) * (0.92 + 0.16 * s.n1.r) * (0.94 + 0.12 * s.nm.g);
	float green = clamp((lut.g - max(lut.r, lut.b)) * 8.0, 0.0, 1.0);    // roste (zelená plodina)
	float bare = clamp(fur.r * 1.3, 0.0, 1.0);                            // zoráno / podmítnuto (jako vegetation.gdshader)
	float grow = 1.0 - bare;
	vec3 soilc = ts_s2l(vec3(0.36, 0.28, 0.20)) * (0.85 + 0.3 * s.n0.r);
	// řádky setí (12,5 cm) – mezi řádky stín a hlína
	float raa = clamp(1.0 - fwa / 0.125 * 1.6, 0.0, 1.0);
	float row = (0.5 + 0.5 * cos(6.2832 * across / 0.125)) * raa;
	cc = mix(cc, mix(soilc, cc * 0.7, 0.5), row * grow * 0.3 * green);
	// porost: stín mezi rostlinami – o něco tmavší a méně sytý než samotná barva plodiny
	cc = mix(cc, vec3(dot(cc, vec3(0.3, 0.5, 0.2))), 0.15 * grow) * mix(1.0, 0.9, grow);
	// kolejové řádky (dvě stopy 1,8 m od sebe, 0,45 m široké, po 18 m) – zdálky průměrné pokrytí
	float tq = abs(fract(across / 18.0 + ph) - 0.5) * 18.0;
	float aw = max(fwa * 0.7, 0.01);
	float lane = 1.0 - smoothstep(0.22 - aw, 0.22 + aw, abs(tq - 0.9));
	lane = mix(lane, 0.05, smoothstep(0.2, 0.6, fwa));
	cc = mix(cc, mix(soilc, cc * 0.75, 0.35 + 0.4 * (1.0 - green)), lane * grow * 0.8);
	// zralé obilí / strniště: pruhy po záběrech kombajnu (~6 m) a hlína mezi stébly
	float ripe = (1.0 - green) * grow * smoothstep(0.08, 0.2, dot(lut.rgb, vec3(0.3, 0.5, 0.2)));
	float swq = abs(fract(across / 6.1 + ph * 3.0) - 0.5);
	float swath = (1.0 - smoothstep(0.17, 0.25, swq)) * clamp(1.0 - fwa / 6.1 * 3.0, 0.0, 1.0);
	cc *= 1.0 + ripe * (swath - 0.25) * 0.12;
	cc = mix(cc, soilc, ripe * smoothstep(0.6, 0.85, s.nf.r) * 0.25);
	// orba: procedurální hlína (hroudy, kamínky) v odstínu plodiny z LUT, brázdy ~0,36 m (nepravidelné – fáze
	// i hloubka se mění šumem), pruhy záběrů pluhu (1,4 m)
	float llum = dot(lut.rgb, vec3(0.3, 0.5, 0.2));
	vec3 tilled = soil_proc * (llum / 0.068) * 0.95;                   // 0,068 = průměrný jas ts_soil
	cc = mix(cc, tilled, 0.65 * bare);
	float faa = clamp(1.0 - fwa / 0.36 * 1.5, 0.0, 1.0);
	float furw = 0.5 + 0.5 * sin(6.2832 * across / 0.36 + (s.n0.r - 0.5) * 2.5 + (s.n1.g - 0.5) * 6.0);
	furw = mix(furw, 0.5, smoothstep(0.55, 0.8, s.n1.r) * 0.6);      // místy uválcováno / rozvláčeno
	float clod = 1.0 - smoothstep(0.05, 0.75, s.n0.b);
	cc *= 1.0 - bare * (0.17 * (1.0 - furw) * faa + 0.08 * (1.0 - clod));
	cc *= 1.0 + bare * 0.07 * sin(6.2832 * across / 1.4 + ph * 6.0) * clamp(1.0 - fwa / 1.4 * 1.5, 0.0, 1.0);
	hgt += bare * (furw * 0.035 * faa + clod * 0.02) + grow * row * 0.008 - lane * grow * 0.02;
	return cc;
}

// normála z výšky reliéfu (m) přes derivace v obrazovce (Mikkelsen, surface gradient) – bez dalších vzorků textur
vec3 bump_normal(vec3 nrm, vec3 dpdx, vec3 dpdy, float dhx, float dhy) {
	vec3 r1 = cross(dpdy, nrm);
	vec3 r2 = cross(nrm, dpdx);
	float det = dot(dpdx, r1);
	vec3 grad = sign(det) * (dhx * r1 + dhy * r2);
	return normalize(abs(det) * nrm - grad + nrm * 1e-8);
}

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX.x, 0.0, VERTEX.z, 1.0)).xyz;
	ivec2 gmax = ivec2(grid_size) - 1;
	ivec2 cell = clamp(ivec2(round((w.xz - grid_origin) / spacing)), ivec2(0), gmax);
	float h = texelFetch(height_tex, cell, 0).r;
	// geomorfing: blíží-li se dlaždice konci dosahu své LOD (vzdálenost středu AABB jako u visibility_range),
	// vrcholy mezi uzly hrubší sítě se plynule stáhnou na její trojúhelníky → přepnutí LOD je beze skoku.
	// U kamery (do ~6–30 m) se nemorfuje: země pod nohama zůstává přesně jako kolize (height_at).
	if (UV.x > 0.5 && lod_cam.y > -50000.0) {
		vec3 cc = (MODEL_MATRIX * vec4(chunk_size * 0.5, 0.0, chunk_size * 0.5, 1.0)).xyz;
		cc.y = texelFetch(height_tex, clamp(ivec2((cc.xz - grid_origin) / spacing), ivec2(0), gmax), 0).r;
		float morph = smoothstep(UV.y * 0.72, UV.y * 0.97, distance(lod_cam, cc))
			* smoothstep(6.0, 30.0, distance(lod_cam.xz, w.xz));
		if (morph > 0.001) {
			int k = int(UV.x + 0.5);
			ivec2 a = (cell / k) * k;
			vec2 f = vec2(cell - a) / float(k);
			if (f.x + f.y > 0.0) {
				float ha = texelFetch(height_tex, a, 0).r;
				float hb = texelFetch(height_tex, min(a + ivec2(k, 0), gmax), 0).r;
				float hc = texelFetch(height_tex, min(a + ivec2(0, k), gmax), 0).r;
				float hd = texelFetch(height_tex, min(a + ivec2(k, k), gmax), 0).r;
				// stejné dělení čtverce jako Terrain._grid_mesh (a, b, c) + (b, d, c) – úhlopříčka b–c
				float hm = (f.x + f.y <= 1.0) ? ha + (hb - ha) * f.x + (hc - ha) * f.y
					: hd + (hc - hd) * (1.0 - f.x) + (hb - hd) * (1.0 - f.y);
				h = mix(h, hm, morph);
			}
		}
	}
	float skirt = VERTEX.y < -0.5 ? skirt_depth : 0.0;
	VERTEX.y = h - skirt;
	wpos = vec3(w.x, VERTEX.y, w.z);
}

void fragment() {
	bool hq = gfx_quality > 1.5;
	vec2 nuv = ((wpos.xz - grid_origin) / spacing + 0.5) / grid_size;
	vec3 n = normalize(texture(normal_tex, nuv).rgb * 2.0 - 1.0);
	float dist = length(VERTEX);
	vec2 pdx = dFdx(wpos.xz);
	vec2 pdy = dFdy(wpos.xz);
	vec3 wdx = dFdx(wpos);
	vec3 wdy = dFdy(wpos);
	vec2 fw = abs(pdx) + abs(pdy);
	// --- šum (jeden RGBA vzorek = 4 hodnoty): 4 měřítka + jemné zblízka; průměr šumu = nejmenší mip
	TsSig s;
	s.n0 = texture(detail_noise, wpos.xz * 0.23);
	s.n1 = texture(detail_noise, wpos.xz * 0.031 + vec2(0.5, 0.13));
	s.n2 = texture(detail_noise, wpos.xz * 0.006 + 0.21);
	s.nm = texture(detail_noise, ROT_A * wpos.xz * 0.0007 + vec2(0.37, 0.61));
	vec4 nmean = textureLod(detail_noise, vec2(0.5), 12.0);
	s.nf = nmean;
	float f_end = hq ? 110.0 : 70.0;
	float ffade = 1.0 - smoothstep(f_end * 0.5, f_end, dist);
	if (ffade > 0.0) {
		vec2 pf = ROT_B * wpos.xz * 1.9;
		vec4 nf = textureGrad(detail_noise, pf, ROT_B * pdx * 1.9, ROT_B * pdy * 1.9);
		if (hq && dist < 30.0) {
			// Vysoká+: druhá jemná oktáva (zrnka, špičky stébel ~5 mm)
			vec2 pf2 = ROT_C * wpos.xz * 5.3 + 0.7;
			vec4 nf2 = textureGrad(detail_noise, pf2, ROT_C * pdx * 5.3, ROT_C * pdy * 5.3);
			nf.rg = mix(nf.rg, nf2.rg, 0.35 * (1.0 - smoothstep(15.0, 30.0, dist)));
		}
		s.nf = mix(nmean, nf, ffade);
	}
	if (hq) {
		// Vysoká+: střední oktáva ~1 m (natočená) – rozbije periodu n0 a přidá variaci trsů
		vec4 nb = texture(detail_noise, ROT_C * wpos.xz * 0.093 + 0.3);
		s.n0.rg = mix(s.n0.rg, nb.rg, 0.3);
	}
	float d1 = s.n0.r;
	float d2 = s.n1.r;
	float dfade = 1.0 - smoothstep(30.0, 140.0, dist);
	// mapa využití ploch (pole, louky): hranice buněk 4 m se rozbíjí šumem (týž posun jako hranice tříd)
	vec2 warp = (s.n1.gr - 0.5) * 9.0;
	int lcls = 0;
	int lid = 0;
	if (landuse_rect.z > 0.0) {
		// 4 sousední buňky, hranice = vrstevnice bilineární váhy (ne schody rastru 4 m)
		ivec2 lsz = textureSize(landuse_tex, 0);
		vec2 lg = (wpos.xz + warp - landuse_rect.xy) / landuse_rect.zw * vec2(lsz) - 0.5;
		if (lg.x > 0.0 && lg.y > 0.0 && lg.x < float(lsz.x - 1) && lg.y < float(lsz.y - 1)) {
			ivec2 l0 = ivec2(floor(lg));
			vec2 lf = fract(lg);
			ivec2 lv[4];
			float lw[4];
			for (int k = 0; k < 4; k++) {
				vec2 lu = texelFetch(landuse_tex, l0 + ivec2(k & 1, k >> 1), 0).rg * 255.0;
				lv[k] = ivec2(lu + 0.5);
			}
			lw[0] = (1.0 - lf.x) * (1.0 - lf.y);
			lw[1] = lf.x * (1.0 - lf.y);
			lw[2] = (1.0 - lf.x) * lf.y;
			lw[3] = lf.x * lf.y;
			int la = 0;
			for (int k = 1; k < 4; k++) {
				if (lw[k] > lw[la]) la = k;
			}
			float lsame = 0.0;
			float lbw = -1.0;
			int lb = la;
			for (int k = 0; k < 4; k++) {
				if (lv[k] == lv[la]) {
					lsame += lw[k];
				} else if (lw[k] > lbw) {
					lbw = lw[k];
					lb = k;
				}
			}
			int lsel = (lsame + (s.n0.r - 0.5) * 0.25 >= 0.5) ? la : lb;
			lcls = lv[lsel].x;
			lid = lv[lsel].y;
		}
	}
	vec3 col;
	float greenish = 0.0;           // podíl zelené plochy (sezónní hnědnutí, květy na loukách)
	float field_keep = 1.0;   // kolik z pole se smí projevit (les, dvůr, břeh a cesta ho zakrývají)
	float rut = 0.0;          // vyjetá kolej polní cesty 0..1 (v mokru v ní drží voda)
	float hgt = 0.0;          // drobný reliéf povrchu (m) → normála
	float rough = 0.92;
	float own_wet = 0.0;      // vlastní vlhkost povrchu (bahno na břehu)
	float porous = 1.0;       // jak moc povrch za mokra tmavne (hlína víc než tráva)
	float puddle_ok = 0.0;    // kde se za deště drží voda v prohlubních (cesty, dvory, holá pole)
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
		hgt = (s.nf.r - 0.5) * 0.015 + (d1 - 0.5) * 0.03;
	} else {
		// --- třída povrchu: dvě nejbližší třídy a jejich poměr (hranice rozbité šumem)
		vec2 wp = wpos.xz + warp * 0.85;
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
				float fd = textureLod(forest_tex, clamp(fuv2, vec2(0.0), vec2(1.0)), 0.0).r;
				cb = 3;
				tb = smoothstep(0.3, 0.7, fd + (d1 - 0.5) * 0.3);
			}
		}
		// --- barva tříd (textury z AssetLib jen do ~1 km, dál procedura = průměr textury)
		float texw = 1.0 - smoothstep(700.0, 1100.0, dist);
		float ga;
		float ha;
		float ra;
		float wa2;
		vec3 colA = class_albedo(ca, s, wpos.xz, pdx, pdy, texw, hq, ha, ra, wa2, ga);
		col = colA;
		greenish = ga;
		hgt = ha;
		rough = ra;
		own_wet = wa2;
		if (tb > 0.001 && cb != ca) {
			float gb;
			float hb;
			float rb;
			float wb2;
			vec3 colB = class_albedo(cb, s, wpos.xz, pdx, pdy, texw, hq, hb, rb, wb2, gb);
			col = mix(colA, colB, tb);
			greenish = mix(ga, gb, tb);
			hgt = mix(ha, hb, tb);
			rough = mix(ra, rb, tb);
			own_wet = mix(wa2, wb2, tb);
		}
		field_keep = 1.0 - mix(blocks_field(ca), blocks_field(cb), tb);
		puddle_ok = mix((ca == 4 || ca == 7) ? 1.0 : 0.0, (cb == 4 || cb == 7) ? 1.0 : 0.0, tb);
		// --- svah: nad ~20° méně trávy (hlína), nad ~35° skála
		float slope_soil = (1.0 - smoothstep(0.90, 0.95, n.y)) * greenish;
		if (slope_soil > 0.0) {
			float h0;
			vec3 soil = ts_macro(ts_soil(s, h0), s, 0.0, false, grass_green);
			col = mix(col, soil, slope_soil * 0.6);
			hgt = mix(hgt, h0, slope_soil * 0.6);
			greenish *= 1.0 - slope_soil * 0.6;
		}
		float rockw = 1.0 - smoothstep(0.78, 0.86, n.y);
		if (rockw > 0.0) {
			float hr;
			vec3 rock = ts_macro(ts_rock(s, hr), s, 0.0, false, grass_green);
			if (texw > 0.0 && (tex_mask & 32) != 0) {
				vec3 bl = pow(abs(n), vec3(4.0));
				bl /= bl.x + bl.y + bl.z;
				vec3 rp = wpos / (tex_scale * 1.5);
				vec3 rdx = wdx / (tex_scale * 1.5);
				vec3 rdy = wdy / (tex_scale * 1.5);
				vec3 rt = textureGrad(tex_rock, rp.zy, rdx.zy, rdy.zy).rgb * bl.x + textureGrad(tex_rock, rp.xz, rdx.xz, rdy.xz).rgb * bl.y + textureGrad(tex_rock, rp.xy, rdx.xy, rdy.xy).rgb * bl.z;
				rock = mix(rock, rt, texw);
			}
			rock = mix(rock, ts_soil(s, hr) * (0.8 + 0.4 * d1), step(d2, 0.42) * 0.5);   // místy holá hlína
			col = mix(col, rock, rockw);
			hgt = mix(hgt, hr, rockw);
			rough = mix(rough, 0.82, rockw);
			greenish *= 1.0 - rockw;
			field_keep *= 1.0 - rockw;
		}
		// --- polní cesta (třída 7): písek s dvěma vyjetými kolejemi ~0,9 m rozchod (§12.2);
		// směr a příčná poloha se odhadnou z gradientu masky třídy, detail jen zblízka
		float trackw = (ca == 7 ? 1.0 - tb : 0.0) + (cb == 7 ? tb : 0.0);
		float rutf = (1.0 - smoothstep(25.0, 90.0, dist));
		if (trackw > 0.02 && rutf > 0.01) {
			vec2 td = track_detail(wpos.xz, (d1 - 0.5) * 0.14);
			rut = td.x * trackw * rutf;
			col = mix(col, col * vec3(0.64, 0.58, 0.50), rut * 0.85);                 // uježděná hlína tmavší
			col = mix(col, col * vec3(0.80, 1.05, 0.70), td.y * trackw * rutf * 0.5 * grass_green);  // mezikolejní pás
			hgt += td.y * trackw * rutf * 0.03 - rut * 0.04;
		}
	}
	// pole podle plodiny a data (před sněhem a mokrem)
	if (lcls == 1) {
		vec4 lut = texelFetch(field_lut, ivec2(lid, 0), 0);
		vec4 fur = texelFetch(field_lut, ivec2(lid, 1), 0);
		float fk = lut.a * field_keep;
		float fh = 0.0;
		float hs;
		vec3 cc = field_color(lid, lut, fur, s, wpos.xz, fw, ts_soil(s, hs), fh);
		col = mix(col, cc, fk);
		hgt = mix(hgt, fh, fk);
		rough = mix(rough, 0.93, fk);
		puddle_ok = mix(puddle_ok, clamp(fur.r * 1.3, 0.0, 1.0) * 0.6, fk);   // holá oranice drží louže v brázdách
	} else if (lcls >= 2) {
		// louky, sady a zahrádky: v době květu drobné bílé, žluté a fialové kvítky (buňky jemného šumu);
		// zdálky jen průměrné pokrytí (jemný šum se dál nečte)
		float cellf = smoothstep(0.32, 0.18, s.nf.b) * step(0.62, s.nf.a);
		float spots = mix(0.07, cellf, ffade) * meadow_bloom * greenish * smoothstep(0.35, 0.6, s.n1.g + 0.15);
		vec3 fc = mix(vec3(0.85, 0.8, 0.62), vec3(0.9, 0.7, 0.1), step(0.5, d1));
		fc = mix(fc, vec3(0.5, 0.25, 0.6), step(0.75, s.n0.a));
		col = mix(col, fc, spots * 0.7);
	}
	porous = 1.0 - 0.45 * greenish;
	// sníh: na rovině víc, na strmých svazích méně, okraje rozbité šumem.
	// Sněhové jazyky (§12.3): při couvající pokrývce sníh déle drží v prohlubních
	// (vlastní výška pod okolím ±6 m) a na severních svazích (normála odvrácená od
	// poledního slunce); okraj se trhá do jazýčků – šum protáhnutý po směru spádu.
	float hold = 0.0;
	float snow = 0.0;
	if (snow_cover > 0.005) {
		// buňka okolí s chvěním ±1 m – hranice prohlubní nejsou čtverce mřížky 2 m
		ivec2 hc = ivec2(clamp((wpos.xz + (s.n0.gr - 0.5) * 4.0 - grid_origin) / spacing, vec2(0.0), grid_size - 1.0));
		ivec2 hlo = max(hc - 3, ivec2(0));
		ivec2 hhi = min(hc + 3, ivec2(grid_size) - 1);
		float hav = (texelFetch(height_tex, ivec2(hlo.x, hc.y), 0).r + texelFetch(height_tex, ivec2(hhi.x, hc.y), 0).r
			+ texelFetch(height_tex, ivec2(hc.x, hlo.y), 0).r + texelFetch(height_tex, ivec2(hc.x, hhi.y), 0).r) * 0.25;
		float dep = clamp((hav - wpos.y) * 0.8, 0.0, 1.0);              // prohlubeň
		vec2 dhv = n.xz / max(length(n.xz), 0.02);                       // směr spádu (protažení jazyků)
		vec2 tc = wpos.xz * 0.045;
		tc -= dhv * dot(tc, dhv) * 0.6;
		float dt = texture(detail_noise, tc + 13.7).r;                  // jazýčkový šum po svahu
		float north_face = smoothstep(0.0, 0.7, dot(dhv, north_xz)) * (1.0 - n.y);   // severní svah
		hold = 0.30 * dep + 0.14 * north_face;
		snow = clamp((snow_cover * 1.35 + hold - (1.0 - dt) * 0.40 - (1.0 - d2) * 0.20
			- (1.0 - d1) * 0.10) * 3.0, 0.0, 1.0) * smoothstep(0.55, 0.85, n.y);   // ostřejší okraje skvrn
		// tenká pokrývka: na okraji prosvítají špičky trávy a hroudy (vyšší reliéf = dřív bez sněhu)
		snow = clamp(snow - (hgt * 12.0 + (s.nf.r - 0.5) * 0.5) * snow * (1.0 - snow) * 2.0, 0.0, 1.0);
	}
	// M8.13: vyjeté koleje a stopy v blátě – tmavá mokrá hlína, svahy koleje v normále, v hlubších louže
	float rdep = 0.0;
	float rpud = 0.0;
	if (rut_rect.z > 0.0 && dist < rut_vis) {
		vec2 rl = wpos.xz - rut_rect.xy;
		if (rl.x > 0.0 && rl.y > 0.0 && rl.x < rut_rect.z && rl.y < rut_rect.w) {
			vec2 ruv = wpos.xz / rut_rect.z;
			float px = 0.25 / rut_rect.z;          // 1 px okna (0,25 m)
			rdep = textureLod(rut_tex, ruv, 0.0).r;
			if (rdep > 0.002) {
				float rx = textureLod(rut_tex, ruv + vec2(px, 0.0), 0.0).r - textureLod(rut_tex, ruv - vec2(px, 0.0), 0.0).r;
				float rz = textureLod(rut_tex, ruv + vec2(0.0, px), 0.0).r - textureLod(rut_tex, ruv - vec2(0.0, px), 0.0).r;
				float rfade = 1.0 - smoothstep(rut_vis * 0.7, rut_vis, dist);
				n = normalize(n + vec3(rx, 0.0, rz) / 0.5 * rut_normal * 4.0 * rfade);
				float rd = smoothstep(0.004, 0.05, rdep) * rfade * (1.0 - snow * 0.8);
				vec3 mudc = vec3(0.23, 0.17, 0.11) * (0.85 + 0.3 * d1);
				col = mix(col, mudc, rd * rut_dark);
				rut = max(rut, rd);
				rpud = smoothstep(0.04, 0.12, rdep) * smoothstep(0.35, 0.8, wetness) * rut_puddle * rfade * (1.0 - snow);
			}
		}
	}
	// M8.14: pěšina z opakované chůze – prošlapaná hlína (na trávě a v lese), okraj rozbitý šumem
	if (path_size > 0.0 && dist < 160.0) {
		float pw = gv_path_wear(wpos.xz);
		if (pw > 0.01) {
			float pd = smoothstep(0.12, 0.7, pw + (d2 - 0.5) * 0.25) * (1.0 - smoothstep(110.0, 160.0, dist))
				* (1.0 - snow * 0.85) * (lcls == 1 ? 0.0 : 1.0);
			col = mix(col, vec3(0.36, 0.29, 0.20) * (0.85 + 0.3 * d1), pd * 0.8);
			hgt = mix(hgt, (s.nf.r - 0.5) * 0.006, pd);
			porous = mix(porous, 1.0, pd);
			puddle_ok = max(puddle_ok, pd * 0.7);
		}
	}
	// mokro: tmavší (hlína víc než tráva) a lesklejší povrch; v kolejích polních cest drží voda déle;
	// za deště voda v drobných prohlubních cest, dvorů a oranice (nízký reliéf + šum ~3 m)
	float wet = min(wetness * (1.0 + rut * 0.6), 1.0) * (1.0 - snow);
	float wpatch = puddle_ok * smoothstep(0.45, 0.85, wetness) * smoothstep(0.58, 0.68, 1.0 - s.n1.g + (0.5 - s.n0.r) * 0.25)
		* (1.0 - snow);
	// M8.9: jinovatka pod mrazovou hranicí (rovina, rozbitá šumem), rosa nad ní – lesk jako mokro, slabší
	float rime = micro_dew * micro_frost * smoothstep(micro_frost_y + 8.0, micro_frost_y - 8.0, wpos.y)
		* (1.0 - snow) * smoothstep(0.6, 0.9, n.y);
	wet = max(wet, max(micro_dew - rime, 0.0) * (1.0 - snow) * 0.6);
	float wet_all = max(wet, own_wet * 0.6 * (1.0 - snow));   // bahno břehu: vlhký lesk, ne zrcadlo
	col *= 1.0 - (0.18 + 0.24 * porous) * wet;
	col *= 1.0 - 0.12 * own_wet * (1.0 - wet);       // bahno břehu i za sucha tmavší
	// sníh: lehce modravý, jemné závěje; Vysoká+: třpyt (drobné lesklé body)
	vec3 snowc = vec3(0.88, 0.91, 0.96) * (0.92 + 0.08 * d1) * (0.96 + 0.04 * s.n1.r);
	col = mix(col, snowc, snow);
	col = mix(col, vec3(0.80, 0.84, 0.88) * (0.9 + 0.1 * d1), rime * (0.35 + 0.35 * d2));   // M8.9 jinovatka
	col = mix(col, col * 0.55 + vec3(0.02, 0.025, 0.03), rpud);     // M8.13: voda v koleji
	col = mix(col, col * 0.62 + vec3(0.015, 0.02, 0.025), wpatch);  // voda v prohlubních
	ALBEDO = col * 1.05;
	float rgh = mix(rough, mix(0.4, 0.58, (1.0 - porous) / 0.45), wet_all);   // mokrá hlína lesklejší než tráva
	float glint = (hq ? step(0.965, s.nf.a) * step(s.nf.b, 0.3) * ffade : 0.0);
	rgh = mix(rgh, mix(0.72, 0.25, glint), snow);
	rgh = mix(rgh, 0.06, max(rpud, wpatch));
	ROUGHNESS = rgh;
	SPECULAR = mix(mix(mix(0.25, 0.45, wet_all), 0.5, snow), 0.5, max(rpud, wpatch));
	// drobný reliéf → normála (derivace výšky v obrazovce); zdálky slábne (Vysoká+ dosáhne dál)
	float bfade = 1.0 - smoothstep(hq ? 90.0 : 45.0, hq ? 170.0 : 95.0, dist);
	float hb2 = mix(hgt, (d1 - 0.5) * 0.01, snow * 0.8) * (1.0 - max(rpud, wpatch));
	// sklon reliéfu omezený (skok výšky na hranici tříd / polí by jinak dal černé tečkované čáry)
	float lx = length(wdx) * 0.35;
	float ly = length(wdy) * 0.35;
	float dhx = clamp(dFdx(hb2), -lx, lx) * bfade;
	float dhy = clamp(dFdy(hb2), -ly, ly) * bfade;
	n = bump_normal(n, wdx, wdy, dhx, dhy);
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
}
