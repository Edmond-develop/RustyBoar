shader_type spatial;
render_mode world_vertex_coords;
// Шаг 103: скала пропасти — слои породы, трещины, наледь по стокам, снег на полках; вглубь — темнее и синее.
uniform float top_y = 0.0;
uniform vec3 rock_a : source_color = vec3(0.3, 0.285, 0.28);
uniform vec3 rock_b : source_color = vec3(0.19, 0.185, 0.2);
uniform vec3 rock_c : source_color = vec3(0.37, 0.31, 0.26);
uniform vec3 snow_col : source_color = vec3(0.93, 0.96, 1.0);
uniform vec3 ice_col : source_color = vec3(0.62, 0.8, 0.92);
uniform vec3 deep_col : source_color = vec3(0.03, 0.05, 0.1);
varying vec3 wp;
varying vec3 wn;

float h3(vec3 p) {
	return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453);
}

float n3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(h3(i), h3(i + vec3(1, 0, 0)), f.x), mix(h3(i + vec3(0, 1, 0)), h3(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(h3(i + vec3(0, 0, 1)), h3(i + vec3(1, 0, 1)), f.x), mix(h3(i + vec3(0, 1, 1)), h3(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

float fbm(vec3 p) {
	return n3(p) * 0.55 + n3(p * 2.3 + 5.0) * 0.3 + n3(p * 5.7 - 2.0) * 0.15;
}

void vertex() {
	wp = VERTEX;
	wn = NORMAL;
}

void fragment() {
	vec3 n = normalize(wn);
	float big = fbm(wp * 0.11);
	// слои: наклонные пласты, слегка смятые
	float sy = wp.y * 0.55 + wp.x * 0.07 + wp.z * 0.05 + big * 3.0;
	float band = fract(sy);
	float bid = floor(sy);
	float tone = h3(vec3(bid, 3.0, 1.0));
	vec3 col = mix(rock_a, rock_b, tone);
	col = mix(col, rock_c, smoothstep(0.75, 0.95, h3(vec3(bid, 9.0, 4.0))));
	col *= 0.86 + 0.28 * fbm(wp * vec3(0.9, 2.4, 0.9));
	// шов между пластами и вертикальные трещины
	float seam = smoothstep(0.0, 0.06, band) * smoothstep(1.0, 0.94, band);
	col *= mix(0.55, 1.0, seam);
	// редкие вертикальные трещины-расколы
	float cr = abs(n3(vec3((wp.x + wp.z) * 0.22, wp.y * 0.02, 4.0)) - 0.5);
	col *= mix(0.45, 1.0, smoothstep(0.0, 0.012, cr));
	// наледь: вертикальные потёки
	float streak = smoothstep(0.62, 0.8, n3(vec3((wp.x + wp.z) * 0.35, wp.y * 0.03, 7.0))) * smoothstep(0.3, 0.6, n3(wp * 0.6));
	float ice = streak * (1.0 - smoothstep(0.2, 0.6, n.y));
	col = mix(col, ice_col, ice * 0.75);
	// снег на всём, что смотрит вверх
	float snow = smoothstep(0.58, 0.82, n.y + (fbm(wp * 1.3) - 0.5) * 0.25);
	col = mix(col, snow_col, snow);
	// глубина: темнее и синее
	float dk = clamp((top_y - wp.y) / 55.0, 0.0, 1.0);
	col = mix(col, deep_col, dk * dk * 0.92);
	ALBEDO = col;
	ROUGHNESS = mix(0.92, 0.25, ice) * (1.0 - snow * 0.1);
	SPECULAR = mix(0.2, 0.6, ice);
}
