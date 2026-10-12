extends Node3D
## Хоккей дронов на катке.
##
## Как играть:
##  * у южного борта стоит стойка с клюшками: подойди и нажми E — взял клюшку
##    (ещё раз E у стойки — вернул; ушёл далеко от поля — клюшка вернётся сама);
##  * подъедь к шайбе — она «прилипнет» к крюку клюшки, можно вести;
##  * ЛКМ (на геймпаде — правый курок) — бросок по направлению камеры:
##    держи кнопку дольше — бросок сильнее (полоска внизу экрана), сильный — с подлётом;
##  * подъедь крюком к шайбе соперника — можешь её отобрать;
##  * без клюшки шайбу можно только толкнуть корпусом.
## Синие ворота — западные, оранжевые — восточные. Шайба в чужих воротах — гол.
##
## Сеть: шайбу считает хост. Кто взял клюшку и у кого шайба — решает хост
## и рассылает всем; бросок клиент просит у хоста (_req_shot).

const CENTER := Vector2(-75.0, 848.0)
const HALF := Vector2(28.0, 15.0)       ## полудлина (x) и полуширина (z) поля
const GOAL_HALF_W := 2.2
const GOAL_H := 1.6
const GOAL_DEPTH := 1.6
const MAX_STICKS := 4
const RACK_RADIUS := 3.5
const STICK_RANGE := 70.0               ## дальше от центра поля — клюшка возвращается
const GRAB_DIST := 0.9                  ## шайба ближе к крюку — прилипает
const STEAL_DIST := 0.75
const SEND_INTERVAL := 0.05
const PUCK_R := 0.3
const CHARGE_TIME := 1.1                ## за сколько секунд бросок заряжается полностью
const SHOT_MIN := 10.0
const SHOT_MAX := 30.0

var holders := {}                       ## peer_id -> true (у кого клюшка)
var possessor := -1                     ## у кого шайба (peer_id) или -1
var score := [0, 0]                     ## [синие, оранжевые]

var _y := 0.0
var _puck: RigidBody3D
var _puck_mesh: MeshInstance3D
var _goals: Array[AABB] = []
var _labels: Array[Label3D] = []
var _rack_pos := Vector3.ZERO
var _rack_sticks: Array[Node3D] = []
var _stick_nodes := {}                  ## peer_id -> Node3D клюшки на дроне
var _cool := {}                         ## peer_id -> пауза, пока нельзя подхватить шайбу
var _prev := {}                         ## дрон -> прошлое положение (толчки корпусом)
var _send := 0.0
var _steal_t := 0.0
var _reset_timer := -1.0
var _net_pos := Vector3.ZERO
var _net_vel := Vector3.ZERO
var _net_age := 0.0
var _charging := false
var _charge := 0.0
var _hud: CanvasLayer
var _charge_bar: ProgressBar
var _hint: Label
var _rack_label: Label3D
var _shaft_mat: StandardMaterial3D
var _tape_mat: StandardMaterial3D


func _ready() -> void:
	add_to_group("hockey")
	_y = IceRiver.river_y(CENTER.y)
	_shaft_mat = StandardMaterial3D.new()
	_shaft_mat.albedo_color = Color(0.85, 0.55, 0.25)
	_shaft_mat.roughness = 0.6
	_tape_mat = StandardMaterial3D.new()
	_tape_mat.albedo_color = Color(0.1, 0.1, 0.12)
	_tape_mat.roughness = 0.8
	_field()
	_rack()
	_make_puck()
	_make_hud()
	_update_labels()
	Network.player_left.connect(_on_player_left)


