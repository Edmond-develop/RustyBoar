class_name IceRiver
extends StaticBody3D
## Огромное замёрзшее озеро — первый участок «Бореи» (~300 × 220 м).
##
## Всё строится из кода по «зерну» layout_seed, поэтому у всех игроков в сети
## озеро и препятствия получаются одинаковыми:
##  * поверхность льда с полыньями (лёд склеивается в длинные полосы — это быстро);
##  * вода подо льдом;
##  * препятствия (их расставляет IceLayout, см. ice_layout.gd);
##  * проверка «провалился»: дрон ломается, посылка возвращается на тропу.
##
## Высота льда зависит только от z — функция river_y(z) (её же использует рельеф).

@export var half_width := 150.0
@export var z_start := 312.0
@export var z_end := 92.0
@export var row := 0.5                 ## Шаг рядов сетки льда (меньше — круглее полыньи)
@export var layout_seed := 20261008
@export var ice_material: Material
@export var water_material: Material
@export var water_depth := 0.6

const SKIRT := 0.35

## Полыньи (заполняются в _generate_holes)
var circles: Array[Vector3] = []       ## (x, z, радиус)
var rects: Array[Vector4] = []         ## (x_min, x_max, z_min, z_max)
## Особые места для расстановки препятствий
var thin_patches: Array[Vector3] = []  ## тонкий лёд над полыньёй (x, z, радиус)
var band_isthmuses: Array[float] = []  ## перешейки в первой полосе полыней (x)
var final_isthmuses: Array[float] = [] ## перешейки в финальной полосе (x)

var _check_timer := 0.0


static func river_y(z: float) -> float:
	if z >= 262.0:
		return 0.0
	if z >= 246.0:
		return lerpf(0.0, -2.5, smoothstep(262.0, 246.0, z))
	if z >= 172.0:
		return -2.5
	if z >= 158.0:
		return lerpf(-2.5, -5.0, smoothstep(172.0, 158.0, z))
	if z >= 92.0:
		return -5.0
	if z >= 80.0:
		return lerpf(-5.0, 0.0, smoothstep(92.0, 80.0, z))
	return 0.0


func is_hole(x: float, z: float, pad: float = 0.0) -> bool:
	for c in circles:
		if Vector2(x - c.x, z - c.y).length() < c.z + pad:
			return true
	for r in rects:
		if x > r.x - pad and x < r.y + pad and z > r.z - pad and z < r.w + pad:
			return true
	return false


func _ready() -> void:
	add_to_group("safe_ground")
	var slippery := PhysicsMaterial.new()
	slippery.friction = 0.04
	physics_material_override = slippery

	var rng := RandomNumberGenerator.new()
	rng.seed = layout_seed
	_generate_holes(rng)
	_build_ice()
	_build_water()

	var layout: IceLayout = IceLayout.new()
	layout.name = "Obstacles"
	add_child(layout)
	layout.build(self, rng)


func _physics_process(delta: float) -> void:
	_check_timer -= delta
	if _check_timer > 0.0:
		return
	_check_timer = 0.1
	var me = Network.local_player
	if me and not me.is_dead and _in_water(me.global_position, 0.4):
		me.kill("ДРОН ПРОВАЛИЛСЯ ПОД ЛЁД")
	if multiplayer.is_server():
		for node in get_tree().get_nodes_in_group("parcel"):
			var p := node as Parcel
			if p and not p.is_held and _in_water(p.global_position, 0.5):
				p.server_return_to_path()


func _in_water(pos: Vector3, margin: float) -> bool:
	if absf(pos.x) > half_width or pos.z > z_start or pos.z < z_end:
		return false
	return pos.y < river_y(pos.z) - margin


# ---------------------------------------------------------------------------
#  Где полыньи (по нарастающей сложности)
# ---------------------------------------------------------------------------

