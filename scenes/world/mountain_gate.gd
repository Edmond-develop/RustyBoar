extends Node3D
## Шаг 73: «ворота» для ботов (группа coop_gate) — стоят там, где испытание, и передают вопросы бота
## модулю горы (mod.bot_target / mod.bot_crank / mod.is_open). Нужны, потому что сам модуль — в начале координат,
## а courier_brain смотрит, далеко ли ворота от хозяина.

var mod: Node
var is_open: bool:
	get:
		return mod == null or bool(mod.get("is_open"))


func bot_target(bot: Node3D, owner_node: Node3D) -> Vector3:
	return mod.bot_target(bot, owner_node)


func bot_crank(bot: Node3D, owner_node: Node3D) -> bool:
	return mod.bot_crank(bot, owner_node)


static func make(m: Node, at: Vector3) -> Node3D:
	var g := Node3D.new()
	g.set_script(load("res://scenes/world/mountain_gate.gd"))
	g.set("mod", m)
	g.add_to_group("coop_gate")
	m.add_child(g)
	g.global_position = at
	return g
