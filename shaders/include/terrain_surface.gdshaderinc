// Procedurální povrch terénu (sdílí terrain.gdshader a surroundings.gdshader, aby okolí barevně navazovalo).
// Vstupem je pět vzorků RGBA šumu `TsSig` (Terrain.detail_noise_texture): R, G = dva nezávislé fraktální šumy,
// B = buňkový šum – vzdálenost ke středu buňky (hrudky, kamínky, listí), A = náhodná hodnota téže buňky.
//   n0 ~ 4,3 m perioda (hrudky / listí ~14 cm, trsy ~0,4 m), n1 ~ 32 m (trsy, skvrny ~3 m), n2 ~ 167 m (skvrny ~16 m),
//   nm ~ 1,4 km (makro: vlhkost R, půdní typ G – skvrny na stovky metrů), nf ~ 0,5 m (stébla, zrnka štěrku).
// Zdálky se za ně dosadí průměr šumu (nejmenší mip) → barva třídy je stejná jako zprůměrovaná blízká textura.
// Třídy: 0 tráva, 1 orná půda, 2 sad / zahrada, 3 les, 4 dvůr, 5 břeh, 6 skála, 7 polní cesta (+ 8 voda v okolí).
//
// Pozor (M8.4): parametry a lokální proměnné mají předponu `ts_`, aby se nekryly s uniformy shaderů, které soubor vkládají.

struct TsSig {
	vec4 n0;
	vec4 n1;
	vec4 n2;
	vec4 nm;
	vec4 nf;
};

vec3 ts_s2l(vec3 ts_c) {
	return pow(ts_c, vec3(2.2));
}

// tráva / louka: stébla (světlá, stín mezi nimi, suchá), trsy, jetel; makro vlhkost a sucho
vec3 ts_grass(TsSig s, out float ts_h) {
	float ts_dry = clamp(0.35 - (s.nm.r - 0.5) * 0.9 + (s.n2.g - 0.5) * 0.4, 0.0, 1.0);
	vec3 g = mix(ts_s2l(vec3(0.17, 0.24, 0.09)), ts_s2l(vec3(0.33, 0.41, 0.18)), smoothstep(0.2, 0.7, s.nf.r));
	g = mix(g, ts_s2l(vec3(0.48, 0.53, 0.27)), smoothstep(0.6, 0.85, s.nf.g) * 0.55);          // špičky na slunci
	g = mix(g, ts_s2l(vec3(0.62, 0.56, 0.35)), smoothstep(0.7, 0.95, s.nf.a) * (0.2 + 0.6 * ts_dry));  // suchá stébla
	g *= 0.80 + 0.40 * s.n0.r;                                                                   // trsy
	g = mix(g, ts_s2l(vec3(0.24, 0.37, 0.16)), smoothstep(0.58, 0.78, s.n0.g) * 0.35);           // jetel, širší listy
	g = mix(g, g * vec3(1.14, 1.04, 0.70), ts_dry * 0.5);                                         // sušší místa do žluta
	g *= mix(vec3(1.0), vec3(0.84, 0.94, 0.82), smoothstep(0.55, 0.8, s.nm.r) * 0.6);            // vlhčí = tmavší
	ts_h = (s.nf.r - 0.5) * 0.02 + (s.n0.r - 0.5) * 0.03;
	return g;
}

// orná půda bez plodiny: hroudy (buňky), vyschlý povrch, kamínky; makro půdní typ
vec3 ts_soil(TsSig s, out float ts_h) {
	// hroudy: buňky ~14 cm s nepravidelným okrajem (fraktální šum), drobky z jemného šumu
	float ts_clod = 1.0 - smoothstep(0.0, 0.85, s.n0.b + (s.nf.r - 0.5) * 0.45 + (s.n0.g - 0.5) * 0.3);
	ts_clod = mix(ts_clod, 1.0 - smoothstep(0.1, 0.8, s.nf.b), 0.4) * smoothstep(0.25, 0.6, s.n0.a + s.nf.g * 0.4);  // různé velikosti, místy rozpadlé
	vec3 c = mix(ts_s2l(vec3(0.31, 0.24, 0.17)), ts_s2l(vec3(0.39, 0.30, 0.21)), ts_clod);
	c = mix(c, ts_s2l(vec3(0.50, 0.42, 0.32)), ts_clod * smoothstep(0.5, 0.8, s.n0.r) * 0.5);   // vyschlé vršky
	c *= 0.84 + 0.32 * s.nf.r;
	c *= 0.9 + 0.2 * s.n0.r;
	float ts_peb = smoothstep(0.26, 0.2, s.n0.b) * step(0.97, s.n0.a);                          // kamínky ~3 cm
	c = mix(c, ts_s2l(vec3(0.46, 0.43, 0.39)) * (0.8 + 0.4 * s.nf.g), ts_peb * 0.8);
	c *= mix(vec3(0.80, 0.83, 0.88), vec3(1.10, 1.0, 0.90), s.nm.g);                              // tmavší / rezavější půda
	ts_h = ts_clod * 0.007 + ts_peb * 0.006 + (s.nf.r - 0.5) * 0.008 + (s.n0.r - 0.5) * 0.02;
	return c;
}

