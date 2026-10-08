extends Node3D
## Замёрзшее озеро из ледяных плиток.
## Тонкий прозрачный лёд в центре быстро трескается под весом дрона,
## толстый белый лёд у берега — почти не трескается.
## Плитка проходит стадии: целая → трещины → сильные трещины → проваливается.
## Под льдом ледяная вода: упавший дрон ломается. Плитки замерзают снова через время.

@export var radius_x := 24.0
@export var radius_z := 17.0
@export var tile := 3.0
@export var thick_ring := 0.72          ## Дальше этой доли радиуса — толстый лёд
@export var thin_rate := 0.45           ## Треск в секунду на тонком льду
@export var thick_mult := 0.15          ## Толстый лёд трескается во столько раз медленнее
@export var carry_mult := 1.6
@export var run_mult := 1.4
@export var landing_stress := 0.45
@export var heal_rate := 0.04           ## Трещины медленно затягиваются
@export var respawn_time := 10.0
@export var water_y := -0.7

var _tiles := {}           # Vector2i -> Dictionary
var _connected: Array = []
var _thin_mats: Array[StandardMaterial3D] = []
var _thick_mats: Array[StandardMaterial3D] = []
var _splash: GPUParticles3D


func _ready() -> void:
	_make_materials()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(tile - 0.06, 0.3, tile - 0.06)
	var shape := BoxShape3D.new()
	shape.size = Vector3(tile, 0.3, tile)
	var slippery := PhysicsMaterial.new()
	slippery.friction = 0.05
	var snowy := PhysicsMaterial.new()
	snowy.friction = 0.35

	var nx := int(ceil(radius_x / tile)) + 1
	var nz := int(ceil(radius_z / tile)) + 1
	for ix in range(-nx, nx + 1):
		for iz in range(-nz, nz + 1):
			var cx := ix * tile
			var cz := iz * tile
			var d := sqrt(pow(cx / radius_x, 2.0) + pow(cz / radius_z, 2.0))
			if d > 1.12:
				continue
			var thick := d > thick_ring
			var body := StaticBody3D.new()
			body.position = Vector3(cx, -0.15, cz)
			body.physics_material_override = snowy if thick else slippery
			var col := CollisionShape3D.new()
			col.shape = shape
			body.add_child(col)
			var mi := MeshInstance3D.new()
			mi.mesh = mesh
			mi.material_override = _thick_mats[0] if thick else _thin_mats[0]
			body.add_child(mi)
			add_child(body)
			_tiles[Vector2i(ix, iz)] = {
				"body": body, "shape": col, "mesh": mi, "thick": thick,
				"stress": 0.0, "stage": 0, "broken": false, "timer": 0.0,
			}

	# Вода подо льдом
	var water := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(radius_x * 2.0 + 6.0, radius_z * 2.0 + 6.0)
	var water_mat := StandardMaterial3D.new()
	water_mat.albedo_color = Color(0.05, 0.18, 0.28, 0.9)
	water_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	water_mat.roughness = 0.05
	water_mat.metallic = 0.4
	plane.material = water_mat
	water.mesh = plane
	water.position.y = water_y
	add_child(water)

	# Кто упал в воду — тот сломался
	var kill_area := Area3D.new()
	var kill_shape := BoxShape3D.new()
	kill_shape.size = Vector3(radius_x * 2.0 + 4.0, 3.0, radius_z * 2.0 + 4.0)
	var kill_col := CollisionShape3D.new()
	kill_col.shape = kill_shape
	kill_area.add_child(kill_col)
	kill_area.position.y = water_y - 1.4
	kill_area.body_entered.connect(_on_water_entered)
	add_child(kill_area)

	_splash = FX.particles(Color(0.75, 0.9, 1.0, 0.9), 70, 1.2, 0.1, 2.0, 6.0, Vector3(0, -12, 0), 40.0)
	_splash.top_level = true
	add_child(_splash)


func _physics_process(delta: float) -> void:
	# Треск льда считает только хост — по всем дронам — и рассылает изменения
	if not multiplayer.is_server():
		return

	for d in get_tree().get_nodes_in_group("player"):
		if not _connected.has(d):
			_connected.append(d)
			d.landed.connect(_on_drone_landed.bind(d))

	# Какие плитки сейчас под дронами и с какой силой давят
	var pressure := {}
	for d in get_tree().get_nodes_in_group("player"):
		var key = _tile_under(d)
		if key == null:
			continue
		var rate := thin_rate
		if d.is_carrying():
			rate *= carry_mult
		if d.is_sprinting:
			rate *= run_mult
		pressure[key] = pressure.get(key, 0.0) + rate

	for key in _tiles:
		var t: Dictionary = _tiles[key]
		if t["broken"]:
			t["timer"] -= delta
			if t["timer"] <= 0.0 and not _anyone_over(key):
				_restore_tile.rpc(key)
			continue
		if pressure.has(key):
			var rate: float = pressure[key]
			if t["thick"]:
				rate *= thick_mult
			t["stress"] += rate * delta
		else:
			t["stress"] = maxf(t["stress"] - heal_rate * delta, 0.0)
		_server_check_tile(key, t)


