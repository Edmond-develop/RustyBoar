extends Node3D
## Шаг 86: «Ледник со скрытыми трещинами» (вместо парового котла).
##   * Поле ~200 м вдоль тропы, шире её; 22 трещины поперёк: открытые (перепрыгнуть), широкие (обойти),
##     со снежными мостами (крепкий держит, слабый рушится), скрытые под снегом (не видно совсем).
##   * У входа — стойка: E — обвязаться одной верёвкой с напарником (другом или ботом), взять ледоруб.
##     Без связки провал в трещину — смерть. Шаг 88: щупа нет — идёте наугад; верёвка держит крепко.
##   * Скрытый/слабый мост под ногами: треск — и через долю секунды рушится.
##   * Провалился в связке: верёвка рвёт напарника к краю. У него секунда — ЛКМ: зарубиться ледорубом
##     (не успел — ещё одна попытка; снова нет — оба в трещину). Удержал — ставит снежный якорь и тянет
##     (держи E), а упавший лезет по стене трещины (ЛКМ/ПКМ по очереди). У края — вылез.
##   * Решает хост (мосты, флажки, спасение), рассылает всем; движение своего дрона — у себя (как скалы).

const M := preload("res://scenes/world/mountain_layout.gd")
const SFX := preload("res://scripts/sfx.gd")
const FX := preload("res://scripts/fx.gd")
const ROPE_L := 9.0                ## длина верёвки между двумя
const PIECE := 3.0                 ## мост рушится кусками по столько метров
const CRACK_T := 0.38              ## скрытый мост: от треска до обвала
const WEAK_T := 0.6                ## слабый видимый мост
const WALL_D := 20.0               ## глубина стенок трещины (сходятся клином)
const WIN1 := 0.7                  ## шаг 89: столько тащит до края — ЛКМ, пока не поздно
const DRAG_P := 1.4                ## как разгоняется (меньше — резче с места)
const SETTLE_T := 0.7              ## зарубился — гашу рывок
const HOLD_T := 12.0               ## шаг 94: даже с ледорубом медленно сползаю к краю — столько секунд до края
const HAUL_V := 0.9                 ## тяну верёвку (в рывке; в среднем ~0.45 м/с)
const CLIMB_STEP := 0.3 
const NEAR_D := 5.5                ## шаг 133: ближе к краю — рывок резкий, ледоруб берёт не всегда           ## один перехват упавшего (узкая трещина)
const SLIP_V := 0.12               ## никто не тянет/не лезет — верёвка ползёт
const IDLE_T := 1.4
const MAX_DEPTH := 9.0
const SELF_W := 1.9                ## трещина уже — упавший достаёт стену и лезет сам
const GRIP_DECAY := 0.05           ## ледоруб выползает из снега

var mtn: Node
var cr: Array = []                 ## трещины (из раскладки)
var pieces: Array = []             ## мосты: {ci, la, lb, kind, ok, node, body}
var teams: Array = []              ## шаг 95: связки (до 4, по порядку на верёвке), у всех
var rescue := {}                   ## спасение (у всех), см. _req_fall
var _st_t := {}                    ## pid → сколько идёт его состояние в спасении (свой счёт)
var _st_last := {}
var _press := {}                   ## мост → сколько на нём стоят (хост)
var _rope_vis := {}                ## pid младшего → [MeshInstance3D…]
var _cp_set := {}
var _no_catch := {}                ## кто уже падает без страховки
var _haul_on := {}                 ## pid держателя → держит E
var _climb_last := {}              ## pid упавшего → [рука, время]
var _strike_t := {}                ## когда ударил ледорубом (держатель, своё)
var _axe_vis := {}                 ## pid → [ледоруб, хват левой]
var _drag_fx: GPUParticles3D
var _axe_fx: GPUParticles3D
var _belly_set := {}
var _last_phase := ""
var _cor: Array = []               ## козырёк каждой трещины (для точного положения стенки)
var _clock := 0.0                  ## своё время (идёт с игрой)
var _impact_t := 9.0               ## шаг 89: ледоруб врезался — снег из-под клюва
var _impact_at := Vector3.ZERO
var _ph_t := 0.0                   ## сколько идёт текущая фаза спасения (у каждого свой счёт)
var _sync_t := 0.0
var _start := Vector3.ZERO
var _exit := Vector3.ZERO
var _rack_a := Vector3.ZERO
var _rack_b := Vector3.ZERO
var _ice_mat: Material
var _rope_mesh: CylinderMesh
var _rope_mat: StandardMaterial3D
var _rope_smat: ShaderMaterial
var _hint_msg := ""
var _hint_t := 0.0
var _puff: GPUParticles3D
var tied := {}                     ## шаг 96: кто обвязался у стойки (обвязка + ледоруб), у всех
var _drop := {}                    ## pid → [трещина, время]: мост рухнул под ногами — тяну в дыру
var _n_cache := {}
var _t_cache := {}
var _exc := {}                     ## pid → края узкой щели не держат (падаю в неё)
var _pieces_of := {}               ## трещина → номера её кусков моста
var _rope_t := 0


func build() -> void:
	add_to_group("part_sockets")
	cr = M.gl_cracks()
	var b: Node3D = mtn.builder
	_ice_mat = b.mat("ice")
	if _ice_mat is ShaderMaterial:
		# в трещине — без свечения толщи: книзу темнеет (цвет вершин)
		_ice_mat = (_ice_mat as ShaderMaterial).duplicate()
		(_ice_mat as ShaderMaterial).set_shader_parameter("glow", 0.0)
	_rope_mesh = CylinderMesh.new()
	_rope_mesh.top_radius = 0.018
	_rope_mesh.bottom_radius = 0.018
	_rope_mesh.height = 1.0
	_rope_mesh.radial_segments = 5
	_rope_mesh.rings = 1
	_rope_mat = StandardMaterial3D.new()
	_rope_mat.albedo_color = Color(0.95, 0.35, 0.1)
	_rope_mat.roughness = 0.8
	var rsh := load("res://shaders/rope_kern.gdshader") as Shader
	if rsh:
		_rope_smat = ShaderMaterial.new()
		_rope_smat.shader = rsh
	_build_surface()
	_build_walls()
	_build_pieces()
	_build_stations(b)

	_puff = FX.particles(Color(0.95, 0.97, 1.0, 0.8), 40, 1.2, 0.25, 1.5, 3.5, Vector3(0, -3.0, 0), 50.0, true)
	add_child(_puff)
	_n_cache.clear()
	_t_cache.clear()


# ---------------------------------------------------------------------------
#  Мир: (s, вбок) → точка
# ---------------------------------------------------------------------------

func W(s: float, lat: float, dy := 0.0) -> Vector3:
	var u := M.GL_U0 + s / M.len_per_u(M.GL_U0)
	var p := M.point(u) + M.outward(u) * lat
	p.y = M.gl_h(s, lat) + dy
	return p


func _tang(s: float) -> Vector3:
	return M.tangent(M.GL_U0 + s / M.len_per_u(M.GL_U0))


func _out(s: float) -> Vector3:
	return M.outward(M.GL_U0 + s / M.len_per_u(M.GL_U0))


## Треугольник лицом в сторону face (для правильной стороны и нормали)
func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, face: Vector3, faces: PackedVector3Array) -> void:
	if (b - a).cross(c - a).dot(face) > 0.0:
		var t := b
		b = c
		c = t
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)
	faces.append(a)
	faces.append(b)
	faces.append(c)


func _tri_c(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, ca: Color, cb: Color, cc: Color, face: Vector3, faces: PackedVector3Array) -> void:
	if (b - a).cross(c - a).dot(face) > 0.0:
		var t := b
		b = c
		c = t
		var tc := cb
		cb = cc
		cc = tc
	st.set_color(ca)
	st.add_vertex(a)
	st.set_color(cb)
	st.add_vertex(b)
	st.set_color(cc)
	st.add_vertex(c)
	faces.append(a)
	faces.append(b)
	faces.append(c)


## Шаг 96: нормаль снега — одна формула и для поля, и для скрытых мостов: шва и «пятна» над трещиной не видно
func _nrm(s: float, lat: float) -> Vector3:
	var ks := int(roundf(s))
	var kl := int(roundf(lat * 2.0))
	var key := ks * 1000 + kl + 500
	if _n_cache.has(key):
		return _n_cache[key]
	var s0 := float(ks)
	var l0 := kl * 0.5
	var e := 0.5
	var tk := ks
	if not _t_cache.has(tk):
		var tg := _tang(s0)
		tg.y = 0.0
		var ou := _out(s0)
		ou.y = 0.0
		_t_cache[tk] = [tg.normalized(), ou.normalized()]
	var to: Array = _t_cache[tk]
	var hs := (M.gl_h(s0 + e, l0) - M.gl_h(s0 - e, l0)) / (2.0 * e)
	var hl := (M.gl_h(s0, l0 + e) - M.gl_h(s0, l0 - e)) / (2.0 * e)
	var n := (Vector3.UP - (to[0] as Vector3) * hs - (to[1] as Vector3) * hl).normalized()
	_n_cache[key] = n
	return n


func _tri_n(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, na: Vector3, nb: Vector3, nc: Vector3, face: Vector3, faces: PackedVector3Array) -> void:
	if (b - a).cross(c - a).dot(face) > 0.0:
		var t := b
		b = c
		c = t
		var tn := nb
		nb = nc
		nc = tn
	st.set_normal(na)
	st.add_vertex(a)
	st.set_normal(nb)
	st.add_vertex(b)
	st.set_normal(nc)
	st.add_vertex(c)
	faces.append(a)
	faces.append(b)
	faces.append(c)


# ---------------------------------------------------------------------------
#  Поверхность ледника: полосы по «вбок» (0.5 м), вдоль — до краёв трещин (точно по краю)
# ---------------------------------------------------------------------------

func _openings(lat: float) -> Array:
	var out: Array = []
	for i in cr.size():
		var sp := M.gl_eff(cr[i], lat)         # за концом трещины — «нулевая» щель (стыкуется с соседней полосой)
		out.append([sp.x, sp.y, i])
	return out


func _build_surface() -> void:
	var chunks := 8
	var sts: Array = []
	var faces: Array = []
	for k in chunks:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		sts.append(st)
		faces.append(PackedVector3Array())
	var l := -M.GL_IN
	while l < M.GL_OUT - 0.01:
		var la := l
		var lb := minf(l + 0.25, M.GL_OUT)
		var oa := _openings(la)
		var ob := _openings(lb)
		# сплошные куски между щелями
		var prev_a := -0.6
		var prev_b := -0.6
		for i in oa.size() + 1:
			var ea := (M.GL_LEN + 0.6) if i == oa.size() else float(oa[i][0])
			var eb := (M.GL_LEN + 0.6) if i == ob.size() else float(ob[i][0])
			var n := maxi(1, ceili(maxf(ea - prev_a, eb - prev_b) / 2.0))
			var RA := PackedVector3Array()
			var RB := PackedVector3Array()
			RA.resize(n + 1)
			RB.resize(n + 1)
			for j0 in n + 1:
				RA[j0] = W(lerpf(prev_a, ea, float(j0) / n), la)
				RB[j0] = W(lerpf(prev_b, eb, float(j0) / n), lb)
			for j in n:
				var t0 := float(j) / n
				var t1 := float(j + 1) / n
				var sa0 := lerpf(prev_a, ea, t0)
				var sa1 := lerpf(prev_a, ea, t1)
				var sb0 := lerpf(prev_b, eb, t0)
				var sb1 := lerpf(prev_b, eb, t1)
				var a0 := RA[j]
				var a1 := RA[j + 1]
				var b0 := RB[j]
				var b1 := RB[j + 1]
				var ck := clampi(int((sa0 + sb0) * 0.5 / M.GL_LEN * chunks), 0, chunks - 1)
				var fs: PackedVector3Array = faces[ck]
				var na0 := _nrm(sa0, la)
				var na1 := _nrm(sa1, la)
				var nb0 := _nrm(sb0, lb)
				var nb1 := _nrm(sb1, lb)
				_tri_n(sts[ck], a0, a1, b1, na0, na1, nb1, Vector3.UP, fs)
				_tri_n(sts[ck], a0, b1, b0, na0, nb1, nb0, Vector3.UP, fs)
				faces[ck] = fs
			if i < oa.size():
				prev_a = float(oa[i][1])
				prev_b = float(ob[i][1])
		l += 0.25
	var body := StaticBody3D.new()
	body.name = "GlacierBody"
	add_child(body)
	for k2 in chunks:
		var st2: SurfaceTool = sts[k2]
		st2.index()
		var mi := MeshInstance3D.new()
		mi.mesh = st2.commit()
		mi.material_override = mtn.builder.mat("rock")
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		var sh := ConcavePolygonShape3D.new()
		sh.set_faces(faces[k2])
		var cs := CollisionShape3D.new()
		cs.shape = sh
		body.add_child(cs)


# ---------------------------------------------------------------------------
#  Стенки трещин: синий лёд, книзу темнее, сходятся клином; край — снежный козырёк
# ---------------------------------------------------------------------------

func _wall_off(d: float, hw: float) -> float:
	# шаг 90: стенки почти отвесные сверху и сходятся клином в глубине (висящему есть место)
	return hw * pow(clampf(d / WALL_D, 0.0, 1.0), 1.3)


## Где на самом деле видна стенка (с козырьком и выщербинами) — насколько внутрь от края, на глубине d
func _vis_off(ci: int, d: float, hw: float, lat: float) -> float:
	var cor := float(_cor[ci]) if ci < _cor.size() else 0.15
	var lip := minf(cor * hw, 0.35) * pow(sin(PI * clampf(d / 0.95, 0.0, 1.0)), 0.7)
	var jit := (0.16 * sin(lat * 1.7 + d * 0.9 + ci) + 0.1 * sin(lat * 4.3 - d * 2.1 + ci * 2.0)) * clampf(d / 2.0, 0.0, 1.0)
	return maxf(_wall_off(d, hw) + lip + jit, 0.0)


