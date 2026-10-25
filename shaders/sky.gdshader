// Fyzikální obloha (M8.5, přepracováno 10/2026): jednoduchý rozptyl Rayleigh + Mie + pohlcování ozonem podél
// paprsku pohledu (8 vzorků), průchod světla ke slunci analyticky Chapmanovou funkcí (Schüler 2012) – modrý
// zenit, bělavý opar u obzoru, aureola kolem slunce, zčervenalé slunce, po západu zemský stín, pás Venuše
// a modrá hodina (ozon); v noci vzdušné světélkování, hvězdy, Mléčná dráha a měsíc s fází (osvětlená strana
// ke slunci). Mraky leží na kulové slupce 1,6 km nad zemí (k obzoru se zhušťují a splývají s oparem), světlo
// slunce prochází jejich hustotou (tmavší spodky a středy, stříbrné okraje proti slunci), zataženo = souvislá
// šedá vrstva, déšť ji tmaví; na Vysoké/Ultra navíc řasy (cirry) ve 8 km a jemnější detail.
// Drahý rozptyl běží ve čtvrtinovém rozlišení (use_quarter_res_pass), detaily v plném. Barvy světla na mraky,
// zisk adaptace oka v soumraku a jas země posílá skript (Atmosphere._sky_light) – týž model počítá i GDScript
// (Atmosphere.SkyModel.clear_sky), takže mlha, slunce a mraky mají stejné barvy jako obloha.
// Stará ruční obloha (Nízká předvolba / realismus „Obloha“ vypnut) je v sky_legacy.gdshader.
shader_type sky;
render_mode use_debanding, use_quarter_res_pass;

global uniform float gfx_quality;

uniform vec3 sun_dir = vec3(0.0, 0.5, -0.8);
uniform vec3 moon_dir = vec3(0.0, 0.3, 0.9);
uniform float moon_light = 0.5;          // osvětlená část kotouče 0..1
// RGBA šum mraků (Atmosphere.cloud_noise_image): R makro fBm, G kupy (Worley), B detail fBm, A jemné kupy
uniform sampler2D cloud_noise : filter_linear_mipmap, repeat_enable;
uniform float cloud_cover = 0.3;         // 0 jasno … 1 zataženo
uniform float cloud_thr = 0.5;           // práh tvaru mraků = kvantil šumu podle pokrytí (skript)
uniform float cloud_dark = 0.0;          // 0..1 dešťová / bouřková oblačnost
uniform vec2 cloud_offset = vec2(0.0);   // posun větrem (dlaždice šumu, skript)
uniform float haze = 0.0;                // opar, mlha 0..1
uniform float flash = 0.0;               // blesk 0..1
uniform float brightness = 1.0;
uniform float light_pollution = 0.0;     // světelný smog obce 0..1
uniform bool sky_on = true;              // zpětná kompatibilita (vypnuto = sky_legacy.gdshader)
// --- fyzikální model (skript)
uniform float turbidity = 1.4;           // aerosol (opar) – násobek ~3× čistého vzduchu
uniform float sun_e = 14.0;              // jas slunce v jednotkách obrazu (kalibrace na expozici 1)
uniform float sky_gain = 1.0;            // adaptace oka v soumraku (komprese jasu, ≥ 1)
uniform vec3 white_bal = vec3(1.0);      // vyvážení bílé (polední slunce bílé)
uniform float sky_night = 0.0;           // 0 den … 1 astronomická noc (hvězdy)
uniform vec3 sun_disk = vec3(40.0);      // jas slunečního kotouče (barva = propustnost atmosféry)
uniform vec3 cloud_sun = vec3(1.5);      // světlo slunce na mraky ve 1,6 km (× propustnost, × zisk)
uniform vec3 cirrus_sun = vec3(1.5);     // … na řasy v 8 km (svítí ještě dlouho po západu)
uniform vec3 cloud_amb = vec3(0.4, 0.5, 0.7);  // světlo oblohy na mraky
uniform vec3 horizon_col = vec3(0.7, 0.75, 0.8); // obloha u obzoru (opar, mlha)
uniform vec3 ground_col = vec3(0.12);    // jas země pod obzorem (odrazy, světlo zdola v cubemapě)
uniform vec3 night_col = vec3(0.0038, 0.0058, 0.0128);  // vzdušné světélkování + hvězdné pozadí
uniform float night_horizon = 2.4;      // … u obzoru jasnější (silnější vrstva vzduchu)
uniform float moon_e = 0.0;              // měsícem nasvícená obloha

