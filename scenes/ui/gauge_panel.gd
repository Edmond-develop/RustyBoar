extends Control
## Приборная панель скафандра внизу экрана (стимпанк):
##  * в центре — большой латунный циферблат «КОРПУС»: стрелка с пружиной (вздрагивает от
##    ударов), красная зона, счётчик-окошко, на стекле трещины, когда корпус плох;
##  * слева — манометр «ПАР» (выносливость): на бегу из клапана валит пар, выдохся —
##    стекло запотевает, мигает лампа;
##  * справа — термометр «ХОЛОД» (обледенение): метки ступеней (нога, нога, рука),
##    красная черта невозврата, по краю стекла растут морозные узоры; в глыбе —
##    вторая, золотая стрелка показывает, сколько льда уже откололи;
##  * когда несёшь груз, над циферблатом выезжает пузырьковый уровень «УСТОЙЧИВОСТЬ».
## Всё рисуется кодом, без картинок.

var player: Node

const W := 560.0
const H := 170.0
const C := Vector2(280, 104)     ## большой циферблат
const CR := 54.0
const L := Vector2(116, 124)     ## пар
const R := Vector2(444, 124)     ## холод
const SR := 38.0

const BRASS_D := Color(0.42, 0.3, 0.13)
const BRASS := Color(0.72, 0.56, 0.27)
const BRASS_L := Color(0.95, 0.82, 0.5)
const FACE := Color(0.93, 0.9, 0.8)
const INK := Color(0.12, 0.1, 0.08)
const STEEL := Color(0.16, 0.17, 0.19)

var _t := 0.0
var _hp_v := 1.0
var _hp_vel := 0.0
var _st_v := 1.0
var _st_vel := 0.0
var _fr_v := 0.0
var _fr_vel := 0.0
var _br_v := 0.0
var _last_hp := 1.0
var _shake := 0.0
var _lvl_k := 0.0              ## уровень выехал (0..1)
var _bubble := 0.0
var _puffs: Array = []         ## пар: {p, v, life, max, r}
var _puff_t := 0.0
var _sparks: Array = []        ## искры из циферблата при сильном ударе
var _cracks: Array = []        ## трещины на стекле (в долях радиуса)
var _ferns: Array = []         ## морозные узоры по краю стекла «ХОЛОД»
var _scratches: Array = []
var _brush: Array = []
var _font: Font


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 1.0
	anchor_bottom = 1.0
	offset_left = -W * 0.5
	offset_right = W * 0.5
	offset_top = -H
	offset_bottom = 0.0
	_font = ThemeDB.fallback_font
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	# трещины: из точки удара лучами, с изломами
	var o := Vector2(0.35, -0.3)
	for k in 9:
		var a := rng.randf_range(0.0, TAU)
		var pts := PackedVector2Array([o])
		var p := o
		for j in 4:
			a += rng.randf_range(-0.5, 0.5)
			p += Vector2(cos(a), sin(a)) * rng.randf_range(0.12, 0.3)
			if p.length() > 0.95:
				p = p.normalized() * 0.95
			pts.append(p)
		_cracks.append(pts)
	# морозные «папоротники» от края внутрь
	for k in 14:
		var a2 := rng.randf_range(0.0, TAU)
		var base := Vector2(cos(a2), sin(a2)) * 0.98
		var dir := -base.rotated(rng.randf_range(-0.5, 0.5))
		var len := rng.randf_range(0.25, 0.55)
		_ferns.append({"a": base, "d": dir, "len": len, "th": rng.randf_range(0.0, 0.9)})
	# царапины и шлифовка на пластине
	for k in 22:
		var p0 := Vector2(rng.randf_range(20, W - 20), rng.randf_range(86, H - 8))
		_scratches.append([p0, p0 + Vector2(rng.randf_range(-18, 18), rng.randf_range(-4, 4))])
	for k in 30:
		_brush.append(rng.randf_range(84, H - 4))


