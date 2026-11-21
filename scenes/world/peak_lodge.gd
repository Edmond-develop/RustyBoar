extends "res://scenes/world/camp_cabin.gd"
## Шаг 73: Базовый лагерь «Пик» у подножия — большой бревенчатый дом экспедиции (18×13 м) во дворе за частоколом.
## Всё, что в избе «Борея-4» (камин, ковёр, подушки у огня, котелок, нары, стол, картины), плюс по-альпинистски:
##  * стена снаряжения: ледорубы, бухты верёвок, каски, кошки, карабины;
##  * стол с макетом горы (предвершина со спиралью тропы, главная вершина, канатка) и картой маршрута;
##  * длинный общий стол с лавками, кружки, керосиновые лампы; чугунная печка у левой стены;
##  * доска объявлений с фотографиями прошлых экспедиций, шкуры на полу, сушилка с варежками;
##  * во дворе — палатки, флажки на растяжках, нарты, бочки, указатель «ПИК 650 м».


func setup() -> void:
	HALF_W = 9.0
	HALF_D = 6.5
	WIN_Z = [-3.6, 0.0, 3.6]
	YARD_R = 24.0
	sign_text = "БАЗОВЫЙ ЛАГЕРЬ «ПИК»\nкамин, похлёбка, снаряжение"
	cp_title = "Базовый лагерь «Пик»"
	cp_sub = "Контрольная точка. Погрейтесь у камина — дальше только вверх"


func _materials() -> void:
	super._materials()
	_std("helmet_r", Color(0.85, 0.16, 0.1), 0.45)
	_std("helmet_y", Color(0.95, 0.75, 0.12), 0.45)
	_std("steel", Color(0.72, 0.74, 0.78), 0.3, 0.85)
	_std("rope_o", Color(0.95, 0.45, 0.08), 0.8)
	_std("rope_b", Color(0.15, 0.38, 0.8), 0.8)
	_std("pelt", Color(0.62, 0.55, 0.45), 1.0)
	_std("pelt_d", Color(0.35, 0.3, 0.26), 1.0)
	_std("paper", Color(0.93, 0.9, 0.8), 0.9)
	_std("map_blue", Color(0.35, 0.55, 0.75), 0.9)
	_std("flag_r", Color(0.9, 0.15, 0.12), 0.9)
	_std("flag_y", Color(0.98, 0.82, 0.15), 0.9)
	_std("flag_g", Color(0.15, 0.65, 0.3), 0.9)
	_std("flag_b", Color(0.15, 0.35, 0.85), 0.9)
	_std("flag_w", Color(0.95, 0.95, 0.95), 0.9)
	_std("stove_glow", Color(1.0, 0.4, 0.1), 0.5, 0.0, Color(1.0, 0.35, 0.05), 3.0)


func _decor() -> void:
	super._decor()
	var b := B()
	_gear_wall()
	_model_table()
	_long_table()
	_iron_stove()
	_notice_board()
	# шкуры на полу
	for pe in [[Vector2(-6.2, -1.0), 0.4, "pelt"], [Vector2(5.8, 3.4), -0.7, "pelt_d"], [Vector2(-2.0, 3.6), 1.2, "pelt"]]:
		var c: Vector2 = pe[0]
		var bb := b * Basis(Vector3.UP, float(pe[1]))
		waste.sph(1.0, L(c.x, 0.075, c.y), bb * Basis.from_scale(Vector3(1.3, 0.025, 0.85)), pe[2], 12)
		for s in [-1.0, 1.0]:
			for q in [-1.0, 1.0]:
				waste.sph(0.25, L(c.x, 0.075, c.y) + bb * Vector3(s * 1.2, 0.0, q * 0.7), bb * Basis.from_scale(Vector3(1.4, 0.06, 0.5)), pe[2], 6)
	# сушилка над камином: варежки и носки на верёвке
	var fz := -HALF_D + 0.5
	waste.beam(L(-1.5, 2.45, fz + 0.9), L(1.5, 2.45, fz + 0.9), 0.012, "wood_dark", 4)
	var cols := ["curtain", "rug_blue", "helmet_y", "blanket", "curtain"]
	for k in 5:
		var x := -1.2 + k * 0.6
		waste.box(Vector3(0.16, 0.26, 0.05), L(x, 2.3, fz + 0.9), b, cols[k])
		waste.box(Vector3(0.07, 0.1, 0.05), L(x + 0.1, 2.36, fz + 0.9), b, cols[k])


