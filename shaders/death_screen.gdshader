shader_type canvas_item;
// Экран при поломке дрона: краски уходят в серое, края темнеют,
// по картинке бегут помехи (полосы и «снег»), как у гаснущего монитора.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float amount = 0.0;     // 0..1

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	// изредка строки сдвигает
	float band = step(0.985, hash(vec2(floor(uv.y * 90.0), floor(TIME * 12.0))));
	uv.x += band * 0.012 * amount;
	vec3 c = texture(screen_tex, uv).rgb;
	float g = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(c, vec3(g) * vec3(1.0, 0.97, 0.93), amount * 0.85);
	vec2 d = SCREEN_UV - 0.5;
	float vig = smoothstep(0.25, 0.85, length(d * vec2(1.25, 1.0)));
	c *= 1.0 - vig * 0.75 * amount;
	float sn = hash(SCREEN_UV * 400.0 + TIME * 37.0);
	c += (sn - 0.5) * 0.08 * amount;
	c += band * 0.08 * amount;
	float scan = 0.94 + 0.06 * sin(SCREEN_UV.y * 700.0);
	c *= mix(1.0, scan, amount);
	COLOR = vec4(c, 1.0);
}
