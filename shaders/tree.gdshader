// Stromy (MultiMesh): barva koruny z ortofota je v INSTANCE_CUSTOM (jako atribut instanceru v Blenderu),
// ohyb ve větru: M8.4 hierarchicky (kmen → větev → list, nárazy z pole větru, include/wind.gdshaderinc);
// s vypnutým realismem „wind“ (global wind_hier = 0) stará sinusovka.
// Dnešní prototypy barvy vrcholů nemají → `use_vertex_color = false` odvodí ohebnost z výšky a vzdálenosti
// od osy, fázi z hashe polohy a třepetání = is_leaf (přesné barvy dodá generátor M8.8 a přepne uniform).
shader_type spatial;
render_mode cull_disabled, diffuse_burley;   // M8.8: karty listí jsou oboustranné (dřív cull_back)

uniform bool is_leaf = true;
uniform vec3 base_color : source_color = vec3(0.09, 0.18, 0.05);
uniform float instance_mix = 0.65;
uniform sampler2D bark_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform float wind = 1.0;
uniform bool deciduous = true;     // listnáč: na podzim barví a shazuje listí (jehličnany ne)
global uniform float foliage;      // olistění listnáčů 0..1 (Seasons.FOLIAGE)
global uniform float autumn;       // podzimní zbarvení 0..1
global uniform float snow_cover;
global uniform float wind_strength; // 0 bezvětří … 1 vichr (Weather.wind / 12) – stará cesta
uniform bool use_vertex_color = false;   // M8.8: barvy vrcholů podle konvence (wind.gdshaderinc)
uniform float local_height = 1.0;        // výška prototypu v lokálních jednotkách (měřítko instance = výška v m)
uniform float stiffness = 1.0;           // tuhost kmene – musí být stejná u kůry i koruny téhož prototypu (jinak se rozejdou)
// M8.8 generované stromy (tools/treegen): atlasy listí a kůry (dlaždice podle UV2.x), LOD pásmo instance (include/tree_gen)
uniform bool use_atlas = false;
uniform sampler2D leaf_atlas : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D bark_atlas : source_color, filter_linear_mipmap, repeat_disable;
uniform vec2 atlas_grid = vec2(4.0, 2.0);
uniform vec4 lod_band = vec4(0.0, 1e6, 0.0, 0.0);   // od, do, půlšířka prolínání (m); z = 0 → bez pásma (staré stromy)

#include "res://shaders/include/wind.gdshaderinc"
#include "res://shaders/include/tree_gen.gdshaderinc"
#include "res://shaders/include/phenology.gdshaderinc"

varying vec3 tint;
varying vec3 lpos;
varying vec3 wpos;
varying vec3 origin_w;
varying vec2 tg_fade;
// M8.11: fenologie druhu a místa (include/phenology) – stav, barvy podzimu / jara / květů, příznaky
varying flat vec4 ph_st;
varying flat vec3 ph_aut;
varying flat vec3 ph_spr;
varying flat vec4 ph_bl;
varying flat vec2 ph_fl;     // x = 1 platný kód, y = 1 stálezelený

void vertex() {
	tint = INSTANCE_CUSTOM.rgb;
	lpos = VERTEX;
	ph_st = vec4(foliage, autumn, 0.0, 0.0);
	ph_aut = vec3(0.0);
	ph_spr = vec3(0.28, 0.5, 0.12);
	ph_bl = vec4(0.0);
	ph_fl = vec2(0.0);
	if (ph_valid(INSTANCE_CUSTOM.a)) {
		ivec2 pc = ph_cell(INSTANCE_CUSTOM.a);
		ph_st = ph_state(pc);
		ph_aut = ph_info(pc, PH_COL_AUT).rgb;
		ph_spr = ph_info(pc, PH_COL_SPR).rgb;
		ph_bl = ph_info(pc, PH_COL_BLOOM);
		ph_fl = vec2(1.0, ph_info(pc, PH_COL_FLAGS).r);
	}
	vec3 origin = MODEL_MATRIX[3].xyz;
	float tg_dc = distance(MAIN_CAM_INV_VIEW_MATRIX[3].xyz, origin);   // M8.8: LOD pásmo podle hlavní kamery
	bool tg_cull = tg_band_outside(tg_dc, lod_band);
	tg_fade = tg_band_fade(tg_dc, lod_band);
	if (wind_hier > 0.5 && !tg_cull) {
		mat3 b = mat3(MODEL_MATRIX);
		vec3 vl = b * VERTEX;
		float H = length(MODEL_MATRIX[1].xyz) * local_height;
		vec4 col = COLOR;
		if (!use_vertex_color) {
			float hh = clamp(vl.y / max(H, 0.5), 0.0, 1.0);
			float rad = clamp(length(vl.xz) / max(0.3 * H, 0.3), 0.0, 1.0);
			col = vec4(0.0, 0.0, 0.0, 1.0);          // kůra: jen ohyb kmene (drží se listí)
			if (is_leaf) {
				col = vec4(smoothstep(0.25, 0.9, hh) * (0.35 + 0.65 * rad), wind_hash(floor(vl * 1.3) + 0.5), 1.0, 1.0);
			}
		}
		VERTEX += inverse(b) * wind_bend(vl, origin, col, H, stiffness);
	} else if (is_leaf && !tg_cull) {
		float t = TIME * 1.1 + origin.x * 0.043 + origin.z * 0.061;
		float gust = 0.35 + wind_strength * 2.2;
		float k = VERTEX.y * VERTEX.y * 0.045 * wind * gust;
		VERTEX.x += (sin(t) + 0.35 * sin(t * 2.7 + VERTEX.y * 6.0)) * k;
		VERTEX.z += (cos(t * 0.83) + 0.35 * cos(t * 3.1 + VERTEX.x * 5.0)) * k;
	}
	if (tg_cull) {
		VERTEX = vec3(0.0);                      // mimo LOD pásmo: nulová plocha, rasterizér zahodí
	}
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	origin_w = origin;
}

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float vnoise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1, 0, 0)), f.x), mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
	           mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x), mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

