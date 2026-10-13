extends Control
## Схема корпуса — латунная табличка с чертежом дрона в левом верхнем углу.
## Выезжает, только когда что-то не так:
##  * оторванная рука/нога — красный пунктир, из гнезда сыплются искры;
##  * вмёрзшая — ледяная, с кристаллами и снежинкой;
##  * в руке чужая деталь — значок внизу.
## Подсказка управления (если есть) на это время отъезжает вниз, чтобы не мешала.

var player: Node
var _t := 0.0
var _shown := 0.0
var _font: Font
var _controls: Control = null
var _help: Control = null
var _controls_y := 0.0
var _help_y := 0.0
var _looked := false

const PW := 150.0
const PH := 182.0
const BRASS_D := Color(0.42, 0.3, 0.13)
const BRASS := Color(0.72, 0.56, 0.27)
const BRASS_L := Color(0.95, 0.82, 0.5)
const PAPER := Color(0.07, 0.14, 0.26)
const LINE := Color(0.62, 0.9, 1.0)
const RED := Color(1.0, 0.32, 0.25)
const ICE := Color(0.82, 0.95, 1.0)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor_left = 0.0
	anchor_right = 0.0
	anchor_top = 0.0
	anchor_bottom = 0.0
	position = Vector2(-PW - 20, 12)
	size = Vector2(PW, PH)
	_font = ThemeDB.fallback_font


func _find_hints() -> void:
	_looked = true
	var sc := get_tree().current_scene
	if sc == null:
		return
	_controls = sc.find_child("Controls", true, false) as Control
	if _controls:
		_controls_y = _controls.position.y
	_help = sc.find_child("HelpText", true, false) as Control
	if _help:
		_help_y = _help.position.y


func _process(delta: float) -> void:
	_t += delta
	if player == null or not is_instance_valid(player):
		return
	if not _looked:
		_find_hints()
	var bad := int(player.limb_mask) != 15 or int(player.ice_mask) != 0 or player.held_limb != null
	_shown = move_toward(_shown, 1.0 if bad and not bool(player.is_dead) else 0.0, delta * 3.0)
	var k := smoothstep(0.0, 1.0, _shown)
	position = Vector2(lerpf(-PW - 20, 12.0, k), 12)
	visible = _shown > 0.01
	# подсказки управления уезжают вниз под табличку
	if _controls and is_instance_valid(_controls):
		_controls.position.y = _controls_y + k * (PH + 6)
	if _help and is_instance_valid(_help):
		_help.position.y = _help_y + k * (PH + 6)
	if visible:
		queue_redraw()


func _text(s: String, at: Vector2, sz: int, col: Color) -> void:
	var w := _font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x
	draw_string(_font, at - Vector2(w * 0.5, 0), s, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, col)


func _rivet(p: Vector2) -> void:
	draw_circle(p + Vector2(0.6, 0.8), 2.4, Color(0, 0, 0, 0.4))
	draw_circle(p, 2.4, BRASS_D)
	draw_circle(p - Vector2(0.7, 0.7), 1.0, BRASS_L)


## Звено руки/ноги: состояние 0 — на месте, 1 — нет, 2 — вмёрзло
func _limb(pts: PackedVector2Array, w: float, state: int, seed_v: int) -> void:
	match state:
		0:
			draw_polyline(pts, Color(LINE.r, LINE.g, LINE.b, 0.25), w + 4.0, true)
			draw_polyline(pts, LINE, w, true)
			for p in pts:
				draw_circle(p, w * 0.5, LINE)
			draw_circle(pts[1], w * 0.32, PAPER)            # сустав
		1:
			# пунктирный контур: детали нет
			for s in pts.size() - 1:
				var a: Vector2 = pts[s]
				var b: Vector2 = pts[s + 1]
				var n := 5
				for k in n:
					if k % 2 == 0:
						draw_line(a.lerp(b, float(k) / n), a.lerp(b, float(k + 1) / n), Color(RED.r, RED.g, RED.b, 0.55 + 0.35 * sin(_t * 5.0)), 2.0, true)
			# искры из гнезда
			for k in 4:
				var ph := fmod(_t * 2.3 + k * 0.27 + seed_v * 0.13, 1.0)
				var a2 := k * 1.7 + seed_v
				var sp := pts[0] + Vector2(cos(a2), sin(a2) * 0.5 + 0.6) * ph * 14.0
				draw_circle(sp, 1.6 * (1.0 - ph), Color(1.0, 0.8, 0.35, 1.0 - ph))
			draw_circle(pts[0], 3.5, Color(1.0, 0.55, 0.25))
		2:
			# ледяная: толще, с инеем и кристаллами
			draw_polyline(pts, Color(0.5, 0.8, 1.0, 0.35), w + 7.0, true)
			draw_polyline(pts, ICE, w + 2.0, true)
			for p in pts:
				draw_circle(p, (w + 2.0) * 0.5, ICE)
			for s in pts.size() - 1:
				var a3: Vector2 = pts[s]
				var b3: Vector2 = pts[s + 1]
				var d := (b3 - a3).normalized()
				var nrm := Vector2(-d.y, d.x)
				for k in 2:
					var q := a3.lerp(b3, 0.3 + k * 0.4)
					var sd := 1.0 if (k + s + seed_v) % 2 == 0 else -1.0
					draw_line(q + nrm * sd * w * 0.4, q + nrm * sd * (w * 0.4 + 5.0) - d * 2.0, Color(1, 1, 1, 0.9), 1.4, true)
			draw_polyline(pts, Color(0.45, 0.7, 0.95, 0.8), 1.2, true)


