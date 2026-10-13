extends Node3D
## Уровень-экспедиция (по сети).
##
## При запуске создаёт дрона каждому игроку из лобби, показывает крупные надписи
## участков, считает время экспедиции и поломки дронов.
## Цель пока одна — исследовать Борею; поиск деталей корабля появится позже.
## Если в сцене уже стоит узел "Player" (старые тестовые уровни) — используется он.
##
## ВРЕМЕННО, для проверки одному: боты-курьеры в скафандрах («+»/«−», панель B,
## G — переселиться в бота), локации по «=», тестовые грузы — всё в test_tools.gd.

@export var ambient_snow := false
@export var spawn_point := Vector3(0, 1, 0)
@export var snow_stop_from_z := 960.0   ## Южнее снегопад слабеет (база)…
@export var snow_stop_to_z := 1020.0     ## …и здесь стихает совсем
@export var objective := "Исследуй Борею — на севере за ледяным озером"
@export var player_scene: PackedScene = preload("res://scenes/player/player.tscn")

const TEST_TOOLS := preload("res://scenes/levels/test_tools.gd")

@onready var objective_label: Label = get_node_or_null("LevelHUD/Top/Objective")
@onready var info_label: Label = get_node_or_null("LevelHUD/Top/Info")
@onready var banner_label: Label = get_node_or_null("LevelHUD/Banner")
@onready var banner_sub: Label = get_node_or_null("LevelHUD/BannerSub")

var player = null                ## Свой дрон
var elapsed := 0.0
var deaths := 0

var _sync_timer := 0.0
var _snow: GPUParticles3D


func _ready() -> void:
	add_to_group("level")
	if banner_label:
		banner_label.modulate.a = 0.0
		banner_sub.modulate.a = 0.0

	_spawn_players()
	player = Network.local_player
	if player:
		player.died.connect(_on_local_died)
	Network.player_left.connect(_on_player_left)
	var tools := Node.new()
	tools.set_script(TEST_TOOLS)
	tools.name = "TestTools"
	tools.set("level", self)
	add_child(tools)

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
		var pos := spawn_point + Vector3((i - (ids.size() - 1) * 0.5) * 2.5, 0.0, 0.0)
		# ставим на землю: рельеф на базе неровный
		var terrain := get_tree().get_first_node_in_group("terrain")
		if terrain:
			pos.y = maxf(pos.y, terrain.height_at(pos.x, pos.z) + 0.6)
		p.position = pos
		container.add_child(p)


func _process(delta: float) -> void:
	elapsed += delta
	if multiplayer.is_server():
		_sync_timer -= delta
		if _sync_timer <= 0.0 and Network.in_game and Network.is_online():
			_sync_timer = 1.0
			_level_state.rpc(elapsed)

	if _snow and player:
		_snow.global_position = player.global_position + Vector3.UP * 9.0
		# над лугом базы снег не идёт (плавно стихает к югу)
		_snow.amount_ratio = 1.0 - smoothstep(snow_stop_from_z, snow_stop_to_z, player.global_position.z)
	_update_hud()


## Боты-курьеры (раньше тут были летающие дроны-помощники) — в test_tools.gd
func _add_bot() -> void:
	var tools := get_node_or_null("TestTools")
	if tools:
		tools.add_courier()


func _remove_bot() -> void:
	var tools := get_node_or_null("TestTools")
	if tools:
		tools.remove_courier()


@rpc("authority", "call_remote", "unreliable_ordered")
func _level_state(new_elapsed: float) -> void:
	elapsed = new_elapsed


func _update_hud() -> void:
	if player == null or objective_label == null:
		return
	objective_label.text = objective
	var ship := Vector3(SnowTerrain.CRASH_NOSE.x, 0.0, SnowTerrain.CRASH_NOSE.y)
	var p: Vector3 = player.global_position
	var dist := Vector2(p.x - ship.x, p.z - ship.z).length()
	if info_label:
		info_label.text = "Время экспедиции %s     До корабля: %d м     Поломок: %d" % [_format_time(elapsed), roundi(dist), deaths]


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
	if multiplayer.is_server():
		deaths += 1
		_deaths_sync.rpc(deaths)


@rpc("authority", "call_remote", "reliable")
func _deaths_sync(n: int) -> void:
	deaths = n


func _on_player_left(peer_id: int) -> void:
	if multiplayer.is_server():
		for p in get_tree().get_nodes_in_group("parcel"):
			p.server_remove_holder(peer_id)
	var node := get_node_or_null("Players/%d" % peer_id)
	if node:
		node.queue_free()
	show_banner("%s покинул игру" % Network.get_player_name(peer_id), "")


func _format_time(seconds: float) -> String:
	var s := int(seconds)
	return "%d:%02d" % [s / 60, s % 60]
