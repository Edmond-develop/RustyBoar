extends Node3D
## Финал Ледяного каньона: большие ледяные ворота на выходе.
## Чтобы открыть — достать со дна Глубокого озера (рядом, слева от ворот) три печати
## и поставить их в гнёзда на площадке (каждая — в своё, по знаку). Потом один дрон
## подходит к замку перед воротами и жмёт E — головоломка «три сцепленных кольца».
## Решил — створки с грохотом расходятся, путь из каньона открыт.
## Решает хост: ставит печати, открывает ворота; остальным рассылает.

const L := preload("res://scenes/world/canyon_layout.gd")
const SYM := preload("res://scenes/world/gate_symbols.gd")
const PART := preload("res://scenes/world/gate_part.gd")
const PUZZLE := preload("res://scenes/world/gate_puzzle.gd")
const ICE_SHADER := preload("res://shaders/pressure_ice.gdshader")

const DOOR_W := 3.9
const DOOR_H := 8.0
const OPEN_TIME := 4.0

var installed := [false, false, false]
var opened := false
var parts: Array = []
var _open_t := -1.0
var _doors: Array[AnimatableBody3D] = []
var _sockets: Array[Vector3] = []
var _socket_sym: Array[MeshInstance3D] = []
var _socket_light: Array[OmniLight3D] = []
var _veins: Array[StandardMaterial3D] = []
var _console: Vector3
var _status: Label3D
var _hint: Label3D
var _puzzle: CanvasLayer
var _prev_mouse := Input.MOUSE_MODE_CAPTURED
var _dust: GPUParticles3D
var _glow: OmniLight3D
var _clock := 0.0


