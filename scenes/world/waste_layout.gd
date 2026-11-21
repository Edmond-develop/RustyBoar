class_name WasteLayout
extends RefCounted
## План Снежной пустоши (шаг 50) — между выходом из Ледяного каньона и Лавинным склоном.
##
##   z -654 … -1668, x −300 … 300 (≈ 1 км × 600 м), по бокам — горы.
##   Тропа (ROUTE) сначала идёт прямо на север, потом петляет. Вдоль неё — вешки.
##   Метель (storm) усиливается к середине: туман, снег, ветер; порывы сносят назад и вбок.
##   Вне тропы под снегом прячутся трещины (crevasses) — накрыты снежными пластами.
##   У тропы — скалы-укрытия (shelters), посередине — брошенный лагерь (CAMP),
##   ближе к концу — метеобудка (HUT). Всё по фиксированному зерну — одинаково у всех.
##
## Высоту рельефа считает terrain.gd (_waste_height) — по этим же данным.

const S_Z := -654.0                ## южный край (выход из каньона)
const N_Z := -1668.0               ## северный край — дальше прежний мир (лавинный склон…)
const NORTH_SHIFT := 700.0         ## насколько сдвинут к северу прежний мир за пустошью
const HALF := 300.0                ## полуширина пустоши (дальше — горы)

## Тропа: опорные точки (x, z)
const ROUTE := [Vector2(0, -655), Vector2(0, -900), Vector2(-110, -985), Vector2(-150, -1080),
	Vector2(-60, -1160), Vector2(90, -1215), Vector2(170, -1300), Vector2(120, -1400),
	Vector2(-40, -1450), Vector2(-160, -1505), Vector2(-90, -1560), Vector2(0, -1600), Vector2(0, -1672)]

const CELL := 2.0                  ## шаг сетки расстояний
const FAR := 40.0                  ## дальше этого расстояние до тропы не считаем
const POLE_STEP := 15.0            ## вешки через каждые … м
const CREVASSE_COUNT := 34
## «Голые» отрезки тропы (доли длины): скал-укрытий нет — только вешки (между кострами и лагерем)
const BARE := [Vector2(0.33, 0.44), Vector2(0.53, 0.62), Vector2(0.71, 0.80)]
const CRACK_DEPTH := -45.0         ## дно трещины

static var _path := PackedVector2Array()      ## точки тропы через ~3 м
static var _acc := PackedFloat32Array()       ## длина пути до точки
static var _pd := PackedFloat32Array()        ## сетка: расстояние до тропы
static var _ps := PackedFloat32Array()        ## сетка: где на тропе ближайшая точка (м от начала)
static var _cd := PackedFloat32Array()        ## сетка: расстояние до края трещины (<0 — внутри)
static var _cy := PackedFloat32Array()        ## сетка: высота снежного пласта над трещиной
static var _nx := 0
static var _nz := 0
static var _cracks: Array = []                ## [a: Vector2, b: Vector2, полуширина, высота пласта]
static var _shelters: Array = []              ## [центр (x, z), радиус]
static var _camp := Vector2.ZERO
static var _hut := Vector2.ZERO
static var _ready_flag := false


# ---------------------------------------------------------------------------
#  Тропа
# ---------------------------------------------------------------------------

static func _ensure() -> void:
	if _ready_flag:
		return
	_ready_flag = true
	# сглаженная тропа (Катмулл — Ром через опорные точки)
	var pts: Array = ROUTE
	_path.clear()
	for i in pts.size() - 1:
		var p0: Vector2 = pts[maxi(i - 1, 0)]
		var p1: Vector2 = pts[i]
		var p2: Vector2 = pts[i + 1]
		var p3: Vector2 = pts[mini(i + 2, pts.size() - 1)]
		var n := maxi(int(p1.distance_to(p2) / 3.0), 2)
		for k in n:
			var t := float(k) / n
			var t2 := t * t
			var t3 := t2 * t
			_path.append(0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3))
	_path.append(pts[-1])
	_acc.clear()
	_acc.append(0.0)
	for i in range(1, _path.size()):
		_acc.append(_acc[i - 1] + _path[i].distance_to(_path[i - 1]))
	# сетки
	_nx = int(2.0 * HALF / CELL) + 1
	_nz = int((S_Z - N_Z + 8.0) / CELL) + 1
	_pd.resize(_nx * _nz)
	_ps.resize(_nx * _nz)
	_cd.resize(_nx * _nz)
	_cy.resize(_nx * _nz)
	_pd.fill(FAR)
	_ps.fill(0.0)
	_cd.fill(99.0)
	_cy.fill(0.0)
	for i in _path.size() - 1:
		_stamp_seg(_path[i], _path[i + 1], _acc[i])
	# лагерь, будка, укрытия, трещины
	_camp = point_at(length() * 0.475) + side_at(length() * 0.475) * 20.0
	_hut = point_at(length() * 0.86) + side_at(length() * 0.86) * -13.0
	_make_shelters()
	_make_cracks()


