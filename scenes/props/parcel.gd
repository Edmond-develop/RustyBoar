class_name Parcel
extends RigidBody3D
## Посылка (по сети).
##
## Физику посылки считает только хост и рассылает её положение остальным.
## Кто держит посылку — список holders (номера игроков). Пока посылку несут,
## каждый компьютер сам ставит её в руки нужного дрона — так она не «дёргается».
##
## Тяжёлая посылка (required_carriers = 2):
##   один курьер — может только тянуть её волоком по земле;
##   два курьера — поднимают и несут между собой. Разошлись слишком далеко — уронили.

signal price_changed(new_price: int)
signal broken
signal holders_changed

@export var display_name := "Посылка"
@export var base_price := 250
@export var fragility := 1.0
@export var safe_impact_speed := 5.5
@export var required_carriers := 1      ## 2 — тяжёлый груз, нести вдвоём
@export var drag_speed := 1.8           ## Скорость волочения одним курьером
@export var max_carry_distance := 3.4   ## Тяжёлый груз падает, если носильщики разошлись дальше
@export var label_height := 0.6
@export var lost_y := -12.0             ## Упала ниже (в пропасть) — возвращается на тропу
@export var soak_percent := 2.5         ## Сколько % цены теряет за секунду в воде

const DAMAGE_PER_MS := 8.0

var price := 0
var hit_count := 0
var holders: Array = []
var is_delivered := false
## Посылку нельзя толкать/подбирать: её несут или она уже доставлена
var is_held: bool:
	get:
		return is_carried() or is_delivered

var _prev_velocity := Vector3.ZERO
var _damage_cooldown := 0.0
var _saved_layer := 1
var _saved_mask := 1
var _net_pos := Vector3.ZERO
var _net_rot := Quaternion.IDENTITY
var _send_timer := 0.0
var _start_xform := Transform3D.IDENTITY
var _safe_pos := Vector3.ZERO
var _has_safe_pos := false
var _safe_timer := 0.0
var _lake: Node = null
var _floating := false
var _float_anchor := Vector3.ZERO
var _soak_t := 0.0

@onready var value_label: Label3D = $ValueLabel


func _ready() -> void:
	add_to_group("parcel")
	price = base_price
	value_label.top_level = true
	_saved_layer = collision_layer
	_saved_mask = collision_mask
	_net_pos = global_position
	_net_rot = quaternion
	_start_xform = global_transform
	if not multiplayer.is_server():
		freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		freeze = true
	_update_label()


# ---------------------------------------------------------------------------
#  Состояние
# ---------------------------------------------------------------------------

func is_carried() -> bool:
	if required_carriers <= 1:
		return holders.size() >= 1
	return holders.size() >= required_carriers


func is_lifted() -> bool:
	return required_carriers > 1 and holders.size() >= required_carriers


func can_be_grabbed_by(peer_id: int) -> bool:
	return not is_delivered and not holders.has(peer_id) and holders.size() < required_carriers


func get_condition() -> float:
	return float(price) / float(maxi(base_price, 1))


# ---------------------------------------------------------------------------
#  Каждый кадр
# ---------------------------------------------------------------------------

func _process(_delta: float) -> void:
	value_label.global_position = global_position + Vector3.UP * label_height
	if is_delivered:
		return
	if is_carried():
		_follow_holders()


func _physics_process(delta: float) -> void:
	if is_delivered or is_carried():
		if multiplayer.is_server() and is_lifted():
			_check_carrier_distance()
		_track_safe_position(delta)
		return

	if multiplayer.is_server():
		if holders.size() > 0:
			_drag(delta)
		if _float_in_water(delta):
			_prev_velocity = linear_velocity
		else:
			_detect_impacts(delta)
		_check_lost()
		_send_state(delta)
	else:
		var t := clampf(delta * 15.0, 0.0, 1.0)
		if global_position.distance_to(_net_pos) > 4.0:
			global_position = _net_pos
		else:
			global_position = global_position.lerp(_net_pos, t)
		quaternion = quaternion.slerp(_net_rot, t)


func _follow_holders() -> void:
	var drones := _holder_drones()
	if drones.is_empty():
		return
	if required_carriers <= 1:
		global_transform = drones[0].get_carry_transform()
	elif drones.size() >= 2:
		var a: Vector3 = drones[0].get_heavy_hold_point()
		var b: Vector3 = drones[1].get_heavy_hold_point()
		var dir := b - a
		dir.y = 0.0
		var yaw := atan2(-dir.z, dir.x) if dir.length() > 0.05 else rotation.y
		global_transform = Transform3D(Basis(Vector3.UP, yaw), (a + b) * 0.5)


func _holder_drones() -> Array:
	var result := []
	for id in holders:
		var d: Node = Network.find_player(id)
		if d != null:
			result.append(d)
	return result


# ---------------------------------------------------------------------------
#  Только на хосте
# ---------------------------------------------------------------------------

