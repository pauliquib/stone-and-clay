// Obrazovkový efekt opilosti: vlnění, dvojité vidění, rozmazání, tunelové vidění, barvy.
// Parametry řídí BodyState (promile) přes DrunkFx.
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float drunk : hint_range(0.0, 1.0) = 0.0;      // celková opilost
uniform float double_vision : hint_range(0.0, 1.0) = 0.0;
uniform float blur : hint_range(0.0, 1.0) = 0.0;
uniform float tunnel : hint_range(0.0, 1.0) = 0.0;
uniform float blackout : hint_range(0.0, 1.0) = 0.0;   // okno / omdlení
uniform float nausea : hint_range(0.0, 1.0) = 0.0;     // nazelenalý nádech
uniform float hurt : hint_range(0.0, 1.0) = 0.0;       // červený záblesk při zranění
uniform float time_s = 0.0;

vec3 sample_blur(vec2 uv, float lod) {
	return textureLod(screen_tex, uv, lod).rgb;
}

void fragment() {
	vec2 uv = SCREEN_UV;
	float t = time_s;
	// vlnění obrazu
	float w = drunk * 0.012;
	uv += vec2(sin(uv.y * 7.0 + t * 1.3), cos(uv.x * 6.0 + t * 1.1)) * w;
	// pomalé "houpání" celé scény
	uv = (uv - 0.5) * (1.0 - drunk * 0.03 * (0.5 + 0.5 * sin(t * 0.6))) + 0.5;
	float lod = blur * 3.0;
	vec3 col = sample_blur(uv, lod);
	// dvojité vidění – druhý obraz posunutý, pomalu se rozjíždí a sjíždí
	float dv = double_vision * (0.012 + 0.012 * sin(t * 0.8));
	vec2 off = vec2(dv, dv * 0.35 * sin(t * 0.5));
	vec3 col2 = sample_blur(uv + off, lod);
	col = mix(col, col2, double_vision * 0.5);
	// tunelové vidění + vinětace
	vec2 c = SCREEN_UV - 0.5;
	float r = length(c * vec2(1.3, 1.0));
	float vig = smoothstep(0.75 - tunnel * 0.45, 0.2 - tunnel * 0.15, r);
	col *= mix(1.0, vig, clamp(drunk * 0.6 + tunnel, 0.0, 1.0));
	// barvy: přesycení teplými tóny, nevolnost do zelena
	float lum = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(col, vec3(lum), -drunk * 0.2);
	col = mix(col, col * vec3(0.85, 1.05, 0.8), nausea * 0.6);
	col = mix(col, vec3(0.6, 0.0, 0.0), hurt * 0.35 * smoothstep(0.2, 0.7, r));
	col *= 1.0 - blackout;
	COLOR = vec4(col, 1.0);
}
