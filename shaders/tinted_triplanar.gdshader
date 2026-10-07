// Fasády, střechy a cesty – PBR Poly Haven, triplanární projekce ve světových souřadnicích,
// jas textury × barva budovy (atribut 'tint' z Blenderu → barva vrcholu), stejně jako v Blender scéně.
shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rough_tex : hint_roughness_g, filter_linear_mipmap, repeat_enable;
uniform float tex_size_m = 3.0;
uniform float desaturate = 1.0;
uniform float gain = 1.0;
uniform bool use_vertex_tint = true;
uniform vec3 base_tint : source_color = vec3(1.0);
uniform float normal_strength = 0.7;
uniform float blend_sharpness = 4.0;
uniform float snow_amount = 1.0;   // kolik sněhu na vodorovných plochách drží (silnice jsou protažené)
uniform float wet_boost = 1.0;     // násobek mokrého efektu (asfalt leskne výrazněji, §12.3)
global uniform float snow_cover;
global uniform float wetness;

varying vec3 wpos;
varying vec3 wnrm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 n = normalize(wnrm);
	if (!FRONT_FACING) { n = -n; }
	vec3 bw = pow(abs(n), vec3(blend_sharpness));
	bw /= (bw.x + bw.y + bw.z);
	vec3 p = wpos / tex_size_m;
	vec3 cx = texture(albedo_tex, p.zy).rgb;
	vec3 cy = texture(albedo_tex, p.xz).rgb;
	vec3 cz = texture(albedo_tex, p.xy).rgb;
	vec3 c = cx * bw.x + cy * bw.y + cz * bw.z;
	float lum = dot(c, vec3(0.2126, 0.7152, 0.0722));
	c = mix(c, vec3(lum), desaturate) * gain;
	vec3 tint = use_vertex_tint ? COLOR.rgb : base_tint;
	vec3 alb = c * tint;
	float r = texture(rough_tex, p.zy).g * bw.x + texture(rough_tex, p.xz).g * bw.y + texture(rough_tex, p.xy).g * bw.z;
	// sníh na střechách a cestách (plochy natočené vzhůru), mokro – tmavší a lesklejší
	float snow = clamp((snow_cover * snow_amount * 1.4 - (1.0 - lum) * 0.25) * 1.8, 0.0, 1.0) * smoothstep(0.35, 0.7, n.y);
	float wet = clamp(wetness * wet_boost, 0.0, 1.0) * (1.0 - snow) * (0.4 + 0.6 * clamp(n.y, 0.0, 1.0));
	alb *= 1.0 - 0.3 * wet;
	ALBEDO = mix(alb, vec3(0.9, 0.92, 0.96), snow);
	ROUGHNESS = mix(mix(clamp(r, 0.3, 1.0), 0.18, wet), 0.7, snow);
	SPECULAR = mix(0.5, 0.7, wet);   // mokrý povrch leskne víc (za sucha původní 0,5; asfalt díky wet_boost)
	vec2 tx = texture(normal_tex, p.zy).xy * 2.0 - 1.0;
	vec2 ty = texture(normal_tex, p.xz).xy * 2.0 - 1.0;
	vec2 tz = texture(normal_tex, p.xy).xy * 2.0 - 1.0;
	vec3 wn = normalize(n + normal_strength * (vec3(0.0, tx.y, tx.x) * bw.x + vec3(tz.x, tz.y, 0.0) * bw.z + vec3(ty.x, 0.0, ty.y) * bw.y));
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
}
