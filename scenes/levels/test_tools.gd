extends Node
## ВРЕМЕННЫЕ инструменты для проверки (создаёт level.gd):
##  * «=» — перенестись в следующую локацию, Shift + «=» — в предыдущую;
##  * B — панель ботов-курьеров: позвать/отпустить, выбрать бота, команды;
##  * «+» (цифровая клавиатура) — позвать бота, «−» — отпустить (только хост);
##  * 1–9 — команды выбранному боту (см. courier_brain.gd);
##  * G — переселиться в бота и управлять им (ещё раз — в следующего, потом обратно в себя);
##  * тестовая площадка у места крушения: лёгкая, обычная и тяжёлая посылки
##    и ящик «вдвоём» — чтобы сразу проверить, как их держат.

const PLAYER := preload("res://scenes/player/player.tscn")
const BRAIN := preload("res://scenes/bots/courier_brain.gd")
const PARCEL := preload("res://scenes/props/parcel.tscn")
const HEAVY := preload("res://scenes/props/heavy_parcel.tscn")
const MAX_COURIERS := 3
const YARD := Vector3(8.0, 0.0, 1070.0)    ## тестовая площадка (x, -, z)

## [название, x, z]
const LOCATIONS := [
	["Место крушения", 8.0, 1084.0],
	["Тестовая площадка: грузы", 8.0, 1075.0],
	["Борея — лагерь", 0.0, 935.0],
	["Каток", -75.0, 858.0],
	["Большая горка", 158.0, 892.0],
	["Ледяное озеро", 0.0, 905.0],
	["Ледяной лабиринт — вход", 0.0, 768.0],
	["Ледяной вал — луч маяка", 10.0, 550.0],
	["Разломы", 0.0, 512.0],
	["Вмёрзший корабль", 0.0, 382.0],
	["Полыньи", 0.0, 346.0],
	["Хрустальный лес", 0.0, 281.0],
	["Ледяные холмы", 0.0, 236.0],
	["Гейзеры, ветер и вихри", 0.0, 192.0],
	["Последний рубеж", 0.0, 136.0],
	["Лавинный склон", 0.0, 75.0],
	["Трещины", 0.0, 3.0],
	["Плато бурь", 0.0, -43.0],
	["Ледяная пещера", 0.0, -110.0],
	["Замёрзшее озеро", 0.0, -151.0],
	["Станция «Борея-7»", 0.0, -193.0],
]
const BOT_PANEL := preload("res://scenes/ui/bot_panel.gd")
const COMMANDS := ["follow", "stay", "come", "goto", "carry", "water", "throw", "faint", "freeze"]
const COMMAND_NAMES := ["За мной", "Стой тут", "Иди ко мне", "Иди туда, куда смотрю", "Помоги нести", "Прыгай в полынью", "Подними меня и кинь", "Без сил (обмякни)", "Замёрзни в глыбу"]

var level: Node
var selected := 1                ## номер выбранного бота (для команд)
var panel: CanvasLayer
var _home: Node3D = null         ## свой дрон (куда возвращаемся из бота)
var _loc := 0
var _help: Label


func _ready() -> void:
	_build_yard.call_deferred()
	_help = Label.new()
	_help.name = "HelpText"
	_help.add_theme_font_size_override("font_size", 15)
	_help.add_theme_color_override("font_color", Color(0.85, 0.95, 1.0))
	_help.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_help.add_theme_constant_override("outline_size", 5)
	_help.position = Vector2(16, 150)
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	layer.add_child(_help)
	panel = CanvasLayer.new()
	panel.set_script(BOT_PANEL)
	panel.set("tools", self)
	add_child(panel)
	_update_help()


