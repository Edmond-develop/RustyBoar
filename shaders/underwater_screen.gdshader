shader_type canvas_item;
// Экран под водой: картинка слегка плывёт и размыта, сине-зелёный оттенок,
// тёмные края (чем глубже — тем темнее). hurt — красная пульсация от давления.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float depth01 = 0.0;
uniform float hurt = 0.0;

void fragment() {
	vec2 uv = SCREEN_UV;
	float t = TIME;
	uv += vec2(sin(uv.y * 23.0 + t * 1.7), cos(uv.x * 19.0 + t * 1.3)) * 0.0022;
	vec2 px = SCREEN_PIXEL_SIZE * 1.6;
	vec3 c = texture(screen_tex, uv).rgb * 0.4;
	c += texture(screen_tex, uv + vec2(px.x, 0.0)).rgb * 0.15;
	c += texture(screen_tex, uv - vec2(px.x, 0.0)).rgb * 0.15;
	c += texture(screen_tex, uv + vec2(0.0, px.y)).rgb * 0.15;
	c += texture(screen_tex, uv - vec2(0.0, px.y)).rgb * 0.15;
	// оттенок воды и приглушённые цвета
	c *= vec3(0.6, 0.92, 0.95);
	float lum = dot(c, vec3(0.3, 0.55, 0.15));
	c = mix(vec3(lum), c, 0.7);
	// тёмные края и темнота на глубине
	float vig = smoothstep(0.3, 0.95, length(UV - 0.5) * 1.35);
	c *= 1.0 - vig * (0.4 + 0.4 * depth01);
	c *= 1.0 - depth01 * 0.3;
	c = mix(c, vec3(0.55, 0.04, 0.04), clamp(hurt, 0.0, 1.0) * (0.25 + vig * 0.5));
	COLOR = vec4(c, 1.0);
}
