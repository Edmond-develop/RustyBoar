shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;
// Альпинистская верёвка: плетёная оплётка (косые пряди) яркого цвета
// с тёмной «маркерной» нитью — хорошо видна на снегу.
// UV.x — длина (м), UV.y — по кругу (0..1).

uniform vec3 col_a : source_color = vec3(0.98, 0.45, 0.08);
uniform vec3 col_b : source_color = vec3(0.98, 0.85, 0.2);
uniform vec3 tracer : source_color = vec3(0.08, 0.08, 0.1);
uniform float wet = 0.0;

void fragment() {
	float u = UV.x * 9.0;
	float v = UV.y;
	// две системы косых прядей
	float s1 = fract(u + v * 2.0);
	float s2 = fract(u - v * 2.0);
	float weave = step(0.5, fract((floor(u + v * 2.0) + floor(u - v * 2.0)) * 0.5));
	float strand = weave > 0.5 ? s1 : s2;
	float ridge = sin(strand * 3.14159);
	vec3 col = mix(col_a, col_b, step(0.82, fract(u * 0.25 + v)) * 0.6);
	// маркерная нить
	float tr = step(fract(UV.x * 1.3 + v), 0.07);
	col = mix(col, tracer, tr);
	col *= 0.72 + 0.28 * ridge;
	ALBEDO = col * (1.0 - wet * 0.25);
	ROUGHNESS = mix(0.82, 0.35, wet);
	SPECULAR = 0.35;
	NORMAL = normalize(NORMAL + (ridge - 0.5) * 0.25 * TANGENT);
}
