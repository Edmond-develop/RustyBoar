class_name IceRiver
extends StaticBody3D
## Огромное замёрзшее озеро — первый участок «Бореи».
##
## С юга на север (шаг 41):
##   915…518  Каток и Ледяной лабиринт (450 м в ширину)
##   518…385  Ледяное поле — расширяется до 800 м, иди куда хочешь
##   385…330  Воронка: поле сужается, по краям — ледяные стены
##   330…302  Узкий скользкий проход между высокими ледяными стенами
##   302…-654 Ледяной каньон (ice_canyon.gd, canyon_layout.gd): дороги в ущельях над пропастью;
##            озера льда здесь нет, кроме трёх замёрзших прудов (POOLS)
##   -654…    дальше озера нет: Снежная пустошь (snow_waste.gd), за ней — прежний мир
##            (лавинный склон и т.д.), сдвинутый к северу
##
## Всё строится из кода по «зерну» layout_seed, поэтому у всех игроков в сети
## озеро и препятствия получаются одинаковыми.
##
## Живой лёд:
##  * каждый проход оставляет на участке 2×2 м трещины (шаг — 1, бег — 2),
##    они рисуются поверх льда (ice_cracks.gd) и с каждым уровнем страшнее;
##  * наступил на участок, где трещины уже есть, — риск провала по таблице crack_risk
##    (1 трещина — 30%, 2 — 60%, 3 — 90%, 4 — 95%, 5 — 99%, 6+ — 100%);
##  * провал без предупреждения: круг ~12 м раскалывается и уходит под воду (ice_collapse.gd);
##  * по озеру разбросаны слабые участки (6–10 м): лёд там чуть темнее и тоньше на вид,
##    и даже на свежем льду с первого шага шанс провалиться — weak_risk (70%);
##  * в полынье дрон плавает (это делает скрипт дрона), посылка держится на плаву.
##
## Вода подо льдом (шаг 18):
##  * глубина разная — от 2 до 12 м (lake_depth): на мелководье лёд светлее и сквозь него
##    видно дно, над глубиной — почти чёрный; рельеф дна строит terrain.gd по той же функции;
##  * подо льдом медленное течение (current_at), может утянуть дрона от полыньи;
##  * вид под водой — мутная вода и столбы света под полыньями (underwater_fx.gd);
##  * на льду стоят жаровни (heat_source.gd): рядом лёд на дроне тает быстро,
##    и лёд вокруг жаровни толстый — не трескается.
##
## Лёд разбит на куски 30×30 м: при новой полынье перестраиваются только соседние куски.
## Высота льда зависит только от z — функция river_y(z) (её же использует рельеф).

@export var half_width := 400.0         ## Самая большая полуширина (Ледяное поле); у каждого z своя — hw_at()
@export var z_start := 915.0
@export var z_end := -654.0
@export var row := 0.5                 ## Шаг рядов сетки льда (меньше — круглее полыньи)
@export var chunk_size := 30.0
@export var layout_seed := 20261008
@export var ice_material: Material
@export var water_material: Material
@export var water_depth := 0.6
@export var ice_friction := 0.045      ## Трение льда (меньше — сильнее скользит)

@export_group("Трещины и проломы")
@export var crack_cell := 2.0          ## Размер участка, м
## Риск провалиться, наступив на участок с N трещинами (N = номер в списке, 0 — свежий лёд)
@export var crack_risk := PackedFloat32Array([0.0, 0.30, 0.60, 0.90, 0.95, 0.99, 1.0])
@export var collapse_radius := 6.0     ## Радиус провала (6 м = круг ~12 м)
@export var weak_spot_count := 64      ## Сколько слабых участков на озере (не больше 64 — столько знает шейдер)
@export var weak_spot_size := Vector2(3.0, 5.0)   ## Радиус слабого участка (м)
@export var weak_risk := 0.7           ## Шанс провалиться на слабом участке с каждого шага
@export var max_dynamic_holes := 150

const SKIRT := 0.35
const COLLAPSE := preload("res://scenes/world/ice_collapse.gd")
const COLLAPSE_WARN := 0.45     ## Сколько лёд трещит паутиной, прежде чем провалиться
var _pending_breaks: Array[Vector3] = []    ## провалы «в процессе» (x, z, радиус)
const UNDERWATER := preload("res://scenes/world/underwater_fx.gd")
const HEATER := preload("res://scenes/world/heat_source.gd")

## Глубина воды (от поверхности воды до дна), м
const DEPTH_MIN := 3.0
const DEPTH_MAX := 16.0
const WATER_GAP := 0.6        ## Насколько вода ниже льда (как water_depth)
const CURRENT_SPEED := 0.3    ## Скорость течения подо льдом, м/с
## Где стоят жаровни: z (по x ищем ближайший к тропе крепкий лёд)
const HEATER_Z := [920.0, 900.0, 505.0, 478.0, 430.0, 380.0]
## Каток и Ледяной лабиринт: толстый старый лёд — не трескается и не проваливается
const TOROS_Z := Vector2(518.0, 916.0)
## Размеры озера для статических функций (как z_start / z_end); LAKE_HALF — ширина у катка и на севере
const LAKE_HALF := 225.0
const LAKE_Z_START := 915.0
const LAKE_Z_END := -654.0     ## (шаг 50: севернее каньона озера больше нет)