func _ready() -> void:
	var g: Vector3 = L.GATE
	var ice := ShaderMaterial.new()
	ice.shader = ICE_SHADER
	ice.set_shader_parameter("deep", Color(0.02, 0.1, 0.22))
	ice.set_shader_parameter("mid", Color(0.12, 0.36, 0.58))
	ice.set_shader_parameter("snow_amount", 0.9)
	ice.set_shader_parameter("crack_amount", 0.6)
	ice.set_shader_parameter("band_scale", 0.8)
	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color(0.3, 0.33, 0.38)
	stone.roughness = 0.85
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.35, 0.38, 0.42)
	metal.metallic = 0.8
	metal.roughness = 0.4
	# башни по бокам — от дна пропасти, твёрдые
	var towers := StaticBody3D.new()
	towers.name = "Towers"
	add_child(towers)
	for sgn in [-1.0, 1.0]:
		var tc: Vector3 = g + Vector3(sgn * (DOOR_W + 2.6), 0.0, 0.0)
		_box(towers, Vector3(5.0, 52.0, 5.0), tc + Vector3(0, -17.0, 0), ice, true)
		_box(towers, Vector3(5.8, 1.2, 5.8), tc + Vector3(0, 9.6, 0), stone, false)
		# зубцы
		for k in 4:
			var o := Vector3((k % 2 - 0.5) * 3.6, 10.8, (k / 2 - 0.5) * 3.6)
			_box(towers, Vector3(1.2, 1.4, 1.2), tc + o, stone, false)
		# ледяные шипы-рога
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = 0.9
		cone.height = 6.0
		cone.radial_segments = 6
		var cm := MeshInstance3D.new()
		cm.mesh = cone
		cm.material_override = ice
		cm.position = tc + Vector3(sgn * 1.4, 13.0, 0)
		cm.rotation.z = -sgn * 0.35
		add_child(cm)
	# перемычка над створками
	_box(towers, Vector3(DOOR_W * 2.0 + 10.0, 2.2, 3.4), g + Vector3(0, DOOR_H + 1.1, 0), stone, true)
	# знаки печатей на перемычке (горят, когда печать на месте)
	for i in 3:
		var smi := MeshInstance3D.new()
		smi.mesh = SYM.mesh(int(L.GATE_PARTS[i][1]), 0.55, 0.12)
		var vm := SYM.material(int(L.GATE_PARTS[i][1]), 0.0)
		smi.material_override = vm
		smi.position = g + Vector3((i - 1) * 2.6, DOOR_H + 1.1, 1.75)
		add_child(smi)
		_veins.append(vm)
	# створки: толстые ледяные плиты с железными полосами
	for sgn in [-1.0, 1.0]:
		var d := AnimatableBody3D.new()
		d.name = "Door%s" % ("L" if sgn < 0 else "R")
		d.sync_to_physics = false
		add_child(d)
		d.global_position = g + Vector3(sgn * DOOR_W * 0.5, DOOR_H * 0.5, 0)
		_box(d, Vector3(DOOR_W, DOOR_H, 1.2), Vector3.ZERO, ice, true, true)
		for k in 3:
			_box(d, Vector3(DOOR_W - 0.2, 0.3, 1.35), Vector3(0, -DOOR_H * 0.5 + 1.4 + k * 2.8, 0), metal, false, true)
		_box(d, Vector3(0.3, DOOR_H, 1.4), Vector3(-sgn * (DOOR_W * 0.5 - 0.15), 0, 0), metal, false, true)
		_doors.append(d)
	# гнёзда для печатей: каменные тумбы со знаком сверху
	for i in 3:
		var sp: Vector3 = L.GATE_SOCKETS[i]
		_sockets.append(sp + Vector3(0, 1.1, 0))
		var body := StaticBody3D.new()
		add_child(body)
		_box(body, Vector3(1.2, 1.0, 1.2), sp + Vector3(0, 0.5, 0), stone, true)
		_box(body, Vector3(1.5, 0.15, 1.5), sp + Vector3(0, 1.05, 0), metal, false)
		var smi2 := MeshInstance3D.new()
		smi2.mesh = SYM.mesh(int(L.GATE_PARTS[i][1]), 0.32, 0.05)
		smi2.material_override = SYM.material(int(L.GATE_PARTS[i][1]), 0.6)
		smi2.position = sp + Vector3(0, 1.75, 0)
		add_child(smi2)
		_socket_sym.append(smi2)
		var lb := Label3D.new()
		lb.text = "Гнездо: %s\n(знак «%s»)" % [L.GATE_PARTS[i][0], SYM.NAMES[int(L.GATE_PARTS[i][1])]]
		lb.font_size = 30
		lb.outline_size = 8
		lb.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
		lb.position = sp + Vector3(0, 2.6, 0)
		lb.modulate = SYM.COLORS[int(L.GATE_PARTS[i][1])]
		lb.visibility_range_end = 40.0
		add_child(lb)
		var sl := OmniLight3D.new()
		sl.light_color = SYM.COLORS[int(L.GATE_PARTS[i][1])]
		sl.light_energy = 0.0
		sl.omni_range = 6.0
		sl.position = sp + Vector3(0, 1.8, 0)
		add_child(sl)
		_socket_light.append(sl)
	# замок перед воротами: каменный пюпитр с тремя кольцами
	_console = g + Vector3(-4.7, 0, 4.0)   # сбоку от прохода, у левой башни
	var cb := StaticBody3D.new()
	add_child(cb)
	_box(cb, Vector3(1.2, 1.1, 0.8), _console + Vector3(0, 0.55, 0), stone, true)
	for k in 3:
		var tor := TorusMesh.new()
		tor.inner_radius = 0.16
		tor.outer_radius = 0.24
		tor.rings = 12
		tor.ring_segments = 6
		var tm := MeshInstance3D.new()
		tm.mesh = tor
		tm.material_override = metal
		tm.position = _console + Vector3((k - 1) * 0.38, 1.2, 0.0)
		tm.rotation.x = PI * 0.5
		add_child(tm)
	_status = Label3D.new()
	_status.font_size = 40
	_status.outline_size = 12
	_status.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	_status.position = g + Vector3(0, DOOR_H + 3.4, 1.0)
	add_child(_status)
	_hint = Label3D.new()
	_hint.font_size = 34
	_hint.outline_size = 10
	_hint.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_hint.position = _console + Vector3(0, 2.0, 0)
	_hint.modulate = Color(1.0, 0.9, 0.5)
	_hint.visible = false
	add_child(_hint)
	_dust = FX.particles(Color(0.85, 0.92, 1.0), 120, 2.0, 0.35, 1.0, 5.0, Vector3(0, -4, 0), 120.0, false)
	FX.set_box(_dust, Vector3(DOOR_W, 0.5, 1.0))
	_dust.position = g + Vector3(0, 0.6, 0)
	_dust.emitting = false
	add_child(_dust)
	_glow = OmniLight3D.new()
	_glow.light_color = Color(1.0, 0.85, 0.55)
	_glow.light_energy = 0.0
	_glow.omni_range = 14.0
	_glow.position = g + Vector3(0, 3.0, -2.0)
	add_child(_glow)
	_build_grotto()
	_update_status()