# ---------------------------------------------------------------------------
#  Поле: борта, разметка, ворота
# ---------------------------------------------------------------------------
func _field() -> void:
	var c := CENTER
	var hx := HALF.x
	var hz := HALF.y
	var snow := StandardMaterial3D.new()
	snow.albedo_color = Color(0.92, 0.95, 1.0)
	snow.roughness = 0.85
	var boards := StaticBody3D.new()
	boards.name = "Boards"
	boards.add_to_group("safe_ground")
	var pm := PhysicsMaterial.new()
	pm.friction = 0.2
	pm.bounce = 0.6
	boards.physics_material_override = pm
	add_child(boards)
	# длинные борта (север и юг) с двумя проходами по 4 м
	for zs in [-1.0, 1.0]:
		var z: float = c.y + zs * hz
		var xs := [c.x - hx, c.x - 12.0, c.x - 8.0, c.x + 8.0, c.x + 12.0, c.x + hx]
		for i in [0, 2, 4]:
			_board(boards, snow, Vector3((xs[i] + xs[i + 1]) * 0.5, _y, z), Vector3(xs[i + 1] - xs[i], 0.8, 0.6))
	# короткие борта с проёмом под ворота
	for xs in [-1.0, 1.0]:
		var x: float = c.x + xs * hx
		var part := hz - GOAL_HALF_W
		_board(boards, snow, Vector3(x, _y, c.y - GOAL_HALF_W - part * 0.5), Vector3(0.6, 0.8, part + 0.6))
		_board(boards, snow, Vector3(x, _y, c.y + GOAL_HALF_W + part * 0.5), Vector3(0.6, 0.8, part + 0.6))
	# разметка — заметно выше льда (лёд на высоте +0.02), иначе линии мерцают,
	# споря со льдом за один и тот же слой
	var red := _unshaded(Color(0.9, 0.15, 0.1))
	var blue := _unshaded(Color(0.15, 0.35, 0.95))
	_flat(Vector3(c.x, _y + 0.07, c.y), Vector3(0.35, 0.02, hz * 2.0), red)
	for xs in [-1.0, 1.0]:
		_flat(Vector3(c.x + xs * hx * 0.45, _y + 0.07, c.y), Vector3(0.35, 0.02, hz * 2.0), blue)
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 4.6
	tm.outer_radius = 5.0
	tm.rings = 48
	tm.material = red
	ring.mesh = tm
	ring.scale = Vector3(1.0, 0.05, 1.0)
	ring.position = Vector3(c.x, _y + 0.07, c.y)
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)
	# ворота: 0 — западные синие, 1 — восточные оранжевые
	for i in 2:
		var sgn := -1.0 if i == 0 else 1.0
		var col := Color(0.2, 0.45, 1.0) if i == 0 else Color(1.0, 0.45, 0.1)
		var mouth_x: float = c.x + sgn * hx
		_goal(mouth_x, sgn, col)
		var box_x := mouth_x if sgn > 0 else mouth_x - GOAL_DEPTH
		_goals.append(AABB(Vector3(box_x + (0.2 if sgn > 0 else 0.0), _y - 0.5, c.y - GOAL_HALF_W + 0.1),
			Vector3(GOAL_DEPTH - 0.2, GOAL_H + 0.4, GOAL_HALF_W * 2.0 - 0.2)))
		_labels.append(_sign("", Vector3(mouth_x + sgn * 0.8, _y + GOAL_H + 1.6, c.y), col, 72))
	_sign("ХОККЕЙ ДРОНОВ", Vector3(c.x, _y + 3.6, c.y + hz + 1.0), Color(1.0, 0.85, 0.5), 64)