// km; Země, horní hranice atmosféry, výška pozorovatele (Morava ~300 m n. m.)
const float PR_ = 6360.0;
const float PA_ = 6460.0;
const float H0_ = 0.3;
const vec3 BR_ = vec3(5.802e-3, 13.558e-3, 33.1e-3);   // Rayleigh (1/km u hladiny moře)
const vec3 BO_ = vec3(2.0e-3, 1.881e-3, 0.085e-3);     // ozon (Chappuisova pásma), stanový profil 10–40 km
const float MS_ = 0.4;                                 // vícenásobný rozptyl (izotropní podíl)

float hash3(vec3 p) {
	p = fract(p * vec3(443.897, 441.423, 437.195));
	p += dot(p, p.yzx + 19.19);
	return fract((p.x + p.y) * p.z);
}

float hg(float c, float g) {
	float g2 = g * g;
	return (1.0 - g2) / (12.566 * pow(max(1.0 + g2 - 2.0 * g * c, 1e-4), 1.5));
}

// Chapmanova funkce × exp(−h) v jednotkách výšky škály (Schüler 2012, GPU Pro 3) – optická hloubka ke slunci
// z výšky h pod úhlem s kosinem cz; pod obzorem paprsek projde přes tečný bod (zemský stín = obří hodnota).
float chapman(float x, float h, float cz) {
	float c = sqrt(x + h);
	if (cz >= 0.0) {
		return c / (c * cz + 1.0) * exp(-h);
	}
	float x0 = sqrt(max(1.0 - cz * cz, 0.0)) * (x + h);
	return 2.0 * sqrt(x0) * exp(min(x - x0, 60.0)) - c / (1.0 - c * cz) * exp(-h);
}

// Jasná obloha ve směru d (bez kotoučů a mraků), relativní radiance pro sun_e = 1.
vec3 clear_sky(vec3 d, vec3 sd, int n) {
	float mu = max(d.y, 0.0);
	float r0 = PR_ + H0_;
	float b = r0 * mu;
	float tmax = -b + sqrt(b * b + PA_ * PA_ - r0 * r0);
	vec2 dh = d.xz;
	float lh = length(dh);
	dh = lh > 1e-5 ? dh / lh : vec2(1.0, 0.0);
	float sh = dot(dh, sd.xz);          // vodorovná složka slunce v rovině pohledu
	float sqmu = sqrt(max(1.0 - mu * mu, 0.0));
	float cs = dot(normalize(vec3(d.x, mu, d.z)), sd);
	float pr = 0.0597 * (1.0 + cs * cs);
	float pm = hg(cs, 0.78);
	float bms = 0.004 * 3.0 * turbidity;
	float bme = bms * 1.11;
	vec3 tauv = vec3(0.0);
	vec3 l = vec3(0.0);
	float fn = float(n);
	for (int i = 0; i < n; i++) {
		float fi = float(i);
		float f0 = (fi + 0.5) / fn;
		float t = tmax * f0 * f0;
		float dt = tmax * ((fi + 1.0) * (fi + 1.0) - fi * fi) / (fn * fn);
		float px = t * sqmu;
		float py = r0 + t * mu;
		float r = sqrt(px * px + py * py);
		float h = r - PR_;
		float mus = (px * sh + py * sd.y) / r;   // výška slunce v místě vzorku (zakřivení Země)
		float dr = exp(-h / 8.0);
		float dm = exp(-h / 1.2);
		float dz = max(1.0 - abs(h - 25.0) / 15.0, 0.0);
		vec3 ext = BR_ * dr + vec3(bme * dm) + BO_ * dz;
		vec3 tmid = tauv + ext * (dt * 0.5);
		tauv += ext * dt;
		float mp = max(mus, 0.0);
		// ozon na cestě ke slunci (tenká slupka ~25 km; pod obzorem ji paprsek protne dvakrát)
		float amo = inversesqrt(mp * mp + 0.0035) * (1.0 + clamp(-mus * 10.0, 0.0, 1.0)) * clamp((45.0 - h) / 20.0, 0.0, 1.0);
		vec3 to = BO_ * 15.0 * amo;
		vec3 ts = exp(-min(BR_ * 8.0 * chapman(795.0, h / 8.0, mus) + vec3(bme * 1.2 * chapman(5300.0, h / 1.2, mus)) + to, vec3(80.0)));
		vec3 ims = exp(-min(BR_ * 4.0 * chapman(795.0, h / 8.0, min(mus + 0.03, 1.0)) + to, vec3(80.0)));
		vec3 tv = exp(-tmid);
		vec3 sr = BR_ * dr;
		vec3 sm = vec3(bms * dm);
		l += tv * (ts * (sr * pr + sm * pm) + (sr + sm) * ims * (MS_ / 12.566)) * dt;
	}
	return l;
}

