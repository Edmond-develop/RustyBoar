extends Node3D
## Порывы ветра над всей шириной озера (участок «Гейзеры и ветер»).
## Перед порывом — предупреждение со стрелкой. Ветер сносит дрона (к полыньям!)
## и раскачивает посылку. Направление и время порывов одинаковы у всех игроков.

@export var z_max := 157.0
@export var z_min := 122.0
@export var half_width := 150.0
@export var strength := 6.5
@export var period := 7.0
@export var warning_time := 1.2
@export var gust_time := 2.4

var _local_t := 0.0
var _snow: GPUParticles3D
var _label: Label


func _ready() -> void:
	_snow = FX.particles(Color(1, 1, 1, 0.85), 700, 1.2, 0.04, 14.0, 20.0, Vector3(0, -1, 0), 6.0, false)
	FX.set_box(_snow, Vector3(2.0, 3.0, 18.0))
	_snow.top_level = true
	add_child(_snow)

	var hud := CanvasLayer.new()
	add_child(hud)
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 34)
	_label.add_theme_color_override("font_color", Color(1, 0.85, 0.4))
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_label.add_theme_constant_override("outline_size", 10)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_label.offset_left = -300.0
	_label.offset_right = 300.0
	_label.offset_top = 120.0
	_label.offset_bottom = 170.0
	_label.visible = false
	hud.add_child(_label)


func _physics_process(delta: float) -> void:
	_local_t += delta
	var t: float = Network.game_time if Network.in_game else _local_t
	var cycle_index := int(floor(t / period))
	var cycle := fposmod(t, period)
	# Направление порыва — одинаковое у всех (зависит только от номера цикла)
	var dir := 1.0 if (cycle_index * 7919) % 2 == 0 else -1.0
	var idle := period - warning_time - gust_time
	var warning := cycle >= idle and cycle < idle + warning_time
	var gusting := cycle >= idle + warning_time

	var me = Network.local_player
	var inside := false
	if me:
		var p: Vector3 = me.global_position
		inside = p.z < z_max and p.z > z_min and absf(p.x) < half_width

	_label.visible = inside and (gusting or (warning and fmod(cycle, 0.3) < 0.2))
	_label.text = "ПОРЫВ ВЕТРА  →" if dir > 0.0 else "←  ПОРЫВ ВЕТРА"
	_snow.emitting = inside and gusting
	if not inside:
		return
	var p2: Vector3 = me.global_position
	_snow.global_position = p2 + Vector3(-dir * 12.0, 2.0, 0.0)
	(_snow.process_material as ParticleProcessMaterial).direction = Vector3(dir, 0.0, 0.0)
	if gusting and not me.is_dead:
		me.apply_wind(Vector3(dir * strength, 0.0, 0.0))
		me.add_shake(0.03)
