shader_type spatial;
render_mode cull_disabled, diffuse_burley;
// Ледяные водоросли: лента колышется в воде (сильнее к кончику),
// у каждой своя фаза (INSTANCE_CUSTOM.r/g). Кончики слабо светятся бирюзой.

uniform vec3 base_col : source_color = vec3(0.10, 0.20, 0.14);
uniform vec3 tip_col : source_color = vec3(0.20, 0.55, 0.50);
uniform vec3 glow_col : source_color = vec3(0.25, 0.95, 0.85);

varying float vy;
varying float glow_amt;

void vertex() {
	vy = UV.y;
	float ph = INSTANCE_CUSTOM.r * 6.2831;
	float k = UV.y * UV.y;
	float sway = sin(TIME * 1.1 + ph + UV.y * 2.2) * 0.35 + sin(TIME * 2.3 + ph * 1.7) * 0.12;
	VERTEX.z += sway * k / max(INSTANCE_CUSTOM.b, 0.3);
	VERTEX.x += sin(TIME * 0.8 + ph * 2.0) * 0.6 * k;
	glow_amt = step(0.55, INSTANCE_CUSTOM.g);
}

void fragment() {
	vec3 c = mix(base_col, tip_col, vy);
	ALBEDO = c;
	ROUGHNESS = 0.6;
	float tip = smoothstep(0.75, 1.0, vy) * glow_amt;
	float pulse = 0.6 + 0.4 * sin(TIME * 2.0 + vy * 6.0);
	EMISSION = glow_col * tip * 1.4 * pulse;
}