// Obloha bez kotoučů a mraků v jednotkách obrazu (jasná + měsíc + noc + světelný smog).
vec3 sky_base(vec3 d, vec3 sd, int n) {
	vec3 col = clear_sky(d, sd, n) * white_bal * (sun_e * sky_gain);
	float mu = max(d.y, 0.0);
	float lo = 1.0 - mu;
	// měsícem nasvícená obloha: modrošedá, u obzoru světlejší, aureola kolem měsíce
	float cm = dot(d, normalize(moon_dir));
	col += moon_e * (vec3(0.30, 0.42, 0.75) * (0.55 + 0.45 * lo * lo * lo) + vec3(0.9, 0.9, 0.85) * hg(cm, 0.8) * 0.35);
	// vzdušné světélkování a hvězdné pozadí (u obzoru silnější vrstva)
	col += night_col * (1.0 + night_horizon * lo * lo * lo * lo);
	// teplý opar nad obcí (sodíková / LED světla), mraky ho zesílí
	col += vec3(1.0, 0.6, 0.3) * 0.05 * light_pollution * sky_night * smoothstep(0.45, 0.0, mu) * (1.0 + cloud_cover);
	return col;
}

// Vzdálenost (km) k vrstvě ve výšce hc nad zemí po kouli – mraky se k obzoru zhušťují jako ve skutečnosti.
float shell_t(float mu, float hc) {
	float r0 = PR_ + H0_;
	float rc = PR_ + hc;
	float b = r0 * mu;
	return -b + sqrt(b * b + rc * rc - r0 * r0);
}

float cloud_shape(vec4 a) {
	return a.r * 0.58 + a.g * 0.42;
}

