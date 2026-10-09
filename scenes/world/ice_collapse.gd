extends Node3D
## Провал льда: круг льда раскалывается на льдины, они проседают, кренятся
## и за полсекунды уходят под воду. Часть льдин всплывает и остаётся
## плавать в полынье, остальные тонут. Вокруг — всплески и брызги.
## (Только внешний вид: сама дыра во льду появляется сразу, в ice_river.gd.)

var radius := 6.0
var seed_value := 1

const SINK_TIME := 0.5

static var _mat: StandardMaterial3D
static var _edge_mat: StandardMaterial3D

var _pieces: Array = []     # [{node, delay, center_dist, tilt_axis, tilt, float, end_y}]
var _t := 0.0
var _ice_y := 0.0
var _water_y := 0.0


func _ready() -> void:
	if _mat == null:
		_mat = StandardMaterial3D.new()
		_mat.albedo_color = Color(0.3, 0.55, 0.75, 0.95)
		_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_mat.roughness = 0.08
		_mat.metallic_specular = 0.9
		_mat.rim_enabled = true
		_mat.rim = 0.6
		_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_edge_mat = StandardMaterial3D.new()
		_edge_mat.albedo_color = Color(0.7, 0.88, 1.0)
		_edge_mat.roughness = 0.4
		_edge_mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	_ice_y = IceRiver.river_y(global_position.z) + 0.02
	var lake = get_tree().get_first_node_in_group("ice_lake")
	_water_y = lake.water_y(global_position.z) if lake else _ice_y - 0.6

	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	# Внутренний круг — 4–5 льдин, внешнее кольцо — 9–12 льдин
	_ring(rng, 0.0, radius * rng.randf_range(0.38, 0.48), rng.randi_range(4, 5))
	_ring(rng, radius * 0.43, radius, rng.randi_range(9, 12))

	_burst(rng, 0.0, 70, 7.0)
	for i in 6:
		var a := TAU * i / 6.0 + rng.randf()
		_burst(rng, radius * 0.75, 40, 5.0, Vector3(cos(a), 0, sin(a)))


func _ring(rng: RandomNumberGenerator, r_in: float, r_out: float, count: int) -> void:
	var start := rng.randf() * TAU
	var angles: Array[float] = []
	for i in count + 1:
		angles.append(start + TAU * i / count + (rng.randf_range(-0.12, 0.12) if i > 0 and i < count else 0.0))
	angles[count] = angles[0] + TAU
	for i in count:
		var a0: float = angles[i]
		var a1: float = angles[i + 1]
		var poly := PackedVector2Array()
		var steps := 4
		# внешний край (с неровностями)
		for s in steps + 1:
			var a := lerpf(a0, a1, float(s) / steps)
			var rr := r_out * rng.randf_range(0.95, 1.02)
			poly.append(Vector2(cos(a), sin(a)) * rr)
		# внутренний край
		if r_in < 0.05:
			poly.append(Vector2.ZERO)
		else:
			for s in range(steps, -1, -1):
				var a := lerpf(a0, a1, float(s) / steps)
				poly.append(Vector2(cos(a), sin(a)) * r_in * rng.randf_range(0.97, 1.05))
		var center := Vector2.ZERO
		for p in poly:
			center += p
		center /= poly.size()
		var local := PackedVector2Array()
		for p in poly:
			# небольшой зазор между льдинами
			local.append((p - center) * 0.94)

		var piece := MeshInstance3D.new()
		piece.mesh = _slab(local, rng.randf_range(0.25, 0.4))
		piece.position = Vector3(center.x, 0.0, center.y)
		piece.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(piece)
		var to_center := -Vector3(center.x, 0, center.y).normalized() if center.length() > 0.1 else Vector3.RIGHT
		var floats := r_in > 0.05 and rng.randf() < 0.55   # часть внешних льдин всплывает
		_pieces.append({
			"node": piece,
			"delay": rng.randf_range(0.0, 0.12) + (center.length() / radius) * 0.08,
			"axis": Vector3.UP.cross(to_center).normalized() if to_center.length() > 0.1 else Vector3.RIGHT,
			"tilt": rng.randf_range(0.35, 0.8) * (1.0 if floats else 1.6),
			"floats": floats,
			"spin": rng.randf_range(-0.4, 0.4),
		})


