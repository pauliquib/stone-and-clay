// Společné tělo hladiny potoků, řeky a rybníků (Water). Varianty:
//   water.gdshader     – Nízká / Střední: hladina se míchá s pozadím přes ALPHA (jen hloubkový buffer), 3 čtení textur.
//   water_hq.gdshader  – Vysoká / Ultra (#define WATER_HQ): lom světla ze screen texture, Beer-Lambert po kanálech,
//                        odraz břehů a stromů (krátký pochod paprsku v hloubkovém bufferu), kapky deště, poryvy větru.
// Water přepíná shader podle globálního `gfx_quality` – screen texture stojí kopii obrazu za snímek, proto v levné
// variantě vůbec není (větvení podle uniformu by kopii nevypnulo).
//
// Mesh (Water._ribbon): UV = metry (x po proudu, y napříč od osy), UV2 = (polovina šířky m, násobek rychlosti
// proudu ze sklonu hladiny), TANGENT = směr toku, COLOR.a = doznění volného konce pásu (pramen, soutok).
// Rybník: UV = světové x, z, UV2 = 0, TANGENT = +X, COLOR = bílá.
// Odraz oblohy (Fresnel, odlesky slunce) dává engine z radiance oblohy (`reflected_light_source = SKY`) přes SPECULAR
// a nízkou ROUGHNESS; SSR enginu průhledné plochy nezasahuje, proto odraz okolí počítá HQ varianta sama. Obě varianty
// tlumí odraz oblohy pod „obzorem“ břehů (okluze obzoru: koryto, olše na březích, linie stromů za rybníkem) a místo
// něj dají tmavý olivový odraz okolí – HQ jen tam, kde pochod paprskem nic netrefí.
// M8.7: per-úsek (instance uniform, nastavuje Water z vodní bilance): posun hladiny `level_ofs` (m),
// kalnost po přívalu `turbid` 0..1 a násobek rychlosti proudu `flow_mult`. Rybníky mají výchozí hodnoty.

// vlnová textura (Water._wave_texture): RG = sklon výškového pole (normalizovaný, RMS 1, kódovaný 0,5 ± s/6),
// B = výška šumu 0..1 (pěna, led), A = druhý nezávislý šum (sníh na ledu)
#ifdef WATER_HQ
uniform sampler2D wave_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear;
#else
uniform sampler2D wave_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
#endif
uniform sampler2D depth_tex : hint_depth_texture, repeat_disable, filter_nearest;
uniform vec3 shallow_color : source_color = vec3(0.30, 0.32, 0.20);   // tenká vrstva (levná varianta)
uniform vec3 deep_color : source_color = vec3(0.13, 0.14, 0.08);      // rozptyl v hloubce (hnědozelená)
uniform vec3 absorb = vec3(1.2, 0.9, 1.6);   // útlum 1/m po kanálech (R, G, B) – zakalená voda, viditelnost ~1 m
uniform float flow_speed = 0.6;      // m/s po proudu (rybník 0)
uniform float ice = 0.0;             // 0 voda … 1 zamrzlé
uniform float snow = 0.0;            // sníh na ledu
uniform float wave_scale = 1.0;      // větší vlnky v dešti / větru
uniform float rain = 0.0;            // déšť 0..1 (kapky na hladině, HQ)
uniform vec3 mud_color : source_color = vec3(0.36, 0.28, 0.17);   // M8.7: kalná voda po přívalu
instance uniform float level_ofs = 0.0;   // M8.7: m vůči normální hladině (max ±0,4)
instance uniform float turbid = 0.0;      // M8.7: kalnost 0..1
instance uniform float flow_mult = 1.0;   // M8.7: × rychlost proudu podle průtoku

global uniform vec2 wind_dir;        // kam fouká (svět xz) – vlnky na rybníce
global uniform float wind_speed;
global uniform vec2 wind_offset;     // m, posun pole nárazů (WindField, modulo 1 024 m) – unáší vlnky na rybníce
#ifdef WATER_HQ
global uniform float gfx_quality;
global uniform sampler2D wind_gust;  // chuchvalce nárazů (WindField) – tmavší zčeřené plochy na rybníce
#endif

