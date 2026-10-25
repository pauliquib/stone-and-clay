// M8.8 Impostory stromů pro dálku: svislá karta natočená ke kameře (kolem osy Y), snímek z atlasu podle úhlu pohledu
// (IMP_VIEWS pohledů kolem stromu, mezi sousedními se prolíná), barva + normála vypečené tools/treegen/bake.py.
// Varianta stromu = barva instance MultiMeshe (COLOR.r · 255), rozměry varianty v `imp_ext`. Odstín koruny jako u
// tree.gdshader z INSTANCE_CUSTOM.rgb, sezóna (rašení, podzim po chomáčích, opad, sníh) zjednodušeně stejně –
// při změně sezónní logiky v tree.gdshader drž v souladu. Bez listí (zima) ukáže siluetu holých větví (normála.a).
//
// 2026-10 (dron, vítr, stín):
//   * karta se natáčí i nahoru ke kameře (náklon = výška pohledu nad středem koruny, pivot ve středu koruny) – shora
//     se nezplošťuje do čárky; od ~43° do ~70° se po pixelech (dither) prolne do procedurální koruny shora (kruh
//     s laločnatým okrajem a chomáči, u jehličnanů přesleny, v zimě paprsky holých větví) se sférickou normálou.
//   * vítr: rohy karty se hýbou stejným ohybem kmene jako LOD0/LOD1 (`wind_bend`, jen složka kmene).
//   * stínový průchod (stíny impostorů zapíná TreeGen jen od Vysoké): karta se natočí ke světlu (svislá) – stín má
//     siluetu stromu, ne čáru. Poznává se podle toho, že kamera průchodu není hlavní kamera.
//   * osvětlení jako LOD1 (drsnost, prosvítání listí, okluze, variace barvy podle stromu).
shader_type spatial;
render_mode cull_disabled, diffuse_burley, world_vertex_coords;

uniform sampler2D imp_color : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D imp_normal : filter_linear_mipmap, repeat_disable;
uniform vec4 imp_ext[64];                // varianta: x = půlšířka, y = spodek, z = vrchol (× měřítko), w = 1 listnáč
uniform float imp_views = 8.0;
uniform float imp_rows = 32.0;
uniform vec4 lod_band = vec4(170.0, 1e6, 6.0, 0.0);   // od, do, půlšířka prolínání (m) – navazuje na LOD1
uniform vec3 base_color : source_color = vec3(0.09, 0.18, 0.05);
uniform vec3 base_color_conifer : source_color = vec3(0.05, 0.12, 0.05);
uniform float instance_mix = 0.65;
uniform vec3 bark_winter : source_color = vec3(0.3, 0.27, 0.24);
global uniform float foliage;
global uniform float autumn;
global uniform float snow_cover;

#include "res://shaders/include/wind.gdshaderinc"
#include "res://shaders/include/tree_gen.gdshaderinc"
#include "res://shaders/include/phenology.gdshaderinc"

const float IMP_SELF_SHADE = 0.62;       // ztmavení listí impostoru na jas LOD1 (viz fragment)

