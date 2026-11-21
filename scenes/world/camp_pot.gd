extends Node3D
## Котелок у камина в избе лагеря «Борея-4».
##   Пустой: E — заложить припасы и сварить похлёбку (COOK_TIME с: булькает, идёт пар).
##   Готово: E — взять миску (SERVINGS мисок на котелок): корпус — до полного, руки/ноги на месте,
##   обморожение — долой. Кончились миски — можно варить снова.
## Решает хост, состояние рассылает всем.

const COOK_TIME := 10.0
const SERVINGS := 4
const REACH := 1.9

var state := 0                     ## 0 — пусто, 1 — варится, 2 — готово
var servings := 0
var _cook_t := 0.0
var _label: Label3D
var _soup: MeshInstance3D
var _soup_mat: StandardMaterial3D
var _steam: GPUParticles3D
var _t := 0.0


func _ready() -> void:
	var iron := StandardMaterial3D.new()
	iron.albedo_color = Color(0.12, 0.12, 0.13)
	iron.metallic = 0.7
	iron.roughness = 0.45
	var body := CylinderMesh.new()
	body.top_radius = 0.26
	body.bottom_radius = 0.2
	body.height = 0.32
	body.radial_segments = 14
	body.material = iron
	var mi := MeshInstance3D.new()
	mi.mesh = body
	mi.position.y = 0.16
	add_child(mi)
	var rim := TorusMesh.new()
	rim.inner_radius = 0.24
	rim.outer_radius = 0.29
	rim.material = iron
	var rmi := MeshInstance3D.new()
	rmi.mesh = rim
	rmi.position.y = 0.32
	add_child(rmi)
	# ручки
	for s in [-1.0, 1.0]:
		var hb := BoxMesh.new()
		hb.size = Vector3(0.1, 0.04, 0.04)
		hb.material = iron
		var h := MeshInstance3D.new()
		h.mesh = hb
		h.position = Vector3(s * 0.32, 0.27, 0)
		add_child(h)
	# похлёбка
	_soup_mat = StandardMaterial3D.new()
	_soup_mat.albedo_color = Color(0.62, 0.36, 0.15)
	_soup_mat.emission_enabled = true
	_soup_mat.emission = Color(0.5, 0.22, 0.05)
	_soup_mat.emission_energy_multiplier = 0.0
	var sd := CylinderMesh.new()
	sd.top_radius = 0.23
	sd.bottom_radius = 0.23
	sd.height = 0.02
	sd.radial_segments = 14
	sd.material = _soup_mat
	_soup = MeshInstance3D.new()
	_soup.mesh = sd
	_soup.position.y = 0.27
	_soup.visible = false
	add_child(_soup)
	_steam = FX.particles(Color(0.95, 0.95, 0.95, 0.35), 30, 1.6, 0.18, 0.4, 0.8, Vector3(0, 0.3, 0), 15.0, false)
	_steam.position.y = 0.35
	add_child(_steam)
	_label = Label3D.new()
	_label.font_size = 26
	_label.outline_size = 8
	_label.modulate = Color(1.0, 0.88, 0.6)
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.position.y = 0.85
	_label.no_depth_test = false
	add_child(_label)
	_show()


func _show() -> void:
	_soup.visible = state != 0
	_steam.emitting = state != 0
	match state:
		0:
			_label.text = "E — сварить похлёбку"
		1:
			_label.text = "Варится… %d с" % ceili(maxf(_cook_t, 0.0))
		2:
			_label.text = "E — взять миску (осталось %d)" % servings


func _process(delta: float) -> void:
	_t += delta
	if state == 1 and multiplayer.is_server():
		_cook_t -= delta
		if _cook_t <= 0.0:
			_set_state.rpc(2, SERVINGS)
	elif state == 1:
		_cook_t = maxf(_cook_t - delta, 0.0)
	if _soup.visible:
		# булькает
		_soup.position.y = 0.27 + 0.008 * sin(_t * 14.0)
		_soup_mat.emission_energy_multiplier = 0.3 + 0.2 * sin(_t * 5.0) if state == 1 else 0.15
	if state == 1:
		_label.text = "Варится… %d с" % ceili(maxf(_cook_t, 0.0))
	var me = Network.local_player
	if me == null or not is_instance_valid(me):
		_label.visible = false
		return
	var near: bool = me.global_position.distance_to(global_position) < REACH
	_label.visible = me.global_position.distance_to(global_position) < 5.0
	if near and not me.is_dead and me.held_parcel == null and Input.is_action_just_pressed("interact"):
		if state == 0:
			_request_cook.rpc_id(1)
		elif state == 2:
			_request_eat.rpc_id(1)


@rpc("any_peer", "call_local", "reliable")
func _request_cook() -> void:
	if not multiplayer.is_server() or state != 0:
		return
	_set_state.rpc(1, 0)


@rpc("any_peer", "call_local", "reliable")
func _request_eat() -> void:
	if not multiplayer.is_server() or state != 2 or servings <= 0:
		return
	var who := multiplayer.get_remote_sender_id()
	if who == 0:
		who = 1
	var left := servings - 1
	_set_state.rpc(2 if left > 0 else 0, left)
	if who != multiplayer.get_unique_id():
		_eat.rpc_id(who)
	else:
		_eat()


@rpc("authority", "call_local", "reliable")
func _set_state(s: int, n: int) -> void:
	if s == 1 and state != 1:
		_cook_t = COOK_TIME
	state = s
	servings = n
	_show()


## Съел миску — у себя: корпус полный, руки-ноги на месте, мороз долой
@rpc("authority", "call_remote", "reliable")
func _eat() -> void:
	var me = Network.local_player
	if me == null or not is_instance_valid(me) or me.is_dead:
		return
	me.health = me.max_health
	me.health_changed.emit(me.health, me.max_health)
	me.frost = 0.0
	if me.has_method("_set_limbs_net") and int(me.get("limb_mask")) != 15:
		me._set_limbs_net(15)
	me.add_shake(0.05)
	eaten += 1


var eaten := 0                     ## сколько мисок съел этот игрок (для проверок)
