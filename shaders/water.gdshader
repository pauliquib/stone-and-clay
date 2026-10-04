// Hladina potoků, řeky a rybníků (Water). UV.x = metry po proudu, UV.y = napříč (0..1);
// u rybníků UV = světové x, z a proud = 0. Vlnky: dvě posouvané vrstvy šumu → normála,
// Fresnel (odraz oblohy z boku), průhlednost podle hloubky za hladinou, pěna u břehu,
// v mrazu led (`ice` 0..1) a sníh na ledu.
shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_disabled, specular_schlick_ggx;

uniform sampler2D noise_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D depth_tex : hint_depth_texture, repeat_disable, filter_nearest;
uniform vec3 shallow_color : source_color = vec3(0.28, 0.36, 0.28);
uniform vec3 deep_color : source_color = vec3(0.06, 0.11, 0.10);
uniform float flow_speed = 0.6;      // m/s po proudu (rybník 0)
uniform float ice = 0.0;             // 0 voda … 1 zamrzlé
uniform float snow = 0.0;            // sníh na ledu
uniform float wave_scale = 1.0;      // větší vlnky v dešti / větru

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float t = TIME;
	vec2 uv = UV;
	vec2 base = world_pos.xz;
	// po proudu: šum se posouvá podél toku (UV.x) – u rybníků se jen pomalu vlní
	vec2 flow = vec2(-t * flow_speed * 0.25, 0.0);
	vec2 a = vec2(uv.x * 0.25, uv.y * 0.7) + flow + base * (flow_speed > 0.01 ? 0.0 : 0.3) + vec2(t * 0.013, t * 0.009);
	vec2 b = vec2(uv.x * 0.6, uv.y * 1.3) + flow * 1.7 + base * (flow_speed > 0.01 ? 0.0 : 0.55) - vec2(t * 0.02, -t * 0.017);
	float n1 = texture(noise_tex, a).r;
	float n2 = texture(noise_tex, b).r;
	float e = 0.02;
	float nx = texture(noise_tex, a + vec2(e, 0.0)).r - n1 + (texture(noise_tex, b + vec2(e, 0.0)).r - n2) * 0.6;
	float nz = texture(noise_tex, a + vec2(0.0, e)).r - n1 + (texture(noise_tex, b + vec2(0.0, e)).r - n2) * 0.6;
	float amp = (1.8 + flow_speed * 2.0) * wave_scale * (1.0 - ice);
	vec3 n_view = normalize((VIEW_MATRIX * vec4(normalize(vec3(-nx * amp, 1.0, -nz * amp)), 0.0)).xyz);
	NORMAL = n_view;

	// hloubka vody za hladinou (z hloubkového bufferu)
	float d_raw = texture(depth_tex, SCREEN_UV).r;
	vec4 ndc = vec4(SCREEN_UV * 2.0 - 1.0, d_raw, 1.0);
	vec4 vpos = INV_PROJECTION_MATRIX * ndc;
	vpos.xyz /= vpos.w;
	float depth = clamp(-vpos.z - (-VERTEX.z), 0.0, 10.0);
	float deep = 1.0 - exp(-depth * 2.2);

	float fres = pow(1.0 - clamp(dot(normalize(VIEW), n_view), 0.0, 1.0), 4.0);
	vec3 col = mix(shallow_color, deep_color, deep);
	// pěna u břehu a v proudu
	float foam = smoothstep(0.12, 0.0, depth) * 0.6 + smoothstep(0.72, 0.9, n2) * 0.25 * min(flow_speed, 1.0);
	col = mix(col, vec3(0.75, 0.78, 0.74), foam * (1.0 - ice));
	vec3 ice_col = mix(vec3(0.62, 0.72, 0.78), vec3(0.93, 0.95, 0.97), snow);
	ALBEDO = mix(col, ice_col, ice);
	ROUGHNESS = mix(0.04, mix(0.25, 0.9, snow), ice);
	METALLIC = 0.0;
	SPECULAR = 0.6;
	ALPHA = mix(clamp(0.45 + deep * 0.45 + fres * 0.4 + foam, 0.0, 0.97), 0.97, ice);
}
