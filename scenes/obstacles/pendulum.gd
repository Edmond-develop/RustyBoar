extends Node3D
## Качающийся маятник. Тяжёлый шар на штанге сбивает дрона с ног.
## Swing — физическое тело, которое вращается вокруг точки подвеса.

@export var amplitude_deg := 50.0   ## Насколько далеко раскачивается
@export var period := 2.6           ## Секунд на полный цикл туда-обратно
@export_range(0.0, 1.0) var phase := 0.0  ## Сдвиг, чтобы маятники качались вразнобой
@export var hit_strength := 1.0     ## Множитель силы удара

@onready var swing: AnimatableBody3D = $Swing
@onready var head: Node3D = $Swing/Head
@onready var hit_area: Area3D = $Swing/HitArea

var _t := 0.0
var _prev_head := Vector3.ZERO
var _head_velocity := Vector3.ZERO


func _ready() -> void:
	_t = phase * period
	swing.rotation.z = deg_to_rad(amplitude_deg) * sin(_t * TAU / period)
	_prev_head = head.global_position
	hit_area.body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	_t += delta
	swing.rotation.z = deg_to_rad(amplitude_deg) * sin(_t * TAU / period)
	var p := head.global_position
	_head_velocity = (p - _prev_head) / delta
	_prev_head = p


func _on_body_entered(body: Node3D) -> void:
	if not body.has_method("receive_hit"):
		return
	var dir := _head_velocity
	dir.y = 0.0
	if dir.length() < 0.5:
		dir = body.global_position - head.global_position
		dir.y = 0.0
	var strength := maxf(_head_velocity.length(), 3.0) * hit_strength
	body.receive_hit(dir.normalized(), strength, head.global_position)
