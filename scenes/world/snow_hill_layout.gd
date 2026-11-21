extends RefCounted
## План Снежной горы (шаги 139–142) — общий для рельефа (terrain.gd) и строителя (snow_hill.gd).
##
## С юга на север:
##   215…160    узкий проход по льду, перегорожен камнями — обход по тонкому льду (lake_rocks.gd)
##   160…146    уступ у края пропасти: нижняя станция подъёмника
##   146…62     ПРОПАСТЬ во всю ширину (дно ~-70); над ней — подъёмник-«турник»
##   62…-20     отвесная стена горы (260 м)
##   -20…-50    вершина (190 м): верхняя станция, стойка сноубордов, старт
##   -50…-640   СКЛОН ГОРЫ на всю ширину, весь в лесу. По нему — трасса-серпантин (~1.3 км):
##              разгон и трамплин → вираж → длинный траверс через лес → шпилька → гребень над ущельями →
##              шпилька → траверс с комами (катятся сзади и наводятся) → трамплины → финиш.
##              С трассы можно съехать в лес и катиться напрямик (заблудиться).
##
## Трасса — ломаная с закруглёнными углами (PATH, радиусы R). Для любой точки — ближайшая точка трассы:
## расстояние поперёк (d, + справа по ходу), длина пути s, z этой точки (рельеф трассы — ровный поперёк).

const Z_FOOT := 160.0
const LEDGE_Y := 0.35
const CHASM_S := 146.0
const CHASM_N := 62.0
const CHASM_Y := -70.0
const Z_TOP := -20.0                ## край вершины (верх стены)
const Z_START := -52.0              ## стартовые ворота
const Z_END := -654.0
const TOP_Y := 190.0
const END_Y := -2.5

## Подъёмник: трос — ломаная (x = LIFT_X); перекладина на ROD ниже троса, ноги — на HANG ниже рук
const LIFT_X := 0.0
const ROD := 1.6
const HANG := 2.02
const CABLE := [Vector2(153.0, 4.0), Vector2(100.0, 57.0), Vector2(-22.0, 197.0), Vector2(-36.0, 193.62)]   ## (z, y троса)
const TOWER_Z := 100.0

## Трасса: точки (x, z) и радиус закругления в каждой
const PATH := [Vector3(0.0, -50.0, 0.0), Vector3(0.0, -112.0, 40.0), Vector3(275.0, -205.0, 36.0),
		Vector3(-285.0, -392.0, 36.0), Vector3(250.0, -556.0, 40.0), Vector3(60.0, -616.0, 34.0), Vector3(0.0, -642.0, 0.0)]
const HALF_W := 21.0                ## полуширина трассы
const EDGE_W := 22.0                ## за краем трассы — переход к склону (насыпь/выемка)
const RIDGE_HALF := 4.5
const GULLY_D := 14.0

## Склон горы по z (без трассы)
const SLOPE := [[-20.0, 190.0], [-45.0, 190.0], [-62.0, 184.0], [-200.0, 140.0], [-350.0, 92.0], [-500.0, 45.0],
		[-600.0, 8.0], [-636.0, -2.5], [-660.0, -2.5]]

# --- построенная трасса (лениво, один раз) ---
static var _prims: Array = []        ## [тип 0 — отрезок: a, b, s0, len; тип 1 — дуга: c, r, a0, da, s0, len]
static var _total := 0.0
static var _samples: Array = []      ## каждые 2 м: [Vector2 pos, Vector2 tan]


