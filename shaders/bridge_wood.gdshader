shader_type spatial;
render_mode world_vertex_coords;
// Шаг 102: доски моста — один MultiMesh (один вызов отрисовки), форму моста считает видеокарта.
// INSTANCE_CUSTOM = (t середины доски, состояние 0 нет / 1 старая / 2 новая, укладка 0…1, зерно случайности)
#include "res://shaders/bridge_deform.gdshaderinc"
uniform vec3 old_col : source_color = vec3(0.36, 0.3, 0.24);
uniform vec3 new_col : source_color = vec3(0.72, 0.55, 0.34);
uniform float half_w = 0.86;
uniform float plank_len = 0.5;
// шаг 132: фото-текстура досок (Poly Haven wood_planks): каждая доска моста — одна полоса текстуры
uniform sampler2D wood_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D wood_nrm : hint_normal, filter_linear_mipmap, repeat_enable;
uniform float use_tex = 0.0;
varying float v_state;
varying vec3 v_loc;
varying float v_seed;

float h1(float n) {
	return fract(sin(n * 12.9898) * 43758.5453);
}

void vertex() {
	vec4 c = INSTANCE_CUSTOM;
	float st = c.y;
	float fill = clamp(c.z, 0.0, 1.0);
	float sd0 = c.w;
	bool old = st < 1.5;
	float width = half_w * 2.0 + mix(-0.12, 0.06, h1(sd0));
	float len = plank_len * mix(0.74, 0.86, h1(sd0 + 1.7));
	float yaw = old ? mix(-0.05, 0.05, h1(sd0 + 3.1)) : 0.0;
	float rl = old ? mix(-0.04, 0.04, h1(sd0 + 5.3)) : 0.0;
	float xo = old ? mix(-0.03, 0.03, h1(sd0 + 7.9)) : 0.0;
	vec3 v = VERTEX;
	float lx = v.x * width;
	float lz = v.z * len * max(fill, 0.001);
	float lx2 = lx * cos(yaw) - lz * sin(yaw) + xo;
	float lz2 = lx * sin(yaw) + lz * cos(yaw);
	float ly = v.y * 0.06 - 0.03 + lx2 * rl + (1.0 - fill) * 0.4;
	vec3 o;
	vec3 sd;
	vec3 up;
	vec3 tg;
	br_frame(clamp(c.x + lz2 / br_len, 0.0, 1.0), o, sd, up, tg);
	if (st < 0.5) {
		VERTEX = o - up * 50.0;
	} else {
		VERTEX = o + sd * lx2 + up * ly;
	}
	NORMAL = normalize(sd * NORMAL.x + up * NORMAL.y + tg * NORMAL.z);
	TANGENT = normalize(sd * TANGENT.x + up * TANGENT.y + tg * TANGENT.z);
	BINORMAL = normalize(sd * BINORMAL.x + up * BINORMAL.y + tg * BINORMAL.z);
	v_state = st;
	v_loc = v;
	v_seed = sd0;
}

void fragment() {
	vec3 col = v_state > 1.5 ? new_col : old_col;
	col *= 0.9 + 0.1 * h1(v_seed + 11.0);
	if (use_tex > 0.5) {
		float stripe = floor(h1(v_seed + 4.4) * 9.0);
		vec2 uv = vec2(v_loc.x * 0.37 + h1(v_seed + 6.6), (stripe + 0.5 + v_loc.z * 0.8) / 9.0);
		vec3 tx = texture(wood_tex, uv).rgb;
		vec3 tint = v_state > 1.5 ? vec3(1.25, 1.12, 1.0) : vec3(0.78, 0.74, 0.7);
		col = tx * tint * (0.92 + 0.12 * h1(v_seed + 11.0));
		if (v_state < 1.5) {
			col = mix(col, vec3(dot(col, vec3(0.33))), 0.35);     // старые — выцветшие, серые
		}
		NORMAL_MAP = texture(wood_nrm, uv).rgb;
	} else {
	// волокна поперёк моста (вдоль доски) и годовые кольца на торцах
	float grain = 0.9 + 0.07 * sin(v_loc.z * 38.0 + sin(v_loc.x * 4.0 + v_seed) * 1.6 + v_seed * 7.0) + 0.03 * sin(v_loc.z * 140.0 + v_seed * 3.0);
	float knot = smoothstep(0.06, 0.0, length(vec2(v_loc.x - (h1(v_seed + 2.0) - 0.5) * 0.7, v_loc.z * 0.3)));
	col *= grain * (1.0 - 0.35 * knot);
	if (v_state < 1.5) {
		col *= 0.85 + 0.15 * h1(floor(v_loc.x * 7.0) + v_seed);   // старые — потемневшие пятнами
	}
	}
	ALBEDO = col;
	ROUGHNESS = v_state > 1.5 ? 0.8 : 0.95;
	SPECULAR = 0.25;
}
