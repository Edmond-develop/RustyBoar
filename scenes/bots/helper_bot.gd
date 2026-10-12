extends Node3D
## ВРЕМЕННЫЙ бот-помощник — чтобы одному проверять командные испытания.
## Появляется по «+», уходит по «−» (см. level.gd). Работает только у хоста
## (у остальных игроков в сети его не видно).
##
## Что умеет:
##  * следует за тобой (держится сбоку, чтобы не загораживать камеру);
##  * если рядом Ледяной вал с лучом маяка (coop_gate.gd), бот работает живым
##    зеркалом: луч отражается от его корпуса. Если луч маяка ловишь ты — бот
##    встаёт за конец барьера и отражает луч в печать; если нет — сам ловит луч
##    и отражает его на тебя (или в точку за барьером). Направление настраивает,
##    как и ты, — смещаясь вбок от линии луча (он тестовый — точный сдвиг знает).
##    Луч жжёт и бота, но бот не ломается;
##  * бот — летающий дрон: через торосы и стены перелетает, а не ищет дорогу;
##  * отстал больше чем на 120 м (ты погиб и появился в лагере) — прилетает к тебе.
## Для ворот и мяча бот считается игроком (группа "coop_helper").

const SPEED := 13.0              ## Скорость полёта, м/с
const CLIMB := 9.0               ## Скорость набора высоты, м/с
const GATE_RANGE := 70.0         ## Ворота ближе этого к тебе — бот летит на площадку
const LINES_HELLO := ["Бот-помощник прибыл. Зарплату не требую!", "Привет! Я вместо друга. Друг не пришёл.", "Включаюсь… Готов страдать за команду!"]
const LINES_POST := ["Ловлю луч корпусом! Горячо!", "Я — зеркало. Направлю куда надо.", "Встаю в луч. Не свети мне в глаз!"]
const LINES_FOLLOW := ["Лечу за тобой!", "Не теряйся, я рядом.", "Догоняю!"]
const LINES_BYE := ["Пока-пока! Отключаюсь.", "Батарейка села. Шучу. Ухожу.", "Удачи! Без меня не скучай."]

var index := 1
var is_dead := false             ## для систем, которые проверяют игроков
var peer_id := -1
var velocity := Vector3.ZERO

var _claimed_gate: Node = null
var _claimed_slot := -1          ## к какому гнезду идёт (или -1)
var _gate_target := Vector3.INF
var _think := 0.0
var _cruise_y := 0.0
var _mode := 0                   ## 0 — следует, 1 — работает зеркалом у вала
var _body: Node3D
var _glow_mat: StandardMaterial3D
var _bubble: Label3D
var _bubble_t := 0.0
var _time := 0.0


func _ready() -> void:
	add_to_group("coop_helper")
	peer_id = -100 - index
	_build_visual()
	say(LINES_HELLO.pick_random())


func _build_visual() -> void:
	_body = Node3D.new()
	_body.position.y = 0.55
	add_child(_body)
	var shell := StandardMaterial3D.new()
	shell.albedo_color = Color(0.25, 0.75, 0.35)
	shell.metallic = 0.3
	shell.roughness = 0.4
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.12, 0.13, 0.15)
	dark.metallic = 0.6
	dark.roughness = 0.5
	_glow_mat = StandardMaterial3D.new()
	_glow_mat.albedo_color = Color(0.5, 1.0, 0.6)
	_glow_mat.emission_enabled = true
	_glow_mat.emission = Color(0.4, 1.0, 0.5)
	_glow_mat.emission_energy_multiplier = 2.0
	_mesh(_body, _sphere(0.42), shell, Vector3.ZERO, Vector3(1, 0.9, 1))
	var ring := TorusMesh.new()
	ring.inner_radius = 0.4
	ring.outer_radius = 0.5
	_mesh(_body, ring, dark, Vector3(0, -0.05, 0), Vector3.ONE)
	_mesh(_body, _sphere(0.14), _glow_mat, Vector3(0, 0.08, -0.36), Vector3.ONE)   # глаз
	var ant := CylinderMesh.new()
	ant.top_radius = 0.02
	ant.bottom_radius = 0.02
	ant.height = 0.4
	_mesh(_body, ant, dark, Vector3(0, 0.55, 0), Vector3.ONE)
	_mesh(_body, _sphere(0.06), _glow_mat, Vector3(0, 0.77, 0), Vector3.ONE)
	for k in 4:
		var a := TAU * k / 4.0 + PI * 0.25
		var leg := CylinderMesh.new()
		leg.top_radius = 0.04
		leg.bottom_radius = 0.03
		leg.height = 0.45
		_mesh(_body, leg, dark, Vector3(cos(a) * 0.3, -0.42, sin(a) * 0.3), Vector3.ONE)
	var light := OmniLight3D.new()
	light.light_color = Color(0.4, 1.0, 0.5)
	light.light_energy = 0.8
	light.omni_range = 3.0
	light.position = Vector3(0, -0.3, 0)
	_body.add_child(light)
	var tag := Label3D.new()
	tag.text = "БОТ %d" % index
	tag.font_size = 48
	tag.outline_size = 10
	tag.modulate = Color(0.6, 1.0, 0.65)
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.position = Vector3(0, 1.0, 0)
	tag.no_depth_test = true
	_body.add_child(tag)
	_bubble = Label3D.new()
	_bubble.font_size = 30
	_bubble.outline_size = 8
	_bubble.modulate = Color(1, 1, 1)
	_bubble.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_bubble.position = Vector3(0, 1.4, 0)
	_body.add_child(_bubble)


