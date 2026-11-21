extends CharacterBody3D
## Снежный робот-воришка Лавинной долины (шаг 56).
## Сидит в сугробе-гнезде (из снега светятся глаза). Подойдёшь — вылезает, ковыляет к тебе,
## цепляется и откручивает руку или ногу — и удирает с ней (бегает быстрее шага, но медленнее бега).
## Через ~25 с зарывается в снег — деталь остаётся лежать на том месте.
##
## Как отбиться:
##   * E — схватить робота (держишь перед собой, он брыкается), Q — швырнуть: о землю разбивается;
##   * ЛКМ — махнуть оторванной рукой/ногой как дубинкой: два удара — и робот рассыпается;
##   * R — стряхнуть вцепившегося робота с себя.
## Разбитый робот роняет украденную деталь. Через время в гнезде вырастает новый.
## Решает всё хост; остальным рассылает положение и события.

enum S { NEST, EMERGE, CHASE, GRAB, FLEE, HELD, FLY, DEAD, BURROW }

const WALK := 6.3                 ## чуть быстрее шага дрона (6): от них не уйти шагом
const DASH := 7.6                 ## рывок, когда цель близко
const FLEE_SPEED := 7.2           ## с деталью удирает быстрее шага (6), но медленнее бега (11.5)
const WAKE_DIST := 60.0
const GRAB_TIME := 0.45
const FLEE_TIME := 25.0
const RESPAWN := 50.0
const HOLD_BREAK := 4.5
const MAX_HP := 2

static var max_awake := 5          ## сколько роботов одновременно не в гнезде (по числу игроков — avalanche.gd)
var dormant := false               ## гнездо пустует (игроков мало — роботов меньше)
var home := Vector3.ZERO           ## гнездо
var index := 0
var state := S.NEST
var hp := MAX_HP
var target_id := 0
var holder_id := 0
var held_limb: Node3D = null       ## украденная деталь (limb_part.gd держится за меня)
var suit: Node3D                   ## для limb_part.gd: «костюм» — это я сам (limb_carry_xform)
var act_target: Node3D = null      ## для limb_part.gd
var act_mode := 0

var _t := 0.0
var _st_t := 0.0
var _anim := 0.0
var _pending_id := 0
var _net_pos := Vector3.ZERO
var _net_yaw := 0.0
var _send := 0.0
var _rip_kind := ""
var _wait_part := 0.0
var _flee_dir := Vector3.ZERO
var _fly_by := 0
var _thrown := false              ## швырнул игрок — о землю разобьётся
var _ter: Node

var _vis: Node3D
var _torso: Node3D
var _head: Node3D
var _arms: Array[Node3D] = []
var _legs: Array[Node3D] = []
var _eye_mat: StandardMaterial3D
var _core_mat: StandardMaterial3D
var _nest: Node3D
var _nest_eyes: Node3D
var _trail: GPUParticles3D
var _burst: GPUParticles3D
var _ice_burst: GPUParticles3D
var _light: OmniLight3D


func _ready() -> void:
	add_to_group("snow_robot")
	suit = self
	collision_layer = 0
	collision_mask = 1
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.38
	cap.height = 1.2
	cs.shape = cap
	cs.position.y = 0.62
	add_child(cs)
	floor_snap_length = 0.5
	_ter = get_tree().get_first_node_in_group("terrain")
	_build()
	_net_pos = global_position
	_apply_state_visual()


# ---------------------------------------------------------------------------
#  Вид
# ---------------------------------------------------------------------------

