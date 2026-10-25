// Lak vozidel (CarModel / BikeModel) – barva z uniformy × barva vrcholu, metalíza a clearcoat jen od Vysoké.
shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;
#define VC_PAINT
#include "res://shaders/include/vc_model.gdshaderinc"