varying vec3 tint;
varying vec2 tg_fade;
varying float frame_a;
varying float frame_t;
varying float row;
varying float decid;
varying vec3 bb_right;
varying vec3 bb_fwd;
varying vec3 wpos;
varying vec3 origin_w;
varying vec2 v_q;            // poloha na kartě (m): x napříč, y podél karty od středu koruny
varying vec3 v_ext;          // půlšířka, spodek a vrchol stromu vůči středu koruny (m)
varying vec3 v_upv;          // osa karty „nahoru“ (nakloněná ke kameře)
varying vec3 v_nrm;          // normála karty
varying float top_k;         // 0 = boční snímek z atlasu, 1 = koruna shora
// M8.11: fenologie druhu a místa jako v tree.gdshader (include/phenology)
varying flat vec4 ph_st;
varying flat vec3 ph_aut;
varying flat vec3 ph_spr;
varying flat vec4 ph_bl;
varying flat vec2 ph_fl;

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	origin_w = origin;
	tint = INSTANCE_CUSTOM.rgb;
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
	int vi = clamp(int(floor(COLOR.r * 255.0 + 0.5)), 0, 63);
	vec4 ext = imp_ext[vi];
	row = float(vi);
	decid = ext.w;
	vec3 cam = MAIN_CAM_INV_VIEW_MATRIX[3].xyz;
	float dc = distance(cam, origin);
	tg_fade = tg_band_fade(dc, lod_band);
	vec3 ax = MODEL_MATRIX[0].xyz;
	vec3 az = MODEL_MATRIX[2].xyz;
	float sxz = max(length(ax), 1e-4);
	float sy = length(MODEL_MATRIX[1].xyz);
	float w = ext.x * sxz;
	float y_lo = ext.y * sy;
	float y_hi = ext.z * sy;
	float cy = mix(y_lo, y_hi, 0.6);                 // pivot karty ≈ střed koruny
	// stínový průchod: kamera průchodu není hlavní kamera → karta svisle čelem ke světlu
	bool shadow_pass = distance(CAMERA_POSITION_WORLD, cam) > 0.05;
	vec2 hv;
	float el = 0.0;
	if (shadow_pass) {
		hv = INV_VIEW_MATRIX[2].xz;                  // směr ke světlu (ortografická stínová kamera)
	} else {
		vec3 tc = cam - (origin + vec3(0.0, cy, 0.0));
		hv = tc.xz;
		el = clamp(atan(tc.y, max(length(tc.xz), 1e-3)), 0.0, 1.45);
	}
	float hl = length(hv);
	hv = hl > 1e-4 ? hv / hl : vec2(0.0, 1.0);
	bb_fwd = vec3(hv.x, 0.0, hv.y);
	bb_right = vec3(hv.y, 0.0, -hv.x);              // cross(up, fwd) – shodně s pečením
	// úhel pohledu v lokálu instance (rotace kolem Y) → snímek atlasu
	float lx = dot(bb_fwd, ax / sxz);
	float lz = dot(bb_fwd, az / sxz);
	float phi = atan(lx, lz);
	if (phi < 0.0) {
		phi += 6.2831853;
	}
	float f = phi / 6.2831853 * imp_views;
	frame_a = floor(f);
	frame_t = f - frame_a;
	// náklon ke kameře kolem vodorovné osy (shora se karta nezploští); karta pokryje i kruh koruny shora
	v_upv = vec3(0.0, cos(el), 0.0) - bb_fwd * sin(el);
	v_nrm = bb_fwd * cos(el) + vec3(0.0, sin(el), 0.0);
	top_k = smoothstep(0.75, 1.22, el);
	v_ext = vec3(w, y_lo - cy, y_hi - cy);
	float qlo = min(y_lo - cy, -w);
	float qhi = max(y_hi - cy, w);
	v_q = vec2((UV.x * 2.0 - 1.0) * w, mix(qhi, qlo, UV.y));
	VERTEX = origin + vec3(0.0, cy, 0.0) + bb_right * v_q.x + v_upv * v_q.y;
	if (wind_hier > 0.5) {
		// vítr: jen ohyb kmene (jako LOD0/LOD1 – na přechodu LOD nic neskočí)
		VERTEX += wind_bend(VERTEX - origin, origin, vec4(0.0, 0.0, 0.0, 1.0), max(y_hi, 1.0), decid > 0.5 ? 1.0 : 1.3);
	}
	NORMAL = v_nrm;
	if (tg_band_outside(dc, lod_band)) {
		VERTEX = origin;                            // blízko: strom kreslí LOD0/LOD1
	}
	wpos = VERTEX;
}

