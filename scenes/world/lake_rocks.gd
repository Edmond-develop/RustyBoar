extends Node3D
## Шаги 140–141: камни на Ледяном поле (вместо вихрей, шипов, кристаллов, торосов и обломков).
##
##  * Завал в узком проходе у пропасти (z 166…208): посередине — гора валунов, у берегов — тоже.
##    Пройти можно только по двум полосам ТОНКОГО льда вдоль завала (IceRiver.THIN_RECTS):
##    каждый шаг оставляет трещины, по чужим следам — риск провала, стоять на месте нельзя.
##  * По полю — группы валунов (ориентиры, укрытия).
## Валуны — Poly Haven (Boulder 01, Rock Boulder Cracked, CC0; облегчённые меши с уровнями LOD),
## шейдер snow_boulder — снег сверху. Мелкие камни — Quaternius Rock_Snow (CC0).
## Всё по фиксированному зерну — одинаково у всех.

const BIG := {"boulder": "res://assets/lake_boulders/boulder_01_lo.res", "cracked": "res://assets/lake_boulders/rock_cracked_lo.res"}
const SMALL := ["Rock_Snow_1", "Rock_Snow_2", "Rock_Snow_3", "Rock_Snow_4", "Rock_Snow_5", "Rock_Snow_6", "Rock_Snow_7"]
const MODELS := ["boulder", "cracked"]
const BOULDER_SHADER := preload("res://shaders/snow_boulder.gdshader")

var _meshes := {}                ## модель → Mesh
var _mats := {}                  ## модель → материал
var _shapes := {}                ## модель → ConvexPolygonShape3D
var _lists := {}                 ## мелкие: модель → [Transform3D]
var _rng := RandomNumberGenerator.new()
var _river: Node


func _ready() -> void:
	_rng.seed = 140140
	_river = get_tree().get_first_node_in_group("ice_lake")
	for k in BIG:
		var m: Mesh = load(BIG[k])
		_meshes[k] = m
		var src := m.surface_get_material(0) as StandardMaterial3D
		var sm := ShaderMaterial.new()
		sm.shader = BOULDER_SHADER
		if src:
			sm.set_shader_parameter("albedo_tex", src.albedo_texture)
			sm.set_shader_parameter("normal_tex", src.normal_texture)
			sm.set_shader_parameter("rough_tex", src.roughness_texture)
			sm.set_shader_parameter("rough_channel", 1 if src.ao_enabled else 0)
		sm.set_shader_parameter("tint", Color(0.9, 0.93, 1.0) if k == "boulder" else Color(0.72, 0.74, 0.8))
		_mats[k] = sm
	var snow := _flat(Color(0.9, 0.93, 0.98), 0.85)
	var rock := _flat(Color(0.3, 0.31, 0.35), 0.9)
	for k2 in SMALL:
		var src_m: Mesh = load("res://assets/hill_nature/%s.obj" % k2)
		var m2 := src_m.duplicate() as Mesh
		for i in m2.get_surface_count():
			var nm := ""
			var sm2 := src_m.surface_get_material(i)
			if sm2:
				nm = sm2.resource_name
			m2.surface_set_material(i, snow if nm == "Snow" else rock)
		_meshes[k2] = m2
		_lists[k2] = []
	_blockade()
	_field_groups()
	_flush()


func _flat(c: Color, r: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = r
	return m


## Валун: модель, центр на льду, «радиус» по горизонтали и высота
func _rock(model: String, at: Vector3, r: float, h: float, yaw: float, tilt := 0.0) -> void:
	var mesh: Mesh = _meshes.get(model)
	if mesh == null:
		return
	var aabb: AABB = mesh.get_aabb()
	var sx := r * 2.0 / maxf(aabb.size.x, 0.01)
	var sz := r * 2.0 / maxf(aabb.size.z, 0.01)
	var sy := h / maxf(aabb.size.y, 0.01)
	var b := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, tilt) * Basis.from_scale(Vector3(sx, sy, sz))
	# низ модели — чуть под лёд
	var org := at - b * Vector3(aabb.get_center().x, aabb.position.y, aabb.get_center().z) + Vector3.DOWN * h * 0.12
	var xf := Transform3D(b, org)
	if _lists.has(model):
		(_lists[model] as Array).append(xf)
		if r < 0.6:
			return                      # мелочь — без столкновений
	else:
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = _mats[model]
		mi.visibility_range_end = 650.0
		mi.lod_bias = 0.6
		add_child(mi)
		mi.global_transform = xf
	var body := StaticBody3D.new()
	body.add_to_group("lake_rock")
	var cs := CollisionShape3D.new()
	cs.shape = _shape(model)
	body.add_child(cs)
	add_child(body)
	body.global_transform = xf


func _shape(model: String) -> Shape3D:
	if not _shapes.has(model):
		var mesh: Mesh = _meshes[model]
		_shapes[model] = mesh.create_convex_shape(true, true)
	return _shapes[model]


func _pick() -> String:
	return MODELS[0] if _rng.randf() < 0.6 else MODELS[1]


