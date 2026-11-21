extends StaticBody3D
## Тонкий ледяной мост над пропастью: ряд ледяных плит с ледяными перильцами и сосульками снизу.
## Стоит ступить на плиту — она трескается и через миг отваливается, а за ней волной
## рушатся соседние (≈8 м/с в обе стороны). Пешком волна догоняет — проскочить можно
## только бегом. Когда на мосту никого и все упавшие плиты улетели, мост через время
## нарастает снова.
## Решает хост (кто на какую плиту ступил) и рассылает «толчки»; падение каждой плиты
## все считают сами по общему времени игры — у всех одинаково.

const PLATE_SHADER := preload("res://shaders/ice_plate.gdshader")

@export var length := 9.0
@export var width := 2.6
@export var respawn_time := 8.0
## Старые настройки (медленный треск) больше не нужны — оставлены, чтобы сцены не ругались
@export var stress_rate := 0.25
@export var carry_mult := 1.6
@export var run_mult := 1.3
@export var landing_stress := 0.35
@export var recovery := 0.15

const CRACK := 0.14              ## Сколько трещит плита под ногой, прежде чем упасть
const STEP := 0.105              ## Задержка волны на каждую соседнюю плиту (≈10 м/с — бегом 11.5 м/с ещё успеть)
const FALL := 1.6                ## Сколько летит вниз (дальше — уже в тумане пропасти)

var broken := false              ## хоть одна плита упала
var _n := 0
var _plen := 1.0
var _fall_at: Array[float] = []  ## когда плита упадёт (INF — цела)
var _shapes: Array[CollisionShape3D] = []
var _mm: MultiMesh
var _mmi: MultiMeshInstance3D
var _seeds: Array[float] = []
var _spin: Array[Vector3] = []
var _local_t := 0.0
var _regrow_t := -100.0
var _empty_t := 0.0
var _shards: Array[GPUParticles3D] = []
var _shard_i := 0
var _dropped: Array[bool] = []


func _now() -> float:
	return Network.game_time if Network.in_game else _local_t


func _ready() -> void:
	add_to_group("safe_ground")
	_n = maxi(int(round(length / 1.1)), 3)
	_plen = length / _n
	var rng := RandomNumberGenerator.new()
	rng.seed = int(global_position.x * 31.0 + global_position.z * 17.0) + _n
	# плита: ледяная доска, перильца на стойках, сосульки снизу — одним мешем
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var slab := BoxMesh.new()
	slab.size = Vector3(width, 0.34, _plen - 0.07)
	st.append_from(slab, 0, Transform3D())
	var under := PrismMesh.new()
	under.size = Vector3(width * 0.8, 0.45, _plen - 0.12)
	st.append_from(under, 0, Transform3D(Basis(Vector3.RIGHT, PI), Vector3(0, -0.39, 0)))
	for sgn in [-1.0, 1.0]:
		var post := CylinderMesh.new()
		post.top_radius = 0.05
		post.bottom_radius = 0.08
		post.height = 0.8
		post.radial_segments = 6
		post.rings = 1
		st.append_from(post, 0, Transform3D(Basis(), Vector3(sgn * (width * 0.5 - 0.1), 0.55, 0)))
		var rail := CylinderMesh.new()
		rail.top_radius = 0.05
		rail.bottom_radius = 0.05
		rail.height = _plen - 0.04
		rail.radial_segments = 6
		rail.rings = 1
		st.append_from(rail, 0, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(sgn * (width * 0.5 - 0.1), 0.92, 0)))
		for k in 2:
			var ic := CylinderMesh.new()
			ic.top_radius = 0.09
			ic.bottom_radius = 0.0
			var ih := 0.5 + 0.35 * k
			ic.height = ih
			ic.radial_segments = 5
			ic.rings = 1
			st.append_from(ic, 0, Transform3D(Basis(), Vector3(sgn * width * (0.18 + 0.15 * k), -0.62 - ih * 0.5, (k - 0.5) * _plen * 0.4)))
	st.generate_normals()
	var mesh := st.commit()
	var mat := ShaderMaterial.new()
	mat.shader = PLATE_SHADER
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_custom_data = true
	_mm.mesh = mesh
	_mm.instance_count = _n
	_mmi = MultiMeshInstance3D.new()
	_mmi.multimesh = _mm
	_mmi.material_override = mat
	_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mmi)
	for i in _n:
		_fall_at.append(INF)
		_dropped.append(false)
		_seeds.append(rng.randf() * 50.0)
		_spin.append(Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-0.3, 0.3), rng.randf_range(-1.0, 1.0)).normalized())
		var shape := BoxShape3D.new()
		shape.size = Vector3(width, 0.34, _plen)
		var col := CollisionShape3D.new()
		col.shape = shape
		col.position = Vector3(0, 0.0, _z(i))
		add_child(col)
		_shapes.append(col)
	for k in 3:
		var p := FX.particles(Color(0.82, 0.94, 1.0), 26, 1.3, 0.13, 1.0, 3.5, Vector3(0, -14, 0))
		FX.set_box(p, Vector3(width * 0.5, 0.15, _plen * 0.5))
		add_child(p)
		_shards.append(p)
	_place_all()


