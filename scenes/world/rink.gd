extends Node3D
## Каток — первые ~150 м ледяного озера (z 912 … 768), всё для развлечения:
##  * лёд здесь толстый — не трескается и не проваливается (см. IceRiver.TOROS_Z);
##  * лёд катка особый (метка "skate" на полу): разгоняешься не спеша, а без кнопок
##    катишься очень долго; на коньках можно разогнаться быстрее обычного
##    (настройки skate_* в player.gd);
##  * большая ледяная горка с извилистым жёлобом (big_slide.gd) — забрался по снегу,
##    съехал с ветерком и долго катишься по катку;
##  * хоккей дронов: клюшки на стойке, шайба, ведение и бросок (hockey.gd).
## Всё одинаково у всех игроков.

const SLIDE := preload("res://scenes/world/big_slide.gd")
const HOCKEY := preload("res://scenes/world/hockey.gd")

@export var rink_grip := 0.02          ## Трение льда катка (для предметов: шайба, мяч)
@export var z_north := 768.0
@export var z_south := 913.0

var _y := 0.0


func _ready() -> void:
	_y = IceRiver.river_y(840.0)
	_rink_floor()
	var slide := Node3D.new()
	slide.set_script(SLIDE)
	slide.name = "BigSlide"
	add_child(slide)
	var hockey := Node3D.new()
	hockey.set_script(HOCKEY)
	hockey.name = "Hockey"
	add_child(hockey)


## Пол катка поверх льда озера: даёт метку "skate" (особое скольжение) и гладкое трение
func _rink_floor() -> void:
	var body := StaticBody3D.new()
	body.name = "RinkFloor"
	body.add_to_group("safe_ground")
	body.set_meta("skate", true)
	var pm := PhysicsMaterial.new()
	pm.friction = rink_grip
	body.physics_material_override = pm
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(IceRiver.LAKE_HALF * 2.0 - 2.0, 0.2, z_south - z_north)
	col.shape = box
	body.position = Vector3(0.0, _y - 0.07, (z_north + z_south) * 0.5)
	body.add_child(col)
	add_child(body)


func _sign(text: String, pos: Vector3, col: Color, size: int) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.outline_size = 12
	l.modulate = col
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.position = pos
	add_child(l)
	return l
