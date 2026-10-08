shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_disabled, specular_schlick_ggx;
// Реалистичный речной лёд:
//  * полупрозрачный — сквозь него видна тёмная вода;
//  * трещины на трёх глубинах (глубокие сдвигаются при движении камеры — эффект толщи льда);
//  * пузырьки воздуха внутри;
//  * изморозь на поверхности.

uniform vec3 shallow_color : source_color = vec3(0.62, 0.86, 0.98);
uniform vec3 deep_color : source_color = vec3(0.1, 0.32, 0.55);
uniform vec3 crack_color : source_color = vec3(0.92, 0.97, 1.0);
uniform vec3 frost_color : source_color = vec3(0.9, 0.95, 1.0);
uniform float base_alpha = 0.72;

varying vec3 wpos;

vec2 hash2(vec2 p) {
	p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return fract(sin(p) * 43758.5453);
}

float hash1(vec2 p) {
	return fract(sin(dot(p, vec2(41.3, 289.1))) * 15731.743);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash1(i);
	float b = hash1(i + vec2(1.0, 0.0));
	float c = hash1(i + vec2(0.0, 1.0));
	float d = hash1(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// Сеть трещин (границы ячеек Вороного)
float cracks(vec2 p, float width) {
	vec2 ip = floor(p);
	vec2 fp = fract(p);
	float f1 = 8.0;
	float f2 = 8.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec2 r = g + hash2(ip + g) - fp;
			float d = dot(r, r);
			if (d < f1) {
				f2 = f1;
				f1 = d;
			} else if (d < f2) {
				f2 = d;
			}
		}
	}
	float edge = sqrt(f2) - sqrt(f1);
	return 1.0 - smoothstep(0.0, width, edge);
}

// Пузырьки: редкие маленькие кружки
float bubbles(vec2 p) {
	vec2 ip = floor(p);
	vec2 fp = fract(p);
	vec2 c = hash2(ip) * 0.8 + 0.1;
	float present = step(0.72, hash1(ip + 7.0));
	float r = 0.06 + 0.08 * hash1(ip + 3.0);
	float d = length(fp - c);
	return present * (1.0 - smoothstep(r * 0.6, r, d));
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 view_dir = normalize(CAMERA_POSITION_WORLD - wpos);
	vec2 par = view_dir.xz / max(view_dir.y, 0.2);

	float tint = vnoise(wpos.xz * 0.07) * 0.6 + vnoise(wpos.xz * 0.25) * 0.4;
	vec3 col = mix(deep_color, shallow_color, 0.3 + 0.45 * tint);

	// Трещины: глубокие (бледные) → средние → поверхностные (яркие)
	float deep_c = cracks((wpos.xz - par * 1.2) * 0.22 + 31.0, 0.05);
	float mid_c = cracks((wpos.xz - par * 0.5) * 0.45 + 13.0, 0.04);
	float top_c = cracks(wpos.xz * 0.3, 0.025);
	col = mix(col, crack_color, deep_c * 0.25);
	col = mix(col, crack_color, mid_c * 0.45);

	float bub = bubbles((wpos.xz - par * 0.3) * 3.0) + bubbles((wpos.xz - par * 0.8) * 2.0 + 5.0) * 0.6;
	col = mix(col, crack_color, clamp(bub, 0.0, 1.0) * 0.55);

	col = mix(col, crack_color, top_c * 0.8);

	float frost = smoothstep(0.55, 0.85, vnoise(wpos.xz * 0.5 + 17.0)) * 0.55;
	// Позёмка: длинные полосы снега, вытянутые ветром поперёк озера
	float streak = smoothstep(0.62, 0.9, vnoise(vec2(wpos.x * 0.04, wpos.z * 0.55)) * 0.7
		+ vnoise(wpos.xz * 0.9) * 0.3);
	frost = max(frost, streak * 0.75);
	// Крупные тёмные «окна» чистого льда
	float clear_ice = smoothstep(0.7, 0.9, vnoise(wpos.xz * 0.03 + 5.0));
	col = mix(col, deep_color * 0.9, clear_ice * 0.4 * (1.0 - frost));
	col = mix(col, frost_color, frost);

	ALBEDO = col;
	ROUGHNESS = clamp(0.03 + frost * 0.5 + top_c * 0.25, 0.0, 1.0);
	SPECULAR = 0.75;
	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	ALPHA = clamp(base_alpha + fresnel * 0.25 + top_c * 0.2 + frost * 0.35, 0.0, 0.97);
}
