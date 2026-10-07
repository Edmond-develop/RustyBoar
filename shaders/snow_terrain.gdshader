shader_type spatial;
render_mode cull_disabled;
// Снег на пологих местах, камень на крутых склонах, синий лёд в глубине трещин,
// плюс редкие искорки на снегу.

uniform vec3 snow_color : source_color = vec3(0.94, 0.96, 1.0);
uniform vec3 snow_shade : source_color = vec3(0.78, 0.85, 0.96);
uniform vec3 rock_color : source_color = vec3(0.34, 0.36, 0.42);
uniform vec3 ice_color : source_color = vec3(0.42, 0.7, 0.92);
uniform float sparkle_amount = 1.6;

varying vec3 world_pos;
varying vec3 world_normal;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	float n = vnoise(world_pos.xz * 0.12) * 0.6 + vnoise(world_pos.xz * 0.7) * 0.4;
	float slope = 1.0 - world_normal.y;
	float rock = smoothstep(0.30, 0.48, slope + (n - 0.5) * 0.12);

	vec3 snow = mix(snow_shade, snow_color, n);
	vec3 stone = rock_color * (0.75 + 0.5 * vnoise(world_pos.xz * 1.3 + world_pos.y));
	vec3 col = mix(snow, stone, rock);

	// Глубина трещин и ущелий — голубой лёд
	float deep = smoothstep(-2.0, -12.0, world_pos.y);
	col = mix(col, ice_color * (0.6 + 0.4 * n), deep * 0.85);

	ALBEDO = col;
	ROUGHNESS = mix(0.7, 0.95, rock);

	float g = hash(floor(world_pos.xz * 14.0) + floor(world_pos.y * 14.0));
	float sparkle = step(0.997, g) * (1.0 - rock) * (1.0 - deep);
	EMISSION = vec3(sparkle * sparkle_amount);
}
