extends CanvasLayer
## Экран завершения уровня: подробный чек доставки.

@onready var title_label: Label = $Center/Panel/Margin/VBox/Title
@onready var rows_grid: GridContainer = $Center/Panel/Margin/VBox/Rows
@onready var total_value: Label = $Center/Panel/Margin/VBox/TotalRow/Value
@onready var restart_button: Button = $Center/Panel/Margin/VBox/Restart

const COLOR_PLUS := Color(0.45, 1.0, 0.5)
const COLOR_MINUS := Color(1.0, 0.45, 0.4)
const COLOR_NORMAL := Color(0.92, 0.94, 0.97)


func _ready() -> void:
	visible = false
	restart_button.pressed.connect(_on_restart_pressed)


## rows — массив строк вида ["Название", "Значение", тип], где тип: 0 — обычный, 1 — плюс, -1 — минус.
func show_receipt(title: String, rows: Array, total: int) -> void:
	title_label.text = title
	for child in rows_grid.get_children():
		child.queue_free()
	for row in rows:
		var name_label := Label.new()
		name_label.text = row[0]
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		rows_grid.add_child(name_label)

		var value_label := Label.new()
		value_label.text = row[1]
		value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		var kind: int = row[2]
		value_label.add_theme_color_override("font_color",
			COLOR_PLUS if kind > 0 else (COLOR_MINUS if kind < 0 else COLOR_NORMAL))
		rows_grid.add_child(value_label)

	total_value.text = "%d кр" % total
	total_value.add_theme_color_override("font_color", COLOR_PLUS if total >= 0 else COLOR_MINUS)

	visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	restart_button.grab_focus()


func _on_restart_pressed() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()
