extends Node3D
## Уровень доставки (по сети).
##
## При запуске создаёт дрона каждому игроку из лобби. Таймер, чаевые, поломки
## дронов, бонусный груз и итоговый чек считает хост и рассылает остальным.
## Если в сцене уже стоит узел "Player" (старые тестовые уровни) — используется он.

@export var fast_time := 60.0
@export var tip_deadline := 150.0
@export var max_tip_percent := 40.0
@export var repair_cost := 50
@export var ambient_snow := false
@export var spawn_point := Vector3(0, 1, 0)
@export var player_scene: PackedScene = preload("res://scenes/player/player.tscn")

@onready var order: Parcel = $OrderParcel
@onready var zone = $DeliveryZone
@onready var objective_label: Label = $LevelHUD/Top/Objective
@onready var info_label: Label = $LevelHUD/Top/Info
@onready var results = $Results
@onready var banner_label: Label = get_node_or_null("LevelHUD/Banner")
@onready var banner_sub: Label = get_node_or_null("LevelHUD/BannerSub")

var player = null                ## Свой дрон
var elapsed := 0.0
var started := false
var finished := false
var deaths := 0
var bonus_rows: Array = []
var bonus_total := 0

var _sync_timer := 0.0
var _snow: GPUParticles3D


func _ready() -> void:
	add_to_group("level")
	order.add_to_group("order")
	for p in get_tree().get_nodes_in_group("parcel"):
		if p != order and p.required_carriers > 1:
			p.add_to_group("bonus")

	if banner_label:
		banner_label.modulate.a = 0.0
		banner_sub.modulate.a = 0.0

	_spawn_players()
	player = Network.local_player
	if player:
		player.died.connect(_on_local_died)

	zone.delivered.connect(_on_order_delivered)
	zone.bonus_delivered.connect(_on_bonus_delivered)
	Network.player_left.connect(_on_player_left)

	if ambient_snow:
		_snow = FX.particles(Color(1, 1, 1, 0.9), 700, 5.0, 0.03, 0.5, 1.5, Vector3(0.3, -1.2, 0.0), 30.0, false)
		FX.set_box(_snow, Vector3(25.0, 2.0, 25.0))
		(_snow.process_material as ParticleProcessMaterial).direction = Vector3.DOWN
		_snow.emitting = true
		add_child(_snow)

	Network.report_level_ready()


func _spawn_players() -> void:
	Network.ensure_players()
	if has_node("Player"):
		return   # старый уровень с готовым дроном
	var container := Node3D.new()
	container.name = "Players"
	add_child(container)
	var ids: Array = Network.players.keys()
	ids.sort()
	for i in ids.size():
		var p: Node3D = player_scene.instantiate()
		p.name = str(ids[i])
		p.position = spawn_point + Vector3((i - (ids.size() - 1) * 0.5) * 2.5, 0.0, 0.0)
		container.add_child(p)


func _process(delta: float) -> void:
	if finished:
		return
	if multiplayer.is_server():
		if not started and order.is_carried():
			started = true
		if started:
			elapsed += delta
		_sync_timer -= delta
		if _sync_timer <= 0.0 and Network.in_game and Network.is_online():
			_sync_timer = 0.25
			_level_state.rpc(elapsed, started)
	elif started:
		elapsed += delta

	if _snow and player:
		_snow.global_position = player.global_position + Vector3.UP * 9.0
	_update_hud()


@rpc("authority", "call_remote", "unreliable_ordered")
func _level_state(new_elapsed: float, new_started: bool) -> void:
	elapsed = new_elapsed
	started = new_started


func current_tip() -> int:
	if order.price <= 0:
		return 0
	var max_tip := order.base_price * max_tip_percent / 100.0
	var t := clampf((tip_deadline - elapsed) / (tip_deadline - fast_time), 0.0, 1.0)
	return roundi(max_tip * t)


func _update_hud() -> void:
	if player == null:
		return
	var my_id: int = player.peer_id
	if not started:
		objective_label.text = "Возьмите заказ «%s» в лагере" % order.display_name
		objective_label.modulate = Color.WHITE
	elif order.holders.has(my_id):
		objective_label.text = "Доставь заказ в пункт выдачи"
		objective_label.modulate = Color.WHITE
	elif order.holders.size() > 0:
		objective_label.text = "Заказ несёт %s — прикрой напарника" % Network.get_player_name(order.holders[0])
		objective_label.modulate = Color(0.7, 0.9, 1.0)
	else:
		objective_label.text = "Заказ лежит на земле — подберите его!"
		objective_label.modulate = Color(1, 0.7, 0.3)

	var dist: float = player.global_position.distance_to(zone.global_position)
	info_label.text = "Время %s     Заказ: %d кр     Чаевые: +%d кр     До пункта: %d м" % [
		_format_time(elapsed), order.price, current_tip(), roundi(dist)
	]


## Крупная надпись по центру экрана (только у этого игрока).
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


## Надпись у всех игроков (вызывает хост).
func announce(title: String, subtitle: String) -> void:
	if multiplayer.is_server():
		_announce_rpc.rpc(title, subtitle)


@rpc("authority", "call_local", "reliable")
func _announce_rpc(title: String, subtitle: String) -> void:
	show_banner(title, subtitle)


func _on_local_died() -> void:
	_report_death.rpc_id(1)


@rpc("any_peer", "call_local", "reliable")
func _report_death() -> void:
	if multiplayer.is_server() and not finished:
		deaths += 1


func _on_player_left(peer_id: int) -> void:
	if multiplayer.is_server():
		for p in get_tree().get_nodes_in_group("parcel"):
			p.server_remove_holder(peer_id)
	var node := get_node_or_null("Players/%d" % peer_id)
	if node:
		node.queue_free()
	show_banner("%s покинул игру" % Network.get_player_name(peer_id), "")


func _on_bonus_delivered(p: Parcel) -> void:
	bonus_rows.append(["Бонус: %s" % p.display_name, "+%d кр" % p.price, 1])
	bonus_total += p.price
	announce("Бонус доставлен!", "%s: +%d кр" % [p.display_name, p.price])


func _on_order_delivered(_p: Parcel) -> void:
	finished = true
	var tip := current_tip()
	var damage := order.base_price - order.price
	var repairs := deaths * repair_cost
	var total := order.price + tip - repairs + bonus_total

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
	rows.append_array(bonus_rows)
	if deaths > 0:
		rows.append(["Ремонт дронов (×%d)" % deaths, "-%d кр" % repairs, -1])

	_finish.rpc(rows, total)


@rpc("authority", "call_local", "reliable")
func _finish(rows: Array, total: int) -> void:
	finished = true
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