static func _stamp_seg(a: Vector2, b: Vector2, s0: float) -> void:
	var r := FAR
	var ix0 := maxi(int(floor((minf(a.x, b.x) - r + HALF) / CELL)), 0)
	var ix1 := mini(int(ceil((maxf(a.x, b.x) + r + HALF) / CELL)), _nx - 1)
	var iz0 := maxi(int(floor((S_Z + 4.0 - maxf(a.y, b.y) - r) / CELL)), 0)
	var iz1 := mini(int(ceil((S_Z + 4.0 - minf(a.y, b.y) + r) / CELL)), _nz - 1)
	var ab := b - a
	var l2 := maxf(ab.length_squared(), 0.0001)
	for iz in range(iz0, iz1 + 1):
		var z := S_Z + 4.0 - iz * CELL
		for ix in range(ix0, ix1 + 1):
			var p := Vector2(-HALF + ix * CELL, z)
			var t := clampf((p - a).dot(ab) / l2, 0.0, 1.0)
			var d := p.distance_to(a + ab * t)
			var k := iz * _nx + ix
			if d < _pd[k]:
				_pd[k] = d
				_ps[k] = s0 + sqrt(l2) * t


static func _sample(arr: PackedFloat32Array, x: float, z: float, outside: float) -> float:
	var fx := (x + HALF) / CELL
	var fz := (S_Z + 4.0 - z) / CELL
	if fx < 0.0 or fz < 0.0 or fx >= _nx - 1 or fz >= _nz - 1:
		return outside
	var ix := int(fx)
	var iz := int(fz)
	var tx := fx - ix
	var tz := fz - iz
	var k := iz * _nx + ix
	return lerpf(lerpf(arr[k], arr[k + 1], tx), lerpf(arr[k + _nx], arr[k + _nx + 1], tx), tz)


## Расстояние до середины тропы (м), не больше FAR
static func path_dist(x: float, z: float) -> float:
	_ensure()
	return _sample(_pd, x, z, FAR)


## Где на тропе ближайшая точка (метров от начала)
static func path_s(x: float, z: float) -> float:
	_ensure()
	return _sample(_ps, x, z, 0.0)


## То же, но точно и для любой дали (перебором — для редких вызовов)
static func nearest_s(x: float, z: float) -> float:
	_ensure()
	var best := 0.0
	var bd := 1e18
	var q := Vector2(x, z)
	for i in _path.size():
		var d := _path[i].distance_squared_to(q)
		if d < bd:
			bd = d
			best = _acc[i]
	return best


static func length() -> float:
	_ensure()
	return _acc[_acc.size() - 1]


## Точка тропы на расстоянии s от начала
static func point_at(s: float) -> Vector2:
	_ensure()
	s = clampf(s, 0.0, _acc[_acc.size() - 1])
	var lo := 0
	var hi := _acc.size() - 1
	while hi - lo > 1:
		var mid := (lo + hi) / 2
		if _acc[mid] <= s:
			lo = mid
		else:
			hi = mid
	var seg := maxf(_acc[hi] - _acc[lo], 0.0001)
	return _path[lo].lerp(_path[hi], (s - _acc[lo]) / seg)


## Направление тропы в точке s (по ходу)
static func dir_at(s: float) -> Vector2:
	var a := point_at(s - 2.0)
	var b := point_at(s + 2.0)
	return (b - a).normalized()


## Вбок от тропы (влево по ходу)
static func side_at(s: float) -> Vector2:
	var d := dir_at(s)
	return Vector2(d.y, -d.x)


static func path_points() -> PackedVector2Array:
	_ensure()
	return _path


# ---------------------------------------------------------------------------
#  Погода и рельеф
# ---------------------------------------------------------------------------

## Сила метели в точке (0…1): у выхода из каньона — лёгкий снег, к середине — белая мгла,
## у лавинного склона стихает
static func storm(z: float) -> float:
	var up := smoothstep(-690.0, -960.0, z)
	# к северному краю буря стихает совсем: дальше — «Передышка» перед Лавинной долиной
	var down := smoothstep(-1540.0, -1650.0, z)
	return clampf((0.12 + 0.88 * up) * (1.0 - down), 0.0, 1.0) if z < S_Z else 0.0


## Куда дует ветер (в плоскости x, z): в основном с севера назад к каньону, со сносом вбок
static func wind_dir(z: float) -> Vector2:
	var a := 0.62 * sin(z * 0.0047 + 0.7) + 0.25 * sin(z * 0.013)
	return Vector2(sin(a), cos(a)).normalized()


## Общий уровень снега (без сугробов): у каньона — уровень старого озера, дальше выше
static func base_y(z: float) -> float:
	return -2.5 + 3.2 * smoothstep(-680.0, -1150.0, z) - 0.8 * smoothstep(-1450.0, -1660.0, z)


# ---------------------------------------------------------------------------
#  Укрытия, лагерь, трещины
# ---------------------------------------------------------------------------

static func camp() -> Vector2:
	_ensure()
	return _camp


static func hut() -> Vector2:
	_ensure()
	return _hut


static func shelters() -> Array:
	_ensure()
	return _shelters


static func cracks() -> Array:
	_ensure()
	return _cracks