// Mraky přes barvu oblohy col; cs = kosinus úhlu ke slunci. hi = jemný detail a řasy (Vysoká / Ultra).
vec3 clouds(vec3 col, vec3 d, vec3 sd, float cs, bool cube, bool hi) {
	float mu = d.y;
	float t = shell_t(mu, 1.6);
	vec2 uv = d.xz * (t / 9.0) + cloud_offset;               // dlaždice šumu = 9 km
	vec4 a = texture(cloud_noise, uv);
	float base = cloud_shape(a);
	float ov = smoothstep(0.72, 0.97, cloud_cover);           // souvislá vrstva (stratus) při zatažení
	float span = max(1.0 - cloud_thr, 0.05);
	float dens = (base - cloud_thr) / span;
	if (!cube) {
		// eroze okrajů jemným šumem (ve 3,3× menším měřítku, táhne o něco rychleji – paralaxa)
		vec4 b = texture(cloud_noise, uv * 3.3 + vec2(0.31, 0.67) + cloud_offset * 0.6);
		float det = b.b * 0.55 + b.a * 0.45;
		if (hi) {
			det = det * 0.7 + texture(cloud_noise, uv * 11.0 + vec2(0.13, 0.41)).b * 0.3;
		}
		dens -= (1.0 - clamp(dens * 2.5, 0.0, 1.0)) * (det - 0.4) * 0.7;
	}
	dens = clamp(dens * 1.7, 0.0, 1.0);
	float dens_c = dens;
	dens = max(dens, ov * (0.78 + 0.22 * a.r));
	// samostín: hustota o kus směrem ke slunci (nízké slunce = delší cesta v mraku)
	vec2 sdir = sd.xz / max(length(sd.xz), 1e-3);
	float lstep = clamp(0.006 / max(sd.y, 0.02), 0.006, 0.08);
	float dl = clamp((cloud_shape(texture(cloud_noise, uv + sdir * lstep)) - cloud_thr) / span * 1.7, 0.0, 1.0);
	if (hi) {
		float dl2 = clamp((cloud_shape(texture(cloud_noise, uv + sdir * lstep * 2.5)) - cloud_thr) / span * 1.7, 0.0, 1.0);
		dl = dl * 0.65 + dl2 * 0.35;
	}
	float shadow = exp(-(dl * 2.6 + dens_c * 1.2));
	float powder = 1.0 - exp(-dens_c * 6.0);                  // „efekt prášku“ – tenké okraje odvrácené od slunce tmavší
	float ph = (hg(cs, 0.6) * 0.7 + hg(cs, -0.2) * 0.3) * 12.566;
	float edge = 1.0 - dens_c;
	vec3 lit = cloud_sun * shadow * (0.35 + 0.65 * powder) * (0.55 + ph * (0.35 + 1.4 * edge));
	vec3 ccol = lit + cloud_amb * (1.05 - 0.5 * dens_c);      // spodky a středy tmavší
	// souvislá vrstva: rozptýlené světlo prošlé vrstvou (šedé, ke slunci světlejší), déšť tmaví
	float sl = dot(cloud_sun, vec3(0.2126, 0.7152, 0.0722));
	vec3 st = mix(cloud_sun, vec3(sl), 0.6) * 0.2 * (0.7 + 0.9 * pow(max(cs, 0.0), 6.0)) * (0.82 + 0.36 * a.r);
	st += cloud_amb * (0.42 - 0.12 * a.g);
	ccol = mix(ccol, st, ov * (1.0 - dens_c * 0.4));
	ccol *= 1.0 - cloud_dark * (0.35 + 0.35 * dens);
	ccol += vec3(1.0, 0.62, 0.32) * 0.07 * light_pollution * sky_night * dens;   // obec nasvítí mraky zespodu
	float alpha = smoothstep(0.0, 0.3, dens);
	// vzdušná perspektiva: vzdálené mraky splývají s oparem u obzoru
	float far = 1.0 - exp(-t / (55.0 + 80.0 * ov));
	ccol = mix(ccol, col, far * 0.85);
	alpha *= smoothstep(-0.01, 0.025, mu);
	col = mix(col, ccol, alpha);
	// řasy (cirry) ve 8 km – jen Vysoká / Ultra, pruhy podél větru
	if (hi && ov < 0.99) {
		float tc = shell_t(mu, 8.0);
		vec2 cu = d.xz * (tc / 30.0) + cloud_offset * 0.35;
		vec2 wd = normalize(cloud_offset + vec2(1e-4, 7e-5));
		vec2 su = vec2(dot(cu, wd) * 0.45, dot(cu, vec2(-wd.y, wd.x)) * 1.4);
		float ci = texture(cloud_noise, su + vec2(0.5, 0.2)).b;
		float patchy = smoothstep(0.45, 0.75, texture(cloud_noise, cu * 0.25 + vec2(0.7, 0.1)).r);
		float amt = (0.2 + 0.3 * smoothstep(0.1, 0.6, cloud_cover)) * patchy;
		float cd = smoothstep(0.5, 0.85, ci) * amt * (1.0 - ov);
		cd *= smoothstep(0.0, 0.06, mu) * (1.0 - alpha) * (1.0 - 0.75 * sky_night);   // v noci skoro neviditelné
		vec3 cc = cirrus_sun * (0.55 + 0.5 * ph) + cloud_amb * 0.6;
		col = mix(col, mix(cc, col, 1.0 - exp(-tc / 300.0)), cd * 0.55);
	}
	return col;
}

