extends Node
## ВРЕМЕННЫЕ инструменты для проверки (создаёт level.gd):
##  * «=» — перенестись в следующую локацию, Shift + «=» — в предыдущую;
##  * B — позвать бота-курьера (до 3), N — отпустить последнего (только хост);
##  * 1–6 — команды ботам-курьерам (см. courier_brain.gd);
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
const COMMANDS := ["follow", "stay", "carry", "water", "throw", "goto"]
const COMMAND_NAMES := ["За мной", "Стой тут", "Помоги нести", "Прыгай в полынью", "Подними меня и кинь", "Иди туда, куда смотрю"]

var level: Node
var _loc := 0
var _help: Label


func _ready() -> void:
	_build_yard.call_deferred()
	_help = Label.new()
	_help.add_theme_font_size_override("font_size", 15)
	_help.add_theme_color_override("font_color", Color(0.85, 0.95, 1.0))
	_help.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_help.add_theme_constant_override("outline_size", 5)
	_help.position = Vector2(16, 150)
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	layer.add_child(_help)
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
	if event.is_action_pressed("teleport"):
		var back: bool = event is InputEventKey and (event as InputEventKey).shift_pressed
		_loc = posmod(_loc + (-1 if back else 1), LOCATIONS.size())
		_teleport(me, _loc)
	elif event.is_action_pressed("courier_add"):
		_add_courier(me)
	elif event.is_action_pressed("courier_remove"):
		_remove_courier()
	else:
		for i in COMMANDS.size():
			if event.is_action_pressed("cmd_%d" % (i + 1)):
				_command(me, i)
				break


func _teleport(me: Node3D, i: int) -> void:
	var l: Array = LOCATIONS[i]
	var pos := _ground(Vector3(l[1], 0.0, l[2]))
	me.teleport_to(pos)
	if me.get("rope") and me.rope.state != me.rope.S.NONE:
		me.rope._detach()
	for b in _couriers():
		var brain = b.get_node("Brain")
		if brain.command in ["follow", "carry", "throw", "water"]:
			brain.set_command("follow")
			b.teleport_to(_ground(pos + Vector3(3.5 + float(brain.index) * 1.5, 0, 3.0)))
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
	return out


func _add_courier(me: Node3D) -> void:
	if not multiplayer.is_server():
		level.show_banner("Боты-курьеры", "Звать ботов может только хост")
		return
	var list := _couriers()
	if list.size() >= MAX_COURIERS:
		level.show_banner("Ботов хватит", "Больше %d курьеров не бывает.  N — отпустить" % MAX_COURIERS)
		return
	var used := {}
	for b in list:
		used[int(b.get_node("Brain").index)] = true
	var idx := 1
	while used.has(idx):
		idx += 1
	var b: CharacterBody3D = PLAYER.instantiate()
	b.name = "Courier%d" % idx
	b.set_meta("bot_id", 1000 + idx)
	b.set_meta("bot_name", "Бот %d" % idx)
	b.set_meta("bot_color", idx % 4)
	var right: Vector3 = me.get("visual").global_basis.x
	b.position = _ground(me.global_position + right * (1.8 + idx * 1.2))
	var parent := me.get_parent()
	parent.add_child(b)
	var brain := Node.new()
	brain.set_script(BRAIN)
	brain.name = "Brain"
	brain.set("index", idx)
	b.add_child(brain)
	level.show_banner("Бот-курьер %d прибыл" % idx, "1 за мной · 2 стой · 3 помоги нести · 4 в полынью · 5 кинь меня · 6 иди туда.  N — отпустить")
	_update_help()


func _remove_courier() -> void:
	var list := _couriers()
	if list.is_empty():
		return
	var last: Node = list[0]
	for b in list:
		if int(b.get_node("Brain").index) > int(last.get_node("Brain").index):
			last = b
	for p in get_tree().get_nodes_in_group("parcel"):
		if (p as Parcel).holders.has(last.get("peer_id")):
			(p as Parcel).server_remove_holder(last.get("peer_id"))
	for d in get_tree().get_nodes_in_group("player"):
		if d.get("held_friend") == last or d.get("carried_by") == last:
			d.set("held_friend", null)
			d.set("carried_by", null)
	last.queue_free()
	_update_help.call_deferred()


func _command(me: Node3D, i: int) -> void:
	var list := _couriers()
	if list.is_empty():
		return
	var point := Vector3.INF
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
	for b in list:
		b.get_node("Brain").set_command(COMMANDS[i], point)
		if COMMANDS[i] in ["throw", "water"]:
			break      # кидать и нырять — хватит одного бота
	level.show_banner("Команда ботам: %s" % COMMAND_NAMES[i], "")


func _update_help() -> void:
	if _help == null:
		return
	var t := "«=» — следующая локация (Shift — назад)   I — инвентарь"
	if multiplayer.is_server():
		t += "\nB — позвать бота-курьера, N — отпустить"
		if not _couriers().is_empty():
			t += "\nКоманды: 1 за мной · 2 стой · 3 помоги нести · 4 в полынью · 5 кинь меня · 6 иди туда"
	_help.text = t