func _build_walls() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var faces := PackedVector3Array()
	var vfaces := PackedVector3Array()             # только для вида (коллизия — ровнее, ниже)
	var levels := [0.0, 0.06, 0.18, 0.35, 0.6, 1.0, 1.8, 3.0, 4.6, 6.8, 9.5, 13.5, WALL_D]
	var deco := SurfaceTool.new()                 # сосульки и застрявшие глыбы (без коллизии)
	deco.begin(Mesh.PRIMITIVE_TRIANGLES)
	var dfaces := PackedVector3Array()
	var rng := RandomNumberGenerator.new()
	rng.seed = 8787
	for ci in cr.size():
		var c: Array = cr[ci]
		var tint := int(c[15])
		var cor := 0.06 + 0.12 * float(int(c[10]) == 1) + rng.randf_range(0.0, 0.1)    # снежный козырёк над краем
		_cor.append(cor)
		var l0 := maxf(float(c[1]), -M.GL_IN)
		var l1 := minf(float(c[2]), M.GL_OUT)
		var lat := l0
		var prev: Array = []
		while lat <= l1 + 0.001:
			var sp := M.gl_span(c, clampf(lat, float(c[1]) + 0.001, float(c[2]) - 0.001))
			var cur: Array = []
			if is_nan(sp.x):
				var ctr := float(c[0])
				sp = Vector2(ctr, ctr)
			var hw := (sp.y - sp.x) * 0.5
			var mid := (sp.x + sp.y) * 0.5
			# шаг 96: быстрее — в глубине точки по касательной от середины (верх — точно, стыкуется со снегом)
			var P0 := W(mid, lat)
			var tsd := (W(mid + 0.5, lat) - P0) * 2.0
			for side in [0, 1]:
				var col: Array = []
				for d: float in levels:
					# край скруглён: снежный козырёк плавно нависает над пустотой и уходит в лёд
					var lip := minf(cor * hw, 0.35) * pow(sin(PI * clampf(d / 0.95, 0.0, 1.0)), 0.7)
					var off := _wall_off(d, hw) + lip
					# стенки неровные: ступени, вздутия, выщербины (у каждой трещины свои)
					var jit := (0.16 * sin(lat * 1.7 + d * 0.9 + ci) + 0.1 * sin(lat * 4.3 - d * 2.1 + ci * 2.0)) * clampf(d / 2.0, 0.0, 1.0)
					var s := (sp.x + off + jit) if side == 0 else (sp.y - off - jit)
					s = clampf(s, sp.x, sp.y) if d > 0.0 else s
					var oc := _wall_off(d, hw) * 0.5
					var scl := (sp.x + oc) if side == 0 else (sp.y - oc)
					var p: Vector3
					var pc: Vector3
					if d == 0.0:
						p = W(s, lat)
						pc = W(scl, lat)
					else:
						p = P0 + tsd * (s - mid) + Vector3.DOWN * d
						# коллизия — без козырька и выщербин: в узкой трещине не застрять на краю
						pc = P0 + tsd * (scl - mid) + Vector3.DOWN * d
					col.append([p, d, pc])
				cur.append(col)
			if not prev.is_empty():
				for side2 in [0, 1]:
					var face := _tang(mid) * (1.0 if side2 == 0 else -1.0)
					var ca: Array = prev[side2]
					var cb: Array = cur[side2]
					for k in levels.size() - 1:
						var p00: Vector3 = ca[k][0]
						var p01: Vector3 = ca[k + 1][0]
						var p10: Vector3 = cb[k][0]
						var p11: Vector3 = cb[k + 1][0]
						var c00 := _depth_col(float(ca[k][1]), tint, ci)
						var c01 := _depth_col(float(ca[k + 1][1]), tint, ci)
						_tri_c(st, p00, p10, p11, c00, c00, c01, face, vfaces)
						_tri_c(st, p00, p11, p01, c00, c01, c01, face, vfaces)
						var q00: Vector3 = ca[k][2]
						var q01: Vector3 = ca[k + 1][2]
						var q10: Vector3 = cb[k][2]
						var q11: Vector3 = cb[k + 1][2]
						faces.append_array([q00, q10, q11, q00, q11, q01])
			# сосульки с козырька (не у всех трещин)
			if bool(c[16]) and hw > 0.3 and rng.randf() < 0.18:
				var sd := rng.randi_range(0, 1)
				var es := (sp.x + 0.05 + minf(cor * hw, 0.35)) if sd == 0 else (sp.y - 0.05 - minf(cor * hw, 0.35))
				var top := W(es, lat + rng.randf_range(-0.2, 0.2), -0.4)
				_icicle(deco, top, rng.randf_range(0.3, 1.3), rng.randf_range(0.04, 0.09), dfaces)
			prev = cur
			lat += 0.25
		# застрявшие глыбы льда в глубине
		for k3 in int(c[17]):
			var lt := rng.randf_range(maxf(float(c[1]), -M.GL_IN) + 2.0, minf(float(c[2]), M.GL_OUT) - 2.0)
			var sp3 := M.gl_span(c, lt)
			if is_nan(sp3.x) or sp3.y - sp3.x < 0.8:
				continue
			var dd := rng.randf_range(3.0, 7.0)
			var hw3 := (sp3.y - sp3.x) * 0.5 - _wall_off(dd, (sp3.y - sp3.x) * 0.5)
			var ctr3 := W((sp3.x + sp3.y) * 0.5, lt, -dd)
			_block(deco, ctr3, Vector3(hw3 * 2.0 + 0.2, rng.randf_range(0.5, 1.1), rng.randf_range(0.8, 1.6)), _tang((sp3.x + sp3.y) * 0.5), rng.randf() * 0.5, dfaces)
	# внешний край ледника — ледяной обрыв (сераки)
	var s0 := 0.0
	while s0 < M.GL_LEN - 0.01:
		var s1 := minf(s0 + 2.0, M.GL_LEN)
		var face2 := _out(s0)
		var j0 := 0.35 * sin(s0 * 1.3)
		var j1 := 0.35 * sin(s1 * 1.3)
		var q0 := W(s0, M.GL_OUT)
		var q1 := W(s1, M.GL_OUT)
		var r0 := W(s0, M.GL_OUT + 0.6 + j0, -14.0)
		var r1 := W(s1, M.GL_OUT + 0.6 + j1, -14.0)
		_tri_c(st, q0, q1, r1, Color(0.9, 0.95, 1.0), Color(0.9, 0.95, 1.0), Color(0.3, 0.4, 0.5), face2, faces)
		_tri_c(st, q0, r1, r0, Color(0.9, 0.95, 1.0), Color(0.3, 0.4, 0.5), Color(0.3, 0.4, 0.5), face2, faces)
		# шаг 96: ледник шире — обрыв глубже, до склона под ним
		var u0 := W(s0, M.GL_OUT + 2.4 + j0, -48.0)
		var u1 := W(s1, M.GL_OUT + 2.4 + j1, -48.0)
		_tri_c(st, r0, r1, u1, Color(0.3, 0.4, 0.5), Color(0.3, 0.4, 0.5), Color(0.16, 0.22, 0.3), face2, faces)
		_tri_c(st, r0, u1, u0, Color(0.3, 0.4, 0.5), Color(0.16, 0.22, 0.3), Color(0.16, 0.22, 0.3), face2, faces)
		s0 = s1
	st.generate_normals()
	st.index()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _ice_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	deco.generate_normals()
	var dmi := MeshInstance3D.new()
	dmi.mesh = deco.commit()
	dmi.material_override = _ice_mat
	dmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	dmi.visibility_range_end = 120.0
	add_child(dmi)
	var body := StaticBody3D.new()
	body.name = "CrackWalls"
	add_child(body)
	var sh := ConcavePolygonShape3D.new()
	sh.backface_collision = true
	sh.set_faces(faces)
	var cs := CollisionShape3D.new()
	cs.shape = sh
	body.add_child(cs)


## Цвет стенки на глубине d: у каждой трещины свой лёд — голубой, бирюзовый, густо-синий, старый (с грязными
## слоями морены); годовые слои — полосы светлее/темнее; книзу — темнота
const TINTS := [Color(0.72, 0.9, 1.05), Color(0.55, 0.95, 0.92), Color(0.45, 0.65, 1.1), Color(0.78, 0.82, 0.86)]
func _depth_col(d: float, tint := 0, ci := 0) -> Color:
	if d < 0.3:
		return Color(1.2, 1.22, 1.28)          # снежный край
	var k := pow(clampf((d - 0.3) / 15.0, 0.0, 1.0), 0.8)
	var base: Color = TINTS[tint % TINTS.size()]
	var band := 0.88 + 0.14 * sin(d * 3.1 + ci * 1.7)
	if tint == 3 and fposmod(d * 1.3 + ci, 2.2) < 0.35:
		base = Color(0.45, 0.42, 0.4)          # слой камешков и пыли
	return (base * band).lerp(Color(0.06, 0.12, 0.24), k)


## Сосулька: шестигранный конус вниз
func _icicle(st: SurfaceTool, top: Vector3, ln: float, r: float, faces: PackedVector3Array) -> void:
	var tip := top + Vector3.DOWN * ln
	for k in 6:
		var a0 := TAU * k / 6.0
		var a1 := TAU * (k + 1) / 6.0
		var p0 := top + Vector3(cos(a0), 0, sin(a0)) * r
		var p1 := top + Vector3(cos(a1), 0, sin(a1)) * r
		var face := (Vector3(cos(a0 + 0.52), 0, sin(a0 + 0.52)))
		_tri_c(st, p0, p1, tip, Color(1.1, 1.15, 1.2), Color(1.1, 1.15, 1.2), Color(0.8, 0.95, 1.1), face, faces)


## Глыба льда, застрявшая между стенками
func _block(st: SurfaceTool, c: Vector3, sz: Vector3, along: Vector3, tilt: float, faces: PackedVector3Array) -> void:
	var ax := along.normalized()
	var up := Vector3.UP.rotated(ax.cross(Vector3.UP).normalized(), tilt * 0.3)
	var bz := ax.cross(up).normalized()
	var hx := ax * sz.x * 0.5
	var hy := up * sz.y * 0.5
	var hz := bz * sz.z * 0.5
	var col := Color(0.6, 0.78, 0.95)
	for f in [[hx, hy, hz], [-hx, hy, -hz], [hy, hz, hx], [-hy, hz, -hx], [hz, hx, hy], [-hz, hx, -hy]]:
		var n: Vector3 = f[0]
		var a: Vector3 = f[1]
		var b: Vector3 = f[2]
		var q0 := c + n - a - b
		var q1 := c + n + a - b
		var q2 := c + n + a + b
		var q3 := c + n - a + b
		_tri_c(st, q0, q1, q2, col, col, col, n, faces)
		_tri_c(st, q0, q2, q3, col, col, col, n, faces)


# ---------------------------------------------------------------------------
#  Мосты: скрытые (как обычный снег), слабые и крепкие видимые. Каждый кусок — свой узел и коллизия
# ---------------------------------------------------------------------------

func _build_pieces() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 86
	for ci in cr.size():
		var c: Array = cr[ci]
		var kd := String(c[6])
		var l0 := maxf(float(c[1]), -M.GL_IN)
		var l1 := minf(float(c[2]), M.GL_OUT)
		if kd == "hidden":
			var a := l0
			while a < l1 - 0.01:
				var b2 := minf(a + PIECE, l1)
				_add_piece(ci, a, b2, "hidden")
				a = b2
		elif kd == "bridged":
			# 1–2 моста: хотя бы один крепкий
			var nb := 2 if rng.randf() < 0.6 else 1
			var strong := rng.randi_range(0, nb - 1)
			for k in nb:
				var la := rng.randf_range(l0 + 2.0, l1 - 6.0)
				if k == 1:
					la = fposmod(la + (l1 - l0) * 0.5 - l0, maxf(l1 - l0 - 6.0, 1.0)) + l0 + 2.0
				var lw := rng.randf_range(2.6, 3.4)
				_add_piece(ci, la, la + lw, "strong" if k == strong else "weak")


func _add_piece(ci: int, la: float, lb: float, kind: String) -> void:
	var c: Array = cr[ci]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var faces := PackedVector3Array()
	var hulls: Array = []
	var hump := 0.0 if kind == "hidden" else (0.16 if kind == "strong" else -0.08)   # шаг 96: скрытый — вровень со снегом, без ложбинки
	var thick := 0.45 if kind != "weak" else 0.28
	var e := 0.12 if kind == "hidden" else 0.25
	var n := 2 if kind == "hidden" else 4                 # шаг 95: скрытых мостов много — плитки крупнее
	var R := maxi(1, ceili((lb - la) / 0.5))
	var rows: Array = []
	var nrows: Array = []
	for r in R + 1:
		var u := float(r) / R
		var l := lerpf(la, lb, u)
		var row: Array = []
		var nrow: Array = []
		for j in n + 1:
			var t := float(j) / n
			# шаг 88: границы кусков — кривые: обвалится — дыра круглая/овальная, не квадрат
			var lt := l + lerpf(_bnd(ci, la, t), _bnd(ci, lb, t), u)
			var sp := M.gl_span(c, clampf(lt, float(c[1]) + 0.001, float(c[2]) - 0.001))
			if is_nan(sp.x):
				sp = Vector2(float(c[0]), float(c[0]))
			var sv := lerpf(sp.x - e, sp.y + e, t)
			row.append(W(sv, lt, hump * sin(PI * t) + 0.01))
			nrow.append(_nrm(sv, lt) if kind == "hidden" else Vector3.ZERO)
		rows.append(row)
		nrows.append(nrow)
	var dn := Vector3.DOWN * thick
	for r2 in R:
		var pr: Array = rows[r2]
		var rw: Array = rows[r2 + 1]
		for j2 in n:
			var a0: Vector3 = pr[j2]
			var a1: Vector3 = pr[j2 + 1]
			var b0: Vector3 = rw[j2]
			var b1: Vector3 = rw[j2 + 1]
			if kind == "hidden":
				var nr0: Array = nrows[r2]
				var nr1: Array = nrows[r2 + 1]
				_tri_n(st, a0, a1, b1, nr0[j2], nr0[j2 + 1], nr1[j2 + 1], Vector3.UP, faces)
				_tri_n(st, a0, b1, b0, nr0[j2], nr1[j2 + 1], nr1[j2], Vector3.UP, faces)
				_tri_n(st, a0 + dn, a1 + dn, b1 + dn, Vector3.DOWN, Vector3.DOWN, Vector3.DOWN, Vector3.DOWN, faces)
				_tri_n(st, a0 + dn, b1 + dn, b0 + dn, Vector3.DOWN, Vector3.DOWN, Vector3.DOWN, Vector3.DOWN, faces)
			else:
				_tri(st, a0, a1, b1, Vector3.UP, faces)
				_tri(st, a0, b1, b0, Vector3.UP, faces)
				_tri(st, a0 + dn, a1 + dn, b1 + dn, Vector3.DOWN, faces)
				_tri(st, a0 + dn, b1 + dn, b0 + dn, Vector3.DOWN, faces)
			var hp := PackedVector3Array()
			for v0: Vector3 in [a0, a1, b0, b1]:
				hp.append(v0)
				hp.append(v0 + dn)
			hulls.append(hp)
	# торцы куска (видно толщину снега на срезе)
	for side in [0, R]:
		var er: Array = rows[side]
		var fc := (W(0.0, lb) - W(0.0, la)).normalized() * (1.0 if side == R else -1.0)
		for j3 in n:
			var q0: Vector3 = er[j3]
			var q1: Vector3 = er[j3 + 1]
			if kind == "hidden":
				_tri_n(st, q0, q1, q1 + dn, fc, fc, fc, fc, faces)
				_tri_n(st, q0, q1 + dn, q0 + dn, fc, fc, fc, fc, faces)
			else:
				_tri(st, q0, q1, q1 + dn, fc, faces)
				_tri(st, q0, q1 + dn, q0 + dn, fc, faces)
	if kind != "hidden":
		st.generate_normals()
	var node := Node3D.new()
	add_child(node)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mtn.builder.mat("rock")
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.add_child(mi)
	var body := StaticBody3D.new()
	node.add_child(body)
	for hp2: PackedVector3Array in hulls:
		var cv := ConvexPolygonShape3D.new()
		cv.points = hp2
		var cs := CollisionShape3D.new()
		cs.shape = cv
		body.add_child(cs)
	if not _pieces_of.has(ci):
		_pieces_of[ci] = []
	(_pieces_of[ci] as Array).append(pieces.size())
	pieces.append({"ci": ci, "la": la, "lb": lb, "kind": kind, "ok": true, "node": node, "body": body})


## Кривая граница куска моста на «вбок» l (t — доля поперёк трещины); у концов трещины — прямая
func _bnd(ci: int, l: float, t: float) -> float:
	var c: Array = cr[ci]
	if l <= maxf(float(c[1]), -M.GL_IN) + 0.01 or l >= minf(float(c[2]), M.GL_OUT) - 0.01:
		return 0.0
	var h := sin(float(ci) * 12.9898 + l * 78.233) * 43758.5453
	h -= floor(h)
	var sg := 1.0 if int(floor(h * 7.0)) % 2 == 0 else -1.0
	return (lerpf(0.3, 0.75, h) * sg * pow(sin(PI * t), 0.8) + 0.12 * sin(t * 6.0 + h * 20.0)) * sin(PI * t)


func _piece_at(s: float, lat: float) -> int:
	var ci0 := M.gl_crack_at(s, lat, 0.16)
	if ci0 < 0:
		return -1
	for i in _pieces_of.get(ci0, []):
		var pc: Dictionary = pieces[i]
		if not bool(pc["ok"]):
			continue
		if lat < float(pc["la"]) - 0.8 or lat > float(pc["lb"]) + 0.8:
			continue
		var ci := int(pc["ci"])
		var sp := M.gl_span(cr[ci], lat)
		if is_nan(sp.x) or s < sp.x - 0.15 or s > sp.y + 0.15:
			continue
		var t := clampf((s - sp.x) / maxf(sp.y - sp.x, 0.01), 0.0, 1.0)
		if lat >= float(pc["la"]) + _bnd(ci, float(pc["la"]), t) and lat <= float(pc["lb"]) + _bnd(ci, float(pc["lb"]), t):
			return i
	return -1


# ---------------------------------------------------------------------------
#  Стойки у входа и выхода: верёвки (бухты), щупы, табличка
# ---------------------------------------------------------------------------

