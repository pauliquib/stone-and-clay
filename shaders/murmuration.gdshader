// M8.10 Murmurace špačků (scripts/fauna/murmuration.gd): jedna MultiMesh, CPU přepočítává boidy v plátcích.
// Poloha mezi přepočty = poslední poloha + rychlost (INSTANCE_CUSTOM.xyz, m/s) × (flock_time − čas přepočtu
// INSTANCE_CUSTOM.w), takže CPU nemusí každý snímek psát transformace všech ptáků. Křídla mávají posunem
// vrcholů podle vzdálenosti od osy těla (fáze podle INSTANCE_ID).
shader_type spatial;
render_mode cull_disabled, specular_disabled;

uniform float flock_time = 0.0;
uniform float flap_hz = 11.0;
uniform float flap_amp = 0.6;
uniform vec3 bird_color : source_color = vec3(0.06, 0.06, 0.07);

void vertex() {
	float age = clamp(flock_time - INSTANCE_CUSTOM.w, 0.0, 0.5);
	vec3 world_off = INSTANCE_CUSTOM.xyz * age;
	// do souřadnic instance (transformace = otočení × měřítko), ať posun nezkreslí měřítko ptáka
	vec3 local_off = (inverse(MODEL_MATRIX) * vec4(world_off, 0.0)).xyz;
	float ph = float(INSTANCE_ID) * 3.8832221;
	float flap = sin(TIME * flap_hz * 6.2831853 + ph);
	VERTEX.y += flap * abs(VERTEX.x) * flap_amp;
	VERTEX += local_off;
}

void fragment() {
	ALBEDO = bird_color;
	ROUGHNESS = 0.9;
}
