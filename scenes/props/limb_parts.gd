extends Node
## Все оторванные руки и ноги на уровне. Один узел «LimbParts» у каждого игрока по
## одному и тому же пути — через него идут команды по сети: появилась деталь, её подняли,
## бросили, прикрутили. Физику каждый считает у себя (это просто весёлый предмет).

const PART := preload("res://scenes/props/limb_part.gd")

var _counter := 0


static func get_manager(tree: SceneTree) -> Node:
	var scene := tree.current_scene
	if scene == null:
		return null
	var m := scene.get_node_or_null("LimbParts")
	if m == null:
		m = Node.new()
		m.set_script(load("res://scenes/props/limb_parts.gd"))
		m.name = "LimbParts"
		scene.add_child(m)
	return m


func _online() -> bool:
	return Network.in_game and Network.is_online()


func _call(method: String, args: Array) -> void:
	if _online():
		callv("rpc", [method] + args)
	else:
		callv(method, args)


## Деталь отлетела от хозяина (или сразу у кого-то в руке — оторвали)
func spawn(owner_id: int, kind: String, vel: Vector3, holder_id := 0) -> void:
	_counter += 1
	var id := "%d_%s_%d_%d" % [owner_id, kind, multiplayer.get_unique_id(), _counter]
	_call("_rpc_spawn", [id, owner_id, kind, vel, holder_id])


func pick(part: Node, holder_id: int) -> void:
	_call("_rpc_pick", [String(part.part_id), holder_id])


func release(part: Node, vel: Vector3) -> void:
	_call("_rpc_release", [String(part.part_id), (part as Node3D).global_transform, vel])


## Прикрутили — детали больше нет (она снова на хозяине)
func consume(part: Node) -> void:
	_call("_rpc_consume", [String(part.part_id)])


func find(id: String) -> Node:
	for p in get_tree().get_nodes_in_group("limb_part"):
		if p.part_id == id:
			return p
	return null


## Лежащая деталь этого хозяина (для ботов и подсказок)
func parts_of(owner_id: int) -> Array:
	var out := []
	for p in get_tree().get_nodes_in_group("limb_part"):
		if p.owner_id == owner_id:
			out.append(p)
	return out


@rpc("any_peer", "call_local", "reliable")
func _rpc_spawn(id: String, owner_id: int, kind: String, vel: Vector3, holder_id: int) -> void:
	var o = Network.find_player(owner_id)
	if o == null or o.suit == null:
		return
	var made: Array = o.suit.make_limb_visual(kind)
	var part := RigidBody3D.new()
	part.set_script(PART)
	part.name = "Limb_" + id
	add_child(part)
	part.part_id = id
	part.owner_id = owner_id
	part.kind = kind
	part.global_transform = (o.suit.socket_xform(kind) as Transform3D).orthonormalized()
	part.setup(made[0], made[1])
	part.linear_velocity = vel
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(id)
	part.angular_velocity = Vector3(rng.randf_range(-6, 6), rng.randf_range(-4, 4), rng.randf_range(-6, 6))
	part._home = o.global_position
	if holder_id != 0:
		_rpc_pick(id, holder_id)


@rpc("any_peer", "call_local", "reliable")
func _rpc_pick(id: String, holder_id: int) -> void:
	var part := find(id)
	var h = Network.find_player(holder_id)
	if part == null or h == null:
		return
	if part.holder != null and is_instance_valid(part.holder):
		part.holder.held_limb = null
	part.holder = h
	part.repair_target = null
	h.held_limb = part


@rpc("any_peer", "call_local", "reliable")
func _rpc_release(id: String, xform: Transform3D, vel: Vector3) -> void:
	var part := find(id)
	if part == null:
		return
	var thrower: Node3D = part.holder if part.holder != null and is_instance_valid(part.holder) else null
	if thrower != null and thrower.held_limb == part:
		thrower.held_limb = null
	part.holder = null
	part.repair_target = null
	if thrower is PhysicsBody3D:
		# только что лежала на плече (внутри капсулы бросающего) — не выталкиваться об него
		part.add_collision_exception_with(thrower)
		get_tree().create_timer(0.6).timeout.connect(func():
			if is_instance_valid(part) and is_instance_valid(thrower):
				part.remove_collision_exception_with(thrower))
	part.freeze = false
	part.global_transform = xform
	part.linear_velocity = vel
	part.angular_velocity = Vector3(randf_range(-8, 8), randf_range(-3, 3), randf_range(-8, 8))


@rpc("any_peer", "call_local", "reliable")
func _rpc_consume(id: String) -> void:
	var part := find(id)
	if part == null:
		return
	if part.holder != null and is_instance_valid(part.holder) and part.holder.held_limb == part:
		part.holder.held_limb = null
	part.queue_free()