func _build_stations(b: Node3D) -> void:
	for st in 2:
		var s := -7.0 if st == 0 else M.GL_LEN + 7.0
		var u := M.GL_U0 + s / M.len_per_u(M.GL_U0)
		var hin := M.half_in(u)
		var p := M.point(u) - M.outward(u) * (hin - 1.2)
		p.y = M.height(u)
		var t := M.tangent(u)
		var o := M.outward(u)
		if st == 0:
			_rack_a = p + o * 0.8
			_start = M.point(u) + Vector3.UP * 0.6
			_start.y = M.height(u) + 0.6
		else:
			_rack_b = p + o * 0.8
			_exit = M.point(u)
			_exit.y = M.height(u) + 0.6
		var bs := Basis(t, Vector3.UP, t.cross(Vector3.UP))
		for sx in [-0.8, 0.8]:
			b.beam(p + t * sx, p + t * sx + Vector3.UP * 1.9, 0.06, "wood_dark", 6)
		b.beam(p - t * 0.85 + Vector3.UP * 1.75, p + t * 0.85 + Vector3.UP * 1.75, 0.05, "wood_dark", 6)
		b.beam(p - t * 0.85 + Vector3.UP * 0.9, p + t * 0.85 + Vector3.UP * 0.9, 0.04, "wood_dark", 6)
		# бухты верёвки (оранжевые кольца) на перекладине
		for k in 3:
			var cc := p + t * (-0.5 + k * 0.5) + Vector3.UP * 1.45
			for r in 6:
				var a0 := TAU * r / 6.0
				var a1 := TAU * (r + 1) / 6.0
				var ring := Basis(t, Vector3.UP, t.cross(Vector3.UP))
				b.beam(cc + ring * Vector3(0, cos(a0), sin(a0)) * 0.22, cc + ring * Vector3(0, cos(a1), sin(a1)) * 0.22, 0.03, "paint_red", 4)
		# ледорубы, прислонённые к раме
		var spr = mtn.get("spires")
		for k2 in 3:
			if spr == null or not spr.has_method("_axe_into"):
				break
			var ax := Node3D.new()
			add_child(ax)
			spr._axe_into(ax)
			var bot := p + t * (-0.5 + k2 * 0.45) + o * 0.42
			var zz := (Vector3.DOWN * 0.9 + o * 0.35).normalized()
			ax.global_transform = Transform3D(Basis(t.cross(zz).normalized(), t, zz).orthonormalized(), bot + Vector3.UP * 0.02 - zz * 0.0)
		b.box(Vector3(1.9, 0.08, 0.5), p + Vector3.UP * 0.04 + o * 0.1, bs, "planks")
		pass                                     # шаг 91: табличку на столбе (висела над землёй) убрал — подсказки у стойки


func in_field(p: Vector3) -> bool:
	var q := M.gl_local(p.x, p.z)
	return not is_nan(q.x) and q.x > -0.5 and q.x < M.GL_LEN + 0.5 and q.y > -M.GL_IN - 1.0 and q.y < M.GL_OUT + 1.0 \
		and absf(p.y - M.gl_line(clampf(q.x, 0.0, M.GL_LEN))) < 40.0


# ---------------------------------------------------------------------------
#  Шаг 95: связка до 4 человек (одна верёвка, по порядку обвязки)
# ---------------------------------------------------------------------------

func _team_of(pid: int) -> Array:
	for tm in teams:
		if (tm as Array).has(pid):
			return tm
	return []


func _linked(pid: int) -> bool:
	return not _team_of(pid).is_empty()


## Соседи по верёвке (до двух)
func _neighbors(pid: int) -> Array:
	var tm := _team_of(pid)
	var out: Array = []
	var i := tm.find(pid)
	if i > 0:
		out.append(tm[i - 1])
	if i >= 0 and i < tm.size() - 1:
		out.append(tm[i + 1])
	return out


func try_socket(d: Node3D) -> bool:
	var p := d.global_position
	var pid := int(d.peer_id)
	if p.distance_to(_rack_a) < 2.2:
		# шаг 96: E у стойки — обвязываюсь сам (обвязка, верёвка, ледоруб); с кем идти — потом ЛКМ по напарнику
		if tied.has(pid):
			_say_to(d, "Ты обвязан. Подойди к напарнику (он тоже обвязан) и нажми ЛКМ — пристегнуться к нему")
			return true
		if d.snow.busy():
			return true
		d.snow.start_scripted(15, self, {"o": -1, "T": 1.0, "rack": true})
		return true
	if p.distance_to(_rack_b) < 2.2 and tied.has(pid):
		_ask_tie(pid, false)
		return true
	return false


func _say_to(d: Node3D, msg: String) -> void:
	if d == Network.local_player:
		mtn.say(msg)


func _ask_tie(pid: int, on: bool) -> void:
	if multiplayer.is_server():
		_req_tie(pid, on)
	else:
		_req_tie.rpc_id(1, pid, on)


func _ask_link(a: int, b: int, on: bool, why := 0) -> void:
	if multiplayer.is_server():
		_req_link(a, b, on, why)
	else:
		_req_link.rpc_id(1, a, b, on, why)


## Связка без pid; если он был в середине — верёвка рвётся на две (отцепился от обоих)
func _without(nt: Array, pid: int, split: bool) -> Array:
	var out: Array = []
	for tm in nt:
		var arr: Array = tm
		var i := arr.find(pid)
		if i < 0:
			out.append(arr.duplicate())
			continue
		if split:
			var left := arr.slice(0, i)
			var right := arr.slice(i + 1)
			if left.size() >= 2:
				out.append(left)
			if right.size() >= 2:
				out.append(right)
		else:
			var rest := arr.duplicate()
			rest.erase(pid)
			if rest.size() >= 2:
				out.append(rest)
	return out


@rpc("any_peer", "call_remote", "reliable")
func _req_tie(pid: int, on: bool) -> void:
	if not multiplayer.is_server():
		return
	var td := tied.duplicate()
	var nt := teams
	if on:
		td[pid] = true
		# боты-спутники у стойки обвязываются сами
		for o in get_tree().get_nodes_in_group("player"):
			var od := o as Node3D
			if bool(od.get("is_bot")) and not bool(od.get("is_dead")) and od.global_position.distance_to(_rack_a) < 8.0:
				td[int(od.peer_id)] = true
	else:
		td.erase(pid)
		nt = _without(teams, pid, true)
	_rpc_all("_set_teams", [nt, td.keys(), 0 if on else 3])
	_rescue_prune()


@rpc("any_peer", "call_remote", "reliable")
func _req_link(a: int, b: int, on: bool, why := 0) -> void:
	if not multiplayer.is_server():
		return
	var nt: Array = teams.duplicate(true)
	var td := tied.duplicate()
	if on:
		if not tied.has(a) or not tied.has(b):
			return
		var ta: Array = _team_of(a).duplicate()
		var tb: Array = _team_of(b).duplicate()
		if not ta.is_empty() and ta == tb:
			return
		if ta.is_empty():
			ta = [a]
		if tb.is_empty():
			tb = [b]
		if ta.size() + tb.size() > 4:
			return
		# пристёгиваюсь к краю связки: a — в конец своей, b — в начало своей
		if ta[0] == a and ta.size() > 1:
			ta.reverse()
		if tb[tb.size() - 1] == b and tb.size() > 1:
			tb.reverse()
		if ta[ta.size() - 1] != a or tb[0] != b:
			return
		var keep: Array = []
		for tm in nt:
			if not (tm as Array).has(a) and not (tm as Array).has(b):
				keep.append(tm)
		keep.append(ta + tb)
		nt = keep
	else:
		nt = _without(nt, a, why == 2)
		if why == 1:
			td.erase(a)
	_rpc_all("_set_teams", [nt, td.keys(), why])
	_rescue_prune()


## why: 0 — пристегнулся/обвязался, 1 — погиб/ушёл, 2 — отцепился (Q), 3 — отвязался у стойки
@rpc("authority", "call_local", "reliable")
func _set_teams(nt: Array, td: Array, why: int) -> void:
	var was_t := {}
	for tm in teams:
		for pid in tm:
			was_t[int(pid)] = true
	var was := tied.duplicate()
	var now := {}
	for pid1 in td:
		now[int(pid1)] = true
	var now_t := {}
	for tm2 in nt:
		for pid2 in tm2:
			now_t[int(pid2)] = true
	var old_n := _team_of(int(Network.local_player.peer_id)).size() if Network.local_player else 0
	teams = nt
	tied = now
	var me = Network.local_player
	var mine := int(me.peer_id) if me else -1
	for pid3 in was.keys():
		if not now.has(pid3):
			var d: Node3D = mtn.drone_by_id(int(pid3))
			if d:
				d.set("glacier_probe", false)
			_gear(int(pid3), false)
			if int(pid3) == mine:
				mtn.say("Связка развязалась. Вернись к стойке у входа и обвяжись снова (E)" if why == 1 else "Отвязался. Верёвка и ледоруб — на стойке")
	for pid4 in now.keys():
		if not was.has(pid4):
			var d2: Node3D = mtn.drone_by_id(int(pid4))
			if d2:
				d2.set("glacier_probe", true)
				SFX.play(self, d2.global_position + Vector3.UP, "latch", -8.0, 0.9)
			_gear(int(pid4), true)
			if int(pid4) == mine:
				mtn.say("Обвязался: верёвка и ледоруб. Подойди к напарнику и нажми ЛКМ — пристегнуться")
	for pid5 in now_t.keys():
		if not was_t.has(pid5):
			var d3: Node3D = mtn.drone_by_id(int(pid5))
			if d3:
				SFX.play(self, d3.global_position + Vector3.UP * 1.0, "clank", -10.0, 1.4)
	if mine >= 0:
		var n := _team_of(mine).size()
		if n >= 2 and n != old_n:
			mtn.say("В связке %d на одной верёвке. Сорвётся кто-то — СРАЗУ ЛКМ: ледоруб в снег!" % n)
		elif n == 0 and old_n >= 2 and now.has(mine):
			mtn.say("Отцепился от связки — ты сам по себе. Снова пристегнуться — ЛКМ по напарнику" if why == 2 else "Связка распалась")
	# верёвки: лишние убираю, новые рисуются в visual()
	var keep := {}
	for tm3 in teams:
		for k in (tm3 as Array).size() - 1:
			keep[_pair_key(int(tm3[k]), int(tm3[k + 1]))] = true
	for key in _rope_vis.keys():
		if not keep.has(key):
			_rope_free(key)


func _pair_key(a: int, b: int) -> String:
	return "%d_%d" % [mini(a, b), maxi(a, b)]


# ---------------------------------------------------------------------------
#  Каждый кадр: мой дрон (не занят горой)
# ---------------------------------------------------------------------------

func local(d: Node3D, _hp: String, _holding: bool, delta: float) -> void:
	var p := d.global_position
	var pid := int(d.peer_id)
	for nb in _neighbors(pid):
		_rope_pull(d, int(nb), delta)
	var q := M.gl_local(p.x, p.z)
	if is_nan(q.x):
		return
	var on_gl := q.x > -0.5 and q.x < M.GL_LEN + 0.5 and q.y > -M.GL_IN - 1.0 and q.y < M.GL_OUT + 1.0
	if (q.x > M.GL_LEN + 40.0 or q.x < -40.0) and multiplayer.is_server():
		if tied.has(pid):
			_req_tie(pid, false)
		elif _linked(pid):
			_req_link(pid, -1, false)
	var near_gl := q.x > -14.0 and q.x < M.GL_LEN + 14.0
	# шаг 96: ЛКМ по обвязанному напарнику — пристегнуться к нему; Q (пустые руки) — отцепиться от всех
	if near_gl and tied.has(pid) and not bool(d.get("is_bot")):
		if _pressed(d, 0) and _hands_free(d):
			_try_clip(d)
		elif d._just("throw") and not d._can_throw() and _linked(pid):
			_ask_link(pid, -1, false, 2)
			SFX.play(self, p + Vector3.UP * 1.0, "latch", -6.0, 0.8)
	if not on_gl:
		return
	if not _cp_set.has(pid) and d.has_method("set_checkpoint"):
		_cp_set[pid] = true
		d.set_checkpoint(_start)
	d.set("impact_soft", true)
	var g := M.gl_h(clampf(q.x, 0.0, M.GL_LEN), q.y)
	# шаг 96: наступил на скрытый мост — рушится сразу (хоть бегом): у себя мгновенно, хост — для всех
	if p.y > g - 0.4 and p.y < g + 0.7:
		# под всей ступнёй (капсула шире точки): соседний кусок тоже рушится — не стою на его краю
		for off in [Vector2.ZERO, Vector2(0.38, 0.0), Vector2(-0.38, 0.0), Vector2(0.0, 0.38), Vector2(0.0, -0.38)]:
			var pi := _piece_at(q.x + off.x, q.y + off.y)
			if pi >= 0 and String(pieces[pi]["kind"]) != "strong":
				_collapse(pi)
				if multiplayer.is_server():
					_rpc_all("_collapse", [pi])
				else:
					_req_collapse.rpc_id(1, pi)
				_drop[pid] = [int(pieces[pi]["ci"]), 0.0]
	# шаг 96б: стою над щелью (открытая трещина, рухнувший мост) — сразу вниз, даже бегом и в узкой
	if not _drop.has(pid) and p.y < g + 0.35 and p.y > g - 0.9:
		var c0 := M.gl_crack_at(q.x, q.y, 0.0)
		if c0 >= 0 and _piece_at(q.x, q.y) < 0:
			var spc := M.gl_span(cr[c0], q.y)
			if spc.y - spc.x > 0.3:
				_drop[pid] = [c0, 0.0]
	if _drop.has(pid):
		_drop_pull(d, q, delta)
	var ci := M.gl_crack_at(q.x, q.y, 0.5)
	if p.y < g - 4.0 and (ci >= 0 or M.gl_crack_at(q.x, q.y, 2.5) >= 0):
		_drop_end(d)
		if d.has_method("kill"):
			d.kill("Провалился в трещину!\nБез связки (или не удержали) ледник не прощает.\nОбвяжись у стойки (E) и пристегнись к напарнику (ЛКМ)")
		return
	if ci >= 0 and p.y < g - 0.9 and p.y > g - 3.95 and not d.snow.busy() and not _no_catch.has(pid):
		_fall(d, ci, q)
		if d.snow.busy():
			_drop_end(d)
			return
		_no_catch[pid] = true
	if ci < 0 or p.y > g - 0.5:
		_no_catch.erase(pid)


## Мост рухнул под ногами: бег гасится, тело уходит в дыру (не повисаю на краю капсулой)
func _drop_pull(d: Node3D, q: Vector2, delta: float) -> void:
	var pid := int(d.peer_id)
	var e: Array = _drop[pid]
	e[1] = float(e[1]) + delta
	if float(e[1]) > 2.0 or d.snow.busy():
		_drop_end(d)
		return
	var sp := M.gl_span(cr[int(e[0])], q.y)
	if is_nan(sp.x):
		_drop_end(d)
		return
	var hw := (sp.y - sp.x) * 0.5
	# узкая — тело шире щели: края не держат (иначе застрял бы капсулой поперёк)
	if hw < 0.5 and not _exc.has(pid):
		_exc[pid] = true
		_set_exc(d, true)
	var mid := (sp.x + sp.y) * 0.5
	var m := maxf(hw - 0.42, 0.0)
	var ts := clampf(q.x, mid - m, mid + m)
	var to := W(ts, q.y) - d.global_position
	to.y = 0.0
	d.global_position += to                # бег не вынесет на тот край: держу над дырой, пока не провалился
	d.velocity.x = 0.0
	d.velocity.z = 0.0
	d.velocity.y = minf(d.velocity.y, -3.0)


func _drop_end(d: Node3D) -> void:
	var pid := int(d.peer_id)
	_drop.erase(pid)
	if _exc.has(pid):
		_exc.erase(pid)
		_set_exc(d, false)


func _set_exc(d: Node3D, on: bool) -> void:
	var cb := d as CollisionObject3D
	if cb == null or not (d is PhysicsBody3D):
		return
	for nm in ["GlacierBody", "CrackWalls"]:
		var n := get_node_or_null(nm)
		if n is PhysicsBody3D:
			if on:
				(d as PhysicsBody3D).add_collision_exception_with(n)
			else:
				(d as PhysicsBody3D).remove_collision_exception_with(n)


@rpc("any_peer", "call_remote", "reliable")
func _req_collapse(pi: int) -> void:
	if multiplayer.is_server() and pi >= 0 and pi < pieces.size():
		_rpc_all("_collapse", [pi])


func _at_end(pid: int) -> bool:
	var tm := _team_of(pid)
	return tm.size() < 2 or int(tm[0]) == pid or int(tm[tm.size() - 1]) == pid


func _hands_free(d: Node3D) -> bool:
	return d.get("held_parcel") == null and d.get("held_friend") == null and d.get("held_limb") == null \
		and d.get("rolling_block") == null and d.snow.held_bot == null


