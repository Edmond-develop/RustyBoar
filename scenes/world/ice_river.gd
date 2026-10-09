class_name IceRiver
extends StaticBody3D
## Огромное замёрзшее озеро — первый участок «Бореи» (~300 × 400 м).
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

@export var half_width := 150.0
@export var z_start := 495.0
@export var z_end := 92.0
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
@export var weak_spot_count := 25      ## Сколько слабых участков на озере
@export var weak_spot_size := Vector2(3.0, 5.0)   ## Радиус слабого участка (м)
@export var weak_risk := 0.7           ## Шанс провалиться на слабом участке с каждого шага
@export var max_dynamic_holes := 150

const SKIRT := 0.35
const COLLAPSE := preload("res://scenes/world/ice_collapse.gd")
const UNDERWATER := preload("res://scenes/world/underwater_fx.gd")
const HEATER := preload("res://scenes/world/heat_source.gd")

## Глубина воды (от поверхности воды до дна), м
const DEPTH_MIN := 2.0
const DEPTH_MAX := 12.0
const WATER_GAP := 0.6        ## Насколько вода ниже льда (как water_depth)
const CURRENT_SPEED := 0.3    ## Скорость течения подо льдом, м/с
## Где стоят жаровни: z (по x ищем ближайший к тропе крепкий лёд)
const HEATER_Z := [500.0, 478.0, 400.0, 330.0, 245.0, 170.0, 100.0]

static var _depth_noise: FastNoiseLite
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
	var n := _noise().get_noise_2d(x, z) * 0.5 + 0.5
	var t := smoothstep(0.32, 0.68, n)
	var edge := minf(minf(150.0 - absf(x), 495.0 - z), z - 92.0)
	t *= smoothstep(0.0, 30.0, edge)
	return lerpf(DEPTH_MIN, DEPTH_MAX, t)


## Высота дна озера
static func bed_y(x: float, z: float) -> float:
	return river_y(z) - WATER_GAP - lake_depth(x, z)


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
	return absf(pos.x) < half_width and pos.z < z_start and pos.z > z_end


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
	if absf(x) > half_width - 0.3 or z > z_start - 0.3 or z < z_end + 0.3:
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
	_build_ice()
	_build_water()
	_make_depth_map()

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
			var d := lake_depth(-half_width + i * step, z_end + j * step)
			img.set_pixel(i, j, Color((d - DEPTH_MIN) / (DEPTH_MAX - DEPTH_MIN), 0, 0))
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
			if is_hole(x, z, 4.0) or is_weak_spot(Vector3(x, 0, z)):
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
			if p and not p.is_held and in_bounds(p.global_position) \
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
	var tries := 0
	while weak_spots.size() < weak_spot_count and tries < weak_spot_count * 40:
		tries += 1
		var r := rng.randf_range(weak_spot_size.x, weak_spot_size.y)
		var x := rng.randf_range(-half_width + r + 2.0, half_width - r - 2.0)
		var z := rng.randf_range(z_end + r + 4.0, z_start - 18.0)   # у лагеря лёд крепкий
		if is_hole(x, z, r + 2.0):
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
		for w in weak_spots:
			arr.append(Vector4(w.x, w.y, w.z, 0.0))
		while arr.size() < 32:
			arr.append(Vector4(0, 0, 0, 0))
		sm.set_shader_parameter("weak_spots", arr)


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
		if _drone_cell.get(d, Vector2i(2147483647, 0)) == cell:
			continue
		if near_heater(d.global_position.x, d.global_position.z):
			_drone_cell[d] = cell
			continue
		_drone_cell[d] = cell
		var before: int = _cracks.get(cell, 0)
		var risk := risk_for(before)
		if is_weak_spot(_cell_center(cell)):   # участок слабый, если его центр в слабом пятне
			risk = maxf(risk, weak_risk)
		if randf() < risk:
			var p: Vector3 = d.global_position
			var jitter := Vector3(randf_range(-1.5, 1.5), 0.0, randf_range(-1.5, 1.5))
			_server_break(p.x + jitter.x, p.z + jitter.z, collapse_radius)
			continue
		var add := 2 if d.is_sprinting else 1
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
	if absf(x) > half_width - 1.0 or z > z_start - 3.0 or z < z_end + 1.0:
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
	_dynamic_holes += 1
	circles.append(Vector3(x, z, radius))
	_open_hole_area(x, z, radius)
	_crack_fx.clear_circle(x, z, radius, crack_cell)
	_crack_fx.add_rim_cracks(x, z, radius, seed_value)

	var fx := Node3D.new()
	fx.set_script(COLLAPSE)
	fx.set("radius", radius)
	fx.set("seed_value", seed_value)
	fx.position = Vector3(x, river_y(z) + 0.02, z)
	add_child(fx)

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
	var w := half_width

	# Торосы: редкие небольшие полыньи между грядами
	for i in 12:
		var z := rng.randf_range(398.0, 452.0)
		if absf(z - 446.0) < 4.0 or absf(z - 428.0) < 4.0:
			continue
		circles.append(Vector3(rng.randf_range(-w + 5.0, w - 5.0), z, rng.randf_range(1.5, 2.8)))

	# Полыньи: тонкий лёд над водой (трещит под весом)
	var x := -w + 12.0
	while x < w - 10.0:
		var patch := Vector3(x + rng.randf_range(-5.0, 5.0), 330.0 + rng.randf_range(-1.0, 1.0), rng.randf_range(3.2, 4.2))
		thin_patches.append(patch)
		circles.append(patch)
		x += rng.randf_range(24.0, 34.0)

	# Полоса полыней с узкими перешейками
	_band_with_isthmuses(316.0, 322.0, 18.0, 26.0, 1.8, 2.8, band_isthmuses, rng)

	# Разводье во всю ширину (переправа по льдинам)
	rects.append(Vector4(-w - 1.0, w + 1.0, 296.0, 306.0))

	# Россыпь полыней после разводья
	for i in 30:
		circles.append(Vector3(rng.randf_range(-w + 3.0, w - 3.0), rng.randf_range(286.0, 292.0), rng.randf_range(1.5, 2.6)))

	# Гейзеры, ветер и вихри: полыньи между рядами гейзеров
	for i in 26:
		circles.append(Vector3(rng.randf_range(-w + 3.0, w - 3.0), rng.randf_range(146.0, 186.0), rng.randf_range(1.4, 2.6)))

	# Финальное разводье (трамплины или льдины)
	rects.append(Vector4(-w - 1.0, w + 1.0, 113.0, 119.0))

	# Финальная полоса с перешейками
	_band_with_isthmuses(95.0, 101.0, 14.0, 19.0, 3.0, 4.0, final_isthmuses, rng)