static func _build() -> void:
	if not _prims.is_empty():
		return
	var pts: Array[Vector2] = []
	var rads: Array[float] = []
	for p in PATH:
		pts.append(Vector2(p.x, p.y))
		rads.append(p.z)
	var cur := pts[0]
	var s := 0.0
	for i in range(1, pts.size()):
		var a := (pts[i] - pts[i - 1]).normalized()
		var end := pts[i]
		var arc := []
		if i < pts.size() - 1 and rads[i] > 0.0:
			var b := (pts[i + 1] - pts[i]).normalized()
			var th := acos(clampf(a.dot(b), -1.0, 1.0))
			var t := rads[i] * tan(th * 0.5)
			var t1 := pts[i] - a * t
			var t2 := pts[i] + b * t
			var cr := a.x * b.y - a.y * b.x
			var nrm := Vector2(-a.y, a.x) * signf(cr)
			var c := t1 + nrm * rads[i]
			var a0 := (t1 - c).angle()
			var a1 := (t2 - c).angle()
			var da := wrapf(a1 - a0, -PI, PI)
			end = t1
			arc = [c, rads[i], a0, da]
		var ln := cur.distance_to(end)
		_prims.append([0, cur, end, s, ln])
		s += ln
		if not arc.is_empty():
			var al: float = absf(float(arc[3])) * float(arc[1])
			_prims.append([1, arc[0], arc[1], arc[2], arc[3], s, al])
			s += al
			var c2: Vector2 = arc[0]
			cur = c2 + Vector2.from_angle(float(arc[2]) + float(arc[3])) * float(arc[1])
		else:
			cur = end
	_total = s
	var k := 0.0
	while k <= _total:
		_samples.append(_eval(k))
		k += 2.0


static func _eval(s: float) -> Array:
	for pr in _prims:
		if int(pr[0]) == 0:
			var s0: float = pr[3]
			var ln: float = pr[4]
			if s <= s0 + ln or pr == _prims[_prims.size() - 1]:
				var a: Vector2 = pr[1]
				var b: Vector2 = pr[2]
				var u := clampf((s - s0) / maxf(ln, 0.001), 0.0, 1.0)
				return [a.lerp(b, u), (b - a).normalized()]
		else:
			var s1: float = pr[5]
			var al: float = pr[6]
			if s <= s1 + al:
				var c: Vector2 = pr[1]
				var r: float = pr[2]
				var da: float = pr[4]
				var ang: float = float(pr[3]) + da * clampf((s - s1) / al, 0.0, 1.0)
				var pos := c + Vector2.from_angle(ang) * r
				var tn := Vector2.from_angle(ang + PI * 0.5 * signf(da))
				return [pos, tn]
	var last: Array = _prims[_prims.size() - 1]
	return [last[2], ((last[2] as Vector2) - (last[1] as Vector2)).normalized()]


static func total() -> float:
	_build()
	return _total


## Точка трассы (x, z) на длине s
static func at(s: float) -> Vector2:
	_build()
	var i := clampi(int(s / 2.0), 0, _samples.size() - 2)
	var u := clampf((s - i * 2.0) / 2.0, 0.0, 1.0)
	return (_samples[i][0] as Vector2).lerp(_samples[i + 1][0], u)


## Направление трассы (x, z) на длине s
static func dir(s: float) -> Vector2:
	_build()
	var i := clampi(int(s / 2.0), 0, _samples.size() - 2)
	var u := clampf((s - i * 2.0) / 2.0, 0.0, 1.0)
	return (_samples[i][1] as Vector2).lerp(_samples[i + 1][1], u).normalized()


## Ближайшие точки каждого куска трассы: [d (поперёк, + справа по ходу), s, z точки трассы]
static func near_all(x: float, z: float) -> Array:
	_build()
	var q := Vector2(x, z)
	var out := []
	for pr in _prims:
		var d := 0.0
		var s := 0.0
		var pz := 0.0
		if int(pr[0]) == 0:
			var a: Vector2 = pr[1]
			var b: Vector2 = pr[2]
			var ab := b - a
			var ln: float = pr[4]
			var u := clampf((q - a).dot(ab) / maxf(ln * ln, 0.0001), 0.0, 1.0)
			var p := a + ab * u
			var t := ab / maxf(ln, 0.001)
			var pd := (q - p).dot(Vector2(-t.y, t.x))       # «+» — справа по ходу
			d = q.distance_to(p) * (1.0 if pd >= 0.0 else -1.0)
			s = float(pr[3]) + u * ln
			pz = p.y
		else:
			var c: Vector2 = pr[1]
			var r: float = pr[2]
			var a0: float = pr[3]
			var da: float = pr[4]
			var ang := (q - c).angle()
			var rel := wrapf(ang - a0, -PI, PI) * signf(da)
			var lim := absf(da)
			if rel < 0.0 or rel > lim:
				# вне дуги — ближайший конец
				var e0 := c + Vector2.from_angle(a0) * r
				var e1 := c + Vector2.from_angle(a0 + da) * r
				if q.distance_to(e0) < q.distance_to(e1):
					rel = 0.0
				else:
					rel = lim
			var pa := a0 + rel * signf(da)
			var p2 := c + Vector2.from_angle(pa) * r
			var tn := Vector2.from_angle(pa + PI * 0.5 * signf(da))
			var pd2 := (q - p2).dot(Vector2(-tn.y, tn.x))
			d = q.distance_to(p2) * (1.0 if pd2 >= 0.0 else -1.0)
			s = float(pr[5]) + rel * r
			pz = p2.y
		out.append([d, s, pz])
	return out