func _mat(c: Color, rough := 0.85, emit := Color.BLACK, e := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	if e > 0.0:
		m.emission_enabled = true
		m.emission = emit
		m.emission_energy_multiplier = e
	return m


func _sph(parent: Node3D, r: float, pos: Vector3, m: Material, sc := Vector3.ONE) -> MeshInstance3D:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = 12
	s.rings = 6
	var mi := MeshInstance3D.new()
	mi.mesh = s
	mi.material_override = m
	mi.position = pos
	mi.scale = sc
	parent.add_child(mi)
	return mi


func _cyl(parent: Node3D, rt: float, rb: float, h: float, pos: Vector3, m: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	var c := CylinderMesh.new()
	c.top_radius = rt
	c.bottom_radius = rb
	c.height = h
	c.radial_segments = 8
	c.rings = 1
	var mi := MeshInstance3D.new()
	mi.mesh = c
	mi.material_override = m
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	return mi


func _build() -> void:
	# тёмный металлический каркас, облепленный слежавшимся снегом и льдом — хорошо видно на белом
	var snow := _mat(Color(0.86, 0.91, 0.98), 0.95)
	var metal := _mat(Color(0.2, 0.23, 0.28), 0.4)
	metal.metallic = 0.75
	var ice := _mat(Color(0.45, 0.75, 0.98), 0.12, Color(0.15, 0.45, 0.85), 0.6)
	var rust := _mat(Color(0.5, 0.27, 0.14), 0.7)
	rust.metallic = 0.6
	_eye_mat = _mat(Color(0.4, 0.95, 1.0), 0.3, Color(0.3, 0.9, 1.0), 6.0)
	_core_mat = _mat(Color(0.3, 0.7, 1.0), 0.2, Color(0.2, 0.6, 1.0), 3.0)
	_vis = Node3D.new()
	add_child(_vis)
	_torso = Node3D.new()
	_torso.position = Vector3(0, 0.62, 0)
	_vis.add_child(_torso)
	# корпус: металлическая бочка, сверху и со спины — снежный панцирь
	_sph(_torso, 0.38, Vector3.ZERO, metal, Vector3(1.0, 1.05, 0.9))
	_sph(_torso, 0.36, Vector3(0, 0.14, 0.08), snow, Vector3(1.12, 0.78, 1.0))
	_sph(_torso, 0.26, Vector3(0, -0.3, 0.02), metal, Vector3(1.1, 0.6, 1.0))
	_cyl(_torso, 0.4, 0.4, 0.06, Vector3(0, -0.08, 0), rust)
	for k in 5:
		var a := -0.9 + k * 0.45
		var plate := _cyl(_torso, 0.0, 0.1, 0.26, Vector3(sin(a) * 0.36, 0.3 + 0.05 * (k % 2), cos(a) * 0.12 + 0.12), ice, Vector3(-0.5, 0, a))
		plate.scale = Vector3(1.0, 1.0, 0.55)
	# светящийся кристалл-сердце в оправе
	var core := _sph(_torso, 0.1, Vector3(0, 0.0, -0.35), _core_mat)
	core.scale = Vector3(1.0, 1.3, 0.7)
	_cyl(_torso, 0.14, 0.14, 0.05, Vector3(0, 0.0, -0.32), rust, Vector3(PI * 0.5, 0, 0))
	# голова: металл, снежная шапка, козырёк, глаза-лампы, антенна с сосулькой
	_head = Node3D.new()
	_head.position = Vector3(0, 0.5, 0)
	_torso.add_child(_head)
	_sph(_head, 0.24, Vector3.ZERO, metal)
	_sph(_head, 0.21, Vector3(0, 0.13, 0.03), snow, Vector3(1.2, 0.62, 1.15))
	var visor := _cyl(_head, 0.17, 0.2, 0.08, Vector3(0, 0.0, -0.17), _mat(Color(0.05, 0.06, 0.08), 0.2), Vector3(PI * 0.5, 0, 0))
	visor.scale = Vector3(1.0, 1.0, 0.55)
	for s in [-1.0, 1.0]:
		_sph(_head, 0.055, Vector3(s * 0.08, 0.01, -0.235), _eye_mat)
	_cyl(_head, 0.012, 0.012, 0.32, Vector3(0.1, 0.34, 0), rust)
	_cyl(_head, 0.0, 0.035, 0.2, Vector3(0.1, 0.42, 0), ice, Vector3(PI, 0, 0))
	_sph(_head, 0.035, Vector3(0.1, 0.52, 0), _core_mat)
	# руки: металл, ледяные когти, на плечах снег
	for s in [-1.0, 1.0]:
		var arm := Node3D.new()
		arm.position = Vector3(s * 0.4, 0.15, 0)
		_torso.add_child(arm)
		_sph(arm, 0.1, Vector3(0, 0.03, 0), snow)
		_cyl(arm, 0.045, 0.055, 0.48, Vector3(0, -0.24, 0), metal)
		_sph(arm, 0.075, Vector3(0, -0.48, 0), metal)
		for c in 3:
			var ca := (c - 1) * 0.5
			_cyl(arm, 0.0, 0.03, 0.2, Vector3(sin(ca) * 0.05, -0.6, cos(ca) * 0.05 - 0.03), ice, Vector3(PI + 0.3, ca, 0))
		_arms.append(arm)
	# ноги: металлические стойки, снежные «валенки»
	for s in [-1.0, 1.0]:
		var leg := Node3D.new()
		leg.position = Vector3(s * 0.18, 0.32, 0)
		_vis.add_child(leg)
		_cyl(leg, 0.06, 0.07, 0.3, Vector3(0, -0.13, 0), metal)
		_sph(leg, 0.13, Vector3(0, -0.29, -0.04), snow, Vector3(1.0, 0.6, 1.35))
		_legs.append(leg)
	_light = OmniLight3D.new()
	_light.light_color = Color(0.4, 0.85, 1.0)
	_light.light_energy = 0.6
	_light.omni_range = 3.0
	_light.position = Vector3(0, 1.1, -0.3)
	_vis.add_child(_light)
	# гнездо: сугроб, из которого светятся глаза
	_nest = Node3D.new()
	_nest.top_level = true
	add_child(_nest)
	_sph(_nest, 1.0, Vector3(0, 0.1, 0), snow, Vector3(1.3, 0.75, 1.2))
	_sph(_nest, 0.6, Vector3(0.7, 0.0, 0.4), snow, Vector3(1.0, 0.6, 1.0))
	# тёмная нора в сугробе, из неё светятся глаза; торчит антенна
	var hole := _sph(_nest, 0.42, Vector3(0, 0.38, -0.86), _mat(Color(0.06, 0.08, 0.12), 0.9), Vector3(1.2, 0.75, 0.5))
	hole.rotation.x = -0.35
	_nest_eyes = Node3D.new()
	_nest_eyes.position = Vector3(0, 0.42, -1.04)
	_nest.add_child(_nest_eyes)
	for s in [-1.0, 1.0]:
		_sph(_nest_eyes, 0.085, Vector3(s * 0.14, 0, 0), _eye_mat)
	var ant_m := _mat(Color(0.2, 0.23, 0.28), 0.4)
	_cyl(_nest, 0.015, 0.015, 0.6, Vector3(0.35, 0.95, 0.1), ant_m, Vector3(0, 0, -0.3))
	_sph(_nest, 0.05, Vector3(0.44, 1.25, 0.1), _core_mat)
	var eye_l := OmniLight3D.new()
	eye_l.light_color = Color(0.4, 0.9, 1.0)
	eye_l.light_energy = 1.2
	eye_l.omni_range = 2.5
	eye_l.position = Vector3(0, 0.45, -1.3)
	_nest.add_child(eye_l)
	_trail = FX.particles(Color(0.95, 0.97, 1.0, 0.7), 16, 0.6, 0.08, 0.3, 1.0, Vector3(0, -2, 0), 60.0, false)
	add_child(_trail)
	_burst = FX.particles(Color(0.95, 0.97, 1.0, 0.95), 60, 1.1, 0.16, 2.5, 7.0, Vector3(0, -9, 0), 180.0, true)
	_burst.position.y = 0.7
	add_child(_burst)
	_ice_burst = FX.particles(Color(0.5, 0.85, 1.0, 1.0), 30, 0.8, 0.05, 3.0, 8.0, Vector3(0, -9, 0), 180.0, true, true)
	_ice_burst.position.y = 0.8
	add_child(_ice_burst)


# ---------------------------------------------------------------------------
#  Для других скриптов
# ---------------------------------------------------------------------------

func alive() -> bool:
	return state in [S.EMERGE, S.CHASE, S.GRAB, S.FLEE, S.HELD, S.FLY]


func can_grab() -> bool:
	return state in [S.CHASE, S.GRAB, S.FLEE, S.EMERGE] and holder_id == 0


## Цепляется ли за этого дрона
func latched_on(pl: Node) -> bool:
	return state == S.GRAB and pl != null and int(pl.peer_id) == target_id


## Куда держать украденную деталь (limb_part.gd спрашивает suit.limb_carry_xform)
func limb_carry_xform() -> Variant:
	var b := _vis.global_basis
	return Transform3D(b * Basis(Vector3.RIGHT, -1.2) * Basis(Vector3.FORWARD, 0.4), _torso.global_position + b * Vector3(0.25, 0.35, 0.3))


func has_limb(_k: String) -> bool:
	return true


func hand_xform(_i: int) -> Transform3D:
	return _arms[0].global_transform


func _online() -> bool:
	return Network.in_game and Network.is_online()


func _bcast(method: String, args: Array) -> void:
	if _online():
		callv("rpc", [method] + args)
	else:
		callv(method, args)


func _to_host(method: String, args: Array) -> void:
	if multiplayer.is_server():
		callv(method, args)
	elif _online():
		callv("rpc_id", [1, method] + args)


## Игрок взял меня в руки (зовёт snow_state.gd у того, кто взял)
func request_grab(peer: int) -> void:
	_pending_id = peer
	_to_host("_srv_grab", [peer])


func request_release(peer: int, at: Vector3, vel: Vector3) -> void:
	_pending_id = 0
	_to_host("_srv_release", [peer, at, vel])


## Удар (деталью-дубинкой, лавиной, стряхнули)
func request_hit(vel: Vector3, by: int, dmg := 1) -> void:
	_to_host("_srv_hit", [vel, by, dmg])


@rpc("any_peer", "call_remote", "reliable")
func _srv_grab(peer: int) -> void:
	if not multiplayer.is_server() or not can_grab():
		return
	_drop_target_grab()
	_bcast("_set_state", [S.HELD, peer, 0])


@rpc("any_peer", "call_remote", "reliable")
func _srv_release(peer: int, at: Vector3, vel: Vector3) -> void:
	if not multiplayer.is_server() or state != S.HELD or holder_id != peer:
		return
	global_position = at
	velocity = vel
	_fly_by = peer
	_thrown = vel.length() > 4.0
	_bcast("_set_state", [S.FLY, 0, 0])


@rpc("any_peer", "call_remote", "reliable")
func _srv_hit(vel: Vector3, by: int, dmg: int) -> void:
	if not multiplayer.is_server() or not alive():
		return
	if state == S.HELD:
		return
	hp -= dmg
	velocity = vel
	_fly_by = by
	_thrown = false
	_bcast("_fx_hit", [global_position])
	if hp <= 0:
		_shatter()
	else:
		_bcast("_set_state", [S.FLY, 0, 0])


# ---------------------------------------------------------------------------
#  Каждый кадр
# ---------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	_t += delta
	_st_t += delta
	if multiplayer.is_server():
		_server(delta)
		_send -= delta
		if _send <= 0.0 and _online():
			_send = 0.08
			_net.rpc(global_position, _vis.rotation.y)
	else:
		if state == S.HELD:
			_follow_holder()
		else:
			global_position = global_position.lerp(_net_pos, clampf(delta * 12.0, 0.0, 1.0)) \
				if global_position.distance_to(_net_pos) < 6.0 else _net_pos
			_vis.rotation.y = lerp_angle(_vis.rotation.y, _net_yaw, clampf(delta * 10.0, 0.0, 1.0))
	_animate(delta)


@rpc("authority", "call_remote", "unreliable_ordered")
func _net(pos: Vector3, yaw: float) -> void:
	_net_pos = pos
	_net_yaw = yaw


func _players() -> Array:
	var out := []
	for d in get_tree().get_nodes_in_group("player"):
		if d.is_dead or (d.get("snow") != null and d.snow.busy()):
			continue
		out.append(d)
	return out


func _nearest(want_limbs: bool, max_d: float) -> Node3D:
	var best: Node3D = null
	var bd := max_d
	for d in _players():
		if want_limbs and int(d.limb_mask) == 0:
			continue
		var dist: float = (d as Node3D).global_position.distance_to(global_position)
		if dist < bd:
			bd = dist
			best = d
	return best


func _ground(x: float, z: float) -> float:
	return _ter.height_at(x, z) if _ter else global_position.y


func _server(delta: float) -> void:
	match state:
		S.NEST:
			global_position = home
			if not dormant and _st_t > 1.0 and _nearest(true, WAKE_DIST) != null and _active_count() < max_awake:
				_bcast("_set_state", [S.EMERGE, 0, 0])
		S.EMERGE:
			global_position = home + Vector3.UP * (-1.2 + 1.2 * smoothstep(0.0, 1.0, _st_t / 1.0))
			if _st_t > 1.0:
				_bcast("_set_state", [S.CHASE, 0, 0])
		S.CHASE:
			var tg := _nearest(true, 85.0)
			if tg == null:
				_walk_to(home, WALK, delta)
				if global_position.distance_to(home) < 1.5 and _st_t > 3.0:
					_bcast("_set_state", [S.NEST, 0, 0])
				return
			var to: Vector3 = tg.global_position - global_position
			to.y = 0.0
			var sp := DASH if to.length() < 7.0 else WALK
			_walk_to(tg.global_position, sp, delta)
			if to.length() < 1.15 and absf(tg.global_position.y - global_position.y) < 1.6:
				_bcast("_set_state", [S.GRAB, int(tg.peer_id), 0])
		S.GRAB:
			var vic = Network.find_player(target_id)
			if vic == null or vic.is_dead or int(vic.limb_mask) == 0 or (vic.get("snow") != null and vic.snow.busy()):
				_bcast("_set_state", [S.CHASE, 0, 0])
				return
			# вцепился в спину: еду на нём, откручиваю
			var vb: Basis = Basis(Vector3.UP, vic.visual.global_rotation.y)
			global_position = (vic as Node3D).global_position + vb * Vector3(0, 0.25, 0.55)
			_vis.rotation.y = vic.visual.global_rotation.y
			velocity = Vector3.ZERO
			if _rip_kind == "" and _st_t > GRAB_TIME:
				var have: Array[String] = []
				for k in ["arm_l", "arm_r", "leg_l", "leg_r"]:
					if vic.has_limb(k):
						have.append(k)
				if have.is_empty():
					_bcast("_set_state", [S.CHASE, 0, 0])
					return
				# руки — чаще (без рук не отобьёшься)
				_rip_kind = have.pick_random()
				for k in have:
					if k.begins_with("arm") and randf() < 0.6:
						_rip_kind = k
				vic.request_rip(_rip_kind, 0)
				_wait_part = 1.5
			if _rip_kind != "":
				_wait_part -= delta
				var part := _find_part(target_id, _rip_kind)
				if part != null:
					_bcast("_claim", [String(part.part_id)])
					var away: Vector3 = global_position - (vic as Node3D).global_position
					away.y = 0.0
					_flee_dir = away.normalized() if away.length() > 0.1 else Vector3.RIGHT
					_bcast("_set_state", [S.FLEE, 0, 0])
				elif _wait_part <= 0.0:
					_bcast("_set_state", [S.CHASE, 0, 0])
		S.FLEE:
			var near := _nearest(false, 30.0)
			if near != null:
				var away2: Vector3 = global_position - near.global_position
				away2.y = 0.0
				if away2.length() > 0.1:
					_flee_dir = _flee_dir.lerp(away2.normalized(), clampf(delta * 1.5, 0.0, 1.0)).normalized()
			var goal := global_position + _flee_dir * 5.0
			_walk_to(goal, FLEE_SPEED, delta)
			if _st_t > FLEE_TIME:
				_bcast("_set_state", [S.BURROW, 0, 0])
		S.HELD:
			_follow_holder()
			var h = Network.find_player(holder_id)
			if h == null or h.is_dead or _st_t > HOLD_BREAK:
				# вырвался
				velocity = Vector3(randf_range(-3, 3), 4.0, randf_range(-3, 3))
				_thrown = false
				_bcast("_set_state", [S.FLY, 0, 0])
		S.FLY:
			velocity.y -= 9.8 * 1.4 * delta
			var spd := velocity.length()
			move_and_slide()
			if _st_t > 0.15 and (is_on_floor() or is_on_wall()):
				if (_thrown and spd > 5.0) or hp <= 0:
					_shatter()
				else:
					velocity = Vector3.ZERO
					_bcast("_set_state", [S.CHASE, 0, 0])
			elif global_position.y < _ground(global_position.x, global_position.z) - 3.0:
				_shatter()
		S.DEAD:
			global_position = home + Vector3.DOWN * 3.0
			if _st_t > RESPAWN and _nearest(false, 25.0) == null:
				hp = MAX_HP
				_bcast("_set_state", [S.NEST, 0, 0])
		S.BURROW:
			global_position.y -= delta * 1.2
			if _st_t > 1.0:
				_bcast("_drop_loot", [global_position + Vector3.UP * 1.3, Vector3.UP * 3.0])
				_bcast("_set_state", [S.DEAD, 0, 0])


func _active_count() -> int:
	var n := 0
	for r in get_tree().get_nodes_in_group("snow_robot"):
		if r != self and r.state in [S.EMERGE, S.CHASE, S.GRAB, S.FLEE, S.HELD, S.FLY]:
			n += 1
	return n


func _find_part(owner_peer: int, kind: String) -> Node3D:
	for pt in get_tree().get_nodes_in_group("limb_part"):
		if int(pt.owner_id) == owner_peer and pt.kind == kind and (pt.holder == null or not is_instance_valid(pt.holder)):
			if (pt as Node3D).global_position.distance_to(global_position) < 4.0:
				return pt
	return null


func _walk_to(goal: Vector3, speed: float, delta: float) -> void:
	var to := goal - global_position
	to.y = 0.0
	var want := to.normalized() * speed if to.length() > 0.4 else Vector3.ZERO
	velocity.x = move_toward(velocity.x, want.x, 30.0 * delta)
	velocity.z = move_toward(velocity.z, want.z, 30.0 * delta)
	if not is_on_floor():
		velocity.y -= 9.8 * 2.0 * delta
	else:
		velocity.y = -1.0
	move_and_slide()
	# застрял на крутом склоне — подпрыгивает
	if is_on_wall() and is_on_floor():
		velocity.y = 4.5
	var hv := Vector3(velocity.x, 0.0, velocity.z)
	if hv.length() > 0.3:
		_vis.rotation.y = lerp_angle(_vis.rotation.y, atan2(-hv.x, -hv.z), clampf(delta * 10.0, 0.0, 1.0))
	if global_position.y < _ground(global_position.x, global_position.z) - 2.0:
		global_position.y = _ground(global_position.x, global_position.z) + 0.3


func _follow_holder() -> void:
	var h = Network.find_player(holder_id)
	if h == null or h.get("snow") == null:
		return
	var x: Transform3D = h.snow.hold_xform()
	global_position = x.origin
	_vis.global_basis = x.basis


func _drop_target_grab() -> void:
	_rip_kind = ""


## Рассыпался: осколки, снег; украденная деталь падает
func _shatter() -> void:
	if not multiplayer.is_server():
		return
	_bcast("_drop_loot", [global_position + Vector3.UP * 0.8, velocity * 0.3 + Vector3.UP * 4.0])
	_bcast("_fx_shatter", [global_position])
	_bcast("_set_state", [S.DEAD, 0, 0])
	# шум от удара тревожит снег
	var av := get_tree().get_first_node_in_group("avalanche_valley")
	if av:
		av.add_tension(0.12)


@rpc("authority", "call_local", "reliable")
func _set_state(s: int, tid: int, _aux: int) -> void:
	state = s
	_st_t = 0.0
	if s == S.GRAB:
		target_id = tid
		_rip_kind = ""
	elif s != S.FLEE:
		target_id = 0
	if s == S.HELD:
		holder_id = tid
	else:
		holder_id = 0
	if s == S.NEST:
		global_position = home
		velocity = Vector3.ZERO
		hp = MAX_HP
	if s == S.CHASE or s == S.EMERGE:
		_vis.rotation = Vector3(0, _vis.rotation.y, 0)
	_apply_state_visual()


func set_dormant(v: bool) -> void:
	dormant = v
	_apply_state_visual()


func _apply_state_visual() -> void:
	_vis.visible = state not in [S.NEST, S.DEAD]
	_nest.visible = state in [S.NEST, S.EMERGE] and not dormant
	_nest.global_position = home + Vector3.UP * 0.2
	# глаза смотрят на тропу
	var to_path := Vector3(AvalancheLayout.center_x(AvalancheLayout.s_of(home.z)) - home.x, 0.0, 0.0)
	if to_path.length() > 0.1:
		_nest.rotation = Vector3(0, atan2(-to_path.x, -to_path.z), 0)
	_trail.emitting = state in [S.CHASE, S.FLEE]
	var flee := state == S.FLEE
	_eye_mat.albedo_color = Color(1.0, 0.3, 0.2) if flee else Color(0.4, 0.95, 1.0)
	_eye_mat.emission = Color(1.0, 0.2, 0.1) if flee else Color(0.3, 0.9, 1.0)
	_light.light_color = Color(1.0, 0.35, 0.2) if flee else Color(0.4, 0.85, 1.0)


@rpc("authority", "call_local", "reliable")
func _claim(part_id: String) -> void:
	var m := get_tree().current_scene.get_node_or_null("LimbParts")
	if m == null:
		return
	var part: Node3D = m.find(part_id)
	if part == null:
		return
	part.holder = self
	held_limb = part


@rpc("authority", "call_local", "reliable")
func _drop_loot(at: Vector3, vel: Vector3) -> void:
	if held_limb == null or not is_instance_valid(held_limb):
		held_limb = null
		return
	var part: RigidBody3D = held_limb as RigidBody3D
	held_limb = null
	part.holder = null
	part.freeze = false
	part.collision_layer = 1
	part.global_position = at
	part.linear_velocity = vel
	part.angular_velocity = Vector3(randf_range(-6, 6), randf_range(-3, 3), randf_range(-6, 6))


@rpc("authority", "call_local", "reliable")
func _fx_hit(at: Vector3) -> void:
	_burst.global_position = at + Vector3.UP * 0.7
	_burst.restart()


@rpc("authority", "call_local", "reliable")
func _fx_shatter(at: Vector3) -> void:
	_burst.global_position = at + Vector3.UP * 0.7
	_burst.restart()
	_ice_burst.global_position = at + Vector3.UP * 0.8
	_ice_burst.restart()
	# комья снега разлетаются (просто для вида)
	var snow := _mat(Color(0.9, 0.94, 1.0), 0.95)
	for k in 9:
		var rb := RigidBody3D.new()
		rb.collision_layer = 0
		rb.collision_mask = 1
		var cs := CollisionShape3D.new()
		var sh := SphereShape3D.new()
		sh.radius = randf_range(0.1, 0.2)
		cs.shape = sh
		rb.add_child(cs)
		_sph(rb, sh.radius, Vector3.ZERO, snow)
		get_tree().current_scene.add_child(rb)
		rb.global_position = at + Vector3(randf_range(-0.3, 0.3), randf_range(0.4, 1.2), randf_range(-0.3, 0.3))
		rb.linear_velocity = Vector3(randf_range(-4, 4), randf_range(2, 6), randf_range(-4, 4))
		get_tree().create_timer(3.5).timeout.connect(rb.queue_free)


func _animate(delta: float) -> void:
	_anim += delta * (11.0 if state == S.FLEE else 8.0)
	var moving := state in [S.CHASE, S.FLEE]
	var sw := sin(_anim) * (0.6 if moving else 0.0)
	if _legs.size() == 2:
		if state == S.HELD:
			# болтает ногами в воздухе
			_legs[0].rotation = Vector3(sin(_t * 21.0) * 1.1, 0, 0.25)
			_legs[1].rotation = Vector3(-sin(_t * 21.0 + 0.6) * 1.1, 0, -0.25)
		else:
			_legs[0].rotation = Vector3(sw, 0, 0)
			_legs[1].rotation = Vector3(-sw, 0, 0)
	if _arms.size() == 2:
		if state == S.GRAB:
			# когтями — в деталь, тянет-крутит
			# вцепился когтями в деталь и дёргает-выкручивает
			_arms[0].rotation = Vector3(-2.2 + sin(_t * 38.0) * 0.45, sin(_t * 19.0) * 0.4, 0.3)
			_arms[1].rotation = Vector3(-2.0 + cos(_t * 35.0) * 0.45, cos(_t * 17.0) * 0.4, -0.3)
		elif state == S.HELD:
			# машет лапами, пытается достать до головы дрона
			_arms[0].rotation = Vector3(-1.6 + sin(_t * 25.0) * 1.1, 0, 0.9 + sin(_t * 13.0) * 0.4)
			_arms[1].rotation = Vector3(-1.6 + cos(_t * 23.0) * 1.1, 0, -0.9 - cos(_t * 11.0) * 0.4)
		elif state == S.FLY:
			_arms[0].rotation = Vector3(-2.8, 0, 0.9)
			_arms[1].rotation = Vector3(-2.8, 0, -0.9)
		else:
			_arms[0].rotation = Vector3(-sw * 0.8 - 0.2, 0, 0.15)
			_arms[1].rotation = Vector3(sw * 0.8 - 0.2, 0, -0.15)
	_torso.position.y = 0.62 + absf(sin(_anim)) * (0.06 if moving else 0.0)
	_torso.rotation.z = sin(_anim) * (0.12 if moving else 0.03)
	if state == S.FLY:
		_vis.rotation.x += delta * 9.0
	elif state != S.HELD:
		_vis.rotation.x = lerpf(_vis.rotation.x, 0.0, clampf(delta * 8.0, 0.0, 1.0))
		_vis.rotation.z = 0.0
	if state == S.HELD:
		_head.rotation = Vector3(sin(_t * 9.0) * 0.3, sin(_t * 15.0) * 0.6, 0)
		var angry := fmod(_t, 0.3) < 0.15
		_eye_mat.emission = Color(1.0, 0.2, 0.1) if angry else Color(0.3, 0.9, 1.0)
	else:
		_head.rotation = Vector3(0, sin(_t * 1.7) * 0.4 if state == S.NEST or state == S.CHASE else 0.0, 0)
	_core_mat.emission_energy_multiplier = 2.0 + sin(_t * 5.0) * 1.0
	if _nest.visible:
		_nest_eyes.visible = fmod(_t + index * 0.7, 3.2) > 0.25    # моргает