## Шаг 41: старый лёд севернее Разломов сдвинут на SHIFT к северу, на его месте — поле и каньон
const SHIFT := 1040.0
const FIELD_HALF := 440.0      ## Полуширина Ледяного поля (шаг 139: было 400)
const FIELD_N := 260.0         ## Северный край поля — дальше воронка (шаг 140: проход длиннее)
const PASS_S := 215.0          ## Воронка кончается — дальше узкий проход (лёд), перегорожен камнями (шаг 140)
## Шаг 140: обход камней — две полосы тонкого льда (x0, x1, z0, z1): трещит от каждого шага, топтаться нельзя
const THIN_RECTS := [Vector4(-37.5, -30.5, 160.0, 212.0), Vector4(30.5, 37.5, 160.0, 212.0)]
const THIN_COLLAPSE := 2.6     ## радиус провала на тонком льду
const THIN_STAND := 1.2        ## стоишь на тонком льду столько секунд — ещё трещина
const CANYON_S := 160.0
const PASS_HALF := 40.0        ## шаг 139: у подножия горы лёд шире (было 14)        ## Горловина каньона (конец воронки)
const CANYON_N := -654.0       ## Северный край каньона — дальше старое озеро
## Замёрзшие пруды в каньоне: [x0, x1, z0, z1, высота льда] (план — canyon_layout.gd)
const POOLS := []                  ## шаг 139: каньона с прудами больше нет (на его месте — Снежная гора, snow_hill.gd)

static var _depth_noise: FastNoiseLite
## Сильные подводные течения: «реки» подо льдом от одной полыньи к другой.
## [ax, az, bx, bz, ширина, скорость]. Одинаковы у всех (строятся по зерну).
static var streams: Array = []
const UNDERWATER_STREAMS := preload("res://scenes/world/lake_streams.gd")
const LAKE_BED := preload("res://scenes/world/lake_bed.gd")
const CRACKS := preload("res://scenes/world/ice_cracks.gd")

## Полыньи (заполняются в _generate_holes и при проломах)
var circles: Array[Vector3] = []       ## (x, z, радиус)
var rects: Array[Vector4] = []         ## (x_min, x_max, z_min, z_max)
## Особые места для расстановки препятствий
var thin_patches: Array[Vector3] = []  ## тонкий лёд над полыньёй (x, z, радиус)
var band_isthmuses: Array[float] = []  ## перешейки в первой полосе полыней (x)
var final_isthmuses: Array[float] = [] ## перешейки в финальной полосе (x)

var _check_timer := 0.0
var _holes_by_row: Array = []
var _chunk_meshes := {}                ## Vector2i -> MeshInstance3D
var _chunk_shapes := {}                ## Vector2i -> CollisionShape3D
var _dynamic_holes := 0

var _cracks := {}                      ## участок -> сколько на нём трещин (общий счётчик)
var _drone_cell := {}                  ## дрон -> участок, на котором он сейчас (у хоста)
var _clock := 0.0
var _crack_fx: Node3D                  ## слой трещин (ice_cracks.gd)
var weak_spots: Array[Vector3] = []    ## слабые участки (x, z, радиус)
var heaters: Array[Vector3] = []       ## жаровни на льду


static func river_y(z: float) -> float:
	if z >= CANYON_S - 2.0:
		return 0.0
	if z > CANYON_N:
		for p in POOLS:                          # пруды каньона (по z не пересекаются по высоте)
			if z > p[2] - 2.0 and z < p[3] + 2.0:
				return p[4]
		return -8.0
	return _old_river_y(z + SHIFT)


## Полуширина льда на этой широте (в каньоне — 0, там только пруды)
static func hw_at(z: float) -> float:
	if z >= 518.0:
		return LAKE_HALF
	if z >= 490.0:
		return lerpf(LAKE_HALF, FIELD_HALF, smoothstep(518.0, 490.0, z))
	if z >= FIELD_N:
		return FIELD_HALF
	if z >= PASS_S:
		return lerpf(PASS_HALF, FIELD_HALF, (z - PASS_S) / (FIELD_N - PASS_S))
	if z >= CANYON_S:
		return PASS_HALF
	if z > CANYON_N:
		return 0.0
	return LAKE_HALF


## Где по x есть лёд на этой широте: отрезки (x0, x1)
static func spans_at(z: float) -> Array[Vector2]:
	var out: Array[Vector2] = []
	if z >= LAKE_Z_START or z <= LAKE_Z_END:
		return out
	if z > CANYON_N and z < CANYON_S:
		for p in POOLS:
			if z > p[2] and z < p[3]:
				out.append(Vector2(p[0], p[1]))
		return out
	var hw := hw_at(z)
	out.append(Vector2(-hw, hw))
	return out


## Точка над озером (с отступом margin от края льда)
static func in_lake(x: float, z: float, margin: float = 0.0) -> bool:
	if z >= LAKE_Z_START - margin or z <= LAKE_Z_END + margin:
		return false
	for sp in spans_at(z):
		if x > sp.x + margin and x < sp.y - margin:
			if z > CANYON_N and z < CANYON_S:
				# в пруду — отступ и по z
				for p in POOLS:
					if x > p[0] and x < p[1] and z > p[2] + margin and z < p[3] - margin:
						return true
				return false
			return true
	return false


## Пруд каньона в этой точке (или пустой массив)
static func pool_at(x: float, z: float) -> Array:
	for p in POOLS:
		if x > p[0] and x < p[1] and z > p[2] and z < p[3]:
			return p
	return []


static func _old_river_y(z: float) -> float:
	if z >= 410.0:
		return 0.0
	if z >= 394.0:
		return lerpf(0.0, -2.5, smoothstep(410.0, 394.0, z))
	if z >= 252.0:
		return -2.5
	if z >= 238.0:
		return lerpf(-2.5, -5.0, smoothstep(252.0, 238.0, z))
	if z >= 92.0:
		return -5.0
	if z >= 80.0:
		return lerpf(-5.0, 0.0, smoothstep(92.0, 80.0, z))
	return 0.0


static func _noise() -> FastNoiseLite:
	if _depth_noise == null:
		_depth_noise = FastNoiseLite.new()
		_depth_noise.seed = 9137
		_depth_noise.frequency = 0.011
		_depth_noise.fractal_octaves = 3
	return _depth_noise