## Ящик: меш + (по желанию) столкновение; local — координаты внутри родителя-створки
func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material, solid: bool, local := false) -> void:
	var bm := BoxMesh.new()
	bm.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = bm
	mi.material_override = mat
	parent.add_child(mi)
	if local:
		mi.position = pos
	else:
		mi.global_position = pos
	if solid:
		var shape := BoxShape3D.new()
		shape.size = size
		var col := CollisionShape3D.new()
		col.shape = shape
		parent.add_child(col)
		if local:
			col.position = pos
		else:
			col.global_position = pos


## Детали — на дно озера (каньон зовёт после того, как готово озеро)
func spawn_parts(parent: Node3D) -> void:
	for i in 3:
		var p: Vector3 = L.GATE_PARTS[i][2]
		var bed: float = IceRiver.bed_y(p.x, p.z)
		var part := PART.make(i, L.GATE_PARTS[i][0], int(L.GATE_PARTS[i][1]), Vector3(p.x, bed + 0.5, p.z))
		parent.add_child(part)
		parts.append(part)


## Подводный грот: ледяной свод на дне над второй печатью, вход с одной стороны
func _build_grotto() -> void:
	var gp: Vector3 = L.GATE_PARTS[1][2]
	var bed: float = IceRiver.bed_y(gp.x, gp.z)
	var ice := ShaderMaterial.new()
	ice.shader = ICE_SHADER
	ice.set_shader_parameter("deep", Color(0.02, 0.12, 0.25))
	ice.set_shader_parameter("mid", Color(0.15, 0.45, 0.7))
	ice.set_shader_parameter("snow_amount", 0.0)
	ice.set_shader_parameter("glow", 0.05)
	var body := StaticBody3D.new()
	body.name = "Grotto"
	add_child(body)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var faces := PackedVector3Array()
	# полукольцо свода вдоль оси x, длина 7 м, вход — с восточной стороны (к берегу)
	var r_in := 2.9
	var r_out := 3.9
	var n := 12
	var x0 := gp.x - 4.0
	var x1 := gp.x + 3.0
	# свод идёт по дну (дно к берегу поднимается)
	var b0: float = IceRiver.bed_y(x0, gp.z) - 0.4
	var b1: float = IceRiver.bed_y(x1, gp.z) - 0.4
	for k in n:
		var a0 := PI * k / n
		var a1 := PI * (k + 1) / n
		for rr in [r_in, r_out]:
			var p00 := Vector3(x0, b0 + sin(a0) * rr, gp.z + cos(a0) * rr)
			var p01 := Vector3(x0, b0 + sin(a1) * rr, gp.z + cos(a1) * rr)
			var p10 := Vector3(x1, b1 + sin(a0) * rr, gp.z + cos(a0) * rr)
			var p11 := Vector3(x1, b1 + sin(a1) * rr, gp.z + cos(a1) * rr)
			var tris := [p00, p10, p11, p00, p11, p01] if rr == r_out else [p00, p11, p10, p00, p01, p11]
			for t in tris:
				st.add_vertex(t)
				faces.append(t)
		# торцевые кольца толщины свода
		for xx in [x0, x1]:
			var by: float = b0 if xx == x0 else b1
			var q0 := Vector3(xx, by + sin(a0) * r_in, gp.z + cos(a0) * r_in)
			var q1 := Vector3(xx, by + sin(a1) * r_in, gp.z + cos(a1) * r_in)
			var q2 := Vector3(xx, by + sin(a1) * r_out, gp.z + cos(a1) * r_out)
			var q3 := Vector3(xx, by + sin(a0) * r_out, gp.z + cos(a0) * r_out)
			for t in [q0, q1, q2, q0, q2, q3]:
				st.add_vertex(t)
				faces.append(t)
	# задняя стенка (запад) — грот глухой, вход только с востока
	for k in n:
		var a0 := PI * k / n
		var a1 := PI * (k + 1) / n
		var c := Vector3(x0 - 0.1, b0, gp.z)
		var q0 := Vector3(x0 - 0.1, b0 + sin(a0) * r_out, gp.z + cos(a0) * r_out)
		var q1 := Vector3(x0 - 0.1, b0 + sin(a1) * r_out, gp.z + cos(a1) * r_out)
		for t in [c, q0, q1]:
			st.add_vertex(t)
			faces.append(t)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = ice
	body.add_child(mi)
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(faces)
	var col := CollisionShape3D.new()
	col.shape = shape
	body.add_child(col)
	var l := OmniLight3D.new()
	l.light_color = Color(0.4, 0.8, 1.0)
	l.light_energy = 1.2
	l.omni_range = 5.0
	l.position = Vector3(gp.x, bed + 1.6, gp.z)
	add_child(l)


func ready_to_unlock() -> bool:
	return installed[0] and installed[1] and installed[2]


