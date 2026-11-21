extends Node3D
## Подъёмник через пропасть (каньон, верный путь — единственный способ перебраться).
##
## Сломан: у привода не хватает трёх деталей — шестерни, зажима троса и рычага.
## Детали лежат в тупиках ложных дорог (над каждой — столб света).
## Принёс деталь к приводу (ближе ~3.5 м) — она встаёт на место.
## Когда все три на месте: встал в люльку — через 3 с она едет на другую сторону (~14 с).
## Пустая люлька сама едет за тем, кто ждёт у другого причала.
## Решает хост и рассылает «поехала отсюда туда в такое-то время» — дальше все считают сами.

const ICE_SHADER := preload("res://shaders/pressure_ice.gdshader")
const TRAVEL := 14.0
const DEPART := 3.0
const CABIN := Vector3(5.2, 0.4, 5.2)
const PART_NAMES := ["шестерня", "зажим троса", "рычаг"]

@export var dock_a := Vector3.ZERO      ## причал у L1 (где привод)
@export var dock_b := Vector3.ZERO      ## причал у L2

var installed := [false, false, false]
var at_b := false                        ## где стоит люлька
var moving := false
var _from_b := false
var _move_start := 0.0
var _clock := 0.0
var _depart_t := -1.0
var _armed := true     ## после прибытия люлька ждёт, пока из неё выйдут, и только потом снова повезёт
var _wait_t := 0.0
var _cabin: AnimatableBody3D
var _gates: Array[CollisionShape3D] = []
var _gate_meshes: Array[MeshInstance3D] = []
var _machine: Node3D
var _sockets: Array[Vector3] = []
var _status: Label3D
var _countdown: Label3D
var _wheel: MeshInstance3D
var _dir := Vector3.FORWARD