func _drag(delta: float) -> void:
	var drones := _holder_drones()
	if drones.is_empty():
		return
	var grip: Vector3 = drones[0].get_drag_point()
	var to := grip - global_position
	to.y = 0.0
	if to.length() > 3.2:
		# Курьер отошёл слишком далеко — отпустил
		_server_set_holders([])
		return
	var target := (to * 4.0).limit_length(drag_speed)
	linear_velocity.x = lerpf(linear_velocity.x, target.x, 10.0 * delta)
	linear_velocity.z = lerpf(linear_velocity.z, target.z, 10.0 * delta)


func _check_carrier_distance() -> void:
	var drones := _holder_drones()
	if drones.size() < 2:
		return
	var d: float = drones[0].global_position.distance_to(drones[1].global_position)
	if d > max_carry_distance:
		var vel: Vector3 = (drones[0].velocity + drones[1].velocity) * 0.5
		_server_release(global_transform, vel + Vector3.UP * 1.5)
		_server_damage(10.0)


func _detect_impacts(delta: float) -> void:
	_damage_cooldown -= delta
	var impact := (linear_velocity - _prev_velocity).length()
	if impact > safe_impact_speed and _damage_cooldown <= 0.0:
		_server_damage((impact - safe_impact_speed) * DAMAGE_PER_MS)
		_damage_cooldown = 0.15
	_prev_velocity = linear_velocity


## Хост: в полынье посылка держится на плаву, медленно дрейфует и мокнет
func _float_in_water(delta: float) -> bool:
	if _lake == null:
		_lake = get_tree().get_first_node_in_group("ice_lake")
		if _lake == null:
			return false
	var p := global_position
	if not _lake.in_bounds(p):
		_stop_floating()
		return false
	if not _lake.is_hole(p.x, p.z):
		# Затянуло под кромку льда — выталкиваем обратно в полынью
		if _floating and p.y < _lake.river_y(p.z) - 0.1:
			var back := _float_anchor - p
			back.y = 0.0
			linear_velocity.x = back.x * 2.0
			linear_velocity.z = back.z * 2.0
			return true
		_stop_floating()
		return false
	var wy: float = _lake.water_y(p.z)
	if p.y > wy + 0.6:
		_stop_floating()   # ещё летит над полыньёй
		return false
	if not _floating:
		_floating = true
		_float_anchor = p
		_soak_t = 0.0
		gravity_scale = 0.0
	var bob := sin(Time.get_ticks_msec() * 0.002 + p.x) * 0.08
	linear_velocity.y = lerpf(linear_velocity.y, (wy - p.y) * 3.0 + bob, clampf(6.0 * delta, 0.0, 1.0))
	linear_velocity.x *= 0.97
	linear_velocity.z *= 0.97
	angular_velocity *= 0.95
	_soak_t += delta
	if _soak_t >= 1.0:
		_soak_t = 0.0
		_server_damage(soak_percent)
	return true


func _stop_floating() -> void:
	if _floating:
		_floating = false
		gravity_scale = 1.0


## Запоминаем надёжное место, пока посылку несут
func _track_safe_position(delta: float) -> void:
	if not multiplayer.is_server() or is_delivered:
		return
	_safe_timer -= delta
	if _safe_timer > 0.0:
		return
	_safe_timer = 0.5
	var drones := _holder_drones()
	if drones.size() > 0 and drones[0].is_on_safe_ground():
		_safe_pos = drones[0].global_position
		_has_safe_pos = true


func _check_lost() -> void:
	if global_position.y <= lost_y:
		server_return_to_path()


## Хост: вернуть посылку на последнее надёжное место (упала в воду, в пропасть)
func server_return_to_path() -> void:
	if not multiplayer.is_server() or is_carried() or is_delivered:
		return
	var xform := _start_xform
	if _has_safe_pos:
		xform = Transform3D(Basis(), _safe_pos + Vector3.UP * 1.2)
	global_transform = xform
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	_prev_velocity = Vector3.ZERO
	if Network.is_online():
		_net_state.rpc(global_position, quaternion)
	get_tree().call_group("level", "announce", "«%s» возвращён на тропу" % display_name, "Курьерская служба выловила груз")


func _send_state(delta: float) -> void:
	if not Network.is_online():
		return
	_send_timer -= delta
	if _send_timer > 0.0:
		return
	_send_timer = 0.05
	_net_state.rpc(global_position, quaternion)


@rpc("authority", "call_remote", "unreliable_ordered")
func _net_state(pos: Vector3, rot: Quaternion) -> void:
	_net_pos = pos
	_net_rot = rot


# ---------------------------------------------------------------------------
#  Запросы от игроков → хост
# ---------------------------------------------------------------------------

func request_pickup(peer_id: int) -> void:
	_rpc_request_pickup.rpc_id(1, peer_id)


@rpc("any_peer", "call_local", "reliable")
func _rpc_request_pickup(peer_id: int) -> void:
	if not multiplayer.is_server() or not can_be_grabbed_by(peer_id):
		return
	var new_holders := holders.duplicate()
	new_holders.append(peer_id)
	_server_set_holders(new_holders)


func request_release(peer_id: int, xform: Transform3D, vel: Vector3) -> void:
	_rpc_request_release.rpc_id(1, peer_id, xform, vel)