func _process(delta: float) -> void:
	_t += delta
	if player == null or not is_instance_valid(player):
		return
	var hp: float = clampf(float(player.health) / float(player.max_health), 0.0, 1.0)
	if hp < _last_hp - 0.005:
		var hit := _last_hp - hp
		_hp_vel -= 6.0 + hit * 40.0              # стрелку дёрнуло
		_shake = minf(0.25 + hit * 2.0, 0.6)
		if hit > 0.05:
			for k in 10:
				_sparks.append({"p": C + Vector2(randf_range(-20, 20), randf_range(-20, 10)),
					"v": Vector2(randf_range(-90, 90), randf_range(-160, -40)), "life": randf_range(0.3, 0.6)})
	_last_hp = hp
	_hp_vel += (90.0 * (hp - _hp_v) - 9.0 * _hp_vel) * delta
	_hp_v += _hp_vel * delta
	var st: float = clampf(float(player.stamina) / float(player.stamina_max), 0.0, 1.0)
	_st_vel += (60.0 * (st - _st_v) - 10.0 * _st_vel) * delta
	_st_v += _st_vel * delta
	var frozen: bool = player.is_frozen
	var fr: float = 1.0 if frozen else clampf(float(player.frost) / float(player.frost_max), 0.0, 1.0)
	_fr_vel += (50.0 * (fr - _fr_v) - 9.0 * _fr_vel) * delta
	_fr_v += _fr_vel * delta
	_br_v = lerpf(_br_v, float(player._break_progress) if frozen else 0.0, clampf(delta * 8.0, 0.0, 1.0))
	_shake = maxf(_shake - delta, 0.0)
	# уровень: только когда несу груз сам или вдвоём
	var carrying: bool = player.held_parcel != null and int(player._carry_mode()) != 2
	_lvl_k = move_toward(_lvl_k, 1.0 if carrying else 0.0, delta * 4.0)
	var inst: float = float(player.instability) if carrying else 0.0
	var wob := clampf(sin(_t * 1.7) * 1.4 + sin(_t * 4.3) * 0.3, -1.0, 1.0)
	_bubble = lerpf(_bubble, clampf(inst * wob * 1.15, -1.0, 1.0), clampf(delta * 6.0, 0.0, 1.0))
	# пар из клапана: на бегу — струйкой, выдохся — клубами
	var exhausted: bool = float(player._exhausted_timer) > 0.0
	var sprint: bool = player.is_sprinting
	_puff_t -= delta
	if (sprint or exhausted) and _puff_t <= 0.0:
		_puff_t = 0.12 if sprint else 0.06
		var big := exhausted
		_puffs.append({"p": L + Vector2(SR * 0.62, -SR - 10), "v": Vector2(randf_range(8, 26), randf_range(-38, -22)),
			"life": 0.0, "max": randf_range(0.8, 1.3), "r": randf_range(4.0, 7.0) * (1.6 if big else 1.0)})
	for k in range(_puffs.size() - 1, -1, -1):
		var pf: Dictionary = _puffs[k]
		pf["life"] = float(pf["life"]) + delta
		pf["p"] = (pf["p"] as Vector2) + (pf["v"] as Vector2) * delta
		pf["v"] = (pf["v"] as Vector2) * (1.0 - delta * 0.8)
		if float(pf["life"]) > float(pf["max"]):
			_puffs.remove_at(k)
	for k in range(_sparks.size() - 1, -1, -1):
		var sp: Dictionary = _sparks[k]
		sp["life"] = float(sp["life"]) - delta
		sp["v"] = (sp["v"] as Vector2) + Vector2(0, 420) * delta
		sp["p"] = (sp["p"] as Vector2) + (sp["v"] as Vector2) * delta
		if float(sp["life"]) <= 0.0:
			_sparks.remove_at(k)
	visible = not bool(player.is_dead)
	queue_redraw()


# ---------------------------------------------------------------------------

func _ang(v: float) -> float:
	return PI * 0.75 + clampf(v, -0.03, 1.03) * PI * 1.5