## Глубина воды в точке (м): от DEPTH_MIN до DEPTH_MAX, у берегов мельче.
## Одна и та же у всех игроков (не зависит от случайности).
static func lake_depth(x: float, z: float) -> float:
	# старое озеро сдвинуто на SHIFT — глубины берём по его прежним координатам (дно то же, что было)
	var zs := z + SHIFT if z <= CANYON_N else z
	var n := _noise().get_noise_2d(x, zs) * 0.5 + 0.5
	var t := smoothstep(0.32, 0.68, n)
	if z > CANYON_N and z < CANYON_S - 2.0:
		var pl := pool_at(x, z)
		if pl.size() > 5:
			return deep_pool_depth(x, z, pl)
		return lerpf(2.6, 4.0, t)       # пруды каньона неглубокие
	var edge := minf(minf(hw_at(z) - absf(x), LAKE_Z_START - z), z - LAKE_Z_END)
	if z <= CANYON_N:
		edge = minf(edge, CANYON_N - z)
	t *= smoothstep(0.0, 30.0, edge)
	return lerpf(DEPTH_MIN, DEPTH_MAX, t)


## Насколько вода студит дрона (1 — как везде; в Глубоком озере у ворот — тёплые ключи)
static func water_cold(x: float, z: float) -> float:
	if z > CANYON_N and z < CANYON_S:
		var pl := pool_at(x, z)
		if pl.size() > 5:
			return 0.25
	return 1.0


## Глубокое озеро у ворот: у берега площадки мелко, к западу глубже, яма и грот — по плану
static func deep_pool_depth(x: float, z: float, pl: Array) -> float:
	var maxd: float = pl[5]
	var shore := minf(minf(x - pl[0], pl[1] - x), minf(z - pl[2], pl[3] - z))
	var d := lerpf(2.5, maxd - 4.0, smoothstep(pl[1] - 2.0, pl[1] - 28.0, x))
	# глубокая яма
	pass
	# у берега — отмель
	d = minf(d, 1.2 + shore * 1.4)
	return clampf(d, 1.0, maxd)


## Высота дна озера
static func bed_y(x: float, z: float) -> float:
	return river_y(z) - WATER_GAP - lake_depth(x, z)


## Сильные течения: от полыньи A к соседней полынье B (16–34 м), подо льдом.
## Упал в такую полынью — утащит под лёд и вынесет к следующей.
func _generate_streams() -> void:
	streams.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = layout_seed + 4242
	var cand: Array[Vector3] = []
	for c in circles:
		var zone_ok := c.y > FIELD_N + 5.0 and c.y < 512.0
		if zone_ok and c.z >= 1.5 and absf(c.x) < hw_at(c.y) - 20.0:
			cand.append(c)
	var used := {}
	var tries := 0
	while streams.size() < 16 and tries < 600 and cand.size() > 2:
		tries += 1
		var ai := rng.randi() % cand.size()
		if used.has(ai):
			continue
		var a: Vector3 = cand[ai]
		var best := -1
		for bi in cand.size():
			if bi == ai or used.has(bi):
				continue
			var b: Vector3 = cand[bi]
			var dist := Vector2(b.x - a.x, b.y - a.y).length()
			if dist > 16.0 + a.z and dist < 34.0 and rng.randf() < 0.5:
				best = bi
				break
		if best < 0:
			continue
		var bb: Vector3 = cand[best]
		used[ai] = true
		used[best] = true
		streams.append([a.x, a.y, bb.x, bb.y, rng.randf_range(5.5, 7.5), rng.randf_range(2.8, 3.6)])


## Сильное течение в точке (м/с) — только внутри «рек» подо льдом
static func stream_at(x: float, z: float) -> Vector3:
	var v := Vector3.ZERO
	for s in streams:
		var ax: float = s[0]
		var az: float = s[1]
		var dx: float = s[2] - ax
		var dz: float = s[3] - az
		var L := sqrt(dx * dx + dz * dz)
		if L < 0.1:
			continue
		var nx := dx / L
		var nz := dz / L
		var px := x - ax
		var pz := z - az
		var t := px * nx + pz * nz
		if t < -3.0 or t > L + 2.0:
			continue
		var lx := px - nx * t
		var lz := pz - nz * t
		var d := sqrt(lx * lx + lz * lz)
		var w: float = s[4]
		if d > w:
			continue
		var k := (1.0 - smoothstep(w * 0.55, w, d)) * smoothstep(-3.0, 1.0, t) * (1.0 - smoothstep(L - 3.0, L + 1.5, t))
		var sp: float = s[5]
		v += Vector3(nx, 0.0, nz) * sp * k
		if d > 0.01:
			v -= Vector3(lx / d, 0.0, lz / d) * 0.5 * k * (d / w)   # затягивает в середину струи
	return v


## Течение подо льдом в точке (горизонтальная скорость, м/с)
static func current_at(x: float, z: float) -> Vector3:
	var a := _noise().get_noise_2d(z * 0.6 + 731.0, x * 0.6 - 417.0) * TAU * 1.5
	return Vector3(cos(a), 0.0, sin(a)) * CURRENT_SPEED


func is_hole(x: float, z: float, pad: float = 0.0) -> bool:
	for c in circles:
		if Vector2(x - c.x, z - c.y).length() < c.z + pad:
			return true
	for r in rects:
		if x > r.x - pad and x < r.y + pad and z > r.z - pad and z < r.w + pad:
			return true
	return false


func in_bounds(pos: Vector3) -> bool:
	return in_lake(pos.x, pos.z)


## Высота поверхности воды в полыньях
func water_y(z: float) -> float:
	return river_y(z) - water_depth


## Точка в открытой воде (в полынье, ниже уровня льда)
func is_open_water(pos: Vector3) -> bool:
	return in_bounds(pos) and is_hole(pos.x, pos.z) and pos.y < river_y(pos.z) - 0.25


