extends AnimatableBody3D
## Тело, которое ездит туда-обратно: толкатель или платформа.
## Если внутри есть узел HitArea и hit_strength > 0 — сбивает дрона.

@export var travel := Vector3(0, 0, 4)  ## Куда и насколько далеко едет
@export var period := 3.0               ## Секунд на полный цикл туда-обратно
@export_range(0.0, 1.0) var phase := 0.0
@export var hit_strength := 1.0         ## 0 — не сбивает (обычная платформа)

var _start := Vector3.ZERO
var _t := 0.0
var _prev := Vector3.ZERO
var _move_velocity := Vector3.ZERO

@onready var hit_area: Area3D = get_node_or_null("HitArea")


func _ready() -> void:
	_start = position
	_t = phase * period
	position = _start + travel * _progress()
	_prev = global_position
	if hit_area:
		hit_area.body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	_t += delta
	position = _start + travel * _progress()
	_move_velocity = (global_position - _prev) / delta
	_prev = global_position


## Плавно 0 → 1 → 0 (замедляется у краёв)
func _progress() -> float:
	return 0.5 - 0.5 * cos(_t * TAU / period)


func _on_body_entered(body: Node3D) -> void:
	if hit_strength <= 0.0 or not body.has_method("receive_hit"):
		return
	var speed := _move_velocity.length()
	if speed < 0.5:
		return
	var dir := _move_velocity
	dir.y = 0.0
	body.receive_hit(dir.normalized(), speed * hit_strength, global_position)