## ЛКМ: ближайший обвязанный напарник впереди (до 2.6 м) — пристёгиваюсь (анимация, потом связка)
func _try_clip(d: Node3D) -> void:
	var pid := int(d.peer_id)
	var fw := -(d.visual as Node3D).global_basis.z
	var cam := get_viewport().get_camera_3d()
	if cam:
		fw = -cam.global_basis.z
	fw.y = 0.0
	fw = fw.normalized()
	var best: Node3D = null
	var bs := -1.0
	var untied_near := false
	for o in get_tree().get_nodes_in_group("player"):
		var od := o as Node3D
		if od == d or bool(od.get("is_dead")):
			continue
		var to := od.global_position - d.global_position
		to.y = 0.0
		var dist := to.length()
		if dist > 2.6 or dist < 0.05 or absf(od.global_position.y - d.global_position.y) > 1.5:
			continue
		var sc := to.normalized().dot(fw)
		if sc < 0.35:
			continue
		if not tied.has(int(od.peer_id)):
			untied_near = true
			continue
		if _team_of(pid).has(int(od.peer_id)):
			continue
		if sc > bs:
			bs = sc
			best = od
	if best == null:
		if untied_near:
			_say_to(d, "Напарник не обвязан — пусть возьмёт верёвку у стойки (E)")
		return
	var na := maxi(_team_of(pid).size(), 1)
	var nb := maxi(_team_of(int(best.peer_id)).size(), 1)
	if not _at_end(pid) or not _at_end(int(best.peer_id)):
		_say_to(d, "Пристегнуться можно только к краю связки (к первому или последнему)")
		return
	if na + nb > 4:
		_say_to(d, "На одной верёвке — не больше четырёх")
		return
	d.snow.start_scripted(15, self, {"o": int(best.peer_id), "T": 1.0})


## Верёвка держит крепко: иду — тащу соседа (тяжелее идти); тянем в разные стороны — стоим
func _rope_pull(d: Node3D, opid: int, delta: float) -> void:
	var o: Node3D = mtn.drone_by_id(opid)
	if o == null or bool(o.get("is_dead")) or o.snow.busy():
		return
	var to := o.global_position - d.global_position
	to.y = 0.0
	var dist := to.length()
	if dist <= ROPE_L or dist < 0.01:
		return
	var n := to / dist
	var ex := dist - ROPE_L
	var hv := Vector3(d.velocity.x, 0.0, d.velocity.z)
	var away := -hv.dot(n)
	if away > 0.4:
		d.global_position += n * away * delta * 0.5
		if ex > 0.3:
			d.global_position += n * minf((ex - 0.3) * 0.5, 4.0 * delta)
			d.velocity += n * away
	else:
		# меня тянет: волочёт следом (только положением — скорость не копится)
		d.global_position += n * minf(ex * 0.6, 6.0 * delta)


func _pressed(d: Node3D, h: int) -> bool:
	if bool(d.get("is_bot")):
		return false
	return d._just("use_item" if h == 0 else "use_alt")


# ---------------------------------------------------------------------------
#  Хост: мосты, посылка, погибшие — из связки; спасение
# ---------------------------------------------------------------------------

func server(delta: float) -> void:
	var on_now := {}
	for d in get_tree().get_nodes_in_group("player"):
		var dn := d as Node3D
		if bool(dn.get("is_dead")):
			continue
		var p := dn.global_position
		var q := M.gl_local(p.x, p.z)
		if is_nan(q.x) or q.x < 0.0 or q.x > M.GL_LEN:
			continue
		var pi := _piece_at(q.x, q.y)
		if pi < 0 or String(pieces[pi]["kind"]) == "strong":
			continue
		if absf(p.y - M.gl_h(q.x, q.y)) > 0.7:
			continue
		on_now[pi] = true
		if not _press.has(pi):
			_press[pi] = 0.0
			_rpc_all("_crack_fx", [pi])
		_press[pi] = float(_press[pi]) + delta
		var lim := 0.12 if String(pieces[pi]["kind"]) == "hidden" else WEAK_T     # шаг 96: скрытый рушится у самого игрока сразу; это — запас
		if float(_press[pi]) > lim:
			_press.erase(pi)
			_rpc_all("_collapse", [pi])
	for k in _press.keys():
		if not on_now.has(k):
			_press[k] = float(_press[k]) - delta * 2.0
			if float(_press[k]) <= 0.0:
				_press.erase(k)
	var last: Vector3 = mtn.get("_parcel_last")
	if last != Vector3.INF:
		var ql := M.gl_local(last.x, last.z)
		if not is_nan(ql.x) and ql.x > -1.0 and ql.x < M.GL_LEN + 1.0 and M.gl_crack_at(ql.x, ql.y, 1.0) >= 0:
			mtn.set_parcel_last(_start + Vector3.UP * 0.3)
	# погиб (или вышел) — из связки; после возрождения — снова к стойке
	for tm in teams:
		for pid in tm:
			var dl: Node3D = mtn.drone_by_id(int(pid))
			if dl == null or bool(dl.get("is_dead")):
				_req_link(int(pid), -1, false, 1)
				return
	for pid2 in tied.keys():
		var dt: Node3D = mtn.drone_by_id(int(pid2))
		if dt == null or bool(dt.get("is_dead")):
			_req_link(int(pid2), -1, false, 1)
			return
	_rescue_server(delta)


func _rpc_all(fn: String, args: Array) -> void:
	if mtn._online():
		callv("rpc", [fn] + args)
	else:
		callv(fn, args)


@rpc("authority", "call_local", "reliable")
func _crack_fx(pi: int) -> void:
	var pc: Dictionary = pieces[pi]
	var c: Array = cr[int(pc["ci"])]
	var lat := (float(pc["la"]) + float(pc["lb"])) * 0.5
	var sp := M.gl_span(c, lat)
	var at := W((sp.x + sp.y) * 0.5 if not is_nan(sp.x) else float(c[0]), lat)
	SFX.play(self, at, "crunch", -6.0, 1.2)               # снег под ногой хрустнул
	var me = Network.local_player
	if me and me.global_position.distance_to(at) < 4.0:
		me.add_shake(0.12)


@rpc("authority", "call_local", "reliable")
func _collapse(pi: int) -> void:
	var pc: Dictionary = pieces[pi]
	if not bool(pc["ok"]):
		return
	pc["ok"] = false
	var node: Node3D = pc["node"]
	var body: StaticBody3D = pc["body"]
	body.process_mode = Node.PROCESS_MODE_DISABLED
	for ch in body.get_children():
		if ch is CollisionShape3D:
			(ch as CollisionShape3D).disabled = true
	var mi: MeshInstance3D = node.get_child(0)
	var at := mi.get_aabb().get_center()
	SFX.play(self, at, "crunch", 0.0, 0.8)                # мост провалился: глухой хруст снега
	SFX.play(self, at, "puff", -4.0, 0.7)
	_puff.global_position = at
	_puff.restart()
	# обломки летят вниз, кувыркаясь
	var tw := create_tween()
	tw.set_parallel(true)
	# шаг 90: обломки уходят вниз быстрее падающего — от 1-го лица не оказываюсь внутри снежной плиты
	tw.tween_property(node, "position:y", node.position.y - 25.0, 0.8).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(node, "rotation:z", 0.5, 0.8)
	tw.chain().tween_callback(func() -> void: node.visible = false)


func _hang_pos(r: Dictionary, depth: float, mode: String) -> Vector3:
	var ci := int(r["ci"])
	var lat := float(r["lat"])
	var side := float(r["side"])
	var sp := M.gl_span(cr[ci], lat)
	var hw := (sp.y - sp.x) * 0.5
	# шаг 90: от видимой стенки (с козырьком, выщербинами) — на всю высоту тела; голова не влезает в лёд
	var near := 0.0
	var far := 0.0
	for dd in [0.0, 0.5, 1.0, 1.5, 1.9]:
		var dv := depth + float(dd)
		near = maxf(near, _vis_off(ci, dv, hw, lat))
		far = maxf(far, _vis_off(ci, dv, hw, lat + 0.37))
	var s0 := near + (0.5 if mode == "self" else 1.2)
	var lim := maxf(hw * 2.0 - far - 0.45, hw)          # и от задней стенки не меньше 0.45
	s0 = minf(s0, lim)
	var s := (sp.x + s0) if side < 0.0 else (sp.y - s0)
	return W(s, lat, -depth - 1.85)


func _drive_out(d: Node3D, t: float, data: Dictionary) -> void:
	var k := clampf(t / 1.3, 0.0, 1.0)
	var from: Vector3 = data["from"]
	var edge: Vector3 = data["edge"]
	var dest: Vector3 = data["dest"]
	var n: Vector3 = data["n"]
	# шаг 90: подтянулся под край (отступив от козырька) → перевалился грудью через край → встал
	var mid := edge + Vector3.DOWN * 1.0 - n * 0.7
	var top := edge + Vector3.UP * 0.1 + n * 0.15
	var pos: Vector3
	if k < 0.45:
		pos = from.lerp(mid, smoothstep(0.0, 1.0, k / 0.45))
	elif k < 0.75:
		var u := smoothstep(0.0, 1.0, (k - 0.45) / 0.3)
		pos = mid.lerp(top, u) - n * 0.25 * sin(u * PI)
	else:
		pos = top.lerp(dest, smoothstep(0.0, 1.0, (k - 0.75) / 0.25)) + Vector3.UP * sin((k - 0.75) / 0.25 * PI) * 0.12
	d.global_position = pos
	d.velocity = Vector3.ZERO
	d.visual.rotation.y = atan2(-n.x, -n.z)
	d.snow.set_mpose(19, k, edge, n)
	if d == Network.local_player:
		d.set("fp_roll", lerpf(float(d.get("fp_roll")), 0.0, 0.1))
	if k >= 1.0:
		d.snow.end_scripted()
		d.snow.set_mpose(0)
		d.set("fp_roll", 0.0)


## Шаг 90: взгляд от 1-го лица в трещине: камера ведёт сама (база), мышью можно чуть отвести — плавно вернётся
func _fp_look(d: Node3D, data: Dictionary, yaw_b: float, pitch_b: float, roll: float, rate: float, delta: float) -> void:
	var pv: Node3D = d.get("camera_pivot")
	if pv == null:
		return
	var dt := delta if delta > 0.0 else 1.0 / 60.0
	if not data.has("fyaw"):
		data["fyaw"] = pv.rotation.y
		data["fpitch"] = pv.rotation.x
	# сколько отвёл мышью с прошлого кадра
	var dev_y := clampf(wrapf(pv.rotation.y - float(data["fyaw"]), -PI, PI), -0.7, 0.7)
	var dev_p := clampf(pv.rotation.x - float(data["fpitch"]), -0.45, 0.45)
	dev_y *= 1.0 - clampf(dt * 0.8, 0.0, 1.0)
	dev_p *= 1.0 - clampf(dt * 0.8, 0.0, 1.0)
	var a := clampf(dt * rate, 0.0, 1.0)
	var by := lerp_angle(float(data["fyaw"]), yaw_b, a)
	var bp := lerpf(float(data["fpitch"]), pitch_b, a)
	data["fyaw"] = by
	data["fpitch"] = bp
	pv.rotation.y = by + dev_y
	pv.rotation.x = clampf(bp + dev_p, -1.4, 1.3)
	d.set("fp_roll", lerpf(float(d.get("fp_roll")), roll, a))


## Куда вонзается ледоруб: перед головой, чуть левее (лежу головой к трещине)
func _axe_snow(d: Node3D, dir: Vector3) -> Vector3:
	var left := Vector3.UP.cross(dir).normalized()
	var hd := _head(d, dir)
	var p := hd + dir * 0.6 + left * 0.2
	var q := M.gl_local(p.x, p.z)
	if not is_nan(q.x):
		p.y = M.gl_h(clampf(q.x, 0.0, M.GL_LEN), q.y)
	return p


## Где правая рука держит верёвку: cyc 0…0.5 — тяну к себе, 0.5…1 — тянусь вперёд за новым хватом
func _rope_grip(d: Node3D, dir: Vector3, cyc: float) -> Vector3:
	var right := dir.cross(Vector3.UP).normalized()
	var reach := 0.42
	var lift := 0.0
	if cyc > 0.0:
		if cyc < 0.5:
			reach = lerpf(0.5, -0.15, smoothstep(0.0, 0.5, cyc))
		else:
			var u := (cyc - 0.5) / 0.5
			reach = lerpf(-0.15, 0.5, smoothstep(0.0, 1.0, u))
			lift = 0.14 * sin(u * PI)
	var hd := _head(d, dir)
	return Vector3(hd.x, d.global_position.y, hd.z) + Vector3.UP * (0.2 + lift) + dir * reach + right * 0.24


## Голова лежащего (на животе): по ходу, у снега
func _head(d: Node3D, dir: Vector3) -> Vector3:
	var suit = d.get("suit")
	if suit != null and suit.get("head") != null and float(d.get("force_belly")) > 0.8:
		var h: Vector3 = (suit.get("head") as Node3D).global_position
		h.y = d.global_position.y
		return h
	return d.global_position + dir * 0.9


func _rope_free(key: String) -> void:
	if _rope_vis.has(key):
		var r: Dictionary = _rope_vis[key]
		for nk in ["mi", "k0", "k1"]:
			if is_instance_valid(r.get(nk)):
				(r[nk] as Node3D).queue_free()
		_rope_vis.erase(key)


## Кулак i (середина хвата) — по нему идёт верёвка
func _fist(d: Node3D, i: int, fallback: Vector3) -> Vector3:
	var su = d.get("suit")
	if su != null and su.has_method("fist_pos"):
		return su.fist_pos(i)
	return fallback


## Где руки (середина между ладонями) — через них идёт верёвка
func _hands_of(d: Node3D) -> Vector3:
	var su = d.get("suit")
	if su != null and su.get("_arms") != null:
		var arms: Array = su.get("_arms")
		if arms.size() >= 2:
			var h0 := arms[0]["hand"] as Node3D
			var h1 := arms[1]["hand"] as Node3D
			if h0 and h1:
				return (h0.global_position + h1.global_position) * 0.5
	return d.global_position + Vector3.UP * 1.75


## Точки ломаной → N+1 точек поровну по длине
func _resample(poly: Array, n: int) -> Array:
	var lens: Array = [0.0]
	for i in poly.size() - 1:
		lens.append(float(lens[i]) + (poly[i] as Vector3).distance_to(poly[i + 1]))
	var total := float(lens[lens.size() - 1])
	var out: Array = []
	var j := 0
	for k in n + 1:
		var at := total * float(k) / n
		while j < poly.size() - 2 and float(lens[j + 1]) < at:
			j += 1
		var seg := maxf(float(lens[j + 1]) - float(lens[j]), 0.0001)
		out.append((poly[j] as Vector3).lerp(poly[j + 1], clampf((at - float(lens[j])) / seg, 0.0, 1.0)))
	return out


## Снаряжение: ледоруб в левой руке
func _gear(pid: int, on: bool) -> void:
	if _axe_vis.has(pid):
		for n2 in _axe_vis[pid]:
			if is_instance_valid(n2):
				(n2 as Node3D).queue_free()
		_axe_vis.erase(pid)
	if not on:
		return
	var d: Node3D = mtn.drone_by_id(pid)
	if d == null:
		return
	var suit = d.get("suit")
	var lgrip := Node3D.new()
	if suit != null and suit.has_method("attach_to_hand"):
		suit.attach_to_hand(0, lgrip)
	else:
		d.add_child(lgrip)
	var axe := Node3D.new()
	lgrip.add_child(axe)                        # шаг 91: ледоруб — в кулаке (как у скал): рукоять через кулак
	var sp = mtn.get("spires")
	if sp != null and sp.has_method("_axe_into"):
		sp._axe_into(axe)
	# шаг 96: бухта верёвки через плечо (запас верёвки) и обвязка
	# шаг 96б: запас верёвки — плотными витками вокруг пояса (над обвязкой), не лезет в обзор
	var coil := Node3D.new()
	var pel: Node3D = suit.get("pelvis") if suit != null else null
	if pel != null:
		pel.add_child(coil)
		coil.position = Vector3(0.0, 0.075, 0.0)
	else:
		(d.visual as Node3D).add_child(coil)
		coil.position = Vector3(0.0, 0.98, 0.0)
	for k in 4:
		var ring := MeshInstance3D.new()
		var tor := TorusMesh.new()
		tor.inner_radius = 0.228
		tor.outer_radius = 0.254
		tor.rings = 36
		tor.ring_segments = 6
		ring.mesh = tor
		ring.material_override = _rope_smat if _rope_smat else _rope_mat
		ring.position = Vector3(0.0, k * 0.024, 0.0)
		ring.rotation = Vector3(0.03 * sin(k * 2.1), k * 0.9, 0.03 * cos(k * 1.7))
		ring.scale = Vector3(1.1 + k * 0.012, 1.0, 0.92 + k * 0.012)
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		coil.add_child(ring)
	_axe_vis[pid] = [axe, lgrip, coil]


