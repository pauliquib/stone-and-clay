// Stromy (MultiMesh): barva koruny z ortofota je v INSTANCE_CUSTOM (jako atribut instanceru v Blenderu),
// lehké pohupování ve větru.
shader_type spatial;
render_mode cull_back, diffuse_burley;

uniform bool is_leaf = true;
uniform vec3 base_color : source_color = vec3(0.09, 0.18, 0.05);
uniform float instance_mix = 0.65;
uniform sampler2D bark_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform float wind = 1.0;
uniform bool deciduous = true;     // listnáč: na podzim barví a shazuje listí (jehličnany ne)
global uniform float foliage;      // olistění listnáčů 0..1 (Seasons.FOLIAGE)
global uniform float autumn;       // podzimní zbarvení 0..1
global uniform float snow_cover;
global uniform float wind_strength; // 0 bezvětří … 1 vichr (Weather.wind)

varying vec3 tint;
varying vec3 lpos;
varying vec3 wpos;
varying vec3 origin_w;

void vertex() {
	tint = INSTANCE_CUSTOM.rgb;
	lpos = VERTEX;
	vec3 origin = MODEL_MATRIX[3].xyz;
	if (is_leaf) {
		float t = TIME * 1.1 + origin.x * 0.043 + origin.z * 0.061;
		float gust = 0.35 + wind_strength * 2.2;
		float k = VERTEX.y * VERTEX.y * 0.045 * wind * gust;
		VERTEX.x += (sin(t) + 0.35 * sin(t * 2.7 + VERTEX.y * 6.0)) * k;
		VERTEX.z += (cos(t * 0.83) + 0.35 * cos(t * 3.1 + VERTEX.x * 5.0)) * k;
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
	if (is_leaf) {
		vec3 c = mix(base_color, tint, instance_mix);
		float nz = vnoise(wpos * 1.3) * 0.6 + vnoise(wpos * 4.0) * 0.4;
		c *= mix(vec3(0.6, 0.7, 0.5), vec3(1.15), nz);
		if (deciduous) {
			// každý strom se barví a opadává trochu jinak (hash polohy), listí mizí po chomáčích
			float th = hash(floor(origin_w * 0.37) + 0.5);
			float clump = vnoise(wpos * 2.2 + th * 13.0);
			if (clump * 0.85 + th * 0.15 > foliage * 1.05 - 0.02) {
				discard;
			}
			float a = clamp(autumn * 1.5 - th * 0.5 + (clump - 0.5) * 0.3, 0.0, 1.0);
			vec3 ac = mix(vec3(0.78, 0.52, 0.07), vec3(0.62, 0.2, 0.05), smoothstep(0.35, 0.9, th + clump * 0.3));
			ac = mix(ac, vec3(0.42, 0.28, 0.1), smoothstep(0.7, 1.0, a) * (1.0 - foliage) * 0.8);
			c = mix(c, ac * (0.75 + 0.45 * nz), a);
			// jarní rašení: světlejší svěží zeleň
			c = mix(c, vec3(0.28, 0.5, 0.12) * (0.8 + 0.4 * nz), (1.0 - smoothstep(0.35, 1.0, foliage)) * (1.0 - autumn) * 0.7);
		}
		vec3 wn = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
		float snow = clamp(snow_cover * 1.6 - (1.0 - nz) * 0.4, 0.0, 1.0) * smoothstep(0.2, 0.7, wn.y);
		c = mix(c, vec3(0.88, 0.9, 0.95), snow);
		ALBEDO = c;
		ROUGHNESS = 0.8;
		SPECULAR = 0.3;
		BACKLIGHT = c * 0.35;
	} else {
		ALBEDO = texture(bark_tex, vec2(atan(lpos.z, lpos.x) * 0.4, wpos.y * 0.5)).rgb * 1.3;
		ROUGHNESS = 0.9;
	}
}