## Скалы у тропы: через ~80 м, с наветренной стороны, в 7–9 м от середины тропы
static func _make_shelters() -> void:
	_shelters.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = 50501
	var s := 70.0
	var total := length()
	while s < total - 40.0:
		var p := point_at(s)
		var sd := side_at(s)
		var wd := wind_dir(p.y)
		var sgn := 1.0 if sd.dot(-wd) >= 0.0 else -1.0
		if absf(sd.dot(wd)) < 0.25:
			sgn = 1.0 if int(s / 80.0) % 2 == 0 else -1.0
		var c := p + sd * sgn * rng.randf_range(7.5, 9.5)
		var r := rng.randf_range(2.4, 3.4)
		var bare := false
		for gap in BARE:
			if s > total * gap.x and s < total * gap.y:
				bare = true
		if not bare and c.distance_to(_camp) > 30.0 and c.distance_to(_hut) > 18.0:
			_shelters.append([c, r])
		s += rng.randf_range(70.0, 95.0)


## Скрытые трещины: вне тропы (не ближе 10 м от её середины), не у лагеря и не у края
static func _make_cracks() -> void:
	_cracks.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = 50777
	var tries := 0
	while _cracks.size() < CREVASSE_COUNT and tries < 4000:
		tries += 1
		# чаще — недалеко от тропы (туда сносит ветер и там срезают углы)
		var s := rng.randf_range(60.0, length() - 60.0)
		var p := point_at(s)
		var sd := side_at(s)
		var off := rng.randf_range(14.0, 60.0) * (1.0 if rng.randf() < 0.5 else -1.0)
		var c := p + sd * off
		if absf(c.x) > HALF - 30.0 or c.y > S_Z - 50.0 or c.y < N_Z + 40.0:
			continue
		var ang := rng.randf_range(0.0, PI)
		var ln := rng.randf_range(12.0, 30.0)
		var hw := rng.randf_range(1.8, 2.6)
		var d := Vector2(cos(ang), sin(ang))
		var a := c - d * ln * 0.5
		var b := c + d * ln * 0.5
		var ok := true
		for t in 7:
			var q := a.lerp(b, t / 6.0)
			if path_dist(q.x, q.y) < hw + 10.0:
				ok = false
				break
		if not ok or c.distance_to(_camp) < 34.0 or c.distance_to(_hut) < 24.0:
			continue
		for sh in _shelters:
			if c.distance_to(sh[0]) < ln * 0.5 + 10.0:
				ok = false
				break
		for cr in _cracks:
			if c.distance_to((cr[0] + cr[1]) * 0.5) < ln * 0.5 + 14.0:
				ok = false
				break
		if not ok:
			continue
		var y := base_y(c.y) + 0.35
		_cracks.append([a, b, hw, y])
		_stamp_crack(a, b, hw, y)


static func _stamp_crack(a: Vector2, b: Vector2, hw: float, y: float) -> void:
	var r := hw + 8.0
	var ix0 := maxi(int(floor((minf(a.x, b.x) - r + HALF) / CELL)), 0)
	var ix1 := mini(int(ceil((maxf(a.x, b.x) + r + HALF) / CELL)), _nx - 1)
	var iz0 := maxi(int(floor((S_Z + 4.0 - maxf(a.y, b.y) - r) / CELL)), 0)
	var iz1 := mini(int(ceil((S_Z + 4.0 - minf(a.y, b.y) + r) / CELL)), _nz - 1)
	var ab := b - a
	var l2 := ab.length_squared()
	for iz in range(iz0, iz1 + 1):
		var z := S_Z + 4.0 - iz * CELL
		for ix in range(ix0, ix1 + 1):
			var p := Vector2(-HALF + ix * CELL, z)
			var t := clampf((p - a).dot(ab) / l2, 0.0, 1.0)
			var d := p.distance_to(a + ab * t) - hw
			var k := iz * _nx + ix
			if d < _cd[k]:
				_cd[k] = d
				_cy[k] = y


## Трещина рядом: (расстояние до края — <0 внутри, высота пласта); далеко — (99, 0)
static func crack_at(x: float, z: float) -> Vector2:
	_ensure()
	var fx := (x + HALF) / CELL
	var fz := (S_Z + 4.0 - z) / CELL
	if fx < 0.0 or fz < 0.0 or fx >= _nx - 1 or fz >= _nz - 1:
		return Vector2(99.0, 0.0)
	var d := _sample(_cd, x, z, 99.0)
	if d > 9.0:
		return Vector2(99.0, 0.0)
	# высота — от ближайшей клетки (не смешиваем с «пустыми» нулями)
	var k := int(round(fz)) * _nx + int(round(fx))
	return Vector2(d, _cy[k])


## Точное расстояние до края трещины (для проверок): <0 — внутри
static func crack_dist(x: float, z: float) -> float:
	_ensure()
	var best := 99.0
	for cr in _cracks:
		var a: Vector2 = cr[0]
		var b: Vector2 = cr[1]
		var ab := b - a
		var t := clampf((Vector2(x, z) - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
		best = minf(best, Vector2(x, z).distance_to(a + ab * t) - float(cr[2]))
	return best