func _axe_place(pid: int, d: Node3D) -> void:
	if not _axe_vis.has(pid):
		return
	var arr: Array = _axe_vis[pid]
	var axe: Node3D = arr[0]
	var grip: Node3D = arr[1]
	if not is_instance_valid(axe) or not is_instance_valid(grip):
		return
	axe.visible = d.visible
	var fw := -(d.visual as Node3D).global_basis.z
	fw.y = 0.0
	fw = fw.normalized() if fw.length() > 0.01 else Vector3.FORWARD
	var mp := int(d.snow.mpose)
	var g := grip.global_position
	if mp == 21:
		var k := float(d.snow.mpose_k)
		if k >= 0.5:
			# шаг 91: удар и держу — ледоруб лежит в кулаке (кисть сама направлена клювом в снег)
			axe.transform = Transform3D.IDENTITY
			return
		# тащит: ледоруб в кулаке за голову, рукоять торчит вбок-назад
		var lft := Vector3.UP.cross(fw).normalized()
		var z3 := (-fw * 0.55 + lft * 0.75 + Vector3.UP * 0.12).normalized()
		var y3 := Vector3.DOWN.cross(z3).cross(z3).normalized() * -1.0
		var x3 := y3.cross(z3).normalized()
		axe.global_transform = Transform3D(Basis(x3, y3, z3), g + z3 * 0.52)
		return
	# несу: голова в ладони, штычок вниз (как трость)
	var z2 := Vector3.DOWN
	var y2 := fw
	var x2 := y2.cross(z2).normalized()
	axe.global_transform = Transform3D(Basis(x2, y2, z2), g + z2 * 0.52)



# ---------------------------------------------------------------------------
#  Шаг 95: провал и спасение — связкой. Каждый наверху (держатель, H) сам по себе: рывок → у каждого ~0.7 с
#  на ЛКМ; не успел — его утаскивает через край, он тоже повисает (упавший, F). Держат все зарубившиеся:
#  сползание к краю = упавших / держащих (один держит троих — несёт очень быстро). Не держит никто — все вниз.
#   rescue = {team, phase, t, T, ci, lat, side, edge, F: {pid: faller}, H: {pid: holder}}
# ---------------------------------------------------------------------------

func _fall(d: Node3D, ci: int, q: Vector2) -> void:
	var pid := int(d.peer_id)
	if d.get("held_parcel") != null and d.has_method("_release_held"):
		d._release_held((d.get("held_parcel") as Node3D).global_transform, Vector3.ZERO)
	var tm := _team_of(pid)
	if tm.is_empty():
		return                                  # без связки — падает (смерть ниже)
	var near: Node3D = null
	var nd := 1e9
	for m in tm:
		if int(m) == pid:
			continue
		var md: Node3D = mtn.drone_by_id(int(m))
		if md == null or bool(md.get("is_dead")) or int(md.snow.climb) == 12:
			continue
		var dd := md.global_position.distance_to(d.global_position)
		if dd < nd:
			nd = dd
			near = md
	if near == null:
		return                                  # все остальные уже в трещине — вниз
	if not rescue.is_empty():
		var ph0 := String(rescue["phase"])
		if not (rescue["team"] as Array).has(pid) or ph0 == "lost" or (rescue["F"] as Dictionary).has(pid):
			return
	var sp := M.gl_span(cr[ci], q.y)
	var pq2 := M.gl_local(near.global_position.x, near.global_position.z)
	var side := -1.0 if pq2.x < (sp.x + sp.y) * 0.5 else 1.0
	d.snow.start_scripted(12, self, {"ci": ci, "lat": q.y, "side": side, "from": d.global_position})
	if multiplayer.is_server():
		_req_fall(pid, ci, q.y, side)
	else:
		_req_fall.rpc_id(1, pid, ci, q.y, side)


func _new_faller(ci: int, lat: float, side: float, d0: float) -> Dictionary:
	var sp := M.gl_span(cr[ci], lat)
	var es := sp.x - 0.05 if side < 0.0 else sp.y + 0.05
	var nn := _tang(es) * side
	nn.y = 0.0
	return {"ci": ci, "lat": lat, "side": side, "edge": W(es, lat), "n": nn.normalized(),
		"mode": "self" if sp.y - sp.x < SELF_W else "haul", "depth": 0.0, "d0": d0,
		"fall_t": sqrt(2.0 * d0 / 9.8) * 0.75, "st": "fall", "t": 0.0}


func _new_holder(hd: Node3D, edge: Vector3) -> Dictionary:
	var hp := hd.global_position
	var to := edge - hp
	to.y = 0.0
	var dist := to.length()
	var dir := to / dist if dist > 0.05 else -(hd.visual as Node3D).global_basis.z
	dir.y = 0.0
	return {"from": hp, "dir": dir.normalized(), "rem": maxf(dist - 0.8, 0.0), "tr": 0.0, "tr0": 0.0, "ta": 0.0, "tex": 0.0,
		"win": WIN1, "st": "wait", "t": 0.0, "grip": 1.0, "rs": -1.0, "pre": false, "close": dist < 1.5, "rips": 0,
		"near": dist < NEAR_D, "miss_t": -1.0, "pid": int(hd.peer_id),
		"v0": -1.0, "hc": 0.0}


@rpc("any_peer", "call_remote", "reliable")
func _req_fall(pid: int, ci: int, lat: float, side: float) -> void:
	if not multiplayer.is_server():
		return
	var f0: Node3D = mtn.drone_by_id(pid)
	if f0 == null:
		return
	if not rescue.is_empty() and String(rescue["phase"]) != "out":
		# ещё один из связки сорвался, пока спасаем: повис рядом
		if String(rescue["phase"]) == "lost" or not (rescue["team"] as Array).has(pid) or (rescue["F"] as Dictionary).has(pid):
			return
		(rescue["F"] as Dictionary)[pid] = _new_faller(ci, lat, side, 1.0)
		(rescue["H"] as Dictionary).erase(pid)
		_send_rescue(rescue)
		return
	var tm := _team_of(pid).duplicate()
	var sp := M.gl_span(cr[ci], lat)
	var es := sp.x - 0.05 if side < 0.0 else sp.y + 0.05
	var edge := W(es, lat)
	var H := {}
	var slack := ROPE_L
	for m in tm:
		if int(m) == pid:
			continue
		var md: Node3D = mtn.drone_by_id(int(m))
		if md == null or bool(md.get("is_dead")):
			continue
		H[int(m)] = _new_holder(md, edge)
		var fh := md.global_position - f0.global_position
		fh.y = 0.0
		slack = minf(slack, clampf(ROPE_L - fh.length(), 0.0, ROPE_L))
	if H.is_empty():
		return
	var d0 := 0.9 + slack * 0.15
	var fl := _new_faller(ci, lat, side, d0)
	# шаг 95: время сползания 8–11 с (на 1 упавшего и 1 держащего): шире трещина и глубже упал — быстрее
	var kk := clampf((sp.y - sp.x - 1.4) / 1.6, 0.0, 1.0) * 0.6 + clampf((d0 - 0.9) / 1.2, 0.0, 1.0) * 0.4
	var r := {"team": tm, "phase": "fall", "t": 0.0, "T": lerpf(11.0, 8.5, kk), "ci": ci, "lat": lat, "side": side,
		"edge": edge, "F": {pid: fl}, "H": H}
	_send_rescue(r)


func _send_rescue(r: Dictionary) -> void:
	var c := r.duplicate(true)
	if mtn._online():
		_rescue_set.rpc(c)
	else:
		_rescue_set(c)


@rpc("authority", "call_local", "reliable")
func _rescue_set(r: Dictionary) -> void:
	_apply_rescue(r, true)


@rpc("authority", "call_remote", "unreliable_ordered")
func _rescue_sync(r: Dictionary) -> void:
	_apply_rescue(r, false)


func _apply_rescue(r: Dictionary, loud: bool) -> void:
	var was_ph := String(rescue.get("phase", ""))
	rescue = r
	if r.is_empty():
		_st_last.clear()
		_ph_t = 0.0
		return
	var ph := String(r["phase"])
	if ph != was_ph:
		_ph_t = 0.0
	var me = Network.local_player
	var mine := int(me.peer_id) if me else -1
	var in_team := (r["team"] as Array).has(mine)
	var H: Dictionary = r["H"]
	var F: Dictionary = r["F"]
	for hp in H.keys():
		var h: Dictionary = H[hp]
		var key := "H:" + String(h["st"])
		if String(_st_last.get(hp, "")) != key:
			_st_last[hp] = key
			_st_t[hp] = 0.0
			var hd: Node3D = mtn.drone_by_id(int(hp))
			if hd and bool(hd.get("is_local")) and int(hd.snow.climb) != 13 and String(h["st"]) in ["wait", "drag", "anchor", "hold"]:
				if hd.snow.busy():
					hd.snow.end_scripted()
				_strike_t.erase(int(hp))
				hd.snow.start_scripted(13, self, {"trs": float(h["tr"])})
			if loud and in_team and hd:
				var at := hd.global_position
				match String(h["st"]):
					"drag":
						SFX.play(self, at + Vector3.UP, "thunk", -3.0 if int(hp) == mine else -9.0, 1.35)
						SFX.play(self, at, "snowslide", -3.0 if int(hp) == mine else -10.0, 1.0)
						SFX.play(self, at + Vector3.UP, "rope", -6.0 if int(hp) == mine else -12.0, 1.0)
						if int(hp) == mine:
							me.add_shake(0.55)
					"anchor":
						SFX.play(self, at, "puff", -6.0, 1.2)
						if int(hp) == mine:
							me.add_shake(0.3)
					"over":
						SFX.play(self, at, "snowslide", -2.0, 0.8)
	for fp in F.keys():
		var f: Dictionary = F[fp]
		var key2 := "F:" + String(f["st"])
		if String(_st_last.get(fp, "")) != key2:
			_st_last[fp] = key2
			_st_t[fp] = 0.0
			var fd: Node3D = mtn.drone_by_id(int(fp))
			if fd and bool(fd.get("is_local")) and String(f["st"]) == "fall" and int(fd.snow.climb) != 12:
				# держателя утащило через край — теперь он висит
				if fd.snow.busy():
					fd.snow.end_scripted()
				fd.snow.start_scripted(12, self, {"ci": int(f["ci"]), "lat": float(f["lat"]), "side": float(f["side"]), "from": fd.global_position})
			if loud and in_team and fd and String(f["st"]) == "fall":
				SFX.play(self, f["edge"], "puff", -4.0, 0.9)
	# не удержал никто: все срываются — через миг разбились
	if ph == "lost" and was_ph != "lost":
		for pid in F.keys() + H.keys():
			var dl: Node3D = mtn.drone_by_id(int(pid))
			if dl and bool(dl.get("is_local")):
				var tw := create_tween()
				tw.tween_interval(2.0)
				tw.tween_callback(func() -> void:
					if is_instance_valid(dl) and not bool(dl.get("is_dead")) and dl.has_method("kill"):
						if dl.snow.busy():
							dl.snow.end_scripted()
						dl.kill("Сорвались в трещину всей связкой!\nКогда тянет — сразу ЛКМ: ледоруб в снег"))


@rpc("any_peer", "call_remote", "reliable")
func _req_act(pid: int, what: String, on: bool) -> void:
	if not multiplayer.is_server() or rescue.is_empty():
		return
	var H: Dictionary = rescue["H"]
	var F: Dictionary = rescue["F"]
	match what:
		"arrest":
			if not H.has(pid):
				return
			var h: Dictionary = H[pid]
			match String(h["st"]):
				"wait":
					h["pre"] = true                 # успел ещё до рывка — лёг и зарубился заранее
				"drag":
					if float(h["t"]) - float(h.get("miss_t", -1.0)) < 0.25:
						return                          # шаг 133: только что сорвался ледоруб — замах ещё не готов
					if _arrest_try(h):
						_arrest_h(h)
					_send_rescue(rescue)
				"anchor", "hold":
					h["grip"] = 1.0                 # перевбил ледоруб
					h["rs"] = float(h["t"])
					_send_rescue(rescue)
		"haul":
			if H.has(pid):
				_haul_on[pid] = on
		"climb":
			if F.has(pid) and String(F[pid]["st"]) == "hang" and String(F[pid]["mode"]) == "self" and _n_anchored() > 0:
				F[pid]["depth"] = maxf(float(F[pid]["depth"]) - CLIMB_STEP, 0.0)


func _act(pid: int, what: String, on := true) -> void:
	if multiplayer.is_server():
		_req_act(pid, what, on)
	else:
		_req_act.rpc_id(1, pid, what, on)


func _n_anchored() -> int:
	var n := 0
	for hp in (rescue["H"] as Dictionary).keys():
		if String(rescue["H"][hp]["st"]) in ["anchor", "hold"]:
			n += 1
	return n


## Зарубился: ещё немного проскальзываю (тем больше, чем быстрее тащило)
## Шаг 133: вблизи края на рывке ледоруб берёт не всегда (скользит по насту); чем ближе край — тем хуже
func _arrest_try(h: Dictionary) -> bool:
	if not bool(h.get("near", false)):
		return true
	var left := float(h["rem"]) - float(h["tr"])
	var ch := lerpf(0.45, 0.8, clampf(left / 3.0, 0.0, 1.0))
	if randf() < ch:
		return true
	h["miss_t"] = float(h["t"])
	var hd: Node3D = mtn.drone_by_id(int(h.get("pid", -1)))
	if hd != null:
		SFX.play(self, hd.global_position, "ding", -6.0, 1.4)
	return false


func _arrest_h(h: Dictionary) -> void:
	var win := float(h["win"])
	var f := clampf(float(h["t"]) / win, 0.05, 1.0)
	var tr0 := float(h["tr0"])
	var rem := float(h["rem"])
	var v := (rem - tr0) * DRAG_P * pow(f, DRAG_P - 1.0) / win
	h["ta"] = h["tr"]
	h["tex"] = minf(clampf(v * 0.1, 0.06, 0.55), maxf(rem - float(h["tr"]) - 0.05, 0.0))
	h["st"] = "anchor"
	h["t"] = 0.0
	h["grip"] = 1.0


## Держателя протащило над другой трещиной (без моста) или за край ледника — падает туда
func _holder_void_h(h: Dictionary) -> bool:
	var from: Vector3 = h["from"]
	var dir: Vector3 = h["dir"]
	var p0 := from + dir * float(h["tr"])
	var q := M.gl_local(p0.x, p0.z)
	if is_nan(q.x):
		return false
	if q.y > M.GL_OUT + 0.2 or q.y < -M.GL_IN - 0.2:
		h["lost_at"] = p0 + dir * 0.6 + Vector3.DOWN * 3.0
		return true
	var c2 := M.gl_crack_at(q.x, q.y, -0.25)
	if c2 >= 0 and _piece_at(q.x, q.y) < 0:
		var sp2 := M.gl_span(cr[c2], q.y)
		h["lost_at"] = W((sp2.x + sp2.y) * 0.5, q.y, -1.6)
		return true
	return false


