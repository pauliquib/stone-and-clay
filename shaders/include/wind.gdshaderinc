// M8.4 Pole větru – sdílený hierarchický ohyb vegetace (kmen → větev → list) a vlny přes trávu / obilí.
// Podle čeho: síla větru ∝ v², průhyb kmene ∝ (y/H)², vlastní frekvence kmene ∝ 1/H (tlumený oscilátor
// buzený nárazy), nárazy = zamrzlá turbulence posouvaná krajinou (Taylor) – stejná mřížka jako WindField.
//
// Globální uniformy (project.godot [shader_globals], nastavuje Atmosphere každý snímek z World.wind_field):
//   wind_dir    vec2       jednotkový směr, KAM fouká (svět xz)
//   wind_speed  float      m/s, 10 m nad otevřenou loukou (Weather.wind)
//   wind_gust   sampler2D  L8 256², 4 m/texel (dlaždice 1 024 m) – WindField.gust_texture
//   wind_offset vec2       m – posun pole nárazů (Taylor), uv = (xz − wind_offset) / WIND_GUST_TILE
//   wind_time   float      s – fáze kmitů
//   wind_hier   float      1 = nový model (realismus „wind“), 0 = stará sinusovka (shader si větví sám)
//
// KONVENCE BAREV VRCHOLŮ VEGETACE (00_PRINCIPY kap. 4 – generátor stromů M8.8 a přízemní vegetace M8.14 ji dodrží):
//   COLOR.r  ohebnost / úroveň větve: 0 = kmen u země (nehybný) … 1 = konec tenké větve
//   COLOR.g  fáze větve (hash 0..1) – sousední větve nekmitají spolu
//   COLOR.b  váha třepetání listů (0 = dřevo, 1 = list)
//   COLOR.a  okluze uvnitř koruny (0 tmavé jádro … 1 okraj)
// Barva povrchu (listí, kůra) do barev vrcholů NEPATŘÍ – textura / uniform / INSTANCE_CUSTOM.
// INSTANCE_CUSTOM u stromů: rgb = odstín koruny, a = fenologický posun druhu (M8.11).

global uniform vec2 wind_dir;
global uniform float wind_speed;
global uniform sampler2D wind_gust;      // bez hintů (globální uniformy je nemusí podporovat) – opakování přes fract()
global uniform vec2 wind_offset;
global uniform float wind_time;
global uniform float wind_hier;

const float WIND_GUST_TILE = 1024.0;   // WindField.GUST_CELL × GUST_RES
const float WIND_F_REF = 400.0;        // v² pro „plnou“ sílu (20 m/s)

float wind_hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

// Náraz 0..1 (0,5 střed) ve světové poloze – shodně s WindField.gust_at.
float wind_gust_at(vec2 xz) {
	return textureLod(wind_gust, fract((xz - wind_offset) / WIND_GUST_TILE), 0.0).r;
}

// Hierarchický ohyb jednoho vrcholu. Vrací POSUN VE SVĚTOVÝCH METRECH (volající ho převede do lokálu).
//   vertex_local – vrchol relativně k patě rostliny, v metrech a ve světové orientaci (mat3(MODEL_MATRIX) * VERTEX)
//   origin_w     – pata rostliny ve světě
//   col          – barvy vrcholů podle konvence výše
//   height       – výška rostliny (m)
//   stiffness    – tuhost (1 = běžný strom; jehličnan ~1,3; keř ~2)
vec3 wind_bend(vec3 vertex_local, vec3 origin_w, vec4 col, float height, float stiffness) {
	float v = wind_speed;
	vec2 d = normalize(wind_dir + vec2(1e-4));
	float H = max(height, 0.5);
	float g = wind_gust_at(origin_w.xz);
	float vg = v * max(1.0 + 0.6 * (2.0 * g - 1.0), 0.05);   // okamžitá rychlost v koruně
	float F = vg * vg / WIND_F_REF;                          // síla ∝ v²
	float calm = clamp(v / 3.0, 0.0, 1.0);                   // za bezvětří klid
	float ph = wind_hash(floor(origin_w * 0.71) + 0.37) * 6.2831853;
	float h = clamp(vertex_local.y / H, 0.0, 1.3);

	// 1) kmen: statický průhyb po větru + pomalý kmit s vlastní frekvencí ∝ 1/H
	float f0 = clamp(5.0 / H, 0.12, 1.5);
	float sway = sin(6.2831853 * f0 * wind_time + ph);
	float trunk = h * h * H * (0.045 * F + 0.004 * calm) * (1.0 + 0.35 * sway) / stiffness;
	vec3 off = vec3(d.x, 0.0, d.y) * trunk;
	off += vec3(-d.y, 0.0, d.x) * h * h * H * (0.006 * F + 0.0015 * calm)
		* sin(6.2831853 * f0 * 0.77 * wind_time + ph * 1.3) / stiffness;
	off.y -= 0.5 * trunk * trunk / max(vertex_local.y, 0.3);  // délka kmene se zhruba zachová

	// 2) větve: ohebnost r, vlastní fáze g, rychlejší kmit
	float bph = col.g * 6.2831853 + ph;
	float fb = f0 * 2.7 + 0.6;
	float br = col.r * (0.12 * F + 0.012 * calm) * (0.55 + 0.9 * g) * sin(6.2831853 * fb * wind_time + bph);
	off += vec3(d.x * 0.8, 0.45, d.y * 0.8) * br;

	// 3) listy: třepetání (vysoká frekvence), amplituda podle nárazu
	float lf = col.b * (0.025 * F + 0.004 * calm) * (0.4 + 1.2 * g);
	off += vec3(sin(wind_time * 11.0 + bph * 7.0 + vertex_local.x * 3.0),
			sin(wind_time * 13.0 + bph * 5.0 + vertex_local.y * 3.0),
			cos(wind_time * 12.0 + bph * 3.0 + vertex_local.z * 3.0)) * lf;
	return off;
}

// Tráva a obilí: ohyb od kořene (h01²), náraz z pole + krátká vlna („honami“) běžící po větru.
// Vrací posun ve světových metrech; `plant_h` = výška stébla (m), `bend_k` = citlivost typu.
vec3 wind_grass(vec3 root_w, float h01, float plant_h, float bend_k) {
	float v = wind_speed;
	vec2 d = normalize(wind_dir + vec2(1e-4));
	float g = wind_gust_at(root_w.xz);
	float calm = clamp(v / 2.5, 0.0, 1.0);
	float along = dot(root_w.xz, d);
	// vlna po větru: délka ~7 m, běží rychlostí ~0,7 v (stébla se kloní za nárazem)
	float lam = 7.0;
	float wave = 0.5 + 0.5 * sin(6.2831853 * (along - wind_time * max(v, 0.5) * 0.7) / lam);
	float vg = v * max(1.0 + 0.7 * (2.0 * g - 1.0), 0.05) * (0.75 + 0.5 * wave);
	float F = vg * vg / WIND_F_REF;
	float ph = wind_hash(floor(root_w * 1.7) + 0.11) * 6.2831853;
	float flutter = sin(wind_time * (2.0 + 0.25 * v) + ph) * (0.03 + 0.06 * calm);
	float amp = h01 * h01 * plant_h * bend_k * (0.55 * clamp(F, 0.0, 1.6) + 0.04 * calm);
	vec3 off = vec3(d.x, 0.0, d.y) * amp;
	off += vec3(-d.y, 0.0, d.x) * h01 * h01 * plant_h * bend_k * flutter * calm;
	off.y -= 0.5 * amp * amp / max(plant_h * h01, 0.05);
	return off;
}