## Куда выбраться из полыньи: ближайшая точка твёрдого льда в пределах reach.
## prefer — направление, которое предпочитаем (куда смотрит/плывёт дрон).
## Возвращает Vector3.INF, если твёрдого льда рядом нет.
func nearest_ice(pos: Vector3, reach: float, prefer: Vector3 = Vector3.ZERO) -> Vector3:
	var near_c: Array[Vector3] = []
	for c in circles:
		if Vector2(pos.x - c.x, pos.z - c.y).length() < c.z + reach + 1.0:
			near_c.append(c)
	var near_r: Array[Vector4] = []
	var m := reach + 1.0
	for r in rects:
		if pos.x > r.x - m and pos.x < r.y + m and pos.z > r.z - m and pos.z < r.w + m:
			near_r.append(r)
	var best := Vector3.INF
	var best_score := INF
	for i in 16:
		var a := TAU * i / 16.0
		var dir := Vector3(cos(a), 0.0, sin(a))
		var d := 0.3
		while d <= reach:
			var q := pos + dir * d
			if _solid_ice(q.x, q.z, near_c, near_r):
				var land := pos + dir * (d + 0.5)
				if not _solid_ice(land.x, land.z, near_c, near_r):
					land = q
				var score := d - dir.dot(prefer) * 0.4
				if score < best_score:
					best_score = score
					best = Vector3(land.x, river_y(land.z) + 0.1, land.z)
				break
			d += 0.15
	return best


func _solid_ice(x: float, z: float, near_c: Array[Vector3], near_r: Array[Vector4]) -> bool:
	if not in_lake(x, z, 0.3):
		return false
	for c in near_c:
		if Vector2(x - c.x, z - c.y).length() < c.z + 0.25:
			return false
	for r in near_r:
		if x > r.x - 0.25 and x < r.y + 0.25 and z > r.z - 0.25 and z < r.w + 0.25:
			return false
	return true


func _ready() -> void:
	add_to_group("safe_ground")
	add_to_group("ice_lake")
	var slippery := PhysicsMaterial.new()
	slippery.friction = ice_friction
	physics_material_override = slippery

	var rng := RandomNumberGenerator.new()
	rng.seed = layout_seed
	_generate_holes(rng)
	_generate_weak_spots()
	_generate_streams()
	_build_ice()
	_build_water()
	_make_depth_map()
	var sm := ice_material as ShaderMaterial
	if sm:
		sm.set_shader_parameter("snow_edge_z", z_start)

	_crack_fx = CRACKS.new()
	_crack_fx.name = "Cracks"
	add_child(_crack_fx)

	var layout: IceLayout = IceLayout.new()
	layout.name = "Obstacles"
	add_child(layout)
	layout.build(self, rng)

	var uw := Node3D.new()
	uw.set_script(UNDERWATER)
	uw.name = "Underwater"
	add_child(uw)
	var st := Node3D.new()
	st.set_script(UNDERWATER_STREAMS)
	st.name = "Streams"
	add_child(st)
	var bed := Node3D.new()
	bed.set_script(LAKE_BED)
	bed.name = "LakeBed"
	add_child(bed)
	_place_heaters.call_deferred()


## Карта глубины для шейдера льда: над глубиной лёд темнее, на мелководье видно дно
func _make_depth_map() -> void:
	var sm := ice_material as ShaderMaterial
	if sm == null:
		return
	var step := 3.0
	var w := int(ceil(half_width * 2.0 / step)) + 1
	var h := int(ceil((z_start - z_end) / step)) + 1
	var img := Image.create(w, h, false, Image.FORMAT_R8)
	for j in h:
		for i in w:
			var px := -half_width + i * step
			var pz := z_end + j * step
			var d := lake_depth(px, pz)
			# над сильным течением лёд промыт снизу — темнее (видно «тёмную реку» между полыньями)
			var k := clampf((d - DEPTH_MIN) / (DEPTH_MAX - DEPTH_MIN) + stream_at(px, pz).length() * 0.35, 0.0, 1.0)
			img.set_pixel(i, j, Color(k, 0, 0))
	sm.set_shader_parameter("depth_map", ImageTexture.create_from_image(img))
	sm.set_shader_parameter("depth_rect", Vector4(-half_width - step * 0.5, z_end - step * 0.5, w * step, h * step))


## Жаровни: недалеко от тропы, на крепком льду, где нет препятствий
func _place_heaters() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	var space := get_world_3d().direct_space_state
	var probe := SphereShape3D.new()
	probe.radius = 1.6
	for z in HEATER_Z:
		for k in 24:
			var x := 7.0 + k * 3.0
			if k % 2 == 1:
				x = -x + 3.0
			if is_hole(x, z, 4.0) or is_weak_spot(Vector3(x, 0, z)) or (z < z_start and not in_lake(x, z, 4.0)):
				continue
			var y := river_y(z)
			if z > z_start:   # в лагере — на земле
				var terrain = get_tree().get_first_node_in_group("terrain")
				if terrain:
					y = terrain.height_at(x, z)
			var q := PhysicsShapeQueryParameters3D.new()
			q.shape = probe
			q.transform = Transform3D(Basis.IDENTITY, Vector3(x, y + 1.8, z))
			var blocked := false
			for hit in space.intersect_shape(q, 8):
				var c: Object = hit.get("collider")
				if c != self and not (c is RigidBody3D) and not (c is CharacterBody3D):
					blocked = true
					break
			if blocked:
				continue
			var hs := Node3D.new()
			hs.set_script(HEATER)
			hs.name = "Heater%d" % heaters.size()
			hs.position = Vector3(x, y, z)
			add_child(hs)
			heaters.append(Vector3(x, y, z))
			break


## Рядом с жаровней лёд толстый: не трескается и не проваливается
func near_heater(x: float, z: float, extra: float = 0.0) -> bool:
	for h in heaters:
		if Vector2(x - h.x, z - h.z).length() < 5.0 + extra:
			return true
	return false


