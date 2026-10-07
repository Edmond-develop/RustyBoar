extends Node3D
## Лавинный склон.
##
## Сходит в двух случаях:
##  1. «Напряжение снега» дошло до максимума. Оно растёт от шума дрона на склоне:
##     бег, прыжки, удары, жёсткие приземления. Тихий ход почти не шумит.
##  2. По сценарию — один раз, когда дрон впервые доходит до середины склона.
##
## Перед лавиной 2.5 секунды гул, тряска и снежная пыль сверху.
## Спастись можно, убежав вдоль тропы или спрятавшись в укрытии под скалой
## (зоны из группы "avalanche_shelter").

@export_group("Зона склона")
@export var zone_z_max := 72.0
@export var zone_z_min := 8.0
@export var zone_x_min := -60.0
@export var zone_x_max := 20.0
@export var script_trigger_z := 40.0   ## Лавина «по сценарию», когда дрон впервые доходит сюда

@export_group("Лавина")
@export var start_x := -58.0           ## Откуда сходит (верх склона)
@export var end_x := 32.0              ## Где останавливается
@export var speed := 16.0
@export var width := 40.0              ## Ширина лавины вдоль тропы
@export var warning_time := 2.5
@export var cooldown := 15.0

@export_group("Шум")
@export var noise_sensitivity := 0.18  ## Как быстро шум раскачивает снег
@export var tension_decay := 0.03      ## Как быстро снег успокаивается

enum State { CALM, WARNING, SLIDING, COOLDOWN }

var state := State.CALM
var tension := 0.0

var _timer := 0.0
var _time := 0.0
var _scripted_done := false
var _front_x := 0.0
var _center_z := 0.0
var _hit_done := false
var _pushed: Array = []
var _player: Node3D
var _terrain: Node

var _front: Node3D
var _balls: Array[MeshInstance3D] = []
var _spray: GPUParticles3D
var _dust: GPUParticles3D
var _hud: CanvasLayer
var _hud_box: Control
var _bar: ProgressBar
var _warning_label: Label

const BALL_COUNT := 14


func _ready() -> void:
	_terrain = get_tree().get_first_node_in_group("terrain")
	_build_visuals()
	_build_hud()


func _physics_process(delta: float) -> void:
	_time += delta
	if _player == null:
		_player = get_tree().get_first_node_in_group("player")
		if _player == null:
			return

	var p := _player.global_position
	var inside := p.z < zone_z_max and p.z > zone_z_min and p.x > zone_x_min and p.x < zone_x_max

	match state:
		State.CALM:
			if inside and not _player.is_dead:
				tension += _player.get_noise() * noise_sensitivity * delta
			tension = maxf(tension - tension_decay * delta, 0.0)
			if inside and not _scripted_done and p.z < script_trigger_z:
				_scripted_done = true
				_start_warning(p.z)
			elif tension >= 1.0:
				_start_warning(p.z)
		State.WARNING:
			_timer -= delta
			_player.add_shake(0.03 + 0.08 * (1.0 - _timer / warning_time))
			if _timer <= 0.0:
				_start_slide()
		State.SLIDING:
			_front_x += speed * delta
			_update_front()
			_check_hits()
			var dist := absf(p.x - _front_x) + absf(p.z - _center_z) * 0.5
			_player.add_shake(clampf(0.3 - dist / 150.0, 0.03, 0.3))
			if _front_x > end_x:
				_finish()
		State.COOLDOWN:
			_timer -= delta
			if _timer <= 0.0:
				state = State.CALM

	_update_hud(inside)


func _start_warning(player_z: float) -> void:
	state = State.WARNING
	_timer = warning_time
	_center_z = clampf(player_z, zone_z_min + 8.0, zone_z_max - 8.0)
	_dust.global_position = Vector3(start_x + 6.0, _height(start_x + 6.0, _center_z) + 3.0, _center_z)
	_dust.emitting = true


func _start_slide() -> void:
	state = State.SLIDING
	_front_x = start_x
	_hit_done = false
	_pushed.clear()
	_front.visible = true
	_spray.emitting = true
	_dust.emitting = false


func _finish() -> void:
	state = State.COOLDOWN
	_timer = cooldown
	tension = 0.0
	_front.visible = false
	_spray.emitting = false


func _update_front() -> void:
	for i in _balls.size():
		var z := _center_z - width * 0.5 + i * (width / float(BALL_COUNT - 1))
		var x := _front_x + sin(_time * 3.0 + i * 1.7) * 0.9
		var ball := _balls[i]
		ball.global_position = Vector3(x, _height(x, z) + 1.4 + sin(_time * 5.0 + i) * 0.3, z)
		var s := 1.0 + sin(_time * 4.0 + i * 2.3) * 0.15
		ball.scale = Vector3(s, s * 0.8, s)
	_spray.global_position = Vector3(_front_x - 1.0, _height(_front_x, _center_z) + 2.0, _center_z)