varying vec3 world_pos;
varying vec3 v_flow_dir;             // svět: směr toku (u rybníka +X)
varying vec2 v_info;                 // UV2: polovina šířky toku (0 = rybník), násobek rychlosti ze sklonu
varying float v_fade;                // COLOR.a: doznění konce pásu toku

const vec3 FOAM_COLOR = vec3(0.70, 0.70, 0.64);   // špinavě bílá pěna
const float WATER_SPEC = 0.35;                     // F0 ≈ 0,02 (0,16 · 0,35²)
const vec3 BANK_REFL = vec3(0.050, 0.064, 0.034);  // odraz břehů, rákosu a olší (osvětlí ho slunce jako ALBEDO)
const float POND_DRIFT = 0.05;                     // vlnky na rybníce: × posun nárazů větru (5 m/s → 0,25 m/s)

void vertex() {
	VERTEX.y += level_ofs;
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 tg = (MODEL_MATRIX * vec4(TANGENT, 0.0)).xyz;
	tg.y = 0.0;
	v_flow_dir = dot(tg, tg) > 1e-6 ? normalize(tg) : vec3(1.0, 0.0, 0.0);
	v_info = UV2;
	v_fade = COLOR.a;
}

// Sklon dvou vrstev vlnek (tečný prostor: x po proudu, y napříč); `wl_ofs` = posun proudem (m), `wl_sa`, `wl_sb` =
// měřítko vrstev (1/m; potok: podél proudu delší čeřiny). Šum (B) druhé vrstvy → `wl_n` (pěna), první → `wl_n1`.
vec2 water_layers(vec2 wl_p, vec2 wl_ofs, vec2 wl_sa, vec2 wl_sb, out float wl_n, out float wl_n1) {
	vec4 a = texture(wave_tex, (wl_p - wl_ofs) * wl_sa);
	vec4 b = texture(wave_tex, (wl_p - wl_ofs * 1.25) * wl_sb + vec2(0.37, 0.61));
	wl_n = b.b;
	wl_n1 = a.b;
	return (a.rg * 2.0 - 1.0) * 2.6 + (b.rg * 2.0 - 1.0) * 1.5;
}

// Výška „obzoru“ okolí (sinus sklonu) ve směru odraženého paprsku: kde paprsek míří níž, odráží břeh, ne oblohu.
// Potok v zářezu: napříč korytem blízký břeh vysoko, po proudu dál a níž; u břehu výš (olše nad vodou).
// Rybník: linie stromů za hladinou – nízká, nepravidelná podle azimutu (jen ALU, žádné čtení textury).
float water_horizon(vec3 wh_rd, vec3 wh_tan, float wh_edge, bool wh_flow) {
	vec2 d = normalize(wh_rd.xz + vec2(1e-5));
	float az = atan(d.y, d.x);
	float line = 0.5 + 0.22 * sin(az * 3.0 + 1.3) + 0.16 * sin(az * 7.0 + 0.4) + 0.12 * sin(az * 17.0 + 2.1);
	if (wh_flow) {
		float across = abs(dot(d, vec2(-wh_tan.z, wh_tan.x)));
		return mix(0.03, 0.24, across * across) + 0.10 * (1.0 - wh_edge) + 0.06 * line;
	}
	return 0.015 + 0.075 * line;
}

#ifdef WATER_HQ
float water_hash(vec2 wh_p) {
	return fract(sin(dot(wh_p, vec2(127.1, 311.7))) * 43758.5453);
}

// Kroužky od dešťových kapek v jedné mřížce (buňka `wr_cell` m): sklon xy. Kapka dopadne v náhodném místě buňky,
// kroužek se rozbíhá a slábne; hustota `wr_dens` = podíl buněk, kde v tomto cyklu kápne.
vec2 water_ripples(vec2 wr_p, float wr_t, float wr_cell, float wr_dens) {
	vec2 q = wr_p / wr_cell;
	vec2 c = floor(q);
	vec2 f = fract(q);
	float h = water_hash(c);
	float ph = fract(wr_t * 0.9 + h);
	float cyc = floor(wr_t * 0.9 + h);
	if (water_hash(c + cyc * 7.31) > wr_dens) {
		return vec2(0.0);
	}
	vec2 ctr = 0.5 + (vec2(water_hash(c + 3.7 + cyc), water_hash(c + 9.1 - cyc)) - 0.5) * 0.4;
	vec2 dv = f - ctr;
	float d = length(dv);
	float r = ph * 0.32;
	float x = (d - r) * 40.0;
	float ring = sin(x * 3.0) * exp(-x * x) * (1.0 - ph) * (1.0 - ph);
	return dv / max(d, 1e-4) * ring;
}
#endif