func _rescue_server(delta: float) -> void:
	if rescue.is_empty():
		return
	var F: Dictionary = rescue["F"]
	var H: Dictionary = rescue["H"]
	var ph := String(rescue["phase"])
	if ph == "lost" or ph == "out":
		return
	var changed := false
	rescue["t"] = float(rescue["t"]) + delta
	# погибшие — из спасения
	for k in F.keys():
		var dk: Node3D = mtn.drone_by_id(int(k))
		if dk == null or bool(dk.get("is_dead")):
			F.erase(k)
			changed = true
	for k2 in H.keys():
		var dk2: Node3D = mtn.drone_by_id(int(k2))
		if dk2 == null or bool(dk2.get("is_dead")):
			H.erase(k2)
			changed = true
	# упавшие
	var any_hang := false
	for fp in F.keys():
		var f: Dictionary = F[fp]
		f["t"] = float(f["t"]) + delta
		if String(f["st"]) == "fall":
			f["depth"] = float(f["d0"]) * pow(minf(float(f["t"]) / float(f["fall_t"]), 1.0), 2.0)
			if float(f["t"]) >= float(f["fall_t"]):
				f["st"] = "hang"
				f["depth"] = f["d0"]
				changed = true
		if String(f["st"]) == "hang":
			any_hang = true
	var nf := 0
	for fp2 in F.keys():
		if String(F[fp2]["st"]) in ["fall", "hang"]:
			nf += 1
	var na := _n_anchored()
	var load := float(maxi(nf, 1)) / float(maxi(na, 1))
	var T := float(rescue["T"])
	var dtr_sum := 0.0
	var ndrag := 0
	var deepen := 0.0
	var max_depth := 0.0
	for fp3 in F.keys():
		max_depth = maxf(max_depth, float(F[fp3]["depth"]))
	var haul_rate := 0.0
	for hp in H.keys():
		var h: Dictionary = H[hp]
		var hd: Node3D = mtn.drone_by_id(int(hp))
		var hbot := hd != null and bool(hd.get("is_bot"))
		h["t"] = float(h["t"]) + delta
		var t := float(h["t"])
		var rem := float(h["rem"])
		match String(h["st"]):
			"wait":
				h["tr"] = minf(0.3, rem) * pow(minf(t / 0.45, 1.0), 2.0)       # верёвка натягивается — дёрнуло вперёд
				if any_hang:
					changed = true
					h["t"] = 0.0
					if bool(h["close"]):
						h["st"] = "over"                # стоял у самого края — затянуло сразу
					else:
						h["st"] = "drag"
						h["tr0"] = h["tr"]
						h["win"] = WIN1
						if bool(h.get("near", false)):
							# шаг 133: стоял близко — рвёт быстро: до края за 0.3–0.55 с, заранее не зарубиться
							h["win"] = lerpf(0.5, 0.8, clampf((rem - 1.2) / 3.5, 0.0, 1.0))   # шаг 136: середина (было 0.3–0.55, потом 0.65–0.95)
						elif bool(h["pre"]):
							_arrest_h(h)
			"drag":
				var fr := minf(t / float(h["win"]), 1.0)
				var trn := float(h["tr0"]) + (rem - float(h["tr0"])) * pow(fr, DRAG_P)
				dtr_sum += trn - float(h["tr"])
				ndrag += 1
				h["tr"] = trn
				if hbot and t > (0.35 if int(h["rips"]) == 0 else 0.25) and t - float(h.get("miss_t", -1.0)) > 0.3:
					if _arrest_try(h):
						_arrest_h(h)
					changed = true
				elif fr >= 1.0:
					h["st"] = "over"
					h["t"] = 0.0
					changed = true
			"anchor":
				h["tr"] = float(h["ta"]) + float(h["tex"]) * (1.0 - pow(1.0 - minf(t / 0.3, 1.0), 2.0))
				if t > SETTLE_T:
					h["st"] = "hold"
					h["t"] = 0.0
					h["rs"] = -1.0
					if float(h["v0"]) < 0.0:
						# шаг 136: время до края зависит от того, как далеко стоял: рядом — ~0.5 T, далеко — ~1.2 T
						h["v0"] = maxf(rem - float(h["tr"]), 0.4) / (T * clampf(rem / 7.5, 0.5, 1.2))
					changed = true
			"hold":
				var restriking := float(h["rs"]) >= 0.0 and t - float(h["rs"]) < 0.4
				var e_on := (bool(_haul_on.get(int(hp), false)) or hbot) and not restriking
				var grip := float(h["grip"])
				grip -= delta * (GRIP_DECAY * load + 0.02 * max_depth / 3.0 + (0.05 if e_on else 0.0))
				if hbot and grip < 0.28:
					grip = 1.0
					h["rs"] = t
				# шаг 94/95: ледоруб режет снег — сползаю к краю; чем больше висит на верёвке и меньше держит, тем быстрее
				h["tr"] = float(h["tr"]) + float(h["v0"]) * load * delta
				if grip < 0.35:
					var ex := 0.3 * (0.35 - grip) / 0.35
					h["tr"] = float(h["tr"]) + ex * delta
					deepen = maxf(deepen, ex * delta)
				h["grip"] = grip
				if e_on:
					var hc := float(h["hc"]) + delta * 1.3
					h["hc"] = hc
					haul_rate += HAUL_V * maxf(sin(TAU * hc), 0.0) * 2.0 * (1.0 if haul_rate == 0.0 else 0.5)
				if grip <= 0.0:
					# вырвало ледоруб — снова рывок, а край уже ближе
					h["st"] = "drag"
					h["t"] = 0.0
					h["tr0"] = h["tr"]
					h["win"] = clampf((rem - float(h["tr"])) / 5.0, 0.4, WIN1)
					h["rips"] = int(h["rips"]) + 1
					changed = true
		if String(h["st"]) in ["drag", "anchor", "hold"]:
			if float(h["tr"]) >= rem or _holder_void_h(h):
				h["st"] = "over"
				h["t"] = 0.0
				changed = true
	# никто ещё не зарубился — упавшие проваливаются глубже вместе с теми, кого тащит
	if na == 0 and ndrag > 0:
		deepen = maxf(deepen, dtr_sum / ndrag)
	for fp4 in F.keys():
		var f2: Dictionary = F[fp4]
		if String(f2["st"]) != "hang":
			continue
		var dep := float(f2["depth"]) + deepen
		if String(f2["mode"]) == "haul":
			dep -= haul_rate * delta
		else:
			var fdr: Node3D = mtn.drone_by_id(int(fp4))
			if fdr and bool(fdr.get("is_bot")) and na > 0 and fposmod(float(f2["t"]), 0.55) < delta and float(f2["t"]) > 0.5:
				dep -= CLIMB_STEP
		f2["depth"] = clampf(dep, 0.0, MAX_DEPTH)
		if float(f2["depth"]) <= 0.2 and na > 0:
			f2["st"] = "out"
			changed = true
	# утащило через край — теперь висит (если кто-то держит), иначе — все вниз
	na = _n_anchored()
	for hp2 in H.keys():
		var h2: Dictionary = H[hp2]
		if String(h2["st"]) == "over" and float(h2["t"]) > 0.55 and na > 0:
			var lat2 := float(rescue["lat"]) + 0.7 * float(F.size())
			var sp3 := M.gl_span(cr[int(rescue["ci"])], lat2)
			if is_nan(sp3.x):
				lat2 = float(rescue["lat"])
			F[hp2] = _new_faller(int(rescue["ci"]), lat2, float(rescue["side"]), 1.3)
			H.erase(hp2)
			_haul_on.erase(hp2)
			changed = true
	# общая фаза
	nf = 0
	var n_out := 0
	for fp5 in F.keys():
		var st5 := String(F[fp5]["st"])
		if st5 == "fall" or st5 == "hang":
			nf += 1
		elif st5 == "out":
			n_out += 1
	var alive_h := 0
	var dragging := 0
	for hp3 in H.keys():
		var s3 := String(H[hp3]["st"])
		if s3 != "over":
			alive_h += 1
		if s3 == "drag":
			dragging += 1
	na = _n_anchored()
	if nf == 0 and n_out == 0:
		_haul_on.clear()
		_send_rescue({})                    # шаг 96: висящих не осталось (отцепились) — спасение кончилось
		return
	var nph := ph
	if alive_h == 0 and nf > 0:
		nph = "lost"
	elif nf == 0 and n_out > 0:
		nph = "out"
	elif na > 0:
		nph = "hold"
	elif dragging > 0:
		nph = "drag"
	if nph != ph:
		rescue["phase"] = nph
		rescue["t"] = 0.0
		changed = true
		if nph == "lost" or nph == "out":
			_end_rescue_later()
	if changed:
		_send_rescue(rescue)
	else:
		_sync_t -= delta
		if _sync_t <= 0.0:
			_sync_t = 0.1
			if mtn._online():
				_rescue_sync.rpc(rescue.duplicate(true))


## Шаг 96: кто-то отцепился (Q) — держатели без связи с висящими свободны; висящий без держащих — вниз
func _rescue_prune() -> void:
	if rescue.is_empty() or String(rescue["phase"]) in ["lost", "out"]:
		return
	var F: Dictionary = rescue["F"]
	var H: Dictionary = rescue["H"]
	var ch := false
	for hp in H.keys():
		var tm := _team_of(int(hp))
		var ok := false
		for fp in F.keys():
			if tm.has(int(fp)) and String(F[fp]["st"]) in ["fall", "hang"]:
				ok = true
		if not ok:
			H.erase(hp)
			_haul_on.erase(hp)
			ch = true
	for fp2 in F.keys():
		if not (String(F[fp2]["st"]) in ["fall", "hang"]):
			continue
		var tm2 := _team_of(int(fp2))
		var ok2 := false
		for hp2 in H.keys():
			if tm2.has(int(hp2)):
				ok2 = true
		if not ok2:
			F.erase(fp2)
			ch = true
	if ch:
		_send_rescue(rescue)


func _end_rescue_later() -> void:
	var tw := create_tween()
	tw.tween_interval(2.4)
	tw.tween_callback(func() -> void:
		if not rescue.is_empty() and String(rescue["phase"]) in ["lost", "out"]:
			_haul_on.clear()
			_send_rescue({}))


func _F(pid: int) -> Dictionary:
	if rescue.is_empty():
		return {}
	return (rescue["F"] as Dictionary).get(pid, {})


func _H(pid: int) -> Dictionary:
	if rescue.is_empty():
		return {}
	return (rescue["H"] as Dictionary).get(pid, {})


func _stt(pid: int) -> float:
	return float(_st_t.get(pid, 0.0))


## Как глубоко упавший сейчас (падение — по формуле от начала; дальше — плавно к значению хоста)
func _depth_now(pid: int, f: Dictionary, prev: float, delta: float) -> float:
	if String(f.get("st", "")) == "fall":
		return float(f["d0"]) * pow(minf(_stt(pid) / float(f["fall_t"]), 1.0), 2.0)
	return lerpf(prev, float(f.get("depth", prev)), clampf(delta * 7.0, 0.0, 1.0))


## Сколько держателя протащило (рывок — по формуле, иначе — плавно к хосту)
func _tr_now(pid: int, h: Dictionary, prev: float, delta: float) -> float:
	var t := _stt(pid)
	match String(h.get("st", "")):
		"wait":
			return minf(0.3, float(h["rem"])) * pow(minf(t / 0.45, 1.0), 2.0)
		"drag":
			var fr := minf(t / float(h["win"]), 1.0)
			return float(h["tr0"]) + (float(h["rem"]) - float(h["tr0"])) * pow(fr, DRAG_P)
		"anchor":
			return float(h["ta"]) + float(h["tex"]) * (1.0 - pow(1.0 - minf(t / 0.3, 1.0), 2.0))
	return lerpf(prev, float(h.get("tr", prev)), clampf(delta * 8.0, 0.0, 1.0))


func drive(d: Node3D, kind: int, t: float, data: Dictionary, delta: float) -> void:
	if kind == 12:
		_drive_faller(d, t, data, delta)
	elif kind == 13:
		_drive_holder(d, t, data, delta)
	elif kind == 14:
		_drive_out(d, t, data)
	elif kind == 15:
		_drive_clip(d, t, data, delta)


## Шаг 96: обвязка у стойки / пристёгиваюсь к напарнику: подхожу, руки к его обвязке, вщёлкиваю карабин,
## закручиваю муфту (поза 14: вставить → довернуть → закрутить)
func _drive_clip(d: Node3D, t: float, data: Dictionary, _delta: float) -> void:
	var pid := int(d.peer_id)
	var T := float(data.get("T", 1.0))
	var rack := bool(data.get("rack", false))
	var o: Node3D = null if rack else mtn.drone_by_id(int(data["o"]))
	if not rack and (o == null or bool(o.get("is_dead")) or not tied.has(int(data["o"]))):
		d.snow.end_scripted()
		d.snow.set_mpose(0)
		return
	d.velocity = Vector3.ZERO
	if not data.has("p0"):
		data["p0"] = d.global_position
	var p0: Vector3 = data["p0"]
	var fw: Vector3
	var tgt: Vector3
	var k := clampf(t / T, 0.0, 0.999)
	if rack:
		fw = _rack_a - p0
		fw.y = 0.0
		fw = fw.normalized() if fw.length() > 0.05 else -(d.visual as Node3D).global_basis.z
		# снял бухту со стойки → обвязал пояс → защёлкнул карабин на себе
		var coil := _rack_a + Vector3.UP * 1.4
		var waist := p0 + Vector3.UP * 0.95 + fw * 0.55
		tgt = coil.lerp(waist, smoothstep(0.15, 0.45, k))
	else:
		var to := o.global_position - p0
		to.y = 0.0
		fw = to.normalized() if to.length() > 0.05 else -(d.visual as Node3D).global_basis.z
		var want := o.global_position - fw * 0.9
		want.y = p0.y
		var ka := smoothstep(0.0, 1.0, clampf(t / 0.3, 0.0, 1.0))
		d.global_position = p0.lerp(want, ka) if to.length() > 0.9 else p0
		tgt = o.global_position + Vector3.UP * 0.98 - fw * 0.22
		d.snow.mpose_moving = ka < 1.0
	d.visual.rotation.y = atan2(-fw.x, -fw.z)
	d.snow.set_mpose(14, k, tgt, fw, t < 0.3 and not rack)
	if k >= 0.34 and not bool(data.get("clk", false)):
		data["clk"] = true
		SFX.play(self, tgt, "click", -6.0, 0.9)             # защёлка карабина
	if k >= 0.6 and not bool(data.get("sent", false)):
		data["sent"] = true
		SFX.play(self, tgt, "ratchet", -12.0, 1.6)          # муфта закручена
		if rack:
			_ask_tie(pid, true)
		else:
			_ask_link(pid, int(data["o"]), true)
	if t >= T:
		d.snow.end_scripted()
		d.snow.set_mpose(0)


## Скриптовое падение в глубину и смерть (не удержали) — без физики, не повиснешь на краю
func _death_drop(d: Node3D, data: Dictionary, delta: float) -> void:
	var lt := float(data.get("lt", 0.0)) + delta
	data["lt"] = lt
	var v := float(data.get("lv", 2.0)) + 9.8 * delta
	data["lv"] = v
	d.global_position += Vector3.DOWN * v * delta
	d.velocity = Vector3.ZERO
	d.snow.set_mpose(22, 2.0 + clampf(lt / 0.7, 0.0, 0.6), d.global_position + Vector3.UP * 3.0, -(d.visual as Node3D).global_basis.z)
	if lt > 1.5 and d.has_method("kill") and not bool(d.get("is_dead")):
		d.snow.end_scripted()
		d.kill("Сорвались в трещину всей связкой!\nКогда тянет — сразу ЛКМ: ледоруб в снег")