func _check_hits() -> void:
	# Дрон
	if not _hit_done and not _player.is_dead:
		var p := _player.global_position
		var in_width := absf(p.z - _center_z) < width * 0.5 + 1.0
		var in_front := p.x < _front_x + 2.5 and p.x > _front_x - 8.0
		if in_width and in_front and not _is_sheltered():
			_hit_done = true
			_player.receive_avalanche(Vector3.RIGHT)

	# Посылки на земле — уносит
	for node in get_tree().get_nodes_in_group("parcel"):
		var parcel := node as Parcel
		if parcel == null or parcel.is_held or _pushed.has(parcel):
			continue
		var pp := parcel.global_position
		if absf(pp.z - _center_z) < width * 0.5 and pp.x < _front_x + 2.0 and pp.x > _front_x - 6.0:
			_pushed.append(parcel)
			parcel.linear_velocity = Vector3(speed * 0.7, 4.0, randf_range(-2.0, 2.0))


func _is_sheltered() -> bool:
	for s in get_tree().get_nodes_in_group("avalanche_shelter"):
		var area := s as Area3D
		if area and area.overlaps_body(_player):
			return true
	return false


func _height(x: float, z: float) -> float:
	return _terrain.height_at(x, z) if _terrain else 0.0


# ---------------------------------------------------------------------------
#  Внешний вид и интерфейс (создаются из кода)
# ---------------------------------------------------------------------------

func _build_visuals() -> void:
	_front = Node3D.new()
	_front.visible = false
	add_child(_front)

	var snow_mat := StandardMaterial3D.new()
	snow_mat.albedo_color = Color(0.93, 0.95, 1.0)
	snow_mat.roughness = 0.9
	for i in BALL_COUNT:
		var sphere := SphereMesh.new()
		sphere.radius = 3.2
		sphere.height = 6.4
		sphere.material = snow_mat
		var mi := MeshInstance3D.new()
		mi.mesh = sphere
		_front.add_child(mi)
		_balls.append(mi)

	_spray = FX.particles(Color(0.95, 0.97, 1.0, 0.8), 400, 1.4, 0.35, 4.0, 9.0,
		Vector3(0, -5, 0), 50.0, false)
	FX.set_box(_spray, Vector3(2.0, 2.0, width * 0.5))
	(_spray.process_material as ParticleProcessMaterial).direction = Vector3(0.6, 1.0, 0.0)
	add_child(_spray)

	_dust = FX.particles(Color(0.95, 0.97, 1.0, 0.7), 200, 2.0, 0.2, 0.5, 2.0,
		Vector3(3, -6, 0), 60.0, false)
	FX.set_box(_dust, Vector3(6.0, 1.0, width * 0.5))
	add_child(_dust)


func _build_hud() -> void:
	_hud = CanvasLayer.new()
	add_child(_hud)

	var box := VBoxContainer.new()
	box.position = Vector2(20, 140)
	box.custom_minimum_size = Vector2(260, 0)
	_hud.add_child(box)
	_hud_box = box

	var caption := Label.new()
	caption.text = "Напряжение снега"
	caption.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	caption.add_theme_constant_override("outline_size", 6)
	box.add_child(caption)

	_bar = ProgressBar.new()
	_bar.max_value = 1.0
	_bar.step = 0.001
	_bar.show_percentage = false
	_bar.custom_minimum_size = Vector2(260, 14)
	box.add_child(_bar)

	var hint := Label.new()
	hint.text = "Бег, прыжки и удары тревожат снег"
	hint.add_theme_font_size_override("font_size", 12)
	hint.modulate = Color(1, 1, 1, 0.7)
	box.add_child(hint)

	_warning_label = Label.new()
	_warning_label.text = "ЛАВИНА!"
	_warning_label.add_theme_font_size_override("font_size", 64)
	_warning_label.add_theme_color_override("font_color", Color(1, 0.3, 0.25))
	_warning_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_warning_label.add_theme_constant_override("outline_size", 14)
	_warning_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_warning_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_warning_label.offset_left = -220.0
	_warning_label.offset_right = 220.0
	_warning_label.offset_top = 110.0
	_warning_label.offset_bottom = 200.0
	_warning_label.visible = false
	_hud.add_child(_warning_label)


func _update_hud(inside: bool) -> void:
	_hud_box.visible = inside and state == State.CALM
	_bar.value = tension
	_bar.modulate = Color(0.6, 0.85, 1.0).lerp(Color(1, 0.3, 0.25), tension)
	var alarm := state == State.WARNING or state == State.SLIDING
	_warning_label.visible = alarm and fmod(_time, 0.4) < 0.28
