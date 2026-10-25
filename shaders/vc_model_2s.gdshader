// Procedurální modely MeshKit – oboustranné plochy (MeshKit.vc_material(…, cull = false)).
shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;
#include "res://shaders/include/vc_model.gdshaderinc"
