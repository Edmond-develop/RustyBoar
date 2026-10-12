shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, specular_schlick_ggx;
// Повреждения поверх модели упавшего корабля: копоть снизу и у носа (где горело),
// подпалины пятнами, светлые царапины от удара о землю.
// Рисуется поверх (material_overlay), там где повреждений нет — прозрачно.

uniform vec2 crash_nose = vec2(0.0, 684.0);
uniform vec2 crash_dir = vec2(0.12, 0.99);   // от носа к хвосту
uniform float ground_y = 0.0;

varying vec3 wp;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.11, 0.17, 0.13));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise3(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1, 0, 0)), f.x), mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x), mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float along = dot(wp.xz - crash_nose, crash_dir);           // 0 у носа, растёт к хвосту
	float n = noise3(wp * 0.8) * 0.6 + noise3(wp * 3.1) * 0.4;
	float low = 1.0 - smoothstep(0.5, 3.5, wp.y - ground_y + (n - 0.5) * 1.5);   // у земли
	float front = 1.0 - smoothstep(2.0, 11.0, along + (n - 0.5) * 4.0);          // нос
	float burn = smoothstep(0.62, 0.72, n) * 0.8;                                   // пятна подпалин
	float soot = clamp(max(max(low, front), burn), 0.0, 1.0);
	// царапины от удара — тонкие светлые полосы вдоль корпуса
	float sc = noise3(vec3(along * 0.4, wp.y * 14.0, 0.0));
	float scratch = smoothstep(0.82, 0.86, sc) * (1.0 - smoothstep(0.5, 2.5, wp.y - ground_y)) * (1.0 - soot * 0.5);
	vec3 col = mix(vec3(0.03, 0.026, 0.024), vec3(0.18, 0.13, 0.1), n * 0.4);
	ALBEDO = mix(col, vec3(0.7, 0.7, 0.72), scratch);
	METALLIC = scratch * 0.9;
	ROUGHNESS = mix(0.95, 0.3, scratch);
	ALPHA = clamp(soot * 0.88 + scratch, 0.0, 0.95);
}
