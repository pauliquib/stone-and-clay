// M8.14 Přízemní vegetace – sdílené globální vstupy pro trávu, obilí a terén:
//   * sešlapání kolem kamery (interaktivní tráva): zdroje (hráč, NPC, zvířata, kola + stopa za nimi, která se
//     za ~30 s narovná) v malé textuře `trample_src` – N × 1 RGBA32F: x, z, poloměr (m), síla 0..1. Plní ji klient
//     (`GroundVegFx`) jednou za 2 snímky, zdroje jsou zhuštěné na začátek (`trample_n` = počet platných, 0 = vypnuto).
//     Místo rastru 512² se tak nepíše nic na GPU (1 malý upload) a smyčka běží jen u rostlin blíž než `trample_range`.
//   * výška porostu louky (seč, pastva) `meadow_h` – R8 relativní výška 0..1 (1 = neposekaná) na mřížce `Meadows`
//     (16 m), aktualizace 1× za den; mimo louky 1.
//   * pěšiny `path_tex` – R8 opotřebení 0..1 v kruhovém bufferu 3 × 3 dlaždic po 64 m (1 m/px, `Footpaths`);
//     pixel = (svět px) mod velikost okna, platné okno `path_origin` + `path_size` (0 = vypnuto).
// Podle čeho: stéblo se při sešlapu sklopí od zdroje kolem patky (zachová délku – rotace, ne posun), relaxace ~30 s
// je lineární pokles síly zdroje (klient). Pěšina = kumulované opotřebení s exponenciálním zarůstáním (Footpaths).
//
// Pozor (M8.4): žádný parametr ani lokální proměnná tady se nesmí jmenovat jako `uniform` shaderu, který soubor
// vkládá (vegetation.gdshader – uniformy mají předponu `veg_`, terrain.gdshader).

global uniform sampler2D trample_src;
global uniform float trample_n;
global uniform float trample_bend;
global uniform float trample_range;
global uniform sampler2D meadow_h;
global uniform vec2 meadow_origin;
global uniform vec2 meadow_size;
global uniform float meadow_k;
global uniform sampler2D path_tex;
global uniform vec2 path_origin;
global uniform float path_size;
global uniform float path_k;

const int GV_TRAMPLE_MAX = 48;          // = GroundVegFx.SRC_N (šířka textury zdrojů)

// Relativní výška porostu louky 0..1 v bodě (1 = plná / mimo louku).
float gv_meadow_rel(vec2 xz) {
	if (meadow_size.x <= 0.0 || meadow_size.y <= 0.0) {
		return 1.0;
	}
	vec2 muv = (xz - meadow_origin) / meadow_size;
	if (muv.x < 0.0 || muv.y < 0.0 || muv.x > 1.0 || muv.y > 1.0) {
		return 1.0;
	}
	return mix(1.0, textureLod(meadow_h, muv, 0.0).r, clamp(meadow_k, 0.0, 1.0));
}

// Opotřebení pěšinou 0..1 v bodě (bilineárně z kruhového bufferu).
float gv_path_wear(vec2 xz) {
	if (path_size <= 0.0) {
		return 0.0;
	}
	vec2 rel = xz - path_origin;
	if (rel.x < 0.0 || rel.y < 0.0 || rel.x >= path_size || rel.y >= path_size) {
		return 0.0;
	}
	vec2 tsz = vec2(textureSize(path_tex, 0));
	vec2 pp = xz / path_size * tsz - 0.5;
	vec2 p0 = floor(pp);
	vec2 fr = pp - p0;
	ivec2 ia = ivec2(mod(p0, tsz));
	ivec2 ib = ivec2(mod(p0 + 1.0, tsz));
	float w00 = texelFetch(path_tex, ia, 0).r;
	float w10 = texelFetch(path_tex, ivec2(ib.x, ia.y), 0).r;
	float w01 = texelFetch(path_tex, ivec2(ia.x, ib.y), 0).r;
	float w11 = texelFetch(path_tex, ib, 0).r;
	return mix(mix(w00, w10, fr.x), mix(w01, w11, fr.x), fr.y) * path_k;
}

// Sešlapání: posun vrcholu ve světových metrech. `root_w` pata rostliny, `hv` výška vrcholu nad patou (m, svět),
// `tk` citlivost typu (0 = nehýbe se), `cam_w` poloha kamery. Stéblo se sklopí od zdrojů o úhel ∝ součtu tlaků.
vec3 gv_trample(vec3 root_w, float hv, float tk, vec3 cam_w) {
	if (trample_n < 0.5 || tk <= 0.0 || hv <= 0.0) {
		return vec3(0.0);
	}
	if (distance(root_w.xz, cam_w.xz) > trample_range) {
		return vec3(0.0);
	}
	vec2 push = vec2(0.0);
	int cnt = min(int(trample_n), GV_TRAMPLE_MAX);
	for (int i = 0; i < cnt; i++) {
		vec4 src = texelFetch(trample_src, ivec2(i, 0), 0);
		vec2 dd = root_w.xz - src.xy;
		float rr = max(src.z, 0.05);
		float ll = length(dd);
		if (ll < rr) {
			vec2 dn = ll > 0.001 ? dd / ll : vec2(0.7071, 0.7071);
			push += dn * (1.0 - ll / rr) * src.w;
		}
	}
	float pl = length(push);
	if (pl < 0.002) {
		return vec3(0.0);
	}
	vec2 dir = push / pl;
	float th = clamp(pl * trample_bend * tk, 0.0, 1.0) * 1.35;   // až ~77° – rozhrnutá, ne položená
	return vec3(dir.x * hv * sin(th), hv * (cos(th) - 1.0), dir.y * hv * sin(th));
}