// lesní půda: tmavá hnědo-olivová hrabanka (listí v rozkladu, jehličí), tmavé mezery, mech a zelený podrost
// (borůvčí, kapradí, tráva) ve skvrnách ~3–16 m, ať les z výšky působí tmavě zeleno-hnědě, ne rudě;
// `ts_aut` = podzim (čerstvé, jen mírně zrzavé listí)
vec3 ts_forest(TsSig s, float ts_aut, out float ts_h) {
	float ts_leaf = 1.0 - smoothstep(0.35, 0.8, s.n0.b);
	vec3 lc = mix(ts_s2l(vec3(0.18, 0.16, 0.11)), ts_s2l(vec3(0.29, 0.26, 0.17)), s.n0.a);   // rozložené listí / jehličí
	lc = mix(lc, ts_s2l(vec3(0.42, 0.31, 0.17)), step(0.8, s.n0.a) * ts_aut * 0.7);
	vec3 c = mix(ts_s2l(vec3(0.10, 0.09, 0.06)), lc, 0.45 + 0.55 * ts_leaf);
	c *= 0.85 + 0.30 * s.nf.r;
	float ts_moss = smoothstep(0.52, 0.72, s.n1.g + (s.nm.g - 0.5) * 0.35 + (s.n0.r - 0.5) * 0.2);
	c = mix(c, ts_s2l(vec3(0.20, 0.27, 0.11)) * (0.8 + 0.4 * s.nf.g), ts_moss * 0.8);
	// podrost: skvrny ~16 m (n2) rozbité trsy ~3 m (n1); v zimě a na podzim hnědne s ostatní zelení (ts_macro)
	float ts_under = smoothstep(0.5, 0.68, s.n2.g + (s.n1.r - 0.5) * 0.3) * (0.6 + 0.4 * smoothstep(0.3, 0.7, s.nf.r));
	vec3 uc = mix(ts_s2l(vec3(0.15, 0.21, 0.09)), ts_s2l(vec3(0.24, 0.30, 0.13)), s.n0.g);
	uc = mix(uc, ts_s2l(vec3(0.30, 0.26, 0.15)), ts_aut * 0.6);
	c = mix(c, uc, ts_under * 0.7);
	ts_h = ts_leaf * 0.012 + ts_moss * 0.02 + ts_under * 0.015 + (s.n0.r - 0.5) * 0.03;
	return c;
}

// dvůr: udusaná hlína, štěrk v plochách (zrnka různého odstínu), skvrny
vec3 ts_yard(TsSig s, out float ts_h) {
	vec3 c = ts_s2l(vec3(0.46, 0.40, 0.31)) * (0.85 + 0.30 * s.n0.r);                          // udusaná hlína
	float ts_cov = smoothstep(0.4, 0.7, s.n1.r + (s.n0.g - 0.5) * 0.3);
	float ts_gr = 1.0 - smoothstep(0.2, 0.75, s.nf.b);
	vec3 gc = mix(ts_s2l(vec3(0.32, 0.30, 0.27)), ts_s2l(vec3(0.56, 0.53, 0.47)), s.nf.a) * (0.7 + 0.3 * ts_gr);
	c = mix(c, gc, ts_cov * 0.6);
	c *= 1.0 - smoothstep(0.62, 0.8, s.n2.g) * 0.25 * (1.0 - ts_cov);
	ts_h = ts_gr * 0.006 * ts_cov + (s.n0.r - 0.5) * 0.01;
	return c;
}

// břeh (pás podél vody v masce): hlavně ostřice a vlhká bujná tráva (v zimě suchá), jen místy vyšlapané bahno.
// Pruh mokrého bahna přímo u vodní čáry kreslí terrain.gdshader z pobřežního pásu (Terrain._compute_shore).
// `ts_own_wet` = vlastní vlhkost, `ts_veg` = podíl porostu
vec3 ts_bank(TsSig s, float ts_dry_season, out float ts_h, out float ts_own_wet, out float ts_veg) {
	vec3 mud = ts_s2l(vec3(0.31, 0.26, 0.19)) * (0.8 + 0.4 * s.n0.r) * (0.9 + 0.2 * s.nf.r);
	float ts_sed = 1.0 - smoothstep(0.66, 0.8, s.n1.g + (s.n0.r - 0.5) * 0.3) * 0.85;
	vec3 sc = mix(ts_s2l(vec3(0.19, 0.28, 0.10)), ts_s2l(vec3(0.36, 0.43, 0.18)), smoothstep(0.3, 0.75, s.nf.r));
	sc *= 0.85 + 0.3 * s.n0.g;                                                                     // trsy ostřic
	sc = mix(sc, ts_s2l(vec3(0.58, 0.52, 0.34)), clamp(smoothstep(0.65, 0.9, s.nf.a) * 0.45 + ts_dry_season * 0.7, 0.0, 1.0));
	ts_own_wet = (1.0 - ts_sed) * 0.6 + 0.1;
	ts_veg = ts_sed;
	ts_h = ts_sed * (s.nf.r - 0.5) * 0.03 + (s.n0.r - 0.5) * 0.012;
	return mix(mud, sc, ts_sed);
}

