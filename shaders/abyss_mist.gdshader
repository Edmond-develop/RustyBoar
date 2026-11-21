shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;
// Туман в пропасти каньона: медленно плывущие клочья, дно почти не видно.
// Края плоскости тают, а вблизи стен туман мягко истончается (проверка глубины).

uniform vec3 mist_color : source_color = vec3(0.78, 0.86, 0.94);
uniform float density = 0.6;
uniform vec2 drift = vec2(0.012, 0.007);
uniform sampler2D depth_tex : hint_depth_texture, filter_linear;

varying vec3 wp;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = wp.xz * 0.018 + TIME * drift;
	float n = noise(p) * 0.55 + noise(p * 2.3 + 7.0) * 0.3 + noise(p * 5.1 - 3.0) * 0.15;
	float a = (smoothstep(0.25, 0.75, n) * 0.45 + 0.55) * density;
	// край плоскости
	vec2 e = min(UV, 1.0 - UV);
	a *= smoothstep(0.0, 0.04, min(e.x, e.y));
	// мягко у пересечения с обрывами и столбами
	float d = texture(depth_tex, SCREEN_UV).r;
#if CURRENT_RENDERER != RENDERER_COMPATIBILITY
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, d);
	vec4 vp = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	float scene_z = -vp.z / vp.w;
	float frag_z = -VERTEX.z;
	a *= clamp((scene_z - frag_z) / 6.0, 0.0, 1.0);
#endif
	ALBEDO = mist_color * (0.85 + 0.15 * n);
	ALPHA = clamp(a, 0.0, 0.92);
}