func _tile_key_at(world_pos: Vector3) -> Vector2i:
	var local := to_local(world_pos)
	return Vector2i(roundi(local.x / tile), roundi(local.z / tile))


func _tile_under(drone: Node) -> Variant:
	if not drone.is_grounded() or drone.is_dead:
		return null
	var local := to_local(drone.global_position)
	if local.y < -0.6 or local.y > 0.8:
		return null
	var key := _tile_key_at(drone.global_position)
	return key if _tiles.has(key) else null


func _anyone_over(key: Vector2i) -> bool:
	for d in get_tree().get_nodes_in_group("player"):
		if _tile_key_at(d.global_position) == key:
			return true
	return false


func _on_drone_landed(fall_speed: float, drone: Node) -> void:
	if not is_instance_valid(drone):
		return
	var key = _tile_under(drone)
	if key == null:
		return
	var t: Dictionary = _tiles[key]
	if t["broken"]:
		return
	var amount := landing_stress * clampf(fall_speed / 6.0, 0.5, 2.0)
	if t["thick"]:
		amount *= thick_mult * 2.0
	t["stress"] += amount
	_server_check_tile(key, t)


func _server_check_tile(key: Vector2i, t: Dictionary) -> void:
	if t["stress"] >= 1.0:
		_break_tile.rpc(key)
		return
	var stage := 0
	if t["stress"] > 0.7:
		stage = 2
	elif t["stress"] > 0.35:
		stage = 1
	if stage != t["stage"]:
		_set_tile_stage.rpc(key, stage)


@rpc("authority", "call_local", "reliable")
func _set_tile_stage(key: Vector2i, stage: int) -> void:
	if not _tiles.has(key):
		return
	var t: Dictionary = _tiles[key]
	if stage > t["stage"] and Network.local_player and _tile_key_at(Network.local_player.global_position) == key:
		Network.local_player.add_shake(0.05)   # хруст под ногами
	t["stage"] = stage
	var mats := _thick_mats if t["thick"] else _thin_mats
	(t["mesh"] as MeshInstance3D).material_override = mats[stage]


@rpc("authority", "call_local", "reliable")
func _break_tile(key: Vector2i) -> void:
	if not _tiles.has(key):
		return
	var t: Dictionary = _tiles[key]
	t["broken"] = true
	t["timer"] = respawn_time
	t["stress"] = 0.0
	t["stage"] = 0
	(t["shape"] as CollisionShape3D).set_deferred("disabled", true)
	(t["mesh"] as MeshInstance3D).visible = false
	var body := t["body"] as Node3D
	_splash.global_position = body.global_position
	_splash.restart()
	if Network.local_player and Network.local_player.global_position.distance_to(body.global_position) < 6.0:
		Network.local_player.add_shake(0.12)


@rpc("authority", "call_local", "reliable")
func _restore_tile(key: Vector2i) -> void:
	if not _tiles.has(key):
		return
	var t: Dictionary = _tiles[key]
	t["broken"] = false
	t["stress"] = 0.0
	t["stage"] = 0
	(t["shape"] as CollisionShape3D).set_deferred("disabled", false)
	var mi := t["mesh"] as MeshInstance3D
	mi.visible = true
	mi.material_override = _thick_mats[0] if t["thick"] else _thin_mats[0]


func _on_water_entered(body: Node3D) -> void:
	if body.has_method("kill"):
		body.kill("ДРОН ПРОВАЛИЛСЯ ПОД ЛЁД")


func _make_materials() -> void:
	# Тонкий лёд: прозрачный голубой, темнеет от трещин
	var thin_colors := [Color(0.62, 0.85, 0.98, 0.7), Color(0.5, 0.7, 0.9, 0.8), Color(0.35, 0.5, 0.75, 0.9)]
	for c in thin_colors:
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.roughness = 0.04
		m.metallic = 0.2
		_thin_mats.append(m)
	# Толстый лёд: белый, присыпан снегом
	var thick_colors := [Color(0.9, 0.95, 1.0), Color(0.78, 0.86, 0.95), Color(0.6, 0.7, 0.85)]
	for c in thick_colors:
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = 0.35
		_thick_mats.append(m)