## Стена снаряжения (правая стена): ледорубы, верёвки, каски, кошки, карабины
func _gear_wall() -> void:
	var b := B()
	var wx := HALF_W - 0.22
	var s := 1.0
	# доска-перфорация
	waste.box(Vector3(0.06, 1.8, 5.0), L(wx, 1.55, 0.0), b, "wood")
	waste.beam(L(wx - 0.05, 2.5, -2.4), L(wx - 0.05, 2.5, 2.4), 0.025, "wood_dark", 5)
	# ледорубы
	for k in 6:
		var z := -2.1 + k * 0.42
		var top := L(wx - 0.12, 2.2, z)
		waste.beam(top, top + Vector3.DOWN * 0.75, 0.022, "wood_dark", 5)
		waste.box(Vector3(0.05, 0.05, 0.34), top + Vector3.UP * 0.02, b, "steel")
		waste.box(Vector3(0.04, 0.12, 0.06), top + u * 0.17 + Vector3.DOWN * 0.04, b, "steel")
		waste.beam(top + Vector3.DOWN * 0.75, top + Vector3.DOWN * 0.85, 0.012, "steel", 4)
	# бухты верёвок
	for k in 3:
		var c := L(wx - 0.14, 1.25, 0.6 + k * 0.62)
		var key: String = ["rope_o", "rope_b", "rope_o"][k]
		for j in 4:
			var tm := TorusMesh.new()
			tm.inner_radius = 0.17 - j * 0.012
			tm.outer_radius = 0.25 - j * 0.012
			tm.rings = 12
			tm.ring_segments = 6
			waste.put(tm, Transform3D(Basis(Quaternion(Vector3.UP, r)), c + r * (-0.02 * j)), key)
		waste.beam(c + Vector3.UP * 0.28, c + Vector3.UP * 0.36, 0.03, "wood_dark", 5)
	# каски на полке
	waste.box(Vector3(0.35, 0.05, 2.2), L(wx - 0.18, 0.85, -1.1), b, "wood")
	for k in 4:
		var hm := SphereMesh.new()
		hm.radius = 0.15
		hm.height = 0.15
		hm.is_hemisphere = true
		hm.radial_segments = 12
		hm.rings = 4
		waste.put(hm, Transform3D(b, L(wx - 0.2, 0.88, -1.9 + k * 0.52)), "helmet_r" if k % 2 == 0 else "helmet_y")
	# кошки и карабины под полкой
	for k in 2:
		var c2 := L(wx - 0.1, 0.5, -1.6 + k * 0.9)
		waste.box(Vector3(0.04, 0.03, 0.32), c2, b, "steel")
		for j in 5:
			waste.beam(c2 + u * (-0.13 + j * 0.065), c2 + u * (-0.13 + j * 0.065) + Vector3.DOWN * 0.07 + r * -0.03, 0.006, "steel", 3)
	for k in 7:
		var tm2 := TorusMesh.new()
		tm2.inner_radius = 0.025
		tm2.outer_radius = 0.04
		tm2.rings = 8
		tm2.ring_segments = 4
		waste.put(tm2, Transform3D(Basis(Quaternion(Vector3.UP, r)) * Basis.from_scale(Vector3(1.0, 1.0, 1.6)), L(wx - 0.08, 2.38 - (k % 2) * 0.05, 1.0 + k * 0.17)), "helmet_y" if k % 3 == 0 else "steel")
	waste.solid_box(L(wx - 0.2, 1.0, 0.0), Vector3(0.45, 2.0, 5.0), b, waste._solids)