## Плоская льдина по контуру: верх, низ, торцы; торцы светлые (свежий скол)
func _slab(poly: PackedVector2Array, thick: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := poly.size()
	var top := 0.0
	var bottom := -thick
	var c := Vector2.ZERO
	for p in poly:
		c += p
	c /= n
	for i in n:
		var a := poly[i]
		var b := poly[(i + 1) % n]
		st.set_normal(Vector3.UP)
		st.add_vertex(Vector3(c.x, top, c.y))
		st.add_vertex(Vector3(b.x, top, b.y))
		st.add_vertex(Vector3(a.x, top, a.y))
		st.set_normal(Vector3.DOWN)
		st.add_vertex(Vector3(c.x, bottom, c.y))
		st.add_vertex(Vector3(a.x, bottom, a.y))
		st.add_vertex(Vector3(b.x, bottom, b.y))
	var top_mesh := st.commit()
	top_mesh.surface_set_material(0, _mat)

	var st2 := SurfaceTool.new()
	st2.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in n:
		var a := poly[i]
		var b := poly[(i + 1) % n]
		var side := Vector3(b.y - a.y, 0.0, -(b.x - a.x)).normalized()
		st2.set_normal(-side)
		st2.add_vertex(Vector3(a.x, top, a.y))
		st2.add_vertex(Vector3(b.x, top, b.y))
		st2.add_vertex(Vector3(a.x, bottom, a.y))
		st2.add_vertex(Vector3(b.x, top, b.y))
		st2.add_vertex(Vector3(b.x, bottom, b.y))
		st2.add_vertex(Vector3(a.x, bottom, a.y))
	st2.set_material(_edge_mat)
	return st2.commit(top_mesh)


func _burst(rng: RandomNumberGenerator, dist: float, amount: int, speed: float, dir: Vector3 = Vector3.ZERO) -> void:
	var p := FX.particles(Color(0.85, 0.95, 1.0, 0.9), amount, 1.2, 0.12, speed * 0.5, speed, Vector3(0, -12, 0), 35.0)
	p.position = dir * dist + Vector3(0, _water_y - _ice_y + 0.2, 0)
	add_child(p)
	p.restart()


func _process(delta: float) -> void:
	_t += delta
	var all_done := true
	for item in _pieces:
		var obj = item["node"]
		if not is_instance_valid(obj):
			continue   # льдина уже утонула и удалена
		var node := obj as MeshInstance3D
		var t: float = maxf(_t - float(item["delay"]), 0.0)
		var k := clampf(t / SINK_TIME, 0.0, 1.0)
		var ease := k * k * (3.0 - 2.0 * k)
		var drop: float
		if item["floats"]:
			# проседает, ныряет и всплывает на поверхность воды
			var dip := sin(clampf(t / (SINK_TIME * 1.6), 0.0, 1.0) * PI) * 0.35
			drop = lerpf(0.0, _water_y - _ice_y + 0.12, ease) - dip
			var settle := clampf((t - SINK_TIME) / 1.0, 0.0, 1.0)
			var tilt: float = item["tilt"] * ease * (1.0 - settle * 0.85)
			node.basis = Basis(item["axis"], tilt) * Basis(Vector3.UP, float(item["spin"]) * ease)
			node.position.y = drop + sin(_t * 1.5 + node.position.x) * 0.03 * settle
			if t < SINK_TIME * 2.6:
				all_done = false
		else:
			# уходит под воду и исчезает
			drop = lerpf(0.0, _water_y - _ice_y - 2.5, ease * ease)
			node.basis = Basis(item["axis"], float(item["tilt"]) * ease) * Basis(Vector3.UP, float(item["spin"]) * ease)
			node.position.y = drop
			if k >= 1.0:
				node.queue_free()
			else:
				all_done = false
	if all_done:
		set_process(false)   # плавающие льдины остаются, анимация закончена
