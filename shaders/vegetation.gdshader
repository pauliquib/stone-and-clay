// Vegetace (Fáze 9 – §9.4): trsy, kopřivy, keře, obilné řádky a plevel v MultiMeshích
// (VegetationManager). Modely z tools/gen_vegetation_meshes.gd – UV.y = poměrná výška
// vrcholu (0 patka, 1 špička), albedo v barvách vrcholů, INSTANCE_CUSTOM.rgb = tint
// instance a INSTANCE_CUSTOM.a = číslo pole / 255 (jen plodiny na orné půdě).
//
// Vítr (M8.4): `wind_grass` z include/wind.gdshaderinc – ohyb od kořene ∝ v², náraz z globální textury
// `wind_gust` (stejné pole jako WindField) a krátká vlna běžící po větru. Stará cesta (wind_hier = 0):
// `wind_strength` (VegetationManager, 0..2) + globální `wind_dir`. Fáze mávání = INSTANCE_ID + poloha instance – trsy se nevlní synchronně.
// Ohyb roste s UV.y² (patka stojí, špička mává). Směr větru se přepočítává do lokálního
// prostoru instance transponovanou bází (instance mají náhodnou rotaci kolem Y).
//
// Sezóny: `season_mode` 0 = bylina (tint podle globálního grass_green), 1 = keř (podle
// foliage zmenší a zhnědne), 2 = plodina (barva a růst z `field_lut` = ta samá tabulka
// 256×2, kterou Fields.lut_image dodává terénnímu shaderu – zralost i posklizňové
// strniště se drží skutečného pole). Sníh bělí špičky a vegetaci mírně shrnuje.
//
// M8.14 Přízemní vegetace (include/ground_veg.gdshaderinc, globální vstupy plní Meadows / Footpaths / GroundVegFx):
//   * `veg_color_mode` 1 = nové typy podle konvence barev vrcholů (00_PRINCIPY kap. 4: r ohebnost, g fáze, b list,
//     a okluze) – albedo z uniformů `veg_lo` → `veg_hi` po výšce (UV.y), `veg_acc` pro květ / bobule (UV.x > 0,5);
//     0 = staré modely (albedo v barvách vrcholů).
//   * `season_mode` 3 = jarní efemér (sasanky, dymnivky – kvetou před olistěním), 4 = beze změny (hrabanka, mech).
//   * `veg_mow` – výška podle porostu louky (`meadow_h`: po seči nízká a zelenější), `veg_path` – na pěšině nižší
//     a řidší, `veg_trample` – ohyb od hráče / NPC / zvířat / kol (sešlapání kolem kamery).
//
// Vzhled 2026-10 (realistická přízemní vegetace, GroundVegMeshes):
//   * druh plochy v UV.x (osminy): 0 kulatý list, 1 karta trsu listí, 2 plné stéblo / list, 3 list kapradí,
//     4 / 5 květ shora / z boku, 6 plný akcent, 7 hrabanka. Výřezy (listy po buňkách, lístky kapradí, okvětí) se
//     počítají z UV2 procedurálně – žádná textura; stébla jsou geometrie (bez alfa testu).
//   * plynulé mizení do dálky (`veg_fade_end`, nastavuje VegetationManager = dosah chunku − rezerva): každá instance
//     má podle hashe vlastní mez 0,6–1 × dosah a před ní se zmenší do bodu → hustota řídne plynule, chunk se zapne
//     dřív, než jeho instance „vyrostou“ (žádný pop-in po 64 m). Vzdálenost od HLAVNÍ kamery (i ve stínovém průchodu).
//   * barevná variace po instancích (hash polohy) a po stéblech (fáze v COLOR.g: část stébel zasychá),
//     keře na podzim barví listy po jednom a v zimě je shazují (`v_keep`), kapradí na podzim zrezaví.
//   * měkké normály z modelu (ven z trsu), rub plochy má stejnou normálu jako líc, prosvítání BACKLIGHT podle druhu.
//   * `veg_inst_acc` = 1: barva květu z INSTANCE_CUSTOM.rgb a tvar okvětí z INSTANCE_CUSTOM.a (MeadowFlowers).
shader_type spatial;
render_mode cull_disabled, diffuse_burley;