void fragment() {
	float t = TIME;
	vec2 p = UV;
	bool flowing = flow_speed > 0.01;
	vec3 up_w = vec3(0.0, 1.0, 0.0);
	vec3 tan_w = v_flow_dir;
	vec3 bin_w = vec3(-tan_w.z, 0.0, tan_w.x);
	float fs = flow_speed * flow_mult;
	float smul = flowing ? clamp(v_info.y, 0.4, 2.5) : 0.0;   // rychlejší v peřejích, pomalejší v tůních
	float halfw = max(v_info.x, 0.01);
	float edge = flowing ? clamp(1.0 - abs(p.y) / halfw, 0.0, 1.0) : 1.0;   // 0 u břehu, 1 v ose toku
	float icy = ice;

	// --- vlnky: potok – čeřiny protažené po proudu, unášené proudem; rybník – drobné vlnky od větru, unášené
	// posunem nárazů (`wind_offset`, plynulý i při změně rychlosti větru; měřítka 1/6,4 a 1/3,2 m dělí skok
	// modula 1 024 m · POND_DRIFT beze švu), čeřené kolmo na vítr silněji než podél
	vec2 wdir = normalize(wind_dir + vec2(0.0001, 0.0));
	vec2 vel = vec2(fs, 0.0);
	vec2 pofs = wind_offset * POND_DRIFT;
	vec2 sc_a = flowing ? vec2(0.11, 0.30) : vec2(0.15625);
	vec2 sc_b = flowing ? vec2(0.32, 0.70) : vec2(0.3125);
	float n_foam;
	float n_big;
	vec2 slope;
#ifdef WATER_HQ
	if (flowing) {
		// dvoufázový flow-map: rychlost se mění po proudu (sklon) i napříč (u břehu pomaleji) bez trhání textury
		vec2 vloc = vel * smul * mix(0.55, 1.15, sqrt(edge));
		float cyc_len = 1.6;
		float ph0 = fract(t / cyc_len);
		float ph1 = fract(t / cyc_len + 0.5);
		float w0 = 1.0 - abs(1.0 - 2.0 * ph0);
		float fa;
		float fb;
		float ga;
		float gb;
		vec2 s0 = water_layers(p, vloc * cyc_len * ph0, sc_a, sc_b, fa, ga);
		vec2 s1 = water_layers(p + vec2(1.73, 0.91), vloc * cyc_len * ph1, sc_a, sc_b, fb, gb);
		slope = (s0 * w0 + s1 * (1.0 - w0)) / sqrt(w0 * w0 + (1.0 - w0) * (1.0 - w0));
		n_foam = mix(fb, fa, w0);
		n_big = mix(gb, ga, w0);
		// jemné čeřiny po proudu (rychlejší než velké vlnky)
		vec2 det = texture(wave_tex, (p - vel * smul * t * 1.4) * vec2(0.9, 1.6) + vec2(0.13, 0.77)).rg * 2.0 - 1.0;
		slope += det * 0.8 / (1.0 + length(VERTEX) * 0.08);   // v dálce by drobné čeřiny jen jiskřily
	} else {
		slope = water_layers(p, pofs, sc_a, sc_b, n_foam, n_big);
		// jemné vlnky od větru (perioda 0,8 m: 1 024 · 0,05 · 1,5 · 1,25 = 96 period → modulo beze švu)
		vec2 det = texture(wave_tex, (p - pofs * 1.5) * 1.25 + vec2(0.13, 0.77)).rg * 2.0 - 1.0;
		slope += det * 1.1 * clamp(wind_speed * 0.25, 0.0, 1.0) / (1.0 + length(VERTEX) * 0.08);
	}
#else
	slope = water_layers(p, flowing ? vel * t : pofs, sc_a, sc_b, n_foam, n_big);
#endif
	if (!flowing) {
		// rybník: hřebeny vlnek kolmo na vítr – sklon podél větru silnější
		vec2 wperp = vec2(-wdir.y, wdir.x);
		slope = wdir * dot(slope, wdir) * 1.25 + wperp * dot(slope, wperp) * 0.6;
	}
	// amplituda (RMS sklonu): potok podle rychlosti, rybník hladký za bezvětří
	float amp = flowing ? (0.026 + 0.032 * min(fs * max(smul, 0.4), 2.0)) * wave_scale
		: 0.006 + 0.02 * wave_scale * wave_scale;
#ifdef WATER_HQ
	if (!flowing) {
		// chuchvalce nárazů větru: tmavší zčeřené plochy, které přebíhají přes rybník
		float g = textureLod(wind_gust, fract((world_pos.xz - wind_offset) / 1024.0), 0.0).r;
		amp *= mix(1.0, 0.35 + 1.5 * g * g, clamp(wind_speed * 0.3, 0.0, 1.0));
	}
	// kapky deště (ne na ledu): dvě mřížky, unášené proudem
	if (rain > 0.01 && icy < 0.5) {
		float dist_f = clamp(1.0 - length(VERTEX) / 35.0, 0.0, 1.0);
		if (dist_f > 0.0) {
			float dens = clamp(rain * 2.5, 0.0, 1.0);
			vec2 rp = flowing ? p - vel * smul * t : world_pos.xz;
			vec2 rip = water_ripples(rp, t, 0.45, dens) + water_ripples(rp + vec2(0.21, 0.13), t * 1.13 + 0.5, 0.31, dens * 0.8);
			slope += rip * 0.35 * dist_f / max(amp, 0.01);   // sklon kroužků nezávisle na amplitudě vlnek
		}
	}
#endif
	amp *= (1.0 - icy) / (1.0 + length(VERTEX) * 0.04);   // v dálce klidnější (méně třpytu a moaré)
	vec3 nw = normalize(tan_w * (-slope.x * amp) + bin_w * (-slope.y * amp) + up_w);
	vec3 nv = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);
	NORMAL = nv;

	// --- hloubka za hladinou: tloušťka vody podél paprsku (útlum) a svislá hloubka (pěna u břehu, led)
	vec2 suv = SCREEN_UV;
	float d_raw = texture(depth_tex, suv).r;
	vec4 bpos = INV_PROJECTION_MATRIX * vec4(suv * 2.0 - 1.0, d_raw, 1.0);
	bpos.xyz /= bpos.w;
	float surf_d = length(VERTEX);
	float thick = clamp(length(bpos.xyz) - surf_d, 0.0, 20.0);
	vec3 vdir = normalize(-VERTEX);
	float ndv = clamp(dot(vdir, nv), 0.0, 1.0);
	float fres = 0.02 + 0.98 * pow(1.0 - ndv, 5.0);
	// okluze obzoru: odraz pod výškou okolí (water_horizon) nevidí oblohu, ale břehy, rákos a stromy – engine odráží
	// jen oblohu, proto tam se SPECULAR ubere a odraz dostane tmavou olivovou barvu břehu (osvětlenou sluncem)
	// (směr odrazu z vyhlazené normály – jinak by vlnky přeskakovaly přes obzor a hladina zrnitě jiskřila)
	vec3 rd_w = reflect(-normalize(INV_VIEW_MATRIX * vec4(vdir, 0.0)).xyz, normalize(mix(up_w, nw, 0.35)));
	float hz = water_horizon(rd_w, tan_w, edge, flowing);
	float sky_vis = smoothstep(hz - 0.06, hz + 0.10, rd_w.y);
	vec3 bank_refl = BANK_REFL * fres * (1.0 - sky_vis) * 3.0;