func _generate_holes(rng: RandomNumberGenerator) -> void:
	var w := half_width

	# Торосы: редкие небольшие полыньи
	for i in 14:
		var z := rng.randf_range(250.0, 286.0)
		if absf(z - 282.0) < 3.5 or absf(z - 270.0) < 3.5:
			continue
		circles.append(Vector3(rng.randf_range(-w + 5.0, w - 5.0), z, rng.randf_range(1.5, 3.0)))

	# Тонкий лёд над водой (трещит под весом)
	var x := -w + 12.0
	while x < w - 10.0:
		var patch := Vector3(x + rng.randf_range(-5.0, 5.0), 242.0 + rng.randf_range(-1.0, 1.0), rng.randf_range(3.2, 4.2))
		thin_patches.append(patch)
		circles.append(patch)
		x += rng.randf_range(20.0, 30.0)

	# Полоса полыней с узкими перешейками
	_band_with_isthmuses(232.0, 238.0, 16.0, 22.0, 1.6, 2.6, band_isthmuses, rng)

	# Разводье во всю ширину (переправа по льдинам)
	rects.append(Vector4(-w - 1.0, w + 1.0, 216.0, 226.0))

	# Россыпь полыней после разводья
	for i in 45:
		circles.append(Vector3(rng.randf_range(-w + 3.0, w - 3.0), rng.randf_range(205.0, 214.0), rng.randf_range(1.6, 3.0)))

	# Гейзеры и ветер: полыньи между рядами гейзеров
	for i in 40:
		circles.append(Vector3(rng.randf_range(-w + 3.0, w - 3.0), rng.randf_range(124.0, 156.0), rng.randf_range(1.4, 3.0)))

	# Финальное разводье (трамплины или льдины)
	rects.append(Vector4(-w - 1.0, w + 1.0, 107.0, 113.0))

	# Финальная полоса с перешейками
	_band_with_isthmuses(93.0, 99.0, 13.0, 17.0, 3.0, 4.0, final_isthmuses, rng)


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
#  Построение льда: каждый ряд — несколько длинных полос между полыньями
# ---------------------------------------------------------------------------

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


func _ice_runs(holes: Array[Vector2]) -> Array[Vector2]:
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
	var nz := int(round((z_start - z_end) / row))
	var holes_by_row: Array = []
	for iz in nz:
		holes_by_row.append(_hole_intervals(z_start - (iz + 0.5) * row))

	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var faces := PackedVector3Array()

	for iz in nz:
		var z0 := z_start - iz * row
		var z1 := z0 - row
		var y0 := river_y(z0)
		var y1 := river_y(z1)
		var holes: Array[Vector2] = holes_by_row[iz]
		for run in _ice_runs(holes):
			var a := Vector3(run.x, y0, z0)
			var b := Vector3(run.y, y0, z0)
			var c := Vector3(run.x, y1, z1)
			var d := Vector3(run.y, y1, z1)
			for v in [a, c, b, b, c, d]:
				verts.append(v)
				normals.append(Vector3.UP)
				faces.append(v)
			# Бортики по бокам полосы (если это край полыньи, а не край озера)
			if run.x > -half_width + 0.01:
				_add_skirt(verts, normals, a, c, Vector3.LEFT)
			if run.y < half_width - 0.01:
				_add_skirt(verts, normals, b, d, Vector3.RIGHT)
			# Бортики спереди/сзади — там, где соседний ряд проваливается в воду
			if iz > 0:
				for seg in _overlap(run, holes_by_row[iz - 1]):
					_add_skirt(verts, normals, Vector3(seg.x, y0, z0), Vector3(seg.y, y0, z0), Vector3.BACK)
			if iz < nz - 1:
				for seg in _overlap(run, holes_by_row[iz + 1]):
					_add_skirt(verts, normals, Vector3(seg.x, y1, z1), Vector3(seg.y, y1, z1), Vector3.FORWARD)

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	if ice_material:
		mesh.surface_set_material(0, ice_material)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)

	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	shape.backface_collision = true
	var col := CollisionShape3D.new()
	col.shape = shape
	add_child(col)


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