uniform float wind_strength = 0.0;             // 0..2 (Weather.wind / 10) – stará cesta (wind_hier = 0)
// M8.4: směr větru je globální `wind_dir` (include/wind.gdshaderinc, nastavuje Atmosphere z World.wind_field)
uniform float bend_k = 1.0;                    // citlivost typu na vítr (keř < tráva)
uniform int season_mode = 0;                   // 0 bylina, 1 keř, 2 plodina (field_lut)
uniform sampler2D field_lut : filter_nearest, repeat_disable;
uniform int veg_color_mode = 0;                // M8.14: 0 albedo v barvách vrcholů, 1 konvence kap. 4 + barvy z uniformů
uniform vec3 veg_lo : source_color = vec3(0.2, 0.35, 0.1);    // M8.14: barva u patky
uniform vec3 veg_hi : source_color = vec3(0.4, 0.55, 0.2);    // M8.14: barva špičky
uniform vec3 veg_acc : source_color = vec3(0.6, 0.3, 0.7);    // M8.14: květ / bobule (UV.x > 0,5)
uniform float veg_mow = 0.0;                   // M8.14: 1 = výška podle seče louky (meadow_h)
uniform float veg_path = 0.0;                  // M8.14: 1 = pěšina sníží a proředí
uniform float veg_trample = 0.0;               // M8.14: citlivost na sešlapání (0 = nehýbe se)
uniform float veg_fade_end = 0.0;              // m – dosah, za kterým instance zmizí (0 = bez plynulého mizení)
uniform float veg_inst_acc = 0.0;              // 1 = barva květu z INSTANCE_CUSTOM.rgb, typ okvětí z .a (louční květy)
uniform float veg_petal = 0.0;                 // typ okvětí: 0 kopretina, 1 pryskyřník, 2 úbor (chrpa, pcháč), 3 pětičetný

global uniform float snow_cover;               // sníh na zemi 0..1 (Atmosphere)
global uniform float grass_green;              // svěžest trávy 0..1 (Seasons.GREEN)
global uniform float foliage;                  // olistění listnáčů 0..1 (Seasons.FOLIAGE)
global uniform float autumn;                   // podzim 0..1 (Seasons.autumn) – M8.14 jarní efeméry v létě a na podzim nejsou
global uniform float micro_dew;                // M8.9: rosa 0..1 (Microclimate → MicroFx)
global uniform float micro_frost;              // M8.9: 1 = rosa na dně údolí zmrzlá (jinovatka)
global uniform float micro_frost_y;            // M8.9: svět Y, pod kterým je zem zmrzlá

#include "res://shaders/include/wind.gdshaderinc"
#include "res://shaders/include/ground_veg.gdshaderinc"

const float LITTER_REP = 5.0;                  // = GroundVegMeshes.LITTER_REP (UV2 hrabanky = souřadnice × LITTER_REP)

varying vec3 v_col;
varying float v_snow;
varying float v_dew;                           // M8.9: rosa (lesk)
varying float v_rime;                          // M8.9: jinovatka (bělavé špičky)
varying vec3 v_acc;                            // barva květu / bobule / klasu
varying float v_keep;                          // podíl listů, které drží (keře v zimě opadají)
varying float v_aut;                           // podzimní zbarvení listů 0..1
varying float v_ptype;                         // typ okvětí

