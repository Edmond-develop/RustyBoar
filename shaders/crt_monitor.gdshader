shader_type spatial;
render_mode unshaded, cull_back;
// Шаг 109: монитор пульта канатки — картинка с камеры на кабине (SubViewport) в старом кинескопе:
// строки развёртки, виньетка; noise — помехи (полосы рвутся, снег, картинка плывёт);
// lost — сигнала нет: снег и тёмный экран; alarm — красные вспышки при ударе.
uniform sampler2D feed : source_color, filter_linear;
uniform float noise = 0.0;
uniform float lost = 0.0;
uniform float alarm = 0.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 uv = UV;
	float t = TIME;
	float band = floor(uv.y * 30.0 + t * 40.0);
	float tear = step(1.0 - noise * 0.6, hash(vec2(band, floor(t * 15.0))));
	uv.x += (hash(vec2(band, floor(t * 25.0))) - 0.5) * 0.16 * noise * (0.3 + tear);
	uv.y = fract(uv.y + noise * noise * 0.25 * sin(t * 0.7));
	vec3 c = texture(feed, uv).rgb;
	float g = dot(c, vec3(0.3, 0.59, 0.11));
	c = mix(c, vec3(g), 0.3) * vec3(0.95, 1.06, 0.97);
	float scan = 0.84 + 0.16 * sin(UV.y * 520.0);
	vec2 cc = UV - 0.5;
	float vig = clamp(1.0 - dot(cc, cc) * 1.5, 0.0, 1.0);
	float sn = hash(floor(UV * vec2(220.0, 140.0)) + floor(t * 30.0));
	float snowk = clamp(noise * 0.55 + lost, 0.0, 1.0);
	c = mix(c, vec3(sn), snowk * 0.85);
	float dark = smoothstep(0.5, 1.0, lost);
	c = mix(c, vec3(0.02, 0.03, 0.07) + vec3(sn) * 0.05, dark);
	c *= scan * vig * (1.0 + 0.1 * sin(t * 50.0) * noise);
	c = mix(c, vec3(1.0, 0.2, 0.15) * 0.45 * vig, alarm * (0.5 + 0.5 * sin(t * 12.0)));
	ALBEDO = c;
}
