extends Node3D
## Коридор-тиски: по обе стороны дороги — сплошные ледяные стены с шипами, длиной во весь коридор.
## Стоит дрону войти с любого конца — по стенам бегут красные огни, и через миг стены начинают
## сходиться ВОЛНОЙ от входа к выходу (~9 м/с). Позади волны проход постепенно сужается до нуля.
## Пешком (6 м/с) волна догоняет и давит, бегом (11.5 м/с) — успеваешь к выходу.
## Раздавило — сильный урон и выбрасывает за вход. Потом стены расходятся, и тиски снова взводятся.
## Решает хост (кто вошёл), остальным — «старт» с общим временем; ход стен все считают сами.

const ICE_SHADER := preload("res://shaders/pressure_ice.gdshader")

@export var road_width := 7.5
@export var damage := 55.0
var path: Array = []                 ## осевая линия коридора (ставит каньон)

const SEG := 2.0
const THICK := 2.6
const HEIGHT := 22.0
const ABOVE := 6.0                   ## на сколько стена выше дороги
const WAVE := 9.0
const DELAY := 0.7
const CLOSE := 1.0
const HOLD := 1.2
const REOPEN := 1.6
const COOL := 1.5

var active := false
var _start_t := -100.0
var _from := 0
var _n := 0
var _len := 0.0
var _cen: Array[Vector3] = []
var _fwd: Array[Vector3] = []
var _side: Array[Vector3] = []
var _s: Array[float] = []
var _bodies: Array[AnimatableBody3D] = []
var _mm: MultiMesh
var _lamps: MultiMesh
var _dust: GPUParticles3D
var _local_t := 0.0
var _crushed := false
var _held_parts := {}
var _last_open: Array[float] = []


func _now() -> float:
	return Network.game_time if Network.in_game else _local_t


func _ready() -> void:
	if path.size() < 2:
		return
	# пересчёт осевой по длине: ровные куски по SEG м
	var acc: Array[float] = [0.0]
	for k in range(1, path.size()):
		acc.append(acc[-1] + (path[k] as Vector3).distance_to(path[k - 1]))
	_len = acc[-1]
	_n = maxi(int(round(_len / SEG)), 2)
	var seg := _len / _n
	for i in _n:
		var want := (i + 0.5) * seg
		var j := 1
		while j < acc.size() - 1 and acc[j] < want:
			j += 1
		var t := clampf((want - acc[j - 1]) / maxf(acc[j] - acc[j - 1], 0.001), 0.0, 1.0)
		var a: Vector3 = path[j - 1]
		var b: Vector3 = path[j]
		var f := Vector3(b.x - a.x, 0.0, b.z - a.z).normalized()
		_cen.append(a.lerp(b, t))
		_fwd.append(f)
		_side.append(Vector3(-f.z, 0.0, f.x))
		_s.append(want)
		_last_open.append(-1.0)
	var ice := ShaderMaterial.new()
	ice.shader = ICE_SHADER
	ice.set_shader_parameter("deep", Color(0.02, 0.1, 0.2))
	ice.set_shader_parameter("mid", Color(0.12, 0.34, 0.52))
	ice.set_shader_parameter("snow_amount", 0.5)
	ice.set_shader_parameter("crack_amount", 0.9)
	ice.set_shader_parameter("band_scale", 0.6)
	# плита стены с шипами на внутренней грани (внутрь — по −x)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var slab := BoxMesh.new()
	slab.size = Vector3(THICK, HEIGHT, seg + 0.06)
	st.append_from(slab, 0, Transform3D())
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.3
	cone.height = 0.9
	cone.radial_segments = 5
	cone.rings = 1
	for k in 3:
		var y := HEIGHT * 0.5 - ABOVE + 0.8 + k * 1.6
		var zz := (k - 1) * seg * 0.3
		st.append_from(cone, 0, Transform3D(Basis.from_euler(Vector3(0, 0, PI * 0.5)), Vector3(-THICK * 0.5 - 0.4, y, zz)))
	# зубчатый верх
	var tooth := PrismMesh.new()
	tooth.size = Vector3(THICK, 0.9, seg)
	st.append_from(tooth, 0, Transform3D(Basis(), Vector3(0, HEIGHT * 0.5 + 0.45, 0)))
	var mesh := st.commit()
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.mesh = mesh
	_mm.instance_count = _n * 2
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = _mm
	mmi.material_override = ice
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	# огни по верху стен
	var lm := StandardMaterial3D.new()
	lm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lm.vertex_color_use_as_albedo = true
	var lamp := BoxMesh.new()
	lamp.size = Vector3(0.3, 0.3, seg * 0.5)
	_lamps = MultiMesh.new()
	_lamps.transform_format = MultiMesh.TRANSFORM_3D
	_lamps.use_colors = true
	_lamps.mesh = lamp
	_lamps.instance_count = _n * 2
	var lmi := MultiMeshInstance3D.new()
	lmi.multimesh = _lamps
	lmi.material_override = lm
	lmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(lmi)
	for i in _n * 2:
		var body := AnimatableBody3D.new()
		body.sync_to_physics = false
		var shape := BoxShape3D.new()
		shape.size = Vector3(THICK, HEIGHT, seg)
		var col := CollisionShape3D.new()
		col.shape = shape
		body.add_child(col)
		add_child(body)
		_bodies.append(body)
	_dust = FX.particles(Color(0.85, 0.92, 1.0), 60, 1.0, 0.25, 1.0, 4.0, Vector3(0, -6, 0))
	FX.set_box(_dust, Vector3(0.6, 2.0, 1.0))
	add_child(_dust)
	_place(true)


