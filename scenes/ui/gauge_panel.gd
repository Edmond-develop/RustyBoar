extends Control
## Компактные показатели в левом нижнем углу: три тонкие светящиеся дуги.
##  * внешняя, из сегментов — КОРПУС (зелёный → жёлтый → красный), в центре — число;
##  * средняя — ПАР (выносливость), тёплая; выдохся — мигает красным;
##  * внутренняя — ХОЛОД, ледяная, с метками ступеней (нога, нога, рука) и красной
##    чертой 70%; в глыбе по ней бежит золотая дуга — сколько льда откололи;
##  * когда несёшь груз, справа появляется тонкий уровень с пузырьком — УСТОЙЧИВОСТЬ.
## Когда всё в порядке, значок почти прозрачный; меняется что-то — вспыхивает.
## Шаг 108: рисуется в свою текстуру (SubViewport) и перерисовывается, только когда что-то изменилось —
## раньше сотни мелких дуг рисовались заново каждый кадр (~200 вызовов отрисовки), теперь — одна картинка.

var player: Node

const SZ := Vector2(240, 128)
const C := Vector2(62, 64)
const R_HP := 52.0
const R_ST := 43.0
const R_FR := 35.0
const A0 := PI * 0.75          ## дуги начинаются слева внизу …
const SWEEP := PI * 1.5        ## … и идут по часовой на 270°

var _t := 0.0
var _hp := 1.0
var _st := 1.0
var _fr := 0.0
var _br := 0.0
var _last := Vector3(1, 1, 0)  ## прошлые значения (корпус, пар, холод)
var _wake := [0.0, 0.0, 0.0]  ## вспышка каждой дуги (0..1)
var _hit := 0.0
var _alpha := 0.4
var _lvl := 0.0
var _bubble := 0.0
var _font: Font
var _vp: SubViewport
var _painter: Control
var _sig := ""


class Painter extends Control:
	var owner_gauge: Control
	func _draw() -> void:
		owner_gauge._paint(self)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor_left = 0.0
	anchor_right = 0.0
	anchor_top = 1.0
	anchor_bottom = 1.0
	offset_left = 14.0
	offset_right = 14.0 + SZ.x
	offset_top = -SZ.y - 12.0
	offset_bottom = -12.0
	_font = ThemeDB.fallback_font
	var box := SubViewportContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.stretch = true
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	var pm := CanvasItemMaterial.new()
	pm.blend_mode = CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA
	box.material = pm
	add_child(box)
	_vp = SubViewport.new()
	_vp.transparent_bg = true
	_vp.size = Vector2i(SZ)
	_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	_vp.disable_3d = true
	box.add_child(_vp)
	_painter = Painter.new()
	_painter.owner_gauge = self
	_painter.size = SZ
	_painter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vp.add_child(_painter)


func _process(delta: float) -> void:
	_t += delta
	if player == null or not is_instance_valid(player):
		return
	var hp: float = clampf(float(player.health) / float(player.max_health), 0.0, 1.0)
	var st: float = clampf(float(player.stamina) / float(player.stamina_max), 0.0, 1.0)
	var frozen: bool = player.is_frozen
	var fr: float = 1.0 if frozen else clampf(float(player.frost) / float(player.frost_max), 0.0, 1.0)
	var now := Vector3(hp, st, fr)
	for k in 3:
		if absf(now[k] - _last[k]) > 0.0005:
			_wake[k] = 1.0
		else:
			_wake[k] = maxf(_wake[k] - delta * 0.35, 0.0)
	if hp < _last.x - 0.004:
		_hit = 1.0
	_last = now
	_hit = maxf(_hit - delta * 2.5, 0.0)
	_hp = lerpf(_hp, hp, clampf(delta * 6.0, 0.0, 1.0))
	_st = lerpf(_st, st, clampf(delta * 8.0, 0.0, 1.0))
	_fr = lerpf(_fr, fr, clampf(delta * 6.0, 0.0, 1.0))
	_br = lerpf(_br, float(player._break_progress) if frozen else 0.0, clampf(delta * 8.0, 0.0, 1.0))
	# насколько видно: всё хорошо — еле-еле; что-то меняется или плохо — ярко
	var need := 0.32
	need = maxf(need, float(_wake.max()))
	if hp < 0.4 or fr > 0.01 or st < 0.98 or frozen:
		need = maxf(need, 0.85)
	var carrying: bool = player.held_parcel != null and int(player._carry_mode()) != 2
	if carrying:
		need = 1.0
	_alpha = move_toward(_alpha, need, delta * (3.0 if need > _alpha else 0.8))
	_lvl = move_toward(_lvl, 1.0 if carrying else 0.0, delta * 4.0)
	var inst: float = float(player.instability) if carrying else 0.0
	var wob := clampf(sin(_t * 1.7) * 1.4 + sin(_t * 4.3) * 0.3, -1.0, 1.0)
	_bubble = lerpf(_bubble, clampf(inst * wob * 1.15, -1.0, 1.0), clampf(delta * 6.0, 0.0, 1.0))
	visible = not bool(player.is_dead)
	# перерисовать, только если на картинке что-то поменяется
	var blink := ""
	if _hp < 0.25:
		blink += "h%d" % int(fmod(_t, 0.5) < 0.25)
	if float(player._exhausted_timer) > 0.0:
		blink += "e%d" % int(fmod(_t, 0.4) < 0.2)
	if bool(player.doomed):
		blink += "d%d" % int(fmod(_t, 0.35) < 0.17)
	var sig := "%d|%d|%d|%d|%d|%d|%d|%s|%d|%d" % [roundi(_hp * 300.0), roundi(_st * 300.0), roundi(_fr * 300.0), roundi(_br * 100.0),
		roundi(_alpha * 120.0), roundi(_lvl * 100.0), roundi(_bubble * 100.0), blink, roundi(float(player.doom_frost) * 100.0), int(frozen)]
	if _hit > 0.0:
		sig += "#%d" % Engine.get_process_frames()
	if sig != _sig and _vp != null:
		_sig = sig
		_painter.queue_redraw()
		_vp.render_target_update_mode = SubViewport.UPDATE_ONCE