func _snowflake(c: Vector2, r: float, col: Color) -> void:
	for k in 3:
		var a := k * PI / 3.0 + _t * 0.6
		var d := Vector2(cos(a), sin(a)) * r
		draw_line(c - d, c + d, col, 1.4, true)
		for sgn in [-1.0, 1.0]:
			var e: Vector2 = c + d * 0.6 * sgn
			draw_line(e, e + d.rotated(0.7) * 0.3 * sgn, col, 1.0, true)
			draw_line(e, e + d.rotated(-0.7) * 0.3 * sgn, col, 1.0, true)


func _draw() -> void:
	var lm: int = player.limb_mask
	var im: int = player.ice_mask
	# латунная рамка и «синька» чертежа
	draw_rect(Rect2(Vector2(3, 4), size), Color(0, 0, 0, 0.35))
	draw_rect(Rect2(Vector2.ZERO, size), BRASS_D)
	draw_rect(Rect2(Vector2(2, 2), size - Vector2(4, 4)), BRASS)
	draw_line(Vector2(3, 3), Vector2(size.x - 3, 3), BRASS_L, 1.5)
	var paper := Rect2(Vector2(8, 22), size - Vector2(16, 48))
	draw_rect(paper, PAPER)
	var gx := paper.position.x
	while gx < paper.end.x:
		draw_line(Vector2(gx, paper.position.y), Vector2(gx, paper.end.y), Color(0.3, 0.5, 0.75, 0.18), 1.0)
		gx += 11.0
	var gy := paper.position.y
	while gy < paper.end.y:
		draw_line(Vector2(paper.position.x, gy), Vector2(paper.end.x, gy), Color(0.3, 0.5, 0.75, 0.18), 1.0)
		gy += 11.0
	_text("СХЕМА КОРПУСА", Vector2(size.x * 0.5, 16), 10, Color(0.2, 0.12, 0.04))
	for p in [Vector2(6, 6), Vector2(size.x - 6, 6), Vector2(6, size.y - 6), Vector2(size.x - 6, size.y - 6)]:
		_rivet(p)
	# дрон
	var cx := size.x * 0.5
	var top := paper.position.y + 8.0
	var head := Vector2(cx, top + 13)
	draw_circle(head, 12.0, Color(LINE.r, LINE.g, LINE.b, 0.2))
	draw_arc(head, 12.0, 0.0, TAU, 28, LINE, 2.0, true)
	draw_arc(head, 7.5, PI * 1.1, PI * 1.9, 12, LINE, 3.0, true)     # визор
	var tor := Rect2(cx - 15, top + 27, 30, 36)
	draw_rect(tor, Color(LINE.r, LINE.g, LINE.b, 0.2))
	draw_rect(tor, LINE, false, 2.0)
	draw_line(Vector2(cx - 15, top + 50), Vector2(cx + 15, top + 50), LINE, 1.2)
	var sh_l := Vector2(cx - 19, top + 31)
	var sh_r := Vector2(cx + 19, top + 31)
	var hip_l := Vector2(cx - 8, top + 65)
	var hip_r := Vector2(cx + 8, top + 65)
	var st := func(bit: int) -> int:
		if (lm & bit) == 0:
			return 1
		return 2 if (im & bit) != 0 else 0
	_limb(PackedVector2Array([sh_l, sh_l + Vector2(-12, 16), sh_l + Vector2(-16, 34)]), 6.0, st.call(1), 1)
	_limb(PackedVector2Array([sh_r, sh_r + Vector2(12, 16), sh_r + Vector2(16, 34)]), 6.0, st.call(2), 2)
	_limb(PackedVector2Array([hip_l, hip_l + Vector2(-5, 20), hip_l + Vector2(-8, 40)]), 7.0, st.call(4), 3)
	_limb(PackedVector2Array([hip_r, hip_r + Vector2(5, 20), hip_r + Vector2(8, 40)]), 7.0, st.call(8), 4)
	if im != 0:
		_snowflake(Vector2(paper.end.x - 12, paper.position.y + 12), 7.0, ICE)
	if player.held_limb != null:
		# в руке деталь: гаечный ключ
		var w0 := Vector2(paper.position.x + 12, paper.end.y - 12)
		draw_line(w0, w0 + Vector2(10, -10), BRASS_L, 3.0, true)
		draw_arc(w0 + Vector2(12, -12), 4.0, 0.0, TAU * 0.8, 10, BRASS_L, 2.0, true)
	# табличка состояния
	var cap := Rect2(Vector2(8, size.y - 22), Vector2(size.x - 16, 16))
	draw_rect(cap, Color(0.12, 0.09, 0.05))
	_text(_status_text(lm, im), Vector2(size.x * 0.5, size.y - 10), 11, Color(1.0, 0.82, 0.45))


func _status_text(lm: int, im: int) -> String:
	if player.held_limb != null:
		return "деталь в руке"
	var work := lm & ~im
	var legs_w := int((work & 4) != 0) + int((work & 8) != 0)
	var legs_have := int((lm & 4) != 0) + int((lm & 8) != 0)
	if legs_w == 0:
		return "ползу на руках" if (work & 3) != 0 else "извиваюсь"
	if legs_w == 1 and legs_have == 2:
		return "волоку ногу"
	if legs_w == 1:
		return "прыгаю"
	if (im & 3) != 0:
		return "рука во льду"
	if (lm & 3) != 3:
		return "нет руки"
	return "всё на месте"
