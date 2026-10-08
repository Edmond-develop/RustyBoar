extends Area3D
## Пункт выдачи. Решает хост: посылка засчитывается, если её внесли в круг
## (несут в руках или она лежит внутри и уже не катится).
## Заказ (группа "order") завершает уровень. Бонусный груз (группа "bonus")
## добавляет денег в чек и остаётся стоять на площадке.

signal delivered(parcel: Parcel)
signal bonus_delivered(parcel: Parcel)

@export var radius := 2.4
@export var waiting_color := Color(1.0, 0.75, 0.2)
@export var done_color := Color(0.3, 1.0, 0.45)

@onready var ring: MeshInstance3D = $Ring
@onready var beacon: MeshInstance3D = $Beacon
@onready var light: OmniLight3D = $Light
@onready var drop_point: Node3D = $DropPoint
@onready var confetti: GPUParticles3D = $Confetti

var is_done := false
var _time := 0.0
var _bonus_count := 0


func _ready() -> void:
	_set_color(waiting_color)


func _physics_process(delta: float) -> void:
	_time += delta
	if not is_done:
		light.light_energy = 1.5 + sin(_time * 3.0) * 0.5
	if not multiplayer.is_server() or is_done:
		return

	for node in get_tree().get_nodes_in_group("parcel"):
		var p := node as Parcel
		if p == null or p.is_delivered:
			continue
		if not (p.is_in_group("order") or p.is_in_group("bonus")):
			continue
		var flat := Vector2(p.global_position.x - global_position.x, p.global_position.z - global_position.z)
		if flat.length() > radius or absf(p.global_position.y - global_position.y) > 3.0:
			continue
		var ok := p.is_carried() or p.linear_velocity.length() < 1.5
		if not ok:
			continue
		if p.is_in_group("order"):
			p.server_deliver(Transform3D(Basis(), drop_point.global_position))
			_fx.rpc(true)
			delivered.emit(p)
			return
		else:
			var offset := Vector3(-1.3 + (_bonus_count % 3) * 1.3, 0.2, 1.3)
			_bonus_count += 1
			p.server_deliver(Transform3D(Basis(), drop_point.global_position + offset))
			_fx.rpc(false)
			bonus_delivered.emit(p)


@rpc("authority", "call_local", "reliable")
func _fx(is_order: bool) -> void:
	confetti.restart()
	if is_order:
		is_done = true
		_set_color(done_color)
		light.light_energy = 3.0


func _set_color(c: Color) -> void:
	var ring_mat := (ring.mesh as PrimitiveMesh).material as StandardMaterial3D
	ring_mat.albedo_color = c
	ring_mat.emission = c
	var beam_mat := (beacon.mesh as PrimitiveMesh).material as StandardMaterial3D
	beam_mat.albedo_color = Color(c.r, c.g, c.b, 0.25)
	beam_mat.emission = c
	light.light_color = c
