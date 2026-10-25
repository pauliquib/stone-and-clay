// Procedurální modely z MeshKit (auta, postavy, zvířata, předměty): barva z vrcholů + levná „materiálovost“.
// Nízká/Střední: jen barva, drsnost, kov a mírné zastínění spodních ploch (pár ALU – cena jako StandardMaterial3D).
// Vysoká/Ultra (gfx_quality ≥ 2): šum v souřadnicích objektu podle odhadnutého druhu materiálu (látka, kov, guma,
// dřevo s letokruhy, srst, lak s metalízou a clearcoatem) – nic nečte z textur, nic se při pohybu „neplaví“.
// Varianty (#define před #include): VC_PAINT = lak auta (barva z uniformy × vrchol, clearcoat jen ≥ Vysoká),
// VC_FUR = srst zvířat (barvy vrcholů v sRGB, odstín jedince, chlupy podél těla).
// Zastínění u země (výška nad zemí) peče do barev vrcholů MeshKit.commit(…, ground_ao) – tady nic nestojí.
// Alfa barvy vrcholu = druh materiálu (MeshKit.tagged): 1 odhad z barvy, 0,9 kůže, 0,8 vlasy, 0,7 látka, 0,6 kůže/obuv,
// 0,5 lesklé (oči), 0,4 jen sRGB (druh odhadem). Označené barvy jsou zadané v sRGB (jako barvy v editoru) – převod
// na lineární ve vertex() (srst vždy).

global uniform float gfx_quality;

uniform float vc_rough : hint_range(0.0, 1.0) = 0.8;
uniform float vc_metal : hint_range(0.0, 1.0) = 0.0;
uniform float vc_emis = 0.0;
#ifdef VC_PAINT
uniform vec4 vc_paint : source_color = vec4(0.7, 0.1, 0.1, 1.0);
uniform float vc_coat = 0.8;
uniform float vc_coat_rough = 0.15;
uniform float vc_low_ao = 1.0;     // síla ztmavení a prachu u země (auto 1, kolo s tenkým rámem méně)
#endif
#ifdef VC_FUR
uniform float vc_tint = 1.0;
#endif

varying vec3 vm_pos;     // poloha v souřadnicích objektu (šum drží na modelu i při pohybu)
varying vec3 vm_wn;      // normála ve světě (zastínění spodku podle skutečného „dolů“)

vec3 vm_srgb_to_linear(vec3 sc) {
	return mix(pow((sc + vec3(0.055)) * (1.0 / 1.055), vec3(2.4)), sc * (1.0 / 12.92), lessThan(sc, vec3(0.04045)));
}

void vertex() {
	vm_pos = VERTEX;
	vm_wn = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
	// barvy zadané v sRGB převést už ve vrcholu (levnější než v každém pixelu)
#ifdef VC_FUR
	COLOR.rgb = vm_srgb_to_linear(COLOR.rgb);
#else
#ifndef VC_PAINT
	if (COLOR.a < 0.95) {
		COLOR.rgb = vm_srgb_to_linear(COLOR.rgb);
	}
#endif
#endif
}

float vm_hash(vec3 hp) {
	hp = fract(hp * 0.3183099 + vec3(0.11, 0.17, 0.13));
	hp *= 17.0;
	return fract(hp.x * hp.y * hp.z * (hp.x + hp.y + hp.z));
}

// hodnotový šum 0..1
float vm_noise(vec3 np) {
	vec3 i = floor(np);
	vec3 f = fract(np);
	f = f * f * (3.0 - 2.0 * f);
	float a = mix(vm_hash(i), vm_hash(i + vec3(1.0, 0.0, 0.0)), f.x);
	float b = mix(vm_hash(i + vec3(0.0, 1.0, 0.0)), vm_hash(i + vec3(1.0, 1.0, 0.0)), f.x);
	float c = mix(vm_hash(i + vec3(0.0, 0.0, 1.0)), vm_hash(i + vec3(1.0, 0.0, 1.0)), f.x);
	float d = mix(vm_hash(i + vec3(0.0, 1.0, 1.0)), vm_hash(i + vec3(1.0, 1.0, 1.0)), f.x);
	return mix(mix(a, b, f.y), mix(c, d, f.y), f.z);
}


