shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, unshaded, shadows_disabled, fog_disabled, skip_vertex_transform;
// Столб света под полыньёй: полоса всегда повёрнута к камере (вокруг вертикали),
// ярче у поверхности, тает книзу; по ней бегут лучи. Туман на неё не действует,
// поэтому свет полыньи видно сквозь муть издалека — по нему ищут выход.
// Цвет экземпляра: .rg — случайное число, .a — яркость.

uniform vec3 tint : source_color = vec3(0.55, 0.85, 0.88);
uniform float strength = 0.45;

varying float v_dist;
varying float v_seed;

void vertex() {
	vec3 origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float w = length(MODEL_MATRIX[0].xyz);
	float h = length(MODEL_MATRIX[1].xyz);
	vec3 cam = INV_VIEW_MATRIX[3].xyz;
	vec3 to_cam = cam - origin;
	to_cam.y = 0.0;
	vec3 right = normalize(vec3(to_cam.z, 0.0, -to_cam.x) + vec3(1e-4, 0.0, 0.0));
	// лёгкое покачивание лучей
	float sway = sin(TIME * 0.5 + COLOR.r * 20.0) * 0.25 * (-VERTEX.y);
	vec3 world = origin + right * (VERTEX.x * w + sway) + vec3(0.0, VERTEX.y * h, 0.0);
	v_dist = length(cam - origin);
	v_seed = COLOR.r * 31.0 + COLOR.g * 7.0;
	VERTEX = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
	NORMAL = normalize((VIEW_MATRIX * vec4(to_cam, 0.0)).xyz + vec3(0.0, 0.0, 1e-4));
}

void fragment() {
	float u = UV.x;
	float v = UV.y;
	float edge = pow(sin(u * 3.14159), 1.6);
	float rays = 0.55 + 0.45 * sin(u * 11.0 + v_seed + TIME * 0.5) * sin(u * 5.0 - TIME * 0.35 + v_seed * 0.3);
	float fade = pow(1.0 - clamp(v, 0.0, 1.0), 1.7);
	float dist_f = smoothstep(34.0, 8.0, v_dist) * smoothstep(0.3, 2.0, v_dist);
	ALBEDO = tint;
	ALPHA = edge * rays * fade * dist_f * COLOR.a * strength;
}