#ifdef WATER_HQ
	// lom: posun podle odchylky normály od klidné hladiny, menší v mělčině a v dálce; co je před hladinou, se nelomí
	vec3 flat_v = (VIEW_MATRIX * vec4(up_w, 0.0)).xyz;
	vec2 rofs = (nv - flat_v).xy * 0.35 * clamp(thick, 0.0, 1.0) / (1.0 + surf_d * 0.08);
	vec2 ruv = clamp(suv + rofs, vec2(0.001), vec2(0.999));
	float r_raw = texture(depth_tex, ruv).r;
	vec4 rpos = INV_PROJECTION_MATRIX * vec4(ruv * 2.0 - 1.0, r_raw, 1.0);
	rpos.xyz /= rpos.w;
	if (length(rpos.xyz) > surf_d + 0.01) {
		suv = ruv;
		bpos = rpos;
		thick = clamp(length(bpos.xyz) - surf_d, 0.0, 20.0);
	}
#endif
	vec3 bot_w = (INV_VIEW_MATRIX * vec4(bpos.xyz, 1.0)).xyz;
	float dv = clamp(world_pos.y - bot_w.y, 0.0, 20.0);

	// --- pěna: u břehu a kamenů (mělko), v peřejích; teče s vodou
	// (práh hloubky rozkmitaný šumem → nepravidelný lem, ne čára podél vrstevnice dna)
	float shore = 1.0 - smoothstep(0.02, 0.16 + 0.14 * n_big, dv);
	float foam = shore * smoothstep(0.4, 0.78, n_foam + shore * 0.3) * (flowing ? 0.85 : 0.3);   // rybník: jen proužek nánosu
	if (flowing) {
		foam += smoothstep(0.62, 0.85, n_foam) * smoothstep(1.2, 2.2, smul * fs * 1.6) * 0.6;
		foam += smoothstep(0.7, 0.9, n_foam) * 0.18 * min(fs, 1.0);
	}
	foam = clamp(foam, 0.0, 1.0) * (1.0 - icy);

	// --- útlum a rozptyl (Beer-Lambert); po přívalu kalná
	vec3 sig = absorb * (1.0 + turbid * 3.0);
	vec3 scat = mix(deep_color, mix(mud_color, mud_color * 0.6, 0.5), turbid * 0.85);
	vec3 col;
	float alpha;