func _physics_process(delta: float) -> void:
	_clock += delta
	if multiplayer.is_server():
		_server_wear()

	_check_timer -= delta
	if _check_timer > 0.0:
		return
	_check_timer = 0.25
	# Хост: посылку, утонувшую или застрявшую под льдом, возвращаем на тропу
	if multiplayer.is_server():
		for node in get_tree().get_nodes_in_group("parcel"):
			var p := node as Parcel
			# (печати ворот лежат на дне нарочно — их не трогаем)
			if p and not p.is_held and not p.get("dive_ok") and in_bounds(p.global_position) \
					and p.global_position.y < water_y(p.global_position.z) - 2.0:
				p.server_return_to_path()


# ---------------------------------------------------------------------------
#  Трещины и риск пролома (общие для всех игроков, решает хост)
#
#   Лёд поделён на участки 2×2 м. Каждый проход оставляет на участке трещины:
#   шаг — 1, бег — 2. Свежий лёд безопасен. Наступаешь на участок, где трещины
#   уже есть, — бросаем кубик по таблице crack_risk:
#     1 трещина — 30%, 2 — 60%, 3 — 90%, 4 — 95%, 5 — 99%, 6 и больше — 100%.
#   Не повезло — лёд без предупреждения раскалывается кругом ~12 м и уходит под воду.
# ---------------------------------------------------------------------------

## Стоит ли дрон на льду озера (не в воде и не на заплатке над полыньёй)
func _on_lake_ice(d: Node) -> bool:
	if d.is_dead or not d.is_grounded():
		return false
	var p: Vector3 = d.global_position
	return in_bounds(p) and absf(p.y - river_y(p.z)) < 0.4 and not is_hole(p.x, p.z)


func _cell_of(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x / crack_cell), floori(p.z / crack_cell))


func _cell_center(cell: Vector2i) -> Vector3:
	var x := (cell.x + 0.5) * crack_cell
	var z := (cell.y + 0.5) * crack_cell
	return Vector3(x, river_y(z), z)


## Сколько трещин на льду в этой точке
func cracks_at(p: Vector3) -> int:
	return _cracks.get(_cell_of(p), 0)


## Риск провалиться, наступив на участок с n трещинами
func risk_for(n: int) -> float:
	if n <= 0:
		return 0.0
	return crack_risk[mini(n, crack_risk.size() - 1)]


## Слабые участки — своё «зерно», чтобы не сдвинуть расстановку препятствий
func _generate_weak_spots() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = layout_seed + 7777
	# пруды каньона: лёд в трещинах почти везде
	for k in POOLS.size():
		var pl: Array = POOLS[k]
		var want: int = [7, 5, 0, 0][k]
		var pt := 0
		while want > 0 and pt < 200:
			pt += 1
			var r := rng.randf_range(3.0, 4.6)
			var x: float = rng.randf_range(pl[0] + r + 1.0, pl[1] - r - 1.0)
			var z: float = rng.randf_range(pl[2] + r + 1.0, pl[3] - r - 1.0)
			if is_hole(x, z, r + 1.0):
				continue
			var ok2 := true
			# там, где дорога выходит на пруд, лёд крепкий — первый шаг не в пролом
			for key in CanyonLayout.ROADS:
				for e in [CanyonLayout.ROADS[key][0], CanyonLayout.ROADS[key][-1]]:
					if Vector2(x - e[0], z - e[2]).length() < r + 8.0:
						ok2 = false
			for w in weak_spots:
				if Vector2(x - w.x, z - w.y).length() < r + w.z + 1.5:
					ok2 = false
					break
			if ok2:
				weak_spots.append(Vector3(x, z, r))
				want -= 1
	var tries := 0
	# (шаг 50: озера севернее каньона нет; места, что выпали бы туда, считаем «занятыми»,
	#  чтобы на южном озере слабые участки остались там же, где были)
	var north: Array[Vector3] = []
	while weak_spots.size() + north.size() < weak_spot_count and tries < weak_spot_count * 40:
		tries += 1
		var r := rng.randf_range(weak_spot_size.x, weak_spot_size.y)
		var z := rng.randf_range(-968.0 + r + 4.0, z_start - 18.0)   # у лагеря лёд крепкий
		if z > TOROS_Z.x - r - 4.0 and z < TOROS_Z.y + r + 4.0:
			continue   # в Торосах лёд толстый
		if z > CANYON_N - r - 4.0 and z < PASS_S + 30.0 + r:
			continue   # каньон — там свои пруды; в узком проходе не обойти — там лёд крепкий
		var hw := hw_at(z) if z > CANYON_N else LAKE_HALF
		var x := rng.randf_range(-hw + r + 2.0, hw - r - 2.0)
		if z <= CANYON_N:
			var ok_n := true
			for w in north:
				if Vector2(x - w.x, z - w.y).length() < r + w.z + 6.0:
					ok_n = false
					break
			if ok_n:
				north.append(Vector3(x, z, r))
			continue
		if not in_lake(x, z, r + 2.0) or is_hole(x, z, r + 2.0):
			continue
		var ok := true
		for w in weak_spots:
			if Vector2(x - w.x, z - w.y).length() < r + w.z + 6.0:
				ok = false
				break
		if ok:
			weak_spots.append(Vector3(x, z, r))
	var sm := ice_material as ShaderMaterial
	if sm:
		var arr := PackedVector4Array()
		# шаг 140: полосы тонкого льда — тоже тёмные (на вид как слабый лёд), но риск у них свой
		for r in THIN_RECTS:
			var v: Vector4 = r
			var zc := v.z + 2.5
			while zc < v.w - 1.0:
				arr.append(Vector4((v.x + v.y) * 0.5, zc, 3.7, 0.0))
				zc += 4.0
		for w in weak_spots:
			if arr.size() >= 64:
				break
			arr.append(Vector4(w.x, w.y, w.z, 0.0))
		while arr.size() < 64:
			arr.append(Vector4(0, 0, 0, 0))
		sm.set_shader_parameter("weak_spots", arr)