// skála: bloky s puklinami, lišejník
vec3 ts_rock(TsSig s, out float ts_h) {
	vec3 c = ts_s2l(vec3(0.47, 0.45, 0.42)) * (0.78 + 0.44 * s.n0.a) * (0.85 + 0.30 * s.n1.r);
	float ts_cr = smoothstep(0.72, 0.95, s.n0.b);
	c *= 1.0 - ts_cr * 0.55;
	float ts_li = smoothstep(0.62, 0.75, s.n1.g) * smoothstep(0.55, 0.75, s.nf.r);
	c = mix(c, ts_s2l(vec3(0.58, 0.57, 0.38)), ts_li * 0.6);
	ts_h = (1.0 - ts_cr) * 0.03 + (s.n0.r - 0.5) * 0.04;
	return c;
}

// polní cesta: písčitá hlína se zrnky a kamínky (koleje dělá terrain.gdshader)
vec3 ts_track(TsSig s, out float ts_h) {
	vec3 c = ts_s2l(vec3(0.47, 0.41, 0.32)) * (0.85 + 0.30 * s.n0.r);
	float ts_gr = 1.0 - smoothstep(0.2, 0.75, s.nf.b);
	c *= 0.86 + 0.28 * ts_gr * s.nf.a;
	float ts_peb = smoothstep(0.30, 0.22, s.n0.b) * step(0.93, s.n0.a);
	c = mix(c, ts_s2l(vec3(0.55, 0.53, 0.48)), ts_peb * 0.7);
	ts_h = ts_gr * 0.004 + ts_peb * 0.01 + (s.n0.r - 0.5) * 0.01;
	return c;
}

// Albedo třídy (lineární) + výška reliéfu pro normálu (m), drsnost, vlastní vlhkost a podíl „zelené“ (sezóna, květy).
vec3 ts_class(int c, TsSig s, float ts_green, out float ts_h, out float ts_rough, out float ts_own_wet, out float ts_grassy) {
	ts_rough = 0.92;
	ts_own_wet = 0.0;
	ts_grassy = 0.0;
	vec3 col;
	if (c == 0 || c == 2) {
		col = ts_grass(s, ts_h);
		if (c == 2) {
			col *= vec3(1.0, 1.05, 0.93);                    // sad / zahrada: svěžejší, sekaná
		}
		ts_grassy = 1.0;
	} else if (c == 1) {
		col = ts_soil(s, ts_h);
		ts_rough = 0.95;
	} else if (c == 3) {
		col = ts_forest(s, 1.0 - ts_green, ts_h);
		ts_rough = 0.9;
	} else if (c == 4) {
		col = ts_yard(s, ts_h);
		ts_rough = 0.88;
	} else if (c == 5) {
		col = ts_bank(s, 1.0 - ts_green, ts_h, ts_own_wet, ts_grassy);
		ts_rough = mix(0.72, 0.88, ts_grassy);
	} else if (c == 6) {
		col = ts_rock(s, ts_h);
		ts_rough = 0.82;
	} else if (c == 7) {
		col = ts_track(s, ts_h);
		ts_rough = 0.9;
	} else {
		col = ts_s2l(vec3(0.16, 0.30, 0.36));                // voda (jen okolí)
		ts_h = 0.0;
		ts_rough = 0.3;
	}
	return col;
}

// Společné velké skvrny (sušší / sytější, ~16 m a ~3 m) a sezóna: mimo vegetační sezónu tráva hnědne, v lese opadané listí.
vec3 ts_macro(vec3 col, TsSig s, float ts_grassy, bool ts_forest_c, float ts_green) {
	col *= (0.84 + 0.32 * s.n2.r) * (0.92 + 0.16 * s.n1.r);
	if (ts_grassy > 0.0) {
		vec3 g = mix(col, col * vec3(1.16, 1.05, 0.72), smoothstep(0.55, 0.36, s.n2.r) * 0.45 * ts_green);
		vec3 dry = vec3(dot(g, vec3(0.3, 0.5, 0.2))) * vec3(1.22, 1.0, 0.66);          // sláma, ne šeď
		g = mix(g, dry * (0.95 + 0.15 * s.nm.g), (1.0 - ts_green) * 0.85);
		col = mix(col, g, ts_grassy);
	} else if (ts_forest_c) {
		vec3 dry = vec3(dot(col, vec3(0.3, 0.5, 0.2))) * vec3(1.15, 1.0, 0.8);
		col = mix(col, dry, (1.0 - ts_green) * 0.3);
	}
	return col;
}

// Pseudo-hash 0..1 celočíselné buňky (pole v okolí, náhodné posuny dlaždic).
float ts_hash(vec2 ts_p) {
	return fract(sin(dot(ts_p, vec2(127.1, 311.7))) * 43758.5453);
}
