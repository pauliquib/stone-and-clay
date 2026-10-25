// Hladina potoků, řeky a rybníků (Water) – levná varianta pro Nízkou a Střední (gfx_quality < 2): bez screen texture,
// hladina se míchá s pozadím přes ALPHA podle tloušťky vody z hloubkového bufferu. Tělo: include/water.gdshaderinc.
// Vysoká a Ultra: water_hq.gdshader (lom, Beer-Lambert po kanálech, odraz okolí, kapky deště).
shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_disabled, specular_schlick_ggx;

#include "res://shaders/include/water.gdshaderinc"
