// Vegetace (Fáze 9 – §9.4): trsy, kopřivy, keře, obilné řádky a plevel v MultiMeshích
// (VegetationManager). Modely z tools/gen_vegetation_meshes.gd – UV.y = poměrná výška
// vrcholu (0 patka, 1 špička), albedo v barvách vrcholů, INSTANCE_CUSTOM.rgb = tint
// instance a INSTANCE_CUSTOM.a = číslo pole / 255 (jen plodiny na orné půdě).
//
// Vítr: `wind_strength` + `wind_dir` nastavuje VegetationManager z Weather.wind_vector()
// (0..2). Fáze mávání = INSTANCE_ID + poloha instance – trsy se nevlní synchronně.
// Ohyb roste s UV.y² (patka stojí, špička mává). Směr větru se přepočítává do lokálního
// prostoru instance transponovanou bází (instance mají náhodnou rotaci kolem Y).
//
// Sezóny: `season_mode` 0 = bylina (tint podle globálního grass_green), 1 = keř (podle
// foliage zmenší a zhnědne), 2 = plodina (barva a růst z `field_lut` = ta samá tabulka
// 256×2, kterou Fields.lut_image dodává terénnímu shaderu – zralost i posklizňové
// strniště se drží skutečného pole). Sníh bělí špičky a vegetaci mírně shrnuje.
shader_type spatial;
render_mode cull_disabled, diffuse_burley;

uniform float wind_strength = 0.0;             // 0..2 (Weather.wind / 10)
uniform vec2 wind_dir = vec2(0.8, 0.5);        // světový směr větru (normalizovaný xz)
uniform float bend_k = 1.0;                    // citlivost typu na vítr (keř < tráva)
uniform int season_mode = 0;                   // 0 bylina, 1 keř, 2 plodina (field_lut)
uniform sampler2D field_lut : filter_nearest, repeat_disable;

global uniform float snow_cover;               // sníh na zemi 0..1 (Atmosphere)
global uniform float grass_green;              // svěžest trávy 0..1 (Seasons.GREEN)
global uniform float foliage;                  // olistění listnáčů 0..1 (Seasons.FOLIAGE)

varying vec3 v_col;
varying float v_snow;

void vertex() {
	vec3 tint = INSTANCE_CUSTOM.rgb;
	float grow = 1.0;
	vec3 org = MODEL_MATRIX[3].xyz;

	if (season_mode == 2 && INSTANCE_CUSTOM.a > 0.004) {
		// plodina: barva a stav pole z kalendáře (řádek 0 = barva+síla, řádek 1 = rýhy)
		float fid = floor(INSTANCE_CUSTOM.a * 255.0 + 0.5);
		vec2 fuv = vec2((fid + 0.5) / 256.0, 0.25);
		vec4 fc = texture(field_lut, fuv);
		vec4 fm = texture(field_lut, vec2(fuv.x, 0.75));
		float bare = clamp(fm.r * 1.3, 0.0, 1.0);          // rýhy = posečeno/zaoráno → strniště
		grow = mix(grow, 0.06, bare);
		tint *= mix(vec3(1.0), fc.rgb * 1.7 + vec3(0.12), 0.8);
	} else if (season_mode == 0) {
		tint *= mix(vec3(1.3, 1.15, 0.75), vec3(1.0), grass_green);   // zima/sucho → sláma
	} else if (season_mode == 1) {
		tint *= mix(vec3(1.0), vec3(0.75, 0.62, 0.45), (1.0 - foliage) * 0.55);  // keř zezelená
		grow *= 0.75 + 0.25 * foliage;                                //   a v zimě „spadne“ listí
	}

	VERTEX.y *= grow;
	float bend = UV.y * UV.y;
	float phase = float(INSTANCE_ID) * 0.618 + org.x * 0.37 + org.z * 0.53;
	float wave = sin(TIME * (1.3 + wind_strength) + phase)
		+ 0.4 * sin(TIME * 3.1 + phase * 1.7 + VERTEX.y * 4.0);
	vec2 wdir = normalize(wind_dir + vec2(0.001));
	vec3 off_w = vec3(wdir.x * (0.6 + 0.4 * wave) + sin(phase * 2.9) * 0.12,
		0.0,
		wdir.y * (0.6 + 0.4 * wave) + cos(phase * 2.3) * 0.12);
	// do lokálního prostoru instance (transponovaná báze = inverze rotace; měřítko vyňato)
	float sc = max(length(MODEL_MATRIX[0].xyz), 0.001);
	vec3 off = transpose(mat3(MODEL_MATRIX)) * off_w / sc;
	VERTEX += off * (bend * bend_k * (0.15 + wind_strength * 0.13));

	v_col = COLOR.rgb * tint;
	v_snow = snow_cover * smoothstep(0.15, 0.9, UV.y + NORMAL.y * 0.4);
}

void fragment() {
	vec3 c = v_col;
	c = mix(c, vec3(0.85, 0.87, 0.92), clamp(v_snow * 0.85, 0.0, 0.8));
	ALBEDO = c;
	ROUGHNESS = 0.85;
	SPECULAR = 0.3;
	BACKLIGHT = c * 0.3;                            // prosycení proti světlu (listy/tráva)
}