void sky() {
	vec3 d = normalize(EYEDIR);
	vec3 sd = normalize(sun_dir);
	if (AT_QUARTER_RES_PASS) {
		COLOR = sky_base(d, sd, 8);
	} else {
		bool cube = AT_CUBEMAP_PASS;
		bool hi = gfx_quality > 1.5 && !cube;
		vec3 col = cube ? sky_base(d, sd, gfx_quality > 1.5 ? 6 : 4) : QUARTER_RES_COLOR.rgb;   // cubemapa (okolní světlo) stačí hrubší
		float mu = d.y;
		float h = max(mu, 0.0);
		float cs = dot(d, sd);
		vec3 md = normalize(moon_dir);
		float vis = 1.0 - smoothstep(0.75, 0.98, cloud_cover);    // za souvislou vrstvou není nic vidět
		if (!cube && mu > 0.0) {
			float ext = exp(-0.12 / (h + 0.03));                     // extinkce u obzoru (vzdušná hmota)
			// --- hvězdy: kulaté body, různá jasnost a barva; světelný smog jich polovinu schová
			if (sky_night > 0.01) {
				vec3 g = d * 360.0;
				vec3 cell = floor(g);
				float st = hash3(cell);
				float thr = mix(0.993, 0.9975, light_pollution);
				if (st > thr) {
					vec3 c = cell + 0.5 + (vec3(hash3(cell + 1.7), hash3(cell + 3.1), hash3(cell + 5.3)) - 0.5) * 0.6;
					float dd = length(g - c);
					float mag = pow(hash3(cell + 7.9), 6.0);
					float k = exp(-dd * dd * 3.5) * (0.2 + 2.2 * mag);
					vec3 tint = mix(vec3(1.0, 0.82, 0.65), vec3(0.75, 0.85, 1.0), hash3(cell + 9.4));
					col += tint * k * sky_night * ext * vis * (1.0 - 0.5 * light_pollution) * 0.9;
				}
				// Mléčná dráha (Vysoká / Ultra): slabý zrnitý pás
				if (hi) {
					vec3 gn = normalize(vec3(0.36, 0.48, -0.8));
					float band = exp(-pow(dot(d, gn), 2.0) * 28.0);
					if (band > 0.02) {
						vec3 ex = normalize(cross(gn, vec3(0.0, 1.0, 0.0)));
						vec2 gu = vec2(dot(d, ex), dot(d, cross(gn, ex))) * 1.6;
						float n = texture(cloud_noise, gu * 0.7).r * 0.6 + texture(cloud_noise, gu * 2.3).b * 0.4;
						col += vec3(0.75, 0.8, 1.0) * 0.022 * band * smoothstep(0.25, 0.8, n) * sky_night * ext * vis * (1.0 - light_pollution);
					}
				}
			}
			// --- měsíc s fází: osvětlená polokoule natočená ke slunci, slabý popelavý svit, moře (tmavší skvrny)
			float mc = dot(d, md);
			if (mc > 0.9999) {
				float rad = 0.0075;                                    // úhlový poloměr (zvětšený ~1,7×, ať je ve hře vidět)
				vec3 o = (d - md * mc) / rad;
				float q = dot(o, o);
				if (q < 1.0) {
					vec3 nrm = o - md * sqrt(1.0 - q);                  // normála koule (k pozorovateli = −md)
					float lit = smoothstep(-0.06, 0.08, dot(nrm, sd));
					vec3 ax = cross(md, vec3(0.0, 1.0, 0.0));
					ax = dot(ax, ax) > 1e-6 ? normalize(ax) : vec3(1.0, 0.0, 0.0);
					vec2 tuv = vec2(dot(o, ax), o.y) * 0.25 + 0.5;
					float mare = 0.72 + 0.28 * smoothstep(0.35, 0.65, texture(cloud_noise, tuv * 0.5 + 0.3).r);
					float limb = smoothstep(1.0, 0.85, q);
					vec3 mcol = vec3(0.98, 0.95, 0.86) * mare * (lit * 1.6 + 0.012) * limb;
					col = mix(col, col * 0.3 + mcol, limb * mix(0.25, 1.0, sky_night) * ext);
				}
			}
			// --- slunce: kotouč s okrajovým ztemněním (barvu dává propustnost atmosféry)
			float sr = 0.0058;                                       // úhlový poloměr (skutečný 0,0047, o trochu větší)
			float sq = (1.0 - cs) * 2.0 / (sr * sr);
			if (sq < 1.4) {
				float disk = 1.0 - smoothstep(0.85, 1.15, sq);
				float limb = 1.0 - 0.55 * (1.0 - sqrt(max(1.0 - min(sq, 1.0), 0.0)));
				col += sun_disk * disk * limb;
			}
		}
		// --- mraky
		if (mu > -0.01) {
			col = clouds(col, d, sd, cs, cube, hi);
		}
		// --- opar / mlha: obloha splývá s barvou obzoru
		col = mix(col, horizon_col, clamp(haze * (1.0 - h * 0.5), 0.0, 1.0) * 0.85);
		// --- pod obzorem: země (osvětlená sluncem a oblohou), u obzoru opar
		if (mu < 0.0) {
			col = mix(col, ground_col, smoothstep(0.0, -0.06, mu));
		}
		col += vec3(0.75, 0.8, 1.0) * flash * (0.6 + 0.4 * h);
		COLOR = col * brightness;
	}
}