## Полоса воды поперёк всего озера, через которую ведут узкие перешейки.
func _band_with_isthmuses(z_min: float, z_max: float, gap_min: float, gap_max: float,
		width_min: float, width_max: float, out: Array[float], rng: RandomNumberGenerator) -> void:
	var w := half_width
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


func _ice_runs(holes: Array) -> Array[Vector2]:
	var runs: Array[Vector2] = []
	var x := -half_width
	for h in holes:
		var a := maxf(h.x, -half_width)
		var b := minf(h.y, half_width)
		if b <= -half_width or a >= half_width:
			continue
		if a > x + 0.05:
			runs.append(Vector2(x, a))
		x = maxf(x, b)
	if x < half_width - 0.05:
		runs.append(Vector2(x, half_width))
	return runs


func _build_ice() -> void:
	var nz := _row_count()
	_holes_by_row.clear()
	for iz in nz:
		_holes_by_row.append(_hole_intervals(z_start - (iz + 0.5) * row))
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
		_holes_by_row[iz] = _hole_intervals(z_start - (iz + 0.5) * row)
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
		var holes: Array = _holes_by_row[iz]
		for full in _ice_runs(holes):
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
			# Бортики по бокам — только у края полыньи (не у края куска и не у края озера)
			if full.x > -half_width + 0.01 and full.x >= xa - 0.001:
				_add_skirt(verts, normals, a, c, Vector3.LEFT)
			if full.y < half_width - 0.01 and full.y <= xb + 0.001:
				_add_skirt(verts, normals, b, d, Vector3.RIGHT)
			# Бортики спереди/сзади — там, где соседний ряд проваливается в воду
			if iz > 0:
				for seg in _overlap(run, _holes_by_row[iz - 1]):
					_add_skirt(verts, normals, Vector3(seg.x, y0, z0), Vector3(seg.y, y0, z0), Vector3.BACK)
			if iz < nz - 1:
				for seg in _overlap(run, _holes_by_row[iz + 1]):
					_add_skirt(verts, normals, Vector3(seg.x, y1, z1), Vector3(seg.y, y1, z1), Vector3.FORWARD)

	var mi: MeshInstance3D = _chunk_meshes.get(key)
	if mi == null:
		mi = MeshInstance3D.new()
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
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
		var y0 := river_y(z) - water_depth
		var y1 := river_y(z1) - water_depth
		var a := Vector3(-half_width - 2.0, y0, z)
		var b := Vector3(half_width + 2.0, y0, z)
		var c := Vector3(-half_width - 2.0, y1, z1)
		var d := Vector3(half_width + 2.0, y1, z1)
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