func _z(i: int) -> float:
	return -length * 0.5 + (i + 0.5) * _plen


## Номер плиты под дроном (или −1)
func _plate_under(d: Node3D) -> int:
	var l := to_local(d.global_position)
	if absf(l.x) > width * 0.5 + 0.3 or l.y < -0.2 or l.y > 1.2 or absf(l.z) > length * 0.5:
		return -1
	return clampi(int(floor((l.z + length * 0.5) / _plen)), 0, _n - 1)


func _physics_process(delta: float) -> void:
	_local_t += delta
	var now := _now()
	if multiplayer.is_server():
		var anyone := false
		for d in get_tree().get_nodes_in_group("player"):
			if d.is_dead:
				continue
			var i := _plate_under(d)
			if i < 0:
				continue
			anyone = true
			if _fall_at[i] == INF and d.is_grounded():
				_trigger.rpc(i, now)
		# мост нарастает: на нём никого, всё упавшее улетело
		if broken:
			_empty_t = 0.0 if anyone else _empty_t + delta
			var last := -INF
			for f in _fall_at:
				if f != INF:
					last = maxf(last, f)
			if now - last > FALL and _empty_t > respawn_time * 0.5 and now - last > respawn_time:
				_restore.rpc(now)
	# столкновения: упавшие плиты — сквозь
	for i in _n:
		var gone := now >= _fall_at[i]
		if _shapes[i].disabled != gone:
			_shapes[i].set_deferred("disabled", gone)
		if gone and not _dropped[i]:
			_dropped[i] = true
			_burst(i)
	_place_all()


func _burst(i: int) -> void:
	var p := _shards[_shard_i % _shards.size()]
	_shard_i += 1
	p.position = Vector3(0, 0, _z(i))
	p.restart()
	var me = Network.local_player
	if me and me.global_position.distance_to(to_global(Vector3(0, 0, _z(i)))) < 6.0:
		me.add_shake(0.12)


func _place_all() -> void:
	var now := _now()
	var grow := clampf((now - _regrow_t) / 1.5, 0.0, 1.0)
	for i in _n:
		var z := _z(i)
		var xf := Transform3D(Basis(), Vector3(0, 0, z))
		var stress := 0.0
		var fa := _fall_at[i]
		if fa != INF:
			var to := fa - now
			if to > 0.0:
				# трещит и проседает (без дрожания — оно мерцало)
				stress = clampf(1.0 - to / CRACK, 0.2, 1.0)
				xf = Transform3D(Basis(_spin[i], 0.05 * stress), Vector3(0, -0.08 * stress, z))
			else:
				# падает, кувыркаясь
				var t := -to
				stress = 1.0
				if t > FALL:
					xf = Transform3D(Basis().scaled(Vector3.ONE * 0.001), Vector3(0, -80.0, z))
				else:
					xf = Transform3D(Basis(_spin[i], 0.05 + t * 3.0), Vector3(0, -0.08 - 5.0 * t - 0.5 * 34.0 * t * t, z))
		elif grow < 1.0:
			# нарастает снизу
			var g := smoothstep(0.0, 1.0, clampf(grow * 1.4 - float(i) / _n * 0.4, 0.0, 1.0))
			xf = Transform3D(Basis().scaled(Vector3(1.0, maxf(g, 0.01), 1.0)), Vector3(0, -0.5 * (1.0 - g), z))
		_mm.set_instance_transform(i, xf)
		_mm.set_instance_custom_data(i, Color(stress, _seeds[i], 0.0, 0.0))


## Ступили на плиту i: она и соседи волной рушатся
@rpc("authority", "call_local", "reliable")
func _trigger(i: int, t: float) -> void:
	broken = true
	for j in _n:
		var at := t + CRACK + absf(j - i) * STEP
		if at < _fall_at[j]:
			_fall_at[j] = at


@rpc("authority", "call_local", "reliable")
func _restore(t: float) -> void:
	broken = false
	_regrow_t = t
	_empty_t = 0.0
	for i in _n:
		_fall_at[i] = INF
		_dropped[i] = false
