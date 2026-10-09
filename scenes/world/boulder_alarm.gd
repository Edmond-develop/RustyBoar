extends Node3D
## Предупреждение «ГЛЫБЫ!» на экране, пока дрон на участке ледяных холмов
## и вот-вот сойдёт волна глыб. Время то же, что у boulder_spawner.gd.

@export var z_max := 236.0
@export var z_min := 194.0
@export var wave_period := 12.0
@export var warning_time := 1.8
@export var first_wave_at := 8.0

var _local_t := 0.0
var _label: Label


func _ready() -> void:
	var hud := CanvasLayer.new()
	add_child(hud)
	_label = Label.new()
	_label.text = "ГУЛ... ГЛЫБЫ!"
	_label.add_theme_font_size_override("font_size", 46)
	_label.add_theme_color_override("font_color", Color(1, 0.5, 0.3))
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_label.add_theme_constant_override("outline_size", 12)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_label.offset_left = -300.0
	_label.offset_right = 300.0
	_label.offset_top = 120.0
	_label.offset_bottom = 180.0
	_label.visible = false
	hud.add_child(_label)


func _physics_process(delta: float) -> void:
	_local_t += delta
	var t: float = Network.game_time if Network.in_game else _local_t
	var since := t - first_wave_at
	var cycle := fposmod(since, wave_period)
	var warning := cycle > wave_period - warning_time
	var me = Network.local_player
	var inside := false
	if me:
		var z: float = me.global_position.z
		inside = z < z_max and z > z_min
	_label.visible = inside and warning and fmod(cycle, 0.3) < 0.2
	if inside and warning:
		me.add_shake(0.05)
