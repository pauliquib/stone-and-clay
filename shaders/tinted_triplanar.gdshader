// Fasády, střechy a cesty. Dvě cesty podle `use_tex`:
//  • s texturami Poly Haven: triplanární projekce ve světových souřadnicích, jas textury × barva budovy (atribut
//    'tint' z Blenderu → barva vrcholu), stejně jako v Blender scéně;
//  • bez textur (čistý checkout – textury nejsou v gitu, ASSETY.md): procedurální materiál podle `mat_kind`
//    (1 omítka v barvě tintu, u tmavých fasád stodol prkna, 2 střecha – pálené tašky / eternit / lepenka, 3 asfalt se záplatami a vyjetými stopami,
//    4 štěrková cesta) ze sdílené RGBA textury šumů `noise_tex` (ProcTextures) – 2–4 čtení místo 9 u textur.
// Na obou cestách: sokl, vlhkost a odstřik u paty zdí, šmouhy a stín pod okapem (UV = pata a vrchol sloupce zdi,
// `wall_cols`), mech na severních stranách střech, krajnice a stopy cest (UV = (s, šířka pásu), `road_uv`, viz road_e;
// atributy dopočítá MapLoader.load_chunks), sníh a mokro (louže ve stopách).
// Dražší části (bump omítky, praskliny, lišejník, louže) jen pro gfx_quality > 1,5 (Vysoká, Ultra).
shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform sampler2D albedo_tex : source_color, hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rough_tex : hint_roughness_g, filter_linear_mipmap, repeat_enable;
uniform sampler2D noise_tex : filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool use_tex = true;       // false = procedurální materiál (MapLoader bez textur)
uniform int mat_kind = 0;          // 1 omítka, 2 střecha, 3 asfalt, 4 štěrk, 0 obecný
uniform bool wall_cols = false;    // UV zdí = (pata, vrchol) sloupce ve světových výškách
uniform bool road_uv = false;      // UV cest = (s 0..1 napříč pásem, šířka pásu; < 0 = vnitřek křižovatky)
uniform vec2 north_xz = vec2(-0.979, -0.201);   // světový sever (MapLoader.north_xz)
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
global uniform float gfx_quality;
global uniform float grass_green;

varying vec3 wpos;
varying vec3 wnrm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

vec4 nzs(vec2 uv) {
	return texture(noise_tex, uv);
}

// Barva omítky z tintu budovy (lineární): bez olivového nádechu – zelená nejvýš jako červená, modrá pod zelenou
// (šedozelené tinty pod modrou oblohou působily zašle), mírně ztlumená.
vec3 plaster_tint(vec3 t) {
	t.g = min(t.g, t.r * 0.975);
	t.b = min(t.b, t.g * 0.93);
	t = mix(vec3(dot(t, vec3(0.2126, 0.7152, 0.0722))), t, 0.85);   // za šera nežloutne do hořčicové
	return t * 0.94;
}

// Cesty: (vzdálenost od okraje, souměrná vzdálenost pro vyjeté stopy) z UV = (s, W). s ∈ 0..1 = „stan“
// min(s, 1 − s) · W (okraje na obou stranách pásu); s ∈ 2..3 = protější strana zakrytá jiným pásem (ústí odbočky,
// křižovatka) → vzdálenost od okraje lineárně (s − 2) · W, stopy dál souměrně.
vec2 road_e(vec2 uv) {
	if (uv.x > 1.5) {
		float l = (uv.x - 2.0) * uv.y;
		return vec2(l, min(l, uv.y - l));
	}
	float e = min(uv.x, 1.0 - uv.x) * uv.y;
	return vec2(e);
}

// Bump z výšky (m) přes derivace obrazovky (Mikkelsen 2010) – bez tangent, jen Vysoká+.
vec3 bump_world(vec3 nw, vec3 pw, float hgt) {
	vec3 dpx = dFdx(pw);
	vec3 dpy = dFdy(pw);
	float dhx = dFdx(hgt);
	float dhy = dFdy(hgt);
	vec3 r1 = cross(dpy, nw);
	vec3 r2 = cross(nw, dpx);
	float det = dot(dpx, r1);
	vec3 grad = sign(det) * (dhx * r1 + dhy * r2);
	return normalize(abs(det) * nw - grad);
}

