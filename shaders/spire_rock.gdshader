shader_type spatial;
// Шаг 84: выступы пропасти — лёгкий шейдер скалы (вместо тяжёлого шейдера рельефа).
// Те же текстуры породы и снега, что у горы: порода с трёх сторон (не тянется на отвесах),
// гранит с пятнами и слоями, на всём, что смотрит вверх, — снег; книзу пропасть темнеет.
// В ~4 раза дешевле на пиксель: в пропасти выступы занимают почти весь экран.

uniform sampler2D rock_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_nrm : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D snow_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float rock_scale = 0.12;
uniform vec3 snow_tint : source_color = vec3(0.72, 0.75, 0.82);
uniform float normal_strength = 1.1;

varying vec3 world_pos;
varying vec3 world_normal;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 N = normalize(world_normal);
	vec3 w = pow(abs(N), vec3(4.0));
	w /= (w.x + w.y + w.z);
	vec3 rp = world_pos * rock_scale;
	vec3 rc = texture(rock_tex, rp.zy).rgb * w.x + texture(rock_tex, rp.xz).rgb * w.y + texture(rock_tex, rp.xy).rgb * w.z;
	vec2 rnx = texture(rock_nrm, rp.zy).rg * 2.0 - 1.0;
	vec2 rny = texture(rock_nrm, rp.xz).rg * 2.0 - 1.0;
	vec2 rnz = texture(rock_nrm, rp.xy).rg * 2.0 - 1.0;
	vec3 pert = vec3(0.0, rnx.y, rnx.x) * w.x + vec3(rny.x, 0.0, rny.y) * w.y + vec3(rnz.x, rnz.y, 0.0) * w.z;
	// гранит: серо-бурый, слои и пятна (как скалы горы)
	float lum = dot(rc, vec3(0.3, 0.5, 0.2));
	vec3 granite = mix(vec3(lum), rc, 0.3) * vec3(0.96, 0.9, 0.85) * 0.85;
	float n1 = vnoise(world_pos.xz * 0.07 + world_pos.y * 0.03);
	float strata = sin(world_pos.y * 0.33 + world_pos.x * 0.04 + n1 * 4.0) * 0.5 + 0.5;
	granite *= mix(0.82, 1.1, strata) * mix(0.8, 1.12, n1);
	// снег на всём, что смотрит вверх (уступы, верхушки)
	float sn = vnoise(world_pos.xz * 0.6) * 0.5 + n1 * 0.5;
	float up = smoothstep(0.55, 0.72, N.y + (sn - 0.5) * 0.3);
	vec3 snow = texture(snow_tex, world_pos.xz * 0.24).rgb * snow_tint;
	vec3 col = mix(granite, snow, up);
	// пропасть книзу темнеет
	col *= mix(1.0, 0.16, smoothstep(-22.0, -58.0, world_pos.y));
	vec3 nw = normalize(N + pert * normal_strength * 1.4 * (1.0 - up));
	NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);
	ALBEDO = col;
	ROUGHNESS = mix(0.95, 0.7, up);
	SPECULAR = mix(0.3, 0.5, up);
}
