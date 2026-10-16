// M8.11 Fenologie stromů (scripts/eko/phenology.gd → globální `pheno_lut`, `pheno_on`):
// INSTANCE_CUSTOM.a stromu = kód (druh × 8 + pásmo teplotního posunu místa + 0,5) / 256; 1,0 = bez kódu (starý vzhled
// z globálních `foliage` / `autumn` podle Seasons). Tabulka `pheno_lut` 16 × 32 (řádek = druh):
//   sloupce 0–6 = stav pro pásmo posunu −3…+3 K: r olistění, g podzimní zbarvení, b kvetení, a jarní přírůst jehličnanů;
//   sloupec 8 = barva podzimu, 9 = barva jara, 10 = barva květů (a = 1 viditelné květy), 11 = r 1 stálezelený.
// Pozor (00_SPOLECNE kap. 6): parametry funkcí se nesmí jmenovat jako uniformy shaderů (foliage, autumn…) – vše má
// předponu `ph_`.
global uniform float pheno_on;
global uniform sampler2D pheno_lut;   // bez hintů (globální uniformy je nemusí podporovat); čte se texelFetch

const int PH_BINS = 8;
const int PH_COL_AUT = 8;
const int PH_COL_SPR = 9;
const int PH_COL_BLOOM = 10;
const int PH_COL_FLAGS = 11;

bool ph_valid(float ph_code) {
	return pheno_on > 0.5 && ph_code < 0.999;
}

ivec2 ph_cell(float ph_code) {
	int c = int(ph_code * 256.0);
	int s = c / PH_BINS;
	return ivec2(c - s * PH_BINS, s);
}

vec4 ph_state(ivec2 ph_c) {
	return texelFetch(pheno_lut, ph_c, 0);
}

vec4 ph_info(ivec2 ph_c, int ph_col) {
	return texelFetch(pheno_lut, ivec2(ph_col, ph_c.y), 0);
}
