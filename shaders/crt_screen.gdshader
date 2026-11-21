shader_type spatial;
render_mode unshaded, cull_back;
// Шаг 107: экранчик пульта канатки — старый зелёный кинескоп: строки развёртки, мерцание,
// виньетка; glitch > 0 — помехи после удара (полосы сдвигаются, экран вспыхивает).
uniform vec3 tint : source_color = vec3(0.25, 1.0, 0.45);
uniform float glow = 0.18;
uniform float glitch = 0.0;
uniform float alarm = 0.0;

float hash(float n) {
	return fract(sin(n) * 43758.5453);
}

void fragment() {
	vec2 uv = UV;
	float t = TIME;
	// помехи: строки рвутся и уезжают вбок
	float band = floor(uv.y * 24.0 + t * 30.0);
	uv.x += (hash(band + floor(t * 20.0)) - 0.5) * 0.08 * glitch;
	float scan = 0.78 + 0.22 * sin(uv.y * 420.0);
	float roll = 0.94 + 0.06 * sin(uv.y * 6.0 - t * 2.4);
	vec2 c = uv - 0.5;
	float vig = clamp(1.0 - dot(c, c) * 1.9, 0.0, 1.0);
	float noise = hash(dot(floor(uv * vec2(160.0, 90.0)), vec2(1.0, 57.0)) + floor(t * 24.0));
	vec3 col = tint * glow * scan * roll * vig;
	col += vec3(noise) * (0.03 + 0.25 * glitch);
	col = mix(col, vec3(1.0, 0.2, 0.15) * 0.35 * vig, alarm * (0.5 + 0.5 * sin(t * 12.0)));
	ALBEDO = col;
}
