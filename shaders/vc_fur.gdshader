// Srst zvířat (QuadrupedModel.fur_material) – barvy vrcholů v sRGB, odstín jedince, oboustranné plochy.
shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;
#define VC_FUR
#include "res://shaders/include/vc_model.gdshaderinc"
