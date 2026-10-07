extends Area3D
## Пункт выдачи заказа. Принимает посылку из группы "order":
## дрон заходит с ней в руках, или посылка лежит внутри (например, её бросили).

signal delivered(parcel: Parcel)

@export var waiting_color := Color(1.0, 0.75, 0.2)
@export var done_color := Color(0.3, 1.0, 0.45)

@onready var ring: MeshInstance3D = $Ring
@onready var beacon: MeshInstance3D = $Beacon
@onready var light: OmniLight3D = $Light
@onready var drop_point: Node3D = $DropPoint
@onready var confetti: GPUParticles3D = $Confetti

var is_done := false
var _time := 0.0


func _ready() -> void:
	_set_color(waiting_color)


func _physics_process(delta: float) -> void:
	_time += delta
	if is_done:
		return
	# Маяк «дышит», пока ждёт заказ
	light.light_energy = 1.5 + sin(_time * 3.0) * 0.5

	for body in get_overlapping_bodies():
		var parcel: Parcel = null
		if body is Parcel:
			var p := body as Parcel
			if p.is_in_group("order") and not p.is_held and p.linear_velocity.length() < 1.5:
				parcel = p
		elif body.has_method("hand_over_parcel"):
			var held: Parcel = body.get_held_parcel()
			if held != null and held.is_in_group("order"):
				parcel = body.hand_over_parcel()
		if parcel != null:
			_complete(parcel)
			return


func _complete(parcel: Parcel) -> void:
	is_done = true
	if not parcel.is_held:
		parcel.pick_up()  # замораживаем — теперь она у получателя
	parcel.global_transform = Transform3D(Basis(), drop_point.global_position)
	_set_color(done_color)
	light.light_energy = 3.0
	confetti.restart()
	delivered.emit(parcel)


func _set_color(c: Color) -> void:
	var ring_mat := (ring.mesh as PrimitiveMesh).material as StandardMaterial3D
	ring_mat.albedo_color = c
	ring_mat.emission = c
	var beam_mat := (beacon.mesh as PrimitiveMesh).material as StandardMaterial3D
	beam_mat.albedo_color = Color(c.r, c.g, c.b, 0.25)
	beam_mat.emission = c
	light.light_color = c
