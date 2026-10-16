// M8.8 Impostory stromů pro dálku: svislá karta natočená ke kameře (kolem osy Y), snímek z atlasu podle úhlu pohledu
// (IMP_VIEWS pohledů kolem stromu, mezi sousedními se prolíná), barva + normála vypečené tools/treegen/bake.py.
// Varianta stromu = barva instance MultiMeshe (COLOR.r · 255), rozměry varianty v `imp_ext`. Odstín koruny jako u
// tree.gdshader z INSTANCE_CUSTOM.rgb, sezóna (rašení, podzim po chomáčích, opad, sníh) zjednodušeně stejně –
// při změně sezónní logiky v tree.gdshader drž v souladu. Bez listí (zima) ukáže siluetu holých větví (normála.a).
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

#include "res://shaders/include/tree_gen.gdshaderinc"

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

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	origin_w = origin;
	tint = INSTANCE_CUSTOM.rgb;
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
	vec2 hv = cam.xz - origin.xz;
	hv = hv / max(length(hv), 1e-4);
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
	float qx = (UV.x * 2.0 - 1.0) * ext.x * sxz;
	float qy = mix(ext.z, ext.y, UV.y) * sy;
	VERTEX = origin + bb_right * qx + vec3(0.0, qy, 0.0);
	NORMAL = bb_fwd;
	if (tg_band_outside(dc, lod_band)) {
		VERTEX = origin;                            // blízko: strom kreslí LOD0/LOD1
	}
	wpos = VERTEX;
}

void fragment() {
	if (tg_dither_out(FRAGCOORD.xy, tg_fade)) {
		discard;
	}
	vec2 cell = vec2(1.0 / imp_views, 1.0 / imp_rows);
	vec2 uvl = clamp(UV, vec2(0.004), vec2(0.996));
	float fa = mod(frame_a, imp_views);
	float fb = mod(frame_a + 1.0, imp_views);
	vec2 ua = (vec2(fa, row) + uvl) * cell;
	vec2 ub = (vec2(fb, row) + uvl) * cell;
	vec4 col = mix(texture(imp_color, ua), texture(imp_color, ub), frame_t);
	vec4 nr = mix(texture(imp_normal, ua), texture(imp_normal, ub), frame_t);
	if (col.a < 0.5) {
		discard;
	}
	vec3 c;
	bool leaf = nr.b > 0.5;
	float nz = tg_vnoise(wpos * 1.3) * 0.6 + tg_vnoise(wpos * 4.0) * 0.4;
	if (leaf) {
		c = mix(mix(base_color_conifer, base_color, decid), tint, instance_mix);
		c *= mix(vec3(0.6, 0.7, 0.5), vec3(1.15), nz);
		if (decid > 0.5) {
			float th = tg_hash(floor(origin_w * 0.37) + 0.5);
			float clump = tg_vnoise(wpos * 2.2 + th * 13.0);
			if (clump * 0.85 + th * 0.15 > foliage * 1.05 - 0.02) {
				if (nr.a < 0.5) {
					discard;                        // bez listí a bez větve za ním
				}
				leaf = false;                       // holá větev (zimní silueta)
				c = bark_winter * (0.8 + 0.3 * nz);
			} else {
				float a = clamp(autumn * 1.5 - th * 0.5 + (clump - 0.5) * 0.3, 0.0, 1.0);
				vec3 ac = mix(vec3(0.78, 0.52, 0.07), vec3(0.62, 0.2, 0.05), smoothstep(0.35, 0.9, th + clump * 0.3));
				ac = mix(ac, vec3(0.42, 0.28, 0.1), smoothstep(0.7, 1.0, a) * (1.0 - foliage) * 0.8);
				c = mix(c, ac * (0.75 + 0.45 * nz), a);
				c = mix(c, vec3(0.28, 0.5, 0.12) * (0.8 + 0.4 * nz), (1.0 - smoothstep(0.35, 1.0, foliage)) * (1.0 - autumn) * 0.7);
			}
		}
		if (leaf) {
			c *= col.r / TG_LEAF_MEAN;
		}
	} else {
		c = col.rgb;
	}
	vec2 nxy = nr.rg * 2.0 - 1.0;
	vec3 nw = normalize(bb_right * nxy.x + vec3(0.0, nxy.y, 0.0) + bb_fwd * sqrt(clamp(1.0 - dot(nxy, nxy), 0.0, 1.0)));
	float snow = clamp(snow_cover * 1.6 - (1.0 - nz) * 0.4, 0.0, 1.0) * smoothstep(0.2, 0.7, nw.y);
	c = mix(c, vec3(0.88, 0.9, 0.95), snow);
	NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);
	ALBEDO = c;
	ROUGHNESS = 0.85;
	SPECULAR = 0.3;
	if (leaf) {
		BACKLIGHT = c * 0.35;
	}
}