## Толстый лёд (не трескается): каток и лабиринт, узкий проход к каньону и выход из каньона —
## там проходят все, и обойти нельзя
static func thick_ice(z: float) -> bool:
	return (z > TOROS_Z.x and z < TOROS_Z.y) or (z <= CANYON_N and z > CANYON_N - 14.0)


## Шаг 140: полосы тонкого льда в обход камней
static func thin_ice(x: float, z: float) -> bool:
	for r in THIN_RECTS:
		var v: Vector4 = r
		if x > v.x and x < v.y and z > v.z and z < v.w:
			return true
	return false


func is_weak_spot(p: Vector3) -> bool:
	for w in weak_spots:
		if Vector2(p.x - w.x, p.z - w.y).length() < w.z:
			return true
	return false


func _server_wear() -> void:
	for d in get_tree().get_nodes_in_group("player"):
		if not _on_lake_ice(d):
			continue   # подпрыгнул или на заплатке — участок не сбрасываем, иначе проход засчитается дважды
		var cell := _cell_of(d.global_position)
		var thin := thin_ice(d.global_position.x, d.global_position.z)
		if _drone_cell.get(d, Vector2i(2147483647, 0)) == cell:
			# шаг 140: топчусь на тонком льду — он всё равно трещит
			if thin:
				var st: float = _thin_stand.get(d, 0.0) + get_physics_process_delta_time()
				_thin_stand[d] = st
				if st >= THIN_STAND:
					_thin_stand[d] = 0.0
					_wear_cell(d, cell, true, 1)
			continue
		_thin_stand[d] = 0.0
		var dz: float = d.global_position.z
		if not thin and (near_heater(d.global_position.x, dz) or thick_ice(dz)):
			_drone_cell[d] = cell
			continue
		_drone_cell[d] = cell
		_wear_cell(d, cell, thin, 2 if d.is_sprinting else 1)


var _thin_stand := {}


## Участок под дроном: кубик на провал по числу трещин, иначе — добавить трещины
func _wear_cell(d: Node3D, cell: Vector2i, thin: bool, add: int) -> void:
	var before: int = _cracks.get(cell, 0)
	var risk := risk_for(before)
	if not thin and is_weak_spot(_cell_center(cell)):   # участок слабый, если его центр в слабом пятне
		risk = maxf(risk, weak_risk)
	if randf() < risk:
		var p: Vector3 = d.global_position
		var jr := 0.6 if thin else 1.5
		var jitter := Vector3(randf_range(-jr, jr), 0.0, randf_range(-jr, jr))
		_server_break(p.x + jitter.x, p.z + jitter.z, THIN_COLLAPSE if thin else collapse_radius)
		return
	var v: Vector3 = d.velocity
	var dir_yaw := atan2(-v.z, v.x) if Vector2(v.x, v.z).length() > 0.3 else randf() * PI
	_set_cracks.rpc(cell, before + add, randi(), dir_yaw)


@rpc("authority", "call_local", "reliable")
func _set_cracks(cell: Vector2i, count: int, seed_value: int, dir_yaw: float = NAN) -> void:
	var before: int = _cracks.get(cell, 0)
	_cracks[cell] = count
	var center := _cell_center(cell)
	for lv in range(before + 1, count + 1):
		# первая полоса на участке — вдоль пути дрона, остальные пересекают её
		var yaw := dir_yaw if lv == 1 else NAN
		_crack_fx.add_crack(cell, center, crack_cell, lv, seed_value + lv * 7919, yaw)


## Проломить лёд в точке (можно вызывать на любом компьютере — решит хост)
func request_break(pos: Vector3, radius: float, _warn: float = 0.0) -> void:
	if multiplayer.is_server():
		_server_break(pos.x, pos.z, radius)
	else:
		_rpc_request_break.rpc_id(1, pos.x, pos.z, radius)


@rpc("any_peer", "call_local", "reliable")
func _rpc_request_break(x: float, z: float, radius: float) -> void:
	if multiplayer.is_server():
		_server_break(x, z, radius)


func _server_break(x: float, z: float, radius: float) -> void:
	if _dynamic_holes >= max_dynamic_holes:
		return
	for pb in _pending_breaks:
		if Vector2(pb.x - x, pb.y - z).length() < pb.z + radius:
			return      # тут уже трещит — второй провал не нужен
	if not in_lake(x, z, 1.0) or z > z_start - 3.0:
		return
	if near_heater(x, z, radius):
		return
	_collapse.rpc(x, z, clampf(radius, 0.8, 9.0), randi())


# ---------------------------------------------------------------------------
#  Провал (у всех игроков одинаково): дыра во льду появляется сразу,
#  льдины раскалываются и за полсекунды уходят под воду (ice_collapse.gd)
# ---------------------------------------------------------------------------

@rpc("authority", "call_local", "reliable")
func _collapse(x: float, z: float, radius: float, seed_value: int) -> void:
	# сначала — паутина трещин и дрожь (COLLAPSE_WARN), потом лёд проваливается
	_dynamic_holes += 1
	_pending_breaks.append(Vector3(x, z, radius))
	var fx := Node3D.new()
	fx.set_script(COLLAPSE)
	fx.set("radius", radius)
	fx.set("seed_value", seed_value)
	fx.set("warn", COLLAPSE_WARN)
	fx.position = Vector3(x, river_y(z) + 0.02, z)
	add_child(fx)
	for d in get_tree().get_nodes_in_group("player"):
		var dd := Vector2(d.global_position.x - x, d.global_position.z - z).length()
		if dd < radius + 0.5 and d.has_method("ice_warning"):
			d.ice_warning(Vector3(x, river_y(z), z))
	var me = Network.local_player
	if me:
		var dist := Vector2(me.global_position.x - x, me.global_position.z - z).length()
		if dist < radius + 12.0:
			me.add_shake(clampf(0.18 - dist * 0.01, 0.05, 0.18))
	get_tree().create_timer(COLLAPSE_WARN, true, true).timeout.connect(_open_collapse.bind(x, z, radius, seed_value))


