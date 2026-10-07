class_name Parcel
extends RigidBody3D
## Посылка. У неё есть цена в кредитах — каждый удар её снижает.
## Когда посылку несут, физика выключается — ею управляет дрон.

signal price_changed(new_price: int)
signal broken

@export var display_name := "Посылка"
@export var base_price := 250          ## Цена целой посылки (кредиты)
@export var fragility := 1.0           ## Хрупкость: 2.0 — теряет вдвое больше от ударов
@export var safe_impact_speed := 5.5   ## Удары слабее этого (м/с) не портят посылку

const DAMAGE_PER_MS := 8.0             ## % цены за каждый м/с удара сверх порога

var price := 0
var hit_count := 0            ## Сколько раз посылку повредили
var is_held := false

var _prev_velocity := Vector3.ZERO
var _damage_cooldown := 0.0
var _saved_layer := 1
var _saved_mask := 1

@onready var value_label: Label3D = $ValueLabel


func _ready() -> void:
	add_to_group("parcel")
	price = base_price
	value_label.top_level = true
	_update_label()


func _process(_delta: float) -> void:
	value_label.global_position = global_position + Vector3.UP * 0.6


func _physics_process(delta: float) -> void:
	_damage_cooldown -= delta
	if not is_held:
		var impact := (linear_velocity - _prev_velocity).length()
		if impact > safe_impact_speed and _damage_cooldown <= 0.0:
			take_damage((impact - safe_impact_speed) * DAMAGE_PER_MS)
			_damage_cooldown = 0.15
	_prev_velocity = linear_velocity


## percent — сколько процентов от базовой цены теряем (до учёта хрупкости).
func take_damage(percent: float) -> void:
	if price <= 0:
		return
	var loss := roundi(base_price * percent / 100.0 * fragility)
	if loss < 1:
		return
	loss = mini(loss, price)
	price -= loss
	hit_count += 1
	_update_label()
	_spawn_popup("-%d кр" % loss, Color(1, 0.35, 0.3))
	price_changed.emit(price)
	if price <= 0:
		broken.emit()


func get_condition() -> float:
	return float(price) / float(maxi(base_price, 1))


## Дрон взял посылку: выключаем физику и столкновения.
func pick_up() -> void:
	is_held = true
	_saved_layer = collision_layer
	_saved_mask = collision_mask
	collision_layer = 0
	collision_mask = 0
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	freeze = true


## Дрон отпустил посылку (положил, бросил или уронил).
func release(release_velocity: Vector3) -> void:
	is_held = false
	collision_layer = _saved_layer
	collision_mask = _saved_mask
	freeze = false
	linear_velocity = release_velocity
	angular_velocity = Vector3(randf_range(-2, 2), randf_range(-2, 2), randf_range(-2, 2))
	_prev_velocity = release_velocity
	_damage_cooldown = 0.2


func _update_label() -> void:
	if price <= 0:
		value_label.text = "%s\nСЛОМАНА" % display_name
		value_label.modulate = Color(1, 0.2, 0.2)
		return
	value_label.text = "%s\n%d кр" % [display_name, price]
	value_label.modulate = Color(1, 0.3, 0.25).lerp(Color(0.45, 1, 0.5), get_condition())


## Всплывающая надпись «-35 кр», улетает вверх и тает.
func _spawn_popup(text: String, color: Color) -> void:
	var popup := Label3D.new()
	popup.text = text
	popup.modulate = color
	popup.font_size = 56
	popup.outline_size = 14
	popup.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	popup.no_depth_test = true
	get_tree().current_scene.add_child(popup)
	var start := global_position + Vector3.UP * 0.9
	popup.global_position = start
	var tween := popup.create_tween().set_parallel()
	tween.tween_property(popup, "global_position", start + Vector3.UP * 1.3, 1.1)
	tween.tween_property(popup, "modulate:a", 0.0, 0.8).set_delay(0.3)
	tween.tween_property(popup, "outline_modulate:a", 0.0, 0.8).set_delay(0.3)
	tween.chain().tween_callback(popup.queue_free)