## Стол с макетом горы и картой маршрута (задний правый угол)
func _model_table() -> void:
	var b := B()
	var tx := 6.6
	var tz := -4.2
	waste.box(Vector3(2.4, 0.08, 1.6), L(tx, 0.85, tz), b, "wood")
	for sx in [-1.05, 1.05]:
		for sz in [-0.68, 0.68]:
			waste.box(Vector3(0.09, 0.84, 0.09), L(tx + sx, 0.42, tz + sz), b, "wood_dark")
	waste.solid_box(L(tx, 0.45, tz), Vector3(2.4, 0.9, 1.6), b, waste._solids)
	waste.box(Vector3(2.2, 0.01, 1.4), L(tx, 0.895, tz), b, "paper")
	# предвершина: конус со спиральной тропой
	var mc := L(tx - 0.45, 0.9, tz + 0.15)
	waste.cyl(0.08, 0.5, 0.36, mc + Vector3.UP * 0.18, b, "cab_stone", 14)
	waste.cyl(0.0, 0.1, 0.06, mc + Vector3.UP * 0.39, b, "pillow", 10)
	var prev := Vector3.INF
	for k in 41:
		var t := k / 40.0
		var a := PI * 0.5 + TAU * 2.5 * t
		var rr := lerpf(0.49, 0.1, t)
		var p := mc + r * cos(a) * rr + u * sin(a) * rr + Vector3.UP * (0.36 * t + 0.01)
		if prev != Vector3.INF:
			waste.beam(prev, p, 0.009, "rope_o", 3)
		prev = p
	# главная вершина: пирамида, снег на макушке
	var pc := L(tx + 0.5, 0.9, tz - 0.25)
	waste.cyl(0.0, 0.42, 0.62, pc + Vector3.UP * 0.31, b * Basis(Vector3.UP, 0.4), "cab_stone", 3)
	waste.cyl(0.0, 0.14, 0.2, pc + Vector3.UP * 0.53, b * Basis(Vector3.UP, 0.4), "pillow", 3)
	# канатка — нитка с плато на плечо
	waste.beam(mc + Vector3.UP * 0.4, pc + Vector3.UP * 0.45 + u * 0.12, 0.004, "dark", 3)
	# флажок на вершине
	waste.beam(pc + Vector3.UP * 0.62, pc + Vector3.UP * 0.78, 0.006, "dark", 3)
	waste.box(Vector3(0.08, 0.05, 0.005), pc + Vector3.UP * 0.75 + r * 0.04, b, "flag_r")
	# лампа над столом
	waste.beam(L(tx, WALL_H, tz), L(tx, WALL_H - 0.7, tz), 0.015, "iron", 4)
	waste.cyl(0.05, 0.28, 0.16, L(tx, WALL_H - 0.75, tz), b, "iron", 12)
	waste.sph(0.1, L(tx, WALL_H - 0.86, tz), b, "lamp", 8)
	var ll := OmniLight3D.new()
	ll.light_color = Color(1.0, 0.8, 0.5)
	ll.light_energy = 1.3
	ll.omni_range = 6.0
	ll.position = L(tx, WALL_H - 1.0, tz)
	add_child(ll)
	var lb := Label3D.new()
	lb.text = "Маршрут на ПИК\nтропа → канатка → стена"
	lb.font_size = 18
	lb.outline_size = 5
	lb.modulate = Color(0.25, 0.2, 0.15)
	lb.position = L(tx, 1.45, tz - 0.8)
	lb.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	add_child(lb)


## Длинный общий стол экспедиции (слева)
func _long_table() -> void:
	var b := B()
	var tx := -6.4
	var tz := 0.6
	waste.box(Vector3(1.2, 0.08, 4.6), L(tx, 0.8, tz), b, "wood")
	for sz in [-2.0, 0.0, 2.0]:
		for sx in [-0.48, 0.48]:
			waste.box(Vector3(0.09, 0.78, 0.09), L(tx + sx, 0.39, tz + sz), b, "wood_dark")
	for sx in [-0.95, 0.95]:
		waste.box(Vector3(0.36, 0.06, 4.4), L(tx + sx, 0.45, tz), b, "wood")
		for sz in [-1.8, 0.0, 1.8]:
			waste.box(Vector3(0.3, 0.42, 0.06), L(tx + sx, 0.22, tz + sz), b, "wood_dark")
	waste.solid_box(L(tx, 0.42, tz), Vector3(2.4, 0.84, 4.6), b, waste._solids)
	for k in 6:
		var mz := tz - 1.9 + k * 0.76
		var mx := tx + (0.3 if k % 2 == 0 else -0.3)
		waste.cyl(0.055, 0.05, 0.12, L(mx, 0.9, mz), b, ["jar_r", "rug_blue", "cream"][k % 3], 10)
		waste.cyl(0.13, 0.13, 0.015, L(-mx + 2.0 * tx, 0.845, mz), b, "cream", 12)
	# керосиновые лампы на столе
	for q in [-1.2, 1.4]:
		waste.cyl(0.07, 0.08, 0.05, L(tx, 0.87, tz + q), b, "iron", 8)
		waste.cyl(0.06, 0.06, 0.16, L(tx, 0.97, tz + q), b, "window", 8)
		waste.cyl(0.03, 0.07, 0.04, L(tx, 1.07, tz + q), b, "iron", 8)
	var ll := OmniLight3D.new()
	ll.light_color = Color(1.0, 0.72, 0.4)
	ll.light_energy = 1.1
	ll.omni_range = 5.5
	ll.position = L(tx, 1.4, tz)
	add_child(ll)