func _drive_faller(d: Node3D, t: float, data: Dictionary, delta: float) -> void:
	var pid := int(d.peer_id)
	var f := _F(pid)
	var ph := String(rescue.get("phase", "wait"))
	if ph == "lost" or (f.is_empty() and t > 1.5):
		_death_drop(d, data, delta)
		return
	var fst := String(f.get("st", "fall"))
	var mode := String(f.get("mode", "haul"))
	var ci := int(data["ci"])
	var lat := float(data["lat"])
	var side := float(data["side"])
	var sp := M.gl_span(cr[ci], lat)
	var face := _tang((sp.x + sp.y) * 0.5) * side
	face.y = 0.0
	face = face.normalized()
	var latv := _out((sp.x + sp.y) * 0.5)
	var dv := float(data.get("dv", 0.0))
	if not f.is_empty():
		dv = _depth_now(pid, f, dv, delta)
	data["dv"] = dv
	var target := _hang_pos({"ci": ci, "lat": lat, "side": side}, dv, mode)
	var from: Vector3 = data["from"]
	var sw: Vector2 = data.get("sw", Vector2.ZERO)
	var swv: Vector2 = data.get("swv", Vector2(0.0, 0.0))
	var last_ph := String(data.get("lph", ""))
	if ph != last_ph:
		data["lph"] = ph
		if ph == "drag":
			swv += Vector2(0.6, 0.9 * (1.0 if pid % 2 == 0 else -1.0))
			if d == Network.local_player:
				d.add_shake(0.45)
				SFX.play(self, d.global_position + Vector3.UP * 1.6, "thunk", -4.0, 1.3)
		elif ph == "hold":
			swv += Vector2(0.8, -0.6)
			data["jolt"] = 0.0
			if d == Network.local_player:
				d.add_shake(0.35)
	var L := maxf(dv + 1.0, 1.5)
	swv += (-sw * (9.8 / L) - swv * (0.9 if mode == "haul" else 2.6)) * delta
	sw += swv * delta
	if mode == "self":
		sw.x = maxf(sw.x, -0.05)
		sw.y = clampf(sw.y, -0.35, 0.35)
	sw = sw.limit_length(0.9)
	data["sw"] = sw
	data["swv"] = swv
	var pos := target - face * sw.x + latv * sw.y
	var jolt := float(data.get("jolt", -1.0))
	if jolt >= 0.0:
		jolt += delta
		data["jolt"] = jolt
		pos += Vector3.UP * sin(clampf(jolt / 0.45, 0.0, 1.0) * PI) * 0.32 * exp(-jolt * 2.0)
	if fst == "fall":
		var ft := float(f.get("fall_t", 0.5))
		var kf := clampf(t / maxf(ft, 0.25), 0.0, 1.0)
		var hx := lerpf(from.x, target.x, smoothstep(0.0, 1.0, kf))
		var hz := lerpf(from.z, target.z, smoothstep(0.0, 1.0, kf))
		pos = Vector3(hx, lerpf(from.y, target.y, kf * kf), hz)
	d.global_position = pos
	d.velocity = Vector3.ZERO
	var yaw := atan2(-face.x, -face.z)
	if mode == "haul" and fst != "fall":
		var spin := float(data.get("spin", 0.0)) + delta * 0.55 * sin(t * 0.35 + 1.0)
		data["spin"] = spin
		yaw += spin
	d.visual.rotation.y = yaw + sw.y * 0.4
	# лезу (узкая): ЛКМ/ПКМ по очереди
	var cl: Array = _climb_last.get(pid, [-1, -10.0])
	var now := _clock
	if fst == "hang" and mode == "self" and ph == "hold":
		for hh in 2:
			if _pressed(d, hh) and hh != int(cl[0]) and now - float(cl[1]) > 0.28:
				_climb_last[pid] = [hh, now]
				cl = _climb_last[pid]
				_act(pid, "climb")
				SFX.play(self, d.global_position + Vector3.UP * 1.8, "thunk", -12.0, 1.5)
		if bool(d.get("is_bot")) and fposmod(t, 0.55) < delta:
			_climb_last[pid] = [1 - maxi(int(cl[0]), 0), now]
			cl = _climb_last[pid]
	var stroke := clampf((now - float(cl[1])) / 0.4, 0.0, 0.99)
	var k22 := float(maxi(int(cl[0]), 0)) + stroke
	if fst == "fall":
		k22 = 2.0 + clampf(t / 0.7, 0.0, 0.6)
	elif ph == "drag" or ph == "fall":
		k22 = 2.6 + clampf(_ph_t / 0.4, 0.0, 0.39)
	elif mode == "haul":
		var hcm := 0.0
		for hp in (rescue["H"] as Dictionary).keys():
			if bool(_haul_on.get(int(hp), false)) or String(rescue["H"][hp]["st"]) == "hold":
				hcm = maxf(hcm, fposmod(float(rescue["H"][hp]["hc"]), 1.0))
		k22 = 3.0 + hcm
	d.snow.set_mpose(22, k22, W(sp.x if side < 0.0 else sp.y, lat), face)
	if d == Network.local_player and bool(d.get("fp_view")):
		if t < 1.0 and fst == "fall" or t < 1.0 and ph == "drag":
			_fp_look(d, data, d.visual.rotation.y, 0.85, 0.08 * sin(t * 9.0), 7.0, delta)
		else:
			d.set("fp_roll", lerpf(float(d.get("fp_roll")), 0.0, clampf(delta * 4.0, 0.0, 1.0)))
	if fst == "out":
		var es := (sp.x - 0.7) if side < 0.0 else (sp.y + 0.7)
		d.snow.end_scripted()
		d.snow.start_scripted(14, self, {"from": d.global_position, "edge": W(sp.x if side < 0.0 else sp.y, lat),
			"dest": W(es, lat, 0.05), "n": face})


func _drive_holder(d: Node3D, t: float, data: Dictionary, delta: float) -> void:
	var pid := int(d.peer_id)
	var h := _H(pid)
	var ph := String(rescue.get("phase", ""))
	if rescue.is_empty() or (h.is_empty() and ph != "out"):
		d.snow.end_scripted()
		d.snow.set_mpose(0)
		return
	if h.is_empty():
		h = data.get("hlast", {})
		if h.is_empty():
			d.snow.end_scripted()
			return
	data["hlast"] = h
	var hst := String(h["st"])
	var from: Vector3 = h["from"]
	var dir: Vector3 = h["dir"]
	d.visual.rotation.y = atan2(-dir.x, -dir.z)
	d.velocity = Vector3.ZERO
	var now := _clock
	var trs := _tr_now(pid, h, float(data.get("trs", 0.0)), delta)
	data["trs"] = trs
	var p0 := from + dir * trs
	var q := M.gl_local(p0.x, p0.z)
	if not is_nan(q.x):
		p0.y = M.gl_h(clampf(q.x, 0.0, M.GL_LEN), q.y)
	if ph == "out":
		d.global_position = p0
		d.snow.set_mpose(21, 0.7 if _ph_t < 0.35 else 0.2, _axe_snow(d, dir) + Vector3.UP * 0.36 - dir * 0.24, _rope_grip(d, dir, 0.0))
		if _ph_t > 0.9:
			d.snow.end_scripted()
			d.snow.set_mpose(0)
		return
	if hst == "over" or ph == "lost":
		# утащило через край: перевалился головой вниз; держит кто-то ещё — повисну, нет — в пропасть
		var edge_p := from + dir * (float(h["rem"]) + 0.8)
		var spl := M.gl_span(cr[int(rescue["ci"])], float(rescue["lat"]))
		var over := W((spl.x + spl.y) * 0.5, float(rescue["lat"]), -1.4) if not is_nan(spl.x) else edge_p + dir * 0.6 + Vector3.DOWN * 1.4
		if h.has("lost_at"):
			over = h["lost_at"]
			edge_p = d.global_position
		var kl := clampf(_stt(pid) / 0.5, 0.0, 1.0)
		var a := (data.get("lfrom", d.global_position)) as Vector3
		data["lfrom"] = a
		var e2 := Vector3(edge_p.x, a.y, edge_p.z)
		if kl < 1.0:
			d.global_position = a.lerp(e2, smoothstep(0.0, 1.0, kl / 0.6)) if kl < 0.6 else e2.lerp(over, pow((kl - 0.6) / 0.4, 1.5))
			d.snow.set_mpose(21, 0.2, _axe_snow(d, dir), _rope_grip(d, dir, 0.0))
		elif ph == "lost":
			_death_drop(d, data, delta)
		return
	d.global_position = p0
	# шаг 96: Q с пустыми руками — отцепился от связки: сам спасён, остальные — как повезёт
	if not bool(d.get("is_bot")) and d._just("throw") and not d._can_throw():
		_ask_link(pid, -1, false, 2)
		SFX.play(self, p0 + Vector3.UP * 0.4, "latch", -4.0, 0.8)
	var me_local: bool = d == Network.local_player
	var st_t := float(_strike_t.get(pid, -10.0))
	if _pressed(d, 0) and now - st_t > 0.4:
		_strike_t[pid] = now
		st_t = now
		_act(pid, "arrest")
		SFX.play(self, d.global_position + Vector3.UP * 0.4, "swish", -8.0, 1.0)
	if bool(d.get("is_bot")) and hst == "hold" and float(h.get("rs", -1.0)) >= 0.0 and absf(float(h["t"]) - float(h["rs"])) < 0.2 and now - st_t > 1.0:
		_strike_t[pid] = now
		st_t = now
	if bool(d.get("is_bot")) and hst == "anchor" and now - st_t > 2.0:
		_strike_t[pid] = now - 0.05
		st_t = now - 0.05
	var sk := now - st_t
	var striking := sk < 0.34
	var kstr := 0.5 + clampf(sk / 0.34, 0.0, 1.0) * 0.19
	var ap := _axe_snow(d, dir)
	if striking or hst == "drag" or hst == "wait" or not data.has("ap"):
		if sk >= 0.2 or not data.has("ap"):
			data["ap"] = ap
	else:
		ap = data["ap"]
	if sk >= 0.2 and sk - delta < 0.2:
		SFX.play(self, ap, "thunk", 0.0, 0.75)
		SFX.play(self, ap, "puff", -6.0, 1.3)
		_impact_t = 0.0
		_impact_at = ap
		if me_local:
			d.add_shake(0.45)
	var k21 := 0.0
	var cyc := 0.0
	match hst:
		"wait":
			k21 = kstr if sk < 3.0 else 0.0
		"drag":
			k21 = kstr if striking else 0.2
			if me_local:
				d.add_shake(0.06)
		_:
			var any_haul := false
			for fp in (rescue["F"] as Dictionary).keys():
				if String(rescue["F"][fp]["mode"]) == "haul" and String(rescue["F"][fp]["st"]) == "hang":
					any_haul = true
			if hst == "hold" and any_haul:
				var e_on: bool = bool(d.get("is_bot")) or d._held("interact")
				if e_on != bool(_haul_on.get(pid, false)):
					_haul_on[pid] = e_on
					if not multiplayer.is_server():
						_act(pid, "haul", e_on)
				if e_on and not striking:
					var hc := float(data.get("hc", 0.0)) + delta * 1.3
					data["hc"] = hc
					cyc = fposmod(hc, 1.0)
			k21 = kstr if striking else 0.7 + cyc * 0.29
			var strain := sin(t * 31.0) * 0.006 * float(hst == "anchor" or float(h.get("grip", 1.0)) < 0.35)
			d.global_position += dir * strain - dir * 0.04 * sin(cyc * PI) * float(cyc > 0.0 and cyc < 0.5)
	var loose := clampf((0.35 - float(h.get("grip", 1.0))) / 0.35, 0.0, 1.0) if hst == "hold" and not striking else 0.0
	var wob := 1.0 + 0.3 * sin(_clock * 30.0)
	d.snow.set_mpose(21, k21, ap + Vector3.UP * (0.36 + 0.1 * loose) - dir * (0.24 - 0.1 * loose * wob), _rope_grip(d, dir, cyc))
	if me_local and bool(d.get("fp_view")):
		_fp_cam(d, pid, hst, dir, sk, delta)


## Вид от 1-го лица держателя: в миг провала голову рвёт к дыре; тащит — низко у снега, кренит; зарубился — встряхнуло
func _fp_cam(d: Node3D, pid: int, hst: String, dir: Vector3, sk: float, delta: float) -> void:
	var pv: Node3D = d.get("camera_pivot")
	if pv == null:
		return
	var yaw_t := atan2(-dir.x, -dir.z)
	var tt := _stt(pid)
	var roll := 0.0
	var pitch_t := pv.rotation.x
	var lock := 0.0
	match hst:
		"wait":
			var cam: Camera3D = d.get("camera")
			var eye: Vector3 = cam.global_position if cam else d.global_position + Vector3.UP * 1.6
			var to_e: Vector3 = (rescue["edge"] as Vector3) + Vector3.DOWN * 0.6 - eye
			yaw_t = atan2(-to_e.x, -to_e.z)
			pitch_t = atan2(to_e.y, Vector2(to_e.x, to_e.z).length())
			roll = 0.05 * sin(tt * 20.0) * clampf(tt / 0.15, 0.0, 1.0)
			lock = 16.0
		"drag":
			var spd := clampf(tt / 0.35, 0.0, 1.0)
			pitch_t = -0.5 + 0.05 * sin(tt * 19.0) * spd - 0.2 * maxf(0.12 - tt, 0.0) / 0.12
			roll = (sin(tt * 11.0) * 0.07 + sin(tt * 4.7 + 1.0) * 0.04) * spd + 0.14 * exp(-tt * 9.0)
			lock = 14.0
			d.set("_speed_fx", maxf(float(d.get("_speed_fx")), 0.55 * spd))
		"anchor":
			var j := exp(-tt * 5.0)
			pitch_t = -0.48 + 0.12 * sin(tt * 14.0) * j
			roll = 0.05 * sin(tt * 9.0) * j
			lock = 10.0
	if sk < 0.34:
		pitch_t += -0.06 * sin(clampf(sk / 0.34, 0.0, 1.0) * PI)
		if sk > 0.2:
			roll += 0.03 * sin((sk - 0.2) * 40.0) * (0.34 - sk) / 0.14
	if lock > 0.0:
		var a := clampf(delta * lock, 0.0, 1.0)
		pv.rotation.y = lerp_angle(pv.rotation.y, yaw_t, a)
		pv.rotation.x = lerpf(pv.rotation.x, pitch_t, a)
		d.set("fp_roll", lerpf(float(d.get("fp_roll")), roll, a))
	else:
		d.set("fp_roll", lerpf(float(d.get("fp_roll")), 0.0, clampf(delta * 4.0, 0.0, 1.0)))


# ---------------------------------------------------------------------------
#  Вид: верёвки, ледорубы
# ---------------------------------------------------------------------------

func visual(delta: float) -> void:
	_hint_t -= delta
	_ph_t += delta
	_clock += delta
	for k in _st_t.keys():
		_st_t[k] = float(_st_t[k]) + delta
	_holder_fx(delta)
	for xp in _exc.keys():
		var xd: Node3D = mtn.drone_by_id(int(xp))
		if xd == null:
			_exc.erase(xp)
			_drop.erase(xp)
		elif bool(xd.get("is_dead")) or xd.snow.busy():
			_drop_end(xd)
	for tm in teams:
		for i in (tm as Array).size() - 1:
			var da: Node3D = mtn.drone_by_id(int(tm[i]))
			var db: Node3D = mtn.drone_by_id(int(tm[i + 1]))
			if da == null or db == null:
				continue
			_rope_draw(_pair_key(int(tm[i]), int(tm[i + 1])), da, db, delta)
	for pid2 in _axe_vis.keys():
		var dd: Node3D = mtn.drone_by_id(int(pid2))
		if dd == null:
			continue
		_axe_place(int(pid2), dd)


# ---------------------------------------------------------------------------
#  Шаг 96: верёвка — своя физика (точки с массой, связи, снег и трещины под ней) и своя модель:
#  трубка с плетёной оплёткой (шейдер), на концах — узел и карабин на обвязке. В спасении — натянута по краю.
# ---------------------------------------------------------------------------

const RN := 30                     ## точек верёвки
const RR := 0.0105                 ## радиус (динамическая 10.5 мм)
const RSIDES := 8


## Карабин на обвязке спереди (лежит — у груди)
func _rope_end(d: Node3D) -> Vector3:
	var fw := -(d.visual as Node3D).global_basis.z
	fw.y = 0.0
	fw = fw.normalized() if fw.length() > 0.01 else Vector3.FORWARD
	if float(d.get("force_belly")) > 0.6:
		return d.global_position + Vector3.UP * 0.22
	var su = d.get("suit")
	if su != null and su.has_method("harness_point"):
		return su.harness_point()
	return d.global_position + Vector3.UP * 0.95 + fw * 0.17


## Натянутая ломаная (один висит в трещине) — или [] (верёвка свободная)
func _rope_taut(a: Node3D, b: Node3D) -> Array:
	var fa := _F(int(a.peer_id))
	var fb := _F(int(b.peer_id))
	var hang_a := not fa.is_empty() and String(fa["st"]) in ["fall", "hang"]
	var hang_b := not fb.is_empty() and String(fb["st"]) in ["fall", "hang"]
	var ph := String(rescue.get("phase", ""))
	if (hang_a != hang_b) and ph != "lost":
		# натянута через край: кто наверху (обвязка → кулак правой) → край → кулаки упавшего → его обвязка
		var fd: Node3D = a if hang_a else b
		var sd: Node3D = b if hang_a else a
		var f: Dictionary = fa if hang_a else fb
		var poly: Array = []
		var lying := float(sd.get("force_belly")) > 0.6
		poly.append(sd.global_position + (Vector3.UP * 0.2 if lying else Vector3.UP * 0.95))
		if lying and int(sd.snow.mpose) == 21 and float(sd.snow.mpose_k) >= 0.7:
			poly.append(_fist(sd, 1, sd.snow.mpose_dir as Vector3))
		poly.append((f["edge"] as Vector3) + Vector3.UP * 0.06)
		if String(f["st"]) != "fall":
			var f0 := _fist(fd, 0, fd.global_position + Vector3.UP * 1.7)
			var f1 := _fist(fd, 1, fd.global_position + Vector3.UP * 1.5)
			poly.append(f0 if f0.y >= f1.y else f1)
			poly.append(f1 if f0.y >= f1.y else f0)
		poly.append(fd.global_position + Vector3.UP * 1.0)
		if hang_b:
			poly.reverse()
		return poly
	if hang_a and hang_b:
		return [a.global_position + Vector3.UP * 1.0, b.global_position + Vector3.UP * 1.0]
	return []


