extends Node
## Сеть: создание игры (хост), подключение по IP, лобби, запуск уровня.
## Хост — главный: он считает физику посылок, лавины, лёд и сдачу заказа.
## Каждый игрок сам управляет своим дроном и рассылает его положение остальным.

signal players_changed
signal connection_failed(reason: String)
signal joined_lobby
signal player_left(peer_id: int)
signal game_started

const DEFAULT_PORT := 24567
const MAX_PLAYERS := 4
const COLORS := [
	Color(0.86, 0.45, 0.17),   # оранжевый
	Color(0.2, 0.62, 0.78),    # бирюзовый
	Color(0.62, 0.4, 0.86),    # фиолетовый
	Color(0.45, 0.76, 0.3),    # зелёный
]
const MENU_SCENE := "res://scenes/ui/main_menu.tscn"

var level_scene := "res://scenes/levels/borea.tscn"
var players := {}            ## peer_id -> {"name": String, "color": int}
var local_name := "Курьер"
var in_game := false         ## Уровень загружен у всех — можно рассылать состояние
var game_running := false    ## Идёт игра (новых игроков не пускаем)
var local_player: Node = null
var last_message := ""       ## Сообщение для меню (например, «хост отключился»)

var _ready_peers: Array = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


# ---------------------------------------------------------------------------
#  Создание / подключение / выход
# ---------------------------------------------------------------------------

func host(port: int = DEFAULT_PORT) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_PLAYERS - 1)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	players = {1: {"name": local_name, "color": 0}}
	game_running = false
	players_changed.emit()
	return OK


func join(ip: String, port: int = DEFAULT_PORT) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, port)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	return OK


## Игра без сети (один игрок).
func play_offline() -> void:
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	players = {1: {"name": local_name, "color": 0}}
	start_game()


## Если уровень запущен напрямую (F6) — создаём одиночную «сессию».
func ensure_players() -> void:
	if players.is_empty():
		players = {multiplayer.get_unique_id(): {"name": local_name, "color": 0}}


func leave_to_menu(message: String = "") -> void:
	last_message = message
	multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	players.clear()
	in_game = false
	game_running = false
	local_player = null
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file(MENU_SCENE)


func is_online() -> bool:
	return not multiplayer.get_peers().is_empty()


func find_player(peer_id: int) -> Node:
	for p in get_tree().get_nodes_in_group("player"):
		if p.peer_id == peer_id:
			return p
	return null


func get_player_name(peer_id: int) -> String:
	var info: Dictionary = players.get(peer_id, {})
	return info.get("name", "Курьер")


# ---------------------------------------------------------------------------
#  Запуск уровня (только хост)
# ---------------------------------------------------------------------------

func start_game() -> void:
	if not multiplayer.is_server():
		return
	game_running = true
	_load_level.rpc()


func restart_level() -> void:
	start_game()


@rpc("authority", "call_local", "reliable")
func _load_level() -> void:
	in_game = false
	_ready_peers.clear()
	local_player = null
	get_tree().paused = false
	get_tree().change_scene_to_file(level_scene)


## Уровень сообщает, что загрузился у этого игрока.
func report_level_ready() -> void:
	_peer_ready.rpc_id(1, multiplayer.get_unique_id())


@rpc("any_peer", "call_local", "reliable")
func _peer_ready(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	if not _ready_peers.has(peer_id):
		_ready_peers.append(peer_id)
	_check_all_ready()


func _check_all_ready() -> void:
	for id in players:
		if not _ready_peers.has(id):
			return
	_all_ready.rpc()


@rpc("authority", "call_local", "reliable")
func _all_ready() -> void:
	in_game = true
	game_started.emit()


# ---------------------------------------------------------------------------
#  Лобби
# ---------------------------------------------------------------------------

func _on_connected_to_server() -> void:
	_register.rpc_id(1, local_name)


@rpc("any_peer", "reliable")
func _register(player_name: String) -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	if game_running or players.size() >= MAX_PLAYERS:
		_rejected.rpc_id(id, "Игра уже идёт или лобби заполнено")
		return
	var used := []
	for p in players.values():
		used.append(p["color"])
	var color := 0
	while used.has(color):
		color += 1
	players[id] = {"name": player_name.substr(0, 16), "color": color}
	_sync_players.rpc(players)


@rpc("authority", "reliable")
func _rejected(reason: String) -> void:
	leave_to_menu(reason)


@rpc("authority", "call_local", "reliable")
func _sync_players(new_players: Dictionary) -> void:
	var first := players.is_empty()
	players = new_players
	players_changed.emit()
	if first and not multiplayer.is_server():
		joined_lobby.emit()


func _on_peer_connected(_id: int) -> void:
	pass


func _on_peer_disconnected(id: int) -> void:
	if players.has(id):
		players.erase(id)
		players_changed.emit()
	player_left.emit(id)
	if multiplayer.is_server():
		_sync_players.rpc(players)
		_check_all_ready()


func _on_connection_failed() -> void:
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	connection_failed.emit("Не удалось подключиться. Проверь IP и что хост создал игру.")


func _on_server_disconnected() -> void:
	leave_to_menu("Хост отключился")