func _unshaded(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m


func _board(body: StaticBody3D, mat: Material, center_bottom: Vector3, size: Vector3) -> void:
	var col := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	col.shape = sh
	col.position = center_bottom + Vector3.UP * size.y * 0.5
	body.add_child(col)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	bm.material = mat
	mi.mesh = bm
	mi.position = col.position
	body.add_child(mi)
	# красная полоса по верху борта
	var stripe := MeshInstance3D.new()
	var sm := BoxMesh.new()
	sm.size = Vector3(size.x + 0.02, 0.12, size.z + 0.02)
	sm.material = _unshaded(Color(0.85, 0.2, 0.15))
	stripe.mesh = sm
	# полоса чуть выше верха борта — иначе их верхние грани совпадают и мерцают
	stripe.position = center_bottom + Vector3.UP * (size.y - 0.03)
	stripe.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.add_child(stripe)


func _flat(pos: Vector3, size: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	bm.material = mat
	mi.mesh = bm
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


## Ворота из обломков корабля: штанги, перекладина, сетка
func _goal(mouth_x: float, sgn: float, col: Color) -> void:
	var cz := CENTER.y
	var metal := StandardMaterial3D.new()
	metal.albedo_color = col.darkened(0.25)
	metal.metallic = 0.6
	metal.roughness = 0.45
	metal.emission_enabled = true
	metal.emission = col
	metal.emission_energy_multiplier = 0.35
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.16, 0.16, 0.18)
	dark.metallic = 0.7
	dark.roughness = 0.6
	var net := StandardMaterial3D.new()
	net.albedo_color = Color(0.9, 0.95, 1.0, 0.28)
	net.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	net.cull_mode = BaseMaterial3D.CULL_DISABLED
	var back_x := mouth_x + sgn * GOAL_DEPTH
	for zs in [-1.0, 1.0]:
		_bar(Vector3(mouth_x, _y, cz + zs * GOAL_HALF_W), Vector3(mouth_x, _y + GOAL_H, cz + zs * GOAL_HALF_W), 0.12, metal)
		_bar(Vector3(back_x, _y, cz + zs * GOAL_HALF_W), Vector3(back_x, _y + GOAL_H * 0.75, cz + zs * GOAL_HALF_W), 0.07, dark)
		_bar(Vector3(mouth_x, _y + GOAL_H, cz + zs * GOAL_HALF_W), Vector3(back_x, _y + GOAL_H * 0.75, cz + zs * GOAL_HALF_W), 0.06, dark)
	_bar(Vector3(mouth_x, _y + GOAL_H, cz - GOAL_HALF_W), Vector3(mouth_x, _y + GOAL_H, cz + GOAL_HALF_W), 0.12, metal)
	var body := StaticBody3D.new()
	var pm := PhysicsMaterial.new()
	pm.bounce = 0.05
	pm.friction = 0.8
	body.physics_material_override = pm
	add_child(body)
	var mid_x := (mouth_x + back_x) * 0.5
	_panel(body, Vector3(back_x + sgn * 0.05, _y + GOAL_H * 0.4, cz), Vector3(0.1, GOAL_H * 0.8, GOAL_HALF_W * 2.0), net)
	for zs in [-1.0, 1.0]:
		_panel(body, Vector3(mid_x, _y + GOAL_H * 0.45, cz + zs * (GOAL_HALF_W + 0.05)), Vector3(GOAL_DEPTH, GOAL_H * 0.9, 0.1), net)
	_panel(body, Vector3(mid_x, _y + GOAL_H * 0.9, cz), Vector3(GOAL_DEPTH, 0.1, GOAL_HALF_W * 2.0), net)
	var lamp := OmniLight3D.new()
	lamp.light_color = col
	lamp.light_energy = 1.4
	lamp.omni_range = 6.0
	lamp.position = Vector3(mouth_x - sgn * 0.5, _y + GOAL_H + 0.4, cz)
	add_child(lamp)


func _bar(a: Vector3, b: Vector3, r: float, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = a.distance_to(b)
	cm.radial_segments = 10
	cm.material = mat
	mi.mesh = cm
	add_child(mi)
	mi.transform = Transform3D(_basis_along(b - a), (a + b) * 0.5)


## Поворот, при котором ось Y смотрит вдоль dir
func _basis_along(dir: Vector3) -> Basis:
	dir = dir.normalized()
	if absf(dir.dot(Vector3.UP)) > 0.999:
		return Basis.IDENTITY
	var x := Vector3.UP.cross(dir).normalized()
	return Basis(x, dir, x.cross(dir).normalized())


func _panel(body: StaticBody3D, center: Vector3, size: Vector3, mat: Material) -> void:
	var col := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	col.shape = sh
	col.position = center
	body.add_child(col)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	bm.material = mat
	mi.mesh = bm
	mi.position = center
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.add_child(mi)


func _sign(text: String, pos: Vector3, col: Color, size: int) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.outline_size = 12
	l.modulate = col
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.position = pos
	add_child(l)
	return l


# ---------------------------------------------------------------------------
#  Стойка с клюшками и сами клюшки
# ---------------------------------------------------------------------------
func _rack() -> void:
	_rack_pos = Vector3(CENTER.x - 4.0, _y, CENTER.y + HALF.y + 2.2)
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.35, 0.22, 0.12)
	wood.roughness = 0.8
	var body := StaticBody3D.new()
	body.position = _rack_pos
	add_child(body)
	var col := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(3.0, 1.2, 0.4)
	col.shape = sh
	col.position = Vector3(0, 0.6, 0.3)
	body.add_child(col)
	for x in [-1.4, 1.4]:
		var post := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.15, 1.3, 0.15)
		bm.material = wood
		post.mesh = bm
		post.position = Vector3(x, 0.65, 0.35)
		body.add_child(post)
	var beam := MeshInstance3D.new()
	var bb := BoxMesh.new()
	bb.size = Vector3(3.0, 0.15, 0.15)
	bb.material = wood
	beam.mesh = bb
	beam.position = Vector3(0, 1.2, 0.35)
	body.add_child(beam)
	for i in MAX_STICKS:
		var s := _stick_mesh()
		s.position = Vector3(-1.05 + i * 0.7, 0.0, 0.0)
		s.rotation = Vector3(0.3, 0.0, 0.0)
		body.add_child(s)
		_rack_sticks.append(s)
	_rack_label = _sign("КЛЮШКИ — нажми E", _rack_pos + Vector3(0, 2.2, 0.3), Color(1.0, 0.9, 0.6), 48)