## Ближайшая точка трассы: [d, s, z]
static func near(x: float, z: float) -> Array:
	var best: Array = []
	var bd := INF
	for e in near_all(x, z):
		if absf(float(e[0])) < bd:
			bd = absf(float(e[0]))
			best = e
	return best


## Высота склона по z (без трассы)
static func slope_y(z: float) -> float:
	var n := SLOPE.size()
	if z >= float(SLOPE[0][0]):
		return float(SLOPE[0][1])
	if z <= float(SLOPE[n - 1][0]):
		return float(SLOPE[n - 1][1])
	var i := 0
	while i < n - 2 and z < float(SLOPE[i + 1][0]):
		i += 1
	var z0: float = SLOPE[i][0]
	var z1: float = SLOPE[i + 1][0]
	var y0: float = SLOPE[i][1]
	var y1: float = SLOPE[i + 1][1]
	if absf(y1 - y0) < 0.01:
		return y0
	var ym: float = SLOPE[maxi(i - 1, 0)][1]
	var zm: float = SLOPE[maxi(i - 1, 0)][0]
	var yp: float = SLOPE[mini(i + 2, n - 1)][1]
	var zp: float = SLOPE[mini(i + 2, n - 1)][0]
	var t := (z - z0) / (z1 - z0)
	var dz := z1 - z0
	var m0 := (y1 - ym) / (z1 - zm) * dz if i > 0 else 0.0
	var m1 := (yp - y0) / (zp - z0) * dz if i + 2 < n else 0.0
	var t2 := t * t
	var t3 := t2 * t
	return (2.0 * t3 - 3.0 * t2 + 1.0) * y0 + (t3 - 2.0 * t2 + t) * m0 + (-2.0 * t3 + 3.0 * t2) * y1 + (t3 - t2) * m1


# --- участки трассы по длине s ---
static func s_of_corner(i: int) -> float:
	## s середины закругления в точке PATH[i] (примерно)
	_build()
	var best := 0.0
	var bd := INF
	var c := Vector2(PATH[i].x, PATH[i].y)
	var k := 0.0
	while k <= _total:
		var dd := at(k).distance_to(c)
		if dd < bd:
			bd = dd
			best = k
		k += 2.0
	return best


## Участки по длине пути s (≈1345 м): виражи у s 58, 282, 744, 1158, 1280
## Лес прямо на трассе (объезжай ёлки): первый траверс, шпилька и второй траверс
static func forest_k(s: float) -> float:
	return smoothstep(80.0, 100.0, s) * (1.0 - smoothstep(680.0, 700.0, s))


## Гребень в начале третьего траверса: узкий верх, по бокам — ущелья
static func ridge_k(_s: float) -> float:
	return 0.0          # шаг 144: гребня с ущельями больше нет — там широкий склон


## Ущелья долго мелеют (дно всё время под уклон)
static func gully_k(_s: float) -> float:
	return 0.0


## Шаг 144: третий траверс (комы) — широкий склон: трасса шире на WIDE_ADD с каждой стороны
const WIDE_ADD := 16.0
static func wide_k(s: float) -> float:
	return smoothstep(790.0, 830.0, s) * (1.0 - smoothstep(1095.0, 1132.0, s))


## Полуширина трассы на длине s
static func half_w(s: float) -> float:
	return HALF_W + WIDE_ADD * wide_k(s)