## Насколько стены у куска i разошлись: 1 — открыто, 0 — сомкнуты
func _openness(i: int, now: float) -> float:
	if not active:
		return 1.0
	var dt := now - _start_t
	var s := _s[i] if _from == 0 else _len - _s[i]
	var t_end := DELAY + _len / WAVE + CLOSE + HOLD
	if dt >= t_end:
		return smoothstep(0.0, 1.0, (dt - t_end) / REOPEN)
	var tc := DELAY + s / WAVE
	if dt < tc:
		return 1.0
	return 1.0 - smoothstep(0.0, 1.0, (dt - tc) / CLOSE)


func _place(force: bool) -> void:
	var now := _now()
	var hw := road_width * 0.5
	var dt := now - _start_t
	for i in _n:
		var o := _openness(i, now)
		var lamp_on := false
		if active:
			var s := _s[i] if _from == 0 else _len - _s[i]
			var tc := DELAY + s / WAVE
			lamp_on = (dt > tc - 1.4 and o > 0.02 and dt < tc + CLOSE)
		if not force and absf(o - _last_open[i]) < 0.0005 and not active:
			continue
		_last_open[i] = o
		var gap := lerpf(0.18, hw + 0.7, o)
		var b := Basis.looking_at(_fwd[i], Vector3.UP)
		for k in 2:
			var sgn := 1.0 if k == 0 else -1.0
			# внутренняя грань (−x локально) смотрит к дороге; у стены с другой стороны — поворот на 180°
			var bb := b if sgn > 0.0 else b * Basis(Vector3.UP, PI)
			var pos := _cen[i] + _side[i] * sgn * (gap + THICK * 0.5) + Vector3(0, ABOVE - HEIGHT * 0.5, 0)
			var xf := Transform3D(bb, pos)
			_mm.set_instance_transform(i * 2 + k, xf)
			_bodies[i * 2 + k].global_transform = global_transform * xf
			var blink := lamp_on and fmod(_local_t, 0.3) < 0.16
			var lc := Color(1.0, 0.12, 0.05) if blink else (Color(0.5, 0.06, 0.04) if lamp_on else Color(0.12, 0.2, 0.28))
			_lamps.set_instance_transform(i * 2 + k, Transform3D(b, _cen[i] + _side[i] * sgn * (gap + 0.25) + Vector3(0, ABOVE + 0.25, 0)))
			_lamps.set_instance_color(i * 2 + k, lc)