func _open_collapse(x: float, z: float, radius: float, seed_value: int) -> void:
	for i in range(_pending_breaks.size() - 1, -1, -1):
		var pb: Vector3 = _pending_breaks[i]
		if is_equal_approx(pb.x, x) and is_equal_approx(pb.y, z):
			_pending_breaks.remove_at(i)
	circles.append(Vector3(x, z, radius))
	_open_hole_area(x, z, radius)
	_crack_fx.clear_circle(x, z, radius, crack_cell)
	_crack_fx.add_rim_cracks(x, z, radius, seed_value)
	var me = Network.local_player
	if me:
		var dist := Vector2(me.global_position.x - x, me.global_position.z - z).length()
		if dist < radius + 12.0:
			me.add_shake(clampf(0.35 - dist * 0.015, 0.08, 0.35))


func _open_hole_area(x: float, z: float, radius: float) -> void:
	_refresh_area(x - radius, x + radius, z - radius, z + radius)
	# Будим всё, что лежало на этом льду (иначе «спящие» предметы зависнут в воздухе)
	for node in get_tree().get_nodes_in_group("parcel"):
		var rb := node as RigidBody3D
		if rb and Vector2(rb.global_position.x - x, rb.global_position.z - z).length() < radius + 1.5:
			rb.sleeping = false


# ---------------------------------------------------------------------------
#  Где полыньи (по нарастающей сложности)
# ---------------------------------------------------------------------------

func _generate_holes(rng: RandomNumberGenerator) -> void:
	var w := LAKE_HALF

	# Ледяное поле: россыпь небольших полыней и несколько больших разводий
	for i in 100:
		var z := rng.randf_range(FIELD_N + 6.0, 508.0)
		var hw := hw_at(z)
		circles.append(Vector3(rng.randf_range(-hw + 8.0, hw - 8.0), z, rng.randf_range(1.5, 3.0)))
	for i in 15:
		var z := rng.randf_range(FIELD_N + 18.0, 480.0)
		var hw := hw_at(z)
		var x := rng.randf_range(-hw + 30.0, hw - 30.0)
		if absf(x) < 25.0:
			x += 50.0 * signf(x + 0.01)       # посередине поля — свободный проход
		circles.append(Vector3(x, z, rng.randf_range(5.0, 8.5)))

	# шаг 139: каньона с прудами больше нет


## Полоса воды поперёк всего озера, через которую ведут узкие перешейки.
func _band_with_isthmuses(z_min: float, z_max: float, gap_min: float, gap_max: float,
		width_min: float, width_max: float, out: Array[float], rng: RandomNumberGenerator) -> void:
	var w := LAKE_HALF
	var x := -w - 1.0
	while x < w + 1.0:
		var next := x + rng.randf_range(gap_min, gap_max)
		if next > w - 4.0:
			rects.append(Vector4(x, w + 1.0, z_min, z_max))
			break
		var iw := rng.randf_range(width_min, width_max)
		rects.append(Vector4(x, next, z_min, z_max))
		out.append(next + iw * 0.5)
		x = next + iw


# ---------------------------------------------------------------------------
#  Построение льда кусками 30×30 м. Каждый ряд — длинные полосы между полыньями.
# ---------------------------------------------------------------------------

func _row_count() -> int:
	return int(round((z_start - z_end) / row))


func _hole_intervals(zc: float) -> Array[Vector2]:
	var list: Array[Vector2] = []
	for c in circles:
		var dz := zc - c.y
		if absf(dz) < c.z:
			var half := sqrt(c.z * c.z - dz * dz)
			list.append(Vector2(c.x - half, c.x + half))
	for r in rects:
		if zc > r.z and zc < r.w:
			list.append(Vector2(r.x, r.y))
	list.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
	var merged: Array[Vector2] = []
	for iv in list:
		if merged.size() > 0 and iv.x <= merged[-1].y:
			merged[-1] = Vector2(merged[-1].x, maxf(merged[-1].y, iv.y))
		else:
			merged.append(iv)
	return merged


## Полосы льда в ряду: отрезки spans без полыней holes
func _ice_runs(holes: Array, spans: Array[Vector2]) -> Array[Vector2]:
	var runs: Array[Vector2] = []
	for sp in spans:
		var x := sp.x
		for h in holes:
			var a := maxf(h.x, sp.x)
			var b := minf(h.y, sp.y)
			if b <= sp.x or a >= sp.y:
				continue
			if a > x + 0.05:
				runs.append(Vector2(x, a))
			x = maxf(x, b)
		if x < sp.y - 0.05:
			runs.append(Vector2(x, sp.y))
	return runs


## Часть отрезка run, где в соседнем ряду льда нет (там нужен бортик)
func _open_parts(run: Vector2, other: Array) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var x := run.x
	for o in other:
		var a := maxf(o.x, run.x)
		var b := minf(o.y, run.y)
		if b <= a:
			continue
		if a > x + 0.01:
			out.append(Vector2(x, a))
		x = maxf(x, b)
	if x < run.y - 0.01:
		out.append(Vector2(x, run.y))
	return out


func _row_runs(iz: int) -> Array[Vector2]:
	var zc := z_start - (iz + 0.5) * row
	return _ice_runs(_hole_intervals(zc), spans_at(zc))


func _build_ice() -> void:
	var nz := _row_count()
	_holes_by_row.clear()
	for iz in nz:
		_holes_by_row.append(_row_runs(iz))
	var ncx := int(ceil(half_width * 2.0 / chunk_size))
	var ncz := int(ceil((z_start - z_end) / chunk_size))
	for cz in ncz:
		for cx in ncx:
			_build_chunk(Vector2i(cx, cz))