## Участок комов: третий траверс до последней шпильки
const CHASE_S := Vector2(820.0, 1150.0)
const KICKERS_S := [30.0, 1195.0, 1232.0]
const FINISH_S := 1300.0


## Рельеф трассы (без шума): склон + трасса ровная поперёк, гребень/ущелья
static func hill_y(x: float, z: float) -> float:
	var base := slope_y(z)
	var list := near_all(x, z)
	var acc := 0.0
	var wsum := 0.0
	var e0: Array = list[0]
	var bd := INF
	for e in list:
		var d := absf(float(e[0]))
		if d < bd:
			bd = d
			e0 = e
		var hw := half_w(float(e[1]))
		if d > hw + EDGE_W:
			continue
		var w := 1.0 - smoothstep(hw, hw + EDGE_W, d)
		acc += w * (slope_y(float(e[2])) - base)
		wsum += w
	var h := base + (acc / maxf(wsum, 1.0) if wsum > 0.0 else 0.0)
	var gk := gully_k(float(e0[1]))
	if gk > 0.0:
		var dx := absf(float(e0[0]))
		var rh := RIDGE_HALF + (1.0 - ridge_k(float(e0[1]))) * 9.0
		h -= GULLY_D * gk * smoothstep(rh, rh + 6.0, dx) * (1.0 - smoothstep(30.0, 40.0, dx))
	return h


## Высота оси трассы на длине s
static func run_y_s(s: float) -> float:
	var p := at(s)
	return slope_y(p.y)


## Рельеф от льда до вершины: уступ → пропасть → стена (снизу полого, к верху отвесно) → вершина
static func face_y(z: float) -> float:
	if z >= CHASM_S + 2.0:
		return LEDGE_Y
	if z >= CHASM_S - 6.0:
		return lerpf(CHASM_Y, LEDGE_Y, smoothstep(CHASM_S - 6.0, CHASM_S + 2.0, z))
	if z >= CHASM_N:
		return CHASM_Y
	if z >= Z_TOP:
		var t := (CHASM_N - z) / (CHASM_N - Z_TOP)
		return CHASM_Y + (TOP_Y - CHASM_Y) * pow(t, 2.5)
	return TOP_Y


## Река на дне пропасти (шаг 143): петляет вдоль пропасти; вода — RIVER_Y, русло глубже
const RIVER_Y := CHASM_Y - 1.6


static func river_z(x: float) -> float:
	return (CHASM_S + CHASM_N) * 0.5 + 12.0 * sin(x * 0.02) + 5.0 * sin(x * 0.051 + 1.0)


static func river_hw(x: float) -> float:
	return 6.5 + 2.0 * sin(x * 0.033 + 0.4)


static func cable_len() -> float:
	var s := 0.0
	for i in CABLE.size() - 1:
		s += (CABLE[i + 1] as Vector2).distance_to(CABLE[i])
	return s


static func cable_point(k: float) -> Vector3:
	var total_l := cable_len()
	var want := clampf(k, 0.0, 1.0) * total_l
	for i in CABLE.size() - 1:
		var a: Vector2 = CABLE[i]
		var b: Vector2 = CABLE[i + 1]
		var seg := a.distance_to(b)
		if want <= seg or i == CABLE.size() - 2:
			var p := a.lerp(b, clampf(want / seg, 0.0, 1.0))
			return Vector3(LIFT_X, p.y, p.x)
		want -= seg
	return Vector3(LIFT_X, CABLE[0].y, CABLE[0].x)


static func lift_bottom() -> Vector3:
	return Vector3(LIFT_X, LEDGE_Y, (CABLE[0] as Vector2).x)


static func lift_top() -> Vector3:
	return Vector3(LIFT_X, TOP_Y, (CABLE[CABLE.size() - 1] as Vector2).x)


static func over_chasm(p: Vector3) -> bool:
	return p.z < CHASM_S - 1.0 and p.z > CHASM_N - 30.0 and p.y < face_y(p.z) + 300.0


static func on_hill(p: Vector3) -> bool:
	return p.z < Z_FOOT + 4.0 and p.z > Z_END - 6.0
