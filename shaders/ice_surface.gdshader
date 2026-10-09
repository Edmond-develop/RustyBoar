shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, specular_schlick_ggx;
// depth_draw_opaque: лёд не закрывает собой то, что внутри него, — трещины видны в толще
// Лёд озера: чистый, тёмный и глубокий — чтобы трещины на нём были хорошо видны.
//  * сквозь лёд видна толща воды: цвет темнеет и меняется большими пятнами;
//  * в глубине — едва заметные старые трещины и пузырьки (сдвигаются при движении камеры);
//  * сверху — редкие пятна инея и искорки; у южного края лёд присыпан снегом;
//  * яркие трещины от шагов рисуются отдельно (ice_cracks.gd), поверх льда.

uniform vec3 shallow_color : source_color = vec3(0.24, 0.47, 0.66);
uniform vec3 deep_color : source_color = vec3(0.02, 0.09, 0.19);
uniform vec3 milky_color : source_color = vec3(0.55, 0.72, 0.86);
uniform vec3 frost_color : source_color = vec3(0.88, 0.94, 1.0);
uniform float base_alpha = 0.86;
uniform float snow_edge_z = 495.0;   // южный край льда: там лёд присыпан снегом
// Слабые участки (x, z, радиус) — их задаёт ice_river.gd. Едва заметны:
// лёд там тоньше — темнее, прозрачнее, без инея, с тонкой паутинкой трещинок.
uniform vec4 weak_spots[32];
// Карта глубины воды (0 — 2 м, 1 — 12 м), её строит ice_river.gd.
// Над глубиной лёд почти чёрный, на мелководье светлее и сквозь него видно дно.
uniform sampler2D depth_map : filter_linear, repeat_disable, hint_default_black;
uniform vec4 depth_rect = vec4(-150.0, 92.0, 300.0, 403.0);
uniform vec3 bed_color : source_color = vec3(0.36, 0.5, 0.52);

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
	return mix(mix(hash1(i), hash1(i + vec2(1.0, 0.0)), f.x),
		mix(hash1(i + vec2(0.0, 1.0)), hash1(i + vec2(1.0, 1.0)), f.x), f.y);
}

float fbm(vec2 p) {
	return vnoise(p) * 0.5 + vnoise(p * 2.03 + 7.1) * 0.3 + vnoise(p * 4.1 + 3.3) * 0.2;
}

// Границы ячеек Вороного — для старых трещин в глубине
float cell_edges(vec2 p, float width) {
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
	return 1.0 - smoothstep(0.0, width, sqrt(f2) - sqrt(f1));
}

float bubbles(vec2 p) {
	vec2 ip = floor(p);
	vec2 fp = fract(p);
	vec2 c = hash2(ip) * 0.8 + 0.1;
	float present = step(0.8, hash1(ip + 7.0));
	float r = 0.04 + 0.06 * hash1(ip + 3.0);
	return present * (1.0 - smoothstep(r * 0.5, r, length(fp - c)));
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 view_dir = normalize(CAMERA_POSITION_WORLD - wpos);
	vec2 par = view_dir.xz / max(view_dir.y, 0.25);

	// Толща: вода под льдом — чем глубже, тем темнее; местами лёд «молочный»
	float depth01 = texture(depth_map, (wpos.xz - depth_rect.xy) / depth_rect.zw).r;
	float depth_n = clamp(depth01 + (fbm(wpos.xz * 0.05) - 0.5) * 0.18, 0.0, 1.0);
	vec3 col = mix(shallow_color, deep_color, smoothstep(0.0, 0.8, depth_n));
	// На мелководье сквозь лёд видно дно: камни и пятна (смещаются при повороте камеры)
	float depth_m = 2.6 + depth01 * 10.0;
	float bed = fbm((wpos.xz - par * depth_m * 0.35) * 0.7);
	float shallow = 1.0 - smoothstep(0.0, 0.35, depth_n);
	col = mix(col, bed_color * (0.55 + 0.7 * bed), shallow * 0.45);
	float milky = smoothstep(0.55, 0.85, fbm(wpos.xz * 0.06 + 13.0));
	col = mix(col, milky_color, milky * 0.25);

	// Старые трещины глубоко во льду: тонкие, бледные, «плавают» при движении камеры
	float deep1 = cell_edges((wpos.xz - par * 1.6) * 0.09 + 31.0, 0.02);
	col = mix(col, milky_color, deep1 * 0.07);

	// Пузырьки воздуха на разной глубине
	float bub = bubbles((wpos.xz - par * 0.4) * 2.5) + bubbles((wpos.xz - par * 1.0) * 1.6 + 5.0) * 0.6;
	col = mix(col, frost_color, clamp(bub, 0.0, 1.0) * 0.3);

	// Слабый лёд: тоньше — сквозь него сильнее видна тёмная вода
	float weak = 0.0;
	for (int i = 0; i < 32; i++) {
		vec4 w = weak_spots[i];
		if (w.z <= 0.0) {
			continue;
		}
		float d = length(wpos.xz - w.xy);
		// неровный край, чтобы пятно не выглядело кругом
		float edge = w.z * (0.85 + 0.25 * vnoise(wpos.xz * 0.6 + w.xy));
		weak = max(weak, 1.0 - smoothstep(edge * 0.55, edge, d));
	}
	col = mix(col, deep_color * 1.25, weak * 0.3);
	float web = cell_edges(wpos.xz * 1.3 + 51.0, 0.03);
	col = mix(col, milky_color, web * weak * 0.22);

	// Редкий иней пятнами (не полосами)
	float frost = smoothstep(0.72, 0.92, fbm(wpos.xz * 0.11 + 17.0)) * 0.55;
	// Южный край присыпан снегом — плавный переход со снега на лёд
	frost *= 1.0 - weak;   // на тонком льду инея нет
	frost = max(frost, smoothstep(snow_edge_z - 7.0, snow_edge_z - 0.5, wpos.z));
	col = mix(col, frost_color, frost);

	// Снизу (из-под воды) лёд — тёмный потолок с бледными прожилками
	if (!FRONT_FACING) {
		col = mix(vec3(0.05, 0.13, 0.17), vec3(0.2, 0.32, 0.36), deep1 * 0.6 + bub * 0.3);
		frost = 0.0;
	}
	ALBEDO = col;
	ROUGHNESS = mix(0.07, 0.75, frost);
	SPECULAR = 0.45;
	// Искорки на изморози
	float glint = step(0.996, hash1(floor(wpos.xz * 9.0))) * frost;
	EMISSION = vec3(glint * 1.5);
	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	ALPHA = clamp(base_alpha + fresnel * 0.12 + frost * 0.3 - weak * 0.08, 0.0, 0.98);
	if (!FRONT_FACING) {
		ALPHA = 0.97;
	}
}
