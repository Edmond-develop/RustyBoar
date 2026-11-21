extends Node3D
## Место у камина (подушка на ковре). E — сесть лицом к огню, E / любое движение — встать.
## Просто посидеть, для уюта. Сидит только один; посадка — у себя (позицию и «сижу» игрок рассылает сам).

const REACH := 1.15

var face := Vector3.FORWARD        ## куда смотреть сидя (на огонь)
var _label: Label3D
var _mine := false


func _ready() -> void:
	_label = Label3D.new()
	_label.font_size = 24
	_label.outline_size = 8
	_label.modulate = Color(1.0, 0.88, 0.6)
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.position.y = 0.75
	_label.text = "E — присесть у огня"
	_label.visible = false
	add_child(_label)


func _taken(me: Node) -> bool:
	for p in get_tree().get_nodes_in_group("player"):
		if p == me or not is_instance_valid(p):
			continue
		var d: Vector3 = p.global_position - global_position
		if Vector2(d.x, d.z).length() < 0.6 and absf(d.y) < 1.0:
			return true
	return false


func _process(_delta: float) -> void:
	var me = Network.local_player
	if me == null or not is_instance_valid(me):
		_label.visible = false
		return
	var d: Vector3 = me.global_position - global_position
	var near := Vector2(d.x, d.z).length() < REACH and absf(d.y) < 1.2
	if _mine and (not me.sitting or not near):
		_mine = false
	var taken := _taken(me)
	_label.visible = near and not me.sitting and not taken and not me.is_dead
	if not Input.is_action_just_pressed("interact"):
		return
	if _mine and me.sitting:
		me._stand_up()
		_mine = false
	elif _label.visible and me.held_parcel == null and me._can_sit():
		sit(me)


## Усадить игрока на это место лицом к огню
func sit(me: Node) -> void:
	me.global_position = global_position + Vector3(0, 0.06, 0)
	me.velocity = Vector3.ZERO
	var yaw := atan2(-face.x, -face.z)
	me.visual.rotation.y = yaw
	me.camera_pivot.rotation.y = yaw
	me._sit_down()
	_mine = true
	_label.visible = false