## Клюшка: древко + крюк. Начало координат — у крюка на льду, древко вверх (+Y), крюк вперёд (-Z)
func _stick_mesh(tilt: float = 0.0) -> Node3D:
	var root := Node3D.new()
	var shaft := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.035
	cm.bottom_radius = 0.035
	cm.height = 1.45
	cm.material = _shaft_mat
	shaft.mesh = cm
	shaft.position = Vector3(0, 0.75, 0.12)
	shaft.rotation.x = 0.18
	root.add_child(shaft)
	var blade := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.07, 0.12, 0.5)
	bm.material = _tape_mat
	blade.mesh = bm
	blade.position = Vector3(0, 0.06, -0.12)
	blade.rotation.x = -tilt   # крюк лежит на льду, даже если клюшка наклонена
	root.add_child(blade)
	var grip := MeshInstance3D.new()
	var gm := CylinderMesh.new()
	gm.top_radius = 0.045
	gm.bottom_radius = 0.045
	gm.height = 0.25
	gm.material = _tape_mat
	grip.mesh = gm
	grip.position = Vector3(0, 1.38, 0.24)
	grip.rotation.x = 0.18
	root.add_child(grip)
	return root


func _player_node(peer: int) -> Node3D:
	for d in get_tree().get_nodes_in_group("player"):
		if int(d.get("peer_id")) == peer:
			return d
	return null


## Где крюк клюшки у дрона (на льду, справа-впереди)
func blade_pos(d: Node3D) -> Vector3:
	var vis: Node3D = d.get("visual")
	var b: Basis = vis.global_basis if vis else d.global_basis
	var fwd := -b.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var right := Vector3(-fwd.z, 0.0, fwd.x)
	return Vector3(d.global_position.x, _y + 0.07, d.global_position.z) + fwd * 1.08 + right * 0.16


func _refresh_sticks() -> void:
	# клюшки на дронах
	for peer in _stick_nodes.keys():
		if not holders.has(peer) or not is_instance_valid(_stick_nodes[peer]):
			if is_instance_valid(_stick_nodes[peer]):
				(_stick_nodes[peer] as Node).queue_free()
			_stick_nodes.erase(peer)
	for peer in holders:
		if _stick_nodes.has(peer):
			continue
		var d := _player_node(peer)
		if d == null:
			continue
		var vis: Node3D = d.get("visual")
		var s := _stick_mesh(0.55)
		s.name = "HockeyStick"
		(vis if vis else d).add_child(s)
		s.position = Vector3(0.16, 0.02, -1.0)     # клюшку держат обе руки (exo_suit.gd)
		s.rotation = Vector3(0.62, 0.0, 0.0)
		_stick_nodes[peer] = s
	# сколько клюшек осталось на стойке
	for i in _rack_sticks.size():
		_rack_sticks[i].visible = i < MAX_STICKS - holders.size()