void fragment() {
	vec3 n = normalize(wnrm);
	if (!FRONT_FACING) { n = -n; }
	bool hq = gfx_quality > 1.5;
	float dist = length(VERTEX);
	vec3 tint = use_vertex_tint ? COLOR.rgb : base_tint;
	vec3 alb = tint;
	float rough = 0.85;
	vec3 wn = n;
	float ao = 1.0;
	float patchy = 0.5;      // nerovnoměrnost sněhu (dřív jas textury)
	float snow_k = 1.0;      // místní násobek sněhu (krajnice, stopy)
	float wet_rough = 0.18;  // drsnost za mokra
	float puddle = 0.0;      // louže (ve stopách, Vysoká+ / štěrk)
	vec4 wnz = vec4(0.5);    // šum zdi (pro okraje vlhkosti)
	// souřadnice po zdi: vodorovně podél stěny × výška
	vec2 wdir = normalize(vec2(-n.z, n.x) + vec2(1e-4, 0.0));
	vec2 wuv = vec2(dot(wpos.xz, wdir), wpos.y);

	if (use_tex) {
		// --- původní cesta s texturami
		vec3 bw = pow(abs(n), vec3(blend_sharpness));
		bw /= (bw.x + bw.y + bw.z);
		vec3 p = wpos / tex_size_m;
		vec3 cx = texture(albedo_tex, p.zy).rgb;
		vec3 cy = texture(albedo_tex, p.xz).rgb;
		vec3 cz = texture(albedo_tex, p.xy).rgb;
		vec3 c = cx * bw.x + cy * bw.y + cz * bw.z;
		float lum = dot(c, vec3(0.2126, 0.7152, 0.0722));
		patchy = lum;
		c = mix(c, vec3(lum), desaturate) * gain;
		alb = c * (mat_kind == 1 ? plaster_tint(tint) / 0.94 : tint);
		float r = texture(rough_tex, p.zy).g * bw.x + texture(rough_tex, p.xz).g * bw.y + texture(rough_tex, p.xy).g * bw.z;
		rough = clamp(r, 0.12, 1.0);
		vec2 tx = texture(normal_tex, p.zy).xy * 2.0 - 1.0;
		vec2 ty = texture(normal_tex, p.xz).xy * 2.0 - 1.0;
		vec2 tz = texture(normal_tex, p.xy).xy * 2.0 - 1.0;
		wn = normalize(n + normal_strength * (vec3(0.0, tx.y, tx.x) * bw.x + vec3(tz.x, tz.y, 0.0) * bw.z + vec3(ty.x, 0.0, ty.y) * bw.y));
		if (mat_kind == 1 && hq) {
			wnz = nzs(wuv * 0.31);
		}
	} else if (mat_kind == 1 || mat_kind == 0) {
		// --- omítka: barva = tint budovy (lineární albedo světlých omítek ~0,45–0,8), jen jemná zrnitost a skvrny;
		// tmavé fasády stodol a kůlen (jas tintu < 0,36) jsou svislá prkna
		wnz = nzs(wuv * 0.31);
		vec4 nb = nzs(wuv * 0.043 + vec2(0.37, 0.11));
		vec3 pt = plaster_tint(tint);
		float v = (nb.g - 0.5) * 0.08 + (wnz.a - 0.5) * 0.05 + (wnz.r - 0.5) * 0.02;
		alb = pt * (1.0 + v);
		alb *= mix(vec3(1.0), vec3(1.02, 1.0, 0.96), nb.a * 0.6);
		rough = 0.92 - wnz.a * 0.08;
		patchy = 0.4 + 0.4 * nb.g;
		if (dot(tint, vec3(0.2126, 0.7152, 0.0722)) < 0.36 && wall_cols) {
			float bx = wuv.x / 0.16;
			float bid = floor(bx);
			float bf = fract(bx);
			float aa = 1.0 - smoothstep(0.15, 0.5, fwidth(bx));
			float hb = hash12(vec2(bid, floor(tint.r * 97.0)));
			float gap = (1.0 - smoothstep(0.0, 0.06, bf)) * aa;
			vec3 wood = pt * vec3(1.05, 0.96, 0.86) * (0.8 + 0.3 * hb) * (0.9 + 0.2 * wnz.a);
			alb = mix(alb, wood * (1.0 - 0.6 * gap), aa * 0.9 + 0.1);
			rough = 0.9;
			if (hq) {
				wn = normalize(n - vec3(wdir.x, 0.0, wdir.y) * gap * 0.6 * aa);
			}
		} else if (hq) {
			vec4 nf = nzs(wuv * 2.3 + vec2(0.5));
			float fade = 1.0 - smoothstep(6.0, 25.0, dist);
			alb *= 0.97 + 0.06 * nf.a;
			wn = bump_world(n, wpos, (nf.a + 0.5 * nf.r) * 0.0012 * fade);
		}
	} else if (mat_kind == 2) {
		// --- střecha
		wet_rough = 0.25;
		if (abs(n.y) < 0.3) {
			// čelo střechy (okapová a štítová lišta, deska pod přesahem): natřené dřevo / plech
			alb = mix(tint * 0.92, vec3(0.07, 0.055, 0.045), 0.55);
			rough = 0.7;
		} else {
			vec3 rt = n.y > 0.985 ? vec3(1.0, 0.0, 0.0) : normalize(vec3(-n.z, 0.0, n.x));
			vec3 rb = normalize(cross(n, rt));
			if (rb.y < 0.0) { rb = -rb; }
			vec2 ruv = vec2(dot(wpos, rt), dot(wpos, rb));
			vec4 nb = nzs(ruv * 0.05 + vec2(0.71, 0.23));
			patchy = 0.35 + 0.5 * nb.g;
			float tmax = max(tint.r, max(tint.g, tint.b));
			float sat = (tmax - min(tint.r, min(tint.g, tint.b))) / max(tmax, 1e-3);
			float north = dot(normalize(n.xz + vec2(1e-4)), north_xz) * (1.0 - smoothstep(0.92, 0.985, n.y));
			if (n.y > 0.985) {
				// plochá střecha: asfaltová lepenka v pásech
				alb = mix(tint * 0.92, vec3(0.055), 0.6) * (0.85 + 0.3 * nb.g);
				float sm = smoothstep(0.94, 0.99, fract(ruv.x)) * (1.0 - smoothstep(0.3, 0.9, fwidth(ruv.x)));
				alb *= 1.0 - 0.3 * sm;
				rough = 0.85;
			} else if (sat < 0.3) {
				// eternitové šablony kladené na koso (kosočtverce ~28 cm), lišejník a mech
				vec2 q = vec2(ruv.x + ruv.y, ruv.y - ruv.x) * (0.7071 / 0.28);
				vec2 cid = floor(q);
				vec2 f = fract(q);
				vec2 fw = fwidth(q);
				float aa = 1.0 - smoothstep(0.2, 0.55, max(fw.x, fw.y));
				float h1 = hash12(cid + vec2(3.7, 1.3));
				float sh = smoothstep(0.8, 1.0, max(f.x, f.y));
				float lx = 1.0 - smoothstep(0.0, 0.06, f.x);
				float ly = 1.0 - smoothstep(0.0, 0.06, f.y);
				vec3 base = mix(tint * 0.92, vec3(0.15, 0.15, 0.145), 0.45);
				alb = base * mix(0.95, (0.86 + 0.24 * h1) * (1.0 - 0.4 * sh), aa);
				wn = normalize(n + aa * (rb * 0.05 - (rt + rb) * (0.5 * lx) + (rt - rb) * (0.5 * ly)));
				float moss = smoothstep(0.0, 0.8, north) * smoothstep(0.56, 0.8, nb.g + sh * 0.15) * 0.6;
				alb = mix(alb, vec3(0.06, 0.075, 0.03), moss);
				float lich = smoothstep(0.55, 0.8, nb.a) * 0.35;
				alb = mix(alb, vec3(0.2, 0.2, 0.17), lich);
				rough = mix(0.8, 0.95, moss);
				if (hq) {
					vec4 nl = nzs(ruv * 0.9 + vec2(0.31, 0.77));
					float spot = step(0.9, nl.r) * smoothstep(0.05, 0.2, nl.b);
					alb = mix(alb, vec3(0.42, 0.36, 0.14), spot * 0.55 * (0.4 + 0.6 * nb.a));
				}
			} else {
				// pálené drážkové tašky v řadách: variace kusů, stín pod vyšší řadou, čelo tašky, profil
				vec2 tc = ruv / vec2(0.21, 0.34);
				vec2 cid = floor(tc);
				vec2 f = fract(tc);
				vec2 fw = fwidth(tc);
				float aa = 1.0 - smoothstep(0.2, 0.55, max(fw.x, fw.y));
				float h1 = hash12(cid + floor(tint.rg * 113.0));
				float h2 = hash12(cid.yx * 1.37 + vec2(17.0, 5.0));
				vec3 tcol = tint * 0.92 * (0.82 + 0.34 * h1);
				if (h2 < 0.12) {
					tcol *= vec3(0.72, 0.66, 0.64);            // tmavší, přepálená / starší taška
				} else if (h2 > 0.975) {
					tcol *= vec3(1.2, 1.06, 0.95);             // vyměněná nová taška
				}
				float sh = smoothstep(0.7, 1.0, f.y);
				float lip = 1.0 - smoothstep(0.0, 0.07, f.y);
				float hp = 0.5 - 0.5 * cos(f.x * 6.2832);      // profil: hřbet uprostřed, drážky na stycích
				float shade = (1.0 - 0.42 * sh) * (0.92 + 0.1 * hp) * (1.0 + 0.12 * lip);
				alb = mix(tint * 0.92 * 0.88, tcol * shade, aa);
				wn = normalize(n + aa * (rb * (0.08 - 1.4 * lip) - rt * (0.3 * sin(f.x * 6.2832))));
				// usazená špína v drážkách a u spodních hran, mech na severu ve stínu přesahů
				alb *= 1.0 - 0.12 * (1.0 - hp) * aa - 0.08 * nb.a;
				float moss = smoothstep(0.1, 0.8, north) * smoothstep(0.56, 0.82, nb.g + sh * 0.2 * aa + (1.0 - hp) * 0.06) * 0.55;
				alb = mix(alb, vec3(0.05, 0.068, 0.022), moss);
				rough = mix(0.72, 0.95, moss);
				if (hq) {
					vec4 nl = nzs(vec2(ruv.x * 0.6, ruv.y * 0.035) + vec2(0.13, 0.57));
					alb *= 1.0 - 0.18 * smoothstep(0.55, 0.8, nl.g);   // stékající šmouhy po spádu
					vec4 ns = nzs(ruv * 0.8 + vec2(0.61, 0.07));
					float spot = step(0.92, ns.r) * smoothstep(0.05, 0.2, ns.b);
					alb = mix(alb, vec3(0.3, 0.29, 0.2), spot * 0.5);  // lišejník
				}
			}
		}
	} else if (mat_kind == 3) {
		// --- asfalt: kamenivo, opotřebení, záplaty se zalitými spárami, vyjeté stopy, rozpadlé okraje
		vec2 g = wpos.xz;
		vec4 na = nzs(g * 0.85);
		vec4 nb = nzs(g * 0.055 + vec2(0.5, 0.21));
		float e = 99.0;
		float et = 99.0;
		float rw = -1.0;
		if (road_uv && UV.y > 0.0) {
			vec2 ee = road_e(UV);
			e = ee.x;
			et = ee.y;
			rw = UV.y;
		}
		vec3 acol = vec3(0.105, 0.103, 0.1) * (0.8 + 0.42 * nb.g);
		float stone = smoothstep(0.55, 0.82, na.r) * smoothstep(0.02, 0.12, na.b);
		acol = mix(acol, vec3(0.17, 0.165, 0.155), stone * 0.45);
		acol *= 0.88 + 0.2 * smoothstep(0.0, 0.15, na.b);
		rough = 0.84 - 0.06 * stone;
		float tr = 0.0;
		if (rw > 0.0) {
			float hw = 0.5 * rw;
			float t1 = rw < 4.6 ? max(hw - 0.85, 0.35) : 0.75;
			tr = 1.0 - smoothstep(0.1, 0.4, abs(et - t1));
			if (rw >= 4.6) {
				tr = max(tr, 1.0 - smoothstep(0.1, 0.4, abs(et - (hw - 0.8))));
			}
			tr *= 0.55 + 0.45 * nb.a;
		}
		acol = mix(acol, acol * 0.78, tr * 0.7);
		rough = mix(rough, 0.62, tr);
		float pv = nb.g * 0.75 + nb.a * 0.25 + (na.a - 0.5) * 0.02;     // záplaty po metrech, roztřepené okraje
		float pm = smoothstep(0.69, 0.7, pv);
		float pw = fwidth(pv);
		float seam = 1.0 - smoothstep(0.0, 0.004 + pw, abs(pv - 0.695));
		float small = step(0.988, nb.r) * smoothstep(0.35, 0.6, nb.g);    // ojedinělé vysprávky výtluků
		float fresh = max(pm, small * 0.8);
		acol = mix(acol, vec3(0.072, 0.071, 0.07) * (0.9 + 0.2 * na.a), fresh * 0.85);
		acol *= 1.0 - 0.3 * seam;
		rough = mix(rough, 0.76, fresh);
		rough = mix(rough, 0.45, seam);
		patchy = 0.3 + 0.5 * nb.g;
		if (rw > 0.0) {
			float ez = e + (nb.g - 0.5) * 0.3 + (na.a - 0.5) * 0.14;
			float broken = 1.0 - smoothstep(0.02, 0.1, ez);
			acol = mix(acol, vec3(0.13, 0.115, 0.09) * (0.75 + 0.5 * na.r), broken);
			acol *= mix(0.84, 1.0, smoothstep(0.05, 0.5, ez));
			rough = mix(rough, 0.95, broken);
			snow_k = 0.6 + 0.9 * (1.0 - smoothstep(0.3, 1.4, e)) - 0.45 * tr;   // prohrnuto: u krajů víc, stopy čisté
		} else {
			snow_k = 0.5;   // vnitřek křižovatky: prohrnutý jako střed pásů (jinak ostrý bílý mnohoúhelník)
		}
		if (hq) {
			vec4 nc = nzs(g * 0.13 + vec2(0.77));
			float crack = (1.0 - smoothstep(0.0, 0.03, nc.b)) * smoothstep(0.45, 0.68, nb.g) * (1.0 - fresh);
			crack *= 1.0 - smoothstep(20.0, 55.0, dist);
			acol *= 1.0 - 0.55 * crack;
			puddle = smoothstep(0.5, 0.8, tr + nb.a * 0.4 - 0.15) * (1.0 - fresh);
			wn = bump_world(n, wpos, (stone * 0.002 - crack * 0.002) * (1.0 - smoothstep(4.0, 15.0, dist)));
		}
		alb = acol * base_tint;
		wet_rough = 0.16;
	} else {
		// --- štěrková / polní cesta: oblázky, ujeté koleje, travnatý pruh uprostřed, okraje do trávy
		vec2 g = wpos.xz;
		vec4 na = nzs(g * 0.6);
		vec4 nb = nzs(g * 0.05 + vec2(0.13, 0.61));
		vec3 base = base_tint * 0.62;
		float gap = smoothstep(0.0, 0.1, na.b);
		vec3 gcol = base * (0.65 + 0.6 * na.r) * mix(0.55, 1.0, gap);
		gcol *= mix(vec3(1.0), vec3(1.05, 0.97, 0.88), nb.a);
		gcol *= 0.85 + 0.3 * nb.g;
		rough = 0.95;
		patchy = 0.3 + 0.6 * nb.g;
		vec3 grass = mix(vec3(0.15, 0.13, 0.065), vec3(0.05, 0.1, 0.025), clamp(grass_green, 0.0, 1.0)) * (0.75 + 0.5 * na.r);
		if (road_uv && UV.y > 0.0) {
			float rw = UV.y;
			vec2 ee = road_e(UV);
			float e = ee.x;
			float hw = 0.5 * rw;
			float tr = 0.0;
			if (rw > 2.2) {
				tr = (1.0 - smoothstep(0.12, 0.4, abs(ee.y - max(hw - 0.75, 0.3)))) * (0.6 + 0.4 * nb.a);
			}
			gcol = mix(gcol, base * vec3(0.8, 0.72, 0.6) * (0.8 + 0.3 * na.a), tr * 0.75);
			rough = mix(rough, 0.82, tr);
			float gs = (1.0 - smoothstep(0.2, 0.42, abs(ee.y - hw) + (na.a - 0.5) * 0.25)) * step(2.4, rw) * smoothstep(0.3, 0.6, nb.g + 0.25);
			float ez = e + (nb.g - 0.5) * 0.35 + (na.a - 0.5) * 0.2;
			float side = 1.0 - smoothstep(0.0, 0.3, ez);
			gcol = mix(gcol, grass, max(gs, side * 0.85));
			puddle = tr * smoothstep(0.5, 0.75, nb.a);
			snow_k = 1.0 - 0.35 * tr;
		}
		alb = gcol;
		wet_rough = 0.35;
	}

	// --- zdi: sokl, vlhkost a odstřik u paty, šmouhy a stín pod okapem
	float under_eave = 1.0;
	if (mat_kind == 1 && wall_cols && abs(n.y) < 0.5) {
		float hg = wpos.y - UV.x - 0.5;           // výška nad terénem (pata zdi ~0,5 m pod terénem)
		float dtop = UV.y - wpos.y;              // vzdálenost pod okapem
		float hb = hash12(floor(tint.rg * 251.0) + floor(tint.bg * 97.0));
		float sokl_h = 0.36 + 0.26 * hb;
		vec3 scol = mix(vec3(0.16, 0.155, 0.15), tint * 0.55, hb < 0.5 ? 0.25 : 0.7);
		float ew = max(fwidth(hg), 0.004);
		float sk = 1.0 - smoothstep(sokl_h - ew, sokl_h + ew, hg);
		alb = mix(alb, scol * (0.88 + 0.18 * wnz.a + 0.1 * hash12(floor(wuv * 90.0)) * (1.0 - smoothstep(4.0, 12.0, dist))), sk);   // brizolit
		rough = mix(rough, 0.95, sk);
		float damp = (1.0 - smoothstep(0.0, 0.3 + 0.4 * wnz.g, hg - sokl_h)) * (1.0 - sk) * 0.12;
		alb *= 1.0 - damp;
		alb *= mix(vec3(0.8, 0.77, 0.72), vec3(1.0), smoothstep(0.0, 0.3, hg + (wnz.a - 0.5) * 0.12));   // odstřik
		ao *= mix(0.6, 1.0, smoothstep(-0.05, 0.35, hg));
		if (!use_tex || hq) {
			vec4 ns = nzs(vec2(wuv.x * 0.7, wpos.y * 0.025) + vec2(0.29, 0.83));
			// šmouhy jen těsně pod okapem (~do 1 m), ne přes celou zeď
			float streak = smoothstep(0.58, 0.85, ns.g) * exp(-max(dtop, 0.0) / 0.7);
			alb *= 1.0 - 0.16 * streak * vec3(0.9, 0.96, 1.0);
		}
		alb *= mix(0.92, 1.0, smoothstep(0.0, 0.5, dtop));
		ao *= mix(0.55, 1.0, smoothstep(0.0, 0.7, dtop));
		under_eave = min(1.0, smoothstep(0.0, 1.2, dtop) * 0.5 + 0.5 * (1.0 - smoothstep(0.0, 0.5, hg)) + 0.5 * smoothstep(1.2, 3.0, dtop));   // pod přesahem sucho
		wet_rough = 0.5;
	}
	if (use_tex && mat_kind == 2 && hq && n.y > 0.3 && n.y < 0.985) {
		vec4 nb = nzs(wpos.xz * 0.05 + vec2(0.71, 0.23));
		float north = dot(normalize(n.xz + vec2(1e-4)), north_xz);
		alb = mix(alb, vec3(0.05, 0.068, 0.022), smoothstep(0.0, 0.75, north) * smoothstep(0.55, 0.8, nb.g) * 0.7);
	}
	if (use_tex && mat_kind == 3 && road_uv) {
		snow_k = 0.5;
		if (UV.y > 0.0) {
			float e = road_e(UV).x;
			alb *= mix(0.8, 1.0, smoothstep(0.03, 0.45, e));
			snow_k = 0.6 + 0.9 * (1.0 - smoothstep(0.3, 1.4, e));
		}
	}

	// --- sníh na střechách a cestách (plochy natočené vzhůru), mokro – tmavší a lesklejší, louže
	float snow = clamp((snow_cover * snow_amount * snow_k * 1.4 - (1.0 - patchy) * 0.25) * 1.8, 0.0, 1.0) * smoothstep(0.35, 0.7, n.y);
	float wet = clamp(wetness * wet_boost, 0.0, 1.0) * (1.0 - snow) * (0.4 + 0.6 * clamp(n.y, 0.0, 1.0));
	if (mat_kind == 1) {
		wet *= under_eave;
	}
	float pud = puddle * smoothstep(0.25, 0.75, wetness) * (1.0 - snow);
	alb *= 1.0 - 0.3 * wet - 0.25 * pud;
	ALBEDO = mix(alb, vec3(0.9, 0.92, 0.96), snow);
	ROUGHNESS = mix(mix(mix(rough, wet_rough, wet), 0.03, pud), 0.7, snow);
	SPECULAR = mix(0.5, 0.7, max(wet, pud));   // mokrý povrch leskne víc (za sucha původní 0,5)
	AO = ao;
	wn = normalize(mix(wn, n, max(pud, snow * 0.7)));
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
}
