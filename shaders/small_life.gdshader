// M8.18 Drobný život (scripts/priroda/small_life.gd): netopýři, světlušky, motýli, komáří roj, jepice.
// Jedna MultiMesh na druh; CPU zapisuje jen polohu kotvy instance (posun, bez otočení) při změně kotev (~1×/s),
// pohyb kolem kotvy počítá tenhle vertex shader z TIME a INSTANCE_CUSTOM (fáze, poloměr, výška, náhoda):
//   0 netopýr – rychlý cikcak nad vodou / u lampy, mávání křídel, natočení podle rychlosti;
//   1 světluška – pomalé plutí u země, blikání (bod, HDR jas → glow);
//   2 motýl – nepravidelné poletování nad loukou, pomalé mávání;
//   3 komár – hustý roj v kouli kolem kotvy (bod);
//   4 jepice – svatební tanec: rychle nahoru, pomalé snášení (bod).
// Body (1, 3, 4) jsou billboardy (quad ±0,5 → `dot_size`), křídlaté (0, 2) mají vlastní mesh (křídla |x| > 0).
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;

uniform int kind = 0;
uniform float amount = 1.0;        // 0..1 – prolnutí (měřítko)
uniform float light_k = 1.0;       // jas barvy (podle osvětlení scény)
uniform float speed = 1.0;
uniform float roam = 10.0;         // m – poloměr pohybu kolem kotvy
uniform float flap_hz = 10.0;
uniform float flap_amp = 0.8;
uniform float dot_size = 0.03;     // m – velikost bodu (světluška, komár, jepice)
uniform float glow = 4.0;          // světluška – jas záblesku
uniform float blink_hz = 0.35;     // světluška – záblesků za s

varying vec3 v_col;
varying float v_blink;

float tri(float x) {
	return abs(fract(x) * 2.0 - 1.0) * 2.0 - 1.0;
}

vec3 life_path(float t, vec4 cd) {
	float ph = cd.x * 6.2831853;
	float r = roam * (0.5 + cd.y);
	if (kind == 0) {
		float a = t * speed * 0.45 + ph;
		return vec3(sin(a) * r + tri(a * 2.3 + cd.w) * 1.8,
			cd.z + sin(a * 1.7 + ph) * 1.2,
			sin(a * 2.0 + ph * 0.5) * r * 0.6 + tri(a * 3.1) * 1.2);
	} else if (kind == 1) {
		float a = t * speed * 0.08 + ph;
		return vec3(sin(a) * r, cd.z + sin(a * 1.6 + ph) * 0.4, cos(a * 0.8 + ph) * r);
	} else if (kind == 2) {
		float a = t * speed * 0.22 + ph;
		return vec3(sin(a) * r + sin(a * 3.7) * 0.6,
			cd.z + abs(sin(a * 2.3 + ph)) * 0.6 + sin(t * 6.0 + ph) * 0.08,
			cos(a * 1.3 + ph) * r + sin(a * 4.1 + ph) * 0.5);
	} else if (kind == 3) {
		float a = t * speed * 2.5 + ph * 7.0;
		return vec3(sin(a * 1.3) * r, cd.z + sin(a * 1.9 + ph) * r * 0.6, cos(a * 1.1 + ph) * r);
	}
	float a = fract(t * speed * 0.18 + cd.x);
	float up = a < 0.25 ? a / 0.25 : 1.0 - (a - 0.25) / 0.75;
	return vec3(sin(ph + t * 0.3) * r, cd.z + up * 2.5, cos(ph * 1.7 + t * 0.2) * r);
}

void vertex() {
	vec4 cd = INSTANCE_CUSTOM;
	float t = TIME;
	vec3 off = life_path(t, cd);
	v_col = COLOR.rgb;
	v_blink = 1.0;
	if (kind == 0 || kind == 2) {
		vec3 nx = life_path(t + 0.05, cd);
		vec3 dir = nx - off;
		float yaw = atan(dir.x, dir.z);
		float flap = sin(t * flap_hz * 6.2831853 + cd.w * 40.0);
		vec3 v = VERTEX * amount;
		v.y += flap * abs(v.x) * flap_amp;
		float cs = cos(yaw);
		float sn = sin(yaw);
		v = vec3(v.x * cs + v.z * sn, v.y, -v.x * sn + v.z * cs);
		VERTEX = v + off;
	} else {
		if (kind == 1) {
			v_blink = pow(max(sin(t * blink_hz * 6.2831853 * (0.7 + cd.w * 0.6) + cd.x * 40.0), 0.0), 10.0);
		}
		float sz = dot_size * amount * (kind == 1 ? (0.4 + 0.6 * v_blink) : 1.0);
		vec3 center = (MODEL_MATRIX * vec4(off, 1.0)).xyz;
		vec3 view = (VIEW_MATRIX * vec4(center, 1.0)).xyz + vec3(VERTEX.xy * sz, 0.0);
		POSITION = PROJECTION_MATRIX * vec4(view, 1.0);
	}
}

void fragment() {
	if (kind == 1) {
		ALBEDO = vec3(0.7, 1.0, 0.25) * (0.05 + glow * v_blink);
	} else {
		ALBEDO = v_col * light_k;
	}
}