# ---------------------------------------------------------------------------
#  Шайба
# ---------------------------------------------------------------------------
func _make_puck() -> void:
	_puck = RigidBody3D.new()
	_puck.name = "Puck"
	_puck.collision_layer = 16
	_puck.collision_mask = 1
	_puck.mass = 0.4
	_puck.linear_damp = 0.25
	_puck.angular_damp = 1.0
	_puck.continuous_cd = true
	_puck.can_sleep = false
	_puck.axis_lock_angular_x = true
	_puck.axis_lock_angular_z = true
	var pm := PhysicsMaterial.new()
	pm.friction = 0.02
	pm.bounce = 0.5
	_puck.physics_material_override = pm
	var col := CollisionShape3D.new()
	var cs := CylinderShape3D.new()
	cs.radius = PUCK_R
	cs.height = 0.14
	col.shape = cs
	_puck.add_child(col)
	_puck_mesh = MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = PUCK_R
	cm.bottom_radius = PUCK_R
	cm.height = 0.14
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.06, 0.06, 0.07)
	mat.roughness = 0.35
	mat.rim_enabled = true
	mat.rim = 0.6
	cm.material = mat
	_puck_mesh.mesh = cm
	_puck.add_child(_puck_mesh)
	# светящийся ободок — шайбу видно издалека
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = PUCK_R - 0.02
	tm.outer_radius = PUCK_R + 0.03
	var glow := StandardMaterial3D.new()
	glow.albedo_color = Color(1.0, 0.6, 0.2)
	glow.emission_enabled = true
	glow.emission = Color(1.0, 0.55, 0.15)
	glow.emission_energy_multiplier = 2.5
	tm.material = glow
	ring.mesh = tm
	ring.scale = Vector3(1, 0.4, 1)
	_puck.add_child(ring)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.55, 0.2)
	light.light_energy = 0.6
	light.omni_range = 2.0
	light.position.y = 0.3
	_puck.add_child(light)
	_puck.position = _home()
	add_child(_puck)
	if not multiplayer.is_server():
		_puck.freeze = true
		_puck.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	_net_pos = _puck.position


func _home() -> Vector3:
	return Vector3(CENTER.x, _y + 0.12, CENTER.y)


func puck() -> RigidBody3D:
	return _puck


func _physics_process(delta: float) -> void:
	if multiplayer.is_server():
		_host_step(delta)
	else:
		_client_step(delta)
	_local_input(delta)


func _client_step(delta: float) -> void:
	_net_age += delta
	if possessor >= 0:
		var d := _player_node(possessor)
		if d:
			_puck.global_position = _puck.global_position.lerp(blade_pos(d), clampf(delta * 20.0, 0.0, 1.0))
			return
	var target := _net_pos + _net_vel * minf(_net_age, 0.2)
	_puck.global_position = _puck.global_position.lerp(target, clampf(delta * 14.0, 0.0, 1.0))


func _host_step(delta: float) -> void:
	for k in _cool.keys():
		_cool[k] = float(_cool[k]) - delta
	# клюшку уносят далеко от поля — она возвращается на стойку
	for peer in holders.keys():
		var d := _player_node(peer)
		if d == null or Vector2(d.global_position.x - CENTER.x, d.global_position.z - CENTER.y).length() > STICK_RANGE:
			_set_stick(peer, false)
	if possessor >= 0:
		var d := _player_node(possessor)
		if d == null or not holders.has(possessor) or bool(d.get("is_dead")):
			_release(Vector3.ZERO)
		else:
			_puck.freeze = true
			_puck.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
			_puck.global_position = blade_pos(d)
			# отбор: чужой крюк рядом с шайбой
			_steal_t -= delta
			if _steal_t <= 0.0:
				_steal_t = 0.15
				for peer in holders:
					if peer == possessor or float(_cool.get(peer, 0.0)) > 0.0:
						continue
					var o := _player_node(peer)
					if o and blade_pos(o).distance_to(_puck.global_position) < STEAL_DIST and randf() < 0.5:
						_cool[possessor] = 0.8
						possessor = peer
						_sync_state()
						break
	else:
		# подхватить свободную шайбу крюком
		for peer in holders:
			if float(_cool.get(peer, 0.0)) > 0.0:
				continue
			var d := _player_node(peer)
			if d == null or bool(d.get("is_dead")):
				continue
			var bp := blade_pos(d)
			var dp := _puck.global_position - bp
			if Vector2(dp.x, dp.z).length() < GRAB_DIST and absf(dp.y) < 0.7 and _puck.linear_velocity.length() < 24.0:
				possessor = peer
				_sync_state()
				break
		if possessor < 0:
			_body_bumps(delta)
	# голы и вылет
	if _reset_timer < 0.0:
		for i in _goals.size():
			if _goals[i].has_point(_puck.global_position):
				_reset_timer = 2.0
				_on_goal(i)
				break
		var gp := _puck.global_position
		if _reset_timer < 0.0 and (gp.y < _y - 3.0 or absf(gp.x - CENTER.x) > HALF.x + 8.0 or absf(gp.z - CENTER.y) > HALF.y + 8.0):
			_reset_timer = 1.0
	else:
		_reset_timer -= delta
		if _reset_timer <= 0.0:
			_reset_timer = -1.0
			if possessor >= 0:
				_release(Vector3.ZERO)
			_puck.linear_velocity = Vector3.ZERO
			_puck.angular_velocity = Vector3.ZERO
			_puck.global_position = _home()
	_send -= delta
	if _send <= 0.0:
		_send = SEND_INTERVAL
		_puck_sync.rpc(_puck.global_position, _puck.linear_velocity, possessor)


