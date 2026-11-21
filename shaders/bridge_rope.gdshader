shader_type spatial;
render_mode world_vertex_coords;
// Шаг 102: канаты и подвески моста — меш в координатах моста, гнёт видеокарта (без пересборки на процессоре).
// mode 0 — канат-трубка: VERTEX = (поперёк, вверх, t); mode 1 — подвеска (MultiMesh): INSTANCE_CUSTOM = (t, поперёк).
#include "res://shaders/bridge_deform.gdshaderinc"
uniform int mode = 0;
uniform float rail_h = 1.05;
uniform vec3 base_col : source_color = vec3(0.93, 0.33, 0.07);
uniform vec3 tracer_col : source_color = vec3(0.05, 0.09, 0.26);
uniform vec3 fleck_col : source_color = vec3(0.96, 0.86, 0.18);
uniform float strands = 16.0;
uniform float pitch = 170.0;
uniform float laid = 0.0;
uniform float dirt = 0.0;
uniform float bump = 1.0;

// высота поверхности (0…1) и номер пряди
vec2 surf(vec2 uv) {
	float a = uv.x;
	float l = uv.y;
	if (laid > 0.5) {
		float s = a * 3.0 - l * pitch;
		float f = fract(s);
		float h = pow(sin(f * 3.14159), 0.55);
		h *= 0.88 + 0.12 * sin((a * 3.0 + l * pitch) * 9.0 + f * 6.0);   // волокна поперёк пряди
		return vec2(h, mod(floor(s), 3.0));
	}
	float s1 = a * strands + l * pitch;
	float s2 = a * strands - l * pitch;
	float top = mod(floor(s1) + floor(s2), 2.0);
	float fu = top > 0.5 ? fract(s1) : fract(s2);
	float fv = top > 0.5 ? fract(s2) : fract(s1);
	float h = sin(fu * 3.14159) * (0.5 + 0.5 * sin(fv * 3.14159));
	h *= 0.9 + 0.1 * sin(fu * 40.0 + fv * 3.0);
	float id = mod(top > 0.5 ? floor(s1) : floor(s2), strands) + top * 100.0;
	return vec2(h, id);
}


void vertex() {
	float t;
	vec2 lp;
	if (mode == 0) {
		t = VERTEX.z;
		lp = VERTEX.xy;
	} else {
		t = INSTANCE_CUSTOM.x + VERTEX.z / br_len;
		lp = vec2(INSTANCE_CUSTOM.y + VERTEX.x, -0.04 + (VERTEX.y + 0.5) * (rail_h + 0.04));
	}
	vec3 o;
	vec3 sd;
	vec3 up;
	vec3 tg;
	br_frame(clamp(t, 0.0, 1.0), o, sd, up, tg);
	vec3 n = NORMAL;
	vec3 ta = TANGENT;
	vec3 bi = BINORMAL;
	VERTEX = o + sd * lp.x + up * lp.y;
	NORMAL = normalize(sd * n.x + up * n.y + tg * n.z);
	TANGENT = normalize(sd * ta.x + up * ta.y + tg * ta.z);
	BINORMAL = normalize(sd * bi.x + up * bi.y + tg * bi.z);
}

void fragment() {
	vec2 sv = surf(UV);
	float h = sv.x;
	float id = sv.y;
	vec3 col = base_col;
	if (laid > 0.5) {
		col = base_col * (0.92 + 0.08 * id);
	} else {
		float fam = id >= 100.0 ? 1.0 : 0.0;
		float m8 = mod(id - fam * 100.0, 8.0);
		if (m8 < 1.0) {
			col = tracer_col;
		} else if (m8 > 3.5 && m8 < 4.5 && fam > 0.5) {
			col = fleck_col;
		} else if (fam < 0.5) {
			col = base_col * vec3(0.92, 0.88, 0.85);
		}
	}
	// вдали — средний цвет (узор мельче пикселя), рельеф гаснет
	float fw = max(fwidth(UV.x * (laid > 0.5 ? 3.0 : strands)), fwidth(UV.y * pitch));
	float aa = clamp(1.4 - fw * 1.2, 0.0, 1.0);
	vec3 mean_col = laid > 0.5 ? base_col * 0.8 : mix(base_col * 0.8, tracer_col, 0.12);
	vec3 woven = col * (0.42 + 0.58 * h);
	ALBEDO = mix(mean_col, woven, aa) * (1.0 - dirt * 0.35);
	// карта нормалей: наклон по высоте в соседних точках
	float e = 0.004;
	float hx = surf(UV + vec2(e, 0.0)).x - surf(UV - vec2(e, 0.0)).x;
	float hy = surf(UV + vec2(0.0, e * 0.25)).x - surf(UV - vec2(0.0, e * 0.25)).x;
	vec3 nm = normalize(vec3(-hx * 2.2 * bump * aa, -hy * 2.2 * bump * aa, 1.0));
	NORMAL_MAP = nm * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 1.0;
	ROUGHNESS = 0.74 + 0.16 * (1.0 - h);
	SPECULAR = 0.32;
	AO = mix(1.0, 0.55 + 0.45 * h, aa);
	AO_LIGHT_AFFECT = 0.45;
}