## Где снег под точкой верёвки: на леднике — по формуле (над открытой трещиной — проваливается внутрь),
## у стоек — лучом (реже: по нескольку точек за кадр)
func _rope_ground(r: Dictionary, i: int, p: Vector3) -> float:
	var q := M.gl_local(p.x, p.z)
	if not is_nan(q.x) and q.x > 0.3 and q.x < M.GL_LEN - 0.3 and q.y > -M.GL_IN + 0.3 and q.y < M.GL_OUT - 0.3:
		var g := M.gl_h(q.x, q.y)
		var c := M.gl_crack_at(q.x, q.y, -0.05)
		if c >= 0 and _piece_at(q.x, q.y) < 0:
			return g - 2.5
		return g + RR
	var G: PackedFloat32Array = r["G"]
	if (_rope_t + i) % 6 == 0 or G[i] < -1e8:
		var rq := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 0.8, p + Vector3.DOWN * 3.0)
		rq.exclude = r["ex"]
		var hit := get_world_3d().direct_space_state.intersect_ray(rq)
		G[i] = (hit["position"] as Vector3).y + RR if not hit.is_empty() else -1e7
		r["G"] = G
	return G[i]


func _rope_draw(key: String, a: Node3D, b: Node3D, delta: float) -> void:
	var r: Dictionary = _rope_vis.get(key, {})
	var pa := _rope_end(a)
	var pb := _rope_end(b)
	if r.is_empty():
		var mi := MeshInstance3D.new()
		mi.mesh = ArrayMesh.new()
		mi.material_override = _rope_smat if _rope_smat else _rope_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		add_child(mi)
		var P := PackedVector3Array()
		var G := PackedFloat32Array()
		P.resize(RN)
		G.resize(RN)
		for i in RN:
			var t := float(i) / (RN - 1)
			P[i] = pa.lerp(pb, t) + Vector3.DOWN * 0.8 * sin(PI * t)
			G[i] = -1e9
		var knots: Array = []
		for k in 2:
			var kn := MeshInstance3D.new()
			var tor := TorusMesh.new()
			tor.inner_radius = 0.011
			tor.outer_radius = 0.019
			tor.rings = 12
			tor.ring_segments = 6
			kn.mesh = tor
			var km := StandardMaterial3D.new()
			km.albedo_color = Color(0.62, 0.64, 0.68)
			km.metallic = 0.9
			km.roughness = 0.3
			kn.material_override = km
			add_child(kn)
			knots.append(kn)
		r = {"mi": mi, "P": P, "O": P.duplicate(), "G": G, "ex": [a.get_rid(), b.get_rid()], "k0": knots[0], "k1": knots[1], "idx": PackedInt32Array()}
		_rope_vis[key] = r
	var P2: PackedVector3Array = r["P"]
	var O2: PackedVector3Array = r["O"]
	var mi2: MeshInstance3D = r["mi"]
	var cam := get_viewport().get_camera_3d()
	var far := cam != null and cam.global_position.distance_to((pa + pb) * 0.5) > 70.0
	mi2.visible = not far and a.visible and b.visible
	(r["k0"] as Node3D).visible = mi2.visible
	(r["k1"] as Node3D).visible = mi2.visible
	var taut := _rope_taut(a, b)
	if not taut.is_empty():
		var pts := _resample(taut, RN - 1)
		for i in RN:
			P2[i] = pts[i]
			O2[i] = pts[i]
	else:
		_rope_t += 1
		# лишняя верёвка — в кольцах через плечо: близко — короче, отходят — выдаётся (не путается кучей на снегу)
		var dab := pa.distance_to(pb)
		var L := clampf(dab * 1.12 + 1.2, dab + 0.05, maxf(ROPE_L, dab))
		var seg := L / (RN - 1)
		var dt := clampf(delta, 1.0 / 120.0, 1.0 / 30.0)
		var grav := Vector3(0.0, -9.8 * dt * dt, 0.0)
		for i in range(1, RN - 1):
			var v := (P2[i] - O2[i]) * 0.982
			O2[i] = P2[i]
			P2[i] += v + grav
		O2[0] = P2[0]
		O2[RN - 1] = P2[RN - 1]
		P2[0] = pa
		P2[RN - 1] = pb
		var gy := PackedFloat32Array()
		gy.resize(RN)
		for i in RN:
			gy[i] = _rope_ground(r, i, P2[i])
		for it in 16:
			for i in RN - 1:
				var dv := P2[i + 1] - P2[i]
				var ln := dv.length()
				if ln < 0.00001:
					continue
				var corr := dv * ((ln - seg) / ln)
				if i == 0:
					P2[i + 1] -= corr
				elif i + 1 == RN - 1:
					P2[i] += corr
				else:
					P2[i] += corr * 0.5
					P2[i + 1] -= corr * 0.5
			for i in range(1, RN - 1):
				if P2[i].y < gy[i]:
					P2[i].y = gy[i]
		# по снегу — трение: лежащая верёвка не скользит
		for i in range(1, RN - 1):
			if P2[i].y <= gy[i] + 0.004:
				var o := O2[i]
				O2[i] = Vector3(lerpf(o.x, P2[i].x, 0.7), o.y, lerpf(o.z, P2[i].z, 0.7))
	r["P"] = P2
	r["O"] = O2
	if mi2.visible:
		_rope_mesh_build(r, P2)
	# карабины на обвязках
	for k in 2:
		var kn2: MeshInstance3D = r["k0" if k == 0 else "k1"]
		var e := P2[0] if k == 0 else P2[RN - 1]
		var nx := (P2[1] - P2[0]) if k == 0 else (P2[RN - 2] - P2[RN - 1])
		nx = nx.normalized() if nx.length() > 0.0001 else Vector3.DOWN
		var yy := nx.cross(Vector3.UP)
		yy = yy.normalized() if yy.length() > 0.05 else Vector3.RIGHT
		var zz := nx.cross(yy).normalized()
		kn2.global_transform = Transform3D(Basis(nx * 1.5, yy, zz), e - nx * 0.012)


## Трубка по точкам (сглажено Катмулл-Ромом вдвое), швы — кольца; длина в UV — метры (оплётка не тянется)
func _rope_mesh_build(r: Dictionary, P: PackedVector3Array) -> void:
	var C := PackedVector3Array()
	var n := P.size()
	for i in n - 1:
		var p0 := P[maxi(i - 1, 0)]
		var p1 := P[i]
		var p2 := P[i + 1]
		var p3 := P[mini(i + 2, n - 1)]
		C.append(p1)
		C.append(0.5 * (p1 + p2) + 0.0625 * ((p1 - p0) - (p3 - p2)) * 1.0)
	C.append(P[n - 1])
	var m := C.size()
	var V := PackedVector3Array()
	var N := PackedVector3Array()
	var U := PackedVector2Array()
	V.resize(m * (RSIDES + 1))
	N.resize(m * (RSIDES + 1))
	U.resize(m * (RSIDES + 1))
	var T := PackedFloat32Array()
	T.resize(m * (RSIDES + 1) * 4)
	var nrm := Vector3.ZERO
	var along := 0.0
	for i in m:
		var tg := (C[mini(i + 1, m - 1)] - C[maxi(i - 1, 0)])
		tg = tg.normalized() if tg.length() > 0.00001 else Vector3.UP
		if i == 0:
			nrm = tg.cross(Vector3.UP if absf(tg.y) < 0.9 else Vector3.RIGHT).normalized()
		else:
			along += C[i].distance_to(C[i - 1])
			nrm = (nrm - tg * nrm.dot(tg))
			nrm = nrm.normalized() if nrm.length() > 0.0001 else tg.cross(Vector3.RIGHT).normalized()
		var bn := tg.cross(nrm)
		for j in RSIDES + 1:
			var ang := TAU * float(j) / RSIDES
			var dir := nrm * cos(ang) + bn * sin(ang)
			var k := i * (RSIDES + 1) + j
			V[k] = C[i] + dir * RR
			N[k] = dir
			U[k] = Vector2(float(j) / RSIDES, along)
			var tv := -nrm * sin(ang) + bn * cos(ang)
			T[k * 4] = tv.x
			T[k * 4 + 1] = tv.y
			T[k * 4 + 2] = tv.z
			T[k * 4 + 3] = 1.0
	var idx: PackedInt32Array = r["idx"]
	if idx.size() != (m - 1) * RSIDES * 6:
		idx = PackedInt32Array()
		for i in m - 1:
			for j in RSIDES:
				var a0 := i * (RSIDES + 1) + j
				var b0 := a0 + RSIDES + 1
				idx.append_array([a0, b0, a0 + 1, a0 + 1, b0, b0 + 1])
		r["idx"] = idx
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = V
	arr[Mesh.ARRAY_NORMAL] = N
	arr[Mesh.ARRAY_TEX_UV] = U
	arr[Mesh.ARRAY_TANGENT] = T
	arr[Mesh.ARRAY_INDEX] = idx
	var am: ArrayMesh = (r["mi"] as MeshInstance3D).mesh
	am.clear_surfaces()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)


# ---------------------------------------------------------------------------
#  Подсказки
# ---------------------------------------------------------------------------

func hint(me: Node3D) -> String:
	var p := me.global_position
	var pid := int(me.peer_id)
	if not rescue.is_empty() and (rescue["team"] as Array).has(pid):
		var ph := String(rescue["phase"])
		var nf := 0
		for fp in (rescue["F"] as Dictionary).keys():
			if String(rescue["F"][fp]["st"]) in ["fall", "hang"]:
				nf += 1
		var na := _n_anchored()
		var h := _H(pid)
		var f := _F(pid)
		if not h.is_empty():
			var edge_m := maxf(float(h["rem"]) - float(h["tr"]), 0.0)
			match String(h["st"]):
				"wait", "drag":
					return "ЛКМ — ЛЕДОРУБ В СНЕГ!!!" if int(h["rips"]) == 0 else "ЛЕДОРУБ ВЫРВАЛО! ЛКМ — ВБЕЙ СНОВА!!!"
				"anchor":
					return "Зарубился! Держи…"
				"hold":
					var who := "Держите вдвоём" if na == 2 else ("Держите втроём" if na >= 3 else "Держишь один")
					var load_s := " — висят %d" % nf if nf > 1 else ""
					if float(h["grip"]) < 0.35:
						return "ЛЕДОРУБ ВЫПОЛЗАЕТ! ЛКМ — перевбей!   До края %.1f м" % edge_m
					var any_haul := false
					for fp2 in (rescue["F"] as Dictionary).keys():
						if String(rescue["F"][fp2]["mode"]) == "haul" and String(rescue["F"][fp2]["st"]) == "hang":
							any_haul = true
					return "%s%s. %sТебя тянет к краю — %.1f м   (Q — отцепиться)" % [who, load_s, "Держи E — тяни! " if any_haul else "Держи ледоруб, напарник лезет. ", edge_m]
				"over":
					return "Утащило через край!"
		if not f.is_empty():
			var edge_f := 99.0
			for hp in (rescue["H"] as Dictionary).keys():
				var hh: Dictionary = rescue["H"][hp]
				if String(hh["st"]) in ["anchor", "hold"]:
					edge_f = minf(edge_f, float(hh["rem"]) - float(hh["tr"]))
			var dep := float(f["depth"])
			match String(f["st"]):
				"fall":
					return "Сорвался!"
				"hang":
					if ph != "hold":
						return "Висишь! Держащие должны зарубиться…"
					if String(f["mode"]) == "self":
						return "Лезь быстрее! ЛКМ/ПКМ по очереди (%.1f м). Держащих тащит к краю — %.1f м" % [dep, maxf(edge_f, 0.0)]
					return "Широкая трещина — до стен не достать. Тебя тянут (%.1f м); держащих тащит к краю — %.1f м" % [dep, maxf(edge_f, 0.0)]
				"out":
					return "Вылез!"
		if ph == "lost":
			return "Не удержали…"
		if ph == "out":
			return "Вытащили!"
	if _hint_t > 0.0 and _hint_msg != "":
		return _hint_msg
	if p.distance_to(_rack_a) < 2.4:
		if not tied.has(pid):
			return "E — обвязаться: верёвка и ледоруб"
		if not _linked(pid):
			return "Обвязан. Подойди к напарнику (он тоже обвязан) — ЛКМ: пристегнуться"
		return "В связке %d. ЛКМ по ещё одному обвязанному — пристегнуть. Q — отцепиться" % _team_of(pid).size() if _team_of(pid).size() < 4 else "В связке четверо. Вперёд — под снегом трещины"
	if p.distance_to(_rack_b) < 2.4 and tied.has(pid):
		return "E — отвязаться"
	var q := M.gl_local(p.x, p.z)
	if not is_nan(q.x) and q.x > -12.0 and q.x < M.GL_LEN and q.y > -M.GL_IN and q.y < M.GL_OUT:
		if not tied.has(pid):
			return "Без связки провал в трещину — смерть. Обвяжись у стойки (E)" if q.x > 0.0 else ""
		if not _linked(pid):
			return "Ты один на верёвке — провалишься, никто не удержит. ЛКМ по напарнику — пристегнуться"
		return "Сорвётся кто-то из связки — сразу ЛКМ: ледоруб в снег. Q — отцепиться от связки" if q.x > 0.0 else "ЛКМ по ещё одному обвязанному — пристегнуть. Q — отцепиться"
	return ""


# ---------------------------------------------------------------------------
#  Держатели — на животе (тащит/держу), снег из-под груди и из-под ледоруба
# ---------------------------------------------------------------------------

func _holder_fx(delta: float) -> void:
	if _drag_fx == null:
		_drag_fx = FX.particles(Color(0.95, 0.97, 1.0, 0.85), 70, 0.55, 0.06, 1.0, 3.4, Vector3(0, -5, 0), 45.0, false)
		add_child(_drag_fx)
		_axe_fx = FX.particles(Color(0.95, 0.97, 1.0, 0.9), 30, 0.4, 0.04, 0.6, 2.2, Vector3(0, -6, 0), 35.0, false)
		add_child(_axe_fx)
	var H: Dictionary = rescue.get("H", {}) if not rescue.is_empty() else {}
	var ph := String(rescue.get("phase", ""))
	for pid in _belly_set.keys():
		if not H.has(pid) or ph == "":
			var o: Node3D = mtn.drone_by_id(int(pid))
			if o:
				o.set("force_belly", 0.0)
				o.set("force_paddle", 0.0)
				o.set("force_belly_spd", 0.0)
				o.set("force_dive", 0.0)
				o.set("rope_hold", false)
				o.set("fp_roll", 0.0)
			_belly_set.erase(pid)
	_drag_fx.emitting = false
	_axe_fx.emitting = false
	_impact_t += delta
	if _impact_t < 0.22:
		_axe_fx.emitting = true
		_axe_fx.global_position = _impact_at + Vector3.UP * 0.05
	if ph == "":
		return
	var me = Network.local_player
	var fx_pid := int(me.peer_id) if me and H.has(int(me.peer_id)) else (int(H.keys()[0]) if not H.is_empty() else -1)
	for hp in H.keys():
		var h: Node3D = mtn.drone_by_id(int(hp))
		if h == null:
			continue
		var e: Dictionary = H[hp]
		var hst := String(e["st"])
		var tt := _stt(int(hp))
		_belly_set[hp] = true
		var mk := float(h.snow.mpose_k) if int(h.snow.mpose) == 21 else 0.0
		var struck := mk >= 0.5
		var fb_t := 1.0
		var rate := 9.0
		if hst == "wait":
			fb_t = 1.0 if struck else 0.0
			rate = 5.0
		if ph == "out":
			fb_t = 0.0 if _ph_t > 0.3 else 1.0
			rate = 2.4
		h.set("force_belly", move_toward(float(h.get("force_belly")), fb_t, delta * rate))
		h.set("rope_hold", hst == "anchor" or hst == "hold" or (ph == "out" and _ph_t < 0.35))
		h.set("force_dive", move_toward(float(h.get("force_dive")), 1.0 if (hst == "over" or ph == "lost") and tt > 0.25 else 0.0, delta * 3.0))
		var dragging := hst == "drag" or hst == "over"
		h.set("force_paddle", 1.0 if dragging and not struck and tt > 0.12 else 0.0)
		var spd := 0.0
		if dragging:
			spd = clampf(tt * 4.0, 0.0, 3.0)
		elif hst == "anchor":
			spd = maxf(1.2 - tt * 4.0, 0.0)
		elif hst == "hold":
			spd = 0.5 if float(e["grip"]) < 0.35 else 0.25
		h.set("force_belly_spd", spd)
		if int(hp) == fx_pid:
			var fw := -(h.visual as Node3D).global_basis.z
			fw.y = 0.0
			if dragging and tt > 0.08:
				_drag_fx.emitting = true
				_drag_fx.global_position = h.global_position + fw.normalized() * 0.6 + Vector3.UP * 0.15
			if (hst == "anchor" and tt < 0.35 and _impact_t > 0.22) or hst == "hold":
				_axe_fx.emitting = true
				_axe_fx.global_position = (h.snow.mpose_pt as Vector3) + Vector3.DOWN * 0.38