func _physics_process(delta: float) -> void:
	if _n == 0:
		return
	_local_t += delta
	var now := _now()
	var dt := now - _start_t
	var t_all := DELAY + _len / WAVE + CLOSE + HOLD + REOPEN
	if active and dt > t_all + COOL:
		active = false
		_crushed = false
		_place(true)
	# хост: кто-то вошёл с конца — запустить
	if multiplayer.is_server() and not active:
		for d in get_tree().get_nodes_in_group("player"):
			if d.is_dead:
				continue
			var si := _seg_at(d.global_position)
			if si < 0:
				continue
			if _s[si] < 4.0:
				_start.rpc(0, now)
				break
			if _s[si] > _len - 4.0:
				_start.rpc(1, now)
				break
	if active:
		_place(false)
		# пыль у фронта волны
		var front := clampf((dt - DELAY) * WAVE, 0.0, _len)
		var fi := clampi(int(front / _len * _n), 0, _n - 1)
		if _from == 1:
			fi = _n - 1 - fi
		_dust.position = _cen[fi] + Vector3(0, 0.5, 0)
		_dust.emitting = dt > DELAY and dt < DELAY + _len / WAVE + 0.5
		var me = Network.local_player
		if me and not me.is_dead and me.global_position.distance_to(_cen[fi]) < 25.0 and fmod(_local_t, 0.25) < delta:
			me.add_shake(0.05)
		_crush_check(now)
	else:
		_dust.emitting = false
	_hold_parts(active)


## Номер куска коридора, над которым стоит точка (или −1)
func _seg_at(p: Vector3) -> int:
	var best := -1
	var bd := 1e9
	for i in _n:
		var d := Vector2(p.x - _cen[i].x, p.z - _cen[i].z).length()
		if d < bd:
			bd = d
			best = i
	if best < 0:
		return -1
	var rel := p - _cen[best]
	if absf(rel.dot(_fwd[best])) > _len / _n * 0.75 or absf(rel.dot(_side[best])) > road_width * 0.5 + 0.8 or absf(rel.y) > 4.0:
		return -1
	return best


func _crush_check(now: float) -> void:
	var me = Network.local_player
	if me == null or me.is_dead or _crushed:
		return
	var i := _seg_at(me.global_position)
	if i < 0 or _openness(i, now) > 0.1:
		return
	_crushed = true
	me.take_damage(damage, "pressure")
	if not me.is_dead:
		# выбрасывает за тот вход, откуда пошла волна
		var e := 0 if _from == 0 else _n - 1
		var out := _cen[e] - _fwd[e] * (SEG + 2.5) if _from == 0 else _cen[e] + _fwd[e] * (SEG + 2.5)
		me.teleport_to(out + Vector3(0, 0.6, 0))
		me.add_shake(0.6)


@rpc("authority", "call_local", "reliable")
func _start(from_end: int, t: float) -> void:
	active = true
	_from = from_end
	_start_t = t
	_crushed = false


## Деталь подъёмника, лежащая в коридоре, «вмерзает», пока стены ходят, — их не выбрасывает в пропасть
func _hold_parts(moving: bool) -> void:
	if not multiplayer.is_server():
		return
	if moving:
		for n in get_tree().get_nodes_in_group("lift_part"):
			var part := n as Parcel
			if part == null or part.is_delivered or part.is_carried() or _held_parts.has(part):
				continue
			if _seg_at(part.global_position) >= 0:
				_held_parts[part] = true
				part.linear_velocity = Vector3.ZERO
				part.angular_velocity = Vector3.ZERO
				part.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
				part.freeze = true
	elif not _held_parts.is_empty():
		for part in _held_parts.keys():
			if is_instance_valid(part) and not part.is_carried() and not part.is_delivered:
				part.freeze = false
		_held_parts.clear()
