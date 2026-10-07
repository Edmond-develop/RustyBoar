extends Node3D
## Ставит объект точно на поверхность рельефа при запуске.
## Удобно для укрытий, маяков и камней: не нужно знать высоту заранее.

@export var height_offset := 0.0


func _ready() -> void:
	var terrain := get_tree().get_first_node_in_group("terrain")
	if terrain:
		global_position.y = terrain.height_at(global_position.x, global_position.z) + height_offset
