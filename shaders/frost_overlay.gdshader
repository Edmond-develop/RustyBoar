shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back;
// Иней и снег поверх любой модели (накладывается как material_overlay).
// Сверху — плотный снег, на боках — пятна инея, у самого льда — сплошная наледь.

uniform vec3 frost_color : source_color = vec3(0.9, 0.95, 1.0);
uniform float ice_y = 0.0;          // высота льда: чем ближе к нему, тем больше наледи
uniform float amount = 1.0;

varying vec3 wnormal;
varying vec3 wpos;

float hash1(vec2 p) {
	return fract(sin(dot(p, vec2(41.3, 289.1))) * 15731.743);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash1(i), hash1(i + vec2(1.0, 0.0)), f.x),
		mix(hash1(i + vec2(0.0, 1.0)), hash1(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	wnormal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float up = smoothstep(0.25, 0.8, wnormal.y);
	float n = vnoise(wpos.xz * 1.3 + wpos.y * 0.7) * 0.6 + vnoise(wpos.xz * 5.0 + wpos.y * 3.0) * 0.4;
	float frost = clamp(up * 1.0 + smoothstep(0.45, 0.8, n) * 0.6, 0.0, 1.0);
	frost = max(frost, smoothstep(1.8, 0.0, wpos.y - ice_y) * 0.9);
	ALBEDO = frost_color * (0.9 + 0.1 * n);
	ROUGHNESS = mix(0.35, 0.9, up);
	ALPHA = frost * 0.9 * amount;
}
