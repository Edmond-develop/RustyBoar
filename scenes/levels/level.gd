extends Node3D
## Управляет уровнем доставки: таймер, чаевые, подсказки, итоговый чек.
## Таймер запускается, когда дрон впервые берёт заказ.

@export var fast_time := 60.0         ## До этого времени (сек) — максимальные чаевые
@export var tip_deadline := 150.0     ## После этого времени чаевых нет
@export var max_tip_percent := 40.0   ## Максимальные чаевые — % от стоимости заказа
@export var repair_cost := 50         ## Списание за каждый сломанный дрон
@export var parcel_lost_y := -5.0     ## Посылка упала ниже (пропасть, вода) — возвращается на тропу
@export var ambient_snow := false     ## Лёгкий снегопад вокруг дрона

@onready var player = $Player  # скрипт дрона (player.gd)
@onready var order: Parcel = $OrderParcel
@onready var zone = $DeliveryZone
@onready var objective_label: Label = $LevelHUD/Top/Objective
@onready var info_label: Label = $LevelHUD/Top/Info
@onready var results = $Results

var elapsed := 0.0
var started := false
var finished := false
var deaths := 0

var _order_start := Transform3D.IDENTITY
var _safe_pos := Vector3.ZERO
var _has_safe_pos := false
var _safe_timer := 0.0
var _snow: GPUParticles3D

@onready var banner_label: Label = get_node_or_null("LevelHUD/Banner")
@onready var banner_sub: Label = get_node_or_null("LevelHUD/BannerSub")


func _ready() -> void:
	add_to_group("level")
	order.add_to_group("order")
	if banner_label:
		banner_label.modulate.a = 0.0
		banner_sub.modulate.a = 0.0
	if ambient_snow:
		_snow = FX.particles(Color(1, 1, 1, 0.9), 700, 5.0, 0.03, 0.5, 1.5, Vector3(0.3, -1.2, 0.0), 30.0, false)
		FX.set_box(_snow, Vector3(25.0, 2.0, 25.0))
		(_snow.process_material as ParticleProcessMaterial).direction = Vector3.DOWN
		_snow.emitting = true
		add_child(_snow)
	_order_start = order.global_transform
	zone.delivered.connect(_on_delivered)
	player.died.connect(_on_player_died)


func _process(delta: float) -> void:
	if finished:
		return
	if not started and order.is_held:
		started = true
	if started:
		elapsed += delta

	# Запоминаем последнее надёжное место, где дрон стоял с заказом
	_safe_timer -= delta
	if _safe_timer <= 0.0:
		_safe_timer = 0.5
		if order.is_held and player.is_on_safe_ground():
			_safe_pos = player.global_position
			_has_safe_pos = true

	# Заказ упал в пропасть или в воду — возвращаем на тропу
	if not order.is_held and order.global_position.y < parcel_lost_y:
		order.linear_velocity = Vector3.ZERO
		order.angular_velocity = Vector3.ZERO
		if _has_safe_pos:
			order.global_transform = Transform3D(Basis(), _safe_pos + Vector3.UP * 1.2)
		else:
			order.global_transform = _order_start
		show_banner("Заказ возвращён на тропу", "Курьерская служба выловила посылку")

	if _snow:
		_snow.global_position = player.global_position + Vector3.UP * 9.0

	_update_hud()


func current_tip() -> int:
	if order.price <= 0:
		return 0
	var max_tip := order.base_price * max_tip_percent / 100.0
	var t := clampf((tip_deadline - elapsed) / (tip_deadline - fast_time), 0.0, 1.0)
	return roundi(max_tip * t)


func _update_hud() -> void:
	if not started:
		objective_label.text = "Возьми заказ «%s» на складе" % order.display_name
		objective_label.modulate = Color.WHITE
	elif player.get_held_parcel() == order:
		objective_label.text = "Доставь заказ в пункт выдачи"
		objective_label.modulate = Color.WHITE
	else:
		objective_label.text = "Заказ выпал — подбери его!"
		objective_label.modulate = Color(1, 0.7, 0.3)

	var dist: float = player.global_position.distance_to(zone.global_position)
	info_label.text = "Время %s     Заказ: %d кр     Чаевые: +%d кр     До пункта: %d м" % [
		_format_time(elapsed), order.price, current_tip(), roundi(dist)
	]


## Крупная надпись по центру экрана (название участка и подсказка).
func show_banner(title: String, subtitle: String) -> void:
	if banner_label == null:
		return
	banner_label.text = title
	banner_sub.text = subtitle
	var tw := create_tween()
	tw.tween_property(banner_label, "modulate:a", 1.0, 0.4)
	tw.parallel().tween_property(banner_sub, "modulate:a", 1.0, 0.4)
	tw.tween_interval(3.0)
	tw.tween_property(banner_label, "modulate:a", 0.0, 0.8)
	tw.parallel().tween_property(banner_sub, "modulate:a", 0.0, 0.8)


func _on_player_died() -> void:
	if not finished:
		deaths += 1


func _on_delivered(_parcel: Parcel) -> void:
	finished = true
	var tip := current_tip()
	var damage := order.base_price - order.price
	var repairs := deaths * repair_cost
	var total := order.price + tip - repairs

	var rows: Array = []
	rows.append(["Заказ", "«%s»" % order.display_name, 0])
	rows.append(["Стоимость заказа", "%d кр" % order.base_price, 0])
	if order.hit_count > 0:
		rows.append(["Повреждения (%d %s)" % [order.hit_count, _plural(order.hit_count, "удар", "удара", "ударов")],
			"-%d кр" % damage, -1])
	else:
		rows.append(["Повреждения", "нет — идеально!", 1])
	rows.append(["Время доставки", _format_time(elapsed), 0])
	if order.price <= 0:
		rows.append(["Чаевые за скорость", "посылка сломана", -1])
	else:
		rows.append(["Чаевые за скорость", "+%d кр" % tip, 1 if tip > 0 else 0])
	if deaths > 0:
		rows.append(["Ремонт дрона (×%d)" % deaths, "-%d кр" % repairs, -1])

	# Небольшая пауза, чтобы увидеть конфетти
	await get_tree().create_timer(1.2).timeout
	results.show_receipt("ЗАКАЗ ДОСТАВЛЕН", rows, total)


func _format_time(seconds: float) -> String:
	var s := int(seconds)
	return "%d:%02d" % [s / 60, s % 60]


func _plural(n: int, one: String, few: String, many: String) -> String:
	var n10 := n % 10
	var n100 := n % 100
	if n10 == 1 and n100 != 11:
		return one
	if n10 >= 2 and n10 <= 4 and (n100 < 10 or n100 >= 20):
		return few
	return many