## Чугунная печка-буржуйка у левой стены, труба через крышу
func _iron_stove() -> void:
	var b := B()
	var sx := -HALF_W + 0.9
	var sz := -4.4
	waste.box(Vector3(0.8, 0.7, 0.6), L(sx, 0.55, sz), b, "iron")
	for q in [-1.0, 1.0]:
		for w in [-1.0, 1.0]:
			waste.box(Vector3(0.06, 0.2, 0.06), L(sx + q * 0.32, 0.1, sz + w * 0.22), b, "iron")
	waste.box(Vector3(0.4, 0.28, 0.03), L(sx + 0.41, 0.55, sz), b * Basis(Vector3.UP, PI * 0.5), "stove_glow")
	waste.beam(L(sx, 0.9, sz), L(sx, WALL_H + 2.0, sz), 0.09, "iron", 8)
	waste.box(Vector3(1.2, 0.05, 1.2), L(sx + 0.1, 0.03, sz), b, "cab_stone")
	waste.solid_box(L(sx, 0.5, sz), Vector3(0.85, 1.0, 0.65), b, waste._solids)
	var sl := OmniLight3D.new()
	sl.light_color = Color(1.0, 0.5, 0.2)
	sl.light_energy = 1.4
	sl.omni_range = 5.0
	sl.position = L(sx + 0.7, 0.6, sz)
	add_child(sl)
	var heat := Node3D.new()
	heat.add_to_group("heat_source")
	heat.position = L(sx + 0.6, 0.4, sz)
	add_child(heat)
	# поленница у печки
	for row in 3:
		for k in 3 - row:
			waste.beam(L(sx + 0.3 + k * 0.24 + row * 0.12, 0.12 + row * 0.21, sz + 0.75), L(sx + 0.3 + k * 0.24 + row * 0.12, 0.12 + row * 0.21, sz + 1.3), 0.1, "cab_logs", 8)


## Доска объявлений с фотографиями прошлых экспедиций (передняя стена слева)
func _notice_board() -> void:
	var b := B()
	var fw := HALF_D - 0.22
	var c := L(-6.8, 1.7, fw)
	waste.box(Vector3(2.6, 1.4, 0.05), c, b, "wood")
	waste.box(Vector3(2.75, 0.07, 0.08), c + Vector3.UP * 0.72, b, "wood_dark")
	waste.box(Vector3(2.75, 0.07, 0.08), c - Vector3.UP * 0.72, b, "wood_dark")
	for k in 3:
		_picture(D.painting(k % 2), c + r * (-0.85 + k * 0.85) - u * 0.04 + Vector3.UP * 0.18, -u, Vector2(0.62, 0.45))
		waste.box(Vector3(0.6, 0.32, 0.01), c + r * (-0.85 + k * 0.85) - u * 0.035 - Vector3.UP * 0.32, b, "paper")
		waste.sph(0.025, c + r * (-0.85 + k * 0.85) - u * 0.06 + Vector3.UP * 0.42, b, "flag_r", 5)


