// Hladina potoků, řeky a rybníků (Water) – varianta pro Vysokou a Ultra (gfx_quality ≥ 2): lom ze screen texture,
// útlum a rozptyl po kanálech (Beer-Lambert), odraz břehů a stromů pochodem paprsku po hloubkovém bufferu (Ultra
// víc kroků), dvoufázové proudění podle sklonu, kapky deště, poryvy větru na rybníce. Tělo: include/water.gdshaderinc.
shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_disabled, specular_schlick_ggx;

#define WATER_HQ
#include "res://shaders/include/water.gdshaderinc"
