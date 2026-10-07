extends Area3D
## Невидимая граница участка. Когда дрон входит — на экране крупно
## показывается название участка и подсказка.

@export var title := "Участок"
@export_multiline var subtitle := ""

var _last_shown := -100.0


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node3D) -> void:
	if not body.is_in_group("player"):
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now - _last_shown < 20.0:
		return
	_last_shown = now
	get_tree().call_group("level", "show_banner", title, subtitle)