# ---------------------------------------------------------------------------
#  Тестовая площадка с грузами (одинаково у всех игроков)
# ---------------------------------------------------------------------------
func _build_yard() -> void:
	var root := get_tree().current_scene
	if root == null:
		return
	var terrain := get_tree().get_first_node_in_group("terrain")
	var yard := Node3D.new()
	yard.name = "TestYard"
	root.add_child(yard)
	var items := [
		["TestLight", "Лёгкая посылка", 0.34, 1, 1, 120, Vector3(-4.5, 0, 0)],
		["TestNormal", "Посылка", 0.6, 2, 1, 250, Vector3(-1.5, 0, 0)],
		["TestHeavy", "Тяжёлый ящик", 0.8, 3, 1, 400, Vector3(1.8, 0, 0)],
	]
	for it in items:
		var p: Parcel = PARCEL.instantiate()
		p.name = it[0]
		p.display_name = it[1]
		p.weight = it[3]
		p.required_carriers = it[4]
		p.base_price = it[5]
		_resize(p, it[2])
		var pos: Vector3 = YARD + it[6]
		pos.y = (terrain.height_at(pos.x, pos.z) if terrain else 0.0) + it[2] * 0.5 + 0.3
		p.position = pos
		p.mass = 3.0 + it[2] * 20.0
		yard.add_child(p)
	var h: Parcel = HEAVY.instantiate()
	h.name = "TestDuo"
	var hp := YARD + Vector3(6.0, 0, 0.5)
	hp.y = (terrain.height_at(hp.x, hp.z) if terrain else 0.0) + 0.7
	h.position = hp
	h.rotation.y = 0.3
	yard.add_child(h)
	# табличка
	var sign := Label3D.new()
	sign.text = "ТЕСТОВАЯ ПЛОЩАДКА\nлёгкая · обычная · тяжёлая · вдвоём"
	sign.font_size = 48
	sign.pixel_size = 0.004
	sign.outline_size = 12
	sign.modulate = Color(1.0, 0.85, 0.5)
	sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	var sp := YARD + Vector3(0.5, 0, -2.5)
	sp.y = (terrain.height_at(sp.x, sp.z) if terrain else 0.0) + 3.2
	sign.position = sp
	yard.add_child(sign)


## Сделать посылку другого размера (свои копии формы и сеток)
func _resize(p: Parcel, size: float) -> void:
	var k := size / 0.6
	for c in p.get_children():
		if c is CollisionShape3D:
			var b := BoxShape3D.new()
			b.size = Vector3.ONE * size
			(c as CollisionShape3D).shape = b
		elif c is MeshInstance3D and (c as MeshInstance3D).mesh is BoxMesh:
			var m: BoxMesh = ((c as MeshInstance3D).mesh as BoxMesh).duplicate()
			m.size = m.size * k
			(c as MeshInstance3D).mesh = m
	p.label_height = p.label_height * k


# ---------------------------------------------------------------------------
#  Клавиши
# ---------------------------------------------------------------------------
func _unhandled_input(event: InputEvent) -> void:
	var me = Network.local_player
	if me == null or me.input_blocked:
		return
	if _home == null and not me.is_bot:
		_home = me
	if event.is_action_pressed("teleport"):
		var back: bool = event is InputEventKey and (event as InputEventKey).shift_pressed
		_loc = posmod(_loc + (-1 if back else 1), LOCATIONS.size())
		_teleport(me, _loc)
	elif event.is_action_pressed("bot_add"):
		add_courier()
	elif event.is_action_pressed("bot_remove"):
		remove_courier()
	elif event.is_action_pressed("bot_panel"):
		panel.call("toggle")
	elif event.is_action_pressed("possess"):
		possess_next()
	else:
		for i in COMMANDS.size():
			if event.is_action_pressed("cmd_%d" % (i + 1)):
				command(i)
				break