void fragment() {
	if (lod_band.z > 0.0 && tg_dither_out(FRAGCOORD.xy, tg_fade)) {
		discard;                                 // M8.8: prolínání LOD po pixelech
	}
	if (is_leaf) {
		vec3 c = mix(base_color, tint, instance_mix);
		float nz = vnoise(wpos * 1.3) * 0.6 + vnoise(wpos * 4.0) * 0.4;
		c *= mix(vec3(0.6, 0.7, 0.5), vec3(1.15), nz);
		// M8.11: s platným kódem instance rozhoduje o opadu druh (modřín opadává, smrk ne), jinak materiál
		bool decid = ph_fl.x > 0.5 ? ph_fl.y < 0.5 : deciduous;
		float fol = ph_st.x;
		float aut = ph_st.y;
		float th = hash(floor(origin_w * 0.37) + 0.5);
		if (decid) {
			// každý strom se barví a opadává trochu jinak (hash polohy), listí mizí po chomáčích
			float clump = vnoise(wpos * 2.2 + th * 13.0);
			// M8.11: kvetoucí strom (ovocné, třešeň, akát…) má v koruně bílé / růžové chomáče i bez listí
			bool flower = ph_bl.a > 0.5 && ph_st.z > 0.01 && vnoise(wpos * 6.5 + th * 7.0) > 1.0 - 0.55 * ph_st.z;
			if (clump * 0.85 + th * 0.15 > fol * 1.05 - 0.02 && !flower) {
				discard;
			}
			float a = clamp(aut * 1.5 - th * 0.5 + (clump - 0.5) * 0.3, 0.0, 1.0);
			vec3 ac = mix(vec3(0.78, 0.52, 0.07), vec3(0.62, 0.2, 0.05), smoothstep(0.35, 0.9, th + clump * 0.3));
			if (ph_fl.x > 0.5) {
				ac = ph_aut * (0.8 + 0.4 * th);       // barva podzimu druhu (dreviny.json)
			}
			ac = mix(ac, vec3(0.42, 0.28, 0.1), smoothstep(0.7, 1.0, a) * (1.0 - fol) * 0.8);
			c = mix(c, ac * (0.75 + 0.45 * nz), a);
			// jarní rašení: světlejší svěží zeleň (s fenologií barva jara druhu)
			c = mix(c, ph_spr * (0.8 + 0.4 * nz), (1.0 - smoothstep(0.35, 1.0, fol)) * (1.0 - aut) * 0.7);
			if (flower) {
				c = ph_bl.rgb * (0.85 + 0.3 * nz);
			}
		} else if (ph_fl.x > 0.5 && ph_st.w > 0.01) {
			// M8.11: jarní přírůst jehličnanů – světlé špičky výhonů
			float tip = smoothstep(0.45, 0.8, vnoise(wpos * 3.1 + th * 5.0));
			c = mix(c, ph_spr * (1.4 + 0.4 * nz), tip * ph_st.w * 0.6);
		}
		if (use_atlas) {                         // M8.8: karta trsu listí z atlasu (kresba × okluze v koruně)
			vec4 lt = tg_leaf(leaf_atlas, UV, UV2.x, atlas_grid);
			if (lt.a < 0.5) {
				discard;
			}
			c *= lt.rgb / TG_LEAF_MEAN * mix(0.5, 1.0, COLOR.a);
			if (!FRONT_FACING) {
				NORMAL = -NORMAL;              // rub karty: normála dál ven z koruny (měkké světlo)
			}
		}
		vec3 wn = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
		float snow = clamp(snow_cover * 1.6 - (1.0 - nz) * 0.4, 0.0, 1.0) * smoothstep(0.2, 0.7, wn.y);
		c = mix(c, vec3(0.88, 0.9, 0.95), snow);
		ALBEDO = c;
		ROUGHNESS = 0.8;
		SPECULAR = 0.3;
		BACKLIGHT = c * 0.35;
	} else if (use_atlas) {                     // M8.8: kůra podle druhu z atlasu, okluze z barvy vrcholu
		ALBEDO = tg_bark(bark_atlas, UV, UV2.x, atlas_grid) * mix(0.45, 1.0, COLOR.a);
		ROUGHNESS = 0.9;
	} else {
		ALBEDO = texture(bark_tex, vec2(atan(lpos.z, lpos.x) * 0.4, wpos.y * 0.5)).rgb * 1.3;
		ROUGHNESS = 0.9;
	}
}
