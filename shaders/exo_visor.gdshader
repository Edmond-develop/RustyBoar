shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, specular_schlick_ggx;
// Широкий визор шлема (рисуется на сфере чуть больше купола — только спереди).
// На визоре — «цифровые глаза» цвета игрока: моргают, смотрят по сторонам,
// меняют выражение (обычное, радость, боль, усталость, выключен).
// cracks 0..1 — трещины на стекле, power — питание (мерцает при поломке).

uniform float radius = 0.2;
uniform vec3 eye_color : source_color = vec3(0.4, 0.9, 1.0);
uniform float power = 1.0;
uniform int mood = 0;               // 0 — обычный, 1 — радость, 2 — больно, 3 — устал, 4 — выключен,
                                    // 5 — паника, 6 — сосредоточен (чинит), 7 — голова кружится
uniform float blink = 0.0;          // 0 — открыты, 1 — закрыты
uniform vec2 look = vec2(0.0);      // куда смотрят глаза (смещение)
uniform float cracks = 0.0;
uniform vec2 crack_origin = vec2(0.35, 0.1);
uniform float wet = 0.0;

varying vec3 lp;

float hash2(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

vec2 hash22(vec2 p) {
	return vec2(hash2(p), hash2(p + 17.3));
}

// расстояние до границы ячеек (Вороной) — линии трещин
float crack_lines(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float d1 = 8.0;
	float d2 = 8.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec2 o = hash22(i + g);
			float d = length(g + o - f);
			if (d < d1) {
				d2 = d1;
				d1 = d;
			} else if (d < d2) {
				d2 = d;
			}
		}
	}
	return d2 - d1;
}

float rbox(vec2 p, vec2 b, float r) {
	vec2 q = abs(p) - b + r;
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

float eye_shape(vec2 p, float side) {
	// p — координаты относительно центра глаза (в долях высоты визора), side — левый (-1) / правый (1)
	if (mood == 5) {
		// паника: круглые глаза-кольца, зрачки мечутся
		vec2 j = vec2(sin(TIME * 23.0 + side * 2.0), cos(TIME * 19.0 + side)) * 0.025;
		float ring = abs(length(p) - 0.115) - 0.022;
		float pupil = length(p - j) - 0.035;
		return min(ring, pupil);
	} else if (mood == 6) {
		// сосредоточен: прищур, внутренние уголки опущены
		vec2 q = p;
		q.y -= q.x * side * 0.55;
		return rbox(q, vec2(0.085, 0.045), 0.03);
	} else if (mood == 7) {
		// голова кружится: глаза-спирали
		float r = length(p);
		float a = atan(p.y, p.x) * side;
		float v = r * 34.0 - (a + TIME * 9.0) / 6.2832;
		float d = abs(fract(v) - 0.5) / 34.0 - 0.0045;
		return (r < 0.14) ? d : 1.0;
	}
	if (mood == 1) {
		// дуга «^»
		float d = abs(length(p - vec2(0.0, -0.09)) - 0.13) - 0.035;
		return (p.y > -0.06) ? d : 1.0;
	} else if (mood == 2) {
		// «> <» — зажмурился
		vec2 a = vec2(abs(p.x * 1.4), p.y);
		float d = abs(a.y - (0.09 - a.x * 0.9)) - 0.03;
		return (a.x < 0.12 && abs(p.y) < 0.12) ? d : 1.0;
	}
	float h = 0.14 * (1.0 - blink * 0.92);
	if (mood == 3) {
		h *= 0.45;
		p.y += 0.05;
	}
	return rbox(p, vec2(0.075, h), 0.05);
}

void vertex() {
	lp = VERTEX;
}

void fragment() {
	float theta = atan(lp.x, -lp.z);          // угол по горизонтали от «вперёд»
	float ey = lp.y / radius;
	vec2 uv = vec2(theta / 1.2, (ey + 0.08) / 0.3);
	float shape = pow(abs(uv.x), 4.0) + pow(abs(uv.y), 4.0);
	if (shape > 1.0 || lp.z > 0.02) {
		discard;
	}
	float edge = smoothstep(0.75, 1.0, shape);

	vec3 glass = vec3(0.015, 0.025, 0.035);
	vec3 emis = vec3(0.0);
	vec2 e = vec2(theta, ey) ;
	// глаза
	if (mood != 4) {
		vec2 c = vec2(0.36, 0.02) ;
		vec2 lk = look * vec2(0.18, 0.12);
		float dl = eye_shape(vec2(e.x + c.x, e.y - c.y) - lk, -1.0);
		float dr = eye_shape(vec2(e.x - c.x, e.y - c.y) - lk, 1.0);
		if (mood == 2) {
			dr = eye_shape(vec2(-(e.x - c.x), e.y - c.y) - lk, 1.0);
		}
		float d = min(dl, dr);
		float eye = 1.0 - smoothstep(-0.005, 0.012, d);
		float halo = exp(-max(d, 0.0) * 28.0) * 0.35;
		float scan = 0.82 + 0.18 * sin(lp.y * 900.0);
		emis += eye_color * (eye * 3.2 * scan + halo);
	}
	// лёгкая подсветка изнутри
	emis += eye_color * 0.05 * (1.0 - edge);
	emis *= power;

	// трещины
	float ck = 0.0;
	if (cracks > 0.001) {
		float dist = length(e - crack_origin);
		float lines = crack_lines(e * 9.0 + crack_origin * 3.0);
		float lines2 = crack_lines(e * 23.0 + 5.0);
		float reach = cracks * 0.9;
		float mask = 1.0 - smoothstep(reach * 0.6, reach, dist);
		ck = (1.0 - smoothstep(0.0, 0.05, lines)) * mask;
		ck = max(ck, (1.0 - smoothstep(0.0, 0.04, lines2)) * mask * smoothstep(reach * 0.8, 0.0, dist));
		ck *= cracks > 0.0 ? 1.0 : 0.0;
	}

	ALBEDO = mix(glass, vec3(0.75, 0.82, 0.88), ck * 0.8) + vec3(0.05) * edge;
	EMISSION = emis * (1.0 - ck * 0.7);
	METALLIC = 0.0;
	ROUGHNESS = mix(0.12, 0.5, ck) + wet * 0.0;
	SPECULAR = 0.45;
}