## Без клюшки шайбу можно толкнуть корпусом
func _body_bumps(delta: float) -> void:
	for d in get_tree().get_nodes_in_group("player"):
		var n := d as Node3D
		var p := n.global_position
		var prev: Vector3 = _prev.get(n, p)
		_prev[n] = p
		var v := (p - prev) / maxf(delta, 0.001)
		var to := _puck.global_position - p
		if Vector2(to.x, to.z).length() > PUCK_R + 0.55 or absf(to.y) > 1.0:
			continue
		var dir := Vector3(to.x, 0.0, to.z).normalized()
		var approach := maxf(Vector3(v.x, 0.0, v.z).dot(dir), 0.0)
		var hv := dir * maxf(approach * 1.3, 2.0)
		_puck.linear_velocity = Vector3(hv.x, _puck.linear_velocity.y, hv.z)


func _release(vel: Vector3) -> void:
	if possessor >= 0:
		_cool[possessor] = 0.45
	possessor = -1
	_puck.freeze = false
	_puck.linear_velocity = vel
	_sync_state()


func _on_goal(goal_index: int) -> void:
	if possessor >= 0:
		_release(Vector3.ZERO)
	var team := 1 if goal_index == 0 else 0   # шайба в синих воротах — очко оранжевым
	score[team] += 1
	_goal_rpc.rpc(team, score[0], score[1])


@rpc("authority", "call_local", "reliable")
func _goal_rpc(team: int, blue: int, orange: int) -> void:
	score = [blue, orange]
	_update_labels()
	var who := "Синие" if team == 0 else "Оранжевые"
	var me = Network.local_player
	if me and me.global_position.distance_to(Vector3(CENTER.x, _y, CENTER.y)) < 80.0:
		get_tree().call_group("level", "show_banner", "ГОЛ!", "%s забили!   Синие %d : %d Оранжевые" % [who, blue, orange])
		me.add_shake(0.15)


func _update_labels() -> void:
	if _labels.size() < 2:
		return
	_labels[0].text = "СИНИЕ  %d" % score[0]
	_labels[1].text = "ОРАНЖЕВЫЕ  %d" % score[1]


@rpc("authority", "call_remote", "unreliable_ordered")
func _puck_sync(pos: Vector3, vel: Vector3, owner_peer: int) -> void:
	if pos.distance_to(_puck.global_position) > 6.0:
		_puck.global_position = pos
	_net_pos = pos
	_net_vel = vel
	_net_age = 0.0
	possessor = owner_peer


# ---------------------------------------------------------------------------
#  Клюшки: взять / вернуть (решает хост)
# ---------------------------------------------------------------------------
func _set_stick(peer: int, take: bool) -> void:
	if take:
		if holders.size() >= MAX_STICKS:
			return
		holders[peer] = true
	else:
		holders.erase(peer)
		if possessor == peer:
			_release(Vector3.ZERO)
	_sync_state()


func _sync_state() -> void:
	if multiplayer.is_server():
		_state_rpc.rpc(holders.keys(), possessor)


@rpc("authority", "call_local", "reliable")
func _state_rpc(peers: Array, owner_peer: int) -> void:
	holders.clear()
	for p in peers:
		holders[int(p)] = true
	possessor = owner_peer
	_refresh_sticks()


