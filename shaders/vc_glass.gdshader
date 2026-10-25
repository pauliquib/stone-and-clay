// Tónované sklo vozidel (MeshKit.glass_material). Zvenku tmavé: skutečné sklo propouští ~75 %, tma „za sklem“ je
// stinný interiér – náš interiér je ale osvětlený oblohou a skrz protější okna prosvítá horizont, proto zvenku
// (přední strana plochy – normály karoserie míří ven) vyšší krytí, k okrajům ještě víc (Fresnel). Zevnitř (rubová
// strana: pohled řidiče, protější okna) jen lehký tón, ať je ven dobře vidět. Premultiplied alpha: odlesky oblohy
// a slunce se nezeslabují průhledností. Cena ≈ průhledný StandardMaterial3D, žádné textury – stejné na všech předvolbách.
shader_type spatial;
render_mode blend_premul_alpha, cull_disabled, depth_draw_opaque, diffuse_burley, specular_schlick_ggx;

uniform vec4 glass_tint : source_color = vec4(0.03, 0.045, 0.055, 0.86);
uniform float glass_inside : hint_range(0.0, 1.0) = 0.28;     // krytí při pohledu zevnitř

void fragment() {
	float nv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float fr = pow(1.0 - nv, 4.0);
	float a = mix(FRONT_FACING ? glass_tint.a : glass_inside, 0.96, fr);
	ALBEDO = glass_tint.rgb * a;      // předem vynásobené krytím (premultiplied)
	ALPHA = a;
	METALLIC = 0.0;
	ROUGHNESS = 0.04;
	SPECULAR = 0.45;
}
