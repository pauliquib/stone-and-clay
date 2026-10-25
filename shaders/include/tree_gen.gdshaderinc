// M8.8 Generátor stromů – sdílené funkce pro LOD pásma (prolínání ditherem po instancích) a atlasy listí / kůry.
// Používá shaders/tree.gdshader (LOD0, LOD1 – mesh z tools/treegen) a shaders/tree_impostor.gdshader (dálka).
//
// LOD pásmo instance: vec4(od, do, půlšířka prolínání, 0) v metrech od HLAVNÍ kamery (MAIN_CAM_INV_VIEW_MATRIX – stejně
// i ve stínovém průchodu, jinak by stíny bral jiný LOD než obraz). Mimo pásmo ± prolínání se instance zhroutí do bodu
// (vertex shader, nulová plocha → rasterizér ji zahodí). V pásmu prolínání se bližší a vzdálenější LOD doplňují
// stejným ditherem (pixel patří právě jednomu) → přechod bez „blikání“ a bez děr.
//
// Pozor (M8.4): parametry funkcí tady se NESMÍ jmenovat jako uniformy shaderů, které soubor vkládají (`lod_band`,
// `leaf_atlas`, `bark_atlas`, `atlas_grid`…) → „Redefinition of …“. Proto přípony `_v` / `_in`.

const float TG_LEAF_MEAN = 0.62;        // průměrný jas atlasu listí (shodně s tools/treegen/textures.py LEAF_MEAN)
const float TG_ALPHA_MIP = 0.25;        // zesílení alfy listí v menších mipmapách (listy v dálce neprořídnou)
const float TG_TILE_PX = 512.0;         // px dlaždice atlasu
const vec3 TG_LEAF_BACKLIGHT = vec3(1.0, 1.1, 0.6);   // 2026-10: barva světla prošlého listem (žlutozelená), LOD i impostor

// 2026-10: variace odstínu a jasu koruny podle stromu (hash polohy) – stejně v tree.gdshader i v impostoru.
vec3 tg_tree_var(float h_in) {
	return mix(vec3(0.93, 1.0, 1.06), vec3(1.07, 1.02, 0.86), h_in) * (0.9 + 0.2 * fract(h_in * 7.31));
}

// x = náběh pásma 0..1 (0 = před začátkem), y = doběh 0..1 (1 = za koncem). band_v.z <= 0 → bez pásma.
vec2 tg_band_fade(float dist_v, vec4 band_v) {
	float fin = 1.0;
	if (band_v.x > 0.0) {
		fin = smoothstep(band_v.x - band_v.z, band_v.x + band_v.z, dist_v);
	}
	float fout = smoothstep(band_v.y - band_v.z, band_v.y + band_v.z, dist_v);
	return vec2(fin, fout);
}

bool tg_band_outside(float dist_v, vec4 band_v) {
	return band_v.z > 0.0 && (dist_v < band_v.x - band_v.z || dist_v > band_v.y + band_v.z);
}

// Interleaved gradient noise (Jimenez 2014) – stabilní dither podle pixelu.
float tg_dither(vec2 frag_v) {
	return fract(52.9829189 * fract(dot(frag_v, vec2(0.06711056, 0.00583715))));
}

// Zahodit pixel v pásmu prolínání? Vzdálenější LOD drží pixely h < náběh, bližší h >= doběh – doplňují se.
bool tg_dither_out(vec2 frag_v, vec2 fade_v) {
	float h = tg_dither(frag_v);
	return h >= fade_v.x || h < fade_v.y;
}

// UV dlaždice `tile_v` v atlasu s mřížkou grid_v (sloupce, řádky); uv_in 0..1 uvnitř dlaždice.
vec2 tg_tile_uv(vec2 uv_in, float tile_v, vec2 grid_v) {
	vec2 o = vec2(mod(tile_v, grid_v.x), floor(tile_v / grid_v.x));
	return (o + uv_in) / grid_v;
}

// Kůra: UV se opakuje (fract) uvnitř dlaždice; derivace z neořezaných UV → bez švů v mipmapách.
vec3 tg_bark(sampler2D atlas_in, vec2 uv_in, float tile_v, vec2 grid_v) {
	vec2 uv = tg_tile_uv(fract(uv_in), tile_v, grid_v);
	return textureGrad(atlas_in, uv, dFdx(uv_in) / grid_v, dFdy(uv_in) / grid_v).rgb;
}

// Listí: karta 0..1 v dlaždici; mip omezený a alfa zesílená podle mipu (Golus 2017) – koruna v dálce neprořídne.
vec4 tg_leaf(sampler2D atlas_in, vec2 uv_in, float tile_v, vec2 grid_v) {
	vec2 uvc = clamp(uv_in, vec2(0.004), vec2(0.996));
	vec2 dx = dFdx(uv_in) * TG_TILE_PX;
	vec2 dy = dFdy(uv_in) * TG_TILE_PX;
	float lod = clamp(0.5 * log2(max(dot(dx, dx), dot(dy, dy))), 0.0, 5.0);
	vec4 t = textureLod(atlas_in, tg_tile_uv(uvc, tile_v, grid_v), lod);
	t.a *= 1.0 + lod * TG_ALPHA_MIP;
	return t;
}

float tg_hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float tg_vnoise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(tg_hash(i), tg_hash(i + vec3(1, 0, 0)), f.x), mix(tg_hash(i + vec3(0, 1, 0)), tg_hash(i + vec3(1, 1, 0)), f.x), f.y),
	           mix(mix(tg_hash(i + vec3(0, 0, 1)), tg_hash(i + vec3(1, 0, 1)), f.x), mix(tg_hash(i + vec3(0, 1, 1)), tg_hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}
