shader_type spatial;
// Шаг 141: валун (текстуры Poly Haven) со снегом на всём, что смотрит вверх, и инеем в складках
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D rough_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform int rough_channel = 1;          // ARM: зелёный — шероховатость; отдельная карта — красный
uniform vec3 tint : source_color = vec3(0.92, 0.94, 1.0);
uniform vec3 snow_col : source_color = vec3(0.93, 0.96, 1.0);
uniform float snow_amount = 0.55;       // 0 — без снега, 1 — сугроб
uniform float uv_scale = 1.0;
varying vec3 wn;
varying vec3 wp;

float h2(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float n2(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h2(i), h2(i + vec2(1, 0)), f.x), mix(h2(i + vec2(0, 1)), h2(i + vec2(1, 1)), f.x), f.y);
}

void vertex() {
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = UV * uv_scale;
	vec3 rock = texture(albedo_tex, uv).rgb * tint;
	vec4 rt = texture(rough_tex, uv);
	float rough = rough_channel == 1 ? rt.g : rt.r;
	float nz = n2(wp.xz * 1.7) * 0.6 + n2(wp.xz * 5.0) * 0.4;
	float up = wn.y + (nz - 0.5) * 0.35;
	float snow = smoothstep(0.62 - snow_amount * 0.45, 0.8 - snow_amount * 0.4, up);
	// у самого льда — тонкая кромка инея
	snow = max(snow, (1.0 - smoothstep(0.0, 0.25, wp.y - 0.05)) * 0.35);
	ALBEDO = mix(rock, snow_col, snow);
	ROUGHNESS = mix(rough, 0.82, snow);
	NORMAL_MAP = mix(texture(normal_tex, uv).rgb, vec3(0.5, 0.5, 1.0), snow * 0.8);
	SPECULAR = mix(0.4, 0.25, snow);
}
