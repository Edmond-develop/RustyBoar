shader_type spatial;
render_mode cull_disabled, specular_schlick_ggx;
// Растения инопланетного луга: качаются на ветру (верхушки сильнее, чем низ),
// цвет — из цвета вершин × цвет экземпляра. UV.x = 1 — эта часть светится
// (шляпки грибов, шары на стеблях, кромки трубок).

uniform float sway = 0.1;          // сила качания
uniform float wind_speed = 1.3;
uniform float glow = 2.2;           // яркость светящихся частей
uniform float pulse = 0.25;         // светящиеся части медленно «дышат»

varying float v_phase;

void vertex() {
	vec3 origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float h = max(VERTEX.y, 0.0);
	v_phase = origin.x * 0.35 + origin.z * 0.27;
	float w = sin(TIME * wind_speed + v_phase) * 0.6 + sin(TIME * wind_speed * 2.3 + v_phase * 1.7) * 0.25;
	VERTEX.x += w * sway * h * h;
	VERTEX.z += w * sway * 0.45 * h * h;
}

void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 0.75;
	float breathe = 1.0 - pulse + pulse * sin(TIME * 1.4 + v_phase * 3.0);
	EMISSION = COLOR.rgb * UV.x * glow * breathe;
}
