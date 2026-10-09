shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded;
// Воронка снежного вихря: полупрозрачные закрученные полосы снега,
// которые бегут вверх и вращаются. Края мягко растворяются.

uniform vec3 snow_color : source_color = vec3(0.92, 0.95, 1.0);
uniform float spin = 2.5;
uniform float rise = 1.2;
uniform float density = 0.55;

varying vec3 lpos;

float hash1(vec2 p) {
	return fract(sin(dot(p, vec2(41.3, 289.1))) * 15731.743);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash1(i), hash1(i + vec2(1.0, 0.0)), f.x),
		mix(hash1(i + vec2(0.0, 1.0)), hash1(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	lpos = VERTEX;
}

void fragment() {
	float ang = atan(lpos.z, lpos.x) / 6.2831853 + 0.5;
	float h = lpos.y;
	// Закрученные полосы: угол смещается с высотой и временем
	vec2 uv = vec2(ang * 6.0 + h * 0.35 - TIME * spin, h * 0.6 - TIME * rise);
	float n = vnoise(uv * vec2(1.0, 1.5)) * 0.65 + vnoise(uv * 3.1 + 7.0) * 0.35;
	float streak = smoothstep(0.45, 0.85, n);
	// Мягко растворяем низ, верх и «боковой» вид
	float fade_v = smoothstep(0.0, 1.5, h + 4.5) * (1.0 - smoothstep(2.5, 4.5, h));
	float facing = abs(dot(NORMAL, VIEW));
	ALBEDO = snow_color;
	ALPHA = streak * density * fade_v * (0.35 + 0.65 * facing);
}