func _text(s: String, at: Vector2, size: int, col: Color, center := true) -> void:
	var w := _font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x if center else 0.0
	draw_string(_font, at - Vector2(w * 0.5, 0), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


func _screw(p: Vector2, r: float, a: float) -> void:
	draw_circle(p + Vector2(0.6, 0.8), r, Color(0, 0, 0, 0.35))
	draw_circle(p, r, Color(0.55, 0.55, 0.58))
	draw_circle(p - Vector2(r * 0.3, r * 0.3), r * 0.45, Color(0.85, 0.85, 0.88, 0.6))
	var d := Vector2(cos(a), sin(a)) * r * 0.8
	draw_line(p - d, p + d, Color(0.15, 0.15, 0.17), 1.2, true)


func _rivet(p: Vector2) -> void:
	draw_circle(p + Vector2(0.8, 1.0), 3.0, Color(0, 0, 0, 0.4))
	draw_circle(p, 3.0, Color(0.36, 0.37, 0.4))
	draw_circle(p - Vector2(0.9, 0.9), 1.2, Color(0.75, 0.76, 0.8, 0.8))


## Латунный ободок, циферблат и стекло (стрелки — отдельно)
func _bezel(c: Vector2, r: float, face: Color) -> void:
	draw_circle(c + Vector2(3, 5), r + 8, Color(0, 0, 0, 0.4))
	draw_circle(c, r + 8, BRASS_D)
	draw_circle(c, r + 6, BRASS)
	draw_arc(c, r + 5, PI * 1.05, PI * 1.85, 32, BRASS_L, 3.0, true)
	draw_arc(c, r + 5, PI * 0.1, PI * 0.9, 32, BRASS_D.darkened(0.3), 3.0, true)
	draw_circle(c, r + 1.5, BRASS_D.darkened(0.4))
	draw_circle(c, r, face)
	# потемнение к краю (старая бумага)
	for k in 7:
		draw_arc(c, r - k * 1.6, 0.0, TAU, 48, Color(0.35, 0.27, 0.15, 0.07), 2.0, true)
	for k in 4:
		var a := PI * 0.25 + k * PI * 0.5
		_screw(c + Vector2(cos(a), sin(a)) * (r + 4), 2.6, a * 2.3 + c.x)


func _scale(c: Vector2, r: float, majors: int, minors: int, labels: Array, col := INK) -> void:
	var n := majors * minors
	for i in n + 1:
		var a := _ang(float(i) / n)
		var dir := Vector2(cos(a), sin(a))
		var major := i % minors == 0
		draw_line(c + dir * r * (0.7 if major else 0.78), c + dir * r * 0.86, col, 1.8 if major else 1.0, true)
		if major and labels.size() > i / minors:
			_text(String(labels[i / minors]), c + dir * r * 0.55 + Vector2(0, 4), int(r * 0.2), col)


func _zone(c: Vector2, r: float, a: float, b: float, col: Color, w: float) -> void:
	draw_arc(c, r, _ang(a), _ang(b), 24, col, w, true)


func _needle(c: Vector2, r: float, v: float, col: Color, w := 3.0) -> void:
	var a := _ang(v)
	var d := Vector2(cos(a), sin(a))
	var n := Vector2(-d.y, d.x)
	var tip := c + d * r * 0.82
	var tail := c - d * r * 0.22
	var sh := Vector2(2, 3)
	draw_colored_polygon(PackedVector2Array([tail + n * w + sh, tip + sh, tail - n * w + sh]), Color(0, 0, 0, 0.25))
	draw_colored_polygon(PackedVector2Array([tail + n * w, tip, tail - n * w]), col)
	draw_circle(tail, w * 1.4, col.darkened(0.3))
	draw_circle(c, r * 0.11, BRASS_D)
	draw_circle(c, r * 0.085, BRASS)
	draw_circle(c - Vector2(r * 0.03, r * 0.03), r * 0.035, BRASS_L)


func _glass(c: Vector2, r: float) -> void:
	draw_arc(c, r * 0.8, PI * 1.12, PI * 1.45, 18, Color(1, 1, 1, 0.22), r * 0.1, true)
	draw_circle(c + Vector2(r * 0.42, -r * 0.5), r * 0.05, Color(1, 1, 1, 0.3))


func _lamp(p: Vector2, col: Color, on: bool) -> void:
	draw_circle(p + Vector2(1, 1.5), 6.5, Color(0, 0, 0, 0.4))
	draw_circle(p, 6.5, BRASS_D)
	draw_circle(p, 5.0, col.darkened(0.75) if not on else col)
	if on:
		draw_circle(p, 10.0, Color(col.r, col.g, col.b, 0.18))
	draw_circle(p - Vector2(1.6, 1.6), 1.6, Color(1, 1, 1, 0.55 if on else 0.2))


# ---------------------------------------------------------------------------

func _draw() -> void:
	if player == null or not is_instance_valid(player):
		return
	var jit := Vector2(randf_range(-1, 1), randf_range(-1, 1)) * _shake * 6.0
	draw_set_transform(jit)
	_draw_plate()
	_draw_level()
	_draw_steam()
	_draw_frost()
	_draw_hull()
	for sp in _sparks:
		var p: Vector2 = sp["p"]
		draw_line(p, p - (sp["v"] as Vector2) * 0.03, Color(1.0, 0.8, 0.35, clampf(float(sp["life"]) * 3.0, 0.0, 1.0)), 2.0, true)
	draw_set_transform(Vector2.ZERO)


func _draw_plate() -> void:
	var poly := PackedVector2Array([Vector2(40, 80), Vector2(W - 40, 80), Vector2(W - 12, 104), Vector2(W - 4, H),
		Vector2(4, H), Vector2(12, 104)])
	var sh := PackedVector2Array()
	for p in poly:
		sh.append(p + Vector2(0, 4))
	draw_colored_polygon(sh, Color(0, 0, 0, 0.35))
	draw_colored_polygon(poly, STEEL)
	# шлифовка и царапины
	for y in _brush:
		draw_line(Vector2(16, y), Vector2(W - 16, y), Color(1, 1, 1, 0.025), 1.0)
	for sc in _scratches:
		draw_line(sc[0], sc[1], Color(1, 1, 1, 0.07), 1.0, true)
	# фаска: светлая сверху, тёмная снизу; латунная окантовка
	draw_polyline(PackedVector2Array([Vector2(12, 104), Vector2(40, 80), Vector2(W - 40, 80), Vector2(W - 12, 104)]), Color(0.42, 0.43, 0.47), 3.0, true)
	draw_polyline(PackedVector2Array([Vector2(15, 106), Vector2(42, 84), Vector2(W - 42, 84), Vector2(W - 15, 106)]), BRASS, 1.5, true)
	for k in 9:
		_rivet(Vector2(56 + k * 56, 92))
	# лампочки: питание, пар, корпус
	var hp := clampf(float(player.health) / float(player.max_health), 0.0, 1.0)
	var st := clampf(float(player.stamina) / float(player.stamina_max), 0.0, 1.0)
	_lamp(Vector2(196, 150), Color(0.35, 1.0, 0.45), fmod(_t, 2.0) < 1.6)
	_lamp(Vector2(214, 150), Color(1.0, 0.75, 0.2), st < 0.3 and fmod(_t, 0.6) < 0.3)
	_lamp(Vector2(232, 150), Color(1.0, 0.25, 0.2), hp < 0.3 and fmod(_t, 0.4) < 0.2)
	# табличка с именем, полоска цвета игрока
	var plate := Rect2(332, 140, 84, 20)
	draw_rect(Rect2(plate.position + Vector2(1, 2), plate.size), Color(0, 0, 0, 0.4))
	draw_rect(plate, BRASS)
	draw_rect(plate.grow(-2), BRASS_D.lerp(BRASS, 0.6))
	var pc := Color(0.86, 0.45, 0.17)
	if player.get("suit") != null:
		pc = player.suit.color
	draw_rect(Rect2(plate.position + Vector2(3, 3), Vector2(6, 14)), pc)
	var nm := String(player.player_name) if player.get("player_name") != null else "РБ"
	if nm.length() > 9:
		nm = nm.substr(0, 9)
	_text(nm, Vector2(plate.position.x + 47, plate.position.y + 15), 11, Color(0.18, 0.12, 0.05))
	_screw(plate.position + Vector2(78, 10), 2.0, 0.7)


func _draw_hull() -> void:
	var hp := clampf(float(player.health) / float(player.max_health), 0.0, 1.0)
	_bezel(C, CR, FACE)
	_zone(C, CR * 0.78, 0.0, 0.25, Color(0.85, 0.15, 0.1, 0.85), CR * 0.1)
	_zone(C, CR * 0.78, 0.25, 0.5, Color(0.95, 0.65, 0.1, 0.7), CR * 0.1)
	_scale(C, CR, 4, 5, ["0", "25", "50", "75", "100"])
	_text("КОРПУС", C + Vector2(0, -CR * 0.22), 9, INK)
	# окошко-счётчик
	var win := Rect2(C + Vector2(-17, CR * 0.46), Vector2(34, 13))
	draw_rect(win.grow(1.5), BRASS_D)
	draw_rect(win, Color(0.08, 0.06, 0.05))
	var num := "%03d" % roundi(hp * 100.0)
	for k in 3:
		var cell := Rect2(win.position + Vector2(1 + k * 11, 1), Vector2(10, 11))
		draw_rect(cell, Color(0.14, 0.11, 0.09))
		var glow := Color(1.0, 0.55, 0.15) if hp >= 0.25 or fmod(_t, 0.5) < 0.3 else Color(0.5, 0.2, 0.05)
		_text(num.substr(k, 1), cell.position + Vector2(5, 10), 11, glow)
	var trem := sin(_t * 47.0) * 0.012 * clampf((0.35 - hp) * 4.0, 0.0, 1.0)
	_needle(C, CR, _hp_v + trem, Color(0.72, 0.1, 0.07), 3.2)
	_glass(C, CR)
	# трещины на стекле
	var ck := clampf((0.45 - hp) / 0.4, 0.0, 1.0)
	var nc := int(ceil(ck * _cracks.size()))
	for k in nc:
		var pts: PackedVector2Array = _cracks[k]
		var out := PackedVector2Array()
		for p in pts:
			out.append(C + p * CR)
		draw_polyline(out, Color(1, 1, 1, 0.75), 1.2, true)
		draw_polyline(out, Color(0.2, 0.2, 0.25, 0.25), 2.6, true)
	# лампа тревоги на ободке
	_lamp(C + Vector2(0, -CR - 8), Color(1.0, 0.25, 0.2), hp < 0.25 and fmod(_t, 0.4) < 0.2)


func _draw_steam() -> void:
	var exhausted: bool = float(player._exhausted_timer) > 0.0
	# клапан сверху справа
	var v0 := L + Vector2(SR * 0.62, -SR - 4)
	draw_rect(Rect2(v0 + Vector2(-4, -8), Vector2(8, 12)), BRASS_D)
	draw_rect(Rect2(v0 + Vector2(-3, -8), Vector2(6, 11)), BRASS)
	draw_rect(Rect2(v0 + Vector2(-6, -11), Vector2(12, 4)), BRASS_L.darkened(0.2))
	_bezel(L, SR, FACE)
	_zone(L, SR * 0.78, 0.0, 0.2, Color(0.85, 0.15, 0.1, 0.85), SR * 0.11)
	_zone(L, SR * 0.78, 0.2, 1.0, Color(0.3, 0.55, 0.75, 0.35), SR * 0.11)
	_scale(L, SR, 4, 4, [])
	_text("ПАР", L + Vector2(0, -SR * 0.22), 9, INK)
	_text("кгс/см²", L + Vector2(0, SR * 0.5), 7, Color(0.3, 0.25, 0.2))
	_needle(L, SR, _st_v + (sin(_t * 31.0) * 0.01 if bool(player.is_sprinting) else 0.0), Color(0.12, 0.12, 0.14), 2.4)
	if exhausted:
		# запотело
		draw_circle(L, SR, Color(0.95, 0.97, 1.0, 0.45 + 0.1 * sin(_t * 3.0)))
		_text("ВЫДОХСЯ", L + Vector2(0, 14), 10, Color(0.75, 0.1, 0.08))
	_glass(L, SR)
	_lamp(L + Vector2(-SR - 2, -SR + 4), Color(1.0, 0.3, 0.2), exhausted and fmod(_t, 0.5) < 0.25)
	for pf in _puffs:
		var k := float(pf["life"]) / float(pf["max"])
		var r := float(pf["r"]) * (1.0 + k * 2.2)
		draw_circle(pf["p"], r, Color(0.95, 0.96, 1.0, 0.45 * (1.0 - k)))


func _draw_frost() -> void:
	var frozen: bool = player.is_frozen
	var doomed: bool = player.doomed
	var doom: float = float(player.doom_frost)
	_bezel(R, SR, Color(0.88, 0.93, 0.97))
	# шкала: от бледно-голубого к тёмно-синему
	for k in 10:
		var a := float(k) / 10.0
		_zone(R, SR * 0.78, a, a + 0.1, Color(0.7, 0.88, 1.0).lerp(Color(0.12, 0.3, 0.75), a), SR * 0.11)
	_zone(R, SR * 0.92, doom, 1.0, Color(0.85, 0.15, 0.1, 0.9), 3.0)
	_scale(R, SR, 4, 4, [], Color(0.1, 0.15, 0.25))
	# черта невозврата
	var ad := _ang(doom)
	var dd := Vector2(cos(ad), sin(ad))
	draw_line(R + dd * SR * 0.62, R + dd * SR * 0.95, Color(0.85, 0.1, 0.08), 2.6, true)
	# ступени: нога, нога, рука
	var stages := [0.25, 0.5, 0.75]
	for k in 3:
		var a := _ang(float(stages[k]))
		var d := Vector2(cos(a), sin(a))
		var p := R + d * SR * 0.5
		var on: bool = float(player.frost) / float(player.frost_max) >= float(stages[k]) or frozen
		var col := Color(0.1, 0.35, 0.8) if on else Color(0.35, 0.45, 0.55, 0.7)
		if k < 2:
			# нога: бедро, голень, ботинок
			draw_polyline(PackedVector2Array([p + Vector2(-1, -6), p + Vector2(1, -1), p + Vector2(0, 4)]), col, 2.2, true)
			draw_colored_polygon(PackedVector2Array([p + Vector2(-2, 3), p + Vector2(5, 3), p + Vector2(5, 6), p + Vector2(-2, 6)]), col)
		else:
			# рука: плечо, локоть, кулак
			draw_polyline(PackedVector2Array([p + Vector2(-5, -4), p + Vector2(0, 0), p + Vector2(3, 4)]), col, 2.2, true)
			draw_circle(p + Vector2(3, 5), 2.4, col)
	_text("ХОЛОД", R + Vector2(0, SR * 0.5), 9, Color(0.1, 0.18, 0.35))
	_needle(R, SR, _fr_v, Color(0.12, 0.3, 0.7), 2.4)
	if frozen:
		# в глыбе: вторая, золотая — сколько льда откололи
		_needle(R, SR * 0.85, _br_v, Color(0.95, 0.72, 0.15), 2.0)
		draw_circle(R, SR, Color(0.8, 0.92, 1.0, 0.3))
		_text("ЛЁД", R + Vector2(0, -SR * 0.25), 11, Color(0.1, 0.2, 0.45))
	# морозные узоры с края
	var fv := clampf(_fr_v, 0.0, 1.0)
	for f in _ferns:
		var grow := clampf((fv - float(f["th"]) * 0.8) * 2.5, 0.0, 1.0)
		if grow <= 0.0:
			continue
		var a0: Vector2 = R + (f["a"] as Vector2) * SR
		var d: Vector2 = f["d"]
		var len := float(f["len"]) * SR * grow
		var b := a0 + d * len
		draw_line(a0, b, Color(1, 1, 1, 0.7), 1.2, true)
		for j in 3:
			var q := a0.lerp(b, 0.3 + j * 0.22)
			var side := d.rotated(0.8) * len * 0.22
			draw_line(q, q + side, Color(1, 1, 1, 0.55), 1.0, true)
			draw_line(q, q + d.rotated(-0.8) * len * 0.22, Color(1, 1, 1, 0.55), 1.0, true)
	_glass(R, SR)
	_lamp(R + Vector2(SR + 2, -SR + 4), Color(1.0, 0.25, 0.2), doomed and fmod(_t, 0.4) < 0.2)


func _draw_level() -> void:
	if _lvl_k <= 0.01:
		return
	var y := lerpf(66.0, 22.0, smoothstep(0.0, 1.0, _lvl_k))
	var a := _lvl_k
	var cx := C.x
	var hw := 96.0
	var stab := 1.0 - (float(player.instability) if player.held_parcel != null else 0.0)
	# латунная оправа
	var frame := Rect2(cx - hw - 10, y - 13, (hw + 10) * 2, 26)
	draw_rect(Rect2(frame.position + Vector2(2, 3), frame.size), Color(0, 0, 0, 0.35 * a))
	draw_rect(frame, Color(BRASS_D.r, BRASS_D.g, BRASS_D.b, a))
	draw_rect(frame.grow(-2), Color(BRASS.r, BRASS.g, BRASS.b, a))
	draw_line(frame.position + Vector2(2, 3), frame.position + Vector2(frame.size.x - 2, 3), Color(BRASS_L.r, BRASS_L.g, BRASS_L.b, 0.8 * a), 1.5)
	_screw(Vector2(frame.position.x + 6, y), 2.4, 0.4)
	_screw(Vector2(frame.end.x - 6, y), 2.4, 1.3)
	# трубка с жидкостью
	var tube := Rect2(cx - hw, y - 7, hw * 2, 14)
	var liq := Color(0.72, 0.85, 0.22, 0.9 * a)
	if stab < 0.3:
		liq = liq.lerp(Color(1.0, 0.3, 0.2, 0.9 * a), 0.5 + 0.5 * sin(_t * 18.0))
	draw_rect(tube, Color(0.1, 0.1, 0.08, a))
	draw_rect(tube.grow(-1), liq)
	draw_line(tube.position + Vector2(2, 3), tube.position + Vector2(tube.size.x - 2, 3), Color(1, 1, 1, 0.35 * a), 2.0)
	# красные края, метки центра
	draw_rect(Rect2(tube.position, Vector2(22, 14)), Color(0.9, 0.15, 0.1, 0.35 * a))
	draw_rect(Rect2(tube.end - Vector2(22, 14), Vector2(22, 14)), Color(0.9, 0.15, 0.1, 0.35 * a))
	for sx in [-16.0, 16.0]:
		draw_line(Vector2(cx + sx, y - 7), Vector2(cx + sx, y + 7), Color(0.1, 0.1, 0.1, 0.8 * a), 1.5)
	# пузырёк
	var bx := cx + _bubble * (hw - 14)
	var br := Rect2(bx - 11, y - 5, 22, 10)
	draw_circle(Vector2(bx - 6, y), 5.0, Color(0.97, 1.0, 0.9, 0.95 * a))
	draw_circle(Vector2(bx + 6, y), 5.0, Color(0.97, 1.0, 0.9, 0.95 * a))
	draw_rect(Rect2(bx - 6, y - 5, 12, 10), Color(0.97, 1.0, 0.9, 0.95 * a))
	draw_line(br.position + Vector2(5, 2), br.position + Vector2(15, 2), Color(1, 1, 1, a), 1.5)
	_text("УСТОЙЧИВОСТЬ", Vector2(cx, y - 17), 10, Color(0.95, 0.88, 0.7, a))