float veg_h2(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

// Listy po buňkách (3 posunuté mřížky, v každé buňce jeden natočený oválný list celý uvnitř buňky – bez hledání
// sousedů). `mask_r` > 0: listy se středem dál od středu karty vypadnou celé (kulatý obrys trsu, ne useknuté listy).
// Vrací x = 1 uvnitř listu, y = hash listu, z = vzdálenost od žilky 0..1, w = poloha podél listu −1..1.
vec4 veg_leaves(vec2 p, float seed, float mask_r) {
	vec4 res = vec4(0.0, 0.0, 1.0, 0.0);
	for (int g = 0; g < 3; g++) {
		float fg = float(g);
		vec2 off = vec2(fg * 0.5, fg * 0.37 + fg * fg * 0.11);
		vec2 q = p * 3.5 + off;
		vec2 id = floor(q);
		float h = veg_h2(id + vec2(fg * 17.3 + seed * 41.0, seed * 13.0));
		vec2 o = vec2(veg_h2(id + 3.1 + fg), veg_h2(id + 7.7 - fg)) - 0.5;
		vec2 ctr = id + 0.5 + o * 0.16;
		if (mask_r > 0.0 && length((ctr - off) / 3.5 - 0.5) > mask_r + 0.08 * h) {
			continue;
		}
		vec2 r = q - ctr;
		float a = h * 6.2831853;
		float ca = cos(a);
		float sa = sin(a);
		r = vec2(ca * r.x - sa * r.y, sa * r.x + ca * r.y);
		float len = 0.36 + 0.06 * h;
		float y = r.y / len;
		float lw = 0.42 * len * sqrt(max(1.0 - y * y, 0.0)) * (1.0 - 0.3 * y);
		if (abs(y) < 1.0 && abs(r.x) < lw) {
			res = vec4(1.0, h, abs(r.x) / max(lw, 1e-3), y);
		}
	}
	return res;
}

// Okvětí květu: `side` = karta z boku. Vrací, zda pixel patří květu; `cen` = 1 v terči (střed květu).
bool veg_flower(vec2 p, bool side, float pt, out float cen) {
	vec2 q = p * 2.0 - 1.0;
	cen = 0.0;
	if (side) {
		float xx = q.x * q.x;
		if (xx >= 1.0) {
			return false;
		}
		if (pt > 1.5 && pt < 2.5) {                     // úbor: kulatý třásnitý chomáč
			vec2 d = q - vec2(0.0, 0.1);
			return length(d) < 0.6 + 0.14 * abs(sin(atan(d.x, d.y) * 9.0));
		}
		float yc = -0.05 + 0.25 * xx;                    // lístky se zvedají do misky
		float hh = 0.2 * sqrt(1.0 - xx) + 0.06 * abs(sin(q.x * 17.0));
		float cr = pt < 0.5 ? 0.34 : 0.24;
		float cx = q.x / cr;
		bool cb = cx * cx < 1.0 && q.y > yc - 0.05 && q.y < yc + 0.06 + 0.22 * sqrt(max(1.0 - cx * cx, 0.0));
		cen = cb ? 1.0 : 0.0;
		return cb || abs(q.y - yc) < hh;
	}
	float r = length(q);
	float a = atan(q.y, q.x);
	float pr;
	float cr;
	if (pt < 0.5) {                                      // kopretina: 14 úzkých lístků, žlutý terč
		pr = 0.4 + 0.58 * pow(abs(cos(a * 7.0)), 0.5);
		cr = 0.3;
	} else if (pt < 1.5) {                               // pryskyřník: 5 kulatých lístků
		pr = 0.58 + 0.4 * pow(abs(cos(a * 2.5)), 0.6);
		cr = 0.2;
	} else if (pt < 2.5) {                               // úbor (chrpa, jetel, pcháč): třásně
		pr = 0.68 + 0.3 * pow(abs(sin(a * 9.0)), 0.3);
		cr = 0.0;
	} else {                                             // pětičetný s vykrojenými lístky (kohoutek, sasanka)
		float pc = abs(cos(a * 2.5));
		pr = 0.48 + 0.5 * pow(pc, 0.8) - 0.22 * pow(pc, 40.0);
		cr = 0.15;
	}
	if (r > pr) {
		return false;
	}
	cen = cr > 0.0 ? 1.0 - smoothstep(cr - 0.04, cr, r) : 0.0;
	return true;
}

void vertex() {
	vec3 tint = INSTANCE_CUSTOM.rgb;
	float grow = 1.0;
	vec3 org = MODEL_MATRIX[3].xyz;
	vec3 cam_w = MAIN_CAM_INV_VIEW_MATRIX[3].xyz;            // i ve stínovém průchodu podle hlavní kamery
	float ih = wind_hash(org * 1.37 + vec3(0.31, 0.17, 0.53));   // hash instance (variace, mez mizení)
	v_acc = veg_acc;
	v_ptype = veg_petal;
	v_keep = 1.0;
	v_aut = 0.0;
	if (veg_inst_acc > 0.5) {
		v_acc = INSTANCE_CUSTOM.rgb;                          // louční květ: barva a typ okvětí z instance
		v_ptype = floor(INSTANCE_CUSTOM.a * 4.0 + 0.01);
		tint = vec3(1.0);
	}

	if (season_mode == 2 && INSTANCE_CUSTOM.a > 0.004) {
		// plodina: barva a stav pole z kalendáře (řádek 0 = barva+síla, řádek 1 = rýhy)
		float fid = floor(INSTANCE_CUSTOM.a * 255.0 + 0.5);
		vec2 fuv = vec2((fid + 0.5) / 256.0, 0.25);
		vec4 fc = texture(field_lut, fuv);
		vec4 fm = texture(field_lut, vec2(fuv.x, 0.75));
		float bare = clamp(fm.r * 1.3, 0.0, 1.0);          // rýhy = posečeno/zaoráno → strniště
		grow = mix(grow, 0.06, bare);
		grow *= 1.0 - fm.b;                                  // M8.12: zakrslé obilí (sucho, slabý vzrůst – Fields._short_of)
		tint *= mix(vec3(1.0), fc.rgb * 1.7 + vec3(0.12), 0.8);
	} else if (season_mode == 0) {
		tint *= mix(vec3(1.3, 1.15, 0.75), vec3(1.0), grass_green);   // zima/sucho → sláma
	} else if (season_mode == 1) {
		tint *= mix(vec3(1.0), vec3(0.75, 0.62, 0.45), (1.0 - foliage) * 0.55);  // keř zezelená
		grow *= 0.75 + 0.25 * foliage;                                //   a v zimě „spadne“ listí
		v_keep = clamp(foliage * 1.1 + 0.06, 0.0, 1.0);               // karty listí: opad po jednotlivých listech
		v_aut = autumn;
	} else if (season_mode == 3) {
		// M8.14 jarní efemér: vidět jen mezi táním a olistěním korun (zelená tráva, holé koruny, ne podzim)
		grow *= clamp(grass_green * (1.0 - foliage) * (1.0 - autumn) * 2.5, 0.0, 1.0);
	}
	// M8.14: louka po seči / pastvě nízká (a svěže zelená), na pěšině nižší a řidší
	if (veg_mow > 0.0) {
		float mrel = gv_meadow_rel(org.xz);
		grow *= mix(1.0, max(mrel, 0.06), veg_mow);
		tint *= mix(vec3(0.9, 1.1, 0.88), vec3(1.0), clamp(mrel * 1.6, 0.0, 1.0));
	}
	if (veg_path > 0.0) {
		float pw = gv_path_wear(org.xz) * veg_path;
		if (pw > 0.003) {
			grow *= 1.0 - 0.7 * clamp(pw, 0.0, 1.0);
			if (wind_hash(org * 1.37 + 0.5) < pw * 0.85) {
				grow = 0.0;                                  // proředění: trs na pěšině chybí
			}
		}
	}
	// plynulé mizení do dálky: každá instance má vlastní mez (0,6–1 × dosah) a před ní se zmenší do bodu
	float fade = 1.0;
	if (veg_fade_end > 0.0) {
		float lim = veg_fade_end * mix(0.6, 1.0, ih);
		fade = 1.0 - smoothstep(lim * 0.8, lim, distance(cam_w, org));
	}

	VERTEX.y *= grow;
	VERTEX *= fade;
	if (grow <= 0.0 || fade <= 0.0) {
		VERTEX = vec3(0.0);                                  // zhroucená instance se nevykreslí
	}
	float sc = max(length(MODEL_MATRIX[0].xyz), 0.001);
	float flex = veg_color_mode == 1 ? COLOR.r : UV.y;      // M8.14: ohebnost z barvy vrcholu (kap. 4)
	if (wind_hier > 0.5) {
		// M8.4: ohyb od kořene, náraz z pole větru a vlna po větru (přes obilí běží viditelné vlny)
		float plant_h = max(VERTEX.y * sc / max(UV.y, 0.1), 0.1);
		vec3 off_m = wind_grass(org, flex, plant_h, bend_k);
		VERTEX += transpose(mat3(MODEL_MATRIX)) * off_m / (sc * sc);
	} else {
	float bend = UV.y * UV.y;
	float phase = float(INSTANCE_ID) * 0.618 + org.x * 0.37 + org.z * 0.53;
	float wave = sin(TIME * (1.3 + wind_strength) + phase)
		+ 0.4 * sin(TIME * 3.1 + phase * 1.7 + VERTEX.y * 4.0);
	vec2 wdir = normalize(wind_dir + vec2(0.001));
	vec3 off_w = vec3(wdir.x * (0.6 + 0.4 * wave) + sin(phase * 2.9) * 0.12,
		0.0,
		wdir.y * (0.6 + 0.4 * wave) + cos(phase * 2.3) * 0.12);
	// do lokálního prostoru instance (transponovaná báze = inverze rotace; měřítko vyňato)
	vec3 off = transpose(mat3(MODEL_MATRIX)) * off_w / sc;
	VERTEX += off * (bend * bend_k * (0.15 + wind_strength * 0.13)) * fade;
	}
	// M8.14: sešlapání – rostlina se sklopí od hráče / NPC / zvířat / kol a pomalu narovná (síla zdroje klesá)
	if (veg_trample > 0.0 && grow > 0.0) {
		vec3 off_t = gv_trample(org, max(VERTEX.y, 0.0) * sc, veg_trample * flex, cam_w);
		VERTEX += transpose(mat3(MODEL_MATRIX)) * off_t / (sc * sc);
	}

	if (veg_color_mode == 1) {
		float occ = 0.55 + 0.45 * COLOR.a;
		if (UV.x > 0.5 && UV.x < 0.875) {                   // akcent (květ, bobule, klas); 7 = hrabanka je list
			v_col = v_acc * occ * tint;
		} else {
			vec3 base = mix(veg_lo, veg_hi, clamp(UV.y, 0.0, 1.0));
			// variace instance (odstín a jas) a stébel (část zasychá – víc v suchu a v zimě)
			base *= mix(vec3(1.06, 1.03, 0.86), vec3(0.92, 1.0, 1.06), ih) * (0.88 + 0.24 * fract(ih * 7.13));
			if (season_mode == 0) {
				float dry = step(fract(COLOR.g * 3.7 + ih), 0.05 + 0.45 * (1.0 - grass_green));
				base = mix(base, vec3(0.46, 0.41, 0.24) * (0.55 + 0.45 * UV.y), dry * 0.7);
			}
			v_col = base * occ * tint;
		}
	} else {
		v_col = COLOR.rgb * tint;
	}
	// sníh drží na plochách obrácených nahoru (listy, trs shora), na svislých stonkách jen málo
	v_snow = snow_cover * smoothstep(0.15, 0.9, UV.y + NORMAL.y * 0.4) * clamp(NORMAL.y * 1.3 - 0.15, 0.2, 1.0);
	float rime_k = micro_dew * micro_frost * smoothstep(micro_frost_y + 8.0, micro_frost_y - 8.0, org.y);
	v_rime = rime_k * smoothstep(0.2, 0.9, UV.y) * (1.0 - snow_cover);
	v_dew = max(micro_dew - rime_k, 0.0) * (1.0 - snow_cover);
}

void fragment() {
	vec3 c = v_col;
	float bl = 0.3;                                  // prosvítání proti světlu
	float rough = 0.85;
	if (veg_color_mode == 1) {
		float kind = floor(UV.x * 8.0);
		vec2 p = UV2;
		if (!FRONT_FACING) {
			NORMAL = -NORMAL;                        // rub plochy: stejná měkká normála jako líc (ven z trsu)
		}
		if (kind < 0.5) {                            // kulatý list (devětsil): zubatý okraj, výkroj u řapíku, žilky
			vec2 q = p * 2.0 - 1.0;
			float r = length(q);
			float a = atan(q.x, q.y);
			bool notch = q.y < 0.0 && abs(q.x) < -q.y * 0.25 && r > 0.1;
			if (r > 0.97 - 0.06 * pow(abs(sin(a * 9.0)), 2.0) || notch) {
				discard;
			}
			float vein = 1.0 - 0.14 * (1.0 - smoothstep(0.0, 0.08, abs(sin(a * 3.5)))) * step(0.12, r);
			c *= vein * (0.82 + 0.28 * r);
			bl = 0.45;
		} else if (kind < 1.5) {                     // trs listí (keře, borůvčí, zahrádky)
			vec4 lf = veg_leaves(p, COLOR.g, 0.42);
			if (lf.x < 0.5 || fract(lf.y * 13.7) > v_keep) {
				discard;
			}
			c *= (0.78 + 0.4 * lf.y) * mix(0.8, 1.0, smoothstep(0.0, 0.14, lf.z)) * (0.92 + 0.08 * lf.w);
			c *= mix(vec3(1.0), vec3(1.12, 1.1, 0.78), step(0.82, fract(lf.y * 5.3)) * 0.6);   // mladé světlé listy
			if (fract(lf.y * 7.3) < v_aut * 1.1) {       // podzim: listy se barví po jednom
				vec3 ac = mix(vec3(0.78, 0.6, 0.12), vec3(0.6, 0.24, 0.07), fract(lf.y * 3.1));
				c = ac * (0.5 + 0.5 * COLOR.a) * (0.8 + 0.3 * lf.y);
			}
			// každý list trochu jinak natočený → třpyt a hloubka v keři
			NORMAL = normalize(NORMAL + vec3(fract(lf.y * 3.7) - 0.5, fract(lf.y * 9.1) - 0.5, 0.0) * 0.7);
			bl = 0.45;
		} else if (kind < 2.5) {                     // stéblo / list (geometrie): světlejší žilka, zasychající špička
			c *= 0.9 + 0.12 * (1.0 - abs(p.x * 2.0 - 1.0));
			c = mix(c, c * vec3(1.18, 1.08, 0.72), smoothstep(0.7, 1.0, p.y) * 0.35);
			bl = 0.4;
		} else if (kind < 3.5) {                     // list kapradí: obrys listu, šikmé lístky, vřeteno
			float s = abs(p.x - 0.5) * 2.0;
			float y = clamp(p.y, 0.0, 1.0);
			float env = pow(sin(3.14159 * y), 0.6) * (1.0 - 0.35 * y);
			float t = fract(y * 15.0 + s * 1.3);
			bool rach = s < 0.045 && y < 0.97;
			if (!rach && (s > env || abs(t - 0.5) > 0.44 * (1.0 - 0.6 * s))) {
				discard;
			}
			c *= rach ? 0.75 : (0.85 + 0.3 * s);
			float dead = max(v_aut, 1.0 - v_keep);      // na podzim zrezaví, v zimě suché
			c = mix(c, vec3(0.42, 0.24, 0.1) * (0.8 + 0.3 * s), clamp(dead * 1.2 - COLOR.g * 0.3, 0.0, 1.0));
			bl = 0.5;
		} else if (kind < 5.5) {                     // květ (shora / z boku)
			float cen;
			if (!veg_flower(p, kind > 4.5, v_ptype, cen)) {
				discard;
			}
			vec3 cc = v_ptype < 0.5 ? vec3(0.95, 0.72, 0.1) : (v_ptype < 1.5 ? vec3(0.8, 0.55, 0.06) : c * 0.6);
			c *= 0.82 + 0.18 * length(p * 2.0 - 1.0);
			c = mix(c, cc * (0.6 + 0.4 * COLOR.a), cen);
			bl = 0.55;
			rough = (v_ptype > 0.5 && v_ptype < 1.5) ? 0.35 : 0.7;   // pryskyřník se leskne
		} else if (kind > 6.5) {                     // hrabanka: jednotlivé listy, mezi nimi tmavší zem, roztřepený okraj
			vec4 lf = veg_leaves(p, COLOR.g, 0.0);
			float rr = length(p / LITTER_REP - 0.5) * 2.0;
			if (lf.x < 0.5) {
				if (rr > 0.55) {
					discard;
				}
				c *= 0.55;
			} else {
				if (rr > 0.97 - 0.3 * lf.y) {
					discard;
				}
				c *= (0.75 + 0.45 * lf.y) * mix(vec3(1.0), vec3(1.12, 0.95, 0.78), fract(lf.y * 5.3));
			}
			bl = 0.0;
		}
	}
	c = mix(c, vec3(0.85, 0.87, 0.92), clamp(v_snow * 0.85, 0.0, 0.8));
	c = mix(c, vec3(0.82, 0.86, 0.9), clamp(v_rime * 0.6, 0.0, 0.6));   // M8.9 jinovatka
	ALBEDO = c;
	ROUGHNESS = mix(rough, 0.4, v_dew);              // M8.9: orosená tráva se leskne
	SPECULAR = mix(0.3, 0.55, v_dew);
	BACKLIGHT = c * bl;                              // prosycení proti světlu (listy/tráva)
}