void fragment() {
	vec3 col = COLOR.rgb;
#ifdef VC_FUR
	col *= vc_tint;
	col /= 1.0 + 0.3 * col;              // bílá srst / vlna nemá albedo ~0,9 – stlačit jen světlé tóny
	float wool = 1.0 - step(0.95, COLOR.a);
#endif
#ifdef VC_PAINT
	col *= vc_paint.rgb;
#endif
	float rgh = vc_rough;
	float mtl = vc_metal;
	float spec = 0.5;
	// označený druh materiálu (alfa vrcholu < 1): 1 kůže, 2 vlasy, 3 látka, 4 useň / obuv, 5 lesklé (oči)
	int kind = 0;
#ifndef VC_PAINT
#ifndef VC_FUR
	kind = int(round((1.0 - COLOR.a) * 10.0));
	if (kind > 0) {
		if (kind >= 6) {
			kind = 0;                     // jen barva v sRGB, druh odhadnout z barvy
		} else if (kind == 1) {
			rgh = 0.55;                   // kůže: měkký široký odlesk, slabší spekulár
			spec = 0.35;
		} else if (kind == 2) {
			rgh = 0.5;                    // vlasy: lesk podél pramenů
			spec = 0.45;
		} else if (kind == 3) {
			rgh = max(rgh, 0.88);         // látka: matná
			spec = 0.3;
		} else if (kind == 4) {
			rgh = 0.45;                   // useň, pryž bot, pásek
		} else {
			rgh = 0.12;                   // oko, lesklý plast
			spec = 0.6;
		}
	}
#endif
#endif
	// spodní plochy (břicho, podvozek, spodek lavičky) dostanou méně oblohy – mírné ztmavení podle světové normály
	float wny = normalize(vm_wn).y;
	float ao = mix(0.78, 1.0, smoothstep(-0.9, 0.25, wny));
#ifdef VC_PAINT
	// lak: spodek karoserie (prahy, nárazníky u země) tmavší – počátek modelu auta leží na zemi
	ao *= mix(1.0, mix(0.6, 1.0, smoothstep(0.08, 0.6, vm_pos.y)), vc_low_ao);
#endif
	float coat = 0.0;
	if (gfx_quality > 1.5) {
		float dist = length(VERTEX);                          // vzdálenost od kamery – jemný šum v dálce zhasne (bez aliasingu)
		float near_k = 1.0 - smoothstep(6.0, 22.0, dist);
		float broad = vm_noise(vm_pos * 2.3) * 0.6 + vm_noise(vm_pos * 7.1 + vec3(3.1)) * 0.4;
#ifdef VC_PAINT
		// metalíza: drobné šupinky mění drsnost, velkoplošně nepatrná nerovnost laku; clearcoat jen od Vysoké
		float flake = vm_noise(vm_pos * 260.0);
		float flake_k = 1.0 - smoothstep(2.0, 8.0, dist);           // šupinky jen zblízka (dál by zrnily)
		rgh = clamp(rgh + (flake - 0.5) * 0.07 * flake_k + (broad - 0.5) * 0.05, 0.05, 1.0);
		col *= 1.0 + (broad - 0.5) * 0.05;
		// prach a odstřik u spodku
		float dirt = (1.0 - smoothstep(0.15, 0.55, vm_pos.y)) * (0.55 + 0.45 * broad) * vc_low_ao;
		col = mix(col, vec3(0.16, 0.13, 0.10), dirt * 0.35);
		rgh = mix(rgh, 0.85, dirt * 0.6);
		coat = vc_coat * (1.0 - dirt * 0.8);
#else
#ifdef VC_FUR
		// srst: chlupy podél těla (osa Z modelu) – protažený šum, v dálce jen velkoplošné skvrny
		float hair = vm_noise(vm_pos * vec3(140.0, 140.0, 18.0));
		float patch = vm_noise(vm_pos * 3.0);
		col *= 0.9 + 0.2 * patch;
		if (wool > 0.5) {
			// vlna: kudrnaté chomáče (izotropní šum ve dvou měřítkách), stín mezi nimi i zdálky
			float curl = vm_noise(vm_pos * 38.0) * 0.65 + vm_noise(vm_pos * 110.0) * 0.35;
			col *= 0.78 + 0.34 * curl * mix(0.6, 1.0, near_k);
			rgh = 0.95;
		} else {
			col *= 1.0 + (hair - 0.5) * 0.35 * near_k;
			rgh = clamp(rgh + (hair - 0.5) * 0.1, 0.0, 1.0);
		}
#else
		if (kind > 0) {
			// označené díly (postavy): šum podle druhu, ne odhad z barvy
			if (kind == 1) {
				// kůže: jemné prokrvení a póry jen zblízka
				col *= 1.0 + (broad - 0.5) * 0.08;
				col.r *= 1.0 + (vm_noise(vm_pos * 31.0) - 0.5) * 0.06;
				rgh = clamp(rgh + (vm_noise(vm_pos * 210.0) - 0.5) * 0.12 * near_k, 0.3, 0.8);
			} else if (kind == 2) {
				// vlasy: prameny podél svislé osy dílu (hlavy), tmavší mezi prameny
				float strand = vm_noise(vm_pos * vec3(190.0, 9.0, 190.0)) * 0.7 + vm_noise(vm_pos * vec3(420.0, 22.0, 420.0)) * 0.3;
				col *= mix(1.0, 0.72 + 0.5 * strand, 0.4 + 0.6 * near_k);
				rgh = clamp(rgh + (strand - 0.5) * 0.25, 0.3, 0.9);
			} else if (kind == 3) {
				// látka: vazba (jen zblízka), velkoplošné vybledání a zmačkání
				float weave = vm_noise(vm_pos * 180.0) * 0.5 + vm_noise(vm_pos * vec3(320.0, 40.0, 320.0)) * 0.5;
				col *= (1.0 + (broad - 0.5) * 0.16) * (1.0 + (weave - 0.5) * 0.2 * near_k);
			} else if (kind == 4) {
				// useň: odřené světlejší a vrásky
				float crease = vm_noise(vm_pos * vec3(60.0, 160.0, 60.0));
				col *= 1.0 + (broad - 0.5) * 0.2 + (crease - 0.5) * 0.12 * near_k;
				rgh = clamp(rgh + (crease - 0.5) * 0.2, 0.2, 0.9);
			}
		} else {
		// odhad druhu materiálu z barvy a parametrů (jeden materiál MeshKit sdílí mnoho modelů)
		// (metriky z barvy, jak byla zadaná – u barev v sRGB přibližně zpět z lineární)
		vec3 gc = (COLOR.a < 0.95) ? sqrt(col) : col;     // sRGB barvy převedené ve vrcholu → zpět (≈ gama 2)
		float lum = dot(gc, vec3(0.299, 0.587, 0.114));
		float cmax = max(gc.r, max(gc.g, gc.b));
		float sat = (cmax - min(gc.r, min(gc.g, gc.b))) / max(cmax, 0.001);
		float metal_w = smoothstep(0.15, 0.45, mtl);
		float rubber_w = (1.0 - smoothstep(0.05, 0.11, lum)) * (1.0 - metal_w);
		float wood_w = step(gc.b, gc.g) * step(gc.g, gc.r) * smoothstep(0.25, 0.4, sat) * (1.0 - smoothstep(0.75, 0.9, sat))
			* smoothstep(0.05, 0.1, lum) * (1.0 - smoothstep(0.5, 0.65, lum)) * smoothstep(0.6, 0.75, rgh) * (1.0 - metal_w);
		// kůže postav (světlá teplá barva) – bez vazby látky, o něco hladší
		float skin_w = step(gc.b, gc.g) * step(gc.g, gc.r) * smoothstep(0.15, 0.25, sat) * (1.0 - smoothstep(0.5, 0.6, sat))
			* smoothstep(0.5, 0.62, lum) * (1.0 - metal_w);
		float cloth_w = smoothstep(0.62, 0.78, rgh) * (1.0 - wood_w) * (1.0 - rubber_w) * (1.0 - metal_w) * (1.0 - skin_w);
		rgh = mix(rgh, rgh * 0.82, skin_w);
		// všude: velkoplošná nerovnoměrnost odstínu a drsnosti (vybledlé, ohmatané, zaprášené)
		col *= 1.0 + (broad - 0.5) * 0.16;
		rgh = clamp(rgh + (broad - 0.5) * 0.12, 0.04, 1.0);
		// kov: broušení – podélné rýhy, světlejší hrany drsnosti
		if (metal_w > 0.01) {
			float brush = vm_noise(vm_pos * vec3(6.0, 90.0, 6.0));
			rgh = mix(rgh, clamp(rgh * (0.7 + 0.6 * brush), 0.05, 1.0), metal_w);
			col *= 1.0 + (brush - 0.5) * 0.12 * metal_w * near_k;
		}
		// guma / pneumatiky: matná, jemné zrno
		if (rubber_w > 0.01) {
			float grain = vm_noise(vm_pos * 120.0);
			rgh = mix(rgh, 0.88 + grain * 0.1, rubber_w);
			col *= 1.0 + (grain - 0.5) * 0.25 * rubber_w * near_k;
		}
		// dřevo: letokruhy (soustředné kolem svislé osy dílu, rozvlněné šumem) a podélná vlákna
		if (wood_w > 0.01) {
			float warp = vm_noise(vm_pos * vec3(2.0, 0.6, 2.0)) * 1.4;
			float ring = fract((length(vm_pos.xz) + vm_pos.y * 0.15 + warp * 0.12) * 22.0);
			float band = smoothstep(0.0, 0.2, ring) * (1.0 - smoothstep(0.55, 1.0, ring));
			float fiber = vm_noise(vm_pos * vec3(55.0, 4.0, 55.0));
			col *= mix(1.0, (0.82 + 0.16 * band) * (0.92 + 0.16 * fiber), wood_w);
			rgh = mix(rgh, clamp(rgh + (fiber - 0.5) * 0.15, 0.0, 1.0), wood_w);
		}
		// látka: jemná vazba (jen zblízka) a měkčí odlesk
		if (cloth_w > 0.01) {
			float weave = vm_noise(vm_pos * 180.0) * 0.5 + vm_noise(vm_pos * vec3(320.0, 40.0, 320.0)) * 0.5;
			col *= 1.0 + (weave - 0.5) * 0.18 * cloth_w * near_k;
			rgh = mix(rgh, max(rgh, 0.85), cloth_w);
		}
		}
#endif
#endif
	}
	ALBEDO = col * ao;
	ROUGHNESS = rgh;
	METALLIC = mtl;
	SPECULAR = spec * ao;
#ifdef VC_PAINT
	CLEARCOAT = coat;
	CLEARCOAT_ROUGHNESS = vc_coat_rough;
#endif
	if (vc_emis > 0.0) {
		EMISSION = col * vc_emis;
	}
}