func _a(v: float) -> float:
	return A0 + clampf(v, 0.0, 1.0) * SWEEP


var ci: CanvasItem


func _arc(r: float, v0: float, v1: float, col: Color, w: float) -> void:
	if v1 - v0 <= 0.001:
		return
	var n := maxi(int((v1 - v0) * 48.0), 3)
	ci.draw_arc(C, r, _a(v0), _a(v1), n, col, w, true)


func _glow_arc(r: float, v0: float, v1: float, col: Color, w: float) -> void:
	_arc(r, v0, v1, Color(col.r, col.g, col.b, col.a * 0.18), w + 6.0)
	_arc(r, v0, v1, Color(col.r, col.g, col.b, col.a * 0.35), w + 2.5)
	_arc(r, v0, v1, col, w)


func _tick(r: float, v: float, len: float, col: Color, w := 1.5) -> void:
	var a := _a(v)
	var d := Vector2(cos(a), sin(a))
	ci.draw_line(C + d * (r - len * 0.5), C + d * (r + len * 0.5), col, w, true)


func _icon(kind: int, p: Vector2, col: Color) -> void:
	match kind:
		0:
			# щиток корпуса
			ci.draw_colored_polygon(PackedVector2Array([p + Vector2(-3.5, -4), p + Vector2(3.5, -4), p + Vector2(3.5, 0), p + Vector2(0, 4.5), p + Vector2(-3.5, 0)]), col)
		1:
			# струйки пара
			for k in 3:
				var x := -3.0 + k * 3.0
				ci.draw_polyline(PackedVector2Array([p + Vector2(x, 4), p + Vector2(x + 1.2, 1.5), p + Vector2(x - 0.8, -1), p + Vector2(x + 0.6, -4)]), col, 1.2, true)
		_:
			# снежинка
			for k in 3:
				var a := k * PI / 3.0
				var d := Vector2(cos(a), sin(a)) * 4.0
				ci.draw_line(p - d, p + d, col, 1.3, true)


func _text(s: String, at: Vector2, sz: int, col: Color) -> void:
	var w := _font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x
	ci.draw_string(_font, at - Vector2(w * 0.5, 0), s, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, col)