func _teleport(me: Node3D, i: int) -> void:
	var l: Array = LOCATIONS[i]
	var pos := _ground(Vector3(l[1], 0.0, l[2]))
	me.teleport_to(pos)
	for b in _couriers():
		if b == me:
			continue
		var brain = b.get_node("Brain")
		if brain.command in ["follow", "carry", "throw", "water", "come", "stay", "goto"]:
			brain.set_command("follow")
			b.teleport_to(_ground(pos + Vector3(3.5 + float(brain.index) * 1.5, 0, 3.0)))
	if _home and _home != me:
		_home.teleport_to(_ground(pos + Vector3(-3.0, 0, 2.0)))
	if level and level.has_method("show_banner"):
		level.show_banner("%d/%d · %s" % [i + 1, LOCATIONS.size(), l[0]], "«=» — дальше,  Shift + «=» — назад")


## Точка на земле (луч сверху), не в полынье
func _ground(p: Vector3) -> Vector3:
	var lake := get_tree().get_first_node_in_group("ice_lake")
	if lake:
		for k in 40:
			if not lake.is_hole(p.x, p.z, 2.0):
				break
			p.x += 1.5
	var space := get_viewport().get_world_3d().direct_space_state
	var ex: Array[RID] = []
	for d in get_tree().get_nodes_in_group("player"):
		if d is CollisionObject3D:
			ex.append((d as CollisionObject3D).get_rid())
	var q := PhysicsRayQueryParameters3D.create(Vector3(p.x, 400.0, p.z), Vector3(p.x, -200.0, p.z), 1)
	q.exclude = ex
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return Vector3(p.x, 5.0, p.z)
	return (hit["position"] as Vector3) + Vector3.UP * 0.4


# ---------------------------------------------------------------------------
#  Боты-курьеры
# ---------------------------------------------------------------------------
func _couriers() -> Array:
	var out := []
	for d in get_tree().get_nodes_in_group("player"):
		if d.get("is_bot") and d.has_node("Brain"):
			out.append(d)
	out.sort_custom(func(a, b): return int(a.get_node("Brain").index) < int(b.get_node("Brain").index))
	return out


func courier(idx: int) -> Node3D:
	for b in _couriers():
		if int(b.get_node("Brain").index) == idx:
			return b
	return null


## Совместимость со старыми тестами
func _add_courier(_me: Node3D = null) -> void:
	add_courier()


func _remove_courier() -> void:
	remove_courier()


func add_courier() -> void:
	var me: Node3D = _home if _home else Network.local_player
	if me == null:
		return
	if not multiplayer.is_server():
		level.show_banner("Боты-курьеры", "Звать ботов может только хост")
		return
	var list := _couriers()
	if list.size() >= MAX_COURIERS:
		level.show_banner("Ботов хватит", "Больше %d курьеров не бывает.  «−» — отпустить" % MAX_COURIERS)
		return
	var used := {}
	for b in list:
		used[int(b.get_node("Brain").index)] = true
	var idx := 1
	while used.has(idx):
		idx += 1
	var ctl: Node3D = Network.local_player
	var b: CharacterBody3D = PLAYER.instantiate()
	b.name = "Courier%d" % idx
	b.set_meta("bot_id", 1000 + idx)
	b.set_meta("bot_name", "Бот %d" % idx)
	b.set_meta("bot_color", idx % 4)
	var right: Vector3 = ctl.get("visual").global_basis.x
	b.position = _ground(ctl.global_position + right * (1.8 + idx * 1.2))
	me.get_parent().add_child(b)
	var brain := Node.new()
	brain.set_script(BRAIN)
	brain.name = "Brain"
	brain.set("index", idx)
	b.add_child(brain)
	if _couriers().size() == 1:
		selected = idx
	level.show_banner("Бот-курьер %d прибыл" % idx, "B — панель ботов: команды и управление.  G — переселиться в бота")
	_update_help()
	if panel:
		panel.call("refresh")