func _sphere(r: float) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	return s


func _mesh(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, scl: Vector3) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.scale = scl
	parent.add_child(mi)


## Реплика над ботом на несколько секунд
func say(text: String) -> void:
	if _bubble:
		_bubble.text = text
		_bubble_t = 3.5


func _physics_process(delta: float) -> void:
	_time += delta
	if _bubble_t > 0.0:
		_bubble_t -= delta
		_bubble.modulate.a = clampf(_bubble_t, 0.0, 1.0)
	var owner_node: Node3D = Network.local_player
	if owner_node == null:
		return
	_think -= delta
	if _think <= 0.0:
		_think = 0.4
		_decide(owner_node)

	var target := _target(owner_node)
	var to := target - global_position
	var flat := Vector2(to.x, to.z)
	var dist := flat.length()
	if dist > 120.0:
		global_position = owner_node.global_position + Vector3(2.0, 0.5, 2.0)
		return
	var ground := _ground_at(global_position)
	var desired_y := target.y
	if dist > 3.0:
		desired_y = maxf(_cruise_y, target.y)
	var h := Vector3.ZERO
	if dist > 0.15:
		var sp := minf(SPEED, dist * 2.5)
		# сначала набрать высоту, потом лететь (чтобы не врезаться в стену)
		if global_position.y < desired_y - 1.5 and dist > 3.0:
			sp *= 0.25
		h = Vector3(flat.x, 0.0, flat.y) / dist * sp
	var vy := clampf((desired_y - global_position.y) * 4.0, -CLIMB, CLIMB)
	velocity = velocity.lerp(Vector3(h.x, vy, h.z), clampf(delta * 6.0, 0.0, 1.0))
	global_position += velocity * delta
	global_position.y = maxf(global_position.y, ground)
	# смотрит туда, куда летит; на месте — слегка покачивается
	var hv := Vector2(velocity.x, velocity.z)
	if hv.length() > 0.5:
		rotation.y = lerp_angle(rotation.y, atan2(-hv.x, -hv.y), clampf(delta * 8.0, 0.0, 1.0))
	var flying := global_position.y > ground + 0.4
	_body.position.y = 0.55 + sin(_time * 3.0) * (0.05 if not flying else 0.12)
	_body.rotation.x = clampf(-velocity.length() * 0.015, -0.2, 0.0)
	_glow_mat.emission_energy_multiplier = 2.0 + sin(_time * 5.0) * 0.8
	if _mode == 1 and is_instance_valid(_claimed_gate):
		_claimed_gate.bot_work(self, delta)


## Выбрать, что делать: работать у ворот зеркалом или следовать за хозяином
func _decide(owner_node: Node3D) -> void:
	var gate := _nearest_gate(owner_node)
	var prev_mode := _mode
	_gate_target = Vector3.INF
	if gate != null:
		_gate_target = gate.bot_target(self, owner_node)
	if _gate_target != Vector3.INF:
		_claimed_gate = gate
		_mode = 1
	else:
		_release()
		_mode = 0
	if _mode != prev_mode:
		say(LINES_POST.pick_random() if _mode == 1 else LINES_FOLLOW.pick_random())
	# высота полёта: выше всего, что под путём
	var target := _target(owner_node)
	var top := maxf(_ground_at(global_position), _ground_at(target))
	var from := global_position
	var steps := int(from.distance_to(target) / 3.0)
	for i in range(1, mini(steps, 40)):
		top = maxf(top, _ground_at(from.lerp(target, float(i) / steps)))
	_cruise_y = top + 2.5


func _release() -> void:
	if is_instance_valid(_claimed_gate):
		_claimed_gate.bot_release(self)
	_claimed_gate = null
	_claimed_slot = -1


func _nearest_gate(owner_node: Node3D) -> Node:
	for g in get_tree().get_nodes_in_group("coop_gate"):
		if bool(g.get("is_open")):
			continue   # ворота уже открыты — летим за хозяином
		if (g as Node3D).global_position.distance_to(owner_node.global_position) < GATE_RANGE:
			return g
	return null


## Куда сейчас лететь
func _target(owner_node: Node3D) -> Vector3:
	if _mode == 1 and _gate_target != Vector3.INF:
		return _gate_target + Vector3(0.0, 0.55, 0.0)   # корпус — на высоте луча
	# следовать: сбоку от хозяина (позади висит камера), каждому боту своё место
	var ref: Node3D = owner_node.get("camera_pivot") as Node3D
	if ref == null:
		ref = owner_node
	var basis := ref.global_basis
	var back := basis.z
	back.y = 0.0
	back = back.normalized() if back.length() > 0.01 else Vector3.BACK
	var right := Vector3.UP.cross(back).normalized()
	var side := -1.0 if index % 2 == 0 else 1.0
	var p := owner_node.global_position + back * 0.3 + right * side * (2.4 + index * 1.2)
	if global_position.distance_to(p) < 1.5:
		return global_position   # уже рядом — не дёргаемся
	p.y = _ground_at(p)
	return p


## Высота поверхности под точкой (луч сверху вниз)
func _ground_at(p: Vector3) -> float:
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(Vector3(p.x, 60.0, p.z), Vector3(p.x, -40.0, p.z), 1)
	var skip: Array[RID] = []
	for d in get_tree().get_nodes_in_group("player"):
		if d is CollisionObject3D:
			skip.append((d as CollisionObject3D).get_rid())
	q.exclude = skip
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return p.y
	return (hit["position"] as Vector3).y