func _small() -> String:
	return SMALL[_rng.randi() % SMALL.size()]


## Завал в проходе: середина |x| < 30 и берега |x| > 38.5 (между ними — тонкий лёд)
func _blockade() -> void:
	var y := IceRiver.river_y(180.0)
	# середина: плотно, в два слоя, высокие валуны
	var z := 168.0
	while z < 208.0:
		var x := -26.0
		while x <= 26.0:
			var r := _rng.randf_range(3.2, 4.6)
			var px := clampf(x + _rng.randf_range(-1.5, 1.5), -30.0 + r * 0.85, 30.0 - r * 0.85)
			_rock(_pick(), Vector3(px, y, z + _rng.randf_range(-1.5, 1.5)), r, _rng.randf_range(4.0, 7.5), _rng.randf() * TAU, _rng.randf_range(-0.15, 0.15))
			x += _rng.randf_range(5.0, 7.0)
		z += _rng.randf_range(5.5, 7.0)
	# сверху — ещё валуны (гора)
	for i in 14:
		var p := Vector3(_rng.randf_range(-20.0, 20.0), y + _rng.randf_range(3.0, 5.0), _rng.randf_range(172.0, 204.0))
		_rock(_pick(), p, _rng.randf_range(2.0, 3.4), _rng.randf_range(2.5, 4.5), _rng.randf() * TAU, _rng.randf_range(-0.4, 0.4))
	# у берегов: от кромки тонкого льда (38.5) до стен прохода
	for sd in [-1.0, 1.0]:
		var zz := 161.0
		while zz < 212.0:
			var xx := 38.5
			while xx < 66.0:
				var r2 := _rng.randf_range(3.0, 4.5)
				var cx := maxf(xx + r2 * 0.85, 38.5 + r2 * 0.85)
				var gy := _ground(sd * cx, zz)
				_rock(_pick(), Vector3(sd * cx, gy, zz + _rng.randf_range(-1.2, 1.2)), r2, _rng.randf_range(4.5, 8.0), _rng.randf() * TAU)
				xx += _rng.randf_range(5.0, 7.0)
			zz += _rng.randf_range(5.0, 6.5)
	# мелкие камни у кромки завала (не на тонком льду)
	for i in 30:
		var sd2 := -1.0 if i % 2 == 0 else 1.0
		var inner := _rng.randf() < 0.5
		var px2 := sd2 * (_rng.randf_range(28.5, 29.8) if inner else _rng.randf_range(39.2, 40.5))
		_rock(_small(), Vector3(px2, y, _rng.randf_range(166.0, 210.0)), _rng.randf_range(0.35, 0.55), _rng.randf_range(0.6, 1.3), _rng.randf() * TAU)
	# табличка у входа в проход
	var lb := Label3D.new()
	lb.text = "ЗАВАЛ\nОбход — по тонкому льду вдоль камней.\nИдите НЕ след в след и не стойте на месте:\nлёд трещит от каждого шага."
	lb.font_size = 34
	lb.outline_size = 10
	lb.modulate = Color(0.75, 0.92, 1.0)
	lb.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	add_child(lb)
	lb.global_position = Vector3(0.0, y + 4.2, 222.0)


func _ground(x: float, z: float) -> float:
	var t := get_tree().get_first_node_in_group("terrain")
	var g: float = t.height_at(x, z) if t else 0.0
	return maxf(g, IceRiver.river_y(z))


## Группы валунов по полю (2–5 камней), не в полыньях и не посередине пути
func _field_groups() -> void:
	var made := 0
	var tries := 0
	while made < 34 and tries < 600:
		tries += 1
		var z := _rng.randf_range(IceRiver.FIELD_N + 14.0, 500.0)
		var hw := IceRiver.hw_at(z)
		var x := _rng.randf_range(-hw + 14.0, hw - 14.0)
		if absf(x) < 22.0:
			continue
		if _river and _river.has_method("is_hole") and _river.is_hole(x, z, 10.0):
			continue
		var n := _rng.randi_range(2, 5)
		var big := _rng.randf_range(2.2, 4.2)
		for k in n:
			var a := _rng.randf() * TAU
			var d := 0.0 if k == 0 else _rng.randf_range(big * 0.9, big * 2.2)
			var p := Vector3(x + cos(a) * d, IceRiver.river_y(z), z + sin(a) * d)
			var r := big if k == 0 else big * _rng.randf_range(0.35, 0.7)
			_rock(_pick() if k == 0 or r > 1.2 else _small(), p, r, r * _rng.randf_range(0.9, 1.5) if (k == 0 or r > 1.2) else r * 2.0, _rng.randf() * TAU, _rng.randf_range(-0.2, 0.2))
		made += 1


func _flush() -> void:
	for m in _lists:
		var arr: Array = _lists[m]
		if arr.is_empty():
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = _meshes[m]
		mm.instance_count = arr.size()
		for i in arr.size():
			mm.set_instance_transform(i, arr[i])
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		mi.name = "Rocks_" + m
		add_child(mi)
