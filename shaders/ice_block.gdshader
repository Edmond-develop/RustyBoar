shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, specular_schlick_ggx;
// Глыба льда, в которую вмёрз дрон: гранёная, полупрозрачная — дрон виден внутри.
// cracks 0..1 — сколько трещин (растёт, пока игрок раскалывает лёд).

uniform float cracks : hint_range(0.0, 1.0) = 0.0;

varying vec3 lp;

vec3 hash33(vec3 p) {
	p = vec3(dot(p, vec3(127.1, 311.7, 74.7)), dot(p, vec3(269.5, 183.3, 246.1)), dot(p, vec3(113.5, 271.9, 124.6)));
	return fract(sin(p) * 43758.5453);
}

// Границы ячеек: тонкие линии трещин внутри льда
float cell_edges(vec3 p, out float cell_id) {
	vec3 ip = floor(p);
	vec3 fp = fract(p);
	float f1 = 8.0;
	float f2 = 8.0;
	cell_id = 0.0;
	for (int z = -1; z <= 1; z++) {
		for (int y = -1; y <= 1; y++) {
			for (int x = -1; x <= 1; x++) {
				vec3 g = vec3(float(x), float(y), float(z));
				vec3 h = hash33(ip + g);
				vec3 r = g + h - fp;
				float d = dot(r, r);
				if (d < f1) {
					f2 = f1;
					f1 = d;
					cell_id = h.x;
				} else if (d < f2) {
					f2 = d;
				}
			}
		}
	}
	return sqrt(f2) - sqrt(f1);
}

void vertex() {
	lp = VERTEX;
}

void fragment() {
	// гранёный вид: нормаль каждой грани плоская
	vec3 n = normalize(cross(dFdx(VERTEX), dFdy(VERTEX)));
	if (dot(n, VIEW) < 0.0) {
		n = -n;
	}
	NORMAL = n;
	float fres = pow(1.0 - clamp(dot(n, VIEW), 0.0, 1.0), 2.0);
	float id;
	float e = cell_edges(lp * 2.6, id);
	// трещин становится больше: «включаются» всё новые грани ячеек
	float active = step(id, cracks * 1.1);
	float crack = (1.0 - smoothstep(0.0, 0.03 + cracks * 0.05, e)) * active * smoothstep(0.02, 0.15, cracks);
	float id2;
	float frost = 1.0 - smoothstep(0.0, 0.08, cell_edges(lp * 6.0 + 3.0, id2));
	ALBEDO = mix(vec3(0.55, 0.8, 0.95), vec3(0.95, 0.99, 1.0), clamp(fres * 0.6 + crack + frost * 0.25, 0.0, 1.0));
	ROUGHNESS = 0.06 + frost * 0.2;
	SPECULAR = 0.85;
	EMISSION = vec3(crack * 0.35);
	ALPHA = clamp(0.32 + fres * 0.45 + crack * 0.6 + frost * 0.12, 0.0, 0.95);
}