func remove_courier() -> void:
	var list := _couriers()
	if list.is_empty():
		return
	var last: Node = courier(selected) if courier(selected) else list.back()
	if last == Network.local_player and _home:
		_switch_to(_home)
	for p in get_tree().get_nodes_in_group("parcel"):
		if (p as Parcel).holders.has(last.get("peer_id")):
			(p as Parcel).server_remove_holder(last.get("peer_id"))
	for d in get_tree().get_nodes_in_group("player"):
		if d.get("held_friend") == last:
			d.set("held_friend", null)
		if d.get("carried_by") == last:
			d.set("carried_by", null)
	last.queue_free()
	await get_tree().process_frame
	var rest := _couriers()
	if not rest.is_empty():
		selected = int(rest[0].get_node("Brain").index)
	_update_help()
	if panel:
		panel.call("refresh")


func command(i: int, idx := -1) -> void:
	if idx < 0:
		idx = selected
	var b := courier(idx)
	if b == null:
		var list := _couriers()
		if list.is_empty():
			level.show_banner("Ботов нет", "«+» на цифровой клавиатуре или B — позвать бота")
			return
		b = list[0]
	if b == Network.local_player:
		level.show_banner("Ты сейчас в этом боте", "G — вернуться в себя или в другого бота")
		return
	var point := Vector3.INF
	var me: Node3D = Network.local_player
	if COMMANDS[i] == "goto":
		var cam: Camera3D = me.get("camera")
		var space := get_viewport().get_world_3d().direct_space_state
		var from := cam.global_position
		var q := PhysicsRayQueryParameters3D.create(from, from - cam.global_basis.z * 60.0, 1)
		var ex: Array[RID] = []
		for d in get_tree().get_nodes_in_group("player"):
			ex.append((d as CollisionObject3D).get_rid())
		q.exclude = ex
		var hit := space.intersect_ray(q)
		point = (hit["position"] as Vector3) if not hit.is_empty() else from - cam.global_basis.z * 20.0
	b.get_node("Brain").set_command(COMMANDS[i], point)
	level.show_banner("%s: %s" % [b.get("player_name"), COMMAND_NAMES[i]], "")


## G: я → бот 1 → бот 2 → … → снова я
func possess_next() -> void:
	var cur: Node3D = Network.local_player
	if _home == null and cur and not cur.get("is_bot"):
		_home = cur
	var order: Array = [_home] + _couriers()
	if order.size() < 2:
		level.show_banner("Некуда переселяться", "Сначала позови бота: «+» или B")
		return
	var i := order.find(cur)
	_switch_to(order[(i + 1) % order.size()])


func possess(target: Node3D) -> void:
	if target and target != Network.local_player:
		_switch_to(target)


func _switch_to(target: Node3D) -> void:
	var cur: Node3D = Network.local_player
	if cur == target or target == null:
		return
	var cam_yaw: float = cur.camera_pivot.rotation.y
	cur.set_controlled(false)
	if cur.get("is_bot") and cur.has_node("Brain"):
		cur.get_node("Brain").call("on_released")
	target.set_controlled(true)
	target.camera_pivot.rotation.y = cam_yaw
	if _home and _home.get("inventory_ui"):
		_home.inventory_ui.set("player", target)
	if level:
		level.set("player", target)
	if target.get("is_bot"):
		selected = int(target.get_node("Brain").index)
		level.show_banner("Ты — %s" % target.get("player_name"), "Управляешь ботом.  G — дальше / вернуться в себя")
	else:
		level.show_banner("Ты снова в своём скафандре", "G — переселиться в бота")
	_update_help()


func _update_help() -> void:
	if _help == null:
		return
	var t := "«=» — следующая локация (Shift — назад)   I — инвентарь"
	if multiplayer.is_server():
		t += "\nB — панель ботов   «+»/«−» — позвать/отпустить   G — переселиться в бота"
		if not _couriers().is_empty():
			t += "\n1 за мной · 2 стой · 3 ко мне · 4 туда · 5 нести · 6 в полынью · 7 кинь меня · 8 без сил · 9 замёрзни"
	_help.text = t
