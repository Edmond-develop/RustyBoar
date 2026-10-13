extends Control
## Шкала силы броска: дуга под прицелом. Чем дольше держишь кнопку — тем дальше бросок.
## Плеер выставляет value (0..1), distance (м) и caption; при 0 скрывается сама.

var value := 0.0
var distance := 0.0
var caption := "Сила броска"
var _shown := 0.0
var _t := 0.0
var _font: Font

const R := 62.0
const W := 12.0
const A0 := PI * 0.82
const A1 := PI * 0.18


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 0.5
	anchor_bottom = 0.5
	offset_left = -110.0
	offset_right = 110.0
	offset_top = 40.0
	offset_bottom = 190.0
	_font = ThemeDB.fallback_font


func _process(delta: float) -> void:
	_t += delta
	var want := 1.0 if value > 0.001 else 0.0
	_shown = move_toward(_shown, want, delta * (8.0 if want > 0.0 else 4.0))
	visible = _shown > 0.01
	if visible:
		queue_redraw()


func _col(k: float) -> Color:
	if k < 0.5:
		return Color(0.35, 0.9, 1.0).lerp(Color(1.0, 0.9, 0.25), k * 2.0)
	return Color(1.0, 0.9, 0.25).lerp(Color(1.0, 0.4, 0.15), (k - 0.5) * 2.0)


func _draw() -> void:
	var c := Vector2(size.x * 0.5, 20.0)
	var a := _shown
	# подложка
	draw_arc(c, R, A0, A1, 40, Color(0.05, 0.07, 0.1, 0.55 * a), W + 6.0, true)
	draw_arc(c, R, A0, A1, 40, Color(1, 1, 1, 0.12 * a), W, true)
	# заполнение — от левого края вправо, цвет теплеет
	var v := clampf(value, 0.0, 1.0)
	var steps := 24
	for k in steps:
		var u0 := float(k) / steps
		var u1 := float(k + 1) / steps
		if u0 >= v:
			break
		var e := minf(u1, v)
		var col := _col((u0 + e) * 0.5)
		col.a = 0.95 * a
		draw_arc(c, R, lerpf(A0, A1, u0), lerpf(A0, A1, e), 4, col, W, true)
	# засечки
	for k in 5:
		var ang := lerpf(A0, A1, k / 4.0)
		var d := Vector2(cos(ang), sin(ang))
		draw_line(c + d * (R - W * 0.7), c + d * (R + W * 0.7), Color(0, 0, 0, 0.45 * a), 2.0)
	# бегунок
	var ang_v := lerpf(A0, A1, v)
	var dv := Vector2(cos(ang_v), sin(ang_v))
	var pulse := 1.0 + (0.25 * sin(_t * 18.0) if v >= 0.999 else 0.0)
	draw_circle(c + dv * R, W * 0.75 * pulse, Color(1, 1, 1, 0.95 * a))
	draw_circle(c + dv * R, W * 0.45 * pulse, _col(v) * Color(1, 1, 1, a))
	# подписи
	var txt := "≈ %d м" % roundi(distance) if distance > 0.0 else ""
	if v >= 0.999:
		txt += "  МАКС"
	var fs := 22
	var tw := _font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string_outline(_font, Vector2(c.x - tw * 0.5, c.y + R + 34.0), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 6, Color(0, 0, 0, 0.8 * a))
	draw_string(_font, Vector2(c.x - tw * 0.5, c.y + R + 34.0), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, a))
	var cs := 15
	var cw := _font.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, cs).x
	draw_string_outline(_font, Vector2(c.x - cw * 0.5, c.y + R + 56.0), caption, HORIZONTAL_ALIGNMENT_LEFT, -1, cs, 5, Color(0, 0, 0, 0.7 * a))
	draw_string(_font, Vector2(c.x - cw * 0.5, c.y + R + 56.0), caption, HORIZONTAL_ALIGNMENT_LEFT, -1, cs, Color(0.85, 0.9, 1.0, 0.9 * a))