#ifdef WATER_HQ
	vec3 trans = exp(-sig * thick);
	vec3 bg = texture(screen_tex, suv).rgb;
	// odraz okolí (břehy, stromy): pochod paprsku po hloubkovém bufferu, kde nic netrefí, zůstává odraz oblohy enginu
	float hitw = 0.0;
	vec3 refl = vec3(0.0);
	vec3 rd = reflect(-vdir, nv);
	if (rd.z < 0.2) {
		int steps = gfx_quality > 2.5 ? 16 : 10;
		float grow = gfx_quality > 2.5 ? 1.36 : 1.62;
		float stp = 0.25 + surf_d * 0.015;
		vec3 rp3 = VERTEX;
		vec3 prev = rp3;
		for (int i = 0; i < steps; i++) {
			prev = rp3;
			rp3 += rd * stp;
			vec4 c = PROJECTION_MATRIX * vec4(rp3, 1.0);
			vec2 huv = c.xy / c.w * 0.5 + 0.5;
			if (c.w <= 0.0 || huv.x < 0.0 || huv.x > 1.0 || huv.y < 0.0 || huv.y > 1.0) {
				break;
			}
			vec4 sp = INV_PROJECTION_MATRIX * vec4(huv * 2.0 - 1.0, textureLod(depth_tex, huv, 0.0).r, 1.0);
			float diff = sp.z / sp.w - rp3.z;
			if (diff > 0.0 && diff < stp * 1.5 + 0.3) {
				// zpřesnění hledáním půlením
				vec3 lo = prev;
				vec3 hi = rp3;
				for (int k = 0; k < 4; k++) {
					vec3 mid = (lo + hi) * 0.5;
					vec4 cm = PROJECTION_MATRIX * vec4(mid, 1.0);
					vec2 muv = cm.xy / cm.w * 0.5 + 0.5;
					vec4 mp = INV_PROJECTION_MATRIX * vec4(muv * 2.0 - 1.0, textureLod(depth_tex, muv, 0.0).r, 1.0);
					if (mp.z / mp.w - mid.z > 0.0) {
						hi = mid;
					} else {
						lo = mid;
					}
				}
				vec4 ch = PROJECTION_MATRIX * vec4(hi, 1.0);
				vec2 fuv = ch.xy / ch.w * 0.5 + 0.5;
				vec2 eb = min(fuv, 1.0 - fuv);
				hitw = smoothstep(0.0, 0.08, min(eb.x, eb.y)) * (1.0 - smoothstep(-0.1, 0.2, rd.z)) * (1.0 - float(i) / float(steps) * 0.5);
				refl = texture(screen_tex, fuv).rgb;
				break;
			}
			stp *= grow;
		}
	}
	col = scat * (1.0 - trans) * (1.0 - fres) + bank_refl * (1.0 - hitw);
	EMISSION = (bg * trans * (1.0 - fres) + refl * fres * hitw) * (1.0 - foam);
	SPECULAR = WATER_SPEC * (1.0 - hitw) * mix(0.2, 1.0, sky_vis);
	alpha = smoothstep(0.0, 0.04, dv);