func _ready() -> void:
	_dir = (dock_b - dock_a)
	_dir.y = 0.0
	_dir = _dir.normalized()
	var side := Vector3(-_dir.z, 0.0, _dir.x)
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.32, 0.3, 0.28)
	metal.metallic = 0.8
	metal.roughness = 0.5
	var rust := StandardMaterial3D.new()
	rust.albedo_color = Color(0.45, 0.25, 0.14)
	rust.metallic = 0.5
	rust.roughness = 0.8
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.35, 0.25, 0.17)
	wood.roughness = 0.9
	# опоры с перекладиной у каждого причала и два троса между ними
	var tops: Array[Vector3] = []
	for dk in [dock_a, dock_b]:
		var back: Vector3 = dk - _dir * (2.5 if dk == dock_a else -2.5)
		for sgn in [-1.0, 1.0]:
			var post := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = 0.22
			cm.bottom_radius = 0.3
			cm.height = 11.0
			cm.material = rust
			post.mesh = cm
			post.position = back + side * sgn * 3.4 + Vector3(0, 5.5, 0)
			add_child(post)
		var bar := MeshInstance3D.new()
		var bb := BoxMesh.new()
		bb.size = Vector3(7.6, 0.45, 0.45)
		bb.material = rust
		bar.mesh = bb
		bar.position = back + Vector3(0, 10.8, 0)
		bar.basis = Basis(Vector3.UP, atan2(-side.z, side.x))
		add_child(bar)
		var wheel := MeshInstance3D.new()
		var wm := CylinderMesh.new()
		wm.top_radius = 1.0
		wm.bottom_radius = 1.0
		wm.height = 0.3
		wm.material = metal
		wheel.mesh = wm
		wheel.position = back + Vector3(0, 10.0, 0)
		wheel.basis = Basis(Vector3.UP, atan2(-side.z, side.x)) * Basis(Vector3.FORWARD, PI * 0.5)
		add_child(wheel)
		if dk == dock_a:
			_wheel = wheel
		tops.append(back + Vector3(0, 10.0, 0))
	for sgn in [-1.0, 1.0]:
		var a: Vector3 = tops[0] + side * sgn * 0.6
		var b: Vector3 = tops[1] + side * sgn * 0.6
		var segs := 12
		for i in segs:
			var p0 := _cable_at(a, b, float(i) / segs)
			var p1 := _cable_at(a, b, float(i + 1) / segs)
			var rope := MeshInstance3D.new()
			var rm := CylinderMesh.new()
			rm.top_radius = 0.06
			rm.bottom_radius = 0.06
			rm.height = p0.distance_to(p1)
			rm.radial_segments = 6
			rm.material = metal
			rope.mesh = rm
			rope.position = (p0 + p1) * 0.5
			rope.basis = Basis(Quaternion(Vector3.UP, (p1 - p0).normalized()))
			rope.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(rope)
	# люлька: пол, борта, решётки-ворота на торцах (закрыты в пути), подвес
	_cabin = AnimatableBody3D.new()
	_cabin.name = "Cabin"
	_cabin.sync_to_physics = true
	_cabin.add_to_group("safe_ground")
	add_child(_cabin)
	_cabin.global_transform = Transform3D(Basis(Vector3.UP, atan2(_dir.x, _dir.z)), dock_a + _dir * CABIN.z * 0.5 - Vector3(0, CABIN.y, 0))
	var floor_mesh := MeshInstance3D.new()
	var fm := BoxMesh.new()
	fm.size = CABIN
	fm.material = wood
	floor_mesh.mesh = fm
	floor_mesh.position.y = CABIN.y * 0.5
	_cabin.add_child(floor_mesh)
	var fshape := BoxShape3D.new()
	fshape.size = CABIN
	var fcol := CollisionShape3D.new()
	fcol.shape = fshape
	fcol.position.y = CABIN.y * 0.5
	_cabin.add_child(fcol)
	for sgn in [-1.0, 1.0]:
		var rail := BoxShape3D.new()
		rail.size = Vector3(0.2, 1.2, CABIN.z)
		var rc := CollisionShape3D.new()
		rc.shape = rail
		rc.position = Vector3(sgn * (CABIN.x * 0.5 - 0.1), CABIN.y + 0.6, 0)
		_cabin.add_child(rc)
		var rm := MeshInstance3D.new()
		var rb := BoxMesh.new()
		rb.size = rail.size
		rb.material = rust
		rm.mesh = rb
		rm.position = rc.position
		_cabin.add_child(rm)
		var gate := BoxShape3D.new()
		gate.size = Vector3(CABIN.x, 1.2, 0.2)
		var gc := CollisionShape3D.new()
		gc.shape = gate
		gc.position = Vector3(0, CABIN.y + 0.6, sgn * (CABIN.z * 0.5 - 0.1))
		gc.disabled = true
		_cabin.add_child(gc)
		_gates.append(gc)
		var gm := MeshInstance3D.new()
		var gb := BoxMesh.new()
		gb.size = gate.size
		gb.material = metal
		gm.mesh = gb
		gm.position = gc.position
		gm.visible = false
		_cabin.add_child(gm)
		_gate_meshes.append(gm)
	for corner in [Vector3(-1, 0, -1), Vector3(1, 0, -1), Vector3(-1, 0, 1), Vector3(1, 0, 1)]:
		var hang := MeshInstance3D.new()
		var hm := CylinderMesh.new()
		hm.top_radius = 0.05
		hm.bottom_radius = 0.05
		hm.height = 9.4
		hm.material = metal
		hang.mesh = hm
		hang.position = Vector3(corner.x * (CABIN.x * 0.5 - 0.1), CABIN.y + 4.7, corner.z * (CABIN.z * 0.5 - 0.1))
		hang.rotation = Vector3(-corner.z * 0.08, 0, corner.x * 0.08)
		_cabin.add_child(hang)
	var roof := MeshInstance3D.new()
	var rfm := BoxMesh.new()
	rfm.size = Vector3(CABIN.x * 0.5, 0.25, CABIN.z * 0.5)
	rfm.material = metal
	roof.mesh = rfm
	roof.position.y = CABIN.y + 9.4
	_cabin.add_child(roof)
	_countdown = Label3D.new()
	_countdown.font_size = 44
	_countdown.outline_size = 12
	_countdown.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_countdown.modulate = Color(1.0, 0.85, 0.4)
	_countdown.position.y = 3.0
	_cabin.add_child(_countdown)
	# привод у причала A: ящик, три гнезда для деталей, табличка
	_machine = Node3D.new()
	_machine.position = dock_a - _dir * 4.5 + side * 3.6
	add_child(_machine)
	var box := MeshInstance3D.new()
	var bxm := BoxMesh.new()
	bxm.size = Vector3(2.2, 1.6, 1.6)
	bxm.material = rust
	box.mesh = bxm
	box.position.y = 0.8
	_machine.add_child(box)
	var body := StaticBody3D.new()
	var bshape := BoxShape3D.new()
	bshape.size = bxm.size
	var bcol := CollisionShape3D.new()
	bcol.shape = bshape
	bcol.position.y = 0.8
	body.add_child(bcol)
	_machine.add_child(body)
	for i in 3:
		var s := Vector3(-0.7 + i * 0.7, 1.75, 0.0)
		_sockets.append(_machine.global_position + s)
	_status = Label3D.new()
	_status.font_size = 40
	_status.outline_size = 12
	_status.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	_status.position = Vector3(0, 3.4, 0)
	_machine.add_child(_status)
	_update_status()


## Точка на провисшем тросе между a и b (t от 0 до 1)
static func _cable_at(a: Vector3, b: Vector3, t: float) -> Vector3:
	return a.lerp(b, t) + Vector3(0, -3.0 * sin(PI * t), 0)