func _update_status() -> void:
	if opened:
		_status.text = "ВОРОТА ОТКРЫТЫ"
		_status.modulate = Color(0.6, 1.0, 0.6)
		return
	var n: int = installed.count(true)
	if n < 3:
		_status.text = "ВОРОТА ЗАПЕЧАТАНЫ\nПечатей на месте: %d из 3\nОни — где-то на дне Глубокого озера: ищите" % n
		_status.modulate = Color(0.75, 0.88, 1.0)
	else:
		_status.text = "Печати на месте!\nПодойди к замку и нажми E"
		_status.modulate = Color(1.0, 0.9, 0.5)


func _physics_process(delta: float) -> void:
	_clock += delta
	var t: float = Network.game_time if Network.in_game else _clock
	# створки
	if opened and _open_t >= 0.0:
		var k := smoothstep(0.0, 1.0, clampf((t - _open_t) / OPEN_TIME, 0.0, 1.0))
		for i in 2:
			var sgn := -1.0 if i == 0 else 1.0
			_doors[i].global_position = L.GATE + Vector3(sgn * (DOOR_W * 0.5 + k * (DOOR_W + 0.2)), DOOR_H * 0.5 + 0.08 * sin(t * 30.0) * (1.0 - k) * float(k > 0.0 and k < 1.0), 0)
		_dust.emitting = k > 0.0 and k < 1.0
		_glow.light_energy = 3.0 * (1.0 - absf(k - 0.5) * 2.0) + 0.6 * k
	# хост: печати к гнёздам
	if multiplayer.is_server():
		for i in parts.size():
			var part = parts[i]
			if not is_instance_valid(part) or part.is_delivered or installed[i]:
				continue
			var sp: Vector3 = _sockets[i]
			var d: Vector3 = part.global_position - sp
			if Vector2(d.x, d.z).length() < 2.6 and absf(d.y) < 3.0:
				part.server_deliver(Transform3D(Basis(), sp + Vector3(0, 0.25, 0)))
				_install.rpc(i)
	# замок: подсказка и E
	var me = Network.local_player
	var near: bool = me != null and is_instance_valid(me) and not me.is_dead and me.global_position.distance_to(_console) < 3.0
	_hint.visible = near and not opened and _puzzle == null
	if _hint.visible:
		_hint.text = "E — открыть замок" if ready_to_unlock() else "Нужны все три печати (%d/3)" % installed.count(true)
	if near and not opened and _puzzle == null and ready_to_unlock() and me.held_parcel == null and Input.is_action_just_pressed("interact"):
		open_puzzle()


func open_puzzle() -> void:
	var pz := CanvasLayer.new()
	pz.set_script(PUZZLE)
	var tgt: Array = []
	for i in 3:
		tgt.append(int(L.GATE_PARTS[i][1]))
	pz.set("target", tgt)
	add_child(pz)
	_puzzle = pz
	pz.solved.connect(_on_solved)
	pz.closed.connect(_on_closed)
	_prev_mouse = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var me = Network.local_player
	if me:
		me.input_blocked = true


func _on_closed() -> void:
	_puzzle = null
	Input.mouse_mode = _prev_mouse
	var me = Network.local_player
	if me:
		me.input_blocked = false


func _on_solved() -> void:
	_on_closed()
	if multiplayer.is_server():
		_server_open()
	else:
		_request_open.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func _request_open() -> void:
	if multiplayer.is_server():
		_server_open()


func _server_open() -> void:
	if opened or not ready_to_unlock():
		return
	var t: float = Network.game_time if Network.in_game else _clock
	_open.rpc(t)


@rpc("authority", "call_local", "reliable")
func _install(i: int) -> void:
	installed[i] = true
	_socket_sym[i].material_override = SYM.material(int(L.GATE_PARTS[i][1]), 4.0)
	_socket_light[i].light_energy = 2.0
	_veins[i].emission_energy_multiplier = 4.0
	_update_status()
	get_tree().call_group("level", "show_banner", "Печать на месте: %s" % L.GATE_PARTS[i][0],
		"Все печати на месте — к замку!" if ready_to_unlock() else "Осталось найти: %d" % installed.count(false))


@rpc("authority", "call_local", "reliable")
func _open(t: float) -> void:
	opened = true
	_open_t = t
	_update_status()
	var me = Network.local_player
	if me and me.global_position.distance_to(L.GATE) < 60.0:
		me.add_shake(0.5)
	get_tree().call_group("level", "show_banner", "Ворота открыты!", "Ледяной каньон пройден — путь на север свободен")


## Для тестов: решить головоломку сразу
func solve_for_test() -> void:
	_server_open()