func _yard() -> void:
	super._yard()
	var gate := u
	# палатки по кругу двора
	for k in 4:
		var a := atan2(u.z, u.x) + PI * (0.55 + k * 0.3)
		var q := Vector3(center.x + cos(a) * (YARD_R - 6.0), 0.0, center.z + sin(a) * (YARD_R - 6.0))
		q.y = waste.ground(q.x, q.z)
		_tent2(q, a + PI * 0.5, "canvas_o" if k % 2 == 0 else "canvas_b")
	# флажки на растяжках: от трубы к мачте во дворе
	var mast := center + r * 9.0 + gate * 6.0
	mast.y = waste.ground(mast.x, mast.z)
	waste.beam(mast - Vector3.UP * 0.4, mast + Vector3.UP * 7.0, 0.08, "wood_dark", 6)
	var post := center - r * 10.0 + gate * 5.0
	post.y = waste.ground(post.x, post.z) + 3.0
	waste.beam(post - Vector3.UP * 3.4, post, 0.06, "wood_dark", 6)
	var tops: Array[Vector3] = [L(0, WALL_H + 3.0, -HALF_D + 0.5), post]
	var keys := ["flag_r", "flag_y", "flag_g", "flag_b", "flag_w"]
	for t0 in tops:
		var a0: Vector3 = mast + Vector3.UP * 7.0
		var n := 18
		var prev := a0
		for k in range(1, n + 1):
			var t := float(k) / n
			var p := a0.lerp(t0, t) - Vector3.UP * 1.4 * sin(t * PI)
			waste.beam(prev, p, 0.01, "dark", 3)
			if k < n:
				var dirv := (p - prev).normalized()
				var side := dirv.cross(Vector3.UP).normalized()
				waste.box(Vector3(0.02, 0.32, 0.3), p + Vector3.DOWN * 0.17, Basis(side, Vector3.UP, dirv).orthonormalized(), keys[k % 5])
			prev = p
	# указатель
	var sp := center + gate * (YARD_R - 3.0) + r * 4.0
	sp.y = waste.ground(sp.x, sp.z)
	waste.beam(sp - Vector3.UP * 0.3, sp + Vector3.UP * 2.6, 0.07, "wood_dark", 6)
	var lb := Label3D.new()
	lb.text = "ПИК — 650 м\n← тропа на предвершину\nканатка — с плато"
	lb.font_size = 32
	lb.outline_size = 9
	lb.modulate = Color(1.0, 0.85, 0.5)
	lb.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	lb.position = sp + Vector3.UP * 3.2
	add_child(lb)
	# нарты и ящики
	var sl := center - r * 7.0 - gate * 7.0
	sl.y = waste.ground(sl.x, sl.z)
	waste.box(Vector3(1.0, 0.08, 2.4), sl + Vector3.UP * 0.35, Basis(r, Vector3.UP, gate), "wood")
	for s in [-1.0, 1.0]:
		waste.beam(sl + r * s * 0.45 + Vector3.UP * 0.1 - gate * 1.3, sl + r * s * 0.45 + Vector3.UP * 0.1 + gate * 1.1, 0.03, "iron", 4)
		waste.beam(sl + r * s * 0.45 + Vector3.UP * 0.1 - gate * 1.3, sl + r * s * 0.45 + Vector3.UP * 0.45 - gate * 1.45, 0.03, "iron", 4)
	for k in 3:
		waste.box(Vector3(0.6, 0.45, 0.6), sl + Vector3.UP * (0.62 + (k / 2) * 0.45) + gate * (-0.7 + (k % 2) * 0.75), Basis(r, Vector3.UP, gate), "crate")


func _tent2(p: Vector3, yaw: float, key: String) -> void:
	var b := Basis(Vector3.UP, yaw)
	var tm := PrismMesh.new()
	tm.size = Vector3(2.6, 1.6, 3.0)
	waste.put(tm, Transform3D(b, p + Vector3.UP * 0.8), key)
	waste.box(Vector3(0.9, 1.0, 0.05), p + b * Vector3(0, 0.5, 1.52), b, "dark")
	for s in [-1.0, 1.0]:
		waste.beam(p + b * Vector3(0, 1.6, s * 1.5), p + b * Vector3(s * 0.2, 1.9, s * 2.1), 0.015, "wood_dark", 3)
	waste.solid_box(p + Vector3.UP * 0.6, Vector3(2.2, 1.2, 3.0), b)