func ready_to_go() -> bool:
	return installed[0] and installed[1] and installed[2]


func _update_status() -> void:
	if ready_to_go():
		_status.text = "ПОДЪЁМНИК РАБОТАЕТ\nвстаньте в люльку"
		_status.modulate = Color(0.5, 1.0, 0.6)
		return
	var need: Array[String] = []
	for i in 3:
		if not installed[i]:
			need.append(PART_NAMES[i])
	_status.text = "ПОДЪЁМНИК СЛОМАН\nНе хватает: %s\nДетали — в тупиках ложных дорог (столбы света)" % ", ".join(need)
	_status.modulate = Color(1.0, 0.6, 0.4)


func _cabin_pos(t: float) -> Vector3:
	var a := dock_a + _dir * CABIN.z * 0.5
	var b := dock_b - _dir * CABIN.z * 0.5
	var k := smoothstep(0.0, 1.0, t)
	return a.lerp(b, k) + Vector3(0, -CABIN.y - 3.0 * sin(PI * k), 0)


func _in_cabin(p: Vector3) -> bool:
	var l := _cabin.to_local(p)
	return absf(l.x) < CABIN.x * 0.5 and absf(l.z) < CABIN.z * 0.5 and l.y > -0.5 and l.y < 3.0


func _physics_process(delta: float) -> void:
	_clock += delta
	var t: float = Network.game_time if Network.in_game else _clock
	if moving:
		var k := clampf((t - _move_start) / TRAVEL, 0.0, 1.0)
		var u := k if not _from_b else 1.0 - k
		_cabin.global_position = _cabin_pos(u)
		if _wheel:
			_wheel.rotate_object_local(Vector3.UP, delta * 2.0)
		if k >= 1.0 and multiplayer.is_server():
			_arrive.rpc(not _from_b)
	else:
		_cabin.global_position = _cabin_pos(1.0 if at_b else 0.0)
	if not multiplayer.is_server():
		return
	# детали: принесли к приводу — ставим на место
	for n in get_tree().get_nodes_in_group("lift_part"):
		var part := n as Parcel
		if part == null or part.is_delivered:
			continue
		var k2: int = int(part.get("kind"))
		if installed[k2]:
			continue
		if part.global_position.distance_to(_machine.global_position + Vector3(0, 1.0, 0)) < 3.8:
			part.server_deliver(Transform3D(Basis(), _sockets[k2]))
			_install.rpc(k2)
	if moving or not ready_to_go():
		return
	var riders := 0
	var waiting_other := false
	var other_dock := dock_a if at_b else dock_b
	for d in get_tree().get_nodes_in_group("player"):
		if d.is_dead:
			continue
		if _in_cabin(d.global_position):
			riders += 1
		elif d.global_position.distance_to(other_dock) < 7.0:
			waiting_other = true
	if riders == 0:
		_armed = true
	if riders > 0 and _armed:
		if _depart_t < 0.0:
			_depart_t = _clock
			_countdown_rpc.rpc(true)
		elif _clock - _depart_t > DEPART:
			_depart_t = -1.0
			_go.rpc(at_b, t)
	elif riders == 0:
		if _depart_t >= 0.0:
			_countdown_rpc.rpc(false)
		_depart_t = -1.0
		if waiting_other:
			_wait_t += delta
			if _wait_t > 2.0:
				_wait_t = 0.0
				_go.rpc(at_b, t)
		else:
			_wait_t = 0.0


@rpc("authority", "call_local", "reliable")
func _install(k: int) -> void:
	installed[k] = true
	_update_status()
	var me = Network.local_player
	if me and me.global_position.distance_to(_machine.global_position) < 30.0:
		me.add_shake(0.1)
	get_tree().call_group("level", "show_banner", "Деталь на месте: %s" % PART_NAMES[k],
		"Подъёмник заработает!" if ready_to_go() else "Осталось найти: %d" % installed.count(false))


@rpc("authority", "call_local", "reliable")
func _countdown_rpc(on: bool) -> void:
	_countdown.visible = on
	if on:
		_countdown.text = "Отправление…"


@rpc("authority", "call_local", "reliable")
func _go(from_b: bool, start: float) -> void:
	moving = true
	_from_b = from_b
	_move_start = start
	_countdown.visible = false
	for g in _gates:
		g.disabled = false
	for gm in _gate_meshes:
		gm.visible = true


@rpc("authority", "call_local", "reliable")
func _arrive(now_at_b: bool) -> void:
	moving = false
	at_b = now_at_b
	_armed = false
	for g in _gates:
		g.disabled = true
	for gm in _gate_meshes:
		gm.visible = false
