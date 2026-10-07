shader_type spatial;
// Сетка для тестового полигона: помогает видеть скорость и расстояния.
// Клетка = 1 метр, жирная линия — каждые 5 метров.

uniform vec3 base_color : source_color = vec3(0.80, 0.84, 0.89);
uniform vec3 line_color : source_color = vec3(0.60, 0.66, 0.74);
uniform vec3 major_line_color : source_color = vec3(0.40, 0.47, 0.58);
uniform float cell_size = 1.0;
uniform float line_width = 0.02;
uniform float major_every = 5.0;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float grid_line(vec2 coord, float width) {
	vec2 dist = abs(fract(coord + 0.5) - 0.5);
	vec2 aa = fwidth(coord);
	vec2 line = 1.0 - smoothstep(vec2(width), vec2(width) + aa, dist);
	return max(line.x, line.y);
}

void fragment() {
	vec2 coord = world_pos.xz / cell_size;
	float minor = grid_line(coord, line_width);
	float major = grid_line(coord / major_every, line_width * 1.5 / major_every);
	vec3 col = mix(base_color, line_color, minor);
	col = mix(col, major_line_color, major);
	ALBEDO = col;
	ROUGHNESS = 0.85;
}