func _paint(canvas: CanvasItem) -> void:
	ci = canvas
	if player == null or not is_instance_valid(player):
		return
	var al := _alpha
	var jit := Vector2(randf_range(-1, 1), randf_range(-1, 1)) * _hit * 3.0
	ci.draw_set_transform(jit)
	# мягкая тёмная подложка — чтобы дуги читались на снегу
	ci.draw_circle(C, R_HP + 10.0, Color(0.02, 0.03, 0.05, 0.22 * al))
	ci.draw_circle(C, R_HP + 7.0, Color(0.02, 0.03, 0.05, 0.3 * al))
	ci.draw_circle(C, R_FR - 6.0, Color(0.02, 0.03, 0.05, 0.35 * al))
	ci.draw_arc(C, R_HP + 7.5, 0.0, TAU, 64, Color(1, 1, 1, 0.1 * al), 1.0, true)
	var track := Color(1, 1, 1, 0.12 * al)
	_arc(R_HP, 0.0, 1.0, track, 5.0)
	_arc(R_ST, 0.0, 1.0, track, 3.0)
	_arc(R_FR, 0.0, 1.0, track, 3.0)

	# --- КОРПУС: 20 сегментов
	var hp := _hp
	var hc := Color(1.0, 0.25, 0.2).lerp(Color(1.0, 0.78, 0.25), clampf(hp * 2.0, 0.0, 1.0)).lerp(Color(0.45, 1.0, 0.6), clampf(hp * 2.0 - 1.0, 0.0, 1.0))
	if hp < 0.25 and fmod(_t, 0.5) < 0.25:
		hc = hc.lightened(0.4)
	hc = hc.lerp(Color(1, 1, 1), _hit * 0.6)
	hc.a = al
	var segs := 20
	for k in segs:
		var v0 := float(k) / segs + 0.006
		var v1 := float(k + 1) / segs - 0.006
		if v0 >= hp:
			break
		_glow_arc(R_HP, v0, minf(v1, hp), hc, 5.0)

	# --- ПАР
	var exhausted: bool = float(player._exhausted_timer) > 0.0
	var sc := Color(1.0, 0.86, 0.55)
	if exhausted:
		sc = Color(1.0, 0.3, 0.25) if fmod(_t, 0.4) < 0.2 else Color(1.0, 0.55, 0.4)
	sc.a = al
	_glow_arc(R_ST, 0.0, _st, sc, 3.0)

	# --- ХОЛОД
	var fc := Color(0.55, 0.85, 1.0)
	var doomed: bool = player.doomed
	if doomed and fmod(_t, 0.35) < 0.17:
		fc = Color(0.9, 0.95, 1.0)
	fc.a = al
	_glow_arc(R_FR, 0.0, _fr, fc, 3.0)
	if bool(player.is_frozen):
		_glow_arc(R_FR, 0.0, _br, Color(1.0, 0.8, 0.3, al), 3.0)
	for v in [0.25, 0.5, 0.75]:
		_tick(R_FR, v, 7.0, Color(0.85, 0.95, 1.0, 0.55 * al), 1.4)
	_tick(R_FR, float(player.doom_frost), 9.0, Color(1.0, 0.3, 0.25, 0.9 * al), 2.2)

	# --- значки в нижнем промежутке между концами дуг: щиток, пар, снежинка
	var ends := [[0, hc], [1, sc], [2, fc]]
	for k in 3:
		var col: Color = ends[k][1]
		col.a = 0.9 * al
		_icon(int(ends[k][0]), C + Vector2(-15.0 + k * 15.0, R_HP - 3.0), col)

	# --- число в центре
	var num := str(roundi(hp * 100.0))
	_text(num, C + Vector2(0, 7), 20, Color(1, 1, 1, 0.92 * al))
	_text("корпус", C + Vector2(0, 18), 8, Color(1, 1, 1, 0.55 * al))
	if exhausted:
		_text("выдохся", C + Vector2(0, -12), 8, Color(1.0, 0.5, 0.4, al))
	elif doomed:
		_text("вмерзаю!", C + Vector2(0, -12), 8, Color(0.75, 0.9, 1.0, al))

	# --- уровень устойчивости (с грузом)
	if _lvl > 0.01:
		var k2 := smoothstep(0.0, 1.0, _lvl)
		var x0 := C.x + R_HP + 16.0
		var y := C.y + 2.0
		var w := 104.0 * k2
		var stab := 1.0 - (float(player.instability) if player.held_parcel != null else 0.0)
		var lc := Color(0.75, 1.0, 0.5).lerp(Color(1.0, 0.3, 0.25), clampf((0.6 - stab) / 0.4, 0.0, 1.0))
		lc.a = k2
		ci.draw_rect(Rect2(x0 - 2, y - 9, w + 4, 18), Color(0.02, 0.03, 0.05, 0.35 * k2))
		ci.draw_line(Vector2(x0, y), Vector2(x0 + w, y), Color(1, 1, 1, 0.18 * k2), 6.0, true)
		ci.draw_line(Vector2(x0, y - 7), Vector2(x0, y + 7), Color(1, 1, 1, 0.5 * k2), 1.5)
		ci.draw_line(Vector2(x0 + w, y - 7), Vector2(x0 + w, y + 7), Color(1, 1, 1, 0.5 * k2), 1.5)
		var mid := x0 + w * 0.5
		ci.draw_line(Vector2(mid - 9, y - 6), Vector2(mid - 9, y + 6), Color(1, 1, 1, 0.35 * k2), 1.0)
		ci.draw_line(Vector2(mid + 9, y - 6), Vector2(mid + 9, y + 6), Color(1, 1, 1, 0.35 * k2), 1.0)
		var bx := mid + _bubble * (w * 0.5 - 8.0)
		ci.draw_line(Vector2(bx - 7, y), Vector2(bx + 7, y), Color(lc.r, lc.g, lc.b, 0.3 * k2), 12.0, true)
		ci.draw_line(Vector2(bx - 6, y), Vector2(bx + 6, y), lc, 6.0, true)
		ci.draw_string(_font, Vector2(x0, y - 12), "устойчивость", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(1, 1, 1, 0.6 * k2))
	ci.draw_set_transform(Vector2.ZERO)