@rpc("any_peer", "call_local", "reliable")
func _req_stick(take: bool) -> void:
	if not multiplayer.is_server():
		return
	var peer := multiplayer.get_remote_sender_id()
	if peer == 0:
		peer = multiplayer.get_unique_id()
	var d := _player_node(peer)
	if d == null:
		return
	if take and d.global_position.distance_to(_rack_pos) > RACK_RADIUS + 1.0:
		return
	_set_stick(peer, take)


@rpc("any_peer", "call_local", "reliable")
func _req_shot(power: float, dir: Vector3) -> void:
	if not multiplayer.is_server():
		return
	var peer := multiplayer.get_remote_sender_id()
	if peer == 0:
		peer = multiplayer.get_unique_id()
	_swing_fx.rpc(peer, power)
	if possessor != peer:
		return
	power = clampf(power, 0.0, 1.0)
	dir.y = 0.0
	dir = dir.normalized()
	var speed := lerpf(SHOT_MIN, SHOT_MAX, power)
	var lift := maxf(power - 0.6, 0.0) * 9.0
	_release(dir * speed + Vector3.UP * lift)


## Взмах клюшкой (видно всем)
@rpc("authority", "call_local", "reliable")
func _swing_fx(peer: int, power: float) -> void:
	var s: Node3D = _stick_nodes.get(peer)
	if s == null or not is_instance_valid(s):
		return
	var tw := create_tween()
	tw.tween_property(s, "rotation:y", 0.9 + power * 0.5, 0.1)
	tw.tween_property(s, "rotation:y", -0.5, 0.08)
	tw.tween_property(s, "rotation:y", 0.0, 0.25)


func _on_player_left(peer: int) -> void:
	if multiplayer.is_server() and holders.has(peer):
		_set_stick(peer, false)


# ---------------------------------------------------------------------------
#  Управление своим дроном: E у стойки, бросок с зарядом
# ---------------------------------------------------------------------------
func _local_input(delta: float) -> void:
	var me: Node3D = Network.local_player
	if me == null:
		return
	var my_id := multiplayer.get_unique_id()
	var have := holders.has(my_id)
	var near_rack := me.global_position.distance_to(_rack_pos) < RACK_RADIUS
	var near_field := Vector2(me.global_position.x - CENTER.x, me.global_position.z - CENTER.y).length() < STICK_RANGE
	if near_rack and Input.is_action_just_pressed("interact") and not bool(me.get("is_dead")):
		_req_stick.rpc_id(1, not have)
	_rack_label.text = ("Вернуть клюшку — E" if have else "КЛЮШКИ — нажми E") if near_rack else "КЛЮШКИ"
	if have and not bool(me.get("is_dead")):
		if Input.is_action_just_pressed("shoot"):
			_charging = true
			_charge = 0.0
		if _charging:
			_charge = minf(_charge + delta / CHARGE_TIME, 1.0)
			if not Input.is_action_pressed("shoot"):
				_charging = false
				var cam: Node3D = me.get("camera_pivot")
				var fwd := -(cam.global_basis.z if cam else me.global_basis.z)
				_req_shot.rpc_id(1, _charge, fwd)
	else:
		_charging = false
	_hud.visible = have or (near_field and near_rack)
	_charge_bar.visible = _charging
	_charge_bar.value = _charge * 100.0
	if have:
		_hint.text = "ЛКМ — бросок (держи — сильнее)    Подъедь к шайбе — подхватишь    E у стойки — вернуть клюшку"
	else:
		_hint.text = "E — взять клюшку"


func _make_hud() -> void:
	_hud = CanvasLayer.new()
	_hud.layer = 5
	_hud.visible = false
	add_child(_hud)
	var box := VBoxContainer.new()
	box.anchor_left = 0.5
	box.anchor_right = 0.5
	box.anchor_top = 1.0
	box.anchor_bottom = 1.0
	box.offset_left = -330.0
	box.offset_right = 330.0
	box.offset_top = -150.0
	box.offset_bottom = -95.0
	_hud.add_child(box)
	_hint = Label.new()
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_hint.add_theme_constant_override("outline_size", 6)
	box.add_child(_hint)
	_charge_bar = ProgressBar.new()
	_charge_bar.custom_minimum_size = Vector2(0, 16)
	_charge_bar.show_percentage = false
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(1.0, 0.55, 0.15)
	_charge_bar.add_theme_stylebox_override("fill", fill)
	box.add_child(_charge_bar)