void fragment() {
	if (tg_dither_out(FRAGCOORD.xy, tg_fade)) {
		discard;
	}
	float th = tg_hash(floor(origin_w * 0.37) + 0.5);
	// boční snímek z atlasu (UV z polohy na kartě – karta je vyšší / širší kvůli pohledu shora); čte se mimo větvení,
	// aby mipmapy (derivace) seděly i na pixelech prolnutí s korunou shora
	vec2 uvl = vec2(v_q.x / max(v_ext.x, 1e-3) * 0.5 + 0.5, (v_ext.z - v_q.y) / max(v_ext.z - v_ext.y, 1e-3));
	bool inside = uvl.x >= 0.0 && uvl.y >= 0.0 && uvl.x <= 1.0 && uvl.y <= 1.0;
	vec2 cell = vec2(1.0 / imp_views, 1.0 / imp_rows);
	uvl = clamp(uvl, vec2(0.004), vec2(0.996));
	float fa = mod(frame_a, imp_views);
	float fb = mod(frame_a + 1.0, imp_views);
	vec2 ua = (vec2(fa, row) + uvl) * cell;
	vec2 ub = (vec2(fb, row) + uvl) * cell;
	vec4 col = mix(texture(imp_color, ua), texture(imp_color, ub), frame_t);
	vec4 nr = mix(texture(imp_normal, ua), texture(imp_normal, ub), frame_t);
	vec3 nw;
	if (tg_dither(FRAGCOORD.yx + vec2(17.0, 5.0)) >= top_k) {
		if (!inside || col.a < 0.5) {
			discard;
		}
		vec2 nxy = nr.rg * 2.0 - 1.0;
		nw = normalize(bb_right * nxy.x + vec3(0.0, nxy.y, 0.0) + bb_fwd * sqrt(clamp(1.0 - dot(nxy, nxy), 0.0, 1.0)));
	} else {
		// koruna shora: laločnatý kruh (jehličnan: přesleny), chomáče listí, sférická normála
		vec2 d = v_q / max(v_ext.x * 0.95, 0.1);
		float r = length(d);
		float a = atan(d.y, d.x);
		float cl = tg_vnoise(vec3(d * 2.6 + th * 11.0, th * 5.0));
		float edge = decid > 0.5
			? 0.78 + 0.2 * tg_vnoise(vec3(cos(a) * 2.2 + th * 7.0, sin(a) * 2.2, th * 3.0))
			: 0.68 + 0.27 * pow(abs(sin(a * 4.0 + th * 9.0)), 0.6);
		if (r > edge * (0.9 + 0.16 * cl)) {
			discard;
		}
		float cl2 = tg_vnoise(vec3(d * 2.6 + 4.7 + th * 11.0, th * 5.0 + 2.0));
		float hz = sqrt(max(1.0 - r * r, 0.05)) * (decid > 0.5 ? 1.0 : 0.6);
		vec3 nl = normalize(vec3(d.x + (cl - 0.5) * 0.7, d.y + (cl2 - 0.5) * 0.7, hz));
		nw = normalize(bb_right * nl.x + v_upv * nl.y + v_nrm * nl.z);
		col = vec4(vec3(TG_LEAF_MEAN * (0.65 + 0.6 * cl)), 1.0);
		float tw = abs(sin(a * 9.0 + r * 5.0 + th * 20.0));   // zima: paprsky holých větví
		nr = vec4(0.5, 0.5, 1.0, (tw < 0.12 + 0.28 * (1.0 - r) && r < 0.92) ? 1.0 : 0.0);
		if (decid < 0.5) {
			nr.a = 1.0;
		}
	}
	vec3 c;
	bool leaf = nr.b > 0.5;
	float nz = tg_vnoise(wpos * 1.3) * 0.6 + tg_vnoise(wpos * 4.0) * 0.4;
	if (leaf) {
		c = mix(mix(base_color_conifer, base_color, decid), tint, instance_mix);
		c *= mix(vec3(0.6, 0.7, 0.5), vec3(1.15), nz);
		c *= tg_tree_var(th);                       // variace odstínu a jasu podle stromu (shodně s tree.gdshader)
		bool dec = ph_fl.x > 0.5 ? ph_fl.y < 0.5 : decid > 0.5;   // M8.11: modřín opadává i jako jehličnan
		float fol = ph_st.x;
		float aut = ph_st.y;
		if (dec) {
			float clump = tg_vnoise(wpos * 2.2 + th * 13.0);
			bool flower = ph_bl.a > 0.5 && ph_st.z > 0.01 && tg_vnoise(wpos * 6.5 + th * 7.0) > 1.0 - 0.55 * ph_st.z;
			if (clump * 0.85 + th * 0.15 > fol * 1.05 - 0.02 && !flower) {
				if (nr.a < 0.5) {
					discard;                        // bez listí a bez větve za ním
				}
				leaf = false;                       // holá větev (zimní silueta)
				c = bark_winter * (0.8 + 0.3 * nz);
			} else {
				float a = clamp(aut * 1.5 - th * 0.5 + (clump - 0.5) * 0.3, 0.0, 1.0);
				vec3 ac = mix(vec3(0.78, 0.52, 0.07), vec3(0.62, 0.2, 0.05), smoothstep(0.35, 0.9, th + clump * 0.3));
				if (ph_fl.x > 0.5) {
					ac = ph_aut * (0.8 + 0.4 * th);
				}
				ac = mix(ac, vec3(0.42, 0.28, 0.1), smoothstep(0.7, 1.0, a) * (1.0 - fol) * 0.8);
				c = mix(c, ac * (0.75 + 0.45 * nz), a);
				c = mix(c, ph_spr * (0.8 + 0.4 * nz), (1.0 - smoothstep(0.35, 1.0, fol)) * (1.0 - aut) * 0.7);
				if (flower) {
					c = ph_bl.rgb * (0.85 + 0.3 * nz);
				}
			}
		} else if (ph_fl.x > 0.5 && ph_st.w > 0.01) {
			float tip = smoothstep(0.45, 0.8, tg_vnoise(wpos * 3.1 + th * 5.0));
			c = mix(c, ph_spr * (1.4 + 0.4 * nz), tip * ph_st.w * 0.6);
		}
		if (leaf) {
			// × IMP_SELF_SHADE: LOD1 má v koruně vlastní stíny a okluzi listů (COLOR.a), vypečený snímek ne – bez
			// korekce byla koruna impostoru ~1,8× světlejší než stejný strom v LOD1 (měřeno na snímku z dronu)
			c *= col.r / TG_LEAF_MEAN * IMP_SELF_SHADE;
		}
	} else {
		c = col.rgb;
	}
	float snow = clamp(snow_cover * 1.6 - (1.0 - nz) * 0.4, 0.0, 1.0) * smoothstep(0.2, 0.7, nw.y);
	c = mix(c, vec3(0.88, 0.9, 0.95), snow);
	NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);
	ALBEDO = c;
	ROUGHNESS = 0.8;
	SPECULAR = leaf ? 0.12 : 0.3;                    // listí jako LOD1 (bez bílého odlesku na hraně)
	AO = 0.85;                                      // průměrná okluze v koruně (LOD1: z barvy vrcholu)
	AO_LIGHT_AFFECT = 0.0;
	if (leaf) {
		BACKLIGHT = c * TG_LEAF_BACKLIGHT * 0.4;    // prosvítání listí jako LOD1 (průměr přes korunu)
	}
}