#else
	float op = 1.0 - exp(-dot(sig, vec3(0.3333)) * thick);
	col = mix(shallow_color, scat, op) + bank_refl;
	SPECULAR = (WATER_SPEC + 0.1) * mix(0.2, 1.0, sky_vis);   // průhlednost odraz zeslabí – trochu víc lesku
	alpha = clamp(0.22 + op * 0.75 + fres * 0.6, 0.0, 0.96) * smoothstep(0.0, 0.04, dv);
	// déšť bez kroužků (levná varianta): hladina zdrsní a ztratí zrcadlový lesk
	SPECULAR *= 1.0 - rain * 0.3 * (1.0 - icy);
#endif
	col = mix(col, FOAM_COLOR, foam);
	// okraj pásu toku: rozostřený a nepravidelný (kde terén u břehu klesne pod hladinu, nekončí rovnou čarou),
	// volné konce pásu (pramen, ústí do jiného toku) doznívají
	if (flowing) {
		float ef = smoothstep(0.0, 0.3, edge + (n_big - 0.5) * 0.22) * smoothstep(0.0, 1.0, v_fade + (n_foam - 0.5) * 0.3);
		alpha *= ef;
		foam *= ef;
	}
	alpha = max(alpha, foam * smoothstep(0.0, 0.02, dv));
	// rybník: hladší pruhy („zrcadla“) a zčeřenější plochy střídavě; déšť zdrsní hladinu
	// v dálce mírně drsnější: vlnky menší než pixel rozmažou odraz (místo jiskření)
	float rough = mix(flowing ? 0.035 : mix(0.02, 0.06, n_big), 0.5, foam) + rain * 0.06 * (1.0 - icy)
		+ min(surf_d * 0.0015, 0.05);

	// --- led: zamrzá od břehů (potok) a od mělčin (rybník), praskliny, na ledu sníh
	if (icy > 0.001) {
		float frontier = flowing ? (1.0 - edge) : clamp(1.0 - dv * 0.6, 0.0, 1.0);
		vec4 ns = texture(wave_tex, world_pos.xz * 0.07);
		float il = smoothstep(1.0 - icy * 1.25, 1.05 - icy * 1.25, frontier + (ns.b - 0.5) * 0.25);
		il = max(il, smoothstep(0.85, 1.0, icy));
		float crack = 1.0 - smoothstep(0.0, 0.018, abs(ns.b - 0.5));
		vec3 ice_col = mix(vec3(0.30, 0.38, 0.40), vec3(0.66, 0.74, 0.78), ns.a * 0.7);
		ice_col = mix(ice_col, vec3(0.85, 0.89, 0.92), crack * 0.7);
		float snow_m = smoothstep(0.7 - snow * 1.1, 0.85 - snow * 1.1, ns.a * 0.6 + ns.b * 0.4) * step(0.01, snow);
		ice_col = mix(ice_col, vec3(0.92, 0.94, 0.96), snow_m);
		col = mix(col, ice_col, il);
		rough = mix(rough, mix(0.12, 0.85, snow_m), il);
		alpha = mix(alpha, 0.97, il);
#ifdef WATER_HQ
		EMISSION *= 1.0 - il;
		SPECULAR = mix(SPECULAR, 0.5, il);
#endif
	}

	ALBEDO = col;
	ROUGHNESS = rough;
	METALLIC = 0.0;
	ALPHA = alpha;
}