## Перестроить лёд в прямоугольнике (после новой полыньи)
func _refresh_area(x0: float, x1: float, z0: float, z1: float) -> void:
	var nz := _row_count()
	var r0 := clampi(int(floor((z_start - z1) / row)) - 1, 0, nz - 1)
	var r1 := clampi(int(ceil((z_start - z0) / row)) + 1, 0, nz - 1)
	for iz in range(r0, r1 + 1):
		_holes_by_row[iz] = _row_runs(iz)
	var cx0 := int(floor((x0 - 1.0 + half_width) / chunk_size))
	var cx1 := int(floor((x1 + 1.0 + half_width) / chunk_size))
	var cz0 := int(floor((z_start - z1 - 1.0) / chunk_size))
	var cz1 := int(floor((z_start - z0 + 1.0) / chunk_size))
	for cz in range(cz0, cz1 + 1):
		for cx in range(cx0, cx1 + 1):
			var key := Vector2i(cx, cz)
			if _chunk_meshes.has(key):
				_build_chunk(key)


func _build_chunk(key: Vector2i) -> void:
	var xa := -half_width + key.x * chunk_size
	var xb := minf(xa + chunk_size, half_width)
	var nz := _row_count()
	var r0 := int(round(key.y * chunk_size / row))
	var r1 := mini(int(round((key.y + 1) * chunk_size / row)), nz)

	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var faces := PackedVector3Array()

	for iz in range(r0, r1):
		var z0 := z_start - iz * row
		var z1 := z0 - row
		var y0 := river_y(z0) + 0.02
		var y1 := river_y(z1) + 0.02
		var runs: Array = _holes_by_row[iz]
		for full in runs:
			var rx0 := maxf(full.x, xa)
			var rx1 := minf(full.y, xb)
			if rx1 <= rx0 + 0.08:
				continue   # слишком узкая полоска — даёт «вырожденные» треугольники
			var run := Vector2(rx0, rx1)
			var a := Vector3(run.x, y0, z0)
			var b := Vector3(run.y, y0, z0)
			var c := Vector3(run.x, y1, z1)
			var d := Vector3(run.y, y1, z1)
			for v in [a, c, b, b, c, d]:
				verts.append(v)
				normals.append(Vector3.UP)
				faces.append(v)
			# Бортики по бокам — у края полыньи и у края льда (не у края куска)
			if full.x >= xa - 0.001:
				_add_skirt(verts, normals, a, c, Vector3.LEFT)
			if full.y <= xb + 0.001:
				_add_skirt(verts, normals, b, d, Vector3.RIGHT)
			# Бортики спереди/сзади — там, где в соседнем ряду льда нет
			var prev: Array = _holes_by_row[iz - 1] if iz > 0 else []
			for seg in _open_parts(run, prev):
				_add_skirt(verts, normals, Vector3(seg.x, y0, z0), Vector3(seg.y, y0, z0), Vector3.BACK)
			var nxt: Array = _holes_by_row[iz + 1] if iz < nz - 1 else []
			for seg in _open_parts(run, nxt):
				_add_skirt(verts, normals, Vector3(seg.x, y1, z1), Vector3(seg.y, y1, z1), Vector3.FORWARD)

	var mi: MeshInstance3D = _chunk_meshes.get(key)
	if mi == null:
		mi = MeshInstance3D.new()
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visibility_range_end = 320.0
		add_child(mi)
		_chunk_meshes[key] = mi
		var shape := ConcavePolygonShape3D.new()
		shape.backface_collision = true
		var col := CollisionShape3D.new()
		col.shape = shape
		add_child(col)
		_chunk_shapes[key] = col

	var col_node := _chunk_shapes[key] as CollisionShape3D
	if verts.is_empty():
		mi.mesh = null
		col_node.disabled = true
		return
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	if ice_material:
		mesh.surface_set_material(0, ice_material)
	mi.mesh = mesh
	(col_node.shape as ConcavePolygonShape3D).set_faces(faces)
	col_node.disabled = false


func _overlap(run: Vector2, holes: Array) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for h in holes:
		var a := maxf(run.x, h.x)
		var b := minf(run.y, h.y)
		if b > a + 0.01:
			out.append(Vector2(a, b))
	return out


func _add_skirt(verts: PackedVector3Array, normals: PackedVector3Array, p: Vector3, q: Vector3, n: Vector3) -> void:
	var pd := p - Vector3(0, SKIRT, 0)
	var qd := q - Vector3(0, SKIRT, 0)
	for v in [p, q, pd, q, qd, pd]:
		verts.append(v)
		normals.append(n)


func _build_water() -> void:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var z := z_start + 1.0
	while z > z_end - 1.0:
		var z1 := z - 2.0
		var zm := (z + z1) * 0.5
		var in_canyon := zm > CANYON_N - 2.0 and zm < CANYON_S
		var y0 := river_y(zm) - water_depth
		var y1 := y0
		if not in_canyon:
			y0 = river_y(z) - water_depth
			y1 = river_y(z1) - water_depth
		var sps: Array[Vector2] = []
		if in_canyon:
			for pl in POOLS:
				if zm > pl[2] - 1.0 and zm < pl[3] + 1.0:
					sps.append(Vector2(pl[0] - 0.5, pl[1] + 0.5))
		else:
			var hw := maxf(hw_at(z), hw_at(z1))
			sps.append(Vector2(-hw - 2.0, hw + 2.0))
		for sp in sps:
			var a := Vector3(sp.x, y0, z)
			var b := Vector3(sp.y, y0, z)
			var c := Vector3(sp.x, y1, z1)
			var d := Vector3(sp.y, y1, z1)
			for v in [a, c, b, b, c, d]:
				verts.append(v)
				normals.append(Vector3.UP)
		z = z1
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	if water_material:
		mesh.surface_set_material(0, water_material)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