@rpc("any_peer", "call_local", "reliable")
func _rpc_request_release(peer_id: int, xform: Transform3D, vel: Vector3) -> void:
	if not multiplayer.is_server() or not holders.has(peer_id):
		return
	if is_carried():
		_server_release(xform, vel)     # отпустил — падает вся посылка
	else:
		var new_holders := holders.duplicate()
		new_holders.erase(peer_id)      # перестал тянуть тяжёлый груз
		_server_set_holders(new_holders)


## Игрок вышел из игры — убираем его из носильщиков
func server_remove_holder(peer_id: int) -> void:
	if not multiplayer.is_server() or not holders.has(peer_id):
		return
	if is_carried():
		_server_release(global_transform, Vector3.UP)
	else:
		var new_holders := holders.duplicate()
		new_holders.erase(peer_id)
		_server_set_holders(new_holders)


## Урон посылке (в % от базовой цены). Можно вызывать на любом компьютере.
func take_damage(percent: float) -> void:
	if multiplayer.is_server():
		_server_damage(percent)
	else:
		_rpc_damage.rpc_id(1, percent)


@rpc("any_peer", "call_local", "reliable")
func _rpc_damage(percent: float) -> void:
	if multiplayer.is_server():
		_server_damage(percent)


## Пункт выдачи забирает посылку
func server_deliver(xform: Transform3D) -> void:
	if not multiplayer.is_server():
		return
	_set_delivered.rpc(xform)


# ---------------------------------------------------------------------------
#  Хост → все
# ---------------------------------------------------------------------------

func _server_set_holders(new_holders: Array) -> void:
	_set_holders.rpc(new_holders)


func _server_release(xform: Transform3D, vel: Vector3) -> void:
	_set_holders.rpc([])
	global_transform = xform
	linear_velocity = vel
	angular_velocity = Vector3(randf_range(-2, 2), randf_range(-2, 2), randf_range(-2, 2))
	_prev_velocity = vel
	_damage_cooldown = 0.2
	if Network.is_online():
		_net_state.rpc(global_position, quaternion)


func _server_damage(percent: float) -> void:
	if price <= 0 or is_delivered:
		return
	var loss := roundi(base_price * percent / 100.0 * fragility)
	if loss < 1:
		return
	loss = mini(loss, price)
	_price_update.rpc(price - loss, hit_count + 1, loss)


@rpc("authority", "call_local", "reliable")
func _set_holders(new_holders: Array) -> void:
	var was_carried := is_carried()
	holders = new_holders.duplicate()
	var now_carried := is_carried()
	if now_carried and not was_carried:
		_stop_floating()
		collision_layer = 0
		collision_mask = 0
		freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		freeze = true
	elif was_carried and not now_carried:
		collision_layer = _saved_layer
		collision_mask = _saved_mask
		_net_pos = global_position
		_net_rot = quaternion
		if multiplayer.is_server():
			freeze = false
	holders_changed.emit()
	if Network.local_player:
		Network.local_player.on_parcel_holders_changed(self)


@rpc("authority", "call_local", "reliable")
func _price_update(new_price: int, hits: int, loss: int) -> void:
	price = new_price
	hit_count = hits
	_update_label()
	_spawn_popup("-%d кр" % loss, Color(1, 0.35, 0.3))
	price_changed.emit(price)
	if price <= 0:
		broken.emit()


@rpc("authority", "call_local", "reliable")
func _set_delivered(xform: Transform3D) -> void:
	is_delivered = true
	var had_holders := not holders.is_empty()
	holders = []
	collision_layer = 0
	collision_mask = 0
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	freeze = true
	global_transform = xform
	if had_holders:
		holders_changed.emit()
		if Network.local_player:
			Network.local_player.on_parcel_holders_changed(self)


# ---------------------------------------------------------------------------
#  Внешний вид
# ---------------------------------------------------------------------------

func _update_label() -> void:
	var heavy := "  [вдвоём]" if required_carriers > 1 else ""
	if price <= 0:
		value_label.text = "%s\nСЛОМАНА" % display_name
		value_label.modulate = Color(1, 0.2, 0.2)
		return
	value_label.text = "%s%s\n%d кр" % [display_name, heavy, price]
	value_label.modulate = Color(1, 0.3, 0.25).lerp(Color(0.45, 1, 0.5), get_condition())


func _spawn_popup(text: String, color: Color) -> void:
	var popup := Label3D.new()
	popup.text = text
	popup.modulate = color
	popup.font_size = 56
	popup.outline_size = 14
	popup.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	popup.no_depth_test = true
	get_tree().current_scene.add_child(popup)
	var start := global_position + Vector3.UP * (label_height + 0.3)
	popup.global_position = start
	var tween := popup.create_tween().set_parallel()
	tween.tween_property(popup, "global_position", start + Vector3.UP * 1.3, 1.1)
	tween.tween_property(popup, "modulate:a", 0.0, 0.8).set_delay(0.3)
	tween.tween_property(popup, "outline_modulate:a", 0.0, 0.8).set_delay(0.3)
	tween.chain().tween_callback(popup.queue_free)
